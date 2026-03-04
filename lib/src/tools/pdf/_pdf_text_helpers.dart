part of 'pdf_text_extractor.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 📄 PDF Text Extraction — Helper Classes & Data
// ═══════════════════════════════════════════════════════════════════════════

class ExtractedPageText {
  final String text;

  /// Text rects in **normalized 0.0–1.0** coordinates relative to page bounds.
  final List<PdfTextRect> rects;

  /// Page dimensions in PDF points (from CropBox or MediaBox).
  final double pageWidth;
  final double pageHeight;

  /// Page origin offsets (lower-left corner of CropBox/MediaBox).
  final double originX;
  final double originY;

  /// Whether the content stream's CTM flipped the Y axis (d < 0 in `cm`).
  /// When true, Y=0 is at the top (top-down). When false, Y=0 is at the
  /// bottom (standard PDF bottom-up).
  final bool isYFlipped;

  const ExtractedPageText(
    this.text,
    this.rects, {
    this.pageWidth = 612,
    this.pageHeight = 792,
    this.originX = 0,
    this.originY = 0,
    this.isYFlipped = false,
  });
  static const empty = ExtractedPageText('', []);
}


/// Font info resolved from the PDF.
class _FontInfo {
  /// CMap: glyph code → Unicode string.
  final Map<int, String> toUnicode;

  /// Character widths: charCode → width in 1/1000 of text space unit.
  final Map<int, double> widths;

  /// Default width for missing entries (1/1000 units).
  final double defaultWidth;

  /// Encoding differences: charCode → glyph name.
  final Map<int, String> differences;

  const _FontInfo({
    this.toUnicode = const {},
    this.widths = const {},
    this.defaultWidth = 600,
    this.differences = const {},
  });

  static const fallback = _FontInfo();

  /// Get the width of [charCode] as a fraction of fontSize.
  ///
  /// Falls back to standard Latin proportional widths (Helvetica/Arial)
  /// when the font's width map is empty, giving ~95% accuracy for
  /// highlight positioning without needing to parse CID /W arrays.
  double charWidth(int charCode, {int? unicodeCode}) {
    if (widths.containsKey(charCode)) {
      return widths[charCode]! / 1000;
    }
    // Try Latin proportional widths using Unicode code point
    final latinKey = unicodeCode ?? charCode;
    final latin = _latinWidths[latinKey];
    if (latin != null) return latin / 1000;
    return defaultWidth / 1000;
  }

