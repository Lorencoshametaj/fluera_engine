part of '../fluera_canvas_screen.dart';

/// 🌉 CROSS-ZONE BRIDGES — Passo 9 canvas integration
///
/// Spec: P9-01 → P9-18, A7-01 → A7-10
///
/// Manages the cross-domain bridge workflow from the canvas:
/// - AI bridge suggestion request (toolbar trigger)
/// - Ghost bridge rendering lifecycle
/// - Accept (trace) / dismiss (swipe) gestures
/// - Student-created bridge marking
/// - Cinematic flight navigation between zones
///
/// Design: The AI is invoked ONLY on explicit student request (P9-08).
/// Suggestions appear as Socratic questions, never assertions (P9-09).
extension CrossZoneBridgesExtension on _FlueraCanvasScreenState {

  // ── PUBLIC API ──────────────────────────────────────────────────────────

  /// Request AI bridge suggestions for the current canvas.
  ///
  /// Triggered by the "Suggeriscimi connessioni" toolbar button.
  /// The AI analyzes cross-zone clusters and returns 2-4 Socratic questions.
  /// Ghost dashed golden lines appear between suggested clusters.
  Future<void> requestCrossZoneBridgeSuggestions() async {
    if (_crossZoneBridgeController == null) {
      _initCrossZoneBridgeController();
    }

    final controller = _crossZoneBridgeController;
    if (controller == null || controller.isLoading) return;

    final aiProvider = EngineScope.current.atlasProvider;
    if (!aiProvider.isInitialized) {
      debugPrint('🌉 [CrossZone] AI not available');
      return;
    }

    // 💳 Tier gate: Free is view-only (0/week), Pro is unlimited.
    // Gate check AFTER aiProvider readiness to avoid wasting a usage credit
    // on an environment where the AI is unreachable.
    if (!_checkTierGate(GatedFeature.crossDomainInteractive)) {
      return;
    }

    // Haptic feedback: starting
    HapticFeedback.mediumImpact();

    if (mounted) setState(() {});

    // Build title cache from semantic morph controller
    final titleCache = <String, String>{};
    if (_semanticMorphController != null) {
      for (final cluster in _clusterCache) {
        final title = _semanticMorphController!.aiTitles[cluster.id];
        if (title != null) titleCache[cluster.id] = title;
      }
    }

    final count = await controller.requestBridgeSuggestions(
      aiProvider: aiProvider,
      clusters: _clusterCache,
      clusterTexts: _clusterTextCache,
      clusterTitles: titleCache,
      index: _clusterConceptIndex,
      tier: _tierGateController.tier.name,
    );

    debugPrint('🌉 [CrossZone] AI returned $count bridge suggestions');

    if (count > 0) {
      // Gentle haptic confirmation
      HapticFeedback.lightImpact();
    } else if (mounted && _clusterCache.length >= 2) {
      // Zero-result UX: the AI returned nothing despite ≥2 zones.
      // Most common cause: not enough content depth, or all candidate
      // pairs were dismissed before. Nudge the student instead of going silent.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Continua a disegnare in nuove zone — Atlas troverà '
            'connessioni quando il contenuto cresce.',
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.only(bottom: 80, left: 20, right: 20),
          duration: const Duration(seconds: 4),
        ),
      );
    }

    if (mounted) setState(() {});
  }

  /// Accept a bridge suggestion — materialize the ghost connection.
  ///
  /// Called when the student taps a ghost dashed golden line.
  /// Returns the materialized connection for optional navigation.
  KnowledgeConnection? acceptCrossZoneBridge(String suggestionId) {
    // 💳 Tier gate: Free cannot materialize bridges (view-only).
    // Defense-in-depth — request gate already blocks suggestions, but a
    // downgrade-from-Pro user could still have ghost suggestions in flight.
    // No recordUsage here: the credit is consumed at request time.
    final result = _tierGateController.checkFeature(
      GatedFeature.crossDomainInteractive,
    );
    if (!result.allowed) {
      if (mounted && result.upgradeMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.upgradeMessage!),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.only(bottom: 80, left: 20, right: 20),
            duration: const Duration(seconds: 5),
            backgroundColor: const Color(0xFF6A1B9A),
          ),
        );
      }
      return null;
    }
    final conn = _crossZoneBridgeController?.acceptBridge(suggestionId);
    if (conn != null) {
      HapticFeedback.lightImpact();
      debugPrint('🌉 [CrossZone] Bridge accepted: ${conn.id}');

      // 🧩 F9: materialize the bridge as a stroke connector so it lives in
      // the scene-graph (exportable, undoable as 1 entry, survives reload).
      // The KnowledgeConnection above stays — it's the LOGICAL layer for
      // FSRS / Socratic seed / cross-session persistence. The connector is
      // the VISUAL layer. Fire-and-forget: never block the UI on
      // materialization, accept feedback (the haptic) already fired.
      final byId = {for (final c in _clusterCache) c.id: c};
      unawaited(_crossZoneBridgeController!
          .materializeAsStrokeConnector(
        bridge: conn,
        layerController: _layerController,
        clusterResolver: (id) => byId[id],
      )
          .then((_) {
        if (!mounted) return;
        _layerController.sceneGraph.bumpVersion();
        DrawingPainter.invalidateAllTiles();
        _canvasController.markNeedsPaint();
        setState(() {});
      }).catchError((e) {
        debugPrint('🌉 [CrossZone] Materialize failed: $e');
      }));
    }
    if (mounted) setState(() {});
    return conn;
  }

  /// Dismiss a bridge suggestion — fade out the ghost connection.
  void dismissCrossZoneBridge(String suggestionId) {
    _crossZoneBridgeController?.dismissBridge(suggestionId);
    HapticFeedback.lightImpact();
    if (mounted) setState(() {});
  }

  /// Mark a student-created connection as a cross-zone bridge.
  ///
  /// Called automatically when a new connection is made between
  /// distant zones (distance > crossZoneDistanceThreshold).
  void markStudentCrossZoneBridge(
    KnowledgeConnection connection, {
    CrossZoneBridgeType? bridgeType,
  }) {
    _initCrossZoneBridgeController();
    _crossZoneBridgeController?.markAsStudentBridge(
      connection,
      bridgeType: bridgeType,
    );
    if (mounted) setState(() {});
  }

  /// Navigate to a cross-zone bridge via cinematic flight (P9-16-17).
  ///
  /// Three-phase camera sequence:
  /// 1. Zoom-out to reveal source and target zones
  /// 2. Pan along the golden bridge arc
  /// 3. Zoom-in on the destination zone
  ///
  /// The "viaggio" must be visually perceivable — no teleportation (P9-17).
  void navigateToCrossZoneBridge(KnowledgeConnection bridge) {
    final endpoints =
        _crossZoneBridgeController?.getBridgeEndpoints(bridge, _clusterCache);
    if (endpoints == null) return;

    // Compute viewport-aware camera transforms for 3-phase flight
    final viewportSize = MediaQuery.of(context).size;

    // Phase 1: Zoom out to reveal both zones (satellite view)
    final midpoint = Offset(
      (endpoints.source.dx + endpoints.target.dx) / 2,
      (endpoints.source.dy + endpoints.target.dy) / 2,
    );
    final distance = (endpoints.target - endpoints.source).distance;
    final zoomOutScale = (viewportSize.width / (distance * 1.8))
        .clamp(0.1, _canvasController.scale * 0.5);

    final zoomOutOffset = Offset(
      viewportSize.width / 2 - midpoint.dx * zoomOutScale,
      viewportSize.height / 2 - midpoint.dy * zoomOutScale,
    );

    // Phase 3: Zoom in on target
    final zoomInScale = _canvasController.scale; // restore original scale
    final zoomInOffset = Offset(
      viewportSize.width / 2 - endpoints.target.dx * zoomInScale,
      viewportSize.height / 2 - endpoints.target.dy * zoomInScale,
    );

    _canvasController.animateMultiPhase(
      keyframes: [
        // Phase 1: Zoom out (0.4s)
        CameraKeyframe(
          targetOffset: zoomOutOffset,
          targetScale: zoomOutScale,
          durationSeconds: 0.4,
          curve: Curves.easeOutCubic,
        ),
        // Phase 2: Hold panoramic view (0.3s)
        CameraKeyframe(
          targetOffset: zoomOutOffset,
          targetScale: zoomOutScale,
          durationSeconds: 0.3,
          curve: Curves.linear,
        ),
        // Phase 3: Zoom in on target zone (0.5s)
        CameraKeyframe(
          targetOffset: zoomInOffset,
          targetScale: zoomInScale,
          durationSeconds: 0.5,
          curve: Curves.easeInOutCubic,
        ),
      ],
      sourceClusterId: bridge.sourceClusterId,
      targetClusterId: bridge.targetClusterId,
      onPhaseChanged: (phase) {
        HapticFeedback.lightImpact();
      },
    );

    HapticFeedback.mediumImpact();
    debugPrint('🌉 [CrossZone] Flight to bridge: ${bridge.id}');
  }

  /// Clear all pending bridge suggestions.
  void clearCrossZoneSuggestions() {
    _crossZoneBridgeController?.clearSuggestions();
    if (mounted) setState(() {});
  }

  /// Whether bridge suggestions are currently loading.
  bool get isCrossZoneBridgeLoading =>
      _crossZoneBridgeController?.isLoading ?? false;

  /// Active (non-dismissed) bridge suggestions.
  List<CrossZoneBridgeSuggestion> get crossZoneBridgeSuggestions =>
      _crossZoneBridgeController?.suggestions ?? const [];

  /// Session stats for cross-zone bridges.
  BridgeSessionStats? get crossZoneBridgeStats =>
      _crossZoneBridgeController?.stats;

  /// Number of solid cross-zone bridges (for toolbar badge).
  int get crossZoneBridgeCount =>
      _knowledgeFlowController?.crossZoneBridgeCount ?? 0;

  /// 🌉 Seed the active Socratic session with `transfer`-type questions
  /// derived from recently accepted Cross-Zone Bridges (last 7 days).
  ///
  /// Returns the number of seeds added — `0` when there is no active
  /// Socratic session, no qualifying bridges, or every bridge has an
  /// empty `bridgeSocraticQuestion`. Surfaces a SnackBar on success so
  /// the student sees the connection between "Approfondisci ponte" and
  /// the new questions appearing in the Socratic queue.
  int seedSocraticFromRecentBridges({int withinDays = 7}) {
    final ctrl = _crossZoneBridgeController;
    if (ctrl == null) return 0;
    if (!_socraticController.isActive) return 0;

    final bridges = ctrl.recentAcceptedBridges(withinDays: withinDays);
    if (bridges.isEmpty) return 0;

    final seeds = <({String clusterId, Offset anchorPosition, String question})>[];
    for (final b in bridges) {
      final q = b.bridgeSocraticQuestion?.trim() ?? '';
      if (q.isEmpty) continue;
      // Anchor at the midpoint of the bridge so the bubble materializes
      // near the visual ponte the student already saw.
      final src = b.sourceAnchor ?? Offset.zero;
      final tgt = b.targetAnchor ?? Offset.zero;
      final anchor = Offset((src.dx + tgt.dx) / 2, (src.dy + tgt.dy) / 2);
      seeds.add((clusterId: b.sourceClusterId, anchorPosition: anchor, question: q));
    }
    if (seeds.isEmpty) return 0;

    final added = _socraticController.seedFromBridges(seeds);
    if (added > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Aggiunti $added ponti recenti alla sessione Socratica.',
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.only(bottom: 80, left: 20, right: 20),
          duration: const Duration(seconds: 3),
          backgroundColor: const Color(0xFFF9A825), // golden accent
        ),
      );
      setState(() {});
    }
    return added;
  }

  /// Whether Step 9 is available (≥2 zones with sufficient content).
  bool get canActivateCrossZoneBridges {
    final gate = _stepGateController.evaluateGate(
      LearningStep.step9CrossDomain,
      context: _buildZoneContext(),
    );
    return gate.canProceed;
  }

  // ── PRIVATE HELPERS ──────────────────────────────────────────────────────

  /// Lazy-initialize the cross-zone bridge controller.
  void _initCrossZoneBridgeController() {
    if (_crossZoneBridgeController != null) return;
    final flowCtrl = _knowledgeFlowController;
    if (flowCtrl == null) return;
    _crossZoneBridgeController = CrossZoneBridgeController(
      flowController: flowCtrl,
      telemetry: widget.config.telemetry,
      canvasId: _canvasId,
      onBridgeAccepted: _applyBridgeFsrsBump,
    );
  }

  /// Apply an FSRS consolidation bump on both clusters of an accepted bridge.
  ///
  /// Pedagogical rationale: Bjork (1994) "desirable difficulty" — a concept
  /// successfully transferred across domains has demonstrated retrievability
  /// in a novel context, which is a stronger memory consolidation signal
  /// than a straight rote review. Modeled as `quality=2` (correct recall)
  /// on the cluster's SRS card via the standard FSRS formula.
  void _applyBridgeFsrsBump({
    required String sourceClusterId,
    required String targetClusterId,
    required CrossZoneBridgeType bridgeType,
    required String socraticQuestion,
  }) {
    final today = DateTime.now();
    final todayKey = DateTime(today.year, today.month, today.day);

    // 🎓 Triennial-scale: opportunistic cleanup of the bump-tracking map.
    // Entries older than 30 days serve no purpose (cap is 1×/cluster/day,
    // so anything past today is non-functional). Pruning here keeps the
    // map small on a 3-year canvas without needing a scheduled job.
    final cutoff = today.subtract(const Duration(days: 30));
    _bridgeFsrsBumpLastDay
        .removeWhere((_, lastBump) => lastBump.isBefore(cutoff));

    for (final clusterId in [sourceClusterId, targetClusterId]) {
      final lastBump = _bridgeFsrsBumpLastDay[clusterId];
      if (lastBump != null && !todayKey.isAfter(lastBump)) {
        // Already bumped this cluster today — skip (gaming guard).
        continue;
      }

      final concept = _clusterConceptIndex?.peek(clusterId);
      if (concept == null || concept.concepts.isEmpty) continue;

      bool didBump = false;
      for (final conceptName in concept.concepts) {
        final card = _reviewSchedule[conceptName];
        if (card == null) continue;
        _reviewSchedule[conceptName] =
            FsrsScheduler.review(card, quality: 2);
        didBump = true;
      }
      if (didBump) {
        _bridgeFsrsBumpLastDay[clusterId] = todayKey;
      }
    }
  }

  /// 🌉 Show a Socratic confirmation dialog for an AI bridge suggestion.
  ///
  /// Presents the Socratic question along with Accept / Dismiss / Navigate
  /// actions. The dialog follows Material Design 3 patterns consistent
  /// with the Socratic Dialogue and Ghost Map cognitive tools.
  void _showBridgeSuggestionDialog(
    CrossZoneBridgeSuggestion suggestion,
    Offset screenAnchor,
  ) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final goldenColor = isDark
        ? const Color(0xFFFFD54F)
        : const Color(0xFFF9A825);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: goldenColor.withValues(alpha: 0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: goldenColor.withValues(alpha: 0.15),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ────────────────────────────────────────
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: goldenColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.hub_rounded,
                      color: goldenColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ponte Cross-Dominio',
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        _buildBridgeTypeBadge(suggestion.bridgeType, goldenColor),
                      ],
                    ),
                  ),
                  // Confidence indicator
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: goldenColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${(suggestion.confidence * 100).round()}%',
                      style: TextStyle(
                        color: goldenColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ── Socratic Question (P9-09) ──────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: goldenColor.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: goldenColor.withValues(alpha: 0.15),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '💡',
                      style: TextStyle(fontSize: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        suggestion.socraticQuestion,
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          height: 1.5,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Actions ────────────────────────────────────────
              Row(
                children: [
                  // Dismiss
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        dismissCrossZoneBridge(suggestion.id);
                      },
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Non ora'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cs.onSurfaceVariant,
                        side: BorderSide(
                          color: cs.outlineVariant,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Accept
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        final conn = acceptCrossZoneBridge(suggestion.id);
                        // Navigate to the bridge for spatial continuity
                        if (conn != null) {
                          navigateToCrossZoneBridge(conn);
                        }
                      },
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Accetta Ponte'),
                      style: FilledButton.styleFrom(
                        backgroundColor: goldenColor,
                        foregroundColor: Colors.black87,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),

              // Safe area padding
              SizedBox(height: MediaQuery.of(ctx).padding.bottom),
            ],
          ),
        ),
      ),
    );
  }

  /// Build badge widget for bridge type classification.
  Widget _buildBridgeTypeBadge(
    CrossZoneBridgeType type,
    Color goldenColor,
  ) {
    final (label, icon) = switch (type) {
      CrossZoneBridgeType.analogyStructural => ('Analogia', '🔗'),
      CrossZoneBridgeType.sharedMechanism => ('Meccanismo', '⚙️'),
      CrossZoneBridgeType.complementaryPerspective => ('Prospettiva', '🔍'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: goldenColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$icon $label',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: goldenColor,
        ),
      ),
    );
  }

}
