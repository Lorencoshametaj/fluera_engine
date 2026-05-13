// ============================================================================
// 🧠 ClusterConceptIndex — Per-canvas service that resolves the canonical
// "concept" for each cluster. Replaces the four-way duplication where
// Semantic Titles, Atlas Exam, Socratic Mode and Ghost Map each ran their
// own OCR+LLM pipeline on the same strokes.
//
// USAGE:
//   final concept = await index.resolve(cluster, needsCleanedOcr: true,
//                                       needsTitle: true);
//   final prompt = concept.bestPromptSource;
//   final label = concept.bestLabel;
//
// CONTRACT:
//   • Idempotent: calling resolve() twice for the same cluster doesn't
//     re-fire AI calls; in-flight Futures are deduplicated.
//   • Lazy: only the requested fields are populated. needsTitle=true
//     does NOT also generate cleanedOcr unless explicitly asked.
//   • Cancel-safe: if the cluster is invalidated mid-resolve, the
//     pending Future still completes (with the values it computed so
//     far) but the result is discarded by the caller — the entry is
//     wiped from the index.
//
// LIFECYCLE: instantiated per `_FlueraCanvasScreenState`. Disposed when
// the canvas screen unmounts. Not a global singleton: a canvas owns its
// concept space (multi-canvas isolation, GC on dispose).
// ============================================================================

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../ai/ai_provider.dart';
import '../../utils/ai_language_preference.dart';
import '../../drawing/models/pro_drawing_point.dart';
import '../../reflow/content_cluster.dart';
import '../../services/cluster_concept_persistence.dart';
import '../../services/digital_ink_service.dart';
import '../../services/italian_ocr_corrector.dart';
import 'cluster_concept.dart';
import 'fsrs_scheduler.dart' show SrsCardData;

/// Maximum questions remembered per cluster before evicting the oldest.
const int _kAvoidRingCap = 8;

/// Version of the `cleanOcrItalian` prompt. Increment whenever the prompt
/// changes in a way that should invalidate existing cached `cleanedOcr`
/// values on disk. Concepts whose `cleanedOcrPromptVersion` is less than
/// this constant have their `cleanedOcr` discarded and regenerated.
///
/// Version history:
/// - 0: pre-versioning (all pre-2026-05-12 caches)
/// - 1: 2026-05-12 — added Italian fusion examples ("LEGGITI"→"LEGGI DI")
/// - 2: 2026-05-12 — added anti-LaTeX hallucination rule
///   ("CORPO A R' to" → "CORPO A RIPOSO", NOT "R^{2}")
const int _kCleanedOcrPromptVersion = 2;

/// Version of the title-generation path. Invalidates [ClusterConcept.title]
/// from disk when stale.
///
/// Version history:
/// - 0: pre-versioning. Includes the buggy era where _generateTitle and
///   bulkGenerateTitles went through `askAtlas`, which uses the canvas-
///   action system prompt → Gemini emitted meta-commentary in the
///   `spiegazione` field (e.g. "The user wants a title for these notes")
///   and the index stored it as the title. Device 2026-05-12.
/// - 1: 2026-05-12 — both paths now go through `askFreeText`, which uses
///   `_streamModel` (no system prompt, no JSON mimeType).
/// - 2: 2026-05-12 — title prompt now enforces native-language output
///   (device produced "Newton's Laws" in English on an Italian device
///   when Gemini drifted). The prompt explicitly bans cross-language
///   drift and includes the language name in native form.
const int _kTitlePromptVersion = 6;

class ClusterConceptIndex extends ChangeNotifier {
  ClusterConceptIndex({
    required AiProvider? Function() providerFn,
    required Map<String, ProStroke> Function() strokeMapFn,
    required Map<String, SrsCardData> Function() reviewScheduleFn,
    required String Function() languageNameFn,
    DigitalInkService? inkService,
  })  : _providerFn = providerFn,
        _strokeMapFn = strokeMapFn,
        _reviewScheduleFn = reviewScheduleFn,
        _languageNameFn = languageNameFn,
        _inkService = inkService ?? DigitalInkService.instance;

  final AiProvider? Function() _providerFn;
  final Map<String, ProStroke> Function() _strokeMapFn;
  final Map<String, SrsCardData> Function() _reviewScheduleFn;
  final String Function() _languageNameFn;
  final DigitalInkService _inkService;

  /// The canonical concept map. Painters read via [snapshot].
  final Map<String, ClusterConcept> _concepts = {};

  /// Memoize-while-pending — concurrent resolve() calls share the same
  /// in-flight Future per cluster.
  final Map<String, Future<ClusterConcept>> _inflight = {};

  /// Cross-feature avoid ring buffer per cluster (cap [_kAvoidRingCap]).
  final Map<String, Queue<AskedQuestion>> _askedRing = {};

  /// Cache for topic grouping results keyed by `sorted clusterIds hash`.
  /// Hit when a feature (Socratic, Exam) re-opens on the same scope —
  /// avoids a Gemini batch grouping call. Invalidated by
  /// [invalidate]/[upsertConcepts]/[setTopic] which bump the version.
  final Map<int, List<({String topic, List<String> clusterIds})>>
      _topicGroupingCache = {};

  /// Pending invalidations to apply on next resolve (lets us defer
  /// notifyListeners during heavy stroke editing).
  final Set<String> _invalidated = {};

  bool _disposed = false;

  // ────────────────────────────────────────────────────────────────────
  // Read API
  // ────────────────────────────────────────────────────────────────────

  /// Synchronous snapshot for painters / UI consumers that can't await.
  /// Returns an unmodifiable view of the current concepts map.
  Map<String, ClusterConcept> snapshot() => UnmodifiableMapView(_concepts);

  /// Latest concept for [clusterId] without triggering any work.
  /// Returns `null` if not yet resolved.
  ClusterConcept? peek(String clusterId) => _concepts[clusterId];

