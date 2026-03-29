import 'package:flutter/foundation.dart';
import 'word_completion_dictionary.dart';

// =============================================================================
// 📝 GRAMMAR CHECK SERVICE v2 — Expanded rule-based grammar validation
//
// 20+ rules across 7+ languages with morphological gender inference,
// contraction detection, subject-verb agreement, and more.
// =============================================================================

/// Severity of a grammar error.
enum GrammarSeverity { info, warning, error }

/// A single grammar error with position and correction.
class GrammarError {
  final String message;
  final int startIndex;
  final int endIndex;
  final String? suggestion;
  final GrammarSeverity severity;
  final String ruleId;

  const GrammarError({
    required this.message,
    required this.startIndex,
    required this.endIndex,
    this.suggestion,
    this.severity = GrammarSeverity.warning,
    required this.ruleId,
  });

  @override
  String toString() => 'GrammarError("$message" [$startIndex:$endIndex])';
}

/// Result of grammar checking a text.
class GrammarResult {
  final String text;
  final List<GrammarError> errors;

  const GrammarResult({required this.text, required this.errors});
  bool get hasErrors => errors.isNotEmpty;
}

// =============================================================================
// 📐 GRAMMAR RULES — Abstract base
// =============================================================================

abstract class _GrammarRule {
  String get id;
  Set<DictLanguage> get languages; // empty = universal
  List<GrammarError> check(String text, DictLanguage lang);
  bool appliesTo(DictLanguage lang) =>
      languages.isEmpty || languages.contains(lang);
}

// █████████████████████████████████████████████████████████████████████████████
// UNIVERSAL RULES (all languages)
// █████████████████████████████████████████████████████████████████████████████

/// Detects repeated consecutive words: "the the", "is is"
class _DuplicateWordRule extends _GrammarRule {
  @override String get id => 'duplicate_word';
  @override Set<DictLanguage> get languages => const {};

  @override
  List<GrammarError> check(String text, DictLanguage lang) {
    final errors = <GrammarError>[];
    final pattern = RegExp(r'\b(\w+)\s+\1\b', caseSensitive: false);
    for (final match in pattern.allMatches(text)) {
      final word = match.group(1)!;
      if (_skip.contains(word.toLowerCase())) continue;
      errors.add(GrammarError(
        message: 'Duplicate word: "$word"',
        startIndex: match.start, endIndex: match.end,
        suggestion: word, ruleId: id,
      ));
    }
    return errors;
  }

  static const _skip = {
    'ha', 'bye', 'no', 'so', 'very', 'far', 'bla', 'yeah',
    'cha', 'tick', 'tock', 'bang', 'knock', 'nom', 'muah',
  };
}

/// Missing capitalization after sentence-ending punctuation.
class _SentenceCapitalizationRule extends _GrammarRule {
  @override String get id => 'sentence_capitalization';
  @override Set<DictLanguage> get languages => const {};

  @override
  List<GrammarError> check(String text, DictLanguage lang) {
    final errors = <GrammarError>[];
    final pattern = RegExp(r'[.!?]\s+([a-zà-öø-ÿ])');
    for (final match in pattern.allMatches(text)) {
      final ch = match.group(1)!;
      final idx = match.start + match.group(0)!.indexOf(ch);
      errors.add(GrammarError(
        message: 'Capitalize after sentence end',
        startIndex: idx, endIndex: idx + 1,
        suggestion: ch.toUpperCase(),
        severity: GrammarSeverity.info, ruleId: id,
      ));
    }
    return errors;
  }
}

/// Multiple consecutive spaces.
class _DoubleSpaceRule extends _GrammarRule {
  @override String get id => 'double_space';
  @override Set<DictLanguage> get languages => const {};

  @override
  List<GrammarError> check(String text, DictLanguage lang) {
    final errors = <GrammarError>[];
    for (final m in RegExp(r'  +').allMatches(text)) {
      errors.add(GrammarError(
        message: 'Multiple spaces',
        startIndex: m.start, endIndex: m.end,
        suggestion: ' ', severity: GrammarSeverity.info, ruleId: id,
      ));
    }
    return errors;
  }
}

/// Missing space after punctuation.
class _MissingSpaceAfterPunctuationRule extends _GrammarRule {
  @override String get id => 'missing_space_punctuation';
  @override Set<DictLanguage> get languages => const {};

  @override
  List<GrammarError> check(String text, DictLanguage lang) {
    final errors = <GrammarError>[];
    final pattern = RegExp(r'(?<!\d)[,;]([a-zA-Zà-öø-ÿÀ-ÖØ-Ý])');
    for (final m in pattern.allMatches(text)) {
      errors.add(GrammarError(
        message: 'Missing space after punctuation',
        startIndex: m.start, endIndex: m.end,
        suggestion: '${text[m.start]} ${m.group(1)}',
        severity: GrammarSeverity.info, ruleId: id,
      ));
    }
    return errors;
  }
}

/// Unclosed parentheses, brackets, or quotes.
class _PunctuationPairingRule extends _GrammarRule {
  @override String get id => 'punctuation_pairing';
  @override Set<DictLanguage> get languages => const {};

  @override
  List<GrammarError> check(String text, DictLanguage lang) {
    final errors = <GrammarError>[];
    for (final pair in _pairs) {
      final openCount = text.split(pair.open).length - 1;
      final closeCount = text.split(pair.close).length - 1;
      if (openCount > closeCount) {
        // Find the last unmatched opener
        final lastOpen = text.lastIndexOf(pair.open);
        if (lastOpen >= 0) {
          errors.add(GrammarError(
            message: 'Unclosed "${pair.open}" — add "${pair.close}"',
            startIndex: lastOpen, endIndex: lastOpen + 1,
            suggestion: null,
            severity: GrammarSeverity.info, ruleId: id,
          ));
        }
      } else if (closeCount > openCount) {
        final lastClose = text.lastIndexOf(pair.close);
        if (lastClose >= 0) {
          errors.add(GrammarError(
            message: 'Extra "${pair.close}" without opening "${pair.open}"',
            startIndex: lastClose, endIndex: lastClose + 1,
            suggestion: null,
            severity: GrammarSeverity.info, ruleId: id,
          ));
        }
      }
    }
    return errors;
  }

  static const _pairs = [
    _Pair('(', ')'), _Pair('[', ']'), _Pair('{', '}'),
  ];
}

class _Pair {
  final String open, close;
  const _Pair(this.open, this.close);
}

