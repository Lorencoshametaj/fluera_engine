/// 🪆 NESTED INSTANCE RESOLVER — Override cascading for instances-within-instances.
///
/// When a component instance contains other component instances (nesting),
/// this resolver walks the tree and recursively resolves each nested instance,
/// applying override cascading: parent overrides > instance overrides > defaults.
///
/// ```dart
/// final resolver = NestedInstanceResolver(
///   library: symbolLibrary,
///   stateResolver: componentStateResolver,
/// );
/// final resolved = resolver.resolveDeep(instance);
/// ```
library;

import '../core/scene_graph/canvas_node.dart';
import '../core/scene_graph/node_id.dart';
import '../core/nodes/group_node.dart';
import '../core/nodes/symbol_system.dart';
import 'component_state_machine.dart';
import 'component_state_resolver.dart';

// =============================================================================
// NESTED INSTANCE RESOLVER
// =============================================================================

/// Resolves nested component instances with override cascading.
///
/// A component can contain other instances. For example, a "Card" component
/// may contain a "Button" instance inside it. When the Card is placed on
/// the canvas, both the Card and the Button need to be resolved, with
/// overrides cascading from parent to child.
///
/// Override priority (highest first):
/// 1. Parent instance overrides targeting nested path (e.g., `"button.label.text"`)
/// 2. Nested instance's own overrides
/// 3. Nested definition's defaults
class NestedInstanceResolver {
  /// The symbol registry containing all definitions.
  final SymbolRegistry registry;

  /// Optional state resolver for interactive states in nested instances.
  final ComponentStateResolver? stateResolver;

  /// Maximum nesting depth to prevent infinite recursion.
  final int maxDepth;

  const NestedInstanceResolver({
    required this.registry,
    this.stateResolver,
    this.maxDepth = 8,
  });

  /// Resolve a [SymbolInstanceNode] and all nested instances within it.
  ///
  /// Returns a fully resolved [GroupNode] tree with no unresolved instances.
  /// Returns null if the definition is not found.
  GroupNode? resolveDeep(
    SymbolInstanceNode instance, {
    Map<String, dynamic> parentOverrides = const {},
    int currentDepth = 0,
  }) {
    if (currentDepth >= maxDepth) return null;

    final definition = registry.lookup(instance.symbolDefinitionId);
    if (definition == null) return null;

    // Resolve the top-level content with variant selections.
    final content = definition.resolveContent(instance.variantSelections);

    // Merge overrides: parent overrides targeting this instance + own overrides.
    final effectiveOverrides = <String, dynamic>{
      ...instance.overrides,
      ...parentOverrides,
    };

    // Apply overrides to the resolved content.
    _applyOverrides(content, effectiveOverrides);

    // Walk children and resolve any nested SymbolInstanceNodes.
    _resolveNestedInstances(content, effectiveOverrides, currentDepth);

    return content;
  }

  /// Recursively walk the tree and resolve any nested [SymbolInstanceNode]s.
  void _resolveNestedInstances(
    GroupNode parent,
    Map<String, dynamic> parentOverrides,
    int currentDepth,
  ) {
    final children = parent.children.toList();
    for (int i = 0; i < children.length; i++) {
      final child = children[i];

      if (child is SymbolInstanceNode) {
        // Extract overrides targeting this nested instance.
        final nestedOverrides = _extractNestedOverrides(
          parentOverrides,
          child.name,
        );

        // Resolve the nested instance.
        final resolved = resolveDeep(
          child,
          parentOverrides: nestedOverrides,
          currentDepth: currentDepth + 1,
        );

        if (resolved != null) {
          // Replace the instance node with the resolved content.
          parent.remove(child);
          parent.insertAt(i, resolved);
        }
      } else if (child is GroupNode) {
        // Walk deeper into non-instance groups.
        _resolveNestedInstances(child, parentOverrides, currentDepth);
      }
    }
  }

  /// Extract overrides that target a nested instance by name prefix.
  ///
  /// For example, if parentOverrides has `"button.label.text": "Save"` and
  /// the nested instance name is `"button"`, this extracts
  /// `{"label.text": "Save"}`.
  Map<String, dynamic> _extractNestedOverrides(
    Map<String, dynamic> parentOverrides,
    String instanceName,
  ) {
    final prefix = '$instanceName.';
    final result = <String, dynamic>{};

    for (final entry in parentOverrides.entries) {
      if (entry.key.startsWith(prefix)) {
        result[entry.key.substring(prefix.length)] = entry.value;
      }
    }

    return result;
  }

  /// Apply property overrides to a resolved [GroupNode] tree.
  ///
  /// Override keys use dot-paths: `"children.0.fillColor"`, `"label.text"`, etc.
  void _applyOverrides(GroupNode node, Map<String, dynamic> overrides) {
    for (final entry in overrides.entries) {
      _applyOverride(node, entry.key, entry.value);
    }
  }

  /// Apply a single override to a node tree by dot-path.
  void _applyOverride(CanvasNode node, String path, dynamic value) {
    final parts = path.split('.');
    if (parts.length == 1) {
      // Apply directly to this node.
      _setProperty(node, parts[0], value);
      return;
    }

    // Navigate into children.
    if (node is GroupNode) {
      final childKey = parts[0];
      final remainingPath = parts.sublist(1).join('.');

      // Try by index.
      final index = int.tryParse(childKey);
      if (index != null && index < node.children.length) {
        _applyOverride(node.children[index], remainingPath, value);
        return;
      }

      // Try by name.
      for (final child in node.children) {
        if (child.name == childKey) {
          _applyOverride(child, remainingPath, value);
          return;
        }
      }
    }
  }

  /// Set a property on a node.
  void _setProperty(CanvasNode node, String property, dynamic value) {
    switch (property) {
      case 'opacity':
        if (value is double) node.opacity = value;
      case 'isVisible':
        if (value is bool) node.isVisible = value;
      case 'name':
        if (value is String) node.name = value;
    }
  }

  // ---------------------------------------------------------------------------
  // Inspection helpers
  // ---------------------------------------------------------------------------

  /// Count nested instance depth in a resolved tree.
  static int countNestingDepth(CanvasNode node, {int current = 0}) {
    if (node is SymbolInstanceNode) {
      return current + 1;
    }
    if (node is GroupNode) {
      int maxChild = current;
      for (final child in node.children) {
        final childDepth = countNestingDepth(child, current: current);
        if (childDepth > maxChild) maxChild = childDepth;
      }
      return maxChild;
    }
    return current;
  }

  /// Find all unresolved instances in a tree (ones that couldn't be resolved).
  static List<SymbolInstanceNode> findUnresolved(CanvasNode node) {
    final result = <SymbolInstanceNode>[];
    if (node is SymbolInstanceNode) {
      result.add(node);
    }
    if (node is GroupNode) {
      for (final child in node.children) {
        result.addAll(findUnresolved(child));
      }
    }
    return result;
  }
}
