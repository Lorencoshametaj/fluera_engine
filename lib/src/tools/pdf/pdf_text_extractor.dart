import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../core/models/pdf_text_rect.dart';


part '_pdf_text_helpers.dart';
part '_pdf_text_parsing.dart';
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
      if (result.isNotEmpty) {
        final p0 = result.first;
        if (p0.rects.isNotEmpty) {
          final r = p0.rects.first;
        }
      }
      return result;
    } catch (e) {
      try {
        final result = _extractFallback(pageCount);
        return result;
      } catch (e2) {
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
