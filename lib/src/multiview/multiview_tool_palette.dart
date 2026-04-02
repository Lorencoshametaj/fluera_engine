import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../tools/unified_tool_controller.dart';
import '../drawing/models/pro_drawing_point.dart';

// =============================================================================
// MULTIVIEW TOOL PALETTE — Compact bottom toolbar for tool/color/width control
// =============================================================================

/// A compact, floating tool palette for the multiview system.
///
/// Provides quick access to:
/// - Tool switching (pen, eraser, pan)
/// - Color selection (6 presets + custom)
/// - Stroke width adjustment (slider)
/// - Brush type quick-switch
class MultiviewToolPalette extends StatelessWidget {
  final UnifiedToolController toolController;

  // OPT #3: Cache shadow & radius to avoid per-build allocation
  static const _shadow = [
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 12,
      offset: Offset(0, -2),
    ),
  ];
  static const _borderRadius = BorderRadius.all(Radius.circular(16));

  const MultiviewToolPalette({super.key, required this.toolController});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: toolController,
      builder: (context, _) => _buildPalette(context),
    );
  }

  Widget _buildPalette(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 60,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color:
            isDark
                ? cs.surfaceContainerHighest.withValues(alpha: 0.95)
                : cs.surfaceContainerLow.withValues(alpha: 0.95),
        borderRadius: _borderRadius,
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.3),
          width: 0.5,
        ),
        boxShadow: _shadow,
      ),
      child: Row(
        children: [
          // ── Tool Selector ─────────────────────────────────────────────
          _ToolButton(
            icon: Icons.edit_rounded,
            tooltip: 'Pen',
            isActive: toolController.isDrawingMode,
            onTap: () {
              HapticFeedback.selectionClick();
              toolController.selectTool(null);
            },
          ),
          _ToolButton(
            icon: Icons.auto_fix_high_rounded,
            tooltip: 'Eraser',
            isActive: toolController.isEraserMode,
            onTap: () {
              HapticFeedback.selectionClick();
              toolController.toggleEraser();
            },
          ),
          _ToolButton(
            icon: Icons.pan_tool_rounded,
            tooltip: 'Pan',
            isActive: toolController.isPanMode,
            onTap: () {
              HapticFeedback.selectionClick();
              toolController.togglePanMode();
            },
          ),

          // Divider
          _PaletteDivider(),

          // ── Color Presets ─────────────────────────────────────────────
          ..._buildColorPresets(cs),

          // Divider
          _PaletteDivider(),

          // ── Width Control ─────────────────────────────────────────────
          Expanded(child: _buildWidthSlider(cs)),

          // ── Brush Type ────────────────────────────────────────────────
          _buildBrushDropdown(cs),
        ],
      ),
    );
  }

  List<Widget> _buildColorPresets(ColorScheme cs) {
    const presets = [
      Colors.black,
      Color(0xFF1565C0), // Blue
      Color(0xFFC62828), // Red
      Color(0xFF2E7D32), // Green
      Color(0xFFFF8F00), // Amber
      Color(0xFF6A1B9A), // Purple
    ];

    return presets.map((color) {
      final isSelected = toolController.color.toARGB32() == color.toARGB32();
      return GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          toolController.setColor(color);
        },
        child: Container(
          width: 28,
          height: 28,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color:
                  isSelected
                      ? cs.primary
                      : cs.outlineVariant.withValues(alpha: 0.3),
              width: isSelected ? 2.5 : 1.0,
            ),
            boxShadow:
                isSelected
                    ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.4),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                    ]
                    : null,
          ),
        ),
      );
    }).toList();
  }

  Widget _buildWidthSlider(ColorScheme cs) {
    return Row(
      children: [
        // Width preview dot
        Container(
          width: (toolController.width * 0.6).clamp(4.0, 18.0),
          height: (toolController.width * 0.6).clamp(4.0, 18.0),
          decoration: BoxDecoration(
            color: toolController.color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: cs.primary,
              inactiveTrackColor: cs.outlineVariant.withValues(alpha: 0.3),
              thumbColor: cs.primary,
            ),
            child: Slider(
              value: toolController.width,
              min: 1.0,
              max: 30.0,
              onChanged: (v) => toolController.setWidth(v),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBrushDropdown(ColorScheme cs) {
    final currentType = toolController.penType;
    return PopupMenuButton<ProPenType>(
      tooltip: 'Brush type',
      onSelected: (type) {
        HapticFeedback.selectionClick();
        toolController.setPenType(type);
      },
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      offset: const Offset(0, -120),
      itemBuilder:
          (context) => [
            _brushMenuItem(
              ProPenType.ballpoint,
              'Ballpoint',
              Icons.edit_rounded,
              cs,
            ),
            _brushMenuItem(ProPenType.pencil, 'Pencil', Icons.draw_rounded, cs),
            _brushMenuItem(
              ProPenType.marker,
              'Marker',
              Icons.format_paint_rounded,
              cs,
            ),
            _brushMenuItem(
              ProPenType.fountain,
              'Fountain',
              Icons.water_drop_rounded,
              cs,
            ),
          ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Icon(
          _brushIcon(currentType),
          size: 16,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }

  PopupMenuItem<ProPenType> _brushMenuItem(
    ProPenType type,
    String label,
    IconData icon,
    ColorScheme cs,
  ) {
    final isSelected = toolController.penType == type;
    return PopupMenuItem(
      value: type,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: isSelected ? cs.primary : cs.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              color: isSelected ? cs.primary : cs.onSurface,
            ),
          ),
          if (isSelected) ...[
            const SizedBox(width: 8),
            Icon(Icons.check_rounded, size: 14, color: cs.primary),
          ],
        ],
      ),
    );
  }

  IconData _brushIcon(ProPenType type) {
    switch (type) {
      case ProPenType.ballpoint:
        return Icons.edit_rounded;
      case ProPenType.pencil:
        return Icons.draw_rounded;
      case ProPenType.marker:
        return Icons.format_paint_rounded;
      case ProPenType.fountain:
        return Icons.water_drop_rounded;
      default:
        return Icons.edit_rounded;
    }
  }
}

// =============================================================================
// TOOLBAR PRIMITIVES
// =============================================================================

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isActive;
  final VoidCallback onTap;

  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Tooltip(
      message: tooltip,
      child: Material(
        color:
            isActive
                ? cs.primaryContainer.withValues(alpha: 0.6)
                : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(
              icon,
              size: 18,
              color: isActive ? cs.primary : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _PaletteDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: cs.outlineVariant.withValues(alpha: 0.3),
    );
  }
}
