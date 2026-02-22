/// 🎬 SMART ANIMATE ENGINE — Layer matching and morphing transitions.
///
/// Implements `PrototypeTransition.smartAnimate` by:
/// 1. Matching layers between source/target frames (by name)
/// 2. Snapshotting animatable properties of matched layers
/// 3. Interpolating all properties during the transition
///
/// ```dart
/// final engine = SmartAnimateEngine();
/// final plan = engine.createTransitionPlan(
///   sourceFrame: loginScreen,
///   targetFrame: settingsScreen,
/// );
/// // At each tick (t = 0.0–1.0):
/// engine.applyTransitionFrame(plan, t);
/// ```
library;

import 'dart:ui' as ui;
import '../core/scene_graph/canvas_node.dart';
import '../core/nodes/group_node.dart';
import '../core/nodes/frame_node.dart'
    hide CrossAxisAlignment, MainAxisAlignment;
import 'smart_animate_snapshot.dart';

// =============================================================================
// MATCHED LAYER PAIR
// =============================================================================

/// A pair of matched nodes between source and target frames.
class MatchedLayer {
  /// The source node (from the outgoing frame).
  final CanvasNode sourceNode;

  /// The target node (from the incoming frame).
  final CanvasNode targetNode;

  /// Snapshot of the source node's animatable properties.
  final SmartAnimateSnapshot sourceSnapshot;

  /// Snapshot of the target node's animatable properties.
  final SmartAnimateSnapshot targetSnapshot;

  const MatchedLayer({
    required this.sourceNode,
    required this.targetNode,
    required this.sourceSnapshot,
    required this.targetSnapshot,
  });
}

/// A node that appears only in the source (exits) or target (enters).
class UnmatchedLayer {
  /// The unmatched node.
  final CanvasNode node;

  /// Snapshot at its resting state.
  final SmartAnimateSnapshot snapshot;

  /// Whether this node is entering (target-only) or exiting (source-only).
  final bool isEntering;

  const UnmatchedLayer({
    required this.node,
    required this.snapshot,
    required this.isEntering,
  });
}

// =============================================================================
// TRANSITION PLAN
// =============================================================================

/// Complete plan for a Smart Animate transition between two frames.
///
/// Created once, then applied at each tick of the animation.
class SmartAnimateTransitionPlan {
  /// Matched layer pairs that will be interpolated.
  final List<MatchedLayer> matchedLayers;

  /// Nodes unique to the source frame (will fade out).
  final List<UnmatchedLayer> exitingLayers;

  /// Nodes unique to the target frame (will fade in).
  final List<UnmatchedLayer> enteringLayers;

  /// Total number of layers involved in the transition.
  int get totalLayers =>
      matchedLayers.length + exitingLayers.length + enteringLayers.length;

  /// Number of matched pairs.
  int get matchedCount => matchedLayers.length;

  const SmartAnimateTransitionPlan({
    required this.matchedLayers,
    required this.exitingLayers,
    required this.enteringLayers,
  });

  /// Serialization for debugging/inspection.
  Map<String, dynamic> toJson() => {
    'matchedCount': matchedLayers.length,
    'exitingCount': exitingLayers.length,
    'enteringCount': enteringLayers.length,
    'matchedNames': matchedLayers.map((m) => m.sourceNode.name).toList(),
    'exitingNames': exitingLayers.map((u) => u.node.name).toList(),
    'enteringNames': enteringLayers.map((u) => u.node.name).toList(),
  };
}

// =============================================================================
// SMART ANIMATE ENGINE
// =============================================================================

/// Engine that creates and executes Smart Animate transitions.
///
/// Smart Animate finds matching layers between two frames by **name**
/// (Figma-compatible) and smoothly interpolates their visual properties
/// (position, size, opacity, color, border radius, rotation).
///
/// Unmatched layers fade in or out as appropriate.
class SmartAnimateEngine {
  /// Whether to use case-sensitive name matching (default: true, Figma-compat).
  final bool caseSensitiveMatching;

