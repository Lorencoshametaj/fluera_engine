// ignore_for_file: lines_longer_than_80_chars
part of 'professional_canvas_toolbar.dart';

// =============================================================================
// 📊 TOOLBAR STATE — Immutable snapshot of canvas tool state.
//
// Used by ProfessionalCanvasToolbar to decouple its API from the 90+ individual
// constructor params. The widget now takes a single ToolbarState object and
// exposes getter-forwarders so that all internal code in
// _toolbar_tools_area.dart remains unchanged (widget.xxx still works).
// =============================================================================

/// Immutable snapshot of all canvas tool state consumed by the toolbar.
///
/// See also: [ToolbarCallbacks] for the callback counterpart.
class ToolbarState {
  // ── Drawing ───────────────────────────────────────────────────────────────
  final ProPenType selectedPenType;
  final Color selectedColor;
  final double selectedWidth;
  final double selectedOpacity;
  final ShapeType selectedShapeType;
  final int strokeCount;
  final bool canUndo;
  final bool canRedo;

  // ── Scoped rebuild — undo/redo (optional) ─────────────────────────────────
  // When provided, _UndoRedoGroup subscribes to these directly, so only the
  // undo/redo buttons rebuild on history change — not the entire toolbar.
  final ValueListenable<int>? undoRedoListenable;
  final bool Function()? computeCanUndo;
  final bool Function()? computeCanRedo;
  final bool isEraserActive;
  final double eraserRadius;
  final bool eraseWholeStroke;
  final bool isLassoActive;
  final bool isDigitalTextActive;
  final bool isImagePickerActive;
  final bool isRecordingActive;
  final bool isPanModeActive;
  final bool isStylusModeActive;
  final bool isRulerActive;
  final bool isMinimapVisible;
  final bool isSectionActive;
  final bool isDualPageMode;
  final bool isPenToolActive;
  final bool isLatexActive;
  final bool isImageEditingMode;

  // ── Brush presets ─────────────────────────────────────────────────────────
  final List<BrushPreset> brushPresets;
  final String? selectedPresetId;

  // ── Excel / Tabular ───────────────────────────────────────────────────────
  final bool isTabularActive;
  final bool hasTabularSelection;
  final bool hasRangeSelection;
  final bool hasFrozenRow;
  final String? selectedCellRef;
  final String? selectedCellValue;
  final CellFormat? selectedCellFormat;

  // ── Recording ─────────────────────────────────────────────────────────────
  final Duration recordingDuration;
  final double recordingAmplitude;
  final ValueListenable<Duration>? recordingDurationNotifier;
  final ValueListenable<double>? recordingAmplitudeNotifier;
  final bool hideRecordingControlWhenActive;

  // ── Canvas / Search ───────────────────────────────────────────────────────
  final bool isSearchActive;
  final bool isCanvasRotated;
  final bool isRotationLocked;
  final bool? isSyncEnabled;
  final String? activeBranchName;
  final String? noteTitle;

  // ── Shape recognition ─────────────────────────────────────────────────────
  final bool shapeRecognitionEnabled;
  final int shapeRecognitionSensitivityIndex;
  final bool ghostSuggestionEnabled;

  // ── PDF ───────────────────────────────────────────────────────────────────
  final bool isPdfActive;
  final PdfDocumentNode? pdfDocument;
  final List<PdfDocumentNode> pdfDocuments;
  final PdfAnnotationController? pdfAnnotationController;
  final PdfSearchController? pdfSearchController;
  final CommandHistory? pdfCommandHistory;
  final int pdfSelectedPageIndex;
  final bool showPdfPageNumbers;

  // ── Design ────────────────────────────────────────────────────────────────
  final bool isInspectActive;
  final bool isRedlineActive;
  final bool isSmartSnapActive;

  // ── Ghost Map ─────────────────────────────────────────────────────────────────
  final bool isGhostMapActive;
  final int ghostMapGapCount;

