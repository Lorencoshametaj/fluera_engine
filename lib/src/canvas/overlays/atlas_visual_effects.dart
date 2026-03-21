import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// 🌌 ATLAS VISUAL EFFECTS — Minority Report-style animations.
///
/// Provides three effect types:
/// - **Materialization**: New nodes fade+scale in with neon glow
/// - **Scan Pulse**: Loading wave that sweeps across selected nodes
/// - **Connection Laser**: Animated line drawn between connected nodes
///
/// All effects use the Atlas signature neon cyan (#00E5FF) and are
/// designed to feel futuristic yet not distracting.

// =============================================================================
// Materialization Effect (node creation)
// =============================================================================

/// Overlay that plays a holographic materialization animation when
/// Atlas creates a new node. Shows at the node's screen position.
class AtlasMaterializeEffect extends StatefulWidget {
  /// Screen-space position of the new node's center.
  final Offset position;

  /// Size of the glow effect.
  final double size;

  /// Callback when animation completes (to remove from overlay list).
  final VoidCallback? onComplete;

  const AtlasMaterializeEffect({
    super.key,
    required this.position,
    this.size = 120,
    this.onComplete,
  });

  @override
  State<AtlasMaterializeEffect> createState() => _AtlasMaterializeEffectState();
}

class _AtlasMaterializeEffectState extends State<AtlasMaterializeEffect>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward().then((_) {
        widget.onComplete?.call();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        // Phase 1 (0-0.5): Glow ring expands outward
        // Phase 2 (0.3-1.0): Content fades in with scale
        final ringProgress = (t * 2.0).clamp(0.0, 1.0);
        final contentProgress = ((t - 0.3) / 0.7).clamp(0.0, 1.0);

        return Positioned(
          left: widget.position.dx - widget.size / 2,
          top: widget.position.dy - widget.size / 2,
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: CustomPaint(
              painter: _MaterializePainter(
                ringProgress: Curves.easeOut.transform(ringProgress),
                contentProgress: Curves.easeOutBack.transform(contentProgress),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MaterializePainter extends CustomPainter {
  final double ringProgress;
  final double contentProgress;

  _MaterializePainter({
    required this.ringProgress,
    required this.contentProgress,
  });

  static const _cyan = Color(0xFF00E5FF);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    // Expanding ring
    if (ringProgress > 0 && ringProgress < 1) {
      final radius = maxRadius * ringProgress;
      final opacity = (1.0 - ringProgress) * 0.6;
      final paint = Paint()
        ..color = _cyan.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(center, radius, paint);

      // Inner glow ring
      final innerPaint = Paint()
        ..color = _cyan.withValues(alpha: opacity * 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      canvas.drawCircle(center, radius * 0.8, innerPaint);
    }

    // Center glow (fades in then out)
    if (contentProgress > 0) {
      final glowOpacity = contentProgress < 0.5
          ? contentProgress * 2 * 0.15
          : (1.0 - contentProgress) * 2 * 0.15;
      final gradient = ui.Gradient.radial(
        center,
        maxRadius * 0.6,
        [
          _cyan.withValues(alpha: glowOpacity),
          _cyan.withValues(alpha: 0),
        ],
      );
      canvas.drawCircle(
        center,
        maxRadius * 0.6,
        Paint()..shader = gradient,
      );
    }

    // Particle sparkles
    if (ringProgress > 0.2 && ringProgress < 0.9) {
      final random = Random(42); // Deterministic for consistent look
      final particleOpacity = (1.0 - ringProgress) * 0.8;
      for (int i = 0; i < 8; i++) {
        final angle = random.nextDouble() * pi * 2;
        final dist = maxRadius * ringProgress * (0.6 + random.nextDouble() * 0.4);
        final px = center.dx + cos(angle) * dist;
        final py = center.dy + sin(angle) * dist;
        canvas.drawCircle(
          Offset(px, py),
          1.5 + random.nextDouble() * 1.5,
          Paint()..color = _cyan.withValues(alpha: particleOpacity),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_MaterializePainter old) =>
      old.ringProgress != ringProgress || old.contentProgress != contentProgress;
}

// =============================================================================
// Scan Pulse Effect (loading state)
// =============================================================================

/// Horizontal scanning beam that sweeps across the overlay area.
/// Used during Atlas loading to show "scanning" selected nodes.
class AtlasScanPulseOverlay extends StatefulWidget {
  /// Bounding rect (screen coordinates) of selected nodes.
  final Rect selectionBounds;

  /// Whether the scan is active.
  final bool isActive;

  const AtlasScanPulseOverlay({
    super.key,
    required this.selectionBounds,
    this.isActive = true,
  });

  @override
  State<AtlasScanPulseOverlay> createState() => _AtlasScanPulseOverlayState();
}

class _AtlasScanPulseOverlayState extends State<AtlasScanPulseOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) return const SizedBox.shrink();

    return Positioned.fromRect(
      rect: widget.selectionBounds.inflate(20),
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              painter: _ScanPulsePainter(
                progress: _controller.value,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ScanPulsePainter extends CustomPainter {
  final double progress;

  _ScanPulsePainter({required this.progress});

  static const _cyan = Color(0xFF00E5FF);

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Subtle border glow
    final borderPaint = Paint()
      ..color = _cyan.withValues(alpha: 0.15 + sin(progress * pi * 2) * 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(8),
    );
    canvas.drawRRect(rrect, borderPaint);

    // 2. Horizontal scan beam
    final beamY = size.height * progress;
    final beamGradient = ui.Gradient.linear(
      Offset(0, beamY - 15),
      Offset(0, beamY + 15),
      [
        _cyan.withValues(alpha: 0),
        _cyan.withValues(alpha: 0.25),
        _cyan.withValues(alpha: 0),
      ],
      [0.0, 0.5, 1.0],
    );
    canvas.drawRect(
      Rect.fromLTWH(0, beamY - 15, size.width, 30),
      Paint()..shader = beamGradient,
    );

    // 3. Leading edge line
    canvas.drawLine(
      Offset(0, beamY),
      Offset(size.width, beamY),
      Paint()
        ..color = _cyan.withValues(alpha: 0.5)
        ..strokeWidth = 1.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    // 4. Corner brackets (sci-fi targeting)
    _drawCornerBracket(canvas, Offset.zero, size, topLeft: true);
    _drawCornerBracket(canvas, Offset(size.width, 0), size, topRight: true);
    _drawCornerBracket(canvas, Offset(0, size.height), size, bottomLeft: true);
    _drawCornerBracket(canvas, Offset(size.width, size.height), size, bottomRight: true);
  }

  void _drawCornerBracket(Canvas canvas, Offset corner, Size size, {
    bool topLeft = false,
    bool topRight = false,
    bool bottomLeft = false,
    bool bottomRight = false,
  }) {
    const len = 16.0;
    final paint = Paint()
      ..color = _cyan.withValues(alpha: 0.6)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    if (topLeft) {
      canvas.drawLine(corner, corner + const Offset(len, 0), paint);
      canvas.drawLine(corner, corner + const Offset(0, len), paint);
    } else if (topRight) {
      canvas.drawLine(corner, corner + const Offset(-len, 0), paint);
      canvas.drawLine(corner, corner + const Offset(0, len), paint);
    } else if (bottomLeft) {
      canvas.drawLine(corner, corner + const Offset(len, 0), paint);
      canvas.drawLine(corner, corner + const Offset(0, -len), paint);
    } else if (bottomRight) {
      canvas.drawLine(corner, corner + const Offset(-len, 0), paint);
      canvas.drawLine(corner, corner + const Offset(0, -len), paint);
    }
  }

  @override
  bool shouldRepaint(_ScanPulsePainter old) => old.progress != progress;
}

// =============================================================================
// Connection Laser Effect
// =============================================================================

/// Animated laser beam drawn progressively between two points.
/// Used when Atlas creates a connection between nodes.
class AtlasConnectionLaserEffect extends StatefulWidget {
  /// Start point in screen coordinates.
  final Offset from;

  /// End point in screen coordinates.
  final Offset to;

  /// Callback when animation completes.
  final VoidCallback? onComplete;

  const AtlasConnectionLaserEffect({
    super.key,
    required this.from,
    required this.to,
    this.onComplete,
  });

  @override
  State<AtlasConnectionLaserEffect> createState() =>
      _AtlasConnectionLaserEffectState();
}

class _AtlasConnectionLaserEffectState extends State<AtlasConnectionLaserEffect>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward().then((_) {
        // Hold for a moment then fade out
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) {
            _controller.reverse().then((_) {
              widget.onComplete?.call();
            });
          }
        });
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              painter: _LaserPainter(
                from: widget.from,
                to: widget.to,
                progress: _controller.value,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LaserPainter extends CustomPainter {
  final Offset from;
  final Offset to;
  final double progress;

  _LaserPainter({
    required this.from,
    required this.to,
    required this.progress,
  });

  static const _cyan = Color(0xFF00E5FF);

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final currentEnd = Offset.lerp(from, to, progress.clamp(0.0, 1.0))!;

    // Outer glow
    canvas.drawLine(
      from,
      currentEnd,
      Paint()
        ..color = _cyan.withValues(alpha: 0.15)
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Mid glow
    canvas.drawLine(
      from,
      currentEnd,
      Paint()
        ..color = _cyan.withValues(alpha: 0.4)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // Core beam
    canvas.drawLine(
      from,
      currentEnd,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );

    // Leading point glow
    final pointPaint = Paint()
      ..color = _cyan.withValues(alpha: 0.7)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(currentEnd, 4, pointPaint);
    canvas.drawCircle(currentEnd, 2, Paint()..color = Colors.white);

    // Start point glow
    canvas.drawCircle(from, 3, pointPaint);
    canvas.drawCircle(from, 1.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_LaserPainter old) =>
      old.progress != progress || old.from != from || old.to != to;
}
