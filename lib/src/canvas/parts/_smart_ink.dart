part of '../fluera_canvas_screen.dart';

/// ✍️ Smart Ink — tap-to-reveal recognized handwriting text.
///
/// Adds the state, stroke hit-test logic, and overlay trigger
/// for the SmartInkOverlay popup. Integrates with the toolwheel
/// (radial menu) UX — no toolbar dependency.
extension FlueraSmartInkExtension on _FlueraCanvasScreenState {
  // State is stored via the existing mixin pattern (ValueNotifier).
  // We use the _uiRebuildNotifier to trigger rebuilds when the overlay
  // shows/hides.

  // =========================================================================
  // SMART INK STATE (stored as static map keyed by state hash)
  // =========================================================================
  // Because Dart `extension` methods cannot add instance fields, we use
  // a static expando-like approach. This is lightweight since there's only
  // ever one canvas screen alive at a time.

  static SmartInkOverlayData? _activeSmartInk;

  // ✍️ Deferred tap state — set in _onDrawStart, resolved in _onDrawEnd.
  // Uses statics because Dart extensions cannot add instance fields.
  static ProStroke? _pendingSmartInkStroke;
  static Offset? _pendingSmartInkScreenPos;

  /// Whether the Smart Ink overlay is currently showing.
  bool get isSmartInkActive => _activeSmartInk != null;

  /// Clear pending Smart Ink state (called from _onDrawCancel).
  void clearPendingSmartInk() {
    _pendingSmartInkStroke = null;
    _pendingSmartInkScreenPos = null;
  }

  /// Dismiss the Smart Ink overlay.
  void dismissSmartInk() {
    _activeSmartInk = null;
    _uiRebuildNotifier.value++;
  }

  // =========================================================================
  // STROKE HIT-TEST
  // =========================================================================

  /// Find a stroke at the given canvas-space position.
  ///
  /// Uses a simple bounding-box + distance-to-polyline check.
  /// Hit radius is scaled by zoom level for consistent tap precision.
  /// Returns the stroke and its ID, or null if no stroke is near.
  ({ProStroke stroke, String strokeId})? _hitTestStroke(Offset canvasPos) {
    final activeLayer = _layerController.activeLayer;
    if (activeLayer == null) return null;

    // 🔍 Zoom-adaptive hit radius: consistent tap precision at all zoom levels
    final hitRadius = 20.0 / _canvasController.scale;
    ProStroke? bestStroke;
    double bestDist = hitRadius;

    for (final stroke in activeLayer.strokes) {
      // Quick bounds check
      final bounds = _strokeBounds(stroke);
      if (bounds == null) continue;
      if (!bounds.inflate(hitRadius).contains(canvasPos)) continue;

      // Fine check: min distance to polyline segments
      final dist = _distToStroke(stroke, canvasPos);
      if (dist < bestDist) {
        bestDist = dist;
        bestStroke = stroke;
      }
    }

    if (bestStroke == null) return null;
    return (stroke: bestStroke, strokeId: bestStroke.id);
  }

