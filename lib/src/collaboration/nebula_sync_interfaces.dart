import '../history/models/canvas_branch.dart';
import '../core/models/canvas_layer.dart';
import '../time_travel/models/time_travel_session.dart';

// =============================================================================
// NEBULA SYNC INTERFACES
//
// Abstract interfaces for app-coupled Firebase services.
// The SDK depends on these interfaces; the host app provides implementations.
// =============================================================================

/// 💾 Interface for Time Travel data persistence
///
/// Wraps local storage of time travel sessions, events, and snapshots.
/// The host app implements this with its own auth + path_provider logic.
abstract class NebulaTimeTravelStorage {
  /// Load session index (lightweight metadata only)
  Future<List<TimeTravelSession>> loadSessionIndex(
    String canvasId, {
    String? branchId,
  });

  /// Load events for a specific session
  Future<List<TimeTravelEvent>> loadSessionEvents(
    TimeTravelSession session, {
    String? branchId,
  });

  /// Load nearest snapshot ≤ target session index
  Future<(List<CanvasLayer>, int)?> loadNearestSnapshot(
    String canvasId,
    int targetSessionIndex, {
    String? branchId,
  });

  /// Load session index without branch (for parent timeline)
  Future<String> getTimeTravelPathForCanvas(String canvasId);
}

/// 🔄 Interface for branch cloud synchronization
///
/// Wraps Firestore metadata + Cloud Storage snapshots for creative branches.
/// The host app implements this with Firebase SDK.
abstract class NebulaBranchCloudSync {
  /// Sync branch metadata to Firestore
  Future<void> syncBranchMetadata(String canvasId, CanvasBranch branch);

  /// Upload fork snapshot to Cloud Storage
  Future<void> uploadForkSnapshot({
    required String canvasId,
    required String branchId,
    required List<CanvasLayer> layers,
  });

  /// Delete branch from cloud
  Future<void> deleteBranchCloud(String canvasId, String branchId);

  /// Schedule a debounced upload
  void scheduleDebouncedUpload({
    required String canvasId,
    required CanvasBranch branch,
    required List<CanvasLayer> layers,
    required void Function(CanvasBranch updated) onUploaded,
  });

  /// Sync branches with cloud (merge local + remote)
  Future<List<CanvasBranch>> syncWithCloud({
    required String canvasId,
    required List<CanvasBranch> localBranches,
    required Future<List<CanvasLayer>> Function(String branchId) getLocalLayers,
    required Future<void> Function(String branchId, List<CanvasLayer> layers)
    saveLocalSnapshot,
  });

  /// Upload Time Travel sessions to cloud
  Future<int> uploadTTSessions({
    required String canvasId,
    required String branchId,
    required int alreadySyncedCount,
  });

  /// Download Time Travel sessions from cloud
  Future<int> downloadTTSessions({
    required String canvasId,
    required String branchId,
  });
}

/// 🔥 Interface for realtime delta synchronization
///
/// Wraps Firebase Realtime Database for low-latency canvas sync.
/// The host app implements this with Firebase RTDB SDK.
abstract class NebulaRealtimeDeltaSync {
  /// Start listening for remote deltas
  Future<void> startListening({
    required String canvasId,
    required String currentUserId,
    required void Function(Map<String, dynamic> delta) onDelta,
    int? lastProcessedEpoch,
    String? branchId,
  });

  /// Stop listening for deltas
  Future<void> stopListening();

  /// Start listening for remote cursors
  Future<void> listenCursors({
    required String canvasId,
    required String currentUserId,
    required void Function(Map<String, Map<String, dynamic>> cursors) onUpdate,
  });

  /// Stop listening for cursors
  Future<void> stopListeningCursors();
}
