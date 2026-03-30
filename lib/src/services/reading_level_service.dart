import 'dart:math' as math;

// =============================================================================
// 📊 READING LEVEL SERVICE — Readability analysis for handwritten notes
//
// Multi-formula readability analysis:
//  - Flesch Reading Ease (EN, universal)
//  - Flesch-Kincaid Grade Level (US school grades)
//  - Gulpease Index (Italian-specific)
//  - Automated Readability Index (ARI)
//
// Supports all languages via syllable counting heuristics.
// Optimized for OCR text from handwritten notes (tolerates fragments).
// =============================================================================

/// Reading difficulty level — human-friendly category.
enum ReadingDifficulty {
  veryEasy,    // Elementary school / A1
  easy,        // Middle school / A2
  moderate,    // High school / B1
  difficult,   // University / B2-C1
  veryDifficult, // Academic / C2+
}

/// Complete readability analysis result.
class ReadingLevelResult {
  /// Flesch Reading Ease score (0–100, higher = easier).
  final double fleschReadingEase;

  /// Flesch-Kincaid Grade Level (US school grade).
  final double fleschKincaidGrade;

  /// Gulpease Index (Italian, 0–100, higher = easier).
  final double gulpease;

  /// Automated Readability Index (US grade level).
  final double ari;

  /// Human-friendly difficulty category.
  final ReadingDifficulty difficulty;

  /// Text statistics.
  final int wordCount;
  final int sentenceCount;
  final int syllableCount;
  final int characterCount;
  final double avgWordsPerSentence;
  final double avgSyllablesPerWord;
  final double avgCharactersPerWord;

  /// Detected language code.
  final String languageCode;

  const ReadingLevelResult({
    required this.fleschReadingEase,
    required this.fleschKincaidGrade,
    required this.gulpease,
    required this.ari,
    required this.difficulty,
    required this.wordCount,
    required this.sentenceCount,
    required this.syllableCount,
    required this.characterCount,
    required this.avgWordsPerSentence,
    required this.avgSyllablesPerWord,
    required this.avgCharactersPerWord,
    required this.languageCode,
  });

  /// Human-readable difficulty label.
  String get difficultyLabel => switch (difficulty) {
    ReadingDifficulty.veryEasy => 'Very Easy',
    ReadingDifficulty.easy => 'Easy',
    ReadingDifficulty.moderate => 'Moderate',
    ReadingDifficulty.difficult => 'Difficult',
    ReadingDifficulty.veryDifficult => 'Very Difficult',
  };

  /// Emoji for difficulty.
  String get difficultyEmoji => switch (difficulty) {
    ReadingDifficulty.veryEasy => '🟢',
    ReadingDifficulty.easy => '🟡',
    ReadingDifficulty.moderate => '🟠',
    ReadingDifficulty.difficult => '🔴',
    ReadingDifficulty.veryDifficult => '⛔',
  };

  /// Grade label (e.g., "Grade 5", "University").
  String get gradeLabel {
    final grade = fleschKincaidGrade.round();
    if (grade <= 5) return 'Grade $grade';
    if (grade <= 8) return 'Middle School';
    if (grade <= 12) return 'High School';
    if (grade <= 16) return 'University';
    return 'Post-Graduate';
  }

  /// Localized difficulty label (Italian).
  String get difficultyLabelIT => switch (difficulty) {
    ReadingDifficulty.veryEasy => 'Molto Facile',
    ReadingDifficulty.easy => 'Facile',
    ReadingDifficulty.moderate => 'Moderato',
    ReadingDifficulty.difficult => 'Difficile',
    ReadingDifficulty.veryDifficult => 'Molto Difficile',
  };

  /// Localized grade label (Italian).
  String get gradeLabelIT {
    final grade = fleschKincaidGrade.round();
    if (grade <= 5) return 'Elementare';
    if (grade <= 8) return 'Medie';
    if (grade <= 13) return 'Superiori';
    if (grade <= 17) return 'Università';
    return 'Post-Laurea';
  }
}

// ── Service ──────────────────────────────────────────────────────────────

class ReadingLevelService {
  ReadingLevelService._();
  static final ReadingLevelService instance = ReadingLevelService._();

