import 'dart:ui';
import 'dart:math' as math;
import './content_cluster.dart';

/// 🌊 REFLOW CONFIG — Tunable parameters for content reflow physics.
///
/// Controls repulsion strength, clearance margins, animation timing,
/// and cluster detection thresholds.
class ReflowConfig {
  /// Whether content reflow is enabled.
  final bool enabled;

  /// Strength of the repulsion force (higher = pushes harder).
  /// Default: 1.2 — balanced between responsiveness and stability.
  final double repulsionStrength;

  /// Minimum clearance margin around moved elements (px).
  /// Creates breathing room so elements don't sit edge-to-edge.
  final double clearanceMargin;

  /// Maximum distance to consider clusters for reflow (px).
  /// Clusters beyond this radius are never affected (performance bound).
  final double maxAffectRadius;

  /// Duration of the settle animation after gesture release.
  final Duration settleDuration;

  /// Maximum iterative passes to resolve secondary collisions.
  final int maxIterations;

  /// Maximum number of affected clusters before skipping reflow.
  /// Performance guardrail to prevent frame drops on dense canvases.
  final int maxAffectedClusters;

  /// Temporal threshold for stroke clustering (ms).
  final int clusterTemporalThresholdMs;

  /// Spatial threshold for stroke clustering (canvas px).
  final double clusterSpatialThreshold;

  /// Whether to attract surrounding content inward when elements are deleted.
  /// Off by default — can be disorienting.
  final bool enableGapAttraction;

  /// Whether reflow affects all layers or only the active layer.
  final bool affectAllLayers;

  const ReflowConfig({
    this.enabled = true,
    this.repulsionStrength = 1.2,
    this.clearanceMargin = 20.0,
    this.maxAffectRadius = 500.0,
    this.settleDuration = const Duration(milliseconds: 300),
    this.maxIterations = 5,
    this.maxAffectedClusters = 50,
    this.clusterTemporalThresholdMs = 1500,
    this.clusterSpatialThreshold = 50.0,
    this.enableGapAttraction = false,
    this.affectAllLayers = false,
  });

  /// Disabled configuration — no reflow at all.
  static const disabled = ReflowConfig(enabled: false);
}

/// 🌊 REFLOW PHYSICS ENGINE — Force-based displacement solver.
///
/// Calculates where surrounding content should move when an element
/// is dragged/inserted/resized (the "disturbance").
///
/// TWO-PHASE DESIGN:
/// - [estimateDisplacements]: O(k) quick pass for ghost previews during drag
/// - [solve]: O(k²) full solve with iterative collision resolution on release
///
/// FORCE MODEL:
/// - Repulsion proportional to overlap area between cluster and disturbance
/// - Direction: away from disturbance centroid
/// - Mass = cluster bounds area (larger clusters resist more)
/// - Damping via iterative convergence (no oscillation)
class ReflowPhysicsEngine {
  final ReflowConfig config;

  const ReflowPhysicsEngine({required this.config});

  /// Phase A: Quick displacement estimate for ghost previews during drag.
  ///
  /// Single pass, no collision resolution. O(k) where k = nearby clusters.
  /// Call this every frame during drag for responsive ghost rendering.
  ///
  /// Returns: Map of cluster ID → estimated displacement offset.
  /// Only affected clusters appear in the result (sparse).
  Map<String, Offset> estimateDisplacements({
    required List<ContentCluster> clusters,
    required Rect disturbance,
    required Set<String> excludeIds,
  }) {
    if (!config.enabled) return {};

    final expanded = disturbance.inflate(config.clearanceMargin);
    final result = <String, Offset>{};

    for (final cluster in clusters) {
      if (excludeIds.contains(cluster.id)) continue;
      if (cluster.isPinned) continue;

      final displacement = _calculateRepulsion(cluster, expanded);
      if (displacement != Offset.zero) {
        result[cluster.id] = displacement;
      }
    }

    return result;
  }

  /// Phase B: Full solve with iterative collision resolution.
  ///
  /// Called once on gesture end. Resolves secondary collisions where
  /// displaced clusters overlap each other.
  ///
  /// Returns: Map of cluster ID → final displacement offset.
  Map<String, Offset> solve({
    required List<ContentCluster> clusters,
    required Rect disturbance,
    required Set<String> excludeIds,
  }) {
    if (!config.enabled) return {};

    final expanded = disturbance.inflate(config.clearanceMargin);
    final displacements = <String, Offset>{};
    final affected = <ContentCluster>[];

    // --- Pass 1: Primary repulsion from disturbance ---
    for (final cluster in clusters) {
      if (excludeIds.contains(cluster.id)) continue;
      if (cluster.isPinned) continue;

      final displacement = _calculateRepulsion(cluster, expanded);
      if (displacement != Offset.zero) {
        displacements[cluster.id] = displacement;
        affected.add(cluster);
      }
    }

    // Performance guardrail
    if (affected.length > config.maxAffectedClusters) {
      return displacements; // Skip iterative resolution
    }

    // --- Pass 2..N: Iterative collision resolution ---
    for (int iter = 0; iter < config.maxIterations; iter++) {
      bool hadCollision = false;

      for (int i = 0; i < affected.length; i++) {
        for (int j = i + 1; j < affected.length; j++) {
          final ci = affected[i];
          final cj = affected[j];

          final boundsI = ci.bounds.shift(displacements[ci.id] ?? Offset.zero);
          final boundsJ = cj.bounds.shift(displacements[cj.id] ?? Offset.zero);

          if (!boundsI.overlaps(boundsJ)) continue;

          // Resolve collision: push the lighter cluster away
          hadCollision = true;
          final overlap = boundsI.intersect(boundsJ);
          final resolution = _resolveCollision(
            boundsI,
            boundsJ,
            overlap,
            ci.mass,
            cj.mass,
          );

          // Apply proportional to inverse mass
          final totalMass = ci.mass + cj.mass;
          final ratioI = cj.mass / totalMass; // Lighter gets pushed more
          final ratioJ = ci.mass / totalMass;

          displacements[ci.id] =
              (displacements[ci.id] ?? Offset.zero) + resolution * -ratioI;
          displacements[cj.id] =
              (displacements[cj.id] ?? Offset.zero) + resolution * ratioJ;
        }
      }

      if (!hadCollision) break; // Converged early
    }

    return displacements;
  }

