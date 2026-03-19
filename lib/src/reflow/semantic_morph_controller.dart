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
/// TITLE GENERATION:
///   1. If recognized text exists → use it (truncated)
///   2. Otherwise → generate element summary ("5 tratti • 2 forme")
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

  /// 🔑 Audio-derived keyword titles per cluster ID.
  /// Set externally by AudioKeywordExtractor after transcription correlation.
  Map<String, String> audioTitles = {};

  // ===========================================================================
  // THRESHOLDS
  // ===========================================================================

  /// Scale at which morphing starts (ink begins to fade).
  static const double morphStartScale = 0.12;

  /// Scale at which morphing is complete (fully semantic).
  static const double morphEndScale = 0.06;

  /// Whether the semantic view is at least partially active.
  bool get isActive => morphProgress > 0.01;

  /// Whether the semantic view is fully opaque.
  bool get isFullySemantic => morphProgress > 0.99;

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
      // Linear interpolation between start and end
      final t = (morphStartScale - canvasScale) /
          (morphStartScale - morphEndScale);
      // Smoothstep for premium feel: 3t² - 2t³
      morphProgress = t * t * (3.0 - 2.0 * t);
    }
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

    for (final cluster in clusters) {
      // Generate title
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
    }
  }

  // ===========================================================================
  // TITLE GENERATION
  // ===========================================================================

  /// Generate a human-readable semantic title for a cluster.
  ///
  /// Priority:
  /// 1. Recognized handwriting text (truncated to 25 chars)
  /// 2. Element summary (e.g., "5 tratti • 2 forme")
  /// 3. Fallback: "Cluster"
  String generateTitle(ContentCluster cluster, String? recognizedText) {
    // Priority 1: recognized text
    if (recognizedText != null && recognizedText.trim().isNotEmpty) {
      final text = recognizedText.trim();
      if (text.length <= 25) return text;
      return '${text.substring(0, 23)}…';
    }

    // Priority 2: audio-derived keyword title
    final audioTitle = audioTitles[cluster.id];
    if (audioTitle != null && audioTitle.isNotEmpty) {
      return audioTitle;
    }

    // Priority 2: element summary
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

    // Priority 3: fallback
    return 'Cluster';
  }
}
