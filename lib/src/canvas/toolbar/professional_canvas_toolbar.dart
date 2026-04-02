library professional_canvas_toolbar;

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
import 'toolbar_tab_bar.dart';

part '_toolbar_top_row.dart';
part '_toolbar_tools_area.dart';
part '_toolbar_tools_widgets.dart';

/// 🎨 Toolbar professionale per uso quotidiano
/// Design minimalista e funzionale con:
/// - Compact status bar with essential info
/// - Tools organized logically (type → color → width)
/// - Quick actions always accessible
/// - Scroll orizzontale smooth
/// - Collapsible to maximize canvas
class ProfessionalCanvasToolbar extends ConsumerStatefulWidget {
  final ProPenType selectedPenType;
  final Color selectedColor;
  final double selectedWidth;
  final double selectedOpacity;
  final ShapeType selectedShapeType;
  final int strokeCount;
  final bool canUndo;
  final bool canRedo;
  final bool isEraserActive;
  final bool isLassoActive;
  final bool isDigitalTextActive;
  final bool isImagePickerActive; // 🖼️ Pulsante immagini
  final bool isRecordingActive; // � Pulsante registrazione
  final bool isPanModeActive; // 🖐️ Modalità Pan
  final bool isStylusModeActive; // 🖊️ Modalità Stylus
  final bool isRulerActive; // 📏 Ruler/guide overlay
  final bool isMinimapVisible; // 🗺️ Minimap overlay
  final bool isSectionActive; // 📐 Section tool
  final bool isPenToolActive; // ✏️ Vector Pen Tool
  final bool isLatexActive; // 🧮 LaTeX editor
  final bool isTabularActive; // 📊 Tabular spreadsheet
  final bool hasTabularSelection; // 📊 A table is selected
  final String? selectedCellRef; // 📊 e.g. "A1" — null if no cell selected
  final String? selectedCellValue; // 📊 current cell display value
  final void Function(int columns, int rows)?
  onTabularCreate; // 📊 Create table
  final void Function(String value)?
  onCellValueSubmit; // 📊 Save cell + navigate down (Enter)
  final void Function(String value)?
  onCellTabSubmit; // 📊 Save cell + navigate right (Tab)
  final VoidCallback? onTabularDelete; // 📊 Delete selected table
  final VoidCallback? onInsertRow; // 📊 Insert row
  final VoidCallback? onDeleteRow; // 📊 Delete row
  final VoidCallback? onInsertColumn; // 📊 Insert column
  final VoidCallback? onDeleteColumn; // 📊 Delete column
  final VoidCallback? onMergeCells; // 📊 Merge selected cells
  final VoidCallback? onUnmergeCells; // 📊 Unmerge selected cell
  final VoidCallback? onCopySelection; // 📊 Copy cells
  final VoidCallback? onCutSelection; // 📊 Cut cells
  final VoidCallback? onPasteSelection; // 📊 Paste cells
  final void Function(bool ascending)? onSortColumn; // 📊 Sort
  final VoidCallback? onAutoFill; // 📊 Auto-fill down
  final VoidCallback? onGenerateLatex; // 🧮 Excel-to-LaTeX Generation
  final VoidCallback? onCopySelectionAsLatex; // 📋 Copy selection as LaTeX code
  final VoidCallback? onGenerateChart; // 📊 TikZ Chart from Selection
  final VoidCallback? onImportLatex; // 📥 Import LaTeX → Spreadsheet
  final VoidCallback? onExportTex; // 📄 Export .tex File
  // 🎨 Cell formatting
  final CellFormat? selectedCellFormat; // Current cell format state
  final bool hasRangeSelection; // Multi-cell range selected
  final VoidCallback? onToggleBold;
  final VoidCallback? onToggleItalic;
  final ValueChanged<String>? onBorderPreset;
  final void Function(CellAlignment)? onSetAlignment;
  final void Function(Color)? onSetTextColor;
  final void Function(Color)? onSetBackgroundColor;
  final VoidCallback? onClearFormatting;
  final VoidCallback? onClearCells;
  final void Function(String csvText)? onImportCsv;
  final VoidCallback? onExportCsv;
  final bool hasFrozenRow; // Whether header row is frozen
  final VoidCallback? onToggleFreezeRow;
  final Duration recordingDuration;
  final double recordingAmplitude; // 🎵 Live amplitude for waveform bars
  /// 🚀 P99 FIX: Optional ValueListenables for recording state.
  /// When provided, the recording button uses these to update independently
  /// of the parent widget tree, eliminating full canvas rebuilds.
  final ValueListenable<Duration>? recordingDurationNotifier;
  final ValueListenable<double>? recordingAmplitudeNotifier;
  final String? noteTitle;
  // 🎨 Preset-based brush selection
  final List<BrushPreset> brushPresets;
  final String? selectedPresetId;
  final ValueChanged<BrushPreset>? onPresetSelected;
  final bool isImageEditingMode;

