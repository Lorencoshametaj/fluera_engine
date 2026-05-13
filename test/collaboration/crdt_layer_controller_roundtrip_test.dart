import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/collaboration/crdt_layer_controller_applier.dart';
import 'package:fluera_engine/src/collaboration/crdt_layer_controller_observer.dart';
import 'package:fluera_engine/src/collaboration/scene_graph_crdt.dart';
import 'package:fluera_engine/src/layers/layer_controller.dart';

import '../helpers/test_helpers.dart';

// =============================================================================
// 🌐 LayerController ↔ CRDT ↔ LayerController full roundtrip
//
// Two LayerControllers wired through the CRDT layer must converge to the
// same observable state when peer A's mutations are replayed on peer B
// via captured CRDTOperations. This is the closest we can get to a true
// "Validated end-to-end" multi-client check without spinning up a real
// transport.
// =============================================================================

void main() {
  test('strokes added on peer A appear on peer B without re-broadcast loop',
      () {
    final wire = <CRDTOperation>[];

    // Peer A: LayerController + observer + CRDT.
    final crdtA = CRDTSceneGraph(localPeerId: 'peer_a');
    final observerA =
        CRDTLayerControllerObserver(crdtA, onLocalOperation: wire.add);
    final lcA = LayerController()..addMutationObserver(observerA.onMutation);

    // Peer B: LayerController + observer + applier wired to CRDT.
    final crdtB = CRDTSceneGraph(localPeerId: 'peer_b');
    final outboundB = <CRDTOperation>[];
    final observerB =
        CRDTLayerControllerObserver(crdtB, onLocalOperation: outboundB.add);
    final lcB = LayerController()..addMutationObserver(observerB.onMutation);
    final applierB = CRDTToLayerControllerApplier(
      crdt: crdtB,
      layerController: lcB,
      observer: observerB,
    );

    // Peer A draws.
    final s1 = testStroke(id: 's1');
    final s2 = testStroke(id: 's2');
    lcA.addStroke(s1);
    lcA.addStroke(s2);

    // Replay every captured op on peer B.
    for (final op in wire) {
      applierB.applyRemote(op);
    }

    // Peer B's LayerController now mirrors peer A's strokes.
    final aLayer = lcA.activeLayer!;
    final bLayer = lcB.activeLayer!;
    final aIds = aLayer.strokes.map((s) => s.id).toSet();
    final bIds = bLayer.strokes.map((s) => s.id).toSet();
    expect(bIds, equals(aIds),
        reason: 'Peer B must end up with the same strokes as peer A');

    // The applier MUST NOT have triggered new outbound ops on peer B
    // (otherwise we have a re-broadcast loop).
    expect(outboundB, isEmpty,
        reason:
            'Applying remote ops must run with the local observer suspended');
  });

  test('remove on peer A removes on peer B', () {
    final wire = <CRDTOperation>[];
    final crdtA = CRDTSceneGraph(localPeerId: 'peer_a');
    final observerA =
        CRDTLayerControllerObserver(crdtA, onLocalOperation: wire.add);
    final lcA = LayerController()..addMutationObserver(observerA.onMutation);

    final crdtB = CRDTSceneGraph(localPeerId: 'peer_b');
    final observerB = CRDTLayerControllerObserver(crdtB);
    final lcB = LayerController()..addMutationObserver(observerB.onMutation);
    final applierB = CRDTToLayerControllerApplier(
      crdt: crdtB,
      layerController: lcB,
      observer: observerB,
    );

    lcA.addStroke(testStroke(id: 's1'));
    lcA.addStroke(testStroke(id: 's2'));
    for (final op in wire) {
      applierB.applyRemote(op);
    }
    wire.clear();

    lcA.removeStroke('s1');
    for (final op in wire) {
      applierB.applyRemote(op);
    }

    final bIds = lcB.activeLayer!.strokes.map((s) => s.id).toSet();
    expect(bIds, equals({'s2'}));
  });

  test('layerAdded on peer A also creates the layer on peer B', () {
    final wire = <CRDTOperation>[];
    final crdtA = CRDTSceneGraph(localPeerId: 'peer_a');
    final observerA =
        CRDTLayerControllerObserver(crdtA, onLocalOperation: wire.add);
    final lcA = LayerController()..addMutationObserver(observerA.onMutation);

    final crdtB = CRDTSceneGraph(localPeerId: 'peer_b');
    final observerB = CRDTLayerControllerObserver(crdtB);
    final lcB = LayerController()..addMutationObserver(observerB.onMutation);
    final applierB = CRDTToLayerControllerApplier(
      crdt: crdtB,
      layerController: lcB,
      observer: observerB,
    );

    final beforeCount = lcB.layers.length;
    lcA.addLayer(name: 'Sketch');
    for (final op in wire) {
      applierB.applyRemote(op);
    }

    expect(lcB.layers.length, beforeCount + 1,
        reason: 'addLayer on A must produce a matching layer on B');
    expect(lcB.layers.any((l) => l.name == 'Sketch'), isTrue);
  });

  test('redelivery of remote ops is idempotent on peer B', () {
    final wire = <CRDTOperation>[];
    final crdtA = CRDTSceneGraph(localPeerId: 'peer_a');
    final observerA =
        CRDTLayerControllerObserver(crdtA, onLocalOperation: wire.add);
    final lcA = LayerController()..addMutationObserver(observerA.onMutation);

    final crdtB = CRDTSceneGraph(localPeerId: 'peer_b');
    final observerB = CRDTLayerControllerObserver(crdtB);
    final lcB = LayerController()..addMutationObserver(observerB.onMutation);
    final applierB = CRDTToLayerControllerApplier(
      crdt: crdtB,
      layerController: lcB,
      observer: observerB,
    );

    lcA.addStroke(testStroke(id: 's_dup'));

    // At-least-once transport: every op delivered three times.
    for (final op in wire) {
      applierB.applyRemote(op);
      applierB.applyRemote(op);
      applierB.applyRemote(op);
    }

    final ids = lcB.activeLayer!.strokes.map((s) => s.id).toList();
    expect(ids.where((id) => id == 's_dup').length, equals(1),
        reason: 'Idempotent applyRemote must not duplicate strokes');
  });
}
