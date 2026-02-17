import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import './models/canvas_branch.dart';
import '../core/models/canvas_layer.dart';
import '../time_travel/models/time_travel_session.dart';
import '../collaboration/nebula_sync_interfaces.dart';

/// 🌿 Branching Manager — Git-like branch operations for Creative Branching
///
/// Orchestrates create/switch/delete/flatten operations on canvas branches.
/// Each branch is a lightweight fork pointer + its own session directory.
/// Parent events are never duplicated — loaded by reference at playback time.
///
/// **v1 Scope**: Branches are **private-only** (no RTDB sync).
/// **v2**: Cloud sync via [BranchCloudSyncService] for multi-device + Pro collaboration.
class BranchingManager {
  final NebulaTimeTravelStorage _storage;
  final NebulaBranchCloudSync _cloudSync;

  /// Whether cloud sync is enabled (Plus/Pro tier)
  bool _cloudSyncEnabled = false;
  bool get cloudSyncEnabled => _cloudSyncEnabled;
  set cloudSyncEnabled(bool value) => _cloudSyncEnabled = value;

  /// Currently active branch (null = main timeline)
  CanvasBranch? _activeBranch;
  CanvasBranch? get activeBranch => _activeBranch;

  /// All branches for the current canvas
  List<CanvasBranch> _branches = [];
  List<CanvasBranch> get branches => List.unmodifiable(_branches);

  BranchingManager({
    required NebulaTimeTravelStorage storage,
    required NebulaBranchCloudSync cloudSync,
  }) : _storage = storage,
       _cloudSync = cloudSync;

  // ============================================================================
  // BRANCH CRUD
  // ============================================================================

  /// 🌿 Ensure a "main" branch exists for a canvas
  ///
  /// Called during recorder initialization. Creates the main branch on first
  /// use with a fixed ID `br_main`. Subsequent calls return the existing one.
  Future<CanvasBranch> ensureMainBranch({
    required String canvasId,
    required String createdBy,
    required List<CanvasLayer> snapshotLayers,
  }) async {
    await loadBranches(canvasId);

    // Check if main branch already exists
    final existing = _branches.where((b) => b.id == 'br_main').firstOrNull;
    if (existing != null) {
      _activeBranch = existing;
      debugPrint('🌿 [BranchingManager] Main branch exists for $canvasId');
      return existing;
    }

    // Create the main branch
    final branch = await createBranch(
      canvasId: canvasId,
      forkPointEventIndex: 0,
      forkPointMs: DateTime.now().millisecondsSinceEpoch,
      name: 'main',
      createdBy: createdBy,
      snapshotLayers: snapshotLayers,
      overrideId: 'br_main',
    );

    _activeBranch = branch;
    debugPrint('🌿 [BranchingManager] Created main branch for $canvasId');
    return branch;
  }

  /// 🌿 Create a child branch from a parent's current state
  ///
  /// Used by the Branch Explorer to fork from any branch. The snapshot
  /// represents the canvas state at the moment of forking.
  Future<CanvasBranch> createChildBranch({
    required String canvasId,
    required String parentBranchId,
    required String name,
    required String createdBy,
    required List<CanvasLayer> snapshotLayers,
  }) async {
    return createBranch(
      canvasId: canvasId,
      forkPointEventIndex: 0, // Not relevant for branch-first model
      forkPointMs: DateTime.now().millisecondsSinceEpoch,
      name: name,
      createdBy: createdBy,
      snapshotLayers: snapshotLayers,
      parentBranchId: parentBranchId,
    );
  }

