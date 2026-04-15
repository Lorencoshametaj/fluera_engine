import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'fluera_localizations_en.g.dart';
import 'fluera_localizations_it.g.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of FlueraLocalizations
/// returned by `FlueraLocalizations.of(context)`.
///
/// Applications need to include `FlueraLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/fluera_localizations.g.dart';
///
/// return MaterialApp(
///   localizationsDelegates: FlueraLocalizations.localizationsDelegates,
///   supportedLocales: FlueraLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the FlueraLocalizations.supportedLocales
/// property.
abstract class FlueraLocalizations {
  FlueraLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static FlueraLocalizations? of(BuildContext context) {
    return Localizations.of<FlueraLocalizations>(context, FlueraLocalizations);
  }

  static const LocalizationsDelegate<FlueraLocalizations> delegate =
      _FlueraLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('it'),
  ];

  /// Generic cancel action
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @toolbarAIFilters.
  ///
  /// In en, this message translates to:
  /// **'AI Filters'**
  String get toolbarAIFilters;

  /// No description provided for @proCanvas_pen.
  ///
  /// In en, this message translates to:
  /// **'Pen'**
  String get proCanvas_pen;

  /// No description provided for @proCanvas_undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get proCanvas_undo;

  /// No description provided for @proCanvas_redo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get proCanvas_redo;

  /// No description provided for @proCanvas_layers.
  ///
  /// In en, this message translates to:
  /// **'Layers'**
  String get proCanvas_layers;

  /// No description provided for @proCanvas_opacity.
  ///
  /// In en, this message translates to:
  /// **'Opacity'**
  String get proCanvas_opacity;

  /// No description provided for @proCanvas_thickness.
  ///
  /// In en, this message translates to:
  /// **'Thickness'**
  String get proCanvas_thickness;

  /// No description provided for @proCanvas_color.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get proCanvas_color;

  /// No description provided for @proCanvas_chooseColor.
  ///
  /// In en, this message translates to:
  /// **'Choose Color'**
  String get proCanvas_chooseColor;

  /// No description provided for @proCanvas_done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get proCanvas_done;

  /// No description provided for @proCanvas_writing.
  ///
  /// In en, this message translates to:
  /// **'Writing'**
  String get proCanvas_writing;

  /// No description provided for @proCanvas_brushSettings.
  ///
  /// In en, this message translates to:
  /// **'Brush Settings'**
  String get proCanvas_brushSettings;

  /// No description provided for @proCanvas_brushTestingLab.
  ///
  /// In en, this message translates to:
  /// **'Brush Testing Lab'**
  String get proCanvas_brushTestingLab;

  /// No description provided for @proCanvas_paperMode.
  ///
  /// In en, this message translates to:
  /// **'Paper Mode'**
  String get proCanvas_paperMode;

  /// No description provided for @proCanvas_pageTemplate.
  ///
  /// In en, this message translates to:
  /// **'Page Template'**
  String get proCanvas_pageTemplate;

  /// No description provided for @proCanvas_exportCanvas.
  ///
  /// In en, this message translates to:
  /// **'Export Canvas'**
  String get proCanvas_exportCanvas;

  /// No description provided for @proCanvas_professionalFilters.
  ///
  /// In en, this message translates to:
  /// **'Professional Filters'**
  String get proCanvas_professionalFilters;

  /// No description provided for @proCanvas_ocrConvertWriting.
  ///
  /// In en, this message translates to:
  /// **'OCR — Convert Writing'**
  String get proCanvas_ocrConvertWriting;

  /// No description provided for @proCanvas_ocrTextRecognition.
  ///
  /// In en, this message translates to:
  /// **'Text Recognition'**
  String get proCanvas_ocrTextRecognition;

  /// No description provided for @proCanvas_selectLanguagesForRecognition.
  ///
  /// In en, this message translates to:
  /// **'Select languages for recognition'**
  String get proCanvas_selectLanguagesForRecognition;

  /// No description provided for @proCanvas_downloaded.
  ///
  /// In en, this message translates to:
  /// **'Downloaded'**
  String get proCanvas_downloaded;

  /// No description provided for @proCanvas_downloadLabel.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get proCanvas_downloadLabel;

  /// No description provided for @proCanvas_downloadingModel.
  ///
  /// In en, this message translates to:
  /// **'Downloading model ({code})...'**
  String proCanvas_downloadingModel(String code);

  /// No description provided for @proCanvas_modelDownloadedSuccess.
  ///
  /// In en, this message translates to:
  /// **'{language} model downloaded successfully'**
  String proCanvas_modelDownloadedSuccess(String language);

  /// No description provided for @proCanvas_languageModelsWillBeDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Language models will be downloaded for offline use'**
  String get proCanvas_languageModelsWillBeDownloaded;

  /// No description provided for @proCanvas_renameNote.
  ///
  /// In en, this message translates to:
  /// **'Rename Note'**
  String get proCanvas_renameNote;

  /// No description provided for @proCanvas_noteName.
  ///
  /// In en, this message translates to:
  /// **'Note Name'**
  String get proCanvas_noteName;

  /// No description provided for @proCanvas_enterName.
  ///
  /// In en, this message translates to:
  /// **'Enter name...'**
  String get proCanvas_enterName;

  /// No description provided for @proCanvas_geometricShapes.
  ///
  /// In en, this message translates to:
  /// **'Geometric Shapes'**
  String get proCanvas_geometricShapes;

  /// No description provided for @proCanvas_singleView.
  ///
  /// In en, this message translates to:
  /// **'Single View'**
  String get proCanvas_singleView;

  /// No description provided for @proCanvas_dualView.
  ///
  /// In en, this message translates to:
  /// **'Dual View'**
  String get proCanvas_dualView;

  /// No description provided for @proCanvas_hide.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get proCanvas_hide;

  /// No description provided for @proCanvas_show.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get proCanvas_show;

  /// No description provided for @proCanvas_advancedEditor.
  ///
  /// In en, this message translates to:
  /// **'Advanced Editor'**
  String get proCanvas_advancedEditor;

  /// No description provided for @proCanvas_professionalEditor.
  ///
  /// In en, this message translates to:
  /// **'Professional Editor'**
  String get proCanvas_professionalEditor;

  /// No description provided for @proCanvas_advancedImageEdit.
  ///
  /// In en, this message translates to:
  /// **'Advanced Image Editing'**
  String get proCanvas_advancedImageEdit;

  /// No description provided for @proCanvas_flipH.
  ///
  /// In en, this message translates to:
  /// **'Flip Horizontal'**
  String get proCanvas_flipH;

  /// No description provided for @proCanvas_flipV.
  ///
  /// In en, this message translates to:
  /// **'Flip Vertical'**
  String get proCanvas_flipV;

  /// No description provided for @proCanvas_cropInstructions.
  ///
  /// In en, this message translates to:
  /// **'Drag corners to crop'**
  String get proCanvas_cropInstructions;

  /// No description provided for @proCanvas_filtersUpdatedRestartApp.
  ///
  /// In en, this message translates to:
  /// **'Filters updated. Restart app to apply.'**
  String get proCanvas_filtersUpdatedRestartApp;

  /// No description provided for @proCanvas_flipHorizontal.
  ///
  /// In en, this message translates to:
  /// **'Flip Horizontal'**
  String get proCanvas_flipHorizontal;

  /// No description provided for @proCanvas_flipVertical.
  ///
  /// In en, this message translates to:
  /// **'Flip Vertical'**
  String get proCanvas_flipVertical;

  /// No description provided for @proCanvas_convertToText.
  ///
  /// In en, this message translates to:
  /// **'Convert to Text'**
  String get proCanvas_convertToText;

  /// No description provided for @proCanvas_delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get proCanvas_delete;

  /// No description provided for @proCanvas_close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get proCanvas_close;

  /// No description provided for @proCanvas_shapeLine.
  ///
  /// In en, this message translates to:
  /// **'Line'**
  String get proCanvas_shapeLine;

  /// No description provided for @proCanvas_shapeRectangle.
  ///
  /// In en, this message translates to:
  /// **'Rectangle'**
  String get proCanvas_shapeRectangle;

  /// No description provided for @proCanvas_shapeCircle.
  ///
  /// In en, this message translates to:
  /// **'Circle'**
  String get proCanvas_shapeCircle;

  /// No description provided for @proCanvas_shapeTriangle.
  ///
  /// In en, this message translates to:
  /// **'Triangle'**
  String get proCanvas_shapeTriangle;

  /// No description provided for @proCanvas_shapeStar.
  ///
  /// In en, this message translates to:
  /// **'Star'**
  String get proCanvas_shapeStar;

  /// No description provided for @proCanvas_shapeArrow.
  ///
  /// In en, this message translates to:
  /// **'Arrow'**
  String get proCanvas_shapeArrow;

  /// No description provided for @proCanvas_shapeDiamond.
  ///
  /// In en, this message translates to:
  /// **'Diamond'**
  String get proCanvas_shapeDiamond;

  /// No description provided for @proCanvas_shapeHexagon.
  ///
  /// In en, this message translates to:
  /// **'Hexagon'**
  String get proCanvas_shapeHexagon;

  /// No description provided for @proCanvas_shapePentagon.
  ///
  /// In en, this message translates to:
  /// **'Pentagon'**
  String get proCanvas_shapePentagon;

  /// No description provided for @proCanvas_shapeHeart.
  ///
  /// In en, this message translates to:
  /// **'Heart'**
  String get proCanvas_shapeHeart;

  /// No description provided for @proCanvas_shapeFreehand.
  ///
  /// In en, this message translates to:
  /// **'Freehand'**
  String get proCanvas_shapeFreehand;

  /// No description provided for @proCanvas_addPage.
  ///
  /// In en, this message translates to:
  /// **'Add Page'**
  String get proCanvas_addPage;

  /// No description provided for @proCanvas_removePage.
  ///
  /// In en, this message translates to:
  /// **'Remove Page'**
  String get proCanvas_removePage;

  /// No description provided for @proCanvas_nextPage.
  ///
  /// In en, this message translates to:
  /// **'Next Page'**
  String get proCanvas_nextPage;

  /// No description provided for @proCanvas_previousPage.
  ///
  /// In en, this message translates to:
  /// **'Previous Page'**
  String get proCanvas_previousPage;

  /// No description provided for @proCanvas_firstPage.
  ///
  /// In en, this message translates to:
  /// **'First Page'**
  String get proCanvas_firstPage;

  /// No description provided for @proCanvas_lastPage.
  ///
  /// In en, this message translates to:
  /// **'Last Page'**
  String get proCanvas_lastPage;

  /// No description provided for @proCanvas_new.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get proCanvas_new;

  /// No description provided for @proCanvas_rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get proCanvas_rename;

  /// No description provided for @proCanvas_renameLayer.
  ///
  /// In en, this message translates to:
  /// **'Rename Layer'**
  String get proCanvas_renameLayer;

  /// No description provided for @proCanvas_nameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get proCanvas_nameLabel;

  /// No description provided for @proCanvas_duplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get proCanvas_duplicate;

  /// No description provided for @proCanvas_clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get proCanvas_clear;

  /// No description provided for @proCanvas_cropImage.
  ///
  /// In en, this message translates to:
  /// **'Crop Image'**
  String get proCanvas_cropImage;

  /// No description provided for @proCanvas_editCrop.
  ///
  /// In en, this message translates to:
  /// **'Edit Crop'**
  String get proCanvas_editCrop;

  /// No description provided for @proCanvas_removeCrop.
  ///
  /// In en, this message translates to:
  /// **'Remove Crop'**
  String get proCanvas_removeCrop;

  /// No description provided for @proCanvas_rotation.
  ///
  /// In en, this message translates to:
  /// **'Rotation'**
  String get proCanvas_rotation;

  /// No description provided for @proCanvas_transformations.
  ///
  /// In en, this message translates to:
  /// **'Transformations'**
  String get proCanvas_transformations;

  /// No description provided for @proCanvas_brightness.
  ///
  /// In en, this message translates to:
  /// **'Brightness'**
  String get proCanvas_brightness;

  /// No description provided for @proCanvas_contrast.
  ///
  /// In en, this message translates to:
  /// **'Contrast'**
  String get proCanvas_contrast;

  /// No description provided for @proCanvas_saturation.
  ///
  /// In en, this message translates to:
  /// **'Saturation'**
  String get proCanvas_saturation;

  /// No description provided for @proCanvas_colorAdjustments.
  ///
  /// In en, this message translates to:
  /// **'Color Adjustments'**
  String get proCanvas_colorAdjustments;

  /// No description provided for @proCanvas_errorLoadingImage.
  ///
  /// In en, this message translates to:
  /// **'Error loading image'**
  String get proCanvas_errorLoadingImage;

  /// No description provided for @proCanvas_errorLoadingImageDetail.
  ///
  /// In en, this message translates to:
  /// **'Error loading image: {error}'**
  String proCanvas_errorLoadingImageDetail(String error);

  /// No description provided for @proCanvas_filters.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get proCanvas_filters;

  /// No description provided for @proCanvas_filterNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get proCanvas_filterNone;

  /// No description provided for @proCanvas_filterBW.
  ///
  /// In en, this message translates to:
  /// **'B&W'**
  String get proCanvas_filterBW;

  /// No description provided for @proCanvas_filterSepia.
  ///
  /// In en, this message translates to:
  /// **'Sepia'**
  String get proCanvas_filterSepia;

  /// No description provided for @proCanvas_filterVintage.
  ///
  /// In en, this message translates to:
  /// **'Vintage'**
  String get proCanvas_filterVintage;

  /// No description provided for @proCanvas_filterCool.
  ///
  /// In en, this message translates to:
  /// **'Cool'**
  String get proCanvas_filterCool;

  /// No description provided for @proCanvas_filterWarm.
  ///
  /// In en, this message translates to:
  /// **'Warm'**
  String get proCanvas_filterWarm;

  /// No description provided for @proCanvas_filterDramatic.
  ///
  /// In en, this message translates to:
  /// **'Dramatic'**
  String get proCanvas_filterDramatic;

  /// No description provided for @proCanvas_aspectFree.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get proCanvas_aspectFree;

  /// No description provided for @proCanvas_aspectSquare.
  ///
  /// In en, this message translates to:
  /// **'1:1'**
  String get proCanvas_aspectSquare;

  /// No description provided for @proCanvas_aspect4x3.
  ///
  /// In en, this message translates to:
  /// **'4:3'**
  String get proCanvas_aspect4x3;

  /// No description provided for @proCanvas_aspect16x9.
  ///
  /// In en, this message translates to:
  /// **'16:9'**
  String get proCanvas_aspect16x9;

  /// No description provided for @proCanvas_aspect3x2.
  ///
  /// In en, this message translates to:
  /// **'3:2'**
  String get proCanvas_aspect3x2;

  /// No description provided for @proCanvas_aspectRatio.
  ///
  /// In en, this message translates to:
  /// **'Aspect Ratio'**
  String get proCanvas_aspectRatio;

  /// No description provided for @proCanvas_beforeAfter.
  ///
  /// In en, this message translates to:
  /// **'Before / After'**
  String get proCanvas_beforeAfter;

  /// No description provided for @proCanvas_vignette.
  ///
  /// In en, this message translates to:
  /// **'Vignette'**
  String get proCanvas_vignette;

  /// No description provided for @proCanvas_hueShift.
  ///
  /// In en, this message translates to:
  /// **'Hue'**
  String get proCanvas_hueShift;

  /// No description provided for @proCanvas_temperature.
  ///
  /// In en, this message translates to:
  /// **'Temperature'**
  String get proCanvas_temperature;

  /// No description provided for @proCanvas_imageInfo.
  ///
  /// In en, this message translates to:
  /// **'Image Info'**
  String get proCanvas_imageInfo;

  /// No description provided for @proCanvas_undoEdit.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get proCanvas_undoEdit;

  /// No description provided for @proCanvas_redoEdit.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get proCanvas_redoEdit;

  /// No description provided for @proCanvas_discardChanges.
  ///
  /// In en, this message translates to:
  /// **'Discard changes?'**
  String get proCanvas_discardChanges;

  /// No description provided for @proCanvas_discardChangesMessage.
  ///
  /// In en, this message translates to:
  /// **'You have unsaved edits. Are you sure you want to discard them?'**
  String get proCanvas_discardChangesMessage;

  /// No description provided for @proCanvas_discardConfirm.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get proCanvas_discardConfirm;

  /// No description provided for @brush_styloPressure.
  ///
  /// In en, this message translates to:
  /// **'Pressure Sensitivity'**
  String get brush_styloPressure;

  /// No description provided for @brush_styloDynamics.
  ///
  /// In en, this message translates to:
  /// **'Dynamics'**
  String get brush_styloDynamics;

  /// No description provided for @brush_styloRealism.
  ///
  /// In en, this message translates to:
  /// **'Realism'**
  String get brush_styloRealism;

  /// No description provided for @brush_styloTapering.
  ///
  /// In en, this message translates to:
  /// **'Tapering'**
  String get brush_styloTapering;

  /// No description provided for @brush_minWidth.
  ///
  /// In en, this message translates to:
  /// **'Min Width'**
  String get brush_minWidth;

  /// No description provided for @brush_minWidthLightPressure.
  ///
  /// In en, this message translates to:
  /// **'Width at light pressure'**
  String get brush_minWidthLightPressure;

  /// No description provided for @brush_maxWidth.
  ///
  /// In en, this message translates to:
  /// **'Max Width'**
  String get brush_maxWidth;

  /// No description provided for @brush_maxWidthFullPressure.
  ///
  /// In en, this message translates to:
  /// **'Width at full pressure'**
  String get brush_maxWidthFullPressure;

  /// No description provided for @brush_velocitySensitivity.
  ///
  /// In en, this message translates to:
  /// **'Velocity Sensitivity'**
  String get brush_velocitySensitivity;

  /// No description provided for @brush_velocitySensitivityDesc.
  ///
  /// In en, this message translates to:
  /// **'How much stroke velocity affects width'**
  String get brush_velocitySensitivityDesc;

  /// No description provided for @brush_velocityInfluence.
  ///
  /// In en, this message translates to:
  /// **'Velocity Influence'**
  String get brush_velocityInfluence;

  /// No description provided for @brush_velocityInfluenceDesc.
  ///
  /// In en, this message translates to:
  /// **'Strength of velocity effect on stroke'**
  String get brush_velocityInfluenceDesc;

  /// No description provided for @brush_curvatureInfluence.
  ///
  /// In en, this message translates to:
  /// **'Curvature Influence'**
  String get brush_curvatureInfluence;

  /// No description provided for @brush_curvatureInfluenceDesc.
  ///
  /// In en, this message translates to:
  /// **'How path curvature affects width'**
  String get brush_curvatureInfluenceDesc;

  /// No description provided for @brush_taperEntry.
  ///
  /// In en, this message translates to:
  /// **'Taper Entry'**
  String get brush_taperEntry;

  /// No description provided for @brush_taperExit.
  ///
  /// In en, this message translates to:
  /// **'Taper Exit'**
  String get brush_taperExit;

  /// No description provided for @brush_pathSmoothSpline.
  ///
  /// In en, this message translates to:
  /// **'Path Smoothing (Spline)'**
  String get brush_pathSmoothSpline;

  /// No description provided for @brush_pathSmoothDesc.
  ///
  /// In en, this message translates to:
  /// **'Catmull-Rom spline interpolation level'**
  String get brush_pathSmoothDesc;

  /// No description provided for @brush_naturalJitter.
  ///
  /// In en, this message translates to:
  /// **'Natural Jitter'**
  String get brush_naturalJitter;

  /// No description provided for @brush_jitterDesc.
  ///
  /// In en, this message translates to:
  /// **'Simulates natural hand tremor'**
  String get brush_jitterDesc;

  /// No description provided for @brush_inkAccumulation.
  ///
  /// In en, this message translates to:
  /// **'Ink Accumulation'**
  String get brush_inkAccumulation;

  /// No description provided for @brush_inkAccumulationDesc.
  ///
  /// In en, this message translates to:
  /// **'Ink builds up where pen stays longer'**
  String get brush_inkAccumulationDesc;

  /// No description provided for @brush_baseOpacity.
  ///
  /// In en, this message translates to:
  /// **'Base Opacity'**
  String get brush_baseOpacity;

  /// No description provided for @brush_maxOpacity.
  ///
  /// In en, this message translates to:
  /// **'Max Opacity'**
  String get brush_maxOpacity;

  /// No description provided for @brush_widthMultiplier.
  ///
  /// In en, this message translates to:
  /// **'Width Multiplier'**
  String get brush_widthMultiplier;

  /// No description provided for @brush_widthMultiplierDesc.
  ///
  /// In en, this message translates to:
  /// **'Global width scaling factor'**
  String get brush_widthMultiplierDesc;

  /// No description provided for @brush_points.
  ///
  /// In en, this message translates to:
  /// **'pts'**
  String get brush_points;

  /// No description provided for @brush_ballpoint.
  ///
  /// In en, this message translates to:
  /// **'Ballpoint'**
  String get brush_ballpoint;

  /// No description provided for @brush_ballpointInfo.
  ///
  /// In en, this message translates to:
  /// **'Standard ballpoint pen settings'**
  String get brush_ballpointInfo;

  /// No description provided for @brush_pencilTexture.
  ///
  /// In en, this message translates to:
  /// **'Pencil Texture'**
  String get brush_pencilTexture;

  /// No description provided for @brush_pencilPressure.
  ///
  /// In en, this message translates to:
  /// **'Pencil Pressure'**
  String get brush_pencilPressure;

  /// No description provided for @brush_pencilOpacity.
  ///
  /// In en, this message translates to:
  /// **'Pencil Opacity'**
  String get brush_pencilOpacity;

  /// No description provided for @brush_graphiteBlur.
  ///
  /// In en, this message translates to:
  /// **'Graphite Blur'**
  String get brush_graphiteBlur;

  /// No description provided for @brush_graphiteBlurDesc.
  ///
  /// In en, this message translates to:
  /// **'Softness of pencil strokes'**
  String get brush_graphiteBlurDesc;

  /// No description provided for @brush_highlighter.
  ///
  /// In en, this message translates to:
  /// **'Highlighter'**
  String get brush_highlighter;

  /// No description provided for @brush_highlighterOpacityDesc.
  ///
  /// In en, this message translates to:
  /// **'Transparency of highlighter strokes'**
  String get brush_highlighterOpacityDesc;

  /// No description provided for @splitPanel_infiniteCanvas.
  ///
  /// In en, this message translates to:
  /// **'Infinite Canvas'**
  String get splitPanel_infiniteCanvas;

  /// No description provided for @splitPanel_canvasDescription.
  ///
  /// In en, this message translates to:
  /// **'Draw on an infinite canvas'**
  String get splitPanel_canvasDescription;

  /// No description provided for @splitPanel_textEditor.
  ///
  /// In en, this message translates to:
  /// **'Text Editor'**
  String get splitPanel_textEditor;

  /// No description provided for @splitPanel_textEditorDescription.
  ///
  /// In en, this message translates to:
  /// **'Write and edit text'**
  String get splitPanel_textEditorDescription;

  /// No description provided for @splitPanel_whiteboard.
  ///
  /// In en, this message translates to:
  /// **'Whiteboard'**
  String get splitPanel_whiteboard;

  /// No description provided for @splitPanel_whiteboardDescription.
  ///
  /// In en, this message translates to:
  /// **'Simple whiteboard'**
  String get splitPanel_whiteboardDescription;

  /// No description provided for @splitPanel_webBrowser.
  ///
  /// In en, this message translates to:
  /// **'Web Browser'**
  String get splitPanel_webBrowser;

  /// No description provided for @splitPanel_browserDescription.
  ///
  /// In en, this message translates to:
  /// **'Browse the web'**
  String get splitPanel_browserDescription;

  /// No description provided for @splitPanel_calculator.
  ///
  /// In en, this message translates to:
  /// **'Calculator'**
  String get splitPanel_calculator;

  /// No description provided for @splitPanel_calculatorDescription.
  ///
  /// In en, this message translates to:
  /// **'Scientific calculator'**
  String get splitPanel_calculatorDescription;

  /// No description provided for @splitPanel_existingNote.
  ///
  /// In en, this message translates to:
  /// **'Existing Note'**
  String get splitPanel_existingNote;

  /// No description provided for @splitPanel_noteDescription.
  ///
  /// In en, this message translates to:
  /// **'Open an existing note'**
  String get splitPanel_noteDescription;

  /// No description provided for @splitPanel_emptyPanel.
  ///
  /// In en, this message translates to:
  /// **'Empty Panel'**
  String get splitPanel_emptyPanel;

  /// No description provided for @splitPanel_emptyDescription.
  ///
  /// In en, this message translates to:
  /// **'Start with an empty panel'**
  String get splitPanel_emptyDescription;

  /// No description provided for @proCanvas_typeHere.
  ///
  /// In en, this message translates to:
  /// **'Type here...'**
  String get proCanvas_typeHere;

  /// No description provided for @proCanvas_insertText.
  ///
  /// In en, this message translates to:
  /// **'Insert Text'**
  String get proCanvas_insertText;

  /// No description provided for @proCanvas_textEmpty.
  ///
  /// In en, this message translates to:
  /// **'Text is empty'**
  String get proCanvas_textEmpty;

  /// No description provided for @proCanvas_ocrTextCheck.
  ///
  /// In en, this message translates to:
  /// **'Text Check'**
  String get proCanvas_ocrTextCheck;

  /// No description provided for @proCanvas_correct.
  ///
  /// In en, this message translates to:
  /// **'Correct'**
  String get proCanvas_correct;

  /// No description provided for @proCanvas_capitalStart.
  ///
  /// In en, this message translates to:
  /// **'Capitalize first letter'**
  String get proCanvas_capitalStart;

  /// No description provided for @proCanvas_endPunctuation.
  ///
  /// In en, this message translates to:
  /// **'End punctuation'**
  String get proCanvas_endPunctuation;

  /// No description provided for @proCanvas_correctSpacing.
  ///
  /// In en, this message translates to:
  /// **'Correct spacing'**
  String get proCanvas_correctSpacing;

  /// No description provided for @proCanvas_keepHandwriting.
  ///
  /// In en, this message translates to:
  /// **'Keep handwriting style'**
  String get proCanvas_keepHandwriting;

  /// No description provided for @proCanvas_previewLabel.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get proCanvas_previewLabel;

  /// No description provided for @proCanvas_colorLabel.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get proCanvas_colorLabel;

  /// No description provided for @proCanvas_canvasMode.
  ///
  /// In en, this message translates to:
  /// **'Canvas Mode'**
  String get proCanvas_canvasMode;

  /// No description provided for @proCanvas_hSplit.
  ///
  /// In en, this message translates to:
  /// **'Horizontal Split'**
  String get proCanvas_hSplit;

  /// No description provided for @proCanvas_vSplit.
  ///
  /// In en, this message translates to:
  /// **'Vertical Split'**
  String get proCanvas_vSplit;

  /// No description provided for @proCanvas_splitPro.
  ///
  /// In en, this message translates to:
  /// **'Split Pro'**
  String get proCanvas_splitPro;

  /// No description provided for @proCanvas_canvasOverlay.
  ///
  /// In en, this message translates to:
  /// **'Canvas Overlay'**
  String get proCanvas_canvasOverlay;

  /// No description provided for @proCanvas_shapes.
  ///
  /// In en, this message translates to:
  /// **'Shapes'**
  String get proCanvas_shapes;

  /// No description provided for @proCanvas_recall.
  ///
  /// In en, this message translates to:
  /// **'Test me'**
  String get proCanvas_recall;

  /// No description provided for @proCanvas_socratic.
  ///
  /// In en, this message translates to:
  /// **'Quiz me'**
  String get proCanvas_socratic;

  /// No description provided for @proCanvas_ghostMap.
  ///
  /// In en, this message translates to:
  /// **'What am I missing?'**
  String get proCanvas_ghostMap;

  /// No description provided for @proCanvas_fogOfWar.
  ///
  /// In en, this message translates to:
  /// **'Challenge'**
  String get proCanvas_fogOfWar;

  /// No description provided for @proCanvas_recording.
  ///
  /// In en, this message translates to:
  /// **'Record'**
  String get proCanvas_recording;

  /// No description provided for @proCanvas_resetRotation.
  ///
  /// In en, this message translates to:
  /// **'Reset Rotation'**
  String get proCanvas_resetRotation;

  /// No description provided for @proCanvas_lockRotation.
  ///
  /// In en, this message translates to:
  /// **'Lock Rotation'**
  String get proCanvas_lockRotation;

  /// No description provided for @proCanvas_unlockRotation.
  ///
  /// In en, this message translates to:
  /// **'Unlock Rotation'**
  String get proCanvas_unlockRotation;

  /// No description provided for @proCanvas_searchHandwriting.
  ///
  /// In en, this message translates to:
  /// **'Search Handwriting'**
  String get proCanvas_searchHandwriting;

  /// No description provided for @proCanvas_closeSearch.
  ///
  /// In en, this message translates to:
  /// **'Close Search'**
  String get proCanvas_closeSearch;

  /// No description provided for @proCanvas_customizeYourSheet.
  ///
  /// In en, this message translates to:
  /// **'Customize your sheet'**
  String get proCanvas_customizeYourSheet;

  /// No description provided for @proCanvas_backgroundColor.
  ///
  /// In en, this message translates to:
  /// **'Background Color'**
  String get proCanvas_backgroundColor;

  /// No description provided for @proCanvas_applyButton.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get proCanvas_applyButton;

  /// No description provided for @proCanvas_paperBlank.
  ///
  /// In en, this message translates to:
  /// **'Blank'**
  String get proCanvas_paperBlank;

  /// No description provided for @proCanvas_paperWideLines.
  ///
  /// In en, this message translates to:
  /// **'Wide Lines'**
  String get proCanvas_paperWideLines;

  /// No description provided for @proCanvas_paperNarrowLines.
  ///
  /// In en, this message translates to:
  /// **'Narrow Lines'**
  String get proCanvas_paperNarrowLines;

  /// No description provided for @proCanvas_paperCalligraphy.
  ///
  /// In en, this message translates to:
  /// **'Calligraphy'**
  String get proCanvas_paperCalligraphy;

  /// No description provided for @proCanvas_paperDots.
  ///
  /// In en, this message translates to:
  /// **'Dots'**
  String get proCanvas_paperDots;

  /// No description provided for @proCanvas_paperDotsDense.
  ///
  /// In en, this message translates to:
  /// **'Dense Dots'**
  String get proCanvas_paperDotsDense;

  /// No description provided for @proCanvas_paperDotGrid.
  ///
  /// In en, this message translates to:
  /// **'Dot Grid'**
  String get proCanvas_paperDotGrid;

  /// No description provided for @proCanvas_paperGraph.
  ///
  /// In en, this message translates to:
  /// **'Graph'**
  String get proCanvas_paperGraph;

  /// No description provided for @proCanvas_paperHex.
  ///
  /// In en, this message translates to:
  /// **'Hexagonal'**
  String get proCanvas_paperHex;

  /// No description provided for @proCanvas_paperIsometric.
  ///
  /// In en, this message translates to:
  /// **'Isometric'**
  String get proCanvas_paperIsometric;

  /// No description provided for @proCanvas_paperMusic.
  ///
  /// In en, this message translates to:
  /// **'Music Staff'**
  String get proCanvas_paperMusic;

  /// No description provided for @proCanvas_paperCornell.
  ///
  /// In en, this message translates to:
  /// **'Cornell Notes'**
  String get proCanvas_paperCornell;

  /// No description provided for @proCanvas_paperStoryboard.
  ///
  /// In en, this message translates to:
  /// **'Storyboard'**
  String get proCanvas_paperStoryboard;

  /// No description provided for @proCanvas_paperPlanner.
  ///
  /// In en, this message translates to:
  /// **'Planner'**
  String get proCanvas_paperPlanner;

  /// No description provided for @proCanvas_categoryBasic.
  ///
  /// In en, this message translates to:
  /// **'Basic'**
  String get proCanvas_categoryBasic;

  /// No description provided for @proCanvas_categoryGrid.
  ///
  /// In en, this message translates to:
  /// **'Grid'**
  String get proCanvas_categoryGrid;

  /// No description provided for @proCanvas_categoryTechnical.
  ///
  /// In en, this message translates to:
  /// **'Technical'**
  String get proCanvas_categoryTechnical;

  /// No description provided for @pdf_importDocument.
  ///
  /// In en, this message translates to:
  /// **'Import PDF'**
  String get pdf_importDocument;

  /// No description provided for @pdf_importingDocument.
  ///
  /// In en, this message translates to:
  /// **'Importing PDF...'**
  String get pdf_importingDocument;

  /// No description provided for @pdf_importFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to import PDF'**
  String get pdf_importFailed;

  /// No description provided for @pdf_importSuccess.
  ///
  /// In en, this message translates to:
  /// **'PDF imported successfully'**
  String get pdf_importSuccess;

  /// No description provided for @pdf_pageCount.
  ///
  /// In en, this message translates to:
  /// **'{count} pages'**
  String pdf_pageCount(int count);

  /// No description provided for @pdf_pageLabel.
  ///
  /// In en, this message translates to:
  /// **'Page {pageNumber}'**
  String pdf_pageLabel(int pageNumber);

  /// No description provided for @pdf_lockPage.
  ///
  /// In en, this message translates to:
  /// **'Lock to Grid'**
  String get pdf_lockPage;

  /// No description provided for @pdf_unlockPage.
  ///
  /// In en, this message translates to:
  /// **'Unlock from Grid'**
  String get pdf_unlockPage;

  /// No description provided for @pdf_lockAll.
  ///
  /// In en, this message translates to:
  /// **'Lock All Pages'**
  String get pdf_lockAll;

  /// No description provided for @pdf_unlockAll.
  ///
  /// In en, this message translates to:
  /// **'Unlock All Pages'**
  String get pdf_unlockAll;

  /// No description provided for @pdf_resetLayout.
  ///
  /// In en, this message translates to:
  /// **'Reset Layout'**
  String get pdf_resetLayout;

  /// No description provided for @pdf_gridColumns.
  ///
  /// In en, this message translates to:
  /// **'Grid Columns'**
  String get pdf_gridColumns;

  /// No description provided for @pdf_gridSpacing.
  ///
  /// In en, this message translates to:
  /// **'Grid Spacing'**
  String get pdf_gridSpacing;

  /// No description provided for @pdf_copyText.
  ///
  /// In en, this message translates to:
  /// **'Copy Text'**
  String get pdf_copyText;

  /// No description provided for @pdf_selectText.
  ///
  /// In en, this message translates to:
  /// **'Select Text'**
  String get pdf_selectText;

  /// No description provided for @pdf_noTextFound.
  ///
  /// In en, this message translates to:
  /// **'No text found on this page'**
  String get pdf_noTextFound;

  /// No description provided for @pdf_textCopied.
  ///
  /// In en, this message translates to:
  /// **'Text copied to clipboard'**
  String get pdf_textCopied;

  /// No description provided for @pdf_removePdf.
  ///
  /// In en, this message translates to:
  /// **'Remove PDF'**
  String get pdf_removePdf;

  /// No description provided for @pdf_autoFitGrid.
  ///
  /// In en, this message translates to:
  /// **'Auto-fit Grid'**
  String get pdf_autoFitGrid;

  /// No description provided for @ghostMap_hypercorrectionDetected.
  ///
  /// In en, this message translates to:
  /// **'Hypercorrection detected!'**
  String get ghostMap_hypercorrectionDetected;

  /// No description provided for @ghostMap_conceptToDeepen.
  ///
  /// In en, this message translates to:
  /// **'Concept to deepen'**
  String get ghostMap_conceptToDeepen;

  /// No description provided for @ghostMap_whatIsMissing.
  ///
  /// In en, this message translates to:
  /// **'What\'s missing here?'**
  String get ghostMap_whatIsMissing;

  /// No description provided for @ghostMap_typeText.
  ///
  /// In en, this message translates to:
  /// **'Type text'**
  String get ghostMap_typeText;

  /// No description provided for @ghostMap_drawByHand.
  ///
  /// In en, this message translates to:
  /// **'Draw by hand'**
  String get ghostMap_drawByHand;

  /// No description provided for @ghostMap_rewriteCorrectConcept.
  ///
  /// In en, this message translates to:
  /// **'Rewrite the correct concept...'**
  String get ghostMap_rewriteCorrectConcept;

  /// No description provided for @ghostMap_writeMissingConcept.
  ///
  /// In en, this message translates to:
  /// **'Write the concept you think is missing...'**
  String get ghostMap_writeMissingConcept;

  /// No description provided for @ghostMap_drawHereHint.
  ///
  /// In en, this message translates to:
  /// **'Draw here with your finger or pen ✍️'**
  String get ghostMap_drawHereHint;

  /// No description provided for @ghostMap_reveal.
  ///
  /// In en, this message translates to:
  /// **'Reveal'**
  String get ghostMap_reveal;

  /// No description provided for @ghostMap_revealCountdown.
  ///
  /// In en, this message translates to:
  /// **'Reveal ({seconds}s)'**
  String ghostMap_revealCountdown(int seconds);

  /// No description provided for @ghostMap_compare.
  ///
  /// In en, this message translates to:
  /// **'Compare'**
  String get ghostMap_compare;

  /// No description provided for @ghostMap_recognizing.
  ///
  /// In en, this message translates to:
  /// **'Recognizing…'**
  String get ghostMap_recognizing;

  /// No description provided for @ghostMap_ignoreNode.
  ///
  /// In en, this message translates to:
  /// **'Ignore this node'**
  String get ghostMap_ignoreNode;

  /// No description provided for @ghostMap_nodeIgnored.
  ///
  /// In en, this message translates to:
  /// **'🗺️ Node ignored'**
  String get ghostMap_nodeIgnored;

  /// No description provided for @ghostMap_undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get ghostMap_undo;

  /// No description provided for @ghostMap_hypercorrectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Hypercorrection detected'**
  String get ghostMap_hypercorrectionTitle;

  /// No description provided for @ghostMap_correctAttempt.
  ///
  /// In en, this message translates to:
  /// **'Great! You were close!'**
  String get ghostMap_correctAttempt;

  /// No description provided for @ghostMap_incorrectAttempt.
  ///
  /// In en, this message translates to:
  /// **'Here\'s what was missing'**
  String get ghostMap_incorrectAttempt;

  /// No description provided for @ghostMap_selfEvalQuestion.
  ///
  /// In en, this message translates to:
  /// **'Was your answer correct?'**
  String get ghostMap_selfEvalQuestion;

  /// No description provided for @ghostMap_selfEvalNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get ghostMap_selfEvalNo;

  /// No description provided for @ghostMap_selfEvalYes.
  ///
  /// In en, this message translates to:
  /// **'Yes!'**
  String get ghostMap_selfEvalYes;

  /// No description provided for @ghostMap_connectionToReview.
  ///
  /// In en, this message translates to:
  /// **'Connection to review'**
  String get ghostMap_connectionToReview;

  /// No description provided for @ghostMap_belowZPD.
  ///
  /// In en, this message translates to:
  /// **'To deepen (outside ZPD)'**
  String get ghostMap_belowZPD;

  /// No description provided for @ghostMap_excellentMastery.
  ///
  /// In en, this message translates to:
  /// **'Excellent — Mastery!'**
  String get ghostMap_excellentMastery;

  /// No description provided for @ghostMap_wellDone.
  ///
  /// In en, this message translates to:
  /// **'Well done!'**
  String get ghostMap_wellDone;

  /// No description provided for @ghostMap_weakPoint.
  ///
  /// In en, this message translates to:
  /// **'Weak point detected'**
  String get ghostMap_weakPoint;

  /// No description provided for @ghostMap_progressExplored.
  ///
  /// In en, this message translates to:
  /// **'{revealed}/{total} gaps explored'**
  String ghostMap_progressExplored(int revealed, int total);

  /// No description provided for @ghostMap_closeGhostMap.
  ///
  /// In en, this message translates to:
  /// **'Close Ghost Map'**
  String get ghostMap_closeGhostMap;

  /// No description provided for @ghostMap_showMoreGaps.
  ///
  /// In en, this message translates to:
  /// **'Show more gaps'**
  String get ghostMap_showMoreGaps;

  /// No description provided for @ghostMap_ocrFailed.
  ///
  /// In en, this message translates to:
  /// **'Handwriting recognition failed'**
  String get ghostMap_ocrFailed;

  /// No description provided for @ghostMap_hypercorrectionExplanation.
  ///
  /// In en, this message translates to:
  /// **'⚡ You were very confident but got it wrong in the quiz. This \"cognitive shock\" makes the correction 3× more effective! Try writing the correct concept.'**
  String get ghostMap_hypercorrectionExplanation;

  /// No description provided for @ghostMap_writeAtLeastTwoGroups.
  ///
  /// In en, this message translates to:
  /// **'Write at least 2 note groups for the Ghost Map 🗺️'**
  String get ghostMap_writeAtLeastTwoGroups;

  /// No description provided for @ghostMap_trySocraticFirst.
  ///
  /// In en, this message translates to:
  /// **'Try questioning your notes first!'**
  String get ghostMap_trySocraticFirst;

  /// No description provided for @ghostMap_belowZPDExplanation.
  ///
  /// In en, this message translates to:
  /// **'📚 This concept is beyond your current development zone. Focus on prerequisites first — you\'ll come back to it later.'**
  String get ghostMap_belowZPDExplanation;

  /// No description provided for @ghostMap_dismissGuidanceExcellent.
  ///
  /// In en, this message translates to:
  /// **'✍️ Great work! Now add the discovered concepts to your canvas — writing them by hand will consolidate them in memory.'**
  String get ghostMap_dismissGuidanceExcellent;

  /// No description provided for @ghostMap_dismissGuidanceGood.
  ///
  /// In en, this message translates to:
  /// **'✍️ Now integrate what you discovered into the canvas. Every concept written by hand strengthens the memory trace.'**
  String get ghostMap_dismissGuidanceGood;

  /// No description provided for @ghostMap_dismissGuidanceDefault.
  ///
  /// In en, this message translates to:
  /// **'✍️ Keep writing — Atlas is dormant. The canvas is all yours now.'**
  String get ghostMap_dismissGuidanceDefault;

  /// No description provided for @ghostMap_proceedAnyway.
  ///
  /// In en, this message translates to:
  /// **'Proceed anyway'**
  String get ghostMap_proceedAnyway;

  /// No description provided for @ghostMap_tapToAttempt.
  ///
  /// In en, this message translates to:
  /// **'Tap to attempt'**
  String get ghostMap_tapToAttempt;

  /// No description provided for @ghostMap_hypercorrectionLabel.
  ///
  /// In en, this message translates to:
  /// **'Hypercorrection — you were sure!'**
  String get ghostMap_hypercorrectionLabel;

  /// No description provided for @ghostMap_belowZPDLabel.
  ///
  /// In en, this message translates to:
  /// **'To deepen later'**
  String get ghostMap_belowZPDLabel;

  /// No description provided for @ghostMap_loadingAnalyzing.
  ///
  /// In en, this message translates to:
  /// **'🌌 Atlas is analyzing your notes...'**
  String get ghostMap_loadingAnalyzing;

  /// No description provided for @ghostMap_penModeHint.
  ///
  /// In en, this message translates to:
  /// **'Use the keyboard button to type text as an alternative'**
  String get ghostMap_penModeHint;

  /// No description provided for @ghostMap_ocrFallbackMessage.
  ///
  /// In en, this message translates to:
  /// **'✍️ Handwriting not recognized. Try writing more clearly or use text.'**
  String get ghostMap_ocrFallbackMessage;

  /// No description provided for @ghostMap_atlasAnswer.
  ///
  /// In en, this message translates to:
  /// **'🎯 Atlas\'s answer'**
  String get ghostMap_atlasAnswer;

  /// No description provided for @ghostMap_sleepConsolidation.
  ///
  /// In en, this message translates to:
  /// **'🌙 Your canvas has grown. Now rest — sleep will consolidate everything.'**
  String get ghostMap_sleepConsolidation;

  /// No description provided for @ghostMap_retryHint.
  ///
  /// In en, this message translates to:
  /// **'🔄 Retrying...'**
  String get ghostMap_retryHint;

  /// No description provided for @ghostMap_emptyResultError.
  ///
  /// In en, this message translates to:
  /// **'Not enough content found for the Ghost Map.'**
  String get ghostMap_emptyResultError;

  /// No description provided for @ghostMap_edgeCaseNearlyPerfect.
  ///
  /// In en, this message translates to:
  /// **'🌟 Your canvas is almost complete! Just a few details to add.'**
  String get ghostMap_edgeCaseNearlyPerfect;

  /// No description provided for @ghostMap_edgeCaseVeryIncomplete.
  ///
  /// In en, this message translates to:
  /// **'📖 I found several areas to explore. Let\'s start with the basics.'**
  String get ghostMap_edgeCaseVeryIncomplete;

  /// No description provided for @ghostMap_activationGapsFound.
  ///
  /// In en, this message translates to:
  /// **'{count} gaps found'**
  String ghostMap_activationGapsFound(Object count);

  /// No description provided for @ghostMap_activationConfirmed.
  ///
  /// In en, this message translates to:
  /// **'{count} confirmed ✅'**
  String ghostMap_activationConfirmed(Object count);

  /// No description provided for @ghostMap_activationHypercorrections.
  ///
  /// In en, this message translates to:
  /// **'{count} hypercorrections ⚡'**
  String ghostMap_activationHypercorrections(Object count);

  /// No description provided for @ghostMap_confidenceLevel.
  ///
  /// In en, this message translates to:
  /// **'Confidence: {level}/5'**
  String ghostMap_confidenceLevel(Object level);

  /// No description provided for @ghostMap_growthSuffix.
  ///
  /// In en, this message translates to:
  /// **' — Growth: {percent}%'**
  String ghostMap_growthSuffix(Object percent);

  /// No description provided for @ghostMap_rateLimitWait.
  ///
  /// In en, this message translates to:
  /// **'Wait {seconds}s before regenerating.'**
  String ghostMap_rateLimitWait(Object seconds);

  /// No description provided for @ghostMap_summaryCorrect.
  ///
  /// In en, this message translates to:
  /// **'✅ {count} correct'**
  String ghostMap_summaryCorrect(Object count);

  /// No description provided for @ghostMap_summaryWeak.
  ///
  /// In en, this message translates to:
  /// **'⚠️ {count} to improve'**
  String ghostMap_summaryWeak(Object count);

  /// No description provided for @ghostMap_summaryMissing.
  ///
  /// In en, this message translates to:
  /// **'❓ {count} missing'**
  String ghostMap_summaryMissing(Object count);

  /// No description provided for @ghostMap_summaryGrowth.
  ///
  /// In en, this message translates to:
  /// **'📈 {percent}% gaps filled'**
  String ghostMap_summaryGrowth(Object percent);

  /// No description provided for @ghostMap_summaryAttempts.
  ///
  /// In en, this message translates to:
  /// **'🎯 {correct}/{total} attempts succeeded'**
  String ghostMap_summaryAttempts(Object correct, Object total);

  /// No description provided for @ghostMap_activationHeader.
  ///
  /// In en, this message translates to:
  /// **'🗺️ Ghost Map active — {details}'**
  String ghostMap_activationHeader(Object details);

  /// No description provided for @ghostMap_errorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Error: {message}'**
  String ghostMap_errorGeneric(Object message);

  /// No description provided for @ghostMap_yourAttempt.
  ///
  /// In en, this message translates to:
  /// **'✍️ Your attempt'**
  String get ghostMap_yourAttempt;

  /// No description provided for @recall_modeFree.
  ///
  /// In en, this message translates to:
  /// **'🧠 Free mode'**
  String get recall_modeFree;

  /// No description provided for @recall_modeSpatial.
  ///
  /// In en, this message translates to:
  /// **'📍 With hints'**
  String get recall_modeSpatial;

  /// No description provided for @recall_counter.
  ///
  /// In en, this message translates to:
  /// **'Rebuilt: {recalled} · Original: ~{total}'**
  String recall_counter(int recalled, int total);

  /// No description provided for @recall_hints.
  ///
  /// In en, this message translates to:
  /// **'Hints'**
  String get recall_hints;

  /// No description provided for @recall_exit.
  ///
  /// In en, this message translates to:
  /// **'Exit'**
  String get recall_exit;

  /// No description provided for @recall_showComparison.
  ///
  /// In en, this message translates to:
  /// **'Done, show comparison'**
  String get recall_showComparison;

  /// No description provided for @recall_gapCounter.
  ///
  /// In en, this message translates to:
  /// **'{current} / {total} to review'**
  String recall_gapCounter(int current, int total);

  /// No description provided for @recall_noGaps.
  ///
  /// In en, this message translates to:
  /// **'🎉 No gaps!'**
  String get recall_noGaps;

  /// No description provided for @recall_viewComparison.
  ///
  /// In en, this message translates to:
  /// **'Comparison'**
  String get recall_viewComparison;

  /// No description provided for @recall_viewAttempt.
  ///
  /// In en, this message translates to:
  /// **'Attempt'**
  String get recall_viewAttempt;

  /// No description provided for @recall_summary.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get recall_summary;

  /// No description provided for @recall_statRecalled.
  ///
  /// In en, this message translates to:
  /// **'✅ Recalled'**
  String get recall_statRecalled;

  /// No description provided for @recall_statToReview.
  ///
  /// In en, this message translates to:
  /// **'📋 To review'**
  String get recall_statToReview;

  /// No description provided for @recall_statPeeked.
  ///
  /// In en, this message translates to:
  /// **'👁️ Peeked'**
  String get recall_statPeeked;

  /// No description provided for @recall_levelBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Breakdown by level'**
  String get recall_levelBreakdown;

  /// No description provided for @recall_startSocratic.
  ///
  /// In en, this message translates to:
  /// **'🎓 Start Socratic Questioning'**
  String get recall_startSocratic;

  /// No description provided for @recall_retry.
  ///
  /// In en, this message translates to:
  /// **'🔄 Retry'**
  String get recall_retry;

  /// No description provided for @recall_close.
  ///
  /// In en, this message translates to:
  /// **'✓ Close'**
  String get recall_close;

  /// No description provided for @recall_deleteReconstruction.
  ///
  /// In en, this message translates to:
  /// **'🧹 Delete attempt from canvas'**
  String get recall_deleteReconstruction;

  /// No description provided for @recall_deltaPositive.
  ///
  /// In en, this message translates to:
  /// **'+{count} nodes vs last time!'**
  String recall_deltaPositive(int count);

  /// No description provided for @recall_deltaNeutral.
  ///
  /// In en, this message translates to:
  /// **'Same result — consistency!'**
  String get recall_deltaNeutral;

  /// No description provided for @recall_deltaNegative.
  ///
  /// In en, this message translates to:
  /// **'A few nodes fewer — it happens!'**
  String get recall_deltaNegative;

  /// No description provided for @recall_summaryText.
  ///
  /// In en, this message translates to:
  /// **'You rebuilt {recalled} of {total} nodes from memory!'**
  String recall_summaryText(int recalled, int total);

  /// No description provided for @recall_peekHint.
  ///
  /// In en, this message translates to:
  /// **'Maybe this topic needs another read 📖'**
  String get recall_peekHint;

  /// No description provided for @recall_selectZone.
  ///
  /// In en, this message translates to:
  /// **'📐 Select the zone to review'**
  String get recall_selectZone;

  /// No description provided for @recall_selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get recall_selectAll;

  /// No description provided for @recall_nodesInZone.
  ///
  /// In en, this message translates to:
  /// **'{count} nodes in zone'**
  String recall_nodesInZone(int count);

  /// No description provided for @recall_startReconstruction.
  ///
  /// In en, this message translates to:
  /// **'Start reconstruction'**
  String get recall_startReconstruction;

  /// No description provided for @recall_notEnoughNodes.
  ///
  /// In en, this message translates to:
  /// **'Need at least 5 nodes to start (found {count})'**
  String recall_notEnoughNodes(int count);

  /// No description provided for @recall_noContent.
  ///
  /// In en, this message translates to:
  /// **'No content in this zone'**
  String get recall_noContent;

  /// No description provided for @recall_modeDescFree.
  ///
  /// In en, this message translates to:
  /// **'Blank canvas'**
  String get recall_modeDescFree;

  /// No description provided for @recall_modeDescSpatial.
  ///
  /// In en, this message translates to:
  /// **'Silhouettes visible'**
  String get recall_modeDescSpatial;

  /// No description provided for @recall_infoSwitchHint.
  ///
  /// In en, this message translates to:
  /// **'You can switch to hint mode anytime by pressing \"Hints\".'**
  String get recall_infoSwitchHint;

  /// No description provided for @recall_infoPeekHint.
  ///
  /// In en, this message translates to:
  /// **'You can peek at a node with a long-press (progressively shorter).'**
  String get recall_infoPeekHint;

  /// No description provided for @recall_infoFreeExplanation.
  ///
  /// In en, this message translates to:
  /// **'Free mode is the most powerful study technique. Trying to remember without hints creates \"desirable difficulties\" that strengthen neural connections up to 3× more than re-reading.'**
  String get recall_infoFreeExplanation;

  /// No description provided for @recall_infoSpatialExplanation.
  ///
  /// In en, this message translates to:
  /// **'Hint mode leverages spatial memory: the brain remembers information better when it can associate it with a physical position. Silhouettes give you a visual anchor without revealing the content.'**
  String get recall_infoSpatialExplanation;

  /// No description provided for @celebration_solid.
  ///
  /// In en, this message translates to:
  /// **'Solid.'**
  String get celebration_solid;

  /// No description provided for @celebration_firstRecall.
  ///
  /// In en, this message translates to:
  /// **'The first memory is the most important.'**
  String get celebration_firstRecall;

  /// No description provided for @recall_levelPeeked.
  ///
  /// In en, this message translates to:
  /// **'Peeked'**
  String get recall_levelPeeked;

  /// No description provided for @recall_levelMissed.
  ///
  /// In en, this message translates to:
  /// **'Not remembered'**
  String get recall_levelMissed;

  /// No description provided for @recall_levelTipOfTongue.
  ///
  /// In en, this message translates to:
  /// **'Tip of the tongue'**
  String get recall_levelTipOfTongue;

  /// No description provided for @recall_levelPartial.
  ///
  /// In en, this message translates to:
  /// **'Partial'**
  String get recall_levelPartial;

  /// No description provided for @recall_levelSubstantial.
  ///
  /// In en, this message translates to:
  /// **'Substantial'**
  String get recall_levelSubstantial;

  /// No description provided for @recall_levelPerfect.
  ///
  /// In en, this message translates to:
  /// **'Perfect'**
  String get recall_levelPerfect;

  /// No description provided for @recall_zoneOriginal.
  ///
  /// In en, this message translates to:
  /// **'📄 Original'**
  String get recall_zoneOriginal;

  /// No description provided for @recall_zoneAttempt.
  ///
  /// In en, this message translates to:
  /// **'Attempt'**
  String get recall_zoneAttempt;

  /// No description provided for @recall_reconstructFromMemory.
  ///
  /// In en, this message translates to:
  /// **'Reconstruct from memory'**
  String get recall_reconstructFromMemory;

  /// No description provided for @recall_difficultyHigh.
  ///
  /// In en, this message translates to:
  /// **'High difficulty'**
  String get recall_difficultyHigh;

  /// No description provided for @recall_difficultyMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium difficulty'**
  String get recall_difficultyMedium;

  /// No description provided for @recall_howItWorks.
  ///
  /// In en, this message translates to:
  /// **'How it works:'**
  String get recall_howItWorks;

  /// No description provided for @recall_infoFreeBlank.
  ///
  /// In en, this message translates to:
  /// **'The canvas becomes completely blank — no visual hints.'**
  String get recall_infoFreeBlank;

  /// No description provided for @recall_infoSpatialBlobs.
  ///
  /// In en, this message translates to:
  /// **'Node positions appear as blurred colored silhouettes.'**
  String get recall_infoSpatialBlobs;

  /// No description provided for @recall_infoRewrite.
  ///
  /// In en, this message translates to:
  /// **'Rewrite the content from memory, in the position you remember.'**
  String get recall_infoRewrite;

  /// No description provided for @recall_infoComparisonEnd.
  ///
  /// In en, this message translates to:
  /// **'At the end, you\'ll see a visual comparison between original and reconstruction.'**
  String get recall_infoComparisonEnd;

  /// No description provided for @socratic_needNotes.
  ///
  /// In en, this message translates to:
  /// **'Write something on the canvas first 🔶'**
  String get socratic_needNotes;

  /// No description provided for @socratic_sessionStarted.
  ///
  /// In en, this message translates to:
  /// **'🔶 Quiz started — {count} questions'**
  String socratic_sessionStarted(int count);

  /// No description provided for @socratic_sessionComplete.
  ///
  /// In en, this message translates to:
  /// **'Session complete'**
  String get socratic_sessionComplete;

  /// No description provided for @socratic_closeSession.
  ///
  /// In en, this message translates to:
  /// **'Close and return to canvas'**
  String get socratic_closeSession;

  /// No description provided for @socratic_endSession.
  ///
  /// In en, this message translates to:
  /// **'End Quiz'**
  String get socratic_endSession;

  /// No description provided for @socratic_activeIndicator.
  ///
  /// In en, this message translates to:
  /// **'Quiz active'**
  String get socratic_activeIndicator;

  /// No description provided for @socratic_generatingOCR.
  ///
  /// In en, this message translates to:
  /// **'Recognizing text…'**
  String get socratic_generatingOCR;

  /// No description provided for @socratic_generatingQuestions.
  ///
  /// In en, this message translates to:
  /// **'Generating questions…'**
  String get socratic_generatingQuestions;

  /// No description provided for @socratic_generatingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Generating questions calibrated to your development zone'**
  String get socratic_generatingSubtitle;

  /// No description provided for @socratic_confidencePrompt.
  ///
  /// In en, this message translates to:
  /// **'How confident are you? (1-5)'**
  String get socratic_confidencePrompt;

  /// No description provided for @socratic_selfEvalPrompt.
  ///
  /// In en, this message translates to:
  /// **'Think about the answer, then evaluate yourself honestly:'**
  String get socratic_selfEvalPrompt;

  /// No description provided for @socratic_selfEvalWrong.
  ///
  /// In en, this message translates to:
  /// **'❌ Didn\'t know'**
  String get socratic_selfEvalWrong;

  /// No description provided for @socratic_selfEvalCorrect.
  ///
  /// In en, this message translates to:
  /// **'✅ Knew it'**
  String get socratic_selfEvalCorrect;

  /// No description provided for @socratic_breadcrumbFirst.
  ///
  /// In en, this message translates to:
  /// **'Hint'**
  String get socratic_breadcrumbFirst;

  /// No description provided for @socratic_breadcrumbSecond.
  ///
  /// In en, this message translates to:
  /// **'Another hint'**
  String get socratic_breadcrumbSecond;

  /// No description provided for @socratic_breadcrumbThird.
  ///
  /// In en, this message translates to:
  /// **'Last hint'**
  String get socratic_breadcrumbThird;

  /// No description provided for @socratic_breadcrumbExhausted.
  ///
  /// In en, this message translates to:
  /// **'No more hints'**
  String get socratic_breadcrumbExhausted;

  /// No description provided for @socratic_next.
  ///
  /// In en, this message translates to:
  /// **'Next →'**
  String get socratic_next;

  /// No description provided for @socratic_sessionEnd.
  ///
  /// In en, this message translates to:
  /// **'End session'**
  String get socratic_sessionEnd;

  /// No description provided for @socratic_feedbackSolidTitle.
  ///
  /// In en, this message translates to:
  /// **'Solid!'**
  String get socratic_feedbackSolidTitle;

  /// No description provided for @socratic_feedbackSolidMsg.
  ///
  /// In en, this message translates to:
  /// **'Your memory is stable. Keep it up.'**
  String get socratic_feedbackSolidMsg;

  /// No description provided for @socratic_feedbackUnderestimatedTitle.
  ///
  /// In en, this message translates to:
  /// **'You knew more than you thought!'**
  String get socratic_feedbackUnderestimatedTitle;

  /// No description provided for @socratic_feedbackUnderestimatedMsg.
  ///
  /// In en, this message translates to:
  /// **'Your confidence was {conf}/5, but you answered correctly. This concept is more solid than you think — trust your memory more.'**
  String socratic_feedbackUnderestimatedMsg(int conf);

  /// No description provided for @socratic_feedbackKnownGapTitle.
  ///
  /// In en, this message translates to:
  /// **'Known gap'**
  String get socratic_feedbackKnownGapTitle;

  /// No description provided for @socratic_feedbackKnownGapMsg.
  ///
  /// In en, this message translates to:
  /// **'You knew you didn\'t know — that\'s already awareness. Review your notes on this topic and it\'ll come back.'**
  String get socratic_feedbackKnownGapMsg;

  /// No description provided for @socratic_feedbackHypercorrectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Learning moment!'**
  String get socratic_feedbackHypercorrectionTitle;

  /// No description provided for @socratic_feedbackHypercorrectionMsg.
  ///
  /// In en, this message translates to:
  /// **'You were {conf}/5 confident, but there\'s something to review. Research shows that high-confidence errors are corrected BETTER — this moment is worth twice as much. Carefully review your notes.'**
  String socratic_feedbackHypercorrectionMsg(int conf);

  /// No description provided for @socratic_feedbackSkippedTitle.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get socratic_feedbackSkippedTitle;

  /// No description provided for @socratic_feedbackBelowZPDTitle.
  ///
  /// In en, this message translates to:
  /// **'Outside your zone'**
  String get socratic_feedbackBelowZPDTitle;

  /// No description provided for @socratic_feedbackBelowZPDMsg.
  ///
  /// In en, this message translates to:
  /// **'This question was out of range. It\'ll come back when you\'re ready.'**
  String get socratic_feedbackBelowZPDMsg;

  /// No description provided for @socratic_summaryCorrect.
  ///
  /// In en, this message translates to:
  /// **'Correct'**
  String get socratic_summaryCorrect;

  /// No description provided for @socratic_summaryWrong.
  ///
  /// In en, this message translates to:
  /// **'Wrong'**
  String get socratic_summaryWrong;

  /// No description provided for @socratic_summaryHypercorrections.
  ///
  /// In en, this message translates to:
  /// **'Hypercorrections'**
  String get socratic_summaryHypercorrections;

  /// No description provided for @socratic_summarySkipped.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get socratic_summarySkipped;

  /// No description provided for @socratic_insightHypercorrection.
  ///
  /// In en, this message translates to:
  /// **'⚡ You had {count} hypercorrection moment(s) — these are your most powerful learning points. Carefully review the involved clusters.'**
  String socratic_insightHypercorrection(int count);

  /// No description provided for @socratic_insightPerfect.
  ///
  /// In en, this message translates to:
  /// **'🎯 All correct! Your mastery is solid. The next review intervals will extend.'**
  String get socratic_insightPerfect;

  /// No description provided for @socratic_insightGaps.
  ///
  /// In en, this message translates to:
  /// **'📚 There are several gaps — now is the best time to re-read your notes. Retrieval activated the right circuits, so reinforcement will be more effective now.'**
  String get socratic_insightGaps;

  /// No description provided for @socratic_insightBalanced.
  ///
  /// In en, this message translates to:
  /// **'👍 Good balance between what you know and what needs review. FSRS will update the review intervals for you.'**
  String get socratic_insightBalanced;

  /// No description provided for @socratic_gateMessage.
  ///
  /// In en, this message translates to:
  /// **'You\'ve used your 3 sessions this week. With Pro, AI is always ready when you are. €3.33/month.'**
  String get socratic_gateMessage;

  /// No description provided for @socratic_typeLacuna.
  ///
  /// In en, this message translates to:
  /// **'Gap'**
  String get socratic_typeLacuna;

  /// No description provided for @socratic_typeChallenge.
  ///
  /// In en, this message translates to:
  /// **'Challenge'**
  String get socratic_typeChallenge;

  /// No description provided for @socratic_typeDepth.
  ///
  /// In en, this message translates to:
  /// **'Depth'**
  String get socratic_typeDepth;

  /// No description provided for @socratic_typeTransfer.
  ///
  /// In en, this message translates to:
  /// **'Transfer'**
  String get socratic_typeTransfer;

  /// No description provided for @fow_summaryStandard.
  ///
  /// In en, this message translates to:
  /// **'You recalled {recalled} of {total} nodes. {forgotten} forgotten. {blindSpots} not visited.'**
  String fow_summaryStandard(
    int recalled,
    int total,
    int forgotten,
    int blindSpots,
  );

  /// No description provided for @fow_summarySlowRecall.
  ///
  /// In en, this message translates to:
  /// **'⏱️ {count} with slow recall (>8s) — fragile consolidation.'**
  String fow_summarySlowRecall(int count);

  /// No description provided for @fow_muroRossoNodesYours.
  ///
  /// In en, this message translates to:
  /// **'✅ {count} nodes are solid'**
  String fow_muroRossoNodesYours(int count);

  /// No description provided for @fow_muroRossoPreciseZones.
  ///
  /// In en, this message translates to:
  /// **'🎯 You identified {count} precise zones to strengthen'**
  String fow_muroRossoPreciseZones(int count);

  /// No description provided for @fow_muroRossoNowYouKnow.
  ///
  /// In en, this message translates to:
  /// **'Now you know exactly where to work'**
  String get fow_muroRossoNowYouKnow;

  /// No description provided for @fow_muroRossoCoaching.
  ///
  /// In en, this message translates to:
  /// **'💡 Try rewriting from memory the concepts that felt most familiar — the Generation Effect will strengthen your memory trace.'**
  String get fow_muroRossoCoaching;

  /// No description provided for @fow_fogLevelLight.
  ///
  /// In en, this message translates to:
  /// **'Light Fog'**
  String get fow_fogLevelLight;

  /// No description provided for @fow_fogLevelMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium Fog'**
  String get fow_fogLevelMedium;

  /// No description provided for @fow_fogLevelTotal.
  ///
  /// In en, this message translates to:
  /// **'Total Fog'**
  String get fow_fogLevelTotal;

  /// No description provided for @fow_selfEval1.
  ///
  /// In en, this message translates to:
  /// **'Didn\'t remember'**
  String get fow_selfEval1;

  /// No description provided for @fow_selfEval2.
  ///
  /// In en, this message translates to:
  /// **'Vaguely'**
  String get fow_selfEval2;

  /// No description provided for @fow_selfEval3.
  ///
  /// In en, this message translates to:
  /// **'Partially'**
  String get fow_selfEval3;

  /// No description provided for @fow_selfEval4.
  ///
  /// In en, this message translates to:
  /// **'Well'**
  String get fow_selfEval4;

  /// No description provided for @fow_selfEval5.
  ///
  /// In en, this message translates to:
  /// **'Perfectly'**
  String get fow_selfEval5;

  /// No description provided for @fow_selfEvalTitle.
  ///
  /// In en, this message translates to:
  /// **'How much did you remember about this node?'**
  String get fow_selfEvalTitle;

  /// No description provided for @fow_selfEvalSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Evaluate honestly before revealing.'**
  String get fow_selfEvalSubtitle;

  /// No description provided for @fow_selfEvalSelect.
  ///
  /// In en, this message translates to:
  /// **'Select your confidence'**
  String get fow_selfEvalSelect;

  /// No description provided for @fow_selfEvalConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm and reveal'**
  String get fow_selfEvalConfirm;

  /// No description provided for @fow_blindSpotLabel.
  ///
  /// In en, this message translates to:
  /// **'Not searched'**
  String get fow_blindSpotLabel;

  /// No description provided for @fow_endSession.
  ///
  /// In en, this message translates to:
  /// **'End Session'**
  String get fow_endSession;

  /// No description provided for @fow_closeFogOfWar.
  ///
  /// In en, this message translates to:
  /// **'Close Challenge'**
  String get fow_closeFogOfWar;

  /// No description provided for @fow_needAtLeast3.
  ///
  /// In en, this message translates to:
  /// **'Need at least 3 note groups for the Challenge ⚔️'**
  String get fow_needAtLeast3;

  /// No description provided for @fow_fogActive.
  ///
  /// In en, this message translates to:
  /// **'⚔️ Challenge active — {level}'**
  String fow_fogActive(String level);

  /// No description provided for @fow_allNodesDiscovered.
  ///
  /// In en, this message translates to:
  /// **'✅ All nodes have been discovered!'**
  String get fow_allNodesDiscovered;

  /// No description provided for @fow_masteryMapBlindSpot.
  ///
  /// In en, this message translates to:
  /// **'You didn\'t know this node was here'**
  String get fow_masteryMapBlindSpot;

  /// No description provided for @fow_masteryMapForgotten.
  ///
  /// In en, this message translates to:
  /// **'Forgotten concept — now revealed'**
  String get fow_masteryMapForgotten;

  /// No description provided for @fow_surgicalReviewDone.
  ///
  /// In en, this message translates to:
  /// **'✅ All critical nodes reviewed! Review complete.'**
  String get fow_surgicalReviewDone;

  /// No description provided for @fow_surgicalReviewCount.
  ///
  /// In en, this message translates to:
  /// **'🗺️ {visited}/{total} reviewed'**
  String fow_surgicalReviewCount(int visited, int total);

  /// No description provided for @fow_surgicalNext.
  ///
  /// In en, this message translates to:
  /// **'Next →'**
  String get fow_surgicalNext;

  /// No description provided for @fow_surgicalCompleted.
  ///
  /// In en, this message translates to:
  /// **'✅ Completed'**
  String get fow_surgicalCompleted;

  /// No description provided for @fow_surgicalGuideReview.
  ///
  /// In en, this message translates to:
  /// **'🗺️ Review guide'**
  String get fow_surgicalGuideReview;

  /// No description provided for @htr_unavailableOnPlatform.
  ///
  /// In en, this message translates to:
  /// **'Handwriting recognition is not available on this platform. AI features will work with typed text only.'**
  String get htr_unavailableOnPlatform;

  /// No description provided for @tierGate_socraticBlocked.
  ///
  /// In en, this message translates to:
  /// **'You\'ve used your 3 Socratic sessions this week. With Pro, the AI is always ready when you are. €3.33/month.'**
  String get tierGate_socraticBlocked;

  /// No description provided for @tierGate_fogBlocked.
  ///
  /// In en, this message translates to:
  /// **'You\'ve already completed the Challenge for this zone. With Pro, you can repeat without limits.'**
  String get tierGate_fogBlocked;

  /// No description provided for @tierGate_ghostMapBlocked.
  ///
  /// In en, this message translates to:
  /// **'You\'ve already used \"What am I missing?\" this week. With Pro, unlimited comparisons anytime.'**
  String get tierGate_ghostMapBlocked;

  /// No description provided for @tierGate_crossDomainBlocked.
  ///
  /// In en, this message translates to:
  /// **'Cross-domain bridges are view-only on the Free plan. With Pro, you can create interactive bridges.'**
  String get tierGate_crossDomainBlocked;

  /// No description provided for @tierGate_deepReviewBlocked.
  ///
  /// In en, this message translates to:
  /// **'You\'ve already completed today\'s deep review. With Pro, unlimited deep reviews.'**
  String get tierGate_deepReviewBlocked;

  /// No description provided for @tierGate_brushBlocked.
  ///
  /// In en, this message translates to:
  /// **'You\'re using the 3 basic brushes on the Free plan. With Pro, unlock all professional brushes.'**
  String get tierGate_brushBlocked;

  /// No description provided for @tierGate_exportBlocked.
  ///
  /// In en, this message translates to:
  /// **'The Free plan exports only to PNG. With Pro, export to PDF, SVG, and all formats.'**
  String get tierGate_exportBlocked;

  /// No description provided for @socraticInfo_title.
  ///
  /// In en, this message translates to:
  /// **'Socratic Method'**
  String get socraticInfo_title;

  /// No description provided for @socraticInfo_heroTitle.
  ///
  /// In en, this message translates to:
  /// **'The Socratic Interrogation'**
  String get socraticInfo_heroTitle;

  /// No description provided for @socraticInfo_heroBody.
  ///
  /// In en, this message translates to:
  /// **'Fluera analyzes your handwritten notes and generates questions calibrated to your zone of proximal development (ZPD). It doesn\'t give you answers — it guides you to find them yourself.'**
  String get socraticInfo_heroBody;

  /// No description provided for @socraticInfo_whyItWorks.
  ///
  /// In en, this message translates to:
  /// **'The cognitive value lies in the ATTEMPT at retrieval, not in the correct answer. Even a high-confidence error (hypercorrection) is a powerful learning moment.'**
  String get socraticInfo_whyItWorks;

  /// No description provided for @socraticInfo_howItWorks.
  ///
  /// In en, this message translates to:
  /// **'How it works'**
  String get socraticInfo_howItWorks;

  /// No description provided for @socraticInfo_typeLacunaTitle.
  ///
  /// In en, this message translates to:
  /// **'Gap'**
  String get socraticInfo_typeLacunaTitle;

  /// No description provided for @socraticInfo_typeLacunaSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Recall 1-2'**
  String get socraticInfo_typeLacunaSubtitle;

  /// No description provided for @socraticInfo_typeLacunaBody.
  ///
  /// In en, this message translates to:
  /// **'Creates a \"cognitive gap\" you feel the need to fill. Asks what CONNECTS two concepts or what\'s MISSING.'**
  String get socraticInfo_typeLacunaBody;

  /// No description provided for @socraticInfo_typeLacunaPrinciple.
  ///
  /// In en, this message translates to:
  /// **'Zeigarnik Effect + Active Recall'**
  String get socraticInfo_typeLacunaPrinciple;

  /// No description provided for @socraticInfo_typeChallengeTitle.
  ///
  /// In en, this message translates to:
  /// **'Challenge'**
  String get socraticInfo_typeChallengeTitle;

  /// No description provided for @socraticInfo_typeChallengeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Recall 3'**
  String get socraticInfo_typeChallengeSubtitle;

  /// No description provided for @socraticInfo_typeChallengeBody.
  ///
  /// In en, this message translates to:
  /// **'Presents a counterexample to challenge you. Forces you to DEFEND or REVISE your understanding.'**
  String get socraticInfo_typeChallengeBody;

  /// No description provided for @socraticInfo_typeChallengePrinciple.
  ///
  /// In en, this message translates to:
  /// **'Desirable Difficulties (Bjork)'**
  String get socraticInfo_typeChallengePrinciple;

  /// No description provided for @socraticInfo_typeDepthTitle.
  ///
  /// In en, this message translates to:
  /// **'Depth'**
  String get socraticInfo_typeDepthTitle;

  /// No description provided for @socraticInfo_typeDepthSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Recall 4'**
  String get socraticInfo_typeDepthSubtitle;

  /// No description provided for @socraticInfo_typeDepthBody.
  ///
  /// In en, this message translates to:
  /// **'Asks for the MECHANISM, the CAUSE, the PRINCIPLE. Shifts from shallow to deep encoding.'**
  String get socraticInfo_typeDepthBody;

  /// No description provided for @socraticInfo_typeDepthPrinciple.
  ///
  /// In en, this message translates to:
  /// **'Levels of Processing (Craik & Lockhart)'**
  String get socraticInfo_typeDepthPrinciple;

  /// No description provided for @socraticInfo_typeTransferTitle.
  ///
  /// In en, this message translates to:
  /// **'Transfer'**
  String get socraticInfo_typeTransferTitle;

  /// No description provided for @socraticInfo_typeTransferSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Recall 5'**
  String get socraticInfo_typeTransferSubtitle;

  /// No description provided for @socraticInfo_typeTransferBody.
  ///
  /// In en, this message translates to:
  /// **'Analogies with OTHER subjects or applications in NEW contexts. Creates bridges between domains to consolidate knowledge.'**
  String get socraticInfo_typeTransferBody;

  /// No description provided for @socraticInfo_typeTransferPrinciple.
  ///
  /// In en, this message translates to:
  /// **'Transfer Learning + Interleaving'**
  String get socraticInfo_typeTransferPrinciple;

  /// No description provided for @socraticInfo_tryConfidence.
  ///
  /// In en, this message translates to:
  /// **'Try the Confidence Scale'**
  String get socraticInfo_tryConfidence;

  /// No description provided for @socraticInfo_spacedRepetition.
  ///
  /// In en, this message translates to:
  /// **'Spaced Repetition (FSRS)'**
  String get socraticInfo_spacedRepetition;

  /// No description provided for @socraticInfo_feedbackMatrix.
  ///
  /// In en, this message translates to:
  /// **'Feedback Matrix'**
  String get socraticInfo_feedbackMatrix;

  /// No description provided for @socraticInfo_references.
  ///
  /// In en, this message translates to:
  /// **'Based on research by Butterfield & Metcalfe (2001),\nBjork (1994), Craik & Lockhart (1972), Vygotsky (1978)'**
  String get socraticInfo_references;

  /// No description provided for @socraticInfo_flowStep1Title.
  ///
  /// In en, this message translates to:
  /// **'Write'**
  String get socraticInfo_flowStep1Title;

  /// No description provided for @socraticInfo_flowStep1Body.
  ///
  /// In en, this message translates to:
  /// **'Take handwritten notes on the canvas'**
  String get socraticInfo_flowStep1Body;

  /// No description provided for @socraticInfo_flowStep2Title.
  ///
  /// In en, this message translates to:
  /// **'Analysis'**
  String get socraticInfo_flowStep2Title;

  /// No description provided for @socraticInfo_flowStep2Body.
  ///
  /// In en, this message translates to:
  /// **'Fluera recognizes the text (OCR) and identifies the subject'**
  String get socraticInfo_flowStep2Body;

  /// No description provided for @socraticInfo_flowStep3Title.
  ///
  /// In en, this message translates to:
  /// **'Question'**
  String get socraticInfo_flowStep3Title;

  /// No description provided for @socraticInfo_flowStep3Body.
  ///
  /// In en, this message translates to:
  /// **'A bubble appears with the Socratic question'**
  String get socraticInfo_flowStep3Body;

  /// No description provided for @socraticInfo_flowStep4Title.
  ///
  /// In en, this message translates to:
  /// **'Confidence'**
  String get socraticInfo_flowStep4Title;

  /// No description provided for @socraticInfo_flowStep4Body.
  ///
  /// In en, this message translates to:
  /// **'You declare how confident you are (1-5)'**
  String get socraticInfo_flowStep4Body;

  /// No description provided for @socraticInfo_flowStep5Title.
  ///
  /// In en, this message translates to:
  /// **'Retrieval'**
  String get socraticInfo_flowStep5Title;

  /// No description provided for @socraticInfo_flowStep5Body.
  ///
  /// In en, this message translates to:
  /// **'You think about the answer mentally'**
  String get socraticInfo_flowStep5Body;

  /// No description provided for @socraticInfo_flowStep6Title.
  ///
  /// In en, this message translates to:
  /// **'Self-evaluation'**
  String get socraticInfo_flowStep6Title;

  /// No description provided for @socraticInfo_flowStep6Body.
  ///
  /// In en, this message translates to:
  /// **'You declare whether you knew or didn\'t know'**
  String get socraticInfo_flowStep6Body;

  /// No description provided for @socraticInfo_flowStep7Title.
  ///
  /// In en, this message translates to:
  /// **'Feedback'**
  String get socraticInfo_flowStep7Title;

  /// No description provided for @socraticInfo_flowStep7Body.
  ///
  /// In en, this message translates to:
  /// **'Personalized insight + FSRS updated'**
  String get socraticInfo_flowStep7Body;

  /// No description provided for @socraticInfo_breadcrumbIntro.
  ///
  /// In en, this message translates to:
  /// **'If you\'re stuck, you can ask for up to 3 progressive hints that guide without revealing:'**
  String get socraticInfo_breadcrumbIntro;

  /// No description provided for @socraticInfo_breadcrumb1Title.
  ///
  /// In en, this message translates to:
  /// **'🌫️ The Distant Echo'**
  String get socraticInfo_breadcrumb1Title;

  /// No description provided for @socraticInfo_breadcrumb1Body.
  ///
  /// In en, this message translates to:
  /// **'Vague direction — activates semantic priming'**
  String get socraticInfo_breadcrumb1Body;

  /// No description provided for @socraticInfo_breadcrumb2Title.
  ///
  /// In en, this message translates to:
  /// **'🛤️ The Path'**
  String get socraticInfo_breadcrumb2Title;

  /// No description provided for @socraticInfo_breadcrumb2Body.
  ///
  /// In en, this message translates to:
  /// **'Narrows the domain — reduces the search space'**
  String get socraticInfo_breadcrumb2Body;

  /// No description provided for @socraticInfo_breadcrumb3Title.
  ///
  /// In en, this message translates to:
  /// **'🚪 The Threshold'**
  String get socraticInfo_breadcrumb3Title;

  /// No description provided for @socraticInfo_breadcrumb3Body.
  ///
  /// In en, this message translates to:
  /// **'Final scaffolding — the answer is one step away'**
  String get socraticInfo_breadcrumb3Body;

  /// No description provided for @socraticInfo_breadcrumbNote.
  ///
  /// In en, this message translates to:
  /// **'The answer is NEVER revealed — not even at level 3.'**
  String get socraticInfo_breadcrumbNote;

  /// No description provided for @socraticInfo_fsrsIntro.
  ///
  /// In en, this message translates to:
  /// **'Every result is saved'**
  String get socraticInfo_fsrsIntro;

  /// No description provided for @socraticInfo_fsrsCorrect.
  ///
  /// In en, this message translates to:
  /// **'Correct'**
  String get socraticInfo_fsrsCorrect;

  /// No description provided for @socraticInfo_fsrsCorrectEffect.
  ///
  /// In en, this message translates to:
  /// **'Interval increases'**
  String get socraticInfo_fsrsCorrectEffect;

  /// No description provided for @socraticInfo_fsrsWrong.
  ///
  /// In en, this message translates to:
  /// **'Wrong'**
  String get socraticInfo_fsrsWrong;

  /// No description provided for @socraticInfo_fsrsWrongEffect.
  ///
  /// In en, this message translates to:
  /// **'Interval decreases'**
  String get socraticInfo_fsrsWrongEffect;

  /// No description provided for @socraticInfo_fsrsHyper.
  ///
  /// In en, this message translates to:
  /// **'Hypercorrection'**
  String get socraticInfo_fsrsHyper;

  /// No description provided for @socraticInfo_fsrsHyperEffect.
  ///
  /// In en, this message translates to:
  /// **'Reduced penalty (shock = learning)'**
  String get socraticInfo_fsrsHyperEffect;

  /// No description provided for @socraticInfo_fsrsHighConf.
  ///
  /// In en, this message translates to:
  /// **'High conf. + correct'**
  String get socraticInfo_fsrsHighConf;

  /// No description provided for @socraticInfo_fsrsHighConfEffect.
  ///
  /// In en, this message translates to:
  /// **'Interval bonus (+30%)'**
  String get socraticInfo_fsrsHighConfEffect;

  /// No description provided for @socraticInfo_matrixIntro.
  ///
  /// In en, this message translates to:
  /// **'Feedback changes based on confidence × correctness:'**
  String get socraticInfo_matrixIntro;

  /// No description provided for @socraticInfo_matrixSolid.
  ///
  /// In en, this message translates to:
  /// **'Knew + High conf.'**
  String get socraticInfo_matrixSolid;

  /// No description provided for @socraticInfo_matrixSolidMsg.
  ///
  /// In en, this message translates to:
  /// **'Solid! The memory is stable.'**
  String get socraticInfo_matrixSolidMsg;

  /// No description provided for @socraticInfo_matrixSurprise.
  ///
  /// In en, this message translates to:
  /// **'Knew + Low conf.'**
  String get socraticInfo_matrixSurprise;

  /// No description provided for @socraticInfo_matrixSurpriseMsg.
  ///
  /// In en, this message translates to:
  /// **'You knew more than you thought!'**
  String get socraticInfo_matrixSurpriseMsg;

  /// No description provided for @socraticInfo_matrixGap.
  ///
  /// In en, this message translates to:
  /// **'Didn\'t know + Low conf.'**
  String get socraticInfo_matrixGap;

  /// No description provided for @socraticInfo_matrixGapMsg.
  ///
  /// In en, this message translates to:
  /// **'Gap identified — review will help.'**
  String get socraticInfo_matrixGapMsg;

  /// No description provided for @socraticInfo_matrixHyper.
  ///
  /// In en, this message translates to:
  /// **'Didn\'t know + High conf.'**
  String get socraticInfo_matrixHyper;

  /// No description provided for @socraticInfo_matrixHyperMsg.
  ///
  /// In en, this message translates to:
  /// **'Hypercorrection! This shock helps you remember.'**
  String get socraticInfo_matrixHyperMsg;

  /// No description provided for @socraticInfo_questionTypes.
  ///
  /// In en, this message translates to:
  /// **'4 question types'**
  String get socraticInfo_questionTypes;

  /// No description provided for @socraticInfo_breadcrumbSection.
  ///
  /// In en, this message translates to:
  /// **'3 Progressive Hints'**
  String get socraticInfo_breadcrumbSection;

  /// No description provided for @socraticInfo_ctaButton.
  ///
  /// In en, this message translates to:
  /// **'Back to canvas — try it!'**
  String get socraticInfo_ctaButton;

  /// No description provided for @socraticInfo_confidencePromptDemo.
  ///
  /// In en, this message translates to:
  /// **'Tap the circles to feel the progressive vibration:'**
  String get socraticInfo_confidencePromptDemo;

  /// No description provided for @socraticInfo_confidenceHigh.
  ///
  /// In en, this message translates to:
  /// **'strong because you declare high confidence'**
  String get socraticInfo_confidenceHigh;

  /// No description provided for @socraticInfo_confidenceMedium.
  ///
  /// In en, this message translates to:
  /// **'medium — uncertain zone'**
  String get socraticInfo_confidenceMedium;

  /// No description provided for @socraticInfo_confidenceLow.
  ///
  /// In en, this message translates to:
  /// **'light — you know you don\'t know'**
  String get socraticInfo_confidenceLow;

  /// No description provided for @socraticInfo_hypercorrectionNote.
  ///
  /// In en, this message translates to:
  /// **'High-confidence errors (⚡ hypercorrection) produce the most LASTING corrections.'**
  String get socraticInfo_hypercorrectionNote;
}

class _FlueraLocalizationsDelegate
    extends LocalizationsDelegate<FlueraLocalizations> {
  const _FlueraLocalizationsDelegate();

  @override
  Future<FlueraLocalizations> load(Locale locale) {
    return SynchronousFuture<FlueraLocalizations>(
      lookupFlueraLocalizations(locale),
    );
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'it'].contains(locale.languageCode);

  @override
  bool shouldReload(_FlueraLocalizationsDelegate old) => false;
}

FlueraLocalizations lookupFlueraLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return FlueraLocalizationsEn();
    case 'it':
      return FlueraLocalizationsIt();
  }

  throw FlutterError(
    'FlueraLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
