import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/rendering/optimization/viewport_culler.dart';
import 'package:nebula_engine/src/drawing/models/pro_drawing_point.dart';

ProStroke _makeStroke({required Rect bounds, String id = 'mock'}) {
  // Build a stroke whose .bounds will match the given rect.
  // We place two points at the corners, with minimal width so padding is small.
  return ProStroke(
    id: id,
    points: [
      ProDrawingPoint(
        position: Offset(bounds.left, bounds.top),
        pressure: 0.5,
        timestamp: 0,
      ),
      ProDrawingPoint(
        position: Offset(bounds.right, bounds.bottom),
        pressure: 0.5,
        timestamp: 0,
      ),
    ],
    color: const Color(0xFF000000),
    baseWidth: 0.1, // tiny width so bounds ≈ point bounds
    penType: ProPenType.ballpoint,
    createdAt: DateTime(2026),
  );
}

void main() {
  group('calculateViewport', () {
    test('calculates viewport from screen coords', () {
      final viewport = ViewportCuller.calculateViewport(
        const Size(1080, 1920),
        const Offset(0, 0),
        1.0,
      );

      expect(viewport.left, 0);
      expect(viewport.top, 0);
      expect(viewport.width, 1080);
      expect(viewport.height, 1920);
    });

    test('accounts for offset and scale', () {
      final viewport = ViewportCuller.calculateViewport(
        const Size(1080, 1920),
        const Offset(-500, -300),
        2.0,
      );

      // topLeft = (-(-500)) / 2 = (250, 150)
      expect(viewport.left, closeTo(250, 1));
      expect(viewport.top, closeTo(150, 1));
      // width = 1080/2 = 540, height = 1920/2 = 960
      expect(viewport.width, closeTo(540, 1));
      expect(viewport.height, closeTo(960, 1));
    });

    test('inflates viewport when rotation is non-zero', () {
      final noRotation = ViewportCuller.calculateViewport(
        const Size(1080, 1920),
        const Offset(0, 0),
        1.0,
      );

      final withRotation = ViewportCuller.calculateViewport(
        const Size(1080, 1920),
        const Offset(0, 0),
        1.0,
        rotation: 0.5,
      );

      expect(withRotation.width, greaterThan(noRotation.width));
      expect(withRotation.height, greaterThan(noRotation.height));
    });
  });

  group('isStrokeVisible', () {
    test('returns true when stroke overlaps viewport', () {
      final stroke = _makeStroke(bounds: const Rect.fromLTWH(50, 50, 100, 100));
      final viewport = const Rect.fromLTWH(0, 0, 200, 200);
      expect(ViewportCuller.isStrokeVisible(stroke, viewport), isTrue);
    });

    test('returns false when stroke is far from viewport', () {
      final stroke = _makeStroke(
        bounds: const Rect.fromLTWH(50000, 50000, 10, 10),
      );
      final viewport = const Rect.fromLTWH(0, 0, 200, 200);
      expect(ViewportCuller.isStrokeVisible(stroke, viewport), isFalse);
    });

    test('margin allows near-viewport strokes to be visible', () {
      final stroke = _makeStroke(bounds: const Rect.fromLTWH(250, 0, 10, 10));
      final viewport = const Rect.fromLTWH(0, 0, 200, 200);

      // With default margin (1000px), stroke is visible
      expect(ViewportCuller.isStrokeVisible(stroke, viewport), isTrue);
    });
  });

  group('filterVisibleStrokes', () {
    test('returns empty for empty input', () {
      final result = ViewportCuller.filterVisibleStrokes(
        [],
        const Rect.fromLTWH(0, 0, 1000, 1000),
      );
      expect(result, isEmpty);
    });

    test('filters out strokes far outside viewport', () {
      final inside = _makeStroke(
        bounds: const Rect.fromLTWH(50, 50, 10, 10),
        id: 'inside',
      );
      final outside = _makeStroke(
        bounds: const Rect.fromLTWH(50000, 50000, 10, 10),
        id: 'outside',
      );

      final viewport = const Rect.fromLTWH(0, 0, 200, 200);
      final result = ViewportCuller.filterVisibleStrokes(
        [inside, outside],
        viewport,
        margin: 0,
      );

      expect(result.length, 1);
      expect(result.first.id, 'inside');
    });
  });

  group('applyAdaptiveLOD', () {
    test('returns all strokes at high zoom (no filtering)', () {
      final strokes = [_makeStroke(bounds: const Rect.fromLTWH(0, 0, 1, 1))];

      // At scale >= 0.5, no LOD filtering
      final result = ViewportCuller.applyAdaptiveLOD(strokes, 1.0);
      expect(result.length, 1);
    });

    test('filters tiny strokes at low zoom', () {
      final bigStroke = _makeStroke(
        bounds: const Rect.fromLTWH(0, 0, 100, 100),
        id: 'big',
      );

      final result = ViewportCuller.applyAdaptiveLOD([bigStroke], 0.1);
      expect(result.length, 1);
    });

    test('returns empty list for empty input', () {
      expect(ViewportCuller.applyAdaptiveLOD([], 0.1), isEmpty);
    });
  });
}
