/// Sealed hierarchy of CLUSTER-level actions that Atlas can request.
///
/// Cluster-level is the dispatcher mode used when the AI must reshape the
/// canvas at the semantic level (concepts, not individual strokes). It is
/// added alongside the existing node-level [AtlasAction] dispatcher to fix
/// a structural bug: node-level commands applied to handwriting were
/// rearranging every single letter-stroke (decision 2026-05-12).
///
/// Cluster ids are produced by `ClusterDetector` (V2 = 240px grid hash)
/// and consumed downstream by `ClusterActionExecutor`, which expands each
/// cluster into its constituent `strokeIds` and applies the transform via
/// `LayerController.runAsBatch` so the whole operation lands as a single
/// undo entry.
sealed class ClusterAction {
  const ClusterAction();

  /// Parse a single cluster action from a JSON map (AI response shape).
  ///
  /// The schema mirrors [AtlasAction.fromJson] (italian-first, english
  /// fallback) so prompts can be authored consistently.
  factory ClusterAction.fromJson(Map<String, dynamic> json) {
    final type = json['tipo'] as String? ?? json['type'] as String? ?? '';
    switch (type) {
      case 'sposta_cluster':
      case 'move_cluster':
        return MoveClusterAction(
          clusterId: json['cluster_id'] as String? ?? '',
          dx: (json['dx'] as num?)?.toDouble() ?? 0,
          dy: (json['dy'] as num?)?.toDouble() ?? 0,
        );

      case 'allinea_clusters':
      case 'align_clusters':
        final ids = (json['cluster_ids'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList();
        return AlignClustersAction(
          clusterIds: ids,
          alignment: _parseAlignment(
            json['allineamento'] as String? ?? json['alignment'] as String?,
          ),
        );

      case 'distribuisci_clusters':
      case 'distribute_clusters':
        final ids = (json['cluster_ids'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList();
        return DistributeClustersAction(
          clusterIds: ids,
          axis: _parseAxis(
            json['asse'] as String? ?? json['axis'] as String?,
          ),
        );

      case 'colora_cluster':
      case 'color_cluster':
        return ColorClusterAction(
          clusterId: json['cluster_id'] as String? ?? '',
          color: json['colore'] as String? ?? json['color'] as String? ?? '',
        );

      case 'collega_clusters':
      case 'connect_clusters':
        return ConnectClustersAction(
          fromId: json['from_id'] as String?
              ?? json['da'] as String?
              ?? '',
          toId: json['to_id'] as String?
              ?? json['a'] as String?
              ?? '',
          label: json['etichetta'] as String? ?? json['label'] as String?,
        );

      default:
        return UnknownClusterAction(type: type, rawJson: json);
    }
  }

  /// Parse a list of cluster actions from the AI's full JSON response.
  /// Mirrors [AtlasAction.parseAll].
  static List<ClusterAction> parseAll(Map<String, dynamic> json) {
    final list = json['azioni'] as List<dynamic>?
        ?? json['actions'] as List<dynamic>?
        ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(ClusterAction.fromJson)
        .toList();
  }

  static ClusterAlignment _parseAlignment(String? raw) {
    switch (raw) {
      case 'left': return ClusterAlignment.left;
      case 'right': return ClusterAlignment.right;
      case 'top': return ClusterAlignment.top;
      case 'bottom': return ClusterAlignment.bottom;
      case 'center_v':
      case 'centerV': return ClusterAlignment.centerV;
      case 'center_h':
      case 'centerH':
      default:
        return ClusterAlignment.centerH;
    }
  }

  static ClusterAxis _parseAxis(String? raw) {
    switch (raw) {
      case 'vertical':
      case 'verticale': return ClusterAxis.vertical;
      case 'horizontal':
      case 'orizzontale':
      default:
        return ClusterAxis.horizontal;
    }
  }
}

enum ClusterAlignment { left, right, top, bottom, centerH, centerV }
enum ClusterAxis { horizontal, vertical }

/// Move a cluster (and all its strokes) by a delta in canvas units.
///
/// The executor expands [clusterId] into its `strokeIds` and applies the
/// same `(dx, dy)` translation to each stroke's `localTransform`. Cluster
/// `bounds` and `centroid` are also shifted to keep state consistent for
/// any subsequent action in the same batch.
class MoveClusterAction extends ClusterAction {
  final String clusterId;
  final double dx;
  final double dy;

  const MoveClusterAction({
    required this.clusterId,
    required this.dx,
    required this.dy,
  });

  @override
  String toString() => 'MoveClusterAction($clusterId, Δ($dx,$dy))';
}

/// Align several clusters along a common edge or center axis.
///
/// The anchor is computed from the cluster bounds (e.g. `min(bounds.left)`
/// for [ClusterAlignment.left]). Each cluster is then moved so that the
/// relevant edge matches the anchor.
class AlignClustersAction extends ClusterAction {
  final List<String> clusterIds;
  final ClusterAlignment alignment;

  const AlignClustersAction({
    required this.clusterIds,
    required this.alignment,
  });

  @override
  String toString() =>
      'AlignClustersAction(${clusterIds.length} clusters, $alignment)';
}

/// Distribute clusters evenly along the given [axis].
///
/// The first and last cluster keep their positions; everything else is
/// re-spaced uniformly between them.
class DistributeClustersAction extends ClusterAction {
  final List<String> clusterIds;
  final ClusterAxis axis;

  const DistributeClustersAction({
    required this.clusterIds,
    required this.axis,
  });

  @override
  String toString() =>
      'DistributeClustersAction(${clusterIds.length} clusters, $axis)';
}

/// Recolor every stroke of a cluster.
///
/// [color] accepts either a neon preset name ('neon_cyan', 'neon_green',
/// 'neon_orange', 'neon_purple') or a `#RRGGBB` hex literal. The executor
/// resolves the value and applies it via `LayerController.updateStroke`
/// for each stroke id in the cluster.
class ColorClusterAction extends ClusterAction {
  final String clusterId;
  final String color;

  const ColorClusterAction({
    required this.clusterId,
    required this.color,
  });

  @override
  String toString() => 'ColorClusterAction($clusterId, "$color")';
}

/// Draw a semantic connection between two clusters.
///
/// The executor connects `clusterA.centroid` and `clusterB.centroid` —
/// the centroid is a stable proxy for "where the concept lives" even when
/// individual strokes shift. Mirrors [ConnectNodesAction] but at cluster
/// granularity.
class ConnectClustersAction extends ClusterAction {
  final String fromId;
  final String toId;
  final String? label;

  const ConnectClustersAction({
    required this.fromId,
    required this.toId,
    this.label,
  });

  @override
  String toString() =>
      'ConnectClustersAction($fromId → $toId${label != null ? ' "$label"' : ''})';
}

/// Fallback for unrecognized cluster-action types. Lets the executor skip
/// without crashing if the model emits a forward-compatible variant.
class UnknownClusterAction extends ClusterAction {
  final String type;
  final Map<String, dynamic> rawJson;

  const UnknownClusterAction({required this.type, required this.rawJson});

  @override
  String toString() => 'UnknownClusterAction($type)';
}
