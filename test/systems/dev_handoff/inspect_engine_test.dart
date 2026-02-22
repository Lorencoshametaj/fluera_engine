import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/systems/dev_handoff/inspect_engine.dart';
import 'package:nebula_engine/src/core/nodes/frame_node.dart';
import 'package:nebula_engine/src/core/nodes/shape_node.dart';
import 'package:nebula_engine/src/core/models/shape_type.dart';
import 'package:nebula_engine/src/core/scene_graph/node_id.dart';
import 'package:nebula_engine/src/core/effects/paint_stack.dart';
import 'package:vector_math/vector_math_64.dart';
import 'dart:ui';

void main() {
  group('InspectEngine Tests', () {
    test('inspect ShapeNode extracts position, size, and properties', () {
      final engine = const InspectEngine();

      final shape = GeometricShape(
        id: 'gs-1',
        type: ShapeType.rectangle,
        startPoint: Offset.zero,
        endPoint: const Offset(100, 50),
        color: const Color(0xFF000000),
        strokeWidth: 0,
        createdAt: DateTime(2026),
      );
      final node = ShapeNode(
        id: NodeId('shape-1'),
        shape: shape,
        localTransform: Matrix4.identity()..setTranslationRaw(10, 20, 0),
        opacity: 0.5,
        blendMode: BlendMode.multiply,
        fills: [FillLayer.solid(color: const Color(0xFFFF0000))],
        strokes: [StrokeLayer(color: const Color(0xFF00FF00), width: 2.0)],
      );

      final report = engine.inspect(node);

      expect(report.nodeId, 'shape-1');
      expect(report.nodeType, 'ShapeNode');
      // position comes from localBounds (includes stroke inflation)
      // With 2px center stroke, inflation = 1px on each side
      expect(report.position.dx, closeTo(-1, 0.1));
      expect(report.position.dy, closeTo(-1, 0.1));
      expect(report.size.width, closeTo(102, 1)); // 100 + 2*1
      expect(report.size.height, closeTo(52, 1)); // 50 + 2*1
      expect(report.opacity, 0.5);
      expect(report.blendMode, 'multiply');

      expect(report.fills.length, 1);

      expect(report.stroke, isNotNull);
      expect(report.stroke!.width, 2.0);
    });

    test('measureBetween returns correct spacing', () {
      final engine = const InspectEngine();

      final nodeA = FrameNode(id: NodeId('a'));
      nodeA.localTransform = Matrix4.identity();

      final nodeB = FrameNode(id: NodeId('b'));
      nodeB.localTransform = Matrix4.identity()..setTranslationRaw(100, 0, 0);

      final spacing = engine.measureBetween(nodeA, nodeB);

      expect(spacing.isOverlapping, isFalse);
    });
  });
}
