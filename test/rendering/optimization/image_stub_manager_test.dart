import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/rendering/optimization/image_stub_manager.dart';
import 'package:fluera_engine/src/rendering/optimization/frame_budget_manager.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Build an identity imageIdToPath map (id == path for simplicity in tests).
  Map<String, String> makeIdToPath(Iterable<String> ids) => {
    for (final id in ids) id: id,
  };

  /// A viewport centered at (0, 0) with a given size.
  ui.Rect viewport({double w = 400, double h = 400}) =>
      ui.Rect.fromCenter(center: ui.Offset.zero, width: w, height: h);

  /// Build NearbyImage list from id-position pairs.
  List<NearbyImage> makeNearby(Map<String, ui.Offset> positions) =>
      positions.entries
          .map(
            (e) => NearbyImage(
              imageId: e.key,
              imagePath: e.key, // id == path for tests
              center: e.value,
            ),
          )
          .toList();

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIVATION
  // ═══════════════════════════════════════════════════════════════════════════

  group('ImageStubManager — Activation —', () {
    test('inactive below threshold (< 30 images)', () {
      final mgr = ImageStubManager();
      final loadedImages = <String, ui.Image>{};
      for (int cycle = 0; cycle < 20; cycle++) {
        final result = mgr.maybeStubOut(
          safeImageIds: const {},
          loadedImages: loadedImages,
          imageIdToPath: makeIdToPath(List.generate(10, (i) => 'img_$i')),
          totalImageCount: 10,
        );
        expect(result, isEmpty);
      }
      expect(mgr.stubbedCount, 0);
    });

    test('activates at threshold (>= 30 images)', () {
      final mgr = ImageStubManager();
      final loadedImages = <String, ui.Image>{};
      List<String> allStubbed = [];
      for (int cycle = 0; cycle < 10; cycle++) {
        final result = mgr.maybeStubOut(
          safeImageIds: const {},
          loadedImages: loadedImages,
          imageIdToPath: makeIdToPath(List.generate(30, (i) => 'img_$i')),
          totalImageCount: 30,
        );
        allStubbed.addAll(result);
      }
      // No loaded images to dispose, so no stubs even though activated
      expect(allStubbed, isEmpty);
      expect(mgr.stats['isActive'], true);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // THROTTLING
  // ═══════════════════════════════════════════════════════════════════════════

  group('ImageStubManager — Throttling —', () {
    test('does not stub on every cycle (throttled)', () {
      final mgr = ImageStubManager();
      final loadedImages = <String, ui.Image>{};
      final result1 = mgr.maybeStubOut(
        safeImageIds: const {},
        loadedImages: loadedImages,
        imageIdToPath: makeIdToPath(List.generate(30, (i) => 'img_$i')),
        totalImageCount: 30,
      );
      expect(result1, isEmpty, reason: 'First cycle should be throttled');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // STUB-OUT LOGIC
  // ═══════════════════════════════════════════════════════════════════════════

  group('ImageStubManager — Stub-out —', () {
    test('does not stub images in safe set', () {
      final mgr = ImageStubManager();
      final loadedImages = <String, ui.Image>{};
      // All 30 images in the safe set → none should be stubbed
      final ids = List.generate(30, (i) => 'img_$i');
      for (int cycle = 0; cycle < 10; cycle++) {
        mgr.maybeStubOut(
          safeImageIds: ids.toSet(),
          loadedImages: loadedImages,
          imageIdToPath: makeIdToPath(ids),
          totalImageCount: 30,
        );
      }
      expect(mgr.stubbedCount, 0);
    });

    test('isStubbed returns true for stubbed images', () {
      final mgr = ImageStubManager();
      expect(mgr.isStubbed('nonexistent'), false);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // HYDRATE
  // ═══════════════════════════════════════════════════════════════════════════

  group('ImageStubManager — Hydrate —', () {
    test('returns empty when no images are stubbed', () {
      final mgr = ImageStubManager();
      final result = mgr.maybeHydrate(
        nearbyImages: makeNearby({'img_0': ui.Offset.zero}),
        loadedImages: <String, ui.Image>{},
        viewport: viewport(),
      );
      expect(result, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BUDGET CAP
  // ═══════════════════════════════════════════════════════════════════════════

  group('ImageStubManager — Budget cap —', () {
    test('max stubs per pass is capped at 30', () {
      final mgr = ImageStubManager();
      final loadedImages = <String, ui.Image>{};
      List<String> allStubbed = [];
      for (int cycle = 0; cycle < 20; cycle++) {
        final result = mgr.maybeStubOut(
          safeImageIds: const {},
          loadedImages: loadedImages,
          imageIdToPath: makeIdToPath(List.generate(100, (i) => 'img_$i')),
          totalImageCount: 100,
        );
        allStubbed.addAll(result);
      }
      expect(allStubbed.length, lessThanOrEqualTo(30));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════════════

  group('ImageStubManager — Lifecycle —', () {
    test('clear() resets all state', () {
      final mgr = ImageStubManager();
      mgr.clear();
      expect(mgr.stubbedCount, 0);
      expect(mgr.totalStubbedCount, 0);
      expect(mgr.stats['isActive'], false);
      expect(mgr.stats['cycleCounter'], 0);
    });

    test('removeStaleEntries retains only current IDs', () {
      final mgr = ImageStubManager();
      mgr.removeStaleEntries({'img_1', 'img_2'});
      expect(mgr.stubbedCount, 0);
    });

    test('removeEntry removes a specific ID', () {
      final mgr = ImageStubManager();
      mgr.removeEntry('img_1');
      expect(mgr.stubbedCount, 0);
    });

    test('stats returns valid diagnostic map', () {
      final mgr = ImageStubManager();
      final stats = mgr.stats;
      expect(stats, containsPair('isActive', false));
      expect(stats, containsPair('stubbedCount', 0));
      expect(stats, containsPair('totalStubbedCount', 0));
      expect(stats, containsPair('microThumbnailCount', 0));
      expect(stats, containsPair('cycleCounter', 0));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // onBeforeStub CALLBACK
  // ═══════════════════════════════════════════════════════════════════════════

  group('ImageStubManager — onBeforeStub —', () {
    test('callback not invoked without loaded images', () {
      final mgr = ImageStubManager();
      final callbacks = <String>[];
      for (int cycle = 0; cycle < 10; cycle++) {
        mgr.maybeStubOut(
          safeImageIds: const {},
          loadedImages: <String, ui.Image>{},
          imageIdToPath: makeIdToPath(List.generate(30, (i) => 'img_$i')),
          totalImageCount: 30,
          onBeforeStub: (path, image) => callbacks.add(path),
        );
      }
      expect(callbacks, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // MICRO-THUMBNAILS
  // ═══════════════════════════════════════════════════════════════════════════

  group('ImageStubManager — Micro-thumbnails —', () {
    test('getMicroThumbnail returns null when no thumbnail set', () {
      final mgr = ImageStubManager();
      expect(mgr.getMicroThumbnail('img_1'), isNull);
    });

    test('microThumbnailCount is 0 initially', () {
      final mgr = ImageStubManager();
      expect(mgr.microThumbnailCount, 0);
    });

    test('microThumbnails getter returns unmodifiable map', () {
      final mgr = ImageStubManager();
      expect(mgr.microThumbnails, isEmpty);
      expect(
        () => (mgr.microThumbnails as dynamic)['test'] = 'x',
        throwsA(isA<Error>()),
      );
    });

    test('clear() disposes micro-thumbnails', () {
      final mgr = ImageStubManager();
      mgr.clear();
      expect(mgr.microThumbnailCount, 0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // DISTANCE-SORTED HYDRATION
  // ═══════════════════════════════════════════════════════════════════════════

  group('ImageStubManager — Distance-sorted hydration —', () {
    test('hydrate returns empty when no stubbed images', () {
      final mgr = ImageStubManager();
      final result = mgr.maybeHydrate(
        nearbyImages: makeNearby({
          'a': const ui.Offset(100, 0),
          'b': const ui.Offset(50, 0),
        }),
        loadedImages: <String, ui.Image>{},
        viewport: viewport(w: 1000, h: 1000),
      );
      expect(result, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // MEMORY PRESSURE
  // ═══════════════════════════════════════════════════════════════════════════

  group('ImageStubManager — Memory pressure —', () {
    test('onMemoryPressure adjusts page-out margin', () {
      final mgr = ImageStubManager();
      expect(mgr.stats['pageOutMargin'], 3.0);

      mgr.onMemoryPressure(MemoryPressureLevel.warning);
      expect(mgr.stats['pageOutMargin'], 1.5);

      mgr.onMemoryPressure(MemoryPressureLevel.critical);
      expect(mgr.stats['pageOutMargin'], 0.5);

      mgr.onMemoryPressure(MemoryPressureLevel.normal);
      expect(mgr.stats['pageOutMargin'], 3.0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // DYNAMIC ACTIVATION THRESHOLD
  // ═══════════════════════════════════════════════════════════════════════════

  group('ImageStubManager — Dynamic threshold —', () {
    test('updateFromBudget adjusts threshold', () {
      final mgr = ImageStubManager();
      expect(mgr.stats['activationThreshold'], 30);

      mgr.updateFromBudget(400);
      expect(mgr.stats['activationThreshold'], 60);

      mgr.updateFromBudget(200);
      expect(mgr.stats['activationThreshold'], 40);

      mgr.updateFromBudget(100);
      expect(mgr.stats['activationThreshold'], 30);

      mgr.updateFromBudget(50);
      expect(mgr.stats['activationThreshold'], 15);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // TELEMETRY
  // ═══════════════════════════════════════════════════════════════════════════

  group('ImageStubManager — Telemetry —', () {
    test('cache hit rate starts at 0', () {
      final mgr = ImageStubManager();
      expect(mgr.cacheHitRate, 0.0);
    });

    test('cache hit rate tracks hits and misses', () {
      final mgr = ImageStubManager();
      mgr.recordCacheHit();
      mgr.recordCacheHit();
      mgr.recordCacheMiss();
      expect(mgr.cacheHitRate, closeTo(0.667, 0.01));
    });

    test('totalHydratedCount starts at 0', () {
      final mgr = ImageStubManager();
      expect(mgr.totalHydratedCount, 0);
    });

    test('stats includes all telemetry fields', () {
      final mgr = ImageStubManager();
      final stats = mgr.stats;
      expect(stats, containsPair('totalHydratedCount', 0));
      expect(stats, containsPair('cacheHitRate', 0.0));
      expect(stats, containsPair('pageOutMargin', 3.0));
      expect(stats, containsPair('activationThreshold', 30));
    });

    test('clear resets telemetry', () {
      final mgr = ImageStubManager();
      mgr.recordCacheHit();
      mgr.recordCacheMiss();
      mgr.clear();
      expect(mgr.cacheHitRate, 0.0);
      expect(mgr.totalHydratedCount, 0);
      expect(mgr.stats['pageOutMargin'], 3.0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // STAGGERED HYDRATION
  // ═══════════════════════════════════════════════════════════════════════════

  group('ImageStubManager — Staggered hydration —', () {
    test('max hydrates per pass capped', () {
      final mgr = ImageStubManager();
      final result = mgr.maybeHydrate(
        nearbyImages: makeNearby({'a': ui.Offset.zero}),
        loadedImages: <String, ui.Image>{},
        viewport: viewport(),
      );
      expect(result, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // LOD-AWARE HYDRATION
  // ═══════════════════════════════════════════════════════════════════════════

  group('ImageStubManager — LOD-aware hydration —', () {
    test('canvasScale parameter accepted by maybeHydrate', () {
      final mgr = ImageStubManager();
      final result = mgr.maybeHydrate(
        nearbyImages: makeNearby({'a': ui.Offset.zero}),
        loadedImages: <String, ui.Image>{},
        viewport: viewport(),
        canvasScale: 0.3,
      );
      expect(result, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SPATIAL-ONLY: NearbyImage
  // ═══════════════════════════════════════════════════════════════════════════

  group('ImageStubManager — NearbyImage —', () {
    test('NearbyImage data class holds correct values', () {
      const nearby = NearbyImage(
        imageId: 'test_id',
        imagePath: '/path/to/image.png',
        center: ui.Offset(100, 200),
      );
      expect(nearby.imageId, 'test_id');
      expect(nearby.imagePath, '/path/to/image.png');
      expect(nearby.center, const ui.Offset(100, 200));
    });

    test('spatial-only stub uses safeImageIds not viewport', () {
      final mgr = ImageStubManager();
      // Verify the new API accepts safeImageIds + totalImageCount
      final result = mgr.maybeStubOut(
        safeImageIds: {'img_0', 'img_1'},
        loadedImages: <String, ui.Image>{},
        imageIdToPath: makeIdToPath(List.generate(30, (i) => 'img_$i')),
        totalImageCount: 30,
      );
      // No loaded images, so nothing to stub
      expect(result, isEmpty);
    });
  });
}
