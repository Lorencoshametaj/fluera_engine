part of '../nebula_canvas_screen.dart';

/// 📦 Cloud Sync — generic save & sync through NebulaCanvasConfig callbacks.
///
/// Replaces the app-specific Firebase implementation with generic provider calls:
///   - `_config.onSaveCanvas()` for local persistence
///   - `_config.onCloudSync()` for full cloud save
///   - `_config.onDeltaSync()` for incremental delta push
extension CloudSyncExtension on _NebulaCanvasScreenState {
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
  /// 1. Always saves locally via `_config.onSaveCanvas`.
  /// 2. If cloud sync is enabled, pushes deltas and debounced full save
  ///    via `_config.onCloudSync`.
  Future<void> _autoSaveCanvas() async {
    if (_isLoading) return;

    try {
      final saveData = _buildSaveData();

      // Push deltas for shared canvases BEFORE local save can consume them
      if (_isSharedCanvas) {
        _snapshotAndPushCloudDeltas();
      }

      // 1️⃣ Local save (always, immediate)
      await _config.onSaveCanvas?.call(saveData);

      // 2️⃣ Cloud save (debounced, only if enabled + tier allows)
      if (_config.cloudSyncEnabled && _hasCloudSync) {
        _config.onCloudSync?.call(_canvasId, saveData.toJson());
      }
    } catch (e) {
      // Don't block the user on save errors
      debugPrint('[CloudSync] Auto-save error: $e');
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

      // Local save
      await _config.onSaveCanvas?.call(saveData);

      // Cloud save (immediate, no debounce)
      if (_config.cloudSyncEnabled) {
        await _config.onCloudSync?.call(_canvasId, saveData.toJson());
      }
    } catch (e) {
      debugPrint('[CloudSync] Force sync error: $e');
    }
  }
}
