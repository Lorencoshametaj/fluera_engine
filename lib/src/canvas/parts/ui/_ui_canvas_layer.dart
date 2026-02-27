part of '../../fluera_canvas_screen.dart';

/// 🎨 Canvas Layers — background, drawings, gesture detector, and canvas area orchestrator.
/// Extracted from _FlueraCanvasScreenState._buildImpl
extension FlueraCanvasLayersUI on _FlueraCanvasScreenState {
  /// Builds the canvas area: background + drawings + gesture detector + overlays.
  Widget _buildCanvasArea(BuildContext context) {
    return ClipRect(
      key: _canvasAreaKey, // Key to track la size of the area
      // 🔒 ClipRect prevents canvas from invading the toolbar
      child: Stack(
        children: [
          _buildBackgroundLayer(),
          _buildDrawingLayer(),
          _buildImageLayer(),
          _buildGestureDetectorLayer(context),
          _buildCurrentStrokeLayer(),
          _buildRemoteLiveStrokesLayer(),
          _buildPdfLoadingPlaceholdersLayer(),

          // 📐 SECTION PREVIEW OVERLAY
          if (_isSectionActive &&
              _sectionStartPoint != null &&
              _sectionCurrentEndPoint != null)
            IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _SectionPreviewPainter(
                    startPoint: _sectionStartPoint!,
                    endPoint: _sectionCurrentEndPoint!,
                    controller: _canvasController,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),

          // 📌 RECORDING PINS OVERLAY
          if (_recordingPins.isNotEmpty || _isPinPlacementMode)
            _buildRecordingPinsOverlay(context),

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

          // 🎵 Audio Mini-Player (floating bar during audio-only playback)
          if (_isPlayingAudio) _buildAudioMiniPlayer(context),

          // V1: LaTeX hidden — re-enable post-launch
          // if (_lassoTool.hasSelection && !_lassoTool.isDragging)
          //   _buildConvertToLatexFab(),
        ],
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
            // Wrap in another builder so search controller changes trigger repaint
            Widget buildPainter(BuildContext context, Widget? _) {
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
                      pdfPainters: _pdfPainters,
                      onPdfRepaint: () {
                        if (mounted) setState(() {});
                      },
                      pdfSearchController:
                          _pdfSearchController, // 🔍 Search highlights
                      pdfLayoutVersion:
                          _pdfLayoutVersion, // 📄 Layout mutation counter
                      showPdfPageNumbers: _showPdfPageNumbers,
                      surface: _activeSurface, // 🧬 Programmable materiality
                    ),
                    size: Size.infinite,
                  ),
                ),
              );
            }

            // If search controller exists, listen for match changes → repaint
            if (_pdfSearchController != null) {
              return ListenableBuilder(
                listenable: _pdfSearchController!,
                builder: buildPainter,
              );
            }
            return buildPainter(context, null);
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
        // 🔧 FIX: Listen to _currentEditingStrokeNotifier so ImagePainter
        // repaints on every pen move during image editing mode.
        // Previously, .value was passed as a snapshot at build time,
        // causing the live stroke to lag behind the finalized strokes.
        return ValueListenableBuilder<ProStroke?>(
          valueListenable: _currentEditingStrokeNotifier,
          builder: (context, editingStroke, _) {
            return RepaintBoundary(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: ImagePainter(
                    images: _imageElements,
                    loadedImages: _loadedImages,
                    selectedImage: _imageTool.selectedImage,
                    imageTool: _imageTool,
                    canvasStrokes:
                        _layerController.layers
                            .firstWhere(
                              (l) => l.id == _layerController.activeLayerId,
                              orElse: () => _layerController.layers.first,
                            )
                            .strokes,
                    loadingPulse: _loadingPulseValue,
                    controller: _canvasController,
                    imageVersion: _imageVersion,
                    devicePixelRatio: dpr,
                    spatialIndex: _imageSpatialIndex,
                    memoryManager: _imageMemoryManager,
                    imageRepaintNotifier: _imageRepaintNotifier,
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
            // 📄 Intercept pan on PDF pages → route to draw callbacks for document drag
            onPanInterceptTest:
                _effectiveIsPanMode
                    ? (canvasPos) {
                      // 🐛 FIX: When an image is selected, ALL touches must
                      // go through _onDrawStart to handle:
                      //   • Rotation handle hit test → start rotation
                      //   • Resize handle hit test → start resize
                      //   • Tap on another image → select it
                      //   • Tap on empty space → deselect current image
                      if (_imageTool.selectedImage != null) return true;

                      // Check images
                      for (final imageElement in _imageElements.reversed) {
                        final image = _loadedImages[imageElement.imagePath];
                        if (image != null) {
                          final imageSize = Size(
                            image.width.toDouble(),
                            image.height.toDouble(),
                          );
                          if (_imageTool.hitTest(
                            imageElement,
                            canvasPos,
                            imageSize,
                          )) {
                            return true;
                          }
                        }
                      }
                      // Check PDF pages
                      for (final layer in _layerController.sceneGraph.layers) {
                        for (final child in layer.children) {
                          if (child is PdfDocumentNode) {
                            if (child.hitTestPageIndex(canvasPos) >= 0)
                              return true;
                          }
                        }
                      }
                      // Check recording pins
                      if (_recordingPins.isNotEmpty) {
                        const hitRadius = 28.0;
                        for (final pin in _recordingPins.reversed) {
                          final dx = canvasPos.dx - pin.position.dx;
                          final dy = canvasPos.dy - pin.position.dy;
                          if (dx * dx + dy * dy <= hitRadius * hitRadius) {
                            return true;
                          }
                        }
                      }
                      return false;
                    }
                    : null,
            isStylusModeEnabled:
                _isMultiPageEditMode
                    ? false
                    : _effectiveIsStylusMode, // 🖊️ Disable stylus mode in multi-page edit
            blockPanZoom:
                _digitalTextTool.isResizing ||
                _digitalTextTool.isDragging ||
                _imageTool.isResizing ||
                _imageTool.isDragging ||
                _imageTool.isRotating ||
                _tabularTool.isDragging ||
                _tabularTool.isResizing ||
                (_effectiveIsPanMode &&
                    _imageTool.selectedImage !=
                        null), // 🌀 Block canvas zoom when image selected in pan mode
            // 🌀 IMAGE ROTATION: Two-finger rotate + scale on selected image (pan mode only)
            onImageScaleStart: _effectiveIsPanMode ? _onImageScaleStart : null,
            onImageTransform: _effectiveIsPanMode ? _onImageTransform : null,
            onImageScaleEnd: _effectiveIsPanMode ? _onImageScaleEnd : null,
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
            pdfClipRect: _activePdfClipRect, // ✂️ PDF page clipping
            surface: _activeSurface, // 🧬 Programmable materiality
          ),
          size: Size.infinite,
        ),
      ),
    );
  }

  /// ☁️ LAYER 4.5: REMOTE LIVE STROKES — strokes in progress from collaborators
  Widget _buildRemoteLiveStrokesLayer() {
    final strokes = CollaborationExtension.remoteLiveStrokes;
    if (strokes.isEmpty) return const SizedBox.shrink();

    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _RemoteLiveStrokesPainter(
            strokes: strokes,
            colors: CollaborationExtension.remoteLiveStrokeColors,
            widths: CollaborationExtension.remoteLiveStrokeWidths,
            controller: _canvasController,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }

  /// 📄 LAYER 4.6: PDF LOADING PLACEHOLDERS — placeholder for remote PDFs being uploaded
  Widget _buildPdfLoadingPlaceholdersLayer() {
    final placeholders = CollaborationExtension.pdfLoadingPlaceholders;
    if (placeholders.isEmpty) return const SizedBox.shrink();

    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _PdfLoadingPlaceholderPainter(
            placeholders: placeholders.values.toList(),
            controller: _canvasController,
            pulseValue: _loadingPulseValue,
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
        return Stack(
          children: [
            Positioned.fill(
              child: SynchronizedPlaybackOverlay(
                controller: widget.externalPlaybackController!,
                canvasOffset: _canvasController.offset,
                canvasScale: _canvasController.scale,
                showControls: false, // Gestiti globalmente
                forcePageIndex: widget.playbackPageIndex,
              ),
            ),
          ],
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
              onAutoFollow: (canvasPos) {
                // Pan to center the active stroke on screen
                final viewSize = MediaQuery.of(context).size;
                final targetOffset = Offset(
                  -canvasPos.dx * _canvasController.scale + viewSize.width / 2,
                  -canvasPos.dy * _canvasController.scale + viewSize.height / 2,
                );
                _canvasController.animateToTransform(
                  targetOffset: targetOffset,
                  targetScale: _canvasController.scale,
                );
              },
            ),
      ),
    );
  }
}

