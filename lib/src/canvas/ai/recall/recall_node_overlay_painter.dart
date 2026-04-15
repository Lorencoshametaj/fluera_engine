// ============================================================================
// 🎨 RECALL NODE OVERLAY PAINTER — Canvas-space node status indicators
//
// This CustomPainter renders the color-coded node overlays (P2-26) directly
// in canvas coordinates. By living inside the same Transform widget as the
// drawing layers, these overlays move in perfect lock-step with strokes
// during interactive pinch-to-zoom — eliminating the 1-frame layout drift
// that occurs when using Positioned widgets in screen space.
//
// Also renders:
//   - Zone labels ("📄 Originale" / "Tentativo") in canvas space
//   - Connection line (dotted + arrow) between original and attempt zones
//
// HUD elements (navigation bar, gap badge) remain as Flutter widgets in
// RecallComparisonOverlay since they don't need to track canvas transforms.
// ============================================================================

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import 'recall_mode_controller.dart';
import 'recall_session_model.dart';

/// Paints color-coded node status overlays in canvas space.
///
/// Each cluster gets a colored rectangle with a status icon and label,
/// positioned at the cluster's canvas coordinates. The parent Transform
/// widget handles offset + scale, so these stay perfectly aligned with
/// strokes during zoom/pan.
class RecallNodeOverlayPainter extends CustomPainter {
  final RecallModeController controller;

  /// Time-based animation value (seconds, looping).
  /// Used for gold pulse effect on mastered nodes.
  final double animationTime;

  /// Original zone rectangle (canvas coordinates), for the zone label.
  final Rect? originalZone;

  /// Reconstruction zone rectangle (canvas coordinates), for the zone label.
  final Rect reconstructionZone;

  /// Whether currently showing originals (true) or reconstruction (false).
  final bool showingOriginals;

  // ── Localized strings from the call-site (have BuildContext) ──
  /// Label above the original zone, e.g. '📄 Originale'.
  final String labelOriginalZone;
  /// Label above the attempt zone, e.g. 'Tentativo'.
  final String labelAttemptZone;
  /// Label inside the reconstruction border, e.g. 'Ricostruisci da memoria'.
  final String labelReconstruct;
  /// Per-level status labels (e.g. 'Not remembered', 'Recalled', …).
  final Map<RecallLevel, String> levelLabels;

  const RecallNodeOverlayPainter({
    required this.controller,
    required this.animationTime,
    required this.labelOriginalZone,
    required this.labelAttemptZone,
    required this.labelReconstruct,
    required this.levelLabels,
    this.originalZone,
    this.reconstructionZone = Rect.zero,
    this.showingOriginals = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!controller.isActive) return;

    // ── Reconstruction zone dashed border (during active recall, before comparison) ──
    if (!controller.isComparing && reconstructionZone != Rect.zero) {
      _paintReconstructionBorder(canvas);
    }

    // ── Comparison-only elements ──
    if (controller.isComparing) {
      // Zone labels + connection line
      if (showingOriginals) {
        _paintZoneLabels(canvas);
      }
      // Node overlays
      _paintNodeOverlays(canvas);
    }
  }

  // ── Reusable Paint objects (avoid allocation in paint()) ──
  static final _fillPaint = Paint();
  static final _borderPaint = Paint()..style = PaintingStyle.stroke;
  static final _glowPaint = Paint()
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
  static final _smallGlowPaint = Paint()
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

  // ── TextPainter cache: eliminates layout() allocations in paint() ──
  //
  // Keys encode every param that affects text metrics: text, fontSize,
  // fontWeight, and color ARGB. At most ~35 entries per recall session
  // (4 icons + 24 label combos + 3 zone labels + 1 star).
  // Cleared on deactivation via [clearTextPainterCache].
  static final Map<String, TextPainter> _tpCache = {};

