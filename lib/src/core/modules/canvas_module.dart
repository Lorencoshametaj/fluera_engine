import '../engine_event_bus.dart';
import '../../history/command_history.dart';
import '../engine_scope.dart';
import '../scene_graph/canvas_node.dart';
import '../../tools/base/tool_interface.dart';

// =============================================================================
// MODULE CONTRACT
// =============================================================================

/// Contract that every canvas module must implement.
///
/// A module is a self-contained domain (drawing, spreadsheet, LaTeX, PDF, etc.)
/// that registers its node types, tools, and commands into the shared canvas
/// platform. The canvas provides the infrastructure (scene graph, undo/redo,
/// event bus, rendering) and each module contributes its specific capabilities.
///
/// ## Lifecycle
///
/// 1. Module is registered via [ModuleRegistry.register]
/// 2. [initialize] is called with a [ModuleContext] providing limited access
///    to core services
/// 3. Module registers its nodes, tools, and commands
/// 4. Module responds to events via [ModuleContext.eventBus]
/// 5. [dispose] is called during scope teardown
///
/// ## Example
///
/// ```dart
/// class DrawingModule extends CanvasModule {
///   @override String get moduleId => 'drawing';
///   @override String get displayName => 'Drawing';
///
///   @override
///   List<NodeDescriptor> get nodeDescriptors => [
///     NodeDescriptor(
///       nodeType: 'stroke',
///       fromJson: StrokeNode.fromJson,
///       displayName: 'Stroke',
///     ),
///   ];
///
///   @override
///   List<DrawingTool> createTools() => [PenTool(), EraserTool()];
///
///   @override
///   Future<void> initialize(ModuleContext context) async {
///     // Set up module-internal services
///   }
/// }
/// ```
abstract class CanvasModule {
  /// Unique identifier for this module (e.g. 'drawing', 'tabular', 'latex').
  ///
  /// Used for registration, serialization, and diagnostics. Must be stable
  /// across versions — changing it breaks deserialization of existing files.
  String get moduleId;

  /// Human-readable name for UI and diagnostics.
  String get displayName;

  /// The [CanvasNode] types this module registers in the scene graph.
  ///
  /// Each descriptor provides the `nodeType` string and a `fromJson` factory,
  /// allowing the [CanvasNodeFactory] to deserialize nodes without hardcoded
  /// switch cases.
  List<NodeDescriptor> get nodeDescriptors;

  /// Create the tools this module contributes to the toolbar.
  ///
  /// Called once during initialization. The returned tools are registered
  /// in the [ToolRegistry].
  List<DrawingTool> createTools() => const [];

  /// Initialize the module with access to core services.
  ///
  /// Called once after registration. Use this to set up module-internal
  /// services, subscribe to events, and perform any async setup.
  Future<void> initialize(ModuleContext context);

  /// Whether this module has been initialized.
  bool get isInitialized;

  /// Dispose all resources owned by this module.
  ///
  /// Called during [EngineScope.dispose] in reverse-registration order.
  Future<void> dispose();
}

// =============================================================================
// MODULE CONTEXT
// =============================================================================

/// Limited access to core engine services, provided to modules during
/// initialization.
///
/// Modules communicate with each other ONLY through the [eventBus].
/// Direct access to other modules is intentionally not provided to maintain
/// clean boundaries.
class ModuleContext {
  /// For cross-module communication.
  final EngineEventBus eventBus;

  /// For undo/redo integration.
  final CommandHistory commandHistory;

  /// Full scope reference for edge-case access to shared infrastructure
  /// (memory budget, telemetry, etc.).
  ///
  /// Prefer using specific fields above; use [scope] only for services
  /// not yet surfaced as dedicated properties.
  final EngineScope scope;

  const ModuleContext({
    required this.eventBus,
    required this.commandHistory,
    required this.scope,
  });
}

// =============================================================================
// NODE DESCRIPTOR
// =============================================================================

/// Describes a [CanvasNode] type that a module contributes to the scene graph.
///
/// Used by [CanvasNodeFactory] to deserialize nodes dynamically, removing the
/// need for a hardcoded switch on `nodeType` strings.
class NodeDescriptor {
  /// The `nodeType` string used in serialized JSON (e.g., 'stroke', 'tabular').
  ///
  /// Must match what [CanvasNode.toJson] emits for this node type.
  final String nodeType;

  /// Factory function to deserialize a node from JSON.
  final CanvasNode Function(Map<String, dynamic> json) fromJson;

  /// Human-readable name for UI (e.g., in layer panels or node inspectors).
  final String displayName;

  /// Optional icon for UI representation.
  final String? iconAsset;

  const NodeDescriptor({
    required this.nodeType,
    required this.fromJson,
    required this.displayName,
    this.iconAsset,
  });

  @override
  String toString() => 'NodeDescriptor($nodeType)';
}
