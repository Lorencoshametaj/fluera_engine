import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/collaboration/scene_graph_crdt.dart';

// =============================================================================
// 🌐 MULTI-PEER E2E CONVERGENCE TEST
//
// Validates that two independent CRDTSceneGraph instances converge to the
// SAME state regardless of message interleaving, partition, duplication, or
// JSON serialization on the wire. This is the closest we can get to a true
// "Validated end-to-end" multi-client check without spinning up a real
// transport.
//
// Invariants assumed (matching production transports like Supabase Realtime):
//   • FIFO per sender: ops produced by peer X are delivered to peer Y in the
//     order peer X produced them.
//   • At-least-once: ops can be delivered more than once (idempotency must
//     hold).
//   • Cross-peer interleaving is arbitrary.
//
// Each test owns its own RNG seed so failures reproduce deterministically.
// =============================================================================

/// Build a structural snapshot of a CRDT graph that can be deep-equated.
/// Excludes peer-local state (localPeerId, applied opIds) — only observable
/// scene graph state matters for convergence.
Map<String, dynamic> snapshotOf(CRDTSceneGraph g) {
  final ids = g.liveNodeIds.toList()..sort();
  return {
    'live': ids,
    'nodes': {
      for (final id in ids)
        if (g.nodeState(id) != null)
          id: {
            'type': g.nodeState(id)!.nodeType.value,
            'parent': g.nodeState(id)!.parentId.value,
            'sort': g.nodeState(id)!.sortIndex.value,
            'props': g.nodeState(id)!.toPropertyMap(),
          },
    },
  };
}

/// Round-trip an op through JSON serialization — this is what the wire
/// actually carries. If serialization is lossy, convergence breaks.
CRDTOperation roundtrip(CRDTOperation op) {
  return CRDTOperation.fromJson(
    jsonDecode(jsonEncode(op.toJson())) as Map<String, dynamic>,
  );
}

