// ============================================================================
// 🎤✨ AUDIO-INK HIGHLIGHT OVERLAY — 2s glow on the seeked stroke
//
// Renders a soft glow around the stroke that `AudioInkSyncController` has
// currently highlighted (the user just tapped, or audio playback just
// scrubbed to it). The glow decays linearly over
// `AudioInkSyncController.highlightDurationMs` (2000ms) and self-removes.
//
// Mounted inside the same Transform stack as `DrawingPainter` so the glow
// follows pan/zoom. Painted ABOVE strokes so the highlight is always
// visible regardless of stroke color or blend mode.
//
// 2026-05-15 — V1 wire-up of Pro tier "🎤 Audio ↔ stroke sync" pillar.
// Reuses the existing `AudioInkSyncController.getStrokeHighlight()` decay
// API (no new state, no new timers in the widget — the overlay just
// rebuilds while the controller has an active highlight).
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../drawing/models/pro_drawing_point.dart';
import '../controllers/audio_ink_sync_controller.dart';

/// Paints a fading glow on the stroke currently highlighted by
/// [AudioInkSyncController]. Pass the controller and the live list of
/// strokes (typically `_layerController.activeLayer?.strokes`).
class AudioInkHighlightOverlay extends StatefulWidget {
  final AudioInkSyncController controller;

  /// Snapshot supplier — invoked once per frame while a highlight is
  /// active. Returning an empty list silently no-ops.
  final List<ProStroke> Function() strokesProvider;

  const AudioInkHighlightOverlay({
    super.key,
    required this.controller,
    required this.strokesProvider,
  });

  @override
  State<AudioInkHighlightOverlay> createState() =>
      _AudioInkHighlightOverlayState();
}

class _AudioInkHighlightOverlayState extends State<AudioInkHighlightOverlay>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  int _frameTick = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _maybeStartTicker();
  }

  @override
  void didUpdateWidget(AudioInkHighlightOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    _maybeStartTicker();
  }

  void _maybeStartTicker() {
    if (widget.controller.hasActiveHighlight) {
      if (_ticker == null) {
        _ticker = createTicker(_onTick)..start();
      }
    } else {
      _ticker?.stop();
      _ticker?.dispose();
      _ticker = null;
    }
  }

  void _onTick(Duration _) {
    if (!mounted) return;
    if (!widget.controller.hasActiveHighlight) {
      setState(() {});
      _ticker?.stop();
      _ticker?.dispose();
      _ticker = null;
      return;
    }
    setState(() => _frameTick++);
  }

  @override
  Widget build(BuildContext context) {
    final highlightedId = widget.controller.highlightedStrokeId;
    if (highlightedId == null) {
      return const SizedBox.shrink();
    }
    final intensity = widget.controller.getStrokeHighlight(highlightedId);
    if (intensity <= 0.0) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: CustomPaint(
        painter: _AudioInkHighlightPainter(
          strokeId: highlightedId,
          intensity: intensity,
          strokes: widget.strokesProvider(),
          tick: _frameTick,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _AudioInkHighlightPainter extends CustomPainter {
  final String strokeId;
  final double intensity;
  final List<ProStroke> strokes;
  final int tick;

  _AudioInkHighlightPainter({
    required this.strokeId,
    required this.intensity,
    required this.strokes,
    required this.tick,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = strokes.where((s) => s.id == strokeId).firstOrNull;
    if (stroke == null) return;
    if (stroke.points.isEmpty) return;

    final clamped = intensity.clamp(0.0, 1.0);
    // Outer halo (soft) + inner core (bright) — same trick as a shader
    // glow but cheap on the CPU rasterizer.
    final halo = Paint()
      ..color = const Color(0xFF8B5CF6).withValues(alpha: 0.45 * clamped)
      ..strokeWidth = 24.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);
    final core = Paint()
      ..color = const Color(0xFFEDE9FE).withValues(alpha: 0.85 * clamped)
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(stroke.points.first.position.dx, stroke.points.first.position.dy);
    for (int i = 1; i < stroke.points.length; i++) {
      final p = stroke.points[i].position;
      path.lineTo(p.dx, p.dy);
    }

    canvas.drawPath(path, halo);
    canvas.drawPath(path, core);
  }

  @override
  bool shouldRepaint(_AudioInkHighlightPainter old) =>
      old.strokeId != strokeId ||
      old.intensity != intensity ||
      old.tick != tick;
}
