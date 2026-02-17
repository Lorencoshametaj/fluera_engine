part of '../../nebula_canvas_screen.dart';

/// 📦 Lifecycle & Initialization — extracted from _NebulaCanvasScreenState
extension on _NebulaCanvasScreenState {
  /// ✨ Initialize Pro shader brushes with subscription gating
  Future<void> _initProShaders() async {
    await ShaderBrushService.instance.initialize();
    // Check Pro subscription — if user has Pro, enable GPU shaders
    final isPro = _config.subscriptionTier == NebulaSubscriptionTier.pro;
    if (isPro) {
      ShaderBrushService.instance.enablePro();
    }
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
    } catch (e) {}
  }

  /// 🎛️ Load brush settings persistenti dal servizio
  void _loadBrushSettings() {
    final service = BrushSettingsService.instance;
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
        _brushSettings = BrushSettingsService.instance.settings;
      });
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

      // 🚀 1. LOCAL FIRST: load via config callback
      data = await _config.onLoadCanvas?.call(_canvasId);
      print(
        '🎨 [ProCanvasScreen] Local load result: ${data != null ? "FOUND (${data.keys.length} keys)" : "NULL"}',
      );

      // 2. Phase 2: cloud sync fallback (not yet implemented in SDK)
      if (data == null) {
        if (_hasCloudSync) {
          print(
            '🎨 [ProCanvasScreen] No local data & cloud sync enabled — cloud load not yet implemented in SDK',
          );
        } else {
          print('🎨 [ProCanvasScreen] No local data & no cloud sync');
        }
      } else {
        loadedFromLocal = true;
      }

      if (data != null && mounted) {
        _applyCanvasData(data);
      }
    } catch (e) {
    } finally {
      // 🔄 Reveal canvas: setState triggers AnimatedOpacity fade-out
      if (mounted) {
        setState(() {
          _isLoading = false;
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

  /// 🔄 Sincronizza Firebase in background dopo caricamento locale
  ///
  /// 🔄 Sincronizzazione Firebase in background
  /// Loads dati da Firebase e li applica SOLO se more recenti del locale.
  /// Do not blocca la UI — l'utente can already disegnare.
  Future<void> _syncFirebaseInBackground() async {
    // 💎 TIER GATE: Only Plus/Pro users sync canvas from the cloud
    if (!_hasCloudSync) return;

    // Phase 2: cloud sync background refresh
    // Currently no cloud-load callback in NebulaCanvasConfig.
    // When available, load remote data and compare timestamps.
    debugPrint(
      '🔄 [ProCanvasScreen] Background sync: cloud sync not yet implemented in SDK',
    );
  }

  /// 🛠️ Applica dati canvas alla UI (estratto per riuso)
  void _applyCanvasData(Map<String, dynamic> data) {
    // 🛠️ APPLICATION OF DATA WITH IMMEDIATE SETSTATE
    setState(() {
      // 🆕 Load titolo (if present nel salvataggio)
      final savedTitle = data['title'] as String?;
      if (savedTitle != null && savedTitle.isNotEmpty) {
        _noteTitle = savedTitle;
      }

      // Load text elements
      final textJson = data['textElements'] as List<dynamic>?;
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
      final imageJson = data['imageElements'] as List<dynamic>?;
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
      }

      // Load settings
      final settingsData = data['settings'] as Map<dynamic, dynamic>?;
      final settings =
          settingsData != null ? Map<String, dynamic>.from(settingsData) : null;
      if (settings != null) {
        final bgColor = settings['backgroundColor'];
        if (bgColor != null) {
          // Supporta sia formato string (hex o decimal) che int
          if (bgColor is String) {
            try {
              // Prova prima come hex (con o without 0x prefix)
              if (bgColor.startsWith('0x') || bgColor.startsWith('0X')) {
                _canvasBackgroundColor = Color(int.parse(bgColor));
              } else if (bgColor.length == 8 && !bgColor.contains('-')) {
                // Formato esadecimale without prefisso (es: "ffffffff")
                _canvasBackgroundColor = Color(int.parse(bgColor, radix: 16));
              } else {
                // Formato decimale (es: "4294967295")
                _canvasBackgroundColor = Color(int.parse(bgColor));
              }
            } catch (e) {
              _canvasBackgroundColor = Colors.white;
            }
          } else if (bgColor is int) {
            _canvasBackgroundColor = Color(bgColor);
          }
        }
        _paperType = settings['paperType'] ?? 'blank';

        // 📐 Load saved guides
        final guidesJson = settings['guides'] as Map<String, dynamic>?;
        if (guidesJson != null) {
          _rulerGuideSystem.loadFromJson(guidesJson);
        }
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

    // 🎯 Set layer attivo DOPO il caricamento dei layers
    final settingsData2 = data['settings'] as Map<dynamic, dynamic>?;
    final settings2 =
        settingsData2 != null ? Map<String, dynamic>.from(settingsData2) : null;
    if (settings2 != null) {
      final activeLayerId = settings2['activeLayerId'] as String?;
      if (activeLayerId != null) {
        _layerController.selectLayer(activeLayerId);
      }
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
    for (final imageElement in _imageElements) {
      if (!layerImageIds.contains(imageElement.id)) {
        // Image exists in _imageElements but not in any layer — add to active layer
        final wasTracking = _layerController.enableDeltaTracking;
        _layerController.enableDeltaTracking =
            false; // Don't record delta for init sync
        _layerController.addImage(imageElement);
        _layerController.enableDeltaTracking = wasTracking;
      }
      _preloadImage(
        imageElement.imagePath,
        storageUrl: imageElement.storageUrl,
        thumbnailUrl: imageElement.thumbnailUrl,
      );
    }

    // 🛠️ FORCE FINAL REBUILD to ensure everything is rendered
    if (mounted) {
      setState(() {
        // Dati caricati completamente - forza rebuild finale
      });
    }
  }

  ///  Callback called when the layer controller notifica modifiche
  void _onLayerChanged() {
    // 🔧 FIX ZOOM LAG: Update list cache
    _refreshCachedLists();

    // Auto-save only thef not stiamo caricando
    if (!_isLoading) {
      _autoSaveCanvas();
    }
  }

  /// 🔧 Update le liste cachate da _layerController
  void _refreshCachedLists() {
    // 🎬 Durante Time Travel, le strokes vengono dal engine, non dal controller
    if (_isTimeTravelMode && _timeTravelEngine != null) return;

    _cachedAllShapes = _layerController.getAllVisibleShapes();

    // 🖼️ Sync images from layers (handles add, update, and remove from remote deltas)
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

    // 🚀 DYNAMIC CANVAS: Expand if content exceeds 50% of size
    _expandCanvasIfNeeded();
  }

  /// 🚀 Espande il canvas in TUTTE e 4 le direzioni:
  /// - Right/Bottom: doubles size when content > 80%
  /// - Left/Top: shifts ALL coordinates and compensates controller offset
  ///
  /// Guarded: NON espande durante caricamento iniziale.
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

    // SizedBox deve coprire il contenuto in tutte le direzioni
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

    try {
      final file = File(imagePath);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        final image = await _decodeImageCapped(bytes);
        if (mounted && image != null) {
          setState(() {
            _loadedImages[imagePath] = image;
          });
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
              });
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
        final image = await _decodeImageCapped(bytes);
        if (mounted && image != null) {
          // Dispose old thumbnail if it was loaded
          final oldImage = _loadedImages[imagePath];
          setState(() {
            _loadedImages[imagePath] = image;
          });
          oldImage?.dispose();
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
      if (originalWidth <= _NebulaCanvasScreenState._maxImageDimension &&
          originalHeight <= _NebulaCanvasScreenState._maxImageDimension) {
        return frame.image;
      }

      // Dispose full-res and re-decode at capped size
      frame.image.dispose();
      codec.dispose();

      // Calculate target dimensions preserving aspect ratio
      int targetWidth;
      int targetHeight;
      if (originalWidth >= originalHeight) {
        targetWidth = _NebulaCanvasScreenState._maxImageDimension;
        targetHeight =
            (originalHeight *
                    _NebulaCanvasScreenState._maxImageDimension /
                    originalWidth)
                .round();
      } else {
        targetHeight = _NebulaCanvasScreenState._maxImageDimension;
        targetWidth =
            (originalWidth *
                    _NebulaCanvasScreenState._maxImageDimension /
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

  /// 🎤 Load saved recordings tramite VoiceRecordingService
  /// Phase 2: voice recordings will be re-enabled
  Future<void> _loadSavedRecordings() async {
    try {
      // Phase 2: VoiceRecordingService stub returns empty list
      final recordings = await VoiceRecordingService.getRecordingsForParent(
        _canvasId,
      );

      final audioFiles = <String>[];
      final loadedSyncRecordings = <SynchronizedRecording>[];

      for (final rec in recordings) {
        // Add audio path to saved recordings
        final recAudioPath = (rec as dynamic).audioPath as String?;
        if (recAudioPath != null) {
          audioFiles.add(recAudioPath);
        }

        // If is una registrazione con tratti, carica il JSON
        final recType = (rec as dynamic).recordingType as String?;
        final recStrokesPath = (rec as dynamic).strokesDataPath as String?;
        if (recType == 'with_strokes' && recStrokesPath != null) {
          final file = File(recStrokesPath);
          if (await file.exists()) {
            try {
              final jsonString = await file.readAsString();
              final syncRecording = SynchronizedRecording.fromJsonString(
                jsonString,
              );
              // 🔄 Update audio path in syncRecording for safety
              // (ensures it points to the correct audio file managed by the service)
              if (recAudioPath != null) {
                loadedSyncRecordings.add(
                  syncRecording.copyWith(audioPath: recAudioPath),
                );
              } else {
                loadedSyncRecordings.add(syncRecording);
              }
            } catch (e) {}
          } else {
            // TODO: Handle download from strokesDataUrl if missing locally
          }
        }
      }

      if (mounted) {
        setState(() {
          _savedRecordings = audioFiles;
          _syncedRecordings = loadedSyncRecordings;
        });
      }
    } catch (e) {}
  }

  // ============================================================================
  // ⏱️ TIME TRAVEL LIFECYCLE → see _lifecycle_time_travel.dart
  // 🌿 CREATIVE BRANCHING LIFECYCLE → see _lifecycle_branching.dart
  // ============================================================================
}
