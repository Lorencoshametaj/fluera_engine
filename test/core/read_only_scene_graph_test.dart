import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/scene_graph/read_only_scene_graph.dart';
import 'package:nebula_engine/src/core/scene_graph/scene_graph.dart';
import 'package:nebula_engine/src/core/scene_graph/node_id.dart';

import '../helpers/test_helpers.dart';

void main() {
  late SceneGraph sg;
  late ReadConsistentView view;

  setUp(() {
    sg = SceneGraph();
    final layer = testLayerNode(
      id: NodeId('L1'),
      children: [testStrokeNode(id: 'S1'), testShapeNode(id: 'SH1')],
    );
    sg.addLayer(layer);
    view = ReadConsistentView(sg);
  });

  // ===========================================================================
  // Read operations
  // ===========================================================================

  group('read operations', () {
    test('layerCount matches scene graph', () {
      expect(view.layerCount, sg.layerCount);
    });

    test('layers returns frozen views', () {
      final layers = view.layers;
      expect(layers, hasLength(1));
      expect(layers.first.id, 'L1');
    });

    test('findNodeById returns frozen node', () {
      final node = view.findNodeById(NodeId('S1'));
      expect(node, isNotNull);
      expect(node!.id, 'S1');
    });

    test('findNodeById returns null for missing node', () {
      final node = view.findNodeById(NodeId('nonexistent'));
      expect(node, isNull);
    });

    test('containsNode returns true for existing node', () {
      expect(view.containsNode(NodeId('S1')), true);
    });

    test('containsNode returns false for missing node', () {
      expect(view.containsNode(NodeId('nope')), false);
    });

    test('totalElementCount matches', () {
      expect(view.totalElementCount, sg.totalElementCount);
    });

    test('version matches', () {
      expect(view.version, sg.version);
    });

    test('toJson works', () {
      final json = view.toJson();
      expect(json, isA<Map<String, dynamic>>());
    });

    test('snapshot works', () {
      final snap = view.snapshot();
      expect(snap.nodeCount, greaterThanOrEqualTo(2));
    });

    test('allNodes iterates all nodes', () {
      final all = view.allNodes.toList();
      expect(all.length, greaterThanOrEqualTo(2));
    });
  });

  // ===========================================================================
  // Epoch guard
  // ===========================================================================

  group('epoch guard', () {
    test('mutation after view creation causes StateError', () {
      // Mutate the scene graph after view was created
      sg.addLayer(testLayerNode(id: NodeId('L2')));

      expect(() => view.layerCount, throwsA(isA<StateError>()));
    });

    test('stale view reports epoch mismatch in error message', () {
      sg.addLayer(testLayerNode(id: NodeId('L2')));

      try {
        view.layers;
        fail('Should have thrown StateError');
      } on StateError catch (e) {
        expect(e.message, contains('mutated'));
        expect(e.message, contains('epoch'));
      }
    });

    test('all read methods throw after mutation', () {
      sg.addLayer(testLayerNode(id: NodeId('L2')));

      expect(() => view.rootNode, throwsA(isA<StateError>()));
      expect(() => view.layers, throwsA(isA<StateError>()));
      expect(() => view.layerCount, throwsA(isA<StateError>()));
      expect(() => view.findNodeById(NodeId('S1')), throwsA(isA<StateError>()));
      expect(() => view.containsNode(NodeId('S1')), throwsA(isA<StateError>()));
      expect(
        () => view.hitTestAt(const Offset(50, 50)),
        throwsA(isA<StateError>()),
      );
      expect(() => view.allNodes, throwsA(isA<StateError>()));
      expect(() => view.totalElementCount, throwsA(isA<StateError>()));
      expect(() => view.version, throwsA(isA<StateError>()));
      expect(() => view.toJson(), throwsA(isA<StateError>()));
      expect(() => view.snapshot(), throwsA(isA<StateError>()));
    });

    test('fresh view after mutation works', () {
      sg.addLayer(testLayerNode(id: NodeId('L2')));
      final freshView = ReadConsistentView(sg);

      expect(freshView.layerCount, 2);
    });
  });
}