  /// Standard Helvetica/Arial character widths (per-1000 units).
  /// Covers ASCII 32-126 with real proportional metrics.
  static const _latinWidths = <int, double>{
    32: 278, // space
    33: 278, // !
    34: 355, // "
    35: 556, // #
    36: 556, // $
    37: 889, // %
    38: 667, // &
    39: 191, // '
    40: 333, // (
    41: 333, // )
    42: 389, // *
    43: 584, // +
    44: 278, // ,
    45: 333, // -
    46: 278, // .
    47: 278, // /
    48: 556, // 0
    49: 556, // 1
    50: 556, // 2
    51: 556, // 3
    52: 556, // 4
    53: 556, // 5
    54: 556, // 6
    55: 556, // 7
    56: 556, // 8
    57: 556, // 9
    58: 278, // :
    59: 278, // ;
    60: 584, // <
    61: 584, // =
    62: 584, // >
    63: 556, // ?
    64: 1015, // @
    65: 667, // A
    66: 667, // B
    67: 722, // C
    68: 722, // D
    69: 667, // E
    70: 611, // F
    71: 778, // G
    72: 722, // H
    73: 278, // I
    74: 500, // J
    75: 667, // K
    76: 556, // L
    77: 833, // M
    78: 722, // N
    79: 778, // O
    80: 667, // P
    81: 778, // Q
    82: 722, // R
    83: 667, // S
    84: 611, // T
    85: 722, // U
    86: 667, // V
    87: 944, // W
    88: 667, // X
    89: 667, // Y
    90: 611, // Z
    91: 278, // [
    92: 278, // backslash
    93: 278, // ]
    94: 469, // ^
    95: 556, // _
    96: 333, // `
    97: 556, // a
    98: 556, // b
    99: 500, // c
    100: 556, // d
    101: 556, // e
    102: 278, // f
    103: 556, // g
    104: 556, // h
    105: 222, // i
    106: 222, // j
    107: 500, // k
    108: 222, // l
    109: 833, // m
    110: 556, // n
    111: 556, // o
    112: 556, // p
    113: 556, // q
    114: 333, // r
    115: 500, // s
    116: 278, // t
    117: 556, // u
    118: 500, // v
    119: 722, // w
    120: 500, // x
    121: 500, // y
    122: 500, // z
    123: 334, // {
    124: 260, // |
    125: 334, // }
    126: 584, // ~
    // Latin-1 Supplement: accented characters (common in IT/FR/DE/ES/PT)
    160: 278, // non-breaking space
    161: 333, // ¡
    162: 556, // ¢
    163: 556, // £
    164: 556, // ¤
    165: 556, // ¥
    166: 260, // ¦
    167: 556, // §
    168: 333, // ¨
    169: 737, // ©
    170: 370, // ª
    171: 556, // «
    172: 584, // ¬
    173: 333, // soft-hyphen
    174: 737, // ®
    176: 400, // °
    177: 584, // ±
    178: 333, // ²
    179: 333, // ³
    180: 333, // ´
    181: 556, // µ
    183: 278, // ·
    184: 333, // ¸
    185: 333, // ¹
    186: 365, // º
    187: 556, // »
    191: 611, // ¿
    192: 667, // À
    193: 667, // Á
    194: 667, // Â
    195: 667, // Ã
    196: 667, // Ä
    197: 667, // Å
    198: 1000, // Æ
    199: 722, // Ç
    200: 667, // È
    201: 667, // É
    202: 667, // Ê
    203: 667, // Ë
    204: 278, // Ì
    205: 278, // Í
    206: 278, // Î
    207: 278, // Ï
    208: 722, // Ð
    209: 722, // Ñ
    210: 778, // Ò
    211: 778, // Ó
    212: 778, // Ô
    213: 778, // Õ
    214: 778, // Ö
    216: 778, // Ø
    217: 722, // Ù
    218: 722, // Ú
    219: 722, // Û
    220: 722, // Ü
    221: 667, // Ý
    223: 611, // ß
    224: 556, // à
    225: 556, // á
    226: 556, // â
    227: 556, // ã
    228: 556, // ä
    229: 556, // å
    230: 889, // æ
    231: 500, // ç
    232: 556, // è
    233: 556, // é
    234: 556, // ê
    235: 556, // ë
    236: 278, // ì
    237: 278, // í
    238: 278, // î
    239: 278, // ï
    240: 556, // ð
    241: 556, // ñ
    242: 556, // ò
    243: 556, // ó
    244: 556, // ô
    245: 556, // õ
    246: 556, // ö
    248: 611, // ø
    249: 556, // ù
    250: 556, // ú
    251: 556, // û
    252: 556, // ü
    253: 500, // ý
    255: 500, // ÿ
  };

  /// Decode a char code to a Unicode string using ToUnicode CMap
  /// or encoding differences.
  String? decode(int charCode) {
    // ToUnicode takes priority
    final uni = toUnicode[charCode];
    if (uni != null) return uni;

    // Then try encoding differences → standard glyph name
    final glyphName = differences[charCode];
    if (glyphName != null) {
      return _glyphNameToChar[glyphName] ?? String.fromCharCode(charCode);
    }

    return null; // use raw char
  }
}

/// Simple 2D affine matrix for CTM tracking.
///
/// Represents: | a  b  0 |
///             | c  d  0 |
///             | e  f  1 |
class _Matrix {
  final double a, b, c, d, e, f;
  const _Matrix(this.a, this.b, this.c, this.d, this.e, this.f);
  static const identity = _Matrix(1, 0, 0, 1, 0, 0);

  /// Concatenate: this × other
  _Matrix concat(_Matrix o) => _Matrix(
    a * o.a + b * o.c,
    a * o.b + b * o.d,
    c * o.a + d * o.c,
    c * o.b + d * o.d,
    e * o.a + f * o.c + o.e,
    e * o.b + f * o.d + o.f,
  );

  /// Transform a point.
  (double, double) transform(double x, double y) => (
    a * x + c * y + e,
    b * x + d * y + f,
  );

  /// Effective horizontal scale.
  double get scaleX => (a * a + b * b) > 0 ? (a * a + b * b).sqrt() : 1;

  /// Effective vertical scale.
  double get scaleY => (c * c + d * d) > 0 ? (c * c + d * d).sqrt() : 1;
}

extension on double {
  double sqrt() {
    if (this <= 0) return 0;
    // Newton's method — 6 iterations for double precision
    double x = this;
    for (int i = 0; i < 6; i++) {
      x = (x + this / x) / 2;
    }
    return x;
  }
}

/// Saved graphics state for q/Q stack.
class _GfxState {
  final _Matrix ctm;
  final double fontSize;
  final double leading;
  final double charSpacing;
  final double wordSpacing;
  final _FontInfo font;

  _GfxState({
    required this.ctm,
    required this.fontSize,
    required this.leading,
    required this.charSpacing,
    required this.wordSpacing,
    required this.font,
  });
}


// =============================================================================
// Internal types
// =============================================================================

