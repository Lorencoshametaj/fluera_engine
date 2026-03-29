import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart' show compute, kIsWeb, kReleaseMode;
import 'package:flutter/scheduler.dart' show Ticker;
import '../drawing/brushes/brush_engine.dart';
import '../drawing/brushes/brush_texture.dart';
import './ai/proactive_analysis_model.dart'; // 💡 Proactive knowledge gap data models
import './ai/exam_session_controller.dart';   // 🎓 Exam Mode session controller
import './ai/chat_session_controller.dart';   // 💬 Chat with Notes controller
import './ai/chat_session_model.dart';        // 💬 Chat data models
import './ai/fsrs_scheduler.dart';             // 🧠 FSRS adaptive spaced repetition
import './overlays/exam_overlay.dart';         // 🎓 Exam Mode fullscreen overlay
import './overlays/chat_overlay.dart';         // 💬 Chat with Notes overlay
import '../ai/chat_context_builder.dart';      // 💬 Chat context builder
import './widgets/proactive_cluster_dot.dart'; // 💡 Animated gap indicator dot
import '../platform/native_notifications.dart'; // 🔔 Native notifications for SR reminders

import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import '../utils/safe_path_provider.dart';
import '../utils/platform_guard.dart';
import '../utils/key_value_store.dart';
import '../audio/native_audio_models.dart';
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
import '../core/models/recording_pin.dart';
import '../core/models/canvas_layer.dart';
import '../core/engine_scope.dart';
import '../core/engine_event_bus.dart';
import '../core/engine_event.dart';
import '../core/conscious_architecture.dart';
import '../core/adaptive_profile.dart';
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
import '../rendering/canvas/implicit_section_painter.dart';
import '../rendering/canvas/knowledge_flow_painter.dart';
import '../rendering/canvas/cluster_thumbnail_cache.dart';
import '../reflow/knowledge_connection.dart';
import '../reflow/knowledge_flow_controller.dart';
import '../reflow/connection_suggestion_engine.dart';
import '../rendering/canvas/current_stroke_painter.dart';
import '../rendering/canvas/pro_stroke_painter.dart';

import '../rendering/optimization/stroke_data_manager.dart';
import '../drawing/services/stroke_persistence_service.dart';
import '../rendering/canvas/image_painter.dart';
import './toolbar/professional_canvas_toolbar.dart';
import './overlays/eyedropper_overlay.dart';
import './overlays/floating_color_disc.dart';
import './overlays/action_flash_overlay.dart';
import './overlays/connection_label_overlay.dart';
import './overlays/cluster_preview_overlay.dart';
import './overlays/knowledge_map_overlay.dart';
import './overlays/canvas_radial_menu.dart';
import './overlays/interactive_page_grid_overlay.dart';
import './overlays/atlas_prompt_overlay.dart';
import './overlays/atlas_visual_effects.dart';
import './overlays/atlas_response_card.dart';
import '../ai/canvas_state_extractor.dart';
import '../ai/atlas_action_executor.dart';
import '../ai/atlas_action.dart';
import '../ai/radial_expansion_controller.dart';
import '../rendering/canvas/radial_expansion_painter.dart';
import '../ai/ai_provider.dart';
import '../core/nodes/text_node.dart';
import '../core/nodes/stroke_node.dart';
import '../core/nodes/image_node.dart';
import '../core/scene_graph/canvas_node.dart';
import '../services/handwriting_index_service.dart';
import './toolbar/pro_color_picker.dart';
import './infinite_canvas_controller.dart';
import './infinite_canvas_gesture_detector.dart';
import '../layers/layer_controller.dart';
import '../layers/widgets/layer_panel.dart';
import '../tools/eraser/eraser_tool.dart';
import '../tools/scratch_out/scratch_out_detector.dart';
import '../tools/eraser/eraser_hit_tester.dart';
import '../tools/lasso/lasso_tool.dart';
import '../tools/lasso/lasso_path_painter.dart';
import '../tools/lasso/lasso_selection_overlay.dart';
import '../tools/text/digital_text_tool.dart';
import '../tools/image/image_tool.dart';
import '../tools/ruler/ruler_guide_system.dart';
import '../tools/flood_fill/flood_fill_tool.dart';
import '../tools/pen/pen_tool.dart';
import '../tools/echo_search_controller.dart';
import '../tools/shape/shape_recognizer.dart';
import '../platform/hme_latex_recognizer.dart';
import '../platform/ink_rasterizer.dart';
import '../platform/latex_recognition_bridge.dart';
import '../core/latex/ink_stroke_data.dart';
import '../core/latex/latex_parser.dart';
import '../core/latex/latex_layout_engine.dart';
import '../canvas/widgets/latex_preview_card.dart';
import '../tools/base/tool_context.dart';
import '../layers/adapters/infinite_canvas_adapter.dart';

import '../tools/ruler/ruler_interactive_overlay.dart';
import './overlays/selection_transform_overlay.dart';
import './overlays/smart_ink_overlay.dart';
import './overlays/inline_text_overlay.dart';
import './overlays/inline_text_toolbar.dart';
import '../dialogs/digital_text_input_dialog.dart';
import '../dialogs/image_editor_dialog.dart';
import '../dialogs/image_editor_crop.dart';
import '../services/image_service.dart';
import '../services/adaptive_debouncer_service.dart';
import '../services/digital_ink_service.dart';
import '../services/ink_prediction_service.dart';
import '../services/word_completion_dictionary.dart';
import '../canvas/overlays/ink_prediction_bubble.dart';
import '../canvas/overlays/ghost_ink_painter.dart';
import '../services/text_recognition_service.dart';
import '../dialogs/handwriting_confirmation_dialog.dart';
import '../dialogs/ocr_scan_dialog.dart';
import '../canvas/widgets/handwriting_search_overlay.dart';
import '../rendering/canvas/handwriting_search_painter.dart';
import '../rendering/canvas/echo_search_pen_painter.dart';
import '../drawing/input/raw_input_processor_120hz.dart';
import '../history/canvas_delta_tracker.dart';
import '../history/background_checkpoint_service.dart';
import '../storage/fluera_cloud_adapter.dart';
import '../drawing/input/stroke_point_pool.dart';
import '../drawing/input/path_pool.dart';
import '../time_travel/models/synchronized_recording.dart';
import '../time_travel/controllers/synchronized_playback_controller.dart';
import '../time_travel/widgets/synchronized_playback_overlay.dart';
import '../collaboration/widgets/canvas_presence_overlay.dart';
import '../collaboration/fluera_realtime_adapter.dart';
import '../collaboration/conflict_resolution.dart';
import '../collaboration/widgets/conflict_resolution_dialog.dart';
import '../multiview/multiview_orchestrator.dart';
import '../config/advanced_split_layout.dart';
import '../config/split_panel_content.dart';
import './overlays/canvas_viewport_overlay.dart';
import '../time_travel/services/time_travel_recorder.dart';
import '../services/phase2_service_stubs.dart'; // Stub implementations for Phase 2 services
import '../services/canvas_performance_monitor.dart'; // 🏎️ Frame time overlay
import '../services/handedness_settings.dart'; // 🖐️ Handedness & palm rejection
import './toolbar/handedness_settings_sheet.dart'; // 🖐️ Handedness onboarding
import './overlays/stylus_hover_overlay.dart'; // 🖊️ Stylus hover cursor
import '../time_travel/services/time_travel_playback_engine.dart';
import '../time_travel/widgets/time_travel_timeline_widget.dart';
import '../history/branching_manager.dart';
import '../history/widgets/branch_explorer_sheet.dart';

import '../tools/base/tool_bridge.dart';
import '../tools/unified_tool_controller.dart';
import './toolbar/menus/selection_actions_menu.dart';
import './overlays/selection_context_halo.dart';
import './toolbar/menus/image_action_button.dart';
import './toolbar/image_contextual_toolbar.dart';
import '../rendering/canvas/canvas_painters.dart';
import '../dialogs/canvas_settings_dialog.dart';
import '../tools/pdf_page_drag_controller.dart';

