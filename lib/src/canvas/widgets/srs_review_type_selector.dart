// ============================================================================
// ⚡🧠 SRS REVIEW TYPE SELECTOR — Micro vs Deep review choice
//
// Spec: P8-15 → P8-18, CA-136, CA-137
//
// When the student returns and SRS nodes are due, this bottom sheet lets
// them choose between:
//   - Micro-Review (⚡): ≤5 min, recall-only, no rewriting, top-N nodes
//   - Deep-Review (🧠): full session with mandatory rewrite for failures
//
// The choice affects how many nodes are presented and what happens on
// incorrect answers (deep-review requires the student to rewrite).
//
// Architecture: pure Flutter widget, no external dependencies.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The two types of SRS review session.
enum SrsReviewType {
  /// ⚡ Quick review: ≤5 min, recall-only, top-N nodes by urgency.
  /// No mandatory rewriting. SRS updated normally.
  micro,

  /// 🧠 Full review: all due nodes, mandatory rewrite for failed recalls.
  /// Socratic follow-up questions available.
  deep,
}

/// Shows a bottom sheet for the student to choose between Micro and Deep review.
///
/// Returns the selected [SrsReviewType], or `null` if dismissed.
Future<SrsReviewType?> showSrsReviewTypeSelector(
  BuildContext context, {
  required int totalDueNodes,
}) {
  return showModalBottomSheet<SrsReviewType>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => _SrsReviewTypeSelectorSheet(
      totalDueNodes: totalDueNodes,
    ),
  );
}

class _SrsReviewTypeSelectorSheet extends StatelessWidget {
  final int totalDueNodes;

  const _SrsReviewTypeSelectorSheet({required this.totalDueNodes});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    // Micro-review caps at 10-15 nodes
    final microCount = totalDueNodes.clamp(0, 12);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1A1A2E)
            : cs.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.15),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Handle bar ──
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: cs.onSurface.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // ── Title ──
          Text(
            '$totalDueNodes nodi da ripassare',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Scegli il tipo di ripasso',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 24),

          // ── Micro Review card ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _ReviewTypeCard(
              icon: '⚡',
              title: 'Ripasso veloce',
              subtitle: '~5 min · solo richiamo · $microCount nodi',
              description: 'Rivela ogni nodo e valuta se lo ricordi. '
                  'Nessuna riscrittura richiesta.',
              accentColor: const Color(0xFF4FC3F7),
              isDark: isDark,
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).pop(SrsReviewType.micro);
              },
            ),
          ),
          const SizedBox(height: 12),

          // ── Deep Review card ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _ReviewTypeCard(
              icon: '🧠',
              title: 'Ripasso profondo',
              subtitle: 'Tutti i $totalDueNodes nodi · riscrittura per errori',
              description: 'Per i nodi dimenticati dovrai riscrivere il '
                  'concetto a mano, consolidando la memoria.',
              accentColor: const Color(0xFFAB47BC),
              isDark: isDark,
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).pop(SrsReviewType.deep);
              },
            ),
          ),

          const SizedBox(height: 16),

          // ── Skip option ──
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: Text(
              'Non ora',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.4),
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _ReviewTypeCard extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;
  final String description;
  final Color accentColor;
  final bool isDark;
  final VoidCallback onTap;

  const _ReviewTypeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.accentColor,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark
          ? accentColor.withValues(alpha: 0.08)
          : accentColor.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: accentColor.withValues(alpha: 0.1),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accentColor.withValues(alpha: isDark ? 0.2 : 0.15),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              // ── Icon ──
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  icon,
                  style: const TextStyle(fontSize: 24),
                ),
              ),
              const SizedBox(width: 14),

              // ── Text content ──
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        color: (isDark ? Colors.white : Colors.black)
                            .withValues(alpha: 0.5),
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Arrow ──
              Icon(
                Icons.chevron_right_rounded,
                color: accentColor.withValues(alpha: 0.5),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
