import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/collaboration/fluera_realtime_adapter.dart';
import 'package:fluera_engine/src/collaboration/scene_graph_crdt.dart';

// =============================================================================
// Mock implementation
// =============================================================================

class MockRealtimeAdapter implements FlueraRealtimeAdapter {
  final _eventController = StreamController<CanvasRealtimeEvent>.broadcast();
  final _cursorController =
      StreamController<Map<String, CursorPresenceData>>.broadcast();

  final List<CanvasRealtimeEvent> broadcastedEvents = [];
  final List<CursorPresenceData> broadcastedCursors = [];
  int subscribeCallCount = 0;
  int disconnectCallCount = 0;

  @override
  Stream<CanvasRealtimeEvent> subscribe(String canvasId) {
    subscribeCallCount++;
    return _eventController.stream;
  }

  @override
  Future<void> broadcast(String canvasId, CanvasRealtimeEvent event) async {
    broadcastedEvents.add(event);
  }

  @override
  Future<void> disconnect(String canvasId) async {
    disconnectCallCount++;
  }

  @override
  Stream<Map<String, CursorPresenceData>> cursorStream(String canvasId) {
    return _cursorController.stream;
  }

  @override
  Future<void> broadcastCursor(
    String canvasId,
    CursorPresenceData cursor,
  ) async {
    broadcastedCursors.add(cursor);
  }

  /// Simulate a remote event arriving.
  void simulateRemoteEvent(CanvasRealtimeEvent event) {
    _eventController.add(event);
  }

  /// Simulate remote cursors arriving.
  void simulateRemoteCursors(Map<String, CursorPresenceData> cursors) {
    _cursorController.add(cursors);
  }

  void dispose() {
    _eventController.close();
    _cursorController.close();
  }
}

