import 'dart:math' as math;

/// 📊 Precision-aware arithmetic using native Dart [BigInt].
///
/// All spreadsheet arithmetic is routed through this class to avoid
/// IEEE 754 floating-point errors. Internally, numbers are converted
/// to scaled [BigInt] integers (fixed-point representation), all
/// operations are performed on integers, then the result is converted
/// back to [num].
///
/// The classic `0.1 + 0.2 = 0.30000000000000004` is eliminated:
///
/// ```dart
/// DecimalHelper.add(0.1, 0.2);       // 0.3 (exact)
/// DecimalHelper.round(2.5, 0);       // 2.0 (Banker's rounding)
/// DecimalHelper.multiply(1.1, 1.1);  // 1.21 (exact)
/// ```
///
/// **No external dependencies** — pure Dart with [BigInt].
class DecimalHelper {
  DecimalHelper._();

  /// Maximum internal scale (decimal digits) for intermediate results.
  static const int _maxScale = 20;

  // -------------------------------------------------------------------------
  // Core arithmetic
  // -------------------------------------------------------------------------

  /// Precision addition: `a + b`.
  static num add(num a, num b) {
    final (aInt, aScale) = _decompose(a);
    final (bInt, bScale) = _decompose(b);
    final scale = math.max(aScale, bScale);
    final aScaled = aInt * _pow10(scale - aScale);
    final bScaled = bInt * _pow10(scale - bScale);
    return _recompose(aScaled + bScaled, scale);
  }

  /// Precision subtraction: `a - b`.
  static num subtract(num a, num b) {
    final (aInt, aScale) = _decompose(a);
    final (bInt, bScale) = _decompose(b);
    final scale = math.max(aScale, bScale);
    final aScaled = aInt * _pow10(scale - aScale);
    final bScaled = bInt * _pow10(scale - bScale);
    return _recompose(aScaled - bScaled, scale);
  }

  /// Precision multiplication: `a * b`.
  static num multiply(num a, num b) {
    final (aInt, aScale) = _decompose(a);
    final (bInt, bScale) = _decompose(b);
    return _recompose(aInt * bInt, aScale + bScale);
  }

  /// Precision division: `a / b`.
  ///
  /// Extends precision to [_maxScale] digits to handle repeating decimals.
  static num divide(num a, num b) {
    if (b == 0) return double.infinity;
    final (aInt, aScale) = _decompose(a);
    final (bInt, bScale) = _decompose(b);
    // Scale up the numerator to get enough precision.
    final extraScale = _maxScale;
    final scaledA = aInt * _pow10(extraScale);
    final resultInt = scaledA ~/ bInt;
    final resultScale = aScale - bScale + extraScale;
    return _recompose(resultInt, resultScale);
  }

  /// Precision modulo: `a % b`.
  static num modulo(num a, num b) {
    if (b == 0) return double.nan;
    final (aInt, aScale) = _decompose(a);
    final (bInt, bScale) = _decompose(b);
    final scale = math.max(aScale, bScale);
    final aScaled = aInt * _pow10(scale - aScale);
    final bScaled = bInt * _pow10(scale - bScale);
    return _recompose(aScaled % bScaled, scale);
  }

  /// Precision power: `base ^ exponent`.
  ///
  /// For integer exponents (≤100), uses repeated BigInt multiplication.
  /// For fractional exponents, falls back to `dart:math`.
  static num power(num base, num exponent) {
    if (exponent == exponent.toInt() && exponent.toInt().abs() <= 100) {
      return _intPower(base, exponent.toInt());
    }
    return math.pow(base.toDouble(), exponent.toDouble()).toDouble();
  }

  /// Precision negation: `-a`.
  static num negate(num a) {
    final (aInt, aScale) = _decompose(a);
    return _recompose(-aInt, aScale);
  }

  /// Precision percentage: `a / 100`.
  static num percent(num a) {
    final (aInt, aScale) = _decompose(a);
    return _recompose(aInt, aScale + 2);
  }

  // -------------------------------------------------------------------------
  // Rounding
  // -------------------------------------------------------------------------

