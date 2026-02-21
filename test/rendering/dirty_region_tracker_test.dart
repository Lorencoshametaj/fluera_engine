import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/rendering/optimization/dirty_region_tracker.dart';

void main() {
  late DirtyRegionTracker tracker;

  setUp(() {
    tracker = DirtyRegionTracker();
  });

  tearDown(() {
    tracker.dispose();
  });

  group('markDirty', () {
    test('marks a region dirty', () {
      expect(tracker.hasDirtyRegions, isFalse);

      tracker.markDirty(const Rect.fromLTWH(0, 0, 100, 100));

      expect(tracker.hasDirtyRegions, isTrue);
      expect(tracker.dirtyCount, 1);
    });

    test('ignores empty rects', () {
      tracker.markDirty(Rect.zero);
      expect(tracker.hasDirtyRegions, isFalse);
    });

    test('expands regions by dirtyExpansion', () {
      tracker.markDirty(const Rect.fromLTWH(50, 50, 10, 10));

      final bounds = tracker.dirtyBounds;
      expect(bounds, isNotNull);
      // Original rect (50,50,60,60) expanded by 10 → (40,40,70,70)
      expect(bounds!.left, lessThanOrEqualTo(50));
      expect(bounds.top, lessThanOrEqualTo(50));
      expect(bounds.right, greaterThanOrEqualTo(60));
      expect(bounds.bottom, greaterThanOrEqualTo(60));
    });

    test('triggers merge when exceeding maxDirtyRegions', () {
      for (int i = 0; i < 15; i++) {
        tracker.markDirty(Rect.fromLTWH(i * 1000.0, 0, 10, 10));
      }

      // After merge, should have fewer regions than 15
      expect(
        tracker.dirtyCount,
        lessThanOrEqualTo(DirtyRegionTracker.maxDirtyRegions),
      );
    });
  });

  group('markDirtyBatch', () {
    test('marks multiple regions at once', () {
      tracker.markDirtyBatch([
        const Rect.fromLTWH(0, 0, 50, 50),
        const Rect.fromLTWH(200, 200, 50, 50),
      ]);

      expect(tracker.hasDirtyRegions, isTrue);
    });

    test('skips empty rects in batch', () {
      tracker.markDirtyBatch([
        Rect.zero,
        const Rect.fromLTWH(10, 10, 20, 20),
        Rect.zero,
      ]);

      // Only the non-empty one
      expect(tracker.dirtyCount, 1);
    });
  });

  group('dirtyBounds', () {
    test('returns null when no dirty regions', () {
      expect(tracker.dirtyBounds, isNull);
    });

    test('returns bounding box of all dirty regions', () {
      tracker.markDirty(const Rect.fromLTWH(0, 0, 10, 10));
      tracker.markDirty(const Rect.fromLTWH(100, 100, 10, 10));

      final bounds = tracker.dirtyBounds!;
      // With expansion, bounds should encompass both regions
      expect(bounds.left, lessThanOrEqualTo(0));
      expect(bounds.top, lessThanOrEqualTo(0));
      expect(bounds.right, greaterThanOrEqualTo(110));
      expect(bounds.bottom, greaterThanOrEqualTo(110));
    });
  });

  group('shouldRepaint', () {
    test('returns false when clean', () {
      expect(
        tracker.shouldRepaint(const Rect.fromLTWH(0, 0, 1000, 1000)),
        isFalse,
      );
    });

    test('returns true when dirty region overlaps viewport', () {
      tracker.markDirty(const Rect.fromLTWH(50, 50, 10, 10));

      expect(
        tracker.shouldRepaint(const Rect.fromLTWH(0, 0, 100, 100)),
        isTrue,
      );
    });

    test('returns false when dirty region is outside viewport', () {
      tracker.markDirty(const Rect.fromLTWH(5000, 5000, 10, 10));

      // Viewport far away — even with expansion the rects shouldn't overlap
      expect(
        tracker.shouldRepaint(const Rect.fromLTWH(0, 0, 100, 100)),
        isFalse,
      );
    });
  });

  group('getDirtyRegions', () {
    test('returns only regions overlapping viewport', () {
      tracker.markDirty(const Rect.fromLTWH(50, 50, 10, 10)); // inside
      tracker.markDirty(const Rect.fromLTWH(5000, 5000, 10, 10)); // outside

      final viewport = const Rect.fromLTWH(0, 0, 200, 200);
      final regions = tracker.getDirtyRegions(viewport);

      expect(regions.length, 1);
    });
  });

  group('clearDirty', () {
    test('clears all dirty regions', () {
      tracker.markDirty(const Rect.fromLTWH(0, 0, 100, 100));
      tracker.clearDirty();

      expect(tracker.hasDirtyRegions, isFalse);
      expect(tracker.dirtyCount, 0);
    });
  });

  group('batch mode', () {
    test('enterBatchMode + exitBatchMode batches notifications', () {
      int notifyCount = 0;
      tracker.addListener(() => notifyCount++);

      tracker.enterBatchMode();

      // Notifications are suppressed during batch mode...
      tracker.markDirty(const Rect.fromLTWH(0, 0, 10, 10));
      tracker.markDirty(const Rect.fromLTWH(20, 20, 10, 10));
      tracker.markDirty(const Rect.fromLTWH(40, 40, 10, 10));
      final duringBatch = notifyCount;

      tracker.exitBatchMode();

      // One notification after exit
      expect(duringBatch, 0);
      expect(notifyCount, 1);
    });
  });

  group('reset', () {
    test('clears all state', () {
      tracker.markDirty(const Rect.fromLTWH(0, 0, 100, 100));
      tracker.reset();

      expect(tracker.hasDirtyRegions, isFalse);
    });
  });
}