  final ValueChanged<ProPenType> onPenTypeChanged;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<double> onWidthChanged;
  final ValueChanged<double> onOpacityChanged;
  final ValueChanged<ShapeType> onShapeTypeChanged;
  final ValueChanged<String>? onNoteTitleChanged; // 🆕 Callback rinomina nota
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onClear;
  final VoidCallback onSettings;
  final void Function(Rect anchorRect)?
  onBrushSettingsPressed; // 🎛️ Callback impostazioni pennello
  final VoidCallback? onExportPressed; // 📤 Callback export canvas
  final VoidCallback onLayersPressed;
  final VoidCallback? onDualPagePressed;
  final bool isDualPageMode;
  final VoidCallback onEraserToggle;
  final double eraserRadius;
  final ValueChanged<double>? onEraserRadiusChanged;
  final bool eraseWholeStroke;
  final ValueChanged<bool>? onEraseWholeStrokeChanged;
  final VoidCallback onLassoToggle;
  final VoidCallback onDigitalTextToggle;
  final VoidCallback onPanModeToggle; // 🖐️ Callback Pan Mode
  final VoidCallback onStylusModeToggle; // 🖊️ Callback Stylus Mode
  final VoidCallback? onRulerToggle; // 📏 Callback Ruler toggle
  final VoidCallback? onMinimapToggle; // 🗺️ Callback Minimap toggle
  final VoidCallback? onSectionToggle; // 📐 Callback Section toggle
  final VoidCallback? onPenToolToggle; // ✏️ Callback Pen Tool toggle
  final VoidCallback? onLatexToggle; // 🧮 Callback LaTeX toggle
  final VoidCallback? onTabularToggle; // 📊 Callback Tabular toggle (compat)
  // (onTabularCreate is the preferred callback for the Excel tab)
  final VoidCallback onImagePickerPressed; // 🖼️ Callback immagini
  final VoidCallback? onImageEditorPressed;
  final VoidCallback? onExitImageEditMode; // ✅ Esci da edit mode
  final VoidCallback onRecordingPressed; // � Callback registrazione
  final VoidCallback
  onViewRecordingsPressed; // 🎧 Callback visualizza registrazioni
  final bool forceLeftAlign; // 🎯 Forza allineamento a sinistra
  // 📐 Layout callbacks
  final VoidCallback? onCanvasLayoutPressed; // Canvas solo
  final VoidCallback? onHSplitLayoutPressed; // H-Split
  final VoidCallback? onVSplitLayoutPressed; // V-Split
  final VoidCallback? onCanvasOverlayPressed; // Canvas Overlay
  // 🔄 Sync callback
  final VoidCallback? onSyncToggle; // Toggle sync
  final bool? isSyncEnabled; // Stato sync
  // 🔧 Advanced Split callback
  final VoidCallback? onAdvancedSplitPressed; // Advanced Split Configuretion
  final VoidCallback? onTimeTravelPressed; // ⏱️ Time Travel
  final VoidCallback? onRecallModePressed; // 🧠 Recall Mode (Step 2)
  final VoidCallback? onBranchExplorerPressed; // 🌿 Branch Explorer
  final String? activeBranchName; // 🌿 Currently active branch
  final VoidCallback? onPaperTypePressed; // 📄 Paper type picker
  final VoidCallback? onReadingLevelPressed; // 📊 Reading level analysis
  final VoidCallback? onResetRotation; // 🌀 Reset canvas rotation to 0°
  final VoidCallback? onToggleRotationLock; // 🌀 Toggle rotation lock
  final bool isCanvasRotated; // 🌀 Whether canvas is currently rotated
  final bool isRotationLocked; // 🌀 Whether rotation is locked
  final bool shapeRecognitionEnabled; // 🔷 Shape recognition mode
  final int shapeRecognitionSensitivityIndex; // 🔷 0=low, 1=medium, 2=high
  final bool ghostSuggestionEnabled; // 👻 Ghost suggestion mode
  final VoidCallback? onShapeRecognitionToggle; // 🔷 Shape recognition toggle
  final VoidCallback?
  onShapeRecognitionSensitivityCycle; // 🔷 Long-press to cycle sensitivity
  final VoidCallback? onGhostSuggestionToggle; // 👻 Double-tap to toggle ghost
  final VoidCallback? onSearchPressed; // 🔍 Handwriting search
  final bool isSearchActive; // 🔍 Search overlay visible
  final VoidCallback? onPdfImportPressed; // 📄 PDF import
  final VoidCallback? onPdfCreateBlankPressed; // 📄 PDF create blank
  // 📄 PDF active state — contextual tools appear when a PDF is loaded
  final bool isPdfActive;
  final PdfDocumentNode? pdfDocument;
  final List<PdfDocumentNode> pdfDocuments; // 📄 All PDFs for multi-doc search
  final PdfAnnotationController? pdfAnnotationController;
  final PdfSearchController? pdfSearchController;
  final CommandHistory? pdfCommandHistory;
  final void Function(int selectedPageIndex)? onPdfInsertBlankPage;
  final void Function(int)? onPdfDuplicatePage;
  final void Function(int)? onPdfDeletePage;
  final void Function(int oldIndex, int newIndex)? onPdfReorderPage;
  final VoidCallback? onPdfNightModeToggle;
  final void Function(int)? onPdfBookmarkToggle;
  final void Function(int)? onPdfZoomToFit;
  final VoidCallback? onPdfWatermarkToggle;
  final void Function(int pageIndex, PdfStampType stamp)? onPdfAddStamp;
  final void Function(int pageIndex)? onPdfChangeBackground;
  final VoidCallback? onPdfPrint;
  final VoidCallback? onPdfPresentation;
  // TODO(future): onPdfSignature — digital signing requires QTSP, X.509, PAdES.
  final void Function(PdfLayoutMode)? onPdfLayoutModeChanged;
  final void Function(String, int)? onPdfGoToPage; // 🔍 Scroll to PDF page
  final void Function(String documentId)?
  onPdfDocumentChanged; // 📄 Switch active PDF
  final VoidCallback?
  onPdfLayoutChanged; // 📄 Notify canvas of PDF layout mutations
  final VoidCallback? onPdfExport;
  final VoidCallback? onPdfDeleteDocument; // 🗑️ Delete entire PDF
  final int pdfSelectedPageIndex;
  final bool showPdfPageNumbers;
  final VoidCallback? onTogglePdfPageNumbers;
  final ValueChanged<int>? onPdfPageIndexChanged;

