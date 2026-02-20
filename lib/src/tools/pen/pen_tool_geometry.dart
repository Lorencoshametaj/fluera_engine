part of 'pen_tool.dart';

// ============================================================================
// PATH MATH, SNAPPING & GEOMETRY HELPERS
// ============================================================================

extension _PenToolGeometry on PenTool {
  /// Finalize the path: convert anchors → VectorPath → PathNode.
  void finalizePath(ToolContext context, {required bool closed}) {
    if (_anchors.length < 2) {
      resetState();
      return;
    }

    context.saveUndoState();

    final vectorPath = AnchorPoint.toVectorPath(_anchors, closed: closed);

    final pathNode = PathNode(
      id: NodeId(_isEditingExisting ? _editingNodeId! : generateUid()),
      path: vectorPath,
      name: 'Path',
      fillColor: fillColor,
      fillGradient: fillGradient,
      strokeColor: strokeColor,
      strokeWidth: strokeWidth,
      strokeCap: strokeCap,
      strokeJoin: strokeJoin,
    );

    if (_isEditingExisting && _editingNodeId != null) {
      onPathNodeEdited?.call(_editingNodeId!, pathNode);
    } else {
      onPathNodeCreated?.call(pathNode);
    }

    // 📳 Haptic feedback on path finalization
    HapticFeedback.mediumImpact();

    context.notifyOperationComplete();
    resetState();
  }

  /// Reset all in-progress state.
  void resetState() {
    _anchors.clear();
    _cursorCanvasPosition = null;
    _dragHandleCanvas = null;
    _previewAnchor = null;
    _isDragging = false;
    _editingAnchorIndex = -1;
    _editTarget = _EditTarget.position;
    _isHandleBreakout = false;
    _lastTappedAnchorIndex = -1;
    _lastAnchorTapMs = 0;
    _selectedAnchorIndices.clear();
    _longPressPending = false;
    _lastTappedHandleIndex = -1;
    _lastTappedHandleIsIn = false;
    _lastHandleTapMs = 0;
    _altKeyDown = false;
    _isEditingExisting = false;
    _editingNodeId = null;
    _showAnchorContextMenu = false;
    _contextMenuAnchorIndex = -1;
    _showSegmentContextMenu = false;
    _contextMenuSegmentIndex = -1;
    _cursorHint = PenCursorHint.none;
    state = ToolOperationState.idle;
  }

  /// Convert an AnchorPoint from canvas coordinates to screen coordinates.
  AnchorPoint anchorToScreen(AnchorPoint anchor, ToolContext context) {
    final screenPos = context.canvasToScreen(anchor.position);

    Offset? screenHandleIn;
    if (anchor.handleIn != null) {
      final absIn = anchor.position + anchor.handleIn!;
      final screenAbsIn = context.canvasToScreen(absIn);
      screenHandleIn = screenAbsIn - screenPos;
    }

    Offset? screenHandleOut;
    if (anchor.handleOut != null) {
      final absOut = anchor.position + anchor.handleOut!;
      final screenAbsOut = context.canvasToScreen(absOut);
      screenHandleOut = screenAbsOut - screenPos;
    }

    return AnchorPoint(
      position: screenPos,
      handleIn: screenHandleIn,
      handleOut: screenHandleOut,
      type: anchor.type,
    );
  }

  /// Get the screen position of startCanvasPosition.
  Offset screenPosFromCanvasStart(ToolContext context) {
    return startCanvasPosition != null
        ? context.canvasToScreen(startCanvasPosition!)
        : Offset.zero;
  }

  /// #3: Constrain [pos] to the nearest 45° angle relative to [ref].
  Offset constrainTo45(Offset pos, Offset ref) {
    final delta = pos - ref;
    final distance = delta.distance;
    if (distance < 1.0) return pos;

    // Snap angle to nearest 45° (0, 45, 90, 135, 180, 225, 270, 315).
    final angle = delta.direction; // radians, -pi to pi
    const step = 3.14159265358979 / 4; // 45°
    final snapped = (angle / step).round() * step;

    return ref + Offset.fromDirection(snapped, distance);
  }

  // ── SEGMENT HIT-TEST & INSERTION ──

