import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'toolbar_tokens.dart';

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

/// Individual color swatch button with premium double-ring selection animation.
///
/// When selected:
///   • Outer ring: colored glow border (tool's active color)
///   • Inner ring: thin white/black separator
///   • Swatch grows slightly (32→30→26 nested visual)
///   • Color-luminance-adaptive check icon
class ToolbarColorButton extends StatefulWidget {
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
  State<ToolbarColorButton> createState() => _ToolbarColorButtonState();
}

class _ToolbarColorButtonState extends State<ToolbarColorButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressCtrl;
  late final Animation<double> _pressScale;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: ToolbarTokens.animFast,
    );
    _pressScale = Tween(begin: 1.0, end: 0.84).animate(
      CurvedAnimation(parent: _pressCtrl, curve: ToolbarTokens.curveActive),
    );
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLight = widget.color.computeLuminance() > 0.5;
    final checkColor = isLight ? Colors.black87 : Colors.white;

    return GestureDetector(
      onTapDown: (_) => _pressCtrl.forward(),
      onTapUp: (_) {
        _pressCtrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _pressCtrl.reverse(),
      onLongPress: () {
        HapticFeedback.mediumImpact();
        widget.onLongPress();
      },
      child: AnimatedBuilder(
        animation: _pressScale,
        builder:
            (_, child) =>
                Transform.scale(scale: _pressScale.value, child: child),
        child: AnimatedContainer(
          duration: ToolbarTokens.animNormal,
          curve: ToolbarTokens.curveActive,
          width: widget.isSelected ? 34 : 28,
          height: widget.isSelected ? 34 : 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // Outer ring: colored glow border when selected
            border: Border.all(
              color:
                  widget.isSelected
                      ? widget.color.withValues(alpha: 0.75)
                      : Colors.transparent,
              width: widget.isSelected ? 2.0 : 0,
            ),
            boxShadow:
                widget.isSelected
                    ? [
                      BoxShadow(
                        color: widget.color.withValues(alpha: 0.45),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ]
                    : null,
          ),
          // Inner separator + fill
          child: AnimatedContainer(
            duration: ToolbarTokens.animNormal,
            curve: ToolbarTokens.curveActive,
            margin:
                widget.isSelected
                    ? const EdgeInsets.all(2.5) // white separator gap
                    : EdgeInsets.zero,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color,
              border:
                  widget.isSelected
                      ? Border.all(
                        color: (widget.isDark ? Colors.white : Colors.white)
                            .withValues(alpha: 0.35),
                        width: 1.0,
                      )
                      : Border.all(
                        color: (widget.isDark ? Colors.white : Colors.black)
                            .withValues(alpha: 0.18),
                        width: 1.0,
                      ),
            ),
            child:
                widget.isSelected
                    ? Center(
                      child: AnimatedOpacity(
                        opacity: 1.0,
                        duration: ToolbarTokens.animFast,
                        child: Icon(
                          Icons.check_rounded,
                          size: 12,
                          color: checkColor,
                        ),
                      ),
                    )
                    : null,
          ),
        ),
      ),
    );
  }
}
