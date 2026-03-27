import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/history/vector_network_commands.dart';
import 'package:fluera_engine/src/history/command_history.dart';
import 'package:fluera_engine/src/core/vector/vector_network.dart';
import 'package:fluera_engine/src/core/nodes/vector_network_node.dart';
import 'package:fluera_engine/src/core/scene_graph/node_id.dart';

VectorNetworkNode _testNode() {
  final node = VectorNetworkNode(id: NodeId('vn1'), network: VectorNetwork());
  return node;
}

void main() {
  late VectorNetworkNode node;
  late CommandHistory history;

  setUp(() {
    node = _testNode();
    history = CommandHistory();
  });

  // ===========================================================================
  // AddVertexCommand
  // ===========================================================================

  group('AddVertexCommand', () {
    test('execute adds vertex', () {
      final vertex = NetworkVertex(position: const Offset(10, 20));
      final cmd = AddVertexCommand(node: node, vertex: vertex);

      history.execute(cmd);

      expect(node.network.vertices, hasLength(1));
      expect(cmd.insertedIndex, 0);
    });

    test('undo removes vertex', () {
      final vertex = NetworkVertex(position: const Offset(10, 20));
      final cmd = AddVertexCommand(node: node, vertex: vertex);

      history.execute(cmd);
      history.undo();

      expect(node.network.vertices, isEmpty);
    });

    test('redo re-adds vertex', () {
      final vertex = NetworkVertex(position: const Offset(10, 20));
      final cmd = AddVertexCommand(node: node, vertex: vertex);

      history.execute(cmd);
      history.undo();
      history.redo();

      expect(node.network.vertices, hasLength(1));
    });
  });

  // ===========================================================================
  // RemoveVertexCommand
  // ===========================================================================

  group('RemoveVertexCommand', () {
    test('execute removes vertex', () {
      // Add a vertex first
      node.network.addVertex(NetworkVertex(position: const Offset(10, 20)));

      final cmd = RemoveVertexCommand(node: node, vertexIndex: 0);
      history.execute(cmd);

      expect(node.network.vertices, isEmpty);
    });

    test('undo restores vertex via snapshot', () {
      node.network.addVertex(NetworkVertex(position: const Offset(10, 20)));

      final cmd = RemoveVertexCommand(node: node, vertexIndex: 0);
      history.execute(cmd);
      history.undo();

      expect(node.network.vertices, hasLength(1));
      expect(node.network.vertices[0].position, const Offset(10, 20));
    });
  });

  // ===========================================================================
  // AddSegmentCommand
  // ===========================================================================

  group('AddSegmentCommand', () {
    test('execute adds segment', () {
      node.network.addVertex(NetworkVertex(position: const Offset(0, 0)));
      node.network.addVertex(NetworkVertex(position: const Offset(100, 100)));

      final segment = NetworkSegment(start: 0, end: 1);
      final cmd = AddSegmentCommand(node: node, segment: segment);
      history.execute(cmd);

      expect(node.network.segments, hasLength(1));
      expect(cmd.insertedIndex, 0);
    });

    test('undo removes segment', () {
      node.network.addVertex(NetworkVertex(position: const Offset(0, 0)));
      node.network.addVertex(NetworkVertex(position: const Offset(100, 100)));

      final segment = NetworkSegment(start: 0, end: 1);
      final cmd = AddSegmentCommand(node: node, segment: segment);
      history.execute(cmd);
      history.undo();

      expect(node.network.segments, isEmpty);
    });
  });

  // ===========================================================================
  // RemoveSegmentCommand
  // ===========================================================================

  group('RemoveSegmentCommand', () {
    test('execute removes segment', () {
      node.network.addVertex(NetworkVertex(position: const Offset(0, 0)));
      node.network.addVertex(NetworkVertex(position: const Offset(100, 100)));
      node.network.addSegment(NetworkSegment(start: 0, end: 1));

      final cmd = RemoveSegmentCommand(node: node, segmentIndex: 0);
      history.execute(cmd);

      expect(node.network.segments, isEmpty);
    });

    test('undo restores segment via snapshot', () {
      node.network.addVertex(NetworkVertex(position: const Offset(0, 0)));
      node.network.addVertex(NetworkVertex(position: const Offset(100, 100)));
      node.network.addSegment(NetworkSegment(start: 0, end: 1));

      final cmd = RemoveSegmentCommand(node: node, segmentIndex: 0);
      history.execute(cmd);
      history.undo();

      expect(node.network.segments, hasLength(1));
    });
  });

  // ===========================================================================
  // MoveVertexCommand
  // ===========================================================================

  group('MoveVertexCommand', () {
    test('execute moves vertex', () {
      node.network.addVertex(NetworkVertex(position: const Offset(0, 0)));

      final cmd = MoveVertexCommand(
        node: node,
        vertexIndex: 0,
        newPosition: const Offset(50, 75),
      );
      history.execute(cmd);

      expect(node.network.vertices[0].position, const Offset(50, 75));
    });

    test('undo restores original position', () {
      node.network.addVertex(NetworkVertex(position: const Offset(10, 20)));

      final cmd = MoveVertexCommand(
        node: node,
        vertexIndex: 0,
        newPosition: const Offset(50, 75),
      );
      history.execute(cmd);
      history.undo();

      expect(node.network.vertices[0].position, const Offset(10, 20));
    });

    test('canMergeWith returns true for same vertex', () {
      node.network.addVertex(NetworkVertex(position: const Offset(0, 0)));

      final cmd1 = MoveVertexCommand(
        node: node,
        vertexIndex: 0,
        newPosition: const Offset(10, 10),
      );
      final cmd2 = MoveVertexCommand(
        node: node,
        vertexIndex: 0,
        newPosition: const Offset(20, 20),
      );

      expect(cmd1.canMergeWith(cmd2), true);
    });

    test('canMergeWith returns false for different vertices', () {
      node.network.addVertex(NetworkVertex(position: const Offset(0, 0)));
      node.network.addVertex(NetworkVertex(position: const Offset(100, 100)));

      final cmd1 = MoveVertexCommand(
        node: node,
        vertexIndex: 0,
        newPosition: const Offset(10, 10),
      );
      final cmd2 = MoveVertexCommand(
        node: node,
        vertexIndex: 1,
        newPosition: const Offset(20, 20),
      );

      expect(cmd1.canMergeWith(cmd2), false);
    });

    test('mergeWith updates new position', () {
      node.network.addVertex(NetworkVertex(position: const Offset(0, 0)));

      final cmd1 = MoveVertexCommand(
        node: node,
        vertexIndex: 0,
        newPosition: const Offset(10, 10),
      );
      final cmd2 = MoveVertexCommand(
        node: node,
        vertexIndex: 0,
        newPosition: const Offset(50, 50),
      );

      cmd1.mergeWith(cmd2);
      history.execute(cmd1);

      expect(node.network.vertices[0].position, const Offset(50, 50));
    });
  });
}
