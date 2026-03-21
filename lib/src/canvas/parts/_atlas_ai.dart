part of '../fluera_canvas_screen.dart';

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

  // ─────────────────────────────────────────────────────────────────────────
  // Entry point — routes to client-side handlers or Gemini
  // ─────────────────────────────────────────────────────────────────────────

  /// 🌌 ATLAS: End-to-end AI invocation
  Future<void> _invokeAtlas(String prompt) async {
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

      print('🔍 Atlas debug: ${strokeIds.length} stroke IDs, ${recognizedTexts.length} recognized');
      for (final e in recognizedTexts.entries) {
        print('  📝 ${e.key} → "${e.value}"');
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
      if (mounted) setState(() => _atlasLoadingPhase = '🌌 Atlas is thinking...');

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
      print('❌ Atlas error: $e');
      if (mounted) {
        setState(() {
          _atlasIsLoading = false;
          _atlasResponseText = 'Errore: ${e.toString().length > 80 ? '${e.toString().substring(0, 80)}...' : e}';
        });
      }
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
    print('🔤 Strategy 1: Multi-stroke (lang=${inkService.languageCode})...');
    final result = await inkService.recognizeMultiStroke(strokeSets);
    if (result != null && result.trim().isNotEmpty) {
      print('🔤 ✅ Multi-stroke result: "$result"');
      return result;
    }

    // Strategy 2: Single-stroke per stroke
    print('🔤 Strategy 2: Single-stroke...');
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
      print('🔤 ✅ Single-stroke result: "$joined"');
      return joined;
    }

    // Strategy 3: Database fallback
    print('🔤 Strategy 3: Database fallback...');
    final strokeIds = strokeNodes.map((n) => n.id.toString()).toList();
    final textMap = await HandwritingIndexService.instance
        .getTextMapForStrokes(_canvasId, strokeIds);
    if (textMap.isNotEmpty) {
      final uniqueTexts = textMap.values.toSet().toList();
      final result = uniqueTexts.join(' ');
      print('🔤 ✅ Database result: "$result"');
      return result;
    }

    print('🔤 ❌ No recognition from any strategy');
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
      print('🔍 Analyze: ${contentParts.length} parts, types: $detectedTypes');

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
      print('⏱️ Analyze timeout');
      _showErrorInCard('⏱️ Atlas took too long. Try again with less content.');
    } catch (e) {
      // (E) All errors route to the holographic card, not prompt overlay
      print('❌ Analyze error: $e');
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
      print('❌ Go deeper error: $e');
      if (mounted) _updateCardText(cardId, '❌ Error: ${e.toString().length > 80 ? '${e.toString().substring(0, 80)}...' : e}');
    }
  }

  /// (2) Follow-up from a suggestion chip — sends the chip text as a focused question.
  Future<void> _followUpFromCard(String question, String context, Offset position) async {
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
      print('❌ Follow-up error: $e');
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

  _AtlasCardEntry({
    required this.id,
    required this.text,
    required this.position,
    this.conversationHistory = const [],
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
