/// Fluera Engine — Looponia's professional 2D graphics engine.
///
/// A complete, production-ready engine for building canvas-based drawing
/// applications with Flutter. Features include:
///
/// - **Scene Graph**: Hierarchical node tree with typed nodes ([CanvasNode],
///   [LayerNode], [StrokeNode], [ShapeNode], [TextNode], [ImageNode])
/// - **Drawing**: Pressure-sensitive brush engine with ballpoint, pencil,
///   highlighter, and fountain pen brushes
/// - **History**: WAL-based delta tracking ([CanvasDeltaTracker]) with
///   undo/redo ([UndoRedoManager]) and timeline branching ([BranchingManager])
/// - **Rendering**: Tile-cached rendering with spatial indexing, viewport
///   culling, and LOD management
/// - **Collaboration**: Real-time sync via Firebase with cursor presence
/// - **Export**: Multi-format pipeline (PNG, SVG, timelapse)
/// - **Tools**: Extensible tool system with pen, eraser, lasso, shape,
///   text, image, ruler, and flood fill tools
///
/// ```dart
/// import 'package:fluera_engine/fluera_engine.dart';
/// ```
library;

// ────────────────────────── CORE ──────────────────────────

// Scene Graph
export 'src/core/scene_graph/canvas_node.dart';
export 'src/core/scene_graph/canvas_node_factory.dart';
export 'src/core/scene_graph/scene_graph.dart';
export 'src/core/scene_graph/node_visitor.dart';
export 'src/core/scene_graph/debug_info.dart';
export 'src/core/scene_graph/scene_graph_observer.dart';
export 'src/core/scene_graph/scene_graph_transaction.dart';
export 'src/core/scene_graph/node_id.dart';
export 'src/core/scene_graph/frozen_node_view.dart';
export 'src/core/scene_graph/read_only_scene_graph.dart';

// Module System
export 'src/core/modules/canvas_module.dart';
export 'src/core/modules/module_registry.dart';

// Nodes
export 'src/core/nodes/group_node.dart';
export 'src/core/nodes/layer_node.dart';
export 'src/core/nodes/shape_node.dart';
export 'src/core/nodes/stroke_node.dart';
export 'src/core/nodes/text_node.dart';
export 'src/core/nodes/image_node.dart';

// Vector

// NOTE: LaTeX and Tabular modules are available as separate add-on
// packages (fluera_engine_latex, fluera_engine_tabular) and are not
// included in the core SDK.

// Effects

// Core Models
export 'src/core/models/canvas_layer.dart';
export 'src/core/models/digital_text_element.dart';
export 'src/core/models/image_element.dart';
export 'src/core/models/recording_pin.dart';
export 'src/core/models/shape_type.dart';
export 'src/core/models/ocr_result.dart';

// Utilities
export 'src/core/engine_logger.dart';
export 'src/core/engine_scope.dart';
export 'src/core/engine_error.dart';
export 'src/core/engine_event.dart';
export 'src/core/engine_event_bus.dart';
export 'src/core/engine_telemetry.dart';
export 'src/systems/engine_theme.dart';
// Internal testing utilities (golden_snapshot, pixel_diff, visual_regression,
// performance_baseline) are not part of the public SDK API.
// NOTE: Marketplace (plugin signing, update manager) is available as a
// separate enterprise add-on.

// ────────────────────────── DRAWING ──────────────────────────

// Drawing Module
export 'src/drawing/drawing_module.dart';

// Brushes
export 'src/drawing/brushes/brush_engine.dart';
export 'src/drawing/brushes/brushes.dart';
export 'src/drawing/brushes/ballpoint_brush.dart';
export 'src/drawing/brushes/pencil_brush.dart';
export 'src/drawing/brushes/highlighter_brush.dart';

// Input
export 'src/drawing/input/drawing_input_handler.dart';
export 'src/drawing/input/raw_input_processor_120hz.dart';
export 'src/drawing/input/stylus_detector.dart';
export 'src/drawing/input/predicted_touch_service.dart';
export 'src/drawing/input/predicted_touch_debug_overlay.dart';
export 'src/drawing/input/path_pool.dart';
export 'src/drawing/input/stroke_point_pool.dart';

// Filters
export 'src/drawing/filters/one_euro_filter.dart';
export 'src/drawing/filters/advanced_one_euro_filter.dart';
export 'src/drawing/filters/dynamic_pressure_mapper.dart';
export 'src/drawing/filters/physics_ink_simulator.dart';
export 'src/drawing/filters/stroke_stabilizer.dart';
export 'src/drawing/filters/predictive_renderer.dart';
export 'src/drawing/filters/post_stroke_optimizer.dart';

