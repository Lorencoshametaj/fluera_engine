import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import './models/canvas_branch.dart';
import './models/branch_merge_result.dart';
import '../core/models/canvas_layer.dart';
import '../time_travel/models/time_travel_session.dart';
import '../services/phase2_service_stubs.dart';

/// 🌿 Branching Manager — Git-like branch operations for Creative Branching
///
/// Orchestrates create/switch/delete/flatten operations on canvas branches.
/// Each branch is a lightweight fork pointer + its own session directory.
/// Parent events are never duplicated — loaded by reference at playback time.
///
/// **v1 Scope**: Branches are **private-only** (no RTDB sync).
/// **v2**: Cloud sync via [BranchCloudSyncService] for multi-device + Pro collaboration.
class BranchingManager {
  final FlueraTimeTravelStorage _storage;
  final FlueraBranchCloudSync _cloudSync;

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
    required FlueraTimeTravelStorage storage,
    required FlueraBranchCloudSync cloudSync,
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

      return List.unmodifiable(_branches);
    } catch (e) {
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
      return null;
    }

    final copy = await createChildBranch(
      canvasId: canvasId,
      parentBranchId: original.parentBranchId ?? branchId,
      name: '${original.name} (copy)',
      createdBy: createdBy,
      snapshotLayers: layers,
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


    // 4. Optionally delete the merged source branch
    if (deleteAfterMerge) {
      await deleteBranch(canvasId, sourceBranchId);
    }

    return sourceLayers;
  }

  /// 🔀 3-Way Merge — per-layer diff against common ancestor (fork snapshot)
  ///
  /// **Strategy**:
  /// 1. Load the fork snapshot as common ancestor (base)
  /// 2. Load source and target's latest working states
  /// 3. For each layer:
  ///    - If only source changed → take source's version
  ///    - If only target changed → keep target's version
  ///    - If both changed → mark as conflict (caller decides)
  ///    - If neither changed → keep as-is
  /// 4. New layers from either branch are auto-included
  ///
  /// Returns a [BranchMergeResult] with merged layers + any conflicts.
  Future<BranchMergeResult> mergeBranchThreeWay({
    required String canvasId,
    required String sourceBranchId,
    String targetBranchId = 'br_main',
    bool deleteAfterMerge = false,
  }) async {
    if (sourceBranchId == targetBranchId) {
      return BranchMergeResult(
        mergedLayers: null,
        conflicts: [],
        strategy: 'rejected: self-merge',
      );
    }

    // Validate branches exist
    _branches.firstWhere(
      (b) => b.id == sourceBranchId,
      orElse: () => throw Exception('Source branch $sourceBranchId not found'),
    );
    _branches.firstWhere(
      (b) => b.id == targetBranchId,
      orElse: () => throw Exception('Target branch $targetBranchId not found'),
    );

    // 1. Load common ancestor (fork snapshot of the source branch)
    final baseLayers = await _loadBranchSnapshot(canvasId, sourceBranchId);

    // 2. Load source and target latest states
    final sourceLayers =
        await _loadBranchWorkingState(canvasId, sourceBranchId) ??
        await _loadBranchSnapshot(canvasId, sourceBranchId);

    final targetLayers =
        await _loadBranchWorkingState(canvasId, targetBranchId) ??
        await _loadBranchSnapshot(canvasId, targetBranchId);

    // If no base or source → fall back to simple merge
    if (baseLayers == null || sourceLayers == null) {
      final fallback = await mergeBranch(
        canvasId: canvasId,
        sourceBranchId: sourceBranchId,
        targetBranchId: targetBranchId,
        deleteAfterMerge: deleteAfterMerge,
      );
      return BranchMergeResult(
        mergedLayers: fallback,
        conflicts: [],
        strategy: 'fallback: theirs-wins (no common ancestor)',
      );
    }

    // 3. Build layer maps by ID
    final baseMap = {for (final l in baseLayers) l.id: l};
    final sourceMap = {for (final l in sourceLayers) l.id: l};
    final targetMap = {
      for (final l in (targetLayers ?? <CanvasLayer>[])) l.id: l,
    };

    // 4. Collect all unique layer IDs
    final allIds = <String>{
      ...baseMap.keys,
      ...sourceMap.keys,
      ...targetMap.keys,
    };

    final merged = <CanvasLayer>[];
    final conflicts = <LayerMergeConflict>[];

    for (final layerId in allIds) {
      final base = baseMap[layerId];
      final source = sourceMap[layerId];
      final target = targetMap[layerId];

      if (base == null) {
        // New layer — added by source, target, or both
        if (source != null && target == null) {
          merged.add(source); // New in source only
        } else if (target != null && source == null) {
          merged.add(target); // New in target only
        } else if (source != null && target != null) {
          // Both added a layer with same ID — conflict
          conflicts.add(
            LayerMergeConflict(
              layerId: layerId,
              sourceLayer: source,
              targetLayer: target,
            ),
          );
          merged.add(target); // Default: keep target's version
        }
        continue;
      }

      // Base exists — check modifications
      final sourceChanged = source != null && _layerDiffers(base, source);
      final targetChanged = target != null && _layerDiffers(base, target);

      if (!sourceChanged && !targetChanged) {
        // Neither changed → keep base (or target if available)
        merged.add(target ?? base);
      } else if (sourceChanged && !targetChanged && source != null) {
        // Only source changed → take source's version
        merged.add(source);
      } else if (!sourceChanged && targetChanged && target != null) {
        // Only target changed → keep target's version
        merged.add(target);
      } else if (source != null && target != null) {
        // Both changed → CONFLICT
        conflicts.add(
          LayerMergeConflict(
            layerId: layerId,
            sourceLayer: source,
            targetLayer: target,
            baseLayer: base,
          ),
        );
        // Default resolution: take source (feature branch wins)
        merged.add(source);
      }
    }

    // 5. Save merged result
    await saveBranchWorkingState(canvasId, targetBranchId, merged);

    // 6. Update metadata
    final targetIdx = _branches.indexWhere((b) => b.id == targetBranchId);
    if (targetIdx != -1) {
      final now = DateTime.now().millisecondsSinceEpoch;
      _branches[targetIdx] = _branches[targetIdx].copyWith(lastModifiedMs: now);
      await _saveBranchesMetadata(canvasId);

      if (_cloudSyncEnabled) {
        await _cloudSync.syncBranchMetadata(canvasId, _branches[targetIdx]);
      }
    }

    // 7. Optionally delete source
    if (deleteAfterMerge && conflicts.isEmpty) {
      await deleteBranch(canvasId, sourceBranchId);
    }

    final strategy =
        conflicts.isEmpty
            ? '3-way merge: clean'
            : '3-way merge: ${conflicts.length} conflict(s)';


    return BranchMergeResult(
      mergedLayers: merged,
      conflicts: conflicts,
      strategy: strategy,
    );
  }

  /// Compare two layers to determine if they differ.
  ///
  /// Uses element counts and structural comparison rather than deep equality
  /// to keep the check fast (O(1) for simple cases, O(n) for element lists).
  bool _layerDiffers(CanvasLayer a, CanvasLayer b) {
    if (a.name != b.name) return true;
    if (a.isVisible != b.isVisible) return true;
    if (a.isLocked != b.isLocked) return true;
    if (a.opacity != b.opacity) return true;
    if (a.blendMode != b.blendMode) return true;
    if (a.strokes.length != b.strokes.length) return true;
    if (a.shapes.length != b.shapes.length) return true;
    if (a.texts.length != b.texts.length) return true;
    if (a.images.length != b.images.length) return true;
    return false;
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
      return workingState;
    }

    final forkSnapshot = await _loadBranchSnapshot(canvasId, branchId);
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

    } catch (e) {
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
      return null;
    }


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
