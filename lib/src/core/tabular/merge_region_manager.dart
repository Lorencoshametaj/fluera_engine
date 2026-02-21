import 'cell_address.dart';
import 'cell_node.dart';
import 'cell_value.dart';

/// 📊 Manages merged cell regions in a spreadsheet.
///
/// Merged cells:
/// - Store their value in the top-left cell of the merge region
/// - Other cells in the region are hidden during rendering
/// - The merge region spans the full area for rendering
///
/// ```dart
/// final manager = MergeRegionManager();
/// manager.addRegion(CellRange.fromLabel('A1:C3'));
/// manager.isMerged(CellAddress.fromLabel('B2')); // true
/// manager.getMasterCell(CellAddress.fromLabel('B2')); // A1
/// ```
class MergeRegionManager {
  final List<CellRange> _regions = [];

  /// All current merge regions.
  List<CellRange> get regions => List.unmodifiable(_regions);

  /// Number of merge regions.
  int get regionCount => _regions.length;

  // =========================================================================
  // Queries
  // =========================================================================

  /// Whether [addr] falls within any merge region.
  bool isMerged(CellAddress addr) {
    return _regions.any((r) => r.contains(addr));
  }

  /// Get the merge region containing [addr], or null if not merged.
  CellRange? getRegion(CellAddress addr) {
    for (final region in _regions) {
      if (region.contains(addr)) return region;
    }
    return null;
  }

  /// Get the top-left "master" cell of the merge region containing [addr].
  ///
  /// Returns [addr] itself if it's not merged.
  CellAddress getMasterCell(CellAddress addr) {
    final region = getRegion(addr);
    if (region == null) return addr;
    return CellAddress(region.startColumn, region.startRow);
  }

  /// Whether [addr] is the master (top-left) cell of its merge region.
  bool isMasterCell(CellAddress addr) {
    final region = getRegion(addr);
    if (region == null) return false;
    return addr.column == region.startColumn && addr.row == region.startRow;
  }

  /// Whether [addr] is a hidden cell (merged but not the master).
  bool isHiddenByMerge(CellAddress addr) {
    return isMerged(addr) && !isMasterCell(addr);
  }

  // =========================================================================
  // Mutations
  // =========================================================================

  /// Add a merge region.
  ///
  /// Throws [ArgumentError] if the region overlaps with an existing merge.
  void addRegion(CellRange region) {
    // Check for overlaps.
    for (final existing in _regions) {
      if (_overlaps(existing, region)) {
        throw ArgumentError(
          'Merge region ${region.label} overlaps with existing '
          'region ${existing.label}',
        );
      }
    }
    _regions.add(region);
  }

  /// Remove a merge region by matching its exact range.
  ///
  /// Returns true if the region was found and removed.
  bool removeRegion(CellRange region) {
    return _regions.remove(region);
  }

  /// Remove the merge region containing [addr].
  ///
  /// Returns the removed region, or null if [addr] was not merged.
  CellRange? removeRegionAt(CellAddress addr) {
    for (int i = 0; i < _regions.length; i++) {
      if (_regions[i].contains(addr)) {
        return _regions.removeAt(i);
      }
    }
    return null;
  }

  /// Remove all merge regions.
  void clear() => _regions.clear();

  // =========================================================================
  // Serialization
  // =========================================================================

  List<Map<String, dynamic>> toJson() =>
      _regions.map((r) => r.toJson()).toList();

  void loadFromJson(List<dynamic> json) {
    _regions.clear();
    for (final item in json) {
      _regions.add(CellRange.fromJson(item as Map<String, dynamic>));
    }
  }

  // =========================================================================
  // Internal
  // =========================================================================

  /// Check if two ranges overlap.
  static bool _overlaps(CellRange a, CellRange b) {
    return a.startColumn <= b.endColumn &&
        a.endColumn >= b.startColumn &&
        a.startRow <= b.endRow &&
        a.endRow >= b.startRow;
  }
}
