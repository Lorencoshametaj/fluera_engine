import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../utils/safe_path_provider.dart';

// =============================================================================
// 📝 LOOKUP ATTEMPT STORE — Persists paraphrase-first dictionary lookups
//
// Each attempt records: word, paraphrase, pre-reveal confidence (1-5),
// post-reveal self-assessment, rewrite, and a timestamp. Skipped lookups are
// also recorded so the student's metacognitive dashboard can surface how
// often the retrieval step is bypassed.
//
// The store is the foundation for the spaced-review feature (§1 Ebbinghaus):
// high-confidence wrong attempts and partial assessments are prime candidates
// for re-surfacing. That logic is not here yet — this service only records.
// =============================================================================

enum LookupAssessment { correct, partial, wrong }

extension LookupAssessmentX on LookupAssessment {
  String get code => switch (this) {
    LookupAssessment.correct => 'correct',
    LookupAssessment.partial => 'partial',
    LookupAssessment.wrong => 'wrong',
  };

  static LookupAssessment? fromCode(String? code) => switch (code) {
    'correct' => LookupAssessment.correct,
    'partial' => LookupAssessment.partial,
    'wrong' => LookupAssessment.wrong,
    _ => null,
  };
}

class LookupAttempt {
  final String word;
  final DateTime timestamp;
  final String? paraphrase;
  final int? confidence; // 1..5
  final LookupAssessment? assessment;
  final String? improvedParaphrase;
  final bool skipped;

  const LookupAttempt({
    required this.word,
    required this.timestamp,
    this.paraphrase,
    this.confidence,
    this.assessment,
    this.improvedParaphrase,
    this.skipped = false,
  });

  /// True if the student took high-confidence position (4-5) and was wrong.
  /// These are the prime candidates for Ipercorrezione-tagged review (§4).
  bool get isHyperCorrectionCandidate =>
      assessment == LookupAssessment.wrong &&
      confidence != null &&
      confidence! >= 4;

  Map<String, dynamic> toJson() => {
    'w': word,
    't': timestamp.toIso8601String(),
    if (paraphrase != null) 'p': paraphrase,
    if (confidence != null) 'c': confidence,
    if (assessment != null) 'a': assessment!.code,
    if (improvedParaphrase != null) 'ip': improvedParaphrase,
    if (skipped) 's': true,
  };

  factory LookupAttempt.fromJson(Map<String, dynamic> j) => LookupAttempt(
    word: j['w'] as String? ?? '',
    timestamp: DateTime.tryParse(j['t'] as String? ?? '') ?? DateTime.now(),
    paraphrase: j['p'] as String?,
    confidence: (j['c'] as num?)?.toInt(),
    assessment: LookupAssessmentX.fromCode(j['a'] as String?),
    improvedParaphrase: j['ip'] as String?,
    skipped: j['s'] as bool? ?? false,
  );
}

class LookupAttemptStore {
  LookupAttemptStore._();
  static final LookupAttemptStore instance = LookupAttemptStore._();

  static const String _fileName = '.fluera_lookup_attempts.json';
  static const int _maxAttempts = 1000;

  final List<LookupAttempt> _attempts = [];
  bool _loaded = false;
  Timer? _saveTimer;

  Future<File?> get _file async {
    final dir = await getSafeDocumentsDirectory();
    if (dir == null) return null;
    return File('${dir.path}/$_fileName');
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = await _file;
      if (file == null || !file.existsSync()) return;
      final content = await file.readAsString();
      final list = jsonDecode(content) as List<dynamic>;
      _attempts.addAll(
        list.map((e) => LookupAttempt.fromJson(e as Map<String, dynamic>)),
      );
    } catch (e) {
      debugPrint('[LookupAttempts] Load error: $e');
    }
  }

  /// Record a new attempt. Debounced write to disk.
  Future<void> record(LookupAttempt attempt) async {
    await _ensureLoaded();
    _attempts.add(attempt);
    while (_attempts.length > _maxAttempts) {
      _attempts.removeAt(0);
    }
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), _saveNow);
  }

  Future<void> _saveNow() async {
    try {
      final file = await _file;
      if (file == null) return;
      await file.writeAsString(
        jsonEncode(_attempts.map((a) => a.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('[LookupAttempts] Save error: $e');
    }
  }

  /// All attempts, oldest first.
  Future<List<LookupAttempt>> all() async {
    await _ensureLoaded();
    return List.unmodifiable(_attempts);
  }

  /// Attempts for a single word (case-insensitive).
  Future<List<LookupAttempt>> forWord(String word) async {
    await _ensureLoaded();
    final lower = word.toLowerCase();
    return _attempts.where((a) => a.word.toLowerCase() == lower).toList();
  }

  Future<void> clear() async {
    _attempts.clear();
    _saveTimer?.cancel();
    try {
      final file = await _file;
      if (file != null && file.existsSync()) await file.delete();
    } catch (_) {}
  }

  void dispose() {
    _saveTimer?.cancel();
  }
}
