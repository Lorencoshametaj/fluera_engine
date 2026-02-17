import 'dart:math' as math;
import 'dart:ui';
import './vector_path.dart';

/// Factory methods to create [VectorPath]s for standard geometric shapes.
///
/// Each preset generates a path using Bézier curves (where needed)
/// that matches the visual output of the existing [ShapePainter].
/// These can be used to create [PathNode]s for the scene graph.
class ShapePresets {
  ShapePresets._();

  // -------------------------------------------------------------------------
  // Rectangles
  // -------------------------------------------------------------------------

  /// Axis-aligned rectangle from [bounds].
  static VectorPath rectangle(Rect bounds) {
    final p = VectorPath.moveTo(bounds.topLeft);
    p.lineTo(bounds.topRight.dx, bounds.topRight.dy);
    p.lineTo(bounds.bottomRight.dx, bounds.bottomRight.dy);
    p.lineTo(bounds.bottomLeft.dx, bounds.bottomLeft.dy);
    p.close();
    return p;
  }

  /// Rounded rectangle with uniform [radius].
  static VectorPath roundedRectangle(Rect bounds, double radius) {
    final r = radius.clamp(0, bounds.shortestSide / 2);
    final l = bounds.left, t = bounds.top;
    final ri = bounds.right, b = bounds.bottom;

    // Bézier magic number for 90° arcs: 4/3 * (√2 - 1) ≈ 0.5523.
    const k = 0.5522847498;
    final kr = k * r;

    final p = VectorPath.moveTo(Offset(l + r, t));
    // Top edge
    p.lineTo(ri - r, t);
    // Top-right corner
    p.cubicTo(ri - r + kr, t, ri, t + r - kr, ri, t + r);
    // Right edge
    p.lineTo(ri, b - r);
    // Bottom-right corner
    p.cubicTo(ri, b - r + kr, ri - r + kr, b, ri - r, b);
    // Bottom edge
    p.lineTo(l + r, b);
    // Bottom-left corner
    p.cubicTo(l + r - kr, b, l, b - r + kr, l, b - r);
    // Left edge
    p.lineTo(l, t + r);
    // Top-left corner
    p.cubicTo(l, t + r - kr, l + r - kr, t, l + r, t);
    p.close();
    return p;
  }

  // -------------------------------------------------------------------------
  // Ellipse / Circle
  // -------------------------------------------------------------------------

  /// Ellipse inscribed in [bounds] using 4 cubic Bézier arcs.
  static VectorPath ellipse(Rect bounds) {
    final cx = bounds.center.dx;
    final cy = bounds.center.dy;
    final rx = bounds.width / 2;
    final ry = bounds.height / 2;
    const k = 0.5522847498;
    final kx = k * rx;
    final ky = k * ry;

    final p = VectorPath.moveTo(Offset(cx, cy - ry)); // top
    p.cubicTo(cx + kx, cy - ry, cx + rx, cy - ky, cx + rx, cy); // right
    p.cubicTo(cx + rx, cy + ky, cx + kx, cy + ry, cx, cy + ry); // bottom
    p.cubicTo(cx - kx, cy + ry, cx - rx, cy + ky, cx - rx, cy); // left
    p.cubicTo(cx - rx, cy - ky, cx - kx, cy - ry, cx, cy - ry); // top
    p.close();
    return p;
  }

  /// Perfect circle centered at [center] with given [radius].
  static VectorPath circle(Offset center, double radius) {
    return ellipse(Rect.fromCircle(center: center, radius: radius));
  }

  // -------------------------------------------------------------------------
  // Polygons
  // -------------------------------------------------------------------------

  /// Regular polygon with [sides] inscribed in [bounds].
  static VectorPath regularPolygon(Rect bounds, int sides) {
    assert(sides >= 3);
    final cx = bounds.center.dx;
    final cy = bounds.center.dy;
    final r = bounds.shortestSide / 2;

    final p = VectorPath(segments: []);
    for (int i = 0; i < sides; i++) {
      final angle = (i * 2 * math.pi / sides) - math.pi / 2;
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      if (i == 0) {
        p.segments.add(MoveSegment(endPoint: Offset(x, y)));
      } else {
        p.lineTo(x, y);
      }
    }
    p.close();
    return p;
  }

  /// Equilateral triangle inscribed in [bounds].
  static VectorPath triangle(Rect bounds) {
    final topCenter = Offset(bounds.center.dx, bounds.top);
    final bottomLeft = bounds.bottomLeft;
    final bottomRight = bounds.bottomRight;

    final p = VectorPath.moveTo(topCenter);
    p.lineTo(bottomRight.dx, bottomRight.dy);
    p.lineTo(bottomLeft.dx, bottomLeft.dy);
    p.close();
    return p;
  }

