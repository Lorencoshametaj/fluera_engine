import 'package:flutter/material.dart';
import './brush_test_screen.dart';
import './brush_settings_dialog.dart';

/// 🎨 Toolbar per Test Pennelli
///
/// Controls:
/// - Selezione brush
/// - Color
/// - Brush width
/// - Opacity
/// - Settings popup for advanced parameters
class BrushTestToolbar extends StatelessWidget {
  final BrushType selectedBrush;
  final Color brushColor;
  final double brushWidth;
  final double opacity;
  final BrushSettings brushSettings;
  final Function(BrushType) onBrushChanged;
  final Function(Color) onColorChanged;
  final Function(double) onWidthChanged;
  final Function(double) onOpacityChanged;
  final Function(BrushSettings) onSettingsChanged;

  const BrushTestToolbar({
    super.key,
    required this.selectedBrush,
    required this.brushColor,
    required this.brushWidth,
    required this.opacity,
    required this.brushSettings,
    required this.onBrushChanged,
    required this.onColorChanged,
    required this.onWidthChanged,
    required this.onOpacityChanged,
    required this.onSettingsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF303030) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:  isDark ? 0.2 : 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header con titolo e pulsante settings
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Brush Type',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? const Color(0xFFBDBDBD) : Colors.black54,
                ),
              ),
              // 🎛️ Pulsante Settings
              IconButton(
                onPressed: () => _openSettingsDialog(context),
                icon: const Icon(Icons.tune),
                tooltip: 'Parametri Pennello',
                style: IconButton.styleFrom(
                  backgroundColor: isDark ? const Color(0xFF616161) : const Color(0xFFF5F5F5),
                  foregroundColor: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children:
                BrushType.values.map((brush) {
                  final isSelected = brush == selectedBrush;
                  return _buildBrushButton(
                    brush: brush,
                    isSelected: isSelected,
                    onTap: () => onBrushChanged(brush),
                    isDark: isDark,
                  );
                }).toList(),
          ),

          const SizedBox(height: 16),

          // Colori
          Text(
            'Color',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFFBDBDBD) : Colors.black54,
            ),
          ),
          const SizedBox(height: 8),
          _buildColorPicker(isDark),

          const SizedBox(height: 16),

          // Width Slider
          Row(
            children: [
              Text(
                'Width: ',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? const Color(0xFFBDBDBD) : Colors.black54,
                ),
              ),
              Text(
                '${brushWidth.toStringAsFixed(1)}px',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              Expanded(
                child: Slider(
                  value: brushWidth,
                  min: 1.0,
                  max: 20.0,
                  divisions: 38,
                  onChanged: onWidthChanged,
                ),
              ),
            ],
          ),

          // Opacity Slider
          Row(
            children: [
              Text(
                'Opacity: ',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? const Color(0xFFBDBDBD) : Colors.black54,
                ),
              ),
              Text(
                '${(opacity * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              Expanded(
                child: Slider(
                  value: opacity,
                  min: 0.1,
                  max: 1.0,
                  divisions: 9,
                  onChanged: onOpacityChanged,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBrushButton({
    required BrushType brush,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 70,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? Colors.blue
                  : (isDark ? const Color(0xFF616161) : const Color(0xFFF5F5F5)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                isSelected
                    ? Colors.blue
                    : (isDark ? const Color(0xFF757575) : const Color(0xFFE0E0E0)),
            width: 2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              brush.icon,
              color:
                  isSelected
                      ? Colors.white
                      : (isDark ? const Color(0xFFE0E0E0) : Colors.black54),
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              brush.name,
              style: TextStyle(
                fontSize: 10,
                color:
                    isSelected
                        ? Colors.white
                        : (isDark ? const Color(0xFFE0E0E0) : Colors.black54),
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorPicker(bool isDark) {
    // 🎨 In dark mode, il primo colore è bianco invece di nero!
    final colors = [
      isDark ? Colors.white : Colors.black,
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.pink,
      Colors.brown,
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children:
          colors.map((color) {
            final isSelected = color == brushColor;
            return GestureDetector(
              onTap: () => onColorChanged(color),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color:
                        isSelected
                            ? (isDark ? Colors.white : Colors.black)
                            : (isDark ? const Color(0xFF757575) : const Color(0xFFE0E0E0)),
                    width: isSelected ? 3 : 1,
                  ),
                ),
              ),
            );
          }).toList(),
    );
  }

  /// 🎛️ Apre il dialog per modificare i parametri del pennello
  void _openSettingsDialog(BuildContext context) {
    BrushSettingsDialog.show(
      context,
      settings: brushSettings,
      currentBrush: selectedBrush,
      onSettingsChanged: onSettingsChanged,
    );
  }
}
