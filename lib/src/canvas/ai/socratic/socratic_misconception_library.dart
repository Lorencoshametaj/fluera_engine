// ============================================================================
// 🧠 SocraticMisconceptionLibrary — Canonical misconceptions per discipline.
//
// Purpose: when the Socratic batch contains a `counterfactual` stage slot,
// inject a domain-specific misconception as a "what if?" probe — making the
// student confront the wrong-but-plausible model they might hold and
// generate the correct distinction.
//
// Evidence base:
//   • Hestenes, Wells & Swackhamer 1992 — Force Concept Inventory (physics)
//   • Dunlosky et al. 2013 — misconception detection as deeper retrieval
//   • Meyer & Land 2003 — Threshold Concepts (mimicry vs transformation)
//
// 🌍 MULTI-LANGUAGE (CC 2026-05-12):
// Each entry carries text + keywords for multiple languages. Default
// language is `it` (Italian, the launch market). Future languages add
// entries via the per-language map. When a language is missing for a
// given entry, the API falls back to `it` so backward compat is preserved.
//
// Pure data + pure functions — no I/O, no Gemini calls, no async.
// ============================================================================

import 'socratic_discipline.dart';
import 'socratic_misconception_bootstrap.dart'
    show bootstrapMisconceptionKeywordsFor, bootstrapMisconceptionTextFor;

/// Per-language text payload of a misconception (3 strings).
class MisconceptionText {
  /// The wrong-but-plausible belief, phrased as a student would say it.
  final String misconception;

  /// The correct view in 1 sentence — for telemetry / future feedback.
  /// NOT shown to the student during the session (would violate the
  /// Generation Effect — student must produce the correction).
  final String correctView;

  /// Template the AI can rephrase to form the probe question. Use
  /// `[concept]` as the placeholder for the cluster topic.
  final String probePattern;

  const MisconceptionText({
    required this.misconception,
    required this.correctView,
    required this.probePattern,
  });
}

/// One canonical misconception entry, with translations for ≥1 language.
class Misconception {
  /// Stable id (snake_case) — used for telemetry and dedup.
  final String id;

  /// Discipline the misconception belongs to.
  final Discipline discipline;

  /// Per-language keyword sets. Each list has ≥3-char keywords used to
  /// match cluster text via word-boundary regex (see [pickMisconceptionFor]).
  final Map<String, List<String>> conceptKeywordsByLang;

  /// Per-language text payloads (misconception / correctView / probePattern).
  final Map<String, MisconceptionText> textsByLang;

  /// Optional citation for the misconception's documented source.
  final String? citation;

  const Misconception({
    required this.id,
    required this.discipline,
    required this.conceptKeywordsByLang,
    required this.textsByLang,
    this.citation,
  });

  // ─── Backward-compat IT accessors (preserves test API + existing callers) ─

  /// IT keywords (default-language accessor). Use [keywordsFor] when you
  /// need a non-IT language.
  List<String> get conceptKeywords =>
      conceptKeywordsByLang['it'] ?? const <String>[];

  /// IT misconception text (default-language accessor).
  String get misconceptionText =>
      textsByLang['it']?.misconception ?? '';

  /// IT correct view (default-language accessor).
  String get correctView => textsByLang['it']?.correctView ?? '';

  /// IT probe pattern (default-language accessor).
  String get probePattern => textsByLang['it']?.probePattern ?? '';

  // ─── Language-aware accessors ─────────────────────────────────────────

  /// Keywords for [language], falling back through:
  ///   1. Inline `conceptKeywordsByLang[language]` (curated IT/EN)
  ///   2. AI-bootstrap map for [language] (14 Tier-1/2 langs)
  ///   3. Inline IT payload (last-resort fallback)
  List<String> keywordsFor(String language) =>
      conceptKeywordsByLang[language] ??
      bootstrapMisconceptionKeywordsFor(id, language) ??
      conceptKeywordsByLang['it'] ??
      const <String>[];

  /// Text payload for [language], falling back through the same chain
  /// as [keywordsFor]: inline → bootstrap → IT. May return null only
  /// when the entry has no `it` payload (shouldn't happen — `it` is
  /// mandatory by convention).
  MisconceptionText? textFor(String language) =>
      textsByLang[language] ??
      bootstrapMisconceptionTextFor(id, language) ??
      textsByLang['it'];
}

// ─── Discipline keyword sets (for inferDiscipline) ─────────────────────────

