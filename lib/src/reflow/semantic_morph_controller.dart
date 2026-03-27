import 'dart:ui';
import './content_cluster.dart';
import './knowledge_connection.dart';
import './knowledge_flow_controller.dart';

/// 📊 Stats for a single cluster in semantic view.
class ClusterStats {
  final int strokeCount;
  final int shapeCount;
  final int textCount;
  final int imageCount;
  final int outgoingConnections;
  final int incomingConnections;

  const ClusterStats({
    this.strokeCount = 0,
    this.shapeCount = 0,
    this.textCount = 0,
    this.imageCount = 0,
    this.outgoingConnections = 0,
    this.incomingConnections = 0,
  });

  /// Total element count in the cluster.
  int get totalElements => strokeCount + shapeCount + textCount + imageCount;

  /// Total connection count (in + out).
  int get totalConnections => outgoingConnections + incomingConnections;
}

/// 🌍 SUPER NODE — A merged group of nearby clusters for God View.
///
/// At extreme zoom-out (< 0.04x), nearby semantic nodes fuse into
/// thematic super-nodes providing a strategic canvas overview.
class SuperNode {
  /// Unique super-node ID (= root cluster ID from union-find).
  final String id;

  /// IDs of member clusters that were merged.
  final List<String> memberClusterIds;

  /// Centroid = average of member centroids.
  final Offset centroid;

  /// Total element count across all members.
  final int totalElements;

  /// Number of member clusters.
  final int memberCount;

  const SuperNode({
    required this.id,
    required this.memberClusterIds,
    required this.centroid,
    required this.totalElements,
    required this.memberCount,
  });
}

/// 🧠 SEMANTIC MORPH CONTROLLER — Manages the zoom-out semantic transition.
///
/// When the user pinch-zooms out past a threshold (scale < 0.12),
/// the canvas transitions from showing raw ink to showing clean
/// semantic nodes (circles with titles and stats).
///
/// MORPH PROGRESS:
///   - 0.0 = full ink (normal canvas view)
///   - 1.0 = full semantic (knowledge graph nodes only)
///   - The transition is CONTINUOUS, not stepped — ink fades as nodes appear.
///
/// TITLE GENERATION (priority chain):
///   1. AI-generated thematic title (Atlas) — e.g. "Termodinamica"
///   2. Recognized handwriting text (truncated to 25 chars)
///   3. Audio-derived keyword title
///   4. Element summary ("5 tratti • 2 forme")
///   5. Fallback: "Cluster"
class SemanticMorphController {
  // ===========================================================================
  // MORPH STATE
  // ===========================================================================

  /// Current morph progress: 0.0 = full ink, 1.0 = full semantic.
  double morphProgress = 0.0;

  /// Semantic titles per cluster ID.
  final Map<String, String> semanticTitles = {};

  /// Stats per cluster ID.
  final Map<String, ClusterStats> clusterStats = {};

  /// 📊 IMPORTANCE: Normalized importance score per cluster (0.0–1.0).
  /// Drives visual node sizing: important nodes grow, isolated ones shrink.
  final Map<String, double> clusterImportance = {};

  /// 🚀 PERF: Hash of last cluster config for importance scoring skip.
  String _lastImportanceHash = '';

  /// 🌊 SMOOTH: Interpolated importance (lerps toward target for fluid transitions).
  final Map<String, double> _smoothImportance = {};

  /// 🚀 PERF: True when smooth values have converged (all delta < epsilon).
  bool _smoothConverged = false;

  /// ⭐ Top-20% importance threshold (clusters above this get a star badge).
  double importanceTopThreshold = 0.8;

  /// Get smoothed importance for a cluster (falls back to raw if not yet lerped).
  double getSmoothedImportance(String clusterId) =>
      _smoothImportance[clusterId] ?? clusterImportance[clusterId] ?? 0.5;

