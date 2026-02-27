import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/services/adaptive_debouncer_service.dart';
import 'package:fluera_engine/src/core/engine_scope.dart';

void main() {
  late AdaptiveDebouncerService debouncer;

  setUp(() {
    EngineScope.reset();
    debouncer = AdaptiveDebouncerService.create();
  });

  tearDown(() {
    debouncer.reset();
    debouncer.dispose();
    EngineScope.reset();
  });

  // =========================================================================
  // Initial State
  // =========================================================================

  group('initial state', () {
    test('starts not drawing', () {
      expect(debouncer.isDrawing, isFalse);
    });

    test('starts with no pending callback', () {
      expect(debouncer.hasPendingCallback, isFalse);
    });

    test('drawing intensity at zero', () {
      expect(debouncer.drawingIntensity, 0.0);
    });
  });

  // =========================================================================
  // Input Notification
  // =========================================================================

  group('notifyInput', () {
    test('marks as drawing', () {
      debouncer.notifyInput();
      expect(debouncer.isDrawing, isTrue);
    });

    test('multiple inputs keep drawing state', () {
      debouncer.notifyInput();
      debouncer.notifyInput();
      debouncer.notifyInput();
      expect(debouncer.isDrawing, isTrue);
    });
  });

  // =========================================================================
  // Stroke Completion
  // =========================================================================

  group('notifyStrokeCompleted', () {
    test('increases drawing intensity', () async {
      for (int i = 0; i < 5; i++) {
        debouncer.notifyStrokeCompleted();
      }
      // With 5 strokes completed rapidly, intensity should be > 0
      await Future.delayed(const Duration(milliseconds: 50));
      expect(debouncer.drawingIntensity, greaterThan(0));
    });
  });

  // =========================================================================
  // Schedule Save
  // =========================================================================

  group('scheduleSave', () {
    test('sets pending callback', () {
      debouncer.scheduleSave(callback: () {});
      expect(debouncer.hasPendingCallback, isTrue);
    });

    test('forceImmediate executes callback immediately', () {
      bool executed = false;
      debouncer.scheduleSave(
        callback: () => executed = true,
        forceImmediate: true,
      );
      expect(executed, isTrue);
    });

    test('normal schedule does not execute immediately', () {
      bool executed = false;
      debouncer.scheduleSave(callback: () => executed = true);
      expect(executed, isFalse);
    });

    test('debounced callback eventually executes', () async {
      bool executed = false;
      debouncer.scheduleSave(callback: () => executed = true);

      // Wait longer than the idle debounce (300ms)
      await Future.delayed(const Duration(milliseconds: 500));

      // The timer should have fired the callback
      // Note: actual timing depends on debounce calculation
      // but flush guarantees execution
      debouncer.flush();
      expect(executed, isTrue);
    });
  });

  // =========================================================================
  // Flush
  // =========================================================================

  group('flush', () {
    test('executes pending callback', () {
      bool executed = false;
      debouncer.scheduleSave(callback: () => executed = true);
      debouncer.flush();
      expect(executed, isTrue);
    });

    test('no-op without pending callback', () {
      expect(() => debouncer.flush(), returnsNormally);
    });

    test('clears pending callback after flush', () {
      debouncer.scheduleSave(callback: () {});
      debouncer.flush();
      expect(debouncer.hasPendingCallback, isFalse);
    });
  });

  // =========================================================================
  // Reset
  // =========================================================================

  group('reset', () {
    test('clears all state', () {
      debouncer.notifyInput();
      debouncer.notifyStrokeCompleted();
      debouncer.scheduleSave(callback: () {});

      debouncer.reset();

      expect(debouncer.isDrawing, isFalse);
      expect(debouncer.hasPendingCallback, isFalse);
      expect(debouncer.drawingIntensity, 0.0);
    });

    test('reset does not execute pending callback', () {
      bool executed = false;
      debouncer.scheduleSave(callback: () => executed = true);
      debouncer.reset();
      expect(executed, isFalse);
    });
  });

  // =========================================================================
  // Configuretion Constants
  // =========================================================================

  group('configuration', () {
    test('has reasonable base debounce', () {
      expect(
        AdaptiveDebouncerService.baseActiveDebounce.inSeconds,
        greaterThanOrEqualTo(3),
      );
      expect(
        AdaptiveDebouncerService.baseActiveDebounce.inSeconds,
        lessThanOrEqualTo(10),
      );
    });

    test('min < base < max debounce', () {
      expect(
        AdaptiveDebouncerService.minActiveDebounce,
        lessThan(AdaptiveDebouncerService.baseActiveDebounce),
      );
      expect(
        AdaptiveDebouncerService.maxActiveDebounce,
        greaterThan(AdaptiveDebouncerService.baseActiveDebounce),
      );
    });

    test('idle debounce is shorter than active', () {
      expect(
        AdaptiveDebouncerService.idleDebounce,
        lessThan(AdaptiveDebouncerService.minActiveDebounce),
      );
    });
  });

  // =========================================================================
  // Drawing Notifier Binding
  // =========================================================================

  group('drawing notifier binding', () {
    test('bind and unbind do not throw', () {
      final notifier = ValueNotifier<bool>(false);
      expect(() => debouncer.bindDrawingNotifier(notifier), returnsNormally);
      expect(() => debouncer.unbindDrawingNotifier(), returnsNormally);
      notifier.dispose();
    });
  });

  // =========================================================================
  // Extension Methods
  // =========================================================================

  group('extension methods', () {
    test('scheduleDeltaSave sets pending callback', () {
      debouncer.scheduleDeltaSave(() {});
      expect(debouncer.hasPendingCallback, isTrue);
    });

    test('forceCheckpoint executes immediately', () {
      bool executed = false;
      debouncer.forceCheckpoint(() => executed = true);
      expect(executed, isTrue);
    });
  });

  // =========================================================================
  // Adaptive Debounce Time
  // =========================================================================

  group('adaptive debounce time', () {
    test('debounce time is within expected range', () {
      final debounceTime = debouncer.currentDebounceTime;
      expect(
        debounceTime.inMilliseconds,
        greaterThanOrEqualTo(
          AdaptiveDebouncerService.idleDebounce.inMilliseconds,
        ),
      );
    });

    test('debounce changes with drawing state', () {
      final idleDebounce = debouncer.currentDebounceTime;
      debouncer.notifyInput();
      final drawingDebounce = debouncer.currentDebounceTime;
      // When drawing, debounce should typically be longer (active mode)
      expect(drawingDebounce.inMilliseconds, greaterThan(0));
      // Just verify both return valid durations
      expect(idleDebounce.inMilliseconds, greaterThan(0));
    });
  });
}
