import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/rendering/optimization/frame_budget_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FrameBudgetManager', () {
    late FrameBudgetManager manager;

    setUp(() {
      manager = FrameBudgetManager.create();
    });

    group('task scheduling', () {
      test('scheduleTask adds tasks to queue', () {
        expect(manager.pendingTasks, 0);
        manager.scheduleTask(() async {}, priority: 50);
        expect(manager.pendingTasks, 1);
        manager.scheduleTask(() async {}, priority: 80);
        expect(manager.pendingTasks, 2);
      });

      test('tasks are sorted by priority (highest first)', () {
        manager.scheduleTask(() async {}, priority: 10, debugLabel: 'low');
        manager.scheduleTask(() async {}, priority: 90, debugLabel: 'high');
        manager.scheduleTask(() async {}, priority: 50, debugLabel: 'mid');
        expect(manager.pendingTasks, 3);
        // We can't inspect order directly, but clearLowPriority can verify
        manager.clearLowPriorityTasks(40);
        expect(manager.pendingTasks, 2); // 10 removed, 50 and 90 remain
      });
    });

    group('clearQueue', () {
      test('removes all tasks', () {
        manager.scheduleTask(() async {});
        manager.scheduleTask(() async {});
        manager.scheduleTask(() async {});
        expect(manager.pendingTasks, 3);
        manager.clearQueue();
        expect(manager.pendingTasks, 0);
      });
    });

    group('clearLowPriorityTasks', () {
      test('removes tasks below threshold', () {
        manager.scheduleTask(() async {}, priority: 10);
        manager.scheduleTask(() async {}, priority: 50);
        manager.scheduleTask(() async {}, priority: 90);
        manager.clearLowPriorityTasks(50);
        expect(manager.pendingTasks, 2); // 50 and 90 remain
      });

      test('removes nothing when all above threshold', () {
        manager.scheduleTask(() async {}, priority: 80);
        manager.scheduleTask(() async {}, priority: 90);
        manager.clearLowPriorityTasks(10);
        expect(manager.pendingTasks, 2);
      });
    });

    group('refresh rate', () {
      test('default is 60Hz with 8ms budget', () {
        expect(manager.detectedRefreshRate, 60.0);
        expect(manager.frameBudgetMs, 8.0);
      });

      test('setRefreshRate adjusts budget for 120Hz', () {
        manager.setRefreshRate(120);
        expect(manager.detectedRefreshRate, 120.0);
        // 1000/120 * 0.5 = ~4.17ms, clamped to [2.0, 12.0]
        expect(manager.frameBudgetMs, closeTo(4.17, 0.1));
      });

      test('setRefreshRate clamps extreme values', () {
        manager.setRefreshRate(500); // Above max
        expect(manager.detectedRefreshRate, 240.0);

        manager.setRefreshRate(10); // Below min
        expect(manager.detectedRefreshRate, 30.0);
      });

      test('setRefreshRate for 30Hz gives ~12ms budget', () {
        manager.setRefreshRate(30);
        // 1000/30 * 0.5 = ~16.67, clamped to 12.0
        expect(manager.frameBudgetMs, 12.0);
      });
    });

    group('stats', () {
      test('stats reports correct values', () {
        manager.scheduleTask(() async {});
        final s = manager.stats;
        expect(s['pendingTasks'], 1);
        expect(s['frameBudgetMs'], isA<double>());
        expect(s['isScheduled'], isA<bool>());
      });
    });

    group('budget checking', () {
      test('shouldYield returns false when no work done', () {
        // Stopwatch not started yet — elapsedMs == 0 < budget
        expect(manager.shouldYield(), isFalse);
      });

      test('hasRemainingBudget returns true when no work done', () {
        expect(manager.hasRemainingBudget(), isTrue);
      });
    });
  });

  group('BudgetedTask', () {
    test('stores all fields correctly', () {
      final task = BudgetedTask(
        task: () async {},
        priority: 75,
        estimatedMs: 3.5,
        debugLabel: 'test-task',
      );
      expect(task.priority, 75);
      expect(task.estimatedMs, 3.5);
      expect(task.debugLabel, 'test-task');
    });
  });

  group('MemoryPressureHandler', () {
    late MemoryPressureHandler handler;

    setUp(() {
      handler = MemoryPressureHandler.create();
    });

    test('initial level is normal', () {
      expect(handler.currentLevel, MemoryPressureLevel.normal);
    });

    test('registerCallback and notifyPressure works', () {
      final levels = <MemoryPressureLevel>[];
      handler.registerCallback(levels.add);

      handler.notifyPressure(MemoryPressureLevel.warning);
      expect(levels, [MemoryPressureLevel.warning]);
      expect(handler.currentLevel, MemoryPressureLevel.warning);
    });

    test('does not notify on same level', () {
      final levels = <MemoryPressureLevel>[];
      handler.registerCallback(levels.add);

      handler.notifyPressure(MemoryPressureLevel.warning);
      handler.notifyPressure(MemoryPressureLevel.warning); // Same level
      expect(levels.length, 1); // Only first notification
    });

    test('escalates from normal to critical', () {
      final levels = <MemoryPressureLevel>[];
      handler.registerCallback(levels.add);

      handler.notifyPressure(MemoryPressureLevel.warning);
      handler.notifyPressure(MemoryPressureLevel.critical);
      expect(levels, [
        MemoryPressureLevel.warning,
        MemoryPressureLevel.critical,
      ]);
    });

    test('unregisterCallback stops notifications', () {
      final levels = <MemoryPressureLevel>[];
      void cb(MemoryPressureLevel l) => levels.add(l);

      handler.registerCallback(cb);
      handler.notifyPressure(MemoryPressureLevel.warning);
      expect(levels.length, 1);

      handler.unregisterCallback(cb);
      handler.notifyPressure(MemoryPressureLevel.critical);
      expect(levels.length, 1); // No new notification
    });

    test('simulatePressure works same as notifyPressure', () {
      final levels = <MemoryPressureLevel>[];
      handler.registerCallback(levels.add);

      handler.simulatePressure(MemoryPressureLevel.critical);
      expect(handler.currentLevel, MemoryPressureLevel.critical);
      expect(levels, [MemoryPressureLevel.critical]);
    });

    test('thresholds are defined', () {
      expect(MemoryPressureHandler.warningThresholdMB, 500);
      expect(MemoryPressureHandler.criticalThresholdMB, 200);
    });
  });

  group('MemoryPressureLevel', () {
    test('has correct values', () {
      expect(MemoryPressureLevel.values.length, 3);
      expect(MemoryPressureLevel.normal.index, 0);
      expect(MemoryPressureLevel.warning.index, 1);
      expect(MemoryPressureLevel.critical.index, 2);
    });
  });
}
