// 🇬🇧 Socratic V3.4 — EN discipline hint modules (production_native).
//
// Small modules (~200-400 chars each) injected as "DISCIPLINE:" block
// in the per-call payload (NOT in the system prompt). Match how
// English-speaking professors of each discipline actually interrogate
// their students.
//
// References: adapted from V3.1 monolith "DISCIPLINE-AWARE STEMS"
// section (atlas_ai_service.dart legacy).

import '../../../canvas/ai/socratic/socratic_model.dart' show Discipline;

/// Returns the "DISCIPLINE: ..." block to inject in the payload for
/// the given discipline in English. Keep concise (≤ 400 chars).
String disciplineHintsEn(Discipline d) => switch (d) {
      Discipline.physics => _physicsEn,
      Discipline.math => _mathEn,
      Discipline.chemistry => _chemistryEn,
      Discipline.biology => _biologyEn,
      Discipline.medicine => _medicineEn,
      Discipline.law => _lawEn,
      Discipline.economics => _economicsEn,
      Discipline.philosophy => _philosophyEn,
      Discipline.history => _historyEn,
      Discipline.generic => _genericEn,
    };

const String _physicsEn = '''
DISCIPLINE: physics.
Typical verbs English professors use: predict the trajectory of, draw
the forces on, reason for limiting cases, sketch the v-t diagram, apply
the balance. Concrete examples that work: inclined plane, simple
pendulum, elastic/inelastic collisions, inertial/non-inertial frames,
oscillators. Avoid "define". Prefer scenarios with numerical values
or physical setup.
''';

const String _mathEn = '''
DISCIPLINE: mathematics.
Typical verbs: prove that, find a counterexample to, show the
equivalence of, explain why THEOREM holds. Concrete examples: domain
of a function, notable limit, integration by substitution, induction.
Avoid "compute" as the only verb — math is proof, not arithmetic.
Reward rigour.
''';

const String _chemistryEn = '''
DISCIPLINE: chemistry.
Typical verbs: explain the molecular mechanism, balance and justify,
reason across scale levels (molecular, macroscopic). Examples:
spontaneous/non-spontaneous reactions, Le Chatelier equilibrium, redox,
Brønsted acid-base. ALWAYS seek molecular causality, not surface "why
it happens".
''';

const String _biologyEn = '''
DISCIPLINE: biology.
Typical verbs: explain the mechanism at molecular/cellular/organism
level, why TRAIT was selected for, what mechanism regulates
homeostasis of X. Examples: active/passive transport, gene regulation,
natural selection, glycemic homeostasis. Avoid "list" — biology
rewards mechanism, not taxonomy.
''';

const String _medicineEn = '''
DISCIPLINE: medicine.
Typical verbs: patient aged X with SYMPTOM, what do you do and why?
What do you NOT expect to find? What would make you change diagnosis?
Examples: case-based reasoning with illness scripts, history-taking,
focused physical exam, differential diagnosis. Forward + backward
reasoning. Never "define disease X" — always concrete patient.
''';

const String _lawEn = '''
DISCIPLINE: law.
Typical verbs: what if the facts were VARIATION? Which legal issues
arise? On what authority does this conclusion rest: statute, case,
doctrine? Examples: hypothetical fact patterns with variations,
statutory conflict, constitutional interpretation. Never ask for
article-by-article definitions — always fact pattern.
''';

const String _economicsEn = '''
DISCIPLINE: economics.
Typical verbs: which model do you apply and why? Real case (e.g. 2008
crisis, COVID, fiscal stimulus): map it onto the model. How do you
distinguish a demand shock from a supply shock in SCENARIO? Examples:
market equilibrium, externalities, monetary policy, information
asymmetries. Reward model selection + real-world transfer.
''';

const String _philosophyEn = '''
DISCIPLINE: philosophy.
Typical verbs: what exactly do you mean by TERM? Reformulate POSITION
as premises + conclusion. What grounds that premise? (continue the
regress). Examples: ontology of duty, problem of induction, foundation
of normative ethics. Philosophical questioning aims at conceptual
disambiguation, not historical summary.
''';

const String _historyEn = '''
DISCIPLINE: history.
Typical verbs: compare proximate vs structural causes of EVENT. Who
wrote this source, when, with what interest? To what extent did X
cause Y? Examples: industrial revolution, world wars, 14th-century
economic shifts, documentary vs narrative sources. Reward multi-causal
analysis + source critique.
''';

const String _genericEn = '''
DISCIPLINE: generic (interdisciplinary or ambiguous signal).
Use neutral Bloom verbs (analyze, evaluate, construct). Avoid
discipline-specific verbs that might sound off-key. No misconception
injection (misconceptions are discipline-specific). Neutral examples:
concept connection, applicative example, critical reflection.
''';
