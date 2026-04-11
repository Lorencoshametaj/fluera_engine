// ============================================================================
// 🎨 CELEBRATION PAINTERS — Visual rendering of pedagogical celebrations
//
// Specifica: A13.8-10 → A13.8-18
//
// These painters render the 5 celebration types directly on the Canvas.
// Each painter produces a LIGHTWEIGHT, GPU-friendly animation using only
// Canvas primitives (arcs, lines, circles) — no images, no shaders.
//
// DESIGN CONSTRAINTS (A13.8):
//   - Max duration: 2000ms
//   - No blocking overlay
//   - No sound
//   - Colors: warm, desaturated, non-distracting
//   - Uses the celebration's color and anchor position
//
// RENDERING:
//   Each painter receives a normalized progress value (0.0 → 1.0)
//   and draws on a Canvas. The host widget drives the animation
//   via AnimationController and calls repaint.
//
// ARCHITECTURE:
//   Pure CustomPainter subclasses — no state, no dependencies.
//   The host overlay provides the Canvas and animation progress.
//
// THREAD SAFETY: Main isolate only (UI thread).
// ============================================================================

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'celebration_controller.dart';

/// 🎨 Particle data for confetti/spark effects.
class CelebrationParticle {
  final double x;
  final double y;
  final double vx;
  final double vy;
  final double size;
  final Color color;
  final double rotation;

  const CelebrationParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.color,
    required this.rotation,
  });

  /// Advance the particle by [t] (0.0–1.0).
  CelebrationParticle at(double t) => CelebrationParticle(
        x: x + vx * t,
        y: y + vy * t + 50 * t * t, // Gravity
        vx: vx,
        vy: vy,
        size: size * (1.0 - t * 0.5), // Shrink
        color: color.withValues(alpha: (1.0 - t).clamp(0, 1)),
        rotation: rotation + t * 3.14,
      );
}

/// 🎨 Generates particles for a celebration type.
class CelebrationParticleSystem {
  CelebrationParticleSystem._();

  /// Generate particles for a recall-perfect celebration.
  /// Subtle green sparks from canvas edges.
  static List<CelebrationParticle> recallPerfect(Size canvasSize) {
    final rng = math.Random(42);
    return List.generate(20, (i) {
      final edge = i % 4; // 0=top, 1=right, 2=bottom, 3=left
      double x, y, vx, vy;
      switch (edge) {
        case 0: // Top
          x = rng.nextDouble() * canvasSize.width;
          y = 0;
          vx = (rng.nextDouble() - 0.5) * 40;
          vy = rng.nextDouble() * 30 + 10;
          break;
        case 1: // Right
          x = canvasSize.width;
          y = rng.nextDouble() * canvasSize.height;
          vx = -(rng.nextDouble() * 30 + 10);
          vy = (rng.nextDouble() - 0.5) * 40;
          break;
        case 2: // Bottom
          x = rng.nextDouble() * canvasSize.width;
          y = canvasSize.height;
          vx = (rng.nextDouble() - 0.5) * 40;
          vy = -(rng.nextDouble() * 30 + 10);
          break;
        default: // Left
          x = 0;
          y = rng.nextDouble() * canvasSize.height;
          vx = rng.nextDouble() * 30 + 10;
          vy = (rng.nextDouble() - 0.5) * 40;
          break;
      }
      return CelebrationParticle(
        x: x,
        y: y,
        vx: vx,
        vy: vy,
        size: rng.nextDouble() * 4 + 2,
        color: Color.fromRGBO(
          102 + rng.nextInt(50),
          187 + rng.nextInt(50),
          106 + rng.nextInt(50),
          1,
        ),
        rotation: rng.nextDouble() * 6.28,
      );
    });
  }

