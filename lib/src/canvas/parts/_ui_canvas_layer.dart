part of '../nebula_canvas_screen.dart';

/// 🎨 Canvas Layers — background, drawings, gesture detector, and canvas area orchestrator.
/// Extracted from _NebulaCanvasScreenState._buildImpl
extension NebulaCanvasLayersUI on _NebulaCanvasScreenState {
  /// Builds the canvas area: background + drawings + gesture detector + overlays.
  Widget _buildCanvasArea(BuildContext context) {
    return Expanded(
      key: _canvasAreaKey, // Key to track la size of the area
      child: ClipRect(
        // 🔒 ClipRect impedisce al canvas di invadere la toolbar
        child: Stack(
          children: [
            _buildBackgroundLayer(),
            _buildDrawingLayer(),
            _buildGestureDetectorLayer(context),

            // 🎤 SYNCHRONIZED PLAYBACK OVERLAY (Locale)
            if (widget.externalPlaybackController != null)
              _buildLocalPlaybackOverlay(context),

            // 🔲 REMOTE VIEWPORT & PRESENCE OVERLAYS
            ..._buildRemoteOverlays(context),

            // 🛠️ STANDARD OVERLAYS (Lasso, Selection, Pen, Ruler, Text)
            ..._buildStandardOverlays(context),

            // 🏗️ ERASER OVERLAYS
            ..._buildEraserOverlays(context),

            // 📏 Ruler & Digital Text overlays
            ..._buildToolOverlays(context),

            // 🎵 Synchronized Playback Overlay (Recorded)
            if (_isPlayingSyncedRecording && _playbackController != null)
              _buildRecordedPlaybackOverlay(context),

            // 🔄 LOADING OVERLAY
            _buildLoadingOverlay(context),
          ],
        ),
      ),
    );
  }

  /// 🎨 LAYER 0: SFONDO VIEWPORT-LEVEL
  Widget _buildBackgroundLayer() {
    return RepaintBoundary(
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
    );
  }

