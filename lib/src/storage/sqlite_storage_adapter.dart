// ============================================================================
// 💾 SQLITE STORAGE ADAPTER — Default local persistence implementation
//
// Built-in SQLite-based storage for canvas data. Provides zero-config local
// persistence using sqflite. Stroke data is stored as binary BLOBs using
// BinaryCanvasFormat for 80% smaller storage vs JSON.
//
// SCHEMA:
//   canvases — one row per canvas (metadata + full JSON data)
//   canvas_layers — one row per layer (binary BLOB via BinaryCanvasFormat)
//
// PERFORMANCE:
//   - All writes wrapped in a single transaction (atomic)
//   - WAL mode for concurrent read/write
//   - Binary BLOBs for stroke data (80% smaller than JSON)
//   - Index on canvas_id for fast lookups
// ============================================================================

import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

import 'nebula_storage_adapter.dart';
import '../core/models/canvas_layer.dart';
import '../core/nodes/pdf_document_node.dart';
import '../export/binary_canvas_format.dart';
import 'save_isolate_service.dart';

/// Schema version — increment when adding migrations.
const int _kSchemaVersion = 3;

/// Database file name.
const String _kDatabaseName = 'nebula_canvas.db';

/// 💾 Default SQLite storage adapter for canvas persistence.
///
/// DESIGN PRINCIPLES:
/// - Zero-config: works out of the box with no setup required
/// - Binary-first: stroke data stored as compact BLOBs (80% smaller than JSON)
/// - ACID transactions: every save is atomic — no partial writes on crash
/// - WAL mode: concurrent reads during writes for smooth UI
/// - Cross-platform: works on Linux, Windows, macOS, Android, and iOS
///
/// USAGE:
/// ```dart
/// final storage = SqliteStorageAdapter();
/// await storage.initialize();
///
/// // Save canvas
/// final data = saveData.toJson();
/// data['layers'] = layers.map((l) => l.toJson()).toList();
/// await storage.saveCanvas(canvasId, data);
///
/// // Load canvas
/// final loaded = await storage.loadCanvas(canvasId);
/// ```
class SqliteStorageAdapter implements NebulaStorageAdapter {
  Database? _db;

  /// Optional custom database path. If null, uses the default sqflite path.
  final String? databasePath;

  /// Creates a new SQLite storage adapter.
  ///
  /// [databasePath] — optional custom path for the database file.
  /// If null, the database is created in the default sqflite directory.
  SqliteStorageAdapter({this.databasePath});

  /// Whether the adapter has been initialized.
  bool get isInitialized => _db != null;

  /// Expose the raw database for shared services (e.g. RecordingStorageService).
  /// Throws if not initialized.
  Database get database => _ensureInitialized();

  // ===========================================================================
  // INITIALIZATION
  // ===========================================================================

