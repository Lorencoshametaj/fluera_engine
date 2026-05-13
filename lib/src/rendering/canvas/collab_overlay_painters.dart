import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../canvas/infinite_canvas_controller.dart';

// ============================================================================
// ☁️ COLLABORATION OVERLAY PAINTERS — public re-export of remote-strokes
// and PDF-loading-placeholder painters.
//
// Originally lived as `_RemoteLiveStrokesPainter` /
// `_PdfLoadingPlaceholderPainter` inside `parts/ui/_ui_canvas_layer_painters.dart`
// (a `part of fluera_canvas_screen.dart` file). Moved here when
// [FlueraCanvasView] (outside the screen library) needed to draw the same
// collab overlays.
//
// The data class [PdfLoadingPlaceholder] is mutable and owned by
// `CollaborationExtension` on the screen wrapper — passed read-only to
// the view via `CanvasLegacyState`.
// ============================================================================

/// 📄 Data class for a PDF loading placeholder shown on remote devices.
class PdfLoadingPlaceholder {
  final String documentId;
  final String? fileName;
  final int pageCount;
  final double pageWidth;
  final double pageHeight;
  final Offset position;
  final double progress; // 0.0 - 1.0
  final DateTime createdAt;
  final String? thumbnailBase64;

  PdfLoadingPlaceholder({
    required this.documentId,
    this.fileName,
    required this.pageCount,
    required this.pageWidth,
    required this.pageHeight,
    required this.position,
    this.progress = 0.0,
    this.thumbnailBase64,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Create a copy with updated progress.
  PdfLoadingPlaceholder copyWith({double? progress}) {
    return PdfLoadingPlaceholder(
      documentId: documentId,
      fileName: fileName,
      pageCount: pageCount,
      pageWidth: pageWidth,
      pageHeight: pageHeight,
      position: position,
      progress: progress ?? this.progress,
      thumbnailBase64: thumbnailBase64,
      createdAt: createdAt,
    );
  }

  /// Total height of the placeholder (all pages stacked vertically with spacing).
  double get totalHeight => pageCount * pageHeight + (pageCount - 1) * 20;

  /// Bounding rect in canvas coordinates.
  Rect get rect =>
      Rect.fromLTWH(position.dx, position.dy, pageWidth, totalHeight);
}

/// ☁️ Paints live strokes from remote collaborators as simple polylines.
class RemoteLiveStrokesPainter extends CustomPainter {
  final Map<String, List<Offset>> strokes;
  final Map<String, int> colors;
  final Map<String, double> widths;
  final InfiniteCanvasController controller;

  RemoteLiveStrokesPainter({
    required this.strokes,
    required this.colors,
    required this.widths,
    required this.controller,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (strokes.isEmpty) return;

    canvas.save();
    canvas.translate(controller.offset.dx, controller.offset.dy);
    canvas.scale(controller.scale);

    for (final entry in strokes.entries) {
      final points = entry.value;
      if (points.length < 2) continue;

      final color = Color(colors[entry.key] ?? 0xFF42A5F5);
      final width = widths[entry.key] ?? 2.0;

      final paint = Paint()
        ..color = color.withValues(alpha: 0.6)
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (int i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(path, paint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant RemoteLiveStrokesPainter oldDelegate) => true;
}

/// 📄 Paints loading placeholders for remote PDFs being uploaded.
class PdfLoadingPlaceholderPainter extends CustomPainter {
  final List<PdfLoadingPlaceholder> placeholders;
  final InfiniteCanvasController controller;
  final double pulseValue;

  PdfLoadingPlaceholderPainter({
    required this.placeholders,
    required this.controller,
    this.pulseValue = 0.5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (placeholders.isEmpty) return;

    canvas.save();
    canvas.translate(controller.offset.dx, controller.offset.dy);
    canvas.scale(controller.scale);

    for (final placeholder in placeholders) {
      final rect = placeholder.rect;

      // 🎬 Fade-in: opacity ramps from 0→1 over 300ms
      final age =
          DateTime.now().difference(placeholder.createdAt).inMilliseconds;
      final fadeOpacity = (age / 300.0).clamp(0.0, 1.0);

      // 🎯 Smooth progress lerp (0.08 factor ≈ smooth interpolation at 30fps)
      final targetProgress = placeholder.progress;
      final currentAnimated = animatedProgress[placeholder.documentId] ?? 0.0;
      final animated =
          currentAnimated + (targetProgress - currentAnimated) * 0.08;
      animatedProgress[placeholder.documentId] = animated;

      // 📸 Thumbnail preview — decode and render as blurred background
      final thumbB64 = placeholder.thumbnailBase64;
      if (thumbB64 != null &&
          decodedThumbnails.containsKey(placeholder.documentId)) {
        final thumbImage = decodedThumbnails[placeholder.documentId]!;
        final srcRect = Rect.fromLTWH(
          0,
          0,
          thumbImage.width.toDouble(),
          thumbImage.height.toDouble(),
        );
        final thumbPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.4 * fadeOpacity)
          ..imageFilter = ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3);
        canvas.save();
        canvas.clipRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(12)),
        );
        canvas.drawImageRect(thumbImage, srcRect, rect, thumbPaint);
        canvas.restore();
      } else if (thumbB64 != null &&
          !thumbnailDecodeRequested.contains(placeholder.documentId)) {
        thumbnailDecodeRequested.add(placeholder.documentId);
        _decodeThumbnail(placeholder.documentId, thumbB64);
      }

      // Background — subtle shimmer
      final alpha = (0.08 + 0.04 * pulseValue) * fadeOpacity;
      final bgPaint = Paint()
        ..color = Colors.white.withValues(alpha: alpha)
        ..style = PaintingStyle.fill;
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(12));
      canvas.drawRRect(rrect, bgPaint);

      // Border
      final borderPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.3 * fadeOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawRRect(rrect, borderPaint);

      // Loading icon (circular indicator) — centered
      final center = rect.center;
      const indicatorRadius = 20.0;
      final indicatorPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.5 * fadeOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round;

      // Draw arc that rotates with pulse
      const sweepAngle = 3.14 * 1.5;
      final startAngle = pulseValue * 3.14 * 2;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: indicatorRadius),
        startAngle,
        sweepAngle,
        false,
        indicatorPaint,
      );

      // Progress bar — shown when animated progress > 0.01
      if (animated > 0.01) {
        final barWidth = rect.width * 0.6;
        const barHeight = 6.0;
        final barLeft = center.dx - barWidth / 2;
        final barTop = center.dy + indicatorRadius + 8;

        // Background track
        final trackPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.15 * fadeOpacity)
          ..style = PaintingStyle.fill;
        final trackRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(barLeft, barTop, barWidth, barHeight),
          const Radius.circular(3),
        );
        canvas.drawRRect(trackRect, trackPaint);

        // Fill (using animated lerped value)
        final fillPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.6 * fadeOpacity)
          ..style = PaintingStyle.fill;
        final fillRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(barLeft, barTop, barWidth * animated, barHeight),
          const Radius.circular(3),
        );
        canvas.drawRRect(fillRect, fillPaint);
      }

      // Label text
      final label = placeholder.fileName ?? 'PDF';
      final pct = animated > 0.01 ? ' ${(animated * 100).toInt()}%' : '';
      final textPainter = TextPainter(
        text: TextSpan(
          text: 'Loading $label...$pct',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6 * fadeOpacity),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: rect.width - 40);

      final labelTop = animated > 0.01
          ? center.dy + indicatorRadius + 22
          : center.dy + indicatorRadius + 16;

      textPainter.paint(
        canvas,
        Offset(center.dx - textPainter.width / 2, labelTop),
      );

      // Page count badge
      final countPainter = TextPainter(
        text: TextSpan(
          text: '${placeholder.pageCount} pages',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4 * fadeOpacity),
            fontSize: 12,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      countPainter.paint(
        canvas,
        Offset(
          center.dx - countPainter.width / 2,
          labelTop + textPainter.height + 6,
        ),
      );
    }

    canvas.restore();
  }

  // 📸 Static thumbnail decode cache — shared across painter instances.
  // Public so the screen wrapper's `CollaborationExtension._cleanupPlaceholder`
  // can prune entries when a remote upload finalizes.
  static final Map<String, ui.Image> decodedThumbnails = {};
  static final Set<String> thumbnailDecodeRequested = {};
  // 🎯 Animated progress cache for smooth lerp
  static final Map<String, double> animatedProgress = {};

  /// Async decode base64 PNG thumbnail → cache for next paint.
  static void _decodeThumbnail(String docId, String base64Str) async {
    try {
      final bytes = base64Decode(base64Str);
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      decodedThumbnails[docId] = frame.image;
      codec.dispose();
    } catch (_) {}
  }

  @override
  bool shouldRepaint(covariant PdfLoadingPlaceholderPainter oldDelegate) =>
      true;
}
