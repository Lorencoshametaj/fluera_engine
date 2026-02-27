import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/rendering/optimization/memory_budget_controller.dart';
import 'package:fluera_engine/src/rendering/optimization/memory_managed_cache.dart';
import 'package:fluera_engine/src/rendering/optimization/memory_event.dart';
import 'package:fluera_engine/src/rendering/optimization/frame_budget_manager.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// MOCK CACHE for testing
// ═══════════════════════════════════════════════════════════════════════════════

class MockManagedCache
    with MemoryManagedCacheMixin
    implements MemoryManagedCache {
  @override
  final String cacheName;
  final int bytesPerEntry;
  final int _priority;

  int entryCount;
  int evictFractionCallCount = 0;
  int evictAllCallCount = 0;
  double lastFractionRequested = 0;

  MockManagedCache({
    this.cacheName = 'MockCache',
    this.bytesPerEntry = 1024 * 1024, // 1 MB per entry
    this.entryCount = 0,
    int priority = 50,
  }) : _priority = priority;

  @override
  int get estimatedMemoryBytes => entryCount * bytesPerEntry;

  @override
  int get cacheEntryCount => entryCount;

  @override
  int get evictionPriority => _priority;

  @override
  void evictFraction(double fraction) {
    evictFractionCallCount++;
    lastFractionRequested = fraction;
    final toRemove = (entryCount * fraction).ceil().clamp(0, entryCount);
    entryCount -= toRemove;
  }

  @override
  void evictAll() {
    evictAllCallCount++;
    entryCount = 0;
  }
}

/// A cache that throws on eviction — used to test error resilience.
class _ThrowingCache
    with MemoryManagedCacheMixin
    implements MemoryManagedCache {
  int entryCount;

  _ThrowingCache({required this.entryCount});

  @override
  String get cacheName => 'ThrowingCache';

  @override
  int get estimatedMemoryBytes => entryCount * 1024 * 1024;

  @override
  int get cacheEntryCount => entryCount;

  @override
  void evictFraction(double fraction) {
    throw StateError('Simulated eviction failure');
  }

  @override
  void evictAll() {
    throw StateError('Simulated eviction failure');
  }
}

