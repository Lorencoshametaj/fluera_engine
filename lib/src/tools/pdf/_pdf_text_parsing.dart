part of 'pdf_text_extractor.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 📄 PDF Text Extraction — Text Block Parsing Methods
// ═══════════════════════════════════════════════════════════════════════════

extension _PdfTextParsing on PdfTextExtractor {
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
}
