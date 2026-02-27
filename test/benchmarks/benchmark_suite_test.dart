// ignore_for_file: avoid_print
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/vector/vector_network.dart';
import 'package:fluera_engine/src/core/vector/spatial_index.dart';
import 'package:fluera_engine/src/core/vector/exact_boolean_ops.dart';
import 'package:fluera_engine/src/core/vector/boolean_ops.dart';
import 'package:fluera_engine/src/core/vector/vector_path.dart';
import 'package:fluera_engine/src/core/vector/anchor_point.dart';
import 'package:fluera_engine/src/core/tabular/cell_address.dart';
import 'package:fluera_engine/src/reflow/reflow_physics_engine.dart';
import 'package:fluera_engine/src/reflow/content_cluster.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// 🏎️ DETERMINISTIC BENCHMARK SUITE
///
/// Pure-logic performance benchmarks. Results are printed for analysis.
/// Each test asserts an upper time bound to catch severe regressions.
///
/// Run with: flutter test test/benchmarks/benchmark_suite_test.dart
/// ═══════════════════════════════════════════════════════════════════════════

void main() {
  final rng = math.Random(42); // fixed seed → deterministic

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Build a VectorNetwork with [n] random vertices and (n-1) segments.
  VectorNetwork buildNetwork(int n, {double range = 10000}) {
    final net = VectorNetwork();
    for (int i = 0; i < n; i++) {
      net.addVertex(
        NetworkVertex(
          position: Offset(rng.nextDouble() * range, rng.nextDouble() * range),
        ),
      );
    }
    for (int i = 0; i < n - 1; i++) {
      net.addSegment(NetworkSegment(start: i, end: i + 1));
    }
    return net;
  }

  /// Build a rectangle VectorNetwork for boolean ops.
  VectorNetwork buildRect(double x, double y, double w, double h) {
    final net = VectorNetwork();
    final v0 = net.addVertex(NetworkVertex(position: Offset(x, y)));
    final v1 = net.addVertex(NetworkVertex(position: Offset(x + w, y)));
    final v2 = net.addVertex(NetworkVertex(position: Offset(x + w, y + h)));
    final v3 = net.addVertex(NetworkVertex(position: Offset(x, y + h)));
    final s0 = net.addSegment(NetworkSegment(start: v0, end: v1));
    final s1 = net.addSegment(NetworkSegment(start: v1, end: v2));
    final s2 = net.addSegment(NetworkSegment(start: v2, end: v3));
    final s3 = net.addSegment(NetworkSegment(start: v3, end: v0));
    net.addRegion(
      NetworkRegion(
        loops: [
          RegionLoop(
            segments: [
              SegmentRef(index: s0),
              SegmentRef(index: s1),
              SegmentRef(index: s2),
              SegmentRef(index: s3),
            ],
          ),
        ],
      ),
    );
    return net;
  }

  /// Benchmark helper: runs [fn], prints and returns elapsed ms.
  int bench(String label, void Function() fn) {
    final sw = Stopwatch()..start();
    fn();
    sw.stop();
    print('  ⏱ $label: ${sw.elapsedMilliseconds}ms');
    return sw.elapsedMilliseconds;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 1. VECTOR NETWORK — INSERT (addVertex + addSegment)
  // ═══════════════════════════════════════════════════════════════════════════

  group('BM1: VectorNetwork — insert', () {
    test('1K vertices + segments', () {
      final ms = bench('1K insert', () => buildNetwork(1000));
      expect(ms, lessThan(500));
    });

    test('5K vertices + segments', () {
      final ms = bench('5K insert', () => buildNetwork(5000));
      expect(ms, lessThan(2000));
    });

    test('10K vertices + segments', () {
      final ms = bench('10K insert', () => buildNetwork(10000));
      expect(ms, lessThan(5000));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. VECTOR NETWORK — SERIALIZATION (toJson / fromJson)
  // ═══════════════════════════════════════════════════════════════════════════

  group('BM2: VectorNetwork — serialization', () {
    test('1K toJson + fromJson round-trip', () {
      final net = buildNetwork(1000);
      late Map<String, dynamic> json;
      final msTo = bench('1K toJson', () {
        json = net.toJson();
      });
      final msFrom = bench('1K fromJson', () {
        VectorNetwork.fromJson(json);
      });
      expect(msTo + msFrom, lessThan(1000));
    });

    test('5K toJson + fromJson round-trip', () {
      final net = buildNetwork(5000);
      late Map<String, dynamic> json;
      final msTo = bench('5K toJson', () {
        json = net.toJson();
      });
      final msFrom = bench('5K fromJson', () {
        VectorNetwork.fromJson(json);
      });
      expect(msTo + msFrom, lessThan(3000));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. R-TREE SPATIAL INDEX — build + query
  // ═══════════════════════════════════════════════════════════════════════════

  group('BM3: NetworkSpatialIndex — R-tree', () {
    test('1K build + 1000 queries', () {
      final net = buildNetwork(1000);
      late NetworkSpatialIndex idx;
      final msBuild = bench('1K R-tree build', () {
        idx = NetworkSpatialIndex.build(net);
      });

      final msQuery = bench('1K × 1000 queryVertices', () {
        for (int i = 0; i < 1000; i++) {
          final cx = rng.nextDouble() * 10000;
          final cy = rng.nextDouble() * 10000;
          idx.queryVertices(
            Rect.fromCenter(center: Offset(cx, cy), width: 500, height: 500),
          );
        }
      });
      expect(msBuild, lessThan(500));
      expect(msQuery, lessThan(500));
    });

    test('10K build + 1000 queries', () {
      final net = buildNetwork(10000);
      late NetworkSpatialIndex idx;
      final msBuild = bench('10K R-tree build', () {
        idx = NetworkSpatialIndex.build(net);
      });

      final msQuery = bench('10K × 1000 queryVertices', () {
        for (int i = 0; i < 1000; i++) {
          final cx = rng.nextDouble() * 10000;
          final cy = rng.nextDouble() * 10000;
          idx.queryVertices(
            Rect.fromCenter(center: Offset(cx, cy), width: 500, height: 500),
          );
        }
      });
      expect(msBuild, lessThan(2000));
      expect(msQuery, lessThan(500), reason: 'R-tree query should be O(log N)');
    });

    test('10K nearestVertex × 1000', () {
      final net = buildNetwork(10000);
      final idx = NetworkSpatialIndex.build(net);

      final ms = bench('10K × 1000 nearestVertex', () {
        for (int i = 0; i < 1000; i++) {
          idx.nearestVertex(
            Offset(rng.nextDouble() * 10000, rng.nextDouble() * 10000),
            200,
          );
        }
      });
      expect(ms, lessThan(500));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. BOOLEAN OPS — union / intersect
  // ═══════════════════════════════════════════════════════════════════════════

  group('BM4: ExactBooleanOps', () {
    test('union 100 overlapping rectangle pairs', () {
      final ms = bench('100 × union', () {
        for (int i = 0; i < 100; i++) {
          final a = buildRect(i * 10.0, 0, 100, 100);
          final b = buildRect(i * 10.0 + 50, 50, 100, 100);
          ExactBooleanOps.execute(BooleanOpType.union, a, b);
        }
      });
      expect(ms, lessThan(5000));
    });

    test('intersect 100 overlapping rectangle pairs', () {
      final ms = bench('100 × intersect', () {
        for (int i = 0; i < 100; i++) {
          final a = buildRect(0, i * 10.0, 100, 100);
          final b = buildRect(50, i * 10.0 + 50, 100, 100);
          ExactBooleanOps.execute(BooleanOpType.intersect, a, b);
        }
      });
      expect(ms, lessThan(5000));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 5. REFLOW PHYSICS ENGINE — collision resolution
  // ═══════════════════════════════════════════════════════════════════════════

  group('BM5: ReflowPhysicsEngine', () {
    test('50 clusters estimateDisplacements', () {
      final engine = ReflowPhysicsEngine(config: const ReflowConfig());
      final clusters = List.generate(50, (i) {
        final x = (i % 10) * 120.0;
        final y = (i ~/ 10) * 120.0;
        return ContentCluster(
          id: 'c$i',
          strokeIds: ['s$i'],
          centroid: Offset(x + 50, y + 50),
          bounds: Rect.fromLTWH(x, y, 100, 100),
        );
      });
      final disturbance = const Rect.fromLTWH(200, 200, 300, 300);

      final ms = bench('50 clusters × estimateDisplacements', () {
        for (int i = 0; i < 100; i++) {
          engine.estimateDisplacements(
            clusters: clusters,
            disturbance: disturbance,
            excludeIds: {},
          );
        }
      });
      expect(ms, lessThan(2000));
    });

    test('50 clusters solve', () {
      final engine = ReflowPhysicsEngine(config: const ReflowConfig());
      final clusters = List.generate(50, (i) {
        final x = (i % 10) * 80.0; // tighter spacing → more collisions
        final y = (i ~/ 10) * 80.0;
        return ContentCluster(
          id: 'c$i',
          strokeIds: ['s$i'],
          centroid: Offset(x + 50, y + 50),
          bounds: Rect.fromLTWH(x, y, 100, 100),
        );
      });

      final ms = bench('50 clusters × solve', () {
        engine.solve(
          clusters: clusters,
          disturbance: const Rect.fromLTWH(100, 100, 400, 400),
          excludeIds: {},
        );
      });
      expect(ms, lessThan(2000));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 6. TABULAR ENGINE — CellAddress/CellRange
  // ═══════════════════════════════════════════════════════════════════════════

  group('BM6: CellAddress / CellRange', () {
    test('10K fromLabel parses', () {
      final labels = <String>[];
      for (int c = 0; c < 100; c++) {
        for (int r = 1; r <= 100; r++) {
          final col = String.fromCharCode(65 + (c % 26));
          final prefix = c >= 26 ? String.fromCharCode(65 + (c ~/ 26) - 1) : '';
          labels.add('$prefix$col$r');
        }
      }

      final ms = bench('10K fromLabel', () {
        for (final l in labels) {
          CellAddress.fromLabel(l);
        }
      });
      expect(ms, lessThan(500));
    });

    test('CellRange 100×100 iteration', () {
      final range = CellRange(
        const CellAddress(0, 0),
        const CellAddress(99, 99),
      );

      final ms = bench('100×100 range → 10K addresses', () {
        int count = 0;
        for (final _ in range.addresses) {
          count++;
        }
        expect(count, 10000);
      });
      expect(ms, lessThan(500));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 7. VECTOR PATH — anchor point conversions
  // ═══════════════════════════════════════════════════════════════════════════

  group('BM7: VectorPath / AnchorPoint conversions', () {
    test('1K anchors → VectorPath → anchors round-trip', () {
      final anchors = List.generate(
        1000,
        (i) => AnchorPoint(
          position: Offset(i * 10.0, rng.nextDouble() * 500),
          handleOut: i < 999 ? Offset(3, rng.nextDouble() * 5) : null,
          handleIn: i > 0 ? Offset(-3, rng.nextDouble() * -5) : null,
        ),
      );

      final ms = bench('1K anchor → path → anchor', () {
        for (int rep = 0; rep < 100; rep++) {
          final path = AnchorPoint.toVectorPath(anchors);
          AnchorPoint.fromVectorPath(path);
        }
      });
      expect(ms, lessThan(3000));
    });
  });
}
