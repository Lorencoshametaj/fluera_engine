import 'dart:math';
import 'package:flutter/material.dart';
import '../../drawing/models/pro_drawing_point.dart';
import '../../core/models/shape_type.dart';
import '../../core/models/canvas_layer.dart';
import '../../core/models/digital_text_element.dart';
import '../../core/models/image_element.dart';
import '../../layers/fluera_layer_controller.dart';
import '../../canvas/infinite_canvas_controller.dart';
import '../../core/nodes/stroke_node.dart';

/// Widget overlay showing elements selected by lasso (with animation).
///
/// Uses a single [selectedIds] set and determines element type by
/// checking the active layer's typed lists.
class LassoSelectionOverlay extends StatefulWidget {
  /// Unified set of all selected element IDs.
  final Set<String> selectedIds;
  final FlueraLayerController layerController;
  final InfiniteCanvasController canvasController;
  final bool isDragging;

  /// Feather radius for soft-edge selection highlight (0 = sharp).
  final double featherRadius;

  /// Canonical selection bounds (canvas coords) from LassoTool.getSelectionBounds().
  /// Used for the unified bounding box so it matches SelectionTransformOverlay.
  final Rect? selectionBounds;

  /// 🚀 PERF: Optional notifier for smooth repositioning during drag.
  final ValueNotifier<int>? dragNotifier;

  /// 🧮 Called when user taps "Convert to LaTeX" action.
  final VoidCallback? onConvertToLatex;

  const LassoSelectionOverlay({
    super.key,
    required this.selectedIds,
    required this.layerController,
    required this.canvasController,
    this.isDragging = false,
    this.featherRadius = 0.0,
    this.selectionBounds,
    this.dragNotifier,
    this.onConvertToLatex,
  });

  @override
  State<LassoSelectionOverlay> createState() => _LassoSelectionOverlayState();
}

