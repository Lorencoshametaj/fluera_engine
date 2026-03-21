import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../../drawing/models/pro_drawing_point.dart';
import '../../tools/echo_search_controller.dart';

// =============================================================================
// ✨ ECHO SEARCH PEN PAINTER — Neon Glow Query Ink (Final Boss)
//
// Features:
//   🌈 Gradient stroke (purple → cyan) with adaptive color override
//   🌊 Sonar ripple (3 staggered rings)
//   🕸️ Knowledge connections (neon lines between results)
//   📌 Pin markers (persistent glowing pins)
//   ✨ Particle dissolution fade-out
//   📝 Recognized text neon preview
// =============================================================================

class EchoSearchPenPainter extends CustomPainter {
  final EchoSearchController controller;
  final double animationValue;
  final Offset canvasOffset;
  final double canvasScale;
  /// Current timestamp in ms (passed from widget to avoid syscalls in paint).
  final int nowMs;

  /// Default neon gradient colors.
  static const Color _defaultPurple = Color(0xFF6C63FF);
  static const Color _defaultCyan = Color(0xFF00D4FF);
  static const Color _defaultGlow = Color(0xFF9D8FFF);

  /// 🎨 Adaptive colors derived from brush accent.
  late final Color neonPrimary;
  late final Color neonSecondary;
  late final Color neonGlow;

  EchoSearchPenPainter({
    required this.controller,
    required this.animationValue,
    required this.nowMs,
    this.canvasOffset = Offset.zero,
    this.canvasScale = 1.0,
  }) : super(repaint: controller) {
    // 🎨 Compute adaptive colors from brush accent
    final accent = controller.accentColor;
    if (accent != null) {
      final hsl = HSLColor.fromColor(accent);
      // Boost saturation and lightness for neon effect
      neonPrimary = hsl.withSaturation(
          (hsl.saturation + 0.3).clamp(0.0, 1.0))
          .withLightness((hsl.lightness * 0.6 + 0.3).clamp(0.35, 0.65))
          .toColor();
      neonSecondary = hsl.withHue((hsl.hue + 60) % 360)
          .withSaturation((hsl.saturation + 0.2).clamp(0.0, 1.0))
          .withLightness((hsl.lightness * 0.5 + 0.4).clamp(0.4, 0.7))
          .toColor();
      neonGlow = neonPrimary.withValues(alpha: 0.5);
    } else {
      neonPrimary = _defaultPurple;
      neonSecondary = _defaultCyan;
      neonGlow = _defaultGlow;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(canvasOffset.dx, canvasOffset.dy);
    canvas.scale(canvasScale);

    final isFading = controller.phase == EchoSearchPhase.fadingOut;
    double fadeProgress = 0.0;
    if (isFading && controller.fadeOutStartMs > 0) {
      final elapsed = nowMs - controller.fadeOutStartMs;
      fadeProgress = (elapsed / 600.0).clamp(0.0, 1.0);
    }

    final breathe = 0.3 + 0.15 * math.sin(animationValue * math.pi * 2);
    final globalAlpha = isFading ? (1.0 - fadeProgress) : 1.0;
    final rng = math.Random(42);

    // Draw committed strokes
    final totalStrokes = controller.committedStrokes.length.clamp(1, 999);
    for (int si = 0; si < controller.committedStrokes.length; si++) {
      final stroke = controller.committedStrokes[si];
      if (isFading) {
        _drawStrokeWithDissolution(canvas, stroke, fadeProgress, rng, globalAlpha);
      } else {
        _drawGradientStroke(canvas, stroke, breathe, globalAlpha, si / totalStrokes);
      }
    }

    // Draw current in-progress stroke
    if (controller.currentPoints.isNotEmpty) {
      _drawGradientStroke(canvas, controller.currentPoints, breathe, globalAlpha, 1.0);
    }

    // Phase indicator
    _drawPhaseIndicator(canvas);

    // 📝 Text preview
    if (controller.phase == EchoSearchPhase.previewing &&
        controller.recognizedQuery != null) {
      _drawTextPreview(canvas, controller.recognizedQuery!);
    }

    // 🌊 Sonar ripple
    if (controller.sonarTarget != null && controller.sonarStartMs > 0) {
      _drawSonarRipple(canvas, controller.sonarTarget!, controller.sonarStartMs);
    }

    // 🕸️ Knowledge connections between results
    if (controller.results.length > 1 &&
        controller.phase == EchoSearchPhase.flyingTo) {
      _drawKnowledgeConnections(canvas);
    }

    // 📌 Pin markers
    for (final pin in controller.pins) {
      _drawPinMarker(canvas, pin);
    }

    canvas.restore();
  }

  void _drawGradientStroke(
    Canvas canvas,
    List<ProDrawingPoint> points,
    double breathe,
    double alpha,
    double strokeProgress,
  ) {
    if (points.length < 2) {
      if (points.length == 1) {
        canvas.drawCircle(points.first.position, 3.0,
            Paint()..color = neonPrimary.withValues(alpha: alpha));
        canvas.drawCircle(points.first.position, 5.0,
            Paint()
              ..color = neonGlow.withValues(alpha: breathe * alpha)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0));
      }
      return;
    }

    final path = Path();
    path.moveTo(points.first.position.dx, points.first.position.dy);
    for (int i = 1; i < points.length; i++) {
      if (i < points.length - 1) {
        final xc = (points[i].position.dx + points[i + 1].position.dx) / 2;
        final yc = (points[i].position.dy + points[i + 1].position.dy) / 2;
        path.quadraticBezierTo(points[i].position.dx, points[i].position.dy, xc, yc);
      } else {
        path.lineTo(points[i].position.dx, points[i].position.dy);
      }
    }

    final startPt = points.first.position;
    final endPt = points.last.position;
    final gradientShift = strokeProgress * 0.3;
    final c1 = Color.lerp(neonPrimary, neonSecondary, gradientShift) ?? neonPrimary;
    final c2 = Color.lerp(neonPrimary, neonSecondary, 0.7 + gradientShift) ?? neonSecondary;

    final glowPaint = Paint()
      ..shader = ui.Gradient.linear(startPt, endPt, [
        neonGlow.withValues(alpha: breathe * alpha),
        neonSecondary.withValues(alpha: breathe * alpha * 0.6),
      ])
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0);

