import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import '../drawing/brushes/brush_engine.dart';
import '../drawing/brushes/brush_texture.dart';

import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/uid.dart';
import '../drawing/models/pro_drawing_point.dart';
import '../drawing/models/pro_brush_settings.dart';
import '../drawing/models/pro_brush_settings_dialog.dart';
import '../drawing/services/brush_preset_manager.dart';
import '../drawing/models/brush_preset.dart';
import '../drawing/models/surface_material.dart';

import '../drawing/services/brush_settings_service.dart';
import '../core/models/shape_type.dart';
import '../core/models/digital_text_element.dart';
import '../core/models/image_element.dart';
import '../core/models/canvas_layer.dart';
import '../core/engine_scope.dart';
import '../core/engine_event_bus.dart';
import '../core/engine_event.dart';
import '../core/conscious_architecture.dart';
import '../core/adaptive_profile.dart';
import '../rendering/optimization/anticipatory_tile_prefetch.dart';
import '../core/engine_error.dart';
import '../export/export_preset.dart';
import '../export/saved_export_area.dart';
import '../config/multi_page_config.dart';
import '../drawing/input/drawing_input_handler.dart';
import '../rendering/canvas/background_painter.dart';
import '../rendering/shaders/shader_brush_service.dart';
import '../rendering/gpu/gpu_texture_service.dart';
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
import '../tools/shape/shape_recognizer.dart';
import '../platform/hme_latex_recognizer.dart';
import '../platform/ink_rasterizer.dart';
import '../platform/latex_recognition_bridge.dart';
import '../core/latex/ink_stroke_data.dart';
import '../canvas/widgets/latex_preview_card.dart';
import '../tools/base/tool_context.dart';
import '../layers/adapters/infinite_canvas_adapter.dart';

import '../tools/ruler/ruler_interactive_overlay.dart';
import './overlays/selection_transform_overlay.dart';
import '../dialogs/digital_text_input_dialog.dart';
import '../dialogs/image_editor_dialog.dart';
import '../services/image_service.dart';
import '../services/adaptive_debouncer_service.dart';
import '../drawing/input/raw_input_processor_120hz.dart';
import '../history/canvas_delta_tracker.dart';
import '../history/background_checkpoint_service.dart';
import '../storage/nebula_cloud_adapter.dart';
import '../drawing/input/stroke_point_pool.dart';
import '../drawing/input/path_pool.dart';
import '../time_travel/models/synchronized_recording.dart';
import '../time_travel/controllers/synchronized_playback_controller.dart';
import '../time_travel/widgets/synchronized_playback_overlay.dart';
import '../collaboration/widgets/canvas_presence_overlay.dart';
import '../collaboration/nebula_realtime_adapter.dart';
import '../collaboration/conflict_resolution.dart';
import '../collaboration/widgets/conflict_resolution_dialog.dart';
import './overlays/canvas_viewport_overlay.dart';
import '../time_travel/services/time_travel_recorder.dart';
import '../services/phase2_service_stubs.dart'; // Stub implementations for Phase 2 services
import '../services/canvas_performance_monitor.dart'; // 🏎️ Frame time overlay
import '../time_travel/services/time_travel_playback_engine.dart';
import '../history/branching_manager.dart';
import '../history/widgets/branch_explorer_sheet.dart';

import '../tools/base/tool_bridge.dart';
import '../tools/unified_tool_controller.dart';
import './toolbar/menus/selection_actions_menu.dart';
import './toolbar/menus/image_action_button.dart';
import '../rendering/canvas/canvas_painters.dart';
import '../dialogs/canvas_settings_dialog.dart';
import '../tools/pdf_page_drag_controller.dart';

