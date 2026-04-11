part of '../fluera_canvas_screen.dart';

// ProactiveAnalysisEntry, ProactiveStatus are imported by fluera_canvas_screen.dart
// from './ai/proactive_analysis_model.dart'.

/// 🧠 PROACTIVE KNOWLEDGE GAP ANALYSIS
///
/// Watches cluster activity. After 2s of writing inactivity, silently runs
/// OCR + Atlas gap analysis on clusters in the viewport. Results appear as
/// glowing cyan dots — zero friction for the user.
extension ProactiveAnalysisWiring on _FlueraCanvasScreenState {

  // ── HELPERS ────────────────────────────────────────────────────────

  /// O(1) cluster lookup instead of O(n) _clusterCache.where for every call.
  dynamic _clusterById(String id) =>
      _clusterCache.where((c) => c.id == id).firstOrNull;

  // ── TRIGGER ──────────────────────────────────────────────────────────

  void _scheduleProactiveAnalysis() {
    // 🧠 P1-26: No background AI analysis during Step 1 (notes) and Step 2 (recall).
    // Proactive gap analysis is only allowed from Step 4+ (elaboration).
    if (!_learningStepController.isProactiveAnalysisAllowed) return;

    // 🛡️ P1-25: Don't trigger analysis during active writing flow.
    if (_flowGuard.isFlowProtected) return;

    _proactiveDebounceTimer?.cancel();
    _proactiveDebounceTimer = Timer(const Duration(milliseconds: 2000), () {
      if (mounted) _runProactiveAnalysisForVisibleClusters();
    });
  }

  Future<void> _runProactiveAnalysisForVisibleClusters() async {
    // Approximate viewport — use a generous 2000×2000 window centered at origin
    final topLeft = _canvasController.screenToCanvas(Offset.zero);
    final bottomRight = _canvasController.screenToCanvas(
      const Offset(2000, 2000),
    );
    final viewport = Rect.fromPoints(topLeft, bottomRight).inflate(300);

    final candidates =
        _clusterCache
            .where((c) {
              if (_proactiveRunning.contains(c.id)) return false;
              final entry = _proactiveCache[c.id];
              // Skip if already analysed and not expired
              if (entry != null &&
                  !entry.isExpired &&
                  (entry.status == ProactiveStatus.pending ||
                      entry.status == ProactiveStatus.ready ||
                      entry.status == ProactiveStatus.seen ||
                      entry.status == ProactiveStatus.dueForReview))
                return false;
              // Skip if every gap already mastered (green dot shows via allMastered flag)
              if (entry != null &&
                  entry.gaps.isNotEmpty &&
                  entry.gaps.every((g) => _sessionMastered.contains(g)))
                return false;
              return viewport.contains(c.centroid);
            })
            .take(3)
            .toList();

    for (final cluster in candidates) {
      if (!mounted) return;
      unawaited(_runProactiveAnalysis(cluster));
      await Future.delayed(
        const Duration(milliseconds: 600),
      ); // stagger slightly
    }
  }

  // ── DUE FOR REVIEW ───────────────────────────────────────────────────

  /// Scans [_reviewSchedule] for overdue concepts and marks matching cluster
  /// dots as [ProactiveStatus.dueForReview] (orange 📅 dot).
  void _checkDueForReview() {
    final now = DateTime.now();
    final overdueKeys =
        _reviewSchedule.entries
            .where((e) => e.value.nextReview.isBefore(now))
            .map((e) => e.key.toLowerCase())
            .toSet();
    if (overdueKeys.isEmpty) return;

    bool changed = false;
    for (final cluster in _clusterCache) {
      final text = (_clusterTextCache[cluster.id] ?? '').toLowerCase();
      if (text.isEmpty) continue;
      // If any overdue concept appears in the cluster text → flag as due
      final hasDue = overdueKeys.any((k) => text.contains(k));
      if (hasDue) {
        final existing = _proactiveCache[cluster.id];
        if (existing == null) {
          // Create a placeholder entry so the dot appears
          _proactiveCache[cluster.id] = ProactiveAnalysisEntry(
            clusterId: cluster.id,
            status: ProactiveStatus.dueForReview,
            gaps: overdueKeys.where((k) => text.contains(k)).take(5).toList(),
          );
        } else if (existing.status != ProactiveStatus.dueForReview) {
          existing.status = ProactiveStatus.dueForReview;
        }
        changed = true;
      }
    }
    if (changed && mounted) setState(() {});

  }

  Future<void> _runProactiveAnalysis(ContentCluster cluster) async {
    if (_proactiveRunning.contains(cluster.id)) return;
    _proactiveRunning.add(cluster.id);
    // Show pending dot
    _proactiveCache[cluster.id] = ProactiveAnalysisEntry(
      clusterId: cluster.id,
      status: ProactiveStatus.pending,
    );
    if (mounted) setState(() {});
    try {
      // 1. OCR
      await _recognizeClusterTextOnDemand(cluster);
      final clusterText = (_clusterTextCache[cluster.id] ?? '').trim();

      // Sanity check: skip if OCR result looks garbage
      // - Too short (< 2 chars)
      // - Looks like ML Kit noise: contains digits mixed with letters randomly,
      //   or is suspiciously long with uppercase mid-word (e.g. "INTEGRALISS Cald")
      if (clusterText.isEmpty || clusterText.length < 2) {
        _proactiveCache.remove(cluster.id);
        return;
      }
      // Heuristic: if text has > 2 words and cluster has < 5 strokes, likely noise
      final wordCount = clusterText.split(RegExp(r'\s+')).length;
      final strokeCount = cluster.strokeIds.length;
      if (wordCount >= 3 && strokeCount < 5) {
        // Probably noise — a short writing that the OCR over-fragmented
        _proactiveCache.remove(cluster.id);
        return;
      }

      // 2. Local context — 1000px includes more semantic signal, sorted by proximity
      final nearbyTexts =
          _clusterCache
              .where(
                (c) =>
                    c.id != cluster.id &&
                    (c.centroid - cluster.centroid).distance < 1000,
              )
              .toList()
            ..sort(
              (a, b) => (a.centroid - cluster.centroid).distance.compareTo(
                (b.centroid - cluster.centroid).distance,
              ),
            );
      final nearbyTextsList =
          nearbyTexts
              .map((c) => _clusterTextCache[c.id] ?? '')
              .where((t) => t.trim().isNotEmpty)
              .take(8)
              .toList();

      // Concepts already covered this session (avoid repeating in CONN)
      final coveredConcepts = {
        ..._sessionMastered,
        ..._sessionExplored.toSet(),
      };
      final coveredNote =
          coveredConcepts.isNotEmpty
              ? 'ALREADY COVERED (EXCLUDE from CONN): ${coveredConcepts.take(10).join(', ')}\n'
              : '';

      // 3. Ask Atlas via stream (raw — no canvas system prompt interference)
      final provider = EngineScope.current.atlasProvider;
      if (!provider.isInitialized) await provider.initialize();

      final lang = _deviceLanguageName;

      // Build a rich context map that lets the AI infer INTENT
      final contextMap = nearbyTextsList
          .asMap()
          .entries
          .map((e) => '  [${e.key + 1}] "${e.value}"')
          .join('\n');
      final hasContext = nearbyTextsList.isNotEmpty;

      final prompt =
          hasContext
              ? '${_nativeLangInstruction}\n'
                  'LANGUAGE RULE: You MUST respond ENTIRELY in the same language as the instruction above. Never switch to English.\n'
                  '\n'
                  'You are ATLAS, a world-class academic tutor and knowledge graph expert.\n'
                  'A student is building a mind map. Analyze their notes:\n'
                  '\n'
                  'FOCUS WORD: "$clusterText"\n'
                  'NEARBY CONTEXT:\n$contextMap\n'
                  '\n'
                  'YOUR TASK: Identify the 5 most critical MISSING concepts from their map,\n'
                  'using the nearby context as a lens to pinpoint the exact study angle.\n'
                  '\n'
                  '━━ RULES ━━\n'
                  '✓ Include formulas if the topic is math/physics/chemistry (e.g. ∫f(x)dx = F(b)-F(a))\n'
                  '✓ Gaps must be SPECIFIC to the angle implied by nearby words, not generic facts\n'
                  '✗ Never repeat concepts already listed on the map\n'
                  '✗ Never start SCAN with "The student is..." or "Lo studente sta..."\n'
                  '\n'
                  '━━ FORMAT (copy EXACTLY, no extra text, no markdown) ━━\n'
                  '▸ SCAN  <1 concise DESCRIPTION of "$clusterText" in the context of nearby words>\n'
                  '▸ CONN  <gap1>, <gap2>, <gap3>, <gap4>, <gap5>\n'
                  '\n'
                  '━━ EXAMPLES (for reference) ━━\n'
                  'Input: FOCUS="Integrali" NEARBY="derivate, funzioni"\n'
                   '▸ SCAN  Metodo per calcolare aree e volumi tramite somme infinitesimali\n'
                   '▸ CONN  ∫f(x)dx = F(b)-F(a), Teorema fondamentale del calcolo, Primitive, Integrazione per parti, Sostituzioni\n'
                  '\n'
                  'Input: FOCUS="Newton" NEARBY="gravità, pianeti, orbite"\n'
                   '▸ SCAN  Leggi del moto e gravitazione universale formulate da Isaac Newton\n'
                   '▸ CONN  F = ma, G·m₁m₂/r², Prima legge (inerzia), Terza legge (azione-reazione), Campo gravitazionale\n'
                  '\n'
                  '${coveredNote}'
                  'Now produce output for FOCUS="$clusterText" NEARBY="${nearbyTextsList.join(', ')}"'
              : '${_nativeLangInstruction}\n'
                  'LANGUAGE RULE: You MUST respond ENTIRELY in the same language as the instruction above. Never switch to English.\n'
                  '\n'
                  'You are ATLAS, a world-class academic tutor.\n'
                  'A student just wrote "$clusterText" on their mind map.\n'
                  '\n'
                  'YOUR TASK: Identify the 5 most foundational concepts to understand "$clusterText".\n'
                  '\n'
                  '━━ RULES ━━\n'
                  '✓ Include a key formula or equation if the topic has one\n'
                  '✗ NEVER start SCAN with "The student is..." or "Lo studente sta..." — write a DEFINITION\n'
                  '✗ No generic platitudes ("$clusterText è un concetto importante...")\n'
                  '\n'
                  '━━ FORMAT (copy EXACTLY) ━━\n'
                  '▸ SCAN  <1 concise DESCRIPTION of "$clusterText">\n'
                  '▸ CONN  <gap1>, <gap2>, <gap3>, <gap4>, <gap5>\n'
                  '\n'
                  '━━ EXAMPLES ━━\n'
                  'Input: "Integrali"\n'
                   '▸ SCAN  Operazione inversa della derivata, calcola aree e accumulazioni\n'
                   '▸ CONN  ∫f(x)dx = F(b)-F(a), Teorema fondamentale del calcolo, Primitive, Integrazione per parti, Somme di Riemann\n'
                  '\n'
                  'Input: "DNA"\n'
                   '▸ SCAN  Molecola a doppia elica che contiene il codice genetico degli organismi\n'
                   '▸ CONN  Doppia elica, Basi azotate (A,T,G,C), Replicazione, Trascrizione in RNA, Codice genetico\n'
                  '\n'
                  'Now produce output for: "$clusterText"';


      final buffer = StringBuffer();
      final stream = provider.askAtlasStream(prompt, []);
      await stream
          .timeout(
            const Duration(seconds: 18),
            onTimeout: (sink) => sink.close(),
          )
          .forEach((chunk) => buffer.write(chunk));

      final raw = buffer.toString().trim();


      // Parse ▸ SCAN
      final scanMatch = RegExp(
        r'▸\s*SCAN\s+(.+?)(?=▸|$)',
        dotAll: true,
      ).firstMatch(raw);
      final scan =
          scanMatch?.group(1)?.trim().replaceAll('\n', ' ') ?? clusterText;

      // Parse ▸ CONN → individual concepts
      final connMatch = RegExp(
        r'▸\s*CONN\s+(.+?)(?=▸|$)',
        dotAll: true,
      ).firstMatch(raw);
      final gaps =
          connMatch != null
              ? connMatch
                  .group(1)!
                  .split(RegExp(r'[,\n]'))
                  .map((s) => s.trim().replaceAll(RegExp(r'^[-•·]\s*'), ''))
                  .where((s) => s.isNotEmpty && s.length > 1)
                  .take(5)
                  .toList()
              : <String>[];

      if (!mounted) return;

      if (gaps.isNotEmpty) {
        _proactiveCache[cluster.id] = ProactiveAnalysisEntry(
          clusterId: cluster.id,
          status: ProactiveStatus.ready,
          scanText: scan,
          gaps: gaps,
        );

        _rebuildProactiveMaps();
        if (mounted) setState(() {});
      } else {
        _proactiveCache.remove(cluster.id);
        _rebuildProactiveMaps();
        if (mounted) setState(() {}); // remove orange dot
      }
    } catch (e) {

      _proactiveCache.remove(cluster.id);
      _rebuildProactiveMaps();
      if (mounted) setState(() {}); // remove stuck orange dot
    } finally {
      _proactiveRunning.remove(cluster.id);
    }
  }

