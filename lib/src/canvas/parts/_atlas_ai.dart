part of '../fluera_canvas_screen.dart';

/// Atlas Prompt operating mode (F8 dual-mode dispatcher).
///
/// - [AtlasMode.node]: status-quo node-level dispatcher. Best for explicit
///   per-node operations on discrete content (translate text, solve LaTeX,
///   describe image, convert handwriting). Selected when the user has an
///   explicit lasso selection.
/// - [AtlasMode.cluster]: cluster-level dispatcher (added 2026-05-12).
///   Best for high-level reshape commands (organize, align, distribute,
///   color, connect) on groups of strokes. Default when no selection is
///   active, so free-form prompts like "organizza" do not scatter
///   handwriting into individual letters.
enum AtlasMode { node, cluster }

/// 🌌 ATLAS AI — End-to-end AI invocation, handwriting recognition,
/// and JARVIS-style spatial intelligence analysis.
///
/// Extracted from [_FlueraCanvasScreenState] for maintainability.
/// All methods here access the parent state fields:
///   `_atlasIsLoading`, `_atlasResponseText`, `_atlasVfxEntries`,
///   `_atlasCardText`, `_atlasCardPosition`, `_showAtlasPrompt`.
extension AtlasAiWiring on _FlueraCanvasScreenState {
  // ─────────────────────────────────────────────────────────────────────────
  // Locale helper — explicit language name from device locale
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns the user's device language name for prompt injection.
  String get _deviceLanguageName {
    final code = ui.PlatformDispatcher.instance.locale.languageCode;
    const map = {
      'it': 'Italian', 'en': 'English', 'es': 'Spanish', 'fr': 'French',
      'de': 'German', 'pt': 'Portuguese', 'ja': 'Japanese', 'ko': 'Korean',
      'zh': 'Chinese', 'ar': 'Arabic', 'ru': 'Russian', 'hi': 'Hindi',
      'nl': 'Dutch', 'sv': 'Swedish', 'pl': 'Polish', 'tr': 'Turkish',
    };
    return map[code] ?? 'English';
  }

