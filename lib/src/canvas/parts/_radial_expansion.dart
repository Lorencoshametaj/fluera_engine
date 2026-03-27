part of '../fluera_canvas_screen.dart';

/// 🌟 ESPANSIONE A RAGGIERA v2 — Minority Report Flow
///
/// GESTURE:
///   1. Long-press cluster → ring charges up (haptic pulse)
///   2. Release finger    → OCR re-reads text → AI generates sub-topics
///   3. Bubbles EXPLODE outward with launch trails
///   4. Drag bubble OUTWARD > threshold → confirm → new node + connection
///   5. Tap bubble (< 20px drag) → confirm at target position
///   5. Drag bubble INWARD → dismiss
extension RadialExpansionWiring on _FlueraCanvasScreenState {

  // ── TRIGGER: Called from _onLongPress when a cluster is hit ───────────────

  /// Start the charge animation. Also kicks off OCR on-demand.
  void _startRadialCharge(ContentCluster cluster) {
    final controller = _radialExpansionController;
    if (controller == null) return;
    if (controller.phase != RadialExpansionPhase.idle) return;

    // Start OCR on-demand (non-blocking) so text is ready when generate() fires
    _recognizeClusterTextOnDemand(cluster);

    var clusterText = _clusterTextCache[cluster.id] ?? '';
    if (clusterText.trim().isEmpty) clusterText = 'Idea';



    controller.onPhaseChanged = (phase) {

      if (mounted) {
        _uiRebuildNotifier.value++;
        if (phase != RadialExpansionPhase.idle) _startRadialExpansionTick();
      }
    };
    controller.onBubblesUpdated = () {
      if (mounted) _uiRebuildNotifier.value++;
    };

    controller.startCharge(cluster.id, cluster.centroid, clusterText);
    _radialExpansionLongPressCluster = cluster;
    _startRadialExpansionTick();
    HapticFeedback.mediumImpact();
  }

  /// Release the charge → fire AI generation.
  /// Re-reads text from cache (OCR may have completed during hold).
  /// Also gathers nearby cluster texts for context-aware suggestions.
  void _releaseRadialCharge() {
    final controller = _radialExpansionController;
    if (controller == null || controller.phase != RadialExpansionPhase.charging) return;


    final language = _deviceLanguageName;
    final cluster = _radialExpansionLongPressCluster;

    // Re-read text: OCR may have completed during the hold
    if (cluster != null) {
      final freshText = _clusterTextCache[cluster.id] ?? '';
      if (freshText.trim().isNotEmpty) {
        controller.updateSourceText(freshText);

      }

      // 🧠 Context-awareness: gather texts from nearby clusters
      final srcPos = cluster.centroid;
      const contextRadius = 500.0; // canvas px
      final nearbyTexts = _clusterCache
          .where((c) =>
              c.id != cluster.id &&
              (c.centroid - srcPos).distance < contextRadius)
          .map((c) => _clusterTextCache[c.id] ?? '')
          .where((t) => t.trim().isNotEmpty)
          .take(5)
          .toList();

      if (nearbyTexts.isNotEmpty) {
        final context = nearbyTexts.join(', ');
        controller.updateNearbyContext(context);

      }
    }

    controller.generate(deviceLanguage: language).then((labels) {

      if (labels.isNotEmpty && mounted) {
        HapticFeedback.heavyImpact();
      }
    }).catchError((e) {

    });
  }

  // ── TICK ──────────────────────────────────────────────────────────────────