/// "..." (3+ dots) → "…" (Unicode ellipsis)
class _EllipsisRule extends _GrammarRule {
  @override String get id => 'ellipsis';
  @override Set<DictLanguage> get languages => const {};

  @override
  List<GrammarError> check(String text, DictLanguage lang) {
    final errors = <GrammarError>[];
    for (final m in RegExp(r'\.{3,}').allMatches(text)) {
      errors.add(GrammarError(
        message: 'Use ellipsis character "…"',
        startIndex: m.start, endIndex: m.end,
        suggestion: '…',
        severity: GrammarSeverity.info, ruleId: id,
      ));
    }
    return errors;
  }
}

/// Common typo patterns (language-independent).
class _CommonTypoRule extends _GrammarRule {
  @override String get id => 'common_typo';
  @override Set<DictLanguage> get languages => const {};

  @override
  List<GrammarError> check(String text, DictLanguage lang) {
    final errors = <GrammarError>[];
    final typos = _typosByLang[lang] ?? {};
    final universal = _universalTypos;

    void _scan(Map<String, String> map) {
      for (final entry in map.entries) {
        final pattern = RegExp('\\b${entry.key}\\b', caseSensitive: false);
        for (final m in pattern.allMatches(text)) {
          // Preserve original capitalization
          final suggestion = _capitalizeAs(m.group(0)!, entry.value);
          errors.add(GrammarError(
            message: 'Did you mean "$suggestion"?',
            startIndex: m.start, endIndex: m.end,
            suggestion: suggestion,
            severity: GrammarSeverity.warning, ruleId: id,
          ));
        }
      }
    }

    _scan(universal);
    _scan(typos);
    return errors;
  }

  static String _capitalizeAs(String original, String replacement) {
    if (original.isEmpty || replacement.isEmpty) return replacement;
    if (original[0] == original[0].toUpperCase()) {
      return replacement[0].toUpperCase() + replacement.substring(1);
    }
    return replacement;
  }

  // Typos that apply regardless of language
  static const _universalTypos = <String, String>{
    'teh': 'the', 'adn': 'and', 'fo': 'of', 'hte': 'the',
    'taht': 'that', 'wiht': 'with', 'thier': 'their',
    'recieve': 'receive', 'beleive': 'believe',
    'occured': 'occurred', 'seperate': 'separate',
    'definately': 'definitely', 'accomodate': 'accommodate',
    'occassion': 'occasion', 'neccessary': 'necessary',
    'independant': 'independent', 'wich': 'which',
  };

  // Language-specific common typos
  static const _typosByLang = <DictLanguage, Map<String, String>>{
    DictLanguage.it: {
      'perchè': 'perché', 'piu': 'più', 'gia': 'già',
      'cioe': 'cioè', 'finche': 'finché', 'poiche': 'poiché',
      'affinche': 'affinché', 'benche': 'benché',
      'percio': 'perciò', 'pubblica': 'pubblica',
    },
    DictLanguage.es: {
      'tambien': 'también', 'mas': 'más', 'asi': 'así',
      'dia': 'día', 'aqui': 'aquí', 'despues': 'después',
    },
    DictLanguage.fr: {
      'a cause': 'à cause', 'ca': 'ça', 'deja': 'déjà',
      'voila': 'voilà', 'ou': 'où',
    },
    DictLanguage.de: {
      'das': 'dass', // "das" (article) vs "dass" (conjunction) — only after certain verbs
    },
    DictLanguage.pt: {
      'voce': 'você', 'tambem': 'também', 'e': 'é',
      'so': 'só', 'ate': 'até', 'nos': 'nós',
    },
  };
}

/// Number formatting suggestion.
class _NumberFormattingRule extends _GrammarRule {
  @override String get id => 'number_formatting';
  @override Set<DictLanguage> get languages => const {};

  @override
  List<GrammarError> check(String text, DictLanguage lang) {
    final errors = <GrammarError>[];
    // Match numbers with 4+ digits without separators
    final pattern = RegExp(r'(?<!\d[.,])\b(\d{4,})\b(?![.,]\d)');
    for (final m in pattern.allMatches(text)) {
      final num = m.group(1)!;
      if (num.length < 5) continue; // Skip 4-digit numbers (years like 2024)
      final formatted = _format(num, lang);
      if (formatted != num) {
        errors.add(GrammarError(
          message: 'Consider formatting: $formatted',
          startIndex: m.start, endIndex: m.end,
          suggestion: formatted,
          severity: GrammarSeverity.info, ruleId: id,
        ));
      }
    }
    return errors;
  }

  static String _format(String num, DictLanguage lang) {
    // IT/ES/FR/DE/PT use "." as thousands separator
    // EN uses ","
    final sep = const {
      DictLanguage.en: ',',
    }[lang] ?? '.';
    final buf = StringBuffer();
    final len = num.length;
    for (int i = 0; i < len; i++) {
      if (i > 0 && (len - i) % 3 == 0) buf.write(sep);
      buf.write(num[i]);
    }
    return buf.toString();
  }
}

// █████████████████████████████████████████████████████████████████████████████
// ENGLISH RULES
// █████████████████████████████████████████████████████████████████████████████

/// English confusables: their/there/they're, your/you're, its/it's, a/an
class _EnglishConfusablesRule extends _GrammarRule {
  @override String get id => 'en_confusables';
  @override Set<DictLanguage> get languages => const {DictLanguage.en};

  @override
  List<GrammarError> check(String text, DictLanguage lang) {
    final errors = <GrammarError>[];
    for (final r in _rules) {
      final pat = RegExp(r.pattern, caseSensitive: false);
      for (final m in pat.allMatches(text)) {
        errors.add(GrammarError(
          message: r.message,
          startIndex: m.start, endIndex: m.end,
          suggestion: r.suggestion,
          severity: GrammarSeverity.warning, ruleId: id,
        ));
      }
    }
    return errors;
  }

  static final _rules = [
    _P(r"\byour\s+(are|is|was|were|going|doing|being|coming|leaving|making)\b",
       '"your" → "you\'re" (you are)', "you're"),
    _P(r"\bits\s+(a|an|the|not|been|going|important|necessary|possible|clear)\b",
       '"its" → "it\'s" (it is)', "it's"),
    _P(r"\bthere\s+(own|house|car|parents|children|work|school|friends|books|notes)\b",
       '"there" → "their" (possessive)', "their"),
    _P(r"\b(more|less|better|worse|bigger|smaller|faster|slower|higher|lower|greater|fewer)\s+then\b",
       '"then" → "than" (comparison)', "than"),
    _P(r"\ba\s+([aeiou]\w+)\b",
       '"a" → "an" before vowel', "an"),
  ];
}

