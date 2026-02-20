import 'dart:ui';
import 'dart:math' as math;

// ---------------------------------------------------------------------------
// Bézier curve intersection & splitting utilities
// ---------------------------------------------------------------------------

/// A cubic Bézier curve defined by four control points.
class CubicBezier {
  final Offset p0, p1, p2, p3;

  const CubicBezier(this.p0, this.p1, this.p2, this.p3);

  /// Evaluate position at parameter [t] ∈ [0, 1].
  Offset pointAt(double t) {
    final mt = 1.0 - t;
    final mt2 = mt * mt;
    final t2 = t * t;
    return p0 * (mt2 * mt) +
        p1 * (3 * mt2 * t) +
        p2 * (3 * mt * t2) +
        p3 * (t2 * t);
  }

  /// Derivative at parameter [t].
  Offset tangentAt(double t) {
    final mt = 1.0 - t;
    return (p1 - p0) * (3 * mt * mt) +
        (p2 - p1) * (6 * mt * t) +
        (p3 - p2) * (3 * t * t);
  }

  /// Axis-aligned bounding box of this curve.
  Rect get bounds {
    double minX = math.min(math.min(p0.dx, p1.dx), math.min(p2.dx, p3.dx));
    double minY = math.min(math.min(p0.dy, p1.dy), math.min(p2.dy, p3.dy));
    double maxX = math.max(math.max(p0.dx, p1.dx), math.max(p2.dx, p3.dx));
    double maxY = math.max(math.max(p0.dy, p1.dy), math.max(p2.dy, p3.dy));
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// Arc length via 20-point Gaussian quadrature approximation.
  double get length {
    double sum = 0;
    const n = 20;
    for (int i = 0; i < n; i++) {
      final t = (i + 0.5) / n;
      sum += tangentAt(t).distance;
    }
    return sum / n;
  }
}

/// Bézier clipping and splitting utilities.
///
/// Provides:
/// - De Casteljau splitting
/// - Curve-curve intersection via recursive subdivision
/// - Winding number computation for point-in-polygon on Bézier boundaries
class BezierClipping {
  BezierClipping._();

  // -------------------------------------------------------------------------
  // De Casteljau split
  // -------------------------------------------------------------------------

  /// Split a cubic Bézier at parameter [t] into two sub-curves.
  ///
  /// Uses the De Casteljau algorithm for numerically stable splitting.
  static (CubicBezier left, CubicBezier right) splitAt(
    CubicBezier c,
    double t,
  ) {
    final p01 = Offset.lerp(c.p0, c.p1, t)!;
    final p12 = Offset.lerp(c.p1, c.p2, t)!;
    final p23 = Offset.lerp(c.p2, c.p3, t)!;
    final p012 = Offset.lerp(p01, p12, t)!;
    final p123 = Offset.lerp(p12, p23, t)!;
    final p0123 = Offset.lerp(p012, p123, t)!;

    return (
      CubicBezier(c.p0, p01, p012, p0123),
      CubicBezier(p0123, p123, p23, c.p3),
    );
  }

  // -------------------------------------------------------------------------
  // Curve-curve intersection
  // -------------------------------------------------------------------------

  /// Find all intersection points between two cubic Bézier curves.
  ///
  /// Uses recursive subdivision with AABB overlap pruning.
  /// Returns list of parameter pairs `(tA, tB)` where the curves intersect.
  ///
  /// [tolerance] controls the precision (default: 0.5 pixels).
  /// [maxDepth] limits recursion depth (default: 30).
  static List<(double tA, double tB)> intersectCubics(
    CubicBezier a,
    CubicBezier b, {
    double tolerance = 0.5,
    int maxDepth = 30,
  }) {
    final results = <(double, double)>[];
    _intersectRecursive(
      a,
      b,
      0.0,
      1.0,
      0.0,
      1.0,
      tolerance,
      maxDepth,
      0,
      results,
    );

    // Deduplicate near-identical intersections.
    return _deduplicateIntersections(results, tolerance: 1e-6);
  }

