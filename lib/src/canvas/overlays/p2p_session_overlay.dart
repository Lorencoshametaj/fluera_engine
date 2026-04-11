// ============================================================================
// 🤝 P2P SESSION OVERLAY — Canvas overlay for P2P collaboration (Passo 7)
//
// Composites all P2P visual layers into a single overlay widget:
//   1. Ghost Cursor (P7-05) — semi-transparent peer cursor
//   2. Laser Pointer (P7-15) — temporary luminous teaching strokes
//   3. Markers (P7-08) — temporary !/?  markers from peer
//   4. Status Pill — floating connection status + mode indicator
//   5. Voice Indicator — speaking/muted state
//
// Usage:
//   Stack the overlay on top of the canvas CustomPaint:
//   ```dart
//   Stack(children: [
//     // ... canvas layers ...
//     if (p2pEngine != null)
//       P2PSessionOverlay(
//         engine: p2pEngine!,
//         canvasTransform: controller.transformationMatrix,
//       ),
//   ]);
//   ```
//
// ARCHITECTURE: StatefulWidget with AnimatedBuilder for 60fps updates.
// ============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import '../../p2p/p2p_engine.dart';
import '../../p2p/p2p_session_state.dart';

import '../../rendering/canvas/ghost_cursor_painter.dart';
import '../../rendering/canvas/laser_pointer_painter.dart';
import '../../rendering/canvas/p2p_marker_painter.dart';
import 'p2p_duel_overlay.dart';
import '../infinite_canvas_controller.dart';

/// 🤝 P2P Session Overlay Widget (Passo 7).
///
/// Renders all P2P visual elements on top of the canvas.
class P2PSessionOverlay extends StatefulWidget {
  /// The P2P engine driving the session.
  final P2PEngine engine;

  /// The canvas controller (for transform matrix).
  final InfiniteCanvasController canvasController;

  const P2PSessionOverlay({
    super.key,
    required this.engine,
    required this.canvasController,
  });

  @override
  State<P2PSessionOverlay> createState() => _P2PSessionOverlayState();
}

class _P2PSessionOverlayState extends State<P2PSessionOverlay>
    with TickerProviderStateMixin {
  /// Ticker for continuous repaint (ghost cursor lerp + laser fade).
  late AnimationController _tickController;

  /// Timer to prune expired laser segments.
  Timer? _laserPruneTimer;

  @override
  void initState() {
    super.initState();

    // 60fps ticker for smooth ghost cursor and laser fade.
    _tickController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();

    // Prune laser segments every 500ms.
    _laserPruneTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) {
        if (widget.engine.laserReceiver.pruneExpired()) {
          if (mounted) setState(() {});
        }
      },
    );

    widget.engine.addListener(_onEngineChanged);
  }

  @override
  void dispose() {
    _tickController.dispose();
    _laserPruneTimer?.cancel();
    widget.engine.removeListener(_onEngineChanged);
    super.dispose();
  }

  void _onEngineChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final engine = widget.engine;
    final session = engine.session;
    final phase = session.phase;

    // Only render when in an active session.
    if (phase == P2PSessionPhase.idle || phase == P2PSessionPhase.ended) {
      return const SizedBox.shrink();
    }

    final isInMode = phase == P2PSessionPhase.mode7a ||
        phase == P2PSessionPhase.mode7b ||
        phase == P2PSessionPhase.mode7c;

    final peerColor = session.remotePeer != null
        ? Color(session.remotePeer!.cursorColor)
        : const Color(0xFF42A5F5);

    final peerName = session.remotePeer?.displayName ?? 'Peer';

    return Stack(
      children: [
        // ── Ghost Cursor + Laser + Markers (canvas-space) ────────────
        if (isInMode) ...[
          // Ghost cursor.
          AnimatedBuilder(
            animation: _tickController,
            builder: (_, __) => CustomPaint(
              size: Size.infinite,
              painter: GhostCursorPainter(
                receiver: engine.cursorReceiver,
                peerColor: peerColor,
                peerName: peerName,
                canvasOffset: widget.canvasController.offset,
                canvasScale: widget.canvasController.scale,
              ),
            ),
          ),

          // Laser pointer (7b only).
          if (session.activeMode == P2PCollabMode.teaching &&
              engine.laserReceiver.hasVisibleSegments)
            AnimatedBuilder(
              animation: _tickController,
              builder: (_, __) => CustomPaint(
                size: Size.infinite,
                painter: LaserPointerPainter(
                  receiver: engine.laserReceiver,
                  canvasOffset: widget.canvasController.offset,
                  canvasScale: widget.canvasController.scale,
                ),
              ),
            ),

          // Markers.
          if (session.markers.isNotEmpty)
            CustomPaint(
              size: Size.infinite,
              painter: P2PMarkerPainter(
                markers: session.markers,
                canvasOffset: widget.canvasController.offset,
                canvasScale: widget.canvasController.scale,
              ),
            ),
        ],

        // ── Status Pill (screen-space, top-center) ───────────────────
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 0,
          right: 0,
          child: Center(
            child: _P2PStatusPill(
              phase: phase,
              mode: session.activeMode,
              peerName: peerName,
              connectionQuality: session.connectionQuality,
              isLocalTeaching: session.isLocalTeaching,
              teachingTurn: session.teachingTurn,
              duelPhase: session.duelPhase,
              isVoiceActive: engine.voice.isActive,
              isVoiceMuted: engine.voice.isLocalMuted,
              isPeerSpeaking: engine.voice.isRemoteSpeaking,
            ),
          ),
        ),

        // ── Duel Overlay (7c only) ───────────────────────────────────
        if (session.activeMode == P2PCollabMode.duel &&
            session.duelPhase != null)
          P2PDuelOverlay(
            phase: session.duelPhase!,
            peerName: peerName,
            onRecallDone: () => engine.session.finishLocalDuel(),
          ),
      ],
    );
  }
}

