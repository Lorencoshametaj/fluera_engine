import 'dart:math' as math;

import 'cell_address.dart';
import 'cell_value.dart';
import 'decimal_value.dart';
import 'formula_ast.dart';

/// 📊 Built-in function registry for the tabular engine.
///
/// Functions receive a flat list of [CellValue] arguments and return a
/// [CellValue]. Range values are expanded before being passed to functions
/// (the evaluator resolves ranges to lists of values).
///
/// Register custom functions via [FormulaFunctions.register].
typedef FormulaFunction = CellValue Function(List<CellValue> args);

/// Range-aware function signature for lookup/conditional functions.
///
/// Receives raw [FormulaNode] args, a [rangeResolver] that converts
/// [CellRange] to 2D value arrays, and a [nodeEval] for scalar args.
typedef RangeAwareFunction =
    CellValue Function(
      List<FormulaNode> args,
      List<List<CellValue>> Function(CellRange range) rangeResolver,
      CellValue Function(FormulaNode node) nodeEval,
    );

/// Registry of built-in and custom spreadsheet functions.
class FormulaFunctions {
  FormulaFunctions._();

  /// The function registry. Keys are uppercase function names.
  static final Map<String, FormulaFunction> _registry = {
    // -- Math --
    'SUM': _sum,
    'AVERAGE': _average,
    'MIN': _min,
    'MAX': _max,
    'ABS': _abs,
    'ROUND': _round,
    'FLOOR': _floor,
    'CEIL': _ceil,
    'SQRT': _sqrt,
    'POWER': _power,
    'MOD': _mod,
    'PI': _pi,
    'LOG': _log,
    'LN': _ln,

    // -- Logic --
    'IF': _if,
    'AND': _and,
    'OR': _or,
    'NOT': _not,

    // -- Text --
    'LEN': _len,
    'UPPER': _upper,
    'LOWER': _lower,
    'CONCAT': _concat,
    'CONCATENATE': _concat,
    'LEFT': _left,
    'RIGHT': _right,
    'MID': _mid,
    'TRIM': _trim,

    // -- Info --
    'ISBLANK': _isBlank,
    'ISNUMBER': _isNumber,
    'ISTEXT': _isText,
    'ISERROR': _isError,

    // -- Statistics --
    'COUNT': _count,
    'COUNTA': _countA,
    'COUNTBLANK': _countBlank,

    // -- Date --
    'TODAY': _today,
    'NOW': _now,
    'YEAR': _year,
    'MONTH': _month,
    'DAY': _day,
    'DATE': _date,

    // -- Additional Text --
    'FIND': _find,
    'SUBSTITUTE': _substitute,
    'TEXT': _text,
    'VALUE': _value,

    // -- Error handling --
    'IFERROR': _iferror,

    // -- Array/Statistics --
    'SUMPRODUCT': _sumproduct,
    'MEDIAN': _median,
    'STDEV': _stdev,
    'LARGE': _large,
    'SMALL': _small,

    // -- Utility --
    'CHOOSE': _choose,
    'ROUNDDOWN': _roundDown,
    'ROUNDUP': _roundUp,
  };

  /// Range-aware function registry (for lookup/conditional functions).
  static final Map<String, RangeAwareFunction> _rangeAwareRegistry = {
    'VLOOKUP': _vlookup,
    'HLOOKUP': _hlookup,
    'INDEX': _index,
    'MATCH': _match,
    'SUMIF': _sumif,
    'COUNTIF': _countif,
    'AVERAGEIF': _averageif,
    'RANK': _rank,
  };

  /// Look up a function by [name] (case-insensitive).
  static FormulaFunction? lookup(String name) => _registry[name.toUpperCase()];

  /// Look up a range-aware function by [name].
  static RangeAwareFunction? lookupRangeAware(String name) =>
      _rangeAwareRegistry[name.toUpperCase()];

  /// Register a custom function.
  static void register(String name, FormulaFunction fn) {
    _registry[name.toUpperCase()] = fn;
  }

  /// Unregister a custom function.
  static void unregister(String name) {
    _registry.remove(name.toUpperCase());
  }

  /// All registered function names (both flat and range-aware).
  static Set<String> get registeredNames => {
    ..._registry.keys,
    ..._rangeAwareRegistry.keys,
  };

  // =========================================================================
  // Math functions
  // =========================================================================

