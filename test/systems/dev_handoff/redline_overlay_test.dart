import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/systems/dev_handoff/redline_overlay.dart';
import 'package:fluera_engine/src/core/nodes/frame_node.dart';
import 'package:fluera_engine/src/core/nodes/shape_node.dart';
import 'package:fluera_engine/src/core/models/shape_type.dart';
import 'package:fluera_engine/src/core/scene_graph/node_id.dart';
import 'dart:ui';
import 'package:vector_math/vector_math_64.dart';

/// Helper to create a ShapeNode with specific bounds via GeometricShape.
ShapeNode _makeShape(
  String id,
  double w,
  double h, {
  double tx = 0,
  double ty = 0,
}) {
  final shape = GeometricShape(
    id: 'gs-$id',
    type: ShapeType.rectangle,
    startPoint: Offset.zero,
    endPoint: Offset(w, h),
    color: const Color(0xFF000000),
    strokeWidth: 0,
    createdAt: DateTime(2026),
  );
  return ShapeNode(
    id: NodeId(id),
    shape: shape,
    localTransform: Matrix4.identity()..setTranslationRaw(tx, ty, 0),
  );
}

void main() {
  group('RedlineCalculator Tests', () {
    late RedlineCalculator calculator;

    setUp(() {
      calculator = const RedlineCalculator();
    });

    test('dimensionAnnotations returns correct width and height labels', () {
      final node = _makeShape('node-A', 100, 50);

      final annotations = calculator.dimensionAnnotations(node);

      expect(annotations.length, 2);

      final widthAnnotation = annotations.firstWhere((a) => a.isHorizontal);
      expect(widthAnnotation.label, '100');

      final heightAnnotation = annotations.firstWhere((a) => !a.isHorizontal);
      expect(heightAnnotation.label, '50');
    });

    test('spacingAnnotations measures horizontal gap', () {
      final nodeA = _makeShape('A', 100, 100);
      final nodeB = _makeShape('B', 50, 50, tx: 150, ty: 50);

      final spacing = calculator.spacingAnnotations(nodeA, nodeB);
      expect(spacing.isNotEmpty, isTrue);

      final hGap = spacing.firstWhere((a) => a.isHorizontal);
      expect(hGap.label, '50');
    });

    test('measureToParent computes parent insets', () {
      final parent = FrameNode(id: NodeId('parent'));
      parent.localTransform = Matrix4.identity();
      final child = _makeShape('child', 50, 50, tx: 20, ty: 30);
      parent.addWithConstraint(child, LayoutConstraint());

      final parentSpacing = calculator.measureToParent(child);
      expect(parentSpacing, isNotNull);
    });
  });
}
