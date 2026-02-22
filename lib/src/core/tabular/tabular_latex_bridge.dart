import 'dart:async';

import 'cell_address.dart';
import 'cell_number_formatter.dart';
import 'cell_value.dart';
import 'spreadsheet_evaluator.dart';
import '../scene_graph/invalidation_graph.dart';
import '../nodes/latex_node.dart';

/// 📊 Reactive bridge connecting TabularNode cells to LatexNode rendering.
///
/// Parses placeholder syntax in LaTeX source and reactively substitutes
/// values from a [SpreadsheetEvaluator]. Supports:
///
/// - **Cell references**: `{A1}` → value of cell A1
/// - **Formatted cells**: `{A1:#,##0.00}` → formatted number
/// - **Range expansion**: `{A1:A5}` → comma-separated values
/// - **Aggregates**: `{SUM(A1:A5)}`, `{AVG(B1:B10)}`, `{MIN(C1:C3)}`,
///   `{MAX(D1:D5)}`, `{COUNT(A:A)}`
/// - **Formatted aggregates**: `{SUM(A1:A5):#,##0.00}`
///
/// ## Provenance
///
/// The bridge tracks bidirectional dependencies between LaTeX nodes and
/// cells, enabling click-through navigation:
///
/// ```dart
/// bridge.getCellsReferencedBy(latexNodeId); // → {A1, B2, C3}
/// bridge.getLatexNodesReferencingCell(CellAddress(0, 0)); // → {'node-1'}
/// ```
///
/// ## Usage
///
/// ```dart
/// final bridge = TabularLatexBridge(evaluator, invalidationGraph);
/// bridge.registerLatexNode(latexNode, 'tabular-1');
/// // When a referenced cell changes → latexNode re-renders automatically
/// bridge.dispose();
/// ```
class TabularLatexBridge {
  final SpreadsheetEvaluator _evaluator;
  final InvalidationGraph? _invalidationGraph;

  /// Active registrations: latexNodeId → _Registration.
  final Map<String, _Registration> _registrations = {};

  TabularLatexBridge(this._evaluator, [this._invalidationGraph]);

  // =========================================================================
  // Registration
  // =========================================================================

  /// Register a [LatexNode] whose source may contain cell reference
  /// placeholders like `{A1}`, `{A1:#,##0}`, `{A1:A5}`, `{SUM(A1:A5)}`.
  ///
  /// The [tabularNodeId] is used as a namespace prefix for
  /// invalidation graph tracking.
  void registerLatexNode(LatexNode node, String tabularNodeId) {
    // Unregister any previous registration.
    unregisterLatexNode(node.id.toString());

    final template = node.latexSource;
    final placeholders = _parsePlaceholders(template);

    if (placeholders.isEmpty) return; // No placeholders to track.

    // Collect all cell addresses that need tracking.
    final cellAddresses = <CellAddress>{};
    for (final ph in placeholders) {
      cellAddresses.addAll(ph.referencedCells);
    }

    // Subscribe to changes.
    final subscription = _evaluator.onCellChanged
        .where((event) => cellAddresses.contains(event.address))
        .listen((event) {
          _onCellChanged(node, template, placeholders);
        });

    _registrations[node.id.toString()] = _Registration(
      node: node,
      template: template,
      placeholders: placeholders,
      addresses: cellAddresses,
      subscription: subscription,
      tabularNodeId: tabularNodeId,
    );

    // Perform initial substitution.
    _substituteAll(node, template, placeholders);
  }

  /// Unregister a previously registered LatexNode.
  void unregisterLatexNode(String latexNodeId) {
    final reg = _registrations.remove(latexNodeId);
    reg?.subscription.cancel();
  }

  /// Dispose all registrations and subscriptions.
  void dispose() {
    for (final reg in _registrations.values) {
      reg.subscription.cancel();
    }
    _registrations.clear();
  }

  // =========================================================================
  // Queries
  // =========================================================================

  /// Get all registered LaTeX node IDs.
  Set<String> get registeredNodeIds => _registrations.keys.toSet();

  /// Check if a LatexNode is registered.
  bool isRegistered(String latexNodeId) =>
      _registrations.containsKey(latexNodeId);

  // =========================================================================
  // Provenance — bidirectional dependency tracking
  // =========================================================================

  /// Get all cell addresses referenced by a registered LaTeX node.
  ///
  /// Returns an empty set if the node is not registered.
  Set<CellAddress> getCellsReferencedBy(String latexNodeId) {
    final reg = _registrations[latexNodeId];
    if (reg == null) return const {};
    return Set.unmodifiable(reg.addresses);
  }

