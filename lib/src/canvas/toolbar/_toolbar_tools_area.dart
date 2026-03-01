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
      child: ToolbarColorPalette(
        colors: _customColors,
        selectedColor: widget.selectedColor,
        onChanged: (color) {
          HapticFeedback.selectionClick();
          widget.onColorChanged(color);
        },
        onLongPress: _showColorPicker,
        isDark: isDark,
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

/// 📄 PDF toggle button — shows active/inactive state with icon swap and glow.
class _PdfToggleButton extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String tooltip;
  final bool isActive;
  final bool isDark;
  final Color? activeColor;
  final VoidCallback onTap;

  const _PdfToggleButton({
    required this.icon,
    required this.activeIcon,
    required this.tooltip,
    required this.isActive,
    required this.isDark,
    this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color =
        isActive
            ? (activeColor ?? cs.primary)
            : (isDark ? Colors.white54 : Colors.black45);

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color:
                  isActive ? color.withValues(alpha: 0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color:
                    isActive
                        ? color.withValues(alpha: 0.3)
                        : Colors.transparent,
              ),
            ),
            child: Icon(isActive ? activeIcon : icon, size: 18, color: color),
          ),
        ),
      ),
    );
  }
}

/// 📄 PDF toolbar group — labelled card mirroring `_ExcelGroup`.
class _PdfGroup extends StatelessWidget {
  final String label;
  final bool isDark;
  final List<Widget> children;

  const _PdfGroup({
    required this.label,
    required this.isDark,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    // Intersperse spacing between children
    final spaced = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) spaced.add(const SizedBox(width: 4));
      spaced.add(children[i]);
    }

    return Container(
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
      decoration: BoxDecoration(
        color:
            isDark
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color:
              isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
          width: 0.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: spaced),
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 1),
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                color:
                    isDark
                        ? Colors.white.withValues(alpha: 0.30)
                        : Colors.black.withValues(alpha: 0.30),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact PDF toolbar button with optional badge.
/// Captures its render box and passes the [Rect] to [onTap].
class _PdfToolbarButton extends StatelessWidget {
  final IconData icon;
  final IconData? secondaryIcon;
  final String tooltip;
  final String? badge;
  final bool isDark;
  final Color? accentColor;
  final void Function(Rect anchor) onTap;

  const _PdfToolbarButton({
    required this.icon,
    this.secondaryIcon,
    required this.tooltip,
    this.badge,
    required this.isDark,
    this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = accentColor ?? cs.primary;

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            HapticFeedback.selectionClick();
            final box = context.findRenderObject() as RenderBox;
            final pos = box.localToGlobal(Offset.zero);
            onTap(pos & box.size);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.15)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: color),
                if (secondaryIcon != null) ...[
                  const SizedBox(width: 3),
                  Icon(secondaryIcon!, size: 18, color: color),
                ],
                if (badge != null) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badge!,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 📄 Compact PDF document switcher — dropdown chip to select the active PDF.
///
/// Shows the current PDF's label (name or "PDF N") and a dropdown arrow.
/// Tapping opens a popup menu listing all loaded PDFs so the user can switch.
class _PdfDocumentSwitcher extends StatelessWidget {
  final List<PdfDocumentNode> documents;
  final String? activeDocumentId;
  final bool isDark;
  final void Function(String documentId) onDocumentSelected;

  const _PdfDocumentSwitcher({
    required this.documents,
    required this.activeDocumentId,
    required this.isDark,
    required this.onDocumentSelected,
  });

  String _labelFor(PdfDocumentNode doc, int index) {
    final name = doc.name;
    if (name.isNotEmpty) return name;
    return 'PDF ${index + 1}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Find active index for display label
    final activeIdx = documents.indexWhere((d) => d.id == activeDocumentId);
    final activeLabel =
        activeIdx >= 0 ? _labelFor(documents[activeIdx], activeIdx) : 'PDF 1';

    return PopupMenuButton<String>(
      tooltip: 'Switch PDF',
      onSelected: onDocumentSelected,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
      itemBuilder: (context) {
        return [
          for (int i = 0; i < documents.length; i++)
            PopupMenuItem<String>(
              value: documents[i].id,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    documents[i].id == activeDocumentId
                        ? Icons.picture_as_pdf_rounded
                        : Icons.picture_as_pdf_outlined,
                    size: 16,
                    color:
                        documents[i].id == activeDocumentId
                            ? cs.primary
                            : (isDark ? Colors.white70 : Colors.black54),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _labelFor(documents[i], i),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            documents[i].id == activeDocumentId
                                ? FontWeight.w700
                                : FontWeight.w400,
                        color:
                            documents[i].id == activeDocumentId
                                ? cs.primary
                                : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${documents[i].documentModel.totalPages}p',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ],
              ),
            ),
        ];
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 160),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: cs.primaryContainer.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.picture_as_pdf_rounded, size: 14, color: cs.primary),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  activeLabel,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.primary,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.arrow_drop_down, size: 16, color: cs.primary),
            ],
          ),
        ),
      ),
    );
  }
}