  /// Round to [places] decimal digits using **Banker's rounding**
  /// (round-half-to-even), the standard in financial software.
  ///
  /// ```dart
  /// DecimalHelper.round(2.5, 0);   // 2 (even)
  /// DecimalHelper.round(3.5, 0);   // 4 (even)
  /// DecimalHelper.round(2.455, 2); // 2.46
  /// ```
  static num round(num value, int places) {
    final (vInt, vScale) = _decompose(value);

    if (vScale <= places) {
      // Already has fewer decimal places than requested.
      return _recompose(vInt * _pow10(places - vScale), places);
    }

    final dropDigits = vScale - places;
    final divisor = _pow10(dropDigits);
    final truncated = vInt ~/ divisor;
    final remainder = (vInt % divisor).abs();
    final half = divisor ~/ BigInt.two;
    final isExactHalf = remainder == half;

    BigInt rounded;
    if (isExactHalf) {
      // Banker's rounding: round to even.
      if (truncated.isEven) {
        rounded = truncated;
      } else {
        rounded =
            vInt.isNegative ? truncated - BigInt.one : truncated + BigInt.one;
      }
    } else if (remainder > half) {
      rounded =
          vInt.isNegative ? truncated - BigInt.one : truncated + BigInt.one;
    } else {
      rounded = truncated;
    }

    return _recompose(rounded, places);
  }

  /// Floor towards negative infinity.
  static num floor(num value) {
    final (vInt, vScale) = _decompose(value);
    if (vScale == 0) return _recompose(vInt, 0);
    final divisor = _pow10(vScale);
    var result = vInt ~/ divisor;
    // For negative numbers with a remainder, floor goes further negative.
    if (vInt.isNegative && vInt % divisor != BigInt.zero) {
      result -= BigInt.one;
    }
    return _recompose(result, 0);
  }

  /// Ceil towards positive infinity.
  static num ceil(num value) {
    final (vInt, vScale) = _decompose(value);
    if (vScale == 0) return _recompose(vInt, 0);
    final divisor = _pow10(vScale);
    var result = vInt ~/ divisor;
    // For positive numbers with a remainder, ceil goes further positive.
    if (!vInt.isNegative && vInt % divisor != BigInt.zero) {
      result += BigInt.one;
    }
    return _recompose(result, 0);
  }

  // -------------------------------------------------------------------------
  // Comparison
  // -------------------------------------------------------------------------

  /// Exact decimal comparison (no epsilon needed).
  static int compare(num a, num b) {
    final (aInt, aScale) = _decompose(a);
    final (bInt, bScale) = _decompose(b);
    final scale = math.max(aScale, bScale);
    final aScaled = aInt * _pow10(scale - aScale);
    final bScaled = bInt * _pow10(scale - bScale);
    return aScaled.compareTo(bScaled);
  }

  /// Exact equality.
  static bool equals(num a, num b) => compare(a, b) == 0;

  // -------------------------------------------------------------------------
  // Aggregation helpers (SUM, AVERAGE)
  // -------------------------------------------------------------------------

  /// Sum with full decimal precision.
  static num sum(Iterable<num> values) {
    if (values.isEmpty) return 0;
    BigInt totalInt = BigInt.zero;
    int totalScale = 0;

    for (final v in values) {
      final (vInt, vScale) = _decompose(v);
      if (vScale > totalScale) {
        totalInt = totalInt * _pow10(vScale - totalScale);
        totalScale = vScale;
      }
      totalInt += vInt * _pow10(totalScale - vScale);
    }
    return _recompose(totalInt, totalScale);
  }

  /// Average with full decimal precision.
  static num average(Iterable<num> values) {
    if (values.isEmpty) return 0;
    return divide(sum(values), values.length);
  }

  // -------------------------------------------------------------------------
  // Internal — fixed-point decomposition
  // -------------------------------------------------------------------------

  /// Decompose a [num] into (scaledBigInt, scale).
  ///
  /// Example: `3.14` → `(BigInt(314), 2)`
  /// Example: `42` → `(BigInt(42), 0)`
  static (BigInt, int) _decompose(num n) {
    if (n is int) return (BigInt.from(n), 0);

    // Convert to string to capture all significant digits exactly.
    String s = n.toString();

    // Handle scientific notation (e.g. '1.5e-7').
    if (s.contains('e') || s.contains('E')) {
      s = _expandScientific(s);
    }

    final negative = s.startsWith('-');
    if (negative) s = s.substring(1);

    final dotIndex = s.indexOf('.');
    if (dotIndex < 0) {
      final bi = BigInt.parse(s);
      return (negative ? -bi : bi, 0);
    }

    final intPart = s.substring(0, dotIndex);
    var fracPart = s.substring(dotIndex + 1);

    // Trim trailing zeros for canonical form.
    while (fracPart.isNotEmpty && fracPart.endsWith('0')) {
      fracPart = fracPart.substring(0, fracPart.length - 1);
    }

    final scale = fracPart.length;
    final combined = intPart + fracPart;
    final bi = combined.isEmpty ? BigInt.zero : BigInt.parse(combined);
    return (negative ? -bi : bi, scale);
  }

