/// 🎲 TRANSFORM 3D — Perspective and 3D rotation for canvas nodes.
///
/// Extends the 2D transform system with rotateX, rotateY, and perspective.
///
/// ```dart
/// final t = Transform3D(
///   rotateX: 15,  // degrees
///   rotateY: -10,
///   perspective: 800,
/// );
/// final matrix = t.toMatrix4(); // Apply to CanvasNode.localTransform
/// ```
library;

import 'dart:math' as math;
import 'package:flutter/material.dart' show Matrix4;

// =============================================================================
// TRANSFORM 3D
// =============================================================================

/// 3D transform parameters for a canvas node.
///
/// All rotations are in degrees. The [perspective] value controls
/// the intensity of the perspective effect (larger = less distortion).
class Transform3D {
  /// Rotation around the X axis (degrees, positive = top tilts away).
  final double rotateX;

  /// Rotation around the Y axis (degrees, positive = right tilts away).
  final double rotateY;

  /// Rotation around the Z axis (degrees, same as 2D rotation).
  final double rotateZ;

  /// Perspective distance in pixels. 0 = no perspective.
  ///
  /// Typical values: 400–1200. Smaller = more extreme perspective.
  final double perspective;

  /// 3D translation offset along Z axis.
  final double translateZ;

  /// Transform origin as fraction of node size (0.5, 0.5 = center).
  final double originX;
  final double originY;

  const Transform3D({
    this.rotateX = 0,
    this.rotateY = 0,
    this.rotateZ = 0,
    this.perspective = 0,
    this.translateZ = 0,
    this.originX = 0.5,
    this.originY = 0.5,
  });

  /// Whether this transform has any 3D effect.
  bool get hasEffect =>
      rotateX != 0 ||
      rotateY != 0 ||
      rotateZ != 0 ||
      perspective != 0 ||
      translateZ != 0;

  /// Whether this is an identity transform (no effect).
  bool get isIdentity => !hasEffect;

  /// Convert degrees to radians.
  static double _rad(double degrees) => degrees * math.pi / 180;

  /// Generate a [Matrix4] from the 3D parameters.
  ///
  /// If [nodeWidth] and [nodeHeight] are provided, the transform origin
  /// is applied relative to those dimensions.
  Matrix4 toMatrix4({double nodeWidth = 0, double nodeHeight = 0}) {
    final m = Matrix4.identity();

    // Apply transform origin offset.
    final ox = nodeWidth * originX;
    final oy = nodeHeight * originY;
    if (ox != 0 || oy != 0) {
      // ignore: deprecated_member_use
      m.translate(ox, oy, 0.0);
    }

    // Apply perspective.
    if (perspective > 0) {
      m.setEntry(3, 2, -1.0 / perspective);
    }

    // Apply rotations.
    if (rotateX != 0) m.rotateX(_rad(rotateX));
    if (rotateY != 0) m.rotateY(_rad(rotateY));
    if (rotateZ != 0) m.rotateZ(_rad(rotateZ));

    // Apply Z translation.
    // ignore: deprecated_member_use
    if (translateZ != 0) m.translate(0.0, 0.0, translateZ);

    // Undo transform origin offset.
    if (ox != 0 || oy != 0) {
      // ignore: deprecated_member_use
      m.translate(-ox, -oy, 0.0);
    }

    return m;
  }

  /// Create a copy with modified parameters.
  Transform3D copyWith({
    double? rotateX,
    double? rotateY,
    double? rotateZ,
    double? perspective,
    double? translateZ,
    double? originX,
    double? originY,
  }) => Transform3D(
    rotateX: rotateX ?? this.rotateX,
    rotateY: rotateY ?? this.rotateY,
    rotateZ: rotateZ ?? this.rotateZ,
    perspective: perspective ?? this.perspective,
    translateZ: translateZ ?? this.translateZ,
    originX: originX ?? this.originX,
    originY: originY ?? this.originY,
  );

  /// Linearly interpolate between two 3D transforms.
  static Transform3D lerp(Transform3D a, Transform3D b, double t) =>
      Transform3D(
        rotateX: a.rotateX + (b.rotateX - a.rotateX) * t,
        rotateY: a.rotateY + (b.rotateY - a.rotateY) * t,
        rotateZ: a.rotateZ + (b.rotateZ - a.rotateZ) * t,
        perspective: a.perspective + (b.perspective - a.perspective) * t,
        translateZ: a.translateZ + (b.translateZ - a.translateZ) * t,
        originX: a.originX + (b.originX - a.originX) * t,
        originY: a.originY + (b.originY - a.originY) * t,
      );

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    if (rotateX != 0) 'rotateX': rotateX,
    if (rotateY != 0) 'rotateY': rotateY,
    if (rotateZ != 0) 'rotateZ': rotateZ,
    if (perspective != 0) 'perspective': perspective,
    if (translateZ != 0) 'translateZ': translateZ,
    if (originX != 0.5) 'originX': originX,
    if (originY != 0.5) 'originY': originY,
  };

  factory Transform3D.fromJson(Map<String, dynamic> json) => Transform3D(
    rotateX: (json['rotateX'] as num?)?.toDouble() ?? 0,
    rotateY: (json['rotateY'] as num?)?.toDouble() ?? 0,
    rotateZ: (json['rotateZ'] as num?)?.toDouble() ?? 0,
    perspective: (json['perspective'] as num?)?.toDouble() ?? 0,
    translateZ: (json['translateZ'] as num?)?.toDouble() ?? 0,
    originX: (json['originX'] as num?)?.toDouble() ?? 0.5,
    originY: (json['originY'] as num?)?.toDouble() ?? 0.5,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Transform3D &&
          rotateX == other.rotateX &&
          rotateY == other.rotateY &&
          rotateZ == other.rotateZ &&
          perspective == other.perspective &&
          translateZ == other.translateZ &&
          originX == other.originX &&
          originY == other.originY;

  @override
  int get hashCode => Object.hash(
    rotateX,
    rotateY,
    rotateZ,
    perspective,
    translateZ,
    originX,
    originY,
  );

  @override
  String toString() =>
      'Transform3D(rX: $rotateX°, rY: $rotateY°, rZ: $rotateZ°, p: $perspective)';
}
