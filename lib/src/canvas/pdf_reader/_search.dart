part of 'pdf_reader_screen.dart';

/// Search logic, OCR, and search bar widget.
extension _PdfSearchMethods on _PdfReaderScreenState {

  // ---------------------------------------------------------------------------
  // Search Logic
  // ---------------------------------------------------------------------------

  /// Register the PDF document bytes with the search controller.
  /// Also eagerly starts text extraction so search is ready when user types.
  void _ensureSearchDocRegistered() {
    if (_searchDocRegistered) return;
    final filePath = widget.documentModel.filePath;
    if (filePath == null || filePath.isEmpty) return;

    File(filePath).readAsBytes().then((bytes) {
      if (!mounted) return;
      _searchController.registerDocument(
        widget.documentId,
        bytes,
        provider: widget.provider,
      );
      _searchDocRegistered = true;
    });
    // Eagerly extract text geometry so it's ready when user types
    _ensureTextRects(0).then((_) {
      if (!mounted) return;
      // Check if PDF has pages with no text (scanned PDF)
      final hasText = _providerPageTexts?.any((p) => p.text.trim().isNotEmpty) ?? false;
      final hasEmptyPages = _providerPageTexts?.any((p) => p.text.trim().isEmpty) ?? false;

      if (hasEmptyPages && _showSearchBar) {
        // Start background OCR for scanned pages
        _startBackgroundOcr();
      }

      // If user already typed something while we were extracting, search now
      final q = _searchTextCtrl.text.trim();
      if (q.isNotEmpty && _searchMatches.isEmpty) {
        _searchInPages(q);
      }
    });
  }

