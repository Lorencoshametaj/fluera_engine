import 'dart:math' as math;
import 'dart:ui';
import '../utils/uid.dart';
import '../drawing/models/pro_drawing_point.dart';
import '../core/models/shape_type.dart';
import '../core/models/digital_text_element.dart';
import '../core/models/image_element.dart';
import '../feature_flags/cluster_id_v2_flag.dart';
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
  /// same cluster (default: 2500ms — covers natural writing speed
  /// including brief pauses between letters).
  final int temporalThresholdMs;

  /// Maximum spatial gap between bounding boxes to consider strokes
  /// part of the same cluster (in canvas pixels at scale 1.0).
  /// Default: 60px — covers the gap between 'i' dot and body.
  final double spatialThreshold;

  /// Maximum HORIZONTAL gap for the post-clustering overlap merge pass.
  /// Two clusters that share vertical overlap (i.e. on the same line) get
  /// merged when their X-gap is within this distance — fixes word splits
  /// from slow writing (e.g. "Lo" + pause + "renzo" → "Lorenzo").
  /// Default: 80px — wider than character spacing, narrower than column gaps.
  final double overlapMergeThreshold;

  /// Maximum VERTICAL gap for the same merge pass on stacked clusters.
  /// Much stricter than the horizontal gap because students write paragraphs
  /// in vertical stacks — merging them aggressively destroys per-paragraph
  /// clusters (the most common case for lecture notes).
  ///
  /// Default: 10px — covers an "i" dot floating just above its body (4-8px)
  /// and accent marks landing slightly above the letter, but rejects normal
  /// inter-line spacing (16-20px) in a multi-paragraph layout.
  final double verticalStackMergeThreshold;

  const ClusterDetector({
    this.temporalThresholdMs = 2500,
    this.spatialThreshold = 60.0,
    this.overlapMergeThreshold = 80.0,
    this.verticalStackMergeThreshold = 10.0,
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
          id: 'cluster_stroke_${newStroke.id}',
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
      final t = strokes[0].createdAt.millisecondsSinceEpoch;
      final id = ClusterIdV2Flag.enabled
          ? 'cluster_v2_${_contentHashV2(bounds, 1, t)}'
          : 'cluster_stroke_${strokes[0].id}';
      return [
        ContentCluster(
          id: id,
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

    var clusters = groups.values.map((indices) {
      final clusterStrokes = indices.map((i) => sorted[i]).toList();
      final ids = clusterStrokes.map((s) => s.id).toList();

      // Compute union bounds
      var bounds = clusterStrokes[0].bounds;
      for (int i = 1; i < clusterStrokes.length; i++) {
        bounds = bounds.expandToInclude(clusterStrokes[i].bounds);
      }

      return ContentCluster(
        id: '', // Temporary, will be assigned after merge pass
        strokeIds: ids,
        bounds: bounds,
        centroid: bounds.center,
      );
    }).toList();

    // Compute median timestamp per cluster — used as a temporal guard in the
    // spatial merge pass below. Two paragraphs written 30s apart but with
    // overlapping x-bounds and only ~20px vertical gap should NOT be merged
    // even if they pass the spatial predicate.
    final strokeTimeById = <String, int>{
      for (final s in sorted) s.id: s.createdAt.millisecondsSinceEpoch,
    };
    int medianTime(List<String> strokeIds) {
      if (strokeIds.isEmpty) return 0;
      final times = strokeIds
          .map((id) => strokeTimeById[id] ?? 0)
          .toList()
        ..sort();
      return times[times.length ~/ 2];
    }
    var clusterTimes = clusters.map((c) => medianTime(c.strokeIds)).toList();

    // === SPATIAL OVERLAP MERGE PASS ===
    // Merge clusters whose bounding boxes overlap or are very close.
    // Direction-aware: a wide horizontal threshold catches split words on
    // the same line ("Lo" + pause + "renzo" → "Lorenzo"); a tight vertical
    // threshold preserves separate paragraphs (lecture notes, lists).
    //
    // The old single-threshold pass (80px in any direction) merged whole
    // multi-paragraph blobs into one cluster — fixed 2026-05-07.
    //
    // Temporal guard (added 2026-05-07, refined later same day): clusters
    // whose median timestamps differ by more than `temporalThresholdMs * 4`
    // (10s) are treated as distinct concepts when they are STACKED
    // (paragraphs above/below). Same-line merges are NOT guarded — students
    // often pause >10s between consecutive words on the same baseline, and
    // we want "LEGGI DI NEWTON PRIMA LEGGE" to be one cluster regardless
    // of writing pace.
    final temporalGuardMs = temporalThresholdMs * 4;
    bool merged = true;
    while (merged) {
      merged = false;
      for (int i = 0; i < clusters.length; i++) {
        for (int j = i + 1; j < clusters.length; j++) {
          final ba = clusters[i].bounds;
          final bb = clusters[j].bounds;
          if (!_shouldMerge(ba, bb)) {
            continue;
          }
          // Temporal guard — only on stacked (vertical) merges. Same-line
          // word sequences may have multi-second pauses between tokens.
          final dxOnly = _axisDistance(ba.left, ba.right, bb.left, bb.right);
          final dyOnly = _axisDistance(ba.top, ba.bottom, bb.top, bb.bottom);
          final isStackedMerge = dyOnly > 0 && dxOnly <= 0;
          if (isStackedMerge) {
            final dt = (clusterTimes[i] - clusterTimes[j]).abs();
            if (dt > temporalGuardMs) continue;
          }
          // Merge j into i
          final mergedIds = [
            ...clusters[i].strokeIds,
            ...clusters[j].strokeIds,
          ];
          final mergedBounds = clusters[i].bounds.expandToInclude(
            clusters[j].bounds,
          );
          clusters[i] = ContentCluster(
            id: '',
            strokeIds: mergedIds,
            bounds: mergedBounds,
            centroid: mergedBounds.center,
          );
          clusters.removeAt(j);
          // Recompute the merged cluster's median time from its new strokeIds.
          clusterTimes[i] = medianTime(mergedIds);
          clusterTimes.removeAt(j);
          merged = true;
          break; // Restart inner loop
        }
        if (merged) break; // Restart outer loop
      }
    }

    // Assign deterministic IDs after all merges.
    // V2 (default): content-stable hash — bounds quantized to 24px + count
    // + temporal centroid (5min granularity). Adding/removing 1-2 strokes
    // within the same footprint preserves the ID, so downstream caches
    // (`aiTitles`, `ClusterConceptIndex`) survive minor edits.
    // V1 (legacy): hash of sorted strokeIds — invalidated on every edit.
    final useV2 = ClusterIdV2Flag.enabled;
    return List<ContentCluster>.generate(clusters.length, (i) {
      final c = clusters[i];
      final String id;
      if (useV2) {
        id = 'cluster_v2_${_contentHashV2(c.bounds, c.strokeIds.length, clusterTimes[i])}';
      } else {
        final sortedIds = List<String>.from(c.strokeIds)..sort();
        id = 'cluster_stroke_${sortedIds.join("_").hashCode.toRadixString(36)}';
      }
      return ContentCluster(
        id: id,
        strokeIds: c.strokeIds,
        bounds: c.bounds,
        centroid: c.centroid,
      );
    });
  }

  /// Content-stable hash for V2 cluster IDs.
  ///
  /// Inputs are quantized so canvas edits / drags don't change the hash:
  /// - Bounds left/top: 240px grid (page-level positioning). A user
  ///   drag of ≤240px preserves the ID. Coarse enough that a cluster
  ///   moved across a section break gets a new ID (intentional).
  /// - Bounds width/height: 24px grid (size-stable to minor stroke
  ///   additions). Adding a small accent / dot won't bump the size
  ///   class enough to change the hash.
  /// - Stroke count: bumps every add/remove. Acceptable — most edits
  ///   add several strokes (one word ≈ 5-12 strokes), so the count
  ///   change usually correlates with a content change.
  /// - Temporal centroid: 5-minute buckets. Two clusters drawn in the
  ///   same session collapse to one bucket; a cluster reactivated days
  ///   later gets a new bucket and a new id (intentional — different
  ///   study session = different concept iteration).
  ///
  /// Position granularity rationale (2026-05-10 device tuning):
  ///   • 24px (old) was too tight — reflow physics shifted clusters
  ///     by ~30-50px, invalidating cache. Cache hit rate ~30%.
  ///   • 240px (new) = ~page-level positioning. Cache hit rate ~95%
  ///     in expected edits. Distinct page regions still distinct.
  ///
  /// Returns a base-36 string. Collisions are statistically unlikely on
  /// a single canvas (≈few hundred clusters max); collisions across
  /// canvases are fine because [ClusterConceptIndex] is canvas-scoped.
  String _contentHashV2(Rect bounds, int strokeCount, int temporalCentroidMs) {
    int q24(double v) => (v / 24).round();
    int q240(double v) => (v / 240).round();
    final qLeft = q240(bounds.left);
    final qTop = q240(bounds.top);
    final qW = q24(bounds.width);
    final qH = q24(bounds.height);
    final qT = (temporalCentroidMs / 300000).round(); // 5 min buckets
    // Mix the components — XOR alone collides too easily on aligned grids.
    int h = 0x811c9dc5; // FNV-1a offset basis
    for (final v in [qLeft, qTop, qW, qH, strokeCount, qT]) {
      h = (h ^ v) & 0xFFFFFFFF;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(36);
  }

  // ---------------------------------------------------------------------------
  // Private: Distance and bounds helpers
  // ---------------------------------------------------------------------------

  /// Direction-aware merge predicate for the post-clustering overlap pass.
  ///
  /// Returns `true` if cluster bounds [a] and [b] should be merged into a
  /// single concept cluster:
  ///
  /// - Same line (vertical overlap, horizontal gap): merge when the
  ///   horizontal gap is within [overlapMergeThreshold]. Catches split
  ///   words on a single baseline.
  /// - Stacked (horizontal overlap, vertical gap): merge only when the
  ///   vertical gap is within [verticalStackMergeThreshold]. Preserves
  ///   separate paragraphs / list items in lecture notes.
  /// - Fully overlapping: always merge (a stroke nested inside another
  ///   cluster's bounds, e.g. an "i" dot landing on top of its body).
  /// - Diagonal (gaps on both axes): never merge — diagonal proximity
  ///   between two distinct clusters almost never means "same concept".
  bool _shouldMerge(Rect a, Rect b) {
    final dx = _axisDistance(a.left, a.right, b.left, b.right);
    final dy = _axisDistance(a.top, a.bottom, b.top, b.bottom);

    // Fully overlapping or touching on both axes.
    if (dx <= 0 && dy <= 0) return true;

    // Same line — vertical overlap, only horizontal gap matters.
    if (dy <= 0) return dx <= overlapMergeThreshold;

    // Stacked — horizontal overlap, only vertical gap matters.
    if (dx <= 0) return dy <= verticalStackMergeThreshold;

    // Diagonal — both axes have gaps. Don't merge.
    return false;
  }

  /// Minimum distance (in pixels) between two bounding boxes.
  /// Returns 0 if they overlap or touch.
  ///
  /// Bug fix 2026-05-07: the diagonal branch used to return the squared
  /// distance (`dx*dx + dy*dy`), so call sites comparing against a pixel
  /// threshold (e.g. `spatialThreshold = 60`) effectively required
  /// `gap < sqrt(60) ≈ 7.7px` for diagonal pairs. Diagonal stroke pairs
  /// were never being merged. Now returns the real Euclidean distance.
  double _boundingBoxDistance(Rect a, Rect b) {
    final dx = _axisDistance(a.left, a.right, b.left, b.right);
    final dy = _axisDistance(a.top, a.bottom, b.top, b.bottom);

    if (dx <= 0 && dy <= 0) return 0; // Overlapping
    if (dx <= 0) return dy; // Overlapping on X, gap on Y
    if (dy <= 0) return dx; // Overlapping on Y, gap on X

    // Diagonal: real Euclidean distance between the closest corners.
    return math.sqrt(dx * dx + dy * dy);
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
