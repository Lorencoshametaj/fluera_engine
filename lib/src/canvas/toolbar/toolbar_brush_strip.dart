import 'package:flutter/material.dart';
import '../../drawing/models/brush_preset.dart';
import '../../drawing/models/pro_drawing_point.dart';
import '../fluera_canvas_config.dart' show FlueraSubscriptionTier;

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

  /// Current user's subscription tier — pills render a 🔒 badge and
  /// suppress selection on Free for any preset NOT in
  /// [BrushPreset.freePresetIds]. Plus / Pro see no gating.
  final FlueraSubscriptionTier subscriptionTier;

  /// Fired when a Free user taps a locked preset. The host typically
  /// shows a paywall sheet / upgrade banner with the supplied message.
  /// When `null`, taps on locked pills are silently ignored (no UX,
  /// but no crash either).
  final void Function(String message)? onUpgradePrompt;

  const ToolbarBrushStrip({
    super.key,
    required this.presets,
    this.selectedPresetId,
    required this.isPenActive,
    required this.onPresetSelected,
    this.onLongPress,
    required this.isDark,
    this.subscriptionTier = FlueraSubscriptionTier.free,
    this.onUpgradePrompt,
  });

  @override
  State<ToolbarBrushStrip> createState() => _ToolbarBrushStripState();
}

class _ToolbarBrushStripState extends State<ToolbarBrushStrip> {
  // V1: category toggle removed — all non-GPU presets shown in a flat list.
  // Re-enable _CategoryToggle post-launch when GPU pens are ready.

  List<BrushPreset> get _displayPresets {
    return widget.presets.isNotEmpty
        ? widget.presets
        : BrushPreset.defaultPresets;
  }

  /// Whether [preset] is locked behind the user's tier. Free users are
  /// limited to [BrushPreset.freePresetIds]; Plus / Pro see no gating.
  bool _isLockedFor(BrushPreset preset) {
    if (widget.subscriptionTier != FlueraSubscriptionTier.free) return false;
    return !BrushPreset.freePresetIds.contains(preset.id);
  }

  /// Pill tap dispatcher. Routes locked taps to the upgrade prompt and
  /// blocks the underlying selection (anti-fraud — even if the visual
  /// gate is bypassed via accessibility tools, the selection won't go
  /// through). Unlocked taps go straight to the host callback.
  void _onPillTap(BrushPreset preset, bool isLocked) {
    if (isLocked) {
      widget.onUpgradePrompt?.call(
        'Sblocca il pennello "${preset.name}" con Fluera Plus o Pro.',
      );
      return;
    }
    widget.onPresetSelected(preset);
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
        children:
            _displayPresets.map((preset) {
              final isLocked = _isLockedFor(preset);
              return ToolbarBrushPill(
                preset: preset,
                isSelected: widget.selectedPresetId == preset.id,
                isPenActive: widget.isPenActive,
                isDark: widget.isDark,
                isLocked: isLocked,
                onTap: () => _onPillTap(preset, isLocked),
                onLongPress: isLocked || widget.selectedPresetId != preset.id
                    ? null
                    : widget.onLongPress,
              );
            }).toList(),
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
  /// Free-tier lock — when true, the pill renders dimmed with a 🔒
  /// badge. The owning strip routes the tap to an upgrade prompt
  /// instead of selecting the preset.
  final bool isLocked;
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
    this.isLocked = false,
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
      case ProPenType.technicalPen:
        return isDark ? const Color(0xFF78909C) : const Color(0xFF37474F);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Locked pills never show as "active" even if their id matches the
    // current selection — paying-tier downgrades shouldn't leave a
    // dangling highlight on a now-forbidden brush.
    final isHighlighted = isSelected && isPenActive && !isLocked;
    final pillBody = AnimatedContainer(
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
          Opacity(
            opacity: isLocked ? 0.4 : 1.0,
            child: Text(
              preset.icon,
              style: TextStyle(fontSize: isHighlighted ? 16 : 14),
            ),
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
    );

    // 🔒 Free-tier lock badge — anchored top-right outside the pill
    // body so it doesn't shift the selected-state width animation.
    final lockBadge = Positioned(
      right: -2,
      top: -2,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            color: isDark ? Colors.black87 : Colors.white,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.lock_rounded,
            size: 9,
            color: (isDark ? Colors.white : Colors.black87)
                .withValues(alpha: 0.7),
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: isSelected && !isLocked ? onLongPress : null,
          borderRadius: BorderRadius.circular(10),
          splashColor: _accentColor.withValues(alpha: isLocked ? 0.05 : 0.2),
          highlightColor:
              _accentColor.withValues(alpha: isLocked ? 0.03 : 0.1),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              pillBody,
              if (isLocked) lockBadge,
            ],
          ),
        ),
      ),
    );
  }
}
