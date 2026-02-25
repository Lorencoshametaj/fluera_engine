import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/tabular/spreadsheet_model.dart';
import 'package:nebula_engine/src/core/tabular/cell_address.dart';
import 'package:nebula_engine/src/core/tabular/cell_node.dart';
import 'package:nebula_engine/src/core/tabular/cell_value.dart';

void main() {
  late SpreadsheetModel model;

  setUp(() {
    model = SpreadsheetModel();
  });

  // ===========================================================================
  // Cell CRUD
  // ===========================================================================

  group('SpreadsheetModel - cell CRUD', () {
    test('starts empty', () {
      expect(model.cellCount, 0);
      expect(model.getCell(CellAddress(0, 0)), isNull);
    });

    test('setCell and getCell', () {
      final cell = CellNode(value: NumberValue(42));
      model.setCell(CellAddress(0, 0), cell);
      expect(model.getCell(CellAddress(0, 0)), isNotNull);
      expect(model.cellCount, 1);
    });

    test('hasCell returns correct state', () {
      expect(model.hasCell(CellAddress(0, 0)), isFalse);
      model.setCell(CellAddress(0, 0), CellNode(value: NumberValue(1)));
      expect(model.hasCell(CellAddress(0, 0)), isTrue);
    });

    test('clearCell removes cell', () {
      model.setCell(CellAddress(0, 0), CellNode(value: NumberValue(10)));
      final removed = model.clearCell(CellAddress(0, 0));
      expect(removed, isNotNull);
      expect(model.hasCell(CellAddress(0, 0)), isFalse);
    });

    test('clearCell on empty returns null', () {
      expect(model.clearCell(CellAddress(5, 5)), isNull);
    });

    test('setCell overwrites existing', () {
      model.setCell(CellAddress(0, 0), CellNode(value: NumberValue(1)));
      model.setCell(CellAddress(0, 0), CellNode(value: NumberValue(2)));
      expect(model.cellCount, 1);
    });
  });

  // ===========================================================================
  // Named ranges
  // ===========================================================================

  group('SpreadsheetModel - named ranges', () {
    test('setNamedRange and getNamedRange', () {
      final range = CellRange(CellAddress(0, 0), CellAddress(2, 2));
      model.setNamedRange('TestRange', range);
      expect(model.getNamedRange('TestRange'), isNotNull);
    });

    test('hasNamedRange checks correctly', () {
      expect(model.hasNamedRange('Missing'), isFalse);
      model.setNamedRange(
        'Found',
        CellRange(CellAddress(0, 0), CellAddress(1, 1)),
      );
      expect(model.hasNamedRange('Found'), isTrue);
    });

    test('removeNamedRange removes', () {
      model.setNamedRange(
        'ToRemove',
        CellRange(CellAddress(0, 0), CellAddress(1, 1)),
      );
      final removed = model.removeNamedRange('ToRemove');
      expect(removed, isNotNull);
      expect(model.hasNamedRange('ToRemove'), isFalse);
    });
  });

  // ===========================================================================
  // Column/Row sizing
  // ===========================================================================

  group('SpreadsheetModel - sizing', () {
    test('getColumnWidth returns default initially', () {
      expect(model.getColumnWidth(0), greaterThan(0));
    });

    test('setColumnWidth overrides default', () {
      model.setColumnWidth(0, 200);
      expect(model.getColumnWidth(0), 200);
    });

    test('getRowHeight returns default initially', () {
      expect(model.getRowHeight(0), greaterThan(0));
    });

    test('setRowHeight overrides default', () {
      model.setRowHeight(0, 50);
      expect(model.getRowHeight(0), 50);
    });

    test('columnOffset/rowOffset are non-negative', () {
      expect(model.columnOffset(0), greaterThanOrEqualTo(0));
      expect(model.rowOffset(0), greaterThanOrEqualTo(0));
    });

    test('totalWidth/totalHeight are positive for non-zero count', () {
      expect(model.totalWidth(5), greaterThan(0));
      expect(model.totalHeight(5), greaterThan(0));
    });
  });

  // ===========================================================================
  // Clone
  // ===========================================================================

  group('SpreadsheetModel - clone', () {
    test('clone creates independent copy', () {
      model.setCell(CellAddress(0, 0), CellNode(value: NumberValue(42)));
      model.setColumnWidth(0, 150);
      final clone = model.clone();
      expect(clone.cellCount, model.cellCount);
      expect(clone.getColumnWidth(0), 150);
      // Mutating clone doesn't affect original
      clone.clearCell(CellAddress(0, 0));
      expect(model.cellCount, 1);
      expect(clone.cellCount, 0);
    });
  });

  // ===========================================================================
  // Serialization
  // ===========================================================================

  group('SpreadsheetModel - toJson', () {
    test('serializes to JSON map', () {
      model.setCell(CellAddress(0, 0), CellNode(value: NumberValue(42)));
      final json = model.toJson();
      expect(json, isA<Map<String, dynamic>>());
    });
  });
}