  /// Analyze text readability.
  ReadingLevelResult analyze(String text, {String languageCode = 'en'}) {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return _emptyResult(languageCode);

    // ── Extract statistics ──
    final words = _extractWords(cleanText);
    final sentences = _extractSentences(cleanText);

    final wordCount = words.length;
    final sentenceCount = math.max(sentences.length, 1);
    final syllableCount = words.fold<int>(
      0, (sum, w) => sum + _countSyllables(w, languageCode),
    );
    final characterCount = words.fold<int>(0, (sum, w) => sum + w.length);

    if (wordCount == 0) return _emptyResult(languageCode);

    // ── Derived stats ──
    final avgWordsPerSentence = wordCount / sentenceCount;
    final avgSyllablesPerWord = syllableCount / wordCount;
    final avgCharsPerWord = characterCount / wordCount;

    // ── Flesch Reading Ease ──
    // 206.835 − 1.015 × (words/sentences) − 84.6 × (syllables/words)
    final fre = 206.835 -
        (1.015 * avgWordsPerSentence) -
        (84.6 * avgSyllablesPerWord);
    final fleschReadingEase = fre.clamp(0.0, 100.0);

    // ── Flesch-Kincaid Grade Level ──
    // 0.39 × (words/sentences) + 11.8 × (syllables/words) − 15.59
    final fkgl = (0.39 * avgWordsPerSentence) +
        (11.8 * avgSyllablesPerWord) -
        15.59;
    final fleschKincaidGrade = math.max(0.0, fkgl);

    // ── Gulpease (Italian) ──
    // 89 + (300 × sentences − 10 × chars) / words
    final gulp = 89.0 +
        ((300.0 * sentenceCount) - (10.0 * characterCount)) / wordCount;
    final gulpease = gulp.clamp(0.0, 100.0);

    // ── Automated Readability Index ──
    // 4.71 × (chars/words) + 0.5 × (words/sentences) − 21.43
    final ariVal = (4.71 * avgCharsPerWord) +
        (0.5 * avgWordsPerSentence) -
        21.43;
    final ari = math.max(0.0, ariVal);

    // ── Determine difficulty ──
    final difficulty = _classifyDifficulty(
      fleschReadingEase,
      gulpease,
      languageCode,
    );

    return ReadingLevelResult(
      fleschReadingEase: double.parse(fleschReadingEase.toStringAsFixed(1)),
      fleschKincaidGrade: double.parse(fleschKincaidGrade.toStringAsFixed(1)),
      gulpease: double.parse(gulpease.toStringAsFixed(1)),
      ari: double.parse(ari.toStringAsFixed(1)),
      difficulty: difficulty,
      wordCount: wordCount,
      sentenceCount: sentenceCount,
      syllableCount: syllableCount,
      characterCount: characterCount,
      avgWordsPerSentence:
          double.parse(avgWordsPerSentence.toStringAsFixed(1)),
      avgSyllablesPerWord:
          double.parse(avgSyllablesPerWord.toStringAsFixed(1)),
      avgCharactersPerWord:
          double.parse(avgCharsPerWord.toStringAsFixed(1)),
      languageCode: languageCode,
    );
  }

  // ── Text Extraction ────────────────────────────────────────────────────

  /// Extract words from text (handles OCR noise).
  List<String> _extractWords(String text) {
    return RegExp(r'[\p{L}\p{N}]+', unicode: true)
        .allMatches(text)
        .map((m) => m.group(0)!)
        .where((w) => w.length > 1 || RegExp(r'[aeiouAEIOU]').hasMatch(w))
        .toList();
  }

  /// Extract sentences (split on .!?:; and newlines).
  List<String> _extractSentences(String text) {
    final sentences = text
        .split(RegExp(r'[.!?;]+\s*|\n\s*\n'))
        .where((s) => s.trim().isNotEmpty)
        .toList();
    return sentences.isEmpty ? [text] : sentences;
  }

  // ── Syllable Counting ──────────────────────────────────────────────────

  /// Count syllables in a word (language-aware heuristic).
  int _countSyllables(String word, String languageCode) {
    final lower = word.toLowerCase();
    if (lower.length <= 2) return 1;

    return switch (languageCode) {
      'it' => _countSyllablesIT(lower),
      'es' || 'pt' => _countSyllablesRomance(lower),
      'de' || 'nl' => _countSyllablesGermanic(lower),
      'fr' => _countSyllablesFR(lower),
      _ => _countSyllablesEN(lower),
    };
  }