void main() {
  late MockRealtimeAdapter adapter;
  late FlueraRealtimeEngine engine;

  setUp(() {
    adapter = MockRealtimeAdapter();
    engine = FlueraRealtimeEngine(adapter: adapter, localUserId: 'user_local');
  });

  tearDown(() {
    engine.dispose();
    adapter.dispose();
  });

  group('FlueraRealtimeEngine — Connection lifecycle', () {
    test('connects and reaches connected state', () async {
      await engine.connect('canvas_1');

      expect(engine.connectionState.value, RealtimeConnectionState.connected);
      expect(adapter.subscribeCallCount, 1);
    });

    test('disconnect clears state and calls adapter', () async {
      await engine.connect('canvas_1');
      await engine.disconnect();

      expect(
        engine.connectionState.value,
        RealtimeConnectionState.disconnected,
      );
      expect(adapter.disconnectCallCount, 1);
      expect(engine.remoteCursors.value, isEmpty);
      expect(engine.lockedElements.value, isEmpty);
    });
  });

  // Stroke / image / text broadcasts no longer exist as discrete engine
  // methods — replaced by [broadcastCRDTOperation] and covered by the
  // "CRDT operation channel" group below.

  group('FlueraRealtimeEngine — Incoming event filtering', () {
    test('filters self-echoes by senderId', () async {
      await engine.connect('canvas_1');

      final received = <CanvasRealtimeEvent>[];
      engine.incomingEvents.listen(received.add);

      // Self event — should be filtered
      adapter.simulateRemoteEvent(
        CanvasRealtimeEvent(
          type: RealtimeEventType.strokeAdded,
          senderId: 'user_local',
          payload: {'id': 's1'},
          timestamp: 1,
        ),
      );
      await Future.delayed(const Duration(milliseconds: 50));
      expect(received, isEmpty);

      // Remote event — should pass through
      adapter.simulateRemoteEvent(
        CanvasRealtimeEvent(
          type: RealtimeEventType.strokeAdded,
          senderId: 'user_remote',
          payload: {'id': 's2'},
          timestamp: 2,
        ),
      );
      await Future.delayed(const Duration(milliseconds: 50));
      expect(received, hasLength(1));
      expect(received.first.senderId, 'user_remote');
    });
  });

  group('FlueraRealtimeEngine — CRDT operation channel', () {
    test('broadcastCRDTOperation produces a crdtOperation event', () async {
      await engine.connect('canvas_1');

      final crdt = CRDTSceneGraph(localPeerId: 'user_local');
      final op = crdt.addNode(nodeId: 'n1', nodeType: 'stroke');
      engine.broadcastCRDTOperation(op);

      // broadcastEvent is async — wait for the rate-limit/dispatch tick.
      await Future.delayed(const Duration(milliseconds: 10));

      expect(adapter.broadcastedEvents, hasLength(1));
      final wire = adapter.broadcastedEvents.single;
      expect(wire.type, RealtimeEventType.crdtOperation);
      expect(wire.senderId, 'user_local');
      expect(wire.elementId, 'n1');
      expect(wire.toCRDTOperation()?.opId, op.opId);
    });

    test('incomingCRDTOperations stream surfaces remote ops', () async {
      await engine.connect('canvas_1');

      final received = <CRDTOperation>[];
      engine.incomingCRDTOperations.listen(received.add);

      // The remote peer ships a CRDT op.
      final remoteCrdt = CRDTSceneGraph(localPeerId: 'user_remote');
      final remoteOp = remoteCrdt.addNode(
        nodeId: 'rn1',
        nodeType: 'stroke',
      );
      adapter.simulateRemoteEvent(
        CanvasRealtimeEvent.fromCRDTOperation(
          remoteOp,
          senderId: 'user_remote',
        ),
      );

      await Future.delayed(const Duration(milliseconds: 20));
      expect(received, hasLength(1));
      expect(received.single.opId, remoteOp.opId);
      expect(received.single.peerId, 'user_remote');
    });

    test(
        'crdtOperation events are NOT echoed on the legacy incomingEvents '
        'stream', () async {
      await engine.connect('canvas_1');

      final legacy = <CanvasRealtimeEvent>[];
      final crdtOps = <CRDTOperation>[];
      engine.incomingEvents.listen(legacy.add);
      engine.incomingCRDTOperations.listen(crdtOps.add);

      final remoteCrdt = CRDTSceneGraph(localPeerId: 'user_remote');
      adapter.simulateRemoteEvent(
        CanvasRealtimeEvent.fromCRDTOperation(
          remoteCrdt.addNode(nodeId: 'rn2', nodeType: 'stroke'),
          senderId: 'user_remote',
        ),
      );

      await Future.delayed(const Duration(milliseconds: 20));
      expect(crdtOps, hasLength(1));
      expect(legacy, isEmpty,
          reason:
              'crdtOperation must route exclusively to incomingCRDTOperations');
    });
  });

  group('FlueraRealtimeEngine — Element locking', () {
    test('lockElement succeeds for unowned element', () async {
      await engine.connect('canvas_1');

      final result = engine.lockElement('img_1');

      expect(result, isTrue);
      expect(engine.lockedElements.value['img_1'], 'user_local');
      // Should broadcast lock event
      await Future.delayed(const Duration(milliseconds: 50));
      expect(adapter.broadcastedEvents, hasLength(1));
      expect(
        adapter.broadcastedEvents.first.type,
        RealtimeEventType.elementLocked,
      );
    });

    test('lockElement fails if locked by another user', () async {
      await engine.connect('canvas_1');

      // Simulate remote lock
      adapter.simulateRemoteEvent(
        CanvasRealtimeEvent(
          type: RealtimeEventType.elementLocked,
          senderId: 'user_remote',
          elementId: 'img_1',
          payload: {'elementId': 'img_1', 'userId': 'user_remote'},
          timestamp: 1,
        ),
      );
      await Future.delayed(const Duration(milliseconds: 50));

      final result = engine.lockElement('img_1');
      expect(result, isFalse);
    });

    test('unlockElement clears lock and broadcasts', () async {
      await engine.connect('canvas_1');

      engine.lockElement('img_1');
      engine.unlockElement('img_1');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(engine.lockedElements.value, isEmpty);
      expect(adapter.broadcastedEvents, hasLength(2));
      expect(
        adapter.broadcastedEvents.last.type,
        RealtimeEventType.elementUnlocked,
      );
    });

    test('isLockedByOther returns correct state', () async {
      await engine.connect('canvas_1');

      // Not locked
      expect(engine.isLockedByOther('img_1'), isFalse);

      // Locked by self
      engine.lockElement('img_1');
      expect(engine.isLockedByOther('img_1'), isFalse);

      // Simulate remote lock on another element
      adapter.simulateRemoteEvent(
        CanvasRealtimeEvent(
          type: RealtimeEventType.elementLocked,
          senderId: 'user_other',
          elementId: 'img_2',
          payload: {'elementId': 'img_2', 'userId': 'user_other'},
          timestamp: 1,
        ),
      );
      await Future.delayed(const Duration(milliseconds: 50));

      expect(engine.isLockedByOther('img_2'), isTrue);
    });
  });

  group('FlueraRealtimeEngine — Cursor throttle', () {
    test('cursor updates are throttled at 50ms', () async {
      await engine.connect('canvas_1');

      // Send multiple rapid cursor updates
      for (var i = 0; i < 10; i++) {
        engine.updateCursor(
          CursorPresenceData(
            userId: 'user_local',
            displayName: 'Test',
            cursorColor: 0xFF000000,
            x: i.toDouble(),
            y: i.toDouble(),
          ),
        );
      }

      // After throttle period, should have dispatched ≤ 2 updates
      await Future.delayed(const Duration(milliseconds: 120));
      expect(adapter.broadcastedCursors.length, lessThanOrEqualTo(2));
    });
  });

  group('FlueraRealtimeEngine — Serialization', () {
    test('CanvasRealtimeEvent roundtrip JSON', () {
      final event = CanvasRealtimeEvent(
        type: RealtimeEventType.strokeAdded,
        senderId: 'user_1',
        elementId: 'stroke_1',
        payload: {
          'id': 'stroke_1',
          'points': [1, 2, 3],
        },
        timestamp: 123456,
      );

      final json = event.toJson();
      final restored = CanvasRealtimeEvent.fromJson(json);

      expect(restored.type, event.type);
      expect(restored.senderId, event.senderId);
      expect(restored.elementId, event.elementId);
      expect(restored.timestamp, event.timestamp);
      expect(restored.payload['id'], 'stroke_1');
    });

    test('CRDTOperation wraps into and unwraps from CanvasRealtimeEvent', () {
      final crdt = CRDTSceneGraph(localPeerId: 'peer_a');
      final op = crdt.addNode(
        nodeId: 'n1',
        nodeType: 'stroke',
        properties: {'color': '#abcdef'},
      );

      final event = CanvasRealtimeEvent.fromCRDTOperation(
        op,
        senderId: 'peer_a',
        timestamp: 12345,
      );

      expect(event.type, RealtimeEventType.crdtOperation);
      expect(event.senderId, 'peer_a');
      expect(event.elementId, 'n1');
      expect(event.timestamp, 12345);

      final unwrapped = event.toCRDTOperation();
      expect(unwrapped, isNotNull);
      expect(unwrapped!.opId, op.opId);
      expect(unwrapped.nodeId, 'n1');
      expect(unwrapped.type, CRDTOpType.addNode);
    });

    test('CRDTOperation survives transport JSON roundtrip', () {
      final crdt = CRDTSceneGraph(localPeerId: 'peer_a');
      final op = crdt.setProperty('n1', 'name', 'hello');
      final event = CanvasRealtimeEvent.fromCRDTOperation(
        op,
        senderId: 'peer_a',
      );

      final wireJson = event.toJson();
      final restored = CanvasRealtimeEvent.fromJson(wireJson);
      final restoredOp = restored.toCRDTOperation();

      expect(restoredOp, isNotNull);
      expect(restoredOp!.opId, op.opId);
      expect(restoredOp.payload['property'], 'name');
      expect(restoredOp.payload['value'], 'hello');
    });

    test('CursorPresenceData roundtrip JSON', () {
      final cursor = CursorPresenceData(
        userId: 'user_1',
        displayName: 'Alice',
        cursorColor: 0xFF42A5F5,
        x: 100.0,
        y: 200.0,
        isDrawing: true,
        penType: 'fountainPen',
        penColor: 0xFFFF0000,
      );

      final json = cursor.toJson();
      final restored = CursorPresenceData.fromJson('user_1', json);

      expect(restored.displayName, 'Alice');
      expect(restored.x, 100.0);
      expect(restored.y, 200.0);
      expect(restored.isDrawing, isTrue);
      expect(restored.penType, 'fountainPen');
      expect(restored.penColor, 0xFFFF0000);
    });
  });
}