/// Discipline keyword sets PER LANGUAGE. Two invariants per language:
///   1. NO duplicates within a language list (each keyword appears once)
///   2. NO short generic stems (≤4 char) that bleed into common non-
///      discipline words (e.g. "dolo" → "dolor", "mole" → "molecola",
///      "ion" → "prescrizione"). Each keyword is ≥5 chars OR is a clearly
///      domain-specific short token (DNA, RNA, ATP, PH).
///
/// EN keyword sets are curated for English textbook vocabulary;
/// IT sets for Italian textbooks.
const Map<Discipline, Map<String, List<String>>> _kDisciplineKeywords = {
  Discipline.physics: {
    'it': [
      'forza', 'inerzia', 'newton', 'gravità', 'gravitazion',
      'energia', 'velocità', 'accelerazione', 'attrito',
      'elettric', 'magnet', 'frequenza', 'termodinamica',
      'entropia', 'calore', 'temperatura', 'pressione', 'fluido',
      'cinetica', 'cinematica', 'dinamica', 'meccanica', 'quantistic',
      'relativi', 'momento', 'potenza',
    ],
    'en': [
      'force', 'inertia', 'newton', 'gravity', 'gravitational',
      'energy', 'velocity', 'acceleration', 'friction',
      'electric', 'magnet', 'frequency', 'thermodynamic',
      'entropy', 'temperature', 'pressure', 'fluid',
      'kinetic', 'kinematic', 'dynamic', 'mechanic', 'quantum',
      'relativi', 'momentum', 'power',
    ],
  },
  Discipline.math: {
    'it': [
      'derivata', 'integral', 'limite', 'funzione', 'equazione',
      'matrice', 'vettore', 'teorema', 'dimostrazione', 'insieme',
      'algebra', 'geometr', 'calcolo', 'trigonometr', 'logaritmo',
      'esponenz', 'continuità', 'successione', 'probabilità',
      'statistic', 'varianza', 'distribuzione',
    ],
    'en': [
      'derivative', 'integral', 'limit', 'function', 'equation',
      'matrix', 'vector', 'theorem', 'proof',
      'algebra', 'geometr', 'calculus', 'trigonometr', 'logarithm',
      'exponential', 'continuity', 'sequence', 'probability',
      'statistic', 'variance', 'distribution',
    ],
  },
  Discipline.chemistry: {
    'it': [
      'reazione', 'molecol', 'atomo', 'legame', 'elettrone',
      'orbital', 'composto', 'soluzione', 'solvente', 'soluto',
      'acido', 'ossidazione', 'riduzione',
      'massa molare', 'concentrazione', 'titolazione',
      'cataliz', 'equilibri', 'cinetic chimic',
    ],
    'en': [
      'reaction', 'molecule', 'atom', 'electron',
      'orbital', 'compound', 'solvent', 'solute',
      'acid', 'oxidation', 'reduction',
      'molar mass', 'concentration', 'titration',
      'catalyst', 'equilibri',
    ],
  },
  Discipline.biology: {
    'it': [
      'cellula', 'cellule', 'cellular', 'dna', 'rna', 'atp',
      'proteina', 'enzima',
      'mitocondri', 'cloroplast', 'membrana', 'mitosi', 'meiosi',
      'evoluzione', 'selezione', 'darwin', 'specie', 'fenotipo',
      'genotipo', 'ecosistema', 'fotosintesi', 'respirazione',
      'ormoni', 'sistema nervoso', 'omeostasi', 'organismo',
    ],
    'en': [
      'cell', 'dna', 'rna', 'atp',
      'protein', 'enzyme',
      'mitochondri', 'chloroplast', 'membrane', 'mitosis', 'meiosis',
      'evolution', 'selection', 'darwin', 'species', 'phenotype',
      'genotype', 'ecosystem', 'photosynthesis', 'respiration',
      'hormone', 'nervous system', 'homeostasis', 'organism',
    ],
  },
  Discipline.medicine: {
    'it': [
      'pazient', 'diagnosi', 'sintomo', 'malattia', 'patologia',
      'fisiopatologia', 'terapia', 'farmaco', 'antibiotic',
      'antivirale', 'vaccino', 'immunità', 'anamnesi',
      'sindrome', 'eziologia', 'prognosi', 'clinica', 'chirurgia',
      'diabete', 'ipertensione', 'cardiopatia',
    ],
    'en': [
      'patient', 'diagnosis', 'symptom', 'disease', 'pathology',
      'pathophysiology', 'therapy', 'drug', 'antibiotic',
      'antiviral', 'vaccine', 'immunity',
      'syndrome', 'etiology', 'prognosis', 'clinical', 'surgery',
      'diabetes', 'hypertension', 'cardiopathy',
    ],
  },
  Discipline.law: {
    'it': [
      'contratto', 'obbligazione', 'codice civile', 'codice penale',
      'sentenza', 'giurisprudenza', 'dottrina', 'normativ', 'articolo',
      'prescrizione', 'decadenza', 'capacità giurid', 'tutela',
      'responsabilità', 'reato', 'penale',
      'usucapione', 'proprietà', 'possesso', 'servitù', 'usufrutto',
      'lavoro subordinato', 'contributiv', 'tribut',
    ],
    'en': [
      'contract', 'obligation', 'civil code', 'criminal code',
      'judgment', 'jurisprudence', 'doctrine', 'statute', 'article',
      'prescription', 'limitation period', 'liability', 'tort',
      'offense', 'criminal',
      'usucap', 'property', 'possession', 'easement', 'usufruct',
    ],
  },
  Discipline.economics: {
    'it': [
      'domanda', 'offerta', 'elasticità', 'mercato',
      'inflazione', 'disoccupazione', 'monetaria', 'fiscale',
      'esternalità', 'monopolio', 'oligopolio', 'concorrenza',
      'utilità', 'preferenze', 'equilibri', 'surplus',
      'tasso interesse', 'commercio', 'tariffa',
      'macroecon', 'microecon', 'keynes',
    ],
    'en': [
      'supply', 'demand', 'elasticity', 'market',
      'inflation', 'unemployment', 'monetary', 'fiscal',
      'externality', 'monopoly', 'oligopoly', 'competition',
      'utility', 'preference', 'surplus',
      'interest rate', 'trade', 'tariff',
      'macroecon', 'microecon', 'keynes',
    ],
  },
  Discipline.philosophy: {
    'it': [
      'epistemolog', 'metafisic', 'ontolog', 'fenomenolog',
      'ermeneutic', 'idealismo', 'empirismo', 'razionalismo',
      'kant', 'hegel', 'platone', 'aristotele', 'cartesio',
      'nietzsche', 'heidegger', 'wittgenstein',
      'sillogismo', 'argomentazione', 'a priori', 'a posteriori',
      'noumeno', 'esistenz', 'libero arbitrio',
      'determinismo', 'morale', 'etica',
    ],
    'en': [
      'epistemology', 'metaphysics', 'ontology', 'phenomenology',
      'hermeneutic', 'idealism', 'empiricism', 'rationalism',
      'kant', 'hegel', 'plato', 'aristotle', 'descartes',
      'nietzsche', 'heidegger', 'wittgenstein',
      'syllogism', 'argument', 'a priori', 'a posteriori',
      'noumenon', 'existence', 'free will',
      'determinism', 'moral', 'ethic',
    ],
  },
  Discipline.history: {
    'it': [
      'rivoluzione', 'guerra', 'impero', 'dinastia',
      'medioevo', 'rinascimento', 'illuminismo', 'risorgimento',
      'fascismo', 'nazismo', 'colonialismo', 'imperialismo',
      'feudale', 'borghesia', 'proletariato',
      'costituzione', 'parlamento', 'monarchia',
      'repubblica', 'antichità', 'preistoria',
    ],
    'en': [
      'revolution', 'empire', 'dynasty',
      'medieval', 'renaissance', 'enlightenment',
      'fascism', 'nazism', 'colonialism', 'imperialism',
      'feudal', 'bourgeoisie', 'proletariat',
      'constitution', 'parliament', 'monarchy',
      'republic', 'antiquity', 'prehistory',
    ],
  },
};

// ─── Misconception library (30 entries with IT + EN translations) ──────────

