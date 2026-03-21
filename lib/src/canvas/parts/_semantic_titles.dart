part of '../fluera_canvas_screen.dart';

/// 🧠 SEMANTIC TITLES — OCR recognition + Atlas AI title generation
/// for semantic morph nodes during dezoom.
///
/// When the user zooms out past scale 0.20x, this engine proactively:
/// 1. Recognizes cluster text via ML Kit (populates _clusterTextCache)
/// 2. Sends recognized text to Atlas AI for concise thematic titles
/// 3. Updates SemanticMorphController.aiTitles for the painter
///
/// Rate-limited and debounced to avoid overwhelming the AI provider.
extension SemanticTitlesEngine on _FlueraCanvasScreenState {
  /// Debounce timer for cluster text recognition.
  static Timer? _semanticOcrDebounce;

  /// Debounce timer for AI title requests.
  static Timer? _semanticAiDebounce;

  /// Cache key for each cluster's text content (to detect changes).
  static final Map<String, String> _semanticTextCacheKeys = {};

  /// Max concurrent AI title requests.
  static const int _maxConcurrentAiRequests = 5;

  // ─────────────────────────────────────────────────────────────────────────
  // Cluster text recognition (OCR) for semantic titles
  // ─────────────────────────────────────────────────────────────────────────

  /// 🔤 Recognize handwriting text in all clusters for semantic title generation.
  ///
  /// This is a targeted version of the disabled suggestion engine OCR:
  /// - Only runs when zoom is at/near semantic morph threshold (scale < 0.20)
  /// - Populates `_clusterTextCache` which feeds into `SemanticMorphController`
  /// - Debounced at 800ms to avoid thrashing during pinch-zoom
  void _scheduleSemanticOcr() {
    _semanticOcrDebounce?.cancel();
    _semanticOcrDebounce = Timer(const Duration(milliseconds: 800), () {
      if (mounted) _recognizeClusterTextsForSemanticTitles();
    });
  }

  /// Performs cluster-level OCR and populates `_clusterTextCache`.
  Future<void> _recognizeClusterTextsForSemanticTitles() async {
    if (_clusterCache.isEmpty) return;
    if (_semanticMorphController == null) return;

    final inkService = DigitalInkService.instance;

    // Get active layer strokes and digital text elements
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

    // Prune cache: remove clusters that no longer exist
    final currentIds = _clusterCache.map((c) => c.id).toSet();
    _clusterTextCache.removeWhere((k, _) => !currentIds.contains(k));
    _semanticTextCacheKeys.removeWhere((k, _) => !currentIds.contains(k));

    // Recognize text for each cluster (parallel)
    final futures = <Future<void>>[];
    bool anyChanged = false;

    for (final cluster in _clusterCache) {
      if (cluster.strokeIds.isEmpty && cluster.textIds.isEmpty) continue;

      // Cache key = sorted IDs (detect content changes)
      final allIds = [...cluster.strokeIds, ...cluster.textIds]..sort();
      final cacheKey = allIds.join(',');
      final prevKey = _semanticTextCacheKeys[cluster.id];

      // Cache hit — content unchanged
      if (prevKey == cacheKey && _clusterTextCache.containsKey(cluster.id)) {
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
        _semanticTextCacheKeys[cluster.id] = cacheKey;
        _clusterTextCache[cluster.id] = '';
        continue;
      }

      final clusterId = cluster.id;
      anyChanged = true;

      if (strokeSets.isNotEmpty && inkService.isAvailable) {
        futures.add(
          inkService.recognizeMultiStroke(strokeSets).then((recognized) {
            final parts = [...textParts];
            if (recognized != null && recognized.isNotEmpty) {
              parts.add(recognized);
            }
            final combined = parts.join(' ');
            _semanticTextCacheKeys[clusterId] = cacheKey;
            _clusterTextCache[clusterId] = combined;
          }),
        );
      } else if (textParts.isNotEmpty) {
        final combined = textParts.join(' ');
        _semanticTextCacheKeys[clusterId] = cacheKey;
        _clusterTextCache[clusterId] = combined;
      }
    }

    // Wait for all parallel recognitions
    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }

