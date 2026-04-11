// ============================================================================
// ⚔️ P2P DUEL OVERLAY — Countdown + Split View for Duel Mode (7c)
//
// Shows:
//   1. Countdown (3-2-1-GO!) before recall starts
//   2. Timer during recall phase
//   3. "Done!" button when finished
//   4. Split-view comparison after both finish
//
// Used inside P2PSessionOverlay when mode == duel.
// ============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../p2p/p2p_session_state.dart';

/// ⚔️ P2P Duel Overlay (7c).
///
/// Manages the duel flow: countdown → recall timer → waiting → split view.
class P2PDuelOverlay extends StatefulWidget {
  /// Current duel phase.
  final DuelPhase phase;

  /// Callback when local user finishes recall.
  final VoidCallback? onRecallDone;

  /// Duration allowed for recall (default 120s).
  final Duration recallDuration;

  /// Peer's display name.
  final String peerName;

  const P2PDuelOverlay({
    super.key,
    required this.phase,
    this.onRecallDone,
    this.recallDuration = const Duration(seconds: 120),
    required this.peerName,
  });

  @override
  State<P2PDuelOverlay> createState() => _P2PDuelOverlayState();
}

class _P2PDuelOverlayState extends State<P2PDuelOverlay>
    with TickerProviderStateMixin {
  // ── Countdown ────────────────────────────────────────────────────────
  late AnimationController _countdownController;
  int _countdownValue = 3;
  Timer? _countdownTimer;

  // ── Recall timer ─────────────────────────────────────────────────────
  Timer? _recallTimer;
  int _recallSecondsRemaining = 0;

  @override
  void initState() {
    super.initState();

    _countdownController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _recallSecondsRemaining = widget.recallDuration.inSeconds;

    if (widget.phase == DuelPhase.countdown) {
      _startCountdown();
    } else if (widget.phase == DuelPhase.recalling) {
      _startRecallTimer();
    }
  }

  @override
  void didUpdateWidget(covariant P2PDuelOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase != widget.phase) {
      if (widget.phase == DuelPhase.countdown) {
        _startCountdown();
      } else if (widget.phase == DuelPhase.recalling) {
        _startRecallTimer();
      } else {
        _countdownTimer?.cancel();
        _recallTimer?.cancel();
      }
    }
  }

  @override
  void dispose() {
    _countdownController.dispose();
    _countdownTimer?.cancel();
    _recallTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _countdownValue = 3;
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          _countdownValue--;
        });
        HapticFeedback.heavyImpact();
        _countdownController.forward(from: 0);

        if (_countdownValue <= 0) {
          timer.cancel();
        }
      },
    );
    _countdownController.forward(from: 0);
  }

  void _startRecallTimer() {
    _recallSecondsRemaining = widget.recallDuration.inSeconds;
    _recallTimer?.cancel();
    _recallTimer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          _recallSecondsRemaining--;
        });
        if (_recallSecondsRemaining <= 0) {
          timer.cancel();
          widget.onRecallDone?.call();
        }
        // Haptic at 10, 5, 3, 2, 1 seconds.
        if (_recallSecondsRemaining <= 5) {
          HapticFeedback.selectionClick();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return switch (widget.phase) {
      DuelPhase.countdown => _buildCountdown(),
      DuelPhase.recalling => _buildRecallTimer(),
      DuelPhase.waitingForOther => _buildWaiting(),
      DuelPhase.splitView => _buildSplitView(),
    };
  }

  // ── Countdown (3-2-1-GO!) ───────────────────────────────────────────

  Widget _buildCountdown() {
    return Center(
      child: AnimatedBuilder(
        animation: _countdownController,
        builder: (_, __) {
          final scale = 1.0 + (1.0 - _countdownController.value) * 0.5;
          final opacity = _countdownController.value > 0.8
              ? 1.0 - (_countdownController.value - 0.8) * 5.0
              : 1.0;

          return Transform.scale(
            scale: scale,
            child: Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Text(
                _countdownValue > 0 ? '$_countdownValue' : 'VIA!',
                style: TextStyle(
                  color: _countdownValue > 0
                      ? Colors.white
                      : const Color(0xFF4CAF50),
                  fontSize: _countdownValue > 0 ? 120 : 80,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4,
                  shadows: [
                    Shadow(
                      color: (_countdownValue > 0
                              ? const Color(0xFFC62828)
                              : const Color(0xFF4CAF50))
                          .withValues(alpha: 0.6),
                      blurRadius: 40,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Recall Timer ────────────────────────────────────────────────────

  Widget _buildRecallTimer() {
    final minutes = _recallSecondsRemaining ~/ 60;
    final seconds = _recallSecondsRemaining % 60;
    final timeString = '${minutes.toString().padLeft(2, '0')}'
        ':${seconds.toString().padLeft(2, '0')}';
    final isUrgent = _recallSecondsRemaining <= 10;

    return Positioned(
      top: MediaQuery.of(context).padding.top + 50,
      left: 0,
      right: 0,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Timer display.
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: (isUrgent
                        ? const Color(0xFFC62828)
                        : const Color(0xFF212121))
                    .withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isUrgent
                      ? const Color(0xFFF44336).withValues(alpha: 0.5)
                      : Colors.white.withValues(alpha: 0.1),
                ),
                boxShadow: [
                  if (isUrgent)
                    BoxShadow(
                      color: const Color(0xFFC62828).withValues(alpha: 0.4),
                      blurRadius: 20,
                    ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.timer,
                    color: isUrgent ? Colors.white : Colors.white70,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    timeString,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isUrgent ? 28 : 24,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'monospace',
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // "Done!" button.
            FilledButton.icon(
              onPressed: widget.onRecallDone,
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Ho finito!'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF50),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Waiting for other ───────────────────────────────────────────────

  Widget _buildWaiting() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        decoration: BoxDecoration(
          color: const Color(0xFF212121).withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Color(0xFFC62828),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '✅ Hai finito!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'In attesa di ${widget.peerName}...',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Split View comparison ───────────────────────────────────────────

  Widget _buildSplitView() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        decoration: BoxDecoration(
          color: const Color(0xFF212121).withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFFC62828).withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '⚔️ Confronto!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Confronta il tuo lavoro con ${widget.peerName}',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            // Placeholder for split-view toggle.
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SplitViewChip(
                  label: 'Il mio',
                  color: const Color(0xFF1565C0),
                  isActive: true,
                ),
                const SizedBox(width: 12),
                _SplitViewChip(
                  label: widget.peerName,
                  color: const Color(0xFFC62828),
                  isActive: false,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SplitViewChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool isActive;

  const _SplitViewChip({
    required this.label,
    required this.color,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isActive ? color.withValues(alpha: 0.3) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive ? color : Colors.white24,
          width: isActive ? 1.5 : 1.0,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isActive ? Colors.white : Colors.white54,
          fontSize: 13,
          fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}
