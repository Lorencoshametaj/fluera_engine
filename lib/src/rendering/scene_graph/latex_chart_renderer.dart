import 'package:flutter/material.dart';
import '../../core/nodes/latex_node.dart';
import '../../core/latex/latex_draw_command.dart';
import 'latex_renderer.dart';

/// 📊 LatexChartRenderer — renders chart previews for [LatexNode]s.
///
/// Extracted from [LatexRenderer] to reduce god-file complexity.
/// Handles bar, line, scatter, pie, area, stacked bar, horizontal bar,
/// radar, waterfall, and bubble chart types.
class LatexChartRenderer {
  // =========================================================================
  // 📊 Visual Chart Preview — Premium Rendering
  // =========================================================================

  /// 5 curated color palettes for charts.
  static const _palettes = <List<Color>>[
    // 0: Neon (default)
    [
      Color(0xFF7C4DFF),
      Color(0xFF00E5FF),
      Color(0xFFFF6D00),
      Color(0xFF00E676),
      Color(0xFFFFD740),
      Color(0xFFFF5252),
      Color(0xFF448AFF),
      Color(0xFFE040FB),
    ],
    // 1: Pastel
    [
      Color(0xFFA78BFA),
      Color(0xFF93C5FD),
      Color(0xFFFCA5A5),
      Color(0xFF86EFAC),
      Color(0xFFFBBF24),
      Color(0xFFF9A8D4),
      Color(0xFF67E8F9),
      Color(0xFFC4B5FD),
    ],
    // 2: Earth
    [
      Color(0xFFD97706),
      Color(0xFF059669),
      Color(0xFF92400E),
      Color(0xFF065F46),
      Color(0xFFB45309),
      Color(0xFF047857),
      Color(0xFF78350F),
      Color(0xFF064E3B),
    ],
    // 3: Ocean
    [
      Color(0xFF0EA5E9),
      Color(0xFF06B6D4),
      Color(0xFF3B82F6),
      Color(0xFF14B8A6),
      Color(0xFF6366F1),
      Color(0xFF0891B2),
      Color(0xFF2563EB),
      Color(0xFF0D9488),
    ],
    // 4: Sunset
    [
      Color(0xFFF43F5E),
      Color(0xFFF97316),
      Color(0xFFEAB308),
      Color(0xFFEC4899),
      Color(0xFFE11D48),
      Color(0xFFF59E0B),
      Color(0xFFDB2777),
      Color(0xFFD946EF),
    ],
  ];

  /// Palette names for the UI.
  static const paletteNames = ['Neon', 'Pastel', 'Earth', 'Ocean', 'Sunset'];

  /// Get the chart colors for a given palette index.
  static List<Color> _chartColors = _palettes[0];
  static List<Color> _chartColorsLight =
      _palettes[0].map((c) => c.withValues(alpha: 0.25)).toList();

  static void _applyPalette(int index) {
    final i = index.clamp(0, _palettes.length - 1);
    _chartColors = _palettes[i];
    _chartColorsLight =
        _palettes[i].map((c) => c.withValues(alpha: 0.25)).toList();
  }

  /// Chart size presets.
  static (double cw, double ch, double totalW, double totalH) _chartSize(
    String preset,
  ) {
    switch (preset) {
      case 'small':
        return (300, 195, 300 + 52 + 20, 195 + 44 + 40);
      case 'large':
        return (520, 340, 520 + 52 + 20, 340 + 44 + 40);
      default:
        return (400, 260, 400 + 52 + 20, 260 + 44 + 40);
    }
  }

  static const double _kPL = 52, _kPR = 20, _kPT = 44, _kPB = 40;
  static const double _pi = 3.14159265358979;

