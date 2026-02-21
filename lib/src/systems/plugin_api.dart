import 'dart:async';
import 'dart:ui';
import '../core/scene_graph/canvas_node.dart';
import '../core/nodes/group_node.dart';
import '../core/scene_graph/frozen_node_view.dart';
import '../core/engine_event.dart';
import '../core/engine_event_bus.dart';
import '../history/command_history.dart';
import './plugin_budget.dart';
import './sandboxed_event_stream.dart';

/// Capability that a plugin can request access to.
enum PluginCapability {
  /// Read scene graph structure and node properties.
  readSceneGraph,

  /// Modify node properties (transform, opacity, effects, etc.).
  writeNodeProperties,

  /// Add/remove nodes from the scene graph.
  modifySceneGraph,

  /// Register custom node types.
  customNodes,

  /// Register custom tools (pointer interaction modes).
  customTools,

  /// Register custom renderers for node types.
  customRenderers,

  /// Register custom export formats.
  customExporters,

  /// Access the undo/redo command history.
  commandHistory,

  /// Access the selection manager.
  selection,

  /// Access the style/design token system.
  styleSystem,

  /// Read/write user preferences.
  preferences,

  /// Network access (for cloud integrations).
  network,

  /// Listen to and emit events on the centralized event bus.
  listenEvents,

  /// Execute undoable commands through CommandHistory.
  executeCommands,
}

/// Permission level for a plugin.
enum PluginPermission {
  /// Plugin can only read data.
  readOnly,

  /// Plugin can read and modify data.
  readWrite,

  /// Full access including structural changes.
  full,
}

/// Metadata describing a plugin.
class PluginManifest {
  /// Unique identifier (reverse-domain style: com.example.my-plugin).
  final String id;

  /// Human-readable name.
  final String name;

  /// Version string (semver).
  final String version;

  /// Author name or organization.
  final String author;

  /// Brief description of what the plugin does.
  final String description;

  /// Capabilities the plugin requires.
  final Set<PluginCapability> capabilities;

  /// Permission level.
  final PluginPermission permission;

  /// Minimum engine version required.
  final String? minimumEngineVersion;

  /// Plugin icon path (asset path).
  final String? iconPath;

  /// Resource limits for sandboxing.
  final PluginBudget budget;

  const PluginManifest({
    required this.id,
    required this.name,
    this.version = '1.0.0',
    this.author = '',
    this.description = '',
    this.capabilities = const {},
    this.permission = PluginPermission.readOnly,
    this.minimumEngineVersion,
    this.iconPath,
    this.budget = const PluginBudget(),
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'version': version,
    'author': author,
    'description': description,
    'capabilities': capabilities.map((c) => c.name).toList(),
    'permission': permission.name,
    if (minimumEngineVersion != null)
      'minimumEngineVersion': minimumEngineVersion,
    if (iconPath != null) 'iconPath': iconPath,
  };

  factory PluginManifest.fromJson(Map<String, dynamic> json) => PluginManifest(
    id: json['id'] as String,
    name: json['name'] as String,
    version: json['version'] as String? ?? '1.0.0',
    author: json['author'] as String? ?? '',
    description: json['description'] as String? ?? '',
    capabilities:
        (json['capabilities'] as List<dynamic>?)
            ?.map((c) => PluginCapability.values.byName(c as String))
            .toSet() ??
        {},
    permission: PluginPermission.values.byName(
      json['permission'] as String? ?? 'readOnly',
    ),
    minimumEngineVersion: json['minimumEngineVersion'] as String?,
    iconPath: json['iconPath'] as String?,
  );
}

/// Sandboxed context provided to plugins for interacting with the engine.
///
/// The context enforces capability-based access control: plugins can
/// only call methods matching their declared capabilities.
///
/// ```dart
/// class MyPlugin implements PluginEntryPoint {
///   @override
///   void onActivate(PluginContext ctx) {
///     final nodes = ctx.getAllNodes();
///     for (final node in nodes) {
///       if (node.opacity < 0.5) ctx.setNodeOpacity(node.id, 1.0);
///     }
///   }
/// }
/// ```
class PluginContext {
  final PluginManifest manifest;
  final PluginBridge _bridge;

