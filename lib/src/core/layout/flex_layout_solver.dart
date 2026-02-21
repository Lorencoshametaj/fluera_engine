/// 📐 FLEX LAYOUT SOLVER — Horizontal/vertical flex distribution.
///
/// Distributes children along a main axis using Flexbox-like rules:
/// spacing, alignment, flex grow, padding, and overflow/wrap.
///
/// ```dart
/// final result = FlexLayoutSolver.solve(
///   config: AutoLayoutConfig(
///     direction: LayoutDirection.horizontal,
///     spacing: 8,
///     mainAxisAlignment: MainAxisAlignment.spaceBetween,
///   ),
///   containerSize: Size(400, 200),
///   children: [
///     FlexChild(intrinsicSize: Size(100, 50)),
///     FlexChild(intrinsicSize: Size(60, 40), flexGrow: 1),
///   ],
/// );
/// // result.childRects → computed positions for each child
/// ```
library;

import 'dart:ui';
import 'dart:math' as math;

import 'auto_layout_config.dart';

// =============================================================================
// FLEX CHILD
// =============================================================================

/// Input: a child to be placed by the flex solver.
class FlexChild {
  /// Intrinsic (natural) size of the child.
  final Size intrinsicSize;

  /// Flex grow factor (0 = don't grow, 1+ = proportional growth).
  final double flexGrow;

  /// Per-child cross axis alignment override.
  final CrossAxisAlignment? selfAlign;

  /// Fixed main axis size override (null = use intrinsic).
  final double? fixedMainSize;

  const FlexChild({
    required this.intrinsicSize,
    this.flexGrow = 0,
    this.selfAlign,
    this.fixedMainSize,
  });
}

// =============================================================================
// FLEX LAYOUT RESULT
// =============================================================================

/// Output: computed rectangles for each child.
class FlexLayoutResult {
  /// Position and size for each child (same order as input).
  final List<Rect> childRects;

  /// Total content size (may exceed container if overflow).
  final Size contentSize;

  /// Whether content overflowed the container.
  final bool didOverflow;

  /// Wrap line breaks (indices where a new line starts). Empty if no wrap.
  final List<int> wrapBreaks;

  const FlexLayoutResult({
    required this.childRects,
    required this.contentSize,
    this.didOverflow = false,
    this.wrapBreaks = const [],
  });

  @override
  String toString() =>
      'FlexLayoutResult(children=${childRects.length}, '
      'content=$contentSize, overflow=$didOverflow)';
}

// =============================================================================
// FLEX LAYOUT SOLVER
// =============================================================================

/// Distributes children along a main axis using Flexbox rules.
class FlexLayoutSolver {
  const FlexLayoutSolver._();

  /// Solve flex layout for the given config, container, and children.
  static FlexLayoutResult solve({
    required AutoLayoutConfig config,
    required Size containerSize,
    required List<FlexChild> children,
  }) {
    if (children.isEmpty) {
      return FlexLayoutResult(
        childRects: const [],
        contentSize: Size(config.padding.horizontal, config.padding.vertical),
      );
    }

    final isH = config.isHorizontal;
    final padStart = isH ? config.padding.left : config.padding.top;
    final padEnd = isH ? config.padding.right : config.padding.bottom;
    final crossPadStart = isH ? config.padding.top : config.padding.left;
    final crossPadEnd = isH ? config.padding.bottom : config.padding.right;

    final mainAvailable =
        (isH ? containerSize.width : containerSize.height) - padStart - padEnd;
    final crossAvailable =
        (isH ? containerSize.height : containerSize.width) -
        crossPadStart -
        crossPadEnd;

    // Order children (optionally reversed)
    final ordered = config.reversed ? children.reversed.toList() : children;

    // If wrapping, solve multi-line
    if (config.overflow == OverflowBehavior.wrap) {
      return _solveWrapped(
        config,
        ordered,
        mainAvailable,
        crossAvailable,
        padStart,
        crossPadStart,
        isH,
      );
    }

    // Single-line solve
    return _solveLine(
      config,
      ordered,
      mainAvailable,
      crossAvailable,
      padStart,
      crossPadStart,
      isH,
    );
  }

