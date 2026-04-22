// ============================================================================
// 🔖 SPATIAL BOOKMARK — Navigable metadata anchor for a canvas viewport
//
// Replaces SectionSummary (deprecated). A bookmark is a pure metadata anchor:
// no bounding box, no rendering on the canvas, no preset/template. Only a
// target viewport (cx, cy, zoom) and a human-readable name.
//
// Rationale: §22 Place Cells operate on position, not on rectangle membership.
// Canvas Sacro (Axiom I) forbids imposed templates. Bookmarks let the user
// "pin this view" after the zone has emerged, not before.
// ============================================================================

import 'dart:ui';

/// Navigable anchor to a specific viewport inside a canvas.
///
/// A [SpatialBookmark] is metadata only — it is never drawn on the canvas.
/// At satellite zoom (<30%) it may appear as a floating label; at any other
/// zoom level it is invisible. Its only purpose is to answer the question
/// "take me back to this view in <400ms" (Axiom IV, Doherty Threshold).
///
/// ```dart
/// final bookmark = SpatialBookmark(
///   id: 'bm_abc',
///   name: 'Termodinamica — Cap. 3',
///   cx: 1200.0,
///   cy: -400.0,
///   zoom: 1.0,
///   createdAt: DateTime.now(),
/// );
/// ```
class SpatialBookmark {
  /// Stable bookmark identifier.
  final String id;

  /// Human-readable name shown in Hub Sheet, minimap label, command palette.
  final String name;

  /// Target viewport center in canvas world space.
  final double cx;
  final double cy;

  /// Target viewport scale (1.0 = 100%).
  final double zoom;

  /// Optional ARGB tint used for the minimap label. Null = neutral.
  final int? color;

  /// Creation timestamp.
  final DateTime createdAt;

  /// Last time the bookmark was visited (jumped to). Null if never visited.
  final DateTime? lastVisitedAt;

  const SpatialBookmark({
    required this.id,
    required this.name,
    required this.cx,
    required this.cy,
    this.zoom = 1.0,
    this.color,
    required this.createdAt,
    this.lastVisitedAt,
  });

  /// Target center as an [Offset] in canvas world space.
  Offset get center => Offset(cx, cy);

  /// Label tint as a [Color]. Returns transparent if no color set.
  Color get labelColor =>
      color != null ? Color(color!) : const Color(0x00000000);

  SpatialBookmark copyWith({
    String? id,
    String? name,
    double? cx,
    double? cy,
    double? zoom,
    int? color,
    bool clearColor = false,
    DateTime? createdAt,
    DateTime? lastVisitedAt,
    bool clearLastVisitedAt = false,
  }) {
    return SpatialBookmark(
      id: id ?? this.id,
      name: name ?? this.name,
      cx: cx ?? this.cx,
      cy: cy ?? this.cy,
      zoom: zoom ?? this.zoom,
      color: clearColor ? null : (color ?? this.color),
      createdAt: createdAt ?? this.createdAt,
      lastVisitedAt: clearLastVisitedAt
          ? null
          : (lastVisitedAt ?? this.lastVisitedAt),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'cx': cx,
    'cy': cy,
    'zoom': zoom,
    if (color != null) 'color': color,
    'createdAt': createdAt.millisecondsSinceEpoch,
    if (lastVisitedAt != null)
      'lastVisitedAt': lastVisitedAt!.millisecondsSinceEpoch,
  };

  factory SpatialBookmark.fromJson(Map<String, dynamic> json) {
    return SpatialBookmark(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Bookmark',
      cx: (json['cx'] as num?)?.toDouble() ?? 0,
      cy: (json['cy'] as num?)?.toDouble() ?? 0,
      zoom: (json['zoom'] as num?)?.toDouble() ?? 1.0,
      color: json['color'] as int?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (json['createdAt'] as int?) ?? 0,
      ),
      lastVisitedAt: json['lastVisitedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['lastVisitedAt'] as int)
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpatialBookmark &&
          id == other.id &&
          name == other.name &&
          cx == other.cx &&
          cy == other.cy &&
          zoom == other.zoom &&
          color == other.color &&
          createdAt == other.createdAt &&
          lastVisitedAt == other.lastVisitedAt;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    cx,
    cy,
    zoom,
    color,
    createdAt,
    lastVisitedAt,
  );

  @override
  String toString() =>
      'SpatialBookmark($name @ ($cx, $cy) zoom=$zoom)';
}
