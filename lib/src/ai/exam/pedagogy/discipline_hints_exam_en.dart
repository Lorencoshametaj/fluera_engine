// 🇬🇧 Atlas Exam V3.4 ω — EN discipline hint modules (production_native).
//
// Hand-written native English. Mirror structure of
// `discipline_hints_exam_it.dart`. Distinct from Socratic discipline
// hints (which are dialogic) — Exam hints emphasize Bloom-level
// verbs typical of summative assessments in that discipline.

import '../../../canvas/ai/socratic/socratic_discipline.dart';

/// Returns the "DISCIPLINE: ..." block to inject into the V2 payload
/// of [ExamPhase.generation]. Kept ≤ 400 chars per discipline to
/// preserve the output token budget.
String disciplineHintsExamEn(Discipline d) => switch (d) {
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
Bloom-Apply verbs: calculate (net force, momentum, energy), predict
(trajectory, position at t+Δt), apply (Newton II, conservation).
Bloom-Analyze verbs: derive (equation of motion), distinguish
(elastic/inelastic), compare (inertial vs non-inertial frames).
Bloom-Evaluate verbs: evaluate the stability of a system, critique
a model assumption.
Preferred scenarios: inclined plane with friction, 1D/2D collisions,
harmonic oscillator, RLC circuits, Carnot cycle thermodynamics.
''';

const String _mathEn = '''
DISCIPLINE: mathematics.
Bloom-Apply verbs: solve (equation, system), compute (limit, derivative,
integral by parts/substitution), apply (L'Hôpital's rule, MVT).
Bloom-Analyze verbs: prove (by induction, by contradiction,
contrapositive), find a counterexample, show equivalence, classify
discontinuities.
Bloom-Evaluate verbs: critique a proof, assess the generality of a
theorem.
Never just "compute" as the only verb — exam mathematics is proof.
''';

const String _chemistryEn = '''
DISCIPLINE: chemistry.
Bloom-Apply verbs: balance (redox, neutralization), calculate
(molarity, pH, concentration), predict (reaction product).
Bloom-Analyze verbs: distinguish (strong/weak acid, SN1/SN2), explain
the molecular mechanism, classify compounds by functional group.
Bloom-Evaluate verbs: evaluate thermodynamic spontaneity (ΔG),
critique a synthesis route.
Always seek the molecular causality and the level of representation
(molecular/macroscopic/symbolic).
''';

const String _biologyEn = '''
DISCIPLINE: biology.
Bloom-Apply verbs: apply (Hardy-Weinberg, Mendelian laws), predict
(F2 phenotypes, mutation outcome), calculate (allele frequencies).
Bloom-Analyze verbs: distinguish (mitosis/meiosis, prokaryote/eukaryote),
explain function (organelle, system), compare (natural selection vs
genetic drift).
Bloom-Evaluate verbs: evaluate evidence for an evolutionary hypothesis,
critique an experimental design.
Examples: ATP synthase, gene regulation, homeostasis, ecosystems.
''';

const String _medicineEn = '''
DISCIPLINE: medicine.
Bloom-Apply verbs: diagnose (from symptoms/signs), propose (first-line
therapy), apply (DSM criteria, ESC guidelines).
Bloom-Analyze verbs: distinguish (differential diagnosis), interpret
(lab work, imaging), assess the underlying pathophysiology.
Bloom-Evaluate verbs: critique a treatment, evaluate prognosis,
reason from evidence (RCT vs case report).
Concrete clinical scenarios with history + exams + expected prognosis.
''';

const String _lawEn = '''
DISCIPLINE: law.
Bloom-Apply verbs: apply (statute to a concrete case), qualify
(legal cause of action), identify (liability).
Bloom-Analyze verbs: distinguish (intent/negligence, contract/unilateral
act), compare precedents, argue from the ratio legis.
Bloom-Evaluate verbs: evaluate the legitimacy of an act, critique
a judicial interpretation.
Preferred scenarios: concrete cases with clear cause-of-action elements
+ applicable statutes (civil code, criminal code, constitution).
''';

const String _economicsEn = '''
DISCIPLINE: economics.
Bloom-Apply verbs: calculate (elasticity, GDP, surplus), apply (perfect
competition model, IS-LM), predict the effect of a monetary/fiscal
policy.
Bloom-Analyze verbs: distinguish (substitution vs income effect),
compare market regimes, interpret macroeconomic data.
Bloom-Evaluate verbs: evaluate an economic policy, critique a model
assumption (perfect mobility, rationality).
Examples with supply-demand graphs + realistic numerical data.
''';

const String _philosophyEn = '''
DISCIPLINE: philosophy.
Bloom-Apply verbs: apply (a Kantian category to a case, utilitarian
principle), classify (philosopher by current, text by school).
Bloom-Analyze verbs: compare (Plato vs Aristotle, Hume vs Kant),
distinguish (deontological vs consequentialist ethics), argue from
the source.
Bloom-Evaluate verbs: critique a thesis, evaluate the internal
coherence of a system, construct a counterargument.
Examples: trolley dilemma, liar paradox, mind-body problem.
''';

const String _historyEn = '''
DISCIPLINE: history.
Bloom-Apply verbs: correctly date an event, apply (a periodization
category to a fact), locate (proximate vs ultimate cause).
Bloom-Analyze verbs: distinguish (economic/political/social causes),
compare (French vs American revolutions), interpret a primary source,
identify bias.
Bloom-Evaluate verbs: evaluate the impact of an event, critique a
historiographical thesis, argue from documentary evidence.
Avoid sterile dates: ask WHY + HOW, not just WHEN.
''';

const String _genericEn = '''
DISCIPLINE: generic.
Bloom-Apply verbs: apply, calculate, predict, classify.
Bloom-Analyze verbs: distinguish, compare, interpret, derive.
Bloom-Evaluate verbs: evaluate, critique, argue, justify.
With no specific discipline, prefer questions that require multi-step
reasoning and that are answerable from the cluster's notes.
Avoid generic questions like "What is X?" (Remember-only).
''';
