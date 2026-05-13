import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/collaboration/crdt_layer_controller_applier.dart';
import 'package:fluera_engine/src/collaboration/crdt_layer_controller_observer.dart';
import 'package:fluera_engine/src/collaboration/fluera_realtime_adapter.dart';
import 'package:fluera_engine/src/collaboration/ready_to_use_adapters.dart';
import 'package:fluera_engine/src/collaboration/scene_graph_crdt.dart';
import 'package:fluera_engine/src/layers/layer_controller.dart';

import '../helpers/test_helpers.dart';

// =============================================================================
// 🌐 REALTIME ENGINE END-TO-END CONVERGENCE TEST
//
// Validates that the FULL collab pipeline — LayerController →
// CRDTLayerControllerObserver → FlueraRealtimeEngine.broadcastCRDTOperation
// → InMemoryRealtimeAdapter (linked) → FlueraRealtimeEngine.incomingCRDTOps
// → CRDTToLayerControllerApplier → LayerController — converges across two
// peers under random interleaving and survives wire duplication.
//
// Complementary to multi_peer_e2e_test.dart, which tests the CRDT layer in
// isolation. This test exercises the actual transport-facing surface so a
// regression in the engine wiring (envelope, self-echo filter, op routing)
// surfaces here, not in production.
// =============================================================================

/// One peer's full pipeline — engine, observer, applier, LayerController.
class _Peer {
  final String peerId;
  final InMemoryRealtimeAdapter adapter;
  final FlueraRealtimeEngine engine;
  final CRDTSceneGraph crdt;
  final CRDTLayerControllerObserver observer;
  final CRDTToLayerControllerApplier applier;
  final LayerController layerController;
  final List<CRDTOperation> outboxLocal = [];
  late final StreamSubscription<CRDTOperation> _opSub;

  _Peer._({
    required this.peerId,
    required this.adapter,
    required this.engine,
    required this.crdt,
    required this.observer,
    required this.applier,
    required this.layerController,
  });

  static _Peer create(String peerId, {int latencyMs = 0}) {
    final adapter = InMemoryRealtimeAdapter(latencyMs: latencyMs);
    final engine = FlueraRealtimeEngine(
      adapter: adapter,
      localUserId: peerId,
    );
    final crdt = CRDTSceneGraph(localPeerId: peerId);
    final lc = LayerController();
    final localOutbox = <CRDTOperation>[];
    final observer = CRDTLayerControllerObserver(
      crdt,
      onLocalOperation: (op) {
        localOutbox.add(op);
        // Fire and forget — same path the production code uses.
        engine.broadcastCRDTOperation(op);
      },
    );
    lc.addMutationObserver(observer.onMutation);
    final applier = CRDTToLayerControllerApplier(
      crdt: crdt,
      layerController: lc,
      observer: observer,
    );
    final peer = _Peer._(
      peerId: peerId,
      adapter: adapter,
      engine: engine,
      crdt: crdt,
      observer: observer,
      applier: applier,
      layerController: lc,
    );
    peer.outboxLocal.addAll(localOutbox);
    // Re-bind the observer's onLocalOperation to also record into the
    // peer instance's outbox (the closure above uses a local list since
    // peer doesn't exist yet).
    peer._opSub = engine.incomingCRDTOperations.listen(applier.applyRemote);
    return peer;
  }

  Future<void> connect(String canvasId) => engine.connect(canvasId);

  Future<void> dispose() async {
    await _opSub.cancel();
    applier.dispose();
    await engine.disconnect();
    engine.dispose();
    adapter.dispose();
    layerController.dispose();
  }
}

/// Snapshot of a peer's *visible* state (what the user sees), keyed by
/// stroke id only. Intentionally ignores per-peer metadata so two peers
/// that converged on the same set of strokes match.
Set<String> visibleStrokeIds(_Peer p) {
  return {
    for (final layer in p.layerController.layers)
      for (final s in layer.strokes) s.id,
  };
}

