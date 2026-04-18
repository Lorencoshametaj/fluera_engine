/// 🏷️ TEXT LABEL PICKER — shared heuristic to pick a short, readable label
/// from handwriting text.
///
/// Used by both [ZoneLabeler] (macro-regions) and the monument rendering
/// layer in KnowledgeFlowPainter (individual landmarks). Keeping the logic
/// in one place avoids the historical drift where the two layers used
/// different tokenizers and produced incoherent labels (e.g. zone =
/// "FOTOSINTESI" but monument = "LA DEFINIZIONE DI").
///
/// Algorithm (single text):
///   1. Tokenize on whitespace.
///   2. Normalize: lowercase, strip non-word punctuation (keep accents).
///   3. Drop tokens shorter than 3 chars, pure numerics, and stopwords.
///   4. Return the first N significant tokens joined, capped at [maxChars].
///
/// Algorithm (multi-text, frequency-weighted):
///   1. Run single-text step 1-3 across every input.
///   2. Build a frequency map.
///   3. Return the highest-frequency token (ties: insertion order).
class TextLabelPicker {
  /// Minimum number of characters for a token to be considered significant.
  static const int minTokenChars = 3;

  /// Default maximum characters in the returned label before truncation.
  static const int defaultMaxChars = 22;

  /// Italian + English stopword set. Intentionally small so domain terms
  /// don't get stripped (e.g. "stato" is a physics term, not filtered).
  /// Override via [stopwords] on the public entry points.
  static const Set<String> defaultStopwords = {
    // Italian
    'il', 'lo', 'la', 'i', 'gli', 'le',
    'un', 'uno', 'una',
    'di', 'da', 'in', 'con', 'su', 'per', 'tra', 'fra',
    'del', 'dello', 'della', 'dei', 'degli', 'delle',
    'al', 'allo', 'alla', 'ai', 'agli', 'alle',
    'nel', 'nello', 'nella', 'nei', 'negli', 'nelle',
    'dal', 'dallo', 'dalla', 'dai', 'dagli', 'dalle',
    'sul', 'sullo', 'sulla', 'sui', 'sugli', 'sulle',
    'ed', 'ma', 'se', 'che', 'chi', 'cui', 'non',
    'è', 'sono', 'era', 'erano', 'essere', 'avere', 'ha', 'hanno',
    'si', 'ci', 'vi', 'mi', 'ti',
    'questo', 'questa', 'questi', 'queste', 'quello', 'quella',
    // English (dedup with Italian above)
    'the', 'an', 'and', 'or', 'but', 'of', 'to', 'on', 'at',
    'for', 'with', 'by', 'from', 'are', 'was', 'were', 'be', 'been',
    'have', 'had', 'do', 'does', 'did', 'it', 'its', 'this', 'that',
    // Single chars that survive the length filter in some scripts
    'a', 'e',
    // LaTeX macro noise — when the student writes math, MyScript's text
    // mode may output "\begin{aligned}...\end{aligned}" which the tokenizer
    // strips to "beginaligned"/"endaligned"/etc. These are markup, not
    // content — filter them so monument/zone labels surface the actual
    // formula subject (e.g. "DERIVATA" instead of "BEGINALIGNED").
    //
    // Intentionally EXCLUDED from this set: Greek-letter command names
    // (`alpha`, `beta`, `gamma`, `delta`, `lambda`, `omega`, ...) — they
    // are legitimate pedagogical labels ("Alpha particles", "Beta decay").
    // Also excluded: common words like "text", "left", "right", "sum",
    // "int", "frac" that collide with domain vocabulary.
    'begin', 'end', 'aligned', 'alignedat', 'bmatrix', 'pmatrix',
    'cases', 'array', 'equation', 'split',
    'cdot', 'mathrm', 'mathbf', 'mathit', 'mathcal',
    // String artifacts from stripping \{}:
    'beginaligned', 'endaligned',
  };

  /// Extract significant tokens from a single text blob.
  ///
  /// Returns lowercased tokens in input order. Numerics and stopwords
  /// are dropped. Tokens shorter than [minTokenChars] are dropped.
  ///
  /// Splits on any non-word character (whitespace, braces, backslashes,
  /// parentheses, punctuation). This is critical for LaTeX-style input:
  /// `\mathrm{const}` must tokenize as `['mathrm', 'const']` so the
  /// stopword filter can strip `mathrm` without the content word `const`
  /// getting absorbed into a concatenated junk token.
  static List<String> tokenize(
    String text, {
    Set<String> stopwords = defaultStopwords,
  }) {
    if (text.isEmpty) return const [];
    final splitter =
        RegExp(r'[^\wàèéìòùâêîôûäëïöü]+', unicode: true);
    final out = <String>[];
    for (final raw in text.split(splitter)) {
      if (raw.isEmpty) continue;
      final token = raw.toLowerCase();
      if (token.length < minTokenChars) continue;
      if (stopwords.contains(token)) continue;
      if (RegExp(r'^[0-9]+$').hasMatch(token)) continue;
      out.add(token);
    }
    return out;
  }

  /// Pick a short label from a *single* handwriting blob.
  ///
  /// Joins up to [maxWords] significant tokens, title-cased, truncated
  /// at [maxChars] with an ellipsis. Returns empty string if no
  /// significant tokens are found.
  static String pickFromSingle(
    String text, {
    int maxWords = 3,
    int maxChars = defaultMaxChars,
    Set<String> stopwords = defaultStopwords,
  }) {
    final tokens = tokenize(text, stopwords: stopwords);
    if (tokens.isEmpty) return '';

    final buf = StringBuffer();
    for (final t in tokens.take(maxWords)) {
      final candidate = buf.isEmpty ? _titleCase(t) : '${buf.toString()} $t';
      if (candidate.length > maxChars) break;
      buf
        ..clear()
        ..write(candidate);
    }
    // If the very first significant token already exceeds maxChars,
    // truncate it rather than return empty — a single long word is still
    // a meaningful label to the student.
    if (buf.isEmpty) {
      final first = _titleCase(tokens.first);
      return first.length > maxChars
          ? '${first.substring(0, maxChars - 1)}…'
          : first;
    }
    final result = buf.toString();
    if (result.length > maxChars) {
      return '${result.substring(0, maxChars - 1)}…';
    }
    return result;
  }

  /// Pick a label from *many* text blobs using frequency voting.
  ///
  /// The single most frequent significant token wins. Ties broken by
  /// insertion order (deterministic). Returns title-cased, truncated.
  static String pickFromMany(
    Iterable<String> texts, {
    int maxChars = defaultMaxChars,
    Set<String> stopwords = defaultStopwords,
  }) {
    final freq = <String, int>{};
    String? firstSignificant;
    for (final text in texts) {
      for (final token in tokenize(text, stopwords: stopwords)) {
        freq[token] = (freq[token] ?? 0) + 1;
        firstSignificant ??= token;
      }
    }
    if (freq.isEmpty) {
      return firstSignificant == null ? '' : _titleCase(firstSignificant);
    }

    String best = freq.keys.first;
    int bestCount = freq[best]!;
    for (final e in freq.entries) {
      if (e.value > bestCount) {
        best = e.key;
        bestCount = e.value;
      }
    }

    final titled = _titleCase(best);
    if (titled.length > maxChars) {
      return '${titled.substring(0, maxChars - 1)}…';
    }
    return titled;
  }

  static String _titleCase(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
