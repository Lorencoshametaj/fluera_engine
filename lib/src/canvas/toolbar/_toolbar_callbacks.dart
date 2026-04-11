// ignore_for_file: lines_longer_than_80_chars
part of 'professional_canvas_toolbar.dart';

// =============================================================================
// 🎛️ TOOLBAR CALLBACKS — Bundle of all action callbacks for the toolbar.
//
// Groups all VoidCallback / ValueChanged callbacks into a single typed object,
// complementing ToolbarState. Together they reduce ProfessionalCanvasToolbar's
// constructor from 90+ named params to 3 grouped params.
// =============================================================================

/// All toolbar callbacks, grouped by domain.
class ToolbarCallbacks {
  // ── Drawing ───────────────────────────────────────────────────────────────
  final ValueChanged<ProPenType> onPenTypeChanged;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<double> onWidthChanged;
  final ValueChanged<double> onOpacityChanged;
  final ValueChanged<ShapeType> onShapeTypeChanged;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onClear;
  final VoidCallback onSettings;
  final VoidCallback onLayersPressed;
  final VoidCallback onEraserToggle;
  final VoidCallback onLassoToggle;
  final VoidCallback onDigitalTextToggle;
  final VoidCallback onPanModeToggle;
  final VoidCallback onStylusModeToggle;
  final VoidCallback onImagePickerPressed;
  final VoidCallback onRecordingPressed;
  final VoidCallback onViewRecordingsPressed;

  // ── Optional drawing ──────────────────────────────────────────────────────
  final ValueChanged<double>? onEraserRadiusChanged;
  final ValueChanged<bool>? onEraseWholeStrokeChanged;
  final void Function(Rect anchorRect)? onBrushSettingsPressed;
  final VoidCallback? onExportPressed;
  final VoidCallback? onDualPagePressed;
  final VoidCallback? onRulerToggle;
  final VoidCallback? onMinimapToggle;
  final VoidCallback? onSectionToggle;
  final VoidCallback? onPenToolToggle;
  final VoidCallback? onLatexToggle;
  final VoidCallback? onTabularToggle;
  final VoidCallback? onImageEditorPressed;
  final VoidCallback? onExitImageEditMode;
  final ValueChanged<String>? onNoteTitleChanged;
  final ValueChanged<BrushPreset>? onPresetSelected;

  // ── Canvas controls ───────────────────────────────────────────────────────
  final VoidCallback? onCanvasLayoutPressed;
  final VoidCallback? onHSplitLayoutPressed;
  final VoidCallback? onVSplitLayoutPressed;
  final VoidCallback? onCanvasOverlayPressed;
  final VoidCallback? onAdvancedSplitPressed;
  final VoidCallback? onSyncToggle;
  final VoidCallback? onTimeTravelPressed;
  final VoidCallback? onRecallModePressed;
  final VoidCallback? onGhostMapPressed;
  final VoidCallback? onFogOfWarPressed;
  final VoidCallback? onSocraticPressed;
  final VoidCallback? onCrossZoneBridgesPressed;
  final VoidCallback? onBranchExplorerPressed;
  final VoidCallback? onPaperTypePressed;
  final VoidCallback? onReadingLevelPressed;
  final VoidCallback? onResetRotation;
  final VoidCallback? onToggleRotationLock;
  final VoidCallback? onSearchPressed;

  // ── Shape recognition ─────────────────────────────────────────────────────
  final VoidCallback? onShapeRecognitionToggle;
  final VoidCallback? onShapeRecognitionSensitivityCycle;
  final VoidCallback? onGhostSuggestionToggle;

  // ── PDF ───────────────────────────────────────────────────────────────────
  final VoidCallback? onPdfImportPressed;
  final VoidCallback? onPdfCreateBlankPressed;
  final void Function(int)? onPdfInsertBlankPage;
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
  final void Function(PdfLayoutMode)? onPdfLayoutModeChanged;
  final void Function(String, int)? onPdfGoToPage;
  final void Function(String documentId)? onPdfDocumentChanged;
  final VoidCallback? onPdfLayoutChanged;
  final VoidCallback? onPdfExport;
  final VoidCallback? onPdfDeleteDocument;
  final VoidCallback? onTogglePdfPageNumbers;
  final ValueChanged<int>? onPdfPageIndexChanged;

