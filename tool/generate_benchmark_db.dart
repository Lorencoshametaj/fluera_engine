// ignore_for_file: avoid_print
/// ═══════════════════════════════════════════════════════════════════════════
/// 🧪 BENCHMARK DB GENERATOR
///
/// Generates pre-built SQLite databases with synthetic stroke data for
/// performance benchmarking at scale (1K → 10M strokes).
///
/// The generated DB uses the EXACT same schema as the production engine:
///   - stroke_pages:     StrokePagingManager table (JSON + bounds)
///   - stroke_rtree:     PersistentSpatialIndex R*Tree (bounds)
///   - stroke_rtree_meta: R*Tree integer ID ↔ stroke string ID mapping
///
/// USAGE:
///   cd fluera_engine
///   dart run tool/generate_benchmark_db.dart [scale]
///
///   scale: 1k, 10k, 100k, 1m, 10m (default: all)
///
/// OUTPUT:
///   tool/benchmark_data/benchmark_1K.db    (~0.2MB)
///   tool/benchmark_data/benchmark_10K.db   (~2MB)
///   tool/benchmark_data/benchmark_100K.db  (~20MB)
///   tool/benchmark_data/benchmark_1M.db    (~200MB)
///   tool/benchmark_data/benchmark_10M.db   (~2GB)
///
/// Each DB can be opened by StrokePagingManager.loadStubsFromIndex() and
/// PersistentSpatialIndex.queryRange() for realistic performance tests.
/// ═══════════════════════════════════════════════════════════════════════════
import 'dart:io';
import 'dart:math' as math;
import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CONFIGURATION
// ═══════════════════════════════════════════════════════════════════════════

/// Canvas size scales with stroke count to maintain realistic density.
/// ~0.04 strokes/pixel² → similar to a real dense drawing session.
const Map<String, int> _scales = {
  '1k': 1000,
  '10k': 10000,
  '100k': 100000,
  '1m': 1000000,
  '10m': 10000000,
};

/// Canvas extent for each scale (strokes spread over this area).
double _canvasExtent(int strokeCount) {
  // √(count / density) where density ≈ 0.04 strokes/pixel²
  return math.sqrt(strokeCount / 0.00004);
}

/// Points per stroke (realistic range 20-80, avg 50).
const int _avgPoints = 50;
const int _pointVariation = 30;

/// Batch size for SQLite transactions (balance: speed vs memory).
const int _batchSize = 5000;

/// Available pen types (weighted toward common ones).
const List<String> _penTypes = [
  'ProPenType.ballpoint',
  'ProPenType.ballpoint',
  'ProPenType.ballpoint', // 3/8 ballpoint
  'ProPenType.fountain',
  'ProPenType.fountain', // 2/8 fountain
  'ProPenType.pencil', // 1/8 pencil
  'ProPenType.highlighter', // 1/8 highlighter
  'ProPenType.charcoal', // 1/8 charcoal
];

// ═══════════════════════════════════════════════════════════════════════════
// MAIN
// ═══════════════════════════════════════════════════════════════════════════

Future<void> main(List<String> args) async {
  // Initialize sqflite FFI for desktop/CLI usage
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final outputDir = Directory('tool/benchmark_data');
  if (!outputDir.existsSync()) {
    outputDir.createSync(recursive: true);
  }

  // Parse args: which scales to generate
  final requested = args.isEmpty ? _scales.keys.toList() : args;

  for (final key in requested) {
    final count = _scales[key.toLowerCase()];
    if (count == null) {
      print('⚠️  Unknown scale "$key". Valid: ${_scales.keys.join(', ')}');
      continue;
    }
    await _generateBenchmarkDb(count, key.toUpperCase(), outputDir.path);
  }

  print('\n✅ All done!');
}

// ═══════════════════════════════════════════════════════════════════════════
// GENERATOR
// ═══════════════════════════════════════════════════════════════════════════

