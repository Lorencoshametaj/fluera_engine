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

    setState(() {
      _inlineEditingElement = element;
      _isInlineEditing = true;
      _digitalTextTool.deselectElement();
    });
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
              _layerController.updateText(
                _digitalTextElements.firstWhere(
                  (e) => e.id == updatedElement.id,
                  orElse: () => updatedElement,
                ),
              );
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
              _layerController.addText(updatedElement);
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
      _digitalTextTool.selectElement(updatedElement);
    });

    // 🔑 Notify overlay subtree to rebuild (it's inside ValueListenableBuilder)
    _uiRebuildNotifier.value++;

    _broadcastTextChange(updatedElement);
    _autoSaveCanvas();
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

    // Check if pressed on a text element → inline editing
    final hitElement = _digitalTextTool.hitTest(
      canvasPosition,
      _digitalTextElements,
    );

    if (hitElement != null) {
      _startInlineTextEdit(hitElement);
    }
  }

  /// Syncs a text element updated by DigitalTextTool back into the canvas state.
  void _syncTextElementFromTool(DigitalTextElement updated) {
    final idx = _digitalTextElements.indexWhere((e) => e.id == updated.id);
    if (idx != -1) {
      _digitalTextElements[idx] = updated;
    }
    _layerController.updateText(updated);
    _broadcastTextChange(updated);
  }
}
