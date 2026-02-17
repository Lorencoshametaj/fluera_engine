import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/nodes/group_node.dart';
import 'package:nebula_engine/src/core/scene_graph/canvas_node.dart';
import 'package:nebula_engine/src/core/scene_graph/node_visitor.dart';
import 'package:nebula_engine/src/systems/dirty_tracker.dart';

/// Concrete leaf node for testing (CanvasNode is abstract).
class _TestNode extends CanvasNode {
  final Rect _bounds;

  _TestNode({
    required super.id,
    Rect bounds = const Rect.fromLTWH(0, 0, 50, 50),
  }) : _bounds = bounds;

  @override
  Rect get localBounds => _bounds;

  @override
  Map<String, dynamic> toJson() => {'id': id, 'nodeType': 'test'};

  @override
  R accept<R>(NodeVisitor<R> visitor) =>
      throw UnimplementedError('not needed for tests');
}

void main() {
  group('DirtyTracker', () {
    late DirtyTracker tracker;

    setUp(() {
      tracker = DirtyTracker();
    });

    // ── Initial State ──────────────────────────────────────────────────

    group('initial state', () {
      test('starts with no dirty nodes', () {
        expect(tracker.hasDirty, isFalse);
        expect(tracker.dirtyCount, 0);
      });
    });

    // ── Registration ───────────────────────────────────────────────────

    group('registration', () {
      test('registerNode makes node available for lookup', () {
        final node = _TestNode(id: 'n1');
        tracker.registerNode(node);
        // Mark it dirty to verify registration worked
        tracker.markDirty(node);
        expect(tracker.isDirty('n1'), isTrue);
      });

      test('unregisterNode removes node and clears dirty flag', () {
        final node = _TestNode(id: 'n1');
        tracker.registerNode(node);
        tracker.markDirty(node);
        tracker.unregisterNode('n1');
        expect(tracker.isDirty('n1'), isFalse);
      });

      test('registerSubtree registers parent and all descendants', () {
        final parent = GroupNode(id: 'g1');
        final child = _TestNode(id: 'c1');
        parent.add(child);
        tracker.registerSubtree(parent);

        tracker.markDirty(child);
        expect(tracker.isDirty('c1'), isTrue);
        // Parent should also be dirty (propagation)
        expect(tracker.isDirty('g1'), isTrue);
      });
    });

    // ── Marking Dirty ──────────────────────────────────────────────────

    group('markDirty', () {
      test('marks node as dirty', () {
        final node = _TestNode(id: 'n1');
        tracker.registerNode(node);
        tracker.markDirty(node);
        expect(tracker.hasDirty, isTrue);
        expect(tracker.isDirty('n1'), isTrue);
        expect(tracker.dirtyCount, 1);
      });

      test('propagates dirty flag to ancestors', () {
        final parent = GroupNode(id: 'g1');
        final child = _TestNode(id: 'c1');
        parent.add(child);
        tracker.registerSubtree(parent);

        tracker.markDirty(child);
        expect(tracker.isDirty('g1'), isTrue);
        expect(tracker.isDirty('c1'), isTrue);
      });

      test('markDirtyById finds registered node and marks it', () {
        final node = _TestNode(id: 'n1');
        tracker.registerNode(node);
        tracker.markDirtyById('n1');
        expect(tracker.isDirty('n1'), isTrue);
      });

      test('markDirtyById does nothing for unregistered node', () {
        tracker.markDirtyById('unknown');
        expect(tracker.hasDirty, isFalse);
      });
    });

    // ── isDirtyLayer ───────────────────────────────────────────────────

    group('isDirtyLayer', () {
      test('returns true when layer itself is dirty', () {
        final layer = GroupNode(id: 'layer');
        tracker.registerNode(layer);
        tracker.markDirty(layer);
        expect(tracker.isDirtyLayer('layer'), isTrue);
      });

      test('returns true when descendant is dirty', () {
        final layer = GroupNode(id: 'layer');
        final child = _TestNode(id: 'c1');
        layer.add(child);
        tracker.registerSubtree(layer);

        tracker.markDirty(child);
        expect(tracker.isDirtyLayer('layer'), isTrue);
      });

      test('returns false when nothing is dirty', () {
        final layer = GroupNode(id: 'layer');
        tracker.registerNode(layer);
        expect(tracker.isDirtyLayer('layer'), isFalse);
      });
    });

    // ── collectDirtyRegion ─────────────────────────────────────────────

    group('collectDirtyRegion', () {
      test('returns Rect.zero when nothing is dirty', () {
        expect(tracker.collectDirtyRegion(), Rect.zero);
      });

      test('returns bounds of single dirty leaf node', () {
        final node = _TestNode(
          id: 'n1',
          bounds: const Rect.fromLTWH(10, 20, 100, 100),
        );
        tracker.registerNode(node);
        tracker.markDirty(node);
        final region = tracker.collectDirtyRegion();
        expect(region, isNot(Rect.zero));
      });

      test('includes old bounds when provided', () {
        final node = _TestNode(
          id: 'n1',
          bounds: const Rect.fromLTWH(100, 100, 50, 50),
        );
        tracker.registerNode(node);
        tracker.markDirty(node, oldBounds: const Rect.fromLTWH(0, 0, 50, 50));
        final region = tracker.collectDirtyRegion();
        // Region should encompass both old and new bounds
        expect(region.left, lessThanOrEqualTo(0));
        expect(region.top, lessThanOrEqualTo(0));
        expect(region.right, greaterThanOrEqualTo(150));
        expect(region.bottom, greaterThanOrEqualTo(150));
      });

      test('caches region on second call', () {
        final node = _TestNode(id: 'n1');
        tracker.registerNode(node);
        tracker.markDirty(node);
        final r1 = tracker.collectDirtyRegion();
        final r2 = tracker.collectDirtyRegion();
        expect(identical(r1, r2), isTrue);
      });
    });

    // ── dirtyLeafIds ───────────────────────────────────────────────────

    group('dirtyLeafIds', () {
      test('excludes group nodes', () {
        final parent = GroupNode(id: 'g1');
        final child = _TestNode(id: 'c1');
        parent.add(child);
        tracker.registerSubtree(parent);
        tracker.markDirty(child); // Also marks parent dirty via propagation

        final leaves = tracker.dirtyLeafIds;
        expect(leaves, contains('c1'));
        expect(leaves, isNot(contains('g1')));
      });
    });

    // ── Clear ──────────────────────────────────────────────────────────

    group('clear', () {
      test('clearAll resets all dirty flags', () {
        final node = _TestNode(id: 'n1');
        tracker.registerNode(node);
        tracker.markDirty(node);
        tracker.clearAll();
        expect(tracker.hasDirty, isFalse);
        expect(tracker.dirtyCount, 0);
      });

      test('clearNode only clears one node', () {
        final n1 = _TestNode(id: 'n1');
        final n2 = _TestNode(id: 'n2');
        tracker.registerNode(n1);
        tracker.registerNode(n2);
        tracker.markDirty(n1);
        tracker.markDirty(n2);
        tracker.clearNode('n1');
        expect(tracker.isDirty('n1'), isFalse);
        expect(tracker.isDirty('n2'), isTrue);
      });
    });

    // ── Dispose ────────────────────────────────────────────────────────

    group('dispose', () {
      test('clears everything', () {
        final node = _TestNode(id: 'n1');
        tracker.registerNode(node);
        tracker.markDirty(node);
        tracker.dispose();
        expect(tracker.hasDirty, isFalse);
        expect(tracker.dirtyCount, 0);
      });
    });
  });
}