  /// FSRS card associated with the cluster's concepts. Used by Atlas
  /// Exam to modulate per-cluster difficulty.
  SrsCardData? srsFor(String clusterId) {
    final concept = _concepts[clusterId];
    if (concept == null || concept.concepts.isEmpty) return null;
    final schedule = _reviewScheduleFn();
    // First match — Concepts list is small (1-5 entities) so O(n) is fine.
    for (final c in concept.concepts) {
      final card = schedule[c];
      if (card != null) return card;
    }
    return null;
  }

  /// Recent questions across all features for [clusterId].
  /// Most-recent first. Capped at [n].
  List<String> recentQuestionsFor(String clusterId, {int n = 8}) {
    final ring = _askedRing[clusterId];
    if (ring == null || ring.isEmpty) return const [];
    final list = ring.toList(growable: false);
    // ring is FIFO (oldest at .first); we want most-recent first.
    final reversed = list.reversed.take(n).map((q) => q.text).toList();
    return reversed;
  }

  // ────────────────────────────────────────────────────────────────────
  // Write API
  // ────────────────────────────────────────────────────────────────────

  /// Record a question that was asked about [clusterId] by [by]. Used
  /// for cross-feature avoid (Exam doesn't repeat what Socratic just
  /// asked, and vice versa). In-memory only — flushed on dispose.
  void recordQuestionAsked(String clusterId, String question, AskedBy by) {
    if (question.trim().isEmpty) return;
    final ring = _askedRing.putIfAbsent(clusterId, () => Queue<AskedQuestion>());
    ring.addLast(AskedQuestion(text: question, by: by, at: DateTime.now()));
    while (ring.length > _kAvoidRingCap) {
      ring.removeFirst();
    }
  }

  /// Drop concept entries when a cluster's stroke set materially changed.
  /// Called from `_clusterCache` rebuild hooks. Does NOT re-fire OCR;
  /// the next resolve() call will lazily repopulate.
  void invalidate(Set<String> clusterIds) {
    if (clusterIds.isEmpty) return;
    var dirty = false;
    for (final id in clusterIds) {
      if (_concepts.remove(id) != null) dirty = true;
      _inflight.remove(id);
      _askedRing.remove(id);
    }
    // Topic groupings reference cluster IDs; any invalidation may
    // change the grouping shape so we drop the cache wholesale.
    if (clusterIds.isNotEmpty) _topicGroupingCache.clear();
    _invalidated.addAll(clusterIds);
    if (dirty) notifyListeners();
  }

  /// Inject a concept directly. Used by tests, persistence rehydration,
  /// and the `aiTitles` migration adapter (Phase A4).
  @visibleForTesting
  void seed(ClusterConcept concept) {
    _concepts[concept.clusterId] = concept;
    notifyListeners();
  }

  /// Look up a previously-cached topic grouping for [clusterIds].
  /// Returns `null` on miss. The hash uses sorted IDs so the cache hit
  /// is order-independent.
  List<({String topic, List<String> clusterIds})>? cachedTopicGrouping(
      Iterable<String> clusterIds) {
    final sorted = clusterIds.toList()..sort();
    return _topicGroupingCache[Object.hashAll(sorted)];
  }

  /// Persist a topic grouping result. Caller computes the hash via
  /// the same key shape as [cachedTopicGrouping]. The cache is cleared
  /// at canvas dispose; not persisted to disk (groupings are batch-
  /// scope and short-lived).
  void cacheTopicGrouping(
    Iterable<String> clusterIds,
    List<({String topic, List<String> clusterIds})> groups,
  ) {
    final sorted = clusterIds.toList()..sort();
    _topicGroupingCache[Object.hashAll(sorted)] = groups;
  }

  /// Write-through setter for the broader theme this cluster belongs to.
  /// Called from `_atlas_ai.dart` after Atlas Exam's `_groupClustersByTopic`
  /// returns, so cross-feature surfaces (Socratic prompt context, future
  /// review dashboards) can read the theme without re-running the LLM
  /// batch.
  ///
  /// Topic is batch-scope (depends on the cluster set being grouped at
  /// that moment), so it can change between exam sessions on different
  /// scopes. The index just stores the most-recent assignment — no
  /// versioning beyond [sourceVersion].
  void setTopic(String clusterId, String topic) {
    if (_disposed) return;
    if (topic.trim().isEmpty) return;
    final existing = _concepts[clusterId];
    if (existing == null) {
      _concepts[clusterId] = ClusterConcept(
        clusterId: clusterId,
        topic: topic,
      );
    } else {
      existing.topic = topic;
      existing.lastUpdated = DateTime.now();
      existing.sourceVersion += 1;
    }
    notifyListeners();
  }

  /// Replace the concepts list for [clusterId]. Used by Ghost Map to
  /// surface concept gaps it discovered into the cross-feature index.
  /// Caller is responsible for merge / dedup before calling. Creates a
  /// stub concept if none exists yet.
  void upsertConcepts(String clusterId, List<String> concepts) {
    if (_disposed) return;
    if (concepts.isEmpty) return;
    final existing = _concepts[clusterId];
    if (existing == null) {
      _concepts[clusterId] = ClusterConcept(
        clusterId: clusterId,
        concepts: List<String>.from(concepts),
      );
    } else {
      existing.concepts = List<String>.from(concepts);
      existing.lastUpdated = DateTime.now();
      existing.sourceVersion += 1;
    }
    notifyListeners();
  }

  /// Write-through setter for an AI-generated cluster title. Called from
  /// `_semantic_titles.dart` so the title is reused by Exam picker and
  /// any other surface without re-running the Atlas Gemini batch.
  ///
  /// Creates a stub concept if none exists yet (the title can arrive
  /// before the OCR resolve, e.g. on initial canvas open).
  void setTitle(String clusterId, String title, {String? sourceText}) {
    if (_disposed) return;
    if (title.trim().isEmpty) return;
    final existing = _concepts[clusterId];
    if (existing == null) {
      _concepts[clusterId] = ClusterConcept(
        clusterId: clusterId,
        rawOcr: sourceText,
        title: title,
        titlePromptVersion: _kTitlePromptVersion,
      );
    } else {
      existing.title = title;
      existing.titlePromptVersion = _kTitlePromptVersion;
      if (existing.rawOcr == null && sourceText != null) {
        existing.rawOcr = sourceText;
      }
      existing.lastUpdated = DateTime.now();
      existing.sourceVersion += 1;
    }
    notifyListeners();
  }