  /// 🌊 Step smooth importance values toward targets.
  /// Called once per update cycle (~60fps when in semantic view).
  void stepSmoothImportance() {
    if (_smoothConverged) return; // 🚀 PERF: skip if already converged

    bool allConverged = true;
    for (final e in clusterImportance.entries) {
      final current = _smoothImportance[e.key] ?? e.value;
      final delta = e.value - current;
      if (delta.abs() < 0.001) {
        _smoothImportance[e.key] = e.value; // snap
      } else {
        _smoothImportance[e.key] = current + delta * 0.20;
        allConverged = false;
      }
    }
    _smoothConverged = allConverged;

    // Clean stale entries
    _smoothImportance.removeWhere((id, _) => !clusterImportance.containsKey(id));
  }

  /// 🤖 AI-generated thematic titles per cluster ID (from Atlas).
  /// Highest priority — concise, meaningful titles like "Termodinamica".
  /// Set externally by the canvas semantic title engine after AI response.
  Map<String, String> aiTitles = {};

  /// 🔑 Audio-derived keyword titles per cluster ID.
  /// Set externally by AudioKeywordExtractor after transcription correlation.
  Map<String, String> audioTitles = {};

  /// 🤖 Cluster IDs for which an AI title request is pending.
  /// Prevents duplicate requests for the same cluster.
  final Set<String> pendingAiRequests = {};

  /// 🔄 Hash of OCR text content when AI title was generated.
  /// Used to invalidate AI titles when cluster content changes.
  final Map<String, String> _aiTitleTextHashes = {};

  /// ✨ CROSSFADE: Title transition state per cluster.
  /// Maps cluster ID → timestamp (ms) when the AI title arrived.
  /// Used by the painter to animate a smooth crossfade from OCR → AI title.
  final Map<String, int> titleTransitions = {};

  /// ✨ CROSSFADE: Previous titles before AI arrived (for fade-out).
  final Map<String, String> previousTitles = {};

  /// ✨ Duration of the crossfade animation in milliseconds.
  static const int crossfadeDurationMs = 600;

  // ===========================================================================
  // 🃏 FLASHCARD PREVIEW — Mini-card on semantic node tap
  // ===========================================================================

  /// Currently shown flashcard cluster ID (null = none).
  String? flashcardClusterId;

  /// Timestamp (ms) when the flashcard was shown (for entrance animation).
  int flashcardShowTime = 0;

  /// 🎬 EXIT: Cluster ID of the card being dismissed (for exit animation).
  String? _dismissingClusterId;

  /// 🎬 EXIT: Timestamp (ms) when dismiss started.
  int flashcardDismissTime = 0;

  /// Whether a flashcard is currently in its exit animation.
  bool get isFlashcardDismissing => _dismissingClusterId != null;

  /// The cluster ID of the dismissing flashcard.
  String? get dismissingClusterId => _dismissingClusterId;

  /// Dismiss the flashcard (starts exit animation).
  void dismissFlashcard() {
    if (flashcardClusterId != null) {
      _dismissingClusterId = flashcardClusterId;
      flashcardDismissTime = DateTime.now().millisecondsSinceEpoch;
    }
    flashcardClusterId = null;
  }

  /// Clear the dismissing state after exit animation completes.
  void clearDismissing() {
    _dismissingClusterId = null;
  }

  /// Show flashcard for a specific cluster.
  void showFlashcard(String clusterId) {
    _dismissingClusterId = null; // Cancel any exit animation
    flashcardClusterId = clusterId;
    flashcardShowTime = DateTime.now().millisecondsSinceEpoch;
  }

