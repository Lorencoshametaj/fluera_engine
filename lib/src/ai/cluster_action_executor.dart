import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart' show debugPrint;

import '../drawing/models/pro_drawing_point.dart';
import '../layers/layer_controller.dart';
import '../reflow/content_cluster.dart';
import 'cluster_action.dart';

/// Result of executing a batch of [ClusterAction]s.
///
/// [touchedClusterIds] lets the caller refresh dependent indexes
/// (e.g. `ClusterConceptIndex`) for the clusters that actually moved.
/// [skipped] lists ids that were referenced by the AI but not resolved —
/// useful for telemetry and the explanation text shown to the user.
class ClusterExecutionReport {
  final Set<String> touchedClusterIds;
  final List<String> skipped;
  final int actionsApplied;

  const ClusterExecutionReport({
    required this.touchedClusterIds,
    required this.skipped,
    required this.actionsApplied,
  });
}

/// Executes [ClusterAction]s by expanding each cluster into its constituent
/// strokes and applying the requested transform via [LayerController].
///
/// This is the cluster-level counterpart of `AtlasActionExecutor`. The two
/// dispatchers coexist (decision 2026-05-12): node-level for explicit
/// per-node operations on discrete content (Text / LaTeX / Image / PDF /
/// handwriting conversion), cluster-level for semantic operations on
/// groups of strokes that the student perceives as a single concept.
///
/// Pricing note: every cluster action is wrapped in
/// `LayerController.runAsBatch` by the dispatcher, so the executor itself
/// does NOT begin its own batch — it must be called from inside one.
class ClusterActionExecutor {
  /// Resolves a cluster id to the current [ContentCluster] in cache.
  /// Returns null if the id is stale (cluster split / merged / removed
  /// since the AI saw the canvas snapshot).
  final ContentCluster? Function(String clusterId) clusterResolver;

  /// Layer controller used to mutate strokes (remove + re-add the modified
  /// copy). Calls are tracked by the delta system and aggregated by the
  /// active composite batch.
  final LayerController layerController;

  /// Called once after all actions complete with the list of touched
  /// cluster ids — typically wired to invalidate the
  /// `ClusterConceptIndex` entries (their `strokeChecksum` may have
  /// changed) and bump the scene-graph version.
  final void Function(Set<String> touchedClusterIds)? onComplete;

  const ClusterActionExecutor({
    required this.clusterResolver,
    required this.layerController,
    this.onComplete,
  });

  /// Apply every action in order and return a report.
  ///
  /// Unknown cluster ids and [UnknownClusterAction] entries are skipped
  /// (logged + counted). Other failures bubble up so the surrounding
  /// `runAsBatch` rolls back the partial state.
  Future<ClusterExecutionReport> executeAll(
    List<ClusterAction> actions,
  ) async {
    final touched = <String>{};
    final skipped = <String>[];
    var applied = 0;

    for (final action in actions) {
      switch (action) {
        case MoveClusterAction():
          if (await _executeMove(action, touched, skipped)) applied++;

        case AlignClustersAction():
          if (await _executeAlign(action, touched, skipped)) applied++;

        case DistributeClustersAction():
          if (await _executeDistribute(action, touched, skipped)) applied++;

        case ColorClusterAction():
          if (await _executeColor(action, touched, skipped)) applied++;

        case ConnectClustersAction():
          if (await _executeConnect(action, touched, skipped)) applied++;

        case UnknownClusterAction():
          debugPrint(
              '⚠️ ClusterActionExecutor: unknown action "${action.type}" — skipped.');
      }
    }

    if (touched.isNotEmpty) onComplete?.call(touched);
    return ClusterExecutionReport(
      touchedClusterIds: touched,
      skipped: skipped,
      actionsApplied: applied,
    );
  }

  // ─── MoveCluster ────────────────────────────────────────────────────────

  Future<bool> _executeMove(
    MoveClusterAction a,
    Set<String> touched,
    List<String> skipped,
  ) async {
    final cluster = clusterResolver(a.clusterId);
    if (cluster == null) {
      skipped.add(a.clusterId);
      return false;
    }
    if (cluster.isPinned) {
      debugPrint('⚠️ MoveCluster ${a.clusterId} skipped (pinned).');
      return false;
    }

    _translateStrokes(cluster.strokeIds, a.dx, a.dy);
    // Keep the in-memory cluster geometry consistent so subsequent actions
    // in the same batch can rely on it.
    cluster.bounds = cluster.bounds.shift(Offset(a.dx, a.dy));
    cluster.centroid = cluster.centroid + Offset(a.dx, a.dy);
    touched.add(a.clusterId);
    return true;
  }

