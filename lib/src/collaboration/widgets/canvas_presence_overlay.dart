// lib/screens/professional_canvas/widgets/canvas_presence_overlay.dart

import 'package:flutter/material.dart';

/// 🔵 Overlay to show remote cursors with tool info, typing and follow mode
///
/// Receives a ValueNotifier of Map (userId → cursorData) from RTDB.
/// Each cursorData contains: x, y, isDrawing, displayName, cursorColor,
/// penType, penColor, isTyping, vx, vy, vs (viewport for follow mode).
class CanvasPresenceOverlay extends StatelessWidget {
  final ValueNotifier<Map<String, Map<String, dynamic>>> cursors;
  final Offset canvasOffset;
  final double canvasScale;
  final String? followingUserId;
  final void Function(String userId)? onFollowUser;

  const CanvasPresenceOverlay({
    super.key,
    required this.cursors,
    required this.canvasOffset,
    required this.canvasScale,
    this.followingUserId,
    this.onFollowUser,
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
              cursorMap.entries.map((entry) {
                final data = entry.value;
                final x = (data['x'] as num?)?.toDouble() ?? 0;
                final y = (data['y'] as num?)?.toDouble() ?? 0;
                // 🚀 COST OPT: Read compact keys with legacy fallback
                final isDrawing =
                    (data['d'] ?? data['isDrawing']) as bool? ?? false;
                final isTyping =
                    (data['t'] ?? data['isTyping']) as bool? ?? false;
                final name =
                    (data['n'] ?? data['displayName']) as String? ?? 'User';
                final colorValue =
                    (data['c'] ?? data['cursorColor']) as int? ?? 0xFF42A5F5;
                final color = Color(colorValue);
                final penType = (data['pt'] ?? data['penType']) as String?;
                final penColorValue = (data['pc'] ?? data['penColor']) as int?;
                final isFollowing = followingUserId == entry.key;

                final screenX = x * canvasScale + canvasOffset.dx;
                final screenY = y * canvasScale + canvasOffset.dy;

                return AnimatedPositioned(
                  key: ValueKey('touch_${entry.key}'),
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOutCubic,
                  left: screenX - 24,
                  top: screenY - 24,
                  child: IgnorePointer(
                    ignoring: onFollowUser == null,
                    child: GestureDetector(
                      onTap:
                          onFollowUser != null
                              ? () => onFollowUser!(entry.key)
                              : null,
                      child: _RemoteTouchIndicator(
                        color: color,
                        isDrawing: isDrawing,
                        isTyping: isTyping,
                        displayName: name,
                        penType: penType,
                        penColor:
                            penColorValue != null ? Color(penColorValue) : null,
                        isFollowing: isFollowing,
                      ),
                    ),
                  ),
                );
              }).toList(),
        );
      },
    );
  }
}

/// 🎯 Remote touch indicator with 3 states:
///
/// - **Idle**: static colored dot + name
/// - **Drawing**: cerchio pulsante + tool icon (pen type + color)
/// - **Typing**: icona tastiera + "typing..."
class _RemoteTouchIndicator extends StatefulWidget {
  final Color color;
  final bool isDrawing;
  final bool isTyping;
  final String displayName;
  final String? penType;
  final Color? penColor;
  final bool isFollowing;

  const _RemoteTouchIndicator({
    required this.color,
    required this.isDrawing,
    required this.isTyping,
    required this.displayName,
    this.penType,
    this.penColor,
    this.isFollowing = false,
  });

  @override
  State<_RemoteTouchIndicator> createState() => _RemoteTouchIndicatorState();
}

class _RemoteTouchIndicatorState extends State<_RemoteTouchIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseScale;
  late final Animation<double> _pulseOpacity;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _pulseScale = Tween<double>(
      begin: 0.6,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeOut));

    _pulseOpacity = Tween<double>(
      begin: 0.6,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeOut));

    if (widget.isDrawing || widget.isTyping) {
      _pulseController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _RemoteTouchIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    final shouldPulse = widget.isDrawing || widget.isTyping;
    final wasPulsing = oldWidget.isDrawing || oldWidget.isTyping;
    if (shouldPulse != wasPulsing) {
      if (shouldPulse) {
        _pulseController.repeat();
      } else {
        _pulseController.stop();
        _pulseController.reset();
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  /// Get tool icon based on pen type
  IconData _getToolIcon() {
    if (widget.isTyping) return Icons.keyboard;
    switch (widget.penType) {
      case 'pencil':
        return Icons.edit;
      case 'fountainPen':
        return Icons.brush;
      case 'marker':
        return Icons.format_paint;
      case 'highlighter':
        return Icons.highlight;
      case 'calligraphy':
        return Icons.gesture;
      case 'eraser':
        return Icons.auto_fix_high;
      default:
        return Icons.edit;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    final isActive = widget.isDrawing || widget.isTyping;
    final dotColor =
        widget.isDrawing && widget.penColor != null ? widget.penColor! : color;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Touch point area
        SizedBox(
          width: 48,
          height: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Pulsing ring — when drawing or typing
              if (isActive)
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _pulseScale.value,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: color.withValues(alpha: _pulseOpacity.value),
                            width: 2.5,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              // Center touch dot — colored with pen color when drawing
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: isActive ? 16 : 12,
                height: isActive ? 16 : 12,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white,
                    width: isActive ? 2.5 : 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: dotColor.withValues(alpha: isActive ? 0.5 : 0.3),
                      blurRadius: isActive ? 10 : 6,
                      spreadRadius: isActive ? 2 : 1,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Name + activity label
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(8),
            border:
                widget.isFollowing
                    ? Border.all(color: Colors.white, width: 1.5)
                    : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isActive) ...[
                Icon(_getToolIcon(), color: Colors.white, size: 10),
                const SizedBox(width: 3),
              ],
              if (widget.isFollowing) ...[
                const Icon(Icons.visibility, color: Colors.white, size: 10),
                const SizedBox(width: 3),
              ],
              Text(
                widget.isTyping
                    ? '${widget.displayName} ✍️'
                    : widget.displayName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
