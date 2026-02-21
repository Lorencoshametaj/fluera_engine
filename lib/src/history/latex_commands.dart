import 'dart:ui';
import '../core/nodes/latex_node.dart';
import '../core/nodes/group_node.dart';
import '../core/scene_graph/canvas_node.dart';
import 'command_history.dart';

// ---------------------------------------------------------------------------
// LaTeX Node Commands — Undoable operations for LaTeX expressions
// ---------------------------------------------------------------------------

/// Add a [LatexNode] to a parent group. Undo removes it.
class AddLatexNodeCommand extends Command {
  final GroupNode parent;
  final LatexNode latexNode;
  final int? index;

  AddLatexNodeCommand({
    required this.parent,
    required this.latexNode,
    this.index,
  }) : super(
         label:
             'Add LaTeX "${latexNode.latexSource.length > 20 ? '${latexNode.latexSource.substring(0, 17)}...' : latexNode.latexSource}"',
       );

  @override
  void execute() {
    if (index != null) {
      parent.insertAt(index!, latexNode);
    } else {
      parent.add(latexNode);
    }
  }

  @override
  void undo() => parent.remove(latexNode);
}

/// Delete a [LatexNode] from its parent. Undo re-inserts at original index.
class DeleteLatexNodeCommand extends Command {
  final GroupNode parent;
  final LatexNode latexNode;
  late final int _originalIndex;

  DeleteLatexNodeCommand({required this.parent, required this.latexNode})
    : super(
        label:
            'Delete LaTeX "${latexNode.latexSource.length > 20 ? '${latexNode.latexSource.substring(0, 17)}...' : latexNode.latexSource}"',
      ) {
    _originalIndex = parent.indexOf(latexNode);
  }

  @override
  void execute() => parent.remove(latexNode);

  @override
  void undo() =>
      parent.insertAt(_originalIndex.clamp(0, parent.childCount), latexNode);
}

/// Change the LaTeX source of a node. Supports merge coalescing for
/// rapid edits (e.g. typing corrections in the editor).
class UpdateLatexSourceCommand extends Command {
  final LatexNode node;
  final String oldSource;
  String newSource;

  UpdateLatexSourceCommand({required this.node, required this.newSource})
    : oldSource = node.latexSource,
      super(label: 'Edit LaTeX');

  @override
  void execute() => node.latexSource = newSource;

  @override
  void undo() => node.latexSource = oldSource;

  @override
  bool canMergeWith(Command other) =>
      other is UpdateLatexSourceCommand && other.node.id == node.id;

  @override
  void mergeWith(Command other) {
    if (other is UpdateLatexSourceCommand) {
      newSource = other.newSource;
    }
  }
}

/// Change the font size of a LaTeX node.
class UpdateLatexFontSizeCommand extends Command {
  final LatexNode node;
  final double oldFontSize;
  final double newFontSize;

  UpdateLatexFontSizeCommand({required this.node, required this.newFontSize})
    : oldFontSize = node.fontSize,
      super(label: 'LaTeX font size');

  @override
  void execute() => node.fontSize = newFontSize;

  @override
  void undo() => node.fontSize = oldFontSize;
}

/// Change the color of a LaTeX node.
class UpdateLatexColorCommand extends Command {
  final LatexNode node;
  final Color oldColor;
  final Color newColor;

  UpdateLatexColorCommand({required this.node, required this.newColor})
    : oldColor = node.color,
      super(label: 'LaTeX color');

  @override
  void execute() => node.color = newColor;

  @override
  void undo() => node.color = oldColor;

  @override
  bool canMergeWith(Command other) =>
      other is UpdateLatexColorCommand && other.node.id == node.id;

  @override
  void mergeWith(Command other) {
    // Keep the latest color — the old color stays from the first command
  }
}
