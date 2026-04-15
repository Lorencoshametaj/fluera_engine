part of 'pdf_reader_screen.dart';

/// Text extraction, selection, and copy logic.
extension _PdfTextSelectionMethods on _PdfReaderScreenState {

  // ---------------------------------------------------------------------------
  // Text Selection Logic
  // ---------------------------------------------------------------------------

  /// Clear current text selection.
  void _clearTextSelection() {
    _selSpans = const [];
    _selStartIdx = -1;
    _selEndIdx = -1;
    _selPageIdx = -1;
    _selAnchor = -1;
    _textOverlayRepaint.value++;
  }

  /// Extract text rects for a page (lazy, via native provider).
  /// Phase 1: fast getPageText() on all pages.
  /// Phase 2 (background OCR) is started separately by _startBackgroundOcr.
  Future<List<PdfTextRect>> _ensureTextRects(int pageIndex) async {
    if (_pageTextRects.containsKey(pageIndex)) {
      return _pageTextRects[pageIndex]!;
    }
    if (_isExtractingText) {
      return const [];
    }

    _isExtractingText = true;
    try {
      final provider = widget.provider;
      final totalPages = widget.documentModel.totalPages;

      // Phase 1: fast native text extraction (no OCR)
      final pageTexts = <_PageTextData>[];
      for (int i = 0; i < totalPages; i++) {
        final text = await provider.getPageText(i);

        List<PdfTextRect> rects = const [];
        if (text.trim().isNotEmpty) {
          try {
            rects = await provider.extractTextGeometry(i);
          } catch (_) {}
        }

        _pageTextRects[i] = rects;
        pageTexts.add(_PageTextData(text: text, rects: rects));
      }

      _providerPageTexts = pageTexts;
    } catch (e, st) {
      debugPrint('📝 ERROR in _ensureTextRects: $e\n$st');
      _pageTextRects[pageIndex] = const [];
    } finally {
      _isExtractingText = false;
    }
    return _pageTextRects[pageIndex] ?? const [];
  }

  /// Find the text rect index at a normalized position on the page.
  int _textRectIndexAt(int pageIndex, Offset normalizedPos) {
    final rects = _pageTextRects[pageIndex];
    if (rects == null || rects.isEmpty) return -1;

    // Direct hit test
    for (int i = 0; i < rects.length; i++) {
      if (rects[i].rect.contains(normalizedPos)) return i;
    }

    // Fallback: closest within tolerance
    const tolerance = 0.03; // 3% of page dimension
    double closest = double.infinity;
    int closestIdx = -1;
    for (int i = 0; i < rects.length; i++) {
      final center = rects[i].rect.center;
      final dist = (center - normalizedPos).distance;
      if (dist < closest && dist < tolerance) {
        closest = dist;
        closestIdx = i;
      }
    }
    return closestIdx;
  }

  /// Handle long-press start in text selection mode.
  ///
  /// Word-level snap: expands the initial selection to cover the entire word
  /// under the touch point (bounded by whitespace / punctuation).
  void _onTextSelectStart(int pageIndex, Offset localPos, Size pageDisplaySize) {
    final normX = localPos.dx / pageDisplaySize.width;
    final normY = localPos.dy / pageDisplaySize.height;
    final normPos = Offset(normX, normY);

    _ensureTextRects(pageIndex).then((rects) {
      if (!mounted || rects.isEmpty) return;
      final idx = _textRectIndexAt(pageIndex, normPos);
      if (idx < 0) {
        setState(_clearTextSelection);
        return;
      }

      // Word-level snap: expand selection to word boundaries
      int wordStart = idx;
      int wordEnd = idx;
      while (wordStart > 0 && _isSameWord(rects[wordStart - 1], rects[wordStart])) {
        wordStart--;
      }
      while (wordEnd < rects.length - 1 && _isSameWord(rects[wordEnd], rects[wordEnd + 1])) {
        wordEnd++;
      }

      setState(() {
        _selPageIdx = pageIndex;
        _selAnchor = idx;
        _selStartIdx = wordStart;
        _selEndIdx = wordEnd;
        _selSpans = rects.sublist(wordStart, wordEnd + 1);
      });
      _textOverlayRepaint.value++;
      HapticFeedback.selectionClick();
    });
  }

