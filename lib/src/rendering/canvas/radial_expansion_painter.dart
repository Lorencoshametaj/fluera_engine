import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../ai/radial_expansion_controller.dart';

// =============================================================================
// 🌟 RADIAL EXPANSION PAINTER v3 — Full Polish Edition
// New: pulsing source ring, bounce landing rendering, collapse animation,
//      outer orbit size differentiation, improved trails.
// =============================================================================

class RadialExpansionPainter extends CustomPainter {
  final RadialExpansionController controller;
  final Offset canvasOffset;
  final double canvasScale;
  final double animationTime;

  RadialExpansionPainter({
    required this.controller,
    required this.canvasOffset,
    required this.canvasScale,
    required this.animationTime,
  });

  static const Color _neonCyan   = Color(0xFF00E5FF);
  static const Color _neonViolet = Color(0xFFAA00FF);
  static const Color _neonGold   = Color(0xFFFFD600);
  static const Color _neonPink   = Color(0xFFFF4081);
  static const Color _glassWhite = Color(0xCCFFFFFF);
  static const List<Color> _bubbleGrad = [Color(0xFF0A1628), Color(0xFF0D2244)];
  static const List<Color> _accentColors = [_neonCyan, _neonViolet, _neonGold, _neonPink, Color(0xFF00FF88), _neonViolet];

  @override
  void paint(Canvas canvas, Size size) {
    final phase = controller.phase;
    if (phase == RadialExpansionPhase.idle) return;

    canvas.save();
    canvas.translate(canvasOffset.dx, canvasOffset.dy);
    canvas.scale(canvasScale);

    final src = controller.sourceCenter;

    switch (phase) {
      case RadialExpansionPhase.charging:
        _drawChargeRing(canvas, src);
      case RadialExpansionPhase.generating:
        _drawGeneratingSpinner(canvas, src);
      case RadialExpansionPhase.presenting:
        _drawSourceActiveRing(canvas, src);
        _drawPresentingPhase(canvas, src);
      default: break;
    }

    canvas.restore();
  }

  // ── Charge ring ────────────────────────────────────────────────────────────

  void _drawChargeRing(Canvas canvas, Offset src) {
    final progress = controller.chargeProgress;
    final t = animationTime;
    final ringRadius = 30.0 + progress * 55.0;

    canvas.drawCircle(src, ringRadius, Paint()
      ..color = _neonCyan.withOpacity((0.4 + 0.4 * math.sin(t * 8)) * progress)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5);

    canvas.drawCircle(src, 28.0, Paint()
      ..shader = ui.Gradient.radial(src, 28.0, [_neonCyan.withOpacity(0.25 * progress), Colors.transparent]));

    if (progress > 0.1) {
      final rect = Rect.fromCircle(center: src, radius: ringRadius - 4);
      canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * progress, false,
        Paint()..color = _neonCyan.withOpacity(0.7 * progress)..style = PaintingStyle.stroke..strokeWidth = 3.0..strokeCap = StrokeCap.round);
    }

