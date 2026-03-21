import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../infinite_canvas_controller.dart';
import './camera_actions.dart';

/// ⚡ Zoom level indicator — Minimal JARVIS HUD style.
///
/// Dark-glass pill with subtle cyan accent:
/// - Dark glass base, thin cyan border
/// - Monospace text for zoom %, coordinates, rotation
/// - Tap → zoom presets popup
/// - Long-press → toggle dot grid
/// - Tap rotation → reset rotation to 0°
class ZoomLevelIndicator extends StatelessWidget {
  final InfiniteCanvasController controller;
  final Size viewportSize;

  /// Canvas background color (kept for API compat).
  final Color canvasBackground;

  /// Called on long press — typically toggles dot grid.
  final VoidCallback? onLongPress;

  /// Whether the dot grid is currently active.
  final bool showGridActive;

  /// Called to toggle minimap visibility.
  final VoidCallback? onToggleMinimap;

  /// Whether the minimap is currently visible.
  final bool isMinimapVisible;

  static const List<double> _presets = [0.25, 0.50, 1.0, 2.0, 4.0];

  // ── HUD palette ──
  static const _glassBase = Color(0xBB0A0E1A);
  static const _neonCyan = Color(0xFF82C8FF);
  static const _primaryText = Color(0xFFB0D4FF);
  static const _secondaryText = Color(0xFF5A8CB8);

  const ZoomLevelIndicator({
    super.key,
    required this.controller,
    required this.viewportSize,
    this.canvasBackground = Colors.white,
    this.onLongPress,
    this.showGridActive = true,
    this.onToggleMinimap,
    this.isMinimapVisible = true,
  });

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

    showMenu<double>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy - (_presets.length * 48.0) - 8,
        position.dx + box.size.width,
        position.dy,
      ),
      color: const Color(0xF00A0E1A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _neonCyan.withValues(alpha: 0.2),
          width: 0.5,
        ),
      ),
      items: _presets.map((preset) {
        final label = '${(preset * 100).round()}%';
        final isActive = (controller.scale - preset).abs() < 0.01;
        final textColor =
            isActive ? _neonCyan : _primaryText.withValues(alpha: 0.8);
        return PopupMenuItem<double>(
          value: preset,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isActive)
                const Icon(Icons.check, size: 16, color: _neonCyan)
              else
                const SizedBox(width: 16),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  fontSize: 13,
                  fontFamily: 'monospace',
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
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final centerScreen = Offset(
          viewportSize.width / 2,
          viewportSize.height / 2,
        );
        final canvasPos = controller.screenToCanvas(centerScreen);
        final zoomText = _formatZoom(controller.scale);
        final coordText =
            '${_formatCoord(canvasPos.dx)}, ${_formatCoord(canvasPos.dy)}';
        final isRotated = controller.rotation.abs() > 0.009; // ~0.5° threshold
        final isSnapped = isRotated &&
            controller.checkSnapAngle(controller.rotation) != null;

        // Responsive: hide elements on narrow screens
        final w = viewportSize.width;
        final showCoords = w > 500;
        final showIcons = w > 380;
        // Leave room for minimap (180 + 16 right pad + 16 gap)
        final maxW = (w - 228).clamp(100.0, 500.0);

        // Build the Row children list
        final children = <Widget>[
          // ── Zoom % ──
          Text(
            zoomText,
            style: const TextStyle(
              color: _primaryText,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
              letterSpacing: 0.3,
            ),
          ),
          // ── Coordinates (hidden on narrow screens) ──
          if (showCoords) ...[
            _separator(0.15),
            Text(
              coordText,
              style: const TextStyle(
                color: _secondaryText,
                fontSize: 10,
                fontWeight: FontWeight.w500,
                fontFamily: 'monospace',
                letterSpacing: 0.3,
              ),
            ),
          ],
          // ── Grid indicator (hidden on very narrow) ──
          if (showIcons && onLongPress != null) ...[
            _separator(0.12),
            Icon(
              Icons.grid_4x4_rounded,
              size: 11,
              color: showGridActive
                  ? _neonCyan.withValues(alpha: 0.7)
                  : _secondaryText.withValues(alpha: 0.4),
            ),
          ],
          // ── Minimap toggle (hidden on very narrow) ──
          if (showIcons && onToggleMinimap != null) ...[
            _separator(0.12),
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onToggleMinimap!.call();
              },
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Icon(
                  isMinimapVisible
                      ? Icons.map_rounded
                      : Icons.map_outlined,
                  size: 12,
                  color: isMinimapVisible
                      ? _neonCyan.withValues(alpha: 0.7)
                      : _secondaryText.withValues(alpha: 0.4),
                ),
              ),
            ),
          ],
          // ── Rotation indicator (only when rotated) ──
          if (isRotated) ...[
            _separator(0.15),
            GestureDetector(
              onTap: () {
                HapticFeedback.mediumImpact();
                controller.resetRotation();
              },
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.rotate(
                    angle: controller.rotation,
                    child: Icon(
                      isSnapped
                          ? Icons.check_circle_rounded
                          : Icons.navigation_rounded,
                      size: 10,
                      color: isSnapped
                          ? _neonCyan
                          : _primaryText.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    controller.rotationDegrees,
                    style: TextStyle(
                      color: isSnapped ? _neonCyan : _primaryText,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ];

        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: GestureDetector(
            onTap: () => _showPresets(context),
            onLongPress: () {
              HapticFeedback.lightImpact();
              onLongPress?.call();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: _glassBase,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _neonCyan.withValues(alpha: 0.2),
                  width: 0.5,
                ),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: children,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Thin gradient separator line.
  static Widget _separator(double alpha) {
    return Container(
      width: 1,
      height: 12,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _neonCyan.withValues(alpha: 0.0),
            _neonCyan.withValues(alpha: alpha),
            _neonCyan.withValues(alpha: 0.0),
          ],
        ),
      ),
    );
  }
}