  // ────────────────────────────────────────────────────────────────────
  // Resolve — the hot path
  // ────────────────────────────────────────────────────────────────────

  /// Resolve the concept for [cluster], lazily computing only the fields
  /// the caller asked for. Idempotent — repeat calls are deduplicated
  /// via [_inflight] while pending, and short-circuit on cache hit.
  Future<ClusterConcept> resolve(
    ContentCluster cluster, {
    bool needsRawOcr = false,
    bool needsCleanedOcr = false,
    bool needsTitle = false,
    bool needsTopic = false,
    bool needsConcepts = false,
  }) {
    if (_disposed) {
      return Future.value(ClusterConcept(clusterId: cluster.id));
    }
    final key = cluster.id;
    final existing = _inflight[key];
    if (existing != null) return existing;

    final cached = _concepts[key];
    if (cached != null && _satisfies(cached, cluster, needsRawOcr,
        needsCleanedOcr, needsTitle, needsTopic, needsConcepts)) {
      return Future.value(cached);
    }

    final fut = _doResolve(
      cluster,
      needsRawOcr: needsRawOcr || needsCleanedOcr || needsTitle || needsConcepts,
      needsCleanedOcr: needsCleanedOcr,
      needsTitle: needsTitle,
      needsTopic: needsTopic,
      needsConcepts: needsConcepts,
    );
    _inflight[key] = fut;
    fut.whenComplete(() {
      _inflight.remove(key);
    });
    return fut;
  }

  bool _satisfies(
    ClusterConcept cached,
    ContentCluster cluster,
    bool needsRawOcr,
    bool needsCleanedOcr,
    bool needsTitle,
    bool needsTopic,
    bool needsConcepts,
  ) {
    final checksum = _strokeChecksum(cluster);
    if (cached.strokeChecksum != 0 && cached.strokeChecksum != checksum) {
      return false; // stroke set changed; re-resolve
    }
    if (needsRawOcr && (cached.rawOcr == null)) return false;
    if (needsCleanedOcr && (cached.cleanedOcr == null)) return false;
    if (needsTitle && (cached.title == null)) return false;
    if (needsTopic && (cached.topic == null)) return false;
    if (needsConcepts && cached.concepts.isEmpty) return false;
    // 🌍 Sprint F.1 (2026-05-13 PM) — stale title cache invalidation on
    // AiLanguagePreference change. The version bump already catches
    // cross-version invalidation; this catches cross-LANGUAGE invalidation.
    // Scenario: user has cached title "Newton's First Law" (EN) generated
    // when preference was EN. User changes preference to IT. Without this
    // check, the EN title stays cached and the user sees stale EN labels
    // on IT notes. With this check, the cached title is considered
    // "unsatisfied" on a language drift, triggering regeneration via
    // _doResolve → produces a fresh IT title.
    if (needsTitle && cached.title != null) {
      final source = cached.cleanedOcr ?? cached.rawOcr;
      if (source != null && source.trim().isNotEmpty) {
        if (_isCachedTitleDrifted(cached.title!, source)) {
          return false;
        }
      }
    }
    return true;
  }

  /// 🌍 Sprint F.1 — checks whether [title] is in a language that no
  /// longer matches the user's current target (AiLanguagePreference or
  /// OCR-detected source). Mirrors the WRITE-time check in
  /// [_titleDriftedFromSource] but applied at READ time so cached
  /// titles regenerate when the user changes language preference.
  ///
  /// 🛡️ Short-title heuristic: function-word signature detection
  /// returns 'unknown' on titles <40 chars without function words
  /// (e.g. "Newton's First Law" has zero function words). For these
  /// cases we fall back to character-pattern hints:
  ///   • English possessive `'s` (Newton's, Earth's) → likely EN
  ///   • Italian accent chars (è à ò ù ì) → likely IT
  /// Without this fallback, the device-observed "Newton's First Law"
  /// on IT-source cluster would NOT be flagged as drift.
  bool _isCachedTitleDrifted(String title, String source) {
    final detected = detectLanguageSignature(source);
    final target = detected == 'unknown'
        ? AiLanguagePreference.code()
        : detected;
    if (socraticLanguageDriftsFromSource(title, source, targetLang: target)) {
      return true;
    }
    // Short-title character-pattern fallback.
    if (title.length < 40 && target.isNotEmpty) {
      final hasEnPossessive =
          title.contains("'s ") || title.endsWith("'s");
      final hasItAccent = RegExp(r'[àèéìòù]').hasMatch(title);
      // EN possessive (Newton's, Earth's) on non-EN target → drift.
      if (target != 'en' && hasEnPossessive && !hasItAccent) {
        return true;
      }
    }
    return false;
  }

