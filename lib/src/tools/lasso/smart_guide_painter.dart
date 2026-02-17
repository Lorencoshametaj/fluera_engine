import 'package:flutter/material.dart';

/// Draws alignment guide lines when the selection aligns with
/// other elements on the canvas (Figma/Sketch-style smart guides).
///
/// Usage: Feed [guides] from [SmartGuideDetector.detect] and overlay
/// this painter on the canvas during drag operations.
class SmartGuidePainter extends CustomPainter {
  final List<SmartGuide> guides;

  SmartGuidePainter({required this.guides});

  @override
  void paint(Canvas canvas, Size size) {
    if (guides.isEmpty) return;

    for (final guide in guides) {
      final paint =
          Paint()
            ..color =
                guide.type == GuideType.horizontal
                    ? Colors.cyan.withValues(alpha: 0.8)
                    : const Color(0xFFE040FB).withValues(alpha: 0.8)
            ..strokeWidth = 0.75
            ..style = PaintingStyle.stroke;

      if (guide.type == GuideType.horizontal) {
        canvas.drawLine(
          Offset(0, guide.position),
          Offset(size.width, guide.position),
          paint,
        );
      } else {
        canvas.drawLine(
          Offset(guide.position, 0),
          Offset(guide.position, size.height),
          paint,
        );
      }

      // Draw small diamond at the alignment point
      final diamond = Path();
      const s = 3.0;
      final p = guide.markerOffset;
      diamond.moveTo(p.dx, p.dy - s);
      diamond.lineTo(p.dx + s, p.dy);
      diamond.lineTo(p.dx, p.dy + s);
      diamond.lineTo(p.dx - s, p.dy);
      diamond.close();
      canvas.drawPath(diamond, paint..style = PaintingStyle.fill);
    }
  }

  @override
  bool shouldRepaint(SmartGuidePainter oldDelegate) =>
      oldDelegate.guides.length != guides.length ||
      !_guidesEqual(oldDelegate.guides, guides);

  static bool _guidesEqual(List<SmartGuide> a, List<SmartGuide> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

enum GuideType { horizontal, vertical }

/// Represents a single alignment guide line.
class SmartGuide {
  /// Whether this is a horizontal or vertical guide.
  final GuideType type;

  /// The Y position (horizontal) or X position (vertical) of the line.
  final double position;

  /// Where to draw the alignment marker diamond.
  final Offset markerOffset;

  const SmartGuide({
    required this.type,
    required this.position,
    required this.markerOffset,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SmartGuide && type == other.type && position == other.position;

  @override
  int get hashCode => Object.hash(type, position);
}

/// Detects alignment guides between the dragged selection and
/// stationary canvas elements.
class SmartGuideDetector {
  /// Snap threshold in logical pixels.
  final double threshold;

  const SmartGuideDetector({this.threshold = 5.0});

  /// Detect guides by comparing [selectionBounds] against [elementBounds].
  ///
  /// Returns matching guides and optionally a snap delta to apply.
  SmartGuideResult detect(Rect selectionBounds, List<Rect> elementBounds) {
    final guides = <SmartGuide>[];
    double snapDx = 0;
    double snapDy = 0;

    // Selection reference points
    final selLeft = selectionBounds.left;
    final selRight = selectionBounds.right;
    final selCenterX = selectionBounds.center.dx;
    final selTop = selectionBounds.top;
    final selBottom = selectionBounds.bottom;
    final selCenterY = selectionBounds.center.dy;

    for (final eb in elementBounds) {
      // Vertical guides (X alignment)
      _checkSnap(
        selLeft,
        eb.left,
        GuideType.vertical,
        eb.left,
        Offset(eb.left, selCenterY),
        guides,
        (d) => snapDx = d,
      );
      _checkSnap(
        selRight,
        eb.right,
        GuideType.vertical,
        eb.right,
        Offset(eb.right, selCenterY),
        guides,
        (d) => snapDx = d,
      );
      _checkSnap(
        selCenterX,
        eb.center.dx,
        GuideType.vertical,
        eb.center.dx,
        Offset(eb.center.dx, selCenterY),
        guides,
        (d) => snapDx = d,
      );
      _checkSnap(
        selLeft,
        eb.right,
        GuideType.vertical,
        eb.right,
        Offset(eb.right, selCenterY),
        guides,
        (d) => snapDx = d,
      );
      _checkSnap(
        selRight,
        eb.left,
        GuideType.vertical,
        eb.left,
        Offset(eb.left, selCenterY),
        guides,
        (d) => snapDx = d,
      );

      // Horizontal guides (Y alignment)
      _checkSnap(
        selTop,
        eb.top,
        GuideType.horizontal,
        eb.top,
        Offset(selCenterX, eb.top),
        guides,
        (d) => snapDy = d,
      );
      _checkSnap(
        selBottom,
        eb.bottom,
        GuideType.horizontal,
        eb.bottom,
        Offset(selCenterX, eb.bottom),
        guides,
        (d) => snapDy = d,
      );
      _checkSnap(
        selCenterY,
        eb.center.dy,
        GuideType.horizontal,
        eb.center.dy,
        Offset(selCenterX, eb.center.dy),
        guides,
        (d) => snapDy = d,
      );
      _checkSnap(
        selTop,
        eb.bottom,
        GuideType.horizontal,
        eb.bottom,
        Offset(selCenterX, eb.bottom),
        guides,
        (d) => snapDy = d,
      );
      _checkSnap(
        selBottom,
        eb.top,
        GuideType.horizontal,
        eb.top,
        Offset(selCenterX, eb.top),
        guides,
        (d) => snapDy = d,
      );
    }

    return SmartGuideResult(guides: guides, snapDelta: Offset(snapDx, snapDy));
  }

  void _checkSnap(
    double selValue,
    double elemValue,
    GuideType type,
    double position,
    Offset marker,
    List<SmartGuide> guides,
    void Function(double) setSnap,
  ) {
    final diff = elemValue - selValue;
    if (diff.abs() <= threshold) {
      guides.add(
        SmartGuide(type: type, position: position, markerOffset: marker),
      );
      setSnap(diff);
    }
  }
}

/// Result of smart guide detection.
class SmartGuideResult {
  final List<SmartGuide> guides;
  final Offset snapDelta;

  const SmartGuideResult({required this.guides, required this.snapDelta});

  bool get hasGuides => guides.isNotEmpty;
}
