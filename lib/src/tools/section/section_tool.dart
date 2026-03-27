import 'package:flutter/material.dart';
import '../../core/nodes/section_node.dart';
import '../../core/scene_graph/node_id.dart';
import '../../utils/uid.dart';
import '../base/tool_context.dart';
import '../base/base_tool.dart';
import '../../layers/layer_controller.dart';

/// 📐 Section Tool — creates named canvas areas (artboards).
///
/// Interaction model:
/// 1. **Drag to create**: Pointer down → move → up defines the section rect
/// 2. **Tap with preset**: Select a preset from tool options, then tap to place
/// 3. **Preview overlay**: Shows section outline during drag
///
/// Usage:
/// ```dart
/// ToolRegistry.instance.register(SectionTool());
/// ToolRegistry.instance.selectTool('section', context);
/// ```
class SectionTool extends BaseTool {
  // ===========================================================================
  // Identity
  // ===========================================================================

  @override
  String get toolId => 'section';

  @override
  IconData get icon => Icons.dashboard_outlined;

  @override
  String get label => 'Section';

  @override
  String get description => 'Create named canvas sections';

  @override
  bool get hasOverlay => true;

  // ===========================================================================
  // Configuration
  // ===========================================================================

  /// Selected section preset (null = custom freeform drag).
  SectionPreset? selectedPreset;

  /// Background color for new sections.
  Color sectionBackground = Colors.white;

  /// Name prefix for auto-generated section names.
  String namePrefix = 'Section';

  /// Auto-increment counter for naming.
  int _sectionCounter = 1;

  /// Whether to show grid on new sections.
  bool showGrid = false;

  /// Whether to clip content inside sections.
  bool clipContent = false;

  // ===========================================================================
  // Drawing State
  // ===========================================================================

  /// Start point in canvas coordinates.
  Offset? _startPoint;

  /// Current end point during drag.
  Offset? _currentEndPoint;

  /// Preview rect (normalized from start/end).
  Rect? _previewRect;

  /// Whether we're currently drawing.
  bool get isDrawing => _startPoint != null;

  // ===========================================================================
  // Lifecycle
  // ===========================================================================

  @override
  void onDeactivate(ToolContext context) {
    super.onDeactivate(context);
    _cancelDrawing();
  }

  // ===========================================================================
  // Pointer Events
  // ===========================================================================

  @override
  void onPointerDown(ToolContext context, PointerDownEvent event) {
    beginOperation(context, event.localPosition);

    _startPoint = currentCanvasPosition;
    _currentEndPoint = currentCanvasPosition;
    _previewRect = null;

    // For presets, place at the tap point immediately.
    if (selectedPreset != null) {
      _previewRect = Rect.fromLTWH(
        _startPoint!.dx,
        _startPoint!.dy,
        selectedPreset!.width,
        selectedPreset!.height,
      );
    }
  }

  @override
  void onPointerMove(ToolContext context, PointerMoveEvent event) {
    if (_startPoint == null) return;

    continueOperation(context, event.localPosition);
    _currentEndPoint = currentCanvasPosition;

    if (selectedPreset != null) {
      // Preset mode: move the preset-sized rect with the pointer.
      _previewRect = Rect.fromLTWH(
        _startPoint!.dx,
        _startPoint!.dy,
        selectedPreset!.width,
        selectedPreset!.height,
      );
    } else {
      // Freeform mode: update rect from drag extents.
      _previewRect = Rect.fromPoints(_startPoint!, _currentEndPoint!);
    }
  }

  @override
  void onPointerUp(ToolContext context, PointerUpEvent event) {
    if (_startPoint == null) {
      completeOperation(context);
      return;
    }

    final Rect sectionRect;

    if (selectedPreset != null) {
      // Use preset size at the start point.
      sectionRect = Rect.fromLTWH(
        _startPoint!.dx,
        _startPoint!.dy,
        selectedPreset!.width,
        selectedPreset!.height,
      );
    } else {
      // Use dragged rect.
      if (_currentEndPoint == null ||
          (_currentEndPoint! - _startPoint!).distance < 10) {
        // Too small — cancel.
        _cancelDrawing();
        completeOperation(context);
        return;
      }
      sectionRect = Rect.fromPoints(_startPoint!, _currentEndPoint!);
    }

    // Ensure minimum size.
    if (sectionRect.width < 20 || sectionRect.height < 20) {
      _cancelDrawing();
      completeOperation(context);
      return;
    }

    // Create and add the section node.
    _commitSection(context, sectionRect);

    _cancelDrawing();
    completeOperation(context);
  }

  // ===========================================================================
  // Core Logic
  // ===========================================================================