  /// Returns true if two adjacent rects belong to the same word
  /// (same line, no whitespace between them).
  bool _isSameWord(PdfTextRect a, PdfTextRect b) {
    // Different lines → not same word
    final lineH = a.rect.height;
    if ((b.rect.top - a.rect.top).abs() > lineH * 0.5) return false;
    // If either ends/starts with whitespace → word boundary
    if (a.text.endsWith(' ') || a.text.endsWith('\n')) return false;
    if (b.text.startsWith(' ') || b.text.startsWith('\n')) return false;
    return true;
  }

  /// Handle drag update in text selection mode.
  void _onTextSelectUpdate(int pageIndex, Offset localPos, Size pageDisplaySize) {
    if (_selPageIdx != pageIndex || _selAnchor < 0) return;
    final rects = _pageTextRects[pageIndex];
    if (rects == null || rects.isEmpty) return;

    final normX = localPos.dx / pageDisplaySize.width;
    final normY = localPos.dy / pageDisplaySize.height;
    final idx = _textRectIndexAt(pageIndex, Offset(normX, normY));
    if (idx < 0) return;

    final startIdx = idx < _selAnchor ? idx : _selAnchor;
    final endIdx = idx < _selAnchor ? _selAnchor : idx;

    if (startIdx != _selStartIdx || endIdx != _selEndIdx) {
      _selStartIdx = startIdx;
      _selEndIdx = endIdx;
      _selSpans = rects.sublist(startIdx, endIdx + 1);
      _textOverlayRepaint.value++;
      HapticFeedback.selectionClick();
    }
  }

  /// Handle release in text selection mode.
  void _onTextSelectEnd() {
    if (_selSpans.isNotEmpty) {
      HapticFeedback.lightImpact();
    }
  }

