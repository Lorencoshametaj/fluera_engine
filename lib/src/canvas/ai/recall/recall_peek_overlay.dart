// ============================================================================
// 👁️ RECALL PEEK OVERLAY — Temporary node reveal system
//
// Spec: P2-16, P2-66 → P2-70
//
// Shows a single node revealed from blur when the user long-presses.
// Features:
//   - Progressive timer: 3s → 2s → 1.5s → 1s (P2-66)
//   - Escalating border color: yellow → orange → red-orange → red
//   - Node shown IN ISOLATION: no connections/arrows (P2-69)
//   - Automatic re-blur with fade animation
//   - Warning suggestion after 4+ peeks (P2-67)
// ============================================================================

import 'package:flutter/material.dart';

import '../../../l10n/generated/fluera_localizations.g.dart';
import 'recall_mode_controller.dart';

/// 👁️ Overlay for the peek reveal system.
///
/// Positioned at the peeked node's screen location.
/// Shows a countdown indicator and the node content (unblurred).
class RecallPeekOverlay extends StatefulWidget {
  final RecallModeController controller;

  /// Screen position of the peeked node's center.
  final Offset screenPosition;

  /// Size of the peeked node in screen pixels.
  final Size nodeSize;

  /// The peek duration (for countdown ring animation).
  final Duration peekDuration;

  /// Current session peek count (for warning display).
  final int peekNumber;

  const RecallPeekOverlay({
    super.key,
    required this.controller,
    required this.screenPosition,
    required this.nodeSize,
    required this.peekDuration,
    required this.peekNumber,
  });

  @override
  State<RecallPeekOverlay> createState() => _RecallPeekOverlayState();
}

class _RecallPeekOverlayState extends State<RecallPeekOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _countdownController;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();

    _countdownController = AnimationController(
      vsync: this,
      duration: widget.peekDuration,
    );

    _fadeAnim = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _countdownController, curve: Curves.easeIn),
    );

    _countdownController.forward();
  }

  @override
  void dispose() {
    _countdownController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final peekColor = _peekColor(widget.peekNumber);
    final width = widget.nodeSize.width.clamp(80.0, 300.0);
    final height = widget.nodeSize.height.clamp(60.0, 200.0);

    return Stack(
      children: [
        // ── Countdown ring around the peeked node ──
        Positioned(
          left: widget.screenPosition.dx - width / 2 - 8,
          top: widget.screenPosition.dy - height / 2 - 8,
          child: AnimatedBuilder(
            animation: _countdownController,
            builder: (_, __) {
              return Container(
                width: width + 16,
                height: height + 16,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: peekColor.withValues(
                      alpha: (1.0 - _countdownController.value) * 0.8,
                    ),
                    width: 2.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: peekColor.withValues(
                        alpha: (1.0 - _countdownController.value) * 0.3,
                      ),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              );
            },
          ),
        ),

        // ── Countdown timer indicator ──
        Positioned(
          left: widget.screenPosition.dx + width / 2 + 4,
          top: widget.screenPosition.dy - height / 2 - 4,
          child: AnimatedBuilder(
            animation: _countdownController,
            builder: (_, __) {
              final remaining = widget.peekDuration.inMilliseconds *
                  (1.0 - _countdownController.value) /
                  1000.0;
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xCC0A0A14),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: peekColor.withValues(alpha: 0.4),
                    width: 0.5,
                  ),
                ),
                child: Text(
                  '${remaining.toStringAsFixed(1)}s',
                  style: TextStyle(
                    color: peekColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            },
          ),
        ),

        // ── Peek warning (P2-67): after 4+ peeks ──
        if (widget.peekNumber >= 4)
          Positioned(
            left: widget.screenPosition.dx - 120,
            top: widget.screenPosition.dy + height / 2 + 12,
            child: FadeTransition(
              opacity: _fadeAnim,
              child: Container(
                width: 240,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xCC1A0A0E),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFFF6B00).withValues(alpha: 0.3),
                    width: 0.5,
                  ),
                ),
                child: Text(
                  FlueraLocalizations.of(context)!.recall_peekHint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFFF9500),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),

        // ── Eye icon at peek marker position ──
        Positioned(
          left: widget.screenPosition.dx - 10,
          top: widget.screenPosition.dy - height / 2 - 22,
          child: Icon(
            Icons.visibility_rounded,
            color: peekColor.withValues(alpha: 0.7),
            size: 16,
          ),
        ),
      ],
    );
  }

  Color _peekColor(int peekNumber) {
    switch (peekNumber) {
      case 1:
        return const Color(0xFFFFCC00); // Yellow
      case 2:
        return const Color(0xFFFF9500); // Orange
      case 3:
        return const Color(0xFFFF6B00); // Red-orange
      default:
        return const Color(0xFFFF3B30); // Red
    }
  }
}
