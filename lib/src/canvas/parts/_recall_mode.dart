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

    // 🚦 A15: Step prerequisite gate for Step 2.
    if (!_checkStepGate(LearningStep.step2Recall,
        onProceed: showRecallZoneSelector)) {
      return;
    }

    // Auto-advance to Step 2 if in Step 1.
    if (_learningStepController.currentStep == LearningStep.step1Notes) {
      _learningStepController.setStep(LearningStep.step2Recall);
    }

    // 🧠 Force-refresh cluster cache so freshly drawn strokes are detected.
    // Without this, the cache may be stale/empty → "0 nodi in zona".
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

      // 🔑 Apply bounds correction for reflow offsets (same as _lifecycle_helpers).
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

      debugPrint('🧠 Recall: ${_clusterCache.length} clusters, '
          '${activeLayer.strokes.length} strokes');
      for (final c in _clusterCache) {
        debugPrint('  📍 cluster ${c.id.substring(0, 8)} '
            'bounds=${c.bounds} centroid=${c.centroid} '
            'strokes=${c.strokeIds.length}');
      }
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

    // 🎵 A13.4: "Sipario che scende" — low 200Hz tone on recall activation
    PedagogicalSoundEngine.instance.play(PedagogicalSound.recallActivation);

    // 📸 Snapshot all current stroke IDs — anything added after this
    // point is "new" (drawn during recall) and should remain visible.
    _recallOriginalStrokeIds = _layerController
        .getAllVisibleStrokes()
        .map((s) => s.id)
        .toSet();

    // 🧠 Calculate adjacent reconstruction zone (to the right, 200px gap).
    const zoneGap = 200.0;
    _recallReconstructionZone = Rect.fromLTWH(
      zone.right + zoneGap,
      zone.top,
      zone.width,
      zone.height,
    );

    // 🧠 Force DrawingPainter reconstruction — it lives inside a late final
    // ListenableBuilder(listenable: _layerController) that only rebuilds
    // on _layerController notifications, not on setState.
    _layerController.notifyListeners();

    setState(() {
      _showRecallZoneSelector = false;
      _showRecallSummary = false;
    });

    // 📍 Auto-pan to reconstruction zone after a brief delay
    // so the zone selector dismissal animation completes.
    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted || !_recallModeController.isActive) return;
      final screenSize = MediaQuery.sizeOf(context);
      final scale = _canvasController.scale;
      final centerX = _recallReconstructionZone.center.dx;
      final centerY = _recallReconstructionZone.center.dy;
      final targetOffset = Offset(
        screenSize.width / 2 - centerX * scale,
        screenSize.height / 2 - centerY * scale,
      );
      _canvasController.animateOffsetTo(targetOffset);
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
      // 🚦 A15: Record Step 2 completion.
      _stepGateController.recordStepCompletion(LearningStep.step2Recall);
      _saveStepGateHistory();
    }

    _recallModeController.deactivate();
    _recallOriginalStrokeIds = const {};
    _recallNewStrokeIds = const {};
    _recallShowingOriginals = true;
    _recallReconstructionZone = Rect.zero;
    _recallBlankMarkers = [];
    _layerController.notifyListeners(); // Force DrawingPainter rebuild
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
    // No setState needed — RecallModeOverlay uses ListenableBuilder
    // on the controller, so it rebuilds automatically.
  }

  // ─────────────────────────────────────────────────────────────────────────
  // COMPARISON (P2-23 → P2-30)
  // ─────────────────────────────────────────────────────────────────────────

  /// Starts the comparison phase — reveals original and evaluates gaps.
  void startRecallComparison() {
    if (!_recallModeController.isActive) return;
    if (_recallModeController.isComparing) return;

    HapticFeedback.heavyImpact();

    // Gather reconstructed clusters from the RECONSTRUCTION zone
    // (adjacent to original — that's where the student wrote).
    final reconstructedClusters = _clusterCache
        .where((c) =>
            _recallReconstructionZone.overlaps(c.bounds) ||
            _recallReconstructionZone.contains(c.centroid))
        .where((c) =>
            // Exclude original clusters — only new ones.
            !_recallModeController.originalClusters
                .any((oc) => oc.id == c.id))
        .toList();

    _recallModeController.startComparison(reconstructedClusters);

    // 🧠 COMPARISON: compute new stroke IDs for reference.
    final allCurrentIds = _layerController
        .getAllVisibleStrokes()
        .map((s) => s.id)
        .toSet();
    _recallNewStrokeIds = allCurrentIds.difference(_recallOriginalStrokeIds);

    // 🧠 With adjacent zones, no strokes need hiding during comparison.
    // Both original and reconstruction are spatially separated.
    // Clear the hidden set so originals become visible.
    _recallOriginalStrokeIds = const {};
    _layerController.notifyListeners(); // Force DrawingPainter to show originals

    // Default: split-view showing both zones.
    _recallShowingOriginals = true;
    _panToSplitView();
    setState(() {}); // Force main widget rebuild (comparison overlay)
  }

  /// Toggles comparison view: Split → Original → Tentativo → Split...
  void toggleRecallComparisonView() {
    HapticFeedback.mediumImpact();

    // Three-state cycle: split → original → reconstruction → split
    if (_recallShowingOriginals) {
      // Was split/original → show reconstruction only.
      _recallShowingOriginals = false;
      _panToReconstructionZone();
    } else {
      // Was reconstruction → back to split view.
      _recallShowingOriginals = true;
      _panToSplitView();
    }

    setState(() {});
  }

  /// Handles horizontal swipe to toggle comparison views.
  void handleRecallSwipe(DragEndDetails details) {
    if (!_recallModeController.isComparing) return;
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 300) return; // Threshold.

    toggleRecallComparisonView();
  }

  /// Deletes all strokes drawn in the reconstruction zone.
  void deleteReconstructionStrokes() {
    if (_recallNewStrokeIds.isEmpty) return;
    HapticFeedback.heavyImpact();

    for (final strokeId in _recallNewStrokeIds) {
      _layerController.removeStroke(strokeId);
    }
    _recallNewStrokeIds = const {};
    _layerController.notifyListeners();
    setState(() {});
  }

  /// Zooms out to show both original and reconstruction zones.
  void _panToSplitView() {
    final zone = _recallModeController.selectedZone;
    if (zone == null || _recallReconstructionZone == Rect.zero) return;

    // Compute bounding rect that contains both zones.
    final combined = zone.expandToInclude(_recallReconstructionZone);
    final screenSize = MediaQuery.sizeOf(context);

    // Calculate scale to fit combined rect with padding.
    const padding = 80.0; // px padding on each side
    final scaleX = (screenSize.width - padding * 2) / combined.width;
    final scaleY = (screenSize.height - padding * 2) / combined.height;
    final targetScale = scaleX < scaleY ? scaleX : scaleY;

    // Center on the combined rect.
    final targetOffset = Offset(
      screenSize.width / 2 - combined.center.dx * targetScale,
      screenSize.height / 2 - combined.center.dy * targetScale,
    );

    _canvasController.animateToTransform(
      targetOffset: targetOffset,
      targetScale: targetScale,
    );
  }

  /// Pans camera to center on the original zone.
  void _panToOriginalZone() {
    final zone = _recallModeController.selectedZone;
    if (zone == null) return;
    final screenSize = MediaQuery.sizeOf(context);
    final scale = _canvasController.scale;
    final targetOffset = Offset(
      screenSize.width / 2 - zone.center.dx * scale,
      screenSize.height / 2 - zone.center.dy * scale,
    );
    _canvasController.animateOffsetTo(targetOffset);
  }

  /// Pans camera to center on the reconstruction zone.
  void _panToReconstructionZone() {
    if (_recallReconstructionZone == Rect.zero) return;
    final screenSize = MediaQuery.sizeOf(context);
    final scale = _canvasController.scale;
    final targetOffset = Offset(
      screenSize.width / 2 - _recallReconstructionZone.center.dx * scale,
      screenSize.height / 2 - _recallReconstructionZone.center.dy * scale,
    );
    _canvasController.animateOffsetTo(targetOffset);
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

    // 🧠 RENDERER-LEVEL HIDING: original strokes are hidden via
    // _recallOriginalStrokeIds → DrawingPainter.recallHiddenIds →
    // SceneGraphRenderer.recallHiddenIds. No visual mask overlay needed.
    // New strokes (not in the set) render normally. Spatial blobs and
    // zone border are drawn by RecallModeOverlay below.

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

      // 📝 Animated reconstruction zone border.
      if (_recallReconstructionZone != Rect.zero) {
        final topLeft = _canvasController.canvasToScreen(
          _recallReconstructionZone.topLeft,
        );
        final bottomRight = _canvasController.canvasToScreen(
          _recallReconstructionZone.bottomRight,
        );
        final screenRect = Rect.fromPoints(topLeft, bottomRight);

        widgets.add(
          _RecallReconstructionBorder(
            key: const ValueKey('reconstruction_border'),
            screenRect: screenRect,
          ),
        );
      }
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
      // 🌟 Zone labels in split-view.
      if (_recallShowingOriginals) {
        final origZone = _recallModeController.selectedZone;
        if (origZone != null) {
          // Label on original zone.
          final origLabelPos = _canvasController.canvasToScreen(
            Offset(origZone.center.dx, origZone.top - 30),
          );
          widgets.add(
            _RecallZoneLabel(
              key: const ValueKey('label_original'),
              screenPos: origLabelPos,
              text: '📄 Originale',
              color: const Color(0xFF007AFF),
            ),
          );

          // Label on reconstruction zone.
          if (_recallReconstructionZone != Rect.zero) {
            final reconLabelPos = _canvasController.canvasToScreen(
              Offset(
                _recallReconstructionZone.center.dx,
                _recallReconstructionZone.top - 30,
              ),
            );
            widgets.add(
              _RecallZoneLabel(
                key: const ValueKey('label_tentativo'),
                screenPos: reconLabelPos,
                text: '📝 Tentativo',
                color: const Color(0xFF30D158),
              ),
            );

            // Connection line between zones.
            final lineStart = _canvasController.canvasToScreen(
              Offset(origZone.right, origZone.center.dy),
            );
            final lineEnd = _canvasController.canvasToScreen(
              Offset(
                _recallReconstructionZone.left,
                _recallReconstructionZone.center.dy,
              ),
            );
            widgets.add(
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _ConnectionLinePainter(
                      start: lineStart,
                      end: lineEnd,
                    ),
                  ),
                ),
              ),
            );
          }
        }
      }

      // Swipe detector + comparison HUD.
      widgets.add(
        GestureDetector(
          key: const ValueKey('recall_swipe_detector'),
          behavior: HitTestBehavior.translucent,
          onHorizontalDragEnd: handleRecallSwipe,
          child: RecallComparisonOverlay(
            controller: _recallModeController,
            canvasController: _canvasController,
            onNavigateToGap: navigateToRecallGap,
            onShowSummary: showRecallSummary,
            onStartSocratic: transitionToStep3Socratic,
            onToggleView: toggleRecallComparisonView,
            showingOriginals: _recallShowingOriginals,
          ),
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
            onDeleteReconstruction: deleteReconstructionStrokes,
            hasReconstructionStrokes: _recallNewStrokeIds.isNotEmpty,
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

// ============================================================================
// 📝 Animated Reconstruction Zone Border
// ============================================================================

class _RecallReconstructionBorder extends StatefulWidget {
  final Rect screenRect;

  const _RecallReconstructionBorder({
    super.key,
    required this.screenRect,
  });

  @override
  State<_RecallReconstructionBorder> createState() =>
      _RecallReconstructionBorderState();
}

class _RecallReconstructionBorderState
    extends State<_RecallReconstructionBorder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.screenRect.left,
      top: widget.screenRect.top,
      child: IgnorePointer(
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _pulseController,
            builder: (_, __) {
              return CustomPaint(
                size: Size(widget.screenRect.width, widget.screenRect.height),
                painter: _AnimatedBorderPainter(
                  dashOffset: _pulseController.value * 40,
                  pulseOpacity: 0.3 + 0.15 * (0.5 + 0.5 *
                      (2 * _pulseController.value - 1).abs()),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AnimatedBorderPainter extends CustomPainter {
  final double dashOffset;
  final double pulseOpacity;

  _AnimatedBorderPainter({
    required this.dashOffset,
    required this.pulseOpacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Color.fromRGBO(108, 99, 255, pulseOpacity)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    // Soft fill.
    final fill = Paint()
      ..color = const Color(0xFF6C63FF).withValues(alpha: 0.03)
      ..style = PaintingStyle.fill;

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rRect = RRect.fromRectAndRadius(rect, const Radius.circular(16));

    canvas.drawRRect(rRect, fill);

    // Animated dashed border.
    final path = Path()..addRRect(rRect);
    final dashPath = _createDashPath(
      path,
      dashLength: 12.0,
      gapLength: 8.0,
      offset: dashOffset,
    );
    canvas.drawPath(dashPath, paint);

    // Label "📝 Ricostruisci da memoria" at top center.
    final textPainter = TextPainter(
      text: const TextSpan(
        text: '📝 Ricostruisci da memoria',
        style: TextStyle(
          color: Color(0xFF6C63FF),
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final labelW = textPainter.width + 24;
    final labelH = textPainter.height + 12;
    final labelX = (size.width - labelW) / 2;
    const labelY = 12.0;

    final labelBg = Paint()
      ..color = const Color(0xFF0A0A14).withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(labelX, labelY, labelW, labelH),
        const Radius.circular(8),
      ),
      labelBg,
    );

    textPainter.paint(canvas, Offset(labelX + 12, labelY + 6));
  }

  @override
  bool shouldRepaint(_AnimatedBorderPainter oldDelegate) =>
      dashOffset != oldDelegate.dashOffset ||
      pulseOpacity != oldDelegate.pulseOpacity;

  Path _createDashPath(
    Path source, {
    required double dashLength,
    required double gapLength,
    double offset = 0,
  }) {
    final dest = Path();
    for (final metric in source.computeMetrics()) {
      double distance = offset % (dashLength + gapLength);
      while (distance < metric.length) {
        final len = dashLength.clamp(0, metric.length - distance);
        dest.addPath(
          metric.extractPath(distance, distance + len),
          Offset.zero,
        );
        distance += dashLength + gapLength;
      }
    }
    return dest;
  }
}


// ============================================================================
// 📄 Zone Label — floating label above each zone in split-view
// ============================================================================

class _RecallZoneLabel extends StatelessWidget {
  final Offset screenPos;
  final String text;
  final Color color;

  const _RecallZoneLabel({
    super.key,
    required this.screenPos,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: screenPos.dx - 60,
      top: screenPos.dy - 12,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xE60A0A14),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: color.withValues(alpha: 0.5),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.15),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// ── Connection Line Painter — dotted line between zones in split-view
// ============================================================================

class _ConnectionLinePainter extends CustomPainter {
  final Offset start;
  final Offset end;

  // Pre-computed for arrowAngle = 0.5 rad (~28.6°)
  static final double _cosA = math.cos(0.5);
  static final double _sinA = math.sin(0.5);

  _ConnectionLinePainter({required this.start, required this.end});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF6C63FF).withValues(alpha: 0.25)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Dotted line.
    const dashLen = 6.0;
    const gapLen = 6.0;
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final distance = (Offset(dx, dy)).distance;
    if (distance < 1) return;

    final unitX = dx / distance;
    final unitY = dy / distance;

    double d = 0;
    while (d < distance) {
      final segEnd = (d + dashLen).clamp(0, distance);
      canvas.drawLine(
        Offset(start.dx + unitX * d, start.dy + unitY * d),
        Offset(start.dx + unitX * segEnd, start.dy + unitY * segEnd),
        paint,
      );
      d += dashLen + gapLen;
    }

    // Arrow at end (pre-computed trig).
    const arrowSize = 8.0;
    final ax1 = end.dx - arrowSize * (unitX * _cosA - unitY * _sinA);
    final ay1 = end.dy - arrowSize * (unitX * _sinA + unitY * _cosA);
    final ax2 = end.dx - arrowSize * (unitX * _cosA + unitY * _sinA);
    final ay2 = end.dy - arrowSize * (-unitX * _sinA + unitY * _cosA);

    final arrowPaint = Paint()
      ..color = const Color(0xFF6C63FF).withValues(alpha: 0.35)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawLine(end, Offset(ax1, ay1), arrowPaint);
    canvas.drawLine(end, Offset(ax2, ay2), arrowPaint);
  }

  @override
  bool shouldRepaint(_ConnectionLinePainter oldDelegate) =>
      start != oldDelegate.start || end != oldDelegate.end;
}
