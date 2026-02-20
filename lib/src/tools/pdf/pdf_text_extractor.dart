import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../core/models/pdf_text_rect.dart';

// =============================================================================
// 📄 PURE-DART PDF TEXT EXTRACTION  (v6 — CTM + State Stack + Spacing)
// =============================================================================
//
// Changes from v5:
//   ✓ CTM matrix (cm operator) — correct positions for scaled/rotated text
//   ✓ q/Q graphics state stack — save/restore position & font state
//   ✓ Tc/Tw operators — character & word spacing for precise widths
//   ✓ Stream /Length validation — robust stream boundary detection
//
// Inherited from v5:
//   ✓ ToUnicode CMap parsing, /Encoding + /Differences
//   ✓ Font /Widths, descendant CIDFont resolution
//   ✓ compute() isolate for non-blocking extraction
//
// HANDLES:
//   ✓ FlateDecode compressed streams
//   ✓ Tj, TJ, ', " text-showing operators
//   ✓ Literal/hex strings + kerning-based word separation
//   ✓ Text position tracking (Tm, Td, TD, T*, TL, Tf)
//   ✓ CTM (cm) with full matrix multiplication
//   ✓ Graphics state save/restore (q/Q)
//   ✓ Character spacing (Tc) and word spacing (Tw)
//   ✓ Page tree + /Contents association
//   ✓ ToUnicode CMap, Font /Widths, /Encoding /Differences
//   ✓ Isolate-based extraction via Flutter compute()
//
// LIMITATIONS:
//   ✗ Encrypted PDFs
//   ✗ CIDFont Type2 complex CMap (partial support)
//   ✗ Inline images (ignored)
// =============================================================================

/// Result of text extraction: plain text + positioned rects.
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

/// Extracts text from a PDF file given its raw bytes.
class PdfTextExtractor {
  final Uint8List _bytes;
  late final String _raw;

  /// Cached object stream data.
  Map<int, Uint8List>? _objectStreams;

  /// Cached font info per font reference name per page.
  final Map<String, _FontInfo> _fontCache = {};

