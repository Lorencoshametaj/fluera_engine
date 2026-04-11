// ============================================================================
// ✨ INTERLEAVING PATH — "Sentiero Luminoso" for SRS review (P6-15, P8-10)
//
// Specifica: P6-15, P8-10, P10-24, A13-T06
//
// The interleaving path is a visual guide that connects review nodes in
// an interleaved order (mixing sub-topics) rather than sequential.
//
// Visual properties (A13-T06):
//   - Golden dotted line connecting nodes
//   - Trail animation: head advances at ~1px/s, trail fades in 3s
//   - Dismissable by student gesture (swipe or tap path)
//
// Pedagogical principle: Interleaving Effect (§10)
//   Mixing topics during review produces better long-term retention
//   than blocked practice. The path SHOWS this to the student visually.
//
// ARCHITECTURE:
//   Pure model + controller — no Canvas/paint() code.
//   The rendering layer reads the path data and draws it.
//   Zero allocations in hot path (pre-computed path points).
// ============================================================================

import 'dart:ui';

import 'package:flutter/foundation.dart';

/// ✨ A single node in the interleaving path.
class PathNode {
  /// Cluster ID.
  final String clusterId;

  /// Canvas-space position (centroid of the cluster).
  final Offset position;

  /// Topic/sub-topic label for interleaving verification.
  final String? topic;

  const PathNode({
    required this.clusterId,
    required this.position,
    this.topic,
  });
}

/// ✨ State of the interleaving path visualization.
enum InterleavingPathState {
  /// Not visible.
  hidden,

  /// Trail animation in progress.
  animating,

  /// Fully visible.
  visible,

  /// Dismissed by student.
  dismissed,
}

/// ✨ Interleaving Path Controller — generates and manages the sentiero luminoso.
///
/// Generates a review path that maximally interleaves sub-topics
/// to leverage the Interleaving Effect (§10).
///
/// Usage:
/// ```dart
/// final path = InterleavingPathController();
/// path.generate(
///   nodes: reviewNodes,
///   topicAssignments: {'cluster_1': 'thermo', 'cluster_2': 'optics', ...},
/// );
/// // Renderer reads path.pathNodes for drawing
/// path.startAnimation();
/// ```
class InterleavingPathController extends ChangeNotifier {

  // ─────────────────────────────────────────────────────────────────────────
  // STATE
  // ─────────────────────────────────────────────────────────────────────────

  InterleavingPathState _state = InterleavingPathState.hidden;
  InterleavingPathState get state => _state;

  /// Whether the path is currently visible (animating or static).
  bool get isVisible =>
      _state == InterleavingPathState.animating ||
      _state == InterleavingPathState.visible;

  /// The ordered path nodes.
  List<PathNode> _pathNodes = const [];
  List<PathNode> get pathNodes => _pathNodes;

  /// Pre-computed path segments as Float32 pairs for rendering.
  /// Format: [x1, y1, x2, y2, ...] — zero allocation in paint().
  Float64List? _pathSegments;
  Float64List? get pathSegments => _pathSegments;

  /// Animation progress (0.0 → 1.0, for trail head position).
  double _animationProgress = 0.0;
  double get animationProgress => _animationProgress;

