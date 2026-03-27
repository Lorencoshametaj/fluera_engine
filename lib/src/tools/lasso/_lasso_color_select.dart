part of 'lasso_tool.dart';

// =============================================================================
// LassoTool — Color-Based Automatic Selection
// =============================================================================

extension LassoColorSelect on LassoTool {
  /// Automatically select all elements on the active layer whose dominant
  /// color matches the color of the element at [tapPoint].
  ///
  /// [tolerance] is the Euclidean distance threshold in normalized RGB space
  /// (0.0 = exact match, 1.0 = match everything). Default 0.15.
  ///
  /// Returns the number of elements selected.
  int _selectByColor(
    Offset tapPoint, {
    double tolerance = 0.15,
    bool additive = false,
  }) {
    final layerNode = _getActiveLayerNode();

    // 1. Find the tapped element — closest center to tapPoint
    CanvasNode? tappedNode;
    double bestDist = double.infinity;

    for (final child in layerNode.children) {
      if (!child.isVisible || child.isLocked) continue;
      final bounds = child.worldBounds;
      if (!bounds.isFinite || bounds.isEmpty) continue;
      if (!bounds.contains(tapPoint)) continue;

      final dist = (bounds.center - tapPoint).distance;
      if (dist < bestDist) {
        bestDist = dist;
        tappedNode = child;
      }
    }

    if (tappedNode == null) return 0;

    // 2. Extract the dominant color from the tapped node
    final referenceColor = _extractNodeColor(tappedNode);
    if (referenceColor == null) return 0;

    // 3. Find all nodes with a similar color
    final matches = <CanvasNode>[];
    for (final child in layerNode.children) {
      if (!child.isVisible || child.isLocked) continue;
      final nodeColor = _extractNodeColor(child);
      if (nodeColor == null) continue;

      if (_colorDistance(referenceColor, nodeColor) <= tolerance) {
        matches.add(child);
      }
    }

    if (matches.isEmpty) return 0;

    // 4. Apply selection
    if (additive || _additiveMode) {
      for (final node in matches) {
        if (!selectionManager.isSelected(node.id)) {
          selectionManager.addToSelection(node);
        }
      }
    } else {
      selectionManager.selectAll(matches);
    }
    _calculateSelectionBounds();

    return matches.length;
  }

  // ===========================================================================
  // Contiguous Flood-Fill Selection (Procreate-style)
  // ===========================================================================

  /// Select a contiguous region of elements starting from [tapPoint].
  ///
  /// Unlike [_selectByColor] which selects ALL matching colors globally,
  /// this performs a BFS flood-fill: starting from the tapped element,
  /// it expands to spatially adjacent elements that share a similar color.
  ///
  /// [gapThreshold] is the max gap (in canvas points) between bounding boxes
  /// for two elements to be considered "adjacent". Larger values bridge gaps.
  ///
  /// Returns the number of elements selected.
  int _floodFillSelect(
    Offset tapPoint, {
    double tolerance = 0.15,
    double gapThreshold = 20.0,
    bool additive = false,
  }) {
    final layerNode = _getActiveLayerNode();

    // 1. Find the tapped element
    CanvasNode? tappedNode;
    double bestDist = double.infinity;

    for (final child in layerNode.children) {
      if (!child.isVisible || child.isLocked) continue;
      final bounds = child.worldBounds;
      if (!bounds.isFinite || bounds.isEmpty) continue;
      if (!bounds.contains(tapPoint)) continue;

      final dist = (bounds.center - tapPoint).distance;
      if (dist < bestDist) {
        bestDist = dist;
        tappedNode = child;
      }
    }

    if (tappedNode == null) return 0;

    final referenceColor = _extractNodeColor(tappedNode);
    if (referenceColor == null) return 0;

    // 2. Build candidate list: all nodes with similar color
    final candidates = <CanvasNode>[];
    for (final child in layerNode.children) {
      if (!child.isVisible || child.isLocked) continue;
      final nodeColor = _extractNodeColor(child);
      if (nodeColor == null) continue;
      if (_colorDistance(referenceColor, nodeColor) <= tolerance) {
        candidates.add(child);
      }
    }

    // 3. BFS flood-fill from the tapped node through spatially adjacent candidates
    final selected = <String>{tappedNode.id};
    final queue = <CanvasNode>[tappedNode];

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final currentBounds = current.worldBounds.inflate(gapThreshold);

      for (final candidate in candidates) {
        if (selected.contains(candidate.id)) continue;
        if (currentBounds.overlaps(candidate.worldBounds)) {
          selected.add(candidate.id);
          queue.add(candidate);
        }
      }
    }

    // 4. Collect selected nodes
    final hits = candidates.where((n) => selected.contains(n.id)).toList();

    if (hits.isEmpty) return 0;

    if (additive || _additiveMode) {
      for (final node in hits) {
        if (!selectionManager.isSelected(node.id)) {
          selectionManager.addToSelection(node);
        }
      }
    } else {
      selectionManager.selectAll(hits);
    }
    _calculateSelectionBounds();

    return hits.length;
  }

  /// Extract the dominant color from a CanvasNode.
  ///
  /// Supports StrokeNode, ShapeNode, TextNode. Returns null for unknown types.
  Color? _extractNodeColor(CanvasNode node) {
    if (node is StrokeNode) {
      return node.stroke.color;
    } else if (node is ShapeNode) {
      return node.shape.color;
    } else if (node is TextNode) {
      return node.textElement.color;
    }
    return null;
  }

  /// Compute the Euclidean distance between two colors in normalized RGB space.
  ///
  /// Returns a value between 0.0 (identical) and ~1.73 (max distance).
  /// We use normalized 0-1 range for each channel.
  double _colorDistance(Color a, Color b) {
    final dr = a.r - b.r;
    final dg = a.g - b.g;
    final db = a.b - b.b;
    return sqrt(dr * dr + dg * dg + db * db);
  }
}

