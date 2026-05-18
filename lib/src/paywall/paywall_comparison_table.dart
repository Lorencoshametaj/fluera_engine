// ============================================================================
// 💳 PAYWALL COMPARISON TABLE — 3-column Free / Plus / Pro + Spark Pack
//
// V1 split paywall surface (2026-05-14). Designed to be embedded inside
// the host's paywall screen as a drop-in section — does NOT own the
// purchase buttons (the host wires those to RevenueCat / Stripe so the
// engine stays platform-neutral).
//
// Trasparenza-first pillar (memory: feedback_transparency_credits_anti_incumbent):
//   • Always shows the AI credit allowance per tier in the header.
//   • Shows an explicit incumbent comparison row ("Notion AI: ?  Fluera: 2000/mese visibili").
//   • Spark Pack section is part of the same surface — never hidden behind
//     a separate flow — because top-up exists ON EVERY TIER, including Free.
// ============================================================================

import 'package:flutter/material.dart';

import '../canvas/fluera_canvas_config.dart' show FlueraSubscriptionTier;
import '../config/v1_feature_gate.dart';

/// 💳 Single row of the comparison table.
class PaywallComparisonRow {
  /// User-facing feature label, e.g. "Crediti AI / mese".
  final String label;

  /// Optional leading icon. Falls back to no icon when null.
  final IconData? icon;

  /// Free-tier cell value, e.g. "100", "—", "Locale", "PNG".
  final String free;

  /// Plus-tier cell value.
  final String plus;

  /// Pro-tier cell value.
  final String pro;

  /// True when this row is one of the marketing "pillars" (Pro pillars #1
  /// — time travel, #2 — collab, #3 — voice/AI). Renders with stronger
  /// emphasis (bold label + accent on the Pro cell).
  final bool isPillar;

  const PaywallComparisonRow({
    required this.label,
    required this.free,
    required this.plus,
    required this.pro,
    this.icon,
    this.isPillar = false,
  });
}

/// 💳 V1 default content for the comparison table. The host can override
/// any row by passing a custom [rows] list — useful for A/B tests or
/// localised labels — but defaults match the decision plan §2.
///
/// Plan: .claude/plans/analizza-tutta-fluera-app-floating-pebble.md
abstract final class PaywallComparisonRowsV1 {
  PaywallComparisonRowsV1._();

  /// Canonical default rows for the V1 launch (in render order).
  static const List<PaywallComparisonRow> rows = [
    PaywallComparisonRow(
      label: 'Crediti AI / mese',
      icon: Icons.auto_awesome,
      free: '100',
      plus: '500',
      pro: '2000',
      isPillar: true,
    ),
    PaywallComparisonRow(
      label: 'Chat Fluera AI',
      icon: Icons.chat_bubble_outline,
      free: '1 cr / msg',
      plus: '1 cr / msg',
      pro: '1 cr / msg',
    ),
    PaywallComparisonRow(
      label: 'Pennelli',
      icon: Icons.brush_outlined,
      free: '3 base',
      plus: '6 V1 (altri in arrivo)',
      pro: '6 V1 (altri in arrivo)',
    ),
    PaywallComparisonRow(
      label: 'Formati export',
      icon: Icons.ios_share_outlined,
      free: 'PNG',
      plus: 'Tutti',
      pro: 'Tutti',
    ),
    PaywallComparisonRow(
      label: 'Cloud sync',
      icon: Icons.cloud_outlined,
      free: 'Locale',
      plus: '5 GB',
      pro: '50 GB',
    ),
    PaywallComparisonRow(
      label: 'Dispositivi sincronizzati',
      icon: Icons.devices_outlined,
      free: '1',
      plus: '2',
      pro: '∞',
    ),
    PaywallComparisonRow(
      label: 'Voice recording',
      icon: Icons.mic_outlined,
      free: '—',
      plus: '∞',
      pro: '∞',
    ),
    PaywallComparisonRow(
      label: 'Time Travel scrubber',
      icon: Icons.history_rounded,
      free: '—',
      plus: '—',
      pro: '✓',
      isPillar: true,
    ),
    PaywallComparisonRow(
      label: 'Audio ↔ stroke sync',
      icon: Icons.graphic_eq_outlined,
      free: '—',
      plus: '—',
      pro: '✓',
      isPillar: true,
    ),
    PaywallComparisonRow(
      label: 'Collaborazione real-time',
      icon: Icons.groups_outlined,
      free: '—',
      plus: '—',
      pro: '✓',
      isPillar: true,
    ),
    PaywallComparisonRow(
      label: '🔍 Background OCR proattivo',
      icon: Icons.manage_search_outlined,
      free: '—',
      plus: '—',
      pro: '✓',
      isPillar: true,
    ),
  ];
}

