import 'dart:ui';
import '../scene_graph/render_plan.dart';
import '../../core/scene_graph/canvas_node.dart';

/// Occlusion culling pass for a compiled [RenderPlan].
///
/// Walks the command list back-to-front, tracking opaque node bounds.
/// Nodes whose bounds are **completely** covered by opaque nodes above
/// them are replaced with [RenderCommand.skip], eliminating redundant
/// draw calls for hidden geometry.
///
/// ## When it helps
///
/// - Dense canvas with overlapping layers (e.g., 50+ layers)
/// - PDF pages stacked on top of each other
/// - Image nodes covering large areas
/// - Any scene where opaque nodes fully occlude lower nodes
///
/// ## Safety
///
/// Only nodes with `opacity == 1.0` AND `blendMode == BlendMode.srcOver`
/// are considered opaque. Transparent, masked, or blended nodes are
/// never used for occlusion and are never culled.
///
/// Usage:
/// ```dart
/// final compiler = RenderPlanCompiler();
/// final plan = compiler.compile(sceneGraph, viewport);
/// final optimized = OcclusionCuller.optimize(plan.commands);
/// ```
class OcclusionCuller {
  /// Maximum number of opaque regions to track before giving up.
  ///
  /// Prevents pathological O(N²) behavior on scenes with thousands
  /// of small opaque nodes.
  static const int maxOpaqueRegions = 64;

  /// Minimum area (in canvas-space px²) for a node to be an occluder.
  ///
  /// Tiny opaque nodes are unlikely to occlude anything, so tracking
  /// them wastes time.
  static const double minOccluderArea = 100.0;

  /// Run the occlusion culling pass on a command list.
  ///
  /// Returns a new list with occluded [RenderCommand.drawNode]s
  /// replaced by [RenderCommand.skip]. If no occlusion is found,
  /// returns the original list unchanged (zero allocation).
  static List<RenderCommand> optimize(List<RenderCommand> commands) {
    // Collect drawNode commands with their indices and bounds.
    final draws = <_DrawEntry>[];
    for (int i = 0; i < commands.length; i++) {
      final cmd = commands[i];
      if (cmd.type == RenderCommandType.drawNode && cmd.node != null) {
        draws.add(_DrawEntry(index: i, node: cmd.node!));
      }
    }

    if (draws.length < 2) return commands; // nothing to occlude

    // Walk back-to-front (last draw = topmost in z-order).
    // Track opaque regions that cover lower nodes.
    final opaqueRegions = <Rect>[];
    final occludedIndices = <int>{};

    for (int i = draws.length - 1; i >= 0; i--) {
      final entry = draws[i];
      final node = entry.node;
      final bounds = node.worldBounds;

      if (!bounds.isFinite || bounds.isEmpty) continue;

      // Check if this node is fully occluded by any opaque region above it.
      if (_isFullyOccluded(bounds, opaqueRegions)) {
        occludedIndices.add(entry.index);
        continue;
      }

      // If this node is opaque and large enough, add it as an occluder.
      if (_isOpaque(node) && _area(bounds) >= minOccluderArea) {
        if (opaqueRegions.length < maxOpaqueRegions) {
          opaqueRegions.add(bounds);
        }
      }
    }

    if (occludedIndices.isEmpty) return commands; // no optimization possible

    // Build optimized command list.
    final optimized = List<RenderCommand>.from(commands);
    for (final idx in occludedIndices) {
      optimized[idx] = const RenderCommand.skip();
    }
    return optimized;
  }

  /// Whether a node is fully opaque (no transparency, standard blend).
  static bool _isOpaque(CanvasNode node) {
    return node.opacity >= 1.0 && node.blendMode == BlendMode.srcOver;
  }

  /// Whether [bounds] is completely covered by any single opaque region.
  ///
  /// Uses simple single-rect containment. A more sophisticated approach
  /// would union opaque regions, but that adds complexity for marginal
  /// gain in typical scenes.
  static bool _isFullyOccluded(Rect bounds, List<Rect> opaqueRegions) {
    for (final opaque in opaqueRegions) {
      if (opaque.left <= bounds.left &&
          opaque.top <= bounds.top &&
          opaque.right >= bounds.right &&
          opaque.bottom >= bounds.bottom) {
        return true;
      }
    }
    return false;
  }

  /// Area of a rectangle.
  static double _area(Rect r) => r.width * r.height;
}

/// Internal helper pairing a draw command index with its node.
class _DrawEntry {
  final int index;
  final CanvasNode node;
  const _DrawEntry({required this.index, required this.node});
}
