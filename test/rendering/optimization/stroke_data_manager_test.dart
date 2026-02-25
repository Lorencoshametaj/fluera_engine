import 'package:flutter_test/flutter_test.dart';
import 'dart:ui';
import 'package:nebula_engine/src/rendering/optimization/stroke_data_manager.dart';
import 'package:nebula_engine/src/drawing/models/pro_drawing_point.dart';

List<ProDrawingPoint> _makePoints(int count) {
  return List.generate(
    count,
    (i) => ProDrawingPoint(
      position: Offset(i.toDouble(), i.toDouble()),
      pressure: 0.5,
      timestamp: i * 10,
    ),
  );
}

void main() {
  setUp(() {
    StrokeDataManager.clearAll();
  });

  tearDown(() {
    StrokeDataManager.clearAll();
  });

  group('StrokeDataManager', () {
    group('registerStrokePoints', () {
      test('registers points in permanent storage', () {
        final points = _makePoints(5);
        StrokeDataManager.registerStrokePoints('s1', points);
        expect(StrokeDataManager.totalStrokesCount, 1);
      });

      test('points are immediately available in cache', () {
        final points = _makePoints(5);
        StrokeDataManager.registerStrokePoints('s1', points);
        expect(StrokeDataManager.hasPointsCached('s1'), isTrue);
      });

      test('multiple registrations accumulate', () {
        StrokeDataManager.registerStrokePoints('s1', _makePoints(3));
        StrokeDataManager.registerStrokePoints('s2', _makePoints(4));
        StrokeDataManager.registerStrokePoints('s3', _makePoints(5));
        expect(StrokeDataManager.totalStrokesCount, 3);
      });
    });

    group('unregisterStroke', () {
      test('removes from storage and cache', () {
        StrokeDataManager.registerStrokePoints('s1', _makePoints(5));
        StrokeDataManager.unregisterStroke('s1');
        expect(StrokeDataManager.totalStrokesCount, 0);
        expect(StrokeDataManager.hasPointsCached('s1'), isFalse);
      });

      test('noop for nonexistent stroke', () {
        StrokeDataManager.unregisterStroke('nonexistent');
        expect(StrokeDataManager.totalStrokesCount, 0);
      });
    });

    group('getPoints', () {
      test('returns cached points', () {
        final points = _makePoints(10);
        StrokeDataManager.registerStrokePoints('s1', points);
        final result = StrokeDataManager.getPoints('s1');
        expect(result.length, 10);
      });

      test('returns points from permanent storage when cache is cleared', () {
        final points = _makePoints(7);
        StrokeDataManager.registerStrokePoints('s1', points);
        StrokeDataManager.clearCache();
        final result = StrokeDataManager.getPoints('s1');
        expect(result.length, 7);
      });

      test('returns fallback points when not found', () {
        final fallback = _makePoints(3);
        final result = StrokeDataManager.getPoints(
          'unknown',
          fallbackPoints: fallback,
        );
        expect(result.length, 3);
      });

      test('returns empty list when nothing found', () {
        final result = StrokeDataManager.getPoints('unknown');
        expect(result, isEmpty);
      });
    });

    group('getPointsAsync', () {
      test('returns cached points', () async {
        StrokeDataManager.registerStrokePoints('s1', _makePoints(5));
        final result = await StrokeDataManager.getPointsAsync('s1');
        expect(result.length, 5);
      });

      test('uses loader when no cache or storage', () async {
        final loaderPoints = _makePoints(8);
        StrokeDataManager.setPointsLoader((id) async => loaderPoints);

        final result = await StrokeDataManager.getPointsAsync('s1');
        expect(result.length, 8);
      });

      test('returns empty when loader fails', () async {
        StrokeDataManager.setPointsLoader((id) async {
          throw Exception('Not found');
        });
        final result = await StrokeDataManager.getPointsAsync('s1');
        expect(result, isEmpty);
      });

      test('returns empty when no loader and no data', () async {
        final result = await StrokeDataManager.getPointsAsync('s1');
        expect(result, isEmpty);
      });
    });

    group('hasPointsCached', () {
      test('returns true for cached stroke', () {
        StrokeDataManager.registerStrokePoints('s1', _makePoints(1));
        expect(StrokeDataManager.hasPointsCached('s1'), isTrue);
      });

      test('returns false for unknown stroke', () {
        expect(StrokeDataManager.hasPointsCached('unknown'), isFalse);
      });

      test('still true after clearCache (permanent storage remains)', () {
        StrokeDataManager.registerStrokePoints('s1', _makePoints(1));
        StrokeDataManager.clearCache();
        // permanent storage still has it
        expect(StrokeDataManager.hasPointsCached('s1'), isTrue);
      });
    });

    group('preloadStrokes', () {
      test('loads from permanent storage into cache', () {
        StrokeDataManager.registerStrokePoints('s1', _makePoints(5));
        StrokeDataManager.registerStrokePoints('s2', _makePoints(3));
        StrokeDataManager.clearCache();

        StrokeDataManager.preloadStrokes(['s1', 's2']);
        expect(StrokeDataManager.cachedStrokesCount, 2);
      });

      test('ignores unknown IDs', () {
        StrokeDataManager.preloadStrokes(['unknown1', 'unknown2']);
        expect(StrokeDataManager.cachedStrokesCount, 0);
      });
    });

    group('clearCache', () {
      test('clears cache but keeps permanent storage', () {
        StrokeDataManager.registerStrokePoints('s1', _makePoints(5));
        StrokeDataManager.clearCache();
        expect(StrokeDataManager.cachedStrokesCount, 0);
        expect(StrokeDataManager.totalStrokesCount, 1);
      });
    });

    group('clearAll', () {
      test('clears everything', () {
        StrokeDataManager.registerStrokePoints('s1', _makePoints(5));
        StrokeDataManager.clearAll();
        expect(StrokeDataManager.cachedStrokesCount, 0);
        expect(StrokeDataManager.totalStrokesCount, 0);
      });
    });

    group('stats', () {
      test('reports correct values', () {
        StrokeDataManager.registerStrokePoints('s1', _makePoints(10));
        StrokeDataManager.registerStrokePoints('s2', _makePoints(20));
        final s = StrokeDataManager.stats;
        expect(s['cachedStrokes'], 2);
        expect(s['totalStrokes'], 2);
      });
    });

    group('estimatedCacheMemory', () {
      test('estimates based on point count', () {
        StrokeDataManager.registerStrokePoints('s1', _makePoints(100));
        // 100 points × 40 bytes = 4000 bytes
        expect(StrokeDataManager.estimatedCacheMemory, 4000);
      });
    });
  });
}
