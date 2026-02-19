import 'package:flutter/material.dart';
import '../core/scene_graph/canvas_node.dart';
import '../core/nodes/group_node.dart';

// ---------------------------------------------------------------------------
// Command base
// ---------------------------------------------------------------------------

/// Base class for all undoable commands in the scene graph.
///
/// Every user action that modifies the scene graph (move, delete, add,
/// reorder, property change) is wrapped in a [Command].
///
/// Subclasses must implement [execute], [undo], and optionally override
/// [redo] (defaults to calling [execute] again).
abstract class Command {
  /// Human-readable label for this command (shown in undo history UI).
  final String label;

  /// Timestamp when this command was first executed.
  final DateTime timestamp;

  Command({required this.label}) : timestamp = DateTime.now();

  /// Execute this command (first time).
  void execute();

  /// Reverse this command's effect.
  void undo();

  /// Re-apply this command. Defaults to [execute].
  void redo() => execute();

  /// Whether this command can merge with [other] (for drag coalescing).
  ///
  /// When true, [mergeWith] is called instead of pushing a new command.
  bool canMergeWith(Command other) => false;

  /// Merge [other] into this command. Only called when [canMergeWith]
  /// returns true. The merged command replaces this one on the stack.
  void mergeWith(Command other) {}
}

// ---------------------------------------------------------------------------
// Composite Command
// ---------------------------------------------------------------------------

/// Groups multiple [Command]s into a single undoable operation.
///
/// Use this when a user action logically consists of several steps
/// (e.g. rename = remove + add) but should appear as one entry in the
/// undo history.
///
/// ```dart
/// final composite = CompositeCommand(
///   label: 'Create themed button',
///   commands: [addNodeCmd, addBindingCmd, setValueCmd],
/// );
/// composite.execute(); // runs all three
/// composite.undo();    // reverses all three in reverse order
/// ```
class CompositeCommand extends Command {
  final List<Command> commands;

  CompositeCommand({required super.label, required this.commands});

  @override
  void execute() {
    for (final cmd in commands) {
      cmd.execute();
    }
  }

  @override
  void undo() {
    for (final cmd in commands.reversed) {
      cmd.undo();
    }
  }

  @override
  void redo() {
    for (final cmd in commands) {
      cmd.redo();
    }
  }
}

// ---------------------------------------------------------------------------
// Concrete Commands
// ---------------------------------------------------------------------------

/// Move a node by [dx], [dy]. Supports drag coalescing.
class MoveCommand extends Command {
  final CanvasNode node;
  double dx;
  double dy;

  MoveCommand({required this.node, required this.dx, required this.dy})
    : super(label: 'Move ${node.name.isNotEmpty ? node.name : node.id}');

  @override
  void execute() => node.translate(dx, dy);

  @override
  void undo() => node.translate(-dx, -dy);

  @override
  bool canMergeWith(Command other) =>
      other is MoveCommand && other.node.id == node.id;

  @override
  void mergeWith(Command other) {
    if (other is MoveCommand) {
      dx += other.dx;
      dy += other.dy;
    }
  }
}

/// Set absolute position. Stores old position for undo.
class SetPositionCommand extends Command {
  final CanvasNode node;
  final double newX;
  final double newY;
  late final double _oldX;
  late final double _oldY;

  SetPositionCommand({
    required this.node,
    required this.newX,
    required this.newY,
  }) : super(label: 'Position ${node.name.isNotEmpty ? node.name : node.id}') {
    _oldX = node.localTransform.getTranslation().x;
    _oldY = node.localTransform.getTranslation().y;
  }

  @override
  void execute() => node.setPosition(newX, newY);

  @override
  void undo() => node.setPosition(_oldX, _oldY);
}

/// Apply a full transform matrix. Stores old matrix for undo.
class TransformCommand extends Command {
  final CanvasNode node;
  final Matrix4 newTransform;
  late final Matrix4 _oldTransform;

  TransformCommand({required this.node, required this.newTransform})
    : super(label: 'Transform ${node.name.isNotEmpty ? node.name : node.id}') {
    _oldTransform = node.localTransform.clone();
  }

  @override
  void execute() => node.localTransform = newTransform.clone();

  @override
  void undo() => node.localTransform = _oldTransform.clone();
}

/// Add a node to a group/layer.
class AddNodeCommand extends Command {
  final GroupNode parent;
  final CanvasNode child;
  final int? index;

  AddNodeCommand({required this.parent, required this.child, this.index})
    : super(label: 'Add ${child.name.isNotEmpty ? child.name : child.id}');

  @override
  void execute() {
    if (index != null) {
      parent.insertAt(index!, child);
    } else {
      parent.add(child);
    }
  }

  @override
  void undo() => parent.remove(child);
}

/// Remove a node from its parent group.
class DeleteNodeCommand extends Command {
  final GroupNode parent;
  final CanvasNode child;
  late final int _index;

  DeleteNodeCommand({required this.parent, required this.child})
    : super(label: 'Delete ${child.name.isNotEmpty ? child.name : child.id}') {
    _index = parent.indexOf(child);
  }

  @override
  void execute() => parent.remove(child);

  @override
  void undo() => parent.insertAt(_index.clamp(0, parent.childCount), child);
}

/// Reorder a child within its parent group.
class ReorderCommand extends Command {
  final GroupNode parent;
  final int oldIndex;
  final int newIndex;

  ReorderCommand({
    required this.parent,
    required this.oldIndex,
    required this.newIndex,
  }) : super(label: 'Reorder');

  @override
  void execute() => parent.reorder(oldIndex, newIndex);

  @override
  void undo() => parent.reorder(
    newIndex > oldIndex ? newIndex - 1 : newIndex,
    oldIndex > newIndex ? oldIndex + 1 : oldIndex,
  );
}

/// Change a single property on a node. Uses getter/setter callbacks.
class PropertyChangeCommand<T> extends Command {
  final T oldValue;
  final T newValue;
  final void Function(T) setter;

  PropertyChangeCommand({
    required super.label,
    required this.oldValue,
    required this.newValue,
    required this.setter,
  });

  @override
  void execute() => setter(newValue);

  @override
  void undo() => setter(oldValue);
}

/// Change opacity of a node.
class OpacityCommand extends Command {
  final CanvasNode node;
  final double newOpacity;
  late final double _oldOpacity;

  OpacityCommand({required this.node, required this.newOpacity})
    : super(label: 'Opacity ${node.name.isNotEmpty ? node.name : node.id}') {
    _oldOpacity = node.opacity;
  }

  @override
  void execute() => node.opacity = newOpacity;

  @override
  void undo() => node.opacity = _oldOpacity;
}

/// Toggle visibility of a node.
class VisibilityCommand extends Command {
  final CanvasNode node;

  VisibilityCommand({required this.node})
    : super(label: 'Visibility ${node.name.isNotEmpty ? node.name : node.id}');

  @override
  void execute() => node.isVisible = !node.isVisible;

  @override
  void undo() => node.isVisible = !node.isVisible;
}

/// Toggle lock state of a node.
class LockCommand extends Command {
  final CanvasNode node;

  LockCommand({required this.node})
    : super(label: 'Lock ${node.name.isNotEmpty ? node.name : node.id}');

  @override
  void execute() => node.isLocked = !node.isLocked;

  @override
  void undo() => node.isLocked = !node.isLocked;
}