    // Update semantic morph controller with recognized texts
    if (anyChanged && mounted && _knowledgeFlowController != null) {
      _semanticMorphController!.update(
        clusters: _clusterCache,
        controller: _knowledgeFlowController!,
        clusterTexts: _clusterTextCache,
      );
      _canvasController.markNeedsPaint();

      // Schedule AI title generation after OCR completes
      _scheduleAiTitleGeneration();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Atlas AI title generation
  // ─────────────────────────────────────────────────────────────────────────

  /// 🤖 Schedule AI title generation for clusters with recognized text.
  /// Debounced at 2s to batch multiple cluster changes.
  void _scheduleAiTitleGeneration() {
    _semanticAiDebounce?.cancel();
    _semanticAiDebounce = Timer(const Duration(seconds: 2), () {
      if (mounted) _requestAiSemanticTitles();
    });
  }

  /// 🤖 Request AI-generated titles for clusters that have OCR text
  /// but no AI title yet. Uses a SINGLE batched API call for efficiency.
  Future<void> _requestAiSemanticTitles() async {
    if (_semanticMorphController == null) return;
    if (_clusterTextCache.isEmpty) return;

    // Get clusters needing AI titles (includes invalidated ones)
    final needed = _semanticMorphController!
        .clustersNeedingAiTitles(_clusterTextCache);
    if (needed.isEmpty) return;

    // Rate limit: max N clusters per batch
    final batch = needed.take(_maxConcurrentAiRequests).toList();

    // Check if Atlas provider is available
    final provider = EngineScope.current.atlasProvider;
    if (!provider.isInitialized) {
      try {
        await provider.initialize();
      } catch (e) {
        // AI not available — silently fall back to OCR text
        print('🧠 Semantic titles: Atlas not available, using OCR fallback');
        return;
      }
    }

    // Build batched cluster texts
    final clusterTexts = <String, String>{};
    for (final id in batch) {
      final text = _clusterTextCache[id];
      if (text != null && text.trim().isNotEmpty) {
        clusterTexts[id] = text.trim();
      }
    }
    if (clusterTexts.isEmpty) return;

    // Mark as pending
    for (final id in batch) {
      _semanticMorphController!.pendingAiRequests.add(id);
    }

    try {
      if (clusterTexts.length == 1) {
        // Single cluster — use simple prompt
        final entry = clusterTexts.entries.first;
        await _generateSingleAiTitle(provider, entry.key, entry.value);
      } else {
        // Multiple clusters — use batched prompt (1 API call)
        await _generateBatchedAiTitles(provider, clusterTexts);
      }

      // Refresh semantic titles with new AI data
      if (mounted && _knowledgeFlowController != null) {
        _semanticMorphController!.update(
          clusters: _clusterCache,
          controller: _knowledgeFlowController!,
          clusterTexts: _clusterTextCache,
        );
        _canvasController.markNeedsPaint();
      }
    } catch (e) {
      print('🧠 Semantic titles: AI batch error: $e');
    } finally {
      // Clear pending flags
      for (final id in batch) {
        _semanticMorphController?.pendingAiRequests.remove(id);
      }
    }
  }

  /// 🚀 Generate titles for MULTIPLE clusters in a single API call.
  /// Returns a JSON map of cluster_index → title.
  Future<void> _generateBatchedAiTitles(
    AiProvider provider,
    Map<String, String> clusterTexts,
  ) async {
    try {
      final prompt = _buildBatchedTitlePrompt(clusterTexts);

      final response = await provider.askAtlas(prompt, [
        {
          'id': 'batch_semantic_titles',
          'tipo': 'titoli_semantici',
          'contenuto': 'Batch di ${clusterTexts.length} cluster',
        },
      ]);

      // Parse the JSON response — expect {"1": "Title1", "2": "Title2", ...}
      if (response.rawJson != null) {
        final raw = response.rawJson!;
        // Try direct "titoli" key first
        final titoli = raw['titoli'] as Map<String, dynamic>? ?? raw;

        final clusterIds = clusterTexts.keys.toList();
        for (int i = 0; i < clusterIds.length; i++) {
          final clusterId = clusterIds[i];
          final key = '${i + 1}';
          final rawTitle = titoli[key]?.toString() ?? '';
          final title = _cleanAiTitle(rawTitle);
          if (title != null && title.isNotEmpty && mounted) {
            _semanticMorphController!.recordAiTitle(
              clusterId, title, clusterTexts[clusterId]!,
            );
          }
        }
        return; // Batch succeeded
      }

      // Fallback: parse explanation as line-separated titles
      if (response.explanation != null) {
        final lines = response.explanation!
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList();
        final clusterIds = clusterTexts.keys.toList();
        for (int i = 0; i < clusterIds.length && i < lines.length; i++) {
          final title = _cleanAiTitle(lines[i]);
          if (title != null && title.isNotEmpty && mounted) {
            _semanticMorphController!.recordAiTitle(
              clusterIds[i], title, clusterTexts[clusterIds[i]]!,
            );
          }
        }
      }
    } catch (e) {
      print('🧠 Batched title error: $e — falling back to individual');
      // Fallback: individual requests
      final futures = <Future<void>>[];
      for (final entry in clusterTexts.entries) {
        futures.add(_generateSingleAiTitle(provider, entry.key, entry.value));
      }
      await Future.wait(futures);
    }
  }

  /// Generate a single AI title for one cluster.
  Future<void> _generateSingleAiTitle(
    AiProvider provider,
    String clusterId,
    String clusterText,
  ) async {
    try {
      // Truncate long text to save tokens
      final truncated = clusterText.length > 200
          ? '${clusterText.substring(0, 200)}...'
          : clusterText;

      final prompt = _buildSemanticTitlePrompt(truncated);

      final response = await provider.askAtlas(prompt, [
        {
          'id': clusterId,
          'tipo': 'cluster_text',
          'contenuto': truncated,
        },
      ]);

      // Extract the title from the response
      String? aiTitle;

      // Try explanation field first (plain text response)
      if (response.explanation != null &&
          response.explanation!.trim().isNotEmpty) {
        aiTitle = _cleanAiTitle(response.explanation!);
      }

      // Try raw JSON if explanation is empty
      if (aiTitle == null && response.rawJson != null) {
        final raw = response.rawJson!;
        aiTitle = _cleanAiTitle(
          raw['titolo'] as String? ??
              raw['title'] as String? ??
              raw['spiegazione'] as String? ??
              '',
        );
      }

      if (aiTitle != null && aiTitle.isNotEmpty && mounted) {
        _semanticMorphController!.recordAiTitle(
          clusterId, aiTitle, clusterText,
        );
      }
    } catch (e) {
      print('🧠 Semantic title error for $clusterId: $e');
    }
  }

  /// Clean and truncate an AI-generated title to fit in semantic nodes.
  String? _cleanAiTitle(String raw) {
    var title = raw
        .trim()
        .replaceAll('"', '')
        .replaceAll("'", '')
        .replaceAll('\n', ' ')
        .replaceAll(RegExp(r'\s+'), ' ');

    // Remove common AI prefixes
    for (final prefix in [
      'Titolo:', 'Title:', 'titolo:', 'title:',
      'TITOLO:', 'TITLE:',
    ]) {
      if (title.startsWith(prefix)) {
        title = title.substring(prefix.length).trim();
      }
    }

    if (title.isEmpty) return null;

    // Truncate to 25 chars
    if (title.length > 25) {
      title = '${title.substring(0, 23)}…';
    }

    return title;
  }

  /// Build the Atlas prompt for generating a concise semantic title.
  String _buildSemanticTitlePrompt(String clusterText) {
    return '''IGNORE tutte le regole precedenti sui canvas action.

Sei un titolatore. Devi generare UN SOLO TITOLO tematico di massimo 25 caratteri per questi appunti.

REGOLE:
- MAX 25 caratteri (CRITICO)
- Titolo tematico, NON un riassunto
- Stile: titolo di un capitolo di libro
- Lingua: stessa degli appunti
- NESSUN JSON, NESSUNA spiegazione — rispondi SOLO con il titolo

ESEMPI:
- Appunti: "mitocondri ATP fosforilazione ossidativa catena di trasporto" → "Respirazione Cellulare"
- Appunti: "force = mass * acceleration newton" → "Dinamica Newtoniana"
- Appunti: "SELECT FROM WHERE JOIN SQL database" → "Query SQL"
- Appunti: "integral derivative limit" → "Calcolo Infinitesimale"

APPUNTI:
$clusterText

TITOLO:''';
  }

  /// 🚀 Build a batched prompt for generating multiple titles in one API call.
  /// Output format: JSON with numbered keys {"1": "Title1", "2": "Title2", ...}
  String _buildBatchedTitlePrompt(Map<String, String> clusterTexts) {
    final sb = StringBuffer();
    sb.writeln('IGNORE tutte le regole precedenti sui canvas action.');
    sb.writeln();
    sb.writeln('Sei un titolatore. Devi generare UN TITOLO tematico per OGNUNO dei seguenti ${clusterTexts.length} gruppi di appunti.');
    sb.writeln();
    sb.writeln('REGOLE:');
    sb.writeln('- MAX 25 caratteri per titolo (CRITICO)');
    sb.writeln('- Titolo tematico, NON un riassunto');
    sb.writeln('- Stile: titolo di un capitolo di libro');
    sb.writeln('- Lingua: stessa degli appunti');
    sb.writeln('- Rispondi con JSON: {"titoli": {"1": "Titolo1", "2": "Titolo2", ...}}');
    sb.writeln();
    sb.writeln('APPUNTI:');

    int index = 1;
    for (final entry in clusterTexts.entries) {
      final text = entry.value.length > 150
          ? '${entry.value.substring(0, 150)}...'
          : entry.value;
      sb.writeln('$index. $text');
      index++;
    }

    sb.writeln();
    sb.write('JSON:');
    return sb.toString();
  }

  /// Called when canvas scale changes and approaches semantic morph threshold.
  /// Proactively triggers OCR + AI titles before the morph becomes visible.
  void _checkSemanticTitlePreload(double scale) {
    if (_semanticMorphController == null) return;

    // Preemptively start recognizing text when approaching morph threshold
    if (scale <= SemanticMorphController.aiPreloadScale &&
        _clusterCache.isNotEmpty) {
      // Only schedule if we haven't recognized text for current clusters
      final hasUnrecognized = _clusterCache.any((c) =>
          (c.strokeIds.isNotEmpty || c.textIds.isNotEmpty) &&
          !_clusterTextCache.containsKey(c.id));

      if (hasUnrecognized) {
        _scheduleSemanticOcr();
      } else if (_clusterTextCache.isNotEmpty) {
        // OCR done, check if AI titles are needed
        final needed = _semanticMorphController!
            .clustersNeedingAiTitles(_clusterTextCache);
        if (needed.isNotEmpty) {
          _scheduleAiTitleGeneration();
        }
      }

      // 👻 GHOST CONNECTIONS: Generate AI relationship labels for suggestions
      if (_knowledgeFlowController != null) {
        final suggestions = _knowledgeFlowController!.suggestions;
        final needsLabel = suggestions.where((s) =>
            !s.dismissed &&
            (s.reason.startsWith('Nearby') ||
             s.reason.startsWith('Similar') ||
             s.reason.startsWith('Written') ||
             s.reason.startsWith('Same')) &&
            _clusterTextCache.containsKey(s.sourceClusterId) &&
            _clusterTextCache.containsKey(s.targetClusterId));
        if (needsLabel.isNotEmpty) {
          _scheduleGhostLabelGeneration(needsLabel.toList());
        }
      }

      // 🌍 GOD VIEW: Generate AI macro themes for super-nodes
      if (scale <= SemanticMorphController.godViewStartScale &&
          _semanticMorphController!.superNodes.isNotEmpty) {
        final needsTheme = _semanticMorphController!.superNodes.where((sn) =>
            sn.memberCount > 1 &&
            !_semanticMorphController!.superNodeThemes.containsKey(sn.id) &&
            !_semanticMorphController!.pendingGodViewAi.contains(sn.id));
        if (needsTheme.isNotEmpty) {
          _scheduleGodViewThemes(needsTheme.toList());
        }
      }
    }
  }

  // ===========================================================================
  // 🃏 FLASHCARD PREVIEW — Tap on semantic node
  // ===========================================================================

  /// Handle tap in semantic view: hit-test semantic nodes and toggle flashcard.
  /// [screenPoint] — the tap position in screen coordinates.
  /// Returns true if a semantic node was hit.
  bool _handleSemanticNodeTap(Offset screenPoint) {
    if (_semanticMorphController == null || !_semanticMorphController!.isActive) {
      return false;
    }

    // Convert screen → canvas coordinates
    final canvasPoint = _canvasController.screenToCanvas(screenPoint);
    final scale = _canvasController.scale;

    final hitId = _semanticMorphController!.hitTestSemanticNode(
      canvasPoint, _clusterCache, scale,
    );

    if (hitId != null) {
      if (_semanticMorphController!.flashcardClusterId == hitId) {
        // Tap same node → dismiss
        _semanticMorphController!.dismissFlashcard();
      } else {
        // Show flashcard for this node
        _semanticMorphController!.showFlashcard(hitId);
        HapticFeedback.lightImpact();
      }
      _canvasController.markNeedsPaint();
      return true;
    } else {
      // Tap on empty space → dismiss any open flashcard
      if (_semanticMorphController!.flashcardClusterId != null) {
        _semanticMorphController!.dismissFlashcard();
        _canvasController.markNeedsPaint();
        return true;
      }
    }
    return false;
  }

  // ===========================================================================
  // 🎬 CINEMATIC FLIGHT — Camera transitions from semantic view
  // ===========================================================================

  /// Zoom into a specific cluster from the flashcard "Zoom in →" action.
  /// Dismisses the flashcard and exits semantic morph to show actual content.
  void _handleFlashcardZoomIn(String clusterId) {
    final cluster = _clusterCache.firstWhere(
      (c) => c.id == clusterId, orElse: () => _clusterCache.first,
    );
    if (cluster.id != clusterId) return;

    final viewportSize = MediaQuery.of(context).size;

    // Dismiss flashcard first (with exit animation)
    _semanticMorphController?.dismissFlashcard();
    _canvasController.markNeedsPaint();

    // Zoom to cluster bounds with padding
    final paddedBounds = cluster.bounds.inflate(
      cluster.bounds.longestSide * 0.3,
    );
    CameraActions.zoomToRect(
      _canvasController, paddedBounds, viewportSize,
    );

    HapticFeedback.mediumImpact();
  }

  /// Handle tap on a gravity line in God View — triggers cinematic flight
  /// between the source and target super-nodes.
  /// Returns true if a gravity line was hit.
  bool _handleGravityLineTap(Offset screenPoint) {
    if (_semanticMorphController == null ||
        !_semanticMorphController!.isActive) return false;

    final superNodes = _semanticMorphController!.superNodes;
    if (superNodes.length < 2) return false;

    final canvasPoint = _canvasController.screenToCanvas(screenPoint);
    final viewportSize = MediaQuery.of(context).size;

    // Hit-test gravity lines between super-nodes
    // (same arc geometry as _paintGravityLines in the painter)
    for (int i = 0; i < superNodes.length; i++) {
      for (int j = i + 1; j < superNodes.length; j++) {
        final a = superNodes[i];
        final b = superNodes[j];

        // Check if these super-nodes share member connections
        final hasConnection = _semanticMorphController!
            .superNodesShareConnections(i, j);
        if (!hasConnection) continue;

        // Arc geometry (matches painter)
        final mid = Offset(
          (a.centroid.dx + b.centroid.dx) / 2,
          (a.centroid.dy + b.centroid.dy) / 2,
        );
        final dx = b.centroid.dx - a.centroid.dx;
        final dy = b.centroid.dy - a.centroid.dy;
        if (dx * dx + dy * dy < 1) continue;
        final perpX = -dy;
        final perpY = dx;
        final arcCP = Offset(
          mid.dx + perpX * 0.15,
          mid.dy + perpY * 0.15,
        );

        // Quick distance check: point to control point area
        final tapDist = (canvasPoint - arcCP).distance;
        final lineLen = (b.centroid - a.centroid).distance;
        final hitThreshold = (lineLen * 0.15).clamp(30.0, 150.0);

        // Also check proximity to the full bezier by sampling
        bool isHit = tapDist < hitThreshold;
        if (!isHit) {
          for (double t = 0; t <= 1.0; t += 0.1) {
            final pt = _bezierSample(a.centroid, arcCP, b.centroid, t);
            if ((canvasPoint - pt).distance < hitThreshold * 0.5) {
              isHit = true;
              break;
            }
          }
        }

        if (isHit) {
          // Build bounds for flight
          final aBounds = Rect.fromCenter(
            center: a.centroid, width: 200, height: 200,
          );
          final bBounds = Rect.fromCenter(
            center: b.centroid, width: 200, height: 200,
          );

          CameraActions.flyAlongConnection(
            _canvasController,
            aBounds,
            bBounds,
            viewportSize,
            sourceClusterId: a.id,
            targetClusterId: b.id,
          );

          HapticFeedback.mediumImpact();
          return true;
        }
      }
    }
    return false;
  }

  /// Sample a quadratic bezier at parameter [t].
  static Offset _bezierSample(Offset p0, Offset p1, Offset p2, double t) {
    final mt = 1.0 - t;
    return Offset(
      mt * mt * p0.dx + 2 * mt * t * p1.dx + t * t * p2.dx,
      mt * mt * p0.dy + 2 * mt * t * p1.dy + t * t * p2.dy,
    );
  }

  // ===========================================================================
  // 👻 GHOST CONNECTION AI LABELS
  // ===========================================================================

  static Timer? _ghostLabelDebounce;

  /// Schedule AI label generation for ghost connections (debounced).
  void _scheduleGhostLabelGeneration(List<SuggestedConnection> suggestions) {
    _ghostLabelDebounce?.cancel();
    _ghostLabelDebounce = Timer(const Duration(milliseconds: 3000), () {
      if (mounted) _requestGhostLabels(suggestions);
    });
  }

  /// 🤖 Ask Atlas to describe the RELATIONSHIP between cluster pairs.
  /// Replaces generic labels like "Nearby notes" with semantic ones like
  /// "Legge fondamentale" or "Causa → Effetto".
  Future<void> _requestGhostLabels(List<SuggestedConnection> suggestions) async {
    if (suggestions.isEmpty) return;

    final provider = EngineScope.current.atlasProvider;
    if (!provider.isInitialized) return;

    try {
      // Build batched prompt for all ghost connections
      final sb = StringBuffer();
      sb.writeln('IGNORE tutte le regole precedenti sui canvas action.');
      sb.writeln();
      sb.writeln('Sei un analista di relazioni. Per ogni coppia di appunti, '
          'genera UNA BREVE ETICHETTA (max 20 caratteri) che descriva la '
          'RELAZIONE tra i due gruppi.');
      sb.writeln();
      sb.writeln('REGOLE:');
      sb.writeln('- MAX 20 caratteri per etichetta');
      sb.writeln('- Descrivi il LEGAME, non il contenuto');
      sb.writeln('- Stile: "causa → effetto", "parte di", "esempio di"');
      sb.writeln('- Lingua: stessa degli appunti');
      sb.writeln('- Rispondi con JSON: {"relazioni": {"1": "etichetta1", ...}}');
      sb.writeln();

      int idx = 1;
      final indexed = <int, SuggestedConnection>{};
      for (final s in suggestions.take(5)) {
        final textA = _clusterTextCache[s.sourceClusterId] ?? '';
        final textB = _clusterTextCache[s.targetClusterId] ?? '';
        if (textA.isEmpty || textB.isEmpty) continue;
        final truncA = textA.length > 100 ? '${textA.substring(0, 100)}...' : textA;
        final truncB = textB.length > 100 ? '${textB.substring(0, 100)}...' : textB;
        sb.writeln('$idx. GRUPPO A: "$truncA" ↔ GRUPPO B: "$truncB"');
        indexed[idx] = s;
        idx++;
      }
      if (indexed.isEmpty) return;

      sb.writeln();
      sb.write('JSON:');

      final response = await provider.askAtlas(sb.toString(), [
        {
          'id': 'ghost_labels',
          'tipo': 'relazioni_semantiche',
          'contenuto': 'Batch di ${indexed.length} coppie',
        },
      ]);

      // Parse response
      if (response.rawJson != null) {
        final raw = response.rawJson!;
        final relazioni = raw['relazioni'] as Map<String, dynamic>? ?? raw;
        for (final entry in indexed.entries) {
          final label = relazioni['${entry.key}']?.toString();
          if (label != null && label.isNotEmpty && label.length <= 25) {
            entry.value.reason = label.trim();
          }
        }
      } else if (response.explanation != null) {
        final lines = response.explanation!
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList();
        int i = 0;
        for (final entry in indexed.entries) {
          if (i < lines.length) {
            var label = lines[i].replaceAll(RegExp(r'^\d+\.\s*'), '');
            if (label.length <= 25 && label.isNotEmpty) {
              entry.value.reason = label;
            }
          }
          i++;
        }
      }

      if (mounted) _canvasController.markNeedsPaint();
    } catch (e) {
      print('👻 Ghost label error: $e');
    }
  }

  // ===========================================================================
  // 👆 TAP-TO-CONFIRM GHOST CONNECTION
  // ===========================================================================

  /// Handle a tap on a ghost connection midpoint.
  /// Promotes the ghost to a real connection with auto-label.
  /// Returns true if a ghost was confirmed, false otherwise.
  bool _handleGhostConnectionTap(Offset canvasPoint) {
    if (_knowledgeFlowController == null) return false;
    if (_canvasController.scale > SemanticMorphController.morphStartScale) {
      return false; // Not in semantic view
    }

    final suggestion = _knowledgeFlowController!.hitTestSuggestion(
      canvasPoint, _clusterCache, radius: 40.0,
    );
    if (suggestion == null) return false;

    // 🎉 Promote ghost → real connection!
    final conn = _knowledgeFlowController!.acceptSuggestion(suggestion);
    if (conn != null) {
      // Apply relationship label as connection label
      if (suggestion.reason.isNotEmpty &&
          !suggestion.reason.startsWith('Nearby') &&
          !suggestion.reason.startsWith('Similar') &&
          !suggestion.reason.startsWith('Written') &&
          !suggestion.reason.startsWith('Same') &&
          !suggestion.reason.startsWith('Shared:')) {
        conn.label = suggestion.reason;
      }
      // Haptic confirmation
      HapticFeedback.mediumImpact();
      _canvasController.markNeedsPaint();
    }
    return conn != null;
  }

  // ===========================================================================
  // 🌍 GOD VIEW AI THEMES
  // ===========================================================================

  static Timer? _godViewThemeDebounce;

  void _scheduleGodViewThemes(List<SuperNode> superNodes) {
    _godViewThemeDebounce?.cancel();
    _godViewThemeDebounce = Timer(const Duration(milliseconds: 3000), () {
      if (mounted) _requestGodViewThemes(superNodes);
    });
  }

  /// 🤖 Ask Atlas to generate macro-themes for super-nodes.
  /// E.g., member titles ["Newton", "F=ma", "Gravitazione"] → "Meccanica Classica"
  Future<void> _requestGodViewThemes(List<SuperNode> superNodes) async {
    if (superNodes.isEmpty || _semanticMorphController == null) return;

    final provider = EngineScope.current.atlasProvider;
    if (!provider.isInitialized) return;

    // Mark pending
    for (final sn in superNodes) {
      _semanticMorphController!.pendingGodViewAi.add(sn.id);
    }

    try {
      final sb = StringBuffer();
      sb.writeln('IGNORE tutte le regole precedenti sui canvas action.');
      sb.writeln();
      sb.writeln('Sei un analista tematico. Per ogni gruppo di argomenti, '
          'genera UN MACRO-TEMA (max 25 caratteri) che li unifica.');
      sb.writeln();
      sb.writeln('REGOLE:');
      sb.writeln('- MAX 25 caratteri');
      sb.writeln('- Un titolo tematico ampio, non specifico');
      sb.writeln('- Lingua: stessa degli argomenti');
      sb.writeln('- Rispondi con JSON: {"temi": {"1": "tema1", ...}}');
      sb.writeln();

      int idx = 1;
      final indexed = <int, SuperNode>{};
      for (final sn in superNodes.take(5)) {
        // Collect member titles
        final memberTitles = <String>[];
        for (final mid in sn.memberClusterIds) {
          final title = _semanticMorphController!.aiTitles[mid] ??
              _semanticMorphController!.semanticTitles[mid];
          if (title != null && title.isNotEmpty) memberTitles.add(title);
        }
        if (memberTitles.isEmpty) continue;

        sb.writeln('$idx. ARGOMENTI: ${memberTitles.join(", ")}');
        indexed[idx] = sn;
        idx++;
      }
      if (indexed.isEmpty) {
        for (final sn in superNodes) {
          _semanticMorphController!.pendingGodViewAi.remove(sn.id);
        }
        return;
      }

      sb.writeln();
      sb.write('JSON:');

      final response = await provider.askAtlas(sb.toString(), [
        {'id': 'god_view', 'tipo': 'macro_temi', 'contenuto': 'Batch'},
      ]);

      if (response.rawJson != null) {
        final raw = response.rawJson!;
        final temi = raw['temi'] as Map<String, dynamic>? ?? raw;
        for (final entry in indexed.entries) {
          final theme = temi['${entry.key}']?.toString();
          if (theme != null && theme.isNotEmpty && theme.length <= 30) {
            _semanticMorphController!.superNodeThemes[entry.value.id] =
                theme.trim();
          }
        }
      } else if (response.explanation != null) {
        final lines = response.explanation!
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList();
        int i = 0;
        for (final entry in indexed.entries) {
          if (i < lines.length) {
            var theme = lines[i].replaceAll(RegExp(r'^\d+\.\s*'), '');
            if (theme.length <= 30 && theme.isNotEmpty) {
              _semanticMorphController!.superNodeThemes[entry.value.id] =
                  theme;
            }
          }
          i++;
        }
      }

      // Clear pending
      for (final sn in superNodes) {
        _semanticMorphController!.pendingGodViewAi.remove(sn.id);
      }
      if (mounted) _canvasController.markNeedsPaint();
    } catch (e) {
      print('🌍 God view theme error: $e');
      for (final sn in superNodes) {
        _semanticMorphController!.pendingGodViewAi.remove(sn.id);
      }
    }
  }

  /// Clean up static timers. Call from dispose().
  static void disposeSemanticTitleTimers() {
    _semanticOcrDebounce?.cancel();
    _semanticOcrDebounce = null;
    _semanticAiDebounce?.cancel();
    _semanticAiDebounce = null;
    _ghostLabelDebounce?.cancel();
    _ghostLabelDebounce = null;
    _godViewThemeDebounce?.cancel();
    _godViewThemeDebounce = null;
    _semanticTextCacheKeys.clear();
  }
}