  // ── CARD REVEAL ───────────────────────────────────────────────────────

  void _showProactiveCard(ContentCluster cluster) {
    final entry = _proactiveCache[cluster.id];
    if (entry != null && entry.status == ProactiveStatus.ready) {
      _presentProactiveCard(cluster, entry);
    } else {
      _runProactiveAnalysis(cluster).then((_) {
        final fresh = _proactiveCache[cluster.id];
        if (fresh != null && mounted) _presentProactiveCard(cluster, fresh);
      });
    }
  }

  void _presentProactiveCard(
    ContentCluster cluster,
    ProactiveAnalysisEntry entry,
  ) {
    final screenPos = _canvasController
        .canvasToScreen(cluster.centroid)
        .translate(0, -60);
    final cardText = entry.scanText;
    HapticFeedback.mediumImpact();
    _addProactiveCard(
      'proactive_${cluster.id}_${DateTime.now().microsecondsSinceEpoch}',
      cardText,
      screenPos,
      entry.gaps,
      cluster.id,
    );
    entry.status = ProactiveStatus.seen;
    if (mounted) setState(() {});
  }

  // ── ACTIVE RECALL (R&K 2006) ──────────────────────────────────────────

  /// Opens a verify card for [concept] from [srcClusterId].
  /// Auto-selects initial mode based on fail history (dual coding adaptation).
  void _openVerifyCard(String concept, String srcClusterId) {
    if (!mounted) return;
    final entry = _proactiveCache[srcClusterId];
    if (entry == null) return;

    final screenSize = MediaQuery.sizeOf(context);
    final pos = Offset(screenSize.width / 2 - 130, 100);
    final cardId =
        'verify_${srcClusterId}_${DateTime.now().microsecondsSinceEpoch}';

    // Confidence-based recall — no mode toggle needed

    setState(() {
      _atlasCards.add(
        _AtlasCardEntry(
          id: cardId,
          text: '',
          position: pos,
          verifyQuestion: concept,
          sourceClusterId: srcClusterId,
        ),
      );
    });
  }

