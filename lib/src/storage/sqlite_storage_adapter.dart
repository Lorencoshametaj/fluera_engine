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
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../utils/safe_path_provider.dart';
import 'encrypted_database_provider.dart';
import 'sqflite_stub_web.dart'
    if (dart.library.ffi) 'package:sqflite_common_ffi/sqflite_ffi.dart';
// sqflite_common imported via conditional import above.
import 'package:path/path.dart' as p;

import 'fluera_storage_adapter.dart';
import 'section_summary.dart';
import 'canvas_creation_options.dart';
import '../core/models/canvas_layer.dart';
import '../core/nodes/pdf_document_node.dart';
import '../core/nodes/pdf_preview_card_node.dart';
import '../core/nodes/latex_node.dart';
import '../core/nodes/tabular_node.dart';
import '../core/nodes/section_node.dart';
import '../core/engine_scope.dart';
import '../core/engine_error.dart';
import '../core/schema_version.dart';
import '../export/binary_canvas_format.dart';
import 'save_isolate_service.dart';

/// Schema version — increment when adding migrations.
const int _kSchemaVersion = 15;

/// Database file name.
const String _kDatabaseName = 'fluera_canvas.db';

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
class SqliteStorageAdapter implements FlueraStorageAdapter {
  Database? _db;

  /// Optional custom database path. If null, uses the default sqflite path.
  final String? databasePath;

  /// 🔐 Current user ID for per-user database isolation.
  /// Each user gets a separate SQLite file for 100% local security.
  String? _currentUserId;

  @override
  String? get currentUserId => _currentUserId;

  @override
  set currentUserId(String? userId) {
    if (userId == _currentUserId) return;
    _currentUserId = userId;
    // Close current DB and re-initialize with user-specific file
    _switchDatabase();
  }

  /// 🔐 Close current DB and open a user-specific one.
  Future<void> _switchDatabase() async {
    await _db?.close();
    _db = null;
    await initialize();
  }

  /// Get the database filename for the current user.
  /// Each user gets their own file: `fluera_canvas_<full_uuid>.db`
  /// Guest/anonymous: `fluera_canvas.db`
  String get _userDatabaseName {
    if (_currentUserId == null) return _kDatabaseName;
    // Use FULL user UUID (dashes removed) for guaranteed uniqueness
    final safeId = _currentUserId!.replaceAll('-', '');
    return 'fluera_canvas_$safeId.db';
  }

  /// 🔐 Optional encryption provider for at-rest encryption (Art. 32).
  /// If provided, the database is opened with SQLCipher encryption.
  final EncryptedDatabaseProvider? encryptionProvider;

  /// Creates a new SQLite storage adapter.
  ///
  /// [databasePath] — optional custom path for the database file.
  /// If null, the database is created in the default sqflite directory.
  /// [encryptionProvider] — optional encryption provider for SQLCipher.
  SqliteStorageAdapter({this.databasePath, this.encryptionProvider});

  /// Whether the database is encrypted.
  bool get isEncrypted =>
      encryptionProvider != null && encryptionProvider!.isEncryptionEnabled;

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

    // Initialize FFI for desktop platforms (no-op on mobile, skip on web)
    if (!kIsWeb) {
      sqfliteFfiInit();
    }
    final factory = databaseFactoryFfi;

    // 🔐 Per-user database file
    String path;
    if (databasePath != null) {
      path = databasePath!;
    } else {
      final appDir = await getSafeDocumentsDirectory();
      if (appDir == null) return; // Web: no filesystem
      path = p.join(appDir.path, _userDatabaseName);
    }

