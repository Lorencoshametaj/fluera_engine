import 'dart:ui';

/// 📄 A positioned text fragment extracted from a PDF page.
///
/// Used by the text geometry layer (Layer 5) to enable text selection
/// on rasterized PDF pages. Each rect represents a word or glyph run
/// with its bounding box in **normalized 0.0–1.0 coordinates** relative
/// to the page's CropBox/MediaBox.
///
/// DESIGN PRINCIPLES:
/// - Coordinates are scale-independent (0.0–1.0 relative to page)
/// - Invisible at render time — exists only for hit-testing
/// - Lazy-loaded: extracted on first text selection attempt
/// - Cached in scene graph JSON for offline access
class PdfTextRect {
  /// Bounding rectangle in normalized 0.0–1.0 page coordinates.
  final Rect rect;

  /// The actual text content of this fragment.
  final String text;

  /// Character offset in the full page text stream.
  final int charOffset;

  /// Cumulative character positions as fractions of the rect width (0.0–1.0).
  ///
  /// Length = [text.length] + 1, where `charPositions[0] = 0.0` and
  /// `charPositions[text.length] = 1.0`. Each entry `charPositions[i]`
  /// represents the left edge of character `i` as a fraction of rect width.
  ///
  /// Computed from per-run PDF Tm/Td positions during line-rect merging,
  /// giving pixel-perfect character boundaries regardless of font.
  final List<double>? charPositions;

  const PdfTextRect({
    required this.rect,
    required this.text,
    required this.charOffset,
    this.charPositions,
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
    if (charPositions != null) 'cp': charPositions,
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
    List<double>? cp;
    if (json['cp'] is List) {
      cp = (json['cp'] as List).map((e) => (e as num).toDouble()).toList();
    }
    return PdfTextRect(
      rect: rect,
      text: json['text'] as String? ?? '',
      charOffset: (json['charOffset'] as num?)?.toInt() ?? 0,
      charPositions: cp,
    );
  }

  /// Returns true if [point] (in normalized coordinates) hits this rect.
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