  /// Hit-test all segments to find if [canvasPos] is near a curve.
  /// Returns `(segmentIndex, t)` or null.
  (int, double)? hitTestSegments(Offset canvasPos, ToolContext context) {
    const int samples = 20;
    double bestDist = double.infinity;
    int bestSeg = -1;
    double bestT = 0;

    for (int i = 0; i < _anchors.length - 1; i++) {
      final a = _anchors[i];
      final b = _anchors[i + 1];

      final p0 = a.position;
      final p1 = a.handleOutAbsolute ?? p0;
      final p2 = b.handleInAbsolute ?? b.position;
      final p3 = b.position;

      for (int s = 0; s <= samples; s++) {
        final t = s / samples;
        final pt = cubicAt(t, p0, p1, p2, p3);
        final screenPt = context.canvasToScreen(pt);
        final screenTap = context.canvasToScreen(canvasPos);
        final dist = (screenPt - screenTap).distance;
        if (dist < bestDist) {
          bestDist = dist;
          bestSeg = i;
          bestT = t;
        }
      }
    }

    if (bestDist < PenTool._anchorHitRadius && bestSeg >= 0) {
      return (bestSeg, bestT);
    }
    return null;
  }

  /// Insert a new anchor on segment [segIndex] at parameter [t]
  /// using De Casteljau subdivision.
  void insertAnchorOnSegment(int segIndex, double t) {
    final a = _anchors[segIndex];
    final b = _anchors[segIndex + 1];

    final p0 = a.position;
    final p1 = a.handleOutAbsolute ?? p0;
    final p2 = b.handleInAbsolute ?? b.position;
    final p3 = b.position;

    // De Casteljau split at t.
    final q0 = lerpOffset(p0, p1, t);
    final q1 = lerpOffset(p1, p2, t);
    final q2 = lerpOffset(p2, p3, t);
    final r0 = lerpOffset(q0, q1, t);
    final r1 = lerpOffset(q1, q2, t);
    final s0 = lerpOffset(r0, r1, t); // point on curve

    // Update anchor A: new handleOut = q0 - p0
    a.handleOut = q0 - p0;

    // Update anchor B: new handleIn = q2 - p3
    b.handleIn = q2 - p3;

    // Create new anchor at s0 with handles r0 and r1.
    final newAnchor = AnchorPoint(
      position: s0,
      handleIn: r0 - s0,
      handleOut: r1 - s0,
      type: AnchorType.smooth,
    );

    _anchors.insert(segIndex + 1, newAnchor);

    // Adjust multi-selection indices.
    final adjusted =
        _selectedAnchorIndices
            .map((idx) => idx > segIndex ? idx + 1 : idx)
            .toSet();
    _selectedAnchorIndices
      ..clear()
      ..addAll(adjusted);
  }

  /// Cubic Bézier point at parameter [t].
  Offset cubicAt(double t, Offset p0, Offset p1, Offset p2, Offset p3) {
    final mt = 1.0 - t;
    return p0 * (mt * mt * mt) +
        p1 * (3 * mt * mt * t) +
        p2 * (3 * mt * t * t) +
        p3 * (t * t * t);
  }

