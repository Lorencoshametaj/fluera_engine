part of '../../fluera_canvas_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 📐 Drawing End — Section Selection, Editing & Customization
// ═══════════════════════════════════════════════════════════════════════════

extension on _FlueraCanvasScreenState {
  // ===========================================================================
  // 📐 SECTION SELECTION — Find and edit existing sections
  // ===========================================================================

  /// Walk the scene graph and return the first SectionNode whose world bounds
  /// contain [canvasPoint], or null.
  SectionNode? _findSectionAtPoint(Offset canvasPoint) {
    final sceneGraph = _layerController.sceneGraph;
    for (final layer in sceneGraph.layers) {
      for (final child in layer.children.reversed) {
        if (child is SectionNode && child.isVisible) {
          final inverse = Matrix4.tryInvert(child.worldTransform);
          if (inverse == null) continue;
          final local = MatrixUtils.transformPoint(inverse, canvasPoint);
          if (child.localBounds.contains(local)) return child;
        }
      }
    }
    return null;
  }

  /// Find a section whose **name label bar** contains [canvasPoint].
  ///
  /// The label bar is the ~30px strip above the section top edge,
  /// rendered by the scene graph renderer. This enables editing
  /// sections by tapping their name from ANY tool.
  SectionNode? _findSectionByNameLabel(Offset canvasPoint) {
    final sceneGraph = _layerController.sceneGraph;
    final invScale = 1.0 / _canvasController.scale;
    final labelH = SectionNode.labelHeight * invScale;
    // Generous touch padding (10px above, 12px below) for easy finger taps
    final padAbove = 10.0 * invScale;
    final padBelow = 12.0 * invScale;
    for (final layer in sceneGraph.layers) {
      for (final child in layer.children.reversed) {
        if (child is SectionNode && child.isVisible) {
          final tx = child.worldTransform.getTranslation();
          final hitRect = Rect.fromLTWH(
            tx.x,
            tx.y - labelH - padAbove,
            child.sectionSize.width,
            labelH + padAbove + padBelow,
          );
          if (hitRect.contains(canvasPoint)) return child;
        }
      }
    }
    return null;
  }

  /// Find a section corner or edge handle near [canvasPoint] within [radius].
  /// Returns (section, anchor point) where anchor is the fixed opposite.
  /// Also sets [_resizeEdgeAxis]: null for corners, 'h' for left/right, 'v' for top/bottom.
  (SectionNode, Offset)? _findSectionCornerAtPoint(
    Offset canvasPoint,
    double radius,
  ) {
    final sceneGraph = _layerController.sceneGraph;
    for (final layer in sceneGraph.layers) {
      for (final child in layer.children.reversed) {
        if (child is! SectionNode || !child.isVisible) continue;

        final tx = child.worldTransform.getTranslation();
        final origin = Offset(tx.x, tx.y);
        final sz = child.sectionSize;
        final right = origin.dx + sz.width;
        final bottom = origin.dy + sz.height;
        final midX = origin.dx + sz.width / 2;
        final midY = origin.dy + sz.height / 2;

        // 4 corners in canvas space (check first — higher priority)
        final corners = [
          origin, // top-left
          Offset(right, origin.dy), // top-right
          Offset(right, bottom), // bottom-right
          Offset(origin.dx, bottom), // bottom-left
        ];
        // Anchor = diagonally opposite corner
        final anchors = [corners[2], corners[3], corners[0], corners[1]];

        for (int i = 0; i < 4; i++) {
          if ((canvasPoint - corners[i]).distance <= radius) {
            _resizeEdgeAxis = null; // Corner → both axes
            return (child, anchors[i]);
          }
        }

        // 4 edge midpoints (check after corners)
        final edgeRadius = radius * 1.5; // Slightly larger for easier edge grab
        // Top edge midpoint
        if ((canvasPoint - Offset(midX, origin.dy)).distance <= edgeRadius) {
          _resizeEdgeAxis = 'v';
          return (child, Offset(midX, bottom)); // anchor = bottom edge
        }
        // Bottom edge midpoint
        if ((canvasPoint - Offset(midX, bottom)).distance <= edgeRadius) {
          _resizeEdgeAxis = 'v';
          return (child, Offset(midX, origin.dy)); // anchor = top edge
        }
        // Left edge midpoint
        if ((canvasPoint - Offset(origin.dx, midY)).distance <= edgeRadius) {
          _resizeEdgeAxis = 'h';
          return (child, Offset(right, midY)); // anchor = right edge
        }
        // Right edge midpoint
        if ((canvasPoint - Offset(right, midY)).distance <= edgeRadius) {
          _resizeEdgeAxis = 'h';
          return (child, Offset(origin.dx, midY)); // anchor = left edge
        }
      }
    }
    return null;
  }

