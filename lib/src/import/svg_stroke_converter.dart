import 'dart:ui' as ui;

import '../drawing/models/pro_drawing_point.dart';
import '../drawing/models/pro_brush_settings.dart';
import '../export/svg_importer.dart';
import '../core/nodes/group_node.dart';
import '../core/nodes/path_node.dart';
import '../core/scene_graph/canvas_node.dart';
import '../utils/uid.dart';

/// Converts SVG path elements into [ProStroke] objects by sampling points
/// along each path using Flutter's [PathMetrics].
///
/// Reuses [SvgImporter] for parsing, then walks the resulting node tree
/// to extract [PathNode]s and sample their vector paths.
class SvgStrokeConverter {
  const SvgStrokeConverter._();

  /// Parse an SVG string and convert all path elements to [ProStroke].
  ///
  /// [offset] shifts all stroke coordinates for canvas placement.
  /// [defaultColor] is used when the SVG element has no stroke color.
  /// [samplingInterval] controls the distance between sampled points (pixels).
  static List<ProStroke> convert(
    String svgContent, {
    ui.Offset offset = ui.Offset.zero,
    ui.Color defaultColor = const ui.Color(0xFF000000),
    double samplingInterval = 4.0,
  }) {
    final importer = SvgImporter();
    final rootNode = importer.parse(svgContent);

    final strokes = <ProStroke>[];
    final now = DateTime.now();

    _collectStrokes(
      rootNode,
      strokes,
      now,
      offset,
      defaultColor,
      samplingInterval,
    );

    return strokes;
  }

  static void _collectStrokes(
    CanvasNode node,
    List<ProStroke> strokes,
    DateTime now,
    ui.Offset offset,
    ui.Color defaultColor,
    double samplingInterval,
  ) {
    if (node is PathNode) {
      final stroke = _pathNodeToStroke(
        node,
        now,
        offset,
        defaultColor,
        samplingInterval,
      );
      if (stroke != null) strokes.add(stroke);
    }

    if (node is GroupNode) {
      for (final child in node.children) {
        _collectStrokes(
          child,
          strokes,
          now,
          offset,
          defaultColor,
          samplingInterval,
        );
      }
    }
  }

  static ProStroke? _pathNodeToStroke(
    PathNode node,
    DateTime now,
    ui.Offset offset,
    ui.Color defaultColor,
    double samplingInterval,
  ) {
    final flutterPath = node.path.toFlutterPath();
    final points = _samplePath(flutterPath, offset, samplingInterval);
    if (points.length < 2) return null;

    // Use the SVG stroke color, falling back to fill, then default
    // ignore: deprecated_member_use
    final color = node.strokeColor ?? node.fillColor ?? defaultColor;
    // ignore: deprecated_member_use
    final width = node.strokeWidth > 0 ? node.strokeWidth : 2.0;

    return ProStroke(
      id: generateUid(),
      points: points,
      color: color,
      baseWidth: width,
      penType: ProPenType.ballpoint,
      createdAt: now,
      settings: const ProBrushSettings(),
    );
  }

  /// Sample points along a Flutter [Path] at regular intervals.
  static List<ProDrawingPoint> _samplePath(
    ui.Path path,
    ui.Offset offset,
    double interval,
  ) {
    final points = <ProDrawingPoint>[];
    final baseTimestamp = DateTime.now().millisecondsSinceEpoch;
    int pointIndex = 0;

    for (final metric in path.computeMetrics()) {
      for (double d = 0; d <= metric.length; d += interval) {
        final tangent = metric.getTangentForOffset(d);
        if (tangent == null) continue;
        points.add(ProDrawingPoint(
          position: tangent.position + offset,
          pressure: 1.0, // Uniform — SVG has no pressure data
          timestamp: baseTimestamp + pointIndex,
        ));
        pointIndex++;
      }

      // Always include the endpoint
      final lastTangent = metric.getTangentForOffset(metric.length);
      if (lastTangent != null && points.isNotEmpty) {
        final lastPos = points.last.position;
        final endPos = lastTangent.position + offset;
        if ((lastPos - endPos).distance > 0.5) {
          points.add(ProDrawingPoint(
            position: endPos,
            pressure: 1.0,
            timestamp: baseTimestamp + pointIndex,
          ));
          pointIndex++;
        }
      }
    }

    return points;
  }
}
