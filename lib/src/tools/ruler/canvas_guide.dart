import 'dart:ui';

/// Unique identifier for guide instances, enabling stable references
/// across frame-scoped and global guides.
int _nextGuideId = 0;

/// A guide line scoped to a specific [FrameNode] (artboard) or to the
/// global canvas.
///
/// Unlike the legacy parallel-list model (global guides only), [CanvasGuide]
/// carries its own identity, position, orientation, and optional frame scope.
///
/// ```dart
/// final guide = CanvasGuide(
///   position: 200,
///   isHorizontal: true,
///   frameId: 'artboard-1', // null for global
/// );
/// ```
class CanvasGuide {
  /// Auto-incrementing unique identifier.
  final String id;

  /// Position in canvas coordinates (Y for horizontal, X for vertical).
  double position;

  /// Whether this is a horizontal (Y-axis) or vertical (X-axis) guide.
  final bool isHorizontal;

  /// If non-null, this guide belongs to the frame with this ID.
  /// If null, it's a global canvas guide.
  String? frameId;

  /// Whether this guide is locked from being moved.
  bool locked;

  /// Custom color override (null = use theme default).
  Color? color;

  /// Optional label annotation.
  String? label;

  CanvasGuide({
    String? id,
    required this.position,
    required this.isHorizontal,
    this.frameId,
    this.locked = false,
    this.color,
    this.label,
  }) : id = id ?? 'guide_${_nextGuideId++}' {
    // Realign counter after deserialization to avoid ID collisions
    if (id != null && id.startsWith('guide_')) {
      final suffix = int.tryParse(id.substring(6));
      if (suffix != null && suffix >= _nextGuideId) {
        _nextGuideId = suffix + 1;
      }
    }
  }

  /// Create a deep copy.
  CanvasGuide copyWith({
    double? position,
    bool? isHorizontal,
    String? frameId,
    bool? locked,
    Color? color,
    String? label,
  }) {
    return CanvasGuide(
      id: id,
      position: position ?? this.position,
      isHorizontal: isHorizontal ?? this.isHorizontal,
      frameId: frameId ?? this.frameId,
      locked: locked ?? this.locked,
      color: color ?? this.color,
      label: label ?? this.label,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'pos': position,
    'isH': isHorizontal,
    if (frameId != null) 'frameId': frameId,
    'locked': locked,
    if (color != null) 'color': color!.toARGB32(),
    if (label != null) 'label': label,
  };

  factory CanvasGuide.fromJson(Map<String, dynamic> json) {
    return CanvasGuide(
      id: json['id'] as String?,
      position: (json['pos'] as num).toDouble(),
      isHorizontal: json['isH'] as bool,
      frameId: json['frameId'] as String?,
      locked: (json['locked'] as bool?) ?? false,
      color: json['color'] != null ? Color(json['color'] as int) : null,
      label: json['label'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is CanvasGuide && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
