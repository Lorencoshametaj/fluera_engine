import 'package:flutter/foundation.dart';
import 'word_completion_dictionary.dart';

// =============================================================================
// 🌍 LANGUAGE DETECTION SERVICE — Per-sentence language identification
//
// Detects the language of each sentence in a multi-language text using
// stop-word matching and character-level heuristics. Enables mixed-language
// spellcheck & grammar (e.g. Italian notes with English terms).
//
// Algorithm:
//   1. Split text into sentences (by punctuation or newline)
//   2. For each sentence, count stop-word matches per language
//   3. If no clear winner, use character analysis (script detection)
//   4. Return a list of LanguageSegments with position + detected language
// =============================================================================

/// A segment of text with its detected language.
class LanguageSegment {
  final int startIndex;
  final int endIndex;
  final DictLanguage language;
  final double confidence; // 0.0 - 1.0

  const LanguageSegment({
    required this.startIndex,
    required this.endIndex,
    required this.language,
    required this.confidence,
  });

  String getText(String fullText) => fullText.substring(startIndex, endIndex);

  @override
  String toString() => 'Segment[$startIndex:$endIndex] ${language.name} (${(confidence * 100).toStringAsFixed(0)}%)';
}

class LanguageDetectionService {
  LanguageDetectionService._();
  static final LanguageDetectionService instance = LanguageDetectionService._();

  /// The primary language (used as fallback when detection is ambiguous).
  DictLanguage get primaryLanguage => WordCompletionDictionary.instance.language;

  // ── Cache ──────────────────────────────────────────────────────────────
  final Map<String, List<LanguageSegment>> _cache = {};
  static const int _maxCacheSize = 16;

  void clearCache() => _cache.clear();

  /// Identify the language of a text, returning BCP-47 code (e.g. "en", "it").
  /// Used by DigitalInkService for auto-detect feedback loop.
  Future<String?> identifyLanguage(String text) async {
    if (text.trim().length < 3) return null;
    final lang = detectLanguage(text);
    return lang.name; // DictLanguage.name matches BCP-47 codes
  }

  /// Dispose resources.
  void dispose() {
    _cache.clear();
    _languagePairCounts.clear();
  }

  // ── Language Pair Learning ─────────────────────────────────────────────

  /// Tracks which language pairs the user commonly uses together.
  /// Key: sorted pair (e.g. 'en+it'), value: frequency count.
  final Map<String, int> _languagePairCounts = {};

  /// Record that two languages appeared together in a note.
  void recordLanguagePair(DictLanguage a, DictLanguage b) {
    if (a == b) return;
    final key = [a.name, b.name]..sort();
    final pairKey = key.join('+');
    _languagePairCounts[pairKey] = (_languagePairCounts[pairKey] ?? 0) + 1;
  }

  /// Get the user's most common secondary languages (paired with primary).
  List<DictLanguage> getCommonPairLanguages({int limit = 3}) {
    final primary = primaryLanguage.name;
    final pairs = _languagePairCounts.entries
        .where((e) => e.key.contains(primary))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return pairs.take(limit).map((e) {
      final parts = e.key.split('+');
      final other = parts.first == primary ? parts.last : parts.first;
      return DictLanguage.values.firstWhere(
        (l) => l.name == other,
        orElse: () => DictLanguage.en,
      );
    }).toList();
  }

  // ── Word-Level Detection ───────────────────────────────────────────────

  /// Detect language of a single word.
  /// Returns the most likely language, prioritizing the user's known pairs.
  DictLanguage detectWordLanguage(String word) {
    final lower = word.toLowerCase();
    if (lower.length < 2) return primaryLanguage;

    // 1. Check if it's a stop word in any language
    for (final entry in _stopWords.entries) {
      if (entry.value.contains(lower)) return entry.key;
    }

    // 2. Check script
    final scriptResult = _detectByScript(word);
    if (scriptResult != null) return scriptResult.language;

    // 3. Check character heuristics
    final charResult = _detectByCharacters(word);
    if (charResult != null) return charResult.language;

    // 4. Default to primary
    return primaryLanguage;
  }

  // ── Cross-Dictionary Validation ────────────────────────────────────────

