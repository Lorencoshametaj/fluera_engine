import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../core/scene_graph/canvas_node.dart';
import '../../core/scene_graph/scene_graph.dart';
import '../../core/nodes/group_node.dart';
import '../infinite_canvas_controller.dart';

/// ⚡ Smart camera actions for canvas orientation.
///
/// Pure utility class with static methods — no state, no side effects
/// beyond calling [InfiniteCanvasController.animateToTransform].
///
/// DESIGN PRINCIPLES:
/// - All transitions use spring animations via the controller.
/// - Padding factor (10%) prevents content from touching viewport edges.
/// - All methods are fire-and-forget — multiple calls are safe (latest wins).
///
/// Usage:
/// ```dart
/// CameraActions.fitAllContent(controller, sceneGraph, viewportSize);
/// CameraActions.fitSelection(controller, selectedNodes, viewportSize);
/// CameraActions.returnToOrigin(controller);
/// ```
class CameraActions {
  CameraActions._(); // Non-instantiable.

  /// Padding fraction applied around content when fitting.
  static const double _paddingFraction = 0.10;

  // ---------------------------------------------------------------------------
  // Fit All Content
  // ---------------------------------------------------------------------------

  /// Animate the camera to show all visible content in the canvas.
  ///
  /// Computes the bounding box of every visible, non-group node and
  /// calculates the optimal zoom level to fit it within [viewportSize]
  /// with 10% padding on each side.
  static void fitAllContent(
    InfiniteCanvasController controller,
    SceneGraph sceneGraph,
    Size viewportSize,
  ) {
    final bounds = _computeAllContentBounds(sceneGraph);
    if (bounds == Rect.zero || bounds.isEmpty) return;
    _animateToFitBounds(controller, bounds, viewportSize);
  }

  // ---------------------------------------------------------------------------
  // Fit Selection
  // ---------------------------------------------------------------------------

  /// Animate the camera to show all selected nodes.
  ///
  /// If [selectedNodes] is empty, does nothing.
  static void fitSelection(
    InfiniteCanvasController controller,
    Iterable<CanvasNode> selectedNodes,
    Size viewportSize,
  ) {
    if (selectedNodes.isEmpty) return;

    Rect? bounds;
    for (final node in selectedNodes) {
      final b = node.worldBounds;
      if (b.isFinite && !b.isEmpty) {
        bounds = bounds == null ? b : bounds.expandToInclude(b);
      }
    }
    if (bounds == null || bounds.isEmpty) return;
    _animateToFitBounds(controller, bounds, viewportSize);
  }

  // ---------------------------------------------------------------------------
  // Zoom to Rect
  // ---------------------------------------------------------------------------

  /// Animate the camera to fit an arbitrary rectangle in view.
  ///
  /// Useful for zoom-to-section, zoom-to-search-result, etc.
  static void zoomToRect(
    InfiniteCanvasController controller,
    Rect target,
    Size viewportSize,
  ) {
    if (target.isEmpty) return;
    _animateToFitBounds(controller, target, viewportSize);
  }

  // ---------------------------------------------------------------------------
  // Return to Origin
  // ---------------------------------------------------------------------------

  /// Animate back to canvas origin (0, 0) at 100% zoom.
  static void returnToOrigin(
    InfiniteCanvasController controller,
    Size viewportSize,
  ) {
    // Center origin in the viewport.
    final targetOffset = Offset(
      viewportSize.width / 2,
      viewportSize.height / 2,
    );
    controller.animateToTransform(
      targetOffset: targetOffset,
      targetScale: 1.0,
      focalPoint: Offset(viewportSize.width / 2, viewportSize.height / 2),
    );
  }

  // ---------------------------------------------------------------------------
  // Zoom to Level
  // ---------------------------------------------------------------------------

  /// Animate to a specific zoom level, centered on the current viewport center.
  static void zoomToLevel(
    InfiniteCanvasController controller,
    double targetScale,
    Size viewportSize,
  ) {
    final center = Offset(viewportSize.width / 2, viewportSize.height / 2);
    controller.animateZoomTo(targetScale, center);
  }

  // ---------------------------------------------------------------------------
  // 🎬 Cinematic Flight — Animated camera pan along a connection
  // ---------------------------------------------------------------------------

