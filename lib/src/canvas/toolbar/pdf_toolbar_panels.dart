part of 'pdf_contextual_toolbar.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 📄 PDF Toolbar — Search, Annotate & Layout Panels
// ═══════════════════════════════════════════════════════════════════════════

// =============================================================================
// 🔍 SEARCH PANEL — Floating anchored dialog
// =============================================================================

class _PdfSearchPanel extends StatefulWidget {
  final Rect anchor;
  final List<PdfDocumentNode> docs;
  final PdfSearchController searchController;
  final int? selectedPageIndex;
  final VoidCallback? onLayoutChanged;
  final void Function(String documentId, int pageIndex)? onGoToPage;

  const _PdfSearchPanel({
    required this.anchor,
    required this.docs,
    required this.searchController,
    this.selectedPageIndex,
    this.onLayoutChanged,
    this.onGoToPage,
  });

  @override
  State<_PdfSearchPanel> createState() => _PdfSearchPanelState();
}

class _PdfSearchPanelState extends State<_PdfSearchPanel> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce; // (O) Debounced auto-search

  @override
  void initState() {
    super.initState();
    _textController.text = widget.searchController.query;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// (N) Navigate to next match and scroll to it.
  void _goToNext() {
    final sc = widget.searchController;
    sc.nextMatch();
    widget.onLayoutChanged?.call();
    if (sc.currentMatch != null) {
      widget.onGoToPage?.call(
        sc.currentMatch!.documentId,
        sc.currentMatch!.pageIndex,
      );
    }
    // Issue 20: Keep focus on search field after clicking Next
    _focusNode.requestFocus();
  }

  /// (N) Navigate to previous match and scroll to it.
  void _goToPrevious() {
    final sc = widget.searchController;
    sc.previousMatch();
    widget.onLayoutChanged?.call();
    if (sc.currentMatch != null) {
      widget.onGoToPage?.call(
        sc.currentMatch!.documentId,
        sc.currentMatch!.pageIndex,
      );
    }
    // Issue 20: Keep focus on search field after clicking Prev
    _focusNode.requestFocus();
  }

  /// (O) Trigger debounced search.
  void _onQueryChanged(String query) {
    setState(() {});
    _debounce?.cancel();
    if (query.isEmpty) {
      widget.searchController.clearSearch();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () {
      widget.searchController.searchDocuments(
        widget.docs,
        query,
        startPageIndex: widget.selectedPageIndex,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sc = widget.searchController;

    return Stack(
      children: [
        // Dismiss tap area
        GestureDetector(onTap: () => Navigator.pop(context)),
        Positioned(
          left: (widget.anchor.left - 40).clamp(
            8,
            MediaQuery.of(context).size.width - 308,
          ),
          top: widget.anchor.bottom + 8,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(16),
            color: isDark ? cs.surfaceContainerHigh : cs.surfaceContainerLow,
            child: Container(
              width: 300,
              padding: const EdgeInsets.all(12),
              child: ListenableBuilder(
                listenable: sc,
                builder: (context, _) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Search field with keyboard shortcuts (N)
                      SizedBox(
                        height: 38,
                        child: KeyboardListener(
                          focusNode: FocusNode(), // passthrough
                          onKeyEvent: (event) {
                            if (event is KeyDownEvent &&
                                event.logicalKey == LogicalKeyboardKey.enter) {
                              if (sc.hasMatches) {
                                if (HardwareKeyboard.instance.isShiftPressed) {
                                  _goToPrevious(); // Shift+Enter → prev
                                } else {
                                  _goToNext(); // Enter → next
                                }
                              }
                            }
                          },
                          child: TextField(
                            controller: _textController,
                            focusNode: _focusNode,
                            style: TextStyle(fontSize: 13, color: cs.onSurface),
                            decoration: InputDecoration(
                              hintText:
                                  widget.docs.length >= 2
                                      ? 'Search in ${widget.docs.length} PDFs…'
                                      : 'Search in PDF…',
                              hintStyle: TextStyle(
                                fontSize: 13,
                                color: cs.onSurfaceVariant.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                size: 18,
                                color: cs.onSurfaceVariant,
                              ),
                              suffixIcon:
                                  _textController.text.isNotEmpty
                                      ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // Issue 18: Whole Word Search Toggle
                                          Tooltip(
                                            message: 'Match whole word',
                                            child: InkWell(
                                              onTap: () {
                                                sc.wholeWord = !sc.wholeWord;
                                                // Retrigger search with new mode
                                                _onQueryChanged(
                                                  _textController.text,
                                                );
                                                _focusNode.requestFocus();
                                              },
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color:
                                                      sc.wholeWord
                                                          ? cs.primaryContainer
                                                          : Colors.transparent,
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  '[W]',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                    color:
                                                        sc.wholeWord
                                                            ? cs.onPrimaryContainer
                                                            : cs.onSurfaceVariant,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            icon: Icon(
                                              Icons.clear_rounded,
                                              size: 16,
                                              color: cs.onSurfaceVariant,
                                            ),
                                            onPressed: () {
                                              _textController.clear();
                                              sc.clearSearch();
                                              setState(() {});
                                              _focusNode.requestFocus();
                                            },
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                        ],
                                      )
                                      : null,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor:
                                  isDark
                                      ? cs.surfaceContainerHighest
                                      : cs.surfaceContainerHigh,
                            ),
                            textInputAction: TextInputAction.search,
                            // Issue 19: Use native onSubmitted for virtual keyboards
                            onSubmitted: (query) {
                              if (query.isNotEmpty) {
                                sc.searchDocuments(
                                  widget.docs,
                                  query,
                                  startPageIndex: widget.selectedPageIndex,
                                );
                              }
                              _focusNode.requestFocus();
                            },
                            onChanged: _onQueryChanged, // (O) Debounced
                          ),
                        ),
                      ),

                      // (M) Progress indicator during search
                      if (sc.isSearching) ...[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value:
                                sc.searchProgress > 0
                                    ? sc.searchProgress
                                    : null,
                            minHeight: 3,
                            backgroundColor: cs.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation(
                              cs.primary.withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Searching page ${sc.pagesSearched}'
                          ' / ${sc.totalPagesToSearch}…',
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                          ),
                        ),
                      ],

                      // Results nav
                      if (sc.hasMatches) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton.filledTonal(
                              onPressed: _goToPrevious,
                              icon: const Icon(
                                Icons.keyboard_arrow_up_rounded,
                                size: 18,
                              ),
                              tooltip: 'Previous (Shift+Enter)',
                              visualDensity: VisualDensity.compact,
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: cs.tertiaryContainer.withValues(
                                  alpha: 0.7,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${sc.currentIndex + 1} / ${sc.matchCount}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onTertiaryContainer,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              onPressed: _goToNext,
                              icon: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 18,
                              ),
                              tooltip: 'Next (Enter)',
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),

                        // 📄 Per-document match breakdown (multi-doc)
                        if (widget.docs.length >= 2) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            alignment: WrapAlignment.center,
                            children:
                                widget.docs.asMap().entries.map((entry) {
                                  final idx = entry.key;
                                  final doc = entry.value;
                                  final docMatches = sc.matchCountForDocument(
                                    doc.id,
                                  );
                                  final isCurrent =
                                      sc.currentMatch?.documentId == doc.id;
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          isCurrent
                                              ? cs.primaryContainer.withValues(
                                                alpha: 0.7,
                                              )
                                              : cs.surfaceContainerHighest
                                                  .withValues(alpha: 0.6),
                                      borderRadius: BorderRadius.circular(6),
                                      border:
                                          isCurrent
                                              ? Border.all(
                                                color: cs.primary.withValues(
                                                  alpha: 0.4,
                                                ),
                                              )
                                              : null,
                                    ),
                                    child: Text(
                                      'PDF ${idx + 1}: $docMatches',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight:
                                            isCurrent
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                        color:
                                            isCurrent
                                                ? cs.primary
                                                : cs.onSurfaceVariant,
                                      ),
                                    ),
                                  );
                                }).toList(),
                          ),
                        ],
                      ],

                      // No results
                      if (!sc.hasMatches &&
                          !sc.isSearching &&
                          sc.query.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'No results found',
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// 🏷️ ANNOTATE PANEL — Floating anchored dialog
// =============================================================================

class _PdfAnnotatePanel extends StatefulWidget {
  final Rect anchor;
  final PdfAnnotationController annotationController;
  final int selectedPageIndex;
  final CommandHistory? history;
  final VoidCallback? onLayoutChanged;

  const _PdfAnnotatePanel({
    required this.anchor,
    required this.annotationController,
    required this.selectedPageIndex,
    this.history,
    this.onLayoutChanged,
  });

  @override
  State<_PdfAnnotatePanel> createState() => _PdfAnnotatePanelState();
}

class _PdfAnnotatePanelState extends State<_PdfAnnotatePanel> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ac = widget.annotationController;

    return Stack(
      children: [
        GestureDetector(onTap: () => Navigator.pop(context)),
        Positioned(
          left: (widget.anchor.left - 60).clamp(
            8,
            MediaQuery.of(context).size.width - 288,
          ),
          top: widget.anchor.bottom + 8,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(16),
            color: isDark ? cs.surfaceContainerHigh : cs.surfaceContainerLow,
            child: Container(
              width: 280,
              padding: const EdgeInsets.all(12),
              child: ListenableBuilder(
                listenable: ac,
                builder: (context, _) {
                  final pageAnnotations = ac.annotationsForPage(
                    widget.selectedPageIndex,
                  );

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          Icon(
                            Icons.edit_note_rounded,
                            size: 18,
                            color: cs.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Annotations',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                          ),
                          const Spacer(),
                          if (pageAnnotations.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: cs.primaryContainer.withValues(
                                  alpha: 0.5,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${pageAnnotations.length}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onPrimaryContainer,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Type picker
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children:
                            PdfAnnotationType.values.map((type) {
                              final isActive = ac.activeType == type;
                              return GestureDetector(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  ac.activeType = type;
                                  ac.activeColor = type.defaultColor;
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        isActive
                                            ? cs.primaryContainer.withValues(
                                              alpha: 0.7,
                                            )
                                            : (isDark
                                                ? cs.surfaceContainerHighest
                                                : cs.surfaceContainerHigh),
                                    borderRadius: BorderRadius.circular(10),
                                    border:
                                        isActive
                                            ? Border.all(
                                              color: cs.primary.withValues(
                                                alpha: 0.4,
                                              ),
                                            )
                                            : null,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _annotationIcon(type),
                                        size: 18,
                                        color:
                                            isActive
                                                ? cs.primary
                                                : cs.onSurfaceVariant,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        type.name,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight:
                                              isActive
                                                  ? FontWeight.w600
                                                  : FontWeight.w400,
                                          color:
                                              isActive
                                                  ? cs.primary
                                                  : cs.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                      ),
                      const SizedBox(height: 10),

                      // Color + clear
                      Row(
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: ac.activeColor,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: cs.outlineVariant.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Page ${widget.selectedPageIndex + 1}',
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const Spacer(),
                          if (pageAnnotations.isNotEmpty)
                            TextButton.icon(
                              onPressed: () {
                                HapticFeedback.heavyImpact();
                                ac.clearPage(widget.selectedPageIndex);
                                widget.onLayoutChanged?.call();
                              },
                              icon: const Icon(
                                Icons.clear_all_rounded,
                                size: 14,
                              ),
                              label: const Text(
                                'Clear',
                                style: TextStyle(fontSize: 11),
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: cs.error,
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                              ),
                            ),
                        ],
                      ),

                      // Undo/redo
                      if (widget.history != null) ...[
                        const SizedBox(height: 8),
                        ValueListenableBuilder<int>(
                          valueListenable: widget.history!.revision,
                          builder: (context, _, __) {
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton.filledTonal(
                                  onPressed:
                                      widget.history!.canUndo
                                          ? () {
                                            widget.history!.undo();
                                            widget.onLayoutChanged?.call();
                                          }
                                          : null,
                                  icon: const Icon(
                                    Icons.undo_rounded,
                                    size: 16,
                                  ),
                                  tooltip: widget.history!.undoLabel ?? 'Undo',
                                  visualDensity: VisualDensity.compact,
                                ),
                                const SizedBox(width: 8),
                                IconButton.filledTonal(
                                  onPressed:
                                      widget.history!.canRedo
                                          ? () {
                                            widget.history!.redo();
                                            widget.onLayoutChanged?.call();
                                          }
                                          : null,
                                  icon: const Icon(
                                    Icons.redo_rounded,
                                    size: 16,
                                  ),
                                  tooltip: widget.history!.redoLabel ?? 'Redo',
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  IconData _annotationIcon(PdfAnnotationType type) {
    switch (type) {
      case PdfAnnotationType.highlight:
        return Icons.highlight_rounded;
      case PdfAnnotationType.underline:
        return Icons.format_underlined_rounded;
      case PdfAnnotationType.stickyNote:
        return Icons.sticky_note_2_rounded;
      case PdfAnnotationType.stamp:
        return Icons.approval_rounded;
    }
  }
}

// =============================================================================
// ⚙️ LAYOUT PANEL — Floating anchored dialog
// =============================================================================

class _PdfLayoutPanel extends StatefulWidget {
  final Rect anchor;
  final PdfDocumentNode doc;
  final VoidCallback? onLayoutChanged;

  const _PdfLayoutPanel({
    required this.anchor,
    required this.doc,
    this.onLayoutChanged,
  });

  @override
  State<_PdfLayoutPanel> createState() => _PdfLayoutPanelState();
}

class _PdfLayoutPanelState extends State<_PdfLayoutPanel> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final doc = widget.doc;
    final cols = doc.documentModel.gridColumns;
    final spacing = doc.documentModel.gridSpacing;

    // Detect active preset
    PdfLayoutPreset? activePreset;
    final allUnlocked = doc.pageNodes.every((p) => !p.pageModel.isLocked);
    if (allUnlocked) {
      activePreset = PdfLayoutPreset.freeform;
    } else if (cols == 1 && spacing <= 15) {
      activePreset = PdfLayoutPreset.reading;
    } else if (cols == 1 && spacing > 50) {
      activePreset = PdfLayoutPreset.single;
    } else if (cols == 2) {
      activePreset = PdfLayoutPreset.standard;
    } else if (cols >= 3) {
      activePreset = PdfLayoutPreset.overview;
    }

    return Stack(
      children: [
        GestureDetector(onTap: () => Navigator.pop(context)),
        Positioned(
          left: (widget.anchor.left - 80).clamp(
            8,
            MediaQuery.of(context).size.width - 308,
          ),
          top: widget.anchor.bottom + 8,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(16),
            color: isDark ? cs.surfaceContainerHigh : cs.surfaceContainerLow,
            child: Container(
              width: 300,
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Row(
                    children: [
                      Icon(
                        Icons.grid_view_rounded,
                        size: 18,
                        color: cs.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Layout',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${cols}col',
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Presets
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children:
                        PdfLayoutPreset.values.map((preset) {
                          final isActive = preset == activePreset;
                          return GestureDetector(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              doc.applyLayoutPreset(preset);
                              widget.onLayoutChanged?.call();
                              setState(() {});
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    isActive
                                        ? cs.primaryContainer
                                        : (isDark
                                            ? cs.surfaceContainerHighest
                                            : cs.surfaceContainerHigh),
                                borderRadius: BorderRadius.circular(10),
                                border:
                                    isActive
                                        ? Border.all(
                                          color: cs.primary.withValues(
                                            alpha: 0.4,
                                          ),
                                        )
                                        : null,
                              ),
                              child: Text(
                                '${preset.icon} ${preset.label}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight:
                                      isActive
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                  color:
                                      isActive
                                          ? cs.onPrimaryContainer
                                          : cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                  ),
                  const SizedBox(height: 10),

                  // Grid columns
                  Row(
                    children: [
                      ...List.generate(4, (i) {
                        final c = i + 1;
                        return Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Material(
                            color:
                                cols == c
                                    ? cs.primary
                                    : (isDark
                                        ? cs.surfaceContainerHighest
                                        : cs.surfaceContainerHigh),
                            borderRadius: BorderRadius.circular(8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                HapticFeedback.selectionClick();
                                doc.setGridColumns(c);
                                widget.onLayoutChanged?.call();
                                setState(() {});
                              },
                              child: SizedBox(
                                width: 32,
                                height: 32,
                                child: Center(
                                  child: Text(
                                    '$c',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color:
                                          cols == c
                                              ? cs.onPrimary
                                              : cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                      const SizedBox(width: 8),
                      // Spacing
                      Expanded(
                        child: Row(
                          children: [
                            Icon(
                              Icons.space_bar_rounded,
                              size: 14,
                              color: cs.onSurfaceVariant,
                            ),
                            Expanded(
                              child: SliderTheme(
                                data: SliderThemeData(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 5,
                                  ),
                                  overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 12,
                                  ),
                                  activeTrackColor: cs.primary,
                                  inactiveTrackColor:
                                      cs.surfaceContainerHighest,
                                  thumbColor: cs.primary,
                                ),
                                child: Slider(
                                  value: spacing,
                                  min: 0,
                                  max: 100,
                                  onChanged: (v) {
                                    doc.setGridSpacing(v);
                                    widget.onLayoutChanged?.call();
                                    setState(() {});
                                  },
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 24,
                              child: Text(
                                '${spacing.toInt()}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: cs.onSurfaceVariant,
                                ),
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