  /// 🌿 Create a new branch at a specific event index in the timeline
  ///
  /// [canvasId] — root canvas ID
  /// [forkPointEventIndex] — event index where the branch splits off
  /// [forkPointMs] — absolute timestamp (epoch ms) of the fork point
  /// [name] — user-facing display name
  /// [createdBy] — user ID of the creator
  /// [snapshotLayers] — canvas state at [forkPointEventIndex] for fast load
  Future<CanvasBranch> createBranch({
    required String canvasId,
    required int forkPointEventIndex,
    required int forkPointMs,
    required String name,
    required String createdBy,
    required List<CanvasLayer> snapshotLayers,
    String? parentBranchId,
    String? color,
    String? overrideId,
  }) async {
    final branchId =
        overrideId ?? 'br_${DateTime.now().millisecondsSinceEpoch}';

    final branch = CanvasBranch(
      id: branchId,
      canvasId: canvasId,
      parentBranchId: parentBranchId ?? _activeBranch?.id,
      forkPointEventIndex: forkPointEventIndex,
      forkPointMs: forkPointMs,
      name: name,
      createdBy: createdBy,
      createdAt: DateTime.now(),
      color: color,
      lastModifiedMs: DateTime.now().millisecondsSinceEpoch,
    );

    // Create branch directory structure
    final branchPath = await _getBranchPath(canvasId, branchId);
    final branchDir = Directory(branchPath);
    await branchDir.create(recursive: true);

    // Write empty session index for the branch
    final indexFile = File(p.join(branchPath, 'index.json'));
    await indexFile.writeAsString(jsonEncode([]));

    // Save snapshot at fork point for fast branch loading
    await _saveBranchSnapshot(canvasId, branchId, snapshotLayers);

    // Add to branches list and persist
    _branches.add(branch);
    await _saveBranchesMetadata(canvasId);

    // ☁️ Cloud sync: upload metadata + fork snapshot
    if (_cloudSyncEnabled) {
      await _cloudSync.syncBranchMetadata(canvasId, branch);
      await _cloudSync.uploadForkSnapshot(
        canvasId: canvasId,
        branchId: branchId,
        layers: snapshotLayers,
      );
    }

    debugPrint(
      '🌿 [BranchingManager] Created branch "$name" ($branchId) '
      'at event index $forkPointEventIndex',
    );

    return branch;
  }

  /// 📋 Load all branches for a canvas
  Future<List<CanvasBranch>> loadBranches(String canvasId) async {
    final branchesFile = await _getBranchesMetadataPath(canvasId);
    final file = File(branchesFile);

    if (!await file.exists()) {
      _branches = [];
      return _branches;
    }

    try {
      final content = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(content) as List<dynamic>;
      _branches =
          jsonList
              .map(
                (j) =>
                    CanvasBranch.fromJson(Map<String, dynamic>.from(j as Map)),
              )
              .toList();

      // Compute depth levels
      _computeDepthLevels();

      debugPrint(
        '🌿 [BranchingManager] Loaded ${_branches.length} branches '
        'for canvas $canvasId',
      );
      return List.unmodifiable(_branches);
    } catch (e) {
      debugPrint('🌿 [BranchingManager] Error loading branches: $e');
      _branches = [];
      return _branches;
    }
  }

  /// ✏️ Rename a branch
  Future<void> renameBranch(
    String canvasId,
    String branchId,
    String newName,
  ) async {
    final index = _branches.indexWhere((b) => b.id == branchId);
    if (index == -1) return;

    _branches[index] = _branches[index].copyWith(name: newName);
    await _saveBranchesMetadata(canvasId);

    // ☁️ Cloud sync: update metadata
    if (_cloudSyncEnabled) {
      await _cloudSync.syncBranchMetadata(canvasId, _branches[index]);
    }

    debugPrint('🌿 [BranchingManager] Renamed branch $branchId to "$newName"');
  }

  /// 📝 Update a branch's description
  Future<void> updateBranchDescription(
    String canvasId,
    String branchId,
    String? description,
  ) async {
    final index = _branches.indexWhere((b) => b.id == branchId);
    if (index == -1) return;

    _branches[index] = _branches[index].copyWith(
      description: description,
      clearDescription: description == null,
    );
    await _saveBranchesMetadata(canvasId);

    // ☁️ Cloud sync: update metadata
    if (_cloudSyncEnabled) {
      await _cloudSync.syncBranchMetadata(canvasId, _branches[index]);
    }

    debugPrint(
      '🌿 [BranchingManager] Updated description for branch $branchId',
    );
  }

  /// 📋 Duplicate a branch — clones its working state into a new child branch
  Future<CanvasBranch?> duplicateBranch({
    required String canvasId,
    required String branchId,
    required String createdBy,
  }) async {
    final original = _branches.firstWhere(
      (b) => b.id == branchId,
      orElse: () => throw Exception('Branch $branchId not found'),
    );

    // Load the branch's latest working state (or fork snapshot as fallback)
    final layers =
        await _loadBranchWorkingState(canvasId, branchId) ??
        await _loadBranchSnapshot(canvasId, branchId);

    if (layers == null) {
      debugPrint(
        '❌ [BranchingManager] Cannot duplicate: no data for $branchId',
      );
      return null;
    }

    final copy = await createChildBranch(
      canvasId: canvasId,
      parentBranchId: original.parentBranchId ?? branchId,
      name: '${original.name} (copy)',
      createdBy: createdBy,
      snapshotLayers: layers,
    );

    debugPrint(
      '🌿 [BranchingManager] Duplicated branch "${original.name}" → "${copy.name}"',
    );

    return copy;
  }