  static void _intersectRecursive(
    CubicBezier a,
    CubicBezier b,
    double aMin,
    double aMax,
    double bMin,
    double bMax,
    double tolerance,
    int maxDepth,
    int depth,
    List<(double, double)> results,
  ) {
    // Early exit if we already have enough intersections.
    if (results.length >= 16) return;

    final boundsA = a.bounds;
    final boundsB = b.bounds;

    // Prune: no AABB overlap.
    if (!boundsA.overlaps(boundsB)) return;

    // Base case: curves are small enough.
    final sizeA = math.max(boundsA.width, boundsA.height);
    final sizeB = math.max(boundsB.width, boundsB.height);

    if ((sizeA < tolerance && sizeB < tolerance) || depth >= maxDepth) {
      final tA = (aMin + aMax) / 2;
      final tB = (bMin + bMax) / 2;
      results.add((tA, tB));
      return;
    }

    // Alternating subdivision: split only the LONGER curve.
    if (sizeA >= sizeB) {
      final aMid = (aMin + aMax) / 2;
      final (aLeft, aRight) = splitAt(a, 0.5);
      _intersectRecursive(
        aLeft,
        b,
        aMin,
        aMid,
        bMin,
        bMax,
        tolerance,
        maxDepth,
        depth + 1,
        results,
      );
      _intersectRecursive(
        aRight,
        b,
        aMid,
        aMax,
        bMin,
        bMax,
        tolerance,
        maxDepth,
        depth + 1,
        results,
      );
    } else {
      final bMid = (bMin + bMax) / 2;
      final (bLeft, bRight) = splitAt(b, 0.5);
      _intersectRecursive(
        a,
        bLeft,
        aMin,
        aMax,
        bMin,
        bMid,
        tolerance,
        maxDepth,
        depth + 1,
        results,
      );
      _intersectRecursive(
        a,
        bRight,
        aMin,
        aMax,
        bMid,
        bMax,
        tolerance,
        maxDepth,
        depth + 1,
        results,
      );
    }
  }

  static List<(double, double)> _deduplicateIntersections(
    List<(double, double)> results, {
    double tolerance = 1e-6,
  }) {
    if (results.length <= 1) return results;

    results.sort((a, b) {
      final cmp = a.$1.compareTo(b.$1);
      return cmp != 0 ? cmp : a.$2.compareTo(b.$2);
    });

    final deduped = <(double, double)>[results.first];
    for (int i = 1; i < results.length; i++) {
      final prev = deduped.last;
      final curr = results[i];
      if ((curr.$1 - prev.$1).abs() > tolerance ||
          (curr.$2 - prev.$2).abs() > tolerance) {
        deduped.add(curr);
      }
    }
    return deduped;
  }

  // -------------------------------------------------------------------------
  // Curve-line intersection
  // -------------------------------------------------------------------------

  /// Find intersection parameters of a cubic Bézier with a horizontal line.
  ///
  /// Returns list of parameter values `t` where `curve.pointAt(t).dy == y`.
  static List<double> intersectCubicHorizontal(CubicBezier c, double y) {
    // Remap to polynomial: a*t³ + b*t² + c*t + d = 0
    final d = c.p0.dy - y;
    final ct = 3 * (c.p1.dy - c.p0.dy);
    final bt = 3 * (c.p2.dy - c.p1.dy) - ct;
    final at = c.p3.dy - c.p0.dy - ct - bt;

    return _solveCubic(at, bt, ct, d).where((t) => t >= 0 && t <= 1).toList();
  }

