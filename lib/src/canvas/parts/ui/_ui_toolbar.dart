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
        // _undoRedoVersion REMOVED: _UndoRedoGroup now subscribes internally
        // via undoRedoListenable, so only the undo/redo buttons rebuild.
        _toolController,
        _isRecordingNotifier,
      ]),
      builder: (context, child) {
        final activeLayer = _layerController.activeLayer;
        final elementCount = activeLayer?.elementCount ?? 0;

        // 🔄 canUndo/canRedo used as initial values only.
        // Live updates come from computeCanUndo/computeCanRedo inside _UndoRedoGroup.
        final canUndo =
            _layerController.canUndo ||
            (_knowledgeFlowController?.canUndo ?? false);
        final canRedo =
            _layerController.canRedo ||
            (_knowledgeFlowController?.canRedo ?? false);

        return RepaintBoundary(
          child: ProfessionalCanvasToolbar(
            cloudSyncState: _syncEngine?.state,
            state: ToolbarState(
              // ── Drawing ──────────────────────────────────────────────────────
              selectedPenType: _effectivePenType,
              selectedColor: _effectiveSelectedColor,
              selectedWidth: _effectiveWidth,
              selectedOpacity: _effectiveOpacity,
              selectedShapeType: _effectiveShapeType,
              strokeCount: elementCount,
              canUndo: canUndo,
              canRedo: canRedo,
              // ⚡ Scoped undo/redo rebuild — only _UndoRedoGroup rebuilds on history change
              undoRedoListenable: _undoRedoVersion,
              computeCanUndo:
                  () =>
                      _layerController.canUndo ||
                      (_knowledgeFlowController?.canUndo ?? false),
              computeCanRedo:
                  () =>
                      _layerController.canRedo ||
                      (_knowledgeFlowController?.canRedo ?? false),
              isEraserActive: _effectiveIsEraser,
              eraserRadius: _eraserTool.eraserRadius,
              eraseWholeStroke: _eraserTool.eraseWholeStroke,
              isLassoActive: _effectiveIsLasso,
              isDigitalTextActive: _effectiveIsDigitalText,
              isImagePickerActive: false,
              isRecordingActive: _isRecordingAudio,
              isPanModeActive: _effectiveIsPanMode,
              isStylusModeActive: _effectiveIsStylusMode,
              isRulerActive: _showRulers,
              isMinimapVisible: _showMinimap,
              isSectionActive: _isSectionActive,
              isDualPageMode: false,
              isPenToolActive: _toolController.isPenToolMode,
              isLatexActive: _toolController.isLatexMode,
              isImageEditingMode: false,
              // ── Brush presets ─────────────────────────────────────────────────
              brushPresets: BrushPreset.defaultPresets,
              selectedPresetId: _selectedPresetId,
              // ── Recording ───────────────────────────────────────────────────
              recordingDuration: _recordingDuration,
              recordingAmplitude:
                  VoiceRecordingExtension._liveAmplitudes.isNotEmpty
                      ? VoiceRecordingExtension._liveAmplitudes.last
                      : 0.0,
              recordingDurationNotifier: _recordingDurationNotifier,
              recordingAmplitudeNotifier: _recordingAmplitudeNotifier,
              // ── Canvas / Search ──────────────────────────────────────────────
              noteTitle: _noteTitle,
              isSearchActive: _showHandwritingSearch,
              isCanvasRotated: _canvasController.rotation != 0.0,
              isRotationLocked: _canvasController.rotationLocked,
              activeBranchName: _activeBranchName,
              // ── Shape recognition ────────────────────────────────────────────
              shapeRecognitionEnabled: _toolController.shapeRecognitionEnabled,
              shapeRecognitionSensitivityIndex:
                  _toolController.shapeRecognitionSensitivity.index,
              ghostSuggestionEnabled: _toolController.ghostSuggestionMode,
              // ── Excel / Tabular ──────────────────────────────────────────────
              isTabularActive: _toolController.isTabularMode,
              hasTabularSelection: _tabularTool.hasSelection,
              hasRangeSelection: _tabularTool.hasRangeSelection,
              hasFrozenRow: _hasFrozenRow(),
              selectedCellRef:
                  _tabularTool.cellRefLabel.isEmpty
                      ? null
                      : _tabularTool.cellRefLabel,
              selectedCellValue: _getSelectedCellDisplayValue(),
              selectedCellFormat: _getSelectedCellFormat(),
              // ── PDF ──────────────────────────────────────────────────────────
              isPdfActive: _pdfPainters.isNotEmpty,
              pdfDocument: _activePdfDocument,
              pdfDocuments: _findAllPdfDocuments(),
              pdfAnnotationController: _pdfAnnotationController,
              pdfSearchController: _pdfSearchController,
              pdfCommandHistory: null,
              pdfSelectedPageIndex: _pdfSelectedPageIndex,
              showPdfPageNumbers: _showPdfPageNumbers,
              // ── Design ───────────────────────────────────────────────────────
              isInspectActive: _isInspectModeActive,
              isRedlineActive: _isRedlineActive,
              isSmartSnapActive: _isSmartSnapEnabled,
              // ── Ghost Map ──────────────────────────────────────────────────────
              isGhostMapActive: _ghostMapController.isActive,
              ghostMapGapCount: _ghostMapController.result?.totalMissing ?? 0,
              // ── Step Gate System (A15) ──────────────────────────────────────────
              recallGateType: _stepGateController.evaluateGate(
                LearningStep.step2Recall, context: _buildZoneContext()).type.index,
              socraticGateType: _stepGateController.evaluateGate(
                LearningStep.step3Socratic, context: _buildZoneContext()).type.index,
              ghostMapGateType: _stepGateController.evaluateGate(
                LearningStep.step4GhostMap, context: _buildZoneContext()).type.index,
              fogOfWarGateType: _stepGateController.evaluateGate(
                LearningStep.step10FogOfWar, context: _buildZoneContext()).type.index,
              crossZoneBridgeGateType: _stepGateController.evaluateGate(
                LearningStep.step9CrossDomain, context: _buildZoneContext()).type.index,
              crossZoneBridgeCount: crossZoneBridgeCount,
              isCrossZoneBridgeLoading: isCrossZoneBridgeLoading,
              suggestedStepIndex: _stepGateController.suggestedNextStep(
                context: _buildZoneContext()).index,
            ),
            callbacks: ToolbarCallbacks(
              // ── Drawing — required ───────────────────────────────────────────
              onPenTypeChanged: (type) {
                _toolController.setPenType(type);
                _toolController.resetToDrawingMode();
                _digitalTextTool.deselectElement();
                setState(() {});
              },
              onColorChanged: (color) {
                _toolController.setColor(color);
                EngineScope.current.styleCoherenceEngine.markManualOverride(
                  _consciousToolName(),
                );
                setState(() {});
              },
              onWidthChanged: (width) {
                _toolController.setStrokeWidth(width);
                EngineScope.current.styleCoherenceEngine.markManualOverride(
                  _consciousToolName(),
                );
                setState(() {});
              },
              onOpacityChanged: (opacity) {
                _toolController.setOpacity(opacity);
                EngineScope.current.styleCoherenceEngine.markManualOverride(
                  _consciousToolName(),
                );
                setState(() {});
              },
              onShapeTypeChanged: (type) {
                _toolController.setShapeType(type);
                if (type != ShapeType.freehand) {
                  _toolController.setEraserMode(false);
                  if (_toolController.isLassoActive) {
                    _toolController.toggleLassoMode();
                  }
                  if (_toolController.isDigitalTextActive) {
                    _toolController.toggleDigitalTextMode();
                  }
                  _digitalTextTool.deselectElement();
                }
                setState(() {});
              },
              onUndo: () {
                // 🐛 FIX: Layer controller (strokes) takes priority over
                // KnowledgeFlow connections. Previously KF was checked first,
                // but cluster rebuilds after each undo push entries into the
                // KF undo stack, causing it to "steal" subsequent undos.
                if (_layerController.canUndo) {
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
                  final undoStrokeCount =
                      _layerController.activeLayer?.strokes.length ?? 0;
                  final undoStrokeId =
                      undoStrokeCount > 0
                          ? _layerController.activeLayer?.strokes.last.id
                          : null;
                  _layerController.undo();
                  _undoRedoVersion.value++;
                  if (lastStrokeId != null && _syncRecordingBuilder != null) {
                    final strokesAfter =
                        _layerController.activeLayer?.strokes.length ?? 0;
                    if (strokesAfter < strokesBefore) {
                      _syncRecordingBuilder!.removeStrokeById(lastStrokeId);
                    }
                  }
                  if (undoStrokeId != null) {
                    final strokesAfterUndo =
                        _layerController.activeLayer?.strokes.length ?? 0;
                    if (strokesAfterUndo < undoStrokeCount) {
                      HandwritingIndexService.instance.removeStroke(
                        _canvasId,
                        undoStrokeId,
                      );
                    }
                  }
                  return;
                }
                // Fallback: undo KnowledgeFlow connection changes
                if (_knowledgeFlowController != null &&
                    _knowledgeFlowController!.canUndo) {
                  _knowledgeFlowController!.undo();
                  _undoRedoVersion.value++;
                  HapticFeedback.selectionClick();
                }
              },
              onRedo: () {
                // 🐛 FIX: Layer controller takes priority (same as undo above)
                if (_layerController.canRedo) {
                  _layerController.redo();
                  _undoRedoVersion.value++;
                  return;
                }
                // Fallback: redo KnowledgeFlow connection changes
                if (_knowledgeFlowController != null &&
                    _knowledgeFlowController!.canRedo) {
                  _knowledgeFlowController!.redo();
                  _undoRedoVersion.value++;
                  HapticFeedback.selectionClick();
                }
              },
              onClear: _clear,
              onSettings: _showSettings,
              onLayersPressed: () {
                _layerPanelKey.currentState?.togglePanel();
              },
              // ── Eraser ──────────────────────────────────────────────────────
              onEraserToggle: () {
                _toolController.toggleEraser();
                if (_effectiveIsEraser) {
                  _digitalTextTool.deselectElement();
                  _toolSystemBridge?.selectTool('eraser');
                } else {
                  _eraserCursorPosition = null;
                }
                setState(() {});
              },
              onEraserRadiusChanged: (radius) {
                _eraserTool.eraserRadius = radius;
                setState(() {});
              },
              onEraseWholeStrokeChanged: (value) {
                _eraserTool.eraseWholeStroke = value;
                setState(() {});
                HapticFeedback.selectionClick();
              },
              // ── Tool toggles ────────────────────────────────────────────────
              onLassoToggle: () {
                _toolController.toggleLassoMode();
                if (_toolController.isLassoActive) {
                  _digitalTextTool.deselectElement();
                  _eraserCursorPosition = null;
                  _toolSystemBridge?.selectTool('lasso');
                }
                setState(() {});
              },
              onDigitalTextToggle: () {
                _toolController.toggleDigitalTextMode();
                if (!_toolController.isDigitalTextActive) {
                  _digitalTextTool.deselectElement();
                }
                setState(() {});
              },
              onPanModeToggle: () {
                _toolController.togglePanMode();
                if (_toolController.isPanMode) {
                  _digitalTextTool.deselectElement();
                }
                setState(() {});
                _gestureRebuildNotifier.value++;
              },
              onStylusModeToggle: () {
                _toolController.toggleStylusMode();
                setState(() {});
                _gestureRebuildNotifier.value++;
              },
              onRulerToggle: () {
                _showRulers = !_showRulers;
                setState(() {});
                HapticFeedback.lightImpact();
              },
              onMinimapToggle: () {
                _showMinimap = !_showMinimap;
                setState(() {});
                HapticFeedback.lightImpact();
              },
              onSectionToggle: () {
                _isSectionActive = !_isSectionActive;
                setState(() {});
                if (_isSectionActive) {
                  _toolController.resetToDrawingMode();
                  _digitalTextTool.deselectElement();
                  _lassoTool.clearSelection();
                  _eraserCursorPosition = null;
                  // Auto-focus last section → handles appear immediately
                  SectionNode? lastSection;
                  for (final layer in _layerController.sceneGraph.layers) {
                    for (final child in layer.children) {
                      if (child is SectionNode && child.isVisible) {
                        lastSection = child;
                      }
                    }
                  }
                  _focusedSectionNode = lastSection;
                } else {
                  _focusedSectionNode = null;
                }
                HapticFeedback.selectionClick();
              },
              onPenToolToggle: () {
                final wasActive = _toolController.isPenToolMode;
                _toolController.togglePenTool();
                if (_toolController.isPenToolMode) {
                  _digitalTextTool.deselectElement();
                  _lassoTool.clearSelection();
                  _imageTool.clearSelection();
                  _eraserCursorPosition = null;
                  _penTool.strokeColor = _effectiveColor;
                  _penTool.strokeWidth = _effectiveWidth;
                  _penTool.isDarkMode =
                      Theme.of(context).brightness == Brightness.dark;
                  _penTool.snapPosition =
                      _showRulers && _rulerGuideSystem.snapEnabled
                          ? (pos) => _rulerGuideSystem.snapPoint(
                            pos,
                            _canvasController.scale,
                          )
                          : null;
                } else if (wasActive) {
                  _penTool.onDeactivate(_penToolContext);
                }
                setState(() {});
              },
              // 🚀 v1 DEFER: LaTeX Recognition gated
              onLatexToggle: V1FeatureGate.latexRecognition ? () {
                _toolController.toggleLatexMode();
                if (_toolController.isLatexMode) {
                  _digitalTextTool.deselectElement();
                  _lassoTool.clearSelection();
                  _eraserCursorPosition = null;
                  _showLatexEditorSheet();
                }
                setState(() {});
              } : null,
              // 🚀 v1 DEFER: Tabular gated
              onTabularToggle: V1FeatureGate.tabular ? () {
                _toolController.toggleTabularMode();
                if (_toolController.isTabularMode) {
                  _digitalTextTool.deselectElement();
                  _lassoTool.clearSelection();
                  _eraserCursorPosition = null;
                  _addTabularNode();
                }
                setState(() {});
              } : null,
              // ── Canvas controls ─────────────────────────────────────────────
              onBrushSettingsPressed: (anchorRect) {
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
                    _drawingHandler.stabilizerLevel =
                        newSettings.stabilizerLevel;
                    EngineScope.current.drawingModule?.brushSettingsService
                        .updateSettings(newSettings);
                  },
                );
              },
              onExportPressed: _enterExportMode,
              onNoteTitleChanged: (newTitle) {
                _noteTitle = newTitle;
                setState(() {});
                _autoSaveCanvas();
              },
              onPresetSelected: (preset) {
                _applyBrushPreset(preset);
              },
              onImagePickerPressed: () {
                pickAndAddImage();
              },
              onImageEditorPressed: null,
              onRecordingPressed: () {
                if (_isRecordingAudio) {
                  _stopAudioRecording();
                } else {
                  _showRecordingChoiceDialog();
                }
              },
              onViewRecordingsPressed: () {
                _showSavedRecordingsDialog();
              },
              // 🚀 v1 DEFER: Multiview gated
              onAdvancedSplitPressed: V1FeatureGate.multiview ? () {
                _launchAdvancedSplitView();
              } : null,
              // 🚀 v1 DEFER: Time Travel gated
              onTimeTravelPressed:
                  (V1FeatureGate.timeTravel && _subscriptionTier == FlueraSubscriptionTier.pro)
                      ? _enterTimeTravelMode
                      : null,
              // 🚀 v1 DEFER: Branch Explorer (part of Time Travel)
              onBranchExplorerPressed:
                  (V1FeatureGate.timeTravel && _subscriptionTier == FlueraSubscriptionTier.pro)
                      ? _openBranchExplorer
                      : null,
              onRecallModePressed:
                  !_recallModeController.isActive
                      ? showRecallZoneSelector
                      : null,
              // 🗺️ P4-28: 3-way toggle: dismiss / reactivate / trigger
              onGhostMapPressed: _ghostMapController.isActive
                  ? dismissGhostMap
                  : _ghostMapController.canReactivate
                      ? () {
                          _ghostMapController.reactivate();
                          _ghostMapAnimController?.repeat();
                          setState(() {});
                          HapticFeedback.mediumImpact();
                        }
                      : triggerGhostMap,
              onFogOfWarPressed:
                  !_fogOfWarController.isActive
                      ? showFogOfWarSetup
                      : dismissFogOfWar,
              onSocraticPressed:
                  !_socraticController.isActive
                      ? showSocraticSetup
                      : dismissSocraticMode,
              // 🚀 v1 DEFER: Cross-Zone Bridges gated
              onCrossZoneBridgesPressed: (V1FeatureGate.crossZoneBridges && canActivateCrossZoneBridges)
                  ? requestCrossZoneBridgeSuggestions
                  : null,
              onSearchPressed: () {
                setState(() {
                  _showHandwritingSearch = !_showHandwritingSearch;
                  if (!_showHandwritingSearch) {
                    _hwSearchResults = [];
                    _hwSearchActiveIndex = 0;
                  }
                });
              },
              onPaperTypePressed: _showPaperTypePicker,
              onReadingLevelPressed: () {
                final allText = _digitalTextElements
                    .map((e) => e.plainText)
                    .where((t) => t.trim().isNotEmpty)
                    .join('. ');
                if (allText.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'No text found on canvas — write something first!',
                      ),
                      duration: Duration(seconds: 2),
                    ),
                  );
                  return;
                }
                ReadingLevelSheet.show(context, allText);
              },
              onResetRotation: () {
                _canvasController.resetRotation();
                setState(() {});
              },
              onToggleRotationLock: () {
                _canvasController.rotationLocked =
                    !_canvasController.rotationLocked;
                setState(() {});
              },
              // ── Shape recognition ────────────────────────────────────────────
              onShapeRecognitionToggle: () {
                _toolController.toggleShapeRecognition();
                setState(() {});
              },
              onShapeRecognitionSensitivityCycle: () {
                _toolController.cycleShapeRecognitionSensitivity();
                setState(() {});
              },
              onGhostSuggestionToggle: () {
                _toolController.toggleGhostSuggestionMode();
                setState(() {});
              },
              // ── PDF ──────────────────────────────────────────────────────────
              onPdfImportPressed: () {
                pickAndAddPdf();
              },
              onPdfCreateBlankPressed: () {
                _showBackgroundChooser(context);
              },
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
                      ? () => showDeletePdfConfirmation(
                        context,
                        _activePdfDocumentId!,
                      )
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
                final pageNode = doc.pageAt(pageIndex);
                if (pageNode == null) return;
                final pageRect = doc.pageRectFor(pageNode);
                final pageCenter = pageRect.center;
                final viewportSize = MediaQuery.of(context).size;
                final scale = _canvasController.scale;
                _canvasController.animateOffsetTo(
                  Offset(
                    viewportSize.width / 2 - pageCenter.dx * scale,
                    viewportSize.height / 2 - pageCenter.dy * scale,
                  ),
                );
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
                final scaleX = (viewportSize.width - 40) / pageRect.width;
                final scaleY = (viewportSize.height - 80) / pageRect.height;
                final targetScale = scaleX < scaleY ? scaleX : scaleY;
                final pageCenter = pageRect.center;
                _canvasController.animateToTransform(
                  targetOffset: Offset(
                    viewportSize.width / 2 - pageCenter.dx * targetScale,
                    viewportSize.height / 2 - pageCenter.dy * targetScale,
                  ),
                  targetScale: targetScale,
                );
              },
              onPdfWatermarkToggle: () {
                final doc = _activePdfDocument;
                if (doc == null) return;
                final current = doc.documentModel.watermarkText;
                doc.documentModel = doc.documentModel.copyWith(
                  watermarkText: current != null ? null : 'DRAFT',
                  clearWatermarkText: current != null,
                );
                _realtimeEngine?.broadcastPdfUpdated(
                  documentId: doc.id.toString(),
                  subAction: 'watermarkChanged',
                  data:
                      current != null
                          ? {'clear': true}
                          : {'watermarkText': 'DRAFT'},
                );
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
                              onTap: () => Navigator.pop(sheetCtx),
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
                              padding: const EdgeInsets.fromLTRB(
                                24,
                                12,
                                24,
                                16,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
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
                                    physics:
                                        const NeverScrollableScrollPhysics(),
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
                                              setSheetState(
                                                () => selected = bg,
                                              );
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
                                          () =>
                                              Navigator.pop(sheetCtx, selected),
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
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
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
                } catch (e) {}
              },
              onPdfPresentation: () async {
                final doc = _activePdfDocument;
                if (doc == null) return;
                FlueraPdfProvider? provider;
                if (_activePdfDocumentId != null) {
                  provider = _pdfProviders[_activePdfDocumentId!];
                }
                provider ??= _pdfProviders[doc.id.value];
                if (provider == null && _pdfProviders.isNotEmpty) {
                  provider = _pdfProviders.values.first;
                }
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
                    final img = await provider.renderPage(
                      pageIndex: page.pageModel.pageIndex,
                      scale: fitScale,
                      targetSize: targetSize,
                    );
                    if (img != null) {
                      page.cachedImage?.dispose();
                      page.cachedImage = img;
                      page.cachedScale = fitScale;
                    } else {
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
                    }
                  }
                }
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
              onPdfLayoutModeChanged: (mode) {
                final doc = _activePdfDocument;
                if (doc == null) return;
                doc.documentModel = doc.documentModel.copyWith(
                  layoutMode: mode,
                );
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
                _pdfLayoutVersion++;
                bool didTranslate = false;
                for (final layer in _layerController.sceneGraph.layers) {
                  for (final child in layer.children) {
                    if (child is PdfDocumentNode &&
                        child.pendingStrokeTranslations.isNotEmpty) {
                      final translations =
                          child.pendingStrokeTranslations.toList();
                      child.pendingStrokeTranslations.clear();
                      for (final tx in translations) {
                        if (tx.annotationIds.isNotEmpty) {
                          final idSet = Set<String>.of(tx.annotationIds);
                          for (final l in _layerController.layers) {
                            for (final strokeNode in l.node.strokeNodes) {
                              if (idSet.contains(strokeNode.stroke.id)) {
                                final old = strokeNode.stroke;
                                strokeNode.stroke = old.copyWith(
                                  points:
                                      old.points
                                          .map(
                                            (p) => p.copyWith(
                                              position: p.position + tx.delta,
                                            ),
                                          )
                                          .toList(),
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
                if (didTranslate) DrawingPainter.invalidateAllTiles();
                for (final layer in _layerController.sceneGraph.layers) {
                  for (final child in layer.children) {
                    if (child is PdfDocumentNode &&
                        child.pendingStrokeRotation != null) {
                      final rot = child.pendingStrokeRotation!;
                      child.pendingStrokeRotation = null;
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
                              strokeNode.stroke = old.copyWith(
                                points:
                                    old.points.map((p) {
                                      final dx = p.position.dx - cx;
                                      final dy = p.position.dy - cy;
                                      return p.copyWith(
                                        position: Offset(
                                          cx + dx * cosA - dy * sinA,
                                          cy + dx * sinA + dy * cosA,
                                        ),
                                      );
                                    }).toList(),
                              );
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
                int renderedCount = 0;
                messenger.showSnackBar(
                  SnackBar(
                    content: StatefulBuilder(
                      builder: (ctx, setSnackState) {
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
                  if (config.format == PdfExportFormat.jpg ||
                      config.format == PdfExportFormat.png) {
                    final tempDir = await getSafeTempDirectory();
                    if (tempDir == null) return;
                    final ext = config.format.extension;
                    final mimeType = config.format.mimeType;
                    final filePaths = <String>[];
                    for (int i = 0; i < result.pages.length; i++) {
                      final pageResult = result.pages[i];
                      final suffix = result.pages.length > 1 ? '_${i + 1}' : '';
                      final filePath =
                          '${tempDir.path}/${sanitizedName}$suffix.$ext';
                      if (config.format == PdfExportFormat.jpg) {
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
                        await File(filePath).writeAsBytes(pageResult.bytes);
                        filePaths.add(filePath);
                      }
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
                              action: SnackBarAction(
                                label: 'OK',
                                onPressed: () {},
                              ),
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
                  if (config.format == PdfExportFormat.svg) {
                    final tempDir = await getSafeTempDirectory();
                    if (tempDir == null) return;
                    final filePaths = <String>[];
                    for (int i = 0; i < result.pages.length; i++) {
                      final pageResult = result.pages[i];
                      final pw = pageResult.pixelSize.width.toInt();
                      final ph = pageResult.pixelSize.height.toInt();
                      final suffix = result.pages.length > 1 ? '_${i + 1}' : '';
                      final filePath =
                          '${tempDir.path}/${sanitizedName}$suffix.svg';
                      final base64Png = base64Encode(pageResult.bytes);
                      final svg =
                          '<?xml version="1.0" encoding="UTF-8"?>\n'
                          '<svg xmlns="http://www.w3.org/2000/svg" '
                          'xmlns:xlink="http://www.w3.org/1999/xlink" '
                          'width="$pw" height="$ph" viewBox="0 0 $pw $ph">\n'
                          '  <image width="$pw" height="$ph" '
                          'href="data:image/png;base64,$base64Png"/>\n'
                          '</svg>';
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
                              action: SnackBarAction(
                                label: 'OK',
                                onPressed: () {},
                              ),
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
                    final codec = await ui.instantiateImageCodec(
                      pageResult.bytes,
                    );
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
                  final tempDir = await getSafeTempDirectory();
                  if (tempDir == null) return;
                  final filePath = '${tempDir.path}/$sanitizedName.pdf';
                  await File(filePath).writeAsBytes(pdfBytes);
                  if (!mounted) return;
                  _exportProgressSetter = null;
                  messenger.hideCurrentSnackBar();
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
                    if (mounted) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            'PDF saved: ${result.pages.length} pages',
                          ),
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
              // ── Excel / Tabular ──────────────────────────────────────────────
              onTabularCreate: (columns, rows) {
                _digitalTextTool.deselectElement();
                _lassoTool.clearSelection();
                _eraserCursorPosition = null;
                _addTabularNode(columns: columns, rows: rows);
              },
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
                final latex = _tabularTool.selectionToLatex(
                  includeHeaders: true,
                );
                if (latex == null) return;
                HapticFeedback.lightImpact();
                LatexCodeDialog.show(context, latex);
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
              onToggleFreezeRow: _toggleFreezeRow,
              // ── Design ───────────────────────────────────────────────────────
              onPrototypePlay: _startPrototypePreview,
              onFlowLinkAdd: _addFlowLink,
              onAnimationTimeline: _showAnimationTimeline,
              onSmartAnimate: _enableSmartAnimate,
              onInspectToggle: _toggleInspectMode,
              onCodeGen: _showCodeGenerator,
              onRedlineToggle: _toggleRedlineOverlay,
              onBreakpointSelect: _showBreakpointPicker,
              onSmartSnapToggle: _toggleSmartSnap,
              onDesignLint: _runDesignLint,
              onStyleSystem: _showStyleSystemPanel,
              onAccessibilityTree: _showAccessibilityTree,
              onImageAdjust: _showImageAdjustments,
              onImageFillMode: _setImageFillMode,
              onTokenExport: _exportTokensToFormat,
              // ── Symbol insert ────────────────────────────────────────────────
              onInsertText: (symbol) {
                final overlayState = _inlineOverlayKey.currentState;
                if (overlayState != null && overlayState.mounted) {
                  overlayState.insertText(symbol);
                  return;
                }
                Clipboard.setData(ClipboardData(text: symbol));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('"$symbol" copied — paste it where needed'),
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                    width: 260,
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
