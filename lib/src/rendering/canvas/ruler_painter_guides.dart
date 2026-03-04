import 'dart:math';
import 'package:flutter/material.dart';
import '../../tools/ruler/ruler_guide_system.dart';
import 'ruler_painter.dart';

/// 📐 Guide rendering extensions for [RulerPainter].
///
/// Contains: guide lines, guide labels, distance labels, intersection markers,
/// glow effects, ghost snap, hover tooltip, diamond markers, lock icons.
extension RulerPainterGuides on RulerPainter {
  // ─── Guide Dispatch ──────────────────────────────────────────────────

  void drawGuides(Canvas canvas, Size size) {
    for (int i = 0; i < guideSystem.horizontalGuides.length; i++) {
      final gy = guideSystem.horizontalGuides[i];
      final sy = guideToScreenY(gy);
      if (sy < 0 || sy > size.height) continue;

      final isActive = activeGuideIsHorizontal == true && activeGuideIndex == i;
      final isLocked = guideSystem.isLocked(true, i);
      final isSelected = guideSystem.isSelected(true, i);
      final color = guideSystem.getGuideColor(true, i);
      final glow = guideSystem.snapGlowAlpha(true, i);
      _drawSingleGuide(
        canvas,
        size,
        sy,
        true,
        isActive,
        isLocked,
        isSelected,
        gy,
        color,
        glow,
      );
    }

    for (int i = 0; i < guideSystem.verticalGuides.length; i++) {
      final gx = guideSystem.verticalGuides[i];
      final sx = guideToScreenX(gx);
      if (sx < 0 || sx > size.width) continue;

      final isActive =
          activeGuideIsHorizontal == false && activeGuideIndex == i;
      final isLocked = guideSystem.isLocked(false, i);
      final isSelected = guideSystem.isSelected(false, i);
      final color = guideSystem.getGuideColor(false, i);
      final glow = guideSystem.snapGlowAlpha(false, i);
      _drawSingleGuide(
        canvas,
        size,
        sx,
        false,
        isActive,
        isLocked,
        isSelected,
        gx,
        color,
        glow,
      );
    }

    // Frame-scoped guides
    _drawFrameGuides(canvas, size);

    // Constraint guides
    _drawConstraintGuides(canvas, size);

    if (activeGuideIndex != null && activeGuideIsHorizontal != null) {
      drawDragCrosshairs(canvas, size);
    }
  }

  // ─── Frame-Scoped Guide Rendering ───────────────────────────────────