  /// Hit-test semantic nodes: returns cluster ID if [canvasPoint] falls
  /// within a semantic node circle, null otherwise.
  String? hitTestSemanticNode(
    Offset canvasPoint,
    List<ContentCluster> clusters,
    double canvasScale, {
    Map<String, String> clusterTexts = const {},
  }) {
    if (!isActive) return null;

    final inverseScale = (1.0 / canvasScale).clamp(3.0, 16.0);

    for (final cluster in clusters) {
      // 🔕 Same filter as _paintSemanticNodes: skip tiny clusters without AI title
      final hasAiTitle = clusterTexts[cluster.id]?.isNotEmpty == true;
      if (cluster.strokeIds.length < 20 && !hasAiTitle) continue;

      final center = cluster.centroid;
      // Node radius matches _paintSemanticNodes computation × importance × inverseScale
      final importance = clusterImportance[cluster.id] ?? 0.5;
      final importanceScale = 0.7 + importance * 0.6;
      final baseR = (20.0 + cluster.elementCount.clamp(0, 50) * 0.8) * importanceScale * inverseScale;
      // 20% larger for easier tap
      final hitRadius = baseR * 1.2;

      final dx = canvasPoint.dx - center.dx;
      final dy = canvasPoint.dy - center.dy;
      if (dx * dx + dy * dy <= hitRadius * hitRadius) {
        return cluster.id;
      }
    }
    return null;
  }

  // ===========================================================================
  // THRESHOLDS
  // ===========================================================================

  /// Scale at which morphing starts (ink begins to fade).
  static const double morphStartScale = 0.12;

  /// Scale at which morphing is complete (fully semantic).
  static const double morphEndScale = 0.06;

  /// Scale at which to preemptively start AI title generation.
  /// Slightly above morphStartScale so titles are ready when morphing begins.
  static const double aiPreloadScale = 0.20;

  /// Whether the semantic view is at least partially active.
  bool get isActive => morphProgress > 0.01;

  /// Whether the semantic view is fully opaque.
  bool get isFullySemantic => morphProgress > 0.99;

  // ===========================================================================
  // 🌍 GOD VIEW — Super-node fusion at extreme zoom-out
  // ===========================================================================

  /// Scale at which god view starts (super-nodes begin to appear).
  static const double godViewStartScale = 0.04;

  /// Scale at which god view is complete (only super-nodes visible).
  static const double godViewEndScale = 0.02;

  /// God view morph progress: 0.0 = semantic nodes, 1.0 = super-nodes only.
  double godViewProgress = 0.0;

  /// Whether god view is at least partially active.
  bool get isGodViewActive => godViewProgress > 0.01;

  /// Current super-nodes (recomputed on cluster changes when in god view).
  List<SuperNode> superNodes = [];

  /// 🤖 AI-generated macro themes per super-node ID.
  Map<String, String> superNodeThemes = {};

  /// 🤖 Pending AI theme requests.
  final Set<String> pendingGodViewAi = {};

  /// Distance threshold (canvas px) for merging clusters into super-nodes.
  static const double _superNodeMergeRadius = 400.0;

  /// 🚀 PERF: Hash of last cluster config for super-node skip.
  String _lastSuperNodeHash = '';

  /// 🚀 PERF: Pre-computed membership map (clusterId → super-node index).
  /// Avoids rebuilding per-frame in gravity line rendering.
  Map<String, int> memberToSuperNodeIndex = {};

  /// 🔗 Pre-computed cross-super-node connection pairs.
  /// Set of "snIdxA|snIdxB" strings (sorted) indicating shared connections.
  final Set<String> _crossSuperNodePairs = {};

  /// Check if two super-nodes (by index) share member connections.
  bool superNodesShareConnections(int snIdxA, int snIdxB) {
    final key = snIdxA < snIdxB ? '$snIdxA|$snIdxB' : '$snIdxB|$snIdxA';
    return _crossSuperNodePairs.contains(key);
  }

  // ===========================================================================
  // UPDATE
  // ===========================================================================

