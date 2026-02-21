/// 📦 ASSET DEPENDENCY GRAPH — Tracks node ↔ asset relationships.
///
/// Maintains a bidirectional mapping between scene-graph nodes and
/// the assets they reference. Enables:
/// - **Impact analysis** — "which nodes break if this asset is deleted?"
/// - **Broken link detection** — "which node references a missing asset?"
/// - **Garbage collection** — "which assets have zero node references?"
///
/// ```dart
/// final graph = AssetDependencyGraph();
/// graph.link('image-node-1', 'sha256:abc123');
/// graph.link('image-node-2', 'sha256:abc123');
///
/// graph.nodesUsing('sha256:abc123'); // → {'image-node-1', 'image-node-2'}
/// graph.assetsUsedBy('image-node-1'); // → {'sha256:abc123'}
///
/// final broken = graph.findBrokenLinks(assetIds);
/// // → [BrokenLink(nodeId: 'image-node-3', assetId: 'sha256:missing')]
/// ```
library;

import 'asset_handle.dart';

// =============================================================================
// BROKEN LINK
// =============================================================================

/// A reference from a node to an asset that cannot be resolved.
class BrokenLink {
  /// The node holding the broken reference.
  final String nodeId;

  /// The asset ID that could not be found.
  final String assetId;

  /// Reason for the broken link.
  final BrokenLinkReason reason;

  const BrokenLink({
    required this.nodeId,
    required this.assetId,
    required this.reason,
  });

  @override
  String toString() =>
      'BrokenLink(node=$nodeId, asset=$assetId, ${reason.name})';
}

/// Why an asset link is considered broken.
enum BrokenLinkReason {
  /// Asset ID not found in the registry.
  missing,

  /// Asset exists but is in error state.
  error,

  /// Asset was evicted and needs reload.
  evicted,

  /// Asset was permanently disposed.
  disposed,
}

// =============================================================================
// ASSET DEPENDENCY GRAPH
// =============================================================================

/// Bidirectional graph tracking which nodes reference which assets.
///
/// Thread-safe for single-isolate use. All mutations are O(1) amortized.
class AssetDependencyGraph {
  /// Forward: nodeId → set of assetIds.
  final Map<String, Set<String>> _nodeToAssets = {};

  /// Reverse: assetId → set of nodeIds.
  final Map<String, Set<String>> _assetToNodes = {};

  /// Whether this graph has been disposed.
  bool _disposed = false;

  /// Create an empty dependency graph.
  AssetDependencyGraph();

  // ===========================================================================
  // MUTATIONS
  // ===========================================================================

  /// Register that [nodeId] depends on [assetId].
  ///
  /// Idempotent — linking the same pair twice is a no-op.
  void link(String nodeId, String assetId) {
    assert(!_disposed, 'AssetDependencyGraph is disposed');
    (_nodeToAssets[nodeId] ??= {}).add(assetId);
    (_assetToNodes[assetId] ??= {}).add(nodeId);
  }

  /// Remove the dependency of [nodeId] on [assetId].
  void unlink(String nodeId, String assetId) {
    assert(!_disposed, 'AssetDependencyGraph is disposed');
    _nodeToAssets[nodeId]?.remove(assetId);
    if (_nodeToAssets[nodeId]?.isEmpty ?? false) {
      _nodeToAssets.remove(nodeId);
    }
    _assetToNodes[assetId]?.remove(nodeId);
    if (_assetToNodes[assetId]?.isEmpty ?? false) {
      _assetToNodes.remove(assetId);
    }
  }

  /// Remove all dependencies for a node (e.g. when node is deleted).
  void unlinkNode(String nodeId) {
    final assetIds = _nodeToAssets.remove(nodeId);
    if (assetIds == null) return;
    for (final assetId in assetIds) {
      _assetToNodes[assetId]?.remove(nodeId);
      if (_assetToNodes[assetId]?.isEmpty ?? false) {
        _assetToNodes.remove(assetId);
      }
    }
  }

