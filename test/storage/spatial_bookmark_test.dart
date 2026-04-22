import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/storage/spatial_bookmark.dart';

void main() {
  group('SpatialBookmark', () {
    final t0 = DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000);
    final t1 = DateTime.fromMillisecondsSinceEpoch(1_700_000_500_000);

    test('round-trip JSON with all fields', () {
      final bm = SpatialBookmark(
        id: 'bm_1',
        name: 'Termodinamica — Cap. 3',
        cx: 1200.5,
        cy: -400.25,
        zoom: 0.8,
        color: 0xFF6750A4,
        createdAt: t0,
        lastVisitedAt: t1,
      );
      final decoded = SpatialBookmark.fromJson(bm.toJson());
      expect(decoded, equals(bm));
    });

    test('round-trip JSON omitting optional fields', () {
      final bm = SpatialBookmark(
        id: 'bm_2',
        name: 'Chimica',
        cx: 0,
        cy: 0,
        createdAt: t0,
      );
      final json = bm.toJson();
      expect(json.containsKey('color'), isFalse);
      expect(json.containsKey('lastVisitedAt'), isFalse);
      expect(json['zoom'], 1.0);

      final decoded = SpatialBookmark.fromJson(json);
      expect(decoded, equals(bm));
      expect(decoded.color, isNull);
      expect(decoded.lastVisitedAt, isNull);
    });

    test('copyWith overrides specific fields', () {
      final bm = SpatialBookmark(
        id: 'bm_3',
        name: 'Old',
        cx: 10,
        cy: 20,
        createdAt: t0,
        color: 0xFF000000,
        lastVisitedAt: t1,
      );
      final renamed = bm.copyWith(name: 'New');
      expect(renamed.name, 'New');
      expect(renamed.cx, 10);
      expect(renamed.color, 0xFF000000);
      expect(renamed.lastVisitedAt, t1);
    });

    test('copyWith can clear color and lastVisitedAt', () {
      final bm = SpatialBookmark(
        id: 'bm_4',
        name: 'X',
        cx: 0,
        cy: 0,
        createdAt: t0,
        color: 0xFF112233,
        lastVisitedAt: t1,
      );
      final cleared = bm.copyWith(clearColor: true, clearLastVisitedAt: true);
      expect(cleared.color, isNull);
      expect(cleared.lastVisitedAt, isNull);
    });

    test('fromJson applies safe defaults for missing fields', () {
      final decoded = SpatialBookmark.fromJson({
        'id': 'bm_5',
        'createdAt': t0.millisecondsSinceEpoch,
      });
      expect(decoded.name, 'Bookmark');
      expect(decoded.cx, 0);
      expect(decoded.cy, 0);
      expect(decoded.zoom, 1.0);
      expect(decoded.color, isNull);
    });

    test('center exposes Offset from cx/cy', () {
      final bm = SpatialBookmark(
        id: 'bm_6',
        name: 'Center',
        cx: 100,
        cy: -50,
        createdAt: t0,
      );
      expect(bm.center.dx, 100);
      expect(bm.center.dy, -50);
    });
  });
}
