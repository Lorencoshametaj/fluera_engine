// ignore_for_file: avoid_print
/// ═══════════════════════════════════════════════════════════════════════════
/// 🌍 EXAM PEDAGOGY BOOTSTRAP — IT → 14 lang translator (Sprint EX-C)
///
/// One-shot script that uses Gemini 2.5 Flash to translate the hand-written
/// Italian Exam phase cells (source-of-truth in
/// `lib/src/ai/exam/pedagogy/exam_pedagogy_it.dart`) into the 14 Tier-1/2
/// target languages. Output replaces the placeholder cells in
/// `lib/src/ai/exam/pedagogy/exam_pedagogy_bootstrap.dart`.
///
/// USAGE:
///   cd fluera_engine
///   # Full bootstrap (all 14 langs)
///   GEMINI_API_KEY=sk-xxx dart run tool/bootstrap_exam_cells.dart
///
///   # Subset (CLI lang filter)
///   GEMINI_API_KEY=sk-xxx dart run tool/bootstrap_exam_cells.dart es,fr,de
///
///   # Dry-run on 1 lang (no file write)
///   GEMINI_API_KEY=sk-xxx dart run tool/bootstrap_exam_cells.dart es --dry-run
///
/// MODEL: `gemini-2.5-flash` (same as runtime + Socratic bootstrap).
///
/// COST: ~$0.15 on Flash (14 langs × 3 phases = 42 calls). Likely $0 on
/// free tier. Far cheaper than Socratic bootstrap (238 calls) — exam has
/// only 3 phases instead of 17 stage+discipline cells.
///
/// IDEMPOTENT: re-running regenerates from the IT source. Review
/// `git diff` to spot regressions.
///
/// QUALITY: each output is flagged `ai_bootstrap` per
/// `docs/socratic_native_validation_protocol.md` (extended scope post
/// Sprint EX-G to cover Exam phases). UI banner activates for non-IT/EN
/// langs until each language graduates to `production_native` via
/// native review.
/// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:google_generative_ai/google_generative_ai.dart';

/// 14 Tier-1/2 langs. IT + EN are excluded (production_native, inline
/// in exam_pedagogy_{it,en}.dart). Mirrors the Socratic bootstrap list.
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

/// 3 ExamPhase identifiers + their IT const names.
const List<({String constName, String identifier})> _phases = [
  (constName: 'examGenerationIt', identifier: 'generation'),
  (constName: 'examEvaluationIt', identifier: 'evaluation'),
  (constName: 'examHintIt', identifier: 'hint'),
];

const String _itSourcePath =
    'lib/src/ai/exam/pedagogy/exam_pedagogy_it.dart';
const String _bootstrapOutputPath =
    'lib/src/ai/exam/pedagogy/exam_pedagogy_bootstrap.dart';

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

