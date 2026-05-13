import 'package:flutter/material.dart';

// ============================================================================
// 🔲 LASSO RIPPLE PAINTER — gestural-lasso closing animation
//
// Originally lived as `_LassoRipplePainter` in `parts/ui/_ui_overlays.dart`
// (a `part of fluera_canvas_screen.dart` file). Extracted to this public
// file so [FlueraCanvasView] can reuse the same FX outside the screen
// library.
// ============================================================================

/// Paints an expanding, fading ripple at a given center — used for the
/// gestural lasso closing animation. The animation timing/center is
/// driven externally; this painter renders a single frame at the supplied
/// `radius` + `opacity`.
class LassoRipplePainter extends CustomPainter {
  final Offset center;
  final double radius;
  final double opacity;

  LassoRipplePainter({
    required this.center,
    required this.radius,
    required this.opacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Outer ring glow
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xFF818CF8).withValues(alpha: opacity * 0.3)
        ..strokeWidth = 3.0
        ..style = PaintingStyle.stroke
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.15),
    );
    // Inner ring
    canvas.drawCircle(
      center,
      radius * 0.6,
      Paint()
        ..color = const Color(0xFF22D3EE).withValues(alpha: opacity * 0.2)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.1),
    );
    // Core flash
    canvas.drawCircle(
      center,
      radius * 0.2,
      Paint()
        ..color = Colors.white.withValues(alpha: opacity * 0.4)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.1),
    );
  }

  @override
  bool shouldRepaint(LassoRipplePainter oldDelegate) =>
      center != oldDelegate.center ||
      radius != oldDelegate.radius ||
      opacity != oldDelegate.opacity;
}
