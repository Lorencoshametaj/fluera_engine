import 'dart:math';
import 'package:flutter/material.dart';
import '../../tools/ruler/ruler_guide_system.dart';
import 'ruler_painter.dart';

/// 📐 Measurement & distance rendering extensions for [RulerPainter].
///
/// Contains: measurement tool, distance labels, auto-distance,
/// crosshair, edge constraints, distance label pills.
extension RulerPainterMeasurement on RulerPainter {
  // ─── Measurement Tool ────────────────────────────────────────────────

  void drawMeasurement(Canvas canvas, Size size) {
    final s = guideSystem.measureStart!;
    final e = guideSystem.measureEnd!;
    final r = guideSystem.measureResult;
    if (r == null) return;

    final ss = Offset(
      s.dx * zoom + canvasOffset.dx,
      s.dy * zoom + canvasOffset.dy,
    );
    final se = Offset(
      e.dx * zoom + canvasOffset.dx,
      e.dy * zoom + canvasOffset.dy,
    );
    final mc = isDark ? const Color(0xFFFFD740) : const Color(0xFFF57F17);

    canvas.drawLine(
      ss,
      se,
      Paint()
        ..color = mc.withValues(alpha: 0.8)
        ..strokeWidth = 1.5
        ..isAntiAlias = true,
    );
    canvas.drawCircle(ss, 3, Paint()..color = mc);
    canvas.drawCircle(se, 3, Paint()..color = mc);

    final dp =
        Paint()
          ..color = mc.withValues(alpha: 0.3)
          ..strokeWidth = 0.5
          ..isAntiAlias = true;
    drawDashedLine(canvas, ss, Offset(se.dx, ss.dy), dp);
    drawDashedLine(canvas, Offset(se.dx, ss.dy), se, dp);

    final suffix = guideSystem.unitSuffix;
    final distUnit = guideSystem.convertToUnit(r.distance);
    final dxUnit = guideSystem.convertToUnit(r.dx.abs());
    final dyUnit = guideSystem.convertToUnit(r.dy.abs());
    final distText =
        guideSystem.currentUnit == RulerUnit.px
            ? '${distUnit.round()}'
            : distUnit.toStringAsFixed(1);
    final dxText =
        guideSystem.currentUnit == RulerUnit.px
            ? '${dxUnit.round()}'
            : dxUnit.toStringAsFixed(1);
    final dyText =
        guideSystem.currentUnit == RulerUnit.px
            ? '${dyUnit.round()}'
            : dyUnit.toStringAsFixed(1);
    final info =
        '$distText $suffix  ${r.angle.toStringAsFixed(1)}°\nΔx: $dxText  Δy: $dyText';

    final mid = Offset((ss.dx + se.dx) / 2, (ss.dy + se.dy) / 2);
    final tp = TextPainter(
      text: TextSpan(
        text: info,
        style: TextStyle(
          color: mc,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          height: 1.4,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();

    final lo = Offset(mid.dx - tp.width / 2, mid.dy - tp.height - 8);
    final bg = RRect.fromRectAndRadius(
      Rect.fromLTWH(lo.dx - 6, lo.dy - 3, tp.width + 12, tp.height + 6),
      const Radius.circular(4),
    );
    canvas.drawRRect(
      bg,
      Paint()
        ..color = isDark ? const Color(0xDD1A1A1A) : const Color(0xDDFFFFFF),
    );
    canvas.drawRRect(
      bg,
      Paint()
        ..color = mc.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    tp.paint(canvas, lo);
  }

  // ─── Distance Labels ─────────────────────────────────────────────────

  void drawDistanceLabels(Canvas canvas, Size size) {
    final suffix = guideSystem.unitSuffix;

    if (guideSystem.horizontalGuides.length >= 2) {
      final sorted = List<double>.from(guideSystem.horizontalGuides)..sort();
      for (int i = 0; i < sorted.length - 1; i++) {
        final dist = (sorted[i + 1] - sorted[i]).abs();
        if (dist < 2) continue;
        final sy1 = sorted[i] * zoom + canvasOffset.dy;
        final sy2 = sorted[i + 1] * zoom + canvasOffset.dy;
        if (sy1 < 0 || sy2 > size.height || (sy2 - sy1).abs() < 20) continue;
        final unitDist = guideSystem.convertToUnit(dist);
        final label =
            guideSystem.currentUnit == RulerUnit.px
                ? '${unitDist.round()} $suffix'
                : '${unitDist.toStringAsFixed(1)} $suffix';
        _drawDistLabel(
          canvas,
          Offset(
            guideSystem.rulersVisible ? RulerPainter.rulerSize + 8 : 8,
            (sy1 + sy2) / 2,
          ),
          label,
          const Color(0xFF00BCD4),
        );
      }
    }

    if (guideSystem.verticalGuides.length >= 2) {
      final sorted = List<double>.from(guideSystem.verticalGuides)..sort();
      for (int i = 0; i < sorted.length - 1; i++) {
        final dist = (sorted[i + 1] - sorted[i]).abs();
        if (dist < 2) continue;
        final sx1 = sorted[i] * zoom + canvasOffset.dx;
        final sx2 = sorted[i + 1] * zoom + canvasOffset.dx;
        if (sx1 < 0 || sx2 > size.width || (sx2 - sx1).abs() < 20) continue;
        final unitDist = guideSystem.convertToUnit(dist);
        final label =
            guideSystem.currentUnit == RulerUnit.px
                ? '${unitDist.round()} $suffix'
                : '${unitDist.toStringAsFixed(1)} $suffix';
        _drawDistLabel(
          canvas,
          Offset(
            (sx1 + sx2) / 2,
            guideSystem.rulersVisible ? RulerPainter.rulerSize + 8 : 8,
          ),
          label,
          const Color(0xFFE040FB),
        );
      }
    }
  }

  void _drawDistLabel(Canvas canvas, Offset pos, String text, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color.withValues(alpha: 0.8),
          fontSize: 8,
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final bg = RRect.fromRectAndRadius(
      Rect.fromCenter(center: pos, width: tp.width + 8, height: tp.height + 4),
      const Radius.circular(3),
    );
    canvas.drawRRect(
      bg,
      Paint()..color = color.withValues(alpha: isDark ? 0.15 : 0.1),
    );
    canvas.drawRRect(
      bg,
      Paint()
        ..color = color.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );
    tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy - tp.height / 2));
  }

  // ─── Auto Distance ───────────────────────────────────────────────────

  void drawAutoDistance(Canvas canvas, Size size) {
    final style = TextStyle(
      color: isDark ? const Color(0x88FFFFFF) : const Color(0x77000000),
      fontSize: 8,
      fontWeight: FontWeight.w500,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final bgColor = isDark ? const Color(0x44000000) : const Color(0x44FFFFFF);

    if (guideSystem.horizontalGuides.length >= 2) {
      final sorted = List<double>.from(guideSystem.horizontalGuides)..sort();
      for (int i = 0; i < sorted.length - 1; i++) {
        final sy1 = sorted[i] * zoom + canvasOffset.dy;
        final sy2 = sorted[i + 1] * zoom + canvasOffset.dy;
        if (sy2 < RulerPainter.rulerSize || sy1 > size.height) continue;
        if ((sy2 - sy1).abs() < 20) continue;
        final dist = guideSystem.convertToUnit(sorted[i + 1] - sorted[i]);
        final label = dist.round().toString();
        final tp = getCachedLabel(label, style);
        final midY = (sy1 + sy2) / 2;
        final px = size.width - tp.width - 8;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              px - 3,
              midY - tp.height / 2 - 1,
              tp.width + 6,
              tp.height + 2,
            ),
            const Radius.circular(2),
          ),
          Paint()..color = bgColor,
        );
        tp.paint(canvas, Offset(px, midY - tp.height / 2));
      }
    }

    if (guideSystem.verticalGuides.length >= 2) {
      final sorted = List<double>.from(guideSystem.verticalGuides)..sort();
      for (int i = 0; i < sorted.length - 1; i++) {
        final sx1 = sorted[i] * zoom + canvasOffset.dx;
        final sx2 = sorted[i + 1] * zoom + canvasOffset.dx;
        if (sx2 < RulerPainter.rulerSize || sx1 > size.width) continue;
        if ((sx2 - sx1).abs() < 20) continue;
        final dist = guideSystem.convertToUnit(sorted[i + 1] - sorted[i]);
        final label = dist.round().toString();
        final tp = getCachedLabel(label, style);
        final midX = (sx1 + sx2) / 2;
        final py = size.height - tp.height - 6;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              midX - tp.width / 2 - 3,
              py - 1,
              tp.width + 6,
              tp.height + 2,
            ),
            const Radius.circular(2),
          ),
          Paint()..color = bgColor,
        );
        tp.paint(canvas, Offset(midX - tp.width / 2, py));
      }
    }
  }

  // ─── Crosshair ───────────────────────────────────────────────────────

  void drawCrosshair(Canvas canvas, Size size) {
    if (cursorPosition == null) return;
    final cx = cursorPosition!.dx;
    final cy = cursorPosition!.dy;
    if (cx <= RulerPainter.rulerSize && cy <= RulerPainter.rulerSize) return;
    final cp =
        Paint()
          ..color = isDark ? const Color(0x55FFFFFF) : const Color(0x44000000)
          ..strokeWidth = 0.5;
    drawDashedLine(
      canvas,
      Offset(RulerPainter.rulerSize, cy),
      Offset(size.width, cy),
      cp,
    );
    drawDashedLine(
      canvas,
      Offset(cx, RulerPainter.rulerSize),
      Offset(cx, size.height),
      cp,
    );
  }

  // ─── Edge Constraints ────────────────────────────────────────────────

  void drawEdgeConstraints(Canvas canvas, Size size) {
    if (activeGuideIndex == null || activeGuideIsHorizontal == null) return;
    final isH = activeGuideIsHorizontal!;
    final idx = activeGuideIndex!;
    double screenPos, canvasPos;

    if (isH) {
      if (idx >= guideSystem.horizontalGuides.length) return;
      canvasPos = guideSystem.horizontalGuides[idx];
      screenPos = canvasPos * zoom + canvasOffset.dy;
    } else {
      if (idx >= guideSystem.verticalGuides.length) return;
      canvasPos = guideSystem.verticalGuides[idx];
      screenPos = canvasPos * zoom + canvasOffset.dx;
    }

    final cp =
        Paint()
          ..color = const Color(0x66FF7043)
          ..strokeWidth = 0.5;
    final ls = TextStyle(
      color: const Color(0xCCFF7043),
      fontSize: 9,
      fontWeight: FontWeight.w500,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    if (isH) {
      final distTop = guideSystem.convertToUnit(canvasPos);
      drawDashedLine(
        canvas,
        Offset(RulerPainter.rulerSize + 4, RulerPainter.rulerSize),
        Offset(RulerPainter.rulerSize + 4, screenPos),
        cp,
      );
      if (distTop.abs() > 1) {
        final lbl = getCachedLabel(distTop.round().toString(), ls);
        lbl.paint(
          canvas,
          Offset(
            RulerPainter.rulerSize + 8,
            (RulerPainter.rulerSize + screenPos) / 2 - lbl.height / 2,
          ),
        );
      }
      final bottomCanvas = (size.height - canvasOffset.dy) / zoom;
      final distBot = guideSystem.convertToUnit(bottomCanvas - canvasPos);
      drawDashedLine(
        canvas,
        Offset(RulerPainter.rulerSize + 4, screenPos),
        Offset(RulerPainter.rulerSize + 4, size.height),
        cp,
      );
      if (distBot.abs() > 1) {
        final lbl = getCachedLabel(distBot.round().toString(), ls);
        lbl.paint(
          canvas,
          Offset(
            RulerPainter.rulerSize + 8,
            (screenPos + size.height) / 2 - lbl.height / 2,
          ),
        );
      }
    } else {
      final distLeft = guideSystem.convertToUnit(canvasPos);
      drawDashedLine(
        canvas,
        Offset(RulerPainter.rulerSize, RulerPainter.rulerSize + 4),
        Offset(screenPos, RulerPainter.rulerSize + 4),
        cp,
      );
      if (distLeft.abs() > 1) {
        final lbl = getCachedLabel(distLeft.round().toString(), ls);
        lbl.paint(
          canvas,
          Offset(
            (RulerPainter.rulerSize + screenPos) / 2 - lbl.width / 2,
            RulerPainter.rulerSize + 8,
          ),
        );
      }
      final rightCanvas = (size.width - canvasOffset.dx) / zoom;
      final distRight = guideSystem.convertToUnit(rightCanvas - canvasPos);
      drawDashedLine(
        canvas,
        Offset(screenPos, RulerPainter.rulerSize + 4),
        Offset(size.width, RulerPainter.rulerSize + 4),
        cp,
      );
      if (distRight.abs() > 1) {
        final lbl = getCachedLabel(distRight.round().toString(), ls);
        lbl.paint(
          canvas,
          Offset(
            (screenPos + size.width) / 2 - lbl.width / 2,
            RulerPainter.rulerSize + 8,
          ),
        );
      }
    }
  }
}
