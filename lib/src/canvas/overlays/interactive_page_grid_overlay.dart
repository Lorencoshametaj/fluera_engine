import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/multi_page_config.dart';
import '../../export/export_preset.dart'; // For ExportPageFormatUtils extension

part 'page_grid_drag_handlers.dart';
part 'page_grid_snap.dart';

/// 📐 INTERACTIVE PAGE GRID OVERLAY
///
/// Widget overlay for interactive editing of multi-page pages.
/// Supports two modes:
/// - Uniform: all pages share the same size
/// - Individual: each page can be independently resized
class InteractivePageGridOverlay extends StatefulWidget {
  /// Multi-page configuration
  final MultiPageConfig config;

  /// Callback when the configuration changes
  final ValueChanged<MultiPageConfig> onConfigChanged;

  /// Canvas scale
  final double canvasScale;

  /// Canvas offset
  final Offset canvasOffset;

  /// If true, show resize handles only for the selected page
  final bool showHandlesOnlySelected;

  /// Callback to request canvas scrolling (auto-pan)
  /// The parameter is the pan delta in screen coordinates
  final ValueChanged<Offset>? onPanCanvas;

  /// Callback for forwarding pinch-zoom from the overlay to the canvas.
  /// Parameters: (local focalPoint, per-frame scale ratio)
  final void Function(Offset focalPoint, double frameRatio)? onScaleCanvas;

  /// Bottom padding to exclude toolbar from the interactive area
  final double bottomPadding;

  /// If true, shows the dark overlay. If false, shows only pages.
  final bool showDarkOverlay;

  const InteractivePageGridOverlay({
    super.key,
    required this.config,
    required this.onConfigChanged,
    required this.canvasScale,
    required this.canvasOffset,
    this.showHandlesOnlySelected = true,
    this.onPanCanvas,
    this.onScaleCanvas,
    this.bottomPadding = 0,
    this.showDarkOverlay = true,
  });

  @override
  State<InteractivePageGridOverlay> createState() =>
      _InteractivePageGridOverlayState();
}

