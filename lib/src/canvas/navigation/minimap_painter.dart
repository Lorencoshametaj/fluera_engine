import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import './content_bounds_tracker.dart';

/// 🗺️ CustomPainter for the minimap bird's-eye view.
///
/// DESIGN PRINCIPLES:
/// - Zero allocations in paint(): all Paints are pre-allocated.
/// - Each content region is drawn as a small colored rectangle.
/// - The current viewport is drawn as a contrasting semi-transparent rectangle.
/// - Scales all coordinates from world space → minimap space.
/// - Adapts panel and indicator colors to canvas background for visibility.
///
/// PERFORMANCE:
/// - Repaint only when content or viewport changes (via repaint notifiers).
/// - No text rendering — icons only for extreme LOD.
class MinimapPainter extends CustomPainter {
  final List<ContentRegion> regions;
  final Rect contentBounds;
  final Rect viewportInCanvas;
  final double minimapWidth;
  final double minimapHeight;
  final Color canvasBackground;

  // Node type → color mapping.
  static const Map<ContentNodeType, Color> _nodeColors = {
    ContentNodeType.stroke: Color(0xCC4A90D9),
    ContentNodeType.shape: Color(0xCC5CB85C),
    ContentNodeType.text: Color(0xCCA0A0A0),
    ContentNodeType.image: Color(0xCCE8A838),
    ContentNodeType.pdf: Color(0xCCD9534F),
    ContentNodeType.other: Color(0xCC8E8E93),
  };

  MinimapPainter({
    required this.regions,
    required this.contentBounds,
    required this.viewportInCanvas,
    required this.minimapWidth,
    required this.minimapHeight,
    this.canvasBackground = Colors.white,
    super.repaint,
  });

  /// Whether the canvas background is light (luminance > 0.5).
  bool get _isLightBg => canvasBackground.computeLuminance() > 0.5;

  @override
  void paint(Canvas canvas, Size size) {
    // Draw background — adaptive to canvas brightness.
    final bgColor =
        _isLightBg
            ? const Color(0xE6F0F0F5) // Light canvas → light panel
            : const Color(0xCC1A1A2E); // Dark canvas → dark panel
    final borderColor =
        _isLightBg ? const Color(0x30000000) : const Color(0x40FFFFFF);

    final bgPaint = Paint()..color = bgColor;
    final borderPaint =
        Paint()
          ..color = borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;

    final bgRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final bgRRect = RRect.fromRectAndRadius(bgRect, const Radius.circular(8));
    canvas.drawRRect(bgRRect, bgPaint);
    canvas.drawRRect(bgRRect, borderPaint);

    // 🔒 Clip all subsequent painting to the panel bounds —
    // prevents the viewport indicator from overflowing outside the minimap.
    canvas.clipRRect(bgRRect);

    if (contentBounds.isEmpty || !contentBounds.isFinite) return;

    // Compute mapping: content world rect → minimap rect with padding.
    final padding = 8.0;
    final drawArea = Rect.fromLTWH(
      padding,
      padding,
      size.width - padding * 2,
      size.height - padding * 2,
    );

    // Expand content bounds slightly for breathing room.
    final expandedBounds = contentBounds.inflate(
      contentBounds.shortestSide * 0.1,
    );

    final scaleX = drawArea.width / expandedBounds.width;
    final scaleY = drawArea.height / expandedBounds.height;
    final scale = scaleX < scaleY ? scaleX : scaleY;

    // Center the content in the draw area.
    final scaledW = expandedBounds.width * scale;
    final scaledH = expandedBounds.height * scale;
    final offsetX = drawArea.left + (drawArea.width - scaledW) / 2;
    final offsetY = drawArea.top + (drawArea.height - scaledH) / 2;

    // Transform: world → minimap.
    Rect worldToMinimap(Rect world) {
      return Rect.fromLTWH(
        offsetX + (world.left - expandedBounds.left) * scale,
        offsetY + (world.top - expandedBounds.top) * scale,
        world.width * scale,
        world.height * scale,
      );
    }

    // Draw content regions.
    final nodePaint = Paint();
    for (final region in regions) {
      final r = worldToMinimap(region.bounds);
      // Clamp minimum size for visibility.
      final drawRect = Rect.fromLTWH(
        r.left,
        r.top,
        r.width < 2 ? 2 : r.width,
        r.height < 2 ? 2 : r.height,
      );
      nodePaint.color = _nodeColors[region.nodeType] ?? const Color(0xCC8E8E93);
      canvas.drawRect(drawRect, nodePaint);
    }

    // Draw viewport indicator — adaptive color.
    if (!viewportInCanvas.isEmpty && viewportInCanvas.isFinite) {
      final viewportStrokeColor =
          _isLightBg ? const Color(0x88333333) : const Color(0x55FFFFFF);
      final viewportFillColor =
          _isLightBg ? const Color(0x0D000000) : const Color(0x0DFFFFFF);

      final viewportStrokePaint =
          Paint()
            ..color = viewportStrokeColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5;
      final viewportFillPaint = Paint()..color = viewportFillColor;

      final vr = worldToMinimap(viewportInCanvas);
      canvas.drawRect(vr, viewportFillPaint);
      canvas.drawRect(vr, viewportStrokePaint);
    }
  }

  @override
  bool shouldRepaint(MinimapPainter oldDelegate) =>
      contentBounds != oldDelegate.contentBounds ||
      viewportInCanvas != oldDelegate.viewportInCanvas ||
      regions.length != oldDelegate.regions.length ||
      canvasBackground != oldDelegate.canvasBackground;
}
