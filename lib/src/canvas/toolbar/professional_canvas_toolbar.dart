library professional_canvas_toolbar;

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import '../../utils/key_value_store.dart';
import '../../core/tabular/cell_node.dart';
import './formula_reference_sheet.dart';
import './hsv_color_picker.dart';
import './pro_color_picker.dart';
import '../overlays/eyedropper_overlay.dart';
import '../../core/engine_scope.dart';
import '../../l10n/fluera_localizations.dart';
import '../../drawing/models/brush_preset.dart';
import '../../drawing/models/pro_drawing_point.dart';
import '../../core/models/shape_type.dart';
import '../../core/models/pdf_annotation_model.dart';
import '../../core/models/pdf_document_model.dart';
import '../../../testing/brush_testing.dart';
import '../../storage/fluera_cloud_adapter.dart';
import '../../core/nodes/pdf_document_node.dart';
import '../../tools/pdf/pdf_annotation_controller.dart';
import '../../tools/pdf/pdf_search_controller.dart';
import '../../history/command_history.dart';
import 'pdf_contextual_toolbar.dart';

import 'toolbar_status.dart';
import 'toolbar_tool_buttons.dart';
import 'toolbar_brush_strip.dart';
import 'toolbar_eraser.dart';
import 'toolbar_shapes.dart';
import 'toolbar_color_palette.dart';
import 'toolbar_sliders.dart';
import 'toolbar_settings_dropdown.dart';
import 'handedness_settings_sheet.dart'; // 🖐️ Handedness & palm rejection
import 'toolbar_recording.dart';
import 'toolbar_layout.dart';
import 'toolbar_tab_bar.dart'; // ToolbarTab enum is still used
import 'toolbar_tokens.dart';
import 'menus/latex_code_dialog.dart';

part '_toolbar_top_row.dart';
part '_toolbar_tools_area.dart';
part '_toolbar_tools_widgets.dart';
part '_toolbar_state.dart';
part '_toolbar_callbacks.dart';

// =============================================================================
// 🎨 ProfessionalCanvasToolbar
//
// Enterprise-grade toolbar for the Fluera canvas.
//
// ## Architecture
// The widget accepts two grouped data objects instead of 90+ individual params:
//   - [ToolbarState]     — immutable snapshot of all boolean/value state
//   - [ToolbarCallbacks] — all action callbacks grouped by domain
//
// Internally, getter-forwarding preserves `widget.xxx` access patterns so
// that all part files (_toolbar_tools_area.dart, _toolbar_top_row.dart, etc.)
// remain unchanged.
//
// ## Visual
// - Contextual toolbar: tab auto-derives from canvas state (no visible tab bar)
// - Collapsible to a thin strip via the chevron toggle
// - Two layout modes: left-aligned pin (forceLeftAlign) and centered Material
// =============================================================================

class ProfessionalCanvasToolbar extends ConsumerStatefulWidget {
  // ── Data objects (new enterprise API) ─────────────────────────────────────
  final ToolbarState state;
  final ToolbarCallbacks callbacks;

  // ── Layout config (not part of state/callbacks) ───────────────────────────
  final bool forceLeftAlign;
  final bool isFloating;

  /// ☁️ Cloud sync state notifier — drives toolbar sync indicator.
  final ValueListenable<FlueraSyncState>? cloudSyncState;

  const ProfessionalCanvasToolbar({
    super.key,
    required this.state,
    required this.callbacks,
    this.forceLeftAlign = false,
    this.isFloating = false,
    this.cloudSyncState,
  });

  // ==========================================================================
  // 🔁 GETTER FORWARDERS
  //
  // These delegate widget.xxx → widget.state.xxx / widget.callbacks.xxx so
  // that all internal part files work without modification.
  // ==========================================================================

