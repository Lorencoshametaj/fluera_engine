part of '../fluera_canvas_screen.dart';

/// 📦 Cloud Sync — generic save & sync through FlueraCanvasConfig callbacks.
///
/// **PERFORMANCE DESIGN**:
/// - Saves are deferred while a stroke is being drawn (zero interference)
/// - 2s debounce batches rapid modifications into a single save
/// - SqliteStorageAdapter path: Layer → Binary (Isolate) → SQLite (no JSON)
/// - Cloud sync via [FlueraSyncEngine] with its own 3s debounce + retry
extension CloudSyncExtension on _FlueraCanvasScreenState {
  /// Flag to log auto-save errors only once (avoid console spam).
  static bool _autoSaveErrorLogged = false;

  /// Lock flag to prevent overlapping save operations from piling up.
  static bool _saveInProgress = false;

  /// 🎛️ Build a JSON string for variable state persistence.
  String? _buildVariablesJsonString(FlueraCanvasSaveData saveData) {
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

  /// Builds a [FlueraCanvasSaveData] snapshot of the current canvas state.
  FlueraCanvasSaveData _buildSaveData() {
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

    return FlueraCanvasSaveData(
      canvasId: _canvasId,
      layers: _layerController.layers,
      textElements: _digitalTextElements,
      imageElements: _imageElements,
      recordingPins: _recordingPins,
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
  /// 2. If cloud adapter is configured, pushes to cloud via [FlueraSyncEngine].
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

      // 🖼️ 1.5: Capture viewport snapshot for next splash screen (fire-and-forget)
      _captureCanvasSnapshot(saveData.canvasId);

      // 2️⃣ Cloud save (via FlueraSyncEngine — has its own debounce + retry)
      if (_syncEngine != null) {
        final adapter = _syncEngine!.adapter;
        final cloudData = saveData.toJson();
        final layers = saveData.layers.map((l) => l.toJson()).toList();

        if (adapter.supportsStrokeSharding) {
          // 🚀 SHARDED: Save metadata (layers without strokes) + strokes separately
          // Strip strokes from layer data to keep doc under 1MB
          final strippedLayers =
              layers.map((layerJson) {
                final copy = Map<String, dynamic>.from(layerJson);
                copy.remove('strokes'); // Remove strokes from metadata doc
                return copy;
              }).toList();
          cloudData['layers'] = strippedLayers;
          _syncEngine!.requestSave(
            _canvasId,
            _FlueraCanvasScreenState._sanitizeForFirestore(cloudData),
          );

          // Save strokes as sub-collection documents
          final strokeTuples = <(String, Map<String, dynamic>)>[];
          for (final layerJson in layers) {
            final layerId = layerJson['id'] as String? ?? 'default';
            final strokes = layerJson['strokes'] as List?;
            if (strokes != null) {
              for (final s in strokes) {
                strokeTuples.add((
                  layerId,
                  Map<String, dynamic>.from(s as Map),
                ));
              }
            }
          }
          if (strokeTuples.isNotEmpty) {
            // Fire-and-forget (debounced by sync engine)
            // Sanitize each stroke map to avoid nested arrays in Firestore
            final sanitizedTuples =
                strokeTuples.map((t) {
                  return (
                    t.$1,
                    _FlueraCanvasScreenState._sanitizeForFirestore(t.$2),
                  );
                }).toList();
            adapter.saveStrokes(_canvasId, sanitizedTuples).catchError((e) {
              debugPrint('☁️ Stroke sharding save failed: $e');
            });
          }
        } else {
          // Legacy: save everything in one document
          cloudData['layers'] = layers;
          _syncEngine!.requestSave(
            _canvasId,
            _FlueraCanvasScreenState._sanitizeForFirestore(cloudData),
          );
        }
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
        await _syncEngine!.flush(
          _canvasId,
          _FlueraCanvasScreenState._sanitizeForFirestore(cloudData),
        );
      }
    } catch (e) {
      debugPrint('[CloudSync] Force sync error: $e');
    }
  }

  /// ☁️ Download missing image assets from cloud storage.
  ///
  /// Called after loading canvas data from cloud. Downloads are run
  /// in parallel (max 4 concurrent) for faster batch loading.
  Future<void> downloadMissingAssets() async {
    if (_syncEngine == null) return;

    // 🚀 FIX #7: Collect all download tasks, run in parallel batches
    final downloadTasks = <Future<void>>[];

    for (final img in _imageElements) {
      if (img.storageUrl == null || img.storageUrl!.isEmpty) continue;

      // Check if local file already exists
      final localFile = File(img.imagePath);
      if (await localFile.exists()) continue;

      downloadTasks.add(_downloadSingleAsset(img.id, img.imagePath));
    }

    if (downloadTasks.isEmpty) return;

    debugPrint(
      '[☁️ DOWNLOAD] Starting ${downloadTasks.length} parallel downloads',
    );

    // Run all downloads in parallel (network handles concurrency)
    await Future.wait(downloadTasks);

    debugPrint('[☁️ DOWNLOAD] All downloads complete');
  }

  /// Download a single asset from cloud and save locally.
  Future<void> _downloadSingleAsset(String assetId, String localPath) async {
    try {
      final bytes = await _syncEngine!.adapter.downloadAsset(
        _canvasId,
        assetId,
      );

      if (bytes != null) {
        final localFile = File(localPath);
        await localFile.parent.create(recursive: true);
        await localFile.writeAsBytes(bytes, flush: true);
        // 💾 Cache compressed bytes for instant reload after eviction
        _imageMemoryManager.cacheCompressedBytes(localPath, bytes);
        debugPrint('[☁️ DOWNLOAD] ✅ ${assetId}: ${bytes.length ~/ 1024}KB');
      }
    } catch (e) {
      debugPrint('[☁️ DOWNLOAD] ❌ $assetId: $e');
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

  /// 🖼️ Capture a low-resolution snapshot of the canvas viewport.
  ///
  /// Used for the splash screen preview on next open. Runs entirely
  /// in the background — never blocks saving or rendering.
  ///
  /// **Strategy**: Uses the RepaintBoundary wrapping the canvas area
  /// to capture the current viewport at reduced resolution (~480px
  /// long side → ~50-100KB PNG).
  Future<void> _captureCanvasSnapshot(String canvasId) async {
    try {
      final adapter = _config.storageAdapter;
      if (adapter == null) return;

      final boundary =
          _canvasRepaintBoundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null || !boundary.hasSize) return;

      // Calculate pixel ratio for ~480px on the long side
      final logicalSize = boundary.size;
      final longestSide = math.max(logicalSize.width, logicalSize.height);
      if (longestSide <= 0) return;
      final pixelRatio = (480.0 / longestSide).clamp(0.1, 1.0);

      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();

      if (byteData == null) return;

      final png = byteData.buffer.asUint8List();
      await adapter.saveSnapshot(canvasId, png);
    } catch (e) {
      // Non-critical — swallow errors silently
      debugPrint('[Snapshot] Capture failed: $e');
    }
  }
}
