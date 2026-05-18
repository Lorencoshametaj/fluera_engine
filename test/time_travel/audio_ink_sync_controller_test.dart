// ============================================================================
// 🎤 AUDIO INK SYNC CONTROLLER TESTS
//
// Unit tests for the V1 Pro pillar "tap a stroke, hear what you said".
// Covers: bind/unbind lifecycle, hit-test radius math, highlight decay,
// seek-to-stroke happy path + unknown id, dispose safety.
//
// Native audio is NOT exercised here — SynchronizedPlaybackController's
// audio_player swallows initialization on test platforms, so seekToStroke
// will fail silently on the native seek. The test verifies the controller-
// observable side-effects (highlight state) which is what the canvas
// painter actually reads.
// ============================================================================
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/drawing/models/pro_drawing_point.dart';
import 'package:fluera_engine/src/time_travel/controllers/audio_ink_sync_controller.dart';
import 'package:fluera_engine/src/time_travel/controllers/synchronized_playback_controller.dart';
import 'package:fluera_engine/src/time_travel/models/synchronized_recording.dart';

/// Mute the native audio player channel so SynchronizedPlaybackController.
/// dispose() (which calls `release` via MethodChannel) returns silently
/// instead of throwing MissingPluginException in an async gap after the
/// test completes.
void _installPlayerChannelMock() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('flueraengine.audio/player'),
    (call) async => null,
  );
}

ProStroke _stroke(String id, {Offset start = const Offset(100, 100), int n = 5}) {
  return ProStroke(
    id: id,
    points: List.generate(
      n,
      (i) => ProDrawingPoint(
        position: Offset(start.dx + i * 5.0, start.dy + i * 5.0),
        pressure: 0.5,
        timestamp: 1000 + i * 16,
      ),
    ),
    color: const Color(0xFF000000),
    baseWidth: 2.0,
    penType: ProPenType.ballpoint,
    createdAt: DateTime(2025, 1, 1),
  );
}