  /// 🎨 LAYER 1: DISEGNI COMPLETATI (VIEWPORT-LEVEL)
  Widget _buildDrawingLayer() {
    return ValueListenableBuilder<GeometricShape?>(
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
                    canvasOffset: _canvasController.offset,
                    canvasScale: _canvasController.scale,
                    viewportSize: Size.zero, // unused in viewport mode
                    enableClipping: _isImageEditFromInfiniteCanvas,
                    canvasSize: _canvasSize,
                    spatialIndex: _layerController.spatialIndex,
                    devicePixelRatio: MediaQuery.of(context).devicePixelRatio,
                    adaptiveConfig: _renderingConfig,
                    layers: _layerController.layers,
                    eraserPreviewIds: _eraserPreviewIds,
                    controller: _canvasController, // 🚀 viewport-level mode
                  ),
                  size: Size.infinite,
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 🚀 INFINITE CANVAS: Gesture detector with OverflowBox transform stack
  Widget _buildGestureDetectorLayer(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 📐 Dimensioni viewport per culling ottimizzato
        final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);

        return IgnorePointer(
          // 🔮 Blocca gesture canvas durante placement mode
          ignoring: _isRecoveryPlacementMode,
          child: InfiniteCanvasGestureDetector(
            controller: _canvasController,
            // 📐 In multi-page edit mode: blocca disegno
            onDrawStart: _isMultiPageEditMode ? null : _onDrawStart,
            onDrawUpdate: _isMultiPageEditMode ? null : _onDrawUpdate,
            onDrawEnd: _isMultiPageEditMode ? null : _onDrawEnd,
            onDrawCancel: _isMultiPageEditMode ? null : _onDrawCancel,
            onLongPress: _isMultiPageEditMode ? null : _onLongPress,
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
            child: ValueListenableBuilder<GeometricShape?>(
              valueListenable: _currentShapeNotifier,
              builder: (context, currentShape, _) {
                return ListenableBuilder(
                  listenable: _layerController,
                  builder: (context, _) {
                    // 🚀 AnimatedBuilder ONLY rebuilds Transform.
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
                                  ..translateByDouble(
                                    _canvasController.offset.dx,
                                    _canvasController.offset.dy,
                                    0.0,
                                    0.0,
                                  )
                                  ..scaleByDouble(
                                    _canvasController.scale,
                                    _canvasController.scale,
                                    1.0,
                                    1.0,
                                  ),
                            child: child,
                          ),
                        );
                      },
                      // 🚀 CACHED CHILD: rebuilt only by ListenableBuilder
                      child: SizedBox(
                        // 🎨 Canvas: dynamic dimensions
                        width: _canvasSize.width,
                        height: _canvasSize.height,
                        child: Stack(
                          children: [
                            // ✚ LAYER 0: INDICATORE ORIGINE (0,0)
                            if (!_isImageEditFromInfiniteCanvas)
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: OriginIndicatorPainter(
                                    scale: _canvasController.scale,
                                  ),
                                ),
                              ),

                            // 🖼️ LAYER 1.5: IMMAGINE DI SFONDO (se presente)
                            if (_backgroundImage != null)
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: BackgroundImagePainter(
                                    image: _backgroundImage!,
                                    isImageEditMode:
                                        _isImageEditFromInfiniteCanvas,
                                    viewportSize: viewportSize,
                                  ),
                                  size: _canvasSize,
                                ),
                              ),

                            // 🖼️ LAYER 3: IMMAGINI
                            RepaintBoundary(
                              child: CustomPaint(
                                painter: ImagePainter(
                                  images: List<ImageElement>.from(
                                    _imageElements,
                                  ),
                                  loadedImages: _loadedImages,
                                  selectedImage: _imageTool.selectedImage,
                                  imageTool: _imageTool,
                                  imageInEditMode: _imageInEditMode,
                                  imageEditingStrokes: _imageEditingStrokes,
                                  currentEditingStroke:
                                      _currentEditingStrokeNotifier.value,
                                  loadingPulse: _loadingPulseValue,
                                ),
                                size: _canvasSize,
                              ),
                            ),

                            // 🚀 LAYER 4 (Top): TRATTO CORRENTE
                            RepaintBoundary(
                              child: CustomPaint(
                                painter: CurrentStrokePainter(
                                  strokeNotifier: _currentStrokeNotifier,
                                  penType: _effectivePenType,
                                  color: _effectiveColor,
                                  width: _effectiveWidth,
                                  settings: _brushSettings,
                                  enableClipping:
                                      _isImageEditFromInfiniteCanvas,
                                  canvasSize: _canvasSize,
                                  enablePredictive:
                                      _renderingConfig
                                          ?.enablePredictiveRendering ??
                                      true,
                                  // 🪞 Live symmetry preview
                                  guideSystem: _rulerGuideSystem,
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
    );
  }

  /// 🎤 SYNCHRONIZED PLAYBACK OVERLAY (Locale — Split View / Multiview)
  Widget _buildLocalPlaybackOverlay(BuildContext context) {
    return ListenableBuilder(
      listenable: _canvasController,
      builder: (context, child) {
        return Positioned.fill(
          child: SynchronizedPlaybackOverlay(
            controller: widget.externalPlaybackController!,
            canvasOffset: _canvasController.offset,
            canvasScale: _canvasController.scale,
            showControls: false, // Gestiti globalmente
            forcePageIndex: widget.playbackPageIndex,
          ),
        );
      },
    );
  }

  /// 🎵 Synchronized Playback Overlay (Recorded — dentro il canvas Stack)
  Widget _buildRecordedPlaybackOverlay(BuildContext context) {
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _canvasController,
        builder:
            (context, _) => SynchronizedPlaybackOverlay(
              controller: _playbackController!,
              canvasOffset: _canvasController.offset,
              canvasScale: _canvasController.scale,
              onClose: _stopSyncedPlayback,
              backgroundColor: _canvasBackgroundColor,
              onNavigateToDrawing: _navigateToCurrentDrawing,
            ),
      ),
    );
  }

  /// 🔄 LOADING OVERLAY: covers canvas during loading
  Widget _buildLoadingOverlay(BuildContext context) {
    return IgnorePointer(
      ignoring: !_isLoading,
      child: AnimatedOpacity(
        opacity: _isLoading ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        child: Container(color: Theme.of(context).scaffoldBackgroundColor),
      ),
    );
  }
}
