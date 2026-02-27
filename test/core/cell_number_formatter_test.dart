import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/tabular/cell_number_formatter.dart';

void main() {
  group('CellNumberFormatter', () {
    group('default format', () {
      test('integer', () {
        expect(CellNumberFormatter.format(42, null), '42');
      });

      test('clean decimal', () {
        expect(CellNumberFormatter.format(3.14, null), '3.14');
      });

      test('whole number double', () {
        expect(CellNumberFormatter.format(5.0, null), '5');
      });

      test('trailing zeros stripped', () {
        expect(CellNumberFormatter.format(1.10, null), '1.1');
      });
    });

    group('thousands separator', () {
      test('#,##0', () {
        expect(CellNumberFormatter.format(1234, '#,##0'), '1,234');
      });

      test('#,##0.00', () {
        expect(CellNumberFormatter.format(1234.5, '#,##0.00'), '1,234.50');
      });

      test('small number', () {
        expect(CellNumberFormatter.format(42, '#,##0'), '42');
      });

      test('million', () {
        expect(CellNumberFormatter.format(1234567, '#,##0'), '1,234,567');
      });
    });

    group('percentage', () {
      test('0%', () {
        expect(CellNumberFormatter.format(0.85, '0%'), '85%');
      });

      test('0.0%', () {
        expect(CellNumberFormatter.format(0.123, '0.0%'), '12.3%');
      });

      test('0.00%', () {
        expect(CellNumberFormatter.format(0.1234, '0.00%'), '12.34%');
      });
    });

    group('currency', () {
      test('dollar prefix', () {
        expect(CellNumberFormatter.format(1234.5, '\$#,##0.00'), '\$1,234.50');
      });

      test('euro prefix', () {
        expect(CellNumberFormatter.format(1234.5, '€#,##0.00'), '€1,234.50');
      });
    });

    group('scientific notation', () {
      test('0.00E+0', () {
        final result = CellNumberFormatter.format(1234.5, '0.00E+0');
        // Should be 1.23E+3
        expect(result, startsWith('1.23'));
        expect(result, contains('E+'));
      });
    });

    group('date format', () {
      test('yyyy-MM-dd from serial 44927', () {
        // 2023-01-01 is serial date 44927
        final result = CellNumberFormatter.format(44927, 'yyyy-MM-dd');
        expect(result, '2023-01-01');
      });
    });

    group('negative format', () {
      test('parentheses', () {
        final result = CellNumberFormatter.format(-1234, '#,##0;(#,##0)');
        expect(result, '(1,234)');
      });

      test('positive with negative pattern', () {
        final result = CellNumberFormatter.format(1234, '#,##0;(#,##0)');
        expect(result, '1,234');
      });
    });

    group('empty pattern', () {
      test('empty string same as null', () {
        expect(CellNumberFormatter.format(42, ''), '42');
      });
    });

    group('presets', () {
      test('preset map has expected keys', () {
        expect(CellNumberFormatter.presets, contains('number'));
        expect(CellNumberFormatter.presets, contains('percent'));
        expect(CellNumberFormatter.presets, contains('currency'));
        expect(CellNumberFormatter.presets, contains('date'));
        expect(CellNumberFormatter.presets, contains('scientific'));
      });
    });
  });
}
