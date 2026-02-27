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

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      enableDrag:
          false, // Prevent swipe-down dismiss (conflicts with handwriting)
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        // Keyboard-aware sizing: calculate available height above keyboard
        // and push the sheet up with bottom padding.
        return Builder(
          builder: (ctx) {
            final mq = MediaQuery.of(ctx);
            final keyboardH = mq.viewInsets.bottom;
            final safeTop = mq.viewPadding.top;
            final maxAvailable = mq.size.height - safeTop;
            // Without keyboard: 85% of screen. With keyboard: fill above keyboard.
            final desired = maxAvailable * 0.85;
            final sheetH = desired.clamp(300.0, maxAvailable - keyboardH);

            return Padding(
              padding: EdgeInsets.only(bottom: keyboardH),
              child: SizedBox(
                height: sheetH,
                child: LatexEditorSheet(
                  initialLatex: initialSource,
                  initialFontSize: initialFontSize,
                  initialColor: initialColor,
                  recognizer: recognizer,
                  onConfirm: (latexSource, fontSize, color) {
                    Navigator.of(sheetContext).pop();

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
                    Navigator.of(sheetContext).pop();
                  },
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      // Deactivate LaTeX mode when the sheet is dismissed
      if (_toolController.isLatexMode) {
        _toolController.toggleLatexMode();
        setState(() {});
      }
    });
  }
}