  /// Apply solved displacements to clusters and return the list of
  /// element IDs that were affected (for undo snapshot).
  ///
  /// This is a convenience method that mutates cluster displacement fields.
  Set<String> applyDisplacements(
    List<ContentCluster> clusters,
    Map<String, Offset> displacements,
  ) {
    final affectedElementIds = <String>{};

    for (final cluster in clusters) {
      final displacement = displacements[cluster.id];
      if (displacement == null || displacement == Offset.zero) continue;

      cluster.displacement = displacement;
      affectedElementIds.addAll(cluster.strokeIds);
      affectedElementIds.addAll(cluster.shapeIds);
      affectedElementIds.addAll(cluster.textIds);
      affectedElementIds.addAll(cluster.imageIds);
    }

    return affectedElementIds;
  }

  // ---------------------------------------------------------------------------
  // Private: Force calculations
  // ---------------------------------------------------------------------------

  /// Calculate repulsion using Minimum Translation Vector (MTV).
  ///
  /// Instead of pushing radially (centroid→centroid), this finds the
  /// shortest axis to separate the cluster from the disturbance:
  /// - If overlap is wider than tall → push vertically (shorter path)
  /// - If overlap is taller than wide → push horizontally (shorter path)
  ///
  /// Also applies a soft "near-field" push for clusters that are close
  /// but not yet overlapping, for smoother anticipatory movement.
  Offset _calculateRepulsion(ContentCluster cluster, Rect disturbance) {
    // Fast reject: too far away
    final distance = _rectDistance(cluster.bounds, disturbance);
    if (distance > config.maxAffectRadius) return Offset.zero;

    // --- Near-field soft push (not overlapping but close) ---
    if (!cluster.bounds.overlaps(disturbance)) {
      // Soft push for clusters within clearanceMargin distance
      if (distance < config.clearanceMargin) {
        final direction = cluster.centroid - disturbance.center;
        if (direction == Offset.zero) return Offset.zero;
        final normalized = _normalize(direction);
        // Gentle push: stronger when closer
        final strength = (config.clearanceMargin - distance) * 0.5;
        return normalized * strength;
      }
      return Offset.zero;
    }

    final overlap = cluster.bounds.intersect(disturbance);
    if (overlap.isEmpty) return Offset.zero;

    // --- MTV: push along the axis of minimum overlap ---
    // Calculate push needed on each axis to fully separate
    final pushLeft = cluster.bounds.right - disturbance.left;
    final pushRight = disturbance.right - cluster.bounds.left;
    final pushUp = cluster.bounds.bottom - disturbance.top;
    final pushDown = disturbance.bottom - cluster.bounds.top;

    // Find the axis with minimum push distance
    double dx = 0, dy = 0;

    final minX = math.min(pushLeft, pushRight);
    final minY = math.min(pushUp, pushDown);

    if (minX < minY) {
      // Push horizontally (shorter path)
      dx =
          pushLeft < pushRight
              ? -(pushLeft + config.clearanceMargin)
              : (pushRight + config.clearanceMargin);
    } else {
      // Push vertically (shorter path)
      dy =
          pushUp < pushDown
              ? -(pushUp + config.clearanceMargin)
              : (pushDown + config.clearanceMargin);
    }

    return Offset(dx, dy);
  }

  /// Resolve collision between two displaced clusters using MTV.
  /// Returns a separation vector pointing from boundsI to boundsJ.
  Offset _resolveCollision(
    Rect boundsI,
    Rect boundsJ,
    Rect overlap,
    double massI,
    double massJ,
  ) {
    // MTV: push along axis of minimum overlap
    final margin = config.clearanceMargin * 0.5;

    if (overlap.width < overlap.height) {
      // Push horizontally
      final sign = boundsJ.center.dx > boundsI.center.dx ? 1.0 : -1.0;
      return Offset(sign * (overlap.width + margin), 0);
    } else {
      // Push vertically
      final sign = boundsJ.center.dy > boundsI.center.dy ? 1.0 : -1.0;
      return Offset(0, sign * (overlap.height + margin));
    }
  }

  /// Normalize an offset to unit length.
  Offset _normalize(Offset offset) {
    final length = offset.distance;
    if (length == 0) return Offset.zero;
    return offset / length;
  }

  /// Minimum distance between two rects (0 if overlapping).
  double _rectDistance(Rect a, Rect b) {
    final dx = _axisGap(a.left, a.right, b.left, b.right);
    final dy = _axisGap(a.top, a.bottom, b.top, b.bottom);

    if (dx <= 0 && dy <= 0) return 0;
    if (dx <= 0) return dy;
    if (dy <= 0) return dx;
    return math.sqrt(dx * dx + dy * dy);
  }

  double _axisGap(double aMin, double aMax, double bMin, double bMax) {
    if (aMax < bMin) return bMin - aMax;
    if (bMax < aMin) return aMin - bMax;
    return -1;
  }
}
