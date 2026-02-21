import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/scene_graph/node_constraint.dart';
import 'package:nebula_engine/src/core/scene_graph/canvas_node.dart';
import 'package:nebula_engine/src/core/scene_graph/node_id.dart';
import 'package:nebula_engine/src/core/nodes/layer_node.dart';

void main() {
  group('NodeConstraint', () {
    test('creates with required fields', () {
      final c = NodeConstraint(
        id: 'c1',
        type: NodeConstraintType.alignCenter,
        sourceNodeId: 'logo',
        targetNodeId: 'title',
      );

      expect(c.id, 'c1');
      expect(c.type, NodeConstraintType.alignCenter);
      expect(c.sourceNodeId, 'logo');
      expect(c.targetNodeId, 'title');
      expect(c.value, 0.0);
      expect(c.isEnabled, isTrue);
    });

    test('equality is based on id', () {
      final c1 = NodeConstraint(
        id: 'same',
        type: NodeConstraintType.alignLeft,
        sourceNodeId: 'a',
        targetNodeId: 'b',
      );
      final c2 = NodeConstraint(
        id: 'same',
        type: NodeConstraintType.alignRight, // different type
        sourceNodeId: 'x',
        targetNodeId: 'y',
      );

      expect(c1, equals(c2));
      expect(c1.hashCode, c2.hashCode);
    });

    test('toJson serializes correctly', () {
      final c = NodeConstraint(
        id: 'c1',
        type: NodeConstraintType.pinDistanceX,
        sourceNodeId: 'a',
        targetNodeId: 'b',
        value: 100.0,
      );

      final json = c.toJson();
      expect(json['id'], 'c1');
      expect(json['type'], 'pinDistanceX');
      expect(json['sourceNodeId'], 'a');
      expect(json['targetNodeId'], 'b');
      expect(json['value'], 100.0);
    });

    test('toJson omits default value and isEnabled', () {
      final c = NodeConstraint(
        id: 'c1',
        type: NodeConstraintType.alignLeft,
        sourceNodeId: 'a',
        targetNodeId: 'b',
      );

      final json = c.toJson();
      expect(json.containsKey('value'), isFalse);
      expect(json.containsKey('isEnabled'), isFalse);
    });

    test('fromJson roundtrip', () {
      final original = NodeConstraint(
        id: 'c1',
        type: NodeConstraintType.matchWidth,
        sourceNodeId: 'a',
        targetNodeId: 'b',
        value: 2.0,
        isEnabled: false,
      );

      final json = original.toJson();
      final restored = NodeConstraint.fromJson(json);

      expect(restored.id, 'c1');
      expect(restored.type, NodeConstraintType.matchWidth);
      expect(restored.sourceNodeId, 'a');
      expect(restored.targetNodeId, 'b');
      expect(restored.value, 2.0);
      expect(restored.isEnabled, isFalse);
    });

    test('fromJson uses defaults for missing optional fields', () {
      final json = {
        'id': 'c1',
        'type': 'alignTop',
        'sourceNodeId': 'a',
        'targetNodeId': 'b',
      };

      final c = NodeConstraint.fromJson(json);
      expect(c.value, 0.0);
      expect(c.isEnabled, isTrue);
    });

    test('toString includes type and node IDs', () {
      final c = NodeConstraint(
        id: 'c1',
        type: NodeConstraintType.pinDistance,
        sourceNodeId: 'a',
        targetNodeId: 'b',
        value: 50.0,
      );

      final s = c.toString();
      expect(s, contains('pinDistance'));
      expect(s, contains('a'));
      expect(s, contains('b'));
    });
  });

  group('NodeConstraintSolver', () {
    test('solve returns true with no constraints', () {
      final solver = NodeConstraintSolver(
        constraints: [],
        nodeResolver: (_) => null,
      );
      expect(solver.solve(), isTrue);
    });

    test('solve returns true when all constraints are disabled', () {
      final c = NodeConstraint(
        id: 'c1',
        type: NodeConstraintType.alignLeft,
        sourceNodeId: 'a',
        targetNodeId: 'b',
        isEnabled: false,
      );

      final solver = NodeConstraintSolver(
        constraints: [c],
        nodeResolver: (_) => null,
      );
      expect(solver.solve(), isTrue);
    });

    test('solve handles missing nodes gracefully', () {
      final c = NodeConstraint(
        id: 'c1',
        type: NodeConstraintType.alignCenter,
        sourceNodeId: 'missing',
        targetNodeId: 'also-missing',
      );

      final solver = NodeConstraintSolver(
        constraints: [c],
        nodeResolver: (_) => null,
      );
      // Should not crash — missing nodes produce zero error
      expect(solver.solve(), isTrue);
    });

    test('solve converges even when nodes have empty bounds', () {
      final source = LayerNode(id: NodeId('source'));
      final target = LayerNode(id: NodeId('target'));

      final nodes = <String, CanvasNode>{'source': source, 'target': target};

      final c = NodeConstraint(
        id: 'c1',
        type: NodeConstraintType.alignCenter,
        sourceNodeId: 'source',
        targetNodeId: 'target',
      );

      final solver = NodeConstraintSolver(
        constraints: [c],
        nodeResolver: (id) => nodes[id],
      );

      // Empty bounds → error 0 → should converge immediately
      expect(solver.solve(), isTrue);
    });
  });
}
