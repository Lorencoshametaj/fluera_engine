part of 'interactive_page_grid_overlay.dart';

// ==================== SNAP/MAGNETISM LOGIC ====================

extension _PageGridSnap on _InteractivePageGridOverlayState {
  /// Calculates snap alignment to other pages
  _SnapResult calculateSnap(Rect movingBounds, int movingIndex) {
    final snapLines = <_SnapLine>[];
    double snapDx = 0;
    double snapDy = 0;

    // Threshold in canvas coordinates
    final threshold = _InteractivePageGridOverlayState._snapThreshold / widget.canvasScale;
    final gap = _InteractivePageGridOverlayState._snapGap / widget.canvasScale;

    // Moving page edges
    final movingLeft = movingBounds.left;
    final movingRight = movingBounds.right;
    final movingTop = movingBounds.top;
    final movingBottom = movingBounds.bottom;
    final movingCenterX = movingBounds.center.dx;
    final movingCenterY = movingBounds.center.dy;

    bool snappedHorizontal = false;
    bool snappedVertical = false;

    // Check alignment with every other page
    for (int i = 0; i < widget.config.individualPageBounds.length; i++) {
      if (i == movingIndex) continue;

      final other = widget.config.individualPageBounds[i];
      final otherLeft = other.left;
      final otherRight = other.right;
      final otherTop = other.top;
      final otherBottom = other.bottom;
      final otherCenterX = other.center.dx;
      final otherCenterY = other.center.dy;

      // === HORIZONTAL SNAP ===
      if (!snappedHorizontal) {
        // Left to Left
        if ((movingLeft - otherLeft).abs() < threshold) {
          snapDx = otherLeft - movingLeft;
          snapLines.add(
            _SnapLine(
              start: Offset(otherLeft, movingTop.clamp(otherTop, otherBottom)),
              end: Offset(otherLeft, movingBottom.clamp(otherTop, otherBottom)),
              isVertical: true,
            ),
          );
          snappedHorizontal = true;
        }
        // Right to Right
        else if ((movingRight - otherRight).abs() < threshold) {
          snapDx = otherRight - movingRight;
          snapLines.add(
            _SnapLine(
              start: Offset(otherRight, movingTop.clamp(otherTop, otherBottom)),
              end: Offset(
                otherRight,
                movingBottom.clamp(otherTop, otherBottom),
              ),
              isVertical: true,
            ),
          );
          snappedHorizontal = true;
        }
        // Left to Right (with gap)
        else if ((movingLeft - otherRight - gap).abs() < threshold) {
          snapDx = otherRight + gap - movingLeft;
          snapLines.add(
            _SnapLine(
              start: Offset(otherRight + gap / 2, movingCenterY),
              end: Offset(otherRight + gap / 2, otherCenterY),
              isVertical: true,
            ),
          );
          snappedHorizontal = true;
        }
        // Right to Left (with gap)
        else if ((movingRight - otherLeft + gap).abs() < threshold) {
          snapDx = otherLeft - gap - movingRight;
          snapLines.add(
            _SnapLine(
              start: Offset(otherLeft - gap / 2, movingCenterY),
              end: Offset(otherLeft - gap / 2, otherCenterY),
              isVertical: true,
            ),
          );
          snappedHorizontal = true;
        }
        // Center to Center (horizontal)
        else if ((movingCenterX - otherCenterX).abs() < threshold) {
          snapDx = otherCenterX - movingCenterX;
          snapLines.add(
            _SnapLine(
              start: Offset(otherCenterX, movingTop),
              end: Offset(otherCenterX, otherBottom),
              isVertical: true,
            ),
          );
          snappedHorizontal = true;
        }
      }

      // === VERTICAL SNAP ===
      if (!snappedVertical) {
        // Top to Top
        if ((movingTop - otherTop).abs() < threshold) {
          snapDy = otherTop - movingTop;
          snapLines.add(
            _SnapLine(
              start: Offset(movingLeft.clamp(otherLeft, otherRight), otherTop),
              end: Offset(movingRight.clamp(otherLeft, otherRight), otherTop),
              isVertical: false,
            ),
          );
          snappedVertical = true;
        }
        // Bottom to Bottom
        else if ((movingBottom - otherBottom).abs() < threshold) {
          snapDy = otherBottom - movingBottom;
          snapLines.add(
            _SnapLine(
              start: Offset(
                movingLeft.clamp(otherLeft, otherRight),
                otherBottom,
              ),
              end: Offset(
                movingRight.clamp(otherLeft, otherRight),
                otherBottom,
              ),
              isVertical: false,
            ),
          );
          snappedVertical = true;
        }
        // Top to Bottom (with gap)
        else if ((movingTop - otherBottom - gap).abs() < threshold) {
          snapDy = otherBottom + gap - movingTop;
          snapLines.add(
            _SnapLine(
              start: Offset(movingCenterX, otherBottom + gap / 2),
              end: Offset(otherCenterX, otherBottom + gap / 2),
              isVertical: false,
            ),
          );
          snappedVertical = true;
        }
        // Bottom to Top (with gap)
        else if ((movingBottom - otherTop + gap).abs() < threshold) {
          snapDy = otherTop - gap - movingBottom;
          snapLines.add(
            _SnapLine(
              start: Offset(movingCenterX, otherTop - gap / 2),
              end: Offset(otherCenterX, otherTop - gap / 2),
              isVertical: false,
            ),
          );
          snappedVertical = true;
        }
        // Center to Center (vertical)
        else if ((movingCenterY - otherCenterY).abs() < threshold) {
          snapDy = otherCenterY - movingCenterY;
          snapLines.add(
            _SnapLine(
              start: Offset(movingLeft, otherCenterY),
              end: Offset(otherRight, otherCenterY),
              isVertical: false,
            ),
          );
          snappedVertical = true;
        }
      }

      // If we found snaps in both directions, exit
      if (snappedHorizontal && snappedVertical) break;
    }

    return _SnapResult(offset: Offset(snapDx, snapDy), lines: snapLines);
  }
}