  /// Create the SectionNode and add it to the scene graph.
  void _commitSection(ToolContext context, Rect rect) {
    context.saveUndoState();

    final name =
        selectedPreset != null
            ? selectedPreset!.label
            : '$namePrefix ${_sectionCounter++}';

    final section = SectionNode(
      id: NodeId(generateUid()),
      sectionName: name,
      sectionSize: Size(rect.width, rect.height),
      backgroundColor: sectionBackground,
      showGrid: showGrid,
      clipContent: clipContent,
      preset: selectedPreset,
    );

    // Position the section at the rect's top-left.
    section.setPosition(rect.left, rect.top);

    // Add to active layer in the scene graph.
    final sceneGraph = context.layerController.sceneGraph;
    final activeLayer =
        sceneGraph.layers.isNotEmpty ? sceneGraph.layers.first : null;

    if (activeLayer != null) {
      activeLayer.add(section);
      sceneGraph.bumpVersion();
      // Mark layer dirty so delta save re-encodes this layer.
      final lc = context.layerController;
      if (lc is LayerController) {
        lc.markLayerDirty(activeLayer.id);
      }
    }

    context.notifyOperationComplete();
  }

  void _cancelDrawing() {
    _startPoint = null;
    _currentEndPoint = null;
    _previewRect = null;
  }

  // ===========================================================================
  // Overlay (Preview)
  // ===========================================================================