  /// Find all strokes near the tapped stroke (same word/phrase).
  ///
  /// Baseline-aware two-pass algorithm (ported from HandwritingIndexService):
  ///
  /// **Pass 1 — Line segmentation**: Compute each stroke's baseline
  /// (median Y) and group strokes with similar baselines into text lines.
  /// Threshold is adaptive to handwriting size (median stroke height × 0.6).
  ///
  /// **Pass 2 — Multi-stroke merging**: Within the tapped stroke's line,
  /// merge strokes whose inflated bounds overlap (union-find). This captures
  /// multi-stroke characters like 't', 'i', 'ñ' without crossing line
  /// boundaries.
  ///
  /// Strokes are sorted left-to-right for natural reading order.
  List<ProStroke> _findNearbyStrokes(ProStroke tappedStroke) {
    final activeLayer = _layerController.activeLayer;
    if (activeLayer == null) return [tappedStroke];

    final allStrokes = activeLayer.strokes;
    if (allStrokes.length <= 1) return [tappedStroke];

    // Pre-compute bounds and baselines for all strokes
    final boundsMap = <ProStroke, Rect>{};
    final baselineMap = <ProStroke, double>{};
    final heights = <double>[];

    for (final stroke in allStrokes) {
      final bounds = _strokeBounds(stroke);
      if (bounds == null) continue;
      boundsMap[stroke] = bounds;
      // Baseline = median Y (more robust than mean against outlier points)
      final ys = stroke.points.map((p) => p.position.dy).toList()..sort();
      baselineMap[stroke] = ys[ys.length ~/ 2];
      heights.add(bounds.height);
    }

    if (!boundsMap.containsKey(tappedStroke)) return [tappedStroke];

    // ── Pass 1: Line segmentation by baseline ──────────────────────────

    // Adaptive line threshold based on median stroke height
    heights.sort();
    final medianHeight = heights[heights.length ~/ 2];
    final lineThreshold = (medianHeight * 0.6).clamp(20.0, 80.0);

    // Sort strokes by baseline for efficient line detection
    final sortedStrokes = boundsMap.keys.toList()
      ..sort((a, b) => baselineMap[a]!.compareTo(baselineMap[b]!));

    // Find which line the tapped stroke belongs to
    List<ProStroke>? tappedLine;
    var currentLine = <ProStroke>[sortedStrokes.first];
    var lineBaseline = baselineMap[sortedStrokes.first]!;

    for (int k = 1; k < sortedStrokes.length; k++) {
      final stroke = sortedStrokes[k];
      final baseline = baselineMap[stroke]!;

      if ((baseline - lineBaseline).abs() <= lineThreshold) {
        currentLine.add(stroke);
        // Rolling average baseline
        lineBaseline = currentLine
            .map((s) => baselineMap[s]!)
            .reduce((a, b) => a + b) / currentLine.length;
      } else {
        // Line boundary — check if tapped stroke was in this line
        if (currentLine.contains(tappedStroke)) {
          tappedLine = currentLine;
          break;
        }
        currentLine = [stroke];
        lineBaseline = baseline;
      }
    }
    // Check last line
    tappedLine ??= currentLine.contains(tappedStroke)
        ? currentLine
        : [tappedStroke];

    if (tappedLine.length <= 1) return tappedLine;

    // ── Pass 2: Proximity-based union-find within the tapped line ─────

    // Adaptive proximity: scale with handwriting size
    final proximityPx = (medianHeight * 1.2).clamp(30.0, 120.0);
    final parent = List<int>.generate(tappedLine.length, (i) => i);

    int find(int i) {
      while (parent[i] != i) {
        parent[i] = parent[parent[i]]; // path compression
        i = parent[i];
      }
      return i;
    }

    void union(int a, int b) {
      final ra = find(a);
      final rb = find(b);
      if (ra != rb) parent[ra] = rb;
    }

    for (int i = 0; i < tappedLine.length; i++) {
      for (int j = i + 1; j < tappedLine.length; j++) {
        final a = boundsMap[tappedLine[i]]!.inflate(proximityPx);
        final b = boundsMap[tappedLine[j]]!;
        if (a.overlaps(b)) {
          union(i, j);
        }
      }
    }

    // Find the group that contains the tapped stroke
    final tappedIdx = tappedLine.indexOf(tappedStroke);
    final tappedRoot = find(tappedIdx);

    final lineGroup = <ProStroke>[];
    for (int i = 0; i < tappedLine.length; i++) {
      if (find(i) == tappedRoot) {
        lineGroup.add(tappedLine[i]);
      }
    }

    if (lineGroup.length <= 1) return lineGroup;

    // ── Pass 3: Word boundary detection ───────────────────────────────
    // Split the line group into words by detecting large horizontal gaps.
    // A "word gap" is significantly larger than the typical inter-letter gap.

    // Sort left-to-right by center X
    lineGroup.sort((a, b) =>
        boundsMap[a]!.center.dx.compareTo(boundsMap[b]!.center.dx));

    // Compute horizontal gaps between consecutive strokes
    final gaps = <double>[];
    for (int i = 0; i < lineGroup.length - 1; i++) {
      final rightEdge = boundsMap[lineGroup[i]]!.right;
      final leftEdge = boundsMap[lineGroup[i + 1]]!.left;
      gaps.add(leftEdge - rightEdge); // negative = overlapping
    }

    if (gaps.isEmpty) return lineGroup;

    // Compute median gap and median stroke width
    final sortedGaps = gaps.toList()..sort();
    final medianGap = sortedGaps[sortedGaps.length ~/ 2];
    final widths = lineGroup.map((s) => boundsMap[s]!.width).toList()..sort();
    final medianWidth = widths[widths.length ~/ 2];

    // Word gap threshold: max of (2× median gap, 0.8× median stroke width)
    // This adapts to both loose and tight handwriting styles
    final wordGapThreshold = [medianGap * 2.0, medianWidth * 0.8]
        .reduce((a, b) => a > b ? a : b)
        .clamp(medianHeight * 0.3, medianHeight * 3.0);

    // Split into words at large gaps
    final words = <List<ProStroke>>[<ProStroke>[lineGroup.first]];
    for (int i = 0; i < gaps.length; i++) {
      if (gaps[i] > wordGapThreshold) {
        // Word boundary detected
        words.add(<ProStroke>[lineGroup[i + 1]]);
      } else {
        words.last.add(lineGroup[i + 1]);
      }
    }

    // Return the word containing the tapped stroke
    for (final word in words) {
      if (word.contains(tappedStroke)) return word;
    }

    // Fallback (shouldn't happen)
    return lineGroup;
  }