  /// Called when the user submits their answer in the verify card.
  /// Streams Atlas evaluation, updates SR schedule.
  Future<void> _onVerifyAnswer(
    String cardId,
    String concept,
    String userAnswer,
    String mode,
  ) async {
    final provider = EngineScope.current.atlasProvider;
    if (!provider.isInitialized) await provider.initialize();

    // Detect mode: confidence-based (zero-keyboard) vs Feynman vs standard
    final isConfidence = mode.startsWith('confidence_');
    final isFeynman = cardId.startsWith('feynman_');
    final String evalPrompt;

    if (isConfidence) {
      // Zero-keyboard confidence-based recall (Bjork JOL, 2011)
      final level = int.tryParse(mode.split('_').last) ?? 0;

      if (level == 1) {
        // 🟢 So spiegarlo → client already showed badge, just update SR
        _sessionMastered.add(concept);
        final existing = _reviewSchedule[concept] ?? SrsCardData.newCard();
        _reviewSchedule[concept] = FsrsScheduler.review(existing, quality: 2, confidence: 5);
        _conceptFailHistory.remove(concept);
        _saveSpacedRepetition();
        return; // No Atlas call needed
      }

      // 🟡 Ho dubbi / 🔴 Non ricordo → pure explanation, no emoji prefix
      final levelPrompt = level == 0
          ? 'Explain "$concept" clearly and concisely (2-3 lines). Focus ONLY on the concept.'
          : 'Define "$concept" clearly (2-3 lines). Then suggest what specific material to review.';
      evalPrompt =
        '${_nativeLangInstruction}\n'
        'LANGUAGE RULE: You MUST respond ENTIRELY in the same language as the previous instruction. Never respond in English unless the instruction is in English.\n'
        '\n'
        'You are ATLAS, a concise learning assistant.\n'
        'CONCEPT: "$concept"\n'
        '$levelPrompt\n'
        '\n'
        '━━ RULES ━━\n'
        '✗ No preamble, no praise, no commentary on the student\n'
        '✗ Never use markdown bold (**) or bullet points\n'
        '✗ Do NOT start with any emoji\n'
        '✓ Start directly with the explanation\n';
    } else if (isFeynman) {
      final srcId = _atlasCards.where((c) => c.id == cardId).firstOrNull?.sourceClusterId;
      final ctx = srcId != null ? (_clusterTextCache[srcId] ?? '').trim() : '';
      evalPrompt = _buildFeynmanEvalPrompt(concept, userAnswer, ctx);
    } else {
      evalPrompt =
        '${_nativeLangInstruction}\n'
        'LANGUAGE RULE: You MUST respond ENTIRELY in the same language as the instruction above. Never switch to English.\n'
        '\n'
        'You are ATLAS evaluating retrieval practice (Roediger & Karpicke, 2006).\n'
        '\n'
        'CONCEPT: "$concept"\n'
        'STUDENT\'S ANSWER: "$userAnswer"\n'
        '\n'
        '━━ EVALUATION RULES ━━\n'
        '✓ Be warm, direct, and concise\n'
        '✓ One result line + 1-2 lines of feedback\n'
        '✗ Never repeat the full definition if already correct\n'
        '✗ Never use markdown bold (**) or bullet points\n'
        '\n'
        '━━ FORMAT (use EXACTLY one of these, then feedback on next line) ━━\n'
        '✅ Corretto — [what they got right in 1 sentence]\n'
        'OR\n'
        '⚠️ Parziale — [what is correct + the key missing element]\n'
        'OR\n'
        '❌ Incompleto — [what is missing + one specific hint to review]\n';
    }

    // Stream evaluation into the card
    String fullText = '';
    try {
      final stream = provider.askAtlasStream(evalPrompt, []);
      await stream
          .timeout(
            const Duration(seconds: 20),
            onTimeout: (sink) => sink.close(),
          )
          .forEach((chunk) {
            fullText += chunk;
            if (mounted) {
              final card = _atlasCards.where((c) => c.id == cardId).firstOrNull;
              if (card != null) setState(() => card.text = fullText);
            }
          });
    } catch (e) {
      if (mounted) {
        final card = _atlasCards.where((c) => c.id == cardId).firstOrNull;
        if (card != null) setState(() => card.text = '🔌 Connessione interrotta — riprova');
      }
      return;
    }

    // Parse result, update SR schedule, record fail mode for adaptive selection
    final result = fullText.trimLeft();
    final now = DateTime.now();
    // 🧠 FSRS: Use adaptive scheduler instead of hardcoded intervals
    final existingCard = _reviewSchedule[concept] ?? SrsCardData.newCard();
    if (isConfidence) {
      // Confidence mode: SR based on level directly (no emoji parsing)
      final level = int.tryParse(mode.split('_').last) ?? 0;
      final quality = level == 0 ? 0 : 1; // 0 = "non ricordo", -1 = "ho dubbi"
      final confidence = level == 0 ? 2 : 3;
      _reviewSchedule[concept] = FsrsScheduler.review(existingCard, quality: quality, confidence: confidence);
      _conceptFailHistory[concept] = mode;
    } else if (result.startsWith('✅')) {
      _reviewSchedule[concept] = FsrsScheduler.review(existingCard, quality: 2, confidence: 3);
      _conceptFailHistory.remove(concept);
    } else if (result.startsWith('💡') || result.startsWith('⚠️')) {
      _reviewSchedule[concept] = FsrsScheduler.review(existingCard, quality: 1, confidence: 3);
      _conceptFailHistory[concept] = mode;
    } else if (result.startsWith('📖') || result.startsWith('❌')) {
      _reviewSchedule[concept] = FsrsScheduler.review(existingCard, quality: 0, confidence: 3);
      _conceptFailHistory[concept] = mode;
    } else {
      _reviewSchedule[concept] = FsrsScheduler.review(existingCard, quality: 0, confidence: 3);
      _conceptFailHistory[concept] = mode;
    }
    _saveSpacedRepetition();

    // Cap _conceptFailHistory to 30 entries max
    if (_conceptFailHistory.length > 30) {
      final overflow = _conceptFailHistory.length - 30;
      final keysToRemove = _conceptFailHistory.keys.take(overflow).toList();
      for (final k in keysToRemove) { _conceptFailHistory.remove(k); }
    }



    // 📊 Metacognitive calibration: compare self-rating vs actual outcome
    final card = _atlasCards.where((c) => c.id == cardId).firstOrNull;
    if (card?.selfRating != null) {
      _recordCalibration(concept, card!.selfRating!, result);
    }
  }

  // ── CLUSTER NAVIGATION ($$ Ripasso jump) ────────────────────────────

  /// Pan the canvas so [clusterId]'s centroid is centered on screen.
  /// Uses a 300ms animated offset update.
  void _navigateToCluster(String clusterId) {
    final cluster = _clusterById(clusterId);
    if (cluster == null) return;
    HapticFeedback.mediumImpact();

    // Convert canvas centroid to the offset needed to center it on screen
    final screenSize = MediaQuery.sizeOf(context);
    final scale = _canvasController.scale;
    // New offset: center cluster on screen
    final targetOffset = Offset(
      screenSize.width / 2 - cluster.centroid.dx * scale,
      screenSize.height / 2 - cluster.centroid.dy * scale,
    );
    // Animate using ticker (simple lerp via repeated setState)
    _animatePanTo(targetOffset);
  }

  void _animatePanTo(Offset target) {
    const steps = 20;
    const stepDuration = Duration(milliseconds: 15);
    int step = 0;
    final start = _canvasController.offset;
    Timer.periodic(stepDuration, (t) {
      step++;
      final progress = step / steps;
      final eased = Curves.easeInOut.transform(progress.clamp(0.0, 1.0));
      final current = Offset.lerp(start, target, eased)!;
      _canvasController.setOffset(current);
      if (mounted) setState(() {});
      if (step >= steps) t.cancel();
    });
  }

  // ── PRE-LETTURA (Carpenter 2011) ───────────────────────────────────