/// ☁️ Paints live strokes from remote collaborators as simple polylines.
class _RemoteLiveStrokesPainter extends CustomPainter {
  final Map<String, List<Offset>> strokes;
  final Map<String, int> colors;
  final Map<String, double> widths;
  final InfiniteCanvasController controller;

  _RemoteLiveStrokesPainter({
    required this.strokes,
    required this.colors,
    required this.widths,
    required this.controller,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (strokes.isEmpty) return;

    canvas.save();
    canvas.translate(controller.offset.dx, controller.offset.dy);
    canvas.scale(controller.scale);

    for (final entry in strokes.entries) {
      final points = entry.value;
      if (points.length < 2) continue;

      final color = Color(colors[entry.key] ?? 0xFF42A5F5);
      final width = widths[entry.key] ?? 2.0;

      final paint =
          Paint()
            ..color = color.withValues(alpha: 0.6)
            ..strokeWidth = width
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..style = PaintingStyle.stroke;

      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (int i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(path, paint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RemoteLiveStrokesPainter oldDelegate) => true;
}

/// 📄 Paints loading placeholders for remote PDFs being uploaded.
class _PdfLoadingPlaceholderPainter extends CustomPainter {
  final List<_PdfLoadingPlaceholder> placeholders;
  final InfiniteCanvasController controller;
  final double pulseValue;

  _PdfLoadingPlaceholderPainter({
    required this.placeholders,
    required this.controller,
    this.pulseValue = 0.5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (placeholders.isEmpty) return;

    canvas.save();
    canvas.translate(controller.offset.dx, controller.offset.dy);
    canvas.scale(controller.scale);

    for (final placeholder in placeholders) {
      final rect = placeholder.rect;

      // 🎬 Fade-in: opacity ramps from 0→1 over 300ms
      final age =
          DateTime.now().difference(placeholder.createdAt).inMilliseconds;
      final fadeOpacity = (age / 300.0).clamp(0.0, 1.0);

      // 🎯 Smooth progress lerp (0.08 factor ≈ smooth interpolation at 30fps)
      final targetProgress = placeholder.progress;
      final currentAnimated = _animatedProgress[placeholder.documentId] ?? 0.0;
      final animated =
          currentAnimated + (targetProgress - currentAnimated) * 0.08;
      _animatedProgress[placeholder.documentId] = animated;

      // 📸 Thumbnail preview — decode and render as blurred background
      final thumbB64 = placeholder.thumbnailBase64;
      if (thumbB64 != null &&
          _decodedThumbnails.containsKey(placeholder.documentId)) {
        final thumbImage = _decodedThumbnails[placeholder.documentId]!;
        final srcRect = Rect.fromLTWH(
          0,
          0,
          thumbImage.width.toDouble(),
          thumbImage.height.toDouble(),
        );
        final thumbPaint =
            Paint()
              ..color = Colors.white.withValues(alpha: 0.4 * fadeOpacity)
              ..imageFilter = ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3);
        canvas.save();
        canvas.clipRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(12)),
        );
        canvas.drawImageRect(thumbImage, srcRect, rect, thumbPaint);
        canvas.restore();
      } else if (thumbB64 != null &&
          !_thumbnailDecodeRequested.contains(placeholder.documentId)) {
        _thumbnailDecodeRequested.add(placeholder.documentId);
        _decodeThumbnail(placeholder.documentId, thumbB64);
      }

      // Background — subtle shimmer
      final alpha = (0.08 + 0.04 * pulseValue) * fadeOpacity;
      final bgPaint =
          Paint()
            ..color = Colors.white.withValues(alpha: alpha)
            ..style = PaintingStyle.fill;
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(12));
      canvas.drawRRect(rrect, bgPaint);

      // Border
      final borderPaint =
          Paint()
            ..color = Colors.white.withValues(alpha: 0.3 * fadeOpacity)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0;
      canvas.drawRRect(rrect, borderPaint);

      // Loading icon (circular indicator) — centered
      final center = rect.center;
      final indicatorRadius = 20.0;
      final indicatorPaint =
          Paint()
            ..color = Colors.white.withValues(alpha: 0.5 * fadeOpacity)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.0
            ..strokeCap = StrokeCap.round;

      // Draw arc that rotates with pulse
      final sweepAngle = 3.14 * 1.5;
      final startAngle = pulseValue * 3.14 * 2;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: indicatorRadius),
        startAngle,
        sweepAngle,
        false,
        indicatorPaint,
      );

      // Progress bar — shown when animated progress > 0.01
      if (animated > 0.01) {
        final barWidth = rect.width * 0.6;
        final barHeight = 6.0;
        final barLeft = center.dx - barWidth / 2;
        final barTop = center.dy + indicatorRadius + 8;

        // Background track
        final trackPaint =
            Paint()
              ..color = Colors.white.withValues(alpha: 0.15 * fadeOpacity)
              ..style = PaintingStyle.fill;
        final trackRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(barLeft, barTop, barWidth, barHeight),
          const Radius.circular(3),
        );
        canvas.drawRRect(trackRect, trackPaint);

        // Fill (using animated lerped value)
        final fillPaint =
            Paint()
              ..color = Colors.white.withValues(alpha: 0.6 * fadeOpacity)
              ..style = PaintingStyle.fill;
        final fillRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(barLeft, barTop, barWidth * animated, barHeight),
          const Radius.circular(3),
        );
        canvas.drawRRect(fillRect, fillPaint);
      }

      // Label text
      final label = placeholder.fileName ?? 'PDF';
      final pct = animated > 0.01 ? ' ${(animated * 100).toInt()}%' : '';
      final textPainter = TextPainter(
        text: TextSpan(
          text: 'Loading $label...$pct',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6 * fadeOpacity),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: rect.width - 40);

      final labelTop =
          animated > 0.01
              ? center.dy + indicatorRadius + 22
              : center.dy + indicatorRadius + 16;

      textPainter.paint(
        canvas,
        Offset(center.dx - textPainter.width / 2, labelTop),
      );

      // Page count badge
      final countPainter = TextPainter(
        text: TextSpan(
          text: '${placeholder.pageCount} pages',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4 * fadeOpacity),
            fontSize: 12,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      countPainter.paint(
        canvas,
        Offset(
          center.dx - countPainter.width / 2,
          labelTop + textPainter.height + 6,
        ),
      );
    }

    canvas.restore();
  }

  // 📸 Static thumbnail decode cache — shared across painter instances
  static final Map<String, ui.Image> _decodedThumbnails = {};
  static final Set<String> _thumbnailDecodeRequested = {};
  // 🎯 Animated progress cache for smooth lerp
  static final Map<String, double> _animatedProgress = {};

  /// Async decode base64 PNG thumbnail → cache for next paint.
  static void _decodeThumbnail(String docId, String base64Str) async {
    try {
      final bytes = base64Decode(base64Str);
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      _decodedThumbnails[docId] = frame.image;
      codec.dispose();
    } catch (e) {
      debugPrint('[RT] 📸 Thumbnail decode failed: $e');
    }
  }

  @override
  bool shouldRepaint(covariant _PdfLoadingPlaceholderPainter oldDelegate) =>
      true;
}