final List<Misconception> _kAllMisconceptions = [
  // ── Physics (5) — FCI Hestenes 1992, Halloun 1985 ──
  const Misconception(
    id: 'motion-requires-force',
    discipline: Discipline.physics,
    conceptKeywordsByLang: {
      'it': ['inerzia', 'moto', 'newton', 'prima legge'],
      'en': ['inertia', 'motion', 'newton', 'first law'],
    },
    textsByLang: {
      'it': MisconceptionText(
        misconception:
            'Un corpo in moto richiede una forza continua per restare in moto.',
        correctView:
            'Per la prima legge di Newton, un corpo prosegue in moto rettilineo uniforme finché nessuna forza risultante agisce su di esso.',
        probePattern:
            'Considera l\'ipotesi che [concept] richieda una forza continua per non fermarsi. Si concilia con un corpo nello spazio profondo, lontano da tutto?',
      ),
      'en': MisconceptionText(
        misconception:
            'A moving body requires a continuous force to stay in motion.',
        correctView:
            "Newton's first law states an object continues in uniform straight-line motion until a net force acts on it.",
        probePattern:
            'Consider the hypothesis that [concept] requires a continuous force to keep moving. Does it fit a body in deep space, far from anything?',
      ),
    },
    citation: 'Hestenes 1992 FCI',
  ),
  const Misconception(
    id: 'heavier-falls-faster',
    discipline: Discipline.physics,
    conceptKeywordsByLang: {
      'it': ['caduta', 'gravità', 'peso', 'massa'],
      'en': ['fall', 'gravity', 'weight', 'mass'],
    },
    textsByLang: {
      'it': MisconceptionText(
        misconception:
            'Nel vuoto, oggetti più pesanti cadono più velocemente dei più leggeri.',
        correctView:
            'Nel vuoto tutti gli oggetti cadono con la stessa accelerazione g, indipendentemente dalla massa (Galileo, principio di equivalenza).',
        probePattern:
            'Se sganciassi una piuma e un martello sulla Luna (no aria), arriverebbero a terra in tempi diversi? Spiega rispetto a [concept].',
      ),
      'en': MisconceptionText(
        misconception:
            'In vacuum, heavier objects fall faster than lighter ones.',
        correctView:
            'In vacuum, all objects fall with the same acceleration g regardless of mass (Galileo, equivalence principle).',
        probePattern:
            'If you dropped a feather and a hammer on the Moon (no air), would they land at different times? Explain using [concept].',
      ),
    },
    citation: 'Halloun 1985',
  ),
  const Misconception(
    id: 'current-consumed',
    discipline: Discipline.physics,
    conceptKeywordsByLang: {
      'it': ['corrente', 'resistenza', 'circuito', 'elettric'],
      'en': ['current', 'resistance', 'circuit', 'electric'],
    },
    textsByLang: {
      'it': MisconceptionText(
        misconception:
            'La corrente elettrica si "consuma" attraversando una resistenza, arrivando ridotta al ramo successivo.',
        correctView:
            'Per la conservazione della carica e Kirchhoff, la corrente è la stessa in ogni punto di un circuito in serie; ciò che si dissipa è l\'energia, non la carica.',
        probePattern:
            'Se misurassi la corrente prima e dopo una resistenza in un circuito in serie, troverei valori diversi? Cosa dice [concept]?',
      ),
      'en': MisconceptionText(
        misconception:
            'Electric current is "consumed" passing through a resistor, arriving reduced at the next branch.',
        correctView:
            "By charge conservation and Kirchhoff's law, current is the same at every point of a series circuit; energy is dissipated, charge is not.",
        probePattern:
            'If you measured the current before and after a resistor in a series circuit, would you find different values? What does [concept] say?',
      ),
    },
  ),
  const Misconception(
    id: 'centrifugal-real',
    discipline: Discipline.physics,
    conceptKeywordsByLang: {
      'it': ['centrifuga', 'rotazione', 'circolare', 'centripeta'],
      'en': ['centrifugal', 'rotation', 'circular', 'centripetal'],
    },
    textsByLang: {
      'it': MisconceptionText(
        misconception:
            'La forza centrifuga è una forza reale che spinge gli oggetti verso l\'esterno in una rotazione.',
        correctView:
            'La centrifuga è apparente, esiste solo nel sistema di riferimento rotante non-inerziale; nel riferimento inerziale c\'è solo centripeta.',
        probePattern:
            'Un sasso in una fionda viene lanciato in tangente quando si rompe il laccio, non radialmente verso l\'esterno. Si concilia con l\'ipotesi che [concept] subisca una "spinta centrifuga"?',
      ),
      'en': MisconceptionText(
        misconception:
            'Centrifugal force is a real force pushing objects outward during rotation.',
        correctView:
            'Centrifugal is apparent — it only exists in the rotating non-inertial frame. In the inertial frame, only centripetal force exists.',
        probePattern:
            'A stone in a sling flies tangentially when the cord breaks, not radially outward. Does this fit the hypothesis that [concept] experiences a "centrifugal push"?',
      ),
    },
  ),
  const Misconception(
    id: 'heat-equals-temperature',
    discipline: Discipline.physics,
    conceptKeywordsByLang: {
      'it': ['calore', 'temperatura', 'termodinamica', 'energia term'],
      'en': ['heat', 'temperature', 'thermodynamic', 'thermal energy'],
    },
    textsByLang: {
      'it': MisconceptionText(
        misconception:
            'Calore e temperatura sono lo stesso concetto, solo nomi diversi.',
        correctView:
            'La temperatura è una proprietà intensiva (energia cinetica media molecolare); il calore è il TRASFERIMENTO di energia termica tra corpi a temperatura diversa.',
        probePattern:
            'Un secchio d\'acqua a 30°C e una goccia a 30°C hanno la stessa temperatura. Possono cedere la stessa quantità di [concept] all\'ambiente? Perché?',
      ),
      'en': MisconceptionText(
        misconception:
            'Heat and temperature are the same concept, just different names.',
        correctView:
            'Temperature is an intensive property (average molecular kinetic energy); heat is the TRANSFER of thermal energy between bodies at different temperatures.',
        probePattern:
            'A bucket of water at 30°C and a drop at 30°C have the same temperature. Can they release the same amount of [concept] to the environment? Why?',
      ),
    },
  ),

  // ── Math (4) ──
  const Misconception(
    id: 'infinity-is-number',
    discipline: Discipline.math,
    conceptKeywordsByLang: {
      'it': ['infinito', 'limite'],
      'en': ['infinity', 'limit'],
    },
    textsByLang: {
      'it': MisconceptionText(
        misconception:
            'Infinito è un numero molto grande, e si può operare con esso come con qualsiasi numero.',
        correctView:
            'Infinito non è un numero ma un simbolo che denota un comportamento di crescita illimitata; ∞ - ∞ è indeterminato, non 0.',
        probePattern:
            'Se ∞ fosse un numero qualunque, quanto farebbe ∞ - ∞? Cosa ti suggerisce questo riguardo [concept]?',
      ),
      'en': MisconceptionText(
        misconception:
            'Infinity is a very large number, and you can operate on it like any other number.',
        correctView:
            'Infinity is not a number but a symbol denoting unbounded growth; ∞ - ∞ is indeterminate, not 0.',
        probePattern:
            'If ∞ were just a number, what would ∞ - ∞ equal? What does this suggest about [concept]?',
      ),
    },
  ),
  const Misconception(
    id: '0999-less-than-1',
    discipline: Discipline.math,
    conceptKeywordsByLang: {
      'it': ['decimal', 'periodic', 'limite', 'serie'],
      'en': ['decimal', 'periodic', 'limit', 'series'],
    },
    textsByLang: {
      'it': MisconceptionText(
        misconception:
            '0.999... è infinitamente vicino a 1 ma diverso da 1.',
        correctView:
            '0.999... = 1 esattamente, dimostrabile via somma di serie geometrica o limite della successione.',
        probePattern:
            'Se 0.999... ≠ 1, quanto fa 1 - 0.999...? Esiste una posizione decimale dove la differenza appare? Cosa dice [concept] sul limite?',
      ),
      'en': MisconceptionText(
        misconception:
            '0.999... is infinitely close to 1 but different from 1.',
        correctView:
            '0.999... = 1 exactly, provable via geometric-series sum or sequence limit.',
        probePattern:
            'If 0.999... ≠ 1, what is 1 - 0.999...? Is there a decimal position where the difference appears? What does [concept] say about the limit?',
      ),
    },
  ),
  const Misconception(
    id: 'correlation-causation',
    discipline: Discipline.math,
    conceptKeywordsByLang: {
      'it': ['correlazione', 'statistic', 'probabilità', 'causa'],
      'en': ['correlation', 'statistic', 'probability', 'cause'],
    },
    textsByLang: {
      'it': MisconceptionText(
        misconception:
            'Se due variabili sono fortemente correlate, una causa l\'altra.',
        correctView:
            'Correlazione ≠ causazione: variabili confondenti, causalità inversa o coincidenza statistica possono produrre correlazioni spurie.',
        probePattern:
            'Vendite di gelato e annegamenti sono molto correlati d\'estate. Il gelato causa annegamenti? Cosa manca in [concept]?',
      ),
      'en': MisconceptionText(
        misconception:
            'If two variables are strongly correlated, one causes the other.',
        correctView:
            'Correlation ≠ causation: confounders, reverse causation, or statistical coincidence can produce spurious correlations.',
        probePattern:
            'Ice cream sales and drownings are highly correlated in summer. Does ice cream cause drowning? What is missing in [concept]?',
      ),
    },
  ),
  const Misconception(
    id: 'derivative-everywhere-visible',
    discipline: Discipline.math,
    conceptKeywordsByLang: {
      'it': ['derivata', 'continuità', 'pendenza'],
      'en': ['derivative', 'continuity', 'slope'],
    },
    textsByLang: {
      'it': MisconceptionText(
        misconception:
            'La derivata di una funzione esiste sempre dove la funzione è continua.',
        correctView:
            'La continuità è necessaria ma non sufficiente: funzioni continue come |x| in x=0 non sono derivabili. La derivabilità richiede tangente unica.',
        probePattern:
            'La funzione |x| è continua ovunque. È anche derivabile in x=0? Cosa dice [concept] sul limite del rapporto incrementale?',
      ),
      'en': MisconceptionText(
        misconception:
            "A function's derivative always exists where the function is continuous.",
        correctView:
            'Continuity is necessary but not sufficient: continuous functions like |x| at x=0 are not differentiable. Differentiability requires a unique tangent.',
        probePattern:
            'The function |x| is continuous everywhere. Is it also differentiable at x=0? What does [concept] say about the limit of the difference quotient?',
      ),
    },
  ),

  // ── Chemistry (3) ──
  const Misconception(
    id: 'mass-loss-combustion',
    discipline: Discipline.chemistry,
    conceptKeywordsByLang: {
      'it': ['combustione', 'reazione', 'massa', 'conservazione'],
      'en': ['combustion', 'reaction', 'mass', 'conservation'],
    },
    textsByLang: {
      'it': MisconceptionText(
        misconception:
            'Quando un oggetto brucia, la materia si distrugge e la massa totale diminuisce.',
        correctView:
            'Per il principio di Lavoisier, la massa si conserva: i prodotti gassosi (CO₂, H₂O) hanno la stessa massa dei reagenti.',
        probePattern:
            'Se bruci una candela in un contenitore sigillato e pesi tutto prima e dopo, cosa ti aspetti? E senza sigillo, dove va la massa secondo [concept]?',
      ),
      'en': MisconceptionText(
        misconception:
            'When an object burns, matter is destroyed and the total mass decreases.',
        correctView:
            "By Lavoisier's principle, mass is conserved: gas products (CO₂, H₂O) have the same mass as the reactants.",
        probePattern:
            'If you burn a candle in a sealed container and weigh everything before and after, what do you expect? Without the seal, where does the mass go according to [concept]?',
      ),
    },
  ),
  const Misconception(
    id: 'atom-indivisible',
    discipline: Discipline.chemistry,
    conceptKeywordsByLang: {
      'it': ['atomo', 'particell', 'nucleo', 'elettron'],
      'en': ['atom', 'particle', 'nucleus', 'electron'],
    },
    textsByLang: {
      'it': MisconceptionText(
        misconception:
            'L\'atomo è la più piccola unità di materia e non può essere diviso.',
        correctView:
            'L\'atomo è composto da protoni, neutroni, elettroni (e questi da quark/leptoni). La fissione nucleare lo divide.',
        probePattern:
            'Una bomba atomica funziona dividendo nuclei di uranio. Se [concept] fosse indivisibile, come potrebbe rilasciare energia?',
      ),
      'en': MisconceptionText(
        misconception:
            'The atom is the smallest unit of matter and cannot be divided.',
        correctView:
            'The atom is composed of protons, neutrons, and electrons (and these of quarks/leptons). Nuclear fission divides it.',
        probePattern:
            'An atomic bomb works by splitting uranium nuclei. If [concept] were indivisible, how could it release energy?',
      ),
    },
  ),
  const Misconception(
    id: 'dissolution-equals-melting',
    discipline: Discipline.chemistry,
    conceptKeywordsByLang: {
      'it': ['soluzione', 'soluto', 'solvente', 'fusione', 'discioglier'],
      'en': ['solution', 'solute', 'solvent', 'melting', 'dissolv'],
    },
    textsByLang: {
      'it': MisconceptionText(
        misconception:
            'Sciogliere zucchero in acqua è lo stesso processo di fondere il ghiaccio.',
        correctView:
            'La dissoluzione è interazione soluto-solvente (idratazione, separazione molecole); la fusione è transizione di fase per accumulo di energia termica.',
        probePattern:
            'Lo zucchero si scioglie in acqua a temperatura ambiente, ma fonde solo sopra 180°C. Sono lo stesso fenomeno? Cosa distingue [concept]?',
      ),
      'en': MisconceptionText(
        misconception:
            'Dissolving sugar in water is the same process as melting ice.',
        correctView:
            'Dissolution is solute-solvent interaction (hydration, molecule separation); melting is a phase transition due to thermal energy accumulation.',
        probePattern:
            'Sugar dissolves in water at room temperature but only melts above 180°C. Are they the same phenomenon? What distinguishes [concept]?',
      ),
    },
  ),

  // ── Biology (4) ──
  const Misconception(
    id: 'lamarckian-inheritance',
    discipline: Discipline.biology,
    conceptKeywordsByLang: {
      'it': ['evoluzione', 'selezione', 'darwin', 'eredità', 'gene'],
      'en': ['evolution', 'selection', 'darwin', 'inheritance', 'gene'],
    },
    textsByLang: {
      'it': MisconceptionText(
        misconception:
            'Le giraffe hanno il collo lungo perché i progenitori lo allungavano per raggiungere foglie alte, e questo carattere acquisito è stato ereditato.',
        correctView:
            'Selezione naturale darwiniana: variazione genetica casuale produce colli di lunghezza diversa; quelli più lunghi hanno più foglie → più riproduzione → frequenza del gene aumenta.',
        probePattern:
            'Se Lamarck avesse ragione, un body builder dovrebbe avere figli muscolosi senza allenarsi. Succede? Cosa dice [concept] sulla differenza eredità/acquisizione?',
      ),
      'en': MisconceptionText(
        misconception:
            'Giraffes have long necks because their ancestors stretched them to reach high leaves, and this acquired trait was inherited.',
        correctView:
            'Darwinian natural selection: random genetic variation produces different neck lengths; longer ones get more leaves → more reproduction → the gene frequency increases.',
        probePattern:
            'If Lamarck were right, a body builder would have muscular children without training. Does this happen? What does [concept] say about the inheritance/acquisition distinction?',
      ),
    },
  ),
  const Misconception(
    id: 'evolution-has-goal',
    discipline: Discipline.biology,
    conceptKeywordsByLang: {
      'it': ['evoluzione', 'selezione', 'specie', 'adattamento'],
      'en': ['evolution', 'selection', 'species', 'adaptation'],
    },
    textsByLang: {
      'it': MisconceptionText(
        misconception:
            'L\'evoluzione tende verso forme più complesse o perfette, come se avesse un obiettivo.',
        correctView:
            'L\'evoluzione è non-direzionata: la selezione naturale ottimizza la fitness nell\'ambiente attuale; complessità decresce in molti lignaggi (parassiti, virus).',
        probePattern:
            'I batteri sono "meno evoluti" degli esseri umani? Sono qui da 3,5 miliardi di anni e dominano la biomassa. Cosa dice [concept] sulla direzione?',
      ),
      'en': MisconceptionText(
        misconception:
            'Evolution tends toward more complex or perfect forms, as if it had a goal.',
        correctView:
            'Evolution is non-directed: natural selection optimizes fitness in the current environment; complexity decreases in many lineages (parasites, viruses).',
        probePattern:
            'Are bacteria "less evolved" than humans? They have been here 3.5 billion years and dominate biomass. What does [concept] say about direction?',
      ),
    },
  ),
  const Misconception(
    id: 'gene-trait-1to1',
    discipline: Discipline.biology,
    conceptKeywordsByLang: {
      'it': ['gene', 'genotipo', 'fenotipo', 'eredità', 'mendel'],
      'en': ['gene', 'genotype', 'phenotype', 'inheritance', 'mendel'],
    },
    textsByLang: {
      'it': MisconceptionText(
        misconception:
            'Ogni carattere è codificato da un gene specifico: c\'è "il gene degli occhi azzurri", "il gene del cancro", ecc.',
        correctView:
            'La maggior parte dei caratteri è poligenica (più geni) ed epigenetica (ambiente, espressione regolata). Il gene-trait 1:1 è una semplificazione didattica.',
        probePattern:
            'Esiste "il gene dell\'altezza"? L\'altezza media di una popolazione cambia di una decina di cm in 100 anni, troppo veloce per evoluzione genetica. Cosa dice [concept]?',
      ),
      'en': MisconceptionText(
        misconception:
            'Each trait is coded by a specific gene: there is "the blue-eye gene", "the cancer gene", etc.',
        correctView:
            'Most traits are polygenic (multiple genes) and epigenetic (environment, regulated expression). 1:1 gene-trait mapping is a didactic simplification.',
        probePattern:
            'Is there "the height gene"? Average height in a population changes by ~10cm in 100 years, too fast for genetic evolution. What does [concept] say?',
      ),
    },
  ),
  const Misconception(
    id: 'antibiotics-vs-virus',
    discipline: Discipline.biology,
    conceptKeywordsByLang: {
      'it': ['antibiotic', 'virus', 'batter', 'infezione', 'farmaco'],
      'en': ['antibiotic', 'virus', 'bacteri', 'infection', 'drug'],
    },
    textsByLang: {
      'it': MisconceptionText(
        misconception:
            'Gli antibiotici curano qualsiasi infezione, compresa l\'influenza.',
        correctView:
            'Gli antibiotici colpiscono strutture batteriche (parete cellulare, ribosomi) che i virus non hanno; sono inefficaci contro virus (influenza, covid, raffreddore).',
        probePattern:
            'Se l\'antibiotico distrugge la parete cellulare batterica, perché dovrebbe funzionare contro un virus che non ha parete? Cosa dice [concept]?',
      ),
      'en': MisconceptionText(
        misconception:
            'Antibiotics cure any infection, including the flu.',
        correctView:
            'Antibiotics target bacterial structures (cell wall, ribosomes) that viruses lack; they are ineffective against viruses (flu, COVID, cold).',
        probePattern:
            'If an antibiotic destroys the bacterial cell wall, why would it work against a virus that has no wall? What does [concept] say?',
      ),
    },
  ),

  // ── Medicine (3) ──
  const Misconception(
    id: 'vaccine-causes-disease',
    discipline: Discipline.medicine,
    conceptKeywordsByLang: {
      'it': ['vaccino', 'immunità', 'infezione', 'antigene'],
      'en': ['vaccine', 'immunity', 'infection', 'antigen'],
    },
    textsByLang: {
      'it': MisconceptionText(
        misconception:
            'Il vaccino può causare la malattia che è progettato per prevenire.',
        correctView:
            'I vaccini moderni contengono antigeni inattivati o frammenti (mRNA, subunità), incapaci di replicarsi e causare la malattia; il "mal di braccio" è risposta immunitaria, non infezione.',
        probePattern:
            'Se il vaccino antinfluenzale contenesse virus vivo, dovresti ammalarti di influenza dopo ogni iniezione. Succede? Cosa distingue [concept] dall\'infezione vera?',
      ),
      'en': MisconceptionText(
        misconception:
            'A vaccine can cause the disease it is designed to prevent.',
        correctView:
            'Modern vaccines contain inactivated antigens or fragments (mRNA, subunits) incapable of replicating and causing disease; arm soreness is an immune response, not infection.',
        probePattern:
            'If a flu shot contained live virus, you would get the flu after every injection. Does that happen? What distinguishes [concept] from a real infection?',
      ),
    },
  ),
  const Misconception(
    id: 'cold-causes-cold',
    discipline: Discipline.medicine,
    conceptKeywordsByLang: {
      'it': ['raffreddore', 'influenza', 'freddo', 'virus', 'infezione'],
      'en': ['cold', 'flu', 'virus', 'infection'],
    },
    textsByLang: {
      'it': MisconceptionText(
        misconception:
            'Stare al freddo causa il raffreddore.',
        correctView:
            'Il raffreddore è causato da rhinovirus (>200 ceppi), non dal freddo; la stagionalità invernale dipende da indoor crowding + bassa umidità + sopravvivenza virale.',
        probePattern:
            'Se uscire al freddo causasse raffreddore, gli abitanti dell\'Antartide dovrebbero ammalarsi di continuo. Cosa dice [concept] sull\'eziologia?',
      ),
      'en': MisconceptionText(
        misconception:
            'Being out in the cold causes a cold.',
        correctView:
            'Colds are caused by rhinoviruses (>200 strains), not by low temperature; winter seasonality is due to indoor crowding + low humidity + viral survival.',
        probePattern:
            'If going out in the cold caused a cold, Antarctic researchers would be constantly sick. What does [concept] say about etiology?',
      ),
    },
  ),
  const Misconception(
    id: 'knuckle-cracking-arthritis',
    discipline: Discipline.medicine,
    conceptKeywordsByLang: {
      'it': ['articolazione', 'artrite', 'osso', 'cartilagine'],
      'en': ['joint', 'arthritis', 'bone', 'cartilage'],
    },
    textsByLang: {
      'it': MisconceptionText(
        misconception:
            'Far scrocchiare le nocche causa artrite.',
        correctView:
            'Lo "scrocchio" è bolle di gas nel liquido sinoviale (cavitazione); studi longitudinali non mostrano correlazione con artrite (Castellanos 1990, Boutin 2018).',
        probePattern:
            'Donald Unger si fece scrocchiare le nocche solo di una mano per 60 anni e ricevette il Nobel-parodia per dimostrare nulla. Cosa dice [concept] sull\'eziologia dell\'artrite?',
      ),
      'en': MisconceptionText(
        misconception:
            'Cracking your knuckles causes arthritis.',
        correctView:
            'The "crack" is gas bubbles in synovial fluid (cavitation); longitudinal studies show no correlation with arthritis (Castellanos 1990, Boutin 2018).',
        probePattern:
            'Donald Unger cracked the knuckles of only one hand for 60 years and earned an Ig Nobel by proving nothing. What does [concept] say about the etiology of arthritis?',
      ),
    },
  ),

  // ── Law (3) ──
  const Misconception(
    id: 'prescription-uninterruptible',
    discipline: Discipline.law,
    conceptKeywordsByLang: {
      'it': ['prescrizione', 'decadenza', 'credito', 'obbligazione'],
      'en': ['prescription', 'limitation', 'credit', 'obligation'],
    },
    textsByLang: {
      'it': MisconceptionText(
        misconception:
            'La prescrizione decorre senza possibilità di interruzione: una volta partito il termine, scorre fino alla fine.',
        correctView:
            'Art. 2943 cc: la prescrizione è interrotta da atti di costituzione in mora (raccomandata, ricorso), riconoscimento del debitore, atti giudiziari; ricomincia da capo.',
        probePattern:
            'Se Caio manda raccomandata a Tizio prima dello scadere dei 10 anni, cosa succede al termine di [concept]? Si ferma o riparte?',
      ),
      'en': MisconceptionText(
        misconception:
            'The limitation period runs without possibility of interruption: once started, it runs to the end.',
        correctView:
            'In Italian Civil Code art. 2943: the limitation period is interrupted by formal notice (registered letter, lawsuit), debtor acknowledgment, or judicial acts; it restarts from zero.',
        probePattern:
            'If Caio sends a registered letter to Tizio before the 10-year period expires, what happens to the [concept] term? Does it freeze or restart?',
      ),
    },
  ),
  const Misconception(
    id: 'retroactive-penalty',
    discipline: Discipline.law,
    conceptKeywordsByLang: {
      'it': ['penal', 'reato', 'codice penal', 'retroattiv'],
      'en': ['criminal', 'offense', 'penal code', 'retroactiv'],
    },
    textsByLang: {
      'it': MisconceptionText(
        misconception:
            'Le leggi penali sono retroattive: una condotta diventa reato anche se commessa prima della legge che la punisce.',
        correctView:
            'Art. 25 Cost. e art. 2 cp: irretroattività della legge penale sfavorevole (nullum crimen sine lege). Solo la legge più favorevole è retroattiva (favor rei).',
        probePattern:
            'Se nel 2024 viene fatta una legge che punisce il consumo di gelato in pubblico, Tizio che lo ha mangiato nel 2020 può essere processato? Cosa dice [concept]?',
      ),
      'en': MisconceptionText(
        misconception:
            'Criminal laws are retroactive: conduct becomes a crime even if committed before the law punishing it.',
        correctView:
            'Italian Constitution art. 25 + Penal Code art. 2: non-retroactivity of unfavorable criminal law (nullum crimen sine lege). Only a more favorable law applies retroactively (favor rei).',
        probePattern:
            'If a 2024 law punishes eating ice cream in public, can Tizio be prosecuted for doing it in 2020? What does [concept] say?',
      ),
    },
  ),
  const Misconception(
    id: 'verbal-contract-invalid',
    discipline: Discipline.law,
    conceptKeywordsByLang: {
      'it': ['contratto', 'forma', 'consens', 'scritt'],
      'en': ['contract', 'form', 'consent', 'written'],
    },
    textsByLang: {
      'it': MisconceptionText(
        misconception:
            'I contratti verbali non hanno valore giuridico, servono sempre forma scritta.',
        correctView:
            'Principio di libertà delle forme (art. 1325 cc): contratto si perfeziona con consenso, salvo forme ad substantiam tipizzate (vendita immobili, donazione...). Compravendite di mercato sono valide a voce.',
        probePattern:
            'Quando compri un caffè al bar, firmi un contratto scritto? È valido lo stesso? Cosa dice [concept] sulla forma necessaria?',
      ),
      'en': MisconceptionText(
        misconception:
            'Verbal contracts have no legal value; written form is always required.',
        correctView:
            'Principle of freedom of form (Italian Civil Code art. 1325): a contract is formed by consent, except for legally-mandated written forms (real estate sale, gift, etc.). Market purchases are valid verbally.',
        probePattern:
            'When you buy a coffee at a bar, do you sign a written contract? Is it valid anyway? What does [concept] say about required form?',
      ),
    },
  ),

  // ── Economics (3) ──
  const Misconception(
    id: 'zero-sum-trade',
    discipline: Discipline.economics,
    conceptKeywordsByLang: {
      'it': ['scambio', 'commercio', 'mercato', 'surplus'],
      'en': ['trade', 'market', 'surplus', 'exchange'],
    },
    textsByLang: {
      'it': MisconceptionText(
        misconception:
            'Lo scambio è a somma zero: se uno guadagna, l\'altro perde della stessa quantità.',
        correctView:
            'Lo scambio volontario crea valore per entrambe le parti: ciascuna cede ciò che valuta meno per ciò che valuta più (surplus del consumatore + del produttore).',
        probePattern:
            'Se pago 3€ un caffè che il barista produce a 0,5€, chi ci guadagna e chi ci perde? Perché lo scambio avviene volontariamente? Cosa dice [concept]?',
      ),
      'en': MisconceptionText(
        misconception:
            'Trade is zero-sum: if one party gains, the other loses by the same amount.',
        correctView:
            'Voluntary trade creates value for both parties: each gives up what they value less for what they value more (consumer + producer surplus).',
        probePattern:
            'If I pay €3 for a coffee the barista produces at €0.50, who gains and who loses? Why does the trade happen voluntarily? What does [concept] say?',
      ),
    },
  ),
  const Misconception(
    id: 'sunk-cost-rational',
    discipline: Discipline.economics,
    conceptKeywordsByLang: {
      'it': ['costo', 'decisione', 'razional', 'investimento'],
      'en': ['cost', 'decision', 'rational', 'investment'],
    },
    textsByLang: {
      'it': MisconceptionText(
        misconception:
            'Bisogna considerare i costi affondati nelle decisioni future per non sprecarli.',
        correctView:
            'I sunk cost sono irrecuperabili e razionalmente IRRILEVANTI per decisioni future: contano solo costi marginali e benefici futuri attesi.',
        probePattern:
            'Hai pagato 20€ il cinema, ma dopo 10 min il film fa schifo. Resti per "non sprecare i 20€" o esci? Cosa dice [concept] sui costi irrecuperabili?',
      ),
      'en': MisconceptionText(
        misconception:
            'You must factor sunk costs into future decisions to avoid wasting them.',
        correctView:
            'Sunk costs are unrecoverable and rationally IRRELEVANT to future decisions: only marginal costs and expected future benefits matter.',
        probePattern:
            'You paid €20 for cinema, but after 10 min the film is awful. Do you stay to "not waste the €20" or leave? What does [concept] say about sunk costs?',
      ),
    },
  ),
  const Misconception(
    id: 'printing-money-wealth',
    discipline: Discipline.economics,
    conceptKeywordsByLang: {
      'it': ['monetaria', 'inflazione', 'banca central', 'moneta'],
      'en': ['monetary', 'inflation', 'central bank', 'money'],
    },
    textsByLang: {
      'it': MisconceptionText(
        misconception:
            'Lo Stato può creare ricchezza stampando moneta.',
        correctView:
            'Stampare moneta senza aumento di produzione reale causa inflazione (Weimar, Zimbabwe, Venezuela): più moneta inseguono gli stessi beni → prezzi salgono, potere d\'acquisto crolla.',
        probePattern:
            'Se la BCE raddoppiasse di colpo l\'offerta di moneta in Europa senza che si producano più beni, cosa accadrebbe ai prezzi? E al potere d\'acquisto secondo [concept]?',
      ),
      'en': MisconceptionText(
        misconception:
            'The state can create wealth by printing money.',
        correctView:
            'Printing money without an increase in real production causes inflation (Weimar, Zimbabwe, Venezuela): more money chasing the same goods → prices rise, purchasing power collapses.',
        probePattern:
            'If the ECB doubled the money supply overnight in Europe without producing more goods, what would happen to prices? And to purchasing power according to [concept]?',
      ),
    },
  ),

  // ── Philosophy (3) ──
  const Misconception(
    id: 'is-ought-conflation',
    discipline: Discipline.philosophy,
    conceptKeywordsByLang: {
      'it': ['etica', 'morale', 'norma', 'fatto', 'valore'],
      'en': ['ethic', 'moral', 'norm', 'fact', 'value'],
    },
    textsByLang: {
      'it': MisconceptionText(
        misconception:
            'Da come SONO le cose discende necessariamente come DEVONO essere (la natura ci dice cosa è giusto).',
        correctView:
            'Hume\'s law: non si può dedurre logicamente un "deve" da un "è". Ogni argomento normativo richiede premesse normative. (G.E. Moore: naturalistic fallacy.)',
        probePattern:
            'In natura il leone uccide la gazzella. Quindi è giusto che gli umani uccidano altri umani? Cosa dice [concept] sul passaggio is→ought?',
      ),
      'en': MisconceptionText(
        misconception:
            'From how things ARE necessarily follows how they OUGHT to be (nature tells us what is right).',
        correctView:
            'Hume\'s law: you cannot logically derive an "ought" from an "is". Every normative argument requires normative premises (G.E. Moore: naturalistic fallacy).',
        probePattern:
            'In nature, lions kill gazelles. Therefore is it right for humans to kill humans? What does [concept] say about the is→ought leap?',
      ),
    },
  ),
  const Misconception(
    id: 'foundationalism-only',
    discipline: Discipline.philosophy,
    conceptKeywordsByLang: {
      'it': ['conoscenza', 'fondamento', 'epistemolog', 'giustificaz'],
      'en': ['knowledge', 'foundation', 'epistemology', 'justification'],
    },
    textsByLang: {
      'it': MisconceptionText(
        misconception:
            'Ogni conoscenza giustificata richiede credenze di base indubitabili (intuizioni, sensazioni dirette).',
        correctView:
            'Alternativa: coerentismo (giustificazione = coerenza nella rete di credenze), reliabilismo (giustificazione = prodotto di processi affidabili). Foundationalism non è l\'unica opzione.',
        probePattern:
            'Su cosa si fondano le tue credenze di base? Su altre credenze (regresso) o su un dato indubitabile (e quale)? Cosa dice [concept] sulle alternative al fondamento?',
      ),
      'en': MisconceptionText(
        misconception:
            'Justified knowledge requires indubitable basic beliefs (intuitions, direct sensations).',
        correctView:
            'Alternatives exist: coherentism (justification = coherence within belief network), reliabilism (justification = product of reliable processes). Foundationalism is not the only option.',
        probePattern:
            'What grounds your basic beliefs? Other beliefs (regress) or an indubitable given (which one)? What does [concept] say about alternatives to foundations?',
      ),
    },
  ),
  const Misconception(
    id: 'relativism-tolerance',
    discipline: Discipline.philosophy,
    conceptKeywordsByLang: {
      'it': ['relativismo', 'tolleranza', 'cultura', 'morale'],
      'en': ['relativism', 'tolerance', 'culture', 'moral'],
    },
    textsByLang: {
      'it': MisconceptionText(
        misconception:
            'Il relativismo culturale implica tolleranza universale: dobbiamo accettare tutte le pratiche di tutte le culture.',
        correctView:
            'Il relativismo descrittivo (le culture differiscono) non implica relativismo normativo (tutto è ammissibile). E "tolleranza universale" è essa stessa una norma universale, contraddice il relativismo.',
        probePattern:
            'Se "tutte le culture sono moralmente equivalenti" è una posizione universale, contraddice se stessa? Cosa dice [concept] sull\'autocontraddizione?',
      ),
      'en': MisconceptionText(
        misconception:
            'Cultural relativism implies universal tolerance: we must accept all practices of all cultures.',
        correctView:
            'Descriptive relativism (cultures differ) does not imply normative relativism (anything goes). "Universal tolerance" is itself a universal norm and contradicts relativism.',
        probePattern:
            'If "all cultures are morally equivalent" is itself a universal claim, does it contradict itself? What does [concept] say about self-contradiction?',
      ),
    },
  ),

  // ── History (2) ──
  const Misconception(
    id: 'great-man-causation',
    discipline: Discipline.history,
    conceptKeywordsByLang: {
      'it': ['rivoluzione', 'guerra', 'leader', 'causa', 'cambiament'],
      'en': ['revolution', 'war', 'leader', 'cause', 'change'],
    },
    textsByLang: {
      'it': MisconceptionText(
        misconception:
            'I grandi eventi storici sono causati da singoli individui eccezionali (Napoleone, Hitler, Cesare).',
        correctView:
            'Le strutture (economiche, sociali, demografiche) creano le CONDIZIONI per gli eventi; i singoli individui agiscono dentro vincoli storici. Senza la crisi del 1929, Hitler resta un agitatore marginale.',
        probePattern:
            'Senza la rivoluzione industriale, Napoleone avrebbe potuto conquistare l\'Europa? Le sue armate dipendevano da quale infrastruttura? Cosa dice [concept] sulla causa storica?',
      ),
      'en': MisconceptionText(
        misconception:
            'Major historical events are caused by exceptional individuals (Napoleon, Hitler, Caesar).',
        correctView:
            'Structural factors (economic, social, demographic) create the CONDITIONS for events; individuals act within historical constraints. Without the 1929 crisis, Hitler remains a marginal agitator.',
        probePattern:
            'Without the Industrial Revolution, could Napoleon have conquered Europe? His armies depended on what infrastructure? What does [concept] say about historical causation?',
      ),
    },
  ),
  const Misconception(
    id: 'anachronistic-judgment',
    discipline: Discipline.history,
    conceptKeywordsByLang: {
      'it': ['storia', 'epoca', 'morale', 'giudizi', 'civiltà'],
      'en': ['history', 'era', 'moral', 'judgment', 'civilization'],
    },
    textsByLang: {
      'it': MisconceptionText(
        misconception:
            'Le società del passato erano "arretrate" perché non condividevano i nostri valori morali (es. abolizione della schiavitù).',
        correctView:
            'Giudicare il passato con categorie morali contemporanee è anacronistico; ogni epoca va capita nei suoi quadri concettuali. Questo NON implica relativismo (vedi misconception philosophy).',
        probePattern:
            'Aristotele difendeva la schiavitù come "naturale". Era un cattivo filosofo per i tuoi standard, o stava ragionando dentro quadri concettuali diversi? Cosa dice [concept] sull\'anacronismo?',
      ),
      'en': MisconceptionText(
        misconception:
            'Past societies were "backward" because they did not share our moral values (e.g. abolition of slavery).',
        correctView:
            'Judging the past with contemporary moral categories is anachronistic; each era must be understood within its conceptual frame. This does NOT imply relativism (see philosophy misconception).',
        probePattern:
            "Aristotle defended slavery as 'natural'. Was he a bad philosopher by your standards, or was he reasoning within a different conceptual frame? What does [concept] say about anachronism?",
      ),
    },
  ),
];

