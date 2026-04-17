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
    }

    // R1: Guard — empty canvas → show message instead of zone selector.
    if (_clusterCache.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_l10n.recall_needNotes),
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
      setState(() => _showRecallZoneSelector = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_l10n.recall_needNotes),
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

    // R1: Guard — controller rejected activation (< minNodesForRecall).
    if (!_recallModeController.isActive) {
      setState(() => _showRecallZoneSelector = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_l10n.recall_needMoreNotes),
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
    // Release the per-session TextPainter layout cache; freed once per session
    // (~35 entries). Called here so the controller stays UI-rendering agnostic.
    RecallNodeOverlayPainter.clearTextPainterCache();
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
  Future<void> startRecallComparison() async {
    if (!_recallModeController.isActive) return;
    if (_recallModeController.isComparing) return;

    HapticFeedback.heavyImpact();

    final allCurrentIds = _layerController
        .getAllVisibleStrokes()
        .map((s) => s.id)
        .toSet();
    _recallNewStrokeIds = allCurrentIds.difference(_recallOriginalStrokeIds);

    final rawReconstructedClusters = _clusterCache
        .where((c) => c.strokeIds.any((id) => _recallNewStrokeIds.contains(id)))
        .where((c) =>
            !_recallModeController.originalClusters
                .any((oc) => oc.id == c.id))
        .toList();

    // Filter out trivial clusters (noise marks, stray dots, underscores).
    // A single short stroke shouldn't count as a recall attempt.
    final reconstructedClusters = rawReconstructedClusters.where((c) {
      if (c.strokeIds.length == 1) {
        final area = c.bounds.width * c.bounds.height;
        if (area < 200) return false;
      }
      return true;
    }).toList();

    // ── Force OCR on reconstructed clusters ──
    // The semantic title OCR only runs at zoom < 0.20, so newly-drawn
    // clusters in the reconstruction zone will NOT have text in the cache.
    // We force-recognize them here before matching.
    final inkService = DigitalInkService.instance;
    if (inkService.isAvailable && reconstructedClusters.isNotEmpty) {
      final activeLayer = _layerController.layers.firstWhere(
        (l) => l.id == _layerController.activeLayerId,
        orElse: () => _layerController.layers.first,
      );
      final strokeMap = <String, ProStroke>{};
      for (final s in activeLayer.strokes) {
        strokeMap[s.id] = s;
      }

      final futures = <Future<void>>[];
      for (final cluster in reconstructedClusters) {
        // Skip if already recognized.
        if (_clusterTextCache.containsKey(cluster.id) &&
            _clusterTextCache[cluster.id]!.trim().isNotEmpty) {
          continue;
        }

        final strokeSets = <List<ProDrawingPoint>>[];
        for (final sid in cluster.strokeIds) {
          final stroke = strokeMap[sid];
          if (stroke != null && !stroke.isStub && stroke.points.length >= 3) {
            strokeSets.add(stroke.points);
          }
        }
        if (strokeSets.isEmpty) continue;

        final clusterId = cluster.id;
        futures.add(
          inkService.engine.recognizeTextMode(strokeSets).then((recognized) {
            if (recognized != null && recognized.trim().isNotEmpty) {
              _clusterTextCache[clusterId] = recognized.trim();
            }
          }),
        );
      }
      if (futures.isNotEmpty) {
        await Future.wait(futures);
      }
    }

    // Also force OCR on ORIGINAL clusters that might not have text yet.
    if (inkService.isAvailable) {
      final activeLayer = _layerController.layers.firstWhere(
        (l) => l.id == _layerController.activeLayerId,
        orElse: () => _layerController.layers.first,
      );
      final strokeMap = <String, ProStroke>{};
      for (final s in activeLayer.strokes) {
        strokeMap[s.id] = s;
      }

      final ocrFutures = <Future<void>>[];
      for (final oc in _recallModeController.originalClusters) {
        if (_clusterTextCache.containsKey(oc.id) &&
            _clusterTextCache[oc.id]!.trim().isNotEmpty) {
          continue;
        }

        final strokeSets = <List<ProDrawingPoint>>[];
        for (final sid in oc.strokeIds) {
          final stroke = strokeMap[sid];
          if (stroke != null && !stroke.isStub && stroke.points.length >= 3) {
            strokeSets.add(stroke.points);
          }
        }
        if (strokeSets.isEmpty) continue;

        final clusterId = oc.id;
        ocrFutures.add(
          inkService.engine.recognizeTextMode(strokeSets).then((recognized) {
            if (recognized != null && recognized.trim().isNotEmpty) {
              _clusterTextCache[clusterId] = recognized.trim();
            }
          }),
        );
      }
      if (ocrFutures.isNotEmpty) {
        await Future.wait(ocrFutures);
      }
    }

    // 💾 Compute bounding rect of new strokes for "attempt" camera pan.
    if (reconstructedClusters.isNotEmpty) {
      _recallAttemptBounds = reconstructedClusters
          .map((c) => c.bounds)
          .reduce((a, b) => a.expandToInclude(b));
    } else {
      // User didn't draw enough new clusters — fall back to original zone.
      _recallAttemptBounds = _recallModeController.selectedZone;
    }

    // Calculate the offset from original zone to reconstruction zone.
    final origZone = _recallModeController.selectedZone;
    final reconstructionOffset = origZone != null
        ? _recallReconstructionZone.topLeft - origZone.topLeft
        : Offset.zero;

    _recallModeController.startComparison(
      reconstructedClusters,
      reconstructionZoneOffset: reconstructionOffset,
      clusterTextMap: _clusterTextCache,
    );

    _recallOriginalStrokeIdsBackup = _recallOriginalStrokeIds;
    _recallOriginalStrokeIds = const {};
    _layerController.notifyListeners();

    _recallShowingOriginals = true;
    _panToOriginalZone();
    setState(() {});
  }

  /// Toggles comparison view: Originale ↔ Tentativo (in-place, no pan).
  ///
  /// • Comparison (showingOriginals=true): original strokes visible + color overlays.
  /// • Attempt (showingOriginals=false): original strokes hidden, only new visible.
  void toggleRecallComparisonView() {
    HapticFeedback.mediumImpact();
    _recallShowingOriginals = !_recallShowingOriginals;

    if (_recallShowingOriginals) {
      // Comparison view: reveal all originals + pan to full zone.
      _recallOriginalStrokeIds = const {};
      _panToOriginalZone();
    } else {
      // Attempt view: hide originals + zoom into user's new strokes.
      _recallOriginalStrokeIds = _recallOriginalStrokeIdsBackup;
      _panToAttemptZone();
    }
    _layerController.notifyListeners();
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

  /// Zooms to show both original and reconstruction zones side-by-side.
  ///
  /// Uses width-first fitting (the two zones are horizontal neighbours)
  /// with a minimum scale floor so it never dezoom below a readable level.
  void _panToSplitView() {
    final zone = _recallModeController.selectedZone;
    if (zone == null || _recallReconstructionZone == Rect.zero) return;

    final combined = zone.expandToInclude(_recallReconstructionZone);
    final screenSize = MediaQuery.sizeOf(context);

    // Adaptive padding: tighter on small screens.
    final hPad = screenSize.width < 500 ? 32.0 : 48.0;
    final vPad = screenSize.height < 900 ? 80.0 : 100.0;

    // Fit scale — width-first because zones are placed side by side.
    final scaleX = (screenSize.width - hPad * 2) / combined.width;
    final scaleY = (screenSize.height - vPad * 2) / combined.height;

    // Prefer width fit; only use height fit if it's significantly smaller.
    // This prevents extreme dezoom when the combined height is very large.
    final rawScale = (scaleY < scaleX * 0.6) ? scaleY : scaleX;

    // Clamp: never below 0.45 (readable) or above 1.5 (nothing to show).
    final targetScale = rawScale.clamp(0.45, 1.5);

    // Center on the horizontal midpoint of both zones, vertically
    // bias toward top of combined rect so active content is visible.
    final centerX = combined.center.dx;
    final centerY = combined.top + (combined.height * 0.45);

    final targetOffset = Offset(
      screenSize.width / 2 - centerX * targetScale,
      screenSize.height / 2 - centerY * targetScale,
    );

    _canvasController.animateToTransform(
      targetOffset: targetOffset,
      targetScale: targetScale,
    );
  }

  /// Pans camera to fit the original zone on screen at a comfortable zoom.
  void _panToOriginalZone() {
    final zone = _recallModeController.selectedZone;
    if (zone == null) return;
    _panToZone(zone, label: 'original');
  }

  /// Pans camera to show the user's reconstruction attempt in context.
  ///
  /// Uses the tight cluster bounding box as center, zooming the
  /// reconstruction zone to fill the viewport horizontally.
  void _panToAttemptZone() {
    // HORIZONTAL-ONLY PAN: Y stays frozen, only X changes.
    // Anchor: align the reconstruction zone LEFT EDGE to the screen left edge
    // so the full reconstruction zone is visible. The attempt cluster appears
    // near the left portion of screen, and the rest of the zone to the right.
    final screenSize = MediaQuery.sizeOf(context);
    _canvasController.stopAnimation();
    final scale = _canvasController.scale;

    final double centerX;
    if (_recallReconstructionZone != Rect.zero) {
      // Left edge of reconstruction zone at screen left → zone fills screen.
      final halfScreenCanvas = screenSize.width / (2 * scale);
      centerX = _recallReconstructionZone.left + halfScreenCanvas;
    } else {
      final bounds = _recallAttemptBounds;
      if (bounds == null) return;
      centerX = bounds.center.dx;
    }

    final targetOffset = Offset(
      screenSize.width / 2 - centerX * scale,
      _canvasController.offset.dy, // ← Y: unchanged (pure horizontal slide)
    );
    _canvasController.animateOffsetTo(targetOffset);
  }

  /// Pans camera to fit the reconstruction zone on screen at a comfortable zoom.
  void _panToReconstructionZone() {
    if (_recallReconstructionZone == Rect.zero) return;
    _panToZone(_recallReconstructionZone, label: 'reconstruction');
  }

  /// Shared helper: animates camera to fit [zone] on screen.
  ///
  /// Uses [animateDiveTo] which lerps BOTH offset and scale simultaneously
  /// via [Offset.lerp] — it always reaches the exact target position.
  ///
  /// ⚠️  Do NOT use [animateToTransform] here: with [_isTransformSpringActive]
  /// the offset update is skipped (`if (!_isTransformSpringActive)`) and the
  /// zoom spring anchors to [Offset.zero], making the camera drift sideways.
  void _panToZone(Rect zone, {String label = ''}) {
    final screenSize = MediaQuery.sizeOf(context);
    // Add 10% horizontal and 15% vertical padding by inflating the zone so
    // animateDiveTo produces the same visual margins as before.
    final inflated = Rect.fromLTRB(
      zone.left   - zone.width  * 0.125,
      zone.top    - zone.height * 0.088,
      zone.right  + zone.width  * 0.125,
      zone.bottom + zone.height * 0.088,
    );
    _canvasController.animateDiveTo(
      nodeWorldRect: inflated,
      viewportSize: screenSize,
      durationSeconds: 0.45,
    );
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

      return;
    }

    HapticFeedback.heavyImpact();

    // Save the current session.
    deactivateRecallMode();

    // Advance to Step 3.
    _learningStepController.advanceTo(LearningStep.step3Socratic);

    // TODO: Pass gapMap to the Socratic controller when implemented.

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

      // 📝 Reconstruction zone dashed border is now painted by
      // RecallNodeOverlayPainter in canvas space (inside the Transform
      // stack in _buildCanvasArea). See _ui_canvas_layer.dart.
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
      // 🌟 Zone labels + connection line are now painted by
      // RecallNodeOverlayPainter in canvas space (inside the Transform
      // stack in _buildCanvasArea), so they track strokes perfectly
      // during zoom/pan. See _ui_canvas_layer.dart.

      // Comparison HUD — Positioned.fill with translucent hit testing
      // so pinch-to-zoom passes through to InfiniteCanvasGestureDetector.
      // 🗑️ Swipe-to-toggle removed: competed with ScaleGestureRecognizer.
      //    Use the toggle button in the navigation bar instead.
      widgets.add(
        Positioned.fill(
          child: RecallComparisonOverlay(
            key: const ValueKey('recall_swipe_detector'),
            controller: _recallModeController,
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

