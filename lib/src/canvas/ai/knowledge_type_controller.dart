// ============================================================================
// 📚 KNOWLEDGE TYPE CONTROLLER — Content-aware SRS adaptation (A20.6)
//
// Specifica: A20.6-01 → A20.6-08
//
// Different knowledge types require different learning strategies.
// This controller tags each zone/cluster with its knowledge type
// and provides SRS parameter modifiers accordingly.
//
// TYPES:
//   - Declarative: facts, definitions (standard spacing)
//   - Procedural: steps, algorithms (more practice, less flashcard)
//   - Linguistic: vocabulary, grammar (shorter intervals, more reps)
//   - Mathematical: formulas, proofs (problem variation, not repetition)
//   - Visual: anatomy, maps, diagrams (spatial recall, ghost map heavy)
//
// RULES:
//   - Each zone has exactly ONE knowledge type (default: declarative)
//   - Type can be set manually or auto-detected from content
//   - SRS modifiers are multiplicative (applied to base intervals)
//   - Ghost Map weight varies by type (visual > declarative > procedural)
//
// ARCHITECTURE:
//   Pure model — serializable, no UI, no platform dependencies.
//   Integrates with FsrsScheduler via parameter modifiers.
//
// THREAD SAFETY: Main isolate only.
// ============================================================================

/// 📚 Knowledge type classification.
enum KnowledgeType {
  /// Facts, definitions, dates, names.
  /// Standard SRS spacing works well.
  declarative,

  /// Steps, algorithms, procedures.
  /// Needs practice problems, not just recall.
  procedural,

  /// Vocabulary, grammar, idioms.
  /// Shorter intervals, more repetitions needed.
  linguistic,

  /// Formulas, proofs, equations.
  /// Problem variation > identical repetition.
  mathematical,

  /// Anatomy, maps, diagrams, charts.
  /// Spatial recall, Ghost Map-heavy learning.
  visual,
}

/// 📚 SRS parameter modifiers for a knowledge type.
class KnowledgeTypeModifiers {
  /// Multiplier for SRS interval (1.0 = standard, <1.0 = shorter).
  final double intervalMultiplier;

  /// Multiplier for ease factor adjustment.
  final double easeFactor;

  /// How heavily Ghost Map is weighted for this type (0.0–1.0).
  final double ghostMapWeight;

  /// How heavily Fog of War is weighted (0.0–1.0).
  final double fogWeight;

  /// Whether to prefer practice problems over recall flashcards.
  final bool preferPractice;

  /// Whether to vary problem presentation (math: different numbers).
  final bool variateProblems;

  /// Recommended minimum reviews per day for this type.
  final int minDailyReviews;

  /// Emoji icon for the type.
  final String icon;

  /// Italian label.
  final String labelIt;

  const KnowledgeTypeModifiers({
    required this.intervalMultiplier,
    required this.easeFactor,
    required this.ghostMapWeight,
    required this.fogWeight,
    required this.preferPractice,
    required this.variateProblems,
    required this.minDailyReviews,
    required this.icon,
    required this.labelIt,
  });
}

/// 📚 Knowledge Type Controller (A20.6).
///
/// Tags zones with knowledge types and provides SRS modifiers.
///
/// Usage:
/// ```dart
/// final controller = KnowledgeTypeController();
///
/// // Tag a zone
/// controller.setType('zone_bio', KnowledgeType.visual);
///
/// // Get SRS modifiers for scheduling
/// final mods = controller.getModifiers('zone_bio');
/// final adjustedInterval = baseInterval * mods.intervalMultiplier;
/// ```
class KnowledgeTypeController {
  /// Creates a new knowledge type controller.
  KnowledgeTypeController();

  /// Zone ID → knowledge type mapping.
  final Map<String, KnowledgeType> _zoneTypes = {};

  /// Default type for untagged zones.
  static const KnowledgeType defaultType = KnowledgeType.declarative;