  /// 🔀 Merge a branch into another — overwrites target's canvas with source state
  ///
  /// **Strategy**: Full layer replacement ("theirs wins"). The source branch's
  /// latest working state becomes the target's working state. This is the
  /// simplest and most intuitive model for a creative tool — no per-stroke merge.
  ///
  /// Works at any level of the branch tree (child → parent), just like Git.
  ///
  /// **Sync flow**:
  /// 1. Load source branch working state (or fork snapshot as fallback)
  /// 2. Save as target's working state → triggers debounced cloud upload
  /// 3. Update target branch metadata (lastModifiedMs) → Firestore sync
  /// 4. Optionally delete the source branch (+ cloud cleanup)
  ///
  /// Returns the merged layers, or null if the merge failed.
  Future<List<CanvasLayer>?> mergeBranch({
    required String canvasId,
    required String sourceBranchId,
    String targetBranchId = 'br_main',
    bool deleteAfterMerge = false,
  }) async {
    if (sourceBranchId == targetBranchId) {
      debugPrint('❌ [BranchingManager] Cannot merge a branch into itself');
      return null;
    }

    final source = _branches.firstWhere(
      (b) => b.id == sourceBranchId,
      orElse: () => throw Exception('Source branch $sourceBranchId not found'),
    );
    final target = _branches.firstWhere(
      (b) => b.id == targetBranchId,
      orElse: () => throw Exception('Target branch $targetBranchId not found'),
    );

    // 1. Load the source branch's latest working state
    final sourceLayers =
        await _loadBranchWorkingState(canvasId, sourceBranchId) ??
        await _loadBranchSnapshot(canvasId, sourceBranchId);

    if (sourceLayers == null || sourceLayers.isEmpty) {
      debugPrint(
        '❌ [BranchingManager] Cannot merge: no data for branch '
        '"${source.name}" ($sourceBranchId)',
      );
      return null;
    }

    // 2. Save source layers as target's working state
    await saveBranchWorkingState(canvasId, targetBranchId, sourceLayers);

    // 3. Update target branch metadata (timestamp for LWW)
    final targetIdx = _branches.indexWhere((b) => b.id == targetBranchId);
    if (targetIdx != -1) {
      final now = DateTime.now().millisecondsSinceEpoch;
      _branches[targetIdx] = _branches[targetIdx].copyWith(lastModifiedMs: now);
      await _saveBranchesMetadata(canvasId);

      // ☁️ Cloud sync: push updated target metadata
      if (_cloudSyncEnabled) {
        await _cloudSync.syncBranchMetadata(canvasId, _branches[targetIdx]);
      }
    }

    debugPrint(
      '🔀 [BranchingManager] Merged "${source.name}" ($sourceBranchId) '
      '→ "${target.name}" ($targetBranchId) '
      '(${sourceLayers.length} layers)',
    );

    // 4. Optionally delete the merged source branch
    if (deleteAfterMerge) {
      await deleteBranch(canvasId, sourceBranchId);
      debugPrint(
        '🔀 [BranchingManager] Deleted merged branch "${source.name}"',
      );
    }

    return sourceLayers;
  }

  /// �🗑️ Delete a branch and all its data
  ///
  /// Also deletes child branches (cascade) to prevent orphaned forks.
  Future<void> deleteBranch(String canvasId, String branchId) async {
    // Find child branches (recursive cascade delete)
    final childIds = _findChildBranchIds(branchId);
    final allToDelete = [branchId, ...childIds];

    for (final id in allToDelete) {
      // Delete branch directory
      final branchPath = await _getBranchPath(canvasId, id);
      final branchDir = Directory(branchPath);
      if (await branchDir.exists()) {
        await branchDir.delete(recursive: true);
      }

      // ☁️ Cloud sync: delete remote data
      if (_cloudSyncEnabled) {
        await _cloudSync.deleteBranchCloud(canvasId, id);
      }

      // Remove from in-memory list
      _branches.removeWhere((b) => b.id == id);
    }

    // Clear active branch if it was deleted
    if (allToDelete.contains(_activeBranch?.id)) {
      _activeBranch = null;
    }

    await _saveBranchesMetadata(canvasId);

    debugPrint(
      '🌿 [BranchingManager] Deleted branch $branchId '
      '(+${childIds.length} children)',
    );
  }