  /// Recompose (scaledBigInt, scale) back to [num].
  ///
  /// Prefers `int` when the result is an exact integer.
  static num _recompose(BigInt value, int scale) {
    // Trim trailing zeros from the scaled representation.
    while (scale > 0 &&
        value != BigInt.zero &&
        value % BigInt.from(10) == BigInt.zero) {
      value = value ~/ BigInt.from(10);
      scale--;
    }

    if (scale <= 0) {
      // Pure integer.
      if (value >= _minSafeInt && value <= _maxSafeInt) {
        return value.toInt();
      }
      return value.toDouble();
    }

    // Build decimal string and parse.
    final negative = value.isNegative;
    final absStr = value.abs().toString();

    String result;
    if (absStr.length <= scale) {
      // Need leading zeros: e.g. BigInt(3), scale=2 → "0.03"
      result = '0.${absStr.padLeft(scale, '0')}';
    } else {
      final intPart = absStr.substring(0, absStr.length - scale);
      final fracPart = absStr.substring(absStr.length - scale);
      result = '$intPart.$fracPart';
    }

    if (negative) result = '-$result';

    // Try int first.
    final d = double.parse(result);
    if (d == d.truncateToDouble() && d.abs() < 9007199254740992) {
      return d.toInt();
    }
    return d;
  }

  /// Cached powers of 10 as BigInt for performance.
  static final List<BigInt> _pow10Cache = List.generate(
    30,
    (i) => BigInt.from(10).pow(i),
  );

  static BigInt _pow10(int n) {
    if (n < 0) return BigInt.one; // safety
    if (n < _pow10Cache.length) return _pow10Cache[n];
    return BigInt.from(10).pow(n);
  }

  static final BigInt _maxSafeInt = BigInt.from(9007199254740991);
  static final BigInt _minSafeInt = BigInt.from(-9007199254740991);

  /// Expand scientific notation string to full decimal string.
  ///
  /// Example: `'1.5e-7'` → `'0.00000015'`
  static String _expandScientific(String s) {
    final lower = s.toLowerCase();
    final eIndex = lower.indexOf('e');
    final mantissa = lower.substring(0, eIndex);
    final exponent = int.parse(lower.substring(eIndex + 1));

    final negative = mantissa.startsWith('-');
    var clean = negative ? mantissa.substring(1) : mantissa;

    final dotIndex = clean.indexOf('.');
    String digits;
    int currentDecimalPlaces;
    if (dotIndex >= 0) {
      digits = clean.substring(0, dotIndex) + clean.substring(dotIndex + 1);
      currentDecimalPlaces = clean.length - dotIndex - 1;
    } else {
      digits = clean;
      currentDecimalPlaces = 0;
    }

    // New position of decimal point from the left.
    final newDotPos = digits.length - currentDecimalPlaces + exponent;

    String result;
    if (newDotPos <= 0) {
      // All digits are after decimal point.
      result = '0.${'0' * (-newDotPos)}$digits';
    } else if (newDotPos >= digits.length) {
      // All digits are before decimal point.
      result = '$digits${'0' * (newDotPos - digits.length)}';
    } else {
      result =
          '${digits.substring(0, newDotPos)}.${digits.substring(newDotPos)}';
    }

    return negative ? '-$result' : result;
  }

  /// Integer power via repeated BigInt multiplication.
  static num _intPower(num base, int exponent) {
    if (exponent == 0) return 1;

    final (baseInt, baseScale) = _decompose(base);
    final negative = exponent < 0;
    var exp = exponent.abs();

    var resultInt = BigInt.one;
    var resultScale = 0;
    var curInt = baseInt;
    var curScale = baseScale;

    while (exp > 0) {
      if (exp.isOdd) {
        resultInt *= curInt;
        resultScale += curScale;
      }
      curInt *= curInt;
      curScale *= 2;
      exp ~/= 2;
    }

    if (negative) {
      // 1 / result — use division with extended precision.
      final extraScale = _maxScale;
      final numerator = _pow10(resultScale + extraScale);
      final divided = numerator ~/ resultInt;
      return _recompose(divided, extraScale);
    }
    return _recompose(resultInt, resultScale);
  }
}
