import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';

// =============================================================================
// 🔄 WARP MESH — Deformation grid for Transform Warp
//
// An NxM grid of control points. Each point has an original position and a
// displaced position. The mesh maps source UVs → deformed UVs via bilinear
// interpolation within each cell.
// =============================================================================

/// A single control point in the warp mesh.
class WarpControlPoint {
  /// Original (undeformed) position in canvas coordinates.
  final Offset original;

  /// Current (deformed) position in canvas coordinates.
  Offset displaced;

  WarpControlPoint({required this.original, Offset? displaced})
      : displaced = displaced ?? original;

  /// The displacement vector from original to current position.
  Offset get displacement => displaced - original;

  /// Reset to original position.
  void reset() => displaced = original;

  Map<String, dynamic> toJson() => {
        'ox': original.dx,
        'oy': original.dy,
        'dx': displaced.dx,
        'dy': displaced.dy,
      };

  factory WarpControlPoint.fromJson(Map<String, dynamic> json) {
    return WarpControlPoint(
      original: Offset(
        (json['ox'] as num).toDouble(),
        (json['oy'] as num).toDouble(),
      ),
      displaced: Offset(
        (json['dx'] as num).toDouble(),
        (json['dy'] as num).toDouble(),
      ),
    );
  }
}

/// NxM warp mesh for structured deformation.
class WarpMesh {
  /// Number of columns in the mesh grid.
  final int columns;

  /// Number of rows in the mesh grid.
  final int rows;

  /// The bounding rect of the original (undeformed) mesh.
  final Rect bounds;

  /// Control points stored row-major: [row * columns + col].
  final List<WarpControlPoint> points;

  WarpMesh({
    required this.columns,
    required this.rows,
    required this.bounds,
  }) : points = List.generate(
          rows * columns,
          (i) {
            final col = i % columns;
            final row = i ~/ columns;
            return WarpControlPoint(
              original: Offset(
                bounds.left + col * bounds.width / (columns - 1),
                bounds.top + row * bounds.height / (rows - 1),
              ),
            );
          },
        );

  WarpMesh._({
    required this.columns,
    required this.rows,
    required this.bounds,
    required this.points,
  });

  /// Get control point at (row, col).
  WarpControlPoint pointAt(int row, int col) => points[row * columns + col];

  /// Move a control point to a new position.
  void movePoint(int row, int col, Offset newPosition) {
    points[row * columns + col].displaced = newPosition;
  }

  /// Reset all control points to their original positions.
  void reset() {
    for (final p in points) {
      p.reset();
    }
  }

  /// Find the mesh cell containing a point and return interpolated UV.
  ///
  /// Returns null if the point is outside the mesh.
  Offset? inverseMap(Offset point) {
    for (int row = 0; row < rows - 1; row++) {
      for (int col = 0; col < columns - 1; col++) {
        final tl = pointAt(row, col).displaced;
        final tr = pointAt(row, col + 1).displaced;
        final bl = pointAt(row + 1, col).displaced;
        final br = pointAt(row + 1, col + 1).displaced;

        // Check if point is inside this quad (approximate with AABB first)
        final minX = math.min(math.min(tl.dx, tr.dx), math.min(bl.dx, br.dx));
        final maxX = math.max(math.max(tl.dx, tr.dx), math.max(bl.dx, br.dx));
        final minY = math.min(math.min(tl.dy, tr.dy), math.min(bl.dy, br.dy));
        final maxY = math.max(math.max(tl.dy, tr.dy), math.max(bl.dy, br.dy));

        if (point.dx < minX || point.dx > maxX ||
            point.dy < minY || point.dy > maxY) {
          continue;
        }

        // Bilinear inverse: solve for (u, v) such that
        // P = (1-v)*((1-u)*TL + u*TR) + v*((1-u)*BL + u*BR)
        // Use iterative Newton's method
        final uv = _inverseBilinear(point, tl, tr, bl, br);
        if (uv != null) {
          // Map local UV to global texture UV
          final globalU =
              (col + uv.dx) / (columns - 1);
          final globalV =
              (row + uv.dy) / (rows - 1);
          return Offset(globalU, globalV);
        }
      }
    }
    return null;
  }

  /// Forward mapping: map a UV coordinate through the mesh to a deformed position.
  Offset forwardMap(Offset uv) {
    final col = (uv.dx * (columns - 1)).clamp(0.0, columns - 2.0);
    final row = (uv.dy * (rows - 1)).clamp(0.0, rows - 2.0);
    final ci = col.floor();
    final ri = row.floor();
    final u = col - ci;
    final v = row - ri;

    final tl = pointAt(ri, ci).displaced;
    final tr = pointAt(ri, ci + 1).displaced;
    final bl = pointAt(ri + 1, ci).displaced;
    final br = pointAt(ri + 1, ci + 1).displaced;

    return Offset(
      (1 - v) * ((1 - u) * tl.dx + u * tr.dx) +
          v * ((1 - u) * bl.dx + u * br.dx),
      (1 - v) * ((1 - u) * tl.dy + u * tr.dy) +
          v * ((1 - u) * bl.dy + u * br.dy),
    );
  }