  /// Recompute morph progress from the current canvas scale.
  ///
  /// The progress is a continuous value mapped from [morphStartScale]
  /// (where it starts fading) to [morphEndScale] (fully semantic).
  void updateFromScale(double canvasScale) {
    if (canvasScale >= morphStartScale) {
      morphProgress = 0.0;
    } else if (canvasScale <= morphEndScale) {
      morphProgress = 1.0;
    } else {
      final t = (morphStartScale - canvasScale) /
          (morphStartScale - morphEndScale);
      morphProgress = t * t * (3.0 - 2.0 * t);
    }

    // 🌍 GOD VIEW: secondary morph tier
    if (canvasScale >= godViewStartScale) {
      godViewProgress = 0.0;
    } else if (canvasScale <= godViewEndScale) {
      godViewProgress = 1.0;
    } else {
      final t = (godViewStartScale - canvasScale) /
          (godViewStartScale - godViewEndScale);
      godViewProgress = t * t * (3.0 - 2.0 * t);
    }
  }

  /// 🌍 Compute super-nodes by spatially merging nearby clusters.
  ///
  /// Uses Union-Find for efficient single-linkage clustering.
  void computeSuperNodes(List<ContentCluster> clusters) {
    if (clusters.isEmpty) {
      superNodes = [];
      memberToSuperNodeIndex = {};
      return;
    }

    // 🚀 PERF: Skip recomputation if clusters haven't changed
    final ids = clusters.map((c) => c.id).toList()..sort();
    final hash = ids.join('|');
    if (hash == _lastSuperNodeHash && superNodes.isNotEmpty) {
      return; // Unchanged — skip O(n²)
    }
    _lastSuperNodeHash = hash;

    // Union-Find
    final parent = <String, String>{};
    String find(String id) {
      while (parent[id] != id) {
        parent[id] = parent[parent[id]!]!;
        id = parent[id]!;
      }
      return id;
    }
    void union(String a, String b) {
      final ra = find(a), rb = find(b);
      if (ra != rb) parent[ra] = rb;
    }

    for (final c in clusters) {
      parent[c.id] = c.id;
    }

    // Merge nearby clusters (squared distance)
    final threshold2 = _superNodeMergeRadius * _superNodeMergeRadius;
    for (int i = 0; i < clusters.length; i++) {
      for (int j = i + 1; j < clusters.length; j++) {
        final dx = clusters[i].centroid.dx - clusters[j].centroid.dx;
        final dy = clusters[i].centroid.dy - clusters[j].centroid.dy;
        if (dx * dx + dy * dy < threshold2) {
          union(clusters[i].id, clusters[j].id);
        }
      }
    }

    // Build groups
    final groups = <String, List<ContentCluster>>{};
    for (final c in clusters) {
      groups.putIfAbsent(find(c.id), () => []).add(c);
    }

    // Convert to SuperNodes
    superNodes = groups.entries.map((entry) {
      final members = entry.value;
      double cx = 0, cy = 0;
      int total = 0;
      for (final m in members) {
        cx += m.centroid.dx;
        cy += m.centroid.dy;
        total += m.elementCount;
      }
      cx /= members.length;
      cy /= members.length;
      return SuperNode(
        id: entry.key,
        memberClusterIds: members.map((m) => m.id).toList(),
        centroid: Offset(cx, cy),
        totalElements: total,
        memberCount: members.length,
      );
    }).toList()
      ..sort((a, b) => b.totalElements.compareTo(a.totalElements));

    // 🚀 PERF: Pre-compute membership map (avoids per-frame rebuild)
    memberToSuperNodeIndex = {};
    for (int i = 0; i < superNodes.length; i++) {
      for (final mid in superNodes[i].memberClusterIds) {
        memberToSuperNodeIndex[mid] = i;
      }
    }

    // Clean stale
    final superIds = superNodes.map((s) => s.id).toSet();
    superNodeThemes.removeWhere((id, _) => !superIds.contains(id));
    pendingGodViewAi.removeWhere((id) => !superIds.contains(id));
  }

