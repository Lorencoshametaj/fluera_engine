import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../drawing/brushes/brush_texture.dart';

import 'package:flutter/services.dart';
// import 'package:path_provider/path_provider.dart'; // Phase 2
import 'package:uuid/uuid.dart';
import '../drawing/models/pro_drawing_point.dart';
import '../drawing/models/pro_brush_settings.dart';
import '../drawing/models/pro_brush_settings_dialog.dart';
import '../drawing/services/brush_preset_manager.dart';

import '../drawing/services/brush_settings_service.dart';
import '../core/models/shape_type.dart';
import '../core/models/digital_text_element.dart';
import '../core/models/image_element.dart';
import '../core/models/canvas_layer.dart';
import '../export/export_preset.dart';
import '../export/saved_export_area.dart';
import '../config/multi_page_config.dart';
import '../drawing/input/drawing_input_handler.dart';
import '../rendering/canvas/background_painter.dart';
import '../rendering/shaders/shader_brush_service.dart';
import '../rendering/canvas/drawing_painter.dart';
import '../rendering/canvas/origin_indicator_painter.dart';
import '../rendering/canvas/current_stroke_painter.dart';
import '../rendering/canvas/pro_stroke_painter.dart';

import '../rendering/optimization/stroke_data_manager.dart';
import '../drawing/services/stroke_persistence_service.dart';
import '../rendering/canvas/image_painter.dart';
import './toolbar/professional_canvas_toolbar.dart';
import './infinite_canvas_controller.dart';
import './infinite_canvas_gesture_detector.dart';
import '../layers/layer_controller.dart';
import '../layers/widgets/layer_panel.dart';
// import '../../widgets/export_area_selector.dart'; // Phase 2: Export
// import '../../widgets/export_mode_toolbar.dart'; // Phase 2: Export mode
// import '../../widgets/multi_page_preview_overlay.dart'; // Phase 2: Export
// import '../../widgets/interactive_page_grid_overlay.dart'; // Phase 2
import '../tools/eraser/eraser_tool.dart';
import '../tools/eraser/eraser_hit_tester.dart';
import '../tools/lasso/lasso_tool.dart';
import '../tools/lasso/lasso_path_painter.dart';
import '../tools/lasso/lasso_selection_overlay.dart';
import '../tools/text/digital_text_tool.dart';
import '../tools/image/image_tool.dart';
import '../tools/ruler/ruler_guide_system.dart';
import '../tools/flood_fill/flood_fill_tool.dart';
import '../tools/pen/pen_tool.dart';
import '../tools/base/tool_context.dart';
import '../layers/adapters/infinite_canvas_adapter.dart';

import '../tools/ruler/ruler_interactive_overlay.dart';
import './overlays/selection_transform_overlay.dart';
import '../dialogs/digital_text_input_dialog.dart';
import '../dialogs/image_editor_dialog.dart';
// import '../../widgets/audio_player_banner.dart'; // Phase 2: Audio
// import '../../services/ocr_service.dart'; // Phase 2: OCR
import '../services/image_service.dart';
// import '../../services/recording_service.dart'; // Phase 2: Recording
import '../services/adaptive_debouncer_service.dart';
import '../drawing/input/raw_input_processor_120hz.dart';
import '../history/canvas_delta_tracker.dart';
import '../history/background_checkpoint_service.dart';
import '../collaboration/canvas_realtime_sync_manager.dart';
import '../drawing/input/stroke_point_pool.dart';
import '../drawing/input/path_pool.dart';
import '../time_travel/models/synchronized_recording.dart';
import '../time_travel/controllers/synchronized_playback_controller.dart';
import '../time_travel/widgets/synchronized_playback_overlay.dart';
import '../collaboration/widgets/canvas_presence_overlay.dart';
import './overlays/canvas_viewport_overlay.dart';
import '../time_travel/services/time_travel_recorder.dart';
import '../services/phase2_service_stubs.dart'; // Stub implementations for Phase 2 services
import '../time_travel/services/time_travel_playback_engine.dart';
// import '../../widgets/time_travel_timeline_widget.dart'; // Phase 2
// import '../../widgets/time_travel_lasso_overlay.dart'; // Phase 2
// import '../../widgets/recovery_placement_overlay.dart'; // Phase 2
import '../history/branching_manager.dart';
import '../history/widgets/branch_explorer_sheet.dart';

