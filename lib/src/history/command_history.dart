import 'package:flutter/material.dart';
import '../core/scene_graph/scene_graph.dart';
import '../core/scene_graph/scene_graph_transaction.dart';
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

  /// Optional scene graph for transaction-based atomic execution.
  ///
  /// When provided, the entire batch is wrapped in a [SceneGraphTransaction].
  /// If any sub-command throws, all mutations are atomically rolled back.
  final SceneGraph? sceneGraph;

  CompositeCommand({
    required super.label,
    required this.commands,
    this.sceneGraph,
  });

  @override
  void execute() {
    final txn = sceneGraph?.beginTransaction();
    try {
      for (final cmd in commands) {
        cmd.execute();
      }
      txn?.commit();
    } catch (e) {
      txn?.rollback();
      rethrow;
    }
  }

  @override
  void undo() {
    final txn = sceneGraph?.beginTransaction();
    try {
      for (final cmd in commands.reversed) {
        cmd.undo();
      }
      txn?.commit();
    } catch (e) {
      txn?.rollback();
      rethrow;
    }
  }

  @override
  void redo() {
    final txn = sceneGraph?.beginTransaction();
    try {
      for (final cmd in commands) {
        cmd.redo();
      }
      txn?.commit();
    } catch (e) {
      txn?.rollback();
      rethrow;
    }
  }
}

// ---------------------------------------------------------------------------
// Compound Command Builder — Fluent API
// ---------------------------------------------------------------------------

/// Fluent builder for creating multi-step atomic operations.
///
/// Unlike [CommandTransaction], the builder does **not** execute commands
/// immediately — it collects them and produces a [CompositeCommand] on
/// [build]. The caller then passes the composite to [CommandHistory.execute].
///
/// ```dart
/// final cmd = CompoundCommandBuilder('Align selection')
///   .add(SetPositionCommand(node: a, newX: 10, newY: 0))
///   .add(SetPositionCommand(node: b, newX: 10, newY: 50))
///   .addIf(snapEnabled, SetPositionCommand(node: c, newX: 10, newY: 100))
///   .build();
/// history.execute(cmd);
/// ```
class CompoundCommandBuilder {
  final String label;
  final List<Command> _commands = [];

  CompoundCommandBuilder(this.label);

  /// Add a command to the compound.
  CompoundCommandBuilder add(Command command) {
    _commands.add(command);
    return this;
  }

  /// Conditionally add a command.
  CompoundCommandBuilder addIf(bool condition, Command command) {
    if (condition) _commands.add(command);
    return this;
  }

  /// Add all commands from an iterable.
  CompoundCommandBuilder addAll(Iterable<Command> commands) {
    _commands.addAll(commands);
    return this;
  }

  /// Build the compound. Returns a [CompositeCommand] wrapping all added
  /// commands. Throws [StateError] if no commands were added.
  CompositeCommand build() {
    if (_commands.isEmpty) {
      throw StateError('CompoundCommandBuilder: no commands to build');
    }
    return CompositeCommand(label: label, commands: List.of(_commands));
  }
}

// ---------------------------------------------------------------------------
// Conditional Command
// ---------------------------------------------------------------------------

/// A command that only executes when a runtime [guard] returns `true`.
///
/// If the guard fails on [execute], the command is silently skipped.
/// [undo] also checks the guard to prevent reverting an action that never ran.
///
/// ```dart
/// ConditionalCommand(
///   label: 'Delete if unlocked',
///   guard: () => !node.isLocked,
///   inner: DeleteNodeCommand(parent: layer, child: node),
/// );
/// ```
class ConditionalCommand extends Command {
  final bool Function() guard;
  final Command inner;
  bool _didExecute = false;

  ConditionalCommand({
    required String label,
    required this.guard,
    required this.inner,
  }) : super(label: label);

  @override
  void execute() {
    if (guard()) {
      inner.execute();
      _didExecute = true;
    }
  }

  @override
  void undo() {
    if (_didExecute) {
      inner.undo();
      _didExecute = false;
    }
  }

  @override
  void redo() {
    if (guard()) {
      inner.redo();
      _didExecute = true;
    }
  }
}

// ---------------------------------------------------------------------------
// Command Middleware
// ---------------------------------------------------------------------------

/// Intercepts every command execution in [CommandHistory].
///
/// Middlewares are called in order on `beforeXxx` and in reverse order on
/// `afterXxx`, forming a middleware stack (onion model).
///
/// Return `false` from [beforeExecute] to **veto** a command — it will not
/// be executed, and no `afterExecute` callbacks will fire.
///
/// ```dart
/// class LoggingMiddleware extends CommandMiddleware {
///   @override
///   bool beforeExecute(Command cmd) {
///     print('Executing: ${cmd.label}');
///     return true;
///   }
/// }
/// ```
abstract class CommandMiddleware {
  /// Called before a command is executed. Return `false` to veto.
  bool beforeExecute(Command cmd) => true;