    if (progress >= 0.95) {
      for (int i = 0; i < 6; i++) {
        final a = (2 * math.pi / 6) * i + t * 3;
        canvas.drawCircle(Offset(src.dx + ringRadius * math.cos(a), src.dy + ringRadius * math.sin(a)), 3.5,
          Paint()..color = _neonGold.withOpacity(0.8));
      }
    }
  }

  // ── Generating spinner ─────────────────────────────────────────────────────

  void _drawGeneratingSpinner(Canvas canvas, Offset src) {
    const orbitR = 38.0, dotCount = 6;
    for (int i = 0; i < dotCount; i++) {
      final p = animationTime * 2.5 + (2 * math.pi / dotCount) * i;
      final dp = Offset(src.dx + orbitR * math.cos(p), src.dy + orbitR * math.sin(p));
      canvas.drawCircle(dp, 4.5,
        Paint()..color = _neonCyan.withOpacity((0.2 + 0.8 * ((i + 1) / dotCount)).clamp(0, 1)));
    }
    canvas.drawCircle(src, 12.0, Paint()
      ..shader = ui.Gradient.radial(src, 12.0, [_neonCyan.withOpacity(0.3), Colors.transparent]));
  }

  // ── Source active ring (during presenting) ─────────────────────────────────

  void _drawSourceActiveRing(Canvas canvas, Offset src) {
    final t = animationTime;
    // Slow breathe (3s cycle)
    final breathe = 0.5 + 0.5 * math.sin(t * 2.0);
    final r1 = 22.0 + breathe * 8.0;

    canvas.drawCircle(src, r1, Paint()
      ..color = _neonCyan.withOpacity(0.12 + 0.08 * breathe)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0);

    // Inner solid glow
    canvas.drawCircle(src, 14.0, Paint()
      ..shader = ui.Gradient.radial(src, 14.0, [_neonCyan.withOpacity(0.2 + 0.1 * breathe), Colors.transparent]));

    // Rotating orbit dot
    final dotA = t * 1.5;
    canvas.drawCircle(Offset(src.dx + r1 * math.cos(dotA), src.dy + r1 * math.sin(dotA)), 3.0,
      Paint()..color = _neonCyan.withOpacity(0.9));
  }

  // ── Presenting phase ───────────────────────────────────────────────────────

  void _drawPresentingPhase(Canvas canvas, Offset src) {
    // 🌟 Draw confirm beams first (behind bubbles)
    for (final beam in controller.beams) {
      if (beam.opacity <= 0.01) continue;
      final beamEnd = Offset.lerp(beam.from, beam.to, beam.progress.clamp(0.0, 1.0))!;
      canvas.drawLine(beam.from, beamEnd, Paint()
        ..color = _neonCyan.withOpacity((beam.opacity * 0.75).clamp(0.0, 1.0))
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round);
      // Secondary glow beam
      canvas.drawLine(beam.from, beamEnd, Paint()
        ..color = _neonCyan.withOpacity((beam.opacity * 0.25).clamp(0.0, 1.0))
        ..strokeWidth = 5.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round);
    }

    // ✨ Draw confirm particles
    const particleColors = [_neonCyan, _neonViolet, _neonGold, _neonPink];
    for (final p in controller.particles) {
      if (p.opacity <= 0.01) continue;
      final color = particleColors[p.colorIndex % particleColors.length]
          .withOpacity(p.opacity.clamp(0.0, 1.0));
      canvas.drawCircle(p.position, p.size, Paint()..color = color);
    }

    final bubbles = controller.bubbles;
    for (int i = 0; i < bubbles.length; i++) {
      final bubble = bubbles[i];
      if (bubble.opacity <= 0.01) continue;

      final accent = _accentColors[i % _accentColors.length];
      final pos = bubble.currentPosition(src);

      // Trail during launch
      if (bubble.state == GhostBubbleState.launching && bubble.launchProgress < 1.0) {
        _drawLaunchTrail(canvas, src, bubble.targetPosition, accent, bubble.launchProgress, bubble.opacity);
      }

      // Dashed connection line
      if (bubble.state == GhostBubbleState.idle ||
          bubble.state == GhostBubbleState.bouncing ||
          bubble.state == GhostBubbleState.dragging) {
        _drawDashedLine(canvas, src, pos, accent, bubble.opacity * 0.45);
      }

      // Elastic line during drag
      if (bubble.state == GhostBubbleState.dragging && bubble.dragOffset != Offset.zero) {
        _drawElasticLine(canvas, bubble.targetPosition, pos, accent, bubble);
      }

      // Bubble body
      _drawBubble(canvas, bubble, pos, accent, i);

      // Drag indicator
      if (bubble.state == GhostBubbleState.dragging) {
        _drawDragIndicator(canvas, bubble, pos, accent, src);
      }
    }
  }

  void _drawLaunchTrail(Canvas canvas, Offset from, Offset to, Color accent, double progress, double opacity) {
    const steps = 6;
    for (int s = 0; s < steps; s++) {
      final t = progress * (1.0 - (s + 1) / steps);
      final trailPos = Offset.lerp(from, to, t.clamp(0, 1))!;
      final trailOpacity = opacity * (1.0 - s / steps) * 0.5;
      final r = 5.0 - s * 0.7;
      if (r > 0.5) canvas.drawCircle(trailPos, r, Paint()..color = accent.withOpacity(trailOpacity.clamp(0, 1)));
    }
  }

  void _drawDashedLine(Canvas canvas, Offset from, Offset to, Color color, double opacity) {
    if (opacity <= 0.01) return;
    final dir = to - from;
    final dist = dir.distance;
    if (dist < 1) return;
    final norm = dir / dist;
    final paint = Paint()..color = color.withOpacity(opacity.clamp(0, 1))..strokeWidth = 1.5..style = PaintingStyle.stroke;
    const dashLen = 8.0, gapLen = 6.0;
    double d = 22.0;
    while (d < dist - 22.0) {
      final end = math.min(d + dashLen, dist - 22.0);
      canvas.drawLine(from + norm * d, from + norm * end, paint);
      d += dashLen + gapLen;
    }
  }

  void _drawElasticLine(Canvas canvas, Offset anchor, Offset dragged, Color accent, GhostBubble bubble) {
    final stretchFraction = (bubble.dragOffset.distance / (RadialExpansionController.innerOrbitRadius * 0.8)).clamp(0.0, 1.0);
    final color = Color.lerp(accent, _neonCyan, stretchFraction)!.withOpacity(0.7 + 0.3 * stretchFraction);
    canvas.drawLine(anchor, dragged, Paint()
      ..color = color..strokeWidth = 1.5 + stretchFraction * 1.5..style = PaintingStyle.stroke..strokeCap = StrokeCap.round);
  }

  void _drawDragIndicator(Canvas canvas, GhostBubble bubble, Offset pos, Color accent, Offset src) {
    final dragDist = bubble.dragOffset.distance;
    final confirmThreshold = RadialExpansionController.innerOrbitRadius * RadialExpansionController.confirmThresholdFraction;
    final toTarget = bubble.targetPosition - src;
    final dot = toTarget.dx * bubble.dragOffset.dx + toTarget.dy * bubble.dragOffset.dy;
    final isOutward = dot >= 0;

    if (isOutward && dragDist >= confirmThreshold * 0.6) {
      final f = ((dragDist - confirmThreshold * 0.6) / (confirmThreshold * 0.4)).clamp(0.0, 1.0);
      canvas.drawCircle(pos, 34.0 + f * 8.0, Paint()..color = _neonCyan.withOpacity(0.6 * f)..style = PaintingStyle.stroke..strokeWidth = 2.5);
      if (f > 0.6) {
        final path = Path()..moveTo(pos.dx - 10, pos.dy)..lineTo(pos.dx - 2, pos.dy + 8)..lineTo(pos.dx + 12, pos.dy - 8);
        canvas.drawPath(path, Paint()..color = _neonCyan.withOpacity(f)..strokeWidth = 2.5..strokeCap = StrokeCap.round..style = PaintingStyle.stroke);
      }
    } else if (!isOutward && dragDist > 20) {
      canvas.drawCircle(pos, 30.0, Paint()..color = _neonPink.withOpacity(0.5)..style = PaintingStyle.stroke..strokeWidth = 2.0);
    }
  }

  void _drawBubble(Canvas canvas, GhostBubble bubble, Offset pos, Color accent, int index) {
    final floatY = bubble.state == GhostBubbleState.dragging ? 0.0 : math.sin(bubble.floatPhase) * 3.5;
    final floatPos = Offset(pos.dx, pos.dy + floatY);
    final scale = bubble.scale.clamp(0, 1.6);
    final opacity = bubble.opacity.clamp(0, 1);
    if (scale <= 0.01 || opacity <= 0.01) return;

    // ✨ Confirming: expanding spark ring
    if (bubble.state == GhostBubbleState.confirming) {
      final ex = 1.0 + (1.0 - opacity) * 2.5;
      canvas.drawCircle(floatPos, 32.0 * ex, Paint()..color = accent.withOpacity((opacity * 0.8).clamp(0, 1))..style = PaintingStyle.stroke..strokeWidth = 3.0);
      canvas.drawCircle(floatPos, 46.0 * ex, Paint()..color = _neonCyan.withOpacity((opacity * 0.35).clamp(0, 1))..style = PaintingStyle.stroke..strokeWidth = 1.5);
      final dotP = Paint()..color = accent.withOpacity((opacity * 0.9).clamp(0, 1));
      for (int i = 0; i < 8; i++) {
        final a = (2 * math.pi / 8) * i;
        final sr = 44.0 * ex;
        canvas.drawCircle(Offset(floatPos.dx + sr * math.cos(a), floatPos.dy + sr * math.sin(a)), 2.5, dotP);
      }
    }

    canvas.save();
    canvas.translate(floatPos.dx, floatPos.dy);
    canvas.scale(scale.toDouble());

    // Outer orbit: slightly smaller bubbles
    final r = bubble.isOuterOrbit ? 26.0 : 32.0;
    final glowR = bubble.isOuterOrbit ? 38.0 : 45.0;

    // Outer glow
    canvas.drawCircle(Offset.zero, glowR, Paint()
      ..shader = ui.Gradient.radial(Offset.zero, glowR, [accent.withOpacity(0.18 * opacity), Colors.transparent]));

    // Glass body
    canvas.drawCircle(Offset.zero, r, Paint()
      ..shader = ui.Gradient.radial(const Offset(-8, -8), r * 1.2,
        [_bubbleGrad[0].withOpacity(opacity * 0.95), _bubbleGrad[1].withOpacity(opacity * 0.85)]));

    // Accent border
    canvas.drawCircle(Offset.zero, r, Paint()
      ..color = accent.withOpacity(opacity * 0.9)..style = PaintingStyle.stroke..strokeWidth = 1.8);

    // Specular
    canvas.drawCircle(Offset(-r * 0.28, -r * 0.28), r * 0.18, Paint()
      ..color = Colors.white.withOpacity(0.08 * opacity));

    _drawBubbleLabel(canvas, bubble.label, opacity.toDouble(), accent, r);
    canvas.restore();
  }

  void _drawBubbleLabel(Canvas canvas, String label, double opacity, Color accent, double r) {
    final fontSize = r > 28 ? 10.5 : 9.0;
    final maxW = r * 1.6;
    final words = label.split(' ');
    final String line1, line2;
    if (words.length <= 2) { line1 = label; line2 = ''; }
    else {
      final mid = words.length ~/ 2;
      line1 = words.sublist(0, mid).join(' ');
      line2 = words.sublist(mid).join(' ');
    }

    void drawLine(String text, double y) {
      if (text.isEmpty) return;
      final tp = TextPainter(
        text: TextSpan(text: text, style: TextStyle(color: _glassWhite.withOpacity(opacity), fontSize: fontSize, fontWeight: FontWeight.w600, letterSpacing: 0.3, height: 1.2)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: maxW);
      tp.paint(canvas, Offset(-tp.width / 2, y));
    }

    if (line2.isEmpty) {
      drawLine(line1, -6.5);
    } else {
      drawLine(line1, -13.0);
      drawLine(line2, -1.0);
    }
  }

  @override
  bool shouldRepaint(RadialExpansionPainter old) => true;
}
