import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart';
import './knowledge_connection.dart';
import './content_cluster.dart';
import './connection_suggestion_engine.dart';
import '../drawing/models/pro_drawing_point.dart';

/// 🧠 KNOWLEDGE FLOW CONTROLLER — Manages the knowledge graph.
///
/// Orchestrates connections between content clusters:
/// - CRUD operations on connections
/// - Bézier path computation for arrows
/// - Magnetic snap detection for connection creation
/// - Particle animation tick
/// - Serialization for canvas save/load
class KnowledgeFlowController {
  /// All connections in the knowledge graph.
  final List<KnowledgeConnection> _connections = [];

  /// Unmodifiable view of connections.
  List<KnowledgeConnection> get connections =>
      List.unmodifiable(_connections);

  /// Version counter — incremented on every mutation.
  /// KnowledgeFlowPainter listens to this for repaint.
  final ValueNotifier<int> version = ValueNotifier(0);

  /// Whether the knowledge flow system is active.
  bool enabled = true;

  // ===========================================================================
  // SUGGESTIONS
  // ===========================================================================

  /// Suggestion engine instance.
  final ConnectionSuggestionEngine _suggestionEngine =
      ConnectionSuggestionEngine();

  /// Current suggestions (recomputed on cluster changes).
  List<SuggestedConnection> _suggestions = [];

  /// Dismissed suggestion pair keys (persisted across recomputations).
  final Set<String> _dismissedPairKeys = {};

  /// Unmodifiable view of active (non-dismissed) suggestions.
  List<SuggestedConnection> get suggestions =>
      _suggestions.where((s) => !s.dismissed).toList();

  /// Recompute suggestions from current clusters and strokes.
  /// [clusterTexts] maps clusterId → recognized handwriting text for semantic signal.
  void recomputeSuggestions({
    required List<ContentCluster> clusters,
    required List<ProStroke> allStrokes,
    Map<String, String>? clusterTexts,
  }) {
    // 🎯 ADAPTIVE: Fewer suggestions when canvas is already busy
    final existingCount = _connections.length;
    final adaptiveMax = existingCount <= 3 ? 3
        : existingCount <= 6 ? 2
        : 1;

    _suggestions = _suggestionEngine.computeSuggestions(
      clusters: clusters,
      allStrokes: allStrokes,
      existingConnections: _connections,
      clusterTexts: clusterTexts,
      maxSuggestions: adaptiveMax,
    );
    // Re-apply dismissals
    for (final s in _suggestions) {
      if (_dismissedPairKeys.contains(s.pairKey)) {
        s.dismissed = true;
      }
    }
    version.value++;
  }

  /// Accept a suggestion — convert it into a real connection.
  /// If the suggestion has shared keywords, auto-populate the connection label.
  KnowledgeConnection? acceptSuggestion(SuggestedConnection suggestion) {
    // Auto-label from shared keywords (e.g., "Newton, physics")
    final autoLabel = suggestion.sharedKeywords.isNotEmpty
        ? suggestion.sharedKeywords.take(3).join(', ')
        : null;

    final conn = addConnection(
      sourceClusterId: suggestion.sourceClusterId,
      targetClusterId: suggestion.targetClusterId,
      label: autoLabel,
    );
    if (conn != null) {
      // 🧠 LEARNING: Reinforce the winning signal
      // Use base reason for learning (strip "Shared: ..." prefix)
      final baseReason = suggestion.reason.startsWith('Shared:')
          ? 'Related content'
          : suggestion.reason;
      _suggestionEngine.reinforceAccept(baseReason);
      // Remove from suggestions
      _suggestions.removeWhere((s) => s.pairKey == suggestion.pairKey);
    }
    return conn;
  }

  /// Dismiss a suggestion — mark it and remember across recomputations.
  void dismissSuggestion(SuggestedConnection suggestion) {
    suggestion.dismissed = true;
    _dismissedPairKeys.add(suggestion.pairKey);
    // 🧠 LEARNING: Penalize the losing signal
    final baseReason = suggestion.reason.startsWith('Shared:')
        ? 'Related content'
        : suggestion.reason;
    _suggestionEngine.reinforceDismiss(baseReason);
    version.value++;
  }

