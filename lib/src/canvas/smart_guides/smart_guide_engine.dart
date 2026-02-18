import 'package:flutter/painting.dart';

/// A single alignment guide line to render on the canvas.
class SmartGuideLine {
  /// The axis of the guide (horizontal = aligns Y, vertical = aligns X).
  final Axis axis;

  /// The position on the perpendicular axis (X for vertical, Y for horizontal).
  final double position;

  /// Start and end of the guide line along its axis.
  final double start;
  final double end;

  /// Whether this guide aligns centers (vs edges).
  final bool isCenter;

  const SmartGuideLine({
    required this.axis,
    required this.position,
    required this.start,
    required this.end,
    this.isCenter = false,
  });
}

/// Result of a smart guide check: snap offset + visible guides.
class SmartGuideResult {
  /// How much to adjust the dragged element's position for snapping.
  final Offset snapOffset;

  /// Guide lines to render.
  final List<SmartGuideLine> guides;

  /// Whether any snap occurred.
  bool get hasSnap => snapOffset != Offset.zero;

  const SmartGuideResult({
    this.snapOffset = Offset.zero,
    this.guides = const [],
  });

  static const none = SmartGuideResult();
}

/// 📐 Smart Guide Engine
///
/// Computes alignment guides and snap offsets when dragging elements.
/// Compares the dragged element's bounds against all other visible
/// element bounds to find edge and center alignments within a threshold.
///
/// DESIGN PRINCIPLES:
/// - Pure computation — no rendering, no state mutation
/// - O(n) per axis where n = number of target elements
/// - Snap threshold in canvas space (scale-independent)
class SmartGuideEngine {
  /// Snap distance threshold in canvas-space pixels.
  static const double snapThreshold = 8.0;

  /// Compute snap offset and guide lines for a dragged element.
  ///
  /// [draggedBounds] — the current bounds of the element being dragged.
  /// [targetBounds] — bounds of all other visible elements to align against.
  /// [excludeId] — optional ID to filter out (the dragged element itself).
  static SmartGuideResult compute({
    required Rect draggedBounds,
    required List<Rect> targetBounds,
  }) {
    if (targetBounds.isEmpty) return SmartGuideResult.none;

    // Extract the 5 reference lines for the dragged element:
    // left, centerX, right, top, centerY, bottom
    final dLeft = draggedBounds.left;
    final dRight = draggedBounds.right;
    final dCenterX = draggedBounds.center.dx;
    final dTop = draggedBounds.top;
    final dBottom = draggedBounds.bottom;
    final dCenterY = draggedBounds.center.dy;

    // Best snap candidates per axis
    double bestSnapX = double.infinity;
    double bestSnapY = double.infinity;
    final List<SmartGuideLine> guides = [];

    for (final target in targetBounds) {
      final tLeft = target.left;
      final tRight = target.right;
      final tCenterX = target.center.dx;
      final tTop = target.top;
      final tBottom = target.bottom;
      final tCenterY = target.center.dy;

      // ── VERTICAL guides (snap X axis) ──
      // Check all dragged-edge vs target-edge combinations
      _checkSnapX(dLeft, tLeft, false, draggedBounds, target, bestSnapX, (
        snap,
        guide,
      ) {
        bestSnapX = snap;
        guides.removeWhere((g) => g.axis == Axis.vertical);
        guides.add(guide);
      });
      _checkSnapX(dLeft, tRight, false, draggedBounds, target, bestSnapX, (
        snap,
        guide,
      ) {
        bestSnapX = snap;
        guides.removeWhere((g) => g.axis == Axis.vertical);
        guides.add(guide);
      });
      _checkSnapX(dRight, tLeft, false, draggedBounds, target, bestSnapX, (
        snap,
        guide,
      ) {
        bestSnapX = snap;
        guides.removeWhere((g) => g.axis == Axis.vertical);
        guides.add(guide);
      });
      _checkSnapX(dRight, tRight, false, draggedBounds, target, bestSnapX, (
        snap,
        guide,
      ) {
        bestSnapX = snap;
        guides.removeWhere((g) => g.axis == Axis.vertical);
        guides.add(guide);
      });
      _checkSnapX(dCenterX, tCenterX, true, draggedBounds, target, bestSnapX, (
        snap,
        guide,
      ) {
        bestSnapX = snap;
        guides.removeWhere((g) => g.axis == Axis.vertical);
        guides.add(guide);
      });

      // ── HORIZONTAL guides (snap Y axis) ──
      _checkSnapY(dTop, tTop, false, draggedBounds, target, bestSnapY, (
        snap,
        guide,
      ) {
        bestSnapY = snap;
        guides.removeWhere((g) => g.axis == Axis.horizontal);
        guides.add(guide);
      });
      _checkSnapY(dTop, tBottom, false, draggedBounds, target, bestSnapY, (
        snap,
        guide,
      ) {
        bestSnapY = snap;
        guides.removeWhere((g) => g.axis == Axis.horizontal);
        guides.add(guide);
      });
      _checkSnapY(dBottom, tTop, false, draggedBounds, target, bestSnapY, (
        snap,
        guide,
      ) {
        bestSnapY = snap;
        guides.removeWhere((g) => g.axis == Axis.horizontal);
        guides.add(guide);
      });
      _checkSnapY(dBottom, tBottom, false, draggedBounds, target, bestSnapY, (
        snap,
        guide,
      ) {
        bestSnapY = snap;
        guides.removeWhere((g) => g.axis == Axis.horizontal);
        guides.add(guide);
      });
      _checkSnapY(dCenterY, tCenterY, true, draggedBounds, target, bestSnapY, (
        snap,
        guide,
      ) {
        bestSnapY = snap;
        guides.removeWhere((g) => g.axis == Axis.horizontal);
        guides.add(guide);
      });
    }

    // Build snap offset
    final snapX = bestSnapX.abs() <= snapThreshold ? bestSnapX : 0.0;
    final snapY = bestSnapY.abs() <= snapThreshold ? bestSnapY : 0.0;

    if (snapX == 0.0 && snapY == 0.0 && guides.isEmpty) {
      return SmartGuideResult.none;
    }

    // Only keep guides that are actually snapping
    guides.removeWhere((g) {
      if (g.axis == Axis.vertical && snapX == 0.0) return true;
      if (g.axis == Axis.horizontal && snapY == 0.0) return true;
      return false;
    });

    return SmartGuideResult(snapOffset: Offset(snapX, snapY), guides: guides);
  }

