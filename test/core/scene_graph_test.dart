import 'package:nebula_engine/src/core/scene_graph/node_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/scene_graph/scene_graph.dart';
import 'package:nebula_engine/src/core/nodes/layer_node.dart';

import '../helpers/test_helpers.dart';

void main() {
  group('SceneGraph layer management', () {
    test('starts empty', () {
      final sg = SceneGraph();
      expect(sg.layers, isEmpty);
    });

    test('addLayer appends a new layer', () {
      final sg = SceneGraph();
      final layer = testLayerNode(id: NodeId('L1'));
      sg.addLayer(layer);

      expect(sg.layers.length, 1);
      expect(sg.layers.first.id, 'L1');
    });

    test('removeLayer removes the layer', () {
      final sg = SceneGraph();
      final layer = testLayerNode(id: NodeId('L1'));
      sg.addLayer(layer);
      sg.removeLayer('L1');

      expect(sg.layers, isEmpty);
    });

    test('reorderLayers changes z-order', () {
      final sg = SceneGraph();
      sg.addLayer(testLayerNode(id: NodeId('A')));
      sg.addLayer(testLayerNode(id: NodeId('B')));
      sg.addLayer(testLayerNode(id: NodeId('C')));

      sg.reorderLayers(0, 2);

      expect(sg.layers[0].id, 'B');
      expect(sg.layers[1].id, 'A');
    });
  });

  group('SceneGraph node lookup', () {
    test('findNodeById finds node in any layer', () {
      final sg = SceneGraph();
      final layer = testLayerNode(id: NodeId('L1'));
      layer.add(testStrokeNode(id: NodeId('target')));
      sg.addLayer(layer);

      final found = sg.findNodeById('target');
      expect(found, isNotNull);
      expect(found!.id, 'target');
    });

    test('findNodeById returns null for missing node', () {
      final sg = SceneGraph();
      sg.addLayer(testLayerNode());
      expect(sg.findNodeById('nope'), isNull);
    });

    test('findNodeById finds deeply nested nodes', () {
      final sg = SceneGraph();
      final layer = testLayerNode(id: NodeId('L'));
      final group = testGroupNode(id: NodeId('G'));
      group.add(testStrokeNode(id: NodeId('deep')));
      layer.add(group);
      sg.addLayer(layer);

      expect(sg.findNodeById('deep'), isNotNull);
    });
  });

  group('SceneGraph serialization', () {
    test('toJson roundtrip preserves structure', () {
      final sg = SceneGraph();
      final layer = testLayerNode(id: NodeId('L1'));
      layer.add(testStrokeNode(id: NodeId('S1')));
      layer.add(testShapeNode(id: NodeId('SH1')));
      sg.addLayer(layer);

      final json = sg.toJson();
      final restored = SceneGraph.fromJson(json);

      expect(restored.layers.length, 1);
      expect(restored.layers.first.children.length, 2);
      expect(restored.findNodeById('S1'), isNotNull);
      expect(restored.findNodeById('SH1'), isNotNull);
    });

    test('toJson/fromJson preserves layer names', () {
      final sg = SceneGraph();
      final layer = testLayerNode(id: NodeId('L1'));
      layer.name = 'Background';
      sg.addLayer(layer);

      final json = sg.toJson();
      final restored = SceneGraph.fromJson(json);

      expect(restored.layers.first.name, 'Background');
    });
  });

  group('SceneGraph hit testing', () {
    test('hitTestAt returns topmost hit across layers', () {
      final sg = SceneGraph();
      final layer1 = testLayerNode(id: NodeId('L1'));
      layer1.add(testShapeNode(id: NodeId('bottom')));
      sg.addLayer(layer1);

      final layer2 = testLayerNode(id: NodeId('L2'));
      layer2.add(testShapeNode(id: NodeId('top')));
      sg.addLayer(layer2);

      final hit = sg.hitTestAt(const Offset(50, 50));
      // Topmost layer's node should win
      expect(hit, isNotNull);
      expect(hit!.id, 'top');
    });

    test('hitTestAt returns null for miss', () {
      final sg = SceneGraph();
      final layer = testLayerNode();
      layer.add(testShapeNode());
      sg.addLayer(layer);

      expect(sg.hitTestAt(const Offset(500, 500)), isNull);
    });

    test('hitTestAt does not skip invisible layers (known limitation)', () {
      final sg = SceneGraph();
      final layer = testLayerNode(id: NodeId('hidden'));
      layer.add(testShapeNode(id: NodeId('invisible-shape')));
      layer.isVisible = false;
      sg.addLayer(layer);

      // NOTE: SceneGraph.hitTestAt currently does NOT check layer visibility.
      // This documents the current behavior — it should be fixed in the
      // renderer, which already handles visibility.
      final hit = sg.hitTestAt(const Offset(50, 50));
      expect(hit, isNotNull);
    });
  });
}
