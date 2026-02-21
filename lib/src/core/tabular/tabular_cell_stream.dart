import 'dart:async';

import 'cell_address.dart';
import 'cell_value.dart';
import 'spreadsheet_evaluator.dart';

/// 📊 Stream-based cell change notification for the tabular engine.
///
/// Re-exports [CellChangeEvent] from the evaluator and provides
/// subscription utilities for filtering by cell address.

/// Subscribe to changes for a specific cell address.
///
/// Returns a filtered [StreamSubscription] that only fires when the
/// specified cell changes.
StreamSubscription<CellChangeEvent> subscribeToCellChanges(
  SpreadsheetEvaluator evaluator,
  CellAddress address,
  void Function(CellChangeEvent event) onChanged,
) {
  return evaluator.onCellChanged
      .where((event) => event.address == address)
      .listen(onChanged);
}

/// Subscribe to changes for any cell in a range.
StreamSubscription<CellChangeEvent> subscribeToRangeChanges(
  SpreadsheetEvaluator evaluator,
  CellRange range,
  void Function(CellChangeEvent event) onChanged,
) {
  return evaluator.onCellChanged
      .where((event) => range.contains(event.address))
      .listen(onChanged);
}

/// Subscribe to changes for any cell, with an optional filter.
StreamSubscription<CellChangeEvent> subscribeToAllChanges(
  SpreadsheetEvaluator evaluator,
  void Function(CellChangeEvent event) onChanged, {
  bool Function(CellChangeEvent event)? filter,
}) {
  var stream = evaluator.onCellChanged;
  if (filter != null) {
    stream = stream.where(filter);
  }
  return stream.listen(onChanged);
}
