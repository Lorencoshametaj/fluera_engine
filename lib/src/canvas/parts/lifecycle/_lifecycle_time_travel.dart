part of '../../nebula_canvas_screen.dart';

// ============================================================================
// ⏱️ TIME TRAVEL LIFECYCLE
// Extracted from _lifecycle.dart — init, enter/exit, flush, export, recovery
// ============================================================================

extension on _NebulaCanvasScreenState {
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

    // 📸 Save live layers before time travel overwrites them
    _savedLiveLayersBeforeTimeTravel = List.from(_layerController.layers);

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
      // 🌲 Inject historical layers into LayerController → auto-invalidates SceneGraph
      _layerController.clearAllAndLoadLayers(_timeTravelEngine!.currentLayers);
      setState(() {
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

    // 🔄 Restore live layers from before time travel
    _layerController.clearAllAndLoadLayers(_savedLiveLayersBeforeTimeTravel);
    _savedLiveLayersBeforeTimeTravel = const [];
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
}