// ─── Public API ───────────────────────────────────────────────────────────

/// Returns all misconceptions grouped by discipline (read-only).
Map<Discipline, List<Misconception>> get kMisconceptionLibrary {
  final map = <Discipline, List<Misconception>>{};
  for (final m in _kAllMisconceptions) {
    map.putIfAbsent(m.discipline, () => []).add(m);
  }
  return map;
}

/// Infer the dominant discipline from a set of cluster texts. Uses
/// WORD-BOUNDARY keyword matching (case-insensitive) over the curated
/// discipline keyword sets above, scoped to [language].
///
/// Default [language] is `'it'` (Italian — launch market). When a
/// language has no keyword set, falls back to `'it'` automatically.
///
/// Returns [Discipline.generic] when the signal is ambiguous (top score
/// does not beat the runner-up by ≥30%, or no discipline scored ≥1 hit).
Discipline inferDiscipline(
  Iterable<String> texts, {
  String language = 'it',
}) {
  if (texts.isEmpty) return Discipline.generic;
  final combined = texts.join(' ').toLowerCase();
  if (combined.trim().isEmpty) return Discipline.generic;

  final scores = <Discipline, int>{};
  for (final entry in _kDisciplineKeywords.entries) {
    final perLangKeywords =
        entry.value[language] ?? entry.value['it'] ?? const <String>[];
    int score = 0;
    for (final kw in perLangKeywords) {
      final pattern = RegExp(
        r'\b' + RegExp.escape(kw.toLowerCase()),
        caseSensitive: false,
      );
      score += pattern.allMatches(combined).length;
    }
    if (score > 0) scores[entry.key] = score;
  }
  if (scores.isEmpty) return Discipline.generic;

  final sorted = scores.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  if (sorted.length == 1) return sorted.first.key;

  final top = sorted[0];
  final runnerUp = sorted[1];
  if (top.value < runnerUp.value * 1.3) return Discipline.generic;
  return top.key;
}

/// Pick a misconception relevant to the given cluster texts, scoped to
/// [language]. Filters the library for the given [discipline], then
/// returns the first entry whose `conceptKeywordsByLang[language]`
/// substring-match at least one of [texts].
///
/// Returns `null` when:
///   • discipline is [Discipline.generic]
///   • no keyword match against any cluster text
///   • the library has no entries for the discipline (defensive)
///
/// Deterministic: same inputs always produce the same output.
Misconception? pickMisconceptionFor(
  Discipline discipline,
  Iterable<String> texts, {
  String language = 'it',
}) {
  if (discipline == Discipline.generic) return null;
  final pool = kMisconceptionLibrary[discipline];
  if (pool == null || pool.isEmpty) return null;
  final joined = texts.join(' ').toLowerCase();
  if (joined.trim().isEmpty) return null;

  for (final m in pool) {
    final kws = m.keywordsFor(language);
    for (final kw in kws) {
      final pattern = RegExp(
        r'\b' + RegExp.escape(kw.toLowerCase()),
        caseSensitive: false,
      );
      if (pattern.hasMatch(joined)) return m;
    }
  }
  return null;
}