SynchronizedRecording _recording({
  required String id,
  required List<SyncedStroke> strokes,
}) {
  return SynchronizedRecording(
    id: id,
    audioPath: '/tmp/test_$id.m4a',
    totalDuration: const Duration(seconds: 10),
    startTime: DateTime(2025, 1, 1),
    syncedStrokes: strokes,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SynchronizedPlaybackController playback;
  late AudioInkSyncController controller;
  bool controllerDisposed = false;

  setUp(() {
    _installPlayerChannelMock();
    playback = SynchronizedPlaybackController();
    controller = AudioInkSyncController(playbackController: playback);
    controllerDisposed = false;
  });

  tearDown(() {
    if (!controllerDisposed) {
      controller.dispose();
      controllerDisposed = true;
    }
    // NativeAudioPlayer.dispose hits the platform channel which throws
    // MissingPluginException on the test VM. Swallow it — the test process
    // tears down immediately after so the leak is bounded.
    try {
      playback.dispose();
    } catch (_) {}
  });

  group('AudioInkSyncController — bind/unbind', () {
    test('isAvailable is false before bind', () {
      expect(controller.isAvailable, isFalse);
    });

    test('isAvailable is true after bindRecording', () {
      final rec = _recording(id: 'r1', strokes: []);
      controller.bindRecording(rec);
      expect(controller.isAvailable, isTrue);
    });

    test('unbindRecording clears state', () {
      final rec = _recording(id: 'r1', strokes: []);
      controller.bindRecording(rec);
      controller.unbindRecording();
      expect(controller.isAvailable, isFalse);
      expect(controller.highlightedStrokeId, isNull);
    });

    test('bindRecording notifies listeners', () {
      int notifications = 0;
      controller.addListener(() => notifications++);
      controller.bindRecording(_recording(id: 'r1', strokes: []));
      expect(notifications, 1);
    });
  });

  group('AudioInkSyncController — hitTestStroke', () {
    test('returns null when no recording bound', () {
      final hit = controller.hitTestStroke(const Offset(100, 100), [_stroke('a')]);
      expect(hit, isNull);
    });

    test('returns null when point is far from any stroke', () {
      final s = _stroke('a', start: const Offset(100, 100));
      controller.bindRecording(_recording(
        id: 'r1',
        strokes: [SyncedStroke(stroke: s, relativeStartMs: 0, relativeEndMs: 100)],
      ));
      final hit = controller.hitTestStroke(const Offset(500, 500), [s]);
      expect(hit, isNull);
    });

    test('returns stroke id when point is on a recorded stroke', () {
      final s = _stroke('target', start: const Offset(200, 200));
      controller.bindRecording(_recording(
        id: 'r1',
        strokes: [SyncedStroke(stroke: s, relativeStartMs: 0, relativeEndMs: 100)],
      ));
      // Stroke starts at (200,200), first point is (200,200) — exact hit
      final hit = controller.hitTestStroke(const Offset(200, 200), [s]);
      expect(hit, 'target');
    });

    test('skips strokes NOT in the recording', () {
      final inRec = _stroke('in', start: const Offset(100, 100));
      final notInRec = _stroke('out', start: const Offset(105, 105));
      controller.bindRecording(_recording(
        id: 'r1',
        strokes: [
          SyncedStroke(stroke: inRec, relativeStartMs: 0, relativeEndMs: 100),
        ],
      ));
      // Both strokes are nearby (100,100); only 'in' is recorded → 'in' wins.
      final hit = controller.hitTestStroke(
        const Offset(102, 102),
        [inRec, notInRec],
      );
      expect(hit, 'in');
    });

    test('hitRadius parameter constrains the match', () {
      final s = _stroke('target', start: const Offset(100, 100));
      controller.bindRecording(_recording(
        id: 'r1',
        strokes: [SyncedStroke(stroke: s, relativeStartMs: 0, relativeEndMs: 100)],
      ));
      // Far from stroke (50 units away) but inside default radius=15 → null
      expect(
        controller.hitTestStroke(const Offset(150, 100), [s]),
        isNull,
      );
      // Same point with larger radius → hits
      expect(
        controller.hitTestStroke(const Offset(150, 100), [s], hitRadius: 80),
        'target',
      );
    });
  });

  group('AudioInkSyncController — getStrokeHighlight decay', () {
    test('returns 0.0 when nothing is highlighted', () {
      expect(controller.getStrokeHighlight('anything'), 0.0);
    });

    test('returns 0.0 for non-highlighted stroke id', () async {
      final s = _stroke('a');
      controller.bindRecording(_recording(
        id: 'r1',
        strokes: [SyncedStroke(stroke: s, relativeStartMs: 100, relativeEndMs: 200)],
      ));
      // Trigger highlight on 'a' — seek will fail on native, but the highlight
      // state is set before that call so we can still observe it.
      // We forcibly set internal state via seekToStroke (it sets the flag
      // even when audio seek fails, since flag-set is before await seek).
      await controller.seekToStroke('a');
      expect(controller.getStrokeHighlight('b'), 0.0);
    });

    test('highlight intensity is in [0, 1] right after seek', () async {
      final s = _stroke('a');
      controller.bindRecording(_recording(
        id: 'r1',
        strokes: [SyncedStroke(stroke: s, relativeStartMs: 100, relativeEndMs: 200)],
      ));
      await controller.seekToStroke('a');
      final v = controller.getStrokeHighlight('a');
      expect(v, lessThanOrEqualTo(1.0));
      expect(v, greaterThan(0.0));
    });

    test('hasActiveHighlight flips true on seek, false on unbind', () async {
      final s = _stroke('a');
      controller.bindRecording(_recording(
        id: 'r1',
        strokes: [SyncedStroke(stroke: s, relativeStartMs: 100, relativeEndMs: 200)],
      ));
      expect(controller.hasActiveHighlight, isFalse);
      await controller.seekToStroke('a');
      expect(controller.hasActiveHighlight, isTrue);
      controller.unbindRecording();
      expect(controller.hasActiveHighlight, isFalse);
    });
  });

  group('AudioInkSyncController — seekToStroke', () {
    test('returns false when no recording is bound', () async {
      final ok = await controller.seekToStroke('any');
      expect(ok, isFalse);
    });

    test('returns false when stroke id is not in the recording', () async {
      final s = _stroke('a');
      controller.bindRecording(_recording(
        id: 'r1',
        strokes: [SyncedStroke(stroke: s, relativeStartMs: 0, relativeEndMs: 100)],
      ));
      final ok = await controller.seekToStroke('unknown');
      expect(ok, isFalse);
      expect(controller.highlightedStrokeId, isNull);
    });

    test('seekToStroke updates highlightedStrokeId on success', () async {
      final s = _stroke('a');
      controller.bindRecording(_recording(
        id: 'r1',
        strokes: [SyncedStroke(stroke: s, relativeStartMs: 500, relativeEndMs: 1500)],
      ));
      await controller.seekToStroke('a');
      expect(controller.highlightedStrokeId, 'a');
    });
  });

  group('AudioInkSyncController — dispose safety', () {
    test('dispose nulls active recording', () {
      controller.bindRecording(_recording(id: 'r1', strokes: []));
      controller.dispose();
      controllerDisposed = true;
      // After dispose isAvailable must be false — recording is cleared.
      expect(controller.isAvailable, isFalse);
    });
  });

  group('AudioInkSyncController — debug print smoke', () {
    test('seek to unknown stroke logs but does not throw', () async {
      debugPrint = (_, {wrapWidth}) {}; // silence
      controller.bindRecording(_recording(id: 'r1', strokes: []));
      final ok = await controller.seekToStroke('ghost');
      expect(ok, isFalse);
    });
  });
}
