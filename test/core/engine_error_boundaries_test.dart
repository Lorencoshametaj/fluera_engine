import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/engine_error_boundaries.dart';

void main() {
  late EngineErrorBoundaries boundaries;

  setUp(() {
    boundaries = EngineErrorBoundaries();
  });

  tearDown(() {
    boundaries.dispose();
  });

  // ═══════════════════════════════════════════════════════════════════
  // 1. Plugin Error Boundary
  // ═══════════════════════════════════════════════════════════════════

  group('Plugin Error Boundary', () {
    test('successful plugin returns result', () {
      final result = boundaries.executePlugin('my-plugin', () => 42);
      expect(result, 42);
    });

    test('crashing plugin returns fallback', () {
      final result = boundaries.executePlugin<int>(
        'bad-plugin',
        () => throw Exception('crash'),
        fallback: -1,
      );
      expect(result, -1);
    });

    test('plugin not disabled after 1 failure', () {
      boundaries.executePlugin('p1', () => throw 'oops');
      expect(boundaries.isPluginDisabled('p1'), isFalse);
    });

    test('plugin auto-disabled after threshold failures', () {
      for (int i = 0; i < EngineErrorBoundaries.pluginDisableThreshold; i++) {
        boundaries.executePlugin('p1', () => throw 'crash $i');
      }
      expect(boundaries.isPluginDisabled('p1'), isTrue);
    });

    test('disabled plugin returns fallback without calling action', () {
      // Disable it
      for (int i = 0; i < EngineErrorBoundaries.pluginDisableThreshold; i++) {
        boundaries.executePlugin('p1', () => throw 'crash');
      }
      // Now it should not execute
      var called = false;
      boundaries.executePlugin('p1', () {
        called = true;
        return 1;
      });
      expect(called, isFalse);
    });

    test('reenablePlugin resets disabled state', () {
      for (int i = 0; i < EngineErrorBoundaries.pluginDisableThreshold; i++) {
        boundaries.executePlugin('p1', () => throw 'crash');
      }
      expect(boundaries.isPluginDisabled('p1'), isTrue);

      boundaries.reenablePlugin('p1');
      expect(boundaries.isPluginDisabled('p1'), isFalse);
    });

    test('success resets failure count', () {
      // 4 failures (just below threshold)
      for (
        int i = 0;
        i < EngineErrorBoundaries.pluginDisableThreshold - 1;
        i++
      ) {
        boundaries.executePlugin('p1', () => throw 'crash');
      }
      // 1 success → resets
      boundaries.executePlugin('p1', () => 'ok');

      // 4 more failures → still not disabled (reset worked)
      for (
        int i = 0;
        i < EngineErrorBoundaries.pluginDisableThreshold - 1;
        i++
      ) {
        boundaries.executePlugin('p1', () => throw 'crash');
      }
      expect(boundaries.isPluginDisabled('p1'), isFalse);
    });

    test('error stream emits on crash', () async {
      final errors = <BoundaryError>[];
      boundaries.onError.listen(errors.add);

      boundaries.executePlugin('p1', () => throw 'boom');
      await Future.delayed(Duration.zero);

      expect(errors.length, 1);
      expect(errors.first.type, BoundaryErrorType.pluginCrash);
      expect(errors.first.source, contains('p1'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 2. Watchdog Timer
  // ═══════════════════════════════════════════════════════════════════

  group('Watchdog Timer', () {
    test('returns result on success', () async {
      final result = await boundaries.withWatchdog<int>(
        'fast-op',
        () async => 42,
        fallback: -1,
        timeout: const Duration(seconds: 5),
      );
      expect(result, 42);
    });

    test('returns fallback on timeout', () async {
      final result = await boundaries.withWatchdog<int>(
        'slow-op',
        () async {
          await Future.delayed(const Duration(seconds: 5));
          return 42;
        },
        fallback: -1,
        timeout: const Duration(milliseconds: 50),
      );
      expect(result, -1);
    });

    test('returns fallback on error', () async {
      final result = await boundaries.withWatchdog<int>(
        'crash-op',
        () => Future<int>.error(Exception('boom')),
        fallback: -1,
      );
      expect(result, -1);
    });

    test('emits timeout error', () async {
      final errors = <BoundaryError>[];
      boundaries.onError.listen(errors.add);

      await boundaries.withWatchdog<int>(
        'timeout-op',
        () => Future.delayed(const Duration(seconds: 5), () => 1),
        fallback: -1,
        timeout: const Duration(milliseconds: 50),
      );

      // Let stream controller deliver
      await Future.delayed(const Duration(milliseconds: 50));
      expect(
        errors.any((e) => e.type == BoundaryErrorType.watchdogTimeout),
        isTrue,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 3. Safe Execution
  // ═══════════════════════════════════════════════════════════════════

  group('Safe Execution', () {
    test('returns result on success', () {
      final result = boundaries.withSafeExecution<int>(
        'safe-op',
        () => 42,
        fallback: -1,
      );
      expect(result, 42);
    });

    test('returns fallback on error', () {
      final result = boundaries.withSafeExecution<int>(
        'crash-op',
        () => throw Exception('boom'),
        fallback: -1,
      );
      expect(result, -1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 4. Graceful Degradation
  // ═══════════════════════════════════════════════════════════════════

  group('Graceful Degradation', () {
    test('starts at none', () {
      expect(boundaries.currentDegradation, DegradationLevel.none);
    });

    test('transitions to reduced under memory pressure', () {
      boundaries.updateDegradation(memoryUsageMB: 520, frameTimeMs: 10);
      expect(boundaries.currentDegradation, DegradationLevel.reduced);
    });

    test('transitions to survival under critical pressure', () {
      boundaries.updateDegradation(memoryUsageMB: 800, frameTimeMs: 60);
      expect(boundaries.currentDegradation, DegradationLevel.survival);
    });

    test('recovers to none when pressure drops', () {
      boundaries.updateDegradation(memoryUsageMB: 800, frameTimeMs: 60);
      boundaries.updateDegradation(memoryUsageMB: 200, frameTimeMs: 10);
      expect(boundaries.currentDegradation, DegradationLevel.none);
    });

    test('emits degradation changes', () async {
      final levels = <DegradationLevel>[];
      boundaries.onDegradationChange.listen(levels.add);

      boundaries.updateDegradation(memoryUsageMB: 800, frameTimeMs: 60);
      await Future.delayed(Duration.zero);

      expect(levels, contains(DegradationLevel.survival));
    });

    test('shouldEnable disables shadows in reduced mode', () {
      boundaries.updateDegradation(memoryUsageMB: 520, frameTimeMs: 10);
      expect(boundaries.shouldEnable(DegradationFeature.shadows), isFalse);
      expect(
        boundaries.shouldEnable(DegradationFeature.basicRendering),
        isTrue,
      );
    });

    test('shouldEnable allows AA in reduced mode', () {
      boundaries.updateDegradation(memoryUsageMB: 520, frameTimeMs: 10);
      expect(boundaries.shouldEnable(DegradationFeature.antiAliasing), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 5. BoundaryError model
  // ═══════════════════════════════════════════════════════════════════

  group('BoundaryError', () {
    test('toString is readable', () {
      final error = BoundaryError(
        source: 'TestPlugin',
        type: BoundaryErrorType.pluginCrash,
        error: Exception('test'),
        message: 'Plugin crashed',
      );
      expect(error.toString(), contains('pluginCrash'));
      expect(error.timestamp, isNotNull);
    });
  });
}
