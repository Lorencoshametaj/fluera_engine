import 'dart:ui';

/// 📄 A positioned text fragment extracted from a PDF page.
///
/// Used by the text geometry layer (Layer 5) to enable text selection
/// on rasterized PDF pages. Each rect represents a word or glyph run
/// with its bounding box in page-local coordinates (PDF points).
///
/// DESIGN PRINCIPLES:
/// - Invisible at render time — exists only for hit-testing
/// - Lazy-loaded: extracted on first text selection attempt
/// - Cached in scene graph JSON for offline access
class PdfTextRect {
  /// Bounding rectangle in page-local coordinates (PDF points).
  final Rect rect;

  /// The actual text content of this fragment.
  final String text;

  /// Character offset in the full page text stream.
  final int charOffset;

  const PdfTextRect({
    required this.rect,
    required this.text,
    required this.charOffset,
  });

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'rect': {
      'left': rect.left,
      'top': rect.top,
      'right': rect.right,
      'bottom': rect.bottom,
    },
    'text': text,
    'charOffset': charOffset,
  };

  factory PdfTextRect.fromJson(Map<String, dynamic> json) {
    // E1: Defensive parsing — fallback to zero rect if missing
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
    return PdfTextRect(
      rect: rect,
      text: json['text'] as String? ?? '',
      charOffset: (json['charOffset'] as num?)?.toInt() ?? 0,
    );
  }

  /// Returns true if [point] (in page-local coordinates) hits this rect.
  bool containsPoint(Offset point) => rect.contains(point);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PdfTextRect &&
          rect == other.rect &&
          text == other.text &&
          charOffset == other.charOffset;

  @override
  int get hashCode => Object.hash(rect, text, charOffset);

  @override
  String toString() => 'PdfTextRect("$text", rect: $rect, offset: $charOffset)';
}
