import 'package:flutter/material.dart';

// ============================================================================
// TOOLBAR SLIDERS — Width and opacity sliders with MD3 theming
// ============================================================================

/// Width slider with live value display (px → mm conversion)
class ToolbarWidthSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;
  final bool isDark;

  const ToolbarWidthSlider({
    super.key,
    required this.value,
    required this.onChanged,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 140,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Current value badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${(value / 3.78).toStringAsFixed(1)}mm',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withValues(alpha: 0.8),
              ),
            ),
          ),

          const SizedBox(width: 6),

          // Slider
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: cs.primary,
                inactiveTrackColor: cs.outlineVariant,
                thumbColor: cs.primary,
                overlayColor: cs.primary.withValues(alpha: 0.2),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                trackHeight: 3,
              ),
              child: Slider(
                value: value.clamp(0.5, 30.0),
                min: 0.5,
                max: 30.0,
                divisions: 59,
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opacity slider (0-100%)
class ToolbarOpacitySlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;
  final bool isDark;

  const ToolbarOpacitySlider({
    super.key,
    required this.value,
    required this.onChanged,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 140,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Current value badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${(value * 100).toInt()}%',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withValues(alpha: 0.8),
              ),
            ),
          ),

          const SizedBox(width: 6),

          // Slider
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: cs.tertiary,
                inactiveTrackColor: cs.outlineVariant,
                thumbColor: cs.tertiary,
                overlayColor: cs.tertiary.withValues(alpha: 0.2),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                trackHeight: 3,
              ),
              child: Slider(
                value: value,
                min: 0.1,
                max: 1.0,
                divisions: 18,
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