class _PageInfo {
  final int objNum;
  final int offset;
  final List<int> contents;
  final String? resourcesBody;
  final double pageWidth;
  final double pageHeight;
  final double originX;
  final double originY;

  _PageInfo({
    required this.objNum,
    required this.offset,
    required this.contents,
    this.resourcesBody,
    this.pageWidth = 612,
    this.pageHeight = 792,
    this.originX = 0,
    this.originY = 0,
  });
}

class _ParsedString {
  final String text;
  final int endIdx;
  final List<int> rawCodes; // for hex strings
  _ParsedString(this.text, this.endIdx, this.rawCodes);
}

class _IsolateArgs {
  final Uint8List bytes;
  final int? pageCount;
  _IsolateArgs(this.bytes, this.pageCount);
}

// =============================================================================
// Standard glyph name → Unicode mapping (subset of Adobe Glyph List)
// =============================================================================

const _glyphNameToChar = <String, String>{
  'space': ' ',
  'exclam': '!',
  'quotedbl': '"',
  'numbersign': '#',
  'dollar': '\$',
  'percent': '%',
  'ampersand': '&',
  'quotesingle': "'",
  'quoteright': '\u2019',
  'quoteleft': '\u2018',
  'parenleft': '(',
  'parenright': ')',
  'asterisk': '*',
  'plus': '+',
  'comma': ',',
  'hyphen': '-',
  'period': '.',
  'slash': '/',
  'zero': '0',
  'one': '1',
  'two': '2',
  'three': '3',
  'four': '4',
  'five': '5',
  'six': '6',
  'seven': '7',
  'eight': '8',
  'nine': '9',
  'colon': ':',
  'semicolon': ';',
  'less': '<',
  'equal': '=',
  'greater': '>',
  'question': '?',
  'at': '@',
  'bracketleft': '[',
  'backslash': '\\',
  'bracketright': ']',
  'asciicircum': '^',
  'underscore': '_',
  'grave': '`',
  'braceleft': '{',
  'bar': '|',
  'braceright': '}',
  'asciitilde': '~',
  'bullet': '\u2022',
  'endash': '\u2013',
  'emdash': '\u2014',
  'ellipsis': '\u2026',
  'quotedblleft': '\u201C',
  'quotedblright': '\u201D',
  'fi': 'fi',
  'fl': 'fl',
  'ff': 'ff',
  'ffi': 'ffi',
  'ffl': 'ffl',
  'degree': '\u00B0',
  'copyright': '\u00A9',
  'registered': '\u00AE',
  'trademark': '\u2122',
  'Euro': '\u20AC',
  'sterling': '\u00A3',
  'yen': '\u00A5',
  'cent': '\u00A2',
  'section': '\u00A7',
  'paragraph': '\u00B6',
  'dagger': '\u2020',
  'daggerdbl': '\u2021',
  // Accented chars
  'agrave': '\u00E0',
  'aacute': '\u00E1',
  'acircumflex': '\u00E2',
  'atilde': '\u00E3',
  'adieresis': '\u00E4',
  'aring': '\u00E5',
  'ccedilla': '\u00E7',
  'egrave': '\u00E8',
  'eacute': '\u00E9',
  'ecircumflex': '\u00EA',
  'edieresis': '\u00EB',
  'igrave': '\u00EC',
  'iacute': '\u00ED',
  'icircumflex': '\u00EE',
  'idieresis': '\u00EF',
  'ntilde': '\u00F1',
  'ograve': '\u00F2',
  'oacute': '\u00F3',
  'ocircumflex': '\u00F4',
  'otilde': '\u00F5',
  'odieresis': '\u00F6',
  'ugrave': '\u00F9',
  'uacute': '\u00FA',
  'ucircumflex': '\u00FB',
  'udieresis': '\u00FC',
  'Agrave': '\u00C0',
  'Aacute': '\u00C1',
  'Acircumflex': '\u00C2',
  'Atilde': '\u00C3',
  'Adieresis': '\u00C4',
  'Aring': '\u00C5',
  'Ccedilla': '\u00C7',
  'Egrave': '\u00C8',
  'Eacute': '\u00C9',
  'Ecircumflex': '\u00CA',
  'Edieresis': '\u00CB',
  'Igrave': '\u00CC',
  'Iacute': '\u00CD',
  'Icircumflex': '\u00CE',
  'Idieresis': '\u00CF',
  'Ntilde': '\u00D1',
  'Ograve': '\u00D2',
  'Oacute': '\u00D3',
  'Ocircumflex': '\u00D4',
  'Otilde': '\u00D5',
  'Odieresis': '\u00D6',
  'Ugrave': '\u00D9',
  'Uacute': '\u00DA',
  'Ucircumflex': '\u00DB',
  'Udieresis': '\u00DC',
};
