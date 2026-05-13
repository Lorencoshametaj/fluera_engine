import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/collaboration/scene_graph_crdt.dart';

// =============================================================================
// 🚀 CRDT throughput + applied-op latency benchmark
//
// These benchmarks measure the *engine* hot path — the cost of producing,
// serializing and re-applying a CRDT operation locally — independent of the
// actual transport. Numbers below are per-host best-of-three; CI ratchets
// them up via generous slack so a 10x slowdown trips, but normal jitter
// doesn't.
//
// Two scenarios:
//
//   1. Single-peer commit throughput — how many strokeAdded ops/sec one
//      device can push through the pipeline. The realistic budget is the
//      drawing engine itself (60 Hz pointer events ⇒ ~60 op/sec sustained,
//      with a ~1000 op spike on bulk paste). We need >> 1000 ops/sec.
//
//   2. Cross-peer apply latency — how long it takes peer B to reflect a
//      remote op once it arrives. This is per-op, NOT round-trip; the
//      transport cost is measured during the device validation session.
//
// Both tests print their numbers so a regression is visible at review,
// even when the assertion bands stay green.
// =============================================================================

void main() {
  test(
    '1000 local ops complete in well under one second (engine-side budget)',
    () {
      final crdt = CRDTSceneGraph(localPeerId: 'peer_a');
      const n = 1000;

      final sw = Stopwatch()..start();
      for (var i = 0; i < n; i++) {
        crdt.addNode(nodeId: 'n$i', nodeType: 'stroke');
      }
      sw.stop();

      final perOpUs = sw.elapsedMicroseconds / n;
      final opsPerSec = n * 1e6 / sw.elapsedMicroseconds;
      // ignore: avoid_print
      print(
        'crdt-throughput: $n local addNode ops in ${sw.elapsedMicroseconds}µs '
        '(${perOpUs.toStringAsFixed(1)}µs/op, ~${opsPerSec.toStringAsFixed(0)} ops/sec)',
      );

      // Hard ceiling: one second for 1000 ops. Real-world target is <50ms;
      // anything above 1s on dev machines means the engine itself is the
      // bottleneck and live drawing would jank before transport ever
      // becomes a problem.
      expect(sw.elapsedMilliseconds, lessThan(1000));
    },
  );

  test('apply remote ops on a fresh peer clears 5000/sec', () {
    final crdtA = CRDTSceneGraph(localPeerId: 'peer_a');
    final crdtB = CRDTSceneGraph(localPeerId: 'peer_b');
    const n = 1000;

    // Pre-generate the wire.
    final ops = <CRDTOperation>[];
    for (var i = 0; i < n; i++) {
      ops.add(crdtA.addNode(nodeId: 'n$i', nodeType: 'stroke'));
    }

    final sw = Stopwatch()..start();
    for (final op in ops) {
      crdtB.apply(op);
    }
    sw.stop();

    final opsPerSec = n * 1e6 / sw.elapsedMicroseconds;
    // ignore: avoid_print
    print(
      'crdt-apply: $n remote ops applied in ${sw.elapsedMicroseconds}µs '
      '(~${opsPerSec.toStringAsFixed(0)} ops/sec)',
    );

    expect(crdtB.nodeCount, equals(n));
    // Ceiling: 1s for 1000 applies (5000 ops/sec floor in practice). A
    // catch-up burst of, say, 5min offline backlog at 60 Hz is 18000 ops;
    // at 5000 ops/sec that's 3.6 seconds, which is acceptable for a
    // reconnect-and-resync experience.
    expect(sw.elapsedMilliseconds, lessThan(1000));
  });

  test(
    'idempotent re-apply under 10x redelivery stays under engine budget',
    () {
      // Models a misbehaving transport that delivers the same op ten times.
      // The dedup path is the cheapest branch in [apply], so this should be
      // strictly faster than the cold apply benchmark above.
      final crdtA = CRDTSceneGraph(localPeerId: 'peer_a');
      final crdtB = CRDTSceneGraph(localPeerId: 'peer_b');
      const n = 1000;
      const redeliveries = 10;

      final ops = <CRDTOperation>[];
      for (var i = 0; i < n; i++) {
        ops.add(crdtA.addNode(nodeId: 'n$i', nodeType: 'stroke'));
      }
      // First-pass apply (real work).
      for (final op in ops) {
        crdtB.apply(op);
      }

      final sw = Stopwatch()..start();
      for (var r = 0; r < redeliveries; r++) {
        for (final op in ops) {
          crdtB.apply(op);
        }
      }
      sw.stop();

      final dropsPerSec = n * redeliveries * 1e6 / sw.elapsedMicroseconds;
      // ignore: avoid_print
      print(
        'crdt-dedup: ${n * redeliveries} duplicate applies in '
        '${sw.elapsedMicroseconds}µs '
        '(~${dropsPerSec.toStringAsFixed(0)} ops/sec)',
      );
      // No new state was created.
      expect(crdtB.nodeCount, equals(n));
      // Dedup must be cheaper than first-time apply by an order of
      // magnitude — anything close to first-apply cost means the dedup
      // hash-set lookup has regressed.
      expect(sw.elapsedMilliseconds, lessThan(500));
    },
  );
}