/// Snap calculation result
class _SnapResult {
  final Offset offset;
  final List<_SnapLine> lines;

  _SnapResult({required this.offset, required this.lines});
}

/// Snap guide line
class _SnapLine {
  final Offset start;
  final Offset end;
  final bool isVertical;

  _SnapLine({required this.start, required this.end, required this.isVertical});
}

/// Painter for snap guide lines
class _SnapLinesPainter extends CustomPainter {
  final List<_SnapLine> snapLines;
  final double canvasScale;
  final Offset canvasOffset;

  _SnapLinesPainter({
    required this.snapLines,
    required this.canvasScale,
    required this.canvasOffset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = Colors.cyan
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke;

    final dashPaint =
        Paint()
          ..color = Colors.cyan.withValues(alpha: 0.5)
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke;

    for (final line in snapLines) {
      // Convert to screen coordinates
      final screenStart = Offset(
        line.start.dx * canvasScale + canvasOffset.dx,
        line.start.dy * canvasScale + canvasOffset.dy,
      );
      final screenEnd = Offset(
        line.end.dx * canvasScale + canvasOffset.dx,
        line.end.dy * canvasScale + canvasOffset.dy,
      );

      // Extend the line towards the screen edges
      Offset extendedStart;
      Offset extendedEnd;

      if (line.isVertical) {
        extendedStart = Offset(screenStart.dx, 0);
        extendedEnd = Offset(screenEnd.dx, size.height);
      } else {
        extendedStart = Offset(0, screenStart.dy);
        extendedEnd = Offset(size.width, screenEnd.dy);
      }

      // Draw dashed extended line
      _drawDashedLine(canvas, extendedStart, extendedEnd, dashPaint);

      // Draw solid line in snap zone
      canvas.drawLine(screenStart, screenEnd, paint);

      // Draw dots at endpoints
      canvas.drawCircle(screenStart, 4, paint..style = PaintingStyle.fill);
      canvas.drawCircle(screenEnd, 4, paint..style = PaintingStyle.fill);
      paint.style = PaintingStyle.stroke;
    }
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashLength = 8.0;
    const gapLength = 4.0;

    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final distance = (Offset(dx, dy)).distance;
    final steps = (distance / (dashLength + gapLength)).floor();

    for (int i = 0; i < steps; i++) {
      final t1 = (i * (dashLength + gapLength)) / distance;
      final t2 = (i * (dashLength + gapLength) + dashLength) / distance;

      if (t1 < 1 && t2 <= 1) {
        canvas.drawLine(
          Offset(start.dx + dx * t1, start.dy + dy * t1),
          Offset(start.dx + dx * t2, start.dy + dy * t2),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SnapLinesPainter oldDelegate) {
    return snapLines != oldDelegate.snapLines ||
        canvasScale != oldDelegate.canvasScale ||
        canvasOffset != oldDelegate.canvasOffset;
  }
}
