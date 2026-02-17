import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/multi_page_config.dart';
import '../../export/export_preset.dart'; // For ExportPageFormatUtils extension

/// 📐 INTERACTIVE PAGE GRID OVERLAY
///
/// Widget overlay per editing interattivo of pages multi-page.
/// Supporta due mode:
/// - Uniform: tutte le pagine hanno la stessa size
/// - Individual: ogni pagina can essere ridimensionata indipendentemente
class InteractivePageGridOverlay extends StatefulWidget {
  /// Multi-page configuration
  final MultiPageConfig config;

  /// Callback when the configuration changes
  final ValueChanged<MultiPageConfig> onConfigChanged;

  /// Scala of the canvas
  final double canvasScale;

  /// Offset of the canvas
  final Offset canvasOffset;

  /// If true, mostra gli handle di resize solo for the pagina selezionata
  final bool showHandlesOnlySelected;

  /// Callback per richiedere lo scorrimento of the canvas (auto-pan)
  /// The parametro is il delta di pan richiesto in screen coordinates
  final ValueChanged<Offset>? onPanCanvas;

  /// Padding inferiore per escludere la toolbar dall'area interattiva
  final double bottomPadding;

  /// If true, mostra l'overlay scuro. Se false, mostra solo le pagine.
  final bool showDarkOverlay;

