// ignore_for_file: avoid_print
/// ═══════════════════════════════════════════════════════════════════════════
/// 🌍 CHAT PEDAGOGY BOOTSTRAP — IT → 14 lang translator (Sprint Chat-C)
///
/// One-shot script that uses Gemini 2.5 Flash to translate the hand-written
/// Italian Chat cell (source-of-truth in `chat_pedagogy_it.dart`) into the
/// 14 Tier-1/2 target languages. Output replaces the placeholder map in
/// `lib/src/ai/chat/pedagogy/chat_pedagogy_bootstrap.dart`.
///
/// USAGE:
///   cd fluera_engine
///   # Full bootstrap (all 14 langs = 14 calls)
///   GEMINI_API_KEY=sk-xxx dart run tool/bootstrap_chat_cells.dart
///
///   # Subset
///   GEMINI_API_KEY=sk-xxx dart run tool/bootstrap_chat_cells.dart es,fr
///
///   # Dry-run
///   GEMINI_API_KEY=sk-xxx dart run tool/bootstrap_chat_cells.dart es --dry-run
///
/// COST: ~$0.03 on Flash (14 calls × ~1500 tokens). Likely $0 on free tier.
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

const String _itSourcePath =
    'lib/src/ai/chat/pedagogy/chat_pedagogy_it.dart';
const String _bootstrapOutputPath =
    'lib/src/ai/chat/pedagogy/chat_pedagogy_bootstrap.dart';
const String _itConstName = 'chatPedagogyIt';

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

String _buildChatPrompt({
  required String langName,
  required String itCell,
}) {
  return '''
You are translating a Chat AI pedagogy system-prompt cell from Italian to $langName.

CRITICAL: this is a SYSTEM PROMPT given to a conversational AI assistant
("Fluera AI") embedded in a cognitive learning canvas. Translate the
CONTENT (rules, instructions, examples) into native $langName, but
PRESERVE the STRUCTURE absolutely:

- Keep ALL section headers exactly: 🛑, 🔠, 📚, 📤
- Keep the brand name "Fluera AI" verbatim in $langName (it is the
  product name, NOT to be translated)
- Keep the numbered list (1-6) of HARD RULES — same numbers, same
  semantic meaning, idiomatic $langName phrasing
- KEEP the literal token "Ghost Map" verbatim (it is a feature name)
- KEEP the literal token "Socratic" verbatim (it is a feature name —
  in some langs "Socratic" can be transliterated, e.g. ソクラテス式 JA;
  but the underlying feature name in the codebase is "Socratic")
- Translate the language directive: "Lingua di output: SEMPRE italiano"
  → "Output language: ALWAYS $langName" in native form
- Translate idiomatically, NO calques from Italian
- Adapt cultural register: T/V form, politeness level (Japanese:
  use level-2 polite form, avoid excessive keigo per arxiv 2402.14531)

DO NOT add new sections, examples, or pedagogical advice the source
doesn't contain. Translation only — no expansion.

Output ONLY the translated cell text. No commentary, no markdown
fences, no preamble.

ITALIAN SOURCE:
$itCell

$langName TRANSLATION (preserve "Fluera AI" + "Ghost Map" + "Socratic" + 🛑/🔠/📚/📤 markers):''';
}

String _escapeForDartTripleQuote(String s) {
  return s.replaceAll(r'\', r'\\').replaceAll(r'$', r'\$');
}

Future<String> _translateCell({
  required GenerativeModel model,
  required String itCell,
  required String langCode,
  required String langName,
}) async {
  print('  → translating Chat cell to $langName...');
  final prompt = _buildChatPrompt(langName: langName, itCell: itCell);
  final response = await model.generateContent([Content.text(prompt)]);
  final text = response.text?.trim() ?? '';
  if (text.isEmpty) {
    throw StateError(
        'Empty translation for $langCode (Gemini returned no text)');
  }
  // Canonical marker validation. Must preserve "Fluera AI" verbatim.
  if (!text.contains('Fluera AI')) {
    print('    ⚠️ WARNING: $langCode missing "Fluera AI" brand. '
        'Runtime will fall back to EN cell.');
  }
  final lengthRatio = text.length / itCell.length;
  if (lengthRatio > 1.8) {
    print('    ⚠️ WARNING: $langCode is '
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
      ? '🌍 Full Chat bootstrap: 14 langs × 1 cell = 14 calls'
      : '🌍 Partial bootstrap: ${selectedLangs.length} lang(s) — '
          '${selectedLangs.join(", ")}${dryRun ? " (DRY RUN)" : ""}');

  print('🌍 Reading IT source-of-truth ($_itSourcePath)...');
  final itSrc = await File(_itSourcePath).readAsString();
  final itCell = _extractStringLiteral(itSrc, _itConstName);
  print('  ✓ Loaded IT chat cell (${itCell.length} chars)');

  final model = GenerativeModel(
    model: 'gemini-2.5-flash',
    apiKey: apiKey,
    generationConfig: GenerationConfig(temperature: 0.3),
  );

  final results = <String, String>{};

  for (final code in selectedLangs) {
    final langName = _targetLanguages[code]!;
    try {
      final translated = await _translateCell(
        model: model,
        itCell: itCell,
        langCode: code,
        langName: langName,
      );
      results[code] = translated;
    } catch (e) {
      print('  ⚠️ Failed to translate to $langName: $e');
    }
  }

  if (dryRun) {
    print('\n🌵 Dry-run complete. Sample for first lang:');
    final firstLang = results.keys.firstOrNull;
    if (firstLang != null) {
      print('  [$firstLang]: '
          '${results[firstLang]!.substring(0, results[firstLang]!.length.clamp(0, 300))}...');
    }
    return;
  }

  // Write output file.
  final out = StringBuffer();
  out.writeln('// ============================================================================');
  out.writeln('// 🌍 ChatPedagogyBootstrap — AI-translated Chat cells for the 14 Tier-1/2');
  out.writeln('// bootstrap languages.');
  out.writeln('//');
  out.writeln('// Generated by `tool/bootstrap_chat_cells.dart` on ${DateTime.now().toIso8601String()}.');
  out.writeln('// Source-of-truth: IT cell in `chat_pedagogy_it.dart`. Model: gemini-2.5-flash.');
  out.writeln('//');
  out.writeln('// Status: `ai_bootstrap` per docs/socratic_native_validation_protocol.md.');
  out.writeln('// ============================================================================');
  out.writeln();
  out.writeln('const Map<String, String> _bootstrapChatCells = {');
  for (final entry in results.entries) {
    final escaped = _escapeForDartTripleQuote(entry.value);
    out.writeln("  '${entry.key}': '''$escaped''',");
  }
  out.writeln('};');
  out.writeln();
  out.writeln('String? bootstrapChatPedagogyFor(String langCode) =>');
  out.writeln('    _bootstrapChatCells[langCode];');

  await File(_bootstrapOutputPath).writeAsString(out.toString());
  print('\n✅ Wrote $_bootstrapOutputPath');
  print('   ${results.length} cells (${selectedLangs.length} langs)');
}
