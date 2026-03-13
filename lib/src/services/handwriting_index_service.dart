import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';

import '../drawing/models/pro_drawing_point.dart';
import 'digital_ink_service.dart';
import '../storage/sqflite_stub_web.dart'
    if (dart.library.ffi) 'package:sqflite_common_ffi/sqflite_ffi.dart';

// =============================================================================
// 🔍 Handwriting Index Service — Searchable Ink Recognition
//
// Background-indexes all handwritten strokes using Google ML Kit Digital Ink
// Recognition, persists recognized text in SQLite FTS5, and provides fast
// full-text search with ranked results.
//
// ARCHITECTURE:
//   - Debounced batch queue: strokes are collected and recognized in batches
//     to avoid hammering the ML model on every stroke commit
//   - SQLite FTS5: instant full-text search with BM25 ranking
//   - Two tables:
//       stroke_text_map  — one row per indexed stroke (strokeId → text + bounds)
//       handwriting_fts  — FTS5 virtual table for full-text search
//   - Background processing: recognition runs async, never blocks UI
//
// USAGE:
//   final service = HandwritingIndexService.instance;
//   await service.init(database);
//   service.enqueueStroke(canvasId, stroke);  // auto-batches
//   final results = await service.search('hello');
// =============================================================================

/// A single search result with location information.
class HandwritingSearchResult {
  final String strokeId;
  final String canvasId;
  final String recognizedText;
  final ui.Rect bounds;
  final double score; // BM25 relevance score (lower = better match)

  const HandwritingSearchResult({
    required this.strokeId,
    required this.canvasId,
    required this.recognizedText,
    required this.bounds,
    required this.score,
  });
}

/// Index entry for a single stroke.
class _IndexEntry {
  final String canvasId;
  final String strokeId;
  final List<ProDrawingPoint> points;
  final ui.Rect bounds;

  _IndexEntry({
    required this.canvasId,
    required this.strokeId,
    required this.points,
    required this.bounds,
  });
}

/// 🔍 Searchable Handwriting Index Service
///
/// Provides GoodNotes "Spyglass"-style search through handwritten content.
/// Indexes strokes in the background using debounced batch processing.
class HandwritingIndexService {
  HandwritingIndexService._();
  static final HandwritingIndexService instance = HandwritingIndexService._();

  Database? _db;
  bool _initialized = false;
  bool _isProcessing = false;

  // ── Batch queue ──────────────────────────────────────────────────────────
  final List<_IndexEntry> _queue = [];
  Timer? _batchTimer;

  /// Debounce window: wait this long after last enqueue before processing.
  /// Prevents hammering ML Kit when user draws multiple strokes quickly.
  static const Duration _batchDebounce = Duration(milliseconds: 1500);

  /// Max batch size per recognition cycle (avoid long locks).
  static const int _maxBatchSize = 20;

  /// Stream controller for notifying UI of index changes.
  final StreamController<void> _indexChangedController =
      StreamController<void>.broadcast();

  /// Stream that fires whenever the index is updated (for live search).
  Stream<void> get onIndexChanged => _indexChangedController.stream;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Initialize the service with a database connection.
  ///
  /// Creates the FTS5 tables if they don't exist.
  /// Call this once after opening the database.
  Future<void> init(Database database) async {
    if (_initialized) return;
    _db = database;

    await _createTables();
    _initialized = true;
    debugPrint('🔍 [HandwritingIndex] Initialized');
  }

