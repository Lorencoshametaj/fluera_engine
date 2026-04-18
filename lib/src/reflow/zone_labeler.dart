import 'dart:math' as math;
import 'dart:ui';

import '../rendering/optimization/spatial_index.dart';
import 'content_cluster.dart';
import 'text_label_picker.dart';

/// 🗺️ ZONE LABEL — a named macro-region emerging from a group of clusters.
///
/// Rendered by the painter at extreme zoom-out as a large label above the
/// zone's centroid. Represents "le macro-zone con i loro nomi" — the
/// student's self-organized subjects on the mappamondo (§1098, §1981).
class ZoneLabel {
  final String id;
  final String label;
  final Offset centroid;
  final Rect bounds;
  final int clusterCount;

  const ZoneLabel({
    required this.id,
    required this.label,
    required this.centroid,
    required this.bounds,
    required this.clusterCount,
  });

  @override
  String toString() =>
      'ZoneLabel($id: "$label", $clusterCount clusters, $bounds)';
}

/// Result of a [ZoneLabeler.compute] pass.
class ZoneLabelResult {
  final List<ZoneLabel> zones;

  /// Cluster ID → zone ID (only for clusters belonging to a labeled zone).
  final Map<String, String> membership;

  const ZoneLabelResult._({required this.zones, required this.membership});

  static const empty = ZoneLabelResult._(zones: [], membership: {});
}

/// Wrapper so cluster indices can live inside an [RTree<T>].
class _ZoneItem {
  final int index;
  final Rect bounds;
  _ZoneItem(this.index, this.bounds);
}

/// 🗺️ ZONE LABELER — detects macro-regions on the canvas and auto-derives
/// a readable label for each.
///
/// Pedagogical contract (§1981, §1961-1963, §1098): zones are *emergent*
/// from the student's own spatial organization — the labeler never imposes
/// categories. It detects clusters-of-clusters by spatial proximity, then
/// picks a representative word from the student's own handwriting via
/// [TextLabelPicker] (shared with the monument layer for consistency).
///
/// Algorithm:
///   1. Insert every cluster centroid into an R-tree (O(n log n) build).
///   2. For each cluster, range-query the R-tree with a radius of
///      [linkDistance] and Union-Find the hits. This replaces the
///      naive O(n²) pairwise loop of the previous implementation.
///   3. For each meta-cluster with ≥ [minClustersPerZone] members, pick
///      a label via [TextLabelPicker.pickFromMany].
///
/// Complexity: **O(n log n)** average (R-tree assisted). Unchanged API.
class ZoneLabeler {
  /// Distance between centroids below which two clusters are in the same zone.
  static const double defaultLinkDistance = 900.0;

  /// Minimum number of member clusters a zone must have to get a label.
  /// Lone clusters are handled by the MonumentResolver layer, not here.
  static const int minClustersPerZone = 3;

  /// Minimum number of member clusters that must have recognized text for
  /// a zone to emerge. When only one cluster in an area carries text, the
  /// zone label collapses to the same word that the monument already shows
  /// on that cluster — a pedagogically redundant duplication. Requiring
  /// ≥2 text-bearing clusters ensures zone labels name *collective*
  /// organization, not single landmarks.
  static const int minTextBearingClusters = 2;

  /// Max characters in the returned label (long titles are truncated).
  static const int maxLabelChars = 18;