// =============================================================================
// 💊 P2P STATUS PILL — Shows connection state, mode, peer info
// =============================================================================

class _P2PStatusPill extends StatelessWidget {
  final P2PSessionPhase phase;
  final P2PCollabMode? mode;
  final String peerName;
  final P2PConnectionQuality connectionQuality;
  final bool isLocalTeaching;
  final TeachingTurn? teachingTurn;
  final DuelPhase? duelPhase;
  final bool isVoiceActive;
  final bool isVoiceMuted;
  final bool isPeerSpeaking;

  const _P2PStatusPill({
    required this.phase,
    required this.mode,
    required this.peerName,
    required this.connectionQuality,
    required this.isLocalTeaching,
    required this.teachingTurn,
    required this.duelPhase,
    required this.isVoiceActive,
    required this.isVoiceMuted,
    required this.isPeerSpeaking,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _bgColor.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: _bgColor.withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Connection quality dot.
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              color: _qualityColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),

          // Status text.
          Text(
            _statusText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),

          // Voice indicator.
          if (isVoiceActive) ...[
            const SizedBox(width: 8),
            Icon(
              isVoiceMuted ? Icons.mic_off : Icons.mic,
              size: 14,
              color: isVoiceMuted
                  ? Colors.white38
                  : (isPeerSpeaking
                      ? const Color(0xFF4CAF50)
                      : Colors.white70),
            ),
          ],
        ],
      ),
    );
  }

  Color get _bgColor {
    if (phase == P2PSessionPhase.reconnecting) {
      return const Color(0xFFFF9800); // Orange for reconnecting.
    }
    return switch (mode) {
      P2PCollabMode.visit => const Color(0xFF1565C0),     // Blue.
      P2PCollabMode.teaching => const Color(0xFF6A1B9A),  // Purple.
      P2PCollabMode.duel => const Color(0xFFC62828),      // Red.
      null => const Color(0xFF37474F),                     // Grey.
    };
  }

  Color get _qualityColor => switch (connectionQuality) {
    P2PConnectionQuality.excellent => const Color(0xFF4CAF50),
    P2PConnectionQuality.good => const Color(0xFF8BC34A),
    P2PConnectionQuality.degraded => const Color(0xFFFF9800),
    P2PConnectionQuality.poor => const Color(0xFFF44336),
  };

  String get _statusText {
    if (phase == P2PSessionPhase.reconnecting) {
      return '⟳ Reconnecting...';
    }
    if (phase == P2PSessionPhase.connecting ||
        phase == P2PSessionPhase.signaling) {
      return '⏳ Connecting...';
    }
    if (phase == P2PSessionPhase.waitingForPeer) {
      return '⏳ Waiting for peer...';
    }
    if (phase == P2PSessionPhase.connected && mode == null) {
      return '🤝 $peerName connected';
    }

    final modeLabel = switch (mode) {
      P2PCollabMode.visit => '👀 Visit',
      P2PCollabMode.teaching => '📚 Teaching',
      P2PCollabMode.duel => '⚔️ Duel',
      null => '',
    };

    final detail = _modeDetail;
    return detail.isEmpty ? '$modeLabel • $peerName' : '$modeLabel • $detail';
  }

  String get _modeDetail {
    if (mode == P2PCollabMode.teaching && teachingTurn != null) {
      return isLocalTeaching ? 'Your turn' : '$peerName teaches';
    }
    if (mode == P2PCollabMode.duel && duelPhase != null) {
      return switch (duelPhase!) {
        DuelPhase.countdown => 'Starting...',
        DuelPhase.recalling => 'Recalling!',
        DuelPhase.waitingForOther => 'Waiting...',
        DuelPhase.splitView => 'Compare!',
      };
    }
    return peerName;
  }
}