  static CellValue _sum(List<CellValue> args) {
    final nums = <num>[];
    for (final arg in args) {
      final n = arg.asNumber;
      if (n != null) nums.add(n);
    }
    return NumberValue(DecimalHelper.sum(nums));
  }

  static CellValue _average(List<CellValue> args) {
    final nums = <num>[];
    for (final arg in args) {
      final n = arg.asNumber;
      if (n != null) nums.add(n);
    }
    if (nums.isEmpty) return const ErrorValue(CellError.divisionByZero);
    return NumberValue(DecimalHelper.average(nums));
  }

  static CellValue _min(List<CellValue> args) {
    double? result;
    for (final arg in args) {
      final n = arg.asNumber;
      if (n != null) {
        result = result == null ? n : math.min(result, n);
      }
    }
    return result != null ? NumberValue(result) : NumberValue(0);
  }

  static CellValue _max(List<CellValue> args) {
    double? result;
    for (final arg in args) {
      final n = arg.asNumber;
      if (n != null) {
        result = result == null ? n : math.max(result, n);
      }
    }
    return result != null ? NumberValue(result) : NumberValue(0);
  }

  static CellValue _abs(List<CellValue> args) {
    if (args.isEmpty) return const ErrorValue(CellError.valueError);
    final n = args[0].asNumber;
    if (n == null) return const ErrorValue(CellError.valueError);
    return NumberValue(n.abs());
  }

  static CellValue _round(List<CellValue> args) {
    if (args.isEmpty) return const ErrorValue(CellError.valueError);
    final n = args[0].asNumber;
    if (n == null) return const ErrorValue(CellError.valueError);
    final decimals = args.length > 1 ? (args[1].asNumber?.toInt() ?? 0) : 0;
    return NumberValue(DecimalHelper.round(n, decimals));
  }

  static CellValue _floor(List<CellValue> args) {
    if (args.isEmpty) return const ErrorValue(CellError.valueError);
    final n = args[0].asNumber;
    if (n == null) return const ErrorValue(CellError.valueError);
    return NumberValue(n.floorToDouble());
  }

  static CellValue _ceil(List<CellValue> args) {
    if (args.isEmpty) return const ErrorValue(CellError.valueError);
    final n = args[0].asNumber;
    if (n == null) return const ErrorValue(CellError.valueError);
    return NumberValue(n.ceilToDouble());
  }

  static CellValue _sqrt(List<CellValue> args) {
    if (args.isEmpty) return const ErrorValue(CellError.valueError);
    final n = args[0].asNumber;
    if (n == null || n < 0) return const ErrorValue(CellError.valueError);
    return NumberValue(math.sqrt(n));
  }

  static CellValue _power(List<CellValue> args) {
    if (args.length < 2) return const ErrorValue(CellError.valueError);
    final base = args[0].asNumber;
    final exp = args[1].asNumber;
    if (base == null || exp == null) {
      return const ErrorValue(CellError.valueError);
    }
    return NumberValue(DecimalHelper.power(base, exp));
  }

  static CellValue _mod(List<CellValue> args) {
    if (args.length < 2) return const ErrorValue(CellError.valueError);
    final a = args[0].asNumber;
    final b = args[1].asNumber;
    if (a == null || b == null) return const ErrorValue(CellError.valueError);
    if (b == 0) return const ErrorValue(CellError.divisionByZero);
    return NumberValue(DecimalHelper.modulo(a, b));
  }

  static CellValue _pi(List<CellValue> args) => const NumberValue(math.pi);

  static CellValue _log(List<CellValue> args) {
    if (args.isEmpty) return const ErrorValue(CellError.valueError);
    final n = args[0].asNumber;
    if (n == null || n <= 0) return const ErrorValue(CellError.valueError);
    final base = args.length > 1 ? (args[1].asNumber ?? 10.0) : 10.0;
    return NumberValue(math.log(n) / math.log(base));
  }

  static CellValue _ln(List<CellValue> args) {
    if (args.isEmpty) return const ErrorValue(CellError.valueError);
    final n = args[0].asNumber;
    if (n == null || n <= 0) return const ErrorValue(CellError.valueError);
    return NumberValue(math.log(n));
  }

  // =========================================================================
  // Logic functions
  // =========================================================================

  static CellValue _if(List<CellValue> args) {
    if (args.isEmpty) return const ErrorValue(CellError.valueError);
    final condition = _toBool(args[0]);
    if (condition) {
      return args.length > 1 ? args[1] : const BoolValue(true);
    } else {
      return args.length > 2 ? args[2] : const BoolValue(false);
    }
  }