  // ── Step Gate System (A15) ─────────────────────────────────────────────────
  /// Gate availability per cognitive tool step.
  /// 0 = open, 1 = soft, 2 = hard, 3 = automatic.
  /// Null means gate system is unavailable (treated as open).
  final int? recallGateType;
  final int? socraticGateType;
  final int? ghostMapGateType;
  final int? fogOfWarGateType;
  final int? crossZoneBridgeGateType;

  /// Number of cross-zone bridges (for badge count).
  final int crossZoneBridgeCount;

  /// Whether bridge suggestions are loading.
  final bool isCrossZoneBridgeLoading;

  /// Index of the suggested next step in `LearningStep.values`.
  /// Used to show a highlight on the suggested toolbar chip.
  final int? suggestedStepIndex;

  ToolbarState({
    // Drawing
    required this.selectedPenType,
    required this.selectedColor,
    required this.selectedWidth,
    required this.selectedOpacity,
    required this.selectedShapeType,
    required this.strokeCount,
    required this.canUndo,
    required this.canRedo,
    // Scoped undo/redo (optional — enables independent rebuild)
    this.undoRedoListenable,
    this.computeCanUndo,
    this.computeCanRedo,
    required this.isEraserActive,
    this.eraserRadius = 20.0,
    this.eraseWholeStroke = false,
    required this.isLassoActive,
    required this.isDigitalTextActive,
    this.isImagePickerActive = false,
    required this.isRecordingActive,
    required this.isPanModeActive,
    required this.isStylusModeActive,
    this.isRulerActive = false,
    this.isMinimapVisible = true,
    this.isSectionActive = false,
    this.isDualPageMode = false,
    this.isPenToolActive = false,
    this.isLatexActive = false,
    this.isImageEditingMode = false,
    // Brush presets
    this.brushPresets = const [],
    this.selectedPresetId,
    // Excel
    this.isTabularActive = false,
    this.hasTabularSelection = false,
    this.hasRangeSelection = false,
    this.hasFrozenRow = false,
    this.selectedCellRef,
    this.selectedCellValue,
    this.selectedCellFormat,
    // Recording
    required this.recordingDuration,
    this.recordingAmplitude = 0.0,
    this.recordingDurationNotifier,
    this.recordingAmplitudeNotifier,
    this.hideRecordingControlWhenActive = false,
    // Canvas / Search
    this.isSearchActive = false,
    this.isCanvasRotated = false,
    this.isRotationLocked = false,
    this.isSyncEnabled,
    this.activeBranchName,
    this.noteTitle,
    // Shape recognition
    this.shapeRecognitionEnabled = false,
    this.shapeRecognitionSensitivityIndex = 1,
    this.ghostSuggestionEnabled = false,
    // PDF
    this.isPdfActive = false,
    this.pdfDocument,
    this.pdfDocuments = const [],
    this.pdfAnnotationController,
    this.pdfSearchController,
    this.pdfCommandHistory,
    this.pdfSelectedPageIndex = 0,
    this.showPdfPageNumbers = true,
    // Design
    this.isInspectActive = false,
    this.isRedlineActive = false,
    this.isSmartSnapActive = false,
    // Ghost Map
    this.isGhostMapActive = false,
    this.ghostMapGapCount = 0,
    // Step Gate System (A15)
    this.recallGateType,
    this.socraticGateType,
    this.ghostMapGateType,
    this.fogOfWarGateType,
    this.crossZoneBridgeGateType,
    this.crossZoneBridgeCount = 0,
    this.isCrossZoneBridgeLoading = false,
    this.suggestedStepIndex,
  });