/// English contraction detection: "dont" → "don't", "cant" → "can't"
class _EnglishContractionRule extends _GrammarRule {
  @override String get id => 'en_contractions';
  @override Set<DictLanguage> get languages => const {DictLanguage.en};

  @override
  List<GrammarError> check(String text, DictLanguage lang) {
    final errors = <GrammarError>[];
    for (final entry in _contractions.entries) {
      final pat = RegExp('\\b${entry.key}\\b', caseSensitive: false);
      for (final m in pat.allMatches(text)) {
        final original = m.group(0)!;
        // Preserve capitalization
        final fix = original[0] == original[0].toUpperCase()
            ? entry.value[0].toUpperCase() + entry.value.substring(1)
            : entry.value;
        errors.add(GrammarError(
          message: 'Missing apostrophe: "$fix"',
          startIndex: m.start, endIndex: m.end,
          suggestion: fix, ruleId: id,
        ));
      }
    }
    return errors;
  }

  static const _contractions = {
    'dont': "don't", 'cant': "can't", 'wont': "won't",
    'didnt': "didn't", 'doesnt': "doesn't", 'isnt': "isn't",
    'arent': "aren't", 'wasnt': "wasn't", 'werent': "weren't",
    'hasnt': "hasn't", 'havent': "haven't", 'hadnt': "hadn't",
    'wouldnt': "wouldn't", 'couldnt': "couldn't", 'shouldnt': "shouldn't",
    'mustnt': "mustn't", 'neednt': "needn't",
    'im': "I'm", 'ive': "I've", 'ill': "I'll",
    'youre': "you're", 'youve': "you've", 'youll': "you'll",
    'hes': "he's", 'shes': "she's", 'theyre': "they're",
    'theyve': "they've", 'theyll': "they'll",
    'whos': "who's", 'whats': "what's", 'thats': "that's",
    'lets': "let's", 'itll': "it'll", 'wheres': "where's",
  };
}

/// English subject-verb agreement: "He don't" → "He doesn't"
class _EnglishSubjectVerbRule extends _GrammarRule {
  @override String get id => 'en_subject_verb';
  @override Set<DictLanguage> get languages => const {DictLanguage.en};

  @override
  List<GrammarError> check(String text, DictLanguage lang) {
    final errors = <GrammarError>[];
    for (final r in _rules) {
      final pat = RegExp(r.pattern, caseSensitive: false);
      for (final m in pat.allMatches(text)) {
        errors.add(GrammarError(
          message: r.message,
          startIndex: m.start, endIndex: m.end,
          suggestion: r.suggestion, ruleId: id,
        ));
      }
    }
    return errors;
  }

  static final _rules = [
    _P(r"\b(he|she|it)\s+don't\b",
       'Subject-verb: use "doesn\'t" with he/she/it', "doesn't"),
    _P(r"\b(he|she|it)\s+have\b",
       'Subject-verb: use "has" with he/she/it', "has"),
    _P(r"\b(I|we|they|you)\s+has\b",
       'Subject-verb: use "have" with I/we/they/you', "have"),
    _P(r"\b(I|we|they|you)\s+doesn't\b",
       'Subject-verb: use "don\'t" with I/we/they/you', "don't"),
    _P(r"\b(he|she|it)\s+were\b",
       'Subject-verb: use "was" with he/she/it', "was"),
    _P(r"\b(I|we|they|you)\s+was\b",
       'Subject-verb: use "were" with we/they/you', "were"),
  ];
}

// █████████████████████████████████████████████████████████████████████████████
// ROMANCE LANGUAGE RULES (IT, ES, FR, PT)
// With Trie-based morphological gender inference
// █████████████████████████████████████████████████████████████████████████████

/// 🧠 Morphological gender inference — uses word endings to determine gender.
/// Much more scalable than hardcoded noun lists.
class _GenderInference {
  /// Infer likely gender of an Italian noun from its ending.
  /// Returns 'f' for feminine, 'm' for masculine, null for unknown.
  static String? inferItalian(String noun) {
    final lower = noun.toLowerCase();
    // Strong feminine suffixes
    if (lower.endsWith('zione') || lower.endsWith('sione') ||
        lower.endsWith('gione') || lower.endsWith('tà') ||
        lower.endsWith('tù') || lower.endsWith('ezza') ||
        lower.endsWith('enza') || lower.endsWith('anza') ||
        lower.endsWith('ica') || lower.endsWith('ura')) return 'f';
    // Exceptions: words ending in -a that are masculine
    if (_itMascInA.contains(lower)) return 'm';
    // General: -a ending = feminine, -o ending = masculine
    if (lower.endsWith('a')) return 'f';
    if (lower.endsWith('o')) return 'm';
    // -e ending: ambiguous in Italian, use known lists
    if (_itFemInE.contains(lower)) return 'f';
    if (lower.endsWith('mente')) return null; // adverb, not noun
    return null; // Can't determine
  }

  static String? inferSpanish(String noun) {
    final lower = noun.toLowerCase();
    if (lower.endsWith('ción') || lower.endsWith('sión') ||
        lower.endsWith('dad') || lower.endsWith('tad') ||
        lower.endsWith('tud') || lower.endsWith('eza') ||
        lower.endsWith('cia') || lower.endsWith('ura')) return 'f';
    if (_esMascInA.contains(lower)) return 'm';
    if (lower.endsWith('a')) return 'f';
    if (lower.endsWith('o')) return 'm';
    return null;
  }

  static String? inferFrench(String noun) {
    final lower = noun.toLowerCase();
    if (lower.endsWith('tion') || lower.endsWith('sion') ||
        lower.endsWith('ité') || lower.endsWith('ure') ||
        lower.endsWith('ence') || lower.endsWith('ance') ||
        lower.endsWith('esse') || lower.endsWith('ette') ||
        lower.endsWith('elle') || lower.endsWith('ie')) return 'f';
    if (lower.endsWith('ment') || lower.endsWith('isme') ||
        lower.endsWith('age') || lower.endsWith('eur')) return 'm';
    return null;
  }

