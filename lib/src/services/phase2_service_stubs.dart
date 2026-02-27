// ============================================================================
// 🔧 PHASE 2 SERVICE STUBS
//
// Minimal stub classes for Looponia services referenced by kept part files.
// Avoids commenting out large blocks of orchestration logic that will be
// re-implemented when Phase 2 features are added to the SDK.
// ============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import '../utils/safe_path_provider.dart';

import '../history/models/canvas_branch.dart';
import '../core/models/canvas_layer.dart';
import '../time_travel/models/time_travel_session.dart';
import '../time_travel/services/time_travel_playback_engine.dart';
import '../time_travel/services/time_travel_recorder.dart';

// ─── Inlined Interfaces (were in deleted fluera_sync_interfaces.dart) ────

/// Abstract interface for time travel storage.
/// Phase 2: host app will provide a concrete implementation.
abstract class FlueraTimeTravelStorage {
  Future<List<TimeTravelSession>> loadSessionIndex(
    String canvasId, {
    String? branchId,
  });
  Future<List<TimeTravelEvent>> loadSessionEvents(
    TimeTravelSession session, {
    String? branchId,
  });
  Future<(List<CanvasLayer>, int)?> loadNearestSnapshot(
    String canvasId,
    int targetSessionIndex, {
    String? branchId,
  });
  Future<String> getTimeTravelPathForCanvas(String canvasId);
}

/// Abstract interface for branch cloud sync.
/// Phase 2: host app will provide a Firebase RTDB-backed implementation.
abstract class FlueraBranchCloudSync {
  Future<void> syncBranchMetadata(String canvasId, CanvasBranch branch);
  Future<void> uploadForkSnapshot({
    required String canvasId,
    required String branchId,
    required List<CanvasLayer> layers,
  });
  Future<void> deleteBranchCloud(String canvasId, String branchId);
  void scheduleDebouncedUpload({
    required String canvasId,
    required CanvasBranch branch,
    required List<CanvasLayer> layers,
    required void Function(CanvasBranch updated) onUploaded,
  });
  Future<List<CanvasBranch>> syncWithCloud({
    required String canvasId,
    required List<CanvasBranch> localBranches,
    required Future<List<CanvasLayer>> Function(String branchId) getLocalLayers,
    required Future<void> Function(String branchId, List<CanvasLayer> layers)
    saveLocalSnapshot,
  });
  Future<int> uploadTTSessions({
    required String canvasId,
    required String branchId,
    required int alreadySyncedCount,
  });
  Future<int> downloadTTSessions({
    required String canvasId,
    required String branchId,
  });
}

// ─── TimeTravelStorageService ───────────────────────────────────────────

/// Stub implementation of [FlueraTimeTravelStorage].
/// Phase 2: the host app will provide a real implementation backed by
/// local filesystem + path_provider.
class TimeTravelStorageService implements FlueraTimeTravelStorage {
  @override
  Future<List<TimeTravelSession>> loadSessionIndex(
    String canvasId, {
    String? branchId,
  }) async {
    final basePath = await _getSessionBasePath(canvasId, branchId: branchId);
    final indexFile = File(p.join(basePath, 'index.json'));

    if (!await indexFile.exists()) return [];

    try {
      final content = await indexFile.readAsString();
      final List<dynamic> jsonList = jsonDecode(content) as List<dynamic>;
      return jsonList
          .map(
            (j) =>
                TimeTravelSession.fromJson(Map<String, dynamic>.from(j as Map)),
          )
          .toList();
    } catch (e) {
      debugPrint('🎬 [TTStorage] Error loading session index: $e');
      return [];
    }
  }

  @override
  Future<List<TimeTravelEvent>> loadSessionEvents(
    TimeTravelSession session, {
    String? branchId,
  }) async {
    final basePath = await _getSessionBasePath(
      session.canvasId,
      branchId: branchId,
    );
    final file = File(p.join(basePath, session.deltaFilePath));

    if (!await file.exists()) {
      debugPrint(
        '🎬 [TTStorage] Session file not found: ${session.deltaFilePath}',
      );
      return [];
    }

    try {
      final compressed = await file.readAsBytes();
      final decompressed = gzip.decode(compressed);
      final text = utf8.decode(decompressed);
      final lines = text.trim().split('\n').where((l) => l.isNotEmpty).toList();

      return lines.map((line) {
        final json = jsonDecode(line) as Map<String, dynamic>;
        return TimeTravelEvent.fromJson(json);
      }).toList();
    } catch (e) {
      debugPrint(
        '🎬 [TTStorage] Error loading events from ${session.deltaFilePath}: $e',
      );
      return [];
    }
  }

