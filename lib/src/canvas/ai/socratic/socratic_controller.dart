import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Offset;
import 'package:flutter/foundation.dart';

import '../../../utils/ai_language_preference.dart';
import 'socratic_misconception_library.dart';
import 'socratic_model.dart';
import 'socratic_output_filter.dart';
import 'socratic_question_validator.dart';
import '../../../ai/ai_provider.dart';
import '../../../ai/socratic/pedagogy/pedagogy_registry.dart';
import '../../../ai/experiments/experiment_manager.dart';
import '../../../ai/telemetry_recorder.dart';
import '../../../reflow/content_cluster.dart';
import '../../../utils/safe_path_provider.dart';
import '../cluster_concept.dart';
import '../cluster_concept_index.dart';

/// 🔶 SOCRATIC SPATIAL — Controller for Socratic interrogation sessions.
///
/// State machine managing the full lifecycle:
///
/// ```
/// inactive → generating → active → complete → inactive
/// ```
///
/// Each question goes through:
/// ```
/// active → awaitingConfidence → awaitingAnswer → [correct|wrong|skipped|belowZPD]
/// ```
///
/// Spec: P3-01 → P3-46
///
/// ❌ ANTI-PATTERNS:
///   P3-06: No automatic activation
///   P3-07: No loading animations
///   P3-29: AI NEVER provides the complete answer
///   P3-36: No correct answer shown after error
///   P3-37: No multiple choice / true-false
///   P3-38: No timer / countdown
///   P3-40: No visible question list count

/// 🎯 S1.C 2026-05-12 — Cluster consolidation level inferred from history.
/// Drives `_buildBatchPlan` to skip anchor for veteran-mastered clusters
/// and add extra anchor/elaboration for struggling clusters.
enum _ClusterConsolidationLevel {
  /// ≥3 recent correct/satisfied outcomes, 0 wrong/uncertain → student
  /// has consolidated this cluster. Skip anchor; jump to application
  /// or interleave to push transfer.
  consolidated,

  /// ≥3 recent wrong/uncertain outcomes → student is struggling. Add
  /// extra anchor/elaboration before exposing them to counterfactual.
  struggling,

  /// Mixed signal or insufficient history → use the default plan.
  neutral,
}

class SocraticController extends ChangeNotifier {
  SocraticController({TelemetryRecorder? telemetry})
      : _telemetry = telemetry ?? TelemetryRecorder.noop {
    // Async-load history at construction so the dashboard can read the
    // previous sessions without a separate boot step. Mirrors Atlas.
    unawaited(_loadHistory());
  }

  final TelemetryRecorder _telemetry;
  DateTime? _sessionStartedAt;

  // ─────────────────────────────────────────────────────────────────────────
  // HISTORY (V1.5 maturity sprint)
  // ─────────────────────────────────────────────────────────────────────────

  /// Capped list of completed sessions (most-recent first). Same cap as
  /// Atlas exam history (50). Cleared at construction; reloaded from
  /// disk via [_loadHistory]; appended on [dismiss] when a session
  /// produced at least one resolved question.
  List<SocraticHistoryRecord> _history = [];
  List<SocraticHistoryRecord> get history => List.unmodifiable(_history);

  static const int _historyCap = 50;
  static const String _historyFileName = 'fluera_socratic_history.json';
  static const String _checkpointFileName = 'fluera_socratic_checkpoint.json';

  // ─── Avoid-list ring buffer (V1.5 maturity sprint) ───────────────────────
  //
  // Per-cluster ring buffer of recently-asked questions. Passed to Gemini
  // via `askSocraticBatch(..., avoidPrompts: ...)` so the model doesn't
  // regenerate prompts the student already saw on the same clusters.
  //
  // In-memory only — clears at app restart, mirroring the Atlas exam
  // controller decision (`_recentQuestionsByCluster`). Students who
  // interrogate the same clusters within one app session get fresh
  // questions; coming back days later, a "natural" variation from the
  // model's temperature is enough.

  final Map<String, List<String>> _recentQuestionsByCluster = {};
  static const int _recentQuestionsCapPerCluster = 8;

  /// Optional cross-feature avoid index. When set (typically from the
  /// canvas screen at boot), recently-asked questions are mirrored to
  /// the index so Atlas Exam doesn't repeat what Socratic just asked
  /// (and vice versa).
  ClusterConceptIndex? _conceptIndex;
  set conceptIndex(ClusterConceptIndex? value) {
    _conceptIndex = value;
  }

  /// Test-only hook to drive [_recordRecentQuestions] without standing
  /// up the full activation pipeline (which needs an AI provider).
  /// Production callers go through the [dismiss] path instead.
  @visibleForTesting
  void testRecordRecentQuestions(SocraticSession s) =>
      _recordRecentQuestions(s);

  /// Test-only hook for Sprint F.4 re-run stage rotation. Returns the
  /// stage sequence produced by [_buildBatchPlan] for the given inputs.
  /// Lets tests verify determinism + floor protection without standing
  /// up the full activation pipeline.
  @visibleForTesting
  List<SocraticStage> testBuildBatchPlanStages(
    List<ContentCluster> sortedClusters,
    Map<String, int> recallData,
    int targetSize, {
    String? rotationSeed,
  }) =>
      _buildBatchPlan(sortedClusters, recallData, targetSize,
              rotationSeed: rotationSeed)
          .map((e) => e.stage)
          .toList();

  /// Records the queue's question texts into [_recentQuestionsByCluster].
  /// Called from [dismiss] before clearing `_session` so subsequent
  /// activations on the same clusters can pass them as `avoidPrompts`.
  void _recordRecentQuestions(SocraticSession s) {
    for (final q in s.queue) {
      final list = _recentQuestionsByCluster
          .putIfAbsent(q.clusterId, () => <String>[]);
      list.add(q.text);
      while (list.length > _recentQuestionsCapPerCluster) {
        list.removeAt(0);
      }
      // Mirror to the cross-feature index so Exam can avoid these too.
      _conceptIndex?.recordQuestionAsked(
        q.clusterId,
        q.text,
        AskedBy.socratic,
      );
    }
  }