  /// Diamond (rhombus) inscribed in [bounds].
  static VectorPath diamond(Rect bounds) {
    final cx = bounds.center.dx;
    final cy = bounds.center.dy;

    final p = VectorPath.moveTo(Offset(cx, bounds.top));
    p.lineTo(bounds.right, cy);
    p.lineTo(cx, bounds.bottom);
    p.lineTo(bounds.left, cy);
    p.close();
    return p;
  }

  /// Pentagon inscribed in [bounds].
  static VectorPath pentagon(Rect bounds) => regularPolygon(bounds, 5);

  /// Hexagon inscribed in [bounds].
  static VectorPath hexagon(Rect bounds) => regularPolygon(bounds, 6);

  // -------------------------------------------------------------------------
  // Star
  // -------------------------------------------------------------------------

  /// Star with [points] tips inscribed in [bounds].
  ///
  /// [innerRatio] controls the inner radius as a fraction of the outer
  /// radius (default 0.4 matches the existing ShapePainter).
  static VectorPath star(
    Rect bounds, {
    int points = 5,
    double innerRatio = 0.4,
  }) {
    final cx = bounds.center.dx;
    final cy = bounds.center.dy;
    final r = bounds.shortestSide / 2;
    final innerR = r * innerRatio;

    final p = VectorPath(segments: []);
    for (int i = 0; i < points * 2; i++) {
      final angle = (i * math.pi / points) - math.pi / 2;
      final currentR = i.isEven ? r : innerR;
      final x = cx + currentR * math.cos(angle);
      final y = cy + currentR * math.sin(angle);
      if (i == 0) {
        p.segments.add(MoveSegment(endPoint: Offset(x, y)));
      } else {
        p.lineTo(x, y);
      }
    }
    p.close();
    return p;
  }

  // -------------------------------------------------------------------------
  // Heart
  // -------------------------------------------------------------------------

  /// Heart shape inscribed in [bounds] using cubic Béziers.
  static VectorPath heart(Rect bounds) {
    final cx = bounds.center.dx;
    final w = bounds.width;
    final h = bounds.height;
    final topY = bounds.top;

    final p = VectorPath.moveTo(Offset(cx, topY + h * 0.3));
    // Left lobe
    p.cubicTo(
      cx - w * 0.3,
      topY,
      cx - w * 0.5,
      topY + h * 0.1,
      cx - w * 0.5,
      topY + h * 0.3,
    );
    p.cubicTo(
      cx - w * 0.5,
      topY + h * 0.5,
      cx - w * 0.3,
      topY + h * 0.7,
      cx,
      topY + h,
    );
    // Right lobe
    p.cubicTo(
      cx + w * 0.3,
      topY + h * 0.7,
      cx + w * 0.5,
      topY + h * 0.5,
      cx + w * 0.5,
      topY + h * 0.3,
    );
    p.cubicTo(
      cx + w * 0.5,
      topY + h * 0.1,
      cx + w * 0.3,
      topY,
      cx,
      topY + h * 0.3,
    );
    p.close();
    return p;
  }

  // -------------------------------------------------------------------------
  // Arrow
  // -------------------------------------------------------------------------

  /// Arrow from [start] to [end] with configurable [headSize].
  static VectorPath arrow(Offset start, Offset end, {double headSize = 20}) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final angle = math.atan2(dy, dx);
    const headAngle = 25 * math.pi / 180;

    final leftX = end.dx - headSize * math.cos(angle - headAngle);
    final leftY = end.dy - headSize * math.sin(angle - headAngle);
    final rightX = end.dx - headSize * math.cos(angle + headAngle);
    final rightY = end.dy - headSize * math.sin(angle + headAngle);

    final p = VectorPath.moveTo(start);
    p.lineTo(end.dx, end.dy);

    // Arrowhead as a sub-path.
    p.segments.add(MoveSegment(endPoint: Offset(leftX, leftY)));
    p.lineTo(end.dx, end.dy);
    p.lineTo(rightX, rightY);

    return p;
  }

  // -------------------------------------------------------------------------
  // Line
  // -------------------------------------------------------------------------

  /// Simple straight line from [start] to [end].
  static VectorPath line(Offset start, Offset end) {
    final p = VectorPath.moveTo(start);
    p.lineTo(end.dx, end.dy);
    return p;
  }
}
