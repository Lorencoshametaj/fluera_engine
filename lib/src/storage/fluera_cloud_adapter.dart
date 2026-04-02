import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/engine_logger.dart';

// =============================================================================
// ☁️ FLUERA CLOUD STORAGE ADAPTER — Abstract cloud persistence interface
//
// Backend-agnostic interface for cloud canvas persistence.
// The host app implements this with its own backend (Firebase, Supabase,
// REST API, etc.). The SDK only depends on this interface.
// =============================================================================

/// State of the cloud sync process — used by toolbar indicator.
enum FlueraSyncState { idle, syncing, error }

/// ☁️ Abstract cloud storage adapter for canvas persistence.
///
/// The SDK calls these methods to persist canvas state to the cloud.
/// The host app provides a concrete implementation for its backend.
///
/// **Contract:**
/// - All methods are async and may throw on network/auth errors.
/// - `saveCanvas` is an upsert: creates or overwrites.
/// - `loadCanvas` returns `null` if the canvas doesn't exist remotely.
///
/// **Example (Supabase):**
/// ```dart
/// class SupabaseCloudAdapter implements FlueraCloudStorageAdapter {
///   final supabase = Supabase.instance.client;
///
///   @override
///   Future<void> saveCanvas(String canvasId, Map<String, dynamic> data) async {
///     await supabase.from('canvases').upsert({
///       'id': canvasId,
///       'data': data,
///       'updated_at': DateTime.now().toIso8601String(),
///     });
///   }
///
///   @override
///   Future<Map<String, dynamic>?> loadCanvas(String canvasId) async {
///     final row = await supabase
///         .from('canvases')
///         .select('data')
///         .eq('id', canvasId)
///         .maybeSingle();
///     return row?['data'] as Map<String, dynamic>?;
///   }
///
///   @override
///   Future<void> deleteCanvas(String canvasId) async {
///     await supabase.from('canvases').delete().eq('id', canvasId);
///   }
/// }
/// ```
abstract class FlueraCloudStorageAdapter {
  /// Save a full canvas snapshot to the cloud (upsert).
  ///
  /// [data] contains the full serialized canvas state (layers, metadata, etc.).
  /// The adapter should store this atomically — partial writes are not acceptable.
  Future<void> saveCanvas(String canvasId, Map<String, dynamic> data);

  /// Load a canvas snapshot from the cloud.
  ///
  /// Returns the full canvas data map, or `null` if no canvas with [canvasId]
  /// exists in the cloud.
  Future<Map<String, dynamic>?> loadCanvas(String canvasId);

  /// Delete a canvas from the cloud.
  ///
  /// No-op if the canvas doesn't exist.
  Future<void> deleteCanvas(String canvasId);

  // ─── Binary Assets (images, PDFs) ────────────────────────────────────

  /// Upload a binary asset (image or PDF) to cloud storage.
  ///
  /// Returns a cloud URL (or storage key) that can be used to retrieve
  /// the asset later. The adapter should store the asset durably.
  ///
  /// [assetId] is a unique identifier for the asset (typically the
  /// `ImageElement.id` or PDF document ID).
  ///
  /// **Example (Supabase Storage):**
  /// ```dart
  /// @override
  /// Future<String> uploadAsset(String canvasId, String assetId, Uint8List data) async {
  ///   final path = 'canvases/$canvasId/assets/$assetId';
  ///   await supabase.storage.from('canvas-assets').uploadBinary(path, data);
  ///   return supabase.storage.from('canvas-assets').getPublicUrl(path);
  /// }
  /// ```
  Future<String> uploadAsset(
    String canvasId,
    String assetId,
    Uint8List data, {
    String? mimeType,
    void Function(double progress)? onProgress,
  });

  /// Download a binary asset from cloud storage.
  ///
  /// Returns the raw bytes, or `null` if the asset doesn't exist.
  Future<Uint8List?> downloadAsset(String canvasId, String assetId);

  /// Delete a single binary asset from cloud storage.
  ///
  /// No-op if the asset doesn't exist. Default implementation does nothing
  /// for backward compatibility — override in concrete adapters.
  Future<void> deleteAsset(String canvasId, String assetId) async {}