  /// Check if a word is valid in ANY of the user's commonly-used languages.
  /// Returns the language it's valid in, or null if invalid everywhere.
  DictLanguage? validateWordAcrossLanguages(String word) {
    final dict = WordCompletionDictionary.instance;

    // First: check current dictionary
    if (dict.isValidWord(word)) return dict.language;

    // Second: check stop-words (these are always valid in their language)
    final lower = word.toLowerCase();
    for (final entry in _stopWords.entries) {
      if (entry.value.contains(lower)) return entry.key;
    }

    // Third: check common pair languages
    // (The actual dictionary data is only loaded for one language at a time,
    // so we can only confirm stop-word membership for other languages.
    // For full cross-dict validation, we'd need to hold multiple tries.)
    return null;
  }

  /// Check if a word is likely valid in a different language than the current one.
  /// Uses stop-words + common loanwords as proxy.
  bool isLikelyForeignWord(String word) {
    final lower = word.toLowerCase();
    final currentLang = primaryLanguage;

    // Check if it's a stop word in another language
    for (final entry in _stopWords.entries) {
      if (entry.key != currentLang && entry.value.contains(lower)) {
        return true;
      }
    }

    return false;
  }

  // ── Public API ─────────────────────────────────────────────────────────

  /// Detect languages in a text, returning segments with language info.
  /// Each segment is typically a sentence or a coherent language block.
  List<LanguageSegment> detectSegments(String text) {
    if (text.isEmpty) return [];

    final cached = _cache[text];
    if (cached != null) return cached;

    final segments = <LanguageSegment>[];
    final sentences = _splitIntoSentences(text);

    for (final sentence in sentences) {
      final lang = _detectSentenceLanguage(sentence.text);
      segments.add(LanguageSegment(
        startIndex: sentence.start,
        endIndex: sentence.end,
        language: lang.language,
        confidence: lang.confidence,
      ));
    }

    // Merge adjacent segments of the same language
    final merged = _mergeSegments(segments);

    // Record language pairs for learning
    final langs = merged.map((s) => s.language).toSet();
    if (langs.length >= 2) {
      final langList = langs.toList();
      for (int i = 0; i < langList.length; i++) {
        for (int j = i + 1; j < langList.length; j++) {
          recordLanguagePair(langList[i], langList[j]);
        }
      }
    }

    // Cache
    if (_cache.length >= _maxCacheSize) _cache.remove(_cache.keys.first);
    _cache[text] = merged;

    return merged;
  }

  /// Quick single-language detection for a short text.
  DictLanguage detectLanguage(String text) {
    if (text.isEmpty) return primaryLanguage;
    final result = _detectSentenceLanguage(text);
    return result.language;
  }

  // ── Sentence splitting ─────────────────────────────────────────────────

  List<_TextSpan> _splitIntoSentences(String text) {
    final spans = <_TextSpan>[];
    // Split by sentence-ending punctuation or newlines
    final pattern = RegExp(r'[.!?]+\s+|\n+');
    int lastEnd = 0;

    for (final match in pattern.allMatches(text)) {
      if (match.start > lastEnd) {
        final segment = text.substring(lastEnd, match.end).trim();
        if (segment.isNotEmpty) {
          spans.add(_TextSpan(lastEnd, match.end, segment));
        }
      }
      lastEnd = match.end;
    }

    // Remaining text
    if (lastEnd < text.length) {
      final remaining = text.substring(lastEnd).trim();
      if (remaining.isNotEmpty) {
        spans.add(_TextSpan(lastEnd, text.length, remaining));
      }
    }

    if (spans.isEmpty && text.trim().isNotEmpty) {
      spans.add(_TextSpan(0, text.length, text));
    }

    return spans;
  }

  // ── Language detection per sentence ────────────────────────────────────