// ── SDK Config (Dependency Inversion) ──────────────────────────────────────
import './fluera_canvas_config.dart';
import '../storage/sqlite_storage_adapter.dart';
import '../storage/save_isolate_service.dart';
import '../rendering/gpu/vulkan_stroke_overlay_service.dart';
import '../rendering/gpu/webgpu_overlay_view.dart';
import '../rendering/gpu/webgpu_stroke_overlay_service_stub.dart'
    if (dart.library.js_interop) '../rendering/gpu/webgpu_stroke_overlay_service.dart';
import '../storage/recording_storage_service.dart';
import '../platform/display_capabilities_detector.dart';
import '../config/adaptive_rendering_config.dart';
import '../reflow/cluster_detector.dart';
import '../reflow/reflow_physics_engine.dart';
import '../reflow/content_cluster.dart';
import '../reflow/reflow_controller.dart';
import '../reflow/animated_reflow_controller.dart';
import '../reflow/semantic_morph_controller.dart';
import './smart_guides/smart_guide_engine.dart';
import './smart_guides/smart_guide_overlay.dart';
import '../audio/default_voice_recording_provider.dart';
import '../audio/sherpa_transcription_service.dart';
import '../audio/sherpa_model_manager.dart';
import '../audio/transcription_result.dart';
import '../audio/streaming_transcription_service.dart';
import '../audio/audio_keyword_extractor.dart';
import '../reflow/space_split_controller.dart';
import '../audio/platform_channels/audio_recorder_channel.dart';
import '../rendering/canvas/image_memory_manager.dart';
import '../rendering/canvas/image_memory_budget.dart';
import '../rendering/optimization/image_stub_manager.dart';
import '../rendering/optimization/frame_budget_manager.dart';
import '../platform/native_performance_monitor.dart';
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
import '../core/nodes/pdf_preview_card_node.dart';
import '../rendering/canvas/pdf_page_painter.dart';
import '../rendering/canvas/pdf_memory_budget.dart';
import './toolbar/pdf_contextual_toolbar.dart';
import '../tools/pdf/pdf_annotation_controller.dart';
import '../tools/pdf/pdf_search_controller.dart';
import '../export/pdf_annotation_exporter.dart';
import '../export/pdf_export_writer.dart';
import '../canvas/overlays/pdf_export_settings_panel.dart';
import '../canvas/pdf_reader_screen.dart';
import '../canvas/image_viewer_screen.dart';
import '../canvas/transitions/wormhole_dive_painter.dart';
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
import '../core/nodes/function_graph_node.dart';
import '../core/scene_graph/canvas_node_factory.dart';
import '../core/scene_graph/node_id.dart';
import './widgets/latex_editor_sheet.dart';
import './widgets/latex_function_graph.dart';
import '../history/latex_commands.dart';
import '../core/nodes/tabular_node.dart';
import '../core/nodes/section_node.dart';
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
import '../export/fluera_file_format.dart';
import '../export/fluera_file_export_service.dart';

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
part './parts/lifecycle/_lifecycle_helpers.dart';
part './parts/lifecycle/_lifecycle_time_travel.dart';
part './parts/lifecycle/_lifecycle_branching.dart';

// 🤝 Features
part './parts/_collaboration.dart';
part './parts/_collaboration_pdf_sync.dart';
part './parts/_canvas_operations.dart';
part './parts/_export.dart';
part './parts/_text_tools.dart';
part './parts/_image_features.dart';
part './parts/_pdf_features.dart';
part './parts/_pdf_features_widgets.dart';
part './parts/_voice_recording.dart';
part './parts/_voice_recording_utils.dart';
part './parts/_cloud_sync.dart';
part './parts/_pending_features.dart';
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
part './parts/_atlas_ai.dart';
part './parts/_echo_search.dart';
part './parts/_semantic_titles.dart';
part './parts/_radial_expansion.dart';
part './parts/_proactive_analysis.dart'; // 💡 Proactive knowledge gap analysis
part './parts/_smart_ink.dart'; // ✍️ Smart Ink — tap-to-reveal handwriting
part './parts/_chat_with_notes.dart'; // 💬 Chat with Notes — conversational AI

// ✏️ Drawing
part './parts/drawing/_drawing_handlers.dart';
part './parts/drawing/_drawing_update.dart';
part './parts/drawing/_drawing_end.dart';
part './parts/drawing/_drawing_end_sections.dart';
part './parts/drawing/_drawing_aux.dart';

// 🎨 UI
part './parts/ui/_build_ui.dart';
part './parts/ui/_ui_toolbar.dart';
part './parts/ui/_ui_canvas_layer.dart';
part './parts/ui/_ui_canvas_layer_painters.dart';
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

/// 🔄 Cross-session wheel mode preference.
/// Persists to a tiny file in the app documents directory.
class _WheelModePref {
  static bool _enabled = false;
  static bool _loaded = false;

  static bool get enabled => _enabled;
  static set enabled(bool v) {
    _enabled = v;
    _save();
  }

  /// Load from disk (fire-and-forget, safe to call multiple times).
  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final dir = await getSafeDocumentsDirectory();
      if (dir == null) return;
      final f = File('${dir.path}/.fluera_wheel_pref');
      if (await f.exists()) {
        _enabled = (await f.readAsString()).trim() == '1';
      }
    } catch (_) {}
  }

  static void _save() {
    getSafeDocumentsDirectory().then((dir) {
      if (dir == null) return;
      File('${dir.path}/.fluera_wheel_pref')
          .writeAsString(_enabled ? '1' : '0');
    }).catchError((_) {});
  }
}

/// 🎨 FLUERA CANVAS SCREEN — SDK-level Professional Canvas
///
/// Caratteristiche:
/// - Infinite canvas with zoom and pan
/// - Zero latency with ValueNotifier
/// - Smoothing adattivo OneEuroFilter
/// - Post-stroke optimization with Douglas-Peucker
/// - Rendering vettoriale puro (no GPU cache)
/// - Triple smoothing for fountain pen
/// - Physics-based ink simulation
/// - 💾 AUTO-SAVE at each stroke/edit (via FlueraCanvasConfig)
///
/// All external dependencies (Firebase, auth, subscription, sync) are
/// injected via [FlueraCanvasConfig] — no direct app coupling.
class FlueraCanvasScreen extends StatefulWidget {
  /// SDK configuration — all external deps injected here
  final FlueraCanvasConfig config;

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

  /// 🎯 Nascondi toolbar
  final bool hideToolbar;

  /// 🖼️ Callback per richiedere aggiunta immagine dall'esterno
  final VoidCallback? onAddImageRequested;

  /// 🎤 Controller playback opzionale (per split view con sync)
  final SynchronizedPlaybackController? externalPlaybackController;

  /// 📄 Pagina specifica per playback (se usato in split view)
  final int? playbackPageIndex;

  /// 🎤 Callback to notify the addition of an external stroke
  final void Function(ProStroke stroke, DateTime startTime, DateTime endTime)?
  onExternalStrokeAdded;