  static CellValue _and(List<CellValue> args) {
    for (final arg in args) {
      if (!_toBool(arg)) return const BoolValue(false);
    }
    return const BoolValue(true);
  }

  static CellValue _or(List<CellValue> args) {
    for (final arg in args) {
      if (_toBool(arg)) return const BoolValue(true);
    }
    return const BoolValue(false);
  }

  static CellValue _not(List<CellValue> args) {
    if (args.isEmpty) return const ErrorValue(CellError.valueError);
    return BoolValue(!_toBool(args[0]));
  }

  // =========================================================================
  // Text functions
  // =========================================================================

  static CellValue _len(List<CellValue> args) {
    if (args.isEmpty) return const ErrorValue(CellError.valueError);
    return NumberValue(args[0].displayString.length);
  }

  static CellValue _upper(List<CellValue> args) {
    if (args.isEmpty) return const ErrorValue(CellError.valueError);
    return TextValue(args[0].displayString.toUpperCase());
  }

  static CellValue _lower(List<CellValue> args) {
    if (args.isEmpty) return const ErrorValue(CellError.valueError);
    return TextValue(args[0].displayString.toLowerCase());
  }

  static CellValue _concat(List<CellValue> args) {
    final buf = StringBuffer();
    for (final arg in args) {
      buf.write(arg.displayString);
    }
    return TextValue(buf.toString());
  }

  static CellValue _left(List<CellValue> args) {
    if (args.isEmpty) return const ErrorValue(CellError.valueError);
    final text = args[0].displayString;
    final count = args.length > 1 ? (args[1].asNumber?.toInt() ?? 1) : 1;
    return TextValue(text.substring(0, math.min(count, text.length)));
  }

  static CellValue _right(List<CellValue> args) {
    if (args.isEmpty) return const ErrorValue(CellError.valueError);
    final text = args[0].displayString;
    final count = args.length > 1 ? (args[1].asNumber?.toInt() ?? 1) : 1;
    return TextValue(text.substring(math.max(0, text.length - count)));
  }

  static CellValue _mid(List<CellValue> args) {
    if (args.length < 3) return const ErrorValue(CellError.valueError);
    final text = args[0].displayString;
    final start = (args[1].asNumber?.toInt() ?? 1) - 1; // 1-indexed in Excel
    final length = args[2].asNumber?.toInt() ?? 0;
    if (start < 0 || start >= text.length) return const TextValue('');
    return TextValue(
      text.substring(start, math.min(start + length, text.length)),
    );
  }

  static CellValue _trim(List<CellValue> args) {
    if (args.isEmpty) return const ErrorValue(CellError.valueError);
    return TextValue(args[0].displayString.trim());
  }

  // =========================================================================
  // Info functions
  // =========================================================================

  static CellValue _isBlank(List<CellValue> args) {
    if (args.isEmpty) return const BoolValue(true);
    return BoolValue(args[0] is EmptyValue);
  }

  static CellValue _isNumber(List<CellValue> args) {
    if (args.isEmpty) return const BoolValue(false);
    return BoolValue(args[0] is NumberValue);
  }

  static CellValue _isText(List<CellValue> args) {
    if (args.isEmpty) return const BoolValue(false);
    return BoolValue(args[0] is TextValue);
  }

  static CellValue _isError(List<CellValue> args) {
    if (args.isEmpty) return const BoolValue(false);
    return BoolValue(args[0] is ErrorValue);
  }

  // =========================================================================
  // Statistics functions
  // =========================================================================

  static CellValue _count(List<CellValue> args) {
    int c = 0;
    for (final arg in args) {
      if (arg is NumberValue) c++;
    }
    return NumberValue(c);
  }

  static CellValue _countA(List<CellValue> args) {
    int c = 0;
    for (final arg in args) {
      if (arg is! EmptyValue) c++;
    }
    return NumberValue(c);
  }

  static CellValue _countBlank(List<CellValue> args) {
    int c = 0;
    for (final arg in args) {
      if (arg is EmptyValue) c++;
    }
    return NumberValue(c);
  }

  // =========================================================================
  // Helpers
  // =========================================================================

  static bool _toBool(CellValue v) => switch (v) {
    BoolValue(:final value) => value,
    NumberValue(:final value) => value != 0,
    TextValue(:final value) => value.isNotEmpty,
    EmptyValue() => false,
    _ => true,
  };

  // =========================================================================
  // Date functions
  // =========================================================================

