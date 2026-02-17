part of '../nebula_canvas_screen.dart';

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
      final ImageStream stream = provider.resolve(const ImageConfiguretion());
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
    } catch (e) {
    }
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
    _isLoading = true; // 🔄 Disable auto-save durante caricamento
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
    // 🛠️ APPLICAZIONE DEI DATI CON SETSTATE IMMEDIATO
    setState(() {
      // 🆕 Load titolo (se presente nel salvataggio)
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

    // 🛠️ FORZA REBUILD FINALE per assicurarsi che tutto sia renderizzato
    if (mounted) {
      setState(() {
        // Dati caricati completamente - forza rebuild finale
      });
    }
  }

  ///  Callback called when the layer controller notifica modifiche
  void _onLayerChanged() {
    // 🔧 FIX ZOOM LAG: Update cache delle liste
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

    _cachedAllStrokes = _layerController.getAllVisibleStrokes();
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

    // 🚀 DYNAMIC CANVAS: Espandi se contenuto supera il 50% della size
    _expandCanvasIfNeeded();
  }

  /// 🚀 Espande il canvas in TUTTE e 4 le direzioni:
  /// - Destra/Basso: raddoppia size quando contenuto > 80%
  /// - Sinistra/Alto: shifta TUTTE le coordinate e compensa offset controller
  ///
  /// Guarded: NON espande durante caricamento iniziale.
  void _expandCanvasIfNeeded() {
    if (_isLoading || _isImageEditFromInfiniteCanvas) return;

    double maxX = 0, maxY = 0;

    for (final stroke in _cachedAllStrokes) {
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


      // 🚀 Se 120Hz+, inizializza raw input processor
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
              // 🔄 Update l'audio path nel syncRecording per scurezza
              // (assicura che punti al file audio corretto gestito dal service)
              if (recAudioPath != null) {
                loadedSyncRecordings.add(
                  syncRecording.copyWith(audioPath: recAudioPath),
                );
              } else {
                loadedSyncRecordings.add(syncRecording);
              }

            } catch (e) {
            }
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

    } catch (e) {
    }
  }

  // ============================================================================
  // ⏱️ TIME TRAVEL LIFECYCLE
  // ============================================================================

  /// ⏱️ Initialize il Time Travel Recorder (solo per utenti Pro)
  ///
  /// Called after the canvas loading. The recorder is a listener
  /// passivo che accumula eventi in memoria con 0ms di overhead sul disegno.
  /// Also ensures a "main" branch exists for branch-first architecture.
  Future<void> _initTimeTravelRecorder() async {
    final isProUser = _config.subscriptionTier == NebulaSubscriptionTier.pro;

    if (!isProUser) {
      debugPrint('🎬 [TimeTravel] Feature not available (not Pro)');
      return;
    }

    _timeTravelRecorder = TimeTravelRecorder();
    _timeTravelRecorder!.startRecording();

    // 🌿 Ensure main branch exists (branch-first architecture)
    final userId = await _config.getUserId() ?? 'unknown';
    final manager = _getOrCreateBranchingManager();
    final mainBranch = await manager.ensureMainBranch(
      canvasId: _canvasId,
      createdBy: userId,
      snapshotLayers: _layerController.layers,
    );

    // Set active branch context
    _activeBranchId = mainBranch.id;
    _activeBranchName = mainBranch.name;
    _timeTravelRecorder!.activeBranchId = mainBranch.id;

    // 🎬 Wire: LayerController → TimeTravelRecorder
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

    debugPrint(
      '🎬 [TimeTravel] Recorder initialized for canvas $_canvasId '
      '(branch: ${mainBranch.name})',
    );
  }

  /// 💾 Flush Time Travel history to disk (chiamato alla chiusura of the canvas)
  ///
  /// Serialize + comprime gli eventi in un isolate → zero UI lag.
  /// Registra la sessione nell'indice for the futuro caricamento.
  Future<void> _flushTimeTravelOnClose() async {
    final recorder = _timeTravelRecorder;
    if (recorder == null || !recorder.hasEvents) return;

    recorder.stopRecording();

    try {
      final storageService = TimeTravelStorageService();
      await storageService.saveRecordedSession(
        recorder,
        _canvasId,
        currentLayers: _layerController.layers,
        branchId: _activeBranchId,
      );

      debugPrint(
        '🎬 [TimeTravel] Session flushed for canvas $_canvasId '
        '(branch: $_activeBranchId)',
      );

      // ☁️ Cloud sync: upload TT sessions + final snapshot on close
      if (_hasCloudSync && _activeBranchId != null) {
        final manager = _getOrCreateBranchingManager();
        await manager.uploadBranchTTSessions(_canvasId, _activeBranchId!);
        await manager.saveBranchWorkingState(
          _canvasId,
          _activeBranchId!,
          _layerController.layers,
        );
      }
    } catch (e) {
      debugPrint('🎬 [TimeTravel] Flush error: $e');
    }
  }

  /// ▶️ Enamong then mode Time Travel (carica, inizializza engine, mostra overlay)
  ///
  /// 💡 Flush critico: la sessione corrente is ancora in memoria nel recorder.
  /// Deve essere scritta to disk PRIMA di inizializzare il playback engine,
  /// altrimenti l'engine non troverà gli eventi appena registrati.
  Future<void> _enterTimeTravelMode() async {
    if (_isTimeTravelMode) return;

    debugPrint('🎬🔍 [TimeTravel] === ENTER MODE START ===');
    debugPrint('🎬🔍 [TimeTravel] canvasId: $_canvasId');
    debugPrint(
      '🎬🔍 [TimeTravel] recorder: ${_timeTravelRecorder != null ? "EXISTS" : "NULL"}',
    );
    debugPrint(
      '🎬🔍 [TimeTravel] recorder.isRecording: ${_timeTravelRecorder?.isRecording}',
    );
    debugPrint(
      '🎬🔍 [TimeTravel] recorder.hasEvents: ${_timeTravelRecorder?.hasEvents}',
    );
    debugPrint(
      '🎬🔍 [TimeTravel] recorder.eventCount: ${_timeTravelRecorder?.eventCount}',
    );

    // 🖐️ Save lo current state e forza pan mode (no disegno durante time travel)
    _wasPanModeBeforeTimeTravel = _toolController.isPanMode;
    if (!_wasPanModeBeforeTimeTravel) {
      _toolController.togglePanMode();
    }

    setState(() {
      _isTimeTravelMode = true;
    });

    // 💾 Flush sessione corrente to disk (gli eventi sono ancora in-memory)
    final recorder = _timeTravelRecorder;
    if (recorder != null && recorder.hasEvents) {
      debugPrint(
        '🎬🔍 [TimeTravel] Flushing ${recorder.eventCount} events to disk...',
      );
      recorder.stopRecording();
      try {
        final storageService = TimeTravelStorageService();
        await storageService.saveRecordedSession(
          recorder,
          _canvasId,
          currentLayers: _layerController.layers,
        );
        debugPrint(
          '🎬🔍 [TimeTravel] ✅ Pre-playback flush: ${recorder.eventCount} events saved',
        );
      } catch (e, st) {
        debugPrint('🎬🔍 [TimeTravel] ❌ Pre-playback flush error: $e');
        debugPrint('🎬🔍 [TimeTravel] Stack: $st');
      }
    } else {
      debugPrint(
        '🎬🔍 [TimeTravel] ⚠️ No events to flush (recorder=${recorder != null}, hasEvents=${recorder?.hasEvents})',
      );
    }

    // ☁️ Cloud sync: download remote TT sessions before initializing playback
    if (_hasCloudSync && _activeBranchId != null) {
      try {
        final manager = _getOrCreateBranchingManager();
        final downloaded = await manager.downloadBranchTTSessions(
          _canvasId,
          _activeBranchId!,
        );
        if (downloaded > 0) {
          debugPrint(
            '🎬🔍 [TimeTravel] Downloaded $downloaded remote TT sessions',
          );
        }
      } catch (e) {
        debugPrint('🎬 [TimeTravel] Remote TT download error: $e');
      }
    }

    debugPrint('🎬🔍 [TimeTravel] Initializing playback engine...');
    _timeTravelEngine = TimeTravelPlaybackEngine(
      storage: TimeTravelStorageService(),
    );

    final initialized = await _timeTravelEngine!.initialize(
      _canvasId,
      this as TickerProvider,
      branchId: _activeBranchId,
    );

    debugPrint(
      '🎬🔍 [TimeTravel] Engine initialized: $initialized, events: ${_timeTravelEngine!.totalEventCount}',
    );

    if (!initialized) {
      debugPrint('🎬🔍 [TimeTravel] ❌ No history found, exiting');
      // Riavvia recording se disponibile
      _timeTravelRecorder?.startRecording();
      setState(() {
        _isTimeTravelMode = false;
        _timeTravelEngine = null;
      });
      return;
    }

    // 🎯 Wire: engine state change → canvas repaint
    // Quando l'engine ricostruisce uno stato, swap le strokes nel painter
    _timeTravelEngine!.onStateChanged = () {
      if (!mounted) return;
      setState(() {
        _cachedAllStrokes =
            _timeTravelEngine!.currentLayers
                .where((l) => l.isVisible)
                .expand((l) => l.strokes)
                .toList();
        _cachedAllShapes =
            _timeTravelEngine!.currentLayers
                .where((l) => l.isVisible)
                .expand((l) => l.shapes)
                .toList();
      });
    };

    // Trigger initial rendering with the engine state
    _timeTravelEngine!.onStateChanged!();

    debugPrint(
      '🎬 [TimeTravel] Mode entered: ${_timeTravelEngine!.totalEventCount} events',
    );
  }

  /// ❌ Esci da mode Time Travel (ripristina canvas live)
  void _exitTimeTravelMode() {
    _timeTravelEngine?.onStateChanged = null;
    _timeTravelEngine?.dispose();
    _timeTravelEngine = null;

    // 🔄 Riavvia recording with a nuovo recorder for the sessione successiva
    if (_timeTravelRecorder != null) {
      _timeTravelRecorder = TimeTravelRecorder();
      _timeTravelRecorder!.startRecording();

      // Re-wire callback
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
    }

    // 🔄 Ripristina le strokes live dal LayerController
    _refreshCachedLists();

    // 🖐️ Ripristina lo stato pan precedente
    if (!_wasPanModeBeforeTimeTravel && _toolController.isPanMode) {
      _toolController.togglePanMode();
    }

    setState(() {
      _isTimeTravelMode = false;
    });

    debugPrint('🎬 [TimeTravel] Mode exited, new recording session started');
  }

  /// 🎬 Esporta il timelapse video del Time Travel
  void _exportTimelapse() {
    if (_timeTravelEngine == null) return;

    // Pausa playback durante l'export
    _timeTravelEngine!.pause();

    TimelapseExportDialog.show(
      context,
      engine: _timeTravelEngine!,
      totalEventCount: _timeTravelEngine!.totalEventCount,
    );
  }

  /// 🔮 Enamong then placement mode: salva gli elementi e mostra overlay posizionamento
  void _recoverElementsFromPast(
    List<ProStroke> strokes,
    List<GeometricShape> shapes,
    List<ImageElement> images,
    List<DigitalTextElement> texts,
  ) {
    final totalElements =
        strokes.length + shapes.length + images.length + texts.length;
    if (totalElements == 0) return;

    debugPrint(
      '🔮 [Recover] Entering placement mode with $totalElements elements',
    );

    // 1. Save elements for positioning
    _pendingRecoveryStrokes = strokes;
    _pendingRecoveryShapes = shapes;
    _pendingRecoveryImages = images;
    _pendingRecoveryTexts = texts;
    _recoveryPlacementOffset = Offset.zero;

    // 2. Esci dal Time Travel (ripristina canvas live)
    _exitTimeTravelMode();

    // 3. Attiva placement mode
    setState(() {
      _isRecoveryPlacementMode = true;
    });
  }

  /// 🔮 Confirm placement: apply offset and add to LayerController
  void _commitRecoveryPlacement() {
    final offset = _recoveryPlacementOffset;
    final uuid = const Uuid();

    debugPrint('🔮 [Recover] Committing with offset: $offset');

    // Strokes: sposta ogni punto
    for (final stroke in _pendingRecoveryStrokes) {
      final movedPoints =
          stroke.points.map((pt) {
            return pt.copyWith(position: pt.position + offset);
          }).toList();

      final recovered = stroke.copyWith(
        id: uuid.v4(),
        createdAt: DateTime.now(),
        points: movedPoints,
      );
      _layerController.addStroke(recovered);
    }

    // Shapes: sposta startPoint e endPoint
    for (final shape in _pendingRecoveryShapes) {
      final recovered = shape.copyWith(
        id: uuid.v4(),
        createdAt: DateTime.now(),
        startPoint: shape.startPoint + offset,
        endPoint: shape.endPoint + offset,
      );
      _layerController.addShape(recovered);
    }

    // Images: sposta position + verifica file
    for (final image in _pendingRecoveryImages) {
      final file = File(image.imagePath);
      if (!file.existsSync()) {
        debugPrint(
          '🔮 [Recover] ⚠️ Skipping image ${image.id}: '
          'file not found at ${image.imagePath}',
        );
        continue;
      }

      final recovered = image.copyWith(
        id: uuid.v4(),
        createdAt: DateTime.now(),
        position: image.position + offset,
      );
      _layerController.addImage(recovered);
    }

    // Texts: sposta position
    for (final text in _pendingRecoveryTexts) {
      final recovered = text.copyWith(
        id: uuid.v4(),
        createdAt: DateTime.now(),
        position: text.position + offset,
      );
      _layerController.addText(recovered);
    }

    final total =
        _pendingRecoveryStrokes.length +
        _pendingRecoveryShapes.length +
        _pendingRecoveryImages.length +
        _pendingRecoveryTexts.length;

    debugPrint('🔮 [Recover] ✅ Committed $total elements');

    // Clear stato
    _cancelRecoveryPlacement();

    // Feedback aptico
    HapticFeedback.mediumImpact();
  }

  /// 🔮 Annulla posizionamento recupero
  void _cancelRecoveryPlacement() {
    setState(() {
      _isRecoveryPlacementMode = false;
      _pendingRecoveryStrokes = [];
      _pendingRecoveryShapes = [];
      _pendingRecoveryImages = [];
      _pendingRecoveryTexts = [];
      _recoveryPlacementOffset = Offset.zero;
    });
  }

  // ============================================================================
  // 🌿 CREATIVE BRANCHING LIFECYCLE
  // ============================================================================

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
    final nameController = TextEditingController(
      text:
          'Branch ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}',
    );

    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
          title: const Row(
            children: [
              Icon(Icons.alt_route_rounded, color: Color(0xFF7C4DFF), size: 22),
              SizedBox(width: 8),
              Text('New Branch'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Fork from event $currentIndex of ${engine.totalEventCount}',
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
                  hintText: 'Branch name',
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
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final n = nameController.text.trim();
                Navigator.pop(ctx, n.isEmpty ? 'Untitled Branch' : n);
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7C4DFF),
              ),
              child: const Text('Create'),
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

      debugPrint(
        '🌿 [Branching] Created branch "${branch.name}" '
        'at event $currentIndex',
      );

      // Switch to the new branch
      _switchToBranch(branch.id);
    } catch (e) {
      debugPrint('🌿 [Branching] ❌ Create branch error: $e');
    }
  }

  /// 🌿 Switch to a branch — swaps canvas state
  ///
  /// 1. Flush current branch's in-memory events to disk
  /// 2. Load target branch's snapshot into LayerController
  /// 3. Update recording context for new branch
  /// 4. If in TT mode: re-enter TT for the new branch
  Future<void> _switchToBranch(String? branchId) async {
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
        debugPrint(
          '🌿 [Branching] Flushed ${recorder.eventCount} events '
          'for branch $_activeBranchId',
        );
      } catch (e) {
        debugPrint('🌿 [Branching] Flush error: $e');
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
      debugPrint(
        '🌿 [Branching] Loaded ${layers.length} layers for branch $branchId',
      );
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

    debugPrint(
      '🌿 [Branching] Switched to ${branch?.name ?? "main"} '
      '(wasInTT: $wasInTimeTravel)',
    );

    // 6. Re-enter TT for the branch only if we were in TT before
    if (wasInTimeTravel) {
      await _enterTimeTravelMode();
    }
  }

  /// 🌿 Open the Branch Explorer bottom sheet
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
          }) => _handleBranchMerge(
            sourceBranchId,
            targetBranchId: targetBranchId,
            deleteAfterMerge: deleteAfterMerge,
          ),
    );
  }

  /// 🔀 Handle branch merge (any child → parent, git-style)
  ///
  /// Merges the source branch's layers into the target, reloads the canvas,
  /// and switches context to the target branch. Cloud sync is triggered
  /// automatically by [saveBranchWorkingState] inside [mergeBranch].
  Future<void> _handleBranchMerge(
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
      debugPrint(
        '❌ [Branching] Merge failed: $sourceBranchId → $targetBranchId',
      );
      return;
    }

    // 3. Switch to the target branch with the merged layers
    await _switchToBranch(targetBranchId);

    debugPrint(
      '🔀 [Branching] Merge complete: $sourceBranchId → $targetBranchId '
      '(${mergedLayers.length} layers, delete=$deleteAfterMerge)',
    );
  }

  /// 🗑️ Handle branch deletion — switch to main and clean up
  Future<void> _handleBranchDeleted(String deletedBranchId) async {
    debugPrint(
      '🌿 [Branching] Branch $deletedBranchId deleted, switching to main',
    );

    // Clean up TT storage for the deleted branch
    try {
      final storageService = TimeTravelStorageService();
      await storageService.deleteHistory(_canvasId, branchId: deletedBranchId);
    } catch (e) {
      debugPrint('🌿 [Branching] TT cleanup error: $e');
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
            title: const Text('New Branch'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Fork from "${_activeBranchName ?? "main"}"',
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
                    hintText: 'Branch name',
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
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final n = nameController.text.trim();
                  Navigator.pop(ctx, n.isEmpty ? 'Untitled Branch' : n);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF7C4DFF),
                ),
                child: const Text('Create'),
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

      debugPrint(
        '🌿 [Branching] Created branch "${branch.name}" from explorer',
      );

      // Switch to the new branch
      _switchToBranch(branch.id);
    } catch (e) {
      debugPrint('🌿 [Branching] ❌ Create branch error: $e');
    }
  }
}
