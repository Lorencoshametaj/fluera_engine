import 'dart:math';
import 'package:flutter/material.dart';
import '../../tools/ruler/ruler_guide_system.dart';
import 'ruler_painter.dart';

/// 📐 Ruler chrome rendering extensions for [RulerPainter].
///
/// Contains: horizontal ruler, vertical ruler, corner box,
/// cursor indicator, cursor tooltip, bookmark marks, scale indicator.
extension RulerPainterRulers on RulerPainter {
  // ─── Horizontal Ruler ────────────────────────────────────────────────

  void drawHorizontalRuler(Canvas canvas, Size size) {
    final bgColor = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5);
    final bgColor2 = isDark ? const Color(0xFF252525) : const Color(0xFFECECEC);
    final tickColor =
        isDark ? const Color(0x99FFFFFF) : const Color(0x99000000);
    final tickMinorColor =
        isDark ? const Color(0x44FFFFFF) : const Color(0x44000000);
    final textColor =
        isDark ? const Color(0xBBFFFFFF) : const Color(0xDD000000);
    final borderColor =
        isDark ? const Color(0x33FFFFFF) : const Color(0x1A000000);
    final originColor =
        isDark ? const Color(0xFFFF6B6B) : const Color(0xFFE53935);

    final rect = Rect.fromLTWH(
      RulerPainter.rulerSize,
      0,
      size.width - RulerPainter.rulerSize,
      RulerPainter.rulerSize,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [bgColor, bgColor2],
        ).createShader(rect),
    );
    canvas.drawLine(
      Offset(RulerPainter.rulerSize, RulerPainter.rulerSize - 0.5),
      Offset(size.width, RulerPainter.rulerSize - 0.5),
      Paint()
        ..color = borderColor
        ..strokeWidth = 1
        ..isAntiAlias = true,
    );

    final step = calculateStep(zoom);
    final smallStep = step / 5;

    // Find the canvas-X range visible on the horizontal ruler strip.
    // When rotation != 0, we sample the ruler strip's left/right edges at
    // a reference screen-Y to establish a linear mapping screenX ↔ canvasX.
    // The mapping is always affine (screen→canvas is a linear transform),
    // so two samples suffice.
    final double startX;
    final double endX;
    // For rotated case: linear mapping coefficients
    double _hRulerCLeftDx = 0;
    double _hRulerDCanvasX = 1;
    final double _hRulerWidth = size.width - RulerPainter.rulerSize;
    if (rotation == 0.0) {
      startX = (-canvasOffset.dx / zoom).floorToDouble();
      endX = startX + (size.width / zoom);
    } else {
      final refY = RulerPainter.rulerSize / 2;
      final cL = screenToCanvas(Offset(RulerPainter.rulerSize, refY));
      final cR = screenToCanvas(Offset(size.width, refY));
      _hRulerCLeftDx = cL.dx;
      _hRulerDCanvasX = cR.dx - cL.dx;
      if (_hRulerDCanvasX.abs() < 0.001) {
        // Canvas X-axis is perpendicular to screen-X — can't show X ticks
        startX = 0;
        endX = -1; // skip loop
      } else {
        startX = min(cL.dx, cR.dx).floorToDouble();
        endX = max(cL.dx, cR.dx).ceilToDouble();
      }
    }
    final firstTick = (startX / smallStep).floor() * smallStep;

    final majorP =
        Paint()
          ..color = tickColor
          ..strokeWidth = 1.0
          ..isAntiAlias = true;
    final midP =
        Paint()
          ..color = tickColor
          ..strokeWidth = 0.5
          ..isAntiAlias = true;
    final minorP =
        Paint()
          ..color = tickMinorColor
          ..strokeWidth = 0.5
          ..isAntiAlias = true;

    for (double x = firstTick; x <= endX; x += smallStep) {
      // Map canvas-X → screen-X along the ruler strip.
      final double sx;
      if (rotation == 0.0) {
        sx = x * zoom + canvasOffset.dx;
      } else {
        // Linear interpolation: sx = rulerSize + (x - cL.dx) / dCanvasX * rulerWidth
        sx =
            RulerPainter.rulerSize +
            (x - _hRulerCLeftDx) / _hRulerDCanvasX * _hRulerWidth;
      }
      if (sx < RulerPainter.rulerSize || sx > size.width) continue;
      final isMajor = (x % step).abs() < 0.001;
      final isMid = !isMajor && (x % (step / 2)).abs() < 0.001;
      final isOrigin = x.abs() < 0.001;
      double tickTop;
      Paint p;
      if (isOrigin) {
        tickTop = 0;
        p =
            Paint()
              ..color = originColor
              ..strokeWidth = 2.0
              ..isAntiAlias = true;
      } else if (isMajor) {
        tickTop = RulerPainter.rulerSize * 0.3;
        p = majorP;
      } else if (isMid) {
        tickTop = RulerPainter.rulerSize * 0.55;
        p = midP;
      } else {
        tickTop = RulerPainter.rulerSize * 0.72;
        p = minorP;
      }
      canvas.drawLine(
        Offset(sx, tickTop),
        Offset(sx, RulerPainter.rulerSize - 1),
        p,
      );
      if (isMajor) {
        final tp = TextPainter(
          text: TextSpan(
            text: formatLabel(x),
            style: TextStyle(
              color: isOrigin ? originColor : textColor,
              fontSize: 9.5,
              fontWeight: isOrigin ? FontWeight.w700 : FontWeight.w500,
              letterSpacing: -0.2,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(sx - tp.width / 2, 2));
      }
    }

    if (size.width > 200) {
      final tp = TextPainter(
        text: TextSpan(
          text: guideSystem.unitSuffix,
          style: TextStyle(
            color: textColor.withValues(alpha: 0.3),
            fontSize: 7,
            fontWeight: FontWeight.w500,
            fontStyle: FontStyle.italic,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(size.width - tp.width - 4, RulerPainter.rulerSize - 11),
      );
    }
  }

  // ─── Vertical Ruler ──────────────────────────────────────────────────

  void drawVerticalRuler(Canvas canvas, Size size) {
    final bgColor = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5);
    final bgColor2 = isDark ? const Color(0xFF252525) : const Color(0xFFECECEC);
    final tickColor =
        isDark ? const Color(0x99FFFFFF) : const Color(0x99000000);
    final tickMinorColor =
        isDark ? const Color(0x44FFFFFF) : const Color(0x44000000);
    final textColor =
        isDark ? const Color(0xBBFFFFFF) : const Color(0xDD000000);
    final borderColor =
        isDark ? const Color(0x33FFFFFF) : const Color(0x1A000000);
    final originColor =
        isDark ? const Color(0xFFFF6B6B) : const Color(0xFFE53935);

    final rect = Rect.fromLTWH(
      0,
      RulerPainter.rulerSize,
      RulerPainter.rulerSize,
      size.height - RulerPainter.rulerSize,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [bgColor, bgColor2],
        ).createShader(rect),
    );
    canvas.drawLine(
      Offset(RulerPainter.rulerSize - 0.5, RulerPainter.rulerSize),
      Offset(RulerPainter.rulerSize - 0.5, size.height),
      Paint()
        ..color = borderColor
        ..strokeWidth = 1
        ..isAntiAlias = true,
    );

    final step = calculateStep(zoom);
    final smallStep = step / 5;

    // Find the canvas-Y range visible on the vertical ruler strip.
    // Same linear-mapping approach as horizontal ruler.
    final double startY;
    final double endY;
    double _vRulerCTopDy = 0;
    double _vRulerDCanvasY = 1;
    final double _vRulerHeight = size.height - RulerPainter.rulerSize;
    if (rotation == 0.0) {
      startY = (-canvasOffset.dy / zoom).floorToDouble();
      endY = startY + (size.height / zoom);
    } else {
      final refX = RulerPainter.rulerSize / 2;
      final cT = screenToCanvas(Offset(refX, RulerPainter.rulerSize));
      final cB = screenToCanvas(Offset(refX, size.height));
      _vRulerCTopDy = cT.dy;
      _vRulerDCanvasY = cB.dy - cT.dy;
      if (_vRulerDCanvasY.abs() < 0.001) {
        startY = 0;
        endY = -1; // skip loop
      } else {
        startY = min(cT.dy, cB.dy).floorToDouble();
        endY = max(cT.dy, cB.dy).ceilToDouble();
      }
    }
    final firstTick = (startY / smallStep).floor() * smallStep;

    final majorP =
        Paint()
          ..color = tickColor
          ..strokeWidth = 1.0
          ..isAntiAlias = true;
    final midP =
        Paint()
          ..color = tickColor
          ..strokeWidth = 0.5
          ..isAntiAlias = true;
    final minorP =
        Paint()
          ..color = tickMinorColor
          ..strokeWidth = 0.5
          ..isAntiAlias = true;

    for (double y = firstTick; y <= endY; y += smallStep) {
      // Map canvas-Y → screen-Y along the ruler strip.
      final double sy;
      if (rotation == 0.0) {
        sy = y * zoom + canvasOffset.dy;
      } else {
        sy =
            RulerPainter.rulerSize +
            (y - _vRulerCTopDy) / _vRulerDCanvasY * _vRulerHeight;
      }
      if (sy < RulerPainter.rulerSize || sy > size.height) continue;
      final isMajor = (y % step).abs() < 0.001;
      final isMid = !isMajor && (y % (step / 2)).abs() < 0.001;
      final isOrigin = y.abs() < 0.001;
      double tickLeft;
      Paint p;
      if (isOrigin) {
        tickLeft = 0;
        p =
            Paint()
              ..color = originColor
              ..strokeWidth = 2.0
              ..isAntiAlias = true;
      } else if (isMajor) {
        tickLeft = RulerPainter.rulerSize * 0.3;
        p = majorP;
      } else if (isMid) {
        tickLeft = RulerPainter.rulerSize * 0.55;
        p = midP;
      } else {
        tickLeft = RulerPainter.rulerSize * 0.72;
        p = minorP;
      }
      canvas.drawLine(
        Offset(tickLeft, sy),
        Offset(RulerPainter.rulerSize - 1, sy),
        p,
      );
      if (isMajor) {
        canvas.save();
        canvas.translate(12, sy);
        canvas.rotate(-pi / 2);
        final tp = TextPainter(
          text: TextSpan(
            text: formatLabel(y),
            style: TextStyle(
              color: isOrigin ? originColor : textColor,
              fontSize: 9.5,
              fontWeight: isOrigin ? FontWeight.w700 : FontWeight.w500,
              letterSpacing: -0.2,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
        canvas.restore();
      }
    }
  }

  // ─── Corner Box ──────────────────────────────────────────────────────

  void drawCornerBox(Canvas canvas, Size size) {
    final bgColor = isDark ? const Color(0xFF1A1A1A) : const Color(0xFFE8E8E8);
    final borderColor =
        isDark ? const Color(0x33FFFFFF) : const Color(0x1A000000);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, RulerPainter.rulerSize, RulerPainter.rulerSize),
      Paint()..color = bgColor,
    );
    canvas.drawLine(
      Offset(RulerPainter.rulerSize - 0.5, 0),
      Offset(RulerPainter.rulerSize - 0.5, RulerPainter.rulerSize),
      Paint()
        ..color = borderColor
        ..strokeWidth = 1,
    );
    canvas.drawLine(
      Offset(0, RulerPainter.rulerSize - 0.5),
      Offset(RulerPainter.rulerSize, RulerPainter.rulerSize - 0.5),
      Paint()
        ..color = borderColor
        ..strokeWidth = 1,
    );

    if (cursorPosition == null) {
      final tp = TextPainter(
        text: TextSpan(
          text: '${(zoom * 100).round()}%',
          style: TextStyle(
            color: isDark ? const Color(0x88FFFFFF) : const Color(0x88000000),
            fontSize: 8,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          (RulerPainter.rulerSize - tp.width) / 2,
          (RulerPainter.rulerSize - tp.height) / 2 - 5,
        ),
      );

      final hCount = guideSystem.horizontalGuides.length;
      final vCount = guideSystem.verticalGuides.length;
      if (hCount > 0 || vCount > 0) {
        final badge = TextPainter(
          text: TextSpan(
            text: 'H$hCount V$vCount',
            style: TextStyle(
              color: isDark ? const Color(0x66FFFFFF) : const Color(0x66000000),
              fontSize: 6,
              fontWeight: FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
        )..layout();
        badge.paint(
          canvas,
          Offset(
            (RulerPainter.rulerSize - badge.width) / 2,
            (RulerPainter.rulerSize - badge.height) / 2 + 6,
          ),
        );
      }
    } else {
      final c = isDark ? const Color(0x66FFFFFF) : const Color(0x66000000);
      final p =
          Paint()
            ..color = c
            ..strokeWidth = 1.0
            ..strokeCap = StrokeCap.round
            ..isAntiAlias = true;
      final cx = RulerPainter.rulerSize / 2;
      final cy = RulerPainter.rulerSize / 2;
      canvas.drawLine(Offset(cx - 5, cy), Offset(cx + 5, cy), p);
      canvas.drawLine(Offset(cx, cy - 5), Offset(cx, cy + 5), p);
    }
  }

  // ─── Cursor Indicator ────────────────────────────────────────────────

  void drawCursorIndicator(Canvas canvas, Size size) {
    if (cursorPosition == null) return;
    final ic =
        isDark
            ? Colors.redAccent.withValues(alpha: 0.8)
            : Colors.red.withValues(alpha: 0.7);
    final lp =
        Paint()
          ..color = ic
          ..strokeWidth = 1.0
          ..isAntiAlias = true;

    if (cursorPosition!.dx > RulerPainter.rulerSize) {
      canvas.drawLine(
        Offset(cursorPosition!.dx, 0),
        Offset(cursorPosition!.dx, RulerPainter.rulerSize),
        lp,
      );
      canvas.drawPath(
        Path()
          ..moveTo(cursorPosition!.dx - 3, RulerPainter.rulerSize)
          ..lineTo(cursorPosition!.dx + 3, RulerPainter.rulerSize)
          ..lineTo(cursorPosition!.dx, RulerPainter.rulerSize - 4)
          ..close(),
        Paint()..color = ic,
      );
    }
    if (cursorPosition!.dy > RulerPainter.rulerSize) {
      canvas.drawLine(
        Offset(0, cursorPosition!.dy),
        Offset(RulerPainter.rulerSize, cursorPosition!.dy),
        lp,
      );
      canvas.drawPath(
        Path()
          ..moveTo(RulerPainter.rulerSize, cursorPosition!.dy - 3)
          ..lineTo(RulerPainter.rulerSize, cursorPosition!.dy + 3)
          ..lineTo(RulerPainter.rulerSize - 4, cursorPosition!.dy)
          ..close(),
        Paint()..color = ic,
      );
    }

    final canvasPos = screenToCanvas(cursorPosition!);
    final cxUnit = guideSystem.convertToUnit(canvasPos.dx);
    final cyUnit = guideSystem.convertToUnit(canvasPos.dy);
    final coordText =
        guideSystem.currentUnit == RulerUnit.px
            ? '${cxUnit.round()}\n${cyUnit.round()}'
            : '${cxUnit.toStringAsFixed(1)}\n${cyUnit.toStringAsFixed(1)}';
    final tp = TextPainter(
      text: TextSpan(
        text: coordText,
        style: TextStyle(
          color: ic,
          fontSize: 7.5,
          fontWeight: FontWeight.w600,
          height: 1.3,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    canvas.drawRect(
      Rect.fromLTWH(0, 0, RulerPainter.rulerSize, RulerPainter.rulerSize),
      Paint()
        ..color = isDark ? const Color(0xFF1A1A1A) : const Color(0xFFE8E8E8),
    );
    tp.paint(
      canvas,
      Offset(
        (RulerPainter.rulerSize - tp.width) / 2,
        (RulerPainter.rulerSize - tp.height) / 2,
      ),
    );
  }

  // ─── Cursor Tooltip ──────────────────────────────────────────────────

  void drawCursorTooltip(Canvas canvas, Size size) {
    if (cursorPosition == null) return;
    final cx = cursorPosition!.dx;
    final cy = cursorPosition!.dy;
    if (cx <= RulerPainter.rulerSize || cy <= RulerPainter.rulerSize) return;

    final canvasPos = screenToCanvas(Offset(cx, cy));
    final cxUnit = guideSystem.convertToUnit(canvasPos.dx);
    final cyUnit = guideSystem.convertToUnit(canvasPos.dy);
    final label =
        guideSystem.currentUnit == RulerUnit.px
            ? '${cxUnit.round()}, ${cyUnit.round()}'
            : '${cxUnit.toStringAsFixed(1)}, ${cyUnit.toStringAsFixed(1)}';
    final tp = getCachedLabel(
      label,
      TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.w500,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    final pillW = tp.width + 12;
    final pillH = tp.height + 6;
    double px = cx + 12;
    double py = cy - pillH - 8;
    if (px + pillW > size.width) px = cx - pillW - 8;
    if (py < RulerPainter.rulerSize) py = cy + 12;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(px, py, pillW, pillH),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0xCC222222),
    );
    tp.paint(canvas, Offset(px + 6, py + 3));
  }

  // ─── Bookmark Marks ──────────────────────────────────────────────────

  void drawBookmarkMarks(Canvas canvas, Size size) {
    for (final bm in guideSystem.bookmarkMarks) {
      final pos = bm.position;
      final color = bm.color;
      if (bm.isHorizontal) {
        final sy = pos * zoom + canvasOffset.dy;
        if (sy < RulerPainter.rulerSize || sy > size.height) continue;
        canvas.drawPath(
          Path()
            ..moveTo(RulerPainter.rulerSize - 1, sy - 4)
            ..lineTo(RulerPainter.rulerSize + 5, sy)
            ..lineTo(RulerPainter.rulerSize - 1, sy + 4)
            ..close(),
          Paint()..color = color,
        );
      } else {
        final sx = pos * zoom + canvasOffset.dx;
        if (sx < RulerPainter.rulerSize || sx > size.width) continue;
        canvas.drawPath(
          Path()
            ..moveTo(sx - 4, RulerPainter.rulerSize - 1)
            ..lineTo(sx, RulerPainter.rulerSize + 5)
            ..lineTo(sx + 4, RulerPainter.rulerSize - 1)
            ..close(),
          Paint()..color = color,
        );
      }
    }
  }

  // ─── Scale Indicator ─────────────────────────────────────────────────

  void drawScaleIndicator(Canvas canvas, Size size) {
    final pxPerCm = 37.795275591;
    final scaledPxPerCm = pxPerCm * zoom;
    final String label;
    if (scaledPxPerCm >= 20) {
      label = '1cm = ${scaledPxPerCm.round()}px';
    } else {
      label = '1cm = ${scaledPxPerCm.toStringAsFixed(1)}px';
    }
    final style = TextStyle(
      color: isDark ? const Color(0x55FFFFFF) : const Color(0x55000000),
      fontSize: 7,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final tp = getCachedLabel(label, style);
    tp.paint(
      canvas,
      Offset(RulerPainter.rulerSize + 4, RulerPainter.rulerSize + 2),
    );
  }
}
