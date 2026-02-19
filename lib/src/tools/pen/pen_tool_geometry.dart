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
      id: const Uuid().v4(),
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
