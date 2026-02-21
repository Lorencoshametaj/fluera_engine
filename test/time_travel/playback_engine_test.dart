import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/services/phase2_service_stubs.dart';
import 'package:nebula_engine/src/time_travel/services/time_travel_playback_engine.dart';
import 'package:nebula_engine/src/time_travel/models/time_travel_session.dart';
import 'package:nebula_engine/src/core/models/canvas_layer.dart';
import 'package:nebula_engine/src/history/canvas_delta_tracker.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // PLAYBACK ENGINE (widget tests with TickerProvider)
  // ═══════════════════════════════════════════════════════════════════════════

  group('TimeTravelPlaybackEngine', () {
    late _FakeTimeTravelStorage fakeStorage;

    setUp(() {
      fakeStorage = _FakeTimeTravelStorage();
    });

    testWidgets('initialize — no sessions returns false', (tester) async {
      final engine = TimeTravelPlaybackEngine(storage: fakeStorage);
      fakeStorage.sessionIndex = [];

      final result = await engine.initialize('canvas_1', tester);
      expect(result, isFalse);
      expect(engine.state, TimeTravelPlaybackState.idle);
      expect(engine.totalEventCount, 0);
      engine.dispose();
    });

    testWidgets('initialize — loads sessions and events', (tester) async {
      final engine = TimeTravelPlaybackEngine(storage: fakeStorage);

      // Set up fake data: 1 session with 5 events
      fakeStorage.sessionIndex = [
        TimeTravelSession(
          id: 'sess_1',
          canvasId: 'canvas_1',
          startTime: DateTime(2025, 1, 1),
          endTime: DateTime(2025, 1, 1, 0, 5),
          deltaCount: 5,
          deltaFilePath: 'sess_1.tt.jsonl.gz',
        ),
      ];
      fakeStorage.sessionEventsMap['sess_1'] = List.generate(
        5,
        (i) => TimeTravelEvent(
          type: CanvasDeltaType.strokeAdded,
          layerId: 'layer_1',
          timestampMs: i * 100,
          elementId: 'stroke_$i',
        ),
      );

      final result = await engine.initialize('canvas_1', tester);
      expect(result, isTrue);
      expect(engine.state, TimeTravelPlaybackState.paused);
      expect(engine.totalEventCount, 5);
      expect(engine.sessions, hasLength(1));
      engine.dispose();
    });

    testWidgets('seekToIndex — forward navigation', (tester) async {
      final engine = TimeTravelPlaybackEngine(storage: fakeStorage);
      _setupFakeSession(fakeStorage, eventCount: 10);

      await engine.initialize('canvas_1', tester);
      expect(engine.currentEventIndex, 10); // Starts at end

      // Seek to beginning
      await engine.seekToIndex(0);
      expect(engine.currentEventIndex, 0);

      // Seek forward
      await engine.seekToIndex(5);
      expect(engine.currentEventIndex, 5);
      engine.dispose();
    });

    testWidgets('seekToIndex — backward navigation (small)', (tester) async {
      final engine = TimeTravelPlaybackEngine(storage: fakeStorage);
      _setupFakeSession(fakeStorage, eventCount: 10);

      await engine.initialize('canvas_1', tester);

      // Go to index 8
      await engine.seekToIndex(8);
      expect(engine.currentEventIndex, 8);

      // Go back 3 steps (within inverse threshold of 5)
      await engine.seekToIndex(5);
      expect(engine.currentEventIndex, 5);
      engine.dispose();
    });

    testWidgets('seekToIndex — backward navigation (large)', (tester) async {
      final engine = TimeTravelPlaybackEngine(storage: fakeStorage);
      _setupFakeSession(fakeStorage, eventCount: 20);

      await engine.initialize('canvas_1', tester);

      // Start at end (20)
      // Go back 10 steps (> threshold of 5 → snapshot reload)
      await engine.seekToIndex(10);
      expect(engine.currentEventIndex, 10);
      engine.dispose();
    });

    testWidgets('seekToProgress — clamps to valid range', (tester) async {
      final engine = TimeTravelPlaybackEngine(storage: fakeStorage);
      _setupFakeSession(fakeStorage, eventCount: 10);

      await engine.initialize('canvas_1', tester);

      await engine.seekToProgress(0.5);
      expect(engine.currentEventIndex, 5);

      await engine.seekToProgress(0.0);
      expect(engine.currentEventIndex, 0);

      await engine.seekToProgress(1.0);
      expect(engine.currentEventIndex, 10);
      engine.dispose();
    });

    testWidgets('play and pause change state', (tester) async {
      final engine = TimeTravelPlaybackEngine(storage: fakeStorage);
      _setupFakeSession(fakeStorage, eventCount: 10);

      await engine.initialize('canvas_1', tester);
      expect(engine.state, TimeTravelPlaybackState.paused);

      // Seek to start first, then play
      await engine.seekToIndex(0);
      engine.play();
      expect(engine.state, TimeTravelPlaybackState.playing);

      await tester.pump(); // Flush ticker callback
      engine.pause();
      expect(engine.state, TimeTravelPlaybackState.paused);
      engine.dispose();
    });

    testWidgets('play from end restarts at beginning', (tester) async {
      final engine = TimeTravelPlaybackEngine(storage: fakeStorage);
      _setupFakeSession(fakeStorage, eventCount: 10);

      await engine.initialize('canvas_1', tester);
      expect(engine.currentEventIndex, 10); // At end

      // Manually seek to 0 (the engine's play() does this internally
      // but without awaiting the async seekToIndex call)
      await engine.seekToIndex(0);
      expect(engine.currentEventIndex, 0);

      engine.play();
      expect(engine.state, TimeTravelPlaybackState.playing);

      await tester.pump(); // Flush ticker callback
      engine.pause();
      engine.dispose();
    });

    testWidgets('progress returns correct fraction', (tester) async {
      final engine = TimeTravelPlaybackEngine(storage: fakeStorage);
      _setupFakeSession(fakeStorage, eventCount: 10);

      await engine.initialize('canvas_1', tester);

      await engine.seekToIndex(5);
      expect(engine.progress, closeTo(0.5, 0.01));

      await engine.seekToIndex(0);
      expect(engine.progress, 0.0);

      await engine.seekToIndex(10);
      expect(engine.progress, 1.0);
      engine.dispose();
    });

    testWidgets('playbackSpeed clamps to range', (tester) async {
      final engine = TimeTravelPlaybackEngine(storage: fakeStorage);
      _setupFakeSession(fakeStorage, eventCount: 10);

      await engine.initialize('canvas_1', tester);

      engine.playbackSpeed = 4.0;
      expect(engine.playbackSpeed, 4.0);

      engine.playbackSpeed = 0.1;
      expect(engine.playbackSpeed, 0.5); // Clamped

      engine.playbackSpeed = 20.0;
      expect(engine.playbackSpeed, 8.0); // Clamped
      engine.dispose();
    });

    testWidgets('onStateChanged fires during seek', (tester) async {
      final engine = TimeTravelPlaybackEngine(storage: fakeStorage);
      _setupFakeSession(fakeStorage, eventCount: 10);

      await engine.initialize('canvas_1', tester);

      int callCount = 0;
      engine.onStateChanged = () => callCount++;

      await engine.seekToIndex(5);
      expect(callCount, 1);

      await engine.seekToIndex(3);
      expect(callCount, 2);
      engine.dispose();
    });

    testWidgets('dispose cleans up state', (tester) async {
      final engine = TimeTravelPlaybackEngine(storage: fakeStorage);
      _setupFakeSession(fakeStorage, eventCount: 10);

      await engine.initialize('canvas_1', tester);
      engine.dispose();

      expect(engine.state, TimeTravelPlaybackState.idle);
      expect(engine.totalEventCount, 0);
      expect(engine.sessions, isEmpty);
    });

    testWidgets('skipToNextSession navigates correctly', (tester) async {
      final engine = TimeTravelPlaybackEngine(storage: fakeStorage);

      // Set up 2 sessions with 5 events each
      fakeStorage.sessionIndex = [
        TimeTravelSession(
          id: 'sess_1',
          canvasId: 'canvas_1',
          startTime: DateTime(2025, 1, 1),
          endTime: DateTime(2025, 1, 1, 0, 5),
          deltaCount: 5,
          deltaFilePath: 'sess_1.tt.jsonl.gz',
        ),
        TimeTravelSession(
          id: 'sess_2',
          canvasId: 'canvas_1',
          startTime: DateTime(2025, 1, 2),
          endTime: DateTime(2025, 1, 2, 0, 5),
          deltaCount: 5,
          deltaFilePath: 'sess_2.tt.jsonl.gz',
        ),
      ];
      for (final s in fakeStorage.sessionIndex) {
        fakeStorage.sessionEventsMap[s.id] = List.generate(
          5,
          (i) => TimeTravelEvent(
            type: CanvasDeltaType.strokeAdded,
            layerId: 'layer_1',
            timestampMs: i * 100,
            elementId: 'stroke_${s.id}_$i',
          ),
        );
      }

      await engine.initialize('canvas_1', tester);
      await engine.seekToIndex(0); // Start at beginning

      engine.skipToNextSession();
      expect(engine.currentEventIndex, 5); // Start of session 2

      engine.skipToNextSession();
      expect(engine.currentEventIndex, 10); // End
      engine.dispose();
    });

    testWidgets('initialize with empty events returns false', (tester) async {
      final engine = TimeTravelPlaybackEngine(storage: fakeStorage);

      // Session exists but has no events
      fakeStorage.sessionIndex = [
        TimeTravelSession(
          id: 'sess_empty',
          canvasId: 'canvas_1',
          startTime: DateTime(2025, 1, 1),
          endTime: DateTime(2025, 1, 1, 0, 1),
          deltaCount: 0,
          deltaFilePath: 'sess_empty.tt.jsonl.gz',
        ),
      ];
      fakeStorage.sessionEventsMap['sess_empty'] = [];

      final result = await engine.initialize('canvas_1', tester);
      expect(result, isFalse);
      engine.dispose();
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// FAKES
// ═══════════════════════════════════════════════════════════════════════════════

/// Helper: set up a single session with N events.
void _setupFakeSession(
  _FakeTimeTravelStorage storage, {
  required int eventCount,
}) {
  storage.sessionIndex = [
    TimeTravelSession(
      id: 'sess_1',
      canvasId: 'canvas_1',
      startTime: DateTime(2025, 1, 1),
      endTime: DateTime(2025, 1, 1, 0, 10),
      deltaCount: eventCount,
      deltaFilePath: 'sess_1.tt.jsonl.gz',
    ),
  ];
  storage.sessionEventsMap['sess_1'] = List.generate(
    eventCount,
    (i) => TimeTravelEvent(
      type: CanvasDeltaType.strokeAdded,
      layerId: 'layer_1',
      timestampMs: i * 100,
      elementId: 'stroke_$i',
    ),
  );
  // Provide a snapshot at session-index 1 (after the session).
  // This tells the engine that events from sessions [0..1) are already
  // accounted for, so `startIndex = 10` → no forward replay needed.
  storage.snapshotMap[0] = (<CanvasLayer>[], 1);
}

/// In-memory fake storage for testing the PlaybackEngine.
class _FakeTimeTravelStorage implements NebulaTimeTravelStorage {
  List<TimeTravelSession> sessionIndex = [];
  Map<String, List<TimeTravelEvent>> sessionEventsMap = {};
  Map<int, (List<CanvasLayer>, int)> snapshotMap = {};

  @override
  Future<List<TimeTravelSession>> loadSessionIndex(
    String canvasId, {
    String? branchId,
  }) async => sessionIndex;

  @override
  Future<List<TimeTravelEvent>> loadSessionEvents(
    TimeTravelSession session, {
    String? branchId,
  }) async => sessionEventsMap[session.id] ?? [];

  @override
  Future<(List<CanvasLayer>, int)?> loadNearestSnapshot(
    String canvasId,
    int targetSessionIndex, {
    String? branchId,
  }) async => snapshotMap[targetSessionIndex];

  @override
  Future<String> getTimeTravelPathForCanvas(String canvasId) async =>
      '/tmp/test_tt/$canvasId';
}