  /// Hit-test suggestion midpoints. Returns the closest suggestion within
  /// [radius] canvas pixels to [canvasPoint], or null.
  SuggestedConnection? hitTestSuggestion(
    Offset canvasPoint,
    List<ContentCluster> clusters, {
    double radius = 25.0,
  }) {
    final activeSuggestions = suggestions;
    if (activeSuggestions.isEmpty) return null;

    final cMap = <String, ContentCluster>{};
    for (final c in clusters) {
      cMap[c.id] = c;
    }

    SuggestedConnection? best;
    double bestDist = radius;

    for (final s in activeSuggestions) {
      final src = cMap[s.sourceClusterId];
      final tgt = cMap[s.targetClusterId];
      if (src == null || tgt == null) continue;

      final midX = (src.centroid.dx + tgt.centroid.dx) / 2;
      final midY = (src.centroid.dy + tgt.centroid.dy) / 2;
      final dx = canvasPoint.dx - midX;
      final dy = canvasPoint.dy - midY;
      final dist = math.sqrt(dx * dx + dy * dy);

      if (dist < bestDist) {
        bestDist = dist;
        best = s;
      }
    }
    return best;
  }

  // ===========================================================================
  // CRUD
  // ===========================================================================

  /// Create a new connection between two clusters.
  ///
  /// Returns the created connection, or null if:
  /// - Source == target (self-loop)
  /// - Connection already exists between these clusters
  KnowledgeConnection? addConnection({
    required String sourceClusterId,
    required String targetClusterId,
    String? label,
    Color? color,
  }) {
    // No self-loops
    if (sourceClusterId == targetClusterId) {
      debugPrint('🔗 [addConnection] BLOCKED: self-loop ($sourceClusterId)');
      return null;
    }

    // No duplicate connections
    final exists = _connections.any(
      (c) =>
          (c.sourceClusterId == sourceClusterId &&
              c.targetClusterId == targetClusterId) ||
          (c.sourceClusterId == targetClusterId &&
              c.targetClusterId == sourceClusterId),
    );
    if (exists) {
      debugPrint('🔗 [addConnection] BLOCKED: duplicate '
          '($sourceClusterId ↔ $targetClusterId)');
      return null;
    }

    final connection = KnowledgeConnection(
      id: _generateId(),
      sourceClusterId: sourceClusterId,
      targetClusterId: targetClusterId,
      label: label,
      color: color ?? KnowledgeConnection.mindMapPalette[
          _connections.length % KnowledgeConnection.mindMapPalette.length],
    );

    _connections.add(connection);
    version.value++;
    return connection;
  }

  /// Soft-delete a connection by ID (starts dissolve animation).
  /// The connection remains in the list with deletedAtMs set.
  /// Actual removal happens via [cleanupDyingConnections] after animation.
  bool removeConnection(String connectionId) {
    final conn = _connections.where((c) => c.id == connectionId).firstOrNull;
    if (conn == null) return false;
    conn.deletedAtMs = DateTime.now().millisecondsSinceEpoch;
    version.value++;
    // Schedule actual cleanup after dissolve animation (500ms)
    Future.delayed(const Duration(milliseconds: 550), () {
      _connections.removeWhere((c) => c.id == connectionId);
      version.value++;
    });
    return true;
  }

  /// Remove all connections involving a cluster (call when cluster is deleted).
  void removeConnectionsForCluster(String clusterId) {
    _connections.removeWhere(
      (c) =>
          c.sourceClusterId == clusterId || c.targetClusterId == clusterId,
    );
    version.value++;
  }

  /// Get all connections involving a specific cluster.
  List<KnowledgeConnection> getConnectionsForCluster(String clusterId) {
    return _connections
        .where(
          (c) =>
              c.sourceClusterId == clusterId ||
              c.targetClusterId == clusterId,
        )
        .toList();
  }

  /// Clear all connections.
  void clear() {
    _connections.clear();
    version.value++;
  }

