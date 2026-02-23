import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../infinite_canvas_controller.dart';
import './camera_actions.dart';

/// ⚡ Zoom level indicator with coordinate display and preset zoom levels.
///
/// Displays the current zoom percentage (e.g. "100%") and canvas coordinates
/// (e.g. "X: 1240  Y: -380") in a compact glassmorphism pill.
/// Tapping opens a popup with preset zoom levels.
///
/// DESIGN PRINCIPLES:
/// - Always visible, minimal footprint.
/// - Presets: 25%, 50%, 100%, 200%, 400%.
/// - Animated text transitions when zoom changes.
/// - Coordinates update in real-time during pan/zoom.
/// - Adapts colors to canvas background for visibility on any surface.
class ZoomLevelIndicator extends StatelessWidget {
  final InfiniteCanvasController controller;
  final Size viewportSize;

  /// Canvas background color — used for adaptive styling.
  final Color canvasBackground;

  /// Called on long press — typically toggles dot grid.
  final VoidCallback? onLongPress;

  /// Whether the dot grid is currently active.
  final bool showGridActive;

  static const List<double> _presets = [0.25, 0.50, 1.0, 2.0, 4.0];

  const ZoomLevelIndicator({
    super.key,
    required this.controller,
    required this.viewportSize,
    this.canvasBackground = Colors.white,
    this.onLongPress,
    this.showGridActive = true,
  });

  bool get _isLightBg => canvasBackground.computeLuminance() > 0.5;

  String _formatZoom(double scale) {
    final pct = (scale * 100).round();
    return '$pct%';
  }

  String _formatCoord(double value) {
    if (value.abs() > 9999) {
      return '${(value / 1000).toStringAsFixed(1)}k';
    }
    return value.round().toString();
  }

  void _showPresets(BuildContext context) {
    final RenderBox box = context.findRenderObject() as RenderBox;
    final position = box.localToGlobal(Offset.zero);

    final isLight = _isLightBg;
    final menuColor =
        isLight ? const Color(0xF0F5F5FA) : const Color(0xF0222235);

    showMenu<double>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy - (_presets.length * 48.0) - 8,
        position.dx + box.size.width,
        position.dy,
      ),
      color: menuColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items:
          _presets.map((preset) {
            final label = '${(preset * 100).round()}%';
            final isActive = (controller.scale - preset).abs() < 0.01;
            final textColor =
                isActive
                    ? const Color(0xFF4A90D9)
                    : isLight
                    ? Colors.black.withValues(alpha: 0.7)
                    : Colors.white.withValues(alpha: 0.8);
            return PopupMenuItem<double>(
              value: preset,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isActive)
                    const Icon(Icons.check, size: 16, color: Color(0xFF4A90D9))
                  else
                    const SizedBox(width: 16),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
    ).then((value) {
      if (value != null) {
        CameraActions.zoomToLevel(controller, value, viewportSize);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isLight = _isLightBg;
    final pillBg = isLight ? const Color(0xCCF0F0F5) : const Color(0xCC1A1A2E);
    final pillBorder =
        isLight
            ? Colors.black.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.15);
    final primaryText =
        isLight
            ? Colors.black.withValues(alpha: 0.75)
            : Colors.white.withValues(alpha: 0.85);
    final secondaryText =
        isLight
            ? Colors.black.withValues(alpha: 0.45)
            : Colors.white.withValues(alpha: 0.45);

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        // Calculate canvas center position
        final centerScreen = Offset(
          viewportSize.width / 2,
          viewportSize.height / 2,
        );
        final canvasPos = controller.screenToCanvas(centerScreen);

        return GestureDetector(
          onTap: () => _showPresets(context),
          onLongPress: () {
            HapticFeedback.lightImpact();
            onLongPress?.call();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: pillBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: pillBorder, width: 0.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Zoom percentage
                Text(
                  _formatZoom(controller.scale),
                  style: TextStyle(
                    color: primaryText,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
                // Separator
                Container(
                  width: 1,
                  height: 12,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  color: pillBorder,
                ),
                // Coordinates
                Text(
                  '${_formatCoord(canvasPos.dx)}, ${_formatCoord(canvasPos.dy)}',
                  style: TextStyle(
                    color: secondaryText,
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                    fontFamily: 'monospace',
                  ),
                ),
                // Grid toggle indicator
                if (onLongPress != null) ...[
                  Container(
                    width: 1,
                    height: 12,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    color: pillBorder,
                  ),
                  Icon(
                    Icons.grid_4x4_rounded,
                    size: 12,
                    color:
                        showGridActive
                            ? const Color(0xFF4A90D9)
                            : secondaryText,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
