import 'dart:ui';

import '../../core/vector/vector_network.dart';

// ---------------------------------------------------------------------------
// Level of Detail (LOD) for VectorNetwork rendering
// ---------------------------------------------------------------------------

/// Level of detail categories.
enum DetailLevel {
  /// Full detail: all segments, vertex handles, per-segment strokes.
  /// Used when zoom > 1.0.
  full,

  /// Medium detail: simplified paths, no vertex handles.
  /// Used when zoom ∈ [0.3, 1.0].
  medium,

  /// Low detail: bounding outline only, no per-segment strokes.
  /// Used when zoom < 0.3.
  low,
}

/// Provides Level of Detail (LOD) utilities for [VectorNetwork] rendering.
///
/// At high zoom, renders every segment with full Bézier curves and vertex
/// handles. At low zoom, renders a simplified bounding outline to save
/// rendering time — crucial for performance with many visible networks.
///
/// ```dart
/// final path = NetworkLOD.buildForZoom(network, zoom);
/// canvas.drawPath(path, strokePaint);
/// ```
class NetworkLOD {
  NetworkLOD._();

  // Cache for LOD paths per detail level.
  static final Map<String, (int revision, DetailLevel level, Path path)>
  _cache = {};

  /// Determine the detail level for a given [zoom] factor.
  static DetailLevel detailLevelForZoom(double zoom) {
    if (zoom > 1.0) return DetailLevel.full;
    if (zoom >= 0.3) return DetailLevel.medium;
    return DetailLevel.low;
  }

  /// Whether vertex handles should be drawn at this [zoom].
  static bool shouldDrawVertexHandles(double zoom) => zoom > 2.0;

  /// Whether per-segment stroke overrides should be applied at this [zoom].
  static bool shouldDrawPerSegmentStroke(double zoom) => zoom > 0.5;

  /// Build a Flutter [Path] appropriate for the given [zoom] level.
  ///
  /// Uses caching with revision-based invalidation.
  /// [networkId] is used as cache key (typically the node ID).
  static Path buildForZoom(
    VectorNetwork network,
    double zoom, {
    String? networkId,
  }) {
    final level = detailLevelForZoom(zoom);
    final cacheKey = networkId ?? network.hashCode.toString();

    // Check cache.
    final cached = _cache[cacheKey];
    if (cached != null && cached.$1 == network.revision && cached.$2 == level) {
      return cached.$3;
    }

    final path = _buildPath(network, level);
    _cache[cacheKey] = (network.revision, level, path);
    return path;
  }

  /// Clear the LOD path cache.
  static void clearCache() => _cache.clear();

  // -------------------------------------------------------------------------
  // Path building per detail level
  // -------------------------------------------------------------------------

  static Path _buildPath(VectorNetwork network, DetailLevel level) {
    switch (level) {
      case DetailLevel.full:
        return _buildFullPath(network);
      case DetailLevel.medium:
        return _buildMediumPath(network);
      case DetailLevel.low:
        return _buildLowPath(network);
    }
  }

  /// Full detail: all segments with their original Bézier curves.
  static Path _buildFullPath(VectorNetwork network) {
    return network.toFlutterPath();
  }

  /// Medium detail: straight-line approximation (skip tangent handles).
  static Path _buildMediumPath(VectorNetwork network) {
    final path = Path();
    if (network.segments.isEmpty) return path;

    final visited = <int>{};

    for (final seg in network.segments) {
      final startPos = network.vertices[seg.start].position;
      final endPos = network.vertices[seg.end].position;

      if (!visited.contains(seg.start)) {
        path.moveTo(startPos.dx, startPos.dy);
        visited.add(seg.start);
      }

      // Skip short segments (< 2px equivalent at medium zoom).
      final dx = endPos.dx - startPos.dx;
      final dy = endPos.dy - startPos.dy;
      if (dx * dx + dy * dy < 4) continue;

      path.lineTo(endPos.dx, endPos.dy);
      visited.add(seg.end);
    }

    return path;
  }

  /// Low detail: just the bounding rectangle outline.
  static Path _buildLowPath(VectorNetwork network) {
    final path = Path();
    if (network.vertices.isEmpty) return path;

    final bounds = network.computeBounds();
    if (bounds.isEmpty) return path;

    path.addRect(bounds);
    return path;
  }
}
