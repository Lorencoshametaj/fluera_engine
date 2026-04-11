// ============================================================================
// 📋 CONTENT TAXONOMY — Tracking content origin for SRS integrity (A20.3)
//
// Specifica: A20-38 → A20-46
//
// Every piece of content on the canvas has an INPUT METHOD that determines
// how the SRS treats it:
//
//   🟢 GENERATED — Written by hand (pen/pencil/highlighter)
//       → Full SRS tracking, full pedagogical weight
//       → This is the GOLD STANDARD (Generation Effect §3)
//
//   🔵 REFERENCE — Imported PDF, image, typed text, formula reference
//       → SRS tracks only handwritten annotations ON the reference
//       → The reference itself is excluded from recall testing
//
//   🔴 AI_GENERATED — Produced by Socratic AI, Ghost Map, etc.
//       → SRS tracks, but with reduced initial_stability (0.5)
//       → Student hasn't GENERATED it, only RECEIVED it
//
//   ⚪ PASTED — Clipboard paste from external source
//       → SRS tracks with very low initial_stability (0.3) (A20-60)
//       → Socratic AI ignores pasted content (A20-59)
//       → Visual: dashed border, 90% opacity (A20-58)
//
// ARCHITECTURAL NOTE:
//   This is a pure data model — no rendering, no widgets.
//   Stored as metadata on CanvasNode (via JSON extension field).
//   The SRS, Socratic AI, and overlay renderers read this data.
// ============================================================================

/// The method by which content was created (A20-38 → A20-46).
///
/// Determines SRS scheduling parameters and AI interaction rules.
enum InputMethod {
  /// 🟢 Handwritten by the student (pen, pencil, highlighter).
  ///
  /// Full SRS weight. This is the pedagogically optimal input.
  generated('generated', '🟢', 1.0),

  /// 🔵 Imported reference material (PDF, image, typed text).
  ///
  /// Excluded from recall testing itself. Only handwritten
  /// annotations ON the reference are tracked.
  reference('reference', '🔵', 0.0),

  /// 🔴 Produced by the AI (Socratic answers, Ghost Map labels).
  ///
  /// Reduced SRS weight — the student received but didn't generate it.
  aiGenerated('ai_generated', '🔴', 0.5),

  /// ⚪ Pasted from clipboard (A20-58).
  ///
  /// Very low SRS weight. Socratic AI ignores it (A20-59).
  /// Visual distinction: dashed border, 90% opacity.
  pasted('pasted', '⚪', 0.3);

  const InputMethod(this.key, this.icon, this.srsStabilityModifier);

  /// Serialization key.
  final String key;

  /// Display icon.
  final String icon;

  /// Modifier applied to FSRS initial_stability.
  ///
  /// 1.0 = full weight (generated)
  /// 0.5 = half weight (AI)
  /// 0.3 = low weight (pasted, A20-60)
  /// 0.0 = excluded from SRS (reference)
  final double srsStabilityModifier;

  /// Whether this content should be included in SRS tracking.
  bool get isTrackedBySrs => srsStabilityModifier > 0.0;

  /// Whether the Socratic AI should interrogate this content (A20-59).
  bool get isSocraticTarget => this == InputMethod.generated;

  /// Whether this content needs visual distinction (A20-58).
  bool get needsVisualDistinction => this == InputMethod.pasted;

  /// Parse from serialized key.
  static InputMethod fromKey(String? key) {
    if (key == null) return InputMethod.generated; // Default: handwritten.
    return InputMethod.values.firstWhere(
      (v) => v.key == key,
      orElse: () => InputMethod.generated,
    );
  }
}

/// Metadata attached to a CanvasNode for content taxonomy.
///
/// Stored in the node's JSON as an extension field:
/// ```json
/// {
///   "type": "stroke_node",
///   "taxonomy": {
///     "inputMethod": "generated",
///     "createdAt": 1712755200000,
///     "sourceId": null
///   }
/// }
/// ```
class ContentTaxonomy {
  /// How this content was created.
  final InputMethod inputMethod;

  /// When this content was created.
  final DateTime createdAt;

  /// Source identifier (e.g., PDF page, clipboard source URL).
  final String? sourceId;

  /// Whether this content has been manually reclassified by the student.
  final bool manuallyReclassified;

  const ContentTaxonomy({
    required this.inputMethod,
    required this.createdAt,
    this.sourceId,
    this.manuallyReclassified = false,
  });

  /// Default taxonomy for handwritten content.
  factory ContentTaxonomy.generated() => ContentTaxonomy(
        inputMethod: InputMethod.generated,
        createdAt: DateTime.now(),
      );

  /// Taxonomy for pasted content (A20-58).
  factory ContentTaxonomy.pasted({String? sourceId}) => ContentTaxonomy(
        inputMethod: InputMethod.pasted,
        createdAt: DateTime.now(),
        sourceId: sourceId,
      );

  /// Taxonomy for reference material.
  factory ContentTaxonomy.reference({String? sourceId}) => ContentTaxonomy(
        inputMethod: InputMethod.reference,
        createdAt: DateTime.now(),
        sourceId: sourceId,
      );

  /// Taxonomy for AI-generated content.
  factory ContentTaxonomy.aiGenerated() => ContentTaxonomy(
        inputMethod: InputMethod.aiGenerated,
        createdAt: DateTime.now(),
      );

  // ── SRS Integration ───────────────────────────────────────────────────

  /// Calculate the initial FSRS stability for this content (A20-60).
  ///
  /// The base stability comes from the FSRS algorithm; this modifier
  /// scales it based on how the content was created.
  double adjustInitialStability(double baseStability) {
    return baseStability * inputMethod.srsStabilityModifier;
  }

  // ── Visual Properties (A20-58) ────────────────────────────────────────

  /// Whether this content should use a dashed border (A20-58).
  bool get useDashedBorder => inputMethod == InputMethod.pasted;

  /// Opacity multiplier for pasted content (A20-58: 90%).
  double get opacityMultiplier =>
      inputMethod == InputMethod.pasted ? 0.90 : 1.0;

  // ── Serialization ─────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'inputMethod': inputMethod.key,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'sourceId': sourceId,
        'manuallyReclassified': manuallyReclassified,
      };

  factory ContentTaxonomy.fromJson(Map<String, dynamic> json) {
    return ContentTaxonomy(
      inputMethod: InputMethod.fromKey(json['inputMethod'] as String?),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (json['createdAt'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
      ),
      sourceId: json['sourceId'] as String?,
      manuallyReclassified: json['manuallyReclassified'] as bool? ?? false,
    );
  }

  /// Create a copy with a changed input method (manual reclassification).
  ContentTaxonomy reclassify(InputMethod newMethod) => ContentTaxonomy(
        inputMethod: newMethod,
        createdAt: createdAt,
        sourceId: sourceId,
        manuallyReclassified: true,
      );
}
