part of '../../fluera_canvas_screen.dart';

// ============================================================================
// ⏱️ TIME TRAVEL LIFECYCLE
// Extracted from _lifecycle.dart — init, enter/exit, flush, export, recovery
// ============================================================================

extension on _FlueraCanvasScreenState {
  /// ⏱️ Initialize il Time Travel Recorder (solo per utenti Pro)
  ///
  /// Called after the canvas loading. The recorder is a listener
  /// passivo che accumula eventi in memoria con 0ms di overhead sul disegno.
  /// Also ensures a "main" branch exists for branch-first architecture.
  Future<void> _initTimeTravelRecorder() async {
    final isProUser = _config.subscriptionTier == FlueraSubscriptionTier.pro;

    if (!isProUser) {
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
    }
  }

  /// ▶️ Enamong then mode Time Travel (carica, inizializza engine, mostra overlay)
  ///
  /// 💡 Critical flush: the current session is still in memory in the recorder.
  /// Deve essere scritta to disk PRIMA di inizializzare il playback engine,
  /// altrimenti l'engine non troverà gli eventi appena registrati.
  Future<void> _enterTimeTravelMode() async {
    if (_isTimeTravelMode) return;


    // 🖐️ Save current state and force pan mode (no drawing during time travel)
    _wasPanModeBeforeTimeTravel = _toolController.isPanMode;
    if (!_wasPanModeBeforeTimeTravel) {
      _toolController.togglePanMode();
    }

    setState(() {
      _isTimeTravelMode = true;
    });

    // 📸 Save live layers before time travel overwrites them
    _savedLiveLayersBeforeTimeTravel = List.from(_layerController.layers);

    // 💾 Flush current session to disk (events are still in-memory)
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
      } catch (e, st) {
      }
    } else {
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
        }
      } catch (e) {
      }
    }

    _timeTravelEngine = TimeTravelPlaybackEngine(
      storage: TimeTravelStorageService(),
    );

    final initialized = await _timeTravelEngine!.initialize(
      _canvasId,
      this as TickerProvider,
      branchId: _activeBranchId,
    );


    if (!initialized) {
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

  }

  /// ❌ Esci da mode Time Travel (ripristina canvas live)
  void _exitTimeTravelMode() {
    _timeTravelEngine?.onStateChanged = null;
    _timeTravelEngine?.dispose();
    _timeTravelEngine = null;

    // 🔄 Restart recording with a new recorder for the next session
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

    // 🖐️ Restore previous pan state
    if (!_wasPanModeBeforeTimeTravel && _toolController.isPanMode) {
      _toolController.togglePanMode();
    }

    setState(() {
      _isTimeTravelMode = false;
    });

  }

  /// 🎬 Esporta il timelapse video del Time Travel
  void _exportTimelapse() {
    if (_timeTravelEngine == null) return;

    // Pause playback during export
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


    // Strokes: sposta ogni punto
    for (final stroke in _pendingRecoveryStrokes) {
      final movedPoints =
          stroke.points.map((pt) {
            return pt.copyWith(position: pt.position + offset);
          }).toList();

      final recovered = stroke.copyWith(
        id: generateUid(),
        createdAt: DateTime.now(),
        points: movedPoints,
      );
      _layerController.addStroke(recovered);
    }

    // Shapes: sposta startPoint e endPoint
    for (final shape in _pendingRecoveryShapes) {
      final recovered = shape.copyWith(
        id: generateUid(),
        createdAt: DateTime.now(),
        startPoint: shape.startPoint + offset,
        endPoint: shape.endPoint + offset,
      );
      _layerController.addShape(recovered);
    }

    // Images: sposta position + verifica file
    for (final image in _pendingRecoveryImages) {
      if (!kIsWeb) {
        final file = File(image.imagePath);
        if (!file.existsSync()) {
          continue;
        }
      }

      final recovered = image.copyWith(
        id: generateUid(),
        createdAt: DateTime.now(),
        position: image.position + offset,
      );
      _layerController.addImage(recovered);
    }

    // Texts: sposta position
    for (final text in _pendingRecoveryTexts) {
      final recovered = text.copyWith(
        id: generateUid(),
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


    // Clear state
    _cancelRecoveryPlacement();

    // Feedback aptico
    HapticFeedback.mediumImpact();
  }

  /// 🔮 Cancel posizionamento recupero
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