  /// Flat list of recent question texts across all clusters in [ids].
  /// Capped at 30 to keep prompt-token cost sane (mirror of the cap in
  /// [ExamSessionController.recentQuestionsForClusters]).
  ///
  /// Merges the local Socratic ring buffer with the cross-feature index
  /// (Exam-asked questions are pulled in via [_conceptIndex]) so the
  /// model sees the full "don't repeat these" surface.
  List<String> recentQuestionsForClusters(Iterable<String> ids) {
    final out = <String>{};
    final idx = _conceptIndex;
    for (final id in ids) {
      final list = _recentQuestionsByCluster[id];
      if (list != null) out.addAll(list);
      if (idx != null) {
        out.addAll(idx.recentQuestionsFor(id));
      }
    }
    if (out.length <= 30) return out.toList();
    return out.toList().sublist(out.length - 30);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STATE
  // ─────────────────────────────────────────────────────────────────────────

  SocraticSession? _session;
  SocraticSession? get session => _session;

  bool _isActive = false;
  bool get isActive => _isActive;

  bool _isGenerating = false;
  bool get isGenerating => _isGenerating;

  /// Whether the last session used fallback questions (AI call failed).
  bool _usedFallback = false;
  bool get usedFallback => _usedFallback;

  /// 🎯 S1.A 2026-05-12 — Number of adaptive skip-aheads consumed in the
  /// current session. Floor-protected to max 1 per session so we never
  /// strip the planned trajectory of more than one stage. Reset to 0 in
  /// [activate]. Logged in telemetry as `adaptive_jumps_count`.
  int _adaptiveSkipsUsed = 0;
  int get adaptiveSkipsUsed => _adaptiveSkipsUsed;

  /// 📊 Sprint 5 — granular validation telemetry. Reset per session.
  /// Logged at `step_3_socratic_completed`; failure-mode dashboard
  /// queries documented in `docs/socratic_v3_telemetry.md`.
  int _validationAcceptCount = 0;
  int _validationRetryCount = 0;
  int _validationRejectCount = 0;
  int _retrySuccessCount = 0;
  int _fallbackCount = 0;
  int _parseFailCount = 0;
  int _parsePartialCount = 0;
  int _crossLangSessionFlag = 0; // 0/1 — at least one slot was cross-lang
  final List<String> _rejectReasons = <String>[];

  // 🌊 Sprint D V3.4 ω — per-stage streaming counters.
  int _stagesStreamedCount = 0; // Stages that completed a real stream
  int _stagesFallbackCount = 0; // Stages that fell back to template
  int _firstQuestionVisibleMs = 0; // Perceived latency for the streaming UX win

  // 🛡️ Sprint E.5 V3.4 ω — defense in depth against future proxy
  // regressions. Counts how many stage calls returned suspiciously
  // short (< 80 chars) buffers that required a retry. Used as an
  // alarm signal in the dashboard: a non-zero rate suggests the
  // proxy/model is starting to cap output again.
  int _suspiciousTinyCount = 0; // calls with buffer < 80 chars
  int _retryOnTinyRecoveredCount = 0; // retries that DID recover

  /// Version notifier for painter/widget repaints.
  final ValueNotifier<int> version = ValueNotifier(0);

  // ─────────────────────────────────────────────────────────────────────────
  // 🌉 Passo 9 → Passo 3: seed Socratic queue from accepted bridges
  // ─────────────────────────────────────────────────────────────────────────

  /// Append `transfer`-type Socratic questions seeded from recently accepted
  /// cross-zone bridges. Each bridge's stored Socratic question becomes a
  /// question in the current session — the student can "approfondire il
  /// ponte" with the same multi-turn flow used for the regular session.
  ///
  /// Returns the number of seed questions actually appended. No-op when:
  ///   - no Socratic session is active (the seeds need a queue to land in)
  ///   - the bridge list is empty
  ///   - the bridge's stored question is empty
  ///
  /// Identity guarantee (`feedback_socratic_identity_distinct_from_exam`):
  /// the seeds are routed through the same Socratic queue as regular
  /// questions, so they inherit the non-judging, multi-turn UX. They do
  /// NOT bypass the no-correctness-evaluation rule.
  int seedFromBridges(
    List<({
      String clusterId,
      Offset anchorPosition,
      String question,
    })> bridgeSeeds, {
    int maxSeeds = 5,
  }) {
    if (bridgeSeeds.isEmpty) return 0;
    final session = _session;
    if (session == null || !_isActive) return 0;

    // 🎓 TRIENNIAL-SCALE cap: a canvas with months of work may surface
    // dozens of accepted bridges. Flooding a Socratic queue with all of
    // them would crowd out fresh recall/depth questions and exceed the
    // session's `maxQuestions` cap. 5 seeds is the upper bound an active
    // session can absorb without losing its primary pedagogical thread.
    int added = 0;
    for (final seed in bridgeSeeds) {
      if (added >= maxSeeds) break;
      final q = seed.question.trim();
      if (q.isEmpty) continue;
      session.queue.add(SocraticQuestion(
        id: 'bridge_seed_${DateTime.now().microsecondsSinceEpoch}_$added',
        clusterId: seed.clusterId,
        anchorPosition: seed.anchorPosition,
        type: SocraticQuestionType.transfer,
        text: q,
      ));
      added++;
    }
    if (added == 0) return 0;

    _telemetry.logEvent('step_3_socratic_seeded_from_bridge', properties: {
      'count': added,
      'origin': 'bridgeFollowup',
    });
    _bump();
    return added;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ACTIVATION (P3-01)
  // ─────────────────────────────────────────────────────────────────────────

  /// Activate Socratic mode.
  ///
  /// [clusters] — the detected content clusters on the canvas.
  /// [recallData] — optional recall levels from Recall Mode (clusterId → recall 1-5).
  /// [fsrsData] — optional FSRS schedule (concept → next review date).
  /// [provider] — Atlas AI provider for question generation.
  Future<void> activate({
    required List<ContentCluster> clusters,
    required Map<String, int> recallData,
    AiProvider? provider,
    Map<String, String> clusterTexts = const {},
  }) async {
    if (_isActive) return;
    if (clusters.isEmpty) return;

    _isGenerating = true;
    _isActive = true;
    _usedFallback = false;
    _adaptiveSkipsUsed = 0; // S1.A — reset per session
    // 📊 Sprint 5 — reset granular validation counters per session
    _validationAcceptCount = 0;
    _validationRetryCount = 0;
    _validationRejectCount = 0;
    _retrySuccessCount = 0;
    _fallbackCount = 0;
    _parseFailCount = 0;
    _parsePartialCount = 0;
    _crossLangSessionFlag = 0;
    _rejectReasons.clear();
    // 🌊 Sprint D V3.4 ω — reset per-stage streaming counters
    _stagesStreamedCount = 0;
    _stagesFallbackCount = 0;
    _firstQuestionVisibleMs = 0;
    // 🛡️ Sprint E.5 V3.4 ω — reset defense-in-depth counters
    _suspiciousTinyCount = 0;
    _retryOnTinyRecoveredCount = 0;
    notifyListeners();

    // Generate questions for the clusters.
    final questions = await _generateQuestions(
      clusters: clusters,
      recallData: recallData,
      provider: provider,
      clusterTexts: clusterTexts,
    );

    if (questions.isEmpty) {
      _isActive = false;
      _isGenerating = false;
      notifyListeners();
      return;
    }

    _session = SocraticSession(
      sessionId: 'socratic_${DateTime.now().millisecondsSinceEpoch}',
      queue: questions,
      maxQuestions: questions.length.clamp(5, 12),
    );

    debugPrint('🔶 Socratic session created:'
        ' ${questions.length} questions in queue,'
        ' maxQuestions=${_session!.maxQuestions},'
        ' types=${questions.map((q) => q.type.name).join(', ')}');

    _sessionStartedAt = DateTime.now();
    // 🎭 2026-05-12 pedagogical redesign: log stage_sequence +
    // discipline_inferred + misconception_id_or_null so the field can
    // verify in production that the redesign delivers the intended
    // distribution (stage shape, discipline detection rate, misconception
    // injection rate).
    final stageSequence = questions
        .map((q) => q.stage?.name ?? 'null')
        .join(',');
    final disciplineInferred =
        questions.isNotEmpty ? questions.first.discipline?.name ?? 'null' : 'null';
    final misconceptionId = questions
        .map((q) => q.misconceptionId)
        .firstWhere((id) => id != null, orElse: () => null);
    _telemetry.logEvent('step_3_socratic_started', properties: {
      'cluster_count': clusters.length,
      'question_count': questions.length,
      'max_questions': _session!.maxQuestions,
      'used_fallback': _usedFallback,
      'stage_sequence': stageSequence,
      'discipline_inferred': disciplineInferred,
      'misconception_id': misconceptionId ?? 'null',
    });

    _isGenerating = false;
    _bump();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // QUESTION GENERATION (P3-09 → P3-14)
  // ─────────────────────────────────────────────────────────────────────────

  Future<List<SocraticQuestion>> _generateQuestions({
    required List<ContentCluster> clusters,
    required Map<String, int> recallData,
    AiProvider? provider,
    Map<String, String> clusterTexts = const {},
  }) async {
    final questions = <SocraticQuestion>[];

    // Sort clusters by recall level (ascending) for priority (P3-12).
    final sorted = List<ContentCluster>.from(clusters);
    sorted.sort((a, b) {
      final ra = recallData[a.id] ?? 3;
      final rb = recallData[b.id] ?? 3;
      return ra.compareTo(rb);
    });

    // Limit to first 8 clusters max
    final toProcess = sorted.take(8).toList();

    // 🎯 Question-type planning. When SRS data exists (recall != 3 for
    // at least one cluster), we mirror the recall-based mapping per
    // cluster. When the canvas is FSRS-naive (all clusters at default
    // recall=3) the mapping would collapse to "all challenge" — a real
    // device session reported 3/3 challenge questions which is
    // pedagogically bad (zero variety lacuna/depth/transfer). Round-
    // robin distribute the 4 types instead so every session shows the
    // full spectrum of Socratic question shapes.
    // 🎭 2026-05-12 pedagogical redesign: stage-based plan replaces the
    // old `typeMap + _expandSlots` chain. The stage drives the AI prompt
    // (anchor/elaboration/comparative/counterfactual/application/
    // interleave/metacognitive), while the type is preserved as the
    // FSRS-recall label for breadcrumb gating + fallback selection.
    //
    // `_buildTypeMap` is still computed for telemetry / fallback paths
    // that haven't been migrated yet, but it's no longer the source of
    // truth for slot enumeration.
    final typeMap = _buildTypeMap(toProcess, recallData);
    // Target session size: ceil(clusters * 1.5), clamped to [3, 8].
    // (n*3+1)~/2 = ceil(n*1.5) for positive integers.
    //   1 cluster → 3 stages   2 → 3    3 → 5
    //   4 → 6                  5+ → 8 (capped)
    final targetSize = (((toProcess.length * 3) + 1) ~/ 2).clamp(3, 8);
    // 🎲 Sprint F.4 (2026-05-13 PM): detect Socratic re-activation on the
    // same cluster set BEFORE plan construction so the seed can also drive
    // stage rotation (not just stems). Without this, re-running on the
    // same cluster set (no history signals) yields the same stage sequence
    // each time — only stems vary. Now both stems AND stage vary.
    final candidateClusterIdSet = {for (final c in toProcess) c.id};
    final isReRun = _history.any((record) {
      final recordIds = record.clusterIds.toSet();
      return recordIds.intersection(candidateClusterIdSet).length >=
          (candidateClusterIdSet.length * 0.6).ceil(); // ≥60% overlap
    });
    final variationSeed = isReRun
        ? DateTime.now().millisecondsSinceEpoch.toRadixString(36)
        : null;
    if (variationSeed != null) {
      debugPrint('🎲 Socratic re-run detected on overlapping clusters → '
          'variation seed=$variationSeed');
    }

    final batchPlan = _buildBatchPlan(
      toProcess,
      recallData,
      targetSize,
      typeMap: typeMap,
      rotationSeed: variationSeed,
    );

    // Infer discipline once for the batch (uses cluster OCR + AI titles
    // when available). Used to gate misconception injection + appears in
    // the per-call prompt header.
    final inferredDiscipline = inferDiscipline([
      for (final s in batchPlan)
        ..._collectClusterText(s.cluster, clusterTexts),
    ]);

    // Pick one misconception for the batch (only if a counterfactual
    // slot exists AND a keyword matches a cluster text). Null otherwise.
    final misconception = batchPlan
            .any((s) => s.stage == SocraticStage.counterfactual)
        ? pickMisconceptionFor(
            inferredDiscipline,
            [for (final s in batchPlan) ..._collectClusterText(s.cluster, clusterTexts)],
          )
        : null;

    // Find the slot index of the counterfactual that will receive the
    // misconception hint (1-based for the AI prompt).
    final counterfactualSlotIdx = misconception == null
        ? -1
        : batchPlan
                .indexWhere((s) => s.stage == SocraticStage.counterfactual) +
            1;

    debugPrint('🎭 Socratic batch plan: size=$targetSize discipline='
        '${inferredDiscipline.name} stages=${batchPlan.map((s) => s.stage.name).join(",")}'
        '${misconception != null ? " misconception=${misconception.id}@slot$counterfactualSlotIdx" : ""}');

    // ─── BATCH AI GENERATION (per-stage parallel streams) ──────────────
    // 🎲 variationSeed already minted above and passed to _buildBatchPlan
    // (so it can drive stage rotation too). It's also passed below so the
    // AI generates materially different STEMS on top of materially
    // different STAGES (Bjork desirable-difficulty / Legge 9).

    if (provider != null) {
      try {
        // 🌊 V3.4 ω: per-stage parallel streaming. Replaces the batch
        // monolith. Truncation eliminated structurally; failure isolated
        // per stage (1 stage fallback ≠ all-3 fallback).
        final batchResult = await _generatePerStageStreams(
          provider: provider,
          batchPlan: batchPlan,
          recallData: recallData,
          clusterTexts: clusterTexts,
          discipline: inferredDiscipline,
          misconception: misconception,
          counterfactualSlotIdx: counterfactualSlotIdx,
          variationSeed: variationSeed,
        );

        for (int i = 0; i < batchPlan.length && i < batchResult.length; i++) {
          final cluster = batchPlan[i].cluster;
          final stage = batchPlan[i].stage;
          final recall = recallData[cluster.id] ?? 3;
          final type = batchPlan[i].type;
          final entry = batchResult[i];

          // `clusterTopic` is used in two ways below:
          //  (a) as a placeholder embedded in fallback question text →
          //      must be a clean short label (title or normalized OCR)
          //  (b) as the source for the B4 specificity check → can be
          //      noisy OCR, but a clean label still works because the
          //      title contains the cluster's key concept word.
          // Single normalized label serves both.
          final rawClusterText = clusterTexts[cluster.id] ?? '';
          final clusterTopic =
              _displayLabelForCluster(cluster.id, rawClusterText);
          final rawQuestion = entry['question'];
          String questionText;
          if (rawQuestion != null) {
            // Pre-clean: strip meta-preambles BEFORE the G2 filter so a
            // task-echo prefix doesn't corrupt the specificity check.
            // Device 2026-05-10: "Il comando chiede… Cosa manca per…"
            // was emitted as one string — strip first sentence.
            final cleaned =
                _stripMetaPreamble(_stripLatex(rawQuestion));
            questionText = _applyG2Filter(cleaned, clusterTopic, type);
            if (questionText != cleaned) {
              debugPrint('🛡️ G2 replaced question for "$clusterTopic": '
                  '"${rawQuestion.substring(0, rawQuestion.length.clamp(0, 50))}..."');
            }
            if (cleaned != _stripLatex(rawQuestion)) {
              debugPrint('🧼 Stripped meta-preamble: '
                  '"${rawQuestion.substring(0, rawQuestion.length.clamp(0, 60))}..." '
                  '→ "${cleaned.substring(0, cleaned.length.clamp(0, 60))}..."');
            }
            // 🛡️ Sprint 2/3 — Consolidated single-gate validation.
            // Replaces the legacy B4 + G4 + dual-retry pipeline with
            // ONE validator → ONE retry → ONE fallback. See
            // `socratic_question_validator.dart` for outcome rules.
            final validator = SocraticQuestionValidator(
              targetLang: AiLanguagePreference.code(),
              clusterTopic: clusterTopic,
              clusterRawOcr: rawClusterText,
              stage: stage,
              type: type,
            );
            var validation = validator.validate(questionText);
            debugPrint(
                '🔶 Socratic validate slot $i: ${validation.outcome.name} '
                '(${validation.reason})');
            // 📊 Sprint 5 telemetry hooks.
            if (validation.reason == 'cross_language') {
              _crossLangSessionFlag = 1;
            }
            if (validation.isRetry) {
              _validationRetryCount++;
              _rejectReasons.add(validation.reason);
              final retried = await _retryQuestionWithLangPin(
                provider: provider,
                drifted: questionText,
                stage: stage,
                clusterTopic: clusterTopic,
                clusterRawOcr: rawClusterText,
              );
              if (retried.isNotEmpty) {
                final retryValidation = validator.validate(retried);
                if (retryValidation.isAccept) {
                  debugPrint('✅ Retry accepted: '
                      '"${retried.substring(0, retried.length.clamp(0, 60))}..."');
                  questionText = retried;
                  validation = retryValidation;
                  _retrySuccessCount++;
                  _validationAcceptCount++;
                } else {
                  debugPrint('🛡️ Retry rejected '
                      '(${retryValidation.outcome.name}, '
                      '${retryValidation.reason}) → fallback');
                  questionText = SocraticOutputFilter.fallbackForStage(
                      stage, clusterTopic);
                  _fallbackCount++;
                }
              } else {
                debugPrint('🛡️ Retry returned empty → fallback');
                questionText = SocraticOutputFilter.fallbackForStage(
                    stage, clusterTopic);
                _fallbackCount++;
              }
            } else if (validation.isReject) {
              debugPrint('🛡️ Rejected (${validation.reason}) → fallback');
              questionText = SocraticOutputFilter.fallbackForStage(
                  stage, clusterTopic);
              _validationRejectCount++;
              _rejectReasons.add(validation.reason);
              _fallbackCount++;
            } else {
              _validationAcceptCount++;
            }
          } else {
            questionText = _fallbackQuestion(type, clusterTopic);
            debugPrint('⚠️ Socratic: null question for "$clusterTopic", using fallback');
            debugPrint('📝 fallback Q: "$questionText"');
          }

          // Misconception id only on the counterfactual slot that
          // received the hint (1-based counterfactualSlotIdx vs 0-based i).
          final misconceptionIdForSlot =
              (counterfactualSlotIdx - 1 == i && misconception != null)
                  ? misconception.id
                  : null;
          questions.add(SocraticQuestion(
            id: 'sq_${cluster.id}_${i}_${DateTime.now().microsecondsSinceEpoch}',
            clusterId: cluster.id,
            anchorPosition: cluster.centroid,
            type: type,
            text: questionText,
            breadcrumbs: List<String>.from(entry['breadcrumbs'] ?? []),
            recallLevel: recall,
            stage: stage,
            discipline: inferredDiscipline,
            misconceptionId: misconceptionIdForSlot,
          ));
        }

        // 🚀 E: Post-batch near-duplicate filter. Even with topic
        // grouping (Bug 2 fix), the model occasionally produces 2
        // questions on adjacent topic groups that overlap heavily.
        // Compare each accepted question against earlier ones; if
        // token-similarity > 0.75 AND the question-stem verb is the
        // same, swap for the type-aware fallback. The two-signal check
        // avoids false positives like "Quali sono le 3 leggi di
        // Newton?" vs "Spiega le 3 leggi di Newton" (Jaccard ~0.7 but
        // recall vs explain — genuinely different).
        final accepted = <({String text, String verb})>[];
        for (int i = 0; i < questions.length; i++) {
          final q = questions[i];
          final lower = q.text.toLowerCase();
          final verb = _questionVerbHead(lower);
          final isDup = accepted.any((other) =>
              _tokenJaccardSimilarity(lower, other.text) > 0.75 &&
              verb == other.verb);
          if (isDup) {
            final rawClusterText = clusterTexts[q.clusterId] ?? '';
            final cleanLabel =
                _displayLabelForCluster(q.clusterId, rawClusterText);
            final fallback = SocraticOutputFilter.fallbackForCluster(
                cleanLabel, q.type);
            debugPrint(
                '🔶 Socratic: near-duplicate replaced by type-aware fallback. '
                'Was: "${q.text}" → Now: "$fallback"');
            questions[i] = q.copyWith(text: fallback);
            accepted.add((
              text: fallback.toLowerCase(),
              verb: _questionVerbHead(fallback.toLowerCase())
            ));
          } else {
            accepted.add((text: lower, verb: verb));
          }
        }

        if (questions.isNotEmpty) return questions;
      } catch (e) {
        debugPrint('⚠️ Socratic batch generation failed: $e');
      }
    }

    // ─── FALLBACK: no AI ─────────────────────────────────────────────────
    // Uses normalized cluster label (title preferred) so fallback question
    // text doesn't embed multi-line OCR like "LEGGI DI NEWTON\nPRIMA\n…".
    // Iterates the batchPlan (not legacy slots) so each fallback question
    // is tagged with its pedagogical stage AND uses the stage-aware
    // fallback string from SocraticOutputFilter.
    _usedFallback = true;
    for (int i = 0; i < batchPlan.length; i++) {
      final cluster = batchPlan[i].cluster;
      final type = batchPlan[i].type;
      final stage = batchPlan[i].stage;
      final recall = recallData[cluster.id] ?? 3;
      final rawClusterText = clusterTexts[cluster.id] ?? '';
      final clusterTopic =
          _displayLabelForCluster(cluster.id, rawClusterText);
      questions.add(SocraticQuestion(
        id: 'sq_${cluster.id}_${i}_${DateTime.now().microsecondsSinceEpoch}',
        clusterId: cluster.id,
        anchorPosition: cluster.centroid,
        type: type,
        text: SocraticOutputFilter.fallbackForStage(stage, clusterTopic),
        breadcrumbs: const [],
        recallLevel: recall,
        stage: stage,
        discipline: inferredDiscipline,
      ));
    }

    return questions;
  }

  /// 🌊 Socratic V3.4 ω — per-stage parallel streaming generator.
  ///
  /// Replacement for [_generateBatchViaAI]. Fires N parallel streaming
  /// calls (one per stage slot), each producing ONE question with the
  /// stage-specific system prompt (cached per (stage, langCode)). Each
  /// call has an output budget of 500 tokens (100%+ margin vs the ~250
  /// expected) and the caller stops reading as soon as JSON is valid →
  /// truncation impossible by design.
  ///
  /// Returns the same shape as [_generateBatchViaAI]: a list of
  /// `{q: String, h: List<String>}` maps in slot order. Failures on
  /// individual stages produce an empty entry at that index — the
  /// caller's existing fallback path handles it (failure isolation).
  ///
  /// Architectural notes:
  /// - System prompt is per-stage, lang-native, cached server-side.
  /// - Per-call payload is small (~500-800 chars vs 2000+ legacy).
  /// - Title drift eliminated by lang-native pedagogy context.
  /// - Salvage/retry-on-truncation paths removed (no batch, no monolith,
  ///   no truncation).
  Future<List<Map<String, dynamic>>> _generatePerStageStreams({
    required AiProvider provider,
    required List<({ContentCluster cluster, SocraticStage stage, SocraticQuestionType type})> batchPlan,
    required Map<String, int> recallData,
    required Map<String, String> clusterTexts,
    required Discipline discipline,
    required Misconception? misconception,
    required int counterfactualSlotIdx,
    String? variationSeed,
  }) async {
    if (!provider.isInitialized) await provider.initialize();

    final langCode = AiLanguagePreference.code();
    final disciplineHints = _pedagogyDisciplineHints(discipline, langCode);

    // Build a peer-clusters summary that `interleave` slots can reference
    // (Bjork cross-concept retrieval). Each slot still gets its own
    // payload, but interleave needs to know the OTHER cluster topics in
    // the batch to legitimately link.
    final peerSummary = StringBuffer();
    for (int i = 0; i < batchPlan.length; i++) {
      final c = batchPlan[i].cluster;
      final title = _conceptIndex?.peek(c.id)?.title;
      final text = clusterTexts[c.id] ?? '';
      final peerLabel = (title != null && title.trim().isNotEmpty)
          ? title
          : (text.length > 40 ? '${text.substring(0, 40)}…' : text);
      peerSummary.writeln('  ${i + 1}. $peerLabel');
    }

    final variationBlock = variationSeed == null
        ? ''
        : 'VARIATION SEED: $variationSeed (the user is re-running the '
            'session — produce a materially different stem from a default '
            'run; rotate opening verb and concrete scenario.)\n\n';

    final streamStartedAt = DateTime.now();

    Future<Map<String, dynamic>> runSlot(int idx) async {
      final slot = batchPlan[idx];
      final cluster = slot.cluster;
      final stage = slot.stage;
      final text = clusterTexts[cluster.id] ?? '(vuoto)';
      final recall = recallData[cluster.id] ?? 3;
      final title = _conceptIndex?.peek(cluster.id)?.title;
      final temaLine =
          (title != null && title.trim().isNotEmpty) ? 'tema: "$title"\n' : '';

      // Misconception only applies to the counterfactual slot.
      final isCounterfactualSlot =
          stage == SocraticStage.counterfactual && (idx + 1) == counterfactualSlotIdx;
      final misconceptionBlock = (misconception != null && isCounterfactualSlot)
          ? 'MISCONCEPTION HINT (treat as plausible hypothesis, NEVER label as wrong):\n'
              '  "${misconception.misconceptionText}"\n'
              '  Citation (do NOT include in question text): '
              '${misconception.citation ?? "n/a"}\n\n'
          : '';

      // Interleave slots need peer-cluster context to link.
      final peerBlock = stage == SocraticStage.interleave
          ? 'PEER CLUSTERS IN THIS BATCH (use for cross-cluster linking):\n'
              '${peerSummary.toString().trim()}\n\n'
          : '';

      // Recent avoid-list scoped to this cluster.
      final avoid = recentQuestionsForClusters({cluster.id});
      final avoidBlock = avoid.isEmpty
          ? ''
          : 'AVOID THESE RECENTLY-ASKED QUESTIONS (do NOT regenerate verbatim):\n'
              '${avoid.map((q) => '  - $q').join('\n')}\n\n';

      final payload = '$disciplineHints\n\n'
          'CLUSTER\n'
          '  ${temaLine}OCR: "$text"\n'
          '  recall: $recall/5\n'
          '  stage: ${stage.name}\n'
          '  type: ${slot.type.name}\n\n'
          '$peerBlock'
          '$misconceptionBlock'
          '$variationBlock'
          '$avoidBlock'
          'OUTPUT: emit ONLY a single JSON object '
          '{"q":"…","h":["…","…","…"]} in the target language. '
          'No markdown fences, no commentary, nothing after the JSON.';

      final buffer = StringBuffer();
      try {
        // Stream + early-stop: read chunks until the JSON parses cleanly.
        await for (final chunk in provider
            .streamForStage(
              stage: stage.name,
              payload: payload,
              langCode: langCode,
            )
            .timeout(
              const Duration(seconds: 15),
              onTimeout: (sink) {
                debugPrint('⚠️ Socratic stage ${stage.name} timed out at 15s');
                sink.close();
              },
            )) {
          buffer.write(chunk);
          final parsed = _tryParseSingleQuestion(buffer.toString());
          if (parsed != null) {
            final qText = parsed['q'] as String? ?? '';
            final hList = (parsed['h'] as List?) ?? const [];
            debugPrint('🌊 ${stage.name} slot $idx streamed in '
                '${buffer.length} chars (parsed clean)');
            debugPrint('📝 ${stage.name} Q: "$qText"');
            for (var i = 0; i < hList.length; i++) {
              debugPrint('   h${i + 1}: "${hList[i]}"');
            }
            _stagesStreamedCount++;
            // First-question visibility tracker for perceived latency
            // telemetry. Records the time from stream-start until the
            // FIRST stage parses cleanly (Sprint D dashboard metric).
            if (_firstQuestionVisibleMs == 0) {
              _firstQuestionVisibleMs =
                  DateTime.now().difference(streamStartedAt).inMilliseconds;
            }
            return parsed;
          }
        }
        // Stream ended without a complete parse → try one more time
        // tolerantly (the buffer may have a complete-but-trailing-junk
        // JSON we missed).
        final lastChance = _tryParseSingleQuestion(buffer.toString());
        if (lastChance != null) {
          final qText = lastChance['q'] as String? ?? '';
          final hList = (lastChance['h'] as List?) ?? const [];
          debugPrint('📝 ${stage.name} Q (last-chance parse): "$qText"');
          for (var i = 0; i < hList.length; i++) {
            debugPrint('   h${i + 1}: "${hList[i]}"');
          }
          _stagesStreamedCount++;
          if (_firstQuestionVisibleMs == 0) {
            _firstQuestionVisibleMs =
                DateTime.now().difference(streamStartedAt).inMilliseconds;
          }
          return lastChance;
        }

        // 🛡️ Sprint E.5 — defense in depth retry-on-truncated.
        // Device repros (2026-05-13 morning + afternoon):
        //   (a) proxy capped output at ~10 tokens → buffer < 80 chars
        //   (b) network/proxy stream interrupted mid-string at ~226
        //       chars (finishReason=null, no `}` close) → user sees
        //       only 2/3 questions
        // Retry condition: parse failed AND (buffer suspiciously short
        // OR buffer doesn't end with the JSON `}` closer — clear
        // mid-stream truncation). A transient hiccup gets a second
        // shot; a persistent cap or repeated cut produces a tiny
        // retry → falls through to template fallback.
        final trimmed = buffer.toString().trimRight();
        final unclosed = trimmed.isNotEmpty && !trimmed.endsWith('}');
        if (buffer.length < 80 || unclosed) {
          _suspiciousTinyCount++;
          debugPrint('🛡️ ${stage.name} slot $idx tiny response '
              '(${buffer.length} chars) → retrying once');
          try {
            final retryBuffer = StringBuffer();
            await for (final chunk in provider.streamForStage(
              stage: stage.name,
              payload: payload,
              langCode: langCode,
            ).timeout(
              const Duration(seconds: 15),
              onTimeout: (sink) => sink.close(),
            )) {
              retryBuffer.write(chunk);
              final retryParsed =
                  _tryParseSingleQuestion(retryBuffer.toString());
              if (retryParsed != null) {
                final qText = retryParsed['q'] as String? ?? '';
                final hList =
                    (retryParsed['h'] as List?) ?? const [];
                debugPrint('✅ ${stage.name} slot $idx retry-on-tiny '
                    'recovered (${retryBuffer.length} chars)');
                debugPrint('📝 ${stage.name} Q (retry): "$qText"');
                for (var i = 0; i < hList.length; i++) {
                  debugPrint('   h${i + 1}: "${hList[i]}"');
                }
                _stagesStreamedCount++;
                _retryOnTinyRecoveredCount++;
                if (_firstQuestionVisibleMs == 0) {
                  _firstQuestionVisibleMs = DateTime.now()
                      .difference(streamStartedAt)
                      .inMilliseconds;
                }
                return retryParsed;
              }
            }
            debugPrint('🛡️ ${stage.name} slot $idx retry also tiny '
                '(${retryBuffer.length} chars) → fallback');
          } catch (e) {
            debugPrint('🛡️ ${stage.name} slot $idx retry errored: $e '
                '→ fallback');
          }
        }

        final preview = buffer.toString();
        final clip = preview.length > 200 ? preview.substring(0, 200) : preview;
        debugPrint('⚠️ ${stage.name} slot $idx stream ended without valid JSON '
            '(${buffer.length} chars) → fallback. Buffer: "$clip"');
        _parseFailCount++;
        _stagesFallbackCount++;
        return <String, dynamic>{}; // caller falls back per-slot
      } catch (e) {
        debugPrint('⚠️ ${stage.name} slot $idx stream error: $e → fallback. '
            'Buffer so far: "${buffer.toString()}"');
        _parseFailCount++;
        _stagesFallbackCount++;
        return <String, dynamic>{};
      }
    }

    // Fire all stage streams in parallel. eagerError:false so one bad
    // stage doesn't cancel the others (failure isolation).
    final futures = <Future<Map<String, dynamic>>>[
      for (int i = 0; i < batchPlan.length; i++) runSlot(i),
    ];
    final raw = await Future.wait(futures, eagerError: false);
    // Filter out empty/failed slots (stream failures, empty parses,
    // or empty-q sentinel from fake). Caller's integration loop runs
    // `min(batchPlan, batchResult)`; dropping empty entries here
    // preserves the V3.3 invariant that queue length tracks AI-success
    // count when the AI path runs at all. Per-slot fallback safety
    // net runs only if the resulting list is empty (`questions.isEmpty`
    // → second loop fires).
    return raw.where((m) {
      if (m.isEmpty) return false;
      final q = m['q'];
      return q is String && q.trim().isNotEmpty;
    }).toList();
  }

  /// Discipline hints in the active output language. Local dispatch into
  /// [PedagogyRegistry]. Kept as private wrapper so the controller body
  /// doesn't depend on the registry import path.
  String _pedagogyDisciplineHints(Discipline d, String langCode) {
    return PedagogyRegistry.disciplineHintsFor(d, langCode);
  }

  /// Tries to parse a streaming buffer as `{"q":"…","h":["…","…","…"]}`.
  /// Tolerant to fenced code blocks and trailing whitespace. Returns
  /// `null` if the JSON is still incomplete (caller continues streaming).
  Map<String, dynamic>? _tryParseSingleQuestion(String text) {
    if (text.trim().isEmpty) return null;
    final cleaned = text
        .replaceAll('```json', '')
        .replaceAll('```', '')
        .trim();
    // Look for the first balanced `{...}` block.
    final start = cleaned.indexOf('{');
    if (start < 0) return null;
    // Find matching close brace, accounting for nested arrays.
    int depth = 0;
    bool inString = false;
    bool escape = false;
    int? end;
    for (int i = start; i < cleaned.length; i++) {
      final ch = cleaned[i];
      if (escape) {
        escape = false;
        continue;
      }
      if (ch == r'\\') {
        escape = true;
        continue;
      }
      if (ch == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;
      if (ch == '{') depth++;
      if (ch == '}') {
        depth--;
        if (depth == 0) {
          end = i;
          break;
        }
      }
    }
    if (end == null) return null;
    final candidate = cleaned.substring(start, end + 1);
    try {
      final decoded = jsonDecode(candidate);
      if (decoded is! Map) return null;
      final q = decoded['q'];
      final h = decoded['h'];
      if (q is! String || q.trim().isEmpty) return null;
      // Match the legacy `_parseBatchResponse` output shape: integration
      // loop reads `entry['question']` + `entry['breadcrumbs']`. Pad the
      // breadcrumbs to 3 with a generic fallback so `requestBreadcrumb`
      // always has scaffolds even when the model emits an empty `h`.
      final breadcrumbs = <String>[];
      if (h is List) {
        for (final e in h) {
          if (e is String && e.trim().isNotEmpty) {
            breadcrumbs.add(e.trim());
          }
        }
      }
      const fallbackBreadcrumb = 'Ripensa al concetto centrale.';
      while (breadcrumbs.length < 3) {
        breadcrumbs.add(fallbackBreadcrumb);
      }
      return {
        'q': q,
        'h': breadcrumbs.take(3).toList(),
        'question': _stripLatex(q),
        'breadcrumbs': breadcrumbs.take(3).map(_stripLatex).toList(),
      };
    } catch (_) {
      return null;
    }
  }

  /// 🛡️ Apply G2 guardrail filter to a question (A2-04 → A2-06).
  ///
  /// If the question contains prohibited patterns (declarations,
  /// explanations, definitions, direct answers), it is replaced
  /// with a safe fallback. Minor issues (missing "?") are auto-corrected.
  ///
  /// [type] is forwarded to [SocraticOutputFilter.fallbackForCluster] so
  /// the fallback phrasing matches the question type's pedagogical
  /// intent (lacuna ≠ profondità ≠ sfida ≠ transfer).
  String _applyG2Filter(
    String question, [
    String clusterTopic = '',
    SocraticQuestionType? type,
  ]) {
    final result = SocraticOutputFilter.scanQuestion(question);

    if (result.passed) return question;

    // Try auto-correction first (e.g. missing "?").
    final corrected = SocraticOutputFilter.tryAutoCorrect(result);
    if (corrected != null) return corrected;

    // Violation too severe — use contextual fallback (A2-05).
    debugPrint('🛡️ G2: replacing violated question with fallback');
    return SocraticOutputFilter.fallbackForCluster(clusterTopic, type);
  }

  // Cached regex for LaTeX stripping (O9 optimization).
  static final _latexDelimiters = RegExp(r'\$\$|\$|\\[()\[\]]');

  /// Strip LaTeX delimiters from text for plain-text display.
  /// Converts "$F=ma$" → "F=ma", "$$E=mc^2$$" → "E=mc^2"
  String _stripLatex(String text) => text.replaceAll(_latexDelimiters, '').trim();

  /// Meta-preamble patterns that the LLM occasionally prefixes to the
  /// question despite the system prompt forbidding it. Device 2026-05-10
  /// observed: "Il comando chiede di generare una domanda sulla prima
  /// legge di Newton. Cosa manca per collegare…" — the first sentence
  /// is task-echo, the second is the real question.
  ///
  /// Pattern: a sentence that DESCRIBES the task, followed by ". " and
  /// the actual question. Strip everything before the first "? " or up
  /// to the first interrogative opener.
  static final _metaPreambleRegex = RegExp(
    r'^(?:'
    r"(?:il |la )?(?:comando|richiesta|task|sistema)\s+(?:chiede|richiede|domanda|dice|vuole)"
    r"|mi\s+(?:è|e)\s+stat[oa]\s+(?:chiesto|richiesto)"
    r"|(?:ecco|questa\s+è|la\s+domanda\s+è)\s+(?:la\s+)?domanda"
    r"|domanda\s*[:\-]"
    r"|per\s+(?:il\s+)?cluster\s+\w+"
    r"|riguardo\s+al\s+cluster"
    r"|come\s+richiesto"
    r"|(?:bene|ottimo|perfetto|allora|certo)\s*[,\.]"
    r"|in\s+base\s+(?:al|all'|alla)"
    r')',
    caseSensitive: false,
  );

  /// Quality gate on the sketch OCR before sending it to the AI for
  /// follow-up generation.
  ///
  /// Returns `true` when the OCR is likely too garbled for the model to
  /// produce a sensible follow-up. Device 2026-05-10 showed cases like
  /// "CA" or "forever" (MyScript misread of sparse strokes) being cited
  /// verbatim in the AI's follow-up — "Hai menzionato 'CA'…". The
  /// system prompt forces literal quotation of one sketch word, so a
  /// garbled OCR poisons the entire turn.
  ///
  /// Heuristic (conservative — prefers shipping the AI call when in
  /// doubt):
  ///   - empty / whitespace only → low quality
  ///   - < 5 chars total → low quality (single token, no info)
  ///   - 1 token, < 8 chars, not in dictionary → low quality
  ///     (catches "forever" garble — single token not multi-word)
  ///   - 0 significant tokens (≥3 chars, alphabetic) → low quality
  bool _isSketchOcrLowQuality(String ocr) {
    final trimmed = ocr.trim();
    if (trimmed.isEmpty) return true;
    if (trimmed.length < 5) return true;
    final tokens = trimmed
        .toLowerCase()
        .split(RegExp(r'[^a-zàèéìòù0-9]+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return true;
    // Single-token sketches with < 8 chars are usually garbled OCR of
    // doodles or symbols. Multi-token sketches with ≥2 significant
    // tokens pass — they carry enough signal even if one is garbled.
    if (tokens.length == 1 && tokens.first.length < 8) return true;
    final significant =
        tokens.where((t) => t.length >= 3).length;
    if (significant == 0) return true;
    return false;
  }

  /// Strip meta-preambles from a generated question. If the text starts
  /// with one of the [_metaPreambleRegex] patterns, find the first
  /// sentence terminator (.|?|!) and return everything AFTER it. If no
  /// terminator, return the input unchanged (defensive — better to ship
  /// imperfect than to lose the entire question).
  String _stripMetaPreamble(String text) {
    final trimmed = text.trim();
    if (!_metaPreambleRegex.hasMatch(trimmed)) return trimmed;
    // Find the first sentence boundary AFTER the preamble.
    final match = RegExp(r'[\.\?!]\s+').firstMatch(trimmed);
    if (match == null) return trimmed;
    final tail = trimmed.substring(match.end).trim();
    // Defensive: if stripping left less than 10 chars, the "preamble"
    // was probably the actual question. Keep original.
    if (tail.length < 10) return trimmed;
    return tail;
  }

  /// Italian + English stopwords excluded from the specificity overlap
  /// check. The list is short on purpose — we only want to filter out
  /// words that would otherwise create false-positive overlap (e.g.
  /// "il", "the", "non"). Domain-specific noun overlap is what we want
  /// to catch.
  static const _specificityStopwords = <String>{
    // Italian
    'cosa', 'come', 'quale', 'quali', 'quando', 'dove', 'perché', 'perche',
    'sono', 'sopra', 'sotto', 'questo', 'questa', 'questi', 'queste',
    'altro', 'altra', 'altri', 'altre', 'molto', 'poco', 'tanto',
    'sempre', 'mai', 'anche', 'ancora', 'forse', 'dopo', 'prima',
    'allora', 'quindi', 'però', 'pero', 'oppure', 'mentre', 'invece',
    'tutto', 'tutti', 'tutta', 'tutte', 'niente', 'nulla',
    'riguardo', 'spiegare', 'parole', 'concetto', 'concetti', 'modo',
    // English (defensive — avoid false matches on English handwriting)
    'what', 'when', 'where', 'which', 'while', 'about', 'these', 'those',
    'their', 'there', 'would', 'could', 'should', 'something', 'concept',
  };

  /// Specificity check (B4 of the quality sprint) — returns `true` if
  /// the question mentions at least one ≥4-char content word from the
  /// cluster's OCR text. Catches generic ceremonial phrasings like
  /// "Riguardo a 'X', cosa puoi spiegare con le tue parole?" where
  /// X is just plumbed in but no actual concept word is engaged.
  ///
  /// The match is case-insensitive and ignores accents (Italian "perché"
  /// vs "perche") via a coarse normaliser.
  ///
  /// 🛡️ 2026-05-12 device fix: the topic pool now includes BOTH the
  /// display label AND the raw OCR text. Atlas-generated labels are
  /// sometimes in English ("Newton's Laws") on Italian OCR ("legge di
  /// Newton, corpo a riposo") — using label alone rejected perfectly
  /// good Italian questions. The OCR raw text closes that gap.
  bool _questionMentionsClusterConcept(
    String question,
    String clusterTopic, {
    String? clusterRawOcr,
  }) {
    String normalise(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    Set<String> contentWords(String s) => normalise(s)
        .split(' ')
        .where((w) => w.length >= 4 && !_specificityStopwords.contains(w))
        .toSet();
    final qWords = contentWords(question);
    final cWords = <String>{
      ...contentWords(clusterTopic),
      if (clusterRawOcr != null) ...contentWords(clusterRawOcr),
    };
    if (cWords.isEmpty) return true; // no concept words at all → nothing to match
    return qWords.intersection(cWords).isNotEmpty;
  }

  /// Token-set Jaccard similarity for near-duplicate Socratic question
  /// detection. Tokenizes on non-alphanumeric, drops stopwords + tokens
  /// shorter than 4 chars (so "ma", "se", "di", "a" don't dominate),
  /// then computes |A ∩ B| / |A ∪ B|.
  ///
  /// Range: [0.0, 1.0]. Empty inputs collapse to 1.0 (treated as
  /// duplicates — defensive, since both are uninformative).
  ///
  /// Used post-batch by E (consolidation sprint) to swap near-duplicate
  /// generations with type-aware fallbacks. Threshold tuned empirically
  /// at 0.6 — paraphrases of the same question (e.g. two "challenge"
  /// questions on adjacent topic clusters about the same concept) tend
  /// to score 0.65-0.85 on this metric.
  double _tokenJaccardSimilarity(String a, String b) {
    String normalise(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final ta = normalise(a)
        .split(' ')
        .where((w) => w.length >= 4 && !_specificityStopwords.contains(w))
        .toSet();
    final tb = normalise(b)
        .split(' ')
        .where((w) => w.length >= 4 && !_specificityStopwords.contains(w))
        .toSet();
    if (ta.isEmpty && tb.isEmpty) return 1.0;
    if (ta.isEmpty || tb.isEmpty) return 0.0;
    final inter = ta.intersection(tb).length;
    final union = ta.union(tb).length;
    return inter / union;
  }

  /// Coarse "stem verb" extractor for Socratic question dedup. Maps
  /// the question opener to a semantic bucket so two questions on the
  /// same topic but different intent (recall vs explain vs apply) are
  /// NOT flagged as duplicates by the Jaccard token similarity.
  ///
  /// Returns one of: 'recall' | 'explain' | 'connect' | 'challenge' |
  /// 'apply' | 'other'. Heuristic, IT-only for V1.5.
  String _questionVerbHead(String questionLower) {
    if (RegExp(r'\b(quali sono|elenca|cita|nomina|cosa sono|chi sono)\b')
        .hasMatch(questionLower)) return 'recall';
    if (RegExp(r'\b(spiega|descrivi|riassumi|illustra|esponi|definisci)\b')
        .hasMatch(questionLower)) return 'explain';
    if (RegExp(r'\b(connett|colleg|relaz|tra .* e |unisce|lega)\b')
        .hasMatch(questionLower)) return 'connect';
    if (RegExp(r'\b(ma se|e se|cosa accadrebbe|caso limite|controesempio|sei sicur)\b')
        .hasMatch(questionLower)) return 'challenge';
    if (RegExp(r'\b(applica|risolv|calcola|usa|deriv|dimostra|deduci|prevedi)\b')
        .hasMatch(questionLower)) return 'apply';
    if (RegExp(r'\b(perché|come mai|meccanismo|principio|causa)\b')
        .hasMatch(questionLower)) return 'why';
    if (RegExp(r'\b(ricorda|simile|analog|trasferi|in un altro)\b')
        .hasMatch(questionLower)) return 'transfer';
    return 'other';
  }

  /// Build the cluster → question-type plan for a Socratic batch.
  ///
  /// When the batch has at least one cluster with a non-default recall
  /// (the student has real SRS history), every cluster's type is mapped
  /// from its own recall value via [_questionTypeForRecall] — the
  /// student's memory state drives the question shape per-cluster.
  ///
  /// When ALL clusters share `recall == 3` (FSRS-naive canvas), the
  /// per-cluster mapping would collapse to "all challenge" — device
  /// session 2026-05-10 reported 3/3 challenge questions which means
  /// the student never sees lacuna/depth/transfer phrasings. Solve by
  /// round-robin distributing the 4 types across the cluster list.
  /// Variety is restored without losing recall-based modulation when
  /// SRS data exists.
  Map<String, SocraticQuestionType> _buildTypeMap(
    List<ContentCluster> clusters,
    Map<String, int> recallData,
  ) {
    final map = <String, SocraticQuestionType>{};
    final hasRealRecallSignal =
        clusters.any((c) => (recallData[c.id] ?? 3) != 3);
    if (hasRealRecallSignal) {
      for (final c in clusters) {
        final recall = recallData[c.id] ?? 3;
        map[c.id] = _questionTypeForRecall(recall);
      }
      return map;
    }
    // FSRS-naive: round-robin all 4 types for variety.
    const rotation = [
      SocraticQuestionType.lacuna,
      SocraticQuestionType.challenge,
      SocraticQuestionType.depth,
      SocraticQuestionType.transfer,
    ];
    for (int i = 0; i < clusters.length; i++) {
      map[clusters[i].id] = rotation[i % rotation.length];
    }
    return map;
  }

  /// Map recall level to question type (P3-13).
  SocraticQuestionType _questionTypeForRecall(int recall) {
    if (recall <= 2) return SocraticQuestionType.lacuna;  // O4: merged branches
    if (recall == 3) return SocraticQuestionType.challenge;
    if (recall == 4) return SocraticQuestionType.depth;
    return SocraticQuestionType.transfer; // recall 5
  }

  /// 🎭 Stage plan for a session of [n] questions (2026-05-12 redesign).
  ///
  /// Returns the ordered list of pedagogical stages for a session of size
  /// `n ∈ [3, 8]`. Sequence is fixed:
  ///   • 3 → anchor, elaboration, counterfactual
  ///   • 4 → anchor, elaboration, comparative, counterfactual
  ///   • 5 → anchor, elaboration, comparative, counterfactual, application
  ///   • 6 → 5 + metacognitive
  ///   • 7 → 5 + interleave + metacognitive
  ///   • 8 → 5 + elaboration × 2 (early) + interleave + metacognitive
  ///
  /// Rationale: anchor first (psychological safety, cued retrieval).
  /// Elaboration second (EI/self-explanation activates schema).
  /// Comparative + counterfactual in the middle (peak difficulty).
  /// Application late (transfer requires prior consolidation).
  /// Interleave + metacog as closure for longer sessions only.
  List<SocraticStage> _stagePlanFor(int n) {
    final clamped = n.clamp(3, 8);
    switch (clamped) {
      case 3:
        return const [
          SocraticStage.anchor,
          SocraticStage.elaboration,
          SocraticStage.counterfactual,
        ];
      case 4:
        return const [
          SocraticStage.anchor,
          SocraticStage.elaboration,
          SocraticStage.comparative,
          SocraticStage.counterfactual,
        ];
      case 5:
        return const [
          SocraticStage.anchor,
          SocraticStage.elaboration,
          SocraticStage.comparative,
          SocraticStage.counterfactual,
          SocraticStage.application,
        ];
      case 6:
        return const [
          SocraticStage.anchor,
          SocraticStage.elaboration,
          SocraticStage.comparative,
          SocraticStage.counterfactual,
          SocraticStage.application,
          SocraticStage.metacognitive,
        ];
      case 7:
        return const [
          SocraticStage.anchor,
          SocraticStage.elaboration,
          SocraticStage.comparative,
          SocraticStage.counterfactual,
          SocraticStage.application,
          SocraticStage.interleave,
          SocraticStage.metacognitive,
        ];
      case 8:
      default:
        return const [
          SocraticStage.anchor,
          SocraticStage.elaboration,
          SocraticStage.elaboration,
          SocraticStage.comparative,
          SocraticStage.counterfactual,
          SocraticStage.application,
          SocraticStage.interleave,
          SocraticStage.metacognitive,
        ];
    }
  }

  /// 🎯 Build the full batch plan: each entry is a (cluster, stage, type)
  /// triple. Length matches the stage plan for the chosen size, capped at 8.
  ///
  /// Cluster ↔ stage allocation policy (when N stages > N clusters, we
  /// reuse clusters but never put two CONSECUTIVE stages on the same one):
  ///   • `anchor`         → cluster with HIGHEST recall (low anxiety)
  ///   • `elaboration`    → next-highest recall (or 2nd if dup)
  ///   • `comparative`    → mid-rank cluster (lots of neighbors to compare)
  ///   • `counterfactual` → LOWEST recall (misconception probe lands here)
  ///   • `application`    → median recall (zone of proximal development)
  ///   • `interleave`     → cluster NOT used by anchor (forces cross-topic)
  ///   • `metacognitive`  → no specific cluster — uses session-wide theme,
  ///     so we assign it to the highest-recall cluster (least anxious)
  ///
  /// The `type` is derived from `_questionTypeForRecall(recallData[id])`
  /// so the legacy FSRS mapping survives. The stage drives the AI prompt
  /// independently.
  List<({ContentCluster cluster, SocraticStage stage, SocraticQuestionType type})>
      _buildBatchPlan(
    List<ContentCluster> sortedClusters, // ascending recall
    Map<String, int> recallData,
    int targetSize, {
    Map<String, SocraticQuestionType>? typeMap,
    String? rotationSeed,
  }) {
    if (sortedClusters.isEmpty) return const [];

    // 🎯 S1.C 2026-05-12 — Per-cluster consolidation from history.
    // Build a quick lookup; used below to skip anchor for "consolidated"
    // clusters and add anchor to "struggling" ones.
    final consolidation = <String, _ClusterConsolidationLevel>{
      for (final c in sortedClusters)
        c.id: _clusterConsolidationLevel(c.id),
    };
    final hasConsolidated = consolidation.values
        .any((l) => l == _ClusterConsolidationLevel.consolidated);
    final hasStruggling = consolidation.values
        .any((l) => l == _ClusterConsolidationLevel.struggling);
    if (hasConsolidated || hasStruggling) {
      debugPrint('🎯 S1.C: consolidation map ${consolidation.entries.map((e) => "${e.key}=${e.value.name}").join(", ")}');
    }

    var plan = _stagePlanFor(targetSize);

    // 🎲 Sprint F.4 (2026-05-13 PM) — Re-run stage rotation.
    // When the user re-runs Socratic on the same cluster set without
    // history signals (no consolidation/struggling/hypercorrection yet),
    // the canonical _stagePlanFor sequence yields identical stage TYPES
    // each run — only stems vary via the AI variation seed. To diversify
    // the pedagogical experience across re-runs, rotate slot 1 (the
    // post-anchor stage) deterministically from the seed.
    //
    // Invariants preserved:
    //   • Anchor stays at slot 0 (psychological safety / cued retrieval).
    //   • Counterfactual presence preserved (peak-difficulty probe).
    //   • S1.C consolidation + S1.B hypercorrection override paths still
    //     fire below — they may rewrite stages further. Rotation here is
    //     the BASELINE, not a final commitment.
    //   • No stage duplicated: only candidates not already in the plan.
    if (rotationSeed != null && plan.length >= 2) {
      const rotationPool = [
        SocraticStage.elaboration,
        SocraticStage.application,
        SocraticStage.interleave,
        SocraticStage.metacognitive,
      ];
      final present = plan.toSet();
      final candidates = rotationPool
          .where((s) => s != plan[1] && !present.contains(s))
          .toList();
      if (candidates.isNotEmpty) {
        final seedHash = rotationSeed.codeUnits
            .fold<int>(0, (a, b) => (a + b) & 0x7fffffff);
        final newStage = candidates[seedHash % candidates.length];
        debugPrint('🎲 Re-run stage rotation: slot 1 '
            '${plan[1].name}→${newStage.name} (seed=$rotationSeed)');
        final mutable = List<SocraticStage>.from(plan);
        mutable[1] = newStage;
        plan = mutable;
      }
      // candidates empty → plan is already diverse (N≥7), no rotation.
    }

    final n = sortedClusters.length;

    // Index helpers (sortedClusters is ascending recall → low recall first).
    final lowestRecallIdx = 0;
    final highestRecallIdx = n - 1;
    final medianIdx = n ~/ 2;
    // 2nd-highest, used by elaboration when anchor took the top.
    final secondHighestIdx = (n >= 2) ? n - 2 : 0;
    // Mid-rank pair for comparative (two adjacent clusters).
    final compareIdxA = medianIdx;
    final compareIdxB = (medianIdx + 1).clamp(0, n - 1);
    // Interleave avoids the anchor cluster.
    final interleaveIdx = (n >= 2) ? lowestRecallIdx : 0;

    // Hard-mapped stages — pedagogically critical that they land on a
    // specific cluster (anchor=highest recall for safety, counterfactual=
    // lowest for misconception probe). These MUST NOT be flipped by the
    // consecutive-cluster avoidance below.
    const hardMappedStages = <SocraticStage>{
      SocraticStage.anchor,
      SocraticStage.counterfactual,
      SocraticStage.comparative,
    };

    ContentCluster pickFor(SocraticStage stage, int slotIdx, int? prevIdx) {
      int chosen;
      switch (stage) {
        case SocraticStage.anchor:
          chosen = highestRecallIdx;
        case SocraticStage.elaboration:
          chosen = secondHighestIdx;
        case SocraticStage.comparative:
          // Alternate between the two compare-pair indices so a duplicated
          // comparative slot uses both pair members.
          chosen = (slotIdx % 2 == 0) ? compareIdxA : compareIdxB;
        case SocraticStage.counterfactual:
          chosen = lowestRecallIdx;
        case SocraticStage.application:
          chosen = medianIdx;
        case SocraticStage.interleave:
          chosen = interleaveIdx;
        case SocraticStage.metacognitive:
          chosen = highestRecallIdx;
      }
      // Only flip for SOFT-mapped stages (elaboration, application,
      // interleave, metacognitive). Hard-mapped stages preserve their
      // pedagogical contract even when adjacent.
      if (n > 1 &&
          prevIdx != null &&
          chosen == prevIdx &&
          !hardMappedStages.contains(stage)) {
        chosen = (chosen + 1) % n;
      }
      return sortedClusters[chosen];
    }

    final out =
        <({ContentCluster cluster, SocraticStage stage, SocraticQuestionType type})>[];
    int? prevIdx;
    for (int i = 0; i < plan.length && out.length < 8; i++) {
      var stage = plan[i];
      var cluster = pickFor(stage, i, prevIdx);

      // 🎯 S1.C — Consolidation-aware stage override:
      // - If the picked cluster is CONSOLIDATED and stage is anchor or
      //   elaboration, promote to application or interleave (push transfer).
      // - If the picked cluster is STRUGGLING and stage is counterfactual,
      //   demote to elaboration (consolidate anchor first, defer probe).
      // Floor protection: keep ≥1 counterfactual per batch overall.
      final level = consolidation[cluster.id];
      if (level == _ClusterConsolidationLevel.consolidated &&
          (stage == SocraticStage.anchor ||
              stage == SocraticStage.elaboration)) {
        stage = (i % 2 == 0)
            ? SocraticStage.application
            : SocraticStage.interleave;
        debugPrint('🎯 S1.C: cluster ${cluster.id} consolidated → '
            'promote slot ${i + 1} to ${stage.name}');
      } else if (level == _ClusterConsolidationLevel.struggling &&
          stage == SocraticStage.counterfactual) {
        // Only demote when there's at least one OTHER counterfactual
        // somewhere in the plan, else floor protection kicks in.
        final otherCfPositions = plan
            .asMap()
            .entries
            .where((e) =>
                e.key != i && e.value == SocraticStage.counterfactual)
            .toList();
        if (otherCfPositions.isNotEmpty) {
          stage = SocraticStage.elaboration;
          debugPrint('🎯 S1.C: cluster ${cluster.id} struggling → '
              'demote slot ${i + 1} to elaboration');
        }
      }

      // Prefer typeMap when supplied (preserves FSRS-naive round-robin
      // variety); fall back to recall-based mapping otherwise.
      final type = typeMap?[cluster.id] ??
          _questionTypeForRecall(recallData[cluster.id] ?? 3);
      out.add((cluster: cluster, stage: stage, type: type));
      prevIdx = sortedClusters.indexOf(cluster);
    }

    // 🎯 S1.B 2026-05-12 — Hypercorrection drives priority counterfactual.
    // If any cluster in this batch had a hypercorrection (high conf +
    // wrong) in a recent past session, ENSURE there's a counterfactual
    // for that cluster, ideally before slot 4. The misconception probe
    // lands best where the student is overconfident-wrong.
    //
    // We don't add a new slot (the plan size is fixed); instead, if no
    // counterfactual already targets the hyper-cluster, swap the FIRST
    // non-anchor/non-comparative slot to counterfactual on that cluster.
    final hyperClusters = _recentHypercorrectionClusterIds();
    if (hyperClusters.isNotEmpty) {
      for (final hcId in hyperClusters) {
        final inBatch = out.any((s) => s.cluster.id == hcId);
        if (!inBatch) continue;
        final alreadyHasCF = out.any((s) =>
            s.cluster.id == hcId && s.stage == SocraticStage.counterfactual);
        if (alreadyHasCF) continue;
        // Find a swappable slot (not anchor, not first comparative).
        for (int i = 1; i < out.length; i++) {
          final s = out[i];
          if (s.stage == SocraticStage.anchor) continue;
          if (s.stage == SocraticStage.counterfactual) continue;
          // Promote this slot to counterfactual on the hyper cluster.
          final hyperCluster = sortedClusters.firstWhere(
            (c) => c.id == hcId,
            orElse: () => s.cluster,
          );
          out[i] = (
            cluster: hyperCluster,
            stage: SocraticStage.counterfactual,
            type: typeMap?[hyperCluster.id] ??
                _questionTypeForRecall(recallData[hyperCluster.id] ?? 3),
          );
          debugPrint('🎯 S1.B: promoted slot ${i + 1} to counterfactual '
              'on hyper-cluster $hcId');
          break;
        }
      }
    }
    return out;
  }

  /// 🎯 S1.B 2026-05-12 — Returns cluster IDs that had a hypercorrection
  /// in the last 3 history records. Used by [_buildBatchPlan] to prioritize
  /// counterfactual stage on those clusters in the next session.
  ///
  /// Hypercorrection effect (Butterfield & Metcalfe 2001): high-confidence
  /// wrong answers are the MOST corrigible — students remember the
  /// correction longer when they were wrong AND certain. Surfacing a
  /// counterfactual probe early in the next session exploits this window.
  Set<String> _recentHypercorrectionClusterIds() {
    if (_history.isEmpty) return const {};
    final recent = _history.take(3); // last 3 sessions
    final clusterIds = <String>{};
    for (final record in recent) {
      for (final q in record.questions) {
        if (q.isHypercorrection) clusterIds.add(q.clusterId);
      }
    }
    return clusterIds;
  }

  /// 🎯 S1.C 2026-05-12 — Cluster consolidation level from history.
  ///
  /// Inspects the last 5 history records for each cluster and returns
  /// `consolidated` when ≥3 recent correct/satisfied outcomes (skip
  /// anchor, jump to application/interleave), `struggling` when ≥3
  /// recent uncertain/wrong (add extra elaboration, defer counterfactual),
  /// or `neutral` otherwise.
  ///
  /// Drives `_buildBatchPlan` to skip anchor for consolidated clusters
  /// and add extra anchor/elaboration for struggling ones, instead of
  /// repeating the same template indefinitely (which would frustrate
  /// veteran students on already-mastered topics).
  _ClusterConsolidationLevel _clusterConsolidationLevel(String clusterId) {
    if (_history.isEmpty) return _ClusterConsolidationLevel.neutral;
    int positives = 0;
    int negatives = 0;
    final recentSessions = _history.take(5);
    for (final record in recentSessions) {
      for (final q in record.questions) {
        if (q.clusterId != clusterId) continue;
        // Positive = recalled (legacy) OR satisfied/correct status.
        if (q.recalled ||
            q.statusName == 'correct' ||
            q.statusName == 'correctLowConf') {
          positives++;
        } else if (q.statusName == 'wrongHighConf' ||
            q.statusName == 'wrongLowConf') {
          negatives++;
        }
      }
    }
    if (positives >= 3 && negatives == 0) {
      return _ClusterConsolidationLevel.consolidated;
    }
    if (negatives >= 3) return _ClusterConsolidationLevel.struggling;
    return _ClusterConsolidationLevel.neutral;
  }

  /// 🌀 S2.B 2026-05-12 — Threshold concept detection (Meyer & Land 2003).
  ///
  /// A "threshold concept" is one that produces sustained productive
  /// struggle before a transformative leap of understanding. Heuristic
  /// signals from the local history:
  ///
  ///   1. Cluster appears in ≥3 distinct sessions
  ///   2. Average breadcrumbs spent ≥1.5 (student needed scaffolding)
  ///   3. At least 1 hypercorrection event OR ≥2 wrong/uncertain outcomes
  ///
  /// When all three hold, the cluster is flagged as a threshold candidate.
  /// Used by:
  ///   • Consolidation sheet (S2.C) → surfaces these as "argomenti in
  ///     fase liminale" with Meyer & Land "è normale" copy
  ///   • Future: extra aporetic turn in next session + wider FSRS spacing
  ///
  /// NOT a verdict — heuristic. False positives are OK (student gets
  /// gentle messaging about a hard topic). False negatives are also OK
  /// (we just don't surface it; everything else still works).
  ///
  /// Reset to const empty when [_history] is empty.
  Set<String> thresholdConceptCandidates() {
    if (_history.isEmpty) return const {};

    // Aggregate per-cluster signals over the whole history (not just
    // recent — threshold concepts are by definition long-running).
    final perCluster = <String,
        ({int sessions, int totalBreadcrumbs, int totalQs, int negativeOutcomes, int hyperEvents})>{};

    for (final record in _history) {
      final sessionClusters = <String>{};
      for (final q in record.questions) {
        sessionClusters.add(q.clusterId);
        final prev = perCluster[q.clusterId] ??
            (sessions: 0, totalBreadcrumbs: 0, totalQs: 0,
             negativeOutcomes: 0, hyperEvents: 0);
        final isNegative = q.statusName == 'wrongHighConf' ||
            q.statusName == 'wrongLowConf';
        perCluster[q.clusterId] = (
          sessions: prev.sessions,
          totalBreadcrumbs: prev.totalBreadcrumbs + q.breadcrumbsUsed,
          totalQs: prev.totalQs + 1,
          negativeOutcomes: prev.negativeOutcomes + (isNegative ? 1 : 0),
          hyperEvents: prev.hyperEvents + (q.isHypercorrection ? 1 : 0),
        );
      }
      // Bump session count once per cluster per session.
      for (final cId in sessionClusters) {
        final prev = perCluster[cId]!;
        perCluster[cId] = (
          sessions: prev.sessions + 1,
          totalBreadcrumbs: prev.totalBreadcrumbs,
          totalQs: prev.totalQs,
          negativeOutcomes: prev.negativeOutcomes,
          hyperEvents: prev.hyperEvents,
        );
      }
    }

    final candidates = <String>{};
    for (final entry in perCluster.entries) {
      final stats = entry.value;
      if (stats.totalQs == 0) continue;
      final avgBreadcrumbs = stats.totalBreadcrumbs / stats.totalQs;
      final hasStruggleSignal =
          stats.hyperEvents >= 1 || stats.negativeOutcomes >= 2;
      if (stats.sessions >= 3 &&
          avgBreadcrumbs >= 1.5 &&
          hasStruggleSignal) {
        candidates.add(entry.key);
      }
    }
    if (candidates.isNotEmpty) {
      debugPrint('🌀 S2.B: threshold candidates = $candidates');
    }
    return candidates;
  }

  /// 🛡️ G4 retry path (Phase 2.2, 2026-05-12 device fix).
  ///
  /// Called when the primary batch generated a question that failed G4
  /// (typically because of language drift — see
  /// `socraticLanguageDriftsFromSource`). Asks the provider to rewrite
  /// the offending question in the user's native language using a
  /// lightweight `askFreeText` call. Returns the rewritten text on
  /// success, or empty string on failure (caller falls back to
  /// stage-aware template).
  ///
  /// Cap 1 retry per question per session. Uses cheap free-text channel
  /// (no full batch re-generation) → cost ~€0.0002/retry.
  /// 🛡️ Sprint 1.2 — Retry prompt ULTRA-MINIMAL.
  ///
  /// Earlier versions included a "Cluster theme:" + "Pedagogical stage:"
  /// scaffold that Gemini Flash frequently ECHOED in its response (device
  /// repro: model appended `Cluster theme: ...\nPedagogical stage:
  /// anchor` to the rewritten question, producing 2-asterisk-or-? G4
  /// scores). The new prompt has ONE line in target lang + the question
  /// to rewrite. No scaffolding to echo.
  ///
  /// The `clusterTopic` and `stage` parameters are kept on the signature
  /// for binary compatibility with current callers, but no longer
  /// injected into the prompt body.
  Future<String> _retryQuestionWithLangPin({
    required AiProvider provider,
    required String drifted,
    required SocraticStage stage,
    required String clusterTopic,
    required String clusterRawOcr,
  }) async {
    final code = AiLanguagePreference.code();
    final instruction = switch (code) {
      'it' =>
        'Riscrivi questa domanda interamente in italiano, mantenendo lo '
            'stesso significato pedagogico. Restituisci SOLO il testo '
            'italiano, senza preambolo né virgolette:',
      'es' =>
        'Reescribe esta pregunta completamente en español, manteniendo '
            'el mismo significado pedagógico. Devuelve SOLO el texto '
            'español, sin preámbulo ni comillas:',
      'fr' =>
        'Réécris cette question entièrement en français, en gardant '
            'le même sens pédagogique. Renvoie SEULEMENT le texte '
            'français, sans préambule ni guillemets:',
      'de' =>
        'Schreibe diese Frage vollständig auf Deutsch um, behalte den '
            'pädagogischen Sinn bei. Gib NUR den deutschen Text zurück, '
            'ohne Vorwort und ohne Anführungszeichen:',
      'pt' =>
        'Reescreva esta pergunta inteiramente em português, mantendo '
            'o mesmo significado pedagógico. Retorne APENAS o texto '
            'português, sem preâmbulo ou aspas:',
      'en' =>
        'Rewrite this question entirely in English, keeping the same '
            'pedagogical meaning. Return ONLY the English text, no '
            'preamble, no quotes:',
      _ =>
        'Rewrite this question entirely in the language with locale '
            'code "$code", keeping the same pedagogical meaning. Return '
            'ONLY the rewritten text, no preamble, no quotes:',
    };
    final prompt = '$instruction\n\n$drifted';
    try {
      final out = await provider.askFreeText(prompt).timeout(
            const Duration(seconds: 5),
            onTimeout: () => '',
          );
      var cleaned = out
          .trim()
          .replaceAll(RegExp(r'''^["']+|["']+$'''), '')
          .replaceAll('\n', ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      // 🛡️ Post-process strip — if the model echoed scaffolding labels
      // (legacy behaviour), drop everything from the first such marker
      // onwards. Defends against future regressions if a caller's prompt
      // re-introduces labelled scaffolding.
      const echoMarkers = [
        'Cluster theme:',
        'Tema del cluster:',
        'Tema do cluster:',
        'Cluster-Thema:',
        'Thème du cluster:',
        'Pedagogical stage:',
        'Stage pedagogica:',
        'Stage pedagogico:',
        'Stadio pedagogico:',
        'Étape pédagogique:',
        'Etapa pedagógica:',
        'Pädagogische Stufe:',
      ];
      for (final marker in echoMarkers) {
        final idx = cleaned.indexOf(marker);
        if (idx >= 0) {
          cleaned = cleaned.substring(0, idx).trim();
        }
      }
      return cleaned;
    } catch (e) {
      debugPrint('🛡️ Retry failed: $e');
      return '';
    }
  }

  /// 🌍 Tail-position language pin for the per-call batch prompt. The
  /// model reads sequentially, so the LAST instruction has highest weight
  /// for the upcoming output. Written in the TARGET language itself
  /// (rules only, no scenario examples) — LLM literature confirms this
  /// anchors output language far more reliably than an EN instruction.
  String _tailLangPin() {
    final code = AiLanguagePreference.code();
    return switch (code) {
      'it' =>
        '🌍 CONTROLLO FINALE PRIMA DEL JSON: ogni valore di `q` DEVE essere '
            'in italiano. Se hai redatto una domanda in inglese internamente, '
            'RISCRIVILA in italiano ADESSO. La prima parola di ogni `q` DEVE '
            'essere italiana. Niente inglese, neanche parziale.',
      'es' =>
        '🌍 COMPROBACIÓN FINAL ANTES DEL JSON: cada valor de `q` DEBE estar '
            'en español. Si redactaste una pregunta en inglés internamente, '
            'REESCRÍBELA en español AHORA. La primera palabra de cada `q` DEBE '
            'estar en español. Nada de inglés, ni siquiera parcial.',
      'fr' =>
        '🌍 VÉRIFICATION FINALE AVANT LE JSON: chaque valeur de `q` DOIT être '
            'en français. Si tu as rédigé une question en anglais en interne, '
            'RÉÉCRIS-LA en français MAINTENANT. Le premier mot de chaque `q` '
            'DOIT être en français. Aucun anglais, même partiel.',
      'de' =>
        '🌍 ENDKONTROLLE VOR DEM JSON: jeder `q`-Wert MUSS auf Deutsch sein. '
            'Wenn du intern eine Frage auf Englisch entworfen hast, SCHREIBE SIE '
            'JETZT auf Deutsch UM. Das erste Wort jedes `q` MUSS auf Deutsch '
            'sein. Kein Englisch, auch nicht teilweise.',
      'pt' =>
        '🌍 VERIFICAÇÃO FINAL ANTES DO JSON: cada valor de `q` DEVE estar em '
            'português. Se redigiu uma pergunta em inglês internamente, '
            'REESCREVA-A em português AGORA. A primeira palavra de cada `q` '
            'DEVE estar em português. Nada de inglês, nem parcial.',
      'ja' =>
        '🌍 JSON出力前の最終チェック：すべての`q`の値は日本語でなければなりません。'
            '内部で英語で質問を作成した場合は、今すぐ日本語に書き直してください。'
            'すべての`q`の最初の単語は日本語でなければなりません。英語は一切使用しないこと。',
      'ko' =>
        '🌍 JSON 출력 전 최종 점검: 모든 `q` 값은 한국어여야 합니다. 내부적으로 '
            '영어로 질문을 작성했다면 지금 즉시 한국어로 다시 작성하세요. '
            '모든 `q`의 첫 단어는 한국어여야 합니다. 부분적으로도 영어 금지.',
      'zh' =>
        '🌍 输出JSON前的最终检查：每个`q`值都必须是中文。如果你内部用英文起草了问题，'
            '现在请用中文重写。每个`q`的第一个词必须是中文。不允许任何英文，即使部分也不行。',
      'ar' =>
        '🌍 الفحص النهائي قبل JSON: كل قيمة `q` يجب أن تكون بالعربية. إذا صغت '
            'سؤالاً بالإنجليزية داخلياً، أعد صياغته بالعربية الآن. الكلمة الأولى '
            'من كل `q` يجب أن تكون بالعربية. ممنوع الإنجليزية، حتى جزئياً.',
      _ =>
        // Fallback for Tier-1 languages not yet hand-translated (hi/nl/sv/pl/tr/ru).
        'OUTPUT LANGUAGE CHECK BEFORE EMITTING JSON: every `q` value MUST be '
            'in the user\'s device language. If a question came out in English '
            'internally, rewrite it now. The first word of every `q` must be in '
            'the user\'s native language.',
    };
  }

  /// ISO 639-1 → display language name (matches the langMap used in
  /// `atlas_ai_service.dart`). Defaults to English for unknown locales.
  String _localeCodeToLanguageName(String code) => switch (code) {
        'it' => 'Italian',
        'es' => 'Spanish',
        'fr' => 'French',
        'de' => 'German',
        'pt' => 'Portuguese',
        'ja' => 'Japanese',
        'ko' => 'Korean',
        'zh' => 'Chinese',
        'ar' => 'Arabic',
        'ru' => 'Russian',
        'hi' => 'Hindi',
        'nl' => 'Dutch',
        'sv' => 'Swedish',
        'pl' => 'Polish',
        'tr' => 'Turkish',
        _ => 'English',
      };

  /// Build a HUMAN-READABLE label for a cluster, suitable for embedding
  /// in question text. Priority order:
  ///   1. AI-generated title (already native-language + correct terminology
  ///      — comes from cleanedOcr → title pipeline)
  ///   2. Normalized raw OCR (collapse whitespace, truncate to 50 chars)
  ///   3. Empty string (caller falls back to generic phrasing)
  ///
  /// Device 2026-05-12: fallback questions were embedding raw multi-line
  /// OCR like `"LEGGI DI NEWTON\nPRIMA\nCORPO A RIPOSO\nSECONDA LEGGE"`
  /// directly into question text, producing nonsense. Use the title
  /// when available — it's the canonical short name students recognize.
  String _displayLabelForCluster(String clusterId, String rawText) {
    final title = _conceptIndex?.peek(clusterId)?.title?.trim();
    if (title != null && title.isNotEmpty) return title;
    final collapsed = rawText.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.isEmpty) return '';
    if (collapsed.length > 50) return '${collapsed.substring(0, 50)}…';
    return collapsed;
  }

  /// Collect all text sources for a cluster: AI title (cleanest signal),
  /// topic (if cached), and raw OCR. Used as input to [inferDiscipline]
  /// and [pickMisconceptionFor] so they have the best possible signal.
  Iterable<String> _collectClusterText(
    ContentCluster cluster,
    Map<String, String> clusterTexts,
  ) sync* {
    final concept = _conceptIndex?.peek(cluster.id);
    final title = concept?.title?.trim();
    if (title != null && title.isNotEmpty) yield title;
    final topic = concept?.topic?.trim();
    if (topic != null && topic.isNotEmpty) yield topic;
    final raw = clusterTexts[cluster.id]?.trim();
    if (raw != null && raw.isNotEmpty) yield raw;
  }

  /// Fallback questions when AI is unavailable (O3: unified, removed duplicate).
  /// [topic] provides cluster context to make the question specific.
  String _fallbackQuestion(SocraticQuestionType type, [String topic = '']) {
    final t = topic.isNotEmpty ? '"$topic"' : 'questo argomento';
    return switch (type) {
      SocraticQuestionType.lacuna =>
        'Cosa manca nella tua comprensione di $t? Riesci a collegare i concetti?',
      SocraticQuestionType.challenge =>
        'Sei sicuro di aver compreso correttamente $t? Cosa accadrebbe se la tua assunzione fosse sbagliata?',
      SocraticQuestionType.depth =>
        'Riguardo a $t, puoi spiegare il *perché* e non solo il *cosa*?',
      SocraticQuestionType.transfer =>
        '$t ti ricorda qualcosa che hai studiato in un altro ambito?',
    };
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CONFIDENCE (P3-17)
  // ─────────────────────────────────────────────────────────────────────────

  /// Set the confidence level (1-5) for the active question.
  ///
  /// [autoChooseAnswer] (default `true`): legacy path. Transitions to
  /// [SocraticBubbleStatus.awaitingAnswer] so the binary self-eval
  /// renders. Set to `false` to enter the V2 multi-turn flow — the
  /// bubble will then show the "Penso solo / Schizzo" choice via
  /// [chooseTurnMode].
  void setConfidence(int level, {bool autoChooseAnswer = true}) {
    final q = _session?.activeQuestion;
    if (q == null) return;
    if (q.status != SocraticBubbleStatus.active &&
        q.status != SocraticBubbleStatus.awaitingConfidence) return;

    final next = autoChooseAnswer
        ? SocraticBubbleStatus.awaitingAnswer
        : SocraticBubbleStatus.awaitingTurnMode;

    // A3: immutable update via copyWith.
    _session!.replaceActive(q.copyWith(
      confidence: level.clamp(1, 5),
      status: next,
    ));
    _bump();
    unawaited(_persistCheckpoint());
  }

  /// V2 multi-turn entry point. Called by the bubble UI after the
  /// student picks one of `[💭 Penso solo] / [✏️ Schizzo]`.
  ///
  /// * `sketch: false` → legacy binary path. Transits to
  ///   [SocraticBubbleStatus.awaitingAnswer], then [recordResult] fires
  ///   as in V1.
  /// * `sketch: true` → opens the inline scratchpad. Transits to
  ///   [SocraticBubbleStatus.awaitingSketch]; on confirm, the UI calls
  ///   [submitSketch] which fires `provider.askSocraticFollowUp`.
  ///
  /// Idempotent: callable only from [SocraticBubbleStatus.awaitingTurnMode].
  void chooseTurnMode({required bool sketch}) {
    final q = _session?.activeQuestion;
    if (q == null) return;
    if (q.status != SocraticBubbleStatus.awaitingTurnMode) return;

    // First-time entry: seed `turns[0]` with the initial question so the
    // bubble can display the dialogue history compactly.
    final initialTurn = q.turns.isEmpty
        ? [
            SocraticTurn(
              index: 0,
              role: SocraticTurnRole.initial,
              question: q.text,
              sketchOcr: null,
              timestamp: DateTime.now(),
            ),
          ]
        : q.turns;

    _session!.replaceActive(q.copyWith(
      status: sketch
          ? SocraticBubbleStatus.awaitingSketch
          : SocraticBubbleStatus.awaitingAnswer,
      turns: initialTurn,
    ));
    _bump();
    unawaited(_persistCheckpoint());
  }

  /// V2 multi-turn: student confirmed a sketch on the inline scratchpad.
  ///
  /// [sketchOcr] is the OCR'd text from the student's sketch (sent to
  /// the AI). The controller:
  ///   1. Appends a turn for this sketch (the AI's next question will
  ///      be added as a new turn).
  ///   2. Transits to [SocraticBubbleStatus.generatingFollowUp].
  ///   3. Calls `provider.askSocraticFollowUp` to generate the next turn.
  ///   4. On response, either:
  ///      - if not yet at turn 2 → appends `followUp` turn, transits
  ///        back to [awaitingTurnMode] for another optional sketch
  ///      - if at turn 2 → appends `aporetic` turn, sets
  ///        `isAporeticClosed = true`, transits to
  ///        [SocraticBubbleStatus.awaitingReflection]
  ///   5. On error/timeout: falls back to type-aware fallback question
  ///      and still emits the turn so the user isn't stuck.
  Future<void> submitSketch({
    required String sketchOcr,
    AiProvider? provider,
    String? clusterText,
  }) async {
    final q = _session?.activeQuestion;
    if (q == null) return;
    if (q.status != SocraticBubbleStatus.awaitingSketch) return;

    final turns = List<SocraticTurn>.from(q.turns);
    // Attach the OCR to the LAST turn (the one the student is responding to)
    // — that turn is the AI's prompt, and `sketchOcr` is the student's reply
    // to it. The AI follow-up will be appended as a NEW turn below.
    if (turns.isNotEmpty) {
      final last = turns.last;
      turns[turns.length - 1] = SocraticTurn(
        index: last.index,
        role: last.role,
        question: last.question,
        sketchOcr: sketchOcr,
        timestamp: last.timestamp,
      );
    }

    // Transit to generating; AI call is async.
    _session!.replaceActive(q.copyWith(
      status: SocraticBubbleStatus.generatingFollowUp,
      turns: turns,
    ));
    _bump();

    // Decide the role of the next turn: followUp at index 1, aporetic at 2.
    final nextIndex = turns.length;
    final nextRole = nextIndex >= 2
        ? SocraticTurnRole.aporetic
        : SocraticTurnRole.followUp;

    // 🛡️ Quality gate on sketch OCR (device 2026-05-10 bug).
    // MyScript on sparse sketches returns garbled tokens like "CA" or
    // "forever". The system prompt forces the model to cite ONE word
    // verbatim from the sketch → "Hai menzionato 'CA'..." appears in
    // the question. If the OCR looks low-quality, we SKIP the AI call
    // entirely and use the type-aware fallback anchored to the cluster
    // (not the garbled sketch). The student still progresses through
    // the dialogue; the question is just less personalized.
    final sketchIsLowQuality = _isSketchOcrLowQuality(sketchOcr);
    String generatedQuestion = '';
    var isAporetic = nextRole == SocraticTurnRole.aporetic;
    if (provider != null && !sketchIsLowQuality) {
      try {
        final priorQuestion = turns.isNotEmpty ? turns.last.question : q.text;
        final result = await provider
            .askSocraticFollowUp(
              tipo: q.type.name,
              tema: clusterText ?? q.text,
              priorQuestion: priorQuestion,
              sketchOcr: sketchOcr,
              role: nextRole,
              // 🎭 S2.A 2026-05-12 — pass the question's stage so the
              // follow-up adapts (counterfactual gets more-extreme
              // edge case; application varies a scenario parameter).
              stage: q.stage?.name,
            )
            .timeout(
              const Duration(seconds: 8),
              onTimeout: () => (question: '', isAporetic: isAporetic),
            );
        // Defense-in-depth: strip meta-preamble from follow-up too.
        generatedQuestion = _stripMetaPreamble(result.question.trim());
        isAporetic = result.isAporetic;
      } catch (e) {
        debugPrint('⚠️ Socratic followUp generation failed: $e');
      }
    } else if (sketchIsLowQuality) {
      debugPrint(
          '🛡️ Socratic: skipped AI follow-up — sketch OCR is low quality '
          '("$sketchOcr"). Using cluster-anchored fallback.');
    }

    if (generatedQuestion.isEmpty) {
      // Fallback to type-aware template so the user is never stuck on
      // an empty bubble. Aporetic fallback adds an explicit closing tone.
      // Use the cleaned cluster label (title preferred) — see
      // [_displayLabelForCluster] for why raw multi-line OCR is unsuitable.
      final cleanLabel =
          _displayLabelForCluster(q.clusterId, clusterText ?? '');
      generatedQuestion = nextRole == SocraticTurnRole.aporetic
          ? '${SocraticOutputFilter.fallbackForCluster(cleanLabel, q.type)} Non rispondere oggi — tienila in testa.'
          : SocraticOutputFilter.fallbackForCluster(cleanLabel, q.type);
    }

    final newTurn = SocraticTurn(
      index: nextIndex,
      role: nextRole,
      question: generatedQuestion,
      sketchOcr: null, // student hasn't replied to this new turn yet
      timestamp: DateTime.now(),
    );
    final updatedTurns = [...turns, newTurn];

    final isFinal = nextRole == SocraticTurnRole.aporetic;
    _session!.replaceActive(q.copyWith(
      turns: updatedTurns,
      status: isFinal
          ? SocraticBubbleStatus.awaitingReflection
          : SocraticBubbleStatus.awaitingTurnMode,
      isAporeticClosed: isFinal,
    ));

    // Mirror the new question into cross-feature avoid list so a future
    // Exam on the same cluster won't repeat the follow-up verbatim.
    _conceptIndex?.recordQuestionAsked(
      q.clusterId,
      generatedQuestion,
      AskedBy.socratic,
    );

    _bump();
    unawaited(_persistCheckpoint());
  }

  /// V2 multi-turn: student tapped "Annulla" on the inline scratchpad.
  /// Rolls back to [SocraticBubbleStatus.awaitingTurnMode] so they can
  /// reconsider (penso solo / try sketch again).
  void cancelSketch() {
    final q = _session?.activeQuestion;
    if (q == null) return;
    if (q.status != SocraticBubbleStatus.awaitingSketch) return;
    _session!.replaceActive(q.copyWith(
      status: SocraticBubbleStatus.awaitingTurnMode,
    ));
    _bump();
  }

  /// V2 multi-turn: student picked one of the 3 reflection outcomes
  /// after the aporetic turn. Records `finalReflection`, transits to
  /// `correct` / `correctLowConf` (cosmetic for legacy UI compat),
  /// and triggers FSRS update via the standard outcome pipeline.
  ///
  /// FSRS stability bump mapping is computed in
  /// `_persistSocraticToFSRS` — see [`finalReflection`] on the
  /// resulting `SocraticQuestion`.
  void recordReflection(SocraticReflectionOutcome outcome) {
    final q = _session?.activeQuestion;
    if (q == null) return;
    if (q.status != SocraticBubbleStatus.awaitingReflection) return;

    final now = DateTime.now();
    // Map reflection → cosmetic status so the bubble renders a green-ish
    // resolved badge instead of red/wrong. Pedagogically the multi-turn
    // path doesn't have "right/wrong" — but the visual queue must show
    // resolution. uncertain → amber (productive struggle), satisfied
    // → green, thinking → light green.
    final cosmeticStatus = switch (outcome) {
      SocraticReflectionOutcome.satisfied => SocraticBubbleStatus.correct,
      SocraticReflectionOutcome.uncertain =>
        SocraticBubbleStatus.correctLowConf,
      SocraticReflectionOutcome.thinking =>
        SocraticBubbleStatus.correctLowConf,
    };

    // 🧠 Hypercorrection detection in multi-turn (Butterfield & Metcalfe
    // 2001). The legacy binary path triggers on `confidence ≥ 4 + wrong`.
    // The multi-turn equivalent: high pre-dialogue confidence + final
    // `uncertain` (productive struggle = student realized their model
    // had cracks). This learning signal must propagate to FSRS and
    // visual ⚡ pulse, otherwise multi-turn loses Butterfield's effect
    // silently. `satisfied` after high confidence is NOT hypercorrection
    // (student was confident AND consolidated → consolidation, not
    // revision). `thinking` is mild engagement, also not hyper.
    final confidence = q.confidence ?? 3;
    final isHyper = confidence >= 4 &&
        outcome == SocraticReflectionOutcome.uncertain;

    _session!.replaceActive(q.copyWith(
      finalReflection: outcome,
      status: cosmeticStatus,
      answeredAt: now,
      isHypercorrection: isHyper,
    ));

    // Count this as an "answered" question for session stats.
    _session!.recordOutcome(cosmeticStatus);
    // Use uncertain/satisfied as "correct" signals for ZPD adaptation
    // (multi-turn engagement = positive learning signal).
    _session!.consecutiveCorrect++;
    _session!.consecutiveWrong = 0;
    _adaptZPD();

    _bump();
    unawaited(_persistCheckpoint());
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ANSWER EVALUATION (P3-17 → P3-23)
  // ─────────────────────────────────────────────────────────────────────────

  /// Record the student's self-evaluation result.
  ///
  /// [recalled] — true if the student believes they answered correctly.
  void recordResult({required bool recalled}) {
    final q = _session?.activeQuestion;
    if (q == null) return;

    final confidence = q.confidence ?? 3;
    final now = DateTime.now();

    SocraticBubbleStatus newStatus;
    bool hyper = false;

    if (recalled) {
      // Correct answer.
      newStatus = confidence >= 4
          ? SocraticBubbleStatus.correct
          : SocraticBubbleStatus.correctLowConf;
      _session!.consecutiveCorrect++;
      _session!.consecutiveWrong = 0;
    } else {
      // Wrong answer.
      if (confidence >= 4) {
        // 🔴 HYPERCORRECTION EVENT (P3-21, P3-23).
        newStatus = SocraticBubbleStatus.wrongHighConf;
        hyper = true;
      } else {
        newStatus = SocraticBubbleStatus.wrongLowConf;
      }
      _session!.consecutiveWrong++;
      _session!.consecutiveCorrect = 0;
    }

    // A3: immutable update via copyWith.
    _session!.replaceActive(q.copyWith(
      status: newStatus,
      isHypercorrection: hyper,
      answeredAt: now,
    ));

    // O1: Update session counters.
    _session!.recordOutcome(newStatus, isHypercorrection: hyper);

    // ZPD adaptation (P3-14): adjust next question type based on sliding window.
    _adaptZPD();

    debugPrint('🔶 Socratic recordResult: activeIndex=${_session!.activeIndex}'
        ' queue.length=${_session!.queue.length}'
        ' totalAnswered=${_session!.totalAnswered}'
        ' maxQuestions=${_session!.maxQuestions}'
        ' isComplete=${_session!.isComplete}');

    _bump();
    unawaited(_persistCheckpoint());
  }

  /// Mark the active question as "below ZPD" (P3-27, P3-28).
  void markBelowZPD() {
    final q = _session?.activeQuestion;
    if (q == null) return;
    // A3: immutable update via copyWith.
    _session!.replaceActive(q.copyWith(
      status: SocraticBubbleStatus.belowZPD,
      answeredAt: DateTime.now(),
    ));
    _session!.recordOutcome(SocraticBubbleStatus.belowZPD);
    _bump();
    unawaited(_persistCheckpoint());
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BREADCRUMBS (P3-24 → P3-29)
  // ─────────────────────────────────────────────────────────────────────────

  /// Request the next breadcrumb for the active question.
  ///
  /// Returns the breadcrumb text, or null if all 3 have been used.
  String? requestBreadcrumb() {
    final q = _session?.activeQuestion;
    if (q == null) return null;
    if (q.breadcrumbsUsed >= 3) return null;
    if (q.breadcrumbs.isEmpty) return null;

    final idx = q.breadcrumbsUsed;
    if (idx >= q.breadcrumbs.length) return null;

    // A3: immutable update via copyWith.
    _session!.replaceActive(q.copyWith(
      breadcrumbsUsed: q.breadcrumbsUsed + 1,
    ));
    _bump();
    unawaited(_persistCheckpoint());
    return q.breadcrumbs[idx];
  }

  /// Whether more breadcrumbs are available for the active question.
  bool get canRequestBreadcrumb {
    final q = _session?.activeQuestion;
    if (q == null) return false;
    return q.breadcrumbsUsed < 3 && q.breadcrumbs.isNotEmpty;
  }



  // ─────────────────────────────────────────────────────────────────────────
  // NAVIGATION (P3-11, P3-15)
  // ─────────────────────────────────────────────────────────────────────────

  /// Move to the next question (P3-11: one at a time).
  void next() {
    if (_session == null) return;
    // Capture the question we're moving AWAY from for adaptive analysis
    // before we mutate activeIndex.
    final justResolved =
        _session!.activeIndex < _session!.queue.length
            ? _session!.queue[_session!.activeIndex]
            : null;

    _session!.activeIndex++;

    // Skip resolved questions.
    while (_session!.activeIndex < _session!.queue.length &&
           _session!.queue[_session!.activeIndex].isResolved) {
      _session!.activeIndex++;
    }

    // 🎯 S1.A 2026-05-12 — Adaptive skip-ahead.
    //
    // If the student just answered with high confidence + positive
    // outcome on an `anchor` stage, the NEXT slot is an `elaboration`
    // on the same cluster, and we haven't already skipped this session,
    // skip the elaboration — the student doesn't need to re-explain
    // a concept they just demonstrated solid retrieval on. Floor-
    // protected to MAX 1 skip per session so we never collapse the
    // session to a single stage.
    if (_adaptiveSkipsUsed < 1 &&
        justResolved != null &&
        _session!.activeIndex < _session!.queue.length) {
      final upcoming = _session!.queue[_session!.activeIndex];
      if (_shouldAdaptiveSkip(justResolved, upcoming)) {
        _adaptiveSkipsUsed++;
        debugPrint('🎯 S1.A: adaptive skip-ahead — '
            'just=${justResolved.stage?.name} '
            '(conf=${justResolved.confidence}, '
            'wasCorrect=${justResolved.wasCorrect}, '
            'refl=${justResolved.finalReflection?.name}) '
            '→ skip ${upcoming.stage?.name}@${upcoming.clusterId}');
        // Mark the skipped question as skipped so it's not surfaced
        // again on a future `next()` skip-resolved sweep.
        _session!.replaceQuestion(
          _session!.activeIndex,
          upcoming.copyWith(
            status: SocraticBubbleStatus.skipped,
            answeredAt: DateTime.now(),
          ),
        );
        _session!.activeIndex++;
        // Continue past any other already-resolved slots.
        while (_session!.activeIndex < _session!.queue.length &&
            _session!.queue[_session!.activeIndex].isResolved) {
          _session!.activeIndex++;
        }
      }
    }

    if (_session!.isComplete) {
      // Session complete — no more questions.
    }

    _bump();
    unawaited(_persistCheckpoint());
  }

  /// 🎯 S1.A 2026-05-12 — Decides whether to skip [upcoming] given the
  /// strong-positive signal from [justResolved].
  ///
  /// Triggers when:
  ///   • Same cluster (justResolved.clusterId == upcoming.clusterId)
  ///   • `upcoming.stage == elaboration` (only elaboration is skippable
  ///     — anchor is always the start, counterfactual + application
  ///     are pedagogically protected)
  ///   • `justResolved.stage == anchor` (we're saving the elaboration
  ///     RIGHT AFTER a successful anchor — not arbitrary positions)
  ///   • Strong positive: confidence ≥4 AND (wasCorrect OR satisfied)
  bool _shouldAdaptiveSkip(
    SocraticQuestion justResolved,
    SocraticQuestion upcoming,
  ) {
    if (justResolved.clusterId != upcoming.clusterId) return false;
    if (upcoming.stage != SocraticStage.elaboration) return false;
    if (justResolved.stage != SocraticStage.anchor) return false;
    final conf = justResolved.confidence ?? 3;
    final positive = justResolved.wasCorrect ||
        justResolved.finalReflection == SocraticReflectionOutcome.satisfied;
    return conf >= 4 && positive;
  }

  /// Skip the current question (P3-15).
  void skip() {
    final q = _session?.activeQuestion;
    if (q == null) return;
    // A3: immutable update via copyWith.
    _session!.replaceActive(q.copyWith(
      status: SocraticBubbleStatus.skipped,
      answeredAt: DateTime.now(),
    ));
    _session!.recordOutcome(SocraticBubbleStatus.skipped);
    next();
  }

  /// 🚩 Sprint F.5 (2026-05-13 PM) — user reports a question as not native /
  /// poorly translated / culturally off. Available to the user only when the
  /// active `AiLanguagePreference` is in `aiBootstrap` tier (per
  /// `docs/socratic_native_validation_protocol.md`). The signal feeds the
  /// continuous native-validation loop: aggregated reports per language ×
  /// stage tell us which cells need priority review.
  ///
  /// 📋 GDPR (2026-05-14): `includeText` defaults to `false` — opt-in
  /// per GDPR Art. 7 (separate consent for distinct processing purposes).
  /// When false, `question_text` is redacted before telemetry emit; the
  /// metadata-only event still lets us count reports per (lang, stage).
  ///
  /// Pure telemetry — no state mutation, no UI side-effects, no async I/O.
  /// Reason is optional free-text (kept ≤500 chars to fit in Sentry tag).
  void reportQuestion(
    SocraticQuestion q,
    String langCode, {
    String? reason,
    bool includeText = false,
  }) {
    _telemetry.logEvent('socratic_question_reported', properties: {
      'question_id': q.id,
      'question_text': includeText
          ? (q.text.length > 500 ? q.text.substring(0, 500) : q.text)
          : '(redacted: user did not consent to text inclusion)',
      'text_included': includeText,
      'stage': q.stage?.name ?? 'unknown',
      'type': q.type.name,
      'cluster_id': q.clusterId,
      'lang_code': langCode,
      'reason': (reason == null || reason.isEmpty)
          ? 'unspecified'
          : (reason.length > 500 ? reason.substring(0, 500) : reason),
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ZPD ADAPTATION (P3-14)
  // ─────────────────────────────────────────────────────────────────────────

  void _adaptZPD() {
    final s = _session;
    if (s == null) return;

    // If 3 consecutive correct → try to upgrade next question type.
    if (s.consecutiveCorrect >= 3) {
      final nextIdx = s.activeIndex + 1;
      if (nextIdx < s.queue.length) {
        final nextQ = s.queue[nextIdx];
        final upgraded = _upgradeType(nextQ.type);
        if (upgraded != nextQ.type) {
          // O12 + A3: Preserve AI text, only change type metadata.
          s.replaceQuestion(nextIdx, nextQ.copyWith(type: upgraded));
        }
      }
    }

    // If 2 consecutive wrong → try to downgrade next question type.
    if (s.consecutiveWrong >= 2) {
      final nextIdx = s.activeIndex + 1;
      if (nextIdx < s.queue.length) {
        final nextQ = s.queue[nextIdx];
        final downgraded = _downgradeType(nextQ.type);
        if (downgraded != nextQ.type) {
          // O12 + A3: Preserve AI text, only change type metadata.
          s.replaceQuestion(nextIdx, nextQ.copyWith(type: downgraded));
        }
      }
    }
  }

  SocraticQuestionType _upgradeType(SocraticQuestionType type) {
    return switch (type) {
      SocraticQuestionType.lacuna    => SocraticQuestionType.challenge,
      SocraticQuestionType.challenge => SocraticQuestionType.depth,
      SocraticQuestionType.depth     => SocraticQuestionType.transfer,
      SocraticQuestionType.transfer  => SocraticQuestionType.transfer,
    };
  }

  SocraticQuestionType _downgradeType(SocraticQuestionType type) {
    return switch (type) {
      SocraticQuestionType.transfer  => SocraticQuestionType.depth,
      SocraticQuestionType.depth     => SocraticQuestionType.challenge,
      SocraticQuestionType.challenge => SocraticQuestionType.lacuna,
      SocraticQuestionType.lacuna    => SocraticQuestionType.lacuna,
    };
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SESSION LIFECYCLE
  // ─────────────────────────────────────────────────────────────────────────

  /// Whether the session is complete.
  bool get isComplete => _session?.isComplete ?? false;

  /// Summary text for display.
  /// Summary text for display (debug only — UI should use L10n).
  String get summaryText {
    final s = _session;
    if (s == null) return '';
    final parts = <String>[];
    if (s.totalCorrect > 0) parts.add('✅ ${s.totalCorrect}');
    if (s.totalWrong > 0) parts.add('❌ ${s.totalWrong}');
    if (s.totalHypercorrections > 0) parts.add('⚡ ${s.totalHypercorrections}');
    if (s.totalSkipped > 0) parts.add('⏭️ ${s.totalSkipped}');
    return parts.join(' · ');
  }

  /// All questions in the current session (for overlay rendering).
  List<SocraticQuestion> get allQuestions => _session?.queue ?? const [];

  /// End the session early.
  void endSession() {
    // Skip all remaining unanswered questions (A3: immutable update).
    if (_session != null) {
      for (int i = 0; i < _session!.queue.length; i++) {
        final q = _session!.queue[i];
        if (!q.isResolved) {
          _session!.replaceQuestion(i, q.copyWith(
            status: SocraticBubbleStatus.skipped,
          ));
        }
      }
    }
    _bump();
    unawaited(_persistCheckpoint());
  }

  /// Dismiss and deactivate.
  void dismiss() {
    // 📊 Emit completion before clearing session state.
    final session = _session;
    final startedAt = _sessionStartedAt;
    if (session != null && startedAt != null) {
      // 🎭 S2.A telemetry — count multi-turn extensions used. A question
      // is "extended" when it grew past the initial turn (i.e. turns ≥ 2).
      int multiturnExtensionsCount = 0;
      for (final q in session.queue) {
        if (q.turns.length >= 2) multiturnExtensionsCount++;
      }

      // 📊 S3.B 2026-05-12 — effect metrics for A/B production analysis.
      // These let us compare V3 (post-redesign) against V2 (pre-redesign)
      // in production by joining on redesign_version. See
      // docs/socratic_v3_telemetry.md for the analysis query.
      int totalConfidence = 0;
      int confidenceCount = 0;
      int uncertainReflectionsCount = 0;
      int satisfiedReflectionsCount = 0;
      int thinkingReflectionsCount = 0;
      for (final q in session.queue) {
        if (q.confidence != null) {
          totalConfidence += q.confidence!;
          confidenceCount++;
        }
        switch (q.finalReflection) {
          case SocraticReflectionOutcome.uncertain:
            uncertainReflectionsCount++;
          case SocraticReflectionOutcome.satisfied:
            satisfiedReflectionsCount++;
          case SocraticReflectionOutcome.thinking:
            thinkingReflectionsCount++;
          case null:
            break;
        }
      }
      final avgConfidence =
          confidenceCount > 0 ? totalConfidence / confidenceCount : 0.0;

      // 📊 Sprint 5 — derived metrics for failure-mode dashboards.
      final totalEvaluated = _validationAcceptCount +
          _validationRetryCount +
          _validationRejectCount;
      final retrySuccessRate = _validationRetryCount > 0
          ? _retrySuccessCount / _validationRetryCount
          : 0.0;
      final acceptRate = totalEvaluated > 0
          ? _validationAcceptCount / totalEvaluated
          : 0.0;
      _telemetry.logEvent('step_3_socratic_completed', properties: {
        // 🧪 Sprint AB-E (2026-05-14) — variant assignment tag for A/B
        // analysis. Empty map when no active experiment / no userId set.
        'variants_assigned':
            ExperimentManager.activeInstance?.currentAssignmentsMap() ??
                const <String, String>{},
        'questions_answered': session.totalAnswered,
        'questions_correct': session.totalCorrect,
        'questions_wrong': session.totalWrong,
        'duration_sec':
            DateTime.now().difference(startedAt).inSeconds,
        // 🎯 S1 telemetry (2026-05-12) — adaptive instrumentation
        'adaptive_jumps_count': _adaptiveSkipsUsed,
        // 🌀 S2.B telemetry — threshold concept candidates after this session
        'threshold_candidates_count': thresholdConceptCandidates().length,
        // 🎭 S2.A telemetry — multi-turn extensions delivered
        'multiturn_extensions_count': multiturnExtensionsCount,
        // 📊 S3.B telemetry — A/B analysis enablers
        'redesign_version': 'v3_4_2026_05_13',
        'avg_confidence': double.parse(avgConfidence.toStringAsFixed(2)),
        'uncertain_reflections': uncertainReflectionsCount,
        'satisfied_reflections': satisfiedReflectionsCount,
        'thinking_reflections': thinkingReflectionsCount,
        // 📊 Sprint 5 (2026-05-12 PM) — granular validation telemetry.
        'validation_accept_count': _validationAcceptCount,
        'validation_retry_count': _validationRetryCount,
        'validation_reject_count': _validationRejectCount,
        'retry_success_count': _retrySuccessCount,
        'fallback_count': _fallbackCount,
        'parse_fail_count': _parseFailCount,
        'parse_partial_count': _parsePartialCount,
        'cross_lang_session': _crossLangSessionFlag,
        'accept_rate': double.parse(acceptRate.toStringAsFixed(2)),
        'retry_success_rate':
            double.parse(retrySuccessRate.toStringAsFixed(2)),
        'reject_reasons': _rejectReasons.join('|'),
        // 🌊 Sprint D V3.4 ω telemetry — per-stage streaming visibility.
        // Native vs ai_bootstrap quality A/B per language. See
        // docs/socratic_v3_telemetry.md for the per-language dashboard
        // query.
        'lang_code': AiLanguagePreference.code(),
        'lang_validation_status':
            AiLanguagePreference.currentValidationStatus().name,
        'stages_streamed_count': _stagesStreamedCount,
        'stages_fallback_count': _stagesFallbackCount,
        'first_question_visible_ms': _firstQuestionVisibleMs,
        // 🛡️ Sprint E.5 — defense in depth signals. `suspicious_tiny_count`
        // is the canary: non-zero = proxy/model is capping output again.
        // `retry_on_tiny_recovered_count` shows how many we recovered.
        'suspicious_tiny_count': _suspiciousTinyCount,
        'retry_on_tiny_recovered_count': _retryOnTinyRecoveredCount,
      });
      // Record the session's question texts into the per-cluster ring
      // buffer BEFORE persisting history — Phase 4 of the maturity
      // sprint. Subsequent activations on the same clusters will pass
      // these as `avoidPrompts` to Gemini so the student doesn't see
      // verbatim duplicates within the same app session.
      _recordRecentQuestions(session);

      // Persist a history record BEFORE clearing _session — only when at
      // least one question was actually resolved. Dismissing a session
      // the user never engaged with would just pollute the dashboard.
      if (session.queue.any((q) => q.isResolved)) {
        unawaited(_saveHistory(session, startedAt));
      }
    }

    // Always delete the checkpoint on dismiss — whether the session
    // completed or the user bailed early. Mirrors Atlas: the checkpoint
    // is for crash-recovery only, not for "save my progress on dismiss".
    unawaited(_deleteCheckpoint());

    _session = null;
    _sessionStartedAt = null;
    _isActive = false;
    _isGenerating = false;
    SocraticOutputFilter.clearLog(); // O8: prevent memory leak
    _bump();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HISTORY PERSISTENCE (V1.5 maturity sprint, parity with Atlas)
  // ─────────────────────────────────────────────────────────────────────────

  /// Path to the history file (or null when running in a sandboxed env
  /// where [getSafeDocumentsDirectory] returns null — e.g. web).
  static Future<File?> _historyFile() async {
    final docs = await getSafeDocumentsDirectory();
    if (docs == null) return null;
    return File('${docs.path}/$_historyFileName');
  }

  /// Builds a history record from the live session + its start time, then
  /// prepends to `_history`, caps at 50, and atomically writes the JSON
  /// file. Failures are swallowed (best-effort persistence).
  Future<void> _saveHistory(SocraticSession s, DateTime startedAt) async {
    // ── Build the record from the in-memory session state ──────────────
    final completedAt = DateTime.now();
    final clusterIds =
        s.queue.map((q) => q.clusterId).toSet().toList(growable: false);
    final hyperClusterIds = s.queue
        .where((q) => q.isHypercorrection)
        .map((q) => q.clusterId)
        .toSet()
        .toList(growable: false);
    final breadcrumbsUsed =
        s.queue.fold<int>(0, (sum, q) => sum + q.breadcrumbsUsed);
    final answered =
        s.queue.where((q) => q.confidence != null).toList(growable: false);
    final avgConfidence = answered.isEmpty
        ? 0.0
        : answered.fold<int>(0, (sum, q) => sum + (q.confidence ?? 0)) /
            answered.length;
    final questions = [
      for (final q in s.queue)
        SocraticHistoryQuestion(
          id: q.id,
          clusterId: q.clusterId,
          text: q.text,
          typeName: q.type.name,
          statusName: q.status.name,
          confidence: q.confidence,
          recalled: q.wasCorrect,
          breadcrumbsUsed: q.breadcrumbsUsed,
          isHypercorrection: q.isHypercorrection,
        ),
    ];

    final record = SocraticHistoryRecord(
      sessionId: s.sessionId,
      startedAt: startedAt,
      completedAt: completedAt,
      totalQuestions: s.queue.length,
      correctCount: s.totalCorrect,
      wrongCount: s.totalWrong,
      skippedCount: s.totalSkipped,
      hypercorrectionCount: s.totalHypercorrections,
      clusterIds: clusterIds,
      hypercorrectionClusterIds: hyperClusterIds,
      breadcrumbsUsed: breadcrumbsUsed,
      avgConfidence: avgConfidence,
      questions: questions,
    );

    _history = [record, ..._history];
    if (_history.length > _historyCap) {
      _history = _history.take(_historyCap).toList();
    }
    notifyListeners();

    // ── Atomic write: tmp → bak → rename (mirror of exam history I/O) ──
    try {
      final file = await _historyFile();
      if (file == null) return;
      final tmp = File('${file.path}.tmp');
      final bak = File('${file.path}.bak');
      await tmp.writeAsString(
        jsonEncode(_history.map((r) => r.toJson()).toList()),
        flush: true,
      );
      if (await file.exists()) {
        if (await bak.exists()) await bak.delete();
        await file.rename(bak.path);
      }
      await tmp.rename(file.path);
    } catch (e) {
      debugPrint('⚠️ SocraticHistory save error: $e');
    }
  }

  /// Reads the history file at construction. Tolerant of corrupt
  /// primary file → falls back to .bak shadow.
  Future<void> _loadHistory() async {
    try {
      final file = await _historyFile();
      if (file == null) return;
      final candidates = [file, File('${file.path}.bak')];
      for (final candidate in candidates) {
        if (!await candidate.exists()) continue;
        try {
          final raw = await candidate.readAsString();
          if (raw.trim().isEmpty) continue;
          final list = jsonDecode(raw);
          if (list is! List) continue;
          final loaded = <SocraticHistoryRecord>[];
          for (final item in list) {
            if (item is! Map) continue;
            try {
              loaded.add(SocraticHistoryRecord.fromJson(
                  Map<String, dynamic>.from(item)));
            } catch (_) {/* skip malformed */}
          }
          if (loaded.isNotEmpty) {
            _history = loaded;
            notifyListeners();
            return;
          }
        } catch (e) {
          debugPrint('⚠️ SocraticHistory load error from ${candidate.path}: $e');
        }
      }
    } catch (e) {
      debugPrint('⚠️ SocraticHistory load error: $e');
    }
  }

  /// Dashboard hook — read the history file without instantiating a full
  /// controller. Mirrors `ExamSessionController.loadHistoryStandalone`.
  static Future<List<SocraticHistoryRecord>> loadHistoryStandalone() async {
    try {
      final file = await _historyFile();
      if (file == null) return const [];
      final candidates = [file, File('${file.path}.bak')];
      for (final candidate in candidates) {
        if (!await candidate.exists()) continue;
        try {
          final raw = await candidate.readAsString();
          if (raw.trim().isEmpty) continue;
          final list = jsonDecode(raw);
          if (list is! List) continue;
          final loaded = <SocraticHistoryRecord>[];
          for (final item in list) {
            if (item is! Map) continue;
            try {
              loaded.add(SocraticHistoryRecord.fromJson(
                  Map<String, dynamic>.from(item)));
            } catch (_) {}
          }
          if (loaded.isNotEmpty) return loaded;
        } catch (_) {}
      }
    } catch (_) {}
    return const [];
  }

  /// Get list of cluster IDs with hypercorrection marks (P3-23).
  Set<String> get hypercorrectionClusterIds {
    if (_session == null) return const {};
    return _session!.queue
        .where((q) => q.isHypercorrection)
        .map((q) => q.clusterId)
        .toSet();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CHECKPOINT (V1.5 maturity sprint, parity with Atlas)
  //
  // The checkpoint file is a single-session dump rewritten after every
  // mutation (`unawaited(_persistCheckpoint())` calls in
  // setConfidence / recordResult / markBelowZPD / requestBreadcrumb /
  // next / skip / endSession). On crash + relaunch:
  //   • [peekCheckpoint] returns a lightweight preview without
  //     instantiating the full session — used by the resume dialog.
  //   • [resumeFromCheckpoint] hydrates `_session` and re-emits
  //     `notifyListeners()` so the UI picks up where it left off.
  //   • [discardCheckpoint] / [_deleteCheckpoint] remove the file.
  //
  // The session JSON serialises every queue item (`SocraticQuestion`)
  // via the model's existing `.toJson()`; counters are re-derived on
  // restore by replaying queue statuses (single source of truth).
  // ─────────────────────────────────────────────────────────────────────────

  static Future<File?> _checkpointFile() async {
    final docs = await getSafeDocumentsDirectory();
    if (docs == null) return null;
    return File('${docs.path}/$_checkpointFileName');
  }

  /// Atomic write of the live session to the checkpoint file. Best-effort
  /// — any I/O error is logged and swallowed (the in-memory session
  /// remains the source of truth until next mutation re-tries).
  Future<void> _persistCheckpoint() async {
    final s = _session;
    final startedAt = _sessionStartedAt;
    if (s == null || startedAt == null) return;
    // Skip persistence once the session is complete / dismissed —
    // dismiss() will delete the checkpoint right after this anyway.
    if (s.queue.isEmpty) return;
    try {
      final file = await _checkpointFile();
      if (file == null) return;
      final tmp = File('${file.path}.tmp');
      final bak = File('${file.path}.bak');
      final payload = {
        ...s.toJson(),
        // _sessionStartedAt is the controller's clock, distinct from
        // SocraticSession.startedAt (which uses ctor's DateTime.now()).
        // Persist the controller's anchor so resume restores the
        // correct duration on completion.
        'controllerStartedAt': startedAt.toIso8601String(),
      };
      await tmp.writeAsString(jsonEncode(payload), flush: true);
      if (await file.exists()) {
        if (await bak.exists()) await bak.delete();
        await file.rename(bak.path);
      }
      await tmp.rename(file.path);
    } catch (e) {
      debugPrint('⚠️ SocraticCheckpoint save error: $e');
    }
  }

  /// Reads the raw checkpoint JSON. Returns null if the file does not
  /// exist or is corrupt (best-effort: tries `.bak` shadow before giving
  /// up). Cleans up corrupt files so the next session starts fresh.
  Future<Map<String, dynamic>?> _readCheckpoint() async {
    final file = await _checkpointFile();
    if (file == null) return null;
    final candidates = [file, File('${file.path}.bak')];
    for (final candidate in candidates) {
      try {
        if (!await candidate.exists()) continue;
        final raw = await candidate.readAsString();
        if (raw.trim().isEmpty) continue;
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (e) {
        debugPrint('⚠️ SocraticCheckpoint corrupt at ${candidate.path}: $e');
        try {
          await candidate.delete();
        } catch (_) {}
      }
    }
    return null;
  }

  /// Returns a lightweight preview without mutating controller state.
  /// Used by the resume dialog so the host can show "Riprendi N
  /// domande risolte / M totali?" before committing.
  Future<SocraticCheckpointPreview?> peekCheckpoint() async {
    final j = await _readCheckpoint();
    if (j == null) return null;
    try {
      final queueRaw = j['queue'];
      final queueLen = queueRaw is List ? queueRaw.length : 0;
      int resolved = 0;
      final clusters = <String>{};
      if (queueRaw is List) {
        for (final item in queueRaw) {
          if (item is! Map) continue;
          final status = item['status'] as String?;
          // Mirror SocraticQuestion.isResolved.
          if (status != null &&
              status != 'active' &&
              status != 'awaitingConfidence' &&
              status != 'awaitingAnswer') {
            resolved++;
          }
          final cid = item['clusterId'];
          if (cid is String) clusters.add(cid);
        }
      }
      final startedRaw = j['controllerStartedAt'] ?? j['startedAt'];
      return SocraticCheckpointPreview(
        totalQuestions: queueLen,
        resolvedCount: resolved,
        clusterCount: clusters.length,
        savedAt: startedRaw is String
            ? DateTime.parse(startedRaw)
            : DateTime.now(),
      );
    } catch (e) {
      debugPrint('⚠️ SocraticCheckpoint peek error: $e');
      return null;
    }
  }

  /// Restore `_session` from disk. Returns true on success. The caller
  /// is responsible for re-running [activate]'s side-effects it cares
  /// about (telemetry "_resumed" event handled here).
  Future<bool> resumeFromCheckpoint() async {
    if (_isActive) return false; // refuse to clobber a live session
    final j = await _readCheckpoint();
    if (j == null) return false;
    try {
      _session = SocraticSession.fromCheckpoint(j);
      final startedRaw = j['controllerStartedAt'] ?? j['startedAt'];
      _sessionStartedAt = startedRaw is String
          ? DateTime.parse(startedRaw)
          : DateTime.now();
      _isActive = true;
      _isGenerating = false;
      _usedFallback = false;

      // 🛡️ Orphan-state guard: if the app died mid-AI-call, the
      // checkpoint may have status=`generatingFollowUp`. There's no
      // in-flight Future on resume → spinner would hang forever.
      // Downgrade to `awaitingTurnMode` so the student can retry.
      // Same defensive treatment for `awaitingSketch` — the scratchpad
      // widget is local and its strokes are gone, so the student
      // would face an empty pad with no way to re-enter the choice.
      for (int i = 0; i < _session!.queue.length; i++) {
        final q = _session!.queue[i];
        if (q.status == SocraticBubbleStatus.generatingFollowUp ||
            q.status == SocraticBubbleStatus.awaitingSketch) {
          _session!.queue[i] = q.copyWith(
            status: SocraticBubbleStatus.awaitingTurnMode,
          );
        }
      }

      _telemetry.logEvent('step_3_socratic_resumed', properties: {
        'total_questions': _session!.queue.length,
        'resolved': _session!.queue.where((q) => q.isResolved).length,
      });
      _bump();
      return true;
    } catch (e) {
      debugPrint('⚠️ SocraticCheckpoint resume error: $e');
      // Corrupt → wipe so the user can start fresh.
      await _deleteCheckpoint();
      return false;
    }
  }

  /// Public API for the host to drop a checkpoint (e.g. user picked
  /// "Inizia nuova sessione" instead of "Riprendi").
  Future<void> discardCheckpoint() => _deleteCheckpoint();

  Future<void> _deleteCheckpoint() async {
    try {
      final file = await _checkpointFile();
      if (file == null) return;
      if (await file.exists()) await file.delete();
      final bak = File('${file.path}.bak');
      if (await bak.exists()) await bak.delete();
    } catch (e) {
      debugPrint('⚠️ SocraticCheckpoint delete error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // INTERNALS
  // ─────────────────────────────────────────────────────────────────────────

  void _bump() {
    version.value++;
    notifyListeners();
  }
}

/// Lightweight preview returned by [SocraticController.peekCheckpoint].
/// Lets the host render a resume dialog without instantiating a full
/// `SocraticSession`. Mirrors `ExamCheckpointPreview` in the exam path.
@immutable
class SocraticCheckpointPreview {
  /// Total questions in the persisted queue (including resolved).
  final int totalQuestions;

  /// How many were already answered / skipped / belowZPD when saved.
  final int resolvedCount;

  /// Distinct cluster IDs covered by the queue.
  final int clusterCount;

  /// Time the session was originally started (controller's clock).
  final DateTime savedAt;

  const SocraticCheckpointPreview({
    required this.totalQuestions,
    required this.resolvedCount,
    required this.clusterCount,
    required this.savedAt,
  });
}
