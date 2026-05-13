import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// =============================================================================
// 🎨 COLOR WHEEL TUTORIAL — One-shot, redesigned for clarity.
//
// Old version showed annotation pills next to the disc + a tiny ghost finger
// inside a spotlight. Users didn't connect the pills to the gestures.
//
// New version: three big "demo cards" stacked vertically, each showing a
// looping animated finger + arrow gesture on a mock disc, plus a clear
// label and one-line description of WHAT changes. The user reads top-to-
// bottom and sees the gesture, the affected property, and the result.
// =============================================================================

class ColorWheelTutorialOverlay extends StatefulWidget {
  /// Centre of the FloatingColorDisc — kept for API compatibility but no
  /// longer used by the redesigned overlay (which centres its own content).
  final Offset discCenter;

  /// Visual radius of the disc — same note as above.
  final double discRadius;

  final VoidCallback onDismiss;

  /// Animate the demo fingers (set false in tests / low-power preview).
  final bool enableGhostFinger;

  const ColorWheelTutorialOverlay({
    super.key,
    required this.discCenter,
    required this.onDismiss,
    this.discRadius = 22.0,
    this.enableGhostFinger = true,
  });

  @override
  State<ColorWheelTutorialOverlay> createState() =>
      _ColorWheelTutorialOverlayState();
}