// Drawing Models
export 'src/drawing/models/pro_drawing_point.dart';
export 'src/drawing/models/pro_brush_settings.dart';
export 'src/drawing/models/pro_brush_settings_dialog.dart';
export 'src/drawing/models/brush_preset.dart';
export 'src/drawing/models/pressure_curve.dart';

// Drawing Services
export 'src/drawing/services/brush_settings_service.dart';
export 'src/drawing/services/brush_preset_manager.dart';
export 'src/drawing/services/stroke_persistence_service.dart';

// ────────────────────────── TOOLS ──────────────────────────

// Tool System
export 'src/tools/base/tool_interface.dart';
export 'src/tools/base/tool_context.dart';
export 'src/tools/base/tool_bridge.dart';
export 'src/tools/base/tool_registry.dart';
export 'src/tools/base/base_tool.dart';

// Tools
export 'src/tools/eraser/eraser_tool.dart';
export 'src/tools/eraser/eraser_hit_tester.dart';
export 'src/tools/eraser/eraser_spatial_index.dart';
export 'src/tools/eraser/eraser_analytics.dart';
export 'src/tools/eraser/eraser_preset_manager.dart';


export 'src/tools/shape/unified_shape_tool.dart';
export 'src/tools/text/digital_text_tool.dart';

export 'src/tools/image/image_tool.dart';

export 'src/tools/pen/pen_tool.dart';
export 'src/tools/pen/pen_tool_painter.dart';
export 'src/tools/unified_tools.dart';
export 'src/tools/unified_tool_controller.dart';

// ────────────────────────── RENDERING ──────────────────────────

// Scene Graph Rendering
export 'src/rendering/scene_graph/scene_graph_renderer.dart';
export 'src/rendering/scene_graph/render_interceptor.dart';
export 'src/rendering/scene_graph/render_plan.dart';
export 'src/rendering/scene_graph/path_renderer.dart';
export 'src/rendering/scene_graph/rich_text_renderer.dart';
export 'src/rendering/scene_graph/render_batch.dart';

// NOTE: LaTeX/Tabular renderers and platform recognizers are available
// in their respective add-on packages.

// Canvas Painters
export 'src/rendering/canvas/drawing_painter.dart';
export 'src/rendering/canvas/current_stroke_painter.dart';
export 'src/rendering/canvas/background_painter.dart';
export 'src/rendering/canvas/shape_painter.dart';
export 'src/rendering/canvas/image_painter.dart';
export 'src/rendering/canvas/digital_text_painter.dart';
export 'src/rendering/canvas/origin_indicator_painter.dart';
export 'src/rendering/canvas/paper_grain_painter.dart';
export 'src/rendering/canvas/paper_pattern_painter.dart';
export 'src/rendering/canvas/pro_stroke_painter.dart';
export 'src/rendering/canvas/ruler_painter.dart';
export 'src/rendering/canvas/canvas_painters.dart';

// Shaders

// NOTE: GPU-accelerated pen renderers (dart:gpu pipeline) are available
// as a separate add-on when dart:gpu reaches Flutter stable.

// Optimization
export 'src/rendering/optimization/spatial_index.dart';
export 'src/rendering/optimization/viewport_culler.dart';
export 'src/rendering/optimization/stroke_optimizer.dart';
export 'src/rendering/optimization/optimized_path_builder.dart';
export 'src/rendering/optimization/paint_pool.dart';
export 'src/rendering/optimization/optimization.dart';
export 'src/rendering/optimization/dirty_region_tracker.dart';
export 'src/rendering/render_profiler.dart';
export 'src/rendering/canvas/incremental_paint_mixin.dart';

// ────────────────────────── TIME TRAVEL ──────────────────────────

// ────────────────────────── HISTORY ──────────────────────────
export 'src/history/command_history.dart';
export 'src/history/version_history.dart';

// ────────────────────────── UI WIRING ──────────────────────────
export 'src/history/undo_redo_manager.dart';
export 'src/history/canvas_delta_tracker.dart';
// NOTE: LaTeX/Tabular history commands are in their add-on packages.

// ────────────────────────── LAYERS ──────────────────────────
export 'src/layers/layer_controller.dart';
export 'src/layers/adapters/canvas_adapter.dart';
export 'src/layers/adapters/infinite_canvas_adapter.dart';
export 'src/layers/widgets/layer_panel.dart';
export 'src/layers/widgets/adjustment_panel_dialog.dart';

// ────────────────────────── COLLABORATION ──────────────────────────

// ────────────────────────── EXPORT ──────────────────────────
export 'src/export/export_pipeline.dart';
export 'src/export/export_preset.dart' hide ExportFormat, ExportConfig;
export 'src/export/saved_export_area.dart';
export 'src/export/binary_canvas_format.dart';
export 'src/export/raster_image_encoder.dart';
export 'src/export/raster_encoder_channel.dart';

