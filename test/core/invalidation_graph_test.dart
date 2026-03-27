import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/scene_graph/invalidation_graph.dart';

void main() {
  late InvalidationGraph graph;

  setUp(() {
    graph = InvalidationGraph();
  });

  tearDown(() {
    graph.dispose();
  });

  group('markDirty', () {
    test('marks a single node dirty for a specific flag', () {
      graph.markDirty('node-1', DirtyFlag.transform);

      expect(graph.isDirty('node-1', DirtyFlag.transform), isTrue);
      expect(graph.isDirty('node-1', DirtyFlag.paint), isFalse);
      expect(graph.hasDirty, isTrue);
      expect(graph.dirtyCount, 1);
    });

    test('marks node dirty for multiple flags', () {
      graph.markDirty('node-1', DirtyFlag.transform);
      graph.markDirty('node-1', DirtyFlag.paint);

      expect(graph.isDirty('node-1', DirtyFlag.transform), isTrue);
      expect(graph.isDirty('node-1', DirtyFlag.paint), isTrue);
      expect(graph.dirtyCount, 1); // still 1 node
    });

    test('cascade rule: transform marks bounds dirty too', () {
      graph.markDirty('node-1', DirtyFlag.transform);

      expect(graph.isDirty('node-1', DirtyFlag.transform), isTrue);
      expect(graph.isDirty('node-1', DirtyFlag.bounds), isTrue);
    });

    test('isAnyDirty returns true for node with any flag', () {
      graph.markDirty('node-1', DirtyFlag.paint);

      expect(graph.isAnyDirty('node-1'), isTrue);
      expect(graph.isAnyDirty('node-2'), isFalse);
    });

    test('markDirtyAll marks all given flags', () {
      graph.markDirtyAll('node-1', [DirtyFlag.paint, DirtyFlag.effects]);

      expect(graph.isDirty('node-1', DirtyFlag.paint), isTrue);
      expect(graph.isDirty('node-1', DirtyFlag.effects), isTrue);
      expect(graph.isDirty('node-1', DirtyFlag.layout), isFalse);
    });
  });

  group('dependency propagation', () {
    test('propagates dirty flag through dependency edge', () {
      graph.addDependency('star', 'label', DirtyFlag.transform);
      graph.markDirty('star', DirtyFlag.transform);

      expect(graph.isDirty('star', DirtyFlag.transform), isTrue);
      expect(graph.isDirty('label', DirtyFlag.transform), isTrue);
    });

    test('propagates through chain: A → B → C', () {
      graph.addDependency('a', 'b', DirtyFlag.layout);
      graph.addDependency('b', 'c', DirtyFlag.layout);
      graph.markDirty('a', DirtyFlag.layout);

      expect(graph.isDirty('a', DirtyFlag.layout), isTrue);
      expect(graph.isDirty('b', DirtyFlag.layout), isTrue);
      expect(graph.isDirty('c', DirtyFlag.layout), isTrue);
    });

    test('does not propagate unrelated flags', () {
      graph.addDependency('a', 'b', DirtyFlag.transform);
      graph.markDirty('a', DirtyFlag.paint);

      expect(graph.isDirty('a', DirtyFlag.paint), isTrue);
      expect(graph.isDirty('b', DirtyFlag.paint), isFalse);
    });

    test('handles circular dependencies without infinite loop', () {
      graph.addDependency('a', 'b', DirtyFlag.paint);
      graph.addDependency('b', 'a', DirtyFlag.paint);
      graph.markDirty('a', DirtyFlag.paint);

      // Should terminate — BFS deduplicates already-dirty flags.
      expect(graph.isDirty('a', DirtyFlag.paint), isTrue);
      expect(graph.isDirty('b', DirtyFlag.paint), isTrue);
    });
  });

  group('collectDirty', () {
    test('collects nodes dirty for a specific flag', () {
      graph.markDirty('a', DirtyFlag.transform);
      graph.markDirty('b', DirtyFlag.paint);
      graph.markDirty('c', DirtyFlag.transform);

      final transforms = graph.collectDirty(DirtyFlag.transform);
      expect(transforms, containsAll(['a', 'c']));
      expect(transforms.contains('b'), isFalse);
    });

    test('collectAllDirty returns all dirty nodes', () {
      graph.markDirty('a', DirtyFlag.transform);
      graph.markDirty('b', DirtyFlag.paint);

      final all = graph.collectAllDirty();
      expect(all, containsAll(['a', 'b']));
    });
  });

  group('dependency management', () {
    test('removeDependency removes specific edge', () {
      graph.addDependency('a', 'b', DirtyFlag.transform);
      graph.removeDependency('a', 'b', DirtyFlag.transform);
      graph.markDirty('a', DirtyFlag.transform);

      expect(graph.isDirty('b', DirtyFlag.transform), isFalse);
    });

    test('removeAllDependencies removes all outgoing edges', () {
      graph.addDependency('a', 'b', DirtyFlag.transform);
      graph.addDependency('a', 'c', DirtyFlag.paint);
      graph.removeAllDependencies('a');
      graph.markDirty('a', DirtyFlag.transform);

      expect(graph.isDirty('b', DirtyFlag.transform), isFalse);
      expect(graph.isDirty('c', DirtyFlag.paint), isFalse);
    });

    test('removeAllDependents removes all incoming edges', () {
      graph.addDependency('a', 'target', DirtyFlag.transform);
      graph.addDependency('b', 'target', DirtyFlag.paint);
      graph.removeAllDependents('target');

      graph.markDirty('a', DirtyFlag.transform);
      graph.markDirty('b', DirtyFlag.paint);

      expect(graph.isDirty('target', DirtyFlag.transform), isFalse);
      expect(graph.isDirty('target', DirtyFlag.paint), isFalse);
    });

    test('removeNode removes dirty state and all edges', () {
      graph.addDependency('a', 'b', DirtyFlag.paint);
      graph.addDependency('c', 'a', DirtyFlag.paint);
      graph.markDirty('a', DirtyFlag.paint);
      graph.removeNode('a');

      expect(graph.isAnyDirty('a'), isFalse);
      expect(graph.edgeCount, 0);
    });

    test('edgeCount tracks edge count correctly', () {
      expect(graph.edgeCount, 0);
      graph.addDependency('a', 'b', DirtyFlag.transform);
      graph.addDependency('a', 'c', DirtyFlag.paint);
      expect(graph.edgeCount, 2);
    });
  });

  group('frame lifecycle', () {
    test('clearAll resets all dirty flags', () {
      graph.markDirty('a', DirtyFlag.transform);
      graph.markDirty('b', DirtyFlag.paint);
      graph.clearAll();

      expect(graph.hasDirty, isFalse);
      expect(graph.dirtyCount, 0);
    });

    test('clearNode clears only one node', () {
      graph.markDirty('a', DirtyFlag.transform);
      graph.markDirty('b', DirtyFlag.paint);
      graph.clearNode('a');

      expect(graph.isAnyDirty('a'), isFalse);
      expect(graph.isAnyDirty('b'), isTrue);
    });
  });

  group('toString', () {
    test('displays dirty and edge count', () {
      graph.markDirty('a', DirtyFlag.paint);
      graph.addDependency('a', 'b', DirtyFlag.paint);

      expect(graph.toString(), contains('dirty: 1'));
      expect(graph.toString(), contains('edges: 1'));
    });
  });
}
