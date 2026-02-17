import 'dart:math';
import 'package:flutter/material.dart';
import 'ruler_painter.dart';

/// 📐 Snap, symmetry, protractor & angular guide extensions for [RulerPainter].
///
/// Contains: snap indicator, snap strength, equal spacing, protractor,
/// symmetry axis, angular guides, smart guides, guide intersections.
extension RulerPainterSnap on RulerPainter {
  // ─── Snap Indicator ──────────────────────────────────────────────────

  void drawSnapIndicator(Canvas canvas, Size size) {
    final pos = guideSystem.lastSnapPosition!;
    final screenPos = Offset(
      pos.dx * zoom + canvasOffset.dx,
      pos.dy * zoom + canvasOffset.dy,
    );

    final color = switch (guideSystem.lastSnapType) {
      'guide' => isDark ? const Color(0xFFFF5252) : const Color(0xFFD32F2F),
      'grid' => isDark ? const Color(0xFF448AFF) : const Color(0xFF1565C0),
      'smart' => isDark ? const Color(0xFF69F0AE) : const Color(0xFF2E7D32),
      'angular' => isDark ? const Color(0xFFFFAB40) : const Color(0xFFE65100),
      _ => isDark ? const Color(0xFFFFFFFF) : const Color(0xFF000000),
    };

    final elapsed =
        guideSystem.lastSnapPosition != null
            ? DateTime.now().millisecondsSinceEpoch % 1000
            : 0;
    final pulse = 0.4 + 0.6 * (0.5 + 0.5 * sin(elapsed * pi / 500));

    final crossPaint =
        Paint()
          ..color = color.withValues(alpha: pulse * 0.8)
          ..strokeWidth = 1.5
          ..isAntiAlias = true;
    const r = 8.0;
    canvas.drawLine(
      Offset(screenPos.dx - r, screenPos.dy),
      Offset(screenPos.dx + r, screenPos.dy),
      crossPaint,
    );
    canvas.drawLine(
      Offset(screenPos.dx, screenPos.dy - r),
      Offset(screenPos.dx, screenPos.dy + r),
      crossPaint,
    );

    canvas.drawCircle(
      screenPos,
      5.0,
      Paint()
        ..color = color.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      screenPos,
      5.0,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    if (guideSystem.lastSnapType != null) {
      final tp = TextPainter(
        text: TextSpan(
          text: guideSystem.lastSnapType!.toUpperCase(),
          style: TextStyle(
            color: color,
            fontSize: 7,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(screenPos.dx + 8, screenPos.dy - 10));
    }
  }

  // ─── Snap Strength Indicator ─────────────────────────────────────────

  void drawSnapStrengthIndicator(Canvas canvas, Size size) {
    if (activeGuideIndex == null) return;
    final strength = guideSystem.snapStrength;
    final radius = 4.0 + 12.0 * strength;
    final color =
        isDark
            ? Color.fromARGB((60 * strength).round(), 100, 200, 255)
            : Color.fromARGB((50 * strength).round(), 0, 120, 255);

    if (activeGuideIsHorizontal == true) {
      final guides = guideSystem.horizontalGuides;
      if (activeGuideIndex! < guides.length) {
        final sy = guides[activeGuideIndex!] * zoom + canvasOffset.dy;
        canvas.drawLine(
          Offset(RulerPainter.rulerSize, sy),
          Offset(size.width, sy),
          Paint()
            ..color = color
            ..strokeWidth = radius
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius / 2),
        );
      }
    } else {
      final guides = guideSystem.verticalGuides;
      if (activeGuideIndex! < guides.length) {
        final sx = guides[activeGuideIndex!] * zoom + canvasOffset.dx;
        canvas.drawLine(
          Offset(sx, RulerPainter.rulerSize),
          Offset(sx, size.height),
          Paint()
            ..color = color
            ..strokeWidth = radius
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius / 2),
        );
      }
    }
  }

  // ─── Equal Spacing Indicators ────────────────────────────────────────

  void drawEqualSpacingIndicators(Canvas canvas, Size size) {
    if (activeGuideIndex == null || activeGuideIsHorizontal == null) return;
    final isH = activeGuideIsHorizontal!;
    final idx = activeGuideIndex!;
    final guides =
        isH ? guideSystem.horizontalGuides : guideSystem.verticalGuides;
    if (idx >= guides.length) return;

    final dragPos = guides[idx];
    final sorted = List<double>.from(guides)..sort();
    final dragIdx = sorted.indexOf(dragPos);
    if (dragIdx < 0) return;

    if (dragIdx > 0 && dragIdx < sorted.length - 1) {
      final dPrev = (dragPos - sorted[dragIdx - 1]).abs();
      final dNext = (sorted[dragIdx + 1] - dragPos).abs();
      if (dPrev > 1 && (dPrev - dNext).abs() < 2.0) {
        final eqPaint =
            Paint()
              ..color = const Color(0xCC4CAF50)
              ..strokeWidth = 1.0;
        final eqStyle = TextStyle(
          color: const Color(0xCC4CAF50),
          fontSize: 9,
          fontWeight: FontWeight.bold,
          fontFeatures: const [FontFeature.tabularFigures()],
        );

        if (isH) {
          final sy = dragPos * zoom + canvasOffset.dy;
          final syPrev = sorted[dragIdx - 1] * zoom + canvasOffset.dy;
          final syNext = sorted[dragIdx + 1] * zoom + canvasOffset.dy;
          final eqLabel = getCachedLabel('=', eqStyle);
          eqLabel.paint(
            canvas,
            Offset(size.width - 24, (syPrev + sy) / 2 - eqLabel.height / 2),
          );
          eqLabel.paint(
            canvas,
            Offset(size.width - 24, (sy + syNext) / 2 - eqLabel.height / 2),
          );
          canvas.drawLine(
            Offset(size.width - 16, syPrev),
            Offset(size.width - 16, sy),
            eqPaint,
          );
          canvas.drawLine(
            Offset(size.width - 16, sy),
            Offset(size.width - 16, syNext),
            eqPaint,
          );
        } else {
          final sx = dragPos * zoom + canvasOffset.dx;
          final sxPrev = sorted[dragIdx - 1] * zoom + canvasOffset.dx;
          final sxNext = sorted[dragIdx + 1] * zoom + canvasOffset.dx;
          final eqLabel = getCachedLabel('=', eqStyle);
          eqLabel.paint(
            canvas,
            Offset((sxPrev + sx) / 2 - eqLabel.width / 2, size.height - 20),
          );
          eqLabel.paint(
            canvas,
            Offset((sx + sxNext) / 2 - eqLabel.width / 2, size.height - 20),
          );
          canvas.drawLine(
            Offset(sxPrev, size.height - 12),
            Offset(sx, size.height - 12),
            eqPaint,
          );
          canvas.drawLine(
            Offset(sx, size.height - 12),
            Offset(sxNext, size.height - 12),
            eqPaint,
          );
        }
      }
    }
  }

  // ─── Guide Intersections ─────────────────────────────────────────────

  void drawGuideIntersections(Canvas canvas, Size size) {
    final dotPaint =
        Paint()
          ..color = isDark ? const Color(0x66FFFFFF) : const Color(0x55000000)
          ..style = PaintingStyle.fill;
    final ringPaint =
        Paint()
          ..color = isDark ? const Color(0x33FFFFFF) : const Color(0x22000000)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5;

    for (final hy in guideSystem.horizontalGuides) {
      final sy = hy * zoom + canvasOffset.dy;
      if (sy < RulerPainter.rulerSize || sy > size.height) continue;
      for (final vx in guideSystem.verticalGuides) {
        final sx = vx * zoom + canvasOffset.dx;
        if (sx < RulerPainter.rulerSize || sx > size.width) continue;
        canvas.drawCircle(Offset(sx, sy), 3.0, dotPaint);
        canvas.drawCircle(Offset(sx, sy), 5.0, ringPaint);
      }
    }
  }

  // ─── Protractor ──────────────────────────────────────────────────────

  void drawProtractor(Canvas canvas, Size size) {
    final center = guideSystem.protractorCenter!;
    final screenCenter = Offset(
      center.dx * zoom + canvasOffset.dx,
      center.dy * zoom + canvasOffset.dy,
    );
    final protColor =
        isDark ? const Color(0xBB80DEEA) : const Color(0xBB00838F);

    canvas.drawCircle(screenCenter, 4.0, Paint()..color = protColor);

    if (guideSystem.protractorArm1 != null) {
      final arm1 = Offset(
        guideSystem.protractorArm1!.dx * zoom + canvasOffset.dx,
        guideSystem.protractorArm1!.dy * zoom + canvasOffset.dy,
      );
      canvas.drawLine(
        screenCenter,
        arm1,
        Paint()
          ..color = protColor
          ..strokeWidth = 1.5
          ..isAntiAlias = true,
      );
    }

    if (guideSystem.protractorArm2 != null) {
      final arm2 = Offset(
        guideSystem.protractorArm2!.dx * zoom + canvasOffset.dx,
        guideSystem.protractorArm2!.dy * zoom + canvasOffset.dy,
      );
      canvas.drawLine(
        screenCenter,
        arm2,
        Paint()
          ..color = protColor
          ..strokeWidth = 1.5
          ..isAntiAlias = true,
      );

      final angle = guideSystem.protractorAngle;
      if (angle != null && guideSystem.protractorArm1 != null) {
        final arm1 = guideSystem.protractorArm1!;
        final a1 = atan2(arm1.dy - center.dy, arm1.dx - center.dx);
        final arcRadius = 40.0;
        final arcRect = Rect.fromCircle(
          center: screenCenter,
          radius: arcRadius,
        );
        canvas.drawArc(
          arcRect,
          a1,
          angle * pi / 180,
          true,
          Paint()
            ..color = protColor.withValues(alpha: 0.3)
            ..style = PaintingStyle.fill
            ..isAntiAlias = true,
        );
        canvas.drawArc(
          arcRect,
          a1,
          angle * pi / 180,
          false,
          Paint()
            ..color = protColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..isAntiAlias = true,
        );

        final midAngle = a1 + (angle * pi / 180) / 2;
        final labelPos = Offset(
          screenCenter.dx + cos(midAngle) * (arcRadius + 16),
          screenCenter.dy + sin(midAngle) * (arcRadius + 16),
        );
        final tp = TextPainter(
          text: TextSpan(
            text: '${angle.toStringAsFixed(1)}°',
            style: TextStyle(
              color: protColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(labelPos.dx - tp.width / 2, labelPos.dy - tp.height / 2),
        );
      }
    }
  }

  // ─── Smart Guides ────────────────────────────────────────────────────

  void drawSmartGuides(Canvas canvas, Size size) {
    if (guideSystem.smartHGuides.isEmpty && guideSystem.smartVGuides.isEmpty)
      return;
    final smartColor =
        isDark ? const Color(0x6600E676) : const Color(0x5500C853);
    final smartPaint =
        Paint()
          ..color = smartColor
          ..strokeWidth = 0.8
          ..isAntiAlias = true;

    for (final gy in guideSystem.smartHGuides) {
      final sy = gy * zoom + canvasOffset.dy;
      if (sy < 0 || sy > size.height) continue;
      drawDashedLine(canvas, Offset(0, sy), Offset(size.width, sy), smartPaint);
    }
    for (final gx in guideSystem.smartVGuides) {
      final sx = gx * zoom + canvasOffset.dx;
      if (sx < 0 || sx > size.width) continue;
      drawDashedLine(
        canvas,
        Offset(sx, 0),
        Offset(sx, size.height),
        smartPaint,
      );
    }
  }

  // ─── Symmetry Axis ───────────────────────────────────────────────────

  void drawSymmetryAxis(Canvas canvas, Size size) {
    final idx = guideSystem.symmetryAxisIndex;
    if (idx == null) return;
    final isH = guideSystem.symmetryAxisIsHorizontal;
    final guides =
        isH ? guideSystem.horizontalGuides : guideSystem.verticalGuides;
    if (idx >= guides.length) return;

    final val = guides[idx];
    final symColor = isDark ? const Color(0xCC7C4DFF) : const Color(0xBB651FFF);
    final symPaint =
        Paint()
          ..color = symColor
          ..strokeWidth = 2.0
          ..isAntiAlias = true;

    if (isH) {
      final sy = val * zoom + canvasOffset.dy;
      drawDashedLine(canvas, Offset(0, sy), Offset(size.width, sy), symPaint);
      _drawMirrorIcon(canvas, Offset(size.width - 20, sy), symColor);
    } else {
      final sx = val * zoom + canvasOffset.dx;
      drawDashedLine(canvas, Offset(sx, 0), Offset(sx, size.height), symPaint);
      _drawMirrorIcon(canvas, Offset(sx, size.height - 20), symColor);
    }

    if (guideSystem.symmetrySegments > 2) {
      final center =
          isH
              ? Offset(size.width / 2, val * zoom + canvasOffset.dy)
              : Offset(val * zoom + canvasOffset.dx, size.height / 2);
      final maxR = size.longestSide;
      final segPaint =
          Paint()
            ..color = symColor.withValues(alpha: 0.3)
            ..strokeWidth = 1.0
            ..isAntiAlias = true;
      final angleStep = pi / guideSystem.symmetrySegments;
      for (int i = 0; i < guideSystem.symmetrySegments; i++) {
        final a = angleStep * i;
        final dx = cos(a) * maxR;
        final dy = sin(a) * maxR;
        canvas.drawLine(
          Offset(center.dx - dx, center.dy - dy),
          Offset(center.dx + dx, center.dy + dy),
          segPaint,
        );
      }
      final tp = TextPainter(
        text: TextSpan(
          text: '${guideSystem.symmetrySegments}×',
          style: TextStyle(
            color: symColor,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(center.dx + 10, center.dy - tp.height - 4));
    }
  }

  void _drawMirrorIcon(Canvas canvas, Offset pos, Color color) {
    final p =
        Paint()
          ..color = color
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke
          ..isAntiAlias = true;
    canvas.drawLine(pos + const Offset(-5, 0), pos + const Offset(5, 0), p);
    canvas.drawLine(pos + const Offset(-5, 0), pos + const Offset(-3, -2), p);
    canvas.drawLine(pos + const Offset(-5, 0), pos + const Offset(-3, 2), p);
    canvas.drawLine(pos + const Offset(5, 0), pos + const Offset(3, -2), p);
    canvas.drawLine(pos + const Offset(5, 0), pos + const Offset(3, 2), p);
  }

  // ─── Angular Guides ──────────────────────────────────────────────────

  void drawAngularGuides(Canvas canvas, Size size) {
    final maxLen = size.longestSide * 2;
    for (final ag in guideSystem.angularGuides) {
      final screenOrigin = Offset(
        ag.origin.dx * zoom + canvasOffset.dx,
        ag.origin.dy * zoom + canvasOffset.dy,
      );
      final angleRad = ag.angleDeg * pi / 180;
      final dx = cos(angleRad) * maxLen;
      final dy = sin(angleRad) * maxLen;
      final color =
          ag.color ??
          (isDark ? const Color(0xBBFF8A65) : const Color(0xBBE65100));
      final paint =
          Paint()
            ..color = color
            ..strokeWidth = ag.locked ? 0.8 : 1.2
            ..isAntiAlias = true;
      drawDashedLine(
        canvas,
        Offset(screenOrigin.dx - dx, screenOrigin.dy - dy),
        Offset(screenOrigin.dx + dx, screenOrigin.dy + dy),
        paint,
      );
      canvas.drawCircle(screenOrigin, 3.0, Paint()..color = color);
      final label = '${ag.angleDeg.toStringAsFixed(1)}°';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, screenOrigin + const Offset(6, -14));
    }
  }
}