Future<void> _generateBenchmarkDb(
  int strokeCount,
  String label,
  String outputDir,
) async {
  final dbPath = '$outputDir/benchmark_$label.db';

  // Delete old DB if exists
  final file = File(dbPath);
  if (file.existsSync()) {
    file.deleteSync();
    print('🗑️  Deleted old $dbPath');
  }

  print('\n═══════════════════════════════════════════════════');
  print('🧪 Generating benchmark_$label.db ($strokeCount strokes)');
  print('═══════════════════════════════════════════════════');

  final sw = Stopwatch()..start();
  final db = await openDatabase(dbPath);

  // ─── Create tables (exact production schema) ──────────────────────────

  // 1. stroke_pages — StrokePagingManager
  await db.execute('''
    CREATE TABLE IF NOT EXISTS stroke_pages (
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
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_stroke_pages_canvas
    ON stroke_pages(canvas_id)
  ''');

  // 2. stroke_rtree — PersistentSpatialIndex R*Tree
  await db.execute('''
    CREATE VIRTUAL TABLE IF NOT EXISTS stroke_rtree USING rtree(
      id,
      min_x, max_x,
      min_y, max_y
    )
  ''');

  // 3. stroke_rtree_meta — ID mapping
  await db.execute('''
    CREATE TABLE IF NOT EXISTS stroke_rtree_meta (
      rowid     INTEGER PRIMARY KEY,
      stroke_id TEXT NOT NULL UNIQUE,
      node_type INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_rtree_meta_stroke
    ON stroke_rtree_meta(stroke_id)
  ''');

  print('  📦 Tables created (${sw.elapsedMilliseconds}ms)');

  // ─── Generate and insert strokes in batches ───────────────────────────

  final rng = math.Random(42); // Deterministic seed
  final canvasExtent = _canvasExtent(strokeCount);
  final numLayers = math.min(5, math.max(1, strokeCount ~/ 2000));
  int inserted = 0;

  // Disable journal for bulk insert speed
  await db.execute('PRAGMA journal_mode = OFF');
  await db.execute('PRAGMA synchronous = OFF');
  await db.execute('PRAGMA cache_size = -64000'); // 64MB cache

  while (inserted < strokeCount) {
    final batchEnd = math.min(inserted + _batchSize, strokeCount);
    final batchCount = batchEnd - inserted;

    await db.transaction((txn) async {
      for (int i = inserted; i < batchEnd; i++) {
        final strokeId = 'stroke_$i';
        final layerIdx = i % numLayers;
        final layerId = 'layer_$layerIdx';

        // ─── Generate realistic stroke geometry ─────────────────────

        // Random start position on canvas
        final startX = rng.nextDouble() * canvasExtent;
        final startY = rng.nextDouble() * canvasExtent;

        // Random stroke direction and length
        final angle = rng.nextDouble() * 2 * math.pi;
        final length = 30.0 + rng.nextDouble() * 200.0;
        final points = _avgPoints + rng.nextInt(_pointVariation) - (_pointVariation ~/ 2);

        // Stroke bounds (approximation from start + direction)
        final endX = startX + math.cos(angle) * length;
        final endY = startY + math.sin(angle) * length;
        final baseWidth = 1.5 + rng.nextDouble() * 5.0;
        final padding = baseWidth * 2;

        final boundsL = math.min(startX, endX) - padding;
        final boundsT = math.min(startY, endY) - padding;
        final boundsR = math.max(startX, endX) + padding;
        final boundsB = math.max(startY, endY) + padding;

        // ─── Generate compact JSON (realistic point data) ────────

        final penType = _penTypes[rng.nextInt(_penTypes.length)];
        final color = 0xFF000000 + rng.nextInt(0xFFFFFF);
        final ts = 1709460000000 + i; // Base timestamp

        // Generate point array: [[x, y, pressure], ...]
        final pointArray = <List<double>>[];
        var cx = startX, cy = startY;
        var dir = angle;

        for (int p = 0; p < points; p++) {
          final pressure = 0.3 + rng.nextDouble() * 0.7;
          pointArray.add([
            (cx * 1000).round() / 1000,
            (cy * 1000).round() / 1000,
            (pressure * 100).round() / 100,
          ]);

          // Move along stroke path with gentle curvature
          dir += (rng.nextDouble() - 0.5) * 0.3;
          final step = length / points;
          cx += math.cos(dir) * step;
          cy += math.sin(dir) * step;
        }

        final strokeJson = jsonEncode({
          'id': strokeId,
          'ev': 2,
          'points': pointArray,
          'color': color,
          'baseWidth': (baseWidth * 10).round() / 10,
          'penType': penType,
          'createdAt': DateTime.fromMillisecondsSinceEpoch(ts).toIso8601String(),
        });

        // ─── Insert into stroke_pages (paging manager) ───────────

        await txn.rawInsert(
          'INSERT INTO stroke_pages '
          '(stroke_id, canvas_id, layer_id, stroke_json, bounds_l, bounds_t, bounds_r, bounds_b) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
          [strokeId, 'benchmark', layerId, strokeJson, boundsL, boundsT, boundsR, boundsB],
        );

        // ─── Insert into stroke_rtree_meta (ID mapping) ──────────

        await txn.rawInsert(
          'INSERT INTO stroke_rtree_meta (rowid, stroke_id, node_type) '
          'VALUES (?, ?, 0)',
          [i + 1, strokeId],
        );

        // ─── Insert into stroke_rtree (R*Tree) ──────────────────

        await txn.rawInsert(
          'INSERT INTO stroke_rtree (id, min_x, max_x, min_y, max_y) '
          'VALUES (?, ?, ?, ?, ?)',
          [i + 1, boundsL, boundsR, boundsT, boundsB],
        );
      }
    });

    inserted = batchEnd;

    // Progress log every 10% or every batch for small counts
    final pct = (inserted / strokeCount * 100).round();
    if (pct % 10 == 0 || strokeCount < 10000) {
      final elapsed = sw.elapsedMilliseconds;
      final rate = inserted / (elapsed / 1000);
      final eta = ((strokeCount - inserted) / rate).round();
      print(
        '  📝 ${inserted.toFormattedString()}/$label '
        '(${pct}%) — ${rate.round()} strokes/s — ETA ${eta}s',
      );
    }
  }

  // ─── Finalize ──────────────────────────────────────────────────────────

  // Re-enable journal for normal operation
  await db.execute('PRAGMA journal_mode = WAL');
  await db.execute('PRAGMA synchronous = NORMAL');

  // Optimize the DB
  await db.execute('ANALYZE');

  await db.close();

  // Print stats
  final fileSize = File(dbPath).lengthSync();
  final elapsed = sw.elapsedMilliseconds;
  final rate = strokeCount / (elapsed / 1000);

  print('  ──────────────────────────────────────────────');
  print('  ✅ benchmark_$label.db generated!');
  print('     Strokes: ${strokeCount.toFormattedString()}');
  print('     Layers:  $numLayers');
  print('     Canvas:  ${canvasExtent.round()} × ${canvasExtent.round()} px');
  print('     DB size: ${_formatBytes(fileSize)}');
  print('     Time:    ${(elapsed / 1000).toStringAsFixed(1)}s');
  print('     Rate:    ${rate.round()} strokes/s');
}

// ═══════════════════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════════════════

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  } else if (bytes >= 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  } else if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '$bytes B';
}

extension on int {
  String toFormattedString() {
    final s = toString();
    final sb = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) sb.write(',');
      sb.write(s[i]);
    }
    return sb.toString();
  }
}