  /// 🔄 Remap connection cluster IDs after a full cluster rebuild.
  ///
  /// [oldClusters] is the cluster list BEFORE the rebuild.
  /// [freshClusters] is the cluster list AFTER the rebuild.
  ///
  /// Builds an oldId→newId map by matching stroke content overlap,
  /// then recreates connections with corrected IDs.
  void remapClusterIds(
    List<ContentCluster> oldClusters,
    List<ContentCluster> freshClusters,
  ) {
    if (_connections.isEmpty || freshClusters.isEmpty) return;

    // Build: strokeId → new cluster ID
    final strokeToNew = <String, String>{};
    for (final c in freshClusters) {
      for (final sid in c.strokeIds) strokeToNew[sid] = c.id;
      for (final sid in c.shapeIds) strokeToNew[sid] = c.id;
      for (final sid in c.textIds) strokeToNew[sid] = c.id;
      for (final sid in c.imageIds) strokeToNew[sid] = c.id;
    }

    // Build: oldClusterId → newClusterId
    // For each old cluster, find which new cluster contains the most
    // of its strokes — that’s the mapping.
    final oldToNew = <String, String>{};
    for (final old in oldClusters) {
      // Count votes: how many of this old cluster's strokes ended up
      // in each new cluster?
      final votes = <String, int>{};
      for (final sid in old.strokeIds) {
        final newId = strokeToNew[sid];
        if (newId != null) votes[newId] = (votes[newId] ?? 0) + 1;
      }
      for (final sid in old.shapeIds) {
        final newId = strokeToNew[sid];
        if (newId != null) votes[newId] = (votes[newId] ?? 0) + 1;
      }
      for (final sid in old.textIds) {
        final newId = strokeToNew[sid];
        if (newId != null) votes[newId] = (votes[newId] ?? 0) + 1;
      }
      for (final sid in old.imageIds) {
        final newId = strokeToNew[sid];
        if (newId != null) votes[newId] = (votes[newId] ?? 0) + 1;
      }

      if (votes.isNotEmpty) {
        // Pick the new cluster with the most overlapping strokes
        final best = votes.entries.reduce(
          (a, b) => a.value >= b.value ? a : b,
        );
        oldToNew[old.id] = best.key;
      }
    }

    // Also add identity mappings for fresh IDs (no remap needed)
    final freshIds = freshClusters.map((c) => c.id).toSet();
    for (final id in freshIds) {
      oldToNew.putIfAbsent(id, () => id);
    }

    // Rebuild connections with remapped IDs
    final updated = <KnowledgeConnection>[];
    for (final conn in _connections) {
      final newSrc = oldToNew[conn.sourceClusterId];
      final newTgt = oldToNew[conn.targetClusterId];

      // Skip if we can't remap either end
      if (newSrc == null || newTgt == null) continue;
      // Skip self-loops
      if (newSrc == newTgt) continue;

      updated.add(KnowledgeConnection(
        id: conn.id,
        sourceClusterId: newSrc,
        targetClusterId: newTgt,
        label: conn.label,
        color: conn.color,
        curveStrength: conn.curveStrength,
        createdAt: conn.createdAtMs, // 🔧 Preserve original timestamp!
      )..deletedAtMs = conn.deletedAtMs);
    }

    _connections
      ..clear()
      ..addAll(updated);
    version.value++;
  }

  // ===========================================================================
  // Hit Testing (for delete gesture)
  // ===========================================================================

  /// Find the closest connection to a canvas point.
  ///
  /// Samples points along each connection's Bézier curve and returns
  /// the connection whose curve passes closest to [canvasPoint],
  /// within [maxDistance] canvas-space pixels.
  /// Uses 4-way smart anchoring (matches painter).
  KnowledgeConnection? hitTestConnection(
    Offset canvasPoint,
    List<ContentCluster> clusters, {
    double maxDistance = 20.0,
  }) {
    if (_connections.isEmpty) return null;

    // Clamp to prevent absurdly large or tiny hit zones at extreme zoom
    final effectiveMaxDist = maxDistance.clamp(8.0, 40.0);

    final cMap = <String, ContentCluster>{};
    for (final c in clusters) {
      cMap[c.id] = c;
    }

    KnowledgeConnection? closest;
    double closestDist = effectiveMaxDist;

    for (final conn in _connections) {
      if (conn.deletedAtMs > 0) continue;
      final src = cMap[conn.sourceClusterId];
      final tgt = cMap[conn.targetClusterId];
      if (src == null || tgt == null) continue;

      // 4-WAY smart anchor (matches painter)
      final adx = (tgt.centroid.dx - src.centroid.dx).abs();
      final ady = (tgt.centroid.dy - src.centroid.dy).abs();
      final Offset srcPt;
      final Offset tgtPt;
      if (adx > ady * 1.5) {
        if (tgt.centroid.dx > src.centroid.dx) {
          srcPt = Offset(src.bounds.right + 4, src.bounds.center.dy);
          tgtPt = Offset(tgt.bounds.left - 4, tgt.bounds.center.dy);
        } else {
          srcPt = Offset(src.bounds.left - 4, src.bounds.center.dy);
          tgtPt = Offset(tgt.bounds.right + 4, tgt.bounds.center.dy);
        }
      } else {
        if (tgt.centroid.dy < src.centroid.dy) {
          srcPt = Offset(src.bounds.center.dx, src.bounds.top - 4);
          tgtPt = Offset(tgt.bounds.center.dx, tgt.bounds.bottom + 4);
        } else {
          srcPt = Offset(src.bounds.center.dx, src.bounds.bottom + 4);
          tgtPt = Offset(tgt.bounds.center.dx, tgt.bounds.top - 4);
        }
      }
      final cp = getControlPoint(srcPt, tgtPt, conn.curveStrength);

      for (int i = 0; i <= 20; i++) {
        final t = i / 20.0;
        final pt = pointOnQuadBezier(srcPt, cp, tgtPt, t);
        final dist = (pt - canvasPoint).distance;
        if (dist < closestDist) {
          closestDist = dist;
          closest = conn;
        }
      }
    }

    return closest;
  }

