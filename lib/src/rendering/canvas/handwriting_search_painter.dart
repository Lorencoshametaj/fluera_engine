import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../../services/handwriting_index_service.dart';

// =============================================================================
// 🔍 Handwriting Search Painter — Canvas highlight for matched strokes
//
// Draws animated highlight rectangles around strokes that match the
// current search query. The active result gets a pulsing glow animation.
// =============================================================================

/// Paints search result highlights on the canvas.
///
/// Overlays semi-transparent rounded rectangles on matched strokes.
/// The active match gets a pulsing border and glow effect.
class HandwritingSearchPainter extends CustomPainter {
  final List<HandwritingSearchResult> results;
  final int activeIndex;
  final double animationValue; // 0.0 → 1.0 for pulse animation

  HandwritingSearchPainter({
    required this.results,
    required this.activeIndex,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (results.isEmpty) return;

    // ── Inactive matches: subtle highlight ──
    final inactiveFill = Paint()
      ..color = const Color(0x18FFB300) // warm amber, very subtle
      ..style = PaintingStyle.fill;

    final inactiveBorder = Paint()
      ..color = const Color(0x55FFB300)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (int i = 0; i < results.length; i++) {
      if (i == activeIndex) continue;

      final bounds = results[i].bounds;
      final inflated = bounds.inflate(4.0);
      final rrect = RRect.fromRectAndRadius(inflated, const Radius.circular(6));

      canvas.drawRRect(rrect, inactiveFill);
      canvas.drawRRect(rrect, inactiveBorder);
    }

    // ── Active match: pulsing glow ──
    if (activeIndex >= 0 && activeIndex < results.length) {
      final bounds = results[activeIndex].bounds;
      final pulse = 0.6 + 0.4 * math.sin(animationValue * math.pi * 2);
      final inflated = bounds.inflate(6.0);
      final rrect =
          RRect.fromRectAndRadius(inflated, const Radius.circular(8));

      // Outer glow
      final glowPaint = Paint()
        ..color = Color.fromARGB((40 * pulse).toInt(), 124, 77, 255)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawRRect(rrect.inflate(2), glowPaint);

      // Fill
      final activeFill = Paint()
        ..color = Color.fromARGB((30 * pulse).toInt(), 124, 77, 255)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(rrect, activeFill);

      // Border
      final activeBorder = Paint()
        ..color = Color.fromARGB((200 * pulse).toInt(), 124, 77, 255)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawRRect(rrect, activeBorder);

      // Small indicator dot at top-left
      final dotCenter = Offset(rrect.left + 3, rrect.top + 3);
      canvas.drawCircle(
        dotCenter,
        3.5,
        Paint()..color = const Color(0xCC7C4DFF),
      );
    }
  }

  @override
  bool shouldRepaint(HandwritingSearchPainter old) =>
      old.activeIndex != activeIndex ||
      old.animationValue != animationValue ||
      old.results.length != results.length;
}

/// Widget wrapper that provides the animation for search highlights.
///
/// Place this in the canvas overlay stack. It continuously animates
/// the active match glow pulse.
class HandwritingSearchHighlights extends StatefulWidget {
  final List<HandwritingSearchResult> results;
  final int activeIndex;

  const HandwritingSearchHighlights({
    super.key,
    required this.results,
    this.activeIndex = 0,
  });

  @override
  State<HandwritingSearchHighlights> createState() =>
      _HandwritingSearchHighlightsState();
}

class _HandwritingSearchHighlightsState
    extends State<HandwritingSearchHighlights>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.results.isEmpty) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        return CustomPaint(
          painter: HandwritingSearchPainter(
            results: widget.results,
            activeIndex: widget.activeIndex,
            animationValue: _pulseController.value,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}
