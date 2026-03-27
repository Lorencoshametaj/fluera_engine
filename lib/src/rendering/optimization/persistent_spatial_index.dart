import 'dart:ui';
import '../../storage/sqflite_stub_web.dart'
    if (dart.library.ffi) 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 🌲 PERSISTENT SPATIAL INDEX — SQLite R*Tree for 10M+ strokes
///
/// Uses SQLite's built-in R*Tree virtual table module for:
/// - **Zero startup cost**: R-Tree is pre-built on disk, no O(N log N) rebuild
/// - **Zero RAM overhead**: Spatial index lives in SQLite, not Dart heap
/// - **Persistent**: survives app restarts, no re-indexing needed
///
/// The R*Tree is a COMPLEMENT to the in-memory SpatialIndex:
/// - In-memory: used for sync paint() queries (must be sync)
/// - Persistent: used for initial load (skip rebuild), background queries,
///   and as the source of truth for the spatial index state
///
/// ARCHITECTURE:
/// ```
/// paint() → in-memory SpatialIndex.queryRange()  [SYNC, fast]
/// startup → PersistentSpatialIndex.loadVisible()  [ASYNC, replaces rebuild]
/// insert → both in-memory AND persistent          [dual-write]
/// remove → both in-memory AND persistent          [dual-write]
/// ```
class PersistentSpatialIndex {
  Database? _db;

  static const String _tableName = 'stroke_rtree';
  static const String _metaTable = 'stroke_rtree_meta';

  /// Whether the persistent index is initialized.
  bool get isInitialized => _db != null;

  // =========================================================================
  // INITIALIZATION
  // =========================================================================

  /// Initialize with shared SQLite database.
  Future<void> initialize(Database db) async {
    _db = db;
    await _ensureTables();
  }

  /// Create R*Tree virtual table and metadata table.
  Future<void> _ensureTables() async {
    // R*Tree virtual table for spatial queries
    await _db!.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS $_tableName USING rtree(
        id,
        min_x, max_x,
        min_y, max_y
      )
    ''');

    // Metadata table linking R*Tree integer IDs to stroke string IDs
    // (R*Tree requires integer primary keys)
    await _db!.execute('''
      CREATE TABLE IF NOT EXISTS $_metaTable (
        rowid     INTEGER PRIMARY KEY,
        stroke_id TEXT NOT NULL UNIQUE,
        node_type INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await _db!.execute('''
      CREATE INDEX IF NOT EXISTS idx_rtree_meta_stroke
      ON $_metaTable(stroke_id)
    ''');
  }

  // =========================================================================
  // INSERT / REMOVE — Dual-write with in-memory index
  // =========================================================================

  /// Insert a stroke into the persistent R*Tree.
  Future<void> insert(String strokeId, Rect bounds) async {
    if (_db == null) return;

    // Get or create a rowid for this stroke
    final rowid = await _getOrCreateRowId(strokeId);

    await _db!.execute(
      'INSERT OR REPLACE INTO $_tableName (id, min_x, max_x, min_y, max_y) '
      'VALUES (?, ?, ?, ?, ?)',
      [rowid, bounds.left, bounds.right, bounds.top, bounds.bottom],
    );
  }

  /// Insert multiple strokes in a batch (efficient for rebuild).
  Future<void> insertBatch(List<(String strokeId, Rect bounds)> entries) async {
    if (_db == null || entries.isEmpty) return;

    final batch = _db!.batch();

    for (final (strokeId, bounds) in entries) {
      // Insert metadata first
      batch.rawInsert(
        'INSERT OR IGNORE INTO $_metaTable (stroke_id) VALUES (?)',
        [strokeId],
      );
    }
    await batch.commit(noResult: true);

    // Now insert R*Tree entries using the rowids
    final batch2 = _db!.batch();
    for (final (strokeId, bounds) in entries) {
      batch2.rawInsert(
        'INSERT OR REPLACE INTO $_tableName (id, min_x, max_x, min_y, max_y) '
        'SELECT rowid, ?, ?, ?, ? FROM $_metaTable WHERE stroke_id = ?',
        [bounds.left, bounds.right, bounds.top, bounds.bottom, strokeId],
      );
    }
    await batch2.commit(noResult: true);
  }

  /// Remove a stroke from the persistent R*Tree.
  Future<void> remove(String strokeId) async {
    if (_db == null) return;

    final rows = await _db!.query(
      _metaTable,
      columns: ['rowid'],
      where: 'stroke_id = ?',
      whereArgs: [strokeId],
    );
    if (rows.isEmpty) return;

    final rowid = rows.first['rowid'] as int;
    await _db!.delete(_tableName, where: 'id = ?', whereArgs: [rowid]);
    await _db!.delete(_metaTable, where: 'rowid = ?', whereArgs: [rowid]);
  }

  // =========================================================================
  // QUERY — Spatial queries on disk
  // =========================================================================

  /// Query stroke IDs whose bounds overlap [range].
  ///
  /// Returns a list of stroke IDs (not CanvasNode objects).
  /// The caller uses these IDs to look up full stroke data.
  Future<List<String>> queryRange(Rect range) async {
    if (_db == null) return const [];

    final rows = await _db!.rawQuery(
      'SELECT m.stroke_id FROM $_tableName r '
      'JOIN $_metaTable m ON r.id = m.rowid '
      'WHERE r.min_x <= ? AND r.max_x >= ? '
      'AND r.min_y <= ? AND r.max_y >= ?',
      [range.right, range.left, range.bottom, range.top],
    );

    return rows.map((r) => r['stroke_id'] as String).toList();
  }

  /// Count total entries in the R*Tree.
  Future<int> count() async {
    if (_db == null) return 0;
    final result = await _db!.rawQuery(
      'SELECT COUNT(*) as cnt FROM $_metaTable',
    );
    return result.first['cnt'] as int;
  }

  /// Check if the persistent index has entries for initial load skip.
  Future<bool> hasEntries() async {
    return (await count()) > 0;
  }

  // =========================================================================
  // BULK OPERATIONS
  // =========================================================================

  /// Rebuild the entire persistent R*Tree from scratch.
  Future<void> rebuild(List<(String strokeId, Rect bounds)> entries) async {
    if (_db == null) return;

    // Clear existing data
    await _db!.delete(_tableName);
    await _db!.delete(_metaTable);

    // Batch insert all entries
    if (entries.isNotEmpty) {
      await insertBatch(entries);
    }
  }

  /// Clear all data.
  Future<void> clear() async {
    if (_db == null) return;
    await _db!.delete(_tableName);
    await _db!.delete(_metaTable);
  }

  // =========================================================================
  // INTERNAL
  // =========================================================================

  /// Get or create a rowid for a stroke ID.
  Future<int> _getOrCreateRowId(String strokeId) async {
    final existing = await _db!.query(
      _metaTable,
      columns: ['rowid'],
      where: 'stroke_id = ?',
      whereArgs: [strokeId],
    );

    if (existing.isNotEmpty) {
      return existing.first['rowid'] as int;
    }

    return await _db!.rawInsert(
      'INSERT INTO $_metaTable (stroke_id) VALUES (?)',
      [strokeId],
    );
  }
}