  /// Linear interpolation between two offsets.
  Offset lerpOffset(Offset a, Offset b, double t) {
    return Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t);
  }

  // ── ANCHOR TYPE CYCLING ──

  /// Cycle anchor type: corner → smooth → symmetric → corner.
  ///
  /// - **corner → smooth**: Creates default handles from neighbor direction
  ///   (1/3 of the distance to each neighbor).
  /// - **smooth → symmetric**: Equalizes both handles to the longer length.
  /// - **symmetric → corner**: Removes both handles.
  void cycleAnchorType(AnchorPoint anchor, int index) {
    switch (anchor.type) {
      case AnchorType.corner:
        // → smooth: generate handles from neighbor directions.
        _generateSmartHandles(anchor, index);
        anchor.type = AnchorType.smooth;
        break;
      case AnchorType.smooth:
        // → symmetric: equalize handles to the longer length.
        if (anchor.handleIn != null && anchor.handleOut != null) {
          final maxLen =
              anchor.handleIn!.distance > anchor.handleOut!.distance
                  ? anchor.handleIn!.distance
                  : anchor.handleOut!.distance;
          if (maxLen > 0) {
            anchor.handleOut =
                anchor.handleOut! / anchor.handleOut!.distance * maxLen;
            anchor.handleIn =
                anchor.handleIn! / anchor.handleIn!.distance * maxLen;
          }
        } else {
          // Only one handle exists — mirror it.
          anchor.handleOut ??=
              anchor.handleIn != null ? -anchor.handleIn! : null;
          anchor.handleIn ??=
              anchor.handleOut != null ? -anchor.handleOut! : null;
        }
        anchor.type = AnchorType.symmetric;
        break;
      case AnchorType.symmetric:
        // → corner: remove handles.
        anchor.handleIn = null;
        anchor.handleOut = null;
        anchor.type = AnchorType.corner;
        break;
    }
  }

  /// Generate smart handles for a corner → smooth conversion.
  ///
  /// Uses 1/3 of the distance to each neighbor as handle length,
  /// pointing in the direction of that neighbor.
  void _generateSmartHandles(AnchorPoint anchor, int index) {
    Offset? prevPos;
    Offset? nextPos;

    if (index > 0) prevPos = _anchors[index - 1].position;
    if (index < _anchors.length - 1) nextPos = _anchors[index + 1].position;

    if (prevPos != null && nextPos != null) {
      // Both neighbors: tangent direction is from prev → next.
      final tangent = nextPos - prevPos;
      final tangentLen = tangent.distance;
      if (tangentLen > 0) {
        final dir = tangent / tangentLen;
        final distToPrev = (anchor.position - prevPos).distance / 3.0;
        final distToNext = (nextPos - anchor.position).distance / 3.0;
        anchor.handleIn = -dir * distToPrev;
        anchor.handleOut = dir * distToNext;
      }
    } else if (prevPos != null) {
      final delta = prevPos - anchor.position;
      final len = delta.distance / 3.0;
      if (len > 0) {
        anchor.handleIn = delta / delta.distance * len;
        anchor.handleOut = -(delta / delta.distance * len);
      }
    } else if (nextPos != null) {
      final delta = nextPos - anchor.position;
      final len = delta.distance / 3.0;
      if (len > 0) {
        anchor.handleOut = delta / delta.distance * len;
        anchor.handleIn = -(delta / delta.distance * len);
      }
    }
  }

  /// Equalize both handle lengths to their average, preserving direction.
  void equalizeHandles(int anchorIndex) {
    if (anchorIndex < 0 || anchorIndex >= _anchors.length) return;
    final anchor = _anchors[anchorIndex];
    if (anchor.handleIn == null || anchor.handleOut == null) return;

    final avgLen =
        (anchor.handleIn!.distance + anchor.handleOut!.distance) / 2.0;
    if (avgLen < 0.01) return;

    anchor.handleIn = anchor.handleIn! / anchor.handleIn!.distance * avgLen;
    anchor.handleOut = anchor.handleOut! / anchor.handleOut!.distance * avgLen;
  }

  // ── PATH REVERSAL ──

  /// Reverse the path direction: reverse anchor order and swap handles.
  void reversePath() {
    if (_anchors.length < 2) return;

    // Swap handleIn ↔ handleOut for each anchor.
    for (final anchor in _anchors) {
      final tmpIn = anchor.handleIn;
      anchor.handleIn = anchor.handleOut;
      anchor.handleOut = tmpIn;
    }

    // Reverse the list in place.
    final reversed = _anchors.reversed.toList();
    _anchors
      ..clear()
      ..addAll(reversed);

    // Update multi-selection indices to match new positions.
    final maxIdx = _anchors.length - 1;
    final adjusted = _selectedAnchorIndices.map((idx) => maxIdx - idx).toSet();
    _selectedAnchorIndices
      ..clear()
      ..addAll(adjusted);
  }

  // ── ANCHOR DELETION ──

  /// Delete anchors at the specified [indices].
  ///
  /// Removes in reverse order to keep indices stable during removal.
  void deleteAnchorsByIndex(Set<int> indices) {
    if (indices.isEmpty) return;

    // Sort descending to remove from end first.
    final sorted = indices.toList()..sort((a, b) => b.compareTo(a));
    for (final idx in sorted) {
      if (idx >= 0 && idx < _anchors.length) {
        _anchors.removeAt(idx);
      }
    }

    // Clear selection — indices no longer valid.
    _selectedAnchorIndices.clear();
  }

  // ── SEGMENT DELETION (SPLIT PATH) ──

  /// Delete segment at [segIndex], splitting the path into two.
  ///
  /// - If only 2 anchors → clear the path entirely.
  /// - If ≥3 anchors → finalize anchors `[0..segIndex]` as a separate
  ///   open PathNode, then keep `[segIndex+1..end]` as the current
  ///   editing session.
  ///
  /// The first half is finalized via [onPathNodeCreated] callback.
  /// Handles at the split boundary are cleared (they pointed to the
  /// deleted segment).
  void deleteSegment(int segIndex, ToolContext context) {
    if (segIndex < 0 || segIndex >= _anchors.length - 1) return;

    // Only 2 anchors — just clear.
    if (_anchors.length <= 2) {
      resetState();
      return;
    }

    // Split into two lists.
    final firstHalf = _anchors.sublist(0, segIndex + 1);
    final secondHalf = _anchors.sublist(segIndex + 1);

    // Clear dangling handles at the split boundary.
    firstHalf.last.handleOut = null;
    secondHalf.first.handleIn = null;

    // Finalize the first half as a separate open PathNode if it has ≥2 anchors.
    if (firstHalf.length >= 2) {
      context.saveUndoState();
      final vectorPath = AnchorPoint.toVectorPath(firstHalf);
      final pathNode = PathNode(
        id: NodeId(generateUid()),
        path: vectorPath,
        name: 'Path',
        fillColor: fillColor,
        fillGradient: fillGradient,
        strokeColor: strokeColor,
        strokeWidth: strokeWidth,
        strokeCap: strokeCap,
        strokeJoin: strokeJoin,
      );
      onPathNodeCreated?.call(pathNode);
    }

    // Load the second half as the current editing session.
    _anchors
      ..clear()
      ..addAll(secondHalf);

    // Clear selection — indices no longer valid.
    _selectedAnchorIndices.clear();
    _editingAnchorIndex = -1;

    // If the second half has < 2 anchors, just keep it for further editing.
    // The user can continue adding points or cancel.
  }

  // ── AUTO-SMOOTH (CATMULL-ROM → BÉZIER) ──

  /// Convert all corner anchors to smooth using Catmull-Rom tangent
  /// interpolation for optimal handle placement.
  ///
  /// For each anchor with neighbors, computes the tangent direction as
  /// `(next - prev)` and sets handles to `tangent * (distance / 6)`.
  /// This produces C1-continuous curves that pass through all anchor points.
  ///
  /// [tension] controls curvature tightness:
  /// - 0.5 (default) = standard Catmull-Rom
  /// - Lower = tighter curves (closer to straight lines)
  /// - Higher = looser, more rounded curves
  void autoSmoothPath({double tension = 0.5}) {
    if (_anchors.length < 2) return;

    final n = _anchors.length;
    for (int i = 0; i < n; i++) {
      final anchor = _anchors[i];

      if (i == 0) {
        // First anchor: use forward difference.
        final next = _anchors[i + 1].position;
        final tangent = next - anchor.position;
        final len = tangent.distance;
        if (len > 0) {
          final dir = tangent / len;
          final handleLen = len / (3.0 / tension);
          anchor.handleOut = dir * handleLen;
          // No handleIn for the first anchor of an open path.
          anchor.handleIn = null;
        }
        anchor.type = AnchorType.smooth;
      } else if (i == n - 1) {
        // Last anchor: use backward difference.
        final prev = _anchors[i - 1].position;
        final tangent = anchor.position - prev;
        final len = tangent.distance;
        if (len > 0) {
          final dir = tangent / len;
          final handleLen = len / (3.0 / tension);
          anchor.handleIn = -dir * handleLen;
          // No handleOut for the last anchor of an open path.
          anchor.handleOut = null;
        }
        anchor.type = AnchorType.smooth;
      } else {
        // Interior anchor: Catmull-Rom tangent from neighbors.
        final prev = _anchors[i - 1].position;
        final next = _anchors[i + 1].position;
        final tangent = next - prev;
        final tangentLen = tangent.distance;
        if (tangentLen > 0) {
          final dir = tangent / tangentLen;
          final distToPrev = (anchor.position - prev).distance;
          final distToNext = (next - anchor.position).distance;
          final handleInLen = distToPrev / (3.0 / tension);
          final handleOutLen = distToNext / (3.0 / tension);
          anchor.handleIn = -dir * handleInLen;
          anchor.handleOut = dir * handleOutLen;
        }
        anchor.type = AnchorType.smooth;
      }
    }
  }

  // ── GRID + GUIDE SNAPPING PIPELINE ──

  /// Apply all snapping stages: grid first, then guide callback.
  Offset applySnapping(Offset pos) {
    var snapped = pos;

    // Grid snap.
    if (gridSpacing != null && gridSpacing! > 0) {
      final g = gridSpacing!;
      snapped = Offset(
        (snapped.dx / g).roundToDouble() * g,
        (snapped.dy / g).roundToDouble() * g,
      );
    }

    // Guide snap callback.
    snapped = snapPosition?.call(snapped) ?? snapped;

    return snapped;
  }
}