  // ─────────────────────────────────────────────────────────────────────────
  // 🎨 DESIGN TAB — Callbacks and state for Design toolbar features
  // ─────────────────────────────────────────────────────────────────────────

  // Prototype
  final VoidCallback? onPrototypePlay;
  final VoidCallback? onFlowLinkAdd;

  // Animation
  final VoidCallback? onAnimationTimeline;
  final VoidCallback? onSmartAnimate;

  // Inspect / Dev Handoff
  final VoidCallback? onInspectToggle;
  final bool isInspectActive;
  final VoidCallback? onCodeGen;
  final VoidCallback? onRedlineToggle;
  final bool isRedlineActive;

  // Responsive
  final ValueChanged<String>? onBreakpointSelect;

  // Quality
  final VoidCallback? onSmartSnapToggle;
  final bool isSmartSnapActive;
  final VoidCallback? onDesignLint;
  final VoidCallback? onStyleSystem;
  final VoidCallback? onAccessibilityTree;

  // Images
  final VoidCallback? onImageAdjust;
  final VoidCallback? onImageFillMode;

  // Token Export
  final ValueChanged<String>? onTokenExport;

  /// ☁️ Cloud sync state notifier — drives the toolbar sync indicator.
  final ValueListenable<FlueraSyncState>? cloudSyncState;