  const InteractivePageGridOverlay({
    super.key,
    required this.config,
    required this.onConfigChanged,
    required this.canvasScale,
    required this.canvasOffset,
    this.showHandlesOnlySelected = true,
    this.onPanCanvas,
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
  static const double _autoPanEdgeZone =
      60.0; // Zona ai bordi che attiva l'auto-pan
  static const double _autoPanSpeed =
      5.0; // Speed base dell'auto-pan (ridotta)
  static const Duration _autoPanInterval = Duration(milliseconds: 16); // ~60fps

  // Snap/Magnetism constants
  static const double _snapThreshold =
      15.0; // Distanza in pixel per attivare lo snap
  static const double _snapGap = 10.0; // Gap tra pagine when agganciano

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

  // Snap state - linee guida visibili durante il drag
  List<_SnapLine> _activeSnapLines = [];

  // Multi-touch state (per permettere pinch zoom)
  int _pointerCount = 0;

  @override
  void dispose() {
    _stopAutoPan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      // Traccia il number of pointer per permettere pinch zoom
      onPointerDown: (_) {
        setState(() => _pointerCount++);
      },
      onPointerUp: (_) {
        setState(() => _pointerCount = (_pointerCount - 1).clamp(0, 10));
      },
      onPointerCancel: (_) {
        setState(() => _pointerCount = (_pointerCount - 1).clamp(0, 10));
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Save la size of the viewport per l'auto-pan
          _viewportSize = Size(constraints.maxWidth, constraints.maxHeight);

          // If ci sono 2+ tocchi, ignora i gesti per permettere pinch zoom
          final content = Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              // Dark overlay (opzionale) - tap per deselezionare
              if (widget.showDarkOverlay)
                Positioned.fill(
                  child: GestureDetector(
                    onTap: _deselectPage,
                    behavior: HitTestBehavior.translucent,
                    child: CustomPaint(
                      painter: _DarkOverlayPainter(
                        pageBounds: widget.config.individualPageBounds,
                        canvasScale: widget.canvasScale,
                        canvasOffset: widget.canvasOffset,
                      ),
                    ),
                  ),
                ),

              // Snap guide lines (mostrate durante il drag)
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

          // With 2+ tocchi, permetti al pinch zoom di passare attraverso
          if (_pointerCount >= 2) {
            return IgnorePointer(child: content);
          }

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
            onPanStart: (details) => _onPageDragStart(index, details),
            onPanUpdate: _onPageDragUpdate,
            onPanEnd: _onPageDragEnd,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: isSelected ? Colors.blue : Colors.white70,
                  width: isSelected ? 3 : 2,
                ),
                color: Colors.white.withValues(alpha:  0.05),
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
                          color: Colors.blue.withValues(alpha:  0.8),
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
                  (details) => _onHandleDragStart(pageIndex, handleId, details),
              onPanUpdate: (details) => _onHandleDragUpdate(details, isUniform),
              onPanEnd: _onHandleDragEnd,
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
                        color: Colors.black.withValues(alpha:  0.3),
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

  /// Deseleziona la current page (tap on the canvas vuoto)
  void _deselectPage() {
    if (widget.config.selectedPageIndex != -1) {
      widget.onConfigChanged(widget.config.copyWith(selectedPageIndex: -1));
      HapticFeedback.selectionClick();
    }
  }

  // ==================== AUTO-PAN LOGIC ====================

  /// Calculatates il delta di pan basato sulla position del cursore vicino ai bordi
  Offset _calculateAutoPanDelta(Offset position) {
    double dx = 0;
    double dy = 0;

    // Bordo sinistro
    if (position.dx < _autoPanEdgeZone) {
      dx = -_autoPanSpeed * (1 - position.dx / _autoPanEdgeZone);
    }
    // Bordo destro
    else if (position.dx > _viewportSize.width - _autoPanEdgeZone) {
      dx =
          _autoPanSpeed *
          (1 - (_viewportSize.width - position.dx) / _autoPanEdgeZone);
    }

    // Bordo superiore
    if (position.dy < _autoPanEdgeZone) {
      dy = -_autoPanSpeed * (1 - position.dy / _autoPanEdgeZone);
    }
    // Bordo inferiore
    else if (position.dy > _viewportSize.height - _autoPanEdgeZone) {
      dy =
          _autoPanSpeed *
          (1 - (_viewportSize.height - position.dy) / _autoPanEdgeZone);
    }

    return Offset(dx, dy);
  }

  /// Avvia il timer per l'auto-pan continuo
  void _startAutoPan() {
    if (_autoPanTimer != null) return;

    _autoPanTimer = Timer.periodic(_autoPanInterval, (_) {
      if (!_isDraggingPage && _activeHandle == null) {
        _stopAutoPan();
        return;
      }

      final panDelta = _calculateAutoPanDelta(_lastDragPosition);

      if (panDelta != Offset.zero && widget.onPanCanvas != null) {
        final canvasDelta = panDelta / widget.canvasScale;

        // Update _initialPageBounds per compensare il movimento of the canvas
        if (_initialPageBounds != null) {
          _initialPageBounds = _initialPageBounds!.translate(
            canvasDelta.dx,
            canvasDelta.dy,
          );
        }

        // Update the actual page position in the config
        // E muovi il canvas insieme nello stesso frame
        if (_isDraggingPage && _draggingPageIndex != null) {
          final currentBounds =
              widget.config.individualPageBounds[_draggingPageIndex!];
          final newBounds = currentBounds.translate(
            canvasDelta.dx,
            canvasDelta.dy,
          );

          final newConfig = widget.config.copyWith(
            individualPageBounds: List.from(widget.config.individualPageBounds)
              ..[_draggingPageIndex!] = newBounds,
          );

          // Prima muovi il canvas
          widget.onPanCanvas!(panDelta);
          // Poi aggiorna il config (nello stesso frame)
          widget.onConfigChanged(newConfig);
        } else {
          // Only movimento canvas (per handle resize)
          widget.onPanCanvas!(panDelta);
        }
      }
    });
  }

  /// Ferma il timer dell'auto-pan
  void _stopAutoPan() {
    _autoPanTimer?.cancel();
    _autoPanTimer = null;
  }

  // ==================== PAGE DRAG HANDLERS ====================

  void _onPageDragStart(int index, DragStartDetails details) {
    _draggingPageIndex = index;
    _dragStartPosition = details.globalPosition;
    _initialPageBounds = widget.config.individualPageBounds[index];
    _isDraggingPage = true;

    // Convert in local coordinates per l'auto-pan
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box != null) {
      _lastDragPosition = box.globalToLocal(details.globalPosition);
    }

    // Select the page if not already selected
    if (widget.config.selectedPageIndex != index) {
      widget.onConfigChanged(widget.config.copyWith(selectedPageIndex: index));
    }

    // Avvia l'auto-pan
    _startAutoPan();
  }

  void _onPageDragUpdate(DragUpdateDetails details) {
    if (!_isDraggingPage ||
        _draggingPageIndex == null ||
        _initialPageBounds == null ||
        _dragStartPosition == null) {
      return;
    }

    // Update position per l'auto-pan
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box != null) {
      _lastDragPosition = box.globalToLocal(details.globalPosition);
    }

    final delta = details.globalPosition - _dragStartPosition!;
    final canvasDelta = delta / widget.canvasScale;

    var newBounds = _initialPageBounds!.translate(
      canvasDelta.dx,
      canvasDelta.dy,
    );

    // Applica snap/magnetismo
    final snapResult = _calculateSnap(newBounds, _draggingPageIndex!);
    newBounds = newBounds.translate(snapResult.offset.dx, snapResult.offset.dy);

    // Feedback aptico when aggancia
    final wasSnapped = _activeSnapLines.isNotEmpty;
    final isSnapped = snapResult.lines.isNotEmpty;
    if (isSnapped && !wasSnapped) {
      HapticFeedback.lightImpact();
    }

    setState(() {
      _activeSnapLines = snapResult.lines;
    });

    final newConfig = widget.config.copyWith(
      individualPageBounds: List.from(widget.config.individualPageBounds)
        ..[_draggingPageIndex!] = newBounds,
    );

    widget.onConfigChanged(newConfig);
  }

  void _onPageDragEnd(DragEndDetails details) {
    _stopAutoPan();
    _isDraggingPage = false;
    _draggingPageIndex = null;
    _dragStartPosition = null;
    _initialPageBounds = null;

    // Nascondi le linee guida
    setState(() {
      _activeSnapLines = [];
    });

    HapticFeedback.selectionClick();
  }

  void _onHandleDragStart(
    int pageIndex,
    String handleId,
    DragStartDetails details,
  ) {
    _draggingPageIndex = pageIndex;
    _activeHandle = handleId;
    _dragStartPosition = details.globalPosition;
    _initialPageBounds = widget.config.individualPageBounds[pageIndex];

    // Convert in local coordinates per l'auto-pan
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box != null) {
      _lastDragPosition = box.globalToLocal(details.globalPosition);
    }

    // Select the page
    if (widget.config.selectedPageIndex != pageIndex) {
      widget.onConfigChanged(
        widget.config.copyWith(selectedPageIndex: pageIndex),
      );
    }

    // Avvia l'auto-pan
    _startAutoPan();
  }

