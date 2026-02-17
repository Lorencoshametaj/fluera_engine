import '../core/scene_graph/canvas_node.dart';

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

  // ---- Read operations ----

  /// Get all nodes in the scene graph (requires readSceneGraph).
  List<CanvasNode> getAllNodes() {
    _requireCapability(PluginCapability.readSceneGraph);
    return _bridge.getAllNodes();
  }

  /// Find a node by ID (requires readSceneGraph).
  CanvasNode? findNode(String nodeId) {
    _requireCapability(PluginCapability.readSceneGraph);
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

  // ---- Guard ----

  void _requireCapability(PluginCapability cap) {
    if (!manifest.capabilities.contains(cap)) {
      throw PluginPermissionError(
        'Plugin "${manifest.name}" requires capability '
        '${cap.name} but it was not declared in the manifest.',
      );
    }
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
  List<CanvasNode> getAllNodes();
  CanvasNode? findNode(String nodeId);
  Set<String> getSelectedIds();
  void setNodeOpacity(String nodeId, double opacity);
  void setNodeVisibility(String nodeId, bool visible);
  void setNodeName(String nodeId, String name);
  void removeNode(String nodeId);
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
/// and provides the engine-side implementation of [_PluginBridge].
class PluginRegistry {
  final Map<String, _PluginEntry> _plugins = {};

  /// Install a plugin.
  void install(PluginManifest manifest, PluginEntryPoint entryPoint) {
    if (_plugins.containsKey(manifest.id)) {
      throw ArgumentError('Plugin "${manifest.id}" is already installed.');
    }
    _plugins[manifest.id] = _PluginEntry(
      manifest: manifest,
      entryPoint: entryPoint,
    );
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
    entry.entryPoint.onActivate(context);
  }

  /// Deactivate a plugin.
  void deactivate(String pluginId) {
    final entry = _plugins[pluginId];
    if (entry == null || !entry.isActive) return;

    entry.entryPoint.onDeactivate();
    entry.isActive = false;
    entry.context = null;
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
        entry.entryPoint.onSelectionChanged(selectedIds);
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
        entry.entryPoint.onSceneChanged();
      }
    }
  }

  /// Dispose all plugins.
  void dispose() {
    for (final id in _plugins.keys.toList()) {
      uninstall(id);
    }
  }
}

class _PluginEntry {
  final PluginManifest manifest;
  final PluginEntryPoint entryPoint;
  PluginContext? context;
  bool isActive = false;

  _PluginEntry({required this.manifest, required this.entryPoint});
}
