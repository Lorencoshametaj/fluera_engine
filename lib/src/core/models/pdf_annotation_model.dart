import 'dart:ui';

// =============================================================================
// 🏷️ PDF STRUCTURED ANNOTATIONS — Highlight, Underline, Sticky Note
// =============================================================================

/// Types of structured PDF annotations.
///
/// Unlike stroke-based annotations (which are freehand drawings),
/// structured annotations are positioned relative to text content
/// and have well-defined semantics.
enum PdfAnnotationType {
  /// Semi-transparent colored rectangle over text.
  highlight,

  /// Colored line drawn beneath a text span.
  underline,

  /// Positioned note icon with expandable text content.
  stickyNote,
}

/// 📝 A structured annotation on a PDF page.
///
/// Immutable data model following the engine's copyWith pattern.
/// Each annotation is positioned in page-local coordinates (PDF points)
/// and belongs to exactly one page.
///
/// DESIGN PRINCIPLES:
/// - Immutable with copyWith pattern for clean state management
/// - Fully serializable with defensive fromJson fallbacks
/// - Value equality via == and hashCode
/// - Separate from stroke-based annotations (which use String IDs)
class PdfAnnotation {
  /// Unique identifier for this annotation.
  final String id;

  /// Type of annotation (highlight, underline, sticky note).
  final PdfAnnotationType type;

  /// Page index (0-based) this annotation belongs to.
  final int pageIndex;

  /// Bounding rect in page-local coordinates (PDF points).
  final Rect rect;

  /// Annotation color (ARGB).
  final Color color;

  /// Optional text content (used for sticky notes, comment text).
  final String? text;

  /// Microseconds since epoch — creation time.
  final int createdAt;

  /// Microseconds since epoch — last modification time.
  final int lastModifiedAt;

  const PdfAnnotation({
    required this.id,
    required this.type,
    required this.pageIndex,
    required this.rect,
    this.color = const Color(0x80FFEB3B), // Yellow highlight default
    this.text,
    int? createdAt,
    int? lastModifiedAt,
  }) : createdAt = createdAt ?? 0,
       lastModifiedAt = lastModifiedAt ?? 0;

  // ---------------------------------------------------------------------------
  // CopyWith
  // ---------------------------------------------------------------------------

  PdfAnnotation copyWith({
    String? id,
    PdfAnnotationType? type,
    int? pageIndex,
    Rect? rect,
    Color? color,
    String? text,
    bool clearText = false,
    int? createdAt,
    int? lastModifiedAt,
  }) {
    return PdfAnnotation(
      id: id ?? this.id,
      type: type ?? this.type,
      pageIndex: pageIndex ?? this.pageIndex,
      rect: rect ?? this.rect,
      color: color ?? this.color,
      text: clearText ? null : (text ?? this.text),
      createdAt: createdAt ?? this.createdAt,
      lastModifiedAt: lastModifiedAt ?? this.lastModifiedAt,
    );
  }

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'pageIndex': pageIndex,
    'rect': {
      'left': rect.left,
      'top': rect.top,
      'right': rect.right,
      'bottom': rect.bottom,
    },
    'color': color.toARGB32(),
    if (text != null) 'text': text,
    'createdAt': createdAt,
    'lastModifiedAt': lastModifiedAt,
  };

  factory PdfAnnotation.fromJson(Map<String, dynamic> json) {
    // Defensive type parsing
    PdfAnnotationType type = PdfAnnotationType.highlight;
    final typeStr = json['type'] as String?;
    if (typeStr != null) {
      type = PdfAnnotationType.values.firstWhere(
        (t) => t.name == typeStr,
        orElse: () => PdfAnnotationType.highlight,
      );
    }

    // Defensive rect parsing
    Rect rect = Rect.zero;
    if (json['rect'] is Map<String, dynamic>) {
      final r = json['rect'] as Map<String, dynamic>;
      rect = Rect.fromLTRB(
        (r['left'] as num?)?.toDouble() ?? 0,
        (r['top'] as num?)?.toDouble() ?? 0,
        (r['right'] as num?)?.toDouble() ?? 0,
        (r['bottom'] as num?)?.toDouble() ?? 0,
      );
    }

    return PdfAnnotation(
      id: json['id'] as String? ?? '',
      type: type,
      pageIndex: (json['pageIndex'] as num?)?.toInt() ?? 0,
      rect: rect,
      color: Color((json['color'] as num?)?.toInt() ?? 0x80FFEB3B),
      text: json['text'] as String?,
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      lastModifiedAt: (json['lastModifiedAt'] as num?)?.toInt() ?? 0,
    );
  }

  // ---------------------------------------------------------------------------
  // Equality
  // ---------------------------------------------------------------------------

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PdfAnnotation &&
          id == other.id &&
          type == other.type &&
          pageIndex == other.pageIndex &&
          rect == other.rect &&
          color == other.color &&
          text == other.text &&
          createdAt == other.createdAt &&
          lastModifiedAt == other.lastModifiedAt;

  @override
  int get hashCode => Object.hash(
    id,
    type,
    pageIndex,
    rect,
    color,
    text,
    createdAt,
    lastModifiedAt,
  );

  @override
  String toString() => 'PdfAnnotation($id, ${type.name}, page: $pageIndex)';
}

/// Default colors for each annotation type.
extension PdfAnnotationTypeDefaults on PdfAnnotationType {
  /// Default color for this annotation type.
  Color get defaultColor {
    switch (this) {
      case PdfAnnotationType.highlight:
        return const Color(0x80FFEB3B); // Semi-transparent yellow
      case PdfAnnotationType.underline:
        return const Color(0xFFE53935); // Red
      case PdfAnnotationType.stickyNote:
        return const Color(0xFFFFF176); // Light yellow
    }
  }

  /// Display label for UI.
  String get label {
    switch (this) {
      case PdfAnnotationType.highlight:
        return 'Highlight';
      case PdfAnnotationType.underline:
        return 'Underline';
      case PdfAnnotationType.stickyNote:
        return 'Note';
    }
  }

  /// Material icon for UI.
  String get iconName {
    switch (this) {
      case PdfAnnotationType.highlight:
        return 'highlight';
      case PdfAnnotationType.underline:
        return 'format_underlined';
      case PdfAnnotationType.stickyNote:
        return 'sticky_note_2';
    }
  }
}