  /// Solve a single line of flex children.
  static FlexLayoutResult _solveLine(
    AutoLayoutConfig config,
    List<FlexChild> children,
    double mainAvailable,
    double crossAvailable,
    double mainPadStart,
    double crossPadStart,
    bool isH,
  ) {
    // 1. Compute main-axis sizes
    final mainSizes = List<double>.filled(children.length, 0);
    double totalFixed = 0;
    double totalGrow = 0;

    for (int i = 0; i < children.length; i++) {
      final child = children[i];
      if (child.flexGrow > 0) {
        totalGrow += child.flexGrow;
        mainSizes[i] =
            child.fixedMainSize ??
            (isH ? child.intrinsicSize.width : child.intrinsicSize.height);
      } else {
        mainSizes[i] =
            child.fixedMainSize ??
            (isH ? child.intrinsicSize.width : child.intrinsicSize.height);
      }
      totalFixed += mainSizes[i];
    }

    final totalSpacing = config.spacing * math.max(0, children.length - 1);
    final freeSpace = mainAvailable - totalFixed - totalSpacing;

    // Distribute free space to grow children
    if (totalGrow > 0 && freeSpace > 0) {
      for (int i = 0; i < children.length; i++) {
        if (children[i].flexGrow > 0) {
          mainSizes[i] += (children[i].flexGrow / totalGrow) * freeSpace;
        }
      }
    }

    // 2. Compute main-axis positions based on alignment
    final totalContent = mainSizes.reduce((a, b) => a + b) + totalSpacing;
    final positions = _distributeMainAxis(
      config.mainAxisAlignment,
      mainSizes,
      mainAvailable,
      config.spacing,
      children.length,
    );

    // 3. Compute cross-axis sizes and positions
    final rects = <Rect>[];
    double maxCross = 0;

    for (int i = 0; i < children.length; i++) {
      final child = children[i];
      final crossAlign = child.selfAlign ?? config.crossAxisAlignment;
      final crossSize =
          crossAlign == CrossAxisAlignment.stretch
              ? crossAvailable
              : (isH ? child.intrinsicSize.height : child.intrinsicSize.width);

      maxCross = math.max(maxCross, crossSize);

      final crossPos = _alignCross(crossAlign, crossSize, crossAvailable);

      final mainPos = mainPadStart + positions[i];
      final crossOffset = crossPadStart + crossPos;

      rects.add(
        isH
            ? Rect.fromLTWH(mainPos, crossOffset, mainSizes[i], crossSize)
            : Rect.fromLTWH(crossOffset, mainPos, crossSize, mainSizes[i]),
      );
    }

    final contentSize =
        isH
            ? Size(
              totalContent + config.padding.horizontal,
              maxCross + config.padding.vertical,
            )
            : Size(
              maxCross + config.padding.horizontal,
              totalContent + config.padding.vertical,
            );

    return FlexLayoutResult(
      childRects: rects,
      contentSize: contentSize,
      didOverflow: totalContent > mainAvailable,
    );
  }

