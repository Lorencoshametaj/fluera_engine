import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:nebula_engine/src/canvas/navigation/content_bounds_tracker.dart';
import 'package:nebula_engine/src/core/scene_graph/node_id.dart';
import 'package:nebula_engine/src/core/nodes/shape_node.dart';
import 'package:nebula_engine/src/core/models/shape_type.dart';
import 'package:nebula_engine/src/tools/shape/shape_recognizer.dart';
import 'package:nebula_engine/src/layers/layer_controller.dart';

void main() {
  group('ContentBoundsTracker', () {
    late LayerController layerController;
    late ContentBoundsTracker tracker;

    GeometricShape _makeShape(String id, Offset start, Offset end) {
      return GeometricShape(
        id: id,
        type: ShapeType.rectangle,
        startPoint: start,
        endPoint: end,
        color: Colors.black,
        strokeWidth: 2.0,
        createdAt: DateTime(2024),
      );
    }

    setUp(() {
      layerController = LayerController();
      tracker = ContentBoundsTracker(layerController: layerController);
    });

    tearDown(() {
      tracker.dispose();
      layerController.dispose();
    });

    test('empty canvas returns Rect.zero', () {
      tracker.update();
      expect(tracker.bounds.value, Rect.zero);
      expect(tracker.regions.value, isEmpty);
    });

    test('single shape returns bounds encompassing it', () {
      layerController.addShape(
        _makeShape('s1', const Offset(100, 100), const Offset(300, 200)),
      );

      tracker.update();

      final bounds = tracker.bounds.value;
      expect(bounds.left, lessThanOrEqualTo(100));
      expect(bounds.top, lessThanOrEqualTo(100));
      expect(bounds.right, greaterThanOrEqualTo(300));
      expect(bounds.bottom, greaterThanOrEqualTo(200));
      expect(tracker.regions.value, hasLength(1));
      expect(tracker.regions.value.first.nodeType, ContentNodeType.shape);
    });

    test('multiple shapes: bounds encompasses all', () {
      layerController.addShape(
        _makeShape('s1', const Offset(0, 0), const Offset(100, 100)),
      );
      layerController.addShape(
        _makeShape('s2', const Offset(500, 400), const Offset(600, 500)),
      );

      tracker.update();

      final bounds = tracker.bounds.value;
      expect(bounds.left, lessThanOrEqualTo(0));
      expect(bounds.top, lessThanOrEqualTo(0));
      expect(bounds.right, greaterThanOrEqualTo(600));
      expect(bounds.bottom, greaterThanOrEqualTo(500));
      expect(tracker.regions.value, hasLength(2));
    });

    test('caching: update() returns false when version unchanged', () {
      layerController.addShape(
        _makeShape('s1', const Offset(10, 10), const Offset(50, 50)),
      );

      expect(tracker.update(), isTrue);
      expect(tracker.update(), isFalse);
    });

    test('recalculates after adding more content', () {
      layerController.addShape(
        _makeShape('s1', const Offset(10, 10), const Offset(50, 50)),
      );

      tracker.update();
      final firstBounds = tracker.bounds.value;

      layerController.addShape(
        _makeShape('s2', const Offset(200, 200), const Offset(400, 400)),
      );

      expect(tracker.update(), isTrue);
      expect(tracker.bounds.value, isNot(equals(firstBounds)));
      expect(tracker.bounds.value.right, greaterThanOrEqualTo(400));
    });

    test('invalidate() forces recalculation', () {
      layerController.addShape(
        _makeShape('s1', const Offset(10, 10), const Offset(50, 50)),
      );

      tracker.update();
      expect(tracker.update(), isFalse);

      tracker.invalidate();
      expect(tracker.update(), isTrue);
    });
  });
}
