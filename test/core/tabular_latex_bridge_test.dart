import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/tabular/cell_address.dart';
import 'package:fluera_engine/src/core/tabular/cell_node.dart';
import 'package:fluera_engine/src/core/tabular/cell_value.dart';
import 'package:fluera_engine/src/core/tabular/spreadsheet_evaluator.dart';
import 'package:fluera_engine/src/core/tabular/spreadsheet_model.dart';
import 'package:fluera_engine/src/core/tabular/tabular_latex_bridge.dart';
import 'package:fluera_engine/src/core/nodes/latex_node.dart';
import 'package:fluera_engine/src/core/scene_graph/node_id.dart';
import 'package:fluera_engine/src/utils/uid.dart';

void main() {
  late SpreadsheetModel model;
  late SpreadsheetEvaluator evaluator;

  setUp(() {
    model = SpreadsheetModel();
    evaluator = SpreadsheetEvaluator(model);
  });

  tearDown(() {
    evaluator.dispose();
  });

  LatexNode _makeLatex(String source) {
    return LatexNode(id: NodeId(generateUid()), latexSource: source);
  }

  // ===========================================================================
  // Simple cell substitution (backward compatibility)
  // ===========================================================================

  group('TabularLatexBridge - simple cell substitution', () {
    test('substitutes single cell reference', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(42),
      );
      final node = _makeLatex(r'x = {A1}');
      final bridge = TabularLatexBridge(evaluator);
      bridge.registerLatexNode(node, 'tab-1');

      expect(node.latexSource, 'x = 42');
      bridge.dispose();
    });

    test('substitutes multiple cell references', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(3),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(1, 0),
        const NumberValue(7),
      );
      final node = _makeLatex(r'{A1} + {B1} = 10');
      final bridge = TabularLatexBridge(evaluator);
      bridge.registerLatexNode(node, 'tab-1');

      expect(node.latexSource, '3 + 7 = 10');
      bridge.dispose();
    });

    test('no placeholders → no registration', () {
      final node = _makeLatex(r'\frac{a}{b}');
      final bridge = TabularLatexBridge(evaluator);
      bridge.registerLatexNode(node, 'tab-1');

      expect(bridge.isRegistered(node.id.toString()), isFalse);
      bridge.dispose();
    });

    test('text cells are substituted correctly', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const TextValue('hello'),
      );
      final node = _makeLatex(r'Value: {A1}');
      final bridge = TabularLatexBridge(evaluator);
      bridge.registerLatexNode(node, 'tab-1');

      expect(node.latexSource, 'Value: hello');
      bridge.dispose();
    });

    test('empty cell substitutes empty string', () {
      // A1 not set → EmptyValue
      final node = _makeLatex(r'x = {A1}');
      final bridge = TabularLatexBridge(evaluator);
      bridge.registerLatexNode(node, 'tab-1');

      expect(node.latexSource, 'x = ');
      bridge.dispose();
    });
  });

  // ===========================================================================
  // Formatted cell substitution
  // ===========================================================================

  group('TabularLatexBridge - formatted cell substitution', () {
    test('formats number with pattern', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(1234.567),
      );
      final node = _makeLatex(r'Total: {A1:#,##0.00}');
      final bridge = TabularLatexBridge(evaluator);
      bridge.registerLatexNode(node, 'tab-1');

      expect(node.latexSource, 'Total: 1,234.57');
      bridge.dispose();
    });

    test('formats percentage', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(0.856),
      );
      final node = _makeLatex(r'Rate: {A1:0%}');
      final bridge = TabularLatexBridge(evaluator);
      bridge.registerLatexNode(node, 'tab-1');

      expect(node.latexSource, 'Rate: 86%');
      bridge.dispose();
    });

    test('non-numeric cell with format falls back to displayString', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const TextValue('N/A'),
      );
      final node = _makeLatex(r'Value: {A1:#,##0}');
      final bridge = TabularLatexBridge(evaluator);
      bridge.registerLatexNode(node, 'tab-1');

      expect(node.latexSource, 'Value: N/A');
      bridge.dispose();
    });
  });

  // ===========================================================================
  // Range expansion
  // ===========================================================================

  group('TabularLatexBridge - range expansion', () {
    test('expands vertical range to comma-separated values', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(10),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 1),
        const NumberValue(20),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 2),
        const NumberValue(30),
      );
      final node = _makeLatex(r'Values: {A1:A3}');
      final bridge = TabularLatexBridge(evaluator);
      bridge.registerLatexNode(node, 'tab-1');

      expect(node.latexSource, 'Values: 10, 20, 30');
      bridge.dispose();
    });

    test('skips empty cells in range', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(1),
      );
      // A2 is empty
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 2),
        const NumberValue(3),
      );
      final node = _makeLatex(r'Values: {A1:A3}');
      final bridge = TabularLatexBridge(evaluator);
      bridge.registerLatexNode(node, 'tab-1');

      expect(node.latexSource, 'Values: 1, 3');
      bridge.dispose();
    });
  });

  // ===========================================================================
  // Aggregate functions
  // ===========================================================================

  group('TabularLatexBridge - aggregate placeholders', () {
    setUp(() {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(10),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 1),
        const NumberValue(20),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 2),
        const NumberValue(30),
      );
    });

    test('SUM aggregate', () {
      final node = _makeLatex(r'Total: {SUM(A1:A3)}');
      final bridge = TabularLatexBridge(evaluator);
      bridge.registerLatexNode(node, 'tab-1');
      expect(node.latexSource, 'Total: 60');
      bridge.dispose();
    });

    test('AVG aggregate', () {
      final node = _makeLatex(r'Avg: {AVG(A1:A3)}');
      final bridge = TabularLatexBridge(evaluator);
      bridge.registerLatexNode(node, 'tab-1');
      expect(node.latexSource, 'Avg: 20');
      bridge.dispose();
    });

    test('MIN aggregate', () {
      final node = _makeLatex(r'Min: {MIN(A1:A3)}');
      final bridge = TabularLatexBridge(evaluator);
      bridge.registerLatexNode(node, 'tab-1');
      expect(node.latexSource, 'Min: 10');
      bridge.dispose();
    });

    test('MAX aggregate', () {
      final node = _makeLatex(r'Max: {MAX(A1:A3)}');
      final bridge = TabularLatexBridge(evaluator);
      bridge.registerLatexNode(node, 'tab-1');
      expect(node.latexSource, 'Max: 30');
      bridge.dispose();
    });

    test('COUNT aggregate', () {
      final node = _makeLatex(r'Count: {COUNT(A1:A3)}');
      final bridge = TabularLatexBridge(evaluator);
      bridge.registerLatexNode(node, 'tab-1');
      expect(node.latexSource, 'Count: 3');
      bridge.dispose();
    });

    test('formatted aggregate', () {
      final node = _makeLatex(r'Total: {SUM(A1:A3):#,##0.00}');
      final bridge = TabularLatexBridge(evaluator);
      bridge.registerLatexNode(node, 'tab-1');
      expect(node.latexSource, 'Total: 60.00');
      bridge.dispose();
    });

    test('aggregate on empty range returns #N/A', () {
      final node = _makeLatex(r'Sum: {SUM(D1:D3)}');
      final bridge = TabularLatexBridge(evaluator);
      bridge.registerLatexNode(node, 'tab-1');
      expect(node.latexSource, 'Sum: #N/A');
      bridge.dispose();
    });

    test('COUNT on empty range returns 0', () {
      final node = _makeLatex(r'Count: {COUNT(D1:D3)}');
      final bridge = TabularLatexBridge(evaluator);
      bridge.registerLatexNode(node, 'tab-1');
      expect(node.latexSource, 'Count: 0');
      bridge.dispose();
    });
  });

  // ===========================================================================
  // Provenance tracking
  // ===========================================================================

  group('TabularLatexBridge - provenance', () {
    test('getCellsReferencedBy returns correct addresses', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(1),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(1, 0),
        const NumberValue(2),
      );

      final node = _makeLatex(r'{A1} + {B1}');
      final bridge = TabularLatexBridge(evaluator);
      bridge.registerLatexNode(node, 'tab-1');

      final refs = bridge.getCellsReferencedBy(node.id.toString());
      expect(refs, contains(const CellAddress(0, 0)));
      expect(refs, contains(const CellAddress(1, 0)));
      expect(refs.length, 2);
      bridge.dispose();
    });

    test('getLatexNodesReferencingCell returns correct node IDs', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(42),
      );

      final node1 = _makeLatex(r'x = {A1}');
      final node2 = _makeLatex(r'y = {A1}^2');
      final bridge = TabularLatexBridge(evaluator);
      bridge.registerLatexNode(node1, 'tab-1');
      bridge.registerLatexNode(node2, 'tab-1');

      final refs = bridge.getLatexNodesReferencingCell(const CellAddress(0, 0));
      expect(refs, contains(node1.id.toString()));
      expect(refs, contains(node2.id.toString()));
      bridge.dispose();
    });

    test('getCellsReferencedBy returns empty for unregistered node', () {
      final bridge = TabularLatexBridge(evaluator);
      expect(bridge.getCellsReferencedBy('nonexistent'), isEmpty);
      bridge.dispose();
    });

    test('provenanceMap returns all entries', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(1),
      );
      final node = _makeLatex(r'{A1}');
      final bridge = TabularLatexBridge(evaluator);
      bridge.registerLatexNode(node, 'tab-1');

      final map = bridge.provenanceMap;
      expect(map.length, 1);
      expect(map[node.id.toString()], contains(const CellAddress(0, 0)));
      bridge.dispose();
    });
  });

  // ===========================================================================
  // Reactive updates
  // ===========================================================================

  group('TabularLatexBridge - reactive updates', () {
    test('updates LaTeX source when referenced cell changes', () async {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(10),
      );

      final node = _makeLatex(r'x = {A1}');
      final bridge = TabularLatexBridge(evaluator);
      bridge.registerLatexNode(node, 'tab-1');
      expect(node.latexSource, 'x = 10');

      // Change the cell value.
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(99),
      );

      // Allow stream to propagate.
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(node.latexSource, 'x = 99');
      bridge.dispose();
    });
  });

  // ===========================================================================
  // Registration lifecycle
  // ===========================================================================

  group('TabularLatexBridge - registration lifecycle', () {
    test('unregister stops tracking', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(1),
      );
      final node = _makeLatex(r'{A1}');
      final bridge = TabularLatexBridge(evaluator);
      bridge.registerLatexNode(node, 'tab-1');

      expect(bridge.isRegistered(node.id.toString()), isTrue);
      bridge.unregisterLatexNode(node.id.toString());
      expect(bridge.isRegistered(node.id.toString()), isFalse);
      bridge.dispose();
    });

    test('re-registering replaces previous registration', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(1),
      );
      final node = _makeLatex(r'{A1}');
      final bridge = TabularLatexBridge(evaluator);
      bridge.registerLatexNode(node, 'tab-1');

      // Re-register with different source (simulate latexSource change).
      node.latexSource = r'{A1} + {A1}';
      bridge.registerLatexNode(node, 'tab-1');

      expect(bridge.registeredNodeIds.length, 1);
      bridge.dispose();
    });

    test('dispose clears all registrations', () {
      final node = _makeLatex(r'{A1}');
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(1),
      );
      final bridge = TabularLatexBridge(evaluator);
      bridge.registerLatexNode(node, 'tab-1');

      bridge.dispose();
      expect(bridge.registeredNodeIds, isEmpty);
    });
  });

  // ===========================================================================
  // Mixed placeholders
  // ===========================================================================

  group('TabularLatexBridge - mixed placeholder types', () {
    test('combines cell, formatted, range, and aggregate', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(100),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 1),
        const NumberValue(200),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 2),
        const NumberValue(300),
      );

      final node = _makeLatex(
        r'Cell: {A1}, Fmt: {A1:#,##0}, Range: {A1:A3}, Sum: {SUM(A1:A3)}',
      );
      final bridge = TabularLatexBridge(evaluator);
      bridge.registerLatexNode(node, 'tab-1');

      expect(
        node.latexSource,
        'Cell: 100, Fmt: 100, Range: 100, 200, 300, Sum: 600',
      );
      bridge.dispose();
    });
  });
}