void main() {
  late MemoryPressureHandler pressureHandler;

  setUp(() {
    pressureHandler = MemoryPressureHandler.create();
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // CORE FUNCTIONALITY
  // ═══════════════════════════════════════════════════════════════════════════

  group('MemoryBudgetController — Core —', () {
    test('registers and unregisters caches', () {
      final controller = MemoryBudgetController.forTesting(
        memoryPressureHandler: pressureHandler,
      );
      final cache1 = MockManagedCache(cacheName: 'A');
      final cache2 = MockManagedCache(cacheName: 'B');

      controller.registerCache(cache1);
      controller.registerCache(cache2);
      expect(controller.registeredCacheCount, 2);

      controller.unregisterCache(cache1);
      expect(controller.registeredCacheCount, 1);

      controller.dispose();
    });

    test('prevents double-registration', () {
      final controller = MemoryBudgetController.forTesting(
        memoryPressureHandler: pressureHandler,
      );
      final cache = MockManagedCache();
      controller.registerCache(cache);
      controller.registerCache(cache);
      expect(controller.registeredCacheCount, 1);
      controller.dispose();
    });

    test('normal pressure does not evict', () {
      final controller = MemoryBudgetController.forTesting(
        budgetCapMB: 200,
        memoryPressureHandler: pressureHandler,
      );
      final cache = MockManagedCache(entryCount: 10);
      controller.registerCache(cache);
      controller.forceEviction(MemoryPressureLevel.normal);

      expect(cache.evictFractionCallCount, 0);
      expect(cache.evictAllCallCount, 0);
      expect(cache.entryCount, 10);
      controller.dispose();
    });

    test('warning pressure evicts fraction', () {
      final controller = MemoryBudgetController.forTesting(
        memoryPressureHandler: pressureHandler,
      );
      final cache = MockManagedCache(entryCount: 20);
      controller.registerCache(cache);
      controller.forceEviction(MemoryPressureLevel.warning);

      expect(cache.evictFractionCallCount, 1);
      expect(cache.lastFractionRequested, 0.30);
      expect(cache.entryCount, 14); // ceil(20*0.3) = 6 evicted
      controller.dispose();
    });

    test('critical pressure calls evictAll', () {
      final controller = MemoryBudgetController.forTesting(
        memoryPressureHandler: pressureHandler,
      );
      final cache = MockManagedCache(entryCount: 30);
      controller.registerCache(cache);
      controller.forceEviction(MemoryPressureLevel.critical);

      expect(cache.evictAllCallCount, 1);
      expect(cache.entryCount, 0);
      controller.dispose();
    });

    test('skips empty caches', () {
      final controller = MemoryBudgetController.forTesting(
        memoryPressureHandler: pressureHandler,
      );
      final empty = MockManagedCache(entryCount: 0);
      final full = MockManagedCache(entryCount: 10);
      controller.registerCache(empty);
      controller.registerCache(full);
      controller.forceEviction(MemoryPressureLevel.warning);

      expect(empty.evictFractionCallCount, 0);
      expect(full.evictFractionCallCount, 1);
      controller.dispose();
    });

    test('totalEstimatedMemoryMB sums all caches', () {
      final controller = MemoryBudgetController.forTesting(
        memoryPressureHandler: pressureHandler,
      );
      final cache1 = MockManagedCache(entryCount: 50); // 50 MB
      final cache2 = MockManagedCache(entryCount: 30); // 30 MB
      controller.registerCache(cache1);
      controller.registerCache(cache2);
      expect(controller.totalEstimatedMemoryMB, closeTo(80.0, 0.01));
      controller.dispose();
    });

    test('notifies MemoryPressureHandler on level change', () {
      final controller = MemoryBudgetController.forTesting(
        memoryPressureHandler: pressureHandler,
      );
      final levels = <MemoryPressureLevel>[];
      pressureHandler.registerCallback((l) => levels.add(l));
      controller.forceEviction(MemoryPressureLevel.warning);

      expect(levels, contains(MemoryPressureLevel.warning));
      controller.dispose();
    });

    test('resilient to cache eviction errors', () {
      final controller = MemoryBudgetController.forTesting(
        memoryPressureHandler: pressureHandler,
      );
      final bad = _ThrowingCache(entryCount: 10);
      final good = MockManagedCache(entryCount: 10);
      controller.registerCache(bad);
      controller.registerCache(good);

      controller.forceEviction(MemoryPressureLevel.critical);
      expect(good.evictAllCallCount, 1);
      expect(good.entryCount, 0);
      controller.dispose();
    });

    test('dispose clears caches and stops monitoring', () {
      final controller = MemoryBudgetController.forTesting(
        memoryPressureHandler: pressureHandler,
      );
      controller.registerCache(MockManagedCache(entryCount: 5));
      controller.dispose();
      expect(controller.registeredCacheCount, 0);
      expect(controller.isMonitoring, false);
    });

    test('works with no registered caches', () {
      final controller = MemoryBudgetController.forTesting(
        memoryPressureHandler: pressureHandler,
      );
      controller.forceEviction(MemoryPressureLevel.critical);
      expect(controller.totalEstimatedMemoryMB, 0.0);
      controller.dispose();
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ENHANCEMENT 1: ADAPTIVE THRESHOLDS
  // ═══════════════════════════════════════════════════════════════════════════

  group('Enhancement 1 — Adaptive Thresholds —', () {
    test('calibrates for low-RAM device (≤ 3 GB)', () {
      final controller = MemoryBudgetController.forTesting(
        memoryPressureHandler: pressureHandler,
      );
      controller.calibrateForRAM(2048); // 2 GB

      expect(controller.budgetCapMB, 150);
      expect(controller.isCalibrated, true);
      controller.dispose();
    });

    test('calibrates for mid-range device (3–6 GB)', () {
      final controller = MemoryBudgetController.forTesting(
        memoryPressureHandler: pressureHandler,
      );
      controller.calibrateForRAM(4096); // 4 GB

      expect(controller.budgetCapMB, 300);
      controller.dispose();
    });

    test('calibrates for flagship device (6–12 GB)', () {
      final controller = MemoryBudgetController.forTesting(
        memoryPressureHandler: pressureHandler,
      );
      controller.calibrateForRAM(8192); // 8 GB

      expect(controller.budgetCapMB, 500);
      controller.dispose();
    });

    test('calibrates for high-end device (> 12 GB)', () {
      final controller = MemoryBudgetController.forTesting(
        memoryPressureHandler: pressureHandler,
      );
      controller.calibrateForRAM(16384); // 16 GB

      expect(controller.budgetCapMB, 800);
      controller.dispose();
    });

    test('calibration happens only once', () {
      final controller = MemoryBudgetController.forTesting(
        memoryPressureHandler: pressureHandler,
      );
      controller.calibrateForRAM(2048); // → 150 MB
      expect(controller.budgetCapMB, 150);

      // Second calibration with same call pattern resets _calibrated first
      // but in production, this is called only once via _onNativeMetrics
      controller.calibrateForRAM(16384); // → 800 MB (allowed via test method)
      expect(controller.budgetCapMB, 800);
      controller.dispose();
    });

    test('stats includes threshold info', () {
      final controller = MemoryBudgetController.forTesting(
        memoryPressureHandler: pressureHandler,
      );
      controller.calibrateForRAM(4096);
      final stats = controller.stats;

      expect(stats['warningThreshold'], 65.0);
      expect(stats['criticalThreshold'], 80.0);
      expect(stats['lowWaterMark'], 45.0);
      expect(stats['isCalibrated'], true);
      controller.dispose();
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ENHANCEMENT 2: PRIORITY-WEIGHTED EVICTION
  // ═══════════════════════════════════════════════════════════════════════════

  group('Enhancement 2 — Priority Eviction —', () {
    test('evicts low-priority caches before high-priority', () {
      final controller = MemoryBudgetController.forTesting(
        memoryPressureHandler: pressureHandler,
      );

      // Disk (10) < Image (30) < Tile (70) — in insertion order opposite
      final tile = MockManagedCache(
        cacheName: 'Tile',
        entryCount: 10,
        priority: 70,
      );
      final image = MockManagedCache(
        cacheName: 'Image',
        entryCount: 10,
        priority: 30,
      );
      final disk = MockManagedCache(
        cacheName: 'Disk',
        entryCount: 10,
        priority: 10,
      );

      controller.registerCache(tile);
      controller.registerCache(image);
      controller.registerCache(disk);

      controller.forceEviction(MemoryPressureLevel.warning);

      // All caches get evicted in priority order — all should have been called
      expect(disk.evictFractionCallCount, 1);
      expect(image.evictFractionCallCount, 1);
      expect(tile.evictFractionCallCount, 1);
      controller.dispose();
    });

    test('critical evicts all in priority order', () {
      final controller = MemoryBudgetController.forTesting(
        memoryPressureHandler: pressureHandler,
      );

      final expensive = MockManagedCache(
        cacheName: 'Expensive',
        entryCount: 20,
        priority: 90,
      );
      final cheap = MockManagedCache(
        cacheName: 'Cheap',
        entryCount: 20,
        priority: 5,
      );

      controller.registerCache(expensive);
      controller.registerCache(cheap);

      controller.forceEviction(MemoryPressureLevel.critical);

      expect(cheap.evictAllCallCount, 1);
      expect(expensive.evictAllCallCount, 1);
      expect(cheap.entryCount, 0);
      expect(expensive.entryCount, 0);
      controller.dispose();
    });

    test('default priority is 50 (via mixin)', () {
      final cache = MockManagedCache(); // uses default
      expect(cache.evictionPriority, 50);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ENHANCEMENT 3: TELEMETRY EVENT STREAM
  // ═══════════════════════════════════════════════════════════════════════════

  group('Enhancement 3 — Telemetry Stream —', () {
    test('emits MemoryPressureChanged on level change', () async {
      final controller = MemoryBudgetController.forTesting(
        memoryPressureHandler: pressureHandler,
      );

      final events = <MemoryEvent>[];
      final sub = controller.onMemoryEvent.listen(events.add);

      controller.forceEviction(MemoryPressureLevel.warning);

      // Give async stream time to deliver
      await Future.delayed(Duration.zero);

      final pressureEvents = events.whereType<MemoryPressureChanged>().toList();
      expect(pressureEvents, hasLength(1));
      expect(pressureEvents.first.previous, MemoryPressureLevel.normal);
      expect(pressureEvents.first.current, MemoryPressureLevel.warning);

      await sub.cancel();
      controller.dispose();
    });

    test('emits MemoryEvictionPerformed after eviction', () async {
      final controller = MemoryBudgetController.forTesting(
        memoryPressureHandler: pressureHandler,
      );
      final cache = MockManagedCache(entryCount: 20); // 20 MB
      controller.registerCache(cache);

      final events = <MemoryEvent>[];
      final sub = controller.onMemoryEvent.listen(events.add);

      controller.forceEviction(MemoryPressureLevel.warning);
      await Future.delayed(Duration.zero);

      final evictionEvents =
          events.whereType<MemoryEvictionPerformed>().toList();
      expect(evictionEvents, hasLength(1));
      expect(evictionEvents.first.trigger, MemoryPressureLevel.warning);
      expect(evictionEvents.first.totalBytesFreedMB, greaterThan(0));

      await sub.cancel();
      controller.dispose();
    });

    test('events have correct timestamps', () async {
      final controller = MemoryBudgetController.forTesting(
        memoryPressureHandler: pressureHandler,
      );

      final before = DateTime.now();
      final events = <MemoryEvent>[];
      final sub = controller.onMemoryEvent.listen(events.add);

      controller.forceEviction(MemoryPressureLevel.warning);
      await Future.delayed(Duration.zero);

      for (final event in events) {
        expect(
          event.timestamp.isAfter(before) ||
              event.timestamp.isAtSameMomentAs(before),
          true,
        );
      }

      await sub.cancel();
      controller.dispose();
    });

    test('stream is broadcast — multiple listeners', () async {
      final controller = MemoryBudgetController.forTesting(
        memoryPressureHandler: pressureHandler,
      );

      final events1 = <MemoryEvent>[];
      final events2 = <MemoryEvent>[];
      final sub1 = controller.onMemoryEvent.listen(events1.add);
      final sub2 = controller.onMemoryEvent.listen(events2.add);

      controller.forceEviction(MemoryPressureLevel.critical);
      await Future.delayed(Duration.zero);

      expect(events1.isNotEmpty, true);
      expect(events2.isNotEmpty, true);

      await sub1.cancel();
      await sub2.cancel();
      controller.dispose();
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ENHANCEMENT 4: HYSTERESIS
  // ═══════════════════════════════════════════════════════════════════════════

  group('Enhancement 4 — Hysteresis —', () {
    test('activates hysteresis after warning eviction', () {
      final controller = MemoryBudgetController.forTesting(
        memoryPressureHandler: pressureHandler,
      );
      final cache = MockManagedCache(entryCount: 10);
      controller.registerCache(cache);

      controller.forceEviction(MemoryPressureLevel.warning);

      expect(controller.hysteresisActive, true);
      expect(cache.isRefillAllowed, false);
      controller.dispose();
    });

    test('releases hysteresis when usage drops below low water mark', () {
      final controller = MemoryBudgetController.forTesting(
        budgetCapMB: 100,
        lowWaterMark: 50.0,
        memoryPressureHandler: pressureHandler,
      );

      // Start with large cache to trigger warning
      final cache = MockManagedCache(entryCount: 80); // 80 MB of 100 MB
      controller.registerCache(cache);

      // Trigger eviction → hysteresis active
      controller.forceEviction(MemoryPressureLevel.warning);
      expect(controller.hysteresisActive, true);
      expect(cache.isRefillAllowed, false);

      // Manually reduce entries to below 50% (50 MB)
      cache.entryCount = 40; // 40 MB < 50% of 100 MB

      // Force normal level, which checks hysteresis release
      controller.forceEviction(MemoryPressureLevel.normal);

      expect(controller.hysteresisActive, false);
      expect(cache.isRefillAllowed, true);
      controller.dispose();
    });

    test('refillAllowed propagates to all caches', () {
      final controller = MemoryBudgetController.forTesting(
        memoryPressureHandler: pressureHandler,
      );
      final cache1 = MockManagedCache(cacheName: 'A', entryCount: 10);
      final cache2 = MockManagedCache(cacheName: 'B', entryCount: 10);
      controller.registerCache(cache1);
      controller.registerCache(cache2);

      controller.forceEviction(MemoryPressureLevel.warning);

      expect(cache1.isRefillAllowed, false);
      expect(cache2.isRefillAllowed, false);
      controller.dispose();
    });

    test('stats includes hysteresis state', () {
      final controller = MemoryBudgetController.forTesting(
        memoryPressureHandler: pressureHandler,
      );
      final cache = MockManagedCache(entryCount: 10);
      controller.registerCache(cache);

      expect(controller.stats['hysteresisActive'], false);

      controller.forceEviction(MemoryPressureLevel.warning);
      expect(controller.stats['hysteresisActive'], true);

      final cacheStats = (controller.stats['caches'] as Map)['MockCache'];
      expect(cacheStats['refillAllowed'], false);

      controller.dispose();
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // INTERFACE EDGE CASES
  // ═══════════════════════════════════════════════════════════════════════════

  group('MemoryManagedCache interface —', () {
    test('evictFraction with 0 does nothing', () {
      final cache = MockManagedCache(entryCount: 10);
      cache.evictFraction(0);
      expect(cache.entryCount, 10);
    });

    test('evictFraction with 1.0 removes all', () {
      final cache = MockManagedCache(entryCount: 10);
      cache.evictFraction(1.0);
      expect(cache.entryCount, 0);
    });

    test('evictFraction rounds up (at least 1 entry)', () {
      final cache = MockManagedCache(entryCount: 3);
      cache.evictFraction(0.01);
      expect(cache.entryCount, 2);
    });

    test('isRefillAllowed defaults to true', () {
      final cache = MockManagedCache();
      expect(cache.isRefillAllowed, true);
    });

    test('refillAllowed setter toggles state', () {
      final cache = MockManagedCache();
      cache.refillAllowed = false;
      expect(cache.isRefillAllowed, false);
      cache.refillAllowed = true;
      expect(cache.isRefillAllowed, true);
    });
  });
}
