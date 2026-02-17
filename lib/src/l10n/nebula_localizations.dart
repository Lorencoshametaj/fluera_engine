import 'package:flutter/widgets.dart';

/// 🌍 SDK Localization system for the Nebula Engine.
///
/// Provides default English strings for all SDK UI elements.
/// The app can override by extending this class:
///
/// ```dart
/// class NebulaLocalizations extends NebulaLocalizations {
///   @override String get proCanvas_pen => myL10n.pen;
///   // ... override only what you need
/// }
/// NebulaLocalizations.override = NebulaLocalizations();
/// ```
class NebulaLocalizations {
  static NebulaLocalizations? _override;
  static set override(NebulaLocalizations? value) => _override = value;
  static NebulaLocalizations of(BuildContext context) =>
      _override ?? const NebulaLocalizations._();
  static const NebulaLocalizations instance = NebulaLocalizations._();
  const NebulaLocalizations._();

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
  String get proCanvas_exportPdf => 'Export PDF';
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
  String get proCanvas_pdfTemplateSettings => 'PDF Template Settings';
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
  String get splitPanel_pdfViewer => 'PDF Viewer';
  String get splitPanel_pdfDescription => 'View and annotate PDFs';
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
  String get proCanvas_pdfMode => 'PDF Mode';
  String get proCanvas_canvasOverlay => 'Canvas Overlay';
  String get proCanvas_pdfOverlay => 'PDF Overlay';
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
}
