import 'package:flutter/widgets.dart';

/// 🌍 SDK Localization system for the Fluera Engine.
///
/// Provides default English strings for all SDK UI elements.
/// The app can override by extending this class:
///
/// ```dart
/// class FlueraLocalizations extends FlueraLocalizations {
///   @override String get proCanvas_pen => myL10n.pen;
///   // ... override only what you need
/// }
/// FlueraLocalizations.override = FlueraLocalizations();
/// ```
class FlueraLocalizations {
  static FlueraLocalizations? _override;
  static set override(FlueraLocalizations? value) => _override = value;
  static FlueraLocalizations of(BuildContext context) =>
      _override ?? const FlueraLocalizations._();
  static const FlueraLocalizations instance = FlueraLocalizations._();
  const FlueraLocalizations._();

  // ============================================================================
  // COMMON
  // ============================================================================
  String get cancel => 'Cancel';
  String get close => 'Close';
  String get save => 'Save';
  String get ok => 'OK';
  String get delete => 'Delete';
  String get confirm => 'Confirm';
  String get apply => 'Apply';

  // ============================================================================
  // TOOLBAR
  // ============================================================================
  String get toolbarAIFilters => 'AI Filters';

  // ============================================================================
  // PRO CANVAS
  // ============================================================================
  String get proCanvas_pen => 'Pen';
  String get proCanvas_undo => 'Undo';
  String get proCanvas_redo => 'Redo';
  String get proCanvas_layers => 'Layers';
  String get proCanvas_opacity => 'Opacity';
  String get proCanvas_thickness => 'Thickness';
  String get proCanvas_color => 'Color';
  String get proCanvas_chooseColor => 'Choose Color';
  String get proCanvas_done => 'Done';
  String get proCanvas_writing => 'Writing';
  String get proCanvas_brushSettings => 'Brush Settings';
  String get proCanvas_brushTestingLab => 'Brush Testing Lab';
  String get proCanvas_paperMode => 'Paper Mode';
  String get proCanvas_pageTemplate => 'Page Template';
  String get proCanvas_exportCanvas => 'Export Canvas';

  String get proCanvas_professionalFilters => 'Professional Filters';
  String get proCanvas_ocrConvertWriting => 'OCR — Convert Writing';
  String get proCanvas_ocrTextRecognition => 'Text Recognition';
  String get proCanvas_selectLanguagesForRecognition =>
      'Select languages for recognition';
  String get proCanvas_downloaded => 'Downloaded';
  String get proCanvas_downloadLabel => 'Download';
  String proCanvas_downloadingModel(String code) =>
      'Downloading model ($code)...';
  String proCanvas_modelDownloadedSuccess(String language) =>
      '$language model downloaded successfully';
  String get proCanvas_languageModelsWillBeDownloaded =>
      'Language models will be downloaded for offline use';
  String get proCanvas_renameNote => 'Rename Note';
  String get proCanvas_noteName => 'Note Name';
  String get proCanvas_enterName => 'Enter name...';

  String get proCanvas_geometricShapes => 'Geometric Shapes';
  String get proCanvas_singleView => 'Single View';
  String get proCanvas_dualView => 'Dual View';
  String get proCanvas_hide => 'Hide';
  String get proCanvas_show => 'Show';
  String get proCanvas_advancedEditor => 'Advanced Editor';
  String get proCanvas_professionalEditor => 'Professional Editor';
  String get proCanvas_advancedImageEdit => 'Advanced Image Editing';
  String get proCanvas_flipH => 'Flip Horizontal';
  String get proCanvas_flipV => 'Flip Vertical';
  String get proCanvas_cropInstructions => 'Drag corners to crop';
  String get proCanvas_filtersUpdatedRestartApp =>
      'Filters updated. Restart app to apply.';
  String get proCanvas_flipHorizontal => 'Flip Horizontal';
  String get proCanvas_flipVertical => 'Flip Vertical';
  String get proCanvas_convertToText => 'Convert to Text';
  String get proCanvas_delete => 'Delete';
  String get proCanvas_close => 'Close';

  // Shapes
  String get proCanvas_shapeLine => 'Line';
  String get proCanvas_shapeRectangle => 'Rectangle';
  String get proCanvas_shapeCircle => 'Circle';
  String get proCanvas_shapeTriangle => 'Triangle';
  String get proCanvas_shapeStar => 'Star';
  String get proCanvas_shapeArrow => 'Arrow';
  String get proCanvas_shapeDiamond => 'Diamond';
  String get proCanvas_shapeHexagon => 'Hexagon';
  String get proCanvas_shapePentagon => 'Pentagon';
  String get proCanvas_shapeHeart => 'Heart';
  String get proCanvas_shapeFreehand => 'Freehand';

  // Pages
  String get proCanvas_addPage => 'Add Page';
  String get proCanvas_removePage => 'Remove Page';
  String get proCanvas_nextPage => 'Next Page';
  String get proCanvas_previousPage => 'Previous Page';
  String get proCanvas_firstPage => 'First Page';
  String get proCanvas_lastPage => 'Last Page';

