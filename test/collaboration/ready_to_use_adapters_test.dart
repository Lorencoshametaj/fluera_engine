import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/collaboration/ready_to_use_adapters.dart';
import 'package:fluera_engine/src/collaboration/fluera_realtime_adapter.dart';

void main() {
  // ===========================================================================
  // InMemoryRealtimeAdapter
  // ===========================================================================

  group('InMemoryRealtimeAdapter', () {
    late InMemoryRealtimeAdapter adapter;

    setUp(() {
      adapter = InMemoryRealtimeAdapter();
    });

    tearDown(() {
      adapter.dispose();
    });

    test('subscribe returns a stream that receives broadcast events', () async {
      final stream = adapter.subscribe('canvas_1');
      final received = <CanvasRealtimeEvent>[];
      final sub = stream.listen(received.add);

      final event = CanvasRealtimeEvent(
        type: RealtimeEventType.strokeAdded,
        senderId: 'user_1',
        payload: {'id': 'stroke_1'},
        timestamp: 1,
      );

      await adapter.broadcast('canvas_1', event);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(received, hasLength(1));
      expect(received.first.type, RealtimeEventType.strokeAdded);
      expect(received.first.senderId, 'user_1');

      await sub.cancel();
    });

    test('cursorStream receives broadcasted cursors', () async {
      final stream = adapter.cursorStream('canvas_1');
      final received = <Map<String, CursorPresenceData>>[];
      final sub = stream.listen(received.add);

      // Inject a remote cursor manually
      adapter.injectRemoteCursors({
        'remote_user': const CursorPresenceData(
          userId: 'remote_user',
          displayName: 'Alice',
          cursorColor: 0xFFFF0000,
          x: 50,
          y: 100,
        ),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      expect(received, hasLength(1));
      expect(received.first.containsKey('remote_user'), isTrue);
      expect(received.first['remote_user']!.displayName, 'Alice');

      await sub.cancel();
    });

    test('disconnect clears active canvas', () async {
      adapter.subscribe('canvas_1');
      await adapter.disconnect('canvas_1');
      // Should not throw
    });

    test('injectRemoteEvent delivers to subscribers', () async {
      final stream = adapter.subscribe('canvas_1');
      final received = <CanvasRealtimeEvent>[];
      final sub = stream.listen(received.add);

      adapter.injectRemoteEvent(
        CanvasRealtimeEvent(
          type: RealtimeEventType.textChanged,
          senderId: 'remote_user',
          payload: {'id': 'txt_1', 'text': 'Hello'},
          timestamp: 42,
        ),
      );

      await Future.delayed(const Duration(milliseconds: 50));

      expect(received, hasLength(1));
      expect(received.first.type, RealtimeEventType.textChanged);

      await sub.cancel();
    });

    test('latency delays event delivery', () async {
      final delayedAdapter = InMemoryRealtimeAdapter(latencyMs: 200);
      final stream = delayedAdapter.subscribe('canvas_1');
      final received = <CanvasRealtimeEvent>[];
      final sub = stream.listen(received.add);

      final before = DateTime.now();
      await delayedAdapter.broadcast(
        'canvas_1',
        CanvasRealtimeEvent(
          type: RealtimeEventType.strokeAdded,
          senderId: 'user_1',
          payload: {'id': 's1'},
          timestamp: 1,
        ),
      );
      final after = DateTime.now();

      expect(
        after.difference(before).inMilliseconds,
        greaterThanOrEqualTo(150), // Allow some tolerance
      );
      // Allow stream delivery to complete
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(received, hasLength(1));

      await sub.cancel();
      delayedAdapter.dispose();
    });

    test('simulateRemoteUser mirrors stroke events', () async {
      final mirrorAdapter = InMemoryRealtimeAdapter(
        simulateRemoteUser: true,
        simulatedOffset: const Offset(100, 50),
      );
      final stream = mirrorAdapter.subscribe('canvas_1');
      final received = <CanvasRealtimeEvent>[];
      final sub = stream.listen(received.add);

      await mirrorAdapter.broadcast(
        'canvas_1',
        CanvasRealtimeEvent(
          type: RealtimeEventType.strokeAdded,
          senderId: 'local_user',
          payload: {
            'id': 'stroke_1',
            'points': [
              {'x': 10.0, 'y': 20.0},
            ],
          },
          timestamp: 1,
        ),
      );

      // Wait for mirror delay (200-300ms)
      await Future.delayed(const Duration(milliseconds: 500));

      // Should have original + mirrored event
      expect(received.length, greaterThanOrEqualTo(2));

      final mirrored = received.firstWhere(
        (e) => e.senderId == '_simulated_remote_user',
        orElse: () => throw StateError('No mirrored event found'),
      );
      expect(mirrored.payload['id'], 'stroke_1_mirror');

      // Check offset was applied
      final points = mirrored.payload['points'] as List;
      final firstPoint = points.first as Map<String, dynamic>;
      expect(firstPoint['x'], 110.0); // 10 + 100 offset
      expect(firstPoint['y'], 70.0); // 20 + 50 offset

      await sub.cancel();
      mirrorAdapter.dispose();
    });
  });

  // ===========================================================================
  // InMemoryPermissionProvider
  // ===========================================================================

  group('InMemoryPermissionProvider', () {
    test('defaults to editor with full permissions', () async {
      const provider = InMemoryPermissionProvider();

      expect(await provider.canEdit('any_canvas'), isTrue);
      expect(await provider.canView('any_canvas'), isTrue);
      expect(provider.currentUserRole, 'editor');
    });

    test('viewer mode returns correct values', () async {
      const provider = InMemoryPermissionProvider(
        canEditValue: false,
        role: 'viewer',
      );

      expect(await provider.canEdit('canvas_1'), isFalse);
      expect(await provider.canView('canvas_1'), isTrue);
      expect(provider.currentUserRole, 'viewer');
    });

    test('fully restricted returns false for all', () async {
      const provider = InMemoryPermissionProvider(
        canEditValue: false,
        canViewValue: false,
        role: 'none',
      );

      expect(await provider.canEdit('canvas_1'), isFalse);
      expect(await provider.canView('canvas_1'), isFalse);
    });
  });

  // ===========================================================================
  // InMemoryPresenceProvider
  // ===========================================================================

  group('InMemoryPresenceProvider', () {
    late InMemoryPresenceProvider presence;

    setUp(() {
      presence = InMemoryPresenceProvider(
        localUserName: 'TestUser',
        localUserColor: const Color(0xFF42A5F5),
      );
    });

    test('joinCanvas adds local user', () {
      expect(presence.activeUsers.value, isEmpty);

      presence.joinCanvas('canvas_1');

      expect(presence.activeUsers.value, hasLength(1));
      expect(presence.activeUsers.value.first.name, 'TestUser');
      expect(presence.activeUsers.value.first.id, '_local');
      expect(presence.currentCanvasId, 'canvas_1');
    });

    test('leaveCanvas removes local user', () {
      presence.joinCanvas('canvas_1');
      expect(presence.activeUsers.value, hasLength(1));

      presence.leaveCanvas();

      expect(presence.activeUsers.value, isEmpty);
      expect(presence.currentCanvasId, isNull);
    });

    test('addSimulatedUser adds remote user', () {
      presence.joinCanvas('canvas_1');

      final bobId = presence.addSimulatedUser('Bob', Colors.orange);

      expect(presence.activeUsers.value, hasLength(2));
      expect(presence.activeUsers.value.any((u) => u.name == 'Bob'), isTrue);
      expect(bobId, startsWith('_simulated_'));
    });

    test('removeSimulatedUser removes specific user', () {
      presence.joinCanvas('canvas_1');
      final bobId = presence.addSimulatedUser('Bob');
      presence.addSimulatedUser('Carol');

      expect(presence.activeUsers.value, hasLength(3));

      presence.removeSimulatedUser(bobId);

      expect(presence.activeUsers.value, hasLength(2));
      expect(presence.activeUsers.value.any((u) => u.name == 'Bob'), isFalse);
      expect(presence.activeUsers.value.any((u) => u.name == 'Carol'), isTrue);
    });

    test('joinCanvas does not duplicate local user', () {
      presence.joinCanvas('canvas_1');
      presence.joinCanvas('canvas_2');

      final localCount =
          presence.activeUsers.value.where((u) => u.id == '_local').length;
      expect(localCount, 1);
    });
  });
}
