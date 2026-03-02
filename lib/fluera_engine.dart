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
export 'src/core/nodes/clip_group_node.dart';
export 'src/core/nodes/path_node.dart';
export 'src/core/nodes/rich_text_node.dart';
export 'src/core/nodes/symbol_system.dart';
export 'src/core/nodes/variant_property.dart';
export 'src/core/nodes/frame_node.dart';
export 'src/core/nodes/advanced_mask_node.dart';
export 'src/core/nodes/boolean_group_node.dart';
export 'src/core/nodes/pdf_page_node.dart';
export 'src/core/nodes/pdf_document_node.dart';
export 'src/core/nodes/section_node.dart';
export 'src/core/nodes/adjustment_layer_node.dart';
export 'src/core/models/pdf_layout_preset.dart';
export 'src/canvas/toolbar/pdf_contextual_toolbar.dart';

// Vector
export 'src/core/vector/vector_path.dart';
export 'src/core/vector/anchor_point.dart';
export 'src/core/vector/shape_presets.dart';
export 'src/core/vector/boolean_ops.dart';
export 'src/core/vector/vector_network.dart';
export 'src/core/nodes/vector_network_node.dart';
export 'src/core/vector/vector_network_svg.dart';
export 'src/core/vector/spatial_index.dart';
export 'src/core/vector/bezier_clipping.dart';
export 'src/core/vector/exact_boolean_ops.dart';
export 'src/core/vector/constraints.dart';
export 'src/rendering/scene_graph/network_lod.dart';

// NOTE: LaTeX and Tabular modules are available as separate add-on
// packages (fluera_engine_latex, fluera_engine_tabular) and are not
// included in the core SDK.

// Effects
export 'src/core/effects/node_effect.dart';
export 'src/core/effects/gradient_fill.dart';
export 'src/core/effects/mesh_gradient.dart';
export 'src/core/effects/shader_effect.dart';
export 'src/core/effects/shader_effect_wrapper.dart';
export 'src/core/effects/paint_stack.dart';
export 'src/core/scene_graph/paint_stack_mixin.dart';

// Core Models
export 'src/core/models/canvas_layer.dart';
export 'src/core/models/digital_text_element.dart';
export 'src/core/models/image_element.dart';
export 'src/core/models/recording_pin.dart';
export 'src/core/models/shape_type.dart';
export 'src/core/models/pdf_page_model.dart';
export 'src/core/models/pdf_document_model.dart';
export 'src/core/models/pdf_text_rect.dart';
export 'src/core/models/ocr_result.dart';
export 'src/tools/shape/shape_recognizer.dart';

// Utilities
export 'src/core/engine_logger.dart';
export 'src/core/engine_scope.dart';
export 'src/core/engine_error.dart';
export 'src/core/engine_event.dart';
export 'src/core/engine_event_bus.dart';
export 'src/core/engine_telemetry.dart';
export 'src/systems/engine_theme.dart';
export 'src/core/assets/asset_handle.dart';
export 'src/core/assets/asset_metadata.dart';
export 'src/core/assets/asset_validator.dart' hide ValidationSeverity;
export 'src/core/assets/asset_dependency_graph.dart';
export 'src/core/assets/asset_registry.dart';
export 'src/core/error_recovery_service.dart';
export 'src/core/audit/audit_entry.dart';
export 'src/core/audit/audit_log_service.dart';
export 'src/core/audit/audit_event_bridge.dart';
export 'src/core/audit/audit_exporter.dart';
export 'src/core/rbac/engine_permission.dart';
export 'src/core/rbac/permission_policy.dart';
export 'src/core/rbac/permission_service.dart';
export 'src/core/rbac/permission_interceptor.dart';
// Internal testing utilities (golden_snapshot, pixel_diff, visual_regression,
// performance_baseline) are not part of the public SDK API.
export 'src/core/layout/auto_layout_config.dart'
    hide
        LayoutDirection,
        MainAxisAlignment,
        CrossAxisAlignment,
        OverflowBehavior;
export 'src/core/layout/flex_layout_solver.dart';
export 'src/core/layout/grid_layout_solver.dart';
export 'src/core/layout/layout_template.dart';
export 'src/core/color/color_space_converter.dart';
export 'src/core/color/color_blindness_simulator.dart';
export 'src/core/color/soft_proof_engine.dart';
export 'src/core/color/color_palette_store.dart' hide ColorPalette;
export 'src/core/editing/adjustment_layer.dart';
export 'src/core/editing/smart_filter_stack.dart';
export 'src/core/editing/blend_mode_engine.dart';
export 'src/core/editing/mask_channel.dart' hide MaskType;
export 'src/core/analytics/usage_analytics.dart';
export 'src/core/analytics/metric_exporter.dart';
export 'src/core/analytics/dashboard_endpoint.dart' hide AlertSeverity;
export 'src/core/analytics/feature_flag_service.dart';
// NOTE: Marketplace (plugin signing, update manager) is available as a
// separate enterprise add-on.
export 'src/core/formats/format_registry.dart';
export 'src/core/formats/format_parser.dart';
export 'src/core/formats/batch_export_pipeline.dart' hide ExportResult;
export 'src/core/formats/format_converter.dart';
export 'src/core/schema_version.dart';
export 'src/core/scene_graph/scene_graph_integrity.dart';
export 'src/core/scene_graph/invalidation_graph.dart';
export 'src/core/scene_graph/node_constraint.dart';
export 'src/core/scene_graph/scene_graph_snapshot.dart';
export 'src/core/scene_graph/scene_graph_interceptor.dart';
export 'src/history/node_constraint_commands.dart';