  /// Recompute semantic titles and stats from current clusters and connections.
  ///
  /// [clusters] — all content clusters on the canvas.
  /// [controller] — knowledge flow controller for connection stats.
  /// [clusterTexts] — recognized text per cluster (from digital ink / OCR).
  void update({
    required List<ContentCluster> clusters,
    required KnowledgeFlowController controller,
    required Map<String, String> clusterTexts,
  }) {
    semanticTitles.clear();
    clusterStats.clear();
    clusterImportance.clear();

    // 🚀 PERF: Hash for importance cache (IDs + element counts + connections)
    final importanceHashBuf = StringBuffer();

    for (final cluster in clusters) {
      // Generate title using the full priority chain
      semanticTitles[cluster.id] = generateTitle(
        cluster,
        clusterTexts[cluster.id],
      );

      // Compute stats
      final connStats = controller.connectionStatsForCluster(cluster.id);
      clusterStats[cluster.id] = ClusterStats(
        strokeCount: cluster.strokeIds.length,
        shapeCount: cluster.shapeIds.length,
        textCount: cluster.textIds.length,
        imageCount: cluster.imageIds.length,
        outgoingConnections: connStats.outgoing,
        incomingConnections: connStats.incoming,
      );
      importanceHashBuf.write('${cluster.id}:${cluster.elementCount}:${connStats.outgoing + connStats.incoming}|');
    }

    // 📊 IMPORTANCE SCORING — skip if unchanged
    final importanceHash = importanceHashBuf.toString();
    final importanceChanged = importanceHash != _lastImportanceHash;
    _lastImportanceHash = importanceHash;

    if (importanceChanged) {
    // 📊 IMPORTANCE SCORING — normalize across all clusters
    if (clusters.length > 1) {
      int maxConns = 1;
      int maxElements = 1;
      double maxMass = 1.0;
      for (final cluster in clusters) {
        final s = clusterStats[cluster.id];
        if (s != null && s.totalConnections > maxConns) {
          maxConns = s.totalConnections;
        }
        if (cluster.elementCount > maxElements) {
          maxElements = cluster.elementCount;
        }
        if (cluster.mass > maxMass) maxMass = cluster.mass;
      }

      for (final cluster in clusters) {
        final s = clusterStats[cluster.id];
        final connScore = (s?.totalConnections ?? 0) / maxConns;
        final contentScore = cluster.elementCount / maxElements;
        final massScore = cluster.mass / maxMass;
        // Weighted: 45% connections, 35% content, 20% spatial mass
        clusterImportance[cluster.id] =
            connScore * 0.45 + contentScore * 0.35 + massScore * 0.20;
      }

      // ⭐ Compute top-20% threshold for star badges
      final sorted = clusterImportance.values.toList()..sort();
      final p80Index = (sorted.length * 0.80).floor().clamp(0, sorted.length - 1);
      importanceTopThreshold = sorted[p80Index];
    } else if (clusters.length == 1) {
      clusterImportance[clusters.first.id] = 1.0;
      importanceTopThreshold = 1.0;
    }
      _smoothConverged = false; // Reset convergence since values changed
    } // end if (importanceChanged)

    // 🌊 Step smooth importance toward targets
    stepSmoothImportance();

    // 🔗 Build cross-super-node connection pairs (for gravity line hit-testing)
    _crossSuperNodePairs.clear();
    if (superNodes.length > 1) {
      for (final conn in controller.connections) {
        final snA = memberToSuperNodeIndex[conn.sourceClusterId];
        final snB = memberToSuperNodeIndex[conn.targetClusterId];
        if (snA == null || snB == null || snA == snB) continue;
        final key = snA < snB ? '$snA|$snB' : '$snB|$snA';
        _crossSuperNodePairs.add(key);
      }
    }

    // Clean up stale entries for removed clusters
    final currentIds = clusters.map((c) => c.id).toSet();
    aiTitles.removeWhere((id, _) => !currentIds.contains(id));
    pendingAiRequests.removeWhere((id) => !currentIds.contains(id));
    _aiTitleTextHashes.removeWhere((id, _) => !currentIds.contains(id));
    titleTransitions.removeWhere((id, _) => !currentIds.contains(id));
    previousTitles.removeWhere((id, _) => !currentIds.contains(id));
  }