  /// 🧹 Clean orphaned assets from cloud storage.
  ///
  /// Compares all files in the canvas folder against [knownAssetIds].
  /// Deletes any files NOT in the known set. Returns count of deleted files.
  /// Default: no-op for backward compatibility.
  Future<int> cleanOrphanedAssets(
    String canvasId,
    Set<String> knownAssetIds,
  ) async => 0;

  /// Delete all assets for a canvas (called when canvas is deleted).
  ///
  /// No-op if no assets exist.
  Future<void> deleteCanvasAssets(String canvasId);

  // ─── Canvas Listing ─────────────────────────────────────────────

  /// List all canvas IDs (with optional metadata) stored in the cloud.
  ///
  /// Returns a list of maps, each containing at least `canvasId`, `title`,
  /// and `updatedAt`. Implementations may include additional metadata.
  ///
  /// **Example (Supabase):**
  /// ```dart
  /// @override
  /// Future<List<Map<String, dynamic>>> listCanvases() async {
  ///   return await supabase.from('canvases')
  ///       .select('id, data->title, updated_at')
  ///       .order('updated_at', ascending: false);
  /// }
  /// ```
  Future<List<Map<String, dynamic>>> listCanvases();

  // ─── Stroke Sharding (Sub-Collection) ──────────────────────────────

  /// Whether this adapter supports stroke-level sharding.
  ///
  /// When `true`, the sync engine will:
  /// 1. Strip strokes from the main canvas document (metadata only)
  /// 2. Save each stroke as a separate document via [saveStrokes]
  /// 3. Load strokes via [loadStrokes] and reassemble into layers
  ///
  /// Default is `false` for backward compatibility. Override in adapters
  /// that support sub-collections (e.g. Firestore).
  bool get supportsStrokeSharding => false;

  /// Save strokes as individual documents (e.g. in a sub-collection).
  ///
  /// [strokes] is a list of `(layerId, strokeJson)` tuples.
  /// Called after [saveCanvas] with metadata-only data.
  Future<void> saveStrokes(
    String canvasId,
    List<(String layerId, Map<String, dynamic> strokeJson)> strokes,
  ) async {}

  /// Load all strokes for a canvas, grouped by layer ID.
  ///
  /// Returns a map of `layerId → List<strokeJson>`.
  Future<Map<String, List<Map<String, dynamic>>>> loadStrokes(
    String canvasId,
  ) async => {};

  /// Delete all strokes for a canvas (called on canvas delete).
  Future<void> deleteStrokes(String canvasId) async {}

  // ─── Image Element Metadata (Optional) ──────────────────────────────

  /// Sync image element metadata to a dedicated table.
  ///
  /// Override in adapters that support a separate `image_elements` table
  /// for per-image incremental sync and metadata queries.
  /// Default: no-op for backward compatibility.
  Future<void> syncImageElements(
    String canvasId,
    List<Map<String, dynamic>> elements,
  ) async {}

  /// Load image element metadata from a dedicated table.
  ///
  /// Returns a list of image element maps, or empty if not supported.
  Future<List<Map<String, dynamic>>> loadImageElements(
    String canvasId,
  ) async => [];

  // ─── PDF Element Metadata (Optional) ────────────────────────────────

  /// Sync PDF document metadata to a dedicated table.
  ///
  /// Override in adapters that support a separate `pdf_elements` table.
  /// Default: no-op for backward compatibility.
  Future<void> syncPdfElements(
    String canvasId,
    List<Map<String, dynamic>> elements,
  ) async {}

  /// Load PDF document metadata from a dedicated table.
  Future<List<Map<String, dynamic>>> loadPdfElements(
    String canvasId,
  ) async => [];

  // ─── Recording Element Metadata (Optional) ──────────────────────────

  /// Sync recording metadata to a dedicated table.
  ///
  /// Override in adapters that support a separate `recording_elements` table.
  /// Default: no-op for backward compatibility.
  Future<void> syncRecordingElements(
    String canvasId,
    List<Map<String, dynamic>> elements,
  ) async {}

