import 'package:nebula_engine/src/core/scene_graph/node_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/scene_graph/canvas_node.dart';
import 'package:nebula_engine/src/core/scene_graph/canvas_node_factory.dart';
import 'package:nebula_engine/src/core/nodes/stroke_node.dart';
import 'package:nebula_engine/src/core/nodes/shape_node.dart';
import 'package:nebula_engine/src/core/nodes/text_node.dart';
import 'package:nebula_engine/src/core/nodes/image_node.dart';
import 'package:nebula_engine/src/core/nodes/group_node.dart';
import 'package:nebula_engine/src/core/nodes/layer_node.dart';
import 'package:nebula_engine/src/core/models/digital_text_element.dart';
import 'package:nebula_engine/src/core/models/image_element.dart';

import '../helpers/test_helpers.dart';

void main() {
  group('StrokeNode serialization roundtrip', () {
    test('toJson → fromJson preserves data', () {
      final original = testStrokeNode(id: NodeId('stroke-rt'));
      final json = original.toJson();
      final restored = StrokeNode.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.stroke.points.length, original.stroke.points.length);
      expect(restored.stroke.color, original.stroke.color);
      expect(restored.stroke.baseWidth, original.stroke.baseWidth);
      expect(restored.stroke.penType, original.stroke.penType);
    });
  });

  group('ShapeNode serialization roundtrip', () {
    test('toJson → fromJson preserves data', () {
      final original = testShapeNode(id: NodeId('shape-rt'));
      final json = original.toJson();
      final restored = ShapeNode.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.shape.type, original.shape.type);
      expect(restored.shape.startPoint, original.shape.startPoint);
      expect(restored.shape.endPoint, original.shape.endPoint);
      expect(restored.shape.color.toARGB32(), original.shape.color.toARGB32());
      expect(restored.shape.strokeWidth, original.shape.strokeWidth);
    });
  });

  group('TextNode serialization roundtrip', () {
    test('toJson → fromJson preserves data', () {
      final original = TextNode(
        id: NodeId('text-rt'),
        textElement: DigitalTextElement(
          id: NodeId('te-1'),
          text: 'Hello World',
          position: const Offset(10, 20),
          color: Colors.blue,
          fontSize: 18.0,
          createdAt: DateTime(2025, 1, 1),
        ),
      );

      final json = original.toJson();
      final restored = TextNode.fromJson(json);

      expect(restored.id, 'text-rt');
      expect(restored.textElement.text, 'Hello World');
      expect(restored.textElement.position.dx, 10.0);
      expect(restored.textElement.position.dy, 20.0);
      expect(restored.textElement.color.toARGB32(), Colors.blue.toARGB32());
      expect(restored.textElement.fontSize, 18.0);
    });
  });

  group('ImageNode serialization roundtrip', () {
    test('toJson → fromJson preserves data', () {
      final original = ImageNode(
        id: NodeId('img-rt'),
        imageElement: ImageElement(
          id: NodeId('ie-1'),
          imagePath: '/path/to/image.png',
          position: const Offset(100, 200),
          scale: 1.5,
          createdAt: DateTime(2025, 6, 15),
          pageIndex: 0,
        ),
      );

      final json = original.toJson();
      final restored = ImageNode.fromJson(json);

      expect(restored.id, 'img-rt');
      expect(restored.imageElement.imagePath, '/path/to/image.png');
      expect(restored.imageElement.position.dx, 100.0);
      expect(restored.imageElement.scale, 1.5);
    });
  });

  group('GroupNode serialization roundtrip', () {
    test('toJson → fromJson preserves children', () {
      final group = testGroupNode(id: NodeId('grp-rt'));
      group.add(testStrokeNode(id: NodeId('child-s')));
      group.add(testShapeNode(id: NodeId('child-sh')));

      final json = group.toJson();
      final restored = CanvasNodeFactory.fromJson(json) as GroupNode;

      expect(restored.id, 'grp-rt');
      expect(restored.children.length, 2);
      expect(restored.children[0], isA<StrokeNode>());
      expect(restored.children[1], isA<ShapeNode>());
    });
  });

  group('LayerNode serialization roundtrip', () {
    test('toJson → fromJson preserves children and properties', () {
      final layer = testLayerNode(id: NodeId('layer-rt'));
      layer.name = 'Background Layer';
      layer.opacity = 0.8;
      layer.add(testStrokeNode(id: NodeId('ls')));

      final json = layer.toJson();
      final restored = CanvasNodeFactory.layerFromJson(json);

      expect(restored.id, 'layer-rt');
      expect(restored.name, 'Background Layer');
      expect(restored.opacity, 0.8);
      expect(restored.children.length, 1);
    });
  });

  group('CanvasNodeFactory', () {
    test('fromJson dispatches to correct type', () {
      final strokeJson = testStrokeNode(id: NodeId('f-s')).toJson();
      final shapeJson = testShapeNode(id: NodeId('f-sh')).toJson();

      expect(CanvasNodeFactory.fromJson(strokeJson), isA<StrokeNode>());
      expect(CanvasNodeFactory.fromJson(shapeJson), isA<ShapeNode>());
    });

    test('fromJson throws for unknown nodeType', () {
      expect(
        () => CanvasNodeFactory.fromJson({'nodeType': 'unknown', 'id': 'x'}),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('Base properties serialization', () {
    test('non-default opacity is preserved', () {
      final node = testStrokeNode(id: NodeId('opacity-test'));
      node.opacity = 0.42;
      final json = node.toJson();
      final restored = StrokeNode.fromJson(json);
      expect(restored.opacity, 0.42);
    });

    test('visibility and lock state are preserved', () {
      final node = testStrokeNode(id: NodeId('vis-lock'));
      node.isVisible = false;
      node.isLocked = true;
      final json = node.toJson();
      final restored = StrokeNode.fromJson(json);
      expect(restored.isVisible, false);
      expect(restored.isLocked, true);
    });

    test('custom name is preserved', () {
      final node = StrokeNode(
        id: NodeId('named'),
        stroke: testStroke(),
        name: 'My Stroke',
      );
      final json = node.toJson();
      final restored = StrokeNode.fromJson(json);
      expect(restored.name, 'My Stroke');
    });
  });
}