  /// Returns cluster IDs that need an AI title request.
  ///
  /// A cluster needs an AI title if:
  /// 1. It has recognized text (from OCR or digital text)
  /// 2. It doesn't already have an AI title OR the title is stale
  /// 3. It doesn't have a pending AI request
  List<String> clustersNeedingAiTitles(Map<String, String> clusterTexts) {
    final needed = <String>[];
    for (final entry in clusterTexts.entries) {
      final id = entry.key;
      final text = entry.value;
      if (text.trim().isEmpty) continue;
      if (pendingAiRequests.contains(id)) continue;

      // New cluster — no AI title yet
      if (!aiTitles.containsKey(id)) {
        needed.add(id);
        continue;
      }

      // Existing AI title — check if content changed (invalidation)
      final textHash = text.trim().hashCode.toString();
      final prevHash = _aiTitleTextHashes[id];
      if (prevHash != null && prevHash != textHash) {
        // Content changed → invalidate stale AI title
        needed.add(id);
      }
    }
    return needed;
  }

  /// Record the text hash when an AI title is set.
  /// Call this after successfully storing an AI title.
  void recordAiTitle(String clusterId, String aiTitle, String sourceText) {
    aiTitles[clusterId] = aiTitle;
    _aiTitleTextHashes[clusterId] = sourceText.trim().hashCode.toString();

    // ✨ CROSSFADE: Save previous title and mark transition start
    final currentTitle = semanticTitles[clusterId];
    if (currentTitle != null && currentTitle != aiTitle) {
      previousTitles[clusterId] = currentTitle;
      titleTransitions[clusterId] = DateTime.now().millisecondsSinceEpoch;
    }
  }

  /// 🧠 Get a copy of the AI title text hashes (for persistence).
  Map<String, String> getAiTitleHashes() => Map.unmodifiable(_aiTitleTextHashes);

  /// 🧠 Restore AI titles and content hashes from persisted storage.
  /// Called during canvas load to avoid regenerating titles.
  void restoreAiTitles(Map<String, String> titles, Map<String, String> hashes) {
    aiTitles.addAll(titles);
    _aiTitleTextHashes.addAll(hashes);
  }

  /// ✨ Get the interpolated title for crossfade animation.
  /// Returns (displayTitle, opacity) where opacity is 0.0-1.0
  /// representing how visible the current title is.
  (String title, double opacity) getCrossfadeTitle(String clusterId) {
    final transitionStart = titleTransitions[clusterId];
    final currentTitle = semanticTitles[clusterId] ?? 'Cluster';

    if (transitionStart == null) {
      return (currentTitle, 1.0);
    }

    final elapsed = DateTime.now().millisecondsSinceEpoch - transitionStart;
    if (elapsed >= crossfadeDurationMs) {
      // Transition complete — clean up
      titleTransitions.remove(clusterId);
      previousTitles.remove(clusterId);
      return (currentTitle, 1.0);
    }

    // Mid-transition: return the new title with growing opacity
    final t = elapsed / crossfadeDurationMs;
    // Ease-in-out: smoothstep
    final progress = t * t * (3.0 - 2.0 * t);
    return (currentTitle, progress);
  }

  /// Whether any title crossfade animation is currently active.
  /// Used by the painter to know if continuous repaints are needed.
  bool get hasPendingTransitions => titleTransitions.isNotEmpty;

  // ===========================================================================
  // TITLE GENERATION
  // ===========================================================================

