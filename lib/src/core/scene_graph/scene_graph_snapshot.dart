import 'canvas_node.dart';
import '../nodes/group_node.dart';
import 'scene_graph.dart';

// ---------------------------------------------------------------------------
// DiffEntry
// ---------------------------------------------------------------------------

/// Type of change detected between two snapshots.
enum DiffType {
  /// Node exists in the new snapshot but not the old.
  added,

  /// Node exists in the old snapshot but not the new.
  removed,

  /// Node exists in both but its content hash changed.
  modified,

  /// Node exists in both but its parent changed (moved in tree).
  moved,
}

/// A single difference between two [SceneGraphSnapshot]s.
class DiffEntry {
  /// The node ID this diff refers to.
  final String nodeId;

  /// The type of change.
  final DiffType type;

  /// Node name (for display purposes).
  final String? nodeName;

  /// Previous parent ID (for [DiffType.moved]).
  final String? oldParentId;

  /// New parent ID (for [DiffType.moved]).
  final String? newParentId;

  /// Previous content hash (for [DiffType.modified]).
  final int? oldHash;

  /// New content hash (for [DiffType.modified]).
  final int? newHash;

  const DiffEntry({
    required this.nodeId,
    required this.type,
    this.nodeName,
    this.oldParentId,
    this.newParentId,
    this.oldHash,
    this.newHash,
  });

  @override
  String toString() {
    switch (type) {
      case DiffType.added:
        return '+ $nodeId (${nodeName ?? "?"})';
      case DiffType.removed:
        return '- $nodeId (${nodeName ?? "?"})';
      case DiffType.modified:
        return '~ $nodeId (${nodeName ?? "?"})';
      case DiffType.moved:
        return '→ $nodeId: $oldParentId → $newParentId';
    }
  }

  Map<String, dynamic> toJson() => {
    'nodeId': nodeId,
    'type': type.name,
    if (nodeName != null) 'name': nodeName,
    if (oldParentId != null) 'oldParent': oldParentId,
    if (newParentId != null) 'newParent': newParentId,
    if (oldHash != null) 'oldHash': oldHash,
    if (newHash != null) 'newHash': newHash,
  };
}

// ---------------------------------------------------------------------------
// SceneGraphDiff
// ---------------------------------------------------------------------------

/// Structural diff between two [SceneGraphSnapshot]s.
class SceneGraphDiff {
  /// All detected differences.
  final List<DiffEntry> entries;

  /// Version of the old snapshot.
  final int oldVersion;

  /// Version of the new snapshot.
  final int newVersion;

  const SceneGraphDiff({
    required this.entries,
    required this.oldVersion,
    required this.newVersion,
  });

  /// Whether the two snapshots are identical.
  bool get isEmpty => entries.isEmpty;

  /// Number of differences.
  int get length => entries.length;

  /// Only additions.
  List<DiffEntry> get additions =>
      entries.where((e) => e.type == DiffType.added).toList();

  /// Only removals.
  List<DiffEntry> get removals =>
      entries.where((e) => e.type == DiffType.removed).toList();

  /// Only modifications.
  List<DiffEntry> get modifications =>
      entries.where((e) => e.type == DiffType.modified).toList();

  /// Only moves.
  List<DiffEntry> get moves =>
      entries.where((e) => e.type == DiffType.moved).toList();

  /// Human-readable summary.
  String get summary =>
      '${additions.length} added, ${removals.length} removed, '
      '${modifications.length} modified, ${moves.length} moved';

  Map<String, dynamic> toJson() => {
    'oldVersion': oldVersion,
    'newVersion': newVersion,
    'summary': summary,
    'entries': entries.map((e) => e.toJson()).toList(),
  };

  @override
  String toString() => 'SceneGraphDiff(v$oldVersion → v$newVersion: $summary)';
}

// ---------------------------------------------------------------------------
// _NodeSnapshot — internal per-node state capture
// ---------------------------------------------------------------------------

class _NodeSnapshot {
  final String nodeId;
  final String name;
  final String? parentId;
  final int contentHash;

  const _NodeSnapshot({
    required this.nodeId,
    required this.name,
    required this.parentId,
    required this.contentHash,
  });
}

// ---------------------------------------------------------------------------
// SceneGraphSnapshot
// ---------------------------------------------------------------------------

