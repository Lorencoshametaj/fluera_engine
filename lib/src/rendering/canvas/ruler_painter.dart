import 'dart:math';
import 'package:flutter/material.dart';
import '../../tools/ruler/ruler_guide_system.dart';

// Extension modules — each adds a category of drawing methods.
import 'ruler_painter_grids.dart';
import 'ruler_painter_guides.dart';
import 'ruler_painter_measurement.dart';
import 'ruler_painter_rulers.dart';
import 'ruler_painter_snap.dart';

/// 📐 RulerPainter — Professional ruler, guide, grid & perspective overlay
///
/// This file contains the core class with fields, the [paint] dispatch method,
/// shared utilities used by extensions, and [shouldRepaint].
///
/// Drawing logic is split across extension files:
/// - [RulerPainterGrids]       — grids, pixel grid, isometric, perspective, radial, golden spiral
/// - [RulerPainterGuides]      — guide lines, labels, intersections, glow, ghost snap
/// - [RulerPainterRulers]      — horizontal/vertical rulers, corner box, cursor, bookmarks
/// - [RulerPainterMeasurement] — measurement tool, distance labels, crosshair, edge constraints
/// - [RulerPainterSnap]        — snap indicator, protractor, symmetry, angular guides
class RulerPainter extends CustomPainter {
  final RulerGuideSystem guideSystem;
  final Offset canvasOffset;
  final double zoom;
  final bool isDark;
  final Offset? cursorPosition;
  final int? activeGuideIndex;
  final bool? activeGuideIsHorizontal;

  static const double rulerSize = 28.0;

  RulerPainter({
    required this.guideSystem,
    required this.canvasOffset,
    required this.zoom,
    this.isDark = false,
    this.cursorPosition,
    this.activeGuideIndex,
    this.activeGuideIsHorizontal,
  });

  // ─── TextPainter LRU cache ───────────────────────────────────────────

  static final Map<String, TextPainter> _labelCache = {};
  static const int _maxLabelCacheSize = 200;

