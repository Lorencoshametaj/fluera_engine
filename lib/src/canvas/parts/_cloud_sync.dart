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

  /// 🔗 Build a JSON string for Knowledge Flow connections persistence.
  String? _buildConnectionsJsonString() {
    if (_knowledgeFlowController == null) return null;
    final connections = _knowledgeFlowController!.connections;
    if (connections.isEmpty) return null;
    return jsonEncode(connections.map((c) => c.toJson()).toList());
  }

  /// 🧠 Build a JSON string for semantic AI titles persistence.
  /// Saves both the AI title and the content hash (for invalidation).
  String? _buildSemanticTitlesJsonString() {
    if (_semanticMorphController == null) return null;
    final titles = _semanticMorphController!.aiTitles;
    if (titles.isEmpty) return null;
    final hashes = _semanticMorphController!.getAiTitleHashes();
    return jsonEncode(<String, dynamic>{
      'titles': titles,
      'hashes': hashes,
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
          // 🛡️ SAVE GUARD: block paging from stubifying strokes during save.
          DrawingPainter.setSaveGuard(true);

          // 🗂️ PRE-SAVE: Restore paged-out stubs with full data from SQLite
          // to prevent data loss during binary encoding.
          final restoredForSave =
              await DrawingPainter.restorePagedStrokesForSave();
          if (restoredForSave.isNotEmpty) {
            for (final layer in saveData.layers) {
              for (final sn in layer.node.strokeNodes) {
                final full = restoredForSave[sn.stroke.id];
                if (full != null) {
                  sn.stroke = full;
                }
              }
              // Invalidate cached strokes so encode() reads from StrokeNodes
              layer.node.invalidateStrokeCache();
            }
          }

          try {
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
              connectionsJson: _buildConnectionsJsonString(),
              semanticTitlesJson: _buildSemanticTitlesJsonString(),
            );
          } finally {
            // 🗂️ POST-SAVE: Re-stub only strokes that were paged-out (restored above)
            if (restoredForSave.isNotEmpty) {
              for (final layer in saveData.layers) {
                for (final sn in layer.node.strokeNodes) {
                  if (restoredForSave.containsKey(sn.stroke.id)) {
                    sn.stroke = sn.stroke.toStub();
                  }
                }
                layer.node.invalidateStrokeCache();
              }
            }

            // 🛡️ Release save guard
            DrawingPainter.setSaveGuard(false);
          }
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
      // 🚀 PERF: Skip ENTIRELY when sync engine is in permanent error state.
      if (_syncEngine != null &&
          _syncEngine!.state.value != FlueraSyncState.error) {
        final cloudAdapter = _syncEngine!.adapter;

        if (cloudAdapter.supportsStrokeSharding) {
          // 🚀 SHARDED PATH — avoid full layer JSON serialization!
          // Only serialize metadata (layers without strokes). Stroke JSON is
          // built per-stroke from ProStroke objects, avoiding a 1MB+ temporary
          // allocation that was causing massive GC pressure on the UI thread.
          final cloudData = saveData.toJson();

          // Build layer metadata WITHOUT strokes (light — ~50KB)
          // 🚀 Uses toJsonMetadataOnly() — NEVER allocates stroke JSON.
          final strippedLayers =
              saveData.layers
                  .map((layer) => layer.toJsonMetadataOnly())
                  .toList();
          cloudData['layers'] = strippedLayers;

          _syncEngine!.requestSave(
            _canvasId,
            _FlueraCanvasScreenState._sanitizeForFirestore(cloudData),
          );

          // Build stroke tuples directly from layer data
          final strokeTuples = <(String, Map<String, dynamic>)>[];
          for (final layer in saveData.layers) {
            for (final stroke in layer.strokes) {
              strokeTuples.add((
                layer.id,
                _FlueraCanvasScreenState._sanitizeForFirestore(stroke.toJson()),
              ));
            }
          }
          if (strokeTuples.isNotEmpty) {
            cloudAdapter
                .saveStrokes(_canvasId, strokeTuples)
                .catchError((e) {});
          }
        } else {
          // Legacy: save everything in one document
          final cloudData = saveData.toJson();
          cloudData['layers'] = saveData.layers.map((l) => l.toJson()).toList();
          _syncEngine!.requestSave(
            _canvasId,
            _FlueraCanvasScreenState._sanitizeForFirestore(cloudData),
          );
        }
      }
    } catch (e, st) {
      debugPrint('💾 [SAVE-DEBUG] ❌ Save FAILED: $e');
      debugPrint('💾 [SAVE-DEBUG] ❌ Stack: $st');
      if (!_autoSaveErrorLogged) {
        _autoSaveErrorLogged = true;
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
          // 🛡️ SAVE GUARD: block paging from stubifying strokes during save.
          DrawingPainter.setSaveGuard(true);

          // 🐛 FIX: Restore paged-out stubs before encoding.
          final restoredForSave =
              await DrawingPainter.restorePagedStrokesForSave();
          if (restoredForSave.isNotEmpty) {
            for (final layer in saveData.layers) {
              for (final sn in layer.node.strokeNodes) {
                final full = restoredForSave[sn.stroke.id];
                if (full != null) {
                  sn.stroke = full;
                }
              }
              layer.node.invalidateStrokeCache();
            }
          }

          try {
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
          } finally {
            // POST-SAVE: Re-stub restored strokes to free RAM
            if (restoredForSave.isNotEmpty) {
              for (final layer in saveData.layers) {
                for (final sn in layer.node.strokeNodes) {
                  if (restoredForSave.containsKey(sn.stroke.id)) {
                    sn.stroke = sn.stroke.toStub();
                  }
                }
                layer.node.invalidateStrokeCache();
              }
            }
            DrawingPainter.setSaveGuard(false);
          }
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
      // 🚀 FIX: Use sharded path when supported — forceFirebaseSync was
      // previously bypassing sharding, saving ALL data in one document
      // which exceeds Firestore's 1MB limit with 300+ strokes.
      if (_syncEngine != null) {
        final cloudAdapter = _syncEngine!.adapter;
        final cloudData = saveData.toJson();

        if (cloudAdapter.supportsStrokeSharding) {
          // 🚀 Use toJsonMetadataOnly() — skips stroke serialization entirely
          cloudData['layers'] =
              saveData.layers.map((l) => l.toJsonMetadataOnly()).toList();
          await _syncEngine!.flush(
            _canvasId,
            _FlueraCanvasScreenState._sanitizeForFirestore(cloudData),
          );

          // Build stroke tuples directly from ProStroke objects (no full toJson)
          final strokeTuples = <(String, Map<String, dynamic>)>[];
          for (final layer in saveData.layers) {
            for (final stroke in layer.strokes) {
              strokeTuples.add((
                layer.id,
                _FlueraCanvasScreenState._sanitizeForFirestore(stroke.toJson()),
              ));
            }
          }
          if (strokeTuples.isNotEmpty) {
            await cloudAdapter.saveStrokes(_canvasId, strokeTuples);
          }
        } else {
          // Legacy: save everything in one document
          cloudData['layers'] = saveData.layers.map((l) => l.toJson()).toList();
          await _syncEngine!.flush(
            _canvasId,
            _FlueraCanvasScreenState._sanitizeForFirestore(cloudData),
          );
        }
      }
    } catch (e) {}
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
      if (!kIsWeb) {
        final localFile = File(img.imagePath);
        if (await localFile.exists()) continue;
      }

      downloadTasks.add(_downloadSingleAsset(img.id, img.imagePath));
    }

    if (downloadTasks.isEmpty) return;

    // Run all downloads in parallel (network handles concurrency)
    await Future.wait(downloadTasks);
  }

  /// Download a single asset from cloud and save locally.
  Future<void> _downloadSingleAsset(String assetId, String localPath) async {
    try {
      final bytes = await _syncEngine!.adapter.downloadAsset(
        _canvasId,
        assetId,
      );

      if (bytes != null) {
        if (!kIsWeb) {
          final localFile = File(localPath);
          await localFile.parent.create(recursive: true);
          await localFile.writeAsBytes(bytes, flush: true);
        }
        // 💾 Cache compressed bytes for instant reload after eviction
        _imageMemoryManager.cacheCompressedBytes(localPath, bytes);
      }
    } catch (e) {}
  }

  /// ☁️ Upload a single image asset to cloud storage.
  ///
  /// Returns the cloud URL on success, or `null` on failure.
  /// Used by `pickAndAddImage` and can be called for batch uploads.
  Future<String?> uploadImageAsset(String imageId, String filePath) async {
    if (_syncEngine == null) return null;

    try {
      if (kIsWeb) return null; // No file system on web
      final bytes = await File(filePath).readAsBytes();
      final url = await _syncEngine!.adapter.uploadAsset(
        _canvasId,
        imageId,
        bytes,
        mimeType: 'image/png',
      );
      return url;
    } catch (e) {
      return null;
    }
  }

  /// 🖼️ Capture a low-res snapshot of the current viewport for splash screen.
  ///
  /// **Strategy**: Uses the RepaintBoundary wrapping the canvas area
  /// to capture the current viewport at reduced resolution (~480px
  /// long side → ~50-100KB PNG).
  ///
  /// 🚀 PERF: Throttled to max once per 30s. Previously ran on every
  /// auto-save (every 2s), doing boundary.toImage() + PNG encoding
  /// each time — significant GPU + memory overhead.
  static int _lastSnapshotTimestamp = 0;
  static const _snapshotThrottleMs = 30000; // 30 seconds

  Future<void> _captureCanvasSnapshot(String canvasId) async {
    // 🚀 Throttle: skip if captured recently
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastSnapshotTimestamp < _snapshotThrottleMs) return;
    _lastSnapshotTimestamp = now;

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
    }
  }
}
