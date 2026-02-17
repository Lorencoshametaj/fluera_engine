import 'dart:ui';
import './vector_path.dart';

/// Type of anchor point behavior when handles are adjusted.
enum AnchorType {
  /// Handles move independently.
  corner,

  /// Handles are always colinear (opposite direction, independent lengths).
  smooth,

  /// Handles are colinear AND same length (fully symmetric).
  symmetric,
}

/// An interactive control point on a [VectorPath].
///
/// Each anchor corresponds to a segment endpoint. The [handleIn] and
/// [handleOut] offsets are *relative* to [position] and control the
/// tangent direction of incoming/outgoing curves.
///
/// ```
///   handleIn ←───● position ───→ handleOut
/// ```
class AnchorPoint {
  /// Position of the anchor in local path coordinates.
  Offset position;

  /// Incoming tangent handle (relative to [position]).
  /// Null for a corner with no incoming curve.
  Offset? handleIn;

  /// Outgoing tangent handle (relative to [position]).
  /// Null for a corner with no outgoing curve.
  Offset? handleOut;

  /// How handles relate to each other.
  AnchorType type;

  AnchorPoint({
    required this.position,
    this.handleIn,
    this.handleOut,
    this.type = AnchorType.corner,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnchorPoint &&
          position == other.position &&
          handleIn == other.handleIn &&
          handleOut == other.handleOut &&
          type == other.type;

  @override
  int get hashCode => Object.hash(position, handleIn, handleOut, type);

  /// Whether this anchor has at least one handle (i.e. produces curves).
  bool get hasCurve => handleIn != null || handleOut != null;

  /// Absolute position of the incoming handle.
  Offset? get handleInAbsolute =>
      handleIn != null ? position + handleIn! : null;

  /// Absolute position of the outgoing handle.
  Offset? get handleOutAbsolute =>
      handleOut != null ? position + handleOut! : null;

  // -------------------------------------------------------------------------
  // Serialization
  // -------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'x': position.dx,
    'y': position.dy,
    'type': type.name,
    if (handleIn != null) 'hix': handleIn!.dx,
    if (handleIn != null) 'hiy': handleIn!.dy,
    if (handleOut != null) 'hox': handleOut!.dx,
    if (handleOut != null) 'hoy': handleOut!.dy,
  };

  factory AnchorPoint.fromJson(Map<String, dynamic> json) {
    return AnchorPoint(
      position: Offset(
        (json['x'] as num).toDouble(),
        (json['y'] as num).toDouble(),
      ),
      type: AnchorType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => AnchorType.corner,
      ),
      handleIn:
          json.containsKey('hix')
              ? Offset(
                (json['hix'] as num).toDouble(),
                (json['hiy'] as num).toDouble(),
              )
              : null,
      handleOut:
          json.containsKey('hox')
              ? Offset(
                (json['hox'] as num).toDouble(),
                (json['hoy'] as num).toDouble(),
              )
              : null,
    );
  }

  // -------------------------------------------------------------------------
  // Conversion helpers
  // -------------------------------------------------------------------------

  /// Convert a list of [AnchorPoint]s to a [VectorPath].
  ///
  /// Adjacent anchors with handles produce cubic Bézier curves.
  /// Adjacent anchors without handles produce straight lines.
  static VectorPath toVectorPath(
    List<AnchorPoint> anchors, {
    bool closed = false,
  }) {
    if (anchors.isEmpty) return VectorPath(segments: []);

    final path = VectorPath.moveTo(anchors.first.position);

    for (int i = 1; i < anchors.length; i++) {
      final prev = anchors[i - 1];
      final curr = anchors[i];
      _addSegment(path, prev, curr);
    }

    // Close: connect last anchor back to first.
    if (closed && anchors.length > 1) {
      _addSegment(path, anchors.last, anchors.first);
      path.close();
    }

    return path;
  }

  /// Extract [AnchorPoint]s from a [VectorPath].
  ///
  /// This is the inverse of [toVectorPath]: it examines each segment
  /// to reconstruct anchor positions and handles.
  static List<AnchorPoint> fromVectorPath(VectorPath vectorPath) {
    final anchors = <AnchorPoint>[];
    if (vectorPath.segments.isEmpty) return anchors;

    for (int i = 0; i < vectorPath.segments.length; i++) {
      final seg = vectorPath.segments[i];

      if (seg is MoveSegment) {
        anchors.add(AnchorPoint(position: seg.endPoint));
      } else if (seg is LineSegment) {
        anchors.add(AnchorPoint(position: seg.endPoint));
      } else if (seg is CubicSegment) {
        // Set handleOut on the previous anchor.
        if (anchors.isNotEmpty) {
          final prev = anchors.last;
          prev.handleOut = seg.controlPoint1 - prev.position;
          prev.type = AnchorType.smooth;
        }
        // Create anchor with handleIn.
        anchors.add(
          AnchorPoint(
            position: seg.endPoint,
            handleIn: seg.controlPoint2 - seg.endPoint,
            type: AnchorType.smooth,
          ),
        );
      } else if (seg is QuadSegment) {
        // Approximate: treat quad control point as shared handle.
        if (anchors.isNotEmpty) {
          final prev = anchors.last;
          prev.handleOut = seg.controlPoint - prev.position;
        }
        anchors.add(
          AnchorPoint(
            position: seg.endPoint,
            handleIn: seg.controlPoint - seg.endPoint,
            type: AnchorType.smooth,
          ),
        );
      }
    }

    return anchors;
  }

  /// Helper: add a segment between two anchors based on their handles.
  static void _addSegment(VectorPath path, AnchorPoint from, AnchorPoint to) {
    final cp1 = from.handleOutAbsolute;
    final cp2 = to.handleInAbsolute;

    if (cp1 != null && cp2 != null) {
      // Both have handles → cubic Bézier.
      path.cubicTo(
        cp1.dx,
        cp1.dy,
        cp2.dx,
        cp2.dy,
        to.position.dx,
        to.position.dy,
      );
    } else if (cp1 != null) {
      // Only outgoing handle → quadratic.
      path.quadTo(cp1.dx, cp1.dy, to.position.dx, to.position.dy);
    } else if (cp2 != null) {
      // Only incoming handle → quadratic.
      path.quadTo(cp2.dx, cp2.dy, to.position.dx, to.position.dy);
    } else {
      // No handles → straight line.
      path.lineTo(to.position.dx, to.position.dy);
    }
  }
}