class _InteractivePageGridOverlayState
    extends State<InteractivePageGridOverlay> {
  // Handle constants
  static const double _handleSize = 24.0;
  static const double _handleHitArea = 44.0;
  static const double _minPageSize = 50.0;

  // Auto-pan constants
  static const double _autoPanEdgeZone = 60.0;
  static const double _autoPanSpeed = 5.0;
  static const Duration _autoPanInterval = Duration(milliseconds: 16); // ~60fps

  // Snap/Magnetism constants
  static const double _snapThreshold = 15.0;
  static const double _snapGap = 10.0;

  // Auto-pan state
  Timer? _autoPanTimer;
  Offset _lastDragPosition = Offset.zero;
  Size _viewportSize = Size.zero;

  // Drag state
  String? _activeHandle;
  int? _draggingPageIndex;
  Offset? _dragStartPosition;
  Rect? _initialPageBounds;
  bool _isDraggingPage = false;

  // Snap state - visible guide lines during drag
  List<_SnapLine> _activeSnapLines = [];

  // Multi-touch state (to allow pinch zoom)
  int _pointerCount = 0;

  // Scale gesture state for dark overlay zoom
  double _scaleStartScale = 1.0;
  double _lastForwardedScale = 1.0;
  Offset _scaleStartFocalPoint = Offset.zero;

  @override
  void dispose() {
    stopAutoPan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      // Track pointer count to allow pinch zoom
      onPointerDown: (_) {
        final newCount = _pointerCount + 1;
        setState(() => _pointerCount = newCount);
        // Cancel active page drag when second finger arrives (enable pinch zoom)
        if (newCount >= 2 && (_isDraggingPage || _activeHandle != null)) {
          stopAutoPan();
          _isDraggingPage = false;
          _draggingPageIndex = null;
          _dragStartPosition = null;
          _initialPageBounds = null;
          _activeHandle = null;
          setState(() => _activeSnapLines = []);
        }
      },
      onPointerUp: (_) {
        setState(() => _pointerCount = (_pointerCount - 1).clamp(0, 10));
      },
      onPointerCancel: (_) {
        setState(() => _pointerCount = (_pointerCount - 1).clamp(0, 10));
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Save viewport size for auto-pan
          _viewportSize = Size(constraints.maxWidth, constraints.maxHeight);

          // If there are 2+ touches, ignore gestures to allow pinch zoom
          final content = Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              // Dark overlay (optional) - tap to deselect, scale to zoom
              if (widget.showDarkOverlay)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _deselectPage,
                    onScaleStart: (details) {
                      _scaleStartScale = widget.canvasScale;
                      _lastForwardedScale = 1.0;
                      _scaleStartFocalPoint = details.localFocalPoint;
                    },
                    onScaleUpdate: (details) {
                      if (details.pointerCount >= 2 && widget.onScaleCanvas != null) {
                        // Per-frame scale ratio
                        final frameRatio = details.scale / _lastForwardedScale;
                        _lastForwardedScale = details.scale;
                        // Use localFocalPoint so coordinates match canvas controller
                        widget.onScaleCanvas!(
                          details.localFocalPoint,
                          frameRatio,
                        );
                      }
                    },
                    onScaleEnd: (_) {
                      _lastForwardedScale = 1.0;
                    },
                    child: CustomPaint(
                      painter: _DarkOverlayPainter(
                        pageBounds: widget.config.individualPageBounds,
                        canvasScale: widget.canvasScale,
                        canvasOffset: widget.canvasOffset,
                      ),
                    ),
                  ),
                ),

              // Snap guide lines (shown during drag)
              if (_activeSnapLines.isNotEmpty)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _SnapLinesPainter(
                      snapLines: _activeSnapLines,
                      canvasScale: widget.canvasScale,
                      canvasOffset: widget.canvasOffset,
                    ),
                  ),
                ),

              // Page boxes with handles (clipped)
              ...widget.config.individualPageBounds.asMap().entries.map((
                entry,
              ) {
                final index = entry.key;
                final bounds = entry.value;
                final isSelected = index == widget.config.selectedPageIndex;

                return _buildPageBox(
                  index: index,
                  bounds: bounds,
                  isSelected: isSelected,
                  constraints: constraints,
                );
              }),
            ],
          );

          return content;
        },
      ),
    );
  }

  Widget _buildPageBox({
    required int index,
    required Rect bounds,
    required bool isSelected,
    required BoxConstraints constraints,
  }) {
    // Convert canvas coordinates to screen coordinates
    final screenBounds = Rect.fromLTWH(
      bounds.left * widget.canvasScale + widget.canvasOffset.dx,
      bounds.top * widget.canvasScale + widget.canvasOffset.dy,
      bounds.width * widget.canvasScale,
      bounds.height * widget.canvasScale,
    );

    final showHandles = isSelected || !widget.showHandlesOnlySelected;

    return Stack(
      children: [
        // Page border and number
        Positioned(
          left: screenBounds.left,
          top: screenBounds.top,
          width: screenBounds.width,
          height: screenBounds.height,
          child: GestureDetector(
            onTap: () => _selectPage(index),
            onScaleStart: (details) => onPageScaleStart(index, details),
            onScaleUpdate: onPageScaleUpdate,
            onScaleEnd: onPageScaleEnd,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: isSelected ? Colors.blue : Colors.white70,
                  width: isSelected ? 3 : 2,
                ),
                color: Colors.white.withValues(alpha: 0.05),
              ),
              child: Stack(
                children: [
                  // Page number badge
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.blue : Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                  // Dimensions indicator
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${bounds.width.toInt()} × ${bounds.height.toInt()}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),

                  // Format label (if uniform)
                  if (widget.config.mode == MultiPageMode.uniform)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          widget.config.pageFormat.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),

        // Resize handles (only for selected page or all if not showHandlesOnlySelected)
        if (showHandles) ..._buildResizeHandles(index, screenBounds),
      ],
    );
  }

  List<Widget> _buildResizeHandles(int pageIndex, Rect screenBounds) {
    final handles = <Widget>[];
    final isUniform = widget.config.mode == MultiPageMode.uniform;

    // Handle positions
    final handlePositions = {
      'tl': Offset(screenBounds.left, screenBounds.top),
      'tc': Offset(screenBounds.center.dx, screenBounds.top),
      'tr': Offset(screenBounds.right, screenBounds.top),
      'ml': Offset(screenBounds.left, screenBounds.center.dy),
      'mr': Offset(screenBounds.right, screenBounds.center.dy),
      'bl': Offset(screenBounds.left, screenBounds.bottom),
      'bc': Offset(screenBounds.center.dx, screenBounds.bottom),
      'br': Offset(screenBounds.right, screenBounds.bottom),
    };

    // Cursors for each handle
    final handleCursors = {
      'tl': SystemMouseCursors.resizeUpLeftDownRight,
      'tc': SystemMouseCursors.resizeUpDown,
      'tr': SystemMouseCursors.resizeUpRightDownLeft,
      'ml': SystemMouseCursors.resizeLeftRight,
      'mr': SystemMouseCursors.resizeLeftRight,
      'bl': SystemMouseCursors.resizeUpRightDownLeft,
      'bc': SystemMouseCursors.resizeUpDown,
      'br': SystemMouseCursors.resizeUpLeftDownRight,
    };

    for (final entry in handlePositions.entries) {
      final handleId = entry.key;
      final position = entry.value;

      handles.add(
        Positioned(
          left: position.dx - _handleHitArea / 2,
          top: position.dy - _handleHitArea / 2,
          child: MouseRegion(
            cursor: handleCursors[handleId]!,
            child: GestureDetector(
              onPanStart:
                  (details) => onHandleDragStart(pageIndex, handleId, details),
              onPanUpdate: (details) => onHandleDragUpdate(details, isUniform),
              onPanEnd: onHandleDragEnd,
              child: Container(
                width: _handleHitArea,
                height: _handleHitArea,
                alignment: Alignment.center,
                child: Container(
                  width: _handleSize,
                  height: _handleSize,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.blue, width: 2),
                    borderRadius: BorderRadius.circular(_handleSize / 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    _getHandleIcon(handleId),
                    size: 12,
                    color: Colors.blue,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return handles;
  }

  IconData _getHandleIcon(String handleId) {
    switch (handleId) {
      case 'tl':
      case 'br':
        return Icons.open_in_full;
      case 'tr':
      case 'bl':
        return Icons.open_in_full;
      case 'tc':
      case 'bc':
        return Icons.height;
      case 'ml':
      case 'mr':
        return Icons.width_normal;
      default:
        return Icons.drag_indicator;
    }
  }

  void _selectPage(int index) {
    if (widget.config.selectedPageIndex != index) {
      widget.onConfigChanged(widget.config.copyWith(selectedPageIndex: index));
      HapticFeedback.selectionClick();
    }
  }

  /// Deselect the current page (tap on empty canvas)
  void _deselectPage() {
    if (widget.config.selectedPageIndex != -1) {
      widget.onConfigChanged(widget.config.copyWith(selectedPageIndex: -1));
      HapticFeedback.selectionClick();
    }
  }
}

/// Painter for dark overlay with holes for pages
class _DarkOverlayPainter extends CustomPainter {
  final List<Rect> pageBounds;
  final double canvasScale;
  final Offset canvasOffset;

  _DarkOverlayPainter({
    required this.pageBounds,
    required this.canvasScale,
    required this.canvasOffset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = Colors.black.withValues(alpha: 0.6)
          ..style = PaintingStyle.fill;

    // Create path for the entire overlay
    final overlayPath =
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    // Create path for holes (page areas)
    final holePath = Path();
    for (final bounds in pageBounds) {
      final screenBounds = Rect.fromLTWH(
        bounds.left * canvasScale + canvasOffset.dx,
        bounds.top * canvasScale + canvasOffset.dy,
        bounds.width * canvasScale,
        bounds.height * canvasScale,
      );
      holePath.addRect(screenBounds);
    }

    // Combine paths using difference
    final combinedPath = Path.combine(
      PathOperation.difference,
      overlayPath,
      holePath,
    );

    canvas.drawPath(combinedPath, paint);
  }

  @override
  bool shouldRepaint(covariant _DarkOverlayPainter oldDelegate) {
    return pageBounds != oldDelegate.pageBounds ||
        canvasScale != oldDelegate.canvasScale ||
        canvasOffset != oldDelegate.canvasOffset;
  }
}