  /// Remove all dependencies for an asset (e.g. when asset is purged).
  void unlinkAsset(String assetId) {
    final nodeIds = _assetToNodes.remove(assetId);
    if (nodeIds == null) return;
    for (final nodeId in nodeIds) {
      _nodeToAssets[nodeId]?.remove(assetId);
      if (_nodeToAssets[nodeId]?.isEmpty ?? false) {
        _nodeToAssets.remove(nodeId);
      }
    }
  }

  // ===========================================================================
  // QUERIES
  // ===========================================================================

  /// Which nodes depend on [assetId]?
  Set<String> nodesUsing(String assetId) =>
      Set.unmodifiable(_assetToNodes[assetId] ?? const {});

  /// Which assets does [nodeId] depend on?
  Set<String> assetsUsedBy(String nodeId) =>
      Set.unmodifiable(_nodeToAssets[nodeId] ?? const {});

  /// All asset IDs that have at least one node reference.
  Set<String> get referencedAssets =>
      Set.unmodifiable(_assetToNodes.keys.toSet());

  /// All asset IDs with zero node references (candidates for cleanup).
  Set<String> orphanedAssets(Set<String> allKnownAssetIds) =>
      allKnownAssetIds.difference(referencedAssets);

  /// Total number of node→asset links.
  int get linkCount => _nodeToAssets.values.fold(0, (sum, s) => sum + s.length);

  /// Total number of tracked nodes.
  int get nodeCount => _nodeToAssets.length;

  /// Total number of tracked assets.
  int get assetCount => _assetToNodes.length;

  // ===========================================================================
  // BROKEN LINK DETECTION
  // ===========================================================================

  /// Find all broken links by checking asset IDs against a set of
  /// known valid asset IDs and their states.
  ///
  /// [assetStates] maps asset IDs to their current [AssetState].
  /// Any referenced asset ID not in the map is considered missing.
  List<BrokenLink> findBrokenLinks(Map<String, AssetState> assetStates) {
    final broken = <BrokenLink>[];

    for (final entry in _nodeToAssets.entries) {
      final nodeId = entry.key;
      for (final assetId in entry.value) {
        final state = assetStates[assetId];
        if (state == null) {
          broken.add(
            BrokenLink(
              nodeId: nodeId,
              assetId: assetId,
              reason: BrokenLinkReason.missing,
            ),
          );
        } else if (state == AssetState.error) {
          broken.add(
            BrokenLink(
              nodeId: nodeId,
              assetId: assetId,
              reason: BrokenLinkReason.error,
            ),
          );
        } else if (state == AssetState.disposed) {
          broken.add(
            BrokenLink(
              nodeId: nodeId,
              assetId: assetId,
              reason: BrokenLinkReason.disposed,
            ),
          );
        } else if (state == AssetState.evicted) {
          broken.add(
            BrokenLink(
              nodeId: nodeId,
              assetId: assetId,
              reason: BrokenLinkReason.evicted,
            ),
          );
        }
      }
    }

    return broken;
  }

  // ===========================================================================
  // SERIALIZATION
  // ===========================================================================

  /// Serialize the graph to JSON.
  Map<String, dynamic> toJson() => {
    'links': [
      for (final entry in _nodeToAssets.entries)
        for (final assetId in entry.value)
          {'nodeId': entry.key, 'assetId': assetId},
    ],
  };

  /// Deserialize from JSON.
  factory AssetDependencyGraph.fromJson(Map<String, dynamic> json) {
    final graph = AssetDependencyGraph();
    final links = json['links'] as List?;
    if (links != null) {
      for (final link in links) {
        final map = link as Map<String, dynamic>;
        graph.link(map['nodeId'] as String, map['assetId'] as String);
      }
    }
    return graph;
  }

  // ===========================================================================
  // LIFECYCLE
  // ===========================================================================

  /// Clear all tracked links.
  void clear() {
    _nodeToAssets.clear();
    _assetToNodes.clear();
  }

  /// Dispose the graph.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    clear();
  }

  /// Whether this graph has been disposed.
  bool get isDisposed => _disposed;

  @override
  String toString() =>
      'AssetDependencyGraph(nodes=$nodeCount, '
      'assets=$assetCount, links=$linkCount)';
}
