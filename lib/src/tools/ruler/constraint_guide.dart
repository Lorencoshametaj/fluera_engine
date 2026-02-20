import 'dart:ui';

/// Which edge of a frame a constraint guide is bound to.
enum ConstraintEdge { left, right, top, bottom, centerX, centerY }

/// A guide that dynamically follows a frame's edge or center.
///
/// Unlike static guides, a [ConstraintGuide] re-computes its position
/// whenever the target frame moves or resizes.
///
/// ```dart
/// final guide = ConstraintGuide(
///   frameId: 'artboard-1',
///   edge: ConstraintEdge.left,
///   offset: 16, // 16px margin from left edge
/// );
/// final pos = guide.resolve(frameBounds); // returns actual X position
/// ```
class ConstraintGuide {
  /// Unique identifier.
  final String id;

  /// The frame this guide is constrained to.
  final String frameId;

  /// Which edge of the frame to follow.
  final ConstraintEdge edge;

  /// Offset in pixels from the edge (positive = inward).
  final double offset;

  /// Custom color override.
  Color? color;

  /// Optional label.
  String? label;

  static int _nextId = 0;

  ConstraintGuide({
    String? id,
    required this.frameId,
    required this.edge,
    this.offset = 0,
    this.color,
    this.label,
  }) : id = id ?? 'cguide_${_nextId++}' {
    // Realign counter after deserialization to avoid ID collisions
    if (id != null && id.startsWith('cguide_')) {
      final suffix = int.tryParse(id.substring(7));
      if (suffix != null && suffix >= _nextId) {
        _nextId = suffix + 1;
      }
    }
  }

  /// Whether this guide resolves to a horizontal line (Y-axis).
  bool get isHorizontal =>
      edge == ConstraintEdge.top ||
      edge == ConstraintEdge.bottom ||
      edge == ConstraintEdge.centerY;

  /// Resolve the absolute canvas position given the frame's bounds.
  ///
  /// Returns [double.nan] if the frame bounds are not available.
  double resolve(Rect frameBounds) {
    switch (edge) {
      case ConstraintEdge.left:
        return frameBounds.left + offset;
      case ConstraintEdge.right:
        return frameBounds.right - offset;
      case ConstraintEdge.top:
        return frameBounds.top + offset;
      case ConstraintEdge.bottom:
        return frameBounds.bottom - offset;
      case ConstraintEdge.centerX:
        return frameBounds.center.dx + offset;
      case ConstraintEdge.centerY:
        return frameBounds.center.dy + offset;
    }
  }

  ConstraintGuide copyWith({
    String? frameId,
    ConstraintEdge? edge,
    double? offset,
    Color? color,
    String? label,
  }) {
    return ConstraintGuide(
      id: id,
      frameId: frameId ?? this.frameId,
      edge: edge ?? this.edge,
      offset: offset ?? this.offset,
      color: color ?? this.color,
      label: label ?? this.label,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'frameId': frameId,
    'edge': edge.index,
    'offset': offset,
    if (color != null) 'color': color!.toARGB32(),
    if (label != null) 'label': label,
  };

  factory ConstraintGuide.fromJson(Map<String, dynamic> json) {
    return ConstraintGuide(
      id: json['id'] as String?,
      frameId: json['frameId'] as String,
      edge: ConstraintEdge.values[json['edge'] as int],
      offset: (json['offset'] as num?)?.toDouble() ?? 0,
      color: json['color'] != null ? Color(json['color'] as int) : null,
      label: json['label'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is ConstraintGuide && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
