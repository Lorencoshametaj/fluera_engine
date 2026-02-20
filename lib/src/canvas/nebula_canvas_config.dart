import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../collaboration/nebula_sync_interfaces.dart';
import '../core/models/canvas_layer.dart';
import '../core/models/digital_text_element.dart';
import '../core/models/pdf_text_rect.dart';
import '../core/models/ocr_result.dart';
import '../export/export_preset.dart';
import '../core/models/image_element.dart';
import '../config/multi_page_config.dart';
import '../storage/nebula_storage_adapter.dart';
import '../drawing/models/pro_drawing_point.dart';
import '../layers/nebula_layer_controller.dart';

// =============================================================================
// NEBULA CANVAS CONFIGURATION
// =============================================================================

/// Configuretion object for the Nebula Canvas Screen.
///
/// This replaces all app-coupled imports with injectable callbacks and providers.
/// The app passes a concrete [NebulaCanvasConfig] to the screen widget.
///
/// **Required:**
/// - [layerController] — manages layers
///
/// **Optional:** All other fields default to no-ops or stubs.
///
/// Example:
/// ```dart
/// NebulaCanvasScreen(
///   config: NebulaCanvasConfig(
///     layerController: myLayerController,
///     auth: MyAuthProvider(),
///     storage: MyStorageProvider(),
///   ),
/// )
/// ```
class NebulaCanvasConfig {
  /// Layer management controller (required)
  final NebulaLayerController layerController;

  // ===========================================================================
  // AUTH & USER
  // ===========================================================================

  /// Get current user ID (for per-user storage paths)
  final Future<String?> Function() getUserId;

  // ===========================================================================
  // SUBSCRIPTION TIER
  // ===========================================================================

  /// Current subscription tier (affects feature gating)
  final NebulaSubscriptionTier subscriptionTier;

  // ===========================================================================
  // STORAGE ADAPTER (RECOMMENDED)
  // ===========================================================================

  /// Storage adapter for canvas persistence.
  ///
  /// When provided, the SDK uses this adapter for all save/load operations.
  /// Use [SqliteStorageAdapter] for zero-config local persistence, or
  /// implement [NebulaStorageAdapter] for custom backends.
  ///
  /// Takes priority over the legacy [onSaveCanvas]/[onLoadCanvas] callbacks.
  final NebulaStorageAdapter? storageAdapter;

  // ===========================================================================
  // LOCAL STORAGE (LEGACY CALLBACKS)
  // ===========================================================================

  /// Save canvas data locally (legacy — prefer [storageAdapter]).
  final Future<void> Function(NebulaCanvasSaveData data)? onSaveCanvas;

  /// Load canvas data from local storage (legacy — prefer [storageAdapter]).
  final Future<Map<String, dynamic>?> Function(String canvasId)? onLoadCanvas;

  /// Delete canvas from local storage (legacy — prefer [storageAdapter]).
  final Future<void> Function(String canvasId)? onDeleteCanvas;

  /// Flush any pending saves immediately.
  final Future<void> Function()? onFlushPendingSave;

  // ===========================================================================
  // CLOUD SYNC
  // ===========================================================================

  /// Whether cloud sync is enabled
  final bool cloudSyncEnabled;

  /// Trigger cloud sync for a canvas
  final Future<void> Function(String canvasId, Map<String, dynamic> data)?
  onCloudSync;

  /// Trigger delta sync
  final Future<void> Function(
    String canvasId,
    List<Map<String, dynamic>> deltas,
  )?
  onDeltaSync;

  /// Real-time delta sync provider (for collaboration)
  final NebulaRealtimeDeltaSync? realtimeSync;

  // ===========================================================================
  // VOICE RECORDING
  // ===========================================================================

  /// Voice recording provider (optional feature)
  final NebulaVoiceRecordingProvider? voiceRecording;

  // ===========================================================================
  // IMAGE STORAGE
  // ===========================================================================

  /// Store canvas images to cloud/disk
  final Future<String?> Function(String canvasId, String localPath)?
  onStoreImage;

  /// Load image from cloud/disk
  final Future<String?> Function(String canvasId, String imageId)? onLoadImage;

  // ===========================================================================
  // OCR
  // ===========================================================================

  /// Run OCR on strokes
  final Future<String?> Function(List<ProStroke> strokes)? onRunOCR;