// ────────────────────────── DRAWING ──────────────────────────

// Drawing Module
export 'src/drawing/drawing_module.dart';

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
export 'src/tools/section/section_tool.dart';
export 'src/tools/pdf/pdf_grid_controller.dart';
export 'src/tools/pdf/pdf_text_selection_controller.dart';
export 'src/tools/pdf/pdf_import_controller.dart';
export 'src/tools/pdf/pdf_search_controller.dart';
export 'src/tools/pdf/pdf_annotation_controller.dart';
export 'src/core/models/pdf_annotation_model.dart';
export 'src/canvas/toolbar/pdf_thumbnail_sidebar.dart';
export 'src/tools/pdf/pdf_module.dart';

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
export 'src/rendering/canvas/pdf_page_painter.dart';
export 'src/rendering/canvas/pdf_memory_budget.dart';

// Shaders
export 'src/rendering/shaders/shader_brush_service.dart';
export 'src/rendering/shaders/adjustment_shader_service.dart';
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

// NOTE: GPU-accelerated pen renderers (dart:gpu pipeline) are available
// as a separate add-on when dart:gpu reaches Flutter stable.

// Optimization
export 'src/rendering/optimization/spatial_index.dart';
export 'src/rendering/optimization/viewport_culler.dart';
export 'src/rendering/optimization/stroke_cache_manager.dart';
export 'src/rendering/optimization/stroke_data_manager.dart';
export 'src/rendering/optimization/disk_stroke_manager.dart';
export 'src/rendering/optimization/lod_manager.dart';
export 'src/rendering/optimization/frame_budget_manager.dart';
export 'src/rendering/optimization/stroke_optimizer.dart';
export 'src/rendering/optimization/optimized_path_builder.dart';
export 'src/rendering/optimization/paint_pool.dart';
export 'src/rendering/optimization/optimization.dart';
export 'src/rendering/optimization/dirty_region_tracker.dart';
export 'src/rendering/optimization/snapshot_cache_manager.dart';
export 'src/rendering/render_profiler.dart';
export 'src/rendering/optimization/memory_managed_cache.dart';
export 'src/rendering/optimization/memory_budget_controller.dart';
export 'src/rendering/optimization/memory_event.dart';
export 'src/rendering/optimization/occlusion_culler.dart';
export 'src/rendering/optimization/layer_picture_cache.dart';
export 'src/rendering/canvas/incremental_paint_mixin.dart';

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
export 'src/history/version_history.dart';
export 'src/core/layout/layout_grid.dart';
export 'src/core/transforms/transform_3d.dart';
export 'src/systems/preferred_values.dart';
export 'src/systems/component_set.dart';

// ────────────────────────── UI WIRING ──────────────────────────
export 'src/canvas/overlays/layout_grid_overlay.dart';
export 'src/canvas/overlays/design_comments_overlay.dart';
export 'src/canvas/widgets/version_history_panel.dart';
export 'src/canvas/toolbar/svg_import_action.dart';
export 'src/rendering/scene_graph/transform_3d_interceptor.dart';
export 'src/rendering/scene_graph/nested_instance_interceptor.dart';
export 'src/canvas/widgets/preferred_value_picker.dart';
export 'src/canvas/widgets/component_set_browser.dart';
export 'src/history/command_journal.dart';
export 'src/history/journal_recovery_middleware.dart';
export 'src/history/command_middlewares.dart';
export 'src/history/guide_commands.dart';
export 'src/history/vector_network_commands.dart';
export 'src/history/constraint_commands.dart';
export 'src/history/variant_commands.dart';
export 'src/history/variant_transactions.dart';
export 'src/history/undo_redo_manager.dart';
export 'src/history/canvas_delta_tracker.dart';
export 'src/history/models/canvas_branch.dart';
export 'src/history/models/branch_merge_result.dart';
export 'src/history/branching_manager.dart';
export 'src/history/background_checkpoint_service.dart';
export 'src/history/async_command.dart';
// NOTE: LaTeX/Tabular history commands are in their add-on packages.
export 'src/history/widgets/branch_explorer_sheet.dart';

