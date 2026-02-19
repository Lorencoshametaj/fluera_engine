import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

// =============================================================================
// 📄 PURE-DART PDF TEXT EXTRACTION  (v2 — stream-scan approach)
// =============================================================================
//
// Extracts plain text from PDF files without any native dependency.
//
// APPROACH:
//   Instead of parsing the PDF page tree (fragile, fails on many generators),
//   this scans the raw bytes for ALL stream/endstream pairs, decompresses them,
//   and extracts text from content streams that contain BT...ET text blocks.
//
//   Text-producing streams are collected in document order and distributed
//   across the known page count.
//
// HANDLES:
//   ✓ FlateDecode compressed streams
//   ✓ Tj, TJ, ', " text-showing operators
//   ✓ Literal strings (...) and hex strings <...>
//   ✓ Large negative kerning as word separators
//   ✓ Line-break operators (Td, TD, T*) as spaces
//
// LIMITATIONS:
//   ✗ Encrypted PDFs
//   ✗ Custom Type1 glyph encodings (uses raw byte values)
//   ✗ ToUnicode CMap remapping
//   ✗ XRef streams (works with cross-ref tables only)
// =============================================================================

/// Extracts text from a PDF file given its raw bytes.
class PdfTextExtractor {
  final Uint8List _bytes;

  PdfTextExtractor(this._bytes);

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Extract text from all pages.
  ///
  /// Returns a list of strings. If [pageCount] is provided, ensures the output
  /// has exactly that many entries (distributing extracted text blocks evenly).
  List<String> extractAllPages({int? pageCount}) {
    try {
      final textBlocks = _extractAllTextBlocks();
      if (textBlocks.isEmpty) return List.filled(pageCount ?? 0, '');

      if (pageCount == null || pageCount <= 0) {
        return textBlocks;
      }

      // Distribute text blocks across pages
      if (textBlocks.length == pageCount) {
        return textBlocks;
      } else if (textBlocks.length > pageCount) {
        // More blocks than pages — merge adjacent blocks
        final result = List.filled(pageCount, '');
        final blocksPerPage = textBlocks.length / pageCount;
        for (int p = 0; p < pageCount; p++) {
          final start = (p * blocksPerPage).round();
          final end = ((p + 1) * blocksPerPage).round().clamp(
            start + 1,
            textBlocks.length,
          );
          result[p] = textBlocks.sublist(start, end).join(' ');
        }
        return result;
      } else {
        // Fewer blocks than pages — assign blocks to first N pages
        final result = List.filled(pageCount, '');
        for (int i = 0; i < textBlocks.length; i++) {
          final pageIdx = (i * pageCount / textBlocks.length).floor().clamp(
            0,
            pageCount - 1,
          );
          if (result[pageIdx].isEmpty) {
            result[pageIdx] = textBlocks[i];
          } else {
            result[pageIdx] += ' ${textBlocks[i]}';
          }
        }
        return result;
      }
    } catch (e) {
      debugPrint('[PdfTextExtractor] Error: $e');
      return List.filled(pageCount ?? 0, '');
    }
  }

  /// Extract text for a specific page index (0-based).
  String extractPage(int pageIndex, {int? totalPages}) {
    final all = extractAllPages(pageCount: totalPages);
    if (pageIndex < 0 || pageIndex >= all.length) return '';
    return all[pageIndex];
  }

  // ---------------------------------------------------------------------------
  // Stream scanning
  // ---------------------------------------------------------------------------

