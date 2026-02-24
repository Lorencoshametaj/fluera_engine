import 'package:flutter/material.dart';
import '../../drawing/models/brush_preset.dart';
import '../../drawing/models/pro_drawing_point.dart';

// ============================================================================
// TOOLBAR BRUSH STRIP — Category-tabbed preset selector (single row)
// ============================================================================

/// Professional Brush Strip with inline Writing / Artistic category toggle.
/// Single row: [📝|🎨] separator [pill pill pill ...]
/// Tap category to switch; tap pill to select; long-press for brush editor.
class ToolbarBrushStrip extends StatefulWidget {
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
  State<ToolbarBrushStrip> createState() => _ToolbarBrushStripState();
}

class _ToolbarBrushStripState extends State<ToolbarBrushStrip> {
  BrushCategory _activeCategory = BrushCategory.writing;

  List<BrushPreset> get _displayPresets {
    final all =
        widget.presets.isNotEmpty ? widget.presets : BrushPreset.defaultPresets;
    return all.where((p) => p.category == _activeCategory).toList();
  }

  /// Whether the selected brush belongs to the OTHER (non-active) category.
  bool get _selectedInOtherCategory {
    if (widget.selectedPresetId == null) return false;
    final all =
        widget.presets.isNotEmpty ? widget.presets : BrushPreset.defaultPresets;
    final selected = all.where((p) => p.id == widget.selectedPresetId);
    if (selected.isEmpty) return false;
    return selected.first.category != _activeCategory;
  }

  /// Category of the currently selected brush.
  BrushCategory? get _selectedCategory {
    if (widget.selectedPresetId == null) return null;
    final all =
        widget.presets.isNotEmpty ? widget.presets : BrushPreset.defaultPresets;
    final selected = all.where((p) => p.id == widget.selectedPresetId);
    if (selected.isEmpty) return null;
    return selected.first.category;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Inline category toggle ──
          _CategoryToggle(
            activeCategory: _activeCategory,
            selectedInOtherCategory: _selectedInOtherCategory,
            selectedCategory: _selectedCategory,
            isDark: widget.isDark,
            onCategoryChanged: (cat) => setState(() => _activeCategory = cat),
          ),
          // ── Thin separator ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Container(
              width: 1,
              height: 22,
              color: cs.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          // ── Animated pill row ──
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: Row(
              key: ValueKey(_activeCategory),
              mainAxisSize: MainAxisSize.min,
              children:
                  _displayPresets.map((preset) {
                    return ToolbarBrushPill(
                      preset: preset,
                      isSelected: widget.selectedPresetId == preset.id,
                      isPenActive: widget.isPenActive,
                      isDark: widget.isDark,
                      onTap: () => widget.onPresetSelected(preset),
                      onLongPress:
                          widget.selectedPresetId == preset.id
                              ? widget.onLongPress
                              : null,
                    );
                  }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact inline category toggle: two emoji buttons side by side.
class _CategoryToggle extends StatelessWidget {
  final BrushCategory activeCategory;
  final bool selectedInOtherCategory;
  final BrushCategory? selectedCategory;
  final bool isDark;
  final ValueChanged<BrushCategory> onCategoryChanged;

  const _CategoryToggle({
    required this.activeCategory,
    required this.selectedInOtherCategory,
    required this.selectedCategory,
    required this.isDark,
    required this.onCategoryChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(9),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTab(context, '📝', 'Writing', BrushCategory.writing, cs),
          _buildTab(context, '🎨', 'Artistic', BrushCategory.artistic, cs),
        ],
      ),
    );
  }

  Widget _buildTab(
    BuildContext context,
    String emoji,
    String tooltip,
    BrushCategory category,
    ColorScheme cs,
  ) {
    final isActive = activeCategory == category;
    final hasDot = selectedInOtherCategory && selectedCategory == category;

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: GestureDetector(
        onTap: () => onCategoryChanged(category),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color:
                isActive
                    ? cs.primary.withValues(alpha: isDark ? 0.3 : 0.15)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 13)),
              if (hasDot)
                Positioned(
                  top: -3,
                  right: -5,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
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
      case ProPenType.oilPaint:
        return isDark ? const Color(0xFF90CAF9) : const Color(0xFF1565C0);
      case ProPenType.sprayPaint:
        return isDark ? const Color(0xFFEF9A9A) : const Color(0xFFE53935);
      case ProPenType.neonGlow:
        return isDark ? const Color(0xFF84FFFF) : const Color(0xFF00B8D4);
      case ProPenType.inkWash:
        return isDark ? const Color(0xFF9E9E9E) : const Color(0xFF424242);
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
