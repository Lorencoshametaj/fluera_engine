import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../storage/fluera_cloud_adapter.dart';
import '../collaboration/fluera_realtime_adapter.dart';
import '../p2p/fluera_p2p_connector.dart';
import '../core/models/canvas_layer.dart';
import '../core/models/digital_text_element.dart';
import '../core/models/pdf_text_rect.dart';
import '../core/models/ocr_result.dart';
import '../rendering/canvas/pdf_texture_tile.dart';
import '../export/export_preset.dart';
import '../core/models/image_element.dart';
import '../core/models/recording_pin.dart';
import '../config/multi_page_config.dart';
import '../storage/fluera_storage_adapter.dart';
import '../drawing/models/pro_drawing_point.dart';
import '../layers/fluera_layer_controller.dart';
import '../audio/native_audio_models.dart';
import 'ai/pedagogical_accessibility_config.dart';
import '../ai/ai_usage_tracker.dart';
import '../ai/telemetry_recorder.dart';

// =============================================================================
// FLUERA CANVAS CONFIGURATION
// =============================================================================

/// Configuretion object for the Fluera Canvas Screen.
///
/// This replaces all app-coupled imports with injectable callbacks and providers.
/// The app passes a concrete [FlueraCanvasConfig] to the screen widget.
///
/// **Required:**
/// - [layerController] — manages layers
///
/// **Optional:** All other fields default to no-ops or stubs.
///
/// Example:
/// ```dart
/// FlueraCanvasScreen(
///   config: FlueraCanvasConfig(
///     layerController: myLayerController,
///     auth: MyAuthProvider(),
///     storage: MyStorageProvider(),
///   ),
/// )
/// ```
class FlueraCanvasConfig {
  /// Layer management controller (required)
  final FlueraLayerController layerController;

  // ===========================================================================
  // AUTH & USER
  // ===========================================================================

  /// Get current user ID (for per-user storage paths)
  final Future<String?> Function() getUserId;

  /// Get a stable, device-local identifier for the local peer.
  ///
  /// Used as the CRDT `peerId` so that two browser tabs / two devices for the
  /// same user resolve concurrent edits independently (the HLC tie-breaker
  /// keys on this id). The value MUST survive app restart — generate a UUID
  /// once and persist it (e.g. `SharedPreferences`).
  ///
  /// When null (default), the engine falls back to [getUserId], which keeps
  /// existing single-device deployments working unchanged. Multi-device
  /// collab installs should override this.
  final Future<String?> Function()? getDeviceId;

  // ===========================================================================
  // SUBSCRIPTION TIER
  // ===========================================================================

  /// Current subscription tier (affects feature gating)
  final FlueraSubscriptionTier subscriptionTier;

  // ===========================================================================
  // STORAGE ADAPTER (RECOMMENDED)
  // ===========================================================================

  /// Storage adapter for canvas persistence.
  ///
  /// When provided, the SDK uses this adapter for all save/load operations.
  /// Use [SqliteStorageAdapter] for zero-config local persistence, or
  /// implement [FlueraStorageAdapter] for custom backends.
  ///
  /// Takes priority over the legacy [onSaveCanvas]/[onLoadCanvas] callbacks.
  final FlueraStorageAdapter? storageAdapter;

  // ===========================================================================
  // LOCAL STORAGE (LEGACY CALLBACKS)
  // ===========================================================================

  /// Save canvas data locally (legacy — prefer [storageAdapter]).
  final Future<void> Function(FlueraCanvasSaveData data)? onSaveCanvas;

  /// Load canvas data from local storage (legacy — prefer [storageAdapter]).
  final Future<Map<String, dynamic>?> Function(String canvasId)? onLoadCanvas;

  /// Delete canvas from local storage (legacy — prefer [storageAdapter]).
  final Future<void> Function(String canvasId)? onDeleteCanvas;

  /// Flush any pending saves immediately.
  final Future<void> Function()? onFlushPendingSave;

  // ===========================================================================
  // CLOUD SYNC
  // ===========================================================================

