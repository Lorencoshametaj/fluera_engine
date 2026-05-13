import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/collaboration/crdt_scene_graph_observer.dart';
import 'package:fluera_engine/src/collaboration/scene_graph_crdt.dart';
import 'package:fluera_engine/src/core/scene_graph/scene_graph.dart';

import '../helpers/test_helpers.dart';

// =============================================================================
// 🔌 CRDT ↔ SceneGraph wiring
//
// Validates the single-point-of-capture promise of T0.2: every scene graph
// mutation produces a CRDTOperation, and replaying those operations on a
// remote peer's CRDT converges to the same state as the local one.
// =============================================================================

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  group('CRDTSceneGraphObserver — local capture', () {
    test('onNodeAdded produces an addNode op with serialized properties', () {
      final crdt = CRDTSceneGraph(localPeerId: 'peer_a');
      final ops = <CRDTOperation>[];
      final observer = CRDTSceneGraphObserver(crdt, onLocalOperation: ops.add);

      final sg = SceneGraph();
      sg.addObserver(observer);

      final node = testStrokeNode(id: 'stroke_1');
      sg.notifyNodeAdded(node, 'layer_root');

      expect(ops, hasLength(1));
      expect(ops.single.type, equals(CRDTOpType.addNode));
      expect(ops.single.nodeId, equals('stroke_1'));
      expect(crdt.containsNode('stroke_1'), isTrue);
      expect(crdt.nodeState('stroke_1')?.parentId.value,
          equals('layer_root'));
    });

    test('onNodeRemoved tombstones the node and emits removeNode op', () {
      final crdt = CRDTSceneGraph(localPeerId: 'peer_a');
      final ops = <CRDTOperation>[];
      final observer = CRDTSceneGraphObserver(crdt, onLocalOperation: ops.add);

      final sg = SceneGraph();
      sg.addObserver(observer);

      final node = testStrokeNode(id: 'stroke_1');
      sg.notifyNodeAdded(node, 'layer_root');
      sg.notifyNodeRemoved(node, 'layer_root');

      expect(ops, hasLength(2));
      expect(ops.last.type, equals(CRDTOpType.removeNode));
      expect(crdt.containsNode('stroke_1'), isFalse);
    });

    test('onNodeChanged emits setProperty when value is in compact JSON', () {
      final crdt = CRDTSceneGraph(localPeerId: 'peer_a');
      final ops = <CRDTOperation>[];
      final observer = CRDTSceneGraphObserver(crdt, onLocalOperation: ops.add);

      final sg = SceneGraph();
      sg.addObserver(observer);

      final node = testStrokeNode(id: 'stroke_1');
      sg.notifyNodeAdded(node, 'layer_root');
      ops.clear();

      // Mutate then notify — name is always serialized by baseToJson.
      node.name = 'renamed-stroke';
      sg.notifyNodeChanged(node, 'name');
      sg.flushPendingChanges();

      expect(ops, hasLength(1));
      expect(ops.single.type, equals(CRDTOpType.setProperty));
      expect(ops.single.payload['property'], equals('name'));
      expect(ops.single.payload['value'], equals('renamed-stroke'));
      expect(
        crdt.nodeState('stroke_1')?.getProperty('name'),
        equals('renamed-stroke'),
      );
    });

    test(
        'onNodeChanged with default-elided value drops without resolver '
        '(documented limitation)', () {
      final crdt = CRDTSceneGraph(localPeerId: 'peer_a');
      final ops = <CRDTOperation>[];
      final observer = CRDTSceneGraphObserver(crdt, onLocalOperation: ops.add);

      final sg = SceneGraph();
      sg.addObserver(observer);

      final node = testStrokeNode(id: 'stroke_1');
      sg.notifyNodeAdded(node, 'layer_root');
      ops.clear();

      // opacity == 1.0 is elided from baseToJson — change must not emit
      // a stale-null setProperty.
      node.opacity = 1.0;
      sg.notifyNodeChanged(node, 'opacity');
      sg.flushPendingChanges();

      expect(ops, isEmpty);
    });

    test(
        'onNodeChanged with custom readProperty resolver captures '
        'compact-elided values', () {
      final crdt = CRDTSceneGraph(localPeerId: 'peer_a');
      final ops = <CRDTOperation>[];
      final observer = CRDTSceneGraphObserver(
        crdt,
        onLocalOperation: ops.add,
        readProperty: (node, property) {
          if (property == 'opacity') return node.opacity;
          return node.toJson()[property];
        },
      );

      final sg = SceneGraph();
      sg.addObserver(observer);

      final node = testStrokeNode(id: 'stroke_1');
      sg.notifyNodeAdded(node, 'layer_root');
      ops.clear();

      node.opacity = 1.0;
      sg.notifyNodeChanged(node, 'opacity');
      sg.flushPendingChanges();

      expect(ops, hasLength(1));
      expect(ops.single.payload['value'], equals(1.0));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('CRDTSceneGraphObserver — remote convergence', () {
    test(
        'mutations on local SceneGraph propagate to remote peer via captured '
        'ops', () {
      // Peer A: scene graph + observer + CRDT.
      final crdtA = CRDTSceneGraph(localPeerId: 'peer_a');
      final wire = <CRDTOperation>[];
      final observerA =
          CRDTSceneGraphObserver(crdtA, onLocalOperation: wire.add);
      final sgA = SceneGraph();
      sgA.addObserver(observerA);

      // Peer B: receives ops only.
      final crdtB = CRDTSceneGraph(localPeerId: 'peer_b');

      // Sequence of local mutations on A.
      final stroke = testStrokeNode(id: 'stroke_1');
      sgA.notifyNodeAdded(stroke, 'layer_root');

      stroke.name = 'first';
      sgA.notifyNodeChanged(stroke, 'name');
      sgA.flushPendingChanges();

      final shape = testShapeNode(id: 'shape_1');
      sgA.notifyNodeAdded(shape, 'layer_root');

      sgA.notifyNodeRemoved(stroke, 'layer_root');

      // Replay every captured op on B in FIFO order.
      for (final op in wire) {
        crdtB.apply(op);
      }

      // Observable convergence.
      expect(crdtB.containsNode('stroke_1'), isFalse,
          reason: 'stroke_1 was removed on A');
      expect(crdtB.containsNode('shape_1'), isTrue,
          reason: 'shape_1 must replicate to B');
      expect(crdtA.liveNodeIds, equals(crdtB.liveNodeIds));
      expect(crdtA.nodeState('shape_1')?.parentId.value,
          equals(crdtB.nodeState('shape_1')?.parentId.value));
    });

    test('multi-peer interleave: B mutates locally too, both converge', () {
      final crdtA = CRDTSceneGraph(localPeerId: 'peer_a');
      final crdtB = CRDTSceneGraph(localPeerId: 'peer_b');
      final wireA = <CRDTOperation>[];
      final wireB = <CRDTOperation>[];

      final sgA = SceneGraph()
        ..addObserver(
            CRDTSceneGraphObserver(crdtA, onLocalOperation: wireA.add));
      final sgB = SceneGraph()
        ..addObserver(
            CRDTSceneGraphObserver(crdtB, onLocalOperation: wireB.add));

      // Concurrent mutations on each peer.
      final fromA = testStrokeNode(id: 'a_stroke');
      sgA.notifyNodeAdded(fromA, 'root');
      final fromB = testShapeNode(id: 'b_shape');
      sgB.notifyNodeAdded(fromB, 'root');

      // Cross-apply.
      for (final op in wireA) {
        crdtB.apply(op);
      }
      for (final op in wireB) {
        crdtA.apply(op);
      }

      expect(crdtA.liveNodeIds, equals(crdtB.liveNodeIds));
      expect(crdtA.containsNode('a_stroke'), isTrue);
      expect(crdtA.containsNode('b_shape'), isTrue);
    });
  });
}
