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
    final now = DateTime.now();
    final defaultTime = '${now.hour}:${now.minute.toString().padLeft(2, '0')}';
    final nameController = TextEditingController(
      text: FlueraLocalizations.of(context)!.branching_defaultBranchName(defaultTime),
    );

    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
          title: Row(
            children: [
              const Icon(Icons.alt_route_rounded, color: Color(0xFF7C4DFF), size: 22),
              const SizedBox(width: 8),
              Text(FlueraLocalizations.of(context)!.branching_newBranch),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                FlueraLocalizations.of(context)!.branching_forkFromEvent(currentIndex, engine.totalEventCount),
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
                  hintText:
                      FlueraLocalizations.of(context)!.branching_branchName,
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
              child: Text(FlueraLocalizations.of(context)!.branching_cancel),
            ),
            FilledButton(
              onPressed: () {
                final n = nameController.text.trim();
                Navigator.pop(ctx, n.isEmpty ? FlueraLocalizations.of(context)!.branching_untitledBranch : n);
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7C4DFF),
              ),
              child: Text(FlueraLocalizations.of(context)!.branching_create),
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


      // Switch to the new branch
      _switchToBranch(branch.id);
    } catch (e) {
    }
  }

  /// 🌿 Switch to a branch — swaps canvas state
  ///
  /// 1. Flush current branch's in-memory events to disk
  /// 2. Load target branch's snapshot into LayerController
  /// 3. Update recording context for new branch
  /// 4. If in TT mode: re-enter TT for the new branch
  Future<void> _switchToBranch(String? branchId) async {
    // 🎤 Audio↔Stroke Sync — if an audio recording is active, stop it
    // BEFORE swapping canvas state. Otherwise the live recording would
    // end up associated with the wrong branch's strokes (race) and
    // playback would replay strokes from a different scene-graph.
    // The standard stop flow shows a save dialog so the user can keep
    // or discard the in-progress recording.
    if (_isRecordingAudio) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              FlueraLocalizations.of(context)!
                  .audioSync_recordingStoppedOnBranchSwitch,
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      await _stopAudioRecording();
    }

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
      } catch (e) {
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


    // 6. Re-enter TT for the branch only if we were in TT before
    if (wasInTimeTravel) {
      await _enterTimeTravelMode();
    }
  }

  /// 🌿 Open the Alternative Explorer bottom sheet
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
          }) => _replaceOriginalWithAlternative(
            sourceBranchId,
            targetBranchId: targetBranchId,
            deleteAfterMerge: deleteAfterMerge,
          ),
      showAdvancedMerge: widget.config.showAdvancedMergeUI,
    );
  }

  // ============================================================================
  // 📍 CHECKPOINT (linear save/restore — Notion-style)
  // ============================================================================

  /// Async lazy-init: lookup the in-memory cache, otherwise load from disk.
  /// Returns the same instance across calls so the [VersionHistoryPanel]
  /// observes mutations in real time via [setState].
  Future<VersionHistory> _getOrLoadCheckpointHistory() async {
    if (_checkpointHistory != null) return _checkpointHistory!;
    _checkpointStore ??= CheckpointStore();
    _checkpointHistory = await _checkpointStore!.load(_canvasId);
    return _checkpointHistory!;
  }

  /// Persist current checkpoint history to disk (best-effort).
  Future<void> _persistCheckpoints() async {
    final history = _checkpointHistory;
    final store = _checkpointStore;
    if (history == null || store == null) return;
    await store.save(_canvasId, history);
  }

  /// 📍 Save the current canvas state as a named checkpoint.
  /// Enforces Free tier cap (3/canvas) via [VersionHistory.createEntryGated].
  /// Snapshot data = serialized [CanvasLayer] list (same shape as
  /// [BranchingManager.saveBranchWorkingState]), so restore round-trips.
  Future<void> _saveCheckpointWithName(String title) async {
    final history = await _getOrLoadCheckpointHistory();
    final tier = widget.config.subscriptionTier;
    final snapshot = <String, dynamic>{
      // Full layer state — same serialization contract as BranchingManager.
      'layers': _layerController.layers.map((l) => l.toJson()).toList(),
      'capturedAt': DateTime.now().toIso8601String(),
    };
    try {
      final userId = (await widget.config.getUserId()) ?? 'anon';
      history.createEntryGated(
        tier: tier,
        title: title,
        authorId: userId,
        data: snapshot,
      );
      await _persistCheckpoints();
      if (mounted) setState(() {}); // refresh counter in panel if open
    } on CheckpointLimitError {
      // Soft block — UI layer (VersionHistoryPanel) already shows upsell modal
      // before calling here, so this catch is defensive only.
    }
  }

  /// 🔄 Restore canvas state from a checkpoint entry.
  /// Mirrors the layer-swap path used in [_switchToBranch].
  Future<void> _restoreCheckpoint(VersionEntry entry) async {
    final layersJson = entry.data['layers'] as List<dynamic>?;
    if (layersJson == null || layersJson.isEmpty) return;
    final layers = layersJson
        .map((j) => CanvasLayer.fromJson(Map<String, dynamic>.from(j as Map)))
        .toList();
    _layerController.clearAllAndLoadLayers(layers);
    _refreshCachedLists();
  }

  /// 📜 Open the Checkpoint panel as a modal bottom sheet.
  Future<void> _openCheckpointPanel() async {
    final history = await _getOrLoadCheckpointHistory();
    if (!mounted) return;
    final tier = widget.config.subscriptionTier;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheetCtx).size.height * 0.7,
        ),
        decoration: BoxDecoration(
          color: Theme.of(sheetCtx).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SizedBox(
          width: double.infinity,
          child: VersionHistoryPanel(
            history: history,
            tier: tier,
            onCreateVersion: (title) async {
              await _saveCheckpointWithName(title);
            },
            onRestore: (entry) async {
              Navigator.pop(sheetCtx);
              await _restoreCheckpoint(entry);
            },
            onDelete: (entry) async {
              history.deleteEntry(entry.id);
              await _persistCheckpoints();
              if (mounted) setState(() {});
            },
            onClose: () => Navigator.pop(sheetCtx),
            onUpgradePressed: () {
              Navigator.pop(sheetCtx);
              // Route to subscription paywall — host wires this.
            },
          ),
        ),
      ),
    );
  }

  /// 🔄 Replace Original (br_main) with the contents of a selected alternative.
  ///
  /// Renamed from `_handleBranchMerge` (2026-05-15) — power-user merge.
  /// Default UI surfaces this with target=main + deleteAfterMerge=true.
  /// Cloud sync is triggered automatically by [saveBranchWorkingState] inside
  /// [mergeBranch].
  Future<void> _replaceOriginalWithAlternative(
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
      return;
    }

    // 3. Switch to the target branch with the merged layers
    await _switchToBranch(targetBranchId);

  }

  /// 🗑️ Handle branch deletion — switch to main and clean up
  Future<void> _handleBranchDeleted(String deletedBranchId) async {

    // Clean up TT storage for the deleted branch
    try {
      final storageService = TimeTravelStorageService();
      await storageService.deleteHistory(_canvasId, branchId: deletedBranchId);
    } catch (e) {
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
            title: Text(FlueraLocalizations.of(context)!.branching_newBranch),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  FlueraLocalizations.of(context)!.branching_forkFromBranch(_activeBranchName ?? 'main'),
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
                    hintText:
                      FlueraLocalizations.of(context)!.branching_branchName,
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
                child: Text(FlueraLocalizations.of(context)!.branching_cancel),
              ),
              FilledButton(
                onPressed: () {
                  final n = nameController.text.trim();
                  Navigator.pop(ctx, n.isEmpty ? FlueraLocalizations.of(context)!.branching_untitledBranch : n);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF7C4DFF),
                ),
                child: Text(FlueraLocalizations.of(context)!.branching_create),
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


      // Switch to the new branch
      _switchToBranch(branch.id);
    } catch (e) {
    }
  }
}
