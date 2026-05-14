// ignore_for_file: avoid_print
/// ═══════════════════════════════════════════════════════════════════════════
/// 🌍 EXAM DISCIPLINE HINTS BOOTSTRAP — IT → 14 lang translator (Sprint EX-H)
///
/// One-shot script that uses Gemini 2.5 Flash to translate the 10
/// hand-written Italian Exam discipline hint cells (source-of-truth in
/// `lib/src/ai/exam/pedagogy/discipline_hints_exam_it.dart`) into the 14
/// Tier-1/2 target languages. Output replaces the placeholder map in
/// `lib/src/ai/exam/pedagogy/discipline_hints_exam_bootstrap.dart`.
///
/// USAGE:
///   cd fluera_engine
///   # Full bootstrap (all 14 langs × 10 disciplines = 140 calls)
///   GEMINI_API_KEY=sk-xxx dart run tool/bootstrap_exam_discipline_hints.dart
///
///   # Subset (CLI lang filter)
///   GEMINI_API_KEY=sk-xxx dart run tool/bootstrap_exam_discipline_hints.dart es,fr
///
///   # Dry-run on 1 lang (no file write)
///   GEMINI_API_KEY=sk-xxx dart run tool/bootstrap_exam_discipline_hints.dart es --dry-run
///
/// COST: ~$0.10 on Flash (140 calls × ~1000 tokens each). Likely $0 on
/// free tier (~1500 RPD limit covers easily).
///
/// IDEMPOTENT: re-running regenerates from the IT source.
/// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:google_generative_ai/google_generative_ai.dart';

const Map<String, String> _targetLanguages = {
  'es': 'Spanish',
  'pt': 'Portuguese',
  'fr': 'French',
  'de': 'German',
  'ja': 'Japanese',
  'ko': 'Korean',
  'zh': 'Chinese',
  'ar': 'Arabic',
  'hi': 'Hindi',
  'ru': 'Russian',
  'nl': 'Dutch',
  'sv': 'Swedish',
  'pl': 'Polish',
  'tr': 'Turkish',
};

/// 10 Discipline enum values + IT const names from discipline_hints_exam_it.dart.
const List<({String constName, String identifier, String enumValue})>
    _disciplines = [
  (constName: '_physicsIt', identifier: 'physics', enumValue: 'physics'),
  (constName: '_mathIt', identifier: 'math', enumValue: 'math'),
  (constName: '_chemistryIt', identifier: 'chemistry', enumValue: 'chemistry'),
  (constName: '_biologyIt', identifier: 'biology', enumValue: 'biology'),
  (constName: '_medicineIt', identifier: 'medicine', enumValue: 'medicine'),
  (constName: '_lawIt', identifier: 'law', enumValue: 'law'),
  (constName: '_economicsIt', identifier: 'economics', enumValue: 'economics'),
  (constName: '_philosophyIt', identifier: 'philosophy', enumValue: 'philosophy'),
  (constName: '_historyIt', identifier: 'history', enumValue: 'history'),
  (constName: '_genericIt', identifier: 'generic', enumValue: 'generic'),
];

const String _itSourcePath =
    'lib/src/ai/exam/pedagogy/discipline_hints_exam_it.dart';
const String _bootstrapOutputPath =
    'lib/src/ai/exam/pedagogy/discipline_hints_exam_bootstrap.dart';

String _extractStringLiteral(String fileContent, String constName) {
  final pattern = RegExp(
    "const\\s+String\\s+$constName\\s*=\\s*'''([\\s\\S]*?)''';",
  );
  final match = pattern.firstMatch(fileContent);
  if (match == null) {
    throw StateError(
        'Could not find const String $constName in $_itSourcePath');
  }
  return match.group(1)!;
}

String _buildDisciplinePrompt({
  required String langName,
  required String identifier,
  required String itCell,
}) {
  return '''
You are translating a short Italian Exam pedagogy discipline-hint block to $langName.

This is a SHORT (~200-700 chars) hint paragraph injected into the per-call
payload of the Exam question-generation phase. Your job is STRICT
translation: same length, same tone, same structure.

RULES:
- Keep the leading "DISCIPLINA: ..." marker (translate "DISCIPLINA" into
  $langName conventional form, e.g. "DISCIPLINA" Spanish, "DISCIPLINE" French,
  "分野" Japanese, "التخصص" Arabic).
- Keep the Bloom-level structure verbatim: "Verbi Bloom-Apply:", "Verbi
  Bloom-Analyze:", "Verbi Bloom-Evaluate:". Translate the noun "Verbi" into
  $langName but keep "Bloom-Apply/Analyze/Evaluate" as English technical
  terms (they are universal Bloom taxonomy levels).
- Translate ALL discipline-specific verbs (calcola/predici/applica/etc) and
  scenarios (piano inclinato, urti elastici, etc) idiomatically into $langName.
- DO NOT add new sections, examples, or pedagogical advice the source
  doesn't contain.
- DO NOT expand the content. Output should be approximately the same
  length as the source (target: ≤1.5× source length).
- Translate idiomatically, NO calques from Italian.

PHASE: discipline hint for $identifier

ITALIAN SOURCE:
$itCell

$langName TRANSLATION (strict, no expansion, preserve Bloom-Apply/Analyze/Evaluate markers):''';
}

