import '../tabular/spreadsheet_model.dart';

/// 📊 Shared binary search utilities for tabular hit-testing.
///
/// Used by [TabularRenderer], [TabularTool], and [TabularInteractionTool]
/// to convert pixel coordinates to column/row indices in O(log n) via
/// prefix-sum offsets.
class TabularHitTestUtils {
  TabularHitTestUtils._();

  /// Binary search for the first column whose right edge is past [x].
  ///
  /// Requires [cols] > 0 and [x] within bounds.
  static int findColumn(SpreadsheetModel model, int cols, double x) {
    int lo = 0, hi = cols - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (model.columnOffset(mid) + model.getColumnWidth(mid) <= x) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Binary search for the first row whose bottom edge is past [y].
  ///
  /// Requires [rows] > 0 and [y] within bounds.
  static int findRow(SpreadsheetModel model, int rows, double y) {
    int lo = 0, hi = rows - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (model.rowOffset(mid) + model.getRowHeight(mid) <= y) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
}
