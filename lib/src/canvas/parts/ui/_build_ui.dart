part of '../../fluera_canvas_screen.dart';

/// 📦 Build UI — orchestrator that delegates to:
///   • [_ui_toolbar.dart]      → _buildToolbar()
///   • [_ui_canvas_layer.dart] → _buildCanvasArea()
///   • [_ui_eraser.dart]       → _buildEraserOverlays()
///   • [_ui_overlays.dart]     → _buildRemoteOverlays(), _buildStandardOverlays(), _buildToolOverlays()
///   • [_ui_menus.dart]        → _buildMenus()
extension on _FlueraCanvasScreenState {
  // ============================================================================
  // BUILD — Main entry point
  // ============================================================================

  Widget _buildImpl(BuildContext context) {
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

        // 📊 Tabular keyboard shortcuts (only on key down)
        if (event is KeyDownEvent &&
            _tabularTool.hasSelection &&
            _tabularTool.hasCellSelection) {
          final isCtrl =
              HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isMetaPressed;

          // Ctrl+C → Copy
          if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyC) {
            _copySelection();
            return KeyEventResult.handled;
          }
          // Ctrl+V → Paste
          if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyV) {
            _pasteAtSelection();
            return KeyEventResult.handled;
          }
          // Ctrl+X → Cut
          if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyX) {
            _cutSelection();
            return KeyEventResult.handled;
          }
          // Ctrl+B → Bold
          if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyB) {
            _toggleBold();
            return KeyEventResult.handled;
          }
          // Ctrl+I → Italic
          if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyI) {
            _toggleItalic();
            return KeyEventResult.handled;
          }

          // Delete / Backspace → Clear cells
          if (event.logicalKey == LogicalKeyboardKey.delete ||
              event.logicalKey == LogicalKeyboardKey.backspace) {
            _clearSelectedCells();
            return KeyEventResult.handled;
          }

          // Arrow keys → Navigate
          if (!isCtrl) {
            if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
              _moveUp();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
              _moveDownNav();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              _moveLeft();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
              _moveRightNav();
              return KeyEventResult.handled;
            }
          }

          // Escape → Deselect cell
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            _tabularTool.deselectCell();
            setState(() {});
            return KeyEventResult.handled;
          }
        }

        // 📊 Escape to deselect table
        if (event is KeyDownEvent &&
            _tabularTool.hasSelection &&
            !_tabularTool.hasCellSelection &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _tabularTool.deselectTabular();
          setState(() {});
          return KeyEventResult.handled;
        }

        // 🧭 Navigation keyboard shortcuts
        if (event is KeyDownEvent) {
          final isCtrl =
              HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isMetaPressed;
          final isShift = HardwareKeyboard.instance.isShiftPressed;

          // Ctrl+Shift+1 → Fit all content
          if (isCtrl &&
              isShift &&
              event.logicalKey == LogicalKeyboardKey.digit1) {
            CameraActions.fitAllContent(
              _canvasController,
              _layerController.sceneGraph,
              MediaQuery.of(context).size,
            );
            return KeyEventResult.handled;
          }

          // Ctrl+0 → Return to origin
          if (isCtrl && event.logicalKey == LogicalKeyboardKey.digit0) {
            CameraActions.returnToOrigin(
              _canvasController,
              MediaQuery.of(context).size,
            );
            return KeyEventResult.handled;
          }

          // Ctrl+M → Toggle minimap
          if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyM) {
            setState(() {
              _showMinimap = !_showMinimap;
            });
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
                  // 🛠️ Professional Toolbar (cached — skipped on parent setState)
                  _toolbarHost,

                  // 🎨 Canvas + Navigation Overlays
                  Expanded(
                    child: Stack(
                      children: [
                        RepaintBoundary(
                          key: _canvasRepaintBoundaryKey,
                          child: _buildCanvasArea(context),
                        ),

                        // 🔵 Navigation: Dot grid (orientation & alignment)
                        if (_showDotGrid)
                          Positioned.fill(
                            child: CanvasDotGrid(
                              controller: _canvasController,
                              canvasBackground: _canvasBackgroundColor,
                            ),
                          ),

                        // ✛ Navigation: Origin crosshair at (0,0)
                        Positioned.fill(
                          child: OriginCrosshair(
                            controller: _canvasController,
                            viewportSize: MediaQuery.of(context).size,
                            canvasBackground: _canvasBackgroundColor,
                          ),
                        ),

                        // 🧭 Navigation: Content Radar (directional indicators)
                        Positioned.fill(
                          child: IgnorePointer(
                            ignoring: false,
                            child: ContentRadarOverlay(
                              controller: _canvasController,
                              boundsTracker: _contentBoundsTracker,
                              viewportSize: MediaQuery.of(context).size,
                              canvasBackground: _canvasBackgroundColor,
                            ),
                          ),
                        ),

                        // 🗺️ Navigation: Minimap (bottom-right)
                        // Auto-hides when no content exists on the canvas.
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: ValueListenableBuilder<List>(
                            valueListenable: _contentBoundsTracker.regions,
                            builder: (context, regions, child) {
                              final hasContent = regions.isNotEmpty;
                              return CanvasMinimap(
                                controller: _canvasController,
                                boundsTracker: _contentBoundsTracker,
                                layerController: _layerController,
                                viewportSize: MediaQuery.of(context).size,
                                visible: _showMinimap && hasContent,
                                canvasBackground: _canvasBackgroundColor,
                                isDrawing: _isDrawingNotifier,
                                currentStroke: _currentStrokeNotifier,
                                currentStrokeColor: _effectiveColor,
                                remoteCursors: _realtimeEngine?.remoteCursors,
                              );
                            },
                          ),
                        ),

                        // 🔍 Navigation: Zoom Level Indicator (bottom-left)
                        Positioned(
                          bottom: 16,
                          left: 16,
                          child: ZoomLevelIndicator(
                            controller: _canvasController,
                            viewportSize: MediaQuery.of(context).size,
                            canvasBackground: _canvasBackgroundColor,
                            showGridActive: _showDotGrid,
                            onLongPress: () {
                              setState(() => _showDotGrid = !_showDotGrid);
                            },
                          ),
                        ),

                        // ↩ Navigation: "Return to content" FAB (centered, bottom)
                        Positioned(
                          bottom: 24,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: ReturnToContentFab(
                              controller: _canvasController,
                              boundsTracker: _contentBoundsTracker,
                              layerController: _layerController,
                              viewportSize: MediaQuery.of(context).size,
                              canvasBackground: _canvasBackgroundColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // 🌀 Rotation Angle Indicator (reactive, floating pill)
              Positioned.fill(
                child: ListenableBuilder(
                  listenable: _canvasController,
                  builder: (context, _) {
                    final rotation = _canvasController.rotation;
                    if (rotation == 0.0) return const SizedBox.shrink();

                    final isSnapped =
                        _canvasController.checkSnapAngle(rotation) != null;
                    final pillColor =
                        isSnapped
                            ? Colors.blue.withValues(alpha: 0.85)
                            : Colors.black.withValues(alpha: 0.65);

                    return Stack(
                      children: [
                        Positioned(
                          bottom: 24,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: IgnorePointer(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: pillColor,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Transform.rotate(
                                      angle: rotation,
                                      child: Icon(
                                        isSnapped
                                            ? Icons.check_circle_rounded
                                            : Icons.navigation_rounded,
                                        color: Colors.white,
                                        size: 14,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _canvasController.rotationDegrees,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

              // 🎯 Context Menus & Panels (above everything)
              ..._buildMenus(context),

              // 🔷 Shape recognition toast
              _buildShapeRecognitionToast(),

              // 👻 Ghost shape suggestion overlay
              _buildGhostSuggestionOverlay(),

              // 🎬 Loading overlay (splash screen during initialization)
              _buildLoadingOverlay(),

              // ⏱️ Time Travel overlay (timeline + controls)
              if (_isTimeTravelMode && _timeTravelEngine != null)
                TimeTravelTimelineWidget(
                  engine: _timeTravelEngine!,
                  onExit: _exitTimeTravelMode,
                  onExportRequested: _exportTimelapse,
                  onNewBranch: _createBranchFromCurrentPosition,
                  onBranchExplorer: _openBranchExplorer,
                  onRecoverRequested: () {
                    // Recover current state elements into the present
                    final layers = _timeTravelEngine!.currentLayers;
                    final strokes =
                        layers
                            .where((l) => l.isVisible)
                            .expand((l) => l.strokes)
                            .toList();
                    final shapes =
                        layers
                            .where((l) => l.isVisible)
                            .expand((l) => l.shapes)
                            .toList();
                    final images =
                        layers
                            .where((l) => l.isVisible)
                            .expand((l) => l.images)
                            .toList();
                    final texts =
                        layers
                            .where((l) => l.isVisible)
                            .expand((l) => l.texts)
                            .toList();
                    _recoverElementsFromPast(strokes, shapes, images, texts);
                  },
                  activeBranchName: _activeBranchName,
                ),

              // 🧠 Conscious Architecture: debug overlay (debug builds only)
              // if (kDebugMode) const ConsciousDebugOverlay(),

              // 🏎️ Performance Monitor: frame time overlay (debug + profile)
              if (!kReleaseMode)
                CanvasPerformanceMonitor.instance.buildDebugOverlay(),
            ],
          ),
        ),
      ),
    ); // Focus + Scaffold
  }

  /// Resolve the currently active PDF document for toolbar interaction.
  ///
  /// Uses [_activePdfDocumentId] if set and found, otherwise falls back to
  /// the first [PdfDocumentNode] in the layer tree.
  PdfDocumentNode? get _activePdfDocument {
    if (_activePdfDocumentId != null) {
      final found = _findPdfDocumentById(_activePdfDocumentId!);
      if (found != null) return found;
    }
    return _findFirstPdfDocument();
  }

  /// Find the first [PdfDocumentNode] in the layer tree.
  PdfDocumentNode? _findFirstPdfDocument() {
    for (final layer in _layerController.layers) {
      for (final child in layer.node.children) {
        if (child is PdfDocumentNode) return child;
      }
    }
    return null;
  }

  /// Find all [PdfDocumentNode]s in the layer tree.
  List<PdfDocumentNode> _findAllPdfDocuments() {
    final docs = <PdfDocumentNode>[];
    for (final layer in _layerController.layers) {
      for (final child in layer.node.children) {
        if (child is PdfDocumentNode) docs.add(child);
      }
    }
    return docs;
  }

  /// Find a specific [PdfDocumentNode] by its document ID.
  PdfDocumentNode? _findPdfDocumentById(String documentId) {
    for (final layer in _layerController.layers) {
      for (final child in layer.node.children) {
        if (child is PdfDocumentNode && child.id == documentId) return child;
      }
    }
    return null;
  }
}
