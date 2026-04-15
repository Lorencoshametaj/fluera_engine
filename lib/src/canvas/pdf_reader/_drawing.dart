part of 'pdf_reader_screen.dart';

/// Drawing, eraser, and shape input handling for PDF annotation.
extension _PdfDrawingMethods on _PdfReaderScreenState {

  void _onPointerDown(PointerDownEvent event, int pageIndex, Size pageDisplaySize) {
    if (!_isDrawingMode) return;

    _activePointerCount++;

    // If a second finger touches, cancel the live stroke and let
    // InteractiveViewer handle the 2-finger pan/zoom gesture.
    if (_activePointerCount > 1) {
      if (_livePoints != null || _shapeStartPos != null) {
        setState(() {
          _livePoints = null;
          _livePageIndex = null;
          _activePointerId = null;
          _shapeStartPos = null;
          _shapeEndPos = null;
          _shapePageIndex = null;
        });
        _liveScreenPoints.clear();
        if (_vulkanActive) _vulkanOverlay.clear();
      }
      return;
    }

    // Only the first finger draws
    _activePointerId = event.pointer;

    final page = widget.documentModel.pages[pageIndex];
    // Transform screen position to PDF-page coordinates
    final scaleX = page.originalSize.width / pageDisplaySize.width;
    final scaleY = page.originalSize.height / pageDisplaySize.height;

    final pos = Offset(
      event.localPosition.dx * scaleX,
      event.localPosition.dy * scaleY,
    );

    if (_isErasing) {
      _eraseAtPoint(pageIndex, pos, page.originalSize);
      return;
    }

    // Shape drawing mode — record start position
    if (_selectedShapeType != ShapeType.freehand) {
      setState(() {
        _shapeStartPos = pos;
        _shapeEndPos = pos;
        _shapePageIndex = pageIndex;
      });
      return;
    }

    setState(() {
      _livePageIndex = pageIndex;
      _livePoints = [
        ProDrawingPoint(
          position: pos,
          pressure: event.pressure > 0 ? event.pressure : 0.5,
          tiltX: event.tilt,
          timestamp: event.timeStamp.inMilliseconds,
        ),
      ];
    });

    // Cache SafeArea top padding once per stroke (avoid hot-path MediaQuery).
    _safeAreaTopCache = MediaQuery.of(context).padding.top;

    // Track screen-space position for Vulkan.
    // Subtract SafeArea top padding because the Texture widget is inside
    // SafeArea but event.position is in global screen coordinates.
    _liveScreenPoints.clear();
    _liveScreenPoints.add(ProDrawingPoint(
      position: Offset(event.position.dx, event.position.dy - _safeAreaTopCache),
      pressure: event.pressure > 0 ? event.pressure : 0.5,
      tiltX: event.tilt,
      timestamp: event.timeStamp.inMilliseconds,
    ));
  }

  void _onPointerMove(PointerMoveEvent event, int pageIndex, Size pageDisplaySize) {
    if (!_isDrawingMode) return;
    // Only track the drawing pointer — ignore 2nd finger moves
    if (event.pointer != _activePointerId) return;

    final page = widget.documentModel.pages[pageIndex];
    final scaleX = page.originalSize.width / pageDisplaySize.width;
    final scaleY = page.originalSize.height / pageDisplaySize.height;

    final pos = Offset(
      event.localPosition.dx * scaleX,
      event.localPosition.dy * scaleY,
    );

    if (_isErasing) {
      _eraseAtPoint(pageIndex, pos, page.originalSize);
      return;
    }

    // Shape drawing mode — update end position
    if (_selectedShapeType != ShapeType.freehand && _shapeStartPos != null) {
      setState(() => _shapeEndPos = pos);
      _annotationRepaint.value++;
      return;
    }

    if (_livePoints != null && _livePageIndex == pageIndex) {
      _livePoints!.add(ProDrawingPoint(
        position: pos,
        pressure: event.pressure > 0 ? event.pressure : 0.5,
        tiltX: event.tilt,
        timestamp: event.timeStamp.inMilliseconds,
      ));

      // Track screen-space position for Vulkan
      _liveScreenPoints.add(ProDrawingPoint(
        position: Offset(event.position.dx, event.position.dy - _safeAreaTopCache),
        pressure: event.pressure > 0 ? event.pressure : 0.5,
        tiltX: event.tilt,
        timestamp: event.timeStamp.inMilliseconds,
      ));

      // Forward to Vulkan GPU for real-time rendering.
      if (_vulkanActive && _liveScreenPoints.length >= 2) {
        _vulkanOverlay.updateAndRender(
          _liveScreenPoints,
          _penColor,
          _penWidth,
          brushType: _penType == ProPenType.pencil ? 2
              : _penType == ProPenType.fountain ? 4
              : 0,
        );
      }

      // 🚀 PERF: Bump notifier instead of setState — only repaints
      // the annotation overlay CustomPaint, not the entire widget tree.
      _annotationRepaint.value++;
    }
  }

