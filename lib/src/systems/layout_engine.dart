import '../core/scene_graph/canvas_node.dart';
import '../core/nodes/group_node.dart';
import '../core/nodes/frame_node.dart';

// =============================================================================
// 🎯 LAYOUT ENGINE
//
// Top-level orchestrator for resolving auto-layout across the scene graph.
// Traverses the node tree and calls performLayout() on all FrameNodes
// that need re-layout, in correct dependency order (bottom-up first).
// =============================================================================

/// Resolves auto-layout for [FrameNode]s in the scene graph.
///
/// The engine traverses the tree depth-first, ensuring nested frames
/// are laid out before their parents (bottom-up measurement, top-down
/// positioning).
///
/// ```dart
/// // Resolve all frames in the entire scene graph:
/// LayoutEngine.resolveLayout(sceneGraphRoot);
///
/// // Resolve a single frame subtree:
/// LayoutEngine.resolveFrame(myFrame);
/// ```
///
/// DESIGN PRINCIPLES:
/// - Stateless: all state lives in the FrameNodes themselves
/// - Lazy: only re-layouts frames with needsLayout == true
/// - Safe: handles arbitrary nesting depth without stack overflow
///   concerns (scene graph depth is typically < 20)
class LayoutEngine {
  /// Resolve layout for all [FrameNode]s reachable from [root].
  ///
  /// Performs a depth-first traversal, collecting all dirty FrameNodes
  /// and resolving them bottom-up (deepest first, then parents).
  static void resolveLayout(CanvasNode root) {
    // Collect all FrameNodes that need layout, deepest first.
    final dirtyFrames = <FrameNode>[];
    _collectDirtyFrames(root, dirtyFrames);

    // Layout in reverse order (deepest first = bottom-up).
    for (final frame in dirtyFrames.reversed) {
      if (frame.needsLayout) {
        frame.performLayout();
      }
    }
  }

  /// Resolve layout for a single [FrameNode] and its descendants.
  ///
  /// This is the most common entry point — called by the renderer
  /// when it encounters a frame with [needsLayout] == true.
  static void resolveFrame(FrameNode frame) {
    // performLayout() already handles recursive bottom-up layout
    // for nested FrameNodes internally.
    if (frame.needsLayout) {
      frame.performLayout();
    }
  }

  /// Resolve layout for all [FrameNode]s with responsive variant support.
  ///
  /// For each FrameNode with responsive variants, applies the matching
  /// breakpoint overrides before layout and restores base values after.
  /// FrameNodes without variants are laid out normally.
  ///
  /// ```dart
  /// // Layout the entire tree for a 375px mobile viewport:
  /// LayoutEngine.resolveResponsiveLayout(root, 375);
  ///
  /// // Layout for desktop viewport:
  /// LayoutEngine.resolveResponsiveLayout(root, 1440);
  /// ```
  static void resolveResponsiveLayout(CanvasNode root, double viewportWidth) {
    // Collect all FrameNodes (including clean ones that may need
    // responsive override application).
    final allFrames = <FrameNode>[];
    _collectAllFrames(root, allFrames);

    // Apply responsive overrides on all frames (deepest first).
    for (final frame in allFrames.reversed) {
      frame.applyResponsiveOverrides(viewportWidth);
    }

    // Perform layout (deepest first = bottom-up).
    for (final frame in allFrames.reversed) {
      frame.markLayoutDirty();
      frame.performLayout();
    }

    // Restore base values on all frames.
    for (final frame in allFrames) {
      frame.restoreBaseValues();
    }
  }

  /// Collect all FrameNodes in DFS order (parents after children).
  static void _collectDirtyFrames(CanvasNode node, List<FrameNode> result) {
    if (node is GroupNode) {
      for (final child in node.children) {
        _collectDirtyFrames(child, result);
      }
    }

    if (node is FrameNode && node.needsLayout) {
      result.add(node);
    }
  }

  /// Collect ALL FrameNodes in DFS order (regardless of dirty flag).
  static void _collectAllFrames(CanvasNode node, List<FrameNode> result) {
    if (node is GroupNode) {
      for (final child in node.children) {
        _collectAllFrames(child, result);
      }
    }

    if (node is FrameNode) {
      result.add(node);
    }
  }
}
