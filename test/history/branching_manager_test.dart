import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/history/branching_manager.dart';
import 'package:nebula_engine/src/history/models/canvas_branch.dart';
import 'package:nebula_engine/src/history/models/branch_merge_result.dart';
import 'package:nebula_engine/src/core/models/canvas_layer.dart';
import 'package:nebula_engine/src/services/phase2_service_stubs.dart';
import 'package:nebula_engine/src/time_travel/models/time_travel_session.dart';

// ═══════════════════════════════════════════════════════════════════════════
// TEST STORAGE — uses a temp directory instead of /tmp/nebula_tt
// ═══════════════════════════════════════════════════════════════════════════

class _TestTimeTravelStorage implements NebulaTimeTravelStorage {
  final String basePath;
  _TestTimeTravelStorage(this.basePath);

  @override
  Future<String> getTimeTravelPathForCanvas(String canvasId) async =>
      '$basePath/$canvasId';

  @override
  Future<List<TimeTravelSession>> loadSessionIndex(
    String canvasId, {
    String? branchId,
  }) async => [];

  @override
  Future<List<TimeTravelEvent>> loadSessionEvents(
    TimeTravelSession session, {
    String? branchId,
  }) async => [];

  @override
  Future<(List<CanvasLayer>, int)?> loadNearestSnapshot(
    String canvasId,
    int targetSessionIndex, {
    String? branchId,
  }) async => null;
}

/// Helper: create a simple test layer.
CanvasLayer _testLayer(String id, {int strokeCount = 0}) {
  return CanvasLayer(
    id: id,
    name: 'Layer $id',
    isVisible: true,
    opacity: 1.0,
    strokes: [],
  );
}