// ── SDK Config (Dependency Inversion) ──────────────────────────────────────
import './nebula_canvas_config.dart';
import '../storage/sqlite_storage_adapter.dart';
import '../storage/save_isolate_service.dart';
import '../storage/recording_storage_service.dart';
import '../platform/display_capabilities_detector.dart';
import '../config/adaptive_rendering_config.dart';
import '../reflow/cluster_detector.dart';
import '../reflow/reflow_physics_engine.dart';
import '../reflow/content_cluster.dart';
import '../reflow/reflow_controller.dart';
import './smart_guides/smart_guide_engine.dart';
import './smart_guides/smart_guide_overlay.dart';
import '../audio/default_voice_recording_provider.dart';
import '../rendering/canvas/image_memory_manager.dart';
import '../rendering/optimization/spatial_index.dart';
import '../tools/pdf/pdf_import_controller.dart';
import '../platform/native_pdf_provider.dart';
import '../core/nodes/pdf_document_node.dart';
import '../core/models/pdf_annotation_model.dart';
import '../core/models/pdf_page_model.dart';
import '../core/models/pdf_document_model.dart';
import '../canvas/toolbar/pdf_presentation_overlay.dart';
// TODO(future): pdf_signature_pad.dart — re-import when digital signing is implemented.
import '../core/nodes/pdf_page_node.dart';
import '../rendering/canvas/pdf_page_painter.dart';
import '../rendering/canvas/pdf_memory_budget.dart';
import './toolbar/pdf_contextual_toolbar.dart';
import '../tools/pdf/pdf_annotation_controller.dart';
import '../tools/pdf/pdf_search_controller.dart';
import '../export/pdf_annotation_exporter.dart';
import '../export/pdf_export_writer.dart';
import '../canvas/overlays/pdf_export_settings_panel.dart';
import 'package:file_picker/file_picker.dart';
import './overlays/variable_manager_panel.dart';
import './overlays/variable_property_sheet.dart';
import './toolbar/toolbar_variable_button.dart';
import '../systems/design_variables.dart';
import '../systems/variable_binding.dart';
import '../systems/variable_resolver.dart';
import '../systems/design_token_exporter.dart';
import '../history/command_history.dart';
import '../systems/variable_commands.dart';
import '../core/nodes/latex_node.dart';
import '../core/scene_graph/canvas_node_factory.dart';
import '../core/scene_graph/node_id.dart';
import './widgets/latex_editor_sheet.dart';
import '../history/latex_commands.dart';
import '../core/nodes/tabular_node.dart';
import '../history/tabular_commands.dart';
import '../tools/tabular_interaction_tool.dart';
import '../core/tabular/cell_address.dart';
import '../core/tabular/cell_node.dart';
import '../core/tabular/cell_value.dart';
import '../core/tabular/tabular_clipboard.dart';
import '../core/tabular/tabular_csv.dart';
import '../core/tabular/latex_report_template.dart';
import '../core/tabular/tikz_chart_generator.dart';
import '../core/tabular/latex_table_parser.dart';
import '../export/latex_file_exporter.dart';
import '../rendering/canvas/latex_provenance_overlay_painter.dart';

// ─── Navigation & Orientation ──────────────────────────────────────────────
import './navigation/content_bounds_tracker.dart';
import './navigation/camera_actions.dart';
import './navigation/canvas_minimap.dart';
import './navigation/content_radar_overlay.dart';
import './navigation/zoom_level_indicator.dart';
import './navigation/return_to_content_fab.dart';
import './navigation/origin_crosshair.dart';
import './navigation/canvas_dot_grid.dart';

// ─── Design SDK modules ────────────────────────────────────────────────────
import '../systems/prototype_flow.dart';
import '../systems/animation_timeline.dart';
import '../systems/animation_player.dart';
import '../systems/spring_simulation.dart';
import '../systems/stagger_animation.dart';
import '../systems/path_motion.dart';
import '../systems/smart_animate_engine.dart';
import '../systems/smart_animate_snapshot.dart';
import '../systems/smart_snap_engine.dart';
import '../systems/design_linter.dart';
import '../systems/style_system.dart';
import '../systems/accessibility_bridge.dart';
import '../systems/intelligence_adapters.dart';
import '../systems/accessibility_tree.dart';
import '../systems/nested_instance_resolver.dart';
import '../systems/image_adjustment.dart';
import '../systems/image_fill_mode.dart';
import '../systems/text_auto_resize.dart';
import '../systems/plugin_api.dart';
import '../systems/plugin_budget.dart';
import '../systems/sandboxed_event_stream.dart';
import '../systems/responsive_breakpoint.dart';
import '../systems/responsive_variant.dart';
import '../systems/animation_commands.dart';
import '../systems/component_state_machine.dart';
import '../systems/component_state_resolver.dart';
import '../systems/dirty_tracker.dart';
import '../systems/engine_theme.dart';
import '../systems/opentype_features.dart';
import '../systems/selection_manager.dart';
import '../systems/selection_query.dart';
import '../systems/semantic_token.dart';
import '../systems/theme_manager.dart';
import '../systems/variable_font.dart';
import '../systems/variable_scope.dart';
import '../systems/dev_handoff/inspect_engine.dart';
import '../systems/dev_handoff/redline_overlay.dart';
import '../systems/dev_handoff/code_generator.dart';
import '../systems/dev_handoff/asset_manifest.dart';
import '../systems/dev_handoff/token_resolver.dart';
import '../systems/component_set.dart';
import '../systems/layout_engine.dart';
import '../systems/preferred_values.dart';
import '../collaboration/scene_graph_crdt.dart';
import '../export/nebula_file_format.dart';