  /// Create the index tables if they don't exist.
  Future<void> _createTables() async {
    final db = _db!;

    // Main mapping table: strokeId → recognized text + metadata
    await db.execute('''
      CREATE TABLE IF NOT EXISTS stroke_text_map (
        stroke_id     TEXT NOT NULL,
        canvas_id     TEXT NOT NULL,
        recognized_text TEXT NOT NULL,
        bounds_left   REAL NOT NULL,
        bounds_top    REAL NOT NULL,
        bounds_right  REAL NOT NULL,
        bounds_bottom REAL NOT NULL,
        language_code TEXT NOT NULL DEFAULT 'en',
        indexed_at    INTEGER NOT NULL,
        PRIMARY KEY (stroke_id, canvas_id)
      )
    ''');

    // Index for fast canvas-scoped queries
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_stroke_text_canvas
      ON stroke_text_map(canvas_id)
    ''');

    // FTS5 virtual table for ranked full-text search
    // content= syncs with stroke_text_map for efficient storage
    await db.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS handwriting_fts
      USING fts5(
        stroke_id,
        canvas_id,
        recognized_text,
        content='stroke_text_map',
        content_rowid='rowid'
      )
    ''');

    // Triggers to keep FTS5 in sync with the mapping table
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS stroke_text_ai AFTER INSERT ON stroke_text_map BEGIN
        INSERT INTO handwriting_fts(rowid, stroke_id, canvas_id, recognized_text)
        VALUES (new.rowid, new.stroke_id, new.canvas_id, new.recognized_text);
      END
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS stroke_text_ad AFTER DELETE ON stroke_text_map BEGIN
        INSERT INTO handwriting_fts(handwriting_fts, rowid, stroke_id, canvas_id, recognized_text)
        VALUES ('delete', old.rowid, old.stroke_id, old.canvas_id, old.recognized_text);
      END
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS stroke_text_au AFTER UPDATE ON stroke_text_map BEGIN
        INSERT INTO handwriting_fts(handwriting_fts, rowid, stroke_id, canvas_id, recognized_text)
        VALUES ('delete', old.rowid, old.stroke_id, old.canvas_id, old.recognized_text);
        INSERT INTO handwriting_fts(rowid, stroke_id, canvas_id, recognized_text)
        VALUES (new.rowid, new.stroke_id, new.canvas_id, new.recognized_text);
      END
    ''');
  }

  // ── Indexing ──────────────────────────────────────────────────────────────

  /// Enqueue a stroke for background indexing.
  ///
  /// The stroke will be processed after [_batchDebounce] to allow batching.
  /// Safe to call on every stroke commit — the debounce prevents thrashing.
  void enqueueStroke(
    String canvasId,
    String strokeId,
    List<ProDrawingPoint> points,
    ui.Rect bounds,
  ) {
    if (!_initialized || points.length < 5) return;

    // Skip if already indexed
    _queue.add(_IndexEntry(
      canvasId: canvasId,
      strokeId: strokeId,
      points: points,
      bounds: bounds,
    ));

    // Reset debounce timer
    _batchTimer?.cancel();
    _batchTimer = Timer(_batchDebounce, _processBatch);
  }

  /// Force-process any pending items immediately (e.g., before app close).
  Future<void> flush() async {
    _batchTimer?.cancel();
    await _processBatch();
  }

  /// Process the pending queue in batch.
  Future<void> _processBatch() async {
    if (_isProcessing || _queue.isEmpty || !_initialized) return;
    _isProcessing = true;

    try {
      final inkService = DigitalInkService.instance;
      if (!inkService.isAvailable) {
        _queue.clear();
        return;
      }

      // Ensure model is ready
      if (!inkService.isReady) {
        await inkService.init();
        if (!inkService.isReady) {
          _queue.clear();
          return;
        }
      }

      // Take up to _maxBatchSize items
      final batch = _queue.take(_maxBatchSize).toList();
      _queue.removeRange(0, batch.length);

      int indexed = 0;
      final db = _db!;
      final now = DateTime.now().millisecondsSinceEpoch;

      // Check which strokes are already indexed
      final existingIds = <String>{};
      for (final entry in batch) {
        final rows = await db.query(
          'stroke_text_map',
          columns: ['stroke_id'],
          where: 'stroke_id = ? AND canvas_id = ?',
          whereArgs: [entry.strokeId, entry.canvasId],
          limit: 1,
        );
        if (rows.isNotEmpty) existingIds.add(entry.strokeId);
      }

      // Recognize and index new strokes
      for (final entry in batch) {
        if (existingIds.contains(entry.strokeId)) continue;

        try {
          final text = await inkService.recognizeStroke(entry.points);
          if (text == null || text.trim().isEmpty) continue;

          await db.insert('stroke_text_map', {
            'stroke_id': entry.strokeId,
            'canvas_id': entry.canvasId,
            'recognized_text': text.trim(),
            'bounds_left': entry.bounds.left,
            'bounds_top': entry.bounds.top,
            'bounds_right': entry.bounds.right,
            'bounds_bottom': entry.bounds.bottom,
            'language_code': inkService.languageCode,
            'indexed_at': now,
          });
          indexed++;
        } catch (e) {
          debugPrint('🔍 [HandwritingIndex] Failed to index ${entry.strokeId}: $e');
        }
      }

      if (indexed > 0) {
        debugPrint('🔍 [HandwritingIndex] Indexed $indexed strokes '
            '(${_queue.length} remaining)');
        _indexChangedController.add(null);
      }

      // If there are more items, schedule another batch
      if (_queue.isNotEmpty) {
        _batchTimer = Timer(const Duration(milliseconds: 200), _processBatch);
      }
    } catch (e) {
      debugPrint('🔍 [HandwritingIndex] Batch processing error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  // ── Full Re-index ─────────────────────────────────────────────────────────

  /// Re-index all strokes in a canvas. Clears existing index for the canvas.
  ///
  /// Use after importing a canvas or when the user explicitly requests it.
  /// Shows progress via [onProgress] callback (0.0 → 1.0).
  Future<void> reindexCanvas(
    String canvasId,
    List<({String id, List<ProDrawingPoint> points, ui.Rect bounds})> strokes, {
    ValueChanged<double>? onProgress,
  }) async {
    if (!_initialized) return;

    final inkService = DigitalInkService.instance;
    if (!inkService.isAvailable || !inkService.isReady) return;

    final db = _db!;

    // Clear existing index for this canvas
    await db.delete(
      'stroke_text_map',
      where: 'canvas_id = ?',
      whereArgs: [canvasId],
    );

    final now = DateTime.now().millisecondsSinceEpoch;
    int processed = 0;

    for (final stroke in strokes) {
      if (stroke.points.length < 5) {
        processed++;
        continue;
      }

      try {
        final text = await inkService.recognizeStroke(stroke.points);
        if (text != null && text.trim().isNotEmpty) {
          await db.insert('stroke_text_map', {
            'stroke_id': stroke.id,
            'canvas_id': canvasId,
            'recognized_text': text.trim(),
            'bounds_left': stroke.bounds.left,
            'bounds_top': stroke.bounds.top,
            'bounds_right': stroke.bounds.right,
            'bounds_bottom': stroke.bounds.bottom,
            'language_code': inkService.languageCode,
            'indexed_at': now,
          });
        }
      } catch (e) {
        debugPrint('🔍 [HandwritingIndex] Reindex failed for ${stroke.id}: $e');
      }

      processed++;
      onProgress?.call(processed / strokes.length);

      // Yield to UI thread every 5 strokes
      if (processed % 5 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    debugPrint('🔍 [HandwritingIndex] Reindexed $processed strokes for $canvasId');
    _indexChangedController.add(null);
  }

  // ── Search ────────────────────────────────────────────────────────────────

  /// Search for handwritten text across all canvases.
  ///
  /// Uses FTS5 BM25 ranking for relevance-ordered results.
  /// Supports prefix queries (e.g., "hel*" matches "hello").
  Future<List<HandwritingSearchResult>> search(
    String query, {
    String? canvasId,
    int limit = 50,
  }) async {
    if (!_initialized || query.trim().isEmpty) return const [];

    final db = _db!;

    // Build FTS5 query with prefix matching
    final ftsQuery = query
        .trim()
        .split(RegExp(r'\s+'))
        .map((w) => '$w*')
        .join(' ');

    try {
      String sql;
      List<Object?> args;

      if (canvasId != null) {
        sql = '''
          SELECT
            m.stroke_id,
            m.canvas_id,
            m.recognized_text,
            m.bounds_left,
            m.bounds_top,
            m.bounds_right,
            m.bounds_bottom,
            rank
          FROM handwriting_fts f
          JOIN stroke_text_map m
            ON f.stroke_id = m.stroke_id AND f.canvas_id = m.canvas_id
          WHERE handwriting_fts MATCH ?
            AND m.canvas_id = ?
          ORDER BY rank
          LIMIT ?
        ''';
        args = [ftsQuery, canvasId, limit];
      } else {
        sql = '''
          SELECT
            m.stroke_id,
            m.canvas_id,
            m.recognized_text,
            m.bounds_left,
            m.bounds_top,
            m.bounds_right,
            m.bounds_bottom,
            rank
          FROM handwriting_fts f
          JOIN stroke_text_map m
            ON f.stroke_id = m.stroke_id AND f.canvas_id = m.canvas_id
          WHERE handwriting_fts MATCH ?
          ORDER BY rank
          LIMIT ?
        ''';
        args = [ftsQuery, limit];
      }

      final rows = await db.rawQuery(sql, args);

      return rows.map((row) {
        return HandwritingSearchResult(
          strokeId: row['stroke_id'] as String,
          canvasId: row['canvas_id'] as String,
          recognizedText: row['recognized_text'] as String,
          bounds: ui.Rect.fromLTRB(
            (row['bounds_left'] as num).toDouble(),
            (row['bounds_top'] as num).toDouble(),
            (row['bounds_right'] as num).toDouble(),
            (row['bounds_bottom'] as num).toDouble(),
          ),
          score: (row['rank'] as num?)?.toDouble() ?? 0.0,
        );
      }).toList();
    } catch (e) {
      debugPrint('🔍 [HandwritingIndex] Search error: $e');
      return const [];
    }
  }

  /// Get the number of indexed strokes for a canvas.
  Future<int> getIndexedCount(String canvasId) async {
    if (!_initialized) return 0;
    final rows = await _db!.rawQuery(
      'SELECT COUNT(*) as cnt FROM stroke_text_map WHERE canvas_id = ?',
      [canvasId],
    );
    return (rows.first['cnt'] as int?) ?? 0;
  }

  /// Get all recognized text for a canvas (for export).
  Future<String> getFullText(String canvasId) async {
    if (!_initialized) return '';
    final rows = await _db!.query(
      'stroke_text_map',
      columns: ['recognized_text'],
      where: 'canvas_id = ?',
      whereArgs: [canvasId],
      orderBy: 'bounds_top ASC, bounds_left ASC',
    );
    return rows.map((r) => r['recognized_text'] as String).join(' ');
  }

  // ── Cleanup ───────────────────────────────────────────────────────────────

  /// Remove index entries for a deleted stroke.
  Future<void> removeStroke(String canvasId, String strokeId) async {
    if (!_initialized) return;
    await _db!.delete(
      'stroke_text_map',
      where: 'stroke_id = ? AND canvas_id = ?',
      whereArgs: [strokeId, canvasId],
    );
  }

  /// Remove all index entries for a canvas.
  Future<void> removeCanvas(String canvasId) async {
    if (!_initialized) return;
    await _db!.delete(
      'stroke_text_map',
      where: 'canvas_id = ?',
      whereArgs: [canvasId],
    );
  }

  /// Check if a stroke is already indexed.
  Future<bool> isStrokeIndexed(String canvasId, String strokeId) async {
    if (!_initialized) return false;
    final rows = await _db!.query(
      'stroke_text_map',
      columns: ['stroke_id'],
      where: 'stroke_id = ? AND canvas_id = ?',
      whereArgs: [strokeId, canvasId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Dispose resources.
  void dispose() {
    _batchTimer?.cancel();
    _queue.clear();
    _indexChangedController.close();
    _initialized = false;
  }
}
