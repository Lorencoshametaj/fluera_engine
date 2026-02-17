import 'dart:math' as math;
import 'dart:ui';
import '../../drawing/models/pro_drawing_point.dart';
import '../../core/models/shape_type.dart';

/// V7: Eraser shape modes
enum EraserShape { circle, rectangle, line }

// ============================================================================
// 🎨 ERASER HIT TESTER — Pure geometry for eraser-stroke intersection
// ============================================================================

/// Static utility class for eraser hit testing.
/// All methods are shape-aware (circle, rectangle, line).
///
/// DESIGN PRINCIPLES:
/// - Pure geometry — no mutable state, no side effects
/// - All shape parameters passed explicitly for testability
/// - Optimized with bounding box pre-rejection
abstract final class EraserHitTester {
  /// Checks if ANY segment of the stroke passes within the eraser area.
  /// Delegates to shape-specific hit testing.
  static bool strokeIntersectsEraser(
    ProStroke stroke,
    Offset eraserCenter, {
    required double eraserRadius,
    required EraserShape eraserShape,
    double eraserShapeWidth = 30.0,
    double eraserShapeAngle = 0.0,
  }) {
    if (stroke.points.isEmpty) return false;

    // Quick bounding box rejection
    final bbox = strokeBBox(stroke);
    if (bbox != null) {
      final expanded = bbox.inflate(eraserRadius);
      if (!expanded.contains(eraserCenter)) return false;
    }

    switch (eraserShape) {
      case EraserShape.rectangle:
        return _strokeIntersectsRect(
          stroke,
          eraserCenter,
          eraserRadius: eraserRadius,
          eraserShapeWidth: eraserShapeWidth,
          eraserShapeAngle: eraserShapeAngle,
        );
      case EraserShape.line:
        return _strokeIntersectsLine(
          stroke,
          eraserCenter,
          eraserRadius: eraserRadius,
          eraserShapeAngle: eraserShapeAngle,
        );
      case EraserShape.circle:
        return _strokeIntersectsCircle(
          stroke,
          eraserCenter,
          eraserRadius: eraserRadius,
        );
    }
  }

  /// Circle hit test (original V1 logic)
  static bool _strokeIntersectsCircle(
    ProStroke stroke,
    Offset eraserCenter, {
    required double eraserRadius,
  }) {
    final radiusSq = eraserRadius * eraserRadius;
    final first = stroke.points.first.position;
    if (distanceSq(first, eraserCenter) <= radiusSq) return true;

    for (int i = 1; i < stroke.points.length; i++) {
      final a = stroke.points[i - 1].position;
      final b = stroke.points[i].position;
      if (pointToSegmentDistSq(eraserCenter, a, b) <= radiusSq) return true;
    }
    return false;
  }

  /// Rectangle hit test — oriented rectangle centered at eraserCenter
  static bool _strokeIntersectsRect(
    ProStroke stroke,
    Offset eraserCenter, {
    required double eraserRadius,
    required double eraserShapeWidth,
    required double eraserShapeAngle,
  }) {
    final halfW = eraserShapeWidth / 2;
    final halfH = eraserRadius;
    final cosA = math.cos(-eraserShapeAngle);
    final sinA = math.sin(-eraserShapeAngle);

    for (final point in stroke.points) {
      final dx = point.position.dx - eraserCenter.dx;
      final dy = point.position.dy - eraserCenter.dy;
      final lx = dx * cosA - dy * sinA;
      final ly = dx * sinA + dy * cosA;
      if (lx.abs() <= halfW && ly.abs() <= halfH) return true;
    }
    // Also check segments
    for (int i = 1; i < stroke.points.length; i++) {
      final a = stroke.points[i - 1].position;
      final b = stroke.points[i].position;
      final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      final dx = mid.dx - eraserCenter.dx;
      final dy = mid.dy - eraserCenter.dy;
      final lx = dx * cosA - dy * sinA;
      final ly = dx * sinA + dy * cosA;
      if (lx.abs() <= halfW && ly.abs() <= halfH) return true;
    }
    return false;
  }

  /// Line hit test — thin line eraser (like a blade/scraper)
  static bool _strokeIntersectsLine(
    ProStroke stroke,
    Offset eraserCenter, {
    required double eraserRadius,
    required double eraserShapeAngle,
  }) {
    final lineLen = eraserRadius * 2;
    final dir = Offset(math.cos(eraserShapeAngle), math.sin(eraserShapeAngle));
    final lineA = eraserCenter - dir * (lineLen / 2);
    final lineB = eraserCenter + dir * (lineLen / 2);
    final threshold = 4.0;
    final thresholdSq = threshold * threshold;

    for (int i = 1; i < stroke.points.length; i++) {
      final a = stroke.points[i - 1].position;
      final b = stroke.points[i].position;
      final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      if (pointToSegmentDistSq(mid, lineA, lineB) <= thresholdSq) return true;
      if (pointToSegmentDistSq(a, lineA, lineB) <= thresholdSq) return true;
    }
    return false;
  }

