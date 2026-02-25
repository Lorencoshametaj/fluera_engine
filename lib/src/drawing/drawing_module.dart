import '../core/modules/canvas_module.dart';
import '../core/nodes/stroke_node.dart';
import 'services/brush_settings_service.dart';
import 'services/stroke_persistence_service.dart';
import '../rendering/shaders/shader_brush_service.dart';
import '../tools/base/tool_interface.dart';
import '../tools/pen/pen_tool.dart';

// =============================================================================
// DRAWING MODULE
// =============================================================================

/// 🎨 Self-contained drawing module for the Nebula Engine canvas.
///
/// Encapsulates all freehand drawing functionality:
/// - [StrokeNode]: scene graph node for ink strokes
/// - [BrushEngine]: pressure-sensitive brush rendering (47KB)
/// - 7 brush types (ballpoint, pencil, fountain pen, highlighter, etc.)
/// - 14 GPU shader renderers (pencil, watercolor, charcoal, etc.)
/// - Input pipeline (1€ filter, stabilizer, predictive renderer)
/// - Fluid topology simulation
/// - Brush settings and persistence
///
/// ## Usage
///
/// ```dart
/// await EngineScope.current.moduleRegistry.register(DrawingModule());
///
/// final drawing = EngineScope.current.moduleRegistry.findModule<DrawingModule>()!;
/// print(drawing.brushSettingsService.currentBrush);
/// ```
class DrawingModule extends CanvasModule {
  // ---------------------------------------------------------------------------
  // Identity
  // ---------------------------------------------------------------------------

  @override
  String get moduleId => 'drawing';

  @override
  String get displayName => 'Drawing';

  // ---------------------------------------------------------------------------
  // Module-owned services
  // ---------------------------------------------------------------------------

  /// Brush configuration and notification.
  late final BrushSettingsService brushSettingsService;

  /// Stroke disk persistence.
  late final StrokePersistenceService strokePersistenceService;

  /// GPU shader brush rendering.
  late final ShaderBrushService shaderBrushService;

  // ---------------------------------------------------------------------------
  // CanvasModule contract
  // ---------------------------------------------------------------------------

  @override
  List<NodeDescriptor> get nodeDescriptors => [
    NodeDescriptor(
      nodeType: 'stroke',
      fromJson: StrokeNode.fromJson,
      displayName: 'Stroke',
    ),
  ];

  @override
  List<DrawingTool> createTools() => [PenTool()];

  @override
  bool get isInitialized => _initialized;
  bool _initialized = false;

  @override
  Future<void> initialize(ModuleContext context) async {
    if (_initialized) return;

    brushSettingsService = BrushSettingsService.create();
    strokePersistenceService = StrokePersistenceService.create();
    shaderBrushService = ShaderBrushService.create();

    _initialized = true;
  }

  @override
  Future<void> dispose() async {
    if (!_initialized) return;

    brushSettingsService.dispose();
    shaderBrushService.dispose();

    _initialized = false;
  }
}
