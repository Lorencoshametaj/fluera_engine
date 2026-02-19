part of 'pen_tool.dart';

// ============================================================================
// POINTER EVENTS + KEYBOARD
// ============================================================================

extension _PenToolInput on PenTool {
  // ── POINTER EVENTS ──

  void handlePointerDown(ToolContext context, PointerDownEvent event) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final isDoubleTap = (now - _lastPointerDownMs) < PenTool._doubleTapMs;
    _lastPointerDownMs = now;

    // Double-tap → finalize as open path.
    if (isDoubleTap && _anchors.length >= 2) {
      _finalizePath(context, closed: false);
      return;
    }

    beginOperation(context, event.localPosition);
    _isDragging = false;
    _dragHandleCanvas = null;
    _previewAnchor = null;
    _editingAnchorIndex = -1;

    final canvasPos = context.screenToCanvas(event.localPosition);
    _cursorCanvasPosition = canvasPos;

    // Check if tapping near the first anchor to close the path.
    if (_anchors.length >= 3) {
      final firstScreenPos = context.canvasToScreen(_anchors.first.position);
      final tapScreenPos = event.localPosition;
      // Threshold scales inversely with zoom for consistent feel
      final threshold =
          PenTool._baseCloseThreshold / context.scale.clamp(0.1, 10.0);
      if ((firstScreenPos - tapScreenPos).distance <
          threshold * context.scale) {
        _finalizePath(context, closed: true);
        return;
      }
    }

    // #1: Check if tapping near a handle FIRST (higher priority than anchor).
    for (int i = 0; i < _anchors.length; i++) {
      final anchor = _anchors[i];
      // Check handleIn
      final hIn = anchor.handleInAbsolute;
      if (hIn != null) {
        final screenHIn = context.canvasToScreen(hIn);
        if ((screenHIn - event.localPosition).distance <
            PenTool._anchorHitRadius) {
          // Double-tap on handle → retract it.
          final now2 = DateTime.now().millisecondsSinceEpoch;
          if (_lastTappedHandleIndex == i &&
              _lastTappedHandleIsIn &&
              (now2 - _lastHandleTapMs) < PenTool._doubleTapMs) {
            anchor.handleIn = null;
            HapticFeedback.mediumImpact();
            _lastTappedHandleIndex = -1;
            state = ToolOperationState.idle;
            return;
          }
          _lastTappedHandleIndex = i;
          _lastTappedHandleIsIn = true;
          _lastHandleTapMs = now2;
          _editingAnchorIndex = i;
          _editTarget = _EditTarget.handleIn;
          return;
        }
      }
      // Check handleOut
      final hOut = anchor.handleOutAbsolute;
      if (hOut != null) {
        final screenHOut = context.canvasToScreen(hOut);
        if ((screenHOut - event.localPosition).distance <
            PenTool._anchorHitRadius) {
          // Double-tap on handle → retract it.
          final now2 = DateTime.now().millisecondsSinceEpoch;
          if (_lastTappedHandleIndex == i &&
              !_lastTappedHandleIsIn &&
              (now2 - _lastHandleTapMs) < PenTool._doubleTapMs) {
            anchor.handleOut = null;
            HapticFeedback.mediumImpact();
            _lastTappedHandleIndex = -1;
            state = ToolOperationState.idle;
            return;
          }
          _lastTappedHandleIndex = i;
          _lastTappedHandleIsIn = false;
          _lastHandleTapMs = now2;
          _editingAnchorIndex = i;
          _editTarget = _EditTarget.handleOut;
          return;
        }
      }
    }

    // Then check if tapping near an existing anchor (for editing/toggle).
    for (int i = 0; i < _anchors.length; i++) {
      final anchorScreenPos = context.canvasToScreen(_anchors[i].position);
      if ((anchorScreenPos - event.localPosition).distance <
          PenTool._anchorHitRadius) {
        // #2: Double-tap on anchor → delete it.
        final now2 = DateTime.now().millisecondsSinceEpoch;
        if (i == _lastTappedAnchorIndex &&
            (now2 - _lastAnchorTapMs) < PenTool._doubleTapMs) {
          _anchors.removeAt(i);
          // Update multi-selection indices after removal.
          _selectedAnchorIndices.remove(i);
          final adjusted =
              _selectedAnchorIndices
                  .map((idx) => idx > i ? idx - 1 : idx)
                  .toSet();
          _selectedAnchorIndices
            ..clear()
            ..addAll(adjusted);
          HapticFeedback.mediumImpact();
          _lastTappedAnchorIndex = -1;
          _lastAnchorTapMs = 0;
          state = ToolOperationState.idle;
          currentCanvasPosition = null;
          startCanvasPosition = null;
          lastScreenPosition = null;
          return;
        }
        _lastTappedAnchorIndex = i;
        _lastAnchorTapMs = now2;

        // Start long-press timer for multi-select.
        _pointerDownMs = now;
        _longPressPending = true;

        _editingAnchorIndex = i;
        _editTarget = _EditTarget.position;
        _isHandleBreakout = false;
        return;
      }
    }

