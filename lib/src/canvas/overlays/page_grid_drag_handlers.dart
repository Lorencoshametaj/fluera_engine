part of 'interactive_page_grid_overlay.dart';

// ==================== AUTO-PAN LOGIC ====================

extension _PageGridDragHandlers on _InteractivePageGridOverlayState {
  /// Calculates the pan delta based on cursor position near edges
  Offset calculateAutoPanDelta(Offset position) {
    double dx = 0;
    double dy = 0;

    // Left edge
    if (position.dx < _InteractivePageGridOverlayState._autoPanEdgeZone) {
      dx = -_InteractivePageGridOverlayState._autoPanSpeed * (1 - position.dx / _InteractivePageGridOverlayState._autoPanEdgeZone);
    }
    // Right edge
    else if (position.dx > _viewportSize.width - _InteractivePageGridOverlayState._autoPanEdgeZone) {
      dx =
          _InteractivePageGridOverlayState._autoPanSpeed *
          (1 - (_viewportSize.width - position.dx) / _InteractivePageGridOverlayState._autoPanEdgeZone);
    }

    // Top edge
    if (position.dy < _InteractivePageGridOverlayState._autoPanEdgeZone) {
      dy = -_InteractivePageGridOverlayState._autoPanSpeed * (1 - position.dy / _InteractivePageGridOverlayState._autoPanEdgeZone);
    }
    // Bottom edge
    else if (position.dy > _viewportSize.height - _InteractivePageGridOverlayState._autoPanEdgeZone) {
      dy =
          _InteractivePageGridOverlayState._autoPanSpeed *
          (1 - (_viewportSize.height - position.dy) / _InteractivePageGridOverlayState._autoPanEdgeZone);
    }

    return Offset(dx, dy);
  }

  /// Starts the timer for continuous auto-pan
  void startAutoPan() {
    if (_autoPanTimer != null) return;

    _autoPanTimer = Timer.periodic(_InteractivePageGridOverlayState._autoPanInterval, (_) {
      if (!_isDraggingPage && _activeHandle == null) {
        stopAutoPan();
        return;
      }

      final panDelta = calculateAutoPanDelta(_lastDragPosition);

      if (panDelta != Offset.zero && widget.onPanCanvas != null) {
        final canvasDelta = panDelta / widget.canvasScale;

        // Update _initialPageBounds to compensate for canvas movement
        if (_initialPageBounds != null) {
          _initialPageBounds = _initialPageBounds!.translate(
            canvasDelta.dx,
            canvasDelta.dy,
          );
        }

        // Update the actual page position in the config
        // And move the canvas together in the same frame
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

          // First move the canvas
          widget.onPanCanvas!(panDelta);
          // Then update the config (in the same frame)
          widget.onConfigChanged(newConfig);
        } else {
          // Canvas movement only (for handle resize)
          widget.onPanCanvas!(panDelta);
        }
      }
    });
  }

  /// Stops the auto-pan timer
  void stopAutoPan() {
    _autoPanTimer?.cancel();
    _autoPanTimer = null;
  }

  // ==================== PAGE SCALE HANDLERS (drag + zoom) ====================

  void onPageScaleStart(int index, ScaleStartDetails details) {
    _draggingPageIndex = index;
    _dragStartPosition = details.focalPoint;
    _initialPageBounds = widget.config.individualPageBounds[index];
    _isDraggingPage = true;

    // Convert to local coordinates for auto-pan
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box != null) {
      _lastDragPosition = box.globalToLocal(details.focalPoint);
    }

    // Select the page if not already selected
    if (widget.config.selectedPageIndex != index) {
      widget.onConfigChanged(widget.config.copyWith(selectedPageIndex: index));
    }

    // Start auto-pan
    startAutoPan();
  }

  void onPageScaleUpdate(ScaleUpdateDetails details) {
    // 🤏 2+ fingers → forward zoom to canvas, cancel drag
    if (details.pointerCount >= 2) {
      if (_isDraggingPage) {
        // Cancel active drag and initialize per-frame scale tracking
        stopAutoPan();
        _isDraggingPage = false;
        _lastForwardedScale = details.scale;
        setState(() => _activeSnapLines = []);
      }
      if (widget.onScaleCanvas != null) {
        final frameRatio = details.scale / _lastForwardedScale;
        _lastForwardedScale = details.scale;
        widget.onScaleCanvas!(details.localFocalPoint, frameRatio);
      }
      return;
    }

    // 👆 1 finger → page drag
    if (!_isDraggingPage ||
        _draggingPageIndex == null ||
        _initialPageBounds == null ||
        _dragStartPosition == null) {
      return;
    }

    // Update position for auto-pan
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box != null) {
      _lastDragPosition = box.globalToLocal(details.focalPoint);
    }

    final delta = details.focalPoint - _dragStartPosition!;
    final canvasDelta = delta / widget.canvasScale;

    var newBounds = _initialPageBounds!.translate(
      canvasDelta.dx,
      canvasDelta.dy,
    );

    // Apply snap/magnetism
    final snapResult = calculateSnap(newBounds, _draggingPageIndex!);
    newBounds = newBounds.translate(snapResult.offset.dx, snapResult.offset.dy);

    // Haptic feedback when snapping
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

  void onPageScaleEnd(ScaleEndDetails details) {
    stopAutoPan();
    _isDraggingPage = false;
    _draggingPageIndex = null;
    _dragStartPosition = null;
    _initialPageBounds = null;

    // Hide guide lines
    setState(() {
      _activeSnapLines = [];
    });

    HapticFeedback.selectionClick();
  }

  void onHandleDragStart(
    int pageIndex,
    String handleId,
    DragStartDetails details,
  ) {
    _draggingPageIndex = pageIndex;
    _activeHandle = handleId;
    _dragStartPosition = details.globalPosition;
    _initialPageBounds = widget.config.individualPageBounds[pageIndex];

    // Convert to local coordinates for auto-pan
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

    // Start auto-pan
    startAutoPan();
  }

  void onHandleDragUpdate(DragUpdateDetails details, bool isUniform) {
    if (_activeHandle == null ||
        _draggingPageIndex == null ||
        _initialPageBounds == null ||
        _dragStartPosition == null) {
      return;
    }

    // Update position for auto-pan
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box != null) {
      _lastDragPosition = box.globalToLocal(details.globalPosition);
    }

    final delta = details.globalPosition - _dragStartPosition!;
    final canvasDelta = delta / widget.canvasScale;

    final newBounds = calculateNewBounds(
      _initialPageBounds!,
      _activeHandle!,
      canvasDelta,
      isUniform,
    );

    widget.onConfigChanged(
      widget.config.updatePageBounds(_draggingPageIndex!, newBounds),
    );
  }

  void onHandleDragEnd(DragEndDetails details) {
    stopAutoPan();
    _activeHandle = null;
    _draggingPageIndex = null;
    _dragStartPosition = null;
    _initialPageBounds = null;
    HapticFeedback.selectionClick();
  }

  Rect calculateNewBounds(
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
    if (right - left < _InteractivePageGridOverlayState._minPageSize) {
      if (handle.contains('l')) {
        left = right - _InteractivePageGridOverlayState._minPageSize;
      } else {
        right = left + _InteractivePageGridOverlayState._minPageSize;
      }
    }
    if (bottom - top < _InteractivePageGridOverlayState._minPageSize) {
      if (handle.contains('t')) {
        top = bottom - _InteractivePageGridOverlayState._minPageSize;
      } else {
        bottom = top + _InteractivePageGridOverlayState._minPageSize;
      }
    }

    return Rect.fromLTRB(left, top, right, bottom);
  }
}
