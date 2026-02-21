import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'decimal_value.dart';

import 'cell_address.dart';
import 'cell_node.dart';
import 'cell_value.dart';
import 'formula_ast.dart';
import 'formula_functions.dart';
import 'formula_parser.dart';
import 'spreadsheet_model.dart';

/// 📊 Cell change event emitted by the evaluator.
class CellChangeEvent {
  /// Address of the changed cell.
  final CellAddress address;

  /// Previous computed value.
  final CellValue oldValue;

  /// New computed value.
  final CellValue newValue;

  const CellChangeEvent({
    required this.address,
    required this.oldValue,
    required this.newValue,
  });

  @override
  String toString() => 'CellChangeEvent($address: $oldValue → $newValue)';
}

/// 📊 DAG-based reactive computation engine for spreadsheets.
///
/// Maintains a dependency graph between cells. When a cell changes,
/// only its transitive dependents are re-evaluated, in topological order.
///
/// ## Cycle Detection
///
/// Before evaluation, the engine runs DFS coloring (white/gray/black).
/// If a back-edge is detected, all cells in the cycle receive
/// `ErrorValue(CellError.circularRef)`.
///
/// ## Usage
///
/// ```dart
/// final model = SpreadsheetModel();
/// final evaluator = SpreadsheetEvaluator(model);
///
/// evaluator.setCellAndEvaluate(CellAddress(0, 0), NumberValue(10));
/// evaluator.setCellAndEvaluate(CellAddress(1, 0), FormulaValue('A1 * 2'));
///
/// print(evaluator.getComputedValue(CellAddress(1, 0))); // 20
/// ```
class SpreadsheetEvaluator {
  /// The underlying data model.
  final SpreadsheetModel model;

  /// Optional callback for resolving cross-sheet references (e.g. Sheet2!A1).
  /// Set by [SpreadsheetWorkbook] when this evaluator belongs to a workbook.
  CellValue Function(String sheetName, CellAddress address)? crossSheetResolver;

  // -------------------------------------------------------------------------
  // Dependency graph
  // -------------------------------------------------------------------------

  /// Forward dependencies: cell → set of cells that reference it.
  ///
  /// If A1's formula references B1, then `_dependents[B1]` contains A1.
  /// When B1 changes, A1 must be re-evaluated.
  final Map<CellAddress, Set<CellAddress>> _dependents = {};

  /// Reverse dependencies: cell → set of cells its formula references.
  ///
  /// If A1's formula references B1 and C1, then
  /// `_precedents[A1]` = {B1, C1}.
  final Map<CellAddress, Set<CellAddress>> _precedents = {};

  /// Cached AST for formula cells (avoids re-parsing).
  final Map<CellAddress, FormulaNode> _astCache = {};

  // -------------------------------------------------------------------------
  // Change stream
  // -------------------------------------------------------------------------

  final StreamController<CellChangeEvent> _changeController =
      StreamController<CellChangeEvent>.broadcast();

  /// Stream of cell change events.
  ///
  /// Emits one event per cell that was re-evaluated (including
  /// transitive dependents).
  Stream<CellChangeEvent> get onCellChanged => _changeController.stream;

  // -------------------------------------------------------------------------
  // Constructor
  // -------------------------------------------------------------------------

  SpreadsheetEvaluator(this.model);

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Set a cell value and trigger incremental re-evaluation.
  ///
  /// 1. Stores the value in the model.
  /// 2. Parses the formula (if applicable) and builds dependencies.
  /// 3. Checks for cycles.
  /// 4. Evaluates the cell and all transitive dependents in topo order.
  /// 5. Emits [CellChangeEvent]s for every changed cell.
  void setCellAndEvaluate(CellAddress addr, CellValue value) {
    // Get or create the CellNode.
    var cell = model.getCell(addr);
    if (cell == null) {
      cell = CellNode(value: value);
      model.setCell(addr, cell);
    } else {
      cell.value = value;
    }

    // Rebuild dependencies for this cell.
    _rebuildDependencies(addr, value);

    // Collect all cells that need re-evaluation.
    final toEvaluate = _topologicalSort(addr);

    // Evaluate in topo order.
    for (final target in toEvaluate) {
      _evaluateCell(target);
    }
  }

  /// Get the computed value for [addr].
  ///
  /// Returns [EmptyValue] if the cell doesn't exist.
  CellValue getComputedValue(CellAddress addr) {
    final cell = model.getCell(addr);
    if (cell == null) return const EmptyValue();
    return cell.displayValue;
  }

  /// Check whether [addr] is in a circular reference.
  bool hasCycle(CellAddress addr) {
    final visited = <CellAddress>{};
    final stack = <CellAddress>{};
    return _dfsCycleCheck(addr, visited, stack);
  }

