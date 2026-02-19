import 'dart:ui' as ui;
import '../scene_graph/canvas_node.dart';
import '../scene_graph/node_visitor.dart';
import '../vector/vector_network.dart';
import '../effects/gradient_fill.dart';

/// Scene graph node that wraps a [VectorNetwork] for rendering.
///
/// Unlike [PathNode] which uses a linear [VectorPath], this node uses
/// a graph-based model where vertices can have any number of connected
/// edges. This enables complex topologies like T-junctions and forks.
///
/// Each region in the network can have its own fill color/gradient.
/// The global stroke applies to all segments.
///
/// ```
/// VectorNetworkNode (star with cross)
///   network: VectorNetwork (5 vertices, 8 segments, 2 regions)
///   regionFills: [RegionFill(color: gold), RegionFill(color: silver)]
///   strokeColor: Colors.black
///   strokeWidth: 2.0
/// ```
class VectorNetworkNode extends CanvasNode {
  /// The underlying vector network graph.
  VectorNetwork network;

  /// Per-region fill overrides.
  ///
  /// If a region index has a [RegionFill], that fill is used.
  /// Otherwise [fillColor] / [fillGradient] is used as fallback.
  List<RegionFill> regionFills;

  /// Default fill color for regions without a specific [RegionFill].
  ui.Color? fillColor;

  /// Default fill gradient for regions without a specific [RegionFill].
  GradientFill? fillGradient;

  /// Stroke color for all segments (null = no stroke).
  ui.Color? strokeColor;

  /// Stroke gradient for all segments.
  GradientFill? strokeGradient;

  /// Stroke width.
  double strokeWidth;

  /// Stroke cap style.
  ui.StrokeCap strokeCap;

  /// Stroke join style.
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
  }) : regionFills = regionFills ?? [];

  @override
  ui.Rect get localBounds {
    final networkBounds = network.computeBounds();
    if (networkBounds.isEmpty) return ui.Rect.zero;
    return networkBounds.inflate(strokeWidth / 2);
  }

  @override
  Map<String, dynamic> toJson() {
    final json = baseToJson();
    json['nodeType'] = 'vector_network';
    json['network'] = network.toJson();
    json['strokeWidth'] = strokeWidth;
    json['strokeCap'] = strokeCap.index;
    json['strokeJoin'] = strokeJoin.index;

    if (fillColor != null) json['fillColor'] = fillColor!.toARGB32();
    if (fillGradient != null) json['fillGradient'] = fillGradient!.toJson();
    if (strokeColor != null) json['strokeColor'] = strokeColor!.toARGB32();
    if (strokeGradient != null) {
      json['strokeGradient'] = strokeGradient!.toJson();
    }
    if (regionFills.isNotEmpty) {
      json['regionFills'] = regionFills.map((r) => r.toJson()).toList();
    }

    return json;
  }

  factory VectorNetworkNode.fromJson(Map<String, dynamic> json) {
    final node = VectorNetworkNode(
      id: json['id'] as String,
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
    return node;
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
