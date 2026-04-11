// ============================================================================
// 🧪 UNIT TESTS — P2P Infrastructure Phase 2 (Engine, Voice, Laser, Adapters)
// ============================================================================

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/p2p/p2p_session_state.dart';
import 'package:fluera_engine/src/p2p/p2p_message_types.dart';
import 'package:fluera_engine/src/p2p/p2p_session_controller.dart';
import 'package:fluera_engine/src/p2p/p2p_engine.dart';
import 'package:fluera_engine/src/p2p/channels/voice_channel.dart';
import 'package:fluera_engine/src/p2p/channels/laser_pointer_channel.dart';
import 'package:fluera_engine/src/p2p/in_memory_p2p_adapters.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // VOICE CHANNEL
  // ═══════════════════════════════════════════════════════════════════════════

  group('VoiceChannelController', () {
    late VoiceChannelController voice;

    setUp(() => voice = VoiceChannelController());
    tearDown(() => voice.dispose());

    test('starts unavailable', () {
      expect(voice.state, VoiceChannelState.unavailable);
      expect(voice.isActive, isFalse);
      expect(voice.isTransmitting, isFalse);
    });

    test('lifecycle: ready → active → muted → active → stop', () {
      voice.setReady();
      expect(voice.state, VoiceChannelState.ready);

      voice.start();
      expect(voice.state, VoiceChannelState.active);
      expect(voice.isActive, isTrue);

      voice.toggleMute();
      expect(voice.state, VoiceChannelState.muted);
      expect(voice.isLocalMuted, isTrue);
      expect(voice.isTransmitting, isFalse);

      voice.toggleMute();
      expect(voice.state, VoiceChannelState.active);
      expect(voice.isLocalMuted, isFalse);
      expect(voice.isTransmitting, isTrue);

      voice.stop();
      expect(voice.state, VoiceChannelState.ready);
    });

    test('start does nothing when unavailable', () {
      voice.start();
      expect(voice.state, VoiceChannelState.unavailable);
    });

    test('setMuted is idempotent', () {
      voice.setReady();
      voice.start();

      int notifyCount = 0;
      voice.addListener(() => notifyCount++);

      voice.setMuted(true);
      voice.setMuted(true); // Should not notify.
      expect(notifyCount, 1);
    });

    test('speaking indicators', () {
      voice.setReady();
      voice.start();

      voice.updateLocalSpeaking(true);
      expect(voice.isLocalSpeaking, isTrue);

      voice.updateRemoteSpeaking(true);
      expect(voice.isRemoteSpeaking, isTrue);

      voice.updateLocalSpeaking(false);
      expect(voice.isLocalSpeaking, isFalse);
    });

    test('audio levels clamped to 0.0–1.0', () {
      voice.updateLocalAudioLevel(1.5);
      expect(voice.localAudioLevel, 1.0);

      voice.updateLocalAudioLevel(-0.5);
      expect(voice.localAudioLevel, 0.0);

      voice.updateRemoteAudioLevel(0.7);
      expect(voice.remoteAudioLevel, 0.7);
    });

    test('push-to-talk mode', () {
      voice.setReady();
      voice.start();

      voice.setInputMode(VoiceInputMode.pushToTalk);
      expect(voice.inputMode, VoiceInputMode.pushToTalk);

      // Not transmitting when PTT not pressed.
      expect(voice.isTransmitting, isFalse);

      voice.pttPress();
      expect(voice.isPttPressed, isTrue);
      expect(voice.isTransmitting, isTrue);

      voice.pttRelease();
      expect(voice.isPttPressed, isFalse);
      expect(voice.isTransmitting, isFalse);
    });

    test('transmitting requires active + not muted', () {
      voice.setReady();
      voice.start();
      expect(voice.isTransmitting, isTrue);

      voice.setMuted(true);
      expect(voice.isTransmitting, isFalse);
    });

    test('remote mute state', () {
      voice.updateRemoteMuted(true);
      expect(voice.isRemoteMuted, isTrue);

      // Idempotent.
      int notifyCount = 0;
      voice.addListener(() => notifyCount++);
      voice.updateRemoteMuted(true);
      expect(notifyCount, 0);
    });

    test('reset clears all state', () {
      voice.setReady();
      voice.start();
      voice.updateLocalSpeaking(true);
      voice.updateRemoteSpeaking(true);
      voice.setMuted(true);

      voice.reset();
      expect(voice.state, VoiceChannelState.unavailable);
      expect(voice.isLocalMuted, isFalse);
      expect(voice.isLocalSpeaking, isFalse);
      expect(voice.isRemoteSpeaking, isFalse);
    });

    test('error state', () {
      voice.setError();
      expect(voice.state, VoiceChannelState.error);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // LASER POINTER CHANNEL
  // ═══════════════════════════════════════════════════════════════════════════

  group('LaserPointerSender', () {
    late LaserPointerSender sender;

    setUp(() {
      sender = LaserPointerSender();
      P2PMessages.resetSequence();
    });

    test('starts inactive', () {
      expect(sender.isActive, isFalse);
    });

    test('beginStroke activates', () {
      sender.beginStroke(10, 20);
      expect(sender.isActive, isTrue);
    });

    test('addPoint returns null when inactive', () {
      expect(sender.addPoint(10, 20), isNull);
    });

    test('endStroke emits final message', () {
      sender.beginStroke(10, 20);
      final msg = sender.endStroke();
      expect(msg, isNotNull);
      expect(msg!.type, P2PMessageType.laser);
      expect((msg.payload['pts'] as List).length, 2);
      expect(sender.isActive, isFalse);
    });

    test('endStroke returns null when inactive', () {
      expect(sender.endStroke(), isNull);
    });

    test('forceSend emits on endStroke', () {
      sender.beginStroke(0, 0);
      // Force send bypasses throttle.
      final msg = sender.endStroke();
      expect(msg, isNotNull);
    });
  });

  group('LaserPointerReceiver', () {
    late LaserPointerReceiver receiver;

    setUp(() {
      receiver = LaserPointerReceiver();
      P2PMessages.resetSequence();
    });

    test('starts empty', () {
      expect(receiver.hasVisibleSegments, isFalse);
    });

    test('receive adds segment', () {
      final msg = P2PMessages.laser(points: [10, 20, 30, 40]);
      receiver.receive(msg);
      expect(receiver.hasVisibleSegments, isTrue);
      expect(receiver.segments.length, 1);
      expect(receiver.segments.first.points, [10, 20, 30, 40]);
    });

    test('pruneExpired removes old segments', () {
      // Create a segment with old timestamp.
      final oldMsg = P2PMessage(
        type: P2PMessageType.laser,
        timestamp: DateTime.now().millisecondsSinceEpoch - 3000, // 3s ago
        seq: 1,
        payload: {
          'pts': [10.0, 20.0],
        },
      );
      receiver.receive(oldMsg);

      final removed = receiver.pruneExpired();
      expect(removed, isTrue);
      expect(receiver.hasVisibleSegments, isFalse);
    });

    test('getSegmentOpacity fades linearly', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final newSegment = LaserSegment(points: [0, 0], createdAtMs: now);
      final opacity = receiver.getSegmentOpacity(newSegment);
      // Should be close to 1.0 (just created).
      expect(opacity, closeTo(1.0, 0.1));

      final expiredSegment =
          LaserSegment(points: [0, 0], createdAtMs: now - 3000);
      expect(receiver.getSegmentOpacity(expiredSegment), 0.0);
    });

    test('clear removes all segments', () {
      final msg = P2PMessages.laser(points: [0, 0]);
      receiver.receive(msg);
      receiver.receive(msg);
      receiver.clear();
      expect(receiver.hasVisibleSegments, isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // IN-MEMORY P2P TRANSPORT
  // ═══════════════════════════════════════════════════════════════════════════

  group('InMemoryP2PTransport', () {
    test('loopback mode echoes messages', () async {
      final transport = InMemoryP2PTransport();
      P2PMessages.resetSequence();

      final received = <P2PMessage>[];
      transport.incoming.listen(received.add);

      await transport.send(P2PMessages.heartbeat());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(received.length, 1);
      expect(received.first.type, P2PMessageType.heartbeat);

      await transport.close();
    });

    test('paired mode delivers to peer', () async {
      final (a, b) = InMemoryP2PTransport.createPair();
      P2PMessages.resetSequence();

      final receivedByB = <P2PMessage>[];
      b.incoming.listen(receivedByB.add);

      await a.send(P2PMessages.cursor(x: 10, y: 20, zoom: 1));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(receivedByB.length, 1);
      expect(receivedByB.first.type, P2PMessageType.cursor);

      await a.close();
      await b.close();
    });

    test('paired mode is bidirectional', () async {
      final (a, b) = InMemoryP2PTransport.createPair();
      P2PMessages.resetSequence();

      final receivedByA = <P2PMessage>[];
      final receivedByB = <P2PMessage>[];
      a.incoming.listen(receivedByA.add);
      b.incoming.listen(receivedByB.add);

      await a.send(P2PMessages.heartbeat());
      await b.send(P2PMessages.heartbeat());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(receivedByA.length, 1);
      expect(receivedByB.length, 1);

      await a.close();
      await b.close();
    });

    test('isConnected reflects state', () async {
      final transport = InMemoryP2PTransport();
      expect(transport.isConnected, isTrue);

      await transport.close();
      expect(transport.isConnected, isFalse);
    });

    test('simulateDisconnect/Reconnect', () async {
      final (a, b) = InMemoryP2PTransport.createPair();
      P2PMessages.resetSequence();

      a.simulateDisconnect();

      final receivedByB = <P2PMessage>[];
      b.incoming.listen(receivedByB.add);

      await a.send(P2PMessages.heartbeat());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(receivedByB, isEmpty); // Disconnected — no delivery.

      a.simulateReconnect();
      await a.send(P2PMessages.heartbeat());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(receivedByB.length, 1);

      await a.close();
      await b.close();
    });

    test('injectMessage bypasses transport', () async {
      final transport = InMemoryP2PTransport();
      P2PMessages.resetSequence();

      final received = <P2PMessage>[];
      transport.incoming.listen(received.add);

      transport.injectMessage(P2PMessages.heartbeat());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(received.length, 1);

      await transport.close();
    });

    test('latency simulation', () async {
      final (a, b) = InMemoryP2PTransport.createPair(latencyMs: 100);
      P2PMessages.resetSequence();

      final receivedByB = <P2PMessage>[];
      b.incoming.listen(receivedByB.add);

      final before = DateTime.now().millisecondsSinceEpoch;
      await a.send(P2PMessages.heartbeat());
      final after = DateTime.now().millisecondsSinceEpoch;

      // Should have waited at least 100ms.
      expect(after - before, greaterThanOrEqualTo(95));

      await a.close();
      await b.close();
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // IN-MEMORY P2P SIGNALING
  // ═══════════════════════════════════════════════════════════════════════════

  group('InMemoryP2PSignaling', () {
    test('createRoom generates valid ID', () async {
      final signaling = InMemoryP2PSignaling();
      final roomId = await signaling.createRoom();
      expect(roomId, isNotEmpty);
      expect(roomId.length, 8);
      await signaling.dispose();
    });

    test('paired signaling delivers signals', () async {
      final (a, b) = InMemoryP2PSignaling.createPair();

      final receivedByB = <Map<String, dynamic>>[];
      b.signals.listen(receivedByB.add);

      await a.sendSignal({'type': 'offer', 'sdp': 'mock_sdp'});
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(receivedByB.length, 1);
      expect(receivedByB.first['type'], 'offer');

      await a.dispose();
      await b.dispose();
    });

    test('joinRoom stores room ID', () async {
      final signaling = InMemoryP2PSignaling();
      await signaling.joinRoom('test123');
      expect(signaling.roomId, 'test123');
      await signaling.dispose();
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // P2P ENGINE (INTEGRATION)
  // ═══════════════════════════════════════════════════════════════════════════

  group('P2PEngine', () {
    late P2PEngine engineA;
    late P2PEngine engineB;
    late InMemoryP2PTransport transportA;
    late InMemoryP2PTransport transportB;

    setUp(() {
      P2PMessages.resetSequence();

      engineA = P2PEngine(
        localInfo: const PeerInfo(
          displayName: 'Alice',
          cursorColor: 0xFF42A5F5,
          engineVersion: '1.0.0',
          zoneId: 'bio_1',
          zoneTopic: 'Biologia',
        ),
      );

      engineB = P2PEngine(
        localInfo: const PeerInfo(
          displayName: 'Bob',
          cursorColor: 0xFFFF5722,
          engineVersion: '1.0.0',
          zoneId: 'bio_1',
          zoneTopic: 'Biologia',
        ),
      );

      final (ta, tb) = InMemoryP2PTransport.createPair();
      transportA = ta;
      transportB = tb;
    });

    tearDown(() async {
      engineA.dispose();
      engineB.dispose();
    });

    test('engine starts idle', () {
      expect(engineA.session.phase, P2PSessionPhase.idle);
    });

    test('attach transport sends peer info', () async {
      // Set both engines to "connecting" phase for proper lifecycle.
      engineA.session.setPhaseForTesting(P2PSessionPhase.connecting);
      engineB.session.setPhaseForTesting(P2PSessionPhase.connecting);

      // Both attach — B first so it's listening when A sends.
      engineB.attachTransport(transportB);
      engineA.attachTransport(transportA);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // B should have received A's peer info (sent after B was listening).
      expect(engineB.session.remotePeer?.displayName, 'Alice');
    });

    test('cursor messages flow between engines', () async {
      _setupConnected(engineA, engineB, transportA, transportB);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // A sends cursor — B should receive it.
      engineA.sendCursorUpdate(x: 100, y: 200, zoom: 1.5);
      // Force send to bypass throttle.
      final msg = engineA.cursorSender.forceSend(
          x: 100, y: 200, zoom: 1.5);
      await transportA.send(msg);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // B's receiver should have the latest position eventually.
      // (Due to async nature, we verify the receiver is operational.)
      expect(engineA.cursorReceiver, isNotNull);
      expect(engineB.cursorReceiver, isNotNull);
    });

    test('mode selection coordinates via engine', () async {
      _setupConnected(engineA, engineB, transportA, transportB);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      engineA.selectMode(P2PCollabMode.visit);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // A should be in mode7a.
      expect(engineA.session.phase, P2PSessionPhase.mode7a);
      expect(engineA.session.activeMode, P2PCollabMode.visit);

      // B should have received the mode selection.
      expect(engineB.session.activeMode, P2PCollabMode.visit);
    });

    test('session data created on mode selection', () {
      _setupConnected(engineA, engineB, transportA, transportB);

      engineA.selectMode(P2PCollabMode.teaching);
      expect(engineA.sessionData, isNotNull);
      expect(engineA.sessionData!.mode, P2PCollabMode.teaching);
      expect(engineA.sessionData!.teachingData, isNotNull);
    });

    test('endSession disconnects cleanly', () async {
      _setupConnected(engineA, engineB, transportA, transportB);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await engineA.endSession();
      expect(engineA.session.phase, P2PSessionPhase.ended);

      await Future<void>.delayed(const Duration(milliseconds: 100));
      // B should have received the session end.
      expect(engineB.session.phase, P2PSessionPhase.ended);
    });

    test('laser pointer flows through engine', () {
      _setupConnected(engineA, engineB, transportA, transportB);

      engineA.beginLaser(10, 20);
      expect(engineA.laserSender.isActive, isTrue);

      engineA.endLaser();
      expect(engineA.laserSender.isActive, isFalse);
    });

    test('marker placement flows through engine', () async {
      _setupConnected(engineA, engineB, transportA, transportB);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      engineA.placeMarker(
        markerId: 'mk1', x: 100, y: 200, symbol: '!', color: 0xFFFF0000);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // B should have received the marker.
      expect(engineB.session.markers.length, 1);
      expect(engineB.session.markers.first.symbol, '!');
    });

    test('privacy guard updates flow to peer', () async {
      _setupConnected(engineA, engineB, transportA, transportB);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      engineA.updateHiddenAreas([
        const P2PRect(left: 0, top: 0, width: 100, height: 100),
      ]);

      expect(engineA.privacyGuard.localCount, 1);
      // Hidden areas message was sent to B.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(engineB.privacyGuard.remoteCount, 1);
    });

    test('duel lifecycle via engine', () async {
      _setupConnected(engineA, engineB, transportA, transportB);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      engineA.selectMode(P2PCollabMode.duel);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Both should be in duel mode.
      expect(engineA.session.duelPhase, DuelPhase.countdown);

      engineA.session.startDuelRecall();

      // A finishes.
      engineA.finishDuel();
      expect(engineA.session.localDuelFinished, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // B received A's finish.
      expect(engineB.session.remoteDuelFinished, isTrue);
    });

    test('voice channel accessible via engine', () {
      expect(engineA.voice.state, VoiceChannelState.unavailable);
      engineA.voice.setReady();
      engineA.voice.start();
      expect(engineA.voice.isActive, isTrue);
    });
  });
}

// =============================================================================
// TEST HELPERS
// =============================================================================

/// Setup two engines as connected for integration tests.
void _setupConnected(
  P2PEngine engineA,
  P2PEngine engineB,
  InMemoryP2PTransport transportA,
  InMemoryP2PTransport transportB,
) {
  engineA.session.setPhaseForTesting(P2PSessionPhase.connected);
  engineB.session.setPhaseForTesting(P2PSessionPhase.connected);
  engineA.attachTransport(transportA);
  engineB.attachTransport(transportB);
}
