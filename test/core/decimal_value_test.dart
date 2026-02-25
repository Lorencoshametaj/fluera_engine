import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/tabular/decimal_value.dart';

void main() {
  // ===========================================================================
  // Addition
  // ===========================================================================

  group('DecimalHelper - add', () {
    test('0.1 + 0.2 = 0.3 (exact)', () {
      expect(DecimalHelper.add(0.1, 0.2), 0.3);
    });

    test('integer addition', () {
      expect(DecimalHelper.add(10, 20), 30);
    });

    test('negative addition', () {
      expect(DecimalHelper.add(-0.5, 0.5), 0.0);
    });
  });

  // ===========================================================================
  // Subtraction
  // ===========================================================================

  group('DecimalHelper - subtract', () {
    test('0.3 - 0.1 = 0.2 (exact)', () {
      expect(DecimalHelper.subtract(0.3, 0.1), 0.2);
    });

    test('integer subtraction', () {
      expect(DecimalHelper.subtract(50, 30), 20);
    });
  });

  // ===========================================================================
  // Multiplication
  // ===========================================================================

  group('DecimalHelper - multiply', () {
    test('1.1 * 1.1 = 1.21 (exact)', () {
      expect(DecimalHelper.multiply(1.1, 1.1), 1.21);
    });

    test('0 * anything = 0', () {
      expect(DecimalHelper.multiply(0, 42), 0);
    });
  });

  // ===========================================================================
  // Division
  // ===========================================================================

  group('DecimalHelper - divide', () {
    test('10 / 3 produces result', () {
      final result = DecimalHelper.divide(10, 3);
      expect(result, closeTo(3.333, 0.01));
    });

    test('1 / 4 = 0.25 (exact)', () {
      expect(DecimalHelper.divide(1, 4), 0.25);
    });
  });

  // ===========================================================================
  // Modulo
  // ===========================================================================

  group('DecimalHelper - modulo', () {
    test('10 % 3 = 1', () {
      expect(DecimalHelper.modulo(10, 3), 1);
    });

    test('7.5 % 2.5 = 0', () {
      expect(DecimalHelper.modulo(7.5, 2.5), 0);
    });
  });

  // ===========================================================================
  // Power
  // ===========================================================================

  group('DecimalHelper - power', () {
    test('2^10 = 1024', () {
      expect(DecimalHelper.power(2, 10), 1024);
    });

    test('3^0 = 1', () {
      expect(DecimalHelper.power(3, 0), 1);
    });
  });

  // ===========================================================================
  // Negate / Percent
  // ===========================================================================

  group('DecimalHelper - negate/percent', () {
    test('negate 5 = -5', () {
      expect(DecimalHelper.negate(5), -5);
    });

    test('percent 50 = 0.5', () {
      expect(DecimalHelper.percent(50), 0.5);
    });
  });

  // ===========================================================================
  // Rounding (Banker's)
  // ===========================================================================

  group('DecimalHelper - round', () {
    test('round 2.5 to 0 places = 2 (banker)', () {
      expect(DecimalHelper.round(2.5, 0), 2);
    });

    test('round 3.5 to 0 places = 4 (banker)', () {
      expect(DecimalHelper.round(3.5, 0), 4);
    });

    test('round 2.455 to 2 places = 2.46', () {
      expect(DecimalHelper.round(2.455, 2), 2.46);
    });
  });

  // ===========================================================================
  // Floor / Ceil
  // ===========================================================================

  group('DecimalHelper - floor/ceil', () {
    test('floor 3.7 = 3', () {
      expect(DecimalHelper.floor(3.7), 3);
    });

    test('ceil 3.2 = 4', () {
      expect(DecimalHelper.ceil(3.2), 4);
    });

    test('floor -2.3 = -3', () {
      expect(DecimalHelper.floor(-2.3), -3);
    });
  });

  // ===========================================================================
  // Comparison
  // ===========================================================================

  group('DecimalHelper - compare/equals', () {
    test('0.1 + 0.2 equals 0.3', () {
      expect(DecimalHelper.equals(DecimalHelper.add(0.1, 0.2), 0.3), isTrue);
    });

    test('compare orders correctly', () {
      expect(DecimalHelper.compare(1, 2), lessThan(0));
      expect(DecimalHelper.compare(2, 1), greaterThan(0));
      expect(DecimalHelper.compare(1, 1), 0);
    });
  });

  // ===========================================================================
  // Sum / Average
  // ===========================================================================

  group('DecimalHelper - sum/average', () {
    test('sum of [0.1, 0.2, 0.3] = 0.6', () {
      expect(DecimalHelper.sum([0.1, 0.2, 0.3]), 0.6);
    });

    test('average of [2, 4, 6] = 4', () {
      expect(DecimalHelper.average([2, 4, 6]), 4);
    });

    test('sum of empty = 0', () {
      expect(DecimalHelper.sum([]), 0);
    });
  });
}
