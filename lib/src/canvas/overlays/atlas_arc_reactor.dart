import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 🦾 ATLAS ARC REACTOR — Iron Man-style AI trigger.
///
/// A pulsing neon cyan circle that appears below the lasso selection.
/// On tap it expands into an orbital HUD with action chips.
/// On chip tap it fires the Atlas prompt.
/// On swipe-up it opens the custom text prompt.
class AtlasArcReactor extends StatefulWidget {
  /// Number of selected nodes (shown in center when expanded).
  final int selectedCount;

  /// Called with the prompt string when user picks an action.
  final ValueChanged<String> onAction;

  /// Called when user wants the free-text prompt overlay.
  final VoidCallback onCustomPrompt;

  /// Whether Atlas is currently processing.
  final bool isLoading;

  const AtlasArcReactor({
    super.key,
    required this.selectedCount,
    required this.onAction,
    required this.onCustomPrompt,
    this.isLoading = false,
  });

  @override
  State<AtlasArcReactor> createState() => _AtlasArcReactorState();
}

class _AtlasArcReactorState extends State<AtlasArcReactor>
    with TickerProviderStateMixin {
  bool _expanded = false;

  // Breathing pulse
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;

  // Expand/collapse
  late final AnimationController _expandController;
  late final Animation<double> _expandAnim;

  // Chip stagger
  late final AnimationController _staggerController;

  // Loading vortex
  late final AnimationController _vortexController;

  static const _accent = Color(0xFF00E5FF);
  static const _coreSize = 36.0;
  static const _expandedRadius = 90.0;

  static const _actions = [
    _ArcAction('📝', 'Converti', '_CONVERT_'), // Client-side, no AI
    _ArcAction('🔍', 'Analizza', '_ANALYZE_'), // Client-side, no AI
  ];

  @override
  void initState() {
    super.initState();

    // Breathing pulse: 0.4 → 0.8 opacity, slow
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.4, end: 0.8).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Expand animation
    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _expandAnim = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeIn,
    );

    // Chip stagger
    _staggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    // Loading vortex rotation
    _vortexController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    if (widget.isLoading) _vortexController.repeat();
  }

  @override
  void didUpdateWidget(AtlasArcReactor old) {
    super.didUpdateWidget(old);
    if (widget.isLoading && !old.isLoading) {
      _vortexController.repeat();
      _collapse();
    } else if (!widget.isLoading && old.isLoading) {
      _vortexController.stop();
    }
  }

  void _toggle() {
    HapticFeedback.mediumImpact();
    if (_expanded) {
      _collapse();
    } else {
      _expand();
    }
  }

  void _expand() {
    setState(() => _expanded = true);
    _expandController.forward();
    _staggerController.forward(from: 0);
  }

  void _collapse() {
    _expandController.reverse().then((_) {
      if (mounted) setState(() => _expanded = false);
    });
  }

  void _onChipTap(int index) {
    HapticFeedback.mediumImpact();
    final action = _actions[index];
    if (action.prompt.isEmpty) {
      // "Chiedi..." → open custom prompt
      _collapse();
      widget.onCustomPrompt();
    } else {
      _collapse();
      widget.onAction(action.prompt);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _expandController.dispose();
    _staggerController.dispose();
    _vortexController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalSize = _expanded ? _expandedRadius * 2 + 60 : _coreSize + 24;

    return SizedBox(
      width: totalSize,
      height: totalSize,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Orbital action chips (behind the core)
          if (_expanded)
            ...List.generate(_actions.length, (i) => _buildChip(i)),

          // Core circle
          _buildCore(),
        ],
      ),
    );
  }

  Widget _buildCore() {
    return GestureDetector(
      onTap: widget.isLoading ? null : _toggle,
      onVerticalDragEnd: (details) {
        // Swipe up → custom prompt
        if (details.velocity.pixelsPerSecond.dy < -100) {
          HapticFeedback.mediumImpact();
          widget.onCustomPrompt();
        }
      },
      child: AnimatedBuilder(
        animation: Listenable.merge([_pulseAnim, _expandAnim, _vortexController]),
        builder: (context, _) {
          final breathe = _pulseAnim.value;
          final expand = _expandAnim.value;
          final size = _coreSize + expand * 8; // Slightly larger when expanded

          return Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                // Outer glow
                BoxShadow(
                  color: _accent.withValues(alpha: breathe * 0.4),
                  blurRadius: 16 + expand * 8,
                  spreadRadius: 2 + expand * 4,
                ),
              ],
            ),
            child: CustomPaint(
              painter: _ArcReactorPainter(
                breathe: breathe,
                expand: expand,
                vortex: widget.isLoading ? _vortexController.value : 0,
                isLoading: widget.isLoading,
              ),
              child: Center(
                child: widget.isLoading
                    ? const SizedBox.shrink()
                    : AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _expanded
                            ? Text(
                                '${widget.selectedCount}',
                                key: const ValueKey('count'),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: _accent.withValues(alpha: 0.9),
                                ),
                              )
                            : Icon(
                                Icons.auto_awesome_rounded,
                                key: const ValueKey('icon'),
                                size: 16,
                                color: Colors.white.withValues(alpha: breathe),
                              ),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildChip(int index) {
    return AnimatedBuilder(
      animation: Listenable.merge([_expandAnim, _staggerController]),
      builder: (context, _) {
        final expand = _expandAnim.value;
        if (expand < 0.01) return const SizedBox.shrink();

        // Stagger: each chip appears with a slight delay
        final staggerDelay = index * 0.12;
        final chipProgress = ((_staggerController.value - staggerDelay) / (1.0 - staggerDelay))
            .clamp(0.0, 1.0);
        final chipScale = Curves.easeOutBack.transform(chipProgress);

        // Position chips in a circle (top = -90°, clockwise)
        final angle = -pi / 2 + (index / _actions.length) * 2 * pi;
        final radius = _expandedRadius * expand;
        final dx = cos(angle) * radius;
        final dy = sin(angle) * radius;

        final action = _actions[index];
        final isCustom = action.prompt.isEmpty;

        return Transform.translate(
          offset: Offset(dx, dy),
          child: Transform.scale(
            scale: chipScale,
            child: Opacity(
              opacity: chipProgress,
              child: GestureDetector(
                onTap: () => _onChipTap(index),
                child: _buildChipContent(action, isCustom),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildChipContent(_ArcAction action, bool isCustom) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isCustom
                ? const Color(0xCC0D0D14)
                : const Color(0xCC0D0D14),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isCustom
                  ? Colors.white.withValues(alpha: 0.2)
                  : _accent.withValues(alpha: 0.3),
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: _accent.withValues(alpha: 0.1),
                blurRadius: 8,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(action.emoji, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 4),
              Text(
                action.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isCustom
                      ? Colors.white.withValues(alpha: 0.7)
                      : _accent.withValues(alpha: 0.9),
                  letterSpacing: 0.2,
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
// Arc Reactor Painter
// =============================================================================

class _ArcReactorPainter extends CustomPainter {
  final double breathe;
  final double expand;
  final double vortex;
  final bool isLoading;

  _ArcReactorPainter({
    required this.breathe,
    required this.expand,
    required this.vortex,
    required this.isLoading,
  });

  static const _cyan = Color(0xFF00E5FF);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2;

    // 1. Dark background circle
    canvas.drawCircle(
      center,
      maxR,
      Paint()..color = const Color(0xFF0A0A14).withValues(alpha: 0.85),
    );

    // 2. Outer ring
    canvas.drawCircle(
      center,
      maxR - 1,
      Paint()
        ..color = _cyan.withValues(alpha: 0.4 + breathe * 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // 3. Inner rings (concentric, rotating if loading)
    for (int i = 0; i < 3; i++) {
      final ringR = maxR * (0.35 + i * 0.15);
      final ringOpacity = (0.15 + breathe * 0.1) * (1.0 - i * 0.25);
      final startAngle = isLoading ? vortex * 2 * pi + i * 0.8 : i * 0.5;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: ringR),
        startAngle,
        pi * 1.2, // 216° arc
        false,
        Paint()
          ..color = _cyan.withValues(alpha: ringOpacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..strokeCap = StrokeCap.round,
      );
    }

    // 4. Center glow
    final glowRadius = maxR * (0.25 + breathe * 0.05);
    final gradient = ui.Gradient.radial(
      center,
      glowRadius,
      [
        _cyan.withValues(alpha: 0.3 + breathe * 0.1),
        _cyan.withValues(alpha: 0.0),
      ],
    );
    canvas.drawCircle(
      center,
      glowRadius,
      Paint()..shader = gradient,
    );

    // 5. Loading: particle vortex
    if (isLoading) {
      final random = Random(42);
      for (int i = 0; i < 6; i++) {
        final angle = vortex * 2 * pi + i * (pi / 3);
        final dist = maxR * 0.5 + random.nextDouble() * maxR * 0.3;
        final px = center.dx + cos(angle) * dist;
        final py = center.dy + sin(angle) * dist;
        final opacity = (0.5 + random.nextDouble() * 0.4);
        canvas.drawCircle(
          Offset(px, py),
          1.5 + random.nextDouble(),
          Paint()..color = _cyan.withValues(alpha: opacity),
        );
      }
    }

    // 6. Expanded: outer dotted orbit ring
    if (expand > 0.01) {
      final orbitR = maxR + 20 * expand;
      final orbitPaint = Paint()
        ..color = _cyan.withValues(alpha: 0.15 * expand)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5;
      canvas.drawCircle(center, orbitR, orbitPaint);

      // Orbit dots
      for (int i = 0; i < 12; i++) {
        final angle = i * (pi / 6);
        final dx = center.dx + cos(angle) * orbitR;
        final dy = center.dy + sin(angle) * orbitR;
        canvas.drawCircle(
          Offset(dx, dy),
          1.0,
          Paint()..color = _cyan.withValues(alpha: 0.2 * expand),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ArcReactorPainter old) =>
      old.breathe != breathe ||
      old.expand != expand ||
      old.vortex != vortex ||
      old.isLoading != isLoading;
}

// =============================================================================
// Data model
// =============================================================================

class _ArcAction {
  final String emoji;
  final String label;
  final String prompt;
  const _ArcAction(this.emoji, this.label, this.prompt);
}
