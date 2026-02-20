part of 'ruler_interactive_overlay.dart';

/// Action dispatcher for the ruler corner menu.
///
/// Routes 30+ string-based menu actions to their
/// corresponding [RulerGuideSystem] calls.

extension _RulerOverlayActions on _RulerInteractiveOverlayState {
  void handleAction(String action) {
    final gs = widget.guideSystem;
    final vp = _viewportRect();

    switch (action) {
      case 'rulers':
        gs.rulersVisible = !gs.rulersVisible;
      case 'guides':
        gs.guidesVisible = !gs.guidesVisible;
      case 'grid':
        gs.gridVisible = !gs.gridVisible;
      case 'gridSnap':
        gs.gridSnapEnabled = !gs.gridSnapEnabled;
      case 'snap':
        gs.snapEnabled = !gs.snapEnabled;
      case 'smartGuides':
        gs.smartGuidesEnabled = !gs.smartGuidesEnabled;
      case 'isometric':
        gs.isometricGridVisible = !gs.isometricGridVisible;
      case 'symmetry':
        if (gs.symmetryEnabled) {
          gs.clearSymmetry();
        } else {
          // Auto-set first vertical guide as axis, or prompt user
          if (gs.verticalGuides.isNotEmpty) {
            gs.setSymmetryAxis(false, 0);
          } else if (gs.horizontalGuides.isNotEmpty) {
            gs.setSymmetryAxis(true, 0);
          } else {
            // Create a center guide and use it as axis
            gs.saveSnapshot();
            gs.addVerticalGuide(vp.center.dx);
            gs.setSymmetryAxis(false, gs.verticalGuides.length - 1);
          }
        }
      case 'gridStyle':
        final values = GridStyle.values;
        gs.gridStyle = values[(gs.gridStyle.index + 1) % values.length];
      case 'cycleUnit':
        gs.cycleUnit();
      case 'crosshair':
        gs.crosshairEnabled = !gs.crosshairEnabled;
      case 'measure':
        gs.isMeasuring = true;
        gs.clearMeasurement();
      case 'multiSelect':
        gs.multiSelectMode = !gs.multiSelectMode;
        if (!gs.multiSelectMode) gs.clearSelection();
      case 'undo':
        gs.undo();
      case 'redo':
        gs.redo();
      case 'persp1':
        gs.initPerspective(PerspectiveType.onePoint, vp);
      case 'persp2':
        gs.initPerspective(PerspectiveType.twoPoint, vp);
      case 'persp3':
        gs.initPerspective(PerspectiveType.threePoint, vp);
      case 'perspOff':
        gs.perspectiveType = PerspectiveType.none;
      case 'radial':
        gs.radialGridVisible = !gs.radialGridVisible;
        if (gs.radialGridVisible) gs.initRadialGrid(vp);
      case 'center':
        gs.addCenterPreset(vp);
      case 'thirds':
        gs.addThirdsPreset(vp);
      case 'golden':
        gs.addGoldenRatioPreset(vp);
      case 'margins':
        gs.addMarginsPreset(vp, 50);
      case 'ar16_9':
        gs.addAspectRatioPreset(vp, 16 / 9);
      case 'ar4_3':
        gs.addAspectRatioPreset(vp, 4 / 3);
      case 'ar1_1':
        gs.addAspectRatioPreset(vp, 1);
      case 'arA4':
        gs.addAspectRatioPreset(vp, 210 / 297);
      case 'clear':
        gs.clearAllGuides();
      case 'distribute':
        gs.distributeSelectedGuides();
      case 'addBookmark':
        // Add bookmark at center of viewport
        final center = vp.center;
        final canvasX =
            (center.dx - widget.canvasController.offset.dx) /
            widget.canvasController.scale;
        final canvasY =
            (center.dy - widget.canvasController.offset.dy) /
            widget.canvasController.scale;
        gs.addBookmark(canvasY, true, const Color(0xFFFF5722));
        gs.addBookmark(canvasX, false, const Color(0xFF2196F3));
      case 'clearBookmarks':
        gs.clearBookmarks();
      case 'exportGuides':
        final json = gs.exportGuidesJson();
        final jsonStr = json.toString();
        Clipboard.setData(ClipboardData(text: jsonStr));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Guides copied to clipboard'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      case 'importGuides':
        Clipboard.getData(Clipboard.kTextPlain).then((clip) {
          if (clip?.text != null) {
            try {
              // Simple parsing — expect Map-like format
              // For robustness, would use dart:convert
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Paste guides from the Export menu'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            } catch (e) {
              debugPrint('[RulerOverlay] importGuides parse error: $e');
            }
          }
        });
      // Color theme actions
      case 'themeDefault':
        gs.guideColorTheme = GuideColorTheme.defaultTheme;
      case 'themeBlueprint':
        gs.guideColorTheme = GuideColorTheme.blueprint;
      case 'themeNeon':
        gs.guideColorTheme = GuideColorTheme.neon;
      case 'themeMinimal':
        gs.guideColorTheme = GuideColorTheme.minimal;
      // Mirror guide
      case 'mirrorGuide':
        if (gs.selectedHorizontalGuides.isNotEmpty) {
          gs.mirrorGuide(
            true,
            gs.selectedHorizontalGuides.first,
            MediaQuery.of(context).size.height,
          );
        } else if (gs.selectedVerticalGuides.isNotEmpty) {
          gs.mirrorGuide(
            false,
            gs.selectedVerticalGuides.first,
            MediaQuery.of(context).size.width,
          );
        }
      // Percentage guides
      case 'addPercent50H':
        gs.addPercentGuide(true, 50.0, MediaQuery.of(context).size.height);
      case 'addPercent50V':
        gs.addPercentGuide(false, 50.0, MediaQuery.of(context).size.width);
      // Guide labels
      case 'guideLabels':
        gs.showGuideLabels = !gs.showGuideLabels;
      case 'symSegments':
        gs.cycleSymmetrySegments();
      case 'addAngular':
        gs.saveSnapshot();
        gs.addAngularGuide(vp.center, 45.0);
      case 'clearAngular':
        gs.saveSnapshot();
        gs.clearAngularGuides();
      case 'protractor':
        if (gs.isProtractorMode) {
          gs.clearProtractor();
        } else {
          gs.isProtractorMode = true;
          gs.protractorCenter = vp.center;
        }
      case 'resetOrigin':
        gs.resetRulerOrigin();
      case 'customGrid':
        if (gs.customGridStep != null) {
          gs.customGridStep = null;
        } else {
          showCustomGridDialog();
        }
      case 'savePreset':
        showSavePresetDialog();
      // Golden spiral
      case 'goldenSpiral':
        gs.showGoldenSpiral = !gs.showGoldenSpiral;
      case 'snapStep':
        // Cycle: 5 → 10 → 15 → 30 → 45 → 90 → 5
        const steps = [5.0, 10.0, 15.0, 30.0, 45.0, 90.0];
        final idx = steps.indexOf(gs.protractorSnapStep);
        gs.protractorSnapStep = steps[(idx + 1) % steps.length];
      case 'groupGuides':
        final groupId = gs.groupSelectedGuides();
        if (groupId < 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Select at least one guide to group'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      case 'exportPresets':
        final json = gs.exportPresetsToJson();
        debugPrint('Guide presets JSON: $json');
      // Batch operations
      case 'lockAll':
        gs.lockAllGuides();
      case 'unlockAll':
        gs.unlockAllGuides();
      case 'deleteSelected':
        gs.saveSnapshot();
        gs.deleteSelectedGuides();
      case 'mirrorH':
        gs.saveSnapshot();
        gs.mirrorGuidesH(_viewportRect());
      case 'mirrorV':
        gs.saveSnapshot();
        gs.mirrorGuidesV(_viewportRect());
      default:
        // loadPreset_N
        if (action.startsWith('loadPreset_')) {
          final idx = int.tryParse(action.substring('loadPreset_'.length));
          if (idx != null && idx < gs.savedPresets.length) {
            gs.importPreset(gs.savedPresets[idx]);
          }
        }
    }

    HapticFeedback.selectionClick();
    widget.onChanged();
    if (mounted) setState(() {});
  }
}