/// Generate a random local op on [graph], appending it to [outbox].
/// Returns the chosen kind for distribution stats. Op kinds biased to keep
/// the graph populated (more adds than removes).
String produceRandomOp({
  required CRDTSceneGraph graph,
  required Random rng,
  required List<CRDTOperation> outbox,
  required Set<String> liveIds,
  required int nodeIdSeed,
}) {
  // Always seed at least one node before doing prop/move/remove ops.
  if (liveIds.isEmpty || rng.nextInt(100) < 25) {
    final id = '${graph.localPeerId}_n$nodeIdSeed';
    final op = graph.addNode(
      nodeId: id,
      nodeType: 'shape',
      sortIndex: rng.nextInt(100),
      properties: {'x': rng.nextDouble() * 1000, 'color': '#ff0000'},
    );
    outbox.add(op);
    liveIds.add(id);
    return 'add';
  }

  final pick = liveIds.elementAt(rng.nextInt(liveIds.length));
  final action = rng.nextInt(10);

  if (action < 5) {
    // setProperty (most common)
    final propName = ['x', 'y', 'opacity', 'color', 'rotation'][rng.nextInt(5)];
    final value = propName == 'color'
        ? '#${rng.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0')}'
        : rng.nextDouble() * 500;
    final op = graph.setProperty(pick, propName, value);
    outbox.add(op);
    return 'setProp';
  } else if (action < 8) {
    // moveNode
    final op = graph.moveNode(pick, newSortIndex: rng.nextInt(100));
    outbox.add(op);
    return 'move';
  } else {
    // removeNode (rare so the graph stays interesting)
    final op = graph.removeNode(pick);
    outbox.add(op);
    liveIds.remove(pick);
    return 'remove';
  }
}

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  // Test 1 — 1000 op random interleaving across 2 peers converges
  // ───────────────────────────────────────────────────────────────────────────

  test('1000 op random interleaving across 2 peers converges', () {
    final rng = Random(42);
    final a = CRDTSceneGraph(localPeerId: 'peer_a');
    final b = CRDTSceneGraph(localPeerId: 'peer_b');

    final aOutbox = <CRDTOperation>[];
    final bOutbox = <CRDTOperation>[];
    final aLive = <String>{};
    final bLive = <String>{};

    // Generate 500 ops per peer in arbitrary turn order. Both peers operate
    // on their own state without seeing each other yet — pure local edits.
    for (var i = 0; i < 1000; i++) {
      if (rng.nextBool()) {
        produceRandomOp(
          graph: a,
          rng: rng,
          outbox: aOutbox,
          liveIds: aLive,
          nodeIdSeed: i,
        );
      } else {
        produceRandomOp(
          graph: b,
          rng: rng,
          outbox: bOutbox,
          liveIds: bLive,
          nodeIdSeed: i,
        );
      }
    }

    // Drain outboxes onto the other peer in FIFO order (transport invariant),
    // but with arbitrary interleaving between the two senders.
    var ai = 0;
    var bi = 0;
    while (ai < aOutbox.length || bi < bOutbox.length) {
      final pickA = ai < aOutbox.length &&
          (bi >= bOutbox.length || rng.nextBool());
      if (pickA) {
        b.apply(roundtrip(aOutbox[ai++]));
      } else {
        a.apply(roundtrip(bOutbox[bi++]));
      }
    }

    expect(snapshotOf(a), equals(snapshotOf(b)),
        reason: 'Peer A and Peer B must converge after full exchange');
    expect(a.nodeCount, greaterThan(0));
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Test 2 — Network partition + reconnect: each peer edits offline, then
  //          they exchange logs and must converge to identical state.
  // ───────────────────────────────────────────────────────────────────────────

  test('partition recovery: 100 + 100 ops offline then reconcile converges',
      () {
    final rng = Random(7);
    final a = CRDTSceneGraph(localPeerId: 'peer_a');
    final b = CRDTSceneGraph(localPeerId: 'peer_b');

    // Both peers start sharing one node (initial sync state).
    final seed = a.addNode(nodeId: 'shared_root', nodeType: 'group');
    b.apply(roundtrip(seed));

    final aOutbox = <CRDTOperation>[];
    final bOutbox = <CRDTOperation>[];
    final aLive = <String>{'shared_root'};
    final bLive = <String>{'shared_root'};

    // Partition: each peer edits in isolation.
    for (var i = 0; i < 100; i++) {
      produceRandomOp(
        graph: a,
        rng: rng,
        outbox: aOutbox,
        liveIds: aLive,
        nodeIdSeed: i,
      );
      produceRandomOp(
        graph: b,
        rng: rng,
        outbox: bOutbox,
        liveIds: bLive,
        nodeIdSeed: i + 1000,
      );
    }

    // Reconnect: A flushes its log to B (FIFO), B flushes to A (FIFO).
    for (final op in aOutbox) {
      b.apply(roundtrip(op));
    }
    for (final op in bOutbox) {
      a.apply(roundtrip(op));
    }

    expect(snapshotOf(a), equals(snapshotOf(b)),
        reason: 'Peers must converge after partition reconciliation');
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Test 3 — Idempotency: applying the same op N times has the same effect
  //          as applying it once. Critical because Supabase Realtime / any
  //          at-least-once transport will redeliver on retry.
  // ───────────────────────────────────────────────────────────────────────────

  test('idempotency: re-applying each op 5x in FIFO order is a no-op', () {
    final a = CRDTSceneGraph(localPeerId: 'peer_a');
    final b = CRDTSceneGraph(localPeerId: 'peer_b');

    final op1 = a.addNode(nodeId: 'n1', nodeType: 'shape');
    final op2 = a.setProperty('n1', 'x', 100.0);
    final op3 = a.moveNode('n1', newSortIndex: 5);

    // FIFO redelivery: same order as produced, but each op delivered 5 times.
    // Mirrors at-least-once transports (Supabase Realtime / WebSocket retry)
    // that preserve per-sender order across redeliveries.
    for (final op in [op1, op2, op3]) {
      for (var i = 0; i < 5; i++) {
        b.apply(roundtrip(op));
      }
    }

    expect(snapshotOf(b), equals(snapshotOf(a)),
        reason: 'Duplicate delivery in FIFO order must not corrupt state');
    expect(b.appliedOpCount, equals(3),
        reason: 'Dedup set must contain exactly 3 unique opIds');
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Test 3b — Out-of-order delivery within a peer's ops must still converge.
  //           setProperty/moveNode that arrive before their target's addNode
  //           are buffered and replayed when the addNode lands, so reconnect
  //           backlogs interleaving with newly-generated ops are safe.
  // ───────────────────────────────────────────────────────────────────────────

  test('out-of-order delivery: orphan ops buffered then replayed on addNode',
      () {
    final a = CRDTSceneGraph(localPeerId: 'peer_a');
    final b = CRDTSceneGraph(localPeerId: 'peer_b');

    final addOp = a.addNode(nodeId: 'n1', nodeType: 'shape');
    final propOp = a.setProperty('n1', 'x', 100.0);
    final moveOp = a.moveNode('n1', newSortIndex: 7);

    // Wire delivers prop + move BEFORE add (out of order).
    b.apply(roundtrip(propOp));
    b.apply(roundtrip(moveOp));
    expect(b.pendingOrphanOpCount, equals(2),
        reason: 'Both ops should be buffered awaiting addNode');
    expect(b.containsNode('n1'), isFalse,
        reason: 'Node not yet visible — addNode has not arrived');

    b.apply(roundtrip(addOp));

    expect(b.pendingOrphanOpCount, equals(0),
        reason: 'Orphans must drain when their addNode arrives');
    expect(snapshotOf(a), equals(snapshotOf(b)));
  });

  test('out-of-order: redelivery of an orphan is idempotent', () {
    final a = CRDTSceneGraph(localPeerId: 'peer_a');
    final b = CRDTSceneGraph(localPeerId: 'peer_b');

    final addOp = a.addNode(nodeId: 'n1', nodeType: 'shape');
    final propOp = a.setProperty('n1', 'x', 42.0);

    // At-least-once transport delivers the orphan twice before the add.
    b.apply(roundtrip(propOp));
    b.apply(roundtrip(propOp));
    expect(b.pendingOrphanOpCount, equals(1),
        reason: 'Duplicate orphan must not double-buffer');

    b.apply(roundtrip(addOp));
    expect(b.pendingOrphanOpCount, equals(0));
    expect(snapshotOf(a), equals(snapshotOf(b)));
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Test 4 — Concurrent move on the same node: LWW must pick a deterministic
  //          winner so both peers agree (HLC physicalMs > counter > peerId).
  // ───────────────────────────────────────────────────────────────────────────

  test('concurrent move of same node converges via LWW', () {
    int aClock = 1000;
    int bClock = 1000;
    final a = CRDTSceneGraph(
      localPeerId: 'peer_a',
      wallClock: () => aClock,
    );
    final b = CRDTSceneGraph(
      localPeerId: 'peer_b',
      wallClock: () => bClock,
    );

    // Both peers see the same initial node.
    final seed = a.addNode(nodeId: 'x', nodeType: 'shape');
    b.apply(roundtrip(seed));

    // Concurrent move at the SAME wall clock — HLC must tie-break on peerId.
    aClock = 2000;
    bClock = 2000;
    final aMove = a.moveNode('x', newSortIndex: 10);
    final bMove = b.moveNode('x', newSortIndex: 99);

    // Cross-apply.
    a.apply(roundtrip(bMove));
    b.apply(roundtrip(aMove));

    final sa = snapshotOf(a);
    final sb = snapshotOf(b);
    expect(sa, equals(sb), reason: 'Peers must converge after concurrent move');
    // peer_b > peer_a lexicographically, so peer_b's move wins on tie.
    expect((sa['nodes'] as Map)['x']['sort'], equals(99),
        reason: 'Tie-break by peerId — peer_b wins on string > peer_a');
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Test 5 — Concurrent property edits on different properties merge cleanly
  //          (per-property LWW). On the SAME property, later HLC wins.
  // ───────────────────────────────────────────────────────────────────────────

  test('concurrent property edits merge per-property via LWW', () {
    int aClock = 1000;
    int bClock = 1500; // peer_b is "ahead" in wall time
    final a = CRDTSceneGraph(
      localPeerId: 'peer_a',
      wallClock: () => aClock,
    );
    final b = CRDTSceneGraph(
      localPeerId: 'peer_b',
      wallClock: () => bClock,
    );

    final seed = a.addNode(nodeId: 'n', nodeType: 'shape');
    b.apply(roundtrip(seed));

    // Different properties — both should survive.
    final aSetX = a.setProperty('n', 'x', 100.0);
    final bSetY = b.setProperty('n', 'y', 200.0);

    // Same property, b wins (later wall time).
    final aSetColor = a.setProperty('n', 'color', '#aaaaaa');
    final bSetColor = b.setProperty('n', 'color', '#bbbbbb');

    for (final op in [aSetX, aSetColor]) {
      b.apply(roundtrip(op));
    }
    for (final op in [bSetY, bSetColor]) {
      a.apply(roundtrip(op));
    }

    expect(snapshotOf(a), equals(snapshotOf(b)));
    final props =
        (snapshotOf(a)['nodes'] as Map)['n']['props'] as Map<String, dynamic>;
    expect(props['x'], equals(100.0));
    expect(props['y'], equals(200.0));
    expect(props['color'], equals('#bbbbbb'),
        reason: 'Later HLC wins on same property');
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Test 6 — Add-vs-remove tie-break: LWWElementSet has add-bias on tie.
  //          Validates removal semantics under concurrent edit.
  // ───────────────────────────────────────────────────────────────────────────

  test('concurrent add then remove with later HLC: remove wins', () {
    int aClock = 1000;
    int bClock = 1000;
    final a = CRDTSceneGraph(
      localPeerId: 'peer_a',
      wallClock: () => aClock,
    );
    final b = CRDTSceneGraph(
      localPeerId: 'peer_b',
      wallClock: () => bClock,
    );

    final addOp = a.addNode(nodeId: 'doomed', nodeType: 'shape');
    b.apply(roundtrip(addOp));

    // Peer B removes at a strictly later time.
    bClock = 2000;
    final rmOp = b.removeNode('doomed');

    a.apply(roundtrip(rmOp));

    expect(a.containsNode('doomed'), isFalse);
    expect(b.containsNode('doomed'), isFalse);
    expect(snapshotOf(a), equals(snapshotOf(b)));
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Test 7 — JSON wire roundtrip preserves all op types end-to-end.
  //          Catches regressions where toJson/fromJson silently drop fields.
  // ───────────────────────────────────────────────────────────────────────────

  test('JSON wire roundtrip preserves every op type', () {
    final a = CRDTSceneGraph(localPeerId: 'peer_a');
    final b = CRDTSceneGraph(localPeerId: 'peer_b');

    final ops = <CRDTOperation>[
      a.addNode(
        nodeId: 'x',
        nodeType: 'shape',
        parentId: 'root',
        sortIndex: 3,
        properties: {'color': '#123456', 'opacity': 0.7},
      ),
      a.setProperty('x', 'opacity', 0.42),
      a.moveNode('x', newParentId: 'group_1', newSortIndex: 9),
      a.removeNode('x'),
    ];

    for (final op in ops) {
      final wire = jsonEncode(op.toJson());
      final decoded = CRDTOperation.fromJson(
        jsonDecode(wire) as Map<String, dynamic>,
      );
      b.apply(decoded);
    }

    expect(snapshotOf(a), equals(snapshotOf(b)),
        reason: 'Every op type must survive JSON wire encoding');
  });
}
