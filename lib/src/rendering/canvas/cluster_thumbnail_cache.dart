import 'dart:ui' as ui;
import 'dart:collection';
import 'package:flutter/material.dart';
import '../../reflow/content_cluster.dart';
import '../../drawing/models/pro_drawing_point.dart';

/// 🖼️ CLUSTER THUMBNAIL CACHE — Rasterizes cluster content into mini-previews.
///
/// Generates small (120×120) images of each cluster's content using simplified
/// Catmull-Rom paths. Uses LRU eviction to cap memory at [maxEntries] images.
///
/// LIFECYCLE:
/// - Call [generateThumbnail] when a cluster is first visible at LOD 1+
/// - Call [invalidate] when cluster content changes (add/remove stroke)
/// - Call [dispose] to free all GPU textures
///
/// THREAD-SAFETY: All ui.Image operations are main-isolate only.
class ClusterThumbnailCache {
  /// Max cached thumbnails (LRU eviction beyond this).
  final int maxEntries;

  /// Thumbnail pixel size (both width and height).
  static const int thumbnailSize = 120;

  /// Cache: cluster ID → rendered thumbnail.
  final LinkedHashMap<String, ui.Image> _cache = LinkedHashMap();

  /// Cluster bounds at render time — used to detect stale thumbnails.
  final Map<String, Rect> _renderedBounds = {};

  ClusterThumbnailCache({this.maxEntries = 20});

  /// Get a cached thumbnail, or null if not yet generated.
  ui.Image? getThumbnail(String clusterId) => _cache[clusterId];

  /// Whether a thumbnail exists for this cluster.
  bool hasThumbnail(String clusterId) => _cache.containsKey(clusterId);

  /// Whether the thumbnail needs regeneration (bounds changed).
  bool isStale(String clusterId, Rect currentBounds) {
    final rendered = _renderedBounds[clusterId];
    if (rendered == null) return true;
    return rendered != currentBounds;
  }

  /// Generate a thumbnail for a cluster by rendering its strokes.
  ///
  /// [strokes] must be the strokes belonging to this cluster only.
  /// The thumbnail is drawn as simplified Catmull-Rom paths at reduced scale.
  Future<void> generateThumbnail(
    ContentCluster cluster,
    List<ProStroke> strokes,
  ) async {
    if (strokes.isEmpty) return;

    final bounds = cluster.bounds;
    if (bounds.isEmpty || bounds.width < 2 || bounds.height < 2) return;

    // Calculate scale to fit cluster content into thumbnail
    final scaleX = thumbnailSize / bounds.width;
    final scaleY = thumbnailSize / bounds.height;
    final scale = scaleX < scaleY ? scaleX : scaleY;

    // Scaled dimensions (maintain aspect ratio)
    final scaledW = (bounds.width * scale).ceil();
    final scaledH = (bounds.height * scale).ceil();
    if (scaledW < 1 || scaledH < 1) return;

    // Record painting commands
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, scaledW.toDouble(), scaledH.toDouble()),
    );

    // Transform: translate to origin + scale down
    canvas.scale(scale);
    canvas.translate(-bounds.left, -bounds.top);

    // Draw each stroke as a simplified path
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;

      strokePaint
        ..color = stroke.color
        ..strokeWidth = stroke.baseWidth;

      canvas.drawPath(stroke.cachedPath, strokePaint);
    }

    // Rasterize to image
    final picture = recorder.endRecording();
    final image = await picture.toImage(scaledW, scaledH);
    picture.dispose();

    // Evict LRU if at capacity
    while (_cache.length >= maxEntries) {
      final oldest = _cache.keys.first;
      _cache.remove(oldest)?.dispose();
      _renderedBounds.remove(oldest);
    }

    // Store
    _cache[cluster.id] = image;
    _renderedBounds[cluster.id] = bounds;
  }

  String get clusterId => _cache.keys.isEmpty ? '' : _cache.keys.last;

  /// Invalidate a specific cluster's thumbnail.
  void invalidate(String clusterId) {
    _cache.remove(clusterId)?.dispose();
    _renderedBounds.remove(clusterId);
  }

  /// Invalidate all thumbnails.
  void invalidateAll() {
    for (final img in _cache.values) {
      img.dispose();
    }
    _cache.clear();
    _renderedBounds.clear();
  }

  /// Dispose all cached images.
  void dispose() {
    invalidateAll();
  }
}
