// ============================================================================
// 🧠 ClusterConcept — Single source of truth for "what does this cluster
// talk about", consumed by Semantic Titles, Atlas Exam, Socratic Mode and
// Ghost Map.
//
// Each cognitive feature used to derive its own answer to that question:
//   • Semantic Titles → AI-generated 2-6 word title
//   • Exam → topic grouping LLM call
//   • Socratic → raw OCR pasted into the prompt
//   • Ghost Map → its own concept extraction
// All four were wasting Gemini calls on data the others had already
// computed. ClusterConcept is the shared structure — every field is
// independently nullable and lazily populated by [ClusterConceptIndex].
// ============================================================================

enum AskedBy { exam, socratic, ghostMap, crossZone }

class AskedQuestion {
  final String text;
  final AskedBy by;
  final DateTime at;

  const AskedQuestion({
    required this.text,
    required this.by,
    required this.at,
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'by': by.name,
        'at': at.toIso8601String(),
      };

  factory AskedQuestion.fromJson(Map<String, dynamic> j) => AskedQuestion(
        text: j['text'] as String? ?? '',
        by: AskedBy.values.firstWhere(
          (e) => e.name == (j['by'] as String?),
          orElse: () => AskedBy.socratic,
        ),
        at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
      );
}

class ClusterConcept {
  final String clusterId;

  /// Raw MyScript label after dictionary re-rank. May still contain
  /// minor OCR artifacts (`null` until first OCR pass).
  String? rawOcr;

  /// LLM-cleaned version of [rawOcr] for Italian prose (`null` until
  /// a feature explicitly requests `needsCleanedOcr: true`).
  String? cleanedOcr;

  /// 2-6 word AI title shown above the cluster at low zoom (`null`
  /// until `needsTitle: true`). Powered by `_socraticModel` /
  /// Atlas batch — see `_generateTitleBatch` in the index.
  String? title;

  /// Broader theme used by Exam topic grouping (`null` until
  /// `needsTopic: true`). Distinct from [title]: a cluster's title
  /// might be "Prima legge" while its topic is "Meccanica classica".
  String? topic;

  /// Named entities for cross-feature avoid / Ghost Map graph.
  /// Empty when not yet populated.
  List<String> concepts;

  DateTime lastUpdated;

  /// Bumped when any field is recomputed; downstream caches that
  /// depend on a derived field key off this number to invalidate.
  int sourceVersion;

  /// Hash of the strokeIds that produced [rawOcr]. When the cluster
  /// stroke set changes meaningfully, the index recomputes.
  int strokeChecksum;

  /// Version of the `cleanOcrItalian` prompt that produced
  /// [cleanedOcr]. Bumped whenever the prompt is changed in a way
  /// that affects existing cached output (e.g. adding anti-LaTeX
  /// hallucination rules). The index compares this against its
  /// current prompt version constant and recomputes when stale.
  ///
  /// Default 0 = pre-versioning era → ALWAYS treated as stale, so
  /// every device that upgrades regenerates clean OCR on first
  /// resolve. After regeneration the value tracks the live constant.
  int cleanedOcrPromptVersion;

  /// Version of the title-generation pipeline that produced [title].
  /// Same invalidation pattern as [cleanedOcrPromptVersion]: when the
  /// index's live `_kTitlePromptVersion` is greater than this value,
  /// the cached title is discarded and regenerated. Device 2026-05-12
  /// caches contained meta-commentary like "The user wants a title
  /// for these notes" because title generation went through `askAtlas`
  /// (canvas-action system prompt) — version bump invalidates them.
  int titlePromptVersion;

  ClusterConcept({
    required this.clusterId,
    this.rawOcr,
    this.cleanedOcr,
    this.title,
    this.topic,
    List<String>? concepts,
    DateTime? lastUpdated,
    this.sourceVersion = 1,
    this.strokeChecksum = 0,
    this.cleanedOcrPromptVersion = 0,
    this.titlePromptVersion = 0,
  })  : concepts = concepts ?? <String>[],
        lastUpdated = lastUpdated ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'clusterId': clusterId,
        'rawOcr': rawOcr,
        'cleanedOcr': cleanedOcr,
        'title': title,
        'topic': topic,
        'concepts': concepts,
        'lastUpdated': lastUpdated.toIso8601String(),
        'sourceVersion': sourceVersion,
        'strokeChecksum': strokeChecksum,
        'cleanedOcrPromptVersion': cleanedOcrPromptVersion,
        'titlePromptVersion': titlePromptVersion,
      };

  factory ClusterConcept.fromJson(Map<String, dynamic> j) => ClusterConcept(
        clusterId: j['clusterId'] as String,
        rawOcr: j['rawOcr'] as String?,
        cleanedOcr: j['cleanedOcr'] as String?,
        title: j['title'] as String?,
        topic: j['topic'] as String?,
        concepts: (j['concepts'] as List?)?.cast<String>() ?? const [],
        lastUpdated:
            DateTime.tryParse(j['lastUpdated'] as String? ?? '') ?? DateTime.now(),
        sourceVersion: (j['sourceVersion'] as num?)?.toInt() ?? 1,
        strokeChecksum: (j['strokeChecksum'] as num?)?.toInt() ?? 0,
        cleanedOcrPromptVersion:
            (j['cleanedOcrPromptVersion'] as num?)?.toInt() ?? 0,
        titlePromptVersion:
            (j['titlePromptVersion'] as num?)?.toInt() ?? 0,
      );

  /// Best human-readable text for this cluster, in priority order:
  /// title → cleanedOcr → rawOcr → empty. Used by UI surfaces that
  /// want the "best label so far" without caring about the source.
  String get bestLabel {
    if (title != null && title!.trim().isNotEmpty) return title!;
    if (cleanedOcr != null && cleanedOcr!.trim().isNotEmpty) return cleanedOcr!;
    if (rawOcr != null && rawOcr!.trim().isNotEmpty) return rawOcr!;
    return '';
  }

  /// Best text source for AI prompts (Socratic, Exam): always prefer
  /// [cleanedOcr] over [rawOcr] when present. The title is ignored
  /// here — it's a label, not a content snapshot.
  String? get bestPromptSource {
    if (cleanedOcr != null && cleanedOcr!.trim().isNotEmpty) return cleanedOcr;
    if (rawOcr != null && rawOcr!.trim().isNotEmpty) return rawOcr;
    return null;
  }
}
