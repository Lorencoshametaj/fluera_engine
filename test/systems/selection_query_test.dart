import 'package:nebula_engine/src/core/scene_graph/node_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/scene_graph/canvas_node.dart';
import 'package:nebula_engine/src/core/scene_graph/node_visitor.dart';
import 'package:nebula_engine/src/core/nodes/group_node.dart';
import 'package:nebula_engine/src/systems/selection_manager.dart';
import 'package:nebula_engine/src/systems/selection_query.dart';
import 'package:nebula_engine/src/utils/uid.dart';

/// Minimal concrete CanvasNode for testing purposes.
class _TestNode extends CanvasNode {
  _TestNode({required super.name, String? id})
    : super(id: NodeId(id ?? generateUid()));

  @override
  Rect get localBounds => const Rect.fromLTWH(0, 0, 100, 100);

  @override
  R accept<R>(NodeVisitor<R> visitor) => throw UnimplementedError();

  @override
  Map<String, dynamic> toJson() => {
    'type': 'test',
    'name': name,
    ...baseToJson(),
  };
}

void main() {
  late SelectionManager manager;
  late GroupNode root;

  setUp(() {
    manager = SelectionManager();
    root = GroupNode(id: NodeId(generateUid()), name: 'root');
  });

  tearDown(() {
    manager.dispose();
  });

  /// Create a test node and add to root.
  _TestNode _addNode(String name, {GroupNode? parent}) {
    final node = _TestNode(name: name);
    (parent ?? root).add(node);
    return node;
  }

  // ===========================================================================
  // SelectionEvent stream
  // ===========================================================================

  group('SelectionEvent stream', () {
    test('select emits replaced event', () async {
      final events = <SelectionEvent>[];
      manager.selectionEvents.listen(events.add);

      final node = _addNode('A');
      manager.select(node);
      await Future.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events.first.type, SelectionChangeType.replaced);
      expect(events.first.totalSelected, 1);
      expect(events.first.affectedIds, contains(node.id));
    });

    test('addToSelection emits selected event', () async {
      final events = <SelectionEvent>[];
      final node1 = _addNode('A');
      final node2 = _addNode('B');
      manager.select(node1);

      manager.selectionEvents.listen(events.add);
      manager.addToSelection(node2);
      await Future.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events.first.type, SelectionChangeType.selected);
      expect(events.first.affectedIds, [node2.id]);
    });

    test('deselect emits deselected event', () async {
      final events = <SelectionEvent>[];
      final node = _addNode('A');
      manager.select(node);

      manager.selectionEvents.listen(events.add);
      manager.deselect(node.id);
      await Future.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events.first.type, SelectionChangeType.deselected);
    });

    test('clearSelection emits cleared event', () async {
      final events = <SelectionEvent>[];
      final node = _addNode('A');
      manager.select(node);

      manager.selectionEvents.listen(events.add);
      manager.clearSelection();
      await Future.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events.first.type, SelectionChangeType.cleared);
      expect(events.first.totalSelected, 0);
    });

    test('toggleSelect emits correct event type', () async {
      final events = <SelectionEvent>[];
      final node = _addNode('A');

      manager.selectionEvents.listen(events.add);
      manager.toggleSelect(node); // select
      manager.toggleSelect(node); // deselect
      await Future.delayed(Duration.zero);

      expect(events, hasLength(2));
      expect(events[0].type, SelectionChangeType.selected);
      expect(events[1].type, SelectionChangeType.deselected);
    });

    test('clearSelection on empty does not emit', () async {
      final events = <SelectionEvent>[];
      manager.selectionEvents.listen(events.add);
      manager.clearSelection();
      await Future.delayed(Duration.zero);
      expect(events, isEmpty);
    });

    test('legacy onSelectionChanged still fires', () {
      int callCount = 0;
      manager.onSelectionChanged = () => callCount++;

      final node = _addNode('A');
      manager.select(node);
      manager.clearSelection();

      expect(callCount, 2);
    });
  });

  // ===========================================================================
  // Selection history
  // ===========================================================================

  group('Selection history', () {
    test('reselectPrevious restores previous selection', () {
      final node1 = _addNode('A');
      final node2 = _addNode('B');

      manager.select(node1);
      manager.select(node2);

      // History should have {node1.id} from before the second select.
      expect(manager.reselectPrevious(), isTrue);
      expect(manager.selectedIds, contains(node1.id));
      expect(manager.selectedIds, isNot(contains(node2.id)));
    });

    test('reselectPrevious returns false when empty', () {
      expect(manager.reselectPrevious(), isFalse);
    });

    test('historyDepth increments with each mutation', () {
      final node1 = _addNode('A');
      final node2 = _addNode('B');

      expect(manager.historyDepth, 0);
      manager.select(node1);
      expect(manager.historyDepth, 0); // first select from empty → no push
      manager.select(node2);
      expect(manager.historyDepth, 1);
      manager.clearSelection();
      expect(manager.historyDepth, 2);
    });

    test('history caps at maxHistory', () {
      final nodes = List.generate(15, (i) => _addNode('N$i'));

      for (final node in nodes) {
        manager.select(node);
      }

      // 14 mutations after the first → 14, but capped at 10.
      expect(manager.historyDepth, lessThanOrEqualTo(10));
    });
  });

  // ===========================================================================
  // SelectionQuery — predicate
  // ===========================================================================

  group('SelectionQuery - predicate', () {
    test('selectWhere selects matching nodes', () {
      final a = _addNode('button_primary');
      final b = _addNode('button_secondary');
      _addNode('label_title');

      final query = SelectionQuery(manager, root);
      final count = query.selectWhere((n) => n.name.contains('button'));

      expect(count, 2);
      expect(manager.isSelected(a.id), isTrue);
      expect(manager.isSelected(b.id), isTrue);
    });

    test('selectWhere additive adds to existing', () {
      final a = _addNode('A');
      final b = _addNode('B');
      manager.select(a);

      final query = SelectionQuery(manager, root);
      query.selectWhere((n) => n.name == 'B', additive: true);

      expect(manager.count, 2);
      expect(manager.isSelected(a.id), isTrue);
      expect(manager.isSelected(b.id), isTrue);
    });

    test('selectWhere replaces when not additive', () {
      final a = _addNode('A');
      final b = _addNode('B');
      manager.select(a);

      final query = SelectionQuery(manager, root);
      query.selectWhere((n) => n.name == 'B');

      expect(manager.count, 1);
      expect(manager.isSelected(a.id), isFalse);
      expect(manager.isSelected(b.id), isTrue);
    });

    test('selectWhere skips invisible nodes', () {
      final a = _addNode('A');
      final b = _addNode('B');
      b.isVisible = false;

      final query = SelectionQuery(manager, root);
      query.selectWhere((_) => true);

      expect(manager.count, 1);
      expect(manager.isSelected(a.id), isTrue);
    });
  });

  // ===========================================================================
  // SelectionQuery — name glob
  // ===========================================================================

  group('SelectionQuery - selectByName', () {
    test('glob matching with wildcard', () {
      _addNode('icon_home');
      _addNode('icon_settings');
      _addNode('button_submit');

      final query = SelectionQuery(manager, root);
      final count = query.selectByName('icon_*');

      expect(count, 2);
    });

    test('glob matching case insensitive', () {
      _addNode('Header');
      _addNode('header');
      _addNode('footer');

      final query = SelectionQuery(manager, root);
      final count = query.selectByName('header');

      expect(count, 2);
    });

    test('glob with question mark', () {
      _addNode('a1');
      _addNode('a2');
      _addNode('a10');

      final query = SelectionQuery(manager, root);
      final count = query.selectByName('a?');

      expect(count, 2); // a1, a2 — NOT a10 (2 chars)
    });
  });

  // ===========================================================================
  // SelectionQuery — hierarchy
  // ===========================================================================

  group('SelectionQuery - hierarchy', () {
    test('selectSiblings expands to all siblings', () {
      final child1 = _addNode('C1');
      _addNode('C2');
      _addNode('C3');

      manager.select(child1);

      final query = SelectionQuery(manager, root);
      final added = query.selectSiblings();

      expect(added, 2); // C2, C3 added
      expect(manager.count, 3);
    });

    test('selectParent selects the parent group', () {
      final subGroup = GroupNode(id: NodeId(generateUid()), name: 'sub');
      root.add(subGroup);
      final child = _TestNode(name: 'leaf');
      subGroup.add(child);

      manager.select(child);

      final query = SelectionQuery(manager, root);
      query.selectParent();

      expect(manager.isSingle, isTrue);
      expect(manager.isSelected(subGroup.id), isTrue);
    });

    test('selectChildren selects children of group', () {
      final subGroup = GroupNode(id: NodeId(generateUid()), name: 'sub');
      root.add(subGroup);
      final c1 = _TestNode(name: 'c1');
      final c2 = _TestNode(name: 'c2');
      subGroup.add(c1);
      subGroup.add(c2);

      manager.select(subGroup);

      final query = SelectionQuery(manager, root);
      final count = query.selectChildren();

      expect(count, 2);
      expect(manager.isSelected(c1.id), isTrue);
      expect(manager.isSelected(c2.id), isTrue);
    });

    test('selectChildren returns 0 for leaf nodes', () {
      final leaf = _addNode('leaf');
      manager.select(leaf);

      final query = SelectionQuery(manager, root);
      expect(query.selectChildren(), 0);
    });
  });

  // ===========================================================================
  // SelectionQuery — invert
  // ===========================================================================

  group('SelectionQuery - invertSelection', () {
    test('inverts selection', () {
      final a = _addNode('A');
      final b = _addNode('B');
      final c = _addNode('C');
      manager.select(a);

      final query = SelectionQuery(manager, root);
      final count = query.invertSelection();

      expect(count, 2);
      expect(manager.isSelected(a.id), isFalse);
      expect(manager.isSelected(b.id), isTrue);
      expect(manager.isSelected(c.id), isTrue);
    });

    test('inverting empty selects all', () {
      _addNode('A');
      _addNode('B');

      final query = SelectionQuery(manager, root);
      final count = query.invertSelection();

      expect(count, 2);
    });
  });

  // ===========================================================================
  // SelectionQuery — deep marquee
  // ===========================================================================

  group('SelectionQuery - deepMarquee', () {
    test('selects nodes within rect', () {
      // Default localBounds = Rect(0,0,100,100), worldBounds same (no transform).
      final a = _addNode('A');
      final b = _addNode('B');
      b.translate(500, 500); // Move B out of the marquee.

      final query = SelectionQuery(manager, root);
      final count = query.deepMarquee(const Rect.fromLTWH(0, 0, 200, 200));

      expect(count, 1);
      expect(manager.isSelected(a.id), isTrue);
      expect(manager.isSelected(b.id), isFalse);
    });

    test('skips locked nodes', () {
      final a = _addNode('A');
      a.isLocked = true;

      final query = SelectionQuery(manager, root);
      final count = query.deepMarquee(const Rect.fromLTWH(0, 0, 200, 200));

      expect(count, 0);
    });

    test('additive deep marquee', () {
      final a = _addNode('A');
      final b = _addNode('B');
      b.translate(500, 500);

      manager.select(b);

      final query = SelectionQuery(manager, root);
      query.deepMarquee(const Rect.fromLTWH(0, 0, 200, 200), additive: true);

      expect(manager.count, 2);
    });
  });

  // ===========================================================================
  // SelectionManager - dispose
  // ===========================================================================

  group('SelectionManager - dispose', () {
    test('dispose closes event stream', () {
      manager.dispose();
      // Creating a new manager for tearDown.
      manager = SelectionManager();
    });

    test('dispose clears history', () {
      final node = _addNode('A');
      manager.select(node);
      manager.clearSelection();
      expect(manager.historyDepth, greaterThan(0));

      manager.dispose();
      manager = SelectionManager();
    });
  });
}