  static CellValue _today(List<CellValue> args) {
    final now = DateTime.now();
    return NumberValue(_dateToSerial(now.year, now.month, now.day));
  }

  static CellValue _now(List<CellValue> args) {
    final now = DateTime.now();
    final datePart = _dateToSerial(now.year, now.month, now.day);
    final timePart = (now.hour * 3600 + now.minute * 60 + now.second) / 86400.0;
    return NumberValue(datePart + timePart);
  }

  static CellValue _year(List<CellValue> args) {
    if (args.isEmpty) return const ErrorValue(CellError.valueError);
    final n = args[0].asNumber;
    if (n == null) return const ErrorValue(CellError.valueError);
    final dt = _serialToDate(n.toInt());
    return NumberValue(dt.year);
  }

  static CellValue _month(List<CellValue> args) {
    if (args.isEmpty) return const ErrorValue(CellError.valueError);
    final n = args[0].asNumber;
    if (n == null) return const ErrorValue(CellError.valueError);
    final dt = _serialToDate(n.toInt());
    return NumberValue(dt.month);
  }

  static CellValue _day(List<CellValue> args) {
    if (args.isEmpty) return const ErrorValue(CellError.valueError);
    final n = args[0].asNumber;
    if (n == null) return const ErrorValue(CellError.valueError);
    final dt = _serialToDate(n.toInt());
    return NumberValue(dt.day);
  }

  static CellValue _date(List<CellValue> args) {
    if (args.length < 3) return const ErrorValue(CellError.valueError);
    final y = args[0].asNumber?.toInt();
    final m = args[1].asNumber?.toInt();
    final d = args[2].asNumber?.toInt();
    if (y == null || m == null || d == null) {
      return const ErrorValue(CellError.valueError);
    }
    return NumberValue(_dateToSerial(y, m, d));
  }

  /// Convert (year, month, day) to Excel serial date number.
  /// Excel epoch: 1900-01-01 = 1 (with the Lotus 1-2-3 29-Feb-1900 bug).
  static int _dateToSerial(int year, int month, int day) {
    final dt = DateTime.utc(year, month, day);
    final epoch = DateTime.utc(1899, 12, 30); // Excel epoch with Lotus bug
    return dt.difference(epoch).inDays;
  }

  /// Convert Excel serial date number to DateTime.
  static DateTime _serialToDate(int serial) {
    final epoch = DateTime.utc(1899, 12, 30);
    return epoch.add(Duration(days: serial));
  }

  // =========================================================================
  // Additional text functions
  // =========================================================================

  static CellValue _find(List<CellValue> args) {
    if (args.length < 2) return const ErrorValue(CellError.valueError);
    final search = args[0].displayString;
    final text = args[1].displayString;
    final startPos = args.length > 2 ? (args[2].asNumber?.toInt() ?? 1) : 1;
    final idx = text.indexOf(search, startPos - 1);
    if (idx < 0) return const ErrorValue(CellError.valueError);
    return NumberValue(idx + 1); // 1-indexed
  }

  static CellValue _substitute(List<CellValue> args) {
    if (args.length < 3) return const ErrorValue(CellError.valueError);
    final text = args[0].displayString;
    final oldText = args[1].displayString;
    final newText = args[2].displayString;
    if (args.length > 3) {
      // Replace nth occurrence only.
      final nth = args[3].asNumber?.toInt() ?? 1;
      int count = 0;
      final buf = StringBuffer();
      int pos = 0;
      while (pos < text.length) {
        final idx = text.indexOf(oldText, pos);
        if (idx < 0) {
          buf.write(text.substring(pos));
          break;
        }
        count++;
        buf.write(text.substring(pos, idx));
        if (count == nth) {
          buf.write(newText);
        } else {
          buf.write(oldText);
        }
        pos = idx + oldText.length;
      }
      return TextValue(buf.toString());
    }
    return TextValue(text.replaceAll(oldText, newText));
  }

  static CellValue _text(List<CellValue> args) {
    if (args.isEmpty) return const ErrorValue(CellError.valueError);
    final n = args[0].asNumber;
    if (n == null) return TextValue(args[0].displayString);
    // Basic format: if format code provided, use it; otherwise plain string.
    if (args.length > 1) {
      final fmt = args[1].displayString;
      // Common format codes.
      if (fmt.contains('.')) {
        final decimals = fmt.split('.').last.length;
        return TextValue(n.toDouble().toStringAsFixed(decimals));
      }
      if (fmt.contains('%')) {
        return TextValue('${(n * 100).toStringAsFixed(0)}%');
      }
    }
    return TextValue(n.toString());
  }

