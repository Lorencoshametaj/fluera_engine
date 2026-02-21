import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/time_travel/models/synchronized_recording.dart';
import 'package:nebula_engine/src/drawing/models/pro_drawing_point.dart';

/// Helper: create a test stroke with N points.
ProStroke _testStroke(String id, {int pointCount = 5}) {
  final points = List.generate(
    pointCount,
    (i) => ProDrawingPoint(
      position: Offset(100.0 + i * 2.0, 200.0 + i * 1.0),
      pressure: 0.5,
      timestamp: 1000 + i * 16,
    ),
  );
  return ProStroke(
    id: id,
    points: points,
    color: const Color(0xFF000000),
    baseWidth: 2.0,
    penType: ProPenType.ballpoint,
    createdAt: DateTime(2025, 1, 1),
  );
}

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // SYNCED STROKE
  // ═══════════════════════════════════════════════════════════════════════════

  group('SyncedStroke', () {
    late SyncedStroke synced;

    setUp(() {
      synced = SyncedStroke(
        stroke: _testStroke('s1', pointCount: 10),
        relativeStartMs: 1000,
        relativeEndMs: 2000,
      );
    });

    test('durationMs is correct', () {
      expect(synced.durationMs, 1000);
    });

    test('visiblePointsAtTime — before start', () {
      expect(synced.visiblePointsAtTime(500), 0);
    });

    test('visiblePointsAtTime — at start', () {
      expect(synced.visiblePointsAtTime(1000), 0);
    });

    test('visiblePointsAtTime — midway', () {
      // 50% through → should show ~5 of 10 points
      final points = synced.visiblePointsAtTime(1500);
      expect(points, greaterThanOrEqualTo(4));
      expect(points, lessThanOrEqualTo(6));
    });

    test('visiblePointsAtTime — at end', () {
      expect(synced.visiblePointsAtTime(2000), 10);
    });

    test('visiblePointsAtTime — after end', () {
      expect(synced.visiblePointsAtTime(5000), 10);
    });

    test('getPartialStroke — returns null before start', () {
      expect(synced.getPartialStroke(500), isNull);
    });

    test('getPartialStroke — returns full stroke after end', () {
      final partial = synced.getPartialStroke(3000);
      expect(partial, isNotNull);
      expect(partial!.points.length, 10);
    });

    test('getPartialStroke — returns subset midway', () {
      final partial = synced.getPartialStroke(1500);
      expect(partial, isNotNull);
      expect(partial!.points.length, greaterThan(0));
      expect(partial.points.length, lessThan(10));
    });

    test('isFullyVisible', () {
      expect(synced.isFullyVisible(500), isFalse);
      expect(synced.isFullyVisible(1999), isFalse);
      expect(synced.isFullyVisible(2000), isTrue);
      expect(synced.isFullyVisible(3000), isTrue);
    });

    test('isStarted', () {
      expect(synced.isStarted(500), isFalse);
      expect(synced.isStarted(1000), isTrue);
      expect(synced.isStarted(1500), isTrue);
    });

    test('JSON round-trip', () {
      final json = synced.toJson();
      final restored = SyncedStroke.fromJson(json);
      expect(restored.relativeStartMs, 1000);
      expect(restored.relativeEndMs, 2000);
      expect(restored.pageIndex, 0);
      expect(restored.stroke.id, 's1');
    });

    test('pageIndex is preserved', () {
      final paged = SyncedStroke(
        stroke: _testStroke('s2'),
        relativeStartMs: 0,
        relativeEndMs: 100,
        pageIndex: 3,
      );
      final json = paged.toJson();
      final restored = SyncedStroke.fromJson(json);
      expect(restored.pageIndex, 3);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SYNCHRONIZED RECORDING
  // ═══════════════════════════════════════════════════════════════════════════

  group('SynchronizedRecording', () {
    late SynchronizedRecording recording;

    setUp(() {
      recording = SynchronizedRecording(
        id: 'rec_1',
        audioPath: '/audio/test.m4a',
        totalDuration: const Duration(seconds: 10),
        startTime: DateTime(2025, 6, 15, 10, 0),
        syncedStrokes: [
          SyncedStroke(
            stroke: _testStroke('s1'),
            relativeStartMs: 0,
            relativeEndMs: 2000,
          ),
          SyncedStroke(
            stroke: _testStroke('s2'),
            relativeStartMs: 3000,
            relativeEndMs: 5000,
          ),
          SyncedStroke(
            stroke: _testStroke('s3'),
            relativeStartMs: 7000,
            relativeEndMs: 9000,
          ),
        ],
      );
    });

    test('strokeCount and hasStrokes', () {
      expect(recording.strokeCount, 3);
      expect(recording.hasStrokes, isTrue);
    });

    test('getVisibleStrokesAtTime — none visible', () {
      // Before first stroke starts (t < 0 effectively)
      // Actually at t=0 the first stroke's start is 0 so visiblePoints would be 0
      // and getPartialStroke returns null
      // Let's test before that
      final visible = SynchronizedRecording(
        id: 'r',
        audioPath: '/a',
        totalDuration: const Duration(seconds: 5),
        startTime: DateTime(2025),
        syncedStrokes: [
          SyncedStroke(
            stroke: _testStroke('s1'),
            relativeStartMs: 1000,
            relativeEndMs: 2000,
          ),
        ],
      ).getVisibleStrokesAtTime(500);
      expect(visible, isEmpty);
    });

    test('getVisibleStrokesAtTime — partial strokes', () {
      // At 1000ms: s1 is at start (0 visible points, returns null)
      // At 1500ms: s1 midway
      final visible = recording.getVisibleStrokesAtTime(1000);
      expect(visible, hasLength(1)); // s1 mid-stroke
    });

    test('getVisibleStrokesAtTime — all visible at end', () {
      final visible = recording.getVisibleStrokesAtTime(10000);
      expect(visible, hasLength(3));
    });

    test('getGhostStrokesAtTime — future strokes as ghosts', () {
      // At t=0, s2 and s3 haven't started
      final ghosts = recording.getGhostStrokesAtTime(0);
      expect(ghosts, hasLength(2)); // s2, s3 not started (s1 started at 0)
    });

    test('getGhostStrokesAtTime — no ghosts after all started', () {
      final ghosts = recording.getGhostStrokesAtTime(8000);
      expect(ghosts, isEmpty); // All 3 have started
    });

    test('JSON round-trip', () {
      final json = recording.toJson();
      final restored = SynchronizedRecording.fromJson(json);

      expect(restored.id, 'rec_1');
      expect(restored.audioPath, '/audio/test.m4a');
      expect(restored.totalDuration.inSeconds, 10);
      expect(restored.syncedStrokes, hasLength(3));
      expect(restored.syncedStrokes[0].relativeStartMs, 0);
      expect(restored.syncedStrokes[2].relativeEndMs, 9000);
    });

    test('JSON string round-trip', () {
      final str = recording.toJsonString();
      final restored = SynchronizedRecording.fromJsonString(str);
      expect(restored.id, 'rec_1');
      expect(restored.syncedStrokes, hasLength(3));
    });

    test('copyWith preserves and updates', () {
      final updated = recording.copyWith(
        noteTitle: 'Test Note',
        canvasId: 'canvas_1',
      );
      expect(updated.noteTitle, 'Test Note');
      expect(updated.canvasId, 'canvas_1');
      expect(updated.id, 'rec_1'); // Unchanged
    });

    test('empty factory creates no-stroke recording', () {
      final empty = SynchronizedRecording.empty(
        id: 'empty_1',
        audioPath: '/audio/empty.m4a',
        startTime: DateTime(2025),
      );
      expect(empty.syncedStrokes, isEmpty);
      expect(empty.totalDuration, Duration.zero);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SYNCHRONIZED RECORDING BUILDER
  // ═══════════════════════════════════════════════════════════════════════════

  group('SynchronizedRecordingBuilder', () {
    late SynchronizedRecordingBuilder builder;
    final startTime = DateTime(2025, 6, 15, 10, 0);

    setUp(() {
      builder = SynchronizedRecordingBuilder(
        id: 'rec_builder_1',
        audioPath: '/audio/test.m4a',
        startTime: startTime,
      );
    });

    test('starts empty', () {
      expect(builder.strokeCount, 0);
      expect(builder.hasStrokes, isFalse);
    });

    test('addStroke records relative timestamps', () {
      final stroke = _testStroke('s1');
      builder.addStroke(
        stroke,
        startTime.add(const Duration(seconds: 1)),
        startTime.add(const Duration(seconds: 3)),
      );

      expect(builder.strokeCount, 1);
      expect(builder.hasStrokes, isTrue);

      final recording = builder.build(const Duration(seconds: 10));
      expect(recording.syncedStrokes[0].relativeStartMs, 1000);
      expect(recording.syncedStrokes[0].relativeEndMs, 3000);
    });

    test('addStroke with page index', () {
      builder.addStroke(
        _testStroke('s1'),
        startTime,
        startTime.add(const Duration(seconds: 1)),
        pageIndex: 2,
      );

      final recording = builder.build(const Duration(seconds: 5));
      expect(recording.syncedStrokes[0].pageIndex, 2);
    });

    test('build produces immutable stroke list', () {
      builder.addStroke(
        _testStroke('s1'),
        startTime,
        startTime.add(const Duration(seconds: 1)),
      );

      final recording = builder.build(const Duration(seconds: 5));
      expect(
        () => recording.syncedStrokes.add(
          SyncedStroke(
            stroke: _testStroke('s2'),
            relativeStartMs: 0,
            relativeEndMs: 100,
          ),
        ),
        throwsA(anything),
      );
    });

    test('removeStrokeById removes correct stroke', () {
      builder.addStroke(
        _testStroke('s1'),
        startTime,
        startTime.add(const Duration(seconds: 1)),
      );
      builder.addStroke(
        _testStroke('s2'),
        startTime.add(const Duration(seconds: 2)),
        startTime.add(const Duration(seconds: 3)),
      );

      expect(builder.strokeCount, 2);

      final removed = builder.removeStrokeById('s1');
      expect(removed, isTrue);
      expect(builder.strokeCount, 1);

      // Remaining stroke should be s2
      final recording = builder.build(const Duration(seconds: 5));
      expect(recording.syncedStrokes[0].stroke.id, 's2');
    });

    test('removeStrokeById returns false for nonexistent', () {
      final removed = builder.removeStrokeById('nonexistent');
      expect(removed, isFalse);
    });

    test('setRecordingType — initial set', () {
      builder.setRecordingType('note');
      final recording = builder.build(const Duration(seconds: 5));
      expect(recording.recordingType, 'note');
    });

    test('setRecordingType — becomes mixed on conflict', () {
      builder.addStroke(
        _testStroke('s1'),
        startTime,
        startTime.add(const Duration(seconds: 1)),
      );

      builder.setRecordingType('note');
      builder.setRecordingType('voice'); // Conflict → mixed
      final recording = builder.build(const Duration(seconds: 5));
      expect(recording.recordingType, 'mixed');
    });

    test('reset clears strokes', () {
      builder.addStroke(
        _testStroke('s1'),
        startTime,
        startTime.add(const Duration(seconds: 1)),
      );

      builder.reset();
      expect(builder.strokeCount, 0);
    });
  });
}