  /// Solve cubic equation at³ + bt² + ct + d = 0.
  static List<double> _solveCubic(double a, double b, double c, double d) {
    if (a.abs() < 1e-10) {
      // Degenerate to quadratic.
      return _solveQuadratic(b, c, d);
    }

    // Normalize.
    final p = (3 * a * c - b * b) / (3 * a * a);
    final q =
        (2 * b * b * b - 9 * a * b * c + 27 * a * a * d) / (27 * a * a * a);
    final disc = q * q / 4 + p * p * p / 27;

    final results = <double>[];
    final shift = -b / (3 * a);

    if (disc > 1e-10) {
      // One real root.
      final sqrtDisc = math.sqrt(disc);
      final u = _cbrt(-q / 2 + sqrtDisc);
      final v = _cbrt(-q / 2 - sqrtDisc);
      results.add(u + v + shift);
    } else if (disc.abs() <= 1e-10) {
      // Two real roots (one double).
      final u = _cbrt(-q / 2);
      results.add(2 * u + shift);
      results.add(-u + shift);
    } else {
      // Three real roots (Vieta's trigonometric).
      final r = math.sqrt(-p * p * p / 27);
      final theta = math.acos(-q / (2 * r)) / 3;
      final m = 2 * _cbrt(r);
      results.add(m * math.cos(theta) + shift);
      results.add(m * math.cos(theta - 2 * math.pi / 3) + shift);
      results.add(m * math.cos(theta - 4 * math.pi / 3) + shift);
    }

    return results;
  }

  static List<double> _solveQuadratic(double a, double b, double c) {
    if (a.abs() < 1e-10) {
      if (b.abs() < 1e-10) return [];
      return [-c / b];
    }
    final disc = b * b - 4 * a * c;
    if (disc < 0) return [];
    if (disc < 1e-10) return [-b / (2 * a)];
    final sqrtDisc = math.sqrt(disc);
    return [(-b + sqrtDisc) / (2 * a), (-b - sqrtDisc) / (2 * a)];
  }

  static double _cbrt(double x) =>
      x >= 0
          ? math.pow(x, 1.0 / 3.0).toDouble()
          : -math.pow(-x, 1.0 / 3.0).toDouble();

  // -------------------------------------------------------------------------
  // Winding number
  // -------------------------------------------------------------------------

  /// Compute the winding number of [point] relative to a closed boundary
  /// defined by a list of [CubicBezier] curves.
  ///
  /// Non-zero → inside. Zero → outside.
  static int windingNumber(Offset point, List<CubicBezier> boundary) {
    int winding = 0;

    for (final curve in boundary) {
      // Find horizontal ray intersections.
      final tValues = intersectCubicHorizontal(curve, point.dy);

      for (final t in tValues) {
        final x = curve.pointAt(t).dx;
        if (x > point.dx) {
          // Ray crossing to the right.
          final dy = curve.tangentAt(t).dy;
          if (dy > 0) {
            winding++;
          } else if (dy < 0) {
            winding--;
          }
        }
      }
    }

    return winding;
  }

  // -------------------------------------------------------------------------
  // Utility: convert straight segment to degenerate cubic
  // -------------------------------------------------------------------------

  /// Convert a straight line (p0 → p1) to a degenerate cubic Bézier.
  static CubicBezier lineToCubic(Offset p0, Offset p1) {
    return CubicBezier(
      p0,
      Offset.lerp(p0, p1, 1.0 / 3.0)!,
      Offset.lerp(p0, p1, 2.0 / 3.0)!,
      p1,
    );
  }

  /// Convert a quadratic Bézier (p0, cp, p1) to a cubic Bézier.
  static CubicBezier quadraticToCubic(Offset p0, Offset cp, Offset p1) {
    return CubicBezier(
      p0,
      Offset(p0.dx + 2 / 3 * (cp.dx - p0.dx), p0.dy + 2 / 3 * (cp.dy - p0.dy)),
      Offset(p1.dx + 2 / 3 * (cp.dx - p1.dx), p1.dy + 2 / 3 * (cp.dy - p1.dy)),
      p1,
    );
  }
}
