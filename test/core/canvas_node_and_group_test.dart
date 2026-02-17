import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/nodes/group_node.dart';
import 'package:nebula_engine/src/core/nodes/layer_node.dart';
import 'package:nebula_engine/src/core/scene_graph/canvas_node.dart';
import 'package:nebula_engine/src/core/scene_graph/node_visitor.dart';

/// Concrete leaf node for testing (CanvasNode is abstract).
class _TestNode extends CanvasNode {
  final Rect _bounds;

  _TestNode({
    required super.id,
    super.name = '',
    Rect bounds = Rect.zero,
    super.opacity,
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
  // =========================================================================
  // CanvasNode
  // =========================================================================

  group('CanvasNode', () {
    // ── Construction ───────────────────────────────────────────────────

    group('construction', () {
      test('creates with required fields', () {
        final node = _TestNode(id: 'n1', name: 'Test');
        expect(node.id, 'n1');
        expect(node.name, 'Test');
        expect(node.opacity, 1.0);
        expect(node.isVisible, isTrue);
        expect(node.isLocked, isFalse);
        expect(node.parent, isNull);
      });

      test('clamps opacity to 0-1', () {
        final over = _TestNode(id: 'n', opacity: 2.0);
        expect(over.opacity, 1.0);

        final under = _TestNode(id: 'n2', opacity: -0.5);
        expect(under.opacity, 0.0);
      });

      test('opacity setter clamps', () {
        final node = _TestNode(id: 'n');
        node.opacity = 1.5;
        expect(node.opacity, 1.0);
        node.opacity = -1.0;
        expect(node.opacity, 0.0);
      });

      test('identity check fails for empty id', () {
        expect(() => _TestNode(id: ''), throwsA(isA<AssertionError>()));
      });
    });

    // ── Transform ──────────────────────────────────────────────────────

    group('transform', () {
      test('initial localTransform is identity', () {
        final node = _TestNode(id: 'n');
        final t = node.localTransform;
        expect(t.getTranslation().x, 0.0);
        expect(t.getTranslation().y, 0.0);
      });

      test('translate modifies position', () {
        final node = _TestNode(id: 'n');
        node.translate(10.0, 20.0);
        final pos = node.position;
        expect(pos.dx, closeTo(10.0, 0.01));
        expect(pos.dy, closeTo(20.0, 0.01));
      });

      test('setPosition sets absolute position', () {
        final node = _TestNode(id: 'n');
        node.translate(5.0, 5.0);
        node.setPosition(100.0, 200.0);
        final pos = node.position;
        expect(pos.dx, closeTo(100.0, 0.01));
        expect(pos.dy, closeTo(200.0, 0.01));
      });

      test('worldTransform without parent equals localTransform', () {
        final node = _TestNode(id: 'n');
        node.translate(10, 20);
        final wt = node.worldTransform;
        expect(wt.getTranslation().x, closeTo(10.0, 0.01));
        expect(wt.getTranslation().y, closeTo(20.0, 0.01));
      });
    });

    // ── Hit Testing ────────────────────────────────────────────────────

    group('hitTest', () {
      test('returns true for point inside bounds', () {
        final node = _TestNode(
          id: 'n',
          bounds: const Rect.fromLTWH(0, 0, 100, 100),
        );
        expect(node.hitTest(const Offset(50, 50)), isTrue);
      });

      test('returns false for point outside bounds', () {
        final node = _TestNode(
          id: 'n',
          bounds: const Rect.fromLTWH(0, 0, 100, 100),
        );
        expect(node.hitTest(const Offset(150, 150)), isFalse);
      });

      test('returns false when not visible', () {
        final node = _TestNode(
          id: 'n',
          bounds: const Rect.fromLTWH(0, 0, 100, 100),
          isVisible: false,
        );
        expect(node.hitTest(const Offset(50, 50)), isFalse);
      });
    });

    // ── toString ───────────────────────────────────────────────────────

    group('toString', () {
      test('includes node id', () {
        final node = _TestNode(id: 'my-node');
        final str = node.toString();
        expect(str, contains('my-node'));
      });
    });
  });

  // =========================================================================
  // GroupNode
  // =========================================================================

  group('GroupNode', () {
    late GroupNode groupNode;

    setUp(() {
      groupNode = GroupNode(id: 'g1', name: 'Group');
    });

    // ── Initial State ──────────────────────────────────────────────────

    group('initial state', () {
      test('starts empty', () {
        expect(groupNode.isEmpty, isTrue);
        expect(groupNode.childCount, 0);
        expect(groupNode.children, isEmpty);
      });
    });

    // ── Add / Remove ───────────────────────────────────────────────────

    group('add / remove', () {
      test('add increases child count', () {
        groupNode.add(_TestNode(id: 'c1'));
        expect(groupNode.childCount, 1);
        expect(groupNode.isEmpty, isFalse);
      });

      test('add sets parent on child', () {
        final child = _TestNode(id: 'c1');
        groupNode.add(child);
        expect(child.parent, same(groupNode));
      });

      test('insertAt places child at correct index', () {
        groupNode.add(_TestNode(id: 'c1'));
        groupNode.add(_TestNode(id: 'c3'));
        groupNode.insertAt(1, _TestNode(id: 'c2'));
        expect(groupNode.children[1].id, 'c2');
      });

      test('remove removes child and clears parent', () {
        final child = _TestNode(id: 'c1');
        groupNode.add(child);
        final removed = groupNode.remove(child);
        expect(removed, isTrue);
        expect(groupNode.childCount, 0);
        expect(child.parent, isNull);
      });

      test('remove returns false for unknown child', () {
        final unknown = _TestNode(id: 'unknown');
        expect(groupNode.remove(unknown), isFalse);
      });

      test('removeById finds and removes child', () {
        groupNode.add(_TestNode(id: 'c1'));
        final removed = groupNode.removeById('c1');
        expect(removed, isNotNull);
        expect(removed!.id, 'c1');
        expect(groupNode.childCount, 0);
      });

      test('removeById returns null for unknown id', () {
        expect(groupNode.removeById('unknown'), isNull);
      });

      test('removeAt removes correct child', () {
        groupNode.add(_TestNode(id: 'c1'));
        groupNode.add(_TestNode(id: 'c2'));
        final removed = groupNode.removeAt(0);
        expect(removed.id, 'c1');
        expect(groupNode.childCount, 1);
      });

      test('clear removes all children', () {
        groupNode.add(_TestNode(id: 'c1'));
        groupNode.add(_TestNode(id: 'c2'));
        groupNode.add(_TestNode(id: 'c3'));
        groupNode.clear();
        expect(groupNode.childCount, 0);
      });

      test('clear nullifies parent on all children', () {
        final c1 = _TestNode(id: 'c1');
        final c2 = _TestNode(id: 'c2');
        groupNode.add(c1);
        groupNode.add(c2);
        groupNode.clear();
        expect(c1.parent, isNull);
        expect(c2.parent, isNull);
      });
    });

    // ── Reorder ────────────────────────────────────────────────────────

    group('reorder', () {
      test('moves child from old to new index', () {
        groupNode.add(_TestNode(id: 'a'));
        groupNode.add(_TestNode(id: 'b'));
        groupNode.add(_TestNode(id: 'c'));
        groupNode.reorder(0, 3); // move 'a' to end
        expect(groupNode.children[2].id, 'a');
      });

      test('no-op when oldIndex == newIndex', () {
        groupNode.add(_TestNode(id: 'a'));
        groupNode.add(_TestNode(id: 'b'));
        groupNode.reorder(0, 0);
        expect(groupNode.children[0].id, 'a');
      });
    });

    // ── Query ──────────────────────────────────────────────────────────

    group('query', () {
      test('findChild returns direct child by id', () {
        groupNode.add(_TestNode(id: 'c1'));
        expect(groupNode.findChild('c1'), isNotNull);
        expect(groupNode.findChild('unknown'), isNull);
      });

      test('findDescendant finds nested child', () {
        final subGroup = GroupNode(id: 'sub');
        subGroup.add(_TestNode(id: 'deep'));
        groupNode.add(subGroup);
        expect(groupNode.findDescendant('deep'), isNotNull);
      });

      test('findDescendant returns null when not found', () {
        expect(groupNode.findDescendant('nowhere'), isNull);
      });

      test('indexOf returns correct index', () {
        final child = _TestNode(id: 'c1');
        groupNode.add(child);
        expect(groupNode.indexOf(child), 0);
      });

      test('indexOf returns -1 for unknown child', () {
        expect(groupNode.indexOf(_TestNode(id: 'unknown')), -1);
      });

      test('indexOfById returns correct index', () {
        groupNode.add(_TestNode(id: 'c1'));
        groupNode.add(_TestNode(id: 'c2'));
        expect(groupNode.indexOfById('c2'), 1);
      });

      test('childrenOfType filters by type', () {
        groupNode.add(_TestNode(id: 't1'));
        groupNode.add(GroupNode(id: 'g2'));
        groupNode.add(_TestNode(id: 't2'));
        final testNodes = groupNode.childrenOfType<_TestNode>();
        expect(testNodes.length, 2);
      });
    });

    // ── Cycle Prevention ───────────────────────────────────────────────

    group('cycle prevention', () {
      test('cannot add self as child', () {
        expect(() => groupNode.add(groupNode), throwsStateError);
      });

      test('cannot add ancestor as child', () {
        final parent = GroupNode(id: 'parent');
        parent.add(groupNode);
        expect(() => groupNode.add(parent), throwsStateError);
      });
    });

    // ── Bounds ─────────────────────────────────────────────────────────

    group('bounds', () {
      test('empty group has Rect.zero bounds', () {
        expect(groupNode.localBounds, Rect.zero);
      });
    });

    // ── Iteration ──────────────────────────────────────────────────────

    group('iteration', () {
      test('allDescendants returns all nodes depth-first', () {
        final subGroup = GroupNode(id: 'sub');
        subGroup.add(_TestNode(id: 'deep'));
        groupNode.add(_TestNode(id: 'c1'));
        groupNode.add(subGroup);
        final all = groupNode.allDescendants.toList();
        expect(all.length, 3); // c1, sub, deep
      });
    });

    // ── Serialization ──────────────────────────────────────────────────

    group('serialization', () {
      test('toJson includes nodeType and children', () {
        groupNode.add(_TestNode(id: 'c1'));
        final json = groupNode.toJson();
        expect(json['nodeType'], 'group');
        expect((json['children'] as List).length, 1);
      });
    });

    // ── Unmodifiable Children ──────────────────────────────────────────

    group('unmodifiable children', () {
      test('children list is unmodifiable', () {
        groupNode.add(_TestNode(id: 'c1'));
        expect(
          () => groupNode.children.add(_TestNode(id: 'hack')),
          throwsUnsupportedError,
        );
      });
    });
  });

  // =========================================================================
  // LayerNode
  // =========================================================================

  group('LayerNode', () {
    late LayerNode layer;

    setUp(() {
      layer = LayerNode(id: 'layer-1', name: 'Layer 1');
    });

    group('typed element access', () {
      test('starts with empty typed lists', () {
        expect(layer.strokes, isEmpty);
        expect(layer.shapes, isEmpty);
        expect(layer.texts, isEmpty);
        expect(layer.images, isEmpty);
        expect(layer.elementCount, 0);
      });
    });

    group('toJson', () {
      test('includes layer nodeType', () {
        final json = layer.toJson();
        expect(json['nodeType'], 'layer');
      });
    });
  });
}