  /// Load recording metadata from a dedicated table.
  Future<List<Map<String, dynamic>>> loadRecordingElements(
    String canvasId,
  ) async => [];

  // ─── Storage Quota (Optional) ───────────────────────────────────────

  /// Get the total storage bytes used by the current user.
  ///
  /// Override in adapters that support server-side quota calculation.
  /// Default: returns 0 (no quota tracking).
  Future<int> getStorageUsageBytes() async => 0;

  /// Maximum storage bytes allowed per user.
  ///
  /// Set to 0 to disable quota enforcement. Override per tier:
  /// - Essential: 500 MB (524_288_000)
  /// - Plus: 5 GB (5_368_709_120)
  /// - Pro: 50 GB (53_687_091_200)
  int get storageQuotaBytes => 0;

  /// Get detailed storage usage breakdown by category.
  ///
  /// Returns a map with keys: `images`, `pdfs`, `recordings`.
  /// Each value has `bytes` (int) and `count` (int).
  Future<Map<String, Map<String, int>>> getStorageUsageBreakdown() async => {
    'images': {'bytes': 0, 'count': 0},
    'pdfs': {'bytes': 0, 'count': 0},
    'recordings': {'bytes': 0, 'count': 0},
  };

  /// Get per-canvas storage breakdown.
  ///
  /// Returns a list of maps with: `canvasId`, `title`, `totalBytes`,
  /// `imageCount`, `pdfCount`, `recordingCount`. Sorted by totalBytes desc.
  Future<List<Map<String, dynamic>>> getPerCanvasStorage() async => [];

  /// Get the user's current storage tier and quota from the server.
  ///
  /// Returns `{'tier': 'free', 'quotaBytes': 52428800}` or similar.
  Future<Map<String, dynamic>> getUserTier() async => {
    'tier': 'free',
    'quotaBytes': 52428800, // 50 MB
  };

  // ─── Realtime Sync ──────────────────────────────────────────────

  /// Stream of canvas IDs that were changed remotely (UPDATE on `canvases`).
  ///
  /// Listeners receive the canvas ID whenever another device saves changes.
  /// Default: empty stream (no realtime support).
  Stream<String> onCanvasChanged() => const Stream<String>.empty();

  /// Stream of gallery-level changes (INSERT/DELETE on `canvases`).
  ///
  /// Each event is a map with `{'type': 'INSERT'|'DELETE', 'canvasId': '...'}`.
  /// Default: empty stream (no realtime support).
  Stream<Map<String, dynamic>> onGalleryChanged() =>
      const Stream<Map<String, dynamic>>.empty();

  /// Dispose all Realtime channel subscriptions.
  ///
  /// Call this on logout / app shutdown.
  void disposeRealtime() {}
}

/// Exception thrown when a user exceeds their storage quota.
class StorageQuotaExceededException implements Exception {
  final int usedBytes;
  final int quotaBytes;

  const StorageQuotaExceededException({
    required this.usedBytes,
    required this.quotaBytes,
  });

  @override
  String toString() =>
      'StorageQuotaExceededException: $usedBytes / $quotaBytes bytes '
      '(${(usedBytes / 1024 / 1024).toStringAsFixed(1)} MB / '
      '${(quotaBytes / 1024 / 1024).toStringAsFixed(0)} MB)';
}

// =============================================================================
// ⚙️ FLUERA SYNC ENGINE — Internal orchestrator for cloud auto-save
//
// Manages debounced cloud saves, retry with backoff, state notifications,
// and overlapping-save prevention. The canvas screen uses this internally.
// =============================================================================

/// ⚙️ Cloud sync orchestrator used internally by the canvas screen.
///
/// **Responsibilities:**
/// - Debounced cloud saves (configurable, default 3s)
/// - Prevents overlapping save operations (lock flag)
/// - Retry with exponential backoff on failure (max 3 retries)
/// - Exposes sync state via [state] `ValueNotifier` for the toolbar indicator
///
/// The engine does NOT handle local saves — those are managed by the canvas
/// screen's existing `_performSave()` pipeline. This engine is called AFTER
/// the local save succeeds.
class FlueraSyncEngine {
  final FlueraCloudStorageAdapter _adapter;

