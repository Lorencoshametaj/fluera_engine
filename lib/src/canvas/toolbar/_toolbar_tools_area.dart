part of 'professional_canvas_toolbar.dart';

// ============================================================================
// 🛠️ TOOLS AREA — Multi-toolbar system with per-tab sub-builders
// Extracted from professional_canvas_toolbar.dart
// ============================================================================

extension _ToolsAreaBuilder on _ProfessionalCanvasToolbarState {
  // --------------------------------------------------------------------------
  // 🗂️ Dispatcher — routes to the active toolbar tab's builder
  // --------------------------------------------------------------------------

  Widget _buildActiveToolbar(BuildContext context, bool isDark) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.05, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: KeyedSubtree(
        key: ValueKey(_activeToolbarTab),
        child: switch (_activeToolbarTab) {
          ToolbarTab.main => _buildMainTools(context, isDark),
          ToolbarTab.pdf => _buildPdfTools(context, isDark),
          ToolbarTab.scientific => _buildScientificTools(context, isDark),
          ToolbarTab.excel => _buildExcelTools(context, isDark),
          ToolbarTab.media => _buildMediaTools(context, isDark),
          ToolbarTab.design => _buildDesignTools(context, isDark),
        },
      ),
    );
  }

  // --------------------------------------------------------------------------
  // 🖊️ MAIN TOOLBAR — Brush presets, pan, stylus, eraser, lasso, ruler,
  //                     colors, width, opacity, shapes
  // --------------------------------------------------------------------------

  Widget _buildMainTools(BuildContext context, bool isDark) {
    final l10n = FlueraLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Primary row: drawing tools
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              // 🖊️ PEN TYPE / BRUSH PRESETS
              _buildPenTypeSection(isDark, l10n),

              // ── Moved from Scientific tab (hidden in V1) ──

              // ✒️ Vector Pen Tool
              if (widget.onPenToolToggle != null &&
                  !widget.isImageEditingMode) ...[
                const SizedBox(width: 12),
                ToolbarPenToolButton(
                  isActive: widget.isPenToolActive,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    widget.onPenToolToggle?.call();
                  },
                  isDark: isDark,
                ),
              ],

              // 🔷 Shape Recognition
              if (widget.onShapeRecognitionToggle != null) ...[
                const SizedBox(width: 12),
                Tooltip(
                  message: 'Shape Recognition',
                  waitDuration: const Duration(milliseconds: 500),
                  child: ToolbarShapeRecognitionButton(
                    isActive: widget.shapeRecognitionEnabled,
                    sensitivityIndex: widget.shapeRecognitionSensitivityIndex,
                    ghostEnabled: widget.ghostSuggestionEnabled,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      widget.onShapeRecognitionToggle!();
                    },
                    onLongPress:
                        widget.onShapeRecognitionSensitivityCycle != null
                            ? () {
                              HapticFeedback.mediumImpact();
                              widget.onShapeRecognitionSensitivityCycle!();
                            }
                            : null,
                    onDoubleTap:
                        widget.onGhostSuggestionToggle != null
                            ? () {
                              HapticFeedback.lightImpact();
                              widget.onGhostSuggestionToggle!();
                            }
                            : null,
                    isDark: isDark,
                  ),
                ),
              ],

              // 📏 Ruler
              if (!widget.isImageEditingMode) ...[
                const SizedBox(width: 12),
                ToolbarRulerButton(
                  isActive: widget.isRulerActive,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    widget.onRulerToggle?.call();
                  },
                  isDark: isDark,
                ),
              ],

              // 📝 Digital Text
              if (!widget.isImageEditingMode) ...[
                const SizedBox(width: 12),
                ToolbarDigitalTextButton(
                  isActive: widget.isDigitalTextActive,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    widget.onDigitalTextToggle();
                  },
                  isDark: isDark,
                ),
              ],

              // 🗺️ Minimap
              if (!widget.isImageEditingMode) ...[
                const SizedBox(width: 8),
                ToolbarMinimapButton(
                  isActive: widget.isMinimapVisible,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    widget.onMinimapToggle?.call();
                  },
                  isDark: isDark,
                ),
              ],

              // 📐 Section
              if (widget.onSectionToggle != null &&
                  !widget.isImageEditingMode) ...[
                const SizedBox(width: 8),
                ToolbarSectionButton(
                  isActive: widget.isSectionActive,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    widget.onSectionToggle?.call();
                  },
                  isDark: isDark,
                ),
              ],

              // 🔍 Handwriting Search (ML Kit)
              if (widget.onSearchPressed != null &&
                  !widget.isImageEditingMode) ...[
                const SizedBox(width: 8),
                ToolbarSearchButton(
                  isActive: widget.isSearchActive,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    widget.onSearchPressed!();
                  },
                  isDark: isDark,
                ),
              ],

              const SizedBox(width: 12),

              // 🎨 COLOR PALETTE
              _buildColorSection(isDark, l10n),

              const SizedBox(width: 12),

              // 📏 WIDTH
              _buildWidthSection(isDark, l10n),

              const SizedBox(width: 12),

              // 🔲 OPACITY
              _buildOpacitySection(isDark, l10n),

              const SizedBox(width: 12),

              // 🔷 GEOMETRIC SHAPES TOGGLE
              _buildShapesToggleButton(isDark, l10n),
            ],
          ),
        ),

        // Secondary row: shapes (animated, only if expanded)
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child:
              _isShapesExpanded
                  ? AnimatedOpacity(
                    opacity: _isShapesExpanded ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.withValues(alpha: 0.03),
                        border: Border(
                          top: BorderSide(
                            color: Colors.deepPurple.withValues(alpha: 0.1),
                            width: 1,
                          ),
                        ),
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: _buildShapeSection(isDark),
                      ),
                    ),
                  )
                  : const SizedBox.shrink(),
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // 📄 PDF TOOLBAR — Document switcher, pages, search, annotate, layout
  // --------------------------------------------------------------------------

  Widget _buildPdfTools(BuildContext context, bool isDark) {
    final l10n = FlueraLocalizations.of(context);

    // 📄 Empty state — beautiful CTA when no PDF is loaded
    if (widget.pdfDocuments.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
        child:
            widget.onPdfImportPressed != null
                ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        widget.onPdfImportPressed!();
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: (isDark ? Colors.white : Colors.black)
                                .withValues(alpha: 0.12),
                            width: 1.5,
                          ),
                          color: (isDark ? Colors.white : Colors.black)
                              .withValues(alpha: 0.03),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.picture_as_pdf_rounded,
                              size: 26,
                              color:
                                  isDark
                                      ? const Color(0xFFEF9A9A)
                                      : const Color(0xFFC62828),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  l10n.pdf_importDocument,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        isDark ? Colors.white : Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Tap to select a PDF file',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color:
                                        isDark
                                            ? Colors.white38
                                            : Colors.black38,
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            Icon(
                              Icons.add_circle_outline_rounded,
                              size: 22,
                              color: isDark ? Colors.white30 : Colors.black26,
                            ),
                          ],
                        ),
                      ),
                    ),
                    // 📄 Create blank PDF document button
                    if (widget.onPdfCreateBlankPressed != null) ...[
                      const SizedBox(height: 10),
                      InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          widget.onPdfCreateBlankPressed!();
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: (isDark ? Colors.white : Colors.black)
                                  .withValues(alpha: 0.12),
                              width: 1.5,
                            ),
                            color: (isDark ? Colors.white : Colors.black)
                                .withValues(alpha: 0.03),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.note_add_rounded,
                                size: 26,
                                color:
                                    isDark
                                        ? const Color(0xFF90CAF9)
                                        : const Color(0xFF1565C0),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Create Blank Document',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color:
                                          isDark
                                              ? Colors.white
                                              : Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Empty A4 pages to annotate',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color:
                                          isDark
                                              ? Colors.white38
                                              : Colors.black38,
                                    ),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              Icon(
                                Icons.add_circle_outline_rounded,
                                size: 22,
                                color: isDark ? Colors.white30 : Colors.black26,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                )
                : Center(
                  child: Text(
                    'PDF import not available',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white38 : Colors.black38,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
      );
    }

    // 📄 Normal PDF toolbar — documents are loaded
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          // ──────── DOC SWITCHER (standalone, only 2+ PDFs) ────────
          if (widget.pdfDocuments.length > 1) ...[
            _PdfDocumentSwitcher(
              documents: widget.pdfDocuments,
              activeDocumentId: widget.pdfDocument?.id,
              isDark: isDark,
              onDocumentSelected: (docId) {
                widget.onPdfDocumentChanged?.call(docId);
              },
            ),
            const SizedBox(width: 10),
          ],

          if (widget.pdfDocuments.isNotEmpty && widget.pdfDocument != null) ...[
            // ──────── NAVIGATE group ────────
            _PdfGroup(
              label: 'Navigate',
              isDark: isDark,
              children: [
                _PdfToolbarButton(
                  icon: Icons.file_copy_rounded,
                  tooltip: 'Pages',
                  badge: '${widget.pdfDocument!.documentModel.totalPages}',
                  isDark: isDark,
                  onTap: (anchor) {
                    showPdfPagePopup(
                      context: context,
                      anchor: anchor,
                      doc: widget.pdfDocument!,
                      selectedPageIndex: widget.pdfSelectedPageIndex,
                      onPageChanged: (_) {},
                      onInsertBlankPage: widget.onPdfInsertBlankPage,
                      onDuplicatePage: widget.onPdfDuplicatePage,
                      onDeletePage: widget.onPdfDeletePage,
                      onReorderPage: widget.onPdfReorderPage,
                      onLayoutChanged: widget.onPdfLayoutChanged,
                      onWatermarkToggle: widget.onPdfWatermarkToggle,
                      onAddStamp: widget.onPdfAddStamp,
                      onChangeBackground: widget.onPdfChangeBackground,
                      onDeleteDocument: widget.onPdfDeleteDocument,
                    );
                  },
                ),
                if (widget.pdfSearchController != null)
                  _PdfToolbarButton(
                    icon: Icons.search_rounded,
                    tooltip: 'Search PDF',
                    badge:
                        widget.pdfSearchController!.hasMatches
                            ? '${widget.pdfSearchController!.matchCount}'
                            : null,
                    isDark: isDark,
                    onTap: (anchor) {
                      showPdfSearchPopup(
                        context: context,
                        anchor: anchor,
                        docs: widget.pdfDocuments,
                        searchController: widget.pdfSearchController!,
                        onGoToPage: widget.onPdfGoToPage,
                      );
                    },
                  ),
                _PdfToolbarButton(
                  icon: Icons.grid_view_rounded,
                  tooltip: 'Layout',
                  isDark: isDark,
                  onTap: (anchor) {
                    showPdfLayoutPopup(
                      context: context,
                      anchor: anchor,
                      doc: widget.pdfDocument!,
                      onLayoutChanged: widget.onPdfLayoutChanged,
                    );
                  },
                ),
              ],
            ),

            // ──────── VIEW group (1-tap toggles) ────────
            _PdfGroup(
              label: 'View',
              isDark: isDark,
              children: [
                if (widget.onPdfNightModeToggle != null)
                  _PdfToggleButton(
                    icon: Icons.dark_mode_rounded,
                    activeIcon: Icons.dark_mode,
                    tooltip: 'Night Mode',
                    isActive: widget.pdfDocument!.documentModel.nightMode,
                    isDark: isDark,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      widget.onPdfNightModeToggle!();
                    },
                  ),
                if (widget.onPdfBookmarkToggle != null) ...[
                  Builder(
                    builder: (_) {
                      final page = widget.pdfDocument!.pageAt(
                        widget.pdfSelectedPageIndex,
                      );
                      final isBookmarked =
                          page?.pageModel.isBookmarked ?? false;
                      return _PdfToggleButton(
                        icon: Icons.bookmark_border_rounded,
                        activeIcon: Icons.bookmark_rounded,
                        tooltip:
                            isBookmarked ? 'Remove Bookmark' : 'Bookmark Page',
                        isActive: isBookmarked,
                        isDark: isDark,
                        activeColor: const Color(0xFFFFB74D),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          widget.onPdfBookmarkToggle!(
                            widget.pdfSelectedPageIndex,
                          );
                        },
                      );
                    },
                  ),
                ],
                if (widget.onPdfZoomToFit != null)
                  _PdfToolbarButton(
                    icon: Icons.fit_screen_rounded,
                    tooltip: 'Zoom to Fit',
                    isDark: isDark,
                    onTap: (_) {
                      HapticFeedback.selectionClick();
                      widget.onPdfZoomToFit!(widget.pdfSelectedPageIndex);
                    },
                  ),
              ],
            ),

            // ──────── ANNOTATE group ────────
            if (widget.pdfAnnotationController != null)
              _PdfGroup(
                label: 'Annotate',
                isDark: isDark,
                children: [
                  _PdfToolbarButton(
                    icon: Icons.edit_note_rounded,
                    tooltip: 'Annotate',
                    badge:
                        widget
                                .pdfAnnotationController!
                                .allAnnotations
                                .isNotEmpty
                            ? '${widget.pdfAnnotationController!.allAnnotations.length}'
                            : null,
                    isDark: isDark,
                    onTap: (anchor) {
                      showPdfAnnotatePopup(
                        context: context,
                        anchor: anchor,
                        annotationController: widget.pdfAnnotationController!,
                        selectedPageIndex: widget.pdfSelectedPageIndex,
                        history: widget.pdfCommandHistory,
                      );
                    },
                  ),
                ],
              ),

            // ──────── OUTPUT group ────────
            _PdfGroup(
              label: 'Output',
              isDark: isDark,
              children: [
                if (widget.onPdfExport != null)
                  _PdfToolbarButton(
                    icon: Icons.ios_share_rounded,
                    tooltip: 'Export',
                    isDark: isDark,
                    onTap: (_) {
                      widget.onPdfExport!();
                    },
                  ),
                if (widget.onPdfPrint != null)
                  _PdfToolbarButton(
                    icon: Icons.print_rounded,
                    tooltip: 'Print',
                    isDark: isDark,
                    onTap: (_) {
                      widget.onPdfPrint!();
                    },
                  ),
                if (widget.onPdfPresentation != null)
                  _PdfToolbarButton(
                    icon: Icons.slideshow_rounded,
                    tooltip: 'Present',
                    isDark: isDark,
                    onTap: (_) {
                      widget.onPdfPresentation!();
                    },
                  ),
              ],
            ),
          ],

          // ──────── ADD group (end — one-time actions) ────────
          _PdfGroup(
            label: 'Add',
            isDark: isDark,
            children: [
              if (widget.onPdfImportPressed != null)
                _PdfToolbarButton(
                  icon: Icons.add_rounded,
                  tooltip: l10n.pdf_importDocument,
                  secondaryIcon: Icons.picture_as_pdf_rounded,
                  isDark: isDark,
                  onTap: (_) {
                    HapticFeedback.selectionClick();
                    widget.onPdfImportPressed!();
                  },
                ),
              if (widget.onPdfCreateBlankPressed != null)
                _PdfToolbarButton(
                  icon: Icons.note_add_rounded,
                  tooltip: 'New blank document',
                  isDark: isDark,
                  accentColor:
                      isDark
                          ? const Color(0xFF90CAF9)
                          : const Color(0xFF1565C0),
                  onTap: (_) {
                    HapticFeedback.selectionClick();
                    widget.onPdfCreateBlankPressed!();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // 🔬 SCIENTIFIC TOOLBAR — LaTeX, Pen Tool, Shape Recognition
  // --------------------------------------------------------------------------

  Widget _buildScientificTools(BuildContext context, bool isDark) {
    final l10n = FlueraLocalizations.of(context);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          // 🧮 LaTeX Editor
          if (widget.onLatexToggle != null) ...[
            ToolbarLatexButton(
              isActive: widget.isLatexActive,
              onTap: () {
                HapticFeedback.selectionClick();
                widget.onLatexToggle!();
              },
              isDark: isDark,
            ),
            const SizedBox(width: 12),
          ],

          // ✒️ Vector Pen Tool
          if (widget.onPenToolToggle != null && !widget.isImageEditingMode) ...[
            ToolbarPenToolButton(
              isActive: widget.isPenToolActive,
              onTap: () {
                HapticFeedback.selectionClick();
                widget.onPenToolToggle?.call();
              },
              isDark: isDark,
            ),
            const SizedBox(width: 12),
          ],

          // 🔷 Shape Recognition
          if (widget.onShapeRecognitionToggle != null) ...[
            Tooltip(
              message: 'Shape Recognition',
              waitDuration: const Duration(milliseconds: 500),
              child: ToolbarShapeRecognitionButton(
                isActive: widget.shapeRecognitionEnabled,
                sensitivityIndex: widget.shapeRecognitionSensitivityIndex,
                ghostEnabled: widget.ghostSuggestionEnabled,
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onShapeRecognitionToggle!();
                },
                onLongPress:
                    widget.onShapeRecognitionSensitivityCycle != null
                        ? () {
                          HapticFeedback.mediumImpact();
                          widget.onShapeRecognitionSensitivityCycle!();
                        }
                        : null,
                onDoubleTap:
                    widget.onGhostSuggestionToggle != null
                        ? () {
                          HapticFeedback.lightImpact();
                          widget.onGhostSuggestionToggle!();
                        }
                        : null,
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 12),
          ],

          // 📏 Ruler toggle (also useful for scientific work)
          if (!widget.isImageEditingMode) ...[
            ToolbarRulerButton(
              isActive: widget.isRulerActive,
              onTap: () {
                HapticFeedback.selectionClick();
                widget.onRulerToggle?.call();
              },
              isDark: isDark,
            ),
          ],
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // 🎬 MEDIA TOOLBAR — Digital Text, Image Picker, Recording
  // --------------------------------------------------------------------------

  Widget _buildMediaTools(BuildContext context, bool isDark) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          if (!widget.isImageEditingMode) ...[
            // ✏️ Digital Text
            ToolbarDigitalTextButton(
              isActive: widget.isDigitalTextActive,
              onTap: () {
                HapticFeedback.selectionClick();
                widget.onDigitalTextToggle();
              },
              isDark: isDark,
            ),
            const SizedBox(width: 12),

            // 🖼️ Image Picker
            ToolbarImagePickerButton(
              isActive: widget.isImagePickerActive,
              onTap: () {
                HapticFeedback.selectionClick();
                widget.onImagePickerPressed();
              },
              isDark: isDark,
            ),
            const SizedBox(width: 12),

            // 🎤 Recording
            // 🚀 P99 FIX: Wrap in ValueListenableBuilder so the recording
            // button updates independently without rebuilding the canvas.
            if (!widget.hideRecordingControlWhenActive ||
                !widget.isRecordingActive)
              Builder(
                builder: (_) {
                  final durNotifier = widget.recordingDurationNotifier;
                  final ampNotifier = widget.recordingAmplitudeNotifier;

                  // If notifiers are provided, use them for live updates
                  if (durNotifier != null && ampNotifier != null) {
                    return ValueListenableBuilder<Duration>(
                      valueListenable: durNotifier,
                      builder: (_, duration, __) {
                        return ValueListenableBuilder<double>(
                          valueListenable: ampNotifier,
                          builder: (_, amplitude, __) {
                            return ToolbarRecordingButton(
                              isActive: widget.isRecordingActive,
                              duration: duration,
                              amplitudeLevel: amplitude,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                widget.onRecordingPressed();
                              },
                              isDark: isDark,
                            );
                          },
                        );
                      },
                    );
                  }

                  // Fallback: use plain fields
                  return ToolbarRecordingButton(
                    isActive: widget.isRecordingActive,
                    duration: widget.recordingDuration,
                    amplitudeLevel: widget.recordingAmplitude,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      widget.onRecordingPressed();
                    },
                    isDark: isDark,
                  );
                },
              ),
            const SizedBox(width: 12),

            // 🎧 View Recordings
            ToolbarViewRecordingsButton(
              onTap: () {
                HapticFeedback.selectionClick();
                widget.onViewRecordingsPressed();
              },
              isDark: isDark,
            ),
          ],
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // 📊 EXCEL TOOLBAR — Create spreadsheet tables with presets
  // --------------------------------------------------------------------------

  Widget _buildExcelTools(BuildContext context, bool isDark) {
    final cs = Theme.of(context).colorScheme;
    final cellRef = widget.selectedCellRef;
    final hasCellSel = cellRef != null && cellRef.isNotEmpty;
    final fmt = widget.selectedCellFormat;
    final isBold = fmt?.bold ?? false;
    final isItalic = fmt?.italic ?? false;
    final hAlign = fmt?.horizontalAlign;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── ROW 1: Grouped toolbar — swipeable cards ───────────────────
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
          child: Row(
            children: [
              // ────── Table group ──────
              _ExcelGroup(
                label: 'Table',
                isDark: isDark,
                children: [
                  _ExcelBtn(
                    icon: Icons.add_rounded,
                    tooltip: 'New Table',
                    isDark: isDark,
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      _showCreateTableDialog(context);
                    },
                  ),
                  if (widget.hasTabularSelection)
                    _ExcelBtn(
                      icon: Icons.delete_outline_rounded,
                      tooltip: 'Delete Table',
                      isDark: isDark,
                      isDestructive: true,
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        widget.onTabularDelete?.call();
                      },
                    ),
                ],
              ),

              // ────── Style group ──────
              if (hasCellSel) ...[
                _ExcelGroup(
                  label: 'Style',
                  isDark: isDark,
                  children: [
                    _ExcelBtn(
                      icon: Icons.format_bold_rounded,
                      tooltip: 'Bold',
                      isDark: isDark,
                      isActive: isBold,
                      onPressed: () => widget.onToggleBold?.call(),
                    ),
                    _ExcelBtn(
                      icon: Icons.format_italic_rounded,
                      tooltip: 'Italic',
                      isDark: isDark,
                      isActive: isItalic,
                      onPressed: () => widget.onToggleItalic?.call(),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Borders',
                      onSelected: (v) => widget.onBorderPreset?.call(v),
                      icon: Icon(
                        Icons.border_all_rounded,
                        size: 16,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 28,
                      ),
                      itemBuilder:
                          (_) => const [
                            PopupMenuItem(
                              value: 'all',
                              child: Row(
                                children: [
                                  Icon(Icons.border_all, size: 18),
                                  SizedBox(width: 8),
                                  Text('All Borders'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'outline',
                              child: Row(
                                children: [
                                  Icon(Icons.border_outer, size: 18),
                                  SizedBox(width: 8),
                                  Text('Outside'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'inside',
                              child: Row(
                                children: [
                                  Icon(Icons.border_inner, size: 18),
                                  SizedBox(width: 8),
                                  Text('Inside'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'bottom',
                              child: Row(
                                children: [
                                  Icon(Icons.border_bottom, size: 18),
                                  SizedBox(width: 8),
                                  Text('Bottom'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'none',
                              child: Row(
                                children: [
                                  Icon(Icons.border_clear, size: 18),
                                  SizedBox(width: 8),
                                  Text('No Borders'),
                                ],
                              ),
                            ),
                          ],
                    ),
                    _ExcelBtn(
                      icon: Icons.format_clear_rounded,
                      tooltip: 'Clear',
                      isDark: isDark,
                      onPressed: () => widget.onClearFormatting?.call(),
                    ),
                  ],
                ),

                // ────── Align group ──────
                _ExcelGroup(
                  label: 'Align',
                  isDark: isDark,
                  children: [
                    _ExcelBtn(
                      icon: Icons.format_align_left_rounded,
                      tooltip: 'Left',
                      isDark: isDark,
                      isActive: hAlign == CellAlignment.left,
                      onPressed:
                          () => widget.onSetAlignment?.call(CellAlignment.left),
                    ),
                    _ExcelBtn(
                      icon: Icons.format_align_center_rounded,
                      tooltip: 'Center',
                      isDark: isDark,
                      isActive: hAlign == CellAlignment.center,
                      onPressed:
                          () =>
                              widget.onSetAlignment?.call(CellAlignment.center),
                    ),
                    _ExcelBtn(
                      icon: Icons.format_align_right_rounded,
                      tooltip: 'Right',
                      isDark: isDark,
                      isActive: hAlign == CellAlignment.right,
                      onPressed:
                          () =>
                              widget.onSetAlignment?.call(CellAlignment.right),
                    ),
                  ],
                ),

                // ────── Color group ──────
                _ExcelGroup(
                  label: 'Color',
                  isDark: isDark,
                  children: [
                    _ColorPickerBtn(
                      icon: Icons.format_color_text_rounded,
                      tooltip: 'Text Color',
                      currentColor: fmt?.textColor ?? cs.onSurface,
                      onColorSelected: (c) => widget.onSetTextColor?.call(c),
                    ),
                    _ColorPickerBtn(
                      icon: Icons.format_color_fill_rounded,
                      tooltip: 'Fill Color',
                      currentColor: fmt?.backgroundColor,
                      onColorSelected:
                          (c) => widget.onSetBackgroundColor?.call(c),
                    ),
                  ],
                ),
              ],

              // ────── Rows/Cols group ──────
              if (widget.hasTabularSelection)
                _ExcelGroup(
                  label: 'Rows & Cols',
                  isDark: isDark,
                  children: [
                    _ExcelBtn(
                      icon: Icons.table_rows_outlined,
                      tooltip: 'Insert Row',
                      isDark: isDark,
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        widget.onInsertRow?.call();
                      },
                    ),
                    _ExcelBtn(
                      icon: Icons.remove_circle_outline_rounded,
                      tooltip: 'Delete Row',
                      isDark: isDark,
                      isDestructive: true,
                      onPressed:
                          hasCellSel
                              ? () {
                                HapticFeedback.selectionClick();
                                widget.onDeleteRow?.call();
                              }
                              : null,
                    ),
                    _ExcelBtn(
                      icon: Icons.view_column_outlined,
                      tooltip: 'Insert Col',
                      isDark: isDark,
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        widget.onInsertColumn?.call();
                      },
                    ),
                    _ExcelBtn(
                      icon: Icons.remove_circle_outline_rounded,
                      tooltip: 'Delete Col',
                      isDark: isDark,
                      isDestructive: true,
                      onPressed:
                          hasCellSel
                              ? () {
                                HapticFeedback.selectionClick();
                                widget.onDeleteColumn?.call();
                              }
                              : null,
                    ),
                  ],
                ),

              // ────── Actions overflow ──────
              if (widget.hasTabularSelection)
                _ExcelGroup(
                  label: 'More',
                  isDark: isDark,
                  children: [
                    SizedBox(
                      width: 40,
                      height: 38,
                      child: PopupMenuButton<String>(
                        icon: Icon(
                          Icons.more_horiz_rounded,
                          size: 22,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                        tooltip: 'More Actions',
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        onSelected: (action) {
                          HapticFeedback.selectionClick();
                          switch (action) {
                            case 'copy':
                              widget.onCopySelection?.call();
                            case 'cut':
                              widget.onCutSelection?.call();
                            case 'paste':
                              widget.onPasteSelection?.call();
                            case 'sort_asc':
                              widget.onSortColumn?.call(true);
                            case 'sort_desc':
                              widget.onSortColumn?.call(false);
                            case 'autofill':
                              widget.onAutoFill?.call();
                            case 'generate_latex':
                              widget.onGenerateLatex?.call();
                            case 'copy_latex':
                              widget.onCopySelectionAsLatex?.call();
                            case 'merge_cells':
                              widget.onMergeCells?.call();
                            case 'unmerge_cells':
                              widget.onUnmergeCells?.call();
                            case 'generate_chart':
                              widget.onGenerateChart?.call();
                            case 'import_latex':
                              widget.onImportLatex?.call();
                            case 'export_tex':
                              widget.onExportTex?.call();
                            case 'clear_cells':
                              widget.onClearCells?.call();
                            case 'export_csv':
                              widget.onExportCsv?.call();
                            case 'freeze_row':
                              widget.onToggleFreezeRow?.call();
                          }
                        },
                        itemBuilder:
                            (ctx) => [
                              _menuItem(
                                'copy',
                                Icons.copy_rounded,
                                'Copy',
                                enabled: hasCellSel,
                              ),
                              _menuItem(
                                'cut',
                                Icons.content_cut_rounded,
                                'Cut',
                                enabled: hasCellSel,
                              ),
                              _menuItem(
                                'paste',
                                Icons.paste_rounded,
                                'Paste',
                                enabled: hasCellSel,
                              ),
                              const PopupMenuDivider(),
                              _menuItem(
                                'sort_asc',
                                Icons.arrow_upward_rounded,
                                'Sort A → Z',
                                enabled: hasCellSel,
                              ),
                              _menuItem(
                                'sort_desc',
                                Icons.arrow_downward_rounded,
                                'Sort Z → A',
                                enabled: hasCellSel,
                              ),
                              _menuItem(
                                'autofill',
                                Icons.flash_on_rounded,
                                'Auto-fill Down',
                                enabled: hasCellSel,
                              ),
                              const PopupMenuDivider(),
                              _menuItem(
                                'merge_cells',
                                Icons.call_merge_rounded,
                                'Merge Cells',
                                enabled: hasCellSel && widget.hasRangeSelection,
                              ),
                              _menuItem(
                                'unmerge_cells',
                                Icons.call_split_rounded,
                                'Unmerge Cells',
                                enabled: hasCellSel,
                              ),
                              const PopupMenuDivider(),
                              _menuItem(
                                'generate_latex',
                                Icons.functions_rounded,
                                'Generate LaTeX Table',
                                enabled: hasCellSel,
                              ),
                              _menuItem(
                                'copy_latex',
                                Icons.content_copy_rounded,
                                'Copy Selection as LaTeX',
                                enabled: hasCellSel,
                              ),
                              _menuItem(
                                'generate_chart',
                                Icons.bar_chart_rounded,
                                'Generate TikZ Chart',
                                enabled: hasCellSel,
                              ),
                              _menuItem(
                                'import_latex',
                                Icons.input_rounded,
                                'Import LaTeX → Table',
                              ),
                              _menuItem(
                                'export_tex',
                                Icons.description_outlined,
                                'Export .tex File',
                              ),
                              const PopupMenuDivider(),
                              _menuItem(
                                'clear_cells',
                                Icons.backspace_rounded,
                                'Clear Cells',
                                enabled: hasCellSel,
                                destructive: true,
                              ),
                              _menuItem(
                                'export_csv',
                                Icons.download_rounded,
                                'Export CSV',
                              ),
                              _menuItem(
                                'freeze_row',
                                widget.hasFrozenRow
                                    ? Icons.lock_open_rounded
                                    : Icons.lock_rounded,
                                widget.hasFrozenRow
                                    ? 'Unfreeze Header'
                                    : 'Freeze Header Row',
                              ),
                            ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),

        // ── ROW 2: Formula bar ────────────────────────────────────────
        if (hasCellSel)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: SizedBox(
              height: 36,
              child: Row(
                children: [
                  // Cell reference chip
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      cellRef,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: cs.onPrimaryContainer,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // fx button — formula reference
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      tooltip: 'Formula Reference',
                      onPressed: () {
                        FormulaReferenceSheet.show(
                          context,
                          onInsertFormula: (formula) {
                            widget.onCellValueSubmit?.call(formula);
                          },
                        );
                      },
                      icon: Text(
                        'fx',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          fontStyle: FontStyle.italic,
                          color: cs.primary,
                        ),
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: cs.primary.withValues(alpha: 0.08),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Formula TextField
                  Expanded(
                    child: _FormulaBarField(
                      cellRef: cellRef,
                      initialValue: widget.selectedCellValue ?? '',
                      onSubmit: (v) => widget.onCellValueSubmit?.call(v),
                      onTab: (v) => widget.onCellTabSubmit?.call(v),
                    ),
                  ),
                ],
              ),
            ),
          )
        else if (widget.hasTabularSelection)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
            child: Text(
              'Tap a cell to edit',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.45),
              ),
            ),
          ),
      ],
    );
  }

  /// Helper: create a popup menu item.
  PopupMenuItem<String> _menuItem(
    String value,
    IconData icon,
    String label, {
    bool enabled = true,
    bool destructive = false,
  }) {
    return PopupMenuItem(
      value: value,
      enabled: enabled,
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: destructive && enabled ? Colors.red : null,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style:
                destructive && enabled
                    ? const TextStyle(color: Colors.red)
                    : null,
          ),
        ],
      ),
    );
  }

  /// Show M3 dialog to configure and create a table.
  void _showCreateTableDialog(BuildContext context) {
    int cols = 8;
    int rows = 15;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setDialogState) {
            final cs = Theme.of(ctx2).colorScheme;
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              icon: Icon(
                Icons.table_chart_rounded,
                color: cs.primary,
                size: 28,
              ),
              title: const Text('New Spreadsheet'),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Columns
                    _CustomSizeRow(
                      label: 'Columns',
                      value: cols,
                      min: 2,
                      max: 50,
                      color: cs.primary,
                      onChanged: (v) => setDialogState(() => cols = v),
                    ),
                    const SizedBox(height: 16),
                    // Rows
                    _CustomSizeRow(
                      label: 'Rows',
                      value: rows,
                      min: 2,
                      max: 100,
                      color: cs.tertiary,
                      onChanged: (v) => setDialogState(() => rows = v),
                    ),
                    const SizedBox(height: 8),
                    // Preview chip
                    Chip(
                      avatar: Icon(
                        Icons.grid_on_rounded,
                        size: 16,
                        color: cs.primary,
                      ),
                      label: Text(
                        '$cols × $rows cells',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      side: BorderSide(color: cs.outlineVariant),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx2).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(ctx2).pop();
                    HapticFeedback.mediumImpact();
                    widget.onTabularCreate?.call(cols, rows);
                  },
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --------------------------------------------------------------------------
  // 🔽 SHARED SECTION BUILDERS (used by Main toolbar)
  // --------------------------------------------------------------------------

  /// The old _buildToolsArea is kept as a fallback / reference but no longer
  /// called from the build method — dispatching is handled by _buildActiveToolbar.

  Widget _buildPenTypeSection(bool isDark, FlueraLocalizations l10n) {
    return ToolbarToolSection(
      title: l10n.proCanvas_pen,
      icon: Icons.edit_rounded,
      isDark: isDark,
      child: Row(
        children: [
          // 🎨 Preset-based brush selector
          ToolbarBrushStrip(
            presets: widget.brushPresets,
            selectedPresetId: widget.selectedPresetId,
            isPenActive: !widget.isEraserActive && !widget.isLassoActive,
            onPresetSelected: (preset) {
              HapticFeedback.selectionClick();
              // Deactivate eraser and lasso when activating pen
              if (widget.isEraserActive) {
                widget.onEraserToggle();
              }
              if (widget.isLassoActive) {
                widget.onLassoToggle();
              }
              // Apply preset (pen type, width, color, settings)
              widget.onPresetSelected?.call(preset);
            },
            onLongPress: () {
              // 🏛️ Long-press → Open brush settings popup anchored to strip
              HapticFeedback.mediumImpact();
              if (widget.onBrushSettingsPressed != null) {
                final box = context.findRenderObject() as RenderBox;
                final pos = box.localToGlobal(Offset.zero);
                final rect = pos & box.size;
                widget.onBrushSettingsPressed!(rect);
              }
            },
            isDark: isDark,
          ),
          const SizedBox(width: 12),
          // 🖐️ Pan Mode Button
          ToolbarPanModeButton(
            isActive: widget.isPanModeActive,
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onPanModeToggle();
            },
            isDark: isDark,
          ),
          const SizedBox(width: 12),
          // 🖊️ Stylus Mode Button
          ToolbarStylusModeButton(
            isActive: widget.isStylusModeActive,
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onStylusModeToggle();
            },
            isDark: isDark,
          ),
          const SizedBox(width: 6),
          // 🖐️ Handedness & Palm Rejection Settings
          Tooltip(
            message: 'Handedness & Palm Rejection',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: Colors.transparent,
                    builder: (_) => HandednessSettingsSheet(
                      onChanged: () {
                        if (mounted) setState(() {});
                      },
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.04),
                  ),
                  child: Icon(
                    Icons.back_hand_rounded,
                    size: 18,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          ToolbarEraserButton(
            isActive: widget.isEraserActive,
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onEraserToggle();
            },
            isDark: isDark,
          ),
          // 🎚️ Eraser size slider (appears when eraser is active)
          if (widget.isEraserActive &&
              widget.onEraserRadiusChanged != null) ...[
            const SizedBox(width: 8),
            ToolbarEraserSizeSlider(
              radius: widget.eraserRadius,
              onChanged: widget.onEraserRadiusChanged!,
              isDark: isDark,
            ),
            // 🔀 Whole/Partial toggle
            if (widget.onEraseWholeStrokeChanged != null) ...[
              const SizedBox(width: 4),
              ToolbarEraseModeToggle(
                isWholeStroke: widget.eraseWholeStroke,
                onChanged: widget.onEraseWholeStrokeChanged!,
                isDark: isDark,
              ),
            ],
          ],
          const SizedBox(width: 12),
          // Lasso hidden in editing mode
          if (!widget.isImageEditingMode) ...[
            ToolbarLassoButton(
              isActive: widget.isLassoActive,
              onTap: () {
                HapticFeedback.selectionClick();
                widget.onLassoToggle();
              },
              isDark: isDark,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildShapeSection(bool isDark) {
    return ToolbarToolSection(
      title: FlueraLocalizations.of(context).proCanvas_shapes.toUpperCase(),
      icon: Icons.category_rounded,
      isDark: isDark,
      child: ToolbarShapeTypeSelector(
        selectedType: widget.selectedShapeType,
        onChanged: (type) {
          HapticFeedback.selectionClick();
          widget.onShapeTypeChanged(type);
        },
        isDark: isDark,
      ),
    );
  }

  Widget _buildColorSection(bool isDark, FlueraLocalizations l10n) {
    return ToolbarToolSection(
      title: l10n.proCanvas_color,
      icon: Icons.palette_rounded,
      isDark: isDark,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ToolbarColorPalette(
            colors: _customColors,
            selectedColor: widget.selectedColor,
            onChanged: (color) {
              HapticFeedback.selectionClick();
              widget.onColorChanged(color);
            },
            onLongPress: _showColorPicker,
            isDark: isDark,
          ),
          const SizedBox(width: 6),
          // 🎨 Eyedropper quick-access
          Tooltip(
            message: 'Eyedropper',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () async {
                  HapticFeedback.selectionClick();
                  final picked = await showEyedropperOverlay(context: context);
                  if (picked != null && mounted) {
                    _addToColorHistory(picked);
                    widget.onColorChanged(picked);
                  }
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.2)
                          : Colors.black.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Icon(
                    Icons.colorize_rounded,
                    size: 15,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWidthSection(bool isDark, FlueraLocalizations l10n) {
    return ToolbarToolSection(
      title: l10n.proCanvas_thickness,
      icon: Icons.line_weight,
      isDark: isDark,
      child: ToolbarWidthSlider(
        value: widget.selectedWidth,
        onChanged: widget.onWidthChanged,
        isDark: isDark,
      ),
    );
  }

  Widget _buildOpacitySection(bool isDark, FlueraLocalizations l10n) {
    return ToolbarToolSection(
      title: l10n.proCanvas_opacity,
      icon: Icons.opacity_rounded,
      isDark: isDark,
      child: ToolbarOpacitySlider(
        value: widget.selectedOpacity,
        onChanged: widget.onOpacityChanged,
        isDark: isDark,
      ),
    );
  }

  Widget _buildShapesToggleButton(bool isDark, FlueraLocalizations l10n) {
    return Tooltip(
      message: l10n.proCanvas_geometricShapes,
      waitDuration: const Duration(milliseconds: 500),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.mediumImpact();
            setState(() {
              _isShapesExpanded = !_isShapesExpanded;
              // 🔄 When closing the shapes section, automatically return to brush
              if (!_isShapesExpanded) {
                widget.onShapeTypeChanged(ShapeType.freehand);
              }
            });
          },
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              gradient:
                  _isShapesExpanded
                      ? LinearGradient(
                        colors: [
                          Colors.deepPurple.withValues(alpha: 0.2),
                          Colors.deepPurple.withValues(alpha: 0.1),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                      : null,
              color:
                  _isShapesExpanded
                      ? null
                      : (isDark ? Colors.white : Colors.black).withValues(
                        alpha: 0.05,
                      ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color:
                    _isShapesExpanded
                        ? Colors.deepPurple.withValues(alpha: 0.6)
                        : (isDark ? Colors.white : Colors.black).withValues(
                          alpha: 0.1,
                        ),
                width: _isShapesExpanded ? 2.5 : 1,
              ),
              boxShadow:
                  _isShapesExpanded
                      ? [
                        BoxShadow(
                          color: Colors.deepPurple.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                      : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedRotation(
                  turns: _isShapesExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: Icon(
                    Icons.category_rounded,
                    size: 22,
                    color:
                        _isShapesExpanded
                            ? Colors.deepPurple
                            : (isDark ? Colors.white70 : Colors.black54),
                  ),
                ),
                const SizedBox(width: 6),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  style: TextStyle(
                    color:
                        _isShapesExpanded
                            ? Colors.deepPurple
                            : (isDark ? Colors.white70 : Colors.black54),
                    fontWeight:
                        _isShapesExpanded ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 13,
                  ),
                  child: Text(FlueraLocalizations.of(context).proCanvas_shapes),
                ),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: _isShapesExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: Icon(
                    Icons.arrow_drop_down,
                    size: 20,
                    color:
                        _isShapesExpanded
                            ? Colors.deepPurple
                            : (isDark ? Colors.white70 : Colors.black54),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
