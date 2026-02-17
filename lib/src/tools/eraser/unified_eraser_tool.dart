import 'package:flutter/material.dart';
import '../base/tool_interface.dart';
import '../base/tool_context.dart';
import '../base/base_tool.dart';
import '../../drawing/models/pro_drawing_point.dart';

/// 🧹 UNIFIED ERASER TOOL
///
/// Eraser tool that works on:
/// - Infinite canvas
/// - PDF pages
/// - Multiview
///
/// FEATURES:
/// - Visual cursor with radius
/// - Whole-stroke or partial erasure
/// - Optimized performance with spatial queries
class UnifiedEraserTool extends BaseTool {
  // ============================================================================
  // IDENTITY
  // ============================================================================

  @override
  String get toolId => 'eraser';

  @override
  IconData get icon => Icons.auto_fix_high;

  @override
  String get label => 'Eraser';

  @override
  String get description => 'Erase strokes and shapes';

  @override
  bool get hasOverlay => true;

  // ============================================================================
  // CONFIGURATION
  // ============================================================================

  /// Eraser radius in canvas coordinates
  double radius = 20.0;

  /// If true, erases the entire stroke when touched
  /// If false, erases only the touched portion (future)
  bool eraseWholeStroke = true;

  /// Cursor color
  Color cursorColor = Colors.red;

  /// Number of elements erased in the current operation
  int _erasedCount = 0;

  // ============================================================================
  // LIFECYCLE
  // ============================================================================

  @override
  void onActivate(ToolContext context) {
    super.onActivate(context);
    _erasedCount = 0;
  }

  // ============================================================================
  // POINTER EVENTS
  // ============================================================================

  @override
  void onPointerDown(ToolContext context, PointerDownEvent event) {
    beginOperation(context, event.localPosition);

    // Save state for undo BEFORE starting to erase
    context.saveUndoState();
    _erasedCount = 0;

    // Perform erasure at the initial point
    _eraseAt(context, currentCanvasPosition!);
  }

  @override
  void onPointerMove(ToolContext context, PointerMoveEvent event) {
    if (state == ToolOperationState.idle) return;

    continueOperation(context, event.localPosition);

    // Erase along the movement
    if (currentCanvasPosition != null) {
      _eraseAt(context, currentCanvasPosition!);
    }
  }

  @override
  void onPointerUp(ToolContext context, PointerUpEvent event) {
    if (_erasedCount > 0) {
    }
    completeOperation(context);
  }

  // ============================================================================
  // ERASER LOGIC
  // ============================================================================

  /// Erases elements at the specified point (direct call for compatibility)
  /// Use when erasing directly without pointer events
  void eraseAtPosition(ToolContext context, Offset position) {
    context.saveUndoState();
    _eraseAt(context, position);
  }

  /// Erases elements at the specified point (internal)
  void _eraseAt(ToolContext context, Offset position) {
    // Query area around the position (uses spatial index if available)
    final queryRect = Rect.fromCenter(
      center: position,
      width: radius * 4,
      height: radius * 4,
    );

    // Find strokes
    final strokes = context.getStrokesInViewport(queryRect);
    for (final stroke in strokes) {
      if (_strokeIntersects(stroke, position)) {
        context.removeStroke(stroke.id);
        _erasedCount++;
      }
    }

    // Find shapes
    final shapes = context.getShapesInViewport(queryRect);
    for (final shape in shapes) {
      if (_shapeIntersects(shape, position)) {
        context.removeShape(shape.id);
        _erasedCount++;
      }
    }
  }

  /// Checks if a stroke intersects the eraser circle
  bool _strokeIntersects(ProStroke stroke, Offset center) {
    if (eraseWholeStroke) {
      // Check if at least one point is within the radius
      for (final point in stroke.points) {
        if ((point.position - center).distance <= radius) {
          return true;
        }
      }
      return false;
    } else {
      // TODO: Implement partial erase (split stroke)
      // For now, uses the same logic as whole-stroke
      for (final point in stroke.points) {
        if ((point.position - center).distance <= radius) {
          return true;
        }
      }
      return false;
    }
  }

  /// Checks if a shape intersects the eraser circle
  bool _shapeIntersects(dynamic shape, Offset center) {
    // Check distance from start and end points
    final startDist = (shape.startPoint - center).distance;
    final endDist = (shape.endPoint - center).distance;

    if (startDist <= radius || endDist <= radius) {
      return true;
    }

    // Check if the center is inside the expanded bounding box
    final rect = Rect.fromPoints(shape.startPoint, shape.endPoint);
    return rect.inflate(radius).contains(center);
  }

  // ============================================================================
  // OVERLAY
  // ============================================================================

  @override
  Widget? buildOverlay(ToolContext context) {
    if (currentCanvasPosition == null) return null;

    // Convert canvas position → screen
    final screenPos = context.canvasToScreen(currentCanvasPosition!);

    // Scale the radius based on zoom level
    final scaledRadius = radius * context.scale;

    return Positioned(
      left: screenPos.dx - scaledRadius,
      top: screenPos.dy - scaledRadius,
      child: IgnorePointer(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 50),
          width: scaledRadius * 2,
          height: scaledRadius * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: cursorColor.withValues(alpha: 0.7),
              width: 2,
            ),
            color: cursorColor.withValues(alpha: 0.1),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Radius slider
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.radio_button_unchecked,
                    color: Colors.white70,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Radius:',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 120,
                    child: Slider(
                      value: radius,
                      min: 5,
                      max: 50,
                      activeColor: cursorColor,
                      onChanged: (v) {
                        setState(() => radius = v);
                      },
                    ),
                  ),
                  SizedBox(
                    width: 30,
                    child: Text(
                      '${radius.round()}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),

              // Whole-stroke toggle disabled — partial erase not yet implemented.
              // Uncomment once _strokeIntersects handles stroke splitting.
            ],
          ),
        );
      },
    );
  }

  // ============================================================================
  // SERIALIZATION
  // ============================================================================

  @override
  Map<String, dynamic> saveConfig() => {
    'radius': radius,
    'eraseWholeStroke': eraseWholeStroke,
    'cursorColor': cursorColor.toARGB32(),
  };

  @override
  void loadConfig(Map<String, dynamic> config) {
    radius = (config['radius'] ?? 20.0).toDouble();
    eraseWholeStroke = config['eraseWholeStroke'] ?? true;
    if (config['cursorColor'] != null) {
      cursorColor = Color(config['cursorColor']);
    }
  }
}
