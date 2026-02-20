import 'dart:ui';
import '../../core/nodes/vector_network_node.dart';
import '../../core/vector/vector_network.dart';
import '../../core/effects/paint_stack.dart';
import './path_renderer.dart';

/// Renders a [VectorNetworkNode] to a [Canvas].
///
/// Handles per-region fills using the paint stack, per-segment stroke
/// overrides, and global stroke stack. Uses a revision counter to
/// cache built [Path] objects.
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

  /// Draw filled regions using the paint stack.
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
      final regionPath = regionPaths[i];
      if (regionPath == null) continue;

      // Per-region fill overrides take priority.
      final regionFill = _findRegionFill(node.regionFills, i);
      if (regionFill != null) {
        _drawRegionWithOverride(canvas, regionFill, bounds, regionPath, node);
        continue;
      }

      // Use the fill stack.
      if (node.fills.isNotEmpty) {
        for (final fill in node.fills) {
          if (!fill.isVisible) continue;
          // Gradient + opacity < 1 needs saveLayer compositing.
          if (fill.type == FillType.gradient &&
              fill.gradient != null &&
              fill.opacity < 1.0) {
            canvas.saveLayer(
              null,
              Paint()
                ..color = Color.fromARGB(
                  (fill.opacity * 255).round(),
                  255,
                  255,
                  255,
                ),
            );
            final paint =
                Paint()
                  ..style = PaintingStyle.fill
                  ..isAntiAlias = true
                  ..shader = fill.gradient!.toShader(bounds)
                  ..blendMode = fill.blendMode;
            canvas.drawPath(regionPath, paint);
            canvas.restore();
          } else {
            final paint = fill.toPaint(bounds);
            if (paint != null) {
              canvas.drawPath(regionPath, paint);
            }
          }
        }
      } else {
        // Legacy fallback.
        final fillPaint = _legacyFillPaint(node, bounds);
        if (fillPaint != null) {
          canvas.drawPath(regionPath, fillPaint);
        }
      }
    }
  }

  /// Draw a region with a per-region fill override.
  static void _drawRegionWithOverride(
    Canvas canvas,
    RegionFill regionFill,
    Rect bounds,
    Path regionPath,
    VectorNetworkNode node,
  ) {
    final fillPaint =
        Paint()
          ..style = PaintingStyle.fill
          ..isAntiAlias = true;

    if (regionFill.gradient != null) {
      fillPaint.shader = regionFill.gradient!.toShader(bounds);
    } else if (regionFill.color != null) {
      fillPaint.color = regionFill.color!;
    } else {
      // Fall through to node-level fill.
      if (node.fills.isNotEmpty) {
        for (final fill in node.fills) {
          final paint = fill.toPaint(bounds);
          if (paint != null) canvas.drawPath(regionPath, paint);
        }
        return;
      }
      final legacyPaint = _legacyFillPaint(node, bounds);
      if (legacyPaint != null) {
        canvas.drawPath(regionPath, legacyPaint);
      }
      return;
    }

    canvas.drawPath(regionPath, fillPaint);
  }

  /// Create a legacy fill paint from deprecated node fields.
  static Paint? _legacyFillPaint(VectorNetworkNode node, Rect bounds) {
    // ignore: deprecated_member_use_from_same_package
    if (node.fillGradient != null) {
      return Paint()
        ..style = PaintingStyle.fill
        ..isAntiAlias = true
        // ignore: deprecated_member_use_from_same_package
        ..shader = node.fillGradient!.toShader(bounds);
    }
    // ignore: deprecated_member_use_from_same_package
    if (node.fillColor != null) {
      return Paint()
        ..style = PaintingStyle.fill
        ..isAntiAlias = true
        // ignore: deprecated_member_use_from_same_package
        ..color = node.fillColor!;
    }
    return null;
  }

  /// Draw segment strokes using the stroke stack.
  static void _drawStroke(
    Canvas canvas,
    VectorNetworkNode node,
    VectorNetwork network,
    Rect bounds,
  ) {
    // Paint stack strokes.
    if (node.strokes.isNotEmpty) {
      final hasOverrides = network.segments.any((s) => s.hasStrokeOverride);
      if (hasOverrides) {
        _drawPerSegmentStrokeStack(canvas, node, network, bounds);
      } else {
        _drawBatchedStrokeStack(canvas, node, network, bounds);
      }
      return;
    }

    // Legacy fallback.
    // ignore: deprecated_member_use_from_same_package
    if (node.strokeColor == null && node.strokeGradient == null) return;
    final hasOverrides = network.segments.any((s) => s.hasStrokeOverride);
    if (hasOverrides) {
      _drawPerSegmentStrokeLegacy(canvas, node, network, bounds);
    } else {
      _drawBatchedStrokeLegacy(canvas, node, network, bounds);
    }
  }

  /// Draw all segments as one batched path per stroke layer.
  static void _drawBatchedStrokeStack(
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

    for (final stroke in node.strokes) {
      if (!stroke.isVisible) continue;
      if (stroke.color == null && stroke.gradient == null) continue;

      // Build paint manually for proper gradient opacity handling.
      final paint =
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke.width
            ..strokeCap = stroke.cap
            ..strokeJoin = stroke.join
            ..strokeMiterLimit = 4.0
            ..isAntiAlias = true
            ..blendMode = stroke.blendMode;

      final needsOpacityLayer = stroke.opacity < 1.0 && stroke.gradient != null;
      if (stroke.gradient != null && bounds.isFinite && !bounds.isEmpty) {
        paint.shader = stroke.gradient!.toShader(bounds);
      } else if (stroke.color != null) {
        paint.color = stroke.color!.withValues(
          alpha: stroke.color!.a * stroke.opacity,
        );
      } else {
        continue;
      }

      // Apply dash pattern.
      final drawPath =
          stroke.dashPattern != null && stroke.dashPattern!.isNotEmpty
              ? PathRenderer.applyDashPattern(strokePath, stroke.dashPattern!)
              : strokePath;

      if (needsOpacityLayer) {
        canvas.saveLayer(
          null,
          Paint()
            ..color = Color.fromARGB(
              (stroke.opacity * 255).round(),
              255,
              255,
              255,
            ),
        );
      }
      canvas.drawPath(drawPath, paint);
      if (needsOpacityLayer) {
        canvas.restore();
      }
    }
  }

  /// Draw each segment individually with per-segment overrides, using stack.
  static void _drawPerSegmentStrokeStack(
    Canvas canvas,
    VectorNetworkNode node,
    VectorNetwork network,
    Rect bounds,
  ) {
    for (final seg in network.segments) {
      final startPos = network.vertices[seg.start].position;
      final endPos = network.vertices[seg.end].position;

      final path = Path();
      path.moveTo(startPos.dx, startPos.dy);
      _addSegmentToPath(path, seg, endPos);

      if (seg.hasStrokeOverride) {
        // Per-segment override paint.
        final segPaint =
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = seg.segmentStrokeWidth ?? node.strokes.first.width
              ..strokeCap = seg.segmentStrokeCap ?? node.strokes.first.cap
              ..strokeJoin = node.strokes.first.join
              ..strokeMiterLimit = 4.0
              ..isAntiAlias = true;

        if (seg.segmentStrokeColor != null) {
          segPaint.color = Color(seg.segmentStrokeColor!.toUnsigned(32));
        } else {
          final fallbackPaint = node.strokes.first.toPaint(bounds);
          if (fallbackPaint != null) {
            segPaint.shader = fallbackPaint.shader;
            if (fallbackPaint.shader == null) {
              segPaint.color = fallbackPaint.color;
            }
          }
        }
        canvas.drawPath(path, segPaint);
      } else {
        for (final stroke in node.strokes) {
          if (!stroke.isVisible) continue;
          if (stroke.color == null && stroke.gradient == null) continue;

          final paint =
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = stroke.width
                ..strokeCap = stroke.cap
                ..strokeJoin = stroke.join
                ..strokeMiterLimit = 4.0
                ..isAntiAlias = true
                ..blendMode = stroke.blendMode;

          final needsOpacityLayer =
              stroke.opacity < 1.0 && stroke.gradient != null;
          if (stroke.gradient != null && bounds.isFinite && !bounds.isEmpty) {
            paint.shader = stroke.gradient!.toShader(bounds);
          } else if (stroke.color != null) {
            paint.color = stroke.color!.withValues(
              alpha: stroke.color!.a * stroke.opacity,
            );
          } else {
            continue;
          }

          // Apply dash pattern.
          final drawPath =
              stroke.dashPattern != null && stroke.dashPattern!.isNotEmpty
                  ? PathRenderer.applyDashPattern(path, stroke.dashPattern!)
                  : path;

          if (needsOpacityLayer) {
            canvas.saveLayer(
              null,
              Paint()
                ..color = Color.fromARGB(
                  (stroke.opacity * 255).round(),
                  255,
                  255,
                  255,
                ),
            );
          }
          canvas.drawPath(drawPath, paint);
          if (needsOpacityLayer) {
            canvas.restore();
          }
        }
      }
    }
  }

  // -------------------------------------------------------------------------
  // Legacy rendering (backward compat)
  // -------------------------------------------------------------------------

  static void _drawBatchedStrokeLegacy(
    Canvas canvas,
    VectorNetworkNode node,
    VectorNetwork network,
    Rect bounds,
  ) {
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
          // ignore: deprecated_member_use_from_same_package
          ..strokeWidth = node.strokeWidth
          // ignore: deprecated_member_use_from_same_package
          ..strokeCap = node.strokeCap
          // ignore: deprecated_member_use_from_same_package
          ..strokeJoin = node.strokeJoin
          ..strokeMiterLimit = 4.0
          ..isAntiAlias = true;

    // ignore: deprecated_member_use_from_same_package
    if (node.strokeGradient != null) {
      // ignore: deprecated_member_use_from_same_package
      strokePaint.shader = node.strokeGradient!.toShader(bounds);
      // ignore: deprecated_member_use_from_same_package
    } else if (node.strokeColor != null) {
      // ignore: deprecated_member_use_from_same_package
      strokePaint.color = node.strokeColor!;
    }

    canvas.drawPath(strokePath, strokePaint);
  }

  static void _drawPerSegmentStrokeLegacy(
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
            // ignore: deprecated_member_use_from_same_package
            ..strokeWidth = seg.segmentStrokeWidth ?? node.strokeWidth
            // ignore: deprecated_member_use_from_same_package
            ..strokeCap = seg.segmentStrokeCap ?? node.strokeCap
            // ignore: deprecated_member_use_from_same_package
            ..strokeJoin = node.strokeJoin
            ..strokeMiterLimit = 4.0
            ..isAntiAlias = true;

      if (seg.segmentStrokeColor != null) {
        segPaint.color = Color(seg.segmentStrokeColor!.toUnsigned(32));
        // ignore: deprecated_member_use_from_same_package
      } else if (node.strokeGradient != null) {
        // ignore: deprecated_member_use_from_same_package
        segPaint.shader = node.strokeGradient!.toShader(bounds);
        // ignore: deprecated_member_use_from_same_package
      } else if (node.strokeColor != null) {
        // ignore: deprecated_member_use_from_same_package
        segPaint.color = node.strokeColor!;
      }

      final path = Path();
      path.moveTo(startPos.dx, startPos.dy);
      _addSegmentToPath(path, seg, endPos);
      canvas.drawPath(path, segPaint);
    }
  }

  // -------------------------------------------------------------------------
  // Shared helpers
  // -------------------------------------------------------------------------

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
