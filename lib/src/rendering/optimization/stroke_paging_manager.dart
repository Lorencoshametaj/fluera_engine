import 'dart:convert';
import 'dart:ui';
import 'package:flutter/foundation.dart' show debugPrint;
import '../../storage/sqflite_stub_web.dart'
    if (dart.library.ffi) 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../drawing/models/pro_drawing_point.dart';

/// 🗂️ STROKE PAGING MANAGER — Memory-bounded stroke storage
///
/// Keeps lightweight stubs (id + bounds ~64 bytes) in RAM for R-Tree queries.
/// Pages out heavy point arrays (~5KB/stroke) to SQLite when strokes are
/// far from the viewport. Reloads on demand when viewport approaches.
///
/// MEMORY SAVINGS:
/// - 1M strokes × 5KB = 5GB → 1M stubs × 64B = 64MB
/// - Only viewport-visible strokes (~1000) have full data in RAM
///
/// PAGING STRATEGY:
/// - Page-out margin: 2× tile size (8192 canvas units)
/// - Page-in margin: 1× tile size (4096 canvas units)
/// - Hysteresis prevents thrashing at the boundary
class StrokePagingManager {
  /// Database for storing paged-out stroke data.
  Database? _db;

  /// Set of stroke IDs currently paged out to disk.
  final Set<String> _pagedOutIds = {};

  /// Table name for stroke point storage.
  static const String _tableName = 'stroke_pages';

  /// Margin outside viewport at which strokes are paged out.
  static const double pageOutMargin = 8192.0;

  /// Margin outside viewport at which strokes are paged in.
  /// Smaller than pageOutMargin to create hysteresis.
  static const double pageInMargin = 4096.0;

  /// Whether the manager has been initialized.
  bool get isInitialized => _db != null;

  /// Number of strokes currently paged out.
  int get pagedOutCount => _pagedOutIds.length;

  /// Check if a specific stroke is paged out.
  bool isPagedOut(String strokeId) => _pagedOutIds.contains(strokeId);

  // =========================================================================
  // INITIALIZATION
  // =========================================================================

  /// Initialize with an existing database (shares the SQLite instance
  /// with SqliteStorageAdapter).
  Future<void> initialize(Database db) async {
    _db = db;
    await _ensureTable();
  }

  /// Create the stroke_pages table if it doesn't exist.
  Future<void> _ensureTable() async {
    await _db!.execute('''
      CREATE TABLE IF NOT EXISTS $_tableName (
        stroke_id    TEXT PRIMARY KEY,
        canvas_id    TEXT NOT NULL,
        layer_id     TEXT NOT NULL DEFAULT '',
        stroke_json  TEXT NOT NULL,
        bounds_l     REAL NOT NULL,
        bounds_t     REAL NOT NULL,
        bounds_r     REAL NOT NULL,
        bounds_b     REAL NOT NULL
      )
    ''');
    await _db!.execute('''
      CREATE INDEX IF NOT EXISTS idx_stroke_pages_canvas
      ON $_tableName(canvas_id)
    ''');
    // Migrate: add layer_id column if it doesn't exist (v2)
    try {
      await _db!.execute(
        'ALTER TABLE $_tableName ADD COLUMN layer_id TEXT NOT NULL DEFAULT ""',
      );
    } catch (_) {
      // Column already exists — ignore
    }
  }

  // =========================================================================
  // PAGE OUT — Move strokes from RAM to disk
  // =========================================================================

