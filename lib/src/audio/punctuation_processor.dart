// =============================================================================

// =============================================================================
// ✏️ PUNCTUATION PROCESSOR
//
// Rule-based automatic punctuation for streaming transcription output.
// Inserts periods, commas, question/exclamation marks, and capitalizes
// sentences. Supports English and Italian patterns.
//
// Pipeline: raw text → normalize → detect sentence type → insert punctuation
//           → capitalize → clean up spacing
// =============================================================================

/// Automatic punctuation post-processor for streaming ASR output.
///
/// Usage:
/// ```dart
/// final processor = PunctuationProcessor();
///
/// // On endpoint (utterance boundary) — insert sentence-ending punctuation:
/// final punctuated = processor.onEndpoint('how are you doing today');
/// // → "How are you doing today?"
///
/// // On partial result — capitalize first letter:
/// final partial = processor.onPartial('hello world');
/// // → "Hello world"
/// ```
class PunctuationProcessor {
  /// Accumulated finalized sentences (with punctuation).
  final StringBuffer _committed = StringBuffer();

  /// Whether the next text should be capitalized (start of new sentence).
  bool _capitalizeNext = true;

  /// Reset the processor state (e.g., when starting a new recording).
  void reset() {
    _committed.clear();
    _capitalizeNext = true;
  }

  /// Process a partial (in-progress) result from the recognizer.
  /// Only applies capitalization — no sentence-ending punctuation.
  String onPartial(String text) {
    if (text.isEmpty) return text;
    return _capitalizeNext ? _capitalizeFirst(text) : text;
  }

  /// Process a finalized utterance (endpoint detected by recognizer).
  /// Applies full punctuation pipeline: detect type → punctuate → capitalize.
  String onEndpoint(String text) {
    if (text.trim().isEmpty) return '';

    var processed = text.trim();

    // ─── Step 1: Detect sentence type ───
    final type = _detectSentenceType(processed);

    // ─── Step 2: Remove existing trailing punctuation (model artifacts) ───
    processed = _stripTrailingPunctuation(processed);

    // ─── Step 3: Insert appropriate punctuation ───
    switch (type) {
      case _SentenceType.question:
        processed = '$processed?';
        break;
      case _SentenceType.exclamation:
        processed = '$processed!';
        break;
      case _SentenceType.comma:
        processed = '$processed,';
        break;
      case _SentenceType.statement:
        processed = '$processed.';
        break;
    }

    // ─── Step 4: Capitalize ───
    if (_capitalizeNext) {
      processed = _capitalizeFirst(processed);
    }

    // ─── Step 5: Update state ───
    // Next text should be capitalized if we ended with sentence-ending punct
    _capitalizeNext = type != _SentenceType.comma;

    // Commit
    _committed.write('$processed ');

    return processed;
  }

  /// Get the full committed text so far.
  String get committedText => _committed.toString();

  // ===========================================================================
  // 🔍 Sentence Type Detection
  // ===========================================================================

  _SentenceType _detectSentenceType(String text) {
    final lower = text.toLowerCase().trim();
    final words = lower.split(RegExp(r'\s+'));
    if (words.isEmpty) return _SentenceType.statement;

    final firstWord = words.first;
    final lastWord = words.last;

    // ─── Question Detection ───

    // English question words at start
    if (_enQuestionStarters.contains(firstWord)) {
      return _SentenceType.question;
    }

    // Italian question words at start
    if (_itQuestionStarters.contains(firstWord)) {
      return _SentenceType.question;
    }

    // Multi-word question patterns (EN)
    for (final pattern in _enQuestionPatterns) {
      if (lower.startsWith(pattern)) {
        return _SentenceType.question;
      }
    }

    // Multi-word question patterns (IT)
    for (final pattern in _itQuestionPatterns) {
      if (lower.startsWith(pattern)) {
        return _SentenceType.question;
      }
    }

    // Tag questions (EN): "...right?", "...isn't it?"
    for (final tag in _enTagQuestions) {
      if (lower.endsWith(tag)) {
        return _SentenceType.question;
      }
    }

    // Italian tag questions: "...no?", "...vero?", "...giusto?"
    for (final tag in _itTagQuestions) {
      if (lower.endsWith(tag)) {
        return _SentenceType.question;
      }
    }

    // ─── Exclamation Detection ───

    // English exclamation words
    if (_enExclamationWords.contains(firstWord) ||
        _enExclamationWords.contains(lastWord)) {
      return _SentenceType.exclamation;
    }

    // Italian exclamation words
    if (_itExclamationWords.contains(firstWord) ||
        _itExclamationWords.contains(lastWord)) {
      return _SentenceType.exclamation;
    }

    // Multi-word exclamation patterns
    for (final pattern in _exclamationPatterns) {
      if (lower.contains(pattern)) {
        return _SentenceType.exclamation;
      }
    }

    // ─── Comma Detection (short phrases, likely incomplete) ───
    // Very short utterances followed by more speech often need commas
    if (words.length <= 2 && !_isCompleteSentence(lower)) {
      return _SentenceType.comma;
    }

    // Conjunction endings (likely clause boundary, not sentence end)
    if (_conjunctionEndings.contains(lastWord)) {
      return _SentenceType.comma;
    }

    return _SentenceType.statement;
  }