  // ===========================================================================
  // SPLIT VIEW
  // ===========================================================================

  /// Open split view
  final void Function(BuildContext context, {String? canvasId})?
  onOpenSplitView;

  // ===========================================================================
  // TIME TRAVEL (HISTORY RECORDING)
  // ===========================================================================

  /// Time travel storage provider (optional)
  final NebulaTimeTravelProvider? timeTravel;

  // ===========================================================================
  // COLLABORATION & SHARING
  // ===========================================================================

  /// Permission provider for shared canvases
  final NebulaPermissionProvider? permissions;

  /// Canvas presence (who's viewing this canvas)
  final NebulaPresenceProvider? presence;

  /// Show canvas share dialog
  final void Function(BuildContext context, String canvasId)? onShareCanvas;

  // ===========================================================================
  // EXPORT
  // ===========================================================================

  /// Show export format dialog
  final Future<void> Function(BuildContext context, NebulaExportData data)?
  onShowExportDialog;

  // ===========================================================================
  // MULTIVIEW
  // ===========================================================================

  /// Open canvas in multiview/popup
  final void Function(BuildContext context, String canvasId)? onOpenMultiview;

  // ===========================================================================
  // SETTINGS
  // ===========================================================================

  /// Show canvas settings dialog
  final void Function(BuildContext context)? onShowSettings;

  // ===========================================================================
  // SYNC COORDINATOR
  // ===========================================================================

  /// Pause/resume background sync (to avoid ANR during heavy canvas work)
  final void Function(bool pause)? onPauseSyncCoordinator;

  /// Pause/resume app-level listeners (e.g. Firestore listeners that are not
  /// needed while the canvas is active). Called with `true` on enter, `false` on exit.
  final void Function(bool pause)? onPauseAppListeners;

  // ===========================================================================
  // SPLASH / LOADING CUSTOMIZATION
  // ===========================================================================

  /// Custom logo asset path for the loading screen.
  /// If null, the default Fluera logo from the SDK is used.
  final String? splashLogoAsset;

  // ===========================================================================
  // PDF VIEWER
  // ===========================================================================

  /// PDF rendering provider (optional feature).
  ///
  /// When provided, enables native PDF document viewing on the canvas.
  /// The host app implements this with platform-specific PDF libraries
  /// (e.g. PDFKit on iOS, PdfRenderer on Android, pdf.js on web).
  final NebulaPdfProvider? pdfProvider;

  /// Callback for picking a PDF file (dependency inversion).
  ///
  /// The host app implements file picking (e.g. via `file_picker` package)
  /// and returns raw PDF bytes, or `null` if the user cancelled.
  /// Only called when [pdfProvider] is non-null.
  final Future<Uint8List?> Function()? onPickPdfFile;

  const NebulaCanvasConfig({
    required this.layerController,
    this.getUserId = _defaultGetUserId,
    this.subscriptionTier = NebulaSubscriptionTier.free,
    this.storageAdapter,
    this.onSaveCanvas,
    this.onLoadCanvas,
    this.onDeleteCanvas,
    this.onFlushPendingSave,
    this.cloudSyncEnabled = false,
    this.onCloudSync,
    this.onDeltaSync,
    this.realtimeSync,
    this.voiceRecording,
    this.onStoreImage,
    this.onLoadImage,
    this.onRunOCR,
    this.onOpenSplitView,
    this.timeTravel,
    this.permissions,
    this.presence,
    this.onShareCanvas,
    this.onShowExportDialog,
    this.onOpenMultiview,
    this.onShowSettings,
    this.onPauseSyncCoordinator,
    this.onPauseAppListeners,
    this.splashLogoAsset,
    this.pdfProvider,
    this.onPickPdfFile,
  });

  static Future<String?> _defaultGetUserId() async => 'local_user';

  // =========================================================================
  // VALIDATION
  // =========================================================================

