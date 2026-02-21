import 'package:nebula_engine/src/core/scene_graph/node_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/scene_graph/frozen_node_view.dart';
import 'package:nebula_engine/src/core/nodes/layer_node.dart';
import 'package:nebula_engine/src/core/nodes/group_node.dart';

void main() {
  group('FrozenNodeView', () {
    test('creates deep frozen copy of node tree', () {
      final root = GroupNode(id: NodeId('root'), name: 'Root');
      final layer = LayerNode(id: NodeId('layer'), name: 'Layer');
      final leaf = GroupNode(id: NodeId('leaf'), name: 'Leaf');

      root.children.add(layer);
      layer.children.add(leaf);

      leaf.translate(10, 20);
      leaf.opacity = 0.5;

      final frozen = FrozenNodeView.from(root);

      // Core properties matched
      expect(frozen.id, NodeId('root'));
      expect(frozen.name, 'Root');
      expect(frozen.children.length, 1);

      final frozenLayer = frozen.children.first;
      expect(frozenLayer.id, NodeId('layer'));
      expect(frozenLayer.children.length, 1);

      final frozenLeaf = frozenLayer.children.first;
      expect(frozenLeaf.id, NodeId('leaf'));
      expect(frozenLeaf.opacity, 0.5);
      expect(frozenLeaf.transformStorage[12], 10.0);
      expect(frozenLeaf.transformStorage[13], 20.0);
    });

    test('mutating original does not affect frozen view', () {
      final leaf = GroupNode(id: NodeId('leaf'));
      leaf.opacity = 1.0;

      final frozen = FrozenNodeView.from(leaf);

      // Mutate original
      leaf.opacity = 0.0;
      leaf.translate(100, 100);
      leaf.name = 'New Name';

      // Frozen view should remain unchanged
      expect(frozen.opacity, 1.0);
      expect(frozen.transformStorage[12], 0.0); // original translation was 0
      expect(frozen.name, ''); // original name was empty
    });
  });
}
