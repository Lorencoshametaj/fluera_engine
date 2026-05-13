import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/collaboration/crdt_layer_controller_observer.dart';
import 'package:fluera_engine/src/collaboration/scene_graph_crdt.dart';
import 'package:fluera_engine/src/layers/layer_controller.dart';

import '../helpers/test_helpers.dart';

// =============================================================================
// 🔌 LayerController ↔ CRDT wiring
//
// Validates the single-point-of-capture for the canvas data path: every
// add/update/remove on a [LayerController] surfaces as a [CRDTOperation]
// that can be replayed on a remote peer to converge state.
// =============================================================================

void main() {
  group('CRDTLayerControllerObserver — local capture', () {
    test('addStroke emits one addNode op tagged as a stroke', () {
      final crdt = CRDTSceneGraph(localPeerId: 'peer_a');
      final ops = <CRDTOperation>[];
      final observer =
          CRDTLayerControllerObserver(crdt, onLocalOperation: ops.add);

      final lc = LayerController();
      lc.addMutationObserver(observer.onMutation);

      final stroke = testStroke(id: 'stroke_1');
      lc.addStroke(stroke);

      expect(ops, hasLength(1));
      expect(ops.single.type, equals(CRDTOpType.addNode));
      expect(ops.single.nodeId, equals('stroke_1'));
      expect(ops.single.payload['nodeType'], equals('stroke'));
      expect(crdt.containsNode('stroke_1'), isTrue);
    });

    test('removeStroke emits a removeNode op', () {
      final crdt = CRDTSceneGraph(localPeerId: 'peer_a');
      final ops = <CRDTOperation>[];
      final observer =
          CRDTLayerControllerObserver(crdt, onLocalOperation: ops.add);

      final lc = LayerController()..addMutationObserver(observer.onMutation);

      final stroke = testStroke(id: 'stroke_2');
      lc.addStroke(stroke);
      ops.clear();

      lc.removeStroke('stroke_2');

      expect(ops, hasLength(1));
      expect(ops.single.type, equals(CRDTOpType.removeNode));
      expect(ops.single.nodeId, equals('stroke_2'));
      expect(crdt.containsNode('stroke_2'), isFalse);
    });

    test('addLayer + addStroke produce parent layer + child stroke', () {
      final crdt = CRDTSceneGraph(localPeerId: 'peer_a');
      final ops = <CRDTOperation>[];
      final observer =
          CRDTLayerControllerObserver(crdt, onLocalOperation: ops.add);

      final lc = LayerController()..addMutationObserver(observer.onMutation);

      lc.addLayer(name: 'Sketch');
      final layerId = lc.activeLayer!.id;
      final stroke = testStroke(id: 'stroke_3');
      lc.addStroke(stroke);

      expect(crdt.containsNode(layerId), isTrue,
          reason: 'layerAdded must propagate as CRDT addNode');
      expect(crdt.nodeState('stroke_3')?.parentId.value, equals(layerId),
          reason: 'stroke must be parented to its layer');
    });

    test('runSilently suspends emission during a remote-apply window', () {
      final crdt = CRDTSceneGraph(localPeerId: 'peer_a');
      final ops = <CRDTOperation>[];
      final observer =
          CRDTLayerControllerObserver(crdt, onLocalOperation: ops.add);

      final lc = LayerController()..addMutationObserver(observer.onMutation);

      observer.runSilently(() {
        lc.addStroke(testStroke(id: 'remote_stroke'));
      });

      expect(ops, isEmpty,
          reason: 'Mutations during runSilently must not emit local ops');
      // Sanity: outside the suspend window, emission resumes.
      lc.addStroke(testStroke(id: 'local_stroke'));
      expect(ops, hasLength(1));
      expect(ops.single.nodeId, equals('local_stroke'));
    });

    test('disabling delta tracking silences both emission paths', () {
      final crdt = CRDTSceneGraph(localPeerId: 'peer_a');
      final ops = <CRDTOperation>[];
      final observer =
          CRDTLayerControllerObserver(crdt, onLocalOperation: ops.add);

      final lc = LayerController()
        ..addMutationObserver(observer.onMutation)
        ..enableDeltaTracking = false;

      lc.addStroke(testStroke(id: 'untracked'));

      expect(ops, isEmpty,
          reason: 'enableDeltaTracking=false must suppress mutation emission');
    });
  });

  group('CRDTLayerControllerObserver — remote convergence', () {
    test('peer A drawing replicates to peer B via captured ops', () {
      // Peer A: real LayerController + observer + CRDT.
      final crdtA = CRDTSceneGraph(localPeerId: 'peer_a');
      final wire = <CRDTOperation>[];
      final observerA =
          CRDTLayerControllerObserver(crdtA, onLocalOperation: wire.add);
      final lcA = LayerController()..addMutationObserver(observerA.onMutation);

      // Peer B: only a CRDT (the receiving side merges into it).
      final crdtB = CRDTSceneGraph(localPeerId: 'peer_b');

      // Sequence of mutations.
      lcA.addLayer(name: 'L1');
      final layerId = lcA.activeLayer!.id;
      lcA.addStroke(testStroke(id: 's1'));
      lcA.addStroke(testStroke(id: 's2'));
      lcA.removeStroke('s1');

      for (final op in wire) {
        crdtB.apply(op);
      }

      expect(crdtB.containsNode(layerId), isTrue);
      expect(crdtB.containsNode('s1'), isFalse,
          reason: 's1 was added then removed on A');
      expect(crdtB.containsNode('s2'), isTrue);
      expect(crdtA.liveNodeIds, equals(crdtB.liveNodeIds));
    });

    test('clearActiveLayer fans out into per-element removeNode ops', () {
      final crdtA = CRDTSceneGraph(localPeerId: 'peer_a');
      final wire = <CRDTOperation>[];
      final observerA =
          CRDTLayerControllerObserver(crdtA, onLocalOperation: wire.add);
      final lcA = LayerController()..addMutationObserver(observerA.onMutation);

      lcA.addStroke(testStroke(id: 's1'));
      lcA.addStroke(testStroke(id: 's2'));
      lcA.addStroke(testStroke(id: 's3'));

      // Stream the additions to peer B before the clear so B's HLC is
      // anchored to peer A's timeline (mirrors a live transport).
      final crdtB = CRDTSceneGraph(localPeerId: 'peer_b');
      for (final op in wire) {
        crdtB.apply(op);
      }
      expect(crdtB.containsNode('s1'), isTrue);
      expect(crdtB.containsNode('s2'), isTrue);
      expect(crdtB.containsNode('s3'), isTrue);

      final beforeClear = wire.length;
      lcA.clearActiveLayer();

      final clearOps = wire.sublist(beforeClear);
      expect(clearOps.length, greaterThanOrEqualTo(3),
          reason: 'clearActiveLayer must fan out one removeNode per element');
      final removedIds = clearOps
          .where((op) => op.type == CRDTOpType.removeNode)
          .map((op) => op.nodeId)
          .toSet();
      expect(removedIds, containsAll(['s1', 's2', 's3']));

      for (final op in clearOps) {
        crdtB.apply(op);
      }
      expect(crdtB.containsNode('s1'), isFalse);
      expect(crdtB.containsNode('s2'), isFalse);
      expect(crdtB.containsNode('s3'), isFalse);
    });
  });
}
