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
  final double transitionValue; // 0.0 → 1.0 for entry scale-in
  final Offset canvasOffset;
  final double canvasScale;

  HandwritingSearchPainter({
    required this.results,
    required this.activeIndex,
    required this.animationValue,
    this.transitionValue = 1.0,
    this.canvasOffset = Offset.zero,
    this.canvasScale = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (results.isEmpty) return;

    // Apply canvas transform so highlights align with strokes
    canvas.save();
    canvas.translate(canvasOffset.dx, canvasOffset.dy);
    canvas.scale(canvasScale);

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

    // ── Active match: pulsing glow with entry scale-in ──
    if (activeIndex >= 0 && activeIndex < results.length) {
      final bounds = results[activeIndex].bounds;
      final pulse = 0.6 + 0.4 * math.sin(animationValue * math.pi * 2);

      // Entry animation: scale from 90% → 100%
      final entryScale = 0.9 + 0.1 * transitionValue;
      final center = bounds.center;
      final scaledBounds = Rect.fromCenter(
        center: center,
        width: bounds.width * entryScale,
        height: bounds.height * entryScale,
      );

      final inflated = scaledBounds.inflate(6.0);
      final rrect =
          RRect.fromRectAndRadius(inflated, const Radius.circular(8));

      // Entry opacity
      final entryAlpha = transitionValue.clamp(0.0, 1.0);

      // Outer glow
      final glowPaint = Paint()
        ..color = Color.fromARGB(
            (40 * pulse * entryAlpha).toInt(), 124, 77, 255)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawRRect(rrect.inflate(2), glowPaint);

      // Fill
      final activeFill = Paint()
        ..color = Color.fromARGB(
            (30 * pulse * entryAlpha).toInt(), 124, 77, 255)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(rrect, activeFill);

      // Border
      final activeBorder = Paint()
        ..color = Color.fromARGB(
            (200 * pulse * entryAlpha).toInt(), 124, 77, 255)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawRRect(rrect, activeBorder);

      // Small indicator dot at top-left
      if (entryAlpha > 0.5) {
        final dotCenter = Offset(rrect.left + 3, rrect.top + 3);
        canvas.drawCircle(
          dotCenter,
          3.5,
          Paint()..color = const Color(0xCC7C4DFF),
        );
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(HandwritingSearchPainter old) =>
      old.activeIndex != activeIndex ||
      old.animationValue != animationValue ||
      old.transitionValue != transitionValue ||
      old.canvasOffset != canvasOffset ||
      old.canvasScale != canvasScale ||
      old.results.length != results.length;
}

/// Widget wrapper that provides the animation for search highlights.
///
/// Place this in the canvas overlay stack. It continuously animates
/// the active match glow pulse, and adds a scale-in transition when
/// navigating between results.
class HandwritingSearchHighlights extends StatefulWidget {
  final List<HandwritingSearchResult> results;
  final int activeIndex;
  final Offset canvasOffset;
  final double canvasScale;

  const HandwritingSearchHighlights({
    super.key,
    required this.results,
    this.activeIndex = 0,
    this.canvasOffset = Offset.zero,
    this.canvasScale = 1.0,
  });

  @override
  State<HandwritingSearchHighlights> createState() =>
      _HandwritingSearchHighlightsState();
}

class _HandwritingSearchHighlightsState
    extends State<HandwritingSearchHighlights>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _transitionController;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _transitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnim = CurvedAnimation(
      parent: _transitionController,
      curve: Curves.easeOut,
    );
    _transitionController.value = 1.0; // Start fully visible
  }

  @override
  void didUpdateWidget(covariant HandwritingSearchHighlights oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Animate transition when active index changes
    if (oldWidget.activeIndex != widget.activeIndex) {
      _transitionController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _transitionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.results.isEmpty) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: Listenable.merge([_pulseController, _transitionController]),
      builder: (context, _) {
        return CustomPaint(
          painter: HandwritingSearchPainter(
            results: widget.results,
            activeIndex: widget.activeIndex,
            animationValue: _pulseController.value,
            transitionValue: _scaleAnim.value,
            canvasOffset: widget.canvasOffset,
            canvasScale: widget.canvasScale,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}
