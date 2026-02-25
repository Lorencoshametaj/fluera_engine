import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/scene_graph/canvas_node_factory.dart';
import 'package:nebula_engine/src/core/scene_graph/canvas_node.dart';
import 'package:nebula_engine/src/core/scene_graph/node_id.dart';
import 'package:nebula_engine/src/core/nodes/stroke_node.dart';
import 'package:nebula_engine/src/core/nodes/shape_node.dart';
import 'package:nebula_engine/src/core/nodes/text_node.dart';
import 'package:nebula_engine/src/core/nodes/group_node.dart';
import 'package:nebula_engine/src/core/nodes/layer_node.dart';
import 'package:nebula_engine/src/core/nodes/path_node.dart';
import 'package:nebula_engine/src/core/nodes/rich_text_node.dart';
import 'package:nebula_engine/src/core/nodes/frame_node.dart';
import 'package:nebula_engine/src/core/nodes/latex_node.dart';

import '../helpers/test_helpers.dart';

void main() {
  // ===========================================================================
  // Basic node type dispatch
  // ===========================================================================

  group('fromJson node type dispatch', () {
    test('stroke → StrokeNode', () {
      final stroke = testStroke(id: 'S1');
      final node = testStrokeNode(id: 'S1');
      final json = node.toJson();

      final restored = CanvasNodeFactory.fromJson(json);
      expect(restored, isA<StrokeNode>());
      expect(restored.id, 'S1');
    });

    test('shape → ShapeNode', () {
      final node = testShapeNode(id: 'SH1');
      final json = node.toJson();

      final restored = CanvasNodeFactory.fromJson(json);
      expect(restored, isA<ShapeNode>());
      expect(restored.id, 'SH1');
    });

    test('group → GroupNode with children', () {
      final group = testGroupNode(
        id: 'G1',
        children: [testStrokeNode(id: 'child1')],
      );
      final json = group.toJson();

      final restored = CanvasNodeFactory.fromJson(json);
      expect(restored, isA<GroupNode>());
      expect((restored as GroupNode).children, hasLength(1));
    });

    test('layer → LayerNode via layerFromJson', () {
      final layer = testLayerNode(
        id: 'L1',
        children: [testShapeNode(id: 'ch1')],
      );
      final json = layer.toJson();

      final restored = CanvasNodeFactory.fromJson(json);
      expect(restored, isA<LayerNode>());
      expect((restored as LayerNode).children, hasLength(1));
    });
  });

  // ===========================================================================
  // Error handling
  // ===========================================================================

  group('error handling', () {
    test('unknown nodeType throws ArgumentError', () {
      final json = {'nodeType': 'unknown_type', 'id': 'x'};
      expect(
        () => CanvasNodeFactory.fromJson(json),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('null nodeType throws ArgumentError', () {
      final json = <String, dynamic>{'id': 'x'};
      expect(
        () => CanvasNodeFactory.fromJson(json),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // ===========================================================================
  // Roundtrip
  // ===========================================================================

  group('roundtrip', () {
    test('stroke node roundtrip preserves data', () {
      final original = testStrokeNode(id: 'rt-1');
      final json = original.toJson();
      final restored = CanvasNodeFactory.fromJson(json) as StrokeNode;

      expect(restored.id, original.id);
    });

    test('nested group roundtrip preserves hierarchy', () {
      final inner = testGroupNode(
        id: 'inner',
        children: [testStrokeNode(id: 'deep')],
      );
      final outer = testGroupNode(id: 'outer', children: [inner]);
      final json = outer.toJson();

      final restored = CanvasNodeFactory.fromJson(json) as GroupNode;
      expect(restored.children, hasLength(1));
      final restoredInner = restored.children.first as GroupNode;
      expect(restoredInner.children, hasLength(1));
      expect(restoredInner.children.first.id, 'deep');
    });
  });

  // ===========================================================================
  // layerFromJson
  // ===========================================================================

  group('layerFromJson', () {
    test('creates layer with correct ID', () {
      final json = <String, dynamic>{
        'nodeType': 'layer',
        'id': 'test-layer',
        'name': 'Background',
      };

      final layer = CanvasNodeFactory.layerFromJson(json);
      expect(layer, isA<LayerNode>());
      expect(layer.id, 'test-layer');
    });

    test('creates layer with children', () {
      final child = testStrokeNode(id: 'child-stroke');
      final layer = testLayerNode(id: 'L1', children: [child]);
      final json = layer.toJson();

      final restored = CanvasNodeFactory.layerFromJson(json);
      expect(restored.children, hasLength(1));
      expect(restored.children.first.id, 'child-stroke');
    });

    test('creates layer without children', () {
      final json = <String, dynamic>{
        'nodeType': 'layer',
        'id': 'empty-layer',
        'name': 'Empty',
      };

      final layer = CanvasNodeFactory.layerFromJson(json);
      expect(layer.children, isEmpty);
    });
  });
}
