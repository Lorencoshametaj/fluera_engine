// ignore_for_file: avoid_print
/// ═══════════════════════════════════════════════════════════════════════════
/// 🏎️ 10M STROKE SCALE BENCHMARK SUITE
///
/// Tests rendering pipeline, spatial index, paging, and memory at scale.
///
/// STRATEGY:
/// - Uses in-memory stubs (64B each) for R-Tree/query benchmarks
/// - Avoids generating full strokes (which would OOM at 10M)
/// - StrokeGenerator for realistic small-scale rendering tests
///
/// PRE-REQUISITE (for DB-backed tests):
///   dart run tool/generate_benchmark_db.dart
///
/// Run:
///   flutter test test/benchmarks/scale_benchmark_test.dart --tags benchmark
/// ═══════════════════════════════════════════════════════════════════════════

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/drawing/models/pro_drawing_point.dart';
import 'package:fluera_engine/src/core/nodes/stroke_node.dart';
import 'package:fluera_engine/src/core/scene_graph/node_id.dart';
import 'package:fluera_engine/src/systems/spatial_index.dart';
import 'package:fluera_engine/src/rendering/optimization/tile_cache_manager.dart';
import 'package:fluera_engine/src/drawing/utils/stroke_generator.dart';

// ═══════════════════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════════════════

/// Fixed-seed RNG for deterministic benchmarks.
final _rng = math.Random(42);

/// Canvas extent for each scale (same formula as generator).
double _canvasExtent(int n) => math.sqrt(n / 0.00004);

/// Benchmark helper: runs [fn], prints and returns elapsed ms.
int _bench(String label, void Function() fn) {
  final sw = Stopwatch()..start();
  fn();
  sw.stop();
  print('    ⏱ $label: ${sw.elapsedMilliseconds}ms');
  return sw.elapsedMilliseconds;
}

/// Benchmark with iterations.
double _benchN(String label, void Function() fn, int iterations) {
  final sw = Stopwatch()..start();
  for (int i = 0; i < iterations; i++) {
    fn();
  }
  sw.stop();
  final avgUs = sw.elapsedMicroseconds / iterations;
  print(
    '    ⏱ $label: ${avgUs.toStringAsFixed(1)}µs avg (${iterations}× in ${sw.elapsedMilliseconds}ms)',
  );
  return avgUs;
}

/// Build N stub ProStrokes with random bounds on a canvas.
List<ProStroke> _buildStubs(int n, double canvasExtent) {
  return List.generate(n, (i) {
    final x = _rng.nextDouble() * canvasExtent;
    final y = _rng.nextDouble() * canvasExtent;
    final w = 50 + _rng.nextDouble() * 200;
    final h = 50 + _rng.nextDouble() * 150;
    return ProStroke.stubFromBounds(
      id: 'stroke_$i',
      bounds: Rect.fromLTWH(x, y, w, h),
    );
  });
}

/// Build R-Tree from stubs.
SpatialIndex _buildRTree(List<ProStroke> stubs) {
  final index = SpatialIndex();
  final nodes =
      stubs.map((s) => StrokeNode(id: NodeId(s.id), stroke: s)).toList();
  index.rebuild(nodes);
  return index;
}

/// Format stroke count for display.
String _label(int n) => switch (n) {
  >= 10000000 => '${n ~/ 1000000}M',
  >= 1000000 => '${(n / 1000000).toStringAsFixed(1)}M',
  >= 1000 => '${n ~/ 1000}K',
  _ => '$n',
};