  TextPainter getCachedLabel(String text, TextStyle style) {
    final key = '${text}_${style.color?.toARGB32()}_${style.fontSize}';
    var tp = _labelCache[key];
    if (tp != null) return tp;
    tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    if (_labelCache.length >= _maxLabelCacheSize) {
      final toRemove = _labelCache.keys.take(_maxLabelCacheSize ~/ 4).toList();
      for (final k in toRemove) {
        _labelCache.remove(k);
      }
    }
    _labelCache[key] = tp;
    return tp;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // paint() — dispatch to extensions
  // ═══════════════════════════════════════════════════════════════════════

  @override
  void paint(Canvas canvas, Size size) {
    // 🌊 Smooth ruler fade at extreme zoom (Phase 8B)
    final double rulerOpacity;
    if (zoom < 0.10) {
      rulerOpacity = 0.2;
    } else if (zoom < 0.20) {
      rulerOpacity = 0.2 + (zoom - 0.10) / 0.10 * 0.8;
    } else if (zoom > 30.0) {
      rulerOpacity = 0.2;
    } else if (zoom > 20.0) {
      rulerOpacity = 1.0 - (zoom - 20.0) / 10.0 * 0.8;
    } else {
      rulerOpacity = 1.0;
    }
    if (rulerOpacity < 1.0) {
      canvas.saveLayer(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()
          ..color = Color.fromARGB((rulerOpacity * 255).round(), 255, 255, 255),
      );
    }

    // Background grids (below guides)
    if (guideSystem.gridVisible) {
      drawGrid(canvas, size);
      if (zoom > 8.0) drawPixelGrid(canvas, size);
    }
    if (guideSystem.isometricGridVisible) drawIsometricGrid(canvas, size);
    if (guideSystem.perspectiveType != PerspectiveType.none) {
      drawPerspectiveGrid(canvas, size);
    }
    if (guideSystem.radialGridVisible) drawRadialGrid(canvas, size);

    // Smart guides (transient alignment lines)
    if (guideSystem.smartGuidesEnabled) drawSmartGuides(canvas, size);

    // Guides — Phase 10C: apply global guide opacity
    if (guideSystem.guidesVisible) {
      if (guideSystem.guideOpacity < 1.0) {
        canvas.saveLayer(
          Offset.zero & size,
          Paint()
            ..color = Color.fromARGB(
              (guideSystem.guideOpacity * 255).round(),
              255,
              255,
              255,
            ),
        );
      }
      drawGuides(canvas, size);
      drawIntersectionMarkers(canvas, size);
      drawDistanceLabels(canvas, size);
      drawGuideDistanceLabels(canvas, size);
      if (guideSystem.showGuideLabels) drawGuideLabels(canvas, size);
      if (guideSystem.guideOpacity < 1.0) {
        canvas.restore();
      }
    }

    // Feature H: Animated guide creation glow
    drawNewGuideGlow(canvas, size);

    // Angular guides
    if (guideSystem.angularGuides.isNotEmpty) drawAngularGuides(canvas, size);

    // Symmetry axis highlight
    if (guideSystem.symmetryEnabled) drawSymmetryAxis(canvas, size);

    // Golden spiral overlay
    if (guideSystem.showGoldenSpiral) drawGoldenSpiral(canvas, size);

    // Protractor
    if (guideSystem.isProtractorMode && guideSystem.protractorCenter != null) {
      drawProtractor(canvas, size);
    }

    // Snap feedback indicator
    if (guideSystem.didSnapOnLastCall && guideSystem.lastSnapPosition != null) {
      drawSnapIndicator(canvas, size);
    }

    // Measurement tool
    if (guideSystem.isMeasuring &&
        guideSystem.measureStart != null &&
        guideSystem.measureEnd != null) {
      drawMeasurement(canvas, size);
    }

    // Feature G: Edge constraint lines when dragging a guide
    if (activeGuideIndex != null && activeGuideIsHorizontal != null) {
      drawEdgeConstraints(canvas, size);
    }

    // Crosshair (Phase 8C)
    if (guideSystem.crosshairEnabled && cursorPosition != null) {
      drawCrosshair(canvas, size);
    }

    // Equal spacing indicators (Phase 8F)
    if (activeGuideIndex != null && activeGuideIsHorizontal != null) {
      drawEqualSpacingIndicators(canvas, size);
    }

    // Phase 9B: Guide intersection dots
    if (guideSystem.guidesVisible &&
        guideSystem.horizontalGuides.isNotEmpty &&
        guideSystem.verticalGuides.isNotEmpty) {
      drawGuideIntersections(canvas, size);
    }

    // Phase 9C: Auto-distance between consecutive guides
    if (guideSystem.guidesVisible && guideSystem.showGuideLabels) {
      drawAutoDistance(canvas, size);
    }

    // Phase 9G: Ruler bookmark marks
    if (guideSystem.rulersVisible && guideSystem.bookmarkMarks.isNotEmpty) {
      drawBookmarkMarks(canvas, size);
    }

    // Phase 10A: Guide hover tooltip
    if (cursorPosition != null && guideSystem.guidesVisible) {
      drawGuideHoverTooltip(canvas, size);
    }

    // Phase 10H: Ghost snap preview
    if (guideSystem.ghostSnapPosition != null && activeGuideIndex != null) {
      drawGhostSnap(canvas, size);
    }

    // Phase 11E: Snap strength indicator during drag
    if (activeGuideIndex != null && guideSystem.snapEnabled) {
      drawSnapStrengthIndicator(canvas, size);
    }

    // Phase 11G: Scale indicator
    if (guideSystem.rulersVisible) {
      drawScaleIndicator(canvas, size);
    }

    // Rulers on top
    if (guideSystem.rulersVisible) {
      drawHorizontalRuler(canvas, size);
      drawVerticalRuler(canvas, size);
      drawCornerBox(canvas, size);
      if (cursorPosition != null) {
        drawCursorIndicator(canvas, size);
        drawCursorTooltip(canvas, size);
      }
    } else {
      drawCornerBox(canvas, size);
    }

    if (rulerOpacity < 1.0) {
      canvas.restore();
    }
  }

  // ─── Shared Utilities (used by extensions) ────────────────────────────

  void drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const d = 6.0;
    const g = 3.0;
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final len = sqrt(dx * dx + dy * dy);
    if (len == 0) return;
    final ux = dx / len;
    final uy = dy / len;
    double dist = 0;
    bool draw = true;
    while (dist < len) {
      final seg = draw ? d : g;
      final ed = (dist + seg).clamp(0.0, len);
      if (draw) {
        canvas.drawLine(
          Offset(start.dx + ux * dist, start.dy + uy * dist),
          Offset(start.dx + ux * ed, start.dy + uy * ed),
          paint,
        );
      }
      dist = ed;
      draw = !draw;
    }
  }

  String formatLabel(double value) {
    final unitVal = guideSystem.convertToUnit(value);
    if (guideSystem.currentUnit != RulerUnit.px) {
      if (unitVal.abs() < 0.05) return '0';
      return unitVal.toStringAsFixed(unitVal.abs() >= 100 ? 0 : 1);
    }
    final v = value.toInt();
    if (v == 0) return '0';
    if (v.abs() >= 1000) {
      return '${(v / 1000).toStringAsFixed(v.abs() >= 10000 ? 0 : 1)}k';
    }
    return v.toString();
  }

  String formatLabelWithOrigin(double value, bool isX) {
    final origin =
        isX ? guideSystem.rulerOrigin.dx : guideSystem.rulerOrigin.dy;
    return formatLabel(value - origin);
  }

