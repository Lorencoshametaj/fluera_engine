// ============================================================================
// 🎬 TIME TRAVEL ENTRY POINT — Pro-gated launch button for the scrubber UI
//
// Toolbar-ready chip. Behaviour by tier:
//   • Free / Plus → renders the upgrade affordance (Pro badge); tap fires
//                    [onUpgradeRequested] so the host can show the paywall.
//   • Pro          → tap opens the [SynchronizedPlaybackOverlay] in a
//                    fullscreen modal route.
//
// Decision plan: .claude/plans/analizza-tutta-fluera-app-floating-pebble.md
// Pillar Pro #1 — see §1 Pro = "Studio amplificato".
// ============================================================================

import 'package:flutter/material.dart';

import '../retention/time_travel_retention_policy.dart';

/// 🎬 Compact entry-point chip. The host wires [onOpenScrubber] to push
/// the `SynchronizedPlaybackOverlay` modal route — the engine keeps this
/// widget overlay-agnostic so the canvas screen can choose how / where
/// the playback UI is presented (fullscreen, side sheet, etc.).
class TimeTravelEntryPoint extends StatelessWidget {
  final TimeTravelRetentionPolicy policy;

  /// True when the user has any recorded session worth playing back.
  /// When false, the chip renders an empty-state tooltip ("Studia un po'
  /// e poi torna a riguardarti."). Default true so the chip is visible
  /// before the host wires the real "has sessions" probe.
  final bool hasSessions;

  /// Invoked when a Pro user taps the chip with at least one session.
  /// Host pushes the `SynchronizedPlaybackOverlay` modal route here.
  final VoidCallback onOpenScrubber;

  /// Invoked when a Free / Plus user taps the chip. Host shows the
  /// paywall focused on the time-travel pillar.
  final VoidCallback? onUpgradeRequested;

  /// Localised label override. Defaults to "Time Travel" (brand term).
  final String label;

  const TimeTravelEntryPoint({
    super.key,
    required this.policy,
    required this.onOpenScrubber,
    this.hasSessions = true,
    this.onUpgradeRequested,
    this.label = 'Time Travel',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canPlay = policy.canShowPlaybackUi;
    final disabled = canPlay && !hasSessions;

    final fg = canPlay
        ? (disabled
            ? theme.colorScheme.onSurfaceVariant
            : theme.colorScheme.primary)
        : theme.colorScheme.onSurfaceVariant;

    return Tooltip(
      message: _tooltipFor(canPlay: canPlay, disabled: disabled),
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: disabled
              ? null
              : () {
                  if (canPlay) {
                    onOpenScrubber();
                  } else {
                    onUpgradeRequested?.call();
                  }
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.history_rounded, size: 18, color: fg),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (!canPlay) ...[
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

  String _tooltipFor({required bool canPlay, required bool disabled}) {
    if (!canPlay) {
      return 'Riguardati mentre studi — funzione Pro';
    }
    if (disabled) {
      return 'Studia un po\' e poi torna a riguardarti';
    }
    return 'Apri lo scrubber Time Travel';
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