String _buildPhasePrompt({
  required String langName,
  required String identifier,
  required String itCell,
}) {
  return '''
You are translating an Exam pedagogy system-prompt cell from Italian to $langName.

CRITICAL: this is a SYSTEM PROMPT given to an AI exam designer (or grader, or hinter — see ROLE below). Translate the CONTENT (rules, instructions, examples) into native $langName, but PRESERVE the STRUCTURE absolutely:
- Keep ALL section headers exactly: 🎓, 🎯, 📐, 🎲, 🚫, 📚, 🔠, 📤, ⚖️, 🛑 (and any others)
- Keep ALL anti-pattern lists (the bullet points after 🚫)
- **KEEP THE OUTPUT BLOCK STRUCTURE VERBATIM**:
  - For phase "generation": the JSON template starting with `{"domande": [...]}` MUST survive intact (key names "domande", "tipo", "domanda", "risposta_corretta", "spiegazione", "scelte", "indice_corretto", "cluster_id", "testo_sorgente" stay in their Italian form — they are the wire protocol fields).
  - For phase "evaluation": the rigid 2-line format `VOTO: [CORRETTO | PARZIALE | SBAGLIATO]` + `FEEDBACK: [...]` MUST survive intact. Words "VOTO", "FEEDBACK", "CORRETTO", "PARZIALE", "SBAGLIATO" stay in Italian — they are the wire protocol values.
  - For phase "hint": the maximum word constraint `12 parole` → translate to "12 words" / "12 mots" / native equivalent, but the digit 12 MUST appear verbatim.
- Keep references to pedagogical authors (Bloom, Anderson, Krathwohl, Dweck, Hattie, Vygotsky, Kapur, etc.)
- Translate idiomatically, NO calques from Italian
- Adapt cultural register: T/V form, politeness level (Japanese: use level-2 polite form, avoid excessive keigo)
- Translate the language directive into $langName (e.g. "Rispondi SOLO in italiano" → "Answer ONLY in $langName" in native form)

DO NOT add new sections, comments, examples, or pedagogical advice the source does not contain. Translation only — no expansion.

Output ONLY the translated cell text. No commentary, no markdown fences, no preamble.

PHASE: $identifier

ITALIAN SOURCE:
$itCell

$langName TRANSLATION (preserve OUTPUT block protocol verbatim):''';
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
  final prompt = _buildPhasePrompt(
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
  // Per-phase canonical marker validation. See registry._isCellComplete.
  bool markerOk;
  switch (identifier) {
    case 'generation':
      markerOk = text.contains('"domande"');
      break;
    case 'evaluation':
      markerOk = text.contains('VOTO:');
      break;
    case 'hint':
      markerOk = text.contains('12');
      break;
    default:
      markerOk = true;
  }
  if (!markerOk) {
    print('    ⚠️ WARNING: $langCode/$identifier missing canonical marker. '
        'Runtime will fall back to EN cell.');
  }
  final lengthRatio = text.length / itCell.length;
  if (lengthRatio > 1.8) {
    print('    ⚠️ WARNING: $langCode/$identifier is '
        '${lengthRatio.toStringAsFixed(1)}× larger than IT source — '
        'model may have auto-expanded the prompt.');
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
      ? '🌍 Full Exam bootstrap: translating to all 14 languages'
      : '🌍 Partial Exam bootstrap: ${selectedLangs.length} lang(s) — '
          '${selectedLangs.join(", ")}${dryRun ? " (DRY RUN)" : ""}');

  print('🌍 Reading IT source-of-truth ($_itSourcePath)...');
  final itSrc = await File(_itSourcePath).readAsString();
  final itCells = <String, String>{};
  for (final phase in _phases) {
    itCells[phase.identifier] =
        _extractStringLiteral(itSrc, phase.constName);
  }
  print('  ✓ Loaded ${itCells.length} phase cells from IT source');

  final model = GenerativeModel(
    model: 'gemini-2.5-flash',
    apiKey: apiKey,
    generationConfig: GenerationConfig(temperature: 0.3),
  );

  // results[lang][phase_identifier] = translated string
  final results = <String, Map<String, String>>{};

  for (final code in selectedLangs) {
    final langName = _targetLanguages[code]!;
    print('🌐 Translating Exam cells to $langName ($code)...');
    results[code] = {};
    for (final phase in _phases) {
      try {
        final translated = await _translateCell(
          model: model,
          itCell: itCells[phase.identifier]!,
          langCode: code,
          langName: langName,
          identifier: phase.identifier,
        );
        results[code]![phase.identifier] = translated;
      } catch (e) {
        print('  ⚠️ Failed to translate ${phase.identifier} to $langName: $e');
        // Skip this phase for this lang → registry falls back to EN.
      }
    }
  }

  if (dryRun) {
    print('\n🌵 Dry-run complete. Sample for first lang:');
    final firstLang = results.keys.firstOrNull;
    if (firstLang != null) {
      for (final entry in results[firstLang]!.entries) {
        print('  [$firstLang/${entry.key}]: '
            '${entry.value.substring(0, entry.value.length.clamp(0, 200))}...');
      }
    }
    return;
  }

  // Write output file.
  final out = StringBuffer();
  out.writeln('// ============================================================================');
  out.writeln('// 🌍 ExamPedagogyBootstrap — AI-translated Exam phase cells for the 14');
  out.writeln('// Tier-1/2 bootstrap languages.');
  out.writeln('//');
  out.writeln('// Generated by `tool/bootstrap_exam_cells.dart` on ${DateTime.now().toIso8601String()}.');
  out.writeln('// Source-of-truth: IT cells in `exam_pedagogy_it.dart`. Model: gemini-2.5-flash.');
  out.writeln('//');
  out.writeln('// Status: `ai_bootstrap` per docs/socratic_native_validation_protocol.md.');
  out.writeln('// ============================================================================');
  out.writeln();
  out.writeln("import 'exam_phase.dart';");
  out.writeln();
  out.writeln('const Map<String, Map<ExamPhase, String>> _bootstrapExamCells = {');
  for (final code in results.keys) {
    if (results[code]!.isEmpty) continue;
    out.writeln("  '$code': {");
    for (final entry in results[code]!.entries) {
      final phaseEnumName = entry.key; // 'generation' | 'evaluation' | 'hint'
      final escaped = _escapeForDartTripleQuote(entry.value);
      out.writeln('    ExamPhase.$phaseEnumName: \'\'\'$escaped\'\'\',');
    }
    out.writeln('  },');
  }
  out.writeln('};');
  out.writeln();
  out.writeln('String? bootstrapExamPedagogyFor(ExamPhase phase, String langCode) =>');
  out.writeln('    _bootstrapExamCells[langCode]?[phase];');

  await File(_bootstrapOutputPath).writeAsString(out.toString());
  print('\n✅ Wrote $_bootstrapOutputPath');
  final cellCount = results.values
      .fold<int>(0, (sum, m) => sum + m.length);
  print('   $cellCount cells (${selectedLangs.length} langs × '
      '${_phases.length} phases)');
}
