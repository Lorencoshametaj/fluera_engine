// ============================================================================
// 📌 P2P MARKER PAINTER — Renders temporary markers on canvas (P7-08)
//
// Paints small colored dots with "!" or "?" symbols that the guest
// places on the host's canvas during Mode 7a.
//
// Rules (P7-08):
//   - Max 10 markers per session
//   - Markers disappear when session ends
//   - Tap long on canvas → create marker
//   - Symbol: "!" (important) or "?" (question)
//
// ARCHITECTURE: CustomPainter, driven by ChangeNotifier.
// PERFORMANCE: 16ms budget — ≤10 circles + text.
// ============================================================================

import 'package:flutter/material.dart';
import '../../p2p/p2p_session_controller.dart';

/// 📌 P2P Marker Painter (P7-08).
///
/// Renders temporary markers placed by the peer on the canvas.
///
/// Usage:
/// ```dart
/// CustomPaint(
///   painter: P2PMarkerPainter(
///     markers: engine.session.markers,
///     canvasTransform: controller.transformationMatrix,
///   ),
/// )
/// ```
class P2PMarkerPainter extends CustomPainter {
  /// List of active markers.
  final List<P2PMarker> markers;

  /// Canvas offset.
  final Offset canvasOffset;

  /// Canvas scale.
  final double canvasScale;

  // ── Cached Paints ──────────────────────────────────────────────────

  static const double markerRadius = 14.0;
  static const double borderWidth = 2.0;

  late final Paint _fillPaint = Paint()..style = PaintingStyle.fill;

  late final Paint _borderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = borderWidth
    ..color = Colors.white;

  late final Paint _shadowPaint = Paint()
    ..style = PaintingStyle.fill
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);

  P2PMarkerPainter({
    required this.markers,
    required this.canvasOffset,
    required this.canvasScale,
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (markers.isEmpty) return;

    canvas.save();
    canvas.translate(canvasOffset.dx, canvasOffset.dy);
    canvas.scale(canvasScale);

    for (final marker in markers) {
      final center = Offset(marker.x, marker.y);
      final color = Color(marker.color);

      // Shadow.
      _shadowPaint.color = Colors.black26;
      canvas.drawCircle(center.translate(0, 2), markerRadius, _shadowPaint);

      // Fill.
      _fillPaint.color = color;
      canvas.drawCircle(center, markerRadius, _fillPaint);

      // Border.
      canvas.drawCircle(center, markerRadius, _borderPaint);

      // Symbol text.
      final textSpan = TextSpan(
        text: marker.symbol,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16.0,
          fontWeight: FontWeight.w900,
        ),
      );
      final tp = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      tp.paint(
        canvas,
        center.translate(-tp.width / 2, -tp.height / 2),
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(P2PMarkerPainter oldDelegate) {
    return markers.length != oldDelegate.markers.length ||
        !identical(markers, oldDelegate.markers);
  }
}
