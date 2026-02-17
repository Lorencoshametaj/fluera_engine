import 'dart:ui';
import '../../drawing/models/pro_drawing_point.dart';
import '../../core/models/shape_type.dart';
import './spatial_index.dart';

/// 🚀 VIEWPORT CULLER - Rendering optimization with spatial culling
///
/// PERFORMANCE:
/// - ✅ Draw SOLO visible elements in the viewport
/// - ✅ Spatial indexing per ricerca O(log n) invece di O(n)
/// - ✅ Bounds pre-calcolati per ogni stroke/shape
/// - ✅ Margine di sicurezza to avoid pop-in durante pan
/// - 🚀 QuadTree per 10k+ strokes
///
/// ESEMPIO:
/// - Canvas 100k x 100k with 10,000 strokes
/// - Viewport 1080 x 1920 pixel
/// - Senza culling: 10.000 tratti renderizzati = LAG
/// - With culling: ~50-100 rendered strokes = SMOOTH ✨
class ViewportCuller {
  /// Margine examong thentorno al viewport to avoid pop-in durante pan
  static const double viewportMargin = 1000.0;

  /// 🚀 QUADTREE: usa QuadTree quando ci sono molti strokes (> threshold)
  static const int quadTreeThreshold = 500;

  /// 🚀 Filtra strokes visibili - con supporto QuadTree per grandi quantity
  ///
  /// If spatialIndex is fornito e costruito, usa O(log n) query
  /// Altrimenti usa fallback O(n) con bounds cachati
  static List<ProStroke> filterVisibleStrokesOptimized(
    List<ProStroke> strokes,
    Rect viewport, {
    double margin = viewportMargin,
    SpatialIndexManager? spatialIndex,
  }) {
    if (strokes.isEmpty) return [];

    // 🚀 Se abbiamo un spatial index e ci sono molti strokes, usa QuadTree
    if (spatialIndex != null &&
        spatialIndex.isBuilt &&
        strokes.length > quadTreeThreshold) {
      return spatialIndex.queryVisibleStrokes(viewport, margin: margin);
    }

    // Fallback: filtering lineare O(n) ma con bounds cachati O(1) per stroke
    return filterVisibleStrokes(strokes, viewport, margin: margin);
  }

  /// 🚀 Filtra shapes visibili - con supporto QuadTree per grandi quantity
  static List<GeometricShape> filterVisibleShapesOptimized(
    List<GeometricShape> shapes,
    Rect viewport, {
    double margin = viewportMargin,
    SpatialIndexManager? spatialIndex,
  }) {
    if (shapes.isEmpty) return [];

    // 🚀 Se abbiamo un spatial index, usa QuadTree
    if (spatialIndex != null &&
        spatialIndex.isBuilt &&
        shapes.length > quadTreeThreshold) {
      return spatialIndex.queryVisibleShapes(viewport, margin: margin);
    }

    // Fallback: filtering lineare
    return filterVisibleShapes(shapes, viewport, margin: margin);
  }

  /// Checks se uno stroke is visible in the viewport
  /// 🚀 USA BOUNDS CACHATI for performance O(1) invece di O(n)
  static bool isStrokeVisible(
    ProStroke stroke,
    Rect viewport, {
    double margin = viewportMargin,
  }) {
    // 🚀 Use cached bounds from the stroke (O(1) after first call)
    final bounds = stroke.bounds;
    if (bounds == Rect.zero) return false;

    // Espandi viewport con margine
    final expandedViewport = viewport.inflate(margin);

    // Check intersezione
    return expandedViewport.overlaps(bounds);
  }

  /// Checks if a shape is visible in the viewport
  static bool isShapeVisible(
    GeometricShape shape,
    Rect viewport, {
    double margin = viewportMargin,
  }) {
    final bounds = getShapeBounds(shape);

    // Espandi viewport con margine
    final expandedViewport = viewport.inflate(margin);

    return expandedViewport.overlaps(bounds);
  }

  /// Filters list of strokes per visibility
  static List<ProStroke> filterVisibleStrokes(
    List<ProStroke> strokes,
    Rect viewport, {
    double margin = viewportMargin,
  }) {
    if (strokes.isEmpty) return [];

    return strokes
        .where((stroke) => isStrokeVisible(stroke, viewport, margin: margin))
        .toList();
  }

  /// Filters list of shapes per visibility
  static List<GeometricShape> filterVisibleShapes(
    List<GeometricShape> shapes,
    Rect viewport, {
    double margin = viewportMargin,
  }) {
    if (shapes.isEmpty) return [];

    return shapes
        .where((shape) => isShapeVisible(shape, viewport, margin: margin))
        .toList();
  }

  /// Calculatates bounds di uno stroke
  static Rect? getStrokeBounds(ProStroke stroke) {
    if (stroke.points.isEmpty) return null;

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    for (final point in stroke.points) {
      if (point.position.dx < minX) minX = point.position.dx;
      if (point.position.dy < minY) minY = point.position.dy;
      if (point.position.dx > maxX) maxX = point.position.dx;
      if (point.position.dy > maxY) maxY = point.position.dy;
    }

    // Add padding for the stroke width
    final padding = stroke.baseWidth * 2;

    return Rect.fromLTRB(
      minX - padding,
      minY - padding,
      maxX + padding,
      maxY + padding,
    );
  }

  /// Calculatates bounds di una shape
  static Rect getShapeBounds(GeometricShape shape) {
    final padding = shape.strokeWidth * 2;

    return Rect.fromPoints(shape.startPoint, shape.endPoint).inflate(padding);
  }

  /// Calculatates current viewport in canvas coordinates
  static Rect calculateViewport(
    Size screenSize,
    Offset canvasOffset,
    double canvasScale,
  ) {
    // Transform screen coordinates in canvas coordinates
    // Remove l'offset e scala inversa
    final topLeft = (-canvasOffset) / canvasScale;
    final bottomRight = Offset(
      topLeft.dx + (screenSize.width / canvasScale),
      topLeft.dy + (screenSize.height / canvasScale),
    );

    return Rect.fromPoints(topLeft, bottomRight);
  }
}
