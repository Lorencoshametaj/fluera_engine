part of '../nebula_canvas_screen.dart';

/// 📦 Cloud Sync — generic save & sync through NebulaCanvasConfig callbacks.
///
/// **PERFORMANCE DESIGN**:
/// - Saves are deferred while a stroke is being drawn (zero interference)
/// - 2s debounce batches rapid modifications into a single save
/// - SqliteStorageAdapter path: Layer → Binary (Isolate) → SQLite (no JSON)
/// - Cloud sync via [NebulaSyncEngine] with its own 3s debounce + retry
extension CloudSyncExtension on _NebulaCanvasScreenState {
  /// Flag to log auto-save errors only once (avoid console spam).
  static bool _autoSaveErrorLogged = false;

  /// Lock flag to prevent overlapping save operations from piling up.
  static bool _saveInProgress = false;

  /// 🎛️ Build a JSON string for variable state persistence.
  String? _buildVariablesJsonString(NebulaCanvasSaveData saveData) {
    final colls = saveData.variableCollectionsJson;
    if (colls == null || colls.isEmpty) return null;
    return jsonEncode(<String, dynamic>{
      'collections': colls,
      if (saveData.variableBindingsJson != null)
        'bindings': saveData.variableBindingsJson,
      if (saveData.variableActiveModesJson != null)
        'activeModes': saveData.variableActiveModesJson,
    });
  }

