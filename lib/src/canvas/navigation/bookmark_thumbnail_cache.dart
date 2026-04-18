import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/models/canvas_layer.dart';

/// 🖼️ BOOKMARK THUMBNAIL CACHE — rasterized previews of bookmarked zones.
///
/// Parallel implementation to [ClusterThumbnailCache] but keyed on a
/// bookmark id + arbitrary world Rect (not on a [ContentCluster]). The
/// bookmark layer doesn't need to know about clusters: any rectangle of
/// the canvas can be turned into a 120×120 preview for the list sheet.
///
/// PRINCIPLES:
///   - LRU eviction beyond [maxEntries] images
///   - All ui.Image disposals tracked — no GPU leak
///   - Lazy: thumbnails are generated on-demand when the bookmark sheet
///     opens, never in batch on canvas load (would cause boot-time jank)
///   - Not persisted to disk: regenerated per-session (compromise — VRAM
///     is cheaper than rasterizing on a background isolate, and bookmarks
///     are infrequent enough that redoing 50 thumbnails on app open is
///     well below the user's pain threshold)
///
/// THREAD-SAFETY: ui.Image / PictureRecorder / Canvas are main-isolate only.
class BookmarkThumbnailCache {
  /// Pixel size (square thumbnails — same as ClusterThumbnailCache).
  static const int thumbnailSize = 120;

  /// Max entries before LRU eviction.
  final int maxEntries;

  final LinkedHashMap<String, ui.Image> _cache = LinkedHashMap();
  final Map<String, Rect> _renderedBounds = {};

  BookmarkThumbnailCache({this.maxEntries = 30});

  ui.Image? get(String bookmarkId) => _cache[bookmarkId];
  bool has(String bookmarkId) => _cache.containsKey(bookmarkId);

  /// True if the cached entry doesn't match [currentBounds] anymore.
  bool isStale(String bookmarkId, Rect currentBounds) {
    final rendered = _renderedBounds[bookmarkId];
    if (rendered == null) return true;
    return rendered != currentBounds;
  }

  /// Generate a thumbnail for the slice of canvas inside [worldBounds].
  ///
  /// Filters strokes from the active layer that overlap the bounds and
  /// rasterizes them at simplified scale into a [ui.Image]. Stores the
  /// result in the LRU cache, evicting the oldest if needed.
  ///
  /// Returns the generated image, or null if the bounds are degenerate
  /// or no content overlaps (caller can render a placeholder).
  Future<ui.Image?> generateForBounds({
    required String bookmarkId,
    required Rect worldBounds,
    required CanvasLayer activeLayer,
  }) async {
    if (worldBounds.isEmpty ||
        worldBounds.width < 2 ||
        worldBounds.height < 2) {
      return null;
    }

    // Fit-into-square scale.
    final scaleX = thumbnailSize / worldBounds.width;
    final scaleY = thumbnailSize / worldBounds.height;
    final scale = scaleX < scaleY ? scaleX : scaleY;

    final scaledW = (worldBounds.width * scale).ceil();
    final scaledH = (worldBounds.height * scale).ceil();
    if (scaledW < 1 || scaledH < 1) return null;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, scaledW.toDouble(), scaledH.toDouble()),
    );
    canvas.scale(scale);
    canvas.translate(-worldBounds.left, -worldBounds.top);

    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    var anyDrawn = false;
    for (final stroke in activeLayer.strokes) {
      if (stroke.points.isEmpty) continue;
      // Cheap early reject — bounds vs stroke bounds.
      if (!worldBounds.overlaps(stroke.bounds)) continue;
      strokePaint
        ..color = stroke.color
        ..strokeWidth = stroke.baseWidth;
      canvas.drawPath(stroke.cachedPath, strokePaint);
      anyDrawn = true;
    }

    final picture = recorder.endRecording();
    if (!anyDrawn) {
      // Empty zone — still allocate a tiny image so the sheet shows a
      // consistent placeholder rather than an undefined slot.
      picture.dispose();
      return null;
    }

    final image = await picture.toImage(scaledW, scaledH);
    picture.dispose();

    // LRU eviction.
    while (_cache.length >= maxEntries) {
      final oldestKey = _cache.keys.first;
      _cache.remove(oldestKey)?.dispose();
      _renderedBounds.remove(oldestKey);
    }

    _cache[bookmarkId] = image;
    _renderedBounds[bookmarkId] = worldBounds;
    return image;
  }

  void invalidate(String bookmarkId) {
    _cache.remove(bookmarkId)?.dispose();
    _renderedBounds.remove(bookmarkId);
  }

  void invalidateAll() {
    for (final img in _cache.values) {
      img.dispose();
    }
    _cache.clear();
    _renderedBounds.clear();
  }

  void dispose() {
    invalidateAll();
  }
}
