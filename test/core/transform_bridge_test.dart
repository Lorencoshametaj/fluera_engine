import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/scene_graph/canvas_node.dart';
import 'package:fluera_engine/src/core/scene_graph/node_id.dart';
import 'package:fluera_engine/src/core/scene_graph/transform_bridge.dart';
import 'package:fluera_engine/src/core/nodes/layer_node.dart';

void main() {
  group('TransformBridge', () {
    test('can be implemented and receives notifications', () {
      final bridge = _TestBridge();
      final node = LayerNode(id: NodeId('l1'));

      // Directly call the bridge method
      bridge.onNodeTransformInvalidated(node);

      expect(bridge.invalidatedNodes, [node]);
    });

    test('receives separate notifications for different nodes', () {
      final bridge = _TestBridge();
      final n1 = LayerNode(id: NodeId('l1'));
      final n2 = LayerNode(id: NodeId('l2'));

      bridge.onNodeTransformInvalidated(n1);
      bridge.onNodeTransformInvalidated(n2);

      expect(bridge.invalidatedNodes.length, 2);
      expect(bridge.invalidatedNodes[0], same(n1));
      expect(bridge.invalidatedNodes[1], same(n2));
    });
  });
}

/// Test implementation that records which nodes were invalidated.
class _TestBridge implements TransformBridge {
  final List<CanvasNode> invalidatedNodes = [];

  @override
  void onNodeTransformInvalidated(CanvasNode node) {
    invalidatedNodes.add(node);
  }
}
