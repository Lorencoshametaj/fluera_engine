// ============================================================================
// 🗺️ GHOST MAP / CONFRONTO CENTAURO — Data models
//
// Step 4 of the 12-step mastery methodology: Atlas AI analyzes the student's
// canvas and generates an "ideal" concept map overlay. Ghost nodes represent
// missing concepts, weak nodes flag errors, and ghost connections show
// missing relationships.
//
// The student's canvas is NEVER modified by the AI. All ghost elements
// are rendered as an overlay via GhostMapOverlayPainter.
// ============================================================================

import 'dart:ui';

/// Status of a node in the Ghost Map overlay.
enum GhostNodeStatus {
  /// Concept is completely missing from the student's canvas.
  /// Rendered as dashed outline with ❓ icon.
  missing,

  /// Concept exists but has errors, is incomplete, or weakly explained.
  /// Rendered as yellow halo around the existing cluster.
  weak,

  /// Concept is well-understood and correctly represented.
  /// Rendered as green border around the existing cluster.
  correct,

  /// 🗺️ P4-11: An existing connection between nodes is erroneous —
  /// points in the wrong direction or links unrelated concepts.
  /// Rendered as yellow halo on the existing connection + "?" icon.
  wrongConnection,
}

/// A single node in the Ghost Map overlay.
///
/// Ghost nodes can represent:
/// - **Missing concepts**: positioned near related clusters, content hidden
///   until reveal. Student can attempt to write the concept before seeing
///   Atlas's answer (Hypercorrection Principle).
/// - **Weak/correct assessments**: anchored to existing clusters, showing
///   Atlas's evaluation of the student's understanding.
class GhostNode {
  /// Unique identifier for this ghost node.
  final String id;

  /// The concept text (hidden until [isRevealed] for missing nodes).
  final String concept;

  /// Estimated position on the canvas (canvas coordinates).
  ///
  /// For [GhostNodeStatus.missing]: computed deterministically below
  /// the related cluster (Gemini's x/y are unreliable).
  /// For [GhostNodeStatus.weak] / [GhostNodeStatus.correct]:
  /// position matches the related cluster's centroid.
  ///
  /// Mutable: repositioned by layout pass after AI response.
  Offset estimatedPosition;

  /// Width/height hint for the ghost node bounds.
  final Size estimatedSize;

  /// Status of this node (missing, weak, correct).
  /// Mutable: can be upgraded to wrongConnection during Passo 3 enrichment.
  GhostNodeStatus status;

  /// The existing cluster this relates to (null for truly orphan concepts).
  final String? relatedClusterId;

  /// Atlas's explanation of why this concept is missing/weak.
  final String? explanation;

  /// 🗺️ P4-21: Whether this node was flagged as hypercorrection in Step 3
  /// (student was highly confident but wrong). Gets special visual treatment:
  /// wavy border + ⚡ icon + priority in navigation order.
  /// Mutable: enriched post-creation from Socratic session data.
  bool isHypercorrection;

  /// 🗺️ P4-22: Whether this node is below the student's ZPD (Zone of
  /// Proximal Development). Rendered in grey with "Da approfondire" label
  /// instead of red — no immediate correction required.
  /// Mutable: enriched post-creation from Socratic session data.
  bool isBelowZPD;

  /// 🗺️ P4-23: The student's confidence level (1-5) from Step 3.
  /// Correct nodes with high confidence get a brighter green border.
  /// Mutable: enriched post-creation from Socratic session data.
  int? confidenceLevel;

  /// Whether the student has revealed this ghost node's content.
  bool isRevealed;

  /// What the student wrote as their attempt (before reveal).
  String? userAttempt;

  /// Whether the student's attempt was evaluated as correct.
  bool? attemptCorrect;

  /// Fix #8: Input mode used for the attempt ('pen' or 'text').
  String? inputMode;

  GhostNode({
    required this.id,
    required this.concept,
    required this.estimatedPosition,
    this.estimatedSize = const Size(200, 80),
    required this.status,
    this.relatedClusterId,
    this.explanation,
    this.isHypercorrection = false,
    this.isBelowZPD = false,
    this.confidenceLevel,
    this.isRevealed = false,
    this.userAttempt,
    this.attemptCorrect,
    this.inputMode,
  });

  /// The bounds of this ghost node on the canvas.
  Rect get bounds => Rect.fromCenter(
        center: estimatedPosition,
        width: estimatedSize.width,
        height: estimatedSize.height,
      );

