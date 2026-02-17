import 'dart:ui';
import '../../core/nodes/path_node.dart';

/// Renders a [PathNode] to a [Canvas].
///
/// Handles fill and stroke rendering independently, each optionally
/// using a gradient shader. This is called by [SceneGraphRenderer]
/// when traversing the scene graph tree.
class PathRenderer {
  PathRenderer._();

  /// Draw the path node's fill and/or stroke.
  static void drawPathNode(Canvas canvas, PathNode node) {
    final flutterPath = node.path.toFlutterPath();
    final bounds = node.path.computeBounds();

    // --- Fill ---
    if (node.fillColor != null || node.fillGradient != null) {
      final fillPaint = Paint()..style = PaintingStyle.fill;

      if (node.fillGradient != null) {
        fillPaint.shader = node.fillGradient!.toShader(bounds);
      } else if (node.fillColor != null) {
        fillPaint.color = node.fillColor!;
      }

      canvas.drawPath(flutterPath, fillPaint);
    }

    // --- Stroke ---
    if (node.strokeColor != null || node.strokeGradient != null) {
      final strokePaint =
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = node.strokeWidth
            ..strokeCap = node.strokeCap
            ..strokeJoin = node.strokeJoin;

      if (node.strokeGradient != null) {
        strokePaint.shader = node.strokeGradient!.toShader(bounds);
      } else if (node.strokeColor != null) {
        strokePaint.color = node.strokeColor!;
      }

      canvas.drawPath(flutterPath, strokePaint);
    }
  }
}
