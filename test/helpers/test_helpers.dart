import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:fluera_engine/src/core/scene_graph/canvas_node.dart';
import 'package:fluera_engine/src/core/scene_graph/node_id.dart';
import 'package:fluera_engine/src/core/nodes/group_node.dart';
import 'package:fluera_engine/src/core/nodes/layer_node.dart';
import 'package:fluera_engine/src/core/nodes/stroke_node.dart';
import 'package:fluera_engine/src/core/nodes/shape_node.dart';
import 'package:fluera_engine/src/drawing/models/pro_drawing_point.dart';
import 'package:fluera_engine/src/drawing/models/pro_brush_settings.dart';
import 'package:fluera_engine/src/core/models/shape_type.dart';

// ---------------------------------------------------------------------------
// Test helpers — reusable across all test files
// ---------------------------------------------------------------------------

/// Create a minimal [ProStroke] for testing.
ProStroke testStroke({
  String id = 'stroke-1',
  int pointCount = 5,
  Color color = Colors.black,
  double baseWidth = 2.0,
  ProPenType penType = ProPenType.ballpoint,
}) {
  final points = List.generate(
    pointCount,
    (i) => ProDrawingPoint(
      position: Offset(i * 10.0, i * 10.0),
      pressure: 0.5,
      timestamp: i * 16,
    ),
  );
  return ProStroke(
    id: id,
    points: points,
    color: color,
    baseWidth: baseWidth,
    penType: penType,
    createdAt: DateTime(2025, 1, 1),
  );
}

/// Create a minimal [GeometricShape] for testing.
GeometricShape testShape({
  String id = 'shape-1',
  ShapeType type = ShapeType.rectangle,
  Offset start = const Offset(0, 0),
  Offset end = const Offset(100, 100),
  Color color = Colors.red,
  double strokeWidth = 2.0,
}) {
  return GeometricShape(
    id: id,
    type: type,
    startPoint: start,
    endPoint: end,
    color: color,
    strokeWidth: strokeWidth,
    createdAt: DateTime(2025, 1, 1),
  );
}

/// Create a [StrokeNode] for testing.
StrokeNode testStrokeNode({String id = 'sn-1'}) {
  return StrokeNode(id: NodeId(id), stroke: testStroke(id: id));
}

/// Create a [ShapeNode] for testing.
ShapeNode testShapeNode({String id = 'sh-1'}) {
  return ShapeNode(id: NodeId(id), shape: testShape(id: id));
}

/// Create a [GroupNode] with optional children.
GroupNode testGroupNode({String id = 'grp-1', List<CanvasNode>? children}) {
  final group = GroupNode(id: NodeId(id));
  if (children != null) {
    for (final child in children) {
      group.add(child);
    }
  }
  return group;
}

/// Create a [LayerNode] with optional children.
LayerNode testLayerNode({String id = 'layer-1', List<CanvasNode>? children}) {
  final layer = LayerNode(id: NodeId(id));
  if (children != null) {
    for (final child in children) {
      layer.add(child);
    }
  }
  return layer;
}
