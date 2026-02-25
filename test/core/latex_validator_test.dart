import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/latex/latex_validator.dart';

void main() {
  // ===========================================================================
  // Valid LaTeX
  // ===========================================================================

  group('LatexValidator - valid', () {
    test('simple expression is valid', () {
      expect(LatexValidator.isValid(r'x^2 + y^2 = z^2'), isTrue);
    });

    test('frac with two args is valid', () {
      expect(LatexValidator.isValid(r'\frac{a}{b}'), isTrue);
    });

    test('nested braces are valid', () {
      expect(LatexValidator.isValid(r'\frac{a+{b}}{c}'), isTrue);
    });

    test('matched left/right is valid', () {
      expect(LatexValidator.isValid(r'\left( x \right)'), isTrue);
    });
  });

  // ===========================================================================
  // Unmatched braces
  // ===========================================================================

  group('LatexValidator - braces', () {
    test('unclosed brace detected', () {
      final errors = LatexValidator.validate(r'{a + b');
      expect(errors, isNotEmpty);
      expect(errors.any((e) => e.message.contains('Unmatched')), isTrue);
    });

    test('extra closing brace detected', () {
      final errors = LatexValidator.validate(r'a + b}');
      expect(errors, isNotEmpty);
    });
  });

  // ===========================================================================
  // Command arity
  // ===========================================================================

  group('LatexValidator - command arity', () {
    test('frac with one arg is error', () {
      final errors = LatexValidator.validate(r'\frac{a}');
      expect(errors.any((e) => e.message.contains('frac')), isTrue);
    });

    test('sqrt with one arg is valid', () {
      final errors = LatexValidator.validate(r'\sqrt{x}');
      expect(errors.where((e) => e.message.contains('sqrt')), isEmpty);
    });
  });

  // ===========================================================================
  // Delimiter matching
  // ===========================================================================

  group('LatexValidator - delimiters', () {
    test('unmatched left detected', () {
      final errors = LatexValidator.validate(r'\left( x + y');
      expect(errors.any((e) => e.message.contains('left')), isTrue);
    });

    test('unmatched right detected', () {
      final errors = LatexValidator.validate(r'x + y \right)');
      expect(errors.any((e) => e.message.contains('right')), isTrue);
    });
  });

  // ===========================================================================
  // LatexValidationError
  // ===========================================================================

  group('LatexValidationError', () {
    test('toString includes position', () {
      const err = LatexValidationError(position: 5, message: 'test');
      expect(err.toString(), contains('5'));
    });

    test('severity defaults to error', () {
      const err = LatexValidationError(position: 0, message: 'x');
      expect(err.severity, ValidationSeverity.error);
    });
  });

  // ===========================================================================
  // ValidationSeverity enum
  // ===========================================================================

  group('ValidationSeverity', () {
    test('has error, warning, info', () {
      expect(ValidationSeverity.values.length, 3);
    });
  });
}