  // Layers
  String get proCanvas_new => 'New';
  String get proCanvas_rename => 'Rename';
  String get proCanvas_renameLayer => 'Rename Layer';
  String get proCanvas_nameLabel => 'Name';
  String get proCanvas_duplicate => 'Duplicate';
  String get proCanvas_clear => 'Clear';

  // Image editor
  String get proCanvas_cropImage => 'Crop Image';
  String get proCanvas_editCrop => 'Edit Crop';
  String get proCanvas_removeCrop => 'Remove Crop';
  String get proCanvas_rotation => 'Rotation';
  String get proCanvas_transformations => 'Transformations';
  String get proCanvas_brightness => 'Brightness';
  String get proCanvas_contrast => 'Contrast';
  String get proCanvas_saturation => 'Saturation';
  String get proCanvas_colorAdjustments => 'Color Adjustments';
  String proCanvas_errorLoadingImage([String? error]) =>
      error != null ? 'Error loading image: $error' : 'Error loading image';

  // Image editor — filter presets
  String get proCanvas_filters => 'Filters';
  String get proCanvas_filterNone => 'None';
  String get proCanvas_filterBW => 'B&W';
  String get proCanvas_filterSepia => 'Sepia';
  String get proCanvas_filterVintage => 'Vintage';
  String get proCanvas_filterCool => 'Cool';
  String get proCanvas_filterWarm => 'Warm';
  String get proCanvas_filterDramatic => 'Dramatic';

  // Image editor — crop aspect ratios
  String get proCanvas_aspectFree => 'Free';
  String get proCanvas_aspectSquare => '1:1';
  String get proCanvas_aspect4x3 => '4:3';
  String get proCanvas_aspect16x9 => '16:9';
  String get proCanvas_aspect3x2 => '3:2';
  String get proCanvas_aspectRatio => 'Aspect Ratio';

  // Image editor — before/after
  String get proCanvas_beforeAfter => 'Before / After';

  // Image editor — advanced adjustments
  String get proCanvas_vignette => 'Vignette';
  String get proCanvas_hueShift => 'Hue';
  String get proCanvas_temperature => 'Temperature';
  String get proCanvas_imageInfo => 'Image Info';
  String get proCanvas_undoEdit => 'Undo';
  String get proCanvas_redoEdit => 'Redo';
  String get proCanvas_discardChanges => 'Discard changes?';
  String get proCanvas_discardChangesMessage =>
      'You have unsaved edits. Are you sure you want to discard them?';
  String get proCanvas_discardConfirm => 'Discard';

  // ============================================================================
  // BRUSH SETTINGS
  // ============================================================================
  String get brush_styloPressure => 'Pressure Sensitivity';
  String get brush_styloDynamics => 'Dynamics';
  String get brush_styloRealism => 'Realism';
  String get brush_styloTapering => 'Tapering';
  String get brush_minWidth => 'Min Width';
  String get brush_minWidthLightPressure => 'Width at light pressure';
  String get brush_maxWidth => 'Max Width';
  String get brush_maxWidthFullPressure => 'Width at full pressure';
  String get brush_velocitySensitivity => 'Velocity Sensitivity';
  String get brush_velocitySensitivityDesc =>
      'How much stroke velocity affects width';
  String get brush_velocityInfluence => 'Velocity Influence';
  String get brush_velocityInfluenceDesc =>
      'Strength of velocity effect on stroke';
  String get brush_curvatureInfluence => 'Curvature Influence';
  String get brush_curvatureInfluenceDesc => 'How path curvature affects width';
  String get brush_taperEntry => 'Taper Entry';
  String get brush_taperExit => 'Taper Exit';
  String get brush_pathSmoothSpline => 'Path Smoothing (Spline)';
  String get brush_pathSmoothDesc => 'Catmull-Rom spline interpolation level';
  String get brush_naturalJitter => 'Natural Jitter';
  String get brush_jitterDesc => 'Simulates natural hand tremor';
  String get brush_inkAccumulation => 'Ink Accumulation';
  String get brush_inkAccumulationDesc =>
      'Ink builds up where pen stays longer';
  String get brush_baseOpacity => 'Base Opacity';
  String get brush_maxOpacity => 'Max Opacity';
  String get brush_widthMultiplier => 'Width Multiplier';
  String get brush_widthMultiplierDesc => 'Global width scaling factor';
  String get brush_points => 'pts';

  // Ballpoint
  String get brush_ballpoint => 'Ballpoint';
  String get brush_ballpointInfo => 'Standard ballpoint pen settings';

  // Pencil
  String get brush_pencilTexture => 'Pencil Texture';
  String get brush_pencilPressure => 'Pencil Pressure';
  String get brush_pencilOpacity => 'Pencil Opacity';
  String get brush_graphiteBlur => 'Graphite Blur';
  String get brush_graphiteBlurDesc => 'Softness of pencil strokes';

