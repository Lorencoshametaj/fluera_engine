import 'package:flutter/material.dart';
import '../../l10n/fluera_localizations.dart';
import '../../core/models/shape_type.dart';

// ============================================================================
// TOOLBAR SHAPES — Shape type selector + individual shape buttons
// ============================================================================

/// Shape type selector — row of all available shapes
class ToolbarShapeTypeSelector extends StatelessWidget {
  final ShapeType selectedType;
  final ValueChanged<ShapeType> onChanged;
  final bool isDark;

  const ToolbarShapeTypeSelector({
    super.key,
    required this.selectedType,
    required this.onChanged,
    required this.isDark,
  });

  static const Map<ShapeType, IconData> shapeIcons = {
    ShapeType.freehand: Icons.gesture_rounded,
    ShapeType.line: Icons.show_chart,
    ShapeType.rectangle: Icons.crop_square,
    ShapeType.circle: Icons.circle_outlined,
    ShapeType.triangle: Icons.change_history,
    ShapeType.arrow: Icons.arrow_forward,
    ShapeType.star: Icons.star_outline,
    ShapeType.heart: Icons.favorite_border,
    ShapeType.diamond: Icons.diamond_outlined,
    ShapeType.pentagon: Icons.pentagon_outlined,
    ShapeType.hexagon: Icons.hexagon_outlined,
  };

  static String getShapeName(ShapeType type, FlueraLocalizations l10n) {
    switch (type) {
      case ShapeType.freehand:
        return l10n.proCanvas_shapeFreehand;
      case ShapeType.line:
        return l10n.proCanvas_shapeLine;
      case ShapeType.rectangle:
        return l10n.proCanvas_shapeRectangle;
      case ShapeType.circle:
        return l10n.proCanvas_shapeCircle;
      case ShapeType.triangle:
        return l10n.proCanvas_shapeTriangle;
      case ShapeType.arrow:
        return l10n.proCanvas_shapeArrow;
      case ShapeType.star:
        return l10n.proCanvas_shapeStar;
      case ShapeType.heart:
        return l10n.proCanvas_shapeHeart;
      case ShapeType.diamond:
        return l10n.proCanvas_shapeDiamond;
      case ShapeType.pentagon:
        return l10n.proCanvas_shapePentagon;
      case ShapeType.hexagon:
        return l10n.proCanvas_shapeHexagon;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = FlueraLocalizations.of(context)!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children:
          ShapeType.values.map((type) {
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ToolbarShapeTypeButton(
                icon: shapeIcons[type]!,
                label: getShapeName(type, l10n),
                isSelected: selectedType == type,
                onTap: () => onChanged(type),
                isDark: isDark,
              ),
            );
          }).toList(),
    );
  }
}

/// Individual shape type button with selection animation
class ToolbarShapeTypeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isDark;

  const ToolbarShapeTypeButton({
    super.key,
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      waitDuration: const Duration(milliseconds: 400),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color:
                  isSelected
                      ? cs.primaryContainer
                      : cs.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color:
                    isSelected
                        ? cs.primary.withValues(alpha: 0.5)
                        : cs.outlineVariant,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Icon(
              icon,
              size: 22,
              color:
                  isSelected
                      ? cs.onPrimaryContainer
                      : cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );
  }
}