class _ColorWheelTutorialOverlayState extends State<ColorWheelTutorialOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _enterCtrl;
  late final AnimationController _loopCtrl;
  Timer? _autoDismissTimer;
  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    _enterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    )..forward();

    _loopCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    if (widget.enableGhostFinger) _loopCtrl.repeat();

    HapticFeedback.mediumImpact();

    // Auto-dismiss after 18 s — enough time to read all three demos.
    _autoDismissTimer = Timer(const Duration(seconds: 18), _handleDismiss);
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _enterCtrl.dispose();
    _loopCtrl.dispose();
    super.dispose();
  }

  void _handleDismiss() {
    if (_exiting) return;
    _exiting = true;
    _autoDismissTimer?.cancel();
    HapticFeedback.selectionClick();
    _enterCtrl.reverse().then((_) {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _enterCtrl,
      builder: (context, _) {
        final t = Curves.easeOutCubic.transform(_enterCtrl.value);
        return Opacity(
          opacity: t,
          child: Transform.scale(
            scale: 0.94 + 0.06 * t,
            alignment: Alignment.center,
            child: _buildContent(context),
          ),
        );
      },
    );
  }

  Widget _buildContent(BuildContext context) {
    final media = MediaQuery.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Solid scrim (no spotlight — every demo is centred).
        Positioned.fill(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(color: const Color(0xE60E1020)),
          ),
        ),

        // 2. Centred content column with the 3 demos.
        Positioned.fill(
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                media.padding.top + 12,
                20,
                media.padding.bottom + 16,
              ),
              child: Column(
                children: [
                  _buildHeader(),
                  const SizedBox(height: 18),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          _GestureDemoCard(
                            title: 'DIMENSIONE',
                            subtitle: 'Trascina ORIZZONTALE',
                            description:
                                'Sposta il dito a destra o sinistra sul '
                                'cerchio per ingrandire o ridurre il pennello.',
                            accent: const Color(0xFF8FB4C9),
                            icon: Icons.swap_horiz_rounded,
                            mode: _DemoMode.horizontal,
                            loopT: _loopCtrl,
                          ),
                          const SizedBox(height: 14),
                          _GestureDemoCard(
                            title: 'INTENSITÀ',
                            subtitle: 'Trascina VERTICALE',
                            description:
                                'Sposta il dito su o giù per rendere il '
                                'colore più acceso o più tenue.',
                            accent: const Color(0xFF8FBDB7),
                            icon: Icons.swap_vert_rounded,
                            mode: _DemoMode.vertical,
                            loopT: _loopCtrl,
                          ),
                          const SizedBox(height: 14),
                          _GestureDemoCard(
                            title: 'COLORE',
                            subtitle: 'Disegna un CERCHIO attorno',
                            description:
                                'Tieni premuto e ruota il dito attorno al '
                                'cerchio per scegliere un nuovo colore.',
                            accent: const Color(0xFFB39DC7),
                            icon: Icons.refresh_rounded,
                            mode: _DemoMode.circular,
                            loopT: _loopCtrl,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildCta(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: const [
        Text(
          'Come usare il cerchio del colore',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
        ),
        SizedBox(height: 4),
        Text(
          '3 gesti, un solo dito.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFFCFC9E8),
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  Widget _buildCta() {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: InkWell(
        onTap: _handleDismiss,
        borderRadius: BorderRadius.circular(28),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_rounded,
                color: Color(0xFF1A1A2E),
                size: 20,
              ),
              SizedBox(width: 10),
              Text(
                'Provo subito',
                style: TextStyle(
                  color: Color(0xFF1A1A2E),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Demo card — large mock disc + animated finger + label + description.
// =============================================================================

enum _DemoMode { horizontal, vertical, circular }

class _GestureDemoCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String description;
  final Color accent;
  final IconData icon;
  final _DemoMode mode;
  final Animation<double> loopT;

  const _GestureDemoCard({
    required this.title,
    required this.subtitle,
    required this.description,
    required this.accent,
    required this.icon,
    required this.mode,
    required this.loopT,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: accent.withValues(alpha: 0.45),
            width: 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.15),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Animated demo (mock disc + finger).
            SizedBox(
              width: 110,
              height: 110,
              child: AnimatedBuilder(
                animation: loopT,
                builder: (_, __) => CustomPaint(
                  painter: _DemoPainter(
                    mode: mode,
                    t: loopT.value,
                    accent: accent,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.30),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: accent,
                            width: 1.2,
                          ),
                        ),
                        child: Icon(icon, size: 16, color: Colors.white),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        title,
                        style: TextStyle(
                          color: accent,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      color: Color(0xFFCFC9E8),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Demo painter — draws a centred mock disc + an animated finger that
// performs the gesture in a continuous loop. Each mode has its own motion
// so the user immediately recognises the gesture.
// =============================================================================

class _DemoPainter extends CustomPainter {
  final _DemoMode mode;
  final double t; // 0..1 loop value
  final Color accent;

  _DemoPainter({
    required this.mode,
    required this.t,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const discRadius = 22.0;

    // Disc body — soft fill + ring.
    canvas.drawCircle(
      center,
      discRadius,
      Paint()..color = accent.withValues(alpha: 0.30),
    );
    canvas.drawCircle(
      center,
      discRadius,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
    // Inner highlight
    canvas.drawCircle(
      center.translate(-4, -5),
      4,
      Paint()..color = Colors.white.withValues(alpha: 0.45),
    );

    // Triangle wave 0→1→0 for back-and-forth gestures.
    final pingPong = t < 0.5 ? t * 2 : (1 - t) * 2;

    Offset tip;
    Offset arrowStart;
    Offset arrowEnd;
    double pulse;

    switch (mode) {
      case _DemoMode.horizontal:
        const reach = 36.0;
        final dx = (pingPong - 0.5) * 2 * reach; // -reach..+reach
        tip = center + Offset(dx, 0);
        arrowStart = center + const Offset(-reach, 0);
        arrowEnd = center + const Offset(reach, 0);
        pulse = math.sin(t * math.pi * 2);
        _drawDoubleArrow(canvas, arrowStart, arrowEnd);
        break;
      case _DemoMode.vertical:
        const reach = 36.0;
        final dy = (pingPong - 0.5) * 2 * reach;
        tip = center + Offset(0, dy);
        arrowStart = center + const Offset(0, -reach);
        arrowEnd = center + const Offset(0, reach);
        pulse = math.sin(t * math.pi * 2);
        _drawDoubleArrow(canvas, arrowStart, arrowEnd);
        break;
      case _DemoMode.circular:
        // Ghost rim ring + finger orbiting.
        canvas.drawCircle(
          center,
          discRadius + 14,
          Paint()
            ..color = accent.withValues(alpha: 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
        final angle = t * math.pi * 2 - math.pi / 2;
        tip = center +
            Offset(math.cos(angle), math.sin(angle)) * (discRadius + 14);
        pulse = 1.0;
        _drawArrowHead(canvas, tip, angle + math.pi / 2);
        break;
    }

    // Ripple under the finger (grows while held).
    final rippleRadius = 6.0 + pulse.abs() * 6.0;
    canvas.drawCircle(
      tip,
      rippleRadius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35 * (1 - pulse.abs()))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    // Fingertip — white dot with thin dark border for visibility.
    canvas.drawCircle(
      tip,
      6.5,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      tip,
      6.5,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
  }

  void _drawDoubleArrow(Canvas canvas, Offset start, Offset end) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.40)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(start, end, paint);
    final dir = (end - start);
    final len = dir.distance;
    if (len < 1) return;
    final unit = dir / len;
    // Arrow heads at each end.
    _drawArrowHead(canvas, start, math.atan2(-unit.dy, -unit.dx));
    _drawArrowHead(canvas, end, math.atan2(unit.dy, unit.dx));
  }

  void _drawArrowHead(Canvas canvas, Offset at, double angle) {
    const size = 6.0;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;
    final p1 = at;
    final p2 = at +
        Offset(
          math.cos(angle + math.pi - 0.45),
          math.sin(angle + math.pi - 0.45),
        ) *
            size;
    final p3 = at +
        Offset(
          math.cos(angle + math.pi + 0.45),
          math.sin(angle + math.pi + 0.45),
        ) *
            size;
    final path = Path()
      ..moveTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _DemoPainter old) =>
      old.t != t || old.accent != accent || old.mode != mode;
}
