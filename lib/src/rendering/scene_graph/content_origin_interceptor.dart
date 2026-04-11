import 'package:flutter/material.dart';
import '../../core/scene_graph/canvas_node.dart';
import '../../core/scene_graph/content_origin.dart';
import '../../core/nodes/group_node.dart';
import './render_interceptor.dart';

// =============================================================================
// 🏷️ CONTENT ORIGIN INTERCEPTOR — Visual provenance indicator (A20.3)
// =============================================================================

/// Paints a small colored dot at the top-right corner of each **leaf** node
/// to indicate its content provenance:
///
/// | Origin       | Color | Meaning          |
/// |--------------|-------|------------------|
/// | handwriting  | 🟢    | Student-authored |
/// | imported     | 🔵    | External source  |
/// | aiGenerated  | 🔴    | AI-produced      |
///
/// The dot is painted in **world coordinates** after the node's own rendering,
/// so it appears as a floating overlay on the canvas. It scales inversely
/// with zoom to maintain a constant physical size.
///
/// Active by default. Toggle via [enabled]. Dots for `handwriting` origin
/// are suppressed by default (they're the majority of nodes and would clutter
/// the canvas). Set [showHandwriting] to true to show them.
class ContentOriginInterceptor extends RenderInterceptor {
  /// Whether the interceptor is active.
  bool enabled = true;

  /// When true, also shows 🟢 green dots for handwritten content.
  /// Default is false — only imported (🔵) and AI (🔴) are shown.
  bool showHandwriting = false;

  /// Current zoom scale — set per frame to ensure dots maintain constant
  /// physical size regardless of canvas zoom level.
  double currentScale = 1.0;

  // Pre-allocated paints — zero allocation per frame.
  static final Paint _handwritingPaintLight = Paint()
    ..color = Color(ContentOriginColors.handwritingLight)
        .withValues(alpha: ContentOriginColors.dotOpacity)
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;

  static final Paint _handwritingPaintDark = Paint()
    ..color = Color(ContentOriginColors.handwritingDark)
        .withValues(alpha: ContentOriginColors.dotOpacity)
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;

  static final Paint _importedPaintLight = Paint()
    ..color = Color(ContentOriginColors.importedLight)
        .withValues(alpha: ContentOriginColors.dotOpacity)
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;

  static final Paint _importedPaintDark = Paint()
    ..color = Color(ContentOriginColors.importedDark)
        .withValues(alpha: ContentOriginColors.dotOpacity)
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;

  static final Paint _aiPaintLight = Paint()
    ..color = Color(ContentOriginColors.aiGeneratedLight)
        .withValues(alpha: ContentOriginColors.dotOpacity)
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;

  static final Paint _aiPaintDark = Paint()
    ..color = Color(ContentOriginColors.aiGeneratedDark)
        .withValues(alpha: ContentOriginColors.dotOpacity)
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;

  /// Whether to use dark-mode color variants.
  bool isDarkMode = false;

  @override
  void intercept(
    Canvas canvas,
    CanvasNode node,
    Rect viewport,
    RenderNext next,
  ) {
    // Render the node first (dot appears on top).
    next(canvas, node, viewport);

    if (!enabled) return;

    // Skip group nodes — only leaf content gets a dot.
    if (node is GroupNode) return;

    final origin = node.contentOrigin;

    // Skip handwriting unless explicitly showing it.
    if (origin == ContentOrigin.handwriting && !showHandwriting) return;

    // Paint the dot at the top-right of the node's world bounds.
    final bounds = node.worldBounds;
    if (!bounds.isFinite || bounds.isEmpty) return;

    // Scale-independent dot size: constant physical size regardless of zoom.
    final dotRadius = ContentOriginColors.dotRadius / currentScale;
    final offsetX = ContentOriginColors.dotOffsetX / currentScale;
    final offsetY = ContentOriginColors.dotOffsetY / currentScale;

    final center = Offset(
      bounds.right + offsetX,
      bounds.top + offsetY,
    );

    final paint = _getPaint(origin);
    canvas.drawCircle(center, dotRadius, paint);
  }

  Paint _getPaint(ContentOrigin origin) {
    switch (origin) {
      case ContentOrigin.handwriting:
        return isDarkMode ? _handwritingPaintDark : _handwritingPaintLight;
      case ContentOrigin.imported:
        return isDarkMode ? _importedPaintDark : _importedPaintLight;
      case ContentOrigin.aiGenerated:
        return isDarkMode ? _aiPaintDark : _aiPaintLight;
    }
  }
}
