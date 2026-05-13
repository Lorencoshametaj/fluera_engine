// ignore_for_file: avoid_print
/// ═══════════════════════════════════════════════════════════════════════════
/// 🌍 SOCRATIC PEDAGOGY BOOTSTRAP — IT → 14 lang translator (Sprint F.2)
///
/// One-shot script that uses Gemini Pro 1.5 to translate the hand-written
/// Italian pedagogy cells (source-of-truth) into the 14 Tier-1/2 target
/// languages. Output replaces the placeholder cells in
/// `lib/src/ai/socratic/pedagogy/stage_pedagogy_bootstrap.dart` and
/// `discipline_hints_bootstrap.dart`.
///
/// USAGE:
///   cd fluera_engine
///   # Full bootstrap (all 14 langs)
///   GEMINI_API_KEY=sk-xxx dart run tool/bootstrap_pedagogy_cells.dart
///
///   # Dry-run on 1 lang (safety check before full run)
///   GEMINI_API_KEY=sk-xxx dart run tool/bootstrap_pedagogy_cells.dart es
///
///   # Specific subset
///   GEMINI_API_KEY=sk-xxx dart run tool/bootstrap_pedagogy_cells.dart es,fr,de
///
/// MODEL: `gemini-2.5-flash` (same as production runtime). Free tier
/// supports ~1500 RPD which covers the 238 calls easily. For higher-stakes
/// translation upgrade to `gemini-2.5-pro` (10x cost, ~10% quality bump).
///
/// COST: ~$0.50 on Flash (14 langs × 17 cells = 238 calls, ~2000 input
/// tokens + ~3000 output per call). Likely $0 on free tier.
///
/// IDEMPOTENT: re-running regenerates from the IT source — outputs are
/// not appended, they're replaced. Review `git diff` to spot regressions.
///
/// QUALITY: every output is flagged `ai_bootstrap` per
/// `docs/socratic_native_validation_protocol.md`. UI shows the banner
/// "AI-translated questions in $lang — feedback welcome" until each
/// language graduates to `production_native` via native review.
/// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:google_generative_ai/google_generative_ai.dart';

/// Target languages (14 — IT + EN are excluded; they're production_native
/// hand-written cells). Mirrors `AiLanguagePreference._supportedLanguages`
/// minus 'it' and 'en'.
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

/// 7 SocraticStage names + identifiers used in the IT source file.
const List<({String constName, String identifier})> _stages = [
  (constName: 'anchorStagePedagogyIt', identifier: 'anchor'),
  (constName: 'elaborationStagePedagogyIt', identifier: 'elaboration'),
  (constName: 'comparativeStagePedagogyIt', identifier: 'comparative'),
  (constName: 'counterfactualStagePedagogyIt', identifier: 'counterfactual'),
  (constName: 'applicationStagePedagogyIt', identifier: 'application'),
  (constName: 'interleaveStagePedagogyIt', identifier: 'interleave'),
  (constName: 'metacognitiveStagePedagogyIt', identifier: 'metacognitive'),
];

/// 10 Discipline names + the IT source const names from
/// `discipline_hints_it.dart`. The constants there use `_physicsIt` etc.
/// (private), so we read the FILE TEXT and parse the const bodies via a
/// simple regex on the string literal.
const List<({String constName, String identifier})> _disciplines = [
  (constName: '_physicsIt', identifier: 'physics'),
  (constName: '_mathIt', identifier: 'math'),
  (constName: '_chemistryIt', identifier: 'chemistry'),
  (constName: '_biologyIt', identifier: 'biology'),
  (constName: '_medicineIt', identifier: 'medicine'),
  (constName: '_lawIt', identifier: 'law'),
  (constName: '_economicsIt', identifier: 'economics'),
  (constName: '_philosophyIt', identifier: 'philosophy'),
  (constName: '_historyIt', identifier: 'history'),
  (constName: '_genericIt', identifier: 'generic'),
];

const String _sourceStageFile =
    'lib/src/ai/socratic/pedagogy/stage_pedagogy_it.dart';
const String _sourceDisciplineFile =
    'lib/src/ai/socratic/pedagogy/discipline_hints_it.dart';
