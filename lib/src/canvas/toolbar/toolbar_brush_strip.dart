import 'package:flutter/material.dart';
import '../../drawing/models/brush_preset.dart';
import '../../drawing/models/pro_drawing_point.dart';

// ============================================================================
// TOOLBAR BRUSH STRIP — Procreate-style preset selector
// ============================================================================

/// Professional Brush Strip — animated preset pills.
/// Shows all brush presets (built-in + custom) as pills.
/// Tap to select; long-press for brush editor.
class ToolbarBrushStrip extends StatelessWidget {
  final List<BrushPreset> presets;
  final String? selectedPresetId;
  final bool isPenActive;
  final ValueChanged<BrushPreset> onPresetSelected;
  final VoidCallback? onLongPress;
  final bool isDark;

  const ToolbarBrushStrip({
    super.key,
    required this.presets,
    this.selectedPresetId,
    required this.isPenActive,
    required this.onPresetSelected,
    this.onLongPress,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final displayPresets =
        presets.isNotEmpty ? presets : BrushPreset.builtInPresets;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children:
            displayPresets.map((preset) {
              return ToolbarBrushPill(
                preset: preset,
                isSelected: selectedPresetId == preset.id,
                isPenActive: isPenActive,
                isDark: isDark,
                onTap: () => onPresetSelected(preset),
                onLongPress: onLongPress,
              );
            }).toList(),
      ),
    );
  }
}

/// Individual brush preset pill
class ToolbarBrushPill extends StatelessWidget {
  final BrushPreset preset;
  final bool isSelected;
  final bool isPenActive;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const ToolbarBrushPill({
    super.key,
    required this.preset,
    required this.isSelected,
    required this.isPenActive,
    required this.isDark,
    required this.onTap,
    this.onLongPress,
  });

  /// Accent color based on pen type
  Color get _accentColor {
    switch (preset.penType) {
      case ProPenType.ballpoint:
        return isDark ? const Color(0xFF64B5F6) : const Color(0xFF1976D2);
      case ProPenType.fountain:
        return isDark ? const Color(0xFF81C784) : const Color(0xFF388E3C);
      case ProPenType.pencil:
        return isDark ? const Color(0xFFFFB74D) : const Color(0xFFF57C00);
      case ProPenType.highlighter:
        return isDark ? const Color(0xFFFFF176) : const Color(0xFFFBC02D);
      case ProPenType.watercolor:
        return isDark ? const Color(0xFF80DEEA) : const Color(0xFF00838F);
      case ProPenType.marker:
        return isDark ? const Color(0xFFCE93D8) : const Color(0xFF7B1FA2);
      case ProPenType.charcoal:
        return isDark ? const Color(0xFFBCAAA4) : const Color(0xFF5D4037);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isHighlighted = isSelected && isPenActive;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: isSelected ? onLongPress : null,
          borderRadius: BorderRadius.circular(10),
          splashColor: _accentColor.withValues(alpha: 0.2),
          highlightColor: _accentColor.withValues(alpha: 0.1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(
              horizontal: isHighlighted ? 10 : 7,
              vertical: 5,
            ),
            decoration: BoxDecoration(
              gradient:
                  isHighlighted
                      ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          _accentColor.withValues(alpha: isDark ? 0.35 : 0.18),
                          _accentColor.withValues(alpha: isDark ? 0.2 : 0.08),
                        ],
                      )
                      : null,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color:
                    isHighlighted
                        ? _accentColor.withValues(alpha: 0.6)
                        : Colors.transparent,
                width: 1.5,
              ),
              boxShadow:
                  isHighlighted
                      ? [
                        BoxShadow(
                          color: _accentColor.withValues(alpha: 0.25),
                          blurRadius: 8,
                          spreadRadius: 0,
                        ),
                      ]
                      : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  preset.icon,
                  style: TextStyle(fontSize: isHighlighted ? 16 : 14),
                ),
                if (isHighlighted) ...[
                  const SizedBox(width: 5),
                  Text(
                    preset.name,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _accentColor,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