  /// Flatten mesh to Float32List for GPU upload.
  /// Format: [origX, origY, dispX, dispY] × (rows * columns)
  Float32List toFloat32List() {
    final data = Float32List(points.length * 4);
    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      data[i * 4] = p.original.dx;
      data[i * 4 + 1] = p.original.dy;
      data[i * 4 + 2] = p.displaced.dx;
      data[i * 4 + 3] = p.displaced.dy;
    }
    return data;
  }

  /// Find the closest control point to a given screen position.
  /// Returns (row, col) or null if no point is within [threshold].
  ({int row, int col})? findClosestPoint(
    Offset position, {
    double threshold = 24.0,
  }) {
    double bestDist = threshold;
    int bestRow = -1, bestCol = -1;

    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < columns; col++) {
        final dist = (pointAt(row, col).displaced - position).distance;
        if (dist < bestDist) {
          bestDist = dist;
          bestRow = row;
          bestCol = col;
        }
      }
    }

    if (bestRow < 0) return null;
    return (row: bestRow, col: bestCol);
  }

  Map<String, dynamic> toJson() => {
        'columns': columns,
        'rows': rows,
        'bounds': {
          'left': bounds.left,
          'top': bounds.top,
          'right': bounds.right,
          'bottom': bounds.bottom,
        },
        'points': points.map((p) => p.toJson()).toList(),
      };

  factory WarpMesh.fromJson(Map<String, dynamic> json) {
    final b = json['bounds'] as Map<String, dynamic>;
    return WarpMesh._(
      columns: json['columns'] as int,
      rows: json['rows'] as int,
      bounds: Rect.fromLTRB(
        (b['left'] as num).toDouble(),
        (b['top'] as num).toDouble(),
        (b['right'] as num).toDouble(),
        (b['bottom'] as num).toDouble(),
      ),
      points: (json['points'] as List)
          .map((p) =>
              WarpControlPoint.fromJson(p as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Newton's method for inverse bilinear interpolation.
  static Offset? _inverseBilinear(
    Offset p,
    Offset tl,
    Offset tr,
    Offset bl,
    Offset br,
  ) {
    double u = 0.5, v = 0.5;

    for (int iter = 0; iter < 8; iter++) {
      // Forward eval
      final fx = (1 - v) * ((1 - u) * tl.dx + u * tr.dx) +
          v * ((1 - u) * bl.dx + u * br.dx) -
          p.dx;
      final fy = (1 - v) * ((1 - u) * tl.dy + u * tr.dy) +
          v * ((1 - u) * bl.dy + u * br.dy) -
          p.dy;

      if (fx.abs() < 0.001 && fy.abs() < 0.001) {
        if (u >= -0.01 && u <= 1.01 && v >= -0.01 && v <= 1.01) {
          return Offset(u.clamp(0.0, 1.0), v.clamp(0.0, 1.0));
        }
        return null;
      }

      // Jacobian
      final dFxDu = (1 - v) * (tr.dx - tl.dx) + v * (br.dx - bl.dx);
      final dFxDv = (1 - u) * (bl.dx - tl.dx) + u * (br.dx - tr.dx);
      final dFyDu = (1 - v) * (tr.dy - tl.dy) + v * (br.dy - bl.dy);
      final dFyDv = (1 - u) * (bl.dy - tl.dy) + u * (br.dy - tr.dy);

      final det = dFxDu * dFyDv - dFxDv * dFyDu;
      if (det.abs() < 1e-10) return null;

      u -= (dFyDv * fx - dFxDv * fy) / det;
      v -= (dFxDu * fy - dFyDu * fx) / det;
    }

    return null;
  }
}

// =============================================================================
// 🌊 DISPLACEMENT FIELD — Per-pixel displacement for Liquify
//
// A 2D grid of displacement vectors (dx, dy). Applied to a source image by
// looking up source pixel at (x + dx, y + dy) for each output pixel.
// =============================================================================

/// Per-pixel displacement field for Liquify deformation.
class DisplacementField {
  /// Width of the field in pixels.
  final int width;

  /// Height of the field in pixels.
  final int height;

  /// Displacement data: interleaved [dx0, dy0, dx1, dy1, ...].
  /// Length = width * height * 2.
  final Float32List data;

  DisplacementField({required this.width, required this.height})
      : data = Float32List(width * height * 2);

  DisplacementField._({
    required this.width,
    required this.height,
    required this.data,
  });

  /// Get displacement at pixel (x, y).
  Offset getDisplacement(int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= height) return Offset.zero;
    final idx = (y * width + x) * 2;
    return Offset(data[idx], data[idx + 1]);
  }

  /// Apply a circular push at (cx, cy) with the given direction,
  /// radius, and strength. Uses Gaussian falloff.
  void applyPush({
    required double cx,
    required double cy,
    required double dx,
    required double dy,
    required double radius,
    required double strength,
  }) {
    final r2 = radius * radius;
    final sigma2 = r2 * 0.5; // Gaussian sigma²

    final minX = math.max(0, (cx - radius).floor());
    final maxX = math.min(width - 1, (cx + radius).ceil());
    final minY = math.max(0, (cy - radius).floor());
    final maxY = math.min(height - 1, (cy + radius).ceil());

    for (int y = minY; y <= maxY; y++) {
      for (int x = minX; x <= maxX; x++) {
        final distX = x - cx;
        final distY = y - cy;
        final dist2 = distX * distX + distY * distY;

        if (dist2 > r2) continue;

        // Gaussian falloff
        final falloff = math.exp(-dist2 / (2.0 * sigma2));
        final factor = strength * falloff;

        final idx = (y * width + x) * 2;
        data[idx] += dx * factor;
        data[idx + 1] += dy * factor;
      }
    }
  }

  /// Apply a twirl effect at (cx, cy) — rotates pixels around the center.
  void applyTwirl({
    required double cx,
    required double cy,
    required double radius,
    required double angle,
    required double strength,
  }) {
    final r2 = radius * radius;

    final minX = math.max(0, (cx - radius).floor());
    final maxX = math.min(width - 1, (cx + radius).ceil());
    final minY = math.max(0, (cy - radius).floor());
    final maxY = math.min(height - 1, (cy + radius).ceil());

    for (int y = minY; y <= maxY; y++) {
      for (int x = minX; x <= maxX; x++) {
        final relX = x - cx;
        final relY = y - cy;
        final dist2 = relX * relX + relY * relY;

        if (dist2 > r2) continue;

        final dist = math.sqrt(dist2);
        final falloff = 1.0 - (dist / radius);
        final rotAngle = angle * strength * falloff * falloff;

        final cosA = math.cos(rotAngle);
        final sinA = math.sin(rotAngle);

        final rotX = relX * cosA - relY * sinA;
        final rotY = relX * sinA + relY * cosA;

        final idx = (y * width + x) * 2;
        data[idx] += rotX - relX;
        data[idx + 1] += rotY - relY;
      }
    }
  }

  /// Apply an expand (bloat) or pinch effect at (cx, cy).
  /// Positive strength = expand, negative = pinch.
  void applyExpandPinch({
    required double cx,
    required double cy,
    required double radius,
    required double strength,
  }) {
    final r2 = radius * radius;

    final minX = math.max(0, (cx - radius).floor());
    final maxX = math.min(width - 1, (cx + radius).ceil());
    final minY = math.max(0, (cy - radius).floor());
    final maxY = math.min(height - 1, (cy + radius).ceil());

    for (int y = minY; y <= maxY; y++) {
      for (int x = minX; x <= maxX; x++) {
        final relX = x - cx;
        final relY = y - cy;
        final dist2 = relX * relX + relY * relY;

        if (dist2 > r2) continue;

        final dist = math.sqrt(dist2);
        if (dist < 0.001) continue;

        final falloff = 1.0 - (dist / radius);
        final factor = strength * falloff * falloff;

        // Expand: move pixels away from center
        // Pinch: move pixels toward center
        final idx = (y * width + x) * 2;
        data[idx] += (relX / dist) * factor * radius * 0.3;
        data[idx + 1] += (relY / dist) * factor * radius * 0.3;
      }
    }
  }

  /// Clear all displacements.
  void clear() {
    data.fillRange(0, data.length, 0.0);
  }

  /// Create a snapshot for undo.
  DisplacementField snapshot() {
    return DisplacementField._(
      width: width,
      height: height,
      data: Float32List.fromList(data),
    );
  }

  Map<String, dynamic> toJson() => {
        'width': width,
        'height': height,
        'data': data.toList(),
      };

  factory DisplacementField.fromJson(Map<String, dynamic> json) {
    return DisplacementField._(
      width: json['width'] as int,
      height: json['height'] as int,
      data: Float32List.fromList(
        (json['data'] as List).map((e) => (e as num).toDouble()).toList(),
      ),
    );
  }
}

/// Mode for the Liquify tool brush.
enum LiquifyMode {
  /// Push pixels in the drag direction.
  push,

  /// Twirl pixels clockwise around the brush center.
  twirlCW,

  /// Twirl pixels counter-clockwise.
  twirlCCW,

  /// Expand (bloat) pixels outward from center.
  expand,

  /// Pinch pixels inward toward center.
  pinch,

  /// Reconstruct: restore pixels toward original position.
  reconstruct,
}