  /// Re-evaluate all formula cells from scratch.
  ///
  /// Useful after deserialization to rebuild computed values.
  void evaluateAll() {
    // Collect all formula cells.
    final formulaCells = <CellAddress>[];
    for (final addr in model.occupiedAddresses) {
      final cell = model.getCell(addr);
      if (cell != null && cell.isFormula) {
        _rebuildDependencies(addr, cell.value);
        formulaCells.add(addr);
      }
    }

    // Full topological sort of all formula cells.
    final sorted = _fullTopologicalSort(formulaCells);
    for (final addr in sorted) {
      _evaluateCell(addr);
    }
  }

  /// Clear a cell and re-evaluate dependents.
  void clearCellAndEvaluate(CellAddress addr) {
    final dependents = _collectTransitiveDependents(addr);

    // Remove dependencies.
    _removeDependencies(addr);
    _astCache.remove(addr);
    model.clearCell(addr);

    // Re-evaluate former dependents.
    final sorted = _fullTopologicalSort(dependents.toList());
    for (final target in sorted) {
      _evaluateCell(target);
    }
  }

  /// Dispose the evaluator and close the change stream.
  void dispose() {
    _changeController.close();
    _dependents.clear();
    _precedents.clear();
    _astCache.clear();
  }

  // -------------------------------------------------------------------------
  // Dependency management
  // -------------------------------------------------------------------------

  void _rebuildDependencies(CellAddress addr, CellValue value) {
    // Remove old precedents.
    _removeDependencies(addr);
    _astCache.remove(addr);

    if (value is! FormulaValue) return;

    // Parse the formula.
    FormulaNode ast;
    try {
      ast = FormulaParser.parse(value.expression);
    } catch (_) {
      // Parse error — no dependencies to track.
      return;
    }
    _astCache[addr] = ast;

    // Extract cell references from the AST.
    final refs = _collectReferences(ast);
    _precedents[addr] = refs;
    for (final ref in refs) {
      _dependents.putIfAbsent(ref, () => {}).add(addr);
    }
  }

  void _removeDependencies(CellAddress addr) {
    final oldPrecedents = _precedents.remove(addr);
    if (oldPrecedents != null) {
      for (final ref in oldPrecedents) {
        _dependents[ref]?.remove(addr);
        if (_dependents[ref]?.isEmpty ?? false) {
          _dependents.remove(ref);
        }
      }
    }
  }

  /// Extract all cell addresses referenced in a formula AST.
  Set<CellAddress> _collectReferences(FormulaNode node) {
    final refs = <CellAddress>{};
    _collectRefsRecursive(node, refs);
    return refs;
  }

  void _collectRefsRecursive(FormulaNode node, Set<CellAddress> refs) {
    switch (node) {
      case CellRef(:final address):
        refs.add(address);
      case RangeRef(:final range):
        for (final addr in range.addresses) {
          refs.add(addr);
        }
      case BinaryOp(:final left, :final right):
        _collectRefsRecursive(left, refs);
        _collectRefsRecursive(right, refs);
      case UnaryOp(:final operand):
        _collectRefsRecursive(operand, refs);
      case FunctionCall(:final args):
        for (final arg in args) {
          _collectRefsRecursive(arg, refs);
        }
      case NumberLiteral():
      case StringLiteral():
      case BoolLiteral():
      case SheetCellRef():
      case SheetRangeRef():
        break; // Cross-sheet refs don't create local dependencies.
    }
  }

  // -------------------------------------------------------------------------
  // Topological sort
  // -------------------------------------------------------------------------

  /// Collect [addr] + all transitive dependents in topological order.
  List<CellAddress> _topologicalSort(CellAddress addr) {
    final allTargets = [addr, ..._collectTransitiveDependents(addr)];
    return _fullTopologicalSort(allTargets);
  }

  /// Full topological sort of a set of cells based on their dependencies.
  List<CellAddress> _fullTopologicalSort(List<CellAddress> cells) {
    if (cells.isEmpty) return cells;
    if (cells.length == 1) return cells;

    final cellSet = cells.toSet();
    final inDegree = <CellAddress, int>{};
    final adj = <CellAddress, List<CellAddress>>{};

    // Initialize.
    for (final c in cellSet) {
      inDegree[c] = 0;
      adj[c] = [];
    }

    // Build adjacency within the subset.
    for (final c in cellSet) {
      final prec = _precedents[c];
      if (prec != null) {
        for (final p in prec) {
          if (cellSet.contains(p)) {
            adj[p]!.add(c);
            inDegree[c] = (inDegree[c] ?? 0) + 1;
          }
        }
      }
    }

    // Kahn's algorithm.
    final queue = Queue<CellAddress>();
    for (final c in cellSet) {
      if (inDegree[c] == 0) queue.add(c);
    }

    final sorted = <CellAddress>[];
    while (queue.isNotEmpty) {
      final node = queue.removeFirst();
      sorted.add(node);
      for (final dep in adj[node]!) {
        inDegree[dep] = inDegree[dep]! - 1;
        if (inDegree[dep] == 0) queue.add(dep);
      }
    }

    // If sorted doesn't contain all cells, there's a cycle.
    if (sorted.length != cellSet.length) {
      // Add remaining cells (cycle members) at the end — they'll get error values.
      for (final c in cellSet) {
        if (!sorted.contains(c)) sorted.add(c);
      }
    }

    return sorted;
  }