/// 📐 Paints a live preview rectangle while dragging to create a section.
/// Includes dashed border, corner marks, translucent fill, and dimension label.
class _SectionPreviewPainter extends CustomPainter {
  final Offset startPoint;
  final Offset endPoint;
  final InfiniteCanvasController controller;

  _SectionPreviewPainter({
    required this.startPoint,
    required this.endPoint,
    required this.controller,
  });

  static const _accentColor = Color(0xFF2196F3);
  static const _cornerLength = 14.0;
  static const _cornerStroke = 2.5;
  static const _dashLength = 6.0;
  static const _dashGap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromPoints(startPoint, endPoint);
    if (rect.width < 2 && rect.height < 2) return;

    canvas.save();
    canvas.translate(controller.offset.dx, controller.offset.dy);
    canvas.scale(controller.scale);

    // 1. Translucent fill
    final fillPaint =
        Paint()
          ..color = _accentColor.withValues(alpha: 0.06)
          ..style = PaintingStyle.fill;
    canvas.drawRect(rect, fillPaint);

    // 2. Dashed border
    final borderPaint =
        Paint()
          ..color = _accentColor.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0 / controller.scale;
    _drawDashedRect(canvas, rect, borderPaint);

    // 3. Corner marks (solid, thicker)
    final cornerPaint =
        Paint()
          ..color = _accentColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = _cornerStroke / controller.scale
          ..strokeCap = StrokeCap.round;
    final cl = _cornerLength / controller.scale;
    _drawCornerMarks(canvas, rect, cornerPaint, cl);