  /// Animate the camera in a cinematic 5-phase flight from [sourceBounds]
  /// to [targetBounds]:
  ///
  /// - **Phase 0 (Anticipation)**: Quick 2% zoom-in on source → "pull back
  ///   before launch" feel (Disney anticipation principle)
  /// - **Phase 1 (Ascent)**: Zoom-out to reveal the arc between clusters
  /// - **Phase 2 (Transit)**: Smooth pan following the connection path
  /// - **Phase 3 (Descent)**: Zoom-in to frame the target cluster
  /// - **Phase 4 (Bounce)**: Overshoot 5% then spring-settle → impact feel
  ///
  /// [sourceClusterId] and [targetClusterId] are passed to the controller
  /// so painters can highlight only the active connection.
  ///
  /// [onPhaseChanged] fires at each phase transition (for haptic feedback).
  /// [onComplete] fires when the flight reaches the target.
  static void cinematicFlight(
    InfiniteCanvasController controller,
    Rect sourceBounds,
    Rect targetBounds,
    Size viewportSize, {
    double curveStrength = 0.3,
    String? sourceClusterId,
    String? targetClusterId,
    VoidCallback? onMidpoint,
    VoidCallback? onComplete,
    void Function(int phase)? onPhaseChanged,
  }) {
    if (sourceBounds.isEmpty || targetBounds.isEmpty) return;

    final currentScale = controller.scale;
    final currentOffset = controller.offset;

    // Compute combined bounds to determine zoom-out level
    final combinedBounds = sourceBounds.expandToInclude(targetBounds);
    final inflated = combinedBounds.inflate(
      combinedBounds.longestSide * 0.25,
    );

    // Overview scale: zoom out to show both clusters with padding
    final overviewScale = _fitScale(inflated, viewportSize) * 0.85;

    // Midpoint of the arc (curving perpendicular to the straight line)
    final srcCenter = sourceBounds.center;
    final tgtCenter = targetBounds.center;
    final midX = (srcCenter.dx + tgtCenter.dx) / 2;
    final midY = (srcCenter.dy + tgtCenter.dy) / 2;
    final dx = tgtCenter.dx - srcCenter.dx;
    final dy = tgtCenter.dy - srcCenter.dy;
    final length = math.sqrt(dx * dx + dy * dy);
    final perpX = length > 0 ? -dy / length : 0.0;
    final perpY = length > 0 ? dx / length : 0.0;
    final offset = length * curveStrength;
    final arcMid = Offset(
      midX + perpX * offset,
      midY + perpY * offset,
    );

    // 🛩️ CAMERA BANKING: Tilt direction based on arc curve
    // Compute angle from source to target, then apply 2° tilt
    final bankAngle = length > 0
        ? math.atan2(dy, dx) * 0.035 // ~2° proportional to arc direction
        : 0.0;
    final bankSign = curveStrength >= 0 ? 1.0 : -1.0;
    final transitRotation = bankAngle * bankSign;

    // ⏱️ ADAPTIVE SPEED: Shorten phases based on current state
    // If already zoomed out, the ascent is shorter
    final scaleRatio = currentScale / overviewScale;
    final ascentAdaptive = scaleRatio < 1.5 ? 0.18 : 0.30; // already close
    // If camera is already near target, shorter descent
    final distToTarget = (currentOffset - Offset(
      viewportSize.width / 2 - tgtCenter.dx * currentScale,
      viewportSize.height / 2 - tgtCenter.dy * currentScale,
    )).distance;
    final descentAdaptive = distToTarget < viewportSize.shortestSide
        ? 0.22 : 0.35;

    // Phase 0 — Anticipation: tiny zoom-in on source (2%)
    final anticipationScale = currentScale * 1.02;
    final anticipationOffset = Offset(
      currentOffset.dx - (anticipationScale - currentScale) * srcCenter.dx,
      currentOffset.dy - (anticipationScale - currentScale) * srcCenter.dy,
    );

    // Phase 1 — Ascent: Zoom out to overview, centered on connection midpoint
    final overviewOffset = Offset(
      viewportSize.width / 2 - arcMid.dx * overviewScale,
      viewportSize.height / 2 - arcMid.dy * overviewScale,
    );

    // Phase 2 — Transit: Pan along the Bézier arc toward target
    final transit60 = Offset(
      srcCenter.dx * 0.16 + arcMid.dx * 0.48 + tgtCenter.dx * 0.36,
      srcCenter.dy * 0.16 + arcMid.dy * 0.48 + tgtCenter.dy * 0.36,
    );
    final transitOffset = Offset(
      viewportSize.width / 2 - transit60.dx * overviewScale,
      viewportSize.height / 2 - transit60.dy * overviewScale,
    );

    // Phase 3 — Descent: Zoom in to frame target cluster
    final targetScale = _fitScale(
      targetBounds.inflate(targetBounds.longestSide * 0.3),
      viewportSize,
    );
    final descendOffset = Offset(
      viewportSize.width / 2 - tgtCenter.dx * targetScale,
      viewportSize.height / 2 - tgtCenter.dy * targetScale,
    );

    // Phase 4 — Bounce: Overshoot 5% then spring back
    final bounceScale = targetScale * 1.05;
    final bounceOffset = Offset(
      viewportSize.width / 2 - tgtCenter.dx * bounceScale,
      viewportSize.height / 2 - tgtCenter.dy * bounceScale,
    );

    controller.animateMultiPhase(
      keyframes: [
        // Phase 0: Anticipation
        CameraKeyframe(
          targetOffset: anticipationOffset,
          targetScale: anticipationScale,
          durationSeconds: 0.10,
          curve: Curves.easeOut,
        ),
        // Phase 1: Ascent (adaptive duration)
        CameraKeyframe(
          targetOffset: overviewOffset,
          targetScale: overviewScale,
          durationSeconds: ascentAdaptive,
          curve: Curves.easeOutCubic,
        ),
        // Phase 2: Transit (with banking rotation)
        CameraKeyframe(
          targetOffset: transitOffset,
          targetScale: overviewScale * 0.95,
          targetRotation: transitRotation,
          durationSeconds: 0.40,
          curve: Curves.easeInOutCubic,
        ),
        // Phase 3: Descent (overshoot, rotation resets)
        CameraKeyframe(
          targetOffset: bounceOffset,
          targetScale: bounceScale,
          targetRotation: 0.0, // Reset banking
          durationSeconds: descentAdaptive,
          curve: Curves.easeInOutCubic,
        ),
        // Phase 4: Bounce settle
        CameraKeyframe(
          targetOffset: descendOffset,
          targetScale: targetScale,
          targetRotation: 0.0,
          durationSeconds: 0.18,
          curve: Curves.easeOutBack,
        ),
      ],
      sourceClusterId: sourceClusterId,
      targetClusterId: targetClusterId,
      onComplete: onComplete,
      onPhaseChanged: (phase) {
        onPhaseChanged?.call(phase);
        if (phase == 2) onMidpoint?.call();
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 🚀 Hyper-Jump — Google Earth-style navigation for distant connections
  // ---------------------------------------------------------------------------

  /// Animate the camera in a dramatic 5-phase Google Earth-style jump:
  ///
  /// - **Phase 0 (Anticipation)**: Quick 3% zoom-in → "launch charge" feel
  /// - **Phase 1 (Ascent)**: Dramatic zoom-out to satellite level (LOD 2)
  /// - **Phase 2 (Transit)**: Pan across the zoomed-out view
  /// - **Phase 3 (Descent)**: Zoom back in past target (overshoot 5%)
  /// - **Phase 4 (Bounce)**: Spring-settle to final scale → impact feel
  ///
  /// [onComplete] fires when the descent finishes.
  /// [onPhaseChanged] fires at each phase transition.
  static void hyperJump(
    InfiniteCanvasController controller,
    Rect sourceBounds,
    Rect targetBounds,
    Size viewportSize, {
    String? sourceClusterId,
    String? targetClusterId,
    VoidCallback? onComplete,
    void Function(int phase)? onPhaseChanged,
  }) {
    if (sourceBounds.isEmpty || targetBounds.isEmpty) return;

    final currentScale = controller.scale;
    final currentOffset = controller.offset;
    final srcCenter = sourceBounds.center;
    final tgtCenter = targetBounds.center;
    final distance = (tgtCenter - srcCenter).distance;

    // Satellite scale: zoom way out so entire journey is visible
    final combinedBounds = sourceBounds.expandToInclude(targetBounds);
    final satelliteScale = _fitScale(
      combinedBounds.inflate(distance * 0.4),
      viewportSize,
    ).clamp(0.03, 0.12);

    // 🛩️ CAMERA BANKING: 3° tilt from travel direction
    final tDx = tgtCenter.dx - srcCenter.dx;
    final tDy = tgtCenter.dy - srcCenter.dy;
    final bankAngle = distance > 0
        ? math.atan2(tDy, tDx) * 0.05 // ~3° proportional
        : 0.0;

    // ⏱️ ADAPTIVE SPEED: If already zoomed out, shorter ascent
    final scaleRatio = currentScale / satelliteScale;
    final ascentAdaptive = scaleRatio < 3.0
        ? 0.25 : (0.40 + (distance / 10000.0).clamp(0.0, 0.3));
    // If camera already near target, shorter descent
    final distToTarget = (currentOffset - Offset(
      viewportSize.width / 2 - tgtCenter.dx * currentScale,
      viewportSize.height / 2 - tgtCenter.dy * currentScale,
    )).distance;
    final targetScale = _fitScale(
      targetBounds.inflate(targetBounds.longestSide * 0.3),
      viewportSize,
    );
    final descentAdaptive = distToTarget < viewportSize.shortestSide * 2
        ? 0.30 : (0.45 + (distance / 12000.0).clamp(0.0, 0.2));

    // Phase 0 — Anticipation: 3% zoom-in on source
    final anticipationScale = currentScale * 1.03;
    final anticipationOffset = Offset(
      currentOffset.dx - (anticipationScale - currentScale) * srcCenter.dx,
      currentOffset.dy - (anticipationScale - currentScale) * srcCenter.dy,
    );

    // Phase 1 — Ascent: zoom out to satellite, centered on source
    final ascentOffset = Offset(
      viewportSize.width / 2 - srcCenter.dx * satelliteScale,
      viewportSize.height / 2 - srcCenter.dy * satelliteScale,
    );

    // Phase 2 — Transit: pan to center on target at satellite level
    final transitOffset = Offset(
      viewportSize.width / 2 - tgtCenter.dx * satelliteScale,
      viewportSize.height / 2 - tgtCenter.dy * satelliteScale,
    );

    // Phase 3 — Descent: zoom back in (overshoot 5%)
    final bounceScale = targetScale * 1.05;
    final bounceOffset = Offset(
      viewportSize.width / 2 - tgtCenter.dx * bounceScale,
      viewportSize.height / 2 - tgtCenter.dy * bounceScale,
    );

    // Phase 4 — Settle: spring to final scale
    final descendOffset = Offset(
      viewportSize.width / 2 - tgtCenter.dx * targetScale,
      viewportSize.height / 2 - tgtCenter.dy * targetScale,
    );

    // Duration proportional to distance (feel natural)
    final transitDuration = 0.45 + (distance / 8000.0).clamp(0.0, 0.4);

    controller.animateMultiPhase(
      keyframes: [
        // Phase 0: Anticipation
        CameraKeyframe(
          targetOffset: anticipationOffset,
          targetScale: anticipationScale,
          durationSeconds: 0.12,
          curve: Curves.easeOut,
        ),
        // Phase 1: Ascent (adaptive)
        CameraKeyframe(
          targetOffset: ascentOffset,
          targetScale: satelliteScale,
          durationSeconds: ascentAdaptive,
          curve: Curves.easeInCubic,
        ),
        // Phase 2: Transit (with banking)
        CameraKeyframe(
          targetOffset: transitOffset,
          targetScale: satelliteScale,
          targetRotation: bankAngle,
          durationSeconds: transitDuration,
          curve: Curves.easeInOutCubic,
        ),
        // Phase 3: Descent (overshoot, rotation resets)
        CameraKeyframe(
          targetOffset: bounceOffset,
          targetScale: bounceScale,
          targetRotation: 0.0,
          durationSeconds: descentAdaptive,
          curve: Curves.easeOutCubic,
        ),
        // Phase 4: Bounce settle
        CameraKeyframe(
          targetOffset: descendOffset,
          targetScale: targetScale,
          targetRotation: 0.0,
          durationSeconds: 0.20,
          curve: Curves.easeOutBack,
        ),
      ],
      sourceClusterId: sourceClusterId,
      targetClusterId: targetClusterId,
      onComplete: onComplete,
      onPhaseChanged: onPhaseChanged,
    );
  }

  // ---------------------------------------------------------------------------
  // 🔗 Fly Along Connection — Auto-selects flight or jump
  // ---------------------------------------------------------------------------

  /// Convenience: tapping a connection triggers either a [cinematicFlight]
  /// or a [hyperJump] depending on the distance between clusters.
  ///
  /// Distance > [distanceThreshold] (default: 3000 canvas px) → Hyper-Jump.
  /// Otherwise → Cinematic Flight.
  ///
  /// Pass [sourceClusterId] and [targetClusterId] for connection-specific
  /// glow effects in the painter.
  static void flyAlongConnection(
    InfiniteCanvasController controller,
    Rect sourceBounds,
    Rect targetBounds,
    Size viewportSize, {
    double curveStrength = 0.3,
    double distanceThreshold = 3000.0,
    String? sourceClusterId,
    String? targetClusterId,
    VoidCallback? onComplete,
    void Function(int phase)? onPhaseChanged,
  }) {
    final distance = (targetBounds.center - sourceBounds.center).distance;

    if (distance > distanceThreshold) {
      hyperJump(
        controller,
        sourceBounds,
        targetBounds,
        viewportSize,
        sourceClusterId: sourceClusterId,
        targetClusterId: targetClusterId,
        onComplete: onComplete,
        onPhaseChanged: onPhaseChanged,
      );
    } else {
      cinematicFlight(
        controller,
        sourceBounds,
        targetBounds,
        viewportSize,
        curveStrength: curveStrength,
        sourceClusterId: sourceClusterId,
        targetClusterId: targetClusterId,
        onComplete: onComplete,
        onPhaseChanged: onPhaseChanged,
        onMidpoint: () => onPhaseChanged?.call(2),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  /// Compute bounding box of all visible content (same logic as ExportPipeline).
  static Rect _computeAllContentBounds(SceneGraph sceneGraph) {
    Rect? bounds;
    for (final node in sceneGraph.allNodes) {
      if (!node.isVisible) continue;
      if (node is GroupNode) continue;
      final b = node.worldBounds;
      if (b.isFinite && !b.isEmpty) {
        bounds = bounds == null ? b : bounds.expandToInclude(b);
      }
    }
    return bounds ?? Rect.zero;
  }

  /// Compute the scale needed to fit [bounds] within [viewportSize] with padding.
  static double _fitScale(Rect bounds, Size viewportSize) {
    if (bounds.isEmpty || bounds.width <= 0 || bounds.height <= 0) return 1.0;
    final paddingH = viewportSize.width * _paddingFraction;
    final paddingV = viewportSize.height * _paddingFraction;
    final availableW = viewportSize.width - paddingH * 2;
    final availableH = viewportSize.height - paddingV * 2;
    if (availableW <= 0 || availableH <= 0) return 1.0;
    final scaleX = availableW / bounds.width;
    final scaleY = availableH / bounds.height;
    return math.min(scaleX, scaleY).clamp(0.05, 10.0);
  }

  /// Animate the controller to fit [bounds] within [viewportSize] with padding.
  static void _animateToFitBounds(
    InfiniteCanvasController controller,
    Rect bounds,
    Size viewportSize,
  ) {
    // Available viewport with padding.
    final paddingH = viewportSize.width * _paddingFraction;
    final paddingV = viewportSize.height * _paddingFraction;
    final availableW = viewportSize.width - paddingH * 2;
    final availableH = viewportSize.height - paddingV * 2;

    if (availableW <= 0 || availableH <= 0) return;

    // Scale to fit the content bounds inside the available viewport.
    final scaleX = availableW / bounds.width;
    final scaleY = availableH / bounds.height;
    final targetScale = math.min(scaleX, scaleY).clamp(0.05, 10.0);

    // Offset to center the content bounds in the viewport.
    final contentCenterX = bounds.left + bounds.width / 2;
    final contentCenterY = bounds.top + bounds.height / 2;
    final targetOffsetX = viewportSize.width / 2 - contentCenterX * targetScale;
    final targetOffsetY =
        viewportSize.height / 2 - contentCenterY * targetScale;

    controller.animateToTransform(
      targetOffset: Offset(targetOffsetX, targetOffsetY),
      targetScale: targetScale,
      focalPoint: Offset(viewportSize.width / 2, viewportSize.height / 2),
    );
  }
}