  const FlueraCanvasScreen({
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
  State<FlueraCanvasScreen> createState() => _FlueraCanvasScreenState();
}

class _FlueraCanvasScreenState extends State<FlueraCanvasScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  // ── SDK Config shortcut ──────────────────────────────────────────────────
  FlueraCanvasConfig get _config => widget.config;

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
  FlueraSyncEngine? _syncEngine;

  /// 🔴 Real-time collaboration engine (manages subscriptions, cursors, locks)
  FlueraRealtimeEngine? _realtimeEngine;
  StreamSubscription<CanvasRealtimeEvent>? _realtimeEventSub;

  /// 🤝 Is this canvas shared with other users?
  bool _isSharedCanvas = false;

  /// 🔒 Is the current user in view-only mode?
  bool _isViewerMode = false;

  /// 💎 Cached subscription tier
  FlueraSubscriptionTier get _subscriptionTier => _config.subscriptionTier;

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

  /// 🔄 Flag to disable auto-save during loading + show splash screen.
  /// 🚀 P99 FIX: ValueNotifier so loading overlay rebuilds independently.
  final ValueNotifier<bool> _isLoadingNotifier = ValueNotifier(true);
  bool get _isLoading => _isLoadingNotifier.value;
  set _isLoading(bool v) => _isLoadingNotifier.value = v;

  /// Whether the loading overlay has fully faded out and can be removed from tree
  bool _loadingOverlayDismissed = false;

  /// 🖼️ Splash screen snapshot (low-res PNG of last saved canvas state).
  /// Loaded during init and shown as background of the loading overlay.
  Uint8List? _splashSnapshot;

  /// 🎯 Key for the RepaintBoundary that wraps the canvas area.
  /// Used to capture viewport snapshots for the splash screen preview.
  final GlobalKey _canvasRepaintBoundaryKey = GlobalKey();

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

  /// 🚀 P99 FIX: Cached toolbar widget — same instance every build.
  /// Flutter's `identical(old, new)` skips the toolbar on parent setState.
  late final Widget _toolbarHost;

  /// 🚀 STRUCTURAL FIX: Cached core rendering layers — same instances every build.
  /// These widgets are the heaviest sub-trees in _buildCanvasArea.
  /// Caching them as `late final` means parent setState() NEVER reconstructs
  /// their widget trees (~700+ widgets). Internal ListenableBuilder/
  /// ValueListenableBuilder handle canvas-specific repaints autonomously.
  late final Widget _backgroundLayerHost;
  /// 🎨 Notifier for background settings changes (paper type, color, surface).
  /// Incrementing this causes the background layer to rebuild with new values.
  final ValueNotifier<int> _backgroundVersionNotifier = ValueNotifier<int>(0);
  late final Widget _drawingLayerHost;
  late final Widget _imageLayerHost;
  late final Widget _gestureLayerHost;
  /// 🎯 Fires ONLY when gesture-affecting tool state changes (pan/stylus mode).
  /// Much more targeted than listening to the full _toolController.
  final _gestureRebuildNotifier = ValueNotifier<int>(0);
  late final Widget _currentStrokeHost;
  late final Widget _remoteLiveStrokesHost;
  late final Widget _pdfPlaceholdersHost;

  /// 🔥 VULKAN: Native GPU stroke overlay service
  final VulkanStrokeOverlayService _vulkanStrokeOverlay =
      VulkanStrokeOverlayService();
  int? _vulkanTextureId;
  bool _vulkanOverlayActive = false;
  /// 🔥 VULKAN HANDOFF: controls Texture widget opacity without setState.
  /// 0.0 = hidden (pen-up), 0.7 = marker brush, 1.0 = other brushes.
  final ValueNotifier<double> _vulkanTextureOpacity = ValueNotifier<double>(1.0);

  /// 🌐 WEBGPU: Web GPU stroke overlay (active only on web)
  bool _webGpuOverlayActive = false;
  final WebGpuStrokeOverlayService _webGpuStrokeOverlay =
      WebGpuStrokeOverlayService();

  /// 🚀 P99 FIX: Lightweight notifier for toolbar undo/redo state.
  /// Fires ONLY when canUndo/canRedo/elementCount transitions — not on every
  /// _layerController notification. Prevents toolbar rebuild per stroke add.
  final ValueNotifier<int> _undoRedoVersion = ValueNotifier(0);
  bool _lastCanUndo = false;
  bool _lastCanRedo = false;
  int _lastElementCount = 0;

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

  /// 🔮 Ink prediction bubble data (null = hidden)
  _InkPredictionBubbleData? _activePredictionBubble;

  /// 🔮 Show a prediction bubble at the given screen position.
  void _showPredictionBubble(InkPrediction prediction, Offset screenPos) {
    // Dismiss any existing prediction bubble first
    _activePredictionBubble = _InkPredictionBubbleData(
      prediction: prediction,
      anchor: screenPos,
      strokeCount: InkPredictionService.instance.strokeCount,
    );
    _uiRebuildNotifier.value++;
  }

  /// 🔮 Dismiss the prediction bubble.
  void _dismissPredictionBubble() {
    if (_activePredictionBubble == null) return;
    _activePredictionBubble = null;
    _uiRebuildNotifier.value++;
  }

  /// 🔮 Clear prediction when tool switches away from freehand pen.
  void _onToolChangeForPrediction() {
    // Only clear if we have an active prediction
    if (_activePredictionBubble == null &&
        !InkPredictionService.instance.hasAccumulatedInk) return;

    // If switching to eraser, lasso, or pan → prediction no longer relevant
    if (_effectiveIsEraser || _effectiveIsLasso || _effectiveIsPanMode) {
      _dismissPredictionBubble();
      InkPredictionService.instance.clear();
    }
  }

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

  // ============================================================================
  // 🖊️ HOVER CURSOR SYNC — maps tool state to StylusHoverState
  // ============================================================================

  void _syncHoverState() {
    final hover = StylusHoverState.instance;

    // Map tool mode
    if (_toolController.isEraserMode) {
      hover.setToolMode(HoverToolMode.eraser);
      hover.setEraserSize(_toolController.width * 3); // Eraser is wider
    } else if (_toolController.isLassoMode) {
      hover.setToolMode(HoverToolMode.selection);
    } else if (_toolController.isPanMode) {
      hover.setToolMode(HoverToolMode.pan);
    } else if (_toolController.isTextMode) {
      hover.setToolMode(HoverToolMode.text);
    } else {
      hover.setToolMode(HoverToolMode.brush);
    }

    // Sync brush context
    hover.setBrushContext(
      size: _toolController.width,
      color: _toolController.color,
      opacity: _toolController.opacity,
    );
  }

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
  final GlobalKey<ActionFlashOverlayState> _actionFlashKey = GlobalKey<ActionFlashOverlayState>();
  final List<Color> _recentColors = [];
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

  /// 🔲 Whether a gestural lasso (tap + drag) is currently active.
  bool _isGesturalLassoActive = false;

  /// 🔲 #1: Tool ID before gestural lasso activated (for auto-return).
  String? _previousToolBeforeGesturalLasso;

  /// 🔲 Whether the current lasso was activated via gestural tap+drag.
  /// Used as guard because _previousToolBeforeGesturalLasso can be null
  /// (drawing mode has null activeToolId).
  bool _wasGesturalLassoActivated = false;

  /// 🔲 #4: Smoothing buffer for gestural lasso path points.
  final List<Offset> _gesturalLassoSmoothBuffer = [];

  /// 🔲 #10: Velocity tracking for path simplification.
  Offset _gesturalLassoLastPoint = Offset.zero;
  int _gesturalLassoLastTime = 0;

  /// 🔲 #4 (visual): Closing ripple position (screen coords) and controller.
  Offset? _lassoRippleCenter;
  AnimationController? _lassoRippleController;

  // 🌊 REFLOW: Cluster detector, cache, and animated controller
  ClusterDetector? _clusterDetector;
  List<ContentCluster> _clusterCache = [];
  AnimatedReflowController? _animatedReflowController;

  // ✂️ SPACE-SPLIT: Controller for two-finger vertical spread gesture
  final SpaceSplitController _spaceSplitController = SpaceSplitController();
  /// ✂️ Snapshot of stroke positions before split — used for undo.
  Map<String, List<ProDrawingPoint>>? _preSplitStrokeSnapshot;

  // 🧠 KNOWLEDGE FLOW: Connection graph + particle animation
  KnowledgeFlowController? _knowledgeFlowController;
  Ticker? _knowledgeParticleTicker;
  bool _particleTickerWasActive = false; // 🔮 Tracks ticker state across app lifecycle
  ClusterThumbnailCache? _thumbnailCache;

  // 🧠 SEMANTIC MORPHING: Zoom-out semantic view controller
  SemanticMorphController? _semanticMorphController;

  // 🧠 KNOWLEDGE FLOW: Connection drag state
  bool _isConnectionDragging = false;
  Offset? _connectionDragSourcePoint;
  Offset? _connectionDragCurrentPoint;
  String? _connectionDragSourceClusterId;
  String? _connectionSnapTargetClusterId;

  // 🏷️ KNOWLEDGE FLOW: Label editor overlay state
  String? _editingLabelConnectionId;
  Offset? _labelOverlayScreenPosition;

  // 🏷️ KNOWLEDGE FLOW: Pending connection tap (deferred to touch-up)
  String? _pendingLabelConnectionId;
  Offset? _pendingLabelScreenPos;

  // 👆 KNOWLEDGE FLOW: Double-tap detection for graph highlight
  int _lastConnectionTapMs = 0;
  String? _lastConnectionTapId;

  // 🧭 KNOWLEDGE FLOW: Connection navigation index (3-finger swipe)
  int _connectionNavIndex = -1;

  // 🎨 KNOWLEDGE FLOW: Curve drag state (control point adjustment)
  bool _isCurveDragging = false;
  String? _curveDragConnectionId;

  // 🔍 KNOWLEDGE FLOW: Cluster preview overlay state
  String? _previewingClusterId;
  Offset? _previewOverlayScreenPosition;

  // 💡 KNOWLEDGE FLOW: Suggestion preview card state
  SuggestedConnection? _previewSuggestion;
  Offset? _previewSuggestionPosition;
  Map<String, String> _previewClusterTexts = {};

  // 🧠 KNOWLEDGE MAP: Fullscreen graph overlay
  bool _showKnowledgeMap = false;

  // 🌟 RADIAL EXPANSION: Generative mind-mapping controller + tick timer
  RadialExpansionController? _radialExpansionController;
  Timer? _radialExpansionTimer;

  // 🌟 RADIAL EXPANSION: Gesture tracking (Minority Report flow)
  ContentCluster? _radialExpansionLongPressCluster; // cluster hit by long-press
  String? _radialDraggedBubbleId;                  // bubble currently being dragged
  Offset? _radialDragStartCanvas;                  // canvas pos when drag started
  double _radialExpansionHapticThreshold = 0.0;    // haptic escalation tracking

  // 💡 PROACTIVE KNOWLEDGE GAP: Background analysis state
  final Map<String, ProactiveAnalysisEntry> _proactiveCache = {};
  Timer? _proactiveDebounceTimer;                  // 2s debounce after drawing stops
  final Set<String> _proactiveRunning = {};         // per-cluster analysis lock
  String? _activeExplainCardId;                    // current chip-explain card (single at a time)

  // 🚀 PERF: Cached maps rebuilt only when _proactiveCache mutates (not every paint frame)
  Map<String, List<String>> _proactiveGapsCache = const {};
  Map<String, String> _proactiveScanCache = const {};

  /// Rebuild the cached proactive maps. Call after any _proactiveCache mutation.
  void _rebuildProactiveMaps() {
    _proactiveGapsCache = {
      for (final e in _proactiveCache.entries)
        if (e.value.gaps.isNotEmpty) e.key: e.value.gaps,
    };
    _proactiveScanCache = {
      for (final e in _proactiveCache.entries)
        if (e.value.scanText.isNotEmpty) e.key: e.value.scanText,
    };
  }

  // 📊 SESSION TRACKING
  final List<String> _sessionExplored = [];         // concepts explored this session
  final Set<String> _sessionMastered = {};          // concepts rated "lo so già"
  final Map<String, SrsCardData> _reviewSchedule = {}; // FSRS spaced repetition: concept → card data
  final Map<String, String> _conceptFailHistory = {}; // concept → last failed mode ('spiega'|'esempio')
  final Set<String> _hiddenClusters = {};             // clusters hidden for retrieval practice
  final Map<String, Map<String, dynamic>> _calibrationLog = {}; // metacognitive calibration
  StreamSubscription<FNotificationTapEvent>? _notifSub; // notification tap handler
  Timer? _srNotifDebounce; // debounce for SR notification scheduling

  // ➡️ NEXT DOT HINT — transient arrow pointing to next ready dot after card dismiss
  Offset? _nextDotHintTarget;
  Timer? _nextDotHintTimer;


  // 🎯 RADIAL MENU: Context menu on long-press
  bool _showRadialMenu = false;
  Offset _radialMenuCenter = Offset.zero;
  final _radialMenuKey = GlobalKey<CanvasRadialMenuState>();

  // 🌌 ATLAS AI: Prompt overlay state
  bool _showAtlasPrompt = false;
  bool _atlasIsLoading = false;
  String? _atlasResponseText;
  String? _atlasLoadingPhase; // (C) Current loading phase description


  // 🌌 ATLAS VFX: Active visual effects
  final List<_AtlasVfxEntry> _atlasVfxEntries = [];

  // 🔮 ATLAS RESPONSE CARDS: Multiple concurrent holographic cards (4)
  final List<_AtlasCardEntry> _atlasCards = [];

  // (1) Follow-up context for "Go deeper"
  String? _atlasFollowUpContext;

  /// 🔄 WHEEL MODE: When true, toolbar is hidden and long-press opens radial wheel.
  /// Persists across widget rebuilds via static holder.
  bool get _useRadialWheel => _WheelModePref.enabled;
  set _useRadialWheel(bool v) => _WheelModePref.enabled = v;

  /// 2️⃣ TOAST: confirmation message shown after toggle.
  String? _wheelModeToast;
  bool _wheelModeToastVisible = false;

  /// 4️⃣ AUTO-HIDE: pill fades out after inactivity.
  bool _wheelPillVisible = true;
  DateTime _wheelPillLastInteraction = DateTime.now();

  void _toggleWheelMode() {
    setState(() {
      _useRadialWheel = !_useRadialWheel;
      if (_showRadialMenu) _showRadialMenu = false;

      _wheelModeToast = _useRadialWheel
          ? 'Wheel mode — long-press to open'
          : 'Toolbar mode';
      _wheelModeToastVisible = true;

      _wheelPillVisible = true;
      _wheelPillLastInteraction = DateTime.now();
    });
    HapticFeedback.mediumImpact();

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _wheelModeToastVisible = false);
    });

    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && DateTime.now().difference(_wheelPillLastInteraction).inSeconds >= 4) {
        setState(() => _wheelPillVisible = false);
      }
    });
  }

  void _showWheelPill() {
    setState(() {
      _wheelPillVisible = true;
      _wheelPillLastInteraction = DateTime.now();
    });
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && DateTime.now().difference(_wheelPillLastInteraction).inSeconds >= 4) {
        setState(() => _wheelPillVisible = false);
      }
    });
  }

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

  /// 📝 Inline text editing state
  bool _isInlineEditing = false;
  DigitalTextElement? _inlineEditingElement;
  DateTime? _inlineTextFinishedAt; // 🔒 Cooldown to prevent spurious re-creation
  final _inlineOverlayKey = GlobalKey<InlineTextOverlayState>();
  Color _inlineTextColor = Colors.black;
  FontWeight _inlineTextFontWeight = FontWeight.normal;
  FontStyle _inlineTextFontStyle = FontStyle.normal;
  double _inlineTextFontSize = 24.0;
  String _inlineTextFontFamily = 'Roboto';
  Shadow? _inlineTextShadow;
  Color? _inlineTextBackgroundColor;
  TextDecoration _inlineTextDecoration = TextDecoration.none;
  TextAlign _inlineTextAlign = TextAlign.left;
  double _inlineTextLetterSpacing = 0.0;
  double _inlineTextOpacity = 1.0;
  double _inlineTextRotation = 0.0;
  Color? _inlineTextOutlineColor;
  double _inlineTextOutlineWidth = 0.0;
  List<Color>? _inlineTextGradientColors;

  /// 📋 Copied text style for paste-style feature
  Map<String, dynamic>? _copiedTextStyle;

  /// ✨ Track last added text for entry animation
  String? _lastAddedTextId;
  DateTime _lastAddedTextTime = DateTime(2000);

  /// 🔍 Text search query (empty = no search active)
  String _textSearchQuery = '';

  /// 🔍 Handwriting search overlay state
  bool _showHandwritingSearch = false;
  List<HandwritingSearchResult> _hwSearchResults = [];
  int _hwSearchActiveIndex = 0;

  /// 🔍 ECHO SEARCH: Jarvis-style spatial search (Query Pen mode)
  EchoSearchController? _echoSearchController;
  bool _isEchoSearchMode = false;


  /// 🎨 Current text selection for rich text styling
  TextSelection? _inlineTextSelection;

  /// 📝 Double-tap detection for text editing
  String? _lastTappedTextId;
  DateTime _lastTextTapTime = DateTime(2000);

  /// 🖼️ Image tool
  late final ImageTool _imageTool;
  final List<ImageElement> _imageElements = [];
  final Map<String, ui.Image> _loadedImages = {};

  /// 📌 Recording pins on canvas
  final List<RecordingPin> _recordingPins = [];

  /// State for pin placement mode (user tapped 📌 in popup)
  bool _isPinPlacementMode = false;
  SynchronizedRecording? _pinPlacementRecording;

  /// State for pin dragging
  String? _draggingPinId;
  Offset? _draggingPinOffset;
  Offset? _pinDragStartCanvasPos;

  /// 📊 Tabular interaction tool
  late final TabularInteractionTool _tabularTool;
  bool _editingInCell = false;

  /// 🧮 LatexNode interaction state
  LatexNode? _selectedLatexNode;
  bool _isDraggingLatex = false;
  Offset? _latexDragStart;

  /// 📈 FunctionGraphNode interaction state
  FunctionGraphNode? _selectedGraphNode;
  bool _isDraggingGraph = false;
  bool _isMovingGraph = false; // Long-press initiated: drag moves graph position
  bool _isDraggingGraphSlider = false; // Slider panel touch — blocks canvas processing
  Offset? _graphDragStart;
  int _lastGraphTapTime = 0; // double-tap detection
  bool _isResizingGraph = false;
  int _graphResizeCorner = -1; // 0=TL,1=TR,2=BL,3=BR
  Offset? _graphResizeAnchor; // opposite corner (fixed)

  // 📈 Graph pinch-to-viewport-zoom state
  double _graphPinchInitXMin = 0, _graphPinchInitXMax = 0;
  double _graphPinchInitYMin = 0, _graphPinchInitYMax = 0;
  bool _graphPinchStarted = false;

  /// 🧠 Version counter: incremented on every image content mutation
  /// Used by ImagePainter for fast shouldRepaint + Picture cache invalidation
  int _imageVersion = 0;

  /// 🚀 PERF: Dedicated repaint notifier for the image layer ONLY.
  /// During drag/resize, incrementing this triggers ONLY the ImagePainter
  /// repaint — NOT DrawingPainter or BackgroundPainter. This is the key
  /// optimization that prevents re-rendering all strokes every frame.
  final ValueNotifier<int> _imageRepaintNotifier = ValueNotifier<int>(0);

  /// 🚀 PERF: General UI rebuild notifier — replaces setState(() {}) for
  /// toolbar/overlay updates. Only rebuilds the overlay subtree, NOT the
  /// entire widget tree (saves ~1-2ms per frame vs full setState).
  final ValueNotifier<int> _uiRebuildNotifier = ValueNotifier<int>(0);

  /// 🤏 Selection pinch transform state (used by _drawing_handlers extension)
  bool _isSelectionPinching = false;
  double _selectionPrevRotation = 0.0;
  double _selectionPrevScale = 1.0;
  double _selectionAccumRotation = 0.0; // Total rotation in radians (for indicator + snap)
  double _selectionAccumScale = 1.0; // Cumulative scale factor (for indicator + limits)
  double? _selectionLastSnapAngle; // Last snapped angle (for haptic dedup)

  /// 🌐 R-tree spatial index for O(log n) image viewport culling
  RTree<ImageElement>? _imageSpatialIndex;

  /// 🧠 LRU memory manager for loaded images
  final ImageMemoryManager _imageMemoryManager = ImageMemoryManager(
    maxImages: 20,
  );

  /// 🧠 Adaptive memory budget for device-aware image sizing
  final ImageMemoryBudget _imageMemoryBudget = ImageMemoryBudget();

  /// 🗂️ Viewport-aware stub manager for zero-cost off-viewport images
  final ImageStubManager _imageStubManager = ImageStubManager();

  /// 🕐 Periodic timer for proactive image eviction (off-viewport > 5s)
  Timer? _imageEvictionTimer;

  /// 🔋 ENERGY: Whether device is in low-power / thermal throttle mode.
  bool _isLowPowerMode = false;

  /// 🔋 ENERGY: Reactive subscription to power/thermal state changes.
  StreamSubscription<dynamic>? _metricsSubscription;

  /// 🔋 ENERGY: React to power mode changes — throttle background work.
  void _onPowerModeChanged(bool isLowPower) {
    _isLowPowerMode = isLowPower;

    // 1. Throttle eviction timer: 5s normal → 15s low-power
    _imageEvictionTimer?.cancel();
    _imageEvictionTimer = Timer.periodic(
      Duration(seconds: isLowPower ? 15 : 5),
      (_) => _runImageEvictionCycle(),
    );

    // 2. Suppress PDF prefetch in low-power mode
    for (final painter in _pdfPainters.values) {
      painter.suppressPrefetch = isLowPower;
    }
  }

  /// 🖼️ Set of image paths currently loaded at thumbnail resolution.
  /// When zooming back in, these are reloaded at full resolution.
  final Set<String> _thumbnailPaths = {};

  /// 📄 PDF providers: one per imported document (keyed by document ID)
  final Map<String, NativeFlueraPdfProvider> _pdfProviders = {};

  /// 📄 PDF page painters: one per document for LOD-aware rendering
  final Map<String, PdfPagePainter> _pdfPainters = {};

  /// 📄 Active PDF upload futures (for cancel support)
  final Map<String, Future<void>> _activePdfUploads = {};

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

  /// 🚀 LOD DEBOUNCE: defers DrawingPainter LOD tier repaint until
  /// 300ms after zoom gesture settles. Eliminates 14-23ms frame skip.
  Timer? _lodDebounceTimer;
  int _lastWidgetLodTier = 0;

  /// Currently selected PDF page index (for insert-at-position).
  int _pdfSelectedPageIndex = 0;

  /// Whether to show page number badges on PDF pages.
  bool _showPdfPageNumbers = true;

  /// Cooldown flag to prevent re-triggering zoom-to-enter during animation.
  bool _pdfZoomEnterCooldown = false;
  bool _imageZoomEnterCooldown = false;
  int _lastImageZoomCheckTime = 0;

  /// Timestamp of last zoom-to-enter check (throttle continuous detection).
  int _lastZoomCheckTime = 0;

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

  /// 🚀 FIRST-ENTRY OPT: Debounce R-tree rebuild — at most once per frame.
  /// During initial image load, N images complete nearly simultaneously.
  /// Without debounce: N × O(N log N) = O(N² log N) UI-thread work.
  /// With debounce: 1 × O(N log N) per frame.
  bool _imageSpatialIndexDirty = false;

  void _scheduleImageSpatialIndexRebuild() {
    if (_imageSpatialIndexDirty) return;
    _imageSpatialIndexDirty = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _imageSpatialIndexDirty = false;
      if (mounted) _rebuildImageSpatialIndex();
    });
  }

  /// 🔄 Loading pulse animation for image placeholders
  Timer? _loadingPulseTimer;
  Timer? _suggestionDebounceTimer; // 💡 Debounced suggestion recomputation
  // 🔤 SEMANTIC CACHE: Avoid re-recognizing unchanged clusters
  final Map<String, String> _clusterTextCache = {};        // clusterId → text
  final Map<String, String> _clusterTextCacheKeys = {};    // clusterId → sorted strokeIds hash
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
  double? _lastSnapAngle; // 🧲 Track last snapped angle for haptic dedup

  /// 📝 Deferred text creation position: saved on pointer-down, consumed on
  /// pointer-up. Cleared on cancel (pinch) to prevent unwanted text creation.
  Offset? _pendingTextCreationPosition;

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

  // ─── 🧹 SCRATCH-OUT State ─────────────────────────────────────────
  /// Bounds of the area being scratch-out deleted (for dissolve animation).
  Rect? _scratchOutBounds;
  /// Whether the scratch-out dissolve animation is playing.
  bool _scratchOutAnimating = false;
  /// Deleted stroke data for particle dissolve effect.
  List<_ScratchOutParticle> _scratchOutParticles = [];
  /// Set to true when draw is cancelled (zoom interrupt) — suppresses scratch-out.
  bool _drawWasCancelled = false;
  /// Timestamp of last _onDrawCancel — used to skip heavy init during zoom churn.
  int _lastDrawCancelMs = 0;

  // ─── 🧹 SCRATCH-OUT v5: Real-time preview + dissolve ──────────────
  /// Incremental scratch-out detector (O(1) per point).
  final ScratchOutAccumulator _scratchOutAccumulator = ScratchOutAccumulator();
  /// Stroke IDs currently highlighted as "will be deleted" (red tint preview).
  Set<String> _scratchOutPreviewIds = const {};
  /// Whether real-time scratch-out preview has been armed (first haptic fired).
  bool _scratchOutPreviewArmed = false;
  /// Last reversal count for progressive haptic dedup.
  int _scratchOutLastReversalCount = 0;
  /// Strokes dissolving: strokeId → remaining opacity (1.0 → 0.0 over 300ms).
  Map<String, double> _scratchOutDissolveMap = const {};
  /// Dissolve animation ticker (drives opacity decrease).
  Ticker? _scratchOutDissolveTicker;
  /// Dissolve start timestamp for animation progress.
  int _scratchOutDissolveStartMs = 0;

  // ─── V7 State ──────────────────────────────────────────────────────
  String? _smartSelectionStrokeId;
  bool _showUndoGhostReplay = false;
  bool _showPressureCurveEditor = false;
  bool _showLayerPreview = false;
  int _eraserShapeMode = 0;

  final ValueNotifier<ProStroke?> _currentEditingStrokeNotifier = ValueNotifier(
    null,
  );

  // 🎤 State per tracking temporale strokes
  DateTime? _lastStrokeStartTime;

  /// 🎤 Audio recording state
  bool _isRecordingAudio = false;
  Duration _recordingDuration = Duration.zero;

  /// 🚀 P99 FIX: ValueNotifiers for recording UI — toolbar observes these
  /// directly, avoiding full canvas setState() during recording.
  final ValueNotifier<Duration> _recordingDurationNotifier = ValueNotifier(
    Duration.zero,
  );
  final ValueNotifier<double> _recordingAmplitudeNotifier = ValueNotifier(0.0);

  /// 🚀 Toolbar rebuild trigger: notifies ListenableBuilder when recording
  /// starts/stops so the cached toolbar host picks up isRecordingActive.
  final ValueNotifier<bool> _isRecordingNotifier = ValueNotifier(false);

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

  /// 🎵 Audio-only playback state (mini-player)
  bool _isPlayingAudio = false;
  String _playingRecordingName = '';
  Duration _playbackPosition = Duration.zero;
  Duration _playbackDuration = Duration.zero;
  StreamSubscription<Duration>? _playbackPositionSub;
  StreamSubscription<Duration?>? _playbackDurationSub;
  Timer? _playbackPollingTimer;
  bool _isPlaybackPaused = false;
  double _playbackSpeed = 1.0;
  bool _showRemainingTime = false;
  bool _isLooping = false;
  String _currentPlaybackPath = '';
  double _playbackVolume = 1.0;
  bool _isScrubbing = false;
  double _lastVolumeBeforeMute = 1.0;
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
  List<ContentCluster> _exportClusters = const [];
  int _currentClusterIndex = -1; // -1 = "frame all" mode

  // ============================================================================
  // ⏱️ TIME TRAVEL STATE
  // ============================================================================

  bool _isTimeTravelMode = false;
  bool _wasPanModeBeforeTimeTravel = false;
  bool _isTimeTravelLassoMode = false;
  bool _isRecoveryPlacementMode = false;

  // ============================================================================
  // 🖥️ MULTIVIEW STATE
  // ============================================================================

  bool _isMultiviewActive = false;
  AdvancedSplitLayout? _multiviewLayout;

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
  bool _isSectionActive = false;
  Offset? _sectionStartPoint;
  Offset? _sectionCurrentEndPoint;
  int _sectionCounter = 1;

  // 📐 Technical Pen — Angle Snap State Machine
  Offset? _techAnchor; // Fixed anchor for current line segment
  double? _techLockedAngle; // Locked direction angle (radians), null = undecided
  double? _techPrevRawAngle; // Previous raw angle for hysteresis

  // 📐 Technical Pen — Visual Overlay State (fed to _TechPenGuidePainter)
  Offset? _techSnapAnchor; // Current anchor for guide line
  double? _techSnapAngleDeg; // Current angle for badge (degrees)
  double? _techSegmentLength; // Current segment length for display

  // 📐 Technical Pen — Other Feature State
  bool _techNearStartPoint = false; // True when endpoint near start (close shape)
  Offset? _techStraightGhostEnd; // End of straightened ghost line
  Offset? _techLastGridCell; // Last grid cell for haptic dedup
  double? _techLastStrokeAngleRad; // Angle of last completed stroke (for parallel/perp)
  List<Offset> _techMultiSegmentPoints = []; // Multi-segment tap points
  List<Offset> _techIntersections = []; // Intersection points with existing strokes

  // Section drag-to-move state
  SectionNode? _draggingSectionNode;
  Offset? _sectionDragGrabOffset;

  // Section resize state
  SectionNode? _resizingSectionNode;
  Offset? _resizeAnchorCorner; // The fixed corner (opposite to grabbed)
  String?
  _resizeEdgeAxis; // null = corner, 'h' = horizontal edge, 'v' = vertical edge

  // Double-tap zoom-to-fit state
  SectionNode? _lastTappedSection;
  DateTime? _lastTapTime;

  @override
  void initState() {
    super.initState();

    // 🌍 Auto-detect dictionary language from device locale
    final deviceLocale = WidgetsBinding.instance.platformDispatcher.locale;
    WordCompletionDictionary.instance.setLanguageFromCode(
      deviceLocale.languageCode,
    );
    // 💾 Load persisted learned words from disk
    WordCompletionDictionary.instance.loadUserFrequency();

    // 🔄 Load wheel mode preference from disk
    _WheelModePref.load().then((_) {
      if (mounted) setState(() {});
    });

    // 📅 Load spaced repetition schedule from disk
    _loadSpacedRepetition().then((_) {
      _checkDueForReview();
      _checkRipasso24h(); // 🔄 24h Ebbinghaus trigger
    });
    _loadSeenClusters(); // 👁️ Restore dismissed dots

    // 🔔 Listen for notification taps (SR review reminders)
    _setupNotificationTapHandler();

    // ── Tool state controller (replaces Riverpod) ──────────────────────────
    _toolController = UnifiedToolController();
    _toolController.addListener(_syncHoverState);
    _toolController.addListener(_onToolChangeForPrediction);
    _syncHoverState(); // Initial sync

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

    // ☁️ Initialize cloud sync engine (if adapter provided)
    if (_config.cloudAdapter != null) {
      _syncEngine = FlueraSyncEngine(adapter: _config.cloudAdapter!);
    }

    // Initialize layer controller
    _layerController = LayerController();
    _layerController.enableDeltaTracking = true;
    _layerController.addListener(_onLayerChanged);
    _refreshCachedLists();

    // 🚀 P99 FIX: Cache toolbar widget — stored as field so identical()
    // short-circuits on parent setState. Internal ListenableBuilder handles
    // toolbar-specific rebuilds via _toolController + _layerController.
    _toolbarHost = Builder(
      builder: (ctx) => RepaintBoundary(child: _buildToolbar(ctx)),
    );

    // 🚀 STRUCTURAL FIX: Cache all core rendering layers.
    // identical(old, new) == true on parent setState → Flutter skips these
    // entire sub-trees. Internal ListenableBuilder/ValueListenableBuilder
    // handle canvas-specific repaints autonomously.
    _backgroundLayerHost = ValueListenableBuilder<int>(
      valueListenable: _backgroundVersionNotifier,
      builder: (_, __, ___) => _buildBackgroundLayer(),
    );
    _drawingLayerHost = Builder(builder: (_) => _buildDrawingLayer());
    _imageLayerHost = Builder(builder: (_) => _buildImageLayer());
    _gestureLayerHost = ValueListenableBuilder<int>(
      valueListenable: _gestureRebuildNotifier,
      builder: (ctx, _, __) => _buildGestureDetectorLayer(ctx),
    );

    _currentStrokeHost = Builder(builder: (_) => _buildCurrentStrokeLayer());
    _remoteLiveStrokesHost = Builder(
      builder: (_) => _buildRemoteLiveStrokesLayer(),
    );
    _pdfPlaceholdersHost = Builder(
      builder: (_) => _buildPdfLoadingPlaceholdersLayer(),
    );

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

    // 🔲 Closing ripple animation (400ms expand + fade)
    _lassoRippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _lassoRippleCenter = null;
          _uiRebuildNotifier.value++;
        }
      });

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

    // 🚀 LOD TIER TRANSITION: invalidate tile cache when zoom crosses
    // LOD boundaries (0.2x, 0.5x). Without this, the RepaintBoundary-cached
    // CustomPaint never repaints during zoom, so strokes stay visible
    // at extreme dezoom instead of fading out.
    _canvasController.onLodTierChanged = () {
      DrawingPainter.invalidateAllTiles();
      _layerController.notifyListeners();
      HapticFeedback.lightImpact(); // subtle "mode change" feedback

      // 🔮 PARTICLE TICKER: Auto-start when entering LOD 1/2 with connections,
      // auto-stop when returning to LOD 0 (battery savings)
      final scale = _canvasController.scale;
      if (scale < 0.5 &&
          _knowledgeFlowController != null &&
          _knowledgeFlowController!.connections.isNotEmpty &&
          _knowledgeParticleTicker != null &&
          !_knowledgeParticleTicker!.isActive) {
        _knowledgeParticleTicker!.start();
      } else if (scale >= 0.5 &&
          _knowledgeParticleTicker != null &&
          _knowledgeParticleTicker!.isActive) {
        // Don't stop ticker if birth/dissolve animations are still running
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final hasActiveAnimation = _knowledgeFlowController?.connections.any(
          (c) => (c.createdAtMs > 0 && nowMs - c.createdAtMs < 2000) ||
                 c.deletedAtMs > 0,
        ) ?? false;
        if (!hasActiveAnimation) {
          _knowledgeParticleTicker!.stop();
        }
      }

      // 🧠 SEMANTIC TITLES: Preload OCR + AI titles when approaching morph threshold
      _checkSemanticTitlePreload(scale);
    };

    // 🔑 When gesture/animation fully ends, rebuild the DrawingPainter child
    // so it re-renders at the new LOD tier. Without this, the AnimatedBuilder
    // caches the child widget and never rebuilds it after zoom.
    _canvasController.onGestureEnd = () {
      if (mounted) _layerController.notifyListeners();
      // 🔍 Check if zoom level triggers PDF immersive entry
      if (mounted) _checkPdfZoomToEnter();
      // 🖼️ Check if zoom level triggers Image immersive entry
      if (mounted) _checkImageZoomToEnter();
    };

    // 🔍 Real-time zoom detection: check continuously during pinch gestures
    _canvasController.addListener(_onPdfZoomCheck);
    _canvasController.addListener(_onImageZoomCheck);

    // 🌀 Load persisted rotation lock preference
    _canvasController.loadPersistedState();

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

    // 🎛️ Load brush settings persistenti
    _loadBrushSettings();

    // 🚀 JANK FIX: Defer all heavy init to addPostFrameCallback so the
    // splash/loading screen renders on the very FIRST frame. Everything
    // below was previously synchronous in initState, blocking ~127 frames.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // Center canvas
      final size = MediaQuery.of(context).size;
      _canvasController.centerCanvas(size, canvasSize: _canvasSize);

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
        // 🧠 KNOWLEDGE FLOW: Initialize controller + particle ticker + thumbnails
        _knowledgeFlowController = KnowledgeFlowController();
        _radialExpansionController = RadialExpansionController();
        _semanticMorphController = SemanticMorphController();
        _thumbnailCache = ClusterThumbnailCache();
        _knowledgeParticleTicker = createTicker((elapsed) {
          // Tick particles at ~60fps (16ms = 0.016s)
          _knowledgeFlowController?.tickParticles(0.016, _clusterCache);
          if (mounted) {
            _knowledgeFlowController?.version.value++;
          }
        });
        // Start particle animation only when connections exist
        // (started lazily when first connection is created)

        // 🌊 Auto-reflow: animated controller for stroke-commit reflow
        _animatedReflowController = AnimatedReflowController(
          reflowController: _lassoTool.reflowController!,
          vsync: this,
          onApplyDeltas: _applyReflowDeltas,
          onReflowComplete: () {
            DrawingPainter.invalidateAllTiles();
            _layerController.sceneGraph.bumpVersion();
            _autoSaveCanvas();
          },
        );
      }

      // 💾 Initialize stroke persistence service
      EngineScope.current.drawingModule?.strokePersistenceService.initialize(
        _canvasId,
      );

      // 🚀 PERFORMANCE POOLS
      StrokePointPool.instance.initialize();
      PathPool.instance.initialize();

      // 🧠 CONSCIOUS ARCHITECTURE: Register subsystems + start idle timer.
      _initConsciousArchitecture();

      // 🚀 SPLASH SCREEN: Run ALL heavy init in parallel (shader, isolate,
      // textures, data load). The loading overlay is shown until complete.
      _initializeCanvas();

      // 🖐️ HANDEDNESS: Load persisted palm rejection settings
      HandednessSettings.instance.load().then((_) {
        // 🚀 FEATURE 7: First-launch onboarding — auto-show settings sheet
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted) {
            HandednessSettingsSheet.showIfNeeded(context, onChanged: () {
              if (mounted) setState(() {});
            });
          }
        });
      });

      // 🔥 VULKAN: Eagerly initialize so first stroke uses GPU overlay
      _initVulkanOverlayIfNeeded();
    });

    // 🖥️ DISPLAY DETECTION: Delay to avoid init contention
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        _detectDisplayCapabilitiesAndConfigure();
      }
    });

    // 🚀 PERFORMANCE: Defer non-critical initialization
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;

      // 🎤 Recordings already loaded by _initializeCanvas pipeline (L120)
      // — no duplicate call needed here.

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
      // 🚀 SCREEN-OFF OPT: Release non-visible image textures to reduce
      // memory footprint while backgrounded (OS may kill high-memory apps).
      _releaseOffscreenImages();

      // 🚀 SCREEN-OFF OPT B: Release all PDF rasterized page caches.
      // These can be tens of MB. LOD system re-renders on demand at resume.
      for (final painter in _pdfPainters.values) {
        painter.releaseAllCachedPages();
      }

      // 🚀 SCREEN-OFF OPT A: Suspend periodic timer — no CPU wake while bg'd.
      _imageEvictionTimer?.cancel();
      _imageEvictionTimer = null;

      // 🔮 PARTICLE THROTTLE: Stop particle ticker to save battery
      if (_knowledgeParticleTicker != null &&
          _knowledgeParticleTicker!.isActive) {
        _particleTickerWasActive = true;
        _knowledgeParticleTicker!.stop();
      }

      BackgroundSaveService.instance.flush();

      // ☁️ Flush pending cloud save on app background
      if (_syncEngine != null) {
        final saveData = _buildSaveData();
        final cloudData = saveData.toJson();
        cloudData['layers'] = saveData.layers.map((l) => l.toJson()).toList();
        _syncEngine!.flush(_canvasId, _sanitizeForFirestore(cloudData));
      }
    } else if (state == AppLifecycleState.inactive) {
      // 🚀 APP SWITCHER: App partially visible — suspend non-essential work
      // but keep ALL caches intact (user likely returns within seconds).
      _imageEvictionTimer?.cancel();
      _imageEvictionTimer = null;
      _loadingPulseTimer?.cancel();
      _loadingPulseTimer = null;

      // 🔮 PARTICLE THROTTLE: Also stop in app switcher
      if (_knowledgeParticleTicker != null &&
          _knowledgeParticleTicker!.isActive) {
        _particleTickerWasActive = true;
        _knowledgeParticleTicker!.stop();
      }
    } else if (state == AppLifecycleState.resumed) {
      // 🚀 SCREEN-ON OPT: Recover from background
      _onResumeFromBackground();

      // 🔮 PARTICLE THROTTLE: Restart ticker if it was active before pause
      if (_particleTickerWasActive &&
          _knowledgeParticleTicker != null &&
          !_knowledgeParticleTicker!.isActive &&
          _canvasController.scale < 0.5 &&
          _knowledgeFlowController != null &&
          _knowledgeFlowController!.connections.isNotEmpty) {
        _knowledgeParticleTicker!.start();
      }
      _particleTickerWasActive = false;
    }
  }

  /// Timestamp of last resume — used to debounce rapid screen toggles.
  DateTime? _lastResumeTime;

  /// 🚀 SCREEN-ON: Recover GPU caches and image textures after resume.
  void _onResumeFromBackground() {
    // 🚀 OPT C: Debounce rapid resume (< 500ms between toggles)
    final now = DateTime.now();
    if (_lastResumeTime != null &&
        now.difference(_lastResumeTime!).inMilliseconds < 500) {
      return;
    }
    _lastResumeTime = now;

    // 1. Invalidate GPU caches — rasterized textures may be stale
    DrawingPainter.invalidateAllTiles();
    _layerController.sceneGraph.bumpVersion();

    // 2. Re-hydrate viewport images that were released on pause
    _rehydrateViewportImages();

    // 3. 🚀 OPT A: Restart periodic image eviction timer
    _imageEvictionTimer ??= Timer.periodic(
      const Duration(seconds: 5),
      (_) => _runImageEvictionCycle(),
    );

    // 4. Force repaint to refresh the canvas
    if (mounted) {
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _canvasController.markNeedsPaint();
      });
    }
  }

  /// 🚀 SCREEN-OFF: Release images outside viewport to reduce memory.
  void _releaseOffscreenImages() {
    final viewportPaths = _getVisibleImagePaths();
    final toRemove = <String>[];
    for (final entry in _loadedImages.entries) {
      if (!viewportPaths.contains(entry.key)) {
        entry.value.dispose();
        toRemove.add(entry.key);
      }
    }
    for (final key in toRemove) {
      _loadedImages.remove(key);
    }
  }

  /// 🚀 SCREEN-ON: Reload images visible in viewport on resume.
  void _rehydrateViewportImages() {
    for (final img in _imageElements) {
      if (!_loadedImages.containsKey(img.imagePath)) {
        // Fire-and-forget — images appear progressively
        unawaited(
          _preloadImage(
            img.imagePath,
            storageUrl: img.storageUrl,
            thumbnailUrl: img.thumbnailUrl,
          ),
        );
      }
    }
  }

  /// 🖼️ Get image paths currently visible in the viewport.
  Set<String> _getVisibleImagePaths() {
    final scale = _canvasController.scale;
    final offset = _canvasController.offset;
    final size = MediaQuery.of(context).size;
    final viewportRect = Rect.fromLTWH(
      -offset.dx / scale,
      -offset.dy / scale,
      size.width / scale,
      size.height / scale,
    );

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
      if (viewportRect.overlaps(imgRect)) {
        visiblePaths.add(img.imagePath);
      }
    }
    return visiblePaths;
  }

  @override
  void didHaveMemoryPressure() {
    super.didHaveMemoryPressure();
    // 🚨 OS is running low on memory — aggressive eviction
    final visiblePaths = _getVisibleImagePaths();

    final evicted = _imageMemoryManager.onMemoryPressure(
      _loadedImages,
      visiblePaths,
    );

    // ⚡ Shrink stub margins under memory pressure
    _imageStubManager.onMemoryPressure(MemoryPressureLevel.critical);

    // 🚀 GPU: Trim native stroke overlay buffers under memory pressure
    _vulkanStrokeOverlay.onMemoryPressure(MemoryPressureLevel.critical);

    if (evicted > 0) {
      ImagePainter.invalidateCache();
      if (mounted) setState(() => _imageVersion++);
    }
  }

  /// 🛡️ Recursively sanitize data for Firestore by converting nested arrays
  /// (arrays containing arrays) into JSON strings.
  /// Firestore error: "Invalid data. Nested arrays are not supported"
  static Map<String, dynamic> _sanitizeForFirestore(Map<String, dynamic> data) {
    final result = <String, dynamic>{};
    for (final entry in data.entries) {
      result[entry.key] = _sanitizeValue(entry.value);
    }
    return result;
  }

  static dynamic _sanitizeValue(dynamic value) {
    if (value is Map) {
      return _sanitizeForFirestore(Map<String, dynamic>.from(value));
    }
    if (value is List) {
      if (_containsNestedArray(value)) {
        // Convert nested array to JSON string
        return jsonEncode(value);
      }
      return value.map(_sanitizeValue).toList();
    }
    return value;
  }

  /// Check if a list contains any nested lists (Firestore rejects these).
  static bool _containsNestedArray(List list) {
    for (final item in list) {
      if (item is List) return true;
    }
    return false;
  }

  // ============================================================================
  // DISPOSE
  // ============================================================================

  @override
  void dispose() {
    // 🏎️ PERF MONITOR: Remove global overlay before disposing
    CanvasPerformanceMonitor.instance.removeGlobalOverlay();
    // 🔥 VULKAN: Release native GPU overlay resources
    _vulkanStrokeOverlay.dispose();
    // 🧹 SCRATCH-OUT: Release dissolve animation ticker
    _scratchOutDissolveTicker?.stop();
    _scratchOutDissolveTicker?.dispose();
    // 🌊 REFLOW: Release animated reflow controller
    _animatedReflowController?.dispose();
    // 🧠 KNOWLEDGE FLOW: Release controller + ticker + thumbnails
    _knowledgeParticleTicker?.stop();
    _knowledgeParticleTicker?.dispose();
    _knowledgeFlowController?.dispose();
    _thumbnailCache?.dispose();
    // 🧠 SEMANTIC TITLES: Release timers
    SemanticTitlesEngine.disposeSemanticTitleTimers();

    // 🚀 DISPOSE OPT: Remove listener FIRST to prevent _onLayerChanged
    // from firing during cleanup (cluster rebuilds on partial state).
    _layerController.removeListener(_onLayerChanged);

    // 🧠 CONSCIOUS ARCHITECTURE: Stop idle timer.
    _disposeConsciousArchitecture();

    // 🔔 SR NOTIFICATIONS: Cancel listener + debounce timer
    _disposeNotificationHandler();
    _srNotifDebounce?.cancel();

    // 🧭 Navigation
    _contentBoundsTracker.dispose();

    // 🖼️ MEMORY: Defer bulk ui.Image disposal to microtask.
    // Disposing 100+ native textures synchronously can jank the
    // navigation transition back from canvas (~2-5ms per 50 images).
    final imagesToDispose = _loadedImages.values.toList();
    _loadedImages.clear();
    if (imagesToDispose.isNotEmpty) {
      scheduleMicrotask(() {
        for (final image in imagesToDispose) {
          image.dispose();
        }
      });
    }
    ImagePainter.invalidateCache();
    _imageMemoryManager.clear();
    _imageStubManager.clear();

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

    // 🚀 DISPOSE OPT: Flush pending debounced save BEFORE cancelling timer.
    // Prevents data loss if user drew in the last 2s before closing.
    if (_saveDebounceTimer?.isActive == true) {
      _saveDebounceTimer!.cancel();
      unawaited(_performSave());
    } else {
      _saveDebounceTimer?.cancel();
    }
    _autoScrollTimer?.cancel();
    _imageEvictionTimer?.cancel();
    _metricsSubscription?.cancel();
    // _layerController.removeListener already called at top of dispose

    _eraserPulseController.dispose();
    _lassoRippleController?.dispose();
    _isDrawingNotifier.dispose();
    _isLoadingNotifier.dispose();
    _undoRedoVersion.dispose();

    _currentStrokeNotifier.dispose();
    _currentShapeNotifier.dispose();
    _currentEditingStrokeNotifier.dispose();
    _recordingDurationNotifier.dispose();
    _recordingAmplitudeNotifier.dispose();
    _isRecordingNotifier.dispose();
    // 🌊 LIQUID: Detach physics ticker before disposal
    _canvasController.detachTicker();
    _canvasController.removeListener(_onPdfZoomCheck);
    _canvasController.dispose();
    _playbackController?.dispose();

    EngineScope.current.drawingModule?.brushSettingsService.removeListener(
      _onBrushSettingsServiceUpdated,
    );

    DrawingPainter.clearTileCache();
    StrokeDataManager.clearCache();

    _toolSystemBridge?.dispose();
    _unifiedToolController?.dispose();
    _toolController.removeListener(_syncHoverState);
    _toolController.removeListener(_onToolChangeForPrediction);
    _toolController.dispose();

    // 🚀 PERSISTENT ISOLATE: Do NOT kill the isolate here — it's a singleton
    // and _performSave() (fire-and-forget above) may still be using it.
    // The isolate stays warm for the next canvas open, which is desirable.
    // SaveIsolateService.instance.dispose(); // 🐛 FIX: was racing with _performSave

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
            source: 'FlueraCanvasScreen.dispose.stopRecording',
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

    // 🌟 Radial expansion cleanup
    _disposeRadialExpansion();

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

