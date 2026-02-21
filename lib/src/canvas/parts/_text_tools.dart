part of '../nebula_canvas_screen.dart';

/// 📦 Text Tools & Settings — extracted from _NebulaCanvasScreenState
extension on _NebulaCanvasScreenState {
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
                            Colors.grey[200]!,
                            Colors.grey[900]!,
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

  /// Shows dialog for inserting digital text
  Future<void> _showDigitalTextDialog() async {
    final result = await DigitalTextInputDialog.show(
      context,
      initialColor: _effectiveColor,
    );

    if (result != null && mounted) {
      // Create text element at the center of the viewport
      // 🛠️ FIX: Use screenToCanvas to convert screen center to canvas coordinates
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
        // Auto-select the new element
        _digitalTextTool.selectElement(newElement);
      });

      // 🔄 Sync: notify delta tracker for synchronization
      _layerController.addText(newElement);

      // 🔴 RT: Broadcast new text to collaborators
      _broadcastTextChange(newElement);

      // 💾 Auto-save after adding digital text
      _autoSaveCanvas();
    }
  }

  /// Shows dialog for editing existing digital text (on long press)
  Future<void> _editDigitalTextElement(DigitalTextElement element) async {
    final result = await DigitalTextInputDialog.show(
      context,
      initialColor: element.color,
      initialText: element.text,
    );

    if (result != null && mounted) {
      // Find the element and update it
      final index = _digitalTextElements.indexOf(element);
      if (index != -1) {
        setState(() {
          // Replace with new updated element
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
          // Re-select the updated element
          _digitalTextTool.selectElement(_digitalTextElements[index]);
        });

        // 🔴 RT: Broadcast text change to collaborators
        _broadcastTextChange(_digitalTextElements[index]);

        // 💾 Auto-save after modifying digital text
        _autoSaveCanvas();
      }
    }
  }

  /// Handles long press on canvas (for editing text)
  void _onLongPress(Offset canvasPosition) {
    // 🔒 VIEWER GUARD
    if (_checkViewerGuard()) return;

    // Check if pressed on a text element
    final hitElement = _digitalTextTool.hitTest(
      canvasPosition,
      _digitalTextElements,
    );

    if (hitElement != null) {
      // Show edit dialog
      _editDigitalTextElement(hitElement);
    }
  }

  /// Syncs a text element updated by DigitalTextTool back into the canvas state.
  ///
  /// Centralizes the repeated pattern of:
  /// 1. Finding the element by ID in _digitalTextElements
  /// 2. Replacing it with the updated version
  /// 3. Notifying the layer controller for delta tracking
  void _syncTextElementFromTool(DigitalTextElement updated) {
    final idx = _digitalTextElements.indexWhere((e) => e.id == updated.id);
    if (idx != -1) {
      _digitalTextElements[idx] = updated;
    }
    _layerController.updateText(updated);

    // 🔴 RT: Broadcast text update to collaborators
    _broadcastTextChange(updated);
  }
}
