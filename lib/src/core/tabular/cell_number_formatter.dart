import 'dart:math' as math;

/// 📊 Number formatting engine for cell display.
///
/// Supports common spreadsheet format patterns:
/// - `#,##0` — Thousands separator
/// - `#,##0.00` — Two decimal places
/// - `0%` — Percentage
/// - `0.0%` — Percentage with decimals
/// - `€#,##0.00` — Currency prefix
/// - `#,##0.00€` — Currency suffix
/// - `0.00E+0` — Scientific notation
/// - `yyyy-MM-dd` — Date formatting (from Excel serial date)
/// - `#,##0;(#,##0)` — Negative format with parentheses
///
/// ```dart
/// CellNumberFormatter.format(1234.567, '#,##0.00'); // '1,234.57'
/// CellNumberFormatter.format(0.85, '0%');             // '85%'
/// ```
class CellNumberFormatter {
  CellNumberFormatter._();

  /// Format a number according to the given pattern.
  ///
  /// Returns the raw number string if [pattern] is null or unrecognized.
  static String format(num value, String? pattern) {
    if (pattern == null || pattern.isEmpty) {
      return _defaultFormat(value);
    }

    // Handle negative format patterns (e.g. "#,##0;(#,##0)")
    if (pattern.contains(';')) {
      final parts = pattern.split(';');
      if (value < 0 && parts.length > 1) {
        return _applyPattern(value.abs(), parts[1]);
      }
      return _applyPattern(value, parts[0]);
    }

    return _applyPattern(value, pattern);
  }

  static String _applyPattern(num value, String pattern) {
    // Percentage.
    if (pattern.endsWith('%')) {
      final decimals = _countDecimalPlaces(
        pattern.substring(0, pattern.length - 1),
      );
      return '${(value.toDouble() * 100).toStringAsFixed(decimals)}%';
    }

    // Scientific notation.
    if (pattern.contains('E+') || pattern.contains('E-')) {
      final decimals = _countDecimalPlaces(pattern.split('E')[0]);
      final result = value.toDouble().toStringAsExponential(decimals);
      // Dart uses lowercase 'e', convert to uppercase 'E'.
      return result.replaceAll('e+', 'E+').replaceAll('e-', 'E-');
    }

    // Date format from Excel serial date number.
    if (_isDateFormat(pattern)) {
      return _formatDate(value, pattern);
    }

    // Extract prefix and suffix (currency symbols, etc.).
    String prefix = '';
    String suffix = '';
    String numPattern = pattern;

    // Extract leading non-format characters (e.g., "$", "€").
    int prefixEnd = 0;
    while (prefixEnd < numPattern.length &&
        !_isFormatChar(numPattern[prefixEnd])) {
      prefixEnd++;
    }
    if (prefixEnd > 0) {
      prefix = numPattern.substring(0, prefixEnd);
      numPattern = numPattern.substring(prefixEnd);
    }

    // Extract trailing non-format characters.
    int suffixStart = numPattern.length;
    while (suffixStart > 0 && !_isFormatChar(numPattern[suffixStart - 1])) {
      suffixStart--;
    }
    if (suffixStart < numPattern.length) {
      suffix = numPattern.substring(suffixStart);
      numPattern = numPattern.substring(0, suffixStart);
    }

    // Count decimal places.
    final decimals = _countDecimalPlaces(numPattern);

    // Check for thousands separator.
    final useThousands = numPattern.contains(',');

    // Format the number.
    final formatted = value.toDouble().toStringAsFixed(decimals);

    // Apply thousands separator.
    String result;
    if (useThousands) {
      result = _addThousandsSeparator(formatted);
    } else {
      result = formatted;
    }

    // Handle parentheses wrapping pattern (used for negative numbers).
    // When called from format() with `;` split, value is already abs.
    if (pattern.contains('(') && pattern.contains(')')) {
      final cleanPattern = pattern.replaceAll('(', '').replaceAll(')', '');
      final inner = _applyPattern(value, cleanPattern);
      return '($inner)';
    }

    if (value < 0) {
      // Ensure negative sign is before prefix.
      return '-$prefix${result.replaceAll('-', '')}$suffix';
    }

    return '$prefix$result$suffix';
  }

  // =========================================================================
  // Predefined format presets
  // =========================================================================

  /// Common format presets.
  static const Map<String, String> presets = {
    'general': '',
    'number': '#,##0.00',
    'integer': '#,##0',
    'percent': '0%',
    'percentDecimal': '0.00%',
    'currency': '\$#,##0.00',
    'euroCurrency': '€#,##0.00',
    'scientific': '0.00E+0',
    'date': 'yyyy-MM-dd',
    'dateTime': 'yyyy-MM-dd HH:mm',
    'accounting': '#,##0.00;(#,##0.00)',
  };

  // =========================================================================
  // Internal helpers
  // =========================================================================

  static String _defaultFormat(num value) {
    if (value is int) return value.toString();
    final d = value.toDouble();
    // Remove trailing zeros for clean display.
    if (d == d.truncateToDouble()) return d.toInt().toString();
    // Limit to 10 decimal places max.
    final s = d.toStringAsFixed(10);
    // Strip trailing zeros.
    int end = s.length - 1;
    while (end > 0 && s[end] == '0') {
      end--;
    }
    if (s[end] == '.') end--;
    return s.substring(0, end + 1);
  }

  static int _countDecimalPlaces(String pattern) {
    final dotIndex = pattern.indexOf('.');
    if (dotIndex < 0) return 0;
    int count = 0;
    for (int i = dotIndex + 1; i < pattern.length; i++) {
      final c = pattern[i];
      if (c == '0' || c == '#') {
        count++;
      } else {
        break;
      }
    }
    return count;
  }

  static bool _isFormatChar(String c) {
    return c == '#' || c == '0' || c == ',' || c == '.' || c == '(' || c == ')';
  }

  static String _addThousandsSeparator(String formatted) {
    final parts = formatted.split('.');
    final intPart = parts[0];
    final isNegative = intPart.startsWith('-');
    final digits = isNegative ? intPart.substring(1) : intPart;

    final buf = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        buf.write(',');
      }
      buf.write(digits[i]);
    }

    final result = isNegative ? '-${buf.toString()}' : buf.toString();
    if (parts.length > 1) {
      return '$result.${parts[1]}';
    }
    return result;
  }

  static bool _isDateFormat(String pattern) {
    return pattern.contains('yyyy') ||
        pattern.contains('MM') ||
        pattern.contains('dd') ||
        pattern.contains('HH') ||
        pattern.contains('mm') ||
        pattern.contains('ss');
  }

  /// Format an Excel serial date number to a date string.
  ///
  /// Excel serial dates start from 1900-01-01 (serial = 1).
  static String _formatDate(num serialDate, String pattern) {
    // Convert Excel serial date to DateTime.
    // Excel epoch: 1899-12-30 (to account for the Lotus 1-2-3 bug).
    final epoch = DateTime(1899, 12, 30);
    final date = epoch.add(Duration(days: serialDate.toInt()));

    String result = pattern;
    result = result.replaceAll('yyyy', date.year.toString().padLeft(4, '0'));
    result = result.replaceAll('MM', date.month.toString().padLeft(2, '0'));
    result = result.replaceAll('dd', date.day.toString().padLeft(2, '0'));
    result = result.replaceAll('HH', date.hour.toString().padLeft(2, '0'));
    result = result.replaceAll('mm', date.minute.toString().padLeft(2, '0'));
    result = result.replaceAll('ss', date.second.toString().padLeft(2, '0'));

    return result;
  }
}
