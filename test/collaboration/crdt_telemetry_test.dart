import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/collaboration/crdt_telemetry.dart';
import 'package:fluera_engine/src/collaboration/scene_graph_crdt.dart';

// =============================================================================
// 📊 CRDTTelemetry — every lifecycle hook fires at the right moment
// =============================================================================

void main() {
  test('local mutations fire onLocalOp once per call', () {
    final tel = RecordingCRDTTelemetry();
    final crdt = CRDTSceneGraph(localPeerId: 'peer_a', telemetry: tel);

    crdt.addNode(nodeId: 'n1', nodeType: 'stroke');
    crdt.setProperty('n1', 'x', 100.0);
    crdt.moveNode('n1', newSortIndex: 5);
    crdt.removeNode('n1');

    expect(tel.localOps, hasLength(4));
    expect(tel.localOps.map((o) => o.type).toList(), equals([
      CRDTOpType.addNode,
      CRDTOpType.setProperty,
      CRDTOpType.moveNode,
      CRDTOpType.removeNode,
    ]));
    expect(tel.remoteOps, isEmpty);
    expect(tel.duplicates, isEmpty);
    expect(tel.orphansBuffered, isEmpty);
  });

  test('apply with foreign peerId fires onRemoteOp', () {
    final telA = RecordingCRDTTelemetry();
    final crdtA = CRDTSceneGraph(localPeerId: 'peer_a', telemetry: telA);
    final crdtB = CRDTSceneGraph(localPeerId: 'peer_b');

    final remote = crdtB.addNode(nodeId: 'r1', nodeType: 'stroke');
    crdtA.apply(remote);

    expect(telA.remoteOps, hasLength(1));
    expect(telA.remoteOps.single.opId, equals(remote.opId));
    expect(telA.localOps, isEmpty);
  });

  test('redelivered op fires onDuplicateOp instead of onRemoteOp', () {
    final telA = RecordingCRDTTelemetry();
    final crdtA = CRDTSceneGraph(localPeerId: 'peer_a', telemetry: telA);
    final crdtB = CRDTSceneGraph(localPeerId: 'peer_b');
    final remote = crdtB.addNode(nodeId: 'r1', nodeType: 'stroke');

    crdtA.apply(remote);
    crdtA.apply(remote); // at-least-once redelivery
    crdtA.apply(remote);

    expect(telA.remoteOps, hasLength(1));
    expect(telA.duplicates, hasLength(2));
  });

  test('out-of-order delivery fires onOrphanBuffered then onOrphanReplayed',
      () {
    final telA = RecordingCRDTTelemetry();
    final crdtA = CRDTSceneGraph(localPeerId: 'peer_a', telemetry: telA);
    final crdtB = CRDTSceneGraph(localPeerId: 'peer_b');

    final addOp = crdtB.addNode(nodeId: 'r1', nodeType: 'stroke');
    final propOp = crdtB.setProperty('r1', 'x', 42.0);

    // Wire delivers prop BEFORE add.
    crdtA.apply(propOp);
    expect(telA.orphansBuffered, hasLength(1));
    expect(telA.remoteOps, isEmpty);

    crdtA.apply(addOp);
    expect(telA.orphanReplays, hasLength(1));
    expect(telA.orphanReplays.single.nodeId, equals('r1'));
    expect(telA.orphanReplays.single.count, equals(1));
    // The addNode itself is a remote op; the replayed orphan is dispatched
    // internally and does NOT re-fire onRemoteOp (it counts as state
    // dispatch, not "first time we saw this op").
    expect(telA.remoteOps, hasLength(1));
  });

  test('CRDTTelemetry.noop is a const tear-off (no allocation)', () {
    expect(identical(CRDTTelemetry.noop, CRDTTelemetry.noop), isTrue);
  });
}
