import 'dart:ui';

/// 📌 SPATIAL BOOKMARK — A student-placed pin on a specific canvas position.
///
/// Pedagogical contract (§1972-1977):
///   "Lo studente può piazzare segnalibri in punti specifici del canvas —
///    posizioni di navigazione rapida verso zone importanti. Come segnalibri
///    in un libro, ma spaziali."
///
/// Bookmarks are *navigation aids only*: they don't modify content, don't
/// auto-arrange, and are never proposed by the system (§1977). The student
/// alone decides what to mark and how to label it.
///
/// SERIALIZATION: hand-rolled toJson/fromJson (no codegen). Persisted as
/// part of a JSON list under KV key `bookmarks_$canvasId`.
class SpatialBookmark {
  /// Stable identifier — `bm_<microseconds>_<rand>`. Equality is by id.
  final String id;

  /// Human-readable label. Defaults to a token derived from the nearest
  /// cluster's handwriting; the student can override at creation time.
  final String label;

  /// Position in world (canvas) coordinates.
  final Offset canvasPosition;

  /// Zoom scale at the moment the bookmark was saved. The "go to bookmark"
  /// camera animation uses this as a target so the student lands at the
  /// same level of detail they had when they cared enough to save it.
  final double scale;

  /// Wall-clock creation time, ms since epoch.
  final int createdAtMs;

  /// Last visit time. Null if the bookmark has never been navigated to
  /// since creation. Drives LRU eviction when [maxBookmarksPerCanvas] is
  /// exceeded — never-visited entries are evicted before frequently-used
  /// ones, then by oldest createdAt.
  final int? lastVisitedAtMs;

  const SpatialBookmark({
    required this.id,
    required this.label,
    required this.canvasPosition,
    required this.scale,
    required this.createdAtMs,
    this.lastVisitedAtMs,
  });

  SpatialBookmark copyWith({
    String? label,
    int? lastVisitedAtMs,
  }) {
    return SpatialBookmark(
      id: id,
      label: label ?? this.label,
      canvasPosition: canvasPosition,
      scale: scale,
      createdAtMs: createdAtMs,
      lastVisitedAtMs: lastVisitedAtMs ?? this.lastVisitedAtMs,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'x': canvasPosition.dx,
        'y': canvasPosition.dy,
        'scale': scale,
        'createdAtMs': createdAtMs,
        if (lastVisitedAtMs != null) 'lastVisitedAtMs': lastVisitedAtMs,
      };

  factory SpatialBookmark.fromJson(Map<String, dynamic> json) {
    return SpatialBookmark(
      id: json['id'] as String,
      label: (json['label'] as String?) ?? '',
      canvasPosition: Offset(
        (json['x'] as num?)?.toDouble() ?? 0.0,
        (json['y'] as num?)?.toDouble() ?? 0.0,
      ),
      scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
      createdAtMs:
          (json['createdAtMs'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
      lastVisitedAtMs: json['lastVisitedAtMs'] as int?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is SpatialBookmark && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'SpatialBookmark($id, "$label", $canvasPosition @${scale.toStringAsFixed(2)})';
}
