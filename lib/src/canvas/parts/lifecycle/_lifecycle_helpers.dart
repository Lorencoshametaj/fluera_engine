part of '../../fluera_canvas_screen.dart';

// ═══════════════════════════════════════
// 🔄 Lifecycle — Layer Callbacks, Image Loading & Helpers
// ═══════════════════════════════════════

extension _LifecycleHelpers on _FlueraCanvasScreenState {

  ///  Callback called when the layer controller notifica modifiche
  ///
  /// 🚀 PERF: Post-frame callbacks use dedupe guards to prevent accumulation.
  /// Without guards, N calls before the next frame → N separate cluster rebuilds
  /// on the same frame (N × O(N log N) = catastrophic).
  static bool _clusterRebuildPending = false;
  static bool _boundsUpdatePending = false;

  void _onLayerChanged() {
    // 🚀 P99 FIX: During active drawing, skip ALL heavy operations.
    // The in-progress stroke is in CurrentStrokePainter (not the layer),
    // so bounds/clusters/lists don't change until stroke end.
    final isDrawing = _isDrawingNotifier.value;

    // 🧭 Update navigation bounds tracker — DEFERRED to post-frame.
    // Skip during active drawing (wasted work, stroke not in layer yet).
    // 🚀 DEDUPE: At most ONE update per frame.
    if (!isDrawing && !_boundsUpdatePending) {
      _boundsUpdatePending = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _boundsUpdatePending = false;
        if (mounted) _contentBoundsTracker.update();
      });
    }

    // 🔧 FIX ZOOM LAG: Update list cache
    // 🚀 Skip during active drawing — list doesn't change mid-stroke.
    if (!isDrawing) {
      _refreshCachedLists();
    }

    // 🌊 REFLOW: Rebuild cluster cache for the active layer
    // 🚀 DEFERRED to post-frame — with 300+ strokes, the O(N log N) detect()
    // was causing 80ms UI thread spikes when called synchronously.
    // 🚀 DEDUPE: At most ONE rebuild per frame.
    if (!isDrawing &&
        _clusterDetector != null &&
        !_lassoTool.isDragging &&
        !_clusterRebuildPending) {
      _clusterRebuildPending = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _clusterRebuildPending = false;
        if (mounted) _rebuildClusterCache();
      });
    }

    // Auto-save only if not loading
    if (!_isLoading) {
      _autoSaveCanvas();
    }

    // 🚀 P99 FIX: Bump toolbar undo/redo notifier only when state transitions.
    // This fires ~2-3x per stroke (not every layer notification), saving the
    // full 1,568-line toolbar rebuild on intermediate events.
    final nowCanUndo = _layerController.canUndo;
    final nowCanRedo = _layerController.canRedo;
    final nowCount = _layerController.activeLayer?.elementCount ?? 0;
    if (nowCanUndo != _lastCanUndo ||
        nowCanRedo != _lastCanRedo ||
        nowCount != _lastElementCount) {
      _lastCanUndo = nowCanUndo;
      _lastCanRedo = nowCanRedo;
      _lastElementCount = nowCount;
      _undoRedoVersion.value++;
    }
  }

  /// 🌊 Rebuild the reflow cluster cache from the active layer.
  void _rebuildClusterCache() {
    if (_clusterDetector == null) return;

    // 🧠 KNOWLEDGE FLOW: Save old clusters BEFORE rebuild for ID remapping
    final oldClusters = List<ContentCluster>.from(_clusterCache);

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
    if (corrected > 0) {}

    _lassoTool.reflowController?.updateClusters(_clusterCache);

    // 🧠 KNOWLEDGE FLOW: Remap connection cluster IDs after full rebuild.
    // detect() generates new IDs — match old→new by stroke content overlap.
    if (_knowledgeFlowController != null &&
        _knowledgeFlowController!.connections.isNotEmpty &&
        oldClusters.isNotEmpty) {
      _knowledgeFlowController!.remapClusterIds(oldClusters, _clusterCache);
    }

    // 💡 SMART PAUSE: Recompute after user pauses writing (1.5s idle)
    // Longer than a simple debounce — this detects intentional pauses,
    // so suggestions appear when the user has ~stopped writing.
    _suggestionDebounceTimer?.cancel();
    if (_knowledgeFlowController != null && _clusterCache.length >= 2) {
      _suggestionDebounceTimer = Timer(const Duration(milliseconds: 1500), () async {
        if (!mounted) return;
        final activeLayer = _layerController.layers.firstWhere(
          (l) => l.id == _layerController.activeLayerId,
          orElse: () => _layerController.layers.first,
        );

        // 🔤 CLUSTER-LEVEL RECOGNITION: Recognize all strokes in each cluster
        // together using recognizeMultiStroke() for dramatically better accuracy.
        Map<String, String>? clusterTexts;
        final inkService = DigitalInkService.instance;
        final ct = <String, String>{};

        // Build stroke lookup from active layer
        final strokeMap = <String, ProStroke>{};
        for (final s in activeLayer.strokes) {
          strokeMap[s.id] = s;
        }

        // Build digital text lookup
        final textMap = <String, DigitalTextElement>{};
        for (final t in _digitalTextElements) {
          textMap[t.id] = t;
        }

        // Prune cache: remove clusters that no longer exist
        final currentIds = _clusterCache.map((c) => c.id).toSet();
        _clusterTextCache.removeWhere((k, _) => !currentIds.contains(k));
        _clusterTextCacheKeys.removeWhere((k, _) => !currentIds.contains(k));

        // 🚀 PARALLEL: Recognize all clusters concurrently
        final futures = <Future<void>>[];
        for (final cluster in _clusterCache) {
          if (cluster.strokeIds.isEmpty && cluster.textIds.isEmpty) continue;

          // Cache key = sorted stroke+text IDs (detect changes)
          final allIds = [...cluster.strokeIds, ...cluster.textIds]..sort();
          final cacheKey = allIds.join(',');
          final prevKey = _clusterTextCacheKeys[cluster.id];

          // Cache hit — strokes unchanged
          if (prevKey == cacheKey && _clusterTextCache.containsKey(cluster.id)) {
            final cached = _clusterTextCache[cluster.id]!;
            if (cached.isNotEmpty) ct[cluster.id] = cached;
            continue;
          }

          // 🔤 DIGITAL TEXT: Include text elements directly (no ML Kit needed)
          final textParts = <String>[];
          for (final tid in cluster.textIds) {
            final textEl = textMap[tid];
            if (textEl != null && textEl.text.trim().isNotEmpty) {
              textParts.add(textEl.text.trim());
            }
          }

          // Collect recognizable stroke data (skip stubs with no points)
          final strokeSets = <List<ProDrawingPoint>>[];
          for (final sid in cluster.strokeIds) {
            final stroke = strokeMap[sid];
            if (stroke != null && !stroke.isStub && stroke.points.length >= 3) {
              strokeSets.add(stroke.points);
            }
          }

          if (strokeSets.isEmpty && textParts.isEmpty) {
            _clusterTextCacheKeys[cluster.id] = cacheKey;
            _clusterTextCache[cluster.id] = '';
            continue;
          }

          // Schedule recognition (parallel)
          final clusterId = cluster.id;
          if (strokeSets.isNotEmpty && inkService.isAvailable) {
            futures.add(
              inkService.recognizeMultiStroke(strokeSets).then((recognized) {
                final parts = [...textParts];
                if (recognized != null && recognized.isNotEmpty) {
                  parts.add(recognized);
                }
                final combined = parts.join(' ');
                _clusterTextCacheKeys[clusterId] = cacheKey;
                _clusterTextCache[clusterId] = combined;
                if (combined.isNotEmpty) ct[clusterId] = combined;
              }),
            );
          } else if (textParts.isNotEmpty) {
            // Text-only cluster — no ML Kit needed
            final combined = textParts.join(' ');
            _clusterTextCacheKeys[clusterId] = cacheKey;
            _clusterTextCache[clusterId] = combined;
            ct[clusterId] = combined;
          }
        }

        // Wait for all parallel recognitions
        if (futures.isNotEmpty) {
          await Future.wait(futures);
        }

        if (!mounted) return;
        final prevCount = _knowledgeFlowController!.suggestions.length;
        clusterTexts = ct.isNotEmpty ? ct : null;
        _knowledgeFlowController!.recomputeSuggestions(
          clusters: _clusterCache,
          allStrokes: activeLayer.strokes,
          clusterTexts: clusterTexts,
        );
        // 🔔 HAPTIC: Subtle pulse when a NEW suggestion appears (pan mode only)
        final newCount = _knowledgeFlowController!.suggestions.length;
        if (newCount > 0 && newCount > prevCount && _effectiveIsPanMode) {
          HapticFeedback.selectionClick();
        }
      });
    }
  }

  /// 🔧 Update le liste cachate da _layerController
  void _refreshCachedLists() {
    // 🎬 Durante Time Travel, le strokes vengono dal engine, non dal controller
    if (_isTimeTravelMode && _timeTravelEngine != null) return;

    _cachedAllShapes = _layerController.getAllVisibleShapes();

    // 🖼️ Sync images from layers (handles add, update, and remove from remote deltas)
    final previousCount = _imageElements.length;
    final layerImageIds = <String>{};
    bool imageChanged = false;
    for (final layer in _layerController.layers) {
      for (final img in layer.images) {
        layerImageIds.add(img.id);
        final existingIndex = _imageElements.indexWhere((e) => e.id == img.id);
        if (existingIndex == -1) {
          // New image from remote delta
          _imageElements.add(img);
          imageChanged = true;
        } else {
          // Update existing image (position, scale, etc. from remote delta)
          _imageElements[existingIndex] = img;
        }
      }
    }
    // Remove images that were deleted remotely
    final beforeRemove = _imageElements.length;
    _imageElements.removeWhere(
      (e) =>
          layerImageIds.isNotEmpty &&
          !layerImageIds.contains(e.id) &&
          _layerController.layers.isNotEmpty,
    );
    if (_imageElements.length != beforeRemove) imageChanged = true;

    // 🧠 Cache coherency: ONLY rebuild R-tree when images actually changed
    // 🚀 FIX: Previous condition `layerImageIds.isNotEmpty` was ALWAYS true
    // when images exist, causing R-tree rebuild + cache prune on EVERY
    // _onLayerChanged call — massive unnecessary work.
    if (imageChanged || _imageElements.length != previousCount) {
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
      final image = await _decodeImageCapped(cachedBytes);
      if (mounted && image != null) {
        setState(() {
          _loadedImages[imagePath] = image;
          _imageVersion++;
        });
        _scheduleImageSpatialIndexRebuild();
        _imageMemoryManager.markAccessed(imagePath);
        _stopLoadingPulseIfDone();
      }
      return;
    }

    try {
      // 🚀 ISOLATE I/O: Read file bytes on background isolate (zero UI jank)
      final bytes = await ImageMemoryManager.readFileOnIsolate(imagePath);
      if (bytes != null) {
        // 🚀 MEMORY: Don't cache compressed bytes for local files — re-reading
        // from disk on eviction (~50ms) is acceptable and saves ~1-5MB RAM per image.
        // Network-downloaded images still cache (see storageUrl path below).
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
          });
          _scheduleImageSpatialIndexRebuild();
          _imageMemoryManager.markAccessed(imagePath);
          _stopLoadingPulseIfDone();
        }
        return;
      }

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
              });
              _scheduleImageSpatialIndexRebuild();
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
          if (!kIsWeb) {
            final localFile = File(imagePath);
            await localFile.parent.create(recursive: true);
            await localFile.writeAsBytes(bytes, flush: true);
          }
        } catch (e) {
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
          });
          _scheduleImageSpatialIndexRebuild();
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
  ///
  /// 🚀 MEMORY FIX: Uses codec header to read dimensions WITHOUT decoding
  /// full-res pixels first. Only decodes once at the target (capped) size.
  Future<ui.Image?> _decodeImageCapped(Uint8List bytes) async {
    try {
      // 1. Instantiate codec to read dimensions from header
      final codec = await ui.instantiateImageCodec(bytes);

      // Read actual dimensions via a single frame decode
      // (Flutter's codec doesn't expose width/height directly on the codec,
      //  so we must decode one frame — but we can request it at capped size.)
      final maxDim = _FlueraCanvasScreenState._maxImageDimension;

      // 2. Peek at dimensions by getting frame info
      final frame = await codec.getNextFrame();
      final w = frame.image.width;
      final h = frame.image.height;

      // 3. If within limits, use as-is (single decode, no waste)
      if (w <= maxDim && h <= maxDim) {
        codec.dispose();
        return frame.image;
      }

      // 4. Over limit — dispose the full-res frame, re-decode at cap
      frame.image.dispose();
      codec.dispose();

      // Calculate target dimensions preserving aspect ratio
      final int targetWidth;
      final int targetHeight;
      if (w >= h) {
        targetWidth = maxDim;
        targetHeight = (h * maxDim / w).round();
      } else {
        targetHeight = maxDim;
        targetWidth = (w * maxDim / h).round();
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

      // 🚀 JANK FIX: Batch all File.exists() checks in parallel instead of
      // sequential awaits. Reduces total I/O from O(n*latency) to O(latency).
      final existsResults = kIsWeb
          ? List.filled(recordings.length, true) // On web, skip file checks
          : await Future.wait(
              recordings.map((r) => File(r.audioPath).exists()),
            );

      final audioFiles = <String>[];
      final loadedSyncRecordings = <SynchronizedRecording>[];

      for (int i = 0; i < recordings.length; i++) {
        final recording = recordings[i];
        if (!existsResults[i]) {
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

      // 🔧 FIX #4 (audit 4): Clean up stale temp recordings
      DefaultVoiceRecordingProvider.cleanupTempRecordings(
        olderThan: const Duration(hours: 24),
      );
    } catch (e) {}
  }

  // ============================================================================
  // ⏱️ TIME TRAVEL LIFECYCLE → see _lifecycle_time_travel.dart
  // 🌿 CREATIVE BRANCHING LIFECYCLE → see _lifecycle_branching.dart
  // ============================================================================
}