  /// Validate this configuration for logical consistency.
  ///
  /// Returns a list of warnings/errors. An empty list means the config
  /// is valid. Call this at startup to fail fast on misconfiguration
  /// instead of hitting a runtime crash deep in the engine.
  ///
  /// ```dart
  /// final issues = config.validate();
  /// if (issues.isNotEmpty) {
  ///   for (final issue in issues) debugPrint('⚠️ Config: $issue');
  /// }
  /// ```
  List<String> validate() {
    final issues = <String>[];

    // Cloud sync needs at least one sync callback
    if (cloudSyncEnabled &&
        onCloudSync == null &&
        onDeltaSync == null &&
        realtimeSync == null) {
      issues.add(
        'cloudSyncEnabled is true but no sync callback is provided '
        '(onCloudSync, onDeltaSync, or realtimeSync).',
      );
    }

    // Storage: need either storageAdapter or legacy callbacks
    if (storageAdapter == null &&
        onSaveCanvas == null &&
        onLoadCanvas == null) {
      issues.add(
        'No persistence configured. Provide a storageAdapter or '
        'onSaveCanvas/onLoadCanvas callbacks to enable saving.',
      );
    }

    // PDF provider without picker
    if (pdfProvider != null && onPickPdfFile == null) {
      issues.add(
        'pdfProvider is set but onPickPdfFile is null. '
        'Users will not be able to import PDF files.',
      );
    }

    // Collaboration features without permissions
    if (presence != null && permissions == null) {
      issues.add(
        'presence is set but permissions is null. '
        'Collaborative sessions need a NebulaPermissionProvider.',
      );
    }

    // Realtime sync without storage
    if (realtimeSync != null &&
        storageAdapter == null &&
        onSaveCanvas == null) {
      issues.add(
        'realtimeSync is set but no storage is configured. '
        'Incoming deltas cannot be persisted.',
      );
    }

    return issues;
  }
}

// =============================================================================
// SUBSCRIPTION TIER ENUM
// =============================================================================

/// Subscription tier enum (SDK-level, decoupled from app's SubscriptionTier)
enum NebulaSubscriptionTier {
  free,
  essential,
  plus,
  pro;

  bool get canUseCloudSync => this == plus || this == pro;
  bool get canUseAIFilters => this == pro;
  bool get canCollaborate => this == plus || this == pro;
}

// =============================================================================
// SAVE DATA
// =============================================================================

/// Data structure for saving canvas state
class NebulaCanvasSaveData {
  final String canvasId;
  final List<CanvasLayer> layers;
  final List<DigitalTextElement> textElements;
  final List<ImageElement> imageElements;
  final String backgroundColor;
  final String paperType;
  final String? activeLayerId;
  final String? title;
  final String? infiniteCanvasId;
  final String? nodeId;
  final DateTime? createdAt;
  final Map<String, dynamic>? guides;

  /// 🎛️ Design variable state (JSON-serialized for persistence).
  final List<Map<String, dynamic>>? variableCollectionsJson;
  final Map<String, dynamic>? variableBindingsJson;
  final Map<String, dynamic>? variableActiveModesJson;

  const NebulaCanvasSaveData({
    required this.canvasId,
    required this.layers,
    required this.textElements,
    required this.imageElements,
    required this.backgroundColor,
    required this.paperType,
    this.activeLayerId,
    this.title,
    this.infiniteCanvasId,
    this.nodeId,
    this.createdAt,
    this.guides,
    this.variableCollectionsJson,
    this.variableBindingsJson,
    this.variableActiveModesJson,
  });

  /// Serialize to a generic JSON map for cloud storage providers.
  Map<String, dynamic> toJson() => {
    'canvasId': canvasId,
    'backgroundColor': backgroundColor,
    'paperType': paperType,
    if (activeLayerId != null) 'activeLayerId': activeLayerId,
    if (title != null) 'title': title,
    if (infiniteCanvasId != null) 'infiniteCanvasId': infiniteCanvasId,
    if (nodeId != null) 'nodeId': nodeId,
    if (guides != null) 'guides': guides,
    if (variableCollectionsJson != null && variableCollectionsJson!.isNotEmpty)
      'variableCollections': variableCollectionsJson,
    if (variableBindingsJson != null) 'variableBindings': variableBindingsJson,
    if (variableActiveModesJson != null)
      'variableActiveModes': variableActiveModesJson,
    'updatedAt': DateTime.now().millisecondsSinceEpoch,
  };
}

/// Data for export operations
class NebulaExportData {
  final String canvasId;
  final List<CanvasLayer> layers;
  final Color backgroundColor;
  final Rect exportArea;
  final MultiPageConfig? multiPageConfig;
  final ExportConfig exportConfig;
  final String paperType;

