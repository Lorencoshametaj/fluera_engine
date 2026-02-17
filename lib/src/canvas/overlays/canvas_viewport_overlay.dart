// lib/screens/professional_canvas/widgets/canvas_viewport_overlay.dart

import 'package:flutter/material.dart';

/// 🔲 Overlay showing colored rectangles for each remote user's visible area.
///
/// Similar to Figma's viewport awareness — shows where other collaborators
/// are looking on the canvas. Uses viewport data (vx, vy, vs) from cursor push.
class CanvasViewportOverlay extends StatelessWidget {
  final ValueNotifier<Map<String, Map<String, dynamic>>> cursors;
  final Offset canvasOffset;
  final double canvasScale;

  /// Local screen size — used to estimate remote viewport dimensions
  final Size screenSize;

  const CanvasViewportOverlay({
    super.key,
    required this.cursors,
    required this.canvasOffset,
    required this.canvasScale,
    required this.screenSize,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, Map<String, dynamic>>>(
      valueListenable: cursors,
      builder: (context, cursorMap, _) {
        if (cursorMap.isEmpty) return const SizedBox.shrink();

        return Stack(
          clipBehavior: Clip.none,
          children:
              cursorMap.entries
                  .where(
                    (e) =>
                        e.value['vx'] != null &&
                        e.value['vy'] != null &&
                        e.value['vs'] != null,
                  )
                  .map((entry) {
                    final data = entry.value;
                    final remoteOffsetX = (data['vx'] as num).toDouble();
                    final remoteOffsetY = (data['vy'] as num).toDouble();
                    final remoteScale = (data['vs'] as num).toDouble();
                    final name = data['displayName'] as String? ?? 'User';
                    final colorValue =
                        data['cursorColor'] as int? ?? 0xFF42A5F5;
                    final color = Color(colorValue);

                    if (remoteScale <= 0) return const SizedBox.shrink();

                    // Remote user's viewport in canvas coordinates:
                    // Canvas point = (screenPoint - offset) / scale
                    // Remote viewport top-left in canvas coords:
                    final remoteCanvasTopLeftX = -remoteOffsetX / remoteScale;
                    final remoteCanvasTopLeftY = -remoteOffsetY / remoteScale;
                    // Remote viewport size in canvas coords (estimate using local screen size):
                    final remoteCanvasWidth = screenSize.width / remoteScale;
                    final remoteCanvasHeight = screenSize.height / remoteScale;

                    // Convert remote canvas coords to OUR screen coords:
                    // screenX = canvasX * ourScale + ourOffset
                    final screenLeft =
                        remoteCanvasTopLeftX * canvasScale + canvasOffset.dx;
                    final screenTop =
                        remoteCanvasTopLeftY * canvasScale + canvasOffset.dy;
                    final screenWidth = remoteCanvasWidth * canvasScale;
                    final screenHeight = remoteCanvasHeight * canvasScale;

                    return Positioned(
                      left: screenLeft,
                      top: screenTop,
                      width: screenWidth,
                      height: screenHeight,
                      child: IgnorePointer(
                        child: _ViewportRect(color: color, userName: name),
                      ),
                    );
                  })
                  .toList(),
        );
      },
    );
  }
}

/// 🔲 A single user's viewport rectangle with name label
class _ViewportRect extends StatelessWidget {
  final Color color;
  final String userName;

  const _ViewportRect({required this.color, required this.userName});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Colored border rectangle
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: color.withValues(alpha: 0.5), width: 2),
              color: color.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        // Name label at top-left corner
        Positioned(
          left: 0,
          top: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.8),
              borderRadius: const BorderRadius.only(
                bottomRight: Radius.circular(6),
              ),
            ),
            child: Text(
              userName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
