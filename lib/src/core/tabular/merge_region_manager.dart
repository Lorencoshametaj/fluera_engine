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

  /// Inverse index: maps every cell in a merge region to its region.
  /// Rebuilt on every mutation for O(1) lookups.
  Map<CellAddress, CellRange> _cellIndex = {};

  /// All current merge regions.
  List<CellRange> get regions => List.unmodifiable(_regions);

  /// Number of merge regions.
  int get regionCount => _regions.length;

  // =========================================================================
  // Queries — all O(1) via _cellIndex
  // =========================================================================

  /// Whether [addr] falls within any merge region.
  bool isMerged(CellAddress addr) => _cellIndex.containsKey(addr);

  /// Get the merge region containing [addr], or null if not merged.
  CellRange? getRegion(CellAddress addr) => _cellIndex[addr];

  /// Get the top-left "master" cell of the merge region containing [addr].
  ///
  /// Returns [addr] itself if it's not merged.
  CellAddress getMasterCell(CellAddress addr) {
    final region = _cellIndex[addr];
    if (region == null) return addr;
    return CellAddress(region.startColumn, region.startRow);
  }

  /// Whether [addr] is the master (top-left) cell of its merge region.
  bool isMasterCell(CellAddress addr) {
    final region = _cellIndex[addr];
    if (region == null) return false;
    return addr.column == region.startColumn && addr.row == region.startRow;
  }

  /// Whether [addr] is a hidden cell (merged but not the master).
  bool isHiddenByMerge(CellAddress addr) {
    final region = _cellIndex[addr];
    if (region == null) return false;
    return addr.column != region.startColumn || addr.row != region.startRow;
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
    _indexRegion(region);
  }

  /// Remove a merge region by matching its exact range.
  ///
  /// Returns true if the region was found and removed.
  bool removeRegion(CellRange region) {
    final removed = _regions.remove(region);
    if (removed) _unindexRegion(region);
    return removed;
  }

  /// Remove the merge region containing [addr].
  ///
  /// Returns the removed region, or null if [addr] was not merged.
  CellRange? removeRegionAt(CellAddress addr) {
    final region = _cellIndex[addr];
    if (region == null) return null;
    _regions.remove(region);
    _unindexRegion(region);
    return region;
  }

  /// Remove all merge regions.
  void clear() {
    _regions.clear();
    _cellIndex.clear();
  }

  // =========================================================================
  // Serialization
  // =========================================================================

  List<Map<String, dynamic>> toJson() =>
      _regions.map((r) => r.toJson()).toList();

  void loadFromJson(List<dynamic> json) {
    _regions.clear();
    _cellIndex.clear();
    for (final item in json) {
      final region = CellRange.fromJson(item as Map<String, dynamic>);
      _regions.add(region);
      _indexRegion(region);
    }
  }

  // =========================================================================
  // Internal
  // =========================================================================

  /// Add all cells of [region] to the inverse index.
  void _indexRegion(CellRange region) {
    for (final addr in region.addresses) {
      _cellIndex[addr] = region;
    }
  }

  /// Remove all cells of [region] from the inverse index.
  void _unindexRegion(CellRange region) {
    for (final addr in region.addresses) {
      _cellIndex.remove(addr);
    }
  }

  /// Check if two ranges overlap.
  static bool _overlaps(CellRange a, CellRange b) {
    return a.startColumn <= b.endColumn &&
        a.endColumn >= b.startColumn &&
        a.startRow <= b.endRow &&
        a.endRow >= b.startRow;
  }
}
