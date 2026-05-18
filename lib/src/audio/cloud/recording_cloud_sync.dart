// ============================================================================
// ☁️ RECORDING CLOUD SYNC — Phase 2 host-injected adapter for audio cross-device
//
// Engine-side abstract interface. The Fluera app provides a Supabase-backed
// concrete implementation via [FlueraCanvasConfig.recordingCloudSync]; the
// engine ships a [NoopRecordingCloudSync] so SDK consumers without Supabase
// keep working (local-only, like V1.0).
//
// CONTRACT:
// - [uploadRecording] is called fire-and-forget post-save. Returns the
//   `audioStorageUrl` (a bucket path or absolute URL — opaque to the engine)
//   on success, null on transient failure. The engine persists the returned
//   URL in SQLite so the next save is idempotent (no double upload).
// - [downloadRecording] is called lazily on first tap-stroke when the local
//   `audioPath` file is missing but `audioStorageUrl` is set. Returns the
//   absolute local path of the downloaded m4a, or null on failure.
// - [deleteRemote] is called after [RecordingStorageService.deleteRecording]
//   so the bucket doesn't grow unbounded with orphan files.
//
// All methods are async and MUST NOT throw — return null on failure. The
// engine assumes fail-open semantics: a missed upload is recoverable on the
// next session open (retry on canvas open), a missed download means the
// user just doesn't get playback this session but local strokes still work.
// ============================================================================

import '../../time_travel/models/synchronized_recording.dart';

/// Host-side adapter for cloud-syncing audio recording files (Phase 2 V1.5).
abstract class RecordingCloudSync {
  /// Upload the audio file at [recording.audioPath] to remote storage.
  ///
  /// The implementation chooses the storage path scheme; by convention the
  /// Supabase impl uses `{userId}/{canvasId}/{branchId}/{recordingId}.m4a`.
  /// Returns the storage URL (or path key) to persist as
  /// `SynchronizedRecording.audioStorageUrl`, or `null` on transient
  /// failure (offline, auth lapsed, bucket policy denied).
  Future<String?> uploadRecording(SynchronizedRecording recording);

  /// Download the audio file referenced by [recording.audioStorageUrl] to
  /// a local path. Implementations should write the bytes into the canonical
  /// `Documents/recordings/{filename}.m4a` location so the existing
  /// playback pipeline picks it up transparently.
  ///
  /// Returns the absolute local path on success, `null` on failure.
  Future<String?> downloadRecording(SynchronizedRecording recording);

  /// Delete the remote object for a recording that was deleted locally.
  /// Idempotent — implementations swallow "not found" errors.
  Future<void> deleteRemote(SynchronizedRecording recording);
}

/// Default no-op implementation. Used by SDK consumers that don't wire a
/// cloud backend (Phase 2 stays inert, behavior is identical to V1.0).
class NoopRecordingCloudSync implements RecordingCloudSync {
  const NoopRecordingCloudSync();

  @override
  Future<String?> uploadRecording(SynchronizedRecording recording) async =>
      null;

  @override
  Future<String?> downloadRecording(SynchronizedRecording recording) async =>
      null;

  @override
  Future<void> deleteRemote(SynchronizedRecording recording) async {}
}

/// Helper signature for chunk-based progress reporting. Optional — adapters
/// that don't expose progress can ignore this.
typedef CloudSyncProgressCallback = void Function(
  int bytesTransferred,
  int totalBytes,
);
