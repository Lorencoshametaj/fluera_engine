import 'dart:ui' as ui;
import '../scene_graph/canvas_node.dart';
import '../scene_graph/node_id.dart';
import '../scene_graph/node_visitor.dart';
import '../scene_graph/paint_stack_mixin.dart';
import '../vector/vector_network.dart';
import '../effects/gradient_fill.dart';
import '../effects/paint_stack.dart';

/// Scene graph node that wraps a [VectorNetwork] for rendering.
///
/// Unlike [PathNode] which uses a linear [VectorPath], this node uses
/// a graph-based model where vertices can have any number of connected
/// edges. This enables complex topologies like T-junctions and forks.
///
/// Supports stacked fills and strokes via [PaintStackMixin].
/// Each region in the network can also have its own per-region fill
/// override via [regionFills].
///
/// ```
/// VectorNetworkNode (star with cross)
///   network: VectorNetwork (5 vertices, 8 segments, 2 regions)
///   regionFills: [RegionFill(color: gold), RegionFill(color: silver)]
///   fills: [FillLayer.solid(color: Colors.blue)]
///   strokes: [StrokeLayer(color: Colors.black, width: 2.0)]
/// ```
class VectorNetworkNode extends CanvasNode with PaintStackMixin {
  /// The underlying vector network graph.
  VectorNetwork network;

  /// Per-region fill overrides.
  ///
  /// If a region index has a [RegionFill], that fill is used.
  /// Otherwise the node-level fill stack (or legacy fallback) is used.
  List<RegionFill> regionFills;

  /// Default fill color — **deprecated**, use [fills] instead.
  @Deprecated('Use fills list from PaintStackMixin instead')
  ui.Color? fillColor;

  /// Default fill gradient — **deprecated**, use [fills] instead.
  @Deprecated('Use fills list from PaintStackMixin instead')
  GradientFill? fillGradient;

  /// Stroke color — **deprecated**, use [strokes] instead.
  @Deprecated('Use strokes list from PaintStackMixin instead')
  ui.Color? strokeColor;

  /// Stroke gradient — **deprecated**, use [strokes] instead.
  @Deprecated('Use strokes list from PaintStackMixin instead')
  GradientFill? strokeGradient;

  /// Stroke width — **deprecated**, use [strokes] instead.
  @Deprecated('Use strokes list from PaintStackMixin instead')
  double strokeWidth;

  /// Stroke cap — **deprecated**, use [strokes] instead.
  @Deprecated('Use strokes list from PaintStackMixin instead')
  ui.StrokeCap strokeCap;

  /// Stroke join — **deprecated**, use [strokes] instead.
  @Deprecated('Use strokes list from PaintStackMixin instead')
  ui.StrokeJoin strokeJoin;

  VectorNetworkNode({
    required super.id,
    required this.network,
    super.name = '',
    super.localTransform,
    super.opacity,
    super.blendMode,
    super.isVisible,
    super.isLocked,
    List<RegionFill>? regionFills,
    this.fillColor,
    this.fillGradient,
    this.strokeColor,
    this.strokeGradient,
    this.strokeWidth = 2.0,
    this.strokeCap = ui.StrokeCap.round,
    this.strokeJoin = ui.StrokeJoin.round,
    List<FillLayer>? fills,
    List<StrokeLayer>? strokes,
  }) : regionFills = regionFills ?? [] {
    if (fills != null) this.fills = fills;
    if (strokes != null) this.strokes = strokes;
  }

  @override
  ui.Rect get localBounds {
    final networkBounds = network.computeBounds();
    if (networkBounds.isEmpty) return ui.Rect.zero;
    final inflation =
        // ignore: deprecated_member_use_from_same_package
        strokes.isNotEmpty ? maxStrokeBoundsInflation : strokeWidth / 2;
    return networkBounds.inflate(inflation);
  }

