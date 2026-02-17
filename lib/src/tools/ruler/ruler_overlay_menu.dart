part of 'ruler_interactive_overlay.dart';

/// Corner menu bottom sheet and MD3 sheet UI helpers
/// for the [RulerInteractiveOverlay].

// ─── Corner Menu (MD3 Bottom Sheet) ─────────────────────────────

extension _RulerOverlayMenu on _RulerInteractiveOverlayState {
  void showCornerMenu() {
    HapticFeedback.selectionClick();
    final gs = widget.guideSystem;
    final dark = widget.isDark;

    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.75,
              ),
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF1E1E1E) : const Color(0xFFF7F7F7),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Drag handle ──
                  Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 4),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color:
                          dark
                              ? const Color(0xFF555555)
                              : const Color(0xFFCCCCCC),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // ── Title bar ──
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.straighten,
                          size: 18,
                          color:
                              dark
                                  ? const Color(0xFF80CBC4)
                                  : const Color(0xFF00897B),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Ruler Settings',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color:
                                dark ? Colors.white : const Color(0xFF1A1A1A),
                            letterSpacing: 0.2,
                          ),
                        ),
                        const Spacer(),
                        // Undo/Redo quick actions
                        if (gs.canUndo)
                          sheetIconBtn(Icons.undo, 'undo', dark, ctx),
                        if (gs.canRedo)
                          sheetIconBtn(Icons.redo, 'redo', dark, ctx),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    color:
                        dark
                            ? const Color(0xFF333333)
                            : const Color(0xFFE0E0E0),
                  ),
                  // ── Scrollable sections ──
                  Flexible(
                    child: ListView(
                      padding: const EdgeInsets.only(bottom: 20),
                      shrinkWrap: true,
                      children: [
                        // ━━ Visibility ━━
                        sectionHeader(
                          'Visibility',
                          Icons.visibility,
                          const Color(0xFF42A5F5),
                          description:
                              'Show or hide rulers, guides, grids and labels on the canvas.',
                        ),
                        sheetToggle(
                          'rulers',
                          Icons.straighten,
                          'Rulers',
                          gs.rulersVisible,
                          dark,
                          ctx,
                          setSheetState,
                        ),
                        sheetToggle(
                          'guides',
                          Icons.linear_scale,
                          'Guides',
                          gs.guidesVisible,
                          dark,
                          ctx,
                          setSheetState,
                        ),
                        sheetToggle(
                          'grid',
                          Icons.grid_4x4,
                          'Grid',
                          gs.gridVisible,
                          dark,
                          ctx,
                          setSheetState,
                        ),
                        sheetToggle(
                          'guideLabels',
                          Icons.label_outline,
                          'Guide Labels',
                          gs.showGuideLabels,
                          dark,
                          ctx,
                          setSheetState,
                        ),
                        sheetToggle(
                          'goldenSpiral',
                          Icons.filter_tilt_shift,
                          'Golden Spiral',
                          gs.showGoldenSpiral,
                          dark,
                          ctx,
                          setSheetState,
                        ),

                        // ━━ Snap & Alignment ━━
                        sectionHeader(
                          'Snap & Alignment',
                          Icons.grain,
                          const Color(0xFF66BB6A),
                          description:
                              'Enable magnetic snapping to grid, guides and smart guides for precise alignment.',
                        ),
                        sheetToggle(
                          'gridSnap',
                          Icons.apps,
                          'Grid Snap',
                          gs.gridSnapEnabled,
                          dark,
                          ctx,
                          setSheetState,
                        ),
                        sheetToggle(
                          'snap',
                          Icons.grain,
                          'Guide Snap',
                          gs.snapEnabled,
                          dark,
                          ctx,
                          setSheetState,
                        ),
                        sheetToggle(
                          'smartGuides',
                          Icons.auto_fix_high,
                          'Smart Guides',
                          gs.smartGuidesEnabled,
                          dark,
                          ctx,
                          setSheetState,
                        ),
                        sheetToggle(
                          'crosshair',
                          Icons.control_camera,
                          'Crosshair',
                          gs.crosshairEnabled,
                          dark,
                          ctx,
                          setSheetState,
                        ),
                        sheetAction(
                          'snapStep',
                          Icons.rotate_90_degrees_cw,
                          'Angular Snap: ${gs.protractorSnapStep.toInt()}°',
                          dark,
                          ctx,
                        ),

                        // ━━ Grid & Units ━━
                        sectionHeader(
                          'Grid & Units',
                          Icons.grid_on,
                          const Color(0xFFAB47BC),
                          description:
                              'Change grid style (lines, dots, crosses), units and special grids.',
                        ),
                        sheetAction(
                          'gridStyle',
                          Icons.grid_on,
                          'Style: ${gridStyleLabel(gs.gridStyle)}',
                          dark,
                          ctx,
                        ),
                        sheetAction(
                          'cycleUnit',
                          Icons.square_foot,
                          'Unit: ${gs.unitSuffix}',
                          dark,
                          ctx,
                        ),
                        sheetToggle(
                          'isometric',
                          Icons.architecture,
                          'Isometric Grid',
                          gs.isometricGridVisible,
                          dark,
                          ctx,
                          setSheetState,
                        ),
                        sheetAction(
                          'customGrid',
                          Icons.space_bar,
                          gs.customGridStep != null
                              ? 'Grid: ${gs.customGridStep!.toInt()}px'
                              : 'Custom Grid',
                          dark,
                          ctx,
                        ),
                        sheetAction(
                          'radial',
                          Icons.radio_button_unchecked,
                          gs.radialGridVisible
                              ? 'Hide Radial Grid'
                              : 'Radial Grid',
                          dark,
                          ctx,
                        ),

                        // ━━ Tools ━━
                        sectionHeader(
                          'Tools',
                          Icons.build_outlined,
                          const Color(0xFFFFA726),
                          description:
                              'Measure distances, use the protractor, symmetry and angular guides for advanced compositions.',
                        ),
                        sheetAction(
                          'measure',
                          Icons.design_services,
                          'Measure Distance',
                          dark,
                          ctx,
                        ),
                        sheetAction(
                          'multiSelect',
                          Icons.select_all,
                          'Multi-select',
                          dark,
                          ctx,
                        ),
                        sheetToggle(
                          'symmetry',
                          Icons.flip,
                          'Symmetry',
                          gs.symmetryEnabled,
                          dark,
                          ctx,
                          setSheetState,
                        ),
                        sheetAction(
                          'symSegments',
                          Icons.blur_circular,
                          'Symmetry: ${gs.symmetrySegments}× segments',
                          dark,
                          ctx,
                        ),
                        sheetAction(
                          'addAngular',
                          Icons.rotate_right,
                          'Angular Guide (45°)',
                          dark,
                          ctx,
                        ),
                        sheetAction(
                          'clearAngular',
                          Icons.layers_clear_outlined,
                          'Remove Angular Guides',
                          dark,
                          ctx,
                        ),
                        sheetAction(
                          'protractor',
                          Icons.architecture_outlined,
                          gs.isProtractorMode
                              ? 'Close Protractor'
                              : 'Protractor',
                          dark,
                          ctx,
                        ),
                        sheetAction(
                          'resetOrigin',
                          Icons.my_location,
                          'Reset Origin',
                          dark,
                          ctx,
                        ),
                        sheetAction(
                          'addBookmark',
                          Icons.bookmark_add,
                          'Add Bookmark',
                          dark,
                          ctx,
                        ),
                        if (gs.bookmarkMarks.isNotEmpty)
                          sheetAction(
                            'clearBookmarks',
                            Icons.bookmark_remove,
                            'Remove Bookmarks',
                            dark,
                            ctx,
                          ),

                        // ━━ Guides & Distribution ━━
                        sectionHeader(
                          'Guides',
                          Icons.linear_scale,
                          const Color(0xFF26C6DA),
                          description:
                              'Mirror, distribute and add percentage guides for precise layouts.',
                        ),
                        sheetAction(
                          'mirrorGuide',
                          Icons.flip,
                          'Mirror Guide',
                          dark,
                          ctx,
                        ),
                        sheetAction(
                          'mirrorH',
                          Icons.swap_vert,
                          'Mirror Horizontal',
                          dark,
                          ctx,
                        ),
                        sheetAction(
                          'mirrorV',
                          Icons.swap_horiz,
                          'Mirror Vertical',
                          dark,
                          ctx,
                        ),
                        sheetAction(
                          'addPercent50H',
                          Icons.percent,
                          '50% Horizontal Guide',
                          dark,
                          ctx,
                        ),
                        sheetAction(
                          'addPercent50V',
                          Icons.percent,
                          '50% Vertical Guide',
                          dark,
                          ctx,
                        ),
                        sheetAction(
                          'distribute',
                          Icons.view_column,
                          'Distribute Guides...',
                          dark,
                          ctx,
                        ),
                        if (gs.selectedHorizontalGuides.length >= 3 ||
                            gs.selectedVerticalGuides.length >= 3)
                          sheetAction(
                            'distribute',
                            Icons.horizontal_distribute,
                            'Distribute Evenly',
                            dark,
                            ctx,
                          ),
                        sheetAction(
                          'groupGuides',
                          Icons.workspaces,
                          'Group Selected',
                          dark,
                          ctx,
                        ),

                        // ━━ Opacity slider ━━
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.opacity,
                                size: 16,
                                color:
                                    dark
                                        ? const Color(0xFF90A4AE)
                                        : const Color(0xFF607D8B),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Opacity',
                                style: TextStyle(
                                  fontSize: 13,
                                  color:
                                      dark
                                          ? Colors.white70
                                          : const Color(0xFF424242),
                                ),
                              ),
                              Expanded(
                                child: SliderTheme(
                                  data: SliderThemeData(
                                    trackHeight: 3,
                                    thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 6,
                                    ),
                                    activeTrackColor: const Color(0xFF00BCD4),
                                    inactiveTrackColor:
                                        dark
                                            ? const Color(0xFF444444)
                                            : const Color(0xFFD0D0D0),
                                    thumbColor: const Color(0xFF00BCD4),
                                    overlayShape: const RoundSliderOverlayShape(
                                      overlayRadius: 14,
                                    ),
                                  ),
                                  child: Slider(
                                    value: gs.guideOpacity,
                                    min: 0.1,
                                    max: 1.0,
                                    onChanged: (v) {
                                      setSheetState(() => gs.guideOpacity = v);
                                      widget.onChanged();
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // ━━ Color themes ━━
                        sectionHeader(
                          'Color Theme',
                          Icons.palette,
                          const Color(0xFFEF5350),
                          description:
                              'Choose a visual theme for guides: default, blueprint, neon or minimal.',
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              themeChip(
                                'themeDefault',
                                'Default',
                                const Color(0xFF42A5F5),
                                dark,
                                ctx,
                              ),
                              themeChip(
                                'themeBlueprint',
                                'Blueprint',
                                const Color(0xFF1565C0),
                                dark,
                                ctx,
                              ),
                              themeChip(
                                'themeNeon',
                                'Neon',
                                const Color(0xFF76FF03),
                                dark,
                                ctx,
                              ),
                              themeChip(
                                'themeMinimal',
                                'Minimal',
                                const Color(0xFF9E9E9E),
                                dark,
                                ctx,
                              ),
                            ],
                          ),
                        ),

                        // ━━ Perspective ━━
                        sectionHeader(
                          'Perspective',
                          Icons.view_in_ar,
                          const Color(0xFF7E57C2),
                          description:
                              'Enable 1, 2 or 3 vanishing point perspective grids for 3D drawing.',
                        ),
                        sheetAction(
                          'persp1',
                          Icons.change_history,
                          '1 Point',
                          dark,
                          ctx,
                        ),
                        sheetAction(
                          'persp2',
                          Icons.view_in_ar,
                          '2 Points',
                          dark,
                          ctx,
                        ),
                        sheetAction(
                          'persp3',
                          Icons.hub,
                          '3 Points',
                          dark,
                          ctx,
                        ),
                        sheetAction(
                          'perspOff',
                          Icons.layers_clear,
                          'Remove Perspective',
                          dark,
                          ctx,
                        ),

                        // ━━ Presets ━━
                        sectionHeader(
                          'Presets',
                          Icons.auto_awesome,
                          const Color(0xFFFFCA28),
                          description:
                              'Preset guides: rule of thirds, golden ratio, margins and standard proportions.',
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              presetChip(
                                'center',
                                'Center',
                                Icons.center_focus_strong,
                                dark,
                                ctx,
                              ),
                              presetChip(
                                'thirds',
                                'Thirds',
                                Icons.grid_3x3,
                                dark,
                                ctx,
                              ),
                              presetChip(
                                'golden',
                                'Golden',
                                Icons.auto_awesome,
                                dark,
                                ctx,
                              ),
                              presetChip(
                                'margins',
                                'Margins',
                                Icons.border_outer,
                                dark,
                                ctx,
                              ),
                              presetChip(
                                'ar16_9',
                                '16:9',
                                Icons.crop_16_9,
                                dark,
                                ctx,
                              ),
                              presetChip(
                                'ar4_3',
                                '4:3',
                                Icons.crop_7_5,
                                dark,
                                ctx,
                              ),
                              presetChip(
                                'ar1_1',
                                '1:1',
                                Icons.crop_square,
                                dark,
                                ctx,
                              ),
                              presetChip(
                                'arA4',
                                'A4',
                                Icons.description,
                                dark,
                                ctx,
                              ),
                            ],
                          ),
                        ),

                        // Saved presets
                        if (gs.savedPresets.isNotEmpty) ...[
                          sheetAction(
                            'savePreset',
                            Icons.bookmark_add,
                            'Save Preset',
                            dark,
                            ctx,
                          ),
                          ...gs.savedPresets.asMap().entries.map(
                            (e) => sheetAction(
                              'loadPreset_${e.key}',
                              Icons.bookmark,
                              'Load: ${e.value.name}',
                              dark,
                              ctx,
                            ),
                          ),
                        ] else
                          sheetAction(
                            'savePreset',
                            Icons.bookmark_add,
                            'Save Guide Preset',
                            dark,
                            ctx,
                          ),

                        // ━━ Import/Export ━━
                        sectionHeader(
                          'Import / Export',
                          Icons.sync_alt,
                          const Color(0xFF78909C),
                          description:
                              'Save guides as JSON and import them into other canvases.',
                        ),
                        sheetAction(
                          'exportGuides',
                          Icons.file_upload_outlined,
                          'Export Guides',
                          dark,
                          ctx,
                        ),
                        sheetAction(
                          'importGuides',
                          Icons.file_download_outlined,
                          'Import Guides',
                          dark,
                          ctx,
                        ),
                        sheetAction(
                          'exportPresets',
                          Icons.file_upload_outlined,
                          'Export Presets (JSON)',
                          dark,
                          ctx,
                        ),

                        // ━━ Batch operations ━━
                        sectionHeader(
                          'Batch Operations',
                          Icons.layers,
                          const Color(0xFFFF7043),
                          description:
                              'Lock, unlock or delete all selected guides at once.',
                        ),
                        sheetAction(
                          'lockAll',
                          Icons.lock,
                          'Lock All',
                          dark,
                          ctx,
                        ),
                        sheetAction(
                          'unlockAll',
                          Icons.lock_open,
                          'Unlock All',
                          dark,
                          ctx,
                        ),
                        if (gs.selectedCount > 0)
                          sheetAction(
                            'deleteSelected',
                            Icons.delete_outline,
                            'Delete Selected (${gs.selectedCount})',
                            dark,
                            ctx,
                            destructive: true,
                          ),

                        const SizedBox(height: 8),
                        // ━━ Danger zone ━━
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () {
                                Navigator.pop(ctx, 'clear');
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: const Color(
                                      0xFFE53935,
                                    ).withValues(alpha: 0.3),
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.delete_sweep,
                                      size: 16,
                                      color: Color(0xFFE53935),
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Clear All Guides',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFFE53935),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).then((v) {
      if (v != null) handleAction(v);
    });
  }
}
