import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/tabular/cell_address.dart';
import 'package:fluera_engine/src/core/tabular/merge_region_manager.dart';
import 'package:fluera_engine/src/core/tabular/spreadsheet_model.dart';

void main() {
  // ===========================================================================
  // P0.1 — Prefix-sum arrays for columnOffset / rowOffset
  // ===========================================================================

  group('SpreadsheetModel prefix-sum offsets', () {
    test('columnOffset with default widths', () {
      final model = SpreadsheetModel(defaultColumnWidth: 100);
      expect(model.columnOffset(0), 0.0);
      expect(model.columnOffset(1), 100.0);
      expect(model.columnOffset(5), 500.0);
      expect(model.columnOffset(100), 10000.0);
    });

    test('rowOffset with default heights', () {
      final model = SpreadsheetModel(defaultRowHeight: 28);
      expect(model.rowOffset(0), 0.0);
      expect(model.rowOffset(1), 28.0);
      expect(model.rowOffset(10), 280.0);
    });

    test('columnOffset with custom widths', () {
      final model = SpreadsheetModel(defaultColumnWidth: 100);
      model.setColumnWidth(0, 50); // half width
      model.setColumnWidth(2, 200); // double width
      // col 0: 50, col 1: 100 (default), col 2: 200
      expect(model.columnOffset(0), 0.0);
      expect(model.columnOffset(1), 50.0);
      expect(model.columnOffset(2), 150.0);
      expect(model.columnOffset(3), 350.0);
      // col 3+ use default 100
      expect(model.columnOffset(4), 450.0);
    });

    test('rowOffset with custom heights', () {
      final model = SpreadsheetModel(defaultRowHeight: 28);
      model.setRowHeight(0, 50);
      model.setRowHeight(1, 14);
      // row 0: 50, row 1: 14, row 2+: 28
      expect(model.rowOffset(0), 0.0);
      expect(model.rowOffset(1), 50.0);
      expect(model.rowOffset(2), 64.0);
      expect(model.rowOffset(3), 92.0);
    });

    test('prefix-sum invalidation on setColumnWidth', () {
      final model = SpreadsheetModel(defaultColumnWidth: 100);
      expect(model.columnOffset(5), 500.0);
      // Change width of column 2 → cache should invalidate.
      model.setColumnWidth(2, 200);
      // col0=100, col1=100, col2=200, col3=100(default), col4=100(default)
      expect(model.columnOffset(3), 400.0); // 100 + 100 + 200
      expect(model.columnOffset(5), 600.0); // 100+100+200+100+100
    });

    test('prefix-sum invalidation on setRowHeight', () {
      final model = SpreadsheetModel(defaultRowHeight: 28);
      expect(model.rowOffset(3), 84.0);
      model.setRowHeight(1, 56);
      // row0=28, row1=56, row2=28
      expect(model.rowOffset(3), 112.0);
    });

    test('prefix-sum invalidation on defaultColumnWidth change', () {
      final model = SpreadsheetModel(defaultColumnWidth: 100);
      expect(model.columnOffset(5), 500.0);
      model.defaultColumnWidth = 50;
      expect(model.columnOffset(5), 250.0);
    });

    test('prefix-sum invalidation on defaultRowHeight change', () {
      final model = SpreadsheetModel(defaultRowHeight: 28);
      expect(model.rowOffset(5), 140.0);
      model.defaultRowHeight = 14;
      expect(model.rowOffset(5), 70.0);
    });

    test('totalWidth and totalHeight use prefix-sum', () {
      final model = SpreadsheetModel(
        defaultColumnWidth: 100,
        defaultRowHeight: 28,
      );
      model.setColumnWidth(0, 50);
      expect(model.totalWidth(3), model.columnOffset(3));
      expect(model.totalHeight(5), model.rowOffset(5));
    });

    test('columnOffset matches naive computation for mixed widths', () {
      final model = SpreadsheetModel(defaultColumnWidth: 80);
      model.setColumnWidth(1, 120);
      model.setColumnWidth(3, 40);
      model.setColumnWidth(7, 200);

      // Verify against naive computation for columns 0..10.
      for (int c = 0; c <= 10; c++) {
        double naive = 0;
        for (int i = 0; i < c; i++) {
          naive += model.getColumnWidth(i);
        }
        expect(
          model.columnOffset(c),
          naive,
          reason: 'columnOffset($c) should be $naive',
        );
      }
    });
  });

  // ===========================================================================
  // P0.2 — MergeRegionManager inverse index
  // ===========================================================================

  group('MergeRegionManager O(1) index', () {
    test('isMerged correctly identifies merged cells', () {
      final mgr = MergeRegionManager();
      // Merge A1:C3 (cols 0-2, rows 0-2)
      mgr.addRegion(CellRange.fromLabel('A1:C3'));

      expect(mgr.isMerged(const CellAddress(0, 0)), true); // A1
      expect(mgr.isMerged(const CellAddress(1, 1)), true); // B2
      expect(mgr.isMerged(const CellAddress(2, 2)), true); // C3
      expect(mgr.isMerged(const CellAddress(3, 0)), false); // D1 (outside)
      expect(mgr.isMerged(const CellAddress(0, 3)), false); // A4 (outside)
    });

    test('getRegion returns the correct region', () {
      final mgr = MergeRegionManager();
      final region = CellRange.fromLabel('B2:D4');
      mgr.addRegion(region);

      expect(mgr.getRegion(const CellAddress(1, 1)), region);
      expect(mgr.getRegion(const CellAddress(3, 3)), region);
      expect(mgr.getRegion(const CellAddress(0, 0)), isNull);
    });

    test('getMasterCell returns top-left of merge', () {
      final mgr = MergeRegionManager();
      mgr.addRegion(CellRange.fromLabel('B2:D4'));

      // Master is B2 = (1, 1).
      expect(
        mgr.getMasterCell(const CellAddress(3, 3)),
        const CellAddress(1, 1),
      );
      // Non-merged cell returns itself.
      expect(
        mgr.getMasterCell(const CellAddress(0, 0)),
        const CellAddress(0, 0),
      );
    });

    test('isMasterCell and isHiddenByMerge', () {
      final mgr = MergeRegionManager();
      mgr.addRegion(CellRange.fromLabel('A1:B2'));

      expect(mgr.isMasterCell(const CellAddress(0, 0)), true);
      expect(mgr.isMasterCell(const CellAddress(1, 0)), false);
      expect(mgr.isMasterCell(const CellAddress(0, 1)), false);

      expect(mgr.isHiddenByMerge(const CellAddress(0, 0)), false); // master
      expect(mgr.isHiddenByMerge(const CellAddress(1, 0)), true); // hidden
      expect(mgr.isHiddenByMerge(const CellAddress(1, 1)), true); // hidden
      expect(mgr.isHiddenByMerge(const CellAddress(2, 0)), false); // outside
    });

    test('index updates after removeRegion', () {
      final mgr = MergeRegionManager();
      final region = CellRange.fromLabel('A1:B2');
      mgr.addRegion(region);
      expect(mgr.isMerged(const CellAddress(0, 0)), true);

      mgr.removeRegion(region);
      expect(mgr.isMerged(const CellAddress(0, 0)), false);
      expect(mgr.getRegion(const CellAddress(1, 1)), isNull);
    });

    test('index updates after removeRegionAt', () {
      final mgr = MergeRegionManager();
      mgr.addRegion(CellRange.fromLabel('A1:B2'));
      expect(mgr.isMerged(const CellAddress(1, 1)), true);

      mgr.removeRegionAt(const CellAddress(0, 0));
      expect(mgr.isMerged(const CellAddress(1, 1)), false);
      expect(mgr.regionCount, 0);
    });

    test('index clears on clear()', () {
      final mgr = MergeRegionManager();
      mgr.addRegion(CellRange.fromLabel('A1:B2'));
      mgr.addRegion(CellRange.fromLabel('D4:E5'));
      expect(mgr.isMerged(const CellAddress(0, 0)), true);
      expect(mgr.isMerged(const CellAddress(4, 4)), true);

      mgr.clear();
      expect(mgr.isMerged(const CellAddress(0, 0)), false);
      expect(mgr.isMerged(const CellAddress(4, 4)), false);
    });

    test('loadFromJson rebuilds index', () {
      final mgr = MergeRegionManager();
      mgr.addRegion(CellRange.fromLabel('A1:C3'));
      final json = mgr.toJson();

      final mgr2 = MergeRegionManager();
      mgr2.loadFromJson(json);
      expect(mgr2.isMerged(const CellAddress(1, 1)), true);
      expect(mgr2.getRegion(const CellAddress(2, 2)), isNotNull);
      expect(mgr2.isMerged(const CellAddress(3, 3)), false);
    });

    test('multiple non-overlapping regions', () {
      final mgr = MergeRegionManager();
      final r1 = CellRange.fromLabel('A1:B2');
      final r2 = CellRange.fromLabel('D1:E2');
      mgr.addRegion(r1);
      mgr.addRegion(r2);

      expect(mgr.getRegion(const CellAddress(0, 0)), r1);
      expect(mgr.getRegion(const CellAddress(3, 0)), r2);
      expect(mgr.getRegion(const CellAddress(2, 0)), isNull); // gap
    });
  });
}