  // ============================================================================
  // BRANCH SWITCHING
  // ============================================================================

  /// 🔀 Switch to a specific branch (or main if branchId is null)
  ///
  /// Returns the branch's latest working state (or fork snapshot as fallback).
  /// The caller should then activate the branch's recording context.
  Future<List<CanvasLayer>?> switchToBranch(
    String canvasId,
    String? branchId,
  ) async {
    if (branchId == null) {
      // Switch to main
      _activeBranch = null;
      debugPrint('🌿 [BranchingManager] Switched to main timeline');
      return null; // Caller should reload main canvas state
    }

    final branch = _branches.firstWhere(
      (b) => b.id == branchId,
      orElse: () => throw Exception('Branch $branchId not found'),
    );

    _activeBranch = branch;

    // Load working state first (latest saved state), fallback to fork snapshot
    final workingState = await _loadBranchWorkingState(canvasId, branchId);
    if (workingState != null) {
      debugPrint(
        '🌿 [BranchingManager] Switched to branch "${branch.name}" '
        '($branchId) — loaded working state (${workingState.length} layers)',
      );
      return workingState;
    }

    final forkSnapshot = await _loadBranchSnapshot(canvasId, branchId);
    debugPrint(
      '🌿 [BranchingManager] Switched to branch "${branch.name}" '
      '($branchId) — loaded fork snapshot',
    );
    return forkSnapshot;
  }

  /// 💾 Save the current canvas state as the branch's working state
  ///
  /// Called when switching away from a branch to preserve modifications.
  Future<void> saveBranchWorkingState(
    String canvasId,
    String branchId,
    List<CanvasLayer> layers,
  ) async {
    final branchPath = await _getBranchPath(canvasId, branchId);
    final snapshotDir = Directory(p.join(branchPath, 'snapshots'));
    await snapshotDir.create(recursive: true);

    final workingFile = File(p.join(snapshotDir.path, 'working_state.json'));
    final layersJson = layers.map((l) => l.toJson()).toList();
    await workingFile.writeAsString(jsonEncode(layersJson));

    // ☁️ Cloud sync: debounced snapshot upload
    if (_cloudSyncEnabled) {
      final branch = _branches.firstWhere(
        (b) => b.id == branchId,
        orElse: () => throw Exception('Branch $branchId not found'),
      );
      _cloudSync.scheduleDebouncedUpload(
        canvasId: canvasId,
        branch: branch,
        layers: layers,
        onUploaded: (updated) {
          // Update in-memory branch with new version
          final idx = _branches.indexWhere((b) => b.id == branchId);
          if (idx != -1) {
            _branches[idx] = updated;
            _saveBranchesMetadata(canvasId);
          }
        },
      );
    }

    debugPrint(
      '🌿 [BranchingManager] Saved working state '
      '(${layers.length} layers) for branch $branchId',
    );
  }

  /// 🔄 Full bidirectional sync with cloud
  ///
  /// Called on canvas open for shared canvases. Handles:
  /// - Uploading local-only branches
  /// - Downloading remote-only branches
  /// - Resolving version conflicts (LWW)
  Future<void> syncWithCloud({
    required String canvasId,
    required Future<List<CanvasLayer>> Function(String branchId) getLocalLayers,
  }) async {
    if (!_cloudSyncEnabled) return;

    try {
      debugPrint('🔄 [BranchingManager] Starting cloud sync for $canvasId');

      final mergedBranches = await _cloudSync.syncWithCloud(
        canvasId: canvasId,
        localBranches: _branches,
        getLocalLayers: getLocalLayers,
        saveLocalSnapshot: (branchId, layers) async {
          await saveBranchWorkingState(canvasId, branchId, layers);
        },
      );

      _branches = mergedBranches;
      _computeDepthLevels();
      await _saveBranchesMetadata(canvasId);

      debugPrint(
        '🔄 [BranchingManager] Cloud sync complete: '
        '${_branches.length} branches',
      );
    } catch (e) {
      debugPrint('❌ [BranchingManager] Cloud sync failed: $e');
    }
  }