class _LassoSelectionOverlayState extends State<LassoSelectionOverlay>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _entryController;
  late Animation<double> _entryAnimation;
  late AnimationController _flowController;
  bool _wasEmpty = true;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.3, end: 0.6).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // #4: Fade-in + scale entry animation
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: 1.0, // Start fully visible — didUpdateWidget triggers fade-in
    );
    _entryAnimation = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOut,
    );

    // #1: Continuous flow animation for gradient border (3s loop)
    _flowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();

    // 🚀 Follow canvas transform (zoom/pan/rotate)
    widget.canvasController.addListener(_onTransformChanged);
    // 🚀 PERF: Listen to drag updates for smooth highlight repositioning
    widget.dragNotifier?.addListener(_onTransformChanged);
  }

  @override
  void didUpdateWidget(covariant LassoSelectionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Track empty→non-empty transition with internal boolean because
    // oldWidget.selectedIds is the SAME mutable Set reference as widget.selectedIds.
    final isNonEmpty = widget.selectedIds.isNotEmpty;
    if (_wasEmpty && isNonEmpty) {
      _entryController.forward(from: 0);
    }
    _wasEmpty = widget.selectedIds.isEmpty;
  }


  @override
  void dispose() {
    widget.canvasController.removeListener(_onTransformChanged);
    widget.dragNotifier?.removeListener(_onTransformChanged);
    _pulseController.dispose();
    _entryController.dispose();
    _flowController.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (widget.selectedIds.isEmpty) {
      return const SizedBox.shrink();
    }

    // 🐛 BISECT: temporarily strip FadeTransition + ScaleTransition that wrap
    // a fullscreen SizedBox.expand. On Impeller-Vulkan this combo triggers
    // a fullscreen saveLayer + Transform that washes the canvas grey and
    // captures all input on Android.
    return AnimatedBuilder(
      animation: Listenable.merge([_pulseAnimation, _flowController]),
      builder: (context, child) {
        return IgnorePointer(
          child: CustomPaint(
            painter: _SelectionHighlightPainter(
              selectedIds: widget.selectedIds,
              layerController: widget.layerController,
              animationValue: _pulseAnimation.value,
              flowValue: _flowController.value,
              canvasController: widget.canvasController,
              isDragging: widget.isDragging,
              featherRadius: widget.featherRadius,
              selectionBounds: widget.selectionBounds,
            ),
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }

  /// Check if the selection contains any strokes (not shapes/text/images).
  bool _hasSelectedStrokes() {
    final layers = widget.layerController.layers;
    if (layers.isEmpty) return false;
    final layer = layers.firstWhere(
      (l) => l.id == widget.layerController.activeLayerId,
      orElse: () => layers.first,
    );
    return layer.strokes.any((s) => widget.selectedIds.contains(s.id));
  }

  /// Build the floating "Convert to LaTeX" button above the selection.
  Widget _buildConvertToLatexFab() {
    // Calculate selection bounding rect in screen coordinates
    final layers = widget.layerController.layers;
    if (layers.isEmpty) return const SizedBox.shrink();
    final layer = layers.firstWhere(
      (l) => l.id == widget.layerController.activeLayerId,
      orElse: () => layers.first,
    );

    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity;
    for (final stroke in layer.strokes) {
      if (!widget.selectedIds.contains(stroke.id)) continue;
      for (final p in stroke.points) {
        final sp = widget.canvasController.canvasToScreen(p.position);
        if (sp.dx < minX) minX = sp.dx;
        if (sp.dy < minY) minY = sp.dy;
        if (sp.dx > maxX) maxX = sp.dx;
      }
    }

    if (!minX.isFinite || !minY.isFinite) return const SizedBox.shrink();

    final centerX = (minX + maxX) / 2;
    final fabTop = minY - 52; // Above the selection

    return Positioned(
      left: centerX - 20,
      top: fabTop.clamp(8, double.infinity),
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(16),
        color: Colors.teal,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: widget.onConvertToLatex,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.functions_rounded, color: Colors.white, size: 20),
                SizedBox(width: 4),
                Text(
                  'LaTeX',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Painter that highlights all selected elements with professional effects.
///
/// Determines element type dynamically from the active layer's typed lists.
class _SelectionHighlightPainter extends CustomPainter {
  final Set<String> selectedIds;
  final FlueraLayerController layerController;
  final double animationValue;
  final double flowValue;
  final InfiniteCanvasController canvasController;
  final bool isDragging;
  final double featherRadius;
  final Rect? selectionBounds;

  _SelectionHighlightPainter({
    required this.selectedIds,
    required this.layerController,
    required this.animationValue,
    required this.flowValue,
    required this.canvasController,
    this.isDragging = false,
    this.featherRadius = 0.0,
    this.selectionBounds,
  });

  /// Helper: compute rotated gradient alignment from flowValue (0→1).
  Alignment _flowStart() {
    final angle = flowValue * 2 * 3.14159265;
    return Alignment(cos(angle), sin(angle));
  }
  Alignment _flowEnd() {
    final angle = flowValue * 2 * 3.14159265 + 3.14159265;
    return Alignment(cos(angle), sin(angle));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final activeLayer = layerController.layers.firstWhere(
      (layer) => layer.id == layerController.activeLayerId,
      orElse: () => layerController.layers.first,
    );

    // =========================================================================
    // Selection Mask Dimming REMOVED.
    // The previous Procreate-style fullscreen dim (indigo 0xFF1E1B4B at
    // alpha 0.15-0.18 over `fullRect` minus selected-item bounds) was being
    // perceived as a grey wash over the canvas as soon as a lasso selection
    // closed. The per-element highlights below already mark what's selected,
    // so the screen-wide dim is unnecessary.

    // =========================================================================
    // Element Highlights
    // =========================================================================

    // Highlight selected strokes
    for (final stroke in activeLayer.strokes) {
      if (selectedIds.contains(stroke.id)) {
        _drawStrokeHighlight(canvas, stroke);
      }
    }

    // Highlight selected shapes
    for (final shape in activeLayer.shapes) {
      if (selectedIds.contains(shape.id)) {
        _drawShapeHighlight(canvas, shape);
      }
    }

    // Highlight selected text elements
    for (final text in activeLayer.texts) {
      if (selectedIds.contains(text.id)) {
        _drawTextHighlight(canvas, text);
      }
    }

    // Highlight selected image elements
    for (final image in activeLayer.images) {
      if (selectedIds.contains(image.id)) {
        _drawImageHighlight(canvas, image);
      }
    }

    // =========================================================================
    // #1: Unified Bounding Box (Figma-style) + #5: Count Badge
    // =========================================================================
    if (selectedIds.length > 1 && !isDragging) {
      // Compute union in CANVAS SPACE first (matching getSelectionBounds() padding)
      Rect? canvasUnion;
      for (final child in activeLayer.node.children) {
        if (!selectedIds.contains(child.id)) continue;
        final wb = child.worldBounds;
        if (!wb.isFinite || wb.isEmpty) continue;
        canvasUnion = canvasUnion?.expandToInclude(wb) ?? wb;
      }

      if (canvasUnion != null) {
        // inflate(20) in canvas space — same as _kSelectionBoundsPadding
        final inflated = canvasUnion.inflate(20);
        final tl = canvasController.canvasToScreen(inflated.topLeft);
        final br = canvasController.canvasToScreen(inflated.bottomRight);
        final expanded = Rect.fromPoints(tl, br);
        final rrect = RRect.fromRectAndRadius(expanded, const Radius.circular(8));

        // Soft outer glow
        canvas.drawRRect(
          rrect.inflate(2),
          Paint()
            ..color = const Color(0xFF818CF8).withValues(alpha: 0.10 + animationValue * 0.05)
            ..strokeWidth = 4.0
            ..style = PaintingStyle.stroke
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0),
        );

        // Flowing gradient border
        canvas.drawRRect(
          rrect,
          Paint()
            ..shader = LinearGradient(
              begin: _flowStart(),
              end: _flowEnd(),
              colors: [
                const Color(0xFF818CF8).withValues(alpha: 0.50),
                const Color(0xFF22D3EE).withValues(alpha: 0.50),
                const Color(0xFFC084FC).withValues(alpha: 0.50),
                const Color(0xFF818CF8).withValues(alpha: 0.50),
              ],
              stops: const [0.0, 0.33, 0.66, 1.0],
            ).createShader(expanded)
            ..strokeWidth = 1.5
            ..style = PaintingStyle.stroke,
        );


        // #5: Count badge — bottom-right of bounding box (avoids rotation handle at top)
        final count = selectedIds.length;
        final badgeText = '$count';
        final tp = TextPainter(
          text: TextSpan(
            text: badgeText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        final badgeW = tp.width + 10;
        final badgeH = tp.height + 4;
        final badgeRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            expanded.right - badgeW / 2,
            expanded.bottom + 4,
            badgeW,
            badgeH,
          ),
          const Radius.circular(8),
        );

        // Badge shadow
        canvas.drawRRect(
          badgeRect.inflate(1),
          Paint()
            ..color = Colors.black.withValues(alpha: 0.12)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0),
        );
        // Badge background
        canvas.drawRRect(
          badgeRect,
          Paint()
            ..shader = const LinearGradient(
              colors: [Color(0xFF818CF8), Color(0xFF6366F1)],
            ).createShader(badgeRect.outerRect),
        );
        // Badge text
        tp.paint(
          canvas,
          Offset(
            badgeRect.outerRect.left + (badgeW - tp.width) / 2,
            badgeRect.outerRect.top + (badgeH - tp.height) / 2,
          ),
        );
      }
    }
  }

  /// Get screen-space bounding rect for a stroke (with node offset).
  Rect? _getStrokeScreenBounds(ProStroke stroke) {
    if (stroke.points.isEmpty) return null;

    Offset nodeOffset = Offset.zero;
    for (final layer in layerController.sceneGraph.layers) {
      for (final child in layer.children) {
        if (child is StrokeNode && child.stroke.id == stroke.id) {
          nodeOffset = child.position;
          break;
        }
      }
      if (nodeOffset != Offset.zero) break;
    }

    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    for (final p in stroke.points) {
      final sp = canvasController.canvasToScreen(p.position + nodeOffset);
      if (sp.dx < minX) minX = sp.dx;
      if (sp.dy < minY) minY = sp.dy;
      if (sp.dx > maxX) maxX = sp.dx;
      if (sp.dy > maxY) maxY = sp.dy;
    }

    if (!minX.isFinite) return null;
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  void _drawStrokeHighlight(Canvas canvas, ProStroke stroke) {
    if (stroke.points.isEmpty) return;

    // 🚀 FIX: Look up the StrokeNode to get its localTransform offset.
    // translateAll() modifies localTransform, not the raw point data.
    Offset nodeOffset = Offset.zero;
    for (final layer in layerController.sceneGraph.layers) {
      for (final child in layer.children) {
        if (child is StrokeNode && child.stroke.id == stroke.id) {
          nodeOffset = child.position;
          break;
        }
      }
      if (nodeOffset != Offset.zero) break;
    }

    final path = Path();
    final screenPoints =
        stroke.points
            .map(
              (p) => canvasController.canvasToScreen(p.position + nodeOffset),
            )
            .toList();

    if (screenPoints.length < 2) return;

    path.moveTo(screenPoints[0].dx, screenPoints[0].dy);

    if (screenPoints.length == 2) {
      path.lineTo(screenPoints[1].dx, screenPoints[1].dy);
    } else {
      // Smooth Catmull-Rom style interpolation using quadratic Bézier
      for (var i = 0; i < screenPoints.length - 1; i++) {
        final p0 = screenPoints[i];
        final p1 = screenPoints[i + 1];
        final midX = (p0.dx + p1.dx) / 2;
        final midY = (p0.dy + p1.dy) / 2;

        if (i == 0) {
          // First segment: line to midpoint
          path.lineTo(midX, midY);
        } else {
          // Use previous point as control point, midpoint as endpoint
          path.quadraticBezierTo(p0.dx, p0.dy, midX, midY);
        }
      }
      // Final segment: curve to last point
      final last = screenPoints.last;
      final secondLast = screenPoints[screenPoints.length - 2];
      path.quadraticBezierTo(secondLast.dx, secondLast.dy, last.dx, last.dy);
    }

    // #2: Lift shadow — draw path offset downward with blur
    final shadowPath = path.shift(const Offset(0, 2));
    canvas.drawPath(
      shadowPath,
      Paint()
        ..color = const Color(0xFF1E1B4B).withValues(alpha: 0.12)
        ..strokeWidth = 4.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0),
    );

    // Soft ambient glow — flowing gradient
    final bounds = path.getBounds();
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: _flowStart(),
          end: _flowEnd(),
          colors: [
            const Color(0xFF818CF8).withValues(alpha: 0.20),
            const Color(0xFF22D3EE).withValues(alpha: 0.25),
            const Color(0xFFC084FC).withValues(alpha: 0.20),
            const Color(0xFF818CF8).withValues(alpha: 0.20),
          ],
          stops: const [0.0, 0.33, 0.66, 1.0],
        ).createShader(bounds)
        ..strokeWidth = 8.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          featherRadius > 0 ? featherRadius : 4.0,
        ),
    );

    // Main flowing gradient border
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: _flowStart(),
          end: _flowEnd(),
          colors: const [
            Color(0xFF818CF8),
            Color(0xFF22D3EE),
            Color(0xFFC084FC),
            Color(0xFF818CF8),
          ],
          stops: const [0.0, 0.33, 0.66, 1.0],
        ).createShader(bounds)
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // White inner highlight
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _drawShapeHighlight(Canvas canvas, GeometricShape shape) {
    final startScreen = canvasController.canvasToScreen(shape.startPoint);
    final endScreen = canvasController.canvasToScreen(shape.endPoint);

    final rect = Rect.fromPoints(startScreen, endScreen);
    final expandedRect = rect.inflate(8);
    final rrect = RRect.fromRectAndRadius(expandedRect, const Radius.circular(6));

    // #2: Lift shadow
    canvas.drawRRect(
      rrect.shift(const Offset(0, 2)),
      Paint()
        ..color = const Color(0xFF1E1B4B).withValues(alpha: 0.10)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0),
    );

    // Flowing glow
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: _flowStart(),
          end: _flowEnd(),
          colors: [
            const Color(0xFF818CF8).withValues(alpha: 0.15),
            const Color(0xFF22D3EE).withValues(alpha: 0.20),
            const Color(0xFFC084FC).withValues(alpha: 0.15),
          ],
        ).createShader(expandedRect)
        ..strokeWidth = 6.0
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0),
    );

    // Flowing gradient border
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: _flowStart(),
          end: _flowEnd(),
          colors: const [Color(0xFF818CF8), Color(0xFF22D3EE), Color(0xFF818CF8)],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(expandedRect)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke,
    );

    // Frosted fill
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = const Color(0xFF818CF8).withValues(alpha: 0.04)
        ..style = PaintingStyle.fill,
    );

    // Corner handles (hidden during drag-move).
    // When 2+ items are selected the unified bounding box already shows
    // 4 corner anchors → drawing per-element handles too means they sit
    // INSIDE the unified box, overlapping the selected content.
    if (!isDragging && selectedIds.length == 1) {
      _drawCornerHandles(canvas, expandedRect);
    }
  }

  void _drawTextHighlight(Canvas canvas, DigitalTextElement text) {
    final screenPos = canvasController.canvasToScreen(text.position);

    final textPainter = TextPainter(
      text: TextSpan(
        text: text.text,
        style: TextStyle(
          fontSize: text.fontSize * text.scale,
          fontWeight: text.fontWeight,
          fontFamily: text.fontFamily,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final scale = canvasController.scale;
    final rect = Rect.fromLTWH(
      screenPos.dx,
      screenPos.dy,
      max(textPainter.width * scale, 60),
      max(textPainter.height * scale, 24),
    );
    final expandedRect = rect.inflate(6);
    final rrect = RRect.fromRectAndRadius(expandedRect, const Radius.circular(6));

    // #2: Lift shadow
    canvas.drawRRect(
      rrect.shift(const Offset(0, 2)),
      Paint()
        ..color = const Color(0xFF1E1B4B).withValues(alpha: 0.10)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0),
    );

    // Flowing gradient glow
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: _flowStart(),
          end: _flowEnd(),
          colors: [
            const Color(0xFF818CF8).withValues(alpha: 0.12),
            const Color(0xFFC084FC).withValues(alpha: 0.15),
            const Color(0xFF818CF8).withValues(alpha: 0.12),
          ],
        ).createShader(expandedRect)
        ..strokeWidth = 5.0
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0),
    );

    // Flowing gradient border
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: _flowStart(),
          end: _flowEnd(),
          colors: const [Color(0xFF818CF8), Color(0xFFC084FC), Color(0xFF818CF8)],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(expandedRect)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );

    // Frosted fill
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = const Color(0xFFC084FC).withValues(alpha: 0.04)
        ..style = PaintingStyle.fill,
    );

    // "T" type indicator badge
    final badgeCenter = expandedRect.topRight + const Offset(4, -4);
    canvas.drawCircle(
      badgeCenter,
      7,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.1)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0),
    );
    canvas.drawCircle(
      badgeCenter,
      6,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF818CF8), Color(0xFFC084FC)],
        ).createShader(Rect.fromCircle(center: badgeCenter, radius: 6)),
    );
    final tp = TextPainter(
      text: const TextSpan(
        text: 'T',
        style: TextStyle(
          color: Colors.white,
          fontSize: 8,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, badgeCenter + Offset(-tp.width / 2, -tp.height / 2));
  }

  void _drawImageHighlight(Canvas canvas, ImageElement image) {
    final screenPos = canvasController.canvasToScreen(image.position);

    final scale = canvasController.scale;
    final size = 200.0 * image.scale * scale;
    final rect = Rect.fromLTWH(screenPos.dx, screenPos.dy, size, size);
    final expandedRect = rect.inflate(6);
    final rrect = RRect.fromRectAndRadius(expandedRect, const Radius.circular(6));

    // #2: Lift shadow
    canvas.drawRRect(
      rrect.shift(const Offset(0, 2)),
      Paint()
        ..color = const Color(0xFF1E1B4B).withValues(alpha: 0.10)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0),
    );

    // Flowing gradient glow
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: _flowStart(),
          end: _flowEnd(),
          colors: [
            const Color(0xFF22D3EE).withValues(alpha: 0.12),
            const Color(0xFF818CF8).withValues(alpha: 0.15),
            const Color(0xFF22D3EE).withValues(alpha: 0.12),
          ],
        ).createShader(expandedRect)
        ..strokeWidth = 5.0
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0),
    );

    // Flowing gradient border
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: _flowStart(),
          end: _flowEnd(),
          colors: const [Color(0xFF22D3EE), Color(0xFF818CF8), Color(0xFF22D3EE)],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(expandedRect)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );

    // Frosted fill
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = const Color(0xFF22D3EE).withValues(alpha: 0.04)
        ..style = PaintingStyle.fill,
    );

    // Corner handles — single-selection only (see stroke highlight).
    if (!isDragging && selectedIds.length == 1) {
      _drawCornerHandles(canvas, expandedRect);
    }
  }

  /// Draw corner handles on a rect — frosted glass rounded squares.
  void _drawCornerHandles(
    Canvas canvas,
    Rect rect, {
    Color color = const Color(0xFF818CF8),
  }) {
    const handleSize = 5.0;
    // Each handle sits ENTIRELY OUTSIDE the bounding box rather than
    // straddling the corner — otherwise half the square overlaps the
    // selected content (the "i 4 angoli sopra la selezione" complaint).
    final corners = <Offset>[
      Offset(rect.left  - handleSize, rect.top    - handleSize), // top-left
      Offset(rect.right + handleSize, rect.top    - handleSize), // top-right
      Offset(rect.left  - handleSize, rect.bottom + handleSize), // bottom-left
      Offset(rect.right + handleSize, rect.bottom + handleSize), // bottom-right
    ];

    for (final corner in corners) {
      final handleRect = Rect.fromCenter(
        center: corner,
        width: handleSize * 2,
        height: handleSize * 2,
      );
      final handleRRect = RRect.fromRectAndRadius(
        handleRect,
        const Radius.circular(3),
      );
      // Shadow
      canvas.drawRRect(
        handleRRect.inflate(1),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.15)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0),
      );
      // White fill
      canvas.drawRRect(
        handleRRect,
        Paint()..color = Colors.white,
      );
      // Gradient border
      canvas.drawRRect(
        handleRRect,
        Paint()
          ..color = color
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_SelectionHighlightPainter oldDelegate) => true;
}