  void _onHandleDragUpdate(DragUpdateDetails details, bool isUniform) {
    if (_activeHandle == null ||
        _draggingPageIndex == null ||
        _initialPageBounds == null ||
        _dragStartPosition == null) {
      return;
    }

    // Update position per l'auto-pan
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box != null) {
      _lastDragPosition = box.globalToLocal(details.globalPosition);
    }

    final delta = details.globalPosition - _dragStartPosition!;
    final canvasDelta = delta / widget.canvasScale;

    final newBounds = _calculateNewBounds(
      _initialPageBounds!,
      _activeHandle!,
      canvasDelta,
      isUniform,
    );

    widget.onConfigChanged(
      widget.config.updatePageBounds(_draggingPageIndex!, newBounds),
    );
  }

  void _onHandleDragEnd(DragEndDetails details) {
    _stopAutoPan();
    _activeHandle = null;
    _draggingPageIndex = null;
    _dragStartPosition = null;
    _initialPageBounds = null;
    HapticFeedback.selectionClick();
  }

  Rect _calculateNewBounds(
    Rect initial,
    String handle,
    Offset delta,
    bool maintainAspectRatio,
  ) {
    double left = initial.left;
    double top = initial.top;
    double right = initial.right;
    double bottom = initial.bottom;

    switch (handle) {
      case 'tl':
        left += delta.dx;
        top += delta.dy;
        if (maintainAspectRatio) {
          final aspectRatio = initial.width / initial.height;
          final newWidth = right - left;
          final newHeight = newWidth / aspectRatio;
          top = bottom - newHeight;
        }
        break;
      case 'tc':
        top += delta.dy;
        if (maintainAspectRatio) {
          final aspectRatio = initial.width / initial.height;
          final newHeight = bottom - top;
          final newWidth = newHeight * aspectRatio;
          final widthDelta = newWidth - initial.width;
          left -= widthDelta / 2;
          right += widthDelta / 2;
        }
        break;
      case 'tr':
        right += delta.dx;
        top += delta.dy;
        if (maintainAspectRatio) {
          final aspectRatio = initial.width / initial.height;
          final newWidth = right - left;
          final newHeight = newWidth / aspectRatio;
          top = bottom - newHeight;
        }
        break;
      case 'ml':
        left += delta.dx;
        if (maintainAspectRatio) {
          final aspectRatio = initial.width / initial.height;
          final newWidth = right - left;
          final newHeight = newWidth / aspectRatio;
          final heightDelta = newHeight - initial.height;
          top -= heightDelta / 2;
          bottom += heightDelta / 2;
        }
        break;
      case 'mr':
        right += delta.dx;
        if (maintainAspectRatio) {
          final aspectRatio = initial.width / initial.height;
          final newWidth = right - left;
          final newHeight = newWidth / aspectRatio;
          final heightDelta = newHeight - initial.height;
          top -= heightDelta / 2;
          bottom += heightDelta / 2;
        }
        break;
      case 'bl':
        left += delta.dx;
        bottom += delta.dy;
        if (maintainAspectRatio) {
          final aspectRatio = initial.width / initial.height;
          final newWidth = right - left;
          final newHeight = newWidth / aspectRatio;
          bottom = top + newHeight;
        }
        break;
      case 'bc':
        bottom += delta.dy;
        if (maintainAspectRatio) {
          final aspectRatio = initial.width / initial.height;
          final newHeight = bottom - top;
          final newWidth = newHeight * aspectRatio;
          final widthDelta = newWidth - initial.width;
          left -= widthDelta / 2;
          right += widthDelta / 2;
        }
        break;
      case 'br':
        right += delta.dx;
        bottom += delta.dy;
        if (maintainAspectRatio) {
          final aspectRatio = initial.width / initial.height;
          final newWidth = right - left;
          final newHeight = newWidth / aspectRatio;
          bottom = top + newHeight;
        }
        break;
    }

    // Enforce minimum size
    if (right - left < _minPageSize) {
      if (handle.contains('l')) {
        left = right - _minPageSize;
      } else {
        right = left + _minPageSize;
      }
    }
    if (bottom - top < _minPageSize) {
      if (handle.contains('t')) {
        top = bottom - _minPageSize;
      } else {
        bottom = top + _minPageSize;
      }
    }

    return Rect.fromLTRB(left, top, right, bottom);
  }

  // ==================== SNAP/MAGNETISM LOGIC ====================

  /// Calculatates lo snap per allineare la pagina alle altre
  _SnapResult _calculateSnap(Rect movingBounds, int movingIndex) {
    final snapLines = <_SnapLine>[];
    double snapDx = 0;
    double snapDy = 0;

    // Threshold in canvas coordinates
    final threshold = _snapThreshold / widget.canvasScale;
    final gap = _snapGap / widget.canvasScale;

    // Bordi della pagina in movimento
    final movingLeft = movingBounds.left;
    final movingRight = movingBounds.right;
    final movingTop = movingBounds.top;
    final movingBottom = movingBounds.bottom;
    final movingCenterX = movingBounds.center.dx;
    final movingCenterY = movingBounds.center.dy;

    bool snappedHorizontal = false;
    bool snappedVertical = false;

    // Check alignment with every other page
    for (int i = 0; i < widget.config.individualPageBounds.length; i++) {
      if (i == movingIndex) continue;

      final other = widget.config.individualPageBounds[i];
      final otherLeft = other.left;
      final otherRight = other.right;
      final otherTop = other.top;
      final otherBottom = other.bottom;
      final otherCenterX = other.center.dx;
      final otherCenterY = other.center.dy;

      // === SNAP ORIZZONTALE ===
      if (!snappedHorizontal) {
        // Left to Left
        if ((movingLeft - otherLeft).abs() < threshold) {
          snapDx = otherLeft - movingLeft;
          snapLines.add(
            _SnapLine(
              start: Offset(otherLeft, movingTop.clamp(otherTop, otherBottom)),
              end: Offset(otherLeft, movingBottom.clamp(otherTop, otherBottom)),
              isVertical: true,
            ),
          );
          snappedHorizontal = true;
        }
        // Right to Right
        else if ((movingRight - otherRight).abs() < threshold) {
          snapDx = otherRight - movingRight;
          snapLines.add(
            _SnapLine(
              start: Offset(otherRight, movingTop.clamp(otherTop, otherBottom)),
              end: Offset(
                otherRight,
                movingBottom.clamp(otherTop, otherBottom),
              ),
              isVertical: true,
            ),
          );
          snappedHorizontal = true;
        }
        // Left to Right (con gap)
        else if ((movingLeft - otherRight - gap).abs() < threshold) {
          snapDx = otherRight + gap - movingLeft;
          snapLines.add(
            _SnapLine(
              start: Offset(otherRight + gap / 2, movingCenterY),
              end: Offset(otherRight + gap / 2, otherCenterY),
              isVertical: true,
            ),
          );
          snappedHorizontal = true;
        }
        // Right to Left (con gap)
        else if ((movingRight - otherLeft + gap).abs() < threshold) {
          snapDx = otherLeft - gap - movingRight;
          snapLines.add(
            _SnapLine(
              start: Offset(otherLeft - gap / 2, movingCenterY),
              end: Offset(otherLeft - gap / 2, otherCenterY),
              isVertical: true,
            ),
          );
          snappedHorizontal = true;
        }
        // Center to Center (orizzontale)
        else if ((movingCenterX - otherCenterX).abs() < threshold) {
          snapDx = otherCenterX - movingCenterX;
          snapLines.add(
            _SnapLine(
              start: Offset(otherCenterX, movingTop),
              end: Offset(otherCenterX, otherBottom),
              isVertical: true,
            ),
          );
          snappedHorizontal = true;
        }
      }

      // === SNAP VERTICALE ===
      if (!snappedVertical) {
        // Top to Top
        if ((movingTop - otherTop).abs() < threshold) {
          snapDy = otherTop - movingTop;
          snapLines.add(
            _SnapLine(
              start: Offset(movingLeft.clamp(otherLeft, otherRight), otherTop),
              end: Offset(movingRight.clamp(otherLeft, otherRight), otherTop),
              isVertical: false,
            ),
          );
          snappedVertical = true;
        }
        // Bottom to Bottom
        else if ((movingBottom - otherBottom).abs() < threshold) {
          snapDy = otherBottom - movingBottom;
          snapLines.add(
            _SnapLine(
              start: Offset(
                movingLeft.clamp(otherLeft, otherRight),
                otherBottom,
              ),
              end: Offset(
                movingRight.clamp(otherLeft, otherRight),
                otherBottom,
              ),
              isVertical: false,
            ),
          );
          snappedVertical = true;
        }
        // Top to Bottom (con gap)
        else if ((movingTop - otherBottom - gap).abs() < threshold) {
          snapDy = otherBottom + gap - movingTop;
          snapLines.add(
            _SnapLine(
              start: Offset(movingCenterX, otherBottom + gap / 2),
              end: Offset(otherCenterX, otherBottom + gap / 2),
              isVertical: false,
            ),
          );
          snappedVertical = true;
        }
        // Bottom to Top (con gap)
        else if ((movingBottom - otherTop + gap).abs() < threshold) {
          snapDy = otherTop - gap - movingBottom;
          snapLines.add(
            _SnapLine(
              start: Offset(movingCenterX, otherTop - gap / 2),
              end: Offset(otherCenterX, otherTop - gap / 2),
              isVertical: false,
            ),
          );
          snappedVertical = true;
        }
        // Center to Center (verticale)
        else if ((movingCenterY - otherCenterY).abs() < threshold) {
          snapDy = otherCenterY - movingCenterY;
          snapLines.add(
            _SnapLine(
              start: Offset(movingLeft, otherCenterY),
              end: Offset(otherRight, otherCenterY),
              isVertical: false,
            ),
          );
          snappedVertical = true;
        }
      }

      // If abbiamo trovato snap in entrambe le direzioni, esci
      if (snappedHorizontal && snappedVertical) break;
    }

    return _SnapResult(offset: Offset(snapDx, snapDy), lines: snapLines);
  }
}

