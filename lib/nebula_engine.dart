/// Nebula Engine — Looponia's professional 2D graphics engine.
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
/// import 'package:nebula_engine/nebula_engine.dart';
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

// Nodes
export 'src/core/nodes/group_node.dart';
export 'src/core/nodes/layer_node.dart';
export 'src/core/nodes/shape_node.dart';
export 'src/core/nodes/stroke_node.dart';
export 'src/core/nodes/text_node.dart';
export 'src/core/nodes/image_node.dart';
export 'src/core/nodes/clip_group_node.dart';
export 'src/core/nodes/path_node.dart';
export 'src/core/nodes/rich_text_node.dart';
export 'src/core/nodes/symbol_system.dart';
export 'src/core/nodes/frame_node.dart';
export 'src/core/nodes/advanced_mask_node.dart';
export 'src/core/nodes/boolean_group_node.dart';
export 'src/core/nodes/pdf_page_node.dart';
export 'src/core/nodes/pdf_document_node.dart';
export 'src/core/models/pdf_layout_preset.dart';
export 'src/canvas/toolbar/pdf_contextual_toolbar.dart';

// Vector
export 'src/core/vector/vector_path.dart';
export 'src/core/vector/anchor_point.dart';
export 'src/core/vector/shape_presets.dart';
export 'src/core/vector/boolean_ops.dart';

// Effects
export 'src/core/effects/node_effect.dart';
export 'src/core/effects/gradient_fill.dart';
export 'src/core/effects/mesh_gradient.dart';
export 'src/core/effects/shader_effect.dart';
export 'src/core/effects/shader_effect_wrapper.dart';

// Core Models
export 'src/core/models/canvas_layer.dart';
export 'src/core/models/digital_text_element.dart';
export 'src/core/models/image_element.dart';
export 'src/core/models/shape_type.dart';
export 'src/core/models/pdf_page_model.dart';
export 'src/core/models/pdf_document_model.dart';
export 'src/core/models/pdf_text_rect.dart';
export 'src/tools/shape/shape_recognizer.dart';

// Utilities
export 'src/core/engine_logger.dart';
export 'src/core/engine_scope.dart';

// ────────────────────────── DRAWING ──────────────────────────

// Brushes
export 'src/drawing/brushes/brush_engine.dart';
export 'src/drawing/brushes/brushes.dart';
export 'src/drawing/brushes/ballpoint_brush.dart';
export 'src/drawing/brushes/pencil_brush.dart';
export 'src/drawing/brushes/highlighter_brush.dart';
export 'src/drawing/brushes/fountain_pen_brush.dart';
export 'src/drawing/brushes/fountain_pen_buffers.dart';
export 'src/drawing/brushes/fountain_pen_path_builder.dart';
export 'src/drawing/brushes/brush_texture.dart';

// Input
export 'src/drawing/input/drawing_input_handler.dart';
export 'src/drawing/input/raw_input_processor_120hz.dart';
export 'src/drawing/input/stylus_detector.dart';
export 'src/drawing/input/predicted_touch_service.dart';
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

export 'src/tools/lasso/lasso_tool.dart';
export 'src/tools/lasso/lasso_path_painter.dart';
export 'src/tools/lasso/lasso_selection_overlay.dart';

export 'src/tools/shape/unified_shape_tool.dart';
export 'src/tools/text/digital_text_tool.dart';

export 'src/tools/image/image_tool.dart';

export 'src/tools/ruler/ruler_guide_system.dart';
export 'src/tools/flood_fill/flood_fill_tool.dart';
export 'src/tools/pen/pen_tool.dart';
export 'src/tools/pen/pen_tool_painter.dart';
export 'src/tools/unified_tools.dart';
export 'src/tools/unified_tool_controller.dart';
export 'src/tools/pdf/pdf_grid_controller.dart';
export 'src/tools/pdf/pdf_text_selection_controller.dart';
export 'src/tools/pdf/pdf_import_controller.dart';

// ────────────────────────── RENDERING ──────────────────────────

// Scene Graph Rendering
export 'src/rendering/scene_graph/scene_graph_renderer.dart';
export 'src/rendering/scene_graph/path_renderer.dart';
export 'src/rendering/scene_graph/rich_text_renderer.dart';

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
export 'src/rendering/canvas/pdf_page_painter.dart';
export 'src/rendering/canvas/pdf_memory_budget.dart';

// Shaders
export 'src/rendering/shaders/shader_brush_service.dart';
export 'src/rendering/shaders/shader_pencil_renderer.dart';
export 'src/rendering/shaders/shader_fountain_pen_renderer.dart';
export 'src/rendering/shaders/shader_stamp_renderer.dart';
export 'src/rendering/shaders/shader_texture_renderer.dart';
export 'src/rendering/shaders/shader_watercolor_renderer.dart';
export 'src/rendering/shaders/shader_marker_renderer.dart';
export 'src/rendering/shaders/shader_charcoal_renderer.dart';
export 'src/rendering/shaders/shader_oil_paint_renderer.dart';
export 'src/rendering/shaders/shader_spray_paint_renderer.dart';
export 'src/rendering/shaders/shader_neon_glow_renderer.dart';
export 'src/rendering/shaders/shader_ink_wash_renderer.dart';
export 'src/rendering/shaders/render_isolate_pool.dart';