  /// Copy selected text to clipboard.
  void _copySelectedText() {
    if (_selSpans.isEmpty) return;
    final buf = StringBuffer();
    for (int i = 0; i < _selSpans.length; i++) {
      if (i > 0) {
        final prevBottom = _selSpans[i - 1].rect.bottom;
        final currTop = _selSpans[i].rect.top;
        final lineH = _selSpans[i - 1].rect.height;
        if ((currTop - prevBottom).abs() < lineH * 0.5) {
          // Same line → space
          buf.write(' ');
        } else {
          buf.write('\n');
        }
      }
      buf.write(_selSpans[i].text);
    }
    Clipboard.setData(ClipboardData(text: buf.toString()));
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Copied to clipboard'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: const Color(0xFF2A2A4A),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  /// Combined selected text string.
  String get _selectedText {
    if (_selSpans.isEmpty) return '';
    final buf = StringBuffer();
    for (int i = 0; i < _selSpans.length; i++) {
      if (i > 0) buf.write(' ');
      buf.write(_selSpans[i].text);
    }
    return buf.toString();
  }

  /// 🖍️ Create a permanent highlighter annotation over the selected text.
  ///
  /// Converts each selected PdfTextRect into a flat ProStroke rectangle
  /// using the highlighter pen type with semi-transparent color.
  void _highlightSelectedText() {
    if (_selSpans.isEmpty || _selPageIdx < 0) return;
    final pageIndex = _selPageIdx;
    final page = widget.documentModel.pages[pageIndex];
    final pageW = page.originalSize.width;
    final pageH = page.originalSize.height;
    final highlightColor = const Color(0x66FFEB3B); // semi-transparent yellow

    // Group spans by line (same vertical position) to create one stroke per line
    final lineGroups = <double, List<PdfTextRect>>{};
    for (final span in _selSpans) {
      // Quantize top to line groups (within 0.5% tolerance)
      final lineKey = (span.rect.top * 200).roundToDouble() / 200;
      lineGroups.putIfAbsent(lineKey, () => []).add(span);
    }

    final newStrokes = <ProStroke>[];
    for (final line in lineGroups.values) {
      // Compute bounding rect for this line group
      double left = double.infinity, right = 0, top = double.infinity, bottom = 0;
      for (final span in line) {
        if (span.rect.left < left) left = span.rect.left;
        if (span.rect.right > right) right = span.rect.right;
        if (span.rect.top < top) top = span.rect.top;
        if (span.rect.bottom > bottom) bottom = span.rect.bottom;
      }

      // Convert normalized 0-1 to page coordinates
      final x1 = left * pageW;
      final x2 = right * pageW;
      final midY = (top + bottom) / 2 * pageH;
      final strokeH = (bottom - top) * pageH;

      // Create a horizontal line stroke through the middle of the text
      final points = [
        ProDrawingPoint(position: Offset(x1, midY), pressure: 0.5),
        ProDrawingPoint(position: Offset(x2, midY), pressure: 0.5),
      ];

      newStrokes.add(ProStroke(
        id: 'pdf_hl_${widget.documentId}_p${pageIndex}_${DateTime.now().millisecondsSinceEpoch}_${newStrokes.length}',
        points: points,
        color: highlightColor,
        baseWidth: strokeH * 0.9,
        penType: ProPenType.highlighter,
        createdAt: DateTime.now(),
      ));
    }

    if (newStrokes.isNotEmpty) {
      setState(() {
        final existing = _pageStrokes[pageIndex] ?? const [];
        _pageStrokes[pageIndex] = [...existing, ...newStrokes];
      });
      _clearTextSelection();
      HapticFeedback.mediumImpact();
    }
  }

  /// 📤 Share selected text via the system share sheet.
  void _shareSelectedText() {
    final text = _selectedText;
    if (text.isEmpty) return;
    // Use Clipboard as a fallback since Share requires platform plugins
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Copied — ready to share'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: const Color(0xFF2A2A4A),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PDF Text Extraction Sheet
  // ---------------------------------------------------------------------------

  /// Opens the text extraction bottom sheet immediately, resolving text in background.
  void _showPdfTextExtractionSheet() {
    HapticFeedback.mediumImpact();

    final filePath = widget.documentModel.filePath;
    final pageIndex = _currentPageIndex;
    final totalPages = widget.documentModel.totalPages;

    final Future<String> textFuture = () async {
      if (filePath == null || filePath.isEmpty) return '';
      try {
        final bytes = await File(filePath).readAsBytes();
        final pages = await PdfTextExtractor.extractInIsolate(
          bytes,
          pageCount: totalPages,
        );
        if (pageIndex < pages.length) {
          return pages[pageIndex].text.trim();
        }
      } catch (_) {}
      return '';
    }();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PdfTextSheet(
        pageIndex: pageIndex,
        textFuture: textFuture,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Text Selection Context Toolbar
  // ---------------------------------------------------------------------------

  Widget _buildTextSelectionToolbar(Size pageDisplaySize) {
    if (_selSpans.isEmpty || _selPageIdx < 0) return const SizedBox.shrink();

    // Compute the top-center of the selection in page-display coordinates
    double minY = double.infinity;
    double sumX = 0;
    for (final span in _selSpans) {
      final top = span.rect.top * pageDisplaySize.height;
      if (top < minY) minY = top;
      sumX += span.rect.center.dx * pageDisplaySize.width;
    }
    final avgX = sumX / _selSpans.length;

    return Positioned(
      left: (avgX - 50).clamp(4.0, pageDisplaySize.width - 100),
      top: (minY - 44).clamp(0.0, pageDisplaySize.height - 36),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xEE1A1A36),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0x30FFFFFF), width: 0.5),
          boxShadow: const [
            BoxShadow(color: Color(0x60000000), blurRadius: 8),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ctxButton('Copy', Icons.copy_rounded, _copySelectedText),
            _ctxButton('Highlight', Icons.highlight_rounded, _highlightSelectedText),
            _ctxButton('Share', Icons.share_rounded, _shareSelectedText),
            _ctxButton('All', Icons.select_all_rounded, () {
              final rects = _pageTextRects[_selPageIdx];
              if (rects == null || rects.isEmpty) return;
              setState(() {
                _selStartIdx = 0;
                _selEndIdx = rects.length - 1;
                _selSpans = rects;
              });
              _textOverlayRepaint.value++;
            }),
          ],
        ),
      ),
    );
  }

  Widget _ctxButton(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: const Color(0xCCFFFFFF)),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(
              color: Color(0xCCFFFFFF), fontSize: 11,
              fontWeight: FontWeight.w600,
            )),
          ],
        ),
      ),
    );
  }
}