/// Risultato del calcolo snap
class _SnapResult {
  final Offset offset;
  final List<_SnapLine> lines;

  _SnapResult({required this.offset, required this.lines});
}

/// Linea guida for the snap
class _SnapLine {
  final Offset start;
  final Offset end;
  final bool isVertical;

  _SnapLine({required this.start, required this.end, required this.isVertical});
}

/// Painter for the linee guida dello snap
class _SnapLinesPainter extends CustomPainter {
  final List<_SnapLine> snapLines;
  final double canvasScale;
  final Offset canvasOffset;

  _SnapLinesPainter({
    required this.snapLines,
    required this.canvasScale,
    required this.canvasOffset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = Colors.cyan
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke;

    final dashPaint =
        Paint()
          ..color = Colors.cyan.withValues(alpha:  0.5)
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke;

    for (final line in snapLines) {
      // Convert in screen coordinates
      final screenStart = Offset(
        line.start.dx * canvasScale + canvasOffset.dx,
        line.start.dy * canvasScale + canvasOffset.dy,
      );
      final screenEnd = Offset(
        line.end.dx * canvasScale + canvasOffset.dx,
        line.end.dy * canvasScale + canvasOffset.dy,
      );

      // Estendi la linea verso i bordi dello schermo
      Offset extendedStart;
      Offset extendedEnd;

      if (line.isVertical) {
        extendedStart = Offset(screenStart.dx, 0);
        extendedEnd = Offset(screenEnd.dx, size.height);
      } else {
        extendedStart = Offset(0, screenStart.dy);
        extendedEnd = Offset(size.width, screenEnd.dy);
      }

      // Draw linea tratteggiata estesa
      _drawDashedLine(canvas, extendedStart, extendedEnd, dashPaint);

      // Draw linea solida nella zona di snap
      canvas.drawLine(screenStart, screenEnd, paint);

      // Draw cerchietti agli estremi
      canvas.drawCircle(screenStart, 4, paint..style = PaintingStyle.fill);
      canvas.drawCircle(screenEnd, 4, paint..style = PaintingStyle.fill);
      paint.style = PaintingStyle.stroke;
    }
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashLength = 8.0;
    const gapLength = 4.0;

    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final distance = (Offset(dx, dy)).distance;
    final steps = (distance / (dashLength + gapLength)).floor();

    for (int i = 0; i < steps; i++) {
      final t1 = (i * (dashLength + gapLength)) / distance;
      final t2 = (i * (dashLength + gapLength) + dashLength) / distance;

      if (t1 < 1 && t2 <= 1) {
        canvas.drawLine(
          Offset(start.dx + dx * t1, start.dy + dy * t1),
          Offset(start.dx + dx * t2, start.dy + dy * t2),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SnapLinesPainter oldDelegate) {
    return snapLines != oldDelegate.snapLines ||
        canvasScale != oldDelegate.canvasScale ||
        canvasOffset != oldDelegate.canvasOffset;
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
          ..color = Colors.black.withValues(alpha:  0.6)
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
