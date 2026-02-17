part of '../../nebula_canvas_screen.dart';

/// 🎯 Menus & Panels — selection actions, image actions, layer panel, Phase 2 stubs.
/// Extracted from _NebulaCanvasScreenState._buildImpl
extension NebulaCanvasMenusUI on _NebulaCanvasScreenState {
  /// Builds menus that sit in the MAIN Stack (outside the canvas area).
  List<Widget> _buildMenus(BuildContext context) {
    return [
      // Menu Contestuale Selezione — azioni sugli selected elements
      if (_lassoTool.hasSelection && !_isDrawingNotifier.value)
        Positioned(
          bottom: 100,
          left: 20,
          right: 20,
          child: SelectionActionsMenu(
            selectionCount: _lassoTool.selectionCount,
            onDelete: () {
              setState(() {
                _lassoTool.deleteSelected();
                // Clear the selection after deletion
                _lassoTool.clearSelection();
                // Disattiva il lasso
                _toolController.toggleLassoMode(); // deactivate lasso
              });
              HapticFeedback.mediumImpact();
            },
            onClearSelection: () {
              setState(() {
                _lassoTool.clearSelection();
                // Disattiva il lasso
                _toolController.toggleLassoMode(); // deactivate lasso
              });
              HapticFeedback.lightImpact();
            },
            onRotate: () {
              setState(() {
                _lassoTool.rotateSelected();
                HapticFeedback.lightImpact();
              });
            },
            onFlipHorizontal: () {
              setState(() {
                _lassoTool.flipHorizontal();
                HapticFeedback.lightImpact();
              });
            },
            onFlipVertical: () {
              setState(() {
                _lassoTool.flipVertical();
                HapticFeedback.lightImpact();
              });
            },
            onConvertToText: () {
              // Phase 2: OCR conversion (requires OCRService)
              HapticFeedback.mediumImpact();
              debugPrint(
                '[Phase2] OCR text conversion not yet available in SDK',
              );
            },
          ),
        ),

      // 🖼️ Menu azioni per selected image
      if (_imageTool.selectedImage != null && !_isDrawingNotifier.value)
        Positioned(
          bottom: 100,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color:
                    Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[850]
                        : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Pulsante Apri Editor
                  ImageActionButton(
                    icon: Icons.edit,
                    label: 'Edit',
                    color: Colors.blue,
                    onTap: () {
                      final imageElement = _imageTool.selectedImage!;
                      final image = _loadedImages[imageElement.imagePath];
                      if (image != null) {
                        _openImageEditor(imageElement, image);
                      }
                    },
                  ),
                  const SizedBox(width: 12),
                  // Pulsante Elimina
                  ImageActionButton(
                    icon: Icons.delete,
                    label: '*',
                    color: Colors.red,
                    onTap: () {
                      final imageElement = _imageTool.selectedImage!;
                      setState(() {
                        _imageElements.removeWhere(
                          (e) => e.id == imageElement.id,
                        );
                        _imageTool.clearSelection();
                      });

                      // 🔄 Sync: notifica delta tracker per sincronizzazione
                      _layerController.removeImage(imageElement.id);
                      if (_isSharedCanvas) _snapshotAndPushCloudDeltas();

                      _autoSaveCanvas();
                      HapticFeedback.mediumImpact();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),

      // PHASE2:             // 📤 EXPORT MODE OVERLAYS
      // PHASE2:             if (_isExportMode) ...[
      // ... (all PHASE2 export/multi-page/audio/share stubs remain commented)

      // Layer Panel (slide da sinistra) — overlay sopra tutto
      LayerPanel(
        key: _layerPanelKey,
        controller: _layerController,
        isDark: false,
        isDrawingNotifier: _isDrawingNotifier,
      ),

      // PHASE2:             // 🎧 Audio Player Banner
      // PHASE2:             // 🤝 Share Canvas FAB
      // PHASE2:             // ⏱️ Time Travel Timeline Overlay
      // PHASE2:             // 🔮 Lasso overlay per recupero dal passato
      // PHASE2:             // 🔮 Overlay posizionamento recupero
    ];
  }
}