  static String? inferPortuguese(String noun) {
    final lower = noun.toLowerCase();
    if (lower.endsWith('ção') || lower.endsWith('são') ||
        lower.endsWith('dade') || lower.endsWith('eza') ||
        lower.endsWith('ência') || lower.endsWith('ância')) return 'f';
    if (_ptMascInA.contains(lower)) return 'm';
    if (lower.endsWith('a')) return 'f';
    if (lower.endsWith('o')) return 'm';
    return null;
  }

  // Italian masculine nouns ending in -a (exceptions)
  static const _itMascInA = {
    'problema', 'sistema', 'programma', 'tema', 'cinema', 'panorama',
    'dramma', 'diploma', 'dilemma', 'clima', 'enigma', 'schema',
    'trauma', 'fantasma', 'pigiama', 'papa', 'poeta', 'pianeta',
  };

  // Italian feminine nouns ending in -e
  static const _itFemInE = {
    'notte', 'arte', 'parte', 'mente', 'gente', 'morte',
    'classe', 'lezione', 'stazione', 'nazione', 'informazione',
    'pace', 'luce', 'voce', 'croce', 'neve', 'sede',
    'pelle', 'torre', 'fame', 'sete', 'chiave', 'nave',
    'volpe', 'tigre', 'lepre', 'serie', 'superficie',
    'moglie', 'legge', 'corte', 'fonte', 'sorte',
  };

  // Spanish masculine nouns ending in -a
  static const _esMascInA = {
    'problema', 'sistema', 'programa', 'tema', 'cinema', 'panorama',
    'drama', 'diploma', 'dilema', 'clima', 'enigma', 'esquema',
    'idioma', 'mapa', 'planeta', 'poeta', 'día',
  };

  // Portuguese masculine nouns in -a
  static const _ptMascInA = {
    'problema', 'sistema', 'programa', 'tema', 'cinema', 'panorama',
    'drama', 'diploma', 'dilema', 'clima', 'enigma', 'esquema',
    'idioma', 'mapa', 'planeta', 'poeta', 'dia',
  };
}

/// Italian article-noun agreement using morphological gender inference.
class _ItalianArticleRule extends _GrammarRule {
  @override String get id => 'it_article_agreement';
  @override Set<DictLanguage> get languages => const {DictLanguage.it};

  @override
  List<GrammarError> check(String text, DictLanguage lang) {
    final errors = <GrammarError>[];
    // Match: article + word
    final pattern = RegExp(
      r'\b(il|lo|la|un|uno|una|del|dello|della|nel|nello|nella|al|allo|alla|dal|dallo|dalla|sul|sullo|sulla)\s+(\w+)\b',
      caseSensitive: false,
    );

    for (final m in pattern.allMatches(text)) {
      final article = m.group(1)!.toLowerCase();
      final noun = m.group(2)!;
      final gender = _GenderInference.inferItalian(noun);
      if (gender == null) continue; // Can't determine

      final articleGender = _mascArticles.contains(article) ? 'm' : 'f';
      if (articleGender != gender) {
        final correction = gender == 'f'
            ? _mascToFem[article]
            : _femToMasc[article];
        if (correction != null) {
          errors.add(GrammarError(
            message: 'Concordanza: "$article $noun" → "$correction $noun"',
            startIndex: m.start, endIndex: m.end,
            suggestion: '$correction $noun', ruleId: id,
          ));
        }
      }
    }
    return errors;
  }

  static const _mascArticles = {
    'il', 'lo', 'un', 'uno', 'del', 'dello', 'nel', 'nello',
    'al', 'allo', 'dal', 'dallo', 'sul', 'sullo',
  };

  static const _mascToFem = {
    'il': 'la', 'lo': 'la', 'un': 'una', 'uno': 'una',
    'del': 'della', 'dello': 'della', 'nel': 'nella', 'nello': 'nella',
    'al': 'alla', 'allo': 'alla', 'dal': 'dalla', 'dallo': 'dalla',
    'sul': 'sulla', 'sullo': 'sulla',
  };

  static const _femToMasc = {
    'la': 'il', 'una': 'un', 'della': 'del', 'nella': 'nel',
    'alla': 'al', 'dalla': 'dal', 'sulla': 'sul',
  };
}

/// Spanish article-noun agreement with morphological inference.
class _SpanishArticleRule extends _GrammarRule {
  @override String get id => 'es_article_agreement';
  @override Set<DictLanguage> get languages => const {DictLanguage.es};

  @override
  List<GrammarError> check(String text, DictLanguage lang) {
    final errors = <GrammarError>[];
    final pattern = RegExp(
      r'\b(el|la|un|una|del|de la|al|a la)\s+(\w+)\b',
      caseSensitive: false,
    );
    for (final m in pattern.allMatches(text)) {
      final article = m.group(1)!.toLowerCase();
      final noun = m.group(2)!;
      final gender = _GenderInference.inferSpanish(noun);
      if (gender == null) continue;

      final artGender = _mascArticles.contains(article) ? 'm' : 'f';
      if (artGender != gender) {
        final fix = gender == 'f' ? _mascToFem[article] : _femToMasc[article];
        if (fix != null) {
          errors.add(GrammarError(
            message: 'Concordancia: "$article $noun" → "$fix $noun"',
            startIndex: m.start, endIndex: m.end,
            suggestion: '$fix $noun', ruleId: id,
          ));
        }
      }
    }
    return errors;
  }

  static const _mascArticles = {'el', 'un', 'del', 'al'};
  static const _mascToFem = {'el': 'la', 'un': 'una', 'del': 'de la', 'al': 'a la'};
  static const _femToMasc = {'la': 'el', 'una': 'un', 'de la': 'del', 'a la': 'al'};
}

/// French article-noun agreement with morphological inference.
class _FrenchArticleRule extends _GrammarRule {
  @override String get id => 'fr_article_agreement';
  @override Set<DictLanguage> get languages => const {DictLanguage.fr};

  @override
  List<GrammarError> check(String text, DictLanguage lang) {
    final errors = <GrammarError>[];
    final pattern = RegExp(
      r'\b(le|la|un|une|du|de la|au|à la)\s+(\w+)\b',
      caseSensitive: false,
    );
    for (final m in pattern.allMatches(text)) {
      final article = m.group(1)!.toLowerCase();
      final noun = m.group(2)!;
      final gender = _GenderInference.inferFrench(noun);
      if (gender == null) continue;

      final artGender = _mascArticles.contains(article) ? 'm' : 'f';
      if (artGender != gender) {
        final fix = gender == 'f' ? _mascToFem[article] : _femToMasc[article];
        if (fix != null) {
          errors.add(GrammarError(
            message: 'Accord: "$article $noun" → "$fix $noun"',
            startIndex: m.start, endIndex: m.end,
            suggestion: '$fix $noun', ruleId: id,
          ));
        }
      }
    }
    return errors;
  }

