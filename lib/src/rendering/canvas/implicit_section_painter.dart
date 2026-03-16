import 'dart:ui';
import 'package:flutter/material.dart';
import '../../reflow/content_cluster.dart';

/// 🫧 IMPLICIT SECTION PAINTER — Visualizes cluster groups as "thought bubbles".
///
/// Draws subtle, semi-transparent rounded rectangles around content clusters
/// detected by [ClusterDetector]. This gives the user a visual sense of
/// how their content is organized without requiring manual section creation.
///
/// DESIGN:
/// - Ultra-subtle fill (3% opacity) — barely visible but creates visual grouping
/// - Rounded corners with generous padding for breathing room
/// - Only multi-element clusters get boundaries (single strokes are too noisy)
/// - Fades out at extreme zoom levels (LOD-aware)
/// - Zero allocation paint path — reuses Paint objects
class ImplicitSectionPainter extends CustomPainter {
  /// Current content clusters to visualize.
  final List<ContentCluster> clusters;

  /// Current canvas scale (for LOD-aware rendering).
  final double canvasScale;

  /// Whether implicit sections are enabled.
  final bool enabled;

  /// Minimum number of elements in a cluster to show a boundary.
  /// Single-stroke clusters are too noisy to visualize.
  static const int _minElementsForBoundary = 2;

  /// Padding around cluster bounds (in canvas pixels).
  static const double _padding = 12.0;

  /// Corner radius for the rounded rect.
  static const double _cornerRadius = 8.0;

  /// Fill opacity (very subtle — 3%).
  static const double _fillOpacity = 0.03;

  /// Border opacity (slightly more visible — 6%).
  static const double _borderOpacity = 0.06;

  /// Minimum scale to render boundaries (too zoomed out = skip).
  static const double _minScale = 0.05;

  /// Maximum scale to render boundaries (too zoomed in = skip).
  static const double _maxScale = 5.0;

  // Reusable Paint objects (zero allocation per frame)
  static final Paint _fillPaint = Paint()
    ..style = PaintingStyle.fill;

  static final Paint _borderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.5;

  ImplicitSectionPainter({
    required this.clusters,
    required this.canvasScale,
    this.enabled = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!enabled) return;
    if (clusters.isEmpty) return;
    if (canvasScale < _minScale || canvasScale > _maxScale) return;

    // Fade at scale extremes for smooth LOD transition
    final scaleFade = _computeScaleFade(canvasScale);
    if (scaleFade <= 0.01) return;

    for (final cluster in clusters) {
      // Only visualize multi-element clusters
      if (cluster.elementCount < _minElementsForBoundary) continue;

      // Skip pinned clusters (they're explicit, not implicit)
      if (cluster.isPinned) continue;

      final bounds = cluster.displacedBounds.inflate(_padding);
      if (bounds.isEmpty || bounds.width < 1 || bounds.height < 1) continue;

      // Determine color from cluster type
      final color = _clusterColor(cluster);

      // Fill
      _fillPaint.color = color.withValues(alpha: _fillOpacity * scaleFade);
      final rrect = RRect.fromRectAndRadius(
        bounds,
        Radius.circular(_cornerRadius / canvasScale),
      );
      canvas.drawRRect(rrect, _fillPaint);

      // Border
      _borderPaint
        ..color = color.withValues(alpha: _borderOpacity * scaleFade)
        ..strokeWidth = 0.5 / canvasScale;
      canvas.drawRRect(rrect, _borderPaint);
    }
  }

  /// Soft fade at scale extremes.
  double _computeScaleFade(double scale) {
    // Fade in from minScale to minScale*2
    if (scale < _minScale * 2) {
      return ((scale - _minScale) / _minScale).clamp(0.0, 1.0);
    }
    // Fade out from maxScale/2 to maxScale
    if (scale > _maxScale / 2) {
      return ((_maxScale - scale) / (_maxScale / 2)).clamp(0.0, 1.0);
    }
    return 1.0;
  }

  /// Color based on cluster content type.
  ///
  /// Strokes = blue, shapes = green, text = purple, mixed = grey.
  Color _clusterColor(ContentCluster cluster) {
    final hasStrokes = cluster.strokeIds.isNotEmpty;
    final hasShapes = cluster.shapeIds.isNotEmpty;
    final hasText = cluster.textIds.isNotEmpty;
    final hasImages = cluster.imageIds.isNotEmpty;

    final typeCount =
        (hasStrokes ? 1 : 0) +
        (hasShapes ? 1 : 0) +
        (hasText ? 1 : 0) +
        (hasImages ? 1 : 0);

    if (typeCount > 1) return const Color(0xFF9E9E9E); // Mixed = grey
    if (hasStrokes) return const Color(0xFF42A5F5); // Blue
    if (hasShapes) return const Color(0xFF66BB6A); // Green
    if (hasText) return const Color(0xFFAB47BC); // Purple
    if (hasImages) return const Color(0xFFFF7043); // Orange

    return const Color(0xFF9E9E9E); // Fallback grey
  }

  @override
  bool shouldRepaint(ImplicitSectionPainter oldDelegate) =>
      clusters != oldDelegate.clusters ||
      canvasScale != oldDelegate.canvasScale ||
      enabled != oldDelegate.enabled;
}
