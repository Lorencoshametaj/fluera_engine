import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/testing/performance_baseline.dart';

void main() {
  late PerformanceBaseline baseline;

  setUp(() {
    baseline = PerformanceBaseline();
  });

  // ===========================================================================
  // Recording
  // ===========================================================================

  group('PerformanceBaseline - record', () {
    test('records a single measurement', () {
      baseline.record('frameTime', 16.0);
      final s = baseline.stats('frameTime');
      expect(s, isNotNull);
      expect(s!.mean, 16.0);
    });

    test('recordAll stores multiple values', () {
      baseline.recordAll('fps', [60.0, 58.0, 62.0, 59.0, 61.0]);
      final s = baseline.stats('fps');
      expect(s, isNotNull);
      expect(s!.count, 5);
    });

    test('stats for unknown metric returns null', () {
      expect(baseline.stats('unknown'), isNull);
    });
  });

  // ===========================================================================
  // MetricStats
  // ===========================================================================

  group('MetricStats', () {
    test('computes mean correctly', () {
      baseline.recordAll('test', [10.0, 20.0, 30.0]);
      final s = baseline.stats('test')!;
      expect(s.mean, closeTo(20.0, 0.01));
    });

    test('computes min and max', () {
      baseline.recordAll('test', [5.0, 15.0, 10.0]);
      final s = baseline.stats('test')!;
      expect(s.min, 5.0);
      expect(s.max, 15.0);
    });

    test('toJson is a map', () {
      baseline.recordAll('test', [10.0]);
      final json = baseline.stats('test')!.toJson();
      expect(json, isA<Map<String, dynamic>>());
    });

    test('toString is readable', () {
      baseline.recordAll('test', [10.0]);
      expect(baseline.stats('test')!.toString(), isNotEmpty);
    });
  });

  // ===========================================================================
  // Regression check
  // ===========================================================================

  group('PerformanceBaseline - check', () {
    test('no regression when within threshold', () {
      baseline.recordAll('frameTime', [16.0, 16.0, 16.0]);
      final result = baseline.check('frameTime', 17.0, threshold: 0.1);
      expect(result.isRegression, isFalse);
    });

    test('regression detected when above threshold', () {
      baseline.recordAll('frameTime', [16.0, 16.0, 16.0]);
      final result = baseline.check('frameTime', 25.0, threshold: 0.1);
      expect(result.isRegression, isTrue);
    });

    test('check unknown metric returns no regression', () {
      final result = baseline.check('unknown', 100.0);
      expect(result.isRegression, isFalse);
    });
  });

  // ===========================================================================
  // checkAll
  // ===========================================================================

  group('PerformanceBaseline - checkAll', () {
    test('checks multiple metrics at once', () {
      baseline.recordAll('a', [10.0, 10.0]);
      baseline.recordAll('b', [20.0, 20.0]);
      final results = baseline.checkAll({'a': 10.5, 'b': 30.0}, threshold: 0.1);
      expect(results, isNotEmpty);
    });
  });

  // ===========================================================================
  // PerformanceCheckResult
  // ===========================================================================

  group('PerformanceCheckResult', () {
    test('toJson is a map', () {
      baseline.recordAll('test', [10.0]);
      final result = baseline.check('test', 10.0);
      final json = result.toJson();
      expect(json, isA<Map<String, dynamic>>());
    });

    test('toString is readable', () {
      baseline.recordAll('test', [10.0]);
      final result = baseline.check('test', 10.0);
      expect(result.toString(), isNotEmpty);
    });
  });

  // ===========================================================================
  // Clear and toJson
  // ===========================================================================

  group('PerformanceBaseline - clear/toJson', () {
    test('clear removes all metrics', () {
      baseline.record('x', 1.0);
      baseline.clear();
      expect(baseline.stats('x'), isNull);
    });

    test('toJson serializes baseline', () {
      baseline.record('x', 1.0);
      final json = baseline.toJson();
      expect(json, isA<Map<String, dynamic>>());
    });

    test('toString is readable', () {
      baseline.record('x', 1.0);
      expect(baseline.toString(), isNotEmpty);
    });
  });
}
