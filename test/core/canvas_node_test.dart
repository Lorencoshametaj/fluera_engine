import 'package:fluera_engine/src/core/scene_graph/node_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/scene_graph/canvas_node.dart';
import 'package:fluera_engine/src/core/scene_graph/canvas_node_factory.dart';
import 'package:fluera_engine/src/core/nodes/stroke_node.dart';
import 'package:fluera_engine/src/core/nodes/shape_node.dart';
import 'package:fluera_engine/src/core/nodes/group_node.dart';

import '../helpers/test_helpers.dart';

void main() {
  group('CanvasNode properties', () {
    test('default values are correct', () {
      final node = testStrokeNode();
      expect(node.opacity, 1.0);
      expect(node.isVisible, true);
      expect(node.isLocked, false);
      expect(node.blendMode, BlendMode.srcOver);
      expect(node.parent, isNull);
      expect(node.effects, isEmpty);
    });

    test('id is set correctly', () {
      final node = testStrokeNode(id: NodeId('my-id'));
      expect(node.id, 'my-id');
    });

    test('name is set correctly', () {
      final node = StrokeNode(id: NodeId('n'), stroke: testStroke(), name: 'My Node');
      expect(node.name, 'My Node');
    });

    test('opacity clamps to valid range', () {
      final node = testStrokeNode();
      node.opacity = 0.5;
      expect(node.opacity, 0.5);
    });
  });

  group('CanvasNode transform', () {
    test('localTransform defaults to identity', () {
      final node = testStrokeNode();
      expect(node.localTransform, Matrix4.identity());
    });

    test('worldTransform equals localTransform when no parent', () {
      final node = testStrokeNode();
      node.localTransform = Matrix4.translationValues(10, 20, 0);
      expect(node.worldTransform, node.localTransform);
    });

    test('worldTransform combines parent and local transforms', () {
      final parent = testGroupNode();
      final child = testStrokeNode(id: NodeId('child'));
      parent.add(child);

      parent.localTransform = Matrix4.translationValues(100, 0, 0);
      child.localTransform = Matrix4.translationValues(0, 50, 0);

      // World transform should be parent * child
      final world = child.worldTransform;
      // Translation should be (100, 50, 0)
      expect(world.getTranslation().x, closeTo(100.0, 0.001));
      expect(world.getTranslation().y, closeTo(50.0, 0.001));
    });

    test('invalidateTransformCache forces recalculation', () {
      final node = testStrokeNode();
      node.localTransform = Matrix4.translationValues(10, 0, 0);
      final before = node.worldTransform;
      expect(before.getTranslation().x, closeTo(10.0, 0.001));

      node.localTransform = Matrix4.translationValues(20, 0, 0);
      node.invalidateTransformCache();
      final after = node.worldTransform;
      expect(after.getTranslation().x, closeTo(20.0, 0.001));
    });
  });

  group('CanvasNode serialization', () {
    test('baseToJson contains all common fields', () {
      final node = testStrokeNode(id: NodeId('test-ser'));
      node.name = 'Test';
      node.opacity = 0.8;
      node.isVisible = false;
      node.isLocked = true;

      final json = node.toJson();
      expect(json['id'], 'test-ser');
      expect(json['name'], 'Test');
      expect(json['opacity'], 0.8);
      expect(json['isVisible'], false);
      expect(json['isLocked'], true);
      expect(json['nodeType'], 'stroke');
    });

    test('toJson omits default values for storage efficiency', () {
      final node = testStrokeNode();
      final json = node.toJson();
      // Default opacity (1.0) should be omitted
      expect(json.containsKey('opacity'), false);
      // Default isVisible (true) should be omitted
      expect(json.containsKey('isVisible'), false);
      // Default isLocked (false) should be omitted
      expect(json.containsKey('isLocked'), false);
    });
  });

  group('CanvasNode clone', () {
    test('clone produces a different node with different id', () {
      final original = testStrokeNode(id: NodeId('original'));
      original.name = 'My Stroke';
      final cloned = original.clone();

      expect(cloned.id, isNot(equals(original.id)));
      expect(cloned, isA<StrokeNode>());
    });

    test('clone preserves properties', () {
      final original = testStrokeNode(id: NodeId('orig'));
      original.name = 'Test Stroke';
      original.opacity = 0.7;
      final cloned = original.clone();

      expect(cloned.name, 'Test Stroke');
      expect(cloned.opacity, 0.7);
    });

    test('clone id is a valid hex-32 format', () {
      final original = testStrokeNode();
      final cloned = original.clone();
      // 32-char hex string (no dashes)
      expect(
        cloned.id,
        matches(
          RegExp(
            r'^[0-9a-f]{32}$',
          ),
        ),
      );
    });
  });

  group('CanvasNode hit testing', () {
    test('hitTest returns true for point inside localBounds', () {
      final node = testShapeNode();
      // Shape is from (0,0) to (100,100)
      expect(node.hitTest(const Offset(50, 50)), isTrue);
    });

    test('hitTest returns false for point outside localBounds', () {
      final node = testShapeNode();
      expect(node.hitTest(const Offset(500, 500)), isFalse);
    });

    test('hitTest returns false when node is invisible', () {
      final node = testShapeNode();
      node.isVisible = false;
      expect(node.hitTest(const Offset(50, 50)), isFalse);
    });
  });
}