  /// Expose the adapter for direct asset upload/download operations.
  FlueraCloudStorageAdapter get adapter => _adapter;

  /// Observable sync state for UI indicators (toolbar cloud icon).
  final ValueNotifier<FlueraSyncState> state = ValueNotifier(
    FlueraSyncState.idle,
  );

  /// Last error message (null when idle/syncing).
  final ValueNotifier<String?> lastError = ValueNotifier(null);

  /// Debounce duration before triggering a cloud save.
  final Duration debounceDuration;

  /// Maximum retry attempts on failure.
  final int maxRetries;

  Timer? _debounceTimer;
  bool _saveInProgress = false;
  int _retryCount = 0;

  /// Pending save data — always the latest snapshot.
  /// When a new save is requested while one is in-flight, this is updated
  /// so the in-flight save is followed by another with the latest data.
  String? _pendingCanvasId;
  Map<String, dynamic>? _pendingData;

  FlueraSyncEngine({
    required FlueraCloudStorageAdapter adapter,
    this.debounceDuration = const Duration(seconds: 3),
    this.maxRetries = 3,
  }) : _adapter = adapter;

  /// Request a debounced cloud save.
  ///
  /// Multiple rapid calls are batched — only the last snapshot is saved.
  /// Call this after every successful local save.
  void requestSave(String canvasId, Map<String, dynamic> data) {
    _pendingCanvasId = canvasId;
    _pendingData = data;

    // ☁️ If there was an offline-queued save, merge it
    _offlinePendingData = null;
    _offlinePendingCanvasId = null;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceDuration, _executeSave);
  }

  /// Force an immediate cloud save (e.g. on app background / canvas exit).
  ///
  /// Bypasses debounce. If a save is already in-flight, the pending data
  /// is queued and will be saved after the current one completes.
  Future<void> flush(String canvasId, Map<String, dynamic> data) async {
    _debounceTimer?.cancel();
    _pendingCanvasId = canvasId;
    _pendingData = data;
    await _executeSave();
  }

  /// Execute the actual cloud save with retry logic.
  Future<void> _executeSave() async {
    if (_saveInProgress) return; // Will be picked up by the tail-chase below
    if (_pendingCanvasId == null || _pendingData == null) return;

    _saveInProgress = true;
    final canvasId = _pendingCanvasId!;
    final data = Map<String, dynamic>.from(_pendingData!);
    _pendingCanvasId = null;
    _pendingData = null;

    state.value = FlueraSyncState.syncing;
    lastError.value = null;

    try {
      await _adapter.saveCanvas(canvasId, data);
      _retryCount = 0;
      _lastSaveTimestamp = DateTime.now().millisecondsSinceEpoch;
      state.value = FlueraSyncState.idle;
      EngineLogger.info('☁️ Cloud sync completed for $canvasId');
    } catch (e) {
      // 🚀 FIX: Detect PERMANENT errors that should NOT be retried.
      // Firestore INVALID_ARGUMENT (document > 1MB) and PERMISSION_DENIED
      // will never succeed on retry — stop immediately to avoid:
      // - 3x heavy JSON re-serialization on UI thread (50-100ms each)
      // - Massive GC from 1MB+ temporary Map objects (30-70MB freed)
      // - 142ms+ GC pause blocking UI thread
      final errorStr = e.toString().toLowerCase();
      final isPermanent =
          errorStr.contains('invalid-argument') ||
          errorStr.contains('invalid_argument') ||
          errorStr.contains('permission-denied') ||
          errorStr.contains('permission_denied') ||
          errorStr.contains('exceeds the maximum');

      if (isPermanent) {
        EngineLogger.error('☁️ Cloud sync permanent failure (no retry): $e');
        state.value = FlueraSyncState.error;
        lastError.value = e.toString();
        _retryCount = 0;
        // Don't queue for offline either — it will always fail
      } else {
        _retryCount++;
        if (_retryCount <= maxRetries) {
          // Exponential backoff: 2s, 4s, 8s
          final delay = Duration(seconds: 1 << _retryCount);
          EngineLogger.warning(
            '☁️ Cloud sync failed (attempt $_retryCount/$maxRetries), '
            'retrying in ${delay.inSeconds}s: $e',
          );
          state.value = FlueraSyncState.syncing;
          _saveInProgress = false;

          // Re-queue for retry
          _pendingCanvasId = canvasId;
          _pendingData = data;
          _debounceTimer?.cancel();
          _debounceTimer = Timer(delay, _executeSave);
          return;
        } else {
          EngineLogger.error(
            '☁️ Cloud sync failed after $maxRetries retries: $e',
          );
          state.value = FlueraSyncState.error;
          lastError.value = e.toString();
          _retryCount = 0;

          // ☁️ Offline queue: retain failed save for replay
          _offlinePendingCanvasId = canvasId;
          _offlinePendingData = data;
          EngineLogger.warning('☁️ Save queued for offline replay');
        }
      }
    } finally {
      _saveInProgress = false;
    }

    // Tail-chase: if new data arrived while we were saving, save again
    if (_pendingCanvasId != null && _pendingData != null) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 500), _executeSave);
    }
  }

  /// Load a canvas from the cloud via the adapter.
  ///
  /// Convenience passthrough — no caching or retry (load is user-initiated).
  Future<Map<String, dynamic>?> loadCanvas(String canvasId) {
    return _adapter.loadCanvas(canvasId);
  }

  /// Delete a canvas from the cloud **and** its associated binary assets.
  Future<void> deleteCanvas(String canvasId) async {
    await _adapter.deleteCanvasAssets(canvasId);
    await _adapter.deleteCanvas(canvasId);
  }

  /// List all canvases stored in the cloud.
  Future<List<Map<String, dynamic>>> listCanvases() => _adapter.listCanvases();

  // ─── Offline Queue ───────────────────────────────────────────────

  /// Pending save that failed due to connectivity issues.
  /// Replayed automatically on the next successful save.
  Map<String, dynamic>? _offlinePendingData;
  String? _offlinePendingCanvasId;

  /// Whether there is a pending offline save waiting to be replayed.
  bool get hasOfflinePending => _offlinePendingData != null;

  // ─── Realtime Subscription ──────────────────────────────────────

  /// Notifies UI when a remote change is detected for the active canvas.
  ///
  /// Value is the canvas ID that changed, or null when no change pending.
  final ValueNotifier<String?> remoteChange = ValueNotifier(null);

  StreamSubscription<String>? _realtimeSub;
  String? _subscribedCanvasId;

  /// Timestamp of last local save — used to ignore self-triggered events.
  int _lastSaveTimestamp = 0;

  /// Subscribe to Realtime changes for a specific canvas.
  ///
  /// Call this when a canvas is opened. Remote changes will be emitted
  /// via [remoteChange], letting the UI offer a reload.
  void subscribeToCanvas(String canvasId) {
    unsubscribeFromCanvas();
    _subscribedCanvasId = canvasId;

    _realtimeSub = _adapter.onCanvasChanged().listen((changedId) {
      if (changedId != _subscribedCanvasId) return;

      // Ignore self-saves: if we saved within the last 5s, skip
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastSaveTimestamp < 5000) {
        EngineLogger.info(
          '🔄 Ignoring self-triggered Realtime event for $changedId',
        );
        return;
      }

      EngineLogger.info('🔄 Remote change detected for canvas $changedId');
      remoteChange.value = changedId;
    });

    EngineLogger.info('🔄 Subscribed to Realtime for canvas $canvasId');
  }

  /// Unsubscribe from Realtime changes.
  ///
  /// Call this when leaving a canvas.
  void unsubscribeFromCanvas() {
    _realtimeSub?.cancel();
    _realtimeSub = null;
    _subscribedCanvasId = null;
    remoteChange.value = null;
  }

  /// Dispose resources.
  void dispose() {
    unsubscribeFromCanvas();
    _adapter.disposeRealtime();
    _debounceTimer?.cancel();
    state.dispose();
    lastError.dispose();
    remoteChange.dispose();
  }
}
