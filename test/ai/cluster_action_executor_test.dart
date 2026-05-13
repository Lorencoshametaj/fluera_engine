import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/ai/cluster_action.dart';
import 'package:fluera_engine/src/ai/cluster_action_executor.dart';
import 'package:fluera_engine/src/layers/layer_controller.dart';
import 'package:fluera_engine/src/reflow/content_cluster.dart';
import '../helpers/test_helpers.dart';

void main() {
  group('ClusterActionExecutor', () {
    late LayerController lc;
    late Map<String, ContentCluster> clustersById;
    late ClusterActionExecutor executor;
    late Set<String> touchedClustersFromCallback;

    setUp(() {
      lc = LayerController();
      clustersById = {};
      touchedClustersFromCallback = <String>{};
      executor = ClusterActionExecutor(
        clusterResolver: (id) => clustersById[id],
        layerController: lc,
        onComplete: (touched) => touchedClustersFromCallback = touched,
      );
    });

    ContentCluster _seedCluster({
      required String id,
      required List<String> strokeIds,
      Rect bounds = const Rect.fromLTWH(0, 0, 100, 50),
    }) {
      // Push strokes into the active layer so the executor can find them.
      for (final sid in strokeIds) {
        lc.addStroke(testStroke(id: sid));
      }
      final c = ContentCluster(
        id: id,
        strokeIds: strokeIds,
        bounds: bounds,
        centroid: bounds.center,
      );
      clustersById[id] = c;
      return c;
    }

    test('MoveCluster shifts every stroke in the cluster by (dx, dy)', () async {
      final cluster = _seedCluster(
        id: 'c1',
        strokeIds: ['s1', 's2', 's3'],
        bounds: const Rect.fromLTWH(0, 0, 80, 40),
      );

      final report = await executor.executeAll([
        const MoveClusterAction(clusterId: 'c1', dx: 50, dy: -10),
      ]);

      expect(report.actionsApplied, 1);
      expect(report.touchedClusterIds, contains('c1'));
      expect(report.skipped, isEmpty);

      // Every stroke now starts at (50, -10) instead of (0, 0) (testStroke
      // builds points along a y = x diagonal).
      final layer = lc.activeLayer!;
      for (final sid in ['s1', 's2', 's3']) {
        final s = layer.strokes.firstWhere((s) => s.id == sid);
        expect(s.points.first.position.dx, 50);
        expect(s.points.first.position.dy, -10);
      }

      // Cluster geometry stays consistent for subsequent actions.
      expect(cluster.bounds.left, 50);
      expect(cluster.bounds.top, -10);
      expect(cluster.centroid.dx, 50 + 40);
      expect(cluster.centroid.dy, -10 + 20);
    });

    test('MoveCluster on pinned cluster is a no-op', () async {
      final pinned = ContentCluster(
        id: 'c_pinned',
        strokeIds: ['p1'],
        bounds: const Rect.fromLTWH(0, 0, 50, 50),
        centroid: const Offset(25, 25),
        isPinned: true,
      );
      lc.addStroke(testStroke(id: 'p1'));
      clustersById['c_pinned'] = pinned;

      final report = await executor.executeAll([
        const MoveClusterAction(clusterId: 'c_pinned', dx: 100, dy: 100),
      ]);

      // Action skipped: nothing applied, cluster geometry unchanged.
      expect(report.actionsApplied, 0);
      expect(pinned.centroid, const Offset(25, 25));
      final stroke =
          lc.activeLayer!.strokes.firstWhere((s) => s.id == 'p1');
      expect(stroke.points.first.position, Offset.zero);
    });

    test('MoveCluster with unknown id is reported as skipped', () async {
      final report = await executor.executeAll([
        const MoveClusterAction(clusterId: 'ghost', dx: 10, dy: 10),
      ]);
      expect(report.actionsApplied, 0);
      expect(report.skipped, contains('ghost'));
    });

    test('AlignClusters left moves every cluster to the leftmost edge',
        () async {
      _seedCluster(
        id: 'a',
        strokeIds: ['a1'],
        bounds: const Rect.fromLTWH(0, 0, 60, 40),
      );
      _seedCluster(
        id: 'b',
        strokeIds: ['b1'],
        bounds: const Rect.fromLTWH(100, 0, 60, 40),
      );
      _seedCluster(
        id: 'c',
        strokeIds: ['c1'],
        bounds: const Rect.fromLTWH(50, 0, 60, 40),
      );

      await executor.executeAll([
        const AlignClustersAction(
          clusterIds: ['a', 'b', 'c'],
          alignment: ClusterAlignment.left,
        ),
      ]);

      // Everyone's left edge is now at x = 0.
      expect(clustersById['a']!.bounds.left, 0);
      expect(clustersById['b']!.bounds.left, 0);
      expect(clustersById['c']!.bounds.left, 0);
    });

    test('ColorCluster recolors every stroke in the cluster', () async {
      _seedCluster(id: 'c1', strokeIds: ['s1', 's2']);

      await executor.executeAll([
        const ColorClusterAction(clusterId: 'c1', color: 'neon_green'),
      ]);

      final layer = lc.activeLayer!;
      for (final sid in ['s1', 's2']) {
        final s = layer.strokes.firstWhere((s) => s.id == sid);
        // neon_green from cluster_action_executor._parseNeonColor.
        expect(s.color, const Color(0xFF69F0AE));
      }
    });

    test('onComplete fires with touched cluster ids', () async {
      _seedCluster(id: 'c1', strokeIds: ['s1']);
      _seedCluster(id: 'c2', strokeIds: ['s2']);

      await executor.executeAll([
        const MoveClusterAction(clusterId: 'c1', dx: 5, dy: 0),
        const ColorClusterAction(clusterId: 'c2', color: 'neon_orange'),
      ]);

      expect(touchedClustersFromCallback, containsAll({'c1', 'c2'}));
    });

    test('UnknownClusterAction is skipped silently', () async {
      final report = await executor.executeAll([
        const UnknownClusterAction(type: 'future_action', rawJson: {}),
      ]);
      expect(report.actionsApplied, 0);
      expect(report.skipped, isEmpty);
    });
  });
}