  /// Shape-aware inside check for a single point. Used by partial erasing.
  static bool isPointInsideEraser(
    Offset point,
    Offset eraserCenter, {
    required double eraserRadius,
    required EraserShape eraserShape,
    double eraserShapeWidth = 30.0,
    double eraserShapeAngle = 0.0,
  }) {
    switch (eraserShape) {
      case EraserShape.circle:
        return distanceSq(point, eraserCenter) <= eraserRadius * eraserRadius;
      case EraserShape.rectangle:
        final dx = point.dx - eraserCenter.dx;
        final dy = point.dy - eraserCenter.dy;
        final cosA = math.cos(-eraserShapeAngle);
        final sinA = math.sin(-eraserShapeAngle);
        final lx = dx * cosA - dy * sinA;
        final ly = dx * sinA + dy * cosA;
        return lx.abs() <= eraserShapeWidth / 2 && ly.abs() <= eraserRadius;
      case EraserShape.line:
        final dx = point.dx - eraserCenter.dx;
        final dy = point.dy - eraserCenter.dy;
        final cosA = math.cos(-eraserShapeAngle);
        final sinA = math.sin(-eraserShapeAngle);
        final lx = dx * cosA - dy * sinA;
        final ly = dx * sinA + dy * cosA;
        return lx.abs() <= eraserRadius && ly.abs() <= 3.0;
    }
  }

  /// Checks if a geometric shape intersects the eraser circle.
  static bool shapeIntersectsEraser(
    GeometricShape shape,
    Offset eraserCenter, {
    required double eraserRadius,
  }) {
    final radiusSq = eraserRadius * eraserRadius;

    if (distanceSq(shape.startPoint, eraserCenter) <= radiusSq) return true;
    if (distanceSq(shape.endPoint, eraserCenter) <= radiusSq) return true;

    final rect = Rect.fromPoints(shape.startPoint, shape.endPoint);
    final corners = [
      rect.topLeft,
      rect.topRight,
      rect.bottomRight,
      rect.bottomLeft,
    ];
    for (int i = 0; i < 4; i++) {
      final a = corners[i];
      final b = corners[(i + 1) % 4];
      if (pointToSegmentDistSq(eraserCenter, a, b) <= radiusSq) {
        return true;
      }
    }

    if (rect.contains(eraserCenter)) return true;
    return false;
  }

  /// Smart edge detection — find the exact point on the stroke
  /// closest to the eraser border for precise clipping.
  static Offset? getClosestEdgePoint(
    Offset eraserCenter,
    double eraserRadius,
    List<ProStroke> strokes,
  ) {
    double bestDist = double.infinity;
    Offset? bestPoint;
    final borderRadius = eraserRadius;

    for (final stroke in strokes) {
      for (int i = 1; i < stroke.points.length; i++) {
        final a = stroke.points[i - 1].position;
        final b = stroke.points[i].position;

        final closest = closestPointOnSegment(eraserCenter, a, b);
        final dist = (closest - eraserCenter).distance;
        final borderDist = (dist - borderRadius).abs();
        if (borderDist < bestDist) {
          bestDist = borderDist;
          bestPoint = closest;
        }
      }
    }
    return bestPoint;
  }

  // ─── Primitive Geometry ────────────────────────────────────────────

  /// Find the closest point on segment AB to point P
  static Offset closestPointOnSegment(Offset p, Offset a, Offset b) {
    final abx = b.dx - a.dx;
    final aby = b.dy - a.dy;
    final lenSq = abx * abx + aby * aby;
    if (lenSq < 0.0001) return a;

    var t = ((p.dx - a.dx) * abx + (p.dy - a.dy) * aby) / lenSq;
    t = t.clamp(0.0, 1.0);
    return Offset(a.dx + t * abx, a.dy + t * aby);
  }

  /// Point-to-segment squared distance.
  static double pointToSegmentDistSq(Offset p, Offset a, Offset b) {
    final abx = b.dx - a.dx;
    final aby = b.dy - a.dy;
    final lenSq = abx * abx + aby * aby;

    if (lenSq < 0.0001) {
      return distanceSq(p, a);
    }

    var t = ((p.dx - a.dx) * abx + (p.dy - a.dy) * aby) / lenSq;
    t = t.clamp(0.0, 1.0);

    final closestX = a.dx + t * abx;
    final closestY = a.dy + t * aby;

    final dx = p.dx - closestX;
    final dy = p.dy - closestY;
    return dx * dx + dy * dy;
  }

  /// Squared distance between two points.
  static double distanceSq(Offset a, Offset b) {
    final dx = a.dx - b.dx;
    final dy = a.dy - b.dy;
    return dx * dx + dy * dy;
  }

  /// Quick bounding box for a stroke (delegates to cached ProStroke.bounds).
  static Rect? strokeBBox(ProStroke stroke) {
    if (stroke.points.isEmpty) return null;
    return stroke.bounds;
  }
}