  /// Whether to also try matching by node ID as a fallback.
  final bool enableIdFallback;

  const SmartAnimateEngine({
    this.caseSensitiveMatching = true,
    this.enableIdFallback = false,
  });

  // ---------------------------------------------------------------------------
  // Transition plan creation
  // ---------------------------------------------------------------------------

  /// Create a transition plan between two frames.
  ///
  /// Walks the children of both frames, matches layers by name,
  /// and snapshots their animatable properties.
  SmartAnimateTransitionPlan createTransitionPlan({
    required CanvasNode sourceFrame,
    required CanvasNode targetFrame,
  }) {
    // Flatten node trees to leaf/group level.
    final sourceNodes = _collectAnimatableNodes(sourceFrame);
    final targetNodes = _collectAnimatableNodes(targetFrame);

    // Build lookup maps.
    final sourceByName = <String, CanvasNode>{};
    final targetByName = <String, CanvasNode>{};
    final sourceById = <String, CanvasNode>{};
    final targetById = <String, CanvasNode>{};

    for (final node in sourceNodes) {
      final key = caseSensitiveMatching ? node.name : node.name.toLowerCase();
      if (key.isNotEmpty) sourceByName[key] = node;
      sourceById[node.id.value] = node;
    }
    for (final node in targetNodes) {
      final key = caseSensitiveMatching ? node.name : node.name.toLowerCase();
      if (key.isNotEmpty) targetByName[key] = node;
      targetById[node.id.value] = node;
    }

    // Match by name.
    final matched = <MatchedLayer>[];
    final matchedSourceIds = <String>{};
    final matchedTargetIds = <String>{};

    for (final entry in sourceByName.entries) {
      final targetNode = targetByName[entry.key];
      if (targetNode != null) {
        matched.add(
          MatchedLayer(
            sourceNode: entry.value,
            targetNode: targetNode,
            sourceSnapshot: SmartAnimateSnapshot.capture(entry.value),
            targetSnapshot: SmartAnimateSnapshot.capture(targetNode),
          ),
        );
        matchedSourceIds.add(entry.value.id.value);
        matchedTargetIds.add(targetNode.id.value);
      }
    }

    // Fallback: match remaining by ID.
    if (enableIdFallback) {
      for (final entry in sourceById.entries) {
        if (matchedSourceIds.contains(entry.key)) continue;
        final targetNode = targetById[entry.key];
        if (targetNode != null && !matchedTargetIds.contains(entry.key)) {
          matched.add(
            MatchedLayer(
              sourceNode: entry.value,
              targetNode: targetNode,
              sourceSnapshot: SmartAnimateSnapshot.capture(entry.value),
              targetSnapshot: SmartAnimateSnapshot.capture(targetNode),
            ),
          );
          matchedSourceIds.add(entry.key);
          matchedTargetIds.add(entry.key);
        }
      }
    }

    // Collect unmatched layers.
    final exiting = <UnmatchedLayer>[];
    final entering = <UnmatchedLayer>[];

    for (final node in sourceNodes) {
      if (!matchedSourceIds.contains(node.id.value)) {
        exiting.add(
          UnmatchedLayer(
            node: node,
            snapshot: SmartAnimateSnapshot.capture(node),
            isEntering: false,
          ),
        );
      }
    }
    for (final node in targetNodes) {
      if (!matchedTargetIds.contains(node.id.value)) {
        entering.add(
          UnmatchedLayer(
            node: node,
            snapshot: SmartAnimateSnapshot.capture(node),
            isEntering: true,
          ),
        );
      }
    }

    return SmartAnimateTransitionPlan(
      matchedLayers: matched,
      exitingLayers: exiting,
      enteringLayers: entering,
    );
  }

  // ---------------------------------------------------------------------------
  // Transition execution
  // ---------------------------------------------------------------------------

