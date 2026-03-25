part of '../../fluera_canvas_screen.dart';

/// 🎨 Canvas Layers — background, drawings, gesture detector, and canvas area orchestrator.
/// Extracted from _FlueraCanvasScreenState._buildImpl
extension FlueraCanvasLayersUI on _FlueraCanvasScreenState {
  /// Builds the canvas area: background + drawings + gesture detector + overlays.
  Widget _buildCanvasArea(BuildContext context) {
    // 🖥️ Multiview mode — replace single canvas with split panels
    if (_isMultiviewActive && _multiviewLayout != null) {
      return MultiviewOrchestrator(
        config: _config,
        canvasId: _canvasId,
        title: _noteTitle,
        layerController: _layerController,
        initialLayout: _multiviewLayout!,
        initialOffset: _canvasController.offset,
        initialScale: _canvasController.scale,
        onExitMultiview: () {
          setState(() {
            _isMultiviewActive = false;
            _multiviewLayout = null;
          });
        },
      );
    }

    return ClipRect(
      key: _canvasAreaKey, // Key to track la size of the area
      // 🔒 ClipRect prevents canvas from invading the toolbar
      child: Stack(
        children: [
          // 🚀 LAYER MERGE: Background is now painted inside DrawingPainter
          // (via inverse transform), eliminating 1 compositing layer.
          // _backgroundLayerHost removed — see DrawingPainter.paint().
          // 🧠 SEMANTIC MORPHING: Fade ink when zooming out into semantic view
          AnimatedBuilder(
            animation: _canvasController,
            builder: (context, child) {
              final morphT = _semanticMorphController?.morphProgress ?? 0.0;
              // Keep a faint ghost (0.15) to maintain spatial reference
              final inkOpacity = morphT > 0.01
                  ? (1.0 - morphT * 0.85).clamp(0.15, 1.0)
                  : 1.0;
              if (inkOpacity >= 0.999) return child!;
              return Opacity(opacity: inkOpacity, child: child);
            },
            child: _drawingLayerHost,
          ),
          _imageLayerHost,
          // 🧠 KNOWLEDGE FLOW: Word underlines + connections + label pills
          // Must be AFTER drawing/image layers so it renders ON TOP of canvas content.
          if (_knowledgeFlowController != null && (_clusterCache.isNotEmpty || _knowledgeFlowController!.connections.isNotEmpty))
            IgnorePointer(
              child: AnimatedBuilder(
                  animation: _canvasController,
                  builder: (context, _) {
                    final m = Matrix4.identity()
                      ..translate(
                        _canvasController.offset.dx,
                        _canvasController.offset.dy,
                      );
                    if (_canvasController.rotation != 0.0) {
                      m.rotateZ(_canvasController.rotation);
                    }
                    m.scale(_canvasController.scale);
                    // 🧠 SEMANTIC MORPHING: Update morph progress from scale
                    _semanticMorphController?.updateFromScale(
                      _canvasController.scale,
                    );
                    // 🃏 AUTO-DISMISS flashcard when leaving semantic view
                    // (user zoomed back in above morphStartScale)
                    if (_semanticMorphController != null &&
                        !_semanticMorphController!.isActive &&
                        _semanticMorphController!.flashcardClusterId != null) {
                      _semanticMorphController!.flashcardClusterId = null;
                    }
                    return Transform(
                      transform: m,
                      child: ValueListenableBuilder<int>(
                        valueListenable: _knowledgeFlowController!.version,
                        builder: (_, __, ___) => CustomPaint(
                          painter: KnowledgeFlowPainter(
                            clusters: _clusterCache,
                            controller: _knowledgeFlowController!,
                            canvasScale: _canvasController.scale,
                            showSuggestions: false,
                            dragSourcePoint: _connectionDragSourcePoint,
                            dragCurrentPoint: _connectionDragCurrentPoint,
                            dragSourceClusterId: _connectionDragSourceClusterId,
                            snapTargetClusterId: _connectionSnapTargetClusterId,
                            animationTime: DateTime.now().millisecondsSinceEpoch % 10000 / 1000.0,
                            clusterTexts: _clusterTextCache,
                            selectedConnectionId: _editingLabelConnectionId,
                            thumbnails: _thumbnailCache != null
                                ? {for (final c in _clusterCache) if (_thumbnailCache!.hasThumbnail(c.id)) c.id: _thumbnailCache!.getThumbnail(c.id)!}
                                : const {},
                            semanticMorphProgress: _semanticMorphController?.morphProgress ?? 0.0,
                            semanticController: _semanticMorphController,
                            spaceSplitLineY: _spaceSplitController.isActive ? _spaceSplitController.splitLineY : null,
                            spaceSplitSpreadProgress: _spaceSplitController.isActive
                                ? (_spaceSplitController.spreadDistance / 200.0).clamp(0.0, 1.0)
                                : 0.0,
                            spaceSplitGhostDisplacements: _spaceSplitController.isActive
                                ? _spaceSplitController.ghostDisplacements
                                : const {},
                            spaceSplitIsHorizontal: _spaceSplitController.isActive
                                ? _spaceSplitController.axis == SplitAxis.horizontal
                                : false,
                            flightProgress: _canvasController.flightProgress,
                            flightPhase: _canvasController.flightPhase,
                            flightSourceClusterId: _canvasController.flightSourceClusterId,
                            flightTargetClusterId: _canvasController.flightTargetClusterId,
                            landingPulseProgress: _canvasController.landingPulseProgress,
                            landingPulseCenter: _canvasController.landingPulseCenter,
                            proactiveGaps: _proactiveGapsCache,
                            proactiveScan: _proactiveScanCache,
                            reviewSchedule: _reviewSchedule,
                          ),
                          size: Size.infinite,
                        ),
                      ),
                    );
                  },
                ),
            ),
          // 🌟 RADIAL EXPANSION: Ghost bubbles + charging pulse
          // Renders AFTER knowledge flow so bubbles appear on top of connections.
          if (_radialExpansionController != null &&
              _radialExpansionController!.phase != RadialExpansionPhase.idle)
            IgnorePointer(
              child: AnimatedBuilder(
                animation: _canvasController,
                builder: (context, _) => CustomPaint(
                  painter: RadialExpansionPainter(
                    controller: _radialExpansionController!,
                    canvasOffset: _canvasController.offset,
                    canvasScale: _canvasController.scale,
                    animationTime: DateTime.now().millisecondsSinceEpoch % 10000 / 1000.0,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
          _gestureLayerHost,
          // 🔥 VULKAN: Native GPU stroke overlay
          // 🖍️ Flutter live stroke: ALWAYS in tree, placed BELOW Vulkan texture.
          // For non-highlighter pens, Vulkan (above, at opacity 1.0) covers this.
          // For highlighter, Vulkan opacity = 0.0 → this Flutter stroke shows through.
          // NOTE: Do NOT conditionally hide — Vulkan may not be ready on first stroke.
          _currentStrokeHost,
          // 🌐 WEB: WebGPU overlay (replaces Texture widget on web)
          if (kIsWeb && _webGpuOverlayActive)
            const Positioned.fill(
              child: IgnorePointer(child: WebGpuOverlayView()),
            ),
          if (_vulkanTextureId != null)
            ValueListenableBuilder<double>(
              valueListenable: _vulkanTextureOpacity,
              builder: (_, opacity, child) {
                // 🚀 PERF: Skip Texture widget entirely when CAMetalLayer
                // direct overlay is active — strokes render to native layer.
                if (_vulkanStrokeOverlay.isDirectOverlayActive) {
                  return const SizedBox.shrink();
                }
                // 🚀 PERF: Skip Opacity widget at 1.0 — avoids potential
                // compositing layer creation by Impeller.
                if (opacity == 1.0) return child!;
                if (opacity == 0.0) return const SizedBox.shrink();
                return Opacity(opacity: opacity, child: child);
              },
              child: IgnorePointer(child: Texture(textureId: _vulkanTextureId!)),
            ),
          _remoteLiveStrokesHost,
          _pdfPlaceholdersHost,

          // 🚀 PERF: All conditional overlays wrapped in ValueListenableBuilder.
          // Drawing handlers increment _uiRebuildNotifier instead of setState,
          // so only this subtree rebuilds (not the entire widget tree).
          Positioned.fill(
            child: ValueListenableBuilder<int>(
            valueListenable: _uiRebuildNotifier,
            builder:
                (context, _, __) {
                  // 🚀 PERF: Determine if we're actively drawing freehand
                  // (not eraser, not pan). When true, hide non-essential
                  // overlays to reduce Impeller compositing layer count.
                  final isActivelyDrawingFreehand =
                      _isDrawingNotifier.value &&
                      !_effectiveIsEraser &&
                      !_effectiveIsPanMode;

                  return Stack(
                   children: [
                    // 🖊️ STYLUS HOVER: Hidden during active drawing (finger/pen is down)
                    if (!isActivelyDrawingFreehand)
                      const StylusHoverOverlay(),
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

                    // 📐 SECTION DRAG/RESIZE HIGHLIGHT OVERLAY
                    if (_draggingSectionNode != null ||
                        _resizingSectionNode != null)
                      IgnorePointer(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: _SectionHighlightPainter(
                              section:
                                  _draggingSectionNode ?? _resizingSectionNode!,
                              controller: _canvasController,
                              isResizing: _resizingSectionNode != null,
                            ),
                            size: Size.infinite,
                          ),
                        ),
                      ),

                    // 📐 TECHNICAL PEN: Snap guide + measurements
                    if (_techSnapAnchor != null &&
                        _techSnapAngleDeg != null &&
                        _isDrawingNotifier.value &&
                        _effectivePenType == ProPenType.technicalPen &&
                        _brushSettings.techShowGuides)
                      IgnorePointer(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: _TechPenGuidePainter(
                              anchor: _techSnapAnchor!,
                              angleDeg: _techSnapAngleDeg!,
                              segmentLength: _techSegmentLength ?? 0.0,
                              controller: _canvasController,
                              color: _effectiveColor,
                              nearStartPoint: _techNearStartPoint,
                              startPoint: (_currentStrokeNotifier.value.isNotEmpty)
                                  ? _currentStrokeNotifier.value.first.position
                                  : null,
                              straightGhostEnd: _techStraightGhostEnd,
                              intersections: _techIntersections,
                            ),
                            size: Size.infinite,
                          ),
                        ),
                      ),

                    // 🔲 TECHNICAL PEN: Visible grid dots
                    if (_isDrawingNotifier.value &&
                        _effectivePenType == ProPenType.technicalPen &&
                        _brushSettings.techGridSnap &&
                        _brushSettings.techShowGuides)
                      IgnorePointer(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: _TechPenGridPainter(
                              gridSize: _brushSettings.techGridSize,
                              controller: _canvasController,
                              color: _effectiveColor,
                            ),
                            size: Size.infinite,
                          ),
                        ),
                      ),

                    // 🗺️ SECTION NAVIGATOR PANEL
                    if (_isSectionActive && !isActivelyDrawingFreehand)
                      _buildSectionNavigator(),

                    // 📌 RECORDING PINS OVERLAY — hidden during drawing
                    if ((_recordingPins.isNotEmpty || _isPinPlacementMode) &&
                        !isActivelyDrawingFreehand)
                      _buildRecordingPinsOverlay(context),

                    // 🎤 SYNCHRONIZED PLAYBACK OVERLAY (Locale)
                    if (widget.externalPlaybackController != null &&
                        !isActivelyDrawingFreehand)
                      _buildLocalPlaybackOverlay(context),

                    // 🎤 LIVE SUBTITLE OVERLAY — shown during recording when enabled
                    if (!isActivelyDrawingFreehand)
                      _buildLiveSubtitleOverlay(context),

                    // 🔲 REMOTE VIEWPORT & PRESENCE OVERLAYS — hidden during drawing
                    if (!isActivelyDrawingFreehand)
                      ..._buildRemoteOverlays(context),

                    // 🛠️ STANDARD OVERLAYS (Lasso, Selection, Pen, Ruler, Text)
                    ..._buildStandardOverlays(context),

                    // 🏗️ ERASER OVERLAYS
                    ..._buildEraserOverlays(context),



                    // 💥 SCRATCH-OUT PARTICLE DISSOLVE
                    if (_scratchOutAnimating && _scratchOutParticles.isNotEmpty)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: _ScratchOutParticleWidget(
                            particles: _scratchOutParticles,
                            bounds: _scratchOutBounds ?? Rect.zero,
                            canvasController: _canvasController,
                            deleteCount: _scratchOutParticles.length,
                          ),
                        ),
                      ),

                    // 📏 Ruler & Digital Text overlays
                    ..._buildToolOverlays(context),

                    // 🎵 Synchronized Playback Overlay (Recorded)
                    if (_isPlayingSyncedRecording &&
                        _playbackController != null)
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

                    // 🎵 Audio Mini-Player — hidden during drawing
                    if (_isPlayingAudio && !isActivelyDrawingFreehand)
                      _buildAudioMiniPlayer(context),

                    // 🎨 Floating Color Disc — always visible in drawing mode
                    if (!_effectiveIsEraser &&
                        !_effectiveIsPanMode &&
                        !isActivelyDrawingFreehand)
                      FloatingColorDisc(
                        color: _effectiveSelectedColor,
                        recentColors: _recentColors,
                        strokeSize: _toolController.width,
                        onStrokeSizeChanged: (s) {
                          _toolController.setStrokeWidth(s);
                          setState(() {});
                        },
                        onColorChanged: (c) {
                          _toolController.setColor(c);
                          // Track recent colors (deduped, max 6)
                          _recentColors.remove(c);
                          _recentColors.insert(0, c);
                          if (_recentColors.length > 6) _recentColors.removeLast();
                          setState(() {});
                        },
                        onExpand: () async {
                          final picked = await showProColorPicker(
                            context: context,
                            currentColor: _effectiveSelectedColor,
                            onEyedropperRequested: () {
                              Navigator.pop(context);
                              _launchEyedropperFromCanvas();
                            },
                          );
                          if (picked != null && mounted) {
                            _toolController.setColor(picked);
                            setState(() {});
                          }
                        },
                      ),

                    // ↩️ Action Flash Overlay (Undo/Redo HUD feedback)
                    ActionFlashOverlay(key: _actionFlashKey),
                  ],
                );
              },
            ),  // close ValueListenableBuilder
          ),  // close Positioned.fill
        ],
      ),
    );
  }

  /// 🎨 LAYER 0: SFONDO VIEWPORT-LEVEL
  Widget _buildBackgroundLayer() {
    // ✅ KEEP RepaintBoundary — BackgroundPainter repaints on every pan/zoom
    // (via _canvasController listenable). Without RPB, repaint cascades to
    // ALL sibling layers in the Stack → catastrophic overdraw.
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
              return AnimatedBuilder(
                animation: _canvasController,
                builder: (context, child) {
                  // 🚀 Apply pan/zoom/rotation at widget level.
                  // The CustomPaint child is cached by the RepaintBoundary
                  // and only re-rasterized when strokes change (shouldRepaint).
                  // Pan/zoom only changes the Transform matrix → GPU compositing.
                  final m =
                      Matrix4.identity()..translate(
                        _canvasController.offset.dx,
                        _canvasController.offset.dy,
                      );
                  if (_canvasController.rotation != 0.0) {
                    m.rotateZ(_canvasController.rotation);
                  }
                  m.scale(_canvasController.scale);

                  // 🚀 LOD DEBOUNCE: detect LOD tier change during zoom.
                  // After zoom settles (300ms), trigger DrawingPainter rebuild
                  // which starts progressive tile-by-tile LOD rendering.
                  final s = _canvasController.scale;
                  final tier = s < 0.2 ? 2 : (s < 0.5 ? 1 : 0);
                  if (tier != _lastWidgetLodTier) {
                    _lastWidgetLodTier = tier;
                    _lodDebounceTimer?.cancel();
                    _lodDebounceTimer = Timer(
                      const Duration(milliseconds: 150),
                      () {
                        if (mounted) {
                          _layerController.notifyListeners();
                          _imageRepaintNotifier
                              .value++; // 🚀 Also repaint images for LOD
                        }
                      },
                    );
                  }

                  return Transform(transform: m, child: child);
                },
                child: RepaintBoundary(
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
                        devicePixelRatio:
                            MediaQuery.of(context).devicePixelRatio,
                        adaptiveConfig: _renderingConfig,
                        layers: _layerController.layers,
                        eraserPreviewIds: _eraserPreviewIds,
                        scratchOutPreviewIds: _scratchOutPreviewIds,
                        scratchOutDissolveMap: _scratchOutDissolveMap,
                        controller:
                            _canvasController, // 🚀 viewport-level mode (for culling)
                        pdfPainters: _pdfPainters,
                        onPdfRepaint: () {
                          if (mounted) {
                            _pdfLayoutVersion++;
                            setState(() {});
                          }
                        },
                        pdfSearchController:
                            _pdfSearchController, // 🔍 Search highlights
                        pdfLayoutVersion:
                            _pdfLayoutVersion, // 📄 Layout mutation counter
                        showPdfPageNumbers: _showPdfPageNumbers,
                        surface: _activeSurface, // 🧬 Programmable materiality
                        paperType: _paperType, // 🚀 LAYER MERGE
                        backgroundColor:
                            _canvasBackgroundColor, // 🚀 LAYER MERGE
                        isActivelyDrawing:
                            _isDrawingNotifier.value && !_effectiveIsEraser,
                      ),
                      isComplex:
                          true, // 🚀 RASTER: hint to cache raster output aggressively
                      willChange:
                          false, // Only changes at stroke end, not every frame
                      size: Size.infinite,
                    ),
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
  /// 🚀 Uses AnimatedBuilder > Transform > RepaintBoundary for GPU compositing.
  Widget _buildImageLayer() {
    return ListenableBuilder(
      listenable: _layerController,
      builder: (context, _) {
        // 🚀 LAYER MERGE #2: Skip entire RPB layer when no images
        if (_imageElements.isEmpty) return const SizedBox.shrink();

        final dpr = MediaQuery.of(context).devicePixelRatio;
        // 🔧 FIX: Listen to _currentEditingStrokeNotifier so ImagePainter
        // repaints on every pen move during image editing mode.
        return ValueListenableBuilder<ProStroke?>(
          valueListenable: _currentEditingStrokeNotifier,
          builder: (context, editingStroke, _) {
            return AnimatedBuilder(
              animation: _canvasController,
              builder: (context, child) {
                // 🚀 Apply pan/zoom/rotation at widget level.
                // The CustomPaint child is cached by the RepaintBoundary
                // and only re-rasterized when images change (shouldRepaint).
                // Pan/zoom only changes the Transform matrix → GPU compositing.
                final m =
                    Matrix4.identity()..translate(
                      _canvasController.offset.dx,
                      _canvasController.offset.dy,
                    );
                if (_canvasController.rotation != 0.0) {
                  m.rotateZ(_canvasController.rotation);
                }
                m.scale(_canvasController.scale);

                return Transform(transform: m, child: child);
              },
              child: RepaintBoundary(
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
                      microThumbnails: _imageStubManager.microThumbnails,
                      imageRepaintNotifier: _imageRepaintNotifier,
                    ),
                    isComplex: true,
                    willChange: false,
                    size: Size.infinite,
                  ),
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
            onLongPressMoveUpdate: _isMultiPageEditMode ? null : _onLongPressMoveUpdate,
            onLongPressEnd: _isMultiPageEditMode ? null : _onLongPressEnd,
            onSpaceSplitStart: _onSpaceSplitStart,
            onSpaceSplitUpdate: _onSpaceSplitUpdate,
            onSpaceSplitEnd: _onSpaceSplitEnd,
            // ✌️ MULTI-FINGER TAP: 2-finger tap = Undo, 3-finger tap = Redo
            onTwoFingerTap: () {
              if (_layerController.canUndo) {
                _layerController.undo();
                HapticFeedback.mediumImpact();
                _actionFlashKey.currentState?.showUndo();
              }
            },
            onThreeFingerTap: () {
              if (_layerController.canRedo) {
                _layerController.redo();
                HapticFeedback.mediumImpact();
                _actionFlashKey.currentState?.showRedo();
              }
            },
            enableSingleFingerPan:
                _effectiveIsPanMode ||
                _isMultiPageEditMode, // 🖐️ Pan with a finger when active OR in multi-page edit
            // 📄 Intercept pan on PDF pages → route to draw callbacks for document drag
            onPanInterceptTest:
                _effectiveIsPanMode
                    ? (canvasPos) {
                      // 🖼️ If an image is selected, check if touch hits the
                      // image, its handles, or another image. Return false for
                      // empty space so canvas pan still works.
                      if (_imageTool.selectedImage != null) {
                        final sel = _imageTool.selectedImage!;
                        final rawImage = _loadedImages[sel.imagePath];
                        if (rawImage != null) {
                          final crop = sel.cropRect;
                          final w = rawImage.width.toDouble();
                          final h = rawImage.height.toDouble();
                          final imageSize =
                              crop != null
                                  ? Size(
                                    (crop.right - crop.left) * w,
                                    (crop.bottom - crop.top) * h,
                                  )
                                  : Size(w, h);
                          // Check rotation handle
                          if (_imageTool.hitTestRotationHandle(
                            canvasPos,
                            imageSize,
                          )) {
                            return true;
                          }
                          // Check resize handles
                          if (_imageTool.hitTestResizeHandle(
                                canvasPos,
                                imageSize,
                              ) !=
                              null) {
                            return true;
                          }
                          // Check if touch hits the selected image body
                          if (_imageTool.hitTest(sel, canvasPos, imageSize)) {
                            return true;
                          }
                        }
                        // Touch is on empty space — fall through to check
                        // other images and PDFs below
                      }

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
                      // 🧠 KNOWLEDGE FLOW: Cluster drag → route to draw callbacks
                      if (_isConnectionDragging) return true;

                      // 🔥 FIX: Tapping empty space in pan mode must deselect
                      // the image. _onDrawStart is never called here because
                      // we return false (canvas pan), so the deselect logic
                      // there is unreachable.
                      if (_imageTool.selectedImage != null) {
                        setState(() {
                          _imageTool.clearSelection();
                        });
                        _gestureRebuildNotifier.value++;
                        _imageRepaintNotifier.value++;
                        _uiRebuildNotifier.value++;
                      }
                      // 🧠 KNOWLEDGE FLOW: Tap connection → open label editor
                      if (_knowledgeFlowController != null &&
                          _clusterCache.isNotEmpty) {
                        final scale = _canvasController.scale;
                        final hitConn = _knowledgeFlowController!.hitTestConnection(
                          canvasPos, _clusterCache, maxDistance: 20.0 / scale,
                        );
                        if (hitConn != null) {
                          final midCanvas = _knowledgeFlowController!.getConnectionMidpoint(
                            hitConn, _clusterCache,
                          );
                          if (midCanvas != null) {
                            final screenPos = _canvasController.canvasToScreen(midCanvas);
                            setState(() {
                              _editingLabelConnectionId = hitConn.id;
                              _labelOverlayScreenPosition = screenPos;
                            });
                            HapticFeedback.selectionClick();
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
            // 🖐️ PALM REJECTION: compute exclusion zone from HandednessSettings
            palmExclusionZone: HandednessSettings.instance.getPalmExclusionZone(viewportSize),
            blockPanZoom: () =>
                _digitalTextTool.isResizing ||
                _digitalTextTool.isDragging ||
                _imageTool.isResizing ||
                _imageTool.isDragging ||
                _imageTool.isRotating ||
                _tabularTool.isDragging ||
                _tabularTool.isResizing ||
                _isDraggingGraph ||
                _isResizingGraph ||
                _isConnectionDragging || // 🧠 Block pan during connection drag
                _isCurveDragging || // 🎨 Block pan during curve drag
                _isDraggingGraphSlider ||
                _lassoTool.isDragging || // 🔒 Block pan during lasso selection drag
                _isSelectionPinching || // 🤏 Block pan during selection pinch transform
                _imageTool
                    .isHandleRotating, // 🌀 Block only during active manipulation
            // 📈 Graph pinch-to-viewport zoom+pan (Desmos-style)
            onBlockedScale: (scale, focalDelta) {
              final node = _selectedGraphNode;
              if (node == null) return;
              // Capture initial viewport on first pinch frame
              if (!_graphPinchStarted) {
                _graphPinchStarted = true;
                _graphPinchInitXMin = node.xMin;
                _graphPinchInitXMax = node.xMax;
                _graphPinchInitYMin = node.yMin;
                _graphPinchInitYMax = node.yMax;
              }
              // Zoom: pinch-out (scale > 1) = zoom in (narrower range)
              final factor = 1.0 / scale;
              final cx = (_graphPinchInitXMin + _graphPinchInitXMax) / 2;
              final cy = (_graphPinchInitYMin + _graphPinchInitYMax) / 2;
              final hw = (_graphPinchInitXMax - _graphPinchInitXMin) / 2 * factor;
              final hh = (_graphPinchInitYMax - _graphPinchInitYMin) / 2 * factor;
              node.xMin = cx - hw;
              node.xMax = cx + hw;
              node.yMin = cy - hh;
              node.yMax = cy + hh;
              // Pan: convert screen delta to graph-space delta
              final canvasScale = _canvasController.scale;
              final dxGraph = -focalDelta.dx / canvasScale / node.graphWidth * (node.xMax - node.xMin);
              final dyGraph = focalDelta.dy / canvasScale / node.graphHeight * (node.yMax - node.yMin);
              node.xMin += dxGraph;
              node.xMax += dxGraph;
              node.yMin += dyGraph;
              node.yMax += dyGraph;
              node.invalidateCache();
              _layerController.sceneGraph.bumpVersion();
              DrawingPainter.triggerRepaint();
              _uiRebuildNotifier.value++;
            },
            // 🌀 IMAGE ROTATION: Two-finger rotate + scale on selected image
            // ⚡ shouldRouteToImageRotation is evaluated at GESTURE TIME, not build time.
            // The gesture detector widget is cached and may not rebuild when
            // pan mode or image selection changes — so we CANNOT rely on
            // conditional callbacks being set at build time.
            shouldRouteToImageRotation: (Offset screenFocalPoint) {
                // Mid-rotation: route immediately (no per-frame hit-test needed)
                if (_imageTool.isRotating) return true;
                // Only route to image rotation if the image is ALREADY selected
                // (via tap in pan mode). This preserves canvas zoom for unselected
                // images, allowing image viewer mode to trigger.
                final sel = _imageTool.selectedImage;
                if (sel == null) return false;
                final canvasPos = _canvasController.screenToCanvas(screenFocalPoint);
                final image = _loadedImages[sel.imagePath];
                if (image == null) return false;
                final rawW = image.width.toDouble();
                final rawH = image.height.toDouble();
                final crop = sel.cropRect;
                final imageSize = crop != null
                    ? Size((crop.right - crop.left) * rawW,
                           (crop.bottom - crop.top) * rawH)
                    : Size(rawW, rawH);
                return _imageTool.hitTest(sel, canvasPos, imageSize);
              },
            onImageScaleStart: _onImageScaleStart,
            onImageTransform: _onImageTransform,
            onImageScaleEnd: _onImageScaleEnd,
            // 🤏 SELECTION TRANSFORM: Two-finger rotate + scale on lasso selection
            shouldRouteToSelectionTransform: (Offset screenFocalPoint) {
              if (_isSelectionPinching) return true;
              if (!_lassoTool.hasSelection) {
                return false;
              }
              final canvasPos = _canvasController.screenToCanvas(screenFocalPoint);
              final inSel = _lassoTool.isPointInSelection(canvasPos);
              return inSel;
            },
            onSelectionScaleStart: _onSelectionScaleStart,
            onSelectionTransform: _onSelectionTransform,
            onSelectionScaleEnd: _onSelectionScaleEnd,
            onSelectionPinchCancel: _cancelSelectionPinch,
            onCancelLassoDrag: () {
              if (_lassoTool.isDragging) {
                _lassoTool.endDrag(skipReflow: true);
              }
            },
            // 🧠 SEMANTIC TAP: Tap on semantic nodes → flashcard preview
            onSingleTap: (screenPoint) {
              // 🧠 SEMANTIC VIEW: handle flashcard/node taps FIRST.
              // Must be checked before radial expansion so that tapping
              // "Zoom in →" on a flashcard isn't swallowed by a radial bubble.

              if (_semanticMorphController != null &&
                  _semanticMorphController!.isActive) {
                if (_handleSemanticNodeTap(screenPoint)) return true;
                final canvasPoint = _canvasController.screenToCanvas(screenPoint);
                if (_handleGhostConnectionTap(canvasPoint)) return true;
                if (_handleGravityLineTap(screenPoint)) return true;
                return false; // Let canvas handle it — don't touch radial in semantic mode
              }

              // 🌟 RADIAL EXPANSION: intercept bubble taps in pan mode
              // (only when NOT in semantic view)
              final canvasPointForRadial = _canvasController.screenToCanvas(screenPoint);
              if (_handleRadialExpansionDrawStart(canvasPointForRadial)) {
                // CRITICAL: onSingleTap never triggers _onDrawEnd.
                // If a bubble was hit we must finalize immediately here.
                if (_radialDraggedBubbleId != null) {
                  finalizeRadialBubbleDrag();
                }
                return true;
              }

              return false;
            },
            // 🔲 GESTURAL LASSO: Tap + Drag activates lasso without switching tools
            onGesturalLassoStart: _onGesturalLassoStart,
            onGesturalLassoUpdate: _onGesturalLassoUpdate,
            onGesturalLassoEnd: _onGesturalLassoEnd,
            onGesturalLassoArmed: () => HapticFeedback.lightImpact(),
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
  ///
  /// 🎨 FIX: Wrapped in ListenableBuilder(_toolController) so that the
  /// painter is reconstructed when the user changes pen type, color, width,
  /// or brush settings. Without this, the `late final` caching of
  /// _currentStrokeHost caused the painter to keep stale parameters
  /// (e.g. highlighter rendered as ballpoint).
  Widget _buildCurrentStrokeLayer() {
    return ListenableBuilder(
      listenable: _toolController,
      builder: (_, __) {
        // 🚀 PERF: When Vulkan handles the stroke (non-highlighter), skip
        // the entire CustomPaint + RepaintBoundary. Even with repaint: null,
        // the RPB creates a GPU compositing layer that costs ~0.5-1ms/frame.
        if (_vulkanOverlayActive && _effectivePenType != ProPenType.highlighter) {
          return const SizedBox.shrink();
        }

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
                useNativeOverlay: _vulkanOverlayActive, // 🔥 Skip Dart when Vulkan handles it
              ),
              size: Size.infinite,
            ),
          ),
        );
      },
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

  /// 🎤 SYNCHRONIZED PLAYBACK OVERLAY (Local — Split View)
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

  /// 🗺️ Floating section navigator panel — lists all sections.
  Widget _buildSectionNavigator() {
    final sceneGraph = _layerController.sceneGraph;
    final sections = <SectionNode>[];
    for (final layer in sceneGraph.layers) {
      for (final child in layer.children) {
        if (child is SectionNode && child.isVisible) {
          sections.add(child);
        }
      }
    }
    if (sections.isEmpty) return const SizedBox.shrink();

    return Positioned(
      top: 100,
      right: 16,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            width: 180,
            constraints: const BoxConstraints(maxHeight: 280),
            decoration: BoxDecoration(
              color: const Color(0xCC1A1A2E),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                  child: Row(
                    children: [
                      Icon(
                        Icons.dashboard_rounded,
                        size: 14,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Sections',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${sections.length}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
                // Section list
                Flexible(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    shrinkWrap: true,
                    itemCount: sections.length,
                    itemBuilder: (ctx, idx) {
                      final s = sections[idx];
                      final bg = s.backgroundColor ?? const Color(0xFF2A2A3E);
                      final dims =
                          '${s.sectionSize.width.round()}×${s.sectionSize.height.round()}';
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          final tx = s.worldTransform.getTranslation();
                          final sectionRect = Rect.fromLTWH(
                            tx.x,
                            tx.y,
                            s.sectionSize.width,
                            s.sectionSize.height,
                          );
                          // Direct camera jump (bypass animation)
                          final vp = MediaQuery.of(context).size;
                          final scaleX = (vp.width * 0.8) / sectionRect.width;
                          final scaleY = (vp.height * 0.8) / sectionRect.height;
                          final targetScale = scaleX < scaleY ? scaleX : scaleY;
                          final cx = sectionRect.left + sectionRect.width / 2;
                          final cy = sectionRect.top + sectionRect.height / 2;
                          final ox = vp.width / 2 - cx * targetScale;
                          final oy = vp.height / 2 - cy * targetScale;
                          _canvasController.setScale(targetScale);
                          _canvasController.setOffset(Offset(ox, oy));
                          setState(() {});
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: bg,
                                  borderRadius: BorderRadius.circular(3),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.15),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  s.sectionName,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.85),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (s.isLocked) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.lock_rounded,
                                  size: 10,
                                  color: Colors.white.withValues(alpha: 0.3),
                                ),
                              ],
                              const SizedBox(width: 6),
                              Text(
                                dims,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.3),
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
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

/// 💥 Particle data for scratch-out dissolve effect.
class _ScratchOutParticle {
  final Offset position;
  final Offset velocity;
  final Color color;
  final double size;

  const _ScratchOutParticle({
    required this.position,
    required this.velocity,
    required this.color,
    required this.size,
  });
}

/// 🔴 Real-time preview overlay: highlights strokes that would be deleted.


/// 💥 Particle dissolve effect — colored particles fly out from deleted area.
class _ScratchOutParticleWidget extends StatefulWidget {
  final List<_ScratchOutParticle> particles;
  final Rect bounds;
  final InfiniteCanvasController canvasController;
  final int deleteCount;

  const _ScratchOutParticleWidget({
    required this.particles,
    required this.bounds,
    required this.canvasController,
    required this.deleteCount,
  });

  @override
  State<_ScratchOutParticleWidget> createState() =>
      _ScratchOutParticleWidgetState();
}

class _ScratchOutParticleWidgetState extends State<_ScratchOutParticleWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) {
        return CustomPaint(
          painter: _ScratchOutParticlePainter(
            particles: widget.particles,
            canvasController: widget.canvasController,
            progress: _anim.value,
            deleteCount: widget.deleteCount,
          ),
        );
      },
    );
  }
}

class _ScratchOutParticlePainter extends CustomPainter {
  final List<_ScratchOutParticle> particles;
  final InfiniteCanvasController canvasController;
  final double progress;
  final int deleteCount;

  static const double _gravity = 400.0; // px/s² downward

  _ScratchOutParticlePainter({
    required this.particles,
    required this.canvasController,
    required this.progress,
    required this.deleteCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final t = Curves.easeOut.transform(progress);
    final opacity = (1.0 - t).clamp(0.0, 1.0);
    if (opacity <= 0) return;

    final dt = progress * 0.5; // 500ms → 0.5s real time

    // 🚀 PAINT CACHE: Reuse single Paint, change color per particle
    final paint = Paint()..style = PaintingStyle.fill;

    for (final p in particles) {
      final screenPos = canvasController.canvasToScreen(p.position);
      final x = screenPos.dx + p.velocity.dx * dt;
      final y = screenPos.dy + p.velocity.dy * dt + 0.5 * _gravity * dt * dt;
      final s = p.size * (1.0 - t * 0.6);

      paint.color = p.color.withValues(alpha: opacity * 0.8);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, y), width: s, height: s),
          Radius.circular(s * 0.3),
        ),
        paint,
      );
    }

    // Count badge for large deletions
    if (deleteCount > 5 && t < 0.7) {
      final badgeOpacity = (1.0 - t / 0.7).clamp(0.0, 1.0);
      // Find center of particle cloud
      if (particles.isNotEmpty) {
        final centerScreen = canvasController.canvasToScreen(
          particles.first.position,
        );
        final badgePaint = Paint()
          ..color = Colors.red.withValues(alpha: badgeOpacity * 0.85)
          ..style = PaintingStyle.fill;
        final badgeRect = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(centerScreen.dx, centerScreen.dy - 30),
            width: 80,
            height: 28,
          ),
          const Radius.circular(14),
        );
        canvas.drawRRect(badgeRect, badgePaint);

        // Draw count text
        final tp = TextPainter(
          text: TextSpan(
            text: '🧹 $deleteCount',
            style: TextStyle(
              color: Colors.white.withValues(alpha: badgeOpacity),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(
            centerScreen.dx - tp.width / 2,
            centerScreen.dy - 30 - tp.height / 2,
          ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ScratchOutParticlePainter old) =>
      progress != old.progress;
}