  PluginContext({required this.manifest, required PluginBridge bridge})
    : _bridge = bridge;

  int _nodeLookups = 0;
  int _lastLookupReset = 0;

  void _checkLookupBudget() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastLookupReset > 1000) {
      _nodeLookups = 0;
      _lastLookupReset = now;
    }
    _nodeLookups++;
    if (_nodeLookups > manifest.budget.maxNodeLookupsPerFrame * 60) {
      throw PluginPermissionError(
        'Plugin "${manifest.name}" exceeded node lookup budget.',
      );
    }
  }

  // ---- Read operations ----

  /// Get all nodes in the scene graph (requires readSceneGraph).
  List<FrozenNodeView> getAllNodes() {
    _requireCapability(PluginCapability.readSceneGraph);
    _checkLookupBudget();
    return _bridge.getAllNodes();
  }

  /// Find a node by ID (requires readSceneGraph).
  FrozenNodeView? findNode(String nodeId) {
    _requireCapability(PluginCapability.readSceneGraph);
    _checkLookupBudget();
    return _bridge.findNode(nodeId);
  }

  /// Get currently selected node IDs (requires selection).
  Set<String> getSelectedIds() {
    _requireCapability(PluginCapability.selection);
    return _bridge.getSelectedIds();
  }

  // ---- Write operations ----

  /// Set a node's opacity (requires writeNodeProperties).
  void setNodeOpacity(String nodeId, double opacity) {
    _requireCapability(PluginCapability.writeNodeProperties);
    _bridge.setNodeOpacity(nodeId, opacity);
  }

  /// Set a node's visibility (requires writeNodeProperties).
  void setNodeVisibility(String nodeId, bool visible) {
    _requireCapability(PluginCapability.writeNodeProperties);
    _bridge.setNodeVisibility(nodeId, visible);
  }

  /// Set a node's name (requires writeNodeProperties).
  void setNodeName(String nodeId, String name) {
    _requireCapability(PluginCapability.writeNodeProperties);
    _bridge.setNodeName(nodeId, name);
  }

  // ---- Structural operations ----

  /// Remove a node from the scene graph (requires modifySceneGraph).
  void removeNode(String nodeId) {
    _requireCapability(PluginCapability.modifySceneGraph);
    _bridge.removeNode(nodeId);
  }

  // ---- Command execution ----

  /// Active transaction, if any.
  CommandTransaction? _activeTransaction;

  /// Execute an undoable command (requires executeCommands).
  ///
  /// The command is pushed to the engine's [CommandHistory] and can be
  /// undone/redone by the user.
  bool executeCommand(Command command) {
    _requireCapability(PluginCapability.executeCommands);
    return _bridge.commandHistory.execute(command);
  }

  /// Begin a command transaction (requires executeCommands).
  ///
  /// All commands added via [addToTransaction] will be grouped as a single
  /// undo entry when [commitTransaction] is called.
  void beginTransaction(String label) {
    _requireCapability(PluginCapability.executeCommands);
    if (_activeTransaction != null && !_activeTransaction!.isFinished) {
      throw StateError(
        'Plugin "${manifest.name}" already has an active transaction.',
      );
    }
    _activeTransaction = CommandTransaction(label: label);
  }

  /// Add a command to the active transaction (requires executeCommands).
  void addToTransaction(Command command) {
    _requireCapability(PluginCapability.executeCommands);
    if (_activeTransaction == null || _activeTransaction!.isFinished) {
      throw StateError('No active transaction.');
    }
    _activeTransaction!.add(command);
  }

  /// Commit the active transaction as a single undo entry.
  void commitTransaction() {
    _requireCapability(PluginCapability.executeCommands);
    if (_activeTransaction == null || _activeTransaction!.isFinished) {
      throw StateError('No active transaction to commit.');
    }
    final composite = _activeTransaction!.commit();
    _bridge.commandHistory.pushWithoutExecute(composite);
    _activeTransaction = null;
  }

  /// Roll back the active transaction, undoing all commands.
  void rollbackTransaction() {
    _requireCapability(PluginCapability.executeCommands);
    if (_activeTransaction == null || _activeTransaction!.isFinished) {
      throw StateError('No active transaction to roll back.');
    }
    _activeTransaction!.rollback();
    _activeTransaction = null;
  }

  // ---- Scene graph mutation ----

  /// Add a node to a parent group (requires modifySceneGraph).
  void addNode(GroupNode parent, CanvasNode child) {
    _requireCapability(PluginCapability.modifySceneGraph);
    _bridge.addNode(parent, child);
  }

  /// Deep-clone a node by ID (requires modifySceneGraph).
  CanvasNode? cloneNode(String nodeId) {
    _requireCapability(PluginCapability.modifySceneGraph);
    return _bridge.cloneNode(nodeId);
  }

  /// Set a node's position (requires writeNodeProperties).
  void setNodePosition(String nodeId, Offset position) {
    _requireCapability(PluginCapability.writeNodeProperties);
    _bridge.setNodePosition(nodeId, position);
  }

  /// Apply a function to multiple nodes as a single undo step
  /// (requires writeNodeProperties + executeCommands).
  void batchModify(
    List<String> nodeIds,
    void Function(CanvasNode node) modifier, {
    String label = 'Batch modify',
  }) {
    _requireCapability(PluginCapability.writeNodeProperties);
    _requireCapability(PluginCapability.executeCommands);
    _bridge.batchModify(nodeIds, modifier, label: label);
  }

  // ---- Guard ----

  void _requireCapability(PluginCapability cap) {
    if (!manifest.capabilities.contains(cap)) {
      throw PluginPermissionError(
        'Plugin "${manifest.name}" requires capability '
        '${cap.name} but it was not declared in the manifest.',
      );
    }
  }

  // ---- Event Bus ----

  /// Subscribe to typed engine events (requires listenEvents).
  ///
  /// Returns a stream of events matching [T]. The subscription is
  /// **not** automatically cancelled — plugins should cancel it
  /// in [PluginEntryPoint.onDeactivate].
  ///
  /// ```dart
  /// final sub = ctx.onEvent<NodeAddedEngineEvent>().listen((e) {
  ///   print('Node ${e.node.id} added');
  /// });
  /// ```
  Stream<T> onEvent<T extends EngineEvent>() {
    _requireCapability(PluginCapability.listenEvents);
    return SandboxedEventStream<T>(
      _bridge.eventBus.on<T>(),
      maxEventsPerSecond: manifest.budget.maxEventSubscriptions * 10,
    );
  }

  /// Emit a custom plugin event (requires listenEvents).
  ///
  /// ```dart
  /// ctx.emitEvent('my-event', data: {'key': 'value'});
  /// ```
  void emitEvent(String name, {Map<String, dynamic>? data}) {
    _requireCapability(PluginCapability.listenEvents);
    _bridge.eventBus.emit(
      CustomPluginEngineEvent(pluginId: manifest.id, name: name, data: data),
    );
  }
}

