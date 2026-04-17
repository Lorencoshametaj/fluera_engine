part of '../fluera_canvas_screen.dart';

/// 🗺️ Ghost Map Lifecycle — Dismiss, progress, navigation, Passo 3 integration.
///
/// Split from _ghost_map.dart for maintainability.
/// See _ghost_map.dart for core trigger/tap logic.
/// See _ghost_map_overlays.dart for overlay bottom sheets.
extension FlueraGhostMapLifecycleExtension on _FlueraCanvasScreenState {

  // ── DISMISS ──────────────────────────────────────────────────────────────

  /// Dismiss the ghost map overlay and show summary toast.
  void dismissGhostMap() {
    final l10n = _l10n;
    final controller = _ghostMapController;

    final summary = controller.summaryText;

    // 🗺️ P4-39: Save Passo 4 dataset before dismissing
    final dataset = controller.toDatasetJson();
    if (dataset.isNotEmpty) {
      debugPrint('🗺️ Passo 4 dataset: ${dataset['canvasGrowth']}% growth, '
          '${dataset['attemptsCount']} attempts, '
          '${dataset['totalHypercorrection']} hypercorrections');

      // 🗺️ P4-39: Persist dataset via storage adapter (fire-and-forget)
      _persistGhostMapDataset(dataset);

      // 🧠 P5-01: Feed Ghost Map results into FSRS scheduler.
      // Each node's attempt result calibrates the spaced-repetition interval,
      // bridging Passo 4 → Passo 5 (overnight computation) → Passo 6 (SRS blur).
      _updateGhostMapSrsSchedule(controller);

      // 🚦 A15: Record Step 4 completion.
      _stepGateController.recordStepCompletion(LearningStep.step4GhostMap);
      _saveStepGateHistory();
    }

    // Cancel any active inline attempt before dismissing
    if (_isInlineAttemptActive) _cancelInlineGhostAttempt();

    // 🗺️ P4-24: Animated fade-out (500ms) before actual dismiss
    _animateGhostMapFadeOut(() {
      controller.dismiss();
      _ghostMapAnimController?.stop();
      // U-1: Stop entry timer on dismiss
      _ghostMapEntryTimer.stop();
      if (!mounted) return;
      setState(() {});

      if (summary.isNotEmpty && mounted) {
        // 🗺️ P4-27: Show growth percentage in summary
        final growth = dataset['canvasGrowth'] as int?;
        final growthSuffix = growth != null ? l10n.ghostMap_growthSuffix(growth) : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🗺️ $summary$growthSuffix'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.only(bottom: 80, left: 20, right: 20),
            duration: const Duration(seconds: 5),
            backgroundColor: const Color(0xFF2E7D32),
          ),
        );
      }

      // 🗺️ P4-38: Post-dismiss writing guidance — the AI is now dormant,
      // but the student should continue writing on their canvas.
      if (mounted) {
        final growthPercent = dataset['canvasGrowth'] as int?;
        final attemptsCount = dataset['attemptsCount'] as int? ?? 0;

        // 2s later: writing guidance
        Future.delayed(const Duration(seconds: 2), () {
          if (!mounted) return;

          // Choose message based on growth level
          final String writeMsg;
          if (growthPercent != null && growthPercent >= 80) {
            writeMsg = l10n.ghostMap_dismissGuidanceExcellent;
          } else if (attemptsCount > 0) {
            writeMsg = l10n.ghostMap_dismissGuidanceGood;
          } else {
            writeMsg = l10n.ghostMap_dismissGuidanceDefault;
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(writeMsg),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.only(bottom: 80, left: 20, right: 20),
              duration: const Duration(seconds: 5),
              backgroundColor: const Color(0xFF00695C),
            ),
          );
        });

        // 🗺️ P4-37: 8s later: consolidation message
        Future.delayed(const Duration(seconds: 8), () {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                l10n.ghostMap_sleepConsolidation,
              ),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.only(bottom: 80, left: 20, right: 20),
              duration: const Duration(seconds: 4),
              backgroundColor: const Color(0xFF1A237E),
            ),
          );
        });
      }
    });
  }

  /// 🗺️ P4-24: Smoothly fade out the ghost map overlay over 500ms,
  /// then call [onComplete] to actually dismiss the controller state.
  ///
  /// Fix #18: Uses AnimationController for vsync-accurate, cancel-safe animation
  /// instead of manual Future.delayed stepping (which was locked to 20fps).
  void _animateGhostMapFadeOut(VoidCallback onComplete) {
    // Cancel any existing fade-out animation (Fix #11: prevents double-dismiss)
    _ghostMapFadeOutController?.dispose();

    final controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _ghostMapFadeOutController = controller;

    controller.addListener(() {
      if (!mounted) return;
      _ghostMapOpacity.value = 1.0 - controller.value;
    });

    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _ghostMapOpacity.value = 0.0;
        onComplete();
        // Reset for next activation
        _ghostMapOpacity.value = 1.0;
        // Clean up
        _ghostMapFadeOutController?.dispose();
        _ghostMapFadeOutController = null;
      }
    });

    controller.forward();
  }

  /// 🗺️ P4-39: Persist the ghost map dataset JSON via the storage adapter.
  ///
  /// R10: Uses transactional write to prevent partial data on force-kill.
  /// Fire-and-forget: runs asynchronously, non-blocking, swallows errors.
  void _persistGhostMapDataset(Map<String, dynamic> dataset) {
    Future(() async {
      try {
        final adapter = _config.storageAdapter;
        if (adapter == null) return;

        final sessionId = dataset['sessionId'] as String? ?? 'unknown';
        final jsonStr = jsonEncode(dataset);

        await adapter.saveGhostMapDataset(_canvasId, sessionId, jsonStr);
        debugPrint('🗺️ P4-39: Dataset persisted (${jsonStr.length} chars)');
      } catch (e) {
        debugPrint('🗺️ P4-39: Dataset persistence failed: $e');
      }
    });
  }

  /// 🧠 P5-01: Feed Ghost Map results into FSRS spaced-repetition scheduler.
  ///
  /// Maps each ghost node's attempt status to an FSRS review:
  /// - Correct attempt → quality 2 (correct)
  /// - Incorrect attempt → quality 0 (wrong)
  /// - Revealed without attempt → quality 0 (skipped/passive)
  /// - Dismissed → no update (student chose to ignore)
  /// - Correct nodes (already on canvas) → quality 2 + full confidence (reinforcement)
  ///
  /// This bridges Passo 4 → Passo 5 (overnight SRS computation) → Passo 6 (blur recall).
  void _updateGhostMapSrsSchedule(GhostMapController controller) {
    final result = controller.result;
    if (result == null) return;

    int updated = 0;

    for (final node in result.nodes) {
      // Use the node's concept as the SRS key
      final concept = node.concept;
      if (concept.isEmpty) continue;

      // Skip dismissed nodes — student explicitly chose to ignore
      if (controller.dismissedNodeIds.contains(node.id)) continue;

      final existing = _reviewSchedule[concept] ?? SrsCardData.newCard();
      final confidence = node.confidenceLevel ?? 3;

      if (node.isCorrect) {
        // Node was already on the canvas correctly → reinforce
        _reviewSchedule[concept] = FsrsScheduler.review(
          existing, quality: 2, confidence: 5,
        );
        updated++;
      } else if (node.attemptCorrect == true) {
        // Student attempted and got it right
        // Fix #23: If self-eval override was used, boost confidence
        final selfEvalConf = confidence < 3 ? 3 : confidence;
        _reviewSchedule[concept] = FsrsScheduler.review(
          existing, quality: 2, confidence: selfEvalConf,
        );
        updated++;
      } else if (node.attemptCorrect == false) {
        // Student attempted and got it wrong
        // Fix #23: If self-eval override (admitted error), cap confidence
        final selfEvalConf = confidence > 1 ? 1 : confidence;
        _reviewSchedule[concept] = FsrsScheduler.review(
          existing, quality: 0, confidence: selfEvalConf,
        );
        updated++;
      } else if (node.isRevealed) {
        // Revealed without attempting → passive exposure, weak encoding
        _reviewSchedule[concept] = FsrsScheduler.review(
          existing, quality: 1, confidence: 1,
        );
        updated++;
      }
      // else: missing node not interacted with → no SRS update
    }

    if (updated > 0) {
      _saveSpacedRepetition();
      debugPrint('🗺️ P5-01: Ghost Map FSRS updated $updated concepts');
    }
  }

  // ── PROGRESS WIDGET ──────────────────────────────────────────────────────

  /// Build a progress indicator for the ghost map exploration.
  Widget _buildGhostMapProgress() {
    final l10n = _l10n;
    final controller = _ghostMapController;
    if (controller.result == null) return const SizedBox.shrink();

    final total = controller.totalMissingNodeCount;
    // O-5: Use pre-computed getter instead of creating 3 temporary sets
    final revealed = controller.addressedMissingCount;
    final progress = total > 0 ? (revealed / total).clamp(0.0, 1.0) : 0.0;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                l10n.ghostMap_progressExplored(revealed, total),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (controller.allMissingRevealed)
              TextButton(
                onPressed: dismissGhostMap,
                child: Text(l10n.ghostMap_closeGhostMap,
                  style: const TextStyle(fontSize: 11)),
              ),
          ],
        ),
        const SizedBox(height: 6),
        // Fix #20: Accessibility for screen readers
        Semantics(
          label: l10n.ghostMap_progressExplored(revealed, total),
          value: '${(progress * 100).round()} percento',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        // 🗺️ P4-32: Show "reveal more" button if more chunks available
        if (controller.hasMoreChunks) ...[
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              icon: const Icon(Icons.expand_more, size: 18),
              label: Text(l10n.ghostMap_showMoreGaps),
              onPressed: () {
                controller.revealNextChunk();
                setState(() {});
              },
            ),
          ),
        ],
      ],
    );
  }

  // ── NAVIGATION BAR ──────────────────────────────────────────────────────────

  /// 🗺️ P4-14: Build the floating navigation bar for traversing ghost nodes.
  ///
  /// Shows prev/next buttons and current position indicator.
  /// Navigation order: 🔴 missing → 🟡 wrong/weak → 🔵 connections.
  Widget buildGhostMapNavigationBar() {
    final controller = _ghostMapController;
    if (!controller.isActive || controller.result == null) {
      return const SizedBox.shrink();
    }

    final missing = controller.activeNodes.where((n) => n.isMissing && !n.isRevealed).length;
    final wrongOrWeak = controller.activeNodes
        .where((n) => (n.isWrongConnection || n.isWeak) && !n.isRevealed)
        .length;

    if (missing == 0 && wrongOrWeak == 0) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Previous
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 22),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: () {
              final node = controller.navigatePrevious();
              if (node != null) _navigateToGhostNode(node);
            },
          ),

          // Type pills
          if (missing > 0)
            _buildNavPill('🔴', '$missing', GhostNodeStatus.missing),
          if (wrongOrWeak > 0)
            _buildNavPill('🟡', '$wrongOrWeak', GhostNodeStatus.weak),

          // Position label
          if (controller.navigationLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                controller.navigationLabel,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),

          // Next
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 22),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: () {
              final node = controller.navigateNext();
              if (node != null) _navigateToGhostNode(node);
            },
          ),

          // Info button
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.info_outline, size: 18),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () => GhostMapInfoScreen.show(context),
            tooltip: 'Info Ghost Map',
          ),

          // Close button
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: dismissGhostMap,
            tooltip: _l10n.ghostMap_closeGhostMap,
          ),
        ],
      ),
    );
  }

  /// Build a small navigation pill button for a specific node type.
  Widget _buildNavPill(String emoji, String count, GhostNodeStatus type) {
    final isActive = _ghostMapController.navigationFocusType == type;
    return GestureDetector(
      onTap: () {
        final node = _ghostMapController.navigateNext(type: type);
        if (node != null) _navigateToGhostNode(node);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '$emoji $count',
          style: TextStyle(
            fontSize: 12,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  /// Navigate the canvas to center on a specific ghost node.
  void _navigateToGhostNode(GhostNode node) {
    HapticFeedback.selectionClick();
    final viewportSize = MediaQuery.of(context).size;

    // Zoom to fit the node with comfortable padding.
    // Target: node fills ~40% of screen width.
    final nodeWidth = node.estimatedSize.width > 0 ? node.estimatedSize.width : 220.0;
    final targetScale = (viewportSize.width * 0.4 / nodeWidth)
        .clamp(0.8, 2.5); // don't zoom too far in or out

    // Only zoom in if current zoom is too far out
    if (_canvasController.scale < targetScale) {
      _canvasController.setScale(targetScale);
    }

    // Center the node on screen at the (possibly new) scale
    final scale = _canvasController.scale;
    final targetOffset = Offset(
      viewportSize.width / 2 - node.estimatedPosition.dx * scale,
      viewportSize.height / 2 - node.estimatedPosition.dy * scale,
    );
    _canvasController.animateOffsetTo(targetOffset);
    if (mounted) setState(() {});
  }

  // ── PASSO 3 INTEGRATION ─────────────────────────────────────────────────

  /// 🗺️ P4-21/22/23: Collect data from the last Socratic session to enrich
  /// Ghost Map nodes with hypercorrection, ZPD, and confidence metadata.
  ///
  /// Returns a map of clusterId → enrichment data that the AI can use.
  Map<String, Map<String, dynamic>> _collectSocraticDataForGhostMap() {
    final data = <String, Map<String, dynamic>>{};

    // From Socratic session (Passo 3)
    final socratic = _socraticController;
    if (socratic.session != null) {
      for (final q in socratic.allQuestions) {
        if (!q.isResolved) continue;

        data[q.clusterId] = {
          'confidence': q.confidence ?? 3,
          'isHypercorrection': q.isHypercorrection,
          'isBelowZPD': q.status == SocraticBubbleStatus.belowZPD,
          'wasCorrect': q.wasCorrect,
          'wasWrong': q.wasWrong,
          'questionType': q.type.name,
          'breadcrumbsUsed': q.breadcrumbsUsed,
        };
      }
    }

    return data;
  }

  /// 🗺️ Post-process ghost nodes with real Passo 3 data.
  ///
  /// The AI generates structural analysis (missing/weak/correct), but the
  /// hypercorrection/ZPD/confidence flags come from actual student behavior
  /// in the Socratic session. This method merges both sources.
  void _enrichGhostNodesFromSocratic(
    GhostMapResult result,
    Map<String, Map<String, dynamic>> socraticData,
  ) {
    if (socraticData.isEmpty) return;

    for (final node in result.nodes) {
      final clusterId = node.relatedClusterId;
      if (clusterId == null) continue;

      final sData = socraticData[clusterId];
      if (sData == null) continue;

      // P4-21: Hypercorrection — student was confident but wrong
      if (sData['isHypercorrection'] == true) {
        node.isHypercorrection = true;
      }

      // P4-22: Below ZPD — concept too advanced for current level
      if (sData['isBelowZPD'] == true) {
        node.isBelowZPD = true;
      }

      // P4-23: Confidence level from Socratic session
      final confidence = sData['confidence'] as int?;
      if (confidence != null) {
        node.confidenceLevel = confidence;
      }

      // P4-11: Wrong connection — Socratic challenge question was answered wrong
      // but with low confidence (not hypercorrection, just a misunderstanding)
      if (sData['wasWrong'] == true &&
          sData['isHypercorrection'] != true &&
          sData['questionType'] == 'challenge' &&
          node.isWeak) {
        node.status = GhostNodeStatus.wrongConnection;
      }
    }

    // Bump version to trigger repaint with enriched data
    // Use the safe method to prevent defunct element crash on dispose.
    // ignore: invalid_use_of_protected_member
    _ghostMapController.notifyListeners();
  }

  // ── OVERLAYS ─────────────────────────────────────────────────────────────

  /// 🗺️ Build Ghost Map UI overlays (navigation bar + progress).
  ///
  /// Called from [_buildImpl] in the main Stack, alongside Recall Mode,
  /// Fog of War, and Socratic overlays.
  List<Widget> buildGhostMapOverlays(BuildContext context) {
    final controller = _ghostMapController;
    if (!controller.isActive || controller.result == null) {
      return const [];
    }

    // U-2: Empty state — all nodes dismissed without interaction
    // Guard: only schedule auto-dismiss once (check via _ghostMapU2Fired)
    if (controller.activeNodes.isEmpty) {
      if (!_ghostMapU2AutoDismissScheduled) {
        _ghostMapU2AutoDismissScheduled = true;
        Future.delayed(const Duration(seconds: 2), () {
          _ghostMapU2AutoDismissScheduled = false;
          if (mounted && controller.isActive) {
            dismissGhostMap();
          }
        });
      }
      return [
        Positioned(
          bottom: 120,
          left: 40,
          right: 40,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 12,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('🎉', style: TextStyle(fontSize: 24)),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    _l10n.ghostMap_closeGhostMap,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ];
    }

    return [
      // 🗺️ P4-14: Floating navigation bar (bottom-center)
      // Hide when inline attempt is active to reduce clutter
      if (!_isInlineAttemptActive)
        Positioned(
          bottom: 80,
          left: 0,
          right: 0,
          child: Center(
            child: buildGhostMapNavigationBar(),
          ),
        ),

      // 🗺️ Progress indicator (top-right, below toolbar)
      if (!_isInlineAttemptActive)
        Positioned(
          top: 12,
          right: 16,
          width: 220,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: _buildGhostMapProgress(),
            ),
          ),
        ),

      // 🗺️ Inline attempt overlay (on-canvas drawing zone)
      ..._buildInlineAttemptWidgets(context),
    ];
  }
}