  /// Scan the entire PDF for stream/endstream pairs, decompress them,
  /// and extract text from those containing BT...ET blocks.
  ///
  /// Returns a list of non-empty text strings, one per text-producing stream,
  /// in document order.
  List<String> _extractAllTextBlocks() {
    final results = <String>[];

    // Markers in raw bytes
    final streamMarker = ascii.encode('stream');
    final endstreamMarker = ascii.encode('endstream');
    final flatDecodeMarker = ascii.encode('/FlateDecode');

    int pos = 0;
    final len = _bytes.length;

    while (pos < len - 10) {
      // Find next "stream" keyword
      final streamIdx = _indexOfBytes(_bytes, streamMarker, pos);
      if (streamIdx < 0) break;

      // Check if stream keyword is preceded by a dictionary (look back for "<<")
      // and determine if FlateDecode is used
      final dictStart = _findDictStart(streamIdx);
      final usesFlate =
          dictStart >= 0 &&
          _indexOfBytes(_bytes, flatDecodeMarker, dictStart, streamIdx) >= 0;

      // Skip past "stream" and \r\n or \n
      var dataStart = streamIdx + 6; // "stream".length
      if (dataStart < len && _bytes[dataStart] == 0x0D) dataStart++;
      if (dataStart < len && _bytes[dataStart] == 0x0A) dataStart++;

      // Find the matching "endstream"
      final endstreamIdx = _indexOfBytes(_bytes, endstreamMarker, dataStart);
      if (endstreamIdx < 0) {
        pos = dataStart;
        continue;
      }

      // Back up over trailing whitespace before endstream
      var dataEnd = endstreamIdx;
      if (dataEnd > dataStart && _bytes[dataEnd - 1] == 0x0A) dataEnd--;
      if (dataEnd > dataStart && _bytes[dataEnd - 1] == 0x0D) dataEnd--;

      if (dataEnd > dataStart) {
        final rawStream = _bytes.sublist(dataStart, dataEnd);

        Uint8List decoded;
        if (usesFlate) {
          try {
            decoded = Uint8List.fromList(zlib.decode(rawStream));
          } catch (_) {
            // Decompression failed — skip this stream
            pos = endstreamIdx + 9;
            continue;
          }
        } else {
          decoded = rawStream;
        }

        // Try extracting text from this stream
        final text = _extractTextFromStream(decoded);
        if (text.isNotEmpty) {
          results.add(text);
        }
      }

      pos = endstreamIdx + 9; // "endstream".length
    }

    return results;
  }

  /// Find the start of the dictionary for a stream by scanning backwards
  /// from [streamIdx] looking for "<<".
  int _findDictStart(int streamIdx) {
    // Look back at most 2000 bytes for the dictionary start
    final searchStart = (streamIdx - 2000).clamp(0, streamIdx);
    for (int i = streamIdx - 2; i >= searchStart; i--) {
      if (_bytes[i] == 0x3C && _bytes[i + 1] == 0x3C) {
        // "<<"
        return i;
      }
    }
    return -1;
  }

  /// Find the index of [needle] in [haystack] starting at [from], up to [end].
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

  // ---------------------------------------------------------------------------
  // Text extraction from decoded content streams
  // ---------------------------------------------------------------------------