  /// Collect all transitive dependents of [addr] (breadth-first).
  Set<CellAddress> _collectTransitiveDependents(CellAddress addr) {
    final result = <CellAddress>{};
    final queue = Queue<CellAddress>();
    queue.add(addr);

    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      final deps = _dependents[current];
      if (deps != null) {
        for (final dep in deps) {
          if (result.add(dep)) {
            queue.add(dep);
          }
        }
      }
    }
    return result;
  }

  // -------------------------------------------------------------------------
  // Cycle detection
  // -------------------------------------------------------------------------

  /// DFS-based cycle detection (white/gray/black coloring).
  bool _dfsCycleCheck(
    CellAddress addr,
    Set<CellAddress> visited,
    Set<CellAddress> stack,
  ) {
    if (stack.contains(addr)) return true; // back-edge = cycle
    if (visited.contains(addr)) return false;

    visited.add(addr);
    stack.add(addr);

    final prec = _precedents[addr];
    if (prec != null) {
      for (final ref in prec) {
        if (_dfsCycleCheck(ref, visited, stack)) return true;
      }
    }

    stack.remove(addr);
    return false;
  }

  // -------------------------------------------------------------------------
  // Cell evaluation
  // -------------------------------------------------------------------------

  void _evaluateCell(CellAddress addr) {
    final cell = model.getCell(addr);
    if (cell == null) return;

    final oldValue = cell.computedValue ?? const EmptyValue();
    CellValue newValue;

    if (cell.value is FormulaValue) {
      // Check for cycles first.
      if (hasCycle(addr)) {
        newValue = const ErrorValue(CellError.circularRef);
      } else {
        final ast = _astCache[addr];
        if (ast == null) {
          // Parse error (already handled in _rebuildDependencies).
          try {
            final parsed = FormulaParser.parse(
              (cell.value as FormulaValue).expression,
            );
            _astCache[addr] = parsed;
            newValue = _evalNode(parsed);
          } catch (e) {
            newValue = ErrorValue(CellError.parseError, message: e.toString());
          }
        } else {
          newValue = _evalNode(ast);
        }
      }
    } else {
      // Non-formula: computed value = raw value.
      newValue = cell.value;
    }

    cell.computedValue = newValue;

    // Emit change event if value actually changed.
    if (oldValue != newValue) {
      _changeController.add(
        CellChangeEvent(address: addr, oldValue: oldValue, newValue: newValue),
      );
    }
  }

  /// Evaluate a formula AST node recursively.
  CellValue _evalNode(FormulaNode node) {
    switch (node) {
      case NumberLiteral(:final value):
        return NumberValue(value);

      case StringLiteral(:final value):
        return TextValue(value);

      case BoolLiteral(:final value):
        return BoolValue(value);

      case CellRef(:final address):
        return getComputedValue(address);

      case RangeRef():
        // Ranges should only appear as function arguments.
        return const ErrorValue(
          CellError.valueError,
          message: 'Range outside of function context',
        );

      case UnaryOp(:final operand, :final op):
        return _evalUnary(op, _evalNode(operand));

      case BinaryOp(:final left, :final right, :final op):
        return _evalBinary(op, _evalNode(left), _evalNode(right));

      case FunctionCall(:final name, :final args):
        return _evalFunction(name, args);

      case SheetCellRef(:final sheetName, :final address):
        if (crossSheetResolver != null) {
          return crossSheetResolver!(sheetName, address);
        }
        return ErrorValue(
          CellError.invalidRef,
          message: 'No workbook context for $sheetName!${address.label}',
        );

      case SheetRangeRef(:final sheetName, :final range):
        // When a cross-sheet range is used as a standalone expression,
        // return an error. Cross-sheet ranges are expanded in _evalFunction.
        if (crossSheetResolver != null) {
          // Return the first cell as a fallback.
          return crossSheetResolver!(sheetName, range.start);
        }
        return ErrorValue(
          CellError.invalidRef,
          message: 'No workbook context for $sheetName!${range.label}',
        );
    }
  }

  CellValue _evalUnary(String op, CellValue operand) {
    if (operand is ErrorValue) return operand;

    switch (op) {
      case '-':
        final n = operand.asNumber;
        if (n == null) return const ErrorValue(CellError.valueError);
        return NumberValue(DecimalHelper.negate(n));
      case '%':
        final n = operand.asNumber;
        if (n == null) return const ErrorValue(CellError.valueError);
        return NumberValue(DecimalHelper.percent(n));
      default:
        return operand;
    }
  }

  CellValue _evalBinary(String op, CellValue left, CellValue right) {
    // Propagate errors.
    if (left is ErrorValue) return left;
    if (right is ErrorValue) return right;

    // String concatenation.
    if (op == '&') {
      return TextValue('${left.displayString}${right.displayString}');
    }

    // Comparison operators.
    switch (op) {
      case '=':
        return BoolValue(left == right);
      case '<>':
        return BoolValue(left != right);
    }

    // Numeric operations.
    final ln = left.asNumber;
    final rn = right.asNumber;

    // Numeric comparisons.
    if (op == '<' || op == '>' || op == '<=' || op == '>=') {
      if (ln == null || rn == null)
        return const ErrorValue(CellError.valueError);
      return switch (op) {
        '<' => BoolValue(ln < rn),
        '>' => BoolValue(ln > rn),
        '<=' => BoolValue(ln <= rn),
        '>=' => BoolValue(ln >= rn),
        _ => const ErrorValue(CellError.valueError),
      };
    }

    if (ln == null || rn == null) return const ErrorValue(CellError.valueError);

    return switch (op) {
      '+' => NumberValue(DecimalHelper.add(ln, rn)),
      '-' => NumberValue(DecimalHelper.subtract(ln, rn)),
      '*' => NumberValue(DecimalHelper.multiply(ln, rn)),
      '/' =>
        rn == 0
            ? const ErrorValue(CellError.divisionByZero)
            : NumberValue(DecimalHelper.divide(ln, rn)),
      '^' => NumberValue(DecimalHelper.power(ln, rn)),
      _ => const ErrorValue(CellError.valueError),
    };
  }

  CellValue _evalFunction(String name, List<FormulaNode> argNodes) {
    // Check for range-aware functions first (VLOOKUP, INDEX, etc.).
    final rawFn = FormulaFunctions.lookupRangeAware(name);
    if (rawFn != null) {
      // Resolve named range arguments to RangeRef nodes.
      final resolvedArgs =
          argNodes.map((node) {
            if (node is FunctionCall &&
                node.args.isEmpty &&
                model.hasNamedRange(node.name)) {
              return RangeRef(model.getNamedRange(node.name)!);
            }
            return node;
          }).toList();
      return rawFn(resolvedArgs, _resolveRange, _evalNode);
    }

    final fn = FormulaFunctions.lookup(name);
    if (fn == null) {
      // Check if the name is a named range used as a function argument.
      // This handles cases like SUM(Revenue) where Revenue is a named range.
      // But if 'name' itself is unknown and has args, it's still an error.
      return ErrorValue(
        CellError.nameError,
        message: 'Unknown function: $name',
      );
    }

    // Expand arguments: ranges become flat lists of values.
    // Named ranges in function arguments are also resolved.
    final expandedArgs = <CellValue>[];
    for (final argNode in argNodes) {
      if (argNode is RangeRef) {
        for (final addr in argNode.range.addresses) {
          expandedArgs.add(getComputedValue(addr));
        }
      } else if (argNode is SheetRangeRef && crossSheetResolver != null) {
        // Cross-sheet range: resolve each cell via cross-sheet resolver.
        for (final addr in argNode.range.addresses) {
          expandedArgs.add(crossSheetResolver!(argNode.sheetName, addr));
        }
      } else if (argNode is FunctionCall &&
          argNode.args.isEmpty &&
          model.hasNamedRange(argNode.name)) {
        // A named range used as a function argument (e.g. SUM(Revenue)).
        final range = model.getNamedRange(argNode.name)!;
        for (final addr in range.addresses) {
          expandedArgs.add(getComputedValue(addr));
        }
      } else {
        expandedArgs.add(_evalNode(argNode));
      }
    }

    return fn(expandedArgs);
  }

  /// Resolve a range into a 2D list of values [row][col].
  List<List<CellValue>> _resolveRange(CellRange range) {
    final rows = <List<CellValue>>[];
    for (int r = range.startRow; r <= range.endRow; r++) {
      final row = <CellValue>[];
      for (int c = range.startColumn; c <= range.endColumn; c++) {
        row.add(getComputedValue(CellAddress(c, r)));
      }
      rows.add(row);
    }
    return rows;
  }
}
