import 'package:flutter/foundation.dart';
import './canvas_module.dart';
import '../scene_graph/canvas_node.dart';
import '../engine_event_bus.dart';
import '../../history/command_history.dart';
import '../../tools/base/tool_registry.dart';

// =============================================================================
// MODULE REGISTRY
// =============================================================================

/// Central registry that manages the lifecycle of all [CanvasModule]s.
///
/// The registry is owned by [EngineScope] and coordinates:
/// - Module registration and initialization
/// - Node type registration (for [CanvasNodeFactory])
/// - Tool registration (for [ToolRegistry])
/// - Ordered disposal
///
/// ## Usage
///
/// ```dart
/// final registry = EngineScope.current.moduleRegistry;
///
/// // Register modules at startup
/// await registry.register(DrawingModule());
/// await registry.register(TabularModule());
/// await registry.register(LaTeXModule());
///
/// // Deserialize a node from any module
/// final node = registry.createNodeFromJson(json);
///
/// // Query registered capabilities
/// print(registry.registeredNodeTypes); // ['stroke', 'tabular', 'latex']
/// print(registry.diagnostics);
/// ```
class ModuleRegistry extends ChangeNotifier {
  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  final Map<String, CanvasModule> _modules = {};
  final Map<String, NodeDescriptor> _nodeDescriptors = {};
  final List<String> _initOrder = [];

  // ---------------------------------------------------------------------------
  // Dependencies (injected from EngineScope)
  // ---------------------------------------------------------------------------

  final EngineEventBus _eventBus;
  final CommandHistory _commandHistory;
  final dynamic _scope; // EngineScope, typed as dynamic to avoid circular dep

  ModuleRegistry({
    required EngineEventBus eventBus,
    required CommandHistory commandHistory,
    required dynamic scope,
  }) : _eventBus = eventBus,
       _commandHistory = commandHistory,
       _scope = scope;

  // ---------------------------------------------------------------------------
  // Registration
  // ---------------------------------------------------------------------------

  /// Register and initialize a [CanvasModule].
  ///
  /// The module's [NodeDescriptor]s are indexed for dynamic deserialization,
  /// and its tools are registered in the [ToolRegistry].
  ///
  /// Throws [StateError] if a module with the same [CanvasModule.moduleId]
  /// is already registered.
  Future<void> register(
    CanvasModule module, {
    ToolRegistry? toolRegistry,
  }) async {
    final id = module.moduleId;

    if (_modules.containsKey(id)) {
      throw StateError('Module "$id" is already registered.');
    }

    // Index node descriptors — check for collisions
    for (final descriptor in module.nodeDescriptors) {
      if (_nodeDescriptors.containsKey(descriptor.nodeType)) {
        final existing = _nodeDescriptors[descriptor.nodeType]!;
        throw StateError(
          'Node type "${descriptor.nodeType}" is already registered '
          'by another module. Cannot register from "$id".',
        );
      }
      _nodeDescriptors[descriptor.nodeType] = descriptor;
    }

    // Register tools
    final tools = module.createTools();
    if (tools.isNotEmpty && toolRegistry != null) {
      toolRegistry.registerAll(tools);
    }

    // Initialize module
    final context = ModuleContext(
      eventBus: _eventBus,
      commandHistory: _commandHistory,
      scope: _scope,
    );
    await module.initialize(context);

    // Track
    _modules[id] = module;
    _initOrder.add(id);
    notifyListeners();
  }

  /// Unregister a module by its ID.
  ///
  /// Disposes the module, removes its node descriptors and tools.
  Future<void> unregister(String moduleId) async {
    final module = _modules[moduleId];
    if (module == null) return;

    // Remove node descriptors
    for (final descriptor in module.nodeDescriptors) {
      _nodeDescriptors.remove(descriptor.nodeType);
    }

    // Dispose module
    await module.dispose();

    _modules.remove(moduleId);
    _initOrder.remove(moduleId);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Node Deserialization
  // ---------------------------------------------------------------------------

  /// Create a [CanvasNode] from JSON using registered [NodeDescriptor]s.
  ///
  /// Returns `null` if no descriptor is registered for the `nodeType`.
  /// This allows the caller to fall back to the legacy hardcoded factory.
  CanvasNode? createNodeFromJson(Map<String, dynamic> json) {
    final nodeType = json['nodeType'] as String?;
    if (nodeType == null) return null;

    final descriptor = _nodeDescriptors[nodeType];
    if (descriptor == null) return null;

    return descriptor.fromJson(json);
  }

  /// Whether a node type is registered by any module.
  bool hasNodeType(String nodeType) => _nodeDescriptors.containsKey(nodeType);

  /// All registered node type strings.
  Set<String> get registeredNodeTypes => _nodeDescriptors.keys.toSet();

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  /// Get a module by its ID.
  CanvasModule? getModule(String moduleId) => _modules[moduleId];

  /// Get a module by type.
  T? findModule<T extends CanvasModule>() {
    for (final module in _modules.values) {
      if (module is T) return module;
    }
    return null;
  }

  /// Whether a module is registered.
  bool isRegistered(String moduleId) => _modules.containsKey(moduleId);

  /// All registered modules.
  Iterable<CanvasModule> get modules => _modules.values;

  /// Number of registered modules.
  int get moduleCount => _modules.length;

  // ---------------------------------------------------------------------------
  // Diagnostics
  // ---------------------------------------------------------------------------

  /// Debug summary of all registered modules and their capabilities.
  String get diagnostics {
    final buf = StringBuffer('ModuleRegistry: ${_modules.length} modules\n');
    for (final id in _initOrder) {
      final m = _modules[id]!;
      buf.writeln(
        '  [$id] ${m.displayName} '
        '(${m.nodeDescriptors.length} nodes, '
        '${m.createTools().length} tools, '
        'init=${m.isInitialized})',
      );
    }
    return buf.toString();
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Dispose all modules in reverse-registration order.
  Future<void> disposeAll() async {
    for (final id in _initOrder.reversed.toList()) {
      final module = _modules[id];
      if (module != null) {
        try {
          await module.dispose();
        } catch (e) {
          // Log but don't throw — ensure all modules get disposed
          debugPrint('Error disposing module "$id": $e');
        }
      }
    }
    _modules.clear();
    _nodeDescriptors.clear();
    _initOrder.clear();
  }

  @override
  void dispose() {
    // Synchronous dispose — modules should have been disposed via disposeAll()
    _modules.clear();
    _nodeDescriptors.clear();
    _initOrder.clear();
    super.dispose();
  }
}