  /// Generate particles for a bridge-formed celebration.
  /// Gold sparks from the anchor point.
  static List<CelebrationParticle> bridgeSparks(Offset anchor) {
    final rng = math.Random(77);
    return List.generate(12, (i) {
      final angle = (i / 12) * 2 * math.pi;
      return CelebrationParticle(
        x: anchor.dx,
        y: anchor.dy,
        vx: math.cos(angle) * (rng.nextDouble() * 40 + 20),
        vy: math.sin(angle) * (rng.nextDouble() * 40 + 20),
        size: rng.nextDouble() * 3 + 2,
        color: Color.fromRGBO(
          255,
          215 + rng.nextInt(40),
          0,
          1,
        ),
        rotation: rng.nextDouble() * 6.28,
      );
    });
  }
}

/// 🎨 Master Celebration Painter.
///
/// Renders any [CelebrationEvent] based on its type and progress.
///
/// Usage:
/// ```dart
/// CustomPaint(
///   painter: CelebrationPainter(
///     event: celebrationEvent,
///     progress: animationController.value, // 0.0 → 1.0
///   ),
/// )
/// ```
class CelebrationPainter extends CustomPainter {
  final CelebrationEvent event;
  final double progress;

  /// Pre-computed particles (cached to avoid per-frame allocations).
  /// If null, particles are generated on first paint and cached.
  List<CelebrationParticle>? _cachedParticles;
  Size? _cachedSize;

