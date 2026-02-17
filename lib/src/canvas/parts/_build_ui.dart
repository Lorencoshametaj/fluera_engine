part of '../nebula_canvas_screen.dart';

/// 📦 Build UI — extracted from _NebulaCanvasScreenState
extension on _NebulaCanvasScreenState {
  // ============================================================================
  // BUILD
  // ============================================================================

  Widget _buildImpl(BuildContext context) {
    // 🔄 Watch provider to rebuild on tool changes (e.g. from multiview toolbar)
    // Tool state managed by _toolController;

    // 🎨 Eagerly load brush presets (async, no-op if already loaded)
    if (!_presetsLoaded) {
      _brushPresetManager.load().then((_) {
        if (mounted) {
          _presetsLoaded = true;
          setState(() {});
        }
      });
    }

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        // ✒️ Delegate key events to pen tool when active
        if (_toolController.isPenToolMode) {
          final consumed = _penTool.handleKeyEvent(event, _penToolContext);
          if (consumed) {
            setState(() {});
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Stack(
            children: [
              // Main content: toolbar + canvas
              Column(
                children: [
                  // Professional Toolbar (nascosta nel multiview, multi-page edit, time travel, e placement mode)
                  if (!widget.hideToolbar &&
                      !_isMultiPageEditMode &&
                      !_isTimeTravelMode &&
                      !_isRecoveryPlacementMode)
                    ListenableBuilder(
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
                          isImagePickerActive:
                              false, // 🖼️ Sempre false (is not una mode toggle)
                          isRecordingActive: _isRecordingAudio,
                          isPanModeActive:
                              _effectiveIsPanMode, // 🖐️ Pan Mode - permette pan with a dito
                          isStylusModeActive:
                              _effectiveIsStylusMode, // 🖊️ Stylus mode
                          isRulerActive: _showRulers, // 📏 Ruler overlay
                          isPenToolActive:
                              _toolController
                                  .isPenToolMode, // ✒️ Vector Pen Tool
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
                            BrushSettingsService.instance.updateSettings(
                              preset.settings,
                            );
                          },
                          onUndo:
                              () =>
                                  _layerController
                                      .undo(), // 🔄 Phase 2: New undo system
                          onRedo:
                              () =>
                                  _layerController
                                      .redo(), // 🔄 Phase 2: New redo system
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
                                _drawingHandler.stabilizerLevel =
                                    newSettings.stabilizerLevel;
                                BrushSettingsService.instance.updateSettings(
                                  newSettings,
                                );
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
                                  Theme.of(context).brightness ==
                                  Brightness.dark;
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
                            // 🖼️ Apri galleria e aggiungi immagine
                            pickAndAddImage();
                          },
                          onImageEditorPressed:
                              _imageInEditMode != null
                                  ? () {
                                    // 🎨 Apri editor avanzato per l'immagine in editing
                                    final image =
                                        _loadedImages[_imageInEditMode!
                                            .imagePath];
                                    if (image != null) {
                                      _openImageEditor(
                                        _imageInEditMode!,
                                        image,
                                      );
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
                          onPdfPressed: () {
                            // 📄 Apri dialog per creare o aprire PDF
                            _showPdfOptionsDialog();
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
                            // 🚀 Lancia il nuovo sistema di split avanzato
                            _launchAdvancedSplitView();
                          },
                          onMultiViewModeSelected: (mode) {
                            // 🔄 Lancia multiview con mode specifica
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
                        );
                      },
                    ),

                  // Canvas Infinito con Zoom e Pan
                  Expanded(
                    key: _canvasAreaKey, // Key to track la size of the area
                    child: ClipRect(
                      // 🔒 ClipRect impedisce al canvas di invadere la toolbar
                      child: Stack(
                        children: [
                          // 🎨 LAYER 0: SFONDO VIEWPORT-LEVEL
                          // 🚀 repaint: controller → paint() su ogni pan/zoom frame
                          // ma isolato in RepaintBoundary → nessun cascade ai siblings
                          // Costo: ~10 drawPicture/frame (trascurabile)
                          RepaintBoundary(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: BackgroundPainter(
                                  paperType: _paperType,
                                  backgroundColor: _canvasBackgroundColor,
                                  controller: _canvasController,
                                ),
                                size: Size.infinite,
                              ),
                            ),
                          ),

                          // 🎨 LAYER 1: DISEGNI COMPLETATI (VIEWPORT-LEVEL)
                          // 🚀 repaint: controller → paint() su ogni pan/zoom frame
                          // 🚀 Costo per-frame: O(1) via StrokeCacheManager (drawPicture)
                          // 🚀 RepaintBoundary texture = viewport size (~20MB vs ~380MB)
                          ValueListenableBuilder<GeometricShape?>(
                            valueListenable: _currentShapeNotifier,
                            builder: (context, currentShape, _) {
                              return ListenableBuilder(
                                listenable: _layerController,
                                builder: (context, _) {
                                  return RepaintBoundary(
                                    child: IgnorePointer(
                                      child: CustomPaint(
                                        painter: DrawingPainter(
                                          completedStrokes: _cachedAllStrokes,
                                          completedShapes: _cachedAllShapes,
                                          currentShape: currentShape,
                                          canvasOffset:
                                              _canvasController.offset,
                                          canvasScale: _canvasController.scale,
                                          viewportSize:
                                              Size.zero, // unused in viewport mode
                                          enableClipping:
                                              _isImageEditFromInfiniteCanvas,
                                          canvasSize: _canvasSize,
                                          spatialIndex:
                                              _layerController.spatialIndex,
                                          devicePixelRatio:
                                              MediaQuery.of(
                                                context,
                                              ).devicePixelRatio,
                                          adaptiveConfig: _renderingConfig,
                                          layers: _layerController.layers,
                                          eraserPreviewIds: _eraserPreviewIds,
                                          controller:
                                              _canvasController, // 🚀 viewport-level mode
                                        ),
                                        size: Size.infinite,
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                          // Layer 1: Canvas con gesture e disegni (tutto segue zoom/pan)
                          // 🚀 INFINITE CANVAS: use OverflowBox to draw beyond screen limits
                          LayoutBuilder(
                            builder: (context, constraints) {
                              // 📐 Dimensioni viewport per culling ottimizzato
                              final viewportSize = Size(
                                constraints.maxWidth,
                                constraints.maxHeight,
                              );

                              return IgnorePointer(
                                // 🔮 Blocca gesture canvas durante placement mode
                                ignoring: _isRecoveryPlacementMode,
                                child: InfiniteCanvasGestureDetector(
                                  controller: _canvasController,
                                  // 📐 In multi-page edit mode: blocca disegno
                                  onDrawStart:
                                      _isMultiPageEditMode
                                          ? null
                                          : _onDrawStart,
                                  onDrawUpdate:
                                      _isMultiPageEditMode
                                          ? null
                                          : _onDrawUpdate,
                                  onDrawEnd:
                                      _isMultiPageEditMode ? null : _onDrawEnd,
                                  onDrawCancel:
                                      _isMultiPageEditMode
                                          ? null
                                          : _onDrawCancel,
                                  onLongPress:
                                      _isMultiPageEditMode
                                          ? null
                                          : _onLongPress,
                                  enableSingleFingerPan:
                                      _effectiveIsPanMode ||
                                      _isMultiPageEditMode, // 🖐️ Pan with a dito quando attivo O in multi-page edit
                                  isStylusModeEnabled:
                                      _isMultiPageEditMode
                                          ? false
                                          : _effectiveIsStylusMode, // 🖊️ Disable stylus mode in multi-page edit
                                  blockPanZoom:
                                      _digitalTextTool.isResizing ||
                                      _digitalTextTool.isDragging ||
                                      _imageTool.isResizing ||
                                      _imageTool
                                          .isDragging, // 🔒 Blocca pan solo when interagisce con testo/immagini
                                  // 🚀 PERF FIX: Content builders OUTSIDE AnimatedBuilder.
                                  // Previously they were nested INSIDE, causing full
                                  // widget subtree rebuilds on every pan/zoom frame.
                                  // Now: content rebuilds only on stroke/shape changes.
                                  child: ValueListenableBuilder<
                                    GeometricShape?
                                  >(
                                    valueListenable: _currentShapeNotifier,
                                    builder: (context, currentShape, _) {
                                      return ListenableBuilder(
                                        listenable: _layerController,
                                        builder: (context, _) {
                                          // 🚀 AnimatedBuilder ONLY rebuilds Transform.
                                          // The child (Stack of painters) is cached by Flutter
                                          // and reused on every pan/zoom frame → zero rebuild.
                                          return AnimatedBuilder(
                                            animation: _canvasController,
                                            builder: (context, child) {
                                              // 🚀 OverflowBox permette al contenuto di superare i limiti del parent
                                              return OverflowBox(
                                                minWidth: 0,
                                                maxWidth: double.infinity,
                                                minHeight: 0,
                                                maxHeight: double.infinity,
                                                alignment: Alignment.topLeft,
                                                child: Transform(
                                                  transform:
                                                      Matrix4.identity()
                                                        ..translate(
                                                          _canvasController
                                                              .offset
                                                              .dx,
                                                          _canvasController
                                                              .offset
                                                              .dy,
                                                        )
                                                        ..scale(
                                                          _canvasController
                                                              .scale,
                                                        ),
                                                  child: child,
                                                ),
                                              );
                                            },
                                            // 🚀 CACHED CHILD: rebuilt only by ListenableBuilder
                                            // (stroke/shape changes), NOT by AnimatedBuilder (pan/zoom).
                                            // ⚠️ NO outer RepaintBoundary! Ognuno dei layer interni ha il suo.
                                            // Un RepaintBoundary qui creerebbe una layer texture di 5000×5000
                                            // (~720MB a dpr 2.75) that the GPU deve compositare every frame.
                                            child: SizedBox(
                                              // 🎨 Canvas: dynamic dimensions
                                              width: _canvasSize.width,
                                              height: _canvasSize.height,
                                              child: Stack(
                                                children: [
                                                  // ✚ LAYER 0: INDICATORE ORIGINE (0,0)
                                                  // Crosshair sottile al centro of the canvas
                                                  if (!_isImageEditFromInfiniteCanvas)
                                                    Positioned.fill(
                                                      child: CustomPaint(
                                                        painter:
                                                            OriginIndicatorPainter(
                                                              scale:
                                                                  _canvasController
                                                                      .scale,
                                                            ),
                                                      ),
                                                    ),

                                                  // 🖼️ LAYER 1.5: IMMAGINE DI SFONDO (se presente)
                                                  if (_backgroundImage != null)
                                                    Positioned.fill(
                                                      child: CustomPaint(
                                                        painter: BackgroundImagePainter(
                                                          image:
                                                              _backgroundImage!,
                                                          isImageEditMode:
                                                              _isImageEditFromInfiniteCanvas,
                                                          viewportSize:
                                                              viewportSize,
                                                        ),
                                                        size: _canvasSize,
                                                      ),
                                                    ),

                                                  // 🖼️ LAYER 3: IMMAGINI (ridisegna quando cambiano immagini)
                                                  RepaintBoundary(
                                                    child: CustomPaint(
                                                      painter: ImagePainter(
                                                        images: List<
                                                          ImageElement
                                                        >.from(_imageElements),
                                                        loadedImages:
                                                            _loadedImages,
                                                        selectedImage:
                                                            _imageTool
                                                                .selectedImage,
                                                        imageTool: _imageTool,
                                                        imageInEditMode:
                                                            _imageInEditMode,
                                                        imageEditingStrokes:
                                                            _imageEditingStrokes,
                                                        currentEditingStroke:
                                                            _currentEditingStrokeNotifier
                                                                .value,
                                                        loadingPulse:
                                                            _loadingPulseValue,
                                                      ),
                                                      size: _canvasSize,
                                                    ),
                                                  ),

                                                  // 🚀 LAYER 4 (Top): TRATTO CORRENTE (ZERO REBUILD!)
                                                  // Deve essere sopra le immagini per essere visibile durante l'editing!
                                                  RepaintBoundary(
                                                    child: CustomPaint(
                                                      painter: CurrentStrokePainter(
                                                        strokeNotifier:
                                                            _currentStrokeNotifier,
                                                        penType:
                                                            _effectivePenType, // 🎯 FIX: Usa effective getter!
                                                        color:
                                                            _effectiveColor, // 🎯 FIX: Usa effective getter!
                                                        width:
                                                            _effectiveWidth, // 🎯 FIX: Usa effective getter!
                                                        settings:
                                                            _brushSettings, // 🎯 FIX: Passa settings per shape consistency!
                                                        // ✂️ Parametri per clipping
                                                        enableClipping:
                                                            _isImageEditFromInfiniteCanvas,
                                                        canvasSize: _canvasSize,
                                                        // 🎯 Predictive rendering (disabled @ 120Hz)
                                                        enablePredictive:
                                                            _renderingConfig
                                                                ?.enablePredictiveRendering ??
                                                            true,
                                                        // 🪞 Live symmetry preview
                                                        guideSystem:
                                                            _rulerGuideSystem,
                                                      ),
                                                      size: _canvasSize,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  ),
                                ), // InfiniteCanvasGestureDetector
                              ); // IgnorePointer
                            },
                          ),

                          // 🎤 SYNCHRONIZED PLAYBACK OVERLAY (Locale)
                          // Necessario per mostrare i tratti sincronizzati with the trasformazione locale (pan/zoom)
                          // nel contesto of the canvas infinito (Split View / Multiview)
                          if (widget.externalPlaybackController != null)
                            ListenableBuilder(
                              listenable: _canvasController,
                              builder: (context, child) {
                                return Positioned.fill(
                                  child: SynchronizedPlaybackOverlay(
                                    controller:
                                        widget.externalPlaybackController!,
                                    canvasOffset: _canvasController.offset,
                                    canvasScale: _canvasController.scale,
                                    showControls: false, // Gestiti globalmente
                                    forcePageIndex: widget.playbackPageIndex,
                                  ),
                                );
                              },
                            ),

                          // 🔲 REMOTE VIEWPORT OVERLAY (aree visibili utenti remoti)
                          if (_isSharedCanvas && _realtimeSyncManager != null)
                            ListenableBuilder(
                              listenable: _canvasController,
                              builder: (context, child) {
                                return CanvasViewportOverlay(
                                  cursors: _realtimeSyncManager!.remoteCursors,
                                  canvasOffset: _canvasController.offset,
                                  canvasScale: _canvasController.scale,
                                  screenSize: MediaQuery.of(context).size,
                                );
                              },
                            ),

                          // 🔵 REMOTE PRESENCE OVERLAY (cursori utenti remoti — via RTDB)
                          if (_isSharedCanvas && _realtimeSyncManager != null)
                            ListenableBuilder(
                              listenable: _canvasController,
                              builder: (context, child) {
                                return CanvasPresenceOverlay(
                                  cursors: _realtimeSyncManager!.remoteCursors,
                                  canvasOffset: _canvasController.offset,
                                  canvasScale: _canvasController.scale,
                                  followingUserId: _followingUserId,
                                  onFollowUser: (userId) {
                                    setState(() {
                                      if (_followingUserId == userId) {
                                        // Toggle off
                                        _followingUserId = null;
                                      } else {
                                        // Follow this user — jump to their viewport
                                        _followingUserId = userId;
                                        _jumpToFollowedUser(userId);
                                      }
                                    });
                                  },
                                );
                              },
                            ),

                          // Lasso Path Overlay - DENTRO l'area canvas (non more nello Stack principale)
                          if (_effectiveIsLasso &&
                              _lassoTool.lassoPath.isNotEmpty)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: CustomPaint(
                                  painter: LassoPathPainter(
                                    path: _lassoTool.lassoPath,
                                    color: Colors.blue,
                                    canvasController: _canvasController,
                                  ),
                                  size: Size.infinite,
                                ),
                              ),
                            ),

                          // Selection Overlay - DENTRO l'area canvas (non more nello Stack principale)
                          if (_lassoTool.hasSelection)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: LassoSelectionOverlay(
                                  selectedStrokeIds:
                                      _lassoTool.selectedStrokeIds,
                                  selectedShapeIds: _lassoTool.selectedShapeIds,
                                  layerController: _layerController,
                                  canvasController: _canvasController,
                                ),
                              ),
                            ),

                          // 🔲 Phase 3B: Selection Transform Handles
                          if (_lassoTool.hasSelection)
                            SelectionTransformOverlay(
                              lassoTool: _lassoTool,
                              canvasController: _canvasController,
                              onTransformComplete: () {
                                setState(() {});
                                _autoSaveCanvas();
                              },
                              isDark:
                                  Theme.of(context).brightness ==
                                  Brightness.dark,
                            ),

                          // ✒️ Pen Tool Overlay — anchors, handles, rubber-band
                          if (_toolController.isPenToolMode)
                            _penTool.buildOverlay(_penToolContext) ??
                                const SizedBox.shrink(),

                          // ✒️ Pen Tool Options Panel — stroke width, fill toggle, action buttons
                          if (_toolController.isPenToolMode)
                            Positioned(
                              bottom: 16,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: Builder(
                                  builder: (ctx) {
                                    // Wire context + callback for touch buttons
                                    _penTool.toolOptionsContext =
                                        _penToolContext;
                                    _penTool.onToolOptionsChanged = () {
                                      if (mounted) setState(() {});
                                    };
                                    return _penTool.buildToolOptions(ctx) ??
                                        const SizedBox.shrink();
                                  },
                                ),
                              ),
                            ),

                          // 🏗️ Eraser Cursor Overlay — trail, animated cursor, crosshair, badge
                          if (_effectiveIsEraser &&
                              _eraserCursorPosition != null)
                            Builder(
                              builder: (context) {
                                final screenPos = _canvasController
                                    .canvasToScreen(_eraserCursorPosition!);
                                final radius =
                                    _eraserTool.eraserRadius *
                                    _canvasController.scale;
                                final now =
                                    DateTime.now().millisecondsSinceEpoch;
                                final isDark =
                                    Theme.of(context).brightness ==
                                    Brightness.dark;

                                // 🎨 Dark/light mode adaptive colors
                                final cursorBorderColor =
                                    isDark
                                        ? Colors.red[300]!.withValues(
                                          alpha: 0.8,
                                        )
                                        : Colors.red.withValues(alpha: 0.7);
                                final cursorFillColor =
                                    isDark
                                        ? Colors.red[400]!.withValues(
                                          alpha:
                                              _eraserPreviewIds.isNotEmpty
                                                  ? 0.25
                                                  : 0.08,
                                        )
                                        : Colors.red.withValues(
                                          alpha:
                                              _eraserPreviewIds.isNotEmpty
                                                  ? 0.2
                                                  : 0.05,
                                        );
                                final crosshairColor =
                                    isDark
                                        ? Colors.white.withValues(alpha: 0.7)
                                        : Colors.white.withValues(alpha: 0.6);

                                // V10: Accessibility semantics for eraser cursor
                                return Semantics(
                                  label:
                                      'Eraser, radius ${_eraserTool.eraserRadius.round()}, '
                                      '${_eraserGestureEraseCount} erased',
                                  child: Stack(
                                    children: [
                                      // 🎯 Eraser trail (fading polyline with gradient)
                                      if (_eraserTrail.length >= 2)
                                        Positioned.fill(
                                          child: IgnorePointer(
                                            child: CustomPaint(
                                              painter: _EraserTrailPainter(
                                                trail: _eraserTrail,
                                                canvasController:
                                                    _canvasController,
                                                now: now,
                                                isDark: isDark,
                                              ),
                                            ),
                                          ),
                                        ),

                                      // 🎯 V3: Boundary particles
                                      if (_eraserParticles.isNotEmpty)
                                        Positioned.fill(
                                          child: IgnorePointer(
                                            child: CustomPaint(
                                              painter: _EraserParticlePainter(
                                                particles: _eraserParticles,
                                                canvasController:
                                                    _canvasController,
                                                isDark: isDark,
                                              ),
                                            ),
                                          ),
                                        ),

                                      // 🎯 V4: Lasso eraser path overlay
                                      if (_eraserLassoMode &&
                                          _eraserLassoPoints.length >= 2)
                                        Positioned.fill(
                                          child: IgnorePointer(
                                            child: CustomPaint(
                                              painter: _EraserLassoPathPainter(
                                                points: _eraserLassoPoints,
                                                canvasController:
                                                    _canvasController,
                                                isDark: isDark,
                                                isAnimating:
                                                    _eraserLassoAnimating,
                                              ),
                                            ),
                                          ),
                                        ),

                                      // 🎯 V4: Protected regions overlay
                                      if (_eraserTool
                                          .protectedRegions
                                          .isNotEmpty)
                                        Positioned.fill(
                                          child: IgnorePointer(
                                            child: CustomPaint(
                                              painter:
                                                  _EraserProtectedRegionPainter(
                                                    regions:
                                                        _eraserTool
                                                            .protectedRegions,
                                                    canvasController:
                                                        _canvasController,
                                                    isDark: isDark,
                                                  ),
                                            ),
                                          ),
                                        ),

                                      // 🎯 V4: Undo scrubber (shows undo depth)
                                      if (_eraserTool.undoStackDepth > 0)
                                        Positioned(
                                          bottom: 100,
                                          left: 0,
                                          right: 0,
                                          child: Center(
                                            child: IgnorePointer(
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 6,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color:
                                                      isDark
                                                          ? Colors.grey[800]!
                                                              .withValues(
                                                                alpha: 0.85,
                                                              )
                                                          : Colors.grey[200]!
                                                              .withValues(
                                                                alpha: 0.85,
                                                              ),
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                ),
                                                child: Text(
                                                  '↶ ${_eraserTool.undoStackDepth}',
                                                  style: TextStyle(
                                                    color:
                                                        isDark
                                                            ? Colors.white70
                                                            : Colors.black54,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),

                                      // 🎯 V5: Ghost preview — show strokes under eraser at low opacity
                                      if (_eraserPreviewIds.isNotEmpty)
                                        Positioned.fill(
                                          child: IgnorePointer(
                                            child: CustomPaint(
                                              painter:
                                                  _EraserGhostPreviewPainter(
                                                    previewStrokeIds:
                                                        _eraserPreviewIds,
                                                    layerController:
                                                        _layerController,
                                                    canvasController:
                                                        _canvasController,
                                                    isDark: isDark,
                                                  ),
                                            ),
                                          ),
                                        ),

                                      // 🎯 V5: Magnetic snap indicator — dashed line from cursor to snap target
                                      if (_eraserTool.magneticSnap &&
                                          _eraserTool.lastMagneticSnapTarget !=
                                              null &&
                                          _eraserCursorPosition != null)
                                        Positioned.fill(
                                          child: IgnorePointer(
                                            child: CustomPaint(
                                              painter: _MagneticSnapIndicatorPainter(
                                                cursorPos: _canvasController
                                                    .canvasToScreen(
                                                      _eraserCursorPosition!,
                                                    ),
                                                snapTarget: _canvasController
                                                    .canvasToScreen(
                                                      _eraserTool
                                                          .lastMagneticSnapTarget!,
                                                    ),
                                                isDark: isDark,
                                              ),
                                            ),
                                          ),
                                        ),

                                      // 🎯 V5: Shortcut ring (radial menu on long-press)
                                      if (_showEraserShortcutRing &&
                                          _eraserCursorPosition != null)
                                        Builder(
                                          builder: (context) {
                                            final center = _canvasController
                                                .canvasToScreen(
                                                  _eraserCursorPosition!,
                                                );
                                            const ringRadius = 80.0;
                                            final items = [
                                              (
                                                '🎯',
                                                'Snap',
                                                _eraserTool.magneticSnap,
                                              ),
                                              ('✂️', 'Lasso', _eraserLassoMode),
                                              (
                                                '🪶',
                                                'Feather',
                                                _eraserTool.featheredEdge,
                                              ),
                                              ('🔄', 'Undo', false),
                                            ];
                                            return Stack(
                                              children: [
                                                for (
                                                  int i = 0;
                                                  i < items.length;
                                                  i++
                                                )
                                                  Positioned(
                                                    left:
                                                        center.dx +
                                                        ringRadius *
                                                            math.cos(
                                                              i * math.pi / 2 -
                                                                  math.pi / 2,
                                                            ) -
                                                        22,
                                                    top:
                                                        center.dy +
                                                        ringRadius *
                                                            math.sin(
                                                              i * math.pi / 2 -
                                                                  math.pi / 2,
                                                            ) -
                                                        22,
                                                    child: GestureDetector(
                                                      onTap: () {
                                                        switch (i) {
                                                          case 0:
                                                            _eraserTool
                                                                    .magneticSnap =
                                                                !_eraserTool
                                                                    .magneticSnap;
                                                            break;
                                                          case 1:
                                                            _eraserLassoMode =
                                                                !_eraserLassoMode;
                                                            break;
                                                          case 2:
                                                            _eraserTool
                                                                    .featheredEdge =
                                                                !_eraserTool
                                                                    .featheredEdge;
                                                            break;
                                                          case 3:
                                                            _eraserTool.undo();
                                                            break;
                                                        }
                                                        _showEraserShortcutRing =
                                                            false;
                                                        setState(() {});
                                                      },
                                                      child: Container(
                                                        width: 44,
                                                        height: 44,
                                                        decoration: BoxDecoration(
                                                          color:
                                                              items[i].$3
                                                                  ? (isDark
                                                                      ? Colors
                                                                          .orange[700]
                                                                      : Colors
                                                                          .orange[400])
                                                                  : (isDark
                                                                      ? Colors
                                                                          .grey[800]
                                                                      : Colors
                                                                          .grey[200]),
                                                          shape:
                                                              BoxShape.circle,
                                                          boxShadow: [
                                                            BoxShadow(
                                                              color:
                                                                  Colors
                                                                      .black26,
                                                              blurRadius: 6,
                                                              offset:
                                                                  const Offset(
                                                                    0,
                                                                    2,
                                                                  ),
                                                            ),
                                                          ],
                                                        ),
                                                        child: Center(
                                                          child: Text(
                                                            items[i].$1,
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 20,
                                                                ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            );
                                          },
                                        ),

                                      // 🎯 V6: Dissolve particles — explosion effect at erased points
                                      if (_eraserShowDissolve &&
                                          _eraserTool.dissolvePoints.isNotEmpty)
                                        Positioned.fill(
                                          child: IgnorePointer(
                                            child: CustomPaint(
                                              painter:
                                                  _DissolveParticlesPainter(
                                                    points: List.from(
                                                      _eraserTool
                                                          .dissolvePoints,
                                                    ),
                                                    canvasController:
                                                        _canvasController,
                                                    isDark: isDark,
                                                  ),
                                            ),
                                          ),
                                        ),

                                      // 🎯 V6: Heatmap trail — color based on touch frequency
                                      if (_eraserTrail.isNotEmpty)
                                        Positioned.fill(
                                          child: IgnorePointer(
                                            child: CustomPaint(
                                              painter: _HeatmapTrailPainter(
                                                trail: _eraserTrail,
                                                eraserTool: _eraserTool,
                                                canvasController:
                                                    _canvasController,
                                              ),
                                            ),
                                          ),
                                        ),

                                      // 🎯 V6: Mask preview — full-canvas erase coverage
                                      if (_eraserMaskPreview &&
                                          _eraserCursorPosition != null)
                                        Positioned.fill(
                                          child: IgnorePointer(
                                            child: CustomPaint(
                                              painter: _EraserMaskPreviewPainter(
                                                cursorPos: _canvasController
                                                    .canvasToScreen(
                                                      _eraserCursorPosition!,
                                                    ),
                                                radius: radius,
                                                isDark: isDark,
                                              ),
                                            ),
                                          ),
                                        ),

                                      // 🎯 V6: Auto-clean highlight — pulse suggested strokes
                                      if (_autoCleanSuggestions.isNotEmpty)
                                        Positioned.fill(
                                          child: IgnorePointer(
                                            child: CustomPaint(
                                              painter:
                                                  _AutoCleanHighlightPainter(
                                                    suggestionIds:
                                                        _autoCleanSuggestions,
                                                    layerController:
                                                        _layerController,
                                                    canvasController:
                                                        _canvasController,
                                                    isDark: isDark,
                                                  ),
                                            ),
                                          ),
                                        ),

                                      // 🎯 V6: Analytics badge (bottom-right near cursor)
                                      if (_eraserTool.totalStrokesErased > 0)
                                        Positioned(
                                          right: 16,
                                          bottom: 100,
                                          child: IgnorePointer(
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 5,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: (isDark
                                                        ? Colors.grey[900]!
                                                        : Colors.white)
                                                    .withValues(alpha: 0.85),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                  color:
                                                      isDark
                                                          ? Colors.grey[700]!
                                                          : Colors.grey[300]!,
                                                ),
                                              ),
                                              child: Text(
                                                _eraserTool.analyticsSummary,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color:
                                                      isDark
                                                          ? Colors.grey[400]
                                                          : Colors.grey[600],
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),

                                      // 🎯 V6: History timeline (bottom strip)
                                      if (_showEraserTimeline &&
                                          _eraserTool
                                              .historySnapshots
                                              .isNotEmpty)
                                        Positioned(
                                          left: 60,
                                          right: 60,
                                          bottom: 50,
                                          height: 40,
                                          child: IgnorePointer(
                                            child: CustomPaint(
                                              painter:
                                                  _EraserHistoryTimelinePainter(
                                                    snapshots:
                                                        _eraserTool
                                                            .historySnapshots,
                                                    isDark: isDark,
                                                  ),
                                            ),
                                          ),
                                        ),

                                      // ─── V7 OVERLAYS ────────────────────────────────

                                      // 🎯 V7: Undo ghost replay — semi-transparent strokes fading in
                                      if (_showUndoGhostReplay &&
                                          _eraserTool
                                              .undoGhostStrokes
                                              .isNotEmpty)
                                        Positioned.fill(
                                          child: IgnorePointer(
                                            child: CustomPaint(
                                              painter: _UndoGhostReplayPainter(
                                                ghostStrokes:
                                                    _eraserTool
                                                        .undoGhostStrokes,
                                                progress:
                                                    _eraserTool
                                                        .undoGhostProgress,
                                                canvasController:
                                                    _canvasController,
                                                isDark: isDark,
                                              ),
                                            ),
                                          ),
                                        ),

                                      // 🎯 V7: Eraser shape cursor (rectangle/line shapes)
                                      if (_eraserCursorPosition != null &&
                                          _eraserTool.eraserShape !=
                                              EraserShape.circle)
                                        Positioned.fill(
                                          child: IgnorePointer(
                                            child: CustomPaint(
                                              painter: _EraserShapeCursorPainter(
                                                center: _canvasController
                                                    .canvasToScreen(
                                                      _eraserCursorPosition!,
                                                    ),
                                                shape: _eraserTool.eraserShape,
                                                radius: radius,
                                                shapeWidth:
                                                    _eraserTool
                                                        .eraserShapeWidth *
                                                    _canvasController.scale,
                                                angle:
                                                    _eraserTool
                                                        .eraserShapeAngle,
                                                isDark: isDark,
                                              ),
                                            ),
                                          ),
                                        ),

                                      // 🎯 V7: Edge-aware highlight — glow on stroke edges near cursor
                                      if (_eraserCursorPosition != null)
                                        Positioned.fill(
                                          child: IgnorePointer(
                                            child: CustomPaint(
                                              painter:
                                                  _EdgeAwareHighlightPainter(
                                                    edgePoints: _eraserTool
                                                        .getEdgeAwareStrokeIds(
                                                          _eraserCursorPosition!,
                                                        ),
                                                    canvasController:
                                                        _canvasController,
                                                    isDark: isDark,
                                                  ),
                                            ),
                                          ),
                                        ),

                                      // 🎯 V7: Smart selection preview — full highlighted stroke
                                      if (_smartSelectionStrokeId != null)
                                        Positioned.fill(
                                          child: IgnorePointer(
                                            child: CustomPaint(
                                              painter:
                                                  _SmartSelectionPreviewPainter(
                                                    strokeId:
                                                        _smartSelectionStrokeId!,
                                                    layerController:
                                                        _layerController,
                                                    canvasController:
                                                        _canvasController,
                                                    isDark: isDark,
                                                  ),
                                            ),
                                          ),
                                        ),

                                      // 🎯 V7: Layer-specific preview — dim non-active layers
                                      if (_showLayerPreview &&
                                          _eraserTool.layerPreviewMode)
                                        Positioned.fill(
                                          child: IgnorePointer(
                                            child: CustomPaint(
                                              painter: _LayerPreviewDimPainter(
                                                nonActiveIndices:
                                                    _eraserTool
                                                        .getNonActiveLayerIndices(),
                                                layerController:
                                                    _layerController,
                                                canvasController:
                                                    _canvasController,
                                                isDark: isDark,
                                              ),
                                            ),
                                          ),
                                        ),

                                      // 🎯 V7/V8: Pressure curve editor (bottom-left, interactive)
                                      if (_showPressureCurveEditor)
                                        Positioned(
                                          left: 16,
                                          bottom: 100,
                                          width: 120,
                                          height: 120,
                                          child: GestureDetector(
                                            onPanUpdate: (details) {
                                              // V8: Convert drag position to normalized [0,1] coords
                                              final box =
                                                  context.findRenderObject()
                                                      as RenderBox?;
                                              if (box == null) return;
                                              final padding = 12.0;
                                              final w = 120.0 - padding * 2;
                                              final h = 120.0 - padding * 2;
                                              final lx = ((details
                                                              .localPosition
                                                              .dx -
                                                          padding) /
                                                      w)
                                                  .clamp(0.0, 1.0);
                                              final ly = (1.0 -
                                                      (details
                                                                  .localPosition
                                                                  .dy -
                                                              padding) /
                                                          h)
                                                  .clamp(0.0, 1.0);
                                              final tapOffset = Offset(lx, ly);

                                              // Find nearest control point
                                              final cp =
                                                  _eraserTool
                                                      .pressureCurveControlPoints;
                                              final d0 =
                                                  (cp[0] - tapOffset).distance;
                                              final d1 =
                                                  (cp[1] - tapOffset).distance;
                                              if (d0 <= d1) {
                                                cp[0] = tapOffset;
                                              } else {
                                                cp[1] = tapOffset;
                                              }
                                              setState(() {});
                                            },
                                            child: CustomPaint(
                                              painter: _PressureCurveEditorPainter(
                                                controlPoints:
                                                    _eraserTool
                                                        .pressureCurveControlPoints,
                                                isDark: isDark,
                                              ),
                                            ),
                                          ),
                                        ),

                                      // 🎯 Cursor circle with pulse + crosshair + badge
                                      AnimatedBuilder(
                                        animation: _eraserPulseController,
                                        builder: (context, child) {
                                          final pulseScale =
                                              1.0 +
                                              0.15 *
                                                  (1.0 -
                                                      _eraserPulseController
                                                          .value);
                                          final scaledRadius =
                                              radius * pulseScale;

                                          return Positioned(
                                            left: screenPos.dx - scaledRadius,
                                            top: screenPos.dy - scaledRadius,
                                            child: IgnorePointer(
                                              child: SizedBox(
                                                width: scaledRadius * 2,
                                                height: scaledRadius * 2,
                                                child: Stack(
                                                  clipBehavior: Clip.none,
                                                  children: [
                                                    // Circle border + fill (V5: tilt-based ellipse)
                                                    Positioned.fill(
                                                      child: Transform(
                                                        alignment:
                                                            Alignment.center,
                                                        // V5: Compress on tilt axis for ellipse effect
                                                        transform:
                                                            Matrix4.identity()
                                                              ..scale(
                                                                1.0 -
                                                                    (_eraserTiltX
                                                                                .abs() *
                                                                            0.3)
                                                                        .clamp(
                                                                          0.0,
                                                                          0.4,
                                                                        ),
                                                                1.0 -
                                                                    (_eraserTiltY
                                                                                .abs() *
                                                                            0.3)
                                                                        .clamp(
                                                                          0.0,
                                                                          0.4,
                                                                        ),
                                                              )
                                                              ..rotateZ(
                                                                _eraserTiltX !=
                                                                            0 ||
                                                                        _eraserTiltY !=
                                                                            0
                                                                    ? math.atan2(
                                                                      _eraserTiltX,
                                                                      _eraserTiltY,
                                                                    )
                                                                    : 0.0,
                                                              ),
                                                        child: AnimatedContainer(
                                                          duration:
                                                              const Duration(
                                                                milliseconds:
                                                                    120,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            shape:
                                                                BoxShape.circle,
                                                            border: Border.all(
                                                              color:
                                                                  cursorBorderColor,
                                                              width: 2,
                                                            ),
                                                            color:
                                                                cursorFillColor,
                                                          ),
                                                        ),
                                                      ),
                                                    ),

                                                    // Crosshair lines
                                                    Center(
                                                      child: CustomPaint(
                                                        size: Size(
                                                          scaledRadius * 2,
                                                          scaledRadius * 2,
                                                        ),
                                                        painter:
                                                            _CrosshairPainter(
                                                              radius:
                                                                  scaledRadius,
                                                              color:
                                                                  crosshairColor,
                                                            ),
                                                      ),
                                                    ),

                                                    // 📏 Px label (below cursor)
                                                    Positioned(
                                                      bottom: -18,
                                                      left: 0,
                                                      right: 0,
                                                      child: Center(
                                                        child: Text(
                                                          '${_eraserTool.eraserRadius.round()}px',
                                                          style: TextStyle(
                                                            color:
                                                                isDark
                                                                    ? Colors
                                                                        .red[200]
                                                                    : Colors
                                                                        .red[600],
                                                            fontSize: 9,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                        ),
                                                      ),
                                                    ),

                                                    // Erase count badge (animated fade-out)
                                                    Positioned(
                                                      right: -6,
                                                      top: -6,
                                                      child: AnimatedOpacity(
                                                        opacity:
                                                            _eraserGestureEraseCount >
                                                                    0
                                                                ? 1.0
                                                                : 0.0,
                                                        duration: Duration(
                                                          milliseconds:
                                                              _eraserGestureEraseCount >
                                                                      0
                                                                  ? 100
                                                                  : 400,
                                                        ),
                                                        child: AnimatedScale(
                                                          scale:
                                                              _eraserGestureEraseCount >
                                                                      0
                                                                  ? 1.0
                                                                  : 0.6,
                                                          duration:
                                                              const Duration(
                                                                milliseconds:
                                                                    200,
                                                              ),
                                                          child: Container(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal: 5,
                                                                  vertical: 2,
                                                                ),
                                                            decoration: BoxDecoration(
                                                              color:
                                                                  Colors
                                                                      .red
                                                                      .shade700,
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    8,
                                                                  ),
                                                              boxShadow: [
                                                                BoxShadow(
                                                                  color:
                                                                      Colors
                                                                          .black26,
                                                                  blurRadius: 3,
                                                                ),
                                                              ],
                                                            ),
                                                            child: Text(
                                                              '${_eraserGestureEraseCount > 0 ? _eraserGestureEraseCount : ""}',
                                                              style: const TextStyle(
                                                                color:
                                                                    Colors
                                                                        .white,
                                                                fontSize: 10,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
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
                                      ),
                                    ],
                                  ), // Stack
                                ); // Semantics
                              },
                            ),

                          // 📏 Phase 3C: Interactive Ruler & Guide Overlay
                          // Always present so the corner menu remains accessible
                          // even when rulers are visually hidden
                          Positioned.fill(
                            child: RulerInteractiveOverlay(
                              guideSystem: _rulerGuideSystem,
                              canvasController: _canvasController,
                              isDark:
                                  Theme.of(context).brightness ==
                                  Brightness.dark,
                              onChanged: () => setState(() {}),
                            ),
                          ),

                          // Digital Text Elements - Rendering dei testi
                          ..._digitalTextElements.map((textElement) {
                            // Durante drag/resize, salta l'selected element
                            // (will be rendered below using selectedElement)
                            if (_digitalTextTool.hasSelection &&
                                _digitalTextTool.selectedElement!.id ==
                                    textElement.id) {
                              return const SizedBox.shrink();
                            }

                            final screenPos = _canvasController.canvasToScreen(
                              textElement.position,
                            );

                            return Positioned(
                              left: screenPos.dx,
                              top: screenPos.dy,
                              child: IgnorePointer(
                                child: Text(
                                  textElement.text,
                                  style: TextStyle(
                                    fontSize:
                                        textElement.fontSize *
                                        textElement.scale *
                                        _canvasController.scale,
                                    color: textElement.color,
                                    fontWeight: textElement.fontWeight,
                                    fontFamily: textElement.fontFamily,
                                  ),
                                ),
                              ),
                            );
                          }),

                          // Rendering dell'selected element dal TOOL
                          // Use Positioned con screen coordinates (NON CustomPaint)
                          if (_digitalTextTool.hasSelection)
                            Builder(
                              builder: (context) {
                                final textElement =
                                    _digitalTextTool.selectedElement!;
                                final screenPos = _canvasController
                                    .canvasToScreen(textElement.position);

                                return Positioned(
                                  left: screenPos.dx,
                                  top: screenPos.dy,
                                  child: IgnorePointer(
                                    child: Text(
                                      textElement.text,
                                      style: TextStyle(
                                        fontSize:
                                            textElement.fontSize *
                                            textElement.scale *
                                            _canvasController.scale,
                                        color: textElement.color,
                                        fontWeight: textElement.fontWeight,
                                        fontFamily: textElement.fontFamily,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),

                          // Rettangolo di selezione per l'selected element
                          if (_digitalTextTool.hasSelection)
                            Builder(
                              builder: (context) {
                                final textElement =
                                    _digitalTextTool.selectedElement!;
                                final screenPos = _canvasController
                                    .canvasToScreen(textElement.position);

                                // Calculate dimensioni del testo
                                final textPainter = TextPainter(
                                  text: TextSpan(
                                    text: textElement.text,
                                    style: TextStyle(
                                      fontSize:
                                          textElement.fontSize *
                                          textElement.scale *
                                          _canvasController.scale,
                                      fontWeight: textElement.fontWeight,
                                      fontFamily: textElement.fontFamily,
                                    ),
                                  ),
                                  textDirection: TextDirection.ltr,
                                )..layout();

                                final width = textPainter.width;
                                final height = textPainter.height;

                                return Positioned(
                                  left: screenPos.dx,
                                  top: screenPos.dy,
                                  width: width,
                                  height: height,
                                  child: IgnorePointer(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: Colors.deepPurple.withValues(
                                            alpha: 0.3,
                                          ),
                                          width: 2.0,
                                        ),
                                        color: Colors.deepPurple.withValues(
                                          alpha: 0.05,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),

                          // Handle di resize - 4 cerchietti agli angoli
                          if (_digitalTextTool.hasSelection)
                            Builder(
                              builder: (context) {
                                final textElement =
                                    _digitalTextTool.selectedElement!;
                                final screenPos = _canvasController
                                    .canvasToScreen(textElement.position);

                                // Calculate dimensioni del testo
                                final textPainter = TextPainter(
                                  text: TextSpan(
                                    text: textElement.text,
                                    style: TextStyle(
                                      fontSize:
                                          textElement.fontSize *
                                          textElement.scale *
                                          _canvasController.scale,
                                      fontWeight: textElement.fontWeight,
                                      fontFamily: textElement.fontFamily,
                                    ),
                                  ),
                                  textDirection: TextDirection.ltr,
                                )..layout();

                                final width = textPainter.width;
                                final height = textPainter.height;

                                // Posizioni dei 4 handle agli angoli
                                final handles = [
                                  Offset(
                                    screenPos.dx,
                                    screenPos.dy,
                                  ), // top-left
                                  Offset(
                                    screenPos.dx + width,
                                    screenPos.dy,
                                  ), // top-right
                                  Offset(
                                    screenPos.dx,
                                    screenPos.dy + height,
                                  ), // bottom-left
                                  Offset(
                                    screenPos.dx + width,
                                    screenPos.dy + height,
                                  ), // bottom-right
                                ];

                                return Stack(
                                  children:
                                      handles.map((handlePos) {
                                        return Positioned(
                                          left: handlePos.dx - 8,
                                          top: handlePos.dy - 8,
                                          child: IgnorePointer(
                                            child: Container(
                                              width: 16,
                                              height: 16,
                                              decoration: BoxDecoration(
                                                color: Colors.deepPurple,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Colors.white,
                                                  width: 2.0,
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                );
                              },
                            ),

                          // 🎵 Synchronized Playback Overlay (dentro il canvas Stack)
                          // This overlay shows the recorded strokes mentre
                          // permette la completa interazione with the canvas sottostante.
                          // The CustomPaint interno usa IgnorePointer per non bloccare i tocchi.
                          if (_isPlayingSyncedRecording &&
                              _playbackController != null)
                            Positioned.fill(
                              // 🔄 AnimatedBuilder per aggiornare l'overlay when the canvas si muove
                              child: AnimatedBuilder(
                                animation: _canvasController,
                                builder:
                                    (context, _) => SynchronizedPlaybackOverlay(
                                      controller: _playbackController!,
                                      canvasOffset: _canvasController.offset,
                                      canvasScale: _canvasController.scale,
                                      onClose: _stopSyncedPlayback,
                                      backgroundColor: _canvasBackgroundColor,
                                      onNavigateToDrawing:
                                          _navigateToCurrentDrawing, // 🧭 Naviga al disegno
                                    ),
                              ),
                            ),

                          // 🔄 LOADING OVERLAY: Copre il canvas durante il caricamento
                          // to avoid il flash background → strokes.
                          // AnimatedOpacity fa apparire tutto in una volta con fade-out.
                          IgnorePointer(
                            ignoring: !_isLoading,
                            child: AnimatedOpacity(
                              opacity: _isLoading ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOut,
                              child: Container(
                                color:
                                    Theme.of(context).scaffoldBackgroundColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ), // ClipRect
                  ),
                ],
              ),

              // Menu Contestuale Selezione - azioni sugli selected elements
              if (_lassoTool.hasSelection && !_isDrawingNotifier.value)
                Positioned(
                  bottom: 100,
                  left: 20,
                  right: 20,
                  child: SelectionActionsMenu(
                    selectionCount: _lassoTool.selectionCount,
                    onDelete: () {
                      setState(() {
                        _lassoTool.deleteSelected();
                        // Clear the selection after deletion
                        _lassoTool.clearSelection();
                        // Disattiva il lasso
                        _toolController.toggleLassoMode(); // deactivate lasso
                      });
                      HapticFeedback.mediumImpact();
                    },
                    onClearSelection: () {
                      setState(() {
                        _lassoTool.clearSelection();
                        // Disattiva il lasso
                        _toolController.toggleLassoMode(); // deactivate lasso
                      });
                      HapticFeedback.lightImpact();
                    },
                    onRotate: () {
                      setState(() {
                        _lassoTool.rotateSelected();
                        HapticFeedback.lightImpact();
                      });
                    },
                    onFlipHorizontal: () {
                      setState(() {
                        _lassoTool.flipHorizontal();
                        HapticFeedback.lightImpact();
                      });
                    },
                    onFlipVertical: () {
                      setState(() {
                        _lassoTool.flipVertical();
                        HapticFeedback.lightImpact();
                      });
                    },
                    onConvertToText: () {
                      // Phase 2: OCR conversion (requires OCRService)
                      HapticFeedback.mediumImpact();
                      debugPrint(
                        '[Phase2] OCR text conversion not yet available in SDK',
                      );
                    },
                  ),
                ),

              // 🖼️ Menu azioni per selected image
              if (_imageTool.selectedImage != null && !_isDrawingNotifier.value)
                Positioned(
                  bottom: 100,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color:
                            Theme.of(context).brightness == Brightness.dark
                                ? Colors.grey[850]
                                : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Pulsante Apri Editor
                          ImageActionButton(
                            icon: Icons.edit,
                            label: 'Edit',
                            color: Colors.blue,
                            onTap: () {
                              final imageElement = _imageTool.selectedImage!;
                              final image =
                                  _loadedImages[imageElement.imagePath];
                              if (image != null) {
                                _openImageEditor(imageElement, image);
                              }
                            },
                          ),
                          const SizedBox(width: 12),
                          // Pulsante Elimina
                          ImageActionButton(
                            icon: Icons.delete,
                            label: '*',
                            color: Colors.red,
                            onTap: () {
                              final imageElement = _imageTool.selectedImage!;
                              setState(() {
                                _imageElements.removeWhere(
                                  (e) => e.id == imageElement.id,
                                );
                                _imageTool.clearSelection();
                              });

                              // 🔄 Sync: notifica delta tracker per sincronizzazione
                              _layerController.removeImage(imageElement.id);
                              if (_isSharedCanvas)
                                _snapshotAndPushCloudDeltas();

                              _autoSaveCanvas();
                              HapticFeedback.mediumImpact();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // PHASE2:             // 📤 EXPORT MODE OVERLAYS
              // PHASE2:             if (_isExportMode) ...[
              // PHASE2:               // Area selector overlay
              // PHASE2:               ExportAreaSelector(
              // PHASE2:                 initialBounds: _exportArea,
              // PHASE2:                 maxBounds: Rect.fromLTWH(
              // PHASE2:                   0,
              // PHASE2:                   0,
              // PHASE2:                   _canvasSize.width,
              // PHASE2:                   _canvasSize.height,
              // PHASE2:                 ),
              // PHASE2:                 onBoundsChanged: _onExportAreaChanged,
              // PHASE2:                 quality: _exportConfig.quality,
              // PHASE2:                 canvasScale: _canvasController.scale,
              // PHASE2:                 canvasOffset: _canvasController.offset,
              // PHASE2:               ),
              // PHASE2:
              // PHASE2:               // Multi-page preview (se area grande)
              // PHASE2:               MultiPagePreviewOverlay(
              // PHASE2:                 exportArea: _exportArea,
              // PHASE2:                 pageFormat: _exportConfig.pageFormat,
              // PHASE2:                 quality: _exportConfig.quality,
              // PHASE2:                 canvasScale: _canvasController.scale,
              // PHASE2:                 canvasOffset: _canvasController.offset,
              // PHASE2:                 isVisible: true,
              // PHASE2:                 onPageFormatChanged: (format) {
              // PHASE2:                   setState(() {
              // PHASE2:                     _exportConfig = _exportConfig.copyWith(pageFormat: format);
              // PHASE2:                   });
              // PHASE2:                 },
              // PHASE2:               ),
              // PHASE2:
              // PHASE2:               // 🎵 Audio player banner
              // PHASE2:               if (_playingAudioPath != null)
              // PHASE2:                 Positioned(
              // PHASE2:                   left: 0,
              // PHASE2:                   right: 0,
              // PHASE2:                   bottom: 0,
              // PHASE2:                   child: AudioPlayerBanner(
              // PHASE2:                     audioPath: _playingAudioPath!,
              // PHASE2:                     onClose: () {
              // PHASE2:                       setState(() {
              // PHASE2:                         _playingAudioPath = null;
              // PHASE2:                       });
              // PHASE2:                     },
              // PHASE2:                   ),
              // PHASE2:                 ),
              // PHASE2:
              // PHASE2:               // Export mode toolbar
              // PHASE2:               Positioned(
              // PHASE2:                 left: 0,
              // PHASE2:                 right: 0,
              // PHASE2:                 bottom: 0,
              // PHASE2:                 child: Builder(
              // PHASE2:                   builder: (context) {
              // PHASE2:                     // Calculate numero pagine
              // PHASE2:                     final (
              // PHASE2:                       cols,
              // PHASE2:                       rows,
              // PHASE2:                       totalPages,
              // PHASE2:                     ) = CanvasExportService.calculatePageGrid(
              // PHASE2:                       exportArea: _exportArea,
              // PHASE2:                       quality: _exportConfig.quality,
              // PHASE2:                       pageFormat: _exportConfig.pageFormat,
              // PHASE2:                     );
              // PHASE2:
              // PHASE2:                     return ExportModeToolbar(
              // PHASE2:                       selectedPreset: _exportConfig.preset,
              // PHASE2:                       selectedQuality: _exportConfig.quality,
              // PHASE2:                       selectedBackground: _exportConfig.background,
              // PHASE2:                       backgroundColor: _exportConfig.backgroundColor,
              // PHASE2:                       showMultiPageIndicator: totalPages > 1,
              // PHASE2:                       pageCount: totalPages,
              // PHASE2:                       savedAreas: SavedExportAreasManager.instance
              // PHASE2:                           .getAreasForCanvas(_canvasId),
              // PHASE2:                       onPresetChanged: (preset) {
              // PHASE2:                         _applyExportPreset(preset);
              // PHASE2:                         setState(() {
              // PHASE2:                           _exportConfig = _exportConfig.copyWith(
              // PHASE2:                             preset: preset,
              // PHASE2:                           );
              // PHASE2:                         });
              // PHASE2:                       },
              // PHASE2:                       onQualityChanged: (quality) {
              // PHASE2:                         setState(() {
              // PHASE2:                           _exportConfig = _exportConfig.copyWith(
              // PHASE2:                             quality: quality,
              // PHASE2:                           );
              // PHASE2:                         });
              // PHASE2:                       },
              // PHASE2:                       onBackgroundChanged: (background) {
              // PHASE2:                         setState(() {
              // PHASE2:                           _exportConfig = _exportConfig.copyWith(
              // PHASE2:                             background: background,
              // PHASE2:                           );
              // PHASE2:                         });
              // PHASE2:                       },
              // PHASE2:                       onSavedAreasPressed: () {
              // PHASE2:                         // TODO: Mostra dialog con aree salvate
              // PHASE2:                       },
              // PHASE2:                       onExportPressed: _showExportFormatDialog,
              // PHASE2:                       onCancelPressed: _exitExportMode,
              // PHASE2:                       onEditPagesPressed: () {
              // PHASE2:                         // Esci from the mode export normale ed enamong then multi-page edit
              // PHASE2:                         setState(() {
              // PHASE2:                           _isExportMode = false;
              // PHASE2:                         });
              // PHASE2:                         _enterMultiPageEditMode();
              // PHASE2:                       },
              // PHASE2:                     );
              // PHASE2:                   },
              // PHASE2:                 ),
              // PHASE2:               ),
              // PHASE2:             ],

              // PHASE2:             // 📐 MULTI-PAGE EDIT MODE OVERLAYS
              // PHASE2:             if (_isMultiPageEditMode) ...[
              // PHASE2:               // Wrappa in AnimatedBuilder per reagire ai cambiamenti di pan/zoom
              // PHASE2:               AnimatedBuilder(
              // PHASE2:                 animation: _canvasController,
              // PHASE2:                 builder: (context, _) {
              // PHASE2:                   return Stack(
              // PHASE2:                     children: [
              // PHASE2:                       // Overlay scuro che copre TUTTO lo schermo CON BUCHI for the pagine
              // PHASE2:                       Positioned.fill(
              // PHASE2:                         child: IgnorePointer(
              // PHASE2:                           child: CustomPaint(
              // PHASE2:                             painter: FullScreenDarkOverlayPainter(
              // PHASE2:                               pageBounds: _multiPageConfig.individualPageBounds,
              // PHASE2:                               canvasScale: _canvasController.scale,
              // PHASE2:                               canvasOffset: _canvasController.offset,
              // PHASE2:                             ),
              // PHASE2:                           ),
              // PHASE2:                         ),
              // PHASE2:                       ),
              // PHASE2:
              // PHASE2:                       // Interactive page grid overlay - without dark overlay (solo pagine e handle)
              // PHASE2:                       Positioned(
              // PHASE2:                         left: 0,
              // PHASE2:                         right: 0,
              // PHASE2:                         top: 0,
              // PHASE2:                         bottom: 150, // Ferma le pagine PRIMA della toolbar
              // PHASE2:                         child: InteractivePageGridOverlay(
              // PHASE2:                           config: _multiPageConfig,
              // PHASE2:                           onConfigChanged: _onMultiPageConfigChanged,
              // PHASE2:                           canvasScale: _canvasController.scale,
              // PHASE2:                           canvasOffset: _canvasController.offset,
              // PHASE2:                           onPanCanvas: _onMultiPageAutoPan,
              // PHASE2:                           bottomPadding: 0,
              // PHASE2:                           showDarkOverlay:
              // PHASE2:                               false, // Do not mostrare overlay scuro (already sopra)
              // PHASE2:                         ),
              // PHASE2:                       ),
              // PHASE2:                     ],
              // PHASE2:                   );
              // PHASE2:                 },
              // PHASE2:               ),
              // PHASE2:
              // PHASE2:               // Multi-page edit toolbar - DOPO (sopra l'overlay)
              // PHASE2:               Positioned(
              // PHASE2:                 left: 0,
              // PHASE2:                 right: 0,
              // PHASE2:                 bottom: 0,
              // PHASE2:                 child: MultiPageEditToolbar(
              // PHASE2:                   config: _multiPageConfig,
              // PHASE2:                   onModeChanged: _onMultiPageModeChanged,
              // PHASE2:                   onPageFormatChanged: _onMultiPageFormatChanged,
              // PHASE2:                   onAddPage: _addMultiPagePage,
              // PHASE2:                   onRemovePage: _removeMultiPagePage,
              // PHASE2:                   onReorganize: _reorganizeMultiPages,
              // PHASE2:                   onConfirm: _confirmMultiPageEdit,
              // PHASE2:                   onCancel: () => _exitMultiPageEditMode(saveChanges: false),
              // PHASE2:                   onSavePreset: () {
              // PHASE2:                     // Save current multi-page config as preset
              // PHASE2:                     if (_multiPageConfig.individualPageBounds.isNotEmpty) {
              // PHASE2:                       Rect totalArea =
              // PHASE2:                           _multiPageConfig.individualPageBounds.first;
              // PHASE2:                       for (final bounds in _multiPageConfig.individualPageBounds
              // PHASE2:                           .skip(1)) {
              // PHASE2:                         totalArea = totalArea.expandToInclude(bounds);
              // PHASE2:                       }
              // PHASE2:
              // PHASE2:                       final savedArea = SavedExportArea(
              // PHASE2:                         id: SavedExportArea.generateId(),
              // PHASE2:                         name: 'Multi-page ${_multiPageConfig.pageCount} pagine',
              // PHASE2:                         canvasId: _canvasId,
              // PHASE2:                         bounds: totalArea,
              // PHASE2:                         createdAt: DateTime.now(),
              // PHASE2:                         multiPageConfig: _multiPageConfig,
              // PHASE2:                       );
              // PHASE2:
              // PHASE2:                       SavedExportAreasManager.instance.addArea(savedArea);
              // PHASE2:
              // PHASE2:                       ScaffoldMessenger.of(context).showSnackBar(
              // PHASE2:                         SnackBar(
              // PHASE2:                           content: Text(
              // PHASE2:                             // AppLocalizations removed // (
              // PHASE2:                               context,
              // PHASE2:                             ).proCanvas_multiPagePresetSaved,
              // PHASE2:                           ),
              // PHASE2:                           backgroundColor: Colors.green,
              // PHASE2:                         ),
              // PHASE2:                       );
              // PHASE2:                     }
              // PHASE2:                   },
              // PHASE2:                 ),
              // PHASE2:               ),
              // PHASE2:             ],

              // Layer Panel (slide da sinistra) - overlay sopra tutto
              LayerPanel(
                key: _layerPanelKey,
                controller: _layerController,
                isDark: false,
                isDrawingNotifier: _isDrawingNotifier,
              ),

              // PHASE2:             // 🎧 Audio Player Banner
              // PHASE2:             if (_playingAudioPath != null)
              // PHASE2:               Positioned(
              // PHASE2:                 left: 16,
              // PHASE2:                 right: 16,
              // PHASE2:                 bottom: 20,
              // PHASE2:                 child: AudioPlayerBanner(
              // PHASE2:                   audioPath: _playingAudioPath!,
              // PHASE2:                   onClose: () {
              // PHASE2:                     setState(() {
              // PHASE2:                       _playingAudioPath = null;
              // PHASE2:                     });
              // PHASE2:                   },
              // PHASE2:                 ),
              // PHASE2:               ),

              // PHASE2:             // 🤝 Share Canvas FAB with collaborator badge
              // PHASE2:             if (!_isExportMode &&
              // PHASE2:                 !_isMultiPageEditMode &&
              // PHASE2:                 !_isTimeTravelMode &&
              // PHASE2:                 !widget.hideToolbar)
              // PHASE2:               Positioned(
              // PHASE2:                 right: 16,
              // PHASE2:                 bottom: _playingAudioPath != null ? 80 : 20,
              // PHASE2:                 child: StreamBuilder<List<CanvasUserPresence>>(
              // PHASE2:                   stream:
              // PHASE2:                       _isSharedCanvas
              // PHASE2:                           ? _presenceService.presenceStream
              // PHASE2:                           : const Stream.empty(),
              // PHASE2:                   builder: (context, snapshot) {
              // PHASE2:                     final activeCount = snapshot.data?.length ?? 0;
              // PHASE2:
              // PHASE2:                     // 🔥 COST OPT: only listen for cursors/live strokes
              // PHASE2:                     // when at least 1 other user is present
              // PHASE2:                     if (_realtimeSyncManager != null) {
              // PHASE2:                       _realtimeSyncManager!.setCollaboratorsPresent(
              // PHASE2:                         activeCount > 0,
              // PHASE2:                       );
              // PHASE2:                     }
              // PHASE2:
              // PHASE2:                     return Stack(
              // PHASE2:                       clipBehavior: Clip.none,
              // PHASE2:                       children: [
              // PHASE2:                         FloatingActionButton.small(
              // PHASE2:                           heroTag: 'canvas_share_fab',
              // PHASE2:                           onPressed: () {
              // PHASE2:                             CanvasShareDialog.show(
              // PHASE2:                               context,
              // PHASE2:                               canvasId: _canvasId,
              // PHASE2:                               canvasTitle: _noteTitle,
              // PHASE2:                             );
              // PHASE2:                           },
              // PHASE2:                           backgroundColor:
              // PHASE2:                               _isSharedCanvas
              // PHASE2:                                   ? Theme.of(context).colorScheme.primary
              // PHASE2:                                   : Theme.of(context).colorScheme.surface,
              // PHASE2:                           foregroundColor:
              // PHASE2:                               _isSharedCanvas
              // PHASE2:                                   ? Colors.white
              // PHASE2:                                   : Theme.of(context).colorScheme.onSurface,
              // PHASE2:                           tooltip: 'Share Canvas',
              // PHASE2:                           child: Icon(
              // PHASE2:                             _isSharedCanvas
              // PHASE2:                                 ? Icons.people
              // PHASE2:                                 : Icons.person_add_outlined,
              // PHASE2:                           ),
              // PHASE2:                         ),
              // PHASE2:                         // 🔴 Active collaborator count badge
              // PHASE2:                         if (activeCount > 0)
              // PHASE2:                           Positioned(
              // PHASE2:                             right: -4,
              // PHASE2:                             top: -4,
              // PHASE2:                             child: Container(
              // PHASE2:                               padding: const EdgeInsets.all(4),
              // PHASE2:                               decoration: BoxDecoration(
              // PHASE2:                                 color: Colors.redAccent,
              // PHASE2:                                 shape: BoxShape.circle,
              // PHASE2:                                 border: Border.all(
              // PHASE2:                                   color: Theme.of(context).colorScheme.surface,
              // PHASE2:                                   width: 1.5,
              // PHASE2:                                 ),
              // PHASE2:                               ),
              // PHASE2:                               constraints: const BoxConstraints(
              // PHASE2:                                 minWidth: 18,
              // PHASE2:                                 minHeight: 18,
              // PHASE2:                               ),
              // PHASE2:                               child: Text(
              // PHASE2:                                 '$activeCount',
              // PHASE2:                                 style: const TextStyle(
              // PHASE2:                                   color: Colors.white,
              // PHASE2:                                   fontSize: 10,
              // PHASE2:                                   fontWeight: FontWeight.bold,
              // PHASE2:                                 ),
              // PHASE2:                                 textAlign: TextAlign.center,
              // PHASE2:                               ),
              // PHASE2:                             ),
              // PHASE2:                           ),
              // PHASE2:                         // 🟢🟡🔴 Dynamic connection status indicator
              // PHASE2:                         if (_realtimeSyncManager != null)
              // PHASE2:                           Positioned(
              // PHASE2:                             left: -2,
              // PHASE2:                             bottom: -2,
              // PHASE2:                             child: ValueListenableBuilder<RtdbConnectionState>(
              // PHASE2:                               valueListenable:
              // PHASE2:                                   ConnectionState.none /* Phase 2 */,
              // PHASE2:                               builder: (context, state, _) {
              // PHASE2:                                 final color = switch (state) {
              // PHASE2:                                   RtdbConnectionState.connected =>
              // PHASE2:                                     Colors.greenAccent.shade400,
              // PHASE2:                                   RtdbConnectionState.reconnecting =>
              // PHASE2:                                     Colors.amber,
              // PHASE2:                                   RtdbConnectionState.disconnected =>
              // PHASE2:                                     Colors.redAccent,
              // PHASE2:                                 };
              // PHASE2:
              // PHASE2:                                 return _SyncDot(
              // PHASE2:                                   color: color,
              // PHASE2:                                   pulsing:
              // PHASE2:                                       state == RtdbConnectionState.reconnecting,
              // PHASE2:                                   surfaceColor:
              // PHASE2:                                       Theme.of(context).colorScheme.surface,
              // PHASE2:                                 );
              // PHASE2:                               },
              // PHASE2:                             ),
              // PHASE2:                           ),
              // PHASE2:                       ],
              // PHASE2:                     );
              // PHASE2:                   },
              // PHASE2:                 ),
              // PHASE2:               ),
              // PHASE2:             // ⏱️ Time Travel Timeline Overlay (nascosta durante il lasso)
              // PHASE2:             if (_isTimeTravelMode &&
              // PHASE2:                 _timeTravelEngine != null &&
              // PHASE2:                 !_isTimeTravelLassoMode)
              // PHASE2:               TimeTravelTimelineWidget(
              // PHASE2:                 engine: _timeTravelEngine!,
              // PHASE2:                 onExit: _exitTimeTravelMode,
              // PHASE2:                 onExportRequested: _exportTimelapse,
              // PHASE2:                 onNewBranch: _createBranchFromCurrentPosition,
              // PHASE2:                 onBranchExplorer: _openBranchExplorer,
              // PHASE2:                 activeBranchName: _activeBranchName,
              // PHASE2:                 onRecoverRequested: () {
              // PHASE2:                   setState(() {
              // PHASE2:                     _isTimeTravelLassoMode = true;
              // PHASE2:                   });
              // PHASE2:                 },
              // PHASE2:               ),
              // PHASE2:
              // PHASE2:             // 🔮 Lasso overlay per recupero dal passato
              // PHASE2:             if (_isTimeTravelMode &&
              // PHASE2:                 _isTimeTravelLassoMode &&
              // PHASE2:                 _timeTravelEngine != null)
              // PHASE2:               Positioned.fill(
              // PHASE2:                 child: TimeTravelLassoOverlay(
              // PHASE2:                   engine: _timeTravelEngine!,
              // PHASE2:                   canvasController: _canvasController,
              // PHASE2:                   onCancel: () {
              // PHASE2:                     setState(() {
              // PHASE2:                       _isTimeTravelLassoMode = false;
              // PHASE2:                     });
              // PHASE2:                   },
              // PHASE2:                   onConfirm: (strokes, shapes, images, texts) {
              // PHASE2:                     setState(() {
              // PHASE2:                       _isTimeTravelLassoMode = false;
              // PHASE2:                     });
              // PHASE2:                     _recoverElementsFromPast(strokes, shapes, images, texts);
              // PHASE2:                   },
              // PHASE2:                 ),
              // PHASE2:               ),
              // PHASE2:
              // PHASE2:             // 🔮 Overlay posizionamento recupero (dopo uscita da Time Travel)
              // PHASE2:             if (_isRecoveryPlacementMode)
              // PHASE2:               Positioned.fill(
              // PHASE2:                 child: RecoveryPlacementOverlay(
              // PHASE2:                   strokes: _pendingRecoveryStrokes,
              // PHASE2:                   shapes: _pendingRecoveryShapes,
              // PHASE2:                   images: _pendingRecoveryImages,
              // PHASE2:                   texts: _pendingRecoveryTexts,
              // PHASE2:                   canvasController: _canvasController,
              // PHASE2:                   initialOffset: _recoveryPlacementOffset,
              // PHASE2:                   onOffsetChanged: (offset) {
              // PHASE2:                     _recoveryPlacementOffset = offset;
              // PHASE2:                   },
              // PHASE2:                   onConfirm: _commitRecoveryPlacement,
              // PHASE2:                   onCancel: _cancelRecoveryPlacement,
              // PHASE2:                 ),
              // PHASE2:               ),
            ],
          ),
        ),
      ),
    ); // Focus + Scaffold
  }
}
