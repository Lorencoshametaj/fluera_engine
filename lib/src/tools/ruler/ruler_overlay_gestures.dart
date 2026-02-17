part of 'ruler_interactive_overlay.dart';

/// Gesture handlers for the ruler interactive overlay.
///
/// Handles single-guide drag, multi-select drag,
/// ruler long-press, and measurement gestures.

extension _RulerOverlayGestures on _RulerInteractiveOverlayState {
  // ─── Single Guide Drag ─────────────────────────────────────────

  void onGrab(int index, bool isH) {
    HapticFeedback.selectionClick();

    if (widget.guideSystem.multiSelectMode) {
      setState(() => widget.guideSystem.toggleSelection(isH, index));
      widget.onChanged();
      return;
    }

    if (HardwareKeyboard.instance.isAltPressed) {
      widget.guideSystem.duplicateGuide(isH, index);
      final newIndex =
          isH
              ? widget.guideSystem.horizontalGuides.length - 1
              : widget.guideSystem.verticalGuides.length - 1;
      setState(() {
        _isDragging = true;
        _isHorizontalGuide = isH;
        _dragGuideIndex = newIndex;
      });
      widget.onChanged();
      return;
    }

    setState(() {
      _isDragging = true;
      _isHorizontalGuide = isH;
      _dragGuideIndex = index;
    });
  }

  void onRulerDragStart(DragStartDetails details, bool fromH) {
    HapticFeedback.lightImpact();
    final s = widget.canvasController.scale;
    final o = widget.canvasController.offset;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final gp = box.globalToLocal(details.globalPosition);
    final gs = widget.guideSystem;

    gs.saveSnapshot();
    if (fromH) {
      gs.addHorizontalGuide((gp.dy - o.dy) / s);
      setState(() {
        _isDragging = true;
        _isHorizontalGuide = true;
        _dragGuideIndex = gs.horizontalGuides.length - 1;
      });
    } else {
      gs.addVerticalGuide((gp.dx - o.dx) / s);
      setState(() {
        _isDragging = true;
        _isHorizontalGuide = false;
        _dragGuideIndex = gs.verticalGuides.length - 1;
      });
    }
    widget.onChanged();
  }

  void onDragUpdate(DragUpdateDetails details) {
    if (!_isDragging || _dragGuideIndex == null) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.globalToLocal(details.globalPosition);
    final s = widget.canvasController.scale;
    final o = widget.canvasController.offset;
    final gs = widget.guideSystem;

    setState(() {
      if (_isHorizontalGuide) {
        final raw = (pos.dy - o.dy) / s;
        var snapped = gs.snapGuideValue(raw, s);
        snapped = gs.snapGuideToNearestGuide(
          snapped,
          true,
          _dragGuideIndex!,
          s,
        );
        if (_dragGuideIndex! < gs.horizontalGuides.length) {
          gs.horizontalGuides[_dragGuideIndex!] = snapped;
        }
      } else {
        final raw = (pos.dx - o.dx) / s;
        var snapped = gs.snapGuideValue(raw, s);
        snapped = gs.snapGuideToNearestGuide(
          snapped,
          false,
          _dragGuideIndex!,
          s,
        );
        if (_dragGuideIndex! < gs.verticalGuides.length) {
          gs.verticalGuides[_dragGuideIndex!] = snapped;
        }
      }
    });
    widget.onChanged();
  }

  void onDragEnd() {
    if (_isDragging && _dragGuideIndex != null) {
      final s = widget.canvasController.scale;
      final o = widget.canvasController.offset;
      final gs = widget.guideSystem;

      if (_isHorizontalGuide && _dragGuideIndex! < gs.horizontalGuides.length) {
        final sy = gs.horizontalGuides[_dragGuideIndex!] * s + o.dy;
        if (sy < _RulerInteractiveOverlayState.rulerSize + 10) {
          gs.removeHorizontalGuideAt(_dragGuideIndex!);
          HapticFeedback.heavyImpact();
        } else {
          HapticFeedback.mediumImpact();
        }
      } else if (!_isHorizontalGuide &&
          _dragGuideIndex! < gs.verticalGuides.length) {
        final sx = gs.verticalGuides[_dragGuideIndex!] * s + o.dx;
        if (sx < _RulerInteractiveOverlayState.rulerSize + 10) {
          gs.removeVerticalGuideAt(_dragGuideIndex!);
          HapticFeedback.heavyImpact();
        } else {
          HapticFeedback.mediumImpact();
        }
      }
    }
    setState(() {
      _isDragging = false;
      _dragGuideIndex = null;
    });
    widget.onChanged();
  }

  // ─── Multi-select Drag ─────────────────────────────────────────

  void onMultiDragStart(DragStartDetails details) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    _isDraggingSelected = true;
    _multiDragStart = box.globalToLocal(details.globalPosition);
  }

  void onMultiDragUpdate(DragUpdateDetails details) {
    if (!_isDraggingSelected || _multiDragStart == null) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final cur = box.globalToLocal(details.globalPosition);
    final s = widget.canvasController.scale;
    final delta = (cur - _multiDragStart!) / s;

    widget.guideSystem.moveSelectedGuides(delta.dx, delta.dy);
    _multiDragStart = cur;
    widget.onChanged();
    setState(() {});
  }

  void onMultiDragEnd() {
    _isDraggingSelected = false;
    _multiDragStart = null;
    HapticFeedback.mediumImpact();
  }

  // ─── Long-press Ruler ──────────────────────────────────────────

  void onRulerLongPress(LongPressStartDetails details, bool fromH) {
    HapticFeedback.mediumImpact();
    final s = widget.canvasController.scale;
    final o = widget.canvasController.offset;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.globalToLocal(details.globalPosition);
    final gs = widget.guideSystem;

    if (fromH) {
      gs.addHorizontalGuide(gs.snapGuideValue((pos.dy - o.dy) / s, s));
    } else {
      gs.addVerticalGuide(gs.snapGuideValue((pos.dx - o.dx) / s, s));
    }
    widget.onChanged();
    setState(() {});
  }

  // ─── Measurement ───────────────────────────────────────────────

  void onMeasureStart(DragStartDetails d) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.globalToLocal(d.globalPosition);
    final s = widget.canvasController.scale;
    final o = widget.canvasController.offset;
    final cp = Offset((pos.dx - o.dx) / s, (pos.dy - o.dy) / s);
    setState(() {
      widget.guideSystem.measureStart = cp;
      widget.guideSystem.measureEnd = cp;
    });
    widget.onChanged();
  }

  void onMeasureUpdate(DragUpdateDetails d) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.globalToLocal(d.globalPosition);
    final s = widget.canvasController.scale;
    final o = widget.canvasController.offset;
    setState(() {
      widget.guideSystem.measureEnd = Offset(
        (pos.dx - o.dx) / s,
        (pos.dy - o.dy) / s,
      );
    });
    widget.onChanged();
  }

  void onMeasureEnd() {
    widget.onChanged();
    if (mounted) setState(() {});
  }
}
