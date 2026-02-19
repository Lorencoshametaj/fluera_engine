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
            hasClipboard: _lassoTool.hasClipboard,
            snapEnabled: _lassoTool.snapEnabled,
            onCopy: () {
              _lassoTool.copySelected();
              HapticFeedback.lightImpact();
            },
            onDuplicate: () {
              setState(() {
                _lassoTool.duplicateSelected();
              });
              DrawingPainter.invalidateAllTiles();
              _autoSaveCanvas();
              HapticFeedback.mediumImpact();
            },
            onPaste: () {
              setState(() {
                _lassoTool.pasteFromClipboard();
              });
              DrawingPainter.invalidateAllTiles();
              _autoSaveCanvas();
              HapticFeedback.lightImpact();
            },
            onSelectAll: () {
              setState(() {
                _lassoTool.selectAll();
              });
              HapticFeedback.lightImpact();
            },
            onBringToFront: () {
              setState(() {
                _lassoTool.bringToFront();
              });
              DrawingPainter.invalidateAllTiles();
              _autoSaveCanvas();
              HapticFeedback.lightImpact();
            },
            onSendToBack: () {
              setState(() {
                _lassoTool.sendToBack();
              });
              DrawingPainter.invalidateAllTiles();
              _autoSaveCanvas();
              HapticFeedback.lightImpact();
            },
            onGroup: () {
              setState(() {
                _lassoTool.groupSelected();
              });
              HapticFeedback.mediumImpact();
            },
            onUngroup: () {
              setState(() {
                _lassoTool.ungroupSelected();
              });
              HapticFeedback.lightImpact();
            },
            onToggleSnap: () {
              setState(() {
                _lassoTool.toggleSnap();
              });
              HapticFeedback.lightImpact();
            },
            onUndo: () {
              setState(() {
                _lassoTool.restoreUndo();
              });
              DrawingPainter.invalidateAllTiles();
              _autoSaveCanvas();
              HapticFeedback.mediumImpact();
            },
            onDelete: () {
              setState(() {
                _lassoTool.deleteSelected();
                _lassoTool.clearSelection();
                _toolController.toggleLassoMode();
              });
              DrawingPainter.invalidateAllTiles();
              _autoSaveCanvas();
              HapticFeedback.mediumImpact();
            },
            onClearSelection: () {
              setState(() {
                _lassoTool.clearSelection();
                _toolController.toggleLassoMode();
              });
              HapticFeedback.lightImpact();
            },
            onRotate: () {
              setState(() {
                _lassoTool.rotateSelected();
              });
              DrawingPainter.invalidateAllTiles();
              _autoSaveCanvas();
              HapticFeedback.lightImpact();
            },
            onFlipHorizontal: () {
              setState(() {
                _lassoTool.flipHorizontal();
              });
              DrawingPainter.invalidateAllTiles();
              _autoSaveCanvas();
              HapticFeedback.lightImpact();
            },
            onFlipVertical: () {
              setState(() {
                _lassoTool.flipVertical();
              });
              DrawingPainter.invalidateAllTiles();
              _autoSaveCanvas();
              HapticFeedback.lightImpact();
            },
            onConvertToText: () {
              // Phase 2: OCR conversion (requires OCRService)
              HapticFeedback.mediumImpact();
              debugPrint(
                '[Phase2] OCR text conversion not yet available in SDK',
              );
            },
            // Round 3 — Enterprise
            isSelectionLocked: _lassoTool.isSelectionLocked,
            multiLayerMode: _lassoTool.multiLayerMode,
            statsSummary: _lassoTool.selectionStats.summary,
            onLock: () {
              setState(() {
                _lassoTool.lockSelected();
              });
              HapticFeedback.mediumImpact();
            },
            onUnlock: () {
              setState(() {
                _lassoTool.unlockSelected();
              });
              HapticFeedback.lightImpact();
            },
            onAlignLeft: () {
              setState(() {
                _lassoTool.alignLeft();
              });
              DrawingPainter.invalidateAllTiles();
              _autoSaveCanvas();
              HapticFeedback.lightImpact();
            },
            onAlignCenterH: () {
              setState(() {
                _lassoTool.alignCenterH();
              });
              DrawingPainter.invalidateAllTiles();
              _autoSaveCanvas();
              HapticFeedback.lightImpact();
            },
            onAlignRight: () {
              setState(() {
                _lassoTool.alignRight();
              });
              DrawingPainter.invalidateAllTiles();
              _autoSaveCanvas();
              HapticFeedback.lightImpact();
            },
            onAlignTop: () {
              setState(() {
                _lassoTool.alignTop();
              });
              DrawingPainter.invalidateAllTiles();
              _autoSaveCanvas();
              HapticFeedback.lightImpact();
            },
            onAlignCenterV: () {
              setState(() {
                _lassoTool.alignCenterV();
              });
              DrawingPainter.invalidateAllTiles();
              _autoSaveCanvas();
              HapticFeedback.lightImpact();
            },
            onAlignBottom: () {
              setState(() {
                _lassoTool.alignBottom();
              });
              DrawingPainter.invalidateAllTiles();
              _autoSaveCanvas();
              HapticFeedback.lightImpact();
            },
            onDistributeH: () {
              setState(() {
                _lassoTool.distributeHorizontal();
              });
              DrawingPainter.invalidateAllTiles();
              _autoSaveCanvas();
              HapticFeedback.lightImpact();
            },
            onDistributeV: () {
              setState(() {
                _lassoTool.distributeVertical();
              });
              DrawingPainter.invalidateAllTiles();
              _autoSaveCanvas();
              HapticFeedback.lightImpact();
            },
            onToggleMultiLayer: () {
              setState(() {
                _lassoTool.toggleMultiLayerMode();
              });
              HapticFeedback.lightImpact();
            },
          ),
        ),

      // 🖼️ Action menu for selected image
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
                        _imageVersion++;
                        _rebuildImageSpatialIndex();
                      });
                      // 🗑️ Prune per-image cache for the deleted image
                      ImagePainter.invalidateImageCache(imageElement.id);

                      // 🔄 Sync: notify delta tracker for synchronization
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

      // Layer Panel (slides from left) — overlay above everything
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