  _DetectionResult _detectSentenceLanguage(String text) {
    // 1. Script-based detection FIRST (fast path for non-Latin)
    // Must run before word extraction since \w strips non-Latin chars!
    final scriptResult = _detectByScript(text);
    if (scriptResult != null) return scriptResult;

    final words = text.toLowerCase().split(RegExp(r'\s+'))
        .where((w) => w.length >= 2)
        .map((w) => w.replaceAll(RegExp(r'[^\w]'), ''))
        .where((w) => w.isNotEmpty)
        .toList();

    if (words.isEmpty) {
      return _DetectionResult(primaryLanguage, 0.5);
    }

    // 2. Stop-word matching
    final scores = <DictLanguage, int>{};
    for (final word in words) {
      for (final entry in _stopWords.entries) {
        if (entry.value.contains(word)) {
          scores[entry.key] = (scores[entry.key] ?? 0) + 1;
        }
      }
    }

    if (scores.isNotEmpty) {
      final sorted = scores.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      final best = sorted.first;
      final total = words.length;
      final confidence = (best.value / total).clamp(0.0, 1.0);

      // Need at least 2 stop words or 20% match for confidence
      if (best.value >= 2 || confidence >= 0.2) {
        return _DetectionResult(best.key, confidence);
      }
    }

    // 3. Character heuristics (accented characters)
    final charResult = _detectByCharacters(text);
    if (charResult != null) return charResult;

    // 4. Fallback: use dictionary validation
    final dictResult = _detectByDictionary(words);
    if (dictResult != null) return dictResult;

    // 5. Ultimate fallback: primary language
    return _DetectionResult(primaryLanguage, 0.3);
  }

  /// Detect by Unicode script (non-Latin alphabets).
  _DetectionResult? _detectByScript(String text) {
    int cyrillic = 0, arabic = 0, cjk = 0, devanagari = 0, greek = 0;
    int hebrew = 0, thai = 0, korean = 0, total = 0;

    for (final rune in text.runes) {
      if (rune >= 0x0400 && rune <= 0x04FF) cyrillic++;
      else if (rune >= 0x0600 && rune <= 0x06FF) arabic++;
      else if (rune >= 0x4E00 && rune <= 0x9FFF) cjk++;
      else if (rune >= 0x0900 && rune <= 0x097F) devanagari++;
      else if (rune >= 0x0370 && rune <= 0x03FF) greek++;
      else if (rune >= 0x0590 && rune <= 0x05FF) hebrew++;
      else if (rune >= 0x0E00 && rune <= 0x0E7F) thai++;
      else if (rune >= 0xAC00 && rune <= 0xD7AF) korean++;
      if (rune > 0x40) total++; // Skip control chars in count
    }

    if (total == 0) return null;
    const threshold = 0.3;

    if (cyrillic / total > threshold) return _DetectionResult(DictLanguage.ru, 0.8);
    if (arabic / total > threshold) return _DetectionResult(DictLanguage.ar, 0.8);
    if (cjk / total > threshold) return _DetectionResult(DictLanguage.zh, 0.8);
    if (devanagari / total > threshold) return _DetectionResult(DictLanguage.hi, 0.8);
    if (greek / total > threshold) return _DetectionResult(DictLanguage.el, 0.8);
    if (hebrew / total > threshold) return _DetectionResult(DictLanguage.he, 0.8);
    if (thai / total > threshold) return _DetectionResult(DictLanguage.th, 0.8);
    if (korean / total > threshold) return _DetectionResult(DictLanguage.ko, 0.8);

    return null;
  }

  /// Detect by accent/diacritic patterns unique to certain languages.
  _DetectionResult? _detectByCharacters(String text) {
    final lower = text.toLowerCase();

    // German: ü, ö, ä, ß (combined uniquely)
    if (lower.contains('ß') ||
        (lower.contains('ü') && lower.contains('ö'))) {
      return _DetectionResult(DictLanguage.de, 0.6);
    }

    // Turkish: ğ, ş, ı (dotless i)
    if (lower.contains('ğ') || lower.contains('ı') ||
        (lower.contains('ş') && !lower.contains('ț'))) {
      return _DetectionResult(DictLanguage.tr, 0.6);
    }

    // Romanian: ț, ș, ă, â, î (uniquely Romanian)
    if (lower.contains('ț') || lower.contains('ș') ||
        (lower.contains('ă') && lower.contains('î'))) {
      return _DetectionResult(DictLanguage.ro, 0.6);
    }

    // Polish: ł, ż, ź, ć, ś, ń
    if (lower.contains('ł') || lower.contains('ź') ||
        (lower.contains('ż') && lower.contains('ś'))) {
      return _DetectionResult(DictLanguage.pl, 0.6);
    }

    // Czech: ř, ů, ě (unique to Czech)
    if (lower.contains('ř') || lower.contains('ů') || lower.contains('ě')) {
      return _DetectionResult(DictLanguage.cs, 0.6);
    }

    // Hungarian: ő, ű (double acute accent)
    if (lower.contains('ő') || lower.contains('ű')) {
      return _DetectionResult(DictLanguage.hu, 0.6);
    }

    // Swedish/Danish/Norwegian: å
    if (lower.contains('å')) {
      return _DetectionResult(DictLanguage.sv, 0.4); // Could be DA/NO too
    }

    return null;
  }

