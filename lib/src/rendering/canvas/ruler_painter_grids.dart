import 'dart:math';
import 'package:flutter/material.dart';
import '../../tools/ruler/ruler_guide_system.dart';
import 'ruler_painter.dart';

/// 📐 Grid rendering extensions for [RulerPainter].
///
/// Contains: standard grid, pixel grid, isometric grid, perspective grid,
/// radial grid, and golden spiral overlay.
extension RulerPainterGrids on RulerPainter {
  // ─── Standard Grid ───────────────────────────────────────────────────

  void drawGrid(Canvas canvas, Size size) {
    final step = guideSystem.gridStep(zoom);
    final opacity = guideSystem.gridOpacity.clamp(0.0, 1.0);
    final gridColor = (isDark
            ? const Color(0x0DFFFFFF)
            : const Color(0x0D000000))
        .withAlpha(((isDark ? 0x0D : 0x0D) * opacity).round());

    // 🎯 Grid LOD: at very low zoom, show only major gridlines (every 10th)
    final effectiveStep = zoom < 0.3 ? step * 10 : step;

    final startX =
        (-canvasOffset.dx / zoom / effectiveStep).floor() * effectiveStep;
    final endX = startX + (size.width / zoom) + effectiveStep;
    final startY =
        (-canvasOffset.dy / zoom / effectiveStep).floor() * effectiveStep;
    final endY = startY + (size.height / zoom) + effectiveStep;

    switch (guideSystem.gridStyle) {
      case GridStyle.lines:
        final gridPaint =
            Paint()
              ..color = gridColor
              ..strokeWidth = 0.5
              ..isAntiAlias = true;
        for (double x = startX; x <= endX; x += effectiveStep) {
          final sx = x * zoom + canvasOffset.dx;
          if (sx >= 0 && sx <= size.width) {
            canvas.drawLine(Offset(sx, 0), Offset(sx, size.height), gridPaint);
          }
        }
        for (double y = startY; y <= endY; y += effectiveStep) {
          final sy = y * zoom + canvasOffset.dy;
          if (sy >= 0 && sy <= size.height) {
            canvas.drawLine(Offset(0, sy), Offset(size.width, sy), gridPaint);
          }
        }
        break;

      case GridStyle.dots:
        final opacity = guideSystem.gridOpacity.clamp(0.0, 1.0);
        final dotPaint =
            Paint()
              ..color = (isDark
                      ? const Color(0x33FFFFFF)
                      : const Color(0x22000000))
                  .withAlpha(((isDark ? 0x33 : 0x22) * opacity).round())
              ..isAntiAlias = true;
        final dotR = (0.8 + zoom * 0.2).clamp(0.5, 2.0);
        for (double x = startX; x <= endX; x += effectiveStep) {
          final sx = x * zoom + canvasOffset.dx;
          if (sx < 0 || sx > size.width) continue;
          for (double y = startY; y <= endY; y += effectiveStep) {
            final sy = y * zoom + canvasOffset.dy;
            if (sy < 0 || sy > size.height) continue;
            canvas.drawCircle(Offset(sx, sy), dotR, dotPaint);
          }
        }
        break;

      case GridStyle.crosses:
        final opacity = guideSystem.gridOpacity.clamp(0.0, 1.0);
        final crossPaint =
            Paint()
              ..color = (isDark
                      ? const Color(0x22FFFFFF)
                      : const Color(0x18000000))
                  .withAlpha(((isDark ? 0x22 : 0x18) * opacity).round())
              ..strokeWidth = 0.5
              ..isAntiAlias = true;
        final armLen = (2.0 + zoom * 1.0).clamp(1.5, 4.0);
        for (double x = startX; x <= endX; x += effectiveStep) {
          final sx = x * zoom + canvasOffset.dx;
          if (sx < 0 || sx > size.width) continue;
          for (double y = startY; y <= endY; y += effectiveStep) {
            final sy = y * zoom + canvasOffset.dy;
            if (sy < 0 || sy > size.height) continue;
            canvas.drawLine(
              Offset(sx - armLen, sy),
              Offset(sx + armLen, sy),
              crossPaint,
            );
            canvas.drawLine(
              Offset(sx, sy - armLen),
              Offset(sx, sy + armLen),
              crossPaint,
            );
          }
        }
        break;
    }
  }

  // ─── Pixel Grid (high zoom) ──────────────────────────────────────────