  /// Get all LaTeX node IDs that reference the given [addr].
  ///
  /// Useful for click-through: tap a cell → see which equations use it.
  Set<String> getLatexNodesReferencingCell(CellAddress addr) {
    final result = <String>{};
    for (final entry in _registrations.entries) {
      if (entry.value.addresses.contains(addr)) {
        result.add(entry.key);
      }
    }
    return result;
  }

  /// Get all provenance entries as a map: latexNodeId → referenced cells.
  Map<String, Set<CellAddress>> get provenanceMap {
    return {
      for (final entry in _registrations.entries)
        entry.key: Set.unmodifiable(entry.value.addresses),
    };
  }

  // =========================================================================
  // Placeholder parsing
  // =========================================================================

  /// Parse all placeholders from a template string.
  ///
  /// Supported patterns:
  /// - `{A1}` — single cell
  /// - `{A1:#,##0.00}` — single cell with format
  /// - `{A1:A5}` — range (ambiguity resolved: if second part is a valid
  ///   cell label, it's a range; otherwise it's a format)
  /// - `{SUM(A1:A5)}` — aggregate function
  /// - `{SUM(A1:A5):#,##0}` — aggregate function with format
  static List<_Placeholder> _parsePlaceholders(String template) {
    // Master regex: matches {CONTENT} where CONTENT can be:
    //   FUNC(RANGE)            → aggregate
    //   FUNC(RANGE):FORMAT     → aggregate with format
    //   CELL:CELL              → range (if second part is valid cell)
    //   CELL:FORMAT            → formatted cell (if second part is format)
    //   CELL                   → simple cell
    final pattern = RegExp(r'\{([^}]+)\}');
    final placeholders = <_Placeholder>[];

    for (final match in pattern.allMatches(template)) {
      final raw = match.group(1)!;
      final fullMatch = match.group(0)!;
      final ph = _parseSinglePlaceholder(raw, fullMatch);
      if (ph != null) placeholders.add(ph);
    }

    return placeholders;
  }

  static final RegExp _cellLabel = RegExp(r'^[A-Z]+[0-9]+$');

  static final RegExp _aggPattern = RegExp(
    r'^(SUM|AVG|AVERAGE|MIN|MAX|COUNT)\(([A-Z]+[0-9]+):([A-Z]+[0-9]+)\)(?::(.+))?$',
    caseSensitive: false,
  );

  /// Parse a single placeholder content (without the braces).
  static _Placeholder? _parseSinglePlaceholder(String raw, String fullMatch) {
    // 1. Try aggregate: SUM(A1:A5) or SUM(A1:A5):#,##0
    final aggMatch = _aggPattern.firstMatch(raw);
    if (aggMatch != null) {
      final func = aggMatch.group(1)!.toUpperCase();
      final start = CellAddress.fromLabel(aggMatch.group(2)!);
      final end = CellAddress.fromLabel(aggMatch.group(3)!);
      final format = aggMatch.group(4);
      final range = CellRange(
        CellAddress(start.column, start.row),
        CellAddress(end.column, end.row),
      );
      return _AggregatePlaceholder(
        raw: fullMatch,
        function: func,
        range: range,
        format: format,
      );
    }

    // 2. Try CELL:SOMETHING — could be range or formatted cell.
    if (raw.contains(':')) {
      final colonIdx = raw.indexOf(':');
      final left = raw.substring(0, colonIdx);
      final right = raw.substring(colonIdx + 1);

      if (_cellLabel.hasMatch(left) && _cellLabel.hasMatch(right)) {
        // Both parts are valid cell labels → range.
        final start = CellAddress.fromLabel(left);
        final end = CellAddress.fromLabel(right);
        return _RangePlaceholder(
          raw: fullMatch,
          range: CellRange(
            CellAddress(start.column, start.row),
            CellAddress(end.column, end.row),
          ),
        );
      }

      if (_cellLabel.hasMatch(left)) {
        // Left is a cell, right is a format string.
        return _FormattedCellPlaceholder(
          raw: fullMatch,
          address: CellAddress.fromLabel(left),
          format: right,
        );
      }
    }

    // 3. Try simple cell: A1
    if (_cellLabel.hasMatch(raw)) {
      return _CellPlaceholder(
        raw: fullMatch,
        address: CellAddress.fromLabel(raw),
      );
    }

    // Not a recognized placeholder — skip silently.
    return null;
  }

  // =========================================================================
  // Substitution
  // =========================================================================