  /// Apply a transition frame at progress [t] (0.0–1.0).
  ///
  /// Interpolates matched layers, fades entering/exiting layers.
  /// The [easing] function transforms `t` before interpolation.
  ///
  /// Call this on each animation tick during prototype playback.
  void applyTransitionFrame(
    SmartAnimateTransitionPlan plan,
    double t, {
    double Function(double)? easing,
  }) {
    final easedT =
        easing != null ? easing(t).clamp(0.0, 1.0) : t.clamp(0.0, 1.0);

    // Interpolate matched layers.
    for (final pair in plan.matchedLayers) {
      final interpolated = SmartAnimateSnapshot.interpolate(
        pair.sourceSnapshot,
        pair.targetSnapshot,
        easedT,
      );

      // Apply to the target node (the one that's visible during transition).
      SmartAnimateSnapshot.apply(pair.targetNode, interpolated);
    }

    // Fade out exiting layers (opacity → 0).
    for (final layer in plan.exitingLayers) {
      layer.node.opacity = (1.0 - easedT).clamp(0.0, 1.0);
    }

    // Fade in entering layers (opacity 0 → target).
    for (final layer in plan.enteringLayers) {
      final targetOpacity =
          layer.snapshot.properties[AnimatableProperty.opacity] ?? 1.0;
      layer.node.opacity = (targetOpacity * easedT).clamp(0.0, 1.0);
    }
  }

  /// Reset all nodes to their original state after a transition completes.
  ///
  /// Applies the target snapshot to matched nodes and restores
  /// entering/exiting nodes to their original opacity.
  void resetAfterTransition(SmartAnimateTransitionPlan plan) {
    // Apply final target state to matched layers.
    for (final pair in plan.matchedLayers) {
      SmartAnimateSnapshot.apply(pair.targetNode, pair.targetSnapshot);
    }

    // Restore exiting layers (they should be hidden after transition).
    for (final layer in plan.exitingLayers) {
      layer.node.opacity = 0.0;
    }

    // Restore entering layers to their target opacity.
    for (final layer in plan.enteringLayers) {
      final targetOpacity =
          layer.snapshot.properties[AnimatableProperty.opacity] ?? 1.0;
      layer.node.opacity = targetOpacity;
    }
  }

  // ---------------------------------------------------------------------------
  // Easing curves
  // ---------------------------------------------------------------------------

  /// Standard easing curves for Smart Animate transitions.
  static double easeIn(double t) => t * t;
  static double easeOut(double t) => 1.0 - (1.0 - t) * (1.0 - t);
  static double easeInOut(double t) =>
      t < 0.5 ? 2 * t * t : 1 - (-2 * t + 2) * (-2 * t + 2) / 2;
  static double linear(double t) => t;

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  /// Recursively collect all animatable nodes from a frame.
  ///
  /// Walks the tree depth-first, collecting descendant nodes that have
  /// a non-empty name (required for matching). The root frame itself
  /// is excluded — only its children participate in matching.
  List<CanvasNode> _collectAnimatableNodes(CanvasNode root) {
    final result = <CanvasNode>[];
    // Only walk children of the root — the root is the frame, not a layer.
    if (root is FrameNode) {
      for (final child in root.children) {
        _walkNodes(child, result);
      }
    } else if (root is GroupNode) {
      for (final child in root.children) {
        _walkNodes(child, result);
      }
    }
    return result;
  }

  void _walkNodes(CanvasNode node, List<CanvasNode> result) {
    // Include this node if it has a name.
    if (node.name.isNotEmpty) {
      result.add(node);
    }

    // Walk children for groups/frames.
    if (node is FrameNode) {
      for (final child in node.children) {
        _walkNodes(child, result);
      }
    } else if (node is GroupNode) {
      for (final child in node.children) {
        _walkNodes(child, result);
      }
    }
  }
}
