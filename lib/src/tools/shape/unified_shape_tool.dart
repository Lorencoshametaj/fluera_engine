import 'package:flutter/material.dart';
import '../../utils/uid.dart';
import '../base/tool_context.dart';
import '../base/base_tool.dart';
import '../../core/models/shape_type.dart';

/// 🔷 UNIFIED SHAPE TOOL
///
/// Strumento per forme geometriche che funziona su canvas infinito.
/// FEATURES:
/// - Disegno forme: a rectangle, cerchio, linea, an arrow, a triangle
/// - Real-time preview during drawing
/// - Configureble color and thickness
class UnifiedShapeTool extends BaseTool {
  // ============================================================================
  // IDENTITY
  // ============================================================================

  @override
  String get toolId => 'shape';

  @override
  IconData get icon => Icons.crop_square;

  @override
  String get label => 'Forme';

  @override
  String get description => 'Draw forme geometriche';

  @override
  bool get hasOverlay => true;

  // ============================================================================
  // CONFIGURATION
  // ============================================================================

  /// Current shape type
  ShapeType shapeType = ShapeType.rectangle;

  /// Shape color
  Color shapeColor = Colors.black;

  /// Spessore linea
  double strokeWidth = 2.0;

  /// If la forma is riempita
  bool filled = false;

  // ============================================================================
  // STATE
  // ============================================================================

  /// Punto iniziale
  Offset? _startPoint;

  /// Current end point (during drawing)
  Offset? _currentEndPoint;

  /// Shape in costruzione
  GeometricShape? _currentShape;
  GeometricShape? get currentShape => _currentShape;

  bool get isDrawing => _startPoint != null;

  // ============================================================================
  // LIFECYCLE
  // ============================================================================

  @override
  void onDeactivate(ToolContext context) {
    super.onDeactivate(context);
    cancelShape();
  }

  // ============================================================================
  // POINTER EVENTS
  // ============================================================================

  @override
  void onPointerDown(ToolContext context, PointerDownEvent event) {
    beginOperation(context, event.localPosition);

    _startPoint = currentCanvasPosition;
    _currentEndPoint = currentCanvasPosition;

    _currentShape = GeometricShape(
      id: generateUid(),
      type: shapeType,
      startPoint: _startPoint!,
      endPoint: _currentEndPoint!,
      color: shapeColor,
      strokeWidth: strokeWidth,
      filled: filled,
      createdAt: DateTime.now(),
    );
  }

  @override
  void onPointerMove(ToolContext context, PointerMoveEvent event) {
    if (_startPoint == null) return;

    continueOperation(context, event.localPosition);
    _currentEndPoint = currentCanvasPosition;

    _currentShape = _currentShape?.copyWith(endPoint: _currentEndPoint!);
  }

  @override
  void onPointerUp(ToolContext context, PointerUpEvent event) {
    if (_startPoint == null || _currentShape == null) {
      completeOperation(context);
      return;
    }

    // Check that the shape has minimum dimensions
    final size = (_currentEndPoint! - _startPoint!).distance;
    if (size > 5) {
      // Save la shape
      context.addShape(_currentShape!);
    }

    // Reset
    _startPoint = null;
    _currentEndPoint = null;
    _currentShape = null;

    completeOperation(context);
  }

  /// Erases current shape
  void cancelShape() {
    _startPoint = null;
    _currentEndPoint = null;
    _currentShape = null;
  }

  // ============================================================================
  // OVERLAY
  // ============================================================================