  /// Detect by checking which dictionary validates the most words.
  _DetectionResult? _detectByDictionary(List<String> words) {
    final dict = WordCompletionDictionary.instance;
    final currentLang = dict.language;
    int currentMatches = 0;

    for (final word in words) {
      if (dict.isValidWord(word)) currentMatches++;
    }

    // If most words validate in current language, it's likely correct
    if (currentMatches >= words.length * 0.6) {
      return _DetectionResult(currentLang, 0.5);
    }

    return null;
  }

  // ── Segment merging ────────────────────────────────────────────────────

  List<LanguageSegment> _mergeSegments(List<LanguageSegment> segments) {
    if (segments.length <= 1) return segments;

    final merged = <LanguageSegment>[segments.first];
    for (int i = 1; i < segments.length; i++) {
      final prev = merged.last;
      final curr = segments[i];
      if (prev.language == curr.language) {
        merged[merged.length - 1] = LanguageSegment(
          startIndex: prev.startIndex,
          endIndex: curr.endIndex,
          language: prev.language,
          confidence: (prev.confidence + curr.confidence) / 2,
        );
      } else {
        merged.add(curr);
      }
    }
    return merged;
  }

  // ── Stop-word dictionaries ─────────────────────────────────────────────

  static const _stopWords = <DictLanguage, Set<String>>{
    DictLanguage.en: {
      'the', 'a', 'an', 'is', 'are', 'was', 'were', 'be', 'been', 'being',
      'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would', 'could',
      'should', 'may', 'might', 'must', 'shall', 'can', 'need', 'dare',
      'and', 'but', 'or', 'nor', 'not', 'so', 'yet', 'both', 'either',
      'neither', 'each', 'every', 'all', 'any', 'few', 'more', 'most',
      'other', 'some', 'such', 'no', 'only', 'own', 'same', 'than',
      'too', 'very', 'just', 'because', 'as', 'until', 'while', 'of',
      'at', 'by', 'for', 'with', 'about', 'against', 'between', 'through',
      'during', 'before', 'after', 'above', 'below', 'to', 'from',
      'in', 'out', 'on', 'off', 'over', 'under', 'again', 'further',
      'then', 'once', 'here', 'there', 'when', 'where', 'why', 'how',
      'this', 'that', 'these', 'those', 'what', 'which', 'who', 'whom',
    },
    DictLanguage.it: {
      'il', 'lo', 'la', 'le', 'gli', 'un', 'uno', 'una', 'di', 'del',
      'della', 'dei', 'delle', 'degli', 'in', 'nel', 'nella', 'nei',
      'nelle', 'negli', 'con', 'su', 'per', 'tra', 'fra', 'da', 'dal',
      'dalla', 'dai', 'dalle', 'dagli', 'al', 'alla', 'ai', 'alle',
      'agli', 'sul', 'sulla', 'sui', 'sulle', 'sugli', 'che', 'chi',
      'cui', 'non', 'questo', 'questa', 'questi', 'queste',
      'quello', 'quella', 'quelli', 'quelle', 'sono', 'sei', 'siamo',
      'siete', 'ho', 'hai', 'ha', 'abbiamo', 'avete', 'hanno',
      'anche', 'ancora', 'come', 'dove', 'quando', 'molto',
      'ogni', 'sempre', 'poi', 'ora', 'cosa', 'tutto', 'tutti',
      'ma', 'se', 'quindi', 'proprio', 'essere',
    },
    DictLanguage.es: {
      'el', 'la', 'los', 'las', 'un', 'una', 'unos', 'unas', 'de', 'del',
      'en', 'con', 'por', 'para', 'al', 'que', 'es', 'son', 'fue', 'ser',
      'como', 'pero', 'muy', 'ya', 'este', 'esta', 'estos', 'estas',
      'ese', 'esa', 'esos', 'esas', 'aquel', 'aquella',
      'hay', 'donde', 'cuando', 'porque', 'todos', 'todo',
      'tiene', 'hacer', 'desde', 'entre', 'sobre',
      'otro', 'otra', 'otros', 'otras', 'nos', 'les', 'lo', 'me',
    },
    DictLanguage.fr: {
      'le', 'la', 'les', 'un', 'une', 'des', 'du', 'de', 'en', 'dans',
      'avec', 'pour', 'par', 'sur', 'que', 'qui', 'est', 'sont',
      'avoir', 'fait', 'comme', 'mais', 'ou', 'et', 'donc', 'car', 'ni',
      'pas', 'plus', 'ne', 'ce', 'cette', 'ces', 'mon', 'ton', 'son',
      'notre', 'votre', 'leur', 'nous', 'vous', 'ils', 'elles', 'je',
      'tu', 'il', 'elle', 'on', 'tout', 'tous', 'aussi', 'bien',
      'comment', 'pourquoi', 'ici', 'encore',
    },
    DictLanguage.de: {
      'der', 'die', 'das', 'ein', 'eine', 'und', 'ist', 'sind', 'war',
      'ich', 'du', 'er', 'sie', 'es', 'wir', 'ihr', 'nicht', 'mit',
      'von', 'auf', 'dem', 'den', 'des', 'bis',
      'nach', 'auch', 'aber', 'nur', 'noch', 'mehr', 'als',
      'aus', 'bei', 'oder', 'wenn', 'wie', 'was', 'kann', 'hat',
      'haben', 'habe', 'wird', 'werden', 'sein', 'schon', 'dass',
      'man', 'diese', 'dieser', 'dieses', 'immer', 'hier', 'dort',
    },
    DictLanguage.pt: {
      'um', 'uma', 'uns', 'umas', 'de', 'do', 'da', 'dos', 'das',
      'em', 'no', 'na', 'nos', 'nas', 'com', 'por', 'para', 'ao',
      'que', 'mais', 'mas', 'como', 'seu', 'sua',
      'ele', 'ela', 'eles', 'elas', 'você',
      'este', 'esta', 'isso', 'aqui', 'onde', 'quando', 'porque',
      'foi', 'ser', 'ter', 'tem', 'muito', 'ainda', 'depois',
    },
    DictLanguage.nl: {
      'de', 'het', 'een', 'en', 'van', 'in', 'is', 'dat', 'op', 'te',
      'voor', 'met', 'zijn', 'hij', 'zij', 'wij', 'dit', 'die', 'aan',
      'er', 'maar', 'om', 'ook', 'als', 'dan', 'nog', 'al', 'bij',
      'naar', 'niet', 'uit', 'wel', 'geen', 'haar', 'hoe', 'wat',
      'wie', 'waar', 'kan', 'heeft', 'hebben', 'worden', 'deze',
    },
    DictLanguage.sv: {
      'och', 'att', 'det', 'som', 'med', 'den', 'inte', 'var',
      'jag', 'han', 'hon', 'vi', 'ett', 'en', 'till', 'av',
      'om', 'kan', 'men', 'har', 'hade', 'ska', 'alla',
      'hur', 'vad', 'vem', 'bara',
    },
    DictLanguage.tr: {
      've', 'bir', 'bu', 'da', 'de', 'ile', 'ama', 'var',
      'ben', 'sen', 'biz', 'siz', 'onlar', 'ne', 'nasıl', 'nerede',
      'gibi', 'kadar', 'sonra', 'önce', 'çok', 'daha', 'şu', 'her',
    },
    DictLanguage.pl: {
      'jest', 'nie', 'się', 'na', 'to', 'do', 'za', 'co', 'jak',
      'ale', 'czy', 'ten', 'ta', 'tym', 'od', 'po', 'też', 'tak',
      'już', 'tylko', 'lub', 'dla', 'ze', 'ich', 'być', 'gdy', 'są',
    },
    DictLanguage.ro: {
      'și', 'este', 'un', 'una', 'din', 'care', 'pentru', 'sau',
      'dar', 'cum', 'mai', 'tot', 'sunt', 'fost', 'avea',
      'acest', 'această', 'aici', 'acolo', 'când', 'unde', 'nu',
    },
    DictLanguage.hu: {
      'és', 'egy', 'nem', 'van', 'volt', 'mint', 'meg', 'már',
      'csak', 'még', 'de', 'nagy', 'ki', 'az', 'amit', 'ahol',
      'hogy', 'ezt', 'fel', 'itt', 'ott', 'igen', 'nagyon', 'sok',
    },
    DictLanguage.cs: {
      'je', 'na', 'se', 'že', 'ale', 'jak', 'tak', 'byl', 'jsou',
      'být', 'ten', 'pro', 'než', 'ani', 'ještě', 'také', 'nebo',
      'jeho', 'jen', 'když', 'který', 'která', 'které', 'velmi',
    },
    DictLanguage.hr: {
      'je', 'na', 'se', 'da', 'ali', 'za', 'ili', 'što', 'od',
      'bio', 'biti', 'taj', 'ovaj', 'koji', 'koja', 'koje', 'sve',
      'još', 'samo', 'nego', 'već', 'kada', 'gdje', 'kako', 'ima',
    },
    // ── Additional languages ──
    DictLanguage.da: {
      'og', 'er', 'en', 'et', 'den', 'det', 'at', 'til', 'af', 'med',
      'fra', 'har', 'var', 'som', 'men', 'ikke', 'kan', 'vil', 'skal',
      'han', 'hun', 'jeg', 'vi', 'dem', 'sin', 'her', 'der', 'hvor',
    },
    DictLanguage.fi: {
      'ja', 'on', 'ei', 'se', 'oli', 'olla', 'kun', 'niin', 'mutta',
      'tai', 'kanssa', 'ovat', 'kuin', 'vain', 'minä', 'sinä', 'hän',
      'tämä', 'missä', 'mikä', 'myös', 'enemmän', 'tässä', 'siellä',
    },
    DictLanguage.no: {
      'og', 'er', 'en', 'et', 'den', 'det', 'til', 'av', 'med',
      'fra', 'har', 'var', 'som', 'men', 'ikke', 'kan', 'vil', 'skal',
      'han', 'hun', 'jeg', 'vi', 'dem', 'sin', 'her', 'der', 'hvor',
    },
    DictLanguage.uk: {
      'і', 'в', 'на', 'не', 'що', 'як', 'це', 'але', 'або', 'та',
      'він', 'вона', 'вони', 'ми', 'ви', 'з', 'до', 'від', 'для',
      'все', 'був', 'бути', 'може', 'тут', 'там', 'коли', 'де', 'чому',
    },
    DictLanguage.vi: {
      'và', 'là', 'của', 'có', 'trong', 'cho', 'không', 'được', 'với',
      'này', 'các', 'một', 'những', 'từ', 'tôi', 'bạn', 'anh', 'chị',
      'đã', 'sẽ', 'cũng', 'như', 'khi', 'thì', 'mà', 'nếu', 'còn',
    },
    DictLanguage.id: {
      'dan', 'di', 'yang', 'ini', 'itu', 'untuk', 'dengan', 'tidak',
      'dari', 'ada', 'pada', 'ke', 'oleh', 'akan', 'sudah', 'juga',
      'saya', 'anda', 'mereka', 'kami', 'kita', 'bisa', 'harus',
    },
    DictLanguage.el: {
      'και', 'το', 'να', 'είναι', 'με', 'που', 'δεν', 'για', 'στο',
      'από', 'αλλά', 'ένα', 'μια', 'αυτό', 'εγώ', 'εσύ', 'αυτός',
      'εδώ', 'εκεί', 'πολύ', 'πώς', 'πότε', 'γιατί', 'τώρα',
    },
    DictLanguage.th: {
      'และ', 'ที่', 'ใน', 'มี', 'เป็น', 'ไม่', 'ได้', 'จาก', 'กับ',
      'ของ', 'นี้', 'คือ', 'แต่', 'หรือ', 'ก็', 'จะ', 'ให้', 'ว่า',
    },
  };
}

// ── Internal types ───────────────────────────────────────────────────────

class _TextSpan {
  final int start;
  final int end;
  final String text;
  const _TextSpan(this.start, this.end, this.text);
}

class _DetectionResult {
  final DictLanguage language;
  final double confidence;
  const _DetectionResult(this.language, this.confidence);
}
