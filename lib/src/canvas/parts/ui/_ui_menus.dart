part of '../../fluera_canvas_screen.dart';

/// 🎯 Menus & Panels — selection actions, image actions, layer panel, Phase 2 stubs.
/// Extracted from _FlueraCanvasScreenState._buildImpl
extension FlueraCanvasMenusUI on _FlueraCanvasScreenState {
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
            // Phase 3 — Procreate parity
            onInverse: () {
              setState(() {
                _lassoTool.invertSelection();
              });
              HapticFeedback.mediumImpact();
            },
            onPasteInPlace: () {
              setState(() {
                _lassoTool.pasteInPlace();
              });
              DrawingPainter.invalidateAllTiles();
              _autoSaveCanvas();
              HapticFeedback.lightImpact();
            },
          ),
        ),

      // 🖼️ Action menu for selected image — opens contextual popup
      if (_imageTool.selectedImage != null && !_isDrawingNotifier.value)
        Positioned(
          bottom: 100,
          left: 0,
          right: 0,
          child: Center(
            child: Builder(
              builder: (btnContext) {
                final cs = Theme.of(btnContext).colorScheme;
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      // 🐛 Guard: selection may have been cleared between
                      // build and tap (e.g. by a concurrent gesture).
                      final imageElement = _imageTool.selectedImage;
                      if (imageElement == null) return;
                      final box = btnContext.findRenderObject() as RenderBox;
                      final pos = box.localToGlobal(Offset.zero);
                      final anchor = Rect.fromLTWH(
                        pos.dx,
                        pos.dy,
                        box.size.width,
                        box.size.height,
                      );
                      final image = _loadedImages[imageElement.imagePath];
                      showImageActionsPopup(
                        context: btnContext,
                        anchor: anchor,
                        image: imageElement,
                        onEdit: () {
                          if (image != null) {
                            _openImageEditor(imageElement, image);
                          }
                        },
                        onCrop: () async {
                          if (image == null) return;
                          // 🐛 FIX: Open crop editor directly, skip full editor
                          final cropResult = await showDialog<Rect?>(
                            context: btnContext,
                            barrierDismissible: false,
                            builder:
                                (_) => CropEditorDialog(
                                  image: image,
                                  initialCropRect: imageElement.cropRect,
                                ),
                          );
                          if (cropResult != null) {
                            final idx = _imageElements.indexWhere(
                              (e) => e.id == imageElement.id,
                            );
                            if (idx != -1) {
                              final updated = imageElement.copyWith(
                                cropRect: cropResult,
                              );
                              setState(() {
                                _imageElements[idx] = updated;
                                _imageTool.selectImage(updated);
                                _imageVersion++;
                                _rebuildImageSpatialIndex();
                              });
                              _layerController.updateImage(updated);
                              _broadcastImageUpdate(updated);
                              _autoSaveCanvas();
                            }
                          }
                        },
                        onAdjust: () {
                          if (image != null) {
                            _openImageEditor(
                              imageElement,
                              image,
                              initialTab: 1,
                            );
                          }
                        },
                        onFlipH: () {
                          final idx = _imageElements.indexWhere(
                            (e) => e.id == imageElement.id,
                          );
                          if (idx != -1) {
                            final updated = imageElement.copyWith(
                              flipHorizontal: !imageElement.flipHorizontal,
                            );
                            setState(() {
                              _imageElements[idx] = updated;
                              _imageTool.selectImage(updated);
                              _imageVersion++;
                              _rebuildImageSpatialIndex();
                            });
                            _layerController.updateImage(updated);
                            _broadcastImageUpdate(updated);
                            _autoSaveCanvas();
                          }
                        },
                        onFlipV: () {
                          final idx = _imageElements.indexWhere(
                            (e) => e.id == imageElement.id,
                          );
                          if (idx != -1) {
                            final updated = imageElement.copyWith(
                              flipVertical: !imageElement.flipVertical,
                            );
                            setState(() {
                              _imageElements[idx] = updated;
                              _imageTool.selectImage(updated);
                              _imageVersion++;
                              _rebuildImageSpatialIndex();
                            });
                            _layerController.updateImage(updated);
                            _broadcastImageUpdate(updated);
                            _autoSaveCanvas();
                          }
                        },
                        onDuplicate: () {
                          final newImage = imageElement.copyWith(
                            id: generateUid(),
                            position:
                                imageElement.position + const Offset(30, 30),
                            createdAt: DateTime.now(),
                          );
                          setState(() {
                            _imageElements.add(newImage);
                            _imageTool.selectImage(newImage);
                            _imageVersion++;
                            _rebuildImageSpatialIndex();
                          });
                          _layerController.addImage(newImage);
                          _broadcastImageUpdate(newImage, isNew: true);
                          _autoSaveCanvas();
                          HapticFeedback.mediumImpact();
                        },
                        onDelete: () {
                          showDeleteImageConfirmation(
                            btnContext,
                            imageElement.id,
                          );
                        },
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.image_rounded,
                            size: 18,
                            color: cs.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Image Actions',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.expand_more_rounded,
                            size: 18,
                            color: cs.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),

      // PHASE2:             // 📤 EXPORT MODE OVERLAYS
      // PHASE2:             if (_isExportMode) ...[
      // ... (all PHASE2 export/multi-page/audio/share stubs remain commented)

      // Layer Panel (slides from left) — overlay above everything
      Positioned(
        left: 0,
        top: 0,
        bottom: 0,
        child: Center(
          child: LayerPanel(
            key: _layerPanelKey,
            controller: _layerController,
            isDark: false,
            isDrawingNotifier: _isDrawingNotifier,
          ),
        ),
      ),

      // PHASE2:             // 🎧 Audio Player Banner
      // PHASE2:             // 🤝 Share Canvas FAB
      // PHASE2:             // ⏱️ Time Travel Timeline Overlay
      // PHASE2:             // 🔮 Lasso overlay per recupero dal passato
      // PHASE2:             // 🔮 Overlay posizionamento recupero
    ];
  }
}