// 🌍 Both stage cells AND discipline cells live in the SAME output file
// (`stage_pedagogy_bootstrap.dart`) — this preserves the existing
// `pedagogy_registry.dart` import contract, which expects both
// `bootstrapStagePedagogy` and `bootstrapDisciplineHints` from one
// module. Splitting would require touching the registry.
const String _outputFile =
    'lib/src/ai/socratic/pedagogy/stage_pedagogy_bootstrap.dart';

/// Reads a triple-quoted string literal from Dart source. Pattern:
/// `const String NAME = '''...''';` — captures the `...` body.
/// Throws if the const isn't found (helps the script fail loud).
String _extractStringLiteral(String fileContent, String constName) {
  // Match: const String <name> = '''<body>''';
  // Use dotAll: true so . matches newlines.
  final pattern = RegExp(
    "const\\s+String\\s+$constName\\s*=\\s*'''([\\s\\S]*?)''';",
  );
  final match = pattern.firstMatch(fileContent);
  if (match == null) {
    throw StateError(
        'Could not find const String $constName in source file');
  }
  return match.group(1)!;
}

/// Stage-cell prompt: full Socratic system prompt translation. Preserves
/// all sections (headers, anti-patterns, JSON output format).
String _buildStagePrompt(String langName, String itCell) {
  return '''
You are translating a Socratic pedagogy system-prompt cell from Italian to $langName.

CRITICAL: this is a SYSTEM PROMPT given to an AI tutor. Translate the CONTENT (rules, instructions, examples) into native $langName, but PRESERVE the STRUCTURE absolutely:
- Keep ALL section headers exactly: 🎯, 📐, 🚫, 🛑, 📤, 🍞, 🔠, 🌍 (and any others)
- Keep ALL anti-pattern lists (the bullet points after 🚫)
- **KEEP THE JSON OUTPUT BLOCK VERBATIM** — the section starting "📤 OUTPUT" with the literal JSON template `{"q":"<...>","h":["<...>","<...>","<...>"]}`. The model NEEDS this template to know the output shape. Only translate the placeholder LABELS inside <...> brackets, keep the JSON structure intact.
- Keep references to pedagogical authors (Bjork, Dunlosky, Chi, etc.)
- Translate idiomatically, NO calques from Italian
- Adapt cultural register: T/V form, politeness level (for Japanese: use level-2 polite form, AVOID excessive keigo per arxiv 2402.14531)
- Translate the language directive into $langName (e.g. "Rispondi in italiano" → native equivalent in $langName)

DO NOT add new sections, comments, examples, or pedagogical advice the source does not contain. Translation only — no expansion.

Output ONLY the translated cell text. No commentary, no markdown fences, no preamble.

ITALIAN SOURCE:
$itCell

$langName TRANSLATION (preserve 📤 OUTPUT JSON block verbatim):''';
}

/// Discipline-cell prompt: short pedagogy hint translation. STRICT
/// translation only — no expansion, no extra sections.
String _buildDisciplinePrompt(String langName, String itCell) {
  return '''
You are translating a short Italian pedagogy hint (about a specific academic discipline) into $langName.

This is NOT a full system prompt — it is a SHORT (~200 chars) hint paragraph that gets injected into other prompts. Your job is STRICT translation: same length, same tone, same structure.

RULES:
- Keep the leading "DISCIPLINA: ..." marker (translate "DISCIPLINA" into $langName conventional form, e.g. Spanish "DISCIPLINA", French "DISCIPLINE", Japanese "分野", Arabic "التخصص").
- Translate every line of the source. Output should have ROUGHLY THE SAME NUMBER OF LINES as the source.
- DO NOT add new sections (no "OBJETIVO", no "ESTRATEGIA", no "🎯 GOAL", no extra emoji headers, nothing the source doesn't have).
- DO NOT expand the content. If the source says "Verbi tipici: prevedi, disegna...", the output is "Verbs typical: <translated verbs>". Period.
- DO NOT add pedagogical metadata or system-prompt boilerplate.
- Translate idiomatically (no calques from Italian).
- Output should be approximately the same length as the source.

Output ONLY the translated hint text. No commentary, no preamble, no extra sections.

ITALIAN SOURCE:
$itCell

$langName TRANSLATION (strict, no expansion):''';
}

