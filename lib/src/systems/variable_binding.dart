// =============================================================================
// 🔗 VARIABLE BINDING REGISTRY
//
// Maps design variables to specific node properties. When a variable's value
// changes (e.g. theme switch), all bound node properties are updated.
// =============================================================================

import '../core/scene_graph/canvas_node.dart';
import '../core/scene_graph/scene_graph_observer.dart';
import '../core/nodes/group_node.dart';

/// A binding between a [DesignVariable] and a specific property of a node.
///
/// ```dart
/// final binding = VariableBinding(
///   variableId: 'bg-primary',
///   nodeId: 'card-1',
///   nodeProperty: 'fillColor',
/// );
/// ```
///
/// DESIGN PRINCIPLES:
/// - Declarative: describes the relationship, not the resolution
/// - Serializable: persists with the document for re-resolution on load
/// - Lightweight: no references to nodes or variables, only IDs
class VariableBinding {
  /// ID of the [DesignVariable] this binding references.
  final String variableId;

  /// ID of the [CanvasNode] this binding targets.
  final String nodeId;

  /// The property on the target node to set (e.g. 'opacity', 'fillColor').
  final String nodeProperty;

  const VariableBinding({
    required this.variableId,
    required this.nodeId,
    required this.nodeProperty,
  });

  Map<String, dynamic> toJson() => {
    'variableId': variableId,
    'nodeId': nodeId,
    'nodeProperty': nodeProperty,
  };

  factory VariableBinding.fromJson(Map<String, dynamic> json) =>
      VariableBinding(
        variableId: json['variableId'] as String,
        nodeId: json['nodeId'] as String,
        nodeProperty: json['nodeProperty'] as String,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VariableBinding &&
          variableId == other.variableId &&
          nodeId == other.nodeId &&
          nodeProperty == other.nodeProperty;

  @override
  int get hashCode => Object.hash(variableId, nodeId, nodeProperty);

  @override
  String toString() => 'VariableBinding($variableId → $nodeId.$nodeProperty)';
}

// ---------------------------------------------------------------------------
// Binding Registry
// ---------------------------------------------------------------------------

/// Central registry managing all variable-to-node bindings.
///
/// Provides efficient lookups in both directions:
/// - By node ID: "which variables affect this node?"
/// - By variable ID: "which nodes use this variable?"
///
/// ```dart
/// final registry = VariableBindingRegistry();
/// registry.addBinding(VariableBinding(
///   variableId: 'bg-primary',
///   nodeId: 'card-1',
///   nodeProperty: 'fillColor',
/// ));
///
/// // Query bindings
/// final nodeBindings = registry.bindingsForNode('card-1');
/// final varBindings  = registry.bindingsForVariable('bg-primary');
/// ```
class VariableBindingRegistry {
  /// All bindings keyed by node ID.
  final Map<String, List<VariableBinding>> _byNode = {};

  /// All bindings keyed by variable ID.
  final Map<String, List<VariableBinding>> _byVariable = {};

  /// Total number of bindings.
  int get bindingCount {
    int count = 0;
    for (final list in _byNode.values) {
      count += list.length;
    }
    return count;
  }

  /// All bindings as a flat list.
  List<VariableBinding> get allBindings {
    final result = <VariableBinding>[];
    for (final list in _byNode.values) {
      result.addAll(list);
    }
    return result;
  }

  // ---- CRUD ----

  /// Add a binding. Skips if an identical binding already exists.
  void addBinding(VariableBinding binding) {
    final nodeList = _byNode.putIfAbsent(binding.nodeId, () => []);
    final varList = _byVariable.putIfAbsent(binding.variableId, () => []);

    // Prevent duplicates.
    if (nodeList.contains(binding)) return;

    nodeList.add(binding);
    varList.add(binding);
  }

  /// Remove a specific binding.
  bool removeBinding(VariableBinding binding) {
    final nodeList = _byNode[binding.nodeId];
    final varList = _byVariable[binding.variableId];
    if (nodeList == null || varList == null) return false;

    final removed = nodeList.remove(binding);
    varList.remove(binding);

    // Clean up empty lists.
    if (nodeList.isEmpty) _byNode.remove(binding.nodeId);
    if (varList.isEmpty) _byVariable.remove(binding.variableId);

    return removed;
  }

  /// Remove all bindings for a specific node.
  void removeBindingsForNode(String nodeId) {
    final bindings = _byNode.remove(nodeId);
    if (bindings == null) return;
    for (final b in bindings) {
      final varList = _byVariable[b.variableId];
      varList?.removeWhere((x) => x.nodeId == nodeId);
      if (varList != null && varList.isEmpty) {
        _byVariable.remove(b.variableId);
      }
    }
  }

  /// Remove all bindings for a specific variable.
  void removeBindingsForVariable(String variableId) {
    final bindings = _byVariable.remove(variableId);
    if (bindings == null) return;
    for (final b in bindings) {
      final nodeList = _byNode[b.nodeId];
      nodeList?.removeWhere((x) => x.variableId == variableId);
      if (nodeList != null && nodeList.isEmpty) {
        _byNode.remove(b.nodeId);
      }
    }
  }

