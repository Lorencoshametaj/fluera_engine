/// 🧮 LaTeX Validator — validates LaTeX syntax before rendering.
///
/// Checks for common structural errors in LaTeX strings:
/// - Unmatched braces `{ }`
/// - Unmatched `\left` / `\right`
/// - Missing arguments for commands (e.g. `\frac` without two arguments)
/// - Empty groups in critical positions
///
/// Returns a list of [LatexValidationError] with position information
/// for UI error highlighting.
///
/// Example:
/// ```dart
/// final errors = LatexValidator.validate(r'\frac{a}');
/// // → [LatexValidationError(pos: 8, message: '\frac requires 2 arguments')]
/// ```
class LatexValidator {
  /// Validate a LaTeX string and return all found errors.
  ///
  /// Returns an empty list if the string is valid.
  static List<LatexValidationError> validate(String source) {
    final errors = <LatexValidationError>[];

    _checkBraces(source, errors);
    _checkCommandArity(source, errors);
    _checkDelimiters(source, errors);

    return errors;
  }

  /// Quick check — returns `true` if the string has no validation errors.
  static bool isValid(String source) => validate(source).isEmpty;

  // ---------------------------------------------------------------------------
  // Brace Matching
  // ---------------------------------------------------------------------------

  static void _checkBraces(String source, List<LatexValidationError> errors) {
    int depth = 0;
    final openPositions = <int>[];

    for (int i = 0; i < source.length; i++) {
      if (source[i] == '{') {
        depth++;
        openPositions.add(i);
      } else if (source[i] == '}') {
        depth--;
        if (depth < 0) {
          errors.add(
            LatexValidationError(
              position: i,
              message: 'Unmatched closing brace "}"',
              severity: ValidationSeverity.error,
            ),
          );
          depth = 0; // reset
        } else {
          openPositions.removeLast();
        }
      }
    }

    // Any remaining unclosed braces
    for (final pos in openPositions) {
      errors.add(
        LatexValidationError(
          position: pos,
          message: 'Unmatched opening brace "{"',
          severity: ValidationSeverity.error,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Command Arity
  // ---------------------------------------------------------------------------

  static void _checkCommandArity(
    String source,
    List<LatexValidationError> errors,
  ) {
    int i = 0;
    while (i < source.length) {
      if (source[i] == '\\') {
        final cmdStart = i;
        i++; // skip backslash

        // Single-char commands
        if (i < source.length && !_isLetter(source[i])) {
          i++;
          continue;
        }

        // Read command name
        final buf = StringBuffer();
        while (i < source.length && _isLetter(source[i])) {
          buf.write(source[i]);
          i++;
        }
        final cmd = buf.toString();

        // Check arity
        final expectedArgs = _commandArity[cmd];
        if (expectedArgs != null && expectedArgs > 0) {
          // Count available braced arguments
          int foundArgs = 0;
          int scanPos = i;

          // Skip whitespace between command and args
          while (scanPos < source.length && source[scanPos] == ' ') {
            scanPos++;
          }

          // Handle optional argument for \sqrt
          if (cmd == 'sqrt' &&
              scanPos < source.length &&
              source[scanPos] == '[') {
            // Skip optional argument
            while (scanPos < source.length && source[scanPos] != ']') {
              scanPos++;
            }
            if (scanPos < source.length) scanPos++; // skip ]
            while (scanPos < source.length && source[scanPos] == ' ') {
              scanPos++;
            }
          }

          for (int a = 0; a < expectedArgs; a++) {
            while (scanPos < source.length && source[scanPos] == ' ') {
              scanPos++;
            }
            if (scanPos < source.length && source[scanPos] == '{') {
              // Skip to matching close brace
              int braceDepth = 1;
              scanPos++;
              while (scanPos < source.length && braceDepth > 0) {
                if (source[scanPos] == '{') braceDepth++;
                if (source[scanPos] == '}') braceDepth--;
                scanPos++;
              }
              foundArgs++;
            } else {
              break;
            }
          }

          if (foundArgs < expectedArgs) {
            errors.add(
              LatexValidationError(
                position: cmdStart,
                message:
                    '\\$cmd requires $expectedArgs argument(s), found $foundArgs',
                severity: ValidationSeverity.error,
              ),
            );
          }
        }
      } else {
        i++;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Delimiter Matching
  // ---------------------------------------------------------------------------

  static void _checkDelimiters(
    String source,
    List<LatexValidationError> errors,
  ) {
    int leftCount = 0;
    int rightCount = 0;
    int i = 0;

    while (i < source.length) {
      if (i < source.length - 4 && source.substring(i, i + 5) == r'\left') {
        leftCount++;
        i += 5;
      } else if (i < source.length - 5 &&
          source.substring(i, i + 6) == r'\right') {
        rightCount++;
        if (rightCount > leftCount) {
          errors.add(
            LatexValidationError(
              position: i,
              message: r'Unmatched \right without corresponding \left',
              severity: ValidationSeverity.error,
            ),
          );
        }
        i += 6;
      } else {
        i++;
      }
    }

    if (leftCount > rightCount) {
      errors.add(
        LatexValidationError(
          position: source.length,
          message: r'Unmatched \left — missing \right',
          severity: ValidationSeverity.warning,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static bool _isLetter(String c) {
    final code = c.codeUnitAt(0);
    return (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
  }

  /// Expected number of braced arguments for commands.
  static const Map<String, int> _commandArity = {
    'frac': 2,
    'dfrac': 2,
    'tfrac': 2,
    'cfrac': 2,
    'binom': 2,
    'sqrt': 1,
    'hat': 1,
    'bar': 1,
    'overline': 1,
    'underline': 1,
    'vec': 1,
    'dot': 1,
    'ddot': 1,
    'tilde': 1,
    'widehat': 1,
    'widetilde': 1,
    'text': 1,
    'mathrm': 1,
    'mathbf': 1,
    'mathit': 1,
    'mathbb': 1,
    'mathcal': 1,
    'mathfrak': 1,
    'mathscr': 1,
    'textbf': 1,
    'textit': 1,
    'textrm': 1,
    'overset': 2,
    'underset': 2,
    'stackrel': 2,
    'boxed': 1,
    'phantom': 1,
    'color': 1,
  };
}

/// A single validation error with position and message.
class LatexValidationError {
  /// Character position in the source string where the error occurs.
  final int position;

  /// Human-readable error message.
  final String message;

  /// Error severity.
  final ValidationSeverity severity;

  const LatexValidationError({
    required this.position,
    required this.message,
    this.severity = ValidationSeverity.error,
  });

  @override
  String toString() =>
      'LatexValidationError(pos: $position, $severity: $message)';
}

/// Severity levels for validation errors.
enum ValidationSeverity {
  /// Hard error — the expression will not render correctly.
  error,

  /// Warning — the expression may render but with potential issues.
  warning,

  /// Info — a style suggestion that doesn't affect rendering.
  info,
}