  static const _mascArticles = {'le', 'un', 'du', 'au'};
  static const _mascToFem = {'le': 'la', 'un': 'une', 'du': 'de la', 'au': 'à la'};
  static const _femToMasc = {'la': 'le', 'une': 'un', 'de la': 'du', 'à la': 'au'};
}

// █████████████████████████████████████████████████████████████████████████████
// PORTUGUESE RULES
// █████████████████████████████████████████████████████████████████████████████

/// Portuguese article-noun agreement.
class _PortugueseArticleRule extends _GrammarRule {
  @override String get id => 'pt_article_agreement';
  @override Set<DictLanguage> get languages => const {DictLanguage.pt};

  @override
  List<GrammarError> check(String text, DictLanguage lang) {
    final errors = <GrammarError>[];
    final pattern = RegExp(
      r'\b(o|a|um|uma|do|da|no|na|ao|à)\s+(\w+)\b',
      caseSensitive: false,
    );
    for (final m in pattern.allMatches(text)) {
      final article = m.group(1)!.toLowerCase();
      final noun = m.group(2)!;
      final gender = _GenderInference.inferPortuguese(noun);
      if (gender == null) continue;

      final artGender = _mascArticles.contains(article) ? 'm' : 'f';
      if (artGender != gender) {
        final fix = gender == 'f' ? _mascToFem[article] : _femToMasc[article];
        if (fix != null) {
          errors.add(GrammarError(
            message: 'Concordância: "$article $noun" → "$fix $noun"',
            startIndex: m.start, endIndex: m.end,
            suggestion: '$fix $noun', ruleId: id,
          ));
        }
      }
    }
    return errors;
  }

  static const _mascArticles = {'o', 'um', 'do', 'no', 'ao'};
  static const _mascToFem = {'o': 'a', 'um': 'uma', 'do': 'da', 'no': 'na', 'ao': 'à'};
  static const _femToMasc = {'a': 'o', 'uma': 'um', 'da': 'do', 'na': 'no', 'à': 'ao'};
}

// █████████████████████████████████████████████████████████████████████████████
// DUTCH RULES
// █████████████████████████████████████████████████████████████████████████████

/// Dutch de/het article — uses common neuter (het) word list.
class _DutchArticleRule extends _GrammarRule {
  @override String get id => 'nl_article';
  @override Set<DictLanguage> get languages => const {DictLanguage.nl};

  @override
  List<GrammarError> check(String text, DictLanguage lang) {
    final errors = <GrammarError>[];
    // "de" + het-word
    final pattern = RegExp(r'\bde\s+(\w+)\b', caseSensitive: false);
    for (final m in pattern.allMatches(text)) {
      final noun = m.group(1)!.toLowerCase();
      if (_hetWords.contains(noun)) {
        errors.add(GrammarError(
          message: '"de $noun" → "het $noun"',
          startIndex: m.start, endIndex: m.end,
          suggestion: 'het $noun', ruleId: id,
        ));
      }
    }
    // "het" + de-word (common errors)
    final pattern2 = RegExp(r'\bhet\s+(\w+)\b', caseSensitive: false);
    for (final m in pattern2.allMatches(text)) {
      final noun = m.group(1)!.toLowerCase();
      if (_deWords.contains(noun)) {
        errors.add(GrammarError(
          message: '"het $noun" → "de $noun"',
          startIndex: m.start, endIndex: m.end,
          suggestion: 'de $noun', ruleId: id,
        ));
      }
    }
    return errors;
  }

  // Most common "het" (neuter) words in Dutch
  static const _hetWords = {
    'huis', 'kind', 'boek', 'land', 'water', 'hoofd', 'leven',
    'werk', 'jaar', 'uur', 'aantal', 'begin', 'einde', 'verschil',
    'probleem', 'systeem', 'programma', 'resultaat', 'moment',
    'voorbeeld', 'belang', 'gevoel', 'gedeelte', 'geval',
    'lichaam', 'onderdeel', 'onderzoek', 'verband', 'voordeel',
    'meisje', 'jongetje', 'huisje', 'broodje', 'gebouw',
  };

  // Very common "de" words often confused with het
  static const _deWords = {
    'man', 'vrouw', 'dag', 'week', 'maand', 'stad', 'school',
    'kamer', 'deur', 'tafel', 'stoel', 'straat', 'kerk',
    'tuin', 'auto', 'fiets', 'trein', 'bus', 'brug',
    'vraag', 'brief', 'krant', 'film', 'muziek',
  };
}

// █████████████████████████████████████████████████████████████████████████████
// GERMAN RULES
// █████████████████████████████████████████████████████████████████████████████

/// German noun capitalization.
class _GermanNounCapitalizationRule extends _GrammarRule {
  @override String get id => 'de_noun_capitalization';
  @override Set<DictLanguage> get languages => const {DictLanguage.de};

  @override
  List<GrammarError> check(String text, DictLanguage lang) {
    final errors = <GrammarError>[];
    final pattern = RegExp(
      r'(?<=\s)('
      '${_mustCapitalize.join('|')}'
      r')(?=[\s,.])',
      caseSensitive: true,
    );
    for (final m in pattern.allMatches(text)) {
      final word = m.group(1)!;
      errors.add(GrammarError(
        message: 'German nouns: capitalize "$word"',
        startIndex: m.start, endIndex: m.end,
        suggestion: word[0].toUpperCase() + word.substring(1),
        severity: GrammarSeverity.warning, ruleId: id,
      ));
    }
    return errors;
  }

  static const _mustCapitalize = [
    'haus', 'schule', 'universität', 'stadt', 'land', 'zeit',
    'mensch', 'frau', 'mann', 'kind', 'freund', 'arbeit',
    'welt', 'leben', 'buch', 'beispiel', 'frage', 'antwort',
    'familie', 'sprache', 'geschichte', 'wissenschaft', 'musik',
    'mathematik', 'physik', 'chemie', 'philosophie', 'kunst',
    'regierung', 'gesellschaft', 'wirtschaft', 'bildung', 'gesundheit',
    'kirche', 'natur', 'technik', 'kultur', 'politik',
  ];
}