  const NebulaExportData({
    required this.canvasId,
    required this.layers,
    required this.backgroundColor,
    required this.exportArea,
    required this.exportConfig,
    required this.paperType,
    this.multiPageConfig,
  });
}

// =============================================================================
// PROVIDER INTERFACES
// =============================================================================

/// Abstract voice recording provider
abstract class NebulaVoiceRecordingProvider {
  Future<void> startRecording();
  Future<String?> stopRecording();
  bool get isRecording;
  Stream<Duration> get recordingDuration;
  Future<void> playRecording(String path);
  Future<void> stopPlayback();

  /// Stream that emits when audio playback completes naturally.
  /// Default implementation returns an empty stream (never completes).
  Stream<void> get playbackCompleted => const Stream.empty();
}

/// Abstract real-time sync provider
abstract class NebulaRealtimeSyncProvider {
  void connect(String canvasId);
  void disconnect();
  Stream<Map<String, dynamic>> get incomingDeltas;
  void sendDelta(Map<String, dynamic> delta);
  bool get isConnected;
}

/// Abstract time travel provider
abstract class NebulaTimeTravelProvider {
  Future<void> saveSnapshot(String canvasId, Map<String, dynamic> data);
  Future<List<Map<String, dynamic>>> loadSnapshots(String canvasId);
  Future<void> deleteSnapshots(String canvasId);
}

/// Abstract permission provider
abstract class NebulaPermissionProvider {
  Future<bool> canEdit(String canvasId);
  Future<bool> canView(String canvasId);
  String get currentUserRole;
}

/// Abstract presence provider
abstract class NebulaPresenceProvider {
  ValueNotifier<List<NebulaPresenceUser>> get activeUsers;
  void joinCanvas(String canvasId);
  void leaveCanvas();
}

/// User presence data
class NebulaPresenceUser {
  final String id;
  final String name;
  final Color cursorColor;
  final Offset? cursorPosition;

  const NebulaPresenceUser({
    required this.id,
    required this.name,
    required this.cursorColor,
    this.cursorPosition,
  });
}

/// Abstract PDF rendering provider.
///
/// Decouples the engine from platform-specific PDF libraries.
/// The host app (Looponia) implements this using:
/// - **iOS**: `PDFKit` via method channels
/// - **Android**: `PdfRenderer` via method channels
/// - **Web**: `pdf.js` via `dart:js_interop`
///
/// The engine calls these methods to decode pages as raster tiles
/// and extract text geometry for the selection layer.
abstract class NebulaPdfProvider {
  /// Load a PDF document from raw bytes.
  ///
  /// Returns `true` if the document was loaded successfully.
  /// After calling this, [pageCount] and [pageSize] are available.
  Future<bool> loadDocument(List<int> bytes);

  /// Total page count of the loaded document.
  int get pageCount;

  /// Native size (in PDF points, 72 ppi) for each page.
  ///
  /// Returns [Size.zero] if [pageIndex] is out of range.
  Size pageSize(int pageIndex);

  /// Decode a page at the given scale into a raster image.
  ///
  /// [targetSize] is the desired pixel dimensions of the output.
  /// Returns `null` if the page is out of range or decoding fails.
  ///
  /// This is called from an async pipeline — never on the UI thread.
  Future<ui.Image?> renderPage({
    required int pageIndex,
    required double scale,
    required Size targetSize,
  });

  /// Extract text geometry rects for a page.
  ///
  /// Returns positioned [PdfTextRect]s for text selection / copy.
  /// Called lazily on the first text selection attempt for a page.
  Future<List<PdfTextRect>> extractTextGeometry(int pageIndex);

  /// Get the full plain text content of a page (for search).
  Future<String> getPageText(int pageIndex);

  /// Run OCR on a page to extract text from scanned/image-based PDFs.
  ///
  /// Returns an [OcrPageResult] with recognized text and bounding boxes,
  /// or `null` if OCR is unavailable or fails. This is only called as a
  /// fallback when both [getPageText] and the Dart-side text extractor
  /// return empty text — indicating the page is likely image-based.
  ///
  /// Default implementation returns `null` (OCR unavailable).
  Future<OcrPageResult?> ocrPage(int pageIndex) async => null;

  /// Release all resources associated with the loaded document.
  void dispose();
}
