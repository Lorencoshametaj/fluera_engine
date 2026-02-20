import 'package:nebula_engine/src/core/scene_graph/node_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/scene_graph/scene_graph.dart';
import 'package:nebula_engine/src/core/scene_graph/scene_graph_observer.dart';
import 'package:nebula_engine/src/core/nodes/layer_node.dart';
import 'package:nebula_engine/src/core/scene_graph/canvas_node.dart';

/// Observer that tries to mutate the graph inside its callback.
class _ReEntrantObserver extends SceneGraphObserver {
  final SceneGraph graph;
  _ReEntrantObserver(this.graph);

  @override
  void onNodeAdded(CanvasNode node, String parentId) {
    // This should throw — re-entrant mutation!
    graph.addLayer(LayerNode(id: NodeId('reentrant')));
  }
}

/// Observer that removes itself during notification.
class _SelfRemovingObserver extends SceneGraphObserver {
  final SceneGraph graph;
  int callCount = 0;
  _SelfRemovingObserver(this.graph);

  @override
  void onNodeAdded(CanvasNode node, String parentId) {
    callCount++;
    graph.removeObserver(this);
  }
}

void main() {
  group('Concurrency Safety', () {
    // =========================================================================
    // Component 1: Re-entrant mutation guard
    // =========================================================================

    test('re-entrant mutation throws StateError', () {
      final graph = SceneGraph();
      graph.addObserver(_ReEntrantObserver(graph));

      expect(() => graph.addLayer(LayerNode(id: NodeId('trigger'))), throwsStateError);
    });

    test('isMutating is false outside mutations', () {
      final graph = SceneGraph();
      expect(graph.isMutating, isFalse);
    });

    test('mutation flag resets after exception', () {
      final graph = SceneGraph();
      final obs = _ReEntrantObserver(graph);
      graph.addObserver(obs);

      try {
        graph.addLayer(LayerNode(id: NodeId('trigger')));
      } catch (_) {}

      // Flag should be reset despite exception — so next mutation works
      expect(graph.isMutating, isFalse);

      // Remove the bad observer so next mutation succeeds
      graph.removeObserver(obs);
      graph.addLayer(LayerNode(id: NodeId('after_error')));
      expect(graph.findLayer('after_error'), isNotNull);
    });

    // =========================================================================
    // Component 2: Iterator-safe observer dispatch
    // =========================================================================

    test('observer can remove itself during notification', () {
      final graph = SceneGraph();
      final obs = _SelfRemovingObserver(graph);
      graph.addObserver(obs);

      // Should not throw ConcurrentModificationError
      graph.addLayer(LayerNode(id: NodeId('l1')));
      expect(obs.callCount, 1);

      // Observer removed itself — shouldn't fire again
      graph.addLayer(LayerNode(id: NodeId('l2')));
      expect(obs.callCount, 1); // Still 1
    });

    // =========================================================================
    // Component 3: Version-stamped reads
    // =========================================================================

    test('snapshotVersion captures current version', () {
      final graph = SceneGraph();
      final v = graph.snapshotVersion();
      expect(v, graph.version);
    });

    test('assertUnchanged passes when no mutation', () {
      final graph = SceneGraph();
      final v = graph.snapshotVersion();
      // Should not throw
      graph.assertUnchanged(v);
    });

    test('assertUnchanged throws after mutation', () {
      final graph = SceneGraph();
      final v = graph.snapshotVersion();
      graph.addLayer(LayerNode(id: NodeId('l1')));

      expect(() => graph.assertUnchanged(v, context: 'test'), throwsStateError);
    });

    test('assertUnchanged error includes context', () {
      final graph = SceneGraph();
      final v = graph.snapshotVersion();
      graph.addLayer(LayerNode(id: NodeId('l1')));

      try {
        graph.assertUnchanged(v, context: 'cloud sync');
        fail('Should have thrown');
      } on StateError catch (e) {
        expect(e.message, contains('cloud sync'));
      }
    });

    // =========================================================================
    // Component 4: toJson serialization safety
    // =========================================================================

    test('toJson works normally outside mutation', () {
      final graph = SceneGraph();
      graph.addLayer(LayerNode(id: NodeId('l1')));
      final json = graph.toJson();
      expect(json, isNotNull);
      expect(json.containsKey('sceneGraph'), isTrue);
    });

    // =========================================================================
    // Version bumps correctly
    // =========================================================================

    test('version increments on each mutation', () {
      final graph = SceneGraph();
      final v0 = graph.version;
      graph.addLayer(LayerNode(id: NodeId('l1')));
      expect(graph.version, v0 + 1);
      graph.addLayer(LayerNode(id: NodeId('l2')));
      expect(graph.version, v0 + 2);
      graph.removeLayer('l1');
      expect(graph.version, v0 + 3);
    });
  });
}