  /// 🔄 Upload TT sessions for a branch (called on flush)
  Future<void> uploadBranchTTSessions(String canvasId, String branchId) async {
    if (!_cloudSyncEnabled) return;

    final branch = _branches.firstWhere(
      (b) => b.id == branchId,
      orElse: () => throw Exception('Branch $branchId not found'),
    );

    final newCount = await _cloudSync.uploadTTSessions(
      canvasId: canvasId,
      branchId: branchId,
      alreadySyncedCount: branch.ttSessionCount,
    );

    if (newCount > 0) {
      final idx = _branches.indexWhere((b) => b.id == branchId);
      if (idx != -1) {
        _branches[idx] = _branches[idx].copyWith(
          ttSessionCount: branch.ttSessionCount + newCount,
        );
        await _saveBranchesMetadata(canvasId);
      }
    }
  }

  /// 🔄 Download remote TT sessions for a branch (lazy, on-demand)
  Future<int> downloadBranchTTSessions(String canvasId, String branchId) async {
    if (!_cloudSyncEnabled) return 0;
    return _cloudSync.downloadTTSessions(
      canvasId: canvasId,
      branchId: branchId,
    );
  }

  // ============================================================================
  // COMPACTION PROTECTION
  // ============================================================================

  /// 🛡️ Check if parent history can be compacted
  ///
  /// Returns false if any branch depends on events that would be lost.
  /// The user must delete or flatten branches first.
  bool canCompactHistory(String canvasId) {
    return _branches.isEmpty;
  }

  /// 🔄 Flatten a branch — returns its fully composed layer state
  ///
  /// Loads the branch's latest working state (which includes all edits),
  /// falling back to the fork snapshot if no working state exists.
  /// The result can be used to create a new independent canvas.
  Future<List<CanvasLayer>?> flattenBranch(
    String canvasId,
    String branchId,
  ) async {
    // Prefer working state (includes all edits), fallback to fork snapshot
    final layers =
        await _loadBranchWorkingState(canvasId, branchId) ??
        await _loadBranchSnapshot(canvasId, branchId);

    if (layers == null) {
      debugPrint('❌ [BranchingManager] Cannot flatten: no data for $branchId');
      return null;
    }

    debugPrint(
      '🌿 [BranchingManager] Flattened branch $branchId '
      '(${layers.length} layers)',
    );

    return layers;
  }

  // ============================================================================
  // BRANCH TREE
  // ============================================================================

  /// 🌳 Get the branch tree for the Branch Explorer UI
  ///
  /// Returns branches sorted for tree display:
  /// - Main children first (parentBranchId == null), sorted by creation time
  /// - Sub-branches nested under their parents
  List<CanvasBranch> getBranchTree() {
    _computeDepthLevels();

    // Sort: root branches first, then by creation time within each level
    final sorted = List<CanvasBranch>.from(_branches);
    sorted.sort((a, b) {
      if (a.depthLevel != b.depthLevel) {
        return a.depthLevel.compareTo(b.depthLevel);
      }
      return a.createdAt.compareTo(b.createdAt);
    });

    // Reorder for tree display: parent followed by its children
    final result = <CanvasBranch>[];
    final visited = <String>{};

    void addWithChildren(String? parentId) {
      for (final branch in sorted) {
        if (branch.parentBranchId == parentId && !visited.contains(branch.id)) {
          visited.add(branch.id);
          result.add(branch);
          addWithChildren(branch.id);
        }
      }
    }

    // Start with root branches (forked from main)
    addWithChildren(null);

    return result;
  }

  /// Check if a specific branch has children
  bool hasChildren(String branchId) {
    return _branches.any((b) => b.parentBranchId == branchId);
  }

  // ============================================================================
  // STORAGE HELPERS
  // ============================================================================

  /// Get the storage path for a branch's sessions
  Future<String> getBranchStoragePath(String canvasId, String branchId) async {
    return _getBranchPath(canvasId, branchId);
  }

