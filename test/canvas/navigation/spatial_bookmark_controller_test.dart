import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/canvas/navigation/spatial_bookmark_controller.dart';
import 'package:fluera_engine/src/storage/sqlite_storage_adapter.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late SqliteStorageAdapter storage;
  late String dbPath;

  setUp(() async {
    final dir = await Directory.systemTemp.createTemp('fluera_ctrl_');
    dbPath = p.join(dir.path, 'test.db');
    storage = SqliteStorageAdapter(databasePath: dbPath);
    await storage.initialize();
  });

  tearDown(() async {
    await storage.close();
    final f = File(dbPath);
    if (await f.exists()) await f.delete();
  });

  group('SpatialBookmarkController (storage-backed)', () {
    test('add inserts a bookmark and persists it', () async {
      final ctrl = SpatialBookmarkController(adapter: storage);
      final bm = await ctrl.add(
        canvasId: 'c1',
        label: 'Termo',
        canvasPosition: const Offset(250, 500),
        scale: 2.0,
      );
      expect(ctrl.bookmarks, hasLength(1));
      expect(ctrl.bookmarks.single.id, bm.id);
      expect(bm.name, 'Termo');
      expect(bm.cx, 250);
      expect(bm.cy, 500);
      expect(bm.zoom, 2.0);
    });

    test('rename updates the name', () async {
      final ctrl = SpatialBookmarkController(adapter: storage);
      final bm = await ctrl.add(
        canvasId: 'c1',
        label: 'Old',
        canvasPosition: Offset.zero,
        scale: 1,
      );
      final ok = await ctrl.rename('c1', bm.id, 'New');
      expect(ok, isTrue);
      expect(ctrl.bookmarks.single.name, 'New');
    });

    test('remove drops the matching entry', () async {
      final ctrl = SpatialBookmarkController(adapter: storage);
      final a = await ctrl.add(
        canvasId: 'c1',
        label: 'A',
        canvasPosition: Offset.zero,
        scale: 1,
      );
      await ctrl.add(
        canvasId: 'c1',
        label: 'B',
        canvasPosition: Offset.zero,
        scale: 1,
      );
      final removed = await ctrl.remove('c1', a.id);
      expect(removed, isTrue);
      expect(ctrl.bookmarks.map((b) => b.name), ['B']);
    });

    test('recordVisit sets lastVisitedAt', () async {
      final ctrl = SpatialBookmarkController(adapter: storage);
      final bm = await ctrl.add(
        canvasId: 'c1',
        label: 'X',
        canvasPosition: Offset.zero,
        scale: 1,
      );
      expect(ctrl.bookmarks.single.lastVisitedAt, isNull);
      await ctrl.recordVisit('c1', bm.id);
      expect(ctrl.bookmarks.single.lastVisitedAt, isNotNull);
    });

    test('controller without adapter is a pure in-memory list', () async {
      final ctrl = SpatialBookmarkController();
      await ctrl.add(
        canvasId: 'c1',
        label: 'A',
        canvasPosition: Offset.zero,
        scale: 1,
      );
      expect(ctrl.bookmarks, hasLength(1));
      await ctrl.loadFromStorage('c1'); // no-op without adapter
      expect(ctrl.bookmarks, hasLength(1));
    });
  });
}
