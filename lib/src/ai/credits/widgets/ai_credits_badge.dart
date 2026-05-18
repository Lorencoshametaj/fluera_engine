// ============================================================================
// 💎 AI CREDITS BADGE — Always-visible counter widget
//
// Pillar of the "trasparenza anti-incumbent" positioning (feedback memory
// 2026-05-14): never hide the user's AI budget. Tap-to-expand shows the
// estimator translation ("≈ 43 Ghost Map · 86 Socratic · 28 Exam") so the
// numbers are anchored to user-meaningful units.
//
// Visual rules:
//   • Tone is positive: "stai usando il tuo Plus" (not "remaining quota").
//   • Color steps soft: ambra only at the actual zero — never red.
//   • Pack credits and monthly credits are surfaced separately on expand
//     ("250 Pack · 223 mese") so the user understands consumption order.
//
// The widget binds to [AiCreditsController.credits]; no setState plumbing
// needed in the parent.
// ============================================================================

import 'package:flutter/material.dart';

import '../../../config/v1_feature_gate.dart';
import '../ai_credits_controller.dart';
import '../ai_credits_costs.dart';

/// 💎 Compact, tap-to-expand credits counter for the canvas header bar.
///
/// Designed to live next to the canvas title — fits ~96 logical pixels wide
/// in collapsed state. Tapping flips into an inline detail row (or a
/// PopupMenuButton overlay on small viewports).
class AiCreditsBadge extends StatelessWidget {
  final AiCreditsController controller;

  /// Optional callback when the user taps the badge to see details.
  /// Use to trigger analytics ("user opened credits inspector").
  final VoidCallback? onTap;

  /// Optional callback when the user taps an empty-state CTA. Wire this
  /// to the Spark Pack purchase dialog in the host app.
  final VoidCallback? onBuyPack;

  const AiCreditsBadge({
    super.key,
    required this.controller,
    this.onTap,
    this.onBuyPack,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AiCreditsSnapshot?>(
      valueListenable: controller.credits,
      builder: (context, snapshot, _) {
        if (snapshot == null) return const SizedBox.shrink();
        return _BadgeChip(
          snapshot: snapshot,
          onTap: onTap,
          onBuyPack: onBuyPack,
        );
      },
    );
  }
}

class _BadgeChip extends StatelessWidget {
  final AiCreditsSnapshot snapshot;
  final VoidCallback? onTap;
  final VoidCallback? onBuyPack;

  const _BadgeChip({
    required this.snapshot,
    this.onTap,
    this.onBuyPack,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = snapshot.total;
    final isExhausted = total <= 0;
    final accent = _accentFor(snapshot, theme.colorScheme);

    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => _showDetails(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome, size: 16, color: accent),
              const SizedBox(width: 6),
              Text(
                isExhausted ? '0' : total.toString(),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'cr',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _accentFor(AiCreditsSnapshot snapshot, ColorScheme cs) {
    final fraction = snapshot.monthlyUsedFraction;
    if (snapshot.total <= 0) return cs.tertiary;       // exhausted → soft accent
    if (fraction >= 0.95) return cs.tertiary;
    if (fraction >= 0.80) return cs.secondary;
    return cs.primary;
  }

  Future<void> _showDetails(BuildContext context) async {
    onTap?.call();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _CreditsDetailsSheet(
        snapshot: snapshot,
        onBuyPack: onBuyPack,
      ),
    );
  }
}

/// Bottom sheet that translates raw credits into "≈ N feature uses" so the
/// number is anchored to user-meaningful units.
class _CreditsDetailsSheet extends StatelessWidget {
  final AiCreditsSnapshot snapshot;
  final VoidCallback? onBuyPack;

  const _CreditsDetailsSheet({
    required this.snapshot,
    this.onBuyPack,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allowance =
        AiCreditsCosts.monthlyAllowance[snapshot.tier] ?? snapshot.monthlyCredits;
    final fraction = snapshot.monthlyUsedFraction;
    final monthlyUsed = (allowance - snapshot.monthlyCredits).clamp(0, allowance);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Headline ──────────────────────────────────────────────
            Row(
              children: [
                Icon(Icons.auto_awesome, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '${snapshot.total} crediti',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              snapshot.packCredits > 0
                  ? '${snapshot.packCredits} dal pacchetto · ${snapshot.monthlyCredits} di questo mese'
                  : '${snapshot.monthlyCredits} di questo mese',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),

            // ── Monthly progress bar ─────────────────────────────────
            if (allowance > 0) ...[
              LinearProgressIndicator(
                value: (1.0 - fraction).clamp(0.0, 1.0),
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
              const SizedBox(height: 6),
              Text(
                'Usati $monthlyUsed / $allowance del piano ${_tierLabel(snapshot.tier)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Estimator: raw credits → user-meaningful units ───────
            Text(
              'Con questi crediti puoi fare circa:',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            _EstimateRow(
              icon: Icons.map_outlined,
              label: 'Confronti Ghost Map',
              estimate: snapshot.total ~/ AiCreditsCosts.ghostMap,
            ),
            _EstimateRow(
              icon: Icons.psychology_outlined,
              label: 'Stage Socratic',
              estimate: snapshot.total ~/ AiCreditsCosts.socraticStage,
            ),
            _EstimateRow(
              icon: Icons.school_outlined,
              label: 'Domande Exam',
              estimate: snapshot.total ~/ AiCreditsCosts.examQuestion,
            ),
            _EstimateRow(
              icon: Icons.chat_bubble_outline,
              label: 'Messaggi chat',
              estimate: snapshot.total ~/ (AiCreditsCosts.chat == 0 ? 1 : AiCreditsCosts.chat),
            ),
            const SizedBox(height: 16),

            // ── Reset hint ───────────────────────────────────────────
            Row(
              children: [
                Icon(Icons.refresh,
                    size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    V1FeatureGate.sparkPackVisible
                        ? 'Il piano mensile si ricarica ${_friendlyReset(snapshot.monthlyResetAt)}. I crediti del pacchetto non scadono.'
                        : 'Il piano mensile si ricarica ${_friendlyReset(snapshot.monthlyResetAt)}.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── CTA ──────────────────────────────────────────────────
            // 💎 Spark Pack CTA hidden when the kill switch is off
            // ([V1FeatureGate.sparkPackVisible] = false). Flip the flag
            // to re-expose top-up without touching this widget.
            if (onBuyPack != null && V1FeatureGate.sparkPackVisible)
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    onBuyPack!();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Aggiungi Spark Pack'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _tierLabel(String tier) {
    return switch (tier) {
      'pro' => 'Pro',
      'plus' => 'Plus',
      'essential' => 'Essential',
      _ => 'Free',
    };
  }

  String _friendlyReset(DateTime resetAt) {
    final now = DateTime.now().toUtc();
    final delta = resetAt.toUtc().difference(now);
    if (delta.isNegative) return 'a breve';
    if (delta.inDays >= 1) {
      return delta.inDays == 1 ? 'tra 1 giorno' : 'tra ${delta.inDays} giorni';
    }
    if (delta.inHours >= 1) {
      return 'tra ${delta.inHours} ore';
    }
    return 'tra meno di un\'ora';
  }
}

class _EstimateRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final int estimate;

  const _EstimateRow({
    required this.icon,
    required this.label,
    required this.estimate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          Text(
            '~ $estimate',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