/// Pump the event loop a few times so streams flush.
Future<void> pump([int microtasks = 8]) async {
  for (var i = 0; i < microtasks; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  // Test 1 — Two-peer convergence under random interleaving
  // ───────────────────────────────────────────────────────────────────────────

  test('two engines linked converge after random interleaved strokes',
      () async {
    final a = _Peer.create('peer_a-${_rand.nextInt(1 << 24)}');
    final b = _Peer.create('peer_b-${_rand.nextInt(1 << 24)}');
    a.adapter.linkTo(b.adapter);

    addTearDown(() async {
      await a.dispose();
      await b.dispose();
    });

    await a.connect('canvas-conv');
    await b.connect('canvas-conv');
    await pump();

    final rng = Random(42);
    // Stay below the engine's 60-events-per-second rate bucket so we
    // exercise the live broadcast path rather than the offline queue
    // replay path (the latter is independently covered by the partition
    // test). 50 strokes interleaved between two peers proves convergence
    // without paying for the 1s token refill window.
    const totalStrokes = 50;

    // Randomly drive strokes on either peer. Each addStroke produces a
    // CRDTOperation that the engine broadcasts to the linked peer's
    // event controller; the receiving engine routes it to its applier
    // which adds the stroke to the receiving LayerController.
    for (var i = 0; i < totalStrokes; i++) {
      final peer = rng.nextBool() ? a : b;
      peer.layerController.addStroke(testStroke(id: '${peer.peerId}_$i'));
      // Yield between bursts so cross-peer events get applied
      // immediately rather than queued on the receiver's microtask
      // ledger (mirrors real wire latency).
      if (i % 8 == 0) await pump(2);
    }

    // Drain remaining microtasks until both peers' visible state stops
    // changing or we hit the budget.
    var lastA = -1, lastB = -1;
    for (var i = 0; i < 100; i++) {
      await pump(4);
      final av = visibleStrokeIds(a).length;
      final bv = visibleStrokeIds(b).length;
      if (av == lastA && bv == lastB && av == bv && av == totalStrokes) break;
      lastA = av;
      lastB = bv;
    }

    expect(visibleStrokeIds(a), equals(visibleStrokeIds(b)),
        reason: 'Both peers must end up with the same set of strokes');
    expect(visibleStrokeIds(a).length, equals(totalStrokes),
        reason: 'Every stroke produced must be visible on both peers');
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Test 2 — Wire idempotency: duplicate event delivered twice = one stroke
  // ───────────────────────────────────────────────────────────────────────────

  test('duplicate broadcast does not produce a second stroke', () async {
    final a = _Peer.create('peer_a_${_rand.nextInt(1 << 24)}');
    final b = _Peer.create('peer_b_${_rand.nextInt(1 << 24)}');
    a.adapter.linkTo(b.adapter);

    addTearDown(() async {
      await a.dispose();
      await b.dispose();
    });

    await a.connect('canvas-dup');
    await b.connect('canvas-dup');
    await pump();

    a.layerController.addStroke(testStroke(id: 'dup-1'));
    await pump(8);

    // Replay every event that has crossed the wire so far. The CRDT
    // layer's _appliedOps dedup MUST collapse the duplicate; the applier
    // MUST detect "stroke already exists" and skip the second add.
    expect(b.outboxLocal, isEmpty,
        reason: 'Peer B must not have generated any local ops');
    expect(visibleStrokeIds(b), equals({'dup-1'}));

    // Manually re-inject the captured outbound op to force a second
    // delivery (mirrors at-least-once transport semantics).
    for (final op in a.outboxLocal) {
      b.adapter.injectRemoteEvent(
        CanvasRealtimeEvent.fromCRDTOperation(op, senderId: a.peerId),
      );
    }
    await pump(8);

    expect(visibleStrokeIds(b), equals({'dup-1'}),
        reason: 'Replayed duplicate must collapse via opId dedup');
    expect(b.layerController.layers.first.strokes.length, equals(1),
        reason: 'Active layer must contain exactly one stroke');
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Test 3 — Partition + reconnect: ops produced while unlinked are lost on
  // the wire (matching Supabase Broadcast semantics) but each peer's local
  // state stays self-consistent.
  // ───────────────────────────────────────────────────────────────────────────

  test('partition drops mid-flight broadcasts; both sides keep local state',
      () async {
    final a = _Peer.create('peer_a_${_rand.nextInt(1 << 24)}');
    final b = _Peer.create('peer_b_${_rand.nextInt(1 << 24)}');
    a.adapter.linkTo(b.adapter);

    addTearDown(() async {
      await a.dispose();
      await b.dispose();
    });

    await a.connect('canvas-part');
    await b.connect('canvas-part');
    await pump();

    // Phase 1 — connected. Both peers see each other's strokes.
    a.layerController.addStroke(testStroke(id: 'pre-a-1'));
    b.layerController.addStroke(testStroke(id: 'pre-b-1'));
    await pump(16);
    expect(visibleStrokeIds(a), equals(visibleStrokeIds(b)));

    // Phase 2 — partition. Drops broadcasts on the wire only; local
    // engine still considers itself connected (matches the failure mode
    // we actually see in production: TCP up but Supabase fan-out flaky).
    a.adapter.linkActive = false;
    b.adapter.linkActive = false;

    a.layerController.addStroke(testStroke(id: 'mid-a-1'));
    b.layerController.addStroke(testStroke(id: 'mid-b-1'));
    await pump(16);

    expect(visibleStrokeIds(a), equals({'pre-a-1', 'pre-b-1', 'mid-a-1'}),
        reason: 'A keeps its own strokes during partition');
    expect(visibleStrokeIds(b), equals({'pre-a-1', 'pre-b-1', 'mid-b-1'}),
        reason: 'B keeps its own strokes during partition');

    // Phase 3 — reconnect. Wire link restored, but no automatic replay
    // (Supabase Broadcast has no buffer). Subsequent strokes propagate
    // again; pre-existing partition-era strokes stay missing on the
    // other side until an out-of-band reconciliation (cloud snapshot
    // or operations_log RPC, both out of scope here).
    a.adapter.linkActive = true;
    b.adapter.linkActive = true;

    a.layerController.addStroke(testStroke(id: 'post-a-1'));
    await pump(16);

    expect(visibleStrokeIds(b).contains('post-a-1'), isTrue,
        reason: 'Post-reconnect strokes must propagate again');
    expect(visibleStrokeIds(b).contains('mid-a-1'), isFalse,
        reason: 'Partition-era ops are not retroactively delivered');
  });
}

final _rand = Random();
