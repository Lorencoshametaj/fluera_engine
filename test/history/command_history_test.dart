import 'package:fluera_engine/src/core/scene_graph/node_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/nodes/group_node.dart';
import 'package:fluera_engine/src/core/scene_graph/canvas_node.dart';
import 'package:fluera_engine/src/core/scene_graph/node_visitor.dart';
import 'package:fluera_engine/src/history/command_history.dart';

/// Concrete leaf node for testing (CanvasNode is abstract).
class _TestNode extends CanvasNode {
  _TestNode({required super.id, super.name = ''});

  @override
  Rect get localBounds => Rect.zero;

  @override
  Map<String, dynamic> toJson() => {'id': id, 'nodeType': 'test'};

  @override
  R accept<R>(NodeVisitor<R> visitor) =>
      throw UnimplementedError('not needed for tests');
}

void main() {
  // =========================================================================
  // Command base
  // =========================================================================

  group('Command', () {
    test('has a timestamp', () {
      final cmd = MoveCommand(node: _TestNode(id: NodeId('n')), dx: 0, dy: 0);
      expect(cmd.timestamp, isA<DateTime>());
    });

    test('redo defaults to execute', () {
      final node = _TestNode(id: NodeId('n'));
      final cmd = MoveCommand(node: node, dx: 10, dy: 20);
      cmd.execute();
      final posAfterExec = node.position;
      cmd.undo();
      cmd.redo(); // should behave like execute
      expect(node.position, posAfterExec);
    });
  });

  // =========================================================================
  // MoveCommand
  // =========================================================================

  group('MoveCommand', () {
    test('execute translates node', () {
      final node = _TestNode(id: NodeId('n'));
      final cmd = MoveCommand(node: node, dx: 10, dy: 20);
      cmd.execute();
      expect(node.position.dx, closeTo(10, 0.01));
      expect(node.position.dy, closeTo(20, 0.01));
    });

    test('undo reverses translation', () {
      final node = _TestNode(id: NodeId('n'));
      final cmd = MoveCommand(node: node, dx: 10, dy: 20);
      cmd.execute();
      cmd.undo();
      expect(node.position.dx, closeTo(0, 0.01));
      expect(node.position.dy, closeTo(0, 0.01));
    });

    test('label includes node name when available', () {
      final cmd = MoveCommand(
        node: _TestNode(id: NodeId('n1'), name: 'Circle'),
        dx: 0,
        dy: 0,
      );
      expect(cmd.label, contains('Circle'));
    });

    test('label falls back to node id', () {
      final cmd = MoveCommand(node: _TestNode(id: NodeId('n1')), dx: 0, dy: 0);
      expect(cmd.label, contains('n1'));
    });

    test('canMergeWith same node', () {
      final node = _TestNode(id: NodeId('n'));
      final a = MoveCommand(node: node, dx: 5, dy: 5);
      final b = MoveCommand(node: node, dx: 3, dy: 3);
      expect(a.canMergeWith(b), isTrue);
    });

    test('canMergeWith different node is false', () {
      final a = MoveCommand(node: _TestNode(id: NodeId('a')), dx: 5, dy: 5);
      final b = MoveCommand(node: _TestNode(id: NodeId('b')), dx: 3, dy: 3);
      expect(a.canMergeWith(b), isFalse);
    });

    test('mergeWith accumulates deltas', () {
      final node = _TestNode(id: NodeId('n'));
      final a = MoveCommand(node: node, dx: 5, dy: 10);
      final b = MoveCommand(node: node, dx: 3, dy: 7);
      a.mergeWith(b);
      expect(a.dx, 8);
      expect(a.dy, 17);
    });
  });

  // =========================================================================
  // SetPositionCommand
  // =========================================================================

  group('SetPositionCommand', () {
    test('execute sets absolute position', () {
      final node = _TestNode(id: NodeId('n'));
      final cmd = SetPositionCommand(node: node, newX: 100, newY: 200);
      cmd.execute();
      expect(node.position.dx, closeTo(100, 0.01));
      expect(node.position.dy, closeTo(200, 0.01));
    });

    test('undo restores old position', () {
      final node = _TestNode(id: NodeId('n'));
      node.setPosition(50, 75);
      final cmd = SetPositionCommand(node: node, newX: 100, newY: 200);
      cmd.execute();
      cmd.undo();
      expect(node.position.dx, closeTo(50, 0.01));
      expect(node.position.dy, closeTo(75, 0.01));
    });
  });

  // =========================================================================
  // TransformCommand
  // =========================================================================

  group('TransformCommand', () {
    test('execute applies new transform', () {
      final node = _TestNode(id: NodeId('n'));
      final newTransform = Matrix4.translationValues(42, 84, 0);
      final cmd = TransformCommand(node: node, newTransform: newTransform);
      cmd.execute();
      expect(node.position.dx, closeTo(42, 0.01));
      expect(node.position.dy, closeTo(84, 0.01));
    });

    test('undo restores old transform', () {
      final node = _TestNode(id: NodeId('n'));
      node.setPosition(10, 20);
      final newTransform = Matrix4.translationValues(42, 84, 0);
      final cmd = TransformCommand(node: node, newTransform: newTransform);
      cmd.execute();
      cmd.undo();
      expect(node.position.dx, closeTo(10, 0.01));
      expect(node.position.dy, closeTo(20, 0.01));
    });
  });

  // =========================================================================
  // AddNodeCommand
  // =========================================================================

  group('AddNodeCommand', () {
    test('execute adds child to parent', () {
      final parent = GroupNode(id: NodeId('p'));
      final child = _TestNode(id: NodeId('c'));
      final cmd = AddNodeCommand(parent: parent, child: child);
      cmd.execute();
      expect(parent.childCount, 1);
      expect(parent.findChild('c'), isNotNull);
    });

    test('undo removes child from parent', () {
      final parent = GroupNode(id: NodeId('p'));
      final child = _TestNode(id: NodeId('c'));
      final cmd = AddNodeCommand(parent: parent, child: child);
      cmd.execute();
      cmd.undo();
      expect(parent.childCount, 0);
    });

    test('execute with index inserts at position', () {
      final parent = GroupNode(id: NodeId('p'));
      parent.add(_TestNode(id: NodeId('first')));
      parent.add(_TestNode(id: NodeId('last')));
      final child = _TestNode(id: NodeId('middle'));
      final cmd = AddNodeCommand(parent: parent, child: child, index: 1);
      cmd.execute();
      expect(parent.children[1].id, 'middle');
    });
  });

  // =========================================================================
  // DeleteNodeCommand
  // =========================================================================

  group('DeleteNodeCommand', () {
    test('execute removes child from parent', () {
      final parent = GroupNode(id: NodeId('p'));
      final child = _TestNode(id: NodeId('c'));
      parent.add(child);
      final cmd = DeleteNodeCommand(parent: parent, child: child);
      cmd.execute();
      expect(parent.childCount, 0);
    });

    test('undo restores child at original index', () {
      final parent = GroupNode(id: NodeId('p'));
      parent.add(_TestNode(id: NodeId('a')));
      final target = _TestNode(id: NodeId('b'));
      parent.add(target);
      parent.add(_TestNode(id: NodeId('c')));
      // target is at index 1
      final cmd = DeleteNodeCommand(parent: parent, child: target);
      cmd.execute();
      expect(parent.childCount, 2);
      cmd.undo();
      expect(parent.childCount, 3);
      expect(parent.children[1].id, 'b');
    });
  });

  // =========================================================================
  // ReorderCommand
  // =========================================================================

  group('ReorderCommand', () {
    test('execute reorders children', () {
      final parent = GroupNode(id: NodeId('p'));
      parent.add(_TestNode(id: NodeId('a')));
      parent.add(_TestNode(id: NodeId('b')));
      parent.add(_TestNode(id: NodeId('c')));
      final cmd = ReorderCommand(parent: parent, oldIndex: 0, newIndex: 3);
      cmd.execute();
      expect(parent.children.map((c) => c.id).toList(), ['b', 'c', 'a']);
    });

    test('undo reverses reorder', () {
      final parent = GroupNode(id: NodeId('p'));
      parent.add(_TestNode(id: NodeId('a')));
      parent.add(_TestNode(id: NodeId('b')));
      parent.add(_TestNode(id: NodeId('c')));
      final cmd = ReorderCommand(parent: parent, oldIndex: 0, newIndex: 3);
      cmd.execute();
      cmd.undo();
      expect(parent.children.map((c) => c.id).toList(), ['a', 'b', 'c']);
    });
  });

  // =========================================================================
  // PropertyChangeCommand
  // =========================================================================

  group('PropertyChangeCommand', () {
    test('execute sets new value', () {
      String value = 'old';
      final cmd = PropertyChangeCommand<String>(
        label: 'Rename',
        oldValue: 'old',
        newValue: 'new',
        setter: (v) => value = v,
      );
      cmd.execute();
      expect(value, 'new');
    });

    test('undo restores old value', () {
      String value = 'old';
      final cmd = PropertyChangeCommand<String>(
        label: 'Rename',
        oldValue: 'old',
        newValue: 'new',
        setter: (v) => value = v,
      );
      cmd.execute();
      cmd.undo();
      expect(value, 'old');
    });
  });

  // =========================================================================
  // OpacityCommand
  // =========================================================================

  group('OpacityCommand', () {
    test('execute sets new opacity', () {
      final node = _TestNode(id: NodeId('n'), name: 'Shape');
      node.opacity = 1.0;
      final cmd = OpacityCommand(node: node, newOpacity: 0.5);
      cmd.execute();
      expect(node.opacity, 0.5);
    });

    test('undo restores old opacity', () {
      final node = _TestNode(id: NodeId('n'));
      node.opacity = 0.8;
      final cmd = OpacityCommand(node: node, newOpacity: 0.3);
      cmd.execute();
      cmd.undo();
      expect(node.opacity, 0.8);
    });
  });

  // =========================================================================
  // VisibilityCommand
  // =========================================================================

  group('VisibilityCommand', () {
    test('execute toggles visibility', () {
      final node = _TestNode(id: NodeId('n'));
      expect(node.isVisible, isTrue);
      final cmd = VisibilityCommand(node: node);
      cmd.execute();
      expect(node.isVisible, isFalse);
    });

    test('undo restores visibility', () {
      final node = _TestNode(id: NodeId('n'));
      final cmd = VisibilityCommand(node: node);
      cmd.execute();
      cmd.undo();
      expect(node.isVisible, isTrue);
    });

    test('double execute restores visibility', () {
      final node = _TestNode(id: NodeId('n'));
      final cmd = VisibilityCommand(node: node);
      cmd.execute();
      cmd.execute();
      expect(node.isVisible, isTrue);
    });
  });

  // =========================================================================
  // LockCommand
  // =========================================================================

  group('LockCommand', () {
    test('execute toggles lock', () {
      final node = _TestNode(id: NodeId('n'));
      expect(node.isLocked, isFalse);
      final cmd = LockCommand(node: node);
      cmd.execute();
      expect(node.isLocked, isTrue);
    });

    test('undo restores lock state', () {
      final node = _TestNode(id: NodeId('n'));
      final cmd = LockCommand(node: node);
      cmd.execute();
      cmd.undo();
      expect(node.isLocked, isFalse);
    });
  });
}