String _escapeForDartTripleQuote(String s) {
  return s.replaceAll(r'\', r'\\').replaceAll(r'$', r'\$');
}

Future<String> _translateCell({
  required GenerativeModel model,
  required String itCell,
  required String langCode,
  required String langName,
  required String identifier,
}) async {
  print('  → translating "$identifier" to $langName...');
  final prompt = _buildDisciplinePrompt(
    langName: langName,
    identifier: identifier,
    itCell: itCell,
  );
  final response = await model.generateContent([Content.text(prompt)]);
  final text = response.text?.trim() ?? '';
  if (text.isEmpty) {
    throw StateError(
        'Empty translation for $langCode/$identifier (Gemini returned no text)');
  }
  // Sanity: discipline marker must survive translation. We check for
  // "Bloom-Apply" verbatim (universal English token preserved across langs).
  if (!text.contains('Bloom-Apply')) {
    print('    ⚠️ WARNING: $langCode/$identifier missing Bloom-Apply marker. '
        'Runtime will fall back to EN cell.');
  }
  final lengthRatio = text.length / itCell.length;
  if (lengthRatio > 1.8) {
    print('    ⚠️ WARNING: $langCode/$identifier is '
        '${lengthRatio.toStringAsFixed(1)}× larger than IT source — '
        'model may have auto-expanded.');
  }
  return text;
}

Future<void> main(List<String> args) async {
  final apiKey = Platform.environment['GEMINI_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    stderr.writeln('❌ GEMINI_API_KEY env var is required.');
    exit(1);
  }

  final dryRun = args.contains('--dry-run');
  final langArg =
      args.firstWhere((a) => !a.startsWith('--'), orElse: () => '');
  final selectedLangs = langArg.isEmpty
      ? _targetLanguages.keys.toList()
      : langArg.split(',').map((s) => s.trim()).toList();

  for (final code in selectedLangs) {
    if (!_targetLanguages.containsKey(code)) {
      stderr.writeln('❌ Unknown language code: "$code". '
          'Valid: ${_targetLanguages.keys.join(", ")}');
      exit(1);
    }
  }

  print(selectedLangs.length == _targetLanguages.length
      ? '🌍 Full discipline hint bootstrap: 14 langs × 10 disciplines = 140 calls'
      : '🌍 Partial bootstrap: ${selectedLangs.length} lang(s) — '
          '${selectedLangs.join(", ")}${dryRun ? " (DRY RUN)" : ""}');

  print('🌍 Reading IT source-of-truth ($_itSourcePath)...');
  final itSrc = await File(_itSourcePath).readAsString();
  final itCells = <String, String>{};
  for (final disc in _disciplines) {
    itCells[disc.identifier] =
        _extractStringLiteral(itSrc, disc.constName);
  }
  print('  ✓ Loaded ${itCells.length} discipline cells from IT source');

  final model = GenerativeModel(
    model: 'gemini-2.5-flash',
    apiKey: apiKey,
    generationConfig: GenerationConfig(temperature: 0.3),
  );

  // results[lang][discipline_identifier] = translated string
  final results = <String, Map<String, String>>{};

  for (final code in selectedLangs) {
    final langName = _targetLanguages[code]!;
    print('🌐 Translating discipline cells to $langName ($code)...');
    results[code] = {};
    for (final disc in _disciplines) {
      try {
        final translated = await _translateCell(
          model: model,
          itCell: itCells[disc.identifier]!,
          langCode: code,
          langName: langName,
          identifier: disc.identifier,
        );
        results[code]![disc.identifier] = translated;
      } catch (e) {
        print('  ⚠️ Failed to translate ${disc.identifier} to $langName: $e');
      }
    }
  }

  if (dryRun) {
    print('\n🌵 Dry-run complete. Sample for first lang:');
    final firstLang = results.keys.firstOrNull;
    if (firstLang != null) {
      for (final entry in results[firstLang]!.entries) {
        print('  [$firstLang/${entry.key}]: '
            '${entry.value.substring(0, entry.value.length.clamp(0, 150))}...');
      }
    }
    return;
  }

  // Write output file.
  final out = StringBuffer();
  out.writeln('// ============================================================================');
  out.writeln('// 🌍 ExamDisciplineHintsBootstrap — AI-translated Exam discipline hints');
  out.writeln('// for the 14 Tier-1/2 bootstrap languages.');
  out.writeln('//');
  out.writeln('// Generated by `tool/bootstrap_exam_discipline_hints.dart` on ${DateTime.now().toIso8601String()}.');
  out.writeln('// Source-of-truth: IT cells in `discipline_hints_exam_it.dart`. Model: gemini-2.5-flash.');
  out.writeln('//');
  out.writeln('// Status: `ai_bootstrap` per docs/socratic_native_validation_protocol.md.');
  out.writeln('// ============================================================================');
  out.writeln();
  out.writeln("import '../../../canvas/ai/socratic/socratic_discipline.dart';");
  out.writeln();
  out.writeln('const Map<String, Map<Discipline, String>> _bootstrapExamDisciplineHints = {');
  for (final code in results.keys) {
    if (results[code]!.isEmpty) continue;
    out.writeln("  '$code': {");
    for (final entry in results[code]!.entries) {
      final escaped = _escapeForDartTripleQuote(entry.value);
      out.writeln('    Discipline.${entry.key}: \'\'\'$escaped\'\'\',');
    }
    out.writeln('  },');
  }
  out.writeln('};');
  out.writeln();
  out.writeln('String? bootstrapExamDisciplineHintsFor(');
  out.writeln('        Discipline discipline, String langCode) =>');
  out.writeln('    _bootstrapExamDisciplineHints[langCode]?[discipline];');

  await File(_bootstrapOutputPath).writeAsString(out.toString());
  print('\n✅ Wrote $_bootstrapOutputPath');
  final cellCount = results.values
      .fold<int>(0, (sum, m) => sum + m.length);
  print('   $cellCount cells (${selectedLangs.length} langs × '
      '${_disciplines.length} disciplines)');
}