  void _onCellChanged(
    LatexNode node,
    String template,
    List<_Placeholder> placeholders,
  ) {
    _substituteAll(node, template, placeholders);

    // Mark dirty in the invalidation graph.
    _invalidationGraph?.markDirty(node.id.toString(), DirtyFlag.paint);
  }

  void _substituteAll(
    LatexNode node,
    String template,
    List<_Placeholder> placeholders,
  ) {
    var result = template;

    for (final ph in placeholders) {
      final value = _resolvePlaceholder(ph);
      result = result.replaceAll(ph.raw, value);
    }

    // Update the LaTeX source (this clears the cached layout automatically).
    node.latexSource = result;
  }

  String _resolvePlaceholder(_Placeholder ph) {
    switch (ph) {
      case _CellPlaceholder(:final address):
        return _evaluator.getComputedValue(address).displayString;

      case _FormattedCellPlaceholder(:final address, :final format):
        final val = _evaluator.getComputedValue(address);
        if (val is NumberValue) {
          return CellNumberFormatter.format(val.value, format);
        }
        return val.displayString;

      case _RangePlaceholder(:final range):
        return _expandRange(range);

      case _AggregatePlaceholder(:final function, :final range, :final format):
        return _computeAggregate(function, range, format);
    }
  }

  String _expandRange(CellRange range) {
    final values = <String>[];
    for (final addr in range.addresses) {
      final val = _evaluator.getComputedValue(addr);
      if (val is! EmptyValue) {
        values.add(val.displayString);
      }
    }
    return values.join(', ');
  }

  String _computeAggregate(String func, CellRange range, String? format) {
    final values = <num>[];
    int totalCount = 0;

    for (final addr in range.addresses) {
      final val = _evaluator.getComputedValue(addr);
      if (val is NumberValue) {
        values.add(val.value);
      }
      if (val is! EmptyValue) {
        totalCount++;
      }
    }

    if (values.isEmpty && func != 'COUNT') return '#N/A';

    final num result;
    switch (func) {
      case 'SUM':
        result = values.fold<num>(0, (a, b) => a + b);
      case 'AVG' || 'AVERAGE':
        result = values.fold<num>(0, (a, b) => a + b) / values.length;
      case 'MIN':
        result = values.reduce((a, b) => a < b ? a : b);
      case 'MAX':
        result = values.reduce((a, b) => a > b ? a : b);
      case 'COUNT':
        result = totalCount;
      default:
        return '#NAME?';
    }

    if (format != null) {
      return CellNumberFormatter.format(result, format);
    }
    return result == result.toInt()
        ? result.toInt().toString()
        : result.toString();
  }
}

// =============================================================================
// Placeholder types
// =============================================================================

/// Base class for parsed placeholders.
sealed class _Placeholder {
  /// The full raw match including braces, e.g. `{A1}`.
  final String raw;

  const _Placeholder({required this.raw});

  /// All individual cell addresses this placeholder references.
  Set<CellAddress> get referencedCells;
}

/// Simple cell reference: `{A1}`.
class _CellPlaceholder extends _Placeholder {
  final CellAddress address;

  const _CellPlaceholder({required super.raw, required this.address});

  @override
  Set<CellAddress> get referencedCells => {address};
}

/// Formatted cell reference: `{A1:#,##0.00}`.
class _FormattedCellPlaceholder extends _Placeholder {
  final CellAddress address;
  final String format;

  const _FormattedCellPlaceholder({
    required super.raw,
    required this.address,
    required this.format,
  });

  @override
  Set<CellAddress> get referencedCells => {address};
}

/// Range expansion: `{A1:A5}` → comma-separated values.
class _RangePlaceholder extends _Placeholder {
  final CellRange range;

  const _RangePlaceholder({required super.raw, required this.range});

  @override
  Set<CellAddress> get referencedCells => range.addresses.toSet();
}

/// Aggregate function: `{SUM(A1:A5)}` or `{SUM(A1:A5):#,##0}`.
class _AggregatePlaceholder extends _Placeholder {
  final String function;
  final CellRange range;
  final String? format;

  const _AggregatePlaceholder({
    required super.raw,
    required this.function,
    required this.range,
    this.format,
  });

  @override
  Set<CellAddress> get referencedCells => range.addresses.toSet();
}

// =============================================================================
// Registration data
// =============================================================================

/// Internal registration data.
class _Registration {
  final LatexNode node;
  final String template;
  final List<_Placeholder> placeholders;
  final Set<CellAddress> addresses;
  final StreamSubscription<CellChangeEvent> subscription;
  final String tabularNodeId;

  _Registration({
    required this.node,
    required this.template,
    required this.placeholders,
    required this.addresses,
    required this.subscription,
    required this.tabularNodeId,
  });
}
