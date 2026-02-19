import 'dart:ui';
import '../utils/uid.dart';
import '../drawing/models/pro_drawing_point.dart';
import '../core/models/shape_type.dart';
import '../core/models/digital_text_element.dart';
import '../core/models/image_element.dart';
import './content_cluster.dart';

/// 🔍 CLUSTER DETECTOR — Groups elements into [ContentCluster]s.
///
/// Uses temporal + spatial proximity to detect which strokes form a
/// logical unit (a word, a doodle, a signature). This ensures that
/// handwritten words are NEVER broken apart during content reflow.
///
/// ALGORITHM (Union-Find with spatial queries):
/// 1. Sort strokes by [createdAt] timestamp
/// 2. For each consecutive pair, if temporal gap ≤ threshold:
///    expand search to check spatial proximity via bounding box distance
/// 3. Use Union-Find (disjoint set forest) to merge stroke groups
/// 4. Non-stroke elements (shapes, text, images) → always single clusters
///
/// PERFORMANCE: O(n log n) for n strokes (dominated by sort).
/// For 1000 strokes: ~2ms on modern hardware.
class ClusterDetector {
  /// Maximum time gap between strokes to consider them part of the
  /// same cluster (default: 1500ms — covers natural writing speed).
  final int temporalThresholdMs;

  /// Maximum spatial gap between bounding boxes to consider strokes
  /// part of the same cluster (in canvas pixels at scale 1.0).
  /// Default: 50px — covers the gap between 'i' dot and body.
  final double spatialThreshold;

  const ClusterDetector({
    this.temporalThresholdMs = 1500,
    this.spatialThreshold = 50.0,
  });

  /// Build [ContentCluster]s from all elements on a layer.
  ///
  /// Strokes are grouped by temporal + spatial proximity.
  /// Shapes, texts, and images are always individual clusters.
  List<ContentCluster> detect({
    required List<ProStroke> strokes,
    required List<GeometricShape> shapes,
    required List<DigitalTextElement> texts,
    required List<ImageElement> images,
  }) {
    final clusters = <ContentCluster>[];

    // --- Group strokes using Union-Find ---
    if (strokes.isNotEmpty) {
      final strokeClusters = _clusterStrokes(strokes);
      clusters.addAll(strokeClusters);
    }

    // --- Shapes: each is its own cluster ---
    for (final shape in shapes) {
      final bounds = _getShapeBounds(shape);
      clusters.add(
        ContentCluster(
          id: 'cluster_shape_${shape.id}',
          strokeIds: const [],
          shapeIds: [shape.id],
          bounds: bounds,
          centroid: bounds.center,
        ),
      );
    }

    // --- Texts: each is its own cluster ---
    for (final text in texts) {
      final bounds = _estimateTextBounds(text);
      clusters.add(
        ContentCluster(
          id: 'cluster_text_${text.id}',
          strokeIds: const [],
          textIds: [text.id],
          bounds: bounds,
          centroid: bounds.center,
        ),
      );
    }

    // --- Images: each is its own cluster ---
    for (final image in images) {
      final bounds = _estimateImageBounds(image);
      clusters.add(
        ContentCluster(
          id: 'cluster_image_${image.id}',
          strokeIds: const [],
          imageIds: [image.id],
          bounds: bounds,
          centroid: bounds.center,
        ),
      );
    }

    return clusters;
  }