  Future<ClusterConcept> _doResolve(
    ContentCluster cluster, {
    required bool needsRawOcr,
    required bool needsCleanedOcr,
    required bool needsTitle,
    required bool needsTopic,
    required bool needsConcepts,
  }) async {
    // 🛡️ Race guard: if the index was disposed while this resolve was
    // queued, bail before touching `_concepts` (cleared on dispose).
    if (_disposed) return ClusterConcept(clusterId: cluster.id);
    final concept = _concepts.putIfAbsent(
      cluster.id,
      () => ClusterConcept(clusterId: cluster.id),
    );
    final checksum = _strokeChecksum(cluster);
    if (concept.strokeChecksum != 0 && concept.strokeChecksum != checksum) {
      // Stroke set changed since last resolve — wipe derived fields.
      concept.rawOcr = null;
      concept.cleanedOcr = null;
      concept.title = null;
      concept.topic = null;
      concept.concepts = const [];
      concept.sourceVersion += 1;
    }
    concept.strokeChecksum = checksum;

    // ── Step 1: raw OCR (MyScript + dict re-rank) ───────────────────
    if (needsRawOcr && concept.rawOcr == null) {
      concept.rawOcr = await _ocrCluster(cluster);
      concept.lastUpdated = DateTime.now();
    }

    // ── Step 2: AI cleanup (cleanOcrItalian) ────────────────────────
    // Eligibility for the Gemini cleanup pass:
    //   • cluster has ≥3 strokes (multi-token handwriting), OR
    //   • rawOcr has ≥5 chars (single compound stroke that produced a
    //     long token — e.g. cursive "prima legge" → "Primalele").
    //
    // The earlier ≥3-strokes-only rule missed device-validated bugs
    // where the user wrote a phrase in 1-2 long cursive strokes and
    // MyScript fused it into a single garbled token. The dictionary
    // re-rank can't fix single-token fusions; only the Gemini cleanup
    // can split "Primalele" → "prima legge". Reported 2026-05-10.
    //
    // 🔄 Prompt-version invalidation: if `cleanedOcr` was produced by
    // an older prompt revision (e.g. before the anti-LaTeX rule was
    // added 2026-05-12 because Gemini was turning "CORPO A R' to"
    // into "CORPO A R^{2}"), discard it so the new prompt runs.
    if (concept.cleanedOcr != null &&
        concept.cleanedOcrPromptVersion < _kCleanedOcrPromptVersion) {
      debugPrint('🔄 cleanedOcr cache invalidated for ${cluster.id}: '
          'version ${concept.cleanedOcrPromptVersion} < '
          '$_kCleanedOcrPromptVersion (prompt updated)');
      concept.cleanedOcr = null;
    }
    // Same invalidation for the cached title — old askAtlas path stored
    // canvas-action meta-commentary as title (e.g. "The user wants a
    // title for these notes"). Drop and regenerate via askFreeText.
    //
    // 🛡️ Phase 3.1 (2026-05-12 device fix): also bump `sourceVersion`
    // and call `notifyListeners()` so the persistence layer schedules
    // a save. Without this, the stale title would only be wiped from
    // RAM — the disk JSON would still contain "Newton's Laws" until
    // the 30d TTL expired, and a subsequent app restart would reload
    // it before the next resolve() ran.
    if (concept.title != null &&
        concept.titlePromptVersion < _kTitlePromptVersion) {
      debugPrint('🔄 title cache invalidated for ${cluster.id}: '
          'version ${concept.titlePromptVersion} < '
          '$_kTitlePromptVersion (was: "${concept.title}")');
      concept.title = null;
      concept.titlePromptVersion = _kTitlePromptVersion;
      concept.sourceVersion += 1;
      concept.lastUpdated = DateTime.now();
      notifyListeners();
    }
    if (needsCleanedOcr &&
        concept.cleanedOcr == null &&
        (concept.rawOcr ?? '').trim().isNotEmpty) {
      final provider = _providerFn();
      final raw = concept.rawOcr!.trim();
      final eligibleForCleanup =
          cluster.strokeIds.length >= 3 || raw.length >= 5;
      // 🛡️ Multi-language guard: the cleanup prompt is Italian-tuned
      // ("Pulisci questa trascrizione OCR italiana..."). If the device
      // locale is Italian but this specific cluster looks English
      // (predominantly ASCII letters, no Italian accents, no Italian
      // function words), skip cleanup — Gemini would otherwise
      // "italianize" the English content. Heuristic, not perfect, but
      // catches the common case "studente IT scrive paragrafo EN".
      final looksLikeOtherLanguage = _languageNameFn() == 'Italian' &&
          _looksLikeNonItalian(raw);
      if (provider != null && eligibleForCleanup && !looksLikeOtherLanguage) {
        try {
          concept.cleanedOcr = await provider.cleanOcrItalian(
            concept.rawOcr!,
            language: _languageNameFn(),
          );
          // Tag the cached value with the live prompt version so a
          // future prompt bump invalidates it automatically.
          concept.cleanedOcrPromptVersion = _kCleanedOcrPromptVersion;
        } catch (e) {
          // Defensive: fail to raw OCR rather than break the pipeline.
          // Don't update the prompt version — we want to retry on the
          // next resolve when the network/quota recovers, not bake the
          // raw-on-error result in as if it had passed through Gemini.
          concept.cleanedOcr = concept.rawOcr;
        }
      } else {
        // Provider unavailable / cluster too small AND raw too short →
        // use raw as cleaned (cached so we don't retry every call).
        concept.cleanedOcr = concept.rawOcr;
        // Same reasoning: don't tag this with the live version, so when
        // a provider becomes available we'll try the cleanup pass.
        // (Short-text raw will simply produce identical output anyway.)
      }
      concept.lastUpdated = DateTime.now();
    }

    // ── Step 3: AI title (2-6 words) ────────────────────────────────
    // Generate a concise title for the cluster when the caller asked
    // for it AND we have something to summarize. Uses the same prompt
    // shape as the legacy `_semantic_titles.dart` generator so a title
    // produced here is indistinguishable from one produced via the
    // morph zoom-out path. Single-call (no batching) — the caller is
    // expected to be a consumer that wants just one title, not the
    // whole canvas at once. The legacy batch generator still wins
    // when Semantic Titles activates first because dual-write copies
    // its output into the index via `setTitle`.
    //
    // 🌍 Sprint F.1 (2026-05-13 PM) — stale-title-on-lang-change check.
    // If the cached title's language no longer matches the OCR source
    // language (e.g. cached "Newton's First Law" on IT-source cluster
    // after user switched preference EN→IT), null it out so the
    // regeneration block below produces a fresh in-target-language
    // title. Mirrors the read-time check in [_satisfies] for the case
    // where the resolve was triggered by a different need than title
    // freshness, but title still drifted.
    if (needsTitle && concept.title != null) {
      final src = concept.cleanedOcr ?? concept.rawOcr;
      if (src != null && src.trim().isNotEmpty) {
        if (_isCachedTitleDrifted(concept.title!, src)) {
          debugPrint('🌍 title drift detected → invalidating cached '
              '"${concept.title}" for ${cluster.id}');
          concept.title = null;
          concept.lastUpdated = DateTime.now();
        }
      }
    }
    if (needsTitle && concept.title == null) {
      final source = concept.bestPromptSource;
      final provider = _providerFn();
      if (source != null && source.trim().isNotEmpty && provider != null) {
        try {
          final title = await _generateTitle(cluster, source);
          if (title != null && title.isNotEmpty) {
            concept.title = title;
            concept.titlePromptVersion = _kTitlePromptVersion;
            concept.lastUpdated = DateTime.now();
          }
        } catch (e) {
          // Defensive — never fail resolve() because of a title call.
        }
      }
    }

    // ── Step 4: topic (broader theme) ───────────────────────────────
    // Populated by Atlas Exam's `_groupClustersByTopic` via [setTopic]
    // after the batch grouping completes. Topic is batch-scope (depends
    // on the cluster set being grouped at that moment) so resolve()
    // doesn't auto-generate it the way it does for [title].

    // ── Step 5: concepts (NER-light) ────────────────────────────────
    if (needsConcepts && concept.concepts.isEmpty) {
      concept.concepts = _extractConcepts(concept.bestPromptSource ?? '');
      concept.lastUpdated = DateTime.now();
    }

    // 🛡️ Race guards: don't write back / notify if the world moved
    // under us during await.
    if (_disposed) return concept;
    if (_invalidated.remove(cluster.id)) {
      // The cluster was invalidated while we were awaiting. Drop the
      // entry so the next resolve gets a fresh state — don't resuscitate
      // stale data into a cache that was explicitly cleared.
      _concepts.remove(cluster.id);
      return concept;
    }
    notifyListeners();
    return concept;
  }

