part of '../../fluera_canvas_screen.dart';

/// 📦 Lifecycle & Initialization — extracted from _FlueraCanvasScreenState
extension on _FlueraCanvasScreenState {
  /// ✨ Initialize GPU shader brushes
  Future<void> _initProShaders() async {
    final drawingModule = EngineScope.current.drawingModule;
    if (drawingModule != null) {
      await drawingModule.shaderBrushService.initialize();
    }
    // 🎯 dart:gpu low-level render pipeline (texture overlay PoC)
    GpuTextureService.instance.initialize();
  }

  // Tool state changes are handled by UnifiedToolController (ChangeNotifier)

  /// 🖼️ Load the background image from URL
  Future<void> _loadBackgroundImage() async {
    try {
      final NetworkImage provider = NetworkImage(widget.backgroundImageUrl!);
      final ImageStream stream = provider.resolve(const ImageConfiguration());
      final Completer<ui.Image> completer = Completer();

      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (ImageInfo info, bool _) {
          completer.complete(info.image);
          stream.removeListener(listener);
        },
        onError: (exception, stackTrace) {
          completer.completeError(exception);
          stream.removeListener(listener);
        },
      );

      stream.addListener(listener);

      final image = await completer.future;

      if (mounted) {
        setState(() {
          _backgroundImage = image;
        });

        // 🎯 Re-cenbetween the canvas sulle dimensioni of the image
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            final size = MediaQuery.of(context).size;
            // Passa le dimensioni of the image per centrare correttamente
            _canvasController.centerCanvas(size, canvasSize: _canvasSize);
          }
        });
      }
    } catch (e, stack) {
      EngineScope.current.errorRecovery.reportError(
        EngineError(
          severity: ErrorSeverity.transient,
          domain: ErrorDomain.network,
          source: '_FlueraCanvasScreenState._loadBackgroundImage',
          original: e,
          stack: stack,
        ),
      );
    }
  }

  /// 🎛️ Load brush settings persistenti dal servizio
  void _loadBrushSettings() {
    final service = EngineScope.current.drawingModule?.brushSettingsService;
    if (service == null) return;
    if (service.isInitialized) {
      setState(() {
        _brushSettings = service.settings;
      });
    } else {
      // Ascolta l'inizializzazione del servizio
      service.addListener(_onBrushSettingsServiceUpdated);
    }
  }

  /// 🎛️ Callback when the servizio aggiorna i settings
  void _onBrushSettingsServiceUpdated() {
    if (mounted) {
      setState(() {
        _brushSettings =
            EngineScope.current.drawingModule?.brushSettingsService.settings ??
            _brushSettings;
      });
    }
  }

  /// 🚀 SPLASH SCREEN PIPELINE — runs ALL heavy initialization in parallel.
  ///
  /// This is the core of the loading screen optimization. Instead of running
  /// shader compilation, isolate spawn, texture decode, and data I/O
  /// sequentially (total = sum of all), we run them all via `Future.wait()`
  /// so total time = max(slowest one).
  ///
  /// The loading overlay is visible during this entire operation.
  Future<void> _initializeCanvas() async {
    // 🖼️ EAGER: Load splash snapshot BEFORE heavy init so it's visible
    // immediately on the loading screen. This is a tiny BLOB read (~50KB).
    await _loadSplashSnapshot();

    // These are all independent — run them in parallel
    await Future.wait([
      // 1. GPU shader compilation (~50-200ms on first run)
      _initProShaders(),

      // 2. Persistent isolate spawn (~2-5ms)
      SaveIsolateService.instance.initialize(),

      // 3. Texture preloading (decodes brush textures)
      Future(() => BrushTexture.preloadAll()),

      // 4. Canvas data load from SQLite (I/O bound, variable time)
      _loadCanvasData(),

      // 5. 🎤 Load saved recordings from SQLite
      _loadSavedRecordings(),
    ]);

    // 🖼️ Wire staggered thumbnail queue callback
    _wireImageMemoryManagerCallbacks();

    // 🕐 Start proactive image eviction after init completes
    _imageEvictionTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _runImageEvictionCycle(),
    );
  }

  /// 🧠 Proactive image eviction cycle.
  ///
  /// Runs every 5s. Features:
  /// - Proactive eviction (off-viewport > 5s)
  /// - Auto-reload when evicted images scroll back into view
  /// - Multi-level LOD (256/512/1024/full based on zoom)
  /// - Staggered thumbnail queue (serial processing)
  /// - Adaptive budget (adjusts maxImages based on RSS)
  void _runImageEvictionCycle() {
    if (!mounted || _imageElements.isEmpty) return;

    // 📏 Adaptive budget: adjust maxImages based on current RSS
    _imageMemoryManager.adjustBudgetFromMemory();

    // Compute viewport rect in canvas coordinates
    final scale = _canvasController.scale;
    final offset = _canvasController.offset;
    final ctx = context;
    final size = MediaQuery.of(ctx).size;
    final viewportRect = Rect.fromLTWH(
      -offset.dx / scale,
      -offset.dy / scale,
      size.width / scale,
      size.height / scale,
    );

    // 🔮 PREDICTIVE: Track scroll velocity and expand viewport in scroll direction
    _imageMemoryManager.updateScrollVelocity(offset);
    final predictiveViewport = _imageMemoryManager.getPredictiveViewport(
      viewportRect,
    );

    // Margin + predictive expansion
    const margin = 500.0;
    final expandedViewport = predictiveViewport.inflate(margin);

    // Find which image paths are currently visible
    final visiblePaths = <String>{};
    for (final img in _imageElements) {
      final loadedImg = _loadedImages[img.imagePath];
      final w = loadedImg?.width.toDouble() ?? 200.0;
      final h = loadedImg?.height.toDouble() ?? 150.0;
      final halfW = w * img.scale / 2;
      final halfH = h * img.scale / 2;
      final imgRect = Rect.fromCenter(
        center: img.position,
        width: halfW * 2,
        height: halfH * 2,
      );
      if (expandedViewport.overlaps(imgRect)) {
        visiblePaths.add(img.imagePath);
      }
    }

    // Run proactive eviction (off-viewport > 5s → dispose, keep compressed)
    if (_loadedImages.isNotEmpty) {
      final evicted = _imageMemoryManager.proactiveEviction(
        _loadedImages,
        visiblePaths,
      );
      if (evicted.isNotEmpty) {
        debugPrint(
          '[🧠 EVICT] Evicted ${evicted.length} images '
          '(budget: ${_imageMemoryManager.maxImages}, '
          'compressed cache: ${_imageMemoryManager.stats['compressedCacheEntries']})',
        );
        for (final path in evicted) {
          for (final img in _imageElements) {
            if (img.imagePath == path) {
              ImagePainter.invalidateImageCache(img.id);
            }
          }
        }
        _thumbnailPaths.removeAll(evicted);
        if (mounted) setState(() => _imageVersion++);
      }
    }

    // Reload evicted images that are now back in viewport
    for (final img in _imageElements) {
      if (visiblePaths.contains(img.imagePath) &&
          !_loadedImages.containsKey(img.imagePath)) {
        debugPrint(
          '[🧠 RELOAD] ${img.imagePath.split('/').last} '
          '(cached bytes: ${_imageMemoryManager.hasCompressedBytes(img.imagePath)})',
        );
        _preloadImage(
          img.imagePath,
          storageUrl: img.storageUrl,
          thumbnailUrl: img.thumbnailUrl,
        );
      }
    }

    // 🖼️ MULTI-LEVEL LOD: Determine optimal resolution tier for current zoom
    final optimalTier = _imageMemoryManager.getOptimalLodTier(scale);

    if (optimalTier != null) {
      // Zoom is low — downscale visible images to optimal LOD tier
      for (final img in _imageElements) {
        final path = img.imagePath;
        if (!visiblePaths.contains(path)) continue;
        if (!_loadedImages.containsKey(path)) continue;

        final currentLod = _imageMemoryManager.getCurrentLodLevel(path);
        if (currentLod == optimalTier.name) continue; // Already at correct LOD

        final currentImage = _loadedImages[path]!;
        // Only downscale if the image is large enough to benefit
        if (currentImage.width <= optimalTier.maxDimension &&
            currentImage.height <= optimalTier.maxDimension) {
          _imageMemoryManager.setLodLevel(path, optimalTier.name);
          continue;
        }

        // 🔄 DOUBLE-BUFFER: Skip if a LOD swap is already in progress
        if (_imageMemoryManager.isLodSwapPending(path)) continue;

        // Use compressed cache for staggered thumbnail (old image stays visible)
        final bytes = _imageMemoryManager.getCompressedBytes(path);
        if (bytes != null) {
          _imageMemoryManager.markLodSwapPending(path);
          _imageMemoryManager.enqueueThumbnail(
            path,
            bytes,
            optimalTier.maxDimension,
          );
        }
      }
    } else if (_thumbnailPaths.isNotEmpty) {
      // Zoom is back to normal (above highest LOD threshold) — reload full-res
      final toUpgrade = _thumbnailPaths.toList();
      for (final path in toUpgrade) {
        if (_loadedImages.containsKey(path)) {
          debugPrint('[🖼️ UPGRADE] Full-res: ${path.split('/').last}');
          _thumbnailPaths.remove(path);
          _imageMemoryManager.setLodLevel(path, null);
          final imgEl =
              _imageElements.where((e) => e.imagePath == path).firstOrNull;
          if (imgEl != null) {
            final oldThumb = _loadedImages.remove(path);
            oldThumb?.dispose();
            _preloadImage(
              path,
              storageUrl: imgEl.storageUrl,
              thumbnailUrl: imgEl.thumbnailUrl,
            );
          }
        } else {
          _thumbnailPaths.remove(path);
          _imageMemoryManager.setLodLevel(path, null);
        }
      }
    }
  }

  /// 🖼️ Wire up the staggered thumbnail callback from ImageMemoryManager.
  ///
  /// Called once during init to connect the serial thumbnail queue
  /// to the canvas state (swap decoded thumbnail into _loadedImages).
  void _wireImageMemoryManagerCallbacks() {
    _imageMemoryManager.onThumbnailReady = (path, thumbnail) {
      if (!mounted) {
        thumbnail.dispose();
        return;
      }

      // 🔄 DOUBLE-BUFFER: New image is decoded → swap atomically
      final oldImage = _loadedImages[path];
      _loadedImages[path] = thumbnail;
      _thumbnailPaths.add(path);
      _imageMemoryManager.markLodSwapComplete(path);
      oldImage?.dispose(); // Old stays visible until this point

      // Update LOD level tracking
      final currentLod = _imageMemoryManager.getCurrentLodLevel(path);
      if (currentLod != null) {
        _imageMemoryManager.setLodLevel(path, currentLod);
      }

      // Invalidate per-image Picture cache
      for (final img in _imageElements) {
        if (img.imagePath == path) {
          ImagePainter.invalidateImageCache(img.id);
        }
      }

      debugPrint(
        '[🖼️ LOD] Swapped to ${thumbnail.width}x${thumbnail.height}: '
        '${path.split('/').last}',
      );

      if (mounted) setState(() => _imageVersion++);
    };
  }

  /// 🖼️ Load the splash screen snapshot from storage.
  ///
  /// Called at the very start of `_initializeCanvas` so the snapshot
  /// appears on the loading overlay before any heavy init starts.
  Future<void> _loadSplashSnapshot() async {
    try {
      final adapter = _config.storageAdapter;
      if (adapter == null) return;

      // Ensure adapter is initialized (may already be from a previous run)
      await adapter.initialize();

      final png = await adapter.loadSnapshot(_canvasId);
      if (png != null && mounted) {
        setState(() {
          _splashSnapshot = png;
        });
      }
    } catch (e) {
      // Non-critical — the loading screen will show logo fallback
      debugPrint('[Snapshot] Load failed: $e');
    }
  }

  /// 🆕 Load dati canvas — LOCAL FIRST per display istantaneo
  Future<void> _loadCanvasData() async {
    _isLoading = true; // 🔄 Disable auto-save during loading
    bool loadedFromLocal = false;

    try {
      Map<String, dynamic>? data;

      print(
        '🎨 [ProCanvasScreen] _loadCanvasData: canvasId=$_canvasId, infiniteCanvasId=${widget.infiniteCanvasId}, nodeId=${widget.nodeId}',
      );

      // 🚀 1. LOCAL FIRST: prefer storageAdapter over legacy callback
      if (_config.storageAdapter != null) {
        await _config.storageAdapter!.initialize();

        // 🎤 Initialize RecordingStorageService with shared DB
        if (_config.storageAdapter is SqliteStorageAdapter) {
          final sqliteAdapter = _config.storageAdapter as SqliteStorageAdapter;
          RecordingStorageService.instance.initialize(sqliteAdapter.database);
        }

        data = await _config.storageAdapter!.loadCanvas(_canvasId);
        print(
          '🎨 [ProCanvasScreen] StorageAdapter load result: ${data != null ? "FOUND (${data.keys.length} keys)" : "NULL"}',
        );
      } else {
        data = await _config.onLoadCanvas?.call(_canvasId);
        print(
          '🎨 [ProCanvasScreen] Legacy callback load result: ${data != null ? "FOUND (${data.keys.length} keys)" : "NULL"}',
        );
      }

      // 2. ☁️ Cloud fallback: load from cloud when no local data
      if (data == null && _hasCloudSync && _syncEngine != null) {
        try {
          data = await _syncEngine!.loadCanvas(_canvasId);
          if (data != null) {
            debugPrint(
              '☁️ No local data — loaded from cloud '
              '(${data.keys.length} keys)',
            );

            // 🚀 SHARDING FIX: Reassemble strokes from sub-collection
            // into layers. Without this, new users see empty canvas because
            // the main document's layers have no strokes when sharded.
            final adapter = _syncEngine!.adapter;
            if (adapter.supportsStrokeSharding) {
              final strokesByLayer = await adapter.loadStrokes(_canvasId);
              final layers = data['layers'] as List?;
              if (layers != null && strokesByLayer.isNotEmpty) {
                for (final layerData in layers) {
                  if (layerData is Map) {
                    final layerId = layerData['id'] as String?;
                    if (layerId != null &&
                        strokesByLayer.containsKey(layerId)) {
                      layerData['strokes'] = strokesByLayer[layerId];
                    }
                  }
                }
                debugPrint(
                  '☁️ Reassembled ${strokesByLayer.values.fold<int>(0, (a, b) => a + b.length)} '
                  'sharded strokes into ${strokesByLayer.length} layers',
                );
              }
            }
          } else {
            debugPrint('☁️ No local data & no cloud data — fresh canvas');
          }
        } catch (e) {
          debugPrint('☁️ Cloud load failed: $e');
        }
      } else if (data == null) {
        debugPrint('🎨 No local data & no cloud sync — fresh canvas');
      }

      if (data != null) {
        loadedFromLocal = true;
      }

      if (data != null && mounted) {
        await _applyCanvasData(data);

        // ☁️ Download images/PDFs that are in cloud but missing locally
        // (runs in background — non-blocking)
        downloadMissingAssets();
      }
    } catch (e) {
    } finally {
      // 🔄 Reveal canvas: setState triggers AnimatedOpacity fade-out
      if (mounted) {
        // 🎨 FORCE CACHE INVALIDATION: the stroke cache and layer caches
        // are EngineScope singletons that may retain stale state from the
        // empty-canvas painter created before data was loaded.
        DrawingPainter.invalidateLayerCaches();
        if (EngineScope.hasScope) {
          EngineScope.current.renderCacheScope.strokeCache.invalidateCache();
        }

        setState(() {
          _isLoading = false;
        });

        // 🏎️ Auto-enable performance overlay in debug builds
        if (kDebugMode) {
          CanvasPerformanceMonitor.instance.setEnabled(true);
        }

        // 🎨 FORCE REPAINT: The DrawingPainter repaints via two mechanisms:
        // 1. ListenableBuilder(listenable: _layerController) → widget rebuild
        // 2. super(repaint: controller) → direct repaint signal
        //
        // After loading, mechanism (1) may fire while the overlay is still
        // opaque, and the rendering system may optimize away the paint.
        // We use BOTH mechanisms with a delay to guarantee the painter
        // renders with the loaded data after the overlay fades out.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          // Bump scene graph version to invalidate any stale caches
          _layerController.sceneGraph.bumpVersion();
          // Force widget rebuild (creates new DrawingPainter with fresh data)
          setState(() {});
          // Direct repaint signal to the DrawingPainter via its repaint listenable
          _canvasController.markNeedsPaint();
        });
      } else {
        _isLoading = false;
      }
    }

    // 🔄 3. BACKGROUND SYNC: If loaded from local, sync Firebase in background
    // per recuperare eventuali modifiche remote da collaboratori
    if (loadedFromLocal && mounted) {
      _syncFirebaseInBackground();
    }
  }

  /// 🔄 Synchronize cloud data in background after local loading.
  ///
  /// Loads data from cloud and applies it ONLY if more recent than local.
  /// Does not block the UI — the user can already draw.
  /// 🐛 FIX C: Reentrancy guard prevents double-apply on rapid reconnect.
  static bool _isSyncingFirebase = false;
  Future<void> _syncFirebaseInBackground() async {
    // 🐛 FIX C: Prevent concurrent sync (rapid reconnect → double apply)
    if (_isSyncingFirebase) {
      debugPrint('☁️ Background sync: already in progress, skipping');
      return;
    }
    _isSyncingFirebase = true;
    try {
      await _syncFirebaseInBackgroundImpl();
    } finally {
      _isSyncingFirebase = false;
    }
  }

  Future<void> _syncFirebaseInBackgroundImpl() async {
    // 💎 TIER GATE: Only Plus/Pro users sync canvas from the cloud
    if (!_hasCloudSync) return;
    if (_syncEngine == null) return;

    try {
      final cloudData = await _syncEngine!.loadCanvas(_canvasId);
      if (cloudData == null) return;

      // 🔒 Conflict detection: compare timestamps
      // Firestore stores Timestamp objects, not raw ints — handle both.
      final rawUpdatedAt = cloudData['updatedAt'];
      final cloudUpdatedAt =
          rawUpdatedAt is int
              ? rawUpdatedAt
              : (rawUpdatedAt != null
                  ? (rawUpdatedAt as dynamic).millisecondsSinceEpoch as int?
                  : null);
      final localUpdatedAt = _lastLocalSaveTimestamp;

      if (cloudUpdatedAt != null && localUpdatedAt != null) {
        if (cloudUpdatedAt <= localUpdatedAt) {
          debugPrint(
            '☁️ Background sync: local is up-to-date '
            '(local=$localUpdatedAt, cloud=$cloudUpdatedAt)',
          );
          return; // Local is newer or same — nothing to do
        }
      }

      // Cloud data is newer — apply it
      if (mounted) {
        debugPrint('☁️ Background sync: applying newer cloud data');

        // 🚀 SHARDING: Reassemble strokes from sub-collection into layers
        final adapter = _syncEngine!.adapter;
        if (adapter.supportsStrokeSharding) {
          final strokesByLayer = await adapter.loadStrokes(_canvasId);
          final rawLayers = cloudData['layers'];
          final layers = rawLayers is List ? rawLayers : null;
          if (layers != null && strokesByLayer.isNotEmpty) {
            for (final layerData in layers) {
              if (layerData is Map) {
                final layerId = layerData['id'] as String?;
                if (layerId != null && strokesByLayer.containsKey(layerId)) {
                  layerData['strokes'] = strokesByLayer[layerId];
                }
              }
            }
          }
        }

        await _applyCanvasData(cloudData);
        downloadMissingAssets();
      }
    } catch (e, st) {
      debugPrint('☁️ Background sync failed: $e');
      debugPrint('☁️ Stack trace: $st');
    }
  }

  /// 🛠️ Applica dati canvas alla UI (estratto per riuso)
  Future<void> _applyCanvasData(Map<String, dynamic> data) async {
    // 🛠️ APPLICATION OF DATA WITH IMMEDIATE SETSTATE
    setState(() {
      // 🆕 Load titolo (if present nel salvataggio)
      final savedTitle = data['title'] as String?;
      if (savedTitle != null && savedTitle.isNotEmpty) {
        _noteTitle = savedTitle;
      }

      // Load text elements
      final rawText = data['textElements'];
      final textJson = rawText is List ? rawText : null;
      if (textJson != null) {
        _digitalTextElements.clear();
        _digitalTextElements.addAll(
          textJson
              .map(
                (t) => DigitalTextElement.fromJson(
                  Map<String, dynamic>.from(t as Map),
                ),
              )
              .toList(),
        );
      }

      // Load image elements
      final rawImages = data['imageElements'];
      final imageJson = rawImages is List ? rawImages : null;
      if (imageJson != null) {
        _imageElements.clear();
        _imageElements.addAll(
          imageJson
              .map(
                (i) =>
                    ImageElement.fromJson(Map<String, dynamic>.from(i as Map)),
              )
              .toList(),
        );
        _imageVersion++;
        _rebuildImageSpatialIndex();
      }

      // 📌 Load recording pins
      final rawPins = data['recordingPins'];
      final pinsJson = rawPins is List ? rawPins : null;
      if (pinsJson != null) {
        _recordingPins.clear();
        _recordingPins.addAll(
          pinsJson
              .map(
                (p) =>
                    RecordingPin.fromJson(Map<String, dynamic>.from(p as Map)),
              )
              .toList(),
        );
      }

      // Load settings — supports both:
      //   1. Flat keys from SqliteStorageAdapter (backgroundColor, paperType, etc.)
      //   2. Legacy nested 'settings' object from cloud/Firestore format
      final settingsData = data['settings'] as Map<dynamic, dynamic>?;
      final settings =
          settingsData != null ? Map<String, dynamic>.from(settingsData) : null;

      // Read each setting from flat key first, then fall back to nested settings
      final bgColor = data['backgroundColor'] ?? settings?['backgroundColor'];
      if (bgColor != null) {
        if (bgColor is String) {
          try {
            if (bgColor.startsWith('0x') || bgColor.startsWith('0X')) {
              _canvasBackgroundColor = Color(int.parse(bgColor));
            } else if (bgColor.length == 8 && !bgColor.contains('-')) {
              _canvasBackgroundColor = Color(int.parse(bgColor, radix: 16));
            } else {
              _canvasBackgroundColor = Color(int.parse(bgColor));
            }
          } catch (e) {
            _canvasBackgroundColor = Colors.white;
          }
        } else if (bgColor is int) {
          _canvasBackgroundColor = Color(bgColor);
        }
      }

      _paperType =
          data['paperType'] as String? ??
          settings?['paperType'] as String? ??
          'blank';

      // 📐 Load saved guides
      final guidesJson =
          data['guides'] as Map<String, dynamic>? ??
          settings?['guides'] as Map<String, dynamic>?;
      if (guidesJson != null) {
        _rulerGuideSystem.loadFromJson(guidesJson);
      }

      // 🎛️ Restore design variable state
      final varCollsJson = data['variableCollections'] as List<dynamic>?;
      if (varCollsJson != null) {
        _variableCollections.clear();
        for (final cJson in varCollsJson) {
          _variableCollections.add(
            VariableCollection.fromJson(
              Map<String, dynamic>.from(cJson as Map),
            ),
          );
        }
        // Re-sync resolver with restored collections
        for (final c in _variableCollections) {
          _variableResolver.addCollection(c);
        }
      }
      final varBindingsJson =
          data['variableBindings'] as Map<dynamic, dynamic>?;
      if (varBindingsJson != null) {
        _variableBindings.loadFromJson(
          Map<String, dynamic>.from(varBindingsJson),
        );
      }
      final varModesJson =
          data['variableActiveModes'] as Map<dynamic, dynamic>?;
      if (varModesJson != null) {
        _variableResolver.loadActiveModes(
          Map<String, dynamic>.from(varModesJson),
        );
      }
    });

    // 🎯 Load layers AFTER setState to avoid notifications during build
    final layersJson = data['layers'] as List<dynamic>?;
    if (layersJson != null && layersJson.isNotEmpty) {
      _layerController.clearAllAndLoadLayers(
        layersJson
            .map(
              (l) => CanvasLayer.fromJson(Map<String, dynamic>.from(l as Map)),
            )
            .toList(),
      );
    }

    // 🎯 Set active layer AFTER loading layers
    final activeLayerIdFromData = data['activeLayerId'] as String?;
    final settingsData2 = data['settings'] as Map<dynamic, dynamic>?;
    final activeLayerIdFromSettings =
        settingsData2 != null
            ? Map<String, dynamic>.from(settingsData2)['activeLayerId']
                as String?
            : null;
    final activeLayerId = activeLayerIdFromData ?? activeLayerIdFromSettings;
    if (activeLayerId != null) {
      _layerController.selectLayer(activeLayerId);
    }

    // Pre-carica immagini in background (non bloccante)
    // 🔧 FIX: Sync _imageElements into layers if they're missing
    // (images from Firestore 'imageElements' array may not be in the binary checkpoint layers)
    final layerImageIds = <String>{};
    for (final layer in _layerController.layers) {
      for (final img in layer.images) {
        layerImageIds.add(img.id);
      }
    }
    debugPrint(
      '[🖼️ RESTORE] Found ${_imageElements.length} images to preload',
    );
    for (final imageElement in _imageElements) {
      if (!layerImageIds.contains(imageElement.id)) {
        // Image exists in _imageElements but not in any layer — add to active layer
        final wasTracking = _layerController.enableDeltaTracking;
        _layerController.enableDeltaTracking =
            false; // Don't record delta for init sync
        _layerController.addImage(imageElement);
        _layerController.enableDeltaTracking = wasTracking;
      }
    }

    // 🚀 #2: Batch preload — all images in parallel instead of sequential
    if (_imageElements.isNotEmpty) {
      await Future.wait(
        _imageElements.map(
          (img) => _preloadImage(
            img.imagePath,
            storageUrl: img.storageUrl,
            thumbnailUrl: img.thumbnailUrl,
          ),
        ),
      );
    }

    // 🛠️ FORCE FINAL REBUILD to ensure everything is rendered
    if (mounted) {
      setState(() {
        // Dati caricati completamente - forza rebuild finale
      });
    }

    // 📄 Restore PDF documents from saved metadata
    final pdfDocsList = data['pdfDocuments'] as List<dynamic>?;
    if (pdfDocsList != null && pdfDocsList.isNotEmpty) {
      await _restorePdfDocuments(pdfDocsList);
    }

    // 🧮 Restore scene nodes (LatexNode, TabularNode) from JSON sidecar
    final sceneNodesList = data['sceneNodes'] as List<dynamic>?;
    if (sceneNodesList != null && sceneNodesList.isNotEmpty) {
      for (final entry in sceneNodesList) {
        try {
          final map = Map<String, dynamic>.from(entry as Map);
          final layerId = map['layerId'] as String;
          final nodeJson = Map<String, dynamic>.from(map['node'] as Map);

          final restoredNode = CanvasNodeFactory.fromJson(nodeJson);

          final targetLayer = _layerController.layers.firstWhere(
            (l) => l.id == layerId,
            orElse: () => _layerController.layers.first,
          );
          targetLayer.node.add(restoredNode);
        } catch (e) {
          debugPrint('[SceneNodes] Error restoring node: $e');
        }
      }
      _layerController.sceneGraph.bumpVersion();
      if (mounted) setState(() {});
    }
  }

  ///  Callback called when the layer controller notifica modifiche
  void _onLayerChanged() {
    // 🧭 Update navigation bounds tracker — DEFERRED to avoid re-entrant
    // scene graph rebuild during the LayerController notification cycle.
    // (sceneGraph getter triggers _rebuildSceneGraphImpl → addLayer →
    //  bumpVersion + notifyNodeAdded, which corrupts state if called
    //  synchronously inside _onLayerChanged.)
    //
    // 🚀 THROTTLE: Skip during active drawing — the current in-progress
    // stroke isn't in the layer yet (it's in CurrentStrokePainter), so
    // updating the minimap mid-stroke is wasted work. The update fires
    // on stroke end when _isDrawingNotifier becomes false.
    if (!_isDrawingNotifier.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _contentBoundsTracker.update();
      });
    }

    // 🔧 FIX ZOOM LAG: Update list cache
    _refreshCachedLists();

    // 🌊 REFLOW: Rebuild cluster cache for the active layer
    // Skip during active drag — clusters don't change, only positions do.
    if (_clusterDetector != null && !_lassoTool.isDragging) {
      _rebuildClusterCache();
    }

    // Auto-save only if not loading
    if (!_isLoading) {
      _autoSaveCanvas();
    }
  }

  /// 🌊 Rebuild the reflow cluster cache from the active layer.
  void _rebuildClusterCache() {
    if (_clusterDetector == null) return;

    final activeLayer = _layerController.layers.firstWhere(
      (l) => l.id == _layerController.activeLayerId,
      orElse: () => _layerController.layers.first,
    );

    _clusterCache = _clusterDetector!.detect(
      strokes: activeLayer.strokes,
      shapes: activeLayer.shapes,
      texts: activeLayer.texts,
      images: activeLayer.images,
    );

    // 🔑 FIX: Cluster bounds come from raw ProStroke data, which doesn't
    // reflect CanvasNode.translate() offsets applied by reflow. Correct each
    // cluster's bounds using the first stroke node's actual scene-graph offset.
    final layerNode = activeLayer.node;
    int corrected = 0;
    for (final cluster in _clusterCache) {
      if (cluster.strokeIds.isEmpty) continue;
      // Use first stroke's node to get translation offset
      final node = layerNode.findChild(cluster.strokeIds.first);
      if (node == null) continue;
      final tx = node.localTransform[12]; // dx
      final ty = node.localTransform[13]; // dy
      if (tx != 0.0 || ty != 0.0) {
        final offset = Offset(tx, ty);
        cluster.bounds = cluster.bounds.shift(offset);
        cluster.centroid = cluster.centroid + offset;
        corrected++;
      }
    }
    if (corrected > 0) {
      print(
        '🌊 REFLOW: Corrected $corrected/${_clusterCache.length} cluster bounds by node transform',
      );
    }

    _lassoTool.reflowController?.updateClusters(_clusterCache);
  }

  /// 🔧 Update le liste cachate da _layerController
  void _refreshCachedLists() {
    // 🎬 Durante Time Travel, le strokes vengono dal engine, non dal controller
    if (_isTimeTravelMode && _timeTravelEngine != null) return;

    _cachedAllShapes = _layerController.getAllVisibleShapes();

    // 🖼️ Sync images from layers (handles add, update, and remove from remote deltas)
    final previousCount = _imageElements.length;
    final layerImageIds = <String>{};
    for (final layer in _layerController.layers) {
      for (final img in layer.images) {
        layerImageIds.add(img.id);
        final existingIndex = _imageElements.indexWhere((e) => e.id == img.id);
        if (existingIndex == -1) {
          // New image from remote delta
          _imageElements.add(img);
        } else {
          // Update existing image (position, scale, etc. from remote delta)
          _imageElements[existingIndex] = img;
        }
      }
    }
    // Remove images that were deleted remotely
    _imageElements.removeWhere(
      (e) =>
          layerImageIds.isNotEmpty &&
          !layerImageIds.contains(e.id) &&
          _layerController.layers.isNotEmpty,
    );

    // 🧠 Cache coherency: if images changed, bump version + rebuild R-tree + prune cache
    if (_imageElements.length != previousCount || layerImageIds.isNotEmpty) {
      _imageVersion++;
      _rebuildImageSpatialIndex();
      // 🗑️ Prune per-image cache entries for deleted images
      ImagePainter.pruneCache(_imageElements.map((e) => e.id).toSet());
    }

    // 🚀 DYNAMIC CANVAS: Expand if content exceeds 50% of size
    _expandCanvasIfNeeded();
  }

  /// 🚀 Espande il canvas in TUTTE e 4 le direzioni:
  /// - Right/Bottom: doubles size when content > 80%
  /// - Left/Top: shifts ALL coordinates and compensates controller offset
  ///
  /// Guarded: does NOT expand during initial loading.
  void _expandCanvasIfNeeded() {
    if (_isLoading || _isImageEditFromInfiniteCanvas) return;

    double maxX = 0, maxY = 0;

    final allStrokes = _layerController.getAllVisibleStrokes();
    for (final stroke in allStrokes) {
      final bounds = stroke.bounds;
      if (bounds.right.abs() > maxX) maxX = bounds.right.abs();
      if (bounds.bottom.abs() > maxY) maxY = bounds.bottom.abs();
      if (bounds.left.abs() > maxX) maxX = bounds.left.abs();
      if (bounds.top.abs() > maxY) maxY = bounds.top.abs();
    }

    for (final shape in _cachedAllShapes) {
      for (final p in [shape.startPoint, shape.endPoint]) {
        if (p.dx.abs() > maxX) maxX = p.dx.abs();
        if (p.dy.abs() > maxY) maxY = p.dy.abs();
      }
    }

    for (final img in _imageElements) {
      if ((img.position.dx + 500).abs() > maxX) {
        maxX = (img.position.dx + 500).abs();
      }
      if ((img.position.dy + 500).abs() > maxY) {
        maxY = (img.position.dy + 500).abs();
      }
    }

    // SizedBox must cover the content in all directions
    // We use double the max extent (to cover ±maxX, ±maxY)
    final neededW = maxX * 2 + 1000; // margine
    final neededH = maxY * 2 + 1000;

    bool changed = false;
    double newW = _dynamicCanvasSize.width;
    double newH = _dynamicCanvasSize.height;

    // Espansione graduale: incrementi del 50% (non raddoppio brusco)
    while (neededW > newW * 0.85) {
      newW *= 1.5;
      changed = true;
    }
    while (neededH > newH * 0.85) {
      newH *= 1.5;
      changed = true;
    }

    if (changed) {
      _dynamicCanvasSize = Size(newW, newH);
      debugPrint(
        '🔲 CANVAS EXPAND: ${newW.toInt()}x${newH.toInt()} '
        '(maxExtent=${maxX.toInt()},${maxY.toInt()})',
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
  }

  /// 🖥️ Rileva capability display e configura rendering adattivo
  Future<void> _detectDisplayCapabilitiesAndConfigure() async {
    try {
      // Detect refresh rate of the display
      _displayCapabilities = await DisplayCapabilitiesDetector.detect();

      // Genera config adattiva basata su refresh rate
      _renderingConfig = AdaptiveRenderingConfig.forRefreshRate(
        _displayCapabilities!.refreshRate,
      );

      // 🚀 If 120Hz+, initialize raw input processor
      if (_displayCapabilities!.refreshRate.value >= 120) {
        _rawInputProcessor120Hz = RawInputProcessor120Hz(
          onPointsUpdated: (points) {
            // 🚀 PERFORMANCE: Set riferimento + notifica repaint
            _currentStrokeNotifier.setStroke(points);
            _currentStrokeNotifier.forceRepaint();
            // No debouncer notification in 120Hz mode (zero overhead)
          },
        );
      }

      // Riconfigura drawing handler esistente con nuove impostazioni
      if (_renderingConfig != null) {
        _drawingHandler.enableOneEuroFilter =
            _renderingConfig!.enableOneEuroFilter;
      }
    } catch (e) {
      // Fallback a 60Hz
      _renderingConfig = AdaptiveRenderingConfig.forRefreshRate(
        RefreshRate.hz60,
      );
    }
  }

  /// 🏗️ Update il context del tool bridge with the current state of the canvas
  void _updateToolBridgeContext() {
    if (_toolSystemBridge == null) return;

    // Get dimensioni viewport
    final viewportSize = MediaQuery.of(context).size;

    _toolSystemBridge!.setCanvasContext(
      canvasId: _canvasId,
      scale: _canvasController.scale,
      viewOffset: _canvasController.offset,
      viewportSize: viewportSize,
    );
  }

  /// 🖼️ Pre-carica immagine da path (con fallback a storageUrl per sync remoto)
  /// Images are downscaled to max 2048px to prevent OOM
  /// When thumbnailUrl is available, loads thumbnail first for instant preview,
  /// then swaps to full-res in the background (progressive loading).
  Future<void> _preloadImage(
    String imagePath, {
    String? storageUrl,
    String? thumbnailUrl,
  }) async {
    if (_loadedImages.containsKey(imagePath)) return;

    // 🚀 FAST PATH: If compressed bytes are cached from a previous eviction,
    // decode from memory (~5ms) instead of reading from disk (~50ms).
    final cachedBytes = _imageMemoryManager.getCompressedBytes(imagePath);
    if (cachedBytes != null) {
      debugPrint(
        '[🖼️ PRELOAD] ⚡ Fast reload from compressed cache: ${imagePath.split('/').last}',
      );
      final image = await _decodeImageCapped(cachedBytes);
      if (mounted && image != null) {
        setState(() {
          _loadedImages[imagePath] = image;
          _imageVersion++;
          _rebuildImageSpatialIndex();
        });
        _imageMemoryManager.markAccessed(imagePath);
        _stopLoadingPulseIfDone();
      }
      return;
    }

    debugPrint(
      '[🖼️ PRELOAD] imagePath=$imagePath, '
      'storageUrl=${storageUrl?.substring(0, (storageUrl.length).clamp(0, 60))}, '
      'thumbnailUrl=${thumbnailUrl != null ? "set" : "null"}',
    );

    try {
      // 🚀 ISOLATE I/O: Read file bytes on background isolate (zero UI jank)
      final bytes = await ImageMemoryManager.readFileOnIsolate(imagePath);
      if (bytes != null) {
        debugPrint(
          '[🖼️ PRELOAD] ✅ Loaded via isolate: ${imagePath.split('/').last}',
        );
        // 💾 Cache compressed bytes for instant reload after eviction
        _imageMemoryManager.cacheCompressedBytes(imagePath, bytes);
        final image = await _decodeImageCapped(bytes);
        if (mounted && image != null) {
          // 📏 #5: Cache dimensions for placeholder sizing
          _imageMemoryManager.cacheImageDimensions(
            imagePath,
            image.width,
            image.height,
          );
          setState(() {
            _loadedImages[imagePath] = image;
            _imageVersion++;
            _rebuildImageSpatialIndex();
          });
          _imageMemoryManager.markAccessed(imagePath);
          _stopLoadingPulseIfDone();
        }
        return;
      }

      debugPrint(
        '[🖼️ PRELOAD] ❌ Local file NOT found, '
        'storageUrl=${storageUrl != null ? "available" : "NULL!"}',
      );

      // 🌐 Local file not found — try downloading from storageUrl
      if (storageUrl != null && storageUrl.isNotEmpty) {
        _startLoadingPulse();

        // 📸 PROGRESSIVE LOADING: load thumbnail first for instant preview
        if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
          try {
            final thumbResponse = await NetworkAssetBundle(
              Uri.parse(thumbnailUrl),
            ).load(thumbnailUrl);
            final thumbBytes = thumbResponse.buffer.asUint8List();
            final thumbImage = await _decodeImageCapped(thumbBytes);
            if (mounted &&
                thumbImage != null &&
                !_loadedImages.containsKey(imagePath)) {
              setState(() {
                _loadedImages[imagePath] = thumbImage;
                _imageVersion++;
                _rebuildImageSpatialIndex();
              });
              _imageMemoryManager.markAccessed(imagePath);
            }
          } catch (_) {
            // Thumbnail failed — no problem, full image will load
          }
        }

        // 📸 Load full-res image (replaces thumbnail if one was loaded)
        final response = await NetworkAssetBundle(
          Uri.parse(storageUrl),
        ).load(storageUrl);
        final bytes = response.buffer.asUint8List();

        // 💾 FIX #1: Persist downloaded bytes to local disk.
        // Without this, every restart re-downloads from cloud.
        try {
          final localFile = File(imagePath);
          await localFile.parent.create(recursive: true);
          await localFile.writeAsBytes(bytes, flush: true);
          debugPrint(
            '[🖼️ PRELOAD] 💾 Saved ${bytes.length ~/ 1024}KB to disk: ${imagePath.split('/').last}',
          );
        } catch (e) {
          debugPrint('[🖼️ PRELOAD] ⚠️ Failed to persist locally: $e');
          // Non-fatal: image works from memory, just won't survive restart
        }

        // 💾 Cache compressed bytes for instant reload after eviction
        _imageMemoryManager.cacheCompressedBytes(imagePath, bytes);

        final image = await _decodeImageCapped(bytes);
        if (mounted && image != null) {
          // 📏 #5: Cache dimensions for placeholder sizing
          _imageMemoryManager.cacheImageDimensions(
            imagePath,
            image.width,
            image.height,
          );
          // Dispose old thumbnail if it was loaded
          final oldImage = _loadedImages[imagePath];
          setState(() {
            _loadedImages[imagePath] = image;
            _imageVersion++;
            _rebuildImageSpatialIndex();
          });
          oldImage?.dispose();
          _imageMemoryManager.markAccessed(imagePath);

          // 🧠 LRU: evict excess images after batch loading
          if (_loadedImages.length > _imageMemoryManager.maxImages) {
            // Get currently visible image paths for protection
            final viewportPaths =
                _imageElements
                    .where((img) => _loadedImages.containsKey(img.imagePath))
                    .map((img) => img.imagePath)
                    .toSet();
            _imageMemoryManager.scheduleEviction(_loadedImages, viewportPaths);
          }
          _stopLoadingPulseIfDone();
        }
      }
    } catch (e) {
      _stopLoadingPulseIfDone();
    }
  }

  /// 🖼️ Decode image bytes with max dimension cap (prevents OOM)
  Future<ui.Image?> _decodeImageCapped(Uint8List bytes) async {
    try {
      // First decode just to get dimensions
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final originalWidth = frame.image.width;
      final originalHeight = frame.image.height;

      // If within limits, use as-is
      if (originalWidth <= _FlueraCanvasScreenState._maxImageDimension &&
          originalHeight <= _FlueraCanvasScreenState._maxImageDimension) {
        codec.dispose(); // 🐛 FIX A: Dispose codec to prevent GPU handle leak
        return frame.image;
      }

      // Dispose full-res and re-decode at capped size
      frame.image.dispose();
      codec.dispose();

      // Calculate target dimensions preserving aspect ratio
      int targetWidth;
      int targetHeight;
      if (originalWidth >= originalHeight) {
        targetWidth = _FlueraCanvasScreenState._maxImageDimension;
        targetHeight =
            (originalHeight *
                    _FlueraCanvasScreenState._maxImageDimension /
                    originalWidth)
                .round();
      } else {
        targetHeight = _FlueraCanvasScreenState._maxImageDimension;
        targetWidth =
            (originalWidth *
                    _FlueraCanvasScreenState._maxImageDimension /
                    originalHeight)
                .round();
      }

      final cappedCodec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      final cappedFrame = await cappedCodec.getNextFrame();
      cappedCodec.dispose();
      return cappedFrame.image;
    } catch (e) {
      return null;
    }
  }

  /// 🔄 Start loading pulse timer (30fps)
  void _startLoadingPulse() {
    if (_loadingPulseTimer != null) return; // Already running
    _loadingPulseTimer = Timer.periodic(
      const Duration(milliseconds: 33), // ~30fps
      (_) {
        if (!mounted) {
          _loadingPulseTimer?.cancel();
          _loadingPulseTimer = null;
          return;
        }
        setState(() {
          _loadingPulseValue = (_loadingPulseValue + 0.02) % 1.0;
        });
      },
    );
  }

  /// 🔄 Stop loading pulse if all images are loaded
  void _stopLoadingPulseIfDone() {
    final hasUnloadedImages = _imageElements.any(
      (img) => !_loadedImages.containsKey(img.imagePath),
    );
    if (!hasUnloadedImages) {
      _loadingPulseTimer?.cancel();
      _loadingPulseTimer = null;
      _loadingPulseValue = 0.0;
    }
  }

  /// 🎤 Load saved recordings from SQLite via RecordingStorageService
  Future<void> _loadSavedRecordings() async {
    try {
      if (!RecordingStorageService.instance.isInitialized) {
        // Service not initialized yet — will be initialized during _loadCanvasData
        // when SqliteStorageAdapter.initialize() runs. Retry after a short delay.
        await Future.delayed(const Duration(milliseconds: 100));
        if (!RecordingStorageService.instance.isInitialized) return;
      }

      final recordings = await RecordingStorageService.instance
          .loadRecordingsForCanvas(_canvasId);

      if (recordings.isEmpty) return;

      final audioFiles = <String>[];
      final loadedSyncRecordings = <SynchronizedRecording>[];

      for (final recording in recordings) {
        // 🔧 FIX #4: Skip recordings whose audio file no longer exists
        final audioFile = File(recording.audioPath);
        if (!await audioFile.exists()) {
          debugPrint(
            '[Lifecycle] Skipping recording ${recording.id} — '
            'file missing: ${recording.audioPath}',
          );
          // 🔧 FIX #3 (audit 4): Also remove stale entry from SQLite
          if (RecordingStorageService.instance.isInitialized) {
            RecordingStorageService.instance
                .deleteRecording(recording.id)
                .catchError((e) {
                  EngineScope.current.errorRecovery.reportError(
                    EngineError(
                      severity: ErrorSeverity.transient,
                      domain: ErrorDomain.storage,
                      source: '_lifecycle.loadSavedRecordings.deleteStale',
                      original: e,
                    ),
                  );
                  return 0;
                });
          }
          continue;
        }

        audioFiles.add(recording.audioPath);
        // Bug fix #4: Add ALL recordings to _syncedRecordings
        // (not just those with strokes) — audio-only recordings
        // also have noteTitle and totalDuration for the UI.
        loadedSyncRecordings.add(recording);
      }

      if (mounted) {
        setState(() {
          // 🔧 FIX #4: Merge instead of overwrite to prevent race
          // (user might save a recording during the same init pipeline)
          for (final path in audioFiles) {
            if (!_savedRecordings.contains(path)) {
              _savedRecordings.add(path);
            }
          }
          for (final rec in loadedSyncRecordings) {
            if (!_syncedRecordings.any((r) => r.id == rec.id)) {
              _syncedRecordings.add(rec);
            }
          }
        });
      }

      debugPrint(
        '[Lifecycle] Loaded ${recordings.length} recordings '
        '(${loadedSyncRecordings.length} with strokes)',
      );

      // 🔧 FIX #4 (audit 4): Clean up stale temp recordings
      DefaultVoiceRecordingProvider.cleanupTempRecordings(
        olderThan: const Duration(hours: 24),
      );
    } catch (e) {
      debugPrint('[Lifecycle] Failed to load recordings: $e');
    }
  }

  // ============================================================================
  // ⏱️ TIME TRAVEL LIFECYCLE → see _lifecycle_time_travel.dart
  // 🌿 CREATIVE BRANCHING LIFECYCLE → see _lifecycle_branching.dart
  // ============================================================================
}