import '../tools/base/tool_bridge.dart';
import '../tools/unified_tool_controller.dart';
import './toolbar/menus/selection_actions_menu.dart';
import './toolbar/menus/image_action_button.dart';
// import '../../widgets/dialogs/recordings_list_dialog.dart'; // Phase 2: Recordings UI
import '../rendering/canvas/canvas_painters.dart';
import '../dialogs/canvas_settings_dialog.dart';

// ── SDK Config (Dependency Inversion) ──────────────────────────────────────
import './nebula_canvas_config.dart';
import '../platform/display_capabilities_detector.dart';
import '../config/adaptive_rendering_config.dart';

// ============================================================================
// PART FILES
// ============================================================================

// 🔄 Lifecycle
part './parts/lifecycle/_lifecycle.dart';
part './parts/lifecycle/_lifecycle_time_travel.dart';
part './parts/lifecycle/_lifecycle_branching.dart';

// 🤝 Features
part './parts/_collaboration.dart';
part './parts/_canvas_operations.dart';
part './parts/_export.dart';
part './parts/_text_tools.dart';
part './parts/_image_features.dart';
part './parts/_voice_recording.dart';
// part 'parts/_navigation_pdf.dart';  // Phase 2: PDF navigation
part './parts/_cloud_sync.dart';
part './parts/_phase2_stubs.dart';

// ✏️ Drawing
part './parts/drawing/_drawing_handlers.dart';
part './parts/drawing/_drawing_update.dart';
part './parts/drawing/_drawing_end.dart';
part './parts/drawing/_drawing_aux.dart';

// 🎨 UI
part './parts/ui/_build_ui.dart';
part './parts/ui/_ui_toolbar.dart';
part './parts/ui/_ui_canvas_layer.dart';
part './parts/ui/_ui_eraser.dart';
part './parts/ui/_ui_overlays.dart';
part './parts/ui/_ui_menus.dart';

// 🧹 Eraser Painters
part './parts/eraser/_eraser_painters.dart';
part './parts/eraser/_eraser_painters_v6.dart';
part './parts/eraser/_eraser_painters_v7.dart';

/// 🚀 PERFORMANCE: Notifier ottimizzato for the current stroke
/// Use in-place mutation + notifyListeners() forzato to avoid copie.
/// NON assegna `value = stroke` to avoid doppia notifica.
class _StrokeNotifier extends ValueNotifier<List<ProDrawingPoint>> {
  _StrokeNotifier() : super([]);

  /// Number of points that were actually painted on-screen.
  /// Updated by CurrentStrokePainter on each paint() call.
  /// Used to trim unseen trailing points on finalization so the
  /// completed stroke doesn't extend beyond what the user saw.
  int lastRenderedCount = 0;

  /// Forza repaint dopo mutazione in-place della lista.
  /// The lista viene modificata direttamente (add/clear), qui notifichiamo solo.
  void forceRepaint() {
    notifyListeners();
  }

  /// Replace il riferimento alla lista e notifica.
  /// Usato only when serve un nuovo riferimento (es. inizio stroke).
  void setStroke(List<ProDrawingPoint> stroke) {
    value = stroke;
  }

  /// Clears the stroke
  void clear() {
    value = [];
    lastRenderedCount = 0;
  }
}