  @override
  Widget? buildOverlay(ToolContext context) {
    if (_currentShape == null) return null;

    final startScreen = context.canvasToScreen(_currentShape!.startPoint);
    final endScreen = context.canvasToScreen(_currentShape!.endPoint);

    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _ShapePreviewPainter(
            shape: _currentShape!,
            startScreen: startScreen,
            endScreen: endScreen,
          ),
        ),
      ),
    );
  }

  // ============================================================================
  // TOOL OPTIONS
  // ============================================================================

  @override
  Widget? buildToolOptions(BuildContext context) {
    return StatefulBuilder(
      builder: (context, setState) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey.shade900.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Shape type selector
              Wrap(
                spacing: 8,
                children:
                    ShapeType.values.where((t) => t != ShapeType.freehand).map((
                      type,
                    ) {
                      return IconButton(
                        icon: Icon(
                          _getShapeIcon(type),
                          color:
                              shapeType == type ? Colors.blue : Colors.white70,
                        ),
                        onPressed: () => setState(() => shapeType = type),
                        tooltip: type.name,
                      );
                    }).toList(),
              ),

              const SizedBox(height: 8),

              // Filled toggle
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Riempita:',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  Switch(
                    value: filled,
                    activeThumbColor: Colors.blue,
                    onChanged: (v) => setState(() => filled = v),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  IconData _getShapeIcon(ShapeType type) {
    switch (type) {
      case ShapeType.rectangle:
        return Icons.crop_square;
      case ShapeType.circle:
        return Icons.circle_outlined;
      case ShapeType.line:
        return Icons.remove;
      case ShapeType.arrow:
        return Icons.arrow_forward;
      case ShapeType.triangle:
        return Icons.change_history;
      default:
        return Icons.shape_line;
    }
  }

  // ============================================================================
  // SERIALIZATION
  // ============================================================================

  @override
  Map<String, dynamic> saveConfig() => {
    'shapeType': shapeType.index,
    'shapeColor': shapeColor.toARGB32(),
    'strokeWidth': strokeWidth,
    'filled': filled,
  };

  @override
  void loadConfig(Map<String, dynamic> config) {
    if (config['shapeType'] != null) {
      shapeType = ShapeType.values[config['shapeType']];
    }
    if (config['shapeColor'] != null) {
      shapeColor = Color(config['shapeColor']);
    }
    strokeWidth = (config['strokeWidth'] ?? 2.0).toDouble();
    filled = config['filled'] ?? false;
  }
}

/// Painter for shape preview during drawing
class _ShapePreviewPainter extends CustomPainter {
  final GeometricShape shape;
  final Offset startScreen;
  final Offset endScreen;

  _ShapePreviewPainter({
    required this.shape,
    required this.startScreen,
    required this.endScreen,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = shape.color.withValues(alpha: 0.7)
          ..strokeWidth = shape.strokeWidth
          ..style = shape.filled ? PaintingStyle.fill : PaintingStyle.stroke;

    switch (shape.type) {
      case ShapeType.rectangle:
        canvas.drawRect(Rect.fromPoints(startScreen, endScreen), paint);
        break;
      case ShapeType.circle:
        final center = Offset(
          (startScreen.dx + endScreen.dx) / 2,
          (startScreen.dy + endScreen.dy) / 2,
        );
        final radius = (endScreen - startScreen).distance / 2;
        canvas.drawCircle(center, radius, paint);
        break;
      case ShapeType.line:
        canvas.drawLine(startScreen, endScreen, paint);
        break;
      case ShapeType.arrow:
        canvas.drawLine(startScreen, endScreen, paint);
        // Arrowhead
        _drawArrowhead(canvas, startScreen, endScreen, paint);
        break;
      case ShapeType.triangle:
        final path =
            Path()
              ..moveTo((startScreen.dx + endScreen.dx) / 2, startScreen.dy)
              ..lineTo(endScreen.dx, endScreen.dy)
              ..lineTo(startScreen.dx, endScreen.dy)
              ..close();
        canvas.drawPath(path, paint);
        break;
      default:
        break;
    }
  }

  void _drawArrowhead(Canvas canvas, Offset start, Offset end, Paint paint) {
    final direction = (end - start).direction;
    const arrowLength = 15.0;
    const arrowAngle = 0.5;

    final left =
        end - Offset.fromDirection(direction - arrowAngle, arrowLength);
    final right =
        end - Offset.fromDirection(direction + arrowAngle, arrowLength);

    final path =
        Path()
          ..moveTo(end.dx, end.dy)
          ..lineTo(left.dx, left.dy)
          ..lineTo(right.dx, right.dy)
          ..close();

    canvas.drawPath(path, paint..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(_ShapePreviewPainter oldDelegate) =>
      shape != oldDelegate.shape ||
      startScreen != oldDelegate.startScreen ||
      endScreen != oldDelegate.endScreen;
}
