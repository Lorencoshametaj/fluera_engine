import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../fluera_realtime_adapter.dart';

// =============================================================================
// 📡 SYNC STATUS INDICATOR
//
// Compact pill that summarizes the realtime collab health for the user:
//
//   • Live · N online        → connected, peers visible, outbox empty.
//   • Syncing · K            → connected, K ops still flushing through the
//                              outbox (e.g. just reconnected from offline).
//   • Offline · K queued     → no transport, K mutations buffered locally
//                              and will broadcast on reconnect.
//   • Reconnecting…          → transient state, showed during backoff.
//   • Sync error             → permanent failure; the host app should expose
//                              "retry" or "settings" affordances elsewhere.
//
// The widget is purely reactive. It owns no state of its own — three
// listenables drive every redraw:
//   - [FlueraRealtimeEngine.connectionState] for transport health,
//   - [FlueraRealtimeEngine.remoteCursors] for the online-peer count,
//   - [pendingOps] for the local outbox depth.
//
// Returns [SizedBox.shrink] when [engine] is null so callers can mount it
// unconditionally without a feature-flag check.
// =============================================================================

class SyncStatusIndicator extends StatelessWidget {
  /// The realtime engine driving connection + presence state.
  final FlueraRealtimeEngine? engine;

  /// Local outbox depth — typically wired to the canvas state's
  /// pending-ops notifier.
  final ValueListenable<int> pendingOps;

  const SyncStatusIndicator({
    super.key,
    required this.engine,
    required this.pendingOps,
  });

  @override
  Widget build(BuildContext context) {
    final localEngine = engine;
    if (localEngine == null) return const SizedBox.shrink();

    return ValueListenableBuilder<RealtimeConnectionState>(
      valueListenable: localEngine.connectionState,
      builder: (context, conn, _) {
        return ValueListenableBuilder<Map<String, Map<String, dynamic>>>(
          valueListenable: localEngine.remoteCursors,
          builder: (context, cursors, _) {
            return ValueListenableBuilder<int>(
              valueListenable: pendingOps,
              builder: (context, queued, _) {
                final state = _resolveState(conn, queued);
                return _StatusPill(
                  color: state.color,
                  label: state.label(cursors.length, queued),
                  pulsing: state.pulsing,
                );
              },
            );
          },
        );
      },
    );
  }

  _ResolvedState _resolveState(RealtimeConnectionState conn, int queued) {
    switch (conn) {
      case RealtimeConnectionState.connected:
        return queued > 0
            ? const _ResolvedState.syncing()
            : const _ResolvedState.live();
      case RealtimeConnectionState.connecting:
      case RealtimeConnectionState.reconnecting:
        return const _ResolvedState.reconnecting();
      case RealtimeConnectionState.disconnected:
        return const _ResolvedState.offline();
      case RealtimeConnectionState.error:
        return const _ResolvedState.error();
    }
  }
}

/// Discriminated state used internally to map connection + queue into the
/// concrete pill appearance.
class _ResolvedState {
  final Color color;
  final bool pulsing;
  final String Function(int onlineCount, int queued) label;

  const _ResolvedState._(this.color, this.pulsing, this.label);

  const _ResolvedState.live()
      : color = const Color(0xFF22C55E),
        pulsing = false,
        label = _liveLabel;
  const _ResolvedState.syncing()
      : color = const Color(0xFFF59E0B),
        pulsing = true,
        label = _syncingLabel;
  const _ResolvedState.reconnecting()
      : color = const Color(0xFFF59E0B),
        pulsing = true,
        label = _reconnectingLabel;
  const _ResolvedState.offline()
      : color = const Color(0xFF94A3B8),
        pulsing = false,
        label = _offlineLabel;
  const _ResolvedState.error()
      : color = const Color(0xFFEF4444),
        pulsing = false,
        label = _errorLabel;

  static String _liveLabel(int online, int queued) =>
      online == 0 ? 'Live' : 'Live · $online online';
  static String _syncingLabel(int online, int queued) => 'Syncing · $queued';
  static String _reconnectingLabel(int online, int queued) =>
      queued > 0 ? 'Reconnecting · $queued queued' : 'Reconnecting…';
  static String _offlineLabel(int online, int queued) =>
      queued > 0 ? 'Offline · $queued queued' : 'Offline';
  static String _errorLabel(int online, int queued) => 'Sync error';
}

class _StatusPill extends StatefulWidget {
  final Color color;
  final String label;
  final bool pulsing;

  const _StatusPill({
    required this.color,
    required this.label,
    required this.pulsing,
  });

  @override
  State<_StatusPill> createState() => _StatusPillState();
}

class _StatusPillState extends State<_StatusPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    if (widget.pulsing) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _StatusPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulsing != oldWidget.pulsing) {
      if (widget.pulsing) {
        _pulse.repeat(reverse: true);
      } else {
        _pulse.stop();
        _pulse.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) {
              final t = widget.pulsing ? _pulse.value : 1.0;
              return Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Color.lerp(
                    widget.color.withValues(alpha: 0.4),
                    widget.color,
                    t,
                  ),
                  shape: BoxShape.circle,
                ),
              );
            },
          ),
          const SizedBox(width: 6),
          Text(
            widget.label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