  @override
  Future<void> initialize() async {
    if (_db != null) return; // Already initialized

    // Initialize FFI for desktop platforms (no-op on mobile)
    final bool isMobile = Platform.isAndroid || Platform.isIOS;
    if (!isMobile) {
      sqfliteFfiInit();
    }
    final factory = databaseFactoryFfi;

    // Use path_provider for a reliable directory on all platforms.
    // The FFI factory's getDatabasesPath() can fail on Android.
    String path;
    if (databasePath != null) {
      path = databasePath!;
    } else {
      final appDir = await getApplicationDocumentsDirectory();
      path = p.join(appDir.path, _kDatabaseName);
    }

    _db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _kSchemaVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onOpen: (db) async {
          // Enable WAL mode for better concurrent performance
          await db.execute('PRAGMA journal_mode=WAL');
          // Enable foreign keys
          await db.execute('PRAGMA foreign_keys=ON');
        },
      ),
    );

    debugPrint('[NebulaStorage] SQLite initialized at: $path');
  }

  /// Create initial schema.
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE canvases (
        canvas_id     TEXT PRIMARY KEY,
        title         TEXT,
        paper_type    TEXT NOT NULL DEFAULT 'blank',
        background_color TEXT,
        active_layer_id TEXT,
        infinite_canvas_id TEXT,
        node_id       TEXT,
        guides_json   TEXT,
        pdf_documents_json TEXT,
        variables_json TEXT,
        layer_count   INTEGER NOT NULL DEFAULT 0,
        stroke_count  INTEGER NOT NULL DEFAULT 0,
        created_at    INTEGER NOT NULL,
        updated_at    INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE canvas_layers (
        canvas_id     TEXT NOT NULL,
        layer_id      TEXT NOT NULL,
        layer_index   INTEGER NOT NULL,
        layer_data    BLOB NOT NULL,
        PRIMARY KEY (canvas_id, layer_id),
        FOREIGN KEY (canvas_id) REFERENCES canvases(canvas_id) ON DELETE CASCADE
      )
    ''');

    // Index for fast layer retrieval by canvas
    await db.execute('''
      CREATE INDEX idx_layers_canvas ON canvas_layers(canvas_id, layer_index)
    ''');

    // 🎤 v2: Recordings table for audio + synced stroke persistence
    await _createRecordingsTable(db);

    debugPrint('[NebulaStorage] Schema v$version created');
  }

  /// Handle schema migrations.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint('[NebulaStorage] Migrating schema v$oldVersion → v$newVersion');

    if (oldVersion < 2) {
      await _createRecordingsTable(db);
      debugPrint('[NebulaStorage] Migration v1→v2: recordings table created');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE canvases ADD COLUMN variables_json TEXT');
      debugPrint(
        '[NebulaStorage] Migration v2→v3: variables_json column added',
      );
    }
  }

  /// Create the recordings table (shared by _onCreate and _onUpgrade).
  Future<void> _createRecordingsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS recordings (
        id                TEXT PRIMARY KEY,
        canvas_id         TEXT NOT NULL,
        audio_path        TEXT NOT NULL,
        note_title        TEXT,
        recording_type    TEXT,
        total_duration_ms INTEGER NOT NULL,
        start_time        TEXT NOT NULL,
        strokes_json      TEXT,
        created_at        INTEGER NOT NULL,
        FOREIGN KEY (canvas_id) REFERENCES canvases(canvas_id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_recordings_canvas ON recordings(canvas_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_recordings_audio_path ON recordings(audio_path)
    ''');
  }

  // ===========================================================================
  // SAVE
  // ===========================================================================

  @override
  Future<void> saveCanvas(String canvasId, Map<String, dynamic> data) async {
    // Parse layers from the data (JSON → CanvasLayer)
    final layersJson = data['layers'] as List<dynamic>? ?? [];
    final layers =
        layersJson
            .map((l) => CanvasLayer.fromJson(l as Map<String, dynamic>))
            .toList();

    // 🎛️ Build variables JSON sidecar from save data
    String? variablesJson;
    final varColls = data['variableCollections'] as List<dynamic>?;
    if (varColls != null && varColls.isNotEmpty) {
      final varData = <String, dynamic>{
        'collections': varColls,
        if (data['variableBindings'] != null)
          'bindings': data['variableBindings'],
        if (data['variableActiveModes'] != null)
          'activeModes': data['variableActiveModes'],
      };
      variablesJson = jsonEncode(varData);
    }

    // Delegate to the zero-round-trip path
    await saveCanvasLayers(
      canvasId: canvasId,
      layers: layers,
      title: data['title'] as String?,
      paperType: data['paperType'] as String? ?? 'blank',
      backgroundColor: data['backgroundColor'] as String?,
      activeLayerId: data['activeLayerId'] as String?,
      infiniteCanvasId: data['infiniteCanvasId'] as String?,
      nodeId: data['nodeId'] as String?,
      guides: data['guides'] as Map<String, dynamic>?,
      variablesJson: variablesJson,
    );
  }

  /// 🚀 DIRECT SAVE — Zero JSON round-trip with DELTA support.
  ///
  /// Takes [CanvasLayer] objects directly and encodes them to binary BLOBs
  /// entirely inside a background Isolate. The main thread does ZERO heavy
  /// computation — it only captures a data snapshot and waits for the
  /// isolate + SQLite I/O to finish (both non-blocking).
  ///
  /// **Delta Save**: When [dirtyLayerIds] is provided and non-empty, only
  /// the dirty layers are re-encoded and re-inserted. Unchanged layers are
  /// left untouched in SQLite. This avoids re-encoding potentially large
  /// unchanged layers (e.g., a layer with 10k strokes that wasn't modified).
  ///
  /// **Performance**:
  /// - Binary encoding (the heaviest part) runs 100% off the main thread
  /// - No Layer→JSON→Layer→Binary round-trip (saves ~3x CPU vs old path)
  /// - Single Isolate.run call for dirty layers only (delta) or all layers
  /// - Layer indices are always updated to maintain correct ordering
  Future<void> saveCanvasLayers({
    required String canvasId,
    required List<CanvasLayer> layers,
    String? title,
    String paperType = 'blank',
    String? backgroundColor,
    String? activeLayerId,
    String? infiniteCanvasId,
    String? nodeId,
    Map<String, dynamic>? guides,
    Set<String>? dirtyLayerIds,
    String? variablesJson,
  }) async {
    final db = _ensureInitialized();
    final now = DateTime.now().millisecondsSinceEpoch;

    // Count total strokes (cheap — just list lengths)
    int totalStrokes = 0;
    for (final layer in layers) {
      totalStrokes += layer.strokes.length;
    }

    // 🚀 DELTA SAVE: Only encode dirty layers in the background Isolate.
    // If dirtyLayerIds is null/empty, encode ALL layers (full save).
    final bool isDelta = dirtyLayerIds != null && dirtyLayerIds.isNotEmpty;
    final layersToEncode =
        isDelta
            ? layers.where((l) => dirtyLayerIds.contains(l.id)).toList()
            : layers;

    // 🚀 PERSISTENT ISOLATE: Reuses a warm isolate (no ~2-5ms spawn overhead).
    // Falls back to Isolate.run() if the service hasn't been initialized.
    final List<Uint8List> encodedBlobs = await SaveIsolateService.instance
        .encodeLayers(layersToEncode);

    // Build a map of layerId → encoded blob for O(1) lookup
    final blobMap = <String, Uint8List>{};
    for (int i = 0; i < layersToEncode.length; i++) {
      blobMap[layersToEncode[i].id] = encodedBlobs[i];
    }

    // 💾 Extract PDF document metadata from layers for separate storage.
    // PDF nodes are part of the scene graph but the binary format doesn't
    // support them — we store them as a JSON sidecar.
    final pdfDocumentsJson = <Map<String, dynamic>>[];
    for (final layer in layers) {
      for (final child in layer.node.children) {
        if (child is PdfDocumentNode) {
          pdfDocumentsJson.add({
            'layerId': layer.id,
            'document': child.toJson(),
          });
        }
      }
    }
    final pdfJson =
        pdfDocumentsJson.isNotEmpty ? jsonEncode(pdfDocumentsJson) : null;

    // SQLite writes are I/O-bound and async — they don't block the main thread.
    final guidesJson = guides != null ? jsonEncode(guides) : null;
    await db.transaction((txn) async {
      // 1. Upsert canvas metadata (always updated)
      await txn.rawInsert(
        '''
        INSERT OR REPLACE INTO canvases (
          canvas_id, title, paper_type, background_color,
          active_layer_id, infinite_canvas_id, node_id, guides_json,
          pdf_documents_json, variables_json,
          layer_count, stroke_count, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
        [
          canvasId,
          title,
          paperType,
          backgroundColor,
          activeLayerId,
          infiniteCanvasId,
          nodeId,
          guidesJson,
          pdfJson,
          variablesJson,
          layers.length,
          totalStrokes,
          now,
          now,
        ],
      );

      if (isDelta) {
        // 🚀 DELTA PATH: Only delete+re-insert dirty layers.
        // Also update layer_index for ALL layers to maintain correct ordering.
        for (final dirtyId in dirtyLayerIds) {
          await txn.delete(
            'canvas_layers',
            where: 'canvas_id = ? AND layer_id = ?',
            whereArgs: [canvasId, dirtyId],
          );
        }

        // Insert dirty layers with their new blobs
        for (int i = 0; i < layers.length; i++) {
          final layerId = layers[i].id;
          if (blobMap.containsKey(layerId)) {
            await txn.rawInsert(
              '''
              INSERT INTO canvas_layers (canvas_id, layer_id, layer_index, layer_data)
              VALUES (?, ?, ?, ?)
            ''',
              [canvasId, layerId, i, blobMap[layerId]!],
            );
          } else {
            // Non-dirty layer: just update the index (in case layer order changed)
            await txn.update(
              'canvas_layers',
              {'layer_index': i},
              where: 'canvas_id = ? AND layer_id = ?',
              whereArgs: [canvasId, layerId],
            );
          }
        }
      } else {
        // FULL PATH: Delete all old layers and re-insert everything
        await txn.delete(
          'canvas_layers',
          where: 'canvas_id = ?',
          whereArgs: [canvasId],
        );

        for (int i = 0; i < layers.length; i++) {
          await txn.rawInsert(
            '''
            INSERT INTO canvas_layers (canvas_id, layer_id, layer_index, layer_data)
            VALUES (?, ?, ?, ?)
          ''',
            [canvasId, layers[i].id, i, blobMap[layers[i].id]!],
          );
        }
      }
    });
  }

  // ===========================================================================
  // LOAD
  // ===========================================================================

  @override
  Future<Map<String, dynamic>?> loadCanvas(String canvasId) async {
    final db = _ensureInitialized();

    // 1. Load canvas metadata
    final rows = await db.query(
      'canvases',
      where: 'canvas_id = ?',
      whereArgs: [canvasId],
    );

    if (rows.isEmpty) return null;
    final meta = rows.first;

    // 2. Load layers (ordered by index)
    final layerRows = await db.query(
      'canvas_layers',
      where: 'canvas_id = ?',
      whereArgs: [canvasId],
      orderBy: 'layer_index ASC',
    );

    // 3. Decode binary layer data
    final List<Map<String, dynamic>> layersJson = [];
    for (final row in layerRows) {
      final binaryData = row['layer_data'] as Uint8List;
      try {
        final decodedLayers = BinaryCanvasFormat.decode(binaryData);
        if (decodedLayers.isNotEmpty) {
          layersJson.add(decodedLayers.first.toJson());
        }
      } catch (e) {
        debugPrint(
          '[NebulaStorage] Warning: failed to decode layer ${row['layer_id']}: $e',
        );
      }
    }

    // 4. Reconstruct full canvas data map
    final result = <String, dynamic>{
      'canvasId': canvasId,
      'title': meta['title'],
      'paperType': meta['paper_type'] ?? 'blank',
      'backgroundColor': meta['background_color'],
      'activeLayerId': meta['active_layer_id'],
      'infiniteCanvasId': meta['infinite_canvas_id'],
      'nodeId': meta['node_id'],
      'layers': layersJson,
      'createdAt': meta['created_at'],
      'updatedAt': meta['updated_at'],
    };

    // Parse guides JSON if present
    final guidesStr = meta['guides_json'] as String?;
    if (guidesStr != null) {
      try {
        result['guides'] = jsonDecode(guidesStr);
      } catch (_) {}
    }

    // Parse PDF documents JSON if present
    final pdfStr = meta['pdf_documents_json'] as String?;
    if (pdfStr != null) {
      try {
        result['pdfDocuments'] = jsonDecode(pdfStr);
      } catch (_) {}
    }

    // 🎛️ Parse design variables JSON if present
    final varsStr = meta['variables_json'] as String?;
    if (varsStr != null) {
      try {
        final varsData = jsonDecode(varsStr) as Map<String, dynamic>;
        if (varsData['collections'] != null) {
          result['variableCollections'] = varsData['collections'];
        }
        if (varsData['bindings'] != null) {
          result['variableBindings'] = varsData['bindings'];
        }
        if (varsData['activeModes'] != null) {
          result['variableActiveModes'] = varsData['activeModes'];
        }
      } catch (_) {}
    }

    return result;
  }

  // ===========================================================================
  // DELETE
  // ===========================================================================

  @override
  Future<void> deleteCanvas(String canvasId) async {
    final db = _ensureInitialized();

    // CASCADE will delete canvas_layers automatically
    await db.delete('canvases', where: 'canvas_id = ?', whereArgs: [canvasId]);
  }

  // ===========================================================================
  // LIST
  // ===========================================================================

  @override
  Future<List<CanvasMetadata>> listCanvases() async {
    final db = _ensureInitialized();

    final rows = await db.query(
      'canvases',
      columns: [
        'canvas_id',
        'title',
        'paper_type',
        'layer_count',
        'stroke_count',
        'created_at',
        'updated_at',
      ],
      orderBy: 'updated_at DESC',
    );

    return rows.map((row) {
      return CanvasMetadata(
        canvasId: row['canvas_id'] as String,
        title: row['title'] as String?,
        paperType: row['paper_type'] as String? ?? 'blank',
        layerCount: row['layer_count'] as int? ?? 0,
        strokeCount: row['stroke_count'] as int? ?? 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          row['created_at'] as int,
        ),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          row['updated_at'] as int,
        ),
      );
    }).toList();
  }

  // ===========================================================================
  // EXISTS
  // ===========================================================================

  @override
  Future<bool> canvasExists(String canvasId) async {
    final db = _ensureInitialized();

    final result = await db.rawQuery(
      'SELECT 1 FROM canvases WHERE canvas_id = ? LIMIT 1',
      [canvasId],
    );

    return result.isNotEmpty;
  }

  // ===========================================================================
  // CLOSE
  // ===========================================================================

  @override
  Future<void> close() async {
    await _db?.close();
    _db = null;
    debugPrint('[NebulaStorage] SQLite closed');
  }

  // ===========================================================================
  // INTERNAL
  // ===========================================================================

  /// Ensure the database is initialized, throws if not.
  Database _ensureInitialized() {
    final db = _db;
    if (db == null) {
      throw StateError(
        'SqliteStorageAdapter not initialized. Call initialize() first.',
      );
    }
    return db;
  }
}