  /// Generate a human-readable semantic title for a cluster.
  ///
  /// Priority chain:
  /// 1. AI-generated thematic title (Atlas) — concise, meaningful
  /// 2. Recognized handwriting text (truncated to 25 chars)
  /// 3. Audio-derived keyword title
  /// 4. Local keyword extraction (offline fallback) — stop-word filtered
  /// 5. Element summary (e.g., "5 tratti • 2 forme")
  /// 6. Fallback: "Cluster"
  String generateTitle(ContentCluster cluster, String? recognizedText) {
    // Priority 1: AI-generated thematic title
    final aiTitle = aiTitles[cluster.id];
    if (aiTitle != null && aiTitle.isNotEmpty) {
      return aiTitle;
    }

    // Priority 2: recognized text (short enough to display directly)
    if (recognizedText != null && recognizedText.trim().isNotEmpty) {
      final text = recognizedText.trim();
      if (text.length <= 25) return text;
      // Priority 3.5: try keyword extraction before raw truncation
      final keywords = extractLocalKeywords(text);
      if (keywords != null) return keywords;
      return '${text.substring(0, 23)}…';
    }

    // Priority 3: audio-derived keyword title
    final audioTitle = audioTitles[cluster.id];
    if (audioTitle != null && audioTitle.isNotEmpty) {
      return audioTitle;
    }

    // Priority 5: element summary
    final parts = <String>[];
    if (cluster.strokeIds.isNotEmpty) {
      parts.add('${cluster.strokeIds.length} tratti');
    }
    if (cluster.shapeIds.isNotEmpty) {
      parts.add('${cluster.shapeIds.length} forme');
    }
    if (cluster.textIds.isNotEmpty) {
      parts.add('${cluster.textIds.length} testi');
    }
    if (cluster.imageIds.isNotEmpty) {
      parts.add('${cluster.imageIds.length} immagini');
    }

    if (parts.isNotEmpty) return parts.join(' • ');

    // Priority 6: fallback
    return 'Cluster';
  }

  // ===========================================================================
  // CONTENT ICON
  // ===========================================================================

  /// 🏷️ Get a content-type icon for a cluster based on its composition.
  ///
  /// Returns an emoji that represents the dominant content type:
  /// - 📐 Math/LaTeX content
  /// - 📝 Handwriting/text
  /// - 🖼 Images
  /// - 📊 Tables
  /// - 🔗 Hub node (3+ connections)
  /// - 📎 Mixed content
  String contentIcon(String clusterId) {
    final stats = clusterStats[clusterId];
    if (stats == null) return '📝';

    // Hub node takes priority — it's a structural indicator
    if (stats.totalConnections >= 3) return '🔗';

    // Dominant content type
    if (stats.imageCount > 0 && stats.imageCount >= stats.strokeCount) {
      return '🖼';
    }
    if (stats.textCount > 0 && stats.strokeCount == 0) {
      return '📝';  // Pure digital text
    }

    // Default to handwriting icon
    return '✏️';
  }

  /// 🏷️ Check if a cluster contains LaTeX content.
  /// This is checked via the cluster text — if it contains LaTeX markers.
  String contentIconFromText(String clusterId, String? clusterText) {
    final stats = clusterStats[clusterId];

    // Hub node takes priority
    if (stats != null && stats.totalConnections >= 3) return '🔗';

    // Check for LaTeX/math markers in recognized text
    if (clusterText != null) {
      final lower = clusterText.toLowerCase();
      if (lower.contains(r'\frac') || lower.contains(r'\int') ||
          lower.contains(r'\sum') || lower.contains(r'\sqrt') ||
          lower.contains('equation') || lower.contains('theorem') ||
          RegExp(r'[=+\-*/^]{2,}').hasMatch(lower) ||
          RegExp(r'\b[xyz]\s*[=<>]').hasMatch(lower)) {
        return '📐';
      }

      // Check for table/data markers
      if (lower.contains('table') || lower.contains('tabella') ||
          lower.contains('csv') || lower.contains('colonna')) {
        return '📊';
      }
    }

    // Image-heavy
    if (stats != null && stats.imageCount > 0 &&
        stats.imageCount >= stats.strokeCount) {
      return '🖼';
    }

    // Default
    return '✏️';
  }