  void drawPixelGrid(Canvas canvas, Size size) {
    if (zoom <= 8.0) return;

    final opacity = guideSystem.gridOpacity.clamp(0.0, 1.0);
    final pixelColor = (isDark
            ? const Color(0x08FFFFFF)
            : const Color(0x08000000))
        .withAlpha(((0x08) * opacity).round());
    final pixelPaint =
        Paint()
          ..color = pixelColor
          ..strokeWidth = 0.5
          ..isAntiAlias = false; // crisp pixel lines

    const pxStep = 1.0;
    final startX = (-canvasOffset.dx / zoom / pxStep).floor() * pxStep;
    final endX = startX + (size.width / zoom) + pxStep;
    final startY = (-canvasOffset.dy / zoom / pxStep).floor() * pxStep;
    final endY = startY + (size.height / zoom) + pxStep;

    final maxLines = 2000;
    final hCount = ((endX - startX) / pxStep).round();
    final vCount = ((endY - startY) / pxStep).round();
    if (hCount + vCount > maxLines) return;

    for (double x = startX; x <= endX; x += pxStep) {
      final sx = x * zoom + canvasOffset.dx;
      if (sx >= 0 && sx <= size.width) {
        canvas.drawLine(Offset(sx, 0), Offset(sx, size.height), pixelPaint);
      }
    }
    for (double y = startY; y <= endY; y += pxStep) {
      final sy = y * zoom + canvasOffset.dy;
      if (sy >= 0 && sy <= size.height) {
        canvas.drawLine(Offset(0, sy), Offset(size.width, sy), pixelPaint);
      }
    }
  }

  // ─── Isometric Grid ──────────────────────────────────────────────────