  /// Get the midpoint of a connection's curve (for label overlay positioning).
  Offset? getConnectionMidpoint(
    KnowledgeConnection conn,
    List<ContentCluster> clusters,
  ) {
    final cMap = <String, ContentCluster>{};
    for (final c in clusters) cMap[c.id] = c;
    final src = cMap[conn.sourceClusterId];
    final tgt = cMap[conn.targetClusterId];
    if (src == null || tgt == null) return null;

    final adx = (tgt.centroid.dx - src.centroid.dx).abs();
    final ady = (tgt.centroid.dy - src.centroid.dy).abs();
    final Offset srcPt;
    final Offset tgtPt;
    if (adx > ady * 1.5) {
      if (tgt.centroid.dx > src.centroid.dx) {
        srcPt = Offset(src.bounds.right + 4, src.bounds.center.dy);
        tgtPt = Offset(tgt.bounds.left - 4, tgt.bounds.center.dy);
      } else {
        srcPt = Offset(src.bounds.left - 4, src.bounds.center.dy);
        tgtPt = Offset(tgt.bounds.right + 4, tgt.bounds.center.dy);
      }
    } else {
      if (tgt.centroid.dy < src.centroid.dy) {
        srcPt = Offset(src.bounds.center.dx, src.bounds.top - 4);
        tgtPt = Offset(tgt.bounds.center.dx, tgt.bounds.bottom + 4);
      } else {
        srcPt = Offset(src.bounds.center.dx, src.bounds.bottom + 4);
        tgtPt = Offset(tgt.bounds.center.dx, tgt.bounds.top - 4);
      }
    }
    final cp = getControlPoint(srcPt, tgtPt, conn.curveStrength);
    return pointOnQuadBezier(srcPt, cp, tgtPt, 0.5);
  }

  // ===========================================================================
  // Bézier Path Computation
  // ===========================================================================

  /// Compute a cubic Bézier path between two cluster centroids.
  ///
  /// The curve bows perpendicular to the straight line, controlled
  /// by [curveStrength]. This creates elegant, non-overlapping arrows.
  Path computeBezierPath({
    required Offset source,
    required Offset target,
    double curveStrength = 0.3,
  }) {
    final path = Path();
    path.moveTo(source.dx, source.dy);

    final mid = Offset(
      (source.dx + target.dx) / 2,
      (source.dy + target.dy) / 2,
    );

    // Perpendicular offset for the curve
    final dx = target.dx - source.dx;
    final dy = target.dy - source.dy;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length < 1.0) {
      path.lineTo(target.dx, target.dy);
      return path;
    }

    // Perpendicular direction (rotated 90°)
    final perpX = -dy / length;
    final perpY = dx / length;

    // Control point offset
    final offset = length * curveStrength;

    // Single control point for quadratic, or two for cubic
    final cp1 = Offset(
      mid.dx + perpX * offset,
      mid.dy + perpY * offset,
    );

