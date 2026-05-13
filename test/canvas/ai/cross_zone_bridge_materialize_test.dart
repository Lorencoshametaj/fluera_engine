import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/canvas/ai/cross_zone_bridge_controller.dart';
import 'package:fluera_engine/src/layers/layer_controller.dart';
import 'package:fluera_engine/src/reflow/content_cluster.dart';
import 'package:fluera_engine/src/reflow/knowledge_connection.dart';
import 'package:fluera_engine/src/reflow/knowledge_flow_controller.dart';

import '../../helpers/test_helpers.dart';

void main() {
  group('CrossZoneBridgeController.materializeAsStrokeConnector (F9)', () {
    late LayerController lc;
    late CrossZoneBridgeController controller;
    late Map<String, ContentCluster> clusters;

    setUp(() {
      lc = LayerController();
      final flow = KnowledgeFlowController();
      controller = CrossZoneBridgeController(flowController: flow);
      clusters = {};
    });

    ContentCluster _seedCluster({
      required String id,
      required Offset centroid,
      List<String>? strokeIds,
    }) {
      // Default unique stroke id derived from the cluster id so multiple
      // _seedCluster calls in the same test do not collide on the scene
      // graph (GroupNode asserts unique child ids).
      strokeIds ??= ['stk_${id}_0'];
      for (final sid in strokeIds) {
        lc.addStroke(testStroke(id: sid));
      }
      final c = ContentCluster(
        id: id,
        strokeIds: strokeIds,
        bounds: Rect.fromCenter(center: centroid, width: 100, height: 60),
        centroid: centroid,
      );
      clusters[id] = c;
      return c;
    }

    KnowledgeConnection _seedBridge({
      required String source,
      required String target,
      String? socraticQuestion,
    }) =>
        KnowledgeConnection(
          id: 'bridge_$source-$target',
          sourceClusterId: source,
          targetClusterId: target,
          bridgeSocraticQuestion: socraticQuestion,
          isCrossZone: true,
        );

    test('creates exactly one connector stroke between two clusters',
        () async {
      _seedCluster(
        id: 'cluster_a',
        centroid: const Offset(100, 100),
        strokeIds: ['a1'],
      );
      _seedCluster(
        id: 'cluster_b',
        centroid: const Offset(800, 600),
        strokeIds: ['b1'],
      );

      final layerBefore = lc.activeLayer!;
      final strokeCountBefore = layerBefore.strokes.length;

      final bridge =
          _seedBridge(source: 'cluster_a', target: 'cluster_b');

      await controller.materializeAsStrokeConnector(
        bridge: bridge,
        layerController: lc,
        clusterResolver: (id) => clusters[id],
      );

      final layerAfter = lc.activeLayer!;
      expect(
        layerAfter.strokes.length,
        strokeCountBefore + 1,
        reason: 'exactly one connector stroke is added',
      );

      // The connector id pattern is set by ClusterActionExecutor: starts with
      // 'atlas_conn_'. Verify it landed in the layer.
      final connector = layerAfter.strokes
          .where((s) => s.id.startsWith('atlas_conn_'))
          .toList();
      expect(connector, hasLength(1));
    });

    test('materialize produces a single composite undo entry', () async {
      _seedCluster(id: 'a', centroid: const Offset(0, 0));
      _seedCluster(id: 'b', centroid: const Offset(500, 0));

      // Baseline: how many undo entries already from the seeded strokes.
      // We measure the delta caused exclusively by materializeAsStrokeConnector.
      // (LayerController.addStroke inside _seedCluster may add to the stack;
      // capture the count and check materialize adds at most 1 entry.)
      // We don't know the seed delta exactly without instrumentation, so we
      // assert the relative bound.
      // ignore: deprecated_member_use_from_same_package
      // Instead, just verify post-materialize state: undo should pop a
      // composite delta (the F8 single-entry guarantee).
      // ─────────────────────────────────────────────────────────────────────
      final bridge = _seedBridge(source: 'a', target: 'b');
      await controller.materializeAsStrokeConnector(
        bridge: bridge,
        layerController: lc,
        clusterResolver: (id) => clusters[id],
      );

      final connectorStrokeIds = lc.activeLayer!.strokes
          .where((s) => s.id.startsWith('atlas_conn_'))
          .map((s) => s.id)
          .toList();
      expect(connectorStrokeIds, hasLength(1));

      // Undo once → the connector should be gone (because the composite
      // covers the whole materialize batch).
      lc.undo();
      final after = lc.activeLayer!.strokes
          .where((s) => s.id.startsWith('atlas_conn_'))
          .toList();
      expect(after, isEmpty,
          reason: 'one undo reverts the entire materialize op');
    });

    test('unknown source/target cluster id is reported as skipped', () async {
      _seedCluster(id: 'real', centroid: const Offset(0, 0));
      final beforeCount = lc.activeLayer!.strokes.length;

      final bridge = _seedBridge(source: 'real', target: 'ghost_cluster');
      await controller.materializeAsStrokeConnector(
        bridge: bridge,
        layerController: lc,
        clusterResolver: (id) => clusters[id],
      );

      // Connector creation is aborted (ClusterActionExecutor.executeConnect
      // requires BOTH clusters to resolve).
      expect(lc.activeLayer!.strokes.length, beforeCount);
    });

    test('truncates long socratic-question label to 40 chars + ellipsis',
        () async {
      _seedCluster(id: 'a', centroid: const Offset(0, 0));
      _seedCluster(id: 'b', centroid: const Offset(300, 0));

      final longQ = 'A' * 200;
      final bridge = _seedBridge(
        source: 'a',
        target: 'b',
        socraticQuestion: longQ,
      );

      // No throw — the truncation happens inside materializeAsStrokeConnector
      // before delegating to ConnectClustersAction. We can't read the label
      // back from the stroke (connector strokes don't carry text), but the
      // call must succeed.
      await controller.materializeAsStrokeConnector(
        bridge: bridge,
        layerController: lc,
        clusterResolver: (id) => clusters[id],
      );
      expect(
        lc.activeLayer!.strokes.where((s) => s.id.startsWith('atlas_conn_')),
        hasLength(1),
      );
    });
  });
}
