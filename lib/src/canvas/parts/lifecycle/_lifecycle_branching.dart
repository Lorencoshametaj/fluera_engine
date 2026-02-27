part of '../../fluera_canvas_screen.dart';

// ============================================================================
// 🌿 CREATIVE BRANCHING LIFECYCLE
// Extracted from _lifecycle.dart — branch create, switch, merge, delete, explore
// ============================================================================

extension on _FlueraCanvasScreenState {
  /// 🌿 Lazy-init BranchingManager (reuses existing StorageService)
  BranchingManager _getOrCreateBranchingManager() {
    _branchingManager ??= BranchingManager(
      storage: TimeTravelStorageService(),
      cloudSync: BranchCloudSyncService.instance,
    )..cloudSyncEnabled = _hasCloudSync;
    return _branchingManager!;
  }

  /// 🌿 Create a new branch from the current Time Travel playback position
  Future<void> _createBranchFromCurrentPosition() async {
    final engine = _timeTravelEngine;
    if (engine == null) return;

    final currentIndex = engine.currentEventIndex;
    final currentMs =
        engine.currentAbsoluteTime?.millisecondsSinceEpoch ??
        DateTime.now().millisecondsSinceEpoch;

    // Pause playback while creating branch
    engine.pause();

    // Show naming dialog
    final nameController = TextEditingController(
      text:
          'Branch ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}',
    );

    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
          title: const Row(
            children: [
              Icon(Icons.alt_route_rounded, color: Color(0xFF7C4DFF), size: 22),
              SizedBox(width: 8),
              Text('New Branch'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Fork from event $currentIndex of ${engine.totalEventCount}',
                style: TextStyle(
                  color: isDark ? Colors.white54 : Colors.black45,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Branch name',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.label_outline_rounded, size: 20),
                  filled: true,
                  fillColor:
                      isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.black.withValues(alpha: 0.03),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final n = nameController.text.trim();
                Navigator.pop(ctx, n.isEmpty ? 'Untitled Branch' : n);
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7C4DFF),
              ),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );

    if (name == null || !mounted) return; // User cancelled

    final manager = _getOrCreateBranchingManager();

    try {
      final branch = await manager.createBranch(
        canvasId: _canvasId,
        forkPointEventIndex: currentIndex,
        forkPointMs: currentMs,
        name: name,
        createdBy: await _config.getUserId() ?? 'unknown',
        snapshotLayers: engine.currentLayers,
      );

      debugPrint(
        '🌿 [Branching] Created branch "${branch.name}" '
        'at event $currentIndex',
      );

      // Switch to the new branch
      _switchToBranch(branch.id);
    } catch (e) {
      debugPrint('🌿 [Branching] ❌ Create branch error: $e');
    }
  }

  /// 🌿 Switch to a branch — swaps canvas state
  ///
  /// 1. Flush current branch's in-memory events to disk
  /// 2. Load target branch's snapshot into LayerController
  /// 3. Update recording context for new branch
  /// 4. If in TT mode: re-enter TT for the new branch
  Future<void> _switchToBranch(String? branchId) async {
    final wasInTimeTravel = _isTimeTravelMode;

    // If in TT mode, exit first
    if (wasInTimeTravel) {
      _exitTimeTravelMode();
    }

    // 1. Flush current branch events before switching
    final recorder = _timeTravelRecorder;
    if (recorder != null && recorder.hasEvents) {
      recorder.stopRecording();
      try {
        final storageService = TimeTravelStorageService();
        await storageService.saveRecordedSession(
          recorder,
          _canvasId,
          currentLayers: _layerController.layers,
          branchId: _activeBranchId,
        );
        debugPrint(
          '🌿 [Branching] Flushed ${recorder.eventCount} events '
          'for branch $_activeBranchId',
        );
      } catch (e) {
        debugPrint('🌿 [Branching] Flush error: $e');
      }
    }

    // 1b. Save current canvas state as working snapshot for this branch
    if (_activeBranchId != null) {
      final manager = _getOrCreateBranchingManager();
      await manager.saveBranchWorkingState(
        _canvasId,
        _activeBranchId!,
        _layerController.layers,
      );

      // ☁️ Cloud sync: upload TT sessions for the branch we're leaving
      if (_hasCloudSync) {
        await manager.uploadBranchTTSessions(_canvasId, _activeBranchId!);
      }
    }

    // 2. Load target branch's canvas state
    final manager = _getOrCreateBranchingManager();
    await manager.loadBranches(_canvasId);

    final layers = await manager.switchToBranch(_canvasId, branchId);
    final branch = manager.activeBranch;

    // 3. Apply branch snapshot to canvas
    if (layers != null && layers.isNotEmpty) {
      _layerController.clearAllAndLoadLayers(layers);
      debugPrint(
        '🌿 [Branching] Loaded ${layers.length} layers for branch $branchId',
      );
    }

    // 4. Update branch context
    setState(() {
      _activeBranchId = branchId;
      _activeBranchName = branch?.name;
    });

    // 5. Restart recording for the new branch
    _timeTravelRecorder = TimeTravelRecorder();
    _timeTravelRecorder!.activeBranchId = branchId;
    _timeTravelRecorder!.startRecording();

    // Re-wire LayerController → Recorder
    _layerController.onTimeTravelEvent = (
      type,
      layerId, {
      elementId,
      elementData,
      pageIndex,
    }) {
      _timeTravelRecorder?.recordEvent(
        type,
        layerId,
        elementId: elementId,
        elementData: elementData,
        pageIndex: pageIndex,
      );
    };

    // Refresh cached strokes/shapes from new layers
    _refreshCachedLists();

    debugPrint(
      '🌿 [Branching] Switched to ${branch?.name ?? "main"} '
      '(wasInTT: $wasInTimeTravel)',
    );

    // 6. Re-enter TT for the branch only if we were in TT before
    if (wasInTimeTravel) {
      await _enterTimeTravelMode();
    }
  }

  /// 🌿 Open the Branch Explorer bottom sheet
  void _openBranchExplorer() {
    final manager = _getOrCreateBranchingManager();

    BranchExplorerSheet.show(
      context: context,
      canvasId: _canvasId,
      branchingManager: manager,
      activeBranchId: _activeBranchId,
      onSwitchBranch: _switchToBranch,
      onCreateBranch: () => _createBranchFromExplorer(),
      onDeleteBranch:
          (deletedBranchId) => _handleBranchDeleted(deletedBranchId),
      onMergeBranch:
          (
            sourceBranchId, {
            String targetBranchId = 'br_main',
            bool deleteAfterMerge = false,
          }) => _handleBranchMerge(
            sourceBranchId,
            targetBranchId: targetBranchId,
            deleteAfterMerge: deleteAfterMerge,
          ),
    );
  }

  /// 🔀 Handle branch merge (any child → parent, git-style)
  ///
  /// Merges the source branch's layers into the target, reloads the canvas,
  /// and switches context to the target branch. Cloud sync is triggered
  /// automatically by [saveBranchWorkingState] inside [mergeBranch].
  Future<void> _handleBranchMerge(
    String sourceBranchId, {
    required String targetBranchId,
    bool deleteAfterMerge = false,
  }) async {
    final manager = _getOrCreateBranchingManager();

    // 1. Save current branch state before merge (auto-save guard)
    if (_activeBranchId != null) {
      await manager.saveBranchWorkingState(
        _canvasId,
        _activeBranchId!,
        _layerController.layers,
      );
    }

    // 2. Perform the merge
    final mergedLayers = await manager.mergeBranch(
      canvasId: _canvasId,
      sourceBranchId: sourceBranchId,
      targetBranchId: targetBranchId,
      deleteAfterMerge: deleteAfterMerge,
    );

    if (mergedLayers == null) {
      debugPrint(
        '❌ [Branching] Merge failed: $sourceBranchId → $targetBranchId',
      );
      return;
    }

    // 3. Switch to the target branch with the merged layers
    await _switchToBranch(targetBranchId);

    debugPrint(
      '🔀 [Branching] Merge complete: $sourceBranchId → $targetBranchId '
      '(${mergedLayers.length} layers, delete=$deleteAfterMerge)',
    );
  }

  /// 🗑️ Handle branch deletion — switch to main and clean up
  Future<void> _handleBranchDeleted(String deletedBranchId) async {
    debugPrint(
      '🌿 [Branching] Branch $deletedBranchId deleted, switching to main',
    );

    // Clean up TT storage for the deleted branch
    try {
      final storageService = TimeTravelStorageService();
      await storageService.deleteHistory(_canvasId, branchId: deletedBranchId);
    } catch (e) {
      debugPrint('🌿 [Branching] TT cleanup error: $e');
    }

    // Switch back to main branch
    await _switchToBranch('br_main');
  }

  /// 🌿 Create a new branch from the Branch Explorer
  ///
  /// Forks from the current active branch's canvas state.
  Future<void> _createBranchFromExplorer() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final nameController = TextEditingController();

    final name = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
            title: const Text('New Branch'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Fork from "${_activeBranchName ?? "main"}"',
                  style: TextStyle(
                    color: isDark ? Colors.white54 : Colors.black45,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Branch name',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(
                      Icons.label_outline_rounded,
                      size: 20,
                    ),
                    filled: true,
                    fillColor:
                        isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.black.withValues(alpha: 0.03),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final n = nameController.text.trim();
                  Navigator.pop(ctx, n.isEmpty ? 'Untitled Branch' : n);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF7C4DFF),
                ),
                child: const Text('Create'),
              ),
            ],
          ),
    );

    if (name == null || !mounted) return;

    try {
      final userId = await _config.getUserId() ?? 'unknown';
      final manager = _getOrCreateBranchingManager();

      final branch = await manager.createChildBranch(
        canvasId: _canvasId,
        parentBranchId: _activeBranchId ?? 'br_main',
        name: name,
        createdBy: userId,
        snapshotLayers: _layerController.layers,
      );

      debugPrint(
        '🌿 [Branching] Created branch "${branch.name}" from explorer',
      );

      // Switch to the new branch
      _switchToBranch(branch.id);
    } catch (e) {
      debugPrint('🌿 [Branching] ❌ Create branch error: $e');
    }
  }
}
