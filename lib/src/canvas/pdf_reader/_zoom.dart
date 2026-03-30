part of 'pdf_reader_screen.dart';

/// Zoom, pan, swipe-dismiss, and double-tap zoom handling.
extension _PdfZoomMethods on _PdfReaderScreenState {

  // ---------------------------------------------------------------------------
  // Scroll & page tracking
  // ---------------------------------------------------------------------------

  void _onScroll() {
    // Page tracking from TransformationController offset
    final yOffset = -_zoomController.value.row1.w;
    final scale = _zoomController.value.getMaxScaleOnAxis();
    final effectiveOffset = yOffset / scale;

    double accumulated = 0;
    for (int i = 0; i < widget.documentModel.totalPages; i++) {
      final pageHeight = _getPageDisplayHeight(i);
      final pageBottom = accumulated + pageHeight;
      final viewportMid = effectiveOffset + MediaQuery.of(context).size.height / 2;

      if (accumulated <= viewportMid && pageBottom > effectiveOffset) {
        if (_currentPageIndex != i) {
          setState(() => _currentPageIndex = i);
        }
        break;
      }
      accumulated += pageHeight + 16.0;
    }

    // Always ensure nearby pages are rendered when scrolling
    _ensureVisiblePagesRendered();
  }

  // ---------------------------------------------------------------------------
  // Pinch-to-zoom & zoom-out-to-exit
  // ---------------------------------------------------------------------------