  /// Number of path segments currently visible (based on progress).
  int get visibleSegmentCount {
    if (_pathNodes.length <= 1) return 0;
    final total = _pathNodes.length - 1;
    return (_animationProgress * total).ceil().clamp(0, total);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // GENERATION (P6-15, P8-10)
  // ─────────────────────────────────────────────────────────────────────────

  /// Generate an interleaved review path.
  ///
  /// [nodes] — review-due nodes with positions.
  /// [topicAssignments] — clusterId → topic label (for interleaving).
  ///
  /// The algorithm maximizes topic switches between consecutive nodes:
  /// 1. Group nodes by topic
  /// 2. Round-robin pick from each topic group
  /// 3. Resolve ties by spatial proximity (minimize canvas jumps)
  void generate({
    required List<PathNode> nodes,
    Map<String, String>? topicAssignments,
  }) {
    if (nodes.isEmpty) {
      _pathNodes = const [];
      _pathSegments = null;
      _state = InterleavingPathState.hidden;
      notifyListeners();
      return;
    }

    if (nodes.length == 1) {
      _pathNodes = List.unmodifiable(nodes);
      _pathSegments = null;
      _state = InterleavingPathState.hidden;
      notifyListeners();
      return;
    }

    // Group by topic.
    final topics = topicAssignments ?? {};
    final groups = <String, List<PathNode>>{};
    for (final node in nodes) {
      final topic = topics[node.clusterId] ?? 'default';
      groups.putIfAbsent(topic, () => []).add(node);
    }

    // If only 1 topic (or no assignments), use spatial nearest-neighbor.
    if (groups.length <= 1) {
      _pathNodes = List.unmodifiable(_spatialOrder(nodes));
    } else {
      _pathNodes = List.unmodifiable(_interleave(groups));
    }

    // Pre-compute path segments.
    _computePathSegments();

    _state = InterleavingPathState.hidden;
    _animationProgress = 0.0;
    notifyListeners();
  }

  /// Interleave nodes from different topics using round-robin.
  List<PathNode> _interleave(Map<String, List<PathNode>> groups) {
    final result = <PathNode>[];
    final queues = groups.values.toList();

    // Sort each group by spatial proximity within topic.
    for (final queue in queues) {
      queue.sort((a, b) => a.position.dy.compareTo(b.position.dy));
    }

    // Round-robin: pick from each topic in turn.
    String? lastTopic;
    while (queues.any((q) => q.isNotEmpty)) {
      // Find the queue with a different topic from the last node.
      int bestQueueIdx = -1;
      double bestDistance = double.infinity;

      for (int i = 0; i < queues.length; i++) {
        if (queues[i].isEmpty) continue;

        final candidateTopic = queues[i].first.topic ?? 'default_$i';
        final isDifferentTopic = candidateTopic != lastTopic || lastTopic == null;

        if (isDifferentTopic) {
          // Prefer different topics (interleaving).
          final dist = result.isEmpty
              ? 0.0
              : (queues[i].first.position - result.last.position).distance;

          if (bestQueueIdx == -1 || dist < bestDistance) {
            bestQueueIdx = i;
            bestDistance = dist;
          }
        }
      }

      // Fallback: if all remaining are same topic, just pick nearest.
      if (bestQueueIdx == -1) {
        for (int i = 0; i < queues.length; i++) {
          if (queues[i].isEmpty) continue;
          bestQueueIdx = i;
          break;
        }
      }

      if (bestQueueIdx == -1) break;

      final node = queues[bestQueueIdx].removeAt(0);
      result.add(node);
      lastTopic = node.topic;
    }

    return result;
  }

  /// Order nodes by spatial nearest-neighbor (for single-topic fallback).
  List<PathNode> _spatialOrder(List<PathNode> nodes) {
    if (nodes.length <= 2) return List.from(nodes);

    final remaining = List<PathNode>.from(nodes);
    final ordered = <PathNode>[remaining.removeAt(0)];

    while (remaining.isNotEmpty) {
      final last = ordered.last.position;
      int nearestIdx = 0;
      double nearestDist = (remaining[0].position - last).distance;

      for (int i = 1; i < remaining.length; i++) {
        final dist = (remaining[i].position - last).distance;
        if (dist < nearestDist) {
          nearestDist = dist;
          nearestIdx = i;
        }
      }

      ordered.add(remaining.removeAt(nearestIdx));
    }

    return ordered;
  }

  /// Pre-compute Float64List of path segments for zero-alloc rendering.
  void _computePathSegments() {
    if (_pathNodes.length < 2) {
      _pathSegments = null;
      return;
    }

    final segCount = _pathNodes.length - 1;
    final segments = Float64List(segCount * 4);

    for (int i = 0; i < segCount; i++) {
      segments[i * 4 + 0] = _pathNodes[i].position.dx;
      segments[i * 4 + 1] = _pathNodes[i].position.dy;
      segments[i * 4 + 2] = _pathNodes[i + 1].position.dx;
      segments[i * 4 + 3] = _pathNodes[i + 1].position.dy;
    }

    _pathSegments = segments;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ANIMATION (A13-T06)
  // ─────────────────────────────────────────────────────────────────────────

  /// Start the trail animation (head advances, trail fades in 3s).
  void startAnimation() {
    if (_pathNodes.length < 2) return;
    _state = InterleavingPathState.animating;
    _animationProgress = 0.0;
    notifyListeners();
  }

  /// Update animation progress (called from animation ticker).
  ///
  /// [progress] — 0.0 (start) to 1.0 (complete).
  void updateProgress(double progress) {
    _animationProgress = progress.clamp(0.0, 1.0);
    if (_animationProgress >= 1.0) {
      _state = InterleavingPathState.visible;
    }
    notifyListeners();
  }

  /// Complete the animation immediately.
  void completeAnimation() {
    _animationProgress = 1.0;
    _state = InterleavingPathState.visible;
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DISMISS
  // ─────────────────────────────────────────────────────────────────────────

  /// Dismiss the path (student gesture).
  void dismiss() {
    _state = InterleavingPathState.dismissed;
    notifyListeners();
  }

  /// Hide the path without dismissing (e.g., session end).
  void hide() {
    _state = InterleavingPathState.hidden;
    _animationProgress = 0.0;
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // RENDERING HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  /// Golden color for the path (pre-cached for paint()).
  static const Color pathColor = Color(0xFFFFD700);

  /// Dotted line dash pattern: [dashLength, gapLength].
  static const double dashLength = 8.0;
  static const double gapLength = 4.0;

  /// Path stroke width.
  static const double strokeWidth = 2.0;

  /// Trail fade duration in milliseconds.
  static const int trailFadeDurationMs = 3000;
}
