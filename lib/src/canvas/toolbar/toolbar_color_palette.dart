import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ============================================================================
// TOOLBAR COLOR PALETTE — 6-slot customizable color palette
// ============================================================================

/// Compact color palette with 6 customizable slots
class ToolbarColorPalette extends StatelessWidget {
  final List<Color> colors;
  final Color selectedColor;
  final ValueChanged<Color> onChanged;
  final ValueChanged<int> onLongPress;
  final bool isDark;

  const ToolbarColorPalette({
    super.key,
    required this.colors,
    required this.selectedColor,
    required this.onChanged,
    required this.onLongPress,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(colors.length, (index) {
        final color = colors[index];
        final isSelected = selectedColor.toARGB32() == color.toARGB32();
        return Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ToolbarColorButton(
            color: color,
            isSelected: isSelected,
            onTap: () => onChanged(color),
            onLongPress: () => onLongPress(index),
            isDark: isDark,
          ),
        );
      }),
    );
  }
}

/// Individual color swatch button with selection animation
class ToolbarColorButton extends StatelessWidget {
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool isDark;

  const ToolbarColorButton({
    super.key,
    required this.color,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: () {
          HapticFeedback.mediumImpact();
          onLongPress();
        },
        customBorder: const CircleBorder(),
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          width: isSelected ? 32 : 28,
          height: isSelected ? 32 : 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(
              color: isSelected ? cs.onSurface : cs.outlineVariant,
              width: isSelected ? 2.5 : 1.5,
            ),
            boxShadow:
                isSelected
                    ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.4),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ]
                    : null,
          ),
          child:
              isSelected
                  ? Icon(
                    Icons.check,
                    size: 14,
                    color:
                        color.computeLuminance() > 0.5
                            ? Colors.black
                            : Colors.white,
                  )
                  : null,
        ),
      ),
    );
  }
}
