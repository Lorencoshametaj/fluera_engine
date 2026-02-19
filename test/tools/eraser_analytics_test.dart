import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/tools/eraser/eraser_analytics.dart';

void main() {
  late EraserAnalytics analytics;

  setUp(() {
    analytics = EraserAnalytics();
  });

  // =========================================================================
  // Initial State
  // =========================================================================

  group('initial state', () {
    test('counters start at zero', () {
      expect(analytics.totalStrokesErased, 0);
      expect(analytics.totalAreaCovered, 0.0);
      expect(analytics.totalEraseTime, Duration.zero);
    });

    test('collections start empty', () {
      expect(analytics.dissolvePoints, isEmpty);
      expect(analytics.historySnapshots, isEmpty);
    });
  });

  // =========================================================================
  // Recording
  // =========================================================================

  group('recordErase', () {
    test('increments stroke counter', () {
      analytics.recordErase(const Offset(50, 50), 10.0);
      expect(analytics.totalStrokesErased, 1);
    });

    test('accumulates area covered', () {
      analytics.recordErase(const Offset(50, 50), 10.0);
      // Area = π × r² = π × 100 ≈ 314.16
      expect(analytics.totalAreaCovered, closeTo(314.16, 1.0));
    });

    test('adds dissolve point', () {
      analytics.recordErase(const Offset(50, 50), 10.0);
      expect(analytics.dissolvePoints, hasLength(1));
      expect(analytics.dissolvePoints.first, const Offset(50, 50));
    });

    test('caps dissolve points at maximum', () {
      for (int i = 0; i < 60; i++) {
        analytics.recordErase(Offset(i.toDouble(), 0), 5.0);
      }
      expect(analytics.dissolvePoints.length, lessThanOrEqualTo(50));
    });

    test('multiple erases accumulate', () {
      analytics.recordErase(const Offset(10, 10), 5.0);
      analytics.recordErase(const Offset(20, 20), 5.0);
      analytics.recordErase(const Offset(30, 30), 5.0);
      expect(analytics.totalStrokesErased, 3);
    });
  });

  // =========================================================================
  // Session Tracking
  // =========================================================================

  group('session tracking', () {
    test('session tracking records time', () async {
      analytics.startSession();
      await Future.delayed(const Duration(milliseconds: 50));
      analytics.endSession();
      expect(analytics.totalEraseTime.inMilliseconds, greaterThanOrEqualTo(40));
    });

    test('endSession without startSession is safe', () {
      analytics.endSession(); // should not throw
      expect(analytics.totalEraseTime, Duration.zero);
    });

    test('multiple sessions accumulate', () async {
      analytics.startSession();
      await Future.delayed(const Duration(milliseconds: 30));
      analytics.endSession();

      analytics.startSession();
      await Future.delayed(const Duration(milliseconds: 30));
      analytics.endSession();

      expect(analytics.totalEraseTime.inMilliseconds, greaterThanOrEqualTo(50));
    });
  });

  // =========================================================================
  // Heatmap
  // =========================================================================

  group('heatmap', () {
    test('returns zero for untouched area', () {
      expect(analytics.getHeatmapIntensity(const Offset(100, 100)), 0.0);
    });

    test('increases with repeated touches', () {
      for (int i = 0; i < 5; i++) {
        analytics.recordErase(const Offset(50, 50), 10.0);
      }
      final intensity = analytics.getHeatmapIntensity(const Offset(50, 50));
      expect(intensity, greaterThan(0.0));
      expect(intensity, lessThanOrEqualTo(1.0));
    });

    test('saturates at 1.0 after many touches', () {
      for (int i = 0; i < 20; i++) {
        analytics.recordErase(const Offset(50, 50), 10.0);
      }
      expect(analytics.getHeatmapIntensity(const Offset(50, 50)), 1.0);
    });
  });

  // =========================================================================
  // Snapshots
  // =========================================================================

  group('takeSnapshot', () {
    test('records snapshot', () {
      analytics.takeSnapshot(42);
      expect(analytics.historySnapshots, hasLength(1));
      expect(analytics.historySnapshots.first.$2, 42);
    });

    test('caps snapshots at maximum', () {
      for (int i = 0; i < 60; i++) {
        analytics.takeSnapshot(i);
      }
      expect(analytics.historySnapshots.length, lessThanOrEqualTo(50));
    });
  });

  // =========================================================================
  // Summary
  // =========================================================================

  group('summary', () {
    test('returns formatted string', () {
      analytics.recordErase(const Offset(50, 50), 10.0);
      final summary = analytics.summary;
      expect(summary, contains('1 strokes'));
      expect(summary, contains('px²'));
    });
  });

  // =========================================================================
  // Reset
  // =========================================================================

  group('reset', () {
    test('clears all data', () {
      analytics.recordErase(const Offset(50, 50), 10.0);
      analytics.takeSnapshot(5);
      analytics.reset();

      expect(analytics.totalStrokesErased, 0);
      expect(analytics.totalAreaCovered, 0.0);
      expect(analytics.totalEraseTime, Duration.zero);
      expect(analytics.dissolvePoints, isEmpty);
      expect(analytics.historySnapshots, isEmpty);
      expect(analytics.getHeatmapIntensity(const Offset(50, 50)), 0.0);
    });
  });
}