// ────────────────────────── AUDIO ──────────────────────────
export 'src/audio/audio_module.dart';
export 'src/audio/native_audio_models.dart';
export 'src/audio/native_audio_player.dart';
export 'src/audio/native_audio_recorder.dart';
export 'src/audio/default_voice_recording_provider.dart';
export 'src/audio/platform_channels/audio_player_channel.dart';
export 'src/audio/platform_channels/audio_recorder_channel.dart';

// ────────────────────────── SYSTEMS ──────────────────────────
export 'src/systems/selection_manager.dart';
export 'src/systems/selection_query.dart';
export 'src/systems/dirty_tracker.dart';
export 'src/systems/spatial_index.dart';

// Dev Handoff / Inspect Mode

// Component Interactive States

// Semantic Tokens & Theme Switching

// Advanced Animation

// Advanced Typography

// Advanced Image Editing

// ────────────────────────── CANVAS (Screen) ──────────────────────────
export 'src/canvas/infinite_canvas_controller.dart';

// SRS (Pedagogical Engine — host app integration)

// Pedagogical Subsystems (P0 — 12-Step Methodology)

// P2P Collaboration (A4, Passo 7)
export 'src/canvas/infinite_canvas_gesture_detector.dart';

// Navigation & Orientation
export 'src/canvas/navigation/content_bounds_tracker.dart';
export 'src/canvas/navigation/camera_actions.dart';
export 'src/canvas/navigation/canvas_minimap.dart';
export 'src/canvas/navigation/content_radar_overlay.dart';
export 'src/canvas/navigation/zoom_level_indicator.dart';

// ────────────────────────── REFLOW ──────────────────────────
export 'src/reflow/content_cluster.dart';
export 'src/reflow/cluster_detector.dart';
export 'src/reflow/reflow_physics_engine.dart';

// ────────────────────────── DIALOGS ──────────────────────────
export 'src/dialogs/canvas_settings_dialog.dart';
export 'src/dialogs/brush_editor_sheet.dart';
export 'src/dialogs/digital_text_input_dialog.dart';
export 'src/dialogs/image_editor_dialog.dart';
export 'src/dialogs/paper_type_picker_sheet.dart';
export 'src/dialogs/pressure_curve_editor.dart';

// ────────────────────────── CONFIG ──────────────────────────
export 'src/config/adaptive_rendering_config.dart';
export 'src/config/multi_page_config.dart';
export 'src/config/color_manager.dart';
export 'src/config/split_panel_content.dart';
export 'src/config/advanced_split_layout.dart';

// ────────────────────────── UTILS ──────────────────────────
export 'src/utils/reduced_motion.dart';

// ────────────────────────── STORAGE ──────────────────────────
export 'src/storage/spatial_bookmark.dart';
export 'src/storage/pin_this_view.dart';
export 'src/storage/canvas_creation_options.dart';
export 'src/storage/sqlite_storage_adapter.dart';
export 'src/storage/recording_storage_service.dart';

// ────────────────────────── SERVICES ──────────────────────────
export 'src/services/adaptive_debouncer_service.dart';
export 'src/services/canvas_performance_monitor.dart';
export 'src/services/image_cache_service.dart';
export 'src/services/image_service.dart';
export 'src/services/phase2_service_stubs.dart';

// ────────────────────────── PLATFORM ──────────────────────────
export 'src/platform/native_display_plugin.dart';
export 'src/platform/display_capabilities_detector.dart';
export 'src/platform/display_link_service.dart';
export 'src/platform/native_vibration.dart';
export 'src/platform/native_notifications.dart';
export 'src/platform/native_stylus_input.dart';
export 'src/platform/native_performance_monitor.dart' hide PerformanceMetrics;


// ────────────────────────── AI ──────────────────────────
// Usage tracking: host apps implement AiUsageTracker to persist quota
// server-side. The engine ships a no-op default.

// Gemini proxy: when the app constructs EngineScope with a GeminiProxyConfig,
// all Gemini calls route through a Supabase Edge Function that holds the
// API key server-side — keeping the key out of the binary.
export 'src/ai/gemini_client.dart'
    show GeminiProxyConfig, GeminiProxyException,
         GeminiProxyQuotaExceededException;

// ────────────────────────── L10N ──────────────────────────

// NOTE: Internal testing utilities (brush_testing, brush_test_screen)
// are not part of the public SDK API. Import directly from
// 'package:fluera_engine/testing/brush_testing.dart' if needed.

// ────────────────────────── PLUGIN REGISTRANT ──────────────────────────
export 'fluera_engine_plugin.dart';