  /// Page out strokes that are far from the viewport.
  ///
  /// Returns the list of stroke IDs that were paged out.
  /// The caller should replace those strokes with stubs.
  Future<List<String>> pageOut(
    String canvasId,
    List<ProStroke> strokes,
    Rect viewport,
  ) async {
    if (_db == null) return const [];

    final pagedOutIds = <String>[];
    final inflatedViewport = viewport.inflate(pageOutMargin);
    final batch = _db!.batch();

    for (final stroke in strokes) {
      // Skip already paged out or stub strokes
      if (stroke.isStub || _pagedOutIds.contains(stroke.id)) continue;

      // Skip strokes within the viewport margin
      if (stroke.bounds.overlaps(inflatedViewport)) continue;

      // Page out: serialize to JSON and store in SQLite
      final strokeJson = jsonEncode(stroke.toJson());
      final bounds = stroke.bounds;

      batch.insert(_tableName, {
        'stroke_id': stroke.id,
        'canvas_id': canvasId,
        'stroke_json': strokeJson,
        'bounds_l': bounds.left,
        'bounds_t': bounds.top,
        'bounds_r': bounds.right,
        'bounds_b': bounds.bottom,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      _pagedOutIds.add(stroke.id);
      pagedOutIds.add(stroke.id);
    }

    if (pagedOutIds.isNotEmpty) {
      await batch.commit(noResult: true);
    }

    return pagedOutIds;
  }

  // =========================================================================
  // PAGE IN — Reload strokes from disk to RAM
  // =========================================================================

  /// Load paged-out strokes that are now within the viewport.
  ///
  /// Returns a map of strokeId → restored ProStroke.
  /// The caller should replace stubs with these full strokes.
  Future<Map<String, ProStroke>> pageIn(Rect viewport) async {
    if (_db == null || _pagedOutIds.isEmpty) return const {};

    final inflatedViewport = viewport.inflate(pageInMargin);
    final restored = <String, ProStroke>{};

    // Query strokes whose bounds overlap the inflated viewport
    final rows = await _db!.query(
      _tableName,
      where:
          'bounds_r >= ? AND bounds_l <= ? AND bounds_b >= ? AND bounds_t <= ?',
      whereArgs: [
        inflatedViewport.left,
        inflatedViewport.right,
        inflatedViewport.top,
        inflatedViewport.bottom,
      ],
    );

    if (rows.isEmpty) return const {};

    final idsToRemove = <String>[];

    for (final row in rows) {
      final strokeId = row['stroke_id'] as String;
      if (!_pagedOutIds.contains(strokeId)) continue;

      try {
        final strokeJson =
            jsonDecode(row['stroke_json'] as String) as Map<String, dynamic>;
        final stroke = ProStroke.fromJson(strokeJson);
        restored[strokeId] = stroke;
        idsToRemove.add(strokeId);
      } catch (_) {
        // Corrupted data — skip
      }
    }

    // Remove from paged-out tracking and database
    if (idsToRemove.isNotEmpty) {
      _pagedOutIds.removeAll(idsToRemove);

      // Remove from SQLite (they're back in RAM)
      final batch = _db!.batch();
      for (final id in idsToRemove) {
        batch.delete(_tableName, where: 'stroke_id = ?', whereArgs: [id]);
      }
      await batch.commit(noResult: true);
    }

    return restored;
  }

  // =========================================================================
  // CLEANUP
  // =========================================================================

  /// Clear all paged-out strokes for a canvas.
  Future<void> clearForCanvas(String canvasId) async {
    if (_db == null) return;
    await _db!.delete(
      _tableName,
      where: 'canvas_id = ?',
      whereArgs: [canvasId],
    );
    _pagedOutIds.clear();
  }

  /// Clear all paged data.
  Future<void> clearAll() async {
    if (_db == null) return;
    await _db!.delete(_tableName);
    _pagedOutIds.clear();
  }

  /// Whether any strokes are currently paged out (need restore before save).
  bool get hasPagedOutStrokes => _pagedOutIds.isNotEmpty;

  // =========================================================================
  // SAVE SUPPORT — Restore paged-out strokes for binary encoding
  // =========================================================================

  /// Restore ALL paged-out strokes from SQLite for save.
  ///
  /// Returns a map of strokeId → full ProStroke.
  /// Does NOT remove them from the paging table — after save,
  /// the strokes go back to being stubs in RAM.
  ///
  /// This is called before binary encoding to prevent data loss.
  Future<Map<String, ProStroke>> restoreAllForSave() async {
    if (_db == null || _pagedOutIds.isEmpty) return const {};

    final restored = <String, ProStroke>{};

    // Load all paged-out strokes in one query
    final rows = await _db!.query(_tableName);

    for (final row in rows) {
      final strokeId = row['stroke_id'] as String;
      try {
        final strokeJson =
            jsonDecode(row['stroke_json'] as String) as Map<String, dynamic>;
        final stroke = ProStroke.fromJson(strokeJson);
        restored[strokeId] = stroke;
      } catch (_) {
        // Corrupted data — skip
      }
    }

    return restored;
  }

  // =========================================================================
  // LAZY-LOAD INDEX — Fast first-open for 1M+ strokes
  // =========================================================================

  /// Check if a canvas has an indexed stroke set for lazy-load.
  Future<bool> hasIndex(String canvasId) async {
    if (_db == null) return false;
    final result = await _db!.rawQuery(
      'SELECT COUNT(*) as cnt FROM $_tableName WHERE canvas_id = ?',
      [canvasId],
    );
    return (result.first['cnt'] as int) > 0;
  }

  /// Index ALL strokes after save — enables lazy-load on next open.
  ///
  /// Writes every stroke's full JSON + bounds + layer_id to stroke_pages.
  /// This runs in background after save, so it doesn't block the UI.
  Future<void> indexAllStrokes(
    String canvasId,
    List<(String layerId, ProStroke stroke)> allStrokes,
  ) async {
    if (_db == null) return;

    final batch = _db!.batch();
    int indexed = 0;
    int skippedStubs = 0;

    for (final (layerId, stroke) in allStrokes) {
      if (stroke.isStub) {
        skippedStubs++;
        continue; // Skip stubs — already indexed
      }
      final strokeJson = jsonEncode(stroke.toJson());
      final bounds = stroke.bounds;

      batch.insert(_tableName, {
        'stroke_id': stroke.id,
        'canvas_id': canvasId,
        'layer_id': layerId,
        'stroke_json': strokeJson,
        'bounds_l': bounds.left,
        'bounds_t': bounds.top,
        'bounds_r': bounds.right,
        'bounds_b': bounds.bottom,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      indexed++;
    }

    debugPrint('🗂️ [INDEX-DEBUG] indexAllStrokes: canvasId=$canvasId, total=${allStrokes.length}, indexed=$indexed, skippedStubs=$skippedStubs');
    await batch.commit(noResult: true);
  }

  /// Load lightweight stubs from index grouped by layer.
  ///
  /// Only reads (stroke_id, layer_id, bounds) — no JSON decode.
  /// Returns map of layerId → list of stub ProStrokes (~64B each).
  /// At 1M strokes: ~200ms vs ~5-10s for full binary decode.
  Future<Map<String, List<ProStroke>>> loadStubsFromIndex(
    String canvasId,
  ) async {
    if (_db == null) return const {};

    final rows = await _db!.query(
      _tableName,
      columns: [
        'stroke_id',
        'layer_id',
        'bounds_l',
        'bounds_t',
        'bounds_r',
        'bounds_b',
      ],
      where: 'canvas_id = ?',
      whereArgs: [canvasId],
    );

    if (rows.isEmpty) return const {};

    final result = <String, List<ProStroke>>{};

    for (final row in rows) {
      final strokeId = row['stroke_id'] as String;
      final layerId = row['layer_id'] as String;
      final bounds = Rect.fromLTRB(
        row['bounds_l'] as double,
        row['bounds_t'] as double,
        row['bounds_r'] as double,
        row['bounds_b'] as double,
      );

      // Create a minimal stub with forced bounds
      final stub = ProStroke.stubFromBounds(id: strokeId, bounds: bounds);
      result.putIfAbsent(layerId, () => []).add(stub);
      _pagedOutIds.add(strokeId);
    }

    return result;
  }
}

/// 🗂️ Per-layer stub data for lazy-load.
class LayerStubData {
  final String layerId;
  final List<ProStroke> stubs;
  LayerStubData({required this.layerId, required this.stubs});
}
