part of '../../fluera_canvas_screen.dart';

/// 🚀 PHASE 5: Top-level function for isolate layer deserialization.
/// Must be top-level (not a closure) for `compute()` to work.
List<CanvasLayer> _deserializeLayersOnIsolate(List<dynamic> args) {
  final layersJson = args[0] as List<dynamic>;
  final skipStrokes = args[1] as bool;
  return layersJson
      .map(
        (l) =>
            skipStrokes
                ? CanvasLayer.fromJsonMetadataOnly(
                  Map<String, dynamic>.from(l as Map),
                )
                : CanvasLayer.fromJson(Map<String, dynamic>.from(l as Map)),
      )
      .toList();
}

/// 📦 Lifecycle & Initialization — extracted from _FlueraCanvasScreenState
extension on _FlueraCanvasScreenState {
  /// Prefix for micro-thumbnail keys in the staggered queue.
  /// Used to distinguish micro-thumbnails from LOD thumbnails.
  static const String _kMicroThumbPrefix = '__micro_';

  /// ✨ Initialize GPU shader brushes
  Future<void> _initProShaders() async {
    final drawingModule = EngineScope.current.drawingModule;
    final adjustmentService =
        EngineScope
            .current
            .renderCacheScope
            .delegateRenderer
            .adjustmentShaderService;

    await Future.wait([
      if (drawingModule != null) drawingModule.shaderBrushService.initialize(),
      adjustmentService.initialize(),
    ]);

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
  /// 🚀 COLD START FIX: Frame yields between heavy steps let the renderer
  /// paint the splash/loading screen between init phases.
  Future<void> _initializeCanvas() async {
    // 🚀 FIRST-ENTRY OPT: Overlap splash load with heavy init.
    // Splash is a tiny read (~50KB) that completes well before shaders.
    // All independent — run them in parallel.
    //
    // 🚀 PHASE 5: Skip shader init if already compiled from previous session.
    final needsShaders =
        !(EngineScope.current.drawingModule?.shaderBrushService.isAvailable ??
            true);
    await Future.wait([
      // 0. Splash snapshot (tiny BLOB ~50KB, painted on loading screen)
      _loadSplashSnapshot(),

      // 1. GPU shader compilation (~50-200ms on first run, no-op if warm)
      if (needsShaders) _initProShaders(),

      // 2. Persistent isolate spawn (~2-5ms)
      SaveIsolateService.instance.initialize(),

      // 3. Texture preloading (decodes brush textures)
      Future(() => BrushTexture.preloadAll()),

      // 4. Canvas data load from SQLite (I/O bound, variable time)
      _loadCanvasData(),

      // 5. 🎤 Load saved recordings from SQLite
      _loadSavedRecordings(),
    ]);

    // 6. 🐛 FIX: Pre-warm Digital Ink Recognition engine AFTER splash.
    // Loading libdigitalink.so + TFLite model (~1s) inside Future.wait
    // overlaps with shader/texture/SQLite init, raising peak memory ~50MB.
    // Deferring to post-splash keeps peak memory lower while still
    // completing before the user starts drawing (500ms head start).
    Future.delayed(const Duration(milliseconds: 500), () {
      final inkService = DigitalInkService.instance;
      if (inkService.isAvailable && !inkService.isReady) {
        inkService.init();
      }
    });

    // 🚀 PHASE 5: Removed post-Future.wait yield — splash is now inside the
    // parallel group, so no separate yield needed. Saves ~16ms.

    // 🖼️ Wire staggered thumbnail queue callback
    _wireImageMemoryManagerCallbacks();

    // 🕐 Start proactive image eviction after init completes
    _imageEvictionTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _runImageEvictionCycle(),
    );

    // 🔋 ENERGY: Subscribe to reactive power/thermal state changes.
    // Instant detection instead of polling every 5-15s.
    final monitor = EngineScope.current.performanceMonitor;
    if (monitor.isInitialized) {
      _metricsSubscription = monitor.metricsStream.listen((metrics) {
        if (!mounted) return;
        final shouldReduce = metrics.shouldReduceQuality;
        if (shouldReduce != _isLowPowerMode) {
          _onPowerModeChanged(shouldReduce);
        }
      });
    }
  }

