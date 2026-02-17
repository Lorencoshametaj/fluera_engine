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
                          _sheetIconBtn(Icons.undo, 'undo', dark, ctx),
                        if (gs.canRedo)
                          _sheetIconBtn(Icons.redo, 'redo', dark, ctx),
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
                        _sectionHeader(
                          'Visibility',
                          Icons.visibility,
                          const Color(0xFF42A5F5),
                          description:
                              'Show or hide rulers, guides, grids and labels on the canvas.',
                        ),
                        _sheetToggle(
                          'rulers',
                          Icons.straighten,
                          'Rulers',
                          gs.rulersVisible,
                          dark,
                          ctx,
                          setSheetState,
                        ),
                        _sheetToggle(
                          'guides',
                          Icons.linear_scale,
                          'Guides',
                          gs.guidesVisible,
                          dark,
                          ctx,
                          setSheetState,
                        ),
                        _sheetToggle(
                          'grid',
                          Icons.grid_4x4,
                          'Grid',
                          gs.gridVisible,
                          dark,
                          ctx,
                          setSheetState,
                        ),
                        _sheetToggle(
                          'guideLabels',
                          Icons.label_outline,
                          'Guide Labels',
                          gs.showGuideLabels,
                          dark,
                          ctx,
                          setSheetState,
                        ),
                        _sheetToggle(
                          'goldenSpiral',
                          Icons.filter_tilt_shift,
                          'Golden Spiral',
                          gs.showGoldenSpiral,
                          dark,
                          ctx,
                          setSheetState,
                        ),

                        // ━━ Snap & Alignment ━━
                        _sectionHeader(
                          'Snap & Alignment',
                          Icons.grain,
                          const Color(0xFF66BB6A),
                          description:
                              'Enable magnetic snapping to grid, guides and smart guides for precise alignment.',
                        ),
                        _sheetToggle(
                          'gridSnap',
                          Icons.apps,
                          'Grid Snap',
                          gs.gridSnapEnabled,
                          dark,
                          ctx,
                          setSheetState,
                        ),
                        _sheetToggle(
                          'snap',
                          Icons.grain,
                          'Guide Snap',
                          gs.snapEnabled,
                          dark,
                          ctx,
                          setSheetState,
                        ),
                        _sheetToggle(
                          'smartGuides',
                          Icons.auto_fix_high,
                          'Smart Guides',
                          gs.smartGuidesEnabled,
                          dark,
                          ctx,
                          setSheetState,
                        ),
                        _sheetToggle(
                          'crosshair',
                          Icons.control_camera,
                          'Crosshair',
                          gs.crosshairEnabled,
                          dark,
                          ctx,
                          setSheetState,
                        ),
                        _sheetAction(
                          'snapStep',
                          Icons.rotate_90_degrees_cw,
                          'Angular Snap: ${gs.protractorSnapStep.toInt()}°',
                          dark,
                          ctx,
                        ),

                        // ━━ Grid & Units ━━
                        _sectionHeader(
                          'Grid & Units',
                          Icons.grid_on,
                          const Color(0xFFAB47BC),
                          description:
                              'Change grid style (lines, dots, crosses), units and special grids.',
                        ),
                        _sheetAction(
                          'gridStyle',
                          Icons.grid_on,
                          'Style: ${_gridStyleLabel(gs.gridStyle)}',
                          dark,
                          ctx,
                        ),
                        _sheetAction(
                          'cycleUnit',
                          Icons.square_foot,
                          'Unit: ${gs.unitSuffix}',
                          dark,
                          ctx,
                        ),
                        _sheetToggle(
                          'isometric',
                          Icons.architecture,
                          'Isometric Grid',
                          gs.isometricGridVisible,
                          dark,
                          ctx,
                          setSheetState,
                        ),
                        _sheetAction(
                          'customGrid',
                          Icons.space_bar,
                          gs.customGridStep != null
                              ? 'Grid: ${gs.customGridStep!.toInt()}px'
                              : 'Custom Grid',
                          dark,
                          ctx,
                        ),
                        _sheetAction(
                          'radial',
                          Icons.radio_button_unchecked,
                          gs.radialGridVisible
                              ? 'Hide Radial Grid'
                              : 'Radial Grid',
                          dark,
                          ctx,
                        ),

                        // ━━ Tools ━━
                        _sectionHeader(
                          'Tools',
                          Icons.build_outlined,
                          const Color(0xFFFFA726),
                          description:
                              'Measure distances, use the protractor, symmetry and angular guides for advanced compositions.',
                        ),
                        _sheetAction(
                          'measure',
                          Icons.design_services,
                          'Measure Distance',
                          dark,
                          ctx,
                        ),
                        _sheetAction(
                          'multiSelect',
                          Icons.select_all,
                          'Multi-select',
                          dark,
                          ctx,
                        ),
                        _sheetToggle(
                          'symmetry',
                          Icons.flip,
                          'Symmetry',
                          gs.symmetryEnabled,
                          dark,
                          ctx,
                          setSheetState,
                        ),
                        _sheetAction(
                          'symSegments',
                          Icons.blur_circular,
                          'Symmetry: ${gs.symmetrySegments}× segments',
                          dark,
                          ctx,
                        ),
                        _sheetAction(
                          'addAngular',
                          Icons.rotate_right,
                          'Angular Guide (45°)',
                          dark,
                          ctx,
                        ),
                        _sheetAction(
                          'clearAngular',
                          Icons.layers_clear_outlined,
                          'Remove Angular Guides',
                          dark,
                          ctx,
                        ),
                        _sheetAction(
                          'protractor',
                          Icons.architecture_outlined,
                          gs.isProtractorMode
                              ? 'Close Protractor'
                              : 'Protractor',
                          dark,
                          ctx,
                        ),
                        _sheetAction(
                          'resetOrigin',
                          Icons.my_location,
                          'Reset Origin',
                          dark,
                          ctx,
                        ),
                        _sheetAction(
                          'addBookmark',
                          Icons.bookmark_add,
                          'Add Bookmark',
                          dark,
                          ctx,
                        ),
                        if (gs.bookmarkMarks.isNotEmpty)
                          _sheetAction(
                            'clearBookmarks',
                            Icons.bookmark_remove,
                            'Remove Bookmarks',
                            dark,
                            ctx,
                          ),

                        // ━━ Guides & Distribution ━━
                        _sectionHeader(
                          'Guides',
                          Icons.linear_scale,
                          const Color(0xFF26C6DA),
                          description:
                              'Mirror, distribute and add percentage guides for precise layouts.',
                        ),
                        _sheetAction(
                          'mirrorGuide',
                          Icons.flip,
                          'Mirror Guide',
                          dark,
                          ctx,
                        ),
                        _sheetAction(
                          'mirrorH',
                          Icons.swap_vert,
                          'Mirror Horizontal',
                          dark,
                          ctx,
                        ),
                        _sheetAction(
                          'mirrorV',
                          Icons.swap_horiz,
                          'Mirror Vertical',
                          dark,
                          ctx,
                        ),
                        _sheetAction(
                          'addPercent50H',
                          Icons.percent,
                          '50% Horizontal Guide',
                          dark,
                          ctx,
                        ),
                        _sheetAction(
                          'addPercent50V',
                          Icons.percent,
                          '50% Vertical Guide',
                          dark,
                          ctx,
                        ),
                        _sheetAction(
                          'distribute',
                          Icons.view_column,
                          'Distribute Guides...',
                          dark,
                          ctx,
                        ),
                        if (gs.selectedHorizontalGuides.length >= 3 ||
                            gs.selectedVerticalGuides.length >= 3)
                          _sheetAction(
                            'distribute',
                            Icons.horizontal_distribute,
                            'Distribute Evenly',
                            dark,
                            ctx,
                          ),
                        _sheetAction(
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
                        _sectionHeader(
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
                              _themeChip(
                                'themeDefault',
                                'Default',
                                const Color(0xFF42A5F5),
                                dark,
                                ctx,
                              ),
                              _themeChip(
                                'themeBlueprint',
                                'Blueprint',
                                const Color(0xFF1565C0),
                                dark,
                                ctx,
                              ),
                              _themeChip(
                                'themeNeon',
                                'Neon',
                                const Color(0xFF76FF03),
                                dark,
                                ctx,
                              ),
                              _themeChip(
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
                        _sectionHeader(
                          'Perspective',
                          Icons.view_in_ar,
                          const Color(0xFF7E57C2),
                          description:
                              'Enable 1, 2 or 3 vanishing point perspective grids for 3D drawing.',
                        ),
                        _sheetAction(
                          'persp1',
                          Icons.change_history,
                          '1 Point',
                          dark,
                          ctx,
                        ),
                        _sheetAction(
                          'persp2',
                          Icons.view_in_ar,
                          '2 Points',
                          dark,
                          ctx,
                        ),
                        _sheetAction(
                          'persp3',
                          Icons.hub,
                          '3 Points',
                          dark,
                          ctx,
                        ),
                        _sheetAction(
                          'perspOff',
                          Icons.layers_clear,
                          'Remove Perspective',
                          dark,
                          ctx,
                        ),

                        // ━━ Presets ━━
                        _sectionHeader(
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
                              _presetChip(
                                'center',
                                'Center',
                                Icons.center_focus_strong,
                                dark,
                                ctx,
                              ),
                              _presetChip(
                                'thirds',
                                'Thirds',
                                Icons.grid_3x3,
                                dark,
                                ctx,
                              ),
                              _presetChip(
                                'golden',
                                'Golden',
                                Icons.auto_awesome,
                                dark,
                                ctx,
                              ),
                              _presetChip(
                                'margins',
                                'Margins',
                                Icons.border_outer,
                                dark,
                                ctx,
                              ),
                              _presetChip(
                                'ar16_9',
                                '16:9',
                                Icons.crop_16_9,
                                dark,
                                ctx,
                              ),
                              _presetChip(
                                'ar4_3',
                                '4:3',
                                Icons.crop_7_5,
                                dark,
                                ctx,
                              ),
                              _presetChip(
                                'ar1_1',
                                '1:1',
                                Icons.crop_square,
                                dark,
                                ctx,
                              ),
                              _presetChip(
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
                          _sheetAction(
                            'savePreset',
                            Icons.bookmark_add,
                            'Save Preset',
                            dark,
                            ctx,
                          ),
                          ...gs.savedPresets.asMap().entries.map(
                            (e) => _sheetAction(
                              'loadPreset_${e.key}',
                              Icons.bookmark,
                              'Load: ${e.value.name}',
                              dark,
                              ctx,
                            ),
                          ),
                        ] else
                          _sheetAction(
                            'savePreset',
                            Icons.bookmark_add,
                            'Save Guide Preset',
                            dark,
                            ctx,
                          ),

                        // ━━ Import/Export ━━
                        _sectionHeader(
                          'Import / Export',
                          Icons.sync_alt,
                          const Color(0xFF78909C),
                          description:
                              'Save guides as JSON and import them into other canvases.',
                        ),
                        _sheetAction(
                          'exportGuides',
                          Icons.file_upload_outlined,
                          'Export Guides',
                          dark,
                          ctx,
                        ),
                        _sheetAction(
                          'importGuides',
                          Icons.file_download_outlined,
                          'Import Guides',
                          dark,
                          ctx,
                        ),
                        _sheetAction(
                          'exportPresets',
                          Icons.file_upload_outlined,
                          'Export Presets (JSON)',
                          dark,
                          ctx,
                        ),

                        // ━━ Batch operations ━━
                        _sectionHeader(
                          'Batch Operations',
                          Icons.layers,
                          const Color(0xFFFF7043),
                          description:
                              'Lock, unlock or delete all selected guides at once.',
                        ),
                        _sheetAction(
                          'lockAll',
                          Icons.lock,
                          'Lock All',
                          dark,
                          ctx,
                        ),
                        _sheetAction(
                          'unlockAll',
                          Icons.lock_open,
                          'Unlock All',
                          dark,
                          ctx,
                        ),
                        if (gs.selectedCount > 0)
                          _sheetAction(
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

  // ─── MD3 Sheet Helpers ─────────────────────────────────────────

  Widget _sectionHeader(
    String title,
    IconData icon,
    Color accent, {
    String? description,
  }) {
    final dark = widget.isDark;
    return Container(
      padding: const EdgeInsets.only(left: 16, right: 12, top: 14, bottom: 6),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: dark ? 0.15 : 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 13, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: accent.withValues(alpha: 0.9),
                letterSpacing: 1.0,
              ),
            ),
          ),
          if (description != null)
            Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () {
                  showDialog(
                    context: context,
                    barrierColor: Colors.black26,
                    builder: (dCtx) {
                      // Auto-dismiss after 3 seconds
                      Future.delayed(const Duration(seconds: 3), () {
                        if (Navigator.of(dCtx).canPop()) {
                          Navigator.of(dCtx).pop();
                        }
                      });
                      return Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(
                            left: 24,
                            right: 24,
                            bottom: 100,
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    dark
                                        ? accent.withValues(alpha: 0.9)
                                        : accent,
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: accent.withValues(alpha: 0.3),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.info_outline,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 10),
                                  Flexible(
                                    child: Text(
                                      description,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.info_outline,
                    size: 15,
                    color: dark ? Colors.white24 : const Color(0xFFBBBBBB),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sheetToggle(
    String value,
    IconData icon,
    String label,
    bool on,
    bool dark,
    BuildContext ctx,
    StateSetter setSheetState,
  ) {
    final tc = dark ? Colors.white : const Color(0xFF1A1A1A);
    final sc = dark ? Colors.white38 : const Color(0xFF999999);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.pop(ctx, value);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 18, color: on ? tc : sc),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: on ? tc : sc,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              SizedBox(
                width: 40,
                height: 22,
                child: FittedBox(
                  child: Switch.adaptive(
                    value: on,
                    activeTrackColor: const Color(0xFF00BCD4),
                    onChanged: (_) {
                      Navigator.pop(ctx, value);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetAction(
    String value,
    IconData icon,
    String label,
    bool dark,
    BuildContext ctx, {
    bool destructive = false,
  }) {
    final c =
        destructive
            ? const Color(0xFFE53935)
            : (dark ? Colors.white : const Color(0xFF1A1A1A));
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.pop(ctx, value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 18, color: c.withValues(alpha: 0.7)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: c,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 14,
                color: dark ? const Color(0xFF555555) : const Color(0xFFCCCCCC),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetIconBtn(
    IconData icon,
    String value,
    bool dark,
    BuildContext ctx,
  ) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => Navigator.pop(ctx, value),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              icon,
              size: 18,
              color: dark ? const Color(0xFF90A4AE) : const Color(0xFF607D8B),
            ),
          ),
        ),
      ),
    );
  }

  Widget _themeChip(
    String value,
    String label,
    Color color,
    bool dark,
    BuildContext ctx,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.pop(ctx, value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: dark ? 0.15 : 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: dark ? Colors.white70 : const Color(0xFF424242),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _presetChip(
    String value,
    String label,
    IconData icon,
    bool dark,
    BuildContext ctx,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => Navigator.pop(ctx, value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF2A2A2A) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: dark ? const Color(0xFF444444) : const Color(0xFFE0E0E0),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: dark ? const Color(0xFF90A4AE) : const Color(0xFF607D8B),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: dark ? Colors.white70 : const Color(0xFF424242),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _gridStyleLabel(GridStyle style) {
    switch (style) {
      case GridStyle.lines:
        return 'Lines';
      case GridStyle.dots:
        return 'Dots';
      case GridStyle.crosses:
        return 'Crosses';
    }
  }
}
