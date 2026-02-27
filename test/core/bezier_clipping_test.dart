import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/vector/bezier_clipping.dart';

void main() {
  // ===========================================================================
  // CubicBezier — pointAt / tangentAt
  // ===========================================================================

  group('CubicBezier', () {
    test('pointAt(0) returns first control point', () {
      final c = CubicBezier(
        Offset(0, 0),
        Offset(10, 20),
        Offset(30, 20),
        Offset(40, 0),
      );
      final p = c.pointAt(0);
      expect(p.dx, closeTo(0, 0.01));
      expect(p.dy, closeTo(0, 0.01));
    });

    test('pointAt(1) returns last control point', () {
      final c = CubicBezier(
        Offset(0, 0),
        Offset(10, 20),
        Offset(30, 20),
        Offset(40, 0),
      );
      final p = c.pointAt(1);
      expect(p.dx, closeTo(40, 0.01));
      expect(p.dy, closeTo(0, 0.01));
    });

    test('pointAt(0.5) is between start and end', () {
      final c = CubicBezier(
        Offset(0, 0),
        Offset(0, 100),
        Offset(100, 100),
        Offset(100, 0),
      );
      final p = c.pointAt(0.5);
      expect(p.dx, greaterThan(0));
      expect(p.dx, lessThan(100));
    });

    test('tangentAt returns non-zero vector', () {
      final c = CubicBezier(
        Offset(0, 0),
        Offset(10, 20),
        Offset(30, 20),
        Offset(40, 0),
      );
      final t = c.tangentAt(0.5);
      final mag = t.dx * t.dx + t.dy * t.dy;
      expect(mag, greaterThan(0));
    });
  });

  // ===========================================================================
  // BezierClipping — splitAt
  // ===========================================================================

  group('BezierClipping - splitAt', () {
    test('splitAt(0.5) returns two sub-curves', () {
      final c = CubicBezier(
        Offset(0, 0),
        Offset(10, 20),
        Offset(30, 20),
        Offset(40, 0),
      );
      final (left, right) = BezierClipping.splitAt(c, 0.5);
      // Left starts at original start
      expect(left.pointAt(0).dx, closeTo(0, 0.01));
      // Right ends at original end
      expect(right.pointAt(1).dx, closeTo(40, 0.01));
    });

    test('split point is shared', () {
      final c = CubicBezier(
        Offset(0, 0),
        Offset(10, 30),
        Offset(30, 30),
        Offset(40, 0),
      );
      final (left, right) = BezierClipping.splitAt(c, 0.3);
      final leftEnd = left.pointAt(1);
      final rightStart = right.pointAt(0);
      expect(leftEnd.dx, closeTo(rightStart.dx, 0.01));
      expect(leftEnd.dy, closeTo(rightStart.dy, 0.01));
    });
  });

  // ===========================================================================
  // BezierClipping — intersectCubics
  // ===========================================================================

  group('BezierClipping - intersectCubics', () {
    test('crossing curves have intersection', () {
      // Horizontal S curve
      final a = CubicBezier(
        Offset(0, 50),
        Offset(50, 0),
        Offset(50, 100),
        Offset(100, 50),
      );
      // Vertical S curve crossing the horizontal one
      final b = CubicBezier(
        Offset(50, 0),
        Offset(0, 50),
        Offset(100, 50),
        Offset(50, 100),
      );
      final hits = BezierClipping.intersectCubics(a, b);
      expect(hits, isNotEmpty);
    });

    test('non-overlapping curves have no intersection', () {
      final a = CubicBezier(
        Offset(0, 0),
        Offset(10, 10),
        Offset(20, 10),
        Offset(30, 0),
      );
      final b = CubicBezier(
        Offset(0, 100),
        Offset(10, 110),
        Offset(20, 110),
        Offset(30, 100),
      );
      final hits = BezierClipping.intersectCubics(a, b);
      expect(hits, isEmpty);
    });
  });

  // ===========================================================================
  // BezierClipping — lineToCubic / quadraticToCubic
  // ===========================================================================

  group('BezierClipping - conversions', () {
    test('lineToCubic preserves endpoints', () {
      final c = BezierClipping.lineToCubic(Offset(0, 0), Offset(100, 50));
      expect(c.pointAt(0).dx, closeTo(0, 0.01));
      expect(c.pointAt(1).dx, closeTo(100, 0.01));
    });

    test('quadraticToCubic preserves endpoints', () {
      final c = BezierClipping.quadraticToCubic(
        Offset(0, 0),
        Offset(50, 100),
        Offset(100, 0),
      );
      expect(c.pointAt(0).dx, closeTo(0, 0.01));
      expect(c.pointAt(1).dx, closeTo(100, 0.01));
    });
  });

  // ===========================================================================
  // BezierClipping — windingNumber
  // ===========================================================================

  group('BezierClipping - windingNumber', () {
    test('point inside square has non-zero winding', () {
      // Build a square from 4 line segments as degenerate cubics
      final square = [
        BezierClipping.lineToCubic(Offset(0, 0), Offset(100, 0)),
        BezierClipping.lineToCubic(Offset(100, 0), Offset(100, 100)),
        BezierClipping.lineToCubic(Offset(100, 100), Offset(0, 100)),
        BezierClipping.lineToCubic(Offset(0, 100), Offset(0, 0)),
      ];
      final w = BezierClipping.windingNumber(Offset(50, 50), square);
      expect(w, isNot(0));
    });

    test('point outside square has zero winding', () {
      final square = [
        BezierClipping.lineToCubic(Offset(0, 0), Offset(100, 0)),
        BezierClipping.lineToCubic(Offset(100, 0), Offset(100, 100)),
        BezierClipping.lineToCubic(Offset(100, 100), Offset(0, 100)),
        BezierClipping.lineToCubic(Offset(0, 100), Offset(0, 0)),
      ];
      final w = BezierClipping.windingNumber(Offset(200, 200), square);
      expect(w, 0);
    });
  });
}