  /// Cloud storage adapter for online persistence.
  ///
  /// When provided, the SDK automatically saves canvas state to the cloud
  /// after every local save (debounced, 3s). No manual "save" button needed.
  ///
  /// Implement [FlueraCloudStorageAdapter] with your backend:
  /// ```dart
  /// class MyFirebaseAdapter implements FlueraCloudStorageAdapter {
  ///   Future<void> saveCanvas(String id, Map<String, dynamic> data) { ... }
  ///   Future<Map<String, dynamic>?> loadCanvas(String id) { ... }
  ///   Future<void> deleteCanvas(String id) { ... }
  /// }
  /// ```
  final FlueraCloudStorageAdapter? cloudAdapter;

  // ===========================================================================
  // VOICE RECORDING
  // ===========================================================================

  /// Voice recording provider (optional feature)
  final FlueraVoiceRecordingProvider? voiceRecording;

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
  final FlueraTimeTravelProvider? timeTravel;

  // ===========================================================================
  // COLLABORATION & SHARING
  // ===========================================================================

  /// Permission provider for shared canvases
  final FlueraPermissionProvider? permissions;

  /// Canvas presence (who's viewing this canvas)
  final FlueraPresenceProvider? presence;

  /// Real-time collaboration adapter (Supabase Realtime, Firebase RTDB, etc).
  ///
  /// When provided, enables live multi-user canvas editing with remote cursors,
  /// stroke broadcasting, element locking, and presence indicators.
  final FlueraRealtimeAdapter? realtimeAdapter;

  /// 🤝 P2P collaboration connector (Passo 7).
  ///
  /// When provided, enables peer-to-peer collaboration with ghost cursors,
  /// laser pointers, voice channels, and three collaboration modes
  /// (Visit, Teaching, Duel). See [FlueraP2PConnector].
  final FlueraP2PConnector? p2pConnector;

  /// Show canvas share dialog
  final void Function(BuildContext context, String canvasId)? onShareCanvas;

  // ===========================================================================
  // EXPORT
  // ===========================================================================

  /// Show export format dialog
  final Future<void> Function(BuildContext context, FlueraExportData data)?
  onShowExportDialog;

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
  // ACCESSIBILITY (A11)
  // ===========================================================================

  /// Pedagogical accessibility configuration (♯ A11).
  ///
  /// Controls colorblind palette, icon redundancy, keyboard mode for
  /// motor disabilities, and high-contrast blur. Host app stores these
  /// preferences and injects them here.
  ///
  /// All accessibility features are ALWAYS FREE (A17-05).
  final PedagogicalAccessibilityConfig accessibilityConfig;

  // ===========================================================================
  // PDF VIEWER
  // ===========================================================================

  /// PDF rendering provider (optional feature).
  ///
  /// When provided, enables native PDF document viewing on the canvas.
  /// The host app implements this with platform-specific PDF libraries
  /// (e.g. PDFKit on iOS, PdfRenderer on Android, pdf.js on web).
  final FlueraPdfProvider? pdfProvider;

  /// Callback for picking a PDF file (dependency inversion).
  ///
  /// The host app implements file picking (e.g. via `file_picker` package)
  /// and returns raw PDF bytes, or `null` if the user cancelled.
  /// Only called when [pdfProvider] is non-null.
  final Future<Uint8List?> Function()? onPickPdfFile;

  // ===========================================================================
  // UPGRADE PROMPT (A17)
  // ===========================================================================

  /// Callback invoked when a tier gate blocks a feature.
  ///
  /// The engine calls this with a user-facing [upgradeMessage] explaining
  /// what was blocked and why. The host app should show the paywall or
  /// an upgrade banner (e.g. via [showFlueraUpgradeBanner]).
  ///
  /// If null, the engine shows a basic SnackBar as a fallback.
  final void Function(BuildContext context, String upgradeMessage)?
      onUpgradePrompt;

  // ===========================================================================
  // AI USAGE TRACKING
  // ===========================================================================

  /// Optional server-backed tracker for AI token consumption.
  ///
  /// When provided, every outbound Gemini call is metered: pre-flight balance
  /// check (may throw [AiQuotaExceededException]) and post-call reconciliation
  /// with the actual `usageMetadata.totalTokenCount`.
  ///
  /// Leave null in tests / the web demo / the landing page. The engine falls
  /// back to a no-op implementation that never enforces limits.
  final AiUsageTracker? aiUsageTracker;

  // ===========================================================================
  // PRODUCT TELEMETRY
  // ===========================================================================

