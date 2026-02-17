// ============================================================================
// 🔧 PHASE 2 SERVICE STUBS
//
// Minimal stub classes for Looponia services referenced by kept part files.
// Avoids commenting out large blocks of orchestration logic that will be
// re-implemented when Phase 2 features are added to the SDK.
// ============================================================================

import 'package:flutter/widgets.dart';

import '../collaboration/nebula_sync_interfaces.dart';
import '../history/models/canvas_branch.dart';
import '../core/models/canvas_layer.dart';
import '../time_travel/models/time_travel_session.dart';
import '../time_travel/services/time_travel_playback_engine.dart';
import '../time_travel/services/time_travel_recorder.dart';

// ─── TimeTravelStorageService ───────────────────────────────────────────

/// Stub implementation of [NebulaTimeTravelStorage].
/// Phase 2: the host app will provide a real implementation backed by
/// local filesystem + path_provider.
class TimeTravelStorageService implements NebulaTimeTravelStorage {
  @override
  Future<List<TimeTravelSession>> loadSessionIndex(
    String canvasId, {
    String? branchId,
  }) async => [];

  @override
  Future<List<TimeTravelEvent>> loadSessionEvents(
    TimeTravelSession session, {
    String? branchId,
  }) async => [];

  @override
  Future<(List<CanvasLayer>, int)?> loadNearestSnapshot(
    String canvasId,
    int targetSessionIndex, {
    String? branchId,
  }) async => null;

  @override
  Future<String> getTimeTravelPathForCanvas(String canvasId) async =>
      '/tmp/nebula_tt/$canvasId';

  /// Save a recorded session (called from _lifecycle.dart).
  /// Phase 2: serialize + compress events to disk.
  Future<void> saveRecordedSession(
    TimeTravelRecorder recorder,
    String canvasId, {
    List<CanvasLayer>? currentLayers,
    String? branchId,
  }) async {
    debugPrint('[Phase2 Stub] TimeTravelStorageService.saveRecordedSession');
  }

  /// Delete time travel history.
  Future<void> deleteHistory(String canvasId, {String? branchId}) async {
    debugPrint('[Phase2 Stub] TimeTravelStorageService.deleteHistory');
  }
}

// ─── BranchCloudSyncService ─────────────────────────────────────────────

/// Stub implementation of [NebulaBranchCloudSync].
/// Phase 2: the host app will provide a Firebase RTDB-backed implementation.
class BranchCloudSyncService implements NebulaBranchCloudSync {
  BranchCloudSyncService._();
  static final BranchCloudSyncService instance = BranchCloudSyncService._();

  @override
  Future<void> syncBranchMetadata(String canvasId, CanvasBranch branch) async {}

  @override
  Future<void> uploadForkSnapshot({
    required String canvasId,
    required String branchId,
    required List<CanvasLayer> layers,
  }) async {}

  @override
  Future<void> deleteBranchCloud(String canvasId, String branchId) async {}

  @override
  void scheduleDebouncedUpload({
    required String canvasId,
    required CanvasBranch branch,
    required List<CanvasLayer> layers,
    required void Function(CanvasBranch updated) onUploaded,
  }) {}

  @override
  Future<List<CanvasBranch>> syncWithCloud({
    required String canvasId,
    required List<CanvasBranch> localBranches,
    required Future<List<CanvasLayer>> Function(String branchId) getLocalLayers,
    required Future<void> Function(String branchId, List<CanvasLayer> layers)
    saveLocalSnapshot,
  }) async => localBranches;

  @override
  Future<int> uploadTTSessions({
    required String canvasId,
    required String branchId,
    required int alreadySyncedCount,
  }) async => 0;

  @override
  Future<int> downloadTTSessions({
    required String canvasId,
    required String branchId,
  }) async => 0;
}

// ─── VoiceRecordingService ──────────────────────────────────────────────

/// Stub for voice recording management.
/// Phase 2: will manage audio recordings attached to canvases.
class VoiceRecordingService {
  static Future<List<VoiceRecordingStub>> getRecordingsForParent(
    String parentId,
  ) async => [];
}

/// Minimal recording data structure.
class VoiceRecordingStub {
  final String? audioPath;
  final String? recordingType;
  final String? strokesDataPath;
  VoiceRecordingStub({
    this.audioPath,
    this.recordingType,
    this.strokesDataPath,
  });
}

// ─── TimelapseExportDialog ──────────────────────────────────────────────

/// Stub for timelapse export dialog.
/// Phase 2: will show export options for time-travel recordings.
class TimelapseExportDialog {
  static void show(
    BuildContext context, {
    required TimeTravelPlaybackEngine engine,
    required int totalEventCount,
  }) {
    debugPrint('[Phase2 Stub] TimelapseExportDialog.show — not available yet');
  }
}

// ─── CanvasImageStorageService ──────────────────────────────────────────

/// Stub for cloud image storage for shared canvases.
/// Phase 2: will upload/download canvas images via Firebase Storage.
class CanvasImageStorageService {
  Future<String?> uploadImage({
    required String canvasId,
    required String imageId,
    required List<int> imageData,
    required String extension,
  }) async => null;

  Future<String?> uploadThumbnail({
    required String canvasId,
    required String imageId,
    required List<int> imageData,
  }) async => null;
}

// ─── AudioRecordingController ───────────────────────────────────────────

/// Stub for audio recording (Phase 2).
/// Phase 2: the host app will provide a real implementation backed by
/// platform-specific audio APIs.
class AudioRecordingController {
  final _service = StubRecordingService();
  StubRecordingService get service => _service;
  String? currentRecordingPath;
  Duration duration = Duration.zero;

  Future<void> start() async {}
  Future<String?> stop() async => null;
  Future<String?> startRecording() async {
    debugPrint(
      '[AudioRecordingController] Recording not available in SDK (Phase 2)',
    );
    return null;
  }

  Future<String?> startRecordingCompressed() async {
    debugPrint(
      '[AudioRecordingController] Compressed recording not available in SDK (Phase 2)',
    );
    return null;
  }

  Future<String?> stopRecording() async => null;
  Future<void> deleteTemporaryFile(String path) async {}
  void dispose() {}
}

/// Stub recording service used by [AudioRecordingController].
class StubRecordingService {
  bool get isRecording => false;
  bool get hasPermission => false;
  Future<bool> requestPermission() async => false;
}

// ─── ExportProgressController ───────────────────────────────────────────

/// Stub for export progress tracking (Phase 2).
/// Phase 2: will provide real-time export progress updates.
class ExportProgressController extends ChangeNotifier {
  double progress = 0.0;
  String? statusMessage;
  bool isExporting = false;

  Stream<double> get progressStream => const Stream.empty();
  Stream<int> get pageStream => const Stream.empty();

  void updateProgress(double value, {String? message}) {
    progress = value;
    statusMessage = message;
    notifyListeners();
  }

  void updatePage(int page) {
    notifyListeners();
  }
}
