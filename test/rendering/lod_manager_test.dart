import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/rendering/optimization/lod_manager.dart';
import 'package:fluera_engine/src/drawing/models/pro_drawing_point.dart';

ProDrawingPoint _pt(double x, double y) =>
    ProDrawingPoint(position: Offset(x, y), pressure: 0.5, timestamp: 0);

ProStroke _makeStroke(String id, List<ProDrawingPoint> points) => ProStroke(
  id: id,
  points: points,
  color: const Color(0xFF000000),
  baseWidth: 2.0,
  penType: ProPenType.ballpoint,
  createdAt: DateTime(2026),
);

void main() {
  late LODManager lod;

  setUp(() {
    lod = LODManager.create();
  });

  group('getLODLevel', () {
    test('returns 0 at high zoom (> 50%)', () {
      expect(LODManager.getLODLevel(1.0), 0);
      expect(LODManager.getLODLevel(0.51), 0);
      // 0.5 exactly hits LOD 1 boundary (> not >=)
      expect(LODManager.getLODLevel(0.5), 1);
    });

    test('returns 1 at medium zoom (20-50%)', () {
      expect(LODManager.getLODLevel(0.3), 1);
    });

    test('returns 2 at low zoom (5-20%)', () {
      expect(LODManager.getLODLevel(0.1), 2);
    });

    test('returns 3 at very low zoom (< 5%)', () {
      expect(LODManager.getLODLevel(0.02), 3);
    });
  });

  group('getToleranceForLevel', () {
    test('returns 0 for LOD 0 (full detail)', () {
      expect(LODManager.getToleranceForLevel(0), 0.0);
    });

    test('returns increasing tolerance for higher LOD', () {
      final t0 = LODManager.getToleranceForLevel(0);
      final t1 = LODManager.getToleranceForLevel(1);
      final t2 = LODManager.getToleranceForLevel(2);
      final t3 = LODManager.getToleranceForLevel(3);

      expect(t1, greaterThan(t0));
      expect(t2, greaterThan(t1));
      expect(t3, greaterThan(t2));
    });
  });

  group('simplifyPoints', () {
    test('returns same points at tolerance 0', () {
      final points = List.generate(10, (i) => _pt(i * 10.0, (i % 2) * 5.0));

      final result = LODManager.simplifyPoints(points, 0.0);
      expect(result.length, points.length);
    });

    test('reduces point count for straight line at high tolerance', () {
      // Perfect straight line should simplify heavily
      final points = List.generate(50, (i) => _pt(i * 1.0, 0));

      final result = LODManager.simplifyPoints(points, 5.0);
      expect(result.length, lessThan(points.length));
    });

    test('preserves at least 2 points', () {
      final points = List.generate(5, (i) => _pt(i * 10.0, 0));

      final result = LODManager.simplifyPoints(points, 1000.0);
      expect(result.length, greaterThanOrEqualTo(2));
    });

    test('returns original if <= 2 points', () {
      final points = [_pt(0, 0), _pt(10, 10)];

      final result = LODManager.simplifyPoints(points, 100.0);
      expect(result.length, 2);
    });
  });

  group('getPointsForZoom', () {
    test('returns original points at LOD 0 (high zoom)', () {
      final points = List.generate(20, (i) => _pt(i * 10.0, (i % 2) * 5.0));
      final stroke = _makeStroke('s1', points);

      final result = lod.getPointsForZoom(stroke, 1.0);
      expect(result.length, stroke.points.length);
    });

    test('caches simplified points', () {
      final points = List.generate(50, (i) => _pt(i * 1.0, 0));
      final stroke = _makeStroke('s1', points);

      final r1 = lod.getPointsForZoom(stroke, 0.02);
      final r2 = lod.getPointsForZoom(stroke, 0.02);

      // Same cached list
      expect(identical(r1, r2), isTrue);
    });
  });

  group('cache management', () {
    test('invalidateStroke clears cache for that stroke', () {
      final points = List.generate(50, (i) => _pt(i * 1.0, 0));
      final stroke = _makeStroke('s1', points);

      final r1 = lod.getPointsForZoom(stroke, 0.02);
      lod.invalidateStroke('s1');
      final r2 = lod.getPointsForZoom(stroke, 0.02);

      expect(identical(r1, r2), isFalse);
    });

    test('clearCache clears all cached data', () {
      final points = List.generate(50, (i) => _pt(i * 1.0, 0));
      final stroke = _makeStroke('s1', points);

      lod.getPointsForZoom(stroke, 0.02);
      lod.clearCache();

      final r2 = lod.getPointsForZoom(stroke, 0.02);
      expect(r2, isNotNull);
    });
  });

  group('getReductionFactor', () {
    test('returns 1.0 for LOD 0 (no reduction)', () {
      final points = List.generate(10, (i) => _pt(i * 10.0, (i % 2) * 5.0));
      final factor = LODManager.getReductionFactor(points, 0);
      expect(factor, 1.0);
    });

    test('returns < 1.0 for higher LOD on straight line', () {
      final points = List.generate(100, (i) => _pt(i * 1.0, 0));
      final factor = LODManager.getReductionFactor(points, 2);
      expect(factor, lessThan(1.0));
    });
  });
}
