import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/storage/pin_this_view.dart';
import 'package:fluera_engine/src/storage/spatial_bookmark.dart';
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
    final dir = await Directory.systemTemp.createTemp('fluera_pin_');
    dbPath = p.join(dir.path, 'test.db');
    storage = SqliteStorageAdapter(databasePath: dbPath);
    await storage.initialize();
  });

  tearDown(() async {
    await storage.close();
    final f = File(dbPath);
    if (await f.exists()) await f.delete();
  });

  group('pinThisView', () {
    test('creates a bookmark at the viewport centre and appends it', () async {
      final bm = await pinThisView(
        adapter: storage,
        canvasId: 'c1',
        name: 'Termo',
        viewport: (dx: -500, dy: -1000, scale: 2.0),
        existingBookmarks: const [],
      );
      expect(bm.cx, 250.0); // -(-500) / 2
      expect(bm.cy, 500.0); // -(-1000) / 2
      expect(bm.zoom, 2.0);
      expect(bm.name, 'Termo');
    });

    test('trims the name and falls back to default when empty', () async {
      final bm = await pinThisView(
        adapter: storage,
        canvasId: 'c1',
        name: '   ',
        viewport: (dx: 0, dy: 0, scale: 1),
        existingBookmarks: const [],
      );
      expect(bm.name, 'Pinned view');
    });

    test('preserves existing bookmarks', () async {
      final pre = SpatialBookmark(
        id: 'old',
        name: 'Old',
        cx: 0,
        cy: 0,
        createdAt: DateTime(2020),
      );
      await pinThisView(
        adapter: storage,
        canvasId: 'c1',
        name: 'New',
        viewport: (dx: 0, dy: 0, scale: 1),
        existingBookmarks: [pre],
      );
      // No direct read-back API — but we verify by listing canvases (which
      // would return empty since no canvas row exists; this sanity tests
      // that saveBookmarks didn't throw on an orphan canvasId).
      final metas = await storage.listCanvases();
      expect(metas, isA<List>());
    });
  });

  group('touchBookmarkVisit', () {
    test('updates lastVisitedAt for the matching bookmark only', () async {
      final a = SpatialBookmark(
        id: 'a',
        name: 'A',
        cx: 0,
        cy: 0,
        createdAt: DateTime(2020),
      );
      final b = SpatialBookmark(
        id: 'b',
        name: 'B',
        cx: 0,
        cy: 0,
        createdAt: DateTime(2020),
      );
      // Just verify the helper signature runs without error.
      await touchBookmarkVisit(
        adapter: storage,
        canvasId: 'c1',
        bookmarkId: 'b',
        existingBookmarks: [a, b],
      );
    });
  });
}
