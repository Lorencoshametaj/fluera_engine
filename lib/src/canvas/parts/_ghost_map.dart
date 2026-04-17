part of '../fluera_canvas_screen.dart';

/// 🗺️ GHOST MAP / CONFRONTO CENTAURO — Step 4 of the cognitive mastery cycle.
///
/// When activated, Atlas AI analyzes the visible clusters and generates an
/// "ideal" concept map overlay. Ghost nodes show missing concepts, weak
/// nodes flag errors, and correct nodes confirm mastery.
///
/// The student can tap ghost nodes to attempt writing the missing concept,
/// then reveal Atlas's answer for comparison (Hypercorrection Principle).
///
/// Integration points:
///   - Triggered from toolbar (🗺️ button) or step controller (step ≥ 4)
///   - Uses `_clusterCache` and `_clusterTextCache` for context
///   - Renders via `GhostMapOverlayPainter` in the canvas layer stack
///   - Tap interception via `_drawing_handlers.dart`
extension FlueraGhostMapExtension on _FlueraCanvasScreenState {

  /// 🗺️ P4-26: Canvas snapshot taken BEFORE ghost map activation.
  /// Used for before/after comparison to visualize growth.
  static Uint8List? _ghostMapBeforeSnapshot;

  /// 🗺️ P4-26: Capture a low-res PNG of the current canvas viewport.
  Future<Uint8List?> _captureGhostMapSnapshot() async {
    try {
      final boundary =
          _canvasRepaintBoundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null || !boundary.hasSize) return null;

      // ~320px on the long side for lightweight comparison
      final logicalSize = boundary.size;
      final longestSide = math.max(logicalSize.width, logicalSize.height);
      if (longestSide <= 0) return null;
      final pixelRatio = (320.0 / longestSide).clamp(0.1, 1.0);

      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();

      if (byteData == null) return null;
      return byteData.buffer.asUint8List();
    } catch (e) {
      debugPrint('🗺️ Snapshot capture failed: $e');
      return null;
    }
  }

  // ── ON-DEMAND OCR ─────────────────────────────────────────────────────

  /// 🔤 Recognize handwriting in **visible** clusters only for Ghost Map.
  /// Sequential processing to avoid platform channel contention.
  Future<void> _recognizeClusterTextsForGhostMap() async {
    if (_clusterCache.isEmpty) return;

    final inkService = DigitalInkService.instance;

    // 🔴 HTR DEGRADED MODE: Warn the user if handwriting recognition
    // is not available on this platform (desktop, web).
    if (!inkService.isAvailable && mounted) {
      final hasHandwriting = _clusterCache.any((c) => c.strokeIds.isNotEmpty);
      if (hasHandwriting) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _l10n.htr_unavailableOnPlatform,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.only(bottom: 80, left: 20, right: 20),
            duration: const Duration(seconds: 5),
            backgroundColor: const Color(0xFFE65100),
          ),
        );
      }
    }

    // 🗺️ Only process clusters visible in the current viewport
    final size = MediaQuery.of(context).size;
    final topLeft = _canvasController.screenToCanvas(Offset.zero);
    final bottomRight = _canvasController.screenToCanvas(
      Offset(size.width, size.height),
    );
    final viewportRect = Rect.fromPoints(topLeft, bottomRight);

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
      if (cluster.strokeIds.isEmpty && cluster.textIds.isEmpty) continue;
      if (_clusterTextCache.containsKey(cluster.id)) continue;

      // Skip clusters outside the viewport
      if (!viewportRect.overlaps(cluster.bounds)) {
        continue;
      }

      // Digital text: include directly
      final textParts = <String>[];
      for (final tid in cluster.textIds) {
        final textEl = textMap[tid];
        if (textEl != null && textEl.text.trim().isNotEmpty) {
          textParts.add(textEl.text.trim());
        }
      }

      // Collect stroke data for recognition
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

      // 🔤 Sequential recognition — force TEXT mode (not auto/math)
      if (strokeSets.isNotEmpty && inkService.isAvailable) {
        final recognized = await inkService.engine.recognizeTextMode(strokeSets);
        final parts = [...textParts];
        if (recognized != null && recognized.isNotEmpty) {
          parts.add(recognized);
        }
        _clusterTextCache[cluster.id] = parts.join(' ');
      } else if (textParts.isNotEmpty) {
        _clusterTextCache[cluster.id] = textParts.join(' ');
      }
    }
  }

  // ── TRIGGER ──────────────────────────────────────────────────────────────

  /// Trigger ghost map generation from the current visible clusters.
  ///
  /// Called from the toolbar button or auto-suggestion when step ≥ 4.
  Future<void> triggerGhostMap() async {
    final controller = _ghostMapController;
    if (controller.isLoading) return;

    // 🚦 A15: Step prerequisite gate — Ghost Map requires at least Step 4.
    if (!_checkStepGate(LearningStep.step4GhostMap,
        onProceed: () => _triggerGhostMapCore())) {
      return;
    }

    await _triggerGhostMapCore();
  }

  /// Core implementation of ghost map generation (separated for step gate bypass).
  Future<void> _triggerGhostMapCore() async {
    final controller = _ghostMapController;
    if (controller.isLoading) return;

    // 💳 A17: Tier gate — Free tier: 1 Ghost Map comparison/week.
    if (!_checkTierGate(GatedFeature.ghostMapComparison)) {
      return;
    }

    // 🗺️ On-demand OCR: populate cluster text cache for unrecognized clusters.
    // This bypasses the Step 3+ gate on _scheduleSemanticOcr() so
    // Ghost Map works at any learning step.
    final hasUnrecognized = _clusterCache.any((c) =>
        (c.strokeIds.isNotEmpty || c.textIds.isNotEmpty) &&
        !_clusterTextCache.containsKey(c.id));
    if (hasUnrecognized) {
      await _recognizeClusterTextsForGhostMap();
    }

    // Collect context from visible clusters
    final clusterTexts = <String, String>{};
    final clusterTitles = <String, String>{};

    for (final cluster in _clusterCache) {
      final text = _clusterTextCache[cluster.id];
      if (text != null && text.trim().isNotEmpty) {
        clusterTexts[cluster.id] = text;
      }
      // Semantic titles from SemanticMorphController
      final title = _semanticMorphController?.aiTitles[cluster.id];
      if (title != null) {
        clusterTitles[cluster.id] = title;
      }
    }

    debugPrint('🗺️ triggerGhostMap: ${_clusterCache.length} clusters, ${_clusterTextCache.length} texts → ${clusterTexts.length} valid');
    for (final entry in clusterTexts.entries) {
      debugPrint('🗺️   cluster ${entry.key.substring(0, 8)}: "${entry.value}"');
    }

    if (clusterTexts.length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_l10n.ghostMap_writeAtLeastTwoGroups),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.only(bottom: 80, left: 20, right: 20),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    // Haptic feedback
    HapticFeedback.mediumImpact();

    // 🎵 A13.4: "L'IA sta esplorando" — ascending sweep 200→800Hz
    PedagogicalSoundEngine.instance.play(PedagogicalSound.ghostMapScan);

    // 🗺️ P4-26: Capture "before" snapshot before generation
    _ghostMapBeforeSnapshot = await _captureGhostMapSnapshot();

    // 🗺️ QW-5: Show loading indicator during generation
    ScaffoldMessengerState? messenger;
    if (mounted) {
      messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Text(_l10n.ghostMap_loadingAnalyzing),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.only(bottom: 80, left: 20, right: 20),
          duration: const Duration(seconds: 15),
          backgroundColor: const Color(0xFF37474F),
        ),
      );
    }

    // 🗺️ P4-21/22/23: Collect Passo 3 Socratic data for enrichment
    final socraticData = _collectSocraticDataForGhostMap();

    // Generate ghost map
    await controller.generateGhostMap(
      clusterTexts: clusterTexts,
      clusterTitles: clusterTitles,
      clusters: _clusterCache,
      existingConnections: _knowledgeFlowController?.connections ?? [],
      socraticContext: socraticData,
    );

    // 🗺️ Post-process: enrich ghost nodes with Passo 3 data
    if (controller.isActive && controller.result != null) {
      _enrichGhostNodesFromSocratic(controller.result!, socraticData);
    }

    // Dismiss loading snackbar
    messenger?.hideCurrentSnackBar();

    if (controller.isActive) {
      // Usage already recorded by _checkTierGate() above.

      // 🗺️ P4-24: Reset opacity to 1.0 when activating
      _ghostMapOpacity.value = 1.0;
      // U-1: Start entry stagger timer
      _ghostMapEntryTimer.reset();
      _ghostMapEntryTimer.start();
      // Start pulse animation
      _ghostMapAnimController?.repeat();
      if (!mounted) return;
      setState(() {});
      if (mounted) {
        final missing = controller.totalMissing;
        final correct = controller.totalCorrect;

        // 🗺️ P4-29/33: Edge case messages
        final edgeMsg = controller.edgeCaseMessage;
        if (edgeMsg != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(edgeMsg),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.only(bottom: 80, left: 20, right: 20),
              duration: const Duration(seconds: 4),
              backgroundColor: missing <= 2
                  ? const Color(0xFF2E7D32) // green for almost perfect
                  : const Color(0xFF37474F), // neutral for incomplete
            ),
          );
        } else {
          final msgParts = <String>[];
          if (missing > 0) msgParts.add(_l10n.ghostMap_activationGapsFound(missing));
          if (correct > 0) msgParts.add(_l10n.ghostMap_activationConfirmed(correct));
          if (controller.totalHypercorrection > 0) {
            msgParts.add(_l10n.ghostMap_activationHypercorrections(controller.totalHypercorrection));
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_l10n.ghostMap_activationHeader(msgParts.join(', '))),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.only(bottom: 80, left: 20, right: 20),
              duration: const Duration(seconds: 3),
              backgroundColor: const Color(0xFF1565C0),
            ),
          );
        }
      }
    } else if (controller.error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(controller.error!),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.only(bottom: 80, left: 20, right: 20),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // ── TAP HANDLING ─────────────────────────────────────────────────────────

  /// Handle a tap on the ghost map overlay.
  ///
  /// Returns `true` if the tap was consumed (ghost node hit), `false` otherwise.
  bool handleGhostMapTap(Offset canvasPosition) {
    final controller = _ghostMapController;
    if (!controller.isActive) return false;

    final node = controller.hitTestGhostNode(canvasPosition);
    if (node == null) return false;

    HapticFeedback.lightImpact();

    if (node.isMissing && !node.isRevealed) {
      // Inline attempt on canvas — preserves stylus flow (§3, §5, §13, T4)
      _startInlineGhostAttempt(node);
    } else if (node.isWeak && node.explanation != null) {
      // Show explanation popup
      _showGhostExplanationPopup(node);
    } else if (node.isCorrect) {
      // 🗺️ P4-13: Show green confirmation popup for correct nodes
      _showGhostExplanationPopup(node);
    } else if (node.isWrongConnection) {
      // 🗺️ P4-11: Show wrong connection popup (no correction hint)
      _showGhostExplanationPopup(node);
    }

    return true;
  }
}