  /// Called after a command has been successfully executed.
  void afterExecute(Command cmd) {}

  /// Called when command execution throws. Use for cleanup (e.g. journal rollback).
  void onExecuteError(Command cmd, Object error, StackTrace stack) {}

  /// Called before a command is undone.
  void beforeUndo(Command cmd) {}

  /// Called after a command has been undone.
  void afterUndo(Command cmd) {}

  /// Called when undo throws.
  void onUndoError(Command cmd, Object error, StackTrace stack) {}

  /// Called before a command is redone.
  void beforeRedo(Command cmd) {}

  /// Called after a command has been redone.
  void afterRedo(Command cmd) {}

  /// Called when redo throws.
  void onRedoError(Command cmd, Object error, StackTrace stack) {}
}

// ---------------------------------------------------------------------------
// Command Transaction
// ---------------------------------------------------------------------------

/// Groups multiple commands into a single atomic operation.
///
/// Use [add] to execute and record commands. Then either [commit] to
/// produce a single [CompositeCommand] for the undo stack, or [rollback]
/// to undo all recorded commands and discard.
///
/// ```dart
/// final txn = CommandTransaction(label: 'Move all vertices');
/// txn.add(MoveVertexCommand(node: n, vertexIndex: 0, newPosition: p1));
/// txn.add(MoveVertexCommand(node: n, vertexIndex: 1, newPosition: p2));
/// final composite = txn.commit(); // single undo entry
/// ```
class CommandTransaction {
  final String label;
  final List<Command> _commands = [];
  bool _committed = false;
  bool _rolledBack = false;

  CommandTransaction({required this.label});

  /// Whether this transaction has been committed or rolled back.
  bool get isFinished => _committed || _rolledBack;

  /// Number of commands in this transaction.
  int get length => _commands.length;

  /// Execute and record a command within this transaction.
  ///
  /// Throws if the transaction has already been committed or rolled back.
  void add(Command command) {
    if (_committed) throw StateError('Transaction already committed');
    if (_rolledBack) throw StateError('Transaction already rolled back');
    command.execute();
    _commands.add(command);
  }

  /// Commit the transaction, returning a [CompositeCommand] that wraps
  /// all recorded commands as a single undo entry.
  ///
  /// Throws if the transaction has already been committed or rolled back.
  CompositeCommand commit() {
    if (_committed) throw StateError('Transaction already committed');
    if (_rolledBack) throw StateError('Transaction already rolled back');
    _committed = true;
    return CompositeCommand(label: label, commands: List.of(_commands));
  }

  /// Roll back all recorded commands in reverse order and discard.
  void rollback() {
    if (_committed) throw StateError('Transaction already committed');
    if (_rolledBack) throw StateError('Transaction already rolled back');
    _rolledBack = true;
    for (int i = _commands.length - 1; i >= 0; i--) {
      _commands[i].undo();
    }
    _commands.clear();
  }
}
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
/// - **Middleware pipeline**: [CommandMiddleware] instances intercept every
///   execute/undo/redo call for validation, telemetry, and event bridging.
class CommandHistory {
  final List<Command> _undoStack = [];
  final List<Command> _redoStack = [];

  /// Maximum number of commands to keep in the undo stack.
  final int maxSize;

  /// Middleware pipeline — processed in order for `before`, reverse for `after`.
  final List<CommandMiddleware> middlewares;

  /// Incremented on every execute/undo/redo/clear — listen to rebuild UI.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  CommandHistory({this.maxSize = 100, List<CommandMiddleware>? middlewares})
    : middlewares = middlewares ?? [];

  /// Add a middleware to the pipeline.
  void addMiddleware(CommandMiddleware middleware) {
    middlewares.add(middleware);
  }

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
  ///
  /// Returns `true` if the command was executed, `false` if vetoed by
  /// middleware.
  bool execute(Command cmd) {
    // Middleware: beforeExecute (veto if any returns false)
    for (final mw in middlewares) {
      if (!mw.beforeExecute(cmd)) return false;
    }

    try {
      cmd.execute();
    } catch (e, s) {
      // Notify middleware of failure (e.g. journal rollback)
      for (final mw in middlewares.reversed) {
        mw.onExecuteError(cmd, e, s);
      }
      rethrow;
    }
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

    // Middleware: afterExecute (reverse order)
    for (final mw in middlewares.reversed) {
      mw.afterExecute(cmd);
    }

    return true;
  }

