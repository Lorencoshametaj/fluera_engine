import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'fluera_localizations_ar.g.dart';
import 'fluera_localizations_da.g.dart';
import 'fluera_localizations_de.g.dart';
import 'fluera_localizations_en.g.dart';
import 'fluera_localizations_es.g.dart';
import 'fluera_localizations_fi.g.dart';
import 'fluera_localizations_fr.g.dart';
import 'fluera_localizations_hi.g.dart';
import 'fluera_localizations_it.g.dart';
import 'fluera_localizations_ja.g.dart';
import 'fluera_localizations_ko.g.dart';
import 'fluera_localizations_nl.g.dart';
import 'fluera_localizations_no.g.dart';
import 'fluera_localizations_pl.g.dart';
import 'fluera_localizations_pt.g.dart';
import 'fluera_localizations_sv.g.dart';

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
    Locale('ar'),
    Locale('da'),
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fi'),
    Locale('fr'),
    Locale('hi'),
    Locale('it'),
    Locale('ja'),
    Locale('ko'),
    Locale('nl'),
    Locale('no'),
    Locale('pl'),
    Locale('pt'),
    Locale('sv'),
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

  /// No description provided for @proCanvas_unlockBrushes.
  ///
  /// In en, this message translates to:
  /// **'Unlock more brushes'**
  String get proCanvas_unlockBrushes;

  /// No description provided for @proCanvas_hideLockedBrushes.
  ///
  /// In en, this message translates to:
  /// **'Hide locked brushes'**
  String get proCanvas_hideLockedBrushes;

  /// No description provided for @proCanvas_brushPreviewTagline.
  ///
  /// In en, this message translates to:
  /// **'Premium brush · preview'**
  String get proCanvas_brushPreviewTagline;

  /// No description provided for @proCanvas_brushPreviewUnlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock with Plus'**
  String get proCanvas_brushPreviewUnlock;

  /// No description provided for @proCanvas_brushPreviewMaybeLater.
  ///
  /// In en, this message translates to:
  /// **'Maybe later'**
  String get proCanvas_brushPreviewMaybeLater;

  /// No description provided for @proCanvas_brushPreviewYourCurrent.
  ///
  /// In en, this message translates to:
  /// **'Your current brush'**
  String get proCanvas_brushPreviewYourCurrent;

  /// No description provided for @proCanvas_brushPreviewThisOne.
  ///
  /// In en, this message translates to:
  /// **'This one'**
  String get proCanvas_brushPreviewThisOne;

  /// No description provided for @canvasSettings_wheelModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Radial brush wheel instead of the flat strip'**
  String get canvasSettings_wheelModeSubtitle;

  /// No description provided for @wheelModeIntro_title.
  ///
  /// In en, this message translates to:
  /// **'Wheel mode'**
  String get wheelModeIntro_title;

  /// No description provided for @wheelModeIntro_lead.
  ///
  /// In en, this message translates to:
  /// **'The toolbar disappears and your brushes live on a radial wheel that opens under your finger.'**
  String get wheelModeIntro_lead;

  /// No description provided for @wheelModeIntro_step1.
  ///
  /// In en, this message translates to:
  /// **'Long-press anywhere on the canvas to summon the wheel.'**
  String get wheelModeIntro_step1;

  /// No description provided for @wheelModeIntro_step2.
  ///
  /// In en, this message translates to:
  /// **'Drag toward a brush to select it, release to commit.'**
  String get wheelModeIntro_step2;

  /// No description provided for @wheelModeIntro_step3.
  ///
  /// In en, this message translates to:
  /// **'Tap the wheel icon in the toolbar again to switch back.'**
  String get wheelModeIntro_step3;

  /// No description provided for @wheelModeIntro_cta.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get wheelModeIntro_cta;

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

  /// No description provided for @pasteWarning_title.
  ///
  /// In en, this message translates to:
  /// **'You\'re pasting text'**
  String get pasteWarning_title;

  /// No description provided for @pasteWarning_body.
  ///
  /// In en, this message translates to:
  /// **'{count} characters pasted. Rewriting them by hand activates the Generation Effect: you encode 10× more deeply than reading prewritten text.'**
  String pasteWarning_body(Object count);

  /// No description provided for @pasteWarning_citation.
  ///
  /// In en, this message translates to:
  /// **'Slamecka & Graf (1978) · Generation Effect'**
  String get pasteWarning_citation;

  /// No description provided for @pasteWarning_rewrite.
  ///
  /// In en, this message translates to:
  /// **'Rewrite by hand'**
  String get pasteWarning_rewrite;

  /// No description provided for @pasteWarning_pasteAnyway.
  ///
  /// In en, this message translates to:
  /// **'Paste anyway'**
  String get pasteWarning_pasteAnyway;

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
  /// **'Which fragment fits here?'**
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
  /// **'Write the fragment you think fits here...'**
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
  /// **'Node ignored'**
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
  /// **'Here\'s the fragment that completes the picture'**
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

  /// No description provided for @ghostMap_selfEvalRecordedNo.
  ///
  /// In en, this message translates to:
  /// **'The effort you put in matters — this concept will come back stronger in your reviews.'**
  String get ghostMap_selfEvalRecordedNo;

  /// No description provided for @ghostMap_selfEvalRecordedYes.
  ///
  /// In en, this message translates to:
  /// **'Your effort on this concept paid off. Keep building.'**
  String get ghostMap_selfEvalRecordedYes;

  /// No description provided for @ghostMap_nowWriteThis.
  ///
  /// In en, this message translates to:
  /// **'Now write this on your canvas:'**
  String get ghostMap_nowWriteThis;

  /// No description provided for @ghostMap_iWroteIt.
  ///
  /// In en, this message translates to:
  /// **'I wrote it ✓'**
  String get ghostMap_iWroteIt;

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
  /// **'Fragment to consolidate'**
  String get ghostMap_weakPoint;

  /// No description provided for @ghostMap_progressExplored.
  ///
  /// In en, this message translates to:
  /// **'{revealed}/{total} fragments explored'**
  String ghostMap_progressExplored(int revealed, int total);

  /// No description provided for @ghostMap_closeGhostMap.
  ///
  /// In en, this message translates to:
  /// **'Close concept map'**
  String get ghostMap_closeGhostMap;

  /// No description provided for @ghostMap_showMoreGaps.
  ///
  /// In en, this message translates to:
  /// **'Show more fragments'**
  String get ghostMap_showMoreGaps;

  /// No description provided for @ghostMap_ocrFailed.
  ///
  /// In en, this message translates to:
  /// **'Handwriting recognition failed'**
  String get ghostMap_ocrFailed;

  /// No description provided for @ghostMap_hypercorrectionExplanation.
  ///
  /// In en, this message translates to:
  /// **'⚡ You were very confident on a fragment that needs recontextualizing. This \"cognitive shock\" makes the integration 3× more effective! Try writing how the concept fits.'**
  String get ghostMap_hypercorrectionExplanation;

  /// No description provided for @ghostMap_writeAtLeastTwoGroups.
  ///
  /// In en, this message translates to:
  /// **'Write at least 2 note groups for the concept map.'**
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
  /// **'Keep writing — the AI is dormant. The canvas is all yours.'**
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
  /// **'Analyzing your notes…'**
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
  /// **'According to the AI (verify!)'**
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
  /// **'Not enough content found for the concept map.'**
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
  /// **'{count} fragments to discover'**
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
  /// **'❓ {count} to discover'**
  String ghostMap_summaryMissing(Object count);

  /// No description provided for @ghostMap_summaryGrowth.
  ///
  /// In en, this message translates to:
  /// **'📈 {percent}% fragments integrated'**
  String ghostMap_summaryGrowth(Object percent);

  /// No description provided for @ghostMap_summaryAttempts.
  ///
  /// In en, this message translates to:
  /// **'🎯 {correct}/{total} attempts succeeded'**
  String ghostMap_summaryAttempts(Object correct, Object total);

  /// No description provided for @ghostMap_activationHeader.
  ///
  /// In en, this message translates to:
  /// **'🗺️ Concept map active — {details}'**
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

  /// No description provided for @flueraMethodInfo_title.
  ///
  /// In en, this message translates to:
  /// **'The Fluera Method'**
  String get flueraMethodInfo_title;

  /// No description provided for @flueraMethodInfo_heroTitle.
  ///
  /// In en, this message translates to:
  /// **'Cognitive Loop'**
  String get flueraMethodInfo_heroTitle;

  /// No description provided for @flueraMethodInfo_heroBody.
  ///
  /// In en, this message translates to:
  /// **'4 phases, 12 steps, one science: turning notes into learning that lasts.'**
  String get flueraMethodInfo_heroBody;

  /// No description provided for @flueraMethodInfo_whyItWorks.
  ///
  /// In en, this message translates to:
  /// **'Every step is a cognitive mechanism proven in the lab.'**
  String get flueraMethodInfo_whyItWorks;

  /// No description provided for @flueraMethodInfo_phasesTitle.
  ///
  /// In en, this message translates to:
  /// **'The 4 phases of the Loop'**
  String get flueraMethodInfo_phasesTitle;

  /// No description provided for @flueraMethodInfo_scienceTitle.
  ///
  /// In en, this message translates to:
  /// **'The science behind Fluera'**
  String get flueraMethodInfo_scienceTitle;

  /// No description provided for @flueraMethodInfo_phase1Title.
  ///
  /// In en, this message translates to:
  /// **'CAPTURE'**
  String get flueraMethodInfo_phase1Title;

  /// No description provided for @flueraMethodInfo_phase1Subtitle.
  ///
  /// In en, this message translates to:
  /// **'Turn lectures into active traces'**
  String get flueraMethodInfo_phase1Subtitle;

  /// No description provided for @flueraMethodInfo_phase2Title.
  ///
  /// In en, this message translates to:
  /// **'GENERATE'**
  String get flueraMethodInfo_phase2Title;

  /// No description provided for @flueraMethodInfo_phase2Subtitle.
  ///
  /// In en, this message translates to:
  /// **'Force your mind to reconstruct'**
  String get flueraMethodInfo_phase2Subtitle;

  /// No description provided for @flueraMethodInfo_phase3Title.
  ///
  /// In en, this message translates to:
  /// **'CONSOLIDATE'**
  String get flueraMethodInfo_phase3Title;

  /// No description provided for @flueraMethodInfo_phase3Subtitle.
  ///
  /// In en, this message translates to:
  /// **'Let time cement memory'**
  String get flueraMethodInfo_phase3Subtitle;

  /// No description provided for @flueraMethodInfo_phase4Title.
  ///
  /// In en, this message translates to:
  /// **'TRANSFER'**
  String get flueraMethodInfo_phase4Title;

  /// No description provided for @flueraMethodInfo_phase4Subtitle.
  ///
  /// In en, this message translates to:
  /// **'Connect and apply beyond context'**
  String get flueraMethodInfo_phase4Subtitle;

  /// No description provided for @flueraMethodInfo_tapToExpand.
  ///
  /// In en, this message translates to:
  /// **'Tap for steps'**
  String get flueraMethodInfo_tapToExpand;

  /// No description provided for @flueraMethodInfo_step1Title.
  ///
  /// In en, this message translates to:
  /// **'Handwritten capture'**
  String get flueraMethodInfo_step1Title;

  /// No description provided for @flueraMethodInfo_step1Body.
  ///
  /// In en, this message translates to:
  /// **'Write on the canvas during the lecture. The pen activates motor and spatial channels the keyboard cannot reach.'**
  String get flueraMethodInfo_step1Body;

  /// No description provided for @flueraMethodInfo_step1Citation.
  ///
  /// In en, this message translates to:
  /// **'Mueller & Oppenheimer, 2014'**
  String get flueraMethodInfo_step1Citation;

  /// No description provided for @flueraMethodInfo_step2Title.
  ///
  /// In en, this message translates to:
  /// **'Blind reconstruction'**
  String get flueraMethodInfo_step2Title;

  /// No description provided for @flueraMethodInfo_step2Body.
  ///
  /// In en, this message translates to:
  /// **'Within 2 hours reopen the canvas in an empty zone. Rewrite without looking at your notes. Gaps are valuable information.'**
  String get flueraMethodInfo_step2Body;

  /// No description provided for @flueraMethodInfo_step2Citation.
  ///
  /// In en, this message translates to:
  /// **'Slamecka & Graf, 1978 — Generation Effect'**
  String get flueraMethodInfo_step2Citation;

  /// No description provided for @flueraMethodInfo_step3Title.
  ///
  /// In en, this message translates to:
  /// **'Socratic interrogation'**
  String get flueraMethodInfo_step3Title;

  /// No description provided for @flueraMethodInfo_step3Body.
  ///
  /// In en, this message translates to:
  /// **'Set your confidence before answering. The AI asks questions, never gives answers. The most powerful metacognitive exercise.'**
  String get flueraMethodInfo_step3Body;

  /// No description provided for @flueraMethodInfo_step3Citation.
  ///
  /// In en, this message translates to:
  /// **'Roediger & Karpicke, 2006 — Test Effect'**
  String get flueraMethodInfo_step3Citation;

  /// No description provided for @flueraMethodInfo_step4Title.
  ///
  /// In en, this message translates to:
  /// **'Centaur Comparison'**
  String get flueraMethodInfo_step4Title;

  /// No description provided for @flueraMethodInfo_step4Body.
  ///
  /// In en, this message translates to:
  /// **'Discover which fragments to integrate. Errors made with high confidence imprint 3 times more deeply.'**
  String get flueraMethodInfo_step4Body;

  /// No description provided for @flueraMethodInfo_step4Citation.
  ///
  /// In en, this message translates to:
  /// **'Butterfield & Metcalfe, 2001 — Hypercorrection'**
  String get flueraMethodInfo_step4Citation;

  /// No description provided for @flueraMethodInfo_step5Title.
  ///
  /// In en, this message translates to:
  /// **'Sleep (7-8 hours)'**
  String get flueraMethodInfo_step5Title;

  /// No description provided for @flueraMethodInfo_step5Body.
  ///
  /// In en, this message translates to:
  /// **'Consolidation happens while you sleep. Without deep sleep, Steps 1-4 vanish in a few days.'**
  String get flueraMethodInfo_step5Body;

  /// No description provided for @flueraMethodInfo_step5Citation.
  ///
  /// In en, this message translates to:
  /// **'Walker, 2017 — Sleep & Memory Consolidation'**
  String get flueraMethodInfo_step5Citation;

  /// No description provided for @flueraMethodInfo_step6Title.
  ///
  /// In en, this message translates to:
  /// **'First return at 24h'**
  String get flueraMethodInfo_step6Title;

  /// No description provided for @flueraMethodInfo_step6Body.
  ///
  /// In en, this message translates to:
  /// **'Fluera blurs nodes proportionally to your confidence. An audio cue from the professor appears as a hint.'**
  String get flueraMethodInfo_step6Body;

  /// No description provided for @flueraMethodInfo_step6Citation.
  ///
  /// In en, this message translates to:
  /// **'Ebbinghaus, 1885 — Forgetting Curve'**
  String get flueraMethodInfo_step6Citation;

  /// No description provided for @flueraMethodInfo_step7Title.
  ///
  /// In en, this message translates to:
  /// **'Solidale Learning'**
  String get flueraMethodInfo_step7Title;

  /// No description provided for @flueraMethodInfo_step7Body.
  ///
  /// In en, this message translates to:
  /// **'Teaching a peer is the fastest way to discover what you don\'t really know. Canvas visits, recall duels.'**
  String get flueraMethodInfo_step7Body;

  /// No description provided for @flueraMethodInfo_step7Citation.
  ///
  /// In en, this message translates to:
  /// **'Chase et al., 2009 — Protégé Effect'**
  String get flueraMethodInfo_step7Citation;

  /// No description provided for @flueraMethodInfo_step8Title.
  ///
  /// In en, this message translates to:
  /// **'Adaptive review (3, 7, 14, 30+ days)'**
  String get flueraMethodInfo_step8Title;

  /// No description provided for @flueraMethodInfo_step8Body.
  ///
  /// In en, this message translates to:
  /// **'Increasing intervals calibrated by FSRS-5. Subjects interleaved, not blocked: interleaving trains pattern recognition.'**
  String get flueraMethodInfo_step8Body;

  /// No description provided for @flueraMethodInfo_step8Citation.
  ///
  /// In en, this message translates to:
  /// **'Rohrer & Taylor, 2007 — Interleaving'**
  String get flueraMethodInfo_step8Citation;

  /// No description provided for @flueraMethodInfo_step9Title.
  ///
  /// In en, this message translates to:
  /// **'Bridges across subjects'**
  String get flueraMethodInfo_step9Title;

  /// No description provided for @flueraMethodInfo_step9Body.
  ///
  /// In en, this message translates to:
  /// **'Maximum zoom out. You draw the connections between different canvas zones. This is where knowledge applies to new contexts.'**
  String get flueraMethodInfo_step9Body;

  /// No description provided for @flueraMethodInfo_step9Citation.
  ///
  /// In en, this message translates to:
  /// **'Perkins & Salomon, 1992 — Far Transfer'**
  String get flueraMethodInfo_step9Citation;

  /// No description provided for @flueraMethodInfo_step10Title.
  ///
  /// In en, this message translates to:
  /// **'Exam simulation'**
  String get flueraMethodInfo_step10Title;

  /// No description provided for @flueraMethodInfo_step10Body.
  ///
  /// In en, this message translates to:
  /// **'Fog of War mode: rebuild an entire zone blind. The test that truly predicts how you\'ll perform.'**
  String get flueraMethodInfo_step10Body;

  /// No description provided for @flueraMethodInfo_step10Citation.
  ///
  /// In en, this message translates to:
  /// **'Bjork, 1994 — Desirable Difficulties'**
  String get flueraMethodInfo_step10Citation;

  /// No description provided for @flueraMethodInfo_step11Title.
  ///
  /// In en, this message translates to:
  /// **'The exam'**
  String get flueraMethodInfo_step11Title;

  /// No description provided for @flueraMethodInfo_step11Body.
  ///
  /// In en, this message translates to:
  /// **'The canvas is already in your head.'**
  String get flueraMethodInfo_step11Body;

  /// No description provided for @flueraMethodInfo_step11Citation.
  ///
  /// In en, this message translates to:
  /// **'(external validation)'**
  String get flueraMethodInfo_step11Citation;

  /// No description provided for @flueraMethodInfo_step12Title.
  ///
  /// In en, this message translates to:
  /// **'Stays forever'**
  String get flueraMethodInfo_step12Title;

  /// No description provided for @flueraMethodInfo_step12Body.
  ///
  /// In en, this message translates to:
  /// **'The canvas doesn\'t close at the end of the course. It grows with you, lecture after lecture, year after year. Temporal replay to relive how it grew.'**
  String get flueraMethodInfo_step12Body;

  /// No description provided for @flueraMethodInfo_step12Citation.
  ///
  /// In en, this message translates to:
  /// **'Clark & Chalmers, 1998 — Extended Cognition'**
  String get flueraMethodInfo_step12Citation;

  /// No description provided for @flueraMethodInfo_proBadge.
  ///
  /// In en, this message translates to:
  /// **'Pro'**
  String get flueraMethodInfo_proBadge;

  /// No description provided for @flueraMethodInfo_v15Badge.
  ///
  /// In en, this message translates to:
  /// **'Soon'**
  String get flueraMethodInfo_v15Badge;

  /// No description provided for @flueraMethodInfo_scienceFooter.
  ///
  /// In en, this message translates to:
  /// **'Based on 50+ years of research in cognitive psychology and learning neuroscience.'**
  String get flueraMethodInfo_scienceFooter;

  /// No description provided for @flueraMethodInfo_learnMoreCta.
  ///
  /// In en, this message translates to:
  /// **'Discover Fluera'**
  String get flueraMethodInfo_learnMoreCta;

  /// No description provided for @flueraMethodInfo_offlineError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open browser. Visit fluera.dev'**
  String get flueraMethodInfo_offlineError;

  /// No description provided for @flueraMethodInfo_settingsTile.
  ///
  /// In en, this message translates to:
  /// **'The Fluera Method'**
  String get flueraMethodInfo_settingsTile;

  /// No description provided for @flueraMethodInfo_settingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'How it works: 4 phases, 12 steps, the science'**
  String get flueraMethodInfo_settingsSubtitle;

  /// No description provided for @flueraMethodInfo_demoTitle.
  ///
  /// In en, this message translates to:
  /// **'Try it: the Centaur Comparison'**
  String get flueraMethodInfo_demoTitle;

  /// No description provided for @flueraMethodInfo_demoIntro.
  ///
  /// In en, this message translates to:
  /// **'Set your confidence, then reveal the answer. Feel the Hypercorrection Effect in 10 seconds.'**
  String get flueraMethodInfo_demoIntro;

  /// No description provided for @flueraMethodInfo_demoQuestion.
  ///
  /// In en, this message translates to:
  /// **'What happens in the brain during REM sleep vs NREM sleep?'**
  String get flueraMethodInfo_demoQuestion;

  /// No description provided for @flueraMethodInfo_demoAnswer.
  ///
  /// In en, this message translates to:
  /// **'During REM sleep, neural activity is wake-like: vivid dreams and emotional consolidation. During NREM (especially SWS), the hippocampus \"replays\" episodic memories to the cortex for declarative consolidation. Both types are essential.'**
  String get flueraMethodInfo_demoAnswer;

  /// No description provided for @flueraMethodInfo_demoCitation.
  ///
  /// In en, this message translates to:
  /// **'Walker, 2017 — Why We Sleep'**
  String get flueraMethodInfo_demoCitation;

  /// No description provided for @flueraMethodInfo_demoConfidence1.
  ///
  /// In en, this message translates to:
  /// **'No idea'**
  String get flueraMethodInfo_demoConfidence1;

  /// No description provided for @flueraMethodInfo_demoConfidence2.
  ///
  /// In en, this message translates to:
  /// **'Unsure'**
  String get flueraMethodInfo_demoConfidence2;

  /// No description provided for @flueraMethodInfo_demoConfidence3.
  ///
  /// In en, this message translates to:
  /// **'I think I know'**
  String get flueraMethodInfo_demoConfidence3;

  /// No description provided for @flueraMethodInfo_demoConfidence4.
  ///
  /// In en, this message translates to:
  /// **'I\'m certain'**
  String get flueraMethodInfo_demoConfidence4;

  /// No description provided for @flueraMethodInfo_demoFeedbackLow.
  ///
  /// In en, this message translates to:
  /// **'👍 Honest. The Centaur will compare your guess against fragments to integrate.'**
  String get flueraMethodInfo_demoFeedbackLow;

  /// No description provided for @flueraMethodInfo_demoFeedbackMid.
  ///
  /// In en, this message translates to:
  /// **'⚡ Hypercorrection zone active. If you were wrong, you\'ll remember this 3× better.'**
  String get flueraMethodInfo_demoFeedbackMid;

  /// No description provided for @flueraMethodInfo_demoFeedbackHigh.
  ///
  /// In en, this message translates to:
  /// **'🎯 High confidence. If you were wrong, you just triggered maximum Hypercorrection Effect.'**
  String get flueraMethodInfo_demoFeedbackHigh;

  /// No description provided for @flueraMethodInfo_demoCtaReveal.
  ///
  /// In en, this message translates to:
  /// **'Reveal answer'**
  String get flueraMethodInfo_demoCtaReveal;

  /// No description provided for @flueraMethodInfo_demoCtaTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get flueraMethodInfo_demoCtaTryAgain;

  /// No description provided for @flueraMethodInfo_teaseStepTitle.
  ///
  /// In en, this message translates to:
  /// **'How it works'**
  String get flueraMethodInfo_teaseStepTitle;

  /// No description provided for @flueraMethodInfo_teaseStepBody.
  ///
  /// In en, this message translates to:
  /// **'4 phases, 12 steps, backed by proven science. Turn notes into learning that sticks.\nExample: write a chapter → Fluera asks you to explain it in your own words → your rephrasing stays.'**
  String get flueraMethodInfo_teaseStepBody;

  /// No description provided for @flueraMethodInfo_teaseStepCta.
  ///
  /// In en, this message translates to:
  /// **'Go to canvas'**
  String get flueraMethodInfo_teaseStepCta;

  /// No description provided for @flueraMethodInfo_teaseStepSecondary.
  ///
  /// In en, this message translates to:
  /// **'Discover the method'**
  String get flueraMethodInfo_teaseStepSecondary;

  /// No description provided for @flueraMethodInfo_coachmark.
  ///
  /// In en, this message translates to:
  /// **'Here\'s your method. Tap to explore the 12 steps.'**
  String get flueraMethodInfo_coachmark;

  /// No description provided for @flueraMethodInfo_proBadgeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Solidale Learning is Pro. Go to Settings → Account to upgrade.'**
  String get flueraMethodInfo_proBadgeTooltip;

  /// No description provided for @recall_modeFree.
  ///
  /// In en, this message translates to:
  /// **'Free mode'**
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
  /// **'Fully consolidated.'**
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
  /// **'Retry'**
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
  /// **'Maybe this topic needs another read.'**
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

  /// No description provided for @recall_needNotes.
  ///
  /// In en, this message translates to:
  /// **'Write something on the canvas before starting recall 🧠'**
  String get recall_needNotes;

  /// No description provided for @recall_needMoreNotes.
  ///
  /// In en, this message translates to:
  /// **'You need at least 5 note groups for recall 🧠'**
  String get recall_needMoreNotes;

  /// No description provided for @socratic_needNotes.
  ///
  /// In en, this message translates to:
  /// **'Write something on the canvas first.'**
  String get socratic_needNotes;

  /// No description provided for @socratic_sessionStarted.
  ///
  /// In en, this message translates to:
  /// **'Quiz started — {count} questions'**
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

  /// No description provided for @socratic_noClustersVisible.
  ///
  /// In en, this message translates to:
  /// **'No notes visible on screen. Scroll to your notes and try again.'**
  String get socratic_noClustersVisible;

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

  /// No description provided for @socratic_fallbackUsed.
  ///
  /// In en, this message translates to:
  /// **'No connection — using generic questions'**
  String get socratic_fallbackUsed;

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
  /// **'Known fragment'**
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
  /// **'To review'**
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
  /// **'All correct. Your mastery is solid — review intervals will extend.'**
  String get socratic_insightPerfect;

  /// No description provided for @socratic_insightGaps.
  ///
  /// In en, this message translates to:
  /// **'There are several fragments to integrate — now is the best time to re-read your notes. Retrieval activated the right circuits, so reinforcement will be more effective now.'**
  String get socratic_insightGaps;

  /// No description provided for @socratic_insightBalanced.
  ///
  /// In en, this message translates to:
  /// **'Good balance between what you know and what needs review. Review intervals will update accordingly.'**
  String get socratic_insightBalanced;

  /// No description provided for @socratic_gateMessage.
  ///
  /// In en, this message translates to:
  /// **'You\'ve used your 3 sessions this week. With Pro, AI is always ready when you are. €3.33/month.'**
  String get socratic_gateMessage;

  /// No description provided for @socratic_typeLacuna.
  ///
  /// In en, this message translates to:
  /// **'Bridge fragment'**
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
  /// **'You identified {count} precise zones to strengthen'**
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
  /// **'{visited}/{total} reviewed'**
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
  /// **'Review guide'**
  String get fow_surgicalGuideReview;

  /// No description provided for @fow_zoneSelectionHint.
  ///
  /// In en, this message translates to:
  /// **'📐 Draw a rectangle to select the area to test'**
  String get fow_zoneSelectionHint;

  /// No description provided for @fow_zoneSelectionWholeCanvas.
  ///
  /// In en, this message translates to:
  /// **'Whole canvas'**
  String get fow_zoneSelectionWholeCanvas;

  /// No description provided for @fow_zoneTooFewNodes.
  ///
  /// In en, this message translates to:
  /// **'Only {count} nodes in the area — need at least 3. Try a larger area.'**
  String fow_zoneTooFewNodes(int count);

  /// No description provided for @fow_hintFlyTo.
  ///
  /// In en, this message translates to:
  /// **'💡 Hint #{number} — look here!'**
  String fow_hintFlyTo(int number);

  /// No description provided for @fow_hintReveal.
  ///
  /// In en, this message translates to:
  /// **'💡 Hint #{number} — temporary reveal!'**
  String fow_hintReveal(int number);

  /// No description provided for @fow_hintDistVeryClose.
  ///
  /// In en, this message translates to:
  /// **'Very close!'**
  String get fow_hintDistVeryClose;

  /// No description provided for @fow_hintDistClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get fow_hintDistClose;

  /// No description provided for @fow_hintDistMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium distance'**
  String get fow_hintDistMedium;

  /// No description provided for @fow_hintDistFar.
  ///
  /// In en, this message translates to:
  /// **'Far'**
  String get fow_hintDistFar;

  /// No description provided for @fow_hintLabel.
  ///
  /// In en, this message translates to:
  /// **'Hint'**
  String get fow_hintLabel;

  /// No description provided for @fow_masteryMapBlindSpotAction.
  ///
  /// In en, this message translates to:
  /// **'👁‍🗨 You didn\'t look for this — read it carefully'**
  String get fow_masteryMapBlindSpotAction;

  /// No description provided for @fow_masteryMapForgottenAction.
  ///
  /// In en, this message translates to:
  /// **'📝 Forgotten — re-read and try writing from memory'**
  String get fow_masteryMapForgottenAction;

  /// No description provided for @fow_surgicalInstruction.
  ///
  /// In en, this message translates to:
  /// **'Re-read this concept carefully'**
  String get fow_surgicalInstruction;

  /// No description provided for @fow_surgicalReadNext.
  ///
  /// In en, this message translates to:
  /// **'Done → Next'**
  String get fow_surgicalReadNext;

  /// No description provided for @fow_surgicalLastOne.
  ///
  /// In en, this message translates to:
  /// **'Last one →'**
  String get fow_surgicalLastOne;

  /// No description provided for @fow_surgicalAllDone.
  ///
  /// In en, this message translates to:
  /// **'All {count} nodes reviewed!'**
  String fow_surgicalAllDone(int count);

  /// No description provided for @fow_surgicalBackToMap.
  ///
  /// In en, this message translates to:
  /// **'Back to map'**
  String get fow_surgicalBackToMap;

  /// No description provided for @fow_setupSelectArea.
  ///
  /// In en, this message translates to:
  /// **'Select area'**
  String get fow_setupSelectArea;

  /// No description provided for @fow_setupWholeCanvas.
  ///
  /// In en, this message translates to:
  /// **'Whole canvas'**
  String get fow_setupWholeCanvas;

  /// No description provided for @fow_setupAreaDesc.
  ///
  /// In en, this message translates to:
  /// **'Draw a rectangle to test only a specific area'**
  String get fow_setupAreaDesc;

  /// No description provided for @fow_setupNodeCount.
  ///
  /// In en, this message translates to:
  /// **'{count} total nodes'**
  String fow_setupNodeCount(int count);

  /// No description provided for @fow_setupChooseLevel.
  ///
  /// In en, this message translates to:
  /// **'Choose fog density. Denser fog = harder challenge.'**
  String get fow_setupChooseLevel;

  /// No description provided for @fow_setupLightDesc.
  ///
  /// In en, this message translates to:
  /// **'Node silhouettes visible, zero content'**
  String get fow_setupLightDesc;

  /// No description provided for @fow_setupMediumDesc.
  ///
  /// In en, this message translates to:
  /// **'Limited visibility (300px). Move closer.'**
  String get fow_setupMediumDesc;

  /// No description provided for @fow_setupTotalDesc.
  ///
  /// In en, this message translates to:
  /// **'Total darkness. Only memory guides you.'**
  String get fow_setupTotalDesc;

  /// No description provided for @fow_setupInfoTooltip.
  ///
  /// In en, this message translates to:
  /// **'How it works'**
  String get fow_setupInfoTooltip;

  /// No description provided for @fow_zoneTooSmall.
  ///
  /// In en, this message translates to:
  /// **'Area too small — drag a larger rectangle'**
  String get fow_zoneTooSmall;

  /// No description provided for @fow_seiQui.
  ///
  /// In en, this message translates to:
  /// **'You are here'**
  String get fow_seiQui;

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
  /// **'Bridge fragment'**
  String get socraticInfo_typeLacunaTitle;

  /// No description provided for @socraticInfo_typeLacunaSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Recall 1-2'**
  String get socraticInfo_typeLacunaSubtitle;

  /// No description provided for @socraticInfo_typeLacunaBody.
  ///
  /// In en, this message translates to:
  /// **'Creates a \"cognitive tension\" you feel the need to resolve. Asks what CONNECTS two concepts or which BRIDGE FRAGMENT fits between them.'**
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
  /// **'To review'**
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
  /// **'To integrate + Low conf.'**
  String get socraticInfo_matrixGap;

  /// No description provided for @socraticInfo_matrixGapMsg.
  ///
  /// In en, this message translates to:
  /// **'Fragment to integrate — review will help.'**
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

  /// No description provided for @ghostMapInfo_title.
  ///
  /// In en, this message translates to:
  /// **'Concept map'**
  String get ghostMapInfo_title;

  /// No description provided for @ghostMapInfo_a11yLabel.
  ///
  /// In en, this message translates to:
  /// **'Concept map informational screen'**
  String get ghostMapInfo_a11yLabel;

  /// No description provided for @ghostMapInfo_heroTitle.
  ///
  /// In en, this message translates to:
  /// **'The Centaur Comparison'**
  String get ghostMapInfo_heroTitle;

  /// No description provided for @ghostMapInfo_heroDescription.
  ///
  /// In en, this message translates to:
  /// **'Fluera generates a \"ghost\" concept map based on your notes and overlays it on the canvas. You can compare what you wrote with what the AI thinks should be integrated, discovering fragments to connect and confirming mastery.'**
  String get ghostMapInfo_heroDescription;

  /// No description provided for @ghostMapInfo_heroPrinciple.
  ///
  /// In en, this message translates to:
  /// **'Discovering what you DON\'T know is more important than confirming what you do — Active Recall Diagnostics.'**
  String get ghostMapInfo_heroPrinciple;

  /// No description provided for @ghostMapInfo_sectionHowItWorks.
  ///
  /// In en, this message translates to:
  /// **'How It Works'**
  String get ghostMapInfo_sectionHowItWorks;

  /// No description provided for @ghostMapInfo_sectionNodeTypes.
  ///
  /// In en, this message translates to:
  /// **'5 Node Types'**
  String get ghostMapInfo_sectionNodeTypes;

  /// No description provided for @ghostMapInfo_sectionAttempts.
  ///
  /// In en, this message translates to:
  /// **'Attempts and Comparison'**
  String get ghostMapInfo_sectionAttempts;

  /// No description provided for @ghostMapInfo_sectionHypercorrection.
  ///
  /// In en, this message translates to:
  /// **'Hypercorrection'**
  String get ghostMapInfo_sectionHypercorrection;

  /// No description provided for @ghostMapInfo_sectionZPD.
  ///
  /// In en, this message translates to:
  /// **'Zone of Proximal Development'**
  String get ghostMapInfo_sectionZPD;

  /// No description provided for @ghostMapInfo_sectionNavigation.
  ///
  /// In en, this message translates to:
  /// **'Guided Navigation'**
  String get ghostMapInfo_sectionNavigation;

  /// No description provided for @ghostMapInfo_sectionFSRS.
  ///
  /// In en, this message translates to:
  /// **'FSRS Integration'**
  String get ghostMapInfo_sectionFSRS;

  /// No description provided for @ghostMapInfo_sectionGrowth.
  ///
  /// In en, this message translates to:
  /// **'Canvas Growth'**
  String get ghostMapInfo_sectionGrowth;

  /// No description provided for @ghostMapInfo_sectionSleep.
  ///
  /// In en, this message translates to:
  /// **'Overnight Consolidation'**
  String get ghostMapInfo_sectionSleep;

  /// No description provided for @ghostMapInfo_flowWrite.
  ///
  /// In en, this message translates to:
  /// **'Write'**
  String get ghostMapInfo_flowWrite;

  /// No description provided for @ghostMapInfo_flowWriteDesc.
  ///
  /// In en, this message translates to:
  /// **'Take handwritten notes on the canvas'**
  String get ghostMapInfo_flowWriteDesc;

  /// No description provided for @ghostMapInfo_flowActivate.
  ///
  /// In en, this message translates to:
  /// **'Activate'**
  String get ghostMapInfo_flowActivate;

  /// No description provided for @ghostMapInfo_flowActivateDesc.
  ///
  /// In en, this message translates to:
  /// **'Tap the \"What am I missing?\" button in the toolbar'**
  String get ghostMapInfo_flowActivateDesc;

  /// No description provided for @ghostMapInfo_flowAnalysis.
  ///
  /// In en, this message translates to:
  /// **'AI Analysis'**
  String get ghostMapInfo_flowAnalysis;

  /// No description provided for @ghostMapInfo_flowAnalysisDesc.
  ///
  /// In en, this message translates to:
  /// **'The AI analyzes clusters and generates the ideal map'**
  String get ghostMapInfo_flowAnalysisDesc;

  /// No description provided for @ghostMapInfo_flowOverlay.
  ///
  /// In en, this message translates to:
  /// **'Overlay'**
  String get ghostMapInfo_flowOverlay;

  /// No description provided for @ghostMapInfo_flowOverlayDesc.
  ///
  /// In en, this message translates to:
  /// **'Ghost nodes appear on the canvas as an overlay'**
  String get ghostMapInfo_flowOverlayDesc;

  /// No description provided for @ghostMapInfo_flowAttempt.
  ///
  /// In en, this message translates to:
  /// **'Attempt'**
  String get ghostMapInfo_flowAttempt;

  /// No description provided for @ghostMapInfo_flowAttemptDesc.
  ///
  /// In en, this message translates to:
  /// **'Tap a node and try to write the fragment to integrate'**
  String get ghostMapInfo_flowAttemptDesc;

  /// No description provided for @ghostMapInfo_flowCompare.
  ///
  /// In en, this message translates to:
  /// **'Comparison'**
  String get ghostMapInfo_flowCompare;

  /// No description provided for @ghostMapInfo_flowCompareDesc.
  ///
  /// In en, this message translates to:
  /// **'See the AI\'s answer and self-evaluate your attempt'**
  String get ghostMapInfo_flowCompareDesc;

  /// No description provided for @ghostMapInfo_flowResults.
  ///
  /// In en, this message translates to:
  /// **'Results'**
  String get ghostMapInfo_flowResults;

  /// No description provided for @ghostMapInfo_flowResultsDesc.
  ///
  /// In en, this message translates to:
  /// **'Growth summary + FSRS updated for SRS'**
  String get ghostMapInfo_flowResultsDesc;

  /// No description provided for @ghostMapInfo_attemptIntro.
  ///
  /// In en, this message translates to:
  /// **'When you tap a node to discover (❓), a window opens where you can:'**
  String get ghostMapInfo_attemptIntro;

  /// No description provided for @ghostMapInfo_attemptType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get ghostMapInfo_attemptType;

  /// No description provided for @ghostMapInfo_attemptTypeDesc.
  ///
  /// In en, this message translates to:
  /// **'Write the fragment you think fits here'**
  String get ghostMapInfo_attemptTypeDesc;

  /// No description provided for @ghostMapInfo_attemptDraw.
  ///
  /// In en, this message translates to:
  /// **'Draw'**
  String get ghostMapInfo_attemptDraw;

  /// No description provided for @ghostMapInfo_attemptDrawDesc.
  ///
  /// In en, this message translates to:
  /// **'Use the pen for handwriting (integrated OCR)'**
  String get ghostMapInfo_attemptDrawDesc;

  /// No description provided for @ghostMapInfo_attemptReveal.
  ///
  /// In en, this message translates to:
  /// **'Reveal'**
  String get ghostMapInfo_attemptReveal;

  /// No description provided for @ghostMapInfo_attemptRevealDesc.
  ///
  /// In en, this message translates to:
  /// **'After 10 seconds, you can reveal the AI\'s answer'**
  String get ghostMapInfo_attemptRevealDesc;

  /// No description provided for @ghostMapInfo_attemptTimerNote.
  ///
  /// In en, this message translates to:
  /// **'The 10-second timer forces you to think before giving up — this activates Retrieval Effort (Bjork, 1994).'**
  String get ghostMapInfo_attemptTimerNote;

  /// No description provided for @ghostMapInfo_hypercorrectionTitle.
  ///
  /// In en, this message translates to:
  /// **'The Hypercorrection Principle'**
  String get ghostMapInfo_hypercorrectionTitle;

  /// No description provided for @ghostMapInfo_hypercorrectionDesc.
  ///
  /// In en, this message translates to:
  /// **'When you are very confident about something but the fragment needs recontextualizing, the surprise focuses attention on the reconfiguration and deeply imprints it in long-term memory.'**
  String get ghostMapInfo_hypercorrectionDesc;

  /// No description provided for @ghostMapInfo_hypercorrectionCitation.
  ///
  /// In en, this message translates to:
  /// **'☝️ Butterfield & Metcalfe (2001)'**
  String get ghostMapInfo_hypercorrectionCitation;

  /// No description provided for @ghostMapInfo_hypercorrectionQuote.
  ///
  /// In en, this message translates to:
  /// **'\"High-confidence errors produce SUPERIOR learning compared to low-confidence errors — the hypercorrective effect.\"'**
  String get ghostMapInfo_hypercorrectionQuote;

  /// No description provided for @ghostMapInfo_hypercorrectionVisual.
  ///
  /// In en, this message translates to:
  /// **'The concept map marks these nodes with ⚡ and a wavy red border.'**
  String get ghostMapInfo_hypercorrectionVisual;

  /// No description provided for @ghostMapInfo_zpdTitle.
  ///
  /// In en, this message translates to:
  /// **'ZPD — Vygotsky (1978)'**
  String get ghostMapInfo_zpdTitle;

  /// No description provided for @ghostMapInfo_zpdDesc.
  ///
  /// In en, this message translates to:
  /// **'Some concepts might be TOO advanced for your current level. The concept map identifies them as \"below ZPD\" and shows them in grey — not because they aren\'t important, but because there are foundational concepts to consolidate first.'**
  String get ghostMapInfo_zpdDesc;

  /// No description provided for @ghostMapInfo_zpdComfort.
  ///
  /// In en, this message translates to:
  /// **'Comfort Zone'**
  String get ghostMapInfo_zpdComfort;

  /// No description provided for @ghostMapInfo_zpdComfortDesc.
  ///
  /// In en, this message translates to:
  /// **'Concepts you\'ve mastered — ✅ green nodes'**
  String get ghostMapInfo_zpdComfortDesc;

  /// No description provided for @ghostMapInfo_zpdZone.
  ///
  /// In en, this message translates to:
  /// **'ZPD'**
  String get ghostMapInfo_zpdZone;

  /// No description provided for @ghostMapInfo_zpdZoneDesc.
  ///
  /// In en, this message translates to:
  /// **'You can learn with support — ❓ and ⚠️ nodes'**
  String get ghostMapInfo_zpdZoneDesc;

  /// No description provided for @ghostMapInfo_zpdAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Too Advanced'**
  String get ghostMapInfo_zpdAdvanced;

  /// No description provided for @ghostMapInfo_zpdAdvancedDesc.
  ///
  /// In en, this message translates to:
  /// **'Revisit after consolidating the basics'**
  String get ghostMapInfo_zpdAdvancedDesc;

  /// No description provided for @ghostMapInfo_navIntro.
  ///
  /// In en, this message translates to:
  /// **'A floating bar at the bottom lets you navigate between nodes:'**
  String get ghostMapInfo_navIntro;

  /// No description provided for @ghostMapInfo_navMissing.
  ///
  /// In en, this message translates to:
  /// **'🔴 To discover'**
  String get ghostMapInfo_navMissing;

  /// No description provided for @ghostMapInfo_navMissingDesc.
  ///
  /// In en, this message translates to:
  /// **'Fragments not yet integrated into the map — highest priority'**
  String get ghostMapInfo_navMissingDesc;

  /// No description provided for @ghostMapInfo_navWeak.
  ///
  /// In en, this message translates to:
  /// **'🟡 To consolidate'**
  String get ghostMapInfo_navWeak;

  /// No description provided for @ghostMapInfo_navWeakDesc.
  ///
  /// In en, this message translates to:
  /// **'Concepts present but imprecise or connections to recontextualize'**
  String get ghostMapInfo_navWeakDesc;

  /// No description provided for @ghostMapInfo_navArrows.
  ///
  /// In en, this message translates to:
  /// **'⬅ ➡ Navigation'**
  String get ghostMapInfo_navArrows;

  /// No description provided for @ghostMapInfo_navArrowsDesc.
  ///
  /// In en, this message translates to:
  /// **'Centers the canvas on the selected node'**
  String get ghostMapInfo_navArrowsDesc;

  /// No description provided for @ghostMapInfo_fsrsTitle.
  ///
  /// In en, this message translates to:
  /// **'Every interaction calibrates review'**
  String get ghostMapInfo_fsrsTitle;

  /// No description provided for @ghostMapInfo_fsrsCorrect.
  ///
  /// In en, this message translates to:
  /// **'Correct attempt'**
  String get ghostMapInfo_fsrsCorrect;

  /// No description provided for @ghostMapInfo_fsrsCorrectEffect.
  ///
  /// In en, this message translates to:
  /// **'Interval lengthens'**
  String get ghostMapInfo_fsrsCorrectEffect;

  /// No description provided for @ghostMapInfo_fsrsWrong.
  ///
  /// In en, this message translates to:
  /// **'Attempt to review'**
  String get ghostMapInfo_fsrsWrong;

  /// No description provided for @ghostMapInfo_fsrsWrongEffect.
  ///
  /// In en, this message translates to:
  /// **'Interval shortens'**
  String get ghostMapInfo_fsrsWrongEffect;

  /// No description provided for @ghostMapInfo_fsrsHyper.
  ///
  /// In en, this message translates to:
  /// **'Hypercorrection'**
  String get ghostMapInfo_fsrsHyper;

  /// No description provided for @ghostMapInfo_fsrsHyperEffect.
  ///
  /// In en, this message translates to:
  /// **'Reduced penalty (shock = learning)'**
  String get ghostMapInfo_fsrsHyperEffect;

  /// No description provided for @ghostMapInfo_fsrsRevealed.
  ///
  /// In en, this message translates to:
  /// **'Only revealed'**
  String get ghostMapInfo_fsrsRevealed;

  /// No description provided for @ghostMapInfo_fsrsRevealedEffect.
  ///
  /// In en, this message translates to:
  /// **'Passive exposure — weak'**
  String get ghostMapInfo_fsrsRevealedEffect;

  /// No description provided for @ghostMapInfo_fsrsOnCanvas.
  ///
  /// In en, this message translates to:
  /// **'Already on canvas'**
  String get ghostMapInfo_fsrsOnCanvas;

  /// No description provided for @ghostMapInfo_fsrsOnCanvasEffect.
  ///
  /// In en, this message translates to:
  /// **'Reinforcement — stable interval'**
  String get ghostMapInfo_fsrsOnCanvasEffect;

  /// No description provided for @ghostMapInfo_fsrsNote.
  ///
  /// In en, this message translates to:
  /// **'The FSRS data feeds into automatic review — concepts associated with nodes will reappear blurred when the algorithm predicts you\'re about to forget them.'**
  String get ghostMapInfo_fsrsNote;

  /// No description provided for @ghostMapInfo_growthTitle.
  ///
  /// In en, this message translates to:
  /// **'How much did your canvas grow?'**
  String get ghostMapInfo_growthTitle;

  /// No description provided for @ghostMapInfo_growthIntro.
  ///
  /// In en, this message translates to:
  /// **'When closing the concept map, you see a summary with:'**
  String get ghostMapInfo_growthIntro;

  /// No description provided for @ghostMapInfo_growthCorrect.
  ///
  /// In en, this message translates to:
  /// **'Correct'**
  String get ghostMapInfo_growthCorrect;

  /// No description provided for @ghostMapInfo_growthCorrectDesc.
  ///
  /// In en, this message translates to:
  /// **'Concepts you already had right'**
  String get ghostMapInfo_growthCorrectDesc;

  /// No description provided for @ghostMapInfo_growthImprove.
  ///
  /// In en, this message translates to:
  /// **'To improve'**
  String get ghostMapInfo_growthImprove;

  /// No description provided for @ghostMapInfo_growthImproveDesc.
  ///
  /// In en, this message translates to:
  /// **'Imprecise or weak concepts'**
  String get ghostMapInfo_growthImproveDesc;

  /// No description provided for @ghostMapInfo_growthMissing.
  ///
  /// In en, this message translates to:
  /// **'To discover'**
  String get ghostMapInfo_growthMissing;

  /// No description provided for @ghostMapInfo_growthMissingDesc.
  ///
  /// In en, this message translates to:
  /// **'Fragments you hadn\'t written yet'**
  String get ghostMapInfo_growthMissingDesc;

  /// No description provided for @ghostMapInfo_growthAttempts.
  ///
  /// In en, this message translates to:
  /// **'Attempts'**
  String get ghostMapInfo_growthAttempts;

  /// No description provided for @ghostMapInfo_growthAttemptsDesc.
  ///
  /// In en, this message translates to:
  /// **'How many you got right vs total'**
  String get ghostMapInfo_growthAttemptsDesc;

  /// No description provided for @ghostMapInfo_growthPercent.
  ///
  /// In en, this message translates to:
  /// **'Growth %'**
  String get ghostMapInfo_growthPercent;

  /// No description provided for @ghostMapInfo_growthPercentDesc.
  ///
  /// In en, this message translates to:
  /// **'Fragments integrated after interaction'**
  String get ghostMapInfo_growthPercentDesc;

  /// No description provided for @ghostMapInfo_growthExplored.
  ///
  /// In en, this message translates to:
  /// **'{percent}% explored'**
  String ghostMapInfo_growthExplored(int percent);

  /// No description provided for @ghostMapInfo_sleepTitle.
  ///
  /// In en, this message translates to:
  /// **'Sleep completes the cycle'**
  String get ghostMapInfo_sleepTitle;

  /// No description provided for @ghostMapInfo_sleepDesc.
  ///
  /// In en, this message translates to:
  /// **'After the session, your brain continues to process during sleep (memory consolidation). On next access, revisited concepts will be more stable and Fluera will automatically adapt review intervals.\n\nThis is the cycle: fragment exploration → overnight interval computation → gradual review.'**
  String get ghostMapInfo_sleepDesc;

  /// No description provided for @ghostMapInfo_sleepCitation.
  ///
  /// In en, this message translates to:
  /// **'Stickgold & Walker (2005): \"Sleep transforms episodic memory into structured semantic knowledge.\"'**
  String get ghostMapInfo_sleepCitation;

  /// No description provided for @ghostMapInfo_cta.
  ///
  /// In en, this message translates to:
  /// **'Back to canvas — try it!'**
  String get ghostMapInfo_cta;

  /// No description provided for @ghostMapInfo_footer.
  ///
  /// In en, this message translates to:
  /// **'Based on research by Butterfield & Metcalfe (2001),\nAusubel (1968), Chi (2009), Bjork (1994), Vygotsky (1978)'**
  String get ghostMapInfo_footer;

  /// No description provided for @ghostMapInfo_nodeTypeTapHint.
  ///
  /// In en, this message translates to:
  /// **'Tap a node to discover its meaning:'**
  String get ghostMapInfo_nodeTypeTapHint;

  /// No description provided for @ghostMapInfo_nodeMissingTitle.
  ///
  /// In en, this message translates to:
  /// **'To discover'**
  String get ghostMapInfo_nodeMissingTitle;

  /// No description provided for @ghostMapInfo_nodeMissingDesc.
  ///
  /// In en, this message translates to:
  /// **'A fragment not yet on your canvas that the AI deems important to integrate. You can attempt to write it or reveal what the AI suggested.'**
  String get ghostMapInfo_nodeMissingDesc;

  /// No description provided for @ghostMapInfo_nodeMissingPrinciple.
  ///
  /// In en, this message translates to:
  /// **'Active Recall + Gap Detection (Ausubel, 1968)'**
  String get ghostMapInfo_nodeMissingPrinciple;

  /// No description provided for @ghostMapInfo_nodeWeakTitle.
  ///
  /// In en, this message translates to:
  /// **'Weak'**
  String get ghostMapInfo_nodeWeakTitle;

  /// No description provided for @ghostMapInfo_nodeWeakDesc.
  ///
  /// In en, this message translates to:
  /// **'A concept present but imprecise, incomplete, or to recontextualize. The AI explains how to integrate it better.'**
  String get ghostMapInfo_nodeWeakDesc;

  /// No description provided for @ghostMapInfo_nodeWeakPrinciple.
  ///
  /// In en, this message translates to:
  /// **'Elaborative Feedback (Chi, 2009)'**
  String get ghostMapInfo_nodeWeakPrinciple;

  /// No description provided for @ghostMapInfo_nodeCorrectTitle.
  ///
  /// In en, this message translates to:
  /// **'Correct'**
  String get ghostMapInfo_nodeCorrectTitle;

  /// No description provided for @ghostMapInfo_nodeCorrectDesc.
  ///
  /// In en, this message translates to:
  /// **'A correct concept — the green circle confirms mastery. Tap it to see positive feedback.'**
  String get ghostMapInfo_nodeCorrectDesc;

  /// No description provided for @ghostMapInfo_nodeCorrectPrinciple.
  ///
  /// In en, this message translates to:
  /// **'Positive Reinforcement + Self-Efficacy'**
  String get ghostMapInfo_nodeCorrectPrinciple;

  /// No description provided for @ghostMapInfo_nodeExcellentTitle.
  ///
  /// In en, this message translates to:
  /// **'Excellent'**
  String get ghostMapInfo_nodeExcellentTitle;

  /// No description provided for @ghostMapInfo_nodeExcellentDesc.
  ///
  /// In en, this message translates to:
  /// **'Deep mastery — high confidence confirmed. These nodes glow bright green ⭐.'**
  String get ghostMapInfo_nodeExcellentDesc;

  /// No description provided for @ghostMapInfo_nodeExcellentPrinciple.
  ///
  /// In en, this message translates to:
  /// **'Mastery Learning (Bloom, 1968)'**
  String get ghostMapInfo_nodeExcellentPrinciple;

  /// No description provided for @ghostMapInfo_nodeHyperTitle.
  ///
  /// In en, this message translates to:
  /// **'Hypercorrection'**
  String get ghostMapInfo_nodeHyperTitle;

  /// No description provided for @ghostMapInfo_nodeHyperDesc.
  ///
  /// In en, this message translates to:
  /// **'You were very confident but the fragment needed recontextualizing — the wavy red border signals the most powerful learning opportunity.'**
  String get ghostMapInfo_nodeHyperDesc;

  /// No description provided for @ghostMapInfo_nodeHyperPrinciple.
  ///
  /// In en, this message translates to:
  /// **'Hypercorrection Effect (Butterfield & Metcalfe, 2001)'**
  String get ghostMapInfo_nodeHyperPrinciple;

  /// No description provided for @ghostMapInfo_demoTitle.
  ///
  /// In en, this message translates to:
  /// **'Try the flow!'**
  String get ghostMapInfo_demoTitle;

  /// No description provided for @ghostMapInfo_demoTapToStart.
  ///
  /// In en, this message translates to:
  /// **'Tap to simulate an attempt'**
  String get ghostMapInfo_demoTapToStart;

  /// No description provided for @ghostMapInfo_demoThinking.
  ///
  /// In en, this message translates to:
  /// **'🤔 Think of the answer...'**
  String get ghostMapInfo_demoThinking;

  /// No description provided for @ghostMapInfo_demoRevealTitle.
  ///
  /// In en, this message translates to:
  /// **'The AI\'s answer:'**
  String get ghostMapInfo_demoRevealTitle;

  /// No description provided for @ghostMapInfo_demoRevealExample.
  ///
  /// In en, this message translates to:
  /// **'\"Chlorophyll photosynthesis\"'**
  String get ghostMapInfo_demoRevealExample;

  /// No description provided for @ghostMapInfo_demoRevealQuestion.
  ///
  /// In en, this message translates to:
  /// **'Had you thought the same thing?'**
  String get ghostMapInfo_demoRevealQuestion;

  /// No description provided for @ghostMapInfo_demoYes.
  ///
  /// In en, this message translates to:
  /// **'Yes!'**
  String get ghostMapInfo_demoYes;

  /// No description provided for @ghostMapInfo_demoNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get ghostMapInfo_demoNo;

  /// No description provided for @ghostMapInfo_demoCorrect.
  ///
  /// In en, this message translates to:
  /// **'Correct! The concept is reinforced.'**
  String get ghostMapInfo_demoCorrect;

  /// No description provided for @ghostMapInfo_demoWrong.
  ///
  /// In en, this message translates to:
  /// **'Hypercorrection! The recontextualization imprints in memory.'**
  String get ghostMapInfo_demoWrong;

  /// No description provided for @ghostMapInfo_demoFsrsUp.
  ///
  /// In en, this message translates to:
  /// **'FSRS: interval ↑ (consolidation)'**
  String get ghostMapInfo_demoFsrsUp;

  /// No description provided for @ghostMapInfo_demoFsrsDown.
  ///
  /// In en, this message translates to:
  /// **'FSRS: interval ↓ + mnemonic shock'**
  String get ghostMapInfo_demoFsrsDown;

  /// No description provided for @ghostMapInfo_demoRetry.
  ///
  /// In en, this message translates to:
  /// **'Tap to retry'**
  String get ghostMapInfo_demoRetry;

  /// No description provided for @ghostMapInfo_beforeAfterBefore.
  ///
  /// In en, this message translates to:
  /// **'Before'**
  String get ghostMapInfo_beforeAfterBefore;

  /// No description provided for @ghostMapInfo_beforeAfterAfter.
  ///
  /// In en, this message translates to:
  /// **'After'**
  String get ghostMapInfo_beforeAfterAfter;

  /// No description provided for @ghostMapInfo_beforeAfterResultAfter.
  ///
  /// In en, this message translates to:
  /// **'📈 7 concepts, 4 new — 57% growth!'**
  String get ghostMapInfo_beforeAfterResultAfter;

  /// No description provided for @ghostMapInfo_beforeAfterResultBefore.
  ///
  /// In en, this message translates to:
  /// **'3 isolated concepts — connections to build'**
  String get ghostMapInfo_beforeAfterResultBefore;

  /// No description provided for @paywall_featureRecall.
  ///
  /// In en, this message translates to:
  /// **'Test me'**
  String get paywall_featureRecall;

  /// No description provided for @paywall_featureSocratic.
  ///
  /// In en, this message translates to:
  /// **'AI Quiz'**
  String get paywall_featureSocratic;

  /// No description provided for @paywall_featureGhostMap.
  ///
  /// In en, this message translates to:
  /// **'What am I missing?'**
  String get paywall_featureGhostMap;

  /// No description provided for @paywall_featureFsrsChallenge.
  ///
  /// In en, this message translates to:
  /// **'Smart review + Challenge'**
  String get paywall_featureFsrsChallenge;

  /// No description provided for @auth_heroWelcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get auth_heroWelcomeBack;

  /// No description provided for @auth_heroCreateAccount.
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get auth_heroCreateAccount;

  /// No description provided for @auth_subtitleLogin.
  ///
  /// In en, this message translates to:
  /// **'Sign in to sync your notes'**
  String get auth_subtitleLogin;

  /// No description provided for @auth_subtitleSignup.
  ///
  /// In en, this message translates to:
  /// **'Sign up to get started'**
  String get auth_subtitleSignup;

  /// No description provided for @auth_fieldEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get auth_fieldEmail;

  /// No description provided for @auth_fieldPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get auth_fieldPassword;

  /// No description provided for @auth_fieldConfirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm Password'**
  String get auth_fieldConfirmPassword;

  /// No description provided for @auth_validatorEmailRequired.
  ///
  /// In en, this message translates to:
  /// **'Email required'**
  String get auth_validatorEmailRequired;

  /// No description provided for @auth_validatorEmailInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid email format'**
  String get auth_validatorEmailInvalid;

  /// No description provided for @auth_validatorPasswordMin.
  ///
  /// In en, this message translates to:
  /// **'Minimum 6 characters'**
  String get auth_validatorPasswordMin;

  /// No description provided for @auth_validatorPasswordMismatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get auth_validatorPasswordMismatch;

  /// No description provided for @auth_strengthWeak.
  ///
  /// In en, this message translates to:
  /// **'Weak'**
  String get auth_strengthWeak;

  /// No description provided for @auth_strengthFair.
  ///
  /// In en, this message translates to:
  /// **'Fair'**
  String get auth_strengthFair;

  /// No description provided for @auth_strengthGood.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get auth_strengthGood;

  /// No description provided for @auth_strengthStrong.
  ///
  /// In en, this message translates to:
  /// **'Strong'**
  String get auth_strengthStrong;

  /// No description provided for @auth_checkLength.
  ///
  /// In en, this message translates to:
  /// **'At least 6 characters'**
  String get auth_checkLength;

  /// No description provided for @auth_checkCase.
  ///
  /// In en, this message translates to:
  /// **'Uppercase and lowercase'**
  String get auth_checkCase;

  /// No description provided for @auth_checkNumber.
  ///
  /// In en, this message translates to:
  /// **'A number'**
  String get auth_checkNumber;

  /// No description provided for @auth_checkSpecial.
  ///
  /// In en, this message translates to:
  /// **'A special character'**
  String get auth_checkSpecial;

  /// No description provided for @auth_ctaLogin.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get auth_ctaLogin;

  /// No description provided for @auth_ctaSignup.
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get auth_ctaSignup;

  /// No description provided for @auth_toggleQuestionNoAccount.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account? '**
  String get auth_toggleQuestionNoAccount;

  /// No description provided for @auth_toggleQuestionHasAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? '**
  String get auth_toggleQuestionHasAccount;

  /// No description provided for @auth_toggleActionSignup.
  ///
  /// In en, this message translates to:
  /// **'Sign Up'**
  String get auth_toggleActionSignup;

  /// No description provided for @auth_toggleActionLogin.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get auth_toggleActionLogin;

  /// No description provided for @auth_magicLink.
  ///
  /// In en, this message translates to:
  /// **'Sign in without password'**
  String get auth_magicLink;

  /// No description provided for @auth_forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get auth_forgotPassword;

  /// No description provided for @auth_socialGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get auth_socialGoogle;

  /// No description provided for @auth_socialApple.
  ///
  /// In en, this message translates to:
  /// **'Continue with Apple'**
  String get auth_socialApple;

  /// No description provided for @auth_taglineCreativeCanvasEngine.
  ///
  /// In en, this message translates to:
  /// **'Creative Canvas Engine'**
  String get auth_taglineCreativeCanvasEngine;

  /// No description provided for @auth_dividerOr.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get auth_dividerOr;

  /// No description provided for @auth_errorPasswordMismatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords don\'t match'**
  String get auth_errorPasswordMismatch;

  /// No description provided for @auth_errorConnection.
  ///
  /// In en, this message translates to:
  /// **'Connection error. Try again.'**
  String get auth_errorConnection;

  /// No description provided for @auth_errorGoogleSignIn.
  ///
  /// In en, this message translates to:
  /// **'Google Sign-In error'**
  String get auth_errorGoogleSignIn;

  /// No description provided for @auth_errorAppleSignIn.
  ///
  /// In en, this message translates to:
  /// **'Apple Sign-In error'**
  String get auth_errorAppleSignIn;

  /// No description provided for @auth_errorInvalidEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email first'**
  String get auth_errorInvalidEmail;

  /// No description provided for @auth_errorResetLink.
  ///
  /// In en, this message translates to:
  /// **'Error sending link'**
  String get auth_errorResetLink;

  /// No description provided for @auth_errorEmailSend.
  ///
  /// In en, this message translates to:
  /// **'Error sending email'**
  String get auth_errorEmailSend;

  /// No description provided for @auth_errorGenericSend.
  ///
  /// In en, this message translates to:
  /// **'Error sending'**
  String get auth_errorGenericSend;

  /// No description provided for @auth_termsPrefix.
  ///
  /// In en, this message translates to:
  /// **'By continuing, you accept the '**
  String get auth_termsPrefix;

  /// No description provided for @auth_termsLinkTos.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get auth_termsLinkTos;

  /// No description provided for @auth_termsConjunction.
  ///
  /// In en, this message translates to:
  /// **' and the '**
  String get auth_termsConjunction;

  /// No description provided for @auth_termsLinkPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get auth_termsLinkPrivacy;

  /// No description provided for @auth_forgotPasswordHeader.
  ///
  /// In en, this message translates to:
  /// **'Reset Password'**
  String get auth_forgotPasswordHeader;

  /// No description provided for @auth_forgotPasswordSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your email and we\'ll send you\na link to reset your password.'**
  String get auth_forgotPasswordSubtitle;

  /// No description provided for @auth_ctaSendResetLink.
  ///
  /// In en, this message translates to:
  /// **'Send Reset Link'**
  String get auth_ctaSendResetLink;

  /// No description provided for @auth_toggleQuestionRememberPassword.
  ///
  /// In en, this message translates to:
  /// **'Remember your password? '**
  String get auth_toggleQuestionRememberPassword;

  /// No description provided for @auth_toggleActionBackToLogin.
  ///
  /// In en, this message translates to:
  /// **'Back to login'**
  String get auth_toggleActionBackToLogin;

  /// No description provided for @auth_emailSentHeader.
  ///
  /// In en, this message translates to:
  /// **'Check your inbox'**
  String get auth_emailSentHeader;

  /// No description provided for @auth_emailSentMessage.
  ///
  /// In en, this message translates to:
  /// **'We sent a reset link to\n{email}'**
  String auth_emailSentMessage(String email);

  /// No description provided for @auth_resendCooldown.
  ///
  /// In en, this message translates to:
  /// **'Resend in {seconds}s'**
  String auth_resendCooldown(int seconds);

  /// No description provided for @auth_resendEmail.
  ///
  /// In en, this message translates to:
  /// **'Resend Email'**
  String get auth_resendEmail;

  /// No description provided for @auth_verifyEmailHeader.
  ///
  /// In en, this message translates to:
  /// **'Verify your Email'**
  String get auth_verifyEmailHeader;

  /// No description provided for @auth_verifyEmailMessage.
  ///
  /// In en, this message translates to:
  /// **'We sent a confirmation link to\n{email}'**
  String auth_verifyEmailMessage(String email);

  /// No description provided for @auth_verifyEmailHint.
  ///
  /// In en, this message translates to:
  /// **'Click the link in the email to activate your account,\nthen come back here to sign in.'**
  String get auth_verifyEmailHint;

  /// No description provided for @auth_resendVerification.
  ///
  /// In en, this message translates to:
  /// **'Resend Verification Email'**
  String get auth_resendVerification;

  /// No description provided for @auth_ctaAlreadyVerified.
  ///
  /// In en, this message translates to:
  /// **'I already verified — Sign In'**
  String get auth_ctaAlreadyVerified;

  /// No description provided for @auth_conflictTitleProvider.
  ///
  /// In en, this message translates to:
  /// **'Account {identifier} already linked'**
  String auth_conflictTitleProvider(String identifier);

  /// No description provided for @auth_conflictTitleEmail.
  ///
  /// In en, this message translates to:
  /// **'This email is already registered'**
  String get auth_conflictTitleEmail;

  /// No description provided for @auth_conflictBodyProvider.
  ///
  /// In en, this message translates to:
  /// **'This {identifier} account is linked to another Fluera profile. Continuing will switch to the other profile and you\'ll lose the work done as a guest:'**
  String auth_conflictBodyProvider(String identifier);

  /// No description provided for @auth_conflictBodyEmail.
  ///
  /// In en, this message translates to:
  /// **'You already have a Fluera account with this email. Signing in now will lose the work done as a guest:'**
  String get auth_conflictBodyEmail;

  /// No description provided for @auth_conflictStatCanvases.
  ///
  /// In en, this message translates to:
  /// **'{count} canvas'**
  String auth_conflictStatCanvases(int count);

  /// No description provided for @auth_conflictStatTokens.
  ///
  /// In en, this message translates to:
  /// **'{tokens} AI tokens used'**
  String auth_conflictStatTokens(String tokens);

  /// No description provided for @auth_conflictRestoreHint.
  ///
  /// In en, this message translates to:
  /// **'You can restore canvases from the gallery within 24h.'**
  String get auth_conflictRestoreHint;

  /// No description provided for @auth_conflictUseOtherEmail.
  ///
  /// In en, this message translates to:
  /// **'Use another email'**
  String get auth_conflictUseOtherEmail;

  /// No description provided for @auth_conflictLoginAndDiscard.
  ///
  /// In en, this message translates to:
  /// **'Sign in and discard'**
  String get auth_conflictLoginAndDiscard;

  /// No description provided for @auth_reauthFallbackAccount.
  ///
  /// In en, this message translates to:
  /// **'your account'**
  String get auth_reauthFallbackAccount;

  /// No description provided for @auth_reauthErrorEmptyPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter your password'**
  String get auth_reauthErrorEmptyPassword;

  /// No description provided for @auth_reauthErrorConnection.
  ///
  /// In en, this message translates to:
  /// **'Connection error. Try again.'**
  String get auth_reauthErrorConnection;

  /// No description provided for @auth_reauthTitle.
  ///
  /// In en, this message translates to:
  /// **'Session expired'**
  String get auth_reauthTitle;

  /// No description provided for @auth_reauthBody.
  ///
  /// In en, this message translates to:
  /// **'For security, you need to sign in again to {email}.'**
  String auth_reauthBody(String email);

  /// No description provided for @auth_reauthContinueAsGuest.
  ///
  /// In en, this message translates to:
  /// **'Continue as guest'**
  String get auth_reauthContinueAsGuest;

  /// No description provided for @auth_restoreSuccessSingle.
  ///
  /// In en, this message translates to:
  /// **'Restored 1 canvas 🎉'**
  String get auth_restoreSuccessSingle;

  /// No description provided for @auth_restoreSuccessMulti.
  ///
  /// In en, this message translates to:
  /// **'Restored {count} canvases 🎉'**
  String auth_restoreSuccessMulti(int count);

  /// No description provided for @auth_restoreExpired.
  ///
  /// In en, this message translates to:
  /// **'No canvases to restore (expired after 24h).'**
  String get auth_restoreExpired;

  /// No description provided for @auth_restoreBannerTitle.
  ///
  /// In en, this message translates to:
  /// **'{count} guest canvas pending'**
  String auth_restoreBannerTitle(int count);

  /// No description provided for @auth_restoreBannerBody.
  ///
  /// In en, this message translates to:
  /// **'Restore within {hoursLeft}h or they\'ll be deleted.'**
  String auth_restoreBannerBody(int hoursLeft);

  /// No description provided for @auth_restoreDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get auth_restoreDiscard;

  /// No description provided for @auth_restoreAction.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get auth_restoreAction;

  /// No description provided for @onboarding_heroHeadline.
  ///
  /// In en, this message translates to:
  /// **'The first canvas that learns how you think'**
  String get onboarding_heroHeadline;

  /// No description provided for @onboarding_heroSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Write, draw, and remember — together.\nWrite before you read · Fail to remember better · Repeat at the right moment.'**
  String get onboarding_heroSubtitle;

  /// No description provided for @onboarding_heroCtaPrimary.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get onboarding_heroCtaPrimary;

  /// No description provided for @onboarding_heroSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip tour'**
  String get onboarding_heroSkip;

  /// No description provided for @onboarding_audienceTitle.
  ///
  /// In en, this message translates to:
  /// **'How will you use Fluera?'**
  String get onboarding_audienceTitle;

  /// No description provided for @onboarding_audienceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'We tailor Fluera around what you do.'**
  String get onboarding_audienceSubtitle;

  /// No description provided for @onboarding_audienceStudyTitle.
  ///
  /// In en, this message translates to:
  /// **'For studying'**
  String get onboarding_audienceStudyTitle;

  /// No description provided for @onboarding_audienceStudyBody.
  ///
  /// In en, this message translates to:
  /// **'Med, STEM, law, humanities — anything you need to remember.'**
  String get onboarding_audienceStudyBody;

  /// No description provided for @onboarding_audienceWorkTitle.
  ///
  /// In en, this message translates to:
  /// **'For work'**
  String get onboarding_audienceWorkTitle;

  /// No description provided for @onboarding_audienceWorkBody.
  ///
  /// In en, this message translates to:
  /// **'Research, consulting, writing, design — your second brain.'**
  String get onboarding_audienceWorkBody;

  /// No description provided for @onboarding_audienceTeamTitle.
  ///
  /// In en, this message translates to:
  /// **'With my team'**
  String get onboarding_audienceTeamTitle;

  /// No description provided for @onboarding_audienceTeamBody.
  ///
  /// In en, this message translates to:
  /// **'Studio, agency, lab — think and build together.'**
  String get onboarding_audienceTeamBody;

  /// No description provided for @onboarding_ghostMapHeadline.
  ///
  /// In en, this message translates to:
  /// **'A guess before reading = stronger memory'**
  String get onboarding_ghostMapHeadline;

  /// No description provided for @onboarding_ghostMapHint.
  ///
  /// In en, this message translates to:
  /// **'Watch as the map reveals fragments to integrate in your notes…'**
  String get onboarding_ghostMapHint;

  /// No description provided for @onboarding_ghostMapTryIt.
  ///
  /// In en, this message translates to:
  /// **'Tap a missing node — try answering before Fluera reveals it (hypercorrection effect)'**
  String get onboarding_ghostMapTryIt;

  /// No description provided for @onboarding_ghostMapTapToast.
  ///
  /// In en, this message translates to:
  /// **'💡 You just used the testing effect'**
  String get onboarding_ghostMapTapToast;

  /// No description provided for @onboarding_replayHeadline.
  ///
  /// In en, this message translates to:
  /// **'Never lose a thought'**
  String get onboarding_replayHeadline;

  /// No description provided for @onboarding_replaySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Every stroke is preserved. Time travel through your past notes.'**
  String get onboarding_replaySubtitle;

  /// No description provided for @onboarding_replayDemoPhrase.
  ///
  /// In en, this message translates to:
  /// **'Remember every idea'**
  String get onboarding_replayDemoPhrase;

  /// No description provided for @onboarding_setupTitle.
  ///
  /// In en, this message translates to:
  /// **'A few quick details'**
  String get onboarding_setupTitle;

  /// No description provided for @onboarding_setupNameLabel.
  ///
  /// In en, this message translates to:
  /// **'What should we call you?'**
  String get onboarding_setupNameLabel;

  /// No description provided for @onboarding_setupNamePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Your first name (optional)'**
  String get onboarding_setupNamePlaceholder;

  /// No description provided for @onboarding_setupSubjectLabel.
  ///
  /// In en, this message translates to:
  /// **'What\'s your main subject?'**
  String get onboarding_setupSubjectLabel;

  /// No description provided for @onboarding_setupWorkRoleLabel.
  ///
  /// In en, this message translates to:
  /// **'What do you do?'**
  String get onboarding_setupWorkRoleLabel;

  /// No description provided for @onboarding_setupTeamSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'How big is your team?'**
  String get onboarding_setupTeamSizeLabel;

  /// No description provided for @onboarding_setupSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip — set this up later'**
  String get onboarding_setupSkip;

  /// No description provided for @onboarding_planHeadline.
  ///
  /// In en, this message translates to:
  /// **'Pick what fits you today'**
  String get onboarding_planHeadline;

  /// No description provided for @onboarding_planFreeTitle.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get onboarding_planFreeTitle;

  /// No description provided for @onboarding_planFreeBullets.
  ///
  /// In en, this message translates to:
  /// **'Core canvas · 3 brushes · 3 layers · 1 device · Local-only'**
  String get onboarding_planFreeBullets;

  /// No description provided for @onboarding_planProTitle.
  ///
  /// In en, this message translates to:
  /// **'Pro — €11.99/mo'**
  String get onboarding_planProTitle;

  /// No description provided for @onboarding_planProBulletsStudy.
  ///
  /// In en, this message translates to:
  /// **'Unlimited Ghost Map · Socratic AI on YOUR notes · Time travel · All brushes'**
  String get onboarding_planProBulletsStudy;

  /// No description provided for @onboarding_planProBulletsWork.
  ///
  /// In en, this message translates to:
  /// **'Multiview · Socratic AI on YOUR notes · Cross-device sync · Time travel'**
  String get onboarding_planProBulletsWork;

  /// No description provided for @onboarding_planProBulletsTeam.
  ///
  /// In en, this message translates to:
  /// **'Everything in Pro · Early access to Team workspaces'**
  String get onboarding_planProBulletsTeam;

  /// No description provided for @onboarding_planTrialCta.
  ///
  /// In en, this message translates to:
  /// **'Try Pro free for 7 days'**
  String get onboarding_planTrialCta;

  /// No description provided for @onboarding_planTrialCtaA.
  ///
  /// In en, this message translates to:
  /// **'Try Pro free for 7 days'**
  String get onboarding_planTrialCtaA;

  /// No description provided for @onboarding_planTrialCtaB.
  ///
  /// In en, this message translates to:
  /// **'Start 7-day free trial · then €11.99/mo'**
  String get onboarding_planTrialCtaB;

  /// No description provided for @onboarding_planTrialCtaC.
  ///
  /// In en, this message translates to:
  /// **'Unlock everything · 7 days free'**
  String get onboarding_planTrialCtaC;

  /// No description provided for @onboarding_planTrialBadge.
  ///
  /// In en, this message translates to:
  /// **'Try Pro 7 days free'**
  String get onboarding_planTrialBadge;

  /// No description provided for @onboarding_planTrialContextMessage.
  ///
  /// In en, this message translates to:
  /// **'Try Pro 7 days free — keep Fluera if you love it.'**
  String get onboarding_planTrialContextMessage;

  /// No description provided for @onboarding_planContinueFree.
  ///
  /// In en, this message translates to:
  /// **'Continue with Free'**
  String get onboarding_planContinueFree;

  /// No description provided for @onboarding_planGreeting.
  ///
  /// In en, this message translates to:
  /// **'Ready, {name}?'**
  String onboarding_planGreeting(String name);

  /// No description provided for @onboarding_planPriceFootnote.
  ///
  /// In en, this message translates to:
  /// **'Cancel anytime in Settings · No charge during the trial'**
  String get onboarding_planPriceFootnote;

  /// No description provided for @onboarding_skipConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Skip the tour?'**
  String get onboarding_skipConfirmTitle;

  /// No description provided for @onboarding_skipConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'You can always replay the tour from Settings → About.'**
  String get onboarding_skipConfirmBody;

  /// No description provided for @onboarding_skipConfirmStay.
  ///
  /// In en, this message translates to:
  /// **'Keep going'**
  String get onboarding_skipConfirmStay;

  /// No description provided for @onboarding_skipConfirmLeave.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get onboarding_skipConfirmLeave;

  /// No description provided for @onboarding_commonContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get onboarding_commonContinue;

  /// No description provided for @onboarding_commonNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get onboarding_commonNext;

  /// No description provided for @onboarding_commonSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get onboarding_commonSkip;

  /// No description provided for @onboarding_commonBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get onboarding_commonBack;

  /// No description provided for @gallery_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get gallery_cancel;

  /// No description provided for @gallery_save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get gallery_save;

  /// No description provided for @gallery_delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get gallery_delete;

  /// No description provided for @gallery_deleteAll.
  ///
  /// In en, this message translates to:
  /// **'Delete all'**
  String get gallery_deleteAll;

  /// No description provided for @gallery_rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get gallery_rename;

  /// No description provided for @gallery_renameFolder.
  ///
  /// In en, this message translates to:
  /// **'Rename folder'**
  String get gallery_renameFolder;

  /// No description provided for @gallery_duplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get gallery_duplicate;

  /// No description provided for @gallery_multiSelect.
  ///
  /// In en, this message translates to:
  /// **'Multiple selection'**
  String get gallery_multiSelect;

  /// No description provided for @gallery_moveToFolder.
  ///
  /// In en, this message translates to:
  /// **'Move to folder'**
  String get gallery_moveToFolder;

  /// No description provided for @gallery_titleLabel.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get gallery_titleLabel;

  /// No description provided for @gallery_folderNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Folder name'**
  String get gallery_folderNameLabel;

  /// No description provided for @gallery_newFolderTitle.
  ///
  /// In en, this message translates to:
  /// **'New folder'**
  String get gallery_newFolderTitle;

  /// No description provided for @gallery_newFolderTooltip.
  ///
  /// In en, this message translates to:
  /// **'New Folder'**
  String get gallery_newFolderTooltip;

  /// No description provided for @gallery_newCanvas.
  ///
  /// In en, this message translates to:
  /// **'New Canvas'**
  String get gallery_newCanvas;

  /// No description provided for @gallery_untitled.
  ///
  /// In en, this message translates to:
  /// **'Untitled'**
  String get gallery_untitled;

  /// No description provided for @gallery_titleMyCanvases.
  ///
  /// In en, this message translates to:
  /// **'My Canvases'**
  String get gallery_titleMyCanvases;

  /// No description provided for @gallery_tooltipSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get gallery_tooltipSelectAll;

  /// No description provided for @gallery_tooltipDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get gallery_tooltipDelete;

  /// No description provided for @gallery_tooltipListView.
  ///
  /// In en, this message translates to:
  /// **'List view'**
  String get gallery_tooltipListView;

  /// No description provided for @gallery_tooltipGridView.
  ///
  /// In en, this message translates to:
  /// **'Grid view'**
  String get gallery_tooltipGridView;

  /// No description provided for @gallery_tooltipCloseSearch.
  ///
  /// In en, this message translates to:
  /// **'Close search'**
  String get gallery_tooltipCloseSearch;

  /// No description provided for @gallery_tooltipSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get gallery_tooltipSearch;

  /// No description provided for @gallery_sortModifiedNewest.
  ///
  /// In en, this message translates to:
  /// **'Modified — newest first'**
  String get gallery_sortModifiedNewest;

  /// No description provided for @gallery_sortModifiedOldest.
  ///
  /// In en, this message translates to:
  /// **'Modified — oldest first'**
  String get gallery_sortModifiedOldest;

  /// No description provided for @gallery_deleteConfirmSingle.
  ///
  /// In en, this message translates to:
  /// **'Delete 1 canvas?'**
  String get gallery_deleteConfirmSingle;

  /// No description provided for @gallery_deleteConfirmMulti.
  ///
  /// In en, this message translates to:
  /// **'Delete {count} canvases?'**
  String gallery_deleteConfirmMulti(int count);

  /// No description provided for @gallery_deleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This action cannot be undone.'**
  String get gallery_deleteConfirmBody;

  /// No description provided for @gallery_deleteConfirmCanvasTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete canvas?'**
  String get gallery_deleteConfirmCanvasTitle;

  /// No description provided for @gallery_deleteConfirmCanvasBody.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" will be permanently deleted.\nThis action cannot be undone.'**
  String gallery_deleteConfirmCanvasBody(String title);

  /// No description provided for @gallery_deletedCanvasToast.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" deleted'**
  String gallery_deletedCanvasToast(String title);

  /// No description provided for @gallery_deletedSingle.
  ///
  /// In en, this message translates to:
  /// **'1 canvas deleted'**
  String get gallery_deletedSingle;

  /// No description provided for @gallery_deletedMulti.
  ///
  /// In en, this message translates to:
  /// **'{count} canvases deleted'**
  String gallery_deletedMulti(int count);

  /// No description provided for @gallery_folderEmptyMoveNote.
  ///
  /// In en, this message translates to:
  /// **'Contents are moved to the parent folder'**
  String get gallery_folderEmptyMoveNote;

  /// No description provided for @gallery_moveDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Move \"{title}\"'**
  String gallery_moveDialogTitle(String title);

  /// No description provided for @gallery_emptyFolderTitle.
  ///
  /// In en, this message translates to:
  /// **'This Folder is Empty'**
  String get gallery_emptyFolderTitle;

  /// No description provided for @gallery_emptyGalleryTitle.
  ///
  /// In en, this message translates to:
  /// **'No Canvases Yet'**
  String get gallery_emptyGalleryTitle;

  /// No description provided for @gallery_emptyAddCanvasHere.
  ///
  /// In en, this message translates to:
  /// **'Add Canvas Here'**
  String get gallery_emptyAddCanvasHere;

  /// No description provided for @gallery_emptyCreateFirstCanvas.
  ///
  /// In en, this message translates to:
  /// **'Create Your First Canvas'**
  String get gallery_emptyCreateFirstCanvas;

  /// No description provided for @gallery_create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get gallery_create;

  /// No description provided for @gallery_folderNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Math Notes'**
  String get gallery_folderNameHint;

  /// No description provided for @gallery_duplicateSuffix.
  ///
  /// In en, this message translates to:
  /// **'(copy)'**
  String get gallery_duplicateSuffix;

  /// No description provided for @gallery_selectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String gallery_selectedCount(int count);

  /// No description provided for @gallery_canvasCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 canvas} other{{count} canvases}}'**
  String gallery_canvasCount(int count);

  /// No description provided for @gallery_tooltipBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get gallery_tooltipBack;

  /// No description provided for @gallery_tooltipSort.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get gallery_tooltipSort;

  /// No description provided for @gallery_tooltipMoveToFolderShort.
  ///
  /// In en, this message translates to:
  /// **'Move to folder'**
  String get gallery_tooltipMoveToFolderShort;

  /// No description provided for @gallery_homeBreadcrumb.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get gallery_homeBreadcrumb;

  /// No description provided for @gallery_sortNameAsc.
  ///
  /// In en, this message translates to:
  /// **'Name A–Z'**
  String get gallery_sortNameAsc;

  /// No description provided for @gallery_sortNameDesc.
  ///
  /// In en, this message translates to:
  /// **'Name Z–A'**
  String get gallery_sortNameDesc;

  /// No description provided for @gallery_searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search canvases…'**
  String get gallery_searchHint;

  /// No description provided for @gallery_searchNoResults.
  ///
  /// In en, this message translates to:
  /// **'No canvases match \"{query}\"'**
  String gallery_searchNoResults(String query);

  /// No description provided for @gallery_rootFolder.
  ///
  /// In en, this message translates to:
  /// **'Root (no folder)'**
  String get gallery_rootFolder;

  /// No description provided for @gallery_moveDialogTitleMulti.
  ///
  /// In en, this message translates to:
  /// **'Move {count, plural, =1{1 canvas} other{{count} canvases}}'**
  String gallery_moveDialogTitleMulti(int count);

  /// No description provided for @gallery_emptyFolderBody.
  ///
  /// In en, this message translates to:
  /// **'Add a canvas or move one here.'**
  String get gallery_emptyFolderBody;

  /// No description provided for @gallery_emptyGalleryBody.
  ///
  /// In en, this message translates to:
  /// **'Create your first canvas to start drawing.\nYour creations will appear here.'**
  String get gallery_emptyGalleryBody;

  /// No description provided for @gallery_paperGrid.
  ///
  /// In en, this message translates to:
  /// **'Grid'**
  String get gallery_paperGrid;

  /// No description provided for @gallery_paperDots.
  ///
  /// In en, this message translates to:
  /// **'Dots'**
  String get gallery_paperDots;

  /// No description provided for @gallery_share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get gallery_share;

  /// No description provided for @createSheet_title.
  ///
  /// In en, this message translates to:
  /// **'New canvas'**
  String get createSheet_title;

  /// No description provided for @createSheet_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Pick a template to get started'**
  String get createSheet_subtitle;

  /// No description provided for @createSheet_titleLabel.
  ///
  /// In en, this message translates to:
  /// **'Canvas title'**
  String get createSheet_titleLabel;

  /// No description provided for @createSheet_titleHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Physics — Waves and Oscillations'**
  String get createSheet_titleHint;

  /// No description provided for @createSheet_preview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get createSheet_preview;

  /// No description provided for @createSheet_background.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get createSheet_background;

  /// No description provided for @createSheet_paperType.
  ///
  /// In en, this message translates to:
  /// **'Paper type'**
  String get createSheet_paperType;

  /// No description provided for @createSheet_create.
  ///
  /// In en, this message translates to:
  /// **'Create canvas'**
  String get createSheet_create;

  /// No description provided for @createSheet_templateLabel.
  ///
  /// In en, this message translates to:
  /// **'Template'**
  String get createSheet_templateLabel;

  /// No description provided for @createSheet_untitledCanvas.
  ///
  /// In en, this message translates to:
  /// **'Untitled canvas'**
  String get createSheet_untitledCanvas;

  /// No description provided for @createSheet_customColor.
  ///
  /// In en, this message translates to:
  /// **'Custom color'**
  String get createSheet_customColor;

  /// No description provided for @createSheet_courseStructure.
  ///
  /// In en, this message translates to:
  /// **'Course structure'**
  String get createSheet_courseStructure;

  /// No description provided for @createSheet_addSection.
  ///
  /// In en, this message translates to:
  /// **'Add section'**
  String get createSheet_addSection;

  /// No description provided for @createSheet_maxSections.
  ///
  /// In en, this message translates to:
  /// **'Max 12'**
  String get createSheet_maxSections;

  /// No description provided for @createSheet_infiniteCanvasOption.
  ///
  /// In en, this message translates to:
  /// **'Infinite canvas · no structure'**
  String get createSheet_infiniteCanvasOption;

  /// No description provided for @createSheet_courseStructureHint.
  ///
  /// In en, this message translates to:
  /// **'Use only if you already know the course syllabus'**
  String get createSheet_courseStructureHint;

  /// No description provided for @createSheet_memoryPalaceHint.
  ///
  /// In en, this message translates to:
  /// **'These are empty containers only. The Memory Palace is built by what you write inside — not by the labels.'**
  String get createSheet_memoryPalaceHint;

  /// No description provided for @createSheet_a4Description.
  ///
  /// In en, this message translates to:
  /// **'A4 Portrait · 595 × 842px · blank · generate content yourself'**
  String get createSheet_a4Description;

  /// No description provided for @createSheet_chapterHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Chapter {index}'**
  String createSheet_chapterHint(int index);

  /// No description provided for @createSheet_defaultTitle.
  ///
  /// In en, this message translates to:
  /// **'Notes — {day} {month}'**
  String createSheet_defaultTitle(int day, String month);

  /// No description provided for @imageEditor_ocrInProgress.
  ///
  /// In en, this message translates to:
  /// **'Recognizing text...'**
  String get imageEditor_ocrInProgress;

  /// No description provided for @imageEditor_ocrNoText.
  ///
  /// In en, this message translates to:
  /// **'No text found in image'**
  String get imageEditor_ocrNoText;

  /// No description provided for @imageEditor_textCopiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Text copied to clipboard'**
  String get imageEditor_textCopiedToClipboard;

  /// No description provided for @imageEditor_textCopied.
  ///
  /// In en, this message translates to:
  /// **'Text copied'**
  String get imageEditor_textCopied;

  /// No description provided for @imageEditor_copyAll.
  ///
  /// In en, this message translates to:
  /// **'Copy all'**
  String get imageEditor_copyAll;

  /// No description provided for @imageEditor_copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get imageEditor_copy;

  /// No description provided for @imageEditor_addOverlay.
  ///
  /// In en, this message translates to:
  /// **'Add overlay'**
  String get imageEditor_addOverlay;

  /// No description provided for @imageEditor_autoEnhance.
  ///
  /// In en, this message translates to:
  /// **'Auto-Enhance'**
  String get imageEditor_autoEnhance;

  /// No description provided for @imageEditor_resetCurve.
  ///
  /// In en, this message translates to:
  /// **'Reset Curve'**
  String get imageEditor_resetCurve;

  /// No description provided for @imageEditor_reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get imageEditor_reset;

  /// No description provided for @imageEditor_addText.
  ///
  /// In en, this message translates to:
  /// **'Add Text'**
  String get imageEditor_addText;

  /// No description provided for @imageEditor_export.
  ///
  /// In en, this message translates to:
  /// **'Export {format}'**
  String imageEditor_export(String format);

  /// No description provided for @imageEditor_textInputHint.
  ///
  /// In en, this message translates to:
  /// **'Enter text...'**
  String get imageEditor_textInputHint;

  /// No description provided for @imageEditor_fontSans.
  ///
  /// In en, this message translates to:
  /// **'Sans'**
  String get imageEditor_fontSans;

  /// No description provided for @imageEditor_fontSerif.
  ///
  /// In en, this message translates to:
  /// **'Serif'**
  String get imageEditor_fontSerif;

  /// No description provided for @imageEditor_fontMono.
  ///
  /// In en, this message translates to:
  /// **'Mono'**
  String get imageEditor_fontMono;

  /// No description provided for @imageEditor_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get imageEditor_cancel;

  /// No description provided for @imageEditor_add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get imageEditor_add;

  /// No description provided for @imageEditor_color.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get imageEditor_color;

  /// No description provided for @imageEditor_size.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get imageEditor_size;

  /// No description provided for @examOverlay_setupHeader.
  ///
  /// In en, this message translates to:
  /// **'What do you want to be tested on?'**
  String get examOverlay_setupHeader;

  /// No description provided for @examOverlay_chipAllTopics.
  ///
  /// In en, this message translates to:
  /// **'🗂 All'**
  String get examOverlay_chipAllTopics;

  /// No description provided for @examOverlay_languageLabel.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get examOverlay_languageLabel;

  /// No description provided for @examOverlay_questionsLabel.
  ///
  /// In en, this message translates to:
  /// **'Questions'**
  String get examOverlay_questionsLabel;

  /// No description provided for @examOverlay_timerPerQuestion.
  ///
  /// In en, this message translates to:
  /// **'Timer per question ({seconds}s)'**
  String examOverlay_timerPerQuestion(int seconds);

  /// No description provided for @examOverlay_closeExam.
  ///
  /// In en, this message translates to:
  /// **'Close exam'**
  String get examOverlay_closeExam;

  /// No description provided for @examOverlay_back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get examOverlay_back;

  /// No description provided for @examOverlay_next.
  ///
  /// In en, this message translates to:
  /// **'Next →'**
  String get examOverlay_next;

  /// No description provided for @examOverlay_seeResults.
  ///
  /// In en, this message translates to:
  /// **'See results 🎓'**
  String get examOverlay_seeResults;

  /// No description provided for @examOverlay_submit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get examOverlay_submit;

  /// No description provided for @examOverlay_reveal.
  ///
  /// In en, this message translates to:
  /// **'Reveal'**
  String get examOverlay_reveal;

  /// No description provided for @examOverlay_understood.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get examOverlay_understood;

  /// No description provided for @examOverlay_resumeNow.
  ///
  /// In en, this message translates to:
  /// **'Resume now'**
  String get examOverlay_resumeNow;

  /// No description provided for @examOverlay_correctAnswerLabel.
  ///
  /// In en, this message translates to:
  /// **'Correct answer:'**
  String get examOverlay_correctAnswerLabel;

  /// No description provided for @examOverlay_chunkCompleted.
  ///
  /// In en, this message translates to:
  /// **'Block {chunk}/{total} completed'**
  String examOverlay_chunkCompleted(int chunk, int total);

  /// No description provided for @examOverlay_sessionHistory.
  ///
  /// In en, this message translates to:
  /// **'Session history'**
  String get examOverlay_sessionHistory;

  /// No description provided for @examOverlay_confidenceTitle.
  ///
  /// In en, this message translates to:
  /// **'How confident are you?'**
  String get examOverlay_confidenceTitle;

  /// No description provided for @examOverlay_confidenceHint.
  ///
  /// In en, this message translates to:
  /// **'Be honest: mistakes made at high confidence are remembered 3× more'**
  String get examOverlay_confidenceHint;

  /// No description provided for @examOverlay_confidence1.
  ///
  /// In en, this message translates to:
  /// **'Guessing'**
  String get examOverlay_confidence1;

  /// No description provided for @examOverlay_confidence2.
  ///
  /// In en, this message translates to:
  /// **'Not sure'**
  String get examOverlay_confidence2;

  /// No description provided for @examOverlay_confidence3.
  ///
  /// In en, this message translates to:
  /// **'More or less'**
  String get examOverlay_confidence3;

  /// No description provided for @examOverlay_confidence4.
  ///
  /// In en, this message translates to:
  /// **'Quite certain'**
  String get examOverlay_confidence4;

  /// No description provided for @examOverlay_confidence5.
  ///
  /// In en, this message translates to:
  /// **'Absolutely sure'**
  String get examOverlay_confidence5;

  /// No description provided for @examOverlay_confidenceA11y.
  ///
  /// In en, this message translates to:
  /// **'Confidence {level} of 5: {label}'**
  String examOverlay_confidenceA11y(int level, String label);

  /// No description provided for @examOverlay_whyConfidenceMatters.
  ///
  /// In en, this message translates to:
  /// **'Why your confidence matters'**
  String get examOverlay_whyConfidenceMatters;

  /// No description provided for @examOverlay_whyConfidenceBody.
  ///
  /// In en, this message translates to:
  /// **'Before answering we ask how confident you are on a 1-5 scale.'**
  String get examOverlay_whyConfidenceBody;

  /// No description provided for @examOverlay_whyConfidenceWarning.
  ///
  /// In en, this message translates to:
  /// **'Don\'t cheat. Faking low confidence to \"save face\" cancels the benefit.'**
  String get examOverlay_whyConfidenceWarning;

  /// No description provided for @examOverlay_bookmarkRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove from bookmarks'**
  String get examOverlay_bookmarkRemove;

  /// No description provided for @examOverlay_bookmarkAdd.
  ///
  /// In en, this message translates to:
  /// **'Bookmark for later review'**
  String get examOverlay_bookmarkAdd;

  /// No description provided for @examOverlay_typeOpenEnded.
  ///
  /// In en, this message translates to:
  /// **'OPEN ANSWER'**
  String get examOverlay_typeOpenEnded;

  /// No description provided for @examOverlay_typeMultipleChoice.
  ///
  /// In en, this message translates to:
  /// **'MULTIPLE CHOICE'**
  String get examOverlay_typeMultipleChoice;

  /// No description provided for @examOverlay_typeTrueFalse.
  ///
  /// In en, this message translates to:
  /// **'TRUE / FALSE'**
  String get examOverlay_typeTrueFalse;

  /// No description provided for @examOverlay_typeFormulaRecall.
  ///
  /// In en, this message translates to:
  /// **'FORMULA'**
  String get examOverlay_typeFormulaRecall;

  /// No description provided for @examOverlay_true.
  ///
  /// In en, this message translates to:
  /// **'True'**
  String get examOverlay_true;

  /// No description provided for @examOverlay_false.
  ///
  /// In en, this message translates to:
  /// **'False'**
  String get examOverlay_false;

  /// No description provided for @examOverlay_writeToRememberHint.
  ///
  /// In en, this message translates to:
  /// **'Write here to memorize better...'**
  String get examOverlay_writeToRememberHint;

  /// No description provided for @examOverlay_outcomeCorrectMsg.
  ///
  /// In en, this message translates to:
  /// **'Your effort worked!'**
  String get examOverlay_outcomeCorrectMsg;

  /// No description provided for @examOverlay_outcomePartialMsg.
  ///
  /// In en, this message translates to:
  /// **'Almost there — keep going'**
  String get examOverlay_outcomePartialMsg;

  /// No description provided for @examOverlay_outcomeIncorrectMsg.
  ///
  /// In en, this message translates to:
  /// **'Every mistake makes a stronger connection'**
  String get examOverlay_outcomeIncorrectMsg;

  /// No description provided for @examOverlay_outcomeSkippedMsg.
  ///
  /// In en, this message translates to:
  /// **'You\'ll come back to it better prepared'**
  String get examOverlay_outcomeSkippedMsg;

  /// No description provided for @examOverlay_outcomeEvaluating.
  ///
  /// In en, this message translates to:
  /// **'Evaluating...'**
  String get examOverlay_outcomeEvaluating;

  /// No description provided for @chatOverlay_header.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get chatOverlay_header;

  /// No description provided for @chatOverlay_tooltipBackToChat.
  ///
  /// In en, this message translates to:
  /// **'Back to chat'**
  String get chatOverlay_tooltipBackToChat;

  /// No description provided for @chatOverlay_tooltipHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get chatOverlay_tooltipHistory;

  /// No description provided for @chatOverlay_tooltipNewChat.
  ///
  /// In en, this message translates to:
  /// **'New chat'**
  String get chatOverlay_tooltipNewChat;

  /// No description provided for @chatOverlay_unavailableAction.
  ///
  /// In en, this message translates to:
  /// **'This action is not available in this context.'**
  String get chatOverlay_unavailableAction;

  /// No description provided for @chatOverlay_retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get chatOverlay_retry;

  /// No description provided for @chatOverlay_historyLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load history'**
  String get chatOverlay_historyLoadError;

  /// No description provided for @chatOverlay_historyEmpty.
  ///
  /// In en, this message translates to:
  /// **'No saved conversations'**
  String get chatOverlay_historyEmpty;

  /// No description provided for @chatOverlay_timeNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get chatOverlay_timeNow;

  /// No description provided for @branchExplorer_emptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No alternatives yet'**
  String get branchExplorer_emptyTitle;

  /// No description provided for @branchExplorer_emptyBody.
  ///
  /// In en, this message translates to:
  /// **'During Time Travel, pick a past moment and tap \"Explore an alternative\" to try a different approach without losing your work.'**
  String get branchExplorer_emptyBody;

  /// No description provided for @branchExplorer_primaryBranch.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get branchExplorer_primaryBranch;

  /// No description provided for @branchExplorer_main.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get branchExplorer_main;

  /// No description provided for @branchExplorer_parent.
  ///
  /// In en, this message translates to:
  /// **'Born from'**
  String get branchExplorer_parent;

  /// No description provided for @branchExplorer_active.
  ///
  /// In en, this message translates to:
  /// **'You are here'**
  String get branchExplorer_active;

  /// No description provided for @branchExplorer_new.
  ///
  /// In en, this message translates to:
  /// **'New alternative'**
  String get branchExplorer_new;

  /// No description provided for @branchExplorer_rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get branchExplorer_rename;

  /// No description provided for @branchExplorer_renameBranch.
  ///
  /// In en, this message translates to:
  /// **'Rename alternative'**
  String get branchExplorer_renameBranch;

  /// No description provided for @branchExplorer_editDescription.
  ///
  /// In en, this message translates to:
  /// **'Edit description'**
  String get branchExplorer_editDescription;

  /// No description provided for @branchExplorer_branchDescription.
  ///
  /// In en, this message translates to:
  /// **'Alternative description'**
  String get branchExplorer_branchDescription;

  /// No description provided for @branchExplorer_duplicate.
  ///
  /// In en, this message translates to:
  /// **'Copy to new alternative'**
  String get branchExplorer_duplicate;

  /// No description provided for @branchExplorer_delete.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get branchExplorer_delete;

  /// No description provided for @branchExplorer_deleteForever.
  ///
  /// In en, this message translates to:
  /// **'Archive permanently'**
  String get branchExplorer_deleteForever;

  /// No description provided for @branchExplorer_merge.
  ///
  /// In en, this message translates to:
  /// **'Replace Original'**
  String get branchExplorer_merge;

  /// No description provided for @branchExplorer_deleteAfterMerge.
  ///
  /// In en, this message translates to:
  /// **'Archive this alternative after replacing'**
  String get branchExplorer_deleteAfterMerge;

  /// No description provided for @branchExplorer_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get branchExplorer_cancel;

  /// No description provided for @branchExplorer_save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get branchExplorer_save;

  /// No description provided for @branchExplorer_branchNameHint.
  ///
  /// In en, this message translates to:
  /// **'Alternative name'**
  String get branchExplorer_branchNameHint;

  /// No description provided for @branchExplorer_warningStrokes.
  ///
  /// In en, this message translates to:
  /// **'All drawings and strokes'**
  String get branchExplorer_warningStrokes;

  /// No description provided for @branchExplorer_warningSnapshots.
  ///
  /// In en, this message translates to:
  /// **'Canvas snapshots'**
  String get branchExplorer_warningSnapshots;

  /// No description provided for @branchExplorer_title.
  ///
  /// In en, this message translates to:
  /// **'Explored alternatives'**
  String get branchExplorer_title;

  /// No description provided for @branchExplorer_mainCanvasLabel.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get branchExplorer_mainCanvasLabel;

  /// No description provided for @branchExplorer_replaceConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Replace Original with this alternative?'**
  String get branchExplorer_replaceConfirmTitle;

  /// No description provided for @branchExplorer_replaceConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'The Original will be replaced with the contents of \"{name}\". This action cannot be undone.'**
  String branchExplorer_replaceConfirmBody(String name);

  /// No description provided for @branchExplorer_archiveConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Archive \"{name}\"?'**
  String branchExplorer_archiveConfirmTitle(String name);

  /// No description provided for @branchExplorer_archiveConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This alternative will be removed from the list. Your Original is not affected.'**
  String get branchExplorer_archiveConfirmBody;

  /// No description provided for @branchExplorer_archiveWithChildren.
  ///
  /// In en, this message translates to:
  /// **'Sub-alternatives will be archived too.'**
  String get branchExplorer_archiveWithChildren;

  /// No description provided for @branchExplorer_descriptionHint.
  ///
  /// In en, this message translates to:
  /// **'Why are you exploring this alternative?'**
  String get branchExplorer_descriptionHint;

  /// No description provided for @branchExplorer_youAreOnActiveWarning.
  ///
  /// In en, this message translates to:
  /// **'You are currently on this alternative. You will be switched back to the Original.'**
  String get branchExplorer_youAreOnActiveWarning;

  /// No description provided for @branchExplorer_timeTravelHistory.
  ///
  /// In en, this message translates to:
  /// **'Time Travel history'**
  String get branchExplorer_timeTravelHistory;

  /// No description provided for @branchExplorer_subBranchesCascade.
  ///
  /// In en, this message translates to:
  /// **'Sub-alternatives (cascade)'**
  String get branchExplorer_subBranchesCascade;

  /// No description provided for @checkpoint_title.
  ///
  /// In en, this message translates to:
  /// **'My checkpoints'**
  String get checkpoint_title;

  /// No description provided for @checkpoint_emptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No checkpoints yet'**
  String get checkpoint_emptyTitle;

  /// No description provided for @checkpoint_emptyBody.
  ///
  /// In en, this message translates to:
  /// **'Save a checkpoint to bookmark this moment. You can come back to it anytime.'**
  String get checkpoint_emptyBody;

  /// No description provided for @checkpoint_saveTitle.
  ///
  /// In en, this message translates to:
  /// **'Save checkpoint'**
  String get checkpoint_saveTitle;

  /// No description provided for @checkpoint_savedAt.
  ///
  /// In en, this message translates to:
  /// **'Saved {date}'**
  String checkpoint_savedAt(String date);

  /// No description provided for @checkpoint_restore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get checkpoint_restore;

  /// No description provided for @checkpoint_archive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get checkpoint_archive;

  /// No description provided for @checkpoint_nameHint.
  ///
  /// In en, this message translates to:
  /// **'Checkpoint name…'**
  String get checkpoint_nameHint;

  /// No description provided for @checkpoint_counterFree.
  ///
  /// In en, this message translates to:
  /// **'Checkpoints used: {used}/{max} on this canvas'**
  String checkpoint_counterFree(int used, int max);

  /// No description provided for @checkpoint_limitReachedTitle.
  ///
  /// In en, this message translates to:
  /// **'You\'ve reached the Free limit'**
  String get checkpoint_limitReachedTitle;

  /// No description provided for @checkpoint_limitReachedBody.
  ///
  /// In en, this message translates to:
  /// **'Free includes 3 checkpoints per canvas. Plus unlocks them all for €5.99/month — or archive an existing checkpoint to free a slot.'**
  String get checkpoint_limitReachedBody;

  /// No description provided for @checkpoint_upgradeToPlus.
  ///
  /// In en, this message translates to:
  /// **'Go Plus'**
  String get checkpoint_upgradeToPlus;

  /// No description provided for @checkpoint_archiveExisting.
  ///
  /// In en, this message translates to:
  /// **'Archive an existing checkpoint'**
  String get checkpoint_archiveExisting;

  /// No description provided for @timeTravelMenu_title.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get timeTravelMenu_title;

  /// No description provided for @timeTravelMenu_saveCheckpoint.
  ///
  /// In en, this message translates to:
  /// **'Save checkpoint here'**
  String get timeTravelMenu_saveCheckpoint;

  /// No description provided for @timeTravelMenu_viewCheckpoints.
  ///
  /// In en, this message translates to:
  /// **'View my checkpoints'**
  String get timeTravelMenu_viewCheckpoints;

  /// No description provided for @timeTravelMenu_exploreAlternative.
  ///
  /// In en, this message translates to:
  /// **'Explore an alternative from here'**
  String get timeTravelMenu_exploreAlternative;

  /// No description provided for @timeTravelMenu_viewAlternatives.
  ///
  /// In en, this message translates to:
  /// **'View explored alternatives'**
  String get timeTravelMenu_viewAlternatives;

  /// No description provided for @advancedMode_mergeToggleTitle.
  ///
  /// In en, this message translates to:
  /// **'Show advanced merge options'**
  String get advancedMode_mergeToggleTitle;

  /// No description provided for @advancedMode_mergeToggleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Adds the classic merge UI to alternatives. For power users familiar with git-style branching.'**
  String get advancedMode_mergeToggleSubtitle;

  /// No description provided for @featuresSheet_chipLabel.
  ///
  /// In en, this message translates to:
  /// **'Features'**
  String get featuresSheet_chipLabel;

  /// No description provided for @featuresSheet_title.
  ///
  /// In en, this message translates to:
  /// **'What Fluera can do'**
  String get featuresSheet_title;

  /// No description provided for @featuresSheet_subtitle.
  ///
  /// In en, this message translates to:
  /// **'The cognitive features available on the canvas. Tap a card to try it.'**
  String get featuresSheet_subtitle;

  /// No description provided for @featuresSheet_proBadge.
  ///
  /// In en, this message translates to:
  /// **'Pro'**
  String get featuresSheet_proBadge;

  /// No description provided for @featuresSheet_ghostMapName.
  ///
  /// In en, this message translates to:
  /// **'Ghost Map'**
  String get featuresSheet_ghostMapName;

  /// No description provided for @featuresSheet_ghostMapDesc.
  ///
  /// In en, this message translates to:
  /// **'See the gaps in your knowledge before reading.'**
  String get featuresSheet_ghostMapDesc;

  /// No description provided for @featuresSheet_socraticName.
  ///
  /// In en, this message translates to:
  /// **'Socratic Mode'**
  String get featuresSheet_socraticName;

  /// No description provided for @featuresSheet_socraticDesc.
  ///
  /// In en, this message translates to:
  /// **'Fluera quizzes you on your notes — no scoring.'**
  String get featuresSheet_socraticDesc;

  /// No description provided for @featuresSheet_examName.
  ///
  /// In en, this message translates to:
  /// **'Exam Session'**
  String get featuresSheet_examName;

  /// No description provided for @featuresSheet_examDesc.
  ///
  /// In en, this message translates to:
  /// **'Simulate a closed-book oral exam on your canvas.'**
  String get featuresSheet_examDesc;

  /// No description provided for @featuresSheet_fogName.
  ///
  /// In en, this message translates to:
  /// **'Fog of War'**
  String get featuresSheet_fogName;

  /// No description provided for @featuresSheet_fogDesc.
  ///
  /// In en, this message translates to:
  /// **'Covers the doc during exam to force active recall.'**
  String get featuresSheet_fogDesc;

  /// No description provided for @featuresSheet_bridgesName.
  ///
  /// In en, this message translates to:
  /// **'Cross-Zone Bridges'**
  String get featuresSheet_bridgesName;

  /// No description provided for @featuresSheet_bridgesDesc.
  ///
  /// In en, this message translates to:
  /// **'Connect concepts across different clusters of the canvas.'**
  String get featuresSheet_bridgesDesc;

  /// No description provided for @featuresSheet_timeTravelName.
  ///
  /// In en, this message translates to:
  /// **'Time Travel'**
  String get featuresSheet_timeTravelName;

  /// No description provided for @featuresSheet_timeTravelDesc.
  ///
  /// In en, this message translates to:
  /// **'Replay your study in playback, stroke by stroke.'**
  String get featuresSheet_timeTravelDesc;

  /// No description provided for @radialMode_settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Radial mode'**
  String get radialMode_settingsTitle;

  /// No description provided for @radialMode_settingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Replace the toolbar with a radial menu summoned by long-press. Best with stylus.'**
  String get radialMode_settingsSubtitle;

  /// No description provided for @radialMode_coachmarkTitle.
  ///
  /// In en, this message translates to:
  /// **'Radial mode'**
  String get radialMode_coachmarkTitle;

  /// No description provided for @radialMode_coachmarkBody.
  ///
  /// In en, this message translates to:
  /// **'If you use a stylus, try radial mode: Settings → Advanced studio.'**
  String get radialMode_coachmarkBody;

  /// No description provided for @pdfBookmark_pageBookmarked.
  ///
  /// In en, this message translates to:
  /// **'Page {page} bookmarked'**
  String pdfBookmark_pageBookmarked(int page);

  /// No description provided for @pdfBookmark_pageRemoved.
  ///
  /// In en, this message translates to:
  /// **'Page {page} bookmark removed'**
  String pdfBookmark_pageRemoved(int page);

  /// No description provided for @pdfBookmark_undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get pdfBookmark_undo;

  /// No description provided for @pdfBookmark_noteDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Note - Page {page}'**
  String pdfBookmark_noteDialogTitle(int page);

  /// No description provided for @pdfBookmark_noteHint.
  ///
  /// In en, this message translates to:
  /// **'Add a note...'**
  String get pdfBookmark_noteHint;

  /// No description provided for @pdfBookmark_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get pdfBookmark_cancel;

  /// No description provided for @pdfBookmark_save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get pdfBookmark_save;

  /// No description provided for @pdfBookmark_tooltipPrev.
  ///
  /// In en, this message translates to:
  /// **'Previous bookmark'**
  String get pdfBookmark_tooltipPrev;

  /// No description provided for @pdfBookmark_tooltipNext.
  ///
  /// In en, this message translates to:
  /// **'Next bookmark'**
  String get pdfBookmark_tooltipNext;

  /// No description provided for @pdfBookmark_summaryShareText.
  ///
  /// In en, this message translates to:
  /// **'Bookmark summary ({count} pages)'**
  String pdfBookmark_summaryShareText(int count);

  /// No description provided for @pdfReader_searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search in PDF...'**
  String get pdfReader_searchHint;

  /// No description provided for @pdfReader_pinchToExit.
  ///
  /// In en, this message translates to:
  /// **'Pinch to exit'**
  String get pdfReader_pinchToExit;

  /// No description provided for @pdfReader_releaseToGoBack.
  ///
  /// In en, this message translates to:
  /// **'Release to go back'**
  String get pdfReader_releaseToGoBack;

  /// No description provided for @settings_searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search settings...'**
  String get settings_searchHint;

  /// No description provided for @settings_themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settings_themeSystem;

  /// No description provided for @settings_themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settings_themeDark;

  /// No description provided for @settings_themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settings_themeLight;

  /// No description provided for @settings_signOutTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign out?'**
  String get settings_signOutTitle;

  /// No description provided for @settings_signOutTooltip.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get settings_signOutTooltip;

  /// No description provided for @settings_signOutConfirm.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get settings_signOutConfirm;

  /// No description provided for @settings_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get settings_cancel;

  /// No description provided for @settings_resetTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore all settings?'**
  String get settings_resetTitle;

  /// No description provided for @settings_resetTypeRESET.
  ///
  /// In en, this message translates to:
  /// **'Type RESET to confirm'**
  String get settings_resetTypeRESET;

  /// No description provided for @settings_resetConfirm.
  ///
  /// In en, this message translates to:
  /// **'Restore all'**
  String get settings_resetConfirm;

  /// No description provided for @settings_resetDone.
  ///
  /// In en, this message translates to:
  /// **'All settings restored to defaults'**
  String get settings_resetDone;

  /// No description provided for @settings_onboardingNextLaunch.
  ///
  /// In en, this message translates to:
  /// **'Onboarding will appear on next launch'**
  String get settings_onboardingNextLaunch;

  /// No description provided for @settings_cacheClearMemory.
  ///
  /// In en, this message translates to:
  /// **'Clear memory'**
  String get settings_cacheClearMemory;

  /// No description provided for @settings_cacheClearDisk.
  ///
  /// In en, this message translates to:
  /// **'Clear disk'**
  String get settings_cacheClearDisk;

  /// No description provided for @settings_cacheClearDictionary.
  ///
  /// In en, this message translates to:
  /// **'Clear dictionary'**
  String get settings_cacheClearDictionary;

  /// No description provided for @settings_cacheClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get settings_cacheClearAll;

  /// No description provided for @settings_cacheMemoryCleared.
  ///
  /// In en, this message translates to:
  /// **'Memory cache cleared'**
  String get settings_cacheMemoryCleared;

  /// No description provided for @settings_cacheDiskCleared.
  ///
  /// In en, this message translates to:
  /// **'Disk cache cleared'**
  String get settings_cacheDiskCleared;

  /// No description provided for @settings_cacheDictionaryCleared.
  ///
  /// In en, this message translates to:
  /// **'Dictionary cache cleared'**
  String get settings_cacheDictionaryCleared;

  /// No description provided for @settings_addWordHint.
  ///
  /// In en, this message translates to:
  /// **'Add a word...'**
  String get settings_addWordHint;

  /// No description provided for @settings_handednessRight.
  ///
  /// In en, this message translates to:
  /// **'Right'**
  String get settings_handednessRight;

  /// No description provided for @settings_handednessLeft.
  ///
  /// In en, this message translates to:
  /// **'Left'**
  String get settings_handednessLeft;

  /// No description provided for @settings_difficultyEasy.
  ///
  /// In en, this message translates to:
  /// **'Easy'**
  String get settings_difficultyEasy;

  /// No description provided for @settings_difficultyNormal.
  ///
  /// In en, this message translates to:
  /// **'Norm'**
  String get settings_difficultyNormal;

  /// No description provided for @settings_difficultyHard.
  ///
  /// In en, this message translates to:
  /// **'Hard'**
  String get settings_difficultyHard;

  /// No description provided for @settings_storeComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Store page coming soon!'**
  String get settings_storeComingSoon;

  /// No description provided for @settings_emptyNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes are empty'**
  String get settings_emptyNotes;

  /// No description provided for @settings_invalidJson.
  ///
  /// In en, this message translates to:
  /// **'Invalid JSON: {error}'**
  String settings_invalidJson(String error);

  /// No description provided for @settings_feedbackHint.
  ///
  /// In en, this message translates to:
  /// **'Your feedback...'**
  String get settings_feedbackHint;

  /// No description provided for @settings_feedbackThanks.
  ///
  /// In en, this message translates to:
  /// **'Thank you for your feedback! 💜'**
  String get settings_feedbackThanks;

  /// No description provided for @settings_feedbackSend.
  ///
  /// In en, this message translates to:
  /// **'Send Feedback'**
  String get settings_feedbackSend;

  /// No description provided for @settings_chartCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get settings_chartCurrent;

  /// No description provided for @settings_chartMin.
  ///
  /// In en, this message translates to:
  /// **'Min'**
  String get settings_chartMin;

  /// No description provided for @settings_chartMax.
  ///
  /// In en, this message translates to:
  /// **'Max'**
  String get settings_chartMax;

  /// No description provided for @settings_chartClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get settings_chartClear;

  /// No description provided for @settings_imagesUnit.
  ///
  /// In en, this message translates to:
  /// **'{count} images'**
  String settings_imagesUnit(int count);

  /// No description provided for @settings_filesUnit.
  ///
  /// In en, this message translates to:
  /// **'{count} files'**
  String settings_filesUnit(int count);

  /// No description provided for @canvasSettings_surfaceTexture.
  ///
  /// In en, this message translates to:
  /// **'Surface Texture'**
  String get canvasSettings_surfaceTexture;

  /// No description provided for @canvasSettings_gpuShaderEngine.
  ///
  /// In en, this message translates to:
  /// **'GPU Shader Engine'**
  String get canvasSettings_gpuShaderEngine;

  /// No description provided for @canvasSettings_gpuShaderActive.
  ///
  /// In en, this message translates to:
  /// **'Active — per-pixel texture rendering'**
  String get canvasSettings_gpuShaderActive;

  /// No description provided for @brushEditor_saveAsPreset.
  ///
  /// In en, this message translates to:
  /// **'Save as Preset'**
  String get brushEditor_saveAsPreset;

  /// No description provided for @brushEditor_savePresetTitle.
  ///
  /// In en, this message translates to:
  /// **'Save Preset'**
  String get brushEditor_savePresetTitle;

  /// No description provided for @brushEditor_presetNameHint.
  ///
  /// In en, this message translates to:
  /// **'Preset name'**
  String get brushEditor_presetNameHint;

  /// No description provided for @brushEditor_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get brushEditor_cancel;

  /// No description provided for @brushEditor_save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get brushEditor_save;

  /// No description provided for @brushEditor_delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get brushEditor_delete;

  /// No description provided for @brushEditor_deletePresetTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"?'**
  String brushEditor_deletePresetTitle(String name);

  /// No description provided for @brushEditor_deletePresetBody.
  ///
  /// In en, this message translates to:
  /// **'This preset will be permanently removed.'**
  String get brushEditor_deletePresetBody;

  /// No description provided for @brushEditor_brushBallpoint.
  ///
  /// In en, this message translates to:
  /// **'Ballpoint'**
  String get brushEditor_brushBallpoint;

  /// No description provided for @brushEditor_brushFountain.
  ///
  /// In en, this message translates to:
  /// **'Fountain Pen'**
  String get brushEditor_brushFountain;

  /// No description provided for @brushEditor_brushPencil.
  ///
  /// In en, this message translates to:
  /// **'Pencil'**
  String get brushEditor_brushPencil;

  /// No description provided for @brushEditor_brushHighlighter.
  ///
  /// In en, this message translates to:
  /// **'Highlighter'**
  String get brushEditor_brushHighlighter;

  /// No description provided for @brushEditor_brushWatercolor.
  ///
  /// In en, this message translates to:
  /// **'Watercolor'**
  String get brushEditor_brushWatercolor;

  /// No description provided for @brushEditor_brushMarker.
  ///
  /// In en, this message translates to:
  /// **'Marker'**
  String get brushEditor_brushMarker;

  /// No description provided for @brushEditor_brushCharcoal.
  ///
  /// In en, this message translates to:
  /// **'Charcoal'**
  String get brushEditor_brushCharcoal;

  /// No description provided for @brushEditor_brushOilPaint.
  ///
  /// In en, this message translates to:
  /// **'Oil Paint'**
  String get brushEditor_brushOilPaint;

  /// No description provided for @brushEditor_brushSprayPaint.
  ///
  /// In en, this message translates to:
  /// **'Spray Paint'**
  String get brushEditor_brushSprayPaint;

  /// No description provided for @brushEditor_brushNeonGlow.
  ///
  /// In en, this message translates to:
  /// **'Neon Glow'**
  String get brushEditor_brushNeonGlow;

  /// No description provided for @brushEditor_brushInkWash.
  ///
  /// In en, this message translates to:
  /// **'Ink Wash'**
  String get brushEditor_brushInkWash;

  /// No description provided for @brushEditor_brushTechnicalPen.
  ///
  /// In en, this message translates to:
  /// **'Technical Pen'**
  String get brushEditor_brushTechnicalPen;

  /// No description provided for @paperPicker_title.
  ///
  /// In en, this message translates to:
  /// **'Paper Type'**
  String get paperPicker_title;

  /// No description provided for @handwritingConfirm_title.
  ///
  /// In en, this message translates to:
  /// **'Handwriting Recognized'**
  String get handwritingConfirm_title;

  /// No description provided for @handwritingConfirm_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Edit the text if needed'**
  String get handwritingConfirm_subtitle;

  /// No description provided for @handwritingConfirm_hint.
  ///
  /// In en, this message translates to:
  /// **'Recognized text...'**
  String get handwritingConfirm_hint;

  /// No description provided for @handwritingConfirm_replaceStrokes.
  ///
  /// In en, this message translates to:
  /// **'Replace strokes with text'**
  String get handwritingConfirm_replaceStrokes;

  /// No description provided for @handwritingConfirm_keepStrokes.
  ///
  /// In en, this message translates to:
  /// **'Keep strokes, add text'**
  String get handwritingConfirm_keepStrokes;

  /// No description provided for @handwritingConfirm_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get handwritingConfirm_cancel;

  /// No description provided for @handwritingConfirm_convert.
  ///
  /// In en, this message translates to:
  /// **'Convert'**
  String get handwritingConfirm_convert;

  /// No description provided for @handwritingConfirm_selectLanguage.
  ///
  /// In en, this message translates to:
  /// **'Select Language'**
  String get handwritingConfirm_selectLanguage;

  /// No description provided for @shapeConfirm_title.
  ///
  /// In en, this message translates to:
  /// **'Shape Recognized'**
  String get shapeConfirm_title;

  /// No description provided for @shapeConfirm_shapeType.
  ///
  /// In en, this message translates to:
  /// **'Shape Type'**
  String get shapeConfirm_shapeType;

  /// No description provided for @shapeConfirm_filled.
  ///
  /// In en, this message translates to:
  /// **'Filled'**
  String get shapeConfirm_filled;

  /// No description provided for @shapeConfirm_outlineOnly.
  ///
  /// In en, this message translates to:
  /// **'Outline only'**
  String get shapeConfirm_outlineOnly;

  /// No description provided for @shapeConfirm_replaceStrokes.
  ///
  /// In en, this message translates to:
  /// **'Replace strokes with shape'**
  String get shapeConfirm_replaceStrokes;

  /// No description provided for @shapeConfirm_keepStrokes.
  ///
  /// In en, this message translates to:
  /// **'Keep strokes, add shape'**
  String get shapeConfirm_keepStrokes;

  /// No description provided for @shapeConfirm_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get shapeConfirm_cancel;

  /// No description provided for @shapeConfirm_convert.
  ///
  /// In en, this message translates to:
  /// **'Convert'**
  String get shapeConfirm_convert;

  /// No description provided for @shape_freehand.
  ///
  /// In en, this message translates to:
  /// **'Freehand'**
  String get shape_freehand;

  /// No description provided for @shape_line.
  ///
  /// In en, this message translates to:
  /// **'Line'**
  String get shape_line;

  /// No description provided for @shape_arrow.
  ///
  /// In en, this message translates to:
  /// **'Arrow'**
  String get shape_arrow;

  /// No description provided for @shape_circle.
  ///
  /// In en, this message translates to:
  /// **'Circle'**
  String get shape_circle;

  /// No description provided for @shape_rectangle.
  ///
  /// In en, this message translates to:
  /// **'Rectangle'**
  String get shape_rectangle;

  /// No description provided for @shape_triangle.
  ///
  /// In en, this message translates to:
  /// **'Triangle'**
  String get shape_triangle;

  /// No description provided for @shape_diamond.
  ///
  /// In en, this message translates to:
  /// **'Diamond'**
  String get shape_diamond;

  /// No description provided for @shape_pentagon.
  ///
  /// In en, this message translates to:
  /// **'Pentagon'**
  String get shape_pentagon;

  /// No description provided for @shape_hexagon.
  ///
  /// In en, this message translates to:
  /// **'Hexagon'**
  String get shape_hexagon;

  /// No description provided for @shape_star.
  ///
  /// In en, this message translates to:
  /// **'Star'**
  String get shape_star;

  /// No description provided for @shape_heart.
  ///
  /// In en, this message translates to:
  /// **'Heart'**
  String get shape_heart;

  /// No description provided for @ocrScan_noTextFound.
  ///
  /// In en, this message translates to:
  /// **'No text found in image'**
  String get ocrScan_noTextFound;

  /// No description provided for @ocrScan_tryAnotherImage.
  ///
  /// In en, this message translates to:
  /// **'Try another image'**
  String get ocrScan_tryAnotherImage;

  /// No description provided for @ocrScan_anotherImage.
  ///
  /// In en, this message translates to:
  /// **'Another image'**
  String get ocrScan_anotherImage;

  /// No description provided for @ocrScan_separatedBlocks.
  ///
  /// In en, this message translates to:
  /// **'Separated blocks'**
  String get ocrScan_separatedBlocks;

  /// No description provided for @ocrScan_mergedText.
  ///
  /// In en, this message translates to:
  /// **'Merged text'**
  String get ocrScan_mergedText;

  /// No description provided for @ocrScan_showBlocks.
  ///
  /// In en, this message translates to:
  /// **'Show detected blocks'**
  String get ocrScan_showBlocks;

  /// No description provided for @ocrScan_deselectAll.
  ///
  /// In en, this message translates to:
  /// **'Deselect all'**
  String get ocrScan_deselectAll;

  /// No description provided for @ocrScan_selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get ocrScan_selectAll;

  /// No description provided for @handwritingPicker_title.
  ///
  /// In en, this message translates to:
  /// **'Handwriting Languages'**
  String get handwritingPicker_title;

  /// No description provided for @handwritingPicker_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Download models for offline recognition (~15 MB each)'**
  String get handwritingPicker_subtitle;

  /// No description provided for @handwritingPicker_active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get handwritingPicker_active;

  /// No description provided for @handwritingPicker_use.
  ///
  /// In en, this message translates to:
  /// **'Use'**
  String get handwritingPicker_use;

  /// No description provided for @handwritingPicker_modelSize.
  ///
  /// In en, this message translates to:
  /// **'~15 MB'**
  String get handwritingPicker_modelSize;

  /// No description provided for @share_invalidEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email'**
  String get share_invalidEmail;

  /// No description provided for @share_inviteSent.
  ///
  /// In en, this message translates to:
  /// **'Invite sent to {email} — they\'ll get access on signup'**
  String share_inviteSent(String email);

  /// No description provided for @share_userNotFound.
  ///
  /// In en, this message translates to:
  /// **'No user found with this email'**
  String get share_userNotFound;

  /// No description provided for @share_title.
  ///
  /// In en, this message translates to:
  /// **'Share canvas'**
  String get share_title;

  /// No description provided for @share_emailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email address'**
  String get share_emailLabel;

  /// No description provided for @share_roleViewer.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get share_roleViewer;

  /// No description provided for @share_roleEditor.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get share_roleEditor;

  /// No description provided for @share_canEdit.
  ///
  /// In en, this message translates to:
  /// **'Can edit'**
  String get share_canEdit;

  /// No description provided for @share_canView.
  ///
  /// In en, this message translates to:
  /// **'View only'**
  String get share_canView;

  /// No description provided for @share_revokeAccess.
  ///
  /// In en, this message translates to:
  /// **'Revoke access'**
  String get share_revokeAccess;

  /// No description provided for @share_shareButton.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share_shareButton;

  /// No description provided for @galleryComp_sortNewest.
  ///
  /// In en, this message translates to:
  /// **'Newest first'**
  String get galleryComp_sortNewest;

  /// No description provided for @galleryComp_sortOldest.
  ///
  /// In en, this message translates to:
  /// **'Oldest first'**
  String get galleryComp_sortOldest;

  /// No description provided for @galleryComp_newest.
  ///
  /// In en, this message translates to:
  /// **'Newest'**
  String get galleryComp_newest;

  /// No description provided for @galleryComp_oldest.
  ///
  /// In en, this message translates to:
  /// **'Oldest'**
  String get galleryComp_oldest;

  /// No description provided for @workspace_resume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get workspace_resume;

  /// No description provided for @workspace_open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get workspace_open;

  /// No description provided for @workspace_origin.
  ///
  /// In en, this message translates to:
  /// **'Origin'**
  String get workspace_origin;

  /// No description provided for @workspace_continue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get workspace_continue;

  /// No description provided for @workspace_recentBookmarks.
  ///
  /// In en, this message translates to:
  /// **'Recent bookmarks'**
  String get workspace_recentBookmarks;

  /// No description provided for @workspace_showAllCanvases.
  ///
  /// In en, this message translates to:
  /// **'Show all canvases'**
  String get workspace_showAllCanvases;

  /// No description provided for @workspace_justNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get workspace_justNow;

  /// No description provided for @hub_bookmarks.
  ///
  /// In en, this message translates to:
  /// **'Bookmarks'**
  String get hub_bookmarks;

  /// No description provided for @hub_tapToJump.
  ///
  /// In en, this message translates to:
  /// **'Tap to jump'**
  String get hub_tapToJump;

  /// No description provided for @hub_now.
  ///
  /// In en, this message translates to:
  /// **'Now'**
  String get hub_now;

  /// No description provided for @examDash_sectionScoreTrend.
  ///
  /// In en, this message translates to:
  /// **'Score trend (30 days)'**
  String get examDash_sectionScoreTrend;

  /// No description provided for @examDash_sectionTopicsToReinforce.
  ///
  /// In en, this message translates to:
  /// **'Topics to reinforce'**
  String get examDash_sectionTopicsToReinforce;

  /// No description provided for @examDash_sectionBloomDistribution.
  ///
  /// In en, this message translates to:
  /// **'Bloom distribution of training'**
  String get examDash_sectionBloomDistribution;

  /// No description provided for @examDash_sectionRecentSessions.
  ///
  /// In en, this message translates to:
  /// **'Recent sessions'**
  String get examDash_sectionRecentSessions;

  /// No description provided for @examDash_sectionRecentSocratic.
  ///
  /// In en, this message translates to:
  /// **'Recent Socratic sessions'**
  String get examDash_sectionRecentSocratic;

  /// No description provided for @examDash_noExamsYet.
  ///
  /// In en, this message translates to:
  /// **'No exams completed yet'**
  String get examDash_noExamsYet;

  /// No description provided for @examDash_totalSessionsKpi.
  ///
  /// In en, this message translates to:
  /// **'total sessions'**
  String get examDash_totalSessionsKpi;

  /// No description provided for @examDash_streakKpi.
  ///
  /// In en, this message translates to:
  /// **'daily streak'**
  String get examDash_streakKpi;

  /// No description provided for @examDash_avg30Kpi.
  ///
  /// In en, this message translates to:
  /// **'30-day average'**
  String get examDash_avg30Kpi;

  /// No description provided for @examDash_noDataLast30.
  ///
  /// In en, this message translates to:
  /// **'No data in the last 30 days'**
  String get examDash_noDataLast30;

  /// No description provided for @examDash_needTwoSessions.
  ///
  /// In en, this message translates to:
  /// **'Need at least 2 sessions for the chart'**
  String get examDash_needTwoSessions;

  /// No description provided for @examDash_allTopicsAbove60.
  ///
  /// In en, this message translates to:
  /// **'No topics below 60%. Keep it up!'**
  String get examDash_allTopicsAbove60;

  /// No description provided for @examDash_socraticReviewSoon.
  ///
  /// In en, this message translates to:
  /// **'Detailed Socratic review coming in V1.6'**
  String get examDash_socraticReviewSoon;

  /// No description provided for @examDash_session.
  ///
  /// In en, this message translates to:
  /// **'Session'**
  String get examDash_session;

  /// No description provided for @examDash_yesterday.
  ///
  /// In en, this message translates to:
  /// **'yesterday'**
  String get examDash_yesterday;

  /// No description provided for @bloom_remember.
  ///
  /// In en, this message translates to:
  /// **'Remember'**
  String get bloom_remember;

  /// No description provided for @bloom_understand.
  ///
  /// In en, this message translates to:
  /// **'Understand'**
  String get bloom_understand;

  /// No description provided for @bloom_apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get bloom_apply;

  /// No description provided for @bloom_analyze.
  ///
  /// In en, this message translates to:
  /// **'Analyze'**
  String get bloom_analyze;

  /// No description provided for @bloom_evaluate.
  ///
  /// In en, this message translates to:
  /// **'Evaluate'**
  String get bloom_evaluate;

  /// No description provided for @bloom_create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get bloom_create;

  /// No description provided for @authExc_invalidCredentials.
  ///
  /// In en, this message translates to:
  /// **'Invalid email or password'**
  String get authExc_invalidCredentials;

  /// No description provided for @authExc_emailInUse.
  ///
  /// In en, this message translates to:
  /// **'This email is already registered'**
  String get authExc_emailInUse;

  /// No description provided for @authExc_weakPassword.
  ///
  /// In en, this message translates to:
  /// **'Password too weak (min. 6 characters)'**
  String get authExc_weakPassword;

  /// No description provided for @authExc_invalidEmail.
  ///
  /// In en, this message translates to:
  /// **'Invalid email format'**
  String get authExc_invalidEmail;

  /// No description provided for @authExc_emailNotConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirm your email before signing in'**
  String get authExc_emailNotConfirmed;

  /// No description provided for @authExc_banned.
  ///
  /// In en, this message translates to:
  /// **'This account has been suspended'**
  String get authExc_banned;

  /// No description provided for @authExc_userNotFound.
  ///
  /// In en, this message translates to:
  /// **'User not found'**
  String get authExc_userNotFound;

  /// No description provided for @authExc_signupDisabled.
  ///
  /// In en, this message translates to:
  /// **'Signups are temporarily disabled'**
  String get authExc_signupDisabled;

  /// No description provided for @authExc_providerLinked.
  ///
  /// In en, this message translates to:
  /// **'This {provider} account is already linked to another profile'**
  String authExc_providerLinked(String provider);

  /// No description provided for @authExc_sessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Session expired — sign in again'**
  String get authExc_sessionExpired;

  /// No description provided for @authExc_accountDeleted.
  ///
  /// In en, this message translates to:
  /// **'Your account has been deleted'**
  String get authExc_accountDeleted;

  /// No description provided for @authExc_offline.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline — sign-in requires connection'**
  String get authExc_offline;

  /// No description provided for @authExc_rateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Try again shortly.'**
  String get authExc_rateLimited;

  /// No description provided for @examReview_emptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing to review'**
  String get examReview_emptyTitle;

  /// No description provided for @examReview_emptyBody.
  ///
  /// In en, this message translates to:
  /// **'For exams completed before V1.5 we only save handwritten strokes, not the questions. New exams will show question + answer + strokes here.'**
  String get examReview_emptyBody;

  /// No description provided for @examReview_resultCorrect.
  ///
  /// In en, this message translates to:
  /// **'✓ correct'**
  String get examReview_resultCorrect;

  /// No description provided for @examReview_resultIncorrect.
  ///
  /// In en, this message translates to:
  /// **'✗ wrong'**
  String get examReview_resultIncorrect;

  /// No description provided for @examReview_resultSkipped.
  ///
  /// In en, this message translates to:
  /// **'➜ skipped'**
  String get examReview_resultSkipped;

  /// No description provided for @examReview_resultPartial.
  ///
  /// In en, this message translates to:
  /// **'◐ partial'**
  String get examReview_resultPartial;

  /// No description provided for @examReview_questionLabel.
  ///
  /// In en, this message translates to:
  /// **'Question {n}'**
  String examReview_questionLabel(int n);

  /// No description provided for @examReview_reworked.
  ///
  /// In en, this message translates to:
  /// **'reworked'**
  String get examReview_reworked;

  /// No description provided for @examReview_yourAnswer.
  ///
  /// In en, this message translates to:
  /// **'Your answer'**
  String get examReview_yourAnswer;

  /// No description provided for @examReview_correctAnswer.
  ///
  /// In en, this message translates to:
  /// **'Correct answer'**
  String get examReview_correctAnswer;

  /// No description provided for @storage_title.
  ///
  /// In en, this message translates to:
  /// **'Cloud storage'**
  String get storage_title;

  /// No description provided for @storage_refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get storage_refresh;

  /// No description provided for @storage_detailTitle.
  ///
  /// In en, this message translates to:
  /// **'Storage detail'**
  String get storage_detailTitle;

  /// No description provided for @storage_images.
  ///
  /// In en, this message translates to:
  /// **'Images'**
  String get storage_images;

  /// No description provided for @storage_pdfs.
  ///
  /// In en, this message translates to:
  /// **'PDFs'**
  String get storage_pdfs;

  /// No description provided for @storage_recordings.
  ///
  /// In en, this message translates to:
  /// **'Recordings'**
  String get storage_recordings;

  /// No description provided for @storage_largestCanvases.
  ///
  /// In en, this message translates to:
  /// **'Largest canvases'**
  String get storage_largestCanvases;

  /// No description provided for @storage_usedLabel.
  ///
  /// In en, this message translates to:
  /// **'used'**
  String get storage_usedLabel;

  /// No description provided for @storage_quotaTotal.
  ///
  /// In en, this message translates to:
  /// **'Total quota'**
  String get storage_quotaTotal;

  /// No description provided for @storage_usedAmount.
  ///
  /// In en, this message translates to:
  /// **'Used'**
  String get storage_usedAmount;

  /// No description provided for @storage_remaining.
  ///
  /// In en, this message translates to:
  /// **'Remaining'**
  String get storage_remaining;

  /// No description provided for @brushStamp_spacing.
  ///
  /// In en, this message translates to:
  /// **'Spacing'**
  String get brushStamp_spacing;

  /// No description provided for @brushStamp_scatter.
  ///
  /// In en, this message translates to:
  /// **'Scatter'**
  String get brushStamp_scatter;

  /// No description provided for @brushStamp_symmetry.
  ///
  /// In en, this message translates to:
  /// **'Symmetry'**
  String get brushStamp_symmetry;

  /// No description provided for @brushStamp_textureNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get brushStamp_textureNone;

  /// No description provided for @brushStamp_texturePencil.
  ///
  /// In en, this message translates to:
  /// **'Pencil Grain'**
  String get brushStamp_texturePencil;

  /// No description provided for @brushStamp_textureCharcoal.
  ///
  /// In en, this message translates to:
  /// **'Charcoal'**
  String get brushStamp_textureCharcoal;

  /// No description provided for @brushStamp_textureWatercolor.
  ///
  /// In en, this message translates to:
  /// **'Watercolor'**
  String get brushStamp_textureWatercolor;

  /// No description provided for @brushStamp_textureCanvas.
  ///
  /// In en, this message translates to:
  /// **'Canvas'**
  String get brushStamp_textureCanvas;

  /// No description provided for @brushStamp_textureKraft.
  ///
  /// In en, this message translates to:
  /// **'Kraft'**
  String get brushStamp_textureKraft;

  /// No description provided for @brushStamp_shapeCircle.
  ///
  /// In en, this message translates to:
  /// **'Circle'**
  String get brushStamp_shapeCircle;

  /// No description provided for @brushStamp_shapeSquare.
  ///
  /// In en, this message translates to:
  /// **'Square'**
  String get brushStamp_shapeSquare;

  /// No description provided for @brushStamp_shapeDiamond.
  ///
  /// In en, this message translates to:
  /// **'Diamond'**
  String get brushStamp_shapeDiamond;

  /// No description provided for @brushStamp_presetWatercolor.
  ///
  /// In en, this message translates to:
  /// **'Watercolor'**
  String get brushStamp_presetWatercolor;

  /// No description provided for @brushStamp_presetCharcoal.
  ///
  /// In en, this message translates to:
  /// **'Charcoal'**
  String get brushStamp_presetCharcoal;

  /// No description provided for @brushStamp_presetAirbrush.
  ///
  /// In en, this message translates to:
  /// **'Airbrush'**
  String get brushStamp_presetAirbrush;

  /// No description provided for @ruler_annotationLabel.
  ///
  /// In en, this message translates to:
  /// **'Annotation'**
  String get ruler_annotationLabel;

  /// No description provided for @ruler_copyCoordinate.
  ///
  /// In en, this message translates to:
  /// **'Copy coordinate'**
  String get ruler_copyCoordinate;

  /// No description provided for @ruler_copied.
  ///
  /// In en, this message translates to:
  /// **'Copied: {coord}'**
  String ruler_copied(String coord);

  /// No description provided for @ruler_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get ruler_cancel;

  /// No description provided for @ruler_ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ruler_ok;

  /// No description provided for @ruler_apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get ruler_apply;

  /// No description provided for @ruler_save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get ruler_save;

  /// No description provided for @ruler_customGridTitle.
  ///
  /// In en, this message translates to:
  /// **'Custom Grid'**
  String get ruler_customGridTitle;

  /// No description provided for @ruler_numberOfGuides.
  ///
  /// In en, this message translates to:
  /// **'Number of guides'**
  String get ruler_numberOfGuides;

  /// No description provided for @ruler_distribute.
  ///
  /// In en, this message translates to:
  /// **'Distribute'**
  String get ruler_distribute;

  /// No description provided for @ruler_presetNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Preset name'**
  String get ruler_presetNameLabel;

  /// No description provided for @latex_undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get latex_undo;

  /// No description provided for @latex_redo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get latex_redo;

  /// No description provided for @latex_history.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get latex_history;

  /// No description provided for @latex_templates.
  ///
  /// In en, this message translates to:
  /// **'Templates'**
  String get latex_templates;

  /// No description provided for @latex_graph.
  ///
  /// In en, this message translates to:
  /// **'Graph'**
  String get latex_graph;

  /// No description provided for @latex_commands.
  ///
  /// In en, this message translates to:
  /// **'Commands'**
  String get latex_commands;

  /// No description provided for @latex_preview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get latex_preview;

  /// No description provided for @latex_reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get latex_reset;

  /// No description provided for @latex_noRecentExpressions.
  ///
  /// In en, this message translates to:
  /// **'No recent expressions'**
  String get latex_noRecentExpressions;

  /// No description provided for @latex_enterExpressionFirst.
  ///
  /// In en, this message translates to:
  /// **'Enter an expression before viewing the graph'**
  String get latex_enterExpressionFirst;

  /// No description provided for @versionHistory_saveVersion.
  ///
  /// In en, this message translates to:
  /// **'Save checkpoint'**
  String get versionHistory_saveVersion;

  /// No description provided for @versionHistory_saveVersionTitle.
  ///
  /// In en, this message translates to:
  /// **'Save checkpoint'**
  String get versionHistory_saveVersionTitle;

  /// No description provided for @versionHistory_noVersions.
  ///
  /// In en, this message translates to:
  /// **'No checkpoints yet'**
  String get versionHistory_noVersions;

  /// No description provided for @versionHistory_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get versionHistory_cancel;

  /// No description provided for @versionHistory_save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get versionHistory_save;

  /// No description provided for @versionHistory_restore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get versionHistory_restore;

  /// No description provided for @versionHistory_delete.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get versionHistory_delete;

  /// No description provided for @varManager_close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get varManager_close;

  /// No description provided for @varManager_remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get varManager_remove;

  /// No description provided for @varManager_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get varManager_cancel;

  /// No description provided for @varManager_create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get varManager_create;

  /// No description provided for @varManager_import.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get varManager_import;

  /// No description provided for @varManager_apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get varManager_apply;

  /// No description provided for @varManager_noVariables.
  ///
  /// In en, this message translates to:
  /// **'No variables yet'**
  String get varManager_noVariables;

  /// No description provided for @varManager_noResults.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get varManager_noResults;

  /// No description provided for @varManager_noCollections.
  ///
  /// In en, this message translates to:
  /// **'No variable collections'**
  String get varManager_noCollections;

  /// No description provided for @varManager_variableName.
  ///
  /// In en, this message translates to:
  /// **'Variable name'**
  String get varManager_variableName;

  /// No description provided for @varManager_typeLabel.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get varManager_typeLabel;

  /// No description provided for @varManager_valueLabel.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get varManager_valueLabel;

  /// No description provided for @warp_undoLastMove.
  ///
  /// In en, this message translates to:
  /// **'Undo last move'**
  String get warp_undoLastMove;

  /// No description provided for @warp_resetMesh.
  ///
  /// In en, this message translates to:
  /// **'Reset mesh'**
  String get warp_resetMesh;

  /// No description provided for @warp_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get warp_cancel;

  /// No description provided for @warp_apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get warp_apply;

  /// No description provided for @warp_gridLabel.
  ///
  /// In en, this message translates to:
  /// **'Grid: '**
  String get warp_gridLabel;

  /// No description provided for @smudge_label.
  ///
  /// In en, this message translates to:
  /// **'Smudge'**
  String get smudge_label;

  /// No description provided for @smudge_description.
  ///
  /// In en, this message translates to:
  /// **'Drag and blend colors like a finger on wet paint'**
  String get smudge_description;

  /// No description provided for @smudge_fingerPainting.
  ///
  /// In en, this message translates to:
  /// **'Finger Painting'**
  String get smudge_fingerPainting;

  /// No description provided for @transformWarp_description.
  ///
  /// In en, this message translates to:
  /// **'Deform with a control-point mesh grid'**
  String get transformWarp_description;

  /// No description provided for @titleBar_minimize.
  ///
  /// In en, this message translates to:
  /// **'Minimize'**
  String get titleBar_minimize;

  /// No description provided for @titleBar_restore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get titleBar_restore;

  /// No description provided for @titleBar_maximize.
  ///
  /// In en, this message translates to:
  /// **'Maximize'**
  String get titleBar_maximize;

  /// No description provided for @titleBar_close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get titleBar_close;

  /// No description provided for @cmdPalette_hint.
  ///
  /// In en, this message translates to:
  /// **'Type a command...'**
  String get cmdPalette_hint;

  /// No description provided for @cmdPalette_noCommands.
  ///
  /// In en, this message translates to:
  /// **'No commands found'**
  String get cmdPalette_noCommands;

  /// No description provided for @cmdPalette_navigate.
  ///
  /// In en, this message translates to:
  /// **'navigate'**
  String get cmdPalette_navigate;

  /// No description provided for @cmdPalette_select.
  ///
  /// In en, this message translates to:
  /// **'select'**
  String get cmdPalette_select;

  /// No description provided for @cmdPalette_toggleFullscreen.
  ///
  /// In en, this message translates to:
  /// **'Toggle Fullscreen'**
  String get cmdPalette_toggleFullscreen;

  /// No description provided for @cmdPalette_toggleAlwaysOnTop.
  ///
  /// In en, this message translates to:
  /// **'Toggle Always on Top'**
  String get cmdPalette_toggleAlwaysOnTop;

  /// No description provided for @cmdPalette_minimize.
  ///
  /// In en, this message translates to:
  /// **'Minimize Window'**
  String get cmdPalette_minimize;

  /// No description provided for @cmdPalette_maximize.
  ///
  /// In en, this message translates to:
  /// **'Maximize / Restore Window'**
  String get cmdPalette_maximize;

  /// No description provided for @cmdPalette_center.
  ///
  /// In en, this message translates to:
  /// **'Center Window'**
  String get cmdPalette_center;

  /// No description provided for @cmdPalette_themeDark.
  ///
  /// In en, this message translates to:
  /// **'Theme: Dark Mode'**
  String get cmdPalette_themeDark;

  /// No description provided for @cmdPalette_themeLight.
  ///
  /// In en, this message translates to:
  /// **'Theme: Light Mode'**
  String get cmdPalette_themeLight;

  /// No description provided for @cmdPalette_themeSystem.
  ///
  /// In en, this message translates to:
  /// **'Theme: System Default'**
  String get cmdPalette_themeSystem;

  /// No description provided for @cmdPalette_newCanvas.
  ///
  /// In en, this message translates to:
  /// **'New Canvas'**
  String get cmdPalette_newCanvas;

  /// No description provided for @cmdPalette_openSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get cmdPalette_openSettings;

  /// No description provided for @cmdPalette_closeFluera.
  ///
  /// In en, this message translates to:
  /// **'Close Fluera'**
  String get cmdPalette_closeFluera;

  /// No description provided for @pdfExport_print.
  ///
  /// In en, this message translates to:
  /// **'Print'**
  String get pdfExport_print;

  /// No description provided for @pdfExport_archive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get pdfExport_archive;

  /// No description provided for @atlasCard_answer.
  ///
  /// In en, this message translates to:
  /// **'Answer'**
  String get atlasCard_answer;

  /// No description provided for @atlasCard_oneMoment.
  ///
  /// In en, this message translates to:
  /// **'One moment…'**
  String get atlasCard_oneMoment;

  /// No description provided for @atlasCard_nextConcept.
  ///
  /// In en, this message translates to:
  /// **'Next → {concept}'**
  String atlasCard_nextConcept(String concept);

  /// No description provided for @atlasCard_swipeForHistory.
  ///
  /// In en, this message translates to:
  /// **'swipe for history'**
  String get atlasCard_swipeForHistory;

  /// No description provided for @atlasCard_canExplain.
  ///
  /// In en, this message translates to:
  /// **'I can explain it'**
  String get atlasCard_canExplain;

  /// No description provided for @atlasCard_hesitant.
  ///
  /// In en, this message translates to:
  /// **'I have doubts'**
  String get atlasCard_hesitant;

  /// No description provided for @atlasCard_cantRemember.
  ///
  /// In en, this message translates to:
  /// **'I don\'t remember'**
  String get atlasCard_cantRemember;

  /// No description provided for @pdfExport_quickShare.
  ///
  /// In en, this message translates to:
  /// **'Quick Share'**
  String get pdfExport_quickShare;

  /// No description provided for @pdfExport_pageOfPages.
  ///
  /// In en, this message translates to:
  /// **'Page {current} of {total}'**
  String pdfExport_pageOfPages(int current, int total);

  /// No description provided for @pdfExport_exportComplete.
  ///
  /// In en, this message translates to:
  /// **'Export Complete'**
  String get pdfExport_exportComplete;

  /// No description provided for @pdfExport_proPlanBadge.
  ///
  /// In en, this message translates to:
  /// **'Pro'**
  String get pdfExport_proPlanBadge;

  /// No description provided for @pdfExport_freePlanLimit.
  ///
  /// In en, this message translates to:
  /// **'The Free plan exports only to PNG. With Pro, export to PDF, SVG, and all formats.'**
  String get pdfExport_freePlanLimit;

  /// No description provided for @pdfExport_position.
  ///
  /// In en, this message translates to:
  /// **'Position'**
  String get pdfExport_position;

  /// No description provided for @pdfExport_positionDiagonal.
  ///
  /// In en, this message translates to:
  /// **'Diagonal'**
  String get pdfExport_positionDiagonal;

  /// No description provided for @pdfExport_positionCenter.
  ///
  /// In en, this message translates to:
  /// **'Center'**
  String get pdfExport_positionCenter;

  /// No description provided for @pdfExport_positionTiled.
  ///
  /// In en, this message translates to:
  /// **'Tiled'**
  String get pdfExport_positionTiled;

  /// No description provided for @pdfExport_opacity.
  ///
  /// In en, this message translates to:
  /// **'Opacity {percent}%'**
  String pdfExport_opacity(int percent);

  /// No description provided for @brushCtrl_angleSnap.
  ///
  /// In en, this message translates to:
  /// **'Angle Snap'**
  String get brushCtrl_angleSnap;

  /// No description provided for @brushCtrl_snapAngle.
  ///
  /// In en, this message translates to:
  /// **'Snap Angle'**
  String get brushCtrl_snapAngle;

  /// No description provided for @brushCtrl_closeShapes.
  ///
  /// In en, this message translates to:
  /// **'Close Shapes'**
  String get brushCtrl_closeShapes;

  /// No description provided for @brushCtrl_cornerSharpness.
  ///
  /// In en, this message translates to:
  /// **'Corner Sharpness'**
  String get brushCtrl_cornerSharpness;

  /// No description provided for @brushCtrl_gridSnap.
  ///
  /// In en, this message translates to:
  /// **'Grid Snap'**
  String get brushCtrl_gridSnap;

  /// No description provided for @brushCtrl_gridSize.
  ///
  /// In en, this message translates to:
  /// **'Grid Size'**
  String get brushCtrl_gridSize;

  /// No description provided for @brushCtrl_straightAssist.
  ///
  /// In en, this message translates to:
  /// **'Straight Assist'**
  String get brushCtrl_straightAssist;

  /// No description provided for @brushCtrl_showGuides.
  ///
  /// In en, this message translates to:
  /// **'Show Guides'**
  String get brushCtrl_showGuides;

  /// No description provided for @brushCtrl_parallelSnap.
  ///
  /// In en, this message translates to:
  /// **'Parallel Snap'**
  String get brushCtrl_parallelSnap;

  /// No description provided for @brushCtrl_perpendicularSnap.
  ///
  /// In en, this message translates to:
  /// **'Perpendicular Snap'**
  String get brushCtrl_perpendicularSnap;

  /// No description provided for @brushCtrl_sensitivity.
  ///
  /// In en, this message translates to:
  /// **'Sensitivity'**
  String get brushCtrl_sensitivity;

  /// No description provided for @brushCtrl_thinning.
  ///
  /// In en, this message translates to:
  /// **'Thinning'**
  String get brushCtrl_thinning;

  /// No description provided for @brushCtrl_velocity.
  ///
  /// In en, this message translates to:
  /// **'Velocity'**
  String get brushCtrl_velocity;

  /// No description provided for @brushCtrl_tilt.
  ///
  /// In en, this message translates to:
  /// **'Tilt'**
  String get brushCtrl_tilt;

  /// No description provided for @brushCtrl_nibAngle.
  ///
  /// In en, this message translates to:
  /// **'Nib Angle'**
  String get brushCtrl_nibAngle;

  /// No description provided for @brushCtrl_nibStrength.
  ///
  /// In en, this message translates to:
  /// **'Nib Strength'**
  String get brushCtrl_nibStrength;

  /// No description provided for @brushCtrl_taperStart.
  ///
  /// In en, this message translates to:
  /// **'Taper Start'**
  String get brushCtrl_taperStart;

  /// No description provided for @brushCtrl_taperEnd.
  ///
  /// In en, this message translates to:
  /// **'Taper End'**
  String get brushCtrl_taperEnd;

  /// No description provided for @brushCtrl_opacity.
  ///
  /// In en, this message translates to:
  /// **'Opacity'**
  String get brushCtrl_opacity;

  /// No description provided for @brushCtrl_softness.
  ///
  /// In en, this message translates to:
  /// **'Softness'**
  String get brushCtrl_softness;

  /// No description provided for @brushCtrl_pressure.
  ///
  /// In en, this message translates to:
  /// **'Pressure'**
  String get brushCtrl_pressure;

  /// No description provided for @brushCtrl_width.
  ///
  /// In en, this message translates to:
  /// **'Width'**
  String get brushCtrl_width;

  /// No description provided for @brushCtrl_autoStraighten.
  ///
  /// In en, this message translates to:
  /// **'Auto-Straighten'**
  String get brushCtrl_autoStraighten;

  /// No description provided for @brushCtrl_stabilizer.
  ///
  /// In en, this message translates to:
  /// **'Stabilizer'**
  String get brushCtrl_stabilizer;

  /// No description provided for @voice_qualitySettings.
  ///
  /// In en, this message translates to:
  /// **'Quality Settings'**
  String get voice_qualitySettings;

  /// No description provided for @voice_withStrokes.
  ///
  /// In en, this message translates to:
  /// **'With Strokes'**
  String get voice_withStrokes;

  /// No description provided for @voice_withoutStrokes.
  ///
  /// In en, this message translates to:
  /// **'Without Strokes'**
  String get voice_withoutStrokes;

  /// No description provided for @voice_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get voice_cancel;

  /// No description provided for @voice_save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get voice_save;

  /// No description provided for @voice_delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get voice_delete;

  /// No description provided for @voice_deleteAll.
  ///
  /// In en, this message translates to:
  /// **'Delete All'**
  String get voice_deleteAll;

  /// No description provided for @voice_download.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get voice_download;

  /// No description provided for @voice_retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get voice_retry;

  /// No description provided for @voice_play.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get voice_play;

  /// No description provided for @voice_unpin.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get voice_unpin;

  /// No description provided for @voice_recordingComplete.
  ///
  /// In en, this message translates to:
  /// **'Recording Complete'**
  String get voice_recordingComplete;

  /// No description provided for @voice_recordingDeleted.
  ///
  /// In en, this message translates to:
  /// **'Recording deleted'**
  String get voice_recordingDeleted;

  /// No description provided for @voice_noRecordingsSaved.
  ///
  /// In en, this message translates to:
  /// **'No recordings saved for this canvas'**
  String get voice_noRecordingsSaved;

  /// No description provided for @voice_errorStarting.
  ///
  /// In en, this message translates to:
  /// **'Error starting recording: {error}'**
  String voice_errorStarting(String error);

  /// No description provided for @voice_errorStopping.
  ///
  /// In en, this message translates to:
  /// **'Error stopping recording: {error}'**
  String voice_errorStopping(String error);

  /// No description provided for @voice_deleteRecording.
  ///
  /// In en, this message translates to:
  /// **'Delete recording?'**
  String get voice_deleteRecording;

  /// No description provided for @voice_downloadSpeechModel.
  ///
  /// In en, this message translates to:
  /// **'Download Speech Model'**
  String get voice_downloadSpeechModel;

  /// No description provided for @voice_transcriptionLanguage.
  ///
  /// In en, this message translates to:
  /// **'Transcription Language'**
  String get voice_transcriptionLanguage;

  /// No description provided for @voice_autoDetect.
  ///
  /// In en, this message translates to:
  /// **'Auto-detect'**
  String get voice_autoDetect;

  /// No description provided for @voice_autoDetectSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Let the model detect the language'**
  String get voice_autoDetectSubtitle;

  /// No description provided for @brushWidget_texture.
  ///
  /// In en, this message translates to:
  /// **'Texture'**
  String get brushWidget_texture;

  /// No description provided for @brushWidget_textureHint.
  ///
  /// In en, this message translates to:
  /// **'Applies a texture overlay to strokes for a more natural feel.'**
  String get brushWidget_textureHint;

  /// No description provided for @brushWidget_intensity.
  ///
  /// In en, this message translates to:
  /// **'Intensity'**
  String get brushWidget_intensity;

  /// No description provided for @brushWidget_intensityHint.
  ///
  /// In en, this message translates to:
  /// **'How strongly the texture shows through the stroke.'**
  String get brushWidget_intensityHint;

  /// No description provided for @brushWidget_pressureCurve.
  ///
  /// In en, this message translates to:
  /// **'Pressure Curve'**
  String get brushWidget_pressureCurve;

  /// No description provided for @brushWidget_pressureCurveHint.
  ///
  /// In en, this message translates to:
  /// **'Maps raw stylus pressure to output. Soft = light touch produces more, Firm = needs harder press.'**
  String get brushWidget_pressureCurveHint;

  /// No description provided for @brushWidget_curveLinear.
  ///
  /// In en, this message translates to:
  /// **'Linear'**
  String get brushWidget_curveLinear;

  /// No description provided for @brushWidget_curveSoft.
  ///
  /// In en, this message translates to:
  /// **'Soft'**
  String get brushWidget_curveSoft;

  /// No description provided for @brushWidget_curveFirm.
  ///
  /// In en, this message translates to:
  /// **'Firm'**
  String get brushWidget_curveFirm;

  /// No description provided for @brushWidget_curveSCurve.
  ///
  /// In en, this message translates to:
  /// **'S-Curve'**
  String get brushWidget_curveSCurve;

  /// No description provided for @brushWidget_curveHeavy.
  ///
  /// In en, this message translates to:
  /// **'Heavy'**
  String get brushWidget_curveHeavy;

  /// No description provided for @canvasParts_mustKeepOnePage.
  ///
  /// In en, this message translates to:
  /// **'Must keep at least one page'**
  String get canvasParts_mustKeepOnePage;

  /// No description provided for @canvasParts_noContentToFrame.
  ///
  /// In en, this message translates to:
  /// **'No content to frame'**
  String get canvasParts_noContentToFrame;

  /// No description provided for @canvasParts_exportNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Export not configured in this app'**
  String get canvasParts_exportNotConfigured;

  /// No description provided for @canvasParts_handwritingUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Handwriting recognition is not available on this platform'**
  String get canvasParts_handwritingUnavailable;

  /// No description provided for @canvasParts_handwritingModelLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load handwriting model'**
  String get canvasParts_handwritingModelLoadFailed;

  /// No description provided for @canvasParts_thisDocument.
  ///
  /// In en, this message translates to:
  /// **'this document'**
  String get canvasParts_thisDocument;

  /// No description provided for @canvasParts_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get canvasParts_cancel;

  /// No description provided for @canvasParts_delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get canvasParts_delete;

  /// No description provided for @toolbarTools_allBorders.
  ///
  /// In en, this message translates to:
  /// **'All Borders'**
  String get toolbarTools_allBorders;

  /// No description provided for @toolbarTools_outsideBorders.
  ///
  /// In en, this message translates to:
  /// **'Outside'**
  String get toolbarTools_outsideBorders;

  /// No description provided for @toolbarTools_insideBorders.
  ///
  /// In en, this message translates to:
  /// **'Inside'**
  String get toolbarTools_insideBorders;

  /// No description provided for @toolbarTools_bottomBorder.
  ///
  /// In en, this message translates to:
  /// **'Bottom'**
  String get toolbarTools_bottomBorder;

  /// No description provided for @toolbarTools_noBorders.
  ///
  /// In en, this message translates to:
  /// **'No Borders'**
  String get toolbarTools_noBorders;

  /// No description provided for @toolbarTools_newSpreadsheet.
  ///
  /// In en, this message translates to:
  /// **'New Spreadsheet'**
  String get toolbarTools_newSpreadsheet;

  /// No description provided for @toolbarTools_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get toolbarTools_cancel;

  /// No description provided for @toolbarTools_create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get toolbarTools_create;

  /// No description provided for @collabShare_inviteCanvas.
  ///
  /// In en, this message translates to:
  /// **'Invite to canvas'**
  String get collabShare_inviteCanvas;

  /// No description provided for @collabShare_copyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get collabShare_copyLink;

  /// No description provided for @collabShare_generateNew.
  ///
  /// In en, this message translates to:
  /// **'Generate new'**
  String get collabShare_generateNew;

  /// No description provided for @collabShare_close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get collabShare_close;

  /// No description provided for @collabShare_linkCopied.
  ///
  /// In en, this message translates to:
  /// **'Link copied'**
  String get collabShare_linkCopied;

  /// No description provided for @collabShare_retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get collabShare_retry;

  /// No description provided for @imageFeatures_errorLoading.
  ///
  /// In en, this message translates to:
  /// **'Error loading image'**
  String get imageFeatures_errorLoading;

  /// No description provided for @imageFeatures_errorDecoding.
  ///
  /// In en, this message translates to:
  /// **'Error decoding image'**
  String get imageFeatures_errorDecoding;

  /// No description provided for @imageFeatures_beingEdited.
  ///
  /// In en, this message translates to:
  /// **'Image is being edited by another collaborator'**
  String get imageFeatures_beingEdited;

  /// No description provided for @imageFeatures_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get imageFeatures_cancel;

  /// No description provided for @imageFeatures_delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get imageFeatures_delete;

  /// No description provided for @uiOverlays_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get uiOverlays_cancel;

  /// No description provided for @uiOverlays_cluster.
  ///
  /// In en, this message translates to:
  /// **'Cluster'**
  String get uiOverlays_cluster;

  /// No description provided for @uiOverlays_ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get uiOverlays_ok;

  /// No description provided for @uiOverlays_quizMe.
  ///
  /// In en, this message translates to:
  /// **'Quiz me'**
  String get uiOverlays_quizMe;

  /// No description provided for @uiOverlays_quizMeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Interactive exam on your notes'**
  String get uiOverlays_quizMeSubtitle;

  /// No description provided for @uiOverlays_trendsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Progress + topics to reinforce'**
  String get uiOverlays_trendsSubtitle;

  /// No description provided for @uiOverlays_lasso.
  ///
  /// In en, this message translates to:
  /// **'Lasso'**
  String get uiOverlays_lasso;

  /// No description provided for @uiOverlays_rect.
  ///
  /// In en, this message translates to:
  /// **'Rect'**
  String get uiOverlays_rect;

  /// No description provided for @uiOverlays_ellipse.
  ///
  /// In en, this message translates to:
  /// **'Ellipse'**
  String get uiOverlays_ellipse;

  /// No description provided for @svgImport_title.
  ///
  /// In en, this message translates to:
  /// **'Import SVG'**
  String get svgImport_title;

  /// No description provided for @svgImport_pasteFromClipboard.
  ///
  /// In en, this message translates to:
  /// **'Paste from clipboard'**
  String get svgImport_pasteFromClipboard;

  /// No description provided for @svgImport_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get svgImport_cancel;

  /// No description provided for @svgImport_import.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get svgImport_import;

  /// No description provided for @noteImport_importingNotes.
  ///
  /// In en, this message translates to:
  /// **'Importing Notes'**
  String get noteImport_importingNotes;

  /// No description provided for @noteImport_noHandwrittenContent.
  ///
  /// In en, this message translates to:
  /// **'No handwritten content found in the file.'**
  String get noteImport_noHandwrittenContent;

  /// No description provided for @noteImport_importedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Imported {count} strokes successfully.'**
  String noteImport_importedSuccess(int count);

  /// No description provided for @noteImport_importFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String noteImport_importFailed(String error);

  /// No description provided for @branching_branchName.
  ///
  /// In en, this message translates to:
  /// **'Branch name'**
  String get branching_branchName;

  /// No description provided for @branching_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get branching_cancel;

  /// No description provided for @branching_create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get branching_create;

  /// No description provided for @branching_newBranch.
  ///
  /// In en, this message translates to:
  /// **'New Branch'**
  String get branching_newBranch;

  /// No description provided for @branching_forkFromEvent.
  ///
  /// In en, this message translates to:
  /// **'Fork from event {current} of {total}'**
  String branching_forkFromEvent(int current, int total);

  /// No description provided for @branching_forkFromBranch.
  ///
  /// In en, this message translates to:
  /// **'Fork from \"{branchName}\"'**
  String branching_forkFromBranch(String branchName);

  /// No description provided for @branching_defaultBranchName.
  ///
  /// In en, this message translates to:
  /// **'Branch {time}'**
  String branching_defaultBranchName(String time);

  /// No description provided for @branching_untitledBranch.
  ///
  /// In en, this message translates to:
  /// **'Untitled Branch'**
  String get branching_untitledBranch;

  /// No description provided for @audioSync_recordingStoppedOnBranchSwitch.
  ///
  /// In en, this message translates to:
  /// **'Recording stopped — switching branch'**
  String get audioSync_recordingStoppedOnBranchSwitch;

  /// No description provided for @audioSync_quotaReachedAutoStop.
  ///
  /// In en, this message translates to:
  /// **'Voice minutes quota reached — recording stopped'**
  String get audioSync_quotaReachedAutoStop;

  /// No description provided for @audioSync_downloadFailedOffline.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t download the recording — check your connection'**
  String get audioSync_downloadFailedOffline;

  /// No description provided for @toolbarTool_panMode.
  ///
  /// In en, this message translates to:
  /// **'Pan Mode'**
  String get toolbarTool_panMode;

  /// No description provided for @toolbarTool_stylusOnlyMode.
  ///
  /// In en, this message translates to:
  /// **'Stylus Only Mode'**
  String get toolbarTool_stylusOnlyMode;

  /// No description provided for @toolbarTool_lassoSelection.
  ///
  /// In en, this message translates to:
  /// **'Lasso Selection'**
  String get toolbarTool_lassoSelection;

  /// No description provided for @toolbarTool_ruler.
  ///
  /// In en, this message translates to:
  /// **'Ruler'**
  String get toolbarTool_ruler;

  /// No description provided for @toolbarTool_minimap.
  ///
  /// In en, this message translates to:
  /// **'Minimap'**
  String get toolbarTool_minimap;

  /// No description provided for @toolbarTool_worldView.
  ///
  /// In en, this message translates to:
  /// **'Mappamondo view'**
  String get toolbarTool_worldView;

  /// No description provided for @toolbarTool_worldViewTooltip.
  ///
  /// In en, this message translates to:
  /// **'Zoom out to see the entire canvas'**
  String get toolbarTool_worldViewTooltip;

  /// No description provided for @monumentNudge_messageWithLabel.
  ///
  /// In en, this message translates to:
  /// **'🏛️ \"{label}\" has become a landmark of your Palace. Consider making it bigger or a distinctive color — landmarks anchor memory.'**
  String monumentNudge_messageWithLabel(String label);

  /// No description provided for @monumentNudge_dismissCta.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get monumentNudge_dismissCta;

  /// No description provided for @toolbarTool_vectorPen.
  ///
  /// In en, this message translates to:
  /// **'Vector Pen Tool'**
  String get toolbarTool_vectorPen;

  /// No description provided for @toolbarTool_digitalText.
  ///
  /// In en, this message translates to:
  /// **'Digital Text'**
  String get toolbarTool_digitalText;

  /// No description provided for @toolbarTool_insertImage.
  ///
  /// In en, this message translates to:
  /// **'Insert Image'**
  String get toolbarTool_insertImage;

  /// No description provided for @toolbarTool_latexMath.
  ///
  /// In en, this message translates to:
  /// **'LaTeX / Math Editor'**
  String get toolbarTool_latexMath;

  /// No description provided for @toolbarTool_spreadsheet.
  ///
  /// In en, this message translates to:
  /// **'Spreadsheet'**
  String get toolbarTool_spreadsheet;

  /// No description provided for @toolbarTool_sectionArtboard.
  ///
  /// In en, this message translates to:
  /// **'Section / Artboard'**
  String get toolbarTool_sectionArtboard;

  /// No description provided for @toolbarTool_searchHandwriting.
  ///
  /// In en, this message translates to:
  /// **'Search Handwriting'**
  String get toolbarTool_searchHandwriting;

  /// No description provided for @hwSearch_allPagesTitle.
  ///
  /// In en, this message translates to:
  /// **'All pages'**
  String get hwSearch_allPagesTitle;

  /// No description provided for @hwSearch_allPagesBody.
  ///
  /// In en, this message translates to:
  /// **'Search in ALL your gallery canvases, not just this one. When off, you only search here.'**
  String get hwSearch_allPagesBody;

  /// No description provided for @hwSearch_caseSensitiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Case sensitive'**
  String get hwSearch_caseSensitiveTitle;

  /// No description provided for @hwSearch_caseSensitiveBody.
  ///
  /// In en, this message translates to:
  /// **'Distinguishes uppercase and lowercase. \"Rome\" doesn\'t match \"rome\" when on.'**
  String get hwSearch_caseSensitiveBody;

  /// No description provided for @hwSearch_wholeWordTitle.
  ///
  /// In en, this message translates to:
  /// **'Whole word'**
  String get hwSearch_wholeWordTitle;

  /// No description provided for @hwSearch_wholeWordBody.
  ///
  /// In en, this message translates to:
  /// **'Finds only whole words. \"art\" doesn\'t match \"smart\" or \"artist\" when on.'**
  String get hwSearch_wholeWordBody;

  /// No description provided for @hwSearch_fuzzyTitle.
  ///
  /// In en, this message translates to:
  /// **'Typo-tolerant search'**
  String get hwSearch_fuzzyTitle;

  /// No description provided for @hwSearch_fuzzyBody.
  ///
  /// In en, this message translates to:
  /// **'Finds words with up to 2 typing errors. Useful for fast handwriting or quick notes.'**
  String get hwSearch_fuzzyBody;

  /// No description provided for @hwSearch_regexTitle.
  ///
  /// In en, this message translates to:
  /// **'Regex'**
  String get hwSearch_regexTitle;

  /// No description provided for @hwSearch_regexBody.
  ///
  /// In en, this message translates to:
  /// **'For advanced users: use regular expression patterns (e.g. \"ca[sr]a\" for cara or casa).'**
  String get hwSearch_regexBody;

  /// No description provided for @hwSearch_visibleAreaTitle.
  ///
  /// In en, this message translates to:
  /// **'Visible area only'**
  String get hwSearch_visibleAreaTitle;

  /// No description provided for @hwSearch_visibleAreaBody.
  ///
  /// In en, this message translates to:
  /// **'Search only the area visible on screen. Useful to narrow down to a specific zone.'**
  String get hwSearch_visibleAreaBody;

  /// No description provided for @hwSearch_gotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get hwSearch_gotIt;

  /// No description provided for @hwSearch_caseSensitiveTooltip.
  ///
  /// In en, this message translates to:
  /// **'Case sensitive matching'**
  String get hwSearch_caseSensitiveTooltip;

  /// No description provided for @hwSearch_wholeWordTooltip.
  ///
  /// In en, this message translates to:
  /// **'Whole words only'**
  String get hwSearch_wholeWordTooltip;

  /// No description provided for @hwSearch_fuzzyTooltip.
  ///
  /// In en, this message translates to:
  /// **'Typo-tolerant (≤2 errors)'**
  String get hwSearch_fuzzyTooltip;

  /// No description provided for @hwSearch_regexTooltip.
  ///
  /// In en, this message translates to:
  /// **'Regex patterns (advanced users)'**
  String get hwSearch_regexTooltip;

  /// No description provided for @hwSearch_visibleLabel.
  ///
  /// In en, this message translates to:
  /// **'Visible'**
  String get hwSearch_visibleLabel;

  /// No description provided for @hwSearch_visibleTooltip.
  ///
  /// In en, this message translates to:
  /// **'Only the area you see on screen'**
  String get hwSearch_visibleTooltip;

  /// No description provided for @hwSearch_searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search handwriting...'**
  String get hwSearch_searchHint;

  /// No description provided for @hwSearch_filtersHelpTooltip.
  ///
  /// In en, this message translates to:
  /// **'What do the filters do?'**
  String get hwSearch_filtersHelpTooltip;

  /// No description provided for @hwSearch_copiedResults.
  ///
  /// In en, this message translates to:
  /// **'Copied {count} results'**
  String hwSearch_copiedResults(int count);

  /// No description provided for @hwSearch_replaceHint.
  ///
  /// In en, this message translates to:
  /// **'Replace with...'**
  String get hwSearch_replaceHint;

  /// No description provided for @hwSearch_wordLabel.
  ///
  /// In en, this message translates to:
  /// **'Word'**
  String get hwSearch_wordLabel;

  /// No description provided for @hwSearch_fuzzyLabel.
  ///
  /// In en, this message translates to:
  /// **'Fuzzy'**
  String get hwSearch_fuzzyLabel;

  /// No description provided for @hwSearch_regexLabel.
  ///
  /// In en, this message translates to:
  /// **'Regex'**
  String get hwSearch_regexLabel;

  /// No description provided for @hwSearch_filtersTitle.
  ///
  /// In en, this message translates to:
  /// **'Search filters'**
  String get hwSearch_filtersTitle;

  /// No description provided for @buildUi_tapToReveal.
  ///
  /// In en, this message translates to:
  /// **'Tap to reveal'**
  String get buildUi_tapToReveal;

  /// No description provided for @buildUi_clusterPrev.
  ///
  /// In en, this message translates to:
  /// **'Previous Cluster'**
  String get buildUi_clusterPrev;

  /// No description provided for @buildUi_clusterNext.
  ///
  /// In en, this message translates to:
  /// **'Next Cluster'**
  String get buildUi_clusterNext;

  /// No description provided for @buildUi_addPage.
  ///
  /// In en, this message translates to:
  /// **'Add Page'**
  String get buildUi_addPage;

  /// No description provided for @buildUi_removePage.
  ///
  /// In en, this message translates to:
  /// **'Remove Page'**
  String get buildUi_removePage;

  /// No description provided for @buildUi_gridFreeFormatTooltip.
  ///
  /// In en, this message translates to:
  /// **'Tap: Grid/Free • Long: Format'**
  String get buildUi_gridFreeFormatTooltip;

  /// No description provided for @buildUi_backgroundTooltip.
  ///
  /// In en, this message translates to:
  /// **'Background (Transparent/Template)'**
  String get buildUi_backgroundTooltip;

  /// No description provided for @buildUi_autoFrameContent.
  ///
  /// In en, this message translates to:
  /// **'Auto-Frame Content'**
  String get buildUi_autoFrameContent;

  /// No description provided for @buildUi_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get buildUi_cancel;

  /// No description provided for @tabularLatex_generated.
  ///
  /// In en, this message translates to:
  /// **'LaTeX Table Generated'**
  String get tabularLatex_generated;

  /// No description provided for @tabularLatex_mergedCellsTitle.
  ///
  /// In en, this message translates to:
  /// **'Merged Cells Detected'**
  String get tabularLatex_mergedCellsTitle;

  /// No description provided for @tabularLatex_mergedCellsBody.
  ///
  /// In en, this message translates to:
  /// **'The selected range contains merged cells.\n\nMerged cells will use the master cell value only — slave cells will be skipped to avoid duplicate zeros.'**
  String get tabularLatex_mergedCellsBody;

  /// No description provided for @tabularLatex_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get tabularLatex_cancel;

  /// No description provided for @tabularLatex_continue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get tabularLatex_continue;

  /// No description provided for @tabularLatex_importTitle.
  ///
  /// In en, this message translates to:
  /// **'Import LaTeX Table'**
  String get tabularLatex_importTitle;

  /// No description provided for @tabularLatex_importHint.
  ///
  /// In en, this message translates to:
  /// **'Paste LaTeX tabular environment here'**
  String get tabularLatex_importHint;

  /// No description provided for @tabularLatex_import.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get tabularLatex_import;

  /// No description provided for @tabularLatex_noValidTable.
  ///
  /// In en, this message translates to:
  /// **'No valid LaTeX table found'**
  String get tabularLatex_noValidTable;

  /// No description provided for @tabularLatex_imported.
  ///
  /// In en, this message translates to:
  /// **'Imported {env} → {cols}×{rows} table'**
  String tabularLatex_imported(String env, int cols, int rows);

  /// No description provided for @tabularLatex_documentCopied.
  ///
  /// In en, this message translates to:
  /// **'.tex document copied to clipboard'**
  String get tabularLatex_documentCopied;

  /// No description provided for @componentSet_autoGroupByName.
  ///
  /// In en, this message translates to:
  /// **'Auto-group by name'**
  String get componentSet_autoGroupByName;

  /// No description provided for @componentSet_insertInstance.
  ///
  /// In en, this message translates to:
  /// **'Insert instance'**
  String get componentSet_insertInstance;

  /// No description provided for @socraticScratchpad_clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get socraticScratchpad_clear;

  /// No description provided for @socraticScratchpad_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get socraticScratchpad_cancel;

  /// No description provided for @socraticBubble_reflectMentally.
  ///
  /// In en, this message translates to:
  /// **'Reflect mentally, no sketch'**
  String get socraticBubble_reflectMentally;

  /// No description provided for @socraticBubble_sketchAndContinue.
  ///
  /// In en, this message translates to:
  /// **'Sketch a thought, AI continues'**
  String get socraticBubble_sketchAndContinue;

  /// No description provided for @socraticBubble_thinkOnly.
  ///
  /// In en, this message translates to:
  /// **'Think only'**
  String get socraticBubble_thinkOnly;

  /// No description provided for @socraticBubble_sketch.
  ///
  /// In en, this message translates to:
  /// **'Sketch'**
  String get socraticBubble_sketch;

  /// No description provided for @toolsArea_pages.
  ///
  /// In en, this message translates to:
  /// **'Pages'**
  String get toolsArea_pages;

  /// No description provided for @toolsArea_searchPdf.
  ///
  /// In en, this message translates to:
  /// **'Search PDF'**
  String get toolsArea_searchPdf;

  /// No description provided for @toolsArea_layout.
  ///
  /// In en, this message translates to:
  /// **'Layout'**
  String get toolsArea_layout;

  /// No description provided for @toolsArea_nightMode.
  ///
  /// In en, this message translates to:
  /// **'Night Mode'**
  String get toolsArea_nightMode;

  /// No description provided for @toolsArea_zoomToFit.
  ///
  /// In en, this message translates to:
  /// **'Zoom to Fit'**
  String get toolsArea_zoomToFit;

  /// No description provided for @toolsArea_annotate.
  ///
  /// In en, this message translates to:
  /// **'Annotate'**
  String get toolsArea_annotate;

  /// No description provided for @toolsArea_export.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get toolsArea_export;

  /// No description provided for @toolsArea_print.
  ///
  /// In en, this message translates to:
  /// **'Print'**
  String get toolsArea_print;

  /// No description provided for @toolsArea_present.
  ///
  /// In en, this message translates to:
  /// **'Present'**
  String get toolsArea_present;

  /// No description provided for @toolsArea_newBlankDocument.
  ///
  /// In en, this message translates to:
  /// **'New blank document'**
  String get toolsArea_newBlankDocument;

  /// No description provided for @toolsArea_newTable.
  ///
  /// In en, this message translates to:
  /// **'New Table'**
  String get toolsArea_newTable;

  /// No description provided for @toolsArea_deleteTable.
  ///
  /// In en, this message translates to:
  /// **'Delete Table'**
  String get toolsArea_deleteTable;

  /// No description provided for @toolsArea_bold.
  ///
  /// In en, this message translates to:
  /// **'Bold'**
  String get toolsArea_bold;

  /// No description provided for @toolsArea_italic.
  ///
  /// In en, this message translates to:
  /// **'Italic'**
  String get toolsArea_italic;

  /// No description provided for @toolsArea_borders.
  ///
  /// In en, this message translates to:
  /// **'Borders'**
  String get toolsArea_borders;

  /// No description provided for @toolsArea_clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get toolsArea_clear;

  /// No description provided for @toolsArea_alignLeft.
  ///
  /// In en, this message translates to:
  /// **'Left'**
  String get toolsArea_alignLeft;

  /// No description provided for @toolsArea_alignCenter.
  ///
  /// In en, this message translates to:
  /// **'Center'**
  String get toolsArea_alignCenter;

  /// No description provided for @toolsArea_alignRight.
  ///
  /// In en, this message translates to:
  /// **'Right'**
  String get toolsArea_alignRight;

  /// No description provided for @toolsArea_textColor.
  ///
  /// In en, this message translates to:
  /// **'Text Color'**
  String get toolsArea_textColor;

  /// No description provided for @toolsArea_fillColor.
  ///
  /// In en, this message translates to:
  /// **'Fill Color'**
  String get toolsArea_fillColor;

  /// No description provided for @toolsArea_insertRow.
  ///
  /// In en, this message translates to:
  /// **'Insert Row'**
  String get toolsArea_insertRow;

  /// No description provided for @toolsArea_deleteRow.
  ///
  /// In en, this message translates to:
  /// **'Delete Row'**
  String get toolsArea_deleteRow;

  /// No description provided for @toolsArea_insertCol.
  ///
  /// In en, this message translates to:
  /// **'Insert Col'**
  String get toolsArea_insertCol;

  /// No description provided for @toolsArea_deleteCol.
  ///
  /// In en, this message translates to:
  /// **'Delete Col'**
  String get toolsArea_deleteCol;

  /// No description provided for @toolsArea_moreActions.
  ///
  /// In en, this message translates to:
  /// **'More Actions'**
  String get toolsArea_moreActions;

  /// No description provided for @toolsArea_formulaReference.
  ///
  /// In en, this message translates to:
  /// **'Formula Reference'**
  String get toolsArea_formulaReference;

  /// No description provided for @toolsArea_switchPdf.
  ///
  /// In en, this message translates to:
  /// **'Switch PDF'**
  String get toolsArea_switchPdf;

  /// No description provided for @toolsArea_wheelMode.
  ///
  /// In en, this message translates to:
  /// **'Wheel mode'**
  String get toolsArea_wheelMode;

  /// No description provided for @toolsArea_pasteSvgHint.
  ///
  /// In en, this message translates to:
  /// **'Paste SVG content here...'**
  String get toolsArea_pasteSvgHint;

  /// No description provided for @latexEditor_info.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get latexEditor_info;

  /// No description provided for @latexEditor_searchCommands.
  ///
  /// In en, this message translates to:
  /// **'Search commands...'**
  String get latexEditor_searchCommands;

  /// No description provided for @latexEditor_color.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get latexEditor_color;

  /// No description provided for @latexEditor_commands.
  ///
  /// In en, this message translates to:
  /// **'Commands'**
  String get latexEditor_commands;

  /// No description provided for @latexEditor_latexCommands.
  ///
  /// In en, this message translates to:
  /// **'LaTeX Commands'**
  String get latexEditor_latexCommands;

  /// No description provided for @latexEditor_fontSize.
  ///
  /// In en, this message translates to:
  /// **'Size: {size}'**
  String latexEditor_fontSize(int size);

  /// No description provided for @latexSymbol_searchSymbol.
  ///
  /// In en, this message translates to:
  /// **'Search symbol...'**
  String get latexSymbol_searchSymbol;

  /// No description provided for @socraticScope_searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search topic (title or note)'**
  String get socraticScope_searchHint;

  /// No description provided for @timeTravel_previousSession.
  ///
  /// In en, this message translates to:
  /// **'Previous session'**
  String get timeTravel_previousSession;

  /// No description provided for @timeTravel_nextSession.
  ///
  /// In en, this message translates to:
  /// **'Next session'**
  String get timeTravel_nextSession;

  /// No description provided for @timeTravel_recoverInPresent.
  ///
  /// In en, this message translates to:
  /// **'Recover in the present'**
  String get timeTravel_recoverInPresent;

  /// No description provided for @timeTravel_exportTimelapse.
  ///
  /// In en, this message translates to:
  /// **'Export timelapse'**
  String get timeTravel_exportTimelapse;

  /// No description provided for @voiceRecording_options.
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get voiceRecording_options;

  /// No description provided for @voiceRecording_copyText.
  ///
  /// In en, this message translates to:
  /// **'Copy text'**
  String get voiceRecording_copyText;

  /// No description provided for @voiceRecording_reTranscribe.
  ///
  /// In en, this message translates to:
  /// **'Re-transcribe'**
  String get voiceRecording_reTranscribe;

  /// No description provided for @ghostMap_info.
  ///
  /// In en, this message translates to:
  /// **'Ghost Map info'**
  String get ghostMap_info;

  /// No description provided for @animTimeline_loop.
  ///
  /// In en, this message translates to:
  /// **'Loop'**
  String get animTimeline_loop;

  /// No description provided for @varProp_searchVariables.
  ///
  /// In en, this message translates to:
  /// **'Search {type} variables…'**
  String varProp_searchVariables(String type);

  /// No description provided for @connLabel_addLabelHint.
  ///
  /// In en, this message translates to:
  /// **'Add label...'**
  String get connLabel_addLabelHint;

  /// No description provided for @varManager_importW3CTokens.
  ///
  /// In en, this message translates to:
  /// **'Import W3C Tokens'**
  String get varManager_importW3CTokens;

  /// No description provided for @varManager_exportW3CTokens.
  ///
  /// In en, this message translates to:
  /// **'Export W3C Tokens'**
  String get varManager_exportW3CTokens;

  /// No description provided for @varManager_newCollection.
  ///
  /// In en, this message translates to:
  /// **'New Collection'**
  String get varManager_newCollection;

  /// No description provided for @varManager_searchVariables.
  ///
  /// In en, this message translates to:
  /// **'Search variables…'**
  String get varManager_searchVariables;

  /// No description provided for @varManager_groupHint.
  ///
  /// In en, this message translates to:
  /// **'Group (e.g. colors/primary)'**
  String get varManager_groupHint;

  /// No description provided for @varManager_pasteW3CHint.
  ///
  /// In en, this message translates to:
  /// **'Paste W3C DTCG JSON here…'**
  String get varManager_pasteW3CHint;

  /// No description provided for @tokenExport_copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get tokenExport_copy;

  /// No description provided for @tabularHandler_enterValueOrFormula.
  ///
  /// In en, this message translates to:
  /// **'Enter value or formula'**
  String get tabularHandler_enterValueOrFormula;

  /// No description provided for @syncPlayback_restart.
  ///
  /// In en, this message translates to:
  /// **'Restart'**
  String get syncPlayback_restart;

  /// No description provided for @syncPlayback_stop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get syncPlayback_stop;

  /// No description provided for @echoSearch_typeQuery.
  ///
  /// In en, this message translates to:
  /// **'Type query...'**
  String get echoSearch_typeQuery;

  /// No description provided for @imageViewer_grid.
  ///
  /// In en, this message translates to:
  /// **'Grid'**
  String get imageViewer_grid;

  /// No description provided for @imageViewer_histogram.
  ///
  /// In en, this message translates to:
  /// **'Histogram'**
  String get imageViewer_histogram;

  /// No description provided for @imageViewer_background.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get imageViewer_background;

  /// No description provided for @imageViewer_edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get imageViewer_edit;

  /// No description provided for @imageViewer_share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get imageViewer_share;

  /// No description provided for @voiceRecording_recordingName.
  ///
  /// In en, this message translates to:
  /// **'Recording name'**
  String get voiceRecording_recordingName;

  /// No description provided for @voiceRecording_enterName.
  ///
  /// In en, this message translates to:
  /// **'Enter name'**
  String get voiceRecording_enterName;

  /// No description provided for @voiceRecording_searchRecordings.
  ///
  /// In en, this message translates to:
  /// **'Search recordings...'**
  String get voiceRecording_searchRecordings;

  /// No description provided for @voiceRecording_name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get voiceRecording_name;

  /// No description provided for @tabular_mergeCells.
  ///
  /// In en, this message translates to:
  /// **'Merge cells'**
  String get tabular_mergeCells;

  /// No description provided for @tabular_unmergeCells.
  ///
  /// In en, this message translates to:
  /// **'Unmerge cells'**
  String get tabular_unmergeCells;

  /// No description provided for @tabular_numberFormat.
  ///
  /// In en, this message translates to:
  /// **'Number format'**
  String get tabular_numberFormat;

  /// No description provided for @tabular_validationRule.
  ///
  /// In en, this message translates to:
  /// **'Validation rule'**
  String get tabular_validationRule;

  /// No description provided for @tabular_conditionalFormat.
  ///
  /// In en, this message translates to:
  /// **'Conditional format'**
  String get tabular_conditionalFormat;

  /// No description provided for @tabular_generateLatex.
  ///
  /// In en, this message translates to:
  /// **'Generate LaTeX Table from Selection'**
  String get tabular_generateLatex;

  /// No description provided for @tabular_copyAsLatex.
  ///
  /// In en, this message translates to:
  /// **'Copy Selection as LaTeX'**
  String get tabular_copyAsLatex;

  /// No description provided for @tabular_generateTikz.
  ///
  /// In en, this message translates to:
  /// **'Generate TikZ Chart from Selection'**
  String get tabular_generateTikz;

  /// No description provided for @tabular_importLatex.
  ///
  /// In en, this message translates to:
  /// **'Import LaTeX → Spreadsheet'**
  String get tabular_importLatex;

  /// No description provided for @tabular_exportTex.
  ///
  /// In en, this message translates to:
  /// **'Export .tex File'**
  String get tabular_exportTex;

  /// No description provided for @tabular_freezePanes.
  ///
  /// In en, this message translates to:
  /// **'Freeze panes'**
  String get tabular_freezePanes;

  /// No description provided for @tabular_importCsv.
  ///
  /// In en, this message translates to:
  /// **'Import CSV'**
  String get tabular_importCsv;

  /// No description provided for @tabular_exportCsv.
  ///
  /// In en, this message translates to:
  /// **'Export CSV'**
  String get tabular_exportCsv;

  /// No description provided for @tabular_importXlsx.
  ///
  /// In en, this message translates to:
  /// **'Import XLSX'**
  String get tabular_importXlsx;

  /// No description provided for @tabular_exportXlsx.
  ///
  /// In en, this message translates to:
  /// **'Export XLSX'**
  String get tabular_exportXlsx;

  /// No description provided for @formulaRef_searchFunctions.
  ///
  /// In en, this message translates to:
  /// **'Search functions…'**
  String get formulaRef_searchFunctions;

  /// No description provided for @pdfFeatures_documentTitle.
  ///
  /// In en, this message translates to:
  /// **'Document title'**
  String get pdfFeatures_documentTitle;

  /// No description provided for @pdfToolbar_previousShiftEnter.
  ///
  /// In en, this message translates to:
  /// **'Previous (Shift+Enter)'**
  String get pdfToolbar_previousShiftEnter;

  /// No description provided for @knowledgeMap_searchClusters.
  ///
  /// In en, this message translates to:
  /// **'Search clusters...'**
  String get knowledgeMap_searchClusters;

  /// No description provided for @multiview_pen.
  ///
  /// In en, this message translates to:
  /// **'Pen'**
  String get multiview_pen;

  /// No description provided for @multiview_eraser.
  ///
  /// In en, this message translates to:
  /// **'Eraser'**
  String get multiview_eraser;

  /// No description provided for @multiview_pan.
  ///
  /// In en, this message translates to:
  /// **'Pan'**
  String get multiview_pan;

  /// No description provided for @multiview_brushType.
  ///
  /// In en, this message translates to:
  /// **'Brush type'**
  String get multiview_brushType;

  /// No description provided for @multiview_undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get multiview_undo;

  /// No description provided for @multiview_redo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get multiview_redo;

  /// No description provided for @multiview_exit.
  ///
  /// In en, this message translates to:
  /// **'Exit Multiview'**
  String get multiview_exit;

  /// No description provided for @multiview_changeLayout.
  ///
  /// In en, this message translates to:
  /// **'Change layout'**
  String get multiview_changeLayout;

  /// No description provided for @bookmarks_addNote.
  ///
  /// In en, this message translates to:
  /// **'Add a note...'**
  String get bookmarks_addNote;

  /// No description provided for @ruler_spacing.
  ///
  /// In en, this message translates to:
  /// **'Spacing (px)'**
  String get ruler_spacing;

  /// No description provided for @ruler_start.
  ///
  /// In en, this message translates to:
  /// **'Start (px)'**
  String get ruler_start;

  /// No description provided for @ruler_end.
  ///
  /// In en, this message translates to:
  /// **'End (px)'**
  String get ruler_end;

  /// No description provided for @dictionary_explainOneLine.
  ///
  /// In en, this message translates to:
  /// **'Explain it in one line…'**
  String get dictionary_explainOneLine;

  /// No description provided for @dictionary_rewriteWithoutCopying.
  ///
  /// In en, this message translates to:
  /// **'Rewrite without copying from the definition…'**
  String get dictionary_rewriteWithoutCopying;

  /// No description provided for @proColor_colorBlindnessPreview.
  ///
  /// In en, this message translates to:
  /// **'Color blindness preview'**
  String get proColor_colorBlindnessPreview;

  /// No description provided for @proColor_eyedropper.
  ///
  /// In en, this message translates to:
  /// **'Eyedropper'**
  String get proColor_eyedropper;

  /// No description provided for @proColor_copyHex.
  ///
  /// In en, this message translates to:
  /// **'Copy hex'**
  String get proColor_copyHex;

  /// No description provided for @proColor_pasteHex.
  ///
  /// In en, this message translates to:
  /// **'Paste hex'**
  String get proColor_pasteHex;

  /// No description provided for @drawing_sectionName.
  ///
  /// In en, this message translates to:
  /// **'Section name...'**
  String get drawing_sectionName;

  /// No description provided for @drawing_chartTitle.
  ///
  /// In en, this message translates to:
  /// **'Chart title…'**
  String get drawing_chartTitle;

  /// No description provided for @uiOverlay_min.
  ///
  /// In en, this message translates to:
  /// **'Min'**
  String get uiOverlay_min;

  /// No description provided for @uiOverlay_max.
  ///
  /// In en, this message translates to:
  /// **'Max'**
  String get uiOverlay_max;

  /// No description provided for @liquify_undoLastBrush.
  ///
  /// In en, this message translates to:
  /// **'Undo last brush'**
  String get liquify_undoLastBrush;

  /// No description provided for @legal_openWebVersion.
  ///
  /// In en, this message translates to:
  /// **'Open web version'**
  String get legal_openWebVersion;

  /// No description provided for @settings_addWord.
  ///
  /// In en, this message translates to:
  /// **'Add a word...'**
  String get settings_addWord;

  /// No description provided for @settings_yourFeedback.
  ///
  /// In en, this message translates to:
  /// **'Your feedback...'**
  String get settings_yourFeedback;

  /// No description provided for @latexRec_noFormula.
  ///
  /// In en, this message translates to:
  /// **'No formula recognized'**
  String get latexRec_noFormula;

  /// No description provided for @latexRec_formulaRecognized.
  ///
  /// In en, this message translates to:
  /// **'Formula recognized'**
  String get latexRec_formulaRecognized;

  /// No description provided for @latexRec_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get latexRec_cancel;

  /// No description provided for @latexRec_confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get latexRec_confirm;

  /// No description provided for @tabular_compareCategories.
  ///
  /// In en, this message translates to:
  /// **'Compare values by category'**
  String get tabular_compareCategories;

  /// No description provided for @tabular_showTrends.
  ///
  /// In en, this message translates to:
  /// **'Show trends over time'**
  String get tabular_showTrends;

  /// No description provided for @tabular_dataDistribution.
  ///
  /// In en, this message translates to:
  /// **'Show data distribution'**
  String get tabular_dataDistribution;

  /// No description provided for @tabular_proportions.
  ///
  /// In en, this message translates to:
  /// **'Show proportions'**
  String get tabular_proportions;

  /// No description provided for @tabular_filledTrends.
  ///
  /// In en, this message translates to:
  /// **'Filled trends over time'**
  String get tabular_filledTrends;

  /// No description provided for @tabular_composition.
  ///
  /// In en, this message translates to:
  /// **'Compare composition'**
  String get tabular_composition;

  /// No description provided for @tabular_horizontalCompare.
  ///
  /// In en, this message translates to:
  /// **'Horizontal value comparison'**
  String get tabular_horizontalCompare;

  /// No description provided for @tabular_waterfall.
  ///
  /// In en, this message translates to:
  /// **'Waterfall'**
  String get tabular_waterfall;

  /// No description provided for @tabular_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get tabular_cancel;

  /// No description provided for @tabular_continue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get tabular_continue;

  /// No description provided for @tabular_import.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get tabular_import;

  /// No description provided for @tabular_borderAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get tabular_borderAll;

  /// No description provided for @tabular_borderOutside.
  ///
  /// In en, this message translates to:
  /// **'Outside'**
  String get tabular_borderOutside;

  /// No description provided for @tabular_borderInside.
  ///
  /// In en, this message translates to:
  /// **'Inside'**
  String get tabular_borderInside;

  /// No description provided for @tabular_borderBottom.
  ///
  /// In en, this message translates to:
  /// **'Bottom'**
  String get tabular_borderBottom;

  /// No description provided for @tabular_borderNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get tabular_borderNone;

  /// No description provided for @pdfReaderExport_title.
  ///
  /// In en, this message translates to:
  /// **'Export Annotated PDF'**
  String get pdfReaderExport_title;

  /// No description provided for @pdfReaderExport_quality.
  ///
  /// In en, this message translates to:
  /// **'Quality: '**
  String get pdfReaderExport_quality;

  /// No description provided for @pdfReaderExport_bookmarkSummary.
  ///
  /// In en, this message translates to:
  /// **'Bookmark Summary'**
  String get pdfReaderExport_bookmarkSummary;

  /// No description provided for @pdfReaderExport_exporting.
  ///
  /// In en, this message translates to:
  /// **'Exporting...'**
  String get pdfReaderExport_exporting;

  /// No description provided for @pdfReaderExport_failed.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String pdfReaderExport_failed(String error);

  /// No description provided for @consent_acceptAll.
  ///
  /// In en, this message translates to:
  /// **'Accept all'**
  String get consent_acceptAll;

  /// No description provided for @consent_continueWithChoices.
  ///
  /// In en, this message translates to:
  /// **'Continue with these choices'**
  String get consent_continueWithChoices;

  /// No description provided for @consent_title.
  ///
  /// In en, this message translates to:
  /// **'Your privacy, your choices'**
  String get consent_title;

  /// No description provided for @consent_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Fluera respects GDPR. Choose what you want to share — you can change your mind anytime from Settings.'**
  String get consent_subtitle;

  /// No description provided for @consent_privacyLink.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get consent_privacyLink;

  /// No description provided for @consent_termsLink.
  ///
  /// In en, this message translates to:
  /// **'Terms of use'**
  String get consent_termsLink;

  /// No description provided for @consent_analyticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Product analytics'**
  String get consent_analyticsTitle;

  /// No description provided for @consent_analyticsBody.
  ///
  /// In en, this message translates to:
  /// **'Helps us understand which features you use most so we can improve Fluera. Only aggregated events — never the content of your notes.'**
  String get consent_analyticsBody;

  /// No description provided for @consent_aiTitle.
  ///
  /// In en, this message translates to:
  /// **'AI features'**
  String get consent_aiTitle;

  /// No description provided for @consent_aiBody.
  ///
  /// In en, this message translates to:
  /// **'Required for Ghost Map, Socratic Mode, LaTeX OCR and Exam Session. Some text from your notes is sent to Google Gemini. Without this option, AI features are disabled.'**
  String get consent_aiBody;

  /// No description provided for @consent_cloudTitle.
  ///
  /// In en, this message translates to:
  /// **'Cloud Sync'**
  String get consent_cloudTitle;

  /// No description provided for @consent_cloudBody.
  ///
  /// In en, this message translates to:
  /// **'Encrypted backup of your canvases on our servers so you can use them on other devices. Without this option, all data stays on this device only.'**
  String get consent_cloudBody;

  /// No description provided for @consent_crashTitle.
  ///
  /// In en, this message translates to:
  /// **'Crash reports'**
  String get consent_crashTitle;

  /// No description provided for @consent_crashBody.
  ///
  /// In en, this message translates to:
  /// **'Sends technical info when Fluera crashes (no content, no personal data) to help us fix bugs faster.'**
  String get consent_crashBody;

  /// No description provided for @exam_headerLabel.
  ///
  /// In en, this message translates to:
  /// **'Exam'**
  String get exam_headerLabel;

  /// No description provided for @exam_selectTopicsHint.
  ///
  /// In en, this message translates to:
  /// **'Select topics (max 10)'**
  String get exam_selectTopicsHint;

  /// No description provided for @exam_elaborationSaved.
  ///
  /// In en, this message translates to:
  /// **'Elaboration saved — it\'ll help you remember!'**
  String get exam_elaborationSaved;

  /// No description provided for @exam_growthPrefix.
  ///
  /// In en, this message translates to:
  /// **'🌱 {message}'**
  String exam_growthPrefix(String message);

  /// No description provided for @exam_calibrationTitle.
  ///
  /// In en, this message translates to:
  /// **'📊 Your calibration'**
  String get exam_calibrationTitle;

  /// No description provided for @exam_calibrationUnder.
  ///
  /// In en, this message translates to:
  /// **'Underconfident'**
  String get exam_calibrationUnder;

  /// No description provided for @exam_calibrationOver.
  ///
  /// In en, this message translates to:
  /// **'Overconfident'**
  String get exam_calibrationOver;

  /// No description provided for @exam_insightOverconfident.
  ///
  /// In en, this message translates to:
  /// **'You tend to overestimate yourself — try being more cautious before answering'**
  String get exam_insightOverconfident;

  /// No description provided for @exam_insightUnderconfident.
  ///
  /// In en, this message translates to:
  /// **'You underestimate yourself — trust your knowledge more!'**
  String get exam_insightUnderconfident;

  /// No description provided for @exam_insightCalibrated.
  ///
  /// In en, this message translates to:
  /// **'Excellent metacognitive calibration — you know your limits well'**
  String get exam_insightCalibrated;

  /// No description provided for @exam_resultsTitle.
  ///
  /// In en, this message translates to:
  /// **'Results'**
  String get exam_resultsTitle;

  /// No description provided for @exam_resultsSummary.
  ///
  /// In en, this message translates to:
  /// **'You faced {total} challenges — {correct} consolidated'**
  String exam_resultsSummary(int total, int correct);

  /// No description provided for @exam_resultsDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration: {minutes}m {seconds}s'**
  String exam_resultsDuration(int minutes, String seconds);

  /// No description provided for @exam_chunkPerformance.
  ///
  /// In en, this message translates to:
  /// **'📦 Per-block performance:'**
  String get exam_chunkPerformance;

  /// No description provided for @exam_reviewNeeded.
  ///
  /// In en, this message translates to:
  /// **'⏰ To review:'**
  String get exam_reviewNeeded;

  /// No description provided for @exam_errorReplay.
  ///
  /// In en, this message translates to:
  /// **'🔄 Strengthen {count} concepts — every review is growth'**
  String exam_errorReplay(int count);

  /// No description provided for @exam_backToCanvas.
  ///
  /// In en, this message translates to:
  /// **'Back to canvas'**
  String get exam_backToCanvas;

  /// No description provided for @exam_historyEmpty.
  ///
  /// In en, this message translates to:
  /// **'No completed sessions yet.'**
  String get exam_historyEmpty;

  /// No description provided for @exam_chunkBreakSummary.
  ///
  /// In en, this message translates to:
  /// **'{correct}/{total} consolidated in this block'**
  String exam_chunkBreakSummary(int correct, int total);

  /// No description provided for @exam_continueArrow.
  ///
  /// In en, this message translates to:
  /// **'Continue →'**
  String get exam_continueArrow;

  /// No description provided for @exam_exitTitle.
  ///
  /// In en, this message translates to:
  /// **'Exit exam?'**
  String get exam_exitTitle;

  /// No description provided for @exam_exitBody.
  ///
  /// In en, this message translates to:
  /// **'You\'ve already answered {count} questions.'**
  String exam_exitBody(int count);

  /// No description provided for @exam_exitContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get exam_exitContinue;

  /// No description provided for @exam_exitConfirm.
  ///
  /// In en, this message translates to:
  /// **'Exit'**
  String get exam_exitConfirm;

  /// No description provided for @bookmark_renameTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename bookmark'**
  String get bookmark_renameTitle;

  /// No description provided for @bookmark_deleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete bookmark?'**
  String get bookmark_deleteTitle;

  /// No description provided for @bookmark_deleteBody.
  ///
  /// In en, this message translates to:
  /// **'\"{label}\" will be removed permanently.'**
  String bookmark_deleteBody(String label);

  /// No description provided for @bookmark_newTitle.
  ///
  /// In en, this message translates to:
  /// **'New bookmark'**
  String get bookmark_newTitle;

  /// No description provided for @bookmark_nameHint.
  ///
  /// In en, this message translates to:
  /// **'Bookmark name'**
  String get bookmark_nameHint;

  /// No description provided for @graph_menuEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get graph_menuEdit;

  /// No description provided for @graph_menuTable.
  ///
  /// In en, this message translates to:
  /// **'Values Table'**
  String get graph_menuTable;

  /// No description provided for @graph_menuDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get graph_menuDuplicate;

  /// No description provided for @graph_menuResetViewport.
  ///
  /// In en, this message translates to:
  /// **'Reset Viewport'**
  String get graph_menuResetViewport;

  /// No description provided for @graph_menuDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get graph_menuDelete;

  /// No description provided for @graph_copyTable.
  ///
  /// In en, this message translates to:
  /// **'Copy table'**
  String get graph_copyTable;

  /// No description provided for @graph_reportCopied.
  ///
  /// In en, this message translates to:
  /// **'Analysis report copied'**
  String get graph_reportCopied;

  /// No description provided for @textToolbar_tabFormat.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get textToolbar_tabFormat;

  /// No description provided for @textToolbar_tabEffects.
  ///
  /// In en, this message translates to:
  /// **'Effects'**
  String get textToolbar_tabEffects;

  /// No description provided for @textToolbar_tabActions.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get textToolbar_tabActions;

  /// No description provided for @textToolbar_effectShadow.
  ///
  /// In en, this message translates to:
  /// **'Shadow'**
  String get textToolbar_effectShadow;

  /// No description provided for @textToolbar_effectBackground.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get textToolbar_effectBackground;

  /// No description provided for @textToolbar_effectBorder.
  ///
  /// In en, this message translates to:
  /// **'Border'**
  String get textToolbar_effectBorder;

  /// No description provided for @textToolbar_effectGradient.
  ///
  /// In en, this message translates to:
  /// **'Gradient'**
  String get textToolbar_effectGradient;

  /// No description provided for @textToolbar_effectGlow.
  ///
  /// In en, this message translates to:
  /// **'Glow'**
  String get textToolbar_effectGlow;

  /// No description provided for @textToolbar_actionDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get textToolbar_actionDuplicate;

  /// No description provided for @textToolbar_actionCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get textToolbar_actionCopy;

  /// No description provided for @pdfText_pageHeader.
  ///
  /// In en, this message translates to:
  /// **'Page {page} — Extracted text'**
  String pdfText_pageHeader(int page);

  /// No description provided for @pdfText_stats.
  ///
  /// In en, this message translates to:
  /// **'{words} words · {chars} characters'**
  String pdfText_stats(int words, int chars);

  /// No description provided for @pdfText_searchTooltip.
  ///
  /// In en, this message translates to:
  /// **'Search in text'**
  String get pdfText_searchTooltip;

  /// No description provided for @pdfText_searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search in text…'**
  String get pdfText_searchHint;

  /// No description provided for @pdfText_copied.
  ///
  /// In en, this message translates to:
  /// **'Copied!'**
  String get pdfText_copied;

  /// No description provided for @pdfText_copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get pdfText_copy;

  /// No description provided for @pdfText_extracting.
  ///
  /// In en, this message translates to:
  /// **'Extracting…'**
  String get pdfText_extracting;

  /// No description provided for @pdfText_empty.
  ///
  /// In en, this message translates to:
  /// **'No text found.\nThis might be a scanned PDF.'**
  String get pdfText_empty;

  /// No description provided for @pdfText_noResults.
  ///
  /// In en, this message translates to:
  /// **'No results for \"{query}\".'**
  String pdfText_noResults(String query);

  /// No description provided for @fow_resultsTitleMilestone.
  ///
  /// In en, this message translates to:
  /// **'Memory Palace Strong!'**
  String get fow_resultsTitleMilestone;

  /// No description provided for @fow_resultsTitleRedWall.
  ///
  /// In en, this message translates to:
  /// **'Zones to Strengthen Identified'**
  String get fow_resultsTitleRedWall;

  /// No description provided for @fow_resultsTitleDefault.
  ///
  /// In en, this message translates to:
  /// **'Challenge Results'**
  String get fow_resultsTitleDefault;

  /// No description provided for @fow_historyEmpty.
  ///
  /// In en, this message translates to:
  /// **'No previous sessions'**
  String get fow_historyEmpty;

  /// No description provided for @fowInfo_nodeHidden.
  ///
  /// In en, this message translates to:
  /// **'Hidden'**
  String get fowInfo_nodeHidden;

  /// No description provided for @fowInfo_nodeRecalled.
  ///
  /// In en, this message translates to:
  /// **'Recalled'**
  String get fowInfo_nodeRecalled;

  /// No description provided for @fowInfo_nodeForgotten.
  ///
  /// In en, this message translates to:
  /// **'Forgotten'**
  String get fowInfo_nodeForgotten;

  /// No description provided for @fowInfo_nodeBlindSpot.
  ///
  /// In en, this message translates to:
  /// **'Blind Spot'**
  String get fowInfo_nodeBlindSpot;

  /// No description provided for @fowInfo_nodeRevealed.
  ///
  /// In en, this message translates to:
  /// **'Revealed'**
  String get fowInfo_nodeRevealed;

  /// No description provided for @atlas_extractFn.
  ///
  /// In en, this message translates to:
  /// **'Extract ƒ'**
  String get atlas_extractFn;

  /// No description provided for @atlas_formulaCount.
  ///
  /// In en, this message translates to:
  /// **'{count} formulas'**
  String atlas_formulaCount(int count);

  /// No description provided for @atlas_extractCount.
  ///
  /// In en, this message translates to:
  /// **'Extract ({count})'**
  String atlas_extractCount(int count);

  /// No description provided for @paywall_done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get paywall_done;

  /// No description provided for @paywall_featureAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get paywall_featureAll;

  /// No description provided for @paywall_featureCanvasPen.
  ///
  /// In en, this message translates to:
  /// **'Canvas + pen'**
  String get paywall_featureCanvasPen;

  /// No description provided for @paywall_featurePdfImport.
  ///
  /// In en, this message translates to:
  /// **'PDF/Image import'**
  String get paywall_featurePdfImport;

  /// No description provided for @paywall_featureAudioSync.
  ///
  /// In en, this message translates to:
  /// **'Audio sync'**
  String get paywall_featureAudioSync;

  /// No description provided for @paywall_featureBrushes.
  ///
  /// In en, this message translates to:
  /// **'Brushes'**
  String get paywall_featureBrushes;

  /// No description provided for @paywall_featureExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get paywall_featureExport;

  /// No description provided for @paywall_featureCloudSync.
  ///
  /// In en, this message translates to:
  /// **'Cloud Sync'**
  String get paywall_featureCloudSync;

  /// No description provided for @paywall_brushesBase.
  ///
  /// In en, this message translates to:
  /// **'3 base'**
  String get paywall_brushesBase;

  /// No description provided for @paywall_purchaseLinkNotFound.
  ///
  /// In en, this message translates to:
  /// **'Purchase link not found for this plan.'**
  String get paywall_purchaseLinkNotFound;

  /// No description provided for @logout_tooltip.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get logout_tooltip;

  /// No description provided for @logout_dialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign out?'**
  String get logout_dialogTitle;

  /// No description provided for @logout_dialogBody.
  ///
  /// In en, this message translates to:
  /// **'Your canvases stay safely saved, visible only to you when you sign back in. Another account won\'t be able to see them.'**
  String get logout_dialogBody;

  /// No description provided for @logout_exit.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get logout_exit;

  /// No description provided for @exam_iniziaCta.
  ///
  /// In en, this message translates to:
  /// **'Start exam →'**
  String get exam_iniziaCta;

  /// No description provided for @exam_iniziaPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing…'**
  String get exam_iniziaPreparing;

  /// No description provided for @exam_iniziaSelectAtLeastOne.
  ///
  /// In en, this message translates to:
  /// **'Select at least one topic'**
  String get exam_iniziaSelectAtLeastOne;

  /// No description provided for @exam_answer_writeByHand.
  ///
  /// In en, this message translates to:
  /// **'Answer by hand'**
  String get exam_answer_writeByHand;

  /// No description provided for @exam_answer_editAnswer.
  ///
  /// In en, this message translates to:
  /// **'Edit answer'**
  String get exam_answer_editAnswer;

  /// No description provided for @exam_answer_writeByHandSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Opens fullscreen for stylus writing'**
  String get exam_answer_writeByHandSubtitle;

  /// No description provided for @exam_answer_writeFormulaHint.
  ///
  /// In en, this message translates to:
  /// **'Write the formula (e.g. F = ma)…'**
  String get exam_answer_writeFormulaHint;

  /// No description provided for @exam_answer_writeAnswerHint.
  ///
  /// In en, this message translates to:
  /// **'Write your answer…'**
  String get exam_answer_writeAnswerHint;

  /// No description provided for @exam_answer_emptyValidation.
  ///
  /// In en, this message translates to:
  /// **'✍️ Write an answer before sending'**
  String get exam_answer_emptyValidation;

  /// No description provided for @exam_answer_minLengthValidation.
  ///
  /// In en, this message translates to:
  /// **'✍️ At least {min} characters needed (you\'re at {current})'**
  String exam_answer_minLengthValidation(int min, int current);

  /// No description provided for @exam_answer_discardTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard answer?'**
  String get exam_answer_discardTitle;

  /// No description provided for @exam_answer_discardBody.
  ///
  /// In en, this message translates to:
  /// **'You have an unsent answer. Closing now will discard it.'**
  String get exam_answer_discardBody;

  /// No description provided for @exam_answer_keepWriting.
  ///
  /// In en, this message translates to:
  /// **'Keep writing'**
  String get exam_answer_keepWriting;

  /// No description provided for @exam_answer_discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get exam_answer_discard;

  /// No description provided for @exam_answer_send.
  ///
  /// In en, this message translates to:
  /// **'Send answer'**
  String get exam_answer_send;

  /// No description provided for @exam_answer_confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get exam_answer_confirm;

  /// No description provided for @exam_answer_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get exam_answer_cancel;

  /// No description provided for @exam_answer_pageTitleOpen.
  ///
  /// In en, this message translates to:
  /// **'Open answer'**
  String get exam_answer_pageTitleOpen;

  /// No description provided for @exam_answer_pageTitleFormula.
  ///
  /// In en, this message translates to:
  /// **'Formula'**
  String get exam_answer_pageTitleFormula;

  /// No description provided for @exam_answer_words.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No words} =1{1 word} other{{count} words}}'**
  String exam_answer_words(int count);

  /// No description provided for @exam_answer_yourAnswerLabel.
  ///
  /// In en, this message translates to:
  /// **'Your answer'**
  String get exam_answer_yourAnswerLabel;

  /// No description provided for @exam_answer_writeFormulaLabel.
  ///
  /// In en, this message translates to:
  /// **'Write the formula / calculation'**
  String get exam_answer_writeFormulaLabel;

  /// No description provided for @exam_loading_phaseRead.
  ///
  /// In en, this message translates to:
  /// **'Reading your notes…'**
  String get exam_loading_phaseRead;

  /// No description provided for @exam_loading_phaseAnalyze.
  ///
  /// In en, this message translates to:
  /// **'Analyzing key concepts…'**
  String get exam_loading_phaseAnalyze;

  /// No description provided for @exam_loading_phaseGenerate.
  ///
  /// In en, this message translates to:
  /// **'Generating questions…'**
  String get exam_loading_phaseGenerate;

  /// No description provided for @exam_loading_phaseValidate.
  ///
  /// In en, this message translates to:
  /// **'Verifying pedagogical quality…'**
  String get exam_loading_phaseValidate;

  /// No description provided for @exam_loading_phaseReady.
  ///
  /// In en, this message translates to:
  /// **'Ready!'**
  String get exam_loading_phaseReady;

  /// No description provided for @exam_loading_atlasWorking.
  ///
  /// In en, this message translates to:
  /// **'🌌 Atlas at work…'**
  String get exam_loading_atlasWorking;

  /// No description provided for @exam_loading_generating.
  ///
  /// In en, this message translates to:
  /// **'🌌 Generating questions…'**
  String get exam_loading_generating;

  /// No description provided for @exam_elaboration_writeByHand.
  ///
  /// In en, this message translates to:
  /// **'Elaborate by hand'**
  String get exam_elaboration_writeByHand;

  /// No description provided for @exam_elaboration_editElaboration.
  ///
  /// In en, this message translates to:
  /// **'Edit elaboration ({chars} characters)'**
  String exam_elaboration_editElaboration(int chars);

  /// No description provided for @exam_elaboration_save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get exam_elaboration_save;

  /// No description provided for @exam_elaboration_promptOverconfident.
  ///
  /// In en, this message translates to:
  /// **'Rewrite in your own words. High-confidence errors stick 3× better when you re-elaborate the concept.'**
  String get exam_elaboration_promptOverconfident;

  /// No description provided for @exam_elaboration_promptStandard.
  ///
  /// In en, this message translates to:
  /// **'Rewrite in your own words to consolidate.\n\nQuestion: {question}\n\nCorrect answer: {answer}'**
  String exam_elaboration_promptStandard(String question, String answer);

  /// No description provided for @exam_elaboration_cardOverconfident.
  ///
  /// In en, this message translates to:
  /// **'⚡ Rewrite in your own words — high-confidence errors stick 3× better when re-elaborated!'**
  String get exam_elaboration_cardOverconfident;

  /// No description provided for @exam_elaboration_cardStandard.
  ///
  /// In en, this message translates to:
  /// **'✍️ Rewrite in your own words to consolidate:'**
  String get exam_elaboration_cardStandard;

  /// No description provided for @exam_error_quotaExceeded.
  ///
  /// In en, this message translates to:
  /// **'You\'ve hit today\'s AI limit. Try again later or upgrade to Pro for more quota.'**
  String get exam_error_quotaExceeded;

  /// No description provided for @exam_error_offline.
  ///
  /// In en, this message translates to:
  /// **'No connection. Exam mode requires internet — reconnect and try again.'**
  String get exam_error_offline;

  /// No description provided for @exam_error_timeout.
  ///
  /// In en, this message translates to:
  /// **'AI is taking too long. Try again in a moment.'**
  String get exam_error_timeout;

  /// No description provided for @exam_error_unexpected.
  ///
  /// In en, this message translates to:
  /// **'Unexpected error: {detail}'**
  String exam_error_unexpected(String detail);

  /// No description provided for @exam_error_emptyContent.
  ///
  /// In en, this message translates to:
  /// **'Not enough content. Add more notes!'**
  String get exam_error_emptyContent;

  /// No description provided for @exam_error_replayFailed.
  ///
  /// In en, this message translates to:
  /// **'Can\'t generate variants. Try again!'**
  String get exam_error_replayFailed;

  /// No description provided for @exam_error_evaluationFailed.
  ///
  /// In en, this message translates to:
  /// **'\n⚠️ Error. Correct answer: {answer}'**
  String exam_error_evaluationFailed(String answer);

  /// No description provided for @exam_error_openFullscreenFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open answer page: {error}'**
  String exam_error_openFullscreenFailed(String error);

  /// No description provided for @exam_error_openElaborationFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open elaboration: {error}'**
  String exam_error_openElaborationFailed(String error);

  /// No description provided for @exam_hint_fallback.
  ///
  /// In en, this message translates to:
  /// **'💡 Think about the fundamental concepts!'**
  String get exam_hint_fallback;

  /// No description provided for @exam_difficultyBoosted.
  ///
  /// In en, this message translates to:
  /// **'🎯 Level up — harder questions!'**
  String get exam_difficultyBoosted;

  /// No description provided for @exam_evaluating.
  ///
  /// In en, this message translates to:
  /// **'Evaluating answer…'**
  String get exam_evaluating;

  /// No description provided for @exam_replayLoading.
  ///
  /// In en, this message translates to:
  /// **'🔄 Generating review variants…'**
  String get exam_replayLoading;

  /// No description provided for @exam_emptyClustersHint.
  ///
  /// In en, this message translates to:
  /// **'📝 Write some notes before starting the exam!'**
  String get exam_emptyClustersHint;

  /// No description provided for @exam_noBlindSpots.
  ///
  /// In en, this message translates to:
  /// **'🌫️ No blind spots to test. You remembered everything!'**
  String get exam_noBlindSpots;

  /// No description provided for @exam_noRecognizableText.
  ///
  /// In en, this message translates to:
  /// **'🔍 No recognizable text. Add written or digital text!'**
  String get exam_noRecognizableText;

  /// No description provided for @exam_topicGroup_orphan.
  ///
  /// In en, this message translates to:
  /// **'Other notes'**
  String get exam_topicGroup_orphan;

  /// No description provided for @exam_antiCramming_title.
  ///
  /// In en, this message translates to:
  /// **'You\'ve studied recently'**
  String get exam_antiCramming_title;

  /// No description provided for @exam_antiCramming_body.
  ///
  /// In en, this message translates to:
  /// **'You completed an exam on this topic {when}.'**
  String exam_antiCramming_body(String when);

  /// No description provided for @exam_antiCramming_explainer.
  ///
  /// In en, this message translates to:
  /// **'Memory consolidates BETTER with spaced practice (spacing effect, Ebbinghaus 1885). Re-running the exam now feels like mastery but reduces long-term retention.'**
  String get exam_antiCramming_explainer;

  /// No description provided for @exam_antiCramming_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get exam_antiCramming_cancel;

  /// No description provided for @exam_antiCramming_proceed.
  ///
  /// In en, this message translates to:
  /// **'Run anyway'**
  String get exam_antiCramming_proceed;

  /// No description provided for @exam_scopeBanner_viewport.
  ///
  /// In en, this message translates to:
  /// **'📍 {preselected} topics pre-selected from the visible area · Tap to edit'**
  String exam_scopeBanner_viewport(int preselected);

  /// No description provided for @exam_scopeBanner_lasso.
  ///
  /// In en, this message translates to:
  /// **'🎯 {preselected} topics pre-selected from the selection · Tap to edit'**
  String exam_scopeBanner_lasso(int preselected);

  /// No description provided for @exam_scopeBanner_showAll.
  ///
  /// In en, this message translates to:
  /// **'Show all'**
  String get exam_scopeBanner_showAll;

  /// No description provided for @exam_scopeBanner_deselectAll.
  ///
  /// In en, this message translates to:
  /// **'Deselect all'**
  String get exam_scopeBanner_deselectAll;

  /// No description provided for @exam_dashboardMenu.
  ///
  /// In en, this message translates to:
  /// **'📊 Exam dashboard'**
  String get exam_dashboardMenu;

  /// No description provided for @relativeTime_secondsAgo.
  ///
  /// In en, this message translates to:
  /// **'a few seconds ago'**
  String get relativeTime_secondsAgo;

  /// No description provided for @relativeTime_minutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 minute ago} other{{count} minutes ago}}'**
  String relativeTime_minutesAgo(int count);

  /// No description provided for @relativeTime_hoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 hour ago} other{{count} hours ago}}'**
  String relativeTime_hoursAgo(int count);

  /// No description provided for @relativeTime_yesterday.
  ///
  /// In en, this message translates to:
  /// **'yesterday'**
  String get relativeTime_yesterday;

  /// No description provided for @relativeTime_daysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} days ago'**
  String relativeTime_daysAgo(int count);

  /// No description provided for @chat_emptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Fluera AI challenges you on your notes'**
  String get chat_emptyTitle;

  /// No description provided for @chat_emptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'The more you write first, the better it asks.'**
  String get chat_emptySubtitle;

  /// No description provided for @chat_inputPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'What do you want it to ask you?'**
  String get chat_inputPlaceholder;

  /// No description provided for @chat_quickFindGaps.
  ///
  /// In en, this message translates to:
  /// **'🗺 Find my fragments'**
  String get chat_quickFindGaps;

  /// No description provided for @chat_quickStartQuiz.
  ///
  /// In en, this message translates to:
  /// **'🎯 Quiz me'**
  String get chat_quickStartQuiz;

  /// No description provided for @chat_quickStartSocratic.
  ///
  /// In en, this message translates to:
  /// **'🤺 Challenge me'**
  String get chat_quickStartSocratic;

  /// No description provided for @chat_quickCompareSource.
  ///
  /// In en, this message translates to:
  /// **'🔍 Compare with source'**
  String get chat_quickCompareSource;

  /// No description provided for @chat_refusalSoft.
  ///
  /// In en, this message translates to:
  /// **'I won\'t summarize your notes — you\'ll remember them better if I quiz you. Shall we?'**
  String get chat_refusalSoft;

  /// No description provided for @chat_costBadge.
  ///
  /// In en, this message translates to:
  /// **'Read in {seconds}s · 7-day recall ~{retention}%'**
  String chat_costBadge(int seconds, int retention);

  /// No description provided for @atlasMenu_commandsTitle.
  ///
  /// In en, this message translates to:
  /// **'Atlas commands'**
  String get atlasMenu_commandsTitle;

  /// No description provided for @atlasMenu_commandsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Free-form prompt or actions on selected nodes'**
  String get atlasMenu_commandsSubtitle;

  /// No description provided for @atlasMenu_chatTitle.
  ///
  /// In en, this message translates to:
  /// **'Ask Fluera AI'**
  String get atlasMenu_chatTitle;

  /// No description provided for @atlasMenu_chatSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Talk about your notes'**
  String get atlasMenu_chatSubtitle;

  /// No description provided for @atlasPrompt_title.
  ///
  /// In en, this message translates to:
  /// **'Commands'**
  String get atlasPrompt_title;

  /// No description provided for @atlasPrompt_hintNoSelection.
  ///
  /// In en, this message translates to:
  /// **'What do you want to do on the canvas?'**
  String get atlasPrompt_hintNoSelection;

  /// No description provided for @atlasPrompt_hintWithSelection.
  ///
  /// In en, this message translates to:
  /// **'What do you want to do with these nodes?'**
  String get atlasPrompt_hintWithSelection;

  /// No description provided for @atlasPrompt_helpTooltip.
  ///
  /// In en, this message translates to:
  /// **'What does this tool do?'**
  String get atlasPrompt_helpTooltip;

  /// No description provided for @atlasPrompt_helpTitle.
  ///
  /// In en, this message translates to:
  /// **'Atlas commands'**
  String get atlasPrompt_helpTitle;

  /// No description provided for @atlasPrompt_helpIntro.
  ///
  /// In en, this message translates to:
  /// **'Atlas reshapes the canvas — it does not produce content to read. To ask questions or get quizzed, use \"Ask Fluera AI\".'**
  String get atlasPrompt_helpIntro;

  /// No description provided for @atlasPrompt_helpDefaults.
  ///
  /// In en, this message translates to:
  /// **'Without a selection, the quick commands (🗺️ Organize, 📐 Layout, 🔗 Connect, 🎨 Color) work on concept CLUSTERS, not on individual strokes — handwriting stays intact.'**
  String get atlasPrompt_helpDefaults;

  /// No description provided for @atlasPrompt_helpHow.
  ///
  /// In en, this message translates to:
  /// **'With a lasso selection, type-specific commands appear:'**
  String get atlasPrompt_helpHow;

  /// No description provided for @atlasPrompt_help_text.
  ///
  /// In en, this message translates to:
  /// **'📝 Text — Translate.'**
  String get atlasPrompt_help_text;

  /// No description provided for @atlasPrompt_help_latex.
  ///
  /// In en, this message translates to:
  /// **'🧮 Formulas — Solve, Graph.'**
  String get atlasPrompt_help_latex;

  /// No description provided for @atlasPrompt_help_image.
  ///
  /// In en, this message translates to:
  /// **'🖼️ Images — Describe.'**
  String get atlasPrompt_help_image;

  /// No description provided for @atlasPrompt_help_pdf.
  ///
  /// In en, this message translates to:
  /// **'📄 PDF — Connect to notes.'**
  String get atlasPrompt_help_pdf;

  /// No description provided for @atlasPrompt_help_stroke.
  ///
  /// In en, this message translates to:
  /// **'✍️ Handwriting — Convert to text, Analyze.'**
  String get atlasPrompt_help_stroke;

  /// No description provided for @atlasPrompt_helpFooter.
  ///
  /// In en, this message translates to:
  /// **'You can also write a free-form command in the text box above (e.g. \"group the yellow nodes\").'**
  String get atlasPrompt_helpFooter;

  /// No description provided for @atlasPrompt_emptySelectionHint.
  ///
  /// In en, this message translates to:
  /// **'Select nodes with the lasso to see available commands.'**
  String get atlasPrompt_emptySelectionHint;

  /// No description provided for @selAction_selectedBadge.
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get selAction_selectedBadge;

  /// No description provided for @selAction_copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get selAction_copy;

  /// No description provided for @selAction_duplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get selAction_duplicate;

  /// No description provided for @selAction_paste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get selAction_paste;

  /// No description provided for @selAction_more.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get selAction_more;

  /// No description provided for @selAction_transform.
  ///
  /// In en, this message translates to:
  /// **'Transform'**
  String get selAction_transform;

  /// No description provided for @selAction_arrange.
  ///
  /// In en, this message translates to:
  /// **'Arrange'**
  String get selAction_arrange;

  /// No description provided for @selAction_advanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get selAction_advanced;

  /// No description provided for @selAction_rotate90.
  ///
  /// In en, this message translates to:
  /// **'Rotate 90°'**
  String get selAction_rotate90;

  /// No description provided for @selAction_bringToFront.
  ///
  /// In en, this message translates to:
  /// **'Bring to Front'**
  String get selAction_bringToFront;

  /// No description provided for @selAction_sendToBack.
  ///
  /// In en, this message translates to:
  /// **'Send to Back'**
  String get selAction_sendToBack;

  /// No description provided for @selAction_alignLeft.
  ///
  /// In en, this message translates to:
  /// **'Align Left'**
  String get selAction_alignLeft;

  /// No description provided for @selAction_alignCenter.
  ///
  /// In en, this message translates to:
  /// **'Align Center'**
  String get selAction_alignCenter;

  /// No description provided for @selAction_alignRight.
  ///
  /// In en, this message translates to:
  /// **'Align Right'**
  String get selAction_alignRight;

  /// No description provided for @selAction_alignTop.
  ///
  /// In en, this message translates to:
  /// **'Align Top'**
  String get selAction_alignTop;

  /// No description provided for @selAction_alignMiddle.
  ///
  /// In en, this message translates to:
  /// **'Align Middle'**
  String get selAction_alignMiddle;

  /// No description provided for @selAction_alignBottom.
  ///
  /// In en, this message translates to:
  /// **'Align Bottom'**
  String get selAction_alignBottom;

  /// No description provided for @selAction_distributeH.
  ///
  /// In en, this message translates to:
  /// **'Distribute H'**
  String get selAction_distributeH;

  /// No description provided for @selAction_distributeV.
  ///
  /// In en, this message translates to:
  /// **'Distribute V'**
  String get selAction_distributeV;

  /// No description provided for @selAction_selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get selAction_selectAll;

  /// No description provided for @selAction_undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get selAction_undo;

  /// No description provided for @selAction_group.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get selAction_group;

  /// No description provided for @selAction_ungroup.
  ///
  /// In en, this message translates to:
  /// **'Ungroup'**
  String get selAction_ungroup;

  /// No description provided for @selAction_lock.
  ///
  /// In en, this message translates to:
  /// **'Lock'**
  String get selAction_lock;

  /// No description provided for @selAction_unlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get selAction_unlock;

  /// No description provided for @selAction_snapOn.
  ///
  /// In en, this message translates to:
  /// **'Snap: ON'**
  String get selAction_snapOn;

  /// No description provided for @selAction_snapOff.
  ///
  /// In en, this message translates to:
  /// **'Snap: OFF'**
  String get selAction_snapOff;

  /// No description provided for @selAction_multiLayerOn.
  ///
  /// In en, this message translates to:
  /// **'Multi-Layer: ON'**
  String get selAction_multiLayerOn;

  /// No description provided for @selAction_multiLayerOff.
  ///
  /// In en, this message translates to:
  /// **'Multi-Layer: OFF'**
  String get selAction_multiLayerOff;

  /// No description provided for @selAction_inverseSelection.
  ///
  /// In en, this message translates to:
  /// **'Inverse Selection'**
  String get selAction_inverseSelection;

  /// No description provided for @selAction_pasteInPlace.
  ///
  /// In en, this message translates to:
  /// **'Paste in Place'**
  String get selAction_pasteInPlace;

  /// No description provided for @settingsL1_subscription_title.
  ///
  /// In en, this message translates to:
  /// **'Subscription and AI credits'**
  String get settingsL1_subscription_title;

  /// No description provided for @settingsL1_subscription_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Plan, remaining credits, Spark Pack'**
  String get settingsL1_subscription_subtitle;

  /// No description provided for @settingsL1_canvas_title.
  ///
  /// In en, this message translates to:
  /// **'Canvas and pen'**
  String get settingsL1_canvas_title;

  /// No description provided for @settingsL1_canvas_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Hand, grip, palm rejection, pressure test'**
  String get settingsL1_canvas_subtitle;

  /// No description provided for @settingsL1_appearance_title.
  ///
  /// In en, this message translates to:
  /// **'Appearance and accessibility'**
  String get settingsL1_appearance_title;

  /// No description provided for @settingsL1_appearance_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Theme, reduce haptics, large text'**
  String get settingsL1_appearance_subtitle;

  /// No description provided for @settingsL1_cognitive_title.
  ///
  /// In en, this message translates to:
  /// **'Cognitive features'**
  String get settingsL1_cognitive_title;

  /// No description provided for @settingsL1_cognitive_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Exam, dictionary, spellcheck, advanced AI'**
  String get settingsL1_cognitive_subtitle;

  /// No description provided for @settingsL1_documents_title.
  ///
  /// In en, this message translates to:
  /// **'Documents and gallery'**
  String get settingsL1_documents_title;

  /// No description provided for @settingsL1_documents_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Default paper, export, view, sort'**
  String get settingsL1_documents_subtitle;

  /// No description provided for @settingsL1_data_title.
  ///
  /// In en, this message translates to:
  /// **'Data and sync'**
  String get settingsL1_data_title;

  /// No description provided for @settingsL1_data_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Cloud sync, backup, cache, reset'**
  String get settingsL1_data_subtitle;

  /// No description provided for @settingsL1_privacy_title.
  ///
  /// In en, this message translates to:
  /// **'Privacy and telemetry'**
  String get settingsL1_privacy_title;

  /// No description provided for @settingsL1_privacy_subtitle.
  ///
  /// In en, this message translates to:
  /// **'GDPR consents, analytics, AI, crash reports'**
  String get settingsL1_privacy_subtitle;

  /// No description provided for @settingsL1_about_title.
  ///
  /// In en, this message translates to:
  /// **'Info and support'**
  String get settingsL1_about_title;

  /// No description provided for @settingsL1_about_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Method, licenses, feedback, advanced studio'**
  String get settingsL1_about_subtitle;

  /// No description provided for @settingsScreen_account_title.
  ///
  /// In en, this message translates to:
  /// **'Profile and account'**
  String get settingsScreen_account_title;

  /// No description provided for @settingsScreen_subscription_title.
  ///
  /// In en, this message translates to:
  /// **'Subscription and AI credits'**
  String get settingsScreen_subscription_title;

  /// No description provided for @settingsScreen_appearance_title.
  ///
  /// In en, this message translates to:
  /// **'Appearance and accessibility'**
  String get settingsScreen_appearance_title;

  /// No description provided for @settingsScreen_canvas_title.
  ///
  /// In en, this message translates to:
  /// **'Canvas and pen'**
  String get settingsScreen_canvas_title;

  /// No description provided for @settingsScreen_documents_title.
  ///
  /// In en, this message translates to:
  /// **'Documents and gallery'**
  String get settingsScreen_documents_title;

  /// No description provided for @settingsScreen_cognitive_title.
  ///
  /// In en, this message translates to:
  /// **'Cognitive features'**
  String get settingsScreen_cognitive_title;

  /// No description provided for @settingsScreen_data_title.
  ///
  /// In en, this message translates to:
  /// **'Data and sync'**
  String get settingsScreen_data_title;

  /// No description provided for @settingsScreen_privacy_title.
  ///
  /// In en, this message translates to:
  /// **'Privacy and telemetry'**
  String get settingsScreen_privacy_title;

  /// No description provided for @settingsScreen_about_title.
  ///
  /// In en, this message translates to:
  /// **'Info and support'**
  String get settingsScreen_about_title;

  /// No description provided for @settingsCognitive_examHeader.
  ///
  /// In en, this message translates to:
  /// **'Exam (Interrogami)'**
  String get settingsCognitive_examHeader;

  /// No description provided for @settingsCognitive_accessibilityHeader.
  ///
  /// In en, this message translates to:
  /// **'Exam accessibility'**
  String get settingsCognitive_accessibilityHeader;

  /// No description provided for @settingsCognitive_returnLandmarkHeader.
  ///
  /// In en, this message translates to:
  /// **'Return & landmark'**
  String get settingsCognitive_returnLandmarkHeader;

  /// No description provided for @settingsCognitive_dictHeader.
  ///
  /// In en, this message translates to:
  /// **'Dictionary & spellcheck'**
  String get settingsCognitive_dictHeader;

  /// No description provided for @settingsCognitive_questionCount_title.
  ///
  /// In en, this message translates to:
  /// **'Question count'**
  String get settingsCognitive_questionCount_title;

  /// No description provided for @settingsCognitive_difficulty_title.
  ///
  /// In en, this message translates to:
  /// **'Default difficulty'**
  String get settingsCognitive_difficulty_title;

  /// No description provided for @settingsCognitive_hypercorrection_title.
  ///
  /// In en, this message translates to:
  /// **'Hypercorrection effect'**
  String get settingsCognitive_hypercorrection_title;

  /// No description provided for @settingsCognitive_reduceMotion_title.
  ///
  /// In en, this message translates to:
  /// **'Reduce motion (exam)'**
  String get settingsCognitive_reduceMotion_title;

  /// No description provided for @settingsCognitive_colorBlind_title.
  ///
  /// In en, this message translates to:
  /// **'Colorblind-safe palette'**
  String get settingsCognitive_colorBlind_title;

  /// No description provided for @settingsCognitive_sound_title.
  ///
  /// In en, this message translates to:
  /// **'Sound feedback'**
  String get settingsCognitive_sound_title;

  /// No description provided for @settingsCognitive_reminders_title.
  ///
  /// In en, this message translates to:
  /// **'Study reminders (FSRS)'**
  String get settingsCognitive_reminders_title;

  /// No description provided for @settingsCognitive_returnRitual_title.
  ///
  /// In en, this message translates to:
  /// **'Return with blur'**
  String get settingsCognitive_returnRitual_title;

  /// No description provided for @settingsCognitive_monumentNudge_title.
  ///
  /// In en, this message translates to:
  /// **'Landmark nudge'**
  String get settingsCognitive_monumentNudge_title;

  /// No description provided for @settingsCognitive_advancedShow.
  ///
  /// In en, this message translates to:
  /// **'Show advanced assistance'**
  String get settingsCognitive_advancedShow;

  /// No description provided for @settingsCognitive_advancedHide.
  ///
  /// In en, this message translates to:
  /// **'Hide advanced assistance'**
  String get settingsCognitive_advancedHide;

  /// No description provided for @settingsAccount_changeEmail_title.
  ///
  /// In en, this message translates to:
  /// **'Change email'**
  String get settingsAccount_changeEmail_title;

  /// No description provided for @settingsAccount_changeEmail_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Update the address linked to the account'**
  String get settingsAccount_changeEmail_subtitle;

  /// No description provided for @settingsAccount_changePassword_title.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get settingsAccount_changePassword_title;

  /// No description provided for @settingsAccount_changePassword_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Set a new password'**
  String get settingsAccount_changePassword_subtitle;

  /// No description provided for @settingsAccount_logout_title.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get settingsAccount_logout_title;

  /// No description provided for @settingsAccount_logout_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Your canvases stay saved locally'**
  String get settingsAccount_logout_subtitle;

  /// No description provided for @settingsAccount_deleteRequest_title.
  ///
  /// In en, this message translates to:
  /// **'Request account deletion'**
  String get settingsAccount_deleteRequest_title;

  /// No description provided for @settingsAccount_deleteRequest_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Write us at feedback@fluera.dev'**
  String get settingsAccount_deleteRequest_subtitle;

  /// No description provided for @settingsAccount_sessionHeader.
  ///
  /// In en, this message translates to:
  /// **'Session'**
  String get settingsAccount_sessionHeader;

  /// No description provided for @settingsAccount_accountHeader.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsAccount_accountHeader;

  /// No description provided for @settingsAbout_license_title.
  ///
  /// In en, this message translates to:
  /// **'Licenses'**
  String get settingsAbout_license_title;

  /// No description provided for @settingsAbout_license_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Open source licenses'**
  String get settingsAbout_license_subtitle;

  /// No description provided for @settingsAbout_feedback_title.
  ///
  /// In en, this message translates to:
  /// **'Send Feedback'**
  String get settingsAbout_feedback_title;

  /// No description provided for @settingsAbout_feedback_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Report bugs or suggest features'**
  String get settingsAbout_feedback_subtitle;

  /// No description provided for @settingsAbout_rate_title.
  ///
  /// In en, this message translates to:
  /// **'Rate Fluera'**
  String get settingsAbout_rate_title;

  /// No description provided for @settingsAbout_rate_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Love the app? Leave a review!'**
  String get settingsAbout_rate_subtitle;

  /// No description provided for @settingsSubscription_currentPlan.
  ///
  /// In en, this message translates to:
  /// **'Current plan'**
  String get settingsSubscription_currentPlan;

  /// No description provided for @settingsSubscription_comparePlans.
  ///
  /// In en, this message translates to:
  /// **'Compare plans'**
  String get settingsSubscription_comparePlans;

  /// No description provided for @settingsSubscription_creditsHeader.
  ///
  /// In en, this message translates to:
  /// **'AI Credits'**
  String get settingsSubscription_creditsHeader;

  /// No description provided for @settingsSubscription_buyCredits_title.
  ///
  /// In en, this message translates to:
  /// **'Buy extra credits'**
  String get settingsSubscription_buyCredits_title;

  /// No description provided for @settingsSubscription_buyCredits_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Spark Pack — one-time packs'**
  String get settingsSubscription_buyCredits_subtitle;

  /// No description provided for @settingsSubscription_managePlan_title.
  ///
  /// In en, this message translates to:
  /// **'Manage subscription'**
  String get settingsSubscription_managePlan_title;

  /// No description provided for @settingsSubscription_managePlan_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Change plan, billing, auto-renewal'**
  String get settingsSubscription_managePlan_subtitle;

  /// No description provided for @settingsData_cloudSyncHeader.
  ///
  /// In en, this message translates to:
  /// **'Cloud sync'**
  String get settingsData_cloudSyncHeader;

  /// No description provided for @settingsData_backupHeader.
  ///
  /// In en, this message translates to:
  /// **'Backup & restore'**
  String get settingsData_backupHeader;

  /// No description provided for @settingsData_cacheHeader.
  ///
  /// In en, this message translates to:
  /// **'Cache & storage'**
  String get settingsData_cacheHeader;

  /// No description provided for @settingsDocuments_documentsHeader.
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get settingsDocuments_documentsHeader;

  /// No description provided for @settingsDocuments_galleryHeader.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get settingsDocuments_galleryHeader;

  /// No description provided for @canvasSettings_actionsSection.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get canvasSettings_actionsSection;

  /// No description provided for @canvasSettings_appearanceSection.
  ///
  /// In en, this message translates to:
  /// **'Canvas appearance'**
  String get canvasSettings_appearanceSection;

  /// No description provided for @canvasSettings_analysisSection.
  ///
  /// In en, this message translates to:
  /// **'Analysis'**
  String get canvasSettings_analysisSection;

  /// No description provided for @canvasSettings_languagesSection.
  ///
  /// In en, this message translates to:
  /// **'Languages'**
  String get canvasSettings_languagesSection;

  /// No description provided for @canvasSettings_languages_title.
  ///
  /// In en, this message translates to:
  /// **'Languages'**
  String get canvasSettings_languages_title;

  /// No description provided for @canvasSettings_languages_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Writing, app, AI'**
  String get canvasSettings_languages_subtitle;

  /// No description provided for @canvasSettings_languages_dialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Languages'**
  String get canvasSettings_languages_dialogTitle;

  /// No description provided for @canvasSettings_languages_tabHandwriting.
  ///
  /// In en, this message translates to:
  /// **'Writing'**
  String get canvasSettings_languages_tabHandwriting;

  /// No description provided for @canvasSettings_languages_tabApp.
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get canvasSettings_languages_tabApp;

  /// No description provided for @canvasSettings_languages_tabAi.
  ///
  /// In en, this message translates to:
  /// **'AI'**
  String get canvasSettings_languages_tabAi;

  /// No description provided for @canvasSettings_readingLevel_title.
  ///
  /// In en, this message translates to:
  /// **'Reading Level'**
  String get canvasSettings_readingLevel_title;

  /// No description provided for @canvasSettings_handwritingLanguages_title.
  ///
  /// In en, this message translates to:
  /// **'Handwriting languages'**
  String get canvasSettings_handwritingLanguages_title;

  /// No description provided for @canvasSettings_appLanguage_title.
  ///
  /// In en, this message translates to:
  /// **'App language'**
  String get canvasSettings_appLanguage_title;

  /// No description provided for @canvasSettings_aiOutputLanguage_title.
  ///
  /// In en, this message translates to:
  /// **'AI output language'**
  String get canvasSettings_aiOutputLanguage_title;

  /// No description provided for @canvasSettings_languages_resetAutoButton.
  ///
  /// In en, this message translates to:
  /// **'Auto-detect all'**
  String get canvasSettings_languages_resetAutoButton;

  /// No description provided for @canvasSettings_languages_resetAutoSnack.
  ///
  /// In en, this message translates to:
  /// **'All languages reset to Auto'**
  String get canvasSettings_languages_resetAutoSnack;

  /// No description provided for @canvasSettings_filtersActiveCount.
  ///
  /// In en, this message translates to:
  /// **'{count} active'**
  String canvasSettings_filtersActiveCount(int count);
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
  bool isSupported(Locale locale) => <String>[
    'ar',
    'da',
    'de',
    'en',
    'es',
    'fi',
    'fr',
    'hi',
    'it',
    'ja',
    'ko',
    'nl',
    'no',
    'pl',
    'pt',
    'sv',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_FlueraLocalizationsDelegate old) => false;
}

FlueraLocalizations lookupFlueraLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return FlueraLocalizationsAr();
    case 'da':
      return FlueraLocalizationsDa();
    case 'de':
      return FlueraLocalizationsDe();
    case 'en':
      return FlueraLocalizationsEn();
    case 'es':
      return FlueraLocalizationsEs();
    case 'fi':
      return FlueraLocalizationsFi();
    case 'fr':
      return FlueraLocalizationsFr();
    case 'hi':
      return FlueraLocalizationsHi();
    case 'it':
      return FlueraLocalizationsIt();
    case 'ja':
      return FlueraLocalizationsJa();
    case 'ko':
      return FlueraLocalizationsKo();
    case 'nl':
      return FlueraLocalizationsNl();
    case 'no':
      return FlueraLocalizationsNo();
    case 'pl':
      return FlueraLocalizationsPl();
    case 'pt':
      return FlueraLocalizationsPt();
    case 'sv':
      return FlueraLocalizationsSv();
  }

  throw FlutterError(
    'FlueraLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
