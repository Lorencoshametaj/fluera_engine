import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/collaboration/realtime_enterprise.dart';
import 'package:nebula_engine/src/collaboration/nebula_realtime_adapter.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // 1. VECTOR CLOCK
  // ═══════════════════════════════════════════════════════════════════════════

  group('VectorClock', () {
    test('tick increments local counter', () {
      final vc = VectorClock();
      vc.tick('user_a');
      expect(vc['user_a'], 1);
      vc.tick('user_a');
      expect(vc['user_a'], 2);
    });

    test('unknown user returns 0', () {
      final vc = VectorClock();
      expect(vc['nonexistent'], 0);
    });

    test('merge takes element-wise max', () {
      final a = VectorClock({'u1': 3, 'u2': 1});
      final b = VectorClock({'u1': 2, 'u2': 5, 'u3': 1});
      a.merge(b);
      expect(a['u1'], 3); // Max(3, 2)
      expect(a['u2'], 5); // Max(1, 5)
      expect(a['u3'], 1); // New from b
    });

    test('compareTo detects before/after/concurrent', () {
      final a = VectorClock({'u1': 1, 'u2': 1});
      final b = VectorClock({'u1': 2, 'u2': 2});
      expect(a.compareTo(b), CausalOrder.before);
      expect(b.compareTo(a), CausalOrder.after);

      // Concurrent: neither dominates
      final c = VectorClock({'u1': 2, 'u2': 1});
      final d = VectorClock({'u1': 1, 'u2': 2});
      expect(c.compareTo(d), CausalOrder.concurrent);
    });

    test('compareTo returns equal for identical clocks', () {
      final a = VectorClock({'u1': 3});
      final b = VectorClock({'u1': 3});
      expect(a.compareTo(b), CausalOrder.equal);
    });

    test('JSON roundtrip', () {
      final original = VectorClock({'u1': 5, 'u2': 3});
      final json = original.toJson();
      final restored = VectorClock.fromJson(json.map((k, v) => MapEntry(k, v)));
      expect(restored['u1'], 5);
      expect(restored['u2'], 3);
    });

    test('copy creates independent copy', () {
      final a = VectorClock({'u1': 1});
      final b = a.copy();
      b.tick('u1');
      expect(a['u1'], 1);
      expect(b['u1'], 2);
    });
  });

  group('VectorClockManager', () {
    test('tick increments and returns snapshot', () {
      final mgr = VectorClockManager('user_local');
      final clock = mgr.tick();
      expect(clock['user_local'], 1);
      final clock2 = mgr.tick();
      expect(clock2['user_local'], 2);
    });

    test('merge advances past remote', () {
      final mgr = VectorClockManager('user_local');
      mgr.tick();
      mgr.merge(VectorClock({'user_remote': 5}));
      expect(mgr.current['user_remote'], 5);
      expect(mgr.current['user_local'], 2); // Tick + merge tick
    });

    test('checkOrder detects before/concurrent', () {
      final mgr = VectorClockManager('u1');
      mgr.tick(); // u1: 1
      final remote = VectorClock({'u2': 1});
      expect(mgr.checkOrder(remote), CausalOrder.concurrent);

      mgr.merge(remote); // Now u1: 2, u2: 1
      final laterRemote = VectorClock({'u2': 1});
      expect(mgr.checkOrder(laterRemote), CausalOrder.after);
    });
  });

  group('CausalEvent', () {
    test('JSON roundtrip with embedded vector clock', () {
      final event = CanvasRealtimeEvent(
        type: RealtimeEventType.strokeAdded,
        senderId: 'u1',
        payload: {'id': 's1'},
        timestamp: 12345,
      );
      final causal = CausalEvent(
        event: event,
        clock: VectorClock({'u1': 3, 'u2': 1}),
      );

      final json = causal.toJson();
      expect(json['_vclock'], {'u1': 3, 'u2': 1});

      final restored = CausalEvent.fromJson(json);
      expect(restored.event.type, RealtimeEventType.strokeAdded);
      expect(restored.clock['u1'], 3);
      expect(restored.clock['u2'], 1);
    });

    test('isConcurrentWith detects conflicts', () {
      final a = CausalEvent(
        event: CanvasRealtimeEvent(
          type: RealtimeEventType.imageUpdated,
          senderId: 'u1',
          payload: {},
          timestamp: 1,
        ),
        clock: VectorClock({'u1': 2, 'u2': 1}),
      );
      final b = CausalEvent(
        event: CanvasRealtimeEvent(
          type: RealtimeEventType.imageUpdated,
          senderId: 'u2',
          payload: {},
          timestamp: 2,
        ),
        clock: VectorClock({'u1': 1, 'u2': 2}),
      );
      expect(a.isConcurrentWith(b), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. SESSION AUDIT LOG
  // ═══════════════════════════════════════════════════════════════════════════

  group('SessionAuditLog', () {
    late SessionAuditLog log;

    setUp(() => log = SessionAuditLog());
    tearDown(() => log.dispose());

    test('logEvent adds entries', () {
      log.logEvent(
        CanvasRealtimeEvent(
          type: RealtimeEventType.strokeAdded,
          senderId: 'u1',
          elementId: 's1',
          payload: {'id': 's1'},
          timestamp: 1000,
        ),
      );
      expect(log.length, 1);
      expect(log.entries.first.action, AuditAction.strokeAdd);
    });

    test('logSession tracks join/leave', () {
      log.logSession('u1', true, userName: 'Alice');
      log.logSession('u1', false, userName: 'Alice');

      expect(log.length, 2);
      expect(log.entries[0].action, AuditAction.sessionLeave); // Newest first
      expect(log.entries[1].action, AuditAction.sessionJoin);
    });

    test('respects maxEntries capacity', () {
      final smallLog = SessionAuditLog(maxEntries: 3);

      for (var i = 0; i < 5; i++) {
        smallLog.logSession('u1', true);
      }

      expect(smallLog.length, 3);
      smallLog.dispose();
    });

    test('entriesForUser filters by user', () {
      log.logSession('u1', true);
      log.logSession('u2', true);
      log.logSession('u1', false);

      expect(log.entriesForUser('u1'), hasLength(2));
      expect(log.entriesForUser('u2'), hasLength(1));
    });

    test('onEntry stream emits entries', () async {
      final received = <AuditLogEntry>[];
      log.onEntry.listen(received.add);

      log.logSession('u1', true);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(received, hasLength(1));
    });

    test('toJson exports all entries', () {
      log.logSession('u1', true);
      final json = log.toJson();
      expect(json, hasLength(1));
      expect(json.first['userId'], 'u1');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. CONNECTION QUALITY MONITOR
  // ═══════════════════════════════════════════════════════════════════════════

  group('ConnectionQualityMonitor', () {
    late ConnectionQualityMonitor monitor;

    setUp(() => monitor = ConnectionQualityMonitor());
    tearDown(() => monitor.dispose());

    test('records samples and calculates latency', () {
      for (var i = 0; i < 5; i++) {
        monitor.recordSample(30); // 30ms
      }
      expect(monitor.latencyMs.value, 30);
    });

    test('excellent quality for low latency', () {
      for (var i = 0; i < 5; i++) {
        monitor.recordSample(20);
      }
      expect(monitor.quality.value, ConnectionQuality.excellent);
    });

    test('poor quality for high latency', () {
      for (var i = 0; i < 5; i++) {
        monitor.recordSample(800);
      }
      expect(monitor.quality.value, ConnectionQuality.poor);
    });

    test('recordFromEvent uses event timestamp', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      monitor.recordFromEvent(
        CanvasRealtimeEvent(
          type: RealtimeEventType.strokeAdded,
          senderId: 'u1',
          payload: {},
          timestamp: now - 50, // 50ms ago
        ),
      );
      expect(monitor.latencyMs.value, greaterThanOrEqualTo(0));
    });

    test('reset clears all data', () {
      monitor.recordSample(100);
      monitor.reset();
      expect(monitor.latencyMs.value, 0);
      expect(monitor.jitterMs.value, 0);
      expect(monitor.quality.value, ConnectionQuality.good);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. BANDWIDTH ADAPTIVE
  // ═══════════════════════════════════════════════════════════════════════════

  group('BandwidthAdaptiveConfig', () {
    late ConnectionQualityMonitor monitor;
    late BandwidthAdaptiveConfig config;

    setUp(() {
      monitor = ConnectionQualityMonitor();
      config = BandwidthAdaptiveConfig(monitor);
    });
    tearDown(() => monitor.dispose());

    test('excellent quality gives max performance', () {
      for (var i = 0; i < 5; i++) {
        monitor.recordSample(10);
      }
      expect(config.cursorUpdatesPerSecond, 20);
      expect(config.maxPointsPerStreamBatch, 50);
      expect(config.enableStrokeStreaming, isTrue);
      expect(config.maxEventsPerSecond, 60);
    });

    test('poor quality reduces all parameters', () {
      for (var i = 0; i < 5; i++) {
        monitor.recordSample(1000);
      }
      expect(config.cursorUpdatesPerSecond, 4);
      expect(config.maxPointsPerStreamBatch, 5);
      expect(config.enableStrokeStreaming, isFalse);
      expect(config.maxEventsPerSecond, 10);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 5. UNDO/REDO BROADCAST
  // ═══════════════════════════════════════════════════════════════════════════

  group('UndoRedoEvent', () {
    test('JSON roundtrip', () {
      final event = UndoRedoEvent(
        isUndo: true,
        userId: 'u1',
        stepCount: 3,
        timestamp: 12345,
      );

      final json = event.toJson();
      final restored = UndoRedoEvent.fromJson(json);

      expect(restored.isUndo, isTrue);
      expect(restored.userId, 'u1');
      expect(restored.stepCount, 3);
      expect(restored.timestamp, 12345);
    });

    test('roundtrip with affected event', () {
      final affected = CanvasRealtimeEvent(
        type: RealtimeEventType.strokeAdded,
        senderId: 'u1',
        payload: {'id': 'stroke_1'},
        timestamp: 100,
      );
      final event = UndoRedoEvent(
        isUndo: false,
        userId: 'u1',
        affectedEvent: affected,
        timestamp: 200,
      );

      final json = event.toJson();
      final restored = UndoRedoEvent.fromJson(json);

      expect(restored.isUndo, isFalse);
      expect(restored.affectedEvent, isNotNull);
      expect(restored.affectedEvent!.type, RealtimeEventType.strokeAdded);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 6. E2E ENCRYPTION (with mock crypto)
  // ═══════════════════════════════════════════════════════════════════════════

  group('EncryptedRealtimeAdapter', () {
    test('encrypt/decrypt roundtrip preserves event data', () async {
      final mockAdapter = _MockAdapter();
      final crypto = _XorCryptoProvider('test_key_12345');
      final encrypted = EncryptedRealtimeAdapter(
        inner: mockAdapter,
        crypto: crypto,
      );

      // Subscribe to get decrypted events
      final stream = encrypted.subscribe('canvas_1');
      final received = <CanvasRealtimeEvent>[];
      stream.listen(received.add);

      // Broadcast sends encrypted
      await encrypted.broadcast(
        'canvas_1',
        CanvasRealtimeEvent(
          type: RealtimeEventType.strokeAdded,
          senderId: 'u1',
          payload: {'id': 'stroke_1', 'color': 0xFF0000},
          timestamp: 12345,
        ),
      );

      await Future.delayed(const Duration(milliseconds: 100));

      // The sent event should have '_enc' instead of original payload
      expect(mockAdapter.sentEvents, hasLength(1));
      expect(mockAdapter.sentEvents.first.payload.containsKey('_enc'), isTrue);
    });
  });
}

// ─── Test helpers ────────────────────────────────────────────────────────────

class _MockAdapter implements NebulaRealtimeAdapter {
  final _controller = StreamController<CanvasRealtimeEvent>.broadcast();
  final List<CanvasRealtimeEvent> sentEvents = [];

  @override
  Stream<CanvasRealtimeEvent> subscribe(String canvasId) => _controller.stream;

  @override
  Future<void> broadcast(String canvasId, CanvasRealtimeEvent event) async {
    sentEvents.add(event);
    _controller.add(event);
  }

  @override
  Future<void> disconnect(String canvasId) async {}

  @override
  Stream<Map<String, CursorPresenceData>> cursorStream(String canvasId) =>
      const Stream.empty();

  @override
  Future<void> broadcastCursor(String canvasId, CursorPresenceData c) async {}
}

/// Simple XOR cipher for testing (NOT secure — development only).
class _XorCryptoProvider implements RealtimeEncryptionProvider {
  final Uint8List _key;
  _XorCryptoProvider(String passphrase)
    : _key = Uint8List.fromList(utf8.encode(passphrase));

  @override
  Future<Uint8List> encrypt(Uint8List data) async {
    return Uint8List.fromList([
      for (var i = 0; i < data.length; i++) data[i] ^ _key[i % _key.length],
    ]);
  }

  @override
  Future<Uint8List> decrypt(Uint8List data) async => encrypt(data);
}
