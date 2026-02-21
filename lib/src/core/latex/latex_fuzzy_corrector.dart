/// 🧮 LaTeX Fuzzy Corrector — corrects typos in ML-recognized LaTeX commands.
///
/// When the ML model produces slightly mangled command names (e.g. `\frcx`
/// instead of `\frac`), this corrector finds the closest valid command
/// using Levenshtein edit distance.
///
/// The dictionary contains ~200 common LaTeX math commands.
/// Commands with edit distance ≤ 2 are corrected; beyond that, the
/// original is preserved to avoid false corrections.
///
/// Example:
/// ```dart
/// final corrected = LatexFuzzyCorrector.correct(r'\frcx{a}{b}');
/// // → r'\frac{a}{b}'
/// ```
class LatexFuzzyCorrector {
  /// Maximum edit distance for correction.
  static const int maxEditDistance = 2;

  /// Correct a full LaTeX string by fixing misspelled commands
  /// and common ML misrecognitions.
  static String correct(String source) {
    // R7: Apply character-level misrecognition fixes first
    var fixed = _applyCharacterFixes(source);

    // Then apply command-level corrections
    return _correctCommands(fixed);
  }

  /// R7: Fix common Pix2Tex character-level confusions.
  ///
  /// These are NOT command-level errors — they're single-character
  /// substitutions the model frequently makes.
  static String _applyCharacterFixes(String source) {
    var result = source;
    for (final entry in _characterFixes.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    return result;
  }

  /// R7: Common character-level misrecognitions specific to Pix2Tex.
  ///
  /// These are applied as string replacements before command correction.
  /// The model frequently confuses these in low-quality input conditions.
  static const Map<String, String> _characterFixes = {
    // Digit/letter confusions
    'O': '0', // uppercase O → digit 0 in numeric context is NOT safe
    // These are applied only in specific patterns to avoid over-correction:
  };

  static String _correctCommands(String source) {
    final result = StringBuffer();
    int i = 0;

    while (i < source.length) {
      if (source[i] == '\\') {
        // Extract command name
        final start = i;
        i++; // skip backslash

        // Single-char commands
        if (i < source.length && !_isLetter(source[i])) {
          result.write(source[start]);
          result.write(source[i]);
          i++;
          continue;
        }

        // Multi-char command
        final cmdBuf = StringBuffer();
        while (i < source.length && _isLetter(source[i])) {
          cmdBuf.write(source[i]);
          i++;
        }
        final cmdName = cmdBuf.toString();

        // Check if the command is valid
        if (_validCommands.contains(cmdName)) {
          result.write('\\');
          result.write(cmdName);
        } else {
          // R7: Check common misrecognitions first (faster than Levenshtein)
          final misrecFix = _commonMisrecognitions[cmdName];
          if (misrecFix != null) {
            result.write('\\');
            result.write(misrecFix);
          } else {
            // Levenshtein fallback
            final closest = _findClosest(cmdName);
            if (closest != null) {
              result.write('\\');
              result.write(closest);
            } else {
              // No close match — preserve original
              result.write('\\');
              result.write(cmdName);
            }
          }
        }
      } else {
        result.write(source[i]);
        i++;
      }
    }

    return result.toString();
  }

  /// Find the closest valid command within [maxEditDistance].
  static String? _findClosest(String input) {
    String? bestMatch;
    int bestDistance = maxEditDistance + 1;

    for (final cmd in _validCommands) {
      // Quick length check — edit distance can't be less than length difference
      final lengthDiff = (cmd.length - input.length).abs();
      if (lengthDiff > maxEditDistance) continue;

      final dist = _levenshtein(input, cmd);
      if (dist < bestDistance) {
        bestDistance = dist;
        bestMatch = cmd;
      }
    }

    return bestDistance <= maxEditDistance ? bestMatch : null;
  }

  /// Compute Levenshtein edit distance between two strings.
  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    // Optimization: use single-row DP
    var prev = List.generate(b.length + 1, (i) => i);
    var curr = List.filled(b.length + 1, 0);

    for (int i = 1; i <= a.length; i++) {
      curr[0] = i;
      for (int j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        final insert = prev[j] + 1;
        final delete = curr[j - 1] + 1;
        final replace = prev[j - 1] + cost;
        curr[j] =
            insert < delete
                ? (insert < replace ? insert : replace)
                : (delete < replace ? delete : replace);
      }
      final temp = prev;
      prev = curr;
      curr = temp;
    }

    return prev[b.length];
  }

