import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/digital_text_element.dart';
import '../../core/models/image_element.dart';
import '../../drawing/models/pro_drawing_point.dart';
import '../../core/models/shape_type.dart';
import '../infinite_canvas_controller.dart';

/// 🔮 Overlay for positioning elements recovered from the past
///
/// Shows a draggable preview of the selected elements
/// on the live canvas, allowing the user to move them before
/// the final commit. Supports auto-pan at screen edges.
class RecoveryPlacementOverlay extends StatefulWidget {
  final List<ProStroke> strokes;
  final List<GeometricShape> shapes;
  final List<ImageElement> images;
  final List<DigitalTextElement> texts;
  final InfiniteCanvasController canvasController;
  final Offset initialOffset;
  final ValueChanged<Offset> onOffsetChanged;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const RecoveryPlacementOverlay({
    super.key,
    required this.strokes,
    required this.shapes,
    required this.images,
    required this.texts,
    required this.canvasController,
    required this.initialOffset,
    required this.onOffsetChanged,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  State<RecoveryPlacementOverlay> createState() =>
      _RecoveryPlacementOverlayState();
}

class _RecoveryPlacementOverlayState extends State<RecoveryPlacementOverlay>
    with SingleTickerProviderStateMixin {
  late Offset _currentOffset;
  late AnimationController _pulseController;

  // ─── Auto-pan (edge scrolling) ─────────────────────
  static const double _autoPanEdgeZone = 60.0;
  static const double _autoPanSpeed = 5.0;
  static const Duration _autoPanInterval = Duration(milliseconds: 16);
  Timer? _autoPanTimer;
  Offset _lastDragPosition = Offset.zero;
  Size _viewportSize = Size.zero;
  bool _isDragging = false;

  /// Overall bounding box of all elements (canvas coords)
  late Rect _elementsBounds;

  @override
  void initState() {
    super.initState();
    _currentOffset = widget.initialOffset;
    _elementsBounds = _calculateBounds();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _stopAutoPan();
    _pulseController.dispose();
    super.dispose();
  }

  Rect _calculateBounds() {
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    for (final stroke in widget.strokes) {
      if (stroke.points.isEmpty) continue;
      final b = stroke.bounds;
      minX = math.min(minX, b.left);
      minY = math.min(minY, b.top);
      maxX = math.max(maxX, b.right);
      maxY = math.max(maxY, b.bottom);
    }

    for (final shape in widget.shapes) {
      minX = math.min(minX, math.min(shape.startPoint.dx, shape.endPoint.dx));
      minY = math.min(minY, math.min(shape.startPoint.dy, shape.endPoint.dy));
      maxX = math.max(maxX, math.max(shape.startPoint.dx, shape.endPoint.dx));
      maxY = math.max(maxY, math.max(shape.startPoint.dy, shape.endPoint.dy));
    }

    for (final img in widget.images) {
      minX = math.min(minX, img.position.dx);
      minY = math.min(minY, img.position.dy);
      maxX = math.max(maxX, img.position.dx + 100);
      maxY = math.max(maxY, img.position.dy + 100);
    }

    for (final text in widget.texts) {
      minX = math.min(minX, text.position.dx);
      minY = math.min(minY, text.position.dy);
      maxX = math.max(maxX, text.position.dx + 150);
      maxY = math.max(maxY, text.position.dy + 30);
    }

    if (minX == double.infinity) {
      return Rect.zero;
    }

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  // ─── Auto-pan logic (matching existing lasso behavior) ───

  Offset _calculateAutoPanDelta(Offset position) {
    double dx = 0;
    double dy = 0;

    // Left edge
    if (position.dx < _autoPanEdgeZone) {
      dx = -_autoPanSpeed * (1 - position.dx / _autoPanEdgeZone);
    }
    // Right edge
    else if (position.dx > _viewportSize.width - _autoPanEdgeZone) {
      dx =
          _autoPanSpeed *
          (1 - (_viewportSize.width - position.dx) / _autoPanEdgeZone);
    }

    // Top edge
    if (position.dy < _autoPanEdgeZone) {
      dy = -_autoPanSpeed * (1 - position.dy / _autoPanEdgeZone);
    }
    // Bottom edge
    else if (position.dy > _viewportSize.height - _autoPanEdgeZone) {
      dy =
          _autoPanSpeed *
          (1 - (_viewportSize.height - position.dy) / _autoPanEdgeZone);
    }

    return Offset(dx, dy);
  }

  void _startAutoPan() {
    if (_autoPanTimer != null) return;

    _autoPanTimer = Timer.periodic(_autoPanInterval, (_) {
      if (!_isDragging) {
        _stopAutoPan();
        return;
      }

      final panDelta = _calculateAutoPanDelta(_lastDragPosition);

      if (panDelta != Offset.zero) {
        // Move the canvas in the OPPOSITE direction to panDelta:
        // positive panDelta (right edge) → offset decreases → scroll right
        final ctrl = widget.canvasController;
        ctrl.setOffset(ctrl.offset - panDelta);

        // Compensate the elements to keep them under the finger
        setState(() {
          _currentOffset += panDelta / ctrl.scale;
        });
        widget.onOffsetChanged(_currentOffset);
      }
    });
  }

  void _stopAutoPan() {
    _autoPanTimer?.cancel();
    _autoPanTimer = null;
  }

  // ─── Drag handlers ─────────────────────────────────

  void _onPanStart(DragStartDetails details) {
    _isDragging = true;
    final box = context.findRenderObject() as RenderBox?;
    if (box != null) {
      _lastDragPosition = box.globalToLocal(details.globalPosition);
    }
    _startAutoPan();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    // Update position per auto-pan
    final box = context.findRenderObject() as RenderBox?;
    if (box != null) {
      _lastDragPosition = box.globalToLocal(details.globalPosition);
    }

    setState(() {
      _currentOffset += details.delta / widget.canvasController.scale;
    });
    widget.onOffsetChanged(_currentOffset);
  }

  void _onPanEnd(DragEndDetails details) {
    _isDragging = false;
    _stopAutoPan();
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportSize = Size(constraints.maxWidth, constraints.maxHeight);

        return Stack(
          children: [
            // Layer 1: Element preview + drag area
            Positioned.fill(
              child: GestureDetector(
                onPanStart: _onPanStart,
                onPanUpdate: _onPanUpdate,
                onPanEnd: _onPanEnd,
                behavior: HitTestBehavior.opaque,
                child: AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _PlacementPreviewPainter(
                        strokes: widget.strokes,
                        shapes: widget.shapes,
                        images: widget.images,
                        texts: widget.texts,
                        offset: _currentOffset,
                        canvasController: widget.canvasController,
                        elementsBounds: _elementsBounds,
                        pulseValue: _pulseController.value,
                        accentColor: cs.tertiary,
                        highlightColor: cs.tertiaryContainer,
                      ),
                    );
                  },
                ),
              ),
            ),

            // Layer 2: Bottom bar
            Positioned(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).padding.bottom + 16,
              child: Material(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(28),
                elevation: 8,
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.open_with_rounded,
                        color: cs.tertiary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Drag to position',
                          style: tt.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),

                      // Cancel
                      TextButton(
                        onPressed: widget.onCancel,
                        child: Text(
                          'Cancel',
                          style: TextStyle(color: cs.error),
                        ),
                      ),

                      const SizedBox(width: 4),

                      // Confirm
                      FilledButton.icon(
                        onPressed: widget.onConfirm,
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text('Position'),
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.tertiary,
                          foregroundColor: cs.onTertiary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── Custom Painter ──────────────────────────────────────

class _PlacementPreviewPainter extends CustomPainter {
  final List<ProStroke> strokes;
  final List<GeometricShape> shapes;
  final List<ImageElement> images;
  final List<DigitalTextElement> texts;
  final Offset offset;
  final InfiniteCanvasController canvasController;
  final Rect elementsBounds;
  final double pulseValue;
  final Color accentColor;
  final Color highlightColor;

  _PlacementPreviewPainter({
    required this.strokes,
    required this.shapes,
    required this.images,
    required this.texts,
    required this.offset,
    required this.canvasController,
    required this.elementsBounds,
    required this.pulseValue,
    required this.accentColor,
    required this.highlightColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final ctrl = canvasController;
    final scale = ctrl.scale;

    // ─── Bounding box group (screen space) ──────────
    if (elementsBounds != Rect.zero) {
      final tl = ctrl.canvasToScreen(elementsBounds.topLeft + offset);
      final br = ctrl.canvasToScreen(elementsBounds.bottomRight + offset);
      final groupRect = Rect.fromPoints(tl, br).inflate(8);

      // Pulsing glow
      final glowAlpha = 0.15 + pulseValue * 0.1;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          groupRect.inflate(4),
          const Radius.circular(12),
        ),
        Paint()
          ..color = highlightColor.withValues(alpha: glowAlpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      );

      // Dashed border
      final borderPaint =
          Paint()
            ..color = accentColor.withValues(alpha: 0.5 + pulseValue * 0.3)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(groupRect, const Radius.circular(10)),
        borderPaint,
      );

      // Move icon at center
      final center = groupRect.center;
      final iconPaint =
          Paint()
            ..color = accentColor.withValues(alpha: 0.3 + pulseValue * 0.2);
      canvas.drawCircle(center, 16, iconPaint);

      // Directional arrows
      final arrowPaint =
          Paint()
            ..color = accentColor.withValues(alpha: 0.6)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round;
      const arrowLen = 8.0;
      // Up
      canvas.drawLine(
        center + const Offset(0, -6),
        center + const Offset(0, -6 - arrowLen),
        arrowPaint,
      );
      // Down
      canvas.drawLine(
        center + const Offset(0, 6),
        center + const Offset(0, 6 + arrowLen),
        arrowPaint,
      );
      // Left
      canvas.drawLine(
        center + const Offset(-6, 0),
        center + const Offset(-6 - arrowLen, 0),
        arrowPaint,
      );
      // Right
      canvas.drawLine(
        center + const Offset(6, 0),
        center + const Offset(6 + arrowLen, 0),
        arrowPaint,
      );
    }

    // ─── Render strokes (simplified: draw the path) ─
    for (final stroke in strokes) {
      if (stroke.points.length < 2) continue;

      final paint =
          Paint()
            ..color = stroke.color.withValues(alpha: 0.7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1, stroke.baseWidth * scale * 0.8)
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round;

      final path = Path();
      final firstPt = ctrl.canvasToScreen(
        Offset(
              stroke.points.first.position.dx,
              stroke.points.first.position.dy,
            ) +
            offset,
      );
      path.moveTo(firstPt.dx, firstPt.dy);

      for (int i = 1; i < stroke.points.length; i++) {
        final pt = ctrl.canvasToScreen(
          Offset(stroke.points[i].position.dx, stroke.points[i].position.dy) +
              offset,
        );
        path.lineTo(pt.dx, pt.dy);
      }

      canvas.drawPath(path, paint);
    }

    // ─── Render shapes ──────────────────────────────
    for (final shape in shapes) {
      final sp = ctrl.canvasToScreen(shape.startPoint + offset);
      final ep = ctrl.canvasToScreen(shape.endPoint + offset);

      final paint =
          Paint()
            ..color = shape.color.withValues(alpha: 0.7)
            ..style = shape.filled ? PaintingStyle.fill : PaintingStyle.stroke
            ..strokeWidth = math.max(1, shape.strokeWidth * scale);

      final rect = Rect.fromPoints(sp, ep);

      switch (shape.type) {
        case ShapeType.rectangle:
          canvas.drawRect(rect, paint);
          break;
        case ShapeType.circle:
          canvas.drawOval(rect, paint);
          break;
        case ShapeType.line:
          canvas.drawLine(sp, ep, paint);
          break;
        case ShapeType.triangle:
          final triPath =
              Path()
                ..moveTo((sp.dx + ep.dx) / 2, sp.dy)
                ..lineTo(ep.dx, ep.dy)
                ..lineTo(sp.dx, ep.dy)
                ..close();
          canvas.drawPath(triPath, paint);
          break;
        default:
          canvas.drawRect(rect, paint);
      }
    }

    // ─── Render images (placeholder) ────────────────
    for (final img in images) {
      final pos = ctrl.canvasToScreen(img.position + offset);
      final imgSize = 80.0 * scale;
      final imgRect = Rect.fromLTWH(pos.dx, pos.dy, imgSize, imgSize);

      canvas.drawRRect(
        RRect.fromRectAndRadius(imgRect, const Radius.circular(8)),
        Paint()..color = highlightColor.withValues(alpha: 0.3),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(imgRect, const Radius.circular(8)),
        Paint()
          ..color = accentColor.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );

      // Image icon at center
      final iconPaint = Paint()..color = accentColor.withValues(alpha: 0.4);
      final imgCenter = imgRect.center;
      canvas.drawCircle(imgCenter, 12 * scale, iconPaint);
    }

    // ─── Render texts ───────────────────────────────
    for (final text in texts) {
      final pos = ctrl.canvasToScreen(text.position + offset);
      final tp = TextPainter(
        text: TextSpan(
          text: text.text,
          style: TextStyle(
            color: text.color.withValues(alpha: 0.7),
            fontSize: (text.fontSize * scale).clamp(8.0, 48.0),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 300 * scale);

      tp.paint(canvas, pos);
    }
  }

  @override
  bool shouldRepaint(covariant _PlacementPreviewPainter oldDelegate) =>
      offset != oldDelegate.offset || pulseValue != oldDelegate.pulseValue;
}
