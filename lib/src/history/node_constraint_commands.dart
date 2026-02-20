import 'dart:ui';

import '../core/scene_graph/canvas_node.dart';
import '../core/scene_graph/node_constraint.dart';
import '../core/scene_graph/scene_graph.dart';
import 'command_history.dart';

// ---------------------------------------------------------------------------
// AddNodeConstraintCommand
// ---------------------------------------------------------------------------

/// Adds a [NodeConstraint] to the scene graph. Undoable.
class AddNodeConstraintCommand extends Command {
  final SceneGraph sceneGraph;
  final NodeConstraint constraint;

  AddNodeConstraintCommand({required this.sceneGraph, required this.constraint})
    : super(label: 'Add ${constraint.type.name} constraint');

  @override
  void execute() {
    sceneGraph.nodeConstraints.add(constraint);
  }

  @override
  void undo() {
    sceneGraph.nodeConstraints.remove(constraint);
  }
}

// ---------------------------------------------------------------------------
// RemoveNodeConstraintCommand
// ---------------------------------------------------------------------------

/// Removes a [NodeConstraint] from the scene graph. Undoable.
class RemoveNodeConstraintCommand extends Command {
  final SceneGraph sceneGraph;
  final NodeConstraint constraint;
  int _index = -1;

  RemoveNodeConstraintCommand({
    required this.sceneGraph,
    required this.constraint,
  }) : super(label: 'Remove constraint');

  @override
  void execute() {
    _index = sceneGraph.nodeConstraints.indexOf(constraint);
    sceneGraph.nodeConstraints.remove(constraint);
  }

  @override
  void undo() {
    if (_index >= 0 && _index <= sceneGraph.nodeConstraints.length) {
      sceneGraph.nodeConstraints.insert(_index, constraint);
    } else {
      sceneGraph.nodeConstraints.add(constraint);
    }
  }
}

// ---------------------------------------------------------------------------
// SolveNodeConstraintsCommand
// ---------------------------------------------------------------------------

/// Runs the [NodeConstraintSolver] and stores pre-solve positions for undo.
class SolveNodeConstraintsCommand extends Command {
  final SceneGraph sceneGraph;

  /// Snapshot of node positions before solve (nodeId → position).
  final Map<String, Offset> _preSolvePositions = {};

  SolveNodeConstraintsCommand({required this.sceneGraph})
    : super(label: 'Solve node constraints');

  @override
  void execute() {
    // Snapshot all constraint-referenced node positions.
    final nodeIds = <String>{};
    for (final c in sceneGraph.nodeConstraints) {
      nodeIds.add(c.sourceNodeId);
      nodeIds.add(c.targetNodeId);
    }
    _preSolvePositions.clear();
    for (final id in nodeIds) {
      final node = sceneGraph.findNodeById(id);
      if (node != null) {
        _preSolvePositions[id] = node.position;
      }
    }

    // Solve.
    final solver = NodeConstraintSolver(
      constraints: sceneGraph.nodeConstraints,
      nodeResolver: sceneGraph.findNodeById,
    );
    solver.solve();
  }

  @override
  void undo() {
    // Restore pre-solve positions.
    for (final entry in _preSolvePositions.entries) {
      final node = sceneGraph.findNodeById(entry.key);
      if (node != null) {
        node.setPosition(entry.value.dx, entry.value.dy);
        node.invalidateTransformCache();
      }
    }
  }
}
