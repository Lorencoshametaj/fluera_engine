import 'package:nebula_engine/src/core/scene_graph/node_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/tools/eraser/eraser_hit_tester.dart';
import 'package:nebula_engine/src/drawing/models/pro_drawing_point.dart';
import 'package:nebula_engine/src/core/models/shape_type.dart';
import '../helpers/test_helpers.dart';

void main() {
  // =========================================================================
  // Geometry Primitives
  // =========================================================================

  group('distanceSq', () {
    test('zero distance for identical points', () {
      expect(EraserHitTester.distanceSq(Offset.zero, Offset.zero), 0.0);
    });

    test('calculates correct squared distance', () {
      expect(
        EraserHitTester.distanceSq(const Offset(0, 0), const Offset(3, 4)),
        25.0,
      ); // 3² + 4² = 25
    });

    test('is symmetric', () {
      const a = Offset(10, 20);
      const b = Offset(30, 40);
      expect(
        EraserHitTester.distanceSq(a, b),
        EraserHitTester.distanceSq(b, a),
      );
    });
  });

  group('pointToSegmentDistSq', () {
    test('point on segment start', () {
      const a = Offset(0, 0);
      const b = Offset(10, 0);
      expect(EraserHitTester.pointToSegmentDistSq(a, a, b), 0.0);
    });

    test('point on segment end', () {
      const a = Offset(0, 0);
      const b = Offset(10, 0);
      expect(EraserHitTester.pointToSegmentDistSq(b, a, b), 0.0);
    });

    test('point on midpoint of horizontal segment', () {
      const p = Offset(5, 0);
      const a = Offset(0, 0);
      const b = Offset(10, 0);
      expect(EraserHitTester.pointToSegmentDistSq(p, a, b), 0.0);
    });

    test('point perpendicular to horizontal segment', () {
      const p = Offset(5, 3);
      const a = Offset(0, 0);
      const b = Offset(10, 0);
      // Distance is 3 → squared = 9
      expect(EraserHitTester.pointToSegmentDistSq(p, a, b), 9.0);
    });

    test('point beyond segment end projects to closest endpoint', () {
      const p = Offset(15, 0);
      const a = Offset(0, 0);
      const b = Offset(10, 0);
      // Distance to b = 5 → squared = 25
      expect(EraserHitTester.pointToSegmentDistSq(p, a, b), 25.0);
    });

    test('degenerate segment (single point)', () {
      const p = Offset(3, 4);
      const a = Offset(0, 0);
      // When a == b, distance is just point-to-point
      expect(EraserHitTester.pointToSegmentDistSq(p, a, a), 25.0);
    });
  });

  group('closestPointOnSegment', () {
    test('returns start when projection falls before segment', () {
      const p = Offset(-5, 0);
      const a = Offset(0, 0);
      const b = Offset(10, 0);
      expect(EraserHitTester.closestPointOnSegment(p, a, b), a);
    });

    test('returns end when projection falls beyond segment', () {
      const p = Offset(15, 0);
      const a = Offset(0, 0);
      const b = Offset(10, 0);
      expect(EraserHitTester.closestPointOnSegment(p, a, b), b);
    });

    test('returns projected point when in middle of segment', () {
      const p = Offset(5, 3);
      const a = Offset(0, 0);
      const b = Offset(10, 0);
      final result = EraserHitTester.closestPointOnSegment(p, a, b);
      expect(result.dx, closeTo(5.0, 0.001));
      expect(result.dy, closeTo(0.0, 0.001));
    });
  });

  // =========================================================================
  // Point-in-Eraser Tests
  // =========================================================================

  group('isPointInsideEraser', () {
    test('circle — point inside', () {
      expect(
        EraserHitTester.isPointInsideEraser(
          const Offset(5, 5),
          const Offset(0, 0),
          eraserRadius: 10.0,
          eraserShape: EraserShape.circle,
        ),
        isTrue,
      );
    });

    test('circle — point outside', () {
      expect(
        EraserHitTester.isPointInsideEraser(
          const Offset(20, 20),
          const Offset(0, 0),
          eraserRadius: 10.0,
          eraserShape: EraserShape.circle,
        ),
        isFalse,
      );
    });

    test('circle — point on boundary', () {
      expect(
        EraserHitTester.isPointInsideEraser(
          const Offset(10, 0),
          const Offset(0, 0),
          eraserRadius: 10.0,
          eraserShape: EraserShape.circle,
        ),
        isTrue, // <= radius
      );
    });

    test('rectangle — point inside axis-aligned rect', () {
      expect(
        EraserHitTester.isPointInsideEraser(
          const Offset(5, 5),
          const Offset(0, 0),
          eraserRadius: 20.0,
          eraserShape: EraserShape.rectangle,
          eraserShapeWidth: 30.0,
          eraserShapeAngle: 0.0,
        ),
        isTrue,
      );
    });

    test('rectangle — point outside', () {
      expect(
        EraserHitTester.isPointInsideEraser(
          const Offset(50, 50),
          const Offset(0, 0),
          eraserRadius: 20.0,
          eraserShape: EraserShape.rectangle,
          eraserShapeWidth: 30.0,
          eraserShapeAngle: 0.0,
        ),
        isFalse,
      );
    });

    test('line — point near line center', () {
      expect(
        EraserHitTester.isPointInsideEraser(
          const Offset(0, 1),
          const Offset(0, 0),
          eraserRadius: 20.0,
          eraserShape: EraserShape.line,
          eraserShapeAngle: 0.0, // horizontal line
        ),
        isTrue,
      );
    });
  });

  // =========================================================================
  // Stroke-Eraser Intersection Tests
  // =========================================================================

  group('strokeIntersectsEraser', () {
    test('circle — stroke passing through eraser center', () {
      final stroke = testStroke(id: NodeId('crossing'), pointCount: 3);
      // Stroke goes from (0,0) to (20,20) — passing through the eraser center
      expect(
        EraserHitTester.strokeIntersectsEraser(
          stroke,
          const Offset(10, 10), // eraser at (10,10)
          eraserRadius: 15.0,
          eraserShape: EraserShape.circle,
        ),
        isTrue,
      );
    });

    test('circle — stroke far from eraser', () {
      final stroke = testStroke(id: NodeId('far'), pointCount: 3);
      expect(
        EraserHitTester.strokeIntersectsEraser(
          stroke,
          const Offset(500, 500),
          eraserRadius: 5.0,
          eraserShape: EraserShape.circle,
        ),
        isFalse,
      );
    });

    test('single point stroke at eraser center', () {
      final stroke = testStroke(id: NodeId('single'), pointCount: 1);
      expect(
        EraserHitTester.strokeIntersectsEraser(
          stroke,
          const Offset(0, 0), // stroke's only point
          eraserRadius: 5.0,
          eraserShape: EraserShape.circle,
        ),
        isTrue,
      );
    });

    test('rectangle — stroke intersecting', () {
      final stroke = testStroke(id: NodeId('rect-cross'), pointCount: 5);
      expect(
        EraserHitTester.strokeIntersectsEraser(
          stroke,
          const Offset(20, 20),
          eraserRadius: 30.0,
          eraserShape: EraserShape.rectangle,
          eraserShapeWidth: 40.0,
          eraserShapeAngle: 0.0,
        ),
        isTrue,
      );
    });
  });

  // =========================================================================
  // Shape-Eraser Intersection Tests
  // =========================================================================

  group('shapeIntersectsEraser', () {
    test('shape overlapping eraser', () {
      final shape = testShape(
        id: NodeId('overlap'),
        start: const Offset(0, 0),
        end: const Offset(50, 50),
      );
      expect(
        EraserHitTester.shapeIntersectsEraser(
          shape,
          const Offset(25, 25),
          eraserRadius: 10.0,
        ),
        isTrue,
      );
    });

    test('shape far from eraser', () {
      final shape = testShape(
        id: NodeId('far'),
        start: const Offset(0, 0),
        end: const Offset(10, 10),
      );
      expect(
        EraserHitTester.shapeIntersectsEraser(
          shape,
          const Offset(500, 500),
          eraserRadius: 5.0,
        ),
        isFalse,
      );
    });
  });

  // =========================================================================
  // strokeBBox
  // =========================================================================

  group('strokeBBox', () {
    test('returns correct bounding rect', () {
      final stroke = testStroke(id: NodeId('bbox'), pointCount: 5);
      // Points go from (0,0) to (40,40) in steps of 10
      final bbox = EraserHitTester.strokeBBox(stroke);
      expect(bbox, isNotNull);
      expect(bbox!.left, lessThanOrEqualTo(0.0));
      expect(bbox.top, lessThanOrEqualTo(0.0));
      expect(bbox.right, greaterThanOrEqualTo(40.0));
      expect(bbox.bottom, greaterThanOrEqualTo(40.0));
    });

    test('single point stroke has non-null bbox', () {
      final stroke = testStroke(id: NodeId('single-bbox'), pointCount: 1);
      final bbox = EraserHitTester.strokeBBox(stroke);
      expect(bbox, isNotNull);
    });
  });

  // =========================================================================
  // EraserShape enum
  // =========================================================================

  group('EraserShape', () {
    test('has three values', () {
      expect(EraserShape.values.length, 3);
    });

    test('contains circle, rectangle, line', () {
      expect(EraserShape.values, contains(EraserShape.circle));
      expect(EraserShape.values, contains(EraserShape.rectangle));
      expect(EraserShape.values, contains(EraserShape.line));
    });
  });
}