  void _drawFrameGuides(Canvas canvas, Size size) {
    final opacity = guideSystem.guideOpacity;
    for (final fg in guideSystem.frameGuides) {
      final screenPos =
          fg.isHorizontal
              ? guideToScreenY(fg.position)
              : guideToScreenX(fg.position);

      // Cull off-screen
      if (fg.isHorizontal && (screenPos < 0 || screenPos > size.height)) {
        continue;
      }
      if (!fg.isHorizontal && (screenPos < 0 || screenPos > size.width)) {
        continue;
      }

      final baseColor =
          fg.color ??
          (isDark ? const Color(0xFF81D4FA) : const Color(0xFF0277BD));
      final alpha = (fg.locked ? 0.25 : 0.55) * opacity;
      final paint =
          Paint()
            ..color = baseColor.withValues(alpha: alpha)
            ..strokeWidth = 1.0
            ..isAntiAlias = true;

      // Draw dotted line to distinguish from global guides
      const dashLen = 4.0;
      const gapLen = 3.0;
      if (fg.isHorizontal) {
        double x = 0;
        while (x < size.width) {
          final end = (x + dashLen).clamp(0.0, size.width);
          canvas.drawLine(Offset(x, screenPos), Offset(end, screenPos), paint);
          x += dashLen + gapLen;
        }
      } else {
        double y = 0;
        while (y < size.height) {
          final end = (y + dashLen).clamp(0.0, size.height);
          canvas.drawLine(Offset(screenPos, y), Offset(screenPos, end), paint);
          y += dashLen + gapLen;
        }
      }

      // Label badge (frameId or custom label)
      final labelText = fg.label ?? fg.frameId ?? '';
      if (labelText.isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(
            text: labelText,
            style: TextStyle(
              color: baseColor.withValues(alpha: 0.9 * opacity),
              fontSize: 7,
              fontWeight: FontWeight.w500,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final bgColor = baseColor.withValues(alpha: 0.12 * opacity);
        if (fg.isHorizontal) {
          final bgRect = RRect.fromRectAndRadius(
            Rect.fromLTWH(
              4,
              screenPos - tp.height - 3,
              tp.width + 6,
              tp.height + 2,
            ),
            const Radius.circular(2),
          );
          canvas.drawRRect(bgRect, Paint()..color = bgColor);
          tp.paint(canvas, Offset(7, screenPos - tp.height - 2));
        } else {
          final bgRect = RRect.fromRectAndRadius(
            Rect.fromLTWH(screenPos + 3, 4, tp.width + 6, tp.height + 2),
            const Radius.circular(2),
          );
          canvas.drawRRect(bgRect, Paint()..color = bgColor);
          tp.paint(canvas, Offset(screenPos + 6, 5));
        }
      }
    }
  }

  // ─── Constraint Guide Rendering ─────────────────────────────────────

  void _drawConstraintGuides(Canvas canvas, Size size) {
    final opacity = guideSystem.guideOpacity;
    final resolved = guideSystem.resolvedConstraintPositions;

    for (final cg in guideSystem.constraintGuides) {
      final pos = resolved[cg.id];
      if (pos == null) continue;

      final screenPos =
          cg.isHorizontal ? guideToScreenY(pos) : guideToScreenX(pos);

      // Cull off-screen
      if (cg.isHorizontal && (screenPos < 0 || screenPos > size.height)) {
        continue;
      }
      if (!cg.isHorizontal && (screenPos < 0 || screenPos > size.width)) {
        continue;
      }

      final baseColor =
          cg.color ??
          (isDark ? const Color(0xFFFFAB40) : const Color(0xFFE65100));
      final alpha = 0.5 * opacity;
      final paint =
          Paint()
            ..color = baseColor.withValues(alpha: alpha)
            ..strokeWidth = 1.0
            ..isAntiAlias = true;

      // Double-line style for constraint guides
      const offset2 = 1.5; // pixel offset for second line
      if (cg.isHorizontal) {
        canvas.drawLine(
          Offset(0, screenPos - offset2),
          Offset(size.width, screenPos - offset2),
          paint,
        );
        canvas.drawLine(
          Offset(0, screenPos + offset2),
          Offset(size.width, screenPos + offset2),
          paint,
        );
      } else {
        canvas.drawLine(
          Offset(screenPos - offset2, 0),
          Offset(screenPos - offset2, size.height),
          paint,
        );
        canvas.drawLine(
          Offset(screenPos + offset2, 0),
          Offset(screenPos + offset2, size.height),
          paint,
        );
      }

      // Edge type + label badge
      final edgeName = cg.edge.name;
      final labelText = cg.label != null ? '${cg.label} ($edgeName)' : edgeName;
      final tp = TextPainter(
        text: TextSpan(
          text: labelText,
          style: TextStyle(
            color: baseColor.withValues(alpha: 0.85 * opacity),
            fontSize: 7,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final bgColor = baseColor.withValues(alpha: 0.12 * opacity);
      if (cg.isHorizontal) {
        final bgRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            size.width - tp.width - 10,
            screenPos - tp.height - 3,
            tp.width + 6,
            tp.height + 2,
          ),
          const Radius.circular(2),
        );
        canvas.drawRRect(bgRect, Paint()..color = bgColor);
        tp.paint(
          canvas,
          Offset(size.width - tp.width - 7, screenPos - tp.height - 2),
        );
      } else {
        final bgRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            screenPos + 3,
            size.height - tp.height - 10,
            tp.width + 6,
            tp.height + 2,
          ),
          const Radius.circular(2),
        );
        canvas.drawRRect(bgRect, Paint()..color = bgColor);
        tp.paint(canvas, Offset(screenPos + 6, size.height - tp.height - 9));
      }
    }
  }

  void _drawSingleGuide(
    Canvas canvas,
    Size size,
    double screenPos,
    bool isH,
    bool isActive,
    bool isLocked,
    bool isSelected,
    double canvasPos,
    Color baseColor,
    double glowAlpha,
  ) {
    Color themedColor = baseColor;
    if (baseColor == const Color(0xFF00BCD4) ||
        baseColor == const Color(0xFFE040FB)) {
      themedColor =
          isDark
              ? baseColor.withValues(alpha: 1.0)
              : HSLColor.fromColor(baseColor).withLightness(0.35).toColor();
    }
    final alpha = isActive ? 0.9 : (isLocked ? 0.3 : 0.5);
    final effectiveColor = themedColor.withValues(alpha: alpha);

    final isSymAxis =
        guideSystem.symmetryEnabled &&
        guideSystem.symmetryAxisIndex != null &&
        guideSystem.symmetryAxisIsHorizontal == isH &&
        guideSystem.symmetryAxisIndex ==
            (isH
                ? guideSystem.horizontalGuides.indexOf(canvasPos)
                : guideSystem.verticalGuides.indexOf(canvasPos));

    if (isSelected) {
      final selPaint =
          Paint()
            ..color = baseColor.withValues(alpha: 0.15)
            ..strokeWidth = 6.0
            ..isAntiAlias = true;
      if (isH) {
        canvas.drawLine(
          Offset(0, screenPos),
          Offset(size.width, screenPos),
          selPaint,
        );
      } else {
        canvas.drawLine(
          Offset(screenPos, 0),
          Offset(screenPos, size.height),
          selPaint,
        );
      }
    }

    if (glowAlpha > 0) {
      final glowP =
          Paint()
            ..color = baseColor.withValues(alpha: glowAlpha * 0.4)
            ..strokeWidth = 4.0
            ..isAntiAlias = true
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      if (isH) {
        canvas.drawLine(
          Offset(0, screenPos),
          Offset(size.width, screenPos),
          glowP,
        );
      } else {
        canvas.drawLine(
          Offset(screenPos, 0),
          Offset(screenPos, size.height),
          glowP,
        );
      }
    }

    final lineColor =
        isSymAxis
            ? (isDark ? const Color(0xCC7C4DFF) : const Color(0xBB651FFF))
            : effectiveColor;
    final gp =
        Paint()
          ..color = lineColor
          ..strokeWidth = isActive ? 1.5 : (isSymAxis ? 2.0 : 1.0)
          ..isAntiAlias = true;

    if (isH) {
      if (zoom < 0.5) {
        canvas.drawLine(
          Offset(0, screenPos),
          Offset(size.width, screenPos),
          gp,
        );
      } else {
        drawDashedLine(
          canvas,
          Offset(0, screenPos),
          Offset(size.width, screenPos),
          gp,
        );
      }
    } else {
      if (zoom < 0.5) {
        canvas.drawLine(
          Offset(screenPos, 0),
          Offset(screenPos, size.height),
          gp,
        );
      } else {
        drawDashedLine(
          canvas,
          Offset(screenPos, 0),
          Offset(screenPos, size.height),
          gp,
        );
      }
    }

    if (guideSystem.rulersVisible) {
      _drawDiamondMarker(canvas, screenPos, isH, effectiveColor);
      final unitVal = guideSystem.convertToUnit(canvasPos);
      final label =
          guideSystem.currentUnit == RulerUnit.px
              ? unitVal.round().toString()
              : unitVal.toStringAsFixed(1);
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: baseColor.withValues(alpha: 0.85),
            fontSize: 8,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final labelBg = baseColor.withValues(alpha: isDark ? 0.2 : 0.12);
      if (isH) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(1, screenPos - 7, RulerPainter.rulerSize - 2, 14),
            const Radius.circular(2),
          ),
          Paint()..color = labelBg,
        );
        tp.paint(
          canvas,
          Offset(
            (RulerPainter.rulerSize - tp.width) / 2,
            screenPos - tp.height / 2,
          ),
        );
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              screenPos - tp.width / 2 - 3,
              1,
              tp.width + 6,
              RulerPainter.rulerSize - 2,
            ),
            const Radius.circular(2),
          ),
          Paint()..color = labelBg,
        );
        tp.paint(
          canvas,
          Offset(
            screenPos - tp.width / 2,
            (RulerPainter.rulerSize - tp.height) / 2,
          ),
        );
      }
      if (isLocked) _drawLockIcon(canvas, screenPos, isH, baseColor);
    }
  }

  void _drawDiamondMarker(Canvas canvas, double pos, bool isH, Color color) {
    const s = 4.0;
    final path = Path();
    if (isH) {
      path
        ..moveTo(RulerPainter.rulerSize, pos - s)
        ..lineTo(RulerPainter.rulerSize + s, pos)
        ..lineTo(RulerPainter.rulerSize, pos + s)
        ..lineTo(RulerPainter.rulerSize - s, pos)
        ..close();
    } else {
      path
        ..moveTo(pos - s, RulerPainter.rulerSize)
        ..lineTo(pos, RulerPainter.rulerSize - s)
        ..lineTo(pos + s, RulerPainter.rulerSize)
        ..lineTo(pos, RulerPainter.rulerSize + s)
        ..close();
    }
    canvas.drawPath(path, Paint()..color = color);
  }

  void _drawLockIcon(Canvas canvas, double pos, bool isH, Color color) {
    final p =
        Paint()
          ..color = color.withValues(alpha: 0.5)
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke
          ..isAntiAlias = true;
    if (isH) {
      final x = RulerPainter.rulerSize / 2;
      final y = pos + 10;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, y + 1.5), width: 5, height: 4),
          const Radius.circular(0.5),
        ),
        p,
      );
      canvas.drawArc(
        Rect.fromCenter(center: Offset(x, y - 1), width: 4, height: 4),
        pi,
        pi,
        false,
        p,
      );
    } else {
      final x = pos + 12;
      final y = RulerPainter.rulerSize / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x + 1.5, y), width: 5, height: 4),
          const Radius.circular(0.5),
        ),
        p,
      );
      canvas.drawArc(
        Rect.fromCenter(center: Offset(x - 1, y), width: 4, height: 4),
        pi,
        pi,
        false,
        p,
      );
    }
  }

  void drawDragCrosshairs(Canvas canvas, Size size) {
    if (activeGuideIndex == null || activeGuideIsHorizontal == null) return;
    final isH = activeGuideIsHorizontal!;
    final guides =
        isH ? guideSystem.horizontalGuides : guideSystem.verticalGuides;
    if (activeGuideIndex! >= guides.length) return;
    final val = guides[activeGuideIndex!];
    final color = guideSystem.getGuideColor(isH, activeGuideIndex!);
    final cp =
        Paint()
          ..color = color.withValues(alpha: 0.08)
          ..strokeWidth = 0.5
          ..isAntiAlias = true;
    if (isH) {
      final sy = guideToScreenY(val);
      canvas.drawLine(Offset(0, sy), Offset(size.width, sy), cp);
    } else {
      final sx = guideToScreenX(val);
      canvas.drawLine(Offset(sx, 0), Offset(sx, size.height), cp);
    }
  }

  // ─── Guide Distance Labels ─────────────────────────────────────────

  void drawGuideDistanceLabels(Canvas canvas, Size size) {
    final gs = guideSystem;
    final labelColor =
        isDark ? const Color(0x99FFFFFF) : const Color(0x99000000);
    final bgColor = isDark ? const Color(0xCC1A1A1A) : const Color(0xCCF5F5F5);

    if (gs.horizontalGuides.length >= 2) {
      final sorted = List<double>.from(gs.horizontalGuides)..sort();
      for (int i = 0; i < sorted.length - 1; i++) {
        final y1 = guideToScreenY(sorted[i]);
        final y2 = guideToScreenY(sorted[i + 1]);
        if (y1 < 0 || y2 > size.height) continue;
        final mid = (y1 + y2) / 2;
        final dist = (sorted[i + 1] - sorted[i]).abs();
        final label = formatLabel(dist);
        final tp = getCachedLabel(
          label,
          TextStyle(
            color: labelColor,
            fontSize: 8,
            fontWeight: FontWeight.w500,
          ),
        );
        final bgRect = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(RulerPainter.rulerSize + 8 + tp.width / 2, mid),
            width: tp.width + 6,
            height: tp.height + 4,
          ),
          const Radius.circular(3),
        );
        canvas.drawRRect(bgRect, Paint()..color = bgColor);
        tp.paint(
          canvas,
          Offset(RulerPainter.rulerSize + 8, mid - tp.height / 2),
        );
      }
    }

    if (gs.verticalGuides.length >= 2) {
      final sorted = List<double>.from(gs.verticalGuides)..sort();
      for (int i = 0; i < sorted.length - 1; i++) {
        final x1 = guideToScreenX(sorted[i]);
        final x2 = guideToScreenX(sorted[i + 1]);
        if (x1 < 0 || x2 > size.width) continue;
        final mid = (x1 + x2) / 2;
        final dist = (sorted[i + 1] - sorted[i]).abs();
        final label = formatLabel(dist);
        final tp = getCachedLabel(
          label,
          TextStyle(
            color: labelColor,
            fontSize: 8,
            fontWeight: FontWeight.w500,
          ),
        );
        final bgRect = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(mid, RulerPainter.rulerSize + 8 + tp.height / 2),
            width: tp.width + 6,
            height: tp.height + 4,
          ),
          const Radius.circular(3),
        );
        canvas.drawRRect(bgRect, Paint()..color = bgColor);
        tp.paint(
          canvas,
          Offset(mid - tp.width / 2, RulerPainter.rulerSize + 8),
        );
      }
    }
  }

  void drawGuideLabels(Canvas canvas, Size size) {
    final textColor =
        isDark ? const Color(0xBBFFFFFF) : const Color(0xDD000000);
    final bgColor = isDark ? const Color(0xCC1E1E1E) : const Color(0xCCF5F5F5);

    void labelAt(Offset pos, String text) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: textColor,
            fontSize: 8.5,
            fontWeight: FontWeight.w500,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final bgRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(pos.dx - 2, pos.dy - 1, tp.width + 4, tp.height + 2),
        const Radius.circular(2),
      );
      canvas.drawRRect(bgRect, Paint()..color = bgColor);
      tp.paint(canvas, pos);
    }

    for (int i = 0; i < guideSystem.horizontalGuides.length; i++) {
      final y = guideSystem.horizontalGuides[i];
      final sy = guideToScreenY(y);
      if (sy < 0 || sy > size.height) continue;
      labelAt(
        Offset(RulerPainter.rulerSize + 4, sy + 2),
        formatLabelWithOrigin(y, false),
      );
      final annot = guideSystem.getGuideLabel(true, i);
      if (annot != null) {
        final annotTp = getCachedLabel(
          annot,
          TextStyle(
            color: Colors.white,
            fontSize: 8,
            fontWeight: FontWeight.w600,
          ),
        );
        final ax = RulerPainter.rulerSize + 8;
        final ay = sy - annotTp.height - 6;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              ax - 3,
              ay - 1,
              annotTp.width + 6,
              annotTp.height + 2,
            ),
            const Radius.circular(3),
          ),
          Paint()
            ..color = guideSystem.getGuideColor(true, i).withValues(alpha: 0.8),
        );
        annotTp.paint(canvas, Offset(ax, ay));
      }
    }

    for (int i = 0; i < guideSystem.verticalGuides.length; i++) {
      final x = guideSystem.verticalGuides[i];
      final sx = guideToScreenX(x);
      if (sx < 0 || sx > size.width) continue;
      labelAt(
        Offset(sx + 2, RulerPainter.rulerSize + 2),
        formatLabelWithOrigin(x, true),
      );
      final annot = guideSystem.getGuideLabel(false, i);
      if (annot != null) {
        final annotTp = getCachedLabel(
          annot,
          TextStyle(
            color: Colors.white,
            fontSize: 8,
            fontWeight: FontWeight.w600,
          ),
        );
        final ax = sx + 8;
        final ay = RulerPainter.rulerSize + 4;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              ax - 3,
              ay - 1,
              annotTp.width + 6,
              annotTp.height + 2,
            ),
            const Radius.circular(3),
          ),
          Paint()
            ..color = guideSystem
                .getGuideColor(false, i)
                .withValues(alpha: 0.8),
        );
        annotTp.paint(canvas, Offset(ax, ay));
      }
    }
  }

  void drawIntersectionMarkers(Canvas canvas, Size size) {
    if (guideSystem.horizontalGuides.isEmpty ||
        guideSystem.verticalGuides.isEmpty)
      return;
    final markerColor =
        isDark ? const Color(0x44FFFFFF) : const Color(0x33000000);
    final markerPaint =
        Paint()
          ..color = markerColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..isAntiAlias = true;
    final fillPaint =
        Paint()
          ..color = markerColor.withValues(alpha: 0.1)
          ..isAntiAlias = true;
    const markerR = 3.5;
    for (final gy in guideSystem.horizontalGuides) {
      final sy = guideToScreenY(gy);
      if (sy < 0 || sy > size.height) continue;
      for (final gx in guideSystem.verticalGuides) {
        final sx = guideToScreenX(gx);
        if (sx < 0 || sx > size.width) continue;
        final center = Offset(sx, sy);
        canvas.drawCircle(center, markerR, fillPaint);
        canvas.drawCircle(center, markerR, markerPaint);
      }
    }
  }

  void drawNewGuideGlow(Canvas canvas, Size size) {
    final t = guideSystem.lastGuideCreatedAt;
    if (t == null) return;
    final elapsed = DateTime.now().difference(t).inMilliseconds;
    if (elapsed > 800) return;
    double alpha;
    if (elapsed < 200) {
      alpha = elapsed / 200.0;
    } else if (elapsed < 500) {
      alpha = 1.0;
    } else {
      alpha = 1.0 - (elapsed - 500) / 300.0;
    }
    alpha = alpha.clamp(0.0, 1.0);
    final gp =
        Paint()
          ..color = Color.fromARGB((alpha * 80).round(), 255, 152, 0)
          ..strokeWidth = 6.0
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    if (guideSystem.horizontalGuides.isNotEmpty) {
      final sy = guideToScreenY(guideSystem.horizontalGuides.last);
      if (sy > 0 && sy < size.height) {
        canvas.drawLine(
          Offset(RulerPainter.rulerSize, sy),
          Offset(size.width, sy),
          gp,
        );
      }
    }
    if (guideSystem.verticalGuides.isNotEmpty) {
      final sx = guideToScreenX(guideSystem.verticalGuides.last);
      if (sx > 0 && sx < size.width) {
        canvas.drawLine(
          Offset(sx, RulerPainter.rulerSize),
          Offset(sx, size.height),
          gp,
        );
      }
    }
  }

  void drawGuideHoverTooltip(Canvas canvas, Size size) {
    if (cursorPosition == null) return;
    final cx = cursorPosition!.dx;
    final cy = cursorPosition!.dy;
    const threshold = 12.0;
    for (int i = 0; i < guideSystem.horizontalGuides.length; i++) {
      final sy = guideToScreenY(guideSystem.horizontalGuides[i]);
      if ((cy - sy).abs() < threshold && cx > RulerPainter.rulerSize) {
        drawTooltipBubble(
          canvas,
          guideSystem.getGuideCoordinate(true, i),
          Offset(cx + 12, sy - 10),
        );
        return;
      }
    }
    for (int i = 0; i < guideSystem.verticalGuides.length; i++) {
      final sx = guideToScreenX(guideSystem.verticalGuides[i]);
      if ((cx - sx).abs() < threshold && cy > RulerPainter.rulerSize) {
        drawTooltipBubble(
          canvas,
          guideSystem.getGuideCoordinate(false, i),
          Offset(sx + 12, cy - 10),
        );
        return;
      }
    }
  }

  void drawGhostSnap(Canvas canvas, Size size) {
    final ghost = guideSystem.ghostSnapPosition;
    if (ghost == null) return;
    final paint =
        Paint()
          ..color = isDark ? const Color(0x55FFFFFF) : const Color(0x5500AAFF)
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke;
    const dashLen = 6.0;
    const gapLen = 4.0;
    if (guideSystem.ghostSnapIsHorizontal) {
      final sy = guideToScreenY(ghost.dy);
      double x = RulerPainter.rulerSize;
      while (x < size.width) {
        canvas.drawLine(
          Offset(x, sy),
          Offset((x + dashLen).clamp(0, size.width), sy),
          paint,
        );
        x += dashLen + gapLen;
      }
    } else {
      final sx = guideToScreenX(ghost.dx);
      double y = RulerPainter.rulerSize;
      while (y < size.height) {
        canvas.drawLine(
          Offset(sx, y),
          Offset(sx, (y + dashLen).clamp(0, size.height)),
          paint,
        );
        y += dashLen + gapLen;
      }
    }
  }
}