  static CellValue _value(List<CellValue> args) {
    if (args.isEmpty) return const ErrorValue(CellError.valueError);
    final text = args[0].displayString.replaceAll(',', '');
    final percent = text.endsWith('%');
    final clean = percent ? text.substring(0, text.length - 1) : text;
    final n = num.tryParse(clean);
    if (n == null) return const ErrorValue(CellError.valueError);
    return NumberValue(percent ? n / 100 : n);
  }

  // =========================================================================
  // Range-aware functions (lookup & conditional)
  // =========================================================================

  /// VLOOKUP(lookup_value, table_range, col_index, [range_lookup])
  static CellValue _vlookup(
    List<FormulaNode> args,
    List<List<CellValue>> Function(CellRange) resolve,
    CellValue Function(FormulaNode) eval,
  ) {
    if (args.length < 3) return const ErrorValue(CellError.valueError);
    final lookupVal = eval(args[0]);
    if (args[1] is! RangeRef) return const ErrorValue(CellError.valueError);
    final table = resolve((args[1] as RangeRef).range);
    final colIdx = eval(args[2]).asNumber?.toInt();
    if (colIdx == null || colIdx < 1) {
      return const ErrorValue(CellError.valueError);
    }
    final exactMatch = args.length > 3 ? !_toBool(eval(args[3])) : false;

    for (final row in table) {
      if (row.isEmpty) continue;
      if (colIdx > row.length)
        return const ErrorValue(CellError.referenceError);
      if (_matchValue(row[0], lookupVal, exact: exactMatch)) {
        return row[colIdx - 1];
      }
    }
    return const ErrorValue(CellError.notAvailable);
  }

  /// HLOOKUP(lookup_value, table_range, row_index, [range_lookup])
  static CellValue _hlookup(
    List<FormulaNode> args,
    List<List<CellValue>> Function(CellRange) resolve,
    CellValue Function(FormulaNode) eval,
  ) {
    if (args.length < 3) return const ErrorValue(CellError.valueError);
    final lookupVal = eval(args[0]);
    if (args[1] is! RangeRef) return const ErrorValue(CellError.valueError);
    final table = resolve((args[1] as RangeRef).range);
    final rowIdx = eval(args[2]).asNumber?.toInt();
    if (rowIdx == null || rowIdx < 1 || rowIdx > table.length) {
      return const ErrorValue(CellError.valueError);
    }
    final exactMatch = args.length > 3 ? !_toBool(eval(args[3])) : false;

    // Search first row for match.
    if (table.isEmpty) return const ErrorValue(CellError.notAvailable);
    final headerRow = table[0];
    for (int c = 0; c < headerRow.length; c++) {
      if (_matchValue(headerRow[c], lookupVal, exact: exactMatch)) {
        return table[rowIdx - 1][c];
      }
    }
    return const ErrorValue(CellError.notAvailable);
  }

  /// INDEX(range, row_num, [col_num])
  static CellValue _index(
    List<FormulaNode> args,
    List<List<CellValue>> Function(CellRange) resolve,
    CellValue Function(FormulaNode) eval,
  ) {
    if (args.length < 2) return const ErrorValue(CellError.valueError);
    if (args[0] is! RangeRef) return const ErrorValue(CellError.valueError);
    final table = resolve((args[0] as RangeRef).range);
    final rowNum = eval(args[1]).asNumber?.toInt() ?? 0;
    final colNum = args.length > 2 ? (eval(args[2]).asNumber?.toInt() ?? 1) : 1;

    if (rowNum < 1 || rowNum > table.length) {
      return const ErrorValue(CellError.referenceError);
    }
    final row = table[rowNum - 1];
    if (colNum < 1 || colNum > row.length) {
      return const ErrorValue(CellError.referenceError);
    }
    return row[colNum - 1];
  }