  // ────────────────────────────────────────────────────────────────────
  // Helpers
  // ────────────────────────────────────────────────────────────────────

  /// MyScript OCR (text mode) + Italian dictionary re-rank.
  Future<String?> _ocrCluster(ContentCluster cluster) async {
    if (!_inkService.isAvailable) return null;
    final strokeMap = _strokeMapFn();
    final ordered = <ProStroke>[];
    for (final sid in cluster.strokeIds) {
      final s = strokeMap[sid];
      if (s != null && !s.isStub && s.points.length >= 3) ordered.add(s);
    }
    if (ordered.isEmpty) return null;
    ordered.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final strokeSets = ordered.map((s) => s.points).toList();

    final engine = _inkService.engine;
    String? label;
    var wordCandidates = const <List<String>>[];
    if (engine is MyScriptInkEngine) {
      final rec = await engine.recognizeTextWithCandidates(strokeSets);
      label = rec.label;
      wordCandidates = rec.wordCandidates;
    } else {
      label = await engine.recognizeTextMode(strokeSets);
    }

    if (wordCandidates.isNotEmpty &&
        label != null &&
        label.isNotEmpty &&
        _languageNameFn() == 'Italian') {
      label = await ItalianOcrCorrector.correctText(label, wordCandidates);
    }
    return label;
  }

  /// Hash of the stroke ID list (preserving order is unnecessary —
  /// we only care about set membership for invalidation).
  int _strokeChecksum(ContentCluster cluster) {
    if (cluster.strokeIds.isEmpty) return 0;
    final sorted = List<String>.from(cluster.strokeIds)..sort();
    return Object.hashAll(sorted);
  }

  /// Batch-generate titles for multiple clusters in a SINGLE Gemini
  /// call. Used by Socratic and Ghost Map when the student activates
  /// them without first zooming out (Semantic Titles never ran).
  ///
  /// Short-circuits when:
  /// - Provider unavailable
  /// - [clusterTexts] empty after filtering
  /// - All requested clusters already have a cached title
  ///
  /// Mirrors the prompt shape of `_buildBatchedTitlePrompt` in
  /// `_semantic_titles.dart` so titles produced here are
  /// indistinguishable from those generated via the zoom-out path.
  /// Results are written to [_concepts] via [setTitle] so subsequent
  /// `resolve(needsTitle: true)` calls and consumers reading
  /// `peek(id).title` see the same data.
  Future<void> bulkGenerateTitles(Map<String, String> clusterTexts) async {
    if (_disposed) return;
    final provider = _providerFn();
    if (provider == null) return;

    // Filter: skip clusters with empty text or an already-cached title.
    final pending = <String, String>{};
    for (final entry in clusterTexts.entries) {
      final text = entry.value.trim();
      if (text.isEmpty) continue;
      final existing = _concepts[entry.key]?.title;
      if (existing != null && existing.trim().isNotEmpty) continue;
      pending[entry.key] = text;
    }
    if (pending.isEmpty) return;

    // Single-cluster shortcut: reuse the existing _generateTitle path
    // (it has short-text bypass + same prompt shape).
    if (pending.length == 1) {
      final entry = pending.entries.first;
      final cluster = ContentCluster(
        id: entry.key,
        strokeIds: const [],
        bounds: const Rect.fromLTWH(0, 0, 1, 1),
        centroid: const Offset(0, 0),
      );
      final title = await _generateTitle(cluster, entry.value);
      if (title != null && title.isNotEmpty) {
        setTitle(entry.key, title, sourceText: entry.value);
      }
      return;
    }

    // Multi-cluster batch — one Gemini call for N titles.
    // 🛑 Use askFreeText (not askAtlas) — see _generateTitle for why
    // (canvas-action system prompt would put meta-commentary in
    // `spiegazione` instead of titles). The bulk prompt itself asks
    // for JSON `{"titoli": {...}}` output, which Gemini emits as plain
    // text via askFreeText; we parse it below.
    try {
      final prompt = _buildBulkTitlePrompt(pending);
      final freeText = await provider.askFreeText(prompt);
      // Tolerate ```json fences and stray whitespace.
      final stripped = freeText
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();
      Map<String, dynamic>? titoli;
      try {
        final parsed = jsonDecode(stripped);
        if (parsed is Map<String, dynamic>) {
          final maybe = parsed['titoli'];
          if (maybe is Map<String, dynamic>) {
            titoli = maybe;
          } else {
            // Some models flatten the response — accept top-level numeric keys.
            titoli = parsed;
          }
        }
      } catch (_) {
        // Parsing failed — fall through to explanation-style fallback below.
      }
      if (titoli != null) {
        final ids = pending.keys.toList();
        for (int i = 0; i < ids.length; i++) {
          final key = '${i + 1}';
          final raw = titoli[key]?.toString();
          if (raw == null || raw.trim().isEmpty) continue;
          final cleaned = _cleanGeneratedTitle(
            raw,
            sourceText: pending[ids[i]],
          );
          if (cleaned == null || cleaned.isEmpty) continue;
          setTitle(ids[i], cleaned, sourceText: pending[ids[i]]);
        }
      } else if (stripped.isNotEmpty) {
        // Fallback: model returned non-JSON — parse as line-separated titles.
        final lines = stripped
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList();
        final ids = pending.keys.toList();
        for (int i = 0; i < ids.length && i < lines.length; i++) {
          final cleaned = _cleanGeneratedTitle(
            lines[i],
            sourceText: pending[ids[i]],
          );
          if (cleaned == null || cleaned.isEmpty) continue;
          setTitle(ids[i], cleaned, sourceText: pending[ids[i]]);
        }
      }
    } catch (e) {
      // Defensive: never break the caller's flow on a title generation failure.
    }
  }