  PdfTextExtractor(this._bytes) {
    _raw = latin1.decode(_bytes);
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Extract text from all pages (runs in current isolate).
  List<ExtractedPageText> extractAllPagesWithRects({int? pageCount}) {
    try {
      final result = _extractViaPageTree(pageCount);
      debugPrint(
        '[PdfTextExtractor] Used PAGE TREE path, '
        '${result.length} pages extracted',
      );
      if (result.isNotEmpty) {
        final p0 = result.first;
        debugPrint(
          '[PdfTextExtractor] Page 0: '
          '${p0.rects.length} rects, '
          'text=${p0.text.length} chars, '
          'pgW=${p0.pageWidth}, pgH=${p0.pageHeight}, '
          'isYFlipped=${p0.isYFlipped}',
        );
        if (p0.rects.isNotEmpty) {
          final r = p0.rects.first;
          debugPrint(
            '[PdfTextExtractor] Page 0 first rect (post-normalize): '
            '${r.rect}, text="${r.text}"',
          );
        }
      }
      return result;
    } catch (e) {
      debugPrint('[PdfTextExtractor] Page tree failed: $e');
      try {
        final result = _extractFallback(pageCount);
        debugPrint(
          '[PdfTextExtractor] Used FALLBACK path, '
          '${result.length} pages extracted',
        );
        return result;
      } catch (e2) {
        debugPrint('[PdfTextExtractor] Fallback failed: $e2');
        return List.filled(pageCount ?? 0, ExtractedPageText.empty);
      }
    }
  }

  /// Extract in a background isolate (non-blocking for UI).
  static Future<List<ExtractedPageText>> extractInIsolate(
    Uint8List bytes, {
    int? pageCount,
  }) {
    return compute(_isolateExtract, _IsolateArgs(bytes, pageCount));
  }

  static List<ExtractedPageText> _isolateExtract(_IsolateArgs args) {
    final extractor = PdfTextExtractor(args.bytes);
    return extractor.extractAllPagesWithRects(pageCount: args.pageCount);
  }

  /// Simple text-only extraction.
  List<String> extractAllPages({int? pageCount}) {
    return extractAllPagesWithRects(
      pageCount: pageCount,
    ).map((e) => e.text).toList();
  }

  // ---------------------------------------------------------------------------
  // Strategy 1: Page-tree based extraction
  // ---------------------------------------------------------------------------

  List<ExtractedPageText> _extractViaPageTree(int? pageCount) {
    final pages = _findPageObjects();
    if (pages.isEmpty) return _extractFallback(pageCount);

    _objectStreams ??= _buildObjectStreamMap();
    final results = <ExtractedPageText>[];

    for (final page in pages) {
      // Resolve fonts for this page
      final fonts = _resolveFontsForPage(page);

      final pageText = StringBuffer();
      final pageRects = <PdfTextRect>[];

      bool pageYFlipped = false;
      for (final objRef in page.contents) {
        final streamData = _objectStreams![objRef];
        if (streamData == null) continue;

        final extracted = _extractTextFromStream(streamData, fonts);
        if (extracted.text.isEmpty) continue;

        // If any content stream has Y-flip, the whole page is Y-flipped
        if (extracted.isYFlipped) pageYFlipped = true;

        final offset = pageText.length;
        if (pageText.isNotEmpty) pageText.write(' ');
        final charShift = offset + (offset > 0 ? 1 : 0);
        for (final r in extracted.rects) {
          pageRects.add(
            PdfTextRect(
              rect: r.rect,
              text: r.text,
              charOffset: r.charOffset + charShift,
              charPositions: r.charPositions,
            ),
          );
        }
        pageText.write(extracted.text);
      }

      // Merge runs into line rects, then normalize to 0.0–1.0
      final merged = _mergeLineRects(pageRects);
      final pgW = page.pageWidth;
      final pgH = page.pageHeight;
      final oX = page.originX;
      final oY = page.originY;

      // Pass raw (un-normalized) rects — normalization + Y-flip is
      // handled by PdfSearchController._normalizeRects in the main isolate.
      results.add(
        ExtractedPageText(
          pageText.toString(),
          merged,
          pageWidth: pgW,
          pageHeight: pgH,
          originX: oX,
          originY: oY,
          isYFlipped: pageYFlipped,
        ),
      );
    }

    // Pad to pageCount
    if (pageCount != null && pageCount > 0) {
      while (results.length < pageCount) {
        results.add(ExtractedPageText.empty);
      }
      if (results.length > pageCount) return results.sublist(0, pageCount);
    }

    return results;
  }

  // ---------------------------------------------------------------------------
  // Page tree parsing
  // ---------------------------------------------------------------------------

  List<_PageInfo> _findPageObjects() {
    final pages = <_PageInfo>[];
    final objPattern = RegExp(r'(\d+)\s+0\s+obj\b');

    for (final match in objPattern.allMatches(_raw)) {
      final objNum = int.parse(match.group(1)!);
      final objStart = match.start;
      final endobjIdx = _raw.indexOf('endobj', objStart);
      if (endobjIdx < 0) continue;

      final objBody = _raw.substring(objStart, endobjIdx);
      if (!RegExp(r'/Type\s*/Page\b(?!s)').hasMatch(objBody)) continue;

      // /Contents reference(s)
      final contentsRefs = <int>[];
      final singleRef = RegExp(r'/Contents\s+(\d+)\s+0\s+R');
      final singleMatch = singleRef.firstMatch(objBody);
      if (singleMatch != null) {
        contentsRefs.add(int.parse(singleMatch.group(1)!));
      } else {
        final arrayRef = RegExp(r'/Contents\s*\[([^\]]+)\]');
        final arrayMatch = arrayRef.firstMatch(objBody);
        if (arrayMatch != null) {
          for (final r in RegExp(
            r'(\d+)\s+0\s+R',
          ).allMatches(arrayMatch.group(1)!)) {
            contentsRefs.add(int.parse(r.group(1)!));
          }
        }
      }

      // /Resources (for font resolution)
      String? resourcesBody;
      final resInline = RegExp(r'/Resources\s*<<(.*?)>>', dotAll: true);
      final resMatch = resInline.firstMatch(objBody);
      if (resMatch != null) {
        resourcesBody = resMatch.group(1);
      } else {
        // /Resources N 0 R
        final resRef = RegExp(r'/Resources\s+(\d+)\s+0\s+R');
        final resRefMatch = resRef.firstMatch(objBody);
        if (resRefMatch != null) {
          final resObj = int.parse(resRefMatch.group(1)!);
          resourcesBody = _getObjectBody(resObj);
        }
      }

      // Parse page dimensions from CropBox (priority) or MediaBox.
      // CropBox defines the visible content area; MediaBox the full page.
      double pageWidth = 612; // default US Letter
      double pageHeight = 792;
      double originX = 0;
      double originY = 0;
      final cropBoxM = _parseBox(objBody, 'CropBox');
      final mediaBoxM = _parseBox(objBody, 'MediaBox');
      final box = cropBoxM ?? mediaBoxM;
      if (box != null) {
        originX = box[0]; // llx
        originY = box[1]; // lly
        pageWidth = box[2] - box[0]; // urx - llx
        pageHeight = box[3] - box[1]; // ury - lly
      }

      pages.add(
        _PageInfo(
          objNum: objNum,
          offset: objStart,
          contents: contentsRefs,
          resourcesBody: resourcesBody,
          pageWidth: pageWidth,
          pageHeight: pageHeight,
          originX: originX,
          originY: originY,
        ),
      );
    }

    pages.sort((a, b) => a.offset.compareTo(b.offset));
    return pages;
  }

  /// Parse a PDF box array (e.g. /MediaBox, /CropBox) from a page dict.
  /// Returns [llx, lly, urx, ury] or null if not found.
  static List<double>? _parseBox(String objBody, String boxName) {
    final re = RegExp(
      '/$boxName\\s*\\[\\s*([\\d.\\-]+)\\s+([\\d.\\-]+)\\s+([\\d.\\-]+)\\s+([\\d.\\-]+)\\s*\\]',
    );
    final m = re.firstMatch(objBody);
    if (m == null) return null;
    return [
      double.tryParse(m.group(1)!) ?? 0,
      double.tryParse(m.group(2)!) ?? 0,
      double.tryParse(m.group(3)!) ?? 0,
      double.tryParse(m.group(4)!) ?? 0,
    ];
  }

  // ---------------------------------------------------------------------------
  // Font resolution
  // ---------------------------------------------------------------------------

  /// Resolve all fonts referenced in a page's /Resources.
  Map<String, _FontInfo> _resolveFontsForPage(_PageInfo page) {
    final fonts = <String, _FontInfo>{};
    if (page.resourcesBody == null) return fonts;

    // Find /Font << /F1 N 0 R /F2 M 0 R ... >>
    final fontDict = RegExp(r'/Font\s*<<(.*?)>>', dotAll: true);
    final fontMatch = fontDict.firstMatch(page.resourcesBody!);
    if (fontMatch == null) return fonts;

    final fontEntries = fontMatch.group(1)!;
    final fontRefPattern = RegExp(r'/(\w+)\s+(\d+)\s+0\s+R');

    for (final m in fontRefPattern.allMatches(fontEntries)) {
      final fontName = m.group(1)!;
      final fontObjNum = int.parse(m.group(2)!);

      // Check cache
      final cacheKey = 'obj_$fontObjNum';
      if (_fontCache.containsKey(cacheKey)) {
        fonts[fontName] = _fontCache[cacheKey]!;
        continue;
      }

      final info = _parseFontObject(fontObjNum);
      _fontCache[cacheKey] = info;
      fonts[fontName] = info;
    }

    return fonts;
  }

  /// Parse a Font object to extract ToUnicode, Widths, and Encoding.
  _FontInfo _parseFontObject(int objNum) {
    final body = _getObjectBody(objNum);
    if (body == null) return _FontInfo.fallback;

    // --- ToUnicode CMap ---
    Map<int, String> toUnicode = {};
    final toUnicodeRef = RegExp(r'/ToUnicode\s+(\d+)\s+0\s+R');
    final tuMatch = toUnicodeRef.firstMatch(body);
    if (tuMatch != null) {
      final tuObjNum = int.parse(tuMatch.group(1)!);
      _objectStreams ??= _buildObjectStreamMap();
      final cmapData = _objectStreams![tuObjNum];
      if (cmapData != null) {
        toUnicode = _parseCMap(utf8.decode(cmapData, allowMalformed: true));
      }
    }

    // --- Widths ---
    Map<int, double> widths = {};
    double defaultWidth = 600;

    // /FirstChar N /LastChar M /Widths [...]
    final firstCharMatch = RegExp(r'/FirstChar\s+(\d+)').firstMatch(body);
    final widthsMatch = RegExp(r'/Widths\s*\[([^\]]*)\]').firstMatch(body);

    if (firstCharMatch != null && widthsMatch != null) {
      final firstChar = int.parse(firstCharMatch.group(1)!);
      final widthValues =
          widthsMatch
              .group(1)!
              .trim()
              .split(RegExp(r'\s+'))
              .map((s) => double.tryParse(s) ?? 0)
              .toList();
      for (int j = 0; j < widthValues.length; j++) {
        widths[firstChar + j] = widthValues[j];
      }
    } else {
      // Try /Widths ref
      final widthsRef = RegExp(r'/Widths\s+(\d+)\s+0\s+R');
      final wrMatch = widthsRef.firstMatch(body);
      if (wrMatch != null && firstCharMatch != null) {
        final firstChar = int.parse(firstCharMatch.group(1)!);
        final wBody = _getObjectBody(int.parse(wrMatch.group(1)!));
        if (wBody != null) {
          final arrMatch = RegExp(r'\[([^\]]*)\]').firstMatch(wBody);
          if (arrMatch != null) {
            final vals =
                arrMatch
                    .group(1)!
                    .trim()
                    .split(RegExp(r'\s+'))
                    .map((s) => double.tryParse(s) ?? 0)
                    .toList();
            for (int j = 0; j < vals.length; j++) {
              widths[firstChar + j] = vals[j];
            }
          }
        }
      }
    }

    // --- /W array (CID fonts) ---
    // Format: /W [ cid [w1 w2 ...] | cid_start cid_end w ]
    if (widths.isEmpty) {
      final wArrayMatch = RegExp(r'/W\s*\[', dotAll: true).firstMatch(body);
      if (wArrayMatch != null) {
        widths = _parseCidWidths(body, wArrayMatch.end);
      }
    }

    // /MissingWidth or /DW for CIDFont
    final dwMatch = RegExp(r'/(?:MissingWidth|DW)\s+(\d+)').firstMatch(body);
    if (dwMatch != null) {
      defaultWidth = double.tryParse(dwMatch.group(1)!) ?? 600;
    }

    // --- Encoding /Differences ---
    Map<int, String> differences = {};
    final diffMatch = RegExp(
      r'/Differences\s*\[([^\]]*)\]',
      dotAll: true,
    ).firstMatch(body);
    if (diffMatch != null) {
      differences = _parseDifferences(diffMatch.group(1)!);
    }

    // Check for descendant CIDFont (composite font)
    final descendantRef = RegExp(
      r'/DescendantFonts\s*\[\s*(\d+)\s+0\s+R',
    ).firstMatch(body);
    if (descendantRef != null && widths.isEmpty) {
      final cidInfo = _parseFontObject(int.parse(descendantRef.group(1)!));
      widths = Map.from(cidInfo.widths);
      if (cidInfo.defaultWidth != 600) defaultWidth = cidInfo.defaultWidth;
    }

    return _FontInfo(
      toUnicode: toUnicode,
      widths: widths,
      defaultWidth: defaultWidth,
      differences: differences,
    );
  }

  // ---------------------------------------------------------------------------
  // CMap parser
  // ---------------------------------------------------------------------------

  Map<int, String> _parseCMap(String cmap) {
    final result = <int, String>{};

    // beginbfchar / endbfchar: <srcCode> <dstString>
    final bfcharBlocks = RegExp(
      r'beginbfchar\s*(.*?)\s*endbfchar',
      dotAll: true,
    );
    for (final block in bfcharBlocks.allMatches(cmap)) {
      final lines = block.group(1)!.trim().split('\n');
      for (final line in lines) {
        final m = RegExp(
          r'<([0-9a-fA-F]+)>\s*<([0-9a-fA-F]+)>',
        ).firstMatch(line.trim());
        if (m != null) {
          final src = int.tryParse(m.group(1)!, radix: 16);
          final dst = _hexToString(m.group(2)!);
          if (src != null && dst.isNotEmpty) result[src] = dst;
        }
      }
    }

    // beginbfrange / endbfrange: <start> <end> <dstStart>
    // or: <start> <end> [<dst1> <dst2> ...]
    final bfrangeBlocks = RegExp(
      r'beginbfrange\s*(.*?)\s*endbfrange',
      dotAll: true,
    );
    for (final block in bfrangeBlocks.allMatches(cmap)) {
      final lines = block.group(1)!.trim().split('\n');
      for (final line in lines) {
        // Array form: <start> <end> [<v1> <v2> ...]
        final arrMatch = RegExp(
          r'<([0-9a-fA-F]+)>\s*<([0-9a-fA-F]+)>\s*\[([^\]]*)\]',
        ).firstMatch(line.trim());
        if (arrMatch != null) {
          final start = int.tryParse(arrMatch.group(1)!, radix: 16) ?? 0;
          final end = int.tryParse(arrMatch.group(2)!, radix: 16) ?? 0;
          final values =
              RegExp(r'<([0-9a-fA-F]+)>')
                  .allMatches(arrMatch.group(3)!)
                  .map((m) => _hexToString(m.group(1)!))
                  .toList();
          for (int code = start; code <= end; code++) {
            final idx = code - start;
            if (idx < values.length) result[code] = values[idx];
          }
          continue;
        }

        // Simple form: <start> <end> <dstStart>
        final simpleMatch = RegExp(
          r'<([0-9a-fA-F]+)>\s*<([0-9a-fA-F]+)>\s*<([0-9a-fA-F]+)>',
        ).firstMatch(line.trim());
        if (simpleMatch != null) {
          final start = int.tryParse(simpleMatch.group(1)!, radix: 16) ?? 0;
          final end = int.tryParse(simpleMatch.group(2)!, radix: 16) ?? 0;
          final dstStart = int.tryParse(simpleMatch.group(3)!, radix: 16) ?? 0;
          for (int code = start; code <= end; code++) {
            result[code] = String.fromCharCode(dstStart + (code - start));
          }
        }
      }
    }

    return result;
  }

  String _hexToString(String hex) {
    final buf = StringBuffer();
    if (hex.length >= 4 && hex.length % 4 == 0) {
      for (var i = 0; i + 3 < hex.length; i += 4) {
        final code = int.tryParse(hex.substring(i, i + 4), radix: 16);
        if (code != null) buf.writeCharCode(code);
      }
    } else {
      for (var i = 0; i + 1 < hex.length; i += 2) {
        final code = int.tryParse(hex.substring(i, i + 2), radix: 16);
        if (code != null && code >= 32) buf.writeCharCode(code);
      }
    }
    return buf.toString();
  }

  Map<int, String> _parseDifferences(String diffStr) {
    final result = <int, String>{};
    final tokens = diffStr.trim().split(RegExp(r'\s+'));
    int currentCode = 0;
    for (final token in tokens) {
      if (token.startsWith('/')) {
        result[currentCode] = token.substring(1);
        currentCode++;
      } else {
        currentCode = int.tryParse(token) ?? currentCode;
      }
    }
    return result;
  }

  /// Parse CID /W array: /W [ cid [w1 w2 ...] | cid_start cid_end w ]
  ///
  /// Two forms:
  /// 1. `c_first [w1 w2 w3 ...]` — CIDs c_first, c_first+1, ... get widths
  /// 2. `c_first c_last w` — CIDs c_first..c_last all get width w
  Map<int, double> _parseCidWidths(String body, int startIdx) {
    final widths = <int, double>{};

    // Collect top-level tokens from the /W array
    final tokens = <String>[];
    int depth = 0;
    int i = startIdx;
    final len = body.length;
    final buf = StringBuffer();

    while (i < len) {
      final ch = body[i];
      if (ch == ']' && depth == 0) break;
      if (ch == '[') {
        if (depth == 0) {
          final s = buf.toString().trim();
          if (s.isNotEmpty) tokens.add(s);
          buf.clear();
          depth++;
        } else {
          depth++;
          buf.write(ch);
        }
      } else if (ch == ']') {
        depth--;
        if (depth == 0) {
          tokens.add('[${buf.toString().trim()}]');
          buf.clear();
        } else {
          buf.write(ch);
        }
      } else {
        if (depth == 0 &&
            (ch == ' ' || ch == '\n' || ch == '\r' || ch == '\t')) {
          final s = buf.toString().trim();
          if (s.isNotEmpty) tokens.add(s);
          buf.clear();
        } else {
          buf.write(ch);
        }
      }
      i++;
    }
    final s = buf.toString().trim();
    if (s.isNotEmpty) tokens.add(s);

    // Process tokens
    int t = 0;
    while (t < tokens.length) {
      final cidStart = int.tryParse(tokens[t]);
      if (cidStart == null) {
        t++;
        continue;
      }
      t++;
      if (t >= tokens.length) break;

      if (tokens[t].startsWith('[')) {
        // Form 1: cid [w1 w2 ...]
        final arrContent = tokens[t].substring(1, tokens[t].length - 1).trim();
        final vals = arrContent.split(RegExp(r'\s+'));
        int cid = cidStart;
        for (final v in vals) {
          final w = double.tryParse(v);
          if (w != null) {
            widths[cid] = w;
            cid++;
          }
        }
        t++;
      } else {
        // Form 2: cid_start cid_end w
        final cidEnd = int.tryParse(tokens[t]);
        t++;
        if (cidEnd != null && t < tokens.length) {
          final w = double.tryParse(tokens[t]);
          t++;
          if (w != null) {
            for (int cid = cidStart; cid <= cidEnd; cid++) {
              widths[cid] = w;
            }
          }
        }
      }
    }
    return widths;
  }

  // ---------------------------------------------------------------------------
  // Object helpers
  // ---------------------------------------------------------------------------

  String? _getObjectBody(int objNum) {
    final pattern = '$objNum 0 obj';
    final idx = _raw.indexOf(pattern);
    if (idx >= 0) {
      final endIdx = _raw.indexOf('endobj', idx);
      if (endIdx >= 0) {
        return _raw.substring(idx + pattern.length, endIdx);
      }
    }
    // Fallback: check decompressed object streams (for ObjStm-stored objects)
    _objectStreams ??= _buildObjectStreamMap();
    final streamData = _objectStreams![objNum];
    if (streamData != null) {
      try {
        return utf8.decode(streamData, allowMalformed: true);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Map<int, Uint8List> _buildObjectStreamMap() {
    final map = <int, Uint8List>{};
    final objPattern = RegExp(r'(\d+)\s+0\s+obj\b');

    for (final match in objPattern.allMatches(_raw)) {
      final objNum = int.parse(match.group(1)!);
      final objStart = match.start;
      final streamIdx = _raw.indexOf('stream', objStart);
      if (streamIdx < 0) continue;
      final endobjIdx = _raw.indexOf('endobj', objStart);
      if (endobjIdx < 0 || streamIdx > endobjIdx) continue;

      final dictSection = _raw.substring(objStart, streamIdx);
      final usesFlate = dictSection.contains('/FlateDecode');

      var dataStart = streamIdx + 6;
      if (dataStart < _bytes.length && _bytes[dataStart] == 0x0D) dataStart++;
      if (dataStart < _bytes.length && _bytes[dataStart] == 0x0A) dataStart++;

      // (J) Try /Length from dictionary for precise stream boundaries
      int? dataEnd;
      final lengthMatch = RegExp(r'/Length\s+(\d+)').firstMatch(dictSection);
      if (lengthMatch != null) {
        final declaredLength = int.tryParse(lengthMatch.group(1)!);
        if (declaredLength != null &&
            dataStart + declaredLength <= _bytes.length) {
          dataEnd = dataStart + declaredLength;
        }
      }

      // Fallback: scan for endstream
      if (dataEnd == null) {
        final endstreamIdx = _raw.indexOf('endstream', dataStart);
        if (endstreamIdx < 0) continue;
        dataEnd = endstreamIdx;
        if (dataEnd > dataStart && _bytes[dataEnd - 1] == 0x0A) dataEnd--;
        if (dataEnd > dataStart && _bytes[dataEnd - 1] == 0x0D) dataEnd--;
      }

      if (dataEnd <= dataStart) continue;

      final rawStream = _bytes.sublist(dataStart, dataEnd);
      Uint8List decoded;
      if (usesFlate) {
        try {
          decoded = Uint8List.fromList(zlib.decode(rawStream));
        } catch (_) {
          continue;
        }
      } else {
        decoded = rawStream;
      }

      // Check if this is an ObjStm (object stream) — parse inner objects
      if (dictSection.contains('/ObjStm') ||
          dictSection.contains('/Type /ObjStm')) {
        _parseObjStm(decoded, dictSection, map);
      }

      map[objNum] = decoded;
    }

    return map;
  }

  /// Parse an ObjStm (Object Stream) to extract individually packed objects.
  ///
  /// ObjStm format: header has /N (number of objects) and /First (byte offset
  /// to first object data). The stream contains pairs of `objNum byteOffset`
  /// followed by the object data at /First offset.
  void _parseObjStm(
    Uint8List decoded,
    String dictSection,
    Map<int, Uint8List> map,
  ) {
    try {
      final nMatch = RegExp(r'/N\s+(\d+)').firstMatch(dictSection);
      final firstMatch = RegExp(r'/First\s+(\d+)').firstMatch(dictSection);
      if (nMatch == null || firstMatch == null) return;

      final n = int.parse(nMatch.group(1)!);
      final first = int.parse(firstMatch.group(1)!);
      if (first >= decoded.length) return;

      final decodedStr = utf8.decode(decoded, allowMalformed: true);

      // Parse header: n pairs of "objNum byteOffset"
      final headerStr = decodedStr.substring(0, first).trim();
      final headerTokens = headerStr.split(RegExp(r'\s+'));

      final objNums = <int>[];
      final objOffsets = <int>[];
      for (
        int i = 0;
        i + 1 < headerTokens.length && objNums.length < n;
        i += 2
      ) {
        final num = int.tryParse(headerTokens[i]);
        final off = int.tryParse(headerTokens[i + 1]);
        if (num != null && off != null) {
          objNums.add(num);
          objOffsets.add(off);
        }
      }

      // Extract each object's data
      final dataSection = decodedStr.substring(first);
      for (int i = 0; i < objNums.length; i++) {
        final start = objOffsets[i];
        final end =
            (i + 1 < objOffsets.length)
                ? objOffsets[i + 1]
                : dataSection.length;
        if (start >= dataSection.length) continue;
        final objData = dataSection.substring(
          start,
          end > dataSection.length ? dataSection.length : end,
        );
        map[objNums[i]] = Uint8List.fromList(utf8.encode(objData));
      }
    } catch (_) {
      // Silently ignore malformed ObjStm
    }
  }

  // ---------------------------------------------------------------------------
  // Text extraction from decoded content streams
  // ---------------------------------------------------------------------------

  ExtractedPageText _extractTextFromStream(
    Uint8List streamData, [
    Map<String, _FontInfo> fonts = const {},
  ]) {
    if (_indexOfBytes(streamData, [0x42, 0x54], 0) < 0) {
      return ExtractedPageText.empty;
    }

    final text = utf8.decode(streamData, allowMalformed: true);
    final buf = StringBuffer();
    final rects = <PdfTextRect>[];
    var i = 0;
    bool needsSpace = false;
    _FontInfo activeFont = _FontInfo.fallback;

    // (F) CTM tracking + (G) graphics state stack
    var ctm = _Matrix.identity;
    final gfxStack = <_GfxState>[];
    double charSpacing = 0;
    double wordSpacing = 0;
    double fontSize = 12;
    double leading = 14;

    // Track whether CTM flips Y at the time of first text extraction
    bool? yFlippedAtFirstText;

    while (i < text.length) {
      // Skip whitespace
      while (i < text.length && _isSpace(text.codeUnitAt(i))) i++;
      if (i >= text.length) break;

      // (G) q — save graphics state
      if (text[i] == 'q' &&
          (i == 0 || _isSpace(text.codeUnitAt(i - 1))) &&
          (i + 1 >= text.length || _isSpace(text.codeUnitAt(i + 1)))) {
        gfxStack.add(
          _GfxState(
            ctm: ctm,
            fontSize: fontSize,
            leading: leading,
            charSpacing: charSpacing,
            wordSpacing: wordSpacing,
            font: activeFont,
          ),
        );
        i++;
        continue;
      }

      // (G) Q — restore graphics state
      if (text[i] == 'Q' &&
          (i == 0 || _isSpace(text.codeUnitAt(i - 1))) &&
          (i + 1 >= text.length || _isSpace(text.codeUnitAt(i + 1)))) {
        if (gfxStack.isNotEmpty) {
          final saved = gfxStack.removeLast();
          ctm = saved.ctm;
          fontSize = saved.fontSize;
          leading = saved.leading;
          charSpacing = saved.charSpacing;
          wordSpacing = saved.wordSpacing;
          activeFont = saved.font;
        }
        i++;
        continue;
      }

      // (F) cm — concat matrix: a b c d e f cm
      if (i + 1 < text.length &&
          text[i] == 'c' &&
          text[i + 1] == 'm' &&
          (i + 2 >= text.length || _isSpace(text.codeUnitAt(i + 2))) &&
          (i == 0 || _isSpace(text.codeUnitAt(i - 1)))) {
        final preceding = _getPrecedingTokens(text, i, 6);
        if (preceding.length >= 6) {
          final a = double.tryParse(preceding[0]) ?? 1;
          final b = double.tryParse(preceding[1]) ?? 0;
          final c = double.tryParse(preceding[2]) ?? 0;
          final d = double.tryParse(preceding[3]) ?? 1;
          final e = double.tryParse(preceding[4]) ?? 0;
          final f = double.tryParse(preceding[5]) ?? 0;
          ctm = ctm.concat(_Matrix(a, b, c, d, e, f));
        }
        i += 2;
        continue;
      }

      // BT — begin text object
      if (text[i] == 'B' && i + 1 < text.length && text[i + 1] == 'T') {
        if (i > 0 && !_isSpace(text.codeUnitAt(i - 1))) {
          i += 2;
          continue;
        }

        final etIdx = text.indexOf('ET', i + 2);
        if (etIdx < 0) break;

        if (needsSpace && buf.isNotEmpty) buf.write(' ');

        // Capture CTM Y-flip state at first text block
        yFlippedAtFirstText ??= ctm.d < 0;

        final textBlock = text.substring(i + 2, etIdx);
        _extractTextFromBlock(
          textBlock,
          buf,
          rects,
          fonts,
          activeFont,
          ctm: ctm,
          charSpacing: charSpacing,
          wordSpacing: wordSpacing,
          initialFontSize: fontSize,
          initialLeading: leading,
        );
        needsSpace = true;
        i = etIdx + 2;
        continue;
      }

      i++;
    }

    return ExtractedPageText(
      buf.toString(),
      rects,
      isYFlipped: yFlippedAtFirstText ?? false,
    );
  }

  void _extractTextFromBlock(
    String block,
    StringBuffer buf,
    List<PdfTextRect> rects,
    Map<String, _FontInfo> fonts,
    _FontInfo activeFont, {
    _Matrix ctm = _Matrix.identity,
    double charSpacing = 0,
    double wordSpacing = 0,
    double initialFontSize = 12,
    double initialLeading = 14,
  }) {
    var i = 0;
    final len = block.length;

    double tx = 0, ty = 0;
    double tfSize = initialFontSize; // Size from Tf operator
    double tmScaleY = 1.0; // Y scale from Tm text matrix
    double fontSize = initialFontSize; // Effective = tfSize * tmScaleY
    double leading = initialLeading;
    double tc = charSpacing; // (I) character spacing
    double tw = wordSpacing; // (I) word spacing
    _FontInfo font = activeFont;

    while (i < len) {
      while (i < len && _isSpace(block.codeUnitAt(i))) i++;
      if (i >= len) break;

      // --- Tf: /FontName fontSize Tf ---
      if (_matchOp(block, i, 'Tf')) {
        final preceding = _getPrecedingTokens(block, i, 2);
        if (preceding.length >= 2) {
          tfSize = double.tryParse(preceding[1]) ?? tfSize;
          fontSize = tfSize * tmScaleY; // Recalculate effective size
          final fontName =
              preceding[0].startsWith('/')
                  ? preceding[0].substring(1)
                  : preceding[0];
          font = fonts[fontName] ?? _FontInfo.fallback;
        }
        i += 2;
        continue;
      }

      // --- Tm: a b c d tx ty Tm ---
      if (_matchOp(block, i, 'Tm')) {
        final preceding = _getPrecedingTokens(block, i, 6);
        if (preceding.length >= 6) {
          final a = (double.tryParse(preceding[0]) ?? 1).abs();
          final d = (double.tryParse(preceding[3]) ?? 1).abs();
          // Use |d| as Y scale; if zero (some PDFs encode size only in |a|
          // or use non-standard matrices), fall back to |a| → the X scale
          // is typically equal to the intended font size.
          tmScaleY = d > 0.001 ? d : (a > 0.001 ? a : tmScaleY);
          tx = double.tryParse(preceding[4]) ?? tx;
          ty = double.tryParse(preceding[5]) ?? ty;
          fontSize = tfSize * tmScaleY; // Recalculate effective size
        }
        i += 2;
        continue;
      }

      // --- Td ---
      if (_matchOp(block, i, 'Td')) {
        final preceding = _getPrecedingTokens(block, i, 2);
        if (preceding.length >= 2) {
          tx += double.tryParse(preceding[0]) ?? 0;
          ty += double.tryParse(preceding[1]) ?? 0;
        }
        _appendSpace(buf);
        i += 2;
        continue;
      }

      // --- TD ---
      if (_matchOp(block, i, 'TD')) {
        final preceding = _getPrecedingTokens(block, i, 2);
        if (preceding.length >= 2) {
          final dx = double.tryParse(preceding[0]) ?? 0;
          final dy = double.tryParse(preceding[1]) ?? 0;
          tx += dx;
          ty += dy;
          leading = -dy;
        }
        _appendSpace(buf);
        i += 2;
        continue;
      }

      // --- T* ---
      if (i + 1 < len && block[i] == 'T' && block[i + 1] == '*') {
        if (i + 2 >= len || _isSpace(block.codeUnitAt(i + 2))) {
          tx = 0;
          ty -= leading;
          _appendSpace(buf);
          i += 2;
          continue;
        }
      }

      // --- TL ---
      if (_matchOp(block, i, 'TL')) {
        final preceding = _getPrecedingTokens(block, i, 1);
        if (preceding.isNotEmpty) {
          leading = double.tryParse(preceding[0]) ?? leading;
        }
        i += 2;
        continue;
      }

      // --- Tc: charSpacing Tc ---
      if (_matchOp(block, i, 'Tc')) {
        final preceding = _getPrecedingTokens(block, i, 1);
        if (preceding.isNotEmpty) {
          tc = double.tryParse(preceding[0]) ?? tc;
        }
        i += 2;
        continue;
      }

      // --- Tw: wordSpacing Tw ---
      if (_matchOp(block, i, 'Tw')) {
        final preceding = _getPrecedingTokens(block, i, 1);
        if (preceding.isNotEmpty) {
          tw = double.tryParse(preceding[0]) ?? tw;
        }
        i += 2;
        continue;
      }

      // --- Literal string (...) ---
      if (block[i] == '(') {
        final str = _parseLiteralString(block, i);
        if (str.text.isNotEmpty) {
          final decoded = _decodeString(str.text, font);
          final width = _measureStringWithSpacing(
            str.text,
            font,
            fontSize,
            tc,
            tw,
            decoded: decoded,
          );
          _addTextRect(
            rects,
            buf.length,
            decoded,
            str.text,
            tx,
            ty,
            fontSize,
            width,
            font,
            tc,
            tw,
            ctm: ctm,
          );
          buf.write(decoded);
          tx += width;
        }
        i = str.endIdx;
        continue;
      }

      // --- Hex string <...> ---
      if (block[i] == '<' && (i + 1 >= len || block[i + 1] != '<')) {
        final str = _parseHexString(block, i);
        if (str.text.isNotEmpty) {
          final decoded = _decodeHexString(str.rawCodes, font);
          final width = _measureHexStringWithSpacing(
            str.rawCodes,
            font,
            fontSize,
            tc,
            tw,
            decoded: decoded,
          );
          _addTextRectForHex(
            rects,
            buf.length,
            decoded,
            str.rawCodes,
            tx,
            ty,
            fontSize,
            width,
            font,
            tc,
            tw,
            ctm: ctm,
          );
          buf.write(decoded);
          tx += width;
        }
        i = str.endIdx;
        continue;
      }

      // --- TJ array [...] ---
      if (block[i] == '[') {
        final arrayEnd = _findMatchingBracket(block, i);
        if (arrayEnd >= 0) {
          tx = _extractTextFromArray(
            block.substring(i + 1, arrayEnd),
            buf,
            rects,
            tx,
            ty,
            fontSize,
            font,
            tc: tc,
            tw: tw,
            ctm: ctm,
          );
          i = arrayEnd + 1;
          continue;
        }
      }

      // --- ' operator ---
      if (block[i] == "'" && i > 0 && _isSpace(block.codeUnitAt(i - 1))) {
        tx = 0;
        ty -= leading;
        _appendSpace(buf);
        i++;
        continue;
      }

      i++;
    }
  }

  /// Decode a literal string using the font's encoding.
  String _decodeString(String raw, _FontInfo font) {
    if (font.toUnicode.isEmpty && font.differences.isEmpty) return raw;

    final buf = StringBuffer();
    for (int i = 0; i < raw.length; i++) {
      final code = raw.codeUnitAt(i);
      final decoded = font.decode(code);
      buf.write(decoded ?? raw[i]);
    }
    return buf.toString();
  }

  /// Decode hex string codes using font encoding.
  String _decodeHexString(List<int> codes, _FontInfo font) {
    if (font.toUnicode.isEmpty && font.differences.isEmpty) {
      return String.fromCharCodes(codes.where((c) => c >= 32));
    }

    final buf = StringBuffer();
    for (final code in codes) {
      final decoded = font.decode(code);
      if (decoded != null) {
        buf.write(decoded);
      } else if (code >= 32) {
        buf.writeCharCode(code);
      }
    }
    return buf.toString();
  }

  /// Measure string width using font widths + Tc/Tw.
  ///
  /// When font widths are empty, uses [decoded] Unicode char codes
  /// so the Latin fallback table gives proportional widths.
  double _measureStringWithSpacing(
    String text,
    _FontInfo font,
    double fontSize,
    double tc,
    double tw, {
    String? decoded,
  }) {
    double w = 0;
    final n =
        decoded != null && decoded.length < text.length
            ? decoded.length
            : text.length;
    for (int i = 0; i < n; i++) {
      final rawCode = text.codeUnitAt(i);
      final uniCode =
          decoded != null && i < decoded.length ? decoded.codeUnitAt(i) : null;
      w += font.charWidth(rawCode, unicodeCode: uniCode) * fontSize + tc;
      if (rawCode == 0x20 || (uniCode != null && uniCode == 0x20)) w += tw;
    }
    return w;
  }

  /// Measure hex string width using font widths + Tc/Tw.
  double _measureHexStringWithSpacing(
    List<int> codes,
    _FontInfo font,
    double fontSize,
    double tc,
    double tw, {
    String? decoded,
  }) {
    double w = 0;
    final n =
        decoded != null && decoded.length < codes.length
            ? decoded.length
            : codes.length;
    for (int i = 0; i < n; i++) {
      final rawCode = codes[i];
      final uniCode =
          decoded != null && i < decoded.length ? decoded.codeUnitAt(i) : null;
      w += font.charWidth(rawCode, unicodeCode: uniCode) * fontSize + tc;
      if (rawCode == 0x20 || (uniCode != null && uniCode == 0x20)) w += tw;
    }
    return w;
  }

  int _countSpaces(String text) {
    int count = 0;
    for (int i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x20) count++;
    }
    return count;
  }

  double _extractTextFromArray(
    String array,
    StringBuffer buf,
    List<PdfTextRect> rects,
    double tx,
    double ty,
    double fontSize,
    _FontInfo font, {
    double tc = 0,
    double tw = 0,
    _Matrix ctm = _Matrix.identity,
  }) {
    var i = 0;
    final len = array.length;
    var localTx = tx;

    while (i < len) {
      while (i < len && _isSpace(array.codeUnitAt(i))) i++;
      if (i >= len) break;

      if (array[i] == '(') {
        final str = _parseLiteralString(array, i);
        if (str.text.isNotEmpty) {
          final decoded = _decodeString(str.text, font);
          final width = _measureStringWithSpacing(
            str.text,
            font,
            fontSize,
            tc,
            tw,
            decoded: decoded,
          );
          _addTextRect(
            rects,
            buf.length,
            decoded,
            str.text,
            localTx,
            ty,
            fontSize,
            width,
            font,
            tc,
            tw,
            ctm: ctm,
          );
          buf.write(decoded);
          localTx += width;
        }
        i = str.endIdx;
      } else if (array[i] == '<') {
        final str = _parseHexString(array, i);
        if (str.text.isNotEmpty) {
          final decoded = _decodeHexString(str.rawCodes, font);
          final width = _measureHexStringWithSpacing(
            str.rawCodes,
            font,
            fontSize,
            tc,
            tw,
            decoded: decoded,
          );
          _addTextRectForHex(
            rects,
            buf.length,
            decoded,
            str.rawCodes,
            localTx,
            ty,
            fontSize,
            width,
            font,
            tc,
            tw,
            ctm: ctm,
          );
          buf.write(decoded);
          localTx += width;
        }
        i = str.endIdx;
      } else {
        final numStart = i;
        while (i < len &&
            !_isSpace(array.codeUnitAt(i)) &&
            array[i] != '(' &&
            array[i] != '<') {
          i++;
        }
        final numStr = array.substring(numStart, i);
        final num = double.tryParse(numStr);
        if (num != null) {
          localTx -= num * fontSize / 1000;
          if (num < -120) _appendSpace(buf);
        }
      }
    }

    return localTx;
  }

  // ---------------------------------------------------------------------------
  // Merge consecutive rects on the same Y-line into single wide rects.
  //
  // This eliminates accumulated tx drift: the merged rect's left edge comes
  // from the first run's PDF position (exact from Tm/Td). Per-run
  // charPositions (computed from actual font metrics in _addTextRect) are
  // remapped into the merged rect's coordinate system.
  // ---------------------------------------------------------------------------

  /// Merge consecutive text rects that share the same Y-coordinate (±2pt)
  /// into single wide rects, one per text line.
  ///
  /// Remaps each rect's [PdfTextRect.charPositions] (computed from real font
  /// metrics) into the merged rect's coordinate system, preserving both
  /// exact run boundaries and within-run proportional subdivision.
  List<PdfTextRect> _mergeLineRects(List<PdfTextRect> rects) {
    if (rects.length <= 1) return rects;

    final merged = <PdfTextRect>[];
    var currentText = StringBuffer(rects[0].text);
    var currentRect = rects[0].rect;
    var currentOffset = rects[0].charOffset;
    var nextExpectedOffset = currentOffset + rects[0].text.length;
    // Collect rects for the current line to remap charPositions
    var lineRects = <PdfTextRect>[rects[0]];
    var gapsBefore = <int>[0]; // gap spaces inserted before each rect

    for (int i = 1; i < rects.length; i++) {
      final r = rects[i];
      final currentMidY = (currentRect.top + currentRect.bottom) / 2;
      final rMidY = (r.rect.top + r.rect.bottom) / 2;
      final sameLine = (currentMidY - rMidY).abs() < 2.0;

      if (sameLine) {
        final gap = r.charOffset - nextExpectedOffset;
        int gapChars = 0;
        if (gap > 0) {
          for (int s = 0; s < gap; s++) {
            currentText.write(' ');
          }
          gapChars = gap;
        }
        currentText.write(r.text);
        nextExpectedOffset = r.charOffset + r.text.length;
        currentRect = Rect.fromLTRB(
          currentRect.left,
          currentRect.top < r.rect.top ? currentRect.top : r.rect.top,
          r.rect.right,
          currentRect.bottom > r.rect.bottom
              ? currentRect.bottom
              : r.rect.bottom,
        );
        lineRects.add(r);
        gapsBefore.add(gapChars);
      } else {
        merged.add(
          PdfTextRect(
            rect: currentRect,
            text: currentText.toString(),
            charOffset: currentOffset,
            charPositions: _remapCharPositions(
              lineRects,
              gapsBefore,
              currentRect,
            ),
          ),
        );
        currentText = StringBuffer(r.text);
        currentRect = r.rect;
        currentOffset = r.charOffset;
        nextExpectedOffset = r.charOffset + r.text.length;
        lineRects = <PdfTextRect>[r];
        gapsBefore = <int>[0];
      }
    }
    merged.add(
      PdfTextRect(
        rect: currentRect,
        text: currentText.toString(),
        charOffset: currentOffset,
        charPositions: _remapCharPositions(lineRects, gapsBefore, currentRect),
      ),
    );

    return merged;
  }

  /// Remap per-rect charPositions into the merged rect's coordinate system.
  ///
  /// For each source rect, its charPositions (0.0–1.0 within that rect's
  /// width) are converted to fractions of the merged rect's width using:
  ///   mergedFrac = (rect.left - merged.left + cp[i] * rect.width) / merged.width
  ///
  /// Gap spaces between rects are uniformly distributed in the gap region.
  List<double>? _remapCharPositions(
    List<PdfTextRect> lineRects,
    List<int> gapsBefore,
    Rect mergedRect,
  ) {
    final mergedWidth = mergedRect.width;
    if (mergedWidth <= 0) return null;

    // Count total characters
    int totalChars = 0;
    for (int i = 0; i < lineRects.length; i++) {
      totalChars += gapsBefore[i] + lineRects[i].text.length;
    }
    if (totalChars == 0) return null;

    final positions = List<double>.filled(totalChars + 1, 0.0);
    int charIdx = 0;

    for (int r = 0; r < lineRects.length; r++) {
      final rect = lineRects[r];
      final gapChars = gapsBefore[r];
      final cp = rect.charPositions;
      final textLen = rect.text.length;

      // Fractional boundaries of this rect within the merged rect
      final rectLeftFrac = (rect.rect.left - mergedRect.left) / mergedWidth;
      final rectRightFrac = (rect.rect.right - mergedRect.left) / mergedWidth;

      // Gap spaces: interpolate from previous position to this rect's left
      if (gapChars > 0) {
        final gapStart = charIdx > 0 ? positions[charIdx] : 0.0;
        for (int g = 0; g < gapChars; g++) {
          positions[charIdx] =
              gapStart + (rectLeftFrac - gapStart) * g / gapChars;
          charIdx++;
        }
      }

      // Remap this rect's charPositions into merged coords
      if (cp != null && cp.length == textLen + 1) {
        // Use pre-computed charPositions
        final rectWidth = rectRightFrac - rectLeftFrac;
        for (int c = 0; c <= textLen; c++) {
          if (charIdx + c <= totalChars) {
            positions[charIdx + c] = (rectLeftFrac + cp[c] * rectWidth).clamp(
              0.0,
              1.0,
            );
          }
        }
      } else {
        // Fallback: uniform subdivision within this rect.
        // For single-run lines with unknown font metrics, uniform
        // distribution is more reliable than Latin-weight assumptions.
        for (int c = 0; c <= textLen; c++) {
          final frac = textLen > 0 ? c / textLen : 0.0;
          if (charIdx + c <= totalChars) {
            final pos = rectLeftFrac + (rectRightFrac - rectLeftFrac) * frac;
            positions[charIdx + c] = pos.clamp(0.0, 1.0);
          }
        }
      }
      charIdx += textLen;
    }

    // Ensure last position is 1.0
    if (positions.isNotEmpty) positions[totalChars] = 1.0;

    return positions;
  }

  // ---------------------------------------------------------------------------
  // Rect + helpers
  // ---------------------------------------------------------------------------

  /// Create a single multi-char rect for the entire text run.
  ///
  /// Instead of per-char rects (which accumulate tx drift), we emit ONE rect
  /// with the full decoded text. Per-character clipping is handled in
  /// [_remapCharPositions] using run boundaries and Latin proportional widths.
  void _addTextRect(
    List<PdfTextRect> rects,
    int charOffset,
    String decoded,
    String rawText,
    double tx,
    double ty,
    double fontSize,
    double totalWidth,
    _FontInfo font,
    double tc,
    double tw, {
    _Matrix ctm = _Matrix.identity,
  }) {
    if (decoded.isEmpty) return;

    final yTop = ty - fontSize * 0.2;
    final yBot = ty + fontSize;
    final (x0, y0) = ctm.transform(tx, yTop);
    final (x1, y1) = ctm.transform(tx + totalWidth, yBot);
    rects.add(
      PdfTextRect(
        rect: Rect.fromLTRB(
          x0 < x1 ? x0 : x1,
          y0 < y1 ? y0 : y1,
          x0 > x1 ? x0 : x1,
          y0 > y1 ? y0 : y1,
        ),
        text: decoded,
        charOffset: charOffset,
      ),
    );
  }

  /// Like [_addTextRect] but for hex strings using raw glyph codes.
  void _addTextRectForHex(
    List<PdfTextRect> rects,
    int charOffset,
    String decoded,
    List<int> rawCodes,
    double tx,
    double ty,
    double fontSize,
    double totalWidth,
    _FontInfo font,
    double tc,
    double tw, {
    _Matrix ctm = _Matrix.identity,
  }) {
    if (decoded.isEmpty) return;

    final yTop = ty - fontSize * 0.2;
    final yBot = ty + fontSize;
    final (x0, y0) = ctm.transform(tx, yTop);
    final (x1, y1) = ctm.transform(tx + totalWidth, yBot);
    rects.add(
      PdfTextRect(
        rect: Rect.fromLTRB(
          x0 < x1 ? x0 : x1,
          y0 < y1 ? y0 : y1,
          x0 > x1 ? x0 : x1,
          y0 > y1 ? y0 : y1,
        ),
        text: decoded,
        charOffset: charOffset,
      ),
    );
  }

  bool _matchOp(String block, int pos, String op) {
    if (pos + op.length > block.length) return false;
    for (int j = 0; j < op.length; j++) {
      if (block.codeUnitAt(pos + j) != op.codeUnitAt(j)) return false;
    }
    final afterIdx = pos + op.length;
    if (afterIdx >= block.length) return true;
    return _isSpace(block.codeUnitAt(afterIdx));
  }

  void _appendSpace(StringBuffer buf) {
    if (buf.isEmpty) return;
    final s = buf.toString();
    if (s.isNotEmpty && s[s.length - 1] != ' ') buf.write(' ');
  }

  List<String> _getPrecedingTokens(String block, int pos, int count) {
    final tokens = <String>[];
    var i = pos - 1;
    while (i >= 0 && tokens.length < count) {
      while (i >= 0 && _isSpace(block.codeUnitAt(i))) i--;
      if (i < 0) break;
      final end = i + 1;
      while (i >= 0 && !_isSpace(block.codeUnitAt(i))) i--;
      tokens.insert(0, block.substring(i + 1, end));
    }
    return tokens;
  }

  /// Like _getPrecedingTokens but works on a full-text string (outside BT blocks).
  /// Used for parsing `cm` operator arguments from the top-level stream.
  List<String> _getPrecedingTokensFromFull(String text, int pos, int count) {
    final tokens = <String>[];
    var i = pos - 1;
    while (i >= 0 && tokens.length < count) {
      while (i >= 0 && _isSpace(text.codeUnitAt(i))) i--;
      if (i < 0) break;
      final end = i + 1;
      while (i >= 0 && !_isSpace(text.codeUnitAt(i))) i--;
      tokens.insert(0, text.substring(i + 1, end));
    }
    return tokens;
  }

  // ---------------------------------------------------------------------------
  // String parsers
  // ---------------------------------------------------------------------------

  _ParsedString _parseLiteralString(String text, int start) {
    final buf = StringBuffer();
    var depth = 0;
    var i = start;
    final len = text.length;

    if (i < len && text[i] == '(') {
      depth = 1;
      i++;
    }

    while (i < len && depth > 0) {
      final c = text[i];
      if (c == '\\' && i + 1 < len) {
        i++;
        final esc = text[i];
        switch (esc) {
          case 'n':
          case 'r':
            buf.write(' ');
            break;
          case 't':
            buf.write(' ');
            break;
          case '(':
            buf.write('(');
            break;
          case ')':
            buf.write(')');
            break;
          case '\\':
            buf.write('\\');
            break;
          default:
            if (esc.codeUnitAt(0) >= 0x30 && esc.codeUnitAt(0) <= 0x37) {
              var octal = esc;
              if (i + 1 < len &&
                  text[i + 1].codeUnitAt(0) >= 0x30 &&
                  text[i + 1].codeUnitAt(0) <= 0x37) {
                octal += text[++i];
              }
              if (i + 1 < len &&
                  text[i + 1].codeUnitAt(0) >= 0x30 &&
                  text[i + 1].codeUnitAt(0) <= 0x37) {
                octal += text[++i];
              }
              final code = int.tryParse(octal, radix: 8) ?? 0;
              if (code > 0) buf.writeCharCode(code);
            } else {
              buf.write(esc);
            }
        }
      } else if (c == '(') {
        depth++;
        buf.write(c);
      } else if (c == ')') {
        depth--;
        if (depth > 0) buf.write(c);
      } else {
        buf.write(c.codeUnitAt(0) >= 32 || c == '\t' ? c : ' ');
      }
      i++;
    }

    return _ParsedString(buf.toString(), i, const []);
  }

  _ParsedString _parseHexString(String text, int start) {
    final buf = StringBuffer();
    final rawCodes = <int>[];
    var i = start + 1;
    final len = text.length;
    final hexBuf = StringBuffer();

    while (i < len && text[i] != '>') {
      if (!_isSpace(text.codeUnitAt(i))) hexBuf.write(text[i]);
      i++;
    }
    if (i < len) i++;

    final hex = hexBuf.toString();

    if (hex.length >= 4 && hex.length % 4 == 0) {
      for (var h = 0; h + 3 < hex.length; h += 4) {
        final code = int.tryParse(hex.substring(h, h + 4), radix: 16);
        if (code != null) {
          rawCodes.add(code);
          if (code >= 32) buf.writeCharCode(code);
        }
      }
    } else {
      for (var h = 0; h + 1 < hex.length; h += 2) {
        final code = int.tryParse(hex.substring(h, h + 2), radix: 16);
        if (code != null) {
          rawCodes.add(code);
          if (code >= 32) buf.writeCharCode(code);
        }
      }
    }

    return _ParsedString(buf.toString(), i, rawCodes);
  }

  // ---------------------------------------------------------------------------
  // Fallback: scan all streams
  // ---------------------------------------------------------------------------

  List<ExtractedPageText> _extractFallback(int? pageCount) {
    final blocks = <ExtractedPageText>[];

    final streamMarker = ascii.encode('stream');
    final endstreamMarker = ascii.encode('endstream');
    final flatDecodeMarker = ascii.encode('/FlateDecode');

    int pos = 0;
    final len = _bytes.length;

    while (pos < len - 10) {
      final streamIdx = _indexOfBytes(_bytes, streamMarker, pos);
      if (streamIdx < 0) break;

      final dictStart = _findDictStart(streamIdx);
      final usesFlate =
          dictStart >= 0 &&
          _indexOfBytes(_bytes, flatDecodeMarker, dictStart, streamIdx) >= 0;

      var dataStart = streamIdx + 6;
      if (dataStart < len && _bytes[dataStart] == 0x0D) dataStart++;
      if (dataStart < len && _bytes[dataStart] == 0x0A) dataStart++;

      final endstreamIdx = _indexOfBytes(_bytes, endstreamMarker, dataStart);
      if (endstreamIdx < 0) {
        pos = dataStart;
        continue;
      }

      var dataEnd = endstreamIdx;
      if (dataEnd > dataStart && _bytes[dataEnd - 1] == 0x0A) dataEnd--;
      if (dataEnd > dataStart && _bytes[dataEnd - 1] == 0x0D) dataEnd--;

      if (dataEnd > dataStart) {
        final raw = _bytes.sublist(dataStart, dataEnd);
        Uint8List decoded;
        if (usesFlate) {
          try {
            decoded = Uint8List.fromList(zlib.decode(raw));
          } catch (_) {
            pos = endstreamIdx + 9;
            continue;
          }
        } else {
          decoded = raw;
        }

        final result = _extractTextFromStream(decoded);
        if (result.text.isNotEmpty) blocks.add(result);
      }

      pos = endstreamIdx + 9;
    }

    if (blocks.isEmpty) {
      return List.filled(pageCount ?? 0, ExtractedPageText.empty);
    }
    if (pageCount == null || pageCount <= 0) return blocks;
    if (blocks.length == pageCount) return blocks;

    // Distribute
    final result = List.filled(pageCount, ExtractedPageText.empty);
    if (blocks.length > pageCount) {
      final bpp = blocks.length / pageCount;
      for (int p = 0; p < pageCount; p++) {
        final s = (p * bpp).round();
        final e = ((p + 1) * bpp).round().clamp(s + 1, blocks.length);
        result[p] = _mergeBlocks(blocks.sublist(s, e));
      }
    } else {
      for (int i = 0; i < blocks.length; i++) {
        final pi = (i * pageCount / blocks.length).floor().clamp(
          0,
          pageCount - 1,
        );
        result[pi] =
            result[pi] == ExtractedPageText.empty
                ? blocks[i]
                : _mergeBlocks([result[pi], blocks[i]]);
      }
    }
    return result;
  }

  ExtractedPageText _mergeBlocks(List<ExtractedPageText> blocks) {
    final text = StringBuffer();
    final rects = <PdfTextRect>[];
    for (final b in blocks) {
      final offset = text.length;
      if (text.isNotEmpty) text.write(' ');
      final shift = offset + (offset > 0 ? 1 : 0);
      for (final r in b.rects) {
        rects.add(
          PdfTextRect(
            rect: r.rect,
            text: r.text,
            charOffset: r.charOffset + shift,
          ),
        );
      }
      text.write(b.text);
    }
    return ExtractedPageText(text.toString(), rects);
  }

  // ---------------------------------------------------------------------------
  // Utilities
  // ---------------------------------------------------------------------------

  int _findDictStart(int streamIdx) {
    final searchStart = (streamIdx - 2000).clamp(0, streamIdx);
    for (int i = streamIdx - 2; i >= searchStart; i--) {
      if (_bytes[i] == 0x3C && _bytes[i + 1] == 0x3C) return i;
    }
    return -1;
  }

  int _indexOfBytes(
    Uint8List haystack,
    List<int> needle,
    int from, [
    int? end,
  ]) {
    final limit = (end ?? haystack.length) - needle.length;
    outer:
    for (int i = from; i <= limit; i++) {
      for (int j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  int _findMatchingBracket(String text, int start) {
    var depth = 0;
    var i = start;
    final len = text.length;
    while (i < len) {
      if (text[i] == '[') {
        depth++;
      } else if (text[i] == ']') {
        depth--;
        if (depth == 0) return i;
      } else if (text[i] == '(') {
        final s = _parseLiteralString(text, i);
        i = s.endIdx;
        continue;
      }
      i++;
    }
    return -1;
  }

  bool _isSpace(int c) => c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;
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