/// Error thrown when a plugin tries to use a capability it hasn't declared.
class PluginPermissionError extends Error {
  final String message;
  PluginPermissionError(this.message);

  @override
  String toString() => 'PluginPermissionError: $message';
}

/// Internal bridge between plugins and the engine.
///
/// This is the actual implementation that the engine provides.
/// Plugins interact through [PluginContext] which wraps this with
/// capability guards.
abstract class PluginBridge {
  List<FrozenNodeView> getAllNodes();
  FrozenNodeView? findNode(String nodeId);
  Set<String> getSelectedIds();
  void setNodeOpacity(String nodeId, double opacity);
  void setNodeVisibility(String nodeId, bool visible);
  void setNodeName(String nodeId, String name);
  void removeNode(String nodeId);

  /// Access to the centralized event bus.
  EngineEventBus get eventBus;

  /// Access to the command history for undoable operations.
  CommandHistory get commandHistory;

  /// Add a child node to a parent group.
  void addNode(GroupNode parent, CanvasNode child);

  /// Deep-clone a node by ID.
  CanvasNode? cloneNode(String nodeId);

  /// Find the parent group of a node.
  GroupNode? findParent(String nodeId);

  /// Set a node's position.
  void setNodePosition(String nodeId, Offset position);

  /// Apply a modifier to multiple nodes as a single undo step.
  void batchModify(
    List<String> nodeIds,
    void Function(CanvasNode node) modifier, {
    String label = 'Batch modify',
  });
}