  /// Compute bounding rect of a stroke.
  Rect? _strokeBounds(ProStroke stroke) {
    if (stroke.points.isEmpty) return null;
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final p in stroke.points) {
      if (p.position.dx < minX) minX = p.position.dx;
      if (p.position.dy < minY) minY = p.position.dy;
      if (p.position.dx > maxX) maxX = p.position.dx;
      if (p.position.dy > maxY) maxY = p.position.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// Minimum distance from a point to a stroke's polyline.
  double _distToStroke(ProStroke stroke, Offset point) {
    if (stroke.points.isEmpty) return double.infinity;
    if (stroke.points.length == 1) {
      return (stroke.points.first.position - point).distance;
    }

    double minDist = double.infinity;
    for (int i = 0; i < stroke.points.length - 1; i++) {
      final a = stroke.points[i].position;
      final b = stroke.points[i + 1].position;
      final d = _distToSegment(point, a, b);
      if (d < minDist) minDist = d;
    }
    return minDist;
  }

  /// Distance from point P to line segment AB.
  double _distToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final ap = p - a;
    final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lenSq < 0.0001) return ap.distance;
    final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / lenSq).clamp(0.0, 1.0);
    final proj = a + ab * t;
    return (p - proj).distance;
  }

  // =========================================================================
  // TRIGGER — called from drawing end or tap handler
  // =========================================================================

  /// Show the Smart Ink overlay for a stroke at the given screen position.
  ///
  /// Gathers all nearby strokes (same word/phrase) for multi-stroke recognition.
  void showSmartInk({
    required Offset screenAnchor,
    required ProStroke stroke,
    required String canvasId,
  }) {
    // Gather nearby strokes for whole-word recognition
    final nearbyStrokes = _findNearbyStrokes(stroke);
    _activeSmartInk = SmartInkOverlayData(
      anchorPosition: screenAnchor,
      strokes: nearbyStrokes,
      canvasId: canvasId,
    );
    _uiRebuildNotifier.value++;
    HapticFeedback.lightImpact();
  }

  /// Build the Smart Ink overlay widget (called from _buildImpl).
  Widget? buildSmartInkOverlay(BuildContext context) {
    final data = _activeSmartInk;
    if (data == null) return null;

    return SmartInkOverlay(
      anchorPosition: data.anchorPosition,
      allStrokeSets: data.strokes.map((s) => s.points).toList(),
      strokeIds: data.strokes.map((s) => s.id).toList(),
      canvasId: data.canvasId,
      writingArea: MediaQuery.sizeOf(context),
      isDark: Theme.of(context).brightness == Brightness.dark,
      onResult: (result) {
        if (result.action == SmartInkAction.convert) {
          // Convert all grouped strokes to digital text
          _convertStrokesToText(data.strokes, result.text);
        }
        dismissSmartInk();
      },
    );
  }

  /// Convert grouped handwriting strokes to a DigitalTextElement.
  void _convertStrokesToText(List<ProStroke> strokes, String text) {
    if (text.isEmpty || strokes.isEmpty) return;

    // Compute combined bounds of all strokes
    Rect? combinedBounds;
    for (final stroke in strokes) {
      final bounds = _strokeBounds(stroke);
      if (bounds == null) continue;
      combinedBounds = combinedBounds?.expandToInclude(bounds) ?? bounds;
    }
    if (combinedBounds == null) return;

    // Create a digital text element at the group position
    final element = DigitalTextElement(
      id: generateUid(),
      text: text,
      position: combinedBounds.topLeft,
      fontSize: (combinedBounds.height * 0.8).clamp(14.0, 48.0),
      color: strokes.first.color,
      createdAt: DateTime.now(),
    );

    // Remove all original strokes
    final activeLayer = _layerController.activeLayer;
    if (activeLayer != null) {
      final strokeIds = strokes.map((s) => s.id).toSet();
      activeLayer.strokes.removeWhere((s) => strokeIds.contains(s.id));
      activeLayer.node.invalidateStrokeCache();
    }

    // Add the text element
    _digitalTextElements.add(element);

    // Update rendering
    _layerController.sceneGraph.bumpVersion();
    DrawingPainter.invalidateAllTiles();
    DrawingPainter.triggerRepaint();
    _uiRebuildNotifier.value++;
    _autoSaveCanvas();

    HapticFeedback.heavyImpact();
  }
}

/// Data holder for an active Smart Ink overlay.
class SmartInkOverlayData {
  final Offset anchorPosition;
  final List<ProStroke> strokes;
  final String canvasId;

  const SmartInkOverlayData({
    required this.anchorPosition,
    required this.strokes,
    required this.canvasId,
  });
}