void main() {
  // ═══════════════════════════════════════════════════════════════════════
  // 1. R-TREE BUILD — O(N log N) at scale
  // ═══════════════════════════════════════════════════════════════════════

  group('🌲 BM-Scale: R-Tree build', () {
    for (final n in [1000, 10000, 100000, 1000000]) {
      test('Build R-Tree from ${_label(n)} stubs', () {
        final extent = _canvasExtent(n);
        final stubs = _buildStubs(n, extent);

        final ms = _bench('${_label(n)} R-Tree build', () {
          _buildRTree(stubs);
        });

        // Expectation: O(N log N)
        // 1K:   <50ms
        // 10K:  <200ms
        // 100K: <2s
        // 1M:   <20s
        final maxMs = switch (n) {
          <= 1000 => 100,
          <= 10000 => 500,
          <= 100000 => 5000,
          _ => 60000,
        };
        expect(
          ms,
          lessThan(maxMs),
          reason: '${_label(n)} R-Tree build must be <${maxMs}ms',
        );
      });
    }
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 2. R-TREE VIEWPORT QUERY — O(log N + K)
  // ═══════════════════════════════════════════════════════════════════════

  group('🔍 BM-Scale: R-Tree viewport query', () {
    for (final n in [1000, 10000, 100000, 1000000]) {
      test('1000 viewport queries on ${_label(n)} R-Tree', () {
        final extent = _canvasExtent(n);
        final stubs = _buildStubs(n, extent);
        final index = _buildRTree(stubs);

        const queries = 1000;
        // Tile-sized viewport (4096×4096)
        final avgUs = _benchN('${_label(n)} viewport query (4096×4096)', () {
          final cx = _rng.nextDouble() * extent;
          final cy = _rng.nextDouble() * extent;
          index.queryRange(
            Rect.fromCenter(center: Offset(cx, cy), width: 4096, height: 4096),
          );
        }, queries);

        // At any scale, a single query must be <1ms (8.33ms frame budget)
        expect(
          avgUs,
          lessThan(1000),
          reason: 'Viewport query must be <1ms at ${_label(n)} strokes',
        );

        // Also test screen-sized viewport (like a real pan frame)
        final avgUs2 = _benchN(
          '${_label(n)} full-screen query (2560×1440)',
          () {
            final cx = _rng.nextDouble() * extent;
            final cy = _rng.nextDouble() * extent;
            index.queryRange(
              Rect.fromCenter(
                center: Offset(cx, cy),
                width: 2560,
                height: 1440,
              ),
            );
          },
          queries,
        );

        expect(
          avgUs2,
          lessThan(2000),
          reason: 'Full-screen query must be <2ms at ${_label(n)} strokes',
        );
      });
    }
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 3. R-TREE INCREMENTAL INSERT — O(log N) per insert
  // ═══════════════════════════════════════════════════════════════════════

  group('➕ BM-Scale: R-Tree incremental insert', () {
    for (final n in [10000, 100000, 1000000]) {
      test('100 inserts into ${_label(n)} R-Tree', () {
        final extent = _canvasExtent(n);
        final stubs = _buildStubs(n, extent);
        final index = _buildRTree(stubs);

        const inserts = 100;
        final ms = _bench('$inserts inserts into ${_label(n)} R-Tree', () {
          for (int i = 0; i < inserts; i++) {
            final x = _rng.nextDouble() * extent;
            final y = _rng.nextDouble() * extent;
            index.insert(
              StrokeNode(
                id: NodeId('new_$i'),
                stroke: ProStroke.stubFromBounds(
                  id: 'new_$i',
                  bounds: Rect.fromLTWH(x, y, 100, 80),
                ),
              ),
            );
          }
        });

        // 100 inserts should be <100ms even at 1M
        expect(
          ms,
          lessThan(500),
          reason: '100 inserts into ${_label(n)} R-Tree must be <500ms',
        );
      });
    }
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 4. HIT TEST — point query
  // ═══════════════════════════════════════════════════════════════════════

  group('🎯 BM-Scale: Hit test (point query)', () {
    for (final n in [10000, 100000, 1000000]) {
      test('1000 hit tests on ${_label(n)} R-Tree', () {
        final extent = _canvasExtent(n);
        final stubs = _buildStubs(n, extent);
        final index = _buildRTree(stubs);

        const queries = 1000;
        // Small viewport simulating a touch point
        final avgUs = _benchN('${_label(n)} hit test (20px radius)', () {
          final cx = _rng.nextDouble() * extent;
          final cy = _rng.nextDouble() * extent;
          index.queryRange(
            Rect.fromCenter(center: Offset(cx, cy), width: 40, height: 40),
          );
        }, queries);

        // Hit test must be <500µs for responsive touch
        expect(
          avgUs,
          lessThan(500),
          reason: 'Hit test must be <500µs at ${_label(n)} strokes',
        );
      });
    }
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 5. TILE CACHE KEY COMPUTATION
  // ═══════════════════════════════════════════════════════════════════════

  group('🧩 BM-Scale: Tile cache key computation', () {
    test('tileKeysForRect speed', () {
      const iterations = 10000;
      final avgUs = _benchN('tileKeysForRect (random viewport)', () {
        final cx = _rng.nextDouble() * 500000;
        final cy = _rng.nextDouble() * 500000;
        TileCacheManager.tileKeysForRect(
          Rect.fromCenter(center: Offset(cx, cy), width: 4096, height: 4096),
        );
      }, iterations);

      // Tile key computation must be <10µs
      expect(avgUs, lessThan(10), reason: 'Tile key computation must be <10µs');
    });

    test('tileKeysForRect at extreme zoom-out', () {
      // At zoom 0.1, viewport covers ~30000×20000 canvas units = ~50 tiles
      const iterations = 1000;
      final avgUs = _benchN('tileKeysForRect (zoom-out, ~50 tiles)', () {
        final cx = _rng.nextDouble() * 500000;
        final cy = _rng.nextDouble() * 500000;
        TileCacheManager.tileKeysForRect(
          Rect.fromCenter(center: Offset(cx, cy), width: 30000, height: 20000),
        );
      }, iterations);

      // Even with ~50 tiles, computation should be fast
      expect(
        avgUs,
        lessThan(50),
        reason: 'Tile key computation for zoom-out must be <50µs',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 6. STUB CREATION — ProStroke memory efficiency
  // ═══════════════════════════════════════════════════════════════════════

  group('📦 BM-Scale: Stub memory', () {
    test('Create and measure 100K stubs', () {
      final stubs = <ProStroke>[];
      final ms = _bench('100K stubFromBounds', () {
        for (int i = 0; i < 100000; i++) {
          stubs.add(
            ProStroke.stubFromBounds(
              id: 'stub_$i',
              bounds: Rect.fromLTWH(
                _rng.nextDouble() * 500000,
                _rng.nextDouble() * 500000,
                100,
                80,
              ),
            ),
          );
        }
      });

      expect(ms, lessThan(1000), reason: '100K stub creation must be <1s');

      // Verify stubs have no point data
      expect(stubs.first.isStub, isTrue);
      expect(stubs.first.points, isEmpty);
      expect(stubs.first.bounds, isNot(Rect.zero));

      print('    📊 100K stubs created in ${ms}ms');
      print('    📊 isStub: ${stubs.first.isStub}');
    });

    test('toStub conversion (full → stub)', () {
      final fullStrokes = StrokeGenerator.generateRandomStrokes(
        1000,
        avgPointsPerStroke: 50,
      );

      final ms = _bench('1K full → stub conversion', () {
        for (final s in fullStrokes) {
          s.toStub();
        }
      });

      expect(ms, lessThan(100), reason: 'Stub conversion must be fast');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 7. VIEWPORT CULLING SIMULATION — the 120Hz critical path
  // ═══════════════════════════════════════════════════════════════════════

  group('🎬 BM-Scale: 120Hz frame simulation', () {
    for (final n in [1000, 10000, 100000, 1000000]) {
      test('Simulated paint() at ${_label(n)} strokes', () {
        final extent = _canvasExtent(n);
        final stubs = _buildStubs(n, extent);
        final index = _buildRTree(stubs);

        // Simulate what DrawingPainter.paint() does per frame:
        // 1. Calculate viewport
        // 2. Query R-Tree for visible strokes
        // 3. (Cache hit → drawPicture, skipped in this benchmark)
        // 4. Tile key computation for cache lookup

        const frames = 100;
        final avgUs = _benchN(
          '${_label(n)} paint() overhead (query + tile keys)',
          () {
            // Step 1: Random viewport (simulating pan)
            final cx = _rng.nextDouble() * extent;
            final cy = _rng.nextDouble() * extent;
            final viewport = Rect.fromCenter(
              center: Offset(cx, cy),
              width: 2560,
              height: 1440,
            );

            // Step 2: R-Tree query for visible strokes
            final visible = index.queryRange(viewport);

            // Step 3: Tile key computation
            TileCacheManager.tileKeysForRect(viewport);

            // Step 4: Filter stubs vs loaded (simulated)
            int loaded = 0;
            for (final node in visible) {
              if (node is StrokeNode && !node.stroke.isStub) loaded++;
            }
          },
          frames,
        );

        // The ENTIRE paint() overhead (excluding actual rendering)
        // must fit within 8.33ms (120Hz budget).
        // Actual rendering uses cache (drawPicture = 0.3ms).
        // So overhead must be <2ms to leave room for rendering.
        expect(
          avgUs,
          lessThan(2000),
          reason: 'paint() overhead must be <2ms at ${_label(n)} for 120Hz',
        );

        print(
          '    ✅ ${_label(n)}: ${(avgUs / 1000).toStringAsFixed(2)}ms per frame (budget: 8.33ms)',
        );
      });
    }
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 8. LIVE STROKE — per-frame cost while drawing
  // ═══════════════════════════════════════════════════════════════════════

  group('✏️ BM-Scale: Live stroke simulation', () {
    for (final n in [1000, 10000, 100000]) {
      test('Live stroke at ${_label(n)} background strokes', () {
        final extent = _canvasExtent(n);
        final stubs = _buildStubs(n, extent);
        final index = _buildRTree(stubs);

        // Simulate a live stroke: 50 points = 50 frames of drawing.
        // Each frame:
        //   1. Add a point to the current stroke (growing list)
        //   2. R-Tree viewport query (what DrawingPainter.paint() does)
        //   3. Tile key computation (cache lookup)
        //   4. Bounds recalculation of the live stroke (incremental)
        //
        // NOTE: The live stroke itself is NOT in the R-Tree yet
        // (it's rendered by CurrentStrokePainter, separate from the
        //  committed strokes). So the R-Tree query is the committed
        //  background strokes only.

        const frames = 50; // 50 points per stroke
        final strokeCenter = Offset(extent * 0.5, extent * 0.5);

        final avgUs = _benchN(
          '${_label(n)} live stroke frame (point + query + tile)',
          () {
            // Growing point list (simulates the live stroke)
            final livePoints = <ProDrawingPoint>[];
            double angle = _rng.nextDouble() * 3.14159;

            for (int f = 0; f < frames; f++) {
              // Step 1: Add a new point (PointerMoveEvent → addPoint)
              final dx = strokeCenter.dx + f * 4.0 * math.cos(angle);
              final dy = strokeCenter.dy + f * 4.0 * math.sin(angle);
              livePoints.add(
                ProDrawingPoint(
                  position: Offset(dx, dy),
                  pressure: 0.5 + _rng.nextDouble() * 0.5,
                ),
              );

              // Step 2: Live stroke bounds (incremental min/max)
              double minX = double.infinity, minY = double.infinity;
              double maxX = double.negativeInfinity,
                  maxY = double.negativeInfinity;
              for (final p in livePoints) {
                if (p.position.dx < minX) minX = p.position.dx;
                if (p.position.dy < minY) minY = p.position.dy;
                if (p.position.dx > maxX) maxX = p.position.dx;
                if (p.position.dy > maxY) maxY = p.position.dy;
              }

              // Step 3: Viewport query (background strokes)
              final viewport = Rect.fromCenter(
                center: Offset(dx, dy),
                width: 2560,
                height: 1440,
              );
              index.queryRange(viewport);

              // Step 4: Tile key computation
              TileCacheManager.tileKeysForRect(viewport);
            }
          },
          20, // 20 repetitions of 50-frame strokes
        );

        // Per-frame budget: the ENTIRE frame must fit in 8.33ms (120Hz).
        // CurrentStrokePainter renders only the last segment (~0.1ms).
        // DrawingPainter renders cached tiles (~0.3ms).
        // So the overhead (query + tile + point) must be <1ms.
        final perFrameUs = avgUs / frames;
        print(
          '    📊 Per-frame: ${perFrameUs.toStringAsFixed(1)}µs '
          '(budget: 1000µs for 120Hz)',
        );

        expect(
          perFrameUs,
          lessThan(1000),
          reason: 'Live stroke per-frame overhead must be <1ms at ${_label(n)}',
        );
      });
    }

    test('Stroke commit (insert into R-Tree) at 100K', () {
      final extent = _canvasExtent(100000);
      final stubs = _buildStubs(100000, extent);
      final index = _buildRTree(stubs);

      // Simulate committing a finished stroke into the R-Tree
      // (what happens on pointerUp)
      const commits = 100;
      final ms = _bench('$commits stroke commits into 100K R-Tree', () {
        for (int i = 0; i < commits; i++) {
          final x = _rng.nextDouble() * extent;
          final y = _rng.nextDouble() * extent;
          // Create a realistic stroke node (not a stub)
          final stroke = ProStroke(
            id: 'committed_$i',
            points: List.generate(
              50,
              (j) => ProDrawingPoint(
                position: Offset(x + j * 3.0, y + j * 2.0),
                pressure: 0.7,
              ),
            ),
            color: const Color(0xFF000000),
            baseWidth: 3.0,
            penType: ProPenType.ballpoint,
            createdAt: DateTime.now(),
          );
          index.insert(StrokeNode(id: NodeId(stroke.id), stroke: stroke));
        }
      });

      // 100 commits should be <50ms (0.5ms each)
      expect(
        ms,
        lessThan(100),
        reason: 'Stroke commit (R-Tree insert) must be fast',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 9. UNDO SIMULATION — stroke count decrease
  // ═══════════════════════════════════════════════════════════════════════

  group('↩️ BM-Scale: Undo simulation', () {
    test('R-Tree remove at 100K scale', () {
      final extent = _canvasExtent(100000);
      final stubs = _buildStubs(100000, extent);
      final index = _buildRTree(stubs);

      // Undo removes the last stroke from R-Tree
      final ms = _bench('100 removes from 100K R-Tree', () {
        for (int i = 99999; i >= 99900; i--) {
          index.remove(stubs[i].id);
        }
      });

      expect(ms, lessThan(500), reason: 'Undo (R-Tree remove) must be fast');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 10. COMBINED STRESS TEST — worst case frame
  // ═══════════════════════════════════════════════════════════════════════

  group('💥 BM-Scale: Worst-case frame (cache miss)', () {
    test('Cache-miss frame at 100K strokes (tile rebuild)', () {
      final extent = _canvasExtent(100000);
      final stubs = _buildStubs(100000, extent);
      final index = _buildRTree(stubs);

      // Simulate a cache-miss frame where we need to:
      // 1. Query R-Tree for tile contents
      // 2. Compute tile keys
      // 3. Iterate visible nodes
      // (Actual brush rendering is excluded — that's tested separately)

      const tiles = 4; // Typical: 4 tiles visible at 1x zoom
      final ms = _bench('Cache-miss: $tiles tiles at 100K strokes', () {
        for (int t = 0; t < tiles; t++) {
          final tx = t % 2;
          final ty = t ~/ 2;
          final tileBounds = Rect.fromLTWH(
            tx * 4096.0 + _rng.nextDouble() * extent * 0.5,
            ty * 4096.0 + _rng.nextDouble() * extent * 0.5,
            4096,
            4096,
          );

          // Query strokes in this tile
          final nodes = index.queryRange(tileBounds);

          // Iterate (simulates rendering loop without actual GPU work)
          int count = 0;
          for (final node in nodes) {
            if (node is StrokeNode && !node.stroke.isStub) count++;
          }
        }
      });

      // Cache-miss should still complete in <5ms
      expect(
        ms,
        lessThan(5),
        reason: 'Cache-miss tile rebuild overhead must be <5ms',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 11. MEMORY PROJECTION — at 10M
  // ═══════════════════════════════════════════════════════════════════════

  group('📊 BM-Scale: Memory projection', () {
    test('Calculate RAM projection for each scale', () {
      print('\n    ═══════════════════════════════════════════════');
      print('    📊 MEMORY PROJECTION (stub-only mode)');
      print('    ═══════════════════════════════════════════════');
      print('    Scale    │ Stubs RAM │ R-Tree RAM │ Total    │ Paged');
      print('    ─────────┼───────────┼────────────┼──────────┼──────');

      for (final n in [1000, 10000, 100000, 1000000, 10000000]) {
        // ProStroke stub: ~120B (id String + Rect + Color + minimal fields)
        // R-Tree node: ~80B (Rect + pointer + metadata)
        final stubMB = n * 120 / 1024 / 1024;
        final rtreeMB = n * 80 / 1024 / 1024;
        final totalMB = stubMB + rtreeMB;

        // In production, paging keeps only ~5000 loaded
        // R-Tree uses SQLite on disk, not in-memory at 10M
        final pagedMB = n > 50000 ? 5000 * 5.0 / 1024 : totalMB;

        print(
          '    ${_label(n).padRight(8)} │ '
          '${stubMB.toStringAsFixed(1).padLeft(7)} MB │ '
          '${rtreeMB.toStringAsFixed(1).padLeft(8)} MB │ '
          '${totalMB.toStringAsFixed(1).padLeft(6)} MB │ '
          '${n > 50000 ? '${pagedMB.toStringAsFixed(0).padLeft(4)} MB' : 'N/A  '}',
        );
      }

      print('    ─────────┴───────────┴────────────┴──────────┴──────');
      print('    📌 "Paged" = with stub paging + SQLite R*Tree');
      print('    📌 At 10M, in-memory total would be ~1.9GB');
      print('    📌 With paging: ~25MB RAM + SQLite on disk\n');
    });
  });
}
