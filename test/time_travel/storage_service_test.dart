import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/services/phase2_service_stubs.dart';
import 'package:nebula_engine/src/time_travel/services/time_travel_recorder.dart';
import 'package:nebula_engine/src/time_travel/models/time_travel_session.dart';
import 'package:nebula_engine/src/core/models/canvas_layer.dart';
import 'package:nebula_engine/src/history/canvas_delta_tracker.dart';

void main() {
  late Directory tempDir;
  late TimeTravelStorageService storage;

  const canvasId = 'test_canvas_storage';

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nebula_tt_storage_test_');
    // Override getTimeTravelPathForCanvas via subclass
    storage = _TestStorageService(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SAVE + LOAD ROUND-TRIP
  // ═══════════════════════════════════════════════════════════════════════════

  group('TimeTravelStorageService — saveRecordedSession', () {
    test('saves session and creates index.json', () async {
      final recorder = TimeTravelRecorder(start: DateTime(2025, 1, 1));
      recorder.startRecording();
      for (int i = 0; i < 5; i++) {
        recorder.recordEvent(
          CanvasDeltaType.strokeAdded,
          'layer_1',
          elementId: 'stroke_$i',
          elementData: {'color': 0xFF0000},
        );
      }

      await storage.saveRecordedSession(recorder, canvasId);

      // Verify index.json exists
      final indexFile = File('${tempDir.path}/$canvasId/index.json');
      expect(await indexFile.exists(), isTrue);

      // Verify index contains 1 session
      final content = await indexFile.readAsString();
      final list = jsonDecode(content) as List;
      expect(list, hasLength(1));
      expect(list[0]['count'], 5);
    });

    test('appends to existing index', () async {
      // First session
      final rec1 = TimeTravelRecorder(start: DateTime(2025, 1, 1));
      rec1.startRecording();
      rec1.recordEvent(CanvasDeltaType.strokeAdded, 'l1', elementId: 's1');
      await storage.saveRecordedSession(rec1, canvasId);

      // Second session
      final rec2 = TimeTravelRecorder(start: DateTime(2025, 1, 2));
      rec2.startRecording();
      rec2.recordEvent(CanvasDeltaType.strokeAdded, 'l1', elementId: 's2');
      rec2.recordEvent(CanvasDeltaType.strokeAdded, 'l1', elementId: 's3');
      await storage.saveRecordedSession(rec2, canvasId);

      // Verify index has 2 sessions
      final sessions = await storage.loadSessionIndex(canvasId);
      expect(sessions, hasLength(2));
      expect(sessions[0].deltaCount, 1);
      expect(sessions[1].deltaCount, 2);
    });

    test('no-ops for empty recorder', () async {
      final recorder = TimeTravelRecorder(start: DateTime(2025, 1, 1));
      recorder.startRecording();
      // No events recorded

      await storage.saveRecordedSession(recorder, canvasId);

      final indexFile = File('${tempDir.path}/$canvasId/index.json');
      expect(await indexFile.exists(), isFalse);
    });

    test('saves snapshot every 5 sessions', () async {
      final layers = [CanvasLayer(id: 'l1', name: 'Layer 1')];

      // Record 5 sessions to trigger snapshot
      for (int i = 0; i < 5; i++) {
        final rec = TimeTravelRecorder(start: DateTime(2025, 1, 1 + i));
        rec.startRecording();
        rec.recordEvent(CanvasDeltaType.strokeAdded, 'l1', elementId: 's$i');
        await storage.saveRecordedSession(rec, canvasId, currentLayers: layers);
      }

      // Verify snapshot was created at index 4 (5th session, 0-indexed)
      final snapshotFile = File(
        '${tempDir.path}/$canvasId/snapshots/snapshot_4.json',
      );
      expect(await snapshotFile.exists(), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // LOAD SESSION INDEX
  // ═══════════════════════════════════════════════════════════════════════════

  group('TimeTravelStorageService — loadSessionIndex', () {
    test('returns empty list for non-existent canvas', () async {
      final sessions = await storage.loadSessionIndex('nonexistent');
      expect(sessions, isEmpty);
    });

    test('loads saved sessions with correct metadata', () async {
      final rec = TimeTravelRecorder(start: DateTime(2025, 6, 15, 10, 0));
      rec.startRecording();
      for (int i = 0; i < 3; i++) {
        rec.recordEvent(CanvasDeltaType.strokeAdded, 'l1', elementId: 's$i');
      }
      await storage.saveRecordedSession(rec, canvasId);

      final sessions = await storage.loadSessionIndex(canvasId);
      expect(sessions, hasLength(1));
      expect(sessions[0].canvasId, canvasId);
      expect(sessions[0].deltaCount, 3);
      expect(sessions[0].strokesAdded, 3);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // LOAD SESSION EVENTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('TimeTravelStorageService — loadSessionEvents', () {
    test('loads and decompresses GZIP JSONL events', () async {
      final rec = TimeTravelRecorder(start: DateTime(2025, 1, 1));
      rec.startRecording();
      rec.recordEvent(
        CanvasDeltaType.strokeAdded,
        'layer_1',
        elementId: 'stroke_1',
        elementData: {'color': 0xFF0000},
      );
      rec.recordEvent(
        CanvasDeltaType.strokeRemoved,
        'layer_1',
        elementId: 'stroke_1',
      );
      await storage.saveRecordedSession(rec, canvasId);

      final sessions = await storage.loadSessionIndex(canvasId);
      final events = await storage.loadSessionEvents(sessions[0]);

      expect(events, hasLength(2));
      expect(events[0].type, CanvasDeltaType.strokeAdded);
      expect(events[0].layerId, 'layer_1');
      expect(events[1].type, CanvasDeltaType.strokeRemoved);
    });

    test('returns empty list for missing file', () async {
      final fakeSession = TimeTravelSession(
        id: 'fake',
        canvasId: canvasId,
        startTime: DateTime.now(),
        endTime: DateTime.now(),
        deltaCount: 0,
        deltaFilePath: 'nonexistent.tt.jsonl.gz',
      );

      final events = await storage.loadSessionEvents(fakeSession);
      expect(events, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // LOAD NEAREST SNAPSHOT
  // ═══════════════════════════════════════════════════════════════════════════

  group('TimeTravelStorageService — loadNearestSnapshot', () {
    test('returns null when no snapshots exist', () async {
      final result = await storage.loadNearestSnapshot(canvasId, 0);
      expect(result, isNull);
    });

    test('loads snapshot at correct index', () async {
      final layers = [
        CanvasLayer(id: 'l1', name: 'Layer 1'),
        CanvasLayer(id: 'l2', name: 'Layer 2'),
      ];

      // Save 5 sessions with layers to trigger snapshot at index 4
      for (int i = 0; i < 5; i++) {
        final rec = TimeTravelRecorder(start: DateTime(2025, 1, 1 + i));
        rec.startRecording();
        rec.recordEvent(CanvasDeltaType.strokeAdded, 'l1', elementId: 's$i');
        await storage.saveRecordedSession(rec, canvasId, currentLayers: layers);
      }

      // Load snapshot at or before index 4
      final result = await storage.loadNearestSnapshot(canvasId, 4);
      expect(result, isNotNull);
      final (loadedLayers, snapshotIndex) = result!;
      expect(loadedLayers, hasLength(2));
      expect(snapshotIndex, 4);
    });

    test('finds best snapshot ≤ target index', () async {
      final layers = [CanvasLayer(id: 'l1', name: 'L1')];

      // Save 10 sessions → snapshots at index 4 and 9
      for (int i = 0; i < 10; i++) {
        final rec = TimeTravelRecorder(start: DateTime(2025, 1, 1 + i));
        rec.startRecording();
        rec.recordEvent(CanvasDeltaType.strokeAdded, 'l1', elementId: 's$i');
        await storage.saveRecordedSession(rec, canvasId, currentLayers: layers);
      }

      // Ask for index 7 → should find snapshot at index 4 (not 9)
      final result = await storage.loadNearestSnapshot(canvasId, 7);
      expect(result, isNotNull);
      expect(result!.$2, 4);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // DELETE HISTORY
  // ═══════════════════════════════════════════════════════════════════════════

  group('TimeTravelStorageService — deleteHistory', () {
    test('deletes all files for canvas', () async {
      final rec = TimeTravelRecorder(start: DateTime(2025, 1, 1));
      rec.startRecording();
      rec.recordEvent(CanvasDeltaType.strokeAdded, 'l1', elementId: 's1');
      await storage.saveRecordedSession(rec, canvasId);

      // Verify files exist
      expect(
        await File('${tempDir.path}/$canvasId/index.json').exists(),
        isTrue,
      );

      // Delete
      await storage.deleteHistory(canvasId);

      // Verify directory is gone
      expect(await Directory('${tempDir.path}/$canvasId').exists(), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BRANCH SUPPORT
  // ═══════════════════════════════════════════════════════════════════════════

  group('TimeTravelStorageService — branch support', () {
    test('stores branch sessions in separate directory', () async {
      final rec = TimeTravelRecorder(start: DateTime(2025, 1, 1));
      rec.startRecording();
      rec.recordEvent(CanvasDeltaType.strokeAdded, 'l1', elementId: 's1');

      await storage.saveRecordedSession(rec, canvasId, branchId: 'br_feature');

      // Verify branch directory
      final branchDir = Directory(
        '${tempDir.path}/$canvasId/branches/br_feature',
      );
      expect(await branchDir.exists(), isTrue);

      // Load via branch
      final sessions = await storage.loadSessionIndex(
        canvasId,
        branchId: 'br_feature',
      );
      expect(sessions, hasLength(1));
    });
  });
}

/// Test subclass that overrides the base path to use a temp directory.
class _TestStorageService extends TimeTravelStorageService {
  final String basePath;
  _TestStorageService(this.basePath);

  @override
  Future<String> getTimeTravelPathForCanvas(String canvasId) async =>
      '$basePath/$canvasId';
}
