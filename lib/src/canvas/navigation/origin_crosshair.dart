import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../infinite_canvas_controller.dart';

/// ✛ Origin crosshair — a subtle "+" marker at canvas position (0, 0).
///
/// DESIGN PRINCIPLES:
/// - Provides a persistent spatial landmark for orientation.
/// - Semi-transparent, non-intrusive — visible but doesn't compete with content.
/// - Only appears when the origin is within the visible viewport.
/// - Scales inversely with zoom so it stays the same screen size.
/// - Adapts color based on canvas background luminance.
///
/// Inspired by Figma's origin indicator.
class OriginCrosshair extends StatelessWidget {
  final InfiniteCanvasController controller;
  final Size viewportSize;

  /// Canvas background color — used for adaptive styling.
  final Color canvasBackground;

  /// Screen-space size of the crosshair arms (in pixels).
  static const double kArmLength = 12.0;

  /// Screen-space thickness of the crosshair lines.
  static const double kLineWidth = 1.0;

  const OriginCrosshair({
    super.key,
    required this.controller,
    required this.viewportSize,
    this.canvasBackground = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        // Convert canvas origin (0, 0) to screen coordinates.
        final screenPos = controller.canvasToScreen(Offset.zero);

        // Check if origin is within the visible screen area (with margin).
        const margin = 50.0;
        if (screenPos.dx < -margin ||
            screenPos.dx > viewportSize.width + margin ||
            screenPos.dy < -margin ||
            screenPos.dy > viewportSize.height + margin) {
          return const SizedBox.shrink();
        }

        final lum = canvasBackground.computeLuminance();
        final color =
            lum > 0.5
                ? Colors.black.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.18);

        return Stack(
          children: [
            Positioned(
              left: screenPos.dx - kArmLength,
              top: screenPos.dy - kArmLength,
              child: IgnorePointer(
                child: CustomPaint(
                  size: const Size(kArmLength * 2, kArmLength * 2),
                  painter: _CrosshairPainter(color: color),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Paints a simple "+" crosshair.
class _CrosshairPainter extends CustomPainter {
  final Color color;

  _CrosshairPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..strokeWidth = OriginCrosshair.kLineWidth
          ..strokeCap = StrokeCap.round;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final arm = OriginCrosshair.kArmLength;

    // Horizontal arm
    canvas.drawLine(Offset(cx - arm, cy), Offset(cx + arm, cy), paint);

    // Vertical arm
    canvas.drawLine(Offset(cx, cy - arm), Offset(cx, cy + arm), paint);
  }

  @override
  bool shouldRepaint(_CrosshairPainter oldDelegate) =>
      color != oldDelegate.color;
}