    // 4. Dimension label
    final w = rect.width.round();
    final h = rect.height.round();
    if (w > 10 && h > 10) {
      final labelFontSize = 11.0 / controller.scale;
      final tp = TextPainter(
        text: TextSpan(
          text: '$w × $h',
          style: TextStyle(
            color: _accentColor,
            fontSize: labelFontSize,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      // Position: centered at bottom of rect, slightly below
      final labelX = rect.center.dx - tp.width / 2;
      final labelY = rect.bottom + 6.0 / controller.scale;

      // Background pill
      final labelPadH = 6.0 / controller.scale;
      final labelPadV = 3.0 / controller.scale;
      final labelRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          labelX - labelPadH,
          labelY - labelPadV,
          tp.width + labelPadH * 2,
          tp.height + labelPadV * 2,
        ),
        Radius.circular(4.0 / controller.scale),
      );
      canvas.drawRRect(labelRect, Paint()..color = const Color(0xE0121212));

      tp.paint(canvas, Offset(labelX, labelY));
    }

    canvas.restore();
  }

  void _drawDashedRect(Canvas canvas, Rect rect, Paint paint) {
    final invScale = 1.0 / controller.scale;
    final dash = _dashLength * invScale;
    final gap = _dashGap * invScale;

    // Top edge
    _drawDashedLine(canvas, rect.topLeft, rect.topRight, paint, dash, gap);
    // Right edge
    _drawDashedLine(canvas, rect.topRight, rect.bottomRight, paint, dash, gap);
    // Bottom edge
    _drawDashedLine(
      canvas,
      rect.bottomRight,
      rect.bottomLeft,
      paint,
      dash,
      gap,
    );
    // Left edge
    _drawDashedLine(canvas, rect.bottomLeft, rect.topLeft, paint, dash, gap);
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint,
    double dashLen,
    double gapLen,
  ) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final length = Offset(dx, dy).distance;
    if (length < 1) return;
    final ux = dx / length;
    final uy = dy / length;

