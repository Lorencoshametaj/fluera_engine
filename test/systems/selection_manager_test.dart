import 'package:nebula_engine/src/core/scene_graph/node_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/nodes/group_node.dart';
import 'package:nebula_engine/src/core/scene_graph/canvas_node.dart';
import 'package:nebula_engine/src/core/scene_graph/node_visitor.dart';
import 'package:nebula_engine/src/systems/selection_manager.dart';

/// Concrete leaf node for testing (CanvasNode is abstract).
class _TestNode extends CanvasNode {
  final Rect _bounds;

  _TestNode({
    required super.id,
    super.name = '',
    Rect bounds = const Rect.fromLTWH(0, 0, 50, 50),
    super.isVisible,
    super.isLocked,
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
  group('SelectionManager', () {
    late SelectionManager manager;

    setUp(() {
      manager = SelectionManager();
    });

    // ── Initial State ──────────────────────────────────────────────────

    group('initial state', () {
      test('starts with empty selection', () {
        expect(manager.selectedNodes, isEmpty);
        expect(manager.count, 0);
        expect(manager.isEmpty, isTrue);
        expect(manager.isSingle, isFalse);
        expect(manager.isMultiple, isFalse);
      });
    });

    // ── Select / Deselect ──────────────────────────────────────────────

    group('select / deselect', () {
      test('select a single node', () {
        final node = _TestNode(id: NodeId('n1'));
        manager.select(node);
        expect(manager.isNotEmpty, isTrue);
        expect(manager.count, 1);
        expect(manager.isSingle, isTrue);
        expect(manager.isSelected('n1'), isTrue);
      });

      test('select clears previous selection', () {
        manager.select(_TestNode(id: NodeId('n1')));
        manager.select(_TestNode(id: NodeId('n2')));
        expect(manager.count, 1);
        expect(manager.isSelected('n1'), isFalse);
        expect(manager.isSelected('n2'), isTrue);
      });

      test('addToSelection adds without clearing', () {
        final n1 = _TestNode(id: NodeId('n1'));
        final n2 = _TestNode(id: NodeId('n2'));
        manager.select(n1);
        manager.addToSelection(n2);
        expect(manager.count, 2);
        expect(manager.isMultiple, isTrue);
      });

      test('toggleSelect adds then removes', () {
        final node = _TestNode(id: NodeId('n1'));
        manager.toggleSelect(node);
        expect(manager.isSelected('n1'), isTrue);
        manager.toggleSelect(node);
        expect(manager.isSelected('n1'), isFalse);
      });

      test('deselect removes specific node', () {
        final n1 = _TestNode(id: NodeId('n1'));
        final n2 = _TestNode(id: NodeId('n2'));
        manager.select(n1);
        manager.addToSelection(n2);
        manager.deselect('n1');
        expect(manager.count, 1);
        expect(manager.isSelected('n2'), isTrue);
      });

      test('clearSelection removes all', () {
        manager.select(_TestNode(id: NodeId('n1')));
        manager.addToSelection(_TestNode(id: NodeId('n2')));
        manager.clearSelection();
        expect(manager.isEmpty, isTrue);
        expect(manager.count, 0);
      });

      test('singleSelected returns the node when one selected', () {
        final node = _TestNode(id: NodeId('n1'));
        manager.select(node);
        expect(manager.singleSelected, same(node));
      });

      test('singleSelected returns null when multiple selected', () {
        manager.selectAll([_TestNode(id: NodeId('a')), _TestNode(id: NodeId('b'))]);
        expect(manager.singleSelected, isNull);
      });
    });

    // ── selectAll ──────────────────────────────────────────────────────

    group('selectAll', () {
      test('selects multiple nodes at once', () {
        final nodes = [
          _TestNode(id: NodeId('a')),
          _TestNode(id: NodeId('b')),
          _TestNode(id: NodeId('c')),
        ];
        manager.selectAll(nodes);
        expect(manager.count, 3);
        expect(manager.isMultiple, isTrue);
      });

      test('replaces previous selection', () {
        manager.select(_TestNode(id: NodeId('old')));
        manager.selectAll([_TestNode(id: NodeId('a')), _TestNode(id: NodeId('b'))]);
        expect(manager.count, 2);
        expect(manager.isSelected('old'), isFalse);
      });
    });

    // ── Marquee Select ─────────────────────────────────────────────────

    group('marqueeSelect', () {
      test('selects nodes inside marquee rect', () {
        final root = GroupNode(id: NodeId('root'));
        root.add(
          _TestNode(id: NodeId('inside'), bounds: const Rect.fromLTWH(10, 10, 30, 30)),
        );
        root.add(
          _TestNode(
            id: NodeId('outside'),
            bounds: const Rect.fromLTWH(200, 200, 30, 30),
          ),
        );

        manager.marqueeSelect(root, const Rect.fromLTWH(0, 0, 100, 100));
        expect(manager.isSelected('inside'), isTrue);
        expect(manager.isSelected('outside'), isFalse);
      });

      test('skips locked nodes', () {
        final root = GroupNode(id: NodeId('root'));
        root.add(
          _TestNode(
            id: NodeId('locked'),
            bounds: const Rect.fromLTWH(10, 10, 30, 30),
            isLocked: true,
          ),
        );

        manager.marqueeSelect(root, const Rect.fromLTWH(0, 0, 100, 100));
        expect(manager.isSelected('locked'), isFalse);
      });

      test('skips invisible nodes', () {
        final root = GroupNode(id: NodeId('root'));
        root.add(
          _TestNode(
            id: NodeId('hidden'),
            bounds: const Rect.fromLTWH(10, 10, 30, 30),
            isVisible: false,
          ),
        );

        manager.marqueeSelect(root, const Rect.fromLTWH(0, 0, 100, 100));
        expect(manager.isSelected('hidden'), isFalse);
      });

      test('additive mode preserves existing selection', () {
        final root = GroupNode(id: NodeId('root'));
        final first = _TestNode(
          id: NodeId('first'),
          bounds: const Rect.fromLTWH(0, 0, 10, 10),
        );
        final second = _TestNode(
          id: NodeId('second'),
          bounds: const Rect.fromLTWH(50, 50, 10, 10),
        );
        root.add(first);
        root.add(second);

        manager.select(first);
        manager.marqueeSelect(
          root,
          const Rect.fromLTWH(45, 45, 20, 20),
          additive: true,
        );
        expect(manager.count, 2);
      });
    });

    // ── Typed Filtering ────────────────────────────────────────────────

    group('typed filtering', () {
      test('selectedOfType filters by runtime type', () {
        final t1 = _TestNode(id: NodeId('t1'));
        final g1 = GroupNode(id: NodeId('g1'));
        manager.select(t1);
        manager.addToSelection(g1);
        final testOnly = manager.selectedOfType<_TestNode>();
        expect(testOnly.length, 1);
        expect(testOnly.first.id, 't1');
      });

      test('removeLockedFromSelection removes locked nodes', () {
        final unlocked = _TestNode(id: NodeId('u'));
        final locked = _TestNode(id: NodeId('l'), isLocked: true);
        manager.select(unlocked);
        manager.addToSelection(locked);
        manager.removeLockedFromSelection();
        expect(manager.count, 1);
        expect(manager.isSelected('u'), isTrue);
      });
    });

    // ── Transforms ─────────────────────────────────────────────────────

    group('transforms', () {
      test('translateAll moves all selected nodes', () {
        final n1 = _TestNode(id: NodeId('n1'));
        final n2 = _TestNode(id: NodeId('n2'));
        manager.selectAll([n1, n2]);
        manager.translateAll(10, 20);
        expect(n1.position.dx, closeTo(10, 0.01));
        expect(n1.position.dy, closeTo(20, 0.01));
        expect(n2.position.dx, closeTo(10, 0.01));
        expect(n2.position.dy, closeTo(20, 0.01));
      });

      test('translateAll skips locked nodes', () {
        final locked = _TestNode(id: NodeId('l'), isLocked: true);
        manager.select(locked);
        manager.translateAll(10, 20);
        expect(locked.position.dx, closeTo(0, 0.01));
      });
    });

    // ── Aggregate Bounds ───────────────────────────────────────────────

    group('aggregate bounds', () {
      test('returns Rect.zero when nothing selected', () {
        expect(manager.aggregateBounds, Rect.zero);
      });
    });

    // ── Serialization ──────────────────────────────────────────────────

    group('serialization', () {
      test('toJson returns selected node IDs', () {
        manager.select(_TestNode(id: NodeId('n1')));
        manager.addToSelection(_TestNode(id: NodeId('n2')));
        final json = manager.toJson();
        expect(json['selectedIds'], isA<List>());
        expect((json['selectedIds'] as List).length, 2);
      });

      test('loadFromJson restores selection', () {
        final n1 = _TestNode(id: NodeId('n1'));
        final n2 = _TestNode(id: NodeId('n2'));
        manager.selectAll([n1, n2]);
        final json = manager.toJson();

        final restored = SelectionManager();
        restored.loadFromJson(json, (id) {
          if (id == 'n1') return n1;
          if (id == 'n2') return n2;
          return null;
        });
        expect(restored.count, 2);
        expect(restored.isSelected('n1'), isTrue);
        expect(restored.isSelected('n2'), isTrue);
      });
    });

    // ── Change Listener ────────────────────────────────────────────────

    group('onSelectionChanged', () {
      test('fires callback on selection change', () {
        int callCount = 0;
        manager.onSelectionChanged = () => callCount++;
        manager.select(_TestNode(id: NodeId('n1')));
        expect(callCount, 1);
      });

      test('fires on clearSelection', () {
        int callCount = 0;
        manager.select(_TestNode(id: NodeId('n1')));
        manager.onSelectionChanged = () => callCount++;
        manager.clearSelection();
        expect(callCount, 1);
      });
    });
  });
}