  /// All modifier presets.
  static const Map<KnowledgeType, KnowledgeTypeModifiers> modifiers = {
    KnowledgeType.declarative: KnowledgeTypeModifiers(
      intervalMultiplier: 1.0,
      easeFactor: 1.0,
      ghostMapWeight: 0.5,
      fogWeight: 0.5,
      preferPractice: false,
      variateProblems: false,
      minDailyReviews: 10,
      icon: '📖',
      labelIt: 'Dichiarativo',
    ),
    KnowledgeType.procedural: KnowledgeTypeModifiers(
      intervalMultiplier: 0.8,
      easeFactor: 0.9,
      ghostMapWeight: 0.3,
      fogWeight: 0.6,
      preferPractice: true,
      variateProblems: false,
      minDailyReviews: 8,
      icon: '⚙️',
      labelIt: 'Procedurale',
    ),
    KnowledgeType.linguistic: KnowledgeTypeModifiers(
      intervalMultiplier: 0.6, // Shorter intervals for vocab
      easeFactor: 0.85,
      ghostMapWeight: 0.4,
      fogWeight: 0.4,
      preferPractice: false,
      variateProblems: false,
      minDailyReviews: 20, // More reps needed
      icon: '🗣️',
      labelIt: 'Linguistico',
    ),
    KnowledgeType.mathematical: KnowledgeTypeModifiers(
      intervalMultiplier: 0.9,
      easeFactor: 0.95,
      ghostMapWeight: 0.3,
      fogWeight: 0.7,
      preferPractice: true,
      variateProblems: true, // Key: vary the numbers
      minDailyReviews: 5,
      icon: '🧮',
      labelIt: 'Matematico',
    ),
    KnowledgeType.visual: KnowledgeTypeModifiers(
      intervalMultiplier: 1.1, // Visual memory lasts longer
      easeFactor: 1.0,
      ghostMapWeight: 0.9, // Ghost Map is key
      fogWeight: 0.8,
      preferPractice: false,
      variateProblems: false,
      minDailyReviews: 8,
      icon: '🖼️',
      labelIt: 'Visuale',
    ),
  };

  /// Set the knowledge type for a zone.
  void setType(String zoneId, KnowledgeType type) {
    _zoneTypes[zoneId] = type;
  }

  /// Get the knowledge type for a zone.
  KnowledgeType getType(String zoneId) =>
      _zoneTypes[zoneId] ?? defaultType;

  /// Get SRS modifiers for a zone.
  KnowledgeTypeModifiers getModifiers(String zoneId) =>
      modifiers[getType(zoneId)]!;

  /// Get all tagged zones.
  Map<String, KnowledgeType> get allTypes =>
      Map.unmodifiable(_zoneTypes);

  /// Number of tagged zones.
  int get taggedCount => _zoneTypes.length;

  /// Auto-detect knowledge type from content keywords.
  ///
  /// Simple heuristic — real detection would use embeddings.
  static KnowledgeType detectFromContent(String text) {
    final lower = text.toLowerCase();

    // Mathematical indicators
    final mathPatterns = [
      '∑', '∫', 'formula', 'equazione', 'teorema',
      'dimostrazione', 'derivata', 'integrale', 'logaritmo',
    ];
    int mathScore = mathPatterns.where((p) => lower.contains(p)).length;

    // Linguistic indicators
    final lingPatterns = [
      'vocabolario', 'vocabulary', 'traduzione', 'translation',
      'grammatica', 'grammar', 'verbo', 'verb', 'conjugazione',
    ];
    int lingScore = lingPatterns.where((p) => lower.contains(p)).length;

    // Procedural indicators
    final procPatterns = [
      'step', 'passo', 'procedura', 'algoritmo', 'istruzioni',
      'come fare', 'how to', 'prima', 'poi', 'infine',
    ];
    int procScore = procPatterns.where((p) => lower.contains(p)).length;

    // Visual indicators
    final visPatterns = [
      'anatomia', 'anatomy', 'diagramma', 'diagram', 'mappa',
      'schema', 'grafico', 'chart', 'immagine', 'image',
    ];
    int visScore = visPatterns.where((p) => lower.contains(p)).length;

    // Pick highest score
    final scores = {
      KnowledgeType.mathematical: mathScore,
      KnowledgeType.linguistic: lingScore,
      KnowledgeType.procedural: procScore,
      KnowledgeType.visual: visScore,
    };

    final best = scores.entries.reduce((a, b) => a.value > b.value ? a : b);
    if (best.value >= 2) return best.key;

    return KnowledgeType.declarative; // Default fallback
  }

  // ── Serialization ─────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'zoneTypes': _zoneTypes.map((k, v) => MapEntry(k, v.name)),
      };

  factory KnowledgeTypeController.fromJson(Map<String, dynamic> json) {
    final controller = KnowledgeTypeController();
    final raw = json['zoneTypes'] as Map<String, dynamic>? ?? {};
    for (final entry in raw.entries) {
      final type = KnowledgeType.values
          .where((t) => t.name == entry.value)
          .firstOrNull;
      if (type != null) {
        controller._zoneTypes[entry.key] = type;
      }
    }
    return controller;
  }
}
