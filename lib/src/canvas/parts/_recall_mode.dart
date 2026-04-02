part of '../fluera_canvas_screen.dart';

// ============================================================================
// 🧠 RECALL MODE — Step 2 (Ricostruzione Solitaria) integration
//
// This extension wires the RecallModeController into the canvas screen,
// providing all the glue logic between the controller, overlays, and
// the existing canvas infrastructure (clusters, layers, gestures).
//
// AI STATE: 💤 DORMANT — no AI calls are made from this module.
//
// Spec: P2-01 → P2-70
// ============================================================================

extension RecallModeWiring on _FlueraCanvasScreenState {

  // ─────────────────────────────────────────────────────────────────────────
  // ACTIVATION (P2-01, P2-37)
  // ─────────────────────────────────────────────────────────────────────────

  /// Opens the zone selector overlay for recall activation.
  ///
  /// Called from toolbar button or long-press on empty area.
  void showRecallZoneSelector() {
    // Guard: don't open if already active.
    if (_recallModeController.isActive) return;

    // Auto-advance to Step 2 if in Step 1.
    if (_learningStepController.currentStep == LearningStep.step1Notes) {
      _learningStepController.setStep(LearningStep.step2Recall);
    }

    HapticFeedback.mediumImpact();
    setState(() => _showRecallZoneSelector = true);
  }

  /// Activates recall mode for the selected zone with the chosen mode.
  void activateRecallMode(Rect zone, RecallPhase mode) async {
    // Find clusters within the zone.
    final clustersInZone = _clusterCache
        .where((c) => zone.overlaps(c.bounds) || zone.contains(c.centroid))
        .toList();

    if (clustersInZone.isEmpty) {
      debugPrint('🧠 No clusters in selected zone');
      setState(() => _showRecallZoneSelector = false);
      return;
    }

    // Get session count for adaptive blur (P2-54).
    final zoneId =
        'zone_${zone.left.toInt()}_${zone.top.toInt()}_${zone.width.toInt()}_${zone.height.toInt()}';
    final sessionCount = await _recallPersistenceService
        .getZoneSessionCount(_canvasId, zoneId);

    // Activate controller.
    _recallModeController.activate(
      zone: zone,
      clustersInZone: clustersInZone,
      canvasId: _canvasId,
      initialPhase: mode,
      sessionCount: sessionCount,
    );

    setState(() {
      _showRecallZoneSelector = false;
      _showRecallSummary = false;
    });
  }

