part of '../../nebula_canvas_screen.dart';

/// 🎨 Canvas Layers — background, drawings, gesture detector, and canvas area orchestrator.
/// Extracted from _NebulaCanvasScreenState._buildImpl
extension NebulaCanvasLayersUI on _NebulaCanvasScreenState {
  /// Builds the canvas area: background + drawings + gesture detector + overlays.
  Widget _buildCanvasArea(BuildContext context) {
    return Expanded(
      key: _canvasAreaKey, // Key to track la size of the area
      child: ClipRect(
        // 🔒 ClipRect prevents canvas from invading the toolbar
        child: Stack(
          children: [
            _buildBackgroundLayer(),
            _buildDrawingLayer(),
            _buildImageLayer(),
            _buildGestureDetectorLayer(context),
            _buildCurrentStrokeLayer(),

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

            // 🏎️ Edge Auto-Scroll Glow Indicator
            if (_activeEdgeScroll != 0) ...[
              // Left edge
              if (_activeEdgeScroll & 1 != 0)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 30,
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Colors.blue.withValues(alpha: 0.25),
                            Colors.blue.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              // Right edge
              if (_activeEdgeScroll & 2 != 0)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 30,
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerRight,
                          end: Alignment.centerLeft,
                          colors: [
                            Colors.blue.withValues(alpha: 0.25),
                            Colors.blue.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              // Top edge
              if (_activeEdgeScroll & 4 != 0)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: 30,
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.blue.withValues(alpha: 0.25),
                            Colors.blue.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              // Bottom edge
              if (_activeEdgeScroll & 8 != 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 30,
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.blue.withValues(alpha: 0.25),
                            Colors.blue.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
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
                    sceneGraph: _layerController.sceneGraph,
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

  /// 🖼️ LAYER 2: IMAGES (VIEWPORT-LEVEL)
  /// Renders images at viewport level with controller-based repaint,
  /// matching the same pattern as DrawingPainter.
  Widget _buildImageLayer() {
    return ListenableBuilder(
      listenable: _layerController,
      builder: (context, _) {
        final dpr = MediaQuery.of(context).devicePixelRatio;
        return RepaintBoundary(
          child: IgnorePointer(
            child: CustomPaint(
              painter: ImagePainter(
                images: List<ImageElement>.from(_imageElements),
                loadedImages: _loadedImages,
                selectedImage: _imageTool.selectedImage,
                imageTool: _imageTool,
                imageInEditMode: _imageInEditMode,
                imageEditingStrokes: _imageEditingStrokes,
                currentEditingStroke: _currentEditingStrokeNotifier.value,
                loadingPulse: _loadingPulseValue,
                controller: _canvasController,
                imageVersion: _imageVersion,
                devicePixelRatio: dpr,
                spatialIndex: _imageSpatialIndex,
                memoryManager: _imageMemoryManager,
              ),
              size: Size.infinite,
            ),
          ),
        );
      },
    );
  }

  /// 🚀 INFINITE CANVAS: Gesture detector with OverflowBox transform stack
  Widget _buildGestureDetectorLayer(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 📐 Viewport dimensions for optimized culling
        final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);

        return IgnorePointer(
          // 🔮 Block canvas gestures during placement mode
          ignoring: _isRecoveryPlacementMode,
          child: InfiniteCanvasGestureDetector(
            controller: _canvasController,
            // 📐 In multi-page edit mode: blocks drawing
            onDrawStart: _isMultiPageEditMode ? null : _onDrawStart,
            onDrawUpdate: _isMultiPageEditMode ? null : _onDrawUpdate,
            onDrawEnd: _isMultiPageEditMode ? null : _onDrawEnd,
            onDrawCancel: _isMultiPageEditMode ? null : _onDrawCancel,
            onDoubleTapZoom:
                _isMultiPageEditMode
                    ? null
                    : () {
                      // Silently remove the dot from the first tap (no redo)
                      _layerController.discardLastAction();
                    },
            onLongPress: _isMultiPageEditMode ? null : _onLongPress,
            enableSingleFingerPan:
                _effectiveIsPanMode ||
                _isMultiPageEditMode, // 🖐️ Pan with a finger when active OR in multi-page edit
            isStylusModeEnabled:
                _isMultiPageEditMode
                    ? false
                    : _effectiveIsStylusMode, // 🖊️ Disable stylus mode in multi-page edit
            blockPanZoom:
                _digitalTextTool.isResizing ||
                _digitalTextTool.isDragging ||
                _imageTool.isResizing ||
                _imageTool
                    .isDragging, // 🔒 Block pan only when interacting with text/images
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
                        // 🚀 OverflowBox allows content to exceed parent limits
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

                            // 🖼️ LAYER 1.5: BACKGROUND IMAGE (if present)
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

                            // 🖼️ LAYER 3: IMAGES (now rendered at viewport level by _buildImageLayer)
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

  /// 🚀 LAYER 4 (Top): CURRENT STROKE — Viewport-level, independent repaint
  ///
  /// Lives OUTSIDE AnimatedBuilder's cached child because RepaintBoundary
  /// inside that cached child does not propagate repaint notifications
  /// from the strokeNotifier. Instead, the painter applies the canvas
  /// transform internally (like DrawingPainter).
  Widget _buildCurrentStrokeLayer() {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: CurrentStrokePainter(
            strokeNotifier: _currentStrokeNotifier,
            penType: _effectivePenType,
            color: _effectiveColor,
            width: _effectiveWidth,
            settings: _brushSettings,
            enableClipping: _isImageEditFromInfiniteCanvas,
            canvasSize: _canvasSize,
            enablePredictive:
                _renderingConfig?.enablePredictiveRendering ?? true,
            guideSystem: _rulerGuideSystem,
            controller: _canvasController, // 🚀 viewport-level mode
          ),
          size: Size.infinite,
        ),
      ),
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

  /// 🎵 Synchronized Playback Overlay (Recorded — inside the canvas Stack)
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
            ),
      ),
    );
  }
}