    final corePaint = Paint()
      ..shader = ui.Gradient.linear(startPt, endPt, [
        c1.withValues(alpha: alpha),
        c2.withValues(alpha: alpha),
      ])
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, corePaint);
  }

  void _drawStrokeWithDissolution(
    Canvas canvas,
    List<ProDrawingPoint> points,
    double progress,
    math.Random rng,
    double alpha,
  ) {
    if (points.isEmpty) return;
    final scatterRadius = progress * 40.0;
    final particleSize = 2.5 * (1.0 - progress * 0.7);
    final step = math.max(1, (points.length / 60).ceil());
    for (int i = 0; i < points.length; i += step) {
      final pt = points[i].position;
      final angle = rng.nextDouble() * math.pi * 2;
      final dist = rng.nextDouble() * scatterRadius;
      final scattered = Offset(
        pt.dx + math.cos(angle) * dist,
        pt.dy + math.sin(angle) * dist,
      );
      final t = i / points.length;
      final color = Color.lerp(neonPrimary, neonSecondary, t) ?? neonPrimary;
      canvas.drawCircle(scattered, particleSize,
          Paint()..color = color.withValues(alpha: alpha));
      if (i % 3 == 0) {
        canvas.drawCircle(scattered, particleSize * 2,
            Paint()
              ..color = neonGlow.withValues(alpha: alpha * 0.4)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0));
      }
    }
  }

  void _drawTextPreview(Canvas canvas, String text) {
    final allStrokes = [
      ...controller.committedStrokes,
      if (controller.currentPoints.isNotEmpty) controller.currentPoints,
    ];
    if (allStrokes.isEmpty) return;

    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity;
    for (final stroke in allStrokes) {
      for (final pt in stroke) {
        if (pt.position.dx < minX) minX = pt.position.dx;
        if (pt.position.dy < minY) minY = pt.position.dy;
        if (pt.position.dx > maxX) maxX = pt.position.dx;
      }
    }

    final centerX = (minX + maxX) / 2;
    final textY = minY - 35;
    final fadeIn = (animationValue * 4).clamp(0.0, 1.0);

    final textStyle = ui.TextStyle(
      color: neonSecondary.withValues(alpha: fadeIn),
      fontSize: 18,
      fontWeight: FontWeight.w600,
      shadows: [
        Shadow(color: neonGlow.withValues(alpha: fadeIn * 0.6), blurRadius: 12),
        Shadow(color: neonPrimary.withValues(alpha: fadeIn * 0.3), blurRadius: 20),
      ],
    );

    final paragraphBuilder = ui.ParagraphBuilder(
      ui.ParagraphStyle(textAlign: TextAlign.center),
    )..pushStyle(textStyle)..addText('"$text"');

    final paragraph = paragraphBuilder.build()
      ..layout(const ui.ParagraphConstraints(width: 300));

    canvas.drawParagraph(paragraph, Offset(
      centerX - paragraph.width / 2,
      textY - (1.0 - fadeIn) * 10,
    ));
  }

  void _drawSonarRipple(Canvas canvas, Offset center, int startMs) {
    final elapsed = nowMs - startMs;
    if (elapsed > 1200) return;
    for (int ring = 0; ring < 3; ring++) {
      final ringElapsed = elapsed - ring * 150;
      if (ringElapsed < 0) continue;
      final progress = (ringElapsed / 800.0).clamp(0.0, 1.0);
      final radius = 20.0 + progress * 120.0;
      final alpha = (1.0 - progress) * 0.5;
      canvas.drawCircle(center, radius, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 * (1.0 - progress * 0.5)
        ..color = neonSecondary.withValues(alpha: alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.0 + progress * 4.0));
    }
    if (elapsed < 600) {
      final dotAlpha = (1.0 - elapsed / 600.0).clamp(0.0, 0.8);
      canvas.drawCircle(center, 4.0,
          Paint()..color = neonSecondary.withValues(alpha: dotAlpha));
      canvas.drawCircle(center, 8.0, Paint()
        ..color = neonGlow.withValues(alpha: dotAlpha * 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0));
    }
  }

  /// 🕸️ Draw glowing neon connection lines between all search results.
  void _drawKnowledgeConnections(Canvas canvas) {
    final results = controller.results;
    if (results.length < 2) return;

    final breathe = 0.15 + 0.1 * math.sin(animationValue * math.pi * 2);

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = neonSecondary.withValues(alpha: breathe)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);

    final dotPaint = Paint()
      ..color = neonPrimary.withValues(alpha: breathe * 2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);

    // Connect sequential results with curved lines
    for (int i = 0; i < results.length - 1; i++) {
      final from = results[i].bounds.center;
      final to = results[i + 1].bounds.center;

      // Curved connection (quadratic bezier with midpoint offset)
      final mid = Offset(
        (from.dx + to.dx) / 2,
        (from.dy + to.dy) / 2 - 30, // Slight arc upward
      );

      final path = Path()
        ..moveTo(from.dx, from.dy)
        ..quadraticBezierTo(mid.dx, mid.dy, to.dx, to.dy);

      canvas.drawPath(path, linePaint);

      // Glowing dots at connection endpoints
      canvas.drawCircle(from, 3.0, dotPaint);
      canvas.drawCircle(to, 3.0, dotPaint);
    }
  }

  /// 📌 Draw a persistent pin marker.
  void _drawPinMarker(Canvas canvas, EchoPinMarker pin) {
    final elapsed = nowMs - pin.createdMs;
    final pulsePhase = (elapsed % 2000) / 2000.0;
    final pulse = 0.4 + 0.3 * math.sin(pulsePhase * math.pi * 2);

    // Glowing diamond shape
    final center = pin.center;
    final size = 8.0;
    final path = Path()
      ..moveTo(center.dx, center.dy - size) // Top
      ..lineTo(center.dx + size * 0.7, center.dy) // Right
      ..lineTo(center.dx, center.dy + size) // Bottom
      ..lineTo(center.dx - size * 0.7, center.dy) // Left
      ..close();

    // Glow
    canvas.drawPath(path, Paint()
      ..color = neonPrimary.withValues(alpha: pulse)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0));

    // Core
    canvas.drawPath(path, Paint()
      ..color = neonSecondary.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill);

    // Outline
    canvas.drawPath(path, Paint()
      ..color = neonPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0);
  }

  void _drawPhaseIndicator(Canvas canvas) {
    if (controller.phase == EchoSearchPhase.recognizing) {
      final allStrokes = [
        ...controller.committedStrokes,
        if (controller.currentPoints.isNotEmpty) controller.currentPoints,
      ];
      if (allStrokes.isEmpty) return;
      final lastStroke = allStrokes.last;
      if (lastStroke.isEmpty) return;
      final lastPoint = lastStroke.last.position;
      for (int i = 0; i < 3; i++) {
        final phase = animationValue * math.pi * 4 + i * (math.pi * 2 / 3);
        final alpha = 0.3 + 0.7 * ((math.sin(phase) + 1) / 2);
        final color = Color.lerp(neonPrimary, neonSecondary, i / 2.0) ?? neonPrimary;
        canvas.drawCircle(
          Offset(lastPoint.dx + 15 + i * 10, lastPoint.dy),
          2.5,
          Paint()..color = color.withValues(alpha: alpha),
        );
      }
    }
  }

  @override
  bool shouldRepaint(EchoSearchPenPainter old) =>
      old.animationValue != animationValue ||
      old.canvasOffset != canvasOffset ||
      old.canvasScale != canvasScale;
}

class EchoSearchPenOverlay extends StatefulWidget {
  final EchoSearchController controller;
  final Offset canvasOffset;
  final double canvasScale;

  const EchoSearchPenOverlay({
    super.key,
    required this.controller,
    this.canvasOffset = Offset.zero,
    this.canvasScale = 1.0,
  });

  @override
  State<EchoSearchPenOverlay> createState() => _EchoSearchPenOverlayState();
}

class _EchoSearchPenOverlayState extends State<EchoSearchPenOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breathController;

  @override
  void initState() {
    super.initState();
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _breathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _breathController,
      builder: (context, _) {
        return CustomPaint(
          painter: EchoSearchPenPainter(
            controller: widget.controller,
            animationValue: _breathController.value,
            nowMs: DateTime.now().millisecondsSinceEpoch,
            canvasOffset: widget.canvasOffset,
            canvasScale: widget.canvasScale,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}