  /// Optional sink for product telemetry events (12-step cycle progression,
  /// AI call cost, tier limits hit, session lifecycle).
  ///
  /// The engine emits events unconditionally via this recorder; the host
  /// implementation is expected to enforce GDPR consent before transmitting.
  ///
  /// Leave null in tests / demos / landing page. The engine falls back to
  /// [TelemetryRecorder.noop].
  final TelemetryRecorder? telemetry;

  // ===========================================================================
  // AI CONSENT (GDPR Art. 6 — explicit consent before LLM call)
  // ===========================================================================

  /// Synchronous check: does the user already grant consent to send their
  /// notes to a third-party LLM (Gemini)?
  ///
  /// The engine calls this BEFORE any prompt-injection of student content
  /// (Exam Session question generation, Atlas chat, Socratic mode).
  ///
  /// Return `true` if consent is on file, `false` if it should be requested.
  /// The host typically wires this to a [GdprConsentManager.isGranted]
  /// check on `ConsentCategory.aiProcessing`.
  ///
  /// Leave null in tests / demos / when no consent system is wired — the
  /// engine assumes consent is implicit (legacy behaviour).
  final bool Function()? hasAiProcessingConsent;
  /// Async prompt: ask the user to grant consent for AI processing.
  ///
  /// Called by the engine when [hasAiProcessingConsent] returns `false`.
  /// The host shows a dialog explaining what will be sent (and what not),
  /// then resolves to `true` if the user accepted.
  ///
  /// Returning `false` (or null) cancels the AI-driven action gracefully.
  /// Leave null in tests — the engine then falls back to a built-in
  /// disclosure dialog inside the calling overlay.
  final Future<bool> Function(BuildContext context)? requestAiProcessingConsent;

  // ===========================================================================
  // CHAT — Cost transparency
  // ===========================================================================

  /// 🧠 Show the read-cost badge under "Chiedi a Fluera AI" responses.
  ///
  /// When `true` (default), each non-streaming Atlas message displays a small
  /// passive badge — once the message has been visible for a few seconds —
  /// with the read duration and an estimated 7-day retention from passive
  /// reading. Tapping the badge offers to route the topic into a Ghost Map
  /// gap analysis.
  ///
  /// This is the UX expression of teoria_cognitiva_apprendimento.md §4
  /// (Hypercorrection) and §11 (Illusion of Fluency). The estimate is a
  /// conservative heuristic, not a clinical predictor.
  ///
  /// Host apps can wire this to a user preference (e.g. via
  /// `shared_preferences`); the engine defaults to on.
  final bool showChatReadCostBadge;

  // ===========================================================================
  // EXAM PREFERENCES (persistent UI defaults)
  // ===========================================================================

  /// Optional bridge to the host app's persistent exam preferences (question
  /// count, input mode, hypercorrection toggle, reduce motion). Leave null
  /// in tests / demos — the engine falls back to legacy hardcoded defaults
  /// (7 questions, handwriting mode on, hypercorrection on, reduce motion off).
  ///
  /// The host typically wires this to its own `ExamPreferences` singleton.
  final ExamPreferencesBridge? examPreferences;

  /// Optional handler that opens the host app's exam analytics dashboard
  /// (cross-session weakness analysis, score trends, Bloom distribution).
  /// When non-null, the engine surfaces a "Dashboard" entry in the Atlas
  /// menu. Leave null on platforms without a dashboard implementation.
  final VoidCallback? onShowExamDashboard;

  /// Optional cloud sync sink for the per-question strokes JSON. Called
  /// from the engine after each local save when this hook is non-null.
  /// Hosts wire this only for tiers that include cloud sync (Plus / Pro);
  /// Free users get `null`, so the engine never even attempts an upload.
  /// Receives the `<sessionId>__<questionId>__answer|elaboration` key +
  /// the JSON string. Implementation is host-side (typically Supabase
  /// Storage with per-user RLS bucket). Failures are silent — local
  /// persistence is the source of truth.
  final Future<void> Function(String key, String json)? onUploadExamStrokes;

