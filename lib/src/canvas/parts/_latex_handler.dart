part of '../fluera_canvas_screen.dart';

/// 🧮 LaTeX Handler — manages the LaTeX editor sheet lifecycle.
///
/// Shows [LatexEditorSheet] as a bottom sheet, handles node creation
/// via the command history system, and wires up the ML recognizer warm-up.
extension FlueraCanvasLatexHandler on _FlueraCanvasScreenState {
  /// Lazily-initialized OCR recognizer for camera mode.
  static HmeLatexRecognizer? _latexRecognizer;

  /// Get or create the HmeLatexRecognizer (singleton per session).
  Future<HmeLatexRecognizer> _getLatexRecognizer() async {
    if (_latexRecognizer == null) {
      _latexRecognizer = HmeLatexRecognizer();
      await _latexRecognizer!.initialize();
    }
    return _latexRecognizer!;
  }

  /// Show the LaTeX editor bottom sheet.
  ///
  /// When confirmed, creates a [LatexNode] at the current viewport center
  /// using [AddLatexNodeCommand] for undo/redo support.
  void _showLatexEditorSheet({LatexNode? existingNode}) async {
    final initialSource = existingNode?.latexSource ?? '';
    final initialFontSize = existingNode?.fontSize ?? 24.0;
    final initialColor = existingNode?.color ?? _effectiveSelectedColor;

    // Initialize recognizer in background (non-blocking)
    final recognizer = await _getLatexRecognizer();

    if (!mounted) return;

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder:
            (routeContext) => LatexEditorSheet(
              initialLatex: initialSource,
              initialFontSize: initialFontSize,
              initialColor: initialColor,
              recognizer: recognizer,
              onInsertGraphToCanvas: (latexSource, xMin, xMax, yMin, yMax, curveColor) {
                // Create FunctionGraphNode at viewport center
                final viewportSize = MediaQuery.of(context).size;
                final screenCenter = Offset(viewportSize.width / 2, viewportSize.height / 2);
                final center = _canvasController.screenToCanvas(screenCenter);

                final graphNode = FunctionGraphNode(
                  id: NodeId(generateUid()),
                  latexSource: latexSource,
                  xMin: xMin,
                  xMax: xMax,
                  yMin: yMin,
                  yMax: yMax,
                  curveColorValue: curveColor,
                );

                // Place at viewport center
                graphNode.localTransform.setTranslationRaw(
                  center.dx - graphNode.graphWidth / 2,
                  center.dy - graphNode.graphHeight / 2,
                  0,
                );

                // Add to active layer (NOT rootNode — renderer only traverses layers)
                final activeLayer = _layerController.activeLayer;
                if (activeLayer == null) return;
                activeLayer.node.add(graphNode);

                _layerController.sceneGraph.bumpVersion();
                setState(() {});
                _autoSaveCanvas();

                // ✨ P5: Animated insertion (scale 0.85 → 1.0 with elastic ease)
                graphNode.localTransform.scale(0.85);
                _layerController.sceneGraph.bumpVersion();

                // Animate over ~400ms using frame callbacks
                final startMs = DateTime.now().millisecondsSinceEpoch;
                const durationMs = 400;
                void _animateScale() {
                  if (!mounted) return;
                  final elapsed = DateTime.now().millisecondsSinceEpoch - startMs;
                  final t = (elapsed / durationMs).clamp(0.0, 1.0);

                  // ElasticOut approximation
                  final scale = t >= 1.0
                      ? 1.0
                      : 1.0 - (1.0 - t) * (1.0 - t) * (0.5 * (1.0 - t) - 0.15) * -6.0;
                  final effectiveScale = (0.85 + (1.0 - 0.85) * scale.clamp(0.0, 1.2)).clamp(0.85, 1.05);

                  // Reset transform and reapply translation + scale
                  graphNode.localTransform.setIdentity();
                  graphNode.localTransform.setTranslationRaw(
                    center.dx - graphNode.graphWidth / 2,
                    center.dy - graphNode.graphHeight / 2,
                    0,
                  );
                  if (effectiveScale != 1.0) {
                    graphNode.localTransform.scale(effectiveScale);
                  }
                  _layerController.sceneGraph.bumpVersion();
                  DrawingPainter.invalidateAllTiles();
                  _uiRebuildNotifier.value++;

                  if (t < 1.0) {
                    WidgetsBinding.instance.addPostFrameCallback((_) => _animateScale());
                  }
                }
                WidgetsBinding.instance.addPostFrameCallback((_) => _animateScale());
              },
              onConfirm: (latexSource, fontSize, color) {
                Navigator.of(routeContext).pop();

                if (latexSource.trim().isEmpty) return;

                if (existingNode != null) {
                  // Update existing node
                  _commandHistory.execute(
                    UpdateLatexSourceCommand(
                      node: existingNode,
                      newSource: latexSource,
                    ),
                  );
                  if (fontSize != existingNode.fontSize) {
                    _commandHistory.execute(
                      UpdateLatexFontSizeCommand(
                        node: existingNode,
                        newFontSize: fontSize,
                      ),
                    );
                  }
                  if (color != existingNode.color) {
                    _commandHistory.execute(
                      UpdateLatexColorCommand(
                        node: existingNode,
                        newColor: color,
                      ),
                    );
                  }
                } else {
                  // Create new LaTeX node at viewport center
                  final viewportSize = MediaQuery.of(context).size;
                  final center = Offset(
                    (_canvasController.offset.dx.abs() +
                            viewportSize.width / 2) /
                        _canvasController.scale,
                    (_canvasController.offset.dy.abs() +
                            viewportSize.height / 2) /
                        _canvasController.scale,
                  );

                  final node = LatexNode(
                    id: NodeId(generateUid()),
                    latexSource: latexSource,
                    fontSize: fontSize,
                    color: color,
                  );

                  // Set translation to place at viewport center
                  node.localTransform.setTranslationRaw(
                    center.dx,
                    center.dy,
                    0,
                  );

                  // Add to the scene graph root
                  final rootGroup = _layerController.sceneGraph.rootNode;
                  _commandHistory.execute(
                    AddLatexNodeCommand(parent: rootGroup, latexNode: node),
                  );
                }

                // Bump version + save
                _layerController.sceneGraph.bumpVersion();
                setState(() {});
                _autoSaveCanvas();
              },
              onCancel: () {
                Navigator.of(routeContext).pop();
              },
            ),
      ),
    );

    // Deactivate LaTeX mode when the page is popped
    if (_toolController.isLatexMode) {
      _toolController.toggleLatexMode();
      setState(() {});
    }
  }
}
