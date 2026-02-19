import 'dart:ui';
import '../../core/nodes/vector_network_node.dart';
import '../../core/vector/vector_network.dart';

/// Renders a [VectorNetworkNode] to a [Canvas].
///
/// Handles per-region fills, per-segment stroke overrides, and global stroke.
/// Uses a revision counter to cache built [Path] objects.
class VectorNetworkRenderer {
  VectorNetworkRenderer._();

  // Cached stroke path + revision for invalidation.
  static Path? _cachedStrokePath;
  static int _cachedStrokeRevision = -1;
  static String? _cachedStrokeNetworkId;

  // Cached region paths.
  static final Map<String, (int revision, Map<int, Path> paths)>
  _cachedRegionPaths = {};

  /// Draw the vector network node's regions (fills) and segments (stroke).
  static void drawVectorNetworkNode(Canvas canvas, VectorNetworkNode node) {
    final network = node.network;
    if (network.vertices.isEmpty) return; // Empty-safe.

    final bounds = network.computeBounds();
    if (bounds.isEmpty) return;

    // --- Region Fills ---
    _drawRegionFills(canvas, node, network, bounds);

    // --- Stroke ---
    _drawStroke(canvas, node, network, bounds);
  }

  /// Draw filled regions.
  static void _drawRegionFills(
    Canvas canvas,
    VectorNetworkNode node,
    VectorNetwork network,
    Rect bounds,
  ) {
    if (network.regions.isEmpty) return;

    // Check cache.
    final cacheKey = node.id;
    Map<int, Path> regionPaths;
    final cached = _cachedRegionPaths[cacheKey];
    if (cached != null && cached.$1 == network.revision) {
      regionPaths = cached.$2;
    } else {
      regionPaths = {};
      for (int i = 0; i < network.regions.length; i++) {
        regionPaths[i] = network.regionToFlutterPath(i);
      }
      _cachedRegionPaths[cacheKey] = (network.revision, regionPaths);
    }

    for (int i = 0; i < network.regions.length; i++) {
      final fillPaint =
          Paint()
            ..style = PaintingStyle.fill
            ..isAntiAlias = true;

      final regionFill = _findRegionFill(node.regionFills, i);
      if (regionFill != null) {
        if (regionFill.gradient != null) {
          fillPaint.shader = regionFill.gradient!.toShader(bounds);
        } else if (regionFill.color != null) {
          fillPaint.color = regionFill.color!;
        } else if (node.fillGradient != null) {
          fillPaint.shader = node.fillGradient!.toShader(bounds);
        } else if (node.fillColor != null) {
          fillPaint.color = node.fillColor!;
        } else {
          continue;
        }
      } else if (node.fillGradient != null) {
        fillPaint.shader = node.fillGradient!.toShader(bounds);
      } else if (node.fillColor != null) {
        fillPaint.color = node.fillColor!;
      } else {
        continue;
      }

      final regionPath = regionPaths[i];
      if (regionPath != null) {
        canvas.drawPath(regionPath, fillPaint);
      }
    }
  }

  /// Draw segment strokes.
  static void _drawStroke(
    Canvas canvas,
    VectorNetworkNode node,
    VectorNetwork network,
    Rect bounds,
  ) {
    if (node.strokeColor == null && node.strokeGradient == null) return;

    // Check if any segment has per-segment overrides.
    final hasOverrides = network.segments.any((s) => s.hasStrokeOverride);

    if (hasOverrides) {
      _drawPerSegmentStroke(canvas, node, network, bounds);
    } else {
      _drawBatchedStroke(canvas, node, network, bounds);
    }
  }

  /// Draw all segments as one batched path (fast path — no per-segment overrides).
  static void _drawBatchedStroke(
    Canvas canvas,
    VectorNetworkNode node,
    VectorNetwork network,
    Rect bounds,
  ) {
    // Check cache.
    Path strokePath;
    if (_cachedStrokeNetworkId == node.id &&
        _cachedStrokeRevision == network.revision &&
        _cachedStrokePath != null) {
      strokePath = _cachedStrokePath!;
    } else {
      strokePath = _buildStrokePath(network);
      _cachedStrokePath = strokePath;
      _cachedStrokeRevision = network.revision;
      _cachedStrokeNetworkId = node.id;
    }

    final strokePaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = node.strokeWidth
          ..strokeCap = node.strokeCap
          ..strokeJoin = node.strokeJoin
          ..strokeMiterLimit = 4.0
          ..isAntiAlias = true;

    if (node.strokeGradient != null) {
      strokePaint.shader = node.strokeGradient!.toShader(bounds);
    } else if (node.strokeColor != null) {
      strokePaint.color = node.strokeColor!;
    }

    canvas.drawPath(strokePath, strokePaint);
  }

  /// Draw each segment individually with its own stroke override.
  static void _drawPerSegmentStroke(
    Canvas canvas,
    VectorNetworkNode node,
    VectorNetwork network,
    Rect bounds,
  ) {
    for (final seg in network.segments) {
      final startPos = network.vertices[seg.start].position;
      final endPos = network.vertices[seg.end].position;

      final segPaint =
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = seg.segmentStrokeWidth ?? node.strokeWidth
            ..strokeCap = seg.segmentStrokeCap ?? node.strokeCap
            ..strokeJoin = node.strokeJoin
            ..strokeMiterLimit = 4.0
            ..isAntiAlias = true;

      if (seg.segmentStrokeColor != null) {
        segPaint.color = Color(seg.segmentStrokeColor!.toUnsigned(32));
      } else if (node.strokeGradient != null) {
        segPaint.shader = node.strokeGradient!.toShader(bounds);
      } else if (node.strokeColor != null) {
        segPaint.color = node.strokeColor!;
      }

      final path = Path();
      path.moveTo(startPos.dx, startPos.dy);
      _addSegmentToPath(path, seg, endPos);
      canvas.drawPath(path, segPaint);
    }
  }

  /// Build a single Flutter [Path] containing all network segments.
  static Path _buildStrokePath(VectorNetwork network) {
    final path = Path();

    for (final seg in network.segments) {
      final startPos = network.vertices[seg.start].position;
      final endPos = network.vertices[seg.end].position;

      path.moveTo(startPos.dx, startPos.dy);
      _addSegmentToPath(path, seg, endPos);
    }

    return path;
  }

  /// Add a single segment curve to a [Path].
  static void _addSegmentToPath(Path path, NetworkSegment seg, Offset endPos) {
    if (seg.isStraight) {
      path.lineTo(endPos.dx, endPos.dy);
    } else if (seg.tangentStart != null && seg.tangentEnd != null) {
      path.cubicTo(
        seg.tangentStart!.dx,
        seg.tangentStart!.dy,
        seg.tangentEnd!.dx,
        seg.tangentEnd!.dy,
        endPos.dx,
        endPos.dy,
      );
    } else {
      final cp = seg.tangentStart ?? seg.tangentEnd ?? endPos;
      path.quadraticBezierTo(cp.dx, cp.dy, endPos.dx, endPos.dy);
    }
  }

  /// Find a [RegionFill] for a given region index.
  static RegionFill? _findRegionFill(List<RegionFill> fills, int regionIndex) {
    for (final fill in fills) {
      if (fill.regionIndex == regionIndex) return fill;
    }
    return null;
  }
}