  // ── ToolbarState forwarders ───────────────────────────────────────────────
  ProPenType get selectedPenType => state.selectedPenType;
  Color get selectedColor => state.selectedColor;
  double get selectedWidth => state.selectedWidth;
  double get selectedOpacity => state.selectedOpacity;
  ShapeType get selectedShapeType => state.selectedShapeType;
  int get strokeCount => state.strokeCount;
  bool get canUndo => state.canUndo;
  bool get canRedo => state.canRedo;
  ValueListenable<int>? get undoRedoListenable => state.undoRedoListenable;
  bool Function()? get computeCanUndo => state.computeCanUndo;
  bool Function()? get computeCanRedo => state.computeCanRedo;
  bool get isEraserActive => state.isEraserActive;
  double get eraserRadius => state.eraserRadius;
  bool get eraseWholeStroke => state.eraseWholeStroke;
  bool get isLassoActive => state.isLassoActive;
  bool get isDigitalTextActive => state.isDigitalTextActive;
  bool get isImagePickerActive => state.isImagePickerActive;
  bool get isRecordingActive => state.isRecordingActive;
  bool get isPanModeActive => state.isPanModeActive;
  bool get isStylusModeActive => state.isStylusModeActive;
  bool get isRulerActive => state.isRulerActive;
  bool get isMinimapVisible => state.isMinimapVisible;
  bool get isSectionActive => state.isSectionActive;
  bool get isDualPageMode => state.isDualPageMode;
  bool get isPenToolActive => state.isPenToolActive;
  bool get isLatexActive => state.isLatexActive;
  bool get isImageEditingMode => state.isImageEditingMode;
  List<BrushPreset> get brushPresets => state.brushPresets;
  String? get selectedPresetId => state.selectedPresetId;
  bool get isTabularActive => state.isTabularActive;
  bool get hasTabularSelection => state.hasTabularSelection;
  bool get hasRangeSelection => state.hasRangeSelection;
  bool get hasFrozenRow => state.hasFrozenRow;
  String? get selectedCellRef => state.selectedCellRef;
  String? get selectedCellValue => state.selectedCellValue;
  CellFormat? get selectedCellFormat => state.selectedCellFormat;
  Duration get recordingDuration => state.recordingDuration;
  double get recordingAmplitude => state.recordingAmplitude;
  ValueListenable<Duration>? get recordingDurationNotifier =>
      state.recordingDurationNotifier;
  ValueListenable<double>? get recordingAmplitudeNotifier =>
      state.recordingAmplitudeNotifier;
  bool get hideRecordingControlWhenActive =>
      state.hideRecordingControlWhenActive;
  bool get isSearchActive => state.isSearchActive;
  bool get isCanvasRotated => state.isCanvasRotated;
  bool get isRotationLocked => state.isRotationLocked;
  bool? get isSyncEnabled => state.isSyncEnabled;
  String? get activeBranchName => state.activeBranchName;
  String? get noteTitle => state.noteTitle;
  bool get shapeRecognitionEnabled => state.shapeRecognitionEnabled;
  int get shapeRecognitionSensitivityIndex =>
      state.shapeRecognitionSensitivityIndex;
  bool get ghostSuggestionEnabled => state.ghostSuggestionEnabled;
  bool get isPdfActive => state.isPdfActive;
  PdfDocumentNode? get pdfDocument => state.pdfDocument;
  List<PdfDocumentNode> get pdfDocuments => state.pdfDocuments;
  PdfAnnotationController? get pdfAnnotationController =>
      state.pdfAnnotationController;
  PdfSearchController? get pdfSearchController => state.pdfSearchController;
  CommandHistory? get pdfCommandHistory => state.pdfCommandHistory;
  int get pdfSelectedPageIndex => state.pdfSelectedPageIndex;
  bool get showPdfPageNumbers => state.showPdfPageNumbers;
  bool get isInspectActive => state.isInspectActive;
  bool get isRedlineActive => state.isRedlineActive;
  bool get isSmartSnapActive => state.isSmartSnapActive;