/// Interface that plugins implement.
abstract class PluginEntryPoint {
  /// Called when the plugin is activated.
  void onActivate(PluginContext context);

  /// Called when the plugin is deactivated.
  void onDeactivate();

  /// Called on each selection change (if plugin has selection capability).
  void onSelectionChanged(Set<String> selectedIds) {}

  /// Called when the scene graph changes (if plugin has readSceneGraph).
  void onSceneChanged() {}
}

/// Registry managing all installed plugins.
///
/// Handles plugin lifecycle (install → activate → deactivate → uninstall)
/// and provides the engine-side implementation of [PluginBridge].
///
/// Enterprise features:
/// - **Lifecycle events**: emits [PluginLifecycleEvent] on install/activate/deactivate
/// - **Hot-reload**: [reloadPlugin] deactivates, re-installs, and re-activates
/// - **Version check**: validates plugin against minimum engine version
class PluginRegistry {
  final Map<String, _PluginEntry> _plugins = {};

  /// Optional event bus for lifecycle event emission.
  final EngineEventBus? _eventBus;

  /// Current engine version (semver string).
  final String engineVersion;

  PluginRegistry({EngineEventBus? eventBus, this.engineVersion = '1.0.0'})
    : _eventBus = eventBus;

  /// Install a plugin.
  ///
  /// Validates version compatibility if the manifest specifies
  /// [PluginManifest.minimumEngineVersion].
  void install(PluginManifest manifest, PluginEntryPoint entryPoint) {
    if (_plugins.containsKey(manifest.id)) {
      throw ArgumentError('Plugin "${manifest.id}" is already installed.');
    }
    // Version check.
    if (manifest.minimumEngineVersion != null &&
        !_isVersionCompatible(manifest.minimumEngineVersion!)) {
      throw ArgumentError(
        'Plugin "${manifest.id}" requires engine >= '
        '${manifest.minimumEngineVersion}, current: $engineVersion',
      );
    }
    _plugins[manifest.id] = _PluginEntry(
      manifest: manifest,
      entryPoint: entryPoint,
    );
    _emitLifecycle(manifest.id, PluginLifecycleAction.installed);
  }

  /// Uninstall a plugin (deactivates first if active).
  void uninstall(String pluginId) {
    final entry = _plugins[pluginId];
    if (entry == null) return;
    if (entry.isActive) deactivate(pluginId);
    _plugins.remove(pluginId);
  }

  /// Activate a plugin.
  void activate(String pluginId, PluginBridge bridge) {
    final entry = _plugins[pluginId];
    if (entry == null) {
      throw ArgumentError('Plugin "$pluginId" is not installed.');
    }
    if (entry.isActive) return;

    final context = PluginContext(manifest: entry.manifest, bridge: bridge);
    entry.context = context;
    entry.isActive = true;

    runZonedGuarded(
      () {
        entry.entryPoint.onActivate(context);
      },
      (error, stackTrace) {
        print('Plugin $pluginId crashed during activation: $error');
        deactivate(pluginId);
      },
    );

    if (entry.isActive) {
      _emitLifecycle(pluginId, PluginLifecycleAction.activated);
    }
  }

  /// Deactivate a plugin.
  void deactivate(String pluginId) {
    final entry = _plugins[pluginId];
    if (entry == null || !entry.isActive) return;

    entry.isActive = false; // Mark true first to avoid loops

    runZonedGuarded(
      () {
        entry.entryPoint.onDeactivate();
      },
      (error, stackTrace) {
        print('Plugin $pluginId crashed during deactivation: $error');
      },
    );

    entry.context = null;
    _emitLifecycle(pluginId, PluginLifecycleAction.deactivated);
  }

  /// Get all installed plugin manifests.
  List<PluginManifest> get installedPlugins =>
      _plugins.values.map((e) => e.manifest).toList();