/// 🎨 NEBULA CANVAS SCREEN — SDK-level Professional Canvas
///
/// Caratteristiche:
/// - Canvas infinito con zoom e pan
/// - Zero latency con ValueNotifier
/// - Smoothing adattivo OneEuroFilter
/// - Post-stroke optimization con Douglas-Peucker
/// - Rendering vettoriale puro (no GPU cache)
/// - Triplo smoothing per fountain pen
/// - Physics-based ink simulation
/// - 💾 AUTO-SAVE ad ogni tratto/modifica (via NebulaCanvasConfig)
///
/// All external dependencies (Firebase, auth, subscription, sync) are
/// injected via [NebulaCanvasConfig] — no direct app coupling.
class NebulaCanvasScreen extends StatefulWidget {
  /// SDK configuration — all external deps injected here
  final NebulaCanvasConfig config;

  /// 🆕 ID univoco of the canvas (collegato a infinite canvas node)
  final String? canvasId;

  /// 🆕 Titolo of the canvas (opzionale)
  final String? title;

  /// 🔥 ID of the canvas infinito (per sync)
  final String? infiniteCanvasId;

  /// 🔥 ID del nodo nell'infinite canvas (per sync)
  final String? nodeId;

  /// 🖼️ Background image URL (for image editing mode)
  final String? backgroundImageUrl;

  /// 🎯 Nascondi toolbar (per uso nel multiview)
  final bool hideToolbar;

  /// 🖼️ Callback per richiedere aggiunta immagine dall'esterno (multiview)
  final VoidCallback? onAddImageRequested;

  /// 🎤 Controller playback opzionale (per split view con sync)
  final SynchronizedPlaybackController? externalPlaybackController;

  /// 📄 Pagina specifica per playback (se usato in split view)
  final int? playbackPageIndex;

  /// 🎤 Callback to notify the addition of an external stroke
  final void Function(ProStroke stroke, DateTime startTime, DateTime endTime)?
  onExternalStrokeAdded;

  const NebulaCanvasScreen({
    super.key,
    required this.config,
    this.canvasId,
    this.title,
    this.infiniteCanvasId,
    this.nodeId,
    this.backgroundImageUrl,
    this.hideToolbar = false,
    this.onAddImageRequested,
    this.externalPlaybackController,
    this.playbackPageIndex,
    this.onExternalStrokeAdded,
  });

  @override
  State<NebulaCanvasScreen> createState() => _NebulaCanvasScreenState();
}