  /// Whether this node is a missing concept (tap to attempt).
  bool get isMissing => status == GhostNodeStatus.missing;

  /// Whether this node is a weak concept (shows warning on existing cluster).
  bool get isWeak => status == GhostNodeStatus.weak;

  /// Whether this node is correct (shows confirmation on existing cluster).
  bool get isCorrect => status == GhostNodeStatus.correct;

  /// Whether this node is a wrong connection flag.
  bool get isWrongConnection => status == GhostNodeStatus.wrongConnection;

  /// 🗺️ P4-23: Whether this is a high-confidence correct node.
  /// These get a brighter green border (#00C853, 3px, 80% opacity).
  bool get isHighConfidenceCorrect =>
      isCorrect && confidenceLevel != null && confidenceLevel! >= 4;
}

/// A suggested connection in the Ghost Map overlay.
///
/// Ghost connections represent relationships that Atlas identifies
/// as missing from the student's knowledge graph. They are rendered
/// as dotted Bézier curves in the overlay.
class GhostConnection {
  /// Unique identifier for this ghost connection.
  final String id;

  /// Source ID — can be a cluster ID or a ghost node ID.
  final String sourceId;

  /// Target ID — can be a cluster ID or a ghost node ID.
  final String targetId;

  /// Optional label describing the relationship.
  final String? label;

  /// Atlas's explanation of why this connection is important.
  final String? explanation;

  /// 🗺️ P4-34/35/36: Whether this is a cross-domain connection (Transfer).
  /// Cross-domain connections link concepts from different subject areas
  /// (e.g., physics and mathematics). Rendered as thicker purple dashes
  /// with a "🔗" icon, to encourage Interleaving (§10) and Transfer (T3).
  final bool isCrossDomain;

  GhostConnection({
    required this.id,
    required this.sourceId,
    required this.targetId,
    this.label,
    this.explanation,
    this.isCrossDomain = false,
  });

  /// Pair key for deduplication (order-independent).
  String get pairKey {
    final a = sourceId.compareTo(targetId) < 0 ? sourceId : targetId;
    final b = sourceId.compareTo(targetId) < 0 ? targetId : sourceId;
    return '$a↔$b';
  }
}

/// Complete Ghost Map result from Atlas AI.
///
/// Contains all ghost nodes, ghost connections, and an overall
/// assessment summary. Generated once per Ghost Map session.
class GhostMapResult {
  /// All ghost nodes (missing, weak, correct).
  final List<GhostNode> nodes;

  /// Suggested connections between existing/ghost nodes.
  final List<GhostConnection> connections;

  /// Overall assessment summary from Atlas.
  final String summary;

  /// When this ghost map was generated.
  final DateTime generatedAt;

  // ── O-09: Single-pass counts (avoids 6× independent list scans) ────────
  /// Counts by status — computed once in constructor via single O(N) pass.
  late final int totalMissing;
  late final int totalWeak;
  late final int totalCorrect;
  late final int totalWrongConnections;
  late final int totalHypercorrection;
  late final int totalBelowZPD;

  GhostMapResult({
    required this.nodes,
    required this.connections,
    required this.summary,
    DateTime? generatedAt,
  }) : generatedAt = generatedAt ?? DateTime.now() {
    int missing = 0, weak = 0, correct = 0, wrong = 0, hyper = 0, zpd = 0;
    for (final n in nodes) {
      switch (n.status) {
        case GhostNodeStatus.missing:         missing++; break;
        case GhostNodeStatus.weak:            weak++;    break;
        case GhostNodeStatus.correct:         correct++; break;
        case GhostNodeStatus.wrongConnection: wrong++;   break;
      }
      if (n.isHypercorrection) hyper++;
      if (n.isBelowZPD) zpd++;
    }
    totalMissing = missing;
    totalWeak = weak;
    totalCorrect = correct;
    totalWrongConnections = wrong;
    totalHypercorrection = hyper;
    totalBelowZPD = zpd;
  }

  /// Empty result (no analysis).
  GhostMapResult.empty()
      : nodes = const [],
        connections = const [],
        summary = '',
        generatedAt = DateTime.now(),
        totalMissing = 0,
        totalWeak = 0,
        totalCorrect = 0,
        totalWrongConnections = 0,
        totalHypercorrection = 0,
        totalBelowZPD = 0;
}
