import 'dart:math' as math;
import 'dart:ui';

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
