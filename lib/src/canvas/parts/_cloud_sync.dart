part of '../nebula_canvas_screen.dart';

/// 📦 Cloud Sync — generic save & sync through NebulaCanvasConfig callbacks.
///
/// Replaces the app-specific Firebase implementation with generic provider calls:
///   - `_config.onSaveCanvas()` for local persistence
///   - `_config.onCloudSync()` for full cloud save
///   - `_config.onDeltaSync()` for incremental delta push
extension CloudSyncExtension on _NebulaCanvasScreenState {
  /// Flag to log auto-save errors only once (avoid console spam).
  static bool _autoSaveErrorLogged = false;

  /// Builds a [NebulaCanvasSaveData] snapshot of the current canvas state.
  NebulaCanvasSaveData _buildSaveData() {
    return NebulaCanvasSaveData(
      canvasId: _canvasId,
      layers: _layerController.layers,
      textElements: _digitalTextElements,
      imageElements: _imageElements,
      backgroundColor: _canvasBackgroundColor.toARGB32().toString(),
      paperType: _paperType,
      activeLayerId: _layerController.activeLayerId,
      title: _noteTitle,
      infiniteCanvasId: widget.infiniteCanvasId,
      nodeId: widget.nodeId,
      guides: _rulerGuideSystem.toJson(),
    );
  }

  /// 💾 AUTO-SAVE canvas (called on every modification).
  ///
  /// **Debounced** (500ms): rapid modifications are batched so the expensive
  /// JSON serialization runs only once after the user pauses.
  /// Heavy work is deferred via `Future.microtask` to avoid blocking the
  /// current pointer-event/paint frame.
  ///
  /// 1. Always saves locally via storage adapter or legacy callback.
  /// 2. If cloud sync is enabled, pushes deltas and debounced full save
  ///    via `_config.onCloudSync`.
  Future<void> _autoSaveCanvas() async {
    if (_isLoading) return;

    // Push deltas immediately (lightweight — no JSON serialization)
    if (_isSharedCanvas) {
      _snapshotAndPushCloudDeltas();
    }

    // Debounce heavy serialization + I/O
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      _performSave();
    });
  }

  /// Actually perform the save (runs after debounce).
  Future<void> _performSave() async {
    try {
      final saveData = _buildSaveData();

      // 1️⃣ Local save — prefer storageAdapter over legacy callback
      if (_config.storageAdapter != null) {
        final dataMap = saveData.toJson();
        dataMap['layers'] = saveData.layers.map((l) => l.toJson()).toList();
        await _config.storageAdapter!.saveCanvas(saveData.canvasId, dataMap);
      } else {
        await _config.onSaveCanvas?.call(saveData);
      }

      // 2️⃣ Cloud save (debounced, only if enabled + tier allows)
      if (_config.cloudSyncEnabled && _hasCloudSync) {
        _config.onCloudSync?.call(_canvasId, saveData.toJson());
      }
    } catch (e) {
      // Log once to avoid console spam (e.g. storage adapter not initialized)
      if (!_autoSaveErrorLogged) {
        _autoSaveErrorLogged = true;
        debugPrint(
          '[CloudSync] Auto-save error (further errors suppressed): $e',
        );
      }
    }
  }

  /// 📤 Snapshot deltas and push to cloud BEFORE local save consumes them.
  void _snapshotAndPushCloudDeltas({String? changeDescription}) {
    if (!_isSharedCanvas) return;
    if (_config.onDeltaSync == null) return;

    final deltas = CanvasDeltaTracker.instance.peekDeltas();
    if (deltas.isEmpty) return;

    final taggedDeltas =
        deltas.map((d) {
          final json = d.toJson();
          json['epoch'] = DateTime.now().millisecondsSinceEpoch;
          if (changeDescription != null) json['desc'] = changeDescription;
          return json;
        }).toList();

    _config.onDeltaSync!.call(_canvasId, taggedDeltas);
  }

  /// 🔄 Force full sync (manual trigger).
  Future<void> forceFirebaseSync() async {
    try {
      final saveData = _buildSaveData();

      // Local save — prefer storageAdapter over legacy callback
      if (_config.storageAdapter != null) {
        final dataMap = saveData.toJson();
        dataMap['layers'] = saveData.layers.map((l) => l.toJson()).toList();
        await _config.storageAdapter!.saveCanvas(saveData.canvasId, dataMap);
      } else {
        await _config.onSaveCanvas?.call(saveData);
      }

      // Cloud save (immediate, no debounce)
      if (_config.cloudSyncEnabled) {
        await _config.onCloudSync?.call(_canvasId, saveData.toJson());
      }
    } catch (e) {
      debugPrint('[CloudSync] Force sync error: $e');
    }
  }
}
