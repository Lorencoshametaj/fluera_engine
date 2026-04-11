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
    // Guard: don't start if already active or conflicting.
    if (_socraticController.isActive) return;
    if (_fogOfWarController.isActive) return;

    // 🚦 A15: Step prerequisite gate for Step 3.
    if (!_checkStepGate(
      LearningStep.step3Socratic,
      onProceed: showSocraticSetup,
    )) {
      return;
    }

    HapticFeedback.mediumImpact();

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
            content: const Text(
              'Servono appunti sul canvas per la Socratica 🔶',
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

    setState(() => _socraticGeneratingPhase = 'Riconoscimento testo…');

    // 🔶 OCR: Recognize cluster texts BEFORE generating questions.
    // Without this, Gemini has no idea what the student wrote.
    final inkService = DigitalInkService.instance;
    final activeLayer = _layerController.layers.firstWhere(
      (l) => l.id == _layerController.activeLayerId,
      orElse: () => _layerController.layers.first,
    );
    final strokeMap = <String, ProStroke>{};
    for (final s in activeLayer.strokes) {
      strokeMap[s.id] = s;
    }
    final textMap = <String, DigitalTextElement>{};
    for (final t in _digitalTextElements) {
      textMap[t.id] = t;
    }

    for (final cluster in _clusterCache) {
      if (_clusterTextCache.containsKey(cluster.id)) continue;
      if (cluster.strokeIds.isEmpty && cluster.textIds.isEmpty) continue;

      final textParts = <String>[];
      for (final tid in cluster.textIds) {
        final textEl = textMap[tid];
        if (textEl != null && textEl.text.trim().isNotEmpty) {
          textParts.add(textEl.text.trim());
        }
      }

      final strokeSets = <List<ProDrawingPoint>>[];
      for (final sid in cluster.strokeIds) {
        final stroke = strokeMap[sid];
        if (stroke != null && !stroke.isStub && stroke.points.length >= 3) {
          strokeSets.add(stroke.points);
        }
      }

      if (strokeSets.isEmpty && textParts.isEmpty) {
        _clusterTextCache[cluster.id] = '';
        continue;
      }

      if (strokeSets.isNotEmpty && inkService.isAvailable) {
        final myScript = inkService.engine as MyScriptInkEngine;
        final recognized = await myScript.recognizeText(strokeSets);
        final parts = [...textParts];
        if (recognized != null && recognized.isNotEmpty) {
          parts.add(recognized);
        }
        _clusterTextCache[cluster.id] = parts.join(' ');
      } else if (textParts.isNotEmpty) {
        _clusterTextCache[cluster.id] = textParts.join(' ');
      }
    }

    debugPrint(
      '🔶 Socratic OCR: ${_clusterTextCache.length} clusters recognized',
    );

    if (mounted)
      setState(() => _socraticGeneratingPhase = 'Generazione domande…');

    await _socraticController.activate(
      clusters: _clusterCache,
      recallData: recallData,
      provider: provider,
      clusterTexts: _clusterTextCache,
    );

    // Start pulse animation.
    _socraticPulseController?.repeat(reverse: true);

    // 🎵 A13.4: "Il mentore arriva" — C4→E4 ascending notes
    PedagogicalSoundEngine.instance.play(PedagogicalSound.aiArrives);

    setState(() => _socraticGeneratingPhase = null);

    if (_socraticController.isActive && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '🔶 Interrogazione Socratica — '
            '${_socraticController.allQuestions.length} domande',
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

  // ─────────────────────────────────────────────────────────────────────────
  // CONFIDENCE + SELF-EVAL
  // ─────────────────────────────────────────────────────────────────────────

  /// Set confidence level for the active question (P3-17).
  void _socraticSetConfidence(int level) {
    _socraticController.setConfidence(level);
    HapticFeedback.selectionClick();
    setState(() {});
  }

  /// Record self-evaluation result (P3-20).
  void _socraticRecordResult(bool recalled) {
    _socraticController.recordResult(recalled: recalled);

    // Haptic feedback varies by result (P3-21).
    final q =
        _socraticController.session?.queue
            .where((q) => q.answeredAt != null)
            .lastOrNull;
    if (q != null && q.isHypercorrection) {
      HapticFeedback.heavyImpact(); // ⚡ Shock!
    } else if (q != null && q.wasWrong) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.lightImpact();
    }

    setState(() {});
  }

  /// Skip the current question (P3-15).
  void _socraticSkip() {
    HapticFeedback.selectionClick();
    _socraticController.skip();
    if (_socraticController.isComplete) {
      _showSocraticSummary();
    }
    setState(() {});
  }

  /// Request a breadcrumb (P3-24).
  void _socraticRequestBreadcrumb() {
    _socraticController.requestBreadcrumb();
    HapticFeedback.selectionClick();
    setState(() {});
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

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A0A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (_) => Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                const Row(
                  children: [
                    Text('🔶', style: TextStyle(fontSize: 20)),
                    SizedBox(width: 8),
                    Text(
                      'Sessione Socratica completata',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Stats row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _summaryStatChip(
                      '✅',
                      '${session.totalCorrect}',
                      'Corrette',
                      const Color(0xFF66BB6A),
                    ),
                    _summaryStatChip(
                      '❌',
                      '${session.totalWrong}',
                      'Errate',
                      const Color(0xFFEF5350),
                    ),
                    _summaryStatChip(
                      '⚡',
                      '${session.totalHypercorrections}',
                      'Ipercorrezioni',
                      const Color(0xFFFF9800),
                    ),
                    _summaryStatChip(
                      '⏭️',
                      '${session.totalSkipped}',
                      'Saltate',
                      Colors.grey,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Metacognitive insight
                _buildMetacognitiveInsight(session),

                const SizedBox(height: 16),

                // Close button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1B5E20),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(context).pop();
                      dismissSocraticMode();
                    },
                    child: const Text('Chiudi e torna al canvas'),
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

  Widget _buildMetacognitiveInsight(SocraticSession session) {
    String insight;
    IconData icon;
    Color color;

    if (session.totalHypercorrections > 0) {
      // Find hypercorrection clusters
      final hyperQs = session.queue.where((q) => q.isHypercorrection);
      final clusterIds = hyperQs.map((q) => q.clusterId).toSet();
      insight =
          '⚡ Hai avuto ${session.totalHypercorrections} momento/i di ipercorrezione '
          '— questi sono i tuoi punti più potenti di apprendimento. '
          'Rivedi attentamente i ${clusterIds.length} cluster coinvolti.';
      icon = Icons.flash_on;
      color = const Color(0xFFFF9800);
    } else if (session.totalCorrect == session.totalAnswered &&
        session.totalAnswered > 0) {
      insight =
          '🎯 Tutto corretto! La tua padronanza è solida. '
          'I prossimi intervalli di ripetizione si allungheranno.';
      icon = Icons.emoji_events;
      color = const Color(0xFF66BB6A);
    } else if (session.totalWrong > session.totalCorrect) {
      insight =
          '📚 Ci sono diverse lacune — è il momento migliore per '
          'rileggere i tuoi appunti. Il retrieval ha attivato i circuiti '
          'giusti, ora il rinforzo sarà più efficace.';
      icon = Icons.menu_book;
      color = const Color(0xFFFFB300);
    } else {
      insight =
          '👍 Buon bilanciamento tra ciò che sai e ciò che devi rivedere. '
          'FSRS aggiornerà gli intervalli di ripetizione per te.';
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

  /// Persist Socratic results to FSRS scheduler.
  void _persistSocraticToFSRS(SocraticSession session) {
    for (final q in session.queue) {
      if (!q.wasCorrect && !q.wasWrong) continue; // Skip unanswered

      // Find concepts associated with this cluster
      final concepts = _proactiveCache[q.clusterId]?.gaps ?? [];
      if (concepts.isEmpty) continue;

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
                        'Genero domande calibrate sulla tua ZPD',
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

    final questions = _socraticController.allQuestions;
    final activeQ = _socraticController.session?.activeQuestion;

    // Render bubbles for all questions (resolved ones show status).
    for (int i = 0; i < questions.length; i++) {
      final q = questions[i];
      // Only show resolved questions and the active one.
      // Skip unresolved future questions (P3-40: no visible queue).
      if (!q.isResolved && q.id != activeQ?.id) continue;

      // Convert canvas position to screen position.
      final screenPos = _canvasController.canvasToScreen(q.anchorPosition);

      // Skip if off-screen.
      final screenSize = MediaQuery.sizeOf(context);
      if (screenPos.dx < -300 ||
          screenPos.dx > screenSize.width + 100 ||
          screenPos.dy < -200 ||
          screenPos.dy > screenSize.height + 100) {
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
              isActiveQuestion: q.id == activeQ?.id,
              currentIndex: i,
              totalQuestions: questions.length,
              onConfidenceSelected: (level) => _socraticSetConfidence(level),
              onSelfEval: (recalled) => _socraticRecordResult(recalled),
              onSkip: () => _socraticSkip(),
              onNext: () {
                _socraticController.next();
                if (_socraticController.isComplete) {
                  _showSocraticSummary();
                }
                setState(() {});
              },
              onRequestBreadcrumb: () => _socraticRequestBreadcrumb(),
              currentBreadcrumbText: breadcrumbText,
              breadcrumbsUsed: q.breadcrumbsUsed,
              canRequestBreadcrumb:
                  q.id == activeQ?.id &&
                  _socraticController.canRequestBreadcrumb,
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
              label: const Text('Termina Interrogazione'),
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
                setState(() {});
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
              label: const Text('Chiudi Socratica'),
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
                const Text(
                  'Socratica Attiva',
                  style: TextStyle(
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
}
