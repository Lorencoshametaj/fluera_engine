import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../infinite_canvas_controller.dart';
import './content_bounds_tracker.dart';
import '../../rendering/optimization/viewport_culler.dart';

/// 📡 Content Radar — pulsing edge glow indicators showing off-screen content.
///
/// DESIGN PRINCIPLES:
/// - Colored gradient bleeds in from edges with off-screen content.
/// - Subtle pulse animation (breathing) draws attention without being intrusive.
/// - Glow intensity & depth scale with the amount of off-screen content.
/// - Tapping on a glowing edge pans towards that content.
/// - Zero UI when all content is visible → fully invisible.
///
/// PERFORMANCE:
/// - O(n) scan of regions per frame, but regions are typically < 500 items.
/// - Only rebuilds when controller or bounds change (ValueListenableBuilder).
/// - Single AnimationController shared via wrapper.
class ContentRadarOverlay extends StatefulWidget {
  final InfiniteCanvasController controller;
  final ContentBoundsTracker boundsTracker;
  final Size viewportSize;

  /// Canvas background color — used to compute contrasting glow color.
  final Color canvasBackground;

  const ContentRadarOverlay({
    super.key,
    required this.controller,
    required this.boundsTracker,
    required this.viewportSize,
    this.canvasBackground = Colors.white,
  });

  @override
  State<ContentRadarOverlay> createState() => _ContentRadarOverlayState();
}