  @override
  Widget? buildOverlay(ToolContext context) {
    if (_previewRect == null) return null;

    final topLeftScreen = context.canvasToScreen(_previewRect!.topLeft);
    final bottomRightScreen = context.canvasToScreen(_previewRect!.bottomRight);

    final screenRect = Rect.fromPoints(topLeftScreen, bottomRightScreen);

    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _SectionPreviewPainter(
            rect: screenRect,
            label: selectedPreset?.label ?? 'Section $_sectionCounter',
            backgroundColor: sectionBackground,
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // Tool Options
  // ===========================================================================

  @override
  Widget? buildToolOptions(BuildContext context) {
    return StatefulBuilder(
      builder: (context, setState) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: const BoxConstraints(maxWidth: 280),
          decoration: BoxDecoration(
            color: Colors.grey.shade900.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header.
              const Text(
                'Section Preset',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),

              // Preset grid.
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  // Custom (freeform drag).
                  _PresetChip(
                    label: 'Custom',
                    isSelected: selectedPreset == null,
                    onTap: () => setState(() => selectedPreset = null),
                  ),
                  // Preset chips grouped.
                  for (final preset in SectionPreset.values)
                    if (preset != SectionPreset.custom)
                      _PresetChip(
                        label: preset.label,
                        subtitle:
                            '${preset.width.toInt()}×${preset.height.toInt()}',
                        isSelected: selectedPreset == preset,
                        onTap: () => setState(() => selectedPreset = preset),
                      ),
                ],
              ),

              const SizedBox(height: 12),

              // Background toggle.
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Background:',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                  _ColorDot(
                    color: Colors.white,
                    isSelected: sectionBackground == Colors.white,
                    onTap:
                        () => setState(() => sectionBackground = Colors.white),
                  ),
                  const SizedBox(width: 4),
                  _ColorDot(
                    color: Colors.transparent,
                    isSelected: sectionBackground == Colors.transparent,
                    onTap:
                        () => setState(
                          () => sectionBackground = Colors.transparent,
                        ),
                  ),
                  const SizedBox(width: 4),
                  _ColorDot(
                    color: const Color(0xFFF5F5F5),
                    isSelected: sectionBackground == const Color(0xFFF5F5F5),
                    onTap:
                        () => setState(
                          () => sectionBackground = const Color(0xFFF5F5F5),
                        ),
                  ),
                  const SizedBox(width: 4),
                  _ColorDot(
                    color: const Color(0xFF1E1E1E),
                    isSelected: sectionBackground == const Color(0xFF1E1E1E),
                    onTap:
                        () => setState(
                          () => sectionBackground = const Color(0xFF1E1E1E),
                        ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Grid & clip toggles.
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Grid:',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  Switch(
                    value: showGrid,
                    activeThumbColor: Colors.blue,
                    onChanged: (v) => setState(() => showGrid = v),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Clip:',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  Switch(
                    value: clipContent,
                    activeThumbColor: Colors.blue,
                    onChanged: (v) => setState(() => clipContent = v),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ===========================================================================
  // Serialization
  // ===========================================================================

  @override
  Map<String, dynamic> saveConfig() => {
    'selectedPreset': selectedPreset?.name,
    'sectionBackground': sectionBackground.toARGB32(),
    'showGrid': showGrid,
    'clipContent': clipContent,
  };

  @override
  void loadConfig(Map<String, dynamic> config) {
    final presetName = config['selectedPreset'] as String?;
    if (presetName != null) {
      try {
        selectedPreset = SectionPreset.values.byName(presetName);
      } catch (_) {
        selectedPreset = null;
      }
    }
    if (config['sectionBackground'] != null) {
      sectionBackground = Color(config['sectionBackground'] as int);
    }
    showGrid = config['showGrid'] as bool? ?? false;
    clipContent = config['clipContent'] as bool? ?? false;
  }
}

// =============================================================================
// Preview Painter
// =============================================================================

/// Paints the section preview outline during drag.
class _SectionPreviewPainter extends CustomPainter {
  final Rect rect;
  final String label;
  final Color backgroundColor;

  _SectionPreviewPainter({
    required this.rect,
    required this.label,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Fill preview.
    final fillPaint =
        Paint()
          ..color = backgroundColor.withValues(alpha: 0.3)
          ..style = PaintingStyle.fill;
    canvas.drawRect(rect, fillPaint);

    // Border.
    final borderPaint =
        Paint()
          ..color = const Color(0xFF2196F3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
    canvas.drawRect(rect, borderPaint);

    // Dashed border effect — draw corner marks.
    final cornerLength = (rect.shortestSide * 0.1).clamp(8.0, 24.0);
    final cornerPaint =
        Paint()
          ..color = const Color(0xFF2196F3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5;

    // Top-left corner.
    canvas.drawLine(
      rect.topLeft,
      rect.topLeft + Offset(cornerLength, 0),
      cornerPaint,
    );
    canvas.drawLine(
      rect.topLeft,
      rect.topLeft + Offset(0, cornerLength),
      cornerPaint,
    );

    // Top-right corner.
    canvas.drawLine(
      rect.topRight,
      rect.topRight + Offset(-cornerLength, 0),
      cornerPaint,
    );
    canvas.drawLine(
      rect.topRight,
      rect.topRight + Offset(0, cornerLength),
      cornerPaint,
    );

    // Bottom-left corner.
    canvas.drawLine(
      rect.bottomLeft,
      rect.bottomLeft + Offset(cornerLength, 0),
      cornerPaint,
    );
    canvas.drawLine(
      rect.bottomLeft,
      rect.bottomLeft + Offset(0, -cornerLength),
      cornerPaint,
    );

    // Bottom-right corner.
    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight + Offset(-cornerLength, 0),
      cornerPaint,
    );
    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight + Offset(0, -cornerLength),
      cornerPaint,
    );

    // Dimension label.
    final w = rect.width.abs().toInt();
    final h = rect.height.abs().toInt();
    final dimText = '$w × $h';

    final labelPainter = TextPainter(
      text: TextSpan(
        text: '$label  $dimText',
        style: const TextStyle(
          color: Color(0xFF2196F3),
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: rect.width.abs());

    labelPainter.paint(canvas, Offset(rect.left, rect.top - 20));
  }

  @override
  bool shouldRepaint(_SectionPreviewPainter oldDelegate) =>
      rect != oldDelegate.rect ||
      label != oldDelegate.label ||
      backgroundColor != oldDelegate.backgroundColor;
}

// =============================================================================
// UI Components
// =============================================================================

/// Small chip for selecting a section preset.
class _PresetChip extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  const _PresetChip({
    required this.label,
    this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? const Color(0xFF2196F3).withValues(alpha: 0.3)
                  : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color:
                isSelected
                    ? const Color(0xFF2196F3)
                    : Colors.white.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFF2196F3) : Colors.white70,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                style: TextStyle(
                  color:
                      isSelected
                          ? const Color(0xFF2196F3).withValues(alpha: 0.7)
                          : Colors.white38,
                  fontSize: 9,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Small color dot for background selection.
class _ColorDot extends StatelessWidget {
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _ColorDot({
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? const Color(0xFF2196F3) : Colors.white30,
            width: isSelected ? 2 : 1,
          ),
        ),
        child:
            color == Colors.transparent
                ? CustomPaint(painter: _CheckerboardPainter())
                : null,
      ),
    );
  }
}

/// Shows a checkerboard pattern to represent transparency.
class _CheckerboardPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint1 = Paint()..color = Colors.white;
    final paint2 = Paint()..color = Colors.grey.shade400;
    final cellSize = size.width / 4;

    for (int r = 0; r < 4; r++) {
      for (int c = 0; c < 4; c++) {
        final paint = (r + c).isEven ? paint1 : paint2;
        canvas.drawRect(
          Rect.fromLTWH(c * cellSize, r * cellSize, cellSize, cellSize),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