class _NebulaCanvasScreenState extends State<NebulaCanvasScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  // ── SDK Config shortcut ──────────────────────────────────────────────────
  NebulaCanvasConfig get _config => widget.config;

  // ── Tool state (replaces Riverpod canvasProvider) ────────────────────────
  late final UnifiedToolController _toolController;

  // ============================================================================
  // STATE MANAGEMENT
  // ============================================================================

  /// 🆕 ID univoco of the canvas (generato o ricevuto)
  late final String _canvasId;

  /// 🆕 Nome/Titolo della nota (caricato o ricevuto)
  String? _noteTitle;

  // ============================================================================
  // 🔄 REAL-TIME COLLABORATION STATE
  // ============================================================================

  /// 🔄 Real-time sync manager (inbound deltas from collaborators)
  CanvasRealtimeSyncManager? _realtimeSyncManager;

  /// 🤝 Is this canvas shared with other users?
  bool _isSharedCanvas = false;

  /// 🔒 Is the current user in view-only mode?
  bool _isViewerMode = false;

  /// 💎 Cached subscription tier
  NebulaSubscriptionTier get _subscriptionTier => _config.subscriptionTier;

  /// 💎 Convenience: has cloud sync
  bool get _hasCloudSync => _subscriptionTier.canUseCloudSync;

  /// 💎 Convenience: has real-time collaboration
  bool get _hasRealtimeCollab => _subscriptionTier.canCollaborate;

  /// ⚡ Throttle cursor feed (200ms)
  int _lastCursorFeedTime = 0;

  /// 👁️ Follow mode: track which user we're following
  String? _followingUserId;

  // ============================================================================
  // 🖥️ DISPLAY CAPABILITIES & ADAPTIVE RENDERING (120Hz Support)
  // ============================================================================

  /// Detected display capabilities (refresh rate, frame budget)
  DisplayCapabilities? _displayCapabilities;

  /// Configuretion rendering adattiva basata su display
  AdaptiveRenderingConfig? _renderingConfig;

  /// Raw input processor per 120Hz mode (quando applicabile)
  RawInputProcessor120Hz? _rawInputProcessor120Hz;

  /// ⏱️ Timer per debouncing save
  Timer? _saveDebounceTimer;

  /// 🔄 Flag per disabilitare auto-save durante caricamento
  bool _isLoading = false;

  /// Layer controller per gestire i layer
  late final LayerController _layerController;

  /// 🔧 FIX ZOOM LAG: Cache delle liste strokes/shapes
  List<ProStroke> _cachedAllStrokes = const [];
  List<GeometricShape> _cachedAllShapes = const [];

  /// Layer panel key per controllare apertura/chiusura
  final GlobalKey<LayerPanelState> _layerPanelKey = GlobalKey();

  /// Notifier per indicare quando l'utente sta disegnando
  final ValueNotifier<bool> _isDrawingNotifier = ValueNotifier(false);

  /// 🚀 PERFORMANCE: Tratto corrente con notifier ottimizzato
  final _StrokeNotifier _currentStrokeNotifier = _StrokeNotifier();

  /// Shape corrente in disegno
  final ValueNotifier<GeometricShape?> _currentShapeNotifier = ValueNotifier(
    null,
  );

  /// Canvas infinito controller
  late final InfiniteCanvasController _canvasController;

  /// 🆕 Drawing input handler (logica condivisa)
  late final DrawingInputHandler _drawingHandler;

  /// Brush settings
  ProBrushSettings _brushSettings = const ProBrushSettings();

  /// 🎨 Phase 4C: Brush Preset Manager
  final BrushPresetManager _brushPresetManager = BrushPresetManager();
  bool _presetsLoaded = false;
  String? _selectedPresetId;

  // ============================================================================
  // 🎛️ GETTERS PER TOOL STATE (UnifiedToolController-native)
  // ============================================================================

  /// Pen type effettivo
  ProPenType get _effectivePenType => _toolController.penType;

  /// Effective color
  Color get _effectiveSelectedColor => _toolController.color;

  /// Larghezza effettiva
  double get _effectiveWidth => _toolController.width;

  /// Opacity effettiva
  double get _effectiveOpacity => _toolController.opacity;

  /// Shape type effettivo
  ShapeType get _effectiveShapeType => _toolController.shapeType;

  /// Eraser active
  bool get _effectiveIsEraser => _toolController.isEraserMode;

  /// Lasso active
  bool get _effectiveIsLasso => _toolController.isLassoMode;

  /// Pan mode active
  bool get _effectiveIsPanMode => _toolController.isPanMode;

  /// Stylus mode
  bool get _effectiveIsStylusMode => _toolController.isStylusMode;

  /// Digital text mode
  bool get _effectiveIsDigitalText => _toolController.isTextMode;

  /// 🪣 Fill mode active
  bool get _effectiveIsFill => _toolController.isFillMode;

  /// 🚀 120Hz Mode
  bool get _is120HzMode =>
      _displayCapabilities != null &&
      _displayCapabilities!.refreshRate.value >= 120;

  /// 🖼️ Modalità editing immagine DA INFINITE CANVAS
  bool get _isImageEditFromInfiniteCanvas => widget.backgroundImageUrl != null;

  /// 📐 Dimensioni of the canvas
  Size get _canvasSize {
    if (_isImageEditFromInfiniteCanvas && _backgroundImage != null) {
      final size = Size(
        _backgroundImage!.width.toDouble(),
        _backgroundImage!.height.toDouble(),
      );
      return size;
    }
    return _dynamicCanvasSize;
  }

  /// 🚀 DYNAMIC CANVAS: size attuale
  Size _dynamicCanvasSize = const Size(5000, 5000);

  /// Canvas settings
  Color _canvasBackgroundColor = Colors.white;
  String _paperType = 'blank';

  /// Undo/Redo
  final List<ProStroke> _undoStack = [];

  /// Effective color with applied opacity
  Color get _effectiveColor =>
      _effectiveSelectedColor.withValues(alpha: _effectiveOpacity);

  /// Auto-scroll durante il drag
  Timer? _autoScrollTimer;
  final GlobalKey _canvasAreaKey = GlobalKey();
  static const double _edgeScrollThreshold = 50.0;
  static const double _scrollSpeed = 5.0;

  // ============================================================================
  // LIFECYCLE
  // ============================================================================

  /// Eraser tool
  late final EraserTool _eraserTool;

  /// Lasso tool
  late final LassoTool _lassoTool;

  // === PHASE 3 TOOLS ===
  final RulerGuideSystem _rulerGuideSystem = RulerGuideSystem();
  final FloodFillTool _floodFillTool = FloodFillTool();
  bool _showRulers = false;

  /// ✒️ PEN TOOL (vector path editor)
  late final PenTool _penTool;

  /// ✒️ Cached adapter for pen tool (avoids re-creation every frame)
  late final InfiniteCanvasAdapter _penToolAdapter;

  /// ✒️ Creates a ToolContext for the pen tool using current canvas state
  ToolContext get _penToolContext => ToolContext(
    adapter: _penToolAdapter,
    layerController: _layerController,
    scale: _canvasController.scale,
    viewOffset: _canvasController.offset,
    viewportSize: MediaQuery.of(context).size,
    settings: const ToolSettings(),
  );

  /// 🏗️ UNIFIED TOOL SYSTEM
  UnifiedToolController? _unifiedToolController;
  ToolSystemBridge? _toolSystemBridge;

  /// Digital text tool
  late final DigitalTextTool _digitalTextTool;
  final List<DigitalTextElement> _digitalTextElements = [];

  /// 🖼️ Image tool
  late final ImageTool _imageTool;
  final List<ImageElement> _imageElements = [];
  final Map<String, ui.Image> _loadedImages = {};

  /// 🔄 Loading pulse animation for image placeholders
  Timer? _loadingPulseTimer;
  double _loadingPulseValue = 0.0;

  /// 🎤 Real-time listener for remote recordings
  StreamSubscription? _recordingsListener;

  /// 🔒 Guard: recording IDs currently being downloaded
  final Set<String> _downloadingRecordingIds = {};

  /// 🖼️ Immagine di sfondo
  ui.Image? _backgroundImage;

  /// Timer for theng press su immagini
  Timer? _imageLongPressTimer;
  Timer? _imageLongPressEditorTimer;

  /// Tracciamento movimento
  Offset? _initialTapPosition;
  static const double _dragThreshold = 25.0;

  /// 🔄 SYNC: Throttle for real-time drag broadcast (100ms)
  int _lastDragSyncTime = 0;
  static const int _dragSyncThrottleMs = 100;

  /// 🏗️ Position corrente del cursore eraser
  Offset? _eraserCursorPosition;

  /// 🎯 Eraser overlay state
  late final AnimationController _eraserPulseController;
  final List<_EraserTrailPoint> _eraserTrail = [];
  Set<String> _eraserPreviewIds = {};
  int _eraserGestureEraseCount = 0;

  /// 🎯 V3: Continuous interpolation + speed-based radius
  Offset? _lastEraserCanvasPosition;
  int _lastEraserMoveTime = 0;
  double _eraserSmoothedRadius = 20.0;
  int _lastEraserPointerDownTime = 0;
  int _eraserTapCount = 0;
  final List<_EraserParticle> _eraserParticles = [];

  /// 🎯 V4: Lasso eraser mode
  bool _eraserLassoMode = false;
  final List<Offset> _eraserLassoPoints = [];
  double? _eraserPinchBaseRadius;

  /// 🎯 V5: Tilt tracking
  double _eraserTiltX = 0.0;
  double _eraserTiltY = 0.0;
  bool _showEraserShortcutRing = false;
  bool _eraserLassoAnimating = false;

  // ─── V6 State ──────────────────────────────────────────────────────
  Set<String> _autoCleanSuggestions = {};
  bool _eraserShowDissolve = false;
  bool _eraserMaskPreview = false;
  bool _showEraserTimeline = false;

  // ─── V7 State ──────────────────────────────────────────────────────
  String? _smartSelectionStrokeId;
  bool _showUndoGhostReplay = false;
  bool _showPressureCurveEditor = false;
  bool _showLayerPreview = false;
  int _eraserShapeMode = 0;

  /// Modalità editing immagine
  ImageElement? _imageInEditMode;
  final ValueNotifier<ProStroke?> _currentEditingStrokeNotifier = ValueNotifier(
    null,
  );
  final List<ProStroke> _imageEditingStrokes = [];
  final List<ProStroke> _imageEditingUndoStack = [];

  // 🎤 State per tracking temporale strokes
  DateTime? _lastStrokeStartTime;

  /// 🎤 Audio recording controller
  AudioRecordingController? _audioRecordingController;
  bool _isRecordingAudio = false;
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;
  StreamSubscription<Duration>? _recordingDurationSubscription;
  List<String> _savedRecordings = [];
  bool _recordingWithStrokes = false;
  DateTime? _recordingStartTime;

  /// 🎵 Registrazione sincronizzata con tratti
  SynchronizedRecordingBuilder? _syncRecordingBuilder;
  DateTime? _currentStrokeStartTime;
  List<SynchronizedRecording> _syncedRecordings = [];
  SynchronizedPlaybackController? _playbackController;
  bool _isPlayingSyncedRecording = false;

  /// 🎧 Audio player state
  String? _playingAudioPath;

  // ============================================================================
  // 📤 EXPORT MODE STATE
  // ============================================================================

  bool _isExportMode = false;
  Rect _exportArea = Rect.zero;
  ExportConfig _exportConfig = const ExportConfig();
  ExportProgressController? _exportProgressController;

  // ============================================================================
  // 📤 MULTI-PAGE EDIT MODE STATE
  // ============================================================================

  bool _isMultiPageEditMode = false;
  MultiPageConfig _multiPageConfig = const MultiPageConfig();

  // ============================================================================
  // ⏱️ TIME TRAVEL STATE
  // ============================================================================

  bool _isTimeTravelMode = false;
  bool _wasPanModeBeforeTimeTravel = false;
  bool _isTimeTravelLassoMode = false;
  bool _isRecoveryPlacementMode = false;
  List<ProStroke> _pendingRecoveryStrokes = [];
  List<GeometricShape> _pendingRecoveryShapes = [];
  List<ImageElement> _pendingRecoveryImages = [];
  List<DigitalTextElement> _pendingRecoveryTexts = [];
  Offset _recoveryPlacementOffset = Offset.zero;

  TimeTravelRecorder? _timeTravelRecorder;
  TimeTravelPlaybackEngine? _timeTravelEngine;

  /// 🌿 Creative Branching
  BranchingManager? _branchingManager;
  String? _activeBranchId;
  String? _activeBranchName;

  @override
  void initState() {
    super.initState();

    // ── Tool state controller (replaces Riverpod) ──────────────────────────
    _toolController = UnifiedToolController();

    // ✨ PRO: Initialize GPU shader brushes
    _initProShaders();

    // 🎨 TEXTURE: Precarica texture pennello
    BrushTexture.preloadAll();

    // 🚀 PERFORMANCE: Pause app-level listeners via config
    _config.onPauseAppListeners?.call(true);

    // 🛡️ ANR FIX: Tell sync coordinator we're in canvas mode
    _config.onPauseSyncCoordinator?.call(true);

    // 🛑 LIFECYCLE: Registra observer per flush checkpoint
    WidgetsBinding.instance.addObserver(this);

    // 🆕 Genera o usa canvasId esistente
    _canvasId =
        widget.canvasId ?? 'canvas_${DateTime.now().microsecondsSinceEpoch}';

    // 🆕 Initialize titolo
    _noteTitle = widget.title;

    // Initialize layer controller
    _layerController = LayerController();
    _layerController.enableDeltaTracking = true;
    _layerController.addListener(_onLayerChanged);
    _refreshCachedLists();

    // Initialize eraser tool
    _eraserTool = EraserTool(
      layerController: _layerController,
      eraserRadius: 20.0,
      eraseWholeStroke: false,
    );
    _eraserTool.loadPersistedRadius();

    // 🎯 Eraser pulse animation
    _eraserPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );

    // Initialize lasso tool
    _lassoTool = LassoTool(layerController: _layerController);

    // 🏗️ UNIFIED TOOL SYSTEM
    _unifiedToolController = UnifiedToolController();
    _toolSystemBridge = ToolSystemBridge(
      layerController: _layerController,
      toolController: _unifiedToolController!,
      onOperationComplete: _autoSaveCanvas,
      onSaveUndo: null,
    );
    _toolSystemBridge!.registerDefaultTools();

    // Initialize digital text tool
    _digitalTextTool = DigitalTextTool();

    // Initialize image tool
    _imageTool = ImageTool();

    // ✒️ Initialize pen tool
    _penToolAdapter = InfiniteCanvasAdapter(
      canvasId: _canvasId,
      onOperationComplete: _autoSaveCanvas,
      onSaveUndo: null,
    );
    _penTool = PenTool(
      onPathNodeCreated: (pathNode) {
        debugPrint(
          '✒️ [PenTool] PathNode created: ${pathNode.id} '
          '(${pathNode.path.segments.length} segments)',
        );
        _autoSaveCanvas();
        if (mounted) setState(() {});
      },
    );

    // Initialize canvas controller
    _canvasController = InfiniteCanvasController();

    // 🖥️ DISPLAY DETECTION: Delay to avoid init contention
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        _detectDisplayCapabilitiesAndConfigure();
      }
    });

    // 🆕 Initialize drawing input handler
    _drawingHandler = DrawingInputHandler(
      enableOneEuroFilter: true,
      onPointsUpdated: (points) {
        _currentStrokeNotifier.setStroke(points);
        _currentStrokeNotifier.forceRepaint();
        AdaptiveDebouncerService.instance.notifyInput();
      },
    );
    _drawingHandler.stabilizerLevel = _brushSettings.stabilizerLevel;

    // Cenbetween the canvas at the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final size = MediaQuery.of(context).size;
        _canvasController.centerCanvas(size, canvasSize: _canvasSize);
      }
    });

    // 🎛️ Load brush settings persistenti
    _loadBrushSettings();

    // 💾 Initialize stroke persistence service
    StrokePersistenceService.instance.initialize(_canvasId);

    // 🚀 PERFORMANCE POOLS
    StrokePointPool.instance.initialize();
    PathPool.instance.initialize();

    // 🆕 Load canvas data (via config)
    _loadCanvasData();

    // 🚀 PERFORMANCE: Defer non-critical initialization
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;

      // Load saved recordings
      _loadSavedRecordings();

      // 🖼️ Load background image if specified
      if (widget.backgroundImageUrl != null) {
        _loadBackgroundImage();
      }

      // 🔄 REAL-TIME COLLABORATION: Initialize sync + presence
      _initRealtimeCollaboration();

      // ⏱️ TIME TRAVEL
      _initTimeTravelRecorder();
    });
  }

  /// 🖼️ Decode image bytes with max dimension cap
  static const int _maxImageDimension = 2048;

  // ============================================================================
  // BUILD (delegates to _build_ui.dart part file)
  // ============================================================================

  @override
  Widget build(BuildContext context) => _buildImpl(context);

  // ============================================================================
  // 🛑 LIFECYCLE MANAGEMENT
  // ============================================================================

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      BackgroundSaveService.instance.flush();

      if (_isSharedCanvas && _realtimeSyncManager != null) {
        _realtimeSyncManager!.pause();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_isSharedCanvas && _realtimeSyncManager != null) {
        _realtimeSyncManager!.resume();
      }
    }
  }

  // ============================================================================
  // DISPOSE
  // ============================================================================

  @override
  void dispose() {
    // 🖼️ MEMORY: Dispose all loaded ui.Image objects
    for (final image in _loadedImages.values) {
      image.dispose();
    }
    _loadedImages.clear();

    _loadingPulseTimer?.cancel();
    _recordingsListener?.cancel();

    // ⏱️ TIME TRAVEL
    unawaited(_flushTimeTravelOnClose());
    _timeTravelEngine?.dispose();
    _timeTravelEngine = null;
    _timeTravelRecorder = null;

    // 🔄 REAL-TIME COLLABORATION
    _realtimeSyncManager?.dispose();

    // 🚀 ADAPTIVE DEBOUNCER
    AdaptiveDebouncerService.instance.flush();

    // 🛑 LIFECYCLE
    unawaited(BackgroundSaveService.instance.flush());
    WidgetsBinding.instance.removeObserver(this);

    // Flush pending save via config
    _config.onFlushPendingSave?.call();

    // 🚀 DELTA TRACKER
    CanvasDeltaTracker.instance.reset();

    // 🗑️ Clear caches
    ProStrokePainter.clearCache();
    BackgroundPainter.clearCache();

    // 🚀 PERFORMANCE: Riattiva app listeners via config
    _config.onPauseAppListeners?.call(false);

    // 🛡️ ANR FIX: Allow sync to resume
    _config.onPauseSyncCoordinator?.call(false);

    _saveDebounceTimer?.cancel();
    _autoScrollTimer?.cancel();
    _layerController.removeListener(_onLayerChanged);

    _eraserPulseController.dispose();
    _isDrawingNotifier.dispose();
    _currentStrokeNotifier.dispose();
    _currentShapeNotifier.dispose();
    _currentEditingStrokeNotifier.dispose();
    _canvasController.dispose();
    _playbackController?.dispose();

    BrushSettingsService.instance.removeListener(
      _onBrushSettingsServiceUpdated,
    );

    DrawingPainter.clearTileCache();
    StrokeDataManager.clearCache();

    _toolSystemBridge?.dispose();
    _unifiedToolController?.dispose();
    _toolController.dispose();

    super.dispose();
  }
}

