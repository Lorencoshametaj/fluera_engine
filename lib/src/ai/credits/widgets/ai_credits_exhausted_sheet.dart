// ============================================================================
// 💎 AI CREDITS EXHAUSTED SHEET — Honest empty-state with Spark Pack CTA
//
// Bottom sheet shown when the user hit 0 credits. Tone is positive ("hai
// usato bene il tuo Plus") and offers two CTAs:
//   1. Wait for the monthly reset (X days remaining)
//   2. Buy a Spark Pack (250 cr @ €1.99 or 500 cr @ €2.99)
//
// The host wires the actual purchase flow via [onSelectPack] — this widget
// stays platform-agnostic (no RevenueCat / Stripe imports in the engine).
// ============================================================================

import 'package:flutter/material.dart';

import '../ai_credits_controller.dart';

/// 💎 Identifies a Spark Pack offering. Maps 1:1 to RevenueCat consumable
/// product IDs in [Fluera/lib/services/subscription_products.dart].
enum SparkPackSku {
  /// 250 credits @ €1.99 (RevenueCat: `fluera.spark.250`).
  spark250,

  /// 500 credits @ €2.99 (RevenueCat: `fluera.spark.500`, ~25% discount).
  spark500,
}

/// Show the exhausted-credits sheet. Returns the SKU the user chose, or
/// `null` if they dismissed without buying.
Future<SparkPackSku?> showAiCreditsExhaustedSheet({
  required BuildContext context,
  required AiCreditsSnapshot snapshot,
  AiCreditFeatureRef? blockedFeature,
}) {
  return showModalBottomSheet<SparkPackSku>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _ExhaustedSheet(
      snapshot: snapshot,
      blockedFeature: blockedFeature,
    ),
  );
}

/// 💎 Engine-side feature reference for the exhaustion sheet. Decoupled
/// from the host's localisation/icon system — the sheet renders a generic
/// "questa funzione" string when null.
class AiCreditFeatureRef {
  final String label;
  final IconData icon;

  const AiCreditFeatureRef({required this.label, required this.icon});
}

class _ExhaustedSheet extends StatelessWidget {
  final AiCreditsSnapshot snapshot;
  final AiCreditFeatureRef? blockedFeature;

  const _ExhaustedSheet({
    required this.snapshot,
    this.blockedFeature,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blocked = blockedFeature;
    final resetIn = _resetFriendly(snapshot.monthlyResetAt);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome,
                    color: theme.colorScheme.tertiary, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Hai usato tutti i crediti AI',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              blocked != null
                  ? 'Per usare ${blocked.label} ti serve qualche credito in più. '
                      'Il piano mensile si ricarica $resetIn — '
                      'oppure puoi continuare ora con uno Spark Pack.'
                  : 'Il piano mensile si ricarica $resetIn. '
                      'Se vuoi continuare ora, scegli uno Spark Pack.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),

            _PackTile(
              title: 'Spark 250',
              price: '€1,99',
              creditsLabel: '250 crediti',
              subtitle:
                  '≈ 31 Ghost Map, 62 stage Socratic o 20 domande Exam.',
              onTap: () => Navigator.of(context).pop(SparkPackSku.spark250),
            ),
            const SizedBox(height: 10),
            _PackTile(
              title: 'Spark 500',
              price: '€2,99',
              creditsLabel: '500 crediti',
              subtitle:
                  '≈ 62 Ghost Map, 125 stage Socratic o 41 domande Exam. -25% al credito.',
              highlight: true,
              onTap: () => Navigator.of(context).pop(SparkPackSku.spark500),
            ),
            const SizedBox(height: 16),

            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                minimumSize: const Size(double.infinity, 44),
                alignment: Alignment.center,
              ),
              child: Text('Aspetto il reset ($resetIn)'),
            ),
            const SizedBox(height: 4),
            Text(
              'I crediti dei pacchetti non scadono e si usano prima di quelli mensili.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _resetFriendly(DateTime resetAt) {
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

class _PackTile extends StatelessWidget {
  final String title;
  final String price;
  final String creditsLabel;
  final String subtitle;
  final bool highlight;
  final VoidCallback onTap;

  const _PackTile({
    required this.title,
    required this.price,
    required this.creditsLabel,
    required this.subtitle,
    required this.onTap,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: highlight
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '· $creditsLabel',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                price,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: highlight
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