  /// Run a search query (debounced 300ms).
  void _runSearch(String query) {
    _searchDebounce?.cancel();
    if (query.trim().isEmpty) {
      _searchController.clearSearch();
      _searchMatches = const [];
      _searchCurrentIdx = -1;
      _textOverlayRepaint.value++;
      setState(() {});
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      // If text rects already extracted, search immediately
      if (_providerPageTexts != null) {
        _searchInPages(query);
      }
      // Otherwise, _ensureSearchDocRegistered's eager extraction
      // will pick up the query when it completes.
    });
  }

  /// Execute search across extracted page texts.
  void _searchInPages(String query) {
    final lowerQuery = query.trim().toLowerCase();
    if (lowerQuery.isEmpty) return;

    debugPrint('🔍 _searchInPages("$lowerQuery"), _providerPageTexts=${_providerPageTexts?.length}');
    if (_providerPageTexts == null) return;

    // Clear previous search state
    _searchController.clearSearch();

    final matches = <_SimpleSearchMatch>[];
    for (int pi = 0; pi < _providerPageTexts!.length; pi++) {
      final pageText = _providerPageTexts![pi].text.toLowerCase();
      int searchFrom = 0;
      while (true) {
        final idx = pageText.indexOf(lowerQuery, searchFrom);
        if (idx < 0) break;
        matches.add(_SimpleSearchMatch(
          pageIndex: pi,
          startOffset: idx,
          endOffset: idx + query.trim().length,
          snippet: _providerPageTexts![pi].text.substring(
            (idx - 20).clamp(0, _providerPageTexts![pi].text.length),
            (idx + query.trim().length + 20).clamp(0, _providerPageTexts![pi].text.length),
          ),
        ));
        searchFrom = idx + 1;
      }
    }

    debugPrint('🔍 Found ${matches.length} matches for "$lowerQuery"');
    setState(() {
      _searchMatches = matches;
      _searchCurrentIdx = matches.isNotEmpty ? 0 : -1;
    });
    _textOverlayRepaint.value++;

    // Auto-scroll to first match
    if (matches.isNotEmpty) {
      _scrollToPage(matches.first.pageIndex);
    }
  }

  void _searchNext() {
    if (_searchMatches.isEmpty) return;
    setState(() {
      _searchCurrentIdx = (_searchCurrentIdx + 1) % _searchMatches.length;
    });
    _scrollToPage(_searchMatches[_searchCurrentIdx].pageIndex);
    _textOverlayRepaint.value++;
  }

  void _searchPrev() {
    if (_searchMatches.isEmpty) return;
    setState(() {
      _searchCurrentIdx = (_searchCurrentIdx - 1 + _searchMatches.length) % _searchMatches.length;
    });
    _scrollToPage(_searchMatches[_searchCurrentIdx].pageIndex);
    _textOverlayRepaint.value++;
  }

  /// Get search highlight rects for a specific page (normalized 0-1 coords).
  List<Rect> _searchHighlightsForPage(int pageIndex) {
    final rects = <Rect>[];
    final pageRects = _pageTextRects[pageIndex];
    if (pageRects == null || pageRects.isEmpty) return rects;

    for (final match in _searchMatches) {
      if (match.pageIndex != pageIndex) continue;
      // Find text rects that overlap this match's character range
      for (final tr in pageRects) {
        final trEnd = tr.charOffset + tr.text.length;
        if (trEnd <= match.startOffset) continue;
        if (tr.charOffset >= match.endOffset) break;
        rects.add(tr.rect);
      }
    }
    return rects;
  }

  /// Get the current search match highlight rect for a page.
  Rect? _currentSearchHighlightForPage(int pageIndex) {
    if (_searchCurrentIdx < 0 || _searchCurrentIdx >= _searchMatches.length) {
      return null;
    }
    final match = _searchMatches[_searchCurrentIdx];
    if (match.pageIndex != pageIndex) return null;

    final pageRects = _pageTextRects[pageIndex];
    if (pageRects == null) return null;

    Rect? union;
    for (final tr in pageRects) {
      final trEnd = tr.charOffset + tr.text.length;
      if (trEnd <= match.startOffset) continue;
      if (tr.charOffset >= match.endOffset) break;
      union = union == null ? tr.rect : union.expandToInclude(tr.rect);
    }
    return union;
  }

  // ---------------------------------------------------------------------------
  // OCR
  // ---------------------------------------------------------------------------

  /// Start background OCR for pages with no text (scanned pages).
  void _startBackgroundOcr() {
    if (_ocrRunning || _providerPageTexts == null) return;

    final emptyPages = <int>[];
    for (int i = 0; i < _providerPageTexts!.length; i++) {
      if (_providerPageTexts![i].text.trim().isEmpty) {
        emptyPages.add(i);
      }
    }

    if (emptyPages.isEmpty) return;

    _ocrCancelled = false;
    _ocrRunning = true;
    _ocrTotal = emptyPages.length;
    _ocrProgress = 0;
    setState(() {});

    _runOcrBatch(emptyPages);
  }

  /// Process OCR pages one at a time in background.
  Future<void> _runOcrBatch(List<int> pages) async {
    final provider = widget.provider;

    for (int i = 0; i < pages.length; i++) {
      if (!mounted || _ocrCancelled) break;

      final pageIdx = pages[i];
      try {
        final ocrResult = await provider.ocrPage(pageIdx);
        if (ocrResult != null && ocrResult.text.isNotEmpty) {
          // Update page text data
          _providerPageTexts![pageIdx] = _PageTextData(
            text: ocrResult.text,
            rects: ocrResult.toTextRects(),
          );
          _pageTextRects[pageIdx] = ocrResult.toTextRects();
        }
      } catch (_) {}

      if (!mounted || _ocrCancelled) break;

      setState(() {
        _ocrProgress = i + 1;
      });

      // Re-run search with current query if user has typed something
      final q = _searchTextCtrl.text.trim();
      if (q.isNotEmpty) {
        _searchInPages(q);
      }
    }

    if (mounted) {
      setState(() {
        _ocrRunning = false;
      });
    }
  }

  /// Cancel background OCR.
  void _cancelOcr() {
    _ocrCancelled = true;
    _ocrRunning = false;
  }

  // ---------------------------------------------------------------------------
  // Search Bar Widget
  // ---------------------------------------------------------------------------

  Widget _buildSearchBar() {
    return Positioned(
      top: 8,
      left: 12,
      right: 12,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 200),
        offset: _showSearchBar ? Offset.zero : const Offset(0, -2),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: _showSearchBar ? 1.0 : 0.0,
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xDD1A1A36),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0x30FFFFFF),
                width: 0.5,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x60000000),
                  blurRadius: 16,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                const SizedBox(width: 14),
                const Icon(Icons.search_rounded,
                    color: Color(0x99FFFFFF), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _searchTextCtrl,
                    autofocus: true,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Search in PDF...',
                      hintStyle: TextStyle(
                        color: Color(0x66FFFFFF),
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                    onChanged: _runSearch,
                    onSubmitted: (_) => _searchNext(),
                  ),
                ),
                // Match count badge
                if (_searchMatches.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0x30FFFFFF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_searchCurrentIdx + 1}/${_searchMatches.length}',
                      style: const TextStyle(
                        color: Color(0xCCFFFFFF),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                // OCR progress indicator
                if (_ocrRunning)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    margin: const EdgeInsets.only(left: 6),
                    decoration: BoxDecoration(
                      color: const Color(0x30FF9800),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 10, height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            valueColor: AlwaysStoppedAnimation(Color(0xCCFF9800)),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '$_ocrProgress/$_ocrTotal',
                          style: const TextStyle(
                            color: Color(0xCCFF9800),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                // Prev/Next buttons
                if (_searchMatches.isNotEmpty) ...[
                  _searchNavButton(Icons.keyboard_arrow_up_rounded, _searchPrev),
                  _searchNavButton(Icons.keyboard_arrow_down_rounded, _searchNext),
                ],
                // Close button
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: Color(0x99FFFFFF), size: 18),
                  onPressed: () {
                    _cancelOcr();
                    setState(() {
                      _showSearchBar = false;
                      _searchController.clearSearch();
                      _searchTextCtrl.clear();
                      _searchMatches = const [];
                      _searchCurrentIdx = -1;
                    });
                    _textOverlayRepaint.value++;
                  },
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchNavButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, color: const Color(0xBBFFFFFF), size: 20),
      ),
    );
  }
}
