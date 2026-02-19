part of '../../nebula_canvas_screen.dart';

/// 🛠️ Toolbar — extracted from _NebulaCanvasScreenState._buildImpl
extension NebulaCanvasToolbarUI on _NebulaCanvasScreenState {
  /// Builds the professional canvas toolbar.
  /// Hidden during multiview, multi-page edit, time travel, and placement mode.
  Widget _buildToolbar(BuildContext context) {
    // Professional Toolbar (nascosta nel multiview, multi-page edit, time travel, e placement mode)
    if (widget.hideToolbar ||
        _isMultiPageEditMode ||
        _isTimeTravelMode ||
        _isRecoveryPlacementMode) {
      return const SizedBox.shrink();
    }

    return ListenableBuilder(
      listenable: _layerController,
      builder: (context, child) {
        final activeLayer = _layerController.activeLayer;
        final elementCount = activeLayer?.elementCount ?? 0;

        // 🔄 Phase 2: Use LayerController undo/redo (delta-based)
        final canUndo =
            _imageInEditMode != null
                ? _imageEditingStrokes.isNotEmpty
                : _layerController.canUndo;
        final canRedo =
            _imageInEditMode != null
                ? _imageEditingUndoStack.isNotEmpty
                : _layerController.canRedo;

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
          isImageEditingMode:
              _imageInEditMode !=
              null, // 🎨 Modalità editing interno (non da infinite canvas)
          noteTitle: _noteTitle, // 🆕 Pass note title
          // 🎨 Preset-based brush selection
          brushPresets: _brushPresetManager.allPresets,
          selectedPresetId: _selectedPresetId,
          onPresetSelected: (preset) {
            setState(() {
              _selectedPresetId = preset.id;
              _brushSettings = preset.settings;
            });
            _toolController.setPenType(preset.penType);
            _toolController.setStrokeWidth(preset.baseWidth);
            _toolController.setColor(preset.color);
            _toolController.resetToDrawingMode();
            _digitalTextTool.deselectElement();
            BrushSettingsService.instance.updateSettings(preset.settings);
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
                setState(() {
                  _brushSettings = newSettings;
                });
                // 🎯 Keep stabilizer in sync with settings
                _drawingHandler.stabilizerLevel = newSettings.stabilizerLevel;
                BrushSettingsService.instance.updateSettings(newSettings);
              },
            );
          },
          onExportPressed: _enterExportMode, // 📤 Export canvas
          onNoteTitleChanged: (newTitle) {
            // 🆕 Callback per rinominare nota
            setState(() {
              _noteTitle = newTitle;
            });
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
            setState(() {}); // Trigger rebuild
          },
          eraserRadius: _eraserTool.eraserRadius,
          onEraserRadiusChanged: (radius) {
            setState(() {
              _eraserTool.eraserRadius = radius;
            });
          },
          eraseWholeStroke: _eraserTool.eraseWholeStroke,
          onEraseWholeStrokeChanged: (value) {
            setState(() {
              _eraserTool.eraseWholeStroke = value;
            });
            HapticFeedback.selectionClick();
          },
          onLassoToggle: () {
            _toolController.toggleLassoMode();
            if (_toolController.isLassoActive) {
              _digitalTextTool.deselectElement();
              _eraserCursorPosition = null;
              _toolSystemBridge?.selectTool('lasso');
            }
            setState(() {}); // Trigger rebuild
          },
          onDigitalTextToggle: () {
            _toolController.toggleDigitalTextMode();
            if (_toolController.isDigitalTextActive) {
              _showDigitalTextDialog();
            } else {
              _digitalTextTool.deselectElement();
            }
            setState(() {}); // Trigger rebuild
          },
          onPanModeToggle: () {
            _toolController.togglePanMode();
            if (_toolController.isPanMode) {
              _digitalTextTool.deselectElement();
            }
            setState(() {}); // Trigger rebuild
          },
          onStylusModeToggle: () {
            _toolController.toggleStylusMode();
            setState(() {}); // Trigger rebuild
          },
          onRulerToggle: () {
            setState(() => _showRulers = !_showRulers);
            HapticFeedback.lightImpact();
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
            setState(() {}); // Trigger rebuild
          },
          onImagePickerPressed: () {
            // 🖼️ Open gallery and add image
            pickAndAddImage();
          },
          onImageEditorPressed:
              _imageInEditMode != null
                  ? () {
                    // 🎨 Apri editor avanzato per l'immagine in editing
                    final image = _loadedImages[_imageInEditMode!.imagePath];
                    if (image != null) {
                      _openImageEditor(_imageInEditMode!, image);
                    }
                  }
                  : null,
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
              (_subscriptionTier == NebulaSubscriptionTier.pro)
                  ? _enterTimeTravelMode
                  : null,
          // 🌿 Branch Explorer (solo Pro)
          onBranchExplorerPressed:
              (_subscriptionTier == NebulaSubscriptionTier.pro)
                  ? _openBranchExplorer
                  : null,
          activeBranchName: _activeBranchName,
          onMultiViewPressed: null, // ❌ Rimosso completamente
          onAdvancedSplitPressed: () {
            // 🚀 Launch new advanced split system
            _launchAdvancedSplitView();
          },
          onMultiViewModeSelected: (mode) {
            // 🔄 Launch multiview with specific mode
            switch (mode) {
              case 1:
                debugPrint("Multiview not available in SDK");
                break;
              case 2:
                debugPrint("Multiview not available in SDK");
                break;
              case 3:
                debugPrint("Multiview not available in SDK");
                break;
              case 4:
                debugPrint("Multiview not available in SDK");
                break;
            }
          },
          onPenTypeChanged: (type) {
            _toolController.setPenType(type);
            _toolController.resetToDrawingMode();
            _digitalTextTool.deselectElement();
            setState(() {}); // Trigger rebuild
          },
          onColorChanged: (color) {
            _toolController.setColor(color);
            setState(() {}); // Trigger rebuild
          },
          onWidthChanged: (width) {
            _toolController.setStrokeWidth(width);
            setState(() {}); // Trigger rebuild
          },
          onOpacityChanged: (opacity) {
            _toolController.setOpacity(opacity);
            setState(() {}); // Trigger rebuild
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
            setState(() {}); // Trigger rebuild
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
          // 📄 PDF active state — contextual tools
          isPdfActive: _pdfPainters.isNotEmpty,
          pdfDocument: _findFirstPdfDocument(),
          pdfAnnotationController: _pdfAnnotationController,
          pdfSearchController: _pdfSearchController,
          pdfSelectedPageIndex: 0,
          onPdfInsertBlankPage:
              _pdfPainters.isNotEmpty
                  ? () {
                    final doc = _findFirstPdfDocument();
                    if (doc != null) {
                      doc.insertBlankPage(
                        afterIndex: doc.documentModel.totalPages - 1,
                      );
                      setState(() {});
                      _autoSaveCanvas();
                    }
                  }
                  : null,
          onPdfDeletePage: (pageIndex) {
            final doc = _findFirstPdfDocument();
            if (doc != null && doc.documentModel.totalPages > 1) {
              doc.removePage(pageIndex);
              setState(() {});
              _autoSaveCanvas();
            }
          },
          onPdfExport: null, // TODO: wire to export annotated PDF
        );
      },
    );
  }
}