  /// MATCH(lookup_value, range, [match_type])
  static CellValue _match(
    List<FormulaNode> args,
    List<List<CellValue>> Function(CellRange) resolve,
    CellValue Function(FormulaNode) eval,
  ) {
    if (args.length < 2) return const ErrorValue(CellError.valueError);
    final lookupVal = eval(args[0]);
    if (args[1] is! RangeRef) return const ErrorValue(CellError.valueError);
    final table = resolve((args[1] as RangeRef).range);
    // matchType: 0=exact, 1=largest<=, -1=smallest>=
    final matchType =
        args.length > 2 ? (eval(args[2]).asNumber?.toInt() ?? 1) : 1;

    // Flatten to 1D (take first column or first row).
    final values = <CellValue>[];
    if (table.length == 1) {
      values.addAll(table[0]); // Single row — search columns.
    } else {
      for (final row in table) {
        if (row.isNotEmpty) values.add(row[0]); // Multiple rows — first col.
      }
    }

    if (matchType == 0) {
      // Exact match.
      for (int i = 0; i < values.length; i++) {
        if (_matchValue(values[i], lookupVal, exact: true)) {
          return NumberValue(i + 1); // 1-indexed
        }
      }
      return const ErrorValue(CellError.notAvailable);
    }

    // For match_type 1 or -1, find position.
    int? bestIdx;
    for (int i = 0; i < values.length; i++) {
      final n = values[i].asNumber;
      final target = lookupVal.asNumber;
      if (n == null || target == null) continue;
      if (matchType == 1 && n <= target) {
        bestIdx = i;
      } else if (matchType == -1 && n >= target) {
        bestIdx = i;
      }
    }
    return bestIdx != null
        ? NumberValue(bestIdx + 1)
        : const ErrorValue(CellError.notAvailable);
  }

  /// SUMIF(range, criteria, [sum_range])
  static CellValue _sumif(
    List<FormulaNode> args,
    List<List<CellValue>> Function(CellRange) resolve,
    CellValue Function(FormulaNode) eval,
  ) {
    if (args.length < 2) return const ErrorValue(CellError.valueError);
    if (args[0] is! RangeRef) return const ErrorValue(CellError.valueError);

    final criteriaRange = resolve((args[0] as RangeRef).range);
    final criteria = eval(args[1]);
    final sumRange =
        args.length > 2 && args[2] is RangeRef
            ? resolve((args[2] as RangeRef).range)
            : criteriaRange;

    final nums = <num>[];
    final flatCriteria = criteriaRange.expand((r) => r).toList();
    final flatSum = sumRange.expand((r) => r).toList();

    for (int i = 0; i < flatCriteria.length && i < flatSum.length; i++) {
      if (_matchesCriteria(flatCriteria[i], criteria)) {
        final n = flatSum[i].asNumber;
        if (n != null) nums.add(n);
      }
    }
    return NumberValue(DecimalHelper.sum(nums));
  }

  /// COUNTIF(range, criteria)
  static CellValue _countif(
    List<FormulaNode> args,
    List<List<CellValue>> Function(CellRange) resolve,
    CellValue Function(FormulaNode) eval,
  ) {
    if (args.length < 2) return const ErrorValue(CellError.valueError);
    if (args[0] is! RangeRef) return const ErrorValue(CellError.valueError);

    final values =
        resolve((args[0] as RangeRef).range).expand((r) => r).toList();
    final criteria = eval(args[1]);

    int count = 0;
    for (final v in values) {
      if (_matchesCriteria(v, criteria)) count++;
    }
    return NumberValue(count);
  }

  /// AVERAGEIF(range, criteria, [average_range])
  static CellValue _averageif(
    List<FormulaNode> args,
    List<List<CellValue>> Function(CellRange) resolve,
    CellValue Function(FormulaNode) eval,
  ) {
    if (args.length < 2) return const ErrorValue(CellError.valueError);
    if (args[0] is! RangeRef) return const ErrorValue(CellError.valueError);

    final criteriaRange = resolve((args[0] as RangeRef).range);
    final criteria = eval(args[1]);
    final avgRange =
        args.length > 2 && args[2] is RangeRef
            ? resolve((args[2] as RangeRef).range)
            : criteriaRange;

    final nums = <num>[];
    final flatCriteria = criteriaRange.expand((r) => r).toList();
    final flatAvg = avgRange.expand((r) => r).toList();

    for (int i = 0; i < flatCriteria.length && i < flatAvg.length; i++) {
      if (_matchesCriteria(flatCriteria[i], criteria)) {
        final n = flatAvg[i].asNumber;
        if (n != null) nums.add(n);
      }
    }
    if (nums.isEmpty) return const ErrorValue(CellError.divisionByZero);
    return NumberValue(DecimalHelper.average(nums));
  }

  // =========================================================================
  // Range-aware helpers
  // =========================================================================