  /// Solve wrapped layout (multi-line).
  static FlexLayoutResult _solveWrapped(
    AutoLayoutConfig config,
    List<FlexChild> children,
    double mainAvailable,
    double crossAvailable,
    double mainPadStart,
    double crossPadStart,
    bool isH,
  ) {
    // Break children into lines
    final lines = <List<int>>[];
    var currentLine = <int>[];
    double lineSize = 0;

    for (int i = 0; i < children.length; i++) {
      final child = children[i];
      final childMain =
          child.fixedMainSize ??
          (isH ? child.intrinsicSize.width : child.intrinsicSize.height);

      if (currentLine.isNotEmpty &&
          lineSize + config.spacing + childMain > mainAvailable) {
        lines.add(currentLine);
        currentLine = [i];
        lineSize = childMain;
      } else {
        if (currentLine.isNotEmpty) lineSize += config.spacing;
        currentLine.add(i);
        lineSize += childMain;
      }
    }
    if (currentLine.isNotEmpty) lines.add(currentLine);

    // Solve each line
    final allRects = List<Rect>.filled(children.length, Rect.zero);
    final wrapBreaks = <int>[];
    double crossOffset = crossPadStart;

    for (final line in lines) {
      if (line.first != 0) wrapBreaks.add(line.first);

      final lineChildren = line.map((i) => children[i]).toList();
      double lineMaxCross = 0;

      for (final child in lineChildren) {
        lineMaxCross = math.max(
          lineMaxCross,
          isH ? child.intrinsicSize.height : child.intrinsicSize.width,
        );
      }

      final mainSizes =
          lineChildren.map((c) {
            return c.fixedMainSize ??
                (isH ? c.intrinsicSize.width : c.intrinsicSize.height);
          }).toList();

      final positions = _distributeMainAxis(
        config.mainAxisAlignment,
        mainSizes,
        mainAvailable,
        config.spacing,
        lineChildren.length,
      );

      for (int j = 0; j < line.length; j++) {
        final idx = line[j];
        final child = children[idx];
        final crossAlign = child.selfAlign ?? config.crossAxisAlignment;
        final crossSize =
            crossAlign == CrossAxisAlignment.stretch
                ? lineMaxCross
                : (isH
                    ? child.intrinsicSize.height
                    : child.intrinsicSize.width);

        final crossPos = _alignCross(crossAlign, crossSize, lineMaxCross);
        final mainPos = mainPadStart + positions[j];

        allRects[idx] =
            isH
                ? Rect.fromLTWH(
                  mainPos,
                  crossOffset + crossPos,
                  mainSizes[j],
                  crossSize,
                )
                : Rect.fromLTWH(
                  crossOffset + crossPos,
                  mainPos,
                  crossSize,
                  mainSizes[j],
                );
      }

      crossOffset += lineMaxCross + config.spacing;
    }

    final totalCross = crossOffset - crossPadStart - config.spacing;
    final contentSize =
        isH
            ? Size(
              mainAvailable + config.padding.horizontal,
              totalCross + config.padding.vertical,
            )
            : Size(
              totalCross + config.padding.horizontal,
              mainAvailable + config.padding.vertical,
            );

    return FlexLayoutResult(
      childRects: allRects,
      contentSize: contentSize,
      wrapBreaks: wrapBreaks,
    );
  }

  /// Distribute items along main axis according to alignment.
  static List<double> _distributeMainAxis(
    MainAxisAlignment alignment,
    List<double> sizes,
    double available,
    double spacing,
    int count,
  ) {
    if (count == 0) return [];

    final total = sizes.reduce((a, b) => a + b);
    final fixedSpacing = spacing * math.max(0.0, count - 1.0);
    final freeSpace = math.max(0.0, available - total - fixedSpacing);

    final positions = List<double>.filled(count, 0);

    switch (alignment) {
      case MainAxisAlignment.start:
        double pos = 0;
        for (int i = 0; i < count; i++) {
          positions[i] = pos;
          pos += sizes[i] + spacing;
        }

      case MainAxisAlignment.center:
        double pos = freeSpace / 2;
        for (int i = 0; i < count; i++) {
          positions[i] = pos;
          pos += sizes[i] + spacing;
        }

      case MainAxisAlignment.end:
        double pos = freeSpace;
        for (int i = 0; i < count; i++) {
          positions[i] = pos;
          pos += sizes[i] + spacing;
        }

      case MainAxisAlignment.spaceBetween:
        if (count == 1) {
          positions[0] = 0;
        } else {
          final gap = (available - total) / (count - 1);
          double pos = 0;
          for (int i = 0; i < count; i++) {
            positions[i] = pos;
            pos += sizes[i] + gap;
          }
        }

      case MainAxisAlignment.spaceAround:
        final gap = (available - total) / count;
        double pos = gap / 2;
        for (int i = 0; i < count; i++) {
          positions[i] = pos;
          pos += sizes[i] + gap;
        }

      case MainAxisAlignment.spaceEvenly:
        final gap = (available - total) / (count + 1);
        double pos = gap;
        for (int i = 0; i < count; i++) {
          positions[i] = pos;
          pos += sizes[i] + gap;
        }
    }

    return positions;
  }

  /// Align a single child along the cross axis.
  static double _alignCross(
    CrossAxisAlignment alignment,
    double childSize,
    double available,
  ) {
    switch (alignment) {
      case CrossAxisAlignment.start:
        return 0;
      case CrossAxisAlignment.center:
        return (available - childSize) / 2;
      case CrossAxisAlignment.end:
        return available - childSize;
      case CrossAxisAlignment.stretch:
        return 0;
    }
  }
}
