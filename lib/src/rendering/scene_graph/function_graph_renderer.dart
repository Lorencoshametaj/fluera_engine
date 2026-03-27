import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../core/nodes/function_graph_node.dart';
import '../../canvas/widgets/graph_painter.dart';

/// Static renderer for [FunctionGraphNode] on the Canvas.
///
/// Uses the node's cached sample points (computed lazily) and delegates
/// to [FunctionGraphPainter] for drawing. Also renders a label badge
/// and optional resize handles.
class FunctionGraphRenderer {
  /// Draw a [FunctionGraphNode] onto the [canvas].
  ///
  /// [isDark] controls the graph background/text color scheme.
  static void drawFunctionGraphNode(
    Canvas canvas,
    FunctionGraphNode node, {
    bool isDark = true,
  }) {
    final size = Size(node.graphWidth, node.graphHeight);

    // Ensure points are sampled (uses hash-based caching)
    node.ensureSampled();

    final fns = node.functions;
    if (fns.isEmpty) return;

    // ── A2: Drop shadow for depth ──
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-2, -1, size.width + 4, size.height + 6),
        const Radius.circular(14),
      ),
      Paint()
        ..color = const Color(0x28000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // ── P3: Frosted background for contrast ──
    final bgRadius = 12.0;
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(-4, -4, size.width + 8, size.height + 8),
      Radius.circular(bgRadius),
    );
    // Gradient fill
    canvas.drawRRect(
      bgRect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, -4),
          Offset(0, size.height + 4),
          isDark
              ? [const Color(0xF0141422), const Color(0xF01A1A2E)]
              : [const Color(0xF0F8F8FF), const Color(0xF0FFFFFF)],
        ),
    );
    // Subtle border
    canvas.drawRRect(
      bgRect,
      Paint()
        ..color = isDark
            ? const Color(0x20FFFFFF)
            : const Color(0x18000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // Use FunctionGraphPainter with cached data
    final painter = FunctionGraphPainter(
      points: node.cachedPoints,
      derivativePoints: node.cachedDerivativePoints,
      xMin: node.xMin,
      xMax: node.xMax,
      yMin: node.yMin,
      yMax: node.yMax,
      curveColor: node.curveColor,
      showDerivative: node.showDerivative,
      showMinorGrid: false,
      showRoots: node.showRoots,
      showCriticalPoints: node.showCriticalPoints,
      showAsymptotes: node.showAsymptotes,
      showArea: node.showArea,
      showMonotonicity: false,
      isDark: isDark,
      showLegend: node.showLegend,
      extraPoints: node.cachedExtraPoints,
      extraColors: FunctionGraphNode.extraPalette
          .take(node.cachedExtraPoints.length)
          .toList(),
      functionLabels: fns,
      intersectionPoints: node.cachedIntersections,
    );

    // ── Clip graph content to background bounds ──
    canvas.save();
    canvas.clipRRect(bgRect);

    painter.paint(canvas, size);

    canvas.restore();

    // ── Badge label above graph ──
    _drawBadgeLabel(canvas, node, size, isDark);

    // ── T1: Trace cursor crosshair ──
    if (node.traceX != null) {
      _drawTraceCrosshair(canvas, node, size, isDark);
    }
  }

  /// Draw a crosshair at the trace position with glow, snap markers, and labels.
  static void _drawTraceCrosshair(
    Canvas canvas,
    FunctionGraphNode node,
    Size graphSize,
    bool isDark,
  ) {
    final x = node.traceX!;
    final y = node.evaluateAt(x);
    if (y == null || y.isNaN || y.isInfinite) return;

    // Convert graph coords to pixel coords
    final px = (x - node.xMin) / (node.xMax - node.xMin) * graphSize.width;
    final py = (1.0 - (y - node.yMin) / (node.yMax - node.yMin)) * graphSize.height;

    // Clamp to visible area
    if (px < 0 || px > graphSize.width || py < 0 || py > graphSize.height) return;

    // ── Snap detection ──
    String? snapLabel;
    final snapThresholdGraph = (node.xMax - node.xMin) * 0.02; // 2% of viewport

    // Check root snap (y ≈ 0)
    if (y.abs() < (node.yMax - node.yMin) * 0.015) {
      snapLabel = 'Zero';
    }

    // Check critical points (f'(x) ≈ 0) via numerical derivative
    if (snapLabel == null) {
      const h = 0.001;
      final yPlus = node.evaluateAt(x + h);
      final yMinus = node.evaluateAt(x - h);
      if (yPlus != null && yMinus != null && yPlus.isFinite && yMinus.isFinite) {
        final derivative = (yPlus - yMinus) / (2 * h);
        if (derivative.abs() < 0.05) {
          // Check second derivative for min/max
          final y2 = node.evaluateAt(x + 2 * h);
          final y0 = node.evaluateAt(x - 2 * h);
          if (y2 != null && y0 != null && y2.isFinite && y0.isFinite) {
            final secondDeriv = (y2 - 2 * y + y0) / (4 * h * h);
            snapLabel = secondDeriv > 0 ? 'Min' : 'Max';
          }
        }
      }
    }

    final isSnapped = snapLabel != null;

    // ── Crosshair lines ──
    final linePaint = Paint()
      ..color = isDark
          ? const Color(0x66FFFFFF)
          : const Color(0x44000000)
      ..strokeWidth = isSnapped ? 1.5 : 1.0;

    // Dashed crosshair for premium feel
    canvas.drawLine(Offset(px, 0), Offset(px, graphSize.height), linePaint);
    canvas.drawLine(Offset(0, py), Offset(graphSize.width, py), linePaint);

    // ── Glow ring ──
    canvas.drawCircle(
      Offset(px, py),
      isSnapped ? 14.0 : 10.0,
      Paint()
        ..color = node.curveColor.withValues(alpha: isSnapped ? 0.25 : 0.12)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 6),
    );

    // ── Dot at intersection ──
    canvas.drawCircle(
      Offset(px, py),
      isSnapped ? 7.0 : 5.0,
      Paint()..color = node.curveColor,
    );
    canvas.drawCircle(
      Offset(px, py),
      isSnapped ? 7.0 : 5.0,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
    if (isSnapped) {
      // Outer ring for snapped points
      canvas.drawCircle(
        Offset(px, py),
        10.0,
        Paint()
          ..color = node.curveColor.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    // ── Coordinate label ──
    final label = isSnapped
        ? '$snapLabel: (${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)})'
        : '(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)})';
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: isDark ? Colors.white : Colors.black,
          fontSize: isSnapped ? 11.0 : 10.0,
          fontWeight: isSnapped ? FontWeight.w700 : FontWeight.w600,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // Background pill for label
    final lx = px + 10 + tp.width + 12 > graphSize.width ? px - tp.width - 18 : px + 10;
    final ly = py - 26 < 0 ? py + 12 : py - 26;
    final labelRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(lx - 6, ly - 2, tp.width + 12, tp.height + 4),
      const Radius.circular(4),
    );
    canvas.drawRRect(
      labelRect,
      Paint()..color = isDark ? const Color(0xDD1E1E2E) : const Color(0xDDFFFFFF),
    );
    canvas.drawRRect(
      labelRect,
      Paint()
        ..color = isSnapped ? node.curveColor.withValues(alpha: 0.6) : (isDark ? const Color(0x33FFFFFF) : const Color(0x33000000))
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSnapped ? 1.5 : 0.5,
    );
    tp.paint(canvas, Offset(lx, ly));
  }

  /// Draw a label badge above the graph showing the function expression.
  static void _drawBadgeLabel(
    Canvas canvas,
    FunctionGraphNode node,
    Size graphSize,
    bool isDark,
  ) {
    final fns = node.functions;
    if (fns.isEmpty) return;

    // Build label text
    final label = fns.length == 1
        ? 'f(x) = ${fns.first}'
        : '${fns.length} funzioni';

    // SL3: Append parameter values
    final paramSuffix = node.parameters.isNotEmpty
        ? '  ${node.parameters.entries.map((e) => '${e.key}=${e.value.toStringAsFixed(1)}').join(' ')}'
        : '';

    // Limit label length
    final fullLabel = '$label$paramSuffix';
    final displayLabel =
        fullLabel.length > 50 ? '${fullLabel.substring(0, 47)}...' : fullLabel;

    final scale = (graphSize.width / 400.0).clamp(0.5, 2.0);
    final fontSize = 11.0 * scale;
    final padH = 8.0 * scale;
    final padV = 3.0 * scale;
    final radius = 6.0 * scale;

    final tp = TextPainter(
      text: TextSpan(
        text: displayLabel,
        style: TextStyle(
          color: isDark ? const Color(0xDDFFFFFF) : const Color(0xDD000000),
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: graphSize.width * 0.8);

    final badgeW = tp.width + padH * 2;
    final badgeH = tp.height + padV * 2;
    final badgeY = -(badgeH + 4 * scale);

    // Badge background
    final badgeRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, badgeY, badgeW, badgeH),
      Radius.circular(radius),
    );
    canvas.drawRRect(
      badgeRect,
      Paint()
        ..color = isDark
            ? const Color(0xDD1E1E2E)
            : const Color(0xDDFFFFFF),
    );

    // Border
    canvas.drawRRect(
      badgeRect,
      Paint()
        ..color = isDark
            ? const Color(0x33FFFFFF)
            : const Color(0x33000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );

    // Icon
    final iconSize = 12.0 * scale;
    final iconPaint = Paint()
      ..color = node.curveColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * scale
      ..strokeCap = StrokeCap.round;

    // Simple chart icon: 3 ascending dots connected by lines
    final iconX = padH * 0.5;
    final iconCY = badgeY + badgeH / 2;
    canvas.drawLine(
      Offset(iconX, iconCY + iconSize * 0.2),
      Offset(iconX + iconSize * 0.4, iconCY - iconSize * 0.1),
      iconPaint,
    );
    canvas.drawLine(
      Offset(iconX + iconSize * 0.4, iconCY - iconSize * 0.1),
      Offset(iconX + iconSize * 0.8, iconCY - iconSize * 0.3),
      iconPaint,
    );

    // Text
    tp.paint(canvas, Offset(padH, badgeY + padV));
  }
}