  /// Returns a pre-laid-out TextPainter, building it once on first call.
  static TextPainter _tp(
    String text,
    double fontSize,
    Color color, {
    FontWeight fontWeight = FontWeight.normal,
    double maxWidth = double.infinity,
  }) {
    final key = '$text|${fontSize.toInt()}|${color.toARGB32()}|${fontWeight.index}';
    return _tpCache.putIfAbsent(key, () {
      return TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: color,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
        // No maxLines/ellipsis: at 8–14pt all recall labels fit within any
        // realistic cluster width. Using ∞ avoids per-width cache fragmentation.
      )..layout();
    });
  }

  /// Call on deactivation to release layout cache between sessions.
  static void clearTextPainterCache() => _tpCache.clear();

  // ─────────────────────────────────────────────────────────────────────────
  // RECONSTRUCTION ZONE BORDER (during active recall, before comparison)
  // ─────────────────────────────────────────────────────────────────────────

  void _paintReconstructionBorder(Canvas canvas) {
    final rect = reconstructionZone;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(16));

    // Pulse animation: oscillate opacity based on animationTime.
    final pulseOpacity = 0.3 + 0.15 * (0.5 + 0.5 *
        (2.0 * ((animationTime / 4.0) % 1.0) - 1.0).abs());

    // Soft fill.
    canvas.drawRRect(
      rrect,
      _fillPaint..color = const Color(0xFF6C63FF).withValues(alpha: 0.03),
    );

    // Animated dashed border.
    final dashOffset = ((animationTime / 4.0) % 1.0) * 40.0;
    canvas.drawPath(
      _createDashPath(
        Path()..addRRect(rrect),
        dashLength: 12.0,
        gapLength: 8.0,
        offset: dashOffset,
      ),
      _borderPaint
        ..color = Color.fromRGBO(108, 99, 255, pulseOpacity)
        ..strokeWidth = 2.0,
    );

    // Zone instruction label.
    _paintLabel(
      canvas,
      text: labelReconstruct,
      color: const Color(0xFF6C63FF),
      position: Offset(rect.center.dx, rect.top + 24),
    );
  }

  /// Creates a dashed path from a source path.
  Path _createDashPath(
    Path source, {
    required double dashLength,
    required double gapLength,
    double offset = 0,
  }) {
    final dest = Path();
    for (final metric in source.computeMetrics()) {
      double distance = offset % (dashLength + gapLength);
      while (distance < metric.length) {
        final len = dashLength.clamp(0, metric.length - distance).toDouble();
        dest.addPath(
          metric.extractPath(distance, distance + len),
          Offset.zero,
        );
        distance += dashLength + gapLength;
      }
    }
    return dest;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ZONE LABELS + CONNECTION LINE
  // ─────────────────────────────────────────────────────────────────────────

  void _paintZoneLabels(Canvas canvas) {
    final origZone = originalZone;
    if (origZone == null) return;

    // Label above original zone.
    _paintLabel(
      canvas,
      text: labelOriginalZone,
      color: const Color(0xFF007AFF),
      position: Offset(origZone.center.dx, origZone.top - 30),
    );

    // Label above reconstruction zone.
    if (reconstructionZone != Rect.zero) {
      _paintLabel(
        canvas,
        text: labelAttemptZone,
        color: const Color(0xFF30D158),
        position: Offset(
          reconstructionZone.center.dx,
          reconstructionZone.top - 30,
        ),
      );

      // Connection line between zones.
      _paintConnectionLine(
        canvas,
        start: Offset(origZone.right, origZone.center.dy),
        end: Offset(reconstructionZone.left, reconstructionZone.center.dy),
      );
    }
  }

  void _paintLabel(
    Canvas canvas, {
    required String text,
    required Color color,
    required Offset position,
  }) {
    final textPainter = _tp(
      text,
      13,
      color,
      fontWeight: FontWeight.w600,
    );

    final paddingH = 14.0;
    final paddingV = 6.0;
    final bgWidth = textPainter.width + paddingH * 2;
    final bgHeight = textPainter.height + paddingV * 2;
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: position,
        width: bgWidth,
        height: bgHeight,
      ),
      const Radius.circular(10),
    );

    // Background
    canvas.drawRRect(
      bgRect,
      Paint()..color = const Color(0xE60A0A14),
    );

    // Border
    canvas.drawRRect(
      bgRect,
      Paint()
        ..color = color.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Glow
    canvas.drawRRect(
      bgRect,
      Paint()
        ..color = color.withValues(alpha: 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );

    // Text
    textPainter.paint(
      canvas,
      Offset(
        position.dx - textPainter.width / 2,
        position.dy - textPainter.height / 2,
      ),
    );
  }

  void _paintConnectionLine(Canvas canvas, {
    required Offset start,
    required Offset end,
  }) {
    final paint = Paint()
      ..color = const Color(0xFF6C63FF).withValues(alpha: 0.25)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Dotted line.
    const dashLen = 6.0;
    const gapLen = 6.0;
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final distance = Offset(dx, dy).distance;
    if (distance < 1) return;

    final unitX = dx / distance;
    final unitY = dy / distance;

    double d = 0;
    while (d < distance) {
      final segEnd = (d + dashLen).clamp(0.0, distance);
      canvas.drawLine(
        Offset(start.dx + unitX * d, start.dy + unitY * d),
        Offset(start.dx + unitX * segEnd, start.dy + unitY * segEnd),
        paint,
      );
      d += dashLen + gapLen;
    }

    // Arrow at end.
    const arrowSize = 8.0;
    final cosA = math.cos(0.5);
    final sinA = math.sin(0.5);
    final ax1 = end.dx - arrowSize * (unitX * cosA - unitY * sinA);
    final ay1 = end.dy - arrowSize * (unitX * sinA + unitY * cosA);
    final ax2 = end.dx - arrowSize * (unitX * cosA + unitY * sinA);
    final ay2 = end.dy - arrowSize * (-unitX * sinA + unitY * cosA);

    final arrowPaint = Paint()
      ..color = const Color(0xFF6C63FF).withValues(alpha: 0.35)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawLine(end, Offset(ax1, ay1), arrowPaint);
    canvas.drawLine(end, Offset(ax2, ay2), arrowPaint);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // NODE OVERLAYS
  // ─────────────────────────────────────────────────────────────────────────

  void _paintNodeOverlays(Canvas canvas) {
    final entries = controller.nodeEntries;
    // O(1) lookup — map is pre-built once at activate() time in the controller.
    final clusterById = controller.originalClustersById;

    for (final entry in entries.entries) {
      final cluster = clusterById[entry.key]; // O(1) vs O(n) linear search
      if (cluster == null) continue;

      final status = controller.comparisonStatus(entry.key);
      final color = _statusColor(status);
      final opacity = _statusOpacity(status);
      final isMastered = entry.value.mastered;
      final isRecalled = entry.value.recallLevel.isSuccessful;

      // Canvas-space rect from cluster AABB.
      // NOTE: We use bounds directly, NOT Rect.fromCenter(centroid, ...),
      // because centroid is the mass center (average of stroke centroids)
      // which differs from the geometric center of the AABB.
      final rect = cluster.bounds;

      // Gold pulse: sin wave 0..1 over ~3s period
      final pulseProgress = isMastered
          ? ((1.0 + math.sin(animationTime * 2.094)) / 2.0)
          : 0.0;

      // ── Background fill ──
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));
      canvas.drawRRect(
        rrect,
        _fillPaint..color = color.withValues(alpha: opacity),
      );

      // ── Border ──
      if (isMastered) {
        final goldGlow = pulseProgress * 0.4;
        canvas.drawRRect(
          rrect,
          _borderPaint
            ..strokeWidth = 2.0
            ..color = const Color(0xFFFFD700).withValues(alpha: 0.5 + goldGlow),
        );
      } else {
        canvas.drawRRect(
          rrect,
          _borderPaint
            ..strokeWidth = 1.0
            ..color = color.withValues(alpha: opacity + 0.15),
        );
      }

      // ── Gold glow shadow for mastered ──
      if (isMastered) {
        final goldGlow = pulseProgress * 0.4;
        canvas.drawRRect(
          rrect.inflate(2),
          _glowPaint
            ..color = const Color(0xFFFFD700).withValues(alpha: goldGlow * 0.5),
        );
      }

      // ── Green glow for recalled (non-mastered) ──
      if (isRecalled && !isMastered) {
        canvas.drawRRect(
          rrect,
          _smallGlowPaint
            ..color = const Color(0xFF30D158).withValues(alpha: 0.15),
        );
      }

      // ── Status icon + label ──
      final icon = _statusIcon(status);
      final label = levelLabels[entry.value.recallLevel] ?? '';

      // Status icon: cached by emoji string (4 emojis × 1 style = 4 entries).
      final iconPainter = _tp(icon, 14, const Color(0xFF000000));

      // Level label: cached by (text, statusColor) = 6 × 4 = 24 entries max.
      final labelColor = color.withValues(alpha: 0.9);
      final labelPainter = _tp(
        label,
        8,
        labelColor,
        fontWeight: FontWeight.w600,
      );

      // Center vertically
      final totalContentHeight = iconPainter.height + 2 + labelPainter.height +
          (isMastered ? 14 : 0);
      var cy = rect.center.dy - totalContentHeight / 2;

      // Icon
      iconPainter.paint(
        canvas,
        Offset(rect.center.dx - iconPainter.width / 2, cy),
      );
      cy += iconPainter.height + 2;

      // Label
      labelPainter.paint(
        canvas,
        Offset(rect.center.dx - labelPainter.width / 2, cy),
      );
      cy += labelPainter.height + 2;

      // Mastery star: single entry in cache.
      if (isMastered) {
        const starColor = Color(0xFFFFD700);
        final starPainter = _tp('⭐', 12, starColor);
        starPainter.paint(
          canvas,
          Offset(rect.center.dx - starPainter.width / 2, cy),
        );
      }
    }
  }

  @override
  bool shouldRepaint(RecallNodeOverlayPainter oldDelegate) {
    return oldDelegate.animationTime != animationTime ||
        oldDelegate.controller != controller ||
        oldDelegate.originalZone != originalZone ||
        oldDelegate.reconstructionZone != reconstructionZone ||
        oldDelegate.showingOriginals != showingOriginals ||
        oldDelegate.labelOriginalZone != labelOriginalZone ||
        oldDelegate.labelAttemptZone != labelAttemptZone ||
        oldDelegate.labelReconstruct != labelReconstruct;
  }

  // ── Status helpers ──

  Color _statusColor(ComparisonNodeStatus status) {
    switch (status) {
      case ComparisonNodeStatus.missed:
        return const Color(0xFFFF453A);
      case ComparisonNodeStatus.recalled:
        return const Color(0xFF30D158);
      case ComparisonNodeStatus.added:
        return const Color(0xFF0A84FF);
      case ComparisonNodeStatus.peeked:
        return const Color(0xFFFFD60A);
    }
  }

  double _statusOpacity(ComparisonNodeStatus status) {
    switch (status) {
      case ComparisonNodeStatus.missed:
        return 0.30;
      case ComparisonNodeStatus.recalled:
        return 0.20;
      case ComparisonNodeStatus.added:
        return 0.20;
      case ComparisonNodeStatus.peeked:
        return 0.25;
    }
  }

  String _statusIcon(ComparisonNodeStatus status) {
    switch (status) {
      case ComparisonNodeStatus.missed:
        return '❌';
      case ComparisonNodeStatus.recalled:
        return '✅';
      case ComparisonNodeStatus.added:
        return '➕';
      case ComparisonNodeStatus.peeked:
        return '👁️';
    }
  }
}