  // ── Excel / Tabular ───────────────────────────────────────────────────────
  final void Function(int columns, int rows)? onTabularCreate;
  final void Function(String value)? onCellValueSubmit;
  final void Function(String value)? onCellTabSubmit;
  final VoidCallback? onTabularDelete;
  final VoidCallback? onInsertRow;
  final VoidCallback? onDeleteRow;
  final VoidCallback? onInsertColumn;
  final VoidCallback? onDeleteColumn;
  final VoidCallback? onMergeCells;
  final VoidCallback? onUnmergeCells;
  final VoidCallback? onCopySelection;
  final VoidCallback? onCutSelection;
  final VoidCallback? onPasteSelection;
  final void Function(bool ascending)? onSortColumn;
  final VoidCallback? onAutoFill;
  final VoidCallback? onGenerateLatex;
  final VoidCallback? onCopySelectionAsLatex;
  final VoidCallback? onGenerateChart;
  final VoidCallback? onImportLatex;
  final VoidCallback? onExportTex;
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
  final VoidCallback? onToggleFreezeRow;

  // ── Design ────────────────────────────────────────────────────────────────
  final VoidCallback? onPrototypePlay;
  final VoidCallback? onFlowLinkAdd;
  final VoidCallback? onAnimationTimeline;
  final VoidCallback? onSmartAnimate;
  final VoidCallback? onInspectToggle;
  final VoidCallback? onCodeGen;
  final VoidCallback? onRedlineToggle;
  final ValueChanged<String>? onBreakpointSelect;
  final VoidCallback? onSmartSnapToggle;
  final VoidCallback? onDesignLint;
  final VoidCallback? onStyleSystem;
  final VoidCallback? onAccessibilityTree;
  final VoidCallback? onImageAdjust;
  final VoidCallback? onImageFillMode;
  final ValueChanged<String>? onTokenExport;

  // ── Symbol insert ─────────────────────────────────────────────────────────
  /// Inserts a text/symbol into the active text field (inline text or LaTeX).
  final ValueChanged<String>? onInsertText;

  const ToolbarCallbacks({
    // Drawing — required
    required this.onPenTypeChanged,
    required this.onColorChanged,
    required this.onWidthChanged,
    required this.onOpacityChanged,
    required this.onShapeTypeChanged,
    required this.onUndo,
    required this.onRedo,
    required this.onClear,
    required this.onSettings,
    required this.onLayersPressed,
    required this.onEraserToggle,
    required this.onLassoToggle,
    required this.onDigitalTextToggle,
    required this.onPanModeToggle,
    required this.onStylusModeToggle,
    required this.onImagePickerPressed,
    required this.onRecordingPressed,
    required this.onViewRecordingsPressed,
    // Optional drawing
    this.onEraserRadiusChanged,
    this.onEraseWholeStrokeChanged,
    this.onBrushSettingsPressed,
    this.onExportPressed,
    this.onDualPagePressed,
    this.onRulerToggle,
    this.onMinimapToggle,
    this.onSectionToggle,
    this.onPenToolToggle,
    this.onLatexToggle,
    this.onTabularToggle,
    this.onImageEditorPressed,
    this.onExitImageEditMode,
    this.onNoteTitleChanged,
    this.onPresetSelected,
    // Canvas controls
    this.onCanvasLayoutPressed,
    this.onHSplitLayoutPressed,
    this.onVSplitLayoutPressed,
    this.onCanvasOverlayPressed,
    this.onAdvancedSplitPressed,
    this.onSyncToggle,
    this.onTimeTravelPressed,
    this.onRecallModePressed,
    this.onGhostMapPressed,
    this.onFogOfWarPressed,
    this.onSocraticPressed,
    this.onCrossZoneBridgesPressed,
    this.onBranchExplorerPressed,
    this.onPaperTypePressed,
    this.onReadingLevelPressed,
    this.onResetRotation,
    this.onToggleRotationLock,
    this.onSearchPressed,
    // Shape recognition
    this.onShapeRecognitionToggle,
    this.onShapeRecognitionSensitivityCycle,
    this.onGhostSuggestionToggle,
    // PDF
    this.onPdfImportPressed,
    this.onPdfCreateBlankPressed,
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
    this.onPdfGoToPage,
    this.onPdfDocumentChanged,
    this.onPdfLayoutChanged,
    this.onPdfExport,
    this.onPdfDeleteDocument,
    this.onTogglePdfPageNumbers,
    this.onPdfPageIndexChanged,
    // Excel
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
    this.onToggleFreezeRow,
    // Design
    this.onPrototypePlay,
    this.onFlowLinkAdd,
    this.onAnimationTimeline,
    this.onSmartAnimate,
    this.onInspectToggle,
    this.onCodeGen,
    this.onRedlineToggle,
    this.onBreakpointSelect,
    this.onSmartSnapToggle,
    this.onDesignLint,
    this.onStyleSystem,
    this.onAccessibilityTree,
    this.onImageAdjust,
    this.onImageFillMode,
    this.onTokenExport,
    // Symbol
    this.onInsertText,
  });
}
