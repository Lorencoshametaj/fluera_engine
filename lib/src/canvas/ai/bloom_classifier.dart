// ============================================================================
// 🧠 BLOOM CLASSIFIER — Verb-key heuristic for question cognitive depth
//
// Bloom's Taxonomy (revised, Anderson & Krathwohl 2001) ranks cognitive
// processes from shallow to deep:
//
//   1. Remember   — recall facts, definitions, lists.
//   2. Understand — explain, paraphrase, summarize.
//   3. Apply      — use a procedure in a new context, calculate, solve.
//   4. Analyze    — compare, distinguish, decompose, categorize.
//   5. Evaluate   — judge, justify, critique, defend.
//   6. Create     — design, construct, propose, generate.
//
// We use this taxonomy to validate the questions Gemini produces. The prompt
// in `atlas_ai_service.dart` claims to map difficulty → Bloom level, but
// nothing currently verifies the output. Without a check, the LLM tends to
// regress to "Remember" (the easiest tokens to predict), which produces
// pedagogically useless exams (Roediger & Karpicke 2006: passive recognition
// produces no measurable retention gain).
//
// This file implements a small classifier that runs on the question text,
// using **verb-key heuristics**. It's deliberately lightweight: no LLM call,
// no ML model, no async, just lowercase + word-boundary regex. Good enough
// for distribution checks; bad cases bias toward Remember (safe fallback).
//
// Multilingual: Italian + English + Spanish + French. The exam UI exposes
// these four languages via the locale segmented control in [exam_overlay.dart].
// ============================================================================

import 'exam_session_model.dart' show ExamQuestion;

/// 🧠 Bloom's Taxonomy levels (Anderson & Krathwohl, 2001).
///
/// Ordered by depth — `index` reflects the cognitive demand. `apply` and
/// higher are "deep processing" (Craik & Lockhart 1972) and produce
/// durable retention.
enum BloomLevel {
  remember,
  understand,
  apply,
  analyze,
  evaluate,
  create;

  /// Convenience: deep processing starts at apply (index ≥ 2).
  bool get isDeep => index >= apply.index;

  /// Display label in Italian.
  String get italianLabel {
    switch (this) {
      case BloomLevel.remember:
        return 'Ricordare';
      case BloomLevel.understand:
        return 'Comprendere';
      case BloomLevel.apply:
        return 'Applicare';
      case BloomLevel.analyze:
        return 'Analizzare';
      case BloomLevel.evaluate:
        return 'Valutare';
      case BloomLevel.create:
        return 'Creare';
    }
  }
}

/// 🧠 Verb-key Bloom classifier.
///
/// Pure functions — no state. Use [classify] on a single question, or
/// [classifyAll] / [distribution] on a batch.
class BloomClassifier {
  BloomClassifier._();

  /// Classify a single question by its text.
  ///
  /// Strategy: scan for verb-key matches at word-boundaries, prioritising
  /// **higher** levels. The presence of a "create" verb anywhere wins over
  /// a "remember" verb because creation requires the lower levels too.
  ///
  /// Returns [BloomLevel.remember] when no verb-key matches — this is the
  /// safe fallback: a question that doesn't expose a clear cognitive verb
  /// is likely a recall prompt ("What is...?", "When did...?").
  static BloomLevel classify(String questionText) {
    final lower = questionText.toLowerCase();

    // Walk levels top-down so the deepest match wins.
    for (final level in [
      BloomLevel.create,
      BloomLevel.evaluate,
      BloomLevel.analyze,
      BloomLevel.apply,
      BloomLevel.understand,
      BloomLevel.remember,
    ]) {
      if (_matchesAny(lower, _keywords[level]!)) {
        return level;
      }
    }
    return BloomLevel.remember;
  }

  /// Classify every question in [items] in-place by setting [ExamQuestion.bloomLevel].
  /// Returns the same list for chaining.
  static List<ExamQuestion> classifyAll(List<ExamQuestion> items) {
    for (final q in items) {
      q.bloomLevel = classify(q.questionText);
    }
    return items;
  }