// ─── Design overlay panels ─────────────────────────────────────────────────
import './overlays/animation_timeline_panel.dart';
import './overlays/dev_handoff_panel.dart';
import './overlays/design_quality_panel.dart';
import './overlays/responsive_preview_panel.dart';
import './overlays/image_adjustment_panel.dart';
import './overlays/token_export_dialog.dart';
import './overlays/conscious_debug_overlay.dart';

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
part './parts/_pdf_features.dart';
part './parts/_voice_recording.dart';
part './parts/_cloud_sync.dart';
part './parts/_phase2_stubs.dart';
part './parts/_design_variables.dart';
part './parts/_latex_handler.dart';
part './parts/_latex_recognition_handler.dart';
part './parts/_tabular_handler.dart';
part './parts/_tabular_fill_handle.dart';
part './parts/_tabular_clipboard.dart';
part './parts/_tabular_formatting.dart';
part './parts/_tabular_csv_import.dart';
part './parts/_tabular_latex_export.dart';

// 🎨 Design Features
part './parts/_prototype_animation.dart';
part './parts/_dev_handoff.dart';
part './parts/_component_system.dart';
part './parts/_responsive_design.dart';
part './parts/_design_quality.dart';
part './parts/_conscious_architecture.dart';
part './parts/_advanced_export.dart';

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
part './parts/ui/_loading_overlay.dart';
part './parts/ui/_shape_recognition_toast.dart';

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

  /// Force repaint after in-place mutation of the list.
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
/// - Infinite canvas with zoom and pan
/// - Zero latency with ValueNotifier
/// - Smoothing adattivo OneEuroFilter
/// - Post-stroke optimization with Douglas-Peucker
/// - Rendering vettoriale puro (no GPU cache)
/// - Triple smoothing for fountain pen
/// - Physics-based ink simulation
/// - 💾 AUTO-SAVE at each stroke/edit (via NebulaCanvasConfig)
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

  /// 🆕 Note name/title (loaded or received)
  String? _noteTitle;

  // ============================================================================
  // 🔄 COLLABORATION & SYNC STATE
  // ============================================================================

  /// ☁️ Cloud sync engine (initialized from config.cloudAdapter)
  NebulaSyncEngine? _syncEngine;

  /// 🔴 Real-time collaboration engine (manages subscriptions, cursors, locks)
  NebulaRealtimeEngine? _realtimeEngine;
  StreamSubscription<CanvasRealtimeEvent>? _realtimeEventSub;

  /// 🤝 Is this canvas shared with other users?
  bool _isSharedCanvas = false;

  /// 🔒 Is the current user in view-only mode?
  bool _isViewerMode = false;

  /// 💎 Cached subscription tier
  NebulaSubscriptionTier get _subscriptionTier => _config.subscriptionTier;

  /// 💎 Convenience: has cloud sync
  bool get _hasCloudSync => _config.cloudAdapter != null;

  /// 💎 Convenience: has real-time collaboration
  bool get _hasRealtimeCollab =>
      _subscriptionTier.canCollaborate && _config.realtimeAdapter != null;

  // ============================================================================
  // 🖥️ DISPLAY CAPABILITIES & ADAPTIVE RENDERING (120Hz Support)
  // ============================================================================

  /// Detected display capabilities (refresh rate, frame budget)
  DisplayCapabilities? _displayCapabilities;

  /// Configuretion rendering adattiva basata su display
  AdaptiveRenderingConfig? _renderingConfig;

  /// Raw input processor for 120Hz mode (when applicable)
  RawInputProcessor120Hz? _rawInputProcessor120Hz;

  /// ⏱️ Timer per debouncing save
  Timer? _saveDebounceTimer;

  /// 🔄 Flag to disable auto-save during loading + show splash screen
  bool _isLoading = true;

  /// Whether the loading overlay has fully faded out and can be removed from tree
  bool _loadingOverlayDismissed = false;

  /// ☁️ Timestamp of last successful local save (millis since epoch).
  /// Used for conflict detection with cloud data.
  int? _lastLocalSaveTimestamp;

  /// Layer controller per gestire i layer
  late final LayerController _layerController;

  /// 🔧 FIX ZOOM LAG: Cache of shape lists
  List<GeometricShape> _cachedAllShapes = const [];

  /// ⏱️ Snapshot of live layers before entering Time Travel
  /// Restored on exit to bring the canvas back to the live state.
  List<CanvasLayer> _savedLiveLayersBeforeTimeTravel = const [];

  /// Layer panel key per controllare apertura/chiusura
  final GlobalKey<LayerPanelState> _layerPanelKey = GlobalKey();

  /// Notifier to indicate when the user is drawing
  final ValueNotifier<bool> _isDrawingNotifier = ValueNotifier(false);

  /// 🚀 PERFORMANCE: Tratto corrente con notifier ottimizzato
  final _StrokeNotifier _currentStrokeNotifier = _StrokeNotifier();

  /// Shape corrente in disegno
  final ValueNotifier<GeometricShape?> _currentShapeNotifier = ValueNotifier(
    null,
  );

  /// 🔷 Shape recognition toast data (null = hidden)
  final ValueNotifier<_ShapeRecognitionToastData?> _shapeRecognitionToast =
      ValueNotifier(null);

  /// 👻 Ghost suggestion data (null = hidden)
  final ValueNotifier<_GhostSuggestionData?> _ghostSuggestion = ValueNotifier(
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

  /// 🧬 Active surface material for programmable materiality.
  /// When set, strokes inherit physical surface properties (roughness,
  /// absorption, grain texture). null = default (no surface effect).
  SurfaceMaterial? _activeSurface;

  /// Undo/Redo
  final List<ProStroke> _undoStack = [];

  /// Effective color with applied opacity
  Color get _effectiveColor =>
      _effectiveSelectedColor.withValues(alpha: _effectiveOpacity);

  /// Auto-scroll during drag
  Timer? _autoScrollTimer;
  final GlobalKey _canvasAreaKey = GlobalKey();
  static const double _edgeScrollThreshold = 60.0; // 🏎️ Edge zone width
  static const double _scrollSpeed = 8.0; // 🏎️ Max scroll speed (px/frame)
  // 🏎️ Active edge scroll state for visual glow indicator
  // Bits: 1=left, 2=right, 4=top, 8=bottom
  int _activeEdgeScroll = 0;
  // 📌 Last screen position of finger during auto-scroll (for re-deriving canvas pos)
  Offset _autoScrollFingerScreenPos = Offset.zero;

  // 📐 Smart Guides: active guide lines during drag
  List<SmartGuideLine> _activeSmartGuides = const [];

  // ============================================================================
  // LIFECYCLE
  // ============================================================================

  /// Eraser tool
  late final EraserTool _eraserTool;

  /// Lasso tool
  late final LassoTool _lassoTool;

  /// 🔒 Backup of lasso selection IDs before starting a new lasso.
  /// Restored in _onDrawCancel if a zoom gesture interrupts the new lasso.
  Set<String>? _lassoSelectionBackup;

  // 🌊 REFLOW: Cluster detector and cache
  ClusterDetector? _clusterDetector;
  List<ContentCluster> _clusterCache = [];

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

  /// 📊 Tabular interaction tool
  late final TabularInteractionTool _tabularTool;
  bool _editingInCell = false;

  /// 🧮 LatexNode interaction state
  LatexNode? _selectedLatexNode;
  bool _isDraggingLatex = false;
  Offset? _latexDragStart;

  /// 🧠 Version counter: incremented on every image content mutation
  /// Used by ImagePainter for fast shouldRepaint + Picture cache invalidation
  int _imageVersion = 0;

  /// 🚀 PERF: Dedicated repaint notifier for the image layer ONLY.
  /// During drag/resize, incrementing this triggers ONLY the ImagePainter
  /// repaint — NOT DrawingPainter or BackgroundPainter. This is the key
  /// optimization that prevents re-rendering all strokes every frame.
  final ValueNotifier<int> _imageRepaintNotifier = ValueNotifier<int>(0);

  /// 🌐 R-tree spatial index for O(log n) image viewport culling
  RTree<ImageElement>? _imageSpatialIndex;

  /// 🧠 LRU memory manager for loaded images
  final ImageMemoryManager _imageMemoryManager = ImageMemoryManager(
    maxImages: 20,
  );

  /// 📄 PDF providers: one per imported document (keyed by document ID)
  final Map<String, NativeNebulaPdfProvider> _pdfProviders = {};

  /// 📄 PDF page painters: one per document for LOD-aware rendering
  final Map<String, PdfPagePainter> _pdfPainters = {};

  /// 📄 PDF annotation controller (shared, attached to active document)
  PdfAnnotationController? _pdfAnnotationController;

  /// 📄 PDF search controller (shared, uses active document's provider)
  PdfSearchController? _pdfSearchController;

  /// 📄 Currently selected PDF document ID for toolbar interaction.
  /// When null, the first PDF found in the layer tree is used as fallback.
  String? _activePdfDocumentId;

  /// 📄 PDF layout mutation counter. Incremented on in-place mutations
  /// (lock toggle, rotate, grid change) so DrawingPainter.shouldRepaint
  /// detects the change (sceneGraph is a shared ref so version comparison
  /// alone doesn’t work).
  int _pdfLayoutVersion = 0;

  /// Currently selected PDF page index (for insert-at-position).
  int _pdfSelectedPageIndex = 0;

  /// Whether to show page number badges on PDF pages.
  bool _showPdfPageNumbers = true;

  // ============================================================================
  // 🧠 CONSCIOUS ARCHITECTURE STATE
  // ============================================================================

  /// Idle detection timer for intelligence subsystems.
  Timer? _consciousIdleTimer;

  /// Timestamp of last user interaction (for idle detection).
  DateTime? _consciousIdleStart;

  /// Throttle timestamp for canvas transform → context push (ms since epoch).
  int _consciousLastTransformPushMs = 0;

  /// Last pushed transform values for the rotation-only filter (Fix 2).
  double _consciousLastScale = 1.0;
  double _consciousLastOffsetX = 0.0;
  double _consciousLastOffsetY = 0.0;

  /// ✂️ Canvas-space clip rect for the PDF page the user is currently
  /// drawing on. When non-null, [CurrentStrokePainter] clips the live
  /// stroke to this rect so ink doesn't overflow outside the page.
  Rect? _activePdfClipRect;

  /// 🎬 Presentation mode — zoom-to-page fullscreen slideshow.
  bool _isPresentationMode = false;
  int _presentationPageIndex = 0;

  /// 📄 Drag controller for unlocked PDF pages.
  final PdfPageDragController _pdfPageDragController = PdfPageDragController();

  /// 📄 Export progress callback — used by StatefulBuilder in SnackBar.
  void Function(int current, int total)? _exportProgressSetter;

  /// 🌐 Rebuild the R-tree spatial index from current image elements.
  void _rebuildImageSpatialIndex() {
    _imageSpatialIndex = RTree<ImageElement>.fromItems(_imageElements, (img) {
      final w = _loadedImages[img.imagePath]?.width.toDouble() ?? 200.0;
      final h = _loadedImages[img.imagePath]?.height.toDouble() ?? 150.0;
      final halfW = w * img.scale * 0.5;
      final halfH = h * img.scale * 0.5;

      // 🔄 Improvement 4: expand bounds to AABB of rotated rect
      if (img.rotation != 0.0) {
        final cosR = math.cos(img.rotation).abs();
        final sinR = math.sin(img.rotation).abs();
        final rotHalfW = halfW * cosR + halfH * sinR;
        final rotHalfH = halfW * sinR + halfH * cosR;
        return Rect.fromCenter(
          center: img.position,
          width: rotHalfW * 2,
          height: rotHalfH * 2,
        );
      }

      return Rect.fromCenter(
        center: img.position,
        width: halfW * 2,
        height: halfH * 2,
      );
    });
  }

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
  int _lastImageTapTime = 0; // 🌀 Double-tap tracking for rotation reset
  static const double _dragThreshold = 8.0;

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
  // 🚀 Fix 1: incremental conversion — avoids O(n) per frame
  final List<ProDrawingPoint> _editingConvertedPoints = [];
  DateTime _editingStrokeCreatedAt = DateTime.now();

  // 🎤 State per tracking temporale strokes
  DateTime? _lastStrokeStartTime;

  /// 🎤 Audio recording state
  bool _isRecordingAudio = false;
  Duration _recordingDuration = Duration.zero;

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

  // ============================================================================
  // 📤 EXPORT MODE STATE
  // ============================================================================

  bool _isExportMode = false;
  Rect _exportArea = Rect.zero;
  ExportConfig _exportConfig = const ExportConfig();
  ExportProgressController? _exportProgressController;

  /// 🎛️ Whether the design variables panel is open.
  bool _showVariablePanel = false;

  /// 🎛️ Design variable collections (themes, tokens, etc.).
  final List<VariableCollection> _variableCollections = [];

  /// 🎛️ Variable-to-node property bindings.
  final VariableBindingRegistry _variableBindings = VariableBindingRegistry();

  /// 🎛️ Runtime variable resolver.
  late final VariableResolver _variableResolver = VariableResolver(
    collections: _variableCollections,
    bindings: _variableBindings,
  );

  /// ⏪ Command history for undoable variable (and future node) operations.
  final CommandHistory _commandHistory = CommandHistory();

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

  // ============================================================================
  // 🎨 DESIGN FEATURES STATE
  // ============================================================================

  /// 🛠️ Inspect mode (dev handoff measurements)
  bool _isInspectModeActive = false;
  InspectEngine? _activeInspectEngine;

  /// 📏 Redline overlay (spec annotations)
  bool _isRedlineActive = false;

  /// 🔲 Smart snap engine
  bool _isSmartSnapEnabled = false;
  SmartSnapEngine? _smartSnapEngine;

  // ============================================================================
  // 🧭 NAVIGATION & ORIENTATION STATE
  // ============================================================================

  /// 🗺️ Content bounds tracker (shared by minimap, radar, camera actions)
  late final ContentBoundsTracker _contentBoundsTracker;

  /// 🗺️ Whether the minimap overlay is visible
  bool _showMinimap = true;
  bool _showDotGrid = true;

  @override
  void initState() {
    super.initState();

    // ── Tool state controller (replaces Riverpod) ──────────────────────────
    _toolController = UnifiedToolController();

    // ✨ Shader init, isolate spawn, texture preload — all moved to
    // _initializeCanvas() pipeline (runs during splash screen).

    // 🚀 PERFORMANCE: Pause app-level listeners via config
    _config.onPauseAppListeners?.call(true);

    // 🛡️ ANR FIX: Tell sync coordinator we're in canvas mode
    _config.onPauseSyncCoordinator?.call(true);

    // 🛑 LIFECYCLE: Register observer for flush checkpoint
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

    // 🧭 Initialize navigation bounds tracker
    _contentBoundsTracker = ContentBoundsTracker(
      layerController: _layerController,
    );

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
      onGetTextElements: () => _digitalTextElements,
      onUpdateTextElement: (updated) {
        final idx = _digitalTextElements.indexWhere((e) => e.id == updated.id);
        if (idx != -1) {
          setState(() => _digitalTextElements[idx] = updated);
          _layerController.updateText(updated);
        }
      },
      onRemoveTextElement: (id) {
        setState(() => _digitalTextElements.removeWhere((e) => e.id == id));
      },
      onGetImageElements: () => _imageElements,
      onUpdateImageElement: (updated) {
        final idx = _imageElements.indexWhere((e) => e.id == updated.id);
        if (idx != -1) {
          setState(() => _imageElements[idx] = updated);
          _layerController.updateImage(updated);
        }
      },
      onRemoveImageElement: (id) {
        setState(() => _imageElements.removeWhere((e) => e.id == id));
      },
    );
    _toolSystemBridge!.registerDefaultTools();

    // Initialize digital text tool
    _digitalTextTool = DigitalTextTool();

    // Initialize image tool
    _imageTool = ImageTool();
    _tabularTool = TabularInteractionTool();

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

    // 🌊 LIQUID: Attach physics ticker from this TickerProviderStateMixin
    _canvasController.attachTicker(this);

    // 🔒 Haptic feedback at zoom limits (one-shot per crossing)
    _canvasController.onZoomLimitReached = () {
      HapticFeedback.heavyImpact();
    };

    // 🌀 Load persisted rotation lock preference
    _canvasController.loadPersistedState();

    // 🌊 REFLOW: Initialize cluster detector and physics engine
    final reflowConfig = _canvasController.liquidConfig.reflow;
    if (reflowConfig.enabled) {
      _clusterDetector = ClusterDetector(
        temporalThresholdMs: reflowConfig.clusterTemporalThresholdMs,
        spatialThreshold: reflowConfig.clusterSpatialThreshold,
      );
      final reflowEngine = ReflowPhysicsEngine(config: reflowConfig);
      _lassoTool.reflowController = ReflowController(
        engine: reflowEngine,
        clusters: _clusterCache,
      );
      // 🌊 Share reflow controller with PDF document drag
      _pdfPageDragController.reflowController = _lassoTool.reflowController;
    }

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

    // 🧠 CONSCIOUS ARCHITECTURE: Register subsystems + start idle timer.
    _initConsciousArchitecture();

    // 🚀 SPLASH SCREEN: Run ALL heavy init in parallel (shader, isolate,
    // textures, data load). The loading overlay is shown until complete.
    _initializeCanvas();

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

      // ☁️ Flush pending cloud save on app background
      if (_syncEngine != null) {
        final saveData = _buildSaveData();
        final cloudData = saveData.toJson();
        cloudData['layers'] = saveData.layers.map((l) => l.toJson()).toList();
        _syncEngine!.flush(_canvasId, cloudData);
      }
    }
  }

  // ============================================================================
  // DISPOSE
  // ============================================================================

  @override
  void dispose() {
    // 🧠 CONSCIOUS ARCHITECTURE: Stop idle timer.
    _disposeConsciousArchitecture();

    // 🧭 Navigation
    _contentBoundsTracker.dispose();

    // 🖼️ MEMORY: Dispose all loaded ui.Image objects
    for (final image in _loadedImages.values) {
      image.dispose();
    }
    _loadedImages.clear();
    ImagePainter.invalidateCache();
    _imageMemoryManager.clear();

    _loadingPulseTimer?.cancel();
    _recordingsListener?.cancel();

    // ⏱️ TIME TRAVEL
    unawaited(_flushTimeTravelOnClose());
    _timeTravelEngine?.dispose();
    _timeTravelEngine = null;
    _timeTravelRecorder = null;

    // ☁️ CLOUD SYNC
    _disposeRealtimeCollaboration();
    _syncEngine?.dispose();

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
    // 🌊 LIQUID: Detach physics ticker before disposal
    _canvasController.detachTicker();
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

    // 🚀 PERSISTENT ISOLATE: Shut down the background encoding isolate
    SaveIsolateService.instance.dispose();

    // 🎤 VOICE RECORDING: Stop active recording and clean up provider
    if (_isRecordingAudio) {
      _recordingDurationSubscription?.cancel();
      _recordingDurationSubscription = null;
      _syncRecordingBuilder = null;
      _isRecordingAudio = false;
      // Fire-and-forget — provider.stopRecording() will stop the native recorder
      _voiceRecordingProvider.stopRecording().catchError((e) {
        EngineScope.current.errorRecovery.reportError(
          EngineError(
            severity: ErrorSeverity.transient,
            domain: ErrorDomain.platform,
            source: 'NebulaCanvasScreen.dispose.stopRecording',
            original: e,
          ),
        );
        return null;
      });
    }

    // 🔧 FIX #1: Stop any active synced playback to prevent setState on disposed state
    if (_isPlayingSyncedRecording) {
      _playbackController?.stop();
      _playbackController = null;
      _isPlayingSyncedRecording = false;
      _voiceRecordingProvider.stopPlayback();
    }
    // 🔧 FIX #7: Clean up playback completion listener
    VoiceRecordingExtension._playbackCompletedSubs[hashCode]?.cancel();
    VoiceRecordingExtension._playbackCompletedSubs.remove(hashCode);
    _disposeDefaultVoiceRecordingProvider();

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