  /// Returns a language instruction written in the NATIVE language itself.
  /// e.g. for Italian: "RISPONDI SOLO IN ITALIANO." (not the English "RESPOND ONLY IN Italian")
  /// This is far more effective because the AI reads the instruction in the target language context.
  String get _nativeLangInstruction {
    final code = ui.PlatformDispatcher.instance.locale.languageCode;
    const map = {
      'it': 'RISPONDI ESCLUSIVAMENTE IN ITALIANO. Non usare l\'inglese.',
      'es': 'RESPONDE EXCLUSIVAMENTE EN ESPAÑOL. No uses el inglés.',
      'fr': 'RÉPONDS EXCLUSIVEMENT EN FRANÇAIS. N\'utilise pas l\'anglais.',
      'de': 'ANTWORTE AUSSCHLIESSLICH AUF DEUTSCH. Verwende kein Englisch.',
      'pt': 'RESPONDA EXCLUSIVAMENTE EM PORTUGUÊS. Não use o inglês.',
      'ja': '必ず日本語で回答してください。英語を使用しないでください。',
      'ko': '반드시 한국어로만 답변하세요. 영어를 사용하지 마세요.',
      'zh': '请仅用中文回答。不要使用英语。',
      'nl': 'ANTWOORD UITSLUITEND IN HET NEDERLANDS. Gebruik geen Engels.',
      'ar': 'أجب باللغة العربية فقط. لا تستخدم الإنجليزية.',
      'ru': 'ОТВЕЧАЙ ИСКЛЮЧИТЕЛЬНО НА РУССКОМ. Не используй английский.',
      'pl': 'ODPOWIADAJ WYŁĄCZNIE PO POLSKU. Nie używaj angielskiego.',
      'tr': 'YALNIZCA TÜRKÇE YANIT VER. İngilizce kullanma.',
      'sv': 'SVARA UTESLUTANDE PÅ SVENSKA. Använd inte engelska.',
      'en': '', // English device — no enforcement needed
    };
    return map[code] ?? '';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Entry point — routes to client-side handlers or Gemini
  // ─────────────────────────────────────────────────────────────────────────

  /// 🌌 ATLAS: End-to-end AI invocation.
  ///
  /// [forcedMode] lets the caller pin the dispatcher mode (cluster vs
  /// node). When null the mode is inferred from the canvas state:
  /// selection present → node, otherwise cluster (safer default for
  /// free-form prompts that would otherwise scatter handwriting).
  Future<void> _invokeAtlas(String prompt, {AtlasMode? forcedMode}) async {
    setState(() {
      _atlasIsLoading = true;
      _atlasResponseText = null;
      _atlasLoadingPhase = null;
    });

    try {
      // ── CLIENT-SIDE HANDLERS (no AI) ────────────────────────────────
      if (prompt == '_CONVERT_') {
        await _convertHandwritingToText();
        return;
      }
      if (prompt == '_ANALYZE_') {
        await _analyzeSelection();
        return;
      }
      if (V1FeatureGate.examSession) {
        if (prompt == '_EXAM_') {
          await _startExamSession();
          return;
        }
        // Keyword detection: exam commands in any language
        final normalizedPrompt = prompt.trim().toLowerCase();
        if (normalizedPrompt.contains('interrogami') ||
            normalizedPrompt.contains('esaminami') ||
            normalizedPrompt.contains('quiz') ||
            normalizedPrompt.contains('test me') ||
            normalizedPrompt.contains('interrogate me') ||
            normalizedPrompt.contains('exam mode')) {
          await _startExamSession();
          return;
        }
      }

      // ── CLUSTER MODE (F8) ────────────────────────────────────────────
      // Default to cluster when no lasso selection is active, so free-form
      // commands like "organizza" operate on concepts instead of stroke
      // letters. Caller can override via forcedMode (e.g. chip presets).
      final mode = forcedMode
          ?? (_lassoTool.hasSelection ? AtlasMode.node : AtlasMode.cluster);

      if (mode == AtlasMode.cluster) {
        await _invokeAtlasCluster(prompt);
        return;
      }

      // (C) Phase: extracting context
      if (mounted) setState(() => _atlasLoadingPhase = '🔍 Extracting context...');

      // 1. Extract canvas context from selection (or viewport)
      // First, get recognized handwriting text for stroke nodes
      final selectedNodes = _lassoTool.hasSelection
          ? _lassoTool.selectionManager.selectedNodes
          : <CanvasNode>[];
      final strokeIds = selectedNodes
          .whereType<StrokeNode>()
          .map((n) => n.id.toString())
          .toList();
      final recognizedTexts = strokeIds.isNotEmpty
          ? await HandwritingIndexService.instance
                .getTextMapForStrokes(_canvasId, strokeIds)
          : <String, String>{};

      debugPrint('🔍 Atlas debug: ${strokeIds.length} stroke IDs, ${recognizedTexts.length} recognized');
      for (final e in recognizedTexts.entries) {
        debugPrint('  📝 ${e.key} → "${e.value}"');
      }

      final extractor = CanvasStateExtractor(recognizedTexts: recognizedTexts);
      final List<Map<String, dynamic>> canvasContext;

      final layerNode = _layerController.layers
          .firstWhere((l) => l.id == _layerController.activeLayerId)
          .node;

      if (_lassoTool.hasSelection) {
        // Use selection manager directly
        canvasContext = extractor.extractFromSelection(_lassoTool.selectionManager);
      } else {
        // No selection — extract all visible nodes in viewport
        final screenSize = MediaQuery.of(context).size;
        final scale = _canvasController.scale;
        final offset = _canvasController.offset;
        final viewportRect = Rect.fromLTWH(
          -offset.dx / scale,
          -offset.dy / scale,
          screenSize.width / scale,
          screenSize.height / scale,
        );
        canvasContext = extractor.extractFromViewport(layerNode, viewportRect);
      }

      // (C) Phase: AI thinking
      if (mounted) setState(() => _atlasLoadingPhase = 'Elaboro\u2026');

      // 2. Call Atlas AI
      final provider = EngineScope.current.atlasProvider;
      if (!provider.isInitialized) {
        await provider.initialize();
      }
      final response = await provider.askAtlas(prompt, canvasContext);

      // (C) Phase: executing
      if (mounted) setState(() => _atlasLoadingPhase = '✨ Executing actions...');

      // 3. Execute actions on the scene graph
      if (response.actions.isNotEmpty) {
        final executor = AtlasActionExecutor(
          sceneRoot: layerNode,
          selectionManager: _lassoTool.selectionManager,
          nodeResolver: (id) => layerNode.findChild(id),
          onNodeCreated: (node) {
            // 📝 Sync created TextNode into the rendering list
            if (node is TextNode) {
              _digitalTextElements.add(node.textElement);
            }

            // Trigger materialization VFX at node's screen position
            final screenPos = _canvasController.canvasToScreen(
              node.position,
            );
            final key = UniqueKey();
            setState(() {
              _atlasVfxEntries.add(_AtlasVfxEntry(
                key: key,
                position: screenPos,
                type: _AtlasVfxType.materialize,
              ));
            });
            // Auto-remove after animation
            Future.delayed(const Duration(milliseconds: 900), () {
              if (mounted) {
                setState(() {
                  _atlasVfxEntries.removeWhere((e) => e.key == key);
                });
              }
            });
          },
        );
        executor.executeAll(response.actions);
        // Full canvas invalidation pipeline (same as drag handlers)
        _layerController.sceneGraph.bumpVersion();
        DrawingPainter.invalidateAllTiles();
        _canvasController.markNeedsPaint();
        _layerController.notifyListeners();
        if (mounted) setState(() {});
      }

      // 4. Show response
      if (mounted) {
        setState(() {
          _atlasIsLoading = false;
          _atlasResponseText = response.explanation ?? 'Azioni eseguite!';
        });
        // Auto-dismiss after 3 seconds
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted && _showAtlasPrompt) {
            setState(() {
              _showAtlasPrompt = false;
              _atlasResponseText = null;
            });
          }
        });
      }
    } catch (e) {
      debugPrint('❌ Atlas error: $e');
      if (mounted) {
        setState(() {
          _atlasIsLoading = false;
          _atlasResponseText = 'Errore: ${e.toString().length > 80 ? '${e.toString().substring(0, 80)}...' : e}';
        });
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 🧩 Cluster-level dispatcher (F8)
  // ─────────────────────────────────────────────────────────────────────────

  /// Build cluster payload → ask Gemini → execute cluster actions atomically.
  ///
  /// Wrapped in `LayerController.runAsBatch` so the entire AI command
  /// (which may translate into dozens of stroke updates) lands as a
  /// single undo entry. Failures inside the batch roll back any partial
  /// mutation thanks to the composite-delta rollback path.
  Future<void> _invokeAtlasCluster(String prompt) async {
    // Refresh cluster cache (same triggers used by Ghost Map / Socratic)
    // so the AI sees the current concept layout.
    if (_clusterCache.isEmpty) {
      if (mounted) setState(() {
        _atlasIsLoading = false;
        _atlasResponseText = 'Niente da organizzare — il canvas è vuoto.';
      });
      return;
    }

    // Build the viewport rectangle in world coords (same logic node-mode
    // uses to extract context — keeps payload focused on what the user
    // is actually looking at).
    final screenSize = MediaQuery.of(context).size;
    final scale = _canvasController.scale;
    final offset = _canvasController.offset;
    final viewportRect = Rect.fromLTWH(
      -offset.dx / scale,
      -offset.dy / scale,
      screenSize.width / scale,
      screenSize.height / scale,
    );

    if (mounted) setState(() => _atlasLoadingPhase = '🔍 Extracting clusters...');

    final conceptIndex = _clusterConceptIndex;
    if (conceptIndex == null) {
      // Cluster index not yet initialized (canvas mounted very recently).
      // Fall back to node mode rather than crashing — node-level on a
      // selection-less canvas is a no-op for most prompts and surfaces
      // a benign empty response.
      if (mounted) setState(() {
        _atlasIsLoading = false;
        _atlasResponseText = 'Indici cluster non ancora pronti — riprova.';
      });
      return;
    }

    final clusterContext = CanvasStateExtractor.buildClusterContext(
      userPrompt: prompt,
      clusters: _clusterCache,
      index: conceptIndex,
      viewport: viewportRect,
    );

    if (mounted) setState(() => _atlasLoadingPhase = 'Elaboro…');

    final provider = EngineScope.current.atlasProvider;
    if (!provider.isInitialized) await provider.initialize();
    final response = await provider.askAtlasCluster(prompt, clusterContext);

    if (mounted) setState(() => _atlasLoadingPhase = '✨ Executing cluster actions...');

    // Build cluster id → ContentCluster lookup for the executor.
    final byId = {for (final c in _clusterCache) c.id: c};
    final executor = ClusterActionExecutor(
      clusterResolver: (id) => byId[id],
      layerController: _layerController,
      // Color / move actions rewrite stroke point lists, which changes
      // each cluster's strokeChecksum. Invalidate the concept index so
      // OCR / title / topic get re-resolved on next access.
      onComplete: (touched) => conceptIndex.invalidate(touched),
    );

    if (response.actions.isNotEmpty) {
      final report = await _layerController.runAsBatch(
        'Atlas: ${prompt.length > 30 ? '${prompt.substring(0, 30)}…' : prompt}',
        () async => executor.executeAll(response.actions),
      );

      // Full canvas invalidation (mirror node-level path).
      _layerController.sceneGraph.bumpVersion();
      DrawingPainter.invalidateAllTiles();
      _canvasController.markNeedsPaint();
      _layerController.notifyListeners();
      if (mounted) setState(() {});

      debugPrint('🧩 Cluster batch applied: ${report.actionsApplied} actions, '
          '${report.touchedClusterIds.length} clusters, '
          '${report.skipped.length} skipped ids.');
    }

    if (mounted) {
      setState(() {
        _atlasIsLoading = false;
        _atlasResponseText = response.actions.isEmpty
            ? (response.explanation ?? 'Atlas non ha trovato azioni utili.')
            : (response.explanation ?? 'Cluster riorganizzati.');
      });
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _showAtlasPrompt) {
          setState(() {
            _showAtlasPrompt = false;
            _atlasResponseText = null;
          });
        }
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Client-side handwriting → digital text
  // ─────────────────────────────────────────────────────────────────────────

  /// 📝 Client-side handwriting → digital text conversion.
  /// Recognizes strokes on-the-fly via DigitalInkService — no DB dependency.
  Future<void> _convertHandwritingToText() async {
    try {
      if (!_lassoTool.hasSelection) {
        if (mounted) setState(() {
          _atlasIsLoading = false;
          _atlasResponseText = 'Nessuna selezione';
        });
        return;
      }

      final selectedNodes = _lassoTool.selectionManager.selectedNodes;
      final strokeNodes = selectedNodes.whereType<StrokeNode>().toList();
      if (strokeNodes.isEmpty) {
        if (mounted) setState(() {
          _atlasIsLoading = false;
          _atlasResponseText = 'Nessun tratto selezionato';
        });
        return;
      }

      // (C) Phase: recognizing handwriting
      if (mounted) setState(() => _atlasLoadingPhase = '✍️ Recognizing handwriting...');

      // Recognize on-the-fly
      final fullText = await _recognizeSelectedStrokes(strokeNodes);

      if (fullText == null || fullText.trim().isEmpty) {
        if (mounted) setState(() {
          _atlasIsLoading = false;
          _atlasResponseText = 'Testo non riconosciuto';
        });
        return;
      }

      // Position: below the selection bounding box
      final selBounds = _lassoTool.getSelectionBounds();
      final posX = selBounds != null ? selBounds.center.dx : 200.0;
      final posY = selBounds != null ? selBounds.bottom + 40 : 200.0;

      // Create text element
      final textElement = DigitalTextElement(
        id: 'atlas_${DateTime.now().microsecondsSinceEpoch}',
        text: fullText.trim(),
        position: Offset(posX - fullText.length * 4, posY),
        fontSize: 18,
        color: const Color(0xFF00E5FF),
        createdAt: DateTime.now(),
      );

      // Add to scene graph + rendering
      final layerNode = _layerController.layers
          .firstWhere((l) => l.id == _layerController.activeLayerId)
          .node;
      layerNode.addText(textElement);
      _digitalTextElements.add(textElement);

      _layerController.sceneGraph.bumpVersion();
      DrawingPainter.invalidateAllTiles();
      _canvasController.markNeedsPaint();
      _layerController.notifyListeners();

      if (mounted) {
        setState(() {
          _atlasIsLoading = false;
          _atlasResponseText = '📝 "$fullText"';
        });
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() {
            _showAtlasPrompt = false;
            _atlasResponseText = null;
          });
        });
      }
    } catch (e) {
      if (mounted) setState(() {
        _atlasIsLoading = false;
        _atlasResponseText = 'Errore: $e';
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Multi-strategy handwriting recognition
  // ─────────────────────────────────────────────────────────────────────────

  /// 🔤 Live recognition helper — tries multiple strategies:
  /// 1. Multi-stroke recognition (best for full words)
  /// 2. Single-stroke recognition per stroke, concatenated
  /// 3. Database lookup (HandwritingIndexService) as fallback
  Future<String?> _recognizeSelectedStrokes(List<StrokeNode> strokeNodes) async {
    if (strokeNodes.isEmpty) return null;

    // Ensure the ink service is initialized
    final inkService = DigitalInkService.instance;
    if (!inkService.isReady) {
      // Show download dialog
      final shouldDownload = await _showModelDownloadDialog();
      if (!shouldDownload) return null;

      // Download and init
      if (mounted) {
        setState(() => _atlasResponseText = '⏬ Scaricamento modello...');
      }
      await inkService.init(languageCode: 'it');
      if (!inkService.isReady) {
        await inkService.init(languageCode: 'en');
      }
      if (!inkService.isReady) {
        if (mounted) {
          setState(() {
            _atlasIsLoading = false;
            _atlasResponseText = '❌ Modello non disponibile';
          });
        }
        return null;
      }
    }

    final strokeSets = strokeNodes
        .map((n) => n.stroke.points)
        .toList();

    // Strategy 1: Multi-stroke recognition
    debugPrint('🔤 Strategy 1: Multi-stroke (lang=${inkService.languageCode})...');
    final result = await inkService.recognizeMultiStroke(strokeSets);
    if (result != null && result.trim().isNotEmpty) {
      debugPrint('🔤 ✅ Multi-stroke result: "$result"');
      return result;
    }

    // Strategy 2: Single-stroke per stroke
    debugPrint('🔤 Strategy 2: Single-stroke...');
    final parts = <String>[];
    for (final points in strokeSets) {
      if (points.length < 5) continue;
      final text = await inkService.recognizeStroke(points);
      if (text != null && text.trim().isNotEmpty) {
        parts.add(text.trim());
      }
    }
    if (parts.isNotEmpty) {
      final joined = parts.toSet().join(' ');
      debugPrint('🔤 ✅ Single-stroke result: "$joined"');
      return joined;
    }

    // Strategy 3: Database fallback
    debugPrint('🔤 Strategy 3: Database fallback...');
    final strokeIds = strokeNodes.map((n) => n.id.toString()).toList();
    final textMap = await HandwritingIndexService.instance
        .getTextMapForStrokes(_canvasId, strokeIds);
    if (textMap.isNotEmpty) {
      final uniqueTexts = textMap.values.toSet().toList();
      final result = uniqueTexts.join(' ');
      debugPrint('🔤 ✅ Database result: "$result"');
      return result;
    }

    debugPrint('🔤 ❌ No recognition from any strategy');
    return null;
  }

  /// 📥 Show dialog to download the handwriting model with progress.
  Future<bool> _showModelDownloadDialog() async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _InkModelDownloadDialog(),
    );
    return result ?? false;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // JARVIS-style spatial intelligence analysis
  // ─────────────────────────────────────────────────────────────────────────

  /// 🔍 AI-powered analysis: extracts content from ALL node types,
  /// recognizes handwriting, then asks Gemini with a content-type-aware prompt.
  ///
  /// (2) Rate-limited: 2s cooldown between invocations.
  static DateTime? _lastAnalyzeTime;

  Future<void> _analyzeSelection() async {
    // (2) Rate limiting — 2s cooldown
    final now = DateTime.now();
    if (_lastAnalyzeTime != null && now.difference(_lastAnalyzeTime!).inMilliseconds < 2000) {
      HapticFeedback.heavyImpact();
      return; // silently ignore spam
    }
    _lastAnalyzeTime = now;

    final cardId = 'atlas_${DateTime.now().microsecondsSinceEpoch}';
    try {
      if (!_lassoTool.hasSelection) {
        _addCard(cardId, '⚠️ Select elements with lasso first', Offset(
          MediaQuery.of(context).size.width / 2,
          MediaQuery.of(context).size.height / 2,
        ));
        return;
      }

      final selectedNodes = _lassoTool.selectionManager.selectedNodes;
      final strokeNodes = selectedNodes.whereType<StrokeNode>().toList();
      final textNodes = selectedNodes.whereType<TextNode>().toList();
      final latexNodes = selectedNodes.whereType<LatexNode>().toList();
      final pdfNodes = selectedNodes.whereType<PdfPageNode>().toList();
      final tabularNodes = selectedNodes.whereType<TabularNode>().toList();
      final imageNodes = selectedNodes.whereType<ImageNode>().toList();

      // ── Phase 1: Recognize handwriting ──────────────────────────────────
      if (strokeNodes.isNotEmpty) {
        if (mounted) setState(() => _atlasLoadingPhase = '🔤 Recognizing handwriting...');
      }

      final recognizedText = strokeNodes.isNotEmpty
          ? await _recognizeSelectedStrokes(strokeNodes)
          : null;

      // ── Phase 2: Extract content from ALL node types ────────────────────
      if (mounted) setState(() => _atlasLoadingPhase = '📋 Extracting content...');

      final contentParts = <String>[];
      final detectedTypes = <String>{};

      // Handwriting (strokes)
      if (recognizedText != null && recognizedText.trim().isNotEmpty) {
        contentParts.add(recognizedText.trim());
        detectedTypes.add('handwriting');
      } else if (strokeNodes.isNotEmpty) {
        detectedTypes.add('unrecognized_strokes');
      }

      // Digital text
      for (final n in textNodes) {
        final text = n.textElement.text.trim();
        if (text.isNotEmpty) {
          contentParts.add(text);
          detectedTypes.add('text');
        }
      }

      // LaTeX formulas
      for (final n in latexNodes) {
        contentParts.add('[LaTeX] ${n.latexSource}');
        detectedTypes.add('math');
      }

      // PDF pages — include extracted text rects if available
      for (final n in pdfNodes) {
        final pageNum = n.pageModel.pageIndex + 1;
        if (n.textRects != null && n.textRects!.isNotEmpty) {
          final pdfText = n.textRects!.map((r) => r.text).join(' ').trim();
          if (pdfText.isNotEmpty) {
            contentParts.add('[PDF p.$pageNum] $pdfText');
            detectedTypes.add('pdf_text');
          } else {
            contentParts.add('[PDF p.$pageNum] (text not extracted)');
            detectedTypes.add('pdf_image');
          }
        } else {
          contentParts.add('[PDF p.$pageNum] (text not extracted)');
          detectedTypes.add('pdf_image');
        }
      }

      // Tabular data — extract first cells as summary
      for (final n in tabularNodes) {
        final cells = n.model.cells;
        if (cells.isNotEmpty) {
          final cellTexts = <String>[];
          for (final entry in cells.entries) {
            final display = entry.value.displayValue;
            cellTexts.add('${entry.key}: $display');
            if (cellTexts.length >= 20) break; // Cap for prompt size
          }
          contentParts.add('[Table] ${cellTexts.join(', ')}');
          detectedTypes.add('tabular');
        }
      }

      // (3) Images — describe for multimodal context
      for (final n in imageNodes) {
        contentParts.add('[Image] file: ${n.imageElement.imagePath}');
        detectedTypes.add('image');
      }

      // Calculate card position early
      final selBounds = _lassoTool.getSelectionBounds();
      Offset cardScreenPos;
      if (selBounds != null) {
        cardScreenPos = _canvasController.canvasToScreen(
          Offset(selBounds.center.dx, selBounds.bottom + 30),
        );
      } else {
        cardScreenPos = Offset(
          MediaQuery.of(context).size.width / 2,
          MediaQuery.of(context).size.height / 2,
        );
      }

      // Fallback if nothing was extracted
      if (contentParts.isEmpty) {
        if (strokeNodes.isNotEmpty && recognizedText == null) {
          _addCard(cardId, '✏️ Handwriting not recognizable. Try writing more clearly.', cardScreenPos);
          return;
        }
        _addCard(cardId, '⚠️ No analyzable content found in ${selectedNodes.length} nodes.', cardScreenPos);
        return;
      }

      final userContent = contentParts.join('\n');
      debugPrint('🔍 Analyze: ${contentParts.length} parts, types: $detectedTypes');

      // ── Phase 3: AI analysis (streaming) ──────────────────────────────
      if (mounted) setState(() => _atlasLoadingPhase = '🌌 Atlas scanning...');

      final provider = EngineScope.current.atlasProvider;
      if (!provider.isInitialized) {
        await provider.initialize();
      }

      // Build JARVIS-style prompt (no JSON wrapping for streaming)
      final analyzePrompt = _buildAnalyzePrompt(
        userContent,
        detectedTypes,
        selectedNodes.length,
      );

      // Build canvas context
      final canvasContext = <Map<String, dynamic>>[];
      if (selBounds != null) {
        canvasContext.add({
          'id': 'selection',
          'tipo': detectedTypes.join(', '),
          'contenuto': userContent,
          'num_nodi': selectedNodes.length,
          'posizione': {
            'x': selBounds.center.dx.roundToDouble(),
            'y': selBounds.center.dy.roundToDouble(),
          },
        });
      }

      // Show card immediately with empty text (streaming fills it)
      _addCard(cardId, '', cardScreenPos);

      // Stream chunks from Gemini in real-time
      final buffer = StringBuffer();
      final stream = provider.askAtlasStream(analyzePrompt, canvasContext);

      await stream.timeout(
        const Duration(seconds: 15),
        onTimeout: (sink) => sink.close(),
      ).forEach((chunk) {
        buffer.write(chunk);
        if (mounted) _updateCardText(cardId, buffer.toString());
      });

      // Ensure final state
      final finalText = buffer.toString();
      if (finalText.isEmpty) {
        if (mounted) _updateCardText(cardId, '⚠️ Atlas returned an empty response.');
      }
    } on TimeoutException {
      // (D) Timeout — show in response card
      debugPrint('⏱️ Analyze timeout');
      _showErrorInCard('⏱️ Atlas took too long. Try again with less content.');
    } catch (e) {
      // (E) All errors route to the holographic card, not prompt overlay
      debugPrint('❌ Analyze error: $e');
      final errorMsg = e.toString();
      final userMessage = errorMsg.contains('SocketException') ||
              errorMsg.contains('ClientException') ||
              errorMsg.contains('HandshakeException')
          ? '🌐 Atlas unreachable. Check your internet connection.'
          : errorMsg.contains('ApiException') ||
                  errorMsg.contains('GenerativeAI')
              ? '🤖 AI service error. Try again in a few seconds.'
              : '❌ Error: ${errorMsg.length > 80 ? '${errorMsg.substring(0, 80)}...' : errorMsg}';
      _showErrorInCard(userMessage);
    }
  }

  /// (4) Add a new card to the multi-card list.
  void _addCard(String id, String text, Offset position) {
    if (!mounted) return;
    setState(() {
      _atlasIsLoading = false;
      _showAtlasPrompt = false;
      _atlasResponseText = null;
      _atlasCards.add(_AtlasCardEntry(id: id, text: text, position: position));
    });
  }

  /// 💡 Add a proactive gap card with embedded gap chips for node creation.
  void _addProactiveCard(
    String id,
    String text,
    Offset position,
    List<String> gapChips,
    String sourceClusterId,
  ) {
    if (!mounted) return;
    setState(() {
      _atlasIsLoading = false;
      _showAtlasPrompt = false;
      _atlasResponseText = null;
      _atlasCards.add(_AtlasCardEntry(
        id: id,
        text: text,
        position: position,
        gapChips: gapChips,
        sourceClusterId: sourceClusterId,
      ));
    });
  }

  /// (4) Update text of an existing card by ID.
  void _updateCardText(String id, String text) {
    if (!mounted) return;
    setState(() {
      final card = _atlasCards.where((c) => c.id == id).firstOrNull;
      if (card != null) card.text = text;
    });
  }

  /// Show an error message in a new holographic card.
  void _showErrorInCard(String message) {
    if (!mounted) return;
    final selBounds = _lassoTool.getSelectionBounds();
    final pos = selBounds != null
        ? _canvasController.canvasToScreen(
            Offset(selBounds.center.dx, selBounds.bottom + 30))
        : Offset(
            MediaQuery.of(context).size.width / 2,
            MediaQuery.of(context).size.height / 2,
          );
    _addCard('error_${DateTime.now().microsecondsSinceEpoch}', message, pos);
  }

  /// (7) Send a "Go deeper" follow-up with full conversation memory.
  Future<void> _goDeeper(List<String> conversationChain, Offset cardPosition) async {
    final cardId = 'deeper_${DateTime.now().microsecondsSinceEpoch}';

    try {
      final provider = EngineScope.current.atlasProvider;
      if (!provider.isInitialized) await provider.initialize();

      // Build context from full conversation chain (truncate long ones)
      final contextParts = <String>[];
      for (int i = 0; i < conversationChain.length; i++) {
        final text = conversationChain[i];
        final truncated = text.length > 400
            ? '${text.substring(0, 400)}...'
            : text;
        contextParts.add('--- SCAN LEVEL ${i + 1} ---\n$truncated');
      }

      final prompt = '''IGNORE all previous canvas action rules.
You are ATLAS, an advanced spatial intelligence scanner (Iron Man JARVIS style).

CONVERSATION HISTORY (${conversationChain.length} previous scans):
${contextParts.join('\n\n')}

The user wants you to GO DEEPER. Provide a more detailed, expanded analysis.
Keep the same ▸ SCAN / ▸ CONN / ▸ NOTE structure but with MORE detail, MORE connections, and MORE actionable insights.
Be 2-3x more detailed than the previous scan. Add sub-points, numbers, specifics.
You MUST respond ENTIRELY in ${_deviceLanguageName}. Do NOT switch to another language.
Do NOT repeat previous scans verbatim — BUILD upon them with NEW depth.''';

      // Show card with conversation history for swipe
      if (!mounted) return;
      setState(() {
        _atlasCards.add(_AtlasCardEntry(
          id: cardId,
          text: '',
          position: cardPosition,
          conversationHistory: conversationChain,
        ));
      });

      // Stream response
      final buffer = StringBuffer();
      final stream = provider.askAtlasStream(prompt, []);

      await stream.timeout(
        const Duration(seconds: 20),
        onTimeout: (sink) => sink.close(),
      ).forEach((chunk) {
        buffer.write(chunk);
        if (mounted) _updateCardText(cardId, buffer.toString());
      });

      if (buffer.isEmpty && mounted) {
        _updateCardText(cardId, '⚠️ Atlas returned an empty response.');
      }
    } catch (e) {
      debugPrint('❌ Go deeper error: $e');
      if (mounted) _updateCardText(cardId, '❌ Error: ${e.toString().length > 80 ? '${e.toString().substring(0, 80)}...' : e}');
    }
  }

  /// (2) Follow-up from a suggestion chip — sends the chip text as a focused question.
  Future<void> _followUpFromCard(String question, String context, Offset position) async {
    // 📊 Session summary intercept
    if (question.toLowerCase().contains('riepilogo') ||
        question.toLowerCase().contains('summary') ||
        question.startsWith('📊')) {
      _showSessionSummary();
      return;
    }
    final cardId = 'followup_${DateTime.now().microsecondsSinceEpoch}';


    try {
      final provider = EngineScope.current.atlasProvider;
      if (!provider.isInitialized) await provider.initialize();

      final truncated = context.length > 400
          ? '${context.substring(0, 400)}...'
          : context;

      final prompt = '''IGNORE all previous canvas action rules.
You are ATLAS, an advanced spatial intelligence scanner (Iron Man JARVIS style).

Previous scan:
$truncated

User request: $question

Respond using ▸ SCAN / ▸ CONN / ▸ NOTE format. Be specific and detailed.
You MUST respond ENTIRELY in ${_deviceLanguageName}. Do NOT switch to another language.''';

      if (!mounted) return;
      setState(() {
        _atlasCards.add(_AtlasCardEntry(
          id: cardId,
          text: '',
          position: position,
          conversationHistory: [context],
        ));
      });

      final buffer = StringBuffer();
      final stream = provider.askAtlasStream(prompt, []);

      await stream.timeout(
        const Duration(seconds: 20),
        onTimeout: (sink) => sink.close(),
      ).forEach((chunk) {
        buffer.write(chunk);
        if (mounted) _updateCardText(cardId, buffer.toString());
      });

      if (buffer.isEmpty && mounted) {
        _updateCardText(cardId, '⚠️ Atlas returned an empty response.');
      }
    } catch (e) {
      debugPrint('❌ Follow-up error: $e');
      if (mounted) _updateCardText(cardId, '❌ Error: ${e.toString().length > 80 ? '${e.toString().substring(0, 80)}...' : e}');
    }
  }

  /// 🧠 (A) Build an Iron Man ATLAS-style scan prompt.
  ///
  /// Produces output that looks like a HUD scan report:
  /// ▸ SCAN: [core finding]
  /// ▸ CONN: [connections/relations]
  /// ▸ NOTE: [insight/recommendation]
  String _buildAnalyzePrompt(
    String userContent,
    Set<String> detectedTypes,
    int nodeCount,
  ) {
    final sb = StringBuffer();

    // System persona
    sb.writeln('IGNORE all previous canvas action rules.');
    sb.writeln('You are ATLAS, an advanced spatial intelligence scanner inspired by Iron Man\'s JARVIS/FRIDAY.');
    sb.writeln('You perform rapid-fire HUD scan reports. Your output must feel like reading a holographic overlay in a sci-fi cockpit.');
    sb.writeln();

    // Format rules — plain text, NO JSON
    sb.writeln('RESPOND DIRECTLY with this EXACT format (plain text, NO JSON, NO wrapping):');
    sb.writeln('▸ SCAN: [core identification — what this is, key facts, 1-2 sentences]');
    sb.writeln('▸ CONN: [connections, relationships, context — 1 sentence]');
    sb.writeln('▸ NOTE: [actionable insight, recommendation, or interesting detail — 1 sentence]');
    sb.writeln();

    // Style rules
    sb.writeln('STYLE RULES:');
    sb.writeln('- Dense, telegraphic, like a HUD readout. No filler words.');
    sb.writeln('- NO introductions ("Here is...", "This is..."), NO meta-commentary.');
    sb.writeln('- Use technical precision. Be specific, not vague.');
    sb.writeln('- You MUST respond ENTIRELY in $_deviceLanguageName. Do NOT switch to another language.');
    sb.writeln('- NO canvas actions. Analysis only.');
    sb.writeln('- DO NOT wrap in JSON. Output plain text ONLY.');
    sb.writeln('- If your response mentions ANY mathematical formula, wrap it in \$...\$ (inline) or \$\$...\$\$ (display). Use LaTeX notation.');
    sb.writeln();

    // Content-type specific guidance + few-shot example
    if (detectedTypes.contains('math') && detectedTypes.length == 1) {
      sb.writeln('CONTENT TYPE: Mathematical expressions');
      sb.writeln('Focus on: expression type, variables, solution approach or meaning.');
      sb.writeln('IMPORTANT: When mentioning ANY mathematical formula in your response,');
      sb.writeln('you MUST wrap it in \$...\$ delimiters for inline formulas');
      sb.writeln('or \$\$...\$\$ for display formulas. Use standard LaTeX notation.');
      sb.writeln('Example: \$\\frac{a}{b}\$, \$\\sqrt{x}\$, \$\\int_0^1 f(x)dx\$');
      sb.writeln();
      sb.writeln('EXAMPLE — Input: "\\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}"');
      sb.writeln('EXAMPLE — Output: ▸ SCAN: Quadratic formula — solves \$ax^2+bx+c=0\$ for \$x\$. Uses \$\\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}\$. Variables: a,b,c (coefficients), discriminant \$\\Delta=b^2-4ac\$ ▸ CONN: Derived from completing the square. \$\\Delta>0\$ → 2 real roots, \$\\Delta=0\$ → 1, \$\\Delta<0\$ → complex ▸ NOTE: Check discriminant first to determine solution count before substituting');
    } else if (detectedTypes.contains('tabular')) {
      sb.writeln('CONTENT TYPE: Tabular/spreadsheet data');
      sb.writeln('Focus on: data structure, patterns, trends, anomalies.');
      sb.writeln();
      sb.writeln('EXAMPLE — Input: "A1: Revenue, B1: 100, B2: 150, B3: 120"');
      sb.writeln('EXAMPLE — Output: ▸ SCAN: Revenue dataset — 3 data points, range 100-150, mean ≈123 ▸ CONN: Upward spike at B2 (+50%) then pullback (-20%). Volatile growth pattern ▸ NOTE: Small sample size. Track B4-B6 to confirm trend direction');
    } else if (detectedTypes.contains('pdf_text') || detectedTypes.contains('pdf_image')) {
      sb.writeln('CONTENT TYPE: PDF document');
      sb.writeln('Focus on: document theme, key arguments, conclusions.');
      sb.writeln();
      sb.writeln('EXAMPLE — Output: ▸ SCAN: [document type] covering [main topic] ▸ CONN: [key arguments and structure] ▸ NOTE: [main takeaway or action item]');
    } else if (detectedTypes.contains('image')) {
      sb.writeln('CONTENT TYPE: Image(s) on canvas');
      sb.writeln('Focus on: visual content description, object identification, colors, composition, text in image (OCR).');
      sb.writeln('If the image contains text, extract and analyze it.');
      sb.writeln('If the image is a diagram/chart, describe its structure and data.');
      sb.writeln();
      sb.writeln('EXAMPLE — Output: ▸ SCAN: [image type] showing [main subject], [key visual elements] ▸ CONN: [how this relates to surrounding notes/content on canvas] ▸ NOTE: [interesting detail, actionable insight, or suggestion]');
    } else if (detectedTypes.length > 1) {
      sb.writeln('CONTENT TYPE: Mixed ($nodeCount nodes: ${detectedTypes.join(", ")})');
      sb.writeln('Focus on: cross-referencing elements, finding hidden links between different content types.');
      sb.writeln();
      sb.writeln('EXAMPLE — Output: ▸ SCAN: [overall summary] ▸ CONN: [how elements relate to each other] ▸ NOTE: [synthesized insight across all elements]');
    } else {
      sb.writeln('CONTENT TYPE: Text/handwriting');
      sb.writeln('Focus on: topic identification, key facts, relevant context.');
      sb.writeln();
      sb.writeln('EXAMPLE — Input: "mitochondria ATP cellular respiration"');
      sb.writeln('EXAMPLE — Output: ▸ SCAN: Cell biology — mitochondria as ATP generators via oxidative phosphorylation. 36-38 ATP per glucose molecule ▸ CONN: Links to Krebs cycle (matrix) and electron transport chain (inner membrane). Endosymbiotic origin from ancient bacteria ▸ NOTE: ATP yield varies by tissue type — muscle cells pack more mitochondria for higher energy demand');
    }

    sb.writeln();
    sb.writeln('CONTENT TO ANALYZE:');
    sb.write(userContent);

    return sb.toString();
  }

  /// (C) Save Atlas response text as a digital text node on the canvas.
  void _saveAtlasResponseAsNote(String text) {
    if (text.isEmpty) return;

    // Clean up HUD markers for the saved text
    final cleanText = text
        .replaceAll(RegExp(r'▸\s*(SCAN|CONN|NOTE)\s*:\s*'), '')
        .trim();

    // Position: below the selection bounding box
    final selBounds = _lassoTool.getSelectionBounds();
    final posX = selBounds != null ? selBounds.center.dx : 200.0;
    final posY = selBounds != null ? selBounds.bottom + 60 : 200.0;

    final textElement = DigitalTextElement(
      id: 'atlas_note_${DateTime.now().microsecondsSinceEpoch}',
      text: cleanText.isNotEmpty ? cleanText : text,
      position: Offset(posX - 100, posY),
      fontSize: 16,
      color: const Color(0xFF00E5FF),
      createdAt: DateTime.now(),
    );

    // Add to scene graph + rendering
    final layerNode = _layerController.layers
        .firstWhere((l) => l.id == _layerController.activeLayerId)
        .node;
    layerNode.addText(textElement);
    _digitalTextElements.add(textElement);

    _layerController.sceneGraph.bumpVersion();
    DrawingPainter.invalidateAllTiles();
    _canvasController.markNeedsPaint();
    _layerController.notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 🎓 EXAM MODE — Entry point
  // ─────────────────────────────────────────────────────────────────────────

  /// Start the Atlas Exam Mode session.
  ///
  /// 1. Checks for an interrupted checkpoint and offers resume (P1.1)
  /// 2. Ensures cluster OCR text is ready (reuses [_clusterTextCache])
  /// 3. Builds [ExamScopeEntry] list from AI titles + OCR text
  /// 4. Mounts [ExamOverlay] as a fullscreen Overlay entry
  ///
  /// **Sprint 5 — Fog↔Exam integration**: when [restrictedToClusterIds] is
  /// non-null the scope picker is **pre-seeded** with only those cluster
  /// IDs. This is the path used by the Fog of War mastery summary when
  /// the student picks "Interrogami sui blind spot" — the IA examiner
  /// only quizzes on the nodes that came up forgotten or as blind spots
  /// (`FogOfWarSession.surgicalPlanNodeIds`), per the spec in
  /// `teoria_cognitiva_apprendimento.md` §"L'IA come Esaminatore".
  ///
  /// **Sprint 6**: [layout] selects between the legacy fullscreen overlay
  /// (Atlas menu / chat keyword path) and the surgical-path lower-third
  /// layout that exposes the canvas behind. [onExamComplete] is fired
  /// after the FSRS update + onClose; the Fog wires it to
  /// `_handleExamCompleteFromFog` to re-mount the heatmap.
  Future<void> _startExamSession({
    Set<String>? restrictedToClusterIds,
    ExamOverlayLayout layout = ExamOverlayLayout.fullscreen,
    Future<void> Function()? onExamComplete,
    bool forceShowAll = false,
  }) async {
    // 🛡️ GDPR consent gate (P2.3) — ask before sending student notes to
    // Gemini. Wired to GdprConsentManager.aiProcessing on the host side;
    // null delegates fall back to an inline disclosure dialog so the
    // engine remains usable in tests / demos.
    if (!await _ensureAiProcessingConsent()) return;

    // 💳 Tier gate — Free users get 1 Exam/week. Pro/Plus unlimited.
    // Mirrors the pattern in _ghost_map.dart and _socratic_mode.dart.
    if (!_checkTierGate(GatedFeature.examSession)) return;

    // 💰 AI budget pre-flight — abort early if the user's monthly token
    // pool is exhausted, instead of paying the OCR + topic-grouping AI
    // round-trip then failing inside generateExamQuestions. Conservative
    // estimate: setup + first question generation ≈ 8000 tokens.
    final tracker = widget.config.aiUsageTracker;
    if (tracker != null) {
      try {
        await tracker.ensureBalance(estimate: 8000, feature: 'exam_session');
      } on AiQuotaExceededException {
        // The app subscribes to tracker.exceededEvents in AiUsageBootstrap
        // and surfaces the unified quota dialog — no double-dialog here.
        return;
      }
    }

    // Pre-overlay loading feedback: from this point until the picker mounts
    // we run OCR + topic-grouping AI (~2-4s). Without a visible cue the
    // user sees "nothing happens" after tapping Interrogami. A persistent
    // SnackBar with a tiny spinner fills the gap; we dismiss it once the
    // overlay or an error message takes over.
    ScaffoldMessengerState? messenger;
    if (mounted) {
      messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        duration: const Duration(seconds: 30),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1A1A2E),
        content: const Row(children: [
          SizedBox(
            width: 16, height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00E5FF)),
            ),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Text('🧠 Atlas analizza i tuoi appunti…',
                style: TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ]),
      ));
    }

    final provider = EngineScope.current.atlasProvider;
    if (!provider.isInitialized) await provider.initialize();

    // Check for an interrupted exam (mid-session crash recovery, P1.1).
    // If found, the user picks: resume the previous exam or start fresh.
    final examController = ExamSessionController(
      provider: provider,
      language: _deviceLanguageName,
      telemetry: widget.config.telemetry,
    );
    // 🤝 Cross-feature avoid: exam questions are mirrored to the index
    // so the next Socratic session on the same clusters can pull them
    // into avoidPrompts (B1 of the consolidation sprint).
    examController.conceptIndex = _clusterConceptIndex;

    final preview = await examController.peekCheckpoint();
    bool resumed = false;
    if (preview != null && mounted) {
      final shouldResume = await _showResumeExamDialog(preview);
      if (shouldResume == null) {
        // User dismissed the dialog without choosing — keep checkpoint, abort.
        examController.dispose();
        messenger?.hideCurrentSnackBar();
        return;
      }
      if (shouldResume) {
        resumed = await examController.resumeFromCheckpoint();
      } else {
        await examController.discardCheckpoint();
      }
    }

    // For a fresh exam we still need cluster picker data.
    // For a resumed exam we can mount the overlay directly with empty data
    // (the scope picker is bypassed because session is already loaded).
    Map<String, String> availableTitles = {};
    Map<String, String> clusterTexts = {};
    // Scope state — shared between the cluster-iteration block (where it's
    // computed) and the overlay-mount block (where it's surfaced via the
    // banner). Hoisted out of `if (!resumed)` so the OverlayEntry builder
    // can capture them.
    Set<String>? scopeIds;
    String? activeScopeReason;

    if (!resumed) {
      if (_clusterCache.isEmpty) {
        examController.dispose();
        messenger?.hideCurrentSnackBar();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(FlueraLocalizations.of(context)!.exam_emptyClustersHint),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF1A1A2E),
            duration: const Duration(seconds: 3),
          ));
        }
        return;
      }

      // Ensure OCR text is available for all clusters.
      // _clusterTextCache is populated by _recognizeClusterTextsForSemanticTitles.
      // Exam runs with requireHighQuality: true so the index resolves the
      // (cached) cleanOcrItalian pass — no extra Gemini call when Semantic
      // Titles or another consumer has already requested it on these
      // clusters. First-time clusters pay one cleanup call; subsequent
      // exams on the same content are free.
      await _recognizeClusterTextsForSemanticTitles(requireHighQuality: true);

      // 🔭 SCOPE FILTER — when the canvas holds a year+ of notes, tapping
      // "Interrogami" used to dump every cluster (sometimes 100+) into the
      // topic-grouping AI: messy result + bloated picker. We narrow scope
      // automatically:
      //   1. Active lasso selection → only clusters intersecting that
      //      bounding box (explicit user intent).
      //   2. Otherwise → only clusters intersecting the current viewport
      //      (what the user can actually see right now). Banner appears
      //      ONLY when the narrow is real (shown < total) so a fully-
      //      visible canvas looks unchanged.
      // The Fog-of-War path (`restrictedToClusterIds != null`) bypasses
      // this entirely — those IDs are the source of truth.
      //
      // NOTE: removed an earlier `>12 cluster` threshold (2026-05-07) —
      // students with 5 clusters zoomed in to one were getting picker
      // chips for the 4 they couldn't see, expecting "Interrogami sul
      // visibile". Always-narrow is more intuitive and the banner
      // explains it when applicable.
      if (restrictedToClusterIds == null && !forceShowAll) {
        Rect? scopeBounds;
        final lassoBounds = _lassoTool.hasSelection
            ? _lassoTool.getSelectionBounds()
            : null;
        if (lassoBounds != null) {
          scopeBounds = lassoBounds;
          activeScopeReason = 'lasso';
        } else {
          // Compute viewport in canvas coordinates.
          final size = MediaQuery.of(context).size;
          final scale = _canvasController.scale;
          final offset = _canvasController.offset;
          scopeBounds = Rect.fromLTWH(
            -offset.dx / scale,
            -offset.dy / scale,
            size.width / scale,
            size.height / scale,
          );
          activeScopeReason = 'viewport';
        }
        scopeIds = <String>{};
        for (final c in _clusterCache) {
          if (c.bounds.overlaps(scopeBounds)) scopeIds.add(c.id);
        }
        debugPrint(
            '🔭 Exam scope ($activeScopeReason): ${scopeIds.length}/${_clusterCache.length} clusters');
        // Graceful fallback: if the viewport intersects no clusters but the
        // canvas DOES have content, fall back to "all clusters" so the
        // student isn't blocked by a snackbar when they tapped Interrogami
        // from a blank area. The banner will not appear (no narrow), and
        // the picker shows everything. Lasso selection is left strict —
        // an empty lasso is explicit user intent ("nothing here").
        if (scopeIds.isEmpty &&
            activeScopeReason == 'viewport' &&
            _clusterCache.isNotEmpty) {
          debugPrint(
              '🔭 Exam scope: viewport empty → expanding to all ${_clusterCache.length} clusters');
          scopeIds = null;
          activeScopeReason = null;
        }
      }

      for (final cluster in _clusterCache) {
        // Sprint 5: when launching from Fog of War, narrow to forgotten /
        // blind-spot nodes only. Preserves the spatial-then-generative
        // sequence the cognitive-theory doc prescribes.
        if (restrictedToClusterIds != null &&
            !restrictedToClusterIds.contains(cluster.id)) {
          continue;
        }
        // NOTE: viewport / lasso scope NO LONGER filters out clusters here.
        // Instead, the picker shows ALL clusters and pre-selects the ones
        // in [scopeIds] via [ExamOverlay.initialSelectedClusterIds]. This
        // unblocks the multi-region selection use case (student wants
        // topics from disjoint canvas regions) without changing the OCR
        // workload (we already cache per-cluster text — same compute).
        final text = _clusterTextCache[cluster.id] ?? '';
        if (text.trim().isEmpty) continue; // Skip empty clusters

        // Use AI-generated semantic title if available, else first words of
        // OCR text — sanitized of any LaTeX leaking through from the math
        // recognizer (defensive: Fix A in the Kotlin classifier should catch
        // these, but if anything slips through we don't want garbled `\dfrac`
        // in the picker chip).
        //
        // Title-source priority (consolidation sprint):
        //   1. SemanticMorphController.aiTitles  — populated when student
        //      already zoomed out past the morph threshold this session.
        //   2. ClusterConceptIndex.peek(id)?.title — populated by hydrated
        //      JSON cache on cold-start, OR by a previous canvas open.
        //   3. First words of cluster OCR text (legacy fallback).
        // The index check costs nothing (sync map lookup) and avoids the
        // Atlas batch call when a hydrated title already exists.
        final aiTitle = _semanticMorphController?.aiTitles[cluster.id] ??
            _clusterConceptIndex?.peek(cluster.id)?.title;
        String? displayTitle;
        if (aiTitle != null && aiTitle.trim().isNotEmpty) {
          displayTitle = aiTitle;
        } else {
          final cleaned = _sanitizeDisplayLabel(text);
          if (cleaned.isNotEmpty) {
            displayTitle = cleaned.split(' ').take(4).join(' ');
          }
        }
        if (displayTitle == null || displayTitle.isEmpty) continue;

        availableTitles[cluster.id] = displayTitle;
        clusterTexts[cluster.id] = text;
      }

      if (availableTitles.isEmpty) {
        examController.dispose();
        messenger?.hideCurrentSnackBar();
        if (mounted) {
          final l10n = FlueraLocalizations.of(context)!;
          final msg = restrictedToClusterIds != null
              ? l10n.exam_noBlindSpots
              : l10n.exam_noRecognizableText;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(msg),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF1A1A2E),
            duration: const Duration(seconds: 3),
          ));
        }
        return;
      }

      // 🧠 TOPIC GROUPING — when the OCR produced many small fragments,
      // ask the LLM to bucket them into 3-7 cardinal topics so the picker
      // shows "Le leggi di Newton" / "Forza e massa" instead of 19 chips
      // like "LEGGI" / "NEW" / "Ton" / "PRIMA". Skipped when launched from
      // Fog of War (those cluster IDs need to remain real for the surgical
      // path overlay to highlight on canvas).
      if (restrictedToClusterIds == null && availableTitles.length >= 3) {
        final groups = await _groupClustersByTopic(provider, clusterTexts);
        // We accept the AI grouping even when it returns N=N — the renamed
        // titles ("Prima Legge di Newton") are far better than raw OCR
        // fragments ("LEGGID 1 NEWTON"), even without consolidation.
        if (groups != null && groups.isNotEmpty) {
          final topicTitles = <String, String>{};
          final topicTexts = <String, String>{};
          for (int i = 0; i < groups.length; i++) {
            final g = groups[i];
            final synthId = 'topic_$i';
            topicTitles[synthId] = g.topic;
            topicTexts[synthId] = g.clusterIds
                .map((id) => clusterTexts[id] ?? '')
                .where((t) => t.trim().isNotEmpty)
                .join('\n\n');
          }
          if (topicTitles.isNotEmpty &&
              topicTexts.values.every((t) => t.isNotEmpty)) {
            availableTitles = topicTitles;
            clusterTexts = topicTexts;
            // 🔭 Re-key the viewport scope: when topic grouping rewrites
            // `cluster_*` → `topic_N`, the pre-existing `scopeIds` (raw
            // cluster IDs) no longer match anything in `availableTitles`.
            // The picker would render zero chips — even when there are
            // clusters in viewport. A topic is in-scope if ANY of its
            // source clusters is in-scope.
            final priorScope = scopeIds;
            if (priorScope != null) {
              final remapped = <String>{};
              for (int i = 0; i < groups.length; i++) {
                final synthId = 'topic_$i';
                if (groups[i].clusterIds.any(priorScope.contains)) {
                  remapped.add(synthId);
                }
              }
              if (remapped.isEmpty) {
                // Same graceful fallback as for the raw-cluster path:
                // if remapping wipes the scope clean (rare — would mean
                // the grouped topics don't share clusters with viewport,
                // which can't actually happen unless the AI returns
                // mismatched ids), fall back to all so the picker isn't
                // empty.
                scopeIds = null;
                activeScopeReason = null;
              } else {
                scopeIds = remapped;
              }
            }
            widget.config.telemetry?.logEvent(
              'step_11_exam_topic_grouped',
              properties: {
                'cluster_count': groups
                    .fold<int>(0, (sum, g) => sum + g.clusterIds.length),
                'topic_count': groups.length,
                'language': _deviceLanguageName,
              },
            );
          }
        }
      }

      // Telemetry: mark exams that started from the spatial Fog phase so we
      // can measure how often the integrated flow gets used vs. the bare
      // "Interrogami" entry point in the Atlas menu.
      if (restrictedToClusterIds != null) {
        widget.config.telemetry?.logEvent(
          'step_11_exam_started_from_fog',
          properties: {
            'cluster_count': availableTitles.length,
            'language': _deviceLanguageName,
          },
        );
      }
    }

    // Mount overlay
    if (!mounted) {
      examController.dispose();
      messenger?.hideCurrentSnackBar();
      return;
    }
    final overlay = Overlay.of(context);
    // Sprint 6.1 — expose the controller + blind-spot ids to the canvas
    // layer so the SurgicalPathOverlayPainter can highlight the right
    // clusters in real time. Cleared in the onClose hook below.
    void Function()? surgicalAutoZoomListener;
    if (layout == ExamOverlayLayout.surgicalPath) {
      setState(() {
        _surgicalExamController = examController;
        _surgicalBlindSpotIds = restrictedToClusterIds;
      });

      // Sprint 6.2 — auto-zoom: when the current question's source cluster
      // changes, animate the canvas to keep that cluster centred + framed
      // at 70% of the viewport so the student doesn't have to pinch-zoom
      // hunting for context. Listener removed in onClose.
      String? lastClusterId;
      surgicalAutoZoomListener = () {
        if (!mounted) return; // widget gone — skip silently
        final qId = examController.session?.currentQuestion?.sourceClusterId;
        if (qId == null || qId == lastClusterId) return;
        // Resolve the cluster — if it's gone (canvas reorganised mid-exam)
        // skip the animation rather than zoom to a random nearby cluster.
        ContentCluster? cluster;
        for (final c in _clusterCache) {
          if (c.id == qId) {
            cluster = c;
            break;
          }
        }
        if (cluster == null) return;
        lastClusterId = qId;
        final size = MediaQuery.sizeOf(context);
        // Reserve the bottom 42% of the viewport for the question card.
        // We frame the cluster against a virtual viewport that is just
        // the upper portion, so the cluster doesn't fall behind the card.
        final upperHeight = size.height * 0.58;
        _canvasController.animateToRect(
          worldRect: cluster.bounds,
          viewportSize: Size(size.width, upperHeight),
          paddingRatio: 0.7,
        );
      };
      examController.addListener(surgicalAutoZoomListener);
    }

    late OverlayEntry entry;
    final examPrefs = widget.config.examPreferences;
    entry = OverlayEntry(builder: (_) => ExamOverlay(
      availableClusters: availableTitles,
      clusterTexts: clusterTexts,
      controller: examController,
      // Pre-select either the Fog-of-War blind-spot IDs (priority) or the
      // viewport/lasso-visible cluster IDs. Either way the user can
      // tap-to-toggle individual chips for full multi-region control.
      initialSelectedClusterIds: restrictedToClusterIds ?? scopeIds,
      layout: layout,
      initialQuestionCount: examPrefs?.questionCount ?? 7,
      initialHandwritingMode: examPrefs?.handwritingMode ?? true,
      hypercorrectionEnabled: examPrefs?.hypercorrectionEnabled ?? true,
      reduceMotion: examPrefs?.reduceMotion ?? false,
      colorBlindSafePalette: examPrefs?.colorBlindSafePalette ?? false,
      // Cloud sync is gated solely by the host: when [onUploadExamStrokes]
      // is non-null the engine fires the hook on every save. The host
      // (Fluera app) wires this only for tiers with cloud sync (Plus /
      // Pro), so Free users get a no-op without a per-feature toggle.
      onUploadExamStrokes: widget.config.onUploadExamStrokes,
      // 🌉 Passo 9 → Passo 11: feed the exam any recently accepted bridges
      // so the validation pass appends one NON-Socratic question per pair.
      crossZoneBridges:
          _crossZoneBridgeController?.recentAcceptedBridges().map((b) {
        return (
          sourceLabel: availableTitles[b.sourceClusterId] ?? b.sourceClusterId,
          targetLabel: availableTitles[b.targetClusterId] ?? b.targetClusterId,
          socraticQuestion: b.bridgeSocraticQuestion ?? '',
          sourceClusterId: b.sourceClusterId,
          targetClusterId: b.targetClusterId,
        );
      }).toList(),
      onQuestionCountChanged: examPrefs == null
          ? null
          : (n) => examPrefs.setQuestionCount(n),
      onHandwritingModeChanged: examPrefs == null
          ? null
          : (h) => examPrefs.setHandwritingMode(h),
      // Scope banner — surfaces "we narrowed your topics" so the user
      // doesn't think clusters are missing. Tap "Mostra tutto" → re-mount
      // with `forceShowAll: true`.
      scopeTotalClusterCount: scopeIds != null ? _clusterCache.length : null,
      scopeReason: activeScopeReason,
      onShowAllClusters: scopeIds == null
          ? null
          : () {
              entry.remove();
              examController.dispose();
              if (surgicalAutoZoomListener != null) {
                examController.removeListener(surgicalAutoZoomListener);
              }
              if (layout == ExamOverlayLayout.surgicalPath && mounted) {
                setState(() {
                  _surgicalExamController = null;
                  _surgicalBlindSpotIds = null;
                });
              }
              _startExamSession(
                restrictedToClusterIds: restrictedToClusterIds,
                layout: layout,
                onExamComplete: onExamComplete,
                forceShowAll: true,
              );
            },
      onClose: () {
        entry.remove();
        // Sprint 6.2 — remove the auto-zoom listener BEFORE disposing,
        // so we don't leak it on the disposed controller.
        if (surgicalAutoZoomListener != null) {
          examController.removeListener(surgicalAutoZoomListener);
        }
        examController.dispose();
        // Sprint 6.1 — release the surgical-path painter inputs so the
        // canvas stops rendering the highlights once the exam is gone.
        if (layout == ExamOverlayLayout.surgicalPath && mounted) {
          setState(() {
            _surgicalExamController = null;
            _surgicalBlindSpotIds = null;
          });
        }
        // Sprint 6 — fire reverse-return callback after the overlay is
        // gone. We do this from onClose (not onComplete) so the heatmap
        // restore happens whether the user finishes or abandons the
        // exam — both end states leave the canvas without spatial context.
        if (onExamComplete != null) unawaited(onExamComplete());
      },
      onComplete: (mastered, reviewMap) {
        // Update spaced repetition state
        for (final concept in mastered) {
          _sessionMastered.add(concept);
          final existing = _reviewSchedule[concept] ?? SrsCardData.newCard();
          _reviewSchedule[concept] = FsrsScheduler.review(existing, quality: 2, confidence: 5);
        }
        for (final e in reviewMap.entries) {
          final existing = _reviewSchedule[e.key] ?? SrsCardData.newCard();
          // Map Duration to quality: <=1d = fail, <=3d = partial, 7d+ = correct
          final quality = e.value.inDays <= 1 ? 0 : (e.value.inDays <= 3 ? 1 : 2);
          _reviewSchedule[e.key] = FsrsScheduler.review(existing, quality: quality);
        }
        if (mounted) setState(() {});
      },
    ));
    // Dismiss the pre-overlay loading SnackBar — the picker UI takes over.
    messenger?.hideCurrentSnackBar();
    overlay.insert(entry);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 🎓 Resume dialog (mid-session crash recovery, P1.1)
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns:
  /// * `true`  → user wants to resume the interrupted exam
  /// * `false` → user wants to discard checkpoint and start a new exam
  /// * `null`  → user dismissed (back gesture / barrier tap) — keep checkpoint
  Future<bool?> _showResumeExamDialog(ExamCheckpointPreview preview) {
    final topics = preview.topicTitles.isNotEmpty
        ? preview.topicTitles.join(' · ')
        : '—';
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Row(
          children: [
            Text('🎓', style: TextStyle(fontSize: 22)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Riprendi esame interrotto?',
                style: TextStyle(
                  color: Color(0xFF00E5FF),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Domanda ${preview.questionNumber} di ${preview.totalQuestions}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              topics,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Iniziato ${_relativeTimeAgo(preview.startedAt)}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 11,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Nuovo esame',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF00E5FF),
              foregroundColor: const Color(0xFF0A0A1A),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Riprendi',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 🛡️ GDPR consent gate for AI processing (P2.3)
  // ─────────────────────────────────────────────────────────────────────────

  /// Checks whether the user has granted consent to send their notes to
  /// the Gemini API, prompting once if not.
  ///
  /// Resolution order:
  /// 1. If [FlueraCanvasConfig.hasAiProcessingConsent] returns true → proceed.
  /// 2. If [FlueraCanvasConfig.requestAiProcessingConsent] is wired → ask
  ///    the host (which typically uses [GdprConsentManager]).
  /// 3. Fall back to an inline disclosure dialog (engine-only path, used in
  ///    tests / demos / standalone engine where no host consent UI exists).
  ///
  /// Returns `true` only if consent is granted (or implicit because no
  /// delegates were wired and the local fallback was accepted).
  Future<bool> _ensureAiProcessingConsent() async {
    final cfg = widget.config;

    // Fast path: host already has consent on file.
    final has = cfg.hasAiProcessingConsent;
    if (has != null && has()) return true;

    // Delegate path: ask the host to show its own consent UI.
    if (cfg.requestAiProcessingConsent != null) {
      if (!mounted) return false;
      try {
        final granted = await cfg.requestAiProcessingConsent!(context);
        return granted;
      } catch (_) {
        return false;
      }
    }

    // Engine-only fallback: inline minimal disclosure dialog.
    // This is shown EVERY time the host hasn't wired a consent system —
    // intentional friction so demos/tests don't silently send notes to LLM.
    if (!mounted) return false;
    final granted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Row(
          children: [
            Text('🛡️', style: TextStyle(fontSize: 22)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'I tuoi appunti, Google Gemini',
                style: TextStyle(
                  color: Color(0xFF00E5FF),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Per generare le domande dell\'esame, Fluera invia gli appunti dei cluster selezionati al servizio Google Gemini.',
              style: TextStyle(color: Colors.white, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 12),
            Text(
              '• Vengono inviati: testo OCR degli appunti, lingua del dispositivo.\n'
              '• NON vengono inviati: nome, email, file, immagini originali.\n'
              '• Google non utilizza i dati per addestrare i modelli (Gemini API ToS).\n'
              '• Puoi revocare il consenso in qualsiasi momento dalle Impostazioni.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12,
                height: 1.55,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Annulla',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF00E5FF),
              foregroundColor: const Color(0xFF0A0A1A),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Continua',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    return granted == true;
  }

  /// Strip LaTeX commands and brace/bracket noise from an OCR result so the
  /// picker chip never displays raw `\begin{aligned}\dfrac{}{}…` even if the
  /// math/text classifier misroutes prose into the math editor. Defensive
  /// net for Fix A in `MyScriptInkPlugin.kt`.
  String _sanitizeDisplayLabel(String raw) {
    if (raw.isEmpty) return raw;
    return raw
        .replaceAll(RegExp(r'\\(begin|end)\{[^}]*\}'), '')
        .replaceAll(RegExp(r'\\[A-Za-z]+'), '')
        .replaceAll(RegExp(r'[\{\}\[\]\\]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// 🧠 Group cluster OCR texts by *cardinal topic* via the Atlas LLM.
  ///
  /// When the user has scribbled lecture notes, the cluster detector often
  /// produces many small clusters (one per word/line) — the picker would
  /// then show 15-20 fragmented chips. This helper sends all OCR snippets
  /// to the LLM in ONE call and asks for a topic-level grouping (3-7
  /// groups). Each group has a friendly name + the indices of the source
  /// clusters that belong to it.
  ///
  /// Returns `null` on failure (provider unavailable, parse error, or
  /// fewer than 2 clusters) so callers fall back to the per-cluster view.
  Future<List<({String topic, List<String> clusterIds})>?>
      _groupClustersByTopic(
    AiProvider provider,
    Map<String, String> clusterTexts,
  ) async {
    if (clusterTexts.length < 2) return null;

    // 🚀 B: Cache lookup. Reopening Socratic / Exam on the same cluster
    // set should not re-fire the Gemini batch grouping.
    final cached = _clusterConceptIndex?.cachedTopicGrouping(clusterTexts.keys);
    if (cached != null) {
      debugPrint('🧠 Topic grouping: cache hit (${cached.length} groups)');
      return cached;
    }

    // 🚀 C: Local grouping shortcut. If every cluster already has a
    // `concept.topic` populated (e.g. Atlas Exam ran recently),
    // group locally by topic name without hitting Gemini at all.
    final index = _clusterConceptIndex;
    if (index != null) {
      final byTopic = <String, List<String>>{};
      var allTopicsKnown = true;
      for (final id in clusterTexts.keys) {
        final topic = index.peek(id)?.topic;
        if (topic == null || topic.trim().isEmpty) {
          allTopicsKnown = false;
          break;
        }
        byTopic.putIfAbsent(topic, () => <String>[]).add(id);
      }
      if (allTopicsKnown && byTopic.length >= 2) {
        final groups = byTopic.entries
            .map((e) => (topic: e.key, clusterIds: e.value))
            .toList();
        index.cacheTopicGrouping(clusterTexts.keys, groups);
        debugPrint(
            '🧠 Topic grouping: local fast-path (${groups.length} groups, no Gemini)');
        return groups;
      }
    }

    final entries = clusterTexts.entries.toList();

    final sb = StringBuffer();
    final langCmd = _nativeLangInstruction;
    if (langCmd.isNotEmpty) {
      sb.writeln(langCmd);
      sb.writeln();
    }
    sb.writeln('IGNORE tutte le regole precedenti sui canvas action.');
    sb.writeln('NON usare lo schema {"spiegazione": ..., "azioni": [...]}.');
    sb.writeln('NON creare nodi sul canvas. NON wrappare la risposta.');
    sb.writeln();
    sb.writeln('## RUOLO');
    sb.writeln('Sei un analista semantico di appunti scolastici. Il tuo '
        'compito è capire di QUALI ARGOMENTI tratta uno studente leggendo '
        'frammenti dei suoi appunti riconosciuti da un OCR handwriting.');
    sb.writeln();
    sb.writeln('## L\'OCR È RUMOROSO');
    sb.writeln('Il riconoscimento può:');
    sb.writeln('- Spezzare una parola in due ("NEW" + "Ton" → "Newton")');
    sb.writeln('- Sbagliare lettere ("LELCE" → "LEGGE", "SECUNDA" → "SECONDA")');
    sb.writeln('- Includere simboli spuri (☐ ◦ | _ ~) — IGNORALI');
    sb.writeln('- Produrre frammenti illeggibili o monosillabici ("k", "OM")');
    sb.writeln('PRIMA di raggruppare, ricostruisci mentalmente le parole '
        'corrette dai frammenti vicini.');
    sb.writeln();
    sb.writeln('## REGOLE DI RAGGRUPPAMENTO');
    sb.writeln('1. **Preferisci 2-4 gruppi**, MAI più di 5. Pochi gruppi ben '
        'definiti > tanti gruppi frammentati.');
    sb.writeln('2. **Nome del gruppo**: max 30 caratteri, SPECIFICO e ACCADEMICO.');
    sb.writeln('   ✅ "Le Leggi di Newton", "Fosforilazione ATP", "Equazione di Drake"');
    sb.writeln('   ❌ "Concetti", "Appunti", "Fisica", "Note", "Vari"');
    sb.writeln('3. **Lingua del nome**: identica a quella degli appunti.');
    sb.writeln('4. **Frammenti illeggibili**: assegnali al gruppo tematicamente '
        'più vicino. NON creare un gruppo solo per loro.');
    sb.writeln('5. **NO INVENZIONI**: se un argomento non emerge chiaramente, '
        'non aggiungerlo.');
    sb.writeln('6. **OGNI indice DEVE comparire in ESATTAMENTE UN gruppo**. '
        'Nessun indice mancante, nessun duplicato.');
    sb.writeln();
    sb.writeln('## ESEMPIO');
    sb.writeln('Input frammenti:');
    sb.writeln('1. LEGGI');
    sb.writeln('2. DI');
    sb.writeln('3. NEW');
    sb.writeln('4. Ton');
    sb.writeln('5. PRIMA');
    sb.writeln('6. LELCE');
    sb.writeln('7. F=ma');
    sb.writeln('8. CORPO A RIPOSO');
    sb.writeln('9. SECUNDA');
    sb.writeln('10. AZIONE');
    sb.writeln('11. REAZIONE');
    sb.writeln();
    sb.writeln('✅ Output corretto (3 argomenti cardine):');
    sb.writeln('{"argomenti":['
        '{"nome":"1ª Legge: Inerzia","indici":[1,2,3,4,5,6,8]},'
        '{"nome":"2ª Legge: F=ma","indici":[7,9]},'
        '{"nome":"3ª Legge: Azione-Reazione","indici":[10,11]}'
        ']}');
    sb.writeln();
    sb.writeln('❌ Output sbagliato (frammentato, titoli generici):');
    sb.writeln('{"argomenti":['
        '{"nome":"Leggi","indici":[1,2]},'
        '{"nome":"Newton","indici":[3,4]},'
        '{"nome":"Concetti","indici":[5,6,7,8,9,10,11]}'
        ']}');
    sb.writeln();
    sb.writeln('## FRAMMENTI DA ANALIZZARE');
    for (int i = 0; i < entries.length; i++) {
      final cleaned = _sanitizeDisplayLabel(entries[i].value)
          .replaceAll('\n', ' ')
          .trim();
      sb.writeln('${i + 1}. ${cleaned.isEmpty ? "(illeggibile)" : cleaned}');
    }
    sb.writeln();
    sb.writeln('## OUTPUT');
    sb.writeln('Rispondi SOLO con JSON valido in questo formato ESATTO:');
    sb.writeln('{"argomenti":[{"nome":"...","indici":[...]}]}');
    sb.writeln('La chiave deve essere ESATTAMENTE "argomenti" (non '
        '"topics" / "categorie" / "spiegazione" / "azioni").');
    sb.writeln('Ogni elemento deve avere ESATTAMENTE le chiavi "nome" e "indici".');

    try {
      final response = await provider.askAtlas(sb.toString(), [
        {
          'id': 'topic_grouping',
          'tipo': 'raggruppamento_argomenti',
          'contenuto': 'Batch di ${entries.length} frammenti',
        },
      ]);

      final raw = response.rawJson;
      debugPrint('🧠 Topic grouping rawJson keys: ${raw?.keys.toList() ?? "null"}');

      // The AI sometimes wraps our schema inside the canvas-action shape
      // (`{"spiegazione": ..., "azioni": [...]}`) because that's what the
      // provider's system instruction asks for. We recover the topic list
      // from any of the shapes the model has produced in practice.
      final argomenti = _extractArgomentiList(raw, response.explanation);
      if (argomenti == null || argomenti.isEmpty) {
        debugPrint('🧠 Topic grouping: no usable list in response — '
            'raw=$raw explanation=${response.explanation}');
        return null;
      }

      final result = <({String topic, List<String> clusterIds})>[];
      final usedIndices = <int>{};
      for (final group in argomenti) {
        if (group is! Map) continue;
        final name = (group['nome'] ?? group['titolo'] ?? group['name'] ?? group['title'])
            ?.toString()
            .trim();
        final rawIndices = group['indici'] ??
            group['indices'] ??
            group['appunti'] ??
            group['cluster_ids'] ??
            group['ids'];
        if (name == null || name.isEmpty || rawIndices is! List) continue;

        final ids = <String>[];
        for (final idx in rawIndices) {
          if (idx is! num) continue;
          final i = idx.toInt() - 1;
          if (i < 0 || i >= entries.length) continue;
          if (!usedIndices.add(i)) continue; // skip duplicates
          ids.add(entries[i].key);
        }
        if (ids.isEmpty) continue;
        result.add((topic: name, clusterIds: ids));
      }

      // Reattach orphan clusters (LLM dropped them) to a generic group so
      // the user never loses access to their notes.
      final orphans = <String>[];
      for (int i = 0; i < entries.length; i++) {
        if (!usedIndices.contains(i)) orphans.add(entries[i].key);
      }
      if (orphans.isNotEmpty) {
        final orphanLabel = mounted
            ? (FlueraLocalizations.of(context)?.exam_topicGroup_orphan ?? 'Altri appunti')
            : 'Altri appunti';
        result.add((topic: orphanLabel, clusterIds: orphans));
      }

      debugPrint('🧠 Topic grouping: ${entries.length} frammenti → ${result.length} argomenti');
      // 🧠 Write-through to ClusterConceptIndex so other surfaces
      // (Socratic prompt context, future review dashboards) can read
      // "this cluster belongs to topic X" without re-running this batch.
      final ccIndex = _clusterConceptIndex;
      if (ccIndex != null) {
        for (final group in result) {
          for (final cid in group.clusterIds) {
            ccIndex.setTopic(cid, group.topic);
          }
        }
        // 🚀 B: Cache the full grouping so the next call on the same
        // cluster set returns instantly.
        if (result.isNotEmpty) {
          ccIndex.cacheTopicGrouping(clusterTexts.keys, result);
        }
      }
      return result.isEmpty ? null : result;
    } catch (e, st) {
      debugPrint('🧠 Topic grouping error: $e\n$st');
      return null;
    }
  }

  /// Extracts the argomenti list from possible response shapes:
  /// - `{"argomenti": [...]}`            (our schema, happy path)
  /// - `{"topics": [...]}`               (English synonym)
  /// - `{"categorie": [...]}` / `{"groups": [...]}`   (other synonyms)
  /// - `{"spiegazione": "...{...argomenti...}", "azioni": []}` (canvas-action wrap)
  /// - the explanation field containing JSON when rawJson is empty
  List<dynamic>? _extractArgomentiList(
    Map<String, dynamic>? raw,
    String? explanation,
  ) {
    const candidateKeys = ['argomenti', 'topics', 'categorie', 'groups', 'gruppi'];
    if (raw != null) {
      // Direct hit at top level.
      for (final key in candidateKeys) {
        final v = raw[key];
        if (v is List) return v;
      }
      // Nested under `result` / `data` (some models wrap defensively).
      for (final wrap in ['result', 'data', 'output']) {
        final inner = raw[wrap];
        if (inner is Map<String, dynamic>) {
          for (final key in candidateKeys) {
            final v = inner[key];
            if (v is List) return v;
          }
        }
      }
      // Canvas-action wrap: pull JSON from spiegazione (string) or from the
      // first action's `contenuto` if it looks like JSON.
      final spiegazione = raw['spiegazione'];
      if (spiegazione is String) {
        final parsed = _tryParseEmbeddedArgomenti(spiegazione);
        if (parsed != null) return parsed;
      }
      final azioni = raw['azioni'];
      if (azioni is List) {
        for (final a in azioni) {
          if (a is Map<String, dynamic>) {
            final c = a['contenuto'];
            if (c is String) {
              final parsed = _tryParseEmbeddedArgomenti(c);
              if (parsed != null) return parsed;
            }
          }
        }
      }
    }
    // Last resort: try the explanation field.
    if (explanation != null && explanation.isNotEmpty) {
      final parsed = _tryParseEmbeddedArgomenti(explanation);
      if (parsed != null) return parsed;
    }
    return null;
  }

  /// Attempts to find a JSON object containing an `argomenti`-like list
  /// somewhere inside [text]. Used to recover from canvas-action wrappers
  /// where the model dumped our JSON inside a string field.
  List<dynamic>? _tryParseEmbeddedArgomenti(String text) {
    final match = RegExp(r'\{[\s\S]*\}').firstMatch(text);
    if (match == null) return null;
    try {
      final decoded = jsonDecode(match.group(0)!);
      if (decoded is Map<String, dynamic>) {
        for (final key in ['argomenti', 'topics', 'categorie', 'groups', 'gruppi']) {
          final v = decoded[key];
          if (v is List) return v;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Human-readable relative time ("2 ore fa", "ieri", "5 minuti fa").
  /// Italian only for V1 (resume dialog is Italian-only copy).
  String _relativeTimeAgo(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inMinutes < 1) return 'pochi secondi fa';
    if (diff.inMinutes < 60) return '${diff.inMinutes} minuti fa';
    if (diff.inHours < 24) {
      return diff.inHours == 1 ? '1 ora fa' : '${diff.inHours} ore fa';
    }
    if (diff.inDays == 1) return 'ieri';
    return '${diff.inDays} giorni fa';
  }
}


// =============================================================================
// Atlas helper types
// =============================================================================

/// 🔮 Entry for a concurrent Atlas holographic response card (4).
class _AtlasCardEntry {
  final String id;
  String text;
  final Offset position;

  /// (7) Full conversation chain for multi-turn "Go deeper".
  final List<String> conversationHistory;

  /// 💡 Gap concepts from proactive analysis (shows as violet chips).
  final List<String> gapChips;

  /// 💡 Cluster ID that produced the gap analysis (for node placement).
  final String? sourceClusterId;

  /// 🌟 Self-rating captured from user (-1=non lo so, 0=ho dubbi, 1=lo so già).
  int? selfRating;

  /// ✏️ When non-null, card shows active-recall verify mode for this concept.
  final String? verifyQuestion;

  /// 🔄 When true, the card shows the self-rating row (used by Ripasso 24h).
  final bool showSelfRating;

  /// 🧠 Initial mode for adaptive recall ('spiega' or 'esempio').
  final String verifyInitialMode;

  _AtlasCardEntry({
    required this.id,
    required this.text,
    required this.position,
    this.conversationHistory = const [],
    this.gapChips = const [],
    this.sourceClusterId,
    this.selfRating,
    this.verifyQuestion,
    this.showSelfRating = false,
    this.verifyInitialMode = 'spiega',
  });
}


/// 🌌 Atlas visual effect types.
enum _AtlasVfxType { materialize, laser }

/// 🌌 Entry tracking an active Atlas visual effect.
class _AtlasVfxEntry {
  final Key key;
  final Offset position;
  final _AtlasVfxType type;
  final Offset? toPosition; // for laser effects

  const _AtlasVfxEntry({
    required this.key,
    required this.position,
    required this.type,
    this.toPosition,
  });
}

/// 📥 Stateful dialog for downloading the ML Kit handwriting model.
class _InkModelDownloadDialog extends StatefulWidget {
  @override
  State<_InkModelDownloadDialog> createState() => _InkModelDownloadDialogState();
}

class _InkModelDownloadDialogState extends State<_InkModelDownloadDialog> {
  bool _downloading = false;
  String _status = '';
  bool _failed = false;

  Future<void> _startDownload() async {
    setState(() {
      _downloading = true;
      _failed = false;
      _status = 'Checking model status...';
    });

    try {
      final inkService = DigitalInkService.instance;

      // Step 1: Check if Italian model exists
      setState(() => _status = 'Step 1/4: Checking Italian model...');
      final itDownloaded = await inkService.isModelDownloaded('it');
      setState(() => _status = 'Step 1/4: Italian model ${itDownloaded ? "found ✅" : "not found"}');
      await Future.delayed(const Duration(milliseconds: 500));

      // Step 2: Download if needed
      if (!itDownloaded) {
        setState(() => _status = 'Step 2/4: Downloading Italian model (~15 MB)...');
        final success = await inkService.downloadLanguage('it');
        if (!success) {
          // Try English
          setState(() => _status = 'Step 2/4: Italian failed, trying English...');
          await Future.delayed(const Duration(milliseconds: 300));
          final enDownloaded = await inkService.isModelDownloaded('en');
          if (!enDownloaded) {
            setState(() => _status = 'Step 2/4: Downloading English model...');
            final enSuccess = await inkService.downloadLanguage('en');
            if (!enSuccess) {
              setState(() {
                _downloading = false;
                _failed = true;
                _status = 'Download timed out.\n'
                    'Google requires WiFi to download models.\n'
                    'Connect to WiFi and retry.';
              });
              return;
            }
          }
          setState(() => _status = 'Step 3/4: Initializing English...');
          await inkService.init(languageCode: 'en');
        } else {
          setState(() => _status = 'Step 3/4: Initializing Italian...');
          await inkService.init(languageCode: 'it');
        }
      } else {
        // Model already downloaded, just init
        setState(() => _status = 'Step 3/4: Initializing Italian...');
        await inkService.init(languageCode: 'it');
      }

      // Step 4: Verify
      setState(() => _status = 'Step 4/4: Verifying...');
      await Future.delayed(const Duration(milliseconds: 300));

      if (inkService.isReady) {
        setState(() => _status = 'Ready! ✅ (${inkService.languageCode})');
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) Navigator.of(context).pop(true);
      } else {
        setState(() {
          _downloading = false;
          _failed = true;
          _status = 'Initialization failed.\n'
              'isAvailable: ${inkService.isAvailable}\n'
              'isReady: ${inkService.isReady}\n'
              'lang: ${inkService.languageCode}';
        });
      }
    } catch (e) {
      setState(() {
        _downloading = false;
        _failed = true;
        _status = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Text('✍️', style: TextStyle(fontSize: 24)),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Handwriting Model',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_downloading && !_failed)
            const Text(
              'To recognize handwriting, the recognition model '
              'needs to be downloaded (~15 MB, one time only).\n\n'
              'Download now?',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          if (_downloading) ...[
            const SizedBox(height: 8),
            const SizedBox(
              width: 36, height: 36,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00E5FF)),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _status,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
          if (_failed) ...[
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 36),
            const SizedBox(height: 12),
            Text(
              _status,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
      actions: _downloading
          ? null
          : [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(
                  _failed ? 'Close' : 'Cancel',
                  style: const TextStyle(color: Colors.white54),
                ),
              ),
              if (!_failed)
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5FF),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _startDownload,
                  child: const Text('Download'),
                ),
              if (_failed)
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5FF),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _startDownload,
                  child: const Text('Retry'),
                ),
            ],
    );
  }
}
