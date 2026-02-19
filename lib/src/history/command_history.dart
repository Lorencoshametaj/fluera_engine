import 'package:flutter/material.dart';
import '../core/scene_graph/canvas_node.dart';
import '../core/nodes/group_node.dart';
import '../core/nodes/pdf_page_node.dart';
import '../core/nodes/pdf_document_node.dart';
import '../core/models/pdf_annotation_model.dart';

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

// ---------------------------------------------------------------------------
// PDF Annotation Commands
// ---------------------------------------------------------------------------

/// Add a structured annotation to a PDF page. Undo removes it.
class AddAnnotationCommand extends Command {
  final PdfPageNode page;
  final PdfAnnotation annotation;

  AddAnnotationCommand({required this.page, required this.annotation})
    : super(label: 'Add ${annotation.type.name}');

  @override
  void execute() {
    final list = [...page.pageModel.structuredAnnotations, annotation];
    page.pageModel = page.pageModel.copyWith(structuredAnnotations: list);
  }

  @override
  void undo() {
    final list =
        page.pageModel.structuredAnnotations
            .where((a) => a.id != annotation.id)
            .toList();
    page.pageModel = page.pageModel.copyWith(structuredAnnotations: list);
  }
}

/// Remove a structured annotation from a PDF page. Undo re-inserts at index.
class RemoveAnnotationCommand extends Command {
  final PdfPageNode page;
  final PdfAnnotation annotation;
  late final int _originalIndex;

  RemoveAnnotationCommand({required this.page, required this.annotation})
    : super(label: 'Remove ${annotation.type.name}') {
    _originalIndex = page.pageModel.structuredAnnotations.indexWhere(
      (a) => a.id == annotation.id,
    );
  }

  @override
  void execute() {
    final list =
        page.pageModel.structuredAnnotations
            .where((a) => a.id != annotation.id)
            .toList();
    page.pageModel = page.pageModel.copyWith(structuredAnnotations: list);
  }

  @override
  void undo() {
    final list = List<PdfAnnotation>.from(page.pageModel.structuredAnnotations);
    final idx = _originalIndex.clamp(0, list.length);
    list.insert(idx, annotation);
    page.pageModel = page.pageModel.copyWith(structuredAnnotations: list);
  }
}

/// Update a structured annotation. Stores old snapshot for undo.
///
/// E1: Supports merge coalescing — rapid edits to the same annotation
/// (e.g. dragging a color slider) collapse into a single undo entry.
class UpdateAnnotationCommand extends Command {
  final PdfPageNode page;
  final PdfAnnotation oldAnnotation;
  PdfAnnotation newAnnotation;

  UpdateAnnotationCommand({
    required this.page,
    required this.oldAnnotation,
    required this.newAnnotation,
  }) : super(label: 'Update ${newAnnotation.type.name}');

  @override
  void execute() => _replace(oldAnnotation.id, newAnnotation);

  @override
  void undo() => _replace(newAnnotation.id, oldAnnotation);

  // E1: Merge rapid updates to the same annotation on the same page
  @override
  bool canMergeWith(Command other) =>
      other is UpdateAnnotationCommand &&
      other.page.id == page.id &&
      other.oldAnnotation.id == newAnnotation.id;

  @override
  void mergeWith(Command other) {
    if (other is UpdateAnnotationCommand) {
      newAnnotation = other.newAnnotation;
    }
  }

  void _replace(String id, PdfAnnotation replacement) {
    final list =
        page.pageModel.structuredAnnotations.map((a) {
          return a.id == id ? replacement : a;
        }).toList();
    page.pageModel = page.pageModel.copyWith(structuredAnnotations: list);
  }
}

// ---------------------------------------------------------------------------
// PDF Page Commands
// ---------------------------------------------------------------------------

/// Insert a blank page into a PDF document. Undo removes it.
class InsertBlankPageCommand extends Command {
  final PdfDocumentNode document;
  final PdfPageNode blankPage;
  final int insertIndex;

  InsertBlankPageCommand({
    required this.document,
    required this.blankPage,
    required this.insertIndex,
  }) : super(label: 'Insert blank page');

  @override
  void execute() {
    document.insertAt(insertIndex.clamp(0, document.childCount), blankPage);
    _reindexPages();
  }

  @override
  void undo() {
    document.remove(blankPage);
    _reindexPages();
  }

  // E3/E5: Re-index pages and sync totalPages + grid layout
  void _reindexPages() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final pages = document.pageNodes;
    for (int i = 0; i < pages.length; i++) {
      pages[i].pageModel = pages[i].pageModel.copyWith(
        pageIndex: i,
        lastModifiedAt: now,
      );
    }
    document.documentModel = document.documentModel.copyWith(
      totalPages: pages.length,
      lastModifiedAt: now,
    );
    document.performGridLayout();
  }
}