  /// Check X-axis alignment and call [onBetter] if this is closer than current best.
  static void _checkSnapX(
    double draggedX,
    double targetX,
    bool isCenter,
    Rect draggedBounds,
    Rect targetBounds,
    double currentBest,
    void Function(double snap, SmartGuideLine guide) onBetter,
  ) {
    final diff = targetX - draggedX;
    if (diff.abs() <= snapThreshold && diff.abs() < currentBest.abs()) {
      // Guide line spans from topmost to bottommost of both rects
      final minY =
          draggedBounds.top < targetBounds.top
              ? draggedBounds.top
              : targetBounds.top;
      final maxY =
          draggedBounds.bottom > targetBounds.bottom
              ? draggedBounds.bottom
              : targetBounds.bottom;

      onBetter(
        diff,
        SmartGuideLine(
          axis: Axis.vertical,
          position: targetX,
          start: minY - 10,
          end: maxY + 10,
          isCenter: isCenter,
        ),
      );
    }
  }

  /// Check Y-axis alignment and call [onBetter] if this is closer than current best.
  static void _checkSnapY(
    double draggedY,
    double targetY,
    bool isCenter,
    Rect draggedBounds,
    Rect targetBounds,
    double currentBest,
    void Function(double snap, SmartGuideLine guide) onBetter,
  ) {
    final diff = targetY - draggedY;
    if (diff.abs() <= snapThreshold && diff.abs() < currentBest.abs()) {
      final minX =
          draggedBounds.left < targetBounds.left
              ? draggedBounds.left
              : targetBounds.left;
      final maxX =
          draggedBounds.right > targetBounds.right
              ? draggedBounds.right
              : targetBounds.right;

      onBetter(
        diff,
        SmartGuideLine(
          axis: Axis.horizontal,
          position: targetY,
          start: minX - 10,
          end: maxX + 10,
          isCenter: isCenter,
        ),
      );
    }
  }
}