  /// Show an edit sheet for an existing section.
  void _showSectionEditSheet(SectionNode section) {
    final nameController = TextEditingController(text: section.sectionName);

    // Same color presets as creation
    const colorPresets = <Color?>[
      null,
      Color(0xFFFFFFFF),
      Color(0xFFF5F5F5),
      Color(0xFF1E1E2E),
      Color(0x1A2196F3),
      Color(0x1AFF9800),
      Color(0x1A4CAF50),
      Color(0x1AE91E63),
      Color(0x1A9C27B0),
      Color(0x1A00BCD4),
    ];

    Color? selectedColor = section.backgroundColor;
    bool showGrid = section.showGrid;
    bool clipContent = section.clipContent;
    int subdivRows = section.subdivisionRows;
    int subdivColumns = section.subdivisionColumns;
    int sectionCornerRadius = section.cornerRadius.round();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final cs = Theme.of(ctx).colorScheme;
            final isDark = cs.brightness == Brightness.dark;
            final bgColor =
                isDark ? const Color(0xFF1E1E2E) : const Color(0xFFF5F5F5);
            final textColor = isDark ? Colors.white : Colors.black87;
            final muted = textColor.withValues(alpha: 0.4);

            Widget sectionLabel(String text) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                text,
                style: TextStyle(
                  color: muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
            );

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.75,
                ),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Drag handle
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 8),
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: textColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // Scrollable content
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Header ──
                            Row(
                              children: [
                                const Icon(
                                  Icons.edit_outlined,
                                  color: Color(0xFF2196F3),
                                  size: 22,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'Edit Section',
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: textColor.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${section.sectionSize.width.round()} × ${section.sectionSize.height.round()}',
                                    style: TextStyle(
                                      color: textColor.withValues(alpha: 0.5),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),

                            // ── Name ──
                            sectionLabel('NAME'),
                            TextField(
                              controller: nameController,
                              autofocus: false,
                              style: TextStyle(color: textColor, fontSize: 15),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: textColor.withValues(alpha: 0.06),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // ── Background Color ──
                            sectionLabel('BACKGROUND'),
                            SizedBox(
                              height: 40,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: colorPresets.length,
                                separatorBuilder:
                                    (_, __) => const SizedBox(width: 8),
                                itemBuilder: (_, i) {
                                  final color = colorPresets[i];
                                  final isSelected = selectedColor == color;
                                  final isTransparent = color == null;

                                  return GestureDetector(
                                    onTap: () {
                                      setSheetState(
                                        () => selectedColor = color,
                                      );
                                      HapticFeedback.selectionClick();
                                    },
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 150,
                                      ),
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color:
                                            isTransparent
                                                ? Colors.transparent
                                                : color,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color:
                                              isSelected
                                                  ? const Color(0xFF2196F3)
                                                  : textColor.withValues(
                                                    alpha: 0.15,
                                                  ),
                                          width: isSelected ? 2.5 : 1.0,
                                        ),
                                      ),
                                      child:
                                          isTransparent
                                              ? Icon(
                                                Icons.block_rounded,
                                                size: 18,
                                                color: textColor.withValues(
                                                  alpha: 0.3,
                                                ),
                                              )
                                              : null,
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 16),

                            // ── Options ──
                            sectionLabel('OPTIONS'),
                            _sectionOptionRow(
                              icon: Icons.grid_4x4_rounded,
                              label: 'Show Grid',
                              value: showGrid,
                              textColor: textColor,
                              onChanged:
                                  (v) => setSheetState(() => showGrid = v),
                            ),
                            const SizedBox(height: 4),
                            _sectionOptionRow(
                              icon: Icons.content_cut_rounded,
                              label: 'Clip Content',
                              value: clipContent,
                              textColor: textColor,
                              onChanged:
                                  (v) => setSheetState(() => clipContent = v),
                            ),
                            const SizedBox(height: 16),

                            // ── Subdivisions ──
                            sectionLabel('SUBDIVISIONS'),
                            _sectionStepperRow(
                              icon: Icons.table_rows_outlined,
                              label: 'Rows',
                              value: subdivRows,
                              textColor: textColor,
                              onChanged:
                                  (v) => setSheetState(() => subdivRows = v),
                            ),
                            const SizedBox(height: 4),
                            _sectionStepperRow(
                              icon: Icons.view_column_outlined,
                              label: 'Columns',
                              value: subdivColumns,
                              textColor: textColor,
                              onChanged:
                                  (v) => setSheetState(() => subdivColumns = v),
                            ),
                            const SizedBox(height: 4),
                            _sectionStepperRow(
                              icon: Icons.rounded_corner_rounded,
                              label: 'Corner Radius',
                              value: sectionCornerRadius,
                              min: 0,
                              max: 32,
                              textColor: textColor,
                              onChanged:
                                  (v) => setSheetState(
                                    () => sectionCornerRadius = v,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ── Quick Actions Row ──
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            // Lock toggle
                            _sectionActionChip(
                              icon:
                                  section.isLocked
                                      ? Icons.lock_rounded
                                      : Icons.lock_open_rounded,
                              label: section.isLocked ? 'Locked' : 'Lock',
                              isActive: section.isLocked,
                              textColor: textColor,
                              onTap: () {
                                setSheetState(() {
                                  section.isLocked = !section.isLocked;
                                });
                                HapticFeedback.selectionClick();
                              },
                            ),
                            const SizedBox(width: 8),
                            // Add Below — append equal-size section directly below
                            _sectionActionChip(
                              icon: Icons.add_box_outlined,
                              label: 'Add Below',
                              textColor: textColor,
                              onTap: () {
                                Navigator.of(ctx).pop();
                                _appendSectionBelow(section);
                              },
                            ),
                            const SizedBox(width: 8),
                            // Duplicate
                            _sectionActionChip(
                              icon: Icons.copy_rounded,
                              label: 'Duplicate',
                              textColor: textColor,
                              onTap: () {
                                Navigator.of(ctx).pop();
                                _duplicateSection(section);
                              },
                            ),
                            const SizedBox(width: 8),
                            // Export
                            _sectionActionChip(
                              icon: Icons.ios_share_rounded,
                              label: 'Export',
                              textColor: textColor,
                              onTap: () {
                                Navigator.of(ctx).pop();
                                _exportSection(section);
                              },
                            ),
                            const SizedBox(width: 12),
                            // Z-Order controls
                            _sectionActionChip(
                              icon: Icons.flip_to_front_rounded,
                              label: 'Front',
                              textColor: textColor,
                              onTap: () {
                                _bringToFront(section);
                                HapticFeedback.selectionClick();
                              },
                            ),
                            const SizedBox(width: 8),
                            _sectionActionChip(
                              icon: Icons.flip_to_back_rounded,
                              label: 'Back',
                              textColor: textColor,
                              onTap: () {
                                _sendToBack(section);
                                HapticFeedback.selectionClick();
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // ── Action buttons ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      child: Row(
                        children: [
                          // Delete button
                          IconButton(
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              _confirmDeleteSection(section);
                            },
                            icon: const Icon(Icons.delete_outline_rounded),
                            color: const Color(0xFFE53935),
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(
                                0xFFE53935,
                              ).withValues(alpha: 0.1),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Cancel
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                'Cancel',
                                style: TextStyle(
                                  color: textColor.withValues(alpha: 0.5),
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Apply
                          Expanded(
                            flex: 2,
                            child: FilledButton(
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                _applySectionEdits(
                                  section: section,
                                  name:
                                      nameController.text.trim().isEmpty
                                          ? section.sectionName
                                          : nameController.text.trim(),
                                  backgroundColor: selectedColor,
                                  showGrid: showGrid,
                                  clipContent: clipContent,
                                  subdivisionRows: subdivRows,
                                  subdivisionColumns: subdivColumns,
                                  cornerRadius: sectionCornerRadius.toDouble(),
                                );
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF2196F3),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'Apply Changes',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Apply edits to an existing section.
  void _applySectionEdits({
    required SectionNode section,
    required String name,
    Color? backgroundColor,
    bool showGrid = false,
    bool clipContent = false,
    int subdivisionRows = 1,
    int subdivisionColumns = 1,
    double cornerRadius = 0,
  }) {
    section.sectionName = name;
    section.name = name;
    section.backgroundColor = backgroundColor;
    section.showGrid = showGrid;
    section.clipContent = clipContent;
    section.subdivisionRows = subdivisionRows;
    section.subdivisionColumns = subdivisionColumns;
    section.cornerRadius = cornerRadius;

    _layerController.sceneGraph.bumpVersion();
    DrawingPainter.invalidateAllTiles();
    HapticFeedback.mediumImpact();
    _layerController.notifyListeners();
    _uiRebuildNotifier.value++;
    _autoSaveCanvas();
  }

  /// Delete a section from the scene graph.
  /// Show a confirmation dialog before deleting a section.
  void _confirmDeleteSection(SectionNode section) {
    showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFFE53935),
                  size: 24,
                ),
                const SizedBox(width: 10),
                Text(
                  'Delete Section?',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            content: Text(
              '"${section.sectionName}" and all its contents will be removed. This cannot be undone.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 14,
                height: 1.4,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE53935),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Delete',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
    ).then((confirmed) {
      if (confirmed == true) _deleteSection(section);
    });
  }

  /// Delete a section from the scene graph.
  void _deleteSection(SectionNode section) {
    final sceneGraph = _layerController.sceneGraph;
    for (final layer in sceneGraph.layers) {
      if (layer.children.contains(section)) {
        layer.remove(section);
        break;
      }
    }
    sceneGraph.bumpVersion();
    DrawingPainter.invalidateAllTiles();
    HapticFeedback.heavyImpact();
    if (_focusedSectionNode == section) _focusedSectionNode = null;
    _layerController.notifyListeners();
    _uiRebuildNotifier.value++;
    _autoSaveCanvas();
  }

  // ===========================================================================
  // 📐 SECTION CUSTOMIZATION — Bottom sheet for name & color

  /// Show a bottom sheet to let the user name the section, pick a color,
  /// select a preset, and toggle grid/clip options.
  void _showSectionCustomizationSheet(Rect sectionRect) {
    final defaultName = 'Section ${_sectionCounter}';
    final nameController = TextEditingController(text: defaultName);

    // Curated color presets (null = transparent / no background)
    const colorPresets = <Color?>[
      null, // transparent
      Color(0xFFFFFFFF), // white
      Color(0xFFF5F5F5), // light grey
      Color(0xFF1E1E2E), // dark navy
      Color(0x1A2196F3), // blue tint
      Color(0x1AFF9800), // orange tint
      Color(0x1A4CAF50), // green tint
      Color(0x1AE91E63), // pink tint
      Color(0x1A9C27B0), // purple tint
      Color(0x1A00BCD4), // cyan tint
    ];

    // Quick-pick presets (most popular — shown by default)
    const quickPicks = <SectionPreset>[
      SectionPreset.iphone16,
      SectionPreset.ipadPro11,
      SectionPreset.a4Portrait,
      SectionPreset.desktop1080p,
      SectionPreset.instagramPost,
    ];

    // Full categories (shown on expand)
    const allCategories = <String, List<SectionPreset>>{
      '📱 Devices': [
        SectionPreset.iphone16,
        SectionPreset.iphone16Pro,
        SectionPreset.iphone16ProMax,
        SectionPreset.ipadPro11,
        SectionPreset.ipadPro13,
      ],
      '🖥 Desktop': [
        SectionPreset.macbook14,
        SectionPreset.desktop1080p,
        SectionPreset.desktop4k,
      ],
      '📄 Paper': [
        SectionPreset.a4Portrait,
        SectionPreset.a4Landscape,
        SectionPreset.a3Portrait,
        SectionPreset.letterPortrait,
        SectionPreset.letterLandscape,
      ],
      '📸 Social': [
        SectionPreset.instagramPost,
        SectionPreset.instagramStory,
        SectionPreset.twitterPost,
      ],
      '🎬 Presentation': [
        SectionPreset.presentation16x9,
        SectionPreset.presentation4x3,
      ],
    };

    Color? selectedColor = Colors.white;
    SectionPreset? selectedPreset;
    bool showAllPresets = false;
    bool showGrid = false;
    bool clipContent = false;
    int subdivRows = 1;
    int subdivColumns = 1;
    int sectionCornerRadius = 0;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final cs = Theme.of(ctx).colorScheme;
            final isDark = cs.brightness == Brightness.dark;
            final bgColor =
                isDark ? const Color(0xFF1E1E2E) : const Color(0xFFF5F5F5);
            final textColor = isDark ? Colors.white : Colors.black87;
            final muted = textColor.withValues(alpha: 0.4);

            // Current effective size
            final effectiveSize =
                selectedPreset != null
                    ? selectedPreset!.size
                    : sectionRect.size;

            Widget sectionLabel(String text) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                text,
                style: TextStyle(
                  color: muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
            );

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.75,
                ),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Drag handle
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 8),
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: textColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // Scrollable content
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Header ──
                            Row(
                              children: [
                                const Icon(
                                  Icons.dashboard_outlined,
                                  color: Color(0xFF2196F3),
                                  size: 22,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'New Section',
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 200),
                                  child: Container(
                                    key: ValueKey(effectiveSize),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: textColor.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '${effectiveSize.width.round()} × ${effectiveSize.height.round()}',
                                      style: TextStyle(
                                        color: textColor.withValues(alpha: 0.5),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),

                            // ── Name ──
                            sectionLabel('NAME'),
                            TextField(
                              controller: nameController,
                              autofocus: true,
                              style: TextStyle(color: textColor, fontSize: 15),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: textColor.withValues(alpha: 0.06),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                hintText: 'Section name...',
                                hintStyle: TextStyle(
                                  color: textColor.withValues(alpha: 0.3),
                                ),
                              ),
                              onSubmitted: (_) {
                                Navigator.of(ctx).pop();
                                _commitSectionWithOptions(
                                  sectionRect: sectionRect,
                                  name:
                                      nameController.text.trim().isEmpty
                                          ? defaultName
                                          : nameController.text.trim(),
                                  backgroundColor: selectedColor,
                                  showGrid: showGrid,
                                  clipContent: clipContent,
                                  preset: selectedPreset,
                                  subdivisionRows: subdivRows,
                                  subdivisionColumns: subdivColumns,
                                  cornerRadius: sectionCornerRadius.toDouble(),
                                );
                              },
                            ),
                            const SizedBox(height: 16),

                            // ── Presets ──
                            sectionLabel('PRESET SIZE'),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                // Custom (freehand) chip
                                _sectionPresetChip(
                                  label: '✏️ Custom',
                                  isSelected: selectedPreset == null,
                                  textColor: textColor,
                                  onTap: () {
                                    setSheetState(() => selectedPreset = null);
                                    HapticFeedback.selectionClick();
                                  },
                                ),
                                // Quick-pick presets (always visible)
                                for (final preset in quickPicks)
                                  _sectionPresetChip(
                                    label: preset.label,
                                    isSelected: selectedPreset == preset,
                                    textColor: textColor,
                                    subtitle:
                                        '${preset.width.round()}×${preset.height.round()}',
                                    onTap: () {
                                      setSheetState(() {
                                        selectedPreset = preset;
                                        nameController.text = preset.label;
                                      });
                                      HapticFeedback.selectionClick();
                                    },
                                  ),
                              ],
                            ),
                            // "More sizes" toggle
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: GestureDetector(
                                onTap: () {
                                  setSheetState(
                                    () => showAllPresets = !showAllPresets,
                                  );
                                  HapticFeedback.selectionClick();
                                },
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      showAllPresets
                                          ? Icons.expand_less_rounded
                                          : Icons.expand_more_rounded,
                                      size: 16,
                                      color: textColor.withValues(alpha: 0.4),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      showAllPresets
                                          ? 'Less sizes'
                                          : 'More sizes',
                                      style: TextStyle(
                                        color: textColor.withValues(alpha: 0.4),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // Expanded: all categories with headers
                            if (showAllPresets)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (final entry
                                        in allCategories.entries) ...[
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          top: 8,
                                          bottom: 4,
                                        ),
                                        child: Text(
                                          entry.key,
                                          style: TextStyle(
                                            color: textColor.withValues(
                                              alpha: 0.4,
                                            ),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: [
                                          for (final preset in entry.value)
                                            _sectionPresetChip(
                                              label: preset.label,
                                              isSelected:
                                                  selectedPreset == preset,
                                              textColor: textColor,
                                              subtitle:
                                                  '${preset.width.round()}×${preset.height.round()}',
                                              onTap: () {
                                                setSheetState(() {
                                                  selectedPreset = preset;
                                                  nameController.text =
                                                      preset.label;
                                                });
                                                HapticFeedback.selectionClick();
                                              },
                                            ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            const SizedBox(height: 16),

                            // ── Background Color ──
                            sectionLabel('BACKGROUND'),
                            SizedBox(
                              height: 40,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: colorPresets.length,
                                separatorBuilder:
                                    (_, __) => const SizedBox(width: 8),
                                itemBuilder: (_, i) {
                                  final color = colorPresets[i];
                                  final isSelected = selectedColor == color;
                                  final isTransparent = color == null;

                                  return GestureDetector(
                                    onTap: () {
                                      setSheetState(
                                        () => selectedColor = color,
                                      );
                                      HapticFeedback.selectionClick();
                                    },
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 150,
                                      ),
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color:
                                            isTransparent
                                                ? Colors.transparent
                                                : color,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color:
                                              isSelected
                                                  ? const Color(0xFF2196F3)
                                                  : textColor.withValues(
                                                    alpha: 0.15,
                                                  ),
                                          width: isSelected ? 2.5 : 1.0,
                                        ),
                                      ),
                                      child:
                                          isTransparent
                                              ? Icon(
                                                Icons.block_rounded,
                                                size: 18,
                                                color: textColor.withValues(
                                                  alpha: 0.3,
                                                ),
                                              )
                                              : null,
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 16),

                            // ── Options ──
                            sectionLabel('OPTIONS'),
                            _sectionOptionRow(
                              icon: Icons.grid_4x4_rounded,
                              label: 'Show Grid',
                              value: showGrid,
                              textColor: textColor,
                              onChanged:
                                  (v) => setSheetState(() => showGrid = v),
                            ),
                            const SizedBox(height: 4),
                            _sectionOptionRow(
                              icon: Icons.content_cut_rounded,
                              label: 'Clip Content',
                              value: clipContent,
                              textColor: textColor,
                              onChanged:
                                  (v) => setSheetState(() => clipContent = v),
                            ),
                            const SizedBox(height: 16),

                            // ── Subdivisions ──
                            sectionLabel('SUBDIVISIONS'),
                            _sectionStepperRow(
                              icon: Icons.table_rows_outlined,
                              label: 'Rows',
                              value: subdivRows,
                              textColor: textColor,
                              onChanged:
                                  (v) => setSheetState(() => subdivRows = v),
                            ),
                            const SizedBox(height: 4),
                            _sectionStepperRow(
                              icon: Icons.view_column_outlined,
                              label: 'Columns',
                              value: subdivColumns,
                              textColor: textColor,
                              onChanged:
                                  (v) => setSheetState(() => subdivColumns = v),
                            ),
                            const SizedBox(height: 4),
                            _sectionStepperRow(
                              icon: Icons.rounded_corner_rounded,
                              label: 'Corner Radius',
                              value: sectionCornerRadius,
                              min: 0,
                              max: 32,
                              textColor: textColor,
                              onChanged:
                                  (v) => setSheetState(
                                    () => sectionCornerRadius = v,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ── Action buttons (pinned at bottom) ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                'Cancel',
                                style: TextStyle(
                                  color: textColor.withValues(alpha: 0.5),
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: FilledButton(
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                _commitSectionWithOptions(
                                  sectionRect: sectionRect,
                                  name:
                                      nameController.text.trim().isEmpty
                                          ? defaultName
                                          : nameController.text.trim(),
                                  backgroundColor: selectedColor,
                                  showGrid: showGrid,
                                  clipContent: clipContent,
                                  preset: selectedPreset,
                                  subdivisionRows: subdivRows,
                                  subdivisionColumns: subdivColumns,
                                  cornerRadius: sectionCornerRadius.toDouble(),
                                );
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF2196F3),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'Create Section',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Selectable preset chip widget.
  Widget _sectionPresetChip({
    required String label,
    required bool isSelected,
    required Color textColor,
    required VoidCallback onTap,
    String? subtitle,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? const Color(0xFF2196F3).withValues(alpha: 0.15)
                  : textColor.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color:
                isSelected
                    ? const Color(0xFF2196F3)
                    : textColor.withValues(alpha: 0.1),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color:
                    isSelected
                        ? const Color(0xFF2196F3)
                        : textColor.withValues(alpha: 0.7),
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(width: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: textColor.withValues(alpha: 0.3),
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Compact action chip used in the edit sheet quick actions row.
  Widget _sectionActionChip({
    required IconData icon,
    required String label,
    required Color textColor,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    final bg =
        isActive
            ? const Color(0xFF2196F3).withValues(alpha: 0.15)
            : textColor.withValues(alpha: 0.06);
    final fg =
        isActive ? const Color(0xFF2196F3) : textColor.withValues(alpha: 0.7);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border:
              isActive
                  ? Border.all(
                    color: const Color(0xFF2196F3).withValues(alpha: 0.3),
                  )
                  : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Append a new section of equal size directly below [section].
  ///
  /// Useful for building multi-page course structures: each tap appends
  /// a fresh "Part N" page immediately below the current one.
  void _appendSectionBelow(SectionNode section) {
    final tx = section.worldTransform.getTranslation();
    const gap = 200.0; // canvas units — same as course-structure seeding

    // Strip an existing "– Part N" suffix and auto-increment.
    final base =
        section.sectionName
            .replaceAll(RegExp(r'\s*[–-]\s*Part \d+$'), '')
            .trim();

    // Count siblings sharing the same base name to derive the next index.
    final sceneGraph = _layerController.sceneGraph;
    int existingCount = 1; // current section counts as Part 1
    for (final layer in sceneGraph.layers) {
      for (final child in layer.children) {
        if (child is SectionNode && child != section) {
          final childBase =
              child.sectionName
                  .replaceAll(RegExp(r'\s*[–-]\s*Part \d+$'), '')
                  .trim();
          if (childBase == base) existingCount++;
        }
      }
    }
    final newName = '$base – Part ${existingCount + 1}';

    final newSection = SectionNode(
      id: NodeId(generateUid()),
      sectionName: newName,
      sectionSize: section.sectionSize,
      backgroundColor: section.backgroundColor,
      showGrid: section.showGrid,
      gridSpacing: section.gridSpacing,
      gridType: section.gridType,
      preset: section.preset,
      clipContent: section.clipContent,
      borderColor: section.borderColor,
      borderWidth: section.borderWidth,
      subdivisionRows: section.subdivisionRows,
      subdivisionColumns: section.subdivisionColumns,
      subdivisionColor: section.subdivisionColor,
      cornerRadius: section.cornerRadius,
    );
    // Place directly below: same X, Y = original.y + height + gap
    newSection.setPosition(tx.x, tx.y + section.sectionSize.height + gap);

    for (final layer in sceneGraph.layers) {
      if (layer.children.contains(section)) {
        layer.add(newSection);
        break;
      }
    }

    sceneGraph.bumpVersion();
    DrawingPainter.invalidateAllTiles();
    debugPrint('[Section] ➕ appendBelow: "${newSection.sectionName}" size=${newSection.sectionSize} gridType=${newSection.gridType} pos=(${tx.x}, ${tx.y + section.sectionSize.height + gap}) sceneV=${sceneGraph.version}');
    HapticFeedback.mediumImpact();
    _sectionCounter++;
    _focusedSectionNode = newSection;
    _layerController.notifyListeners();
    _uiRebuildNotifier.value++;
    _autoSaveCanvas();
  }

  /// Duplicate a section with a 20px offset.
  void _duplicateSection(SectionNode section) {
    final tx = section.worldTransform.getTranslation();
    final offset = 20.0;

    final clone = SectionNode(
      id: NodeId(generateUid()),
      sectionName: '${section.sectionName} Copy',
      sectionSize: section.sectionSize,
      backgroundColor: section.backgroundColor,
      showGrid: section.showGrid,
      gridSpacing: section.gridSpacing,
      gridType: section.gridType,
      preset: section.preset,
      clipContent: section.clipContent,
      borderColor: section.borderColor,
      borderWidth: section.borderWidth,
      subdivisionRows: section.subdivisionRows,
      subdivisionColumns: section.subdivisionColumns,
      subdivisionColor: section.subdivisionColor,
      cornerRadius: section.cornerRadius,
    );
    clone.setPosition(tx.x + offset, tx.y + offset);

    // Add to the same layer as the original
    final sceneGraph = _layerController.sceneGraph;
    for (final layer in sceneGraph.layers) {
      if (layer.children.contains(section)) {
        layer.add(clone);
        break;
      }
    }

    sceneGraph.bumpVersion();
    DrawingPainter.invalidateAllTiles();
    HapticFeedback.mediumImpact();
    _sectionCounter++;
    _layerController.notifyListeners();
    _uiRebuildNotifier.value++;
    _autoSaveCanvas();
  }

  /// Export a single section by setting the export area and showing the dialog.
  void _exportSection(SectionNode section) {
    final tx = section.worldTransform.getTranslation();
    final sectionRect = Rect.fromLTWH(
      tx.x,
      tx.y,
      section.sectionSize.width,
      section.sectionSize.height,
    );
    setState(() {
      _exportArea = sectionRect;
      _isExportMode = true;
    });
    HapticFeedback.mediumImpact();
    _showExportFormatDialog();
  }

  /// Move a section to the front (last in the children list = rendered on top).
  void _bringToFront(SectionNode section) {
    final sceneGraph = _layerController.sceneGraph;
    for (final layer in sceneGraph.layers) {
      final idx = layer.children.indexOf(section);
      if (idx >= 0 && idx < layer.children.length - 1) {
        layer.remove(section);
        layer.add(section);
        sceneGraph.bumpVersion();
        DrawingPainter.invalidateAllTiles();
        _layerController.notifyListeners();
        _uiRebuildNotifier.value++;
        break;
      }
    }
  }

  /// Move a section to the back (first in the children list = rendered behind).
  void _sendToBack(SectionNode section) {
    final sceneGraph = _layerController.sceneGraph;
    for (final layer in sceneGraph.layers) {
      final idx = layer.children.indexOf(section);
      if (idx > 0) {
        layer.remove(section);
        layer.insertAt(0, section);
        sceneGraph.bumpVersion();
        DrawingPainter.invalidateAllTiles();
        _layerController.notifyListeners();
        _uiRebuildNotifier.value++;
        break;
      }
    }
  }

  /// Toggle row for grid/clip options.
  Widget _sectionOptionRow({
    required IconData icon,
    required String label,
    required bool value,
    required Color textColor,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: textColor.withValues(alpha: 0.4)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: textColor.withValues(alpha: 0.7),
              fontSize: 14,
            ),
          ),
        ),
        SizedBox(
          height: 28,
          child: Switch.adaptive(
            value: value,
            onChanged: (v) {
              onChanged(v);
              HapticFeedback.selectionClick();
            },
            activeThumbColor: const Color(0xFF2196F3),
          ),
        ),
      ],
    );
  }

  /// Commit the SectionNode with all user-chosen options.
  /// Stepper row for numeric values (rows/columns).
  Widget _sectionStepperRow({
    required IconData icon,
    required String label,
    required int value,
    required Color textColor,
    required ValueChanged<int> onChanged,
    int min = 1,
    int max = 12,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: textColor.withValues(alpha: 0.4)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: textColor.withValues(alpha: 0.7),
              fontSize: 14,
            ),
          ),
        ),
        // Minus button
        GestureDetector(
          onTap:
              value > min
                  ? () {
                    onChanged(value - 1);
                    HapticFeedback.selectionClick();
                  }
                  : null,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: textColor.withValues(alpha: value > min ? 0.1 : 0.04),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              Icons.remove_rounded,
              size: 16,
              color: textColor.withValues(alpha: value > min ? 0.6 : 0.2),
            ),
          ),
        ),
        // Value
        SizedBox(
          width: 32,
          child: Center(
            child: Text(
              '$value',
              style: TextStyle(
                color: textColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        // Plus button
        GestureDetector(
          onTap:
              value < max
                  ? () {
                    onChanged(value + 1);
                    HapticFeedback.selectionClick();
                  }
                  : null,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: textColor.withValues(alpha: value < max ? 0.1 : 0.04),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              Icons.add_rounded,
              size: 16,
              color: textColor.withValues(alpha: value < max ? 0.6 : 0.2),
            ),
          ),
        ),
      ],
    );
  }

  /// Commit the SectionNode with all user-chosen options.
  void _commitSectionWithOptions({
    required Rect sectionRect,
    required String name,
    Color? backgroundColor,
    bool showGrid = false,
    bool clipContent = false,
    SectionPreset? preset,
    int subdivisionRows = 1,
    int subdivisionColumns = 1,
    double cornerRadius = 0,
    double gridSpacing = 20,
    String gridType = 'grid',
  }) {
    final effectiveSize =
        preset != null
            ? preset.size
            : Size(sectionRect.width, sectionRect.height);

    final section = SectionNode(
      id: NodeId(generateUid()),
      sectionName: name,
      sectionSize: effectiveSize,
      backgroundColor: backgroundColor ?? Colors.white,
      showGrid: showGrid,
      gridSpacing: gridSpacing,
      gridType: gridType,
      clipContent: clipContent,
      preset: preset,
      subdivisionRows: subdivisionRows,
      subdivisionColumns: subdivisionColumns,
      cornerRadius: cornerRadius,
    );
    section.setPosition(sectionRect.left, sectionRect.top);

    final sceneGraph = _layerController.sceneGraph;
    final activeLayer =
        sceneGraph.layers.isNotEmpty ? sceneGraph.layers.first : null;
    if (activeLayer != null) {
      activeLayer.add(section);
      sceneGraph.bumpVersion();
    }

    _sectionCounter++;
    _focusedSectionNode = section;
    DrawingPainter.invalidateAllTiles();
    debugPrint('[Section] 🆕 commitSection: "$name" size=$effectiveSize gridType=$gridType pos=(${sectionRect.left}, ${sectionRect.top}) sceneV=${sceneGraph.version}');
    HapticFeedback.mediumImpact();
    _uiRebuildNotifier.value++;
    _autoSaveCanvas();
  }

  /// Append a new section to the right of [section] (same height, add column).
  /// Mirrors [_appendSectionBelow] but places horizontally.
  void _appendSectionRight(SectionNode section) {
    final tx = section.worldTransform.getTranslation();
    const gap = 200.0;

    final base =
        section.sectionName
            .replaceAll(RegExp(r'\s*[–-]\s*Col \d+$'), '')
            .trim();

    final sceneGraph = _layerController.sceneGraph;
    int existingCount = 1;
    for (final layer in sceneGraph.layers) {
      for (final child in layer.children) {
        if (child is SectionNode && child != section) {
          final childBase =
              child.sectionName
                  .replaceAll(RegExp(r'\s*[–-]\s*Col \d+$'), '')
                  .trim();
          if (childBase == base) existingCount++;
        }
      }
    }
    final newName = '$base – Col ${existingCount + 1}';

    final newSection = SectionNode(
      id: NodeId(generateUid()),
      sectionName: newName,
      sectionSize: section.sectionSize,
      backgroundColor: section.backgroundColor,
      showGrid: section.showGrid,
      gridSpacing: section.gridSpacing,
      gridType: section.gridType,
      preset: section.preset,
      clipContent: section.clipContent,
      borderColor: section.borderColor,
      borderWidth: section.borderWidth,
      subdivisionRows: section.subdivisionRows,
      subdivisionColumns: section.subdivisionColumns,
      subdivisionColor: section.subdivisionColor,
      cornerRadius: section.cornerRadius,
    );
    // Place directly right: same Y, X = original.x + width + gap
    newSection.setPosition(tx.x + section.sectionSize.width + gap, tx.y);

    for (final layer in sceneGraph.layers) {
      if (layer.children.contains(section)) {
        layer.add(newSection);
        break;
      }
    }

    sceneGraph.bumpVersion();
    DrawingPainter.invalidateAllTiles();
    debugPrint('[Section] ➕ appendRight: "${newSection.sectionName}" size=${newSection.sectionSize} gridType=${newSection.gridType} pos=(${tx.x + section.sectionSize.width + gap}, ${tx.y}) sceneV=${sceneGraph.version}');
    HapticFeedback.mediumImpact();
    _sectionCounter++;
    _focusedSectionNode = newSection;
    _layerController.notifyListeners();
    _uiRebuildNotifier.value++;
    _autoSaveCanvas();
  }
}
