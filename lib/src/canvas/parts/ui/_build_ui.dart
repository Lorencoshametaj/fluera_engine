part of '../../nebula_canvas_screen.dart';

/// 📦 Build UI — orchestrator that delegates to:
///   • [_ui_toolbar.dart]      → _buildToolbar()
///   • [_ui_canvas_layer.dart] → _buildCanvasArea()
///   • [_ui_eraser.dart]       → _buildEraserOverlays()
///   • [_ui_overlays.dart]     → _buildRemoteOverlays(), _buildStandardOverlays(), _buildToolOverlays()
///   • [_ui_menus.dart]        → _buildMenus()
extension on _NebulaCanvasScreenState {
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
                  // 🛠️ Professional Toolbar
                  _buildToolbar(context),

                  // 🎨 Infinite Canvas with Zoom & Pan
                  _buildCanvasArea(context),
                ],
              ),

              // 🌀 Rotation Angle Indicator (reactive, floating pill)
              ListenableBuilder(
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

                  return Positioned(
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
                  );
                },
              ),

              // 🎯 Context Menus & Panels (above everything)
              ..._buildMenus(context),

              // 🔷 Shape recognition toast
              _buildShapeRecognitionToast(),

              // 👻 Ghost shape suggestion overlay
              _buildGhostSuggestionOverlay(),

              // 🎬 Loading overlay (splash screen during initialization)
              _buildLoadingOverlay(),

              // 🎛️ Design Variables: floating toggle button (top-right)
              Positioned(
                right: 12,
                top: 8,
                child: ToolbarVariableButton(
                  isActive: _showVariablePanel,
                  onTap: _toggleVariablePanel,
                  isDark: Theme.of(context).brightness == Brightness.dark,
                  variableCount: _totalVariableCount,
                ),
              ),

              // 🎛️ Design Variables: manager panel overlay
              _buildVariableManagerOverlay(),
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
