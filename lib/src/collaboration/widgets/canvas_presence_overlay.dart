// lib/screens/professional_canvas/widgets/canvas_presence_overlay.dart

import 'package:flutter/material.dart';

/// 🔵 Overlay to show remote cursors with tool info, typing and follow mode
///
/// Receives a ValueNotifier of Map (userId → cursorData) from RTDB.
/// Each cursorData contains: x, y, isDrawing, displayName, cursorColor,
/// penType, penColor, isTyping, vx, vy, vs (viewport for follow mode),
/// and `s`/`selection` (List<String> of node ids the peer has selected).
class CanvasPresenceOverlay extends StatelessWidget {
  final ValueNotifier<Map<String, Map<String, dynamic>>> cursors;
  final Offset canvasOffset;
  final double canvasScale;
  final String? followingUserId;
  final void Function(String userId)? onFollowUser;

  /// Optional lookup that turns a CRDT node id into its bounding rect in
  /// canvas coordinates. When provided, the overlay paints a dashed
  /// rectangle (in the peer's cursor color) around every node the peer
  /// currently has selected — the standard "selection awareness" UX in
  /// collaborative tools (Figma / Notion). Returning `null` for an id
  /// silently skips that one (element since deleted, not yet replicated,
  /// etc.).
  final Rect? Function(String nodeId)? nodeBoundsLookup;

  const CanvasPresenceOverlay({
    super.key,
    required this.cursors,
    required this.canvasOffset,
    required this.canvasScale,
    this.followingUserId,
    this.onFollowUser,
    this.nodeBoundsLookup,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, Map<String, dynamic>>>(
      valueListenable: cursors,
      builder: (context, cursorMap, _) {
        if (cursorMap.isEmpty) return const SizedBox.shrink();

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Selection rects sit BEHIND the cursor markers so the tip
            // remains tappable when the rect overlaps the cursor.
            if (nodeBoundsLookup != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _RemoteSelectionsPainter(
                      cursorMap: cursorMap,
                      canvasOffset: canvasOffset,
                      canvasScale: canvasScale,
                      lookup: nodeBoundsLookup!,
                    ),
                  ),
                ),
              ),
            ...cursorMap.entries.map((entry) {
                final data = entry.value;
                final x = (data['x'] as num?)?.toDouble() ?? 0;
                final y = (data['y'] as num?)?.toDouble() ?? 0;
                // 🚀 COST OPT: Read compact keys with legacy fallback
                final isDrawing =
                    (data['d'] ?? data['isDrawing']) as bool? ?? false;
                final isTyping =
                    (data['t'] ?? data['isTyping']) as bool? ?? false;
                final isRecording =
                    (data['r'] ?? data['isRecording']) as bool? ?? false;
                final isListening =
                    (data['l'] ?? data['isListening']) as bool? ?? false;
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
                        isRecording: isRecording,
                        isListening: isListening,
                        displayName: name,
                        penType: penType,
                        penColor:
                            penColorValue != null ? Color(penColorValue) : null,
                        isFollowing: isFollowing,
                      ),
                    ),
                  ),
                );
              }),
          ],
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
  final bool isRecording;
  final bool isListening;
  final String displayName;
  final String? penType;
  final Color? penColor;
  final bool isFollowing;

  const _RemoteTouchIndicator({
    required this.color,
    required this.isDrawing,
    required this.isTyping,
    this.isRecording = false,
    this.isListening = false,
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

    if (widget.isDrawing ||
        widget.isTyping ||
        widget.isRecording ||
        widget.isListening) {
      _pulseController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _RemoteTouchIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    final shouldPulse =
        widget.isDrawing ||
        widget.isTyping ||
        widget.isRecording ||
        widget.isListening;
    final wasPulsing =
        oldWidget.isDrawing ||
        oldWidget.isTyping ||
        oldWidget.isRecording ||
        oldWidget.isListening;
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
    if (widget.isListening) return Icons.headphones;
    if (widget.isRecording) return Icons.mic;
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
    final isActive =
        widget.isDrawing ||
        widget.isTyping ||
        widget.isRecording ||
        widget.isListening;
    final dotColor =
        widget.isDrawing && widget.penColor != null
            ? widget.penColor!
            : widget.isRecording
            ? Colors.red
            : widget.isListening
            ? Colors.green
            : color;

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
                widget.isListening
                    ? '${widget.displayName} 🎧'
                    : widget.isRecording
                    ? '${widget.displayName} 🎤'
                    : widget.isTyping
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

/// Paints a dashed rectangle around every node currently selected by a
/// remote peer, in the peer's cursor color.
///
/// Selection ids travel inside the cursor payload (compact key `s`). The
/// painter resolves them to canvas-coordinate bounds via [lookup] and
/// projects each into screen space using the same camera transform as
/// the cursor markers — so the boxes stay locked to the selected
/// elements during pan & zoom.
class _RemoteSelectionsPainter extends CustomPainter {
  final Map<String, Map<String, dynamic>> cursorMap;
  final Offset canvasOffset;
  final double canvasScale;
  final Rect? Function(String nodeId) lookup;

  const _RemoteSelectionsPainter({
    required this.cursorMap,
    required this.canvasOffset,
    required this.canvasScale,
    required this.lookup,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final entry in cursorMap.entries) {
      final data = entry.value;
      final selectionRaw = data['s'] ?? data['selection'];
      if (selectionRaw is! List || selectionRaw.isEmpty) continue;

      final colorValue =
          (data['c'] ?? data['cursorColor']) as int? ?? 0xFF42A5F5;
      final paint = Paint()
        ..color = Color(colorValue)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6;

      for (final raw in selectionRaw) {
        final id = raw is String ? raw : raw?.toString();
        if (id == null || id.isEmpty) continue;
        final bounds = lookup(id);
        if (bounds == null) continue;

        final rect = Rect.fromLTRB(
          bounds.left * canvasScale + canvasOffset.dx,
          bounds.top * canvasScale + canvasOffset.dy,
          bounds.right * canvasScale + canvasOffset.dx,
          bounds.bottom * canvasScale + canvasOffset.dy,
        ).inflate(2);

        _drawDashedRect(canvas, rect, paint);
      }
    }
  }

  /// Draw a rounded dashed rectangle. Dash length scales mildly with the
  /// camera scale so we don't get a solid line at extreme zoom-in.
  void _drawDashedRect(Canvas canvas, Rect rect, Paint paint) {
    const dash = 5.0;
    const gap = 4.0;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)));
    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(
          metric.extractPath(distance, next),
          paint,
        );
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RemoteSelectionsPainter old) {
    return old.cursorMap != cursorMap ||
        old.canvasOffset != canvasOffset ||
        old.canvasScale != canvasScale ||
        old.lookup != lookup;
  }
}