  /// Compute zone labels for [clusters] using their handwriting [clusterTexts].
  ///
  /// [linkDistance] defaults to [defaultLinkDistance]. Increase for sparse
  /// canvases, decrease for dense ones.
  /// [stopwords] is forwarded to [TextLabelPicker]. Override to localize.
  static ZoneLabelResult compute({
    required List<ContentCluster> clusters,
    required Map<String, String> clusterTexts,
    double linkDistance = defaultLinkDistance,
    Set<String> stopwords = TextLabelPicker.defaultStopwords,
  }) {
    if (clusters.length < minClustersPerZone) return ZoneLabelResult.empty;

    // ── Union-Find over cluster indices ──────────────────────────────
    final parent = List<int>.generate(clusters.length, (i) => i);
    int find(int i) {
      var root = i;
      while (parent[root] != root) {
        root = parent[root];
      }
      // Path compression for stable O(α(n)) cost across repeated calls.
      while (parent[i] != root) {
        final next = parent[i];
        parent[i] = root;
        i = next;
      }
      return root;
    }

    void union(int a, int b) {
      final ra = find(a), rb = find(b);
      if (ra != rb) parent[ra] = rb;
    }

    // ── R-tree range queries replace the O(n²) pairwise loop ─────────
    final tree = RTree<_ZoneItem>((item) => item.bounds);
    final items = <_ZoneItem>[];
    for (var i = 0; i < clusters.length; i++) {
      final c = clusters[i].centroid;
      final item = _ZoneItem(
        i,
        // Point bounds (tiny rect around centroid).
        Rect.fromLTWH(c.dx, c.dy, 1, 1),
      );
      items.add(item);
      tree.insert(item);
    }

    final half = linkDistance;
    final linkSq = linkDistance * linkDistance;
    for (final item in items) {
      final c = clusters[item.index].centroid;
      final searchRect = Rect.fromLTRB(
        c.dx - half,
        c.dy - half,
        c.dx + half,
        c.dy + half,
      );
      // The RTree public query takes a viewport rect; margin 0 = no inflate.
      final candidates = tree.queryVisible(searchRect, margin: 0);
      for (final cand in candidates) {
        if (cand.index <= item.index) continue; // dedup symmetric pairs
        final co = clusters[cand.index].centroid;
        final dx = c.dx - co.dx;
        final dy = c.dy - co.dy;
        if (dx * dx + dy * dy <= linkSq) union(item.index, cand.index);
      }
    }

    // ── Group by root ────────────────────────────────────────────────
    final groups = <int, List<int>>{};
    for (var i = 0; i < clusters.length; i++) {
      groups.putIfAbsent(find(i), () => []).add(i);
    }

    final zones = <ZoneLabel>[];
    final membership = <String, String>{};
    groups.forEach((root, indices) {
      if (indices.length < minClustersPerZone) return;

      // Require enough text-bearing clusters so the zone label names
      // *collective* organization rather than duplicating a single
      // monument's label on the one cluster that happens to have OCR'd text.
      final textBearing = indices
          .where((i) => (clusterTexts[clusters[i].id] ?? '').trim().isNotEmpty)
          .length;
      if (textBearing < minTextBearingClusters) return;

      // Bounds + mass-weighted centroid.
      var minX = double.infinity, minY = double.infinity;
      var maxX = -double.infinity, maxY = -double.infinity;
      var sumX = 0.0, sumY = 0.0, sumW = 0.0;
      for (final idx in indices) {
        final c = clusters[idx];
        final b = c.bounds;
        if (b.left < minX) minX = b.left;
        if (b.top < minY) minY = b.top;
        if (b.right > maxX) maxX = b.right;
        if (b.bottom > maxY) maxY = b.bottom;
        final w = math.max(1.0, c.elementCount.toDouble());
        sumX += c.centroid.dx * w;
        sumY += c.centroid.dy * w;
        sumW += w;
      }
      final centroid = sumW > 0
          ? Offset(sumX / sumW, sumY / sumW)
          : Offset((minX + maxX) / 2, (minY + maxY) / 2);

      final label = TextLabelPicker.pickFromMany(
        indices.map((i) => clusterTexts[clusters[i].id] ?? ''),
        maxChars: maxLabelChars,
        stopwords: stopwords,
      );
      if (label.isEmpty) return;

      final zoneId = 'zone_$root';
      zones.add(ZoneLabel(
        id: zoneId,
        label: label,
        centroid: centroid,
        bounds: Rect.fromLTRB(minX, minY, maxX, maxY),
        clusterCount: indices.length,
      ));
      for (final idx in indices) {
        membership[clusters[idx].id] = zoneId;
      }
    });

    return ZoneLabelResult._(zones: zones, membership: membership);
  }
}
