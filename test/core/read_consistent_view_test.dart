import 'package:nebula_engine/src/core/scene_graph/node_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/scene_graph/read_only_scene_graph.dart';
import 'package:nebula_engine/src/core/scene_graph/scene_graph.dart';
import 'package:nebula_engine/src/core/nodes/layer_node.dart';
import 'package:nebula_engine/src/core/nodes/group_node.dart';

void main() {
  group('ReadConsistentView', () {
    test('allows reads when graph is unmodified (same epoch)', () {
      final graph = SceneGraph();
      final layer = LayerNode(id: NodeId('layer'));
      graph.addLayer(layer);

      final readView = graph.readView;

      // Should succeed since no mutations happened since readView creation
      expect(readView.layerCount, 1);
      expect(readView.layers.first.id, NodeId('layer'));
      expect(readView.findNodeById(NodeId('layer'))?.id, NodeId('layer'));
    });

    test('throws StateError if graph mutates and view becomes stale', () {
      final graph = SceneGraph();
      final layer = LayerNode(id: NodeId('layer'));
      graph.addLayer(layer);

      // Epoch is captured here
      final readView = graph.readView;
      expect(readView.layerCount, 1);

      // Mutate the graph -> version increments
      final layer2 = LayerNode(id: NodeId('layer2'));
      graph.addLayer(layer2);

      // Now reads on the old view should fail
      expect(() => readView.layerCount, throwsStateError);
      expect(() => readView.layers, throwsStateError);
      expect(() => readView.findNodeById(NodeId('layer')), throwsStateError);
      expect(() => readView.allNodes, throwsStateError);

      // However, creating a fresh view works
      final freshView = graph.readView;
      expect(freshView.layerCount, 2);
    });
  });
}