  void _onPointerUp(PointerUpEvent event, int pageIndex, Size pageDisplaySize) {
    _activePointerCount = (_activePointerCount - 1).clamp(0, 10);
    if (!_isDrawingMode || _isErasing) return;
    // Only commit from the drawing pointer
    if (event.pointer != _activePointerId) return;
    _activePointerId = null;

    // Shape commit — generate shape points from start/end
    if (_selectedShapeType != ShapeType.freehand &&
        _shapeStartPos != null && _shapeEndPos != null &&
        _shapePageIndex == pageIndex) {
      final shapePoints = _generateShapePoints(_shapeStartPos!, _shapeEndPos!, _selectedShapeType);
      if (shapePoints.length >= 2) {
        final effectiveColor = _penColor.withValues(alpha: _penOpacity);
        final page = widget.documentModel.pages[pageIndex];
        final widthScale = page.originalSize.width / pageDisplaySize.width;
        final stroke = ProStroke(
          id: 'pdf_${widget.documentId}_p${pageIndex}_${DateTime.now().millisecondsSinceEpoch}',
          points: shapePoints,
          color: effectiveColor,
          baseWidth: _penWidth * widthScale,
          penType: _penType,
          settings: _brushSettings,
          createdAt: DateTime.now(),
        );
        setState(() {
          final existing = _pageStrokes[pageIndex] ?? const [];
          _pageStrokes[pageIndex] = [...existing, stroke];
          _shapeStartPos = null;
          _shapeEndPos = null;
          _shapePageIndex = null;
        });
        HapticFeedback.lightImpact();

      } else {
        setState(() {
          _shapeStartPos = null;
          _shapeEndPos = null;
          _shapePageIndex = null;
        });
      }
      return;
    }

    if (_livePoints != null && _livePoints!.length >= 2 && _livePageIndex == pageIndex) {
      // Commit stroke — apply opacity to color alpha
      final effectiveColor = _penColor.withValues(alpha: _penOpacity);
      final page = widget.documentModel.pages[pageIndex];
      final widthScale = page.originalSize.width / pageDisplaySize.width;
      final stroke = ProStroke(
        id: 'pdf_${widget.documentId}_p${pageIndex}_${DateTime.now().millisecondsSinceEpoch}',
        points: List.from(_livePoints!),
        color: effectiveColor,
        baseWidth: _penWidth * widthScale,
        penType: _penType,
        settings: _brushSettings,
        createdAt: DateTime.now(),
      );

      setState(() {
        // 🐛 FIX: Create a NEW list instead of mutating in-place.
        final existing = _pageStrokes[pageIndex] ?? const [];
        _pageStrokes[pageIndex] = [...existing, stroke];
        _livePoints = null;
        _livePageIndex = null;
      });

      // Clear Vulkan live stroke overlay and screen-space points
      _liveScreenPoints.clear();
      if (_vulkanActive) _vulkanOverlay.clear();
      HapticFeedback.lightImpact();

    } else {
      _liveScreenPoints.clear();
      if (_vulkanActive) _vulkanOverlay.clear();
      setState(() {
        _livePoints = null;
        _livePageIndex = null;
      });
    }
  }