  /// Generates 3 priming questions from the cluster before the user reads.
  /// Activates top-down attention: user reads WITH questions in mind.
  Future<void> _generatePreLettura(String srcClusterId) async {
    if (!mounted) return;
    final provider = EngineScope.current.atlasProvider;
    if (!provider.isInitialized) await provider.initialize();

    final cluster =
        _clusterById(srcClusterId);
    final clusterCtx = (_clusterTextCache[srcClusterId] ?? '').trim();
    final screenPos =
        cluster != null
            ? _canvasController
                .canvasToScreen(cluster.centroid)
                .translate(0, -80)
            : Offset(MediaQuery.sizeOf(context).width / 2 - 140, 100);

    final cardId =
        'preread_${srcClusterId}_${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      _atlasCards.add(
        _AtlasCardEntry(
          id: cardId,
          text: '❓ Generando domande di pre-lettura…',
          position: screenPos,
        ),
      );
    });

    final entry = _proactiveCache[srcClusterId];
    final gaps = entry?.gaps.take(4).join(', ') ?? '';
    final ctx =
        clusterCtx.length > 200
            ? clusterCtx.substring(0, 198) + '…'
            : clusterCtx;

    final prompt =
        '$_nativeLangInstruction\n'
        'LANGUAGE RULE: You MUST respond ENTIRELY in the same language as the instruction above. Never switch to English.\n'
        '\n'
        'You are ATLAS using PRE-QUESTIONING (Carpenter 2011) to activate focused reading.\n'
        '\n'
        'CLUSTER CONTENT: "$ctx"\n'
        'KEY CONCEPTS: $gaps\n'
        '\n'
        '━━ GENERATE exactly 3 PRE-READING QUESTIONS ━━\n'
        'These questions PRIME the reader attention — she will read looking for answers.\n'
        '✓ Each starts with: Cosa / Come / Perché / Qual è / In che modo\n'
        '✓ Open-ended (no yes/no)\n'
        '✓ Based on the actual content above (not generic)\n'
        '✗ Do NOT give answers\n'
        '\n'
        'Format:\n'
        '❓ PRE-LETTURA\n'
        '1. [question]\n'
        '2. [question]\n'
        '3. [question]\n'
        '\n'
        'Rules: max 80 words total, no markdown bold.';

    String fullText = '';
    try {
      final stream = provider.askAtlasStream(prompt, []);
      await stream
          .timeout(
            const Duration(seconds: 20),
            onTimeout: (sink) => sink.close(),
          )
          .forEach((chunk) {
            fullText += chunk;
            if (mounted) {
              final card = _atlasCards.where((c) => c.id == cardId).firstOrNull;
              if (card != null) setState(() => card.text = fullText);
            }
          });
    } catch (e) {
      if (mounted) {
        final card = _atlasCards.where((c) => c.id == cardId).firstOrNull;
        if (card != null) setState(() => card.text = '⚠️ $e');
      }
    }
  }

  // ── CLUSTER HIDE (Retrieval Practice puro) ─────────────────────────

  /// Hides the cluster's content so the user must recall from memory.

  void _clusterHide(String srcClusterId) {
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    setState(() => _hiddenClusters.add(srcClusterId));


    // Show a card prompting the user to recall
    final cluster = _clusterById(srcClusterId);
    final screenPos = cluster != null
        ? _canvasController.canvasToScreen(cluster.centroid).translate(0, -60)
        : Offset(MediaQuery.sizeOf(context).width / 2 - 140, 100);

    final entry = _proactiveCache[srcClusterId];
    final gaps = entry?.gaps.take(4).join(', ') ?? 'i concetti';
    final cardId = 'hide_${srcClusterId}_${DateTime.now().microsecondsSinceEpoch}';

    setState(() {
      _atlasCards.add(_AtlasCardEntry(
        id: cardId,
        text: '🙈 NASCONDI E RICORDA\n\n'
            'Ho nascosto il cluster. Prova a ricordare:\n'
            '→ $gaps\n\n'
            'Quando sei pronto, tap "Rivela" per verificare.',
        position: screenPos,
        sourceClusterId: srcClusterId,
      ));
    });

    // Auto-reveal after 60s
    Timer(const Duration(seconds: 60), () {
      if (mounted && _hiddenClusters.contains(srcClusterId)) {
        _revealCluster(srcClusterId);
      }
    });
  }

  void _revealCluster(String clusterId) {
    if (!mounted) return;
    setState(() => _hiddenClusters.remove(clusterId));
    HapticFeedback.lightImpact();

  }

  // ── FEYNMAN MODE (Feynman Technique + Generation Effect) ──────────

  /// Opens a Feynman-technique card: user must explain [concept] simply,
  /// then Atlas evaluates clarity and identifies gaps in the explanation.
  Future<void> _feynmanMode(String concept, String srcClusterId) async {
    if (!mounted) return;
    HapticFeedback.mediumImpact();

    final cluster = _clusterById(srcClusterId);
    final screenPos = cluster != null
        ? _canvasController.canvasToScreen(cluster.centroid).translate(0, -80)
        : Offset(MediaQuery.sizeOf(context).width / 2 - 140, 100);

    // Open a verify card — user writes their Feynman explanation,
    // then submits for Atlas evaluation via the existing verify flow
    final cardId = 'feynman_${srcClusterId}_${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      _atlasCards.add(_AtlasCardEntry(
        id: cardId,
        text: '🧑‍🏫 FEYNMAN MODE\n\n'
            'Spiega "$concept" come a un bambino di 5 anni.\n'
            'Usa parole semplici, esempi concreti, analogie.\n\n'
            'Scrivi sotto e premi Invia per il feedback Atlas.',
        position: screenPos,
        verifyQuestion: concept,
        sourceClusterId: srcClusterId,
        showSelfRating: true,
        gapChips: [concept],
      ));
    });
  }

  /// Feynman evaluation prompt — used when verify submit detects a Feynman card.
  String _buildFeynmanEvalPrompt(String concept, String answer, String clusterCtx) {
    return '$_nativeLangInstruction\n'
        'LANGUAGE RULE: You MUST respond ENTIRELY in the same language as the instruction above. Never switch to English.\n\n'
        'You are ATLAS using the FEYNMAN TECHNIQUE to evaluate understanding.\n\n'
        'CONCEPT: "$concept"\n'
        'STUDENT EXPLANATION: "$answer"\n'
        'REFERENCE CONTENT: "$clusterCtx"\n\n'
        '━━ EVALUATE ━━\n'
        '1. Is the explanation SIMPLE enough for a 5-year-old? (Yes/No + why)\n'
        '2. Are there GAPS or ERRORS in understanding?\n'
        '3. Rate: ✅ Ottimo / 💡 Quasi ci sei / 📖 Rivedi i punti chiave\n\n'
        '━━ IMPROVED EXPLANATION ━━\n'
        'Rewrite their explanation with corrections, keeping it simple.\n\n'
        'Max 100 words. No markdown bold.';
  }

  // ── METACOGNITIVE CALIBRATION (Dunning-Kruger awareness) ──────────

  /// Tracks the delta between self-rating and actual verify outcome.

  void _recordCalibration(String concept, int selfRating, String verifyResult) {
    // selfRating: -1=non lo so, 0=ho dubbi, 1=lo so già
    // verifyResult: '✅', '⚠️', '❌'
    final verifyScore = verifyResult.startsWith('✅') ? 1
                      : verifyResult.startsWith('⚠️') ? 0
                      : -1;

    final delta = selfRating - verifyScore; // positive = overconfident
    _calibrationLog[concept] = {
      'selfRating': selfRating,
      'verifyScore': verifyScore,
      'delta': delta,
      'timestamp': DateTime.now().toIso8601String(),
    };

    // Check if user is consistently overconfident
    final recent = _calibrationLog.values.toList();
    if (recent.length >= 3) {
      final lastThree = recent.skip(recent.length - 3).toList();
      final avgDelta = lastThree.map((e) => (e['delta'] as int)).reduce((a, b) => a + b) / 3;
      if (avgDelta > 0.5) {
      } else if (avgDelta < -0.5) {
      }
    }



    // Cap calibration log at 50 entries
    if (_calibrationLog.length > 50) {
      final overflow = _calibrationLog.length - 50;
      final keys = _calibrationLog.keys.take(overflow).toList();
      for (final k in keys) { _calibrationLog.remove(k); }
    }
  }

  // ── STEM EXERCISES (Problem-Based Learning) ───────────────────────

  /// Generates a STEM practice exercise from the cluster content.
  /// Atlas detects formulas/concepts and creates a problem with hidden solution.
  Future<void> _generateStemExercise(String srcClusterId) async {
    if (!mounted) return;
    final provider = EngineScope.current.atlasProvider;
    if (!provider.isInitialized) await provider.initialize();

    final cluster = _clusterById(srcClusterId);
    final clusterCtx = (_clusterTextCache[srcClusterId] ?? '').trim();
    final screenPos = cluster != null
        ? _canvasController.canvasToScreen(cluster.centroid).translate(0, -80)
        : Offset(MediaQuery.sizeOf(context).width / 2 - 140, 100);

    final cardId = 'stem_${srcClusterId}_${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      _atlasCards.add(_AtlasCardEntry(
        id: cardId,
        text: '🧪 Generando esercizio STEM…',
        position: screenPos,
        sourceClusterId: srcClusterId,
      ));
    });

    final entry = _proactiveCache[srcClusterId];
    final gaps = entry?.gaps.take(4).join(', ') ?? '';
    final ctx = clusterCtx.length > 300 ? '${clusterCtx.substring(0, 298)}…' : clusterCtx;

    final prompt = '''
$_nativeLangInstruction
LANGUAGE RULE: You MUST respond ENTIRELY in the same language as the instruction above. Never switch to English.

You are ATLAS generating a PRACTICE EXERCISE for Problem-Based Learning.

CLUSTER CONTENT: "$ctx"
KEY CONCEPTS: $gaps

━━ GENERATE 1 STEM EXERCISE ━━
Analyze the content and create an appropriate exercise:
• Math/Physics → calculation or derivation problem
• Chemistry → balancing, stoichiometry, or mechanism question
• Biology → labeling, process ordering, or comparison
• CS → algorithm trace, code output prediction, or complexity
• If NOT STEM → create an analytical question requiring structured reasoning

FORMAT:
🧪 ESERCIZIO
[Problem statement — clear, specific, solvable]

📝 DATI / HINT
[Given values or helpful hints]

🔑 SOLUZIONE (prova prima!)
[Step-by-step solution with final answer]

Rules: use the actual formulas/data from the content. Max 150 words. No markdown bold.
''';

    String fullText = '';
    try {
      final stream = provider.askAtlasStream(prompt, []);
      await stream
          .timeout(const Duration(seconds: 25), onTimeout: (sink) => sink.close())
          .forEach((chunk) {
            fullText += chunk;
            if (mounted) {
              final card = _atlasCards.where((c) => c.id == cardId).firstOrNull;
              if (card != null) setState(() => card.text = fullText);
            }
          });
    } catch (e) {
      if (mounted) {
        final card = _atlasCards.where((c) => c.id == cardId).firstOrNull;
        if (card != null) setState(() => card.text = '🔌 Connessione interrotta — riprova');
      }
    }
  }

  // ── GAP CHIP: EXPLAIN MODE ────────────────────────────────────────────

  /// Called when user taps a gap chip in the Atlas card.
  /// [socraticMode] = true when user rated "Non lo so" → shows a Socratic question first.
  /// Opens a new Atlas explanation or Socratic card. No canvas node created.
  void _createNodeFromGap(
    String concept,
    String sourceClusterId, {
    bool socraticMode = false,
  }) {
    HapticFeedback.mediumImpact();

    // Find the source cluster's OCR text for context
    final source =
        _clusterById(sourceClusterId);
    final sourceText =
        source != null ? (_clusterTextCache[source.id] ?? '').trim() : '';

    // Gather nearby cluster texts as study context
    final studyContext =
        source != null
            ? _clusterCache
                .where(
                  (c) =>
                      c.id != sourceClusterId &&
                      (c.centroid - source.centroid).distance < 600,
                )
                .map((c) => _clusterTextCache[c.id] ?? '')
                .where((t) => t.trim().isNotEmpty)
                .take(6)
                .join(', ')
            : '';

    // Use concept name as language anchor (e.g. "Primitive" → Italian, "DNA" → any)
    final contextClue = sourceText.isNotEmpty ? sourceText : concept;
    final ctxNote = studyContext.isNotEmpty ? ' (contesto: $studyContext)' : '';

    final String prompt;
    if (socraticMode) {
      // 🟡 Ho dubbi → Socratic question
      prompt =
          '$_nativeLangInstruction\n'
          'LANGUAGE RULE: You MUST respond ENTIRELY in the same language as the instruction above. Never switch to English.\n'
          'NEVER use English if the concept is Italian/Spanish/French/etc.\n'
          '\n'
          'You are a Socratic tutor.\n'
          'Topic: "$contextClue"$ctxNote\n'
          '\n'
          '━━ TASK ━━\n'
          'Ask ONE short, sharp question that makes the student think about "$concept" without giving the answer.\n'
          '\n'
          '━━ RULES ━━\n'
          '✗ No introductions ("Come sai...", "Certo!")\n'
          '✗ No answers in the question\n'
          '\n'
          '━━ EXAMPLES ━━\n'
          'Concept: "Teorema fondamentale del calcolo" → "Se derivi ∫₀ˣ f(t)dt, cosa ottieni?"\n'
          'Concept: "Principio di inerzia" → "Perché un\'astronauta nello spazio continua a muoversi senza spingere?"\n'
          '\n'
          'Now: concept="$concept"';
    } else {
      // 🔴 Non lo so → direct concise explanation
      prompt =
          '$_nativeLangInstruction\n'
          'LANGUAGE RULE: You MUST respond ENTIRELY in the same language as the instruction above. Never switch to English.\n'
          'NEVER use English if the concept is Italian/Spanish/French/etc.\n'
          '\n'
          'You are ATLAS, expert academic tutor.\n'
          'Topic: "$contextClue"$ctxNote\n'
          '\n'
          '━━ OUTPUT FORMAT ━━\n'
          'Se il concetto ha una formula chiave: inizia con essa su una riga.\n'
          'Poi: 2-3 frasi di spiegazione chiara e precisa.\n'
          'Poi: un esempio concreto legato al contesto "$contextClue".\n'
          '\n'
          '━━ RULES ━━\n'
          '✗ No intro ("Certo!", "Ottima domanda!")\n'
          '✗ No padding — ogni frase deve aggiungere informazione\n'
          '✗ Non iniziare con il nome del concetto — vai diretto al contenuto\n'
          '\n'
          '━━ EXAMPLES ━━\n'
          'Concept: "\u222ff(x)dx = F(b)-F(a)"\n'
          '\u22121 frase (formula): \u222b\u00e2\u0081\u00b0\u1d47 f(x)dx = F(b)\u2212F(a)\n'
          '\u22122-3 frasi: "Il Teorema fondamentale collega derivazione e integrazione. Per calcolare l\'integrale definito basta trovare una primitiva F di f e valutarla negli estremi: F(b)\u2212F(a)."\n'
          '\u22121 esempio: "Esempio: per \u222b\u00e2\u0081\u00b0\u00b2 x dx, F(x)=x\u00b2/2, quindi F(2)\u2212F(0) = 2."\n'
          '\n'
          'Concept: "Somme di Riemann"\n'
          '\u22122-3 frasi: "Le somme di Riemann approssimano l\'area sotto una curva dividendo l\'intervallo in n rettangoli. Per n\u2192\u221e la somma converge all\'integrale definito."\n'
          '\u22121 esempio: "Esempio: per f(x)=x\u00b2 in [0,1] con 4 rettangoli, si approssima l\'area come 0.25\u00b2+0.5\u00b2+0.75\u00b2+1\u00b2 \u00d7 0.25 \u2248 0.47."\n'
          '\n'
          'Now: concept="$concept"';
    }

    // Position card near the source cluster on screen
    final screenPos =
        source != null
            ? _canvasController
                .canvasToScreen(source.centroid)
                .translate(20, -80)
            : const Offset(80, 200);

    // Dismiss the previous explanation card if any (prevent stacking)
    final prevId = _activeExplainCardId;
    if (prevId != null) {
      setState(() => _atlasCards.removeWhere((c) => c.id == prevId));
    }

    // Stream the explanation into a new Atlas card
    final cardId = 'gap_explain_${DateTime.now().microsecondsSinceEpoch}';
    _activeExplainCardId = cardId;
    _addCard(cardId, '', screenPos);
    _streamExplanationIntoCard(
      cardId,
      prompt,
      screenPos,
      prefix: '**$concept**\n\n',
    );
  }

  /// Streams an Atlas explanation into an existing card (updates text progressively).
  Future<void> _streamExplanationIntoCard(
    String cardId,
    String prompt,
    Offset position, {
    String prefix = '',
  }) async {
    try {
      final provider = EngineScope.current.atlasProvider;
      if (!provider.isInitialized) await provider.initialize();

      final buffer = StringBuffer();
      if (prefix.isNotEmpty) {
        buffer.write(prefix);
        if (mounted) _updateCardText(cardId, buffer.toString());
      }
      final stream = provider.askAtlasStream(prompt, []);
      await stream
          .timeout(
            const Duration(seconds: 20),
            onTimeout: (sink) => sink.close(),
          )
          .forEach((chunk) {
            buffer.write(chunk);
            // Update card text progressively (streaming feel)
            if (mounted) {
              _updateCardText(cardId, buffer.toString().trim());
            }
          });
    } catch (e) {
      if (mounted) _updateCardText(cardId, '⚠️ Errore: $e');
    }
  }

  // ── SESSION SUMMARY ─────────────────────────────────────────────────────

  /// Shows an Atlas card summarizing what was studied this session.
  void _showSessionSummary() {
    if (_sessionExplored.isEmpty && _sessionMastered.isEmpty) return;

    final lang = _deviceLanguageName;
    final explored = _sessionExplored.toSet(); // deduplicated
    final due =
        _reviewSchedule.entries
            .where(
              (e) =>
                  e.value.nextReview.isBefore(DateTime.now().add(const Duration(days: 2))),
            )
            .map((e) => e.key)
            .take(5)
            .toList();

    final summary = StringBuffer();
    summary.writeln('📊 **Riepilogo sessione**\n');
    if (explored.isNotEmpty) {
      summary.writeln('✅ Esplorati (${explored.length}):');
      for (final c in explored.take(8)) {
        summary.writeln('  • $c');
      }
    }
    if (_sessionMastered.isNotEmpty) {
      summary.writeln('\n🟢 Già noti (${_sessionMastered.length}):');
      for (final c in _sessionMastered.take(5)) {
        summary.writeln('  • $c');
      }
    }
    if (due.isNotEmpty) {
      summary.writeln('\n⏰ Da rivedere domani:');
      for (final c in due) {
        summary.writeln('  • $c');
      }
    }

    final pos = Offset(
      MediaQuery.sizeOf(context as BuildContext? ?? context).width / 2 - 100,
      120,
    );
    _addCard(
      'session_summary_${DateTime.now().millisecondsSinceEpoch}',
      summary.toString().trim(),
      pos,
    );
    if (mounted) setState(() {});
  }

  // ── STUDY DASHBOARD (Metacognitive self-regulation) ────────────────

  /// Shows a comprehensive study dashboard card with SR stats, accuracy,
  /// calibration delta, and upcoming reviews.
  void _showStudyDashboard() {
    if (!mounted) return;
    HapticFeedback.mediumImpact();

    final now = DateTime.now();
    final totalConcepts = _proactiveCache.values
        .expand((e) => e.gaps)
        .toSet()
        .length;
    final mastered = _sessionMastered.length;
    final dueCount = _reviewSchedule.entries
        .where((e) => e.value.nextReview.isBefore(now))
        .length;
    final scheduledCount = _reviewSchedule.length;

    // Calibration accuracy
    String calibrationNote = '';
    if (_calibrationLog.isNotEmpty) {
      final deltas = _calibrationLog.values
          .map((e) => (e['delta'] as int?) ?? 0)
          .toList();
      final avg = deltas.reduce((a, b) => a + b) / deltas.length;
      if (avg > 0.3) {
        calibrationNote = '📈 Tendi a sentirti più sicuro del previsto (Δ=${avg.toStringAsFixed(1)})';
      } else if (avg < -0.3) {
        calibrationNote = '📉 Sai più di quanto pensi! (Δ=${avg.toStringAsFixed(1)})';
      } else {
        calibrationNote = '✅ Calibrazione accurata (Δ=${avg.toStringAsFixed(1)})';
      }
    }

    // Next review
    String nextReview = '';
    if (_reviewSchedule.isNotEmpty) {
      final sorted = _reviewSchedule.entries.toList()
        ..sort((a, b) => a.value.nextReview.compareTo(b.value.nextReview));
      final next = sorted.first;
      final diff = next.value.nextReview.difference(now);
      final when = diff.isNegative ? 'ORA' : diff.inHours < 1
          ? '${diff.inMinutes}min'
          : '${diff.inHours}h';
      nextReview = '\n⏰ Prossima: "${next.key}" → $when';
    }

    // Progress bar helper
    String bar(int filled, int total, {int width = 10}) {
      if (total == 0) return '░' * width;
      final pct = (filled / total).clamp(0.0, 1.0);
      final full = (pct * width).round();
      return '█' * full + '░' * (width - full);
    }

    final pctMastered = totalConcepts > 0
        ? (mastered / totalConcepts * 100).round()
        : 0;

    final dashboard = '📊 I TUOI PROGRESSI\n\n'
        '✅ Concetti padroneggiati: $mastered/$totalConcepts [$pctMastered%]\n'
        '   ${bar(mastered, totalConcepts)}\n\n'
        '📅 Concetti in ripasso: $scheduledCount\n'
        '🔔 Da ripassare oggi: $dueCount\n'
        '   ${bar(scheduledCount - dueCount, scheduledCount)}\n'
        '${calibrationNote.isNotEmpty ? '\n$calibrationNote' : ''}'
        '$nextReview';

    final pos = Offset(MediaQuery.sizeOf(context).width / 2 - 140, 100);
    final cardId = 'dashboard_${now.microsecondsSinceEpoch}';
    setState(() {
      _atlasCards.add(_AtlasCardEntry(
        id: cardId,
        text: dashboard,
        position: pos,
      ));
    });
  }

  // ── SR NOTIFICATIONS (External scaffolding) ───────────────────────

  /// Schedules native notifications for all concepts due for review.
  /// Debounced: waits 5s after last call to avoid excessive scheduling.
  Future<void> _scheduleReviewNotifications() async {
    _srNotifDebounce?.cancel();
    _srNotifDebounce = Timer(const Duration(seconds: 5), () async {
    try {
      // Cancel old review group
      await NativeNotifications.cancelGroup('sr_review');

      final now = DateTime.now();
      int scheduled = 0;

      for (final entry in _reviewSchedule.entries) {
        final concept = entry.key;
        final reviewAt = entry.value.nextReview;

        // Only schedule future reviews (not already past)
        if (reviewAt.isAfter(now)) {
          await NativeNotifications.schedule(
            FNotification(
              id: 'sr_${concept.hashCode}',
              title: '📅 Review: $concept',
              body: 'Time to review this concept. Open your canvas!',
              style: FNotificationStyle.bigText,
              priority: FNotificationPriority.high,
              category: FNotificationCategory.reviewSession,
              groupKey: 'sr_review',
              data: {'concept': concept},
              actions: [
                FNotificationAction(id: 'review_now', label: 'Review now', openApp: true),
                FNotificationAction(id: 'snooze_1h', label: 'In 1h', openApp: false),
              ],
            ),
            reviewAt,
          );
          scheduled++;
        }
      }

      if (scheduled > 0) {
        debugPrint('🔔 Scheduled $scheduled SR review notifications');
      }
    } catch (e) {
      debugPrint('⚠️ SR notification error: $e');
    }
    });
  }

  // ── NOTIFICATION TAP HANDLER ──────────────────────────────────────

  /// Sets up a listener for notification tap events.
  /// Call this once during canvas init.
  void _setupNotificationTapHandler() {
    _notifSub?.cancel();
    _notifSub = NativeNotifications.onNotificationTapped.listen((event) {
      if (!mounted) return;
      debugPrint('🔔 Notification tapped: ${event.notificationId}, action: ${event.actionId}');

      final concept = event.data?['concept'];
      if (concept == null) return;

      if (event.actionId == 'review_now' || event.actionId == null) {
        // Open a verify card for the concept
        HapticFeedback.mediumImpact();
        final pos = Offset(MediaQuery.sizeOf(context).width / 2 - 130, 100);
        final cardId = 'notif_review_${DateTime.now().microsecondsSinceEpoch}';
        setState(() {
          _atlasCards.add(_AtlasCardEntry(
            id: cardId,
            text: '🔔 SCHEDULED REVIEW\n\n'
                'Time to review: "$concept"',
            position: pos,
            verifyQuestion: concept,
            showSelfRating: true,
            gapChips: [concept],
          ));
        });
      } else if (event.actionId == 'snooze_1h') {
        // Snooze the review by 1 hour
        final existing = _reviewSchedule[concept] ?? SrsCardData.newCard();
        _reviewSchedule[concept] = SrsCardData(
          stability: existing.stability,
          difficulty: existing.difficulty,
          elapsedDays: existing.elapsedDays,
          scheduledDays: existing.scheduledDays,
          reps: existing.reps,
          lapses: existing.lapses,
          state: existing.state,
          nextReview: DateTime.now().add(const Duration(hours: 1)),
          lastReview: existing.lastReview,
          desiredRetention: existing.desiredRetention,
          recentResults: existing.recentResults,
        );
        _saveSpacedRepetition();
        debugPrint('⏰ Snoozed "$concept" for 1h');
      }
    });
  }

  void _disposeNotificationHandler() {
    _notifSub?.cancel();
    _notifSub = null;
  }

  // ── INTERLEAVED VERIFY (Rohrer & Taylor 2007) ─────────────────────

  /// Opens a verify card with concepts from ALL clusters, sorted by SR urgency.
  /// Interleaving across topics strengthens discrimination and long-term retention.
  void _openInterleavedVerify() {
    if (!mounted) return;
    HapticFeedback.mediumImpact();

    // Collect all unmastered concepts across all clusters (O(1) Set lookup)
    final seen = <String>{};
    final allConcepts = <String>[];
    for (final entry in _proactiveCache.entries) {
      for (final gap in entry.value.gaps) {
        if (!_sessionMastered.contains(gap) && seen.add(gap)) {
          allConcepts.add(gap);
        }
      }
    }

    if (allConcepts.isEmpty) return;

    // Sort by SR urgency: due concepts first, then by next review date
    final now = DateTime.now();
    allConcepts.sort((a, b) {
      final aDate = _reviewSchedule[a]?.nextReview ?? now.add(const Duration(days: 30));
      final bDate = _reviewSchedule[b]?.nextReview ?? now.add(const Duration(days: 30));
      return aDate.compareTo(bDate);
    });

    final pos = Offset(MediaQuery.sizeOf(context).width / 2 - 130, 100);
    final cardId = 'interleave_${now.microsecondsSinceEpoch}';

    setState(() {
      _atlasCards.add(_AtlasCardEntry(
        id: cardId,
        text: '🔀 INTERLEAVING\n\nConcetti da cluster diversi — scegli quale verificare:',
        position: pos,
        verifyQuestion: null, // null = show picker
        showSelfRating: true,
        gapChips: allConcepts.take(8).toList(),
      ));
    });

    debugPrint('🔀 Interleaved verify: ${allConcepts.length} concepts from ${_proactiveCache.length} clusters');
  }

  // ── EXPORT STUDY DATA (Self-regulation portfolio) ─────────────────

  /// Exports all learning data as formatted JSON to clipboard.
  Future<void> _exportStudyData() async {
    if (!mounted) return;
    HapticFeedback.mediumImpact();

    final data = {
      'exportedAt': DateTime.now().toIso8601String(),
      'spacedRepetition': {
        for (final e in _reviewSchedule.entries)
          e.key: e.value.toJson(),
      },
      'sessionMastered': _sessionMastered.toList(),
      'sessionExplored': _sessionExplored.toList(),
      'conceptFailHistory': _conceptFailHistory,
      'calibration': _calibrationLog,
      'totalClustersAnalyzed': _proactiveCache.length,
      'totalConceptsFound': _proactiveCache.values
          .expand((e) => e.gaps)
          .toSet()
          .length,
    };

    final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
    await Clipboard.setData(ClipboardData(text: jsonStr));

    // Show confirmation card
    final pos = Offset(MediaQuery.sizeOf(context).width / 2 - 140, 120);
    final cardId = 'export_${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      _atlasCards.add(_AtlasCardEntry(
        id: cardId,
        text: '📋 DATI ESPORTATI\n\n'
            'Copiato negli appunti!\n\n'
            '• ${_reviewSchedule.length} concetti SR\n'
            '• ${_sessionMastered.length} padroneggiati\n'
            '• ${_calibrationLog.length} calibrazioni\n\n'
            'Incolla in un editor per vedere il JSON completo.',
        position: pos,
      ));
    });

    debugPrint('📋 Study data exported: ${jsonStr.length} chars');
  }

  // ── CLEANUP ───────────────────────────────────────────────────────────

  void _disposeProactiveAnalysis() {
    _proactiveDebounceTimer?.cancel();
  }

  // ── SPACED REPETITION PERSISTENCE ────────────────────────────────────

  /// SR key scoped to the current canvas document.
  String get _srKey => 'proactive_sr_$_canvasId';

  /// Stats key scoped to the current canvas document.
  String get _statsKey => 'proactive_stats_$_canvasId';

  /// Seen clusters key — persists dismissed dot IDs across sessions.
  String get _seenKey => 'proactive_seen_$_canvasId';

  /// Load spaced repetition schedule from disk into [_reviewSchedule].
  /// Call this during canvas init.
  Future<void> _loadSpacedRepetition() async {
    try {
      final kv = await KeyValueStore.getInstance();
      final raw = kv.getString(_srKey);
      if (raw == null || raw.isEmpty) return;
      final map = (jsonDecode(raw) as Map<String, dynamic>);
      // 🧠 FSRS migration: detect old format (int epoch) vs new (SrsCardData JSON)
      final migrated = FsrsScheduler.migrateLegacySchedule(map);
      _reviewSchedule.addAll(migrated);
      debugPrint('📅 SR loaded: ${_reviewSchedule.length} concepts scheduled (FSRS)');
    } catch (e) {
      debugPrint('⚠️ SR load error: $e');
    }
  }

  /// Load seen cluster IDs from disk → pre-populate _proactiveCache with 'seen' status.
  Future<void> _loadSeenClusters() async {
    try {
      final kv = await KeyValueStore.getInstance();
      final raw = kv.getString(_seenKey);
      if (raw == null || raw.isEmpty) return;
      final ids = (jsonDecode(raw) as List<dynamic>).cast<String>();
      for (final id in ids) {
        _proactiveCache[id] = ProactiveAnalysisEntry(
          clusterId: id,
          status: ProactiveStatus.seen,
          gaps: [],
        );
      }
      debugPrint('👁️ Loaded ${ids.length} seen clusters');
    } catch (e) {
      debugPrint('⚠️ Seen clusters load error: $e');
    }
  }

  /// Persist seen cluster IDs to disk.
  Future<void> _saveSeenClusters() async {
    try {
      final kv = await KeyValueStore.getInstance();
      final seenIds = _proactiveCache.entries
          .where((e) => e.value.status == ProactiveStatus.seen)
          .map((e) => e.key)
          .toList();
      await kv.setString(_seenKey, jsonEncode(seenIds));
    } catch (e) {
      debugPrint('⚠️ Seen clusters save error: $e');
    }
  }

  /// Persist the current [_reviewSchedule] to disk (FSRS format).
  Future<void> _saveSpacedRepetition() async {
    try {
      final kv = await KeyValueStore.getInstance();
      final map = {
        for (final e in _reviewSchedule.entries)
          e.key: e.value.toJson(),
      };
      await kv.setString(_srKey, jsonEncode(map));
      // Also persist calibration log
      if (_calibrationLog.isNotEmpty) {
        await kv.setString(
          'fluera_calibration_$_canvasId',
          jsonEncode(_calibrationLog),
        );
      }
      // Schedule native notifications for upcoming reviews
      _scheduleReviewNotifications();
    } catch (e) {
      debugPrint('⚠️ SR save error: $e');
    }
  }

  /// 🚦 KV key for step gate history, scoped per canvas.
  String get _stepGateKey => 'step_gate_$_canvasId';

  /// Load step gate history from KeyValueStore into [_stepGateController].
  Future<void> _loadStepGateHistory() async {
    try {
      final kv = await KeyValueStore.getInstance();
      final raw = kv.getString(_stepGateKey);
      if (raw == null || raw.isEmpty) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _stepGateController = StepGateController.fromJson(json);
      debugPrint('🚦 Step gate: loaded ${_stepGateController.stepHistory.length} step records');
    } catch (e) {
      debugPrint('⚠️ Step gate load error: $e');
    }
  }

  /// Persist step gate history to KeyValueStore.
  Future<void> _saveStepGateHistory() async {
    try {
      final kv = await KeyValueStore.getInstance();
      await kv.setString(_stepGateKey, jsonEncode(_stepGateController.toJson()));
    } catch (e) {
      debugPrint('⚠️ Step gate save error: $e');
    }
  }

  /// 🚦 Build a [ZoneContext] from the current canvas state for gate evaluation.
  ZoneContext _buildZoneContext() {
    // Node count: total content clusters visible
    final nodeCount = _clusterCache.length;

    // Socratic questions answered
    final socraticAnswered = _socraticController.allQuestions
        .where((q) => q.isResolved)
        .length;

    // Last Step 1/2 timestamp
    final step1Record = _stepGateController.lastCompleted(LearningStep.step1Notes);
    final step2Record = _stepGateController.lastCompleted(LearningStep.step2Recall);
    DateTime? lastStep1Or2;
    if (step1Record != null && step2Record != null) {
      lastStep1Or2 = step1Record.isAfter(step2Record) ? step1Record : step2Record;
    } else {
      lastStep1Or2 = step1Record ?? step2Record;
    }

    // Due node count for SRS
    final dueCount = _reviewSchedule.entries
        .where((e) => e.value.nextReview.isBefore(DateTime.now()))
        .length;

    // Next review date
    DateTime? nextReview;
    if (_reviewSchedule.isNotEmpty) {
      final dates = _reviewSchedule.values.map((v) => v.nextReview).toList()
        ..sort();
      nextReview = dates.first;
    }

    // Stage ≥2 ratio for Fog of War gate
    double stageGte2Ratio = 0.0;
    if (_reviewSchedule.isNotEmpty) {
      final atStage2OrHigher = _reviewSchedule.values
          .where((card) => stageFromCard(card).index >= SrsStage.growing.index)
          .length;
      stageGte2Ratio = atStage2OrHigher / _reviewSchedule.length;
    }

    return ZoneContext(
      nodeCount: nodeCount,
      socraticQuestionsAnswered: socraticAnswered,
      lastStep1Or2: lastStep1Or2,
      hasInternet: true, // TODO: check connectivity when available
      dueNodeCount: dueCount,
      nextReviewDate: nextReview,
      zonesWithEnoughNodes: 0, // Deferred: cross-canvas metadata not available
      stageGte2Ratio: stageGte2Ratio,
    );
  }

  /// 🚦 Helper to check a step gate and show SnackBar if needed.
  ///
  /// Returns `true` if the step can proceed (either open, or soft gate
  /// already shown, or soft gate bypassed). Returns `false` if the step
  /// is hard-blocked.
  ///
  /// For soft gates, shows the SnackBar with "Procedi comunque" action
  /// that calls [onProceed] when tapped.
  bool _checkStepGate(LearningStep step, {VoidCallback? onProceed}) {
    final context = _buildZoneContext();
    final gate = _stepGateController.evaluateGate(step, context: context);

    switch (gate.type) {
      case StepGateType.open:
      case StepGateType.automatic:
        return true;

      case StepGateType.soft:
        // A15-02: Show only once per session.
        if (_stepGateController.wasGateShownThisSession(step)) {
          return true; // Already shown, let them proceed.
        }
        _stepGateController.markGateShown(step);

        if (mounted) {
          ScaffoldMessenger.of(this.context).showSnackBar(
            SnackBar(
              content: Text(gate.message!),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              margin: const EdgeInsets.only(bottom: 80, left: 20, right: 20),
              duration: const Duration(seconds: 5),
              backgroundColor: const Color(0xFFE65100),
              action: SnackBarAction(
                label: gate.proceedLabel!,
                textColor: Colors.white,
                onPressed: () {
                  onProceed?.call();
                },
              ),
            ),
          );
        }
        return false; // Don't proceed immediately — wait for bypass tap.

      case StepGateType.hard:
        if (mounted) {
          ScaffoldMessenger.of(this.context).showSnackBar(
            SnackBar(
              content: Text(gate.message!),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              margin: const EdgeInsets.only(bottom: 80, left: 20, right: 20),
              duration: const Duration(seconds: 4),
              backgroundColor: const Color(0xFF546E7A),
            ),
          );
        }
        return false; // Hard block — cannot proceed.
    }
  }

  /// Saves cumulative session stats to disk for cross-session progress tracking.
  Future<void> _saveSessionStats() async {
    try {
      final kv = await KeyValueStore.getInstance();
      // Load existing stats and accumulate
      final raw = kv.getString(_statsKey);
      final existing = raw != null ? (jsonDecode(raw) as Map<String, dynamic>) : <String, dynamic>{};
      final prevExplored = (existing['totalExplored'] as int?) ?? 0;
      final prevMastered = (existing['totalMastered'] as int?) ?? 0;
      final prevSessions = (existing['sessionCount'] as int?) ?? 0;
      final stats = {
        'totalExplored': prevExplored + _sessionExplored.length,
        'totalMastered': prevMastered + _sessionMastered.length,
        'sessionCount': prevSessions + 1,
        'lastSessionAt': DateTime.now().toIso8601String(),
      };
      await kv.setString(_statsKey, jsonEncode(stats));
    } catch (e) {
      debugPrint('⚠️ Stats save error: $e');
    }
  }

  // ── RIPASSO 24H (Ebbinghaus 1885 + Peterson 1959) ─────────────────────

  static const _sessionTsKey = 'fluera_last_session_ts';
  static const _ripassoShownKey = 'fluera_last_ripasso_shown_ts';

  /// Called on canvas open. Saves current timestamp, checks snooze window,
  /// and defers the review trigger 3.5s so proactive analysis has time to run.
  Future<void> _checkRipasso24h() async {
    final kv = await KeyValueStore.getInstance();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final lastMs = kv.getInt(_sessionTsKey);
    await kv.setInt(_sessionTsKey, nowMs);

    if (lastMs == null) return; // first ever session

    final elapsed = Duration(milliseconds: nowMs - lastMs);
    // Trigger only in the 2h–24h golden zone (Ebbinghaus)
    if (elapsed.inHours < 2 || elapsed.inHours > 24) return;

    // 🔕 Snooze: don’t re-trigger if already shown within the last 18h
    final lastShownMs = kv.getInt(_ripassoShownKey);
    if (lastShownMs != null) {
      final sinceShown = Duration(milliseconds: nowMs - lastShownMs);
      if (sinceShown.inHours < 18) return;
    }

    // ⏳ Wait 3.5s so proactive analysis has time to populate _proactiveCache
    await Future.delayed(const Duration(milliseconds: 3500));
    if (!mounted) return;

    // Primary: use live cache; Fallback: use persisted SR schedule
    final analysed =
        _proactiveCache.values
            .where(
              (e) =>
                  e.status == ProactiveStatus.seen ||
                  e.status == ProactiveStatus.ready ||
                  e.status == ProactiveStatus.dueForReview,
            )
            .toList();

    // If cache is empty but we have a SR schedule, build minimal entries from it
    List<ProactiveAnalysisEntry> candidates = analysed;
    if (candidates.length < 2 && _reviewSchedule.isNotEmpty) {
      // Synthesize one placeholder entry so the ripasso can fire
      candidates = [
        ProactiveAnalysisEntry(
          clusterId: 'sr_fallback',
          status: ProactiveStatus.dueForReview,
          gaps: _reviewSchedule.keys.take(6).toList(),
          scanText: 'Ripasso dai tuoi appunti precedenti',
        ),
      ];
    }
    if (candidates.isEmpty) return;

    debugPrint(
      '🔄 Ripasso 24h: ${elapsed.inHours}h gap — launching guided review',
    );
    // 🔕 Mark snooze timestamp so it won’t fire again today
    await kv.setInt(_ripassoShownKey, nowMs);
    if (mounted) _launchRipassoGuidato(candidates, elapsed);
  }

  /// Launches the 24h guided review with an accurate elapsed label and
  /// SR-tracking via the self-rating row.
  void _launchRipassoGuidato(
    List<ProactiveAnalysisEntry> entries,
    Duration elapsed,
  ) {
    if (!mounted) return;
    final screenSize = MediaQuery.sizeOf(context);
    final pos = Offset(screenSize.width / 2 - 135, 80);
    final cardId = 'ripasso24h_${DateTime.now().microsecondsSinceEpoch}';

    final allGaps =
        entries
            .expand((e) => e.gaps)
            .where((g) => !_sessionMastered.contains(g))
            .toSet()
            .take(6)
            .toList();

    final label = _elapsedLabel(elapsed);
    final intro =
        '🔄 RIPASSO — $label fa\n'
        'Perfetto per consolidare prima del dimenticatoio!\n\n'
        'Preparo le domande…';

    setState(() {
      _atlasCards.add(
        _AtlasCardEntry(
          id: cardId,
          text: intro,
          position: pos,
          gapChips: allGaps,
          showSelfRating: true, // ★ enables SR-tracking chips
        ),
      );
    });
    _streamRipassoQuestions(cardId, entries, allGaps, elapsed);
  }

  Future<void> _streamRipassoQuestions(
    String cardId,
    List<ProactiveAnalysisEntry> entries,
    List<String> gaps,
    Duration elapsed,
  ) async {
    final provider = EngineScope.current.atlasProvider;
    if (!provider.isInitialized) await provider.initialize();

    final clusterSummaries = entries
        .where((e) => e.scanText.isNotEmpty)
        .take(4)
        .map(
          (e) =>
              '• ' +
              (e.scanText.length > 60
                  ? e.scanText.substring(0, 58) + '…'
                  : e.scanText),
        )
        .join('\n');

    final elapsedStr = _elapsedLabel(elapsed);

    final prompt = '''
$_nativeLangInstruction
LANGUAGE RULE: You MUST respond ENTIRELY in the same language as the instruction above. Never switch to English.

You are ATLAS guiding a focused 24-hour review session (Ebbinghaus spacing).
The student is returning after $elapsedStr.

NOTES CONTENT:
$clusterSummaries

KEY CONCEPTS: ${gaps.join(', ')}

━━ YOUR TASK ━━
Format:
🔄 RIPASSO — $elapsedStr fa
[1 warm line referencing the exact elapsed time]

3–4 ELABORATIVE INTERROGATION questions:
→ "Perché [concept] funziona così?"
→ "Qual è la conseguenza di [concept] su [related]?"
→ "In che situazione reale useresti [concept]?"

Rules: warm tone, max 130 words, no markdown bold/bullets.
DO NOT give answers — student must recall.
''';

    String fullText = '';
    try {
      final stream = provider.askAtlasStream(prompt, []);
      await stream
          .timeout(
            const Duration(seconds: 25),
            onTimeout: (sink) => sink.close(),
          )
          .forEach((chunk) {
            fullText += chunk;
            if (mounted) {
              final card = _atlasCards.where((c) => c.id == cardId).firstOrNull;
              if (card != null) setState(() => card.text = fullText);
            }
          });
    } catch (e) {
      if (mounted) {
        final card = _atlasCards.where((c) => c.id == cardId).firstOrNull;
        if (card != null)
          setState(() => card.text = '⚠️ Ripasso non disponibile: $e');
      }
    }
  }

  /// Converts [elapsed] to a human-readable Italian label: "6 ore", "ieri sera", etc.
  String _elapsedLabel(Duration elapsed) {
    final h = elapsed.inHours;
    final m = elapsed.inMinutes % 60;
    if (h == 0) return '$m min';
    if (h == 1) return '1 ora';
    if (h < 6) return '$h ore';
    if (h < 12) return '$h ore';
    if (h < 18) return 'circa mezza giornata';
    if (h < 24) return 'ieri sera';
    return '${elapsed.inDays} giorni';
  }

  // ── CORNELL QUESTION ──────────────────────────────────────────────────

  /// Generates a Cornell-style question for [concept] and adds it as an
  /// overlay tag near the cluster centroid so the user can write the answer.
  Future<void> _generateCornellQuestion(
    String concept,
    String srcClusterId,
  ) async {
    if (!mounted) return;
    final provider = EngineScope.current.atlasProvider;
    if (!provider.isInitialized) await provider.initialize();

    final cluster =
        _clusterById(srcClusterId);
    final clusterCtx = (_clusterTextCache[srcClusterId] ?? '').trim();
    final screenPos =
        cluster != null
            ? _canvasController
                .canvasToScreen(cluster.centroid)
                .translate(0, -50)
            : Offset(MediaQuery.sizeOf(context).width / 2 - 140, 120);

    final cardId =
        'cornell_${srcClusterId}_${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      _atlasCards.add(
        _AtlasCardEntry(
          id: cardId,
          text: '💬 Generando domanda Cornell…',
          position: screenPos,
        ),
      );
    });

    // Include cluster scan text for contextual questions
    final contextLine =
        clusterCtx.isNotEmpty
            ? 'CLUSTER CONTEXT: "${clusterCtx.length > 120 ? clusterCtx.substring(0, 118) + "..." : clusterCtx}"\n'
            : '';

    final prompt =
        '$_nativeLangInstruction\n'
        'LANGUAGE RULE: You MUST respond ENTIRELY in the same language as the instruction above. Never switch to English.\n'
        '\n'
        'You are ATLAS generating a Cornell method question (Pauk 1962).\n'
        '\n'
        'CONCEPT: "$concept"\n'
        '\n'
        '━━ GENERATE ━━\n'
        'One SHORT, PRECISE Cornell question (max 1 sentence) that:\n'
        '✓ Tests UNDERSTANDING, not recall of a definition\n'
        '✓ Starts with: Come / Perché / Qual è la relazione / In che modo / Cosa succede se…\n'
        '✓ Is open-ended (no yes/no answers)\n'
        '✗ No preamble, no explanation — just the question.\n'
        '\n'
        'Format: 💬 [your question here]';

    String fullText = '';
    try {
      final stream = provider.askAtlasStream(prompt, []);
      await stream
          .timeout(
            const Duration(seconds: 15),
            onTimeout: (sink) => sink.close(),
          )
          .forEach((chunk) {
            fullText += chunk;
            if (mounted) {
              final card = _atlasCards.where((c) => c.id == cardId).firstOrNull;
              if (card != null) setState(() => card.text = fullText);
            }
          });
    } catch (e) {
      if (mounted) {
        final card = _atlasCards.where((c) => c.id == cardId).firstOrNull;
        if (card != null) setState(() => card.text = '🔌 Connessione interrotta — riprova');
      }
    }
  }
}