    double drawn = 0;
    bool drawing = true;
    while (drawn < length) {
      final segLen = drawing ? dashLen : gapLen;
      final remaining = length - drawn;
      final len = segLen < remaining ? segLen : remaining;

      if (drawing) {
        canvas.drawLine(
          Offset(start.dx + ux * drawn, start.dy + uy * drawn),
          Offset(start.dx + ux * (drawn + len), start.dy + uy * (drawn + len)),
          paint,
        );
      }
      drawn += len;
      drawing = !drawing;
    }
  }

  void _drawCornerMarks(Canvas canvas, Rect rect, Paint paint, double len) {
    // Top-left
    canvas.drawLine(rect.topLeft, Offset(rect.left + len, rect.top), paint);
    canvas.drawLine(rect.topLeft, Offset(rect.left, rect.top + len), paint);
    // Top-right
    canvas.drawLine(rect.topRight, Offset(rect.right - len, rect.top), paint);
    canvas.drawLine(rect.topRight, Offset(rect.right, rect.top + len), paint);
    // Bottom-left
    canvas.drawLine(
      rect.bottomLeft,
      Offset(rect.left + len, rect.bottom),
      paint,
    );
    canvas.drawLine(
      rect.bottomLeft,
      Offset(rect.left, rect.bottom - len),
      paint,
    );
    // Bottom-right
    canvas.drawLine(
      rect.bottomRight,
      Offset(rect.right - len, rect.bottom),
      paint,
    );
    canvas.drawLine(
      rect.bottomRight,
      Offset(rect.right, rect.bottom - len),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _SectionPreviewPainter oldDelegate) =>
      startPoint != oldDelegate.startPoint || endPoint != oldDelegate.endPoint;
}
