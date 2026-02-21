import 'package:nebula_engine/src/core/scene_graph/node_id.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/scene_graph/scene_graph.dart';
import 'package:nebula_engine/src/core/scene_graph/scene_graph_observer.dart';

import '../helpers/test_helpers.dart';

/// Test observer that records all received events.
class _RecordingObserver extends SceneGraphObserver {
  final List<String> added = [];
  final List<String> removed = [];
  final List<String> changed = [];
  final List<String> reordered = [];

  @override
  void onNodeAdded(node, parentId) => added.add(node.id);

  @override
  void onNodeRemoved(node, parentId) => removed.add(node.id);

  @override
  void onNodeChanged(node, property) => changed.add('${node.id}:$property');

  @override
  void onNodeReordered(parentId, oldIndex, newIndex) =>
      reordered.add('$parentId:$oldIndex→$newIndex');
}

void main() {
  group('Observer coalescing', () {
    late SceneGraph sg;
    late _RecordingObserver observer;

    setUp(() {
      sg = SceneGraph();
      observer = _RecordingObserver();
      sg.addObserver(observer);
      // Ensure coalescing is enabled (default).
      sg.coalescingEnabled = true;
    });

    tearDown(() {
      sg.dispose();
    });

    test('property changes are coalesced into a single microtask', () async {
      final layer = testLayerNode(id: NodeId('L1'));
      sg.addLayer(layer);
      // Clear the 'added' event from addLayer.
      observer.added.clear();
      observer.changed.clear();

      // Fire multiple property changes — they should be coalesced.
      sg.notifyNodeChanged(layer, 'color');
      sg.notifyNodeChanged(layer, 'opacity');
      sg.notifyNodeChanged(layer, 'color'); // duplicate

      // Nothing dispatched yet (buffered).
      expect(observer.changed, isEmpty);

      // Wait for microtask to flush.
      await Future<void>.delayed(Duration.zero);

      // Only unique (node, property) pairs dispatched.
      expect(observer.changed, containsAll(['L1:color', 'L1:opacity']));
      expect(observer.changed.length, 2);
    });

    test('structural changes (add/remove) are dispatched immediately', () {
      final layer = testLayerNode(id: NodeId('L1'));
      sg.addLayer(layer);

      // Add is immediate.
      expect(observer.added, contains('L1'));

      sg.removeLayer('L1');
      // Remove is immediate.
      expect(observer.removed, contains('L1'));
    });

    test('flushPendingChanges forces immediate dispatch', () {
      final layer = testLayerNode(id: NodeId('L1'));
      sg.addLayer(layer);
      observer.changed.clear();

      sg.notifyNodeChanged(layer, 'name');
      expect(observer.changed, isEmpty);

      sg.flushPendingChanges();
      expect(observer.changed, ['L1:name']);
    });

    test('coalescing disabled dispatches immediately', () {
      sg.coalescingEnabled = false;

      final layer = testLayerNode(id: NodeId('L1'));
      sg.addLayer(layer);
      observer.changed.clear();

      sg.notifyNodeChanged(layer, 'color');
      // Dispatched immediately (no coalescing).
      expect(observer.changed, ['L1:color']);
    });

    test('deferred notifications take precedence over coalescing', () async {
      final layer = testLayerNode(id: NodeId('L1'));
      sg.addLayer(layer);
      observer.changed.clear();

      // Transaction deferral.
      sg.beginDeferNotifications();

      sg.notifyNodeChanged(layer, 'color');
      sg.notifyNodeChanged(layer, 'color'); // dedup by transaction

      // Nothing yet.
      expect(observer.changed, isEmpty);

      // Wait a microtask — still nothing (deferred, not coalesced).
      await Future<void>.delayed(Duration.zero);
      expect(observer.changed, isEmpty);

      sg.flushDeferredNotifications();
      // Exactly one (dedup'd by transaction system).
      expect(observer.changed, ['L1:color']);
    });

    test('multiple nodes coalesced correctly', () async {
      final layer = testLayerNode(id: NodeId('L1'));
      final stroke1 = testStrokeNode(id: NodeId('S1'));
      final stroke2 = testStrokeNode(id: NodeId('S2'));
      layer.add(stroke1);
      layer.add(stroke2);
      sg.addLayer(layer);
      observer.changed.clear();

      sg.notifyNodeChanged(stroke1, 'color');
      sg.notifyNodeChanged(stroke2, 'color');
      sg.notifyNodeChanged(stroke1, 'opacity');
      sg.notifyNodeChanged(stroke2, 'opacity');
      sg.notifyNodeChanged(stroke1, 'color'); // duplicate

      expect(observer.changed, isEmpty);

      await Future<void>.delayed(Duration.zero);

      expect(observer.changed.length, 4);
      expect(
        observer.changed,
        containsAll(['S1:color', 'S1:opacity', 'S2:color', 'S2:opacity']),
      );
    });

    test('flushPendingChanges is no-op when nothing pending', () {
      // Should not throw or dispatch anything.
      sg.flushPendingChanges();
      expect(observer.changed, isEmpty);
    });

    test('dispose clears pending changes', () async {
      final layer = testLayerNode(id: NodeId('L1'));
      sg.addLayer(layer);
      sg.notifyNodeChanged(layer, 'color');
      sg.dispose();

      // Wait for microtask — callback should not fire after dispose.
      await Future<void>.delayed(Duration.zero);
      // Observer list was cleared by dispose, so nothing dispatched.
      // This mainly ensures no exceptions are thrown.
    });
  });
}
