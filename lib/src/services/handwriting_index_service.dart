import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show ValueChanged;

import '../drawing/models/pro_drawing_point.dart';
import '../core/models/digital_text_element.dart';
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
  final bool isTextElement; // true if from DigitalTextElement, not handwriting

  const HandwritingSearchResult({
    required this.strokeId,
    required this.canvasId,
    required this.recognizedText,
    required this.bounds,
    required this.score,
    this.isTextElement = false,
  });
}

/// Index entry for a single stroke.
class _IndexEntry {
  final String canvasId;
  final String strokeId;
  final List<ProDrawingPoint> points;
  final ui.Rect bounds;
  final ui.Size? writingArea;

  _IndexEntry({
    required this.canvasId,
    required this.strokeId,
    required this.points,
    required this.bounds,
    this.writingArea,
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

  /// Whether the service is initialized and ready for queries.
  bool get isInitialized => _initialized;

  // ── Batch queue ──────────────────────────────────────────────────────────
  final List<_IndexEntry> _queue = [];
  Timer? _batchTimer;

  /// Debounce window: wait this long after last enqueue before processing.
  /// Prevents hammering ML Kit when user draws multiple strokes quickly.
  static const Duration _batchDebounce = Duration(milliseconds: 1500);

  /// Max batch size per recognition cycle (avoid long locks).
  static const int _maxBatchSize = 8;

  /// Stream controller for notifying UI of index changes.
  final StreamController<void> _indexChangedController =
      StreamController<void>.broadcast();

  /// Stream that fires whenever the index is updated (for live search).
  Stream<void> get onIndexChanged => _indexChangedController.stream;

  /// In-memory vocabulary cache for fuzzy search (invalidated on index change).
  List<String>? _vocabCache;
  String? _vocabCacheKey; // canvasId or '*' for all

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

    // Persistent search history
    await db.execute('''
      CREATE TABLE IF NOT EXISTS search_history (
        query TEXT NOT NULL PRIMARY KEY,
        last_used INTEGER NOT NULL
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
  ///
  /// [writingArea] is the canvas viewport size (helps ML Kit distinguish
  /// uppercase from lowercase, e.g. 'o' vs 'O').
  void enqueueStroke(
    String canvasId,
    String strokeId,
    List<ProDrawingPoint> points,
    ui.Rect bounds, {
    ui.Size? writingArea,
  }) {
    if (!_initialized || points.length < 5) return;

    // 🔍 Fix 1: Skip if already queued (e.g. undo → redo)
    if (_queue.any((e) => e.strokeId == strokeId)) return;

    _queue.add(_IndexEntry(
      canvasId: canvasId,
      strokeId: strokeId,
      points: points,
      bounds: bounds,
      writingArea: writingArea,
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

      // 🔍 Fix 2: Group by canvasId for correct cross-canvas dedup
      final existingIds = <String>{};
      final grouped = <String, List<String>>{};
      for (final e in batch) {
        (grouped[e.canvasId] ??= []).add(e.strokeId);
      }
      for (final entry in grouped.entries) {
        final ph = List.filled(entry.value.length, '?').join(',');
        final rows = await db.rawQuery(
          'SELECT stroke_id FROM stroke_text_map '
          'WHERE canvas_id = ? AND stroke_id IN ($ph)',
          [entry.key, ...entry.value],
        );
        for (final row in rows) {
          existingIds.add(row['stroke_id'] as String);
        }
      }

      // 🔍 Fix 4: Group nearby strokes for multi-stroke recognition
      // Characters like 't', 'i', 'ñ' need multiple strokes recognized
      // together for accurate results.
      final newEntries = batch
          .where((e) => !existingIds.contains(e.strokeId))
          .toList();
      final strokeGroups = _groupNearbyStrokes(newEntries);

      for (final group in strokeGroups) {
        try {
          String? text;
          String langCode = inkService.languageCode;

          // ✨ Build recognition context for accuracy boost:
          // - writingArea: canvas dimensions for case disambiguation
          // - preContext: last ~20 chars recognized on this canvas
          final writingArea = group.first.writingArea;
          final preContext = await _getPreContext(
            db, group.first.canvasId,
          );
          final context = InkRecognitionContext(
            writingArea: writingArea,
            preContext: preContext,
          );

          if (group.length == 1) {
            // Single stroke — try auto-detect recognition
            final result = await inkService.recognizeWithAutoDetect(
              group.first.points,
              context: context,
            );
            if (result != null) {
              text = result.text;
              langCode = result.languageCode;
            }
          } else {
            // Multi-stroke — use combined recognition with auto-detect
            final strokeSets = group.map((e) => e.points).toList();
            final result =
                await inkService.recognizeMultiStrokeWithAutoDetect(
              strokeSets,
              context: context,
            );
            if (result != null) {
              text = result.text;
              langCode = result.languageCode;
            }
          }
          if (text == null || text.trim().isEmpty) continue;

          // Compute combined bounds for the group
          var combinedBounds = group.first.bounds;
          for (int i = 1; i < group.length; i++) {
            combinedBounds = combinedBounds.expandToInclude(group[i].bounds);
          }

          // Store one row per stroke in the group (all with same text)
          // so that erasing any one stroke removes it from search.
          for (final entry in group) {
            // Cache points for potential re-recognition with neighbors
            _cachePoints(entry.strokeId, entry.points);
            await db.insert('stroke_text_map', {
              'stroke_id': entry.strokeId,
              'canvas_id': entry.canvasId,
              'recognized_text': text.trim(),
              'bounds_left': combinedBounds.left,
              'bounds_top': combinedBounds.top,
              'bounds_right': combinedBounds.right,
              'bounds_bottom': combinedBounds.bottom,
              'language_code': langCode,
              'indexed_at': now,
            });
          }
          indexed += group.length;

          // 🔍 Fix 5: Re-recognize with already-indexed nearby strokes.
          // When "lorenzo" is split across batches ("lorenz" + "o"),
          // the "o" alone is recognized as just "o". We query the DB
          // for nearby strokes and re-recognize the combined group.
          if (text.isNotEmpty) {
            await _reRecognizeWithNeighbors(
              db,
              group,
              combinedBounds,
              text.trim(),
              inkService,
              now,
            );
          }
        } catch (_) {
        }

        // 🚀 ANR FIX: Yield to UI thread between recognitions.
        await Future<void>.delayed(Duration.zero);
      }

      if (indexed > 0) {
        _vocabCache = null; // Invalidate fuzzy cache
        _indexChangedController.add(null);
      }

      // If there are more items, schedule another batch
      if (_queue.isNotEmpty) {
        _batchTimer = Timer(const Duration(milliseconds: 200), _processBatch);
      }
    } catch (_) {
    } finally {
      _isProcessing = false;
    }
  }

  // ── Pre-context for accuracy boost ────────────────────────────────────────

  /// Get the last ~20 characters recognized on [canvasId] as pre-context.
  ///
  /// Feeds ML Kit's language model so it can predict the next word better.
  /// Example: if pre-context is "Il teorema di", ML Kit is more likely
  /// to recognize the next handwritten word as "Pitagora" than "Ritagora".
  Future<String?> _getPreContext(Database db, String canvasId) async {
    try {
      final rows = await db.rawQuery('''
        SELECT recognized_text FROM stroke_text_map
        WHERE canvas_id = ?
        ORDER BY indexed_at DESC
        LIMIT 3
      ''', [canvasId]);

      if (rows.isEmpty) return null;

      // Concatenate last 3 recognized texts (most recent last)
      final texts = rows.reversed
          .map((r) => (r['recognized_text'] as String).trim())
          .where((t) => t.isNotEmpty)
          .join(' ');

      if (texts.isEmpty) return null;

      // ML Kit recommends ~20 characters of pre-context
      return texts.length > 20 ? texts.substring(texts.length - 20) : texts;
    } catch (_) {
      return null;
    }
  }

  // ── Multi-stroke grouping ─────────────────────────────────────────────────

  /// Groups strokes for recognition using baseline-aware line segmentation.
  ///
  /// Two-pass approach for dramatically better recognition:
  ///
  /// **Pass 1 — Line segmentation**: Compute each stroke's baseline
  /// (median Y of all points) and group strokes with similar baselines
  /// into text lines. This means "hello world" written on one line is
  /// recognized as a phrase, not individual letters.
  ///
  /// **Pass 2 — Multi-stroke merging**: Within each line, merge strokes
  /// whose inflated bounds overlap (for characters like 't', 'i', 'ñ'
  /// that require multiple strokes).
  ///
  /// Strokes within each group are sorted left-to-right for natural
  /// reading order, which feeds ML Kit a properly sequenced input.
  List<List<_IndexEntry>> _groupNearbyStrokes(List<_IndexEntry> entries) {
    if (entries.length <= 1) {
      return entries.map((e) => [e]).toList();
    }

    // ── Pass 1: Line segmentation by baseline ────────────────────────────

    // Compute baseline (median Y) for each stroke
    final baselines = <double>[];
    for (final entry in entries) {
      final ys = entry.points.map((p) => p.position.dy).toList()..sort();
      // Median Y — more robust than mean against outlier points
      baselines.add(ys[ys.length ~/ 2]);
    }

    // Line height threshold: adaptive to stroke heights
    // Use the median stroke height as reference, with a minimum of 30px
    final strokeHeights = entries.map((e) => e.bounds.height).toList()..sort();
    final medianHeight = strokeHeights[strokeHeights.length ~/ 2];
    final lineThreshold = (medianHeight * 0.6).clamp(20.0, 80.0);

    // Group by baseline similarity (same canvas only)
    // Sort entries by baseline for efficient line detection
    final indexed = List.generate(entries.length, (i) => i);
    indexed.sort((a, b) => baselines[a].compareTo(baselines[b]));

    final lines = <List<int>>[]; // Each line is a list of entry indices
    var currentLine = <int>[indexed.first];
    var lineBaseline = baselines[indexed.first];

    for (int k = 1; k < indexed.length; k++) {
      final i = indexed[k];
      // Same line? Must be same canvas and similar baseline
      if (entries[i].canvasId == entries[currentLine.first].canvasId &&
          (baselines[i] - lineBaseline).abs() <= lineThreshold) {
        currentLine.add(i);
        // Update rolling average baseline
        lineBaseline = currentLine
                .map((j) => baselines[j])
                .reduce((a, b) => a + b) /
            currentLine.length;
      } else {
        lines.add(currentLine);
        currentLine = [i];
        lineBaseline = baselines[i];
      }
    }
    lines.add(currentLine);

    // ── Pass 2: Multi-stroke character merging within each line ──────────

    final result = <List<_IndexEntry>>[];

    for (final line in lines) {
      if (line.length == 1) {
        result.add([entries[line.first]]);
        continue;
      }

      // Within a line, use proximity-based union-find for multi-stroke chars
      const double proximityPx = 60.0;
      final parent = List<int>.generate(line.length, (i) => i);

      int find(int i) {
        while (parent[i] != i) {
          parent[i] = parent[parent[i]];
          i = parent[i];
        }
        return i;
      }

      void union(int a, int b) {
        final ra = find(a);
        final rb = find(b);
        if (ra != rb) parent[ra] = rb;
      }

      for (int i = 0; i < line.length; i++) {
        for (int j = i + 1; j < line.length; j++) {
          final a = entries[line[i]].bounds.inflate(proximityPx);
          final b = entries[line[j]].bounds.inflate(proximityPx);
          if (a.overlaps(b)) {
            union(i, j);
          }
        }
      }

      // Collect sub-groups within this line
      final subGroups = <int, List<int>>{};
      for (int i = 0; i < line.length; i++) {
        final root = find(i);
        (subGroups[root] ??= []).add(line[i]);
      }

      for (final group in subGroups.values) {
        // Sort left-to-right by stroke X center for natural reading order
        group.sort((a, b) =>
            entries[a].bounds.center.dx.compareTo(entries[b].bounds.center.dx));
        result.add(group.map((i) => entries[i]).toList());
      }
    }

    return result;
  }

  // ── Neighbor re-recognition ─────────────────────────────────────────────

  /// Short-lived cache of recent stroke points for re-recognition.
  /// Key: strokeId, Value: drawing points.
  /// Entries expire after 30s (enough for handwriting sessions).
  final Map<String, List<ProDrawingPoint>> _recentPoints = {};
  final Map<String, DateTime> _recentPointsTimestamp = {};

  /// Cache stroke points for potential re-recognition with neighbors.
  void _cachePoints(String strokeId, List<ProDrawingPoint> points) {
    _recentPoints[strokeId] = points;
    _recentPointsTimestamp[strokeId] = DateTime.now();
    // Prune old entries
    _recentPointsTimestamp.removeWhere((_, ts) =>
        DateTime.now().difference(ts).inSeconds > 30);
    _recentPoints.removeWhere((k, _) =>
        !_recentPointsTimestamp.containsKey(k));
  }

  /// Re-recognize new strokes together with already-indexed nearby strokes.
  ///
  /// When "lorenzo" is split across batches ("lorenz" in batch 1, "o" in
  /// batch 2), this finds the existing "lorenz" entries, combines their
  /// cached points with the new "o" points, and re-recognizes the full
  /// set for "lorenzo".
  Future<void> _reRecognizeWithNeighbors(
    Database db,
    List<_IndexEntry> newGroup,
    ui.Rect combinedBounds,
    String currentText,
    DigitalInkService inkService,
    int now,
  ) async {
    if (!inkService.isAvailable) return;

    final canvasId = newGroup.first.canvasId;

    // Query nearby already-indexed strokes (inflated by 60px proximity)
    const proximity = 60.0;
    final queryBounds = combinedBounds.inflate(proximity);

    // Find strokes that are nearby but NOT in the current group
    final newIds = newGroup.map((e) => e.strokeId).toSet();
    final placeholders = List.filled(newIds.length, '?').join(',');
    final rows = await db.rawQuery('''
      SELECT stroke_id, recognized_text,
             bounds_left, bounds_top, bounds_right, bounds_bottom
      FROM stroke_text_map
      WHERE canvas_id = ?
        AND stroke_id NOT IN ($placeholders)
        AND bounds_right >= ? AND bounds_left <= ?
        AND bounds_bottom >= ? AND bounds_top <= ?
    ''', [
      canvasId,
      ...newIds,
      queryBounds.left,
      queryBounds.right,
      queryBounds.top,
      queryBounds.bottom,
    ]);

    if (rows.isEmpty) return;

    // Collect cached points from neighbors
    final neighborPoints = <List<ProDrawingPoint>>[];
    final neighborIds = <String>[];
    for (final row in rows) {
      final id = row['stroke_id'] as String;
      final pts = _recentPoints[id];
      if (pts != null && pts.isNotEmpty) {
        neighborPoints.add(pts);
        neighborIds.add(id);
      }
    }

    if (neighborPoints.isEmpty) return;

    // Combine: neighbor points + new group points
    final allSets = <List<ProDrawingPoint>>[
      ...neighborPoints,
      ...newGroup.map((e) => e.points),
    ];

    // Re-recognize the combined set
    final reText = await inkService.recognizeMultiStroke(allSets);
    if (reText == null || reText.trim().isEmpty) return;
    if (reText.trim() == currentText) return; // No improvement



    // Update all entries (neighbors + new group) with the improved text
    var mergedBounds = combinedBounds;
    for (final row in rows) {
      if (neighborIds.contains(row['stroke_id'] as String)) {
        mergedBounds = mergedBounds.expandToInclude(ui.Rect.fromLTRB(
          (row['bounds_left'] as num).toDouble(),
          (row['bounds_top'] as num).toDouble(),
          (row['bounds_right'] as num).toDouble(),
          (row['bounds_bottom'] as num).toDouble(),
        ));
      }
    }

    final allIds = [...neighborIds, ...newIds];
    for (final id in allIds) {
      await db.update(
        'stroke_text_map',
        {
          'recognized_text': reText.trim(),
          'bounds_left': mergedBounds.left,
          'bounds_top': mergedBounds.top,
          'bounds_right': mergedBounds.right,
          'bounds_bottom': mergedBounds.bottom,
          'indexed_at': now,
        },
        where: 'stroke_id = ? AND canvas_id = ?',
        whereArgs: [id, canvasId],
      );
    }

    // Notify listeners of the update
    _indexChangedController.add(null);
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
      } catch (_) {
      }

      processed++;
      onProgress?.call(processed / strokes.length);

      // Yield to UI thread every 5 strokes
      if (processed % 5 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }


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
    bool caseSensitive = false,
    bool wholeWord = false,
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

      final rawResults = rows.map((row) {
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

      // Dedup overlapping results with same recognized text
      final deduped = _deduplicateResults(rawResults);

      // 🔍 Fuzzy fallback: when FTS5 returns nothing, try LIKE with wildcards
      if (deduped.isEmpty) {
        return _fuzzySearch(query,
            canvasId: canvasId,
            limit: limit,
            caseSensitive: caseSensitive,
            wholeWord: wholeWord);
      }

      // 🔍 Post-filter for case-sensitive / whole-word mode
      return _postFilter(deduped, query,
          caseSensitive: caseSensitive, wholeWord: wholeWord);
    } catch (_) {
      return const [];
    }
  }

  /// Unified search: handwriting + digital text elements.
  ///
  /// Searches both the FTS5 index (handwritten strokes) and in-memory
  /// DigitalTextElements (typed text) for a comprehensive search.
  Future<List<HandwritingSearchResult>> searchUnified(
    String query, {
    String? canvasId,
    List<DigitalTextElement> textElements = const [],
    int limit = 50,
    bool caseSensitive = false,
    bool wholeWord = false,
    bool fuzzy = false,
  }) async {
    // Get handwriting results from FTS5
    var hwResults = await search(query,
        canvasId: canvasId,
        limit: limit,
        caseSensitive: caseSensitive,
        wholeWord: wholeWord);

    // 🔍 Fuzzy mode: also fetch Levenshtein-close results
    if (fuzzy && _initialized && _db != null) {
      final fuzzyResults = await _levenshteinSearch(
        query.trim(),
        canvasId: canvasId,
        limit: limit,
      );
      // Merge, avoiding duplicates
      final existingIds = hwResults.map((r) => r.strokeId).toSet();
      for (final r in fuzzyResults) {
        if (!existingIds.contains(r.strokeId)) {
          hwResults.add(r);
          existingIds.add(r.strokeId);
        }
      }
      hwResults = _deduplicateResults(hwResults);
    }

    if (textElements.isEmpty) return hwResults;

    // Search digital text elements in-memory
    final queryLower = query.trim().toLowerCase();
    if (queryLower.isEmpty) return hwResults;

    final textMatched = <HandwritingSearchResult>[];
    for (final element in textElements) {
      final plainText = element.plainText;
      bool matches;
      if (fuzzy) {
        // Fuzzy: check if any word in the text is close to the query
        matches = _fuzzyContains(plainText, query.trim());
      } else if (caseSensitive) {
        matches = plainText.contains(query.trim());
      } else {
        matches = plainText.toLowerCase().contains(queryLower);
      }
      if (wholeWord && matches && !fuzzy) {
        final pattern = RegExp(
          '\\b${RegExp.escape(query.trim())}\\b',
          caseSensitive: caseSensitive,
        );
        matches = pattern.hasMatch(plainText);
      }
      if (matches) {
        textMatched.add(HandwritingSearchResult(
          strokeId: element.id,
          canvasId: canvasId ?? '',
          recognizedText: plainText,
          bounds: element.getBounds(),
          score: -1.0, // High priority (BM25: lower = better)
          isTextElement: true,
        ));
      }
    }

    // Merge: text elements first (exact matches), then handwriting
    return [...textMatched, ...hwResults].take(limit).toList();
  }

  /// Check if text fuzzy-contains the query (any word within Levenshtein ≤ 2).
  bool _fuzzyContains(String text, String query) {
    final words = text.toLowerCase().split(RegExp(r'\s+'));
    final q = query.toLowerCase();
    for (final word in words) {
      if (_levenshtein(word, q) <= 2) return true;
      // Also check substring containment
      if (word.contains(q) || q.contains(word)) return true;
    }
    return false;
  }

  /// Levenshtein distance search: find indexed texts within edit distance 2.
  Future<List<HandwritingSearchResult>> _levenshteinSearch(
    String query, {
    String? canvasId,
    int limit = 50,
  }) async {
    try {
      final db = _db!;
      // Fetch all distinct texts (bounded by canvas if specified)
      String sql;
      List<Object?> args;
      if (canvasId != null) {
        sql = 'SELECT DISTINCT recognized_text FROM stroke_text_map WHERE canvas_id = ?';
        args = [canvasId];
      } else {
        sql = 'SELECT DISTINCT recognized_text FROM stroke_text_map';
        args = [];
      }
      // Use cached vocabulary if available
      final cacheKey = canvasId ?? '*';
      List<String> vocabTexts;
      if (_vocabCache != null && _vocabCacheKey == cacheKey) {
        vocabTexts = _vocabCache!;
      } else {
        final rows = await db.rawQuery(sql, args);
        vocabTexts = rows.map((r) => r['recognized_text'] as String).toList();
        _vocabCache = vocabTexts;
        _vocabCacheKey = cacheKey;
      }

      // Filter by Levenshtein distance
      final queryLower = query.toLowerCase();
      final matchingTexts = <String>[];
      for (final text in vocabTexts) {
        final textLower = text.toLowerCase();
        // Check each word in the recognized text
        final words = textLower.split(RegExp(r'\s+'));
        for (final word in words) {
          if (_levenshtein(word, queryLower) <= 2) {
            matchingTexts.add(text);
            break;
          }
        }
      }

      if (matchingTexts.isEmpty) return [];

      // Fetch full entries for matching texts
      final placeholders = List.filled(matchingTexts.length, '?').join(',');
      final fetchSql = canvasId != null
          ? 'SELECT * FROM stroke_text_map WHERE canvas_id = ? AND recognized_text IN ($placeholders) LIMIT ?'
          : 'SELECT * FROM stroke_text_map WHERE recognized_text IN ($placeholders) LIMIT ?';
      final fetchArgs = canvasId != null
          ? [canvasId, ...matchingTexts, limit]
          : [...matchingTexts, limit];

      final matchRows = await db.rawQuery(fetchSql, fetchArgs);
      return matchRows.map((row) {
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
          score: 2.0, // Lower priority than exact
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Levenshtein edit distance between two strings.
  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    // Optimization: early exit if length difference > max distance
    if ((a.length - b.length).abs() > 2) return 3;

    var prev = List<int>.generate(b.length + 1, (i) => i);
    var curr = List<int>.filled(b.length + 1, 0);

    for (int i = 1; i <= a.length; i++) {
      curr[0] = i;
      for (int j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        curr[j] = [
          prev[j] + 1,     // deletion
          curr[j - 1] + 1, // insertion
          prev[j - 1] + cost, // substitution
        ].reduce((a, b) => a < b ? a : b);
      }
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }
    return prev[b.length];
  }

  // ── Result deduplication ──────────────────────────────────────────────────

  /// Deduplicates results with identical recognized text and overlapping bounds.
  ///
  /// Multi-stroke grouping (Fix 4) stores one row per stroke in a group,
  /// all with the same text. When searching, they appear as N separate
  /// results. This merges them into one result with combined bounds.
  List<HandwritingSearchResult> _deduplicateResults(
    List<HandwritingSearchResult> results,
  ) {
    if (results.length <= 1) return results;

    final deduped = <HandwritingSearchResult>[];
    final used = List.filled(results.length, false);

    for (int i = 0; i < results.length; i++) {
      if (used[i]) continue;
      used[i] = true;

      var merged = results[i];
      // Find other results with same text and overlapping bounds
      for (int j = i + 1; j < results.length; j++) {
        if (used[j]) continue;
        if (results[j].recognizedText != merged.recognizedText) continue;
        if (results[j].canvasId != merged.canvasId) continue;

        // Check spatial proximity (80px)
        final a = merged.bounds.inflate(80);
        if (a.overlaps(results[j].bounds)) {
          // Merge bounds
          merged = HandwritingSearchResult(
            strokeId: merged.strokeId,
            canvasId: merged.canvasId,
            recognizedText: merged.recognizedText,
            bounds: merged.bounds.expandToInclude(results[j].bounds),
            score: merged.score, // keep best score
          );
          used[j] = true;
        }
      }
      deduped.add(merged);
    }

    return deduped;
  }

  /// Post-filter results for case-sensitive and whole-word modes.
  ///
  /// FTS5 is always case-insensitive, so we post-filter when the user
  /// enables case-sensitive or whole-word search.
  List<HandwritingSearchResult> _postFilter(
    List<HandwritingSearchResult> results,
    String query, {
    bool caseSensitive = false,
    bool wholeWord = false,
  }) {
    if (!caseSensitive && !wholeWord) return results;

    final trimmed = query.trim();
    return results.where((r) {
      final text = r.recognizedText;
      if (caseSensitive && !text.contains(trimmed)) return false;
      if (wholeWord) {
        final pattern = RegExp(
          '\\b${RegExp.escape(trimmed)}\\b',
          caseSensitive: caseSensitive,
        );
        if (!pattern.hasMatch(text)) return false;
      }
      return true;
    }).toList();
  }

  /// Fuzzy search fallback using SQL LIKE with wildcards.
  ///
  /// When FTS5 returns no results (e.g., user typed "helo" but recognition
  /// produced "hello"), this tries a more lenient `LIKE` pattern with
  /// `%` between each character for single-char tolerance.
  Future<List<HandwritingSearchResult>> _fuzzySearch(
    String query, {
    String? canvasId,
    int limit = 50,
    bool caseSensitive = false,
    bool wholeWord = false,
  }) async {
    if (!_initialized) return const [];

    try {
      final db = _db!;
      // Build pattern: "hello" → "%h%e%l%l%o%"
      final chars = query.trim().split('');
      if (chars.isEmpty) return const [];
      final pattern = '%${chars.join('%')}%';

      String sql;
      List<Object?> args;

      if (canvasId != null) {
        sql = '''
          SELECT stroke_id, canvas_id, recognized_text,
                 bounds_left, bounds_top, bounds_right, bounds_bottom
          FROM stroke_text_map
          WHERE canvas_id = ? AND recognized_text LIKE ?
          LIMIT ?
        ''';
        args = [canvasId, pattern, limit];
      } else {
        sql = '''
          SELECT stroke_id, canvas_id, recognized_text,
                 bounds_left, bounds_top, bounds_right, bounds_bottom
          FROM stroke_text_map
          WHERE recognized_text LIKE ?
          LIMIT ?
        ''';
        args = [pattern, limit];
      }

      final rows = await db.rawQuery(sql, args);
      final results = rows.map((row) {
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
          score: 1.0, // Lower priority than FTS5 results
        );
      }).toList();

      final deduped = _deduplicateResults(results);
      return _postFilter(deduped, query,
          caseSensitive: caseSensitive, wholeWord: wholeWord);
    } catch (_) {
      return const [];
    }
  }

  // ── Suggestions ──────────────────────────────────────────────────────────

  /// Get autocomplete suggestions from indexed vocabulary.
  ///
  /// Returns distinct recognized texts matching the prefix, ordered by
  /// frequency (most common first). Used for search suggestions.
  Future<List<String>> getSuggestions(
    String prefix, {
    String? canvasId,
    int limit = 5,
  }) async {
    if (!_initialized || prefix.trim().isEmpty) return const [];

    try {
      final pattern = '${prefix.trim()}%';
      String sql;
      List<Object?> args;

      if (canvasId != null) {
        sql = '''
          SELECT recognized_text, COUNT(*) as freq
          FROM stroke_text_map
          WHERE canvas_id = ? AND recognized_text LIKE ?
          GROUP BY recognized_text
          ORDER BY freq DESC
          LIMIT ?
        ''';
        args = [canvasId, pattern, limit];
      } else {
        sql = '''
          SELECT recognized_text, COUNT(*) as freq
          FROM stroke_text_map
          WHERE recognized_text LIKE ?
          GROUP BY recognized_text
          ORDER BY freq DESC
          LIMIT ?
        ''';
        args = [pattern, limit];
      }

      final rows = await _db!.rawQuery(sql, args);
      return rows
          .map((r) => r['recognized_text'] as String)
          .where((t) => t.trim().isNotEmpty)
          .toList();
    } catch (_) {
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

  /// Get aggregated recognized text for a set of stroke IDs in a canvas.
  /// Used by the suggestion engine for per-cluster semantic scoring.
  Future<String> getTextForStrokes(
    String canvasId,
    List<String> strokeIds,
  ) async {
    if (!_initialized || strokeIds.isEmpty) return '';
    try {
      // Query in batches to avoid SQLite variable limits
      final results = <String>[];
      for (int i = 0; i < strokeIds.length; i += 50) {
        final batch = strokeIds.skip(i).take(50).toList();
        final placeholders = List.filled(batch.length, '?').join(',');
        final rows = await _db!.rawQuery(
          'SELECT recognized_text FROM stroke_text_map '
          'WHERE canvas_id = ? AND stroke_id IN ($placeholders)',
          [canvasId, ...batch],
        );
        results.addAll(rows.map((r) => r['recognized_text'] as String));
      }
      return results.join(' ');
    } catch (_) {
      return '';
    }
  }

  /// Get a map of strokeId → recognizedText for a set of stroke IDs.
  /// Used by Atlas AI to enrich canvas context with handwriting content.
  /// Note: queries by strokeId only (not canvasId) because stroke IDs are
  /// globally unique MD5 hashes, and canvasId may change between restarts.
  Future<Map<String, String>> getTextMapForStrokes(
    String canvasId,
    List<String> strokeIds,
  ) async {
    if (!_initialized || strokeIds.isEmpty) return const {};
    try {
      final map = <String, String>{};
      for (int i = 0; i < strokeIds.length; i += 50) {
        final batch = strokeIds.skip(i).take(50).toList();
        final placeholders = List.filled(batch.length, '?').join(',');
        final rows = await _db!.rawQuery(
          'SELECT stroke_id, recognized_text FROM stroke_text_map '
          'WHERE stroke_id IN ($placeholders)',
          [...batch],
        );
        for (final row in rows) {
          map[row['stroke_id'] as String] = row['recognized_text'] as String;
        }
      }
      return map;
    } catch (_) {
      return const {};
    }
  }
  // ── Pre-context (public API) ─────────────────────────────────────────────

  /// Get the last ~20 characters recognized on [canvasId] as pre-context.
  ///
  /// Feeds ML Kit's language model so it can predict the next word better.
  /// Example: if pre-context is "Il teorema di", ML Kit is more likely
  /// to recognize "Pitagora" than "Ritagora".
  Future<String?> getPreContext(String canvasId) async {
    if (!_initialized) return null;
    return _getPreContext(_db!, canvasId);
  }

  // ── Cleanup ───────────────────────────────────────────────────────────────

  /// Remove index entries for a deleted stroke.
  Future<void> removeStroke(String canvasId, String strokeId) async {
    if (!_initialized) return;
    final deleted = await _db!.delete(
      'stroke_text_map',
      where: 'stroke_id = ? AND canvas_id = ?',
      whereArgs: [strokeId, canvasId],
    );
    if (deleted > 0) _indexChangedController.add(null);
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

  /// Reconcile index with actual strokes on canvas.
  ///
  /// Removes index entries for strokes that no longer exist.
  /// Called after eraser finalization to clean up ghost entries.
  Future<void> reconcileWithStrokes(
    String canvasId,
    Set<String> existingStrokeIds,
  ) async {
    if (!_initialized) return;
    try {
      final rows = await _db!.query(
        'stroke_text_map',
        columns: ['stroke_id'],
        where: 'canvas_id = ?',
        whereArgs: [canvasId],
      );
      int removed = 0;
      for (final row in rows) {
        final id = row['stroke_id'] as String;
        if (!existingStrokeIds.contains(id)) {
          await _db!.delete(
            'stroke_text_map',
            where: 'stroke_id = ? AND canvas_id = ?',
            whereArgs: [id, canvasId],
          );
          removed++;
        }
      }
      if (removed > 0) {
        _indexChangedController.add(null);
      }
    } catch (_) {
    }
  }

  /// Get the number of indexed strokes for a canvas (or all canvases).
  Future<int> getIndexedStrokeCount({String? canvasId}) async {
    if (!_initialized || _db == null) return 0;
    try {
      final result = canvasId != null
          ? await _db!.rawQuery(
              'SELECT COUNT(DISTINCT stroke_id) as cnt FROM stroke_text_map WHERE canvas_id = ?',
              [canvasId])
          : await _db!.rawQuery(
              'SELECT COUNT(DISTINCT stroke_id) as cnt FROM stroke_text_map');
      return (result.first['cnt'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Save a search query to persistent history.
  Future<void> saveSearchHistory(String query) async {
    if (!_initialized || _db == null || query.trim().isEmpty) return;
    try {
      await _db!.insert('search_history', {
        'query': query.trim(),
        'last_used': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (_) {}
  }

  /// Load recent search history, ordered by last used.
  Future<List<String>> loadSearchHistory({int limit = 10}) async {
    if (!_initialized || _db == null) return [];
    try {
      final rows = await _db!.rawQuery(
        'SELECT query FROM search_history ORDER BY last_used DESC LIMIT ?',
        [limit],
      );
      return rows.map((r) => r['query'] as String).toList();
    } catch (_) {
      return [];
    }
  }

  /// Dispose resources.
  void dispose() {
    _batchTimer?.cancel();
    _queue.clear();
    _indexChangedController.close();
    _initialized = false;
  }
}