  /// 🚀 Yield one frame to the rendering pipeline.
  /// Completes after the current frame has been painted, allowing the
  /// splash/loading screen to update between heavy init steps.
  Future<void> _yieldFrame() {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      completer.complete();
    });
    return completer.future;
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

    // 📏 Adaptive budget: compute maxImages from RSS-based device budget
    final budgetMB = _imageMemoryBudget.computeBudgetFromRSS();
    _imageMemoryManager.maxImages = _imageMemoryBudget.computeMaxImages();
    _imageStubManager.updateFromBudget(budgetMB);

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

    // 🚀 Build O(1) lookup maps once, reuse everywhere
    final imageIdToPath = <String, String>{};
    final pathToIds = <String, List<String>>{};
    final idToElement = <String, ImageElement>{};
    for (final img in _imageElements) {
      imageIdToPath[img.id] = img.imagePath;
      (pathToIds[img.imagePath] ??= []).add(img.id);
      idToElement[img.id] = img;
    }

    // 🚀 OPT 2: R-tree for visiblePaths (replaces O(n) overlaps loop)
    final visibleElements =
        _imageSpatialIndex?.queryVisible(expandedViewport) ?? _imageElements;
    final visiblePaths = visibleElements.map((e) => e.imagePath).toSet();

    // Run proactive eviction (off-viewport > 5s → dispose, keep compressed)
    if (_loadedImages.isNotEmpty) {
      final evicted = _imageMemoryManager.proactiveEviction(
        _loadedImages,
        visiblePaths,
      );
      if (evicted.isNotEmpty) {
        // 🚀 OPT 4: Use pathToIds reverse map for O(1) invalidation
        for (final path in evicted) {
          for (final id in (pathToIds[path] ?? const [])) {
            ImagePainter.invalidateImageCache(id);
          }
        }
        _thumbnailPaths.removeAll(evicted);
        if (mounted) setState(() => _imageVersion++);
      }
    }

    // 🗂️ STUB-OUT: Query R-tree for safe images (near viewport)
    final pageOutMargin = viewportRect.longestSide * 3.0;
    final safeElements =
        _imageSpatialIndex?.queryVisible(viewportRect, margin: pageOutMargin) ??
        _imageElements;
    final safeIds = safeElements.map((e) => e.id).toSet();

    final stubbedPaths = _imageStubManager.maybeStubOut(
      safeImageIds: safeIds,
      loadedImages: _loadedImages,
      imageIdToPath: imageIdToPath,
      totalImageCount: _imageElements.length,
      onBeforeStub: (imagePath, image) {
        if (!_imageMemoryManager.hasCompressedBytes(imagePath)) {
          // Compressed bytes loaded from disk on hydration if not cached.
        }

        // 🖼️ Enqueue micro-thumbnail generation (64px)
        final bytes = _imageMemoryManager.getCompressedBytes(imagePath);
        if (bytes != null) {
          // 🚀 OPT 3: Use pathToIds reverse map for O(1) lookup
          final imgId = pathToIds[imagePath]?.firstOrNull;
          if (imgId != null) {
            _imageMemoryManager.enqueueThumbnail(
              '\$_kMicroThumbPrefix$imgId',
              bytes,
              64,
            );
          }
        }
      },
    );
    if (stubbedPaths.isNotEmpty) {
      // 🚀 OPT 4: Use pathToIds reverse map for O(1) invalidation
      for (final path in stubbedPaths) {
        for (final id in (pathToIds[path] ?? const [])) {
          ImagePainter.invalidateImageCache(id);
        }
      }
      _thumbnailPaths.removeAll(stubbedPaths);
      if (mounted) setState(() => _imageVersion++);
    }

    // 🗂️ HYDRATE: Query R-tree for nearby images in page-in margin
    final pageInMargin = viewportRect.longestSide * 1.5;
    final nearbyElements =
        _imageSpatialIndex?.queryVisible(
          predictiveViewport,
          margin: pageInMargin,
        ) ??
        const [];
    final nearbyImages =
        nearbyElements
            .map(
              (e) => NearbyImage(
                imageId: e.id,
                imagePath: e.imagePath,
                center: e.position,
              ),
            )
            .toList();

    final hydrateRequests = _imageStubManager.maybeHydrate(
      nearbyImages: nearbyImages,
      loadedImages: _loadedImages,
      viewport: predictiveViewport,
      canvasScale: scale,
    );
    for (final req in hydrateRequests) {
      // 🚀 OPT 3: Use idToElement map for O(1) lookup
      final imgEl = idToElement[req.imageId];
      if (imgEl != null) {
        _preloadImage(
          req.imagePath,
          storageUrl: imgEl.storageUrl,
          thumbnailUrl: imgEl.thumbnailUrl,
        );
      }
    }

    // Reload evicted images that are now back in viewport
    for (final img in _imageElements) {
      if (visiblePaths.contains(img.imagePath) &&
          !_loadedImages.containsKey(img.imagePath) &&
          !_imageStubManager.isStubbed(img.id)) {
        _preloadImage(
          img.imagePath,
          storageUrl: img.storageUrl,
          thumbnailUrl: img.thumbnailUrl,
        );
      }
    }

    // 🖼️ MULTI-LEVEL LOD: Determine optimal resolution tier for current zoom
    // 🔋 ENERGY: Skip LOD thumbnail work in low-power mode to save CPU
    if (_isLowPowerMode) return;
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

      // 🖼️ MICRO-THUMBNAIL: Route to stub manager (not _loadedImages)
      if (path.startsWith(_kMicroThumbPrefix)) {
        final imageId = path.substring(_kMicroThumbPrefix.length);
        if (_imageStubManager.isStubbed(imageId)) {
          _imageStubManager.setMicroThumbnail(imageId, thumbnail);
          // Invalidate per-image cache to show micro-thumbnail
          ImagePainter.invalidateImageCache(imageId);
          if (mounted) setState(() => _imageVersion++);
        } else {
          thumbnail.dispose(); // Image was hydrated before thumb finished
        }
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
    }
  }

  /// 🆕 Load dati canvas — LOCAL FIRST per display istantaneo
  Future<void> _loadCanvasData() async {
    _isLoading = true; // 🔄 Disable auto-save during loading
    bool loadedFromLocal = false;

    try {
      Map<String, dynamic>? data;

      // 🚀 1. LOCAL FIRST: prefer storageAdapter over legacy callback
      if (_config.storageAdapter != null) {
        await _config.storageAdapter!.initialize();

        // 🎤 Initialize RecordingStorageService with shared DB
        if (_config.storageAdapter is SqliteStorageAdapter) {
          final sqliteAdapter = _config.storageAdapter as SqliteStorageAdapter;
          RecordingStorageService.instance.initialize(sqliteAdapter.database);
          // 🗂️ Initialize stroke paging with shared DB for 1M+ stroke support
          DrawingPainter.initializePaging(sqliteAdapter.database);
          // 🔍 Initialize handwriting index with shared DB
          HandwritingIndexService.instance.init(sqliteAdapter.database);
        }

        data = await _config.storageAdapter!.loadCanvas(_canvasId);
      } else {
        data = await _config.onLoadCanvas?.call(_canvasId);
      }

      // 2. ☁️ Cloud fallback: load from cloud when no local data
      if (data == null && _hasCloudSync && _syncEngine != null) {
        try {
          data = await _syncEngine!.loadCanvas(_canvasId);
          if (data != null) {
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
              }
            }
          } else {}
        } catch (e) {}
      } else if (data == null) {}

      if (data != null) {
        loadedFromLocal = true;
      }

      if (data != null && mounted) {
        // 🐛 FIX: Always do full decode — the lazy-load stub system had
        // multiple bugs (Isolate.run closure capture, stub corruption during
        // save, re-stub after save corrupting the index). Full decode is
        // fast enough for normal canvases (< 10K strokes). The lazy-load
        // optimization can be re-enabled once the stub lifecycle is robust.
        await _applyCanvasData(data, skipStrokes: false);

        // ☁️ Download images/PDFs that are in cloud but missing locally
        // (runs in background — non-blocking)
        downloadMissingAssets();
      }
    } catch (e, st) {
      debugPrint('❌ _loadCanvasData EXCEPTION: $e\n$st');
    } finally {
      // 🔄 Reveal canvas: setState triggers AnimatedOpacity fade-out
      if (mounted) {
        // 🎨 Invalidate layer caches (layer compositing state may have changed).
        // NOTE: Do NOT invalidate strokeCache here — the version-based
        // self-invalidation in _paintDirect() handles incremental updates.
        // Explicit invalidation would destroy the warm cache just built
        // by bumpVersion() → paint(), causing a 120ms+ full rebuild.
        DrawingPainter.invalidateLayerCaches();

        setState(() {
          _isLoading = false;
        });

        // 🏎️ Auto-enable performance overlay in debug + profile builds
        if (!kReleaseMode) {
          CanvasPerformanceMonitor.instance.setEnabled(true);
          CanvasPerformanceMonitor.instance.attachVulkanService(
            _vulkanStrokeOverlay,
          );
          // 🌐 Global overlay: persists across Navigator routes
          // (ImageViewer, PDF Reader, LaTeX Editor, etc.)
          CanvasPerformanceMonitor.instance.showGlobalOverlay(context);
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

          // 🏎️ PERF: Flush cold-start frames from the P99 rolling window.
          // The first 1-2 paint frames after load are always expensive
          // (cache warmup, RenderPlan compilation, R-tree build). Without
          // this reset, those ~25ms frames inflate P99 for 2 full seconds
          // (120-sample window / 60fps) despite steady-state being <5ms.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            CanvasPerformanceMonitor.instance.reset();
          });
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
          return; // Local is newer or same — nothing to do
        }
      }

      // Cloud data is newer — apply it
      if (mounted) {
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
    } catch (e, st) {}
  }

  /// Helper: apply text/image/pin elements (called from within setState)
  void _applyElementsInline(
    List<dynamic>? textJson,
    List<dynamic>? imageJson,
    List<dynamic>? pinsJson,
  ) {
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
    if (imageJson != null) {
      _imageElements.clear();
      _imageElements.addAll(
        imageJson
            .map(
              (i) => ImageElement.fromJson(Map<String, dynamic>.from(i as Map)),
            )
            .toList(),
      );
      _imageVersion++;
      _rebuildImageSpatialIndex();
    }
    if (pinsJson != null) {
      _recordingPins.clear();
      _recordingPins.addAll(
        pinsJson
            .map(
              (p) => RecordingPin.fromJson(Map<String, dynamic>.from(p as Map)),
            )
            .toList(),
      );
    }
  }

  /// 🛠️ Applica dati canvas alla UI (estratto per riuso)
  ///
  /// 🚀 ADAPTIVE: Small canvases (≤50 elements) use a single setState.
  /// Large canvases use 2 grouped setStates with frame yields.
  Future<void> _applyCanvasData(
    Map<String, dynamic> data, {
    bool skipStrokes = false,
  }) async {
    if (!mounted) return;

    // Count total elements to decide if yields are needed
    final layersJson = data['layers'] as List<dynamic>?;
    final totalStrokeCount =
        layersJson?.fold<int>(0, (sum, l) {
          final strokes = (l is Map) ? (l['strokes'] as List?)?.length ?? 0 : 0;
          return sum + strokes;
        }) ??
        0;
    final rawText = data['textElements'];
    final textJson = rawText is List ? rawText : null;
    final rawImages = data['imageElements'];
    final imageJson = rawImages is List ? rawImages : null;
    final rawPins = data['recordingPins'];
    final pinsJson = rawPins is List ? rawPins : null;
    final totalElements =
        totalStrokeCount +
        (textJson?.length ?? 0) +
        (imageJson?.length ?? 0) +
        (pinsJson?.length ?? 0);
    final isSmall = totalElements <= 50;

    // ── METADATA + SETTINGS ─────────────────────────────────────────────
    setState(() {
      // Title
      final savedTitle = data['title'] as String?;
      if (savedTitle != null && savedTitle.isNotEmpty) {
        _noteTitle = savedTitle;
      }

      // Background color + paper type
      final settingsData = data['settings'] as Map<dynamic, dynamic>?;
      final settings =
          settingsData != null ? Map<String, dynamic>.from(settingsData) : null;

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

      // Guides
      final guidesJson =
          data['guides'] as Map<String, dynamic>? ??
          settings?['guides'] as Map<String, dynamic>?;
      if (guidesJson != null) {
        _rulerGuideSystem.loadFromJson(guidesJson);
      }

      // Design variables
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

      // 🚀 FAST PATH: Small canvas — include elements in the same setState
      if (isSmall) {
        _applyElementsInline(textJson, imageJson, pinsJson);
      }
    });

    // For large canvases: yield between metadata and elements
    if (!isSmall) {
      if (mounted) await _yieldFrame();
      if (!mounted) return;
      setState(() {
        _applyElementsInline(textJson, imageJson, pinsJson);
      });
    }

    // 🚀 Yield before layer deserialization (skip for small canvases)
    if (!isSmall && mounted) await _yieldFrame();

    // 🎯 Load layers AFTER setState to avoid notifications during build
    if (layersJson != null && layersJson.isNotEmpty) {
      // 🚀 MEMORY FIX C: Skip expensive layer teardown+rebuild if cloud
      // layers are structurally identical to local ones (same IDs & stroke
      // counts). This prevents massive transient allocations during
      // background sync when nothing actually changed.
      bool shouldReloadLayers = true;
      if (!_isLoading && _layerController.layers.length == layersJson.length) {
        shouldReloadLayers = false;
        for (int i = 0; i < layersJson.length; i++) {
          final cloudLayer = layersJson[i] as Map;
          final localLayer = _layerController.layers[i];
          final cloudId = cloudLayer['id'] as String?;
          final cloudStrokes = cloudLayer['strokes'] as List?;
          if (cloudId != localLayer.id ||
              (cloudStrokes?.length ?? 0) != localLayer.strokes.length) {
            shouldReloadLayers = true;
            break;
          }
        }
        if (!shouldReloadLayers) {}
      }

      if (shouldReloadLayers) {
        // 🚀 PHASE 5: Deserialize layers on background isolate.
        // CanvasLayer.fromJson is pure Dart (no Flutter bindings),
        // safe for isolate execution via compute().
        //
        // 🐛 FIX: Use compute() instead of Isolate.run() — the anonymous
        // closure in Isolate.run() implicitly captures `this` (the
        // _FlueraCanvasScreenState) from the extension method context.
        // `this` contains a _Timer (_saveDebounceTimer) which is
        // unsendable across isolate boundaries, causing a silent crash
        // that was swallowed by catch(e){} → empty canvas on re-open.
        final parsedLayers = await compute(
          _deserializeLayersOnIsolate,
          <dynamic>[layersJson, skipStrokes],
        );
        _layerController.clearAllAndLoadLayers(parsedLayers);
      }
    }

    // 🚀 CRITICAL: Bump scene graph version after layer loading.
    // With Transform+RepaintBoundary architecture, paint() only runs when
    // shouldRepaint() detects a version change. Without this bump, loaded
    // strokes remain invisible until the user draws a new stroke.
    _layerController.sceneGraph.bumpVersion();
    DrawingPainter.invalidateAllTiles();
    // 🎨 Rebuild background layer with loaded paper type / color
    BackgroundPainter.clearCache();
    _backgroundVersionNotifier.value++;

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

    // 🚀 P99 FIX: Yield after layer loading before image sync
    if (mounted) await _yieldFrame();

    // Pre-carica immagini in background (non bloccante)
    // 🔧 FIX: Sync _imageElements into layers if they're missing
    // 🚀 FIRST-ENTRY OPT: Use beginBatch/endBatch to collapse N
    // notifyListeners calls into 1 (avoids N × cluster rebuild).
    final layerImageIds = <String>{};
    for (final layer in _layerController.layers) {
      for (final img in layer.images) {
        layerImageIds.add(img.id);
      }
    }
    final imagesToSync =
        _imageElements.where((e) => !layerImageIds.contains(e.id)).toList();
    if (imagesToSync.isNotEmpty) {
      final wasTracking = _layerController.enableDeltaTracking;
      _layerController.enableDeltaTracking = false;
      _layerController.beginBatch();
      for (final imageElement in imagesToSync) {
        _layerController.addImage(imageElement);
      }
      _layerController.endBatch();
      _layerController.enableDeltaTracking = wasTracking;
    }

    // 🚀 Batch preload — skip images already loaded AND deduplicate by path
    final seenPaths = <String>{};
    final imagesToPreload = <ImageElement>[];
    for (final img in _imageElements) {
      if (!_loadedImages.containsKey(img.imagePath) &&
          seenPaths.add(img.imagePath)) {
        imagesToPreload.add(img);
      }
    }
    if (imagesToPreload.isNotEmpty) {
      // 🚀 FIRST-ENTRY OPT: Fire-and-forget — don't block canvas reveal.
      // Each _preloadImage calls setState internally when done.
      unawaited(
        Future.wait(
          imagesToPreload.map(
            (img) => _preloadImage(
              img.imagePath,
              storageUrl: img.storageUrl,
              thumbnailUrl: img.thumbnailUrl,
            ),
          ),
        ),
      );
    }

    // 🛠️ FORCE FINAL REBUILD — only needed for large canvases where
    // elements were applied in a separate setState before image preload.
    // Small canvases already applied everything in one setState.
    if (!isSmall && mounted) {
      setState(() {});
    }

    // 📄 Restore PDF documents from saved metadata
    // 🚀 FIRST-ENTRY OPT: Fire-and-forget — canvas reveals immediately.
    // Repaint scheduled via addPostFrameCallback when restore completes.
    final pdfDocsList = data['pdfDocuments'] as List<dynamic>?;
    if (pdfDocsList != null && pdfDocsList.isNotEmpty) {
      unawaited(
        _restorePdfDocuments(pdfDocsList).then((_) {
          if (mounted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _layerController.sceneGraph.bumpVersion();
                _pdfLayoutVersion++;
                setState(() {});
              }
            });
          }
        }),
      );
    }

    // 🧮 Restore scene nodes (LatexNode, TabularNode, SectionNode) from JSON sidecar
    // 🚀 FIRST-ENTRY OPT: Defer to post-frame — canvas reveals first,
    // scene nodes appear on the next frame.
    final sceneNodesList = data['sceneNodes'] as List<dynamic>?;
    if (sceneNodesList != null && sceneNodesList.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
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
          } catch (e) {}
        }
        _layerController.sceneGraph.bumpVersion();
        _layerController.notifyListeners();
        setState(() {});
      });
    }
  }
}