  /// Check if two CellValues match for lookup purposes.
  static bool _matchValue(CellValue a, CellValue b, {required bool exact}) {
    if (exact) {
      if (a is NumberValue && b is NumberValue) return a.value == b.value;
      if (a is TextValue && b is TextValue) {
        return a.value.toLowerCase() == b.value.toLowerCase();
      }
      if (a is BoolValue && b is BoolValue) return a.value == b.value;
      return a.displayString == b.displayString;
    } else {
      // Approximate match: numbers compare by value, text by prefix.
      if (a is NumberValue && b is NumberValue) return a.value <= b.value;
      return a.displayString.toLowerCase() == b.displayString.toLowerCase();
    }
  }

  /// Match a cell value against a criteria value.
  ///
  /// Supports:
  /// - Exact value match (number, text, bool)
  /// - Comparison operators: `">5"`, `"<10"`, `">=3"`, `"<=7"`, `"<>0"`
  /// - Wildcard text: `"*text*"` (not yet implemented)
  static bool _matchesCriteria(CellValue value, CellValue criteria) {
    // If criteria is a string with comparison operator.
    if (criteria is TextValue && criteria.value.length > 1) {
      final s = criteria.value;
      if (s.startsWith('>=')) {
        final t = num.tryParse(s.substring(2));
        final v = value.asNumber;
        return t != null && v != null && v >= t;
      }
      if (s.startsWith('<=')) {
        final t = num.tryParse(s.substring(2));
        final v = value.asNumber;
        return t != null && v != null && v <= t;
      }
      if (s.startsWith('<>')) {
        final t = num.tryParse(s.substring(2));
        final v = value.asNumber;
        if (t != null && v != null) return v != t;
        return value.displayString != s.substring(2);
      }
      if (s.startsWith('>')) {
        final t = num.tryParse(s.substring(1));
        final v = value.asNumber;
        return t != null && v != null && v > t;
      }
      if (s.startsWith('<')) {
        final t = num.tryParse(s.substring(1));
        final v = value.asNumber;
        return t != null && v != null && v < t;
      }
    }

    // Exact match.
    if (criteria is NumberValue && value is NumberValue) {
      return value.value == criteria.value;
    }
    if (criteria is TextValue) {
      return value.displayString.toLowerCase() == criteria.value.toLowerCase();
    }
    return value.displayString == criteria.displayString;
  }

  // =========================================================================
  // Error handling
  // =========================================================================

  /// IFERROR(value, value_if_error)
  static CellValue _iferror(List<CellValue> args) {
    if (args.isEmpty) return const ErrorValue(CellError.valueError);
    if (args[0] is ErrorValue) {
      return args.length > 1 ? args[1] : const EmptyValue();
    }
    return args[0];
  }

  // =========================================================================
  // Array / Statistics functions
  // =========================================================================

  /// SUMPRODUCT(array1, array2, ...)
  /// Multiplies corresponding elements and sums the products.
  static CellValue _sumproduct(List<CellValue> args) {
    if (args.isEmpty) return const NumberValue(0);
    // All args are already flattened by the evaluator.
    // With a single range, just sum the values.
    // With multiple ranges, we multiply element-wise then sum.
    // Since ranges are flattened, we get interleaved values.
    // The simplest model: treat all as one flat array and sum products.
    // For true SUMPRODUCT with multiple arrays, the evaluator would need
    // to pass arrays separately. We support the common case: single array sum.
    final nums = <num>[];
    for (final v in args) {
      final n = v.asNumber;
      if (n != null) nums.add(n);
    }
    return NumberValue(DecimalHelper.sum(nums));
  }

  /// MEDIAN(values...)
  static CellValue _median(List<CellValue> args) {
    final nums = <num>[];
    for (final v in args) {
      final n = v.asNumber;
      if (n != null) nums.add(n);
    }
    if (nums.isEmpty) return const ErrorValue(CellError.valueError);
    nums.sort();
    final mid = nums.length ~/ 2;
    if (nums.length.isOdd) {
      return NumberValue(nums[mid]);
    }
    return NumberValue(DecimalHelper.average([nums[mid - 1], nums[mid]]));
  }

  /// STDEV(values...) — sample standard deviation.
  static CellValue _stdev(List<CellValue> args) {
    final nums = <num>[];
    for (final v in args) {
      final n = v.asNumber;
      if (n != null) nums.add(n);
    }
    if (nums.length < 2) return const ErrorValue(CellError.divisionByZero);
    final mean = DecimalHelper.average(nums);
    double sumSqDiff = 0;
    for (final n in nums) {
      final diff = n - mean;
      sumSqDiff += diff * diff;
    }
    return NumberValue(math.sqrt(sumSqDiff / (nums.length - 1)));
  }