  void _onZoomChanged() {
    final scale = _zoomController.value.getMaxScaleOnAxis();
    final changed = (_currentZoomScale - scale).abs() > 0.01;
    final previousScale = _currentZoomScale;
    _currentZoomScale = scale;

    // 📍 Haptic snap at round zoom levels (1×, 2×, 3×)
    final currentSnap = scale.round();
    if (currentSnap != _lastSnapLevel && currentSnap >= 1 && currentSnap <= 4) {
      final diff = (scale - currentSnap).abs();
      if (diff < 0.05) {
        HapticFeedback.selectionClick();
        _lastSnapLevel = currentSnap;
      }
    }

    // Show zoom indicator and schedule auto-fade
    if (changed && (scale - 1.0).abs() > 0.05) {
      _zoomIndicatorTimer?.cancel();
      if (_zoomIndicatorOpacity < 1.0) {
        _zoomIndicatorOpacity = 1.0;
      }
      _zoomIndicatorTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _zoomIndicatorOpacity = 0.0);
      });
    } else if ((scale - 1.0).abs() <= 0.05) {
      _zoomIndicatorOpacity = 0.0;
    }

    // Only rebuild when zoom indicator visibility or exit hint actually changes
    final needsRebuild = changed && mounted && (
      // Zoom indicator visibility changed
      (previousScale - 1.0).abs() <= 0.05 != (scale - 1.0).abs() <= 0.05 ||
      // Exit hint visibility changed  
      (previousScale >= 0.95) != (scale >= 0.95) ||
      // Exit-ready state changed
      (previousScale >= 0.75) != (scale >= 0.75) ||
      // Zoom percentage display changed (skip during active interaction for perf)
      (!_isInteracting && (previousScale * 100).round() != (scale * 100).round())
    );
    
    if (needsRebuild) {
      setState(() {});
    }

    // Update page tracking on every scroll (but not during active pinch)
    if (changed && mounted && !_isInteracting) {
      _onScroll();
    }

    // Haptic when crossing the exit-ready threshold
    if (previousScale >= 0.70 && scale < 0.70 && !_zoomOutExitTriggered) {
      HapticFeedback.mediumImpact();
    }

    // Zoom-out-to-exit: when scale drops below 0.65, go back to canvas
    if (scale < 0.65 && !_zoomOutExitTriggered) {
      _zoomOutExitTriggered = true;
      HapticFeedback.heavyImpact();
      widget.onClose?.call(_buildUpdatedModel());
      Navigator.of(context).pop();
    }
  }

  /// Detect swipe-down-to-dismiss from InteractiveViewer's own pan gestures.
  void _onInteractionUpdate(ScaleUpdateDetails details) {
    // Mark as actively interacting to suppress expensive work
    if (!_isInteracting) _isInteracting = true;

    if (_currentZoomScale > 1.05 || _isDrawingMode) return;

    // Only single-finger pan (not pinch-to-zoom)
    if (details.pointerCount > 1) return;

    // Check if document is at/above the top (positive Y = over-scrolled past top)
    final yTranslation = _zoomController.value.row1.w;
    if (yTranslation > 0 && details.focalPointDelta.dy > 0) {
      // Over-scrolled past top AND still pulling down → dismiss gesture
      setState(() {
        _isSwiping = true;
        _swipeDismissOffset = yTranslation * 0.5; // Damped offset for visual feedback
      });
    } else if (_isSwiping && yTranslation <= 0) {
      // Released back into content → cancel dismiss
      setState(() {
        _isSwiping = false;
        _swipeDismissOffset = 0;
      });
    }
  }

  /// Called when the pinch gesture ends — snap back or exit.
  void _onInteractionEnd(ScaleEndDetails details) {
    // End interaction mode — resume expensive work
    _isInteracting = false;
    final scale = _zoomController.value.getMaxScaleOnAxis();

    // Deferred: update page tracking and ensure renders
    _onScroll();
    _ensureVisiblePagesRendered();

    // Prefetch extra pages if zoomed out (more pages visible)
    if (scale < 0.9) {
      final total = widget.documentModel.totalPages;
      final extraBuffer = (1.0 / scale).ceil() + 1;
      for (int i = (_currentPageIndex - extraBuffer).clamp(0, total);
           i < (_currentPageIndex + extraBuffer + 1).clamp(0, total); i++) {
        if (_pageImages[i] == null) {
          _renderPage(i, widget.provider);
        }
      }
    }

    // Schedule hi-res re-render if zoomed in
    _scheduleHiResRender(scale);

    // Force a final setState with correct isZoomed/FilterQuality
    if (mounted) setState(() {});

    // ── Swipe-down-to-dismiss: check if dismiss threshold reached ──
    if (_isSwiping) {
      final velocity = details.velocity.pixelsPerSecond.dy;
      if (_swipeDismissOffset > 120 || velocity > 800) {
        HapticFeedback.mediumImpact();
        widget.onClose?.call(_buildUpdatedModel());
        Navigator.of(context).pop();
        return;
      } else {
        // Rubber-band snap back
        _swipeSnapController?.dispose();
        final startOffset = _swipeDismissOffset;
        final ctrl = AnimationController(
          duration: const Duration(milliseconds: 350), vsync: this,
        );
        _swipeSnapController = ctrl;
        final curved = CurvedAnimation(
          parent: ctrl,
          curve: const Cubic(0.34, 1.56, 0.64, 1.0),
        );
        curved.addListener(() {
          if (mounted) {
            setState(() {
              _swipeDismissOffset = startOffset * (1.0 - curved.value);
            });
          }
        });
        ctrl.addStatusListener((s) {
          if (s == AnimationStatus.completed && mounted) {
            setState(() {
              _swipeDismissOffset = 0;
              _isSwiping = false;
            });
          }
        });
        ctrl.forward();
        return;
      }
    }

    // Exit if released at low zoom
    if (scale < 0.75 && !_zoomOutExitTriggered) {
      _zoomOutExitTriggered = true;
      HapticFeedback.heavyImpact();
      widget.onClose?.call(_buildUpdatedModel());
      Navigator.of(context).pop();
      return;
    }

    // If zoomed out at all, snap back smoothly
    if (scale < 0.95 && !_zoomOutExitTriggered) {
      // Preserve current scroll offset, just reset scale
      final currentY = _zoomController.value.row1.w;
      // ignore: deprecated_member_use
      final target = Matrix4.identity()..translate(0.0, currentY);
      _animateZoomTo(target);
    }
  }

  // ---------------------------------------------------------------------------
  // Swipe down to dismiss
  // ---------------------------------------------------------------------------

  void _onSwipeDragUpdate(DragUpdateDetails d) {
    if (_currentZoomScale > 1.05 || _isDrawingMode) return;
    setState(() {
      _isSwiping = true;
      _swipeDismissOffset += d.delta.dy;
    });
  }

  void _onSwipeDragEnd(DragEndDetails d) {
    // No-op: dismiss logic now handled in _onInteractionEnd
  }

  /// Double-tap: toggle between 1x and 2.5x zoom centered on tap.
  void _onDoubleTapZoom(TapDownDetails details) {
    final currentScale = _zoomController.value.getMaxScaleOnAxis();

    if (currentScale > 1.5) {
      // Animate back to 1x, preserving scroll position
      final currentY = _zoomController.value.row1.w;
      // ignore: deprecated_member_use
      final target = Matrix4.identity()..translate(0.0, currentY);
      _animateZoomTo(target);
    } else {
      // Animate to 2.5x centered on tap position
      final position = details.localPosition;
      const targetScale = 2.5;
      // ignore: deprecated_member_use
      final matrix = Matrix4.identity()
        ..translate(position.dx, position.dy) // ignore: deprecated_member_use
        ..scale(targetScale) // ignore: deprecated_member_use
        ..translate(-position.dx, -position.dy); // ignore: deprecated_member_use
      _animateZoomTo(matrix);
    }
  }

  /// Smoothly animate the zoom transformation.
  void _animateZoomTo(Matrix4 target) {
    _zoomAnimController?.dispose();
    _zoomAnimStart = _zoomController.value.clone();
    _zoomAnimEnd = target;

    final controller = AnimationController(
      duration: const Duration(milliseconds: 200), // 🚀 Faster
      vsync: this,
    );
    _zoomAnimController = controller;

    final curve = CurvedAnimation(
      parent: controller,
      curve: Curves.fastOutSlowIn, // 🚀 Smoother deceleration
    );

    curve.addListener(() {
      if (!mounted) return;
      final t = curve.value;
      // Lerp each element of the 4x4 matrix
      final start = _zoomAnimStart!;
      final end = _zoomAnimEnd!;
      final result = Matrix4.zero();
      for (int i = 0; i < 16; i++) {
        result.storage[i] = start.storage[i] + (end.storage[i] - start.storage[i]) * t;
      }
      _zoomController.value = result;
    });

    curve.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        controller.dispose();
        if (_zoomAnimController == controller) {
          _zoomAnimController = null;
        }
        // Schedule hi-res after programmatic zoom settles
        _scheduleHiResRender(_zoomController.value.getMaxScaleOnAxis());
      }
    });

    controller.forward();
  }

  /// Schedule hi-res re-render when zoom settles above 1.5x.
  void _scheduleHiResRender(double scale) {
    _hiResDebounce?.cancel();
    if (scale > 1.5) {
      _hiResDebounce = Timer(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        // Re-render current page at higher resolution
        final hiResScale = (scale / 1.5).clamp(1.0, 2.5);
        _renderPage(_currentPageIndex, widget.provider, renderScale: hiResScale);
        // Also render adjacent pages
        if (_currentPageIndex > 0) {
          _renderPage(_currentPageIndex - 1, widget.provider, renderScale: hiResScale);
        }
        if (_currentPageIndex < widget.documentModel.totalPages - 1) {
          _renderPage(_currentPageIndex + 1, widget.provider, renderScale: hiResScale);
        }
      });
    }
  }

  void _scrollToPage(int pageIndex) {
    double offset = 16; // top padding
    for (int i = 0; i < pageIndex; i++) {
      offset += _getPageDisplayHeight(i) + 16.0;
    }
    // ignore: deprecated_member_use
    final target = Matrix4.identity()..translate(0.0, -offset);
    _animateZoomTo(target);
  }
}
