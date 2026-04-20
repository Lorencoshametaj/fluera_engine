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
    );

    debugPrint('🌉 [CrossZone] AI returned $count bridge suggestions');

    if (count > 0) {
      // Gentle haptic confirmation
      HapticFeedback.lightImpact();
    }

    if (mounted) setState(() {});
  }

  /// Accept a bridge suggestion — materialize the ghost connection.
  ///
  /// Called when the student taps a ghost dashed golden line.
  /// Returns the materialized connection for optional navigation.
  KnowledgeConnection? acceptCrossZoneBridge(String suggestionId) {
    final conn = _crossZoneBridgeController?.acceptBridge(suggestionId);
    if (conn != null) {
      HapticFeedback.lightImpact();
      debugPrint('🌉 [CrossZone] Bridge accepted: ${conn.id}');
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
    );
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
