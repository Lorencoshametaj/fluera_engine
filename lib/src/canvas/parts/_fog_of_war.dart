part of '../fluera_canvas_screen.dart';

// ============================================================================
// 🌫️ FOG OF WAR — Step 10 (Preparazione all'Esame) integration
//
// This extension wires the FogOfWarController into the canvas screen,
// providing all the glue logic between the controller, overlays, and
// the existing canvas infrastructure (clusters, gestures, toolbar).
//
// AI STATE: 💤 DORMANT — no AI calls. All logic is spatial and local.
//
// Spec: P10-01 → P10-29
//
// ❌ ANTI-PATTERNS:
//   P10-10: No timer/countdown
//   P10-11: No node counter during session
//   P10-12: No feedback during exploration
// ============================================================================

extension FogOfWarWiring on _FlueraCanvasScreenState {

  // ─────────────────────────────────────────────────────────────────────────
  // SETUP (P10-01, P10-02, P10-03)
  // ─────────────────────────────────────────────────────────────────────────

  /// Opens the Fog of War setup — fog level picker + zone selection.
  ///
  /// Called from toolbar button. Shows a bottom sheet with 3 fog levels,
  /// then transitions to zone selection.
  void showFogOfWarSetup() {
    // Guard: don't open if already active.
    if (_fogOfWarController.isActive) return;
    if (_recallModeController.isActive) return; // Conflict guard.

    // 🚦 A15: Step prerequisite gate for Step 10.
    if (!_checkStepGate(LearningStep.step10FogOfWar,
        onProceed: showFogOfWarSetup)) {
      return;
    }

    // 💳 A17: Tier gate — Free users get 1 FoW session/zone.
    final fowZoneId = 'fow_$_canvasId';
    if (!_checkTierGate(GatedFeature.fogOfWarSession, zoneId: fowZoneId)) {
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

    if (_clusterCache.length < 3) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              FlueraLocalizations.of(context)?.fow_needAtLeast3 ?? 'Servono almeno 3 gruppi di appunti per la Sfida ⚔️',
            ),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin:
                const EdgeInsets.only(bottom: 80, left: 20, right: 20),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    // Show fog level picker bottom sheet.
    _showFogLevelPicker();
  }