  // ─── AlignClusters ──────────────────────────────────────────────────────

  Future<bool> _executeAlign(
    AlignClustersAction a,
    Set<String> touched,
    List<String> skipped,
  ) async {
    final clusters = _resolveAll(a.clusterIds, skipped);
    if (clusters.length < 2) return false;

    // Anchor = extremum chosen by alignment direction.
    final anchor = switch (a.alignment) {
      ClusterAlignment.left =>
          clusters.map((c) => c.bounds.left).reduce(math.min),
      ClusterAlignment.right =>
          clusters.map((c) => c.bounds.right).reduce(math.max),
      ClusterAlignment.top =>
          clusters.map((c) => c.bounds.top).reduce(math.min),
      ClusterAlignment.bottom =>
          clusters.map((c) => c.bounds.bottom).reduce(math.max),
      ClusterAlignment.centerH => _meanCenterX(clusters),
      ClusterAlignment.centerV => _meanCenterY(clusters),
    };

    for (final c in clusters) {
      if (c.isPinned) continue;
      final delta = switch (a.alignment) {
        ClusterAlignment.left => Offset(anchor - c.bounds.left, 0),
        ClusterAlignment.right => Offset(anchor - c.bounds.right, 0),
        ClusterAlignment.top => Offset(0, anchor - c.bounds.top),
        ClusterAlignment.bottom => Offset(0, anchor - c.bounds.bottom),
        ClusterAlignment.centerH => Offset(anchor - c.bounds.center.dx, 0),
        ClusterAlignment.centerV => Offset(0, anchor - c.bounds.center.dy),
      };
      if (delta.distanceSquared < 0.25) continue; // already aligned
      _translateStrokes(c.strokeIds, delta.dx, delta.dy);
      c.bounds = c.bounds.shift(delta);
      c.centroid = c.centroid + delta;
      touched.add(c.id);
    }
    return true;
  }

  // ─── DistributeClusters ─────────────────────────────────────────────────

  Future<bool> _executeDistribute(
    DistributeClustersAction a,
    Set<String> touched,
    List<String> skipped,
  ) async {
    final clusters = _resolveAll(a.clusterIds, skipped);
    if (clusters.length < 3) return false; // need ≥3 to distribute interior

    // Sort along the chosen axis using cluster centroid.
    clusters.sort((x, y) => switch (a.axis) {
          ClusterAxis.horizontal =>
              x.centroid.dx.compareTo(y.centroid.dx),
          ClusterAxis.vertical =>
              x.centroid.dy.compareTo(y.centroid.dy),
        });

    final first = clusters.first;
    final last = clusters.last;
    final spacing = switch (a.axis) {
      ClusterAxis.horizontal =>
          (last.centroid.dx - first.centroid.dx) / (clusters.length - 1),
      ClusterAxis.vertical =>
          (last.centroid.dy - first.centroid.dy) / (clusters.length - 1),
    };

    for (var i = 1; i < clusters.length - 1; i++) {
      final c = clusters[i];
      if (c.isPinned) continue;
      final target = switch (a.axis) {
        ClusterAxis.horizontal => first.centroid.dx + spacing * i,
        ClusterAxis.vertical => first.centroid.dy + spacing * i,
      };
      final delta = switch (a.axis) {
        ClusterAxis.horizontal => Offset(target - c.centroid.dx, 0),
        ClusterAxis.vertical => Offset(0, target - c.centroid.dy),
      };
      if (delta.distanceSquared < 0.25) continue;
      _translateStrokes(c.strokeIds, delta.dx, delta.dy);
      c.bounds = c.bounds.shift(delta);
      c.centroid = c.centroid + delta;
      touched.add(c.id);
    }
    return true;
  }

  // ─── ColorCluster ───────────────────────────────────────────────────────

  Future<bool> _executeColor(
    ColorClusterAction a,
    Set<String> touched,
    List<String> skipped,
  ) async {
    final cluster = clusterResolver(a.clusterId);
    if (cluster == null) {
      skipped.add(a.clusterId);
      return false;
    }
    final color = _parseNeonColor(a.color);

    for (final strokeId in cluster.strokeIds) {
      final stroke = _findStroke(strokeId);
      if (stroke == null) continue;
      final recolored = stroke.copyWith(color: color);
      layerController.removeStroke(strokeId);
      layerController.addStroke(recolored);
    }
    touched.add(a.clusterId);
    return true;
  }