  @override
  Map<String, dynamic> toJson() {
    final json = baseToJson();
    json['nodeType'] = 'vector_network';
    json['network'] = network.toJson();

    // Paint stack (new format).
    json.addAll(paintStackToJson());

    // Per-region fills (stays separate from stacking).
    if (regionFills.isNotEmpty) {
      json['regionFills'] = regionFills.map((r) => r.toJson()).toList();
    }

    // Legacy fields — only if stack is empty.
    if (fills.isEmpty) {
      // ignore: deprecated_member_use_from_same_package
      json['strokeWidth'] = strokeWidth;
      // ignore: deprecated_member_use_from_same_package
      json['strokeCap'] = strokeCap.index;
      // ignore: deprecated_member_use_from_same_package
      json['strokeJoin'] = strokeJoin.index;
      // ignore: deprecated_member_use_from_same_package
      if (fillColor != null) json['fillColor'] = fillColor!.toARGB32();
      // ignore: deprecated_member_use_from_same_package
      if (fillGradient != null) json['fillGradient'] = fillGradient!.toJson();
      // ignore: deprecated_member_use_from_same_package
      if (strokeColor != null) json['strokeColor'] = strokeColor!.toARGB32();
      // ignore: deprecated_member_use_from_same_package
      if (strokeGradient != null) {
        // ignore: deprecated_member_use_from_same_package
        json['strokeGradient'] = strokeGradient!.toJson();
      }
    }

    return json;
  }

  factory VectorNetworkNode.fromJson(Map<String, dynamic> json) {
    final node = VectorNetworkNode(
      id: NodeId(json['id'] as String),
      network: VectorNetwork.fromJson(json['network'] as Map<String, dynamic>),
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
      regionFills:
          json['regionFills'] != null
              ? (json['regionFills'] as List)
                  .map((r) => RegionFill.fromJson(r as Map<String, dynamic>))
                  .toList()
              : [],
    );
    CanvasNode.applyBaseFromJson(node, json);

    // Paint stack — new format has priority.
    if (json.containsKey('fills') || json.containsKey('strokes')) {
      PaintStackMixin.applyPaintStackFromJson(node, json);
    } else {
      _migrateLegacyPaintStack(node);
    }

    return node;
  }

  /// Migrate legacy single fill/stroke into the paint stack.
  static void _migrateLegacyPaintStack(VectorNetworkNode node) {
    // ignore: deprecated_member_use_from_same_package
    if (node.fillGradient != null) {
      // ignore: deprecated_member_use_from_same_package
      node.fills.add(FillLayer.fromGradient(gradient: node.fillGradient!));
      // ignore: deprecated_member_use_from_same_package
    } else if (node.fillColor != null) {
      // ignore: deprecated_member_use_from_same_package
      node.fills.add(FillLayer.solid(color: node.fillColor!));
    }
    // ignore: deprecated_member_use_from_same_package
    if (node.strokeColor != null || node.strokeGradient != null) {
      node.strokes.add(
        StrokeLayer(
          // ignore: deprecated_member_use_from_same_package
          color: node.strokeColor,
          // ignore: deprecated_member_use_from_same_package
          gradient: node.strokeGradient,
          // ignore: deprecated_member_use_from_same_package
          width: node.strokeWidth,
          // ignore: deprecated_member_use_from_same_package
          cap: node.strokeCap,
          // ignore: deprecated_member_use_from_same_package
          join: node.strokeJoin,
        ),
      );
    }
  }

  @override
  R accept<R>(NodeVisitor<R> visitor) => visitor.visitVectorNetwork(this);
}

// ---------------------------------------------------------------------------
// RegionFill — per-region fill override
// ---------------------------------------------------------------------------

/// Fill specification for a single region.
class RegionFill {
  /// Region index in the [VectorNetwork.regions] list.
  final int regionIndex;

  /// Fill color (null = use node's default).
  ui.Color? color;

  /// Fill gradient (null = use node's default or [color]).
  GradientFill? gradient;

  RegionFill({required this.regionIndex, this.color, this.gradient});

  Map<String, dynamic> toJson() => {
    'regionIndex': regionIndex,
    if (color != null) 'color': color!.toARGB32(),
    if (gradient != null) 'gradient': gradient!.toJson(),
  };

  factory RegionFill.fromJson(Map<String, dynamic> json) {
    return RegionFill(
      regionIndex: json['regionIndex'] as int,
      color:
          json['color'] != null
              ? ui.Color((json['color'] as int).toUnsigned(32))
              : null,
      gradient:
          json['gradient'] != null
              ? GradientFill.fromJson(json['gradient'] as Map<String, dynamic>)
              : null,
    );
  }
}