  /// Get all active plugin IDs.
  List<String> get activePluginIds =>
      _plugins.entries
          .where((e) => e.value.isActive)
          .map((e) => e.key)
          .toList();

  /// Check if a plugin is active.
  bool isActive(String pluginId) => _plugins[pluginId]?.isActive ?? false;

  /// Notify all active plugins of a selection change.
  void notifySelectionChanged(Set<String> selectedIds) {
    for (final entry in _plugins.values) {
      if (entry.isActive &&
          entry.manifest.capabilities.contains(PluginCapability.selection)) {
        runZonedGuarded(
          () {
            entry.entryPoint.onSelectionChanged(selectedIds);
          },
          (error, stackTrace) {
            print(
              'Plugin ${entry.manifest.id} crashed dynamically (selection): $error',
            );
            deactivate(entry.manifest.id);
          },
        );
      }
    }
  }

  /// Notify all active plugins of a scene graph change.
  void notifySceneChanged() {
    for (final entry in _plugins.values) {
      if (entry.isActive &&
          entry.manifest.capabilities.contains(
            PluginCapability.readSceneGraph,
          )) {
        runZonedGuarded(
          () {
            entry.entryPoint.onSceneChanged();
          },
          (error, stackTrace) {
            print(
              'Plugin ${entry.manifest.id} crashed dynamically (scene): $error',
            );
            deactivate(entry.manifest.id);
          },
        );
      }
    }
  }

  /// Dispose all plugins.
  void dispose() {
    for (final id in _plugins.keys.toList()) {
      uninstall(id);
    }
  }

  // ---------------------------------------------------------------------------
  // Hot-reload
  // ---------------------------------------------------------------------------

  /// Hot-reload a plugin: deactivate → uninstall → install → activate.
  ///
  /// The [bridge] is required to re-activate. The new entry point replaces
  /// the old one.
  void reloadPlugin(
    String pluginId,
    PluginEntryPoint newEntryPoint,
    PluginBridge bridge,
  ) {
    final entry = _plugins[pluginId];
    if (entry == null) {
      throw ArgumentError('Plugin "$pluginId" is not installed.');
    }
    final manifest = entry.manifest;
    final wasActive = entry.isActive;

    if (wasActive) deactivate(pluginId);
    uninstall(pluginId);
    install(manifest, newEntryPoint);
    if (wasActive) activate(pluginId, bridge);
  }

  // ---------------------------------------------------------------------------
  // Version compatibility
  // ---------------------------------------------------------------------------

  /// Simple semver major.minor check.
  bool _isVersionCompatible(String minimumVersion) {
    final current = _parseSemver(engineVersion);
    final required = _parseSemver(minimumVersion);
    if (current[0] != required[0]) return current[0] > required[0];
    if (current[1] != required[1]) return current[1] >= required[1];
    return current[2] >= required[2];
  }

  static List<int> _parseSemver(String version) {
    final parts = version.split('.');
    return [
      int.tryParse(parts.isNotEmpty ? parts[0] : '0') ?? 0,
      int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
      int.tryParse(parts.length > 2 ? parts[2] : '0') ?? 0,
    ];
  }

  // ---------------------------------------------------------------------------
  // Lifecycle events
  // ---------------------------------------------------------------------------

  void _emitLifecycle(String pluginId, PluginLifecycleAction action) {
    _eventBus?.emit(PluginLifecycleEvent(pluginId: pluginId, action: action));
  }
}

class _PluginEntry {
  final PluginManifest manifest;
  final PluginEntryPoint entryPoint;
  PluginContext? context;
  bool isActive = false;

  _PluginEntry({required this.manifest, required this.entryPoint});
}

// =============================================================================
// Plugin Lifecycle Events
// =============================================================================

/// Action type for plugin lifecycle events.
enum PluginLifecycleAction { installed, activated, deactivated, uninstalled }

/// Emitted on the event bus when a plugin lifecycle state changes.
class PluginLifecycleEvent extends EngineEvent {
  final String pluginId;
  final PluginLifecycleAction action;

  PluginLifecycleEvent({required this.pluginId, required this.action})
    : super(source: 'PluginRegistry', domain: EventDomain.custom);
}
