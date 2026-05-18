// Tests for SemanticMorphController.computeSuperNodes adaptive merge radius
// (FX3, 2026-05-17). Verifies that:
//   - Few sparse clusters spread across a wide area do NOT collapse into a
//     single super-node (regression observed on device 17/05 when the
//     radius was a fixed 400 px).
//   - Many tightly-packed clusters produce a granular super-node set
//     instead of one giant blob.

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/canvas/ai/srs_stage_indicator.dart';
import 'package:fluera_engine/src/reflow/content_cluster.dart';
import 'package:fluera_engine/src/reflow/semantic_morph_controller.dart';

ContentCluster _mk(String id, Offset centroid) => ContentCluster(
      id: id,
      strokeIds: const ['s1'],
      bounds: Rect.fromCenter(center: centroid, width: 80, height: 40),
      centroid: centroid,
    );

void main() {
  group('SemanticMorphController.computeSuperNodes (FX3 adaptive radius)', () {
    test(
        'sparse cluster set (5 widely spread) does NOT collapse into a single '
        'super-node — regression guard for the device test of 17/05', () {
      // ≤3 clusters now hit the sparse-fallback (radius=800). With 5
      // clusters spread across ~6000 px the density-driven radius lands
      // near 6000/sqrt(5)*0.7 ≈ 1900 → clamped to 800, but spacing is
      // still ~2000 px so most pairs stay above the threshold.
      final controller = SemanticMorphController();
      final clusters = <ContentCluster>[
        _mk('A', const Offset(0, 0)),
        _mk('B', const Offset(3000, 0)),
        _mk('C', const Offset(6000, 0)),
        _mk('D', const Offset(0, 3000)),
        _mk('E', const Offset(6000, 3000)),
      ];
      controller.computeSuperNodes(clusters);
      // Pre-FX3 this would have produced 1 super-node (all merged at
      // radius=400 — actually no, but the regression saw the opposite
      // edge: tiny canvases would over-merge). The contract we care
      // about is: spatially distant clusters do NOT all merge.
      expect(controller.superNodes.length, greaterThanOrEqualTo(3),
          reason:
              '5 sparse clusters across 6000 px should yield at least 3 super-nodes; '
              'got ${controller.superNodes.length}. Likely cause: merge radius '
              'collapsed unrelated clusters into one blob (regression of FX3).');
    });

    test(
        'dense cluster set (49 clusters on a 7×7 grid, 100 px spacing) produces '
        'a granular super-node set rather than 1 monolithic blob', () {
      final controller = SemanticMorphController();
      final clusters = <ContentCluster>[];
      // 7×7 grid, 100 px spacing → area ≈ 600×600 → density ≈
      // sqrt(360_000 / 49) ≈ 86 → clamped up to _minMergeRadius=250.
      // At 250 px radius, neighbours up to 2 cells away merge.
      for (var y = 0; y < 7; y++) {
        for (var x = 0; x < 7; x++) {
          clusters
              .add(_mk('g$y-$x', Offset(x * 100.0, y * 100.0)));
        }
      }
      controller.computeSuperNodes(clusters);
      // Sanity: we must have AT LEAST 1 super-node, and we must NOT
      // exceed the cluster count.
      expect(controller.superNodes, isNotEmpty);
      expect(controller.superNodes.length, lessThanOrEqualTo(clusters.length));
      // The piano contract: ≤20 super-nodes on dense canvases (so they
      // stay readable). With this grid spacing + adaptive radius the
      // 49 clusters should collapse into well under 20 super-nodes.
      expect(controller.superNodes.length, lessThanOrEqualTo(20),
          reason:
              'dense 7×7 grid should produce ≤20 super-nodes; got '
              '${controller.superNodes.length}. Likely cause: radius dropped '
              'below the min clamp and granularity exploded.');
    });

    test(
        '≤3 clusters always merge into a single super-node (sparse fallback '
        'uses _sparseFallbackRadius = 800)', () {
      final controller = SemanticMorphController();
      final clusters = <ContentCluster>[
        _mk('A', const Offset(0, 0)),
        _mk('B', const Offset(500, 0)),
        _mk('C', const Offset(1000, 0)),
      ];
      controller.computeSuperNodes(clusters);
      expect(controller.superNodes.length, 1,
          reason:
              '3 clusters within 1000 px should merge under the 800 px sparse '
              'fallback radius.');
    });

    test(
        'meta tier stays empty when the super-node count is below '
        'kMetaTierMinSuperNodes (sparse canvas)', () {
      final controller = SemanticMorphController();
      // 5 widely-spread clusters → ~5 super-nodes (well below the
      // meta threshold of 12) → meta tier must stay empty so we don't
      // collapse a sparse canvas into too few visual anchors.
      final clusters = <ContentCluster>[
        _mk('A', const Offset(0, 0)),
        _mk('B', const Offset(3000, 0)),
        _mk('C', const Offset(6000, 0)),
        _mk('D', const Offset(0, 3000)),
        _mk('E', const Offset(6000, 3000)),
      ];
      controller.computeSuperNodes(clusters);
      expect(controller.superNodes.length, lessThan(
          SemanticMorphController.kMetaTierMinSuperNodes));
      expect(controller.metaSuperNodes, isEmpty,
          reason: 'meta tier should not activate when super-node count is '
              'below kMetaTierMinSuperNodes — collapsing few super-nodes loses '
              'information without solving any density problem.');
      // effectiveSuperNodes must fall back to plain superNodes.
      expect(
        identical(
          controller.effectiveSuperNodes(0.10),
          controller.superNodes,
        ),
        isTrue,
        reason: 'effectiveSuperNodes must return the plain superNodes '
            'reference (not a copy) when meta tier is inactive.',
      );
    });

    test(
        'meta tier activates and collapses many super-nodes into fewer '
        '"continents" on a dense canvas', () {
      final controller = SemanticMorphController();
      // 200 clusters laid out so each cluster sits in its own
      // super-node (~no merge at the cluster tier) → super-node count
      // explodes past the meta threshold. Use a sparse grid with
      // 1000 px spacing so the adaptive cluster radius (clamped to
      // 800) doesn't merge them prematurely.
      final clusters = <ContentCluster>[];
      const cols = 20;
      const spacing = 1000.0;
      for (var i = 0; i < 200; i++) {
        final x = (i % cols) * spacing;
        final y = (i ~/ cols) * spacing;
        clusters.add(_mk('c$i', Offset(x, y)));
      }
      controller.computeSuperNodes(clusters);
      expect(controller.superNodes.length, greaterThanOrEqualTo(
          SemanticMorphController.kMetaTierMinSuperNodes),
          reason: 'sanity: super-node count must clear the threshold so we '
              'can exercise the meta tier.');
      expect(controller.metaSuperNodes, isNotEmpty,
          reason: 'meta tier must compute when super-node count clears the '
              'threshold.');
      expect(controller.metaSuperNodes.length,
          lessThan(controller.superNodes.length),
          reason: 'continents must be strictly fewer than super-nodes — '
              'otherwise the meta layer is not aggregating anything.');
      // The continents should be a reasonably small handful, not
      // virtually equal to the super-node count.
      expect(controller.metaSuperNodes.length, lessThanOrEqualTo(40),
          reason: '200 clusters on a 20-col grid should collapse to ≤40 '
              'continents at the meta tier; got '
              '${controller.metaSuperNodes.length}.');
    });

    test(
        'effectiveSuperNodes respects kMetaTierActivationScale: meta visible '
        'only when canvasScale ≤ 0.13', () {
      final controller = SemanticMorphController();
      // Build a dense scenario so meta tier is populated.
      final clusters = <ContentCluster>[];
      for (var i = 0; i < 200; i++) {
        clusters.add(_mk('c$i', Offset((i % 20) * 1000.0, (i ~/ 20) * 1000.0)));
      }
      controller.computeSuperNodes(clusters);
      expect(controller.metaSuperNodes, isNotEmpty);

      // Above activation scale → plain super-nodes.
      expect(
        identical(
          controller.effectiveSuperNodes(0.20),
          controller.superNodes,
        ),
        isTrue,
        reason: 'above kMetaTierActivationScale (0.13) effectiveSuperNodes '
            'must return the original super-node list (no collapse yet).',
      );
      // Just above the threshold → still plain.
      expect(
        identical(
          controller.effectiveSuperNodes(
            SemanticMorphController.kMetaTierActivationScale + 0.001,
          ),
          controller.superNodes,
        ),
        isTrue,
      );
      // At/below the threshold → meta tier kicks in.
      expect(
        identical(
          controller.effectiveSuperNodes(
            SemanticMorphController.kMetaTierActivationScale,
          ),
          controller.metaSuperNodes,
        ),
        isTrue,
      );
      expect(
        identical(
          controller.effectiveSuperNodes(0.10),
          controller.metaSuperNodes,
        ),
        isTrue,
      );
    });

    test(
        'meta-super-node memberClusterIds is the UNION of all member-super-'
        'nodes` cluster ids (no loss)', () {
      final controller = SemanticMorphController();
      final clusters = <ContentCluster>[];
      for (var i = 0; i < 200; i++) {
        clusters.add(_mk('c$i', Offset((i % 20) * 1000.0, (i ~/ 20) * 1000.0)));
      }
      controller.computeSuperNodes(clusters);

      // Every cluster id must appear in exactly one meta-super-node.
      final allMetaMembers = controller.metaSuperNodes
          .expand((m) => m.memberClusterIds)
          .toSet();
      final allClusterIds = clusters.map((c) => c.id).toSet();
      expect(allMetaMembers, equals(allClusterIds),
          reason: 'no cluster id may be lost or duplicated across the meta '
              'tier — the continent set must partition the cluster space.');
      // memberCount on a meta-super-node must equal the sum of member
      // super-node memberCounts (which equals the number of clusters
      // in that continent).
      for (final meta in controller.metaSuperNodes) {
        expect(meta.memberCount, meta.memberClusterIds.length,
            reason: 'meta-super-node memberCount must equal the number of '
                'underlying clusters.');
        expect(meta.id, startsWith('meta_'),
            reason: 'meta-super-node ids must be namespaced with the meta_ '
                'prefix so theme/colour caches keyed on super-node id never '
                'collide between tiers.');
      }
    });

    test(
        'cache hash includes the adaptive radius, so a centroid shift that '
        'changes density invalidates the super-node cache', () {
      final controller = SemanticMorphController();
      // 2D distribution with non-zero y span — so the bbox area is
      // non-degenerate and the adaptive radius actually responds to
      // density changes (the y=0 edge case falls back to the constant
      // sparse-fallback radius and would mask the cache test).
      final base = <ContentCluster>[
        _mk('A', const Offset(0, 0)),
        _mk('B', const Offset(200, 100)),
        _mk('C', const Offset(400, 50)),
        _mk('D', const Offset(600, 150)),
        _mk('E', const Offset(800, 80)),
        _mk('F', const Offset(1000, 120)),
      ];
      controller.computeSuperNodes(base);
      final firstCount = controller.superNodes.length;

      // Move F very far — same ids, very different density → different
      // adaptive radius → different hash → cache must rebuild.
      final moved = List<ContentCluster>.from(base);
      moved[5] = _mk('F', const Offset(50000, 30000));
      controller.computeSuperNodes(moved);

      final containsLonelyF = controller.superNodes
          .any((sn) => sn.memberClusterIds.length == 1 && sn.memberClusterIds.first == 'F');
      expect(containsLonelyF, isTrue,
          reason: 'after moving F to (50000, 30000) the cache should rebuild '
              'with the new adaptive radius and F should be its own super-node. '
              'Cluster count before: $firstCount, after: '
              '${controller.superNodes.length}.');
    });
  });

  group('SemanticMorphController.memberToMetaSuperNodeIndex (Bundle A)', () {
    test(
        'is populated only when meta tier is active; empty otherwise', () {
      final controller = SemanticMorphController();
      // Sparse → no meta tier
      final sparse = <ContentCluster>[
        _mk('A', const Offset(0, 0)),
        _mk('B', const Offset(3000, 0)),
        _mk('C', const Offset(6000, 0)),
        _mk('D', const Offset(0, 3000)),
        _mk('E', const Offset(6000, 3000)),
      ];
      controller.computeSuperNodes(sparse);
      expect(controller.metaSuperNodes, isEmpty);
      expect(controller.memberToMetaSuperNodeIndex, isEmpty,
          reason: 'meta tier inactive ⇒ map must stay empty so the painter '
              'never indexes into a missing list.');
    });

    test(
        'partitions every cluster id into the meta tier exactly once', () {
      final controller = SemanticMorphController();
      final clusters = <ContentCluster>[];
      for (var i = 0; i < 200; i++) {
        clusters.add(_mk('c$i', Offset((i % 20) * 1000.0, (i ~/ 20) * 1000.0)));
      }
      controller.computeSuperNodes(clusters);
      expect(controller.metaSuperNodes, isNotEmpty);

      // Every cluster appears exactly once in the map and its mapped
      // index resolves to a valid meta-super-node containing that id.
      for (final c in clusters) {
        final idx = controller.memberToMetaSuperNodeIndex[c.id];
        expect(idx, isNotNull,
            reason: 'cluster ${c.id} missing from memberToMetaSuperNodeIndex');
        expect(idx, inInclusiveRange(0, controller.metaSuperNodes.length - 1));
        final meta = controller.metaSuperNodes[idx!];
        expect(meta.memberClusterIds, contains(c.id),
            reason: 'cluster ${c.id} mapped to meta index $idx but that '
                'meta-super-node does not list ${c.id} as a member.');
      }
      // No spurious keys.
      expect(controller.memberToMetaSuperNodeIndex.length, clusters.length);
    });
  });

  group('SrsStage worst-of contract (Bundle B)', () {
    test(
        'lower SrsStage.index encodes "worse" memory state, so worst-of is '
        'the minimum index — invariant relied on by both '
        '_fsrsClusterStageList (host) and _paintGodView (painter).', () {
      // The contract: fragile=0 is the worst, integrated=last is the best.
      expect(SrsStage.fragile.index, lessThan(SrsStage.growing.index));
      expect(SrsStage.growing.index, lessThan(SrsStage.solid.index));
      expect(SrsStage.solid.index, lessThan(SrsStage.mastered.index));
      expect(SrsStage.mastered.index, lessThan(SrsStage.integrated.index));
    });

    test(
        'worst-of helper for super-nodes: among [solid, fragile, mastered] '
        'must return fragile; null members are skipped; all-null returns null',
        () {
      SrsStage? worstOf(Iterable<SrsStage?> stages) {
        SrsStage? worst;
        for (final s in stages) {
          if (s == null) continue;
          if (worst == null || s.index < worst.index) worst = s;
        }
        return worst;
      }

      expect(
        worstOf([SrsStage.solid, SrsStage.fragile, SrsStage.mastered]),
        SrsStage.fragile,
      );
      expect(
        worstOf([SrsStage.mastered, null, SrsStage.growing]),
        SrsStage.growing,
      );
      expect(worstOf([null, null]), isNull);
      expect(worstOf(const []), isNull);
    });
  });
}