// █████████████████████████████████████████████████████████████████████████████
// PATTERN HELPER
// █████████████████████████████████████████████████████████████████████████████

// █████████████████████████████████████████████████████████████████████████████
// ITALIAN ADVANCED — Avere/Essere passato prossimo
// █████████████████████████████████████████████████████████████████████████████

/// IT: "ho andato" → "sono andato", "sono mangiato" → "ho mangiato"
class _ItalianAvereEssereRule extends _GrammarRule {
  @override String get id => 'it_avere_essere';
  @override Set<DictLanguage> get languages => const {DictLanguage.it};

  @override
  List<GrammarError> check(String text, DictLanguage lang) {
    final errors = <GrammarError>[];
    // "ho" + verb that requires "essere"
    final hoPattern = RegExp(
      r'\b(ho|hai|ha|abbiamo|avete|hanno)\s+('
      '${_essereVerbs.join('|')}'
      r')\b',
      caseSensitive: false,
    );
    for (final m in hoPattern.allMatches(text)) {
      final aux = m.group(1)!.toLowerCase();
      final verb = m.group(2)!;
      final fix = _avereToEssere[aux] ?? 'sono';
      errors.add(GrammarError(
        message: 'Usa "$fix" con "$verb"',
        startIndex: m.start, endIndex: m.end,
        suggestion: '$fix $verb', ruleId: id,
      ));
    }

    // "sono" + verb that requires "avere"
    final sonoPattern = RegExp(
      r'\b(sono|sei|è|siamo|siete|sono)\s+('
      '${_avereVerbs.join('|')}'
      r')\b',
      caseSensitive: false,
    );
    for (final m in sonoPattern.allMatches(text)) {
      final aux = m.group(1)!.toLowerCase();
      final verb = m.group(2)!;
      final fix = _essereToAvere[aux] ?? 'ho';
      errors.add(GrammarError(
        message: 'Usa "$fix" con "$verb"',
        startIndex: m.start, endIndex: m.end,
        suggestion: '$fix $verb', ruleId: id,
      ));
    }
    return errors;
  }

  // Verbs that require "essere" in passato prossimo
  static const _essereVerbs = [
    'andato', 'andata', 'andati', 'andate',
    'venuto', 'venuta', 'venuti', 'venute',
    'partito', 'partita', 'partiti', 'partite',
    'arrivato', 'arrivata', 'arrivati', 'arrivate',
    'tornato', 'tornata', 'tornati', 'tornate',
    'uscito', 'uscita', 'usciti', 'uscite',
    'entrato', 'entrata', 'entrati', 'entrate',
    'nato', 'nata', 'nati', 'nate',
    'morto', 'morta', 'morti', 'morte',
    'caduto', 'caduta', 'caduti', 'cadute',
    'rimasto', 'rimasta', 'rimasti', 'rimaste',
    'stato', 'stata', 'stati', 'state',
    'diventato', 'diventata', 'diventati', 'diventate',
    'cresciuto', 'cresciuta', 'cresciuti', 'cresciute',
    'salito', 'salita', 'saliti', 'salite',
    'sceso', 'scesa', 'scesi', 'scese',
  ];

  // Verbs that require "avere" in passato prossimo
  static const _avereVerbs = [
    'mangiato', 'bevuto', 'dormito', 'lavorato', 'studiato',
    'parlato', 'scritto', 'letto', 'visto', 'comprato',
    'venduto', 'capito', 'finito', 'iniziato', 'pensato',
    'detto', 'fatto', 'preso', 'messo', 'chiuso',
    'aperto', 'cambiato', 'giocato', 'cucinato', 'pagato',
  ];

  static const _avereToEssere = {
    'ho': 'sono', 'hai': 'sei', 'ha': 'è',
    'abbiamo': 'siamo', 'avete': 'siete', 'hanno': 'sono',
  };

  static const _essereToAvere = {
    'sono': 'ho', 'sei': 'hai', 'è': 'ha',
    'siamo': 'abbiamo', 'siete': 'avete',
  };
}

// █████████████████████████████████████████████████████████████████████████████
// BIGRAM CONTEXT SUGGESTIONS
// █████████████████████████████████████████████████████████████████████████████

/// Uses bigram data from the dictionary to flag unlikely word pairs.
class _BigramContextRule extends _GrammarRule {
  @override String get id => 'bigram_context';
  @override Set<DictLanguage> get languages => const {};

  @override
  List<GrammarError> check(String text, DictLanguage lang) {
    final errors = <GrammarError>[];
    final dict = WordCompletionDictionary.instance;
    final words = text.split(RegExp(r'\s+'));

    int offset = 0;
    for (int i = 0; i < words.length - 1; i++) {
      final w1 = words[i].replaceAll(RegExp(r'[^\w]'), '');
      final w2 = words[i + 1].replaceAll(RegExp(r'[^\w]'), '');

      if (w1.length < 2 || w2.length < 2) {
        offset += words[i].length + 1;
        continue;
      }

      // Check if the bigram exists and get next-word suggestions
      final suggestions = dict.getContextSuggestions(w1, limit: 3);
      if (suggestions.isNotEmpty && dict.isValidWord(w2)) {
        // Only flag if w2 is NOT in the top bigram continuations
        // and a much better continuation exists (frequency ratio > 5x)
        final topFreq = dict.bigramFrequency(w1, suggestions.first);
        final actualFreq = dict.bigramFrequency(w1, w2);
        if (topFreq > 0 && actualFreq == 0 && suggestions.first != w2.toLowerCase()) {
          final startIdx = offset + words[i].length + 1;
          final endIdx = startIdx + words[i + 1].length;
          if (startIdx < text.length && endIdx <= text.length) {
            errors.add(GrammarError(
              message: 'After "$w1", consider: "${suggestions.first}"',
              startIndex: startIdx, endIndex: endIdx,
              suggestion: suggestions.first,
              severity: GrammarSeverity.info, ruleId: id,
            ));
          }
        }
      }
      offset += words[i].length + 1;
    }
    return errors;
  }
}

// █████████████████████████████████████████████████████████████████████████████
// SWEDISH RULES
// █████████████████████████████████████████████████████████████████████████████

/// Swedish en/ett articles (common/neuter gender).
class _SwedishArticleRule extends _GrammarRule {
  @override String get id => 'sv_article';
  @override Set<DictLanguage> get languages => const {DictLanguage.sv};