  /// Builds a [NebulaCanvasSaveData] snapshot of the current canvas state.
  NebulaCanvasSaveData _buildSaveData() {
    // 🎛️ Serialize variable state (only if non-empty)
    final collectionsJson =
        _variableCollections.isNotEmpty
            ? _variableCollections.map((c) => c.toJson()).toList()
            : null;
    final bindingsJson =
        _variableBindings.bindingCount > 0 ? _variableBindings.toJson() : null;
    final activeModesJson =
        _variableResolver.activeModes.isNotEmpty
            ? _variableResolver.activeModesToJson()
            : null;

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
      variableCollectionsJson: collectionsJson,
      variableBindingsJson: bindingsJson,
      variableActiveModesJson: activeModesJson,
    );
  }

  /// 💾 AUTO-SAVE canvas (called on every modification).
  ///
  /// **Debounced** (2s): rapid modifications are batched so the expensive
  /// serialization + I/O runs only once after the user pauses.
  /// Saves are deferred if a stroke is currently being drawn.
  ///
  /// 1. Always saves locally via storage adapter or legacy callback.
  /// 2. If cloud adapter is configured, pushes to cloud via [NebulaSyncEngine].
  Future<void> _autoSaveCanvas() async {
    if (_isLoading) return;

    // Debounce heavy serialization + I/O (2s for maximum batching)
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(milliseconds: 2000), () {
      _performSave();
    });
  }

  /// Actually perform the save (runs after debounce).
  ///
  /// **Zero main-thread work**: For SqliteStorageAdapter, layers are passed
  /// directly (no JSON round-trip). Binary encoding runs in an Isolate inside
  /// the adapter. For legacy/custom adapters, JSON serialization is used.
  Future<void> _performSave() async {
    // Prevent overlapping saves
    if (_saveInProgress) return;

    // 🚫 Defer save while actively drawing — never interfere with rendering.
    // The debounce timer will fire again after the stroke ends.
    if (_currentStrokeNotifier.value.isNotEmpty) {
      _saveDebounceTimer?.cancel();
      _saveDebounceTimer = Timer(const Duration(milliseconds: 2000), () {
        _performSave();
      });
      return;
    }

    _saveInProgress = true;

    try {
      final saveData = _buildSaveData();
      // Capture dirty IDs BEFORE save (they'll be cleared after success)
      final dirtyIds = _layerController.dirtyLayerIds;

      // 1️⃣ Local save
      final adapter = _config.storageAdapter;
      if (adapter != null) {
        if (adapter is SqliteStorageAdapter) {
          // 🚀 FAST PATH: Direct Layer → Binary (Isolate) → SQLite
          // 🚀 DELTA: Only re-encode dirty layers
          await adapter.saveCanvasLayers(
            canvasId: saveData.canvasId,
            layers: saveData.layers,
            title: saveData.title,
            paperType: saveData.paperType,
            backgroundColor: saveData.backgroundColor,
            activeLayerId: saveData.activeLayerId,
            infiniteCanvasId: saveData.infiniteCanvasId,
            nodeId: saveData.nodeId,
            guides: saveData.guides,
            dirtyLayerIds: dirtyIds.isNotEmpty ? dirtyIds : null,
            variablesJson: _buildVariablesJsonString(saveData),
          );
        } else {
          // Legacy path for custom adapters (JSON required by interface)
          final dataMap = saveData.toJson();
          dataMap['layers'] = saveData.layers.map((l) => l.toJson()).toList();
          await adapter.saveCanvas(saveData.canvasId, dataMap);
        }
      } else {
        await _config.onSaveCanvas?.call(saveData);
      }

      // ✅ Save succeeded — clear dirty tracking
      _layerController.clearDirtyLayerIds();
      _lastLocalSaveTimestamp = DateTime.now().millisecondsSinceEpoch;

      // 2️⃣ Cloud save (via NebulaSyncEngine — has its own debounce + retry)
      if (_syncEngine != null) {
        final cloudData = saveData.toJson();
        cloudData['layers'] = saveData.layers.map((l) => l.toJson()).toList();
        _syncEngine!.requestSave(_canvasId, cloudData);
      }
    } catch (e) {
      if (!_autoSaveErrorLogged) {
        _autoSaveErrorLogged = true;
        debugPrint(
          '[CloudSync] Auto-save error (further errors suppressed): $e',
        );
      }
    } finally {
      _saveInProgress = false;
    }
  }

  /// 🔄 Force full sync (manual trigger). Always does a FULL save.
  Future<void> forceFirebaseSync() async {
    try {
      final saveData = _buildSaveData();

      final adapter = _config.storageAdapter;
      if (adapter != null) {
        if (adapter is SqliteStorageAdapter) {
          // Full save (no dirtyLayerIds = encode all layers)
          await adapter.saveCanvasLayers(
            canvasId: saveData.canvasId,
            layers: saveData.layers,
            title: saveData.title,
            paperType: saveData.paperType,
            backgroundColor: saveData.backgroundColor,
            activeLayerId: saveData.activeLayerId,
            infiniteCanvasId: saveData.infiniteCanvasId,
            nodeId: saveData.nodeId,
            guides: saveData.guides,
          );
        } else {
          final dataMap = saveData.toJson();
          dataMap['layers'] = saveData.layers.map((l) => l.toJson()).toList();
          await adapter.saveCanvas(saveData.canvasId, dataMap);
        }
      } else {
        await _config.onSaveCanvas?.call(saveData);
      }

      // Full save succeeded — clear dirty tracking
      _layerController.clearDirtyLayerIds();

      // Cloud save (immediate, no debounce)
      if (_syncEngine != null) {
        final cloudData = saveData.toJson();
        cloudData['layers'] = saveData.layers.map((l) => l.toJson()).toList();
        await _syncEngine!.flush(_canvasId, cloudData);
      }
    } catch (e) {
      debugPrint('[CloudSync] Force sync error: $e');
    }
  }

  /// ☁️ Download missing image assets from cloud storage.
  ///
  /// Called after loading canvas data from cloud. For each image element
  /// that has a `storageUrl` but no local file, downloads the binary
  /// and saves it locally.
  Future<void> downloadMissingAssets() async {
    if (_syncEngine == null) return;

    for (final img in _imageElements) {
      if (img.storageUrl == null || img.storageUrl!.isEmpty) continue;

      // Check if local file already exists
      final localFile = File(img.imagePath);
      if (await localFile.exists()) continue;

      try {
        final bytes = await _syncEngine!.adapter.downloadAsset(
          _canvasId,
          img.id,
        );

        if (bytes != null) {
          // Ensure parent directory exists
          await localFile.parent.create(recursive: true);
          await localFile.writeAsBytes(bytes);
          debugPrint('☁️ Downloaded missing asset: ${img.id}');
        }
      } catch (e) {
        debugPrint('☁️ Failed to download asset ${img.id}: $e');
      }
    }
  }

  /// ☁️ Upload a single image asset to cloud storage.
  ///
  /// Returns the cloud URL on success, or `null` on failure.
  /// Used by `pickAndAddImage` and can be called for batch uploads.
  Future<String?> uploadImageAsset(String imageId, String filePath) async {
    if (_syncEngine == null) return null;

    try {
      final bytes = await File(filePath).readAsBytes();
      final url = await _syncEngine!.adapter.uploadAsset(
        _canvasId,
        imageId,
        bytes,
        mimeType: 'image/png',
      );
      debugPrint('☁️ Asset uploaded: $imageId');
      return url;
    } catch (e) {
      debugPrint('☁️ Asset upload failed: $e');
      return null;
    }
  }
}
