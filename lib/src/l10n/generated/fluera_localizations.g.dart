// GENERATED FILE — DO NOT EDIT BY HAND.
// Regenerate with: ./tool/gen_l10n.sh
//
// Source: lib/src/l10n/arb/app_en.arb (template)
//         lib/src/l10n/arb/app_it.arb

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'fluera_localizations_en.g.dart';
import 'fluera_localizations_it.g.dart';

/// Localization support for the Fluera Engine SDK.
///
/// To add the SDK localizations to your app, include [FlueraLocalizations.delegate]
/// in your `MaterialApp.localizationsDelegates`:
///
/// ```dart
/// MaterialApp(
///   localizationsDelegates: [
///     FlueraLocalizations.delegate,
///     GlobalMaterialLocalizations.delegate,
///     GlobalWidgetsLocalizations.delegate,
///   ],
///   supportedLocales: FlueraLocalizations.supportedLocales,
/// )
/// ```
///
/// If the delegate is NOT registered, [FlueraLocalizations.of] falls back to
/// English automatically — no crash, no configuration required.
abstract class FlueraLocalizations {
  FlueraLocalizations(this.localeName);

  final String localeName;

  // ---------------------------------------------------------------------------
  // Static API
  // ---------------------------------------------------------------------------

  /// Manual override. When set, [of] always returns this instance.
  static FlueraLocalizations? _override;
  static set override(FlueraLocalizations? value) => _override = value;

  /// Crash-proof lookup. Resolution order:
  /// 1. Manual [override]
  /// 2. Registered delegate via [Localizations.of]
  /// 3. English fallback
  static FlueraLocalizations of(BuildContext context) {
    if (_override != null) return _override!;
    return Localizations.of<FlueraLocalizations>(context, FlueraLocalizations)
        ?? FlueraLocalizationsEn();
  }

  /// The delegate to register in [MaterialApp.localizationsDelegates].
  static const LocalizationsDelegate<FlueraLocalizations> delegate =
      _FlueraLocalizationsDelegate();

