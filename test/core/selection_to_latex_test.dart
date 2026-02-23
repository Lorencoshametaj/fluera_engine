import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/nodes/tabular_node.dart';
import 'package:nebula_engine/src/core/scene_graph/node_id.dart';
import 'package:nebula_engine/src/core/tabular/cell_address.dart';
import 'package:nebula_engine/src/core/tabular/cell_value.dart';
import 'package:nebula_engine/src/core/tabular/selection_to_latex.dart';

/// Helper to create a populated TabularNode for testing.
TabularNode _makeNode({
  required int cols,
  required int rows,
  required List<List<String>> data,
}) {
  final node = TabularNode(
    id: NodeId('test-node'),
    visibleColumns: cols,
    visibleRows: rows,
  );
  for (int r = 0; r < data.length; r++) {
    for (int c = 0; c < data[r].length; c++) {
      final text = data[r][c];
      if (text.isEmpty) continue;
      // Try parsing as number.
      final num = double.tryParse(text);
      final val = num != null ? NumberValue(num) : TextValue(text);
      node.evaluator.setCellAndEvaluate(CellAddress(c, r), val);
    }
  }
  return node;
}

void main() {
  group('SelectionToLatex — basic', () {
    test('converts a single cell', () {
      final node = _makeNode(
        cols: 3,
        rows: 3,
        data: [
          ['Hello', '', ''],
          ['', '', ''],
          ['', '', ''],
        ],
      );
      final range = CellRange(CellAddress(0, 0), CellAddress(0, 0));
      final latex = SelectionToLatex.convert(node, range);

      expect(latex, contains(r'\begin{tabular}'));
      expect(latex, contains(r'\end{tabular}'));
      expect(latex, contains('Hello'));
    });

    test('converts a multi-cell range', () {
      final node = _makeNode(
        cols: 3,
        rows: 3,
        data: [
          ['Name', 'Age', 'Score'],
          ['Alice', '30', '95'],
          ['Bob', '25', '88'],
        ],
      );
      final range = CellRange(CellAddress(0, 0), CellAddress(2, 2));
      final latex = SelectionToLatex.convert(node, range);

      expect(latex, contains('Name'));
      expect(latex, contains('Alice'));
      expect(latex, contains('Bob'));
      expect(latex, contains('95'));
      expect(latex, contains('88'));
      // 3 columns → alignment {|c|c|c|}
      expect(latex, contains('{|c|c|c|}'));
    });

    test('handles empty cells in range', () {
      final node = _makeNode(
        cols: 2,
        rows: 2,
        data: [
          ['A', ''],
          ['', 'D'],
        ],
      );
      final range = CellRange(CellAddress(0, 0), CellAddress(1, 1));
      final latex = SelectionToLatex.convert(node, range);

      expect(latex, contains('A'));
      expect(latex, contains('D'));
      // Empty cells produce empty strings between &
      expect(latex, contains(' & '));
    });
  });

  group('SelectionToLatex — headers', () {
    test('wraps first row in textbf when includeHeaders is true', () {
      final node = _makeNode(
        cols: 2,
        rows: 2,
        data: [
          ['Name', 'Value'],
          ['X', '42'],
        ],
      );
      final range = CellRange(CellAddress(0, 0), CellAddress(1, 1));
      final latex = SelectionToLatex.convert(node, range, includeHeaders: true);

      expect(latex, contains(r'\textbf{Name}'));
      expect(latex, contains(r'\textbf{Value}'));
      // Data rows should NOT be bold.
      expect(latex, isNot(contains(r'\textbf{X}')));
      expect(latex, isNot(contains(r'\textbf{42}')));
    });

    test('does not wrap in textbf when includeHeaders is false', () {
      final node = _makeNode(
        cols: 2,
        rows: 1,
        data: [
          ['Name', 'Value'],
        ],
      );
      final range = CellRange(CellAddress(0, 0), CellAddress(1, 0));
      final latex = SelectionToLatex.convert(node, range);

      expect(latex, isNot(contains(r'\textbf')));
    });
  });

  group('SelectionToLatex — booktabs', () {
    test('uses toprule/midrule/bottomrule when useBooktabs is true', () {
      final node = _makeNode(
        cols: 2,
        rows: 2,
        data: [
          ['A', 'B'],
          ['C', 'D'],
        ],
      );
      final range = CellRange(CellAddress(0, 0), CellAddress(1, 1));
      final latex = SelectionToLatex.convert(
        node,
        range,
        includeHeaders: true,
        useBooktabs: true,
      );

      expect(latex, contains(r'\toprule'));
      expect(latex, contains(r'\midrule'));
      expect(latex, contains(r'\bottomrule'));
      expect(latex, isNot(contains(r'\hline')));
      // No pipe separators in booktabs alignment.
      expect(latex, contains('{c c}'));
    });

    test('uses hline when useBooktabs is false', () {
      final node = _makeNode(
        cols: 2,
        rows: 2,
        data: [
          ['A', 'B'],
          ['C', 'D'],
        ],
      );
      final range = CellRange(CellAddress(0, 0), CellAddress(1, 1));
      final latex = SelectionToLatex.convert(node, range, includeHeaders: true);

      expect(latex, contains(r'\hline'));
      expect(latex, isNot(contains(r'\toprule')));
    });
  });

  group('SelectionToLatex — alignment', () {
    test('uses custom alignment when provided', () {
      final node = _makeNode(
        cols: 3,
        rows: 1,
        data: [
          ['A', 'B', 'C'],
        ],
      );
      final range = CellRange(CellAddress(0, 0), CellAddress(2, 0));
      final latex = SelectionToLatex.convert(node, range, alignment: 'lcr');

      expect(latex, contains('{|l|c|r|}'));
    });
  });

  group('SelectionToLatex — LaTeX escaping', () {
    test('escapes special characters', () {
      final node = _makeNode(
        cols: 1,
        rows: 1,
        data: [
          ['100% profit & loss'],
        ],
      );
      final range = CellRange(CellAddress(0, 0), CellAddress(0, 0));
      final latex = SelectionToLatex.convert(node, range);

      expect(latex, contains(r'100\%'));
      expect(latex, contains(r'\&'));
    });

    test('escapes underscore and hash', () {
      final node = _makeNode(
        cols: 1,
        rows: 1,
        data: [
          ['var_name #1'],
        ],
      );
      final range = CellRange(CellAddress(0, 0), CellAddress(0, 0));
      final latex = SelectionToLatex.convert(node, range);

      expect(latex, contains(r'var\_name'));
      expect(latex, contains(r'\#1'));
    });
  });

  group('SelectionToLatex — merged cells', () {
    test('emits multicolumn for merged master cells', () {
      final node = _makeNode(
        cols: 3,
        rows: 2,
        data: [
          ['Header', '', 'Other'],
          ['A', 'B', 'C'],
        ],
      );
      // Merge A1:B1 (cols 0-1, row 0).
      node.mergeManager.addRegion(
        CellRange(CellAddress(0, 0), CellAddress(1, 0)),
      );

      final range = CellRange(CellAddress(0, 0), CellAddress(2, 1));
      final latex = SelectionToLatex.convert(node, range);

      expect(latex, contains(r'\multicolumn{2}'));
      expect(latex, contains('Header'));
      // The hidden cell should not produce an extra column.
      // Row 2 should have 3 cells.
      final dataRowMatch = RegExp(r'A & B & C');
      expect(latex, contains(dataRowMatch));
    });
  });

  group('SelectionToLatex — inverted range', () {
    test('handles inverted range (end < start)', () {
      final node = _makeNode(
        cols: 2,
        rows: 2,
        data: [
          ['A', 'B'],
          ['C', 'D'],
        ],
      );
      // Inverted: bottom-right to top-left.
      final range = CellRange(CellAddress(1, 1), CellAddress(0, 0));
      final latex = SelectionToLatex.convert(node, range);

      expect(latex, contains('A'));
      expect(latex, contains('D'));
    });
  });

  group('SelectionToLatex — partial selection', () {
    test('exports only the selected sub-range', () {
      final node = _makeNode(
        cols: 4,
        rows: 4,
        data: [
          ['A1', 'B1', 'C1', 'D1'],
          ['A2', 'B2', 'C2', 'D2'],
          ['A3', 'B3', 'C3', 'D3'],
          ['A4', 'B4', 'C4', 'D4'],
        ],
      );
      // Select B2:C3.
      final range = CellRange(CellAddress(1, 1), CellAddress(2, 2));
      final latex = SelectionToLatex.convert(node, range);

      expect(latex, contains('B2'));
      expect(latex, contains('C3'));
      // Should NOT contain cells outside the range.
      expect(latex, isNot(contains('A1')));
      expect(latex, isNot(contains('D4')));
      // 2 columns.
      expect(latex, contains('{|c|c|}'));
    });
  });
}