  /// Generate shape points from drag start/end positions.
  List<ProDrawingPoint> _generateShapePoints(Offset start, Offset end, ShapeType type) {
    List<Offset> pts;
    switch (type) {
      case ShapeType.freehand:
        return [];
      case ShapeType.line:
        pts = [start, end];
        break;
      case ShapeType.rectangle:
        pts = [
          start,
          Offset(end.dx, start.dy),
          end,
          Offset(start.dx, end.dy),
          start, // Close
        ];
        break;
      case ShapeType.circle:
        final center = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
        final rx = (end.dx - start.dx).abs() / 2;
        final ry = (end.dy - start.dy).abs() / 2;
        const segments = 36;
        pts = List.generate(segments + 1, (i) {
          final angle = 2 * math.pi * i / segments;
          return Offset(
            center.dx + rx * math.cos(angle),
            center.dy + ry * math.sin(angle),
          );
        });
        break;
      case ShapeType.triangle:
        final midX = (start.dx + end.dx) / 2;
        pts = [
          Offset(midX, start.dy),
          Offset(end.dx, end.dy),
          Offset(start.dx, end.dy),
          Offset(midX, start.dy), // Close
        ];
        break;
      case ShapeType.arrow:
        final dx = end.dx - start.dx;
        final dy = end.dy - start.dy;
        final len = math.sqrt(dx * dx + dy * dy);
        if (len < 1) return [];
        final nx = dx / len;
        final ny = dy / len;
        final headLen = len * 0.2;
        final headW = headLen * 0.6;
        final arrowBase = Offset(end.dx - nx * headLen, end.dy - ny * headLen);
        pts = [
          start,
          arrowBase,
          Offset(arrowBase.dx - ny * headW, arrowBase.dy + nx * headW),
          end,
          Offset(arrowBase.dx + ny * headW, arrowBase.dy - nx * headW),
          arrowBase,
        ];
        break;
      case ShapeType.star:
        final center = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
        final rx = (end.dx - start.dx).abs() / 2;
        final ry = (end.dy - start.dy).abs() / 2;
        pts = [];
        for (int i = 0; i <= 10; i++) {
          final angle = math.pi / 2 + (2 * math.pi * i / 10);
          final r = i.isEven ? 1.0 : 0.4;
          pts.add(Offset(center.dx + rx * r * math.cos(angle), center.dy - ry * r * math.sin(angle)));
        }
        break;
      case ShapeType.heart:
        final center = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
        final w = (end.dx - start.dx).abs() / 2;
        final h = (end.dy - start.dy).abs() / 2;
        pts = List.generate(37, (i) {
          final t = 2 * math.pi * i / 36;
          return Offset(
            center.dx + w * 16 * math.pow(math.sin(t), 3) / 16,
            center.dy - h * (13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)) / 16,
          );
        });
        break;
      case ShapeType.diamond:
        final cx = (start.dx + end.dx) / 2;
        final cy = (start.dy + end.dy) / 2;
        pts = [
          Offset(cx, start.dy),
          Offset(end.dx, cy),
          Offset(cx, end.dy),
          Offset(start.dx, cy),
          Offset(cx, start.dy),
        ];
        break;
      case ShapeType.pentagon:
        final center = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
        final rx = (end.dx - start.dx).abs() / 2;
        final ry = (end.dy - start.dy).abs() / 2;
        pts = List.generate(6, (i) {
          final angle = -math.pi / 2 + 2 * math.pi * i / 5;
          return Offset(center.dx + rx * math.cos(angle), center.dy + ry * math.sin(angle));
        });
        break;
      case ShapeType.hexagon:
        final center = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
        final rx = (end.dx - start.dx).abs() / 2;
        final ry = (end.dy - start.dy).abs() / 2;
        pts = List.generate(7, (i) {
          final angle = 2 * math.pi * i / 6;
          return Offset(center.dx + rx * math.cos(angle), center.dy + ry * math.sin(angle));
        });
        break;
    }
    return pts.map((p) => ProDrawingPoint(position: p, pressure: 0.5)).toList();
  }

  void _eraseAtPoint(int pageIndex, Offset pos, Size pageSize) {
    final strokes = _pageStrokes[pageIndex];
    if (strokes == null || strokes.isEmpty) return;

    final eraserRadius = _penWidth * 5;
    final eraserRect = Rect.fromCircle(center: pos, radius: eraserRadius);

    final toRemove = <int>[];
    for (int i = 0; i < strokes.length; i++) {
      if (strokes[i].bounds.overlaps(eraserRect)) {
        toRemove.add(i);
      }
    }

    if (toRemove.isNotEmpty) {
      setState(() {
        // Create new list excluding erased strokes (avoid in-place mutation)
        final updated = <ProStroke>[
          for (int i = 0; i < strokes.length; i++)
            if (!toRemove.contains(i)) strokes[i],
        ];
        _pageStrokes[pageIndex] = updated;
      });
      HapticFeedback.selectionClick();
    }
  }

  void _undoLastStroke() {
    final strokes = _pageStrokes[_currentPageIndex];
    if (strokes != null && strokes.isNotEmpty) {
      // Create new list without last stroke (avoid in-place mutation)
      _pageStrokes[_currentPageIndex] = strokes.sublist(0, strokes.length - 1);
      setState(() {});
      HapticFeedback.lightImpact();
    }
  }

  // ---------------------------------------------------------------------------
  // Viewport culling helper
  // ---------------------------------------------------------------------------

  /// Compute the visible viewport rect in page-coordinate space.
  /// Used by _AnnotationOverlayPainter for stroke culling.
  Rect? _computeVisibleRect(int pageIndex, Size displaySize, Size originalSize) {
    final scale = _zoomController.value.getMaxScaleOnAxis();
    if (scale <= 1.05) return null; // Not zoomed, render all

    final screenSize = MediaQuery.of(context).size;
    final xOffset = -_zoomController.value.row0.w;
    final yOffset = -_zoomController.value.row1.w;

    // Compute page Y offset in the scroll layout
    double pageTop = 0;
    for (int i = 0; i < pageIndex; i++) {
      pageTop += _getPageDisplayHeight(i);
    }

    // Viewport in scroll-layout coordinates
    final viewLeft = xOffset / scale;
    final viewTop = yOffset / scale;
    final viewWidth = screenSize.width / scale;
    final viewHeight = screenSize.height / scale;

    // Convert to page-local coordinates
    final localLeft = viewLeft;
    final localTop = viewTop - pageTop;

    // Scale from display coords to original PDF coords
    final sx = originalSize.width / displaySize.width;
    final sy = originalSize.height / displaySize.height;

    return Rect.fromLTWH(
      localLeft * sx - 50, // padding for stroke width
      localTop * sy - 50,
      viewWidth * sx + 100,
      viewHeight * sy + 100,
    );
  }

  /// Lazily initialize Vulkan overlay when drawing mode is first activated.
  void _initVulkanIfNeeded() {
    if (_vulkanActive || _vulkanTextureId != null) return;
    _vulkanOverlay.isAvailable.then((available) {
      if (!available || !mounted) return;
      final dpr = MediaQuery.of(context).devicePixelRatio;
      final size = MediaQuery.of(context).size;
      final padding = MediaQuery.of(context).padding;
      // Size the texture to the SafeArea content area, NOT full screen.
      // If the texture is oversized, Flutter scales it to fit the Texture
      // widget bounds, causing vertical/horizontal shifts.
      final safeHeight = size.height - padding.top - padding.bottom;
      final pw = (size.width * dpr).toInt();
      final ph = (safeHeight * dpr).toInt();
      _vulkanOverlay.init(pw, ph).then((id) {
        if (id != null && mounted) {
          _vulkanOverlay.setScreenSpaceTransform(pw, ph, dpr);
          setState(() {
            _vulkanTextureId = id;
            _vulkanActive = true;
          });
        }
      });
    });
  }
}
