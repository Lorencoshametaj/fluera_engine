part of '../fluera_canvas_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 💬 CHAT WITH NOTES — Canvas Integration
//
// Wires ChatSessionController + ChatOverlay into the canvas screen.
// Launched via OverlayEntry (same pattern as ExamOverlay).
// ─────────────────────────────────────────────────────────────────────────────

extension ChatWithNotesWiring on _FlueraCanvasScreenState {

  /// Start the Chat with Notes session.
  ///
  /// 1. Ensures cluster OCR text is ready (reuses [_clusterTextCache])
  /// 2. Creates [ChatSessionController] with canvas context
  /// 3. Mounts [ChatOverlay] as a slide-in OverlayEntry
  Future<void> _startChatWithNotes() async {
    // Ensure OCR text is available
    if (_clusterCache.isNotEmpty) {
      await _recognizeClusterTextsForSemanticTitles();
    }

    final provider = EngineScope.current.atlasProvider;
    if (!provider.isInitialized) await provider.initialize();

    // OverlayEntry is captured by the router callbacks so the chips can
    // close the chat before opening the destination feature. Declared
    // `late` so the closures can capture it before assignment.
    late OverlayEntry entry;
    late ChatSessionController chatController;

    final router = ChatActionRouter(
      onTriggerGhostMap: () {
        entry.remove();
        chatController.dispose();
        unawaited(triggerGhostMap());
      },
      onTriggerExam: () {
        entry.remove();
        chatController.dispose();
        unawaited(_startExamSession());
      },
      onTriggerSocraticOnCluster: (clusterId) {
        entry.remove();
        chatController.dispose();
        // Socratic V2 currently scopes to selected/all clusters at activation
        // time; preselected clusterId is passed for future scoped activation.
        showSocraticSetup();
      },
      onTriggerSourceCompare: (clusterId) {
        entry.remove();
        chatController.dispose();
        _openFirstPdfForChatCompare();
      },
    );

    chatController = ChatSessionController(provider: provider, router: router);

    // Populate context from canvas state
    chatController.clusterTexts = Map.from(_clusterTextCache);

    // Semantic titles
    if (_semanticMorphController != null) {
      chatController.clusterTitles = Map.from(
        _semanticMorphController!.aiTitles,
      );
    }

    // Determine auto-scope based on current state
    ChatContextScope autoScope = ChatContextScope.allCanvas;
    if (_lassoTool.hasSelection) {
      autoScope = ChatContextScope.selectedClusters;
      // Map selected nodes to nearest cluster IDs
      chatController.selectedClusterIds = _getSelectedClusterIds();
    }

    // Visible cluster IDs
    chatController.visibleClusterIds = _getVisibleClusterIds();

    // Start session
    chatController.startSession(scope: autoScope);

    // Mount overlay
    if (!mounted) return;
    final overlay = Overlay.of(context);
    entry = OverlayEntry(builder: (_) => ChatOverlay(
      controller: chatController,
      showReadCostBadge: widget.config.showChatReadCostBadge,
      telemetry: widget.config.telemetry ?? TelemetryRecorder.noop,
      onClose: () {
        entry.remove();
        chatController.dispose();
      },
      onNavigateToCluster: (clusterId) {
        _navigateToCluster(clusterId);
      },
    ));
    overlay.insert(entry);
  }

  /// 🔍 Open the first available PDF preview card on the canvas for
  /// source-comparison from the chat. Surfaces a snackbar if none.
  ///
  /// Coerent with feedback_pdf_is_source_not_ai_input.md: the PDF is the
  /// student's source of verification, not an input fed back into the AI.
  void _openFirstPdfForChatCompare() {
    PdfPreviewCardNode? firstCard;
    for (final layer in _layerController.layers) {
      final cards = layer.node.childrenOfType<PdfPreviewCardNode>();
      if (cards.isNotEmpty) {
        firstCard = cards.first;
        break;
      }
    }

    if (firstCard == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Nessuna fonte PDF collegata a questo canvas.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFF1A1A2E),
        ));
      }
      return;
    }
    _enterPdfReader(firstCard);
  }

  /// Get cluster IDs that overlap with selected nodes.
  Set<String> _getSelectedClusterIds() {
    final selectedBounds = _lassoTool.selectionManager.selectedNodes
        .map((n) => n.worldBounds)
        .where((b) => b.isFinite)
        .toList();
    if (selectedBounds.isEmpty) return {};

    final ids = <String>{};
    for (final cluster in _clusterCache) {
      for (final bounds in selectedBounds) {
        if ((cluster.centroid - bounds.center).distance < 500) {
          ids.add(cluster.id);
        }
      }
    }
    return ids;
  }

  /// Get cluster IDs visible in the current viewport.
  Set<String> _getVisibleClusterIds() {
    final topLeft = _canvasController.screenToCanvas(Offset.zero);
    final screenSize = MediaQuery.sizeOf(context);
    final bottomRight = _canvasController.screenToCanvas(
      Offset(screenSize.width, screenSize.height),
    );
    final viewport = Rect.fromPoints(topLeft, bottomRight).inflate(200);

    return _clusterCache
        .where((c) => viewport.contains(c.centroid))
        .map((c) => c.id)
        .toSet();
  }
}