  const ProfessionalCanvasToolbar({
    super.key,
    required this.selectedPenType,
    required this.selectedColor,
    required this.selectedWidth,
    required this.selectedOpacity,
    required this.selectedShapeType,
    required this.strokeCount,
    required this.canUndo,
    required this.canRedo,
    required this.isEraserActive,
    required this.isLassoActive,
    required this.isDigitalTextActive,
    required this.isImagePickerActive,
    required this.isRecordingActive,
    required this.isPanModeActive,
    required this.isStylusModeActive,
    this.isRulerActive = false,
    this.isMinimapVisible = true,
    this.isSectionActive = false,
    this.isPenToolActive = false,
    this.isLatexActive = false,
    this.isTabularActive = false,
    this.hasTabularSelection = false,
    this.selectedCellRef,
    this.selectedCellValue,
    this.onTabularCreate,
    this.onCellValueSubmit,
    this.onCellTabSubmit,
    this.onTabularDelete,
    this.onInsertRow,
    this.onDeleteRow,
    this.onInsertColumn,
    this.onDeleteColumn,
    this.onMergeCells,
    this.onUnmergeCells,
    this.onCopySelection,
    this.onCutSelection,
    this.onPasteSelection,
    this.onSortColumn,
    this.onAutoFill,
    this.onGenerateLatex,
    this.onCopySelectionAsLatex,
    this.onGenerateChart,
    this.onImportLatex,
    this.onExportTex,
    this.selectedCellFormat,
    this.hasRangeSelection = false,
    this.onToggleBold,
    this.onToggleItalic,
    this.onBorderPreset,
    this.onSetAlignment,
    this.onSetTextColor,
    this.onSetBackgroundColor,
    this.onClearFormatting,
    this.onClearCells,
    this.onImportCsv,
    this.onExportCsv,
    this.hasFrozenRow = false,
    this.onToggleFreezeRow,
    required this.recordingDuration,
    this.recordingAmplitude = 0.0,
    this.recordingDurationNotifier,
    this.recordingAmplitudeNotifier,
    this.isImageEditingMode = false,
    this.noteTitle,
    this.brushPresets = const [],
    this.selectedPresetId,
    this.onPresetSelected,
    required this.onPenTypeChanged,
    required this.onColorChanged,
    required this.onWidthChanged,
    required this.onOpacityChanged,
    required this.onShapeTypeChanged,
    this.onNoteTitleChanged,
    required this.onUndo,
    required this.onRedo,
    required this.onClear,
    required this.onSettings,
    this.onBrushSettingsPressed, // 🎛️ Brush settings
    this.onExportPressed, // 📤 Export canvas
    required this.onLayersPressed,
    this.onDualPagePressed,
    this.isDualPageMode = false,
    required this.onEraserToggle,
    this.eraserRadius = 20.0,
    this.onEraserRadiusChanged,
    this.eraseWholeStroke = false,
    this.onEraseWholeStrokeChanged,
    required this.onLassoToggle,
    required this.onDigitalTextToggle,
    required this.onPanModeToggle,
    required this.onStylusModeToggle,
    this.onRulerToggle,
    this.onMinimapToggle,
    this.onSectionToggle,
    this.onPenToolToggle,
    this.onLatexToggle,
    this.onTabularToggle,
    required this.onImagePickerPressed,
    this.onImageEditorPressed,
    this.onExitImageEditMode, // ✅ Esci da edit mode
    required this.onRecordingPressed,
    required this.onViewRecordingsPressed,

    this.forceLeftAlign = false,
    this.onCanvasLayoutPressed,
    this.onHSplitLayoutPressed,
    this.onVSplitLayoutPressed,
    this.onCanvasOverlayPressed,
    // 🔄 Sync callback
    this.onSyncToggle,
    this.isSyncEnabled,
    // 🔧 Advanced Split callback
    this.onAdvancedSplitPressed,
    this.onTimeTravelPressed, // ⏱️ Time Travel
    this.onRecallModePressed, // 🧠 Recall Mode (Step 2)
    this.onBranchExplorerPressed, // 🌿 Branch Explorer
    this.activeBranchName, // 🌿 Active branch name
    this.onPaperTypePressed, // 📄 Paper type picker
    this.onReadingLevelPressed, // 📊 Reading level analysis
    this.onResetRotation, // 🌀 Reset rotation
    this.onToggleRotationLock, // 🌀 Toggle rotation lock
    this.isCanvasRotated = false, // 🌀 Rotation state
    this.isRotationLocked = false, // 🌀 Rotation lock state
    this.shapeRecognitionEnabled = false, // 🔷 Shape recognition
    this.shapeRecognitionSensitivityIndex = 1, // 🔷 Medium
    this.ghostSuggestionEnabled = false, // 👻 Ghost mode
    this.onShapeRecognitionToggle, // 🔷 Shape recognition toggle
    this.onShapeRecognitionSensitivityCycle, // 🔷 Sensitivity cycle
    this.onGhostSuggestionToggle, // 👻 Ghost toggle
    this.onSearchPressed, // 🔍 Handwriting search
    this.isSearchActive = false, // 🔍 Search overlay state
    this.onPdfImportPressed, // 📄 PDF import
    this.onPdfCreateBlankPressed, // 📄 PDF create blank
    this.isPdfActive = false,
    this.pdfDocument,
    this.pdfDocuments = const [],
    this.pdfAnnotationController,
    this.pdfSearchController,
    this.pdfCommandHistory,
    this.onPdfInsertBlankPage,
    this.onPdfDuplicatePage,
    this.onPdfDeletePage,
    this.onPdfReorderPage,
    this.onPdfNightModeToggle,
    this.onPdfBookmarkToggle,
    this.onPdfZoomToFit,
    this.onPdfWatermarkToggle,
    this.onPdfAddStamp,
    this.onPdfChangeBackground,
    this.onPdfPrint,
    this.onPdfPresentation,
    this.onPdfLayoutModeChanged,
    this.onPdfGoToPage, // 🔍 Scroll to page
    this.onPdfDocumentChanged, // 📄 Switch active PDF
    this.onPdfLayoutChanged, // 📄 Layout mutation callback
    this.onPdfExport,
    this.onPdfDeleteDocument, // 🗑️ Delete entire PDF
    this.pdfSelectedPageIndex = 0,
    this.showPdfPageNumbers = true,
    this.onTogglePdfPageNumbers,
    this.onPdfPageIndexChanged,
    // 🎨 Design tab
    this.onPrototypePlay,
    this.onFlowLinkAdd,
    this.onAnimationTimeline,
    this.onSmartAnimate,
    this.onInspectToggle,
    this.isInspectActive = false,
    this.onCodeGen,
    this.onRedlineToggle,
    this.isRedlineActive = false,
    this.onBreakpointSelect,
    this.onSmartSnapToggle,
    this.isSmartSnapActive = false,
    this.onDesignLint,
    this.onStyleSystem,
    this.onAccessibilityTree,
    this.onImageAdjust,
    this.onImageFillMode,
    this.onTokenExport,
    this.cloudSyncState,
    this.hideRecordingControlWhenActive = false,
    this.isFloating = false, // 🏝️ Floating Island mode
  });