  double calculateStep(double zoom) {
    final double minGap;
    switch (guideSystem.currentUnit) {
      case RulerUnit.px:
        minGap = 60.0;
      case RulerUnit.cm:
      case RulerUnit.mm:
        minGap = 72.0;
      case RulerUnit.inches:
        minGap = 78.0;
    }
    const steps = [
      0.5,
      1.0,
      2.0,
      5.0,
      10.0,
      20.0,
      50.0,
      100.0,
      200.0,
      500.0,
      1000.0,
      2000.0,
      5000.0,
    ];
    for (final s in steps) {
      if (s * zoom >= minGap) return s;
    }
    return 5000.0;
  }

  void drawTooltipBubble(Canvas canvas, String text, Offset pos) {
    final style = TextStyle(
      color: isDark ? Colors.white : Colors.black87,
      fontSize: 10,
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final tp = getCachedLabel(text, style);
    final rect = Rect.fromLTWH(
      pos.dx - 4,
      pos.dy - 2,
      tp.width + 8,
      tp.height + 4,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = isDark ? const Color(0xDD333333) : const Color(0xDDFFFFFF),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = isDark ? const Color(0x44FFFFFF) : const Color(0x44000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );
    tp.paint(canvas, Offset(pos.dx, pos.dy));
  }

  // ─── shouldRepaint ────────────────────────────────────────────────────

  @override
  bool shouldRepaint(RulerPainter oldDelegate) {
    return canvasOffset != oldDelegate.canvasOffset ||
        zoom != oldDelegate.zoom ||
        isDark != oldDelegate.isDark ||
        cursorPosition != oldDelegate.cursorPosition ||
        activeGuideIndex != oldDelegate.activeGuideIndex ||
        activeGuideIsHorizontal != oldDelegate.activeGuideIsHorizontal ||
        guideSystem.horizontalGuides.length !=
            oldDelegate.guideSystem.horizontalGuides.length ||
        guideSystem.verticalGuides.length !=
            oldDelegate.guideSystem.verticalGuides.length ||
        guideSystem.rulersVisible != oldDelegate.guideSystem.rulersVisible ||
        guideSystem.guidesVisible != oldDelegate.guideSystem.guidesVisible ||
        guideSystem.gridVisible != oldDelegate.guideSystem.gridVisible ||
        guideSystem.gridStyle != oldDelegate.guideSystem.gridStyle ||
        guideSystem.isometricGridVisible !=
            oldDelegate.guideSystem.isometricGridVisible ||
        guideSystem.isMeasuring != oldDelegate.guideSystem.isMeasuring ||
        guideSystem.perspectiveType !=
            oldDelegate.guideSystem.perspectiveType ||
        guideSystem.radialGridVisible !=
            oldDelegate.guideSystem.radialGridVisible ||
        guideSystem.multiSelectMode !=
            oldDelegate.guideSystem.multiSelectMode ||
        guideSystem.symmetryEnabled !=
            oldDelegate.guideSystem.symmetryEnabled ||
        guideSystem.symmetrySegments !=
            oldDelegate.guideSystem.symmetrySegments ||
        guideSystem.smartGuidesEnabled !=
            oldDelegate.guideSystem.smartGuidesEnabled ||
        guideSystem.currentUnit != oldDelegate.guideSystem.currentUnit ||
        guideSystem.smartHGuides.length !=
            oldDelegate.guideSystem.smartHGuides.length ||
        guideSystem.smartVGuides.length !=
            oldDelegate.guideSystem.smartVGuides.length ||
        guideSystem.angularGuides.length !=
            oldDelegate.guideSystem.angularGuides.length ||
        guideSystem.showGuideLabels !=
            oldDelegate.guideSystem.showGuideLabels ||
        guideSystem.customGridStep != oldDelegate.guideSystem.customGridStep ||
        guideSystem.isProtractorMode !=
            oldDelegate.guideSystem.isProtractorMode ||
        guideSystem.rulerOrigin != oldDelegate.guideSystem.rulerOrigin ||
        guideSystem.didSnapOnLastCall ||
        guideSystem.hasActiveGlow ||
        guideSystem.showGoldenSpiral !=
            oldDelegate.guideSystem.showGoldenSpiral ||
        guideSystem.lastGuideCreatedAt !=
            oldDelegate.guideSystem.lastGuideCreatedAt ||
        guideSystem.gridSnapEnabled !=
            oldDelegate.guideSystem.gridSnapEnabled ||
        guideSystem.crosshairEnabled !=
            oldDelegate.guideSystem.crosshairEnabled ||
        guideSystem.selectedHorizontalGuides.length !=
            oldDelegate.guideSystem.selectedHorizontalGuides.length ||
        guideSystem.selectedVerticalGuides.length !=
            oldDelegate.guideSystem.selectedVerticalGuides.length ||
        guideSystem.protractorCenter !=
            oldDelegate.guideSystem.protractorCenter ||
        guideSystem.protractorSnapStep !=
            oldDelegate.guideSystem.protractorSnapStep;
  }
}