/// 💳 Incumbent-comparison row: anti-rate-limit-nascosto positioning.
/// See memory `feedback_transparency_credits_anti_incumbent` (2026-05-14).
class IncumbentComparisonEntry {
  /// Product name, e.g. "Notion AI".
  final String name;

  /// Public price tag, e.g. "€10 / mese".
  final String price;

  /// Marketing-style summary of the rate-limit policy, e.g. "limit nascosti"
  /// or "~50 transcript / mese".
  final String aiPolicy;

  const IncumbentComparisonEntry({
    required this.name,
    required this.price,
    required this.aiPolicy,
  });
}

/// 💳 Default incumbents for the IT student / knowledge-worker audience.
/// Updated 2026-05-14 with the published / surveyed terms.
abstract final class IncumbentsV1 {
  IncumbentsV1._();

  static const List<IncumbentComparisonEntry> entries = [
    IncumbentComparisonEntry(
      name: 'Notion AI',
      price: '€10 / mese',
      aiPolicy: 'Limiti non dichiarati',
    ),
    IncumbentComparisonEntry(
      name: 'ChatGPT Plus',
      price: '€20 / mese',
      aiPolicy: 'Rate limit non visibile',
    ),
    IncumbentComparisonEntry(
      name: 'Notability + AI',
      price: '€15 + €4 / mese',
      aiPolicy: '~50 transcript / mese',
    ),
  ];
}

/// 💳 Drop-in comparison table. Embed inside the host's paywall scroll
/// view; the host wires the purchase CTAs (RevenueCat / Stripe) outside
/// this widget so the engine stays platform-neutral.
class PaywallComparisonTable extends StatelessWidget {
  /// Rows to render. Defaults to [PaywallComparisonRowsV1.rows].
  final List<PaywallComparisonRow> rows;

  /// Incumbent entries for the trasparenza-first comparison row. Defaults
  /// to [IncumbentsV1.entries]. Pass an empty list to hide the section.
  final List<IncumbentComparisonEntry> incumbents;

  /// Tier the user is currently on. The matching column gets a "Piano
  /// attuale" badge so the user knows the baseline.
  final FlueraSubscriptionTier currentTier;

  /// Optional Spark Pack section toggle. Defaults to
  /// [V1FeatureGate.sparkPackVisible] so flipping the kill switch hides
  /// the section everywhere automatically.
  final bool? showSparkPackSection;

  /// Localised header overrides.
  final String freeHeader;
  final String plusHeader;
  final String proHeader;

  const PaywallComparisonTable({
    super.key,
    this.rows = PaywallComparisonRowsV1.rows,
    this.incumbents = IncumbentsV1.entries,
    this.currentTier = FlueraSubscriptionTier.free,
    this.showSparkPackSection,
    this.freeHeader = 'Free',
    this.plusHeader = 'Plus',
    this.proHeader = 'Pro',
  });

  /// Resolved spark-pack visibility: explicit override wins, otherwise
  /// the compile-time flag decides.
  bool get _effectiveShowSparkPack =>
      showSparkPackSection ?? V1FeatureGate.sparkPackVisible;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeaderRow(
          freeHeader: freeHeader,
          plusHeader: plusHeader,
          proHeader: proHeader,
          currentTier: currentTier,
        ),
        const SizedBox(height: 8),
        ...rows.map((r) => _BodyRow(row: r, currentTier: currentTier)),
        if (incumbents.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            'Cosa promettono gli altri',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ...incumbents.map((i) => _IncumbentRow(entry: i)),
          const SizedBox(height: 12),
          _TrasparencyCallout(theme: theme),
        ],
        if (_effectiveShowSparkPack) ...[
          const SizedBox(height: 24),
          _SparkPackSection(theme: theme),
        ],
      ],
    );
  }
}

