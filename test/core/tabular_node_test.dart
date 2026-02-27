import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/nodes/tabular_node.dart';
import 'package:fluera_engine/src/core/scene_graph/node_id.dart';
import 'package:fluera_engine/src/core/scene_graph/canvas_node_factory.dart';
import 'package:fluera_engine/src/core/tabular/cell_address.dart';
import 'package:fluera_engine/src/core/tabular/cell_value.dart';
import 'package:fluera_engine/src/core/tabular/cell_node.dart';

void main() {
  group('TabularNode', () {
    test('default construction', () {
      final node = TabularNode(id: const NodeId('test-1'));
      expect(node.model.cellCount, 0);
      expect(node.showColumnHeaders, true);
      expect(node.showRowHeaders, true);
      expect(node.visibleColumns, 10);
      expect(node.visibleRows, 20);
    });

    test('embeds SpreadsheetModel and evaluator', () {
      final node = TabularNode(id: const NodeId('test-2'));
      node.evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(10),
      );
      node.evaluator.setCellAndEvaluate(
        const CellAddress(1, 0),
        const FormulaValue('A1 * 3'),
      );

      expect(node.model.cellCount, 2);
      expect(
        node.evaluator.getComputedValue(const CellAddress(1, 0)),
        const NumberValue(30),
      );
    });

    test('localBounds incorporates headers and grid sizing', () {
      final node = TabularNode(
        id: const NodeId('test-3'),
        visibleColumns: 5,
        visibleRows: 3,
      );
      // Default: headerWidth=50, headerHeight=28, colWidth=100, rowHeight=28
      final bounds = node.localBounds;
      expect(bounds.width, 50 + 5 * 100); // 550
      expect(bounds.height, 28 + 3 * 28.0); // 112
    });

    test('JSON serialization roundtrip', () {
      final node = TabularNode(
        id: const NodeId('tab-1'),
        name: 'Budget',
        visibleColumns: 5,
        visibleRows: 3,
      );
      node.evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(100),
      );
      node.evaluator.setCellAndEvaluate(
        const CellAddress(1, 0),
        const TextValue('Revenue'),
      );

      final json = node.toJson();
      expect(json['nodeType'], 'tabular');

      final restored = TabularNode.fromJson(json);
      expect(restored.id.value, 'tab-1');
      expect(restored.model.cellCount, 2);
      expect(
        restored.model.getCell(const CellAddress(0, 0))?.value,
        const NumberValue(100),
      );
      expect(restored.visibleColumns, 5);
    });

    test('CanvasNodeFactory deserializes tabular node', () {
      final node = TabularNode(id: const NodeId('factory-1'));
      node.evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(42),
      );

      final json = node.toJson();
      final restored = CanvasNodeFactory.fromJson(json);
      expect(restored, isA<TabularNode>());
      expect((restored as TabularNode).model.cellCount, 1);
    });

    test('clone produces independent copy', () {
      final original = TabularNode(
        id: const NodeId('orig-1'),
        name: 'Original',
      );
      original.evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(1),
      );
      original.evaluator.setCellAndEvaluate(
        const CellAddress(1, 0),
        const FormulaValue('A1 + 10'),
      );

      final cloned = original.clone();
      expect(cloned, isA<TabularNode>());
      final clonedTab = cloned as TabularNode;

      // Verify independent copy.
      expect(clonedTab.id.value, isNot('orig-1'));
      expect(clonedTab.model.cellCount, 2);

      // Change original should NOT affect clone.
      original.evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(99),
      );
      expect(
        clonedTab.evaluator.getComputedValue(const CellAddress(1, 0)),
        const NumberValue(11), // still using original A1=1
      );
    });

    test('formulas are re-evaluated after fromJson', () {
      final node = TabularNode(id: const NodeId('formula-test'));
      node.evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(5),
      );
      node.evaluator.setCellAndEvaluate(
        const CellAddress(1, 0),
        const FormulaValue('A1 * 4'),
      );

      // Serialize then restore.
      final json = node.toJson();
      final restored = TabularNode.fromJson(json);

      // Formula should be re-evaluated.
      expect(
        restored.evaluator.getComputedValue(const CellAddress(1, 0)),
        const NumberValue(20),
      );
    });

    test('dispose cleans up evaluator', () {
      final node = TabularNode(id: const NodeId('dispose-test'));
      node.evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(1),
      );
      node.dispose();
      // After dispose, the evaluator's stream should be closed.
      // We just verify it doesn't throw.
    });
  });
}