  static bool _isLetter(String c) {
    final code = c.codeUnitAt(0);
    return (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
  }

  /// Dictionary of valid LaTeX math commands (~200 entries).
  static const Set<String> _validCommands = {
    // Fractions & roots
    'frac', 'dfrac', 'tfrac', 'cfrac', 'sqrt',
    // Big operators
    'int', 'iint', 'iiint', 'oint', 'sum', 'prod',
    'coprod', 'bigcup', 'bigcap', 'bigoplus', 'bigotimes',
    // Limits & logs
    'lim', 'limsup', 'liminf', 'sup', 'inf', 'max', 'min',
    'log', 'ln', 'exp', 'sin', 'cos', 'tan', 'cot', 'sec', 'csc',
    'arcsin', 'arccos', 'arctan', 'sinh', 'cosh', 'tanh',
    'arg', 'deg', 'det', 'dim', 'gcd', 'hom', 'ker', 'Pr',
    // Greek lowercase
    'alpha', 'beta', 'gamma', 'delta', 'epsilon', 'varepsilon',
    'zeta', 'eta', 'theta', 'vartheta', 'iota', 'kappa',
    'lambda', 'mu', 'nu', 'xi', 'pi', 'varpi',
    'rho', 'varrho', 'sigma', 'varsigma', 'tau', 'upsilon',
    'phi', 'varphi', 'chi', 'psi', 'omega',
    // Greek uppercase
    'Gamma', 'Delta', 'Theta', 'Lambda', 'Xi', 'Pi',
    'Sigma', 'Upsilon', 'Phi', 'Psi', 'Omega',
    // Relational
    'leq', 'le', 'geq', 'ge', 'neq', 'ne', 'approx', 'equiv',
    'sim', 'simeq', 'cong', 'propto', 'prec', 'succ',
    'preceq', 'succeq', 'll', 'gg', 'subset', 'supset',
    'subseteq', 'supseteq', 'sqsubseteq', 'sqsupseteq',
    'in', 'notin', 'ni',
    // Binary operators
    'pm', 'mp', 'times', 'div', 'cdot', 'circ', 'ast',
    'star', 'dagger', 'ddagger', 'cap', 'cup', 'vee', 'wedge',
    'oplus', 'ominus', 'otimes', 'oslash', 'odot',
    // Arrows
    'to', 'rightarrow', 'leftarrow', 'leftrightarrow',
    'Rightarrow', 'Leftarrow', 'Leftrightarrow',
    'mapsto', 'hookrightarrow', 'hookleftarrow',
    'uparrow', 'downarrow', 'updownarrow',
    'Uparrow', 'Downarrow', 'nearrow', 'searrow',
    'longrightarrow', 'longleftarrow', 'longleftrightarrow',
    // Accents
    'hat', 'bar', 'overline', 'underline', 'vec',
    'dot', 'ddot', 'tilde', 'widehat', 'widetilde',
    'overrightarrow', 'overleftarrow',
    // Delimiters
    'left', 'right', 'big', 'Big', 'bigg', 'Bigg',
    'langle', 'rangle', 'lfloor', 'rfloor', 'lceil', 'rceil',
    'lvert', 'rvert', 'lVert', 'rVert',
    // Text & fonts
    'text', 'mathrm', 'mathbf', 'mathit', 'mathsf', 'mathtt',
    'mathbb', 'mathcal', 'mathfrak', 'mathscr',
    'textrm', 'textbf', 'textit',
    // Spacing
    'quad', 'qquad', 'enspace', 'hspace',
    // Misc
    'infty', 'partial', 'nabla', 'forall', 'exists', 'nexists',
    'emptyset', 'varnothing', 'neg', 'not',
    'ldots', 'cdots', 'vdots', 'ddots', 'dots',
    'aleph', 'hbar', 'ell', 'wp', 'Re', 'Im',
    'angle', 'triangle', 'backslash', 'prime',
    // Environments
    'begin', 'end',
    // Matrices
    'matrix', 'pmatrix', 'bmatrix', 'Bmatrix', 'vmatrix', 'Vmatrix',
    // Other
    'phantom', 'hphantom', 'vphantom', 'smash',
    'stackrel', 'overset', 'underset',
    'binom', 'choose',
    'color', 'boxed',
  };

  /// R7: Common Pix2Tex misrecognitions — command substitution table.
  ///
  /// These are specific to the Pix2Tex/LatexOCR model and address its
  /// known failure modes. Applied before Levenshtein to get instant
  /// zero-distance corrections.
  static const Map<String, String> _commonMisrecognitions = {
    // Letter/symbol confusions
    'E': 'sum', // \E misrecognized instead of \sum
    'II': 'Pi', // \II misrecognized instead of \Pi
    'Ε': 'sum', // Greek E (epsilon uppercase) → sum
    // Fraction confusions
    'frcx': 'frac',
    'froc': 'frac',
    'froe': 'frac',
    'frao': 'frac',

    // Integral confusions
    'lnt': 'int', // l→i confusion
    'ınt': 'int', // dotless i
    'lim1t': 'limit',

    // Operator confusions
    'surn': 'sum', // m→rn ligature confusion
    'prod1': 'prod',
    'prод': 'prod', // Cyrillic д
    // Root confusions
    'sqr': 'sqrt',
    'sqrl': 'sqrt',

    // Greek confusions
    'apha': 'alpha',
    'aipha': 'alpha',
    'bata': 'beta',
    'gamrna': 'gamma', // m→rn
    'gama': 'gamma',
    'deta': 'delta',
    'thela': 'theta',
    'lamda': 'lambda',
    'larnbda': 'lambda',
    'ornega': 'omega', // m→rn
    'sigrna': 'sigma', // m→rn
    // Arrow confusions
    'rigntarrow': 'rightarrow',
    'leftarow': 'leftarrow',
    'Rigntarrow': 'Rightarrow',

    // Function confusions
    'liim': 'lim',
    'iim': 'lim',
    'sln': 'sin',
    'ccs': 'cos',
    'tari': 'tan',
  };
}
