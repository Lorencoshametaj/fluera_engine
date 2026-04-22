// End-to-end migration test: seed a v15 database containing SectionSummary
// rows in `sections_json`, then open it through SqliteStorageAdapter to
// trigger the v15 → v16 upgrade and verify that `bookmarks_json` is populated
// with the expected SpatialBookmark entries.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/storage/sqlite_storage_adapter.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('v15 → v16 migration (sections → bookmarks)', () {
    late String dbPath;

    setUp(() async {
      final dir = await Directory.systemTemp.createTemp('fluera_mig_v16_');
      dbPath = p.join(dir.path, 'test.db');
    });

    tearDown(() async {
      final f = File(dbPath);
      if (await f.exists()) await f.delete();
    });

    Future<void> seedV15() async {
      final db = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 15,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE canvases (
                canvas_id TEXT PRIMARY KEY,
                user_id TEXT,
                title TEXT,
                paper_type TEXT NOT NULL DEFAULT 'blank',
                background_color TEXT,
                folder_id TEXT,
                active_layer_id TEXT,
                infinite_canvas_id TEXT,
                node_id TEXT,
                guides_json TEXT,
                pdf_documents_json TEXT,
                variables_json TEXT,
                scene_nodes_json TEXT,
                connections_json TEXT,
                semantic_titles_json TEXT,
                snapshot_png BLOB,
                sections_json TEXT,
                content_bounds_json TEXT,
                last_viewport_json TEXT,
                schema_version INTEGER NOT NULL DEFAULT 1,
                layer_count INTEGER NOT NULL DEFAULT 0,
                stroke_count INTEGER NOT NULL DEFAULT 0,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
              )
            ''');
            await db.execute('''
              CREATE TABLE canvas_layers (
                canvas_id TEXT NOT NULL,
                layer_id TEXT NOT NULL,
                layer_index INTEGER NOT NULL,
                layer_data BLOB NOT NULL,
                PRIMARY KEY (canvas_id, layer_id)
              )
            ''');
            await db.execute('''
              CREATE TABLE folders (
                folder_id TEXT PRIMARY KEY,
                user_id TEXT,
                name TEXT NOT NULL,
                parent_folder_id TEXT,
                color TEXT NOT NULL DEFAULT '0xFF6750A4',
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
              )
            ''');
          },
        ),
      );

      await db.insert('canvases', {
        'canvas_id': 'c_with_sections',
        'paper_type': 'blank',
        'created_at': 1700000000000,
        'updated_at': 1700000000000,
        'sections_json': jsonEncode([
          {
            'id': 's1',
            'name': 'Termodinamica',
            'x': 100.0,
            'y': 200.0,
            'width': 800.0,
            'height': 600.0,
            'bgColor': 0xFFAA1111,
          },
          {
            'id': 's2',
            'name': 'Chimica',
            'x': -500.0,
            'y': 0.0,
            'width': 400.0,
            'height': 400.0,
          },
        ]),
      });

      await db.insert('canvases', {
        'canvas_id': 'c_without_sections',
        'paper_type': 'blank',
        'created_at': 1700000000000,
        'updated_at': 1700000000000,
      });

      await db.close();
    }

    test('migrates each section to a bookmark preserving name/center/color',
        () async {
      await seedV15();

      final storage = SqliteStorageAdapter(databasePath: dbPath);
      await storage.initialize();

      final metas = await storage.listCanvases();
      final byId = {for (final m in metas) m.canvasId: m};

      final migrated = byId['c_with_sections']!;
      expect(migrated.bookmarks.length, 2);

      final byName = {for (final b in migrated.bookmarks) b.name: b};

      final termo = byName['Termodinamica']!;
      expect(termo.cx, 500.0); // 100 + 800/2
      expect(termo.cy, 500.0); // 200 + 600/2
      expect(termo.color, 0xFFAA1111);

      final chimica = byName['Chimica']!;
      expect(chimica.cx, -300.0); // -500 + 400/2
      expect(chimica.cy, 200.0); //    0 + 400/2
      expect(chimica.color, isNull);

      final untouched = byId['c_without_sections']!;
      expect(untouched.bookmarks, isEmpty);

      await storage.close();
    });

    test('migration is idempotent (re-open does not duplicate bookmarks)',
        () async {
      await seedV15();

      final storage = SqliteStorageAdapter(databasePath: dbPath);
      await storage.initialize();
      final first = await storage.listCanvases();
      await storage.close();

      final storage2 = SqliteStorageAdapter(databasePath: dbPath);
      await storage2.initialize();
      final second = await storage2.listCanvases();
      await storage2.close();

      final firstCount = first
          .firstWhere((m) => m.canvasId == 'c_with_sections')
          .bookmarks
          .length;
      final secondCount = second
          .firstWhere((m) => m.canvasId == 'c_with_sections')
          .bookmarks
          .length;

      expect(secondCount, firstCount);
    });
  });
}