  /// Creates a copy with selected fields overridden.
  ToolbarState copyWith({
    ProPenType? selectedPenType,
    Color? selectedColor,
    double? selectedWidth,
    double? selectedOpacity,
    ShapeType? selectedShapeType,
    int? strokeCount,
    bool? canUndo,
    bool? canRedo,
    bool? isEraserActive,
    double? eraserRadius,
    bool? eraseWholeStroke,
    bool? isLassoActive,
    bool? isDigitalTextActive,
    bool? isRecordingActive,
    bool? isPanModeActive,
    bool? isStylusModeActive,
    bool? isRulerActive,
    bool? isLatexActive,
    bool? isPdfActive,
    List<PdfDocumentNode>? pdfDocuments,
  }) {
    return ToolbarState(
      selectedPenType: selectedPenType ?? this.selectedPenType,
      selectedColor: selectedColor ?? this.selectedColor,
      selectedWidth: selectedWidth ?? this.selectedWidth,
      selectedOpacity: selectedOpacity ?? this.selectedOpacity,
      selectedShapeType: selectedShapeType ?? this.selectedShapeType,
      strokeCount: strokeCount ?? this.strokeCount,
      canUndo: canUndo ?? this.canUndo,
      canRedo: canRedo ?? this.canRedo,
      isEraserActive: isEraserActive ?? this.isEraserActive,
      eraserRadius: eraserRadius ?? this.eraserRadius,
      eraseWholeStroke: eraseWholeStroke ?? this.eraseWholeStroke,
      isLassoActive: isLassoActive ?? this.isLassoActive,
      isDigitalTextActive: isDigitalTextActive ?? this.isDigitalTextActive,
      isRecordingActive: isRecordingActive ?? this.isRecordingActive,
      isPanModeActive: isPanModeActive ?? this.isPanModeActive,
      isStylusModeActive: isStylusModeActive ?? this.isStylusModeActive,
      isRulerActive: isRulerActive ?? this.isRulerActive,
      isLatexActive: isLatexActive ?? this.isLatexActive,
      isPdfActive: isPdfActive ?? this.isPdfActive,
      pdfDocuments: pdfDocuments ?? this.pdfDocuments,
      // Carry over all other fields
      isImagePickerActive: isImagePickerActive,
      isMinimapVisible: isMinimapVisible,
      isSectionActive: isSectionActive,
      isDualPageMode: isDualPageMode,
      isPenToolActive: isPenToolActive,
      isImageEditingMode: isImageEditingMode,
      brushPresets: brushPresets,
      selectedPresetId: selectedPresetId,
      isTabularActive: isTabularActive,
      hasTabularSelection: hasTabularSelection,
      hasRangeSelection: hasRangeSelection,
      hasFrozenRow: hasFrozenRow,
      selectedCellRef: selectedCellRef,
      selectedCellValue: selectedCellValue,
      selectedCellFormat: selectedCellFormat,
      recordingDuration: recordingDuration,
      recordingAmplitude: recordingAmplitude,
      recordingDurationNotifier: recordingDurationNotifier,
      recordingAmplitudeNotifier: recordingAmplitudeNotifier,
      hideRecordingControlWhenActive: hideRecordingControlWhenActive,
      isSearchActive: isSearchActive,
      isCanvasRotated: isCanvasRotated,
      isRotationLocked: isRotationLocked,
      isSyncEnabled: isSyncEnabled,
      activeBranchName: activeBranchName,
      noteTitle: noteTitle,
      shapeRecognitionEnabled: shapeRecognitionEnabled,
      shapeRecognitionSensitivityIndex: shapeRecognitionSensitivityIndex,
      ghostSuggestionEnabled: ghostSuggestionEnabled,
      pdfDocument: pdfDocument,
      pdfAnnotationController: pdfAnnotationController,
      pdfSearchController: pdfSearchController,
      pdfCommandHistory: pdfCommandHistory,
      pdfSelectedPageIndex: pdfSelectedPageIndex,
      showPdfPageNumbers: showPdfPageNumbers,
      isInspectActive: isInspectActive,
      isRedlineActive: isRedlineActive,
      isSmartSnapActive: isSmartSnapActive,
      isGhostMapActive: isGhostMapActive,
      ghostMapGapCount: ghostMapGapCount,
      // Step Gate
      recallGateType: recallGateType,
      socraticGateType: socraticGateType,
      ghostMapGateType: ghostMapGateType,
      fogOfWarGateType: fogOfWarGateType,
      crossZoneBridgeGateType: crossZoneBridgeGateType,
      crossZoneBridgeCount: crossZoneBridgeCount,
      isCrossZoneBridgeLoading: isCrossZoneBridgeLoading,
      suggestedStepIndex: suggestedStepIndex,
    );
  }
}
