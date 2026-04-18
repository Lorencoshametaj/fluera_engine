import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/canvas/navigation/spatial_bookmark.dart';

void main() {
  group('SpatialBookmark', () {
    test('toJson round-trip preserves all fields', () {
      final bm = SpatialBookmark(
        id: 'bm_test_1',
        label: 'Glicolisi',
        canvasPosition: const Offset(123.45, -678.9),
        scale: 0.42,
        createdAtMs: 1234567890,
        lastVisitedAtMs: 1234999999,
      );
      final restored = SpatialBookmark.fromJson(bm.toJson());
      expect(restored.id, bm.id);
      expect(restored.label, bm.label);
      expect(restored.canvasPosition, bm.canvasPosition);
      expect(restored.scale, bm.scale);
      expect(restored.createdAtMs, bm.createdAtMs);
      expect(restored.lastVisitedAtMs, bm.lastVisitedAtMs);
    });

    test('fromJson without lastVisitedAtMs leaves it null', () {
      final bm = SpatialBookmark.fromJson({
        'id': 'bm_x',
        'label': 'X',
        'x': 0.0,
        'y': 0.0,
        'scale': 1.0,
        'createdAtMs': 100,
      });
      expect(bm.lastVisitedAtMs, isNull);
    });

    test('fromJson tolerates missing optional fields with defaults', () {
      final bm = SpatialBookmark.fromJson({'id': 'bm_min'});
      expect(bm.id, 'bm_min');
      expect(bm.label, isEmpty);
      expect(bm.canvasPosition, Offset.zero);
      expect(bm.scale, 1.0);
      expect(bm.createdAtMs, isPositive);
    });

    test('equality is based on id, not content', () {
      const a = SpatialBookmark(
        id: 'same',
        label: 'A',
        canvasPosition: Offset.zero,
        scale: 1.0,
        createdAtMs: 1,
      );
      const b = SpatialBookmark(
        id: 'same',
        label: 'B',
        canvasPosition: Offset(99, 99),
        scale: 0.5,
        createdAtMs: 2,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('copyWith does not mutate original', () {
      final original = SpatialBookmark(
        id: 'bm',
        label: 'Original',
        canvasPosition: const Offset(1, 2),
        scale: 1.0,
        createdAtMs: 100,
      );
      final modified = original.copyWith(
        label: 'Modified',
        lastVisitedAtMs: 999,
      );
      expect(original.label, 'Original');
      expect(original.lastVisitedAtMs, isNull);
      expect(modified.label, 'Modified');
      expect(modified.lastVisitedAtMs, 999);
      // Unchanged fields preserved
      expect(modified.id, original.id);
      expect(modified.canvasPosition, original.canvasPosition);
      expect(modified.scale, original.scale);
      expect(modified.createdAtMs, original.createdAtMs);
    });

    test('toString contains diagnostic info', () {
      const bm = SpatialBookmark(
        id: 'bm_42',
        label: 'Hello',
        canvasPosition: Offset(10, 20),
        scale: 0.75,
        createdAtMs: 1000,
      );
      final s = bm.toString();
      expect(s, contains('bm_42'));
      expect(s, contains('Hello'));
      expect(s, contains('0.75'));
    });
  });
}