    // A1: Check if tapping on a segment (insert anchor via De Casteljau).
    if (_anchors.length >= 2) {
      final result = _hitTestSegments(canvasPos, context);
      if (result != null) {
        final (segmentIndex, t) = result;
        _insertAnchorOnSegment(segmentIndex, t);
        HapticFeedback.mediumImpact();
        state = ToolOperationState.idle;
        currentCanvasPosition = null;
        startCanvasPosition = null;
        lastScreenPosition = null;
        return;
      }
    }

    // Tap on empty area clears multi-selection.
    if (_selectedAnchorIndices.isNotEmpty) {
      _selectedAnchorIndices.clear();
    }
  }

  void handlePointerMove(ToolContext context, PointerMoveEvent event) {
    if (state == ToolOperationState.idle) {
      // Not in an operation — track cursor for rubber-band and compute hint.
      _cursorCanvasPosition = context.screenToCanvas(event.localPosition);
      _computeCursorHint(context, event.localPosition);
      return;
    }

    continueOperation(context, event.localPosition);

    final canvasPos = context.screenToCanvas(event.localPosition);
    _cursorCanvasPosition = canvasPos;

    // Cancel long-press if user moves beyond dead zone.
    if (_longPressPending) {
      final dist =
          (event.localPosition - _screenPosFromCanvasStart(context)).distance;
      if (dist > PenTool._dragDeadZone) {
        _longPressPending = false;
      }
    }

    // #1: Editing anchor or handle — drag to reposition.
    if (_editingAnchorIndex >= 0) {
      final anchor = _anchors[_editingAnchorIndex];
      var snapped = _applySnapping(canvasPos);

      switch (_editTarget) {
        case _EditTarget.position:
          // Handle breakout: dragging from a corner anchor creates handles.
          if (anchor.type == AnchorType.corner &&
              anchor.handleIn == null &&
              anchor.handleOut == null) {
            final dist =
                (event.localPosition - _screenPosFromCanvasStart(context))
                    .distance;
            if (dist > PenTool._dragDeadZone) {
              _isHandleBreakout = true;
              _editTarget = _EditTarget.handleOut;
              // Apply constraint if needed.
              if (constrainAngles) {
                snapped = PenTool._constrainTo45(snapped, anchor.position);
              }
              final handleOffset = snapped - anchor.position;
              anchor.handleOut = handleOffset;
              anchor.handleIn = -handleOffset;
              anchor.type = AnchorType.symmetric;
              return;
            }
          }
          // A2: Batch move selected anchors.
          if (_selectedAnchorIndices.contains(_editingAnchorIndex) &&
              _selectedAnchorIndices.length > 1) {
            final delta = snapped - anchor.position;
            for (final idx in _selectedAnchorIndices) {
              _anchors[idx].position += delta;
            }
          } else {
            anchor.position = snapped;
          }
          break;
        case _EditTarget.handleOut:
          // #3: Constrain handle angles.
          if (constrainAngles) {
            snapped = PenTool._constrainTo45(snapped, anchor.position);
          }
          anchor.handleOut = snapped - anchor.position;
          // Alt+drag → independent handle movement (break symmetry).
          if (_altKeyDown) {
            // Don't mirror — leave handleIn as-is.
          } else if (anchor.type == AnchorType.symmetric) {
            anchor.handleIn = -(snapped - anchor.position);
          } else if (anchor.type == AnchorType.smooth &&
              anchor.handleIn != null) {
            // Smooth: keep colinear, preserve length.
            final len = anchor.handleIn!.distance;
            final dir = -(snapped - anchor.position);
            if (dir.distance > 0) {
              anchor.handleIn = dir / dir.distance * len;
            }
          }
          break;
        case _EditTarget.handleIn:
          // #3: Constrain handle angles.
          if (constrainAngles) {
            snapped = PenTool._constrainTo45(snapped, anchor.position);
          }
          anchor.handleIn = snapped - anchor.position;
          // Alt+drag → independent handle movement (break symmetry).
          if (_altKeyDown) {
            // Don't mirror — leave handleOut as-is.
          } else if (anchor.type == AnchorType.symmetric) {
            anchor.handleOut = -(snapped - anchor.position);
          } else if (anchor.type == AnchorType.smooth &&
              anchor.handleOut != null) {
            final len = anchor.handleOut!.distance;
            final dir = -(snapped - anchor.position);
            if (dir.distance > 0) {
              anchor.handleOut = dir / dir.distance * len;
            }
          }
          break;
      }
      return;
    }

    // Detect drag (beyond dead zone → user wants a curve handle).
    if (!_isDragging && startCanvasPosition != null) {
      if ((event.localPosition - _screenPosFromCanvasStart(context)).distance >
          PenTool._dragDeadZone) {
        _isDragging = true;
      }
    }

    if (_isDragging) {
      // #3: Constrain drag handle angles.
      if (constrainAngles && startCanvasPosition != null) {
        _dragHandleCanvas = PenTool._constrainTo45(
          canvasPos,
          startCanvasPosition!,
        );
      } else {
        _dragHandleCanvas = canvasPos;
      }

      // Build live preview anchor showing the actual curve shape.
      if (startCanvasPosition != null) {
        final anchorPos = _applySnapping(startCanvasPosition!);
        final handleOut = (_dragHandleCanvas ?? canvasPos) - anchorPos;
        final handleIn = -handleOut;
        _previewAnchor = AnchorPoint(
          position: anchorPos,
          handleIn: _anchors.isEmpty ? null : handleIn,
          handleOut: handleOut,
          type: AnchorType.symmetric,
        );
      }
    } else {
      _previewAnchor = null;
    }
  }

  void handlePointerUp(ToolContext context, PointerUpEvent event) {
    if (state == ToolOperationState.idle) return;

    final canvasPos = context.screenToCanvas(event.localPosition);

    // #1/#2: Editing an existing anchor or handle.
    if (_editingAnchorIndex >= 0) {
      final dist =
          (event.localPosition - _screenPosFromCanvasStart(context)).distance;
      final elapsed = DateTime.now().millisecondsSinceEpoch - _pointerDownMs;

      if (_editTarget == _EditTarget.position && dist < PenTool._dragDeadZone) {
        // A2: Long-press on anchor → show context menu.
        if (_longPressPending && elapsed >= PenTool._longPressMs) {
          _contextMenuAnchorIndex = _editingAnchorIndex;
          _showAnchorContextMenu = true;
          HapticFeedback.mediumImpact();
        } else {
          // #2: Tap without drag on anchor → cycle: corner→smooth→symmetric→corner.
          final anchor = _anchors[_editingAnchorIndex];
          cycleAnchorType(anchor, _editingAnchorIndex);
          HapticFeedback.selectionClick();
        }
      } else {
        // Was dragged — position/handle already updated in onPointerMove.
        HapticFeedback.lightImpact();
      }
      _longPressPending = false;
      _editingAnchorIndex = -1;
      _editTarget = _EditTarget.position;
      _isHandleBreakout = false;
      state = ToolOperationState.idle;
      currentCanvasPosition = null;
      startCanvasPosition = null;
      lastScreenPosition = null;
      return;
    }

    if (_isDragging && startCanvasPosition != null) {
      // Tap + drag → smooth anchor with symmetric handles.
      final rawAnchorPos = startCanvasPosition!;
      final anchorPos = _applySnapping(rawAnchorPos);
      final handleOut = canvasPos - anchorPos; // Relative offset.
      final handleIn = Offset(-handleOut.dx, -handleOut.dy); // Mirror.

      _anchors.add(
        AnchorPoint(
          position: anchorPos,
          handleIn: _anchors.isEmpty ? null : handleIn,
          handleOut: handleOut,
          type: AnchorType.symmetric,
        ),
      );
    } else {
      // Simple tap → corner anchor (straight line).
      final rawPos = startCanvasPosition ?? canvasPos;
      var snappedPos = _applySnapping(rawPos);

      // #3: Constrained angles — snap to 45° multiples.
      if (constrainAngles && _anchors.isNotEmpty) {
        snappedPos = PenTool._constrainTo45(snappedPos, _anchors.last.position);
      }

      _anchors.add(AnchorPoint(position: snappedPos, type: AnchorType.corner));
    }

    _isDragging = false;
    _dragHandleCanvas = null;
    _previewAnchor = null;
    _cursorCanvasPosition = canvasPos;

    // 📳 Haptic feedback on anchor placement
    HapticFeedback.lightImpact();

    // Reset operation state but keep anchors.
    state = ToolOperationState.idle;
    currentCanvasPosition = null;
    startCanvasPosition = null;
    lastScreenPosition = null;
  }

  void handlePointerCancel(ToolContext context) {
    _isDragging = false;
    _dragHandleCanvas = null;
    state = ToolOperationState.idle;
  }

  // ── KEYBOARD EVENTS ──

  /// Call this from the host widget's key handler.
  /// Returns true if the event was consumed.
  bool handleKeyboardEvent(KeyEvent event, ToolContext context) {
    // Track Alt key state for handle break.
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.altLeft ||
            event.logicalKey == LogicalKeyboardKey.altRight)) {
      _altKeyDown = true;
    }
    if (event is KeyUpEvent &&
        (event.logicalKey == LogicalKeyboardKey.altLeft ||
            event.logicalKey == LogicalKeyboardKey.altRight)) {
      _altKeyDown = false;
    }

    if (event is! KeyDownEvent) return false;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _reset();
      return true;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_anchors.length >= 2) {
        _finalizePath(context, closed: false);
        return true;
      }
    }

    // Backspace / Delete → remove selected anchors or last anchor.
    if (event.logicalKey == LogicalKeyboardKey.backspace ||
        event.logicalKey == LogicalKeyboardKey.delete) {
      if (_selectedAnchorIndices.isNotEmpty) {
        deleteAnchorsByIndex(Set<int>.from(_selectedAnchorIndices));
        HapticFeedback.mediumImpact();
        return true;
      } else if (_anchors.isNotEmpty) {
        _anchors.removeLast();
        return true;
      }
    }

    // 'S' key → cycle anchor type on editing or last-tapped anchor.
    if (event.logicalKey == LogicalKeyboardKey.keyS) {
      final targetIdx =
          _editingAnchorIndex >= 0
              ? _editingAnchorIndex
              : _lastTappedAnchorIndex;
      if (targetIdx >= 0 && targetIdx < _anchors.length) {
        cycleAnchorType(_anchors[targetIdx], targetIdx);
        HapticFeedback.selectionClick();
        return true;
      }
    }

    // 'R' key → reverse path direction.
    if (event.logicalKey == LogicalKeyboardKey.keyR) {
      if (_anchors.length >= 2) {
        reversePath();
        HapticFeedback.selectionClick();
        return true;
      }
    }

    // 'A' key → auto-smooth all anchors.
    if (event.logicalKey == LogicalKeyboardKey.keyA) {
      if (_anchors.length >= 2) {
        autoSmoothPath();
        HapticFeedback.mediumImpact();
        return true;
      }
    }

    return false;
  }

  // ── CURSOR HINT COMPUTATION ──

  /// Compute cursor hint based on what the cursor is hovering over.
  void _computeCursorHint(ToolContext context, Offset screenPos) {
    if (_anchors.isEmpty) {
      _cursorHint = PenCursorHint.addPoint;
      return;
    }

    // Check close indicator first (near first anchor with ≥3 points).
    if (_anchors.length >= 3) {
      final firstScreenPos = context.canvasToScreen(_anchors.first.position);
      final threshold =
          PenTool._baseCloseThreshold / context.scale.clamp(0.1, 10.0);
      if ((firstScreenPos - screenPos).distance < threshold * context.scale) {
        _cursorHint = PenCursorHint.closePath;
        return;
      }
    }

    // Check anchors.
    for (int i = 0; i < _anchors.length; i++) {
      final anchorScreenPos = context.canvasToScreen(_anchors[i].position);
      if ((anchorScreenPos - screenPos).distance < PenTool._anchorHitRadius) {
        _cursorHint = PenCursorHint.editAnchor;
        return;
      }
    }

    // Check segments.
    if (_anchors.length >= 2) {
      final canvasPos = context.screenToCanvas(screenPos);
      final result = _hitTestSegments(canvasPos, context);
      if (result != null) {
        _cursorHint = PenCursorHint.addOnSegment;
        return;
      }
    }

    _cursorHint = PenCursorHint.addPoint;
  }
}