// ────────────────────────── LAYERS ──────────────────────────
export 'src/layers/layer_controller.dart';
export 'src/layers/fluera_layer_controller.dart';
export 'src/layers/adapters/canvas_adapter.dart';
export 'src/layers/adapters/infinite_canvas_adapter.dart';
export 'src/layers/widgets/layer_panel.dart';
export 'src/layers/widgets/adjustment_panel_dialog.dart';

// ────────────────────────── COLLABORATION ──────────────────────────
export 'src/collaboration/widgets/canvas_presence_overlay.dart';
export 'src/collaboration/fluera_realtime_adapter.dart';
export 'src/collaboration/widgets/connected_users_strip.dart';
export 'src/collaboration/realtime_enterprise.dart' hide AuditAction;
export 'src/collaboration/conflict_resolution.dart';
export 'src/collaboration/widgets/conflict_resolution_dialog.dart';
export 'src/collaboration/design_comment.dart';
export 'src/collaboration/ready_to_use_adapters.dart';

// ────────────────────────── EXPORT ──────────────────────────
export 'src/export/export_pipeline.dart';
export 'src/export/export_preset.dart' hide ExportFormat, ExportConfig;
export 'src/export/saved_export_area.dart';
export 'src/export/timelapse_export_config.dart';
export 'src/export/binary_canvas_format.dart';
export 'src/export/pdf_annotation_exporter.dart';
export 'src/export/pdf_export_writer.dart';
export 'src/export/svg_importer.dart';
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
export 'src/systems/smart_snap_engine.dart';
export 'src/systems/layout_engine.dart';
export 'src/systems/animation_timeline.dart';
export 'src/systems/selection_manager.dart';
export 'src/systems/selection_query.dart';
export 'src/systems/dirty_tracker.dart';
export 'src/systems/spatial_index.dart';
export 'src/systems/style_system.dart';
export 'src/systems/prototype_flow.dart';
export 'src/systems/smart_animate_engine.dart';
export 'src/systems/smart_animate_snapshot.dart';
export 'src/systems/nested_instance_resolver.dart';
export 'src/systems/plugin_api.dart';
export 'src/systems/plugin_budget.dart';
export 'src/systems/sandboxed_event_stream.dart';
export 'src/systems/accessibility_tree.dart';
export 'src/systems/accessibility_bridge.dart';
export 'src/systems/animation_player.dart';
export 'src/systems/animation_commands.dart';
export 'src/systems/design_linter.dart';
export 'src/systems/responsive_breakpoint.dart';
export 'src/systems/responsive_variant.dart';
export 'src/systems/design_variables.dart';
export 'src/systems/variable_binding.dart';
export 'src/systems/variable_commands.dart';
export 'src/systems/variable_resolver.dart';
export 'src/systems/variable_scope.dart';
export 'src/systems/design_token_exporter.dart';

// Dev Handoff / Inspect Mode
export 'src/systems/dev_handoff/inspect_engine.dart';
export 'src/systems/dev_handoff/code_generator.dart';
export 'src/systems/dev_handoff/asset_manifest.dart';
export 'src/systems/dev_handoff/redline_overlay.dart';
export 'src/systems/dev_handoff/token_resolver.dart';

// Component Interactive States
export 'src/systems/component_state_machine.dart';
export 'src/systems/component_state_resolver.dart';

// Semantic Tokens & Theme Switching
export 'src/systems/semantic_token.dart';
export 'src/systems/theme_manager.dart';

// Advanced Animation
export 'src/systems/spring_simulation.dart';
export 'src/systems/path_motion.dart';
export 'src/systems/stagger_animation.dart';

// Advanced Typography
export 'src/systems/variable_font.dart';
export 'src/systems/opentype_features.dart';
export 'src/systems/text_auto_resize.dart';

// Advanced Image Editing
export 'src/systems/image_adjustment.dart';
export 'src/systems/image_fill_mode.dart';

// ────────────────────────── CANVAS (Screen) ──────────────────────────
export 'src/canvas/fluera_canvas_screen.dart';
export 'src/canvas/fluera_canvas_config.dart';
export 'src/canvas/infinite_canvas_controller.dart';
export 'src/canvas/infinite_canvas_gesture_detector.dart';
export 'src/canvas/liquid_canvas_config.dart';
export 'src/canvas/spring_animation_controller.dart';

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

// ────────────────────────── STORAGE ──────────────────────────
export 'src/storage/fluera_storage_adapter.dart';
export 'src/storage/fluera_cloud_adapter.dart';
export 'src/storage/sqlite_storage_adapter.dart';
export 'src/storage/recording_storage_service.dart';
export 'src/storage/fluera_canvas_gallery.dart';

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
export 'src/l10n/fluera_localizations.dart';

// NOTE: Internal testing utilities (brush_testing, brush_test_screen)
// are not part of the public SDK API. Import directly from
// 'package:fluera_engine/testing/brush_testing.dart' if needed.
