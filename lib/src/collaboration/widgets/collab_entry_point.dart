// ============================================================================
// 🤝 COLLAB ENTRY POINT — Pro-gated share button for canvas collaboration
//
// Toolbar-ready chip. Behaviour by tier:
//   • Free / Plus → renders the upgrade affordance (Pro badge); tap fires
//                    [onUpgradeRequested] so the host can show the paywall.
//   • Pro          → tap invokes [onShareRequested] which the host wires
//                    to the share sheet (invite link generation + copy /
//                    share-via-system-UI / QR code).
//
// When a session is already live, the chip shifts to "connected" state and
// shows the active-peer count next to the icon.
//
// Decision plan: .claude/plans/analizza-tutta-fluera-app-floating-pebble.md
// Pillar Pro #2.
// ============================================================================

import 'package:flutter/material.dart';

/// 🤝 Compact entry-point chip for the canvas toolbar.
class CollabEntryPoint extends StatelessWidget {
  /// True when the current tier may use real-time collaboration. Pass
  /// `tierGate.canUseFeature(GatedFeature.collaboration)` here.
  final bool tierAllowsCollab;

  /// Number of peers currently connected (0 when not in a live session).
  /// Drives the "connected" visual state and the badge count.
  final int activePeerCount;

  /// Invoked when a Pro user taps the chip outside a live session.
  /// Host opens the share sheet (invite link generation + copy / system
  /// share UI / QR).
  final VoidCallback onShareRequested;

  /// Invoked when a Pro user taps the chip during a live session.
  /// Defaults to a no-op so hosts that don't need a connection panel
  /// (e.g. simple share-only flow) can omit it.
  final VoidCallback? onShowConnectionPanel;

  /// Invoked when a Free / Plus user taps the chip. Host shows the
  /// paywall focused on the collab pillar.
  final VoidCallback? onUpgradeRequested;

  /// Localised label override. Defaults to "Condividi".
  final String shareLabel;

  /// Localised label override for the connected state. Defaults to "Live".
  final String connectedLabel;

  const CollabEntryPoint({
    super.key,
    required this.tierAllowsCollab,
    required this.onShareRequested,
    this.activePeerCount = 0,
    this.onShowConnectionPanel,
    this.onUpgradeRequested,
    this.shareLabel = 'Condividi',
    this.connectedLabel = 'Live',
  });

  bool get _isConnected => activePeerCount > 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final tooltip = !tierAllowsCollab
        ? 'Collaborazione in tempo reale — funzione Pro'
        : (_isConnected
            ? '$activePeerCount partecipanti connessi'
            : 'Condividi il canvas con un compagno');

    final bg = _isConnected
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHigh;
    final fg = !tierAllowsCollab
        ? theme.colorScheme.onSurfaceVariant
        : (_isConnected
            ? theme.colorScheme.onPrimaryContainer
            : theme.colorScheme.primary);

    return Tooltip(
      message: tooltip,
      child: Material(
        color: bg,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () {
            if (!tierAllowsCollab) {
              onUpgradeRequested?.call();
              return;
            }
            if (_isConnected) {
              onShowConnectionPanel?.call();
            } else {
              onShareRequested();
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isConnected
                      ? Icons.groups_rounded
                      : Icons.share_outlined,
                  size: 18,
                  color: fg,
                ),
                const SizedBox(width: 6),
                Text(
                  _isConnected ? connectedLabel : shareLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_isConnected) ...[
                  const SizedBox(width: 6),
                  _PeerCountBadge(count: activePeerCount, theme: theme),
                ],
                if (!tierAllowsCollab) ...[
                  const SizedBox(width: 8),
                  _ProBadge(theme: theme),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PeerCountBadge extends StatelessWidget {
  final int count;
  final ThemeData theme;
  const _PeerCountBadge({required this.count, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$count',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ProBadge extends StatelessWidget {
  final ThemeData theme;
  const _ProBadge({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Pro',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
