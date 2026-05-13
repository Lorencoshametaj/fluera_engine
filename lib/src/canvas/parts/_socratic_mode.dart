part of '../fluera_canvas_screen.dart';

// ============================================================================
// 🔶 SOCRATIC SPATIAL — Step 3 (Interrogazione Socratica) integration
//
// This extension wires the SocraticController into the canvas screen,
// providing spatially-anchored question bubbles ON the canvas instead of
// the side-panel chat overlay.
//
// AI STATE: 🔶 SOCRATICO — on-demand, question generation only.
//
// Spec: P3-01 → P3-46
//
// ❌ ANTI-PATTERNS:
//   P3-06: No automatic activation
//   P3-07: No loading animations
//   P3-29: AI NEVER provides the complete answer
//   P3-37: No multiple choice
//   P3-38: No timer / countdown
//   P3-40: No visible question list count
// ============================================================================

extension SocraticModeWiring on _FlueraCanvasScreenState {
  // ─────────────────────────────────────────────────────────────────────────
  // SETUP (P3-01)
  // ─────────────────────────────────────────────────────────────────────────

  /// Opens Socratic mode — invoked by toolbar button "Mettimi alla Prova".
  void showSocraticSetup() {
    // 🔄 Auto-recycle a completed-but-still-active session. After the
    // student finishes all 3 questions, the controller stays in
    // `isActive=true` state (queue resolved, awaiting explicit
    // dismiss). Without this, pressing "Quiz me" again was a silent
    // no-op (device repro 2026-05-13). Auto-dismiss the old session
    // before starting fresh so the UX is "Quiz me → new session" every
    // time, regardless of whether the previous one was dismissed.
    if (_socraticController.isActive &&
        _socraticController.isComplete) {
      _socraticController.dismiss();
    }
    // Guard: don't start if a still-running session is active, or if
    // another mode (Fog of War) is exclusive.
    if (_socraticController.isActive) return;
    if (_fogOfWarController.isActive) return;

    // 🚦 A15: Step prerequisite gate for Step 3.
    if (!_checkStepGate(
      LearningStep.step3Socratic,
      onProceed: showSocraticSetup,
    )) {
      return;
    }

    // 💳 A17: Tier gate — Free users get 3 Socratic sessions/week.
    if (!_checkTierGate(GatedFeature.socraticSession)) {
      return;
    }

    HapticFeedback.mediumImpact();

    // 🔄 Crash-recovery: if a checkpoint exists from a prior crash,
    // ask the student before clobbering it with a fresh activation.
    // Async because peekCheckpoint hits disk; the rest of the setup
    // continues in [_continueSocraticSetup] once the user picks.
    unawaited(_socraticController.peekCheckpoint().then((preview) {
      if (!mounted) return;
      if (preview != null) {
        _showResumeSocraticDialog(preview).then((shouldResume) async {
          if (!mounted) return;
          if (shouldResume == null) {
            // User dismissed — abort entirely; the checkpoint stays
            // on disk for the next attempt.
            return;
          }
          if (shouldResume) {
            final ok = await _socraticController.resumeFromCheckpoint();
            if (!mounted) return;
            if (ok) {
              // Restored — kick off the same post-activate plumbing
              // that fresh sessions get.
              _dismissedSocraticIds.clear();
              _socraticPulseController?.repeat(reverse: true);
              PedagogicalSoundEngine.instance.play(PedagogicalSound.aiArrives);
              setState(() {});
              return;
            }
            // Resume failed (corrupt checkpoint, etc.) — fall through
            // to fresh-session path below.
          } else {
            await _socraticController.discardCheckpoint();
          }
          if (mounted) _continueSocraticSetup();
        });
        return;
      }
      _continueSocraticSetup();
    }));
  }

  /// Continues the setup flow after the optional resume-checkpoint check.
  /// Extracted from [showSocraticSetup] so the dialog branch can rejoin
  /// without duplicating the cluster-detection / OCR / activation logic.
  void _continueSocraticSetup() {

    // Force-refresh cluster cache.
    if (_clusterDetector != null) {
      final activeLayer = _layerController.layers.firstWhere(
        (l) => l.id == _layerController.activeLayerId,
        orElse: () => _layerController.layers.first,
      );
      _clusterCache = _clusterDetector!.detect(
        strokes: activeLayer.strokes,
        shapes: activeLayer.shapes,
        texts: activeLayer.texts,
        images: activeLayer.images,
      );

      // Apply bounds correction for reflow offsets.
      final layerNode = activeLayer.node;
      for (final cluster in _clusterCache) {
        if (cluster.strokeIds.isEmpty) continue;
        final node = layerNode.findChild(cluster.strokeIds.first);
        if (node == null) continue;
        final tx = node.localTransform[12];
        final ty = node.localTransform[13];
        if (tx != 0.0 || ty != 0.0) {
          final offset = Offset(tx, ty);
          cluster.bounds = cluster.bounds.shift(offset);
          cluster.centroid = cluster.centroid + offset;
        }
      }
    }

    if (_clusterCache.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _l10n.socratic_needNotes,
            ),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.only(bottom: 80, left: 20, right: 20),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    // Build recall data from FSRS schedule (if available).
    final recallData = <String, int>{};
    for (final cluster in _clusterCache) {
      // Check if FSRS has data for this cluster's concepts.
      final concepts = _proactiveCache[cluster.id]?.gaps ?? [];
      if (concepts.isNotEmpty) {
        // Use average repetitions from FSRS data as recall proxy.
        int totalRep = 0;
        int count = 0;
        for (final concept in concepts) {
          final srs = _reviewSchedule[concept];
          if (srs != null) {
            totalRep += srs.reps;
            count++;
          }
        }
        recallData[cluster.id] =
            count > 0 ? (totalRep ~/ count).clamp(1, 5) : 3;
      } else {
        recallData[cluster.id] = 3; // Default: mid-range.
      }
    }

    // Activate with AI provider.
    activateSocraticMode(recallData);
  }

