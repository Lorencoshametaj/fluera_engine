import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/tabular/cell_address.dart';
import 'package:fluera_engine/src/core/tabular/cell_value.dart';
import 'package:fluera_engine/src/core/tabular/spreadsheet_evaluator.dart';
import 'package:fluera_engine/src/core/tabular/spreadsheet_model.dart';
import 'package:fluera_engine/src/core/tabular/tikz_chart_generator.dart';

void main() {
  late SpreadsheetModel model;
  late SpreadsheetEvaluator evaluator;
  late TikzChartGenerator gen;

  setUp(() {
    model = SpreadsheetModel();
    evaluator = SpreadsheetEvaluator(model);
    gen = TikzChartGenerator(evaluator);

    // Headers: row 0
    evaluator.setCellAndEvaluate(CellAddress(0, 0), const TextValue('Month'));
    evaluator.setCellAndEvaluate(CellAddress(1, 0), const TextValue('Sales'));
    evaluator.setCellAndEvaluate(CellAddress(2, 0), const TextValue('Costs'));

    // Data rows
    evaluator.setCellAndEvaluate(CellAddress(0, 1), const TextValue('Jan'));
    evaluator.setCellAndEvaluate(CellAddress(1, 1), const NumberValue(100));
    evaluator.setCellAndEvaluate(CellAddress(2, 1), const NumberValue(60));

    evaluator.setCellAndEvaluate(CellAddress(0, 2), const TextValue('Feb'));
    evaluator.setCellAndEvaluate(CellAddress(1, 2), const NumberValue(150));
    evaluator.setCellAndEvaluate(CellAddress(2, 2), const NumberValue(80));

    evaluator.setCellAndEvaluate(CellAddress(0, 3), const TextValue('Mar'));
    evaluator.setCellAndEvaluate(CellAddress(1, 3), const NumberValue(200));
    evaluator.setCellAndEvaluate(CellAddress(2, 3), const NumberValue(90));
  });

  tearDown(() => evaluator.dispose());

  final range = CellRange(CellAddress(0, 0), CellAddress(2, 3));

  group('TikzChartGenerator', () {
    test('generates line plot with correct structure', () {
      final result = gen.generate(range, TikzChartType.line);
      expect(result, contains('\\begin{tikzpicture}'));
      expect(result, contains('\\begin{axis}'));
      expect(result, contains('\\end{axis}'));
      expect(result, contains('\\end{tikzpicture}'));
      expect(result, contains('\\addplot'));
      expect(result, contains('mark=*'));
      expect(result, contains('Jan'));
      expect(result, contains('100.0'));
    });

    test('generates bar chart with ybar option', () {
      final result = gen.generate(range, TikzChartType.bar);
      expect(result, contains('ybar'));
      expect(result, contains('nodes near coords'));
      expect(result, contains('fill='));
    });

    test('generates scatter plot with only marks', () {
      final result = gen.generate(range, TikzChartType.scatter);
      expect(result, contains('only marks'));
      expect(result, contains('mark=o'));
    });

    test('generates pie chart from first series', () {
      final result = gen.generate(range, TikzChartType.pie);
      expect(result, contains('\\fill'));
      expect(result, contains('arc'));
      expect(result, contains('Jan'));
    });

    test('includes title option', () {
      final result = gen.generate(
        range,
        TikzChartType.bar,
        opts: const TikzChartOptions(title: 'Revenue Q1'),
      );
      expect(result, contains('title={Revenue Q1}'));
    });

    test('includes axis labels', () {
      final result = gen.generate(
        range,
        TikzChartType.line,
        opts: const TikzChartOptions(xlabel: 'Time', ylabel: 'Amount'),
      );
      expect(result, contains('xlabel={Time}'));
      expect(result, contains('ylabel={Amount}'));
    });

    test('includes legend entries', () {
      final result = gen.generate(range, TikzChartType.line);
      expect(result, contains('\\legend{'));
      expect(result, contains('Sales'));
      expect(result, contains('Costs'));
    });

    test('handles empty data range gracefully', () {
      final emptyRange = CellRange(CellAddress(10, 10), CellAddress(10, 10));
      final result = gen.generate(emptyRange, TikzChartType.bar);
      expect(result, contains('Empty range'));
    });

    test('respects headers=false option', () {
      final result = gen.generate(
        range,
        TikzChartType.line,
        opts: const TikzChartOptions(headers: false),
      );
      // Without headers, first row (Month/Sales/Costs) becomes data
      expect(result, contains('Month'));
      expect(result, contains('Series 1'));
    });

    test('uses custom dimensions', () {
      final result = gen.generate(
        range,
        TikzChartType.bar,
        opts: const TikzChartOptions(width: '15cm', height: '10cm'),
      );
      expect(result, contains('width=15cm'));
      expect(result, contains('height=10cm'));
    });

    test('color cycles through all series', () {
      final result = gen.generate(range, TikzChartType.line);
      // Two series should use two different colors
      expect(result, contains('blue'));
      expect(result, contains('red'));
    });

    test('grid lines enabled by default', () {
      final result = gen.generate(range, TikzChartType.line);
      expect(result, contains('grid=major'));
    });

    test('pie chart percentage labels', () {
      final result = gen.generate(range, TikzChartType.pie);
      // Values: 100, 150, 200 => total 450
      expect(result, contains('%'));
    });
  });
}
