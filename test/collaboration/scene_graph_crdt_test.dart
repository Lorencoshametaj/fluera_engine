import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/collaboration/scene_graph_crdt.dart';

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  // HybridLogicalClock
  // ───────────────────────────────────────────────────────────────────────────

  group('HybridLogicalClock', () {
    test('monotonically increasing timestamps', () {
      var time = 1000;
      final clock = HybridLogicalClock('peer_1', wallClock: () => time);

      final ts1 = clock.now();
      final ts2 = clock.now();
      final ts3 = clock.now();

      expect(ts2 > ts1, isTrue);
      expect(ts3 > ts2, isTrue);
    });

    test('advances past received remote timestamp', () {
      var time = 1000;
      final clock = HybridLogicalClock('peer_1', wallClock: () => time);

      final local = clock.now();

      // Simulate a remote timestamp far in the future
      final remote = HLCTimestamp(
        physicalMs: 5000,
        counter: 0,
        peerId: 'peer_2',
      );
      clock.receive(remote);

      final afterMerge = clock.now();
      expect(afterMerge > remote, isTrue);
      expect(afterMerge > local, isTrue);
    });

    test('wall clock advancing resets counter', () {
      var time = 1000;
      final clock = HybridLogicalClock('peer_1', wallClock: () => time);

      clock.now(); // counter = 0
      clock.now(); // counter = 1

      time = 2000; // advance wall clock
      final ts = clock.now();
      expect(ts.counter, 0);
      expect(ts.physicalMs, 2000);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // HLCTimestamp
  // ───────────────────────────────────────────────────────────────────────────

  group('HLCTimestamp', () {
    test('ordering: physicalMs first, then counter, then peerId', () {
      final a = HLCTimestamp(physicalMs: 100, counter: 0, peerId: 'a');
      final b = HLCTimestamp(physicalMs: 200, counter: 0, peerId: 'a');
      expect(b > a, isTrue);

      final c = HLCTimestamp(physicalMs: 100, counter: 1, peerId: 'a');
      expect(c > a, isTrue);

      final d = HLCTimestamp(physicalMs: 100, counter: 0, peerId: 'b');
      expect(d > a, isTrue);
    });

    test('equality', () {
      final a = HLCTimestamp(physicalMs: 100, counter: 5, peerId: 'p');
      final b = HLCTimestamp(physicalMs: 100, counter: 5, peerId: 'p');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('JSON roundtrip', () {
      final ts = HLCTimestamp(physicalMs: 12345, counter: 7, peerId: 'peer_x');
      final json = ts.toJson();
      final restored = HLCTimestamp.fromJson(json);
      expect(restored, equals(ts));
    });

    test('zero is older than anything', () {
      final ts = HLCTimestamp(physicalMs: 1, counter: 0, peerId: 'a');
      expect(ts > HLCTimestamp.zero, isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // LWWRegister
  // ───────────────────────────────────────────────────────────────────────────

  group('LWWRegister', () {
    test('set accepts newer timestamp', () {
      final ts1 = HLCTimestamp(physicalMs: 100, counter: 0, peerId: 'a');
      final ts2 = HLCTimestamp(physicalMs: 200, counter: 0, peerId: 'a');
      final reg = LWWRegister<double>(1.0, ts1);

      expect(reg.set(2.0, ts2), isTrue);
      expect(reg.value, 2.0);
    });

    test('set rejects older timestamp', () {
      final ts1 = HLCTimestamp(physicalMs: 200, counter: 0, peerId: 'a');
      final ts2 = HLCTimestamp(physicalMs: 100, counter: 0, peerId: 'a');
      final reg = LWWRegister<double>(1.0, ts1);

      expect(reg.set(2.0, ts2), isFalse);
      expect(reg.value, 1.0);
    });

    test('merge takes later value', () {
      final ts1 = HLCTimestamp(physicalMs: 100, counter: 0, peerId: 'a');
      final ts2 = HLCTimestamp(physicalMs: 200, counter: 0, peerId: 'b');
      final local = LWWRegister<String>('hello', ts1);
      final remote = LWWRegister<String>('world', ts2);

      local.merge(remote);
      expect(local.value, 'world');
    });

    test('JSON roundtrip', () {
      final ts = HLCTimestamp(physicalMs: 100, counter: 0, peerId: 'a');
      final reg = LWWRegister<int>(42, ts);
      final json = reg.toJson((v) => v);
      final restored = LWWRegister<int>.fromJson(
        json,
        (v) => (v as num).toInt(),
      );
      expect(restored.value, 42);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // LWWElementSet
  // ───────────────────────────────────────────────────────────────────────────

  group('LWWElementSet', () {
    test('add and contains', () {
      final set = LWWElementSet<String>();
      final ts = HLCTimestamp(physicalMs: 100, counter: 0, peerId: 'a');
      set.add('node_1', ts);

      expect(set.contains('node_1'), isTrue);
      expect(set.contains('node_2'), isFalse);
      expect(set.length, 1);
    });

    test('remove removes element', () {
      final ts1 = HLCTimestamp(physicalMs: 100, counter: 0, peerId: 'a');
      final ts2 = HLCTimestamp(physicalMs: 200, counter: 0, peerId: 'a');
      final set = LWWElementSet<String>();
      set.add('node_1', ts1);
      set.remove('node_1', ts2);

      expect(set.contains('node_1'), isFalse);
    });

    test('add-bias: concurrent add+remove → add wins on tie', () {
      final ts = HLCTimestamp(physicalMs: 100, counter: 0, peerId: 'a');
      final set = LWWElementSet<String>();
      set.add('node_1', ts);
      set.remove('node_1', ts); // same timestamp

      expect(set.contains('node_1'), isTrue); // add-bias
    });

    test('re-add after remove works', () {
      final ts1 = HLCTimestamp(physicalMs: 100, counter: 0, peerId: 'a');
      final ts2 = HLCTimestamp(physicalMs: 200, counter: 0, peerId: 'a');
      final ts3 = HLCTimestamp(physicalMs: 300, counter: 0, peerId: 'a');
      final set = LWWElementSet<String>();

      set.add('n', ts1);
      set.remove('n', ts2);
      expect(set.contains('n'), isFalse);

      set.add('n', ts3);
      expect(set.contains('n'), isTrue);
    });

    test('merge two sets converges', () {
      final ts1 = HLCTimestamp(physicalMs: 100, counter: 0, peerId: 'a');
      final ts2 = HLCTimestamp(physicalMs: 200, counter: 0, peerId: 'b');

      final setA = LWWElementSet<String>();
      setA.add('x', ts1);

      final setB = LWWElementSet<String>();
      setB.add('y', ts2);

      setA.merge(setB);
      expect(setA.elements, containsAll(['x', 'y']));
    });

    test('gc removes old tombstones', () {
      final ts1 = HLCTimestamp(physicalMs: 100, counter: 0, peerId: 'a');
      final ts2 = HLCTimestamp(physicalMs: 200, counter: 0, peerId: 'a');
      final cutoff = HLCTimestamp(physicalMs: 300, counter: 0, peerId: '');

      final set = LWWElementSet<String>();
      set.add('n', ts1);
      set.remove('n', ts2);

      final removed = set.gc(cutoff);
      expect(removed, 1);
    });

    test('JSON roundtrip', () {
      final ts = HLCTimestamp(physicalMs: 100, counter: 0, peerId: 'a');
      final set = LWWElementSet<String>();
      set.add('node_1', ts);
      set.add('node_2', ts);

      final json = set.toJson((e) => e);
      final restored = LWWElementSet<String>.fromJson(json, (String s) => s);
      expect(restored.elements, containsAll(['node_1', 'node_2']));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // CRDTSceneGraph — full integration
  // ───────────────────────────────────────────────────────────────────────────

  group('CRDTSceneGraph', () {
    test('add node and query', () {
      var time = 1000;
      final graph = CRDTSceneGraph(
        localPeerId: 'peer_1',
        wallClock: () => time++,
      );

      graph.addNode(nodeId: 'n1', nodeType: 'shape');
      expect(graph.containsNode('n1'), isTrue);
      expect(graph.nodeCount, 1);
      expect(graph.nodeState('n1')!.nodeType.value, 'shape');
    });

    test('remove node tombstones it', () {
      var time = 1000;
      final graph = CRDTSceneGraph(
        localPeerId: 'peer_1',
        wallClock: () => time++,
      );

      graph.addNode(nodeId: 'n1', nodeType: 'shape');
      graph.removeNode('n1');
      expect(graph.containsNode('n1'), isFalse);
      expect(graph.nodeCount, 0);
    });

    test('set property updates node state', () {
      var time = 1000;
      final graph = CRDTSceneGraph(
        localPeerId: 'peer_1',
        wallClock: () => time++,
      );

      graph.addNode(nodeId: 'n1', nodeType: 'shape');
      graph.setProperty('n1', 'x', 100.0);
      graph.setProperty('n1', 'y', 200.0);

      expect(graph.nodeState('n1')!.getProperty('x'), 100.0);
      expect(graph.nodeState('n1')!.getProperty('y'), 200.0);
    });

    test('move node updates parent and sort index', () {
      var time = 1000;
      final graph = CRDTSceneGraph(
        localPeerId: 'peer_1',
        wallClock: () => time++,
      );

      graph.addNode(nodeId: 'parent', nodeType: 'group');
      graph.addNode(nodeId: 'child', nodeType: 'shape');
      graph.moveNode('child', newParentId: 'parent', newSortIndex: 1);

      expect(graph.nodeState('child')!.parentId.value, 'parent');
      expect(graph.nodeState('child')!.sortIndex.value, 1);
    });

    test('concurrent operations from two peers converge', () {
      var time = 1000;
      final peerA = CRDTSceneGraph(localPeerId: 'A', wallClock: () => time++);
      final peerB = CRDTSceneGraph(localPeerId: 'B', wallClock: () => time++);

      // Both add a node
      final opA = peerA.addNode(nodeId: 'shared', nodeType: 'text');
      final opB = peerB.addNode(nodeId: 'shared', nodeType: 'text');

      // Peer A sets x=100
      final opAx = peerA.setProperty('shared', 'x', 100.0);

      // Peer B sets y=200 (no conflict — different properties)
      final opBy = peerB.setProperty('shared', 'y', 200.0);

      // Cross-apply
      peerB.apply(opA);
      peerB.apply(opAx);
      peerA.apply(opB);
      peerA.apply(opBy);

      // Both should converge to x=100, y=200
      expect(peerA.nodeState('shared')!.getProperty('x'), 100.0);
      expect(peerA.nodeState('shared')!.getProperty('y'), 200.0);
      expect(peerB.nodeState('shared')!.getProperty('x'), 100.0);
      expect(peerB.nodeState('shared')!.getProperty('y'), 200.0);
    });

    test('operation idempotency — duplicate ops ignored', () {
      var time = 1000;
      final graph = CRDTSceneGraph(
        localPeerId: 'peer_1',
        wallClock: () => time++,
      );

      final op = graph.addNode(nodeId: 'n1', nodeType: 'shape');
      final changes = graph.apply(op); // duplicate
      expect(changes, isEmpty);
    });

    test('merge commutativity — A∪B == B∪A', () {
      var time = 1000;
      final peerA = CRDTSceneGraph(localPeerId: 'A', wallClock: () => time++);
      final peerB = CRDTSceneGraph(localPeerId: 'B', wallClock: () => time++);

      peerA.addNode(nodeId: 'a1', nodeType: 'shape');
      peerB.addNode(nodeId: 'b1', nodeType: 'text');

      // Merge A into B
      final mergeAB = CRDTSceneGraph(
        localPeerId: 'merge',
        wallClock: () => time++,
      );
      mergeAB.mergeState(peerA);
      mergeAB.mergeState(peerB);

      // Merge B into A
      final mergeBA = CRDTSceneGraph(
        localPeerId: 'merge2',
        wallClock: () => time++,
      );
      mergeBA.mergeState(peerB);
      mergeBA.mergeState(peerA);

      // Both should have the same nodes
      expect(mergeAB.liveNodeIds, mergeBA.liveNodeIds);
    });

    test('childrenOf returns sorted children', () {
      var time = 1000;
      final graph = CRDTSceneGraph(
        localPeerId: 'peer_1',
        wallClock: () => time++,
      );

      graph.addNode(nodeId: 'parent', nodeType: 'group');
      graph.addNode(
        nodeId: 'c2',
        nodeType: 'shape',
        parentId: 'parent',
        sortIndex: 2,
      );
      graph.addNode(
        nodeId: 'c1',
        nodeType: 'shape',
        parentId: 'parent',
        sortIndex: 1,
      );
      graph.addNode(
        nodeId: 'c3',
        nodeType: 'shape',
        parentId: 'parent',
        sortIndex: 3,
      );

      final children = graph.childrenOf('parent');
      expect(children, ['c1', 'c2', 'c3']);
    });

    test('JSON roundtrip preserves full state', () {
      var time = 1000;
      final graph = CRDTSceneGraph(
        localPeerId: 'peer_1',
        wallClock: () => time++,
      );

      graph.addNode(nodeId: 'n1', nodeType: 'shape');
      graph.setProperty('n1', 'color', '#ff0000');

      final json = graph.toJson();
      final restored = CRDTSceneGraph.fromJson(json);

      expect(restored.containsNode('n1'), isTrue);
      expect(restored.nodeState('n1')!.getProperty('color'), '#ff0000');
    });

    test('change listener is notified', () {
      var time = 1000;
      final graph = CRDTSceneGraph(
        localPeerId: 'peer_1',
        wallClock: () => time++,
      );

      final changes = <CRDTChange>[];
      graph.addChangeListener(changes.addAll);

      graph.addNode(nodeId: 'n1', nodeType: 'shape');
      expect(changes.length, 1);
      expect(changes.first.type, CRDTChangeType.added);

      graph.setProperty('n1', 'x', 50.0);
      expect(changes.length, 2);
      expect(changes.last.type, CRDTChangeType.propertyChanged);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // CRDTOperation
  // ───────────────────────────────────────────────────────────────────────────

  group('CRDTOperation', () {
    test('JSON roundtrip for all op types', () {
      final ts = HLCTimestamp(physicalMs: 100, counter: 0, peerId: 'p');

      final addOp = CRDTOperation.addNode(
        opId: 'op1',
        nodeId: 'n1',
        nodeType: 'shape',
        timestamp: ts,
        peerId: 'p',
      );
      final addJson = addOp.toJson();
      final restoredAdd = CRDTOperation.fromJson(addJson);
      expect(restoredAdd.type, CRDTOpType.addNode);
      expect(restoredAdd.nodeId, 'n1');

      final removeOp = CRDTOperation.removeNode(
        opId: 'op2',
        nodeId: 'n1',
        timestamp: ts,
        peerId: 'p',
      );
      final removeJson = removeOp.toJson();
      final restoredRemove = CRDTOperation.fromJson(removeJson);
      expect(restoredRemove.type, CRDTOpType.removeNode);

      final propOp = CRDTOperation.setProperty(
        opId: 'op3',
        nodeId: 'n1',
        propertyName: 'x',
        value: 42.0,
        timestamp: ts,
        peerId: 'p',
      );
      final propJson = propOp.toJson();
      final restoredProp = CRDTOperation.fromJson(propJson);
      expect(restoredProp.payload['property'], 'x');
      expect(restoredProp.payload['value'], 42.0);
    });

    test('batch op contains sub-operations', () {
      final ts = HLCTimestamp(physicalMs: 100, counter: 0, peerId: 'p');
      final batch = CRDTOperation.batchOp(
        opId: 'batch1',
        timestamp: ts,
        peerId: 'p',
        operations: [
          CRDTOperation.addNode(
            opId: 'sub1',
            nodeId: 'n1',
            nodeType: 'shape',
            timestamp: ts,
            peerId: 'p',
          ),
          CRDTOperation.addNode(
            opId: 'sub2',
            nodeId: 'n2',
            nodeType: 'text',
            timestamp: ts,
            peerId: 'p',
          ),
        ],
      );

      expect(batch.batch!.length, 2);

      final json = batch.toJson();
      final restored = CRDTOperation.fromJson(json);
      expect(restored.batch!.length, 2);
    });
  });
}