  @override
  List<GrammarError> check(String text, DictLanguage lang) {
    final errors = <GrammarError>[];
    // "en" + neuter noun
    for (final m in RegExp(r'\ben\s+(\w+)\b', caseSensitive: false).allMatches(text)) {
      final noun = m.group(1)!.toLowerCase();
      if (_ettWords.contains(noun)) {
        errors.add(GrammarError(
          message: '"en $noun" → "ett $noun"',
          startIndex: m.start, endIndex: m.end,
          suggestion: 'ett $noun', ruleId: id,
        ));
      }
    }
    // "ett" + common noun
    for (final m in RegExp(r'\bett\s+(\w+)\b', caseSensitive: false).allMatches(text)) {
      final noun = m.group(1)!.toLowerCase();
      if (_enWords.contains(noun)) {
        errors.add(GrammarError(
          message: '"ett $noun" → "en $noun"',
          startIndex: m.start, endIndex: m.end,
          suggestion: 'en $noun', ruleId: id,
        ));
      }
    }
    return errors;
  }

  static const _ettWords = {
    'hus', 'barn', 'bord', 'land', 'vatten', 'liv', 'ord',
    'år', 'ställe', 'rum', 'djur', 'träd', 'problem', 'system',
    'resultat', 'arbete', 'nummer', 'exempel', 'ögonblick',
    'parti', 'äpple', 'öga', 'öra', 'hjärta',
  };

  static const _enWords = {
    'man', 'kvinna', 'dag', 'bil', 'stad', 'skola', 'familj',
    'vän', 'fråga', 'bok', 'film', 'dörr', 'väg', 'stol',
    'historia', 'musik', 'politik', 'ekonomi', 'vetenskap',
  };
}

// █████████████████████████████████████████████████████████████████████████████
// ROMANIAN RULES
// █████████████████████████████████████████████████████████████████████████████

/// Romanian article-noun gender (un/o).
class _RomanianArticleRule extends _GrammarRule {
  @override String get id => 'ro_article_agreement';
  @override Set<DictLanguage> get languages => const {DictLanguage.ro};

  @override
  List<GrammarError> check(String text, DictLanguage lang) {
    final errors = <GrammarError>[];
    // "un" + feminine noun (detected by ending)
    for (final m in RegExp(r'\bun\s+(\w+)\b', caseSensitive: false).allMatches(text)) {
      final noun = m.group(1)!.toLowerCase();
      if (_isFeminine(noun)) {
        errors.add(GrammarError(
          message: '"un $noun" → "o $noun"',
          startIndex: m.start, endIndex: m.end,
          suggestion: 'o $noun', ruleId: id,
        ));
      }
    }
    return errors;
  }

  static bool _isFeminine(String noun) {
    // Romanian: -ă, -ie, -iune, -tate are typically feminine
    return noun.endsWith('ă') || noun.endsWith('ie') ||
           noun.endsWith('iune') || noun.endsWith('tate') ||
           noun.endsWith('ețe');
  }
}

// █████████████████████████████████████████████████████████████████████████████
// TURKISH RULES
// █████████████████████████████████████████████████████████████████████████████

/// Turkish vowel harmony: suffix vowels must match the last vowel of the stem.
class _TurkishVowelHarmonyRule extends _GrammarRule {
  @override String get id => 'tr_vowel_harmony';
  @override Set<DictLanguage> get languages => const {DictLanguage.tr};

  @override
  List<GrammarError> check(String text, DictLanguage lang) {
    final errors = <GrammarError>[];
    // Common suffix pairs that violate harmony
    for (final r in _rules) {
      final pat = RegExp(r.pattern, caseSensitive: false);
      for (final m in pat.allMatches(text)) {
        errors.add(GrammarError(
          message: r.message,
          startIndex: m.start, endIndex: m.end,
          suggestion: r.suggestion,
          severity: GrammarSeverity.warning, ruleId: id,
        ));
      }
    }
    return errors;
  }

  static final _rules = [
    // Locative: -da/-de (front/back harmony)
    _P(r'\b(\w*[eiöü]\w*)da\b', 'Vowel harmony: use "-de"', null),
    _P(r'\b(\w*[aoıu]\w*)de\b', 'Vowel harmony: use "-da"', null),
  ];
}

// █████████████████████████████████████████████████████████████████████████████
// POLISH RULES
// █████████████████████████████████████████████████████████████████████████████

/// Polish common accent/diacritic errors.
class _PolishDiacriticsRule extends _GrammarRule {
  @override String get id => 'pl_diacritics';
  @override Set<DictLanguage> get languages => const {DictLanguage.pl};

  @override
  List<GrammarError> check(String text, DictLanguage lang) {
    final errors = <GrammarError>[];
    for (final entry in _diacritics.entries) {
      final pat = RegExp('\\b${entry.key}\\b', caseSensitive: false);
      for (final m in pat.allMatches(text)) {
        errors.add(GrammarError(
          message: 'Brak polskich znaków: "${entry.value}"',
          startIndex: m.start, endIndex: m.end,
          suggestion: entry.value, ruleId: id,
        ));
      }
    }
    return errors;
  }

  static const _diacritics = {
    'ze': 'że', 'ze by': 'żeby', 'zeby': 'żeby',
    'rowniez': 'również', 'moze': 'może',
    'takze': 'także', 'prosze': 'proszę',
    'dziekuje': 'dziękuję', 'czesc': 'cześć',
    'juz': 'już', 'wiecej': 'więcej', 'zle': 'źle',
  };
}

// █████████████████████████████████████████████████████████████████████████████
// CZECH RULES
// █████████████████████████████████████████████████████████████████████████████

/// Czech háček/čárka diacritic errors.
class _CzechDiacriticsRule extends _GrammarRule {
  @override String get id => 'cs_diacritics';
  @override Set<DictLanguage> get languages => const {DictLanguage.cs};

  @override
  List<GrammarError> check(String text, DictLanguage lang) {
    final errors = <GrammarError>[];
    for (final entry in _diacritics.entries) {
      final pat = RegExp('\\b${entry.key}\\b', caseSensitive: false);
      for (final m in pat.allMatches(text)) {
        errors.add(GrammarError(
          message: 'Chybí diakritika: "${entry.value}"',
          startIndex: m.start, endIndex: m.end,
          suggestion: entry.value, ruleId: id,
        ));
      }
    }
    return errors;
  }

