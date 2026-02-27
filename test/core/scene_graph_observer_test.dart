import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/scene_graph/scene_graph_observer.dart';
import 'package:fluera_engine/src/core/scene_graph/canvas_node.dart';
import 'package:fluera_engine/src/core/scene_graph/scene_graph.dart';
import 'package:fluera_engine/src/core/scene_graph/node_id.dart';

import '../helpers/test_helpers.dart';

/// Test observer that records calls for assertions.
class RecordingObserver extends SceneGraphObserver {
  final List<String> log = [];

  @override
  void onNodeAdded(CanvasNode node, String parentId) {
    log.add('added:${node.id}:$parentId');
  }

  @override
  void onNodeRemoved(CanvasNode node, String parentId) {
    log.add('removed:${node.id}:$parentId');
  }

  @override
  void onNodeChanged(CanvasNode node, String property) {
    log.add('changed:${node.id}:$property');
  }

  @override
  void onNodeReordered(String parentId, int oldIndex, int newIndex) {
    log.add('reordered:$parentId:$oldIndex->$newIndex');
  }
}

void main() {
  late SceneGraph sg;
  late RecordingObserver observer;

  setUp(() {
    sg = SceneGraph();
    observer = RecordingObserver();
    sg.addObserver(observer);
  });

  // ===========================================================================
  // Observer notifications
  // ===========================================================================

  group('observer notifications', () {
    test('notifyNodeAdded fires onNodeAdded', () {
      final node = testStrokeNode(id: 'n1');
      sg.notifyNodeAdded(node, 'parent1');

      expect(observer.log, contains('added:n1:parent1'));
    });

    test('notifyNodeRemoved fires onNodeRemoved', () {
      final node = testShapeNode(id: 'n2');
      sg.notifyNodeRemoved(node, 'parent2');

      expect(observer.log, contains('removed:n2:parent2'));
    });

    test('notifyNodeReordered fires onNodeReordered', () {
      sg.notifyNodeReordered('parent3', 0, 2);

      expect(observer.log, contains('reordered:parent3:0->2'));
    });
  });

  // ===========================================================================
  // Multiple observers
  // ===========================================================================

  group('multiple observers', () {
    test('all observers are notified', () {
      final observer2 = RecordingObserver();
      sg.addObserver(observer2);

      final node = testStrokeNode(id: 'n1');
      sg.notifyNodeAdded(node, 'p');

      expect(observer.log, hasLength(1));
      expect(observer2.log, hasLength(1));
    });
  });

  // ===========================================================================
  // Observer removal
  // ===========================================================================

  group('observer removal', () {
    test('removed observer stops receiving notifications', () {
      sg.removeObserver(observer);

      final node = testStrokeNode(id: 'n1');
      sg.notifyNodeAdded(node, 'p');

      expect(observer.log, isEmpty);
    });
  });

  // ===========================================================================
  // Event stream
  // ===========================================================================

  group('event stream', () {
    test('events stream receives NodeAddedEvent', () async {
      final events = <SceneGraphEvent>[];
      final sub = sg.events.listen(events.add);

      final node = testStrokeNode(id: 'e1');
      sg.notifyNodeAdded(node, 'p');

      await Future<void>.delayed(Duration.zero);
      sub.cancel();

      expect(events, hasLength(1));
      expect(events.first, isA<NodeAddedEvent>());
    });

    test('events stream receives NodeRemovedEvent', () async {
      final events = <SceneGraphEvent>[];
      final sub = sg.events.listen(events.add);

      final node = testStrokeNode(id: 'e2');
      sg.notifyNodeRemoved(node, 'p');

      await Future<void>.delayed(Duration.zero);
      sub.cancel();

      expect(events, hasLength(1));
      expect(events.first, isA<NodeRemovedEvent>());
    });
  });

  // ===========================================================================
  // Deferred notifications (transaction support)
  // ===========================================================================

  group('deferred notifications', () {
    test('beginDeferNotifications suppresses immediate dispatch', () {
      sg.beginDeferNotifications();
      final node = testStrokeNode(id: 'd1');
      sg.notifyNodeAdded(node, 'p');

      expect(observer.log, isEmpty);
    });

    test('flushDeferredNotifications dispatches buffered callbacks', () {
      sg.beginDeferNotifications();
      final node = testStrokeNode(id: 'd1');
      sg.notifyNodeAdded(node, 'p');
      sg.notifyNodeRemoved(node, 'p');

      sg.flushDeferredNotifications();

      expect(observer.log, hasLength(2));
      expect(observer.log[0], 'added:d1:p');
      expect(observer.log[1], 'removed:d1:p');
    });

    test('clearDeferredNotifications discards buffered callbacks', () {
      sg.beginDeferNotifications();
      final node = testStrokeNode(id: 'd1');
      sg.notifyNodeAdded(node, 'p');

      sg.clearDeferredNotifications();

      expect(observer.log, isEmpty);
      expect(sg.isDeferringNotifications, false);
    });

    test('deferred property changes are deduplicated', () {
      sg.beginDeferNotifications();
      final node = testStrokeNode(id: 'dup');
      // Same node+property twice — only one callback
      sg.notifyNodeChanged(node, 'opacity');
      sg.notifyNodeChanged(node, 'opacity');

      sg.flushDeferredNotifications();

      expect(observer.log, hasLength(1));
      expect(observer.log[0], 'changed:dup:opacity');
    });

    test('deferred different properties are not deduplicated', () {
      sg.beginDeferNotifications();
      final node = testStrokeNode(id: 'dup');
      sg.notifyNodeChanged(node, 'opacity');
      sg.notifyNodeChanged(node, 'visibility');

      sg.flushDeferredNotifications();

      expect(observer.log, hasLength(2));
    });
  });

  // ===========================================================================
  // Per-frame coalescing
  // ===========================================================================

  group('per-frame coalescing', () {
    test('coalesced changes are dispatched in microtask', () async {
      // Ensure coalescing is on (default)
      expect(sg.coalescingEnabled, true);

      final node = testStrokeNode(id: 'c1');
      sg.notifyNodeChanged(node, 'opacity');
      sg.notifyNodeChanged(node, 'visibility');

      // Not dispatched synchronously
      expect(observer.log, isEmpty);

      // Wait for microtask
      await Future<void>.delayed(Duration.zero);

      expect(observer.log, hasLength(2));
    });

    test('flushPendingChanges dispatches immediately', () {
      final node = testStrokeNode(id: 'c2');
      sg.notifyNodeChanged(node, 'opacity');

      expect(observer.log, isEmpty);

      sg.flushPendingChanges();

      expect(observer.log, hasLength(1));
      expect(observer.log[0], 'changed:c2:opacity');
    });

    test('same property on same node is coalesced', () async {
      final node = testStrokeNode(id: 'c3');
      // Multiple changes to same property coalesce into one
      sg.notifyNodeChanged(node, 'opacity');
      sg.notifyNodeChanged(node, 'opacity');
      sg.notifyNodeChanged(node, 'opacity');

      await Future<void>.delayed(Duration.zero);

      // Set only stores unique values, so 'opacity' appears once
      expect(observer.log, hasLength(1));
    });

    test('disabled coalescing dispatches immediately', () {
      sg.coalescingEnabled = false;
      final node = testStrokeNode(id: 'c4');
      sg.notifyNodeChanged(node, 'opacity');

      expect(observer.log, hasLength(1));
    });
  });
}