  const FlueraCanvasConfig({
    required this.layerController,
    this.getUserId = _defaultGetUserId,
    this.getDeviceId,
    this.subscriptionTier = FlueraSubscriptionTier.free,
    this.storageAdapter,
    this.onSaveCanvas,
    this.onLoadCanvas,
    this.onDeleteCanvas,
    this.onFlushPendingSave,
    this.cloudAdapter,
    this.voiceRecording,
    this.onStoreImage,
    this.onLoadImage,
    this.onRunOCR,
    this.onOpenSplitView,
    this.timeTravel,
    this.permissions,
    this.presence,
    this.realtimeAdapter,
    this.p2pConnector,
    this.onShareCanvas,
    this.onShowExportDialog,
    this.onShowSettings,
    this.onPauseSyncCoordinator,
    this.onPauseAppListeners,
    this.splashLogoAsset,
    this.accessibilityConfig = PedagogicalAccessibilityConfig.defaultConfig,
    this.pdfProvider,
    this.onPickPdfFile,
    this.onUpgradePrompt,
    this.aiUsageTracker,
    this.telemetry,
    this.hasAiProcessingConsent,
    this.requestAiProcessingConsent,
    this.examPreferences,
    this.onShowExamDashboard,
    this.onUploadExamStrokes,
    this.showChatReadCostBadge = true,
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
  ///   for (final issue in issues)  /// }
  /// ```
  List<String> validate() {
    final issues = <String>[];

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
        'Collaborative sessions need a FlueraPermissionProvider.',
      );
    }

    return issues;
  }
}

/// Host-side bridge to persistent exam preferences. Implemented by the
/// host app (Fluera) — the engine reads via the synchronous getters and
/// writes via the async setters. Defaults match legacy hardcoded behaviour
/// so an absent bridge is indistinguishable from V1.
abstract class ExamPreferencesBridge {
  /// Number of questions per exam (clamped to 3..15).
  int get questionCount;

  /// Whether handwriting is the default input mode for new exam sessions.
  bool get handwritingMode;

  /// Whether the hypercorrection shock UI is enabled (red flash + shake on
  /// overconfident-wrong answers). When false, the cognitive logic still
  /// runs but the visual cue is suppressed.
  bool get hypercorrectionEnabled;

  /// User-opted reduce-motion preference. ORed with the OS-level
  /// `MediaQuery.disableAnimations` at the call site.
  bool get reduceMotion;

  /// When true, the exam UI uses a deuteranopia-safe palette
  /// (blue=correct, orange=incorrect, yellow=partial) plus always-visible
  /// icons (✓ ≈ ✗) so colour is never the sole signal.
  bool get colorBlindSafePalette;

  /// Persist a new question count.
  Future<void> setQuestionCount(int value);

  /// Persist the latest handwriting/keyboard toggle.
  Future<void> setHandwritingMode(bool value);
}

// =============================================================================
// SUBSCRIPTION TIER ENUM
// =============================================================================

/// Subscription tier enum (SDK-level, decoupled from app's SubscriptionTier)
enum FlueraSubscriptionTier {
  free,
  essential,
  plus,
  pro;

  bool get canUseCloudSync => this == plus || this == pro;
  bool get canUseAIFilters => this == pro;
  // Real-time multi-user collab is Pro-tier (Team/Edu pricing layer on top of Pro).
  // Plus is single-user multi-device cloud sync only.
  bool get canCollaborate => this == pro;

  /// Whether this tier may export the given file format.
  ///
  /// Free → PNG only (raster snapshot). Plus / Pro → every supported format
  /// (JPEG, WebP, SVG, PDF, .fluera). The host's export dialog should call
  /// this before showing each format option so Free users see a clear
  /// "Plus richiesto" badge instead of hitting the paywall after picking.
  ///
  /// [format] is matched case-insensitively against the canonical short
  /// names: 'png', 'jpeg', 'webp', 'svg', 'pdf', 'fluera'.
  bool canUseExportFormat(String format) {
    final f = format.trim().toLowerCase();
    if (f == 'png') return true; // PNG is universal
    return this == plus || this == pro;
  }
}

// =============================================================================
// SAVE DATA
// =============================================================================

/// Data structure for saving canvas state
class FlueraCanvasSaveData {
  final String canvasId;
  final List<CanvasLayer> layers;
  final List<DigitalTextElement> textElements;
  final List<ImageElement> imageElements;
  final List<RecordingPin> recordingPins;
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

