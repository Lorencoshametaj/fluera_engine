import 'package:flutter/material.dart';

import '../../canvas/infinite_canvas_controller.dart';

// ============================================================================
// 💥 SCRATCH-OUT PARTICLES — explosion FX for batch stroke deletion
//
// Originally lived as `_ScratchOutParticle` / `_ScratchOutParticleWidget`
// / `_ScratchOutParticlePainter` in `parts/ui/_ui_canvas_layer.dart` (a
// `part of fluera_canvas_screen.dart` file). Extracted to this public
// file so [FlueraCanvasView] can render the FX outside the screen
// library.
// ============================================================================

/// Particle data for the scratch-out dissolve effect — one per fragment.
class ScratchOutParticle {
  final Offset position;
  final Offset velocity;
  final Color color;
  final double size;

  const ScratchOutParticle({
    required this.position,
    required this.velocity,
    required this.color,
    required this.size,
  });
}

/// 💥 Particle dissolve effect — colored particles fly out from a freshly
/// scratched-out area, with gravity, fade, and an optional batch-count
/// badge. Self-contained: drives its own 500 ms animation controller.
class ScratchOutParticleWidget extends StatefulWidget {
  final List<ScratchOutParticle> particles;
  final Rect bounds;
  final InfiniteCanvasController canvasController;
  final int deleteCount;

  const ScratchOutParticleWidget({
    super.key,
    required this.particles,
    required this.bounds,
    required this.canvasController,
    required this.deleteCount,
  });

  @override
  State<ScratchOutParticleWidget> createState() =>
      _ScratchOutParticleWidgetState();
}

class _ScratchOutParticleWidgetState extends State<ScratchOutParticleWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) {
        return CustomPaint(
          painter: _ScratchOutParticlePainter(
            particles: widget.particles,
            canvasController: widget.canvasController,
            progress: _anim.value,
            deleteCount: widget.deleteCount,
          ),
        );
      },
    );
  }
}

class _ScratchOutParticlePainter extends CustomPainter {
  final List<ScratchOutParticle> particles;
  final InfiniteCanvasController canvasController;
  final double progress;
  final int deleteCount;

  static const double _gravity = 400.0; // px/s² downward

  _ScratchOutParticlePainter({
    required this.particles,
    required this.canvasController,
    required this.progress,
    required this.deleteCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final t = Curves.easeOut.transform(progress);
    final opacity = (1.0 - t).clamp(0.0, 1.0);
    if (opacity <= 0) return;

    final dt = progress * 0.5; // 500ms → 0.5s real time

    final paint = Paint()..style = PaintingStyle.fill;

    for (final p in particles) {
      final screenPos = canvasController.canvasToScreen(p.position);
      final x = screenPos.dx + p.velocity.dx * dt;
      final y = screenPos.dy + p.velocity.dy * dt + 0.5 * _gravity * dt * dt;
      final s = p.size * (1.0 - t * 0.6);

      paint.color = p.color.withValues(alpha: opacity * 0.8);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, y), width: s, height: s),
          Radius.circular(s * 0.3),
        ),
        paint,
      );
    }

    // Count badge for large deletions
    if (deleteCount > 5 && t < 0.7 && particles.isNotEmpty) {
      final badgeOpacity = (1.0 - t / 0.7).clamp(0.0, 1.0);
      final centerScreen = canvasController.canvasToScreen(
        particles.first.position,
      );
      final badgePaint = Paint()
        ..color = Colors.red.withValues(alpha: badgeOpacity * 0.85)
        ..style = PaintingStyle.fill;
      final badgeRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(centerScreen.dx, centerScreen.dy - 30),
          width: 80,
          height: 28,
        ),
        const Radius.circular(14),
      );
      canvas.drawRRect(badgeRect, badgePaint);

      final tp = TextPainter(
        text: TextSpan(
          text: '🧹 $deleteCount',
          style: TextStyle(
            color: Colors.white.withValues(alpha: badgeOpacity),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          centerScreen.dx - tp.width / 2,
          centerScreen.dy - 30 - tp.height / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScratchOutParticlePainter old) =>
      progress != old.progress;
}
