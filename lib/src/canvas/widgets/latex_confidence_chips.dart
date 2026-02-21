import 'package:flutter/material.dart';
import '../../core/latex/latex_confidence_annotator.dart';

/// 🧮 LatexConfidenceChips — shows per-symbol confidence levels as M3 chips.
///
/// Renders uncertain regions with colored chips:
/// - 🟢 High    → `primaryContainer`
/// - 🟡 Medium  → `tertiaryContainer`
/// - 🟠 Low     → `secondaryContainer`
/// - 🔴 Very Low → `errorContainer`
///
/// Tapping a chip invokes [onChipTapped] with the annotation for
/// manual correction.
class LatexConfidenceChips extends StatelessWidget {
  /// The confidence annotations to display.
  final List<ConfidenceAnnotation> annotations;

  /// Called when the user taps an uncertain chip.
  final ValueChanged<ConfidenceAnnotation>? onChipTapped;

  /// Whether to show only uncertain regions (medium/low/veryLow).
  final bool onlyUncertain;

  const LatexConfidenceChips({
    super.key,
    required this.annotations,
    this.onChipTapped,
    this.onlyUncertain = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final visible =
        onlyUncertain
            ? annotations.where((a) => a.isUncertain).toList()
            : annotations;

    if (visible.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(
              Icons.check_circle_outline_rounded,
              size: 16,
              color: cs.primary,
            ),
            const SizedBox(width: 8),
            Text(
              'Confidenza alta su tutti i simboli',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: visible.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final ann = visible[i];
          final chipColors = _chipColors(ann.level, cs);

          return ActionChip(
            label: Text(
              ann.text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: chipColors.foreground,
              ),
            ),
            avatar: Icon(
              _confidenceIcon(ann.level),
              size: 14,
              color: chipColors.foreground,
            ),
            backgroundColor: chipColors.background,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: chipColors.border, width: 0.5),
            ),
            onPressed: () => onChipTapped?.call(ann),
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 4),
          );
        },
      ),
    );
  }

  IconData _confidenceIcon(ConfidenceLevel level) {
    switch (level) {
      case ConfidenceLevel.high:
        return Icons.check_circle_rounded;
      case ConfidenceLevel.medium:
        return Icons.help_outline_rounded;
      case ConfidenceLevel.low:
        return Icons.warning_amber_rounded;
      case ConfidenceLevel.veryLow:
        return Icons.error_outline_rounded;
      case ConfidenceLevel.unknown:
        return Icons.question_mark_rounded;
    }
  }

  _ChipColors _chipColors(ConfidenceLevel level, ColorScheme cs) {
    switch (level) {
      case ConfidenceLevel.high:
        return _ChipColors(
          cs.primaryContainer,
          cs.onPrimaryContainer,
          cs.primary.withValues(alpha: 0.3),
        );
      case ConfidenceLevel.medium:
        return _ChipColors(
          cs.tertiaryContainer,
          cs.onTertiaryContainer,
          cs.tertiary.withValues(alpha: 0.3),
        );
      case ConfidenceLevel.low:
        return _ChipColors(
          cs.secondaryContainer,
          cs.onSecondaryContainer,
          cs.secondary.withValues(alpha: 0.3),
        );
      case ConfidenceLevel.veryLow:
        return _ChipColors(
          cs.errorContainer,
          cs.onErrorContainer,
          cs.error.withValues(alpha: 0.3),
        );
      case ConfidenceLevel.unknown:
        return _ChipColors(
          cs.surfaceContainerHigh,
          cs.onSurfaceVariant,
          cs.outline.withValues(alpha: 0.3),
        );
    }
  }
}

class _ChipColors {
  final Color background;
  final Color foreground;
  final Color border;
  const _ChipColors(this.background, this.foreground, this.border);
}