  /// English syllable counting (adapted from Hyphenator algorithm).
  int _countSyllablesEN(String word) {
    if (word.length <= 3) return 1;

    var count = 0;
    var prevVowel = false;
    const vowels = {'a', 'e', 'i', 'o', 'u', 'y'};

    for (int i = 0; i < word.length; i++) {
      final isVowel = vowels.contains(word[i]);
      if (isVowel && !prevVowel) count++;
      prevVowel = isVowel;
    }

    // Silent e
    if (word.endsWith('e') && !word.endsWith('le') && count > 1) count--;

    // -ed ending
    if (word.endsWith('ed') && count > 1) count--;

    return math.max(count, 1);
  }

  /// Italian syllable counting.
  int _countSyllablesIT(String word) {
    if (word.length <= 3) return 1;

    var count = 0;
    var prevVowel = false;
    const vowels = {'a', 'e', 'i', 'o', 'u', 'à', 'è', 'é', 'ì', 'ò', 'ù'};

    for (int i = 0; i < word.length; i++) {
      final isVowel = vowels.contains(word[i]);
      if (isVowel && !prevVowel) count++;
      prevVowel = isVowel;
    }

    return math.max(count, 1);
  }

  /// French syllable counting.
  int _countSyllablesFR(String word) {
    if (word.length <= 3) return 1;

    var count = 0;
    var prevVowel = false;
    const vowels = {
      'a', 'e', 'i', 'o', 'u', 'y',
      'à', 'â', 'é', 'è', 'ê', 'ë',
      'î', 'ï', 'ô', 'ù', 'û', 'ü', 'ÿ',
    };

    for (int i = 0; i < word.length; i++) {
      final isVowel = vowels.contains(word[i]);
      if (isVowel && !prevVowel) count++;
      prevVowel = isVowel;
    }

    // Silent final e in French
    if (word.endsWith('e') && !word.endsWith('é') && count > 1) count--;
    if (word.endsWith('es') && count > 1) count--;
    if (word.endsWith('ent') && count > 1) count--;

    return math.max(count, 1);
  }

  /// Romance language syllable counting (Spanish, Portuguese).
  int _countSyllablesRomance(String word) {
    if (word.length <= 3) return 1;

    var count = 0;
    var prevVowel = false;
    const vowels = {
      'a', 'e', 'i', 'o', 'u',
      'á', 'é', 'í', 'ó', 'ú', 'ã', 'õ', 'â', 'ê', 'ô', 'ü',
    };

    for (int i = 0; i < word.length; i++) {
      final isVowel = vowels.contains(word[i]);
      if (isVowel && !prevVowel) count++;
      prevVowel = isVowel;
    }

    return math.max(count, 1);
  }

  /// Germanic language syllable counting (German, Dutch).
  int _countSyllablesGermanic(String word) {
    if (word.length <= 3) return 1;

    var count = 0;
    var prevVowel = false;
    const vowels = {'a', 'e', 'i', 'o', 'u', 'ä', 'ö', 'ü', 'y'};

    for (int i = 0; i < word.length; i++) {
      final isVowel = vowels.contains(word[i]);
      if (isVowel && !prevVowel) count++;
      prevVowel = isVowel;
    }

    return math.max(count, 1);
  }

  // ── Classification ─────────────────────────────────────────────────────

  ReadingDifficulty _classifyDifficulty(
    double flesch,
    double gulpease,
    String languageCode,
  ) {
    // For Italian, prefer Gulpease
    if (languageCode == 'it') {
      if (gulpease >= 80) return ReadingDifficulty.veryEasy;
      if (gulpease >= 60) return ReadingDifficulty.easy;
      if (gulpease >= 40) return ReadingDifficulty.moderate;
      if (gulpease >= 20) return ReadingDifficulty.difficult;
      return ReadingDifficulty.veryDifficult;
    }

    // For other languages, use Flesch
    if (flesch >= 80) return ReadingDifficulty.veryEasy;
    if (flesch >= 60) return ReadingDifficulty.easy;
    if (flesch >= 40) return ReadingDifficulty.moderate;
    if (flesch >= 20) return ReadingDifficulty.difficult;
    return ReadingDifficulty.veryDifficult;
  }

  // ── Empty result ───────────────────────────────────────────────────────

  ReadingLevelResult _emptyResult(String lang) => ReadingLevelResult(
    fleschReadingEase: 100,
    fleschKincaidGrade: 0,
    gulpease: 100,
    ari: 0,
    difficulty: ReadingDifficulty.veryEasy,
    wordCount: 0,
    sentenceCount: 0,
    syllableCount: 0,
    characterCount: 0,
    avgWordsPerSentence: 0,
    avgSyllablesPerWord: 0,
    avgCharactersPerWord: 0,
    languageCode: lang,
  );
}
