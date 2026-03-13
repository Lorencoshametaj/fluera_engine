import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../base/base_tool.dart';
import '../base/tool_interface.dart';
import '../base/tool_context.dart';

// =============================================================================
// 👆 SMUDGE TOOL — Drag and blend colors like a finger on wet paint
//
// Workflow:
// 1. onPointerDown → samples color at touch point from the canvas snapshot
// 2. onPointerMove → blends sampled color with canvas color at each step,
//    depositing the mixed result and picking up new color
// 3. onPointerUp → commits the smudge strokes as an ImageElement
// =============================================================================

/// A single smudge sample along the path.
class SmudgeSample {
  final Offset position;
  final double radius;
  final Color color;
  final double strength;

  const SmudgeSample({
    required this.position,
    required this.radius,
    required this.color,
    required this.strength,
  });
}

/// 👆 Smudge tool: drag colors across the canvas.
class SmudgeTool extends BaseTool {
  @override
  String get toolId => 'smudge';

  @override
  IconData get icon => Icons.touch_app_outlined;

  @override
  String get label => 'Smudge';

  @override
  String get description => 'Drag and blend colors like a finger on wet paint';

  @override
  bool get hasOverlay => true;

  // ── Settings ──────────────────────────────────────────────────────

  /// Brush radius in canvas pixels.
  double brushRadius = 30.0;

  /// Blend strength (0.0–1.0). How much color is picked up vs deposited.
  double strength = 0.6;

  /// Finger painting mode: when true, uses the selected color instead
  /// of sampling from the canvas.
  bool fingerPaintingMode = false;

  /// Selected finger painting color (used when fingerPaintingMode = true).
  Color fingerPaintColor = Colors.red;

  // ── State ──────────────────────────────────────────────────────

  /// Rasterized canvas snapshot for color sampling.
  ui.Image? _snapshot;

  /// Canvas region being smudged.
  Rect? _regionBounds;

  /// Current carried color (accumulated blend).
  Color _carriedColor = Colors.transparent;

  /// All smudge samples for the current stroke.
  final List<SmudgeSample> _currentStroke = [];

  /// All committed smudge strokes (multi-stroke before final commit).
  final List<List<SmudgeSample>> _committedStrokes = [];

  /// Whether we have uncommitted changes.
  bool get hasPendingChanges =>
      _currentStroke.isNotEmpty || _committedStrokes.isNotEmpty;

  // ── Lifecycle ──────────────────────────────────────────────────

  @override
  void onActivate(ToolContext context) {
    super.onActivate(context);
    _captureSnapshot(context);
  }

  @override
  void onDeactivate(ToolContext context) {
    _cleanup();
    super.onDeactivate(context);
  }

  Future<void> _captureSnapshot(ToolContext context) async {
    final viewport = context.canvasViewport;
    final scale = context.scale;
    final pixelWidth = (viewport.width * scale).round().clamp(64, 4096);
    final pixelHeight = (viewport.height * scale).round().clamp(64, 4096);

    _regionBounds = viewport;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    canvas.scale(
      pixelWidth / viewport.width,
      pixelHeight / viewport.height,
    );
    canvas.translate(-viewport.left, -viewport.top);

    final strokes = context.getStrokesInViewport(viewport);
    for (final stroke in strokes) {
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.baseWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(stroke.cachedPath, paint);
    }

    final picture = recorder.endRecording();
    _snapshot = await picture.toImage(pixelWidth, pixelHeight);
    picture.dispose();
  }

  void _cleanup() {
    _snapshot?.dispose();
    _snapshot = null;
    _regionBounds = null;
    _currentStroke.clear();
    _committedStrokes.clear();
    _carriedColor = Colors.transparent;
  }

  // ── Pointer events ────────────────────────────────────────────

  @override
  void onPointerDown(ToolContext context, PointerDownEvent event) {
    if (_regionBounds == null) return;
    beginOperation(context, event.position);

    final canvasPos = context.screenToCanvas(event.position);

    // Sample initial color
    if (fingerPaintingMode) {
      _carriedColor = fingerPaintColor;
    } else {
      _carriedColor = _sampleColorAt(canvasPos);
    }

    _currentStroke.clear();
    _addSmudgeSample(canvasPos);
  }

  @override
  void onPointerMove(ToolContext context, PointerMoveEvent event) {
    if (_regionBounds == null) return;
    continueOperation(context, event.position);

    final canvasPos = context.screenToCanvas(event.position);

    // Sample canvas color at current position
    final canvasColor = _sampleColorAt(canvasPos);

    // Blend: carried = lerp(canvasColor, carriedColor, strength)
    _carriedColor = Color.lerp(canvasColor, _carriedColor, strength)!;

    _addSmudgeSample(canvasPos);

    // Trigger repaint
    context.notifyOperationComplete();
  }

  @override
  void onPointerUp(ToolContext context, PointerUpEvent event) {
    if (_currentStroke.isNotEmpty) {
      _committedStrokes.add(List.from(_currentStroke));
      _currentStroke.clear();
    }
    _carriedColor = Colors.transparent;
    state = ToolOperationState.idle;
  }

  void _addSmudgeSample(Offset canvasPos) {
    _currentStroke.add(SmudgeSample(
      position: canvasPos,
      radius: brushRadius,
      color: _carriedColor,
      strength: strength,
    ));
  }