  void drawIsometricGrid(Canvas canvas, Size size) {
    final opacity = guideSystem.gridOpacity.clamp(0.0, 1.0);
    final isoColor = (isDark
            ? const Color(0x1A42A5F5)
            : const Color(0x151565C0))
        .withAlpha(((isDark ? 0x1A : 0x15) * opacity).round());
    final isoPaint =
        Paint()
          ..color = isoColor
          ..strokeWidth = 0.5
          ..isAntiAlias = true;

    final step = guideSystem.gridStep(zoom);
    final angleDeg = guideSystem.isometricAngle;
    final angleRad = angleDeg * pi / 180;
    final tanA = tan(angleRad);

    final diag = size.width + size.height;
    final hStep = step * zoom;

    // Vertical lines (0°)
    final startX = (-canvasOffset.dx / zoom / step).floor() * step;
    final endX = startX + (size.width / zoom) + step;
    for (double x = startX; x <= endX; x += step) {
      final sx = x * zoom + canvasOffset.dx;
      if (sx >= 0 && sx <= size.width) {
        canvas.drawLine(Offset(sx, 0), Offset(sx, size.height), isoPaint);
      }
    }

    // Lines at +angle (going up-right)
    final spacing = hStep / cos(angleRad);
    final numLines = (diag / spacing).ceil() + 1;
    for (int i = -numLines; i <= numLines; i++) {
      final base = i * hStep;
      final x1 = 0.0;
      final y1 = base + canvasOffset.dy.remainder(hStep);
      final x2 = size.width;
      final y2 = y1 - size.width * tanA;
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), isoPaint);
    }

    // Lines at -angle (going down-right)
    for (int i = -numLines; i <= numLines; i++) {
      final base = i * hStep;
      final x1 = 0.0;
      final y1 = base + canvasOffset.dy.remainder(hStep);
      final x2 = size.width;
      final y2 = y1 + size.width * tanA;
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), isoPaint);
    }
  }

  // ─── Perspective Grid ────────────────────────────────────────────────

  void drawPerspectiveGrid(Canvas canvas, Size size) {
    final opacity = guideSystem.gridOpacity.clamp(0.0, 1.0);
    final perspColor = (isDark
            ? const Color(0x1AFFA726)
            : const Color(0x15E65100))
        .withAlpha(((isDark ? 0x1A : 0x15) * opacity).round());
    final perspPaint =
        Paint()
          ..color = perspColor
          ..strokeWidth = 0.5
          ..isAntiAlias = true;

    final vpPaint =
        Paint()
          ..color = isDark ? const Color(0x55FFA726) : const Color(0x55E65100)
          ..strokeWidth = 1.5
          ..isAntiAlias = true;

    final type = guideSystem.perspectiveType;
    final density = guideSystem.perspectiveLineDensity;

    Offset toScreen(Offset canvasP) => Offset(
      canvasP.dx * zoom + canvasOffset.dx,
      canvasP.dy * zoom + canvasOffset.dy,
    );

    final svp1 = toScreen(guideSystem.vp1);

    void drawVPMarker(Offset screenVP) {
      canvas.drawCircle(screenVP, 5, vpPaint);
      canvas.drawLine(
        screenVP + const Offset(-8, 0),
        screenVP + const Offset(8, 0),
        vpPaint,
      );
      canvas.drawLine(
        screenVP + const Offset(0, -8),
        screenVP + const Offset(0, 8),
        vpPaint,
      );
    }

    void drawRadiatingLines(Offset screenVP) {
      for (int i = 0; i <= density; i++) {
        final t = i / density;
        final topX = size.width * t;
        canvas.drawLine(screenVP, Offset(topX, 0), perspPaint);
        canvas.drawLine(screenVP, Offset(topX, size.height), perspPaint);
        final leftY = size.height * t;
        canvas.drawLine(screenVP, Offset(0, leftY), perspPaint);
        canvas.drawLine(screenVP, Offset(size.width, leftY), perspPaint);
      }
    }

    if (type == PerspectiveType.onePoint) {
      drawRadiatingLines(svp1);
      drawVPMarker(svp1);
      canvas.drawLine(
        Offset(0, svp1.dy),
        Offset(size.width, svp1.dy),
        vpPaint..strokeWidth = 0.8,
      );
    } else if (type == PerspectiveType.twoPoint) {
      final svp2 = toScreen(guideSystem.vp2);
      drawRadiatingLines(svp1);
      drawRadiatingLines(svp2);
      canvas.drawLine(
        Offset(0, (svp1.dy + svp2.dy) / 2),
        Offset(size.width, (svp1.dy + svp2.dy) / 2),
        vpPaint..strokeWidth = 0.8,
      );
      drawVPMarker(svp1);
      drawVPMarker(svp2);
    } else if (type == PerspectiveType.threePoint) {
      final svp2 = toScreen(guideSystem.vp2);
      final svp3 = toScreen(guideSystem.vp3);
      drawRadiatingLines(svp1);
      drawRadiatingLines(svp2);
      drawRadiatingLines(svp3);
      canvas.drawLine(
        Offset(0, (svp1.dy + svp2.dy) / 2),
        Offset(size.width, (svp1.dy + svp2.dy) / 2),
        vpPaint..strokeWidth = 0.8,
      );
      drawVPMarker(svp1);
      drawVPMarker(svp2);
      drawVPMarker(svp3);
    }
  }

  // ─── Radial Grid ─────────────────────────────────────────────────────

  void drawRadialGrid(Canvas canvas, Size size) {
    final center = Offset(
      guideSystem.radialCenter.dx * zoom + canvasOffset.dx,
      guideSystem.radialCenter.dy * zoom + canvasOffset.dy,
    );

    final opacity = guideSystem.gridOpacity.clamp(0.0, 1.0);
    final radialColor = (isDark
            ? const Color(0x1A69F0AE)
            : const Color(0x152E7D32))
        .withAlpha(((isDark ? 0x1A : 0x15) * opacity).round());
    final radialPaint =
        Paint()
          ..color = radialColor
          ..strokeWidth = 0.5
          ..style = PaintingStyle.stroke
          ..isAntiAlias = true;

    final centerPaint =
        Paint()
          ..color = isDark ? const Color(0x5569F0AE) : const Color(0x552E7D32)
          ..strokeWidth = 1.5
          ..isAntiAlias = true;

    final maxR = guideSystem.radialMaxRadius * zoom;
    final rings = guideSystem.radialRings;
    final divisions = guideSystem.radialDivisions;

    for (int i = 1; i <= rings; i++) {
      final r = maxR * i / rings;
      canvas.drawCircle(center, r, radialPaint);
    }

    for (int i = 0; i < divisions; i++) {
      final angle = 2 * pi * i / divisions;
      final endX = center.dx + cos(angle) * maxR;
      final endY = center.dy + sin(angle) * maxR;
      canvas.drawLine(center, Offset(endX, endY), radialPaint);
    }

    canvas.drawCircle(center, 3, centerPaint);
    canvas.drawLine(
      center + const Offset(-6, 0),
      center + const Offset(6, 0),
      centerPaint,
    );
    canvas.drawLine(
      center + const Offset(0, -6),
      center + const Offset(0, 6),
      centerPaint,
    );
  }

  // ─── Golden Spiral ───────────────────────────────────────────────────

  void drawGoldenSpiral(Canvas canvas, Size size) {
    final opacity = guideSystem.gridOpacity.clamp(0.0, 1.0);
    final spiralColor = (isDark
            ? const Color(0x55FFD700)
            : const Color(0x44B8860B))
        .withAlpha(((isDark ? 0x55 : 0x44) * opacity).round());
    final spiralPaint =
        Paint()
          ..color = spiralColor
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke
          ..isAntiAlias = true;

    const phi = 1.618033988749895;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final baseSize = size.shortestSide * 0.35;

    double w = baseSize;
    double x = cx - baseSize / 2;
    double y = cy - baseSize / 2;

    for (int i = 0; i < 8; i++) {
      final rect = Rect.fromLTWH(x, y, w, w);
      final startAngle = (i % 4) * pi / 2;
      canvas.drawArc(rect, startAngle, pi / 2, false, spiralPaint);

      final nextW = w / phi;
      switch (i % 4) {
        case 0:
          x += w - nextW;
          break;
        case 1:
          y += w - nextW;
          break;
        case 2:
          x -= (w - nextW);
          x += nextW - nextW;
          break;
        case 3:
          y -= (w - nextW);
          y += nextW - nextW;
          break;
      }
      w = nextW;
    }

    final rectColor =
        isDark ? const Color(0x33FFD700) : const Color(0x22B8860B);
    final rectPaint =
        Paint()
          ..color = rectColor
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke
          ..isAntiAlias = true;
    final goldenW = baseSize;
    final goldenH = baseSize / phi;
    canvas.drawRect(
      Rect.fromCenter(center: Offset(cx, cy), width: goldenW, height: goldenH),
      rectPaint,
    );
  }
}