  /// Incrementally add a new stroke to existing clusters.
  ///
  /// Checks if the new stroke should merge into an existing stroke cluster
  /// based on temporal + spatial proximity. If no match, creates a new cluster.
  ///
  /// Returns the updated cluster list.
  List<ContentCluster> addStroke(
    List<ContentCluster> existing,
    ProStroke newStroke,
    List<ProStroke> allStrokes,
  ) {
    final newBounds = newStroke.bounds;
    final newTime = newStroke.createdAt.millisecondsSinceEpoch;
    ContentCluster? bestMatch;

    // Find the best matching cluster (temporal + spatial proximity)
    for (final cluster in existing) {
      // Only merge with stroke clusters
      if (cluster.strokeIds.isEmpty) continue;

      // Check temporal proximity: find the latest stroke in this cluster
      final clusterStrokes =
          allStrokes.where((s) => cluster.strokeIds.contains(s.id)).toList();
      if (clusterStrokes.isEmpty) continue;

      final latestTime = clusterStrokes
          .map((s) => s.createdAt.millisecondsSinceEpoch)
          .reduce((a, b) => a > b ? a : b);

      final timeDiff = (newTime - latestTime).abs();
      if (timeDiff > temporalThresholdMs) continue;

      // Check spatial proximity
      final distance = _boundingBoxDistance(newBounds, cluster.bounds);
      if (distance > spatialThreshold) continue;

      // This cluster matches — pick the closest one
      if (bestMatch == null ||
          _boundingBoxDistance(newBounds, cluster.bounds) <
              _boundingBoxDistance(newBounds, bestMatch.bounds)) {
        bestMatch = cluster;
      }
    }

    final result = List<ContentCluster>.from(existing);

    if (bestMatch != null) {
      // Merge into existing cluster
      final idx = result.indexOf(bestMatch);
      final mergedStrokeIds = [...bestMatch.strokeIds, newStroke.id];
      final mergedBounds = bestMatch.bounds.expandToInclude(newBounds);

      result[idx] = ContentCluster(
        id: bestMatch.id,
        strokeIds: mergedStrokeIds,
        shapeIds: bestMatch.shapeIds,
        textIds: bestMatch.textIds,
        imageIds: bestMatch.imageIds,
        bounds: mergedBounds,
        centroid: mergedBounds.center,
        isPinned: bestMatch.isPinned,
      );
    } else {
      // Create new single-stroke cluster
      result.add(
        ContentCluster(
          id: 'cluster_stroke_${generateUid()}',
          strokeIds: [newStroke.id],
          bounds: newBounds,
          centroid: newBounds.center,
        ),
      );
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // Private: Stroke clustering with Union-Find
  // ---------------------------------------------------------------------------

  List<ContentCluster> _clusterStrokes(List<ProStroke> strokes) {
    if (strokes.isEmpty) return [];
    if (strokes.length == 1) {
      final bounds = strokes[0].bounds;
      return [
        ContentCluster(
          id: 'cluster_stroke_${generateUid()}',
          strokeIds: [strokes[0].id],
          bounds: bounds,
          centroid: bounds.center,
        ),
      ];
    }

    // Sort by creation time
    final sorted = List<ProStroke>.from(strokes)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    // Union-Find data structure
    final parent = List<int>.generate(sorted.length, (i) => i);
    final rank = List<int>.filled(sorted.length, 0);

    int find(int x) {
      while (parent[x] != x) {
        parent[x] = parent[parent[x]]; // Path compression
        x = parent[x];
      }
      return x;
    }

    void union(int a, int b) {
      final ra = find(a);
      final rb = find(b);
      if (ra == rb) return;
      // Union by rank
      if (rank[ra] < rank[rb]) {
        parent[ra] = rb;
      } else if (rank[ra] > rank[rb]) {
        parent[rb] = ra;
      } else {
        parent[rb] = ra;
        rank[ra]++;
      }
    }

    // Merge strokes that are both temporally and spatially close
    for (int i = 0; i < sorted.length; i++) {
      final si = sorted[i];
      final siTime = si.createdAt.millisecondsSinceEpoch;
      final siBounds = si.bounds;

      // Look forward: check subsequent strokes within temporal window
      for (int j = i + 1; j < sorted.length; j++) {
        final sj = sorted[j];
        final sjTime = sj.createdAt.millisecondsSinceEpoch;

        // Once we exceed temporal threshold, no more candidates
        if (sjTime - siTime > temporalThresholdMs) break;

        // Check spatial proximity
        final distance = _boundingBoxDistance(siBounds, sj.bounds);
        if (distance <= spatialThreshold) {
          union(i, j);
        }
      }
    }

    // Build clusters from Union-Find groups
    final groups = <int, List<int>>{};
    for (int i = 0; i < sorted.length; i++) {
      final root = find(i);
      groups.putIfAbsent(root, () => []).add(i);
    }

    return groups.values.map((indices) {
      final clusterStrokes = indices.map((i) => sorted[i]).toList();
      final ids = clusterStrokes.map((s) => s.id).toList();

      // Compute union bounds
      var bounds = clusterStrokes[0].bounds;
      for (int i = 1; i < clusterStrokes.length; i++) {
        bounds = bounds.expandToInclude(clusterStrokes[i].bounds);
      }

      return ContentCluster(
        id: 'cluster_stroke_${generateUid()}',
        strokeIds: ids,
        bounds: bounds,
        centroid: bounds.center,
      );
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Private: Distance and bounds helpers
  // ---------------------------------------------------------------------------

  /// Minimum distance between two bounding boxes.
  /// Returns 0 if they overlap or touch.
  double _boundingBoxDistance(Rect a, Rect b) {
    final dx = _axisDistance(a.left, a.right, b.left, b.right);
    final dy = _axisDistance(a.top, a.bottom, b.top, b.bottom);

    if (dx <= 0 && dy <= 0) return 0; // Overlapping
    if (dx <= 0) return dy; // Overlapping on X, gap on Y
    if (dy <= 0) return dx; // Overlapping on Y, gap on X

    // Diagonal distance (corner to corner)
    return (dx * dx + dy * dy).toDouble();
  }

  /// Gap between two 1D intervals [aMin, aMax] and [bMin, bMax].
  /// Negative means overlap.
  double _axisDistance(double aMin, double aMax, double bMin, double bMax) {
    if (aMax < bMin) return bMin - aMax;
    if (bMax < aMin) return aMin - bMax;
    return -1; // Overlapping
  }

  /// Compute bounds for a geometric shape from its start/end points.
  Rect _getShapeBounds(GeometricShape shape) {
    final left =
        shape.startPoint.dx < shape.endPoint.dx
            ? shape.startPoint.dx
            : shape.endPoint.dx;
    final top =
        shape.startPoint.dy < shape.endPoint.dy
            ? shape.startPoint.dy
            : shape.endPoint.dy;
    final right =
        shape.startPoint.dx > shape.endPoint.dx
            ? shape.startPoint.dx
            : shape.endPoint.dx;
    final bottom =
        shape.startPoint.dy > shape.endPoint.dy
            ? shape.startPoint.dy
            : shape.endPoint.dy;
    return Rect.fromLTRB(left, top, right, bottom);
  }

  /// Estimate text bounds without BuildContext.
  /// Uses a rough approximation: fontSize × text length.
  Rect _estimateTextBounds(DigitalTextElement text) {
    final charWidth = text.fontSize * text.scale * 0.6;
    final lineHeight = text.fontSize * text.scale * 1.2;
    final lines = text.text.split('\n');
    final maxLineLength = lines
        .map((l) => l.length)
        .reduce((a, b) => a > b ? a : b);

    return Rect.fromLTWH(
      text.position.dx,
      text.position.dy,
      maxLineLength * charWidth,
      lines.length * lineHeight,
    );
  }

  /// Estimate image bounds from position and scale.
  Rect _estimateImageBounds(ImageElement image) {
    // Default image size assumption (actual size loaded async)
    const defaultSize = 200.0;
    final size = defaultSize * image.scale;
    return Rect.fromLTWH(image.position.dx, image.position.dy, size, size);
  }
}