/// Escape a Dart triple-quoted string body for safe embedding.
String _escapeForDartTripleQuote(String s) {
  // Triple-single-quote strings still allow `\$` for dollar signs and
  // backticks. The body may contain `'''` rarely, so we use raw string
  // wrapping only if needed. For safety, escape `\` and `$` first.
  return s.replaceAll(r'\', r'\\').replaceAll(r'$', r'\$');
}

enum _CellKind { stage, discipline }

Future<String> _translateCell({
  required GenerativeModel model,
  required String itCell,
  required String langCode,
  required String langName,
  required String identifier,
  required _CellKind kind,
}) async {
  print('  → translating "$identifier" to $langName...');
  final prompt = switch (kind) {
    _CellKind.stage => _buildStagePrompt(langName, itCell),
    _CellKind.discipline => _buildDisciplinePrompt(langName, itCell),
  };
  final response = await model.generateContent([Content.text(prompt)]);
  final text = response.text?.trim() ?? '';
  if (text.isEmpty) {
    throw StateError(
        'Empty translation for $langCode/$identifier (Gemini returned no text)');
  }
  // Sanity validation: differs by cell kind.
  switch (kind) {
    case _CellKind.stage:
      // Stage cells MUST preserve the JSON output template `{"q":...,"h":[...]}`.
      // The runtime parser needs that template to know what shape to emit.
      if (!text.contains('"q"') || !text.contains('"h"')) {
        print('    ⚠️ WARNING: stage cell for $langCode/$identifier is '
            'missing JSON output template. Output may be malformed.');
      }
      // Also bloat check: source vs translation length ratio.
      final lengthRatio = text.length / itCell.length;
      if (lengthRatio > 1.8) {
        print('    ⚠️ WARNING: stage cell for $langCode/$identifier is '
            '${lengthRatio.toStringAsFixed(1)}x larger than source — model '
            'may have auto-expanded the prompt.');
      }
      break;
    case _CellKind.discipline:
      // Discipline modules are short pedagogy hints. They should NOT have
      // the JSON template (that's a stage-cell artifact). Instead they
      // start with a "DISCIPLINA: ..." (or translated equivalent) marker.
      // Bloat check is critical here — Flash tends to add Socratic
      // boilerplate ("OBJETIVO", "ESTRATEGIA") that the source lacks.
      final lengthRatio = text.length / itCell.length;
      if (lengthRatio > 1.5) {
        print('    ⚠️ WARNING: discipline cell for $langCode/$identifier '
            'is ${lengthRatio.toStringAsFixed(1)}x larger than source '
            '(${itCell.length}→${text.length} chars) — model may have '
            'auto-expanded the hint. Re-running may help.');
      }
      break;
  }
  return text;
}

/// Writes BOTH stage cells AND discipline cells into a single output file
/// (`stage_pedagogy_bootstrap.dart`) — matches the existing
/// `pedagogy_registry.dart` import contract that expects both
/// dispatcher functions from this one module.
Future<void> _writeCombinedOutput({
  required Map<String, Map<String, String>> stageByLang,
  required Map<String, Map<String, String>> disciplineByLang,
}) async {
  final buf = StringBuffer();
  buf.writeln('// 🤖 AUTO-GENERATED by tool/bootstrap_pedagogy_cells.dart');
  buf.writeln('// DO NOT EDIT BY HAND — regenerate via:');
  buf.writeln('//   GEMINI_API_KEY=xxx dart run tool/bootstrap_pedagogy_cells.dart');
  buf.writeln('//');
  buf.writeln('// Generated: ${DateTime.now().toIso8601String()}');
  buf.writeln('// Source-of-truth: stage_pedagogy_it.dart + discipline_hints_it.dart');
  buf.writeln('// (hand-written, IT native). Status: ai_bootstrap per');
  buf.writeln('// docs/socratic_native_validation_protocol.md. UI banner remains');
  buf.writeln('// active for these languages until they graduate via native review.');
  buf.writeln('// Languages: ${_targetLanguages.keys.join(", ")}');
  buf.writeln();
  buf.writeln(
      "import '../../../canvas/ai/socratic/socratic_model.dart' "
      "show Discipline, SocraticStage;");
  buf.writeln();

  // ── Stage cells ────────────────────────────────────────────────────────
  buf.writeln(
      '/// AI-translated stage pedagogy cells, indexed by (langCode, stage).');
  buf.writeln(
      'const Map<String, Map<SocraticStage, String>> _bootstrapStageCells = {');
  for (final lang in _targetLanguages.entries) {
    final cells = stageByLang[lang.key]!;
    buf.writeln("  '${lang.key}': {");
    for (final stage in _stages) {
      final body = _escapeForDartTripleQuote(cells[stage.identifier]!);
      buf.writeln("    SocraticStage.${stage.identifier}: '''");
      buf.write(body);
      buf.writeln("''',");
    }
    buf.writeln('  },');
  }
  buf.writeln('};');
  buf.writeln();
  buf.writeln(
      'String bootstrapStagePedagogy(SocraticStage stage, String langCode) {');
  buf.writeln(
      "  return _bootstrapStageCells[langCode]?[stage] ?? _bootstrapStageCells['es']![stage]!;");
  buf.writeln('}');
  buf.writeln();

  // ── Discipline cells ───────────────────────────────────────────────────
  buf.writeln(
      '/// AI-translated discipline hint modules, indexed by (langCode, discipline).');
  buf.writeln(
      'const Map<String, Map<Discipline, String>> _bootstrapDisciplineHints = {');
  for (final lang in _targetLanguages.entries) {
    final cells = disciplineByLang[lang.key]!;
    buf.writeln("  '${lang.key}': {");
    for (final disc in _disciplines) {
      final body = _escapeForDartTripleQuote(cells[disc.identifier]!);
      buf.writeln("    Discipline.${disc.identifier}: '''");
      buf.write(body);
      buf.writeln("''',");
    }
    buf.writeln('  },');
  }
  buf.writeln('};');
  buf.writeln();
  buf.writeln(
      'String bootstrapDisciplineHints(Discipline d, String langCode) {');
  buf.writeln(
      "  return _bootstrapDisciplineHints[langCode]?[d] ?? _bootstrapDisciplineHints['es']![d]!;");
  buf.writeln('}');

  final file = File(_outputFile);
  await file.writeAsString(buf.toString());
  print('✅ Wrote $_outputFile (${stageByLang.length} languages, '
      '${_stages.length} stages + ${_disciplines.length} disciplines)');
}

Future<void> main(List<String> args) async {
  final apiKey = Platform.environment['GEMINI_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    stderr.writeln('ERROR: set GEMINI_API_KEY env var before running.');
    stderr.writeln('  GEMINI_API_KEY=sk-xxx dart run tool/bootstrap_pedagogy_cells.dart');
    exit(1);
  }

  // CLI lang filter: `dart run ... es` for dry-run on Spanish only,
  // `... es,fr,de` for a subset. No arg = all 14 langs.
  final Map<String, String> langsToTranslate;
  if (args.isNotEmpty) {
    final requested = args.first.split(',').map((s) => s.trim()).toSet();
    final filtered = <String, String>{};
    final unknown = <String>[];
    for (final code in requested) {
      if (_targetLanguages.containsKey(code)) {
        filtered[code] = _targetLanguages[code]!;
      } else {
        unknown.add(code);
      }
    }
    if (unknown.isNotEmpty) {
      stderr.writeln(
          'ERROR: unknown lang code(s): ${unknown.join(", ")}. '
          'Supported: ${_targetLanguages.keys.join(", ")}');
      exit(1);
    }
    if (filtered.isEmpty) {
      stderr.writeln('ERROR: no valid langs in arg "${args.first}"');
      exit(1);
    }
    langsToTranslate = filtered;
    print('🎯 Dry-run filter: translating only '
        '${filtered.keys.join(", ")} (${filtered.length} langs)');
    print('   ⚠️  Output will REPLACE the existing bootstrap file. Make sure '
        'to commit/stash before running on a partial set, or re-run with '
        'no args after to generate the full 14 langs.');
  } else {
    langsToTranslate = _targetLanguages;
    print('🌍 Full bootstrap: translating to all '
        '${_targetLanguages.length} languages');
  }

  print('🌍 Reading IT source-of-truth cells...');
  final stageFileContent = await File(_sourceStageFile).readAsString();
  final disciplineFileContent =
      await File(_sourceDisciplineFile).readAsString();

  final itStageCells = <String, String>{
    for (final s in _stages)
      s.identifier: _extractStringLiteral(stageFileContent, s.constName),
  };
  final itDisciplineCells = <String, String>{
    for (final d in _disciplines)
      d.identifier:
          _extractStringLiteral(disciplineFileContent, d.constName),
  };
  print('  ✓ Loaded ${_stages.length} stage cells + '
      '${_disciplines.length} discipline cells from IT source');

  // Build the Gemini client. Direct mode (no proxy) — this is a one-shot
  // CLI tool, not production runtime. Using `gemini-2.5-flash` (same as
  // production runtime) keeps the cost low (~$0.50 total vs ~$5 for Pro)
  // and matches the model that will SERVE the translated cells at
  // session time. ai_bootstrap status flag means a native validation
  // review is still required before each lang graduates to
  // production_native, regardless of which model translates.
  final model = GenerativeModel(
    model: 'gemini-2.5-flash',
    apiKey: apiKey,
    generationConfig: GenerationConfig(
      temperature: 0.3, // low for translation fidelity
      maxOutputTokens: 4000,
    ),
  );

  // Translate stage cells
  final stageCellsByLang = <String, Map<String, String>>{};
  for (final lang in langsToTranslate.entries) {
    print('🌐 Translating stage cells to ${lang.value} (${lang.key})...');
    final translated = <String, String>{};
    for (final stage in _stages) {
      final itCell = itStageCells[stage.identifier]!;
      try {
        final translatedCell = await _translateCell(
          model: model,
          itCell: itCell,
          langCode: lang.key,
          langName: lang.value,
          identifier: stage.identifier,
          kind: _CellKind.stage,
        );
        translated[stage.identifier] = translatedCell;
      } catch (e) {
        stderr.writeln(
            '⚠️ Failed to translate ${stage.identifier} to ${lang.value}: $e');
        // Fallback: store the IT source as placeholder. The bootstrap
        // path's runtime fallback in pedagogy_registry will handle it.
        translated[stage.identifier] = itCell;
      }
    }
    stageCellsByLang[lang.key] = translated;
  }

  // Translate discipline cells
  final disciplineCellsByLang = <String, Map<String, String>>{};
  for (final lang in langsToTranslate.entries) {
    print('🌐 Translating discipline hints to ${lang.value} (${lang.key})...');
    final translated = <String, String>{};
    for (final disc in _disciplines) {
      final itCell = itDisciplineCells[disc.identifier]!;
      try {
        final translatedCell = await _translateCell(
          model: model,
          itCell: itCell,
          langCode: lang.key,
          langName: lang.value,
          identifier: disc.identifier,
          kind: _CellKind.discipline,
        );
        translated[disc.identifier] = translatedCell;
      } catch (e) {
        stderr.writeln(
            '⚠️ Failed to translate ${disc.identifier} to ${lang.value}: $e');
        translated[disc.identifier] = itCell;
      }
    }
    disciplineCellsByLang[lang.key] = translated;
  }

  // Dry-run mode (partial lang set) → print samples to stdout, NO file
  // write. Protects the existing full bootstrap file from being
  // overwritten by a partial run.
  final isDryRun = langsToTranslate.length < _targetLanguages.length;
  if (isDryRun) {
    print('');
    print('🔍 DRY-RUN MODE — output sample below (NO FILE WRITTEN).');
    print('   To commit, re-run with NO args (all 14 langs).');
    print('   To check quality, eyeball one of each language\'s cells:');
    print('');
    for (final lang in stageCellsByLang.entries) {
      print('─── ${langsToTranslate[lang.key]} (${lang.key}) — anchor stage ───');
      final anchor = lang.value['anchor'] ?? '(missing)';
      // Print first 800 chars to avoid flooding terminal.
      final preview = anchor.length > 800 ? '${anchor.substring(0, 800)}...' : anchor;
      print(preview);
      print('');
    }
    for (final lang in disciplineCellsByLang.entries) {
      print('─── ${langsToTranslate[lang.key]} (${lang.key}) — physics discipline ───');
      print(lang.value['physics'] ?? '(missing)');
      print('');
    }
    print('🔍 DRY-RUN complete. Review samples above. If quality OK, run the '
        'FULL bootstrap (no args).');
  } else {
    // Full run: write outputs (both maps in a single file).
    await _writeCombinedOutput(
      stageByLang: stageCellsByLang,
      disciplineByLang: disciplineCellsByLang,
    );
  }

  print('');
  print('✅ Bootstrap complete: ${_targetLanguages.length} languages × '
      '(${_stages.length} stages + ${_disciplines.length} disciplines) cells generated.');
  print('Review: `git diff lib/src/ai/socratic/pedagogy/`');
  print('Spot-check 3-4 random cells for sanity (ES counterfactual, JA anchor, AR application).');
}