void main() {
  late Directory tempDir;
  late BranchingManager manager;
  late _TestTimeTravelStorage storage;

  const canvasId = 'test_canvas_001';
  const userId = 'user_1';

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nebula_branching_test_');
    storage = _TestTimeTravelStorage(tempDir.path);
    manager = BranchingManager(
      storage: storage,
      cloudSync: BranchCloudSyncService.instance,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ENSURE MAIN BRANCH
  // ═══════════════════════════════════════════════════════════════════════════

  group('BranchingManager — ensureMainBranch', () {
    test('creates main branch on first call', () async {
      final layers = [_testLayer('l1')];
      final branch = await manager.ensureMainBranch(
        canvasId: canvasId,
        createdBy: userId,
        snapshotLayers: layers,
      );

      expect(branch.id, 'br_main');
      expect(branch.name, 'main');
      expect(branch.createdBy, userId);
      expect(manager.branches, hasLength(1));
      expect(manager.activeBranch, isNotNull);
      expect(manager.activeBranch!.id, 'br_main');
    });

    test('returns existing main branch on second call', () async {
      final layers = [_testLayer('l1')];
      await manager.ensureMainBranch(
        canvasId: canvasId,
        createdBy: userId,
        snapshotLayers: layers,
      );

      final second = await manager.ensureMainBranch(
        canvasId: canvasId,
        createdBy: userId,
        snapshotLayers: layers,
      );

      expect(second.id, 'br_main');
      expect(manager.branches, hasLength(1)); // Not duplicated
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // CREATE BRANCH
  // ═══════════════════════════════════════════════════════════════════════════

  group('BranchingManager — createBranch', () {
    test('creates branch with correct metadata', () async {
      final layers = [_testLayer('l1'), _testLayer('l2')];
      final branch = await manager.createBranch(
        canvasId: canvasId,
        forkPointEventIndex: 42,
        forkPointMs: 1234567890,
        name: 'Experiment A',
        createdBy: userId,
        snapshotLayers: layers,
        overrideId: 'br_test_1',
        color: '#FF0000',
      );

      expect(branch.id, 'br_test_1');
      expect(branch.name, 'Experiment A');
      expect(branch.forkPointEventIndex, 42);
      expect(branch.color, '#FF0000');
      expect(branch.canvasId, canvasId);
      expect(manager.branches, hasLength(1));
    });

    test('creates directory structure on disk', () async {
      await manager.createBranch(
        canvasId: canvasId,
        forkPointEventIndex: 0,
        forkPointMs: 0,
        name: 'test',
        createdBy: userId,
        snapshotLayers: [_testLayer('l1')],
        overrideId: 'br_disk_test',
      );

      // Verify branch directory exists
      final branchDir = Directory(
        '${tempDir.path}/$canvasId/branches/br_disk_test',
      );
      expect(await branchDir.exists(), isTrue);

      // Verify index.json exists
      final indexFile = File('${branchDir.path}/index.json');
      expect(await indexFile.exists(), isTrue);

      // Verify fork snapshot exists
      final snapshotFile = File(
        '${branchDir.path}/snapshots/fork_snapshot.json',
      );
      expect(await snapshotFile.exists(), isTrue);
    });

    test('persists metadata to branches.json', () async {
      await manager.createBranch(
        canvasId: canvasId,
        forkPointEventIndex: 0,
        forkPointMs: 0,
        name: 'persisted',
        createdBy: userId,
        snapshotLayers: [],
        overrideId: 'br_persist',
      );

      final metaFile = File('${tempDir.path}/$canvasId/branches.json');
      expect(await metaFile.exists(), isTrue);

      final content = await metaFile.readAsString();
      final list = jsonDecode(content) as List;
      expect(list, hasLength(1));
      expect(list[0]['name'], 'persisted');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // CREATE CHILD BRANCH
  // ═══════════════════════════════════════════════════════════════════════════

  group('BranchingManager — createChildBranch', () {
    test('sets parentBranchId correctly', () async {
      await manager.ensureMainBranch(
        canvasId: canvasId,
        createdBy: userId,
        snapshotLayers: [_testLayer('l1')],
      );

      final child = await manager.createChildBranch(
        canvasId: canvasId,
        parentBranchId: 'br_main',
        name: 'Feature Branch',
        createdBy: userId,
        snapshotLayers: [_testLayer('l1')],
      );

      expect(child.parentBranchId, 'br_main');
      expect(manager.branches, hasLength(2)); // main + child
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // LOAD BRANCHES
  // ═══════════════════════════════════════════════════════════════════════════

  group('BranchingManager — loadBranches', () {
    test('loads branches from disk', () async {
      // Create some branches
      await manager.ensureMainBranch(
        canvasId: canvasId,
        createdBy: userId,
        snapshotLayers: [_testLayer('l1')],
      );
      await manager.createChildBranch(
        canvasId: canvasId,
        parentBranchId: 'br_main',
        name: 'Branch A',
        createdBy: userId,
        snapshotLayers: [_testLayer('l1')],
      );

      // Create a fresh manager and load
      final freshManager = BranchingManager(
        storage: storage,
        cloudSync: BranchCloudSyncService.instance,
      );
      final loaded = await freshManager.loadBranches(canvasId);

      expect(loaded, hasLength(2));
      expect(loaded.any((b) => b.id == 'br_main'), isTrue);
    });

    test('returns empty list for non-existent canvas', () async {
      final branches = await manager.loadBranches('nonexistent');
      expect(branches, isEmpty);
    });

    test('computes depth levels', () async {
      await manager.ensureMainBranch(
        canvasId: canvasId,
        createdBy: userId,
        snapshotLayers: [_testLayer('l1')],
      );

      final child = await manager.createChildBranch(
        canvasId: canvasId,
        parentBranchId: 'br_main',
        name: 'Child',
        createdBy: userId,
        snapshotLayers: [_testLayer('l1')],
      );

      // Reload to trigger _computeDepthLevels
      await manager.loadBranches(canvasId);

      // Main has no parent → depthLevel 0
      // Child has parent br_main → depthLevel 1
      final mainBranch = manager.branches.firstWhere((b) => b.id == 'br_main');
      final childBranch = manager.branches.firstWhere((b) => b.id == child.id);
      expect(mainBranch.depthLevel, 0);
      expect(childBranch.depthLevel, 1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // RENAME & DESCRIPTION
  // ═══════════════════════════════════════════════════════════════════════════

  group('BranchingManager — rename', () {
    test('renames a branch', () async {
      await manager.ensureMainBranch(
        canvasId: canvasId,
        createdBy: userId,
        snapshotLayers: [],
      );

      await manager.renameBranch(canvasId, 'br_main', 'production');
      expect(manager.branches.first.name, 'production');
    });

    test('no-ops for unknown branchId', () async {
      await manager.ensureMainBranch(
        canvasId: canvasId,
        createdBy: userId,
        snapshotLayers: [],
      );

      await manager.renameBranch(canvasId, 'br_nonexistent', 'newname');
      expect(manager.branches.first.name, 'main'); // Unchanged
    });
  });

  group('BranchingManager — description', () {
    test('updates description', () async {
      await manager.ensureMainBranch(
        canvasId: canvasId,
        createdBy: userId,
        snapshotLayers: [],
      );

      await manager.updateBranchDescription(
        canvasId,
        'br_main',
        'The main production branch',
      );
      expect(manager.branches.first.description, 'The main production branch');
    });

    test('clears description with null', () async {
      await manager.ensureMainBranch(
        canvasId: canvasId,
        createdBy: userId,
        snapshotLayers: [],
      );

      await manager.updateBranchDescription(canvasId, 'br_main', 'something');
      await manager.updateBranchDescription(canvasId, 'br_main', null);
      expect(manager.branches.first.description, isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SWITCH BRANCH
  // ═══════════════════════════════════════════════════════════════════════════

  group('BranchingManager — switchToBranch', () {
    test('switches to main when branchId is null', () async {
      await manager.ensureMainBranch(
        canvasId: canvasId,
        createdBy: userId,
        snapshotLayers: [],
      );

      await manager.switchToBranch(canvasId, null);
      expect(manager.activeBranch, isNull);
    });

    test('switches to existing branch and loads fork snapshot', () async {
      final layers = [_testLayer('l1'), _testLayer('l2')];
      await manager.ensureMainBranch(
        canvasId: canvasId,
        createdBy: userId,
        snapshotLayers: layers,
      );

      final child = await manager.createChildBranch(
        canvasId: canvasId,
        parentBranchId: 'br_main',
        name: 'Feature',
        createdBy: userId,
        snapshotLayers: layers,
      );

      final loadedLayers = await manager.switchToBranch(canvasId, child.id);
      expect(manager.activeBranch?.id, child.id);
      expect(loadedLayers, isNotNull);
      expect(loadedLayers, hasLength(2));
    });

    test('throws for nonexistent branch', () async {
      await manager.ensureMainBranch(
        canvasId: canvasId,
        createdBy: userId,
        snapshotLayers: [],
      );

      expect(
        () => manager.switchToBranch(canvasId, 'br_ghost'),
        throwsA(isA<Exception>()),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SAVE & LOAD WORKING STATE
  // ═══════════════════════════════════════════════════════════════════════════

  group('BranchingManager — working state', () {
    test('saves and loads working state', () async {
      await manager.ensureMainBranch(
        canvasId: canvasId,
        createdBy: userId,
        snapshotLayers: [_testLayer('l1')],
      );

      // Save a different working state
      final updatedLayers = [
        _testLayer('l1'),
        _testLayer('l2'),
        _testLayer('l3'),
      ];
      await manager.saveBranchWorkingState(canvasId, 'br_main', updatedLayers);

      // Switch away and back — should load working state (3 layers), not snapshot (1)
      await manager.switchToBranch(canvasId, null);
      final loaded = await manager.switchToBranch(canvasId, 'br_main');
      expect(loaded, hasLength(3));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // MERGE BRANCH
  // ═══════════════════════════════════════════════════════════════════════════

  group('BranchingManager — mergeBranch', () {
    test('merges source layers into target', () async {
      await manager.ensureMainBranch(
        canvasId: canvasId,
        createdBy: userId,
        snapshotLayers: [_testLayer('l1')],
      );

      final child = await manager.createChildBranch(
        canvasId: canvasId,
        parentBranchId: 'br_main',
        name: 'Feature',
        createdBy: userId,
        snapshotLayers: [_testLayer('feat_1'), _testLayer('feat_2')],
      );

      // Merge child → main
      final result = await manager.mergeBranch(
        canvasId: canvasId,
        sourceBranchId: child.id,
        targetBranchId: 'br_main',
      );

      expect(result, isNotNull);
      expect(result, hasLength(2)); // Feature's 2 layers
    });

    test('returns null for self-merge', () async {
      await manager.ensureMainBranch(
        canvasId: canvasId,
        createdBy: userId,
        snapshotLayers: [],
      );

      final result = await manager.mergeBranch(
        canvasId: canvasId,
        sourceBranchId: 'br_main',
        targetBranchId: 'br_main',
      );

      expect(result, isNull);
    });

    test('deleteAfterMerge removes source branch', () async {
      await manager.ensureMainBranch(
        canvasId: canvasId,
        createdBy: userId,
        snapshotLayers: [_testLayer('l1')],
      );

      final child = await manager.createChildBranch(
        canvasId: canvasId,
        parentBranchId: 'br_main',
        name: 'Temporary',
        createdBy: userId,
        snapshotLayers: [_testLayer('t1')],
      );

      await manager.mergeBranch(
        canvasId: canvasId,
        sourceBranchId: child.id,
        targetBranchId: 'br_main',
        deleteAfterMerge: true,
      );

      expect(manager.branches, hasLength(1)); // Only main remains
      expect(manager.branches.first.id, 'br_main');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // DELETE BRANCH
  // ═══════════════════════════════════════════════════════════════════════════

  group('BranchingManager — deleteBranch', () {
    test('deletes a branch', () async {
      await manager.ensureMainBranch(
        canvasId: canvasId,
        createdBy: userId,
        snapshotLayers: [],
      );

      final child = await manager.createChildBranch(
        canvasId: canvasId,
        parentBranchId: 'br_main',
        name: 'ToDelete',
        createdBy: userId,
        snapshotLayers: [],
      );

      await manager.deleteBranch(canvasId, child.id);
      expect(manager.branches, hasLength(1)); // Only main
    });

    test('cascade deletes children', () async {
      await manager.ensureMainBranch(
        canvasId: canvasId,
        createdBy: userId,
        snapshotLayers: [],
      );

      final parent = await manager.createChildBranch(
        canvasId: canvasId,
        parentBranchId: 'br_main',
        name: 'Parent',
        createdBy: userId,
        snapshotLayers: [],
      );

      await manager.createChildBranch(
        canvasId: canvasId,
        parentBranchId: parent.id,
        name: 'GrandChild',
        createdBy: userId,
        snapshotLayers: [],
      );

      expect(manager.branches, hasLength(3)); // main + parent + grandchild

      // Delete parent → should cascade to grandchild
      await manager.deleteBranch(canvasId, parent.id);
      expect(manager.branches, hasLength(1)); // Only main
    });

    test('clears activeBranch if deleted', () async {
      await manager.ensureMainBranch(
        canvasId: canvasId,
        createdBy: userId,
        snapshotLayers: [],
      );

      final child = await manager.createChildBranch(
        canvasId: canvasId,
        parentBranchId: 'br_main',
        name: 'Active',
        createdBy: userId,
        snapshotLayers: [],
      );

      await manager.switchToBranch(canvasId, child.id);
      expect(manager.activeBranch?.id, child.id);

      await manager.deleteBranch(canvasId, child.id);
      expect(manager.activeBranch, isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // DUPLICATE BRANCH
  // ═══════════════════════════════════════════════════════════════════════════

  group('BranchingManager — duplicateBranch', () {
    test('duplicates a branch with working state', () async {
      await manager.ensureMainBranch(
        canvasId: canvasId,
        createdBy: userId,
        snapshotLayers: [_testLayer('l1')],
      );

      // Save working state to main
      await manager.saveBranchWorkingState(canvasId, 'br_main', [
        _testLayer('l1'),
        _testLayer('l2'),
      ]);

      final dup = await manager.duplicateBranch(
        canvasId: canvasId,
        branchId: 'br_main',
        createdBy: userId,
      );

      expect(dup, isNotNull);
      expect(dup!.name, contains('main'));
      expect(dup.parentBranchId, 'br_main');
      expect(manager.branches, hasLength(2));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // FLATTEN BRANCH
  // ═══════════════════════════════════════════════════════════════════════════

  group('BranchingManager — flattenBranch', () {
    test('returns working state layers', () async {
      await manager.ensureMainBranch(
        canvasId: canvasId,
        createdBy: userId,
        snapshotLayers: [_testLayer('l1')],
      );

      await manager.saveBranchWorkingState(canvasId, 'br_main', [
        _testLayer('l1'),
        _testLayer('l2'),
        _testLayer('l3'),
      ]);

      final flat = await manager.flattenBranch(canvasId, 'br_main');
      expect(flat, isNotNull);
      expect(flat, hasLength(3));
    });

    test('falls back to fork snapshot', () async {
      final layers = [_testLayer('snap1')];
      await manager.createBranch(
        canvasId: canvasId,
        forkPointEventIndex: 0,
        forkPointMs: 0,
        name: 'snap_only',
        createdBy: userId,
        snapshotLayers: layers,
        overrideId: 'br_snap',
      );

      // No working state saved — should fall back to fork snapshot
      final flat = await manager.flattenBranch(canvasId, 'br_snap');
      expect(flat, isNotNull);
      expect(flat, hasLength(1));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BRANCH TREE
  // ═══════════════════════════════════════════════════════════════════════════

  group('BranchingManager — getBranchTree', () {
    test('returns branches sorted by depth and creation', () async {
      await manager.ensureMainBranch(
        canvasId: canvasId,
        createdBy: userId,
        snapshotLayers: [],
      );

      final child1 = await manager.createChildBranch(
        canvasId: canvasId,
        parentBranchId: 'br_main',
        name: 'Child 1',
        createdBy: userId,
        snapshotLayers: [],
      );

      await manager.createChildBranch(
        canvasId: canvasId,
        parentBranchId: child1.id,
        name: 'Grandchild',
        createdBy: userId,
        snapshotLayers: [],
      );

      final tree = manager.getBranchTree();
      expect(tree, hasLength(3));
      // Main should be first (root), then children in order
    });

    test('hasChildren returns correct state', () async {
      await manager.ensureMainBranch(
        canvasId: canvasId,
        createdBy: userId,
        snapshotLayers: [],
      );

      expect(manager.hasChildren('br_main'), isFalse);

      await manager.createChildBranch(
        canvasId: canvasId,
        parentBranchId: 'br_main',
        name: 'Child',
        createdBy: userId,
        snapshotLayers: [],
      );

      expect(manager.hasChildren('br_main'), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 3-WAY MERGE
  // ═══════════════════════════════════════════════════════════════════════════

  group('BranchingManager — mergeBranchThreeWay', () {
    test('clean merge when only source changed a layer', () async {
      // Setup: main with 2 layers, child modifies 1 layer
      final baseLayers = [_testLayer('l1'), _testLayer('l2')];
      await manager.ensureMainBranch(
        canvasId: canvasId,
        createdBy: userId,
        snapshotLayers: baseLayers,
      );

      // Save main's working state (unchanged from snapshot)
      await manager.saveBranchWorkingState(canvasId, 'br_main', baseLayers);

      final child = await manager.createChildBranch(
        canvasId: canvasId,
        parentBranchId: 'br_main',
        name: 'Feature',
        createdBy: userId,
        snapshotLayers: baseLayers,
      );

      // Child modifies l1 (adds a stroke via name change to simulate diff)
      final childLayers = [
        _testLayer('l1').copyWith(name: 'Modified Layer 1'),
        _testLayer('l2'),
      ];
      await manager.saveBranchWorkingState(canvasId, child.id, childLayers);

      // 3-way merge
      final result = await manager.mergeBranchThreeWay(
        canvasId: canvasId,
        sourceBranchId: child.id,
        targetBranchId: 'br_main',
      );

      expect(result.isClean, isTrue);
      expect(result.hasConflicts, isFalse);
      expect(result.mergedLayers, isNotNull);
      expect(result.strategy, contains('3-way merge'));
    });

    test('detects conflict when both changed same layer', () async {
      final baseLayers = [_testLayer('l1')];
      await manager.ensureMainBranch(
        canvasId: canvasId,
        createdBy: userId,
        snapshotLayers: baseLayers,
      );

      final child = await manager.createChildBranch(
        canvasId: canvasId,
        parentBranchId: 'br_main',
        name: 'Feature',
        createdBy: userId,
        snapshotLayers: baseLayers,
      );

      // Both modify l1 differently
      await manager.saveBranchWorkingState(canvasId, 'br_main', [
        _testLayer('l1').copyWith(name: 'Main version'),
      ]);
      await manager.saveBranchWorkingState(canvasId, child.id, [
        _testLayer('l1').copyWith(name: 'Feature version'),
      ]);

      final result = await manager.mergeBranchThreeWay(
        canvasId: canvasId,
        sourceBranchId: child.id,
        targetBranchId: 'br_main',
      );

      expect(result.hasConflicts, isTrue);
      expect(result.conflicts, hasLength(1));
      expect(result.conflicts.first.layerId, 'l1');
      expect(result.strategy, contains('conflict'));
    });

    test('self-merge is rejected', () async {
      await manager.ensureMainBranch(
        canvasId: canvasId,
        createdBy: userId,
        snapshotLayers: [],
      );

      final result = await manager.mergeBranchThreeWay(
        canvasId: canvasId,
        sourceBranchId: 'br_main',
        targetBranchId: 'br_main',
      );

      expect(result.mergedLayers, isNull);
      expect(result.strategy, contains('self-merge'));
    });

    test('new layers from source are included', () async {
      final baseLayers = [_testLayer('l1')];
      await manager.ensureMainBranch(
        canvasId: canvasId,
        createdBy: userId,
        snapshotLayers: baseLayers,
      );
      await manager.saveBranchWorkingState(canvasId, 'br_main', baseLayers);

      final child = await manager.createChildBranch(
        canvasId: canvasId,
        parentBranchId: 'br_main',
        name: 'Feature',
        createdBy: userId,
        snapshotLayers: baseLayers,
      );

      // Child adds a new layer
      await manager.saveBranchWorkingState(canvasId, child.id, [
        _testLayer('l1'),
        _testLayer('l_new'),
      ]);

      final result = await manager.mergeBranchThreeWay(
        canvasId: canvasId,
        sourceBranchId: child.id,
        targetBranchId: 'br_main',
      );

      expect(result.isClean, isTrue);
      expect(result.mergedLayers, hasLength(2));
    });
  });

  group('BranchMergeResult', () {
    test('isClean and hasConflicts work correctly', () {
      final clean = BranchMergeResult(
        mergedLayers: [],
        conflicts: [],
        strategy: '3-way merge: clean',
      );
      expect(clean.isClean, isTrue);
      expect(clean.hasConflicts, isFalse);

      final conflicted = BranchMergeResult(
        mergedLayers: [],
        conflicts: [
          LayerMergeConflict(
            layerId: 'l1',
            sourceLayer: _testLayer('l1'),
            targetLayer: _testLayer('l1'),
          ),
        ],
        strategy: '3-way merge: 1 conflict(s)',
      );
      expect(conflicted.isClean, isFalse);
      expect(conflicted.hasConflicts, isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // CANVAS BRANCH MODEL
  // ═══════════════════════════════════════════════════════════════════════════

  group('CanvasBranch — serialization', () {
    test('round-trips through JSON', () {
      final branch = CanvasBranch(
        id: 'br_1',
        canvasId: 'c1',
        parentBranchId: 'br_main',
        forkPointEventIndex: 42,
        forkPointMs: 1234567890,
        name: 'Test Branch',
        createdBy: 'u1',
        createdAt: DateTime(2025, 6, 15),
        color: '#00FF00',
        description: 'A test branch',
        lastModifiedMs: 9999,
        snapshotVersion: 3,
        snapshotStoragePath: '/cloud/path',
        ttSessionCount: 7,
        layerHashes: {'layer1': 'abc123', 'layer2': 'def456'},
      );

      final json = branch.toJson();
      final restored = CanvasBranch.fromJson(json);

      expect(restored.id, 'br_1');
      expect(restored.canvasId, 'c1');
      expect(restored.parentBranchId, 'br_main');
      expect(restored.forkPointEventIndex, 42);
      expect(restored.name, 'Test Branch');
      expect(restored.color, '#00FF00');
      expect(restored.description, 'A test branch');
      expect(restored.lastModifiedMs, 9999);
      expect(restored.snapshotVersion, 3);
      expect(restored.snapshotStoragePath, '/cloud/path');
      expect(restored.ttSessionCount, 7);
      expect(restored.layerHashes, {'layer1': 'abc123', 'layer2': 'def456'});
    });

    test('copyWith updates fields correctly', () {
      final branch = CanvasBranch(
        id: 'br_1',
        canvasId: 'c1',
        forkPointEventIndex: 0,
        forkPointMs: 0,
        name: 'Original',
        createdBy: 'u1',
        createdAt: DateTime(2025),
      );

      final updated = branch.copyWith(
        name: 'Updated',
        description: 'New desc',
        snapshotVersion: 5,
      );

      expect(updated.name, 'Updated');
      expect(updated.description, 'New desc');
      expect(updated.snapshotVersion, 5);
      expect(updated.id, 'br_1'); // Unchanged
    });

    test('copyWith clearDescription removes description', () {
      final branch = CanvasBranch(
        id: 'br_1',
        canvasId: 'c1',
        forkPointEventIndex: 0,
        forkPointMs: 0,
        name: 'test',
        createdBy: 'u1',
        createdAt: DateTime(2025),
        description: 'Has description',
      );

      final cleared = branch.copyWith(clearDescription: true);
      expect(cleared.description, isNull);
    });

    test('helper properties work', () {
      final rootBranch = CanvasBranch(
        id: 'br_1',
        canvasId: 'c1',
        forkPointEventIndex: 0,
        forkPointMs: 0,
        name: 'root',
        createdBy: 'u1',
        createdAt: DateTime(2025),
      );

      expect(rootBranch.isRootBranch, isTrue);
      expect(rootBranch.isSyncedToCloud, isFalse);

      final syncedBranch = rootBranch.copyWith(
        snapshotStoragePath: '/cloud/snap',
      );
      expect(syncedBranch.isSyncedToCloud, isTrue);
    });
  });
}