class _ContentRadarOverlayState extends State<ContentRadarOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  /// Compute which edges have off-screen content and how much.
  _RadarData _computeRadar(Rect viewport, List<ContentRegion> regions) {
    if (regions.isEmpty) {
      return const _RadarData(top: 0, right: 0, bottom: 0, left: 0);
    }

    // Use a generous inflation so barely-clipping content doesn't trigger glow.
    final inflated = viewport.inflate(viewport.shortestSide * 0.1);

    double topWeight = 0;
    double rightWeight = 0;
    double bottomWeight = 0;
    double leftWeight = 0;

    for (final region in regions) {
      final b = region.bounds;
      if (!b.isFinite || b.isEmpty) continue;

      // Skip content that is even PARTIALLY visible in the viewport.
      // Only count content that is COMPLETELY off-screen.
      if (inflated.overlaps(b)) {
        continue;
      }

      final area = b.width * b.height;
      if (area <= 0) continue;

      final w = math.log(area + 1).clamp(0.0, 20.0);
      if (b.top < inflated.top) topWeight += w;
      if (b.right > inflated.right) rightWeight += w;
      if (b.bottom > inflated.bottom) bottomWeight += w;
      if (b.left < inflated.left) leftWeight += w;
    }

    const minWeight = 1.0;
    return _RadarData(
      top: topWeight < minWeight ? 0 : topWeight,
      right: rightWeight < minWeight ? 0 : rightWeight,
      bottom: bottomWeight < minWeight ? 0 : bottomWeight,
      left: leftWeight < minWeight ? 0 : leftWeight,
    );
  }

  Rect _viewportInCanvas() {
    return ViewportCuller.calculateViewport(
      widget.viewportSize,
      widget.controller.offset,
      widget.controller.scale,
      rotation: widget.controller.rotation,
    );
  }

  void _navigateToDirection(_Direction direction) {
    // Light haptic on navigation
    HapticFeedback.lightImpact();

    final viewport = _viewportInCanvas();
    final panDistance =
        direction == _Direction.left || direction == _Direction.right
            ? viewport.width * 0.6
            : viewport.height * 0.6;

    Offset delta;
    switch (direction) {
      case _Direction.top:
        delta = Offset(0, panDistance * widget.controller.scale);
      case _Direction.right:
        delta = Offset(-panDistance * widget.controller.scale, 0);
      case _Direction.bottom:
        delta = Offset(0, -panDistance * widget.controller.scale);
      case _Direction.left:
        delta = Offset(panDistance * widget.controller.scale, 0);
    }

    widget.controller.animateOffsetTo(widget.controller.offset + delta);
  }

  void _showDirectionTooltip(BuildContext context, _Direction direction) {
    HapticFeedback.mediumImpact();

    String label;
    switch (direction) {
      case _Direction.top:
        label = 'Contenuto in alto ↑';
      case _Direction.right:
        label = 'Contenuto a destra →';
      case _Direction.bottom:
        label = 'Contenuto in basso ↓';
      case _Direction.left:
        label = 'Contenuto a sinistra ←';
    }

    final overlay = Overlay.of(context, rootOverlay: true);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) {
        return _DirectionTooltip(
          label: label,
          direction: direction,
          onDone: () => entry.remove(),
        );
      },
    );
    overlay.insert(entry);
  }

  /// Glow color — contrasts with canvas background.
  Color get _glowColor {
    final lum = widget.canvasBackground.computeLuminance();
    return lum > 0.5
        ? const Color(0xFF3B82F6) // Bright blue
        : const Color(0xFF38BDF8); // Sky blue
  }

  double _glowDepth(double weight) => (24 + weight * 2.0).clamp(24.0, 80.0);
  double _glowOpacity(double weight) => (weight / 30.0).clamp(0.15, 0.55);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.controller, _pulseAnimation]),
      builder: (context, _) {
        return ValueListenableBuilder<List<ContentRegion>>(
          valueListenable: widget.boundsTracker.regions,
          builder: (context, regions, _) {
            final viewport = _viewportInCanvas();
            final radar = _computeRadar(viewport, regions);

            if (radar.isEmpty) return const SizedBox.shrink();

            final glow = _glowColor;
            final pulse = _pulseAnimation.value;

            return Stack(
              children: [
                if (radar.top > 0)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: _glowDepth(radar.top),
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => _navigateToDirection(_Direction.top),
                      onLongPress:
                          () => _showDirectionTooltip(context, _Direction.top),
                      child: _EdgeGlow(
                        direction: _Direction.top,
                        color: glow,
                        opacity: _glowOpacity(radar.top) * pulse,
                      ),
                    ),
                  ),
                if (radar.right > 0)
                  Positioned(
                    top: 0,
                    right: 0,
                    bottom: 0,
                    width: _glowDepth(radar.right),
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => _navigateToDirection(_Direction.right),
                      onLongPress:
                          () =>
                              _showDirectionTooltip(context, _Direction.right),
                      child: _EdgeGlow(
                        direction: _Direction.right,
                        color: glow,
                        opacity: _glowOpacity(radar.right) * pulse,
                      ),
                    ),
                  ),
                if (radar.bottom > 0)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: _glowDepth(radar.bottom),
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => _navigateToDirection(_Direction.bottom),
                      onLongPress:
                          () =>
                              _showDirectionTooltip(context, _Direction.bottom),
                      child: _EdgeGlow(
                        direction: _Direction.bottom,
                        color: glow,
                        opacity: _glowOpacity(radar.bottom) * pulse,
                      ),
                    ),
                  ),
                if (radar.left > 0)
                  Positioned(
                    top: 0,
                    left: 0,
                    bottom: 0,
                    width: _glowDepth(radar.left),
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => _navigateToDirection(_Direction.left),
                      onLongPress:
                          () => _showDirectionTooltip(context, _Direction.left),
                      child: _EdgeGlow(
                        direction: _Direction.left,
                        color: glow,
                        opacity: _glowOpacity(radar.left) * pulse,
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

// =============================================================================
// Private types
// =============================================================================

enum _Direction { top, right, bottom, left }

class _RadarData {
  final double top;
  final double right;
  final double bottom;
  final double left;

  const _RadarData({
    required this.top,
    required this.right,
    required this.bottom,
    required this.left,
  });

  bool get isEmpty => top == 0 && right == 0 && bottom == 0 && left == 0;
}

/// A single edge glow — gradient from edge color to transparent.
class _EdgeGlow extends StatelessWidget {
  final _Direction direction;
  final Color color;
  final double opacity;

  const _EdgeGlow({
    required this.direction,
    required this.color,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    final glowColor = color.withValues(alpha: opacity);
    final transparent = color.withValues(alpha: 0);

    AlignmentGeometry begin;
    AlignmentGeometry end;

    switch (direction) {
      case _Direction.top:
        begin = Alignment.topCenter;
        end = Alignment.bottomCenter;
      case _Direction.right:
        begin = Alignment.centerRight;
        end = Alignment.centerLeft;
      case _Direction.bottom:
        begin = Alignment.bottomCenter;
        end = Alignment.topCenter;
      case _Direction.left:
        begin = Alignment.centerLeft;
        end = Alignment.centerRight;
    }

    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: begin,
            end: end,
            colors: [glowColor, transparent],
            stops: const [0.0, 1.0],
          ),
        ),
      ),
    );
  }
}

/// Tooltip that shows direction info on long-press and auto-dismisses.
class _DirectionTooltip extends StatefulWidget {
  final String label;
  final _Direction direction;
  final VoidCallback onDone;

  const _DirectionTooltip({
    required this.label,
    required this.direction,
    required this.onDone,
  });

  @override
  State<_DirectionTooltip> createState() => _DirectionTooltipState();
}

class _DirectionTooltipState extends State<_DirectionTooltip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..forward();

    // Auto-dismiss after 2 seconds
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _anim.reverse().then((_) {
          if (mounted) widget.onDone();
        });
      }
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    double top;
    double? left;
    double? right;

    switch (widget.direction) {
      case _Direction.top:
        top = 80;
        left = 0;
        right = 0;
      case _Direction.bottom:
        top = size.height - 120;
        left = 0;
        right = 0;
      case _Direction.left:
        top = size.height / 2 - 20;
        left = 20;
      case _Direction.right:
        top = size.height / 2 - 20;
        right = 20;
    }

    return Positioned(
      top: top,
      left: left,
      right: right,
      child: FadeTransition(
        opacity: CurvedAnimation(parent: _anim, curve: Curves.easeOut),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xE6222235),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              widget.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
