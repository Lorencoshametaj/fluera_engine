import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../infinite_canvas_controller.dart';
import './content_bounds_tracker.dart';
import './camera_actions.dart';
import '../../rendering/optimization/viewport_culler.dart';
import '../../layers/layer_controller.dart';

/// ↩ "Return to content" FAB — appears when the user has panned far away
/// from all canvas content, providing a one-tap way to get back.
///
/// DESIGN PRINCIPLES:
/// - Invisible when content is visible in the viewport.
/// - Fades in with a spring animation when the viewport doesn't intersect
///   any content bounds.
/// - Tapping triggers [CameraActions.fitAllContent] with padding.
/// - Swipe down to dismiss (user wants to stay where they are).
/// - Adaptive styling based on canvas background color.
///
/// PERFORMANCE:
/// - Only checks viewport vs. content bounds (O(1) rect intersection).
/// - Uses [AnimatedOpacity] for smooth transitions.
class ReturnToContentFab extends StatefulWidget {
  final InfiniteCanvasController controller;
  final ContentBoundsTracker boundsTracker;
  final LayerController layerController;
  final Size viewportSize;

  /// Canvas background color — used for adaptive styling.
  final Color canvasBackground;

  const ReturnToContentFab({
    super.key,
    required this.controller,
    required this.boundsTracker,
    required this.layerController,
    required this.viewportSize,
    this.canvasBackground = Colors.white,
  });

  @override
  State<ReturnToContentFab> createState() => _ReturnToContentFabState();
}

class _ReturnToContentFabState extends State<ReturnToContentFab> {
  /// When user dismisses, we suppress the FAB until they navigate again.
  bool _dismissed = false;
  Offset _lastOffset = Offset.zero;

  @override
  void initState() {
    super.initState();
    _lastOffset = widget.controller.offset;
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!_dismissed) return;
    // If user pans significantly after dismiss, re-enable the FAB
    final delta = (widget.controller.offset - _lastOffset).distance;
    if (delta > 100) {
      setState(() {
        _dismissed = false;
        _lastOffset = widget.controller.offset;
      });
    }
  }

  /// Check if the viewport overlaps content bounds at all.
  bool _isLostFromContent(Rect contentBounds) {
    if (contentBounds.isEmpty) return false;

    final viewport = ViewportCuller.calculateViewport(
      widget.viewportSize,
      widget.controller.offset,
      widget.controller.scale,
      rotation: widget.controller.rotation,
    );

    // Inflate content bounds slightly so the FAB disappears before
    // you're right at the edge.
    final expandedContent = contentBounds.inflate(
      contentBounds.longestSide * 0.15,
    );

    return !viewport.overlaps(expandedContent);
  }

  bool get _isLightBg => widget.canvasBackground.computeLuminance() > 0.5;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return ValueListenableBuilder<Rect>(
          valueListenable: widget.boundsTracker.bounds,
          builder: (context, contentBounds, _) {
            final isLost = _isLostFromContent(contentBounds) && !_dismissed;

            // When content becomes visible again, reset dismiss state
            if (!_isLostFromContent(contentBounds) && _dismissed) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _dismissed = false);
              });
            }

            return AnimatedOpacity(
              opacity: isLost ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              child: AnimatedScale(
                scale: isLost ? 1.0 : 0.8,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                child: IgnorePointer(
                  ignoring: !isLost,
                  child: _buildSwipeableFab(context),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSwipeableFab(BuildContext context) {
    return GestureDetector(
      onVerticalDragEnd: (details) {
        // Swipe down to dismiss
        if (details.velocity.pixelsPerSecond.dy > 100) {
          HapticFeedback.lightImpact();
          setState(() {
            _dismissed = true;
            _lastOffset = widget.controller.offset;
          });
        }
      },
      child: _buildFab(context),
    );
  }

  Widget _buildFab(BuildContext context) {
    final isLight = _isLightBg;
    final bgColor =
        isLight
            ? const Color(0xFF3B82F6) // Blue on light
            : const Color(0xFF38BDF8); // Sky blue on dark
    final textColor = Colors.white;
    final shadowColor = bgColor.withValues(alpha: 0.3);

    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        CameraActions.fitAllContent(
          widget.controller,
          widget.layerController.sceneGraph,
          widget.viewportSize,
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: shadowColor,
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.my_location_rounded, size: 18, color: textColor),
                const SizedBox(width: 8),
                Text(
                  'Torna al contenuto',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Swipe hint
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 14,
            color: (isLight ? Colors.black : Colors.white).withValues(
              alpha: 0.25,
            ),
          ),
        ],
      ),
    );
  }
}