/// 🔵 Sync status dot with optional pulse animation
class _SyncDot extends StatefulWidget {
  final Color color;
  final bool pulsing;
  final Color surfaceColor;

  const _SyncDot({
    required this.color,
    required this.pulsing,
    required this.surfaceColor,
  });

  @override
  State<_SyncDot> createState() => _SyncDotState();
}

class _SyncDotState extends State<_SyncDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _opacity = Tween<double>(
      begin: 1.0,
      end: 0.3,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    if (widget.pulsing) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _SyncDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulsing != oldWidget.pulsing) {
      if (widget.pulsing) {
        _controller.repeat(reverse: true);
      } else {
        _controller.stop();
        _controller.reset();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color:
                widget.pulsing
                    ? widget.color.withValues(alpha: _opacity.value)
                    : widget.color,
            shape: BoxShape.circle,
            border: Border.all(color: widget.surfaceColor, width: 1.5),
          ),
        );
      },
    );
  }
}

/// 🎯 Trail point for eraser trail visualization
class _EraserTrailPoint {
  final Offset position;
  final int timestamp;

  const _EraserTrailPoint(this.position, this.timestamp);
}

/// 🎯 V3: Particle emitted at erase intersection points
class _EraserParticle {
  Offset position;
  final Offset velocity;
  double opacity;
  final int createdAt;
  final double size;

  _EraserParticle({
    required this.position,
    required this.velocity,
    this.opacity = 1.0,
    required this.createdAt,
    this.size = 3.0,
  });
}