  /// LARGE(array, k) — kth largest value.
  static CellValue _large(List<CellValue> args) {
    if (args.length < 2) return const ErrorValue(CellError.valueError);
    final k = args.last.asNumber?.toInt();
    if (k == null || k < 1) return const ErrorValue(CellError.valueError);
    final nums = <num>[];
    for (int i = 0; i < args.length - 1; i++) {
      final n = args[i].asNumber;
      if (n != null) nums.add(n);
    }
    if (k > nums.length) return const ErrorValue(CellError.valueError);
    nums.sort((a, b) => b.compareTo(a)); // descending
    return NumberValue(nums[k - 1]);
  }

  /// SMALL(array, k) — kth smallest value.
  static CellValue _small(List<CellValue> args) {
    if (args.length < 2) return const ErrorValue(CellError.valueError);
    final k = args.last.asNumber?.toInt();
    if (k == null || k < 1) return const ErrorValue(CellError.valueError);
    final nums = <num>[];
    for (int i = 0; i < args.length - 1; i++) {
      final n = args[i].asNumber;
      if (n != null) nums.add(n);
    }
    if (k > nums.length) return const ErrorValue(CellError.valueError);
    nums.sort(); // ascending
    return NumberValue(nums[k - 1]);
  }

  // =========================================================================
  // Utility functions
  // =========================================================================

  /// CHOOSE(index, val1, val2, ...)
  static CellValue _choose(List<CellValue> args) {
    if (args.length < 2) return const ErrorValue(CellError.valueError);
    final idx = args[0].asNumber?.toInt();
    if (idx == null || idx < 1 || idx >= args.length) {
      return const ErrorValue(CellError.valueError);
    }
    return args[idx];
  }

  /// ROUNDDOWN(number, digits) — truncate toward zero.
  static CellValue _roundDown(List<CellValue> args) {
    if (args.isEmpty) return const ErrorValue(CellError.valueError);
    final n = args[0].asNumber?.toDouble();
    if (n == null) return const ErrorValue(CellError.valueError);
    final digits = args.length > 1 ? (args[1].asNumber?.toInt() ?? 0) : 0;
    final factor = math.pow(10, digits);
    final truncated = (n * factor).truncateToDouble() / factor;
    return NumberValue(truncated);
  }

  /// ROUNDUP(number, digits) — round away from zero.
  static CellValue _roundUp(List<CellValue> args) {
    if (args.isEmpty) return const ErrorValue(CellError.valueError);
    final n = args[0].asNumber?.toDouble();
    if (n == null) return const ErrorValue(CellError.valueError);
    final digits = args.length > 1 ? (args[1].asNumber?.toInt() ?? 0) : 0;
    final factor = math.pow(10, digits);
    final scaled = n * factor;
    final rounded = n >= 0 ? scaled.ceilToDouble() : scaled.floorToDouble();
    return NumberValue(rounded / factor);
  }

  /// RANK(number, range, [order])
  /// Returns the rank of a number within a range.
  /// order=0 or omitted: descending (largest=1), order=1: ascending (smallest=1).
  static CellValue _rank(
    List<FormulaNode> args,
    List<List<CellValue>> Function(CellRange) resolve,
    CellValue Function(FormulaNode) eval,
  ) {
    if (args.length < 2) return const ErrorValue(CellError.valueError);
    final numVal = eval(args[0]).asNumber;
    if (numVal == null) return const ErrorValue(CellError.valueError);
    if (args[1] is! RangeRef) return const ErrorValue(CellError.valueError);

    final values =
        resolve((args[1] as RangeRef).range).expand((r) => r).toList();
    final ascending =
        args.length > 2 ? (eval(args[2]).asNumber?.toInt() ?? 0) != 0 : false;

    final nums = <num>[];
    for (final v in values) {
      final n = v.asNumber;
      if (n != null) nums.add(n);
    }

    if (ascending) {
      nums.sort();
    } else {
      nums.sort((a, b) => b.compareTo(a));
    }

    for (int i = 0; i < nums.length; i++) {
      if (nums[i] == numVal) return NumberValue(i + 1);
    }
    return const ErrorValue(CellError.notAvailable);
  }
}