  /// Load branch session index
  Future<List<TimeTravelSession>> loadBranchSessions(
    String canvasId,
    String branchId,
  ) async {
    final branchPath = await _getBranchPath(canvasId, branchId);
    final indexFile = File(p.join(branchPath, 'index.json'));

    if (!await indexFile.exists()) return [];

    try {
      final content = await indexFile.readAsString();
      final List<dynamic> jsonList = jsonDecode(content) as List<dynamic>;
      return jsonList
          .map(
            (j) =>
                TimeTravelSession.fromJson(Map<String, dynamic>.from(j as Map)),
          )
          .toList();
    } catch (e) {
      debugPrint('🌿 [BranchingManager] Error loading branch sessions: $e');
      return [];
    }
  }

  // ============================================================================
  // PRIVATE HELPERS
  // ============================================================================

  Future<String> _getBranchPath(String canvasId, String branchId) async {
    final ttPath = await _storage.getTimeTravelPathForCanvas(canvasId);
    return p.join(ttPath, 'branches', branchId);
  }

  Future<String> _getBranchesMetadataPath(String canvasId) async {
    final ttPath = await _storage.getTimeTravelPathForCanvas(canvasId);
    return p.join(ttPath, 'branches.json');
  }

  Future<void> _saveBranchesMetadata(String canvasId) async {
    final path = await _getBranchesMetadataPath(canvasId);
    final file = File(path);
    await file.parent.create(recursive: true);
    final jsonList = _branches.map((b) => b.toJson()).toList();
    await file.writeAsString(jsonEncode(jsonList));
  }

  Future<void> _saveBranchSnapshot(
    String canvasId,
    String branchId,
    List<CanvasLayer> layers,
  ) async {
    final branchPath = await _getBranchPath(canvasId, branchId);
    final snapshotDir = Directory(p.join(branchPath, 'snapshots'));
    await snapshotDir.create(recursive: true);

    final snapshotFile = File(p.join(snapshotDir.path, 'fork_snapshot.json'));
    final layersJson = layers.map((l) => l.toJson()).toList();
    await snapshotFile.writeAsString(jsonEncode(layersJson));

    debugPrint(
      '🌿 [BranchingManager] Saved fork snapshot '
      '(${layers.length} layers) for branch $branchId',
    );
  }

  Future<List<CanvasLayer>?> _loadBranchSnapshot(
    String canvasId,
    String branchId,
  ) async {
    final branchPath = await _getBranchPath(canvasId, branchId);
    final snapshotFile = File(
      p.join(branchPath, 'snapshots', 'fork_snapshot.json'),
    );

    if (!await snapshotFile.exists()) return null;

    try {
      final content = await snapshotFile.readAsString();
      final List<dynamic> jsonList = jsonDecode(content) as List<dynamic>;
      return jsonList
          .map((j) => CanvasLayer.fromJson(Map<String, dynamic>.from(j as Map)))
          .toList();
    } catch (e) {
      debugPrint('🌿 [BranchingManager] Error loading snapshot: $e');
      return null;
    }
  }

  Future<List<CanvasLayer>?> _loadBranchWorkingState(
    String canvasId,
    String branchId,
  ) async {
    final branchPath = await _getBranchPath(canvasId, branchId);
    final workingFile = File(
      p.join(branchPath, 'snapshots', 'working_state.json'),
    );

    if (!await workingFile.exists()) return null;

    try {
      final content = await workingFile.readAsString();
      final List<dynamic> jsonList = jsonDecode(content) as List<dynamic>;
      return jsonList
          .map((j) => CanvasLayer.fromJson(Map<String, dynamic>.from(j as Map)))
          .toList();
    } catch (e) {
      debugPrint('🌿 [BranchingManager] Error loading working state: $e');
      return null;
    }
  }

  void _computeDepthLevels() {
    for (final branch in _branches) {
      int depth = 0;
      String? currentParent = branch.parentBranchId;
      while (currentParent != null) {
        depth++;
        final parent = _branches.where((b) => b.id == currentParent);
        currentParent = parent.isNotEmpty ? parent.first.parentBranchId : null;
      }
      branch.depthLevel = depth;
    }
  }

  List<String> _findChildBranchIds(String parentId) {
    final children = <String>[];
    for (final branch in _branches) {
      if (branch.parentBranchId == parentId) {
        children.add(branch.id);
        children.addAll(_findChildBranchIds(branch.id));
      }
    }
    return children;
  }
}