  final bool hideRecordingControlWhenActive;
  final bool isFloating;

  @override
  ConsumerState<ProfessionalCanvasToolbar> createState() =>
      _ProfessionalCanvasToolbarState();
}

class _ProfessionalCanvasToolbarState
    extends ConsumerState<ProfessionalCanvasToolbar> {
  bool _isToolsExpanded = true;
  bool _isShapesExpanded = false;
  ToolbarTab _activeToolbarTab = ToolbarTab.main;

  /// Tabs currently available based on canvas state.
  List<ToolbarTab> get _availableTabs {
    final tabs = [ToolbarTab.main];
    // Always show PDF tab — even without documents, the import button is there
    tabs.add(ToolbarTab.pdf);
    // V1: Excel hidden — re-enable post-launch
    tabs.add(ToolbarTab.scientific);
    // tabs.add(ToolbarTab.excel);
    tabs.add(ToolbarTab.media);
    // Design tab: SDK-only, not exposed in Looponia (see dev.md)
    return tabs;
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
        _colorHistory = saved
            .map((s) => Color(int.parse(s)))
            .toList();
      });
    }
  }

  // Save color to history
  Future<void> _addToColorHistory(Color color) async {
    setState(() {
      _colorHistory.removeWhere((c) => c.toARGB32() == color.toARGB32());
      _colorHistory.insert(0, color);
      if (_colorHistory.length > 12) _colorHistory = _colorHistory.sublist(0, 12);
    });
    final prefs = await KeyValueStore.getInstance();
    await prefs.setStringList('color_history',
        _colorHistory.map((c) => c.toARGB32().toString()).toList());
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
  void didUpdateWidget(covariant ProfessionalCanvasToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auto-switch to PDF tab when first PDF is loaded
    if (widget.pdfDocuments.isNotEmpty && oldWidget.pdfDocuments.isEmpty) {
      setState(() => _activeToolbarTab = ToolbarTab.pdf);
    }
    // Auto-switch away from PDF tab when last PDF is removed
    if (widget.pdfDocuments.isEmpty && _activeToolbarTab == ToolbarTab.pdf) {
      setState(() => _activeToolbarTab = ToolbarTab.main);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Different background color in editing mode
    final backgroundColor =
        widget.isImageEditingMode
            ? (isDark ? const Color(0xFF1A2F1A) : const Color(0xFFE8F5E8))
            : (isDark ? const Color(0xFF1E1E1E) : Colors.white);

    // 🏝️ Floating Configuretion
    final borderRadius =
        widget.isFloating ? BorderRadius.circular(24) : BorderRadius.zero;
    final elevation = widget.isFloating ? 4.0 : 8.0;
    final clipBehavior = widget.isFloating ? Clip.antiAlias : Clip.none;

    return widget.forceLeftAlign
        ? Align(
          alignment: Alignment.centerLeft,
          child: Material(
            color: backgroundColor,
            elevation: elevation,
            borderRadius: borderRadius,
            clipBehavior: clipBehavior,
            shadowColor: Colors.black.withValues(alpha: 0.3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Status Bar + Quick Actions
                _buildTopRow(context, isDark),

                // 🗂️ Tab Bar — switch between toolbar contexts
                if (_isToolsExpanded)
                  ToolbarTabBar(
                    activeTab: _activeToolbarTab,
                    availableTabs: _availableTabs,
                    onTabChanged:
                        (tab) => setState(() => _activeToolbarTab = tab),
                    isDark: isDark,
                  ),

                // Tools Area (collapsible) — dispatched by active tab
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child:
                      _isToolsExpanded
                          ? _buildActiveToolbar(context, isDark)
                          : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        )
        : Material(
          color: backgroundColor,
          elevation: elevation,
          borderRadius: borderRadius,
          clipBehavior: clipBehavior,
          shadowColor: Colors.black.withValues(alpha: 0.3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Row: Status Bar + Quick Actions
              _buildTopRow(context, isDark),

              // 🗂️ Tab Bar — switch between toolbar contexts
              if (_isToolsExpanded)
                ToolbarTabBar(
                  activeTab: _activeToolbarTab,
                  availableTabs: _availableTabs,
                  onTabChanged:
                      (tab) => setState(() => _activeToolbarTab = tab),
                  isDark: isDark,
                ),

              // Tools Area (collapsible) — dispatched by active tab
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child:
                    _isToolsExpanded
                        ? _buildActiveToolbar(context, isDark)
                        : const SizedBox.shrink(),
              ),
            ],
          ),
        );
  }

  // ============================================================================
  // 🔝 TOP ROW → see _toolbar_top_row.dart
  // 🛠️ TOOLS AREA → see _toolbar_tools_area.dart
  // ============================================================================
}