  @override
  Future<(List<CanvasLayer>, int)?> loadNearestSnapshot(
    String canvasId,
    int targetSessionIndex, {
    String? branchId,
  }) async {
    final basePath = await _getSessionBasePath(canvasId, branchId: branchId);
    final snapshotsDir = Directory(p.join(basePath, 'snapshots'));

    if (!await snapshotsDir.exists()) return null;

    // Scan snapshot files: named snapshot_{sessionIndex}.json
    // Find the one with the highest index ≤ targetSessionIndex
    int bestIndex = -1;
    File? bestFile;

    await for (final entity in snapshotsDir.list()) {
      if (entity is File && entity.path.endsWith('.json')) {
        final name = p.basenameWithoutExtension(entity.path);
        final match = RegExp(r'snapshot_(\d+)').firstMatch(name);
        if (match != null) {
          final idx = int.parse(match.group(1)!);
          if (idx <= targetSessionIndex && idx > bestIndex) {
            bestIndex = idx;
            bestFile = entity;
          }
        }
      }
    }

    if (bestFile == null) return null;

    try {
      final content = await bestFile.readAsString();
      final List<dynamic> jsonList = jsonDecode(content) as List<dynamic>;
      final layers =
          jsonList
              .map(
                (j) =>
                    CanvasLayer.fromJson(Map<String, dynamic>.from(j as Map)),
              )
              .toList();
      return (layers, bestIndex);
    } catch (e) {
      debugPrint('🎬 [TTStorage] Error loading snapshot: $e');
      return null;
    }
  }

  @override
  Future<String> getTimeTravelPathForCanvas(String canvasId) async {
    final dir = await getSafeDocumentsDirectory();
    if (dir == null) return ''; // Web: no filesystem
    return p.join(dir.path, 'fluera_tt', canvasId);
  }

  /// 💾 Save a recorded session to disk.
  ///
  /// 1. Flush recorder events to compressed GZIP JSONL via `recorder.flushToDisk`
  /// 2. Save a layer snapshot every N sessions for fast state reconstruction
  /// 3. Append the new session to the index file
  Future<void> saveRecordedSession(
    TimeTravelRecorder recorder,
    String canvasId, {
    List<CanvasLayer>? currentLayers,
    String? branchId,
  }) async {
    if (!recorder.hasEvents) {
      debugPrint('🎬 [TTStorage] No events to save');
      return;
    }

    final basePath = await _getSessionBasePath(canvasId, branchId: branchId);

    // 1. Flush events to disk (recorder handles GZIP compression in isolate)
    final session = await recorder.flushToDisk(canvasId, basePath);
    if (session == null) return;

    // 2. Load existing index
    final indexFile = File(p.join(basePath, 'index.json'));
    List<Map<String, dynamic>> existingIndex = [];
    if (await indexFile.exists()) {
      try {
        final content = await indexFile.readAsString();
        existingIndex =
            (jsonDecode(content) as List<dynamic>).cast<Map<String, dynamic>>();
      } catch (_) {}
    }

    // 3. Append new session
    existingIndex.add(session.toJson());
    await indexFile.parent.create(recursive: true);
    await indexFile.writeAsString(jsonEncode(existingIndex));

    // 4. Save layer snapshot every 5 sessions (for fast reconstruction)
    if (currentLayers != null && existingIndex.length % 5 == 0) {
      await _saveSnapshot(basePath, existingIndex.length - 1, currentLayers);
    }

    debugPrint(
      '🎬 [TTStorage] Saved session ${session.id} '
      '(${session.deltaCount} events, index #${existingIndex.length - 1})',
    );
  }

  /// 🗑️ Delete all time travel history for a canvas/branch.
  Future<void> deleteHistory(String canvasId, {String? branchId}) async {
    final basePath = await _getSessionBasePath(canvasId, branchId: branchId);
    final dir = Directory(basePath);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      debugPrint('🎬 [TTStorage] Deleted history at $basePath');
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // PRIVATE HELPERS
  // ════════════════════════════════════════════════════════════════════════

  /// Get the base storage path for sessions.
  /// Branch sessions go in `{ttPath}/branches/{branchId}/`.
  /// Main sessions go in `{ttPath}/`.
  Future<String> _getSessionBasePath(
    String canvasId, {
    String? branchId,
  }) async {
    final ttPath = await getTimeTravelPathForCanvas(canvasId);
    if (branchId != null) {
      return p.join(ttPath, 'branches', branchId);
    }
    return ttPath;
  }

  /// Save a layer snapshot at a given session index.
  Future<void> _saveSnapshot(
    String basePath,
    int sessionIndex,
    List<CanvasLayer> layers,
  ) async {
    final snapshotDir = Directory(p.join(basePath, 'snapshots'));
    await snapshotDir.create(recursive: true);
    final file = File(p.join(snapshotDir.path, 'snapshot_$sessionIndex.json'));
    final json = layers.map((l) => l.toJson()).toList();
    await file.writeAsString(jsonEncode(json));
    debugPrint(
      '🎬 [TTStorage] Saved snapshot at session index $sessionIndex '
      '(${layers.length} layers)',
    );
  }
}

// ─── BranchCloudSyncService ─────────────────────────────────────────────

/// Stub implementation of [FlueraBranchCloudSync].
/// Phase 2: the host app will provide a Firebase RTDB-backed implementation.
class BranchCloudSyncService implements FlueraBranchCloudSync {
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

// AudioRecordingController — removed.
// Replaced by NativeAudioRecorder + DefaultVoiceRecordingProvider in
// lib/src/audio/.

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