  CelebrationPainter({
    required this.event,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;

    switch (event.type) {
      case CelebrationType.recallPerfect:
        _paintEdgePulse(canvas, size);
        break;
      case CelebrationType.stabilityGain:
        _paintNodeGlow(canvas, size);
        break;
      case CelebrationType.bridgeFormed:
        _paintBridgePulse(canvas, size);
        break;
      case CelebrationType.fogCleared:
        _paintCenterFlash(canvas, size);
        break;
      case CelebrationType.firstRecall:
        _paintWarmPulse(canvas, size);
        break;
    }
  }

  /// Green pulse on canvas edges (recallPerfect).
  void _paintEdgePulse(Canvas canvas, Size size) {
    final opacity = _bellCurve(progress);
    final thickness = 4.0 + progress * 8.0;

    final paint = Paint()
      ..color = event.color.withValues(alpha: opacity * 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    // Draw glowing border
    final inset = thickness / 2;
    canvas.drawRRect(
      RRect.fromLTRBR(
        inset,
        inset,
        size.width - inset,
        size.height - inset,
        const Radius.circular(12),
      ),
      paint,
    );

    // Particles (cached to avoid allocations every frame)
    if (_cachedParticles == null || _cachedSize != size) {
      _cachedParticles = CelebrationParticleSystem.recallPerfect(size);
      _cachedSize = size;
    }
    _drawParticles(canvas, _cachedParticles!, progress);
  }

  /// Gold glow around a node (stabilityGain).
  void _paintNodeGlow(Canvas canvas, Size size) {
    final anchor = event.anchorPosition ?? Offset(size.width / 2, size.height / 2);
    final opacity = _bellCurve(progress);
    final radius = 20.0 + progress * 30.0;

    final paint = Paint()
      ..color = event.color.withValues(alpha: opacity * 0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);

    canvas.drawCircle(anchor, radius, paint);

    // Inner bright core
    final corePaint = Paint()
      ..color = event.color.withValues(alpha: opacity * 0.8)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    canvas.drawCircle(anchor, radius * 0.4, corePaint);
  }

  /// Gold pulse along a bridge line (bridgeFormed).
  void _paintBridgePulse(Canvas canvas, Size size) {
    final anchor = event.anchorPosition ?? Offset(size.width / 2, size.height / 2);
    final opacity = _bellCurve(progress);

    // Expanding ring
    final radius = 10.0 + progress * 50.0;
    final paint = Paint()
      ..color = event.color.withValues(alpha: opacity * 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0 * (1.0 - progress)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    canvas.drawCircle(anchor, radius, paint);

    // Second offset ring
    canvas.drawCircle(anchor, radius * 0.6, paint);

    // Sparks (cached — anchor doesn't change during animation)
    if (_cachedParticles == null || _cachedSize == null) {
      _cachedParticles = CelebrationParticleSystem.bridgeSparks(anchor);
    }
    _drawParticles(canvas, _cachedParticles!, progress);
  }

  /// White flash from center (fogCleared).
  void _paintCenterFlash(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final opacity = _bellCurve(progress) * 0.3;
    final maxRadius = math.max(size.width, size.height);

    final gradient = RadialGradient(
      colors: [
        event.color.withValues(alpha: opacity),
        event.color.withValues(alpha: 0),
      ],
      stops: const [0.0, 1.0],
    );

    final paint = Paint()
      ..shader = gradient.createShader(
        Rect.fromCircle(center: center, radius: maxRadius * progress),
      );

    canvas.drawCircle(center, maxRadius * progress, paint);
  }

  /// Warm amber pulse (firstRecall).
  void _paintWarmPulse(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final opacity = _bellCurve(progress);
    final radius = 30.0 + progress * 60.0;

    // Soft amber glow
    final gradient = RadialGradient(
      colors: [
        event.color.withValues(alpha: opacity * 0.5),
        event.color.withValues(alpha: 0),
      ],
    );

    final paint = Paint()
      ..shader = gradient.createShader(
        Rect.fromCircle(center: center, radius: radius),
      );

    canvas.drawCircle(center, radius, paint);

    // Pulsing inner ring
    final ringPaint = Paint()
      ..color = event.color.withValues(alpha: opacity * 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    canvas.drawCircle(center, radius * 0.5, ringPaint);
  }

  /// Draw particles at the given progress.
  void _drawParticles(
    Canvas canvas,
    List<CelebrationParticle> particles,
    double t,
  ) {
    for (final particle in particles) {
      final p = particle.at(t);
      final paint = Paint()..color = p.color;

      canvas.save();
      canvas.translate(p.x, p.y);
      canvas.rotate(p.rotation);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size),
        paint,
      );
      canvas.restore();
    }
  }

  /// Bell curve: 0→1→0 with peak at t=0.3 (fast in, slow out).
  double _bellCurve(double t) {
    // Fast attack, slow decay
    if (t < 0.3) return t / 0.3;
    return 1.0 - ((t - 0.3) / 0.7);
  }

  @override
  bool shouldRepaint(CelebrationPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.event != event;
}

/// 🎨 Message painter for celebration text.
///
/// Renders the celebration message as a floating label above the canvas.
///
/// Usage:
/// ```dart
/// CustomPaint(
///   painter: CelebrationMessagePainter(
///     message: event.message,
///     progress: animationController.value,
///     color: event.color,
///   ),
/// )
/// ```
class CelebrationMessagePainter extends CustomPainter {
  final String message;
  final double progress;
  final Color color;
  final double fontScale;

  CelebrationMessagePainter({
    required this.message,
    required this.progress,
    required this.color,
    this.fontScale = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;

    final opacity = _textOpacity(progress);
    final yOffset = size.height * 0.15 - (progress * 20); // Float up

    final fontSize = 18.0 * fontScale;

    final paragraphBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: ui.TextAlign.center,
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
    ))
      ..pushStyle(ui.TextStyle(
        color: color.withValues(alpha: opacity),
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      ))
      ..addText(message);

    final paragraph = paragraphBuilder.build()
      ..layout(ui.ParagraphConstraints(width: size.width));

    canvas.drawParagraph(
      paragraph,
      Offset(0, yOffset),
    );
  }

  double _textOpacity(double t) {
    // Fade in 0→0.2, hold 0.2→0.7, fade out 0.7→1.0
    if (t < 0.2) return t / 0.2;
    if (t < 0.7) return 1.0;
    return 1.0 - ((t - 0.7) / 0.3);
  }

  @override
  bool shouldRepaint(CelebrationMessagePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.message != message;
}