  /// Shows the fog level picker bottom sheet with zone selection (P10-02).
  void _showFogLevelPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _FogSetupSheet(
        clusterCount: _clusterCache.length,
        canvasId: _canvasId,
        onStart: (level, useZoneSelection) {
          Navigator.pop(ctx);
          if (useZoneSelection) {
            _startFogWithZoneSelection(level);
          } else {
            _startFogWithLevel(level);
          }
        },
      ),
    );
  }

  /// Starts the fog with the selected level, using all clusters in the canvas.
  void _startFogWithLevel(FogLevel level) {
    // Use the bounding rect of all clusters as the zone.
    if (_clusterCache.isEmpty) return;

    Rect zone = _clusterCache.first.bounds;
    for (final cluster in _clusterCache.skip(1)) {
      zone = zone.expandToInclude(cluster.bounds);
    }
    // Inflate zone for visual padding.
    zone = zone.inflate(100.0);

    activateFogOfWar(zone, _clusterCache, level);
  }

  /// P10-02: Start zone-selection mode — the student draws a rectangle,
  /// then fog activates only within that area.
  void _startFogWithZoneSelection(FogLevel level) {
    _pendingFogLevel = level;

    // Ensure zoom is above 50% — the gesture detector's overview guard
    // blocks draw gestures at ≤50%, which would prevent rectangle drawing.
    if (_canvasController.scale <= 0.5) {
      _canvasController.setScale(0.6);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            FlueraLocalizations.of(context)?.fow_zoneSelectionHint ?? '📐 Traccia un rettangolo per selezionare l\'area da testare',
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.only(bottom: 80, left: 20, right: 20),
          duration: const Duration(seconds: 5),
          backgroundColor: const Color(0xFF37474F),
          action: SnackBarAction(
            label: FlueraLocalizations.of(context)?.fow_zoneSelectionWholeCanvas ?? 'Tutta la canvas',
            textColor: Colors.white70,
            onPressed: () {
              _pendingFogLevel = null;
              _startFogWithLevel(level);
            },
          ),
        ),
      );
    }

    // Activate section-style area selection.
    // The fog will start when the student completes the gesture.
    setState(() {});
  }

  /// P10-02: Called when the student completes a zone selection gesture.
  /// Filters clusters to only those within the selected area.
  void completeFogZoneSelection(Rect zone) {
    final level = _pendingFogLevel;
    if (level == null) return;
    _pendingFogLevel = null;

    // Dismiss the "draw a rectangle" snackbar.
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }

    // Filter clusters to those within the selected zone.
    final clustersInZone = _clusterCache
        .where((c) => zone.overlaps(c.bounds))
        .toList();

    if (clustersInZone.length < 3) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              FlueraLocalizations.of(context)?.fow_zoneTooFewNodes(clustersInZone.length)
                  ?? 'Solo ${clustersInZone.length} nodi nell\'area — servono almeno 3. Prova un\'area più grande.',
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

    // Inflate zone for visual padding and activate.
    activateFogOfWar(zone.inflate(50.0), clustersInZone, level);
  }

  /// Whether we're waiting for the student to select a zone (P10-02).
  bool get isFogZoneSelectionPending => _pendingFogLevel != null;

  // ─────────────────────────────────────────────────────────────────────────
  // ACTIVATION
  // ─────────────────────────────────────────────────────────────────────────

  /// Activates Fog of War with the given zone and fog level.
  Future<void> activateFogOfWar(
    Rect zone,
    List<ContentCluster> clusters,
    FogLevel fogLevel,
  ) async {
    _fogOfWarController.activate(
      zone: zone,
      clustersInZone: clusters,
      canvasId: _canvasId,
      fogLevel: fogLevel,
    );

    // 🧠 Partial Zone Memory (E): Load prior failure IDs from same zone.
    // Awaited so markers are ready before the first paint frame.
    await _loadPriorFailureIds(zone);

    // Start animation ticker for medium fog visibility effects.
    _fogOfWarAnimController?.repeat();

    // Force layer rebuild for the overlay painter.
    _layerController.notifyListeners();

    setState(() {});

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            FlueraLocalizations.of(context)?.fow_fogActive(
                _fogOfWarController.localizedFogLevelLabel(FlueraLocalizations.of(context)))
                ?? '⚔️ Sfida attiva — ${_fogOfWarController.fogLevelLabel}',
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin:
              const EdgeInsets.only(bottom: 80, left: 20, right: 20),
          duration: const Duration(seconds: 3),
          backgroundColor: const Color(0xFF37474F),
        ),
      );
    }
  }

  /// 🧠 Partial Zone Memory: Load failed node IDs from previous session
  /// in the same zone for cross-session continuity markers.
  Future<void> _loadPriorFailureIds(Rect zone) async {
    try {
      final kv = await KeyValueStore.getInstance();
      final raw = kv.getString(_fogHistoryKey);
      if (raw == null || raw.isEmpty) return;

      final history = (jsonDecode(raw) as List<dynamic>)
          .cast<Map<String, dynamic>>();
      if (history.isEmpty) return;

      // Find the most recent session matching this zone.
      final zoneId =
          'zone_${zone.left.toInt()}_${zone.top.toInt()}_'
          '${zone.width.toInt()}_${zone.height.toInt()}';

      Map<String, dynamic>? priorSession;
      for (int i = history.length - 1; i >= 0; i--) {
        if (history[i]['zone'] == zoneId) {
          priorSession = history[i];
          break;
        }
      }
      if (priorSession == null) return;

      // Extract failed node IDs.
      final nodeResults = priorSession['nodeResults'] as List<dynamic>?;
      if (nodeResults == null) return;

      final failedIds = <String>{};
      for (final node in nodeResults) {
        if (node is Map<String, dynamic>) {
          final status = node['status'] as String?;
          final id = node['clusterId'] as String?;
          if (id != null && (status == 'forgotten' || status == 'blindSpot')) {
            failedIds.add(id);
          }
        }
      }

      if (failedIds.isNotEmpty && mounted) {
        _fogOfWarController.priorFailureNodeIds = failedIds;
        debugPrint(
          '🧠 FoW Partial Zone Memory: ${failedIds.length} prior failures loaded',
        );
      }
    } catch (e) {
      debugPrint('⚠️ FoW prior failure load error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAP HANDLING (P10-05, P10-06, P10-07)
  // ─────────────────────────────────────────────────────────────────────────

  /// Handle a tap on the fog overlay.
  ///
  /// Returns `true` if the tap was consumed, `false` otherwise.
  bool handleFogOfWarTap(Offset canvasPosition) {
    if (!_fogOfWarController.isActive) return false;

    // During mastery map — tap on red/grey nodes to mark as "reviewed"
    // and zoom in for a closer look. Content is already visible after the
    // cinematic reveal — the tap is for NAVIGATION + ACKNOWLEDGEMENT,
    // not for "revealing" anything.
    if (_fogOfWarController.isMasteryMap) {
      final result = _fogOfWarController.handleMasteryMapTap(
        canvasPosition,
        canvasScale: _canvasController.scale,
      );
      if (result != null) {
        HapticFeedback.mediumImpact();
        _fogOfWarVersionNotifier.value++;

        // P10-21: Contextual snackbar — focus on actionable insight.
        if (mounted) {
          final l10n = FlueraLocalizations.of(context);
          final message = result.status == FogNodeStatus.blindSpot
              ? (l10n?.fow_masteryMapBlindSpotAction ?? '👁‍🗨 Non l\'avevi cercato — rileggilo con attenzione')
              : (l10n?.fow_masteryMapForgottenAction ?? '📝 Dimenticato — rileggilo e prova a riscriverlo a memoria');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              margin: const EdgeInsets.only(
                bottom: 80, left: 20, right: 20,
              ),
              duration: const Duration(seconds: 3),
              backgroundColor: result.status == FogNodeStatus.blindSpot
                  ? const Color(0xFF546E7A)
                  : const Color(0xFF5D4037),
            ),
          );

          // Zoom to the node so it's readable at the center of the screen.
          ContentCluster? tappedCluster;
          for (final c in _clusterCache) {
            if (c.id == result.clusterId) {
              tappedCluster = c;
              break;
            }
          }
          if (tappedCluster != null) {
            final viewportSize = MediaQuery.of(context).size;

            // Save current camera state to return to it smoothly.
            final savedOffset = _canvasController.offset;
            final savedScale = _canvasController.scale;

            CameraActions.zoomToRect(
              _canvasController,
              tappedCluster.bounds.inflate(120.0),
              viewportSize,
            );

            // Return to previous view after 4 seconds of reading.
            _fogZoomBackTimer?.cancel();
            _fogZoomBackTimer = Timer(const Duration(seconds: 4), () {
              if (mounted && _fogOfWarController.isMasteryMap) {
                _canvasController.animateToTransform(
                  targetOffset: savedOffset,
                  targetScale: savedScale,
                  focalPoint: Offset(
                    viewportSize.width / 2,
                    viewportSize.height / 2,
                  ),
                );
              }
            });
          }
        }
        return true;
      }
      return false;
    }

    // During active fog — hit-test against hidden clusters.
    if (_fogOfWarController.isFogActive) {
      final clusterId = _fogOfWarController.handleTap(
        canvasPosition,
        canvasScale: _canvasController.scale,
      );
      if (clusterId != null) {
        HapticFeedback.mediumImpact();
        // Show self-evaluation popup FIRST (P10-08).
        // Node stays fogged until the student declares confidence.
        // Sound + visual reveal happen in the onResult callback.
        _showFogSelfEvalPopup(clusterId);
        return true;
      }

      // P1: Proximity haptic feedback — "warmer/colder" on missed taps.
      // Only in total fog where there are zero visual cues.
      if (_fogOfWarController.fogLevel == FogLevel.total) {
        // 🚀 OPT-5: Compare squared distances (avoid sqrt).
        final distSq = _fogOfWarController.getNearestUnrevealedDistanceSq(canvasPosition);
        if (distSq != null) {
          if (distSq < 10000) {        // < 100px
            HapticFeedback.heavyImpact();
          } else if (distSq < 40000) { // < 200px
            HapticFeedback.mediumImpact();
          } else if (distSq < 160000) { // < 400px
            HapticFeedback.lightImpact();
          }
        }
      }
      return false;
    }

    return false;
  }

  /// Show the self-evaluation popup with a 5-level confidence slider.
  ///
  /// P10-08: "Le regole P6-07 → P6-14 si applicano integralmente."
  /// The student rates their confidence (1-5) before the node is revealed.
  /// This activates explicit metacognition (T1) and feeds FSRS (P10-23).
  void _showFogSelfEvalPopup(String clusterId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true, // Allow full height for small screens.
      builder: (ctx) => _FogSelfEvalSheet(
        clusterId: clusterId,
        onResult: (recalled, confidence) {
          HapticFeedback.lightImpact();
          _fogOfWarController.recordResult(
            clusterId,
            recalled: recalled,
            confidence: confidence,
          );
          // 🎵 A13.4: "Rivelazione cinematografica" — plays AFTER eval,
          // when the fog hole actually opens and content becomes visible.
          PedagogicalSoundEngine.instance.play(PedagogicalSound.fogOfWarReveal);
          // Trigger fog overlay repaint to show revealed node.
          _fogOfWarVersionNotifier.value++;
        },
      ),
    ).whenComplete(() {
      // Safety net: if popup was dismissed without confirming (e.g. Android
      // back button), clear the pending eval to unblock subsequent taps.
      if (!mounted) return;
      if (_fogOfWarController.pendingEvalClusterId == clusterId) {
        debugPrint('⚔️ FoW: popup dismissed without confirm — treating as forgotten');
        _fogOfWarController.recordResult(
          clusterId,
          recalled: false,
          confidence: 1,
        );
        _fogOfWarVersionNotifier.value++;
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // END SESSION (P10-18 → P10-22)
  // ─────────────────────────────────────────────────────────────────────────

  /// End the Fog of War session — trigger cinematic reveal.
  void endFogOfWarSession() {
    if (!_fogOfWarController.isFogActive) return;

    HapticFeedback.heavyImpact();
    _fogOfWarController.endSession();

    // Start cinematic reveal animation (P10-18: 2-3s, center→outward).
    // 1800ms feels snappy without being abrupt.
    _fogOfWarAnimController?.stop();
    _fogOfWarRevealController?.duration =
        const Duration(milliseconds: 1800);
    _fogOfWarRevealController?.forward(from: 0.0);
  }

  /// Called from the reveal animation listener — every frame during reveal.
  void _onFogRevealTick() {
    final progress = _fogOfWarRevealController?.value ?? 0.0;
    _fogOfWarController.updateRevealProgress(progress);

    // 🚀 FIX: Trigger painter rebuild every frame during reveal.
    _fogOfWarVersionNotifier.value++;

    if (progress >= 1.0) {
      // Reveal complete → apply SRS reset + show mastery map summary.
      _fogOfWarRevealController?.stop();
      _applyFogOfWarSrsReset();
      _saveFogOfWarSession();
      // Rebuild overlay widgets — phase changed from revealing → masteryMap,
      // so the hint button and end-session button must disappear and the
      // mastery map controls (legend, surgical path, close) must appear.
      setState(() {});
      // Show summary after a brief pause so the student sees the mastery
      // map heatmap first — the map is immediately tappable, the summary
      // provides context without blocking interaction.
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted && _fogOfWarController.isMasteryMap) {
          _showFogMasteryMapSummary();
        }
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HINT — Progressive 3-tier system: direction → fly-to → reveal silhouette
  // ─────────────────────────────────────────────────────────────────────────

  /// Progressive hint system:
  ///  - Hint 1: Directional arrow showing compass direction to nearest node
  ///  - Hint 2: Camera flies to the area for 2 seconds
  ///  - Hint 3+: Briefly reveal the silhouette of the nearest node (1.5s)
  void _onFogHintTap() {
    // P3: 3-second cooldown to prevent spam.
    final now = DateTime.now();
    if (_lastHintTime != null &&
        now.difference(_lastHintTime!) < const Duration(seconds: 3)) {
      HapticFeedback.selectionClick();
      return;
    }
    _lastHintTime = now;

    final hintPos = _fogOfWarController.getHintPosition();
    if (hintPos == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(FlueraLocalizations.of(context)?.fow_allNodesDiscovered ?? '✅ Tutti i nodi sono stati scoperti!'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.only(bottom: 80, left: 20, right: 20),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    final hintNumber = _fogOfWarController.hintsUsed; // Already incremented.
    HapticFeedback.lightImpact();

    if (hintNumber == 1) {
      // ── TIER 1: Directional arrow ────────────────────────────────────
      _showDirectionalHint(hintPos);
    } else if (hintNumber == 2) {
      // ── TIER 2: Camera fly-to ────────────────────────────────────────
      _showFlyToHint(hintPos, hintNumber);
    } else {
      // ── TIER 3+: Briefly reveal silhouette ───────────────────────────
      _showRevealHint(hintPos, hintNumber);
    }
  }

  /// Tier 1: Show a visual arrow overlay on the canvas pointing toward the
  /// nearest unrevealed node, centered on the viewport with distance label.
  ///
  /// The arrow rotates to point in the exact direction and a "pulsing ring"
  /// marks the viewport center as the reference point — so the student
  /// clearly sees "from HERE, go THAT WAY".
  void _showDirectionalHint(Offset nodePos) {
    if (!mounted) return;

    final screenSize = MediaQuery.of(context).size;
    final viewportCenter = _canvasController.screenToCanvas(
      Offset(screenSize.width / 2, screenSize.height / 2),
    );
    final delta = nodePos - viewportCenter;
    final distance = delta.distance;

    // Angle in radians for the overlay arrow rotation.
    _fogHintArrowAngle = delta.direction;

    // Distance label: gives the student a sense of how far to go.
    final l10n = FlueraLocalizations.of(context);
    if (distance < 200) {
      _fogHintDistanceLabel = l10n?.fow_hintDistVeryClose ?? 'Vicinissimo!';
    } else if (distance < 500) {
      _fogHintDistanceLabel = l10n?.fow_hintDistClose ?? 'Vicino';
    } else if (distance < 1200) {
      _fogHintDistanceLabel = l10n?.fow_hintDistMedium ?? 'Media distanza';
    } else {
      _fogHintDistanceLabel = l10n?.fow_hintDistFar ?? 'Lontano';
    }

    setState(() {});

    // Auto-dismiss after 3 seconds.
    _fogHintArrowTimer?.cancel();
    _fogHintArrowTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        _fogHintArrowAngle = null;
        _fogHintDistanceLabel = null;
        setState(() {});
      }
    });
  }

  /// Tier 2: Fly camera to the node's area for 2 seconds.
  void _showFlyToHint(Offset nodePos, int hintNumber) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(FlueraLocalizations.of(context)?.fow_hintFlyTo(hintNumber) ?? '💡 Suggerimento #$hintNumber — guarda qui!'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.only(bottom: 200, left: 20, right: 20),
          duration: const Duration(milliseconds: 1500),
          backgroundColor: const Color(0xFFFF8F00).withValues(alpha: 0.9),
        ),
      );
    }

    final viewportSize = mounted
        ? MediaQuery.of(context).size
        : const Size(400, 800);
    CameraActions.zoomToRect(
      _canvasController,
      Rect.fromCenter(center: nodePos, width: 300, height: 300),
      viewportSize,
    );

    _fogHintTimer?.cancel();
    _fogHintTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && _fogOfWarController.isFogActive) {
        final zone = _fogOfWarController.selectedZone;
        if (zone != null) {
          CameraActions.zoomToRect(
            _canvasController,
            zone,
            mounted ? MediaQuery.of(context).size : const Size(400, 800),
          );
        }
      }
    });
  }

  /// Tier 3+: Briefly reveal the nearest node, then re-hide it.
  void _showRevealHint(Offset nodePos, int hintNumber) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            FlueraLocalizations.of(context)?.fow_hintReveal(hintNumber) ?? '💡 Suggerimento #$hintNumber — rivelazione temporanea!',
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.only(bottom: 200, left: 20, right: 20),
          duration: const Duration(milliseconds: 1500),
          backgroundColor: const Color(0xFFEF6C00).withValues(alpha: 0.9),
        ),
      );
    }

    // Find the nearest unrevealed node and temporarily add it to revealed set.
    String? tempRevealId;
    double minDist = double.infinity;
    for (final c in _fogOfWarController.originalClusters) {
      if (_fogOfWarController.revealedNodeIds.contains(c.id)) continue;
      final d = (c.centroid - nodePos).distance;
      if (d < minDist) {
        minDist = d;
        tempRevealId = c.id;
      }
    }

    if (tempRevealId == null) return;

    // Fly to the node.
    final viewportSize = mounted
        ? MediaQuery.of(context).size
        : const Size(400, 800);
    CameraActions.zoomToRect(
      _canvasController,
      Rect.fromCenter(center: nodePos, width: 200, height: 200),
      viewportSize,
    );

    // Temporarily reveal (add to revealed set → painter punches hole).
    _fogOfWarController.revealedNodeIds.add(tempRevealId);
    _fogOfWarVersionNotifier.value++;

    // Re-hide after 1.5 seconds.
    final idToHide = tempRevealId;
    _fogHintTimer?.cancel();
    _fogHintTimer = Timer(const Duration(milliseconds: 1500), () {
      // Only re-hide if the user hasn't tapped it in the meantime.
      final entry = _fogOfWarController.session?.nodeEntries[idToHide];
      final wasEvaluated = entry?.status != null &&
          entry!.status != FogNodeStatus.hidden;
      if (!wasEvaluated) {
        _fogOfWarController.revealedNodeIds.remove(idToHide);
      }
      _fogOfWarVersionNotifier.value++;

      // Fly back.
      if (mounted && _fogOfWarController.isFogActive) {
        final zone = _fogOfWarController.selectedZone;
        if (zone != null) {
          CameraActions.zoomToRect(
            _canvasController,
            zone,
            mounted ? MediaQuery.of(context).size : const Size(400, 800),
          );
        }
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SRS INTEGRATION (P10-23, P10-26)
  // ─────────────────────────────────────────────────────────────────────────

  /// P10-23: Reset SRS intervals for forgotten/blindspot nodes to 1 day.
  /// P10-26: Green nodes keep their normal intervals — no wasted time.
  void _applyFogOfWarSrsReset() {
    final surgicalIds = _fogOfWarController.surgicalPlanNodeIds;
    if (surgicalIds.isEmpty) return;

    final now = DateTime.now();
    int resetCount = 0;

    for (final clusterId in surgicalIds) {
      // Find concepts associated with this cluster via word-boundary matching.
      // Word boundaries prevent false positives (e.g. "DNA" matching "DNAPL").
      final clusterText = (_clusterTextCache[clusterId] ?? '').toLowerCase();
      if (clusterText.isEmpty) continue;

      for (final concept in _reviewSchedule.keys.toList()) {
        final conceptLower = concept.toLowerCase();
        // Use word-boundary regex: concept must appear as a whole word.
        final pattern = RegExp('\\b${RegExp.escape(conceptLower)}\\b');
        if (pattern.hasMatch(clusterText)) {
          // P10-23: Reset to 1-day interval, priority review.
          final existing = _reviewSchedule[concept]!;
          _reviewSchedule[concept] = FsrsScheduler.review(
            existing,
            quality: 0,       // Treated as "incorrect" → short interval
            confidence: 1,    // Low confidence → conservative scheduling
          );
          resetCount++;
        }
      }
    }

    if (resetCount > 0) {
      _saveSpacedRepetition();
      debugPrint(
        '⚔️ FoW P10-23: Reset $resetCount SRS concepts to priority review',
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SESSION PERSISTENCE (P10-25)
  // ─────────────────────────────────────────────────────────────────────────

  /// KV key for Fog of War session history, scoped per canvas.
  String get _fogHistoryKey => 'fog_history_$_canvasId';

  /// P10-25: Save the completed session to persistent storage.
  /// Maintains a rolling history of the last 10 sessions for delta tracking.
  Future<void> _saveFogOfWarSession() async {
    final sessionJson = _fogOfWarController.exportSessionJson();
    if (sessionJson == null) return;

    try {
      final kv = await KeyValueStore.getInstance();
      final raw = kv.getString(_fogHistoryKey);
      final history = raw != null
          ? (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>()
          : <Map<String, dynamic>>[];

      history.add(sessionJson);

      // Keep only last 10 sessions to bound storage.
      while (history.length > 10) {
        history.removeAt(0);
      }

      await kv.setString(_fogHistoryKey, jsonEncode(history));
      debugPrint(
        '⚔️ FoW P10-25: Session saved (${history.length} total)',
      );
    } catch (e) {
      debugPrint('⚠️ FoW session save error: $e');
    }
  }

  /// Load previous Fog of War sessions for delta tracking (P10-27).
  /// Returns the most recent completed session, or null.
  Future<Map<String, dynamic>?> _loadPreviousFogSession() async {
    try {
      final kv = await KeyValueStore.getInstance();
      final raw = kv.getString(_fogHistoryKey);
      if (raw == null || raw.isEmpty) return null;
      final history =
          (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
      if (history.isEmpty) return null;

      // Return second-to-last (the PREVIOUS session, not the one we just saved).
      if (history.length >= 2) return history[history.length - 2];
      return null;
    } catch (e) {
      debugPrint('⚠️ FoW history load error: $e');
      return null;
    }
  }

  /// P10-25: Count of consecutive high-recall sessions (for P10-29).
  Future<int> _consecutiveHighRecallCount() async {
    try {
      final kv = await KeyValueStore.getInstance();
      final raw = kv.getString(_fogHistoryKey);
      if (raw == null) return 0;
      final history =
          (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();

      int count = 0;
      for (int i = history.length - 1; i >= 0; i--) {
        final results = history[i]['results'] as Map<String, dynamic>?;
        if (results == null) break;
        final recalled = (results['recalled'] as num?)?.toInt() ?? 0;
        final total = (history[i]['totalNodes'] as num?)?.toInt() ?? 1;
        if (total > 0 && recalled / total >= 0.9) {
          count++;
        } else {
          break;
        }
      }
      return count;
    } catch (e) {
      return 0;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MASTERY MAP (P10-19 → P10-22, P10-27 → P10-29)
  // ─────────────────────────────────────────────────────────────────────────

  /// Show the mastery map summary (P10-22 + §XI.4 Muro Rosso + P10-27 delta).
  void _showFogMasteryMapSummary() async {
    if (!_fogOfWarController.isMasteryMap) return;
    if (!mounted) return;

    final isMuroRosso = _fogOfWarController.isMuroRossoActive;
    final session = _fogOfWarController.session;

    // P10-27: Calculate delta from previous session.
    String deltaText = '';
    final prevSession = await _loadPreviousFogSession();
    if (prevSession != null && session != null) {
      final prevResults = prevSession['results'] as Map<String, dynamic>?;
      if (prevResults != null) {
        final prevRecalled = (prevResults['recalled'] as num?)?.toInt() ?? 0;
        final prevForgotten =
            (prevResults['forgotten'] as num?)?.toInt() ?? 0;
        final prevBlind =
            (prevResults['blind_spots'] as num?)?.toInt() ?? 0;

        final deltaRecalled = session.recalledCount - prevRecalled;
        final deltaForgotten = session.forgottenCount - prevForgotten;
        final deltaBlind = session.blindSpotCount - prevBlind;

        final parts = <String>[];
        if (deltaRecalled > 0) parts.add('+$deltaRecalled ricordati');
        if (deltaRecalled < 0) parts.add('$deltaRecalled ricordati');
        if (deltaForgotten < 0) parts.add('${deltaForgotten.abs()} errori in meno');
        if (deltaBlind < 0) parts.add('${deltaBlind.abs()} punti ciechi in meno');

        if (parts.isNotEmpty) {
          deltaText = '\n📈 ${parts.join(", ")}';
        }
      }
    }

    // P10-29: Check for "Sei pronto" milestone.
    final consecutiveHigh = await _consecutiveHighRecallCount();
    String milestoneText = '';
    if (consecutiveHigh >= 3 && session != null) {
      final recallRatio = session.totalNodes > 0
          ? session.recalledCount / session.totalNodes
          : 0.0;
      if (recallRatio >= 0.9) {
        milestoneText =
            '\n\n🏆 Sei pronto per l\'esame. Il tuo Palazzo della Memoria è solido.';
      }
    }

    // P10-28: Suggest density increase if >80% green.
    String densitySuggestion = '';
    if (session != null &&
        session.totalNodes > 0 &&
        milestoneText.isEmpty) {
      final recallRatio = session.recalledCount / session.totalNodes;
      if (recallRatio > 0.8 &&
          _fogOfWarController.fogLevel != FogLevel.total) {
        densitySuggestion =
            '\n💡 Hai ricordato quasi tutto — provare con nebbia più densa?';
      }
    }

    if (!mounted) return;

    final l10n = FlueraLocalizations.of(context);
    final summaryText = _fogOfWarController.localizedSummaryText(l10n);

    // Show structured bottom sheet instead of multi-line SnackBar.
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      isScrollControlled: true,
      builder: (ctx) => _FogMasterySummarySheet(
        session: session!,
        summaryText: summaryText,
        deltaText: deltaText,
        densitySuggestion: densitySuggestion,
        milestoneText: milestoneText,
        isMuroRosso: isMuroRosso,
        onDismiss: () {
          Navigator.pop(ctx);
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DISMISS
  // ─────────────────────────────────────────────────────────────────────────

  /// Dismiss the Fog of War and return to normal canvas.
  void dismissFogOfWar() {
    // 🚦 A15: Record Step 10 completion if the session had any reveals.
    if (_fogOfWarController.revealedNodeIds.isNotEmpty) {
      _stepGateController.recordStepCompletion(LearningStep.step10FogOfWar);
      _saveStepGateHistory();
    }

    _fogOfWarController.dismiss();
    _fogOfWarAnimController?.stop();
    _fogOfWarRevealController?.stop();
    _fogOfWarRevealController?.reset();
    // 🗺️ Clean up surgical path state.
    _fogSurgicalPathActive = false;
    _fogSurgicalVisitedIds.clear();
    _fogSurgicalCurrentIndex = 0;
    _fogSurgicalClusterMap = const {};
    // OPT-6: Cancel zoom-back timer.
    _fogZoomBackTimer?.cancel();
    _fogZoomBackTimer = null;
    // 💡 Clean up hint arrow overlay.
    _fogHintArrowTimer?.cancel();
    _fogHintArrowTimer = null;
    _fogHintArrowAngle = null;
    _fogHintDistanceLabel = null;
    _layerController.notifyListeners();
    setState(() {});
  }

  // ─────────────────────────────────────────────────────────────────────────
  // OVERLAY BUILDERS (called from _build_ui.dart or _ui_canvas_layer.dart)
  // ─────────────────────────────────────────────────────────────────────────

  /// Build the end-session FAB and mastery map controls.
  List<Widget> buildFogOfWarOverlays(BuildContext context) {
    final widgets = <Widget>[];
    if (!_fogOfWarController.isActive) return widgets;

    // End session button (bottom-center).
    if (_fogOfWarController.isFogActive) {
      widgets.add(
        Positioned(
          bottom: 100,
          left: 0,
          right: 0,
          child: Center(
            child: FilledButton.icon(
              icon: const Icon(Icons.flag, size: 18),
              label: Text(FlueraLocalizations.of(context)?.fow_endSession ?? 'Termina Sessione'),
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
              onPressed: endFogOfWarSession,
            ),
          ),
        ),
      );

      // P10-11: NO node counter shown during session — only hint button.
      widgets.add(
        Positioned(
          bottom: 160,
          left: 0,
          right: 0,
          child: Center(
            child: FilledButton.icon(
              icon: const Icon(Icons.lightbulb_outline, size: 16),
              label: Text(FlueraLocalizations.of(context)?.fow_hintLabel ?? 'Suggerimento'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF8F00).withValues(alpha: 0.8),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(fontSize: 13),
              ),
              onPressed: _onFogHintTap,
            ),
          ),
        ),
      );

      // Fog level indicator (top-center, subtle).
      widgets.add(
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                FlueraLocalizations.of(context)?.fow_fogActive(
                    _fogOfWarController.localizedFogLevelLabel(FlueraLocalizations.of(context)))
                    ?? '⚔️ ${_fogOfWarController.fogLevelLabel}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      );

      // 💡 Directional hint arrow overlay — visual compass on screen center.
      if (_fogHintArrowAngle != null) {
        widgets.add(
          Positioned.fill(
            child: IgnorePointer(
              child: _FogDirectionalArrow(
                angle: _fogHintArrowAngle!,
                distanceLabel: _fogHintDistanceLabel ?? '',
              ),
            ),
          ),
        );
      }
    }

    // Mastery map controls.
    if (_fogOfWarController.isMasteryMap) {
      // 📋 Legend (J) — bottom-left collapsible.
      widgets.add(
        Positioned(
          bottom: 170,
          left: 16,
          child: _FogMasteryLegend(),
        ),
      );

      // Row of buttons: "Guida ripasso" + "Chiudi".
      widgets.add(
        Positioned(
          bottom: 100,
          left: 0,
          right: 0,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 🗺️ Surgical Path button (P10-24).
                if (!_fogSurgicalPathActive &&
                    _fogOfWarController.surgicalPlanNodeIds.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: FilledButton.icon(
                      icon: const Icon(Icons.route, size: 18),
                      label: Text(
                        '🗺️ Guida ripasso '
                        '(${_fogOfWarController.surgicalPlanNodeIds.length})',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFE65100),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 4,
                      ),
                      onPressed: _startSurgicalPath,
                    ),
                  ),
                FilledButton.icon(
                  icon: const Icon(Icons.check_circle, size: 18),
                  label: Text(FlueraLocalizations.of(context)?.fow_closeFogOfWar ?? 'Chiudi Sfida'),
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
                  onPressed: dismissFogOfWar,
                ),
              ],
            ),
          ),
        ),
      );

      // 🗺️ Surgical Path UI — bottom card with progress, instruction, and action.
      if (_fogSurgicalPathActive) {
        final totalPath = _fogOfWarController.surgicalPlanNodeIds.length;
        final visitedCount = _fogSurgicalVisitedIds.length;
        final isDone = _fogSurgicalVisitedIds.length >= totalPath;

        widgets.add(
          Positioned(
            bottom: 100,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              decoration: BoxDecoration(
                color: isDone
                    ? const Color(0xFF1B5E20).withValues(alpha: 0.95)
                    : const Color(0xFF37474F).withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Progress bar.
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 4,
                      child: LinearProgressIndicator(
                        value: totalPath > 0 ? visitedCount / totalPath : 0,
                        backgroundColor: Colors.white.withValues(alpha: 0.15),
                        color: isDone
                            ? const Color(0xFF4CAF50)
                            : const Color(0xFFFFB74D),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  if (!isDone) ...[
                    // Instruction text.
                    Text(
                      FlueraLocalizations.of(context)?.fow_surgicalInstruction ?? '📖 Rileggi questo concetto con attenzione',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Action row: progress + next button.
                    Row(
                      children: [
                        // Progress count.
                        Text(
                          '$visitedCount/$totalPath',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        // "Ho riletto → Prossimo" button.
                        FilledButton.icon(
                          icon: const Icon(Icons.arrow_forward, size: 16),
                          label: Text(
                            visitedCount == totalPath - 1
                                ? (FlueraLocalizations.of(context)?.fow_surgicalLastOne ?? 'Ultimo →')
                                : (FlueraLocalizations.of(context)?.fow_surgicalReadNext ?? 'Ho riletto → Prossimo'),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFFF8F00),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          onPressed: _navigateToNextSurgicalNode,
                        ),
                      ],
                    ),
                  ] else ...[
                    // Done state.
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('✅', style: TextStyle(fontSize: 20)),
                        const SizedBox(width: 8),
                        Text(
                          FlueraLocalizations.of(context)?.fow_surgicalAllDone(totalPath) ?? 'Tutti i $totalPath nodi rivisti!',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _stopSurgicalPath,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF4CAF50),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          FlueraLocalizations.of(context)?.fow_surgicalBackToMap ?? 'Torna alla mappa',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      }
    }

    return widgets;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 🗺️ SURGICAL PATH (P10-24)
  // ─────────────────────────────────────────────────────────────────────────

  /// Start the guided review path — fly to the first critical node.
  void _startSurgicalPath() {
    final planIds = _fogOfWarController.surgicalPlanNodeIds;
    if (planIds.isEmpty) return;

    HapticFeedback.mediumImpact();

    // M: Nearest-neighbor spatial ordering — start from viewport center,
    // always visit the closest unvisited node next. O(n²) but n < 30.
    // Use the controller's originalClusters (the ones used during the fog
    // session) — these have the correct bounds from when fog was activated.
    // _clusterCache may have been re-detected since then.
    _fogSurgicalClusterMap = {
      for (final c in _fogOfWarController.originalClusters) c.id: c,
    };

    final remaining = planIds.where((id) => _fogSurgicalClusterMap.containsKey(id)).toList();
    final ordered = <String>[];
    final viewportSize = MediaQuery.of(context).size;
    var currentPos = _canvasController.screenToCanvas(
      Offset(viewportSize.width / 2, viewportSize.height / 2),
    );

    while (remaining.isNotEmpty) {
      // Find nearest to currentPos.
      String? nearest;
      double nearestDist = double.infinity;
      for (final id in remaining) {
        final dist = (_fogSurgicalClusterMap[id]!.centroid - currentPos).distance;
        if (dist < nearestDist) {
          nearestDist = dist;
          nearest = id;
        }
      }
      if (nearest == null) break;
      ordered.add(nearest);
      currentPos = _fogSurgicalClusterMap[nearest]!.centroid;
      remaining.remove(nearest);
    }

    // Replace the controller's plan with the spatially sorted order.
    _fogOfWarController.overrideSurgicalPlanOrder(ordered);

    _fogSurgicalPathActive = true;
    _fogSurgicalVisitedIds.clear();
    _fogSurgicalCurrentIndex = 0;

    setState(() {});

    // Fly to the first node.
    _navigateToNextSurgicalNode();
  }

  /// Navigate to the next node in the surgical path.
  ///
  /// Flow: mark CURRENT node as visited → advance index → fly to NEXT node.
  /// On first call (from _startSurgicalPath), index is 0 and nothing is
  /// visited yet, so we just fly to planIds[0] without marking anything.
  void _navigateToNextSurgicalNode() {
    final planIds = _fogOfWarController.surgicalPlanNodeIds;

    // Find the next valid cluster to fly to, skipping stale IDs.
    while (_fogSurgicalCurrentIndex < planIds.length) {
      final targetId = planIds[_fogSurgicalCurrentIndex];
      final targetCluster = _fogSurgicalClusterMap[targetId];
      _fogSurgicalCurrentIndex++;

      if (targetCluster == null) continue; // Stale ID — skip.

      // Mark the PREVIOUS valid node as visited (the one the student
      // just finished reading). We skip this on the first call.
      // Only mark nodes that actually exist in the cluster map.
      if (_fogSurgicalVisitedIds.isNotEmpty || _fogSurgicalCurrentIndex > 1) {
        // Find the previous valid node in the path.
        for (int j = _fogSurgicalCurrentIndex - 2; j >= 0; j--) {
          final prevId = planIds[j];
          if (_fogSurgicalClusterMap.containsKey(prevId)) {
            _fogSurgicalVisitedIds.add(prevId);
            break;
          }
        }
      }

      HapticFeedback.selectionClick();

      // Fly to the node — set scale immediately, then animate offset.
      // Using animateOffsetTo avoids the spring-interaction bug in
      // animateToTransform where pan spring values are discarded when
      // _isTransformSpringActive is true.
      final viewportSize = MediaQuery.of(context).size;
      final centroid = targetCluster.centroid;
      final targetScale = _canvasController.scale.clamp(1.0, 3.0);

      // Snap scale to target (no animation — instant, avoids spring conflict).
      if ((_canvasController.scale - targetScale).abs() >= 0.001) {
        _canvasController.setScale(targetScale);
      }

      // Animate offset to center the node in the viewport.
      final targetOffset = Offset(
        viewportSize.width / 2 - centroid.dx * targetScale,
        viewportSize.height / 2 - centroid.dy * targetScale,
      );
      _canvasController.animateOffsetTo(targetOffset);

      setState(() {});
      return;
    }

    // All nodes exhausted — mark the last valid node as visited.
    for (int j = planIds.length - 1; j >= 0; j--) {
      if (_fogSurgicalClusterMap.containsKey(planIds[j])) {
        _fogSurgicalVisitedIds.add(planIds[j]);
        break;
      }
    }
    setState(() {});

    // Auto-complete check.
    if (_fogSurgicalVisitedIds.length >= planIds.length) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && _fogSurgicalPathActive) {
          HapticFeedback.heavyImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                FlueraLocalizations.of(context)?.fow_surgicalReviewDone ?? '✅ Tutti i nodi critici rivisti! Ripasso completato.',
              ),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              margin: const EdgeInsets.only(
                bottom: 80, left: 20, right: 20,
              ),
              duration: const Duration(seconds: 3),
              backgroundColor: const Color(0xFF2E7D32),
            ),
          );
        }
      });
    }
  }

  /// Stop the surgical path mode and clean up state.
  void _stopSurgicalPath() {
    _fogSurgicalPathActive = false;
    _fogSurgicalVisitedIds.clear();
    _fogSurgicalCurrentIndex = 0;
    _fogSurgicalClusterMap = const {};
    setState(() {});
  }
}

// ============================================================================
// 🌫️ Fog Self-Evaluation Sheet — 5-level confidence (P10-08, P6-07→P6-14)
// ============================================================================

/// A bottom sheet with a 5-level confidence slider for metacognitive
/// self-evaluation during a Fog of War session.
///
/// The student rates how well they remembered the node's content BEFORE
/// seeing it, activating explicit metacognition (Flavell 1979, T1).
///
/// Levels:
///  1 = "Non ricordavo nulla"      → recalled: false, confidence: 1
///  2 = "Vagamente"                → recalled: false, confidence: 2
///  3 = "Parzialmente"             → recalled: true,  confidence: 3
///  4 = "Bene"                     → recalled: true,  confidence: 4
///  5 = "Perfettamente"            → recalled: true,  confidence: 5
class _FogSelfEvalSheet extends StatefulWidget {
  final String clusterId;
  final void Function(bool recalled, int confidence) onResult;

  const _FogSelfEvalSheet({
    required this.clusterId,
    required this.onResult,
  });

  @override
  State<_FogSelfEvalSheet> createState() => _FogSelfEvalSheetState();
}

class _FogSelfEvalSheetState extends State<_FogSelfEvalSheet> {
  int? _selectedLevel;

  /// Build levels with localized labels at runtime.
  List<_ConfidenceLevel> _buildLevels(FlueraLocalizations? l10n) => [
    _ConfidenceLevel(
      value: 1,
      emoji: '❌',
      label: l10n?.fow_selfEval1 ?? 'Non ricordavo nulla',
      color: const Color(0xFFEF5350),
      recalled: false,
    ),
    _ConfidenceLevel(
      value: 2,
      emoji: '😕',
      label: l10n?.fow_selfEval2 ?? 'Vagamente',
      color: const Color(0xFFFF7043),
      recalled: false,
    ),
    _ConfidenceLevel(
      value: 3,
      emoji: '🤔',
      label: l10n?.fow_selfEval3 ?? 'Parzialmente',
      color: const Color(0xFFFFB74D),
      recalled: true,
    ),
    _ConfidenceLevel(
      value: 4,
      emoji: '😊',
      label: l10n?.fow_selfEval4 ?? 'Bene',
      color: const Color(0xFF66BB6A),
      recalled: true,
    ),
    _ConfidenceLevel(
      value: 5,
      emoji: '✅',
      label: l10n?.fow_selfEval5 ?? 'Perfettamente',
      color: const Color(0xFF4CAF50),
      recalled: true,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = FlueraLocalizations.of(context);
    final levels = _buildLevels(l10n);

    return SafeArea(
      child: SingleChildScrollView(
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🧠', style: TextStyle(fontSize: 36)),
              const SizedBox(height: 12),
              Text(
                l10n?.fow_selfEvalTitle ?? 'Quanto ricordavi di questo nodo?',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n?.fow_selfEvalSubtitle ?? 'Valuta onestamente prima di rivelare.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 20),
              // 5-level confidence options.
              ...List.generate(levels.length, (i) {
                final level = levels[i];
                final isSelected = _selectedLevel == level.value;

                return Padding(
                  padding: EdgeInsets.only(bottom: i < levels.length - 1 ? 6 : 0),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedLevel = level.value);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? level.color.withValues(alpha: 0.15)
                              : theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? level.color.withValues(alpha: 0.5)
                                : theme.colorScheme.outline.withValues(alpha: 0.1),
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(level.emoji, style: const TextStyle(fontSize: 20)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                level.label,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight:
                                      isSelected ? FontWeight.w700 : FontWeight.w500,
                                  color: isSelected
                                      ? level.color
                                      : theme.colorScheme.onSurface,
                                ),
                              ),
                            ),
                            // Confidence number badge.
                            Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSelected
                                    ? level.color.withValues(alpha: 0.2)
                                    : theme.colorScheme.surfaceContainerHighest
                                        .withValues(alpha: 0.4),
                              ),
                              child: Center(
                                child: Text(
                                  '${level.value}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: isSelected
                                        ? level.color
                                        : theme.colorScheme.onSurface
                                            .withValues(alpha: 0.4),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 16),
              // Confirm button — only active when a level is selected.
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _selectedLevel == null
                      ? null
                      : () {
                          final level = levels.firstWhere(
                            (l) => l.value == _selectedLevel,
                          );
                          widget.onResult(level.recalled, level.value);
                          Navigator.pop(context);
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: _selectedLevel != null
                        ? levels
                            .firstWhere((l) => l.value == _selectedLevel)
                            .color
                        : null,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    _selectedLevel == null
                        ? (l10n?.fow_selfEvalSelect ?? 'Seleziona la tua confidenza')
                        : (l10n?.fow_selfEvalConfirm ?? 'Conferma e rivela'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Data class for confidence level options.
class _ConfidenceLevel {
  final int value;
  final String emoji;
  final String label;
  final Color color;
  final bool recalled;

  const _ConfidenceLevel({
    required this.value,
    required this.emoji,
    required this.label,
    required this.color,
    required this.recalled,
  });
}

// ============================================================================
// 🌫️ Fog Mastery Summary Sheet — Structured results (P10-22, §XI.4, P10-27)
// ============================================================================

/// A structured bottom sheet showing the mastery map results with:
/// - Progress ring, stats grid, delta from previous session
/// - Muro Rosso emotional protection when >70% failed
/// - Milestone celebration when 3+ consecutive high-recall sessions
/// - Density increase suggestion when >80% green
class _FogMasterySummarySheet extends StatelessWidget {
  final FogOfWarSession session;
  final String summaryText;
  final String deltaText;
  final String densitySuggestion;
  final String milestoneText;
  final bool isMuroRosso;
  final VoidCallback onDismiss;

  const _FogMasterySummarySheet({
    required this.session,
    required this.summaryText,
    required this.deltaText,
    required this.densitySuggestion,
    required this.milestoneText,
    required this.isMuroRosso,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = session.totalNodes > 0
        ? session.recalledCount / session.totalNodes
        : 0.0;
    final headerEmoji = milestoneText.isNotEmpty
        ? '🏆'
        : isMuroRosso
            ? '🎯'
            : '⚔️';
    final accentColor = milestoneText.isNotEmpty
        ? const Color(0xFF4CAF50)
        : isMuroRosso
            ? const Color(0xFF78909C)
            : const Color(0xFF4CAF50);

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with emoji.
            Text(headerEmoji, style: const TextStyle(fontSize: 36)),
            const SizedBox(height: 8),
            Text(
              milestoneText.isNotEmpty
                  ? FlueraLocalizations.of(context)!.fow_resultsTitleMilestone
                  : isMuroRosso
                      ? FlueraLocalizations.of(context)!.fow_resultsTitleRedWall
                      : FlueraLocalizations.of(context)!.fow_resultsTitleDefault,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),

            // Progress ring + stats row.
            Row(
              children: [
                // Progress ring.
                SizedBox(
                  width: 56,
                  height: 56,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: ratio,
                        strokeWidth: 4.5,
                        backgroundColor: theme.colorScheme.onSurface
                            .withValues(alpha: 0.08),
                        color: accentColor,
                      ),
                      Text(
                        '${(ratio * 100).round()}%',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: accentColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // Stats column.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _statChip('✅', '${session.recalledCount}',
                          'ricordati', const Color(0xFF4CAF50), theme),
                      const SizedBox(height: 4),
                      _statChip(
                          isMuroRosso ? '📝' : '❌',
                          '${session.forgottenCount}',
                          'dimenticati',
                          isMuroRosso
                              ? const Color(0xFF78909C)
                              : const Color(0xFFEF5350),
                          theme),
                      const SizedBox(height: 4),
                      _statChip('👁\u200D🗨', '${session.blindSpotCount}',
                          'non visitati', const Color(0xFF9E9E9E), theme),
                    ],
                  ),
                ),
              ],
            ),

            // Delta from previous session.
            if (deltaText.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF4CAF50).withValues(alpha: 0.2),
                  ),
                ),
                child: Text(
                  '📈 ${deltaText.replaceFirst('\n📈 ', '')}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF4CAF50),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],

            // Density suggestion.
            if (densitySuggestion.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB74D).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFFFB74D).withValues(alpha: 0.2),
                  ),
                ),
                child: Text(
                  densitySuggestion.replaceFirst('\n', ''),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFFFFB74D),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],

            // Milestone celebration.
            if (milestoneText.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF4CAF50).withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  milestoneText.replaceAll('\n', '').trim(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF4CAF50),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],

            // Muro Rosso coaching text.
            if (isMuroRosso) ...[
              const SizedBox(height: 8),
              Text(
                summaryText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  height: 1.4,
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Dismiss button.
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onDismiss,
                style: FilledButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  isMuroRosso ? 'Esplora la mappa' : 'Esplora la mappa',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(String emoji, String value, String label,
      Color color, ThemeData theme) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// 🌫️ Fog Setup Sheet — Level picker + zone selection (P10-01, P10-02, P10-03)
// ============================================================================

class _FogSetupSheet extends StatefulWidget {
  final int clusterCount;
  final String canvasId;
  final void Function(FogLevel level, bool useZoneSelection) onStart;

  const _FogSetupSheet({
    required this.clusterCount,
    required this.canvasId,
    required this.onStart,
  });

  @override
  State<_FogSetupSheet> createState() => _FogSetupSheetState();
}

class _FogSetupSheetState extends State<_FogSetupSheet>
    with SingleTickerProviderStateMixin {
  bool _useZoneSelection = true;
  List<Map<String, dynamic>> _sessionHistory = [];
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadHistory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final kv = await KeyValueStore.getInstance();
      final raw = kv.getString('fog_history_${widget.canvasId}');
      if (raw != null && raw.isNotEmpty) {
        final list = (jsonDecode(raw) as List<dynamic>)
            .cast<Map<String, dynamic>>();
        if (mounted) {
          setState(() => _sessionHistory = list);
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasHistory = _sessionHistory.isNotEmpty;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header.
          Row(
            children: [
              const Text('⚔️', style: TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  FlueraLocalizations.of(context)?.proCanvas_fogOfWar ?? 'Sfida',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.info_outline, size: 20),
                tooltip: FlueraLocalizations.of(context)?.fow_setupInfoTooltip ?? 'Come funziona',
                onPressed: () => FogOfWarInfoScreen.show(context),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Tabs: Nuova sessione / Storico
          if (hasHistory) ...[
            TabBar(
              controller: _tabController,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
              indicatorSize: TabBarIndicatorSize.label,
              tabs: [
                const Tab(text: '⚔️ Nuova sessione'),
                Tab(text: '📊 Storico (${_sessionHistory.length})'),
              ],
            ),
            const SizedBox(height: 8),
          ],

          // Content — Flexible is needed in BOTH paths so the
          // SingleChildScrollView inside _buildNewSessionTab gets
          // bounded constraints and can actually scroll.
          if (hasHistory)
            Flexible(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildNewSessionTab(theme),
                  _buildHistoryTab(theme),
                ],
              ),
            )
          else
            Flexible(child: _buildNewSessionTab(theme)),
        ],
      ),
    );
  }

  Widget _buildNewSessionTab(ThemeData theme) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_sessionHistory.isEmpty)
            Text(
              FlueraLocalizations.of(context)?.fow_setupChooseLevel ?? 'Scegli il livello di nebbia. Più è densa, più è difficile.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          if (_sessionHistory.isNotEmpty) ...[
            // Quick summary of last session.
            _buildLastSessionSummary(theme),
            const SizedBox(height: 8),

            // N: Streak & gamification badges.
            Builder(builder: (_) {
              final badges = <(String, String, Color)>[];

              // Calculate consecutive high-recall streak.
              int streak = 0;
              for (int i = _sessionHistory.length - 1; i >= 0; i--) {
                final r = _sessionHistory[i]['results'] as Map<String, dynamic>?;
                final recalled = (r?['recalled'] as num?)?.toInt() ?? 0;
                final total = (_sessionHistory[i]['totalNodes'] as num?)?.toInt() ?? 1;
                if (total > 0 && recalled / total >= 0.7) {
                  streak++;
                } else {
                  break;
                }
              }

              if (streak >= 10) {
                badges.add(('💎', 'Palazzo della Memoria', const Color(0xFF7C4DFF)));
              } else if (streak >= 5) {
                badges.add(('🌟', 'Memoria solida', const Color(0xFFFFD600)));
              } else if (streak >= 3) {
                badges.add(('🔥', 'In forma', const Color(0xFFFF6D00)));
              }

              // Check confidence growth (last 3 sessions).
              if (_sessionHistory.length >= 3) {
                final last3 = _sessionHistory.sublist(
                  _sessionHistory.length - 3,
                );
                final confs = last3
                    .map((s) => (s['avgConfidence'] as num?)?.toDouble())
                    .where((c) => c != null && c > 0)
                    .cast<double>()
                    .toList();
                if (confs.length >= 3 &&
                    confs[2] > confs[1] && confs[1] > confs[0]) {
                  badges.add(
                    ('📈', 'Crescita costante', const Color(0xFF00C853)),
                  );
                }
              }

              if (badges.isEmpty) return const SizedBox.shrink();

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final (emoji, label, color) in badges)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: color.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          '$emoji $label',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),
          ],
          const SizedBox(height: 4),

          // P10-02: Zone selection toggle.
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _useZoneSelection = !_useZoneSelection);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _useZoneSelection
                      ? theme.colorScheme.primary.withValues(alpha: 0.08)
                      : theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _useZoneSelection
                        ? theme.colorScheme.primary.withValues(alpha: 0.3)
                        : theme.colorScheme.outline.withValues(alpha: 0.1),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _useZoneSelection ? Icons.crop_free : Icons.select_all,
                      size: 20,
                      color: _useZoneSelection
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _useZoneSelection
                                ? 'Seleziona area'
                                : 'Tutta la canvas',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: _useZoneSelection
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            _useZoneSelection
                                ? 'Traccerà un rettangolo per testare solo un\'area'
                                : '${widget.clusterCount} nodi totali',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: _useZoneSelection,
                      onChanged: (v) {
                        HapticFeedback.selectionClick();
                        setState(() => _useZoneSelection = v);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Fog level options.
          _FogLevelOption(
            emoji: '🌤️',
            title: 'Nebbia Leggera',
            subtitle: FlueraLocalizations.of(context)?.fow_setupLightDesc ?? 'Sagome dei nodi visibili, zero contenuto',
            difficulty: 'Media',
            color: const Color(0xFF64B5F6),
            onTap: () => widget.onStart(FogLevel.light, _useZoneSelection),
          ),
          const SizedBox(height: 8),
          _FogLevelOption(
            emoji: '🌫️',
            title: 'Nebbia Media',
            subtitle: FlueraLocalizations.of(context)?.fow_setupMediumDesc ?? 'Visibilità limitata (300px). Devi avvicinarti.',
            difficulty: 'Alta',
            color: const Color(0xFFFFB74D),
            onTap: () => widget.onStart(FogLevel.medium, _useZoneSelection),
          ),
          const SizedBox(height: 8),
          _FogLevelOption(
            emoji: '🌑',
            title: 'Nebbia Totale',
            subtitle: FlueraLocalizations.of(context)?.fow_setupTotalDesc ?? 'Buio completo. Solo la memoria ti guida.',
            difficulty: 'Massima',
            color: const Color(0xFFEF5350),
            onTap: () => widget.onStart(FogLevel.total, _useZoneSelection),
          ),
        ],
      ),
    );
  }

  /// Quick summary card of the most recent session shown in the "new session" tab.
  Widget _buildLastSessionSummary(ThemeData theme) {
    final last = _sessionHistory.last;
    final results = last['results'] as Map<String, dynamic>?;
    final recalled = (results?['recalled'] as num?)?.toInt() ?? 0;
    final total = (last['totalNodes'] as num?)?.toInt() ?? 1;
    final ratio = total > 0 ? recalled / total : 0.0;
    final fogLevel = last['fogLevel'] as String? ?? 'light';

    // Delta vs previous.
    String? deltaText;
    if (_sessionHistory.length >= 2) {
      final prev = _sessionHistory[_sessionHistory.length - 2];
      final prevResults = prev['results'] as Map<String, dynamic>?;
      final prevRecalled = (prevResults?['recalled'] as num?)?.toInt() ?? 0;
      final diff = recalled - prevRecalled;
      if (diff > 0) {
        deltaText = '+$diff vs precedente';
      } else if (diff < 0) {
        deltaText = '$diff vs precedente';
      } else {
        deltaText = '= precedente';
      }
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          // Mini progress ring.
          SizedBox(
            width: 40,
            height: 40,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: ratio,
                  strokeWidth: 3.5,
                  backgroundColor: theme.colorScheme.onSurface
                      .withValues(alpha: 0.08),
                  color: ratio >= 0.8
                      ? const Color(0xFF4CAF50)
                      : ratio >= 0.5
                          ? const Color(0xFFFFB74D)
                          : const Color(0xFFEF5350),
                ),
                Text(
                  '${(ratio * 100).round()}%',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ultima: $recalled/$total ricordati · ${_fogLevelEmoji(fogLevel)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (deltaText != null)
                  Text(
                    deltaText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: deltaText.startsWith('+')
                          ? const Color(0xFF4CAF50)
                          : deltaText.startsWith('-')
                              ? const Color(0xFFEF5350)
                              : theme.colorScheme.onSurface
                                  .withValues(alpha: 0.5),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Session History tab — trend chart + session cards + insights.
  Widget _buildHistoryTab(ThemeData theme) {
    if (_sessionHistory.isEmpty) {
      return Center(
        child: Text(
          FlueraLocalizations.of(context)!.fow_historyEmpty,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      );
    }

    // Reversed so newest is on top.
    final sessions = _sessionHistory.reversed.toList();

    // Compute global stats for insights.
    final ratios = _sessionHistory.map((s) {
      final r = s['results'] as Map<String, dynamic>?;
      final recalled = (r?['recalled'] as num?)?.toInt() ?? 0;
      final total = (s['totalNodes'] as num?)?.toInt() ?? 1;
      return total > 0 ? recalled / total : 0.0;
    }).toList();
    final bestRatio = ratios.reduce(math.max);
    final bestIndex = ratios.indexOf(bestRatio);
    final latestRatio = ratios.last;
    final avgRatio = ratios.fold(0.0, (a, b) => a + b) / ratios.length;

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      children: [
        // ── 1. Recall trend chart ──
        if (_sessionHistory.length >= 2) ...[
          Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: CustomPaint(
              painter: _RecallTrendPainter(
                ratios: ratios,
                isDark: theme.brightness == Brightness.dark,
              ),
            ),
          ),
          // Legend.
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Prima sessione',
                  style: TextStyle(
                    fontSize: 9,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                ),
                Text(
                  'Media: ${(avgRatio * 100).round()}%',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
                Text(
                  'Ultima',
                  style: TextStyle(
                    fontSize: 9,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                ),
              ],
            ),
          ),
        ],

        // ── 2. Insight text ──
        _buildInsight(theme, ratios, latestRatio, bestRatio, bestIndex),

        const SizedBox(height: 8),

        // ── 3. Progress bar legend (shown once) ──
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 4),
          child: Row(
            children: [
              _legendDot(const Color(0xFF4CAF50), '✅ Ricordati', theme),
              const SizedBox(width: 12),
              _legendDot(const Color(0xFFEF5350), '❌ Dimenticati', theme),
              const SizedBox(width: 12),
              _legendDot(
                theme.colorScheme.onSurface.withValues(alpha: 0.3),
                '👁‍🗨 Non cercati',
                theme,
              ),
            ],
          ),
        ),

        // ── 4. Session cards ──
        ...List.generate(sessions.length, (index) {
          final session = sessions[index];
          final origIndex = _sessionHistory.length - 1 - index;
          return Padding(
            padding: EdgeInsets.only(bottom: index < sessions.length - 1 ? 8 : 0),
            child: _buildHistoryCard(
              theme, session, origIndex,
              isBest: origIndex == bestIndex && _sessionHistory.length > 1,
            ),
          );
        }),
      ],
    );
  }

  Widget _legendDot(Color color, String label, ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }

  Widget _buildInsight(ThemeData theme, List<double> ratios,
      double latest, double best, int bestIndex) {
    String text;
    Color color;
    String emoji;

    if (ratios.length >= 3) {
      final last3 = ratios.sublist(ratios.length - 3);
      final improving = last3[2] > last3[1] && last3[1] > last3[0];
      final declining = last3[2] < last3[1] && last3[1] < last3[0];

      if (improving) {
        text = '3 sessioni consecutive in crescita!';
        color = const Color(0xFF4CAF50);
        emoji = '📈';
      } else if (declining) {
        text = 'Trend in calo — prova nebbia più leggera per consolidare';
        color = const Color(0xFFFF9800);
        emoji = '💡';
      } else if (latest >= 0.9) {
        text = 'Padronanza eccellente — prova nebbia più densa!';
        color = const Color(0xFF4CAF50);
        emoji = '🔥';
      } else if (latest >= 0.7) {
        text = 'Buon livello — continua così';
        color = const Color(0xFF64B5F6);
        emoji = '💪';
      } else {
        text = 'Le lacune sono preziose — ora sai cosa ripassare';
        color = const Color(0xFF78909C);
        emoji = '🎯';
      }
    } else if (latest >= 0.8) {
      text = 'Ottimo inizio!';
      color = const Color(0xFF4CAF50);
      emoji = '✨';
    } else {
      text = 'Ogni sessione rafforza la memoria';
      color = const Color(0xFF78909C);
      emoji = '🧠';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(
    ThemeData theme,
    Map<String, dynamic> session,
    int sessionIndex, {
    bool isBest = false,
  }) {
    final results = session['results'] as Map<String, dynamic>?;
    final recalled = (results?['recalled'] as num?)?.toInt() ?? 0;
    final forgotten = (results?['forgotten'] as num?)?.toInt() ?? 0;
    final blindSpots = (results?['blind_spots'] as num?)?.toInt() ?? 0;
    final total = (session['totalNodes'] as num?)?.toInt() ?? 1;
    final ratio = total > 0 ? recalled / total : 0.0;
    final fogLevel = session['fogLevel'] as String? ?? 'light';
    final timestamp = session['timestamp'] as String?;

    // Parse date.
    String dateLabel = 'Sessione #${sessionIndex + 1}';
    if (timestamp != null) {
      try {
        final dt = DateTime.parse(timestamp);
        final now = DateTime.now();
        final diff = now.difference(dt);
        if (diff.inMinutes < 60) {
          dateLabel = '${diff.inMinutes} min fa';
        } else if (diff.inHours < 24) {
          dateLabel = '${diff.inHours}h fa';
        } else if (diff.inDays == 1) {
          dateLabel = 'Ieri ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        } else if (diff.inDays < 7) {
          dateLabel = '${diff.inDays} giorni fa';
        } else {
          dateLabel =
              '${dt.day}/${dt.month}/${dt.year}';
        }
      } catch (_) {}
    }

    // Delta vs previous session.
    String? deltaText;
    Color deltaColor = theme.colorScheme.onSurface.withValues(alpha: 0.5);
    if (sessionIndex > 0) {
      final prev = _sessionHistory[sessionIndex - 1];
      final prevResults = prev['results'] as Map<String, dynamic>?;
      final prevRecalled = (prevResults?['recalled'] as num?)?.toInt() ?? 0;
      final diff = recalled - prevRecalled;
      if (diff > 0) {
        deltaText = '↑ +$diff';
        deltaColor = const Color(0xFF4CAF50);
      } else if (diff < 0) {
        deltaText = '↓ $diff';
        deltaColor = const Color(0xFFEF5350);
      }
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isBest
            ? const Color(0xFFFFD600).withValues(alpha: 0.06)
            : theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isBest
              ? const Color(0xFFFFD600).withValues(alpha: 0.3)
              : theme.colorScheme.outline.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: session label + delta.
          Row(
            children: [
              Text(
                '${isBest ? "🏆" : "⚔️"} #${sessionIndex + 1}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${_fogLevelEmoji(fogLevel)} ${_fogLevelLabel(fogLevel)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const Spacer(),
              Text(
                dateLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 10,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Progress bar.
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  // Green: recalled.
                  if (recalled > 0)
                    Expanded(
                      flex: recalled,
                      child: Container(color: const Color(0xFF4CAF50)),
                    ),
                  // Red: forgotten.
                  if (forgotten > 0)
                    Expanded(
                      flex: forgotten,
                      child: Container(color: const Color(0xFFEF5350)),
                    ),
                  // Grey: blind spots.
                  if (blindSpots > 0)
                    Expanded(
                      flex: blindSpots,
                      child: Container(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.15),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),

          // Duration + speed row (I).
          Builder(builder: (_) {
            final durSec = (session['durationSeconds'] as num?)?.toInt();
            final avgMs = (session['avgResponseTimeMs'] as num?)?.toInt();
            final avgConf = (session['avgConfidence'] as num?)?.toDouble();

            if (durSec == null && avgMs == null) {
              return const SizedBox.shrink();
            }

            final parts = <String>[];
            if (durSec != null && durSec > 0) {
              final m = durSec ~/ 60;
              final s = durSec % 60;
              parts.add('⏱️ $m:${s.toString().padLeft(2, '0')}');
            }
            if (avgMs != null && avgMs > 0) {
              parts.add('${(avgMs / 1000).toStringAsFixed(1)}s/nodo');
            }
            if (avgConf != null && avgConf > 0) {
              parts.add('conf ${avgConf.toStringAsFixed(1)}/5');
            }

            if (parts.isEmpty) return const SizedBox.shrink();

            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                parts.join(' · '),
                style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
            );
          }),

          // Bottom row: stats + delta.
          Row(
            children: [
              Text(
                '✅ $recalled',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF4CAF50),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '❌ $forgotten',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFEF5350),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '👁‍🗨 $blindSpots',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
              if (deltaText != null) ...[
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: deltaColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    deltaText,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: deltaColor,
                    ),
                  ),
                ),
              ],
            ],
          ),

          // K: Confidence trend sparkline (last N sessions up to this one).
          Builder(builder: (_) {
            // Collect avgConfidence for sessions 0..sessionIndex (inclusive).
            final confValues = <double>[];
            final windowStart = (sessionIndex - 4).clamp(0, sessionIndex);
            for (int i = windowStart; i <= sessionIndex; i++) {
              final c = (_sessionHistory[i]['avgConfidence'] as num?)?.toDouble();
              if (c != null && c > 0) confValues.add(c);
            }
            if (confValues.length < 2) return const SizedBox.shrink();

            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Text(
                    '📊',
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 60,
                    height: 16,
                    child: CustomPaint(
                      painter: _ConfidenceSparklinePainter(
                        values: confValues,
                        isDark: theme.brightness == Brightness.dark,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    confValues.last >= confValues.first ? '↗' : '↘',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: confValues.last >= confValues.first
                          ? const Color(0xFF4CAF50)
                          : const Color(0xFFEF5350),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  String _fogLevelEmoji(String level) {
    switch (level) {
      case 'light': return '🌤️';
      case 'medium': return '🌫️';
      case 'total': return '🌑';
      default: return '🌫️';
    }
  }

  String _fogLevelLabel(String level) {
    switch (level) {
      case 'light': return 'Leggera';
      case 'medium': return 'Media';
      case 'total': return 'Totale';
      default: return level;
    }
  }
}

// ============================================================================
// 🌫️ Fog Level Picker Option Widget
// ============================================================================


class _FogLevelOption extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final String difficulty;
  final Color color;
  final VoidCallback onTap;

  const _FogLevelOption({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.difficulty,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style:
                          Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style:
                          Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.6),
                              ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  difficulty,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 💡 Directional Hint Arrow — Visual compass overlay for Tier 1 hints
// ============================================================================

/// A visual arrow overlay centered on the screen that rotates to point
/// toward the nearest unrevealed node. Includes:
/// - A pulsing ring at center marking "you are here"
/// - A rotating arrow pointing toward the target
/// - A distance label (Vicinissimo/Vicino/Media distanza/Lontano)
///
/// This replaces the old text-only snackbar ("→") which was confusing
/// because the student couldn't see the reference point.
class _FogDirectionalArrow extends StatefulWidget {
  final double angle; // radians
  final String distanceLabel;

  const _FogDirectionalArrow({
    required this.angle,
    required this.distanceLabel,
  });

  @override
  State<_FogDirectionalArrow> createState() => _FogDirectionalArrowState();
}

class _FogDirectionalArrowState extends State<_FogDirectionalArrow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        final pulse = _pulseController.value; // 0.0 → 1.0 → 0.0
        return CustomPaint(
          painter: _DirectionalArrowPainter(
            angle: widget.angle,
            distanceLabel: widget.distanceLabel,
            pulse: pulse,
            isDark: Theme.of(context).brightness == Brightness.dark,
          ),
        );
      },
    );
  }
}

class _DirectionalArrowPainter extends CustomPainter {
  final double angle;
  final String distanceLabel;
  final double pulse;
  final bool isDark;

  _DirectionalArrowPainter({
    required this.angle,
    required this.distanceLabel,
    required this.pulse,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint();

    // ── 1. "You are here" pulsing ring ──
    final ringRadius = 16.0 + pulse * 6.0;
    final ringAlpha = 0.5 + pulse * 0.3;
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = Color.fromRGBO(255, 143, 0, ringAlpha);
    canvas.drawCircle(center, ringRadius, paint);

    // Inner dot.
    paint
      ..style = PaintingStyle.fill
      ..color = const Color.fromRGBO(255, 143, 0, 0.8);
    canvas.drawCircle(center, 5.0, paint);

    // ── 2. "Sei qui" label below center ──
    final hereTP = TextPainter(
      text: TextSpan(
        text: 'Sei qui',
        style: TextStyle(
          color: Color.fromRGBO(255, 143, 0, 0.7 + pulse * 0.3),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    hereTP.paint(canvas, center + Offset(-hereTP.width / 2, 28));

    // ── 3. Arrow shaft + head pointing toward node ──
    final arrowStart = 35.0; // start past the ring
    final arrowEnd = 80.0 + pulse * 10.0; // pulsing length

    final dx = math.cos(angle);
    final dy = math.sin(angle);

    final startPt = center + Offset(dx * arrowStart, dy * arrowStart);
    final endPt = center + Offset(dx * arrowEnd, dy * arrowEnd);

    // Arrow shaft (thick, glowing).
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round
      ..color = Color.fromRGBO(255, 143, 0, 0.6 + pulse * 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);
    canvas.drawLine(startPt, endPt, paint);
    paint.maskFilter = null;

    // Arrow shaft (crisp, on top).
    paint
      ..strokeWidth = 2.5
      ..color = Color.fromRGBO(255, 183, 0, 0.8 + pulse * 0.2);
    canvas.drawLine(startPt, endPt, paint);

    // Arrowhead (triangle).
    final headSize = 12.0;
    final perpDx = -dy; // perpendicular
    final perpDy = dx;

    final headTip = center + Offset(dx * (arrowEnd + 4), dy * (arrowEnd + 4));
    final headLeft = endPt + Offset(
      perpDx * headSize * 0.5 - dx * headSize * 0.3,
      perpDy * headSize * 0.5 - dy * headSize * 0.3,
    );
    final headRight = endPt + Offset(
      -perpDx * headSize * 0.5 - dx * headSize * 0.3,
      -perpDy * headSize * 0.5 - dy * headSize * 0.3,
    );

    final headPath = Path()
      ..moveTo(headTip.dx, headTip.dy)
      ..lineTo(headLeft.dx, headLeft.dy)
      ..lineTo(headRight.dx, headRight.dy)
      ..close();

    paint
      ..style = PaintingStyle.fill
      ..color = Color.fromRGBO(255, 183, 0, 0.8 + pulse * 0.2);
    canvas.drawPath(headPath, paint);

    // ── 4. Distance label along the arrow ──
    final labelOffset = center + Offset(
      dx * (arrowEnd + 22),
      dy * (arrowEnd + 22),
    );

    // Background pill.
    final labelTP = TextPainter(
      text: TextSpan(
        text: distanceLabel,
        style: TextStyle(
          color: isDark ? Colors.white : const Color(0xFF1A1A2E),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final pillRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: labelOffset,
        width: labelTP.width + 16,
        height: labelTP.height + 8,
      ),
      const Radius.circular(8),
    );

    paint
      ..style = PaintingStyle.fill
      ..color = isDark
          ? const Color.fromRGBO(255, 143, 0, 0.85)
          : const Color.fromRGBO(255, 143, 0, 0.9);
    canvas.drawRRect(pillRect, paint);

    labelTP.paint(
      canvas,
      labelOffset - Offset(labelTP.width / 2, labelTP.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _DirectionalArrowPainter old) =>
      angle != old.angle ||
      distanceLabel != old.distanceLabel ||
      (pulse - old.pulse).abs() > 0.02;
}

// ============================================================================
// 📋 Mastery Map Legend (J) — Collapsible onboarding overlay
// ============================================================================

class _FogMasteryLegend extends StatefulWidget {
  @override
  State<_FogMasteryLegend> createState() => _FogMasteryLegendState();
}

class _FogMasteryLegendState extends State<_FogMasteryLegend> {
  bool _expanded = false;

  static const _entries = <(String, String, Color)>[
    ('✅', 'Ricordato', Color(0xFF4CAF50)),
    ('❌', 'Dimenticato', Color(0xFFF44336)),
    ('👁\u200D🗨', 'Non visitato', Color(0xFF9E9E9E)),
    ('⏱️', 'Recall lento (>8s)', Color(0xFFFF9800)),
    ('⚠️', 'Critico ultima volta', Color(0xFFFFB74D)),
    ('📖', 'Contenuto rivelato', Color(0xFF64B5F6)),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xDD1A1A2E)
              : const Color(0xEEF5F5FA),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header.
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('📋', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Text(
                  'Legenda',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
              ],
            ),
            // Expanded entries.
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 200),
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (emoji, label, color) in _entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '$emoji $label',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? Colors.white60
                                    : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              crossFadeState: _expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 📈 Recall Trend Painter — Global recall % trend across all sessions
// ============================================================================

class _RecallTrendPainter extends CustomPainter {
  final List<double> ratios; // 0.0–1.0 recall ratios per session
  final bool isDark;

  _RecallTrendPainter({required this.ratios, this.isDark = false});

  @override
  void paint(Canvas canvas, Size size) {
    if (ratios.length < 2) return;

    final n = ratios.length;
    final dx = size.width / (n - 1);
    double yForVal(double v) => size.height - v * size.height;

    // Fill area under the curve.
    final fillPath = Path()..moveTo(0, size.height);
    for (int i = 0; i < n; i++) {
      fillPath.lineTo(i * dx, yForVal(ratios[i]));
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..style = PaintingStyle.fill
        ..color = isDark
            ? const Color.fromRGBO(76, 175, 80, 0.08)
            : const Color.fromRGBO(76, 175, 80, 0.06),
    );

    // Line.
    final linePath = Path();
    for (int i = 0; i < n; i++) {
      final x = i * dx;
      final y = yForVal(ratios[i]);
      if (i == 0) {
        linePath.moveTo(x, y);
      } else {
        linePath.lineTo(x, y);
      }
    }

    canvas.drawPath(
      linePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..color = isDark
            ? const Color.fromRGBO(76, 175, 80, 0.6)
            : const Color.fromRGBO(76, 175, 80, 0.5),
    );

    // Dots.
    final dotPaint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < n; i++) {
      final x = i * dx;
      final y = yForVal(ratios[i]);
      final v = ratios[i];

      dotPaint.color = v >= 0.8
          ? const Color(0xFF4CAF50)
          : v >= 0.5
              ? const Color(0xFFFFB74D)
              : const Color(0xFFEF5350);
      canvas.drawCircle(Offset(x, y), i == n - 1 ? 4.0 : 2.5, dotPaint);
    }

    // 70% threshold line.
    final threshY = yForVal(0.7);
    canvas.drawLine(
      Offset(0, threshY),
      Offset(size.width, threshY),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        ..color = isDark
            ? const Color.fromRGBO(255, 255, 255, 0.1)
            : const Color.fromRGBO(0, 0, 0, 0.08),
    );
  }

  @override
  bool shouldRepaint(covariant _RecallTrendPainter old) =>
      ratios.length != old.ratios.length;
}

// ============================================================================
// 📊 Confidence Sparkline Painter (K) — Mini trend chart
// ============================================================================

class _ConfidenceSparklinePainter extends CustomPainter {
  final List<double> values; // avgConfidence values (1.0–5.0)
  final bool isDark;

  _ConfidenceSparklinePainter({required this.values, this.isDark = false});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    final n = values.length;
    final dx = size.width / (n - 1);
    // Map 1..5 → size.height..0
    double yForVal(double v) =>
        size.height - ((v - 1.0) / 4.0).clamp(0.0, 1.0) * size.height;

    // Draw connecting line.
    final path = Path();
    for (int i = 0; i < n; i++) {
      final x = i * dx;
      final y = yForVal(values[i]);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..color = isDark
          ? const Color.fromRGBO(180, 200, 255, 0.5)
          : const Color.fromRGBO(100, 140, 220, 0.5);
    canvas.drawPath(path, linePaint);

    // Draw dots.
    for (int i = 0; i < n; i++) {
      final x = i * dx;
      final y = yForVal(values[i]);
      final v = values[i];

      Color dotColor;
      if (v > 3.5) {
        dotColor = const Color(0xFF4CAF50); // green
      } else if (v > 2.0) {
        dotColor = const Color(0xFFFFB74D); // amber
      } else {
        dotColor = const Color(0xFF9E9E9E); // grey
      }

      canvas.drawCircle(
        Offset(x, y),
        2.5,
        Paint()
          ..style = PaintingStyle.fill
          ..color = dotColor,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ConfidenceSparklinePainter old) =>
      values != old.values;
}