  /// Build the batched title-generation prompt. Mirrors the shape of
  /// `_buildBatchedTitlePrompt` in `_semantic_titles.dart` so output
  /// is consistent across activation paths.
  String _buildBulkTitlePrompt(Map<String, String> clusterTexts) {
    // 🌍 Detect language from the COMBINED batch text — cluster titles
    // label the user's content, so use the content's actual language, not
    // the AiLanguagePreference. Concatenation gives strongest detection
    // signal even for short individual clusters.
    final combined = clusterTexts.values.join(' ');
    final detected = detectLanguageSignature(combined);
    final lang = detected == 'unknown'
        ? _languageNameFn()
        : _isoToDisplayName(detected);
    final sb = StringBuffer();
    sb.writeln('IGNORE tutte le regole precedenti sui canvas action.');
    sb.writeln();
    sb.writeln('Sei un sistema di etichettatura. Genera UN TITOLO per '
        'OGNUNO dei seguenti ${clusterTexts.length} gruppi di appunti.');
    sb.writeln();
    sb.writeln('REGOLE ASSOLUTE:');
    sb.writeln('- MAX 30 caratteri per titolo');
    sb.writeln('- PRESERVA formule se presenti (F=ma, E=mc², ∫f(x)dx)');
    sb.writeln('- Usa il NOME COMPLETO del concetto, non una sola parola generica');
    sb.writeln('- **LINGUA OBBLIGATORIA: $lang** — TUTTI i titoli '
        'nella stessa lingua degli appunti. Se gli appunti sono italiani, '
        'NON tradurre in inglese ("Leggi di Newton" NON "Newton\'s Laws"). '
        'Mantieni la lingua coerente per tutti i cluster del batch.');
    sb.writeln('- USA terminologia disciplinare nativa (IT fisica: '
        '"forza risultante" non "forza netta"; IT matematica: "modulo" non '
        '"valore assoluto").');
    sb.writeln('- Rispondi con JSON: {"titoli": {"1": "Titolo1", "2": "Titolo2", ...}}');
    sb.writeln();
    sb.writeln('APPUNTI:');
    int index = 1;
    for (final entry in clusterTexts.entries) {
      final text = entry.value.length > 150
          ? '${entry.value.substring(0, 150)}...'
          : entry.value;
      sb.writeln('$index. $text');
      index++;
    }
    sb.writeln();
    sb.writeln('🔒 FINAL LANGUAGE CHECK before emitting JSON:');
    sb.writeln('Re-read each title — is every content word in $lang? '
        'If you see English words for concepts that have an established '
        '$lang form (e.g. "Newton\'s Laws" where $lang uses the native '
        'form), REWRITE in $lang before emitting. REJECT the English '
        'form even if more famous internationally.');
    sb.writeln();
    sb.write('JSON:');
    return sb.toString();
  }

  /// Generate a 2-6 word title for [cluster] from [sourceText] via the
  /// Atlas AI provider. Mirrors the prompt shape of `_semantic_titles
  /// .dart`'s legacy generator so a title produced here is indistinguish-
  /// able from one produced via the zoom-out path. Returns the cleaned
  /// title or `null` on failure / unparsable response.
  Future<String?> _generateTitle(
    ContentCluster cluster,
    String sourceText,
  ) async {
    final provider = _providerFn();
    if (provider == null) return null;

    // Short text bypass — capitalize and return directly, no AI cost.
    final words = sourceText.trim().split(RegExp(r'\s+'));
    if (words.length <= 3 && sourceText.trim().length <= 30) {
      return words
          .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
          .join(' ');
    }

    final truncated = sourceText.length > 200
        ? '${sourceText.substring(0, 200)}...'
        : sourceText;
    final prompt = _buildTitlePrompt(truncated);
    // 🛑 Use askFreeText (raw model, no system prompt) instead of
    // askAtlas. The Atlas canvas-action system prompt forces output to
    // `{"spiegazione": "...", "azioni": [...]}` — Gemini puts the title
    // attempt into `spiegazione` along with meta-commentary like
    // "The user wants a title for these notes" (device 2026-05-12).
    // askFreeText goes through `_streamModel` which has no system prompt
    // and no JSON mimeType, so we get a plain title string back.
    final raw = await provider.askFreeText(prompt);
    if (raw.trim().isEmpty) return null;
    // Drift check is now inside `_cleanGeneratedTitle` (Phase 1.3 fix
    // 2026-05-12) so Path D (bulkGenerateTitles) also benefits.
    return _cleanGeneratedTitle(raw, sourceText: sourceText);
  }