  /// All locales supported out-of-the-box by the SDK.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('it'),
  ];

  // ---------------------------------------------------------------------------
  // COMMON
  // ---------------------------------------------------------------------------
  String get cancel;
  String get close;
  String get save;
  String get ok;
  String get delete;
  String get confirm;
  String get apply;

  // ---------------------------------------------------------------------------
  // TOOLBAR
  // ---------------------------------------------------------------------------
  String get toolbarAIFilters;

  // ---------------------------------------------------------------------------
  // PRO CANVAS
  // ---------------------------------------------------------------------------
  String get proCanvas_pen;
  String get proCanvas_undo;
  String get proCanvas_redo;
  String get proCanvas_layers;
  String get proCanvas_opacity;
  String get proCanvas_thickness;
  String get proCanvas_color;
  String get proCanvas_chooseColor;
  String get proCanvas_done;
  String get proCanvas_writing;
  String get proCanvas_brushSettings;
  String get proCanvas_brushTestingLab;
  String get proCanvas_paperMode;
  String get proCanvas_pageTemplate;
  String get proCanvas_exportCanvas;
  String get proCanvas_professionalFilters;
  String get proCanvas_ocrConvertWriting;
  String get proCanvas_ocrTextRecognition;
  String get proCanvas_selectLanguagesForRecognition;
  String get proCanvas_downloaded;
  String get proCanvas_downloadLabel;
  String proCanvas_downloadingModel(String code);
  String proCanvas_modelDownloadedSuccess(String language);
  String get proCanvas_languageModelsWillBeDownloaded;
  String get proCanvas_renameNote;
  String get proCanvas_noteName;
  String get proCanvas_enterName;
  String get proCanvas_geometricShapes;
  String get proCanvas_singleView;
  String get proCanvas_dualView;
  String get proCanvas_hide;
  String get proCanvas_show;
  String get proCanvas_advancedEditor;
  String get proCanvas_professionalEditor;
  String get proCanvas_advancedImageEdit;
  String get proCanvas_flipH;
  String get proCanvas_flipV;
  String get proCanvas_cropInstructions;
  String get proCanvas_filtersUpdatedRestartApp;
  String get proCanvas_flipHorizontal;
  String get proCanvas_flipVertical;
  String get proCanvas_convertToText;
  String get proCanvas_delete;
  String get proCanvas_close;

  // Shapes
  String get proCanvas_shapeLine;
  String get proCanvas_shapeRectangle;
  String get proCanvas_shapeCircle;
  String get proCanvas_shapeTriangle;
  String get proCanvas_shapeStar;
  String get proCanvas_shapeArrow;
  String get proCanvas_shapeDiamond;
  String get proCanvas_shapeHexagon;
  String get proCanvas_shapePentagon;
  String get proCanvas_shapeHeart;
  String get proCanvas_shapeFreehand;

  // Pages
  String get proCanvas_addPage;
  String get proCanvas_removePage;
  String get proCanvas_nextPage;
  String get proCanvas_previousPage;
  String get proCanvas_firstPage;
  String get proCanvas_lastPage;

  // Layers
  String get proCanvas_new;
  String get proCanvas_rename;
  String get proCanvas_renameLayer;
  String get proCanvas_nameLabel;
  String get proCanvas_duplicate;
  String get proCanvas_clear;

  // Image editor
  String get proCanvas_cropImage;
  String get proCanvas_editCrop;
  String get proCanvas_removeCrop;
  String get proCanvas_rotation;
  String get proCanvas_transformations;
  String get proCanvas_brightness;
  String get proCanvas_contrast;
  String get proCanvas_saturation;
  String get proCanvas_colorAdjustments;
  String get proCanvas_errorLoadingImage;
  String proCanvas_errorLoadingImageDetail(String error);

  // Filters
  String get proCanvas_filters;
  String get proCanvas_filterNone;
  String get proCanvas_filterBW;
  String get proCanvas_filterSepia;
  String get proCanvas_filterVintage;
  String get proCanvas_filterCool;
  String get proCanvas_filterWarm;
  String get proCanvas_filterDramatic;

  // Aspect ratios
  String get proCanvas_aspectFree;
  String get proCanvas_aspectSquare;
  String get proCanvas_aspect4x3;
  String get proCanvas_aspect16x9;
  String get proCanvas_aspect3x2;
  String get proCanvas_aspectRatio;

  // Before/After
  String get proCanvas_beforeAfter;

  // Advanced adjustments
  String get proCanvas_vignette;
  String get proCanvas_hueShift;
  String get proCanvas_temperature;
  String get proCanvas_imageInfo;
  String get proCanvas_undoEdit;
  String get proCanvas_redoEdit;
  String get proCanvas_discardChanges;
  String get proCanvas_discardChangesMessage;
  String get proCanvas_discardConfirm;

  // ---------------------------------------------------------------------------
  // BRUSH SETTINGS
  // ---------------------------------------------------------------------------
  String get brush_styloPressure;
  String get brush_styloDynamics;
  String get brush_styloRealism;
  String get brush_styloTapering;
  String get brush_minWidth;
  String get brush_minWidthLightPressure;
  String get brush_maxWidth;
  String get brush_maxWidthFullPressure;
  String get brush_velocitySensitivity;
  String get brush_velocitySensitivityDesc;
  String get brush_velocityInfluence;
  String get brush_velocityInfluenceDesc;
  String get brush_curvatureInfluence;
  String get brush_curvatureInfluenceDesc;
  String get brush_taperEntry;
  String get brush_taperExit;
  String get brush_pathSmoothSpline;
  String get brush_pathSmoothDesc;
  String get brush_naturalJitter;
  String get brush_jitterDesc;
  String get brush_inkAccumulation;
  String get brush_inkAccumulationDesc;
  String get brush_baseOpacity;
  String get brush_maxOpacity;
  String get brush_widthMultiplier;
  String get brush_widthMultiplierDesc;
  String get brush_points;
  String get brush_ballpoint;
  String get brush_ballpointInfo;
  String get brush_pencilTexture;
  String get brush_pencilPressure;
  String get brush_pencilOpacity;
  String get brush_graphiteBlur;
  String get brush_graphiteBlurDesc;
  String get brush_highlighter;
  String get brush_highlighterOpacityDesc;

  // ---------------------------------------------------------------------------
  // SPLIT PANEL
  // ---------------------------------------------------------------------------
  String get splitPanel_infiniteCanvas;
  String get splitPanel_canvasDescription;
  String get splitPanel_textEditor;
  String get splitPanel_textEditorDescription;
  String get splitPanel_whiteboard;
  String get splitPanel_whiteboardDescription;
  String get splitPanel_webBrowser;
  String get splitPanel_browserDescription;
  String get splitPanel_calculator;
  String get splitPanel_calculatorDescription;
  String get splitPanel_existingNote;
  String get splitPanel_noteDescription;
  String get splitPanel_emptyPanel;
  String get splitPanel_emptyDescription;

  // ---------------------------------------------------------------------------
  // TEXT INPUT / OCR
  // ---------------------------------------------------------------------------
  String get proCanvas_typeHere;
  String get proCanvas_insertText;
  String get proCanvas_textEmpty;
  String get proCanvas_ocrTextCheck;
  String get proCanvas_correct;
  String get proCanvas_capitalStart;
  String get proCanvas_endPunctuation;
  String get proCanvas_correctSpacing;
  String get proCanvas_keepHandwriting;
  String get proCanvas_previewLabel;
  String get proCanvas_colorLabel;

  // ---------------------------------------------------------------------------
  // CANVAS MODES / SPLIT
  // ---------------------------------------------------------------------------
  String get proCanvas_canvasMode;
  String get proCanvas_hSplit;
  String get proCanvas_vSplit;
  String get proCanvas_splitPro;
  String get proCanvas_canvasOverlay;
  String get proCanvas_shapes;

  // Enterprise top-row actions
  String get proCanvas_recall;
  String get proCanvas_resetRotation;
  String get proCanvas_lockRotation;
  String get proCanvas_unlockRotation;
  String get proCanvas_searchHandwriting;
  String get proCanvas_closeSearch;

  // ---------------------------------------------------------------------------
  // PAPER MODE / CANVAS SETTINGS
  // ---------------------------------------------------------------------------
  String get proCanvas_customizeYourSheet;
  String get proCanvas_backgroundColor;
  String get proCanvas_applyButton;
  String get proCanvas_paperBlank;
  String get proCanvas_paperWideLines;
  String get proCanvas_paperNarrowLines;
  String get proCanvas_paperCalligraphy;
  String get proCanvas_paperDots;
  String get proCanvas_paperDotsDense;
  String get proCanvas_paperDotGrid;
  String get proCanvas_paperGraph;
  String get proCanvas_paperHex;
  String get proCanvas_paperIsometric;
  String get proCanvas_paperMusic;
  String get proCanvas_paperCornell;
  String get proCanvas_paperStoryboard;
  String get proCanvas_paperPlanner;
  String get proCanvas_categoryBasic;
  String get proCanvas_categoryGrid;
  String get proCanvas_categoryTechnical;

  // ---------------------------------------------------------------------------
  // PDF VIEWER
  // ---------------------------------------------------------------------------
  String get pdf_importDocument;
  String get pdf_importingDocument;
  String get pdf_importFailed;
  String get pdf_importSuccess;
  String pdf_pageCount(int count);
  String pdf_pageLabel(int pageNumber);
  String get pdf_lockPage;
  String get pdf_unlockPage;
  String get pdf_lockAll;
  String get pdf_unlockAll;
  String get pdf_resetLayout;
  String get pdf_gridColumns;
  String get pdf_gridSpacing;
  String get pdf_copyText;
  String get pdf_selectText;
  String get pdf_noTextFound;
  String get pdf_textCopied;
  String get pdf_removePdf;
  String get pdf_autoFitGrid;

  // PDF toolbar UI
  String get pdf_tapToSelect;
  String get pdf_createBlankDocument;
  String get pdf_emptyA4Pages;
  String get pdf_importNotAvailable;
  String get pdf_navigate;
  String get pdf_pages;
  String get pdf_search;
  String get pdf_layout;
  String get pdf_view;
  String get pdf_nightMode;
  String get pdf_removeBookmark;
  String get pdf_bookmarkPage;
  String get pdf_zoomToFit;
  String get pdf_annotate;
  String get pdf_output;
  String get pdf_export;
  String get pdf_print;
  String get pdf_present;
  String get pdf_add;

  // Tools
  String get proCanvas_shapeRecognition;

  // ---------------------------------------------------------------------------
  // GHOST MAP (PASSO 4)
  // ---------------------------------------------------------------------------
  String get ghostMap_hypercorrectionDetected;
  String get ghostMap_conceptToDeepen;
  String get ghostMap_whatIsMissing;
  String get ghostMap_typeText;
  String get ghostMap_drawByHand;
  String get ghostMap_rewriteCorrectConcept;
  String get ghostMap_writeMissingConcept;
  String get ghostMap_drawHereHint;
  String get ghostMap_reveal;
  String ghostMap_revealCountdown(int seconds);
  String get ghostMap_compare;
  String get ghostMap_recognizing;
  String get ghostMap_ignoreNode;
  String get ghostMap_nodeIgnored;
  String get ghostMap_undo;
  String get ghostMap_hypercorrectionTitle;
  String get ghostMap_correctAttempt;
  String get ghostMap_incorrectAttempt;
  String get ghostMap_selfEvalQuestion;
  String get ghostMap_selfEvalNo;
  String get ghostMap_selfEvalYes;
  String get ghostMap_connectionToReview;
  String get ghostMap_belowZPD;
  String get ghostMap_excellentMastery;
  String get ghostMap_wellDone;
  String get ghostMap_weakPoint;
  String ghostMap_progressExplored(int revealed, int total);
  String get ghostMap_closeGhostMap;
  String get ghostMap_showMoreGaps;
  String get ghostMap_ocrFailed;
  String get ghostMap_hypercorrectionExplanation;
  String get ghostMap_writeAtLeastTwoGroups;
  String get ghostMap_trySocraticFirst;
  String get ghostMap_belowZPDExplanation;
  String get ghostMap_dismissGuidanceExcellent;
  String get ghostMap_dismissGuidanceGood;
  String get ghostMap_dismissGuidanceDefault;
  String get ghostMap_proceedAnyway;
  // O-8: Painter overlay labels
  String get ghostMap_tapToAttempt;
  String get ghostMap_hypercorrectionLabel;
  String get ghostMap_belowZPDLabel;

  // ─── L10n Pass 2: Remaining 22 strings ──────────────────────────────────
  // Simple strings (no params)
  String get ghostMap_loadingAnalyzing;
  String get ghostMap_penModeHint;
  String get ghostMap_ocrFallbackMessage;
  String get ghostMap_atlasAnswer;
  String get ghostMap_sleepConsolidation;
  String get ghostMap_retryHint;
  String get ghostMap_emptyResultError;
  String get ghostMap_edgeCaseNearlyPerfect;
  String get ghostMap_edgeCaseVeryIncomplete;
  // Methods with int param
  String ghostMap_activationGapsFound(int count);
  String ghostMap_activationConfirmed(int count);
  String ghostMap_activationHypercorrections(int count);
  String ghostMap_confidenceLevel(int level);
  String ghostMap_growthSuffix(int percent);
  String ghostMap_rateLimitWait(int seconds);
  String ghostMap_summaryCorrect(int count);
  String ghostMap_summaryWeak(int count);
  String ghostMap_summaryMissing(int count);
  String ghostMap_summaryGrowth(int percent);
  // Methods with two int params
  String ghostMap_summaryAttempts(int correct, int total);
  // Methods with String param
  String ghostMap_activationHeader(String details);
  String ghostMap_errorGeneric(String message);
  String get ghostMap_yourAttempt;
}


// =============================================================================
// Delegate
// =============================================================================

class _FlueraLocalizationsDelegate
    extends LocalizationsDelegate<FlueraLocalizations> {
  const _FlueraLocalizationsDelegate();

  @override
  Future<FlueraLocalizations> load(Locale locale) {
    return SynchronousFuture<FlueraLocalizations>(
      _lookupFlueraLocalizations(locale),
    );
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'it'].contains(locale.languageCode);

  @override
  bool shouldReload(_FlueraLocalizationsDelegate old) => false;
}

FlueraLocalizations _lookupFlueraLocalizations(Locale locale) {
  switch (locale.languageCode) {
    case 'it':
      return FlueraLocalizationsIt();
    case 'en':
    default:
      return FlueraLocalizationsEn();
  }
}
