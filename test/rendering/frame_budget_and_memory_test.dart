import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/rendering/optimization/frame_budget_manager.dart';
import 'package:nebula_engine/src/core/engine_scope.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // =========================================================================
  // FrameBudgetManager
  // =========================================================================

  group('FrameBudgetManager', () {
    late FrameBudgetManager manager;

    setUp(() {
      EngineScope.reset();
      manager = FrameBudgetManager.create();
    });

    tearDown(() {
      manager.clearQueue();
      EngineScope.reset();
    });

    // ── Initial State ──────────────────────────────────────────────────

    group('initial state', () {
      test('starts with zero pending tasks', () {
        expect(manager.pendingTasks, 0);
      });

      test('stats returns valid map', () {
        final stats = manager.stats;
        expect(stats, containsPair('pendingTasks', 0));
        expect(stats, containsPair('frameBudgetMs', manager.frameBudgetMs));
        expect(stats, containsPair('isScheduled', false));
      });
    });

    // ── Task Scheduling ────────────────────────────────────────────────

    group('scheduleTask', () {
      test('adds task to queue', () {
        manager.scheduleTask(() async {}, priority: 50);
        expect(manager.pendingTasks, 1);
      });

      test('multiple tasks added to queue', () {
        manager.scheduleTask(() async {}, priority: 10);
        manager.scheduleTask(() async {}, priority: 50);
        manager.scheduleTask(() async {}, priority: 90);
        expect(manager.pendingTasks, 3);
      });
    });

    // ── Queue Management ───────────────────────────────────────────────

    group('clearQueue', () {
      test('removes all tasks', () {
        manager.scheduleTask(() async {}, priority: 50);
        manager.scheduleTask(() async {}, priority: 60);
        manager.clearQueue();
        expect(manager.pendingTasks, 0);
      });
    });

    group('clearLowPriorityTasks', () {
      test('removes only tasks below threshold', () {
        manager.scheduleTask(() async {}, priority: 10, debugLabel: 'low');
        manager.scheduleTask(() async {}, priority: 50, debugLabel: 'mid');
        manager.scheduleTask(() async {}, priority: 90, debugLabel: 'high');

        manager.clearLowPriorityTasks(50);
        expect(manager.pendingTasks, 2); // mid(50) and high(90) remain
      });

      test('keeps all tasks above threshold', () {
        manager.scheduleTask(() async {}, priority: 80);
        manager.scheduleTask(() async {}, priority: 90);

        manager.clearLowPriorityTasks(50);
        expect(manager.pendingTasks, 2);
      });

      test('removes all tasks if all below threshold', () {
        manager.scheduleTask(() async {}, priority: 10);
        manager.scheduleTask(() async {}, priority: 20);

        manager.clearLowPriorityTasks(50);
        expect(manager.pendingTasks, 0);
      });
    });

    // ── Budget Checking ────────────────────────────────────────────────

    group('budget checking', () {
      test('hasRemainingBudget is true initially', () {
        expect(manager.hasRemainingBudget(), isTrue);
      });

      test('shouldYield is false initially', () {
        expect(manager.shouldYield(), isFalse);
      });

      test('measureWork returns the work result', () {
        final result = manager.measureWork(() => 42);
        expect(result, 42);
      });

      test('measureWork works with strings', () {
        final result = manager.measureWork(() => 'hello');
        expect(result, 'hello');
      });
    });

    // ── Configuretion ──────────────────────────────────────────────────

    group('configuration', () {
      test('frame budget is reasonable (8ms for 60fps)', () {
        expect(manager.frameBudgetMs, 8.0);
      });

      test('heavy task threshold is less than frame budget', () {
        expect(
          FrameBudgetManager.heavyTaskThresholdMs,
          lessThan(manager.frameBudgetMs),
        );
      });

      test('max tasks per frame is reasonable', () {
        expect(FrameBudgetManager.maxTasksPerFrame, greaterThan(0));
        expect(FrameBudgetManager.maxTasksPerFrame, lessThanOrEqualTo(20));
      });
    });

    // ── EngineScope ────────────────────────────────────────────────────

    group('EngineScope integration', () {
      test('accessible via EngineScope.current', () {
        final scopeManager = EngineScope.current.frameBudgetManager;
        expect(scopeManager, isNotNull);
        expect(scopeManager, isA<FrameBudgetManager>());
      });
    });
  });

  // =========================================================================
  // BudgetedTask
  // =========================================================================

  group('BudgetedTask', () {
    test('stores all properties', () {
      final task = BudgetedTask(
        task: () async {},
        priority: 75.0,
        estimatedMs: 3.0,
        debugLabel: 'test-task',
      );
      expect(task.priority, 75.0);
      expect(task.estimatedMs, 3.0);
      expect(task.debugLabel, 'test-task');
    });

    test('debugLabel is optional', () {
      final task = BudgetedTask(
        task: () async {},
        priority: 50.0,
        estimatedMs: 2.0,
      );
      expect(task.debugLabel, isNull);
    });
  });

  // =========================================================================
  // MemoryPressureHandler
  // =========================================================================

  group('MemoryPressureHandler', () {
    late MemoryPressureHandler handler;

    setUp(() {
      EngineScope.reset();
      handler = MemoryPressureHandler.create();
    });

    tearDown(() {
      EngineScope.reset();
    });

    // ── Initial State ──────────────────────────────────────────────────

    group('initial state', () {
      test('starts at normal level', () {
        expect(handler.currentLevel, MemoryPressureLevel.normal);
      });
    });

    // ── Callback Registration ──────────────────────────────────────────

    group('registerCallback', () {
      test('registered callback is called on pressure change', () {
        MemoryPressureLevel? receivedLevel;
        handler.registerCallback((level) => receivedLevel = level);

        handler.notifyPressure(MemoryPressureLevel.warning);
        expect(receivedLevel, MemoryPressureLevel.warning);
      });

      test('multiple callbacks all receive notification', () {
        MemoryPressureLevel? level1, level2;
        handler.registerCallback((level) => level1 = level);
        handler.registerCallback((level) => level2 = level);

        handler.notifyPressure(MemoryPressureLevel.critical);
        expect(level1, MemoryPressureLevel.critical);
        expect(level2, MemoryPressureLevel.critical);
      });
    });

    group('unregisterCallback', () {
      test('unregistered callback is not called', () {
        int callCount = 0;
        void callback(MemoryPressureLevel level) => callCount++;
        handler.registerCallback(callback);
        handler.unregisterCallback(callback);

        handler.notifyPressure(MemoryPressureLevel.warning);
        expect(callCount, 0);
      });
    });

    // ── Notify Pressure ────────────────────────────────────────────────

    group('notifyPressure', () {
      test('updates current level', () {
        handler.notifyPressure(MemoryPressureLevel.warning);
        expect(handler.currentLevel, MemoryPressureLevel.warning);
      });

      test('does not notify if same level', () {
        int callCount = 0;
        handler.registerCallback((level) => callCount++);

        handler.notifyPressure(MemoryPressureLevel.warning);
        handler.notifyPressure(MemoryPressureLevel.warning); // same level
        expect(callCount, 1);
      });

      test('notifies on level transitions', () {
        final levels = <MemoryPressureLevel>[];
        handler.registerCallback((level) => levels.add(level));

        handler.notifyPressure(MemoryPressureLevel.warning);
        handler.notifyPressure(MemoryPressureLevel.critical);
        handler.notifyPressure(MemoryPressureLevel.normal);

        expect(levels, [
          MemoryPressureLevel.warning,
          MemoryPressureLevel.critical,
          MemoryPressureLevel.normal,
        ]);
      });
    });

    // ── Simulate Pressure ──────────────────────────────────────────────

    group('simulatePressure', () {
      test('delegates to notifyPressure', () {
        MemoryPressureLevel? received;
        handler.registerCallback((level) => received = level);

        handler.simulatePressure(MemoryPressureLevel.critical);
        expect(received, MemoryPressureLevel.critical);
        expect(handler.currentLevel, MemoryPressureLevel.critical);
      });
    });

    // ── Resilience ─────────────────────────────────────────────────────

    group('resilience', () {
      test('throwing callback does not break other callbacks', () {
        MemoryPressureLevel? received;
        handler.registerCallback((_) => throw 'boom');
        handler.registerCallback((level) => received = level);

        handler.notifyPressure(MemoryPressureLevel.warning);
        expect(received, MemoryPressureLevel.warning);
      });
    });

    // ── Configuretion ──────────────────────────────────────────────────

    group('configuration', () {
      test('warning threshold is above critical', () {
        expect(
          MemoryPressureHandler.warningThresholdMB,
          greaterThan(MemoryPressureHandler.criticalThresholdMB),
        );
      });
    });

    // ── Enum ───────────────────────────────────────────────────────────

    group('MemoryPressureLevel', () {
      test('has three values', () {
        expect(MemoryPressureLevel.values.length, 3);
      });

      test('contains expected levels', () {
        expect(
          MemoryPressureLevel.values,
          contains(MemoryPressureLevel.normal),
        );
        expect(
          MemoryPressureLevel.values,
          contains(MemoryPressureLevel.warning),
        );
        expect(
          MemoryPressureLevel.values,
          contains(MemoryPressureLevel.critical),
        );
      });
    });

    // ── EngineScope ────────────────────────────────────────────────────

    group('EngineScope integration', () {
      test('accessible via EngineScope.current', () {
        final scopeHandler = EngineScope.current.memoryPressureHandler;
        expect(scopeHandler, isNotNull);
        expect(scopeHandler, isA<MemoryPressureHandler>());
      });
    });
  });
}