  // Highlighter
  String get brush_highlighter => 'Highlighter';
  String get brush_highlighterOpacityDesc =>
      'Transparency of highlighter strokes';

  // ============================================================================
  // SPLIT PANEL
  // ============================================================================
  String get splitPanel_infiniteCanvas => 'Infinite Canvas';
  String get splitPanel_canvasDescription => 'Draw on an infinite canvas';

  String get splitPanel_textEditor => 'Text Editor';
  String get splitPanel_textEditorDescription => 'Write and edit text';
  String get splitPanel_whiteboard => 'Whiteboard';
  String get splitPanel_whiteboardDescription => 'Simple whiteboard';
  String get splitPanel_webBrowser => 'Web Browser';
  String get splitPanel_browserDescription => 'Browse the web';
  String get splitPanel_calculator => 'Calculator';
  String get splitPanel_calculatorDescription => 'Scientific calculator';
  String get splitPanel_existingNote => 'Existing Note';
  String get splitPanel_noteDescription => 'Open an existing note';
  String get splitPanel_emptyPanel => 'Empty Panel';
  String get splitPanel_emptyDescription => 'Start with an empty panel';

  // ============================================================================
  // TEXT INPUT / OCR
  // ============================================================================
  String get proCanvas_typeHere => 'Type here...';
  String get proCanvas_insertText => 'Insert Text';
  String get proCanvas_textEmpty => 'Text is empty';
  String get proCanvas_ocrTextCheck => 'Text Check';
  String get proCanvas_correct => 'Correct';
  String get proCanvas_capitalStart => 'Capitalize first letter';
  String get proCanvas_endPunctuation => 'End punctuation';
  String get proCanvas_correctSpacing => 'Correct spacing';
  String get proCanvas_keepHandwriting => 'Keep handwriting style';
  String get proCanvas_previewLabel => 'Preview';
  String get proCanvas_colorLabel => 'Color';

  // ============================================================================
  // CANVAS MODES / SPLIT
  // ============================================================================
  String get proCanvas_canvasMode => 'Canvas Mode';

  String get proCanvas_hSplit => 'Horizontal Split';
  String get proCanvas_vSplit => 'Vertical Split';
  String get proCanvas_splitPro => 'Split Pro';
  String get proCanvas_shapes => 'Shapes';

  // ============================================================================
  // PAPER MODE / CANVAS SETTINGS DIALOG
  // ============================================================================
  String get proCanvas_customizeYourSheet => 'Customize your sheet';
  String get proCanvas_backgroundColor => 'Background Color';
  String get proCanvas_applyButton => 'Apply';

  // Paper type names
  String get proCanvas_paperBlank => 'Blank';
  String get proCanvas_paperWideLines => 'Wide Lines';
  String get proCanvas_paperNarrowLines => 'Narrow Lines';
  String get proCanvas_paperCalligraphy => 'Calligraphy';
  String get proCanvas_paperDots => 'Dots';
  String get proCanvas_paperDotsDense => 'Dense Dots';
  String get proCanvas_paperDotGrid => 'Dot Grid';
  String get proCanvas_paperGraph => 'Graph';
  String get proCanvas_paperHex => 'Hexagonal';
  String get proCanvas_paperIsometric => 'Isometric';
  String get proCanvas_paperMusic => 'Music Staff';
  String get proCanvas_paperCornell => 'Cornell Notes';
  String get proCanvas_paperStoryboard => 'Storyboard';
  String get proCanvas_paperPlanner => 'Planner';

  // Category names
  String get proCanvas_categoryBasic => 'Basic';
  String get proCanvas_categoryGrid => 'Grid';
  String get proCanvas_categoryTechnical => 'Technical';

  // ============================================================================
  // PDF VIEWER
  // ============================================================================
  String get pdf_importDocument => 'Import PDF';
  String get pdf_importingDocument => 'Importing PDF...';
  String get pdf_importFailed => 'Failed to import PDF';
  String get pdf_importSuccess => 'PDF imported successfully';
  String pdf_pageCount(int count) => '$count pages';
  String pdf_pageLabel(int index) => 'Page ${index + 1}';
  String get pdf_lockPage => 'Lock to Grid';
  String get pdf_unlockPage => 'Unlock from Grid';
  String get pdf_lockAll => 'Lock All Pages';
  String get pdf_unlockAll => 'Unlock All Pages';
  String get pdf_resetLayout => 'Reset Layout';
  String get pdf_gridColumns => 'Grid Columns';
  String get pdf_gridSpacing => 'Grid Spacing';
  String get pdf_copyText => 'Copy Text';
  String get pdf_selectText => 'Select Text';
  String get pdf_noTextFound => 'No text found on this page';
  String get pdf_textCopied => 'Text copied to clipboard';
  String get pdf_removePdf => 'Remove PDF';
  String get pdf_autoFitGrid => 'Auto-fit Grid';
}