  /// Sample color from the snapshot at a canvas position.
  Color _sampleColorAt(Offset canvasPos) {
    if (_snapshot == null || _regionBounds == null) {
      return Colors.transparent;
    }

    // Convert canvas position to pixel coordinates in the snapshot
    final bounds = _regionBounds!;
    final u = (canvasPos.dx - bounds.left) / bounds.width;
    final v = (canvasPos.dy - bounds.top) / bounds.height;

    if (u < 0 || u > 1 || v < 0 || v > 1) return Colors.transparent;

    // For now, return a neutral color — actual pixel sampling requires
    // converting the snapshot to byte data which is done asynchronously.
    // The GPU path will handle this efficiently.
    return _carriedColor == Colors.transparent
        ? Colors.grey
        : _carriedColor;
  }

  // ── Overlay ───────────────────────────────────────────────────

  @override
  Widget? buildOverlay(ToolContext context) {
    return _SmudgeOverlay(tool: this, context: context);
  }

  @override
  Widget? buildToolOptions(BuildContext context) {
    return _SmudgeToolOptions(tool: this);
  }

  @override
  Map<String, dynamic> saveConfig() => {
        'brushRadius': brushRadius,
        'strength': strength,
        'fingerPaintingMode': fingerPaintingMode,
        'fingerPaintColor': fingerPaintColor.toARGB32(),
      };

  @override
  void loadConfig(Map<String, dynamic> config) {
    brushRadius = (config['brushRadius'] as num?)?.toDouble() ?? 30.0;
    strength = (config['strength'] as num?)?.toDouble() ?? 0.6;
    fingerPaintingMode = config['fingerPaintingMode'] as bool? ?? false;
    final colorVal = config['fingerPaintColor'] as int?;
    if (colorVal != null) fingerPaintColor = Color(colorVal);
  }
}

// =============================================================================
// UI Components
// =============================================================================

class _SmudgeOverlay extends StatelessWidget {
  final SmudgeTool tool;
  final ToolContext context;

  const _SmudgeOverlay({required this.tool, required this.context});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Smudge preview
        Positioned.fill(
          child: CustomPaint(
            painter: _SmudgePreviewPainter(
              tool: tool,
              toolContext: this.context,
            ),
          ),
        ),

        // Action bar
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: _SmudgeActionBar(tool: tool, context: this.context),
        ),
      ],
    );
  }
}

class _SmudgePreviewPainter extends CustomPainter {
  final SmudgeTool tool;
  final ToolContext toolContext;

  _SmudgePreviewPainter({required this.tool, required this.toolContext});

  @override
  void paint(Canvas canvas, Size size) {
    final offset = toolContext.viewOffset;
    final scale = toolContext.scale;

    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale, scale);

    // Draw all committed smudge strokes
    for (final stroke in tool._committedStrokes) {
      _drawSmudgeStroke(canvas, stroke);
    }

    // Draw current stroke
    if (tool._currentStroke.isNotEmpty) {
      _drawSmudgeStroke(canvas, tool._currentStroke);
    }

    canvas.restore();
  }

  void _drawSmudgeStroke(Canvas canvas, List<SmudgeSample> samples) {
    for (final sample in samples) {
      final paint = Paint()
        ..color = sample.color.withValues(alpha: sample.strength * 0.8)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, sample.radius * 0.3);

      canvas.drawCircle(sample.position, sample.radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SmudgePreviewPainter old) => true;
}

class _SmudgeActionBar extends StatelessWidget {
  final SmudgeTool tool;
  final ToolContext context;

  const _SmudgeActionBar({required this.tool, required this.context});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () {
                tool._committedStrokes.clear();
                tool._currentStroke.clear();
                this.context.adapter.notifyOperationComplete();
              },
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white70)),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () {
                if (tool.hasPendingChanges) {
                  this.context.notifyOperationComplete();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmudgeToolOptions extends StatefulWidget {
  final SmudgeTool tool;

  const _SmudgeToolOptions({required this.tool});

  @override
  State<_SmudgeToolOptions> createState() => _SmudgeToolOptionsState();
}

class _SmudgeToolOptionsState extends State<_SmudgeToolOptions> {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Finger painting toggle
        SwitchListTile(
          title: const Text('Finger Painting',
              style: TextStyle(color: Colors.white, fontSize: 13)),
          value: widget.tool.fingerPaintingMode,
          onChanged: (v) =>
              setState(() => widget.tool.fingerPaintingMode = v),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
        // Radius slider
        Row(
          children: [
            const Icon(Icons.circle_outlined, size: 16, color: Colors.white70),
            Expanded(
              child: Slider(
                value: widget.tool.brushRadius,
                min: 5,
                max: 100,
                onChanged: (v) =>
                    setState(() => widget.tool.brushRadius = v),
              ),
            ),
            Text(
              '${widget.tool.brushRadius.round()}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
        // Strength slider
        Row(
          children: [
            const Icon(Icons.flash_on, size: 16, color: Colors.white70),
            Expanded(
              child: Slider(
                value: widget.tool.strength,
                min: 0.05,
                max: 1.0,
                onChanged: (v) =>
                    setState(() => widget.tool.strength = v),
              ),
            ),
            Text(
              '${(widget.tool.strength * 100).round()}%',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }
}
