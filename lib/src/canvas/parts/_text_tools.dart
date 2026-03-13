part of '../fluera_canvas_screen.dart';

/// 📦 Text Tools & Settings — extracted from _FlueraCanvasScreenState
extension on _FlueraCanvasScreenState {
  void _showSettings() {
    // Phase 2: CanvasSettingsDialog will be re-added
    // For now, use a minimal color-picker dialog
    showModalBottomSheet(
      context: context,
      builder:
          (ctx) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Canvas Settings',
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  children:
                      [
                            Colors.white,
                            Colors.black,
                            const Color(0xFFEEEEEE),
                            const Color(0xFF212121),
                          ]
                          .map(
                            (color) => GestureDetector(
                              onTap: () {
                                setState(() => _canvasBackgroundColor = color);
                                _autoSaveCanvas();
                                Navigator.pop(ctx);
                              },
                              child: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: color,
                                  border: Border.all(
                                    color:
                                        _canvasBackgroundColor == color
                                            ? Colors.blue
                                            : Colors.grey,
                                    width:
                                        _canvasBackgroundColor == color ? 3 : 1,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                ),
              ],
            ),
          ),
    );
  }

  /// Shows dialog for inserting digital text (fallback for OCR mode)
  Future<void> _showDigitalTextDialog() async {
    final result = await DigitalTextInputDialog.show(
      context,
      initialColor: _effectiveColor,
    );

    if (result != null && mounted) {
      final screenCenter = Offset(
        MediaQuery.of(context).size.width / 2,
        MediaQuery.of(context).size.height / 2,
      );
      final viewportCenter = _canvasController.screenToCanvas(screenCenter);

      final newElement = DigitalTextElement(
        id: generateUid(),
        text: result.text,
        position: viewportCenter,
        color: result.color,
        fontSize: result.fontSize,
        scale: 1.0,
        createdAt: DateTime.now(),
      );

      setState(() {
        _digitalTextElements.add(newElement);
        _digitalTextTool.selectElement(newElement);
      });

      _layerController.addText(newElement);
      _broadcastTextChange(newElement);
      _autoSaveCanvas();
    }
  }

  // ── Inline Text Creation ──────────────────────────────────────────────────

  /// 📝 Start inline text creation at a canvas position.
  /// Creates an empty text element and opens the inline editor overlay.
  void _startInlineTextCreation(Offset canvasPosition) {
    // 🔒 Cooldown: prevent spurious re-creation when keyboard dismissal
    // fires _onDrawStart immediately after _finishInlineText.
    if (_inlineTextFinishedAt != null &&
        DateTime.now().difference(_inlineTextFinishedAt!) < const Duration(milliseconds: 500)) {
      return;
    }
    // If already editing inline, finish the current one first
    if (_isInlineEditing) {
      _cancelInlineText();
    }

    _inlineTextColor = _effectiveColor;
    _inlineTextFontWeight = FontWeight.normal;
    _inlineTextFontStyle = FontStyle.normal;
    _inlineTextFontSize = 24.0;
    _inlineTextFontFamily = 'Roboto';
    _inlineTextShadow = null;
    _inlineTextBackgroundColor = null;
    _inlineTextDecoration = TextDecoration.none;
    _inlineTextAlign = TextAlign.left;
    _inlineTextLetterSpacing = 0.0;
    _inlineTextOpacity = 1.0;
    _inlineTextRotation = 0.0;
    _inlineTextOutlineColor = null;
    _inlineTextOutlineWidth = 0.0;
    _inlineTextGradientColors = null;

    final newElement = DigitalTextElement(
      id: generateUid(),
      text: '',
      position: canvasPosition,
      color: _inlineTextColor,
      fontSize: _inlineTextFontSize,
      fontWeight: _inlineTextFontWeight,
      fontStyle: _inlineTextFontStyle,
      scale: 1.0,
      createdAt: DateTime.now(),
    );

    setState(() {
      _inlineEditingElement = newElement;
      _isInlineEditing = true;
    });
    _uiRebuildNotifier.value++;
  }

  /// 📝 Start inline editing of an existing text element.
  void _startInlineTextEdit(DigitalTextElement element) {
    if (_isInlineEditing) {
      _cancelInlineText();
    }

    _inlineTextColor = element.color;
    _inlineTextFontWeight = element.fontWeight;
    _inlineTextFontStyle = element.fontStyle;
    _inlineTextFontSize = element.fontSize;
    _inlineTextFontFamily = element.fontFamily;
    _inlineTextShadow = element.shadow;
    _inlineTextBackgroundColor = element.backgroundColor;
    _inlineTextDecoration = element.textDecoration;
    _inlineTextAlign = element.textAlign;
    _inlineTextLetterSpacing = element.letterSpacing;
    _inlineTextOpacity = element.opacity;
    _inlineTextRotation = element.rotation;
    _inlineTextOutlineColor = element.outlineColor;
    _inlineTextOutlineWidth = element.outlineWidth;
    _inlineTextGradientColors = element.gradientColors;

    // deselectElement() already calls endDrag() internally

    setState(() {
      _inlineEditingElement = element;
      _isInlineEditing = true;
      _digitalTextTool.deselectElement();
    });
    _uiRebuildNotifier.value++;
  }

  /// 📝 Finish inline text editing — save the element.
  void _finishInlineText(String text) {
    final element = _inlineEditingElement;
    if (element == null || !mounted) return;

    final trimmedText = text.trim();
    if (trimmedText.isEmpty) {
      _cancelInlineText();
      return;
    }

    final existingIdx = _digitalTextElements.indexWhere(
      (e) => e.id == element.id,
    );

    final updatedElement = element.copyWith(
      text: trimmedText,
      color: _inlineTextColor,
      fontWeight: _inlineTextFontWeight,
      fontStyle: _inlineTextFontStyle,
      fontSize: _inlineTextFontSize,
      fontFamily: _inlineTextFontFamily,
      shadow: _inlineTextShadow,
      backgroundColor: _inlineTextBackgroundColor,
      textDecoration: _inlineTextDecoration,
      textAlign: _inlineTextAlign,
      letterSpacing: _inlineTextLetterSpacing,
      opacity: _inlineTextOpacity,
      rotation: _inlineTextRotation,
      outlineColor: _inlineTextOutlineColor,
      outlineWidth: _inlineTextOutlineWidth,
      gradientColors: _inlineTextGradientColors,
      modifiedAt: existingIdx != -1 ? DateTime.now() : null,
    );


    setState(() {
      if (existingIdx != -1) {
        // Use UpdateTextCommand for undo/redo
        final oldElement = _digitalTextElements[existingIdx];
        _commandHistory.execute(
          UpdateTextCommand(
            elements: _digitalTextElements,
            oldElement: oldElement,
            newElement: updatedElement,
            onChanged: () {
              if (mounted) setState(() {});
            },
          ),
        );
      } else {
        // Use AddTextCommand for undo/redo
        _commandHistory.execute(
          AddTextCommand(
            elements: _digitalTextElements,
            element: updatedElement,
            onChanged: () {
              if (mounted) setState(() {});
            },
          ),
        );
        // ✨ Track for entry animation
        _lastAddedTextId = updatedElement.id;
        _lastAddedTextTime = DateTime.now();
      }

      _isInlineEditing = false;
      _inlineEditingElement = null;
      // Don't auto-select — just leave the text on canvas
    });

    // 🔑 Notify overlay subtree to rebuild (it's inside ValueListenableBuilder)
    _uiRebuildNotifier.value++;

    _broadcastTextChange(updatedElement);
    _autoSaveCanvas();

    // 🔒 Set cooldown timestamp to prevent spurious re-creation
    _inlineTextFinishedAt = DateTime.now();
  }

  /// 📝 Cancel inline text editing.
  void _cancelInlineText() {
    if (!mounted) return;
    setState(() {
      _isInlineEditing = false;
      _inlineEditingElement = null;
    });
    _uiRebuildNotifier.value++;
  }

  /// 🗑️ Delete the currently inline-editing text element.
  void _deleteInlineTextElement() {
    final element = _inlineEditingElement;
    if (element == null || !mounted) return;

    final idx = _digitalTextElements.indexWhere((e) => e.id == element.id);

    setState(() {
      if (idx != -1) {
        // Use DeleteTextCommand for undo/redo
        _commandHistory.execute(
          DeleteTextCommand(
            elements: _digitalTextElements,
            element: _digitalTextElements[idx],
            onChanged: () {
              _layerController.removeText(element.id);
              if (mounted) setState(() {});
            },
          ),
        );
      }
      _isInlineEditing = false;
      _inlineEditingElement = null;
      _digitalTextTool.deselectElement();
    });

    _uiRebuildNotifier.value++;

    if (idx != -1) {
      HapticFeedback.mediumImpact();
      _autoSaveCanvas();
    }
  }

  /// Shows dialog for editing existing digital text (legacy, used for OCR)
  Future<void> _editDigitalTextElement(DigitalTextElement element) async {
    final result = await DigitalTextInputDialog.show(
      context,
      initialColor: element.color,
      initialText: element.text,
    );

    if (result != null && mounted) {
      final index = _digitalTextElements.indexOf(element);
      if (index != -1) {
        setState(() {
          _digitalTextElements[index] = DigitalTextElement(
            id: element.id,
            text: result.text,
            position: element.position,
            color: result.color,
            fontSize: result.fontSize,
            scale: element.scale,
            createdAt: element.createdAt,
            modifiedAt: DateTime.now(),
          );
          _digitalTextTool.selectElement(_digitalTextElements[index]);
        });

        _broadcastTextChange(_digitalTextElements[index]);
        _autoSaveCanvas();
      }
    }
  }

  /// Handles long press on canvas (for editing text)
  void _onLongPress(Offset canvasPosition) {
    // 🔒 VIEWER GUARD
    if (_checkViewerGuard()) return;

    // 📌 Check recording pins first
    if (_handleRecordingPinLongPress(canvasPosition)) return;

    // 📄 PDF Preview Card: long-press → enter full-screen reader
    final hitCard = _hitTestPdfPreviewCard(canvasPosition);
    if (hitCard != null) {
      _enterPdfReader(hitCard);
      return;
    }

    // 📈 FunctionGraphNode: long-press → enable graph move mode
    final hitGraph = _hitTestGraphNode(canvasPosition);
    if (hitGraph != null) {
      _selectedGraphNode = hitGraph;
      _isDraggingGraph = true;
      _isMovingGraph = true;
      _graphDragStart = canvasPosition;
      _graphPinchStarted = false;
      HapticFeedback.mediumImpact();
      _uiRebuildNotifier.value++;
      return;
    }

    // Check if pressed on a text element → inline editing
    final hitElement = _digitalTextTool.hitTest(
      canvasPosition,
      _digitalTextElements,
    );


    if (hitElement != null) {
      _startInlineTextEdit(hitElement);
      return;
    }

    // 🎨 Eyedropper fallback: long-press empty canvas → pick color
    // Matches Procreate's touch-and-hold behavior
    if (!_effectiveIsPanMode) {
      HapticFeedback.mediumImpact();
      _launchEyedropperFromCanvas();
    }
  }

  /// Launch eyedropper overlay from a canvas long-press.
  void _launchEyedropperFromCanvas() async {
    final picked = await showEyedropperOverlay(context: context);
    if (picked != null && mounted) {
      _toolController.setColor(picked);
      setState(() {});
    }
  }

  /// Syncs a text element updated by DigitalTextTool back into the canvas state.
  void _syncTextElementFromTool(DigitalTextElement updated) {
    final idx = _digitalTextElements.indexWhere((e) => e.id == updated.id);
    if (idx != -1) {
      _digitalTextElements[idx] = updated;
    }
    _broadcastTextChange(updated);
  }

  // ── Handwriting Recognition ────────────────────────────────────────────────

  /// ✍️ Recognize recent strokes as handwritten text and convert to digital text.
  Future<void> _recognizeHandwriting() async {
    final service = DigitalInkService.instance;

    if (!service.isAvailable) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Handwriting recognition is not available on this platform'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    // Initialize the service if needed
    if (!service.isReady) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Downloading handwriting model...'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      await service.init();
      if (!service.isReady) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not load handwriting model'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }
    }

    // Collect recent strokes from the active layer
    final strokes = _layerController.activeLayer?.strokes ?? [];
    if (strokes.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Draw something first, then tap Handwriting Recognition'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    // Collect all points from recent strokes
    final allPoints = <ProDrawingPoint>[];
    for (final stroke in strokes) {
      allPoints.addAll(stroke.points);
    }

    // Recognize
    final recognizedText = await service.recognizeStroke(allPoints);
    if (recognizedText == null || recognizedText.isEmpty || !mounted) return;

    // Show confirmation dialog
    final result = await HandwritingConfirmationDialog.show(
      context,
      recognizedText: recognizedText,
      languageCode: service.languageCode,
    );

    if (result == null || !mounted) return;

    // Create digital text element at the center of the strokes
    final screenCenter = Offset(
      MediaQuery.of(context).size.width / 2,
      MediaQuery.of(context).size.height / 2,
    );
    final canvasCenter = _canvasController.screenToCanvas(screenCenter);

    final newElement = DigitalTextElement(
      id: generateUid(),
      text: result.text,
      position: canvasCenter,
      color: _effectiveColor,
      fontSize: 24.0,
      scale: 1.0,
      createdAt: DateTime.now(),
    );

    setState(() {
      _digitalTextElements.add(newElement);
      _digitalTextTool.selectElement(newElement);
    });

    _layerController.addText(newElement);
    _broadcastTextChange(newElement);
    _autoSaveCanvas();

    // Optionally delete the original strokes
    if (result.deleteStrokes) {
      for (final stroke in strokes.toList()) {
        _layerController.removeStroke(stroke.id);
      }
      _layerController.sceneGraph.bumpVersion();
      DrawingPainter.invalidateAllTiles();
      setState(() {});
    }

    HapticFeedback.mediumImpact();
  }

  // ── OCR Scan ───────────────────────────────────────────────────────────────

  /// 📷 Show OCR scan dialog to recognize text from an image.
  Future<void> _showOcrScanDialog() async {
    final result = await OcrScanDialog.show(context);
    if (result == null || !mounted) return;

    final screenCenter = Offset(
      MediaQuery.of(context).size.width / 2,
      MediaQuery.of(context).size.height / 2,
    );
    final canvasCenter = _canvasController.screenToCanvas(screenCenter);

    if (result.mergeAll && result.fullText != null) {
      // Import as a single text element
      final newElement = DigitalTextElement(
        id: generateUid(),
        text: result.fullText!,
        position: canvasCenter,
        color: _effectiveColor,
        fontSize: 18.0,
        scale: 1.0,
        createdAt: DateTime.now(),
      );

      setState(() {
        _digitalTextElements.add(newElement);
        _digitalTextTool.selectElement(newElement);
      });

      _layerController.addText(newElement);
      _broadcastTextChange(newElement);
    } else if (result.blocks != null) {
      // Import individual blocks with relative positions
      final scaleX = 1.0 / result.imageWidth;
      final scaleY = 1.0 / result.imageHeight;

      for (final block in result.blocks!) {
        final relativeOffset = Offset(
          block.boundingBox.left * scaleX * 400, // Scale to ~400px canvas area
          block.boundingBox.top * scaleY * 400,
        );

        final newElement = DigitalTextElement(
          id: generateUid(),
          text: block.text,
          position: canvasCenter + relativeOffset,
          color: _effectiveColor,
          fontSize: 16.0,
          scale: 1.0,
          createdAt: DateTime.now(),
        );

        _digitalTextElements.add(newElement);
        _layerController.addText(newElement);
        _broadcastTextChange(newElement);
      }

      setState(() {});
    }

    _autoSaveCanvas();
    HapticFeedback.mediumImpact();
  }
}