  /// Activate Socratic mode with the given recall data.
  void activateSocraticMode(Map<String, int> recallData) async {
    // Get AI provider from EngineScope.
    AiProvider? provider;
    try {
      provider = EngineScope.current.atlasProvider;
    } catch (_) {}

    // 🛠️ Ensure provider is initialized BEFORE the cognitive pipeline
    // runs. Device 2026-05-10 reported: opening Socratic as the first
    // AI feature of a session left the provider uninitialized → every
    // AI call (topic grouping, bulkGenerateTitles, cleanOcrItalian)
    // threw "Bad state: Atlas non inizializzato" silently → "Leggitt"-
    // style raw OCR leaked into Gemini-generated questions.
    if (provider != null && !provider.isInitialized) {
      try {
        await provider.initialize();
      } catch (e) {
        debugPrint('⚠️ Socratic: provider.initialize() failed: $e');
      }
    }

    setState(() => _socraticGeneratingPhase = _l10n.socratic_generatingOCR);

    // 🧠 OCR via ClusterConceptIndex — single source of truth.
    //
    // All four cognitive features (Semantic Titles, Exam, Socratic, Ghost
    // Map) now route OCR through the index so the cleanedOcr / title /
    // concepts derived from the same cluster are computed AT MOST ONCE
    // per session. If the user already opened Exam (or zoomed out to
    // Semantic Titles) on these clusters, resolve() returns instantly
    // from cache — zero extra Gemini calls.
    //
    // The index pipeline preserves the quality-sprint fixes:
    //   • A1: stroke timestamp sort
    //   • A3: MyScript JIIX word candidates
    //   • A4: Italian dictionary re-rank
    //   • A2: cleanOcrItalian Gemini cleanup (≥3 strokes, lazy)
    final index = _clusterConceptIndex;
    final textMap = <String, DigitalTextElement>{};
    for (final t in _digitalTextElements) {
      textMap[t.id] = t;
    }

    // 🚀 D: Parallel OCR resolve. Sequential await on N clusters means
    // N round-trips happen in series (≈200ms each → 8 cluster → 1.6s).
    // Future.wait runs them concurrently — limited by the index's
    // memoize-while-pending so duplicate clusters don't double-fire.
    //
    // 🛡️ SCALE GUARD: canvas can hold 10k+ clusters (entire degree —
    // see `project_canvas_scale`). NEVER OCR every cluster on activation.
    // We only OCR the clusters that will likely be SHOWN to the user
    // (viewport-visible). On-demand OCR for off-viewport happens later
    // when the search picker actually surfaces them.
    final topLeftForOcr = _canvasController.screenToCanvas(Offset.zero);
    final screenSizeForOcr = MediaQuery.sizeOf(context);
    final bottomRightForOcr = _canvasController.screenToCanvas(
      Offset(screenSizeForOcr.width, screenSizeForOcr.height),
    );
    final ocrViewport =
        Rect.fromPoints(topLeftForOcr, bottomRightForOcr).inflate(200);
    final ocrFutures = <Future<void>>[];
    for (final cluster in _clusterCache) {
      if (_clusterTextCache.containsKey(cluster.id)) continue;
      if (cluster.strokeIds.isEmpty && cluster.textIds.isEmpty) continue;
      if (!ocrViewport.overlaps(cluster.bounds)) continue;

      final textParts = <String>[];
      for (final tid in cluster.textIds) {
        final textEl = textMap[tid];
        if (textEl != null && textEl.text.trim().isNotEmpty) {
          textParts.add(textEl.text.trim());
        }
      }

      ocrFutures.add(() async {
        String? recognized;
        if (index != null && cluster.strokeIds.isNotEmpty) {
          final concept = await index.resolve(
            cluster,
            needsCleanedOcr: true,
          );
          recognized = concept.bestPromptSource;
        }
        final parts = [...textParts];
        if (recognized != null && recognized.isNotEmpty) {
          parts.add(recognized);
        }
        _clusterTextCache[cluster.id] = parts.join(' ').trim();
      }());
    }
    if (ocrFutures.isNotEmpty) {
      await Future.wait(ocrFutures);
    }

    debugPrint(
      '🔶 Socratic OCR: ${_clusterTextCache.length} clusters recognized',
    );

    // ── Scope to viewport (like "test me") ──────────────────────────────
    // Only ask about clusters visible on screen — the canvas could contain
    // an entire degree's worth of content!
    final topLeft = _canvasController.screenToCanvas(Offset.zero);
    final screenSize = MediaQuery.sizeOf(context);
    final bottomRight = _canvasController.screenToCanvas(
      Offset(screenSize.width, screenSize.height),
    );
    final viewport = Rect.fromPoints(topLeft, bottomRight).inflate(200);

    // 🔧 Use bounds OVERLAP, not centroid containment. A long cluster
    // (e.g. "PRIMA LEGGE NEWTON / CORPO A Riposo / SECUNDA L-") can have
    // its centroid fall outside the viewport while half the strokes are
    // visible. Device log 2026-05-11: "1/3 clusters visible" but user
    // confirmed at least 3 argomenti were on screen → centroid filter
    // was over-rejecting tall/wide clusters.
    final visibleClusters = _clusterCache
        .where((c) => viewport.overlaps(c.bounds))
        .toList();

    debugPrint(
      '🔶 Socratic viewport: ${visibleClusters.length}/${_clusterCache.length}'
      ' clusters visible',
    );

    // NB: don't early-return when `visibleClusters.isEmpty` — the scope
    // picker downstream shows ALL canvas clusters (the viewport ones are
    // merely the pre-selected default). Returning here would block the
    // student from being interrogated on off-screen argomenti, which is
    // exactly the "canvas con tutta la triennale" case we must support.

    if (mounted)
      setState(() => _socraticGeneratingPhase = _l10n.socratic_generatingQuestions);

    // 🧠 Bulk title generation — viewport-only (scale guard). Off-viewport
    // clusters get their title resolved ON-DEMAND when the search picker
    // matches them. Generating titles for 10k cluster on activation would
    // (a) blow Gemini's context window, (b) cost ~$1/session, (c) lag the
    // UI for seconds. Single Gemini call for the visible set, cached.
    if (provider != null &&
        _clusterConceptIndex != null &&
        visibleClusters.isNotEmpty) {
      final pendingTitles = <String, String>{};
      for (final c in visibleClusters) {
        final existing = _clusterConceptIndex!.peek(c.id)?.title;
        if (existing != null && existing.trim().isNotEmpty) continue;
        final text = _clusterTextCache[c.id];
        if (text != null && text.trim().isNotEmpty) {
          pendingTitles[c.id] = text.trim();
        }
      }
      if (pendingTitles.isNotEmpty) {
        await _clusterConceptIndex!.bulkGenerateTitles(pendingTitles);
      }
    }

    // 🎯 Scope picker — user must explicitly pick the argomenti.
    // The picker is search-first and scale-safe: it never iterates the
    // full `_clusterCache` to build chips. It receives lazy resolvers
    // (peek titles, peek OCR text) and renders only the top-20 ranked
    // matches at a time. With 10k+ clusters in the canvas, this is
    // bounded both in CPU (debounced O(N) ranking) and in memory
    // (≤20 widgets painted). See `project_canvas_scale`.
    final preselectedIds = visibleClusters.map((c) => c.id).toSet();
    Set<String> chosenIds = preselectedIds;
    if (_clusterCache.length > 1 && mounted) {
      setState(() => _socraticGeneratingPhase = null);
      final picked = await SocraticScopePicker.show(
        context: context,
        allClusters: _clusterCache,
        viewportClusterIds: preselectedIds,
        titleResolver: (id) => _clusterConceptIndex?.peek(id)?.title,
        // Normalize raw OCR before showing as fallback: MyScript emits
        // one "\n" per line of handwriting, which the picker would
        // truncate mid-paragraph (device 2026-05-12 screenshot:
        // "LEGGITI NEWTON\nPRIMA\nCORPO A Rito\nSE…"). Collapse all
        // whitespace to single spaces so the picker truncation produces
        // readable single-line previews.
        textResolver: (id) {
          final raw = _clusterTextCache[id];
          if (raw == null) return null;
          final collapsed = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
          return collapsed.isEmpty ? null : collapsed;
        },
        initialSelectedClusterIds: preselectedIds,
        // Lazy OCR + title for off-viewport clusters the picker decides
        // to surface (empty-query top-N or search matches). Pre-picker
        // pipeline OCR'd only viewport clusters for scale safety — this
        // callback unlocks the rest on-demand. Bounded by the picker's
        // own dedupe (each id fires at most once per session) and the
        // _maxResults=20 cap, so even on a 10k-cluster canvas at most
        // 20 lazy resolves occur per picker session.
        lazyResolve: (ids) =>
            _resolveClustersForPicker(ids, provider: provider, textMap: textMap),
      );
      if (!mounted) return;
      if (picked == null || picked.isEmpty) {
        // Dismissed or no selection — abort the whole activation.
        return;
      }
      chosenIds = picked;
      setState(() =>
          _socraticGeneratingPhase = _l10n.socratic_generatingQuestions);
    }

    // 🛡️ Late OCR + title resolution for clusters chosen OUT of viewport.
    // The pre-picker pipeline only OCR'd / titled viewport clusters
    // (scale guard). If the student picked a cluster found via search
    // (so it had a cached title) but its OCR isn't in `_clusterTextCache`,
    // resolve it now — only for the ≤10 chosen clusters, bounded.
    final lateOcr = <Future<void>>[];
    for (final id in chosenIds) {
      if (_clusterTextCache.containsKey(id)) continue;
      final cluster = _clusterCache.firstWhere(
        (c) => c.id == id,
        orElse: () => visibleClusters.isNotEmpty
            ? visibleClusters.first
            : _clusterCache.first,
      );
      if (cluster.id != id) continue;
      if (cluster.strokeIds.isEmpty && cluster.textIds.isEmpty) continue;
      final textParts = <String>[];
      for (final tid in cluster.textIds) {
        final textEl = textMap[tid];
        if (textEl != null && textEl.text.trim().isNotEmpty) {
          textParts.add(textEl.text.trim());
        }
      }
      lateOcr.add(() async {
        String? recognized;
        if (index != null && cluster.strokeIds.isNotEmpty) {
          final concept =
              await index.resolve(cluster, needsCleanedOcr: true);
          recognized = concept.bestPromptSource;
        }
        final parts = [...textParts];
        if (recognized != null && recognized.isNotEmpty) {
          parts.add(recognized);
        }
        _clusterTextCache[cluster.id] = parts.join(' ').trim();
      }());
    }
    if (lateOcr.isNotEmpty) {
      await Future.wait(lateOcr);
    }

    final scopedClusters =
        _clusterCache.where((c) => chosenIds.contains(c.id)).toList();
    if (scopedClusters.isEmpty) return;

    // 🧠 Topic grouping: consolidate fragmented clusters into 3-5 logical
    // topics. Without this, "prima legge di Newton" written in 8 short
    // strokes generates 8 nearly-duplicate Socratic questions (reported
    // device 2026-05-10). Mirrors the Atlas Exam consolidation pass.
    var activationClusters = scopedClusters;
    var activationTexts = _clusterTextCache;
    var activationRecall = recallData;

    if (scopedClusters.length >= 3 && provider != null) {
      final scopeTexts = <String, String>{};
      for (final c in scopedClusters) {
        final t = _clusterTextCache[c.id];
        if (t != null && t.trim().isNotEmpty) scopeTexts[c.id] = t;
      }
      if (scopeTexts.length >= 2) {
        final groups = await _groupClustersByTopic(provider, scopeTexts);
        if (groups != null &&
            groups.isNotEmpty &&
            groups.length < scopedClusters.length) {
          final reps = <ContentCluster>[];
          final repTexts = <String, String>{};
          final repRecall = <String, int>{};
          for (final group in groups) {
            final sourceIds = group.clusterIds.toSet();
            final sources = scopedClusters
                .where((c) => sourceIds.contains(c.id))
                .toList();
            if (sources.isEmpty) continue;
            var bounds = sources.first.bounds;
            final allStrokes = <String>[];
            for (final src in sources) {
              bounds = bounds.expandToInclude(src.bounds);
              allStrokes.addAll(src.strokeIds);
            }
            // Dedup OCR text fragments — fragmented clusters of one phrase
            // often share the same OCR token after dict re-rank.
            final mergedSet = <String>{};
            for (final s in sources) {
              final t = (_clusterTextCache[s.id] ?? '').trim();
              if (t.isNotEmpty) mergedSet.add(t);
            }
            final merged = mergedSet.join(' ');
            final repId =
                'topic_${group.topic.hashCode.toUnsigned(32).toRadixString(36)}';
            reps.add(ContentCluster(
              id: repId,
              strokeIds: allStrokes,
              bounds: bounds,
              centroid: bounds.center,
            ));
            repTexts[repId] = merged.isEmpty ? group.topic : merged;
            // Recall: take the WORST (lowest) recall across the group's
            // source clusters — Socratic should target the weakest link.
            var minRecall = 5;
            for (final s in sources) {
              final r = recallData[s.id] ?? 3;
              if (r < minRecall) minRecall = r;
            }
            repRecall[repId] = minRecall;
          }
          if (reps.isNotEmpty) {
            activationClusters = reps;
            activationTexts = repTexts;
            activationRecall = repRecall;
            debugPrint(
                '🔶 Socratic topic grouping: ${scopedClusters.length} → ${reps.length}');
          }
        }
      }
    }

    await _socraticController.activate(
      clusters: activationClusters,
      recallData: activationRecall,
      provider: provider,
      clusterTexts: activationTexts,
    );

    // Clear any previously dismissed bubble IDs from prior sessions.
    _dismissedSocraticIds.clear();

    // Start pulse animation.
    _socraticPulseController?.repeat(reverse: true);

    // 🎵 A13.4: "Il mentore arriva" — C4→E4 ascending notes
    PedagogicalSoundEngine.instance.play(PedagogicalSound.aiArrives);

    setState(() => _socraticGeneratingPhase = null);

    if (_socraticController.isActive && mounted) {
      // R4: Show fallback warning if AI call failed and generic questions used.
      if (_socraticController.usedFallback) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_l10n.socratic_fallbackUsed),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.only(bottom: 80, left: 20, right: 20),
            duration: const Duration(seconds: 4),
            backgroundColor: Colors.orange[700],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _l10n.socratic_sessionStarted(
                  _socraticController.allQuestions.length),
            ),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.only(bottom: 80, left: 20, right: 20),
            duration: const Duration(seconds: 3),
            backgroundColor: const Color(0xFF37474F),
          ),
        );
      }
    }
  }

  /// 🛠️ Lazy resolver fed to [SocraticScopePicker]. Runs OCR (MyScript) +
  /// cleanOcrItalian (Gemini) + title generation for the given cluster
  /// ids in parallel, writing results into [_clusterTextCache] and the
  /// [_clusterConceptIndex]. Returns when ALL ids are resolved so the
  /// picker can re-render with the freshly-resolved labels.
  ///
  /// The picker dedupes ids per session, so this is called at most once
  /// per cluster id even when the user types/clears the search box.
  Future<void> _resolveClustersForPicker(
    List<String> clusterIds, {
    required AiProvider? provider,
    required Map<String, DigitalTextElement> textMap,
  }) async {
    final index = _clusterConceptIndex;
    final futures = <Future<void>>[];
    final pendingTitleTexts = <String, String>{};
    debugPrint('🛠️ scopePicker lazy resolve: ${clusterIds.length} ids');
    for (final id in clusterIds) {
      // Find the cluster object (O(N) — picker passes ≤20 ids, fine).
      ContentCluster? cluster;
      for (final c in _clusterCache) {
        if (c.id == id) {
          cluster = c;
          break;
        }
      }
      if (cluster == null) {
        debugPrint('🛠️ lazy resolve skip $id: not in _clusterCache');
        continue;
      }
      if (cluster.strokeIds.isEmpty && cluster.textIds.isEmpty) {
        debugPrint('🛠️ lazy resolve skip $id: no strokes/texts '
            '(shapes=${cluster.shapeIds.length}, '
            'images=${cluster.imageIds.length})');
        continue;
      }
      futures.add(() async {
        // Collect any digital text elements attached to the cluster.
        final textParts = <String>[];
        for (final tid in cluster!.textIds) {
          final el = textMap[tid];
          if (el != null && el.text.trim().isNotEmpty) {
            textParts.add(el.text.trim());
          }
        }
        String? recognized;
        if (index != null && cluster.strokeIds.isNotEmpty) {
          final concept = await index.resolve(cluster,
              needsCleanedOcr: true, needsTitle: true);
          recognized = concept.bestPromptSource;
        }
        final parts = [...textParts];
        if (recognized != null && recognized.isNotEmpty) parts.add(recognized);
        final joined = parts.join(' ').trim();
        if (joined.isNotEmpty) {
          _clusterTextCache[cluster.id] = joined;
          // If the index already produced a title (resolve needsTitle:true),
          // peek confirms it and we're done. If not, queue for the bulk
          // title generation below — single Gemini call for the batch.
          if (index?.peek(cluster.id)?.title == null) {
            pendingTitleTexts[cluster.id] = joined;
          }
        }
      }());
    }
    if (futures.isEmpty) return;
    await Future.wait(futures);

    // Bulk-generate titles for any clusters that came out of resolve
    // without one (resolve(needsTitle:true) only runs single-cluster;
    // bulk is more efficient when there are several at once).
    if (provider != null &&
        index != null &&
        pendingTitleTexts.isNotEmpty) {
      await index.bulkGenerateTitles(pendingTitleTexts);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CONFIDENCE + SELF-EVAL
  // ─────────────────────────────────────────────────────────────────────────

  /// Set confidence level for the active question (P3-17).
  ///
  /// V2 multi-turn: `autoChooseAnswer: false` transitions to
  /// `awaitingTurnMode` so the bubble shows the [Penso solo / Schizzo]
  /// choice instead of jumping straight to binary self-eval.
  void _socraticSetConfidence(int level) {
    _socraticController.setConfidence(level, autoChooseAnswer: false);
    HapticFeedback.selectionClick();
    // A2: No setState — ListenableBuilder on controller handles rebuild.
  }

  /// V2 multi-turn: student picked "Penso solo" or "Schizzo".
  void _socraticChooseTurnMode(bool sketch) {
    _socraticController.chooseTurnMode(sketch: sketch);
  }

  /// V2 multi-turn: student confirmed a sketch on the inline scratchpad.
  /// Fires the AI follow-up call.
  Future<void> _socraticSubmitSketch(String sketchOcr) async {
    final activeQ = _socraticController.session?.activeQuestion;
    if (activeQ == null) return;
    AiProvider? provider;
    try {
      provider = EngineScope.current.atlasProvider;
    } catch (_) {}
    // Defense in depth — same init guard as activateSocraticMode in case
    // the follow-up happens on a different code path that bypassed it.
    if (provider != null && !provider.isInitialized) {
      try {
        await provider.initialize();
      } catch (_) {}
    }
    final clusterText = _clusterTextCache[activeQ.clusterId] ??
        _clusterConceptIndex?.peek(activeQ.clusterId)?.bestPromptSource ??
        '';
    await _socraticController.submitSketch(
      sketchOcr: sketchOcr,
      provider: provider,
      clusterText: clusterText,
    );
  }

  /// V2 multi-turn: student tapped "Annulla" on the inline scratchpad.
  void _socraticCancelSketch() {
    _socraticController.cancelSketch();
  }

  /// V2 multi-turn: student picked one of the 3 reflection outcomes.
  void _socraticRecordReflection(SocraticReflectionOutcome outcome) {
    _socraticController.recordReflection(outcome);
    HapticFeedback.mediumImpact();
    if (_socraticController.isComplete) {
      _showSocraticSummary();
    } else {
      _socraticScheduleAutoAdvance();
    }
  }

  /// Auto-advance the queue after the active bubble resolves so the
  /// student doesn't have to chase the "Avanti →" tap target.
  ///
  /// **Delay = 3000ms** (Bjork's desirable difficulty). Earlier prototype
  /// used 1200ms but that's a "fluent transition" — Bjork specifically
  /// warns that overly fluent practice produces illusion of mastery
  /// without consolidation. 2-3 seconds is the minimum window for
  /// post-retrieval reflection on the feedback badge / hypercorrection
  /// shock / metacognitive update. The student can still tap "Avanti →"
  /// to override and advance immediately.
  ///
  /// We bail out if the user advanced manually in the meantime
  /// (activeIndex changed) or the session ended or the controller was
  /// torn down.
  void _socraticScheduleAutoAdvance() {
    final session = _socraticController.session;
    if (session == null) {
      debugPrint('🔶 autoAdvance: session==null, skip schedule');
      return;
    }
    final fromIndex = session.activeIndex;
    debugPrint('🔶 autoAdvance scheduled: from=$fromIndex, '
        'queue.length=${session.queue.length}, delay=3000ms');
    Future.delayed(const Duration(milliseconds: 3000), () {
      if (!mounted) {
        debugPrint('🔶 autoAdvance: !mounted, bail');
        return;
      }
      if (!_socraticController.isActive) {
        debugPrint('🔶 autoAdvance: controller !isActive, bail');
        return;
      }
      final s = _socraticController.session;
      if (s == null) {
        debugPrint('🔶 autoAdvance: session==null after delay, bail');
        return;
      }
      if (s.activeIndex != fromIndex) {
        debugPrint('🔶 autoAdvance: activeIndex moved '
            '$fromIndex→${s.activeIndex}, bail (user advanced manually)');
        return;
      }
      final q = s.activeQuestion;
      if (q == null) {
        debugPrint('🔶 autoAdvance: activeQuestion==null at $fromIndex, bail');
        return;
      }
      if (!q.isResolved) {
        debugPrint('🔶 autoAdvance: q.status=${q.status.name} '
            'not resolved, bail');
        return;
      }
      debugPrint('🔶 autoAdvance: firing next() from index=$fromIndex');
      _socraticController.next();
      debugPrint('🔶 autoAdvance: after next() activeIndex='
          '${_socraticController.session?.activeIndex}, '
          'isComplete=${_socraticController.isComplete}');
      if (_socraticController.isComplete) {
        _showSocraticSummary();
      }
    });
  }

  /// Record self-evaluation result (P3-20).
  void _socraticRecordResult(bool recalled) {
    // O15: Capture active question BEFORE recordResult changes state.
    final q = _socraticController.session?.activeQuestion;
    _socraticController.recordResult(recalled: recalled);

    // Haptic feedback varies by result (P3-21).
    if (q != null && q.isHypercorrection) {
      HapticFeedback.heavyImpact(); // ⚡ Shock!
      // ⚡ P3-23: Visual pulse on the cluster node.
      final clusterId = q.clusterId;
      setState(() => _hypercorrectionPulseClusterIds.add(clusterId));
      // Auto-remove after 3s.
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() => _hypercorrectionPulseClusterIds.remove(clusterId));
        }
      });
    } else if (q != null && q.wasWrong) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.lightImpact();
    }
    if (_socraticController.isComplete) {
      _showSocraticSummary();
    } else {
      _socraticScheduleAutoAdvance();
    }
    // A2: No setState — ListenableBuilder on controller handles rebuild.
  }

  /// Skip the current question (P3-15).
  void _socraticSkip() {
    HapticFeedback.selectionClick();
    _socraticController.skip();
    if (_socraticController.isComplete) {
      _showSocraticSummary();
    } else {
      _socraticScheduleAutoAdvance();
    }
    // A2: No setState — ListenableBuilder on controller handles rebuild.
  }

  /// Request a breadcrumb (P3-24).
  void _socraticRequestBreadcrumb() {
    _socraticController.requestBreadcrumb();
    HapticFeedback.selectionClick();
    // A2: No setState — ListenableBuilder on controller handles rebuild.
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SESSION END
  // ─────────────────────────────────────────────────────────────────────────

  /// Show the rich session summary (P3-46).
  void _showSocraticSummary() {
    if (!mounted) return;
    final session = _socraticController.session;
    if (session == null) return;

    // ── Persist results to FSRS ──────────────────────────────────────────
    _persistSocraticToFSRS(session);

    final total = session.totalAnswered + session.totalSkipped;
    final pct = total > 0 ? (session.totalCorrect / total * 100).round() : 0;

    // V2 multi-turn detection — if ANY question used the reflection path,
    // swap correct/wrong framing for reflection breakdown (pedagogically
    // multi-turn has no "right/wrong", only thinking/uncertain/satisfied).
    int thinkingCount = 0;
    int uncertainCount = 0;
    int satisfiedCount = 0;
    int multiTurnCount = 0;
    for (final q in session.queue) {
      switch (q.finalReflection) {
        case SocraticReflectionOutcome.thinking:
          thinkingCount++;
          multiTurnCount++;
        case SocraticReflectionOutcome.uncertain:
          uncertainCount++;
          multiTurnCount++;
        case SocraticReflectionOutcome.satisfied:
          satisfiedCount++;
          multiTurnCount++;
        case null:
          break;
      }
    }
    final isMultiTurnSession = multiTurnCount > 0;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0F1028), Color(0xFF060612)],
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),

            // Score circle + title
            Row(
              children: [
                // Score / engagement circle
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isMultiTurnSession
                          ? [const Color(0xFF7B1FA2), const Color(0xFF4A148C)]
                          : pct >= 70
                              ? [const Color(0xFF66BB6A), const Color(0xFF2E7D32)]
                              : pct >= 40
                                  ? [const Color(0xFFFFB300), const Color(0xFFE65100)]
                                  : [const Color(0xFFEF5350), const Color(0xFFC62828)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (isMultiTurnSession
                                ? const Color(0xFF7B1FA2)
                                : pct >= 70
                                    ? const Color(0xFF66BB6A)
                                    : pct >= 40
                                        ? const Color(0xFFFFB300)
                                        : const Color(0xFFEF5350))
                            .withValues(alpha: 0.3),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      isMultiTurnSession ? '🤔' : '$pct%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _l10n.socratic_sessionComplete,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isMultiTurnSession
                            ? '$multiTurnCount dialoghi · $total domande'
                            : '${session.totalCorrect}/$total ${_l10n.socratic_summaryCorrect.toLowerCase()}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Visual result bar — one segment per question
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 8,
                child: Row(
                  children: [
                    for (final q in session.queue)
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 0.5),
                          color: switch (q.finalReflection) {
                            SocraticReflectionOutcome.satisfied =>
                              const Color(0xFF66BB6A),
                            SocraticReflectionOutcome.uncertain =>
                              const Color(0xFF7B1FA2),
                            SocraticReflectionOutcome.thinking =>
                              const Color(0xFF42A5F5),
                            null => q.wasCorrect
                                ? const Color(0xFF66BB6A)
                                : q.isHypercorrection
                                    ? const Color(0xFFFF9800)
                                    : q.status == SocraticBubbleStatus.skipped
                                        ? Colors.grey.shade700
                                        : const Color(0xFFEF5350),
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Stats row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: isMultiTurnSession
                  ? [
                      _summaryStatChip(
                        '💡', '$thinkingCount',
                        'Spunti', const Color(0xFF42A5F5),
                      ),
                      _summaryStatChip(
                        '🤔', '$uncertainCount',
                        'Dubbi', const Color(0xFF7B1FA2),
                      ),
                      _summaryStatChip(
                        '😌', '$satisfiedCount',
                        'Consolidati', const Color(0xFF66BB6A),
                      ),
                      _summaryStatChip(
                        '⚡', '${session.totalHypercorrections}',
                        _l10n.socratic_summaryHypercorrections,
                        const Color(0xFFFF9800),
                      ),
                    ]
                  : [
                      _summaryStatChip(
                        '✅', '${session.totalCorrect}',
                        _l10n.socratic_summaryCorrect, const Color(0xFF66BB6A),
                      ),
                      _summaryStatChip(
                        '❌', '${session.totalWrong}',
                        _l10n.socratic_summaryWrong, const Color(0xFFEF5350),
                      ),
                      _summaryStatChip(
                        '⚡', '${session.totalHypercorrections}',
                        _l10n.socratic_summaryHypercorrections,
                        const Color(0xFFFF9800),
                      ),
                      _summaryStatChip(
                        '⏭️', '${session.totalSkipped}',
                        _l10n.socratic_summarySkipped, Colors.grey,
                      ),
                    ],
            ),
            const SizedBox(height: 16),

            // Metacognitive insight
            _buildMetacognitiveInsight(
              session,
              isMultiTurn: isMultiTurnSession,
              thinking: thinkingCount,
              uncertain: uncertainCount,
              satisfied: satisfiedCount,
            ),

            // 📚 Consolidation phase (Productive Failure phase 2 — Kapur 2008).
            // PF without expert consolidation has effect size that "disappears
            // or reverses" (Sinha & Kapur 2021). We can't act as expert, but
            // we CAN structure the bridge back to the student's own notes:
            // for every uncertain / wrong bubble, surface a tap target that
            // pans to the source cluster and pulses it briefly. The student's
            // notes ARE the consolidation material — Socratic just routes
            // attention back to them.
            ..._buildConsolidationSection(session),

            // 🌀 S2.C 2026-05-12 — Threshold concept tile (Meyer & Land).
            // Surfaces clusters that the heuristic flags as "liminale"
            // (productive struggle over multiple sessions). Copy is
            // explicitly encouraging — "è normale che ti sfidino" — so
            // the student doesn't read this as failure.
            ..._buildThresholdConceptTile(),

            const SizedBox(height: 20),

            // Close button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1B5E20),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  dismissSocraticMode();
                },
                child: Text(
                  _l10n.socratic_closeSession,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryStatChip(
    String emoji,
    String value,
    String label,
    Color color,
  ) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _buildMetacognitiveInsight(
    SocraticSession session, {
    bool isMultiTurn = false,
    int thinking = 0,
    int uncertain = 0,
    int satisfied = 0,
  }) {
    String insight;
    IconData icon;
    Color color;

    // Multi-turn path: pedagogically uncertain > satisfied > thinking, because
    // productive struggle (Bjork 2011) is the strongest learning signal. The
    // ⚡ hypercorrection branch still wins when high pre-dialogue confidence
    // ended in uncertain (Butterfield & Metcalfe 2001).
    if (isMultiTurn) {
      if (session.totalHypercorrections > 0) {
        insight = _l10n.socratic_insightHypercorrection(
            session.totalHypercorrections);
        icon = Icons.flash_on;
        color = const Color(0xFFFF9800);
      } else if (uncertain >= thinking && uncertain >= satisfied && uncertain > 0) {
        insight =
            'Hai avuto $uncertain momento/i di dubbio produttivo — questo è il segnale di apprendimento più forte. Le ricerche (Bjork 2011) mostrano che lo "struggle desiderabile" consolida la memoria meglio della comprensione fluida. Rivedi i cluster coinvolti.';
        icon = Icons.psychology;
        color = const Color(0xFF7B1FA2);
      } else if (satisfied > 0 && uncertain == 0) {
        insight =
            'Modelli mentali solidi — il dialogo socratico li ha confermati. Gli intervalli di ripetizione si allungheranno.';
        icon = Icons.check_circle_outline;
        color = const Color(0xFF66BB6A);
      } else {
        insight =
            'Dialogo aperto — hai esplorato i concetti senza arrivare a chiusura. Continua a rileggere e tornare sui punti.';
        icon = Icons.lightbulb_outline;
        color = const Color(0xFF42A5F5);
      }
    } else if (session.totalHypercorrections > 0) {
      insight = _l10n.socratic_insightHypercorrection(
          session.totalHypercorrections);
      icon = Icons.flash_on;
      color = const Color(0xFFFF9800);
    } else if (session.totalCorrect == session.totalAnswered &&
        session.totalAnswered > 0) {
      insight = _l10n.socratic_insightPerfect;
      icon = Icons.emoji_events;
      color = const Color(0xFF66BB6A);
    } else if (session.totalWrong > session.totalCorrect) {
      insight = _l10n.socratic_insightGaps;
      icon = Icons.menu_book;
      color = const Color(0xFFFFB300);
    } else {
      insight = _l10n.socratic_insightBalanced;
      icon = Icons.balance;
      color = const Color(0xFF42A5F5);
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              insight,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 📚 Consolidation section — Productive Failure phase 2 (Kapur 2008).
  ///
  /// Builds a "Da rileggere" list of bubbles where the student marked
  /// `uncertain` (multi-turn) or got a binary `wasWrong` result. Each row
  /// pans the canvas to the source cluster + pulses it briefly. The
  /// student's own notes are the consolidation material; the AI never
  /// reveals an answer — coherent with the Socratic identity vincolo.
  ///
  /// Returns a list of widgets so the caller can spread them into a
  /// surrounding Column without forcing a wrapper Container when empty.
  List<Widget> _buildConsolidationSection(SocraticSession session) {
    final items = <({SocraticQuestion q, bool isMimicrySuspect})>[];
    for (final q in session.queue) {
      final isUncertain =
          q.finalReflection == SocraticReflectionOutcome.uncertain;
      // For the legacy binary path, the relevant signal is "wrong" — we
      // route the student back to the notes for the same reason.
      final isWrong = q.finalReflection == null && q.wasWrong;
      // 🎭 Mimicry detection (Threshold Concepts — Meyer & Land 2003).
      // The student picked `satisfied` (FSRS +2.0) BUT the multi-turn
      // sketch content was thin (<3 significant tokens, or sketch turns
      // were skipped entirely after the initial). This is the
      // "mimicry" pattern: student produces an output that *looks* like
      // mastery without the underlying conceptual transformation. We
      // route them back to consolidation rather than trusting the
      // satisfied signal at face value.
      final isMimicry = q.finalReflection ==
              SocraticReflectionOutcome.satisfied &&
          _isMimicrySuspect(q);
      if (isUncertain || isWrong || isMimicry) {
        items.add((q: q, isMimicrySuspect: isMimicry));
      }
    }
    if (items.isEmpty) return const [];

    return [
      const SizedBox(height: 14),
      Row(
        children: [
          const Icon(Icons.menu_book_outlined,
              size: 14, color: Color(0xFF7B1FA2)),
          const SizedBox(width: 6),
          Text(
            'Da rileggere · ${items.length}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Text(
        'Rivedi i tuoi appunti sui punti dove hai avuto dubbi. La rilettura mirata DOPO la riflessione consolida l\'apprendimento (Kapur).',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.45),
          fontSize: 11,
          height: 1.4,
        ),
      ),
      const SizedBox(height: 8),
      for (final item in items)
        _buildConsolidationRow(item.q, isMimicrySuspect: item.isMimicrySuspect),
    ];
  }

  /// 🌀 S2.C 2026-05-12 — Threshold concept tile.
  ///
  /// Surfaces clusters flagged by `SocraticController.thresholdConceptCandidates()`
  /// as "liminale" — productive struggle over multiple sessions (Meyer &
  /// Land 2003). The copy explicitly reframes the difficulty as the
  /// learning process itself, NOT as failure.
  ///
  /// Hidden when no candidates exist (most sessions, especially early
  /// usage). Tap on a candidate → pan canvas to the cluster (same UX
  /// as the consolidation rows above) so the student can return to
  /// their notes with the gentle Meyer & Land framing.
  List<Widget> _buildThresholdConceptTile() {
    final candidates = _socraticController.thresholdConceptCandidates();
    if (candidates.isEmpty) return const [];
    return [
      const SizedBox(height: 14),
      Row(
        children: [
          const Icon(Icons.auto_awesome_outlined,
              size: 14, color: Color(0xFFFFB300)),
          const SizedBox(width: 6),
          Text(
            'Argomenti in fase liminale · ${candidates.length}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Text(
        'Sono argomenti che ti stanno sfidando da più sessioni. È normale: '
        'è il processo di apprendimento profondo (Meyer & Land 2003). Non '
        'è fallimento — è il punto in cui un concetto si trasforma.',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.45),
          fontSize: 11,
          height: 1.4,
        ),
      ),
      const SizedBox(height: 8),
      for (final clusterId in candidates)
        _buildThresholdRow(clusterId),
    ];
  }

  /// One row in the threshold concept tile. Tap pans canvas to the
  /// cluster's anchor (same pattern as the consolidation rows).
  Widget _buildThresholdRow(String clusterId) {
    final title = _clusterConceptIndex?.peek(clusterId)?.title?.trim();
    final fallbackRaw = _clusterTextCache[clusterId];
    final fallback = fallbackRaw
        ?.replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final display = (title != null && title.isNotEmpty)
        ? title
        : (fallback != null && fallback.isNotEmpty)
            ? (fallback.length > 36
                ? '${fallback.substring(0, 36)}…'
                : fallback)
            : 'Cluster ${clusterId.substring(0, clusterId.length.clamp(0, 6))}';

    // Find a representative anchor for pan-to. Use the most recent
    // session's question for this cluster if available, else canvas
    // origin as a soft fallback.
    Offset anchor = Offset.zero;
    for (final c in _clusterCache) {
      if (c.id == clusterId) {
        anchor = c.centroid;
        break;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: InkWell(
        onTap: () => _consolidateOnCluster(clusterId, anchor),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFFFB300).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: const Color(0xFFFFB300).withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            children: [
              const Text('🌀', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  display,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.north_east,
                size: 14,
                color: Colors.white.withValues(alpha: 0.45),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Mimicry detection — see Meyer & Land 2003 (Threshold Concepts) and
  /// Sweller's "expertise reversal" critique of fluent practice.
  ///
  /// Returns true when the question used the multi-turn path AND the
  /// student attempted at least one sketch turn AND the captured OCR was
  /// thin (< 3 alphanumeric tokens of ≥3 characters). This is a heuristic,
  /// not a verdict: it just flags the bubble for the consolidation list
  /// so the student is gently routed back to their notes despite picking
  /// `satisfied`.
  bool _isMimicrySuspect(SocraticQuestion q) {
    if (q.turns.length < 2) return false;
    bool anyAttempt = false;
    int totalSignificantTokens = 0;
    for (final t in q.turns) {
      final ocr = t.sketchOcr;
      if (ocr == null) continue;
      anyAttempt = true;
      // Count tokens ≥3 chars that contain at least one letter (filters
      // pure-punctuation noise without rejecting numerical concepts).
      for (final tok in ocr.split(RegExp(r'\s+'))) {
        final trimmed = tok.trim();
        if (trimmed.length < 3) continue;
        if (!RegExp(r'[a-zA-ZÀ-ÿ]').hasMatch(trimmed)) continue;
        totalSignificantTokens++;
      }
    }
    if (!anyAttempt) return false;
    return totalSignificantTokens < 3;
  }

  Widget _buildConsolidationRow(
    SocraticQuestion q, {
    bool isMimicrySuspect = false,
  }) {
    final title = _clusterConceptIndex?.peek(q.clusterId)?.title?.trim();
    // Same OCR normalization as the picker: collapse \n/whitespace so
    // multi-line MyScript output doesn't render as a stack of fragments.
    final fallbackRaw = _clusterTextCache[q.clusterId];
    final fallback = fallbackRaw
        ?.replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final display = (title != null && title.isNotEmpty)
        ? title
        : (fallback != null && fallback.isNotEmpty)
            ? (fallback.length > 36
                ? '${fallback.substring(0, 36)}…'
                : fallback)
            : 'Cluster ${q.clusterId.substring(0, q.clusterId.length.clamp(0, 6))}';

    final rowColor = isMimicrySuspect
        ? const Color(0xFFFFB300) // amber for mimicry — distinct from uncertain purple
        : const Color(0xFF7B1FA2);
    final emoji = isMimicrySuspect ? '🎭' : '🤔';
    final hint = isMimicrySuspect
        ? ' · forse rivedi un attimo'
        : '';

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: InkWell(
        onTap: () => _consolidateOnCluster(q.clusterId, q.anchorPosition),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: rowColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: rowColor.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$display$hint',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.north_east,
                size: 14,
                color: Colors.white.withValues(alpha: 0.45),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Closes the summary sheet, pans the canvas to the cluster's anchor,
  /// and flashes its border for ~3s so the student can locate their notes.
  void _consolidateOnCluster(String clusterId, Offset anchor) {
    Navigator.of(context).pop(); // dismiss the summary sheet
    // Find the cluster bounds (we know the anchor; fall back to a small
    // square if the cluster vanished — shouldn't happen mid-session).
    ContentCluster? cluster;
    for (final c in _clusterCache) {
      if (c.id == clusterId) {
        cluster = c;
        break;
      }
    }
    final targetRect = cluster?.bounds ??
        Rect.fromCenter(center: anchor, width: 320, height: 200);
    // Animate camera to the cluster.
    final screenSize = MediaQuery.sizeOf(context);
    final inflated = Rect.fromLTRB(
      targetRect.left - targetRect.width * 0.12,
      targetRect.top - targetRect.height * 0.18,
      targetRect.right + targetRect.width * 0.12,
      targetRect.bottom + targetRect.height * 0.18,
    );
    _canvasController.animateDiveTo(
      nodeWorldRect: inflated,
      viewportSize: screenSize,
      durationSeconds: 0.5,
    );
    // Reuse the hypercorrection pulse pattern for visual highlight. Semantics
    // overlap: both signal "this cluster needs your attention right now".
    setState(() => _hypercorrectionPulseClusterIds.add(clusterId));
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _hypercorrectionPulseClusterIds.remove(clusterId));
    });
    dismissSocraticMode();
  }

  /// Persist Socratic results to FSRS scheduler.
  void _persistSocraticToFSRS(SocraticSession session) {
    for (final q in session.queue) {
      // Find concepts associated with this cluster
      final concepts = _proactiveCache[q.clusterId]?.gaps ?? [];
      if (concepts.isEmpty) continue;

      // V2 multi-turn path: reflection-based stability bump.
      if (q.finalReflection != null) {
        final bump = switch (q.finalReflection!) {
          SocraticReflectionOutcome.thinking => 0.5,
          SocraticReflectionOutcome.uncertain => 1.0,
          SocraticReflectionOutcome.satisfied => 2.0,
        };
        for (final concept in concepts) {
          final existing = _reviewSchedule[concept] ?? SrsCardData.newCard();
          _reviewSchedule[concept] = FsrsScheduler.applyReflection(
            existing,
            stabilityBump: bump,
          );
        }
        continue;
      }

      // Legacy single-turn path: quality-based recall signal.
      if (!q.wasCorrect && !q.wasWrong) continue; // Skip unanswered
      final quality = q.wasCorrect ? 2 : 0;
      final confidence = q.confidence ?? 3;
      for (final concept in concepts) {
        final existing = _reviewSchedule[concept] ?? SrsCardData.newCard();
        _reviewSchedule[concept] = FsrsScheduler.review(
          existing,
          quality: quality,
          confidence: confidence,
        );
      }
    }

    // Trigger persist
    _saveSpacedRepetition();
    debugPrint('🔶 Socratic FSRS: ${session.totalAnswered} results persisted');
  }

  /// Dismiss Socratic mode.
  void dismissSocraticMode() {
    // Mark hypercorrection clusters permanently (P3-23).
    final hyperIds = _socraticController.hypercorrectionClusterIds;
    if (hyperIds.isNotEmpty) {
      debugPrint('⚡ Hypercorrection clusters: $hyperIds');
    }

    // 🚦 A15: Record Step 3 completion if any questions were answered.
    if (_socraticController.allQuestions.any((q) => q.isResolved)) {
      _stepGateController.recordStepCompletion(LearningStep.step3Socratic);
      _saveStepGateHistory();
    }

    _socraticController.dismiss();
    _socraticPulseController?.stop();
    _socraticPulseController?.reset();
    // A2: setState still needed here for pulse controller visual reset
    // (pulse state lives in _FlueraCanvasScreenState, not in SocraticController).
    setState(() {});
  }

  // ─────────────────────────────────────────────────────────────────────────
  // OVERLAY BUILDERS
  // ─────────────────────────────────────────────────────────────────────────

  /// Build all Socratic mode overlays for the UI stack.
  List<Widget> buildSocraticOverlays(BuildContext context) {
    final widgets = <Widget>[];

    // ── Loading overlay during generation ────────────────────────────
    if (_socraticGeneratingPhase != null) {
      final phase = _socraticGeneratingPhase!;
      widgets.add(
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              color: Colors.black.withValues(alpha: 0.3),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 18,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xE60A0A1A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFFFFB300).withValues(alpha: 0.3),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFB300).withValues(alpha: 0.15),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFFFFB300),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        phase,
                        style: TextStyle(
                          color: const Color(0xFFFFB300).withValues(alpha: 0.9),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _l10n.socratic_generatingSubtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      return widgets;
    }

    if (!_socraticController.isActive) return widgets;

    // 🌍 V3.4 ω — AI-bootstrap language banner. When the active AI
    // language has not yet been native-validated (per
    // `docs/socratic_native_validation_protocol.md`), show a discreet
    // top banner so the student knows the questions are AI-translated
    // and feedback is welcome. IT + EN are `productionNative` and skip
    // this banner.
    final langStatus = AiLanguagePreference.currentValidationStatus();
    if (langStatus == SocraticValidationStatus.aiBootstrap) {
      final langName = AiLanguagePreference.displayName();
      widgets.add(
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: IgnorePointer(
              child: Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xE60A0A1A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFFFB300).withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('🌐', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        // i18n: keep static EN copy (the bootstrap
                        // disclaimer itself is meta — the student already
                        // sees it because they picked a non-native lang).
                        'Questions in $langName are AI-translated. '
                        'Feedback welcome in Settings → AI Output Language.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 11.5,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    // ⚡ P3-23: Render hypercorrection pulse overlays BEHIND bubbles.
    for (final clusterId in _hypercorrectionPulseClusterIds) {
      final cluster = _clusterCache.where((c) => c.id == clusterId).firstOrNull;
      if (cluster == null) continue;
      widgets.add(
        AnimatedBuilder(
          animation: _canvasController,
          builder: (_, __) {
            final pos = _canvasController.canvasToScreen(cluster.centroid);
            return Positioned(
              left: pos.dx - 60,
              top: pos.dy - 60,
              child: IgnorePointer(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 1.0, end: 0.0),
                  duration: const Duration(seconds: 3),
                  builder: (_, opacity, __) {
                    final pulse = (opacity * 6 * 3.14159).remainder(3.14159 * 2);
                    final scale = 1.0 + 0.3 * (pulse > 0 ? (pulse < 3.14159 ? 1.0 : -1.0) * (1 - (pulse / 3.14159 - 1).abs()) : 0);
                    return Transform.scale(
                      scale: scale.clamp(0.8, 1.4),
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFF1744).withValues(alpha: opacity * 0.5),
                              blurRadius: 40,
                              spreadRadius: 20,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        ),
      );
    }

    final questions = _socraticController.allQuestions;
    final activeQ = _socraticController.session?.activeQuestion;

    // 🎯 Auto-pan to the active question when it's off-screen. The picker
    // lets the student pick off-viewport clusters; when the controller
    // advances to the question on one of those clusters the bubble's
    // anchor falls outside the screen and the loop below skips it →
    // "si ferma alla prima domanda" (device 2026-05-12). Pan once per
    // activeIndex change so the bubble enters the viewport before we
    // even reach the off-screen guard.
    if (activeQ != null) {
      final activeScreenPos =
          _canvasController.canvasToScreen(activeQ.anchorPosition);
      final screenSize = MediaQuery.sizeOf(context);
      final isOffScreen = activeScreenPos.dx < -300 ||
          activeScreenPos.dx > screenSize.width + 100 ||
          activeScreenPos.dy < -200 ||
          activeScreenPos.dy > screenSize.height + 100;
      if (isOffScreen && _lastPannedActiveQuestionId != activeQ.id) {
        _lastPannedActiveQuestionId = activeQ.id;
        // Pan to the cluster bounds (or fallback to a small rect at the
        // anchor) so the bubble is in view by the next frame.
        ContentCluster? cluster;
        for (final c in _clusterCache) {
          if (c.id == activeQ.clusterId) {
            cluster = c;
            break;
          }
        }
        final target = cluster?.bounds ??
            Rect.fromCenter(
              center: activeQ.anchorPosition,
              width: 320,
              height: 200,
            );
        final inflated = Rect.fromLTRB(
          target.left - target.width * 0.12,
          target.top - target.height * 0.18,
          target.right + target.width * 0.12,
          target.bottom + target.height * 0.18,
        );
        debugPrint('🔶 Socratic: auto-pan to off-screen active question '
            'q.id=${activeQ.id} cluster=${activeQ.clusterId}');
        // Schedule post-frame so it doesn't fight the current build.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _canvasController.animateDiveTo(
            nodeWorldRect: inflated,
            viewportSize: screenSize,
            durationSeconds: 0.45,
          );
        });
      }
    }

    for (int i = 0; i < questions.length; i++) {
      final q = questions[i];

      // ── ALL questions → SocraticBubble (resolved ones are read-only) ──
      // Skip un-resolved questions that are NOT active (they wait their turn).
      if (!q.isResolved && q.id != activeQ?.id) continue;
      // Skip resolved bubbles that the user swiped away.
      if (_dismissedSocraticIds.contains(q.id)) continue;

      // Convert canvas position to screen position.
      final screenPos = _canvasController.canvasToScreen(q.anchorPosition);

      // Skip if off-screen — BUT never skip the ACTIVE question. The
      // active bubble must always be rendered: when the picker lets the
      // student pick an off-viewport cluster, the auto-pan above
      // animates the camera over ~0.45s. During the animation the
      // AnimatedBuilder rebuilds and the bubble enters the viewport.
      // If we `continue` here on the active bubble it would NEVER be
      // added to the widget tree, so the camera animates but the
      // student sees nothing. (Device repro 2026-05-12: "non vedo le
      // domande nello schermo".) Stack clips negative coordinates
      // safely so off-screen-but-listed bubbles cost ~nothing.
      final screenSize = MediaQuery.sizeOf(context);
      final isOffScreen = screenPos.dx < -300 ||
          screenPos.dx > screenSize.width + 100 ||
          screenPos.dy < -200 ||
          screenPos.dy > screenSize.height + 100;
      final isActiveBubble = q.id == activeQ?.id;
      if (isOffScreen && !isActiveBubble) {
        continue;
      }

      // Get current breadcrumb text (if any revealed).
      String? breadcrumbText;
      if (q.breadcrumbsUsed > 0 && q.breadcrumbs.isNotEmpty) {
        final bcIdx = (q.breadcrumbsUsed - 1).clamp(
          0,
          q.breadcrumbs.length - 1,
        );
        breadcrumbText = q.breadcrumbs[bcIdx];
      }

      final isActive = q.id == activeQ?.id;

      widgets.add(
        AnimatedBuilder(
          animation: _canvasController,
          builder: (_, __) {
            final updatedPos = _canvasController.canvasToScreen(
              q.anchorPosition,
            );
            return SocraticBubble(
              key: ValueKey('socratic_${q.id}'),
              question: q,
              screenPosition: updatedPos,
              isActiveQuestion: isActive,
              currentIndex: i,
              totalQuestions: questions.length,
              questionResults: [
                for (final qr in questions)
                  qr.isResolved
                      ? qr.wasCorrect
                      : null,
              ],
              onConfidenceSelected: isActive
                  ? (level) => _socraticSetConfidence(level)
                  : null,
              onSelfEval: isActive
                  ? (recalled) => _socraticRecordResult(recalled)
                  : null,
              // V2 multi-turn callbacks.
              onChooseTurnMode: isActive
                  ? (sketch) => _socraticChooseTurnMode(sketch)
                  : null,
              onSubmitSketch: isActive
                  ? (ocr) => _socraticSubmitSketch(ocr)
                  : null,
              onCancelSketch: isActive ? () => _socraticCancelSketch() : null,
              onRecordReflection: isActive
                  ? (outcome) => _socraticRecordReflection(outcome)
                  : null,
              onSkip: isActive ? () => _socraticSkip() : null,
              onNext: isActive
                  ? () {
                      _socraticController.next();
                      if (_socraticController.isComplete) {
                        _showSocraticSummary();
                      }
                    }
                  : null,
              onRequestBreadcrumb: isActive
                  ? () => _socraticRequestBreadcrumb()
                  : null,
              onDismissResolved: !isActive
                  ? () {
                      _dismissedSocraticIds.add(q.id);
                      setState(() {});
                    }
                  : null,
              currentBreadcrumbText: breadcrumbText,
              breadcrumbsUsed: q.breadcrumbsUsed,
              canRequestBreadcrumb:
                  isActive && _socraticController.canRequestBreadcrumb,
            );
          },
        ),
      );
    }

    // End session button (bottom-center).
    if (!_socraticController.isComplete) {
      widgets.add(
        Positioned(
          bottom: 100,
          left: 0,
          right: 0,
          child: Center(
            child: FilledButton.icon(
              icon: const Icon(Icons.flag, size: 18),
              label: Text(_l10n.socratic_endSession),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF455A64),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 4,
              ),
              onPressed: () {
                HapticFeedback.heavyImpact();
                _socraticController.endSession();
                _showSocraticSummary();
                // A2: No setState — ListenableBuilder handles rebuild.
              },
            ),
          ),
        ),
      );
    } else {
      // Session complete — dismiss button.
      widgets.add(
        Positioned(
          bottom: 100,
          left: 0,
          right: 0,
          child: Center(
            child: FilledButton.icon(
              icon: const Icon(Icons.check_circle, size: 18),
              label: Text(_l10n.socratic_closeSession),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 4,
              ),
              onPressed: () => dismissSocraticMode(),
            ),
          ),
        ),
      );
    }

    // Socratic indicator dot (P3-04: 8px, amber, pulsing).
    widgets.add(
      Positioned(
        top: MediaQuery.of(context).padding.top + 8,
        left: 0,
        right: 0,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFFB300).withValues(alpha: 0.8),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFB300).withValues(alpha: 0.4),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _l10n.socratic_activeIndicator,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return widgets;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // RESUME DIALOG (V1.5 maturity sprint)
  //
  // Shown when [SocraticController.peekCheckpoint] reports a checkpoint
  // file from a prior crash. Three outcomes:
  //   • true  → user chose "Riprendi" — caller invokes resumeFromCheckpoint
  //   • false → user chose "Nuova sessione" — caller invokes discardCheckpoint
  //   • null  → user dismissed via barrier-tap or back gesture; the
  //             checkpoint stays on disk for the next attempt.
  // Mirrors `_showResumeExamDialog` in `_atlas_ai.dart`.
  // ─────────────────────────────────────────────────────────────────────────

  Future<bool?> _showResumeSocraticDialog(SocraticCheckpointPreview preview) {
    final remaining = (preview.totalQuestions - preview.resolvedCount)
        .clamp(0, preview.totalQuestions);
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Row(
          children: [
            Text('🔶', style: TextStyle(fontSize: 22)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Riprendi sessione Socratic?',
                style: TextStyle(
                  color: Color(0xFFFFB347),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$remaining domande da rispondere',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${preview.resolvedCount}/${preview.totalQuestions} già risolte · ${preview.clusterCount} argomenti',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Iniziato ${_relativeSocraticTime(preview.savedAt)}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 11,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Nuova sessione',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFFB347),
              foregroundColor: const Color(0xFF0A0A1A),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Riprendi',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  /// Mirror of `_relativeTimeAgo` in `_atlas_ai.dart` — kept local to the
  /// Socratic extension so we don't have to expose it on the parent state.
  String _relativeSocraticTime(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inMinutes < 1) return 'ora';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min fa';
    if (diff.inHours < 24) return '${diff.inHours} ore fa';
    if (diff.inDays == 1) return 'ieri';
    if (diff.inDays < 7) return '${diff.inDays} giorni fa';
    return '${when.day.toString().padLeft(2, '0')}/${when.month.toString().padLeft(2, '0')}';
  }
}