// Optimization
export 'src/rendering/optimization/spatial_index.dart';
export 'src/rendering/optimization/tile_cache_manager.dart';
export 'src/rendering/optimization/viewport_culler.dart';
export 'src/rendering/optimization/stroke_cache_manager.dart';
export 'src/rendering/optimization/stroke_data_manager.dart';
export 'src/rendering/optimization/disk_stroke_manager.dart';
export 'src/rendering/optimization/lod_manager.dart';
export 'src/rendering/optimization/frame_budget_manager.dart';
export 'src/rendering/optimization/advanced_tile_optimizer.dart';
export 'src/rendering/optimization/stroke_optimizer.dart';
export 'src/rendering/optimization/optimized_path_builder.dart';
export 'src/rendering/optimization/paint_pool.dart';
export 'src/rendering/optimization/optimization.dart';
export 'src/rendering/optimization/dirty_region_tracker.dart';
export 'src/rendering/optimization/snapshot_cache_manager.dart';

// ────────────────────────── TIME TRAVEL ──────────────────────────
export 'src/time_travel/models/time_travel_session.dart';
export 'src/time_travel/models/synchronized_recording.dart';
export 'src/time_travel/services/time_travel_playback_engine.dart';
export 'src/time_travel/services/time_travel_recorder.dart';
export 'src/time_travel/services/time_travel_compressor.dart';
export 'src/time_travel/widgets/time_travel_timeline_widget.dart';
export 'src/time_travel/widgets/time_travel_lasso_overlay.dart';
export 'src/time_travel/controllers/synchronized_playback_controller.dart';
export 'src/time_travel/widgets/synchronized_playback_overlay.dart';

// ────────────────────────── HISTORY ──────────────────────────
export 'src/history/command_history.dart';
export 'src/history/undo_redo_manager.dart';
export 'src/history/canvas_delta_tracker.dart';
export 'src/history/models/canvas_branch.dart';
export 'src/history/branching_manager.dart';
export 'src/history/background_checkpoint_service.dart';
export 'src/history/widgets/branch_explorer_sheet.dart';

// ────────────────────────── LAYERS ──────────────────────────
export 'src/layers/layer_controller.dart';
export 'src/layers/nebula_layer_controller.dart';
export 'src/layers/adapters/canvas_adapter.dart';
export 'src/layers/adapters/infinite_canvas_adapter.dart';
export 'src/layers/widgets/layer_panel.dart';

// ────────────────────────── COLLABORATION ──────────────────────────
export 'src/collaboration/canvas_realtime_sync_manager.dart';
export 'src/collaboration/sync_state_provider.dart';
export 'src/collaboration/nebula_sync_interfaces.dart';
export 'src/collaboration/widgets/canvas_presence_overlay.dart';

// ────────────────────────── EXPORT ──────────────────────────
export 'src/export/export_pipeline.dart';
export 'src/export/export_preset.dart' hide ExportFormat, ExportConfig;
export 'src/export/saved_export_area.dart';
export 'src/export/timelapse_export_config.dart';
export 'src/export/binary_canvas_format.dart';
export 'src/export/pdf_annotation_exporter.dart';

// ────────────────────────── AUDIO ──────────────────────────
export 'src/audio/native_audio_models.dart';
export 'src/audio/native_audio_player.dart';
export 'src/audio/native_audio_recorder.dart';
export 'src/audio/default_voice_recording_provider.dart';
export 'src/audio/platform_channels/audio_player_channel.dart';
export 'src/audio/platform_channels/audio_recorder_channel.dart';

// ────────────────────────── SYSTEMS ──────────────────────────
export 'src/systems/smart_snap_engine.dart';
export 'src/systems/layout_engine.dart';
export 'src/systems/animation_timeline.dart';
export 'src/systems/selection_manager.dart';
export 'src/systems/dirty_tracker.dart';
export 'src/systems/spatial_index.dart';
export 'src/systems/style_system.dart';
export 'src/systems/prototype_flow.dart';
export 'src/systems/plugin_api.dart';
export 'src/systems/accessibility_tree.dart';
export 'src/systems/responsive_breakpoint.dart';
export 'src/systems/responsive_variant.dart';
export 'src/systems/design_variables.dart';
export 'src/systems/variable_binding.dart';
export 'src/systems/variable_commands.dart';
export 'src/systems/variable_resolver.dart';
export 'src/systems/variable_scope.dart';
export 'src/systems/design_token_exporter.dart';

// ────────────────────────── CANVAS (Screen) ──────────────────────────
export 'src/canvas/nebula_canvas_screen.dart';
export 'src/canvas/nebula_canvas_config.dart';
export 'src/canvas/infinite_canvas_controller.dart';
export 'src/canvas/infinite_canvas_gesture_detector.dart';
export 'src/canvas/liquid_canvas_config.dart';
export 'src/canvas/spring_animation_controller.dart';

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

// ────────────────────────── STORAGE ──────────────────────────
export 'src/storage/nebula_storage_adapter.dart';
export 'src/storage/sqlite_storage_adapter.dart';
export 'src/storage/recording_storage_service.dart';
export 'src/storage/nebula_canvas_gallery.dart';

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
export 'src/platform/native_stylus_input.dart';
export 'src/platform/native_performance_monitor.dart' hide PerformanceMetrics;
export 'src/platform/native_pdf_provider.dart';

// ────────────────────────── L10N ──────────────────────────
export 'src/l10n/nebula_localizations.dart';

// ────────────────────────── TESTING ──────────────────────────
export 'testing/brush_testing.dart';
export 'testing/brush_test_screen.dart';