  /// Tally classifications by level. Useful for telemetry and gating.
  static Map<BloomLevel, int> distribution(Iterable<ExamQuestion> items) {
    final out = {for (final l in BloomLevel.values) l: 0};
    for (final q in items) {
      final lvl = q.bloomLevel ?? classify(q.questionText);
      out[lvl] = out[lvl]! + 1;
    }
    return out;
  }

  /// Fraction of questions at [BloomLevel.apply] or deeper.
  /// Used by the post-validation gate in [atlas_ai_service].
  static double deepRatio(Iterable<ExamQuestion> items) {
    if (items.isEmpty) return 0;
    final dist = distribution(items);
    final deep = dist.entries
        .where((e) => e.key.isDeep)
        .fold<int>(0, (acc, e) => acc + e.value);
    return deep / items.length;
  }

  /// Fraction of questions at [BloomLevel.analyze] or deeper.
  /// Used for difficulty=difficile validation.
  static double higherOrderRatio(Iterable<ExamQuestion> items) {
    if (items.isEmpty) return 0;
    final dist = distribution(items);
    final higher = dist.entries
        .where((e) => e.key.index >= BloomLevel.analyze.index)
        .fold<int>(0, (acc, e) => acc + e.value);
    return higher / items.length;
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  /// Word-boundary match. Each keyword can appear anywhere in the text but
  /// must be a whole token (so "applicazione" doesn't match the bare verb
  /// "apply" prefix-style). We accept Unicode letters, accents and apostrophe.
  static bool _matchesAny(String lower, List<String> keys) {
    for (final k in keys) {
      // Build a word-boundary regex per call — small set of keys, micro cost.
      // Unicode-aware boundaries via \\p{L}.
      final pattern = RegExp(
        r"(^|[^\p{L}'])" + RegExp.escape(k) + r"([^\p{L}']|$)",
        unicode: true,
      );
      if (pattern.hasMatch(lower)) return true;
    }
    return false;
  }

  /// Verb-key dictionary. Each level lists verbs / interrogative phrases that
  /// strongly imply that cognitive process across IT/EN/ES/FR. Keys are
  /// **lowercase**, including stripped apostrophes where relevant.
  ///
  /// Keep ordering stable: tests assert on specific entries.
  static final Map<BloomLevel, List<String>> _keywords = {
    BloomLevel.remember: [
      // Italian
      'definisci', 'definisce', 'definizione',
      'elenca', 'elenco',
      'identifica', 'identifico',
      'quale', 'quali',
      'quando',
      'chi',
      'dove',
      'che cos', // "che cos'è"
      'cos\'è',
      'cosa è',
      'ricorda',
      'nomina',
      // English
      'define', 'definition',
      'list', 'lists',
      'identify', 'identifies',
      'which',
      'when',
      'who',
      'where',
      'what is', 'what are',
      'recall',
      'name',
      'state',
      // Spanish
      'define', 'definir',
      'enumera', 'enumere',
      'identifica',
      'cuál', 'cuales',
      'cuándo',
      'quién',
      'dónde',
      'qué es', 'qué son',
      // French
      'définis', 'définition',
      'énumère',
      'identifie',
      'quel', 'quelle', 'quels', 'quelles',
      'quand',
      'qui',
      'où',
      'qu\'est',
    ],
    BloomLevel.understand: [
      // Italian
      'spiega', 'spiegazione',
      'descrivi', 'descrizione',
      'perché',
      'riassumi', 'riassunto',
      'illustra',
      'interpreta',
      'parafrasa',
      'esemplifica',
      // English
      'explain', 'explanation',
      'describe', 'description',
      'why',
      'summarize', 'summary',
      'interpret',
      'paraphrase',
      'illustrate',
      'discuss',
      // Spanish
      'explica',
      'describe', 'descripción',
      'por qué',
      'resume', 'resumen',
      'interpreta',
      'ilustra',
      // French
      'explique', 'explication',
      'décris', 'description',
      'pourquoi',
      'résume', 'résumé',
      'interprète',
      'illustre',
    ],
    BloomLevel.apply: [
      // Italian
      'applica', 'applicazione',
      'calcola', 'calcolo',
      'risolvi', 'risoluzione',
      'usa', 'utilizza',
      'dato', 'data',
      'determina',
      'esegui',
      'dimostra', // "dimostra come" → apply
      // English
      'apply', 'application',
      'calculate', 'compute',
      'solve',
      'use',
      'given',
      'determine',
      'execute',
      'demonstrate',
      'illustrate how',
      'predict the outcome',
      // Spanish
      'aplica', 'aplicación',
      'calcula',
      'resuelve',
      'usa', 'utiliza',
      'dado',
      'determina',
      'ejecuta',
      'demuestra',
      // French
      'applique',
      'calcule',
      'résous',
      'utilise',
      'étant donné',
      'détermine',
      'exécute',
      'démontre',
    ],
    BloomLevel.analyze: [
      // Italian
      'confronta', 'confronto',
      'contrappone', 'contrapposizione',
      'distingui',
      'categorizza', 'categoria',
      'classifica', 'classificazione',
      'differenza', 'differenze',
      'analizza', 'analisi',
      'scomponi',
      'che relazione',
      'in che modo',
      'individua le cause',
      // English
      'compare',
      'contrast',
      'distinguish',
      'categorize',
      'classify',
      'differentiate',
      'analyze', 'analyse', 'analysis',
      'decompose',
      'how does',
      'how do',
      'what is the relationship',
      'examine',
      'inspect',
      // Spanish
      'compara', 'comparación',
      'contrasta',
      'distingue',
      'categoriza',
      'clasifica',
      'diferencia',
      'analiza', 'análisis',
      'descompón',
      // French
      'compare', 'comparaison',
      'contraste',
      'distingue',
      'catégorise',
      'classe', 'classifie',
      'différencie',
      'analyse',
      'décompose',
    ],
    BloomLevel.evaluate: [
      // Italian
      'valuta', 'valutazione',
      'critica', 'critico',
      'giustifica',
      'argomenta',
      'difendi',
      'sostieni',
      'è meglio',
      'è preferibile',
      'qual è il migliore',
      'pro e contro',
      'vantaggi e svantaggi',
      // English
      'evaluate',
      'assess', 'assessment',
      'critique',
      'justify',
      'argue',
      'defend',
      'support',
      'judge',
      'is it better',
      'pros and cons',
      'advantages and disadvantages',
      'rate',
      // Spanish
      'evalúa',
      'critica',
      'justifica',
      'argumenta',
      'defiende',
      'pros y contras',
      // French
      'évalue', 'évaluation',
      'critique',
      'justifie',
      'argumente',
      'défends',
      'avantages et inconvénients',
    ],
    BloomLevel.create: [
      // Italian
      'progetta', 'progettazione',
      'costruisci', 'costruzione',
      'genera',
      'proponi', 'proposta',
      'crea', 'creazione',
      'componi',
      'inventa',
      'sviluppa',
      'pianifica',
      'formula un\'ipotesi',
      // English
      'design',
      'build', 'construct',
      'generate',
      'propose', 'proposal',
      'create',
      'compose',
      'invent',
      'develop',
      'plan',
      'formulate a hypothesis',
      'devise',
      'craft',
      // Spanish
      'diseña',
      'construye',
      'genera',
      'propone', 'proponer',
      'crea',
      'compón',
      'inventa',
      'desarrolla',
      'planifica',
      // French
      'conçois',
      'construis',
      'génère',
      'propose',
      'crée',
      'compose',
      'invente',
      'développe',
      'planifie',
    ],
  };
}
