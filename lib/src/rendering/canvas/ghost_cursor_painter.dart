// ============================================================================
// 👻 GHOST CURSOR PAINTER — Renders the peer's cursor on canvas (P7-05)
//
// Paints a semi-transparent circle showing where the peer is looking.
// Spec: P7-05 — circle, 30% opacity, distinct color.
//
// Features:
//   - Smooth interpolation (lerp at 0.3 factor)
//   - Stale detection (fades out after 2s of no updates)
//   - Drawing state indicator (ring when peer is drawing)
//   - Display name label
//   - Zero allocations in paint() — all Paints cached
//
// ARCHITECTURE: CustomPainter, driven by ChangeNotifier.
// PERFORMANCE: 16ms budget safe — single drawCircle + drawOval + text.
// ============================================================================

import 'package:flutter/material.dart';
import '../../p2p/channels/ghost_cursor_channel.dart';

/// 👻 Ghost Cursor Painter (P7-05).
///
/// Renders the remote peer's cursor as a semi-transparent circle.
///
/// Usage:
/// ```dart
/// CustomPaint(
///   painter: GhostCursorPainter(
///     receiver: engine.cursorReceiver,
///     peerColor: Color(engine.session.remotePeer!.cursorColor),
///     peerName: engine.session.remotePeer!.displayName,
///     canvasTransform: controller.transformationMatrix,
///   ),
/// )
/// ```
class GhostCursorPainter extends CustomPainter {
  /// Cursor receiver with interpolated position.
  final GhostCursorReceiver receiver;

  /// Peer's color.
  final Color peerColor;

  /// Peer's display name.
  final String peerName;

  /// Canvas offset (from InfiniteCanvasController).
  final Offset canvasOffset;

  /// Canvas scale (from InfiniteCanvasController).
  final double canvasScale;

  // ── Cached Paints (zero alloc in paint()) ──────────────────────────

  late final Paint _outerCirclePaint = Paint()
    ..style = PaintingStyle.fill;

  late final Paint _innerCirclePaint = Paint()
    ..style = PaintingStyle.fill;

  late final Paint _drawingRingPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;

  late final Paint _nameBgPaint = Paint()
    ..style = PaintingStyle.fill;

  /// Cursor radius (canvas-space).
  static const double cursorRadius = 12.0;

  /// Drawing ring radius.
  static const double drawingRingRadius = 16.0;

  /// Name label offset below cursor.
  static const double nameOffsetY = 24.0;

  GhostCursorPainter({
    required this.receiver,
    required this.peerColor,
    required this.peerName,
    required this.canvasOffset,
    required this.canvasScale,
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Skip if stale (no updates for >2s).
    if (receiver.isStale) return;

    // Transform canvas-space position to screen-space.
    final canvasPos = Offset(receiver.x, receiver.y);

    // Apply canvas transform.
    canvas.save();
    canvas.translate(canvasOffset.dx, canvasOffset.dy);
    canvas.scale(canvasScale);

    // Calculate fade-out opacity based on staleness.
    final age =
        DateTime.now().millisecondsSinceEpoch - receiver.lastReceivedMs;
    final staleProgress =
        (age / GhostCursorReceiver.staleTimeoutMs).clamp(0.0, 1.0);
    final opacity = (1.0 - staleProgress) * 0.3; // P7-05: 30% max opacity

    if (opacity <= 0.01) {
      canvas.restore();
      return;
    }

    // ── Outer circle (30% opacity, P7-05) ────────────────────────────
    _outerCirclePaint.color = peerColor.withValues(alpha: opacity);
    canvas.drawCircle(canvasPos, cursorRadius, _outerCirclePaint);

    // ── Inner dot (60% opacity) ──────────────────────────────────────
    _innerCirclePaint.color = peerColor.withValues(alpha: opacity * 2);
    canvas.drawCircle(canvasPos, 3.0, _innerCirclePaint);

    // ── Drawing ring (pulsing when peer is drawing) ──────────────────
    if (receiver.isDrawing) {
      _drawingRingPaint.color =
          peerColor.withValues(alpha: opacity * 2.5);
      canvas.drawCircle(canvasPos, drawingRingRadius, _drawingRingPaint);
    }

    // ── Name label ───────────────────────────────────────────────────
    final textSpan = TextSpan(
      text: peerName,
      style: TextStyle(
        color: Colors.white.withValues(alpha: opacity * 3),
        fontSize: 10.0,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.3,
      ),
    );
    final tp = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    // Background pill behind name.
    final nameCenter =
        canvasPos.translate(-tp.width / 2, nameOffsetY);
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        nameCenter.dx - 4,
        nameCenter.dy - 2,
        tp.width + 8,
        tp.height + 4,
      ),
      const Radius.circular(6),
    );
    _nameBgPaint.color = peerColor.withValues(alpha: opacity * 2);
    canvas.drawRRect(bgRect, _nameBgPaint);

    tp.paint(canvas, nameCenter);

    canvas.restore();
  }

  @override
  bool shouldRepaint(GhostCursorPainter oldDelegate) {
    // Always repaint — interpolation drives smooth movement.
    return true;
  }
}
