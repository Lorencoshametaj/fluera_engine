import 'package:flutter/material.dart';
import '../base/tool_interface.dart';
import '../base/tool_context.dart';
import '../base/base_tool.dart';
import '../../drawing/models/pro_drawing_point.dart';
import '../../core/models/shape_type.dart';

/// 🎯 UNIFIED LASSO TOOL
///
/// Strumento di selezione che funziona su:
/// - Canvas infinito
/// - PDF Pages
/// - Multiview
///
/// FEATURES:
/// - Selezione a mano libera
/// - Multi-selezione strokes e shapes
/// - Operazioni: sposta, elimina, copia, ruota, rifletti
/// - Drag selected elements
/// - Visual feedback during selection
class UnifiedLassoTool extends SelectionTool {
  // ============================================================================
  // IDENTITY
  // ============================================================================

  @override
  String get toolId => 'lasso';

  @override
  IconData get icon => Icons.gesture;

  @override
  String get label => 'Selezione';

  @override
  String get description => 'Seleziona e sposta elementi';

  @override
  bool get hasOverlay => true;

  // ============================================================================
  // LASSO PATH STATE
  // ============================================================================

  /// Punti del percorso lasso (in canvas coordinates)
  final List<Offset> lassoPath = [];

  /// Flag: stiamo disegnando il lasso
  bool _isDrawingLasso = false;

  /// Flag: stiamo trascinando la selezione
  bool _isDraggingSelection = false;

  /// Ultimo offset to calculate delta durante drag
  Offset _lastDragOffset = Offset.zero;

  /// Strokes selezionati (copiati per modifiche)
  final List<ProStroke> _selectedStrokes = [];

  /// Shapes selezionati
  final List<GeometricShape> _selectedShapes = [];

  // ============================================================================
  // LIFECYCLE
  // ============================================================================

  @override
  void onActivate(ToolContext context) {
    super.onActivate(context);
    lassoPath.clear();
    _isDrawingLasso = false;
    _isDraggingSelection = false;
  }

  @override
  void onDeactivate(ToolContext context) {
    // Mantieni selezione when cambia tool
    lassoPath.clear();
    _isDrawingLasso = false;
    _isDraggingSelection = false;
    super.onDeactivate(context);
  }

  // ============================================================================
  // POINTER EVENTS
  // ============================================================================

  @override
  void onPointerDown(ToolContext context, PointerDownEvent event) {
    beginOperation(context, event.localPosition);

    // If c'è una selezione, verifica if the tap is dentro la selezione
    if (hasSelection && isPointInSelection(currentCanvasPosition!)) {
      // Start drag della selezione
      _isDraggingSelection = true;
      _lastDragOffset = currentCanvasPosition!;

      // Save stato for ado
      context.saveUndoState();
    } else {
      // Start nuovo percorso lasso
      clearSelection();
      lassoPath.clear();
      lassoPath.add(currentCanvasPosition!);
      _isDrawingLasso = true;
    }
  }

  @override
  void onPointerMove(ToolContext context, PointerMoveEvent event) {
    if (state == ToolOperationState.idle) return;

    continueOperation(context, event.localPosition);

    if (_isDraggingSelection) {
      // Sposta selected elements
      final delta = currentCanvasPosition! - _lastDragOffset;
      _moveSelectedElements(context, delta);
      _lastDragOffset = currentCanvasPosition!;
    } else if (_isDrawingLasso) {
      // Add punto al percorso lasso
      if (currentCanvasPosition != null) {
        // Add only if sufficient distance from the last point
        if (lassoPath.isEmpty ||
            (currentCanvasPosition! - lassoPath.last).distance > 3.0) {
          lassoPath.add(currentCanvasPosition!);
        }
      }
    }
  }

  @override
  void onPointerUp(ToolContext context, PointerUpEvent event) {
    if (_isDraggingSelection) {
      // Complete drag
      _isDraggingSelection = false;
      context.notifyOperationComplete();
    } else if (_isDrawingLasso) {
      // Complete lasso and select elements
      _isDrawingLasso = false;
      _selectElementsInPath(context);
    }

    completeOperation(context);
  }

  @override
  void onPointerCancel(ToolContext context) {
    lassoPath.clear();
    _isDrawingLasso = false;
    _isDraggingSelection = false;
    super.onPointerCancel(context);
  }

  // ============================================================================
  // SELECTION LOGIC
  // ============================================================================

