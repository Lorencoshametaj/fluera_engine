import 'dart:ui' as ui;
import '../scene_graph/canvas_node.dart';
import '../scene_graph/node_id.dart';
import '../scene_graph/node_visitor.dart';
import '../vector/vector_path.dart';
import '../vector/boolean_ops.dart';
import '../effects/gradient_fill.dart';
import './group_node.dart';

/// Non-destructive boolean group — like Figma's Boolean Groups.
///
/// Contains children that are combined using the specified [operation].
/// The result is lazily computed and cached. Children remain editable
/// as individual nodes.
///
/// ```
/// BooleanGroupNode (union)
///   ├── PathNode (circle)
///   └── PathNode (rectangle)
///   → computedPath: merged outline
/// ```
class BooleanGroupNode extends GroupNode {
  /// Which boolean operation to apply (union, subtract, intersect, exclude).
  BooleanOpType operation;

  /// Fill color applied to the computed boolean result.
  ui.Color? fillColor;

  /// Fill gradient (overrides [fillColor] if set).
  GradientFill? fillGradient;

  /// Stroke color applied to the computed outline.
  ui.Color? strokeColor;

  /// Stroke gradient (overrides [strokeColor] if set).
  GradientFill? strokeGradient;

  /// Stroke width for the outline.
  double strokeWidth;

  /// Stroke cap style.
  ui.StrokeCap strokeCap;

  /// Stroke join style.
  ui.StrokeJoin strokeJoin;

  // ---- Caching ----
  VectorPath? _cachedPath;
  bool _dirty = true;

  BooleanGroupNode({
    required super.id,
    required this.operation,
    super.name = '',
    super.localTransform,
    super.opacity,
    super.blendMode,
    super.isVisible,
    super.isLocked,
    this.fillColor,
    this.fillGradient,
    this.strokeColor,
    this.strokeGradient,
    this.strokeWidth = 2.0,
    this.strokeCap = ui.StrokeCap.round,
    this.strokeJoin = ui.StrokeJoin.round,
  });

  // ---------------------------------------------------------------------------
  // Computed path (lazy, cached)
  // ---------------------------------------------------------------------------

  /// The boolean-combined path from all children.
  ///
  /// Computed lazily on first access and cached until invalidated.
  /// Returns an empty path if there are no valid children.
  VectorPath get computedPath {
    if (!_dirty && _cachedPath != null) return _cachedPath!;
    _cachedPath = _computeBooleanResult();
    _dirty = false;
    return _cachedPath!;
  }

  /// Whether this group needs recomputation.
  bool get needsRecompute => _dirty;

  /// Mark the boolean result as stale and needing recomputation.
  void invalidate() {
    _dirty = true;
    _cachedPath = null;
  }

  // ---------------------------------------------------------------------------
  // Child management (override to invalidate cache)
  // ---------------------------------------------------------------------------

  @override
  void add(CanvasNode child) {
    super.add(child);
    invalidate();
  }

  @override
  bool remove(CanvasNode child) {
    final removed = super.remove(child);
    if (removed) invalidate();
    return removed;
  }

  // ---------------------------------------------------------------------------
  // Bounds
  // ---------------------------------------------------------------------------

  @override
  ui.Rect get localBounds {
    final pathBounds = computedPath.computeBounds();
    if (pathBounds.isEmpty) return ui.Rect.zero;
    return pathBounds.inflate(strokeWidth / 2);
  }

  // ---------------------------------------------------------------------------
  // Boolean computation
  // ---------------------------------------------------------------------------

  VectorPath _computeBooleanResult() {
    // Collect VectorPaths from children.
    final paths = <VectorPath>[];
    for (final child in children) {
      final vp = BooleanOps.nodeToVectorPath(child);
      if (vp != null) paths.add(vp);
    }

    if (paths.isEmpty) return VectorPath(segments: []);
    if (paths.length == 1) return paths.first;

    // Chain the operation across all paths.
    return BooleanOps.multiExecute(operation, paths);
  }

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  @override
  Map<String, dynamic> toJson() {
    final json = baseToJson();
    json['nodeType'] = 'booleanGroup';
    json['operation'] = operation.name;
    json['strokeWidth'] = strokeWidth;
    json['strokeCap'] = strokeCap.index;
    json['strokeJoin'] = strokeJoin.index;

    if (fillColor != null) json['fillColor'] = fillColor!.toARGB32();
    if (fillGradient != null) json['fillGradient'] = fillGradient!.toJson();
    if (strokeColor != null) json['strokeColor'] = strokeColor!.toARGB32();
    if (strokeGradient != null) {
      json['strokeGradient'] = strokeGradient!.toJson();
    }

    // Serialize children.
    json['children'] = children.map((c) => c.toJson()).toList();

    return json;
  }

  factory BooleanGroupNode.fromJson(Map<String, dynamic> json) {
    final node = BooleanGroupNode(
      id: NodeId(json['id'] as String),
      operation: BooleanOpType.values.firstWhere(
        (e) => e.name == json['operation'],
        orElse: () => BooleanOpType.union,
      ),
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 2.0,
      strokeCap:
          json['strokeCap'] != null
              ? ui.StrokeCap.values[json['strokeCap'] as int]
              : ui.StrokeCap.round,
      strokeJoin:
          json['strokeJoin'] != null
              ? ui.StrokeJoin.values[json['strokeJoin'] as int]
              : ui.StrokeJoin.round,
      fillColor:
          json['fillColor'] != null
              ? ui.Color((json['fillColor'] as int).toUnsigned(32))
              : null,
      fillGradient:
          json['fillGradient'] != null
              ? GradientFill.fromJson(
                json['fillGradient'] as Map<String, dynamic>,
              )
              : null,
      strokeColor:
          json['strokeColor'] != null
              ? ui.Color((json['strokeColor'] as int).toUnsigned(32))
              : null,
      strokeGradient:
          json['strokeGradient'] != null
              ? GradientFill.fromJson(
                json['strokeGradient'] as Map<String, dynamic>,
              )
              : null,
    );
    CanvasNode.applyBaseFromJson(node, json);
    // Children are loaded via canvas_node_factory dispatch.
    return node;
  }

  // ---------------------------------------------------------------------------
  // Visitor
  // ---------------------------------------------------------------------------

  @override
  R accept<R>(NodeVisitor<R> visitor) => visitor.visitBooleanGroup(this);
}