  /// Rename a variable ID across all bindings.
  ///
  /// Used by [RenameVariableCommand] to atomically update all references
  /// when a variable is renamed.
  void renameVariable(String oldId, String newId) {
    final bindings = _byVariable.remove(oldId);
    if (bindings == null || bindings.isEmpty) return;

    // Create new bindings with the updated variable ID.
    final newBindings = <VariableBinding>[];
    for (final b in bindings) {
      final updated = VariableBinding(
        variableId: newId,
        nodeId: b.nodeId,
        nodeProperty: b.nodeProperty,
      );
      newBindings.add(updated);

      // Update in the node index.
      final nodeList = _byNode[b.nodeId];
      if (nodeList != null) {
        nodeList.remove(b);
        nodeList.add(updated);
      }
    }
    _byVariable[newId] = newBindings;
  }

  /// Clear all bindings.
  void clear() {
    _byNode.clear();
    _byVariable.clear();
  }

  // ---- Queries ----

  /// All bindings targeting a specific node.
  List<VariableBinding> bindingsForNode(String nodeId) =>
      List.unmodifiable(_byNode[nodeId] ?? const []);

  /// All bindings using a specific variable.
  List<VariableBinding> bindingsForVariable(String variableId) =>
      List.unmodifiable(_byVariable[variableId] ?? const []);

  /// Whether a node has any variable bindings.
  bool hasBindings(String nodeId) =>
      _byNode.containsKey(nodeId) && _byNode[nodeId]!.isNotEmpty;

  /// Whether a variable is bound to any nodes.
  bool isVariableBound(String variableId) =>
      _byVariable.containsKey(variableId) &&
      _byVariable[variableId]!.isNotEmpty;

  // ---- Copy/Paste Support ----

  /// Clone all bindings from [oldNodeId] to [newNodeId].
  ///
  /// Used when duplicating or pasting a node — the new node should retain
  /// the same variable bindings but with its own node ID.
  ///
  /// Returns the number of bindings cloned.
  int cloneBindingsForNode(String oldNodeId, String newNodeId) {
    final existing = _byNode[oldNodeId];
    if (existing == null || existing.isEmpty) return 0;
    int count = 0;
    for (final b in List<VariableBinding>.from(existing)) {
      final cloned = VariableBinding(
        variableId: b.variableId,
        nodeId: newNodeId,
        nodeProperty: b.nodeProperty,
      );
      addBinding(cloned);
      count++;
    }
    return count;
  }

  // ---- Usage Tracking ----

  /// Returns a usage report: how many nodes each variable is bound to.
  ///
  /// ```dart
  /// final report = registry.variableUsageReport();
  /// // {'bg-color': 5, 'opacity': 3, 'text-size': 0}
  /// ```
  Map<String, int> variableUsageReport() {
    final report = <String, int>{};
    for (final entry in _byVariable.entries) {
      report[entry.key] = entry.value.length;
    }
    return report;
  }

  /// Returns variable IDs that are not bound to any nodes (orphans).
  ///
  /// Useful for cleanup UI — shows variables that can be safely removed.
  List<String> unboundVariables(List<String> allVariableIds) {
    final unbound = <String>[];
    for (final id in allVariableIds) {
      if (!isVariableBound(id)) {
        unbound.add(id);
      }
    }
    return unbound;
  }

  // ---- Serialization ----

  Map<String, dynamic> toJson() => {
    'bindings': allBindings.map((b) => b.toJson()).toList(),
  };

  void loadFromJson(Map<String, dynamic> json) {
    clear();
    final bindingsJson = json['bindings'] as List<dynamic>? ?? [];
    for (final b in bindingsJson) {
      addBinding(VariableBinding.fromJson(b as Map<String, dynamic>));
    }
  }
}

// ---------------------------------------------------------------------------
// Auto-cleanup Observer
// ---------------------------------------------------------------------------

/// Observer that automatically removes variable bindings when nodes are
/// deleted from the scene graph.
///
/// Register this on the [SceneGraph] to prevent stale bindings from
/// accumulating when nodes are removed.
///
/// ```dart
/// final observer = VariableBindingObserver(registry);
/// sceneGraph.addObserver(observer);
/// ```
class VariableBindingObserver extends SceneGraphObserver {
  final VariableBindingRegistry _registry;

  VariableBindingObserver(this._registry);

  @override
  void onNodeRemoved(CanvasNode node, String parentId) {
    _registry.removeBindingsForNode(node.id);
    // Recursively clean up children for group nodes.
    if (node is GroupNode) {
      _removeChildBindings(node);
    }
  }

  void _removeChildBindings(GroupNode group) {
    for (final child in group.children) {
      _registry.removeBindingsForNode(child.id);
      if (child is GroupNode) {
        _removeChildBindings(child);
      }
    }
  }
}