/// 📄 PDF "More Actions" popup — exposes less-common functions.
class _PdfMoreActions extends StatelessWidget {
  final PdfDocumentNode doc;
  final int selectedPageIndex;
  final bool isDark;
  final bool showPageNumbers;
  final VoidCallback? onLayoutChanged;
  final VoidCallback? onTogglePageNumbers;
  final ValueChanged<int>? onPageIndexChanged;

  const _PdfMoreActions({
    required this.doc,
    required this.selectedPageIndex,
    required this.isDark,
    required this.showPageNumbers,
    this.onLayoutChanged,
    this.onTogglePageNumbers,
    this.onPageIndexChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final page = doc.pageAt(selectedPageIndex);
    final annotationsVisible = page?.pageModel.showAnnotations ?? true;
    final isUnlocked = page != null && !page.pageModel.isLocked;
    final totalPages = doc.documentModel.totalPages;

    return PopupMenuButton<String>(
      tooltip: 'More Actions',
      icon: Icon(
        Icons.more_vert_rounded,
        size: 20,
        color: isDark ? Colors.white70 : Colors.black54,
      ),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 8,
      onSelected: (action) {
        HapticFeedback.selectionClick();
        switch (action) {
          case 'toggle_annotations':
            doc.togglePageAnnotations(selectedPageIndex);
            onLayoutChanged?.call();
          case 'return_to_grid':
            doc.returnPageToGrid(selectedPageIndex);
            onLayoutChanged?.call();
          case 'move_up':
            if (selectedPageIndex > 0) {
              doc.reorderPage(selectedPageIndex, selectedPageIndex - 1);
              onPageIndexChanged?.call(selectedPageIndex - 1);
              onLayoutChanged?.call();
            }
          case 'move_down':
            if (selectedPageIndex < totalPages - 1) {
              doc.reorderPage(selectedPageIndex, selectedPageIndex + 1);
              onPageIndexChanged?.call(selectedPageIndex + 1);
              onLayoutChanged?.call();
            }
          case 'toggle_page_numbers':
            onTogglePageNumbers?.call();
        }
      },
      itemBuilder:
          (_) => [
            PopupMenuItem(
              value: 'toggle_annotations',
              child: Row(
                children: [
                  Icon(
                    annotationsVisible
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    size: 18,
                    color: cs.onSurface,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    annotationsVisible
                        ? 'Hide Annotations'
                        : 'Show Annotations',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
            if (isUnlocked)
              PopupMenuItem(
                value: 'return_to_grid',
                child: Row(
                  children: [
                    Icon(Icons.grid_on_rounded, size: 18, color: cs.onSurface),
                    const SizedBox(width: 10),
                    const Text(
                      'Return to Grid',
                      style: TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            const PopupMenuDivider(),
            PopupMenuItem(
              enabled: selectedPageIndex > 0,
              value: 'move_up',
              child: Row(
                children: [
                  Icon(
                    Icons.arrow_upward_rounded,
                    size: 18,
                    color:
                        selectedPageIndex > 0
                            ? cs.onSurface
                            : cs.onSurface.withValues(alpha: 0.3),
                  ),
                  const SizedBox(width: 10),
                  const Text('Move Page Up', style: TextStyle(fontSize: 13)),
                ],
              ),
            ),
            PopupMenuItem(
              enabled: selectedPageIndex < totalPages - 1,
              value: 'move_down',
              child: Row(
                children: [
                  Icon(
                    Icons.arrow_downward_rounded,
                    size: 18,
                    color:
                        selectedPageIndex < totalPages - 1
                            ? cs.onSurface
                            : cs.onSurface.withValues(alpha: 0.3),
                  ),
                  const SizedBox(width: 10),
                  const Text('Move Page Down', style: TextStyle(fontSize: 13)),
                ],
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'toggle_page_numbers',
              child: Row(
                children: [
                  Icon(
                    showPageNumbers ? Icons.numbers_rounded : Icons.tag_rounded,
                    size: 18,
                    color: cs.onSurface,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    showPageNumbers ? 'Hide Page Numbers' : 'Show Page Numbers',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
    );
  }
}

// =============================================================================
// 📊 EXCEL TAB — SUPPORTING WIDGETS
// =============================================================================

/// Row with label, slider, and value display for custom table sizing.
class _CustomSizeRow extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final Color color;
  final ValueChanged<int> onChanged;

  const _CustomSizeRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: color,
              thumbColor: color,
              inactiveTrackColor: color.withValues(alpha: 0.15),
              overlayColor: color.withValues(alpha: 0.1),
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: value.toDouble(),
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: max - min,
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
        ),
        Container(
          width: 36,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$value',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

/// 📊 Formula bar text field with Tab key support.
///
/// Tab → saves value and moves selection right.
/// Enter → saves value and moves selection down.
class _FormulaBarField extends StatefulWidget {
  final String cellRef;
  final String initialValue;
  final ValueChanged<String> onSubmit;
  final ValueChanged<String> onTab;

  const _FormulaBarField({
    required this.cellRef,
    required this.initialValue,
    required this.onSubmit,
    required this.onTab,
  });

  @override
  State<_FormulaBarField> createState() => _FormulaBarFieldState();
}

class _FormulaBarFieldState extends State<_FormulaBarField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode = FocusNode();
    // Auto-focus
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant _FormulaBarField old) {
    super.didUpdateWidget(old);
    if (old.cellRef != widget.cellRef) {
      _controller.text = widget.initialValue;
      _controller.selection = TextSelection.collapsed(
        offset: widget.initialValue.length,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return KeyboardListener(
      focusNode: FocusNode(), // Wrapper focus — forwards to TextField
      onKeyEvent: (event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.tab) {
          widget.onTab(_controller.text);
        }
      },
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Type value or =formula…',
          hintStyle: TextStyle(
            fontSize: 12,
            color: cs.onSurface.withValues(alpha: 0.35),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.3)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: cs.primary, width: 1.5),
          ),
          isDense: true,
          suffixIcon: IconButton(
            icon: Icon(Icons.check_rounded, size: 18, color: cs.primary),
            onPressed: () => widget.onSubmit(_controller.text),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ),
        onSubmitted: (value) => widget.onSubmit(value),
      ),
    );
  }
}

/// 📊 Compact toolbar icon button with active state.
class _ToolbarIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isActive;
  final Color? color;
  final VoidCallback? onPressed;

  const _ToolbarIconBtn({
    required this.icon,
    required this.tooltip,
    this.isActive = false,
    this.color,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        icon: Icon(icon, size: 18, color: color),
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          backgroundColor: isActive ? cs.primary.withValues(alpha: 0.15) : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}

/// 📊 Thin vertical divider for toolbar groups.
class _ToolbarDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Container(
        width: 1,
        height: 20,
        color: Theme.of(
          context,
        ).colorScheme.outlineVariant.withValues(alpha: 0.3),
      ),
    );
  }
}

/// 📊 Visual group card for Excel toolbar — wraps buttons with a label.
class _ExcelGroup extends StatelessWidget {
  final String label;
  final bool isDark;
  final List<Widget> children;

  const _ExcelGroup({
    required this.label,
    required this.isDark,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.fromLTRB(4, 3, 4, 1),
      decoration: BoxDecoration(
        color:
            isDark
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color:
              isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
          width: 0.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: children),
          Padding(
            padding: const EdgeInsets.only(top: 1, bottom: 1),
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                color:
                    isDark
                        ? Colors.white.withValues(alpha: 0.30)
                        : Colors.black.withValues(alpha: 0.30),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 📊 Excel toolbar button — 40×38 with 22px icon. Larger, easier to tap.
class _ExcelBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isDark;
  final bool isActive;
  final bool isDestructive;
  final VoidCallback? onPressed;

  const _ExcelBtn({
    required this.icon,
    required this.tooltip,
    required this.isDark,
    this.isActive = false,
    this.isDestructive = false,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = onPressed != null;

    Color iconColor;
    if (!enabled) {
      iconColor =
          isDark
              ? Colors.white.withValues(alpha: 0.20)
              : Colors.black.withValues(alpha: 0.20);
    } else if (isDestructive) {
      iconColor = cs.error;
    } else if (isActive) {
      iconColor = cs.primary;
    } else {
      iconColor = isDark ? Colors.white70 : Colors.black54;
    }

    return SizedBox(
      width: 40,
      height: 38,
      child: IconButton(
        icon: Icon(icon, size: 22, color: iconColor),
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          backgroundColor: isActive ? cs.primary.withValues(alpha: 0.12) : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}

/// 📊 Color picker button with popup grid of preset colors.
class _ColorPickerBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color? currentColor;
  final ValueChanged<Color> onColorSelected;

  const _ColorPickerBtn({
    required this.icon,
    required this.tooltip,
    this.currentColor,
    required this.onColorSelected,
  });

  static const _presetColors = [
    Colors.black,
    Colors.white,
    Colors.red,
    Colors.pink,
    Colors.orange,
    Colors.amber,
    Colors.yellow,
    Colors.green,
    Colors.teal,
    Colors.blue,
    Colors.indigo,
    Colors.purple,
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: PopupMenuButton<Color>(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onSelected: onColorSelected,
        itemBuilder:
            (ctx) => [
              PopupMenuItem(
                enabled: false,
                child: SizedBox(
                  width: 180,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children:
                        _presetColors.map((c) {
                          final selected =
                              currentColor?.toARGB32() == c.toARGB32();
                          return GestureDetector(
                            onTap: () {
                              onColorSelected(c);
                              Navigator.of(ctx).pop();
                            },
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: c,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color:
                                      selected
                                          ? Colors.blue
                                          : Colors.grey.withValues(alpha: 0.3),
                                  width: selected ? 2.5 : 1,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                  ),
                ),
              ),
            ],
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16),
            Container(
              width: 16,
              height: 3,
              decoration: BoxDecoration(
                color: currentColor ?? Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 🎨 DESIGN TOOLBAR — Design tools, prototyping, inspect, responsive
// ============================================================================

extension _DesignToolsBuilder on _ProfessionalCanvasToolbarState {
  Widget _buildDesignTools(BuildContext context, bool isDark) {
    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          // ─── Prototype ───
          _DesignChipGroup(
            label: 'Prototype',
            icon: Icons.play_circle_outline_rounded,
            isDark: isDark,
            children: [
              _DesignActionChip(
                icon: Icons.play_arrow_rounded,
                label: 'Play',
                isDark: isDark,
                onTap: widget.onPrototypePlay,
              ),
              _DesignActionChip(
                icon: Icons.link_rounded,
                label: 'Flow',
                isDark: isDark,
                onTap: widget.onFlowLinkAdd,
              ),
            ],
          ),
          const SizedBox(width: 8),

          // ─── Animate ───
          _DesignChipGroup(
            label: 'Animate',
            icon: Icons.animation_rounded,
            isDark: isDark,
            children: [
              _DesignActionChip(
                icon: Icons.timeline_rounded,
                label: 'Timeline',
                isDark: isDark,
                onTap: widget.onAnimationTimeline,
              ),
              _DesignActionChip(
                icon: Icons.auto_fix_high_rounded,
                label: 'Smart',
                isDark: isDark,
                onTap: widget.onSmartAnimate,
              ),
            ],
          ),
          const SizedBox(width: 8),

          // ─── Inspect ───
          _DesignChipGroup(
            label: 'Inspect',
            icon: Icons.straighten_rounded,
            isDark: isDark,
            children: [
              _DesignActionChip(
                icon: Icons.space_bar_rounded,
                label: 'Measure',
                isDark: isDark,
                isActive: widget.isInspectActive,
                onTap: widget.onInspectToggle,
              ),
              _DesignActionChip(
                icon: Icons.code_rounded,
                label: 'Code',
                isDark: isDark,
                onTap: widget.onCodeGen,
              ),
              _DesignActionChip(
                icon: Icons.grid_on_rounded,
                label: 'Redline',
                isDark: isDark,
                isActive: widget.isRedlineActive,
                onTap: widget.onRedlineToggle,
              ),
            ],
          ),
          const SizedBox(width: 8),

          // ─── Responsive ───
          _DesignChipGroup(
            label: 'Responsive',
            icon: Icons.devices_rounded,
            isDark: isDark,
            children: [
              _DesignActionChip(
                icon: Icons.phone_android_rounded,
                label: 'Mobile',
                isDark: isDark,
                onTap: () => widget.onBreakpointSelect?.call('mobile'),
              ),
              _DesignActionChip(
                icon: Icons.tablet_rounded,
                label: 'Tablet',
                isDark: isDark,
                onTap: () => widget.onBreakpointSelect?.call('tablet'),
              ),
              _DesignActionChip(
                icon: Icons.desktop_windows_rounded,
                label: 'Desktop',
                isDark: isDark,
                onTap: () => widget.onBreakpointSelect?.call('desktop'),
              ),
            ],
          ),
          const SizedBox(width: 8),

          // ─── Quality ───
          _DesignChipGroup(
            label: 'Quality',
            icon: Icons.verified_rounded,
            isDark: isDark,
            children: [
              _DesignActionChip(
                icon: Icons.grid_3x3_rounded,
                label: 'Snap',
                isDark: isDark,
                isActive: widget.isSmartSnapActive,
                onTap: widget.onSmartSnapToggle,
              ),
              _DesignActionChip(
                icon: Icons.checklist_rounded,
                label: 'Lint',
                isDark: isDark,
                onTap: widget.onDesignLint,
              ),
              _DesignActionChip(
                icon: Icons.palette_rounded,
                label: 'Styles',
                isDark: isDark,
                onTap: widget.onStyleSystem,
              ),
              _DesignActionChip(
                icon: Icons.accessibility_new_rounded,
                label: 'A11y',
                isDark: isDark,
                onTap: widget.onAccessibilityTree,
              ),
            ],
          ),
          const SizedBox(width: 8),

          // ─── Images ───
          _DesignChipGroup(
            label: 'Images',
            icon: Icons.tune_rounded,
            isDark: isDark,
            children: [
              _DesignActionChip(
                icon: Icons.brightness_6_rounded,
                label: 'Adjust',
                isDark: isDark,
                onTap: widget.onImageAdjust,
              ),
              _DesignActionChip(
                icon: Icons.crop_rounded,
                label: 'Fill',
                isDark: isDark,
                onTap: widget.onImageFillMode,
              ),
            ],
          ),
          const SizedBox(width: 8),

          // ─── Export ───
          _DesignChipGroup(
            label: 'Export',
            icon: Icons.download_rounded,
            isDark: isDark,
            children: [
              _DesignActionChip(
                icon: Icons.css_rounded,
                label: 'CSS',
                isDark: isDark,
                onTap: () => widget.onTokenExport?.call('css'),
              ),
              _DesignActionChip(
                icon: Icons.android_rounded,
                label: 'Kotlin',
                isDark: isDark,
                onTap: () => widget.onTokenExport?.call('kotlin'),
              ),
              _DesignActionChip(
                icon: Icons.apple_rounded,
                label: 'Swift',
                isDark: isDark,
                onTap: () => widget.onTokenExport?.call('swift'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 🏷️ Design Chip Widgets — Material 3 grouped action chips
// ============================================================================

/// A labeled group of action chips for the Design toolbar.
class _DesignChipGroup extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isDark;
  final List<Widget> children;

  const _DesignChipGroup({
    required this.label,
    required this.icon,
    required this.isDark,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: isDark ? 0.3 : 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Group label
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11, color: cs.onSurfaceVariant),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          // Action chips row
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                children[i],
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Single Material 3 action chip for the Design toolbar.
class _DesignActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final bool isActive;
  final VoidCallback? onTap;

  const _DesignActionChip({
    required this.icon,
    required this.label,
    required this.isDark,
    this.isActive = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeColor = cs.primary;
    final enabled = onTap != null;

    return GestureDetector(
      onTap:
          enabled
              ? () {
                HapticFeedback.selectionClick();
                onTap!();
              }
              : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color:
              isActive
                  ? activeColor.withValues(alpha: isDark ? 0.25 : 0.12)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border:
              isActive
                  ? Border.all(
                    color: activeColor.withValues(alpha: 0.5),
                    width: 1.5,
                  )
                  : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color:
                  !enabled
                      ? cs.onSurface.withValues(alpha: 0.25)
                      : isActive
                      ? activeColor
                      : (isDark ? Colors.white70 : Colors.black54),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color:
                    !enabled
                        ? cs.onSurface.withValues(alpha: 0.25)
                        : isActive
                        ? activeColor
                        : (isDark ? Colors.white54 : Colors.black45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
