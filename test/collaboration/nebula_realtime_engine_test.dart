import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/collaboration/nebula_realtime_adapter.dart';

// =============================================================================
// Mock implementation
// =============================================================================

class MockRealtimeAdapter implements NebulaRealtimeAdapter {
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
  late NebulaRealtimeEngine engine;

  setUp(() {
    adapter = MockRealtimeAdapter();
    engine = NebulaRealtimeEngine(adapter: adapter, localUserId: 'user_local');
  });

  tearDown(() {
    engine.dispose();
    adapter.dispose();
  });

  group('NebulaRealtimeEngine — Connection lifecycle', () {
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

  group('NebulaRealtimeEngine — Event broadcasting', () {
    test('broadcastStroke creates event with correct type', () async {
      await engine.connect('canvas_1');

      engine.broadcastStroke({'id': 'stroke_1', 'points': []});

      // Allow async
      await Future.delayed(const Duration(milliseconds: 50));

      expect(adapter.broadcastedEvents, hasLength(1));
      expect(
        adapter.broadcastedEvents.first.type,
        RealtimeEventType.strokeAdded,
      );
      expect(adapter.broadcastedEvents.first.senderId, 'user_local');
      expect(adapter.broadcastedEvents.first.payload['id'], 'stroke_1');
    });

    test('broadcastStrokeRemoved creates correct event', () async {
      await engine.connect('canvas_1');

      engine.broadcastStrokeRemoved('stroke_42');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(adapter.broadcastedEvents, hasLength(1));
      expect(
        adapter.broadcastedEvents.first.type,
        RealtimeEventType.strokeRemoved,
      );
      expect(adapter.broadcastedEvents.first.payload['strokeId'], 'stroke_42');
    });

    test('broadcastImageUpdate with isNew flag', () async {
      await engine.connect('canvas_1');

      engine.broadcastImageUpdate({
        'id': 'img_1',
        'path': '/test.png',
      }, isNew: true);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(adapter.broadcastedEvents, hasLength(1));
      expect(
        adapter.broadcastedEvents.first.type,
        RealtimeEventType.imageAdded,
      );
    });

    test('broadcastTextChange creates correct event', () async {
      await engine.connect('canvas_1');

      engine.broadcastTextChange({'id': 'txt_1', 'text': 'Hello'});
      await Future.delayed(const Duration(milliseconds: 50));

      expect(adapter.broadcastedEvents, hasLength(1));
      expect(
        adapter.broadcastedEvents.first.type,
        RealtimeEventType.textChanged,
      );
    });
  });

  group('NebulaRealtimeEngine — Incoming event filtering', () {
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

  group('NebulaRealtimeEngine — Element locking', () {
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

  group('NebulaRealtimeEngine — Cursor throttle', () {
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

  group('NebulaRealtimeEngine — Serialization', () {
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