  void _startRadialExpansionTick() {
    if (_radialExpansionTimer?.isActive == true) return;
    _radialExpansionHapticThreshold = 0.0;
    _radialExpansionTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) {
        final controller = _radialExpansionController;
        if (controller == null || controller.phase == RadialExpansionPhase.idle) {
          _radialExpansionTimer?.cancel();
          _radialExpansionTimer = null;
          return;
        }

        // 📳 Haptic escalation during charge
        if (controller.phase == RadialExpansionPhase.charging) {
          final p = controller.chargeProgress;
          if (p >= 1.0 && _radialExpansionHapticThreshold < 1.0) {
            _radialExpansionHapticThreshold = 1.0;
            HapticFeedback.heavyImpact();
          } else if (p >= 0.66 && _radialExpansionHapticThreshold < 0.66) {
            _radialExpansionHapticThreshold = 0.66;
            HapticFeedback.mediumImpact();
          } else if (p >= 0.33 && _radialExpansionHapticThreshold < 0.33) {
            _radialExpansionHapticThreshold = 0.33;
            HapticFeedback.selectionClick();
          }
        }

        final changed = controller.tick(0.016);
        if (changed && mounted) _uiRebuildNotifier.value++;
      },
    );
  }

  // ── DRAG-TO-CONFIRM GESTURE ───────────────────────────────────────────────

  /// Start dragging a bubble (called from _onDrawStart when a bubble is hit).
  void _startRadialBubbleDrag(GhostBubble bubble, Offset canvasPos) {
    final controller = _radialExpansionController;
    if (controller == null) return;
    controller.startBubbleDrag(bubble.id);
    _radialDraggedBubbleId = bubble.id;
    _radialDragStartCanvas = canvasPos;
    HapticFeedback.selectionClick();
  }

  /// Update bubble drag position (called from _onDrawUpdate).
  void updateRadialBubbleDrag(Offset canvasPos) {
    final controller = _radialExpansionController;
    if (controller == null || _radialDraggedBubbleId == null || _radialDragStartCanvas == null) return;
    final delta = canvasPos - _radialDragStartCanvas!;
    controller.updateBubbleDrag(_radialDraggedBubbleId!, delta);
  }

  /// Finalize bubble drag (called from _onDrawEnd).
  void finalizeRadialBubbleDrag() {
    final controller = _radialExpansionController;
    final bubbleId = _radialDraggedBubbleId;
    if (controller == null || bubbleId == null) return;

    _radialDraggedBubbleId = null;
    _radialDragStartCanvas = null;

    final result = controller.finalizeBubbleDrag(bubbleId);
    if (result != null) {
      _onRadialBubbleConfirmed(result.label, result.position);
    }
  }

  // ── CONFIRM: Create real node + connection ────────────────────────────────

  void _onRadialBubbleConfirmed(String label, Offset canvasPos) {
    HapticFeedback.heavyImpact();

    final textElement = DigitalTextElement(
      id: 'radial_${DateTime.now().microsecondsSinceEpoch}',
      text: label,
      position: canvasPos,
      fontSize: 18,
      color: const Color(0xFF00E5FF),
      createdAt: DateTime.now(),
    );

    final activeLayer = _layerController.layers
        .firstWhere((l) => l.id == _layerController.activeLayerId);
    activeLayer.node.addText(textElement);
    _digitalTextElements.add(textElement);

    if (_knowledgeFlowController != null &&
        _radialExpansionController?.sourceClusterId != null) {
      _rebuildClusterCache();
      final newCluster = _clusterCache
          .where((c) => c.textIds.contains(textElement.id))
          .firstOrNull;
      if (newCluster != null) {
        _knowledgeFlowController!.addConnection(
          sourceClusterId: _radialExpansionController!.sourceClusterId!,
          targetClusterId: newCluster.id,
          label: null,
        );
        if (_knowledgeParticleTicker != null && !_knowledgeParticleTicker!.isActive) {
          _knowledgeParticleTicker!.start();
        }
      }
    }

    _layerController.sceneGraph.bumpVersion();
    DrawingPainter.invalidateAllTiles();
    _autoSaveCanvas();
    if (mounted) setState(() {});
  }

  // ── HIT TEST ─────────────────────────────────────────────────────────────

  GhostBubble? _hitTestRadialBubble(Offset canvasPoint) {
    return _radialExpansionController?.hitTest(
      canvasPoint,
      radius: 50.0 / _canvasController.scale,
    );
  }

  /// Intercept draw-start during presenting → start bubble drag.
  /// Returns true if consumed.
  bool _handleRadialExpansionDrawStart(Offset canvasPoint) {
    final controller = _radialExpansionController;
    if (controller == null || controller.phase != RadialExpansionPhase.presenting) return false;

    final bubble = _hitTestRadialBubble(canvasPoint);
    if (bubble != null) {
      _startRadialBubbleDrag(bubble, canvasPoint);
      return true;
    }

    // Tapped empty space → dismiss all
    controller.dismissAll();
    return true;
  }

  // ── OCR ON DEMAND ────────────────────────────────────────────────────────

  /// Recognize the text of a single cluster via ML Kit, directly
  /// (bypasses SemanticMorphController availability guard).
  /// Non-blocking: stores result in `_clusterTextCache[cluster.id]`.
  Future<void> _recognizeClusterTextOnDemand(ContentCluster cluster) async {
    // Cache hit: non-empty text already known
    if (_clusterTextCache[cluster.id]?.isNotEmpty == true) {

      return;
    }



    // Digital text elements (no OCR needed)
    final textParts = <String>[];
    for (final tid in cluster.textIds) {
      final el = _digitalTextElements.firstWhere(
        (e) => e.id == tid,
        orElse: () => DigitalTextElement(
          id: '', text: '', position: Offset.zero, fontSize: 0,
          color: const Color(0xFF000000), createdAt: DateTime.now(),
        ),
      );
      if (el.id.isNotEmpty && el.text.trim().isNotEmpty) {
        textParts.add(el.text.trim());
      }
    }

    // Collect strokes for ink recognition
    final activeLayer = _layerController.layers.firstWhere(
      (l) => l.id == _layerController.activeLayerId,
      orElse: () => _layerController.layers.first,
    );
    final strokeSets = <List<ProDrawingPoint>>[];
    for (final sid in cluster.strokeIds) {
      final stroke = activeLayer.strokes.where((s) => s.id == sid).firstOrNull;
      if (stroke != null && !stroke.isStub && stroke.points.length >= 3) {
        strokeSets.add(stroke.points);
      }
    }

    final inkService = DigitalInkService.instance;
    String recognized = '';
    if (strokeSets.isNotEmpty && inkService.isAvailable) {
      recognized = await inkService.recognizeMultiStroke(strokeSets) ?? '';
    }

    final combined = [...textParts, if (recognized.isNotEmpty) recognized]
        .join(' ')
        .trim();
    _clusterTextCache[cluster.id] = combined;



    // Update controller if still in charging phase
    if (combined.isNotEmpty) {
      _radialExpansionController?.updateSourceText(combined);
    }
  }

  // ── CLEANUP ───────────────────────────────────────────────────────────────

  void _disposeRadialExpansion() {
    _radialExpansionTimer?.cancel();
    _radialExpansionTimer = null;
    _radialExpansionController?.dispose();
  }
}