  /// Undo the most recent command.
  void undo() {
    if (!canUndo) return;
    final cmd = _undoStack.removeLast();

    for (final mw in middlewares) {
      mw.beforeUndo(cmd);
    }

    try {
      cmd.undo();
    } catch (e, s) {
      _undoStack.add(cmd); // restore to undo stack
      for (final mw in middlewares.reversed) {
        mw.onUndoError(cmd, e, s);
      }
      rethrow;
    }
    _redoStack.add(cmd);
    revision.value++;

    for (final mw in middlewares.reversed) {
      mw.afterUndo(cmd);
    }
  }

  /// Redo the most recently undone command.
  void redo() {
    if (!canRedo) return;
    final cmd = _redoStack.removeLast();

    for (final mw in middlewares) {
      mw.beforeRedo(cmd);
    }

    try {
      cmd.redo();
    } catch (e, s) {
      _redoStack.add(cmd); // restore to redo stack
      for (final mw in middlewares.reversed) {
        mw.onRedoError(cmd, e, s);
      }
      rethrow;
    }
    _undoStack.add(cmd);
    revision.value++;

    for (final mw in middlewares.reversed) {
      mw.afterRedo(cmd);
    }
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

// ---------------------------------------------------------------------------
// Digital Text Commands
// ---------------------------------------------------------------------------

/// Add a digital text element. Undo removes it.
class AddTextCommand extends Command {
  final List<dynamic> elements;
  final dynamic element;
  final void Function() onChanged;

  AddTextCommand({
    required this.elements,
    required this.element,
    required this.onChanged,
  }) : super(label: 'Add text');

  @override
  void execute() {
    elements.add(element);
    onChanged();
  }

  @override
  void undo() {
    elements.removeWhere((e) => e.id == element.id);
    onChanged();
  }
}

/// Delete a digital text element. Undo re-inserts at original index.
class DeleteTextCommand extends Command {
  final List<dynamic> elements;
  final dynamic element;
  final int _index;
  final void Function() onChanged;

  DeleteTextCommand({
    required this.elements,
    required this.element,
    required this.onChanged,
  }) : _index = elements.indexWhere((e) => e.id == element.id),
       super(label: 'Delete text');

  @override
  void execute() {
    elements.removeWhere((e) => e.id == element.id);
    onChanged();
  }

  @override
  void undo() {
    elements.insert(_index.clamp(0, elements.length), element);
    onChanged();
  }
}

/// Update a digital text element. Stores old element for undo.
/// Supports merge coalescing for rapid edits to the same element.
class UpdateTextCommand extends Command {
  final List<dynamic> elements;
  final dynamic oldElement;
  dynamic newElement;
  final void Function() onChanged;

  UpdateTextCommand({
    required this.elements,
    required this.oldElement,
    required this.newElement,
    required this.onChanged,
  }) : super(label: 'Edit text');

  @override
  void execute() {
    final idx = elements.indexWhere((e) => e.id == oldElement.id);
    if (idx != -1) {
      elements[idx] = newElement;
      onChanged();
    }
  }

  @override
  void undo() {
    final idx = elements.indexWhere((e) => e.id == newElement.id);
    if (idx != -1) {
      elements[idx] = oldElement;
      onChanged();
    }
  }

  @override
  bool canMergeWith(Command other) =>
      other is UpdateTextCommand && other.oldElement.id == newElement.id;

  @override
  void mergeWith(Command other) {
    if (other is UpdateTextCommand) {
      newElement = other.newElement;
    }
  }
}

// ---------------------------------------------------------------------------
// Scratch-Out Commands
// ---------------------------------------------------------------------------

/// Delete multiple strokes via scratch-out gesture. Undo re-adds them all.
class ScratchOutCommand extends Command {
  final List<dynamic> _deletedStrokes; // List<ProStroke>
  final dynamic _layerController; // FlueraLayerController

  ScratchOutCommand({
    required List<dynamic> deletedStrokes,
    required dynamic layerController,
  })  : _deletedStrokes = List.of(deletedStrokes),
        _layerController = layerController,
        super(label: 'Scratch-out (${deletedStrokes.length} strokes)');

  @override
  void execute() {
    // Already executed externally — pushed via pushWithoutExecute
  }

  @override
  void undo() {
    for (final stroke in _deletedStrokes) {
      _layerController.addStroke(stroke);
    }
  }

  @override
  void redo() {
    for (final stroke in _deletedStrokes) {
      _layerController.removeStroke(stroke.id as String);
    }
  }
}
