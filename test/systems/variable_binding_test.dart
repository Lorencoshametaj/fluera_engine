import 'package:nebula_engine/src/core/scene_graph/node_id.dart';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/nodes/group_node.dart';
import 'package:nebula_engine/src/core/nodes/layer_node.dart';
import 'package:nebula_engine/src/core/scene_graph/canvas_node.dart';
import 'package:nebula_engine/src/core/scene_graph/node_visitor.dart';
import 'package:nebula_engine/src/core/scene_graph/scene_graph.dart';
import 'package:nebula_engine/src/systems/variable_binding.dart';

/// Minimal concrete node for testing.
class _SimpleNode extends CanvasNode {
  _SimpleNode({required super.id, super.name = ''});

  @override
  Rect get localBounds => Rect.zero;

  @override
  Map<String, dynamic> toJson() => {'id': id, 'nodeType': 'simple'};

  @override
  R accept<R>(NodeVisitor<R> visitor) =>
      throw UnimplementedError('not needed for tests');
}

void main() {
  // =========================================================================
  // VariableBinding
  // =========================================================================

  group('VariableBinding', () {
    test('constructs with required fields', () {
      final b = VariableBinding(
        variableId: 'bg-color',
        nodeId: 'card-1',
        nodeProperty: 'fillColor',
      );
      expect(b.variableId, 'bg-color');
      expect(b.nodeId, 'card-1');
      expect(b.nodeProperty, 'fillColor');
    });

    test('equality by all fields', () {
      final a = VariableBinding(
        variableId: 'v1',
        nodeId: 'n1',
        nodeProperty: 'opacity',
      );
      final b = VariableBinding(
        variableId: 'v1',
        nodeId: 'n1',
        nodeProperty: 'opacity',
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('inequality when any field differs', () {
      final base = VariableBinding(
        variableId: 'v1',
        nodeId: 'n1',
        nodeProperty: 'opacity',
      );
      expect(
        base,
        isNot(
          equals(
            VariableBinding(
              variableId: 'v2',
              nodeId: 'n1',
              nodeProperty: 'opacity',
            ),
          ),
        ),
      );
      expect(
        base,
        isNot(
          equals(
            VariableBinding(
              variableId: 'v1',
              nodeId: 'n2',
              nodeProperty: 'opacity',
            ),
          ),
        ),
      );
      expect(
        base,
        isNot(
          equals(
            VariableBinding(
              variableId: 'v1',
              nodeId: 'n1',
              nodeProperty: 'isVisible',
            ),
          ),
        ),
      );
    });

    test('toJson / fromJson round-trip', () {
      final original = VariableBinding(
        variableId: 'color-1',
        nodeId: 'node-42',
        nodeProperty: 'fillColor',
      );
      final json = original.toJson();
      final restored = VariableBinding.fromJson(json);
      expect(restored, equals(original));
    });
  });

  // =========================================================================
  // VariableBindingRegistry
  // =========================================================================

  group('VariableBindingRegistry', () {
    late VariableBindingRegistry registry;

    setUp(() {
      registry = VariableBindingRegistry();
    });

    // ── Add / Count ──────────────────────────────────────────────────────

    test('addBinding increments count', () {
      expect(registry.bindingCount, 0);
      registry.addBinding(
        const VariableBinding(
          variableId: 'v1',
          nodeId: 'n1',
          nodeProperty: 'opacity',
        ),
      );
      expect(registry.bindingCount, 1);
    });

    test('addBinding skips duplicates', () {
      const binding = VariableBinding(
        variableId: 'v1',
        nodeId: 'n1',
        nodeProperty: 'opacity',
      );
      registry.addBinding(binding);
      registry.addBinding(binding);
      expect(registry.bindingCount, 1);
    });

    test('multiple bindings on same node', () {
      registry.addBinding(
        const VariableBinding(
          variableId: 'v1',
          nodeId: 'n1',
          nodeProperty: 'opacity',
        ),
      );
      registry.addBinding(
        const VariableBinding(
          variableId: 'v2',
          nodeId: 'n1',
          nodeProperty: 'fillColor',
        ),
      );
      expect(registry.bindingsForNode('n1').length, 2);
    });

    test('multiple nodes using same variable', () {
      registry.addBinding(
        const VariableBinding(
          variableId: 'v1',
          nodeId: 'n1',
          nodeProperty: 'opacity',
        ),
      );
      registry.addBinding(
        const VariableBinding(
          variableId: 'v1',
          nodeId: 'n2',
          nodeProperty: 'opacity',
        ),
      );
      expect(registry.bindingsForVariable('v1').length, 2);
    });

    // ── Remove ──────────────────────────────────────────────────────────

    test('removeBinding removes specific binding', () {
      const binding = VariableBinding(
        variableId: 'v1',
        nodeId: 'n1',
        nodeProperty: 'opacity',
      );
      registry.addBinding(binding);
      final removed = registry.removeBinding(binding);
      expect(removed, isTrue);
      expect(registry.bindingCount, 0);
    });

    test('removeBinding returns false for unknown binding', () {
      const binding = VariableBinding(
        variableId: 'unknown',
        nodeId: 'unknown',
        nodeProperty: 'unknown',
      );
      expect(registry.removeBinding(binding), isFalse);
    });

    test('removeBindingsForNode removes all node bindings', () {
      registry.addBinding(
        const VariableBinding(
          variableId: 'v1',
          nodeId: 'n1',
          nodeProperty: 'opacity',
        ),
      );
      registry.addBinding(
        const VariableBinding(
          variableId: 'v2',
          nodeId: 'n1',
          nodeProperty: 'fillColor',
        ),
      );
      registry.addBinding(
        const VariableBinding(
          variableId: 'v1',
          nodeId: 'n2',
          nodeProperty: 'opacity',
        ),
      );

      registry.removeBindingsForNode('n1');
      expect(registry.hasBindings('n1'), isFalse);
      expect(registry.bindingCount, 1); // only n2 binding remains
    });

    test('removeBindingsForVariable removes all variable bindings', () {
      registry.addBinding(
        const VariableBinding(
          variableId: 'v1',
          nodeId: 'n1',
          nodeProperty: 'opacity',
        ),
      );
      registry.addBinding(
        const VariableBinding(
          variableId: 'v1',
          nodeId: 'n2',
          nodeProperty: 'opacity',
        ),
      );
      registry.addBinding(
        const VariableBinding(
          variableId: 'v2',
          nodeId: 'n1',
          nodeProperty: 'fillColor',
        ),
      );

      registry.removeBindingsForVariable('v1');
      expect(registry.isVariableBound('v1'), isFalse);
      expect(registry.bindingCount, 1); // only v2 binding remains
    });

    // ── Queries ──────────────────────────────────────────────────────────

    test('hasBindings returns false for unknown node', () {
      expect(registry.hasBindings('nonexistent'), isFalse);
    });

    test('isVariableBound returns false for unknown variable', () {
      expect(registry.isVariableBound('nonexistent'), isFalse);
    });

    test('allBindings returns flat list', () {
      registry.addBinding(
        const VariableBinding(
          variableId: 'v1',
          nodeId: 'n1',
          nodeProperty: 'opacity',
        ),
      );
      registry.addBinding(
        const VariableBinding(
          variableId: 'v2',
          nodeId: 'n2',
          nodeProperty: 'isVisible',
        ),
      );
      expect(registry.allBindings.length, 2);
    });

    // ── Clear ────────────────────────────────────────────────────────────

    test('clear removes everything', () {
      registry.addBinding(
        const VariableBinding(
          variableId: 'v1',
          nodeId: 'n1',
          nodeProperty: 'opacity',
        ),
      );
      registry.clear();
      expect(registry.bindingCount, 0);
    });

    // ── Serialization ────────────────────────────────────────────────────

    test('toJson / loadFromJson round-trip', () {
      registry.addBinding(
        const VariableBinding(
          variableId: 'v1',
          nodeId: 'n1',
          nodeProperty: 'opacity',
        ),
      );
      registry.addBinding(
        const VariableBinding(
          variableId: 'v2',
          nodeId: 'n2',
          nodeProperty: 'fillColor',
        ),
      );

      final json = registry.toJson();
      final restored = VariableBindingRegistry();
      restored.loadFromJson(json);

      expect(restored.bindingCount, 2);
      expect(restored.hasBindings('n1'), isTrue);
      expect(restored.isVariableBound('v2'), isTrue);
    });
  });

  // =========================================================================
  // Copy/Paste (cloneBindingsForNode)
  // =========================================================================

  group('cloneBindingsForNode', () {
    test('clones all bindings to new node ID', () {
      final registry = VariableBindingRegistry();
      registry.addBinding(
        const VariableBinding(
          variableId: 'v1',
          nodeId: 'original',
          nodeProperty: 'opacity',
        ),
      );
      registry.addBinding(
        const VariableBinding(
          variableId: 'v2',
          nodeId: 'original',
          nodeProperty: 'fillColor',
        ),
      );

      final count = registry.cloneBindingsForNode('original', 'clone');

      expect(count, 2);
      expect(registry.hasBindings('clone'), isTrue);
      expect(registry.bindingsForNode('clone').length, 2);
      // Original still intact.
      expect(registry.hasBindings('original'), isTrue);
      // Total: 4 (2 original + 2 cloned).
      expect(registry.bindingCount, 4);
    });

    test('returns 0 for non-existent node', () {
      final registry = VariableBindingRegistry();
      expect(registry.cloneBindingsForNode('missing', 'new'), 0);
    });
  });

  // =========================================================================
  // Usage Tracking
  // =========================================================================

  group('Usage tracking', () {
    test('variableUsageReport returns counts', () {
      final registry = VariableBindingRegistry();
      registry.addBinding(
        const VariableBinding(
          variableId: 'v1',
          nodeId: 'n1',
          nodeProperty: 'opacity',
        ),
      );
      registry.addBinding(
        const VariableBinding(
          variableId: 'v1',
          nodeId: 'n2',
          nodeProperty: 'opacity',
        ),
      );
      registry.addBinding(
        const VariableBinding(
          variableId: 'v2',
          nodeId: 'n1',
          nodeProperty: 'fillColor',
        ),
      );

      final report = registry.variableUsageReport();
      expect(report['v1'], 2);
      expect(report['v2'], 1);
    });

    test('unboundVariables identifies orphans', () {
      final registry = VariableBindingRegistry();
      registry.addBinding(
        const VariableBinding(
          variableId: 'v1',
          nodeId: 'n1',
          nodeProperty: 'opacity',
        ),
      );

      final unbound = registry.unboundVariables(['v1', 'v2', 'v3']);
      expect(unbound, ['v2', 'v3']);
    });
  });

  // =========================================================================
  // Rename Variable
  // =========================================================================

  group('renameVariable', () {
    test('renames variable across all bindings', () {
      final registry = VariableBindingRegistry();
      registry.addBinding(
        const VariableBinding(
          variableId: 'old-id',
          nodeId: 'n1',
          nodeProperty: 'opacity',
        ),
      );
      registry.addBinding(
        const VariableBinding(
          variableId: 'old-id',
          nodeId: 'n2',
          nodeProperty: 'opacity',
        ),
      );

      registry.renameVariable('old-id', 'new-id');

      expect(registry.isVariableBound('old-id'), isFalse);
      expect(registry.isVariableBound('new-id'), isTrue);
      expect(registry.bindingsForVariable('new-id').length, 2);
      // Node bindings should also reflect the new ID.
      expect(registry.bindingsForNode('n1').first.variableId, 'new-id');
    });
  });

  // =========================================================================
  // VariableBindingObserver
  // =========================================================================

  group('VariableBindingObserver', () {
    test('removes bindings when node is removed', () {
      final registry = VariableBindingRegistry();
      registry.addBinding(
        const VariableBinding(
          variableId: 'v1',
          nodeId: 'n1',
          nodeProperty: 'opacity',
        ),
      );
      registry.addBinding(
        const VariableBinding(
          variableId: 'v2',
          nodeId: 'n1',
          nodeProperty: 'fillColor',
        ),
      );
      registry.addBinding(
        const VariableBinding(
          variableId: 'v1',
          nodeId: 'n2',
          nodeProperty: 'opacity',
        ),
      );

      final observer = VariableBindingObserver(registry);
      final node = _SimpleNode(id: NodeId('n1'));
      observer.onNodeRemoved(node, 'parent');

      expect(registry.hasBindings('n1'), isFalse);
      expect(registry.hasBindings('n2'), isTrue); // unaffected
      expect(registry.bindingCount, 1);
    });

    test('recursively removes bindings for group children', () {
      final registry = VariableBindingRegistry();
      registry.addBinding(
        const VariableBinding(
          variableId: 'v1',
          nodeId: 'group-1',
          nodeProperty: 'opacity',
        ),
      );
      registry.addBinding(
        const VariableBinding(
          variableId: 'v1',
          nodeId: 'child-1',
          nodeProperty: 'opacity',
        ),
      );
      registry.addBinding(
        const VariableBinding(
          variableId: 'v1',
          nodeId: 'grandchild-1',
          nodeProperty: 'opacity',
        ),
      );

      // Build group hierarchy.
      final grandchild = _SimpleNode(id: NodeId('grandchild-1'));
      final childGroup = GroupNode(id: NodeId('child-1'), name: 'Child');
      childGroup.add(grandchild);
      final parentGroup = GroupNode(id: NodeId('group-1'), name: 'Parent');
      parentGroup.add(childGroup);

      final observer = VariableBindingObserver(registry);
      observer.onNodeRemoved(parentGroup, 'root');

      expect(registry.bindingCount, 0);
    });

    test('SceneGraph auto-cleans bindings on node removal', () {
      final sg = SceneGraph();
      final layer = LayerNode(id: NodeId('layer-1'), name: 'L1');
      sg.addLayer(layer);

      // Add a node with bindings.
      final node = _SimpleNode(id: NodeId('test-node'));
      layer.add(node);
      sg.variableBindings.addBinding(
        const VariableBinding(
          variableId: 'v1',
          nodeId: 'test-node',
          nodeProperty: 'opacity',
        ),
      );

      expect(sg.variableBindings.hasBindings('test-node'), isTrue);

      // Remove the node — observer should auto-clean.
      layer.remove(node);
      sg.notifyNodeRemoved(node, layer.id);

      expect(sg.variableBindings.hasBindings('test-node'), isFalse);
      sg.dispose();
    });
  });
}