  const FlueraCanvasSaveData({
    required this.canvasId,
    required this.layers,
    required this.textElements,
    required this.imageElements,
    this.recordingPins = const [],
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
    // 📝 Text elements (digital text on canvas)
    if (textElements.isNotEmpty)
      'textElements': textElements.map((t) => t.toJson()).toList(),
    // 🖼️ Image elements (positioned images with transforms)
    if (imageElements.isNotEmpty)
      'imageElements': imageElements.map((i) => i.toJson()).toList(),
    // 📌 Recording pins
    if (recordingPins.isNotEmpty)
      'recordingPins': recordingPins.map((p) => p.toJson()).toList(),
    'updatedAt': DateTime.now().millisecondsSinceEpoch,
  };
}

/// Data for export operations
class FlueraExportData {
  final String canvasId;
  final List<CanvasLayer> layers;
  final Color backgroundColor;
  final Rect exportArea;
  final MultiPageConfig? multiPageConfig;
  final ExportConfig exportConfig;
  final String paperType;

  const FlueraExportData({
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
abstract class FlueraVoiceRecordingProvider {
  Future<void> startRecording({AudioRecordConfig? config});
  Future<String?> stopRecording();
  bool get isRecording;
  Stream<Duration> get recordingDuration;
  Future<void> playRecording(String path);
  Future<void> stopPlayback();

  /// Stream that emits when audio playback completes naturally.
  /// Default implementation returns an empty stream (never completes).
  Stream<void> get playbackCompleted => const Stream.empty();
}

/// Abstract time travel provider
abstract class FlueraTimeTravelProvider {
  Future<void> saveSnapshot(String canvasId, Map<String, dynamic> data);
  Future<List<Map<String, dynamic>>> loadSnapshots(String canvasId);
  Future<void> deleteSnapshots(String canvasId);
}

/// Abstract permission provider
abstract class FlueraPermissionProvider {
  Future<bool> canEdit(String canvasId);
  Future<bool> canView(String canvasId);
  String get currentUserRole;

  /// Optional reactive stream of edit-permission changes for [canvasId].
  ///
  /// Emits `true` when the local user gains edit access, `false` when it
  /// is revoked. Implementations that wire this (e.g. via Postgres
  /// realtime on a `canvas_shares` table) let the canvas screen react to
  /// runtime revocation — without it, an editor whose access was removed
  /// while the canvas is open keeps broadcasting until they close and
  /// reopen the canvas.
  ///
  /// Returning `null` (the default) preserves the legacy
  /// "check-once-at-open" behavior; the canvas screen treats it as
  /// "no live updates available".
  Stream<bool>? canEditChanges(String canvasId) => null;
}

/// Abstract presence provider
abstract class FlueraPresenceProvider {
  ValueNotifier<List<FlueraPresenceUser>> get activeUsers;
  void joinCanvas(String canvasId);
  void leaveCanvas();
}

/// User presence data
class FlueraPresenceUser {
  final String id;
  final String name;
  final Color cursorColor;
  final Offset? cursorPosition;

  const FlueraPresenceUser({
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
abstract class FlueraPdfProvider {
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

  /// 🚀 Zero-copy rendering via TextureRegistry.
  ///
  /// Returns a [PdfTextureTile] containing a Flutter texture ID that
  /// can be composited directly by Impeller/Skia without any pixel copy.
  /// Returns `null` if the platform doesn't support TextureRegistry or
  /// if the render fails — caller should fall back to [renderPage].
  ///
  /// Default implementation returns `null` (texture path unavailable).
  Future<PdfTextureTile?> renderPageTexture({
    required int pageIndex,
    required double scale,
    required Size targetSize,
  }) async =>
      null;

  /// 🖼️ Fast low-resolution thumbnail for instant page preview.
  ///
  /// Returns a small `ui.Image` (~200px wide) suitable for showing
  /// an immediate placeholder while the full-LOD render is in progress.
  /// On iOS this uses Apple's optimized `PDFPage.thumbnail(of:for:)`.
  /// 
  /// Default implementation returns `null` (thumbnails unavailable).
  Future<ui.Image?> renderThumbnail(int pageIndex) async => null;

  /// Release all resources associated with the loaded document.
  void dispose();
}
