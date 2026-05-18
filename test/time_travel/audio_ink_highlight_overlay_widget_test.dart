// ============================================================================
// 🎤✨ AUDIO INK HIGHLIGHT OVERLAY — widget tests
//
// Verifies that the overlay:
//  • Renders nothing when no recording is bound (early-return SizedBox.shrink).
//  • Renders nothing when bound but no stroke is highlighted.
//  • Renders an IgnorePointer + CustomPaint when a stroke is highlighted.
//  • Cleans up its Ticker on dispose (no leak warning).
//
// We exercise via the public `AudioInkSyncController.seekToStroke` API which
// is the same path the canvas uses in production.
// ============================================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/drawing/models/pro_drawing_point.dart';
import 'package:fluera_engine/src/time_travel/controllers/audio_ink_sync_controller.dart';
import 'package:fluera_engine/src/time_travel/controllers/synchronized_playback_controller.dart';
import 'package:fluera_engine/src/time_travel/models/synchronized_recording.dart';
import 'package:fluera_engine/src/time_travel/widgets/audio_ink_highlight_overlay.dart';

void _installPlayerChannelMock() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('flueraengine.audio/player'),
    (call) async => null,
  );
}

ProStroke _stroke(String id) {
  return ProStroke(
    id: id,
    points: List.generate(
      5,
      (i) => ProDrawingPoint(
        position: Offset(100.0 + i * 5.0, 200.0 + i * 3.0),
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

SynchronizedRecording _recording(List<SyncedStroke> strokes) =>
    SynchronizedRecording(
      id: 'rec1',
      audioPath: '/tmp/rec1.m4a',
      totalDuration: const Duration(seconds: 10),
      startTime: DateTime(2025, 1, 1),
      syncedStrokes: strokes,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SynchronizedPlaybackController playback;
  late AudioInkSyncController controller;

  setUp(() {
    _installPlayerChannelMock();
    playback = SynchronizedPlaybackController();
    controller = AudioInkSyncController(playbackController: playback);
  });

  tearDown(() {
    controller.dispose();
    try {
      playback.dispose();
    } catch (_) {}
  });

  /// Bare host — no MaterialApp/Scaffold so test finders don't compete with
  /// framework-internal CustomPaint/IgnorePointer widgets.
  Widget _host(List<ProStroke> strokes) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(size: Size(400, 400)),
        child: SizedBox(
          width: 400,
          height: 400,
          child: AudioInkHighlightOverlay(
            controller: controller,
            strokesProvider: () => strokes,
          ),
        ),
      ),
    );
  }

  testWidgets('renders nothing when no recording bound', (tester) async {
    await tester.pumpWidget(_host([_stroke('a')]));
    // Overlay returns SizedBox.shrink → no CustomPaint subtree mounted.
    expect(find.byType(CustomPaint), findsNothing);
    expect(find.byType(IgnorePointer), findsNothing);
  });

  testWidgets('renders nothing when bound but no stroke highlighted',
      (tester) async {
    final s = _stroke('a');
    controller.bindRecording(_recording([
      SyncedStroke(stroke: s, relativeStartMs: 0, relativeEndMs: 100),
    ]));
    await tester.pumpWidget(_host([s]));
    expect(find.byType(IgnorePointer), findsNothing);
  });

  testWidgets('paints CustomPaint when a stroke is highlighted',
      (tester) async {
    final s = _stroke('a');
    controller.bindRecording(_recording([
      SyncedStroke(stroke: s, relativeStartMs: 100, relativeEndMs: 500),
    ]));
    await tester.pumpWidget(_host([s]));

    // Trigger highlight via the public seek API.
    await controller.seekToStroke('a');
    await tester.pump();
    // Wrap CustomPaint + IgnorePointer should both be present.
    expect(find.byType(IgnorePointer), findsOneWidget);
    expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
  });

  testWidgets('overlay reverts to empty after highlight decays',
      (tester) async {
    final s = _stroke('a');
    controller.bindRecording(_recording([
      SyncedStroke(stroke: s, relativeStartMs: 100, relativeEndMs: 500),
    ]));
    await tester.pumpWidget(_host([s]));
    await controller.seekToStroke('a');
    await tester.pump();
    expect(controller.hasActiveHighlight, isTrue);

    // Simulate the 2-second highlight expiry. The decay logic reads
    // wall-clock millisecondsSinceEpoch so we can't fake it cheaply —
    // instead unbind to force getStrokeHighlight to return 0.
    controller.unbindRecording();
    await tester.pump();
    expect(controller.hasActiveHighlight, isFalse);
  });

  testWidgets('disposing the host stops the internal Ticker cleanly',
      (tester) async {
    final s = _stroke('a');
    controller.bindRecording(_recording([
      SyncedStroke(stroke: s, relativeStartMs: 100, relativeEndMs: 500),
    ]));
    await tester.pumpWidget(_host([s]));
    await controller.seekToStroke('a');
    await tester.pump();
    // Unmount — if the Ticker leaks, flutter_test surfaces a 'Tickers were
    // active when the test ended' failure here.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('overlay tolerates strokesProvider returning a missing id',
      (tester) async {
    final s = _stroke('a');
    controller.bindRecording(_recording([
      SyncedStroke(stroke: s, relativeStartMs: 100, relativeEndMs: 500),
    ]));
    // Provider returns NO strokes at all → painter must still mount but
    // skip drawing (no crash).
    await tester.pumpWidget(_host(const []));
    await controller.seekToStroke('a');
    await tester.pump();
    // Painter is mounted (highlight is active) but paints nothing visible.
    expect(find.byType(IgnorePointer), findsOneWidget);
  });
}
