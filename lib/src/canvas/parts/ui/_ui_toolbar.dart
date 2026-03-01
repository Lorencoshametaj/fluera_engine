part of '../../fluera_canvas_screen.dart';

/// 🛠️ Toolbar — extracted from _FlueraCanvasScreenState._buildImpl
extension FlueraCanvasToolbarUI on _FlueraCanvasScreenState {
  /// Builds the professional canvas toolbar.
  /// Hidden during multi-page edit, time travel, and placement mode.
  Widget _buildToolbar(BuildContext context) {
    // Professional Toolbar (nascosta nel multi-page edit, time travel, e placement mode)
    if (widget.hideToolbar ||
        _isMultiPageEditMode ||
        _isTimeTravelMode ||
        _isRecoveryPlacementMode) {
      return const SizedBox.shrink();
    }

    return ListenableBuilder(
      listenable: Listenable.merge([
        _undoRedoVersion,
        _toolController,
        _isRecordingNotifier,
      ]),
      builder: (context, child) {
        final activeLayer = _layerController.activeLayer;
        final elementCount = activeLayer?.elementCount ?? 0;

        // 🔄 Phase 2: Use LayerController undo/redo (delta-based)
        final canUndo = _layerController.canUndo;
        final canRedo = _layerController.canRedo;

        return ProfessionalCanvasToolbar(
          selectedPenType: _effectivePenType,
          selectedColor: _effectiveSelectedColor,
          selectedWidth: _effectiveWidth,
          selectedOpacity: _effectiveOpacity,
          selectedShapeType: _effectiveShapeType,
          strokeCount: elementCount,
          canUndo: canUndo,
          canRedo: canRedo,
          isEraserActive: _effectiveIsEraser,
          isLassoActive: _effectiveIsLasso,
          isDigitalTextActive: _effectiveIsDigitalText,
          isImagePickerActive: false, // 🖼️ Always false (is not a mode toggle)
          isRecordingActive: _isRecordingAudio,
          isPanModeActive:
              _effectiveIsPanMode, // 🖐️ Pan Mode - allows pan with a finger
          isStylusModeActive: _effectiveIsStylusMode, // 🖊️ Stylus mode
          isRulerActive: _showRulers, // 📏 Ruler overlay
          isPenToolActive: _toolController.isPenToolMode, // ✒️ Vector Pen Tool
          recordingDuration: _recordingDuration,
          recordingAmplitude:
              VoiceRecordingExtension._liveAmplitudes.isNotEmpty
                  ? VoiceRecordingExtension._liveAmplitudes.last
                  : 0.0,
          // 🚀 P99 FIX: Pass notifiers for independent recording UI updates
          recordingDurationNotifier: _recordingDurationNotifier,
          recordingAmplitudeNotifier: _recordingAmplitudeNotifier,
          isImageEditingMode: false,
          noteTitle: _noteTitle, // 🆕 Pass note title
          // 🎨 Preset-based brush selection
          brushPresets: BrushPreset.defaultPresets,
          selectedPresetId: _selectedPresetId,
          onPresetSelected: (preset) {
            _selectedPresetId = preset.id;
            _brushSettings = preset.settings;
            _toolController.setPenType(preset.penType);
            _toolController.setStrokeWidth(preset.baseWidth);
            _toolController.setColor(preset.color);
            _toolController.resetToDrawingMode();
            _digitalTextTool.deselectElement();
            EngineScope.current.drawingModule?.brushSettingsService
                .updateSettings(preset.settings);
          },
          onUndo: () {
            // 🎤 FIX: If recording with strokes, track stroke removal
            // to prevent ghost strokes during synced playback.
            final strokesBefore =
                _isRecordingAudio && _recordingWithStrokes
                    ? _layerController.activeLayer?.strokes.length ?? 0
                    : 0;
            final lastStrokeId =
                (_isRecordingAudio &&
                        _recordingWithStrokes &&
                        _syncRecordingBuilder != null &&
                        (strokesBefore > 0))
                    ? _layerController.activeLayer?.strokes.last.id
                    : null;

            _layerController.undo(); // 🔄 Phase 2: New undo system

            // If a stroke was removed during undo, remove it from sync builder
            if (lastStrokeId != null && _syncRecordingBuilder != null) {
              final strokesAfter =
                  _layerController.activeLayer?.strokes.length ?? 0;
              if (strokesAfter < strokesBefore) {
                _syncRecordingBuilder!.removeStrokeById(lastStrokeId);
              }
            }
          },
          onRedo: () => _layerController.redo(), // 🔄 Phase 2: New redo system
          onClear: _clear,
          onSettings: _showSettings,
          onPaperTypePressed: _showPaperTypePicker,
          onBrushSettingsPressed: (anchorRect) {
            // 🎛️ Long-press → Show brush characteristics popup
            if (!mounted) return;
            ProBrushSettingsDialog.show(
              context,
              settings: _brushSettings,
              currentBrush: _effectivePenType,
              anchorRect: anchorRect,
              currentColor: _effectiveColor,
              currentWidth: _effectiveWidth,
              onSettingsChanged: (newSettings) {
                _brushSettings = newSettings;
                // 🎯 Keep stabilizer in sync with settings
                _drawingHandler.stabilizerLevel = newSettings.stabilizerLevel;
                EngineScope.current.drawingModule?.brushSettingsService
                    .updateSettings(newSettings);
              },
            );
          },
          onExportPressed: _enterExportMode, // 📤 Export canvas
          onNoteTitleChanged: (newTitle) {
            // 🆕 Callback per rinominare nota
            _noteTitle = newTitle;
            setState(() {});
            _autoSaveCanvas(); // Save immediatamente
          },
          onLayersPressed: () {
            _layerPanelKey.currentState?.togglePanel();
          },
          onEraserToggle: () {
            _toolController.toggleEraser();
            if (_effectiveIsEraser) {
              _digitalTextTool.deselectElement();
              _toolSystemBridge?.selectTool('eraser');
            } else {
              _eraserCursorPosition = null;
            }
            setState(() {}); // 🚀 Toolbar-only rebuild
          },
          eraserRadius: _eraserTool.eraserRadius,
          onEraserRadiusChanged: (radius) {
            _eraserTool.eraserRadius = radius;
            setState(() {});
          },
          eraseWholeStroke: _eraserTool.eraseWholeStroke,
          onEraseWholeStrokeChanged: (value) {
            _eraserTool.eraseWholeStroke = value;
            setState(() {});
            HapticFeedback.selectionClick();
          },
          onLassoToggle: () {
            _toolController.toggleLassoMode();
            if (_toolController.isLassoActive) {
              _digitalTextTool.deselectElement();
              _eraserCursorPosition = null;
              _toolSystemBridge?.selectTool('lasso');
            }
            setState(() {}); // 🚀 Toolbar-only rebuild
          },
          onDigitalTextToggle: () {
            _toolController.toggleDigitalTextMode();
            if (_toolController.isDigitalTextActive) {
              _showDigitalTextDialog();
            } else {
              _digitalTextTool.deselectElement();
            }
            setState(() {}); // 🚀 Toolbar-only rebuild
          },
          onPanModeToggle: () {
            _toolController.togglePanMode();
            if (_toolController.isPanMode) {
              _digitalTextTool.deselectElement();
            }
            setState(() {}); // 🚀 Toolbar-only rebuild
          },
          onStylusModeToggle: () {
            _toolController.toggleStylusMode();
            setState(() {}); // 🚀 Toolbar-only rebuild
          },
          onRulerToggle: () {
            _showRulers = !_showRulers;
            setState(() {});
            HapticFeedback.lightImpact();
          },
          isMinimapVisible: _showMinimap,
          onMinimapToggle: () {
            _showMinimap = !_showMinimap;
            setState(() {});
            HapticFeedback.lightImpact();
          },
          isSectionActive: _isSectionActive,
          onSectionToggle: () {
            _isSectionActive = !_isSectionActive;
            setState(() {});
            if (_isSectionActive) {
              // Deselect conflicting tools
              _toolController.resetToDrawingMode();
              _digitalTextTool.deselectElement();
              _lassoTool.clearSelection();
              _eraserCursorPosition = null;
            }
            HapticFeedback.selectionClick();
          },
          onPenToolToggle: () {
            final wasActive = _toolController.isPenToolMode;
            _toolController.togglePenTool();
            if (_toolController.isPenToolMode) {
              // Deselect all other interactive tools
              _digitalTextTool.deselectElement();
              _lassoTool.clearSelection();
              _imageTool.clearSelection();
              _eraserCursorPosition = null;
              // #7: Sync pen tool color with toolbar selection
              _penTool.strokeColor = _effectiveColor;
              _penTool.strokeWidth = _effectiveWidth;
              // #5: Dark/light mode
              _penTool.isDarkMode =
                  Theme.of(context).brightness == Brightness.dark;
              // #1: Snap-to-guide
              _penTool.snapPosition =
                  _showRulers && _rulerGuideSystem.snapEnabled
                      ? (pos) => _rulerGuideSystem.snapPoint(
                        pos,
                        _canvasController.scale,
                      )
                      : null;
            } else if (wasActive) {
              // #8: Call onDeactivate to finalize partial paths
              _penTool.onDeactivate(_penToolContext);
            }
            setState(() {}); // 🚀 Toolbar-only rebuild
          },
          // 🧮 LaTeX Editor
          isLatexActive: _toolController.isLatexMode,
          onLatexToggle: () {
            _toolController.toggleLatexMode();
            if (_toolController.isLatexMode) {
              _digitalTextTool.deselectElement();
              _lassoTool.clearSelection();
              _eraserCursorPosition = null;
              _showLatexEditorSheet();
            }
            setState(() {}); // 🚀 Toolbar-only rebuild
          },
          // 📊 Tabular (Spreadsheet) — Excel tab uses onTabularCreate
          isTabularActive: _toolController.isTabularMode,
          onTabularToggle: () {
            _toolController.toggleTabularMode();
            if (_toolController.isTabularMode) {
              _digitalTextTool.deselectElement();
              _lassoTool.clearSelection();
              _eraserCursorPosition = null;
              _addTabularNode();
            }
            setState(() {});
          },
          onTabularCreate: (columns, rows) {
            _digitalTextTool.deselectElement();
            _lassoTool.clearSelection();
            _eraserCursorPosition = null;
            _addTabularNode(columns: columns, rows: rows);
          },
          hasTabularSelection: _tabularTool.hasSelection,
          selectedCellRef:
              _tabularTool.cellRefLabel.isEmpty
                  ? null
                  : _tabularTool.cellRefLabel,
          selectedCellValue: _getSelectedCellDisplayValue(),
          onCellValueSubmit: _onFormulaBarSubmit,
          onCellTabSubmit: _onFormulaBarTab,
          onTabularDelete: _deleteSelectedTabular,
          onInsertRow: _insertRow,
          onDeleteRow: _deleteRow,
          onInsertColumn: _insertColumn,
          onDeleteColumn: _deleteColumn,
          onMergeCells: _mergeCells,
          onUnmergeCells: _unmergeCells,
          onCopySelection: _copySelection,
          onCutSelection: _cutSelection,
          onPasteSelection: _pasteAtSelection,
          onSortColumn: (ascending) {
            final col = _tabularTool.selectedCol;
            if (col != null) {
              _sortByColumn(column: col, ascending: ascending);
            }
          },
          onAutoFill: _autoFillDown,
          selectedCellFormat: _getSelectedCellFormat(),
          hasRangeSelection: _tabularTool.hasRangeSelection,
          onToggleBold: _toggleBold,
          onToggleItalic: _toggleItalic,
          onBorderPreset: _setBorderPreset,
          onSetAlignment: _setAlignment,
          onSetTextColor: _setTextColor,
          onSetBackgroundColor: _setBackgroundColor,
          onClearFormatting: _clearFormatting,
          onClearCells: _clearSelectedCells,
          onGenerateLatex: _generateLatexFromSelection,
          onCopySelectionAsLatex: () {
            final latex = _tabularTool.selectionToLatex(includeHeaders: true);
            if (latex == null) return;
            HapticFeedback.lightImpact();
            showDialog(
              context: context,
              builder: (ctx) {
                final cs = Theme.of(ctx).colorScheme;
                return AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  backgroundColor: const Color(0xFF1E1E1E),
                  titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                  title: Row(
                    children: [
                      Icon(Icons.code_rounded, color: cs.primary, size: 22),
                      const SizedBox(width: 10),
                      const Text(
                        'LaTeX Code',
                        style: TextStyle(
                          color: Color(0xFFE0E0E0),
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Package requirements notice.
                      if (latex.contains('\\multirow') ||
                          latex.contains('\\toprule'))
                        Container(
                          width: double.maxFinite,
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2A2010),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(0xFF5C4A1E),
                              width: 0.5,
                            ),
                          ),
                          child: Text(
                            '📦 Add to preamble:\n'
                            '${latex.contains('\\multirow') ? '\\usepackage{multirow}\n' : ''}'
                            '${latex.contains('\\toprule') ? '\\usepackage{booktabs}\n' : ''}',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: Color(0xFFFFD54F),
                              height: 1.4,
                            ),
                          ),
                        ),
                      // LaTeX code.
                      Container(
                        width: double.maxFinite,
                        constraints: const BoxConstraints(maxHeight: 300),
                        decoration: BoxDecoration(
                          color: const Color(0xFF121212),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF333333),
                            width: 0.5,
                          ),
                        ),
                        padding: const EdgeInsets.all(14),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            latex,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              color: Color(0xFFA5D6A7),
                              height: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Close'),
                    ),
                    FilledButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: latex));
                        HapticFeedback.mediumImpact();
                        Navigator.of(ctx).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('LaTeX copied to clipboard'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('Copy'),
                    ),
                  ],
                );
              },
            );
          },
          onGenerateChart: _generateChartFromSelection,
          onImportLatex: _importLatexToSpreadsheet,
          onExportTex: _exportTexFile,
          onImportCsv: _importCsv,
          onExportCsv: () {
            final csv = _exportCsv();
            if (csv.isNotEmpty) {
              Clipboard.setData(ClipboardData(text: csv));
              HapticFeedback.lightImpact();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('CSV copied to clipboard'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          },
          hasFrozenRow: _hasFrozenRow(),
          onToggleFreezeRow: _toggleFreezeRow,
          onImagePickerPressed: () {
            // 🖼️ Open gallery and add image
            pickAndAddImage();
          },
          onImageEditorPressed: null,
          onRecordingPressed: () {
            // 🎤 Se sta registrando, ferma la registrazione
            if (_isRecordingAudio) {
              _stopAudioRecording();
            } else {
              // Altrimenti mostra popup scelta registrazione
              _showRecordingChoiceDialog();
            }
          },
          onViewRecordingsPressed: () {
            // 🎧 Mostra lista saved recordings
            _showSavedRecordingsDialog();
          },
          // ⏱️ Time Travel (solo Pro)
          onTimeTravelPressed:
              (_subscriptionTier == FlueraSubscriptionTier.pro)
                  ? _enterTimeTravelMode
                  : null,
          // 🌿 Branch Explorer (solo Pro)
          onBranchExplorerPressed:
              (_subscriptionTier == FlueraSubscriptionTier.pro)
                  ? _openBranchExplorer
                  : null,
          activeBranchName: _activeBranchName,
          onAdvancedSplitPressed: () {
            // 🚀 Launch new advanced split system
            _launchAdvancedSplitView();
          },
          onPenTypeChanged: (type) {
            _toolController.setPenType(type);
            _toolController.resetToDrawingMode();
            _digitalTextTool.deselectElement();
            setState(() {}); // 🚀 Toolbar-only rebuild
          },
          onColorChanged: (color) {
            _toolController.setColor(color);
            // 🎨 Mark manual override to prevent auto-apply from overriding
            EngineScope.current.styleCoherenceEngine.markManualOverride(
              _consciousToolName(),
            );
            setState(() {}); // 🚀 Toolbar-only rebuild
          },
          onWidthChanged: (width) {
            _toolController.setStrokeWidth(width);
            EngineScope.current.styleCoherenceEngine.markManualOverride(
              _consciousToolName(),
            );
            setState(() {}); // 🚀 Toolbar-only rebuild
          },
          onOpacityChanged: (opacity) {
            _toolController.setOpacity(opacity);
            EngineScope.current.styleCoherenceEngine.markManualOverride(
              _consciousToolName(),
            );
            setState(() {}); // 🚀 Toolbar-only rebuild
          },
          onShapeTypeChanged: (type) {
            _toolController.setShapeType(type);
            // 🛠️ FIX: Don't call resetToDrawingMode() - it resets shapeType to freehand!
            // Instead, only disable conflicting modes
            if (type != ShapeType.freehand) {
              _toolController.setEraserMode(false);
              // Lasso and digital text should also be disabled for shapes
              if (_toolController.isLassoActive) {
                _toolController.toggleLassoMode();
              }
              if (_toolController.isDigitalTextActive) {
                _toolController.toggleDigitalTextMode();
              }
              _digitalTextTool.deselectElement();
            }
            setState(() {}); // 🚀 Toolbar-only rebuild
          },
          // 🌀 Reset Rotation
          isCanvasRotated: _canvasController.rotation != 0.0,
          onResetRotation: () {
            _canvasController.resetRotation();
            setState(() {});
          },
          isRotationLocked: _canvasController.rotationLocked,
          onToggleRotationLock: () {
            _canvasController.rotationLocked =
                !_canvasController.rotationLocked;
            setState(() {});
          },
          // 🔷 Shape Recognition
          shapeRecognitionEnabled: _toolController.shapeRecognitionEnabled,
          shapeRecognitionSensitivityIndex:
              _toolController.shapeRecognitionSensitivity.index,
          onShapeRecognitionToggle: () {
            _toolController.toggleShapeRecognition();
            setState(() {});
          },
          onShapeRecognitionSensitivityCycle: () {
            _toolController.cycleShapeRecognitionSensitivity();
            setState(() {});
          },
          ghostSuggestionEnabled: _toolController.ghostSuggestionMode,
          onGhostSuggestionToggle: () {
            _toolController.toggleGhostSuggestionMode();
            setState(() {});
          },
          onPdfImportPressed: () {
            pickAndAddPdf();
          },
          onPdfCreateBlankPressed: () {
            _showBackgroundChooser(context);
          },
          // 📄 PDF active state — contextual tools
          isPdfActive: _pdfPainters.isNotEmpty,
          pdfDocument: _activePdfDocument,
          pdfDocuments: _findAllPdfDocuments(),
          pdfAnnotationController: _pdfAnnotationController,
          pdfSearchController: _pdfSearchController,
          pdfSelectedPageIndex: _pdfSelectedPageIndex,
          showPdfPageNumbers: _showPdfPageNumbers,
          onTogglePdfPageNumbers: () {
            _showPdfPageNumbers = !_showPdfPageNumbers;
            _pdfLayoutVersion++;
            _canvasController.markNeedsPaint();
            setState(() {});
          },
          onPdfPageIndexChanged: (newIndex) {
            _pdfSelectedPageIndex = newIndex;
            setState(() {});
          },
          onPdfDocumentChanged: (docId) {
            _activePdfDocumentId = docId;
            setState(() {});
            // Re-attach annotation controller to newly selected document
            final doc = _findPdfDocumentById(docId);
            if (doc != null) {
              _pdfAnnotationController?.dispose();
              _pdfAnnotationController = PdfAnnotationController();
              _pdfAnnotationController!.attach(doc);
            }
          },
          onPdfInsertBlankPage:
              _pdfPainters.isNotEmpty
                  ? (selectedPageIndex) {
                    final doc = _activePdfDocument;
                    if (doc != null) {
                      doc.insertBlankPage(afterIndex: selectedPageIndex);
                      // Track the newly inserted page as selected
                      _pdfSelectedPageIndex = selectedPageIndex + 1;
                      _pdfLayoutVersion++;
                      _canvasController.markNeedsPaint();
                      setState(() {});
                      _autoSaveCanvas();
                    }
                  }
                  : null,
          onPdfDuplicatePage:
              _pdfPainters.isNotEmpty
                  ? (pageIndex) {
                    final doc = _activePdfDocument;
                    if (doc != null) {
                      doc.duplicatePage(pageIndex);
                      _pdfSelectedPageIndex = pageIndex + 1;
                      _pdfLayoutVersion++;
                      _canvasController.markNeedsPaint();
                      setState(() {});
                      _autoSaveCanvas();
                    }
                  }
                  : null,
          onPdfDeletePage: (pageIndex) {
            final doc = _activePdfDocument;
            if (doc != null && doc.documentModel.totalPages > 1) {
              doc.removePage(pageIndex);
              _canvasController.markNeedsPaint();
              setState(() {});
              _autoSaveCanvas();
            }
          },
          onPdfDeleteDocument:
              _activePdfDocumentId != null
                  ? () =>
                      showDeletePdfConfirmation(context, _activePdfDocumentId!)
                  : null,
          onPdfReorderPage: (oldIndex, newIndex) {
            final doc = _activePdfDocument;
            if (doc == null) return;
            doc.reorderPage(oldIndex, newIndex);
            _pdfLayoutVersion++;
            _canvasController.markNeedsPaint();
            setState(() {});
            _autoSaveCanvas();
          },
          onPdfGoToPage: (documentId, pageIndex) {
            final doc =
                _findPdfDocumentById(documentId) ?? _findFirstPdfDocument();
            if (doc == null) return;
            // Find the page node for this index
            final pageNode = doc.pageAt(pageIndex);
            if (pageNode == null) return;
            // Get the canvas-space rect for the page
            final pageRect = doc.pageRectFor(pageNode);
            final pageCenter = pageRect.center;
            // Compute viewport size from context
            final viewportSize = MediaQuery.of(context).size;
            // Target offset: center the page in the viewport
            final scale = _canvasController.scale;
            final targetOffset = Offset(
              viewportSize.width / 2 - pageCenter.dx * scale,
              viewportSize.height / 2 - pageCenter.dy * scale,
            );
            _canvasController.animateOffsetTo(targetOffset);
          },
          onPdfNightModeToggle: () {
            final doc = _activePdfDocument;
            if (doc == null) return;
            final newNightMode = !doc.documentModel.nightMode;
            doc.documentModel = doc.documentModel.copyWith(
              nightMode: newNightMode,
            );
            _realtimeEngine?.broadcastPdfUpdated(
              documentId: doc.id.toString(),
              subAction: 'nightModeToggled',
              data: {'enabled': newNightMode},
            );
            _pdfLayoutVersion++;
            _canvasController.markNeedsPaint();
            setState(() {});
            _autoSaveCanvas();
          },
          onPdfBookmarkToggle: (pageIndex) {
            final doc = _activePdfDocument;
            if (doc == null) return;
            final pages = doc.pageNodes;
            if (pageIndex < 0 || pageIndex >= pages.length) return;
            final page = pages[pageIndex];
            final newBookmarked = !page.pageModel.isBookmarked;
            page.pageModel = page.pageModel.copyWith(
              isBookmarked: newBookmarked,
            );
            _realtimeEngine?.broadcastPdfUpdated(
              documentId: doc.id.toString(),
              subAction: 'bookmarkToggled',
              data: {'pageIndex': pageIndex, 'isBookmarked': newBookmarked},
            );
            _pdfLayoutVersion++;
            _canvasController.markNeedsPaint();
            setState(() {});
            _autoSaveCanvas();
          },
          onPdfZoomToFit: (pageIndex) {
            final doc = _activePdfDocument;
            if (doc == null) return;
            final pageNode = doc.pageAt(pageIndex);
            if (pageNode == null) return;
            final pageRect = doc.pageRectFor(pageNode);
            final viewportSize = MediaQuery.of(context).size;
            // Scale to fit page in viewport with padding
            final scaleX = (viewportSize.width - 40) / pageRect.width;
            final scaleY = (viewportSize.height - 80) / pageRect.height;
            final targetScale = scaleX < scaleY ? scaleX : scaleY;
            final pageCenter = pageRect.center;
            final targetOffset = Offset(
              viewportSize.width / 2 - pageCenter.dx * targetScale,
              viewportSize.height / 2 - pageCenter.dy * targetScale,
            );
            _canvasController.animateToTransform(
              targetOffset: targetOffset,
              targetScale: targetScale,
            );
          },
          onPdfWatermarkToggle: () {
            final doc = _activePdfDocument;
            if (doc == null) return;
            final current = doc.documentModel.watermarkText;
            if (current != null) {
              // Remove watermark
              doc.documentModel = doc.documentModel.copyWith(
                clearWatermarkText: true,
              );
              _realtimeEngine?.broadcastPdfUpdated(
                documentId: doc.id.toString(),
                subAction: 'watermarkChanged',
                data: {'clear': true},
              );
            } else {
              // Add default watermark
              doc.documentModel = doc.documentModel.copyWith(
                watermarkText: 'DRAFT',
              );
              _realtimeEngine?.broadcastPdfUpdated(
                documentId: doc.id.toString(),
                subAction: 'watermarkChanged',
                data: {'watermarkText': 'DRAFT'},
              );
            }
            _pdfLayoutVersion++;
            _canvasController.markNeedsPaint();
            setState(() {});
            _autoSaveCanvas();
          },
          onPdfAddStamp: (pageIndex, _) {
            final doc = _activePdfDocument;
            if (doc == null) return;
            final pages = doc.pageNodes;
            if (pageIndex < 0 || pageIndex >= pages.length) return;
            final page = pages[pageIndex];
            final hasStamps = page.pageModel.structuredAnnotations.any(
              (a) => a.type == PdfAnnotationType.stamp,
            );
            // Show stamp type picker
            showModalBottomSheet<PdfStampType?>(
              context: context,
              builder: (sheetCtx) {
                final cs = Theme.of(sheetCtx).colorScheme;
                return SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Text(
                          'Choose Stamp',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                      // 🗑️ Remove stamps option (only if stamps exist)
                      if (hasStamps) ...[
                        ListTile(
                          leading: Icon(
                            Icons.delete_outline_rounded,
                            color: cs.error,
                          ),
                          title: Text(
                            'Remove All Stamps',
                            style: TextStyle(color: cs.error),
                          ),
                          onTap: () => Navigator.pop(sheetCtx), // null = remove
                        ),
                        const Divider(height: 1),
                      ],
                      ...PdfStampType.values.map((stamp) {
                        final label =
                            stamp.name.replaceAll('_', '').toUpperCase();
                        final colors = <PdfStampType, Color>{
                          PdfStampType.approved: Colors.green,
                          PdfStampType.draft: Colors.orange,
                          PdfStampType.confidential: Colors.red,
                          PdfStampType.final_: Colors.blue,
                          PdfStampType.reviewed: Colors.teal,
                          PdfStampType.rejected: Colors.red.shade900,
                        };
                        return ListTile(
                          leading: Icon(
                            Icons.approval_rounded,
                            color: colors[stamp],
                          ),
                          title: Text(label),
                          onTap: () => Navigator.pop(sheetCtx, stamp),
                        );
                      }),
                      const SizedBox(height: 8),
                    ],
                  ),
                );
              },
            ).then((stampType) {
              if (stampType == null) {
                // Remove all stamps from this page (user picked 'Remove')
                // But only if stamps exist — dismiss without action otherwise
                if (hasStamps) {
                  page.pageModel = page.pageModel.copyWith(
                    structuredAnnotations:
                        page.pageModel.structuredAnnotations
                            .where((a) => a.type != PdfAnnotationType.stamp)
                            .toList(),
                  );
                  _pdfLayoutVersion++;
                  _canvasController.markNeedsPaint();
                  setState(() {});
                  _autoSaveCanvas();
                }
                return;
              }
              final pageSize = page.pageModel.originalSize;
              final stamp = PdfAnnotation(
                id: 'stamp_${DateTime.now().microsecondsSinceEpoch}',
                type: PdfAnnotationType.stamp,
                pageIndex: pageIndex,
                rect: Rect.fromCenter(
                  center: Offset(pageSize.width / 2, pageSize.height / 2),
                  width: pageSize.width * 0.4,
                  height: pageSize.height * 0.08,
                ),
                color: const Color(0x80E53935),
                stampType: stampType,
                createdAt: DateTime.now().microsecondsSinceEpoch,
                lastModifiedAt: DateTime.now().microsecondsSinceEpoch,
              );
              page.pageModel = page.pageModel.copyWith(
                structuredAnnotations: [
                  ...page.pageModel.structuredAnnotations,
                  stamp,
                ],
              );
              _pdfLayoutVersion++;
              _canvasController.markNeedsPaint();
              setState(() {});
              _autoSaveCanvas();
            });
          },
          onPdfChangeBackground: (pageIndex) {
            final doc = _activePdfDocument;
            if (doc == null) return;
            final pages = doc.pageNodes;
            if (pageIndex < 0 || pageIndex >= pages.length) return;
            final page = pages[pageIndex];
            // Only allow background change for blank pages
            if (!page.pageModel.isBlank) return;

            final currentBg = page.pageModel.background;
            showModalBottomSheet<PdfPageBackground>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              backgroundColor: Colors.transparent,
              builder: (sheetCtx) {
                final cs = Theme.of(sheetCtx).colorScheme;
                PdfPageBackground selected = currentBg;
                return StatefulBuilder(
                  builder: (ctx, setSheetState) {
                    return Container(
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(28),
                        ),
                      ),
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Handle bar
                              Container(
                                width: 32,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: cs.onSurfaceVariant.withValues(
                                    alpha: 0.4,
                                  ),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'Page Background',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 20),
                              GridView.count(
                                crossAxisCount: 3,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                childAspectRatio: 0.72,
                                children:
                                    PdfPageBackground.values.map((bg) {
                                      return _PatternCard(
                                        background: bg,
                                        isSelected: selected == bg,
                                        colorScheme: cs,
                                        onTap: () {
                                          setSheetState(() => selected = bg);
                                        },
                                      );
                                    }).toList(),
                              ),
                              const SizedBox(height: 24),
                              SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: FilledButton.icon(
                                  onPressed:
                                      () => Navigator.pop(sheetCtx, selected),
                                  icon: const Icon(
                                    Icons.check_rounded,
                                    size: 20,
                                  ),
                                  label: const Text(
                                    'Apply',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  style: FilledButton.styleFrom(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ).then((newBg) {
              if (newBg == null || newBg == currentBg) return;
              page.pageModel = page.pageModel.copyWith(background: newBg);
              _realtimeEngine?.broadcastPdfUpdated(
                documentId: doc.id.toString(),
                subAction: 'pageBackgroundChanged',
                data: {'pageIndex': pageIndex, 'background': newBg.name},
              );
              _pdfLayoutVersion++;
              _canvasController.markNeedsPaint();
              setState(() {});
              _autoSaveCanvas();
            });
          },
          onPdfPrint: () async {
            final doc = _activePdfDocument;
            if (doc == null) return;
            final filePath = doc.documentModel.filePath;
            if (filePath == null) return;
            const channel = MethodChannel(
              'com.flueraengine.fluera_engine/print',
            );
            try {
              await channel.invokeMethod('printPdf', {
                'filePath': filePath,
                'jobName': doc.documentModel.fileName ?? 'PDF Document',
              });
            } catch (e) {
              debugPrint('Print failed: $e');
            }
          },
          onPdfPresentation: () async {
            final doc = _activePdfDocument;
            if (doc == null) return;

            // ── Pre-render pages at screen-fit resolution ──
            FlueraPdfProvider? provider;
            // Try multiple keys to find the provider
            if (_activePdfDocumentId != null) {
              provider = _pdfProviders[_activePdfDocumentId!];
            }
            provider ??= _pdfProviders[doc.id.value];
            // Fallback: use first available provider
            if (provider == null && _pdfProviders.isNotEmpty) {
              provider = _pdfProviders.values.first;
            }
            debugPrint(
              '[Present] provider found: ${provider != null}, '
              'keys: ${_pdfProviders.keys.toList()}, '
              'docId: ${doc.id.value}, activeId: $_activePdfDocumentId',
            );
            if (provider != null) {
              final screenSize = MediaQuery.of(context).size;
              final dpr = MediaQuery.of(context).devicePixelRatio;
              final pgs = doc.pageNodes;
              for (int i = 0; i < pgs.length; i++) {
                final page = pgs[i];
                final pSize = page.pageModel.originalSize;
                final sx = screenSize.width / pSize.width;
                final sy = screenSize.height / pSize.height;
                final fitScale = (sx < sy ? sx : sy) * dpr;
                final targetSize = Size(
                  pSize.width * fitScale,
                  pSize.height * fitScale,
                );
                debugPrint(
                  '[Present] Rendering page $i at ${targetSize.width.toInt()}x${targetSize.height.toInt()} (scale: ${fitScale.toStringAsFixed(2)})',
                );
                final img = await provider.renderPage(
                  pageIndex: page.pageModel.pageIndex,
                  scale: fitScale,
                  targetSize: targetSize,
                );
                if (img != null) {
                  page.cachedImage?.dispose();
                  page.cachedImage = img;
                  page.cachedScale = fitScale;
                  debugPrint(
                    '[Present] Page $i rendered: ${img.width}x${img.height}',
                  );
                } else {
                  // Blank/out-of-range page — create white image
                  final w = targetSize.width.toInt();
                  final h = targetSize.height.toInt();
                  final recorder = ui.PictureRecorder();
                  final c = Canvas(
                    recorder,
                    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
                  );
                  c.drawRect(
                    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
                    Paint()..color = Colors.white,
                  );
                  final pic = recorder.endRecording();
                  final blankImg = await pic.toImage(w, h);
                  page.cachedImage?.dispose();
                  page.cachedImage = blankImg;
                  page.cachedScale = fitScale;
                  debugPrint('[Present] Page $i: blank fallback ${w}x$h');
                }
              }
            }

            // ── Collect strokes linked to each page ──
            final allStrokes = <String, ProStroke>{};
            for (final layer in _layerController.sceneGraph.layers) {
              for (final strokeNode in layer.strokeNodes) {
                allStrokes[strokeNode.stroke.id] = strokeNode.stroke;
              }
            }
            final pageStrokes = <int, List<ProStroke>>{};
            final pages = doc.pageNodes;
            for (int i = 0; i < pages.length; i++) {
              final ids = pages[i].pageModel.annotations;
              final strokes = <ProStroke>[];
              for (final id in ids) {
                final s = allStrokes[id];
                if (s != null) strokes.add(s);
              }
              if (strokes.isNotEmpty) pageStrokes[i] = strokes;
            }
            if (!mounted) return;
            Navigator.of(context).push(
              MaterialPageRoute(
                builder:
                    (_) => PdfPresentationOverlay(
                      doc: doc,
                      initialPage: _pdfSelectedPageIndex,
                      pageStrokes: pageStrokes,
                    ),
              ),
            );
          },
          // TODO(future): onPdfSignature — digital signing requires QTSP, X.509, PAdES.
          onPdfLayoutModeChanged: (mode) {
            final doc = _activePdfDocument;
            if (doc == null) return;
            doc.documentModel = doc.documentModel.copyWith(layoutMode: mode);
            _realtimeEngine?.broadcastPdfUpdated(
              documentId: doc.id.toString(),
              subAction: 'layoutModeChanged',
              data: {'layoutMode': mode.name},
            );
            _pdfLayoutVersion++;
            setState(() {});
            _autoSaveCanvas();
          },
          onPdfLayoutChanged: () {
            // Bump version so DrawingPainter.shouldRepaint detects the change.
            // togglePageLock/rotate/grid mutate page models in-place without
            // structural changes, so the version must be bumped explicitly.
            _pdfLayoutVersion++;

            // 📄 Translate linked annotation strokes when pages move.
            // performGridLayout() populates pendingStrokeTranslations with
            // per-page deltas for all pages whose annotations need moving.
            bool didTranslate = false;
            for (final layer in _layerController.sceneGraph.layers) {
              for (final child in layer.children) {
                if (child is PdfDocumentNode &&
                    child.pendingStrokeTranslations.isNotEmpty) {
                  final translations = child.pendingStrokeTranslations.toList();
                  child.pendingStrokeTranslations.clear(); // Consume

                  for (final tx in translations) {
                    if (tx.annotationIds.isNotEmpty) {
                      final idSet = Set<String>.of(tx.annotationIds);
                      for (final l in _layerController.layers) {
                        for (final strokeNode in l.node.strokeNodes) {
                          if (idSet.contains(strokeNode.stroke.id)) {
                            final old = strokeNode.stroke;
                            final translated =
                                old.points.map((p) {
                                  return p.copyWith(
                                    position: p.position + tx.delta,
                                  );
                                }).toList();
                            strokeNode.stroke = old.copyWith(
                              points: translated,
                            );
                            didTranslate = true;
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
            if (didTranslate) {
              DrawingPainter.invalidateAllTiles();
            }

            // 🔄 Rotate linked annotation strokes when a page is rotated.
            // rotatePage() populates pendingStrokeRotation with the angle,
            // center, and annotation IDs for the rotated page.
            for (final layer in _layerController.sceneGraph.layers) {
              for (final child in layer.children) {
                if (child is PdfDocumentNode &&
                    child.pendingStrokeRotation != null) {
                  final rot = child.pendingStrokeRotation!;
                  child.pendingStrokeRotation = null; // Consume

                  if (rot.annotationIds.isNotEmpty) {
                    final idSet = Set<String>.of(rot.annotationIds);
                    final cosA = math.cos(rot.angleRadians);
                    final sinA = math.sin(rot.angleRadians);
                    final cx = rot.center.dx;
                    final cy = rot.center.dy;

                    for (final l in _layerController.layers) {
                      for (final strokeNode in l.node.strokeNodes) {
                        if (idSet.contains(strokeNode.stroke.id)) {
                          final old = strokeNode.stroke;
                          final rotated =
                              old.points.map((p) {
                                final dx = p.position.dx - cx;
                                final dy = p.position.dy - cy;
                                return p.copyWith(
                                  position: Offset(
                                    cx + dx * cosA - dy * sinA,
                                    cy + dx * sinA + dy * cosA,
                                  ),
                                );
                              }).toList();
                          strokeNode.stroke = old.copyWith(points: rotated);
                        }
                      }
                    }
                    DrawingPainter.invalidateAllTiles();
                  }
                }
              }
            }

            _canvasController.markNeedsPaint();
            setState(() {});
            _autoSaveCanvas();
          },
          onPdfExport: () async {
            final doc = _activePdfDocument;
            if (doc == null) return;

            final pdfName =
                doc.documentModel.fileName ?? _noteTitle ?? 'Export';

            // 1. Generate first page thumbnail for preview
            Uint8List? firstPagePreview;
            final firstPage = doc.pageNodes.firstOrNull;
            if (firstPage?.cachedImage != null) {
              final byteData = await firstPage!.cachedImage!.toByteData(
                format: ui.ImageByteFormat.png,
              );
              if (byteData != null) {
                firstPagePreview = byteData.buffer.asUint8List();
              }
            }

            // 2. Show export settings dialog with PDF name pre-filled
            final config = await PdfExportDialog.show(
              context,
              defaultFileName: pdfName,
              totalPages: doc.pageNodes.length,
              firstPagePreview: firstPagePreview,
            );
            if (config == null || !mounted) return;

            final messenger = ScaffoldMessenger.of(context);
            final totalPages =
                config.onlyAnnotatedPages
                    ? doc.pageNodes
                        .where((p) => p.pageModel.annotations.isNotEmpty)
                        .length
                    : doc.pageNodes.length;

            // 2. Show progress snackbar with live updates
            int renderedCount = 0;
            messenger.showSnackBar(
              SnackBar(
                content: StatefulBuilder(
                  builder: (ctx, setSnackState) {
                    // Store setter for updates from onProgress
                    _exportProgressSetter = (current, total) {
                      renderedCount = current;
                      setSnackState(() {});
                    };
                    return Row(
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            value:
                                totalPages > 0
                                    ? renderedCount / totalPages
                                    : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text('Exporting… $renderedCount/$totalPages pages'),
                      ],
                    );
                  },
                ),
                duration: const Duration(seconds: 120),
              ),
            );

            try {
              // 3. Export annotated pages as PNG images
              final exporter = PdfAnnotationExporter(
                pixelRatio:
                    config.format == PdfExportFormat.pdf
                        ? 3.0
                        : config.resolution.multiplier,
                onProgress: (current, total) {
                  _exportProgressSetter?.call(current, total);
                },
              );
              final result = await exporter.exportDocument(
                doc,
                layers: _layerController.layers,
                onlyAnnotatedPages: config.onlyAnnotatedPages,
              );

              if (!mounted) return;

              final exportName =
                  config.fileName?.isNotEmpty == true
                      ? config.fileName!
                      : pdfName.replaceAll(
                        RegExp(r'\.pdf$', caseSensitive: false),
                        '',
                      );
              final sanitizedName = exportName.replaceAll(
                RegExp(r'[^\w\s-]'),
                '_',
              );

              // ─── IMAGE FORMAT EXPORT (JPG/PNG) ─────────────────────────
              if (config.format == PdfExportFormat.jpg ||
                  config.format == PdfExportFormat.png) {
                final tempDir = await getSafeTempDirectory();
                if (tempDir == null) return; // Web: no filesystem
                final ext = config.format.extension;
                final mimeType = config.format.mimeType;
                final filePaths = <String>[];

                for (int i = 0; i < result.pages.length; i++) {
                  final pageResult = result.pages[i];
                  final suffix = result.pages.length > 1 ? '_${i + 1}' : '';
                  final filePath =
                      '${tempDir.path}/${sanitizedName}$suffix.$ext';

                  if (config.format == PdfExportFormat.jpg) {
                    // Decode PNG bytes → re-encode as JPEG
                    final codec = await ui.instantiateImageCodec(
                      pageResult.bytes,
                    );
                    final frame = await codec.getNextFrame();
                    final image = frame.image;
                    final byteData = await image.toByteData(
                      format: ui.ImageByteFormat.png,
                    );
                    image.dispose();
                    codec.dispose();
                    if (byteData != null) {
                      await File(
                        filePath,
                      ).writeAsBytes(byteData.buffer.asUint8List());
                      filePaths.add(filePath);
                    }
                  } else {
                    // PNG — already in PNG format
                    await File(filePath).writeAsBytes(pageResult.bytes);
                    filePaths.add(filePath);
                  }
                }

                if (!mounted) return;
                _exportProgressSetter = null;
                messenger.hideCurrentSnackBar();

                // Share all images
                if (filePaths.isNotEmpty) {
                  try {
                    const channel = MethodChannel(
                      'com.flueraengine.fluera_engine/share',
                    );
                    if (filePaths.length == 1) {
                      await channel.invokeMethod('shareFile', {
                        'filePath': filePaths.first,
                        'mimeType': mimeType,
                        'subject': exportName,
                      });
                    } else {
                      await channel.invokeMethod('shareFiles', {
                        'filePaths': filePaths,
                        'mimeType': mimeType,
                        'subject': exportName,
                      });
                    }
                  } catch (_) {
                    if (mounted) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            '${ext.toUpperCase()} saved: ${filePaths.length} ${filePaths.length == 1 ? "image" : "images"}',
                          ),
                          action: SnackBarAction(label: 'OK', onPressed: () {}),
                        ),
                      );
                    }
                  }
                }

                if (!mounted) return;
                ExportSuccessOverlay.show(
                  context,
                  format: config.format,
                  fileName: '$sanitizedName.${config.format.extension}',
                );
                return;
              }

              // ─── SVG FORMAT EXPORT ─────────────────────────────
              if (config.format == PdfExportFormat.svg) {
                final tempDir = await getSafeTempDirectory();
                if (tempDir == null) return; // Web: no filesystem
                final filePaths = <String>[];

                for (int i = 0; i < result.pages.length; i++) {
                  final pageResult = result.pages[i];
                  final pw = pageResult.pixelSize.width.toInt();
                  final ph = pageResult.pixelSize.height.toInt();
                  final suffix = result.pages.length > 1 ? '_${i + 1}' : '';
                  final filePath =
                      '${tempDir.path}/${sanitizedName}$suffix.svg';

                  final base64Png = base64Encode(pageResult.bytes);
                  final svg = '''<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="$pw" height="$ph" viewBox="0 0 $pw $ph">
  <image width="$pw" height="$ph" href="data:image/png;base64,$base64Png"/>
</svg>''';
                  await File(filePath).writeAsString(svg);
                  filePaths.add(filePath);
                }

                if (!mounted) return;
                _exportProgressSetter = null;
                messenger.hideCurrentSnackBar();

                if (filePaths.isNotEmpty) {
                  try {
                    const channel = MethodChannel(
                      'com.flueraengine.fluera_engine/share',
                    );
                    if (filePaths.length == 1) {
                      await channel.invokeMethod('shareFile', {
                        'filePath': filePaths.first,
                        'mimeType': 'image/svg+xml',
                        'subject': exportName,
                      });
                    } else {
                      await channel.invokeMethod('shareFiles', {
                        'filePaths': filePaths,
                        'mimeType': 'image/svg+xml',
                        'subject': exportName,
                      });
                    }
                  } catch (_) {
                    if (mounted) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            'SVG saved: ${filePaths.length} ${filePaths.length == 1 ? "image" : "images"}',
                          ),
                          action: SnackBarAction(label: 'OK', onPressed: () {}),
                        ),
                      );
                    }
                  }
                }

                if (!mounted) return;
                ExportSuccessOverlay.show(
                  context,
                  format: config.format,
                  fileName: '$sanitizedName.svg',
                );
                return;
              }

              // ─── PDF FORMAT EXPORT ─────────────────────────────────────
              // 4. Assemble final PDF with PdfExportWriter
              final writer = PdfExportWriter(
                enableCompression: config.enableCompression,
              );
              config.applyToWriter(writer);

              for (final pageResult in result.pages) {
                final pw = pageResult.pixelSize.width;
                final ph = pageResult.pixelSize.height;
                final pageW = pw / 3.0;
                final pageH = ph / 3.0;
                writer.beginPage(width: pageW, height: pageH);

                final codec = await ui.instantiateImageCodec(pageResult.bytes);
                final frame = await codec.getNextFrame();
                final image = frame.image;
                final byteData = await image.toByteData(
                  format: ui.ImageByteFormat.rawRgba,
                );
                image.dispose();
                codec.dispose();

                if (byteData != null) {
                  final rgbaBytes = byteData.buffer.asUint8List();
                  final xobj = writer.addRgbaXObject(
                    rgbaBytes,
                    pw.toInt(),
                    ph.toInt(),
                  );
                  writer.drawImageXObject(xobj, 0, 0, pageW, pageH);
                }
              }

              final pdfBytes = writer.finish(title: exportName);

              // 5. Save to temp directory
              final tempDir = await getSafeTempDirectory();
              if (tempDir == null) return; // Web: no filesystem
              final filePath = '${tempDir.path}/$sanitizedName.pdf';
              final file = File(filePath);
              await file.writeAsBytes(pdfBytes);

              if (!mounted) return;
              _exportProgressSetter = null;
              messenger.hideCurrentSnackBar();

              // 6. Share via native platform channel (zero deps)
              try {
                const channel = MethodChannel(
                  'com.flueraengine.fluera_engine/share',
                );
                await channel.invokeMethod('shareFile', {
                  'filePath': filePath,
                  'mimeType': 'application/pdf',
                  'subject': exportName,
                });
              } catch (_) {
                // Fallback: show success snackbar if native share unavailable
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('PDF saved: ${result.pages.length} pages'),
                      action: SnackBarAction(label: 'OK', onPressed: () {}),
                    ),
                  );
                }
              }

              if (!mounted) return;
              ExportSuccessOverlay.show(
                context,
                format: config.format,
                fileName: '$sanitizedName.pdf',
              );
            } catch (e) {
              _exportProgressSetter = null;
              if (!mounted) return;
              messenger.hideCurrentSnackBar();
              messenger.showSnackBar(
                SnackBar(
                  content: Text('Export failed: $e'),
                  backgroundColor: Colors.red.shade700,
                ),
              );
            }
          },
          // 🎨 Design Tab — Wire to part file extensions
          onPrototypePlay: _startPrototypePreview,
          onFlowLinkAdd: _addFlowLink,
          onAnimationTimeline: _showAnimationTimeline,
          onSmartAnimate: _enableSmartAnimate,
          onInspectToggle: _toggleInspectMode,
          isInspectActive: _isInspectModeActive,
          onCodeGen: _showCodeGenerator,
          onRedlineToggle: _toggleRedlineOverlay,
          isRedlineActive: _isRedlineActive,
          onBreakpointSelect: _showBreakpointPicker,
          onSmartSnapToggle: _toggleSmartSnap,
          isSmartSnapActive: _isSmartSnapEnabled,
          onDesignLint: _runDesignLint,
          onStyleSystem: _showStyleSystemPanel,
          onAccessibilityTree: _showAccessibilityTree,
          onImageAdjust: _showImageAdjustments,
          onImageFillMode: _setImageFillMode,
          onTokenExport: _exportTokensToFormat,
          cloudSyncState: _syncEngine?.state,
        );
      },
    );
  }
}