  // ─── ConnectClusters ────────────────────────────────────────────────────

  Future<bool> _executeConnect(
    ConnectClustersAction a,
    Set<String> touched,
    List<String> skipped,
  ) async {
    final from = clusterResolver(a.fromId);
    final to = clusterResolver(a.toId);
    if (from == null) skipped.add(a.fromId);
    if (to == null) skipped.add(a.toId);
    if (from == null || to == null) return false;

    final connector = _buildConnectorStroke(
      from.centroid,
      to.centroid,
      label: a.label,
    );
    layerController.addStroke(connector);
    touched
      ..add(from.id)
      ..add(to.id);
    return true;
  }

  // ─── Helpers ────────────────────────────────────────────────────────────

  /// Translate every stroke in [strokeIds] by ([dx], [dy]) by remove+add.
  ///
  /// We mutate the stroke's POINTS rather than the scene-graph transform
  /// so the delta tracker captures the change (the transform-only path
  /// `StrokeNode.translate` bypasses [CanvasDelta] and would not survive
  /// a save/load cycle nor sync via CRDT).
  void _translateStrokes(List<String> strokeIds, double dx, double dy) {
    if (dx == 0 && dy == 0) return;
    final offset = Offset(dx, dy);
    for (final id in strokeIds) {
      final stroke = _findStroke(id);
      if (stroke == null) continue;
      final shiftedPoints = stroke.points
          .map((p) => p.copyWith(position: p.position + offset))
          .toList();
      final shifted = stroke.copyWith(points: shiftedPoints);
      layerController.removeStroke(id);
      layerController.addStroke(shifted);
    }
  }

  /// Find a [ProStroke] by id across every layer (active first).
  ProStroke? _findStroke(String strokeId) {
    for (final layer in layerController.layers) {
      for (final s in layer.strokes) {
        if (s.id == strokeId) return s;
      }
    }
    return null;
  }

  /// Resolve a list of cluster ids, accumulating any misses in [skipped].
  List<ContentCluster> _resolveAll(
    List<String> ids,
    List<String> skipped,
  ) {
    final out = <ContentCluster>[];
    for (final id in ids) {
      final c = clusterResolver(id);
      if (c == null) {
        skipped.add(id);
      } else {
        out.add(c);
      }
    }
    return out;
  }

  double _meanCenterX(List<ContentCluster> cs) =>
      cs.map((c) => c.bounds.center.dx).reduce((a, b) => a + b) / cs.length;

  double _meanCenterY(List<ContentCluster> cs) =>
      cs.map((c) => c.bounds.center.dy).reduce((a, b) => a + b) / cs.length;

  /// Resolve the AI-supplied color name to a [Color].
  /// Accepts the four neon presets used by the node-level Atlas as well
  /// as `#RRGGBB` literals so the prompt can stay flexible.
  static Color _parseNeonColor(String raw) {
    switch (raw.toLowerCase().trim()) {
      case 'neon_cyan':
        return const Color(0xFF00E5FF);
      case 'neon_green':
        return const Color(0xFF69F0AE);
      case 'neon_orange':
        return const Color(0xFFFFAB40);
      case 'neon_purple':
        return const Color(0xFFCE93D8);
    }
    if (raw.startsWith('#') && raw.length == 7) {
      final hex = int.tryParse(raw.substring(1), radix: 16);
      if (hex != null) return Color(0xFF000000 | hex);
    }
    return const Color(0xFF00E5FF); // safe fallback
  }

  /// Build a simple straight-line connector stroke between two centroids.
  /// Visually it's a thin cyan line; persistence/CRDT-friendly because it
  /// is a real [ProStroke] in the active layer (not a phantom overlay).
  static ProStroke _buildConnectorStroke(
    Offset from,
    Offset to, {
    String? label,
  }) {
    final id = 'atlas_conn_${DateTime.now().microsecondsSinceEpoch}';
    final now = DateTime.now();
    return ProStroke(
      id: id,
      points: [
        ProDrawingPoint(
          position: from,
          pressure: 1.0,
          timestamp: now.millisecondsSinceEpoch,
        ),
        ProDrawingPoint(
          position: to,
          pressure: 1.0,
          timestamp: now.millisecondsSinceEpoch,
        ),
      ],
      color: const Color(0xCC00E5FF),
      baseWidth: 2.0,
      penType: ProPenType.ballpoint,
      createdAt: now,
    );
  }
}
