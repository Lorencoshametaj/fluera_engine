import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/rendering/scene_graph/scene_graph_renderer.dart';

import '../helpers/test_helpers.dart';

void main() {
  group('B.2 decimation cache', () {
    test('repeated lookup at the same step returns the identical list', () {
      final stroke = testStroke(pointCount: 200);
      final a = debugDecimatedPointsCached(stroke, 4);
      final b = debugDecimatedPointsCached(stroke, 4);
      expect(identical(a, b), isTrue,
          reason: 'cache miss on second call would build a new list');
    });

    test('different steps yield different lists for the same stroke', () {
      final stroke = testStroke(pointCount: 200);
      final a = debugDecimatedPointsCached(stroke, 2);
      final b = debugDecimatedPointsCached(stroke, 8);
      expect(identical(a, b), isFalse);
      expect(a.length, greaterThan(b.length));
    });

    test('decimated list always includes the final point', () {
      final stroke = testStroke(pointCount: 50);
      final last = stroke.points.last;
      for (final step in [2, 3, 5, 8]) {
        final out = debugDecimatedPointsCached(stroke, step);
        expect(out.last, last, reason: 'step=$step lost the endpoint');
      }
    });

    test('different strokes get independent cache slots', () {
      final s1 = testStroke(id: 's1', pointCount: 60);
      final s2 = testStroke(id: 's2', pointCount: 60);
      final a = debugDecimatedPointsCached(s1, 4);
      final b = debugDecimatedPointsCached(s2, 4);
      expect(identical(a, b), isFalse);
    });
  });
}