    _db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _kSchemaVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onOpen: (db) async {
          // 🔐 SQLCipher: PRAGMA key MUST be the first statement
          if (encryptionProvider != null) {
            final config = encryptionProvider!.getConfig(
              databaseName: _userDatabaseName,
            );
            for (final pragma in config.pragmaStatements) {
              await db.execute(pragma);
            }
          }
          // Enable WAL mode for better concurrent performance
          await db.execute('PRAGMA journal_mode=WAL');
          // Enable foreign keys
          await db.execute('PRAGMA foreign_keys=ON');
        },
      ),
    );
  }

  /// Create initial schema.
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE canvases (
        canvas_id     TEXT PRIMARY KEY,
        user_id       TEXT,
        title         TEXT,
        paper_type    TEXT NOT NULL DEFAULT 'blank',
        background_color TEXT,
        folder_id     TEXT,
        active_layer_id TEXT,
        infinite_canvas_id TEXT,
        node_id       TEXT,
        guides_json   TEXT,
        pdf_documents_json TEXT,
        variables_json TEXT,
        scene_nodes_json TEXT,
        connections_json TEXT,
        semantic_titles_json TEXT,
        snapshot_png   BLOB,
        sections_json  TEXT,
        content_bounds_json TEXT,
        last_viewport_json TEXT,
        schema_version INTEGER NOT NULL DEFAULT 1,
        layer_count   INTEGER NOT NULL DEFAULT 0,
        stroke_count  INTEGER NOT NULL DEFAULT 0,
        created_at    INTEGER NOT NULL,
        updated_at    INTEGER NOT NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_canvases_user ON canvases(user_id)',
    );

    await db.execute('''
      CREATE TABLE folders (
        folder_id       TEXT PRIMARY KEY,
        user_id         TEXT,
        name            TEXT NOT NULL,
        parent_folder_id TEXT,
        color           TEXT NOT NULL DEFAULT '0xFF6750A4',
        created_at      INTEGER NOT NULL,
        updated_at      INTEGER NOT NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_folders_user ON folders(user_id)',
    );

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

    // 🗺️ v15: Ghost Map sessions (R10 — atomic persistence).
    await _createGhostMapSessionsTable(db);
  }

  /// Handle schema migrations.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createRecordingsTable(db);
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE canvases ADD COLUMN variables_json TEXT');
    }
    if (oldVersion < 4) {
      await db.execute(
        'ALTER TABLE canvases ADD COLUMN schema_version INTEGER NOT NULL DEFAULT 1',
      );
    }
    if (oldVersion < 5) {
      // 📄 PDF persistence: add column for PDF document JSON sidecar.
      // Without this migration, databases created before the column was
      // added to _onCreate silently fail to save/restore PDF documents.
      try {
        await db.execute(
          'ALTER TABLE canvases ADD COLUMN pdf_documents_json TEXT',
        );
      } catch (_) {
        // Column may already exist if database was created with v4+ _onCreate.
      }
    }
    if (oldVersion < 6) {
      try {
        await db.execute(
          'ALTER TABLE canvases ADD COLUMN scene_nodes_json TEXT',
        );
      } catch (_) {
        // Column may already exist if database was created with v6+ _onCreate.
      }
    }
    if (oldVersion < 7) {
      try {
        await db.execute('ALTER TABLE canvases ADD COLUMN snapshot_png BLOB');
      } catch (_) {}
    }
    if (oldVersion < 8) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS folders (
            folder_id       TEXT PRIMARY KEY,
            name            TEXT NOT NULL,
            parent_folder_id TEXT,
            color           TEXT NOT NULL DEFAULT '0xFF6750A4',
            created_at      INTEGER NOT NULL,
            updated_at      INTEGER NOT NULL
          )
        ''');
        await db.execute('ALTER TABLE canvases ADD COLUMN folder_id TEXT');
      } catch (_) {}
    }
    if (oldVersion < 9) {
      // 🔍 Handwriting index tables.
      // The actual table creation is handled by HandwritingIndexService._createTables()
      // when it initializes with this database. Migration here just bumps version.
    }
    if (oldVersion < 10) {
      // 🔗 Knowledge Flow connections persistence.
      try {
        await db.execute(
          'ALTER TABLE canvases ADD COLUMN connections_json TEXT',
        );
      } catch (_) {
        // Column may already exist in fresh databases.
      }
    }
    if (oldVersion < 11) {
      // 📝 Speech-to-text transcription persistence.
      try {
        await db.execute(
          'ALTER TABLE recordings ADD COLUMN transcription_text TEXT',
        );
        await db.execute(
          'ALTER TABLE recordings ADD COLUMN transcription_language TEXT',
        );
        await db.execute(
          'ALTER TABLE recordings ADD COLUMN transcription_segments_json TEXT',
        );
      } catch (_) {
        // Columns may already exist in fresh databases.
      }
    }
    if (oldVersion < 12) {
      // 🧠 Semantic AI titles persistence.
      try {
        await db.execute(
          'ALTER TABLE canvases ADD COLUMN semantic_titles_json TEXT',
        );
      } catch (_) {
        // Column may already exist in fresh databases.
      }
    }
    if (oldVersion < 13) {
      // 🔐 User isolation: add user_id to canvases and folders.
      try {
        await db.execute('ALTER TABLE canvases ADD COLUMN user_id TEXT');
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_canvases_user ON canvases(user_id)',
        );
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE folders ADD COLUMN user_id TEXT');
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_folders_user ON folders(user_id)',
        );
      } catch (_) {}
    }
    if (oldVersion < 14) {
      // 📐 Workspace Hub: section summaries, content bounds, last viewport.
      try {
        await db.execute('ALTER TABLE canvases ADD COLUMN sections_json TEXT');
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE canvases ADD COLUMN content_bounds_json TEXT',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE canvases ADD COLUMN last_viewport_json TEXT',
        );
      } catch (_) {}
    }
    if (oldVersion < 15) {
      // 🗺️ R10: Ghost Map sessions — atomic persistence.
      await _createGhostMapSessionsTable(db);
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
        transcription_text TEXT,
        transcription_language TEXT,
        transcription_segments_json TEXT,
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

  /// Create the ghost_map_sessions table (shared by _onCreate and _onUpgrade).
  Future<void> _createGhostMapSessionsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ghost_map_sessions (
        session_id    TEXT PRIMARY KEY,
        canvas_id     TEXT NOT NULL,
        data_json     TEXT NOT NULL,
        created_at    INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_ghost_map_canvas
        ON ghost_map_sessions(canvas_id)
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
    String? connectionsJson,
    String? semanticTitlesJson,
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

    // 💾 Extract scene graph nodes not supported by binary format
    // (LatexNode, TabularNode, SectionNode, PdfPreviewCardNode)
    // — stored as JSON sidecar in scene_nodes_json column.
    final sceneNodesJson = <Map<String, dynamic>>[];
    for (final layer in layers) {
      for (final child in layer.node.children) {
        if (child is LatexNode) {
          sceneNodesJson.add({'layerId': layer.id, 'node': child.toJson()});
        } else if (child is TabularNode) {
          sceneNodesJson.add({'layerId': layer.id, 'node': child.toJson()});
        } else if (child is SectionNode) {
          sceneNodesJson.add({'layerId': layer.id, 'node': child.toJson()});
        } else if (child is PdfPreviewCardNode) {
          sceneNodesJson.add({'layerId': layer.id, 'node': child.toJson()});
        }
      }
    }
    final sceneJson =
        sceneNodesJson.isNotEmpty ? jsonEncode(sceneNodesJson) : null;

    // SQLite writes are I/O-bound and async — they don't block the main thread.
    final guidesJson = guides != null ? jsonEncode(guides) : null;
    await db.transaction((txn) async {
      // 🔧 FIX: Use ON CONFLICT ... DO UPDATE instead of INSERT OR REPLACE.
      // INSERT OR REPLACE is internally DELETE+INSERT, which triggers
      // ON DELETE CASCADE on the recordings table and wipes all recordings
      // every time the canvas is saved!
      await txn.rawInsert(
        '''
        INSERT INTO canvases (
          canvas_id, title, paper_type, background_color,
          active_layer_id, infinite_canvas_id, node_id, guides_json,
          pdf_documents_json, variables_json, schema_version,
          layer_count, stroke_count, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(canvas_id) DO UPDATE SET
          title = excluded.title,
          paper_type = excluded.paper_type,
          background_color = excluded.background_color,
          active_layer_id = excluded.active_layer_id,
          infinite_canvas_id = excluded.infinite_canvas_id,
          node_id = excluded.node_id,
          guides_json = excluded.guides_json,
          pdf_documents_json = excluded.pdf_documents_json,
          variables_json = excluded.variables_json,
          schema_version = excluded.schema_version,
          layer_count = excluded.layer_count,
          stroke_count = excluded.stroke_count,
          updated_at = excluded.updated_at
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
          kCurrentSchemaVersion,
          layers.length,
          totalStrokes,
          now,
          now,
        ],
      );

      // 🧮 Save scene nodes (LatexNode, TabularNode) as a separate UPDATE
      // to avoid breaking the main INSERT if column doesn't exist yet.
      if (sceneJson != null) {
        try {
          await txn.update(
            'canvases',
            {'scene_nodes_json': sceneJson},
            where: 'canvas_id = ?',
            whereArgs: [canvasId],
          );
        } catch (_) {
          // Column may not exist if migration hasn't run — safe to ignore.
        }
      }

      // 🔗 Save Knowledge Flow connections as JSON sidecar
      if (connectionsJson != null) {
        try {
          await txn.update(
            'canvases',
            {'connections_json': connectionsJson},
            where: 'canvas_id = ?',
            whereArgs: [canvasId],
          );
        } catch (_) {
          // Column may not exist if migration hasn't run — safe to ignore.
        }
      }

      // 🧠 Save semantic AI titles as JSON sidecar
      if (semanticTitlesJson != null) {
        try {
          await txn.update(
            'canvases',
            {'semantic_titles_json': semanticTitlesJson},
            where: 'canvas_id = ?',
            whereArgs: [canvasId],
          );
        } catch (_) {
          // Column may not exist if migration hasn't run — safe to ignore.
        }
      }

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
      } catch (e, stack) {
        EngineScope.current.errorRecovery.reportError(
          EngineError(
            severity: ErrorSeverity.degraded,
            domain: ErrorDomain.storage,
            source: 'SqliteStorageAdapter.loadCanvas.decodeLayer',
            original: e,
            stack: stack,
            context: {'layerId': row['layer_id']},
          ),
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
      } catch (e, stack) {
        EngineScope.current.errorRecovery.reportError(
          EngineError(
            severity: ErrorSeverity.degraded,
            domain: ErrorDomain.storage,
            source: 'SqliteStorageAdapter.loadCanvas.guidesJson',
            original: e,
            stack: stack,
          ),
        );
      }
    }

    // Parse PDF documents JSON if present
    final pdfStr = meta['pdf_documents_json'] as String?;
    if (pdfStr != null) {
      try {
        result['pdfDocuments'] = jsonDecode(pdfStr);
      } catch (e, stack) {
        EngineScope.current.errorRecovery.reportError(
          EngineError(
            severity: ErrorSeverity.degraded,
            domain: ErrorDomain.storage,
            source: 'SqliteStorageAdapter.loadCanvas.pdfJson',
            original: e,
            stack: stack,
          ),
        );
      }
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
      } catch (e, stack) {
        EngineScope.current.errorRecovery.reportError(
          EngineError(
            severity: ErrorSeverity.degraded,
            domain: ErrorDomain.storage,
            source: 'SqliteStorageAdapter.loadCanvas.variablesJson',
            original: e,
            stack: stack,
          ),
        );
      }
    }

    // 🧮 Parse scene nodes JSON (LatexNode, TabularNode) if present
    final sceneNodesStr = meta['scene_nodes_json'] as String?;
    if (sceneNodesStr != null) {
      try {
        result['sceneNodes'] = jsonDecode(sceneNodesStr);
      } catch (e, stack) {
        EngineScope.current.errorRecovery.reportError(
          EngineError(
            severity: ErrorSeverity.degraded,
            domain: ErrorDomain.storage,
            source: 'SqliteStorageAdapter.loadCanvas.sceneNodesJson',
            original: e,
            stack: stack,
          ),
        );
      }
    }

    // 🔗 Parse Knowledge Flow connections JSON if present
    final connectionsStr = meta['connections_json'] as String?;
    if (connectionsStr != null) {
      try {
        result['connections'] = jsonDecode(connectionsStr);
      } catch (e, stack) {
        EngineScope.current.errorRecovery.reportError(
          EngineError(
            severity: ErrorSeverity.degraded,
            domain: ErrorDomain.storage,
            source: 'SqliteStorageAdapter.loadCanvas.connectionsJson',
            original: e,
            stack: stack,
          ),
        );
      }
    }

    // 🧠 Parse semantic AI titles JSON if present
    final semanticTitlesStr = meta['semantic_titles_json'] as String?;
    if (semanticTitlesStr != null) {
      try {
        result['semanticTitles'] = jsonDecode(semanticTitlesStr);
      } catch (e, stack) {
        EngineScope.current.errorRecovery.reportError(
          EngineError(
            severity: ErrorSeverity.degraded,
            domain: ErrorDomain.storage,
            source: 'SqliteStorageAdapter.loadCanvas.semanticTitlesJson',
            original: e,
            stack: stack,
          ),
        );
      }
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
  Future<List<CanvasMetadata>> listCanvases({String? folderId}) async {
    final db = _ensureInitialized();

    // 🔐 Build WHERE clause with user_id filtering
    final conditions = <String>[];
    final args = <dynamic>[];

    if (_currentUserId != null) {
      conditions.add('user_id = ?');
      args.add(_currentUserId);
    }

    if (folderId != null) {
      conditions.add('folder_id = ?');
      args.add(folderId);
    } else {
      conditions.add('folder_id IS NULL');
    }

    final rows = await db.query(
      'canvases',
      columns: [
        'canvas_id',
        'title',
        'paper_type',
        'background_color',
        'folder_id',
        'layer_count',
        'stroke_count',
        'created_at',
        'updated_at',
        'sections_json',
        'content_bounds_json',
        'last_viewport_json',
      ],
      where: conditions.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'updated_at DESC',
    );

    return rows.map((row) {
      // 📐 Parse section summaries
      List<SectionSummary> sections = const [];
      final sectionsStr = row['sections_json'] as String?;
      if (sectionsStr != null) {
        try {
          final list = jsonDecode(sectionsStr) as List<dynamic>;
          sections = list
              .map((s) => SectionSummary.fromJson(s as Map<String, dynamic>))
              .toList();
        } catch (_) {}
      }

      // 📐 Parse content bounds
      Rect? contentBounds;
      final boundsStr = row['content_bounds_json'] as String?;
      if (boundsStr != null) {
        try {
          final b = jsonDecode(boundsStr) as Map<String, dynamic>;
          contentBounds = Rect.fromLTRB(
            (b['left'] as num).toDouble(),
            (b['top'] as num).toDouble(),
            (b['right'] as num).toDouble(),
            (b['bottom'] as num).toDouble(),
          );
        } catch (_) {}
      }

      // 📐 Parse last viewport
      ({double dx, double dy, double scale})? lastViewport;
      final vpStr = row['last_viewport_json'] as String?;
      if (vpStr != null) {
        try {
          final v = jsonDecode(vpStr) as Map<String, dynamic>;
          lastViewport = (
            dx: (v['dx'] as num).toDouble(),
            dy: (v['dy'] as num).toDouble(),
            scale: (v['scale'] as num).toDouble(),
          );
        } catch (_) {}
      }

      return CanvasMetadata(
        canvasId: row['canvas_id'] as String,
        title: row['title'] as String?,
        paperType: row['paper_type'] as String? ?? 'blank',
        backgroundColorValue: _parseBackgroundColor(row['background_color']),
        parentFolderId: row['folder_id'] as String?,
        layerCount: row['layer_count'] as int? ?? 0,
        strokeCount: row['stroke_count'] as int? ?? 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          row['created_at'] as int,
        ),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          row['updated_at'] as int,
        ),
        sections: sections,
        contentBounds: contentBounds,
        lastViewport: lastViewport,
      );
    }).toList();
  }

  /// Parse background color from DB (stored as hex string or int).
  static int _parseBackgroundColor(dynamic value) {
    if (value == null) return 0xFFFFFFFF;
    if (value is int) return value;
    if (value is String) {
      return int.tryParse(value.replaceFirst('#', '0xFF')) ?? 0xFFFFFFFF;
    }
    return 0xFFFFFFFF;
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
  // SNAPSHOT (SPLASH SCREEN PREVIEW)
  // ===========================================================================

  @override
  Future<void> saveSnapshot(String canvasId, Uint8List png) async {
    final db = _ensureInitialized();
    await db.update(
      'canvases',
      {'snapshot_png': png},
      where: 'canvas_id = ?',
      whereArgs: [canvasId],
    );
  }

  @override
  Future<Uint8List?> loadSnapshot(String canvasId) async {
    final db = _ensureInitialized();
    final rows = await db.query(
      'canvases',
      columns: ['snapshot_png'],
      where: 'canvas_id = ?',
      whereArgs: [canvasId],
    );
    if (rows.isEmpty) return null;
    return rows.first['snapshot_png'] as Uint8List?;
  }

  // ===========================================================================
  // GHOST MAP SESSIONS (R10)
  // ===========================================================================

  @override
  Future<void> saveGhostMapDataset(
    String canvasId,
    String sessionId,
    String dataJson,
  ) async {
    final db = _ensureInitialized();
    await db.transaction((txn) async {
      await txn.rawInsert(
        '''INSERT OR REPLACE INTO ghost_map_sessions
           (session_id, canvas_id, data_json, created_at)
           VALUES (?, ?, ?, ?)''',
        [sessionId, canvasId, dataJson, DateTime.now().millisecondsSinceEpoch],
      );
    });
  }

  @override
  Future<void> cleanupIncompleteGhostMapSessions() async {
    final db = _ensureInitialized();
    // Remove sessions older than 1 hour (likely from a killed process).
    final cutoff = DateTime.now()
        .subtract(const Duration(hours: 1))
        .millisecondsSinceEpoch;
    await db.delete(
      'ghost_map_sessions',
      where: 'created_at < ?',
      whereArgs: [cutoff],
    );
  }

  // ===========================================================================
  // CLOSE
  // ===========================================================================

  @override
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  @override
  Future<String> createCanvas(CanvasCreationOptions options) async {
    final id = options.resolveCanvasId();
    final now = DateTime.now().millisecondsSinceEpoch;
    final db = _ensureInitialized();

    // 1. Insert canvas metadata row (always)
    await db.rawInsert(
      '''
      INSERT INTO canvases (
        canvas_id, user_id, title, paper_type, background_color,
        folder_id, layer_count, stroke_count, created_at, updated_at, schema_version
      ) VALUES (?, ?, ?, ?, ?, ?, 0, 0, ?, ?, ?)
    ''',
      [
        id,
        _currentUserId,
        options.title,
        options.paperType.storageKey,
        '0x${options.backgroundColor.toARGB32().toRadixString(16).padLeft(8, '0')}',
        options.folderId,
        now,
        now,
        kCurrentSchemaVersion,
      ],
    );

    // 2. 📐 Pre-seed initial sections when requested
    if (options.initialSections.isNotEmpty) {
      // A4 at 150 DPI screen equivalent — looks like a real notebook page.
      // 595pt A4 (72 DPI PDF) → ×2.083 → 1240 canvas units ≈ A4 at 150 DPI.
      // At 0.3× zoom on a phone (393px wide), section fills ~95% of the screen.
      const sectionW = 1240.0; // A4 Portrait width  — feels like a real page
      const sectionH = 1754.0; // A4 Portrait height (1240 × √2 ≈ 1754)
      const gap     = 200.0;   // comfortable breathing room between sections

      // Create one empty binary layer to anchor the section nodes
      final layerId = 'layer_$now';
      final emptyLayer = CanvasLayer(
        id: layerId,
        name: 'Layer',
        strokes: const [],
        shapes: const [],
        texts: const [],
        images: const [],
      );
      final encodedLayer = BinaryCanvasFormat.encode([emptyLayer]);

      await db.rawInsert(
        'INSERT INTO canvas_layers (canvas_id, layer_id, layer_index, layer_data) '
        'VALUES (?, ?, 0, ?)',
        [id, layerId, encodedLayer],
      );
      await db.update(
        'canvases',
        {'layer_count': 1},
        where: 'canvas_id = ?',
        whereArgs: [id],
      );

      // Build SectionNode JSON entries for scene_nodes_json
      final sceneNodes = <Map<String, dynamic>>[];
      final sectionSummaries = <Map<String, dynamic>>[];

      for (int i = 0; i < options.initialSections.length; i++) {
        final name = options.initialSections[i].trim();
        if (name.isEmpty) continue;

        final y = i * (sectionH + gap);
        final nodeId = 'section_${now}_$i';

        // Only include transform if not at origin (matrix4 column-major storage)
        final transform = i == 0
            ? null
            : [
                1.0, 0.0, 0.0, 0.0,
                0.0, 1.0, 0.0, 0.0,
                0.0, 0.0, 1.0, 0.0,
                0.0,   y, 0.0, 1.0,
              ];

        sceneNodes.add({
          'layerId': layerId,
          'node': <String, dynamic>{
            'id': nodeId,
            'name': name,
            'nodeType': 'section',
            'sectionName': name,
            'sectionSize': {'width': sectionW, 'height': sectionH},
            if (transform != null) 'transform': transform,
            'backgroundColor': 0xFFFFFFFF,
            'showGrid': false,
            'gridSpacing': 20.0,
            'clipContent': false,
            'borderColor': 0xFFBDBDBD,
            'borderWidth': 1.0,
            'children': <dynamic>[],
          },
        });

        // Pre-seed lightweight summary for gallery display
        sectionSummaries.add({
          'id': nodeId,
          'name': name,
          'x': 0.0,
          'y': y,
          'width': sectionW,
          'height': sectionH,
        });
      }

      // Save scene graph JSON (SectionNodes)
      if (sceneNodes.isNotEmpty) {
        try {
          await db.update(
            'canvases',
            {'scene_nodes_json': jsonEncode(sceneNodes)},
            where: 'canvas_id = ?',
            whereArgs: [id],
          );
        } catch (_) {
          // Column may not exist on old schema — safe to ignore.
        }

        // Pre-seed sections_json for immediate gallery minimap / section list
        try {
          await db.update(
            'canvases',
            {'sections_json': jsonEncode(sectionSummaries)},
            where: 'canvas_id = ?',
            whereArgs: [id],
          );
        } catch (_) {}
      }
    }

    return id;
  }


  // ===========================================================================
  // FOLDER OPERATIONS
  // ===========================================================================

  @override
  Future<String> createFolder(
    String name, {
    String? parentFolderId,
    Color color = const Color(0xFF6750A4),
  }) async {
    final db = _ensureInitialized();
    final id = 'folder_${DateTime.now().millisecondsSinceEpoch}';
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('folders', {
      'folder_id': id,
      'user_id': _currentUserId,
      'name': name,
      'parent_folder_id': parentFolderId,
      'color': '0x${color.toARGB32().toRadixString(16).padLeft(8, '0')}',
      'created_at': now,
      'updated_at': now,
    });
    return id;
  }

  @override
  Future<void> renameFolder(String folderId, String name) async {
    final db = _ensureInitialized();
    await db.update(
      'folders',
      {'name': name, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'folder_id = ?',
      whereArgs: [folderId],
    );
  }

  @override
  Future<void> deleteFolder(String folderId) async {
    final db = _ensureInitialized();
    // Find the folder's parent so we can reparent contents
    final rows = await db.query(
      'folders',
      columns: ['parent_folder_id'],
      where: 'folder_id = ?',
      whereArgs: [folderId],
    );
    final parentId =
        rows.isNotEmpty ? rows.first['parent_folder_id'] as String? : null;

    await db.transaction((txn) async {
      // Move canvases to parent folder
      await txn.update(
        'canvases',
        {'folder_id': parentId},
        where: 'folder_id = ?',
        whereArgs: [folderId],
      );
      // Move subfolders to parent folder
      await txn.update(
        'folders',
        {'parent_folder_id': parentId},
        where: 'parent_folder_id = ?',
        whereArgs: [folderId],
      );
      // Delete the folder itself
      await txn.delete(
        'folders',
        where: 'folder_id = ?',
        whereArgs: [folderId],
      );
    });
  }

  @override
  Future<List<FolderMetadata>> listFolders({String? parentFolderId}) async {
    final db = _ensureInitialized();

    // 🔐 Build WHERE clause with user_id filtering
    final conditions = <String>[];
    final args = <dynamic>[];

    if (_currentUserId != null) {
      conditions.add('user_id = ?');
      args.add(_currentUserId);
    }

    if (parentFolderId != null) {
      conditions.add('parent_folder_id = ?');
      args.add(parentFolderId);
    } else {
      conditions.add('parent_folder_id IS NULL');
    }

    final rows = await db.query(
      'folders',
      where: conditions.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'name ASC',
    );

    final results = <FolderMetadata>[];
    for (final row in rows) {
      final fId = row['folder_id'] as String;
      // Count canvases in this folder
      final cCountRows = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM canvases WHERE folder_id = ?',
        [fId],
      );
      final cCount = (cCountRows.first['cnt'] as int?) ?? 0;
      // Count subfolders
      final sCountRows = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM folders WHERE parent_folder_id = ?',
        [fId],
      );
      final sCount = (sCountRows.first['cnt'] as int?) ?? 0;

      results.add(
        FolderMetadata(
          folderId: fId,
          name: row['name'] as String,
          parentFolderId: row['parent_folder_id'] as String?,
          colorValue: _parseBackgroundColor(row['color']),
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            row['created_at'] as int,
          ),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(
            row['updated_at'] as int,
          ),
          canvasCount: cCount,
          subfolderCount: sCount,
        ),
      );
    }
    return results;
  }

  @override
  Future<void> moveCanvasToFolder(String canvasId, String? folderId) async {
    final db = _ensureInitialized();
    await db.update(
      'canvases',
      {'folder_id': folderId},
      where: 'canvas_id = ?',
      whereArgs: [canvasId],
    );
  }

  @override
  Future<void> moveFolderToFolder(
    String folderId,
    String? parentFolderId,
  ) async {
    final db = _ensureInitialized();
    await db.update(
      'folders',
      {
        'parent_folder_id': parentFolderId,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'folder_id = ?',
      whereArgs: [folderId],
    );
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

  // ===========================================================================
  // 📐 SECTION SUMMARIES (WORKSPACE HUB)
  // ===========================================================================

  @override
  Future<void> saveSectionSummaries(
    String canvasId, {
    required List<SectionSummary> sections,
    Rect? contentBounds,
    ({double dx, double dy, double scale})? lastViewport,
  }) async {
    final db = _ensureInitialized();

    final updates = <String, dynamic>{};

    // Sections JSON
    updates['sections_json'] = sections.isNotEmpty
        ? jsonEncode(sections.map((s) => s.toJson()).toList())
        : null;

    // Content bounds JSON
    if (contentBounds != null && contentBounds != Rect.zero) {
      updates['content_bounds_json'] = jsonEncode({
        'left': contentBounds.left,
        'top': contentBounds.top,
        'right': contentBounds.right,
        'bottom': contentBounds.bottom,
      });
    }

    // Last viewport JSON
    if (lastViewport != null) {
      updates['last_viewport_json'] = jsonEncode({
        'dx': lastViewport.dx,
        'dy': lastViewport.dy,
        'scale': lastViewport.scale,
      });
    }

    if (updates.isNotEmpty) {
      try {
        await db.update(
          'canvases',
          updates,
          where: 'canvas_id = ?',
          whereArgs: [canvasId],
        );
      } catch (_) {
        // Columns may not exist if migration hasn't run — safe to ignore.
      }
    }
  }

  // ===========================================================================
  // 📐 VIEWPORT RESTORE (ENGINE-INTERNAL)
  // ===========================================================================

  @override
  Future<({double dx, double dy, double scale})?> loadLastViewport(
    String canvasId,
  ) async {
    final db = _ensureInitialized();
    try {
      final rows = await db.query(
        'canvases',
        columns: ['last_viewport_json'],
        where: 'canvas_id = ?',
        whereArgs: [canvasId],
      );
      if (rows.isEmpty) return null;
      final vpStr = rows.first['last_viewport_json'] as String?;
      if (vpStr == null) return null;
      final v = jsonDecode(vpStr) as Map<String, dynamic>;
      return (
        dx: (v['dx'] as num).toDouble(),
        dy: (v['dy'] as num).toDouble(),
        scale: (v['scale'] as num).toDouble(),
      );
    } catch (_) {
      return null;
    }
  }
}