  static const _diacritics = {
    'cesky': 'česky', 'clovek': 'člověk',
    'dekuji': 'děkuji', 'prosim': 'prosím',
    'muzete': 'můžete', 'protoze': 'protože',
    'jeste': 'ještě', 'mozna': 'možná',
    'takze': 'takže', 'uz': 'už',
  };
}

// █████████████████████████████████████████████████████████████████████████████
// CROATIAN RULES
// █████████████████████████████████████████████████████████████████████████████

/// Croatian common diacritic errors.
class _CroatianDiacriticsRule extends _GrammarRule {
  @override String get id => 'hr_diacritics';
  @override Set<DictLanguage> get languages => const {DictLanguage.hr};

  @override
  List<GrammarError> check(String text, DictLanguage lang) {
    final errors = <GrammarError>[];
    for (final entry in _diacritics.entries) {
      final pat = RegExp('\\b${entry.key}\\b', caseSensitive: false);
      for (final m in pat.allMatches(text)) {
        errors.add(GrammarError(
          message: 'Nedostaje dijakritički znak: "${entry.value}"',
          startIndex: m.start, endIndex: m.end,
          suggestion: entry.value, ruleId: id,
        ));
      }
    }
    return errors;
  }

  static const _diacritics = {
    'sto': 'što', 'zasto': 'zašto', 'sta': 'šta',
    'vise': 'više', 'clan': 'član', 'ucitelj': 'učitelj',
    'sreca': 'sreća', 'zivot': 'život',
    'moze': 'može', 'zelim': 'želim',
  };
}

// █████████████████████████████████████████████████████████████████████████████
// HUNGARIAN RULES
// █████████████████████████████████████████████████████████████████████████████

/// Hungarian accent errors (long vs short vowels).
class _HungarianAccentRule extends _GrammarRule {
  @override String get id => 'hu_accents';
  @override Set<DictLanguage> get languages => const {DictLanguage.hu};

  @override
  List<GrammarError> check(String text, DictLanguage lang) {
    final errors = <GrammarError>[];
    for (final entry in _accents.entries) {
      final pat = RegExp('\\b${entry.key}\\b', caseSensitive: false);
      for (final m in pat.allMatches(text)) {
        errors.add(GrammarError(
          message: 'Ékezet: "${entry.value}"',
          startIndex: m.start, endIndex: m.end,
          suggestion: entry.value, ruleId: id,
        ));
      }
    }
    return errors;
  }

  static const _accents = {
    'koszonomm': 'köszönöm', 'koszonom': 'köszönöm',
    'kerem': 'kérem', 'udv': 'üdv', 'udvozlet': 'üdvözlet',
    'konyvtar': 'könyvtár', 'egyetem': 'egyetem',
    'tortenet': 'történet', 'kulonos': 'különös',
  };
}

class _P {
  final String pattern;
  final String message;
  final String? suggestion;
  const _P(this.pattern, this.message, this.suggestion);
}

// =============================================================================
// 📝 GRAMMAR CHECK SERVICE — Main service
// =============================================================================

class GrammarCheckService {
  GrammarCheckService._();
  static final GrammarCheckService instance = GrammarCheckService._();

  bool _enabled = true;
  bool get enabled => _enabled;
  void setEnabled(bool value) => _enabled = value;

  /// All grammar rules — 29 rules.
  final List<_GrammarRule> _rules = [
    // ── Universal (9) ──
    _DuplicateWordRule(),
    _SentenceCapitalizationRule(),
    _DoubleSpaceRule(),
    _MissingSpaceAfterPunctuationRule(),
    _PunctuationPairingRule(),
    _EllipsisRule(),
    _CommonTypoRule(),
    _NumberFormattingRule(),
    _BigramContextRule(),
    // ── English (3) ──
    _EnglishConfusablesRule(),
    _EnglishContractionRule(),
    _EnglishSubjectVerbRule(),
    // ── Romance (5) ──
    _ItalianArticleRule(),
    _ItalianAvereEssereRule(),
    _SpanishArticleRule(),
    _FrenchArticleRule(),
    _PortugueseArticleRule(),
    _RomanianArticleRule(),
    // ── Germanic (3) ──
    _GermanNounCapitalizationRule(),
    _DutchArticleRule(),
    _SwedishArticleRule(),
    // ── Slavic (3) ──
    _PolishDiacriticsRule(),
    _CzechDiacriticsRule(),
    _CroatianDiacriticsRule(),
    // ── Other (2) ──
    _TurkishVowelHarmonyRule(),
    _HungarianAccentRule(),
  ];

  final Map<String, GrammarResult> _cache = {};
  DictLanguage? _cachedLanguage;
  static const int _maxCacheSize = 32;

  final Set<String> _disabledRules = {};

  void disableRule(String ruleId) { _disabledRules.add(ruleId); _cache.clear(); }
  void enableRule(String ruleId) { _disabledRules.remove(ruleId); _cache.clear(); }

  /// Get all available rule IDs and their descriptions.
  List<({String id, String name, bool enabled})> get availableRules =>
      _rules.map((r) => (
        id: r.id,
        name: r.id.replaceAll('_', ' '),
        enabled: !_disabledRules.contains(r.id),
      )).toList();

  GrammarResult checkText(String text) {
    if (!_enabled || text.isEmpty) {
      return GrammarResult(text: text, errors: []);
    }

    final currentLang = WordCompletionDictionary.instance.language;
    if (_cachedLanguage != currentLang) {
      _cache.clear();
      _cachedLanguage = currentLang;
    }

    final cached = _cache[text];
    if (cached != null) return cached;

    final errors = <GrammarError>[];
    for (final rule in _rules) {
      if (_disabledRules.contains(rule.id)) continue;
      if (!rule.appliesTo(currentLang)) continue;
      errors.addAll(rule.check(text, currentLang));
    }

    errors.sort((a, b) => a.startIndex.compareTo(b.startIndex));

    // Remove overlapping errors
    final filtered = <GrammarError>[];
    for (final error in errors) {
      final overlaps = filtered.any((e) =>
          error.startIndex < e.endIndex && error.endIndex > e.startIndex);
      if (!overlaps) filtered.add(error);
    }

    final result = GrammarResult(text: text, errors: filtered);
    if (_cache.length >= _maxCacheSize) _cache.remove(_cache.keys.first);
    _cache[text] = result;
    return result;
  }
}