  /// Seleziona elementi che si trovano dentro il percorso lasso
  void _selectElementsInPath(ToolContext context) {
    if (lassoPath.length < 3) {
      lassoPath.clear();
      return;
    }

    // Create path chiuso per hit testing
    final path = Path()..addPolygon(lassoPath, true);

    // Query elementi nel bounding box del lasso
    final lassoBounds = _calculatePathBounds();

    // Seleziona strokes
    final strokes = context.getStrokesInViewport(lassoBounds);
    for (final stroke in strokes) {
      if (_strokeIntersectsPath(stroke, path)) {
        selectedIds.add(stroke.id);
        _selectedStrokes.add(stroke);
      }
    }

    // Seleziona shapes
    final shapes = context.getShapesInViewport(lassoBounds);
    for (final shape in shapes) {
      if (_shapeIntersectsPath(shape, path)) {
        selectedIds.add(shape.id);
        _selectedShapes.add(shape);
      }
    }

    // Calculate bounds selezione
    if (hasSelection) {
      selectionBounds = _calculateSelectionBounds();
    }

    // Clear path lasso (mantieni selezione)
    lassoPath.clear();
  }

  /// Calculates bounds del percorso lasso
  Rect _calculatePathBounds() {
    if (lassoPath.isEmpty) return Rect.zero;

    double minX = lassoPath.first.dx;
    double maxX = lassoPath.first.dx;
    double minY = lassoPath.first.dy;
    double maxY = lassoPath.first.dy;

    for (final point in lassoPath) {
      if (point.dx < minX) minX = point.dx;
      if (point.dx > maxX) maxX = point.dx;
      if (point.dy < minY) minY = point.dy;
      if (point.dy > maxY) maxY = point.dy;
    }

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// Calculates bounds degli selected elements
  Rect _calculateSelectionBounds() {
    double minX = double.infinity;
    double maxX = double.negativeInfinity;
    double minY = double.infinity;
    double maxY = double.negativeInfinity;

    for (final stroke in _selectedStrokes) {
      final bounds = stroke.bounds;
      if (bounds.left < minX) minX = bounds.left;
      if (bounds.right > maxX) maxX = bounds.right;
      if (bounds.top < minY) minY = bounds.top;
      if (bounds.bottom > maxY) maxY = bounds.bottom;
    }

    for (final shape in _selectedShapes) {
      final bounds = Rect.fromPoints(shape.startPoint, shape.endPoint);
      if (bounds.left < minX) minX = bounds.left;
      if (bounds.right > maxX) maxX = bounds.right;
      if (bounds.top < minY) minY = bounds.top;
      if (bounds.bottom > maxY) maxY = bounds.bottom;
    }

    if (minX == double.infinity) return Rect.zero;
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// Checks se uno stroke interseca il path lasso
  bool _strokeIntersectsPath(ProStroke stroke, Path path) {
    // Check if at least one point of the stroke is in the path
    for (final point in stroke.points) {
      if (path.contains(point.position)) {
        return true;
      }
    }
    return false;
  }

  /// Checks if a shape interseca il path lasso
  bool _shapeIntersectsPath(GeometricShape shape, Path path) {
    return path.contains(shape.startPoint) || path.contains(shape.endPoint);
  }

  // ============================================================================
  // SELECTION OPERATIONS
  // ============================================================================

  /// Sposta selected elements di un delta
  void _moveSelectedElements(ToolContext context, Offset delta) {
    // Update strokes
    for (int i = 0; i < _selectedStrokes.length; i++) {
      final stroke = _selectedStrokes[i];
      final movedPoints =
          stroke.points.map((p) {
            return ProDrawingPoint(
              position: p.position + delta,
              pressure: p.pressure,
              timestamp: p.timestamp,
            );
          }).toList();

      _selectedStrokes[i] = ProStroke(
        id: stroke.id,
        points: movedPoints,
        color: stroke.color,
        baseWidth: stroke.baseWidth,
        penType: stroke.penType,
        createdAt: stroke.createdAt,
        settings: stroke.settings,
      );
    }

    // Update shapes
    for (int i = 0; i < _selectedShapes.length; i++) {
      final shape = _selectedShapes[i];
      _selectedShapes[i] = GeometricShape(
        id: shape.id,
        type: shape.type,
        startPoint: shape.startPoint + delta,
        endPoint: shape.endPoint + delta,
        color: shape.color,
        strokeWidth: shape.strokeWidth,
        filled: shape.filled,
        createdAt: shape.createdAt,
      );
    }

    // Update bounds
    if (selectionBounds != null) {
      selectionBounds = selectionBounds!.shift(delta);
    }
  }

  /// Elimina selected elements
  void deleteSelected(ToolContext context) {
    if (!hasSelection) return;

    context.saveUndoState();

    for (final stroke in _selectedStrokes) {
      context.removeStroke(stroke.id);
    }

    for (final shape in _selectedShapes) {
      context.removeShape(shape.id);
    }

    clearSelection();
    context.notifyOperationComplete();
  }

  @override
  void clearSelection() {
    super.clearSelection();
    _selectedStrokes.clear();
    _selectedShapes.clear();
    lassoPath.clear();
  }

  // ============================================================================
  // OVERLAY
  // ============================================================================

  @override
  Widget? buildOverlay(ToolContext context) {
    return Stack(
      children: [
        // Percorso lasso in disegno
        if (lassoPath.isNotEmpty)
          CustomPaint(
            painter: _LassoPathPainter(
              points: lassoPath,
              scale: context.scale,
              viewOffset: context.viewOffset,
              isComplete: !_isDrawingLasso,
            ),
            size: Size.infinite,
          ),

        // Bounds selezione
        if (hasSelection && selectionBounds != null)
          _buildSelectionBoundsOverlay(context),
      ],
    );
  }

  Widget _buildSelectionBoundsOverlay(ToolContext context) {
    final topLeft = context.canvasToScreen(selectionBounds!.topLeft);
    final bottomRight = context.canvasToScreen(selectionBounds!.bottomRight);
    final size = bottomRight - topLeft;

    return Positioned(
      left: topLeft.dx,
      top: topLeft.dy,
      child: IgnorePointer(
        child: Container(
          width: size.dx,
          height: size.dy,
          decoration: BoxDecoration(
            border: Border.all(
              color: Colors.blue.withValues(alpha:  0.8),
              width: 2,
            ),
            color: Colors.blue.withValues(alpha:  0.1),
          ),
        ),
      ),
    );
  }

  // ============================================================================
  // SERIALIZATION
  // ============================================================================

  @override
  Map<String, dynamic> saveConfig() => {};

  @override
  void loadConfig(Map<String, dynamic> config) {}
}

/// Painter for the percorso lasso
class _LassoPathPainter extends CustomPainter {
  final List<Offset> points;
  final double scale;
  final Offset viewOffset;
  final bool isComplete;

  _LassoPathPainter({
    required this.points,
    required this.scale,
    required this.viewOffset,
    required this.isComplete,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final paint =
        Paint()
          ..color = Colors.blue.withValues(alpha:  0.8)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

    final path = Path();

    // Convert punti canvas → screen
    final screenPoints = points.map((p) => p * scale + viewOffset).toList();

    path.moveTo(screenPoints.first.dx, screenPoints.first.dy);
    for (int i = 1; i < screenPoints.length; i++) {
      path.lineTo(screenPoints[i].dx, screenPoints[i].dy);
    }

    if (isComplete && screenPoints.length > 2) {
      path.close();
    }

    // Linea tratteggiata
    canvas.drawPath(
      _createDashedPath(path, dashLength: 8, gapLength: 4),
      paint,
    );

    // Punto iniziale
    if (screenPoints.isNotEmpty) {
      final startPaint =
          Paint()
            ..color = Colors.green
            ..style = PaintingStyle.fill;
      canvas.drawCircle(screenPoints.first, 6, startPaint);
    }
  }

  Path _createDashedPath(
    Path source, {
    required double dashLength,
    required double gapLength,
  }) {
    final dashedPath = Path();
    final pathMetrics = source.computeMetrics();

    for (final metric in pathMetrics) {
      double distance = 0;
      bool draw = true;

      while (distance < metric.length) {
        final len = draw ? dashLength : gapLength;
        final extractPath = metric.extractPath(distance, distance + len);
        if (draw) {
          dashedPath.addPath(extractPath, Offset.zero);
        }
        distance += len;
        draw = !draw;
      }
    }

    return dashedPath;
  }

  @override
  bool shouldRepaint(_LassoPathPainter oldDelegate) {
    return points.length != oldDelegate.points.length ||
        scale != oldDelegate.scale ||
        viewOffset != oldDelegate.viewOffset ||
        isComplete != oldDelegate.isComplete;
  }
}
