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

  /// Shows dialog per inserire testo digitale
  Future<void> _showDigitalTextDialog() async {
    final result = await DigitalTextInputDialog.show(
      context,
      initialColor: _effectiveColor,
    );


    if (result != null && mounted) {
      // Create text element al centro of the viewport
      // 🛠️ FIX: Use screenToCanvas to convert screen center to canvas coordinates
      final screenCenter = Offset(
        MediaQuery.of(context).size.width / 2,
        MediaQuery.of(context).size.height / 2,
      );
      final viewportCenter = _canvasController.screenToCanvas(screenCenter);


      final newElement = DigitalTextElement(
        id: const Uuid().v4(),
        text: result.text,
        position: viewportCenter,
        color: result.color,
        fontSize: result.fontSize,
        scale: 1.0,
        createdAt: DateTime.now(),
      );

      setState(() {
        _digitalTextElements.add(newElement);
        // Seleziona automaticamente il nuovo elemento
        _digitalTextTool.selectElement(newElement);
      });

      // 🔄 Sync: notify delta tracker for synchronization
      _layerController.addText(newElement);


      // 💾 Auto-save dopo aggiunta testo digitale
      _autoSaveCanvas();
    }
  }

  /// Shows dialog per MODIFICARE testo digitale esistente (long press)
  Future<void> _editDigitalTextElement(DigitalTextElement element) async {
    final result = await DigitalTextInputDialog.show(
      context,
      initialColor: element.color,
      initialText: element.text,
    );

    if (result != null && mounted) {
      // Find the element e aggiornalo
      final index = _digitalTextElements.indexOf(element);
      if (index != -1) {
        setState(() {
          // Replaci con nuovo elemento aggiornato
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
          // Ri-seleziona l'elemento aggiornato
          _digitalTextTool.selectElement(_digitalTextElements[index]);
        });

        // 💾 Auto-save dopo modifica testo digitale
        _autoSaveCanvas();
      }
    }
  }

  /// Handles long press sul canvas (per modificare testo)
  void _onLongPress(Offset canvasPosition) {
    // 🔒 VIEWER GUARD
    if (_checkViewerGuard()) return;

    // Check if pressed on a text element
    final hitElement = _digitalTextTool.hitTest(
      canvasPosition,
      _digitalTextElements,
      context,
    );

    if (hitElement != null) {
      // Show dialog di modifica
      _editDigitalTextElement(hitElement);
    }
  }
}
