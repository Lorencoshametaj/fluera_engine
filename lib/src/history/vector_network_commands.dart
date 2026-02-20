import 'dart:ui';

import '../core/vector/vector_network.dart';
import '../core/vector/boolean_ops.dart';
import '../core/nodes/vector_network_node.dart';
import 'command_history.dart';

// ---------------------------------------------------------------------------
// AddVertexCommand
// ---------------------------------------------------------------------------

/// Adds a vertex to a [VectorNetworkNode]'s network. Undoable.
class AddVertexCommand extends Command {
  final VectorNetworkNode node;
  final NetworkVertex vertex;
  int? _insertedIndex;

  AddVertexCommand({required this.node, required this.vertex})
    : super(label: 'Add vertex');

  /// Index of the added vertex after [execute].
  int get insertedIndex => _insertedIndex!;

  @override
  void execute() {
    _insertedIndex = node.network.addVertex(vertex);
  }

  @override
  void undo() {
    if (_insertedIndex != null) {
      node.network.removeVertex(_insertedIndex!);
    }
  }
}

// ---------------------------------------------------------------------------
// RemoveVertexCommand
// ---------------------------------------------------------------------------

/// Removes a vertex (and its connected segments) from a network. Undoable.
///
/// Uses full network snapshot for reliable undo — handles the complexity of
/// segment reindexing and connected segment removal automatically.
class RemoveVertexCommand extends Command {
  final VectorNetworkNode node;
  final int vertexIndex;

  late final VectorNetwork _snapshot;

  RemoveVertexCommand({required this.node, required this.vertexIndex})
    : super(label: 'Remove vertex');

  @override
  void execute() {
    _snapshot = node.network.clone();
    node.network.removeVertex(vertexIndex);
  }

  @override
  void undo() {
    node.network = _snapshot.clone();
  }
}

// ---------------------------------------------------------------------------
// AddSegmentCommand
// ---------------------------------------------------------------------------

/// Adds a segment between two existing vertices. Undoable.
class AddSegmentCommand extends Command {
  final VectorNetworkNode node;
  final NetworkSegment segment;
  int? _insertedIndex;

  AddSegmentCommand({required this.node, required this.segment})
    : super(label: 'Add segment');

  /// Index of the added segment after [execute].
  int get insertedIndex => _insertedIndex!;

  @override
  void execute() {
    _insertedIndex = node.network.addSegment(segment);
  }

  @override
  void undo() {
    if (_insertedIndex != null) {
      node.network.removeSegment(_insertedIndex!);
    }
  }
}

// ---------------------------------------------------------------------------
// RemoveSegmentCommand
// ---------------------------------------------------------------------------

/// Removes a segment from the network. Undoable.
///
/// Uses full network snapshot for reliable undo — avoids issues with
/// segment reindexing in regions.
class RemoveSegmentCommand extends Command {
  final VectorNetworkNode node;
  final int segmentIndex;

  late final VectorNetwork _snapshot;

  RemoveSegmentCommand({required this.node, required this.segmentIndex})
    : super(label: 'Remove segment');

  @override
  void execute() {
    _snapshot = node.network.clone();
    node.network.removeSegment(segmentIndex);
  }

  @override
  void undo() {
    node.network = _snapshot.clone();
  }
}

// ---------------------------------------------------------------------------
// MoveVertexCommand
// ---------------------------------------------------------------------------

/// Moves a vertex to a new position. Supports drag coalescing.
class MoveVertexCommand extends Command {
  final VectorNetworkNode node;
  final int vertexIndex;
  final Offset _oldPosition;
  Offset _newPosition;

  MoveVertexCommand({
    required this.node,
    required this.vertexIndex,
    required Offset newPosition,
  }) : _oldPosition = node.network.vertices[vertexIndex].position,
       _newPosition = newPosition,
       super(label: 'Move vertex');

  @override
  void execute() {
    node.network.vertices[vertexIndex].position = _newPosition;
    node.network.invalidate();
  }

  @override
  void undo() {
    node.network.vertices[vertexIndex].position = _oldPosition;
    node.network.invalidate();
  }

  @override
  bool canMergeWith(Command other) {
    return other is MoveVertexCommand &&
        other.node == node &&
        other.vertexIndex == vertexIndex;
  }

  @override
  void mergeWith(Command other) {
    if (other is MoveVertexCommand) {
      _newPosition = other._newPosition;
    }
  }
}

// ---------------------------------------------------------------------------
// NetworkBooleanCommand
// ---------------------------------------------------------------------------

/// Applies a boolean operation between two [VectorNetworkNode]s. Undoable.
///
/// On execute, replaces the target node's network with the boolean result
/// and stores the original networks for undo.
class NetworkBooleanCommand extends Command {
  final VectorNetworkNode targetNode;
  final VectorNetworkNode otherNode;
  final BooleanOpType operation;

  late final VectorNetwork _originalTargetNetwork;
  late final VectorNetwork _originalOtherNetwork;

  NetworkBooleanCommand({
    required this.targetNode,
    required this.otherNode,
    required this.operation,
  }) : super(label: 'Boolean ${operation.name}');

  @override
  void execute() {
    _originalTargetNetwork = targetNode.network.clone();
    _originalOtherNetwork = otherNode.network.clone();

    final result = BooleanOps.executeOnNetworks(
      operation,
      targetNode.network,
      otherNode.network,
    );

    targetNode.network = result;
  }

  @override
  void undo() {
    targetNode.network = _originalTargetNetwork.clone();
    otherNode.network = _originalOtherNetwork.clone();
  }
}