/// Reorder a PDF page. Undo reverses the reorder.
class ReorderPageCommand extends Command {
  final PdfDocumentNode document;
  final int fromIndex;
  final int toIndex;

  ReorderPageCommand({
    required this.document,
    required this.fromIndex,
    required this.toIndex,
  }) : super(label: 'Reorder page ${fromIndex + 1} → ${toIndex + 1}');

  @override
  void execute() {
    // E4: No-op guard
    if (fromIndex == toIndex) return;
    document.reorderPage(fromIndex, toIndex);
  }

  @override
  void undo() {
    if (fromIndex == toIndex) return;
    document.reorderPage(toIndex, fromIndex);
  }
}

// ---------------------------------------------------------------------------
// Command History Manager
// ---------------------------------------------------------------------------

/// Manages undo/redo stacks for [Command] objects.
///
/// ```dart
/// final history = CommandHistory();
/// history.execute(MoveCommand(node: n, dx: 10, dy: 0));
/// history.undo();  // reverses the move
/// history.redo();  // re-applies the move
/// ```
///
/// Supports:
/// - **Merge coalescing**: consecutive similar commands (e.g. drag moves)
///   are merged into a single undo entry via [Command.canMergeWith].
/// - **Reactive UI**: [revision] notifier increments on every state change,
///   so widgets can rebuild when undo/redo availability changes.
/// - **Max stack size**: prevents unbounded memory growth (default 100).
class CommandHistory {
  final List<Command> _undoStack = [];
  final List<Command> _redoStack = [];

  /// Maximum number of commands to keep in the undo stack.
  final int maxSize;

  /// Incremented on every execute/undo/redo/clear — listen to rebuild UI.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  CommandHistory({this.maxSize = 100});

  /// Whether there are commands to undo.
  bool get canUndo => _undoStack.isNotEmpty;

  /// Whether there are commands to redo.
  bool get canRedo => _redoStack.isNotEmpty;

  /// The label of the last executed command (for UI display).
  String? get undoLabel => _undoStack.isNotEmpty ? _undoStack.last.label : null;

  /// The label of the next redo command (for UI display).
  String? get redoLabel => _redoStack.isNotEmpty ? _redoStack.last.label : null;

  /// Execute a command, push it onto the undo stack, and clear redo.
  ///
  /// If the top of the undo stack can merge with [cmd], the merge happens
  /// instead of pushing a new entry (useful for drag coalescing).
  void execute(Command cmd) {
    cmd.execute();
    _redoStack.clear();

    // Attempt merge with top of undo stack
    if (_undoStack.isNotEmpty && _undoStack.last.canMergeWith(cmd)) {
      _undoStack.last.mergeWith(cmd);
    } else {
      _undoStack.add(cmd);
      // Enforce max size
      if (_undoStack.length > maxSize) {
        _undoStack.removeAt(0);
      }
    }

    revision.value++;
  }

  /// Undo the most recent command.
  void undo() {
    if (!canUndo) return;
    final cmd = _undoStack.removeLast();
    cmd.undo();
    _redoStack.add(cmd);
    revision.value++;
  }

  /// Redo the most recently undone command.
  void redo() {
    if (!canRedo) return;
    final cmd = _redoStack.removeLast();
    cmd.redo();
    _undoStack.add(cmd);
    revision.value++;
  }

  /// Clear all undo/redo history.
  void clear() {
    _undoStack.clear();
    _redoStack.clear();
    revision.value++;
  }

  /// Number of commands in the undo stack.
  int get undoCount => _undoStack.length;

  /// Number of commands in the redo stack.
  int get redoCount => _redoStack.length;

  /// F5: Peek at the top of the undo stack without popping.
  ///
  /// Useful for UI tooltips or confirmation dialogs.
  Command? get peekUndo => _undoStack.isNotEmpty ? _undoStack.last : null;

  /// F5: Peek at the top of the redo stack without popping.
  Command? get peekRedo => _redoStack.isNotEmpty ? _redoStack.last : null;

  /// F6: Push a command onto the undo stack WITHOUT calling [execute].
  ///
  /// Use when the action has already been performed externally
  /// (e.g. `ReorderableListView.onReorder` fires the action first).
  /// Still clears the redo stack and respects max size.
  void pushWithoutExecute(Command cmd) {
    _redoStack.clear();

    if (_undoStack.isNotEmpty && _undoStack.last.canMergeWith(cmd)) {
      _undoStack.last.mergeWith(cmd);
    } else {
      _undoStack.add(cmd);
      if (_undoStack.length > maxSize) {
        _undoStack.removeAt(0);
      }
    }

    revision.value++;
  }

  /// Dispose the revision notifier.
  void dispose() {
    revision.dispose();
  }
}