/// Lightweight immutable snapshot of a [SceneGraph]'s structure.
///
/// Captures node IDs, parent relationships, and content hashes —
/// but **not** the full node data. This makes snapshots cheap to
/// create and compare.
///
/// ```dart
/// final a = SceneGraphSnapshot.capture(sceneGraph);
/// // ... mutations ...
/// final b = SceneGraphSnapshot.capture(sceneGraph);
/// final diff = a.diff(b);
/// print(diff.summary); // "2 added, 0 removed, 1 modified, 0 moved"
/// ```
class SceneGraphSnapshot {
  /// SceneGraph version at capture time.
  final int version;

  /// Timestamp of capture.
  final DateTime timestamp;

  /// Per-node snapshots indexed by node ID.
  final Map<String, _NodeSnapshot> _nodes;

  SceneGraphSnapshot._({
    required this.version,
    required this.timestamp,
    required Map<String, _NodeSnapshot> nodes,
  }) : _nodes = nodes;

  /// Capture a snapshot of the current scene graph state.
  factory SceneGraphSnapshot.capture(SceneGraph graph) {
    final nodes = <String, _NodeSnapshot>{};
    _captureNode(graph.rootNode, null, nodes);
    return SceneGraphSnapshot._(
      version: graph.version,
      timestamp: DateTime.now(),
      nodes: Map.unmodifiable(nodes),
    );
  }

  static void _captureNode(
    CanvasNode node,
    String? parentId,
    Map<String, _NodeSnapshot> out,
  ) {
    out[node.id] = _NodeSnapshot(
      nodeId: node.id,
      name: node.name,
      parentId: parentId,
      contentHash: _computeHash(node),
    );
    if (node is GroupNode) {
      for (final child in node.children) {
        _captureNode(child, node.id, out);
      }
    }
  }

  /// Compute a lightweight content hash for a node using FNV-1a.
  ///
  /// FNV-1a produces better distribution than naive `h * 31` chains,
  /// reducing false-negative diffs in large scene graphs.
  static int _computeHash(CanvasNode node) {
    // FNV-1a 32-bit hash (JS-safe — no 64-bit literals).
    var h = 0x811c9dc5;
    void _mix(int v) {
      h ^= v;
      h = (h * 0x01000193) & 0x7FFFFFFF;
    }

    _mix(node.name.hashCode);
    _mix(node.isVisible.hashCode);
    _mix(node.opacity.hashCode);
    _mix(node.isLocked.hashCode);
    _mix(node.localTransform.hashCode);
    _mix(node.contentFingerprint);
    return h;
  }

  /// Number of nodes in the snapshot.
  int get nodeCount => _nodes.length;

  /// All node IDs in the snapshot.
  Set<String> get nodeIds => _nodes.keys.toSet();

  // -------------------------------------------------------------------------
  // Diffing
  // -------------------------------------------------------------------------

  /// Compute the structural diff from `this` (old) to [other] (new).
  SceneGraphDiff diff(SceneGraphSnapshot other) {
    final entries = <DiffEntry>[];

    final oldIds = _nodes.keys.toSet();
    final newIds = other._nodes.keys.toSet();

    // Additions.
    for (final id in newIds.difference(oldIds)) {
      final n = other._nodes[id]!;
      entries.add(
        DiffEntry(
          nodeId: id,
          type: DiffType.added,
          nodeName: n.name,
          newParentId: n.parentId,
        ),
      );
    }

    // Removals.
    for (final id in oldIds.difference(newIds)) {
      final n = _nodes[id]!;
      entries.add(
        DiffEntry(
          nodeId: id,
          type: DiffType.removed,
          nodeName: n.name,
          oldParentId: n.parentId,
        ),
      );
    }

    // Modifications & moves.
    for (final id in oldIds.intersection(newIds)) {
      final oldNode = _nodes[id]!;
      final newNode = other._nodes[id]!;

      // Check for parent change (move).
      if (oldNode.parentId != newNode.parentId) {
        entries.add(
          DiffEntry(
            nodeId: id,
            type: DiffType.moved,
            nodeName: newNode.name,
            oldParentId: oldNode.parentId,
            newParentId: newNode.parentId,
          ),
        );
      }

      // Check for content change.
      if (oldNode.contentHash != newNode.contentHash) {
        entries.add(
          DiffEntry(
            nodeId: id,
            type: DiffType.modified,
            nodeName: newNode.name,
            oldHash: oldNode.contentHash,
            newHash: newNode.contentHash,
          ),
        );
      }
    }

    return SceneGraphDiff(
      entries: entries,
      oldVersion: version,
      newVersion: other.version,
    );
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'timestamp': timestamp.toIso8601String(),
    'nodeCount': nodeCount,
  };
}
