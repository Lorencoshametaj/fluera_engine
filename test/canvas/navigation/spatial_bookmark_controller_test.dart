import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/canvas/navigation/spatial_bookmark.dart';
import 'package:fluera_engine/src/canvas/navigation/spatial_bookmark_controller.dart';

void main() {
  group('SpatialBookmarkController CRUD', () {
    late SpatialBookmarkController ctrl;
    setUp(() => ctrl = SpatialBookmarkController());
    tearDown(() => ctrl.dispose());

    test('starts with empty list', () {
      expect(ctrl.bookmarks, isEmpty);
    });

    test('add returns the bookmark and inserts it', () {
      final bm = ctrl.add(
        label: 'Glicolisi',
        canvasPosition: const Offset(100, 200),
        scale: 1.5,
      );
      expect(bm.label, 'Glicolisi');
      expect(bm.canvasPosition, const Offset(100, 200));
      expect(bm.scale, 1.5);
      expect(ctrl.bookmarks, contains(bm));
      expect(ctrl.bookmarks.length, 1);
    });

    test('add notifies listeners', () {
      var fired = 0;
      ctrl.addListener(() => fired++);
      ctrl.add(
        label: 'X',
        canvasPosition: Offset.zero,
        scale: 1.0,
      );
      expect(fired, 1);
    });

    test('add with empty label falls back to "Bookmark"', () {
      final bm = ctrl.add(
        label: '   ',
        canvasPosition: Offset.zero,
        scale: 1.0,
      );
      expect(bm.label, 'Bookmark');
    });

    test('remove existing returns true and notifies', () {
      final bm = ctrl.add(
        label: 'X',
        canvasPosition: Offset.zero,
        scale: 1.0,
      );
      var fired = 0;
      ctrl.addListener(() => fired++);
      expect(ctrl.remove(bm.id), isTrue);
      expect(ctrl.bookmarks, isEmpty);
      expect(fired, 1);
    });

    test('remove non-existent returns false and does not notify', () {
      var fired = 0;
      ctrl.addListener(() => fired++);
      expect(ctrl.remove('bm_does_not_exist'), isFalse);
      expect(fired, 0);
    });

    test('rename updates label and notifies', () {
      final bm = ctrl.add(
        label: 'Old',
        canvasPosition: Offset.zero,
        scale: 1.0,
      );
      var fired = 0;
      ctrl.addListener(() => fired++);
      expect(ctrl.rename(bm.id, 'New'), isTrue);
      expect(ctrl.bookmarks.first.label, 'New');
      expect(fired, 1);
    });

    test('rename to empty/whitespace is rejected', () {
      final bm = ctrl.add(
        label: 'Original',
        canvasPosition: Offset.zero,
        scale: 1.0,
      );
      expect(ctrl.rename(bm.id, '   '), isFalse);
      expect(ctrl.bookmarks.first.label, 'Original');
    });

    test('recordVisit updates lastVisitedAtMs', () {
      final bm = ctrl.add(
        label: 'X',
        canvasPosition: Offset.zero,
        scale: 1.0,
      );
      expect(bm.lastVisitedAtMs, isNull);
      ctrl.recordVisit(bm.id);
      expect(ctrl.byId(bm.id)!.lastVisitedAtMs, isNotNull);
    });

    test('contains returns true only for existing ids', () {
      final bm = ctrl.add(
        label: 'X',
        canvasPosition: Offset.zero,
        scale: 1.0,
      );
      expect(ctrl.contains(bm.id), isTrue);
      expect(ctrl.contains('other'), isFalse);
    });

    test('clear removes all bookmarks and notifies', () {
      ctrl.add(label: 'A', canvasPosition: Offset.zero, scale: 1.0);
      ctrl.add(label: 'B', canvasPosition: Offset.zero, scale: 1.0);
      var fired = 0;
      ctrl.addListener(() => fired++);
      ctrl.clear();
      expect(ctrl.bookmarks, isEmpty);
      expect(fired, 1);
    });

    test('clear on empty list is a no-op (no notification)', () {
      var fired = 0;
      ctrl.addListener(() => fired++);
      ctrl.clear();
      expect(fired, 0);
    });

    test('LRU eviction: when cap reached, least-recent never-visited is dropped',
        () async {
      // Fill to cap. Use small delays so createdAtMs strictly increases —
      // without them the wall-clock resolution can collapse all timestamps
      // to the same ms and the eviction picks the wrong entry.
      final earliest = ctrl.add(
        label: 'earliest_unvisited',
        canvasPosition: Offset.zero,
        scale: 1.0,
      );
      await Future<void>.delayed(const Duration(milliseconds: 2));
      for (var i = 1; i < SpatialBookmarkController.maxBookmarksPerCanvas; i++) {
        ctrl.add(
          label: 'bm_$i',
          canvasPosition: Offset.zero,
          scale: 1.0,
        );
      }
      expect(ctrl.bookmarks.length,
          SpatialBookmarkController.maxBookmarksPerCanvas);

      await Future<void>.delayed(const Duration(milliseconds: 2));
      // Add one more — earliest never-visited must be evicted.
      ctrl.add(
        label: 'overflow',
        canvasPosition: Offset.zero,
        scale: 1.0,
      );
      expect(ctrl.bookmarks.length,
          SpatialBookmarkController.maxBookmarksPerCanvas);
      expect(ctrl.contains(earliest.id), isFalse);
    });

    test('list is sorted by createdAtMs descending', () async {
      final a = ctrl.add(
        label: 'A',
        canvasPosition: Offset.zero,
        scale: 1.0,
      );
      // Force a measurable timestamp gap so the sort is deterministic.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final b = ctrl.add(
        label: 'B',
        canvasPosition: Offset.zero,
        scale: 1.0,
      );
      // Most recent first.
      expect(ctrl.bookmarks.first.id, b.id);
      expect(ctrl.bookmarks.last.id, a.id);
    });
  });

  group('SpatialBookmarkController JSON round-trip', () {
    test('serialize → loadFromJson preserves order + content', () async {
      final source = SpatialBookmarkController();
      source.add(
        label: 'Glicolisi',
        canvasPosition: const Offset(100, 200),
        scale: 1.5,
      );
      await Future<void>.delayed(const Duration(milliseconds: 2));
      source.add(
        label: 'Krebs',
        canvasPosition: const Offset(-50, 300),
        scale: 0.75,
      );
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final last = source.add(
        label: 'Mitocondri',
        canvasPosition: const Offset(0, -100),
        scale: 2.0,
      );
      source.recordVisit(last.id); // touch lastVisitedAtMs to verify it persists

      final json = source.serializeToJson();
      source.dispose();

      final target = SpatialBookmarkController();
      expect(target.loadFromJson(json), isTrue);

      expect(target.bookmarks.length, source.bookmarks.length);
      // Most recent first (as in source)
      expect(target.bookmarks[0].label, 'Mitocondri');
      expect(target.bookmarks[1].label, 'Krebs');
      expect(target.bookmarks[2].label, 'Glicolisi');

      // Canvas positions preserved exactly
      expect(target.bookmarks[0].canvasPosition, const Offset(0, -100));
      expect(target.bookmarks[0].scale, 2.0);
      // lastVisitedAtMs survived the round-trip
      expect(target.bookmarks[0].lastVisitedAtMs, isNotNull);

      target.dispose();
    });

    test('serialize on empty list yields empty JSON array', () {
      final ctrl = SpatialBookmarkController();
      expect(ctrl.serializeToJson(), '[]');
      ctrl.dispose();
    });

    test('loadFromJson on empty string is a no-op (returns true)', () {
      final ctrl = SpatialBookmarkController();
      expect(ctrl.loadFromJson(''), isTrue);
      expect(ctrl.bookmarks, isEmpty);
      ctrl.dispose();
    });

    test('loadFromJson on malformed JSON returns false, list untouched', () {
      final ctrl = SpatialBookmarkController();
      ctrl.add(
        label: 'preserve_me',
        canvasPosition: Offset.zero,
        scale: 1.0,
      );
      expect(ctrl.loadFromJson('{not valid json ['), isFalse);
      // State preserved on parse failure.
      expect(ctrl.bookmarks.length, 1);
      expect(ctrl.bookmarks.first.label, 'preserve_me');
      ctrl.dispose();
    });

    test('loadFromJson on non-list JSON returns false', () {
      final ctrl = SpatialBookmarkController();
      expect(ctrl.loadFromJson('{"not": "a list"}'), isFalse);
      expect(ctrl.bookmarks, isEmpty);
      ctrl.dispose();
    });

    test('loadFromJson skips malformed entries, keeps valid ones', () {
      final ctrl = SpatialBookmarkController();
      // First entry missing required 'id' → throws inside fromJson,
      // must be skipped without aborting the whole load.
      // Second entry is fully valid — should survive.
      const json = '['
          '{"notAnId": true},'
          '{"id": "bm_valid", "label": "X", "x": 1.0, "y": 2.0, '
          '"scale": 1.5, "createdAtMs": 100}'
          ']';
      expect(ctrl.loadFromJson(json), isTrue);
      // Corrupted entry silently dropped, valid entry preserved.
      // Critical for resilience on partial writes (power loss mid-save).
      expect(ctrl.bookmarks.length, 1);
      expect(ctrl.bookmarks.first.id, 'bm_valid');
      ctrl.dispose();
    });
  });
}