  /// Check if a short phrase is a complete sentence vs a clause fragment.
  bool _isCompleteSentence(String lower) {
    // Common complete short utterances
    const completePhrases = {
      'yes', 'no', 'ok', 'okay', 'sure', 'thanks', 'thank you',
      'hello', 'hi', 'bye', 'goodbye', 'please', 'sorry', 'wow',
      // Italian
      'sì', 'certo', 'grazie', 'prego',
      'ciao', 'arrivederci', 'scusa', 'perfetto', 'esatto',
      'bene', 'benissimo', 'va bene', 'dai',
    };
    return completePhrases.contains(lower);
  }

  // ===========================================================================
  // 📚 Pattern Dictionaries
  // ===========================================================================

  // English question starters
  static const _enQuestionStarters = {
    'what', 'where', 'when', 'why', 'who', 'whom', 'which',
    'how', 'whose', 'whichever', 'wherever', 'whatever',
  };

  // Italian question starters
  static const _itQuestionStarters = {
    'che', 'cosa', 'come', 'dove', 'quando', 'perché',
    'chi', 'quale', 'quali', 'quanto', 'quanta',
    'quanti', 'quante',
  };

  // English multi-word question patterns
  static const _enQuestionPatterns = [
    'is there', 'is it', 'is this', 'is that',
    'are you', 'are we', 'are they', 'are there',
    'do you', 'do we', 'do they', 'does it', 'does he', 'does she',
    'did you', 'did we', 'did they', 'did it',
    'can you', 'can we', 'can i', 'can they',
    'could you', 'could we', 'could i',
    'would you', 'would it', 'would we',
    'will you', 'will it', 'will we', 'will they',
    'should i', 'should we', 'should they',
    'have you', 'have we', 'have they', 'has it',
    'was it', 'was there', 'were you', 'were they',
    'shall we', 'shall i',
  ];

  // Italian multi-word question patterns
  static const _itQuestionPatterns = [
    'è vero che', 'è possibile', 'è giusto',
    'ci sono', 'c\'è',
    'puoi', 'posso', 'possiamo', 'potete',
    'hai', 'avete', 'abbiamo',
    'sai', 'sapete', 'sappiamo',
    'vuoi', 'volete', 'vogliamo',
    'ti piace', 'vi piace',
    'non è', 'non credi',
    'ma come', 'ma dove', 'ma quando', 'ma perché',
  ];

  // English tag questions
  static const _enTagQuestions = [
    'right', 'correct', 'isn\'t it', 'aren\'t you',
    'don\'t you', 'doesn\'t it', 'won\'t you',
    'can\'t you', 'didn\'t you', 'haven\'t you',
    'wasn\'t it', 'weren\'t they', 'isn\'t that right',
  ];

  // Italian tag questions
  static const _itTagQuestions = [
    'no', 'vero', 'giusto', 'capito',
    'non è vero', 'o no', 'oppure no',
    'non credi', 'non pensi', 'non trovi',
    'sì o no', 'dico bene',
  ];

  // English exclamation words
  static const _enExclamationWords = {
    'wow', 'amazing', 'incredible', 'awesome', 'fantastic',
    'great', 'wonderful', 'excellent', 'brilliant', 'perfect',
    'oh', 'aha', 'yay', 'hooray', 'hurray', 'damn', 'gosh',
    'congratulations', 'bravo', 'brava', 'stop', 'wait',
    'look', 'listen', 'help', 'watch',
  };

  // Italian exclamation words
  static const _itExclamationWords = {
    'fantastico', 'incredibile', 'meraviglioso', 'eccellente',
    'perfetto', 'bellissimo', 'stupendo', 'magnifico',
    'bravo', 'brava', 'bravissimo', 'complimenti',
    'dai', 'forza', 'evviva', 'accidenti',
    'cavolo', 'mamma', 'oddio', 'madonna',
    'guarda', 'ascolta', 'aiuto', 'attento', 'attenta',
    'basta', 'smettila', 'fermati',
  };

  // Multi-word exclamation patterns
  static const _exclamationPatterns = [
    'oh my god', 'oh my gosh', 'no way', 'i can\'t believe',
    'what a', 'how beautiful', 'how wonderful',
    // Italian
    'che bello', 'che bella', 'mamma mia', 'non ci credo',
    'non è possibile', 'ma dai', 'ma va', 'porca miseria',
    'che meraviglia', 'che spettacolo',
  ];

  // Conjunction endings (clause boundary, not sentence end)
  static const _conjunctionEndings = {
    'and', 'but', 'or', 'so', 'because', 'since', 'while',
    'although', 'though', 'however', 'therefore', 'moreover',
    'furthermore', 'also', 'then', 'yet',
    // Italian
    'e', 'ma', 'o', 'oppure', 'quindi', 'perché', 'poiché',
    'mentre', 'anche', 'inoltre', 'però', 'dunque',
    'allora', 'poi', 'anzi', 'eppure',
  };

  // ===========================================================================
  // 🔧 Utility Methods
  // ===========================================================================

  /// Capitalize the first letter of a string.
  String _capitalizeFirst(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }

  /// Strip trailing punctuation characters.
  String _stripTrailingPunctuation(String text) {
    return text.replaceAll(RegExp(r'[.!?,;:]+$'), '').trimRight();
  }
}

/// Internal sentence type classification.
enum _SentenceType {
  statement,
  question,
  exclamation,
  comma,
}
