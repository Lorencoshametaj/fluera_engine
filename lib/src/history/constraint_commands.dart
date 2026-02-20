import '../core/vector/vector_network.dart';
import '../core/vector/constraints.dart';
import '../core/nodes/vector_network_node.dart';
import 'command_history.dart';

// ---------------------------------------------------------------------------
// AddConstraintCommand
// ---------------------------------------------------------------------------

/// Adds a geometric constraint to a [VectorNetworkNode]'s network. Undoable.
class AddConstraintCommand extends Command {
  final VectorNetworkNode node;
  final GeometricConstraint constraint;

  AddConstraintCommand({required this.node, required this.constraint})
    : super(label: 'Add ${constraint.type.name} constraint');

  @override
  void execute() {
    node.network.constraints.add(constraint);
    node.network.invalidate();
  }

  @override
  void undo() {
    node.network.constraints.remove(constraint);
    node.network.invalidate();
  }
}

// ---------------------------------------------------------------------------
// RemoveConstraintCommand
// ---------------------------------------------------------------------------

/// Removes a geometric constraint from a network. Undoable.
class RemoveConstraintCommand extends Command {
  final VectorNetworkNode node;
  final int constraintIndex;
  late final GeometricConstraint _removedConstraint;

  RemoveConstraintCommand({required this.node, required this.constraintIndex})
    : super(label: 'Remove constraint');

  @override
  void execute() {
    _removedConstraint = node.network.constraints[constraintIndex];
    node.network.constraints.removeAt(constraintIndex);
    node.network.invalidate();
  }

  @override
  void undo() {
    node.network.constraints.insert(constraintIndex, _removedConstraint);
    node.network.invalidate();
  }
}

// ---------------------------------------------------------------------------
// SolveConstraintsCommand
// ---------------------------------------------------------------------------

/// Runs the constraint solver and stores the pre-solve state for undo.
class SolveConstraintsCommand extends Command {
  final VectorNetworkNode node;
  late final VectorNetwork _snapshot;

  SolveConstraintsCommand({required this.node})
    : super(label: 'Solve constraints');

  @override
  void execute() {
    _snapshot = node.network.clone();
    final solver = ConstraintSolver(
      network: node.network,
      constraints: node.network.constraints,
    );
    solver.solve();
  }

  @override
  void undo() {
    node.network = _snapshot.clone();
  }
}