  /// Deactivates recall mode and saves the session.
  void deactivateRecallMode() async {
    final session = _recallModeController.session;
    if (session != null) {
      // Save session to persistence.
      await _recallPersistenceService.saveSession(session);
      // Update mastery records.
      await _recallPersistenceService.updateMasteryAfterSession(
        _canvasId,
        session,
      );
    }

    _recallModeController.deactivate();
    setState(() {
      _showRecallSummary = false;
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FREE → SPATIAL TRANSITION (P2-41)
  // ─────────────────────────────────────────────────────────────────────────

  /// Switches from Free Recall to Spatial Recall (unidirectional).
  void switchRecallToSpatial() {
    HapticFeedback.mediumImpact();
    _recallModeController.switchToSpatial();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PEEK (P2-16, P2-66 → P2-70)
  // ─────────────────────────────────────────────────────────────────────────

  /// Handles long-press on a blurred node to peek.
  void handleRecallPeek(String clusterId) {
    if (!_recallModeController.isActive) return;
    if (_recallModeController.isComparing) return;

    HapticFeedback.lightImpact();
    final started = _recallModeController.peekNode(clusterId);

    if (started && _recallModeController.shouldShowPeekWarning) {
      // The overlay will show the warning automatically.
      HapticFeedback.heavyImpact();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // "NON RICORDO" MARKER (P2-14, P2-15)
  // ─────────────────────────────────────────────────────────────────────────

  /// Double-tap handler for creating a "non ricordo" marker.
  void handleRecallDoubleTap(Offset screenPosition) {
    if (!_recallModeController.isActive) return;
    if (_recallModeController.isComparing) return;

    final canvasPos = _canvasController.screenToCanvas(screenPosition);
    HapticFeedback.mediumImpact();
    _recallModeController.addMissedMarker(canvasPos);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // COMPARISON (P2-23 → P2-30)
  // ─────────────────────────────────────────────────────────────────────────

  /// Starts the comparison phase — reveals original and evaluates gaps.
  void startRecallComparison() {
    if (!_recallModeController.isActive) return;
    if (_recallModeController.isComparing) return;

    HapticFeedback.heavyImpact();

    // Gather reconstructed clusters (current canvas content in the zone).
    final zone = _recallModeController.selectedZone;
    if (zone == null) return;

    final reconstructedClusters = _clusterCache
        .where((c) =>
            zone.overlaps(c.bounds) || zone.contains(c.centroid))
        .where((c) =>
            // Exclude original clusters — only new ones.
            !_recallModeController.originalClusters
                .any((oc) => oc.id == c.id))
        .toList();

    _recallModeController.startComparison(reconstructedClusters);
  }

  /// Navigates to a specific gap cluster during comparison.
  void navigateToRecallGap(String clusterId) {
    final cluster = _clusterCache
        .where((c) => c.id == clusterId)
        .firstOrNull;
    if (cluster == null) return;

    HapticFeedback.lightImpact();

    // Pan canvas to center on the gap cluster.
    final screenSize = MediaQuery.sizeOf(context);
    final scale = _canvasController.scale;
    final targetOffset = Offset(
      screenSize.width / 2 - cluster.centroid.dx * scale,
      screenSize.height / 2 - cluster.centroid.dy * scale,
    );
    _canvasController.animateOffsetTo(targetOffset);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SUMMARY (P2-58 → P2-61)
  // ─────────────────────────────────────────────────────────────────────────

  /// Shows the recall summary overlay.
  void showRecallSummary() {
    HapticFeedback.mediumImpact();
    setState(() => _showRecallSummary = true);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TRANSITION TO STEP 3 (P2-35, P2-36)
  // ─────────────────────────────────────────────────────────────────────────

  /// Transitions to Step 3 (Socratic Interrogation) with the gap map.
  void transitionToStep3Socratic() {
    final gapMap = _recallModeController.getGapMapForStep3();
    if (gapMap == null || gapMap.isEmpty) {
      debugPrint('🧠 No gaps to pass to Step 3');
      return;
    }

    HapticFeedback.heavyImpact();

    // Save the current session.
    deactivateRecallMode();

    // Advance to Step 3.
    _learningStepController.advanceTo(LearningStep.step3Socratic);

    // TODO: Pass gapMap to the Socratic controller when implemented.
    debugPrint('🧠 Step 3 transition — gap map: ${gapMap.length} entries');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // REPEAT (P2 retry)
  // ─────────────────────────────────────────────────────────────────────────

  /// Resets and repeats the recall session for the same zone.
  void repeatRecallSession() {
    final zone = _recallModeController.selectedZone;
    final phase = _recallModeController.isSpatialRecall
        ? RecallPhase.spatialRecall
        : RecallPhase.freeRecall;

    // Deactivate first (saves current session).
    deactivateRecallMode();

    // Re-activate with the same zone.
    if (zone != null) {
      activateRecallMode(zone, phase);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // OVERLAY BUILDERS (called from _build_ui.dart)
  // ─────────────────────────────────────────────────────────────────────────

  /// Build all recall mode overlay widgets.
  ///
  /// Returns a list of widgets to add to the canvas Stack.
  List<Widget> buildRecallModeOverlays(BuildContext context) {
    final widgets = <Widget>[];

    // Zone selector.
    if (_showRecallZoneSelector) {
      widgets.add(
        RecallZoneSelector(
          key: const ValueKey('recall_zone_selector'),
          allClusters: _clusterCache,
          canvasController: _canvasController,
          onZoneSelected: activateRecallMode,
          onDismiss: () => setState(() => _showRecallZoneSelector = false),
        ),
      );
      return widgets; // Don't render anything else during selection.
    }

    if (!_recallModeController.isActive) return widgets;

    // Main recall mode overlay (HUD + blobs).
    if (!_recallModeController.isComparing) {
      widgets.add(
        RecallModeOverlay(
          key: const ValueKey('recall_mode_overlay'),
          controller: _recallModeController,
          canvasController: _canvasController,
          onSwitchToSpatial: switchRecallToSpatial,
          onStartComparison: startRecallComparison,
          onExit: deactivateRecallMode,
        ),
      );
    }

    // Missed markers.
    for (final marker in _recallModeController.missedMarkers) {
      final screenPos = _canvasController.canvasToScreen(marker.position);
      widgets.add(
        RecallMissedMarkerWidget(
          key: ValueKey('recall_missed_${marker.id}'),
          marker: marker,
          screenPosition: screenPos,
          scale: _canvasController.scale,
          onTap: () {
            HapticFeedback.lightImpact();
            _recallModeController.removeMissedMarker(marker.id);
          },
        ),
      );
    }

    // Peek overlay (active peek).
    if (_recallModeController.activePeekClusterId != null) {
      final peekId = _recallModeController.activePeekClusterId!;
      final cluster = _recallModeController.originalClusters
          .where((c) => c.id == peekId)
          .firstOrNull;
      if (cluster != null) {
        final screenPos = _canvasController.canvasToScreen(cluster.centroid);
        final scale = _canvasController.scale;
        final peekNumber = _recallModeController.sessionPeekCount;
        widgets.add(
          RecallPeekOverlay(
            key: ValueKey('recall_peek_$peekId'),
            controller: _recallModeController,
            screenPosition: screenPos,
            nodeSize: Size(
              cluster.bounds.width * scale,
              cluster.bounds.height * scale,
            ),
            peekDuration: _peekDuration(peekNumber),
            peekNumber: peekNumber,
          ),
        );
      }
    }

    // Comparison overlay.
    if (_recallModeController.isComparing) {
      widgets.add(
        RecallComparisonOverlay(
          key: const ValueKey('recall_comparison_overlay'),
          controller: _recallModeController,
          canvasController: _canvasController,
          onNavigateToGap: navigateToRecallGap,
          onShowSummary: showRecallSummary,
          onStartSocratic: transitionToStep3Socratic,
        ),
      );
    }

    // Summary overlay.
    if (_showRecallSummary) {
      widgets.add(
        Positioned.fill(
          child: RecallSummaryOverlay(
            key: const ValueKey('recall_summary_overlay'),
            controller: _recallModeController,
            onStartSocratic: transitionToStep3Socratic,
            onDismiss: deactivateRecallMode,
            onRepeat: repeatRecallSession,
          ),
        ),
      );
    }

    return widgets;
  }

  /// Peek duration for a given peek number.
  Duration _peekDuration(int peekNumber) {
    switch (peekNumber) {
      case 1:
        return const Duration(milliseconds: 3000);
      case 2:
        return const Duration(milliseconds: 2000);
      case 3:
        return const Duration(milliseconds: 1500);
      default:
        return const Duration(milliseconds: 1000);
    }
  }
}
