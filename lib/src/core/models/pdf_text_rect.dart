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
    final r = json['rect'] as Map<String, dynamic>;
    return PdfTextRect(
      rect: Rect.fromLTRB(
        (r['left'] as num).toDouble(),
        (r['top'] as num).toDouble(),
        (r['right'] as num).toDouble(),
        (r['bottom'] as num).toDouble(),
      ),
      text: json['text'] as String,
      charOffset: (json['charOffset'] as num?)?.toInt() ?? 0,
    );
  }

  /// Returns true if [point] (in page-local coordinates) hits this rect.
  bool containsPoint(Offset point) => rect.contains(point);

  @override
  String toString() => 'PdfTextRect("$text", rect: $rect, offset: $charOffset)';
}