class _HeaderRow extends StatelessWidget {
  final String freeHeader;
  final String plusHeader;
  final String proHeader;
  final FlueraSubscriptionTier currentTier;

  const _HeaderRow({
    required this.freeHeader,
    required this.plusHeader,
    required this.proHeader,
    required this.currentTier,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        const Expanded(flex: 4, child: SizedBox.shrink()),
        Expanded(
          flex: 2,
          child: _HeaderCell(
            label: freeHeader,
            sublabel: '€0',
            isCurrent: currentTier == FlueraSubscriptionTier.free,
            theme: theme,
          ),
        ),
        Expanded(
          flex: 2,
          child: _HeaderCell(
            label: plusHeader,
            sublabel: '€5,99',
            isCurrent: currentTier == FlueraSubscriptionTier.plus,
            theme: theme,
          ),
        ),
        Expanded(
          flex: 2,
          child: _HeaderCell(
            label: proHeader,
            sublabel: '€11,99',
            isCurrent: currentTier == FlueraSubscriptionTier.pro,
            theme: theme,
            accent: true,
          ),
        ),
      ],
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String label;
  final String sublabel;
  final bool isCurrent;
  final bool accent;
  final ThemeData theme;

  const _HeaderCell({
    required this.label,
    required this.sublabel,
    required this.isCurrent,
    required this.theme,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: accent ? theme.colorScheme.primary : null,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          sublabel,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (isCurrent) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Attuale',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _BodyRow extends StatelessWidget {
  final PaywallComparisonRow row;
  final FlueraSubscriptionTier currentTier;

  const _BodyRow({required this.row, required this.currentTier});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Row(
              children: [
                if (row.icon != null) ...[
                  Icon(row.icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    row.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: row.isPillar ? FontWeight.w700 : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: _Cell(
              value: row.free,
              accent: false,
              theme: theme,
              highlightedColumn: currentTier == FlueraSubscriptionTier.free,
            ),
          ),
          Expanded(
            flex: 2,
            child: _Cell(
              value: row.plus,
              accent: false,
              theme: theme,
              highlightedColumn: currentTier == FlueraSubscriptionTier.plus,
            ),
          ),
          Expanded(
            flex: 2,
            child: _Cell(
              value: row.pro,
              accent: row.isPillar,
              theme: theme,
              highlightedColumn: currentTier == FlueraSubscriptionTier.pro,
            ),
          ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  final String value;
  final bool accent;
  final bool highlightedColumn;
  final ThemeData theme;

  const _Cell({
    required this.value,
    required this.accent,
    required this.theme,
    this.highlightedColumn = false,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        value,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: accent || highlightedColumn ? FontWeight.w700 : null,
          color: accent
              ? theme.colorScheme.primary
              : (highlightedColumn
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _IncumbentRow extends StatelessWidget {
  final IncumbentComparisonEntry entry;
  const _IncumbentRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              entry.name,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              entry.price,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: Text(
              entry.aiPolicy,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.tertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrasparencyCallout extends StatelessWidget {
  final ThemeData theme;
  const _TrasparencyCallout({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.visibility_outlined,
              size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Su Fluera vedi sempre quanti crediti AI ti rimangono. '
              'Nessun rate limit nascosto, nessun "siamo spiacenti, riprova".',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SparkPackSection extends StatelessWidget {
  final ThemeData theme;
  const _SparkPackSection({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Crediti extra al volo · Spark Pack',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Disponibili su tutti i piani, non scadono mai, si usano prima dei mensili.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _SparkChip(
                title: 'Spark 250',
                subtitle: '250 crediti',
                price: '€1,99',
                highlight: false,
                theme: theme,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SparkChip(
                title: 'Spark 500',
                subtitle: '500 crediti · -25%',
                price: '€2,99',
                highlight: true,
                theme: theme,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SparkChip extends StatelessWidget {
  final String title;
  final String subtitle;
  final String price;
  final bool highlight;
  final ThemeData theme;

  const _SparkChip({
    required this.title,
    required this.subtitle,
    required this.price,
    required this.highlight,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlight
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
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
    );
  }
}