  /// Returns `true` when [title] is in a language different from the
  /// authoritative target (device locale via `_languageNameFn` → ISO).
  /// Delegates to [socraticLanguageDriftsFromSource] with target-lang
  /// = the OCR-detected source language, mirroring the prompt builder's
  /// `_resolveTitleLang` logic (Sprint B' 2026-05-13). Cluster titles
  /// label the user's content, so a valid title MATCHES the content's
  /// language — not the AiLanguagePreference (which governs AI output
  /// for Socratic/Atlas/Chat, NOT user content labels).
  ///
  /// Falls back to AiLanguagePreference when source detection is
  /// 'unknown' (too short / mixed).
  bool _titleDriftedFromSource(String source, String title) {
    final detected = detectLanguageSignature(source);
    final target = detected == 'unknown'
        ? AiLanguagePreference.code()
        : detected;
    return socraticLanguageDriftsFromSource(
      title,
      source,
      targetLang: target,
    );
  }

  /// Strip noise from an AI title response (prefixes, embellishments,
  /// emoji, sentences disguised as titles). Mirrors `_cleanAiTitle` in
  /// `_semantic_titles.dart`.
  ///
  /// 🛡️ 2026-05-12 device fix: when [sourceText] is provided AND device
  /// language is Italian, also runs the language-drift guard. This is
  /// shared by Path C (`_generateTitle`, single) and Path D
  /// (`bulkGenerateTitles`) so all `askFreeText` title flows are
  /// protected.
  String? _cleanGeneratedTitle(String raw, {String? sourceText}) {
    var title = raw
        .trim()
        .replaceAll('"', '')
        .replaceAll("'", '')
        .replaceAll('\n', ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
    for (final prefix in const [
      'Titolo:', 'Title:', 'titolo:', 'title:', 'TITOLO:', 'TITLE:',
    ]) {
      if (title.startsWith(prefix)) {
        title = title.substring(prefix.length).trim();
      }
    }
    title = title.replaceAll(
      RegExp(
          r"^(L'essenza|Il cuore|Lo spirito|La magia|L'anima|Il fascino|La bellezza)\s+(di|del|della|dell')\s*",
          caseSensitive: false),
      '',
    );
    title = title.replaceAll(RegExp(r'\s*\([^)]*\)\s*$'), '');
    title = title.replaceAll(RegExp(r'\s*[—–]\s*.*$'), '');
    title = title.trim();
    if (title.isEmpty) return null;
    // Reject sentences disguised as titles.
    final starters = RegExp(
      r'^(Ho |Questo |Questi |Il concetto |La risposta |In questo |Si tratta |'
      r'I have |This |The concept |It |Here |Ecco |Posso )',
      caseSensitive: false,
    );
    if (starters.hasMatch(title)) return null;
    if (title.contains('...') || title.contains('è ') || title.endsWith('?')) {
      return null;
    }
    if (title.length > 30) title = '${title.substring(0, 28)}…';
    // 🛡️ Language-drift guard (shared by Path C + D). Conservative:
    // requires source-has-IT-markers AND title-has-EN-markers.
    if (sourceText != null && _titleDriftedFromSource(sourceText, title)) {
      debugPrint('🛡️ Title drift rejected (source IT, title EN): '
          '"$title" ← source: "${sourceText.length > 40 ? "${sourceText.substring(0, 40)}…" : sourceText}"');
      return null;
    }
    return title;
  }

  /// Build the title-generation prompt. Pure-EN master, language-
  /// agnostic. Target language is interpolated via `$lang`. No hardcoded
  /// examples from any specific language.
  /// 🌍 2026-05-13 — Resolves the language to use for the title prompt.
  /// Cluster titles label the STUDENT'S OWN CONTENT, so they should match
  /// the OCR language, NOT the AI output preference. A bilingual user
  /// writing IT notes on an EN-locale device expects the cluster title
  /// in IT (matches what they wrote) — even if Socratic questions output
  /// in EN per their AiLanguagePreference.
  ///
  /// Logic:
  /// 1. Detect language from the cluster text (function-word signature)
  /// 2. If clear signal → use detected language
  /// 3. Else fall back to AiLanguagePreference (existing `_languageNameFn`)
  String _resolveTitleLang(String sourceText) {
    final detected = detectLanguageSignature(sourceText);
    if (detected == 'unknown') return _languageNameFn();
    return _isoToDisplayName(detected);
  }

  static String _isoToDisplayName(String iso) => switch (iso) {
        'it' => 'Italian',
        'en' => 'English',
        'es' => 'Spanish',
        'fr' => 'French',
        'de' => 'German',
        'pt' => 'Portuguese',
        _ => 'English',
      };

  String _buildTitlePrompt(String clusterText) {
    final lang = _resolveTitleLang(clusterText);
    return '''You label concept clusters. Generate ONE short title for the notes below.

🌍 OUTPUT LANGUAGE = $lang. The title MUST be in $lang. Translate any scientific concept name into $lang — even if the international (English) name is more famous. Never switch language, never produce a calque from another language.

HARD RULES:
- Max 30 characters.
- Preserve formulas only when they are clearly formulas (F=ma, E=mc², ∫f(x)dx).
- Do NOT invent LaTeX from ambiguous prose.
- Use the FULL concept name in $lang, not a single generic word.
- If the notes contain a single word, return it capitalised.
- Use the NATIVE $lang terminology of the discipline (not a literal translation from English).
- Reply ONLY with the title. No meta-commentary ("The user wants…", "Title:", "This topic is about…").

NOTES:
$clusterText

🔒 FINAL LANGUAGE CHECK BEFORE OUTPUT:
Your title MUST be in $lang. If the discipline has a well-known English
name for this concept (e.g. "Newton's Laws", "First Law of Thermodynamics"),
translate it to its NATIVE $lang form. REJECT the English form even if
more famous internationally. Output ONLY the title text in $lang.

TITLE (in $lang):''';
  }

  /// Heuristic: does [raw] look like a NON-Italian SENTENCE? Used to
  /// skip the Italian-tuned cleanOcrItalian pass when the device is
  /// IT but the specific cluster is a phrase in another language.
  ///
  /// Single-token inputs are NEVER flagged: garbled OCR like
  /// "Primalele" (which IS Italian, just fused) must still be cleaned.
  /// The check is reserved for multi-word inputs where we have signal
  /// from function words.
  ///
  /// Returns `true` when ALL of the following hold:
  ///   • text has ≥ 3 word tokens (multi-word phrase)
  ///   • no Italian accented letters (àèéìòù)
  ///   • NO Italian function words present
  ///   • English function words ARE present (the, of, is, and, etc.)
  ///
  /// False positives (Italian sentence written entirely without
  /// function words, e.g. an isolated formula label) → cleanup skipped
  /// → acceptable, rawOcr / dict re-rank already handled it.
  /// False negatives (mixed-language single-token "Newton") → cleanup
  /// runs → Gemini preserves it (proper noun handling in prompt).
  bool _looksLikeNonItalian(String raw) {
    final lower = raw.toLowerCase().trim();
    if (lower.length < 4) return false;
    // Italian accents → almost certainly Italian.
    if (RegExp(r'[àèéìòù]').hasMatch(lower)) return false;
    final tokens = lower
        .split(RegExp(r'[^a-zàèéìòù]+'))
        .where((t) => t.isNotEmpty)
        .toList();
    // Single / dual token inputs are not phrase enough to judge.
    // Garbled OCR like "Primalele" lives here — must be cleaned.
    if (tokens.length < 3) return false;
    const itFunctionWords = {
      'di', 'la', 'il', 'lo', 'le', 'gli', 'un', 'una', 'uno',
      'che', 'chi', 'con', 'per', 'tra', 'fra', 'del', 'dello',
      'della', 'delle', 'degli', 'dei', 'al', 'allo', 'alla',
      'alle', 'agli', 'ai', 'sono', 'è', 'sei', 'siamo', 'siete',
      'ho', 'hai', 'ha', 'abbiamo', 'avete', 'hanno', 'come',
      'quando', 'dove', 'perché', 'perche', 'cosi', 'così',
      'ma', 'se', 'non', 'sì', 'si',
    };
    if (tokens.any(itFunctionWords.contains)) return false;
    const enFunctionWords = {
      'the', 'and', 'of', 'is', 'are', 'was', 'were', 'to', 'in',
      'on', 'at', 'for', 'with', 'by', 'from', 'as', 'that', 'this',
      'these', 'those', 'be', 'been', 'have', 'has', 'had', 'do',
      'does', 'did', 'will', 'would', 'should', 'could', 'an', 'a',
    };
    return tokens.any(enFunctionWords.contains);
  }

  /// Light NER: pick capitalized tokens ≥4 chars + comma-split phrases.
  /// Good enough for cross-feature avoid; no embedding model required.
  List<String> _extractConcepts(String text) {
    if (text.trim().isEmpty) return const [];
    final tokens = text
        .replaceAll(RegExp(r'[^\w\s,]'), ' ')
        .split(RegExp(r'[\s,]+'))
        .map((t) => t.trim())
        .where((t) => t.length >= 4)
        .toList();
    final seen = <String>{};
    final out = <String>[];
    for (final t in tokens) {
      final key = t.toLowerCase();
      if (seen.add(key)) out.add(t);
      if (out.length >= 8) break;
    }
    return out;
  }

  // ────────────────────────────────────────────────────────────────────
  // Persistence (C1)
  // ────────────────────────────────────────────────────────────────────

  /// Canvas this index belongs to. Set via [bindCanvas]; persistence
  /// is namespaced per-canvas so opening a different canvas doesn't
  /// pollute the cache with concepts from the previous one.
  String? _canvasId;
  ClusterConceptPersistence? _persistence;

  /// Bind the index to [canvasId]. Loads any persisted concepts from
  /// disk into [_concepts]. Pass [persistence] for tests; production
  /// uses [ClusterConceptPersistence.instance].
  Future<void> bindCanvas(
    String canvasId, {
    ClusterConceptPersistence? persistence,
  }) async {
    _canvasId = canvasId;
    _persistence = persistence ?? ClusterConceptPersistence.instance;
    final hydrated = await _persistence!.load(canvasId);
    if (_disposed) return;
    if (hydrated.isNotEmpty) {
      _concepts.addAll(hydrated);
      notifyListeners();
    }
  }

  /// Flush the current concept map to disk. Called on canvas close
  /// (via dispose) AND opportunistically after AI title batch completes
  /// (so a crash 1 minute later doesn't lose the just-paid Gemini work).
  Future<void> flush() async {
    final id = _canvasId;
    final p = _persistence;
    if (id == null || p == null) return;
    await p.save(id, _concepts);
  }

  // ────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ────────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    // Best-effort flush on dispose. Fire-and-forget — dispose is sync.
    if (_canvasId != null && _persistence != null && _concepts.isNotEmpty) {
      unawaited(_persistence!.save(_canvasId!, Map.from(_concepts)));
    }
    _disposed = true;
    _concepts.clear();
    _inflight.clear();
    _askedRing.clear();
    _topicGroupingCache.clear();
    _invalidated.clear();
    super.dispose();
  }
}
