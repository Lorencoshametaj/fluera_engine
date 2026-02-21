import '../../core/models/canvas_layer.dart';

/// 🔀 Result of a 3-way branch merge operation.
///
/// Contains the merged layers, any conflicts detected, and the strategy used.
/// The caller can inspect [conflicts] to decide whether to:
/// - Accept the default resolution (source/feature branch wins)
/// - Show a UI for the user to resolve manually
/// - Reject the merge entirely
class BranchMergeResult {
  /// The merged layer set (null if merge was rejected, e.g. self-merge).
  final List<CanvasLayer>? mergedLayers;

  /// Layers that both branches modified — requires user decision.
  ///
  /// Empty list = clean merge, no conflicts.
  final List<LayerMergeConflict> conflicts;

  /// Human-readable description of the merge strategy used.
  ///
  /// Examples:
  /// - `'3-way merge: clean'`
  /// - `'3-way merge: 2 conflict(s)'`
  /// - `'fallback: theirs-wins (no common ancestor)'`
  /// - `'rejected: self-merge'`
  final String strategy;

  BranchMergeResult({
    required this.mergedLayers,
    required this.conflicts,
    required this.strategy,
  });

  /// Whether the merge completed without conflicts.
  bool get isClean => conflicts.isEmpty && mergedLayers != null;

  /// Whether the merge has unresolved conflicts.
  bool get hasConflicts => conflicts.isNotEmpty;

  @override
  String toString() =>
      'BranchMergeResult($strategy, '
      '${mergedLayers?.length ?? 0} layers, '
      '${conflicts.length} conflicts)';
}

/// 🔀 A single layer-level merge conflict.
///
/// Occurs when both the source and target branches modified the same layer
/// (identified by layer ID) relative to their common ancestor.
class LayerMergeConflict {
  /// The layer ID that is in conflict.
  final String layerId;

  /// The source branch's version of this layer.
  final CanvasLayer sourceLayer;

  /// The target branch's version of this layer.
  final CanvasLayer targetLayer;

  /// The common ancestor's version (null if the layer didn't exist in base).
  final CanvasLayer? baseLayer;

  LayerMergeConflict({
    required this.layerId,
    required this.sourceLayer,
    required this.targetLayer,
    this.baseLayer,
  });

  @override
  String toString() =>
      'LayerMergeConflict($layerId, '
      'source: ${sourceLayer.elementCount} elements, '
      'target: ${targetLayer.elementCount} elements)';
}
