import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/collaboration/fluera_realtime_adapter.dart';
import 'package:fluera_engine/src/collaboration/widgets/sync_status_indicator.dart';

// =============================================================================
// 📡 SyncStatusIndicator — pill label transitions
//
// Drives the indicator through every state matrix combination it can render:
//
//   connection × queued      → expected label
//   ─────────────────────────────────────────
//   connected · 0            → "Live"
//   connected · 0 + N online → "Live · N online"
//   connected · K (queued)   → "Syncing · K"
//   connecting               → "Reconnecting…"
//   reconnecting · K         → "Reconnecting · K queued"
//   disconnected · 0         → "Offline"
//   disconnected · K         → "Offline · K queued"
//   error                    → "Sync error"
// =============================================================================

class _StubAdapter implements FlueraRealtimeAdapter {
  final _events = StreamController<CanvasRealtimeEvent>.broadcast();
  final _cursors =
      StreamController<Map<String, CursorPresenceData>>.broadcast();

  @override
  Stream<CanvasRealtimeEvent> subscribe(String canvasId) => _events.stream;

  @override
  Future<void> broadcast(String canvasId, CanvasRealtimeEvent event) async {}

  @override
  Future<void> disconnect(String canvasId) async {}

  @override
  Stream<Map<String, CursorPresenceData>> cursorStream(String canvasId) =>
      _cursors.stream;

  @override
  Future<void> broadcastCursor(
    String canvasId,
    CursorPresenceData cursor,
  ) async {}

  void close() {
    _events.close();
    _cursors.close();
  }
}

void main() {
  late FlueraRealtimeEngine engine;
  late _StubAdapter adapter;
  late ValueNotifier<int> pending;

  setUp(() {
    adapter = _StubAdapter();
    engine = FlueraRealtimeEngine(
      adapter: adapter,
      localUserId: 'local',
    );
    pending = ValueNotifier<int>(0);
  });

  tearDown(() {
    pending.dispose();
    engine.dispose();
    adapter.close();
  });

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SyncStatusIndicator(engine: engine, pendingOps: pending),
        ),
      ),
    );
  }

  testWidgets('null engine renders nothing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SyncStatusIndicator(engine: null, pendingOps: pending),
        ),
      ),
    );
    expect(find.byType(SyncStatusIndicator), findsOneWidget);
    expect(find.text('Live'), findsNothing);
  });

  testWidgets('connected + no peers + empty outbox → Live', (tester) async {
    await mount(tester);
    engine.connectionState.value = RealtimeConnectionState.connected;
    await tester.pump();
    expect(find.text('Live'), findsOneWidget);
  });

  testWidgets('connected + 2 remote peers → "Live · 2 online"',
      (tester) async {
    await mount(tester);
    engine.connectionState.value = RealtimeConnectionState.connected;
    engine.remoteCursors.value = {
      'a': const {'n': 'Alice', 'x': 0.0, 'y': 0.0},
      'b': const {'n': 'Bob', 'x': 0.0, 'y': 0.0},
    };
    await tester.pump();
    expect(find.text('Live · 2 online'), findsOneWidget);
  });

  testWidgets('connected + outbox > 0 → Syncing · K', (tester) async {
    await mount(tester);
    engine.connectionState.value = RealtimeConnectionState.connected;
    pending.value = 7;
    await tester.pump();
    expect(find.text('Syncing · 7'), findsOneWidget);
  });

  testWidgets('reconnecting with no queue → Reconnecting…', (tester) async {
    await mount(tester);
    engine.connectionState.value = RealtimeConnectionState.reconnecting;
    await tester.pump();
    expect(find.text('Reconnecting…'), findsOneWidget);
  });

  testWidgets('reconnecting with queue → Reconnecting · K queued',
      (tester) async {
    await mount(tester);
    engine.connectionState.value = RealtimeConnectionState.reconnecting;
    pending.value = 3;
    await tester.pump();
    expect(find.text('Reconnecting · 3 queued'), findsOneWidget);
  });

  testWidgets('disconnected + queue → Offline · K queued', (tester) async {
    await mount(tester);
    engine.connectionState.value = RealtimeConnectionState.disconnected;
    pending.value = 12;
    await tester.pump();
    expect(find.text('Offline · 12 queued'), findsOneWidget);
  });

  testWidgets('disconnected + empty queue → Offline', (tester) async {
    await mount(tester);
    engine.connectionState.value = RealtimeConnectionState.disconnected;
    await tester.pump();
    expect(find.text('Offline'), findsOneWidget);
  });

  testWidgets('error state → Sync error', (tester) async {
    await mount(tester);
    engine.connectionState.value = RealtimeConnectionState.error;
    await tester.pump();
    expect(find.text('Sync error'), findsOneWidget);
  });
}