  // ── ToolbarCallbacks forwarders ───────────────────────────────────────────
  ValueChanged<ProPenType> get onPenTypeChanged => callbacks.onPenTypeChanged;
  ValueChanged<Color> get onColorChanged => callbacks.onColorChanged;
  ValueChanged<double> get onWidthChanged => callbacks.onWidthChanged;
  ValueChanged<double> get onOpacityChanged => callbacks.onOpacityChanged;
  ValueChanged<ShapeType> get onShapeTypeChanged =>
      callbacks.onShapeTypeChanged;
  VoidCallback get onUndo => callbacks.onUndo;
  VoidCallback get onRedo => callbacks.onRedo;
  VoidCallback get onClear => callbacks.onClear;
  VoidCallback get onSettings => callbacks.onSettings;
  VoidCallback get onLayersPressed => callbacks.onLayersPressed;
  VoidCallback get onEraserToggle => callbacks.onEraserToggle;
  VoidCallback get onLassoToggle => callbacks.onLassoToggle;
  VoidCallback get onDigitalTextToggle => callbacks.onDigitalTextToggle;
  VoidCallback get onPanModeToggle => callbacks.onPanModeToggle;
  VoidCallback get onStylusModeToggle => callbacks.onStylusModeToggle;
  VoidCallback get onImagePickerPressed => callbacks.onImagePickerPressed;
  VoidCallback get onRecordingPressed => callbacks.onRecordingPressed;
  VoidCallback get onViewRecordingsPressed => callbacks.onViewRecordingsPressed;
  ValueChanged<double>? get onEraserRadiusChanged =>
      callbacks.onEraserRadiusChanged;
  ValueChanged<bool>? get onEraseWholeStrokeChanged =>
      callbacks.onEraseWholeStrokeChanged;
  void Function(Rect anchorRect)? get onBrushSettingsPressed =>
      callbacks.onBrushSettingsPressed;
  VoidCallback? get onExportPressed => callbacks.onExportPressed;
  VoidCallback? get onDualPagePressed => callbacks.onDualPagePressed;
  VoidCallback? get onRulerToggle => callbacks.onRulerToggle;
  VoidCallback? get onMinimapToggle => callbacks.onMinimapToggle;
  VoidCallback? get onSectionToggle => callbacks.onSectionToggle;
  VoidCallback? get onPenToolToggle => callbacks.onPenToolToggle;
  VoidCallback? get onLatexToggle => callbacks.onLatexToggle;
  VoidCallback? get onTabularToggle => callbacks.onTabularToggle;
  VoidCallback? get onImageEditorPressed => callbacks.onImageEditorPressed;
  VoidCallback? get onExitImageEditMode => callbacks.onExitImageEditMode;
  ValueChanged<String>? get onNoteTitleChanged => callbacks.onNoteTitleChanged;
  ValueChanged<BrushPreset>? get onPresetSelected => callbacks.onPresetSelected;
  VoidCallback? get onCanvasLayoutPressed => callbacks.onCanvasLayoutPressed;
  VoidCallback? get onHSplitLayoutPressed => callbacks.onHSplitLayoutPressed;
  VoidCallback? get onVSplitLayoutPressed => callbacks.onVSplitLayoutPressed;
  VoidCallback? get onCanvasOverlayPressed => callbacks.onCanvasOverlayPressed;
  VoidCallback? get onAdvancedSplitPressed => callbacks.onAdvancedSplitPressed;
  VoidCallback? get onSyncToggle => callbacks.onSyncToggle;
  VoidCallback? get onTimeTravelPressed => callbacks.onTimeTravelPressed;
  VoidCallback? get onRecallModePressed => callbacks.onRecallModePressed;
  VoidCallback? get onGhostMapPressed => callbacks.onGhostMapPressed;
  VoidCallback? get onFogOfWarPressed => callbacks.onFogOfWarPressed;
  VoidCallback? get onSocraticPressed => callbacks.onSocraticPressed;
  VoidCallback? get onCrossZoneBridgesPressed =>
      callbacks.onCrossZoneBridgesPressed;
  VoidCallback? get onBranchExplorerPressed =>
      callbacks.onBranchExplorerPressed;
  VoidCallback? get onPaperTypePressed => callbacks.onPaperTypePressed;
  VoidCallback? get onReadingLevelPressed => callbacks.onReadingLevelPressed;
  VoidCallback? get onResetRotation => callbacks.onResetRotation;
  VoidCallback? get onToggleRotationLock => callbacks.onToggleRotationLock;
  VoidCallback? get onSearchPressed => callbacks.onSearchPressed;
  VoidCallback? get onShapeRecognitionToggle =>
      callbacks.onShapeRecognitionToggle;
  VoidCallback? get onShapeRecognitionSensitivityCycle =>
      callbacks.onShapeRecognitionSensitivityCycle;
  VoidCallback? get onGhostSuggestionToggle =>
      callbacks.onGhostSuggestionToggle;
  VoidCallback? get onPdfImportPressed => callbacks.onPdfImportPressed;
  VoidCallback? get onPdfCreateBlankPressed =>
      callbacks.onPdfCreateBlankPressed;
  void Function(int)? get onPdfInsertBlankPage =>
      callbacks.onPdfInsertBlankPage;
  void Function(int)? get onPdfDuplicatePage => callbacks.onPdfDuplicatePage;
  void Function(int)? get onPdfDeletePage => callbacks.onPdfDeletePage;
  void Function(int oldIndex, int newIndex)? get onPdfReorderPage =>
      callbacks.onPdfReorderPage;
  VoidCallback? get onPdfNightModeToggle => callbacks.onPdfNightModeToggle;
  void Function(int)? get onPdfBookmarkToggle => callbacks.onPdfBookmarkToggle;
  void Function(int)? get onPdfZoomToFit => callbacks.onPdfZoomToFit;
  VoidCallback? get onPdfWatermarkToggle => callbacks.onPdfWatermarkToggle;
  void Function(int pageIndex, PdfStampType stamp)? get onPdfAddStamp =>
      callbacks.onPdfAddStamp;
  void Function(int pageIndex)? get onPdfChangeBackground =>
      callbacks.onPdfChangeBackground;
  VoidCallback? get onPdfPrint => callbacks.onPdfPrint;
  VoidCallback? get onPdfPresentation => callbacks.onPdfPresentation;
  void Function(PdfLayoutMode)? get onPdfLayoutModeChanged =>
      callbacks.onPdfLayoutModeChanged;
  void Function(String, int)? get onPdfGoToPage => callbacks.onPdfGoToPage;
  void Function(String documentId)? get onPdfDocumentChanged =>
      callbacks.onPdfDocumentChanged;
  VoidCallback? get onPdfLayoutChanged => callbacks.onPdfLayoutChanged;
  VoidCallback? get onPdfExport => callbacks.onPdfExport;
  VoidCallback? get onPdfDeleteDocument => callbacks.onPdfDeleteDocument;
  VoidCallback? get onTogglePdfPageNumbers => callbacks.onTogglePdfPageNumbers;
  ValueChanged<int>? get onPdfPageIndexChanged =>
      callbacks.onPdfPageIndexChanged;
  void Function(int columns, int rows)? get onTabularCreate =>
      callbacks.onTabularCreate;
  void Function(String value)? get onCellValueSubmit =>
      callbacks.onCellValueSubmit;
  void Function(String value)? get onCellTabSubmit => callbacks.onCellTabSubmit;
  VoidCallback? get onTabularDelete => callbacks.onTabularDelete;
  VoidCallback? get onInsertRow => callbacks.onInsertRow;
  VoidCallback? get onDeleteRow => callbacks.onDeleteRow;
  VoidCallback? get onInsertColumn => callbacks.onInsertColumn;
  VoidCallback? get onDeleteColumn => callbacks.onDeleteColumn;
  VoidCallback? get onMergeCells => callbacks.onMergeCells;
  VoidCallback? get onUnmergeCells => callbacks.onUnmergeCells;
  VoidCallback? get onCopySelection => callbacks.onCopySelection;
  VoidCallback? get onCutSelection => callbacks.onCutSelection;
  VoidCallback? get onPasteSelection => callbacks.onPasteSelection;
  void Function(bool ascending)? get onSortColumn => callbacks.onSortColumn;
  VoidCallback? get onAutoFill => callbacks.onAutoFill;
  VoidCallback? get onGenerateLatex => callbacks.onGenerateLatex;
  VoidCallback? get onCopySelectionAsLatex => callbacks.onCopySelectionAsLatex;
  VoidCallback? get onGenerateChart => callbacks.onGenerateChart;
  VoidCallback? get onImportLatex => callbacks.onImportLatex;
  VoidCallback? get onExportTex => callbacks.onExportTex;
  VoidCallback? get onToggleBold => callbacks.onToggleBold;
  VoidCallback? get onToggleItalic => callbacks.onToggleItalic;
  ValueChanged<String>? get onBorderPreset => callbacks.onBorderPreset;
  void Function(CellAlignment)? get onSetAlignment => callbacks.onSetAlignment;
  void Function(Color)? get onSetTextColor => callbacks.onSetTextColor;
  void Function(Color)? get onSetBackgroundColor =>
      callbacks.onSetBackgroundColor;
  VoidCallback? get onClearFormatting => callbacks.onClearFormatting;
  VoidCallback? get onClearCells => callbacks.onClearCells;
  void Function(String csvText)? get onImportCsv => callbacks.onImportCsv;
  VoidCallback? get onExportCsv => callbacks.onExportCsv;
  VoidCallback? get onToggleFreezeRow => callbacks.onToggleFreezeRow;
  VoidCallback? get onPrototypePlay => callbacks.onPrototypePlay;
  VoidCallback? get onFlowLinkAdd => callbacks.onFlowLinkAdd;
  VoidCallback? get onAnimationTimeline => callbacks.onAnimationTimeline;
  VoidCallback? get onSmartAnimate => callbacks.onSmartAnimate;
  VoidCallback? get onInspectToggle => callbacks.onInspectToggle;
  VoidCallback? get onCodeGen => callbacks.onCodeGen;
  VoidCallback? get onRedlineToggle => callbacks.onRedlineToggle;
  ValueChanged<String>? get onBreakpointSelect => callbacks.onBreakpointSelect;
  VoidCallback? get onSmartSnapToggle => callbacks.onSmartSnapToggle;
  VoidCallback? get onDesignLint => callbacks.onDesignLint;
  VoidCallback? get onStyleSystem => callbacks.onStyleSystem;
  VoidCallback? get onAccessibilityTree => callbacks.onAccessibilityTree;
  VoidCallback? get onImageAdjust => callbacks.onImageAdjust;
  VoidCallback? get onImageFillMode => callbacks.onImageFillMode;
  ValueChanged<String>? get onTokenExport => callbacks.onTokenExport;
  ValueChanged<String>? get onInsertText => callbacks.onInsertText;