  // ===========================================================================
  // LOCAL KEYWORD EXTRACTION (OFFLINE FALLBACK)
  // ===========================================================================

  /// Common stop-words to filter out (multilingual: IT + EN).
  static const _stopWords = <String>{
    // Italian
    'il', 'la', 'lo', 'le', 'gli', 'un', 'una', 'di', 'da', 'in', 'a',
    'e', 'è', 'che', 'non', 'per', 'con', 'su', 'del', 'della', 'dei',
    'delle', 'al', 'alla', 'nel', 'nella', 'sono', 'come', 'si', 'ha',
    'più', 'anche', 'ma', 'se', 'era', 'dove', 'quando', 'questo',
    'questa', 'questi', 'quello', 'quella', 'essere', 'avere', 'fare',
    'suo', 'sua', 'suoi', 'loro', 'molto', 'tutto', 'tutti', 'ogni',
    // English
    'the', 'an', 'is', 'are', 'was', 'were', 'be', 'been', 'being',
    'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would', 'could',
    'should', 'may', 'might', 'shall', 'can', 'need', 'to', 'of',
    'for', 'on', 'with', 'at', 'by', 'from', 'as', 'into', 'through',
    'during', 'before', 'after', 'above', 'below', 'between', 'out',
    'off', 'up', 'down', 'and', 'but', 'or', 'nor', 'not', 'so', 'yet',
    'both', 'either', 'neither', 'each', 'every', 'all', 'any', 'few',
    'more', 'most', 'other', 'some', 'such', 'no', 'only', 'own',
    'same', 'than', 'too', 'very', 'just', 'because', 'if', 'when',
    'where', 'how', 'what', 'which', 'who', 'whom', 'this', 'that',
    'these', 'those', 'it', 'its', 'he', 'she', 'we', 'they', 'them',
    'his', 'her', 'our', 'their', 'my', 'your', 'about', 'then',
  };

  /// 🧠 Extract 2-3 significant keywords from OCR text.
  ///
  /// Strategy:
  /// 1. Tokenize and lowercase
  /// 2. Remove stop-words (IT + EN)
  /// 3. Remove short words (< 3 chars)
  /// 4. Score by word length (longer = more specific)
  /// 5. Take top 2-3 keywords, capitalize
  ///
  /// Returns null if no significant keywords found.
  static final RegExp _kwNonWordRe = RegExp(r'[^\w\s\u00C0-\u024F]');
  static final RegExp _kwWhitespaceRe = RegExp(r'\s+');

  static String? extractLocalKeywords(String text) {
    final words = text
        .replaceAll(_kwNonWordRe, ' ')
        .split(_kwWhitespaceRe)
        .where((w) => w.length >= 3)
        .where((w) => !_stopWords.contains(w.toLowerCase()))
        .toList();

    if (words.isEmpty) return null;

    // Deduplicate (case-insensitive), keep first occurrence
    final seen = <String>{};
    final unique = <String>[];
    for (final w in words) {
      final key = w.toLowerCase();
      if (seen.add(key)) unique.add(w);
    }

    if (unique.isEmpty) return null;

    // Score by length (longer words are more specific/meaningful)
    unique.sort((a, b) => b.length.compareTo(a.length));

    // Take top 2-3 keywords
    final count = unique.length.clamp(1, 3);
    final selected = unique.take(count).map(_capitalize).toList();
    final result = selected.join(' • ');

    // Must fit in 25 chars
    if (result.length > 25) {
      // Try with just 2
      final shorter = selected.take(2).join(' • ');
      if (shorter.length > 25) {
        // Just 1
        final single = selected.first;
        if (single.length > 25) return '${single.substring(0, 23)}…';
        return single;
      }
      return shorter;
    }

    return result;
  }

  /// Capitalize first letter of a word.
  static String _capitalize(String word) {
    if (word.isEmpty) return word;
    return word[0].toUpperCase() + word.substring(1).toLowerCase();
  }
}