  /// Extract text from a decoded PDF content stream.
  String _extractTextFromStream(Uint8List streamData) {
    // Quick check: does this stream contain BT (Begin Text)?
    // If not, it's not a text-producing stream (e.g., image XObject).
    if (_indexOfBytes(streamData, [0x42, 0x54], 0) < 0) {
      // "BT"
      return '';
    }

    final text = utf8.decode(streamData, allowMalformed: true);
    final buffer = StringBuffer();
    var i = 0;

    while (i < text.length) {
      // Find "BT" (Begin Text Object)
      final btIdx = text.indexOf('BT', i);
      if (btIdx < 0) break;

      // Verify it's a standalone operator (preceded by whitespace or start)
      if (btIdx > 0 && !_isSpace(text.codeUnitAt(btIdx - 1))) {
        i = btIdx + 2;
        continue;
      }

      final etIdx = text.indexOf('ET', btIdx + 2);
      if (etIdx < 0) break;

      final textBlock = text.substring(btIdx + 2, etIdx);
      _extractTextFromBlock(textBlock, buffer);
      buffer.write(' '); // space between text blocks
      i = etIdx + 2;
    }

    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Parse a BT...ET text block for text-showing operators.
  void _extractTextFromBlock(String block, StringBuffer buffer) {
    var i = 0;
    final len = block.length;

    while (i < len) {
      // Skip whitespace
      while (i < len && _isSpace(block.codeUnitAt(i))) i++;
      if (i >= len) break;

      // Literal string (...)
      if (block[i] == '(') {
        final str = _parseLiteralString(block, i);
        buffer.write(str.text);
        i = str.endIdx;
        continue;
      }

      // Hex string <...> (not dictionary "<<")
      if (block[i] == '<' && (i + 1 >= len || block[i + 1] != '<')) {
        final str = _parseHexString(block, i);
        buffer.write(str.text);
        i = str.endIdx;
        continue;
      }

      // TJ array [...]
      if (block[i] == '[') {
        final arrayEnd = _findMatchingBracket(block, i);
        if (arrayEnd >= 0) {
          _extractTextFromArray(block.substring(i + 1, arrayEnd), buffer);
          i = arrayEnd + 1;
          continue;
        }
      }

      // Line-break operators: Td, TD, T*
      if (i + 1 < len &&
          block[i] == 'T' &&
          (block[i + 1] == 'd' || block[i + 1] == 'D' || block[i + 1] == '*')) {
        buffer.write(' ');
        i += 2;
        continue;
      }

      // ' operator (next line + show string)
      if (block[i] == "'" && i > 0 && _isSpace(block.codeUnitAt(i - 1))) {
        buffer.write(' ');
        i++;
        continue;
      }

      i++;
    }
  }

  /// Extract text from a TJ array [...].
  void _extractTextFromArray(String array, StringBuffer buffer) {
    var i = 0;
    final len = array.length;

    while (i < len) {
      while (i < len && _isSpace(array.codeUnitAt(i))) i++;
      if (i >= len) break;

      if (array[i] == '(') {
        final str = _parseLiteralString(array, i);
        buffer.write(str.text);
        i = str.endIdx;
      } else if (array[i] == '<') {
        final str = _parseHexString(array, i);
        buffer.write(str.text);
        i = str.endIdx;
      } else {
        // Skip number (kerning value)
        final numStart = i;
        while (i < len &&
            !_isSpace(array.codeUnitAt(i)) &&
            array[i] != '(' &&
            array[i] != '<') {
          i++;
        }
        // Large negative kerning = word space
        final numStr = array.substring(numStart, i);
        final num = double.tryParse(numStr);
        if (num != null && num < -120) {
          buffer.write(' ');
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // String parsers
  // ---------------------------------------------------------------------------

  /// Parse a literal PDF string starting at index [start].
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
        final escaped = text[i];
        switch (escaped) {
          case 'n':
            buf.write(' ');
            break;
          case 'r':
            buf.write(' ');
            break;
          case 't':
            buf.write('\t');
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
            // Octal escape \NNN
            if (escaped.codeUnitAt(0) >= 0x30 &&
                escaped.codeUnitAt(0) <= 0x37) {
              var octal = escaped;
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
              final charCode = int.tryParse(octal, radix: 8) ?? 0;
              if (charCode > 0) buf.writeCharCode(charCode);
            } else {
              buf.write(escaped);
            }
        }
      } else if (c == '(') {
        depth++;
        buf.write(c);
      } else if (c == ')') {
        depth--;
        if (depth > 0) buf.write(c);
      } else {
        if (c.codeUnitAt(0) >= 32 || c == '\t') {
          buf.write(c);
        } else {
          buf.write(' ');
        }
      }
      i++;
    }

    return _ParsedString(buf.toString(), i);
  }

  /// Parse a hex PDF string starting at index [start].
  _ParsedString _parseHexString(String text, int start) {
    final buf = StringBuffer();
    var i = start + 1; // skip '<'
    final len = text.length;
    final hexBuf = StringBuffer();

    while (i < len && text[i] != '>') {
      final c = text[i];
      if (!_isSpace(c.codeUnitAt(0))) hexBuf.write(c);
      i++;
    }
    if (i < len) i++; // skip '>'

    // Decode hex pairs
    final hex = hexBuf.toString();

    // Check if this looks like 4-digit (UTF-16) hex encoding
    if (hex.length >= 4 && hex.length % 4 == 0) {
      // Try decoding as UTF-16 BE
      for (var h = 0; h + 3 < hex.length; h += 4) {
        final code = int.tryParse(hex.substring(h, h + 4), radix: 16);
        if (code != null && code >= 32) {
          buf.writeCharCode(code);
        }
      }
    } else {
      // 2-digit hex encoding
      for (var h = 0; h + 1 < hex.length; h += 2) {
        final code = int.tryParse(hex.substring(h, h + 2), radix: 16);
        if (code != null && code >= 32) {
          buf.writeCharCode(code);
        }
      }
    }

    return _ParsedString(buf.toString(), i);
  }

  // ---------------------------------------------------------------------------
  // Utilities
  // ---------------------------------------------------------------------------

  /// Find the matching ']' for a '[' at [start], handling nested strings.
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
        // Skip literal string
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

class _ParsedString {
  final String text;
  final int endIdx;
  _ParsedString(this.text, this.endIdx);
}