  static void drawChartPreview(Canvas canvas, LatexNode node) {
    final labels = node.chartLabels;
    final values = node.chartValues;
    if (labels == null || labels.isEmpty || values == null || values.isEmpty) {
      LatexRenderer.drawPlaceholder(canvas, node);
      return;
    }
    // Apply palette and size.
    _applyPalette(node.chartColorPalette);
    final (cw, ch, _, _) = _chartSize(node.chartSizePreset);
    final data = _ChartParseData(labels: labels, values: values);
    final totalW = cw + _kPL + _kPR;
    const legendH = 28.0;
    final showLegend =
        node.chartShowLegend &&
        data.values.length > 1 &&
        node.chartType != 'pie';
    final totalH = _kPT + ch + _kPB + (showLegend ? legendH : 0);
    node.cachedLayout = LatexLayoutResult(
      commands: const [],
      size: Size(totalW, totalH),
    );
    final card = Rect.fromLTWH(0, 0, totalW, totalH);
    final rrCard = RRect.fromRectAndRadius(card, const Radius.circular(12));
    // Outer shadow for floating effect.
    canvas.drawRRect(
      RRect.fromRectAndRadius(card.translate(0, 4), const Radius.circular(12)),
      Paint()
        ..color = const Color(0x30000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    // Background — use custom color or default gradient.
    if (node.chartBgColor != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(card, const Radius.circular(12)),
        Paint()..color = Color(node.chartBgColor!),
      );
    } else {
      canvas.drawRRect(
        rrCard,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xF0181820), Color(0xF0252530)],
          ).createShader(card),
      );
    }
    // Glassmorphism inner highlight (top edge).
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(1, 1, totalW - 2, totalH / 3),
        const Radius.circular(12),
      ),
      Paint()..color = const Color(0x08FFFFFF),
    );
    // Title — use chartTitle if set, else node.name, else 'Chart'.
    final tt = node.chartTitle ?? (node.name.isNotEmpty ? node.name : 'Chart');
    final tp = TextPainter(
      text: TextSpan(
        text: tt,
        style: const TextStyle(
          color: Color(0xFFF0F0FF),
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: totalW - 30);
    tp.paint(canvas, Offset((totalW - tp.width) / 2, 12));
    // Subtitle — source range label.
    if (node.sourceRangeLabel != null && node.sourceRangeLabel!.isNotEmpty) {
      final sp = TextPainter(
        text: TextSpan(
          text: node.sourceRangeLabel!,
          style: const TextStyle(
            color: Color(0x50FFFFFF),
            fontSize: 9,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.5,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      sp.paint(canvas, Offset((totalW - sp.width) / 2, 12 + tp.height + 2));
    }
    // Chart.
    final cr = Rect.fromLTWH(_kPL, _kPT, cw, ch);
    switch (node.chartType) {
      case 'bar':
        _drawBarChart(canvas, cr, data, node);
      case 'line':
        _drawLineChart(canvas, cr, data, node);
      case 'scatter':
        _drawScatterChart(canvas, cr, data, node);
      case 'pie':
        _drawPieChart(
          canvas,
          Offset(totalW / 2, _kPT + ch / 2),
          ch * 0.38,
          data,
          node,
        );
      case 'area':
        _drawAreaChart(canvas, cr, data, node);
      case 'stacked_bar':
        _drawStackedBarChart(canvas, cr, data, node);
      case 'hbar':
        _drawHBarChart(canvas, cr, data, node);
      case 'radar':
        _drawRadarChart(
          canvas,
          Offset(totalW / 2, _kPT + ch / 2),
          ch * 0.38,
          data,
          node,
        );
      case 'waterfall':
        _drawWaterfallChart(canvas, cr, data, node);
      case 'bubble':
        _drawBubbleChart(canvas, cr, data, node);
      default:
        _drawBarChart(canvas, cr, data, node);
    }
    if (showLegend) _drawLegend(canvas, card, data, node);
    // Border glow.
    canvas.drawRRect(
      rrCard,
      Paint()
        ..color = const Color(0x607C4DFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 4),
    );
    canvas.drawRRect(
      rrCard,
      Paint()
        ..color = const Color(0xFF7C4DFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    // Inner subtle top highlight for glass feel.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(1, 1, totalW - 2, 1),
        const Radius.circular(12),
      ),
      Paint()..color = const Color(0x18FFFFFF),
    );
  }

  // ── Bar ────────────────────────────────────────────────────────────────
  static void _drawBarChart(
    Canvas canvas,
    Rect a,
    _ChartParseData d,
    LatexNode node,
  ) {
    final mx = d.maxValue;
    if (mx <= 0) return;
    final _ac =
        node.chartAxisColor != null ? Color(node.chartAxisColor!) : null;
    _drawGrid(canvas, a, mx, axisColor: _ac);
    if (node.chartShowAvg) _drawAvgLine(canvas, a, d, mx);
    final gw = a.width / d.labels.length;
    final bw = (gw * 0.65) / d.values.length;
    for (int s = 0; s < d.values.length; s++) {
      final c = _chartColors[s % _chartColors.length];
      for (int i = 0; i < d.values[s].length && i < d.labels.length; i++) {
        final v = d.values[s][i];
        final bh = (v / mx) * a.height;
        final x = a.left + i * gw + (gw - bw * d.values.length) / 2 + s * bw;
        final y = a.bottom - bh;
        final br = Rect.fromLTWH(x + 1, y, bw - 2, bh);
        // Shadow behind bar.
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x + 3, y + 2, bw - 2, bh),
            const Radius.circular(3),
          ),
          Paint()
            ..color = const Color(0x20000000)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
        // Gradient bar.
        final isMax = v == mx;
        canvas.drawRRect(
          RRect.fromRectAndRadius(br, const Radius.circular(3)),
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                isMax ? c.withValues(alpha: 1.0) : c,
                c.withValues(alpha: 0.55),
              ],
            ).createShader(br),
        );
        // Max bar glow highlight.
        if (isMax && bh > 10) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(br, const Radius.circular(3)),
            Paint()
              ..color = c.withValues(alpha: 0.25)
              ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 4),
          );
        }
        // Top glow.
        if (bh > 6)
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(x + 2, y, bw - 4, 3),
              const Radius.circular(3),
            ),
            Paint()
              ..color = c.withValues(alpha: 0.45)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
          );
        // Value label.
        if (node.chartShowValues && bh > 18) {
          final seriesTotal = d.values[s].fold(0.0, (a, b) => a + b);
          final vs = _formatLabel(v, seriesTotal, node.chartValueDisplay);
          final vp = TextPainter(
            text: TextSpan(
              text: vs,
              style: const TextStyle(
                color: Color(0xDDFFFFFF),
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          vp.paint(canvas, Offset(x + (bw - vp.width) / 2, y - vp.height - 3));
        }
      }
    }
    final _ac2 =
        node.chartAxisColor != null ? Color(node.chartAxisColor!) : null;
    _drawXLabels(canvas, a, d.labels, axisColor: _ac2);
  }

  // ── Line ───────────────────────────────────────────────────────────────────────
  static void _drawLineChart(
    Canvas canvas,
    Rect a,
    _ChartParseData d,
    LatexNode node,
  ) {
    final mx = d.maxValue;
    if (mx <= 0) return;
    final _ac3 =
        node.chartAxisColor != null ? Color(node.chartAxisColor!) : null;
    _drawGrid(canvas, a, mx, axisColor: _ac3);
    if (node.chartShowAvg) _drawAvgLine(canvas, a, d, mx);
    for (int s = 0; s < d.values.length; s++) {
      final c = _chartColors[s % _chartColors.length];
      final lc = _chartColorsLight[s % _chartColorsLight.length];
      final pts = <Offset>[];
      for (int i = 0; i < d.values[s].length && i < d.labels.length; i++) {
        final v = d.values[s][i];
        final x = a.left + (i + 0.5) * (a.width / d.labels.length);
        final y = a.bottom - (v / mx) * a.height;
        pts.add(Offset(x, y));
      }
      if (pts.isEmpty) continue;

      // Build smooth Bézier line + area path.
      final linePath = _smoothPath(pts);
      final areaPath = Path()..moveTo(pts.first.dx, a.bottom);
      areaPath.lineTo(pts.first.dx, pts.first.dy);
      // Replay the smooth curve for the area path top edge.
      if (pts.length == 1) {
        areaPath.lineTo(pts.first.dx, pts.first.dy);
      } else {
        for (int i = 0; i < pts.length - 1; i++) {
          final p0 = i > 0 ? pts[i - 1] : pts[i];
          final p1 = pts[i];
          final p2 = pts[i + 1];
          final p3 = i + 2 < pts.length ? pts[i + 2] : p2;
          final cp1x = p1.dx + (p2.dx - p0.dx) / 6;
          final cp1y = p1.dy + (p2.dy - p0.dy) / 6;
          final cp2x = p2.dx - (p3.dx - p1.dx) / 6;
          final cp2y = p2.dy - (p3.dy - p1.dy) / 6;
          areaPath.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.dx, p2.dy);
        }
      }
      areaPath.lineTo(pts.last.dx, a.bottom);
      areaPath.close();

      // Area fill gradient.
      canvas.drawPath(
        areaPath,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [lc, lc.withValues(alpha: 0)],
          ).createShader(a),
      );

      // Glow + line.
      canvas.drawPath(
        linePath,
        Paint()
          ..color = c.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawPath(
        linePath,
        Paint()
          ..color = c
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );

      // Data points.
      for (int i = 0; i < pts.length; i++) {
        final p = pts[i];
        canvas.drawCircle(p, 5, Paint()..color = c);
        canvas.drawCircle(
          p,
          5,
          Paint()
            ..color = const Color(0xFF202028)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
        canvas.drawCircle(p, 2.5, Paint()..color = const Color(0xFFFFFFFF));
        // Value label.
        if (node.chartShowValues) {
          final v = d.values[s][i];
          final seriesTotal = d.values[s].fold(0.0, (a, b) => a + b);
          final vs = _formatLabel(v, seriesTotal, node.chartValueDisplay);
          final vp = TextPainter(
            text: TextSpan(
              text: vs,
              style: const TextStyle(
                color: Color(0xBBFFFFFF),
                fontSize: 8,
                fontWeight: FontWeight.w600,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          vp.paint(canvas, Offset(p.dx - vp.width / 2, p.dy - vp.height - 6));
        }
      }
    }
    _drawXLabels(
      canvas,
      a,
      d.labels,
      axisColor:
          node.chartAxisColor != null ? Color(node.chartAxisColor!) : null,
    );
  }

  /// Build a smooth Catmull-Rom-style cubic Bézier path through points.
  static Path _smoothPath(List<Offset> pts) {
    final path = Path();
    if (pts.isEmpty) return path;
    path.moveTo(pts.first.dx, pts.first.dy);
    if (pts.length == 1) return path;
    for (int i = 0; i < pts.length - 1; i++) {
      final p0 = i > 0 ? pts[i - 1] : pts[i];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = i + 2 < pts.length ? pts[i + 2] : p2;
      final cp1x = p1.dx + (p2.dx - p0.dx) / 6;
      final cp1y = p1.dy + (p2.dy - p0.dy) / 6;
      final cp2x = p2.dx - (p3.dx - p1.dx) / 6;
      final cp2y = p2.dy - (p3.dy - p1.dy) / 6;
      path.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.dx, p2.dy);
    }
    return path;
  }

  // ── Scatter ────────────────────────────────────────────────────────────
  static void _drawScatterChart(
    Canvas canvas,
    Rect a,
    _ChartParseData d,
    LatexNode node,
  ) {
    final mx = d.maxValue;
    if (mx <= 0) return;
    _drawGrid(
      canvas,
      a,
      mx,
      axisColor:
          node.chartAxisColor != null ? Color(node.chartAxisColor!) : null,
    );
    // Average line.
    if (node.chartShowAvg) _drawAvgLine(canvas, a, d, mx);
    for (int s = 0; s < d.values.length; s++) {
      final c = _chartColors[s % _chartColors.length];
      for (int i = 0; i < d.values[s].length && i < d.labels.length; i++) {
        final v = d.values[s][i];
        final x = a.left + (i + 0.5) * (a.width / d.labels.length);
        final y = a.bottom - (v / mx) * a.height;
        final o = Offset(x, y);
        canvas.drawCircle(
          o,
          10,
          Paint()
            ..color = c.withValues(alpha: 0.15)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
        canvas.drawCircle(o, 6, Paint()..color = c.withValues(alpha: 0.3));
        canvas.drawCircle(o, 4, Paint()..color = c);
        canvas.drawCircle(
          Offset(x - 1, y - 1),
          1.5,
          Paint()..color = const Color(0x80FFFFFF),
        );
        // Value label.
        if (node.chartShowValues) {
          final seriesTotal = d.values[s].fold(0.0, (a, b) => a + b);
          final vs = _formatLabel(v, seriesTotal, node.chartValueDisplay);
          final vp = TextPainter(
            text: TextSpan(
              text: vs,
              style: const TextStyle(
                color: Color(0xBBFFFFFF),
                fontSize: 8,
                fontWeight: FontWeight.w600,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          vp.paint(canvas, Offset(x - vp.width / 2, y - vp.height - 8));
        }
      }
    }
    _drawXLabels(
      canvas,
      a,
      d.labels,
      axisColor:
          node.chartAxisColor != null ? Color(node.chartAxisColor!) : null,
    );
    // Trend line (linear regression) for first series.
    if (node.chartShowTrend && d.values.isNotEmpty && d.values[0].length >= 2) {
      final sv = d.values[0];
      final n = sv.length;
      double sx = 0, sy = 0, sxy = 0, sx2 = 0;
      for (int i = 0; i < n; i++) {
        sx += i;
        sy += sv[i];
        sxy += i * sv[i];
        sx2 += i * i;
      }
      final slope = (n * sxy - sx * sy) / (n * sx2 - sx * sx);
      final intercept = (sy - slope * sx) / n;
      final x0 = a.left + 0.5 * (a.width / d.labels.length);
      final x1 = a.left + (n - 0.5) * (a.width / d.labels.length);
      final y0 = a.bottom - (intercept / mx) * a.height;
      final y1 = a.bottom - ((slope * (n - 1) + intercept) / mx) * a.height;
      canvas.drawLine(
        Offset(x0, y0.clamp(a.top, a.bottom)),
        Offset(x1, y1.clamp(a.top, a.bottom)),
        Paint()
          ..color = const Color(0x40FFFFFF)
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke,
      );
    }
  }

  // ── Pie (donut) ────────────────────────────────────────────────────────
  static void _drawPieChart(
    Canvas canvas,
    Offset ctr,
    double r,
    _ChartParseData d,
    LatexNode node,
  ) {
    if (d.values.isEmpty || d.values[0].isEmpty) return;
    final vals = d.values[0];
    final tot = vals.fold(0.0, (a, b) => a + b);
    if (tot <= 0) return;
    // Drop shadow behind donut.
    canvas.drawCircle(
      Offset(ctr.dx + 2, ctr.dy + 3),
      r + 2,
      Paint()
        ..color = const Color(0x28000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    double sa = -_pi / 2;
    for (int i = 0; i < vals.length; i++) {
      final sw = (vals[i] / tot) * 2 * _pi;
      final c = _chartColors[i % _chartColors.length];
      final ar = Rect.fromCircle(center: ctr, radius: r);
      canvas.drawArc(ar, sa, sw, true, Paint()..color = c);
      canvas.drawArc(
        Rect.fromCircle(center: ctr, radius: r * 0.7),
        sa,
        sw,
        true,
        Paint()..color = c.withValues(alpha: 0.3),
      );
      canvas.drawArc(
        ar,
        sa,
        sw,
        true,
        Paint()
          ..color = const Color(0xFF1A1A24)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
      // External label with connector.
      final ma = sa + sw / 2;
      final pct = (vals[i] / tot * 100).toStringAsFixed(0);
      final rawVal =
          vals[i] == vals[i].roundToDouble()
              ? vals[i].toInt().toString()
              : vals[i].toStringAsFixed(1);
      final catLabel = i < d.labels.length ? d.labels[i] : '';
      String lb;
      switch (node.chartValueDisplay) {
        case 'percent':
          lb = catLabel.isNotEmpty ? '$catLabel ($pct%)' : '$pct%';
        case 'value':
          lb = catLabel.isNotEmpty ? '$catLabel ($rawVal)' : rawVal;
        case 'both':
          lb =
              catLabel.isNotEmpty
                  ? '$catLabel ($rawVal · $pct%)'
                  : '$rawVal · $pct%';
        default:
          lb = catLabel.isNotEmpty ? '$catLabel ($pct%)' : '$pct%';
      }
      final ex = ctr.dx + r * _cos(ma), ey = ctr.dy + _sin(ma) * r;
      final ox = ctr.dx + (r + 18) * _cos(ma),
          oy = ctr.dy + _sin(ma) * (r + 18);
      canvas.drawLine(
        Offset(ex, ey),
        Offset(ox, oy),
        Paint()
          ..color = c.withValues(alpha: 0.6)
          ..strokeWidth = 1,
      );
      final lp = TextPainter(
        text: TextSpan(
          text: lb,
          style: TextStyle(
            color: c,
            fontSize: 9.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final isR = _cos(ma) >= 0;
      lp.paint(
        canvas,
        Offset(isR ? ox + 3 : ox - lp.width - 3, oy - lp.height / 2),
      );
      sa += sw;
    }
    // Donut hole.
    canvas.drawCircle(ctr, r * 0.35, Paint()..color = const Color(0xFF1E1E28));
    canvas.drawCircle(
      ctr,
      r * 0.35,
      Paint()
        ..color = const Color(0xFF7C4DFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  // ── Area ─────────────────────────────────────────────────────────────
  static void _drawAreaChart(
    Canvas canvas,
    Rect a,
    _ChartParseData d,
    LatexNode node,
  ) {
    final mx = d.maxValue;
    if (mx <= 0) return;
    final _ac =
        node.chartAxisColor != null ? Color(node.chartAxisColor!) : null;
    _drawGrid(canvas, a, mx, axisColor: _ac);
    if (node.chartShowAvg) _drawAvgLine(canvas, a, d, mx);

    // Draw series back-to-front so first series is on top.
    for (int s = d.values.length - 1; s >= 0; s--) {
      final c = _chartColors[s % _chartColors.length];
      final pts = <Offset>[];
      for (int i = 0; i < d.values[s].length && i < d.labels.length; i++) {
        final v = d.values[s][i];
        final x = a.left + (i + 0.5) * (a.width / d.labels.length);
        final y = a.bottom - (v / mx) * a.height;
        pts.add(Offset(x, y));
      }
      if (pts.isEmpty) continue;

      // Build area path.
      final areaPath = Path()..moveTo(pts.first.dx, a.bottom);
      areaPath.lineTo(pts.first.dx, pts.first.dy);
      if (pts.length > 1) {
        for (int i = 0; i < pts.length - 1; i++) {
          final p0 = i > 0 ? pts[i - 1] : pts[i];
          final p1 = pts[i];
          final p2 = pts[i + 1];
          final p3 = i + 2 < pts.length ? pts[i + 2] : p2;
          final cp1x = p1.dx + (p2.dx - p0.dx) / 6;
          final cp1y = p1.dy + (p2.dy - p0.dy) / 6;
          final cp2x = p2.dx - (p3.dx - p1.dx) / 6;
          final cp2y = p2.dy - (p3.dy - p1.dy) / 6;
          areaPath.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.dx, p2.dy);
        }
      }
      areaPath.lineTo(pts.last.dx, a.bottom);
      areaPath.close();

      // Fill gradient.
      canvas.drawPath(
        areaPath,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [c.withValues(alpha: 0.45), c.withValues(alpha: 0.03)],
          ).createShader(a),
      );

      // Smooth line stroke.
      final linePath = _smoothPath(pts);
      canvas.drawPath(
        linePath,
        Paint()
          ..color = c
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );

      // Glow on line.
      canvas.drawPath(
        linePath,
        Paint()
          ..color = c.withValues(alpha: 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );

      // Dots with value labels.
      for (int i = 0; i < pts.length; i++) {
        final p = pts[i];
        canvas.drawCircle(p, 3, Paint()..color = c);
        canvas.drawCircle(p, 1.5, Paint()..color = const Color(0xFFFFFFFF));
        if (node.chartShowValues) {
          final v = d.values[s][i];
          final seriesTotal = d.values[s].fold(0.0, (a, b) => a + b);
          final vs = _formatLabel(v, seriesTotal, node.chartValueDisplay);
          final vp = TextPainter(
            text: TextSpan(
              text: vs,
              style: const TextStyle(
                color: Color(0xBBFFFFFF),
                fontSize: 8,
                fontWeight: FontWeight.w600,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          vp.paint(canvas, Offset(p.dx - vp.width / 2, p.dy - vp.height - 6));
        }
      }
    }
    _drawXLabels(canvas, a, d.labels, axisColor: _ac);
  }

  // ── Stacked Bar ─────────────────────────────────────────────────────
  static void _drawStackedBarChart(
    Canvas canvas,
    Rect a,
    _ChartParseData d,
    LatexNode node,
  ) {
    if (d.values.isEmpty || d.labels.isEmpty) return;
    // Compute stacked max.
    double stackMax = 0;
    for (int i = 0; i < d.labels.length; i++) {
      double sum = 0;
      for (int s = 0; s < d.values.length; s++) {
        if (i < d.values[s].length) sum += d.values[s][i];
      }
      if (sum > stackMax) stackMax = sum;
    }
    if (stackMax <= 0) return;
    final _ac =
        node.chartAxisColor != null ? Color(node.chartAxisColor!) : null;
    _drawGrid(canvas, a, stackMax, axisColor: _ac);

    final gw = a.width / d.labels.length;
    final bw = gw * 0.6;

    for (int i = 0; i < d.labels.length; i++) {
      double base = 0;
      final x = a.left + i * gw + (gw - bw) / 2;
      for (int s = 0; s < d.values.length; s++) {
        final v = (i < d.values[s].length) ? d.values[s][i] : 0.0;
        final bh = (v / stackMax) * a.height;
        final baseY = a.bottom - (base / stackMax) * a.height;
        final topY = baseY - bh;
        final c = _chartColors[s % _chartColors.length];
        final br = Rect.fromLTWH(x, topY, bw, bh);

        // Shadow.
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x + 2, topY + 2, bw, bh),
            const Radius.circular(2),
          ),
          Paint()
            ..color = const Color(0x18000000)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
        );

        // Gradient segment.
        canvas.drawRRect(
          RRect.fromRectAndRadius(br, const Radius.circular(2)),
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [c, c.withValues(alpha: 0.6)],
            ).createShader(br),
        );

        // Separator line between segments.
        if (s > 0 && bh > 1) {
          canvas.drawLine(
            Offset(x, baseY),
            Offset(x + bw, baseY),
            Paint()
              ..color = const Color(0x40000000)
              ..strokeWidth = 0.8,
          );
        }

        // Value label inside segment.
        if (node.chartShowValues && bh > 16) {
          final stackTotal = d.values.fold(
            0.0,
            (acc, s) => acc + (i < s.length ? s[i] : 0.0),
          );
          final vs = _formatLabel(v, stackTotal, node.chartValueDisplay);
          final vp = TextPainter(
            text: TextSpan(
              text: vs,
              style: const TextStyle(
                color: Color(0xDDFFFFFF),
                fontSize: 8,
                fontWeight: FontWeight.w600,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          if (vp.width < bw - 4) {
            vp.paint(
              canvas,
              Offset(x + (bw - vp.width) / 2, topY + (bh - vp.height) / 2),
            );
          }
        }
        base += v;
      }
    }
    _drawXLabels(canvas, a, d.labels, axisColor: _ac);
  }

  // ── Horizontal Bar ──────────────────────────────────────────────────
  static void _drawHBarChart(
    Canvas canvas,
    Rect a,
    _ChartParseData d,
    LatexNode node,
  ) {
    final mx = d.maxValue;
    if (mx <= 0) return;
    final _ac =
        node.chartAxisColor != null ? Color(node.chartAxisColor!) : null;
    final baseColor = _ac ?? const Color(0xFFFFFFFF);

    // Draw horizontal axis and vertical grid.
    final ap =
        Paint()
          ..color = baseColor.withValues(alpha: 0.19)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8;
    canvas.drawLine(a.bottomLeft, a.bottomRight, ap);
    canvas.drawLine(a.bottomLeft, a.topLeft, ap);

    // Vertical grid lines.
    final gp =
        Paint()
          ..color = baseColor.withValues(alpha: 0.05)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5;
    for (int i = 1; i <= 5; i++) {
      final x = a.left + (i / 5) * a.width;
      const dotGap = 5.0;
      double dy = a.top;
      while (dy < a.bottom) {
        canvas.drawCircle(Offset(x, dy), 0.5, gp);
        dy += dotGap;
      }
      // X-axis tick label.
      final vn = mx * i / 5;
      final vs =
          vn >= 1000
              ? '${(vn / 1000).toStringAsFixed(1)}k'
              : vn == vn.roundToDouble()
              ? vn.toInt().toString()
              : vn.toStringAsFixed(1);
      final tp = TextPainter(
        text: TextSpan(
          text: vs,
          style: TextStyle(
            color: baseColor.withValues(alpha: 0.38),
            fontSize: 9,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, a.bottom + 4));
    }

    if (node.chartShowAvg) _drawAvgLine(canvas, a, d, mx);

    final gh = a.height / d.labels.length;
    final bh = (gh * 0.65) / d.values.length;

    for (int s = 0; s < d.values.length; s++) {
      final c = _chartColors[s % _chartColors.length];
      for (int i = 0; i < d.values[s].length && i < d.labels.length; i++) {
        final v = d.values[s][i];
        final barW = (v / mx) * a.width;
        final y = a.top + i * gh + (gh - bh * d.values.length) / 2 + s * bh;
        final br = Rect.fromLTWH(a.left, y + 1, barW, bh - 2);

        // Shadow.
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(a.left + 2, y + 3, barW, bh - 2),
            const Radius.circular(3),
          ),
          Paint()
            ..color = const Color(0x20000000)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );

        // Gradient bar.
        final isMax = v == mx;
        canvas.drawRRect(
          RRect.fromRectAndRadius(br, const Radius.circular(3)),
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                c.withValues(alpha: 0.6),
                isMax ? c.withValues(alpha: 1.0) : c,
              ],
            ).createShader(br),
        );

        // Right-end glow for max bar.
        if (isMax && barW > 10) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(br, const Radius.circular(3)),
            Paint()
              ..color = c.withValues(alpha: 0.25)
              ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 4),
          );
        }

        // Value label after bar.
        if (node.chartShowValues && barW > 8) {
          final seriesTotal = d.values[s].fold(0.0, (a, b) => a + b);
          final vs = _formatLabel(v, seriesTotal, node.chartValueDisplay);
          final vp = TextPainter(
            text: TextSpan(
              text: vs,
              style: const TextStyle(
                color: Color(0xDDFFFFFF),
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          vp.paint(canvas, Offset(a.left + barW + 4, y + (bh - vp.height) / 2));
        }
      }
    }

    // Y-axis category labels.
    for (int i = 0; i < d.labels.length; i++) {
      final lb =
          d.labels[i].length > 8
              ? '${d.labels[i].substring(0, 7)}…'
              : d.labels[i];
      final tp = TextPainter(
        text: TextSpan(
          text: lb,
          style: TextStyle(
            color: baseColor.withValues(alpha: 0.50),
            fontSize: 9,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(a.left - tp.width - 6, a.top + i * gh + (gh - tp.height) / 2),
      );
    }
  }

  // ── Radar / Spider ──────────────────────────────────────────────────
  static void _drawRadarChart(
    Canvas canvas,
    Offset ctr,
    double r,
    _ChartParseData d,
    LatexNode node,
  ) {
    if (d.labels.isEmpty || d.values.isEmpty) return;
    final n = d.labels.length;
    if (n < 3) return; // Need at least 3 axes.

    final mx = d.maxValue;
    if (mx <= 0) return;
    final _ac =
        node.chartAxisColor != null ? Color(node.chartAxisColor!) : null;
    final gridColor = _ac ?? const Color(0xFFFFFFFF);

    // Draw concentric polygons (grid).
    for (int ring = 1; ring <= 4; ring++) {
      final ringR = r * ring / 4;
      final path = Path();
      for (int i = 0; i <= n; i++) {
        final angle = -_pi / 2 + (i % n) * 2 * _pi / n;
        final px = ctr.dx + ringR * _cos(angle);
        final py = ctr.dy + _sin(angle) * ringR;
        if (i == 0) {
          path.moveTo(px, py);
        } else {
          path.lineTo(px, py);
        }
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..color = gridColor.withValues(alpha: ring == 4 ? 0.18 : 0.06)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );
    }

    // Draw axis spokes + labels.
    for (int i = 0; i < n; i++) {
      final angle = -_pi / 2 + i * 2 * _pi / n;
      final ex = ctr.dx + r * _cos(angle);
      final ey = ctr.dy + _sin(angle) * r;
      canvas.drawLine(
        ctr,
        Offset(ex, ey),
        Paint()
          ..color = gridColor.withValues(alpha: 0.08)
          ..strokeWidth = 0.5,
      );
      // Label.
      final lx = ctr.dx + (r + 14) * _cos(angle);
      final ly = ctr.dy + _sin(angle) * (r + 14);
      final lb =
          d.labels[i].length > 8
              ? '${d.labels[i].substring(0, 7)}…'
              : d.labels[i];
      final tp = TextPainter(
        text: TextSpan(
          text: lb,
          style: TextStyle(
            color: gridColor.withValues(alpha: 0.50),
            fontSize: 8,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(lx - tp.width / 2, ly - tp.height / 2));
    }

    // Draw data polygons for each series.
    for (int s = 0; s < d.values.length; s++) {
      final c = _chartColors[s % _chartColors.length];
      final polyPath = Path();
      final pts = <Offset>[];
      for (int i = 0; i < n; i++) {
        final v = (i < d.values[s].length) ? d.values[s][i] : 0.0;
        final frac = (v / mx).clamp(0.0, 1.0);
        final angle = -_pi / 2 + i * 2 * _pi / n;
        final px = ctr.dx + r * frac * _cos(angle);
        final py = ctr.dy + _sin(angle) * r * frac;
        pts.add(Offset(px, py));
        if (i == 0) {
          polyPath.moveTo(px, py);
        } else {
          polyPath.lineTo(px, py);
        }
      }
      polyPath.close();

      // Gradient fill.
      canvas.drawPath(
        polyPath,
        Paint()
          ..color = c.withValues(alpha: 0.15)
          ..style = PaintingStyle.fill,
      );
      // Glow fill.
      canvas.drawPath(
        polyPath,
        Paint()
          ..color = c.withValues(alpha: 0.10)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      // Stroke.
      canvas.drawPath(
        polyPath,
        Paint()
          ..color = c.withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );

      // Dots at vertices.
      for (int i = 0; i < pts.length; i++) {
        canvas.drawCircle(pts[i], 3.5, Paint()..color = c);
        canvas.drawCircle(
          pts[i],
          1.5,
          Paint()..color = const Color(0xFFFFFFFF),
        );
        // Value labels.
        if (node.chartShowValues) {
          final v = (i < d.values[s].length) ? d.values[s][i] : 0.0;
          final seriesTotal = d.values[s].fold(0.0, (a, b) => a + b);
          final vs = _formatLabel(v, seriesTotal, node.chartValueDisplay);
          final vp = TextPainter(
            text: TextSpan(
              text: vs,
              style: const TextStyle(
                color: Color(0xBBFFFFFF),
                fontSize: 7,
                fontWeight: FontWeight.w600,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          final angle = -_pi / 2 + i * 2 * _pi / n;
          final lx = pts[i].dx + 6 * _cos(angle);
          final ly = pts[i].dy + 6 * _sin(angle);
          vp.paint(canvas, Offset(lx - vp.width / 2, ly - vp.height / 2));
        }
      }
    }
  }

  // ── Waterfall ───────────────────────────────────────────────────────
  static void _drawWaterfallChart(
    Canvas canvas,
    Rect a,
    _ChartParseData d,
    LatexNode node,
  ) {
    if (d.values.isEmpty || d.values[0].isEmpty) return;
    final vals = d.values[0]; // Single series only.
    final _ac =
        node.chartAxisColor != null ? Color(node.chartAxisColor!) : null;

    // Compute cumulative values to determine range.
    final cumulative = <double>[0];
    for (final v in vals) {
      cumulative.add(cumulative.last + v);
    }
    final maxCum = cumulative.reduce((a, b) => a > b ? a : b);
    final minCum = cumulative.reduce((a, b) => a < b ? a : b);
    final range = maxCum - minCum;
    if (range <= 0) return;

    // Draw grid using absolute range.
    _drawGrid(canvas, a, maxCum - (minCum < 0 ? minCum : 0), axisColor: _ac);

    final gw = a.width / vals.length;
    final bw = gw * 0.6;
    final baseline = minCum < 0 ? -minCum : 0.0;

    const posColor = Color(0xFF4CAF50);
    const negColor = Color(0xFFF44336);
    final totalColor = _chartColors[0];

    for (int i = 0; i < vals.length; i++) {
      final v = vals[i];
      final startCum = cumulative[i] + baseline;
      final endCum = cumulative[i + 1] + baseline;
      final x = a.left + i * gw + (gw - bw) / 2;

      final isLast = i == vals.length - 1;
      final c = isLast ? totalColor : (v >= 0 ? posColor : negColor);

      final topY =
          a.bottom -
          (startCum > endCum ? startCum : endCum) /
              (range + baseline) *
              a.height;
      final botY =
          a.bottom -
          (startCum < endCum ? startCum : endCum) /
              (range + baseline) *
              a.height;
      final bh = botY - topY;
      final br = Rect.fromLTWH(x, topY, bw, bh < 2 ? 2 : bh);

      // Shadow.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x + 2, topY + 2, bw, bh < 2 ? 2 : bh),
          const Radius.circular(3),
        ),
        Paint()
          ..color = const Color(0x20000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );

      // Bar with gradient.
      canvas.drawRRect(
        RRect.fromRectAndRadius(br, const Radius.circular(3)),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [c, c.withValues(alpha: 0.55)],
          ).createShader(br),
      );

      // Connector line to next bar.
      if (i < vals.length - 1) {
        final connY = a.bottom - endCum / (range + baseline) * a.height;
        final nextX = a.left + (i + 1) * gw + (gw - bw) / 2;
        canvas.drawLine(
          Offset(x + bw, connY),
          Offset(nextX, connY),
          Paint()
            ..color = const Color(0x30FFFFFF)
            ..strokeWidth = 1
            ..strokeCap = StrokeCap.round,
        );
      }

      // Value label.
      if (node.chartShowValues && bh > 14) {
        final sign = v >= 0 ? '+' : '';
        final raw =
            v == v.roundToDouble()
                ? v.toInt().toString()
                : v.toStringAsFixed(1);
        final vs = '$sign$raw';
        final vp = TextPainter(
          text: TextSpan(
            text: vs,
            style: const TextStyle(
              color: Color(0xDDFFFFFF),
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        vp.paint(canvas, Offset(x + (bw - vp.width) / 2, topY - vp.height - 3));
      }
    }
    _drawXLabels(canvas, a, d.labels, axisColor: _ac);
  }

  // ── Bubble ──────────────────────────────────────────────────────────
  static void _drawBubbleChart(
    Canvas canvas,
    Rect a,
    _ChartParseData d,
    LatexNode node,
  ) {
    // Bubble needs at least 2 series: Y-values and bubble sizes.
    // Series 0 = Y, Series 1 = bubble radius (optional, defaults to equal).
    if (d.values.isEmpty) return;
    final yVals = d.values[0];
    final sizeVals = d.values.length > 1 ? d.values[1] : null;
    final mx = d.maxValue;
    if (mx <= 0) return;

    final _ac =
        node.chartAxisColor != null ? Color(node.chartAxisColor!) : null;
    _drawGrid(canvas, a, mx, axisColor: _ac);

    // Max bubble size for normalization.
    double maxSize = 1;
    if (sizeVals != null) {
      for (final s in sizeVals) {
        if (s > maxSize) maxSize = s;
      }
    }

    for (int i = 0; i < yVals.length && i < d.labels.length; i++) {
      final v = yVals[i];
      final x = a.left + (i + 0.5) * (a.width / d.labels.length);
      final y = a.bottom - (v / mx) * a.height;
      final s = sizeVals != null && i < sizeVals.length ? sizeVals[i] : 1.0;
      final radius = 6 + (s / maxSize) * 20; // 6..26 px radius.
      final c = _chartColors[i % _chartColors.length];

      // Outer glow.
      canvas.drawCircle(
        Offset(x, y),
        radius + 4,
        Paint()
          ..color = c.withValues(alpha: 0.12)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );

      // Bubble fill.
      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.3, -0.3),
            radius: 1.0,
            colors: [c.withValues(alpha: 0.8), c.withValues(alpha: 0.3)],
          ).createShader(Rect.fromCircle(center: Offset(x, y), radius: radius)),
      );

      // Bubble stroke.
      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()
          ..color = c.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );

      // Specular highlight.
      canvas.drawCircle(
        Offset(x - radius * 0.2, y - radius * 0.2),
        radius * 0.35,
        Paint()..color = const Color(0x30FFFFFF),
      );

      // Value label.
      if (node.chartShowValues) {
        final seriesTotal = yVals.fold(0.0, (a, b) => a + b);
        final vs = _formatLabel(v, seriesTotal, node.chartValueDisplay);
        final vp = TextPainter(
          text: TextSpan(
            text: vs,
            style: const TextStyle(
              color: Color(0xDDFFFFFF),
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        vp.paint(canvas, Offset(x - vp.width / 2, y - vp.height / 2));
      }
    }
    _drawXLabels(canvas, a, d.labels, axisColor: _ac);
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  /// Format a value label based on the display mode.
  static String _formatLabel(double v, double total, String mode) {
    final raw =
        v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
    if (mode == 'percent') {
      final pct = total > 0 ? (v / total * 100).toStringAsFixed(0) : '0';
      return '$pct%';
    } else if (mode == 'both') {
      final pct = total > 0 ? (v / total * 100).toStringAsFixed(0) : '0';
      return '$raw · $pct%';
    }
    return raw; // 'value' or default
  }

  /// Draw a dashed horizontal line at the average value.
  static void _drawAvgLine(
    Canvas canvas,
    Rect a,
    _ChartParseData d,
    double mx,
  ) {
    // Compute overall average.
    double sum = 0;
    int count = 0;
    for (final s in d.values) {
      for (final v in s) {
        sum += v;
        count++;
      }
    }
    if (count == 0) return;
    final avg = sum / count;
    final y = a.bottom - (avg / mx) * a.height;
    if (y < a.top || y > a.bottom) return;

    // Dashed line.
    final dashPaint =
        Paint()
          ..color = const Color(0x50FFD740)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
    const dashW = 6.0, gapW = 4.0;
    double dx = a.left;
    while (dx < a.right) {
      final end = (dx + dashW).clamp(a.left, a.right);
      canvas.drawLine(Offset(dx, y), Offset(end, y), dashPaint);
      dx += dashW + gapW;
    }

    // Label.
    final avgStr =
        avg == avg.roundToDouble()
            ? avg.toInt().toString()
            : avg.toStringAsFixed(1);
    final tp = TextPainter(
      text: TextSpan(
        text: 'avg $avgStr',
        style: const TextStyle(
          color: Color(0x80FFD740),
          fontSize: 8,
          fontWeight: FontWeight.w600,
          fontStyle: FontStyle.italic,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(a.right - tp.width - 4, y - tp.height - 2));
  }

  static void _drawGrid(Canvas canvas, Rect a, double mx, {Color? axisColor}) {
    final baseColor = axisColor ?? const Color(0xFFFFFFFF);
    final ap =
        Paint()
          ..color = baseColor.withValues(alpha: 0.19)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8;
    canvas.drawLine(a.bottomLeft, a.bottomRight, ap);
    canvas.drawLine(a.bottomLeft, a.topLeft, ap);
    final gp =
        Paint()
          ..color = baseColor.withValues(alpha: 0.05)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5;
    for (int i = 1; i <= 5; i++) {
      final y = a.bottom - (i / 5) * a.height;
      // Dotted grid line.
      const dotGap = 5.0;
      double dx = a.left;
      while (dx < a.right) {
        canvas.drawCircle(Offset(dx, y), 0.5, gp);
        dx += dotGap;
      }
      // Tick mark on Y-axis.
      canvas.drawLine(Offset(a.left - 3, y), Offset(a.left, y), ap);
      final vn = mx * i / 5;
      final vs =
          vn >= 1000
              ? '${(vn / 1000).toStringAsFixed(1)}k'
              : vn == vn.roundToDouble()
              ? vn.toInt().toString()
              : vn.toStringAsFixed(1);
      final tp = TextPainter(
        text: TextSpan(
          text: vs,
          style: TextStyle(
            color: baseColor.withValues(alpha: 0.38),
            fontSize: 9,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(a.left - tp.width - 6, y - tp.height / 2));
    }
  }

  static void _drawXLabels(
    Canvas canvas,
    Rect a,
    List<String> labels, {
    Color? axisColor,
  }) {
    final baseColor = axisColor ?? const Color(0xFFFFFFFF);
    final cw = a.width / labels.length;
    for (int i = 0; i < labels.length; i++) {
      final lb =
          labels[i].length > 8 ? '${labels[i].substring(0, 7)}…' : labels[i];
      final tp = TextPainter(
        text: TextSpan(
          text: lb,
          style: TextStyle(
            color: baseColor.withValues(alpha: 0.44),
            fontSize: 9,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(a.left + i * cw + (cw - tp.width) / 2, a.bottom + 6),
      );
    }
  }

  static void _drawLegend(
    Canvas canvas,
    Rect card,
    _ChartParseData d,
    LatexNode node,
  ) {
    final y = card.bottom - 22;
    double x = card.left + 20;
    final names = node.chartSeriesNames;
    for (int s = 0; s < d.values.length; s++) {
      final c = _chartColors[s % _chartColors.length];
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, 10, 10),
          const Radius.circular(2),
        ),
        Paint()..color = c,
      );
      x += 14;
      final seriesName =
          (names != null && s < names.length) ? names[s] : 'Series ${s + 1}';
      final tp = TextPainter(
        text: TextSpan(
          text: seriesName,
          style: const TextStyle(
            color: Color(0x90FFFFFF),
            fontSize: 9,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x, y - 1));
      x += tp.width + 16;
    }
  }

  static double _cos(double r) {
    double x = r % (2 * _pi);
    if (x < 0) x += 2 * _pi;
    double res = 1.0, t = 1.0;
    for (int i = 1; i <= 12; i++) {
      t *= -x * x / ((2 * i - 1) * (2 * i));
      res += t;
    }
    return res;
  }

  static double _sin(double r) => _cos(r - _pi / 2);
}

class _ChartParseData {
  final List<String> labels;
  final List<List<double>> values;
  const _ChartParseData({required this.labels, required this.values});
  double get maxValue {
    double m = 0;
    for (final s in values) for (final v in s) if (v > m) m = v;
    return m;
  }
}