  @override
  ConsumerState<ProfessionalCanvasToolbar> createState() =>
      _ProfessionalCanvasToolbarState();
}

class _ProfessionalCanvasToolbarState
    extends ConsumerState<ProfessionalCanvasToolbar> {
  bool _isToolsExpanded = true;
  bool _isShapesExpanded = false;

  /// Manual tab override — set when the user taps a tab chip.
  /// Cleared automatically when the auto-context changes.
  ToolbarTab? _manualTabOverride;
  ToolbarTab? _lastAutoTab;

  /// Which tabs are available in the current context.
  List<ToolbarTab> get _availableTabs {
    final tabs = <ToolbarTab>[ToolbarTab.main];

    // PDF tab: only when a PDF document is loaded
    if (widget.isPdfActive || widget.pdfDocuments.isNotEmpty) {
      tabs.add(ToolbarTab.pdf);
    }

    // Scientific: always available (LaTeX, pen tool, shapes)
    tabs.add(ToolbarTab.scientific);

    // Excel: always available (can create new tables)
    tabs.add(ToolbarTab.excel);

    // Media: always available (digital text, images, recording)
    tabs.add(ToolbarTab.media);

    return tabs;
  }

  /// Auto-derives the active toolbar tab from canvas state,
  /// but respects manual override when set.
  ToolbarTab get _computedTab {
    final autoTab = _autoContextTab;

    // If auto-context changed, clear manual override
    if (_lastAutoTab != null && _lastAutoTab != autoTab) {
      _manualTabOverride = null;
    }
    _lastAutoTab = autoTab;

    // Manual override takes priority if it's in the available tabs
    if (_manualTabOverride != null &&
        _availableTabs.contains(_manualTabOverride)) {
      return _manualTabOverride!;
    }

    return autoTab;
  }

  /// Pure auto-context tab derivation (no manual override).
  ToolbarTab get _autoContextTab {
    // 1. PDF: a document is loaded
    if (widget.isPdfActive || widget.pdfDocuments.isNotEmpty) {
      return ToolbarTab.pdf;
    }
    // 2. Math / LaTeX: editor is open or vector pen is active
    if (widget.isLatexActive || widget.isPenToolActive) {
      return ToolbarTab.scientific;
    }
    // 3. Spreadsheet: table is active or has selection
    if (widget.isTabularActive || widget.hasTabularSelection) {
      return ToolbarTab.excel;
    }
    // 4. Media: digital text, image picker, or active recording
    if (widget.isDigitalTextActive ||
        widget.isImagePickerActive ||
        widget.isRecordingActive) {
      return ToolbarTab.media;
    }
    // 5. Default: main drawing tools
    return ToolbarTab.main;
  }

  // Customizable colors (6 slots)
  List<Color> _customColors = [
    Colors.black,
    const Color(0xFF2196F3), // Blu
    const Color(0xFFE53935), // Rosso
    const Color(0xFF43A047), // Verde
    const Color(0xFF8E24AA), // Viola
    const Color(0xFFFF6F00), // Arancione
  ];

  // Color history (last 12 used)
  List<Color> _colorHistory = [];

  @override
  void initState() {
    super.initState();
    _loadCustomColors();
    _loadColorHistory();
  }

  // Load colori salvati
  Future<void> _loadCustomColors() async {
    final prefs = await KeyValueStore.getInstance();
    final List<String>? savedColors = prefs.getStringList('custom_colors');
    if (savedColors != null && savedColors.length == 6) {
      setState(() {
        _customColors =
            savedColors
                .map((colorString) => Color(int.parse(colorString)))
                .toList();
      });
    }
  }

  // Save colori
  Future<void> _saveCustomColors() async {
    final prefs = await KeyValueStore.getInstance();
    final colorStrings =
        _customColors.map((c) => c.toARGB32().toString()).toList();
    await prefs.setStringList('custom_colors', colorStrings);
  }

  // Load color history
  Future<void> _loadColorHistory() async {
    final prefs = await KeyValueStore.getInstance();
    final saved = prefs.getStringList('color_history');
    if (saved != null && saved.isNotEmpty) {
      setState(() {
        _colorHistory = saved.map((s) => Color(int.parse(s))).toList();
      });
    }
  }

  // Save color to history
  Future<void> _addToColorHistory(Color color) async {
    setState(() {
      _colorHistory.removeWhere((c) => c.toARGB32() == color.toARGB32());
      _colorHistory.insert(0, color);
      if (_colorHistory.length > 12)
        _colorHistory = _colorHistory.sublist(0, 12);
    });
    final prefs = await KeyValueStore.getInstance();
    await prefs.setStringList(
      'color_history',
      _colorHistory.map((c) => c.toARGB32().toString()).toList(),
    );
  }

  // Show pro color picker per slot specifico
  void _showColorPicker(int index) async {
    final color = await showProColorPicker(
      context: context,
      currentColor: _customColors[index],
      colorHistory: _colorHistory,
      onEyedropperRequested: () async {
        final picked = await showEyedropperOverlay(context: context);
        if (picked != null && mounted) {
          setState(() => _customColors[index] = picked);
          _saveCustomColors();
          _addToColorHistory(picked);
          widget.onColorChanged(picked);
        }
      },
    );
    if (color != null && mounted) {
      setState(() => _customColors[index] = color);
      _saveCustomColors();
      _addToColorHistory(color);
      widget.onColorChanged(color);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Cache computed tab — avoids recomputing in _buildActiveToolbar
    // (_computedTab getter traverses 5+ boolean conditions)

    // 🎨 Glassmorphism surface colors
    final Color bgBase =
        widget.isImageEditingMode
            ? (isDark ? const Color(0xFF0F2210) : const Color(0xFFE8F5E8))
            : (isDark ? const Color(0xFF111111) : Colors.white);
    final double bgOpacity =
        isDark
            ? ToolbarTokens.surfaceOpacityDark
            : ToolbarTokens.surfaceOpacityLight;
    final backgroundColor = bgBase.withValues(alpha: bgOpacity);

    // 🏝️ Floating Configuration
    final borderRadius =
        widget.isFloating ? BorderRadius.circular(24) : BorderRadius.zero;
    final clipBehavior = widget.isFloating ? Clip.antiAlias : Clip.antiAlias;

    // 🌫️ Glassmorphism shell
    Widget _glassShell({required Widget child}) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: ToolbarTokens.surfaceBlur,
            sigmaY: ToolbarTokens.surfaceBlur,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: borderRadius,
              border: Border(
                top: BorderSide(
                  color: (isDark ? Colors.white : Colors.black).withValues(
                    alpha:
                        isDark
                            ? ToolbarTokens.surfaceBorderOpacityDark
                            : ToolbarTokens.surfaceBorderOpacityLight,
                  ),
                  width: 0.5,
                ),
                bottom: BorderSide(
                  color: (isDark ? Colors.white : Colors.black).withValues(
                    alpha: isDark ? 0.06 : 0.04,
                  ),
                  width: 0.5,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: ToolbarTokens.surfaceShadowOpacity,
                  ),
                  blurRadius: ToolbarTokens.surfaceShadowBlur,
                  spreadRadius: ToolbarTokens.surfaceShadowSpread,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 4,
                  spreadRadius: 0,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: child,
          ),
        ),
      );
    }

    // 📐 Collapsed/expanded content with spring animation
    Widget _toolsArea() {
      // Active tool icon for the mini indicator
      IconData activeIcon = Icons.edit_rounded;
      if (widget.isEraserActive)
        activeIcon = Icons.auto_fix_high_rounded;
      else if (widget.isLassoActive)
        activeIcon = Icons.gesture_rounded;
      else if (widget.isPanModeActive)
        activeIcon = Icons.pan_tool_outlined;
      else if (widget.isStylusModeActive)
        activeIcon = Icons.draw_rounded;
      else if (widget.isRulerActive)
        activeIcon = Icons.straighten_rounded;
      else if (widget.isLatexActive)
        activeIcon = Icons.functions_rounded;

      return AnimatedCrossFade(
        duration: ToolbarTokens.animNormal,
        sizeCurve: ToolbarTokens.curveCollapse,
        firstCurve: Curves.easeOut,
        secondCurve: Curves.easeIn,
        crossFadeState:
            _isToolsExpanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
        firstChild: _buildActiveToolbar(context, isDark),
        secondChild: _CollapsedToolIndicator(
          toolIcon: activeIcon,
          penColor: widget.selectedColor,
          strokeWidth: widget.selectedWidth,
          isDark: isDark,
          onTap: () {
            HapticFeedback.lightImpact();
            setState(() => _isToolsExpanded = true);
          },
        ),
      );
    }

    return widget.forceLeftAlign
        ? Align(
          alignment: Alignment.centerLeft,
          child: _glassShell(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTopRow(context, isDark),
                _toolsArea(),
              ],
            ),
          ),
        )
        : _glassShell(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTopRow(context, isDark),
              _toolsArea(),
            ],
          ),
        );
  }

  // ============================================================================
  // 🔝 TOP ROW → see _toolbar_top_row.dart
  // 🛠️ TOOLS AREA → see _toolbar_tools_area.dart
  // ============================================================================
}