    path.quadraticBezierTo(cp1.dx, cp1.dy, target.dx, target.dy);
    return path;
  }

  /// Compute the arrowhead triangle at the end of a Bézier path.
  ///
  /// Returns a Path for the filled triangle pointing in the
  /// direction of arrival at [target].
  Path computeArrowhead({
    required Offset target,
    required Offset controlPoint,
    double size = 10.0,
  }) {
    // Direction of arrival: from last control point to target
    final dx = target.dx - controlPoint.dx;
    final dy = target.dy - controlPoint.dy;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length < 0.1) return Path();

    final nx = dx / length;
    final ny = dy / length;

    // Perpendicular
    final px = -ny;
    final py = nx;

    // Triangle vertices
    final tip = target;
    final left = Offset(
      tip.dx - nx * size + px * size * 0.4,
      tip.dy - ny * size + py * size * 0.4,
    );
    final right = Offset(
      tip.dx - nx * size - px * size * 0.4,
      tip.dy - ny * size - py * size * 0.4,
    );

    return Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();
  }

  /// Get the control point for a connection between two centroids.
  Offset getControlPoint(Offset source, Offset target, double curveStrength) {
    final mid = Offset(
      (source.dx + target.dx) / 2,
      (source.dy + target.dy) / 2,
    );

    final dx = target.dx - source.dx;
    final dy = target.dy - source.dy;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length < 1.0) return mid;

    final perpX = -dy / length;
    final perpY = dx / length;
    final offset = length * curveStrength;

    return Offset(mid.dx + perpX * offset, mid.dy + perpY * offset);
  }

  /// Get a point along the quadratic Bézier curve at parameter [t] (0–1).
  Offset pointOnQuadBezier(Offset p0, Offset p1, Offset p2, double t) {
    final mt = 1.0 - t;
    return Offset(
      mt * mt * p0.dx + 2 * mt * t * p1.dx + t * t * p2.dx,
      mt * mt * p0.dy + 2 * mt * t * p1.dy + t * t * p2.dy,
    );
  }

  // ===========================================================================
  // Magnetic Snap
  // ===========================================================================

  /// Find the nearest cluster to a canvas point within [maxDistance].
  ///
  /// Used during connection drag to detect snap targets.
  /// Returns null if no cluster is close enough.
  ContentCluster? findNearestCluster(
    Offset canvasPoint,
    List<ContentCluster> clusters, {
    double maxDistance = 60.0,
    String? excludeClusterId,
  }) {
    ContentCluster? nearest;
    double nearestDist = maxDistance;

    for (final cluster in clusters) {
      if (cluster.id == excludeClusterId) continue;
      if (cluster.elementCount < 1) continue;

      // Use bounds-based distance: 0 if inside bounds, nearest-edge distance otherwise
      final inflated = cluster.bounds.inflate(10.0); // Small padding for easier tapping
      double dist;
      if (inflated.contains(canvasPoint)) {
        dist = 0.0; // Inside bounds = perfect hit
      } else {
        // Distance to nearest edge of bounds
        final dx = (canvasPoint.dx - canvasPoint.dx.clamp(inflated.left, inflated.right)).abs();
        final dy = (canvasPoint.dy - canvasPoint.dy.clamp(inflated.top, inflated.bottom)).abs();
        dist = math.sqrt(dx * dx + dy * dy);
      }
      if (dist < nearestDist) {
        nearestDist = dist;
        nearest = cluster;
      }
    }

    return nearest;
  }

  // ===========================================================================
  // Particle Animation
  // ===========================================================================

  /// Advance all particle animations by [dt] seconds.
  ///
  /// Call this from a Ticker callback (~60/120fps).
  /// Optionally pass [clusters] to lazily compute pathLength for speed-proportional particles.
  void tickParticles(double dt, [List<ContentCluster>? clusters]) {
    for (final connection in _connections) {
      // Lazy path length computation: only compute once per connection
      if (clusters != null && connection.pathLength == 500.0) {
        final src = clusters.where((c) => c.id == connection.sourceClusterId).firstOrNull;
        final tgt = clusters.where((c) => c.id == connection.targetClusterId).firstOrNull;
        if (src != null && tgt != null) {
          final dx = tgt.centroid.dx - src.centroid.dx;
          final dy = tgt.centroid.dy - src.centroid.dy;
          connection.pathLength = math.sqrt(dx * dx + dy * dy);
        }
      }
      connection.advanceParticles(dt);
    }
  }

  // ===========================================================================
  // Serialization
  // ===========================================================================

  Map<String, dynamic> toJson() => {
    'connections': _connections.map((c) => c.toJson()).toList(),
  };

  void loadFromJson(Map<String, dynamic> json) {
    _connections.clear();
    final list = json['connections'] as List<dynamic>? ?? [];
    for (final item in list) {
      _connections.add(
        KnowledgeConnection.fromJson(item as Map<String, dynamic>),
      );
    }
    version.value++;
  }

  // ===========================================================================
  // Utilities
  // ===========================================================================

  static String _generateId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final rand = math.Random().nextInt(0xFFFF);
    return 'kc_${now.toRadixString(36)}_${rand.toRadixString(36)}';
  }

  void dispose() {
    version.dispose();
  }
}
