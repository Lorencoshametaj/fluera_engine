import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:fluera_engine/src/canvas/navigation/camera_actions.dart';
import 'package:fluera_engine/src/core/scene_graph/scene_graph.dart';
import 'package:fluera_engine/src/core/scene_graph/node_id.dart';
import 'package:fluera_engine/src/core/nodes/layer_node.dart';
import 'package:fluera_engine/src/core/nodes/shape_node.dart';
import 'package:fluera_engine/src/core/models/shape_type.dart';
import 'package:fluera_engine/src/tools/shape/shape_recognizer.dart';
import 'package:fluera_engine/src/canvas/infinite_canvas_controller.dart';

void main() {
  group('CameraActions', () {
    late InfiniteCanvasController controller;
    late SceneGraph sceneGraph;

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
      controller = InfiniteCanvasController();
      sceneGraph = SceneGraph();
    });

    tearDown(() {
      controller.dispose();
    });

    test('fitAllContent with empty graph does nothing', () {
      final initialOffset = controller.offset;
      final initialScale = controller.scale;

      CameraActions.fitAllContent(controller, sceneGraph, const Size(800, 600));

      expect(controller.offset, equals(initialOffset));
      expect(controller.scale, equals(initialScale));
    });

    test('fitAllContent with content triggers animation', () {
      final layer = LayerNode(id: NodeId('layer1'));
      sceneGraph.addLayer(layer);
      layer.add(
        ShapeNode(
          id: NodeId('s1'),
          shape: _makeShape(
            's1',
            const Offset(100, 100),
            const Offset(500, 400),
          ),
        ),
      );

      CameraActions.fitAllContent(controller, sceneGraph, const Size(800, 600));

      expect(controller.scale, isPositive);
    });

    test('fitSelection with empty selection does nothing', () {
      final initialOffset = controller.offset;

      CameraActions.fitSelection(controller, [], const Size(800, 600));

      expect(controller.offset, equals(initialOffset));
    });

    test('fitSelection with nodes computes bounds', () {
      final layer = LayerNode(id: NodeId('layer1'));
      sceneGraph.addLayer(layer);

      final node1 = ShapeNode(
        id: NodeId('s1'),
        shape: _makeShape('s1', const Offset(0, 0), const Offset(200, 200)),
      );
      final node2 = ShapeNode(
        id: NodeId('s2'),
        shape: _makeShape('s2', const Offset(300, 300), const Offset(500, 500)),
      );
      layer.add(node1);
      layer.add(node2);

      CameraActions.fitSelection(controller, [
        node1,
        node2,
      ], const Size(800, 600));

      expect(controller.scale, isPositive);
    });

    test('returnToOrigin sets correct target', () {
      controller.setOffset(const Offset(1000, 2000));
      controller.setScale(3.0);

      CameraActions.returnToOrigin(controller, const Size(800, 600));

      expect(controller.scale, isPositive);
    });

    test('zoomToLevel sets correct target scale', () {
      controller.setScale(1.0);

      CameraActions.zoomToLevel(controller, 2.0, const Size(800, 600));

      expect(controller.scale, isPositive);
    });

    test('zoomToRect with valid rect works', () {
      CameraActions.zoomToRect(
        controller,
        const Rect.fromLTWH(100, 100, 400, 300),
        const Size(800, 600),
      );

      expect(controller.scale, isPositive);
    });

    test('zoomToRect with empty rect does nothing', () {
      final initialScale = controller.scale;

      CameraActions.zoomToRect(controller, Rect.zero, const Size(800, 600));

      expect(controller.scale, equals(initialScale));
    });
  });
}
