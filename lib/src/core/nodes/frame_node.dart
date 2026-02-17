import 'package:flutter/material.dart';
import '../scene_graph/canvas_node.dart';
import '../scene_graph/node_visitor.dart';
import './group_node.dart';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// Direction of auto layout flow.
enum LayoutDirection {
  /// Children flow left to right.
  horizontal,

  /// Children flow top to bottom.
  vertical,
}

/// How a child sizes itself along the parent's primary axis.
enum SizingMode {
  /// Fixed pixel size (user-specified).
  fixed,

  /// Shrink-wrap to content.
  hug,

  /// Expand to fill available space.
  fill,
}

/// Alignment of children along the cross axis.
enum CrossAxisAlignment { start, center, end, stretch }

/// Alignment of children along the main axis.
enum MainAxisAlignment {
  start,
  center,
  end,
  spaceBetween,
  spaceAround,
  spaceEvenly,
}

// ---------------------------------------------------------------------------
// Layout Constraint
// ---------------------------------------------------------------------------

/// Per-child layout constraint within a [FrameNode].
///
/// Determines how the child behaves when its parent resizes.
class LayoutConstraint {
  /// Sizing along the parent's primary axis.
  SizingMode primarySizing;

  /// Sizing along the parent's cross axis.
  SizingMode crossSizing;

  /// Fixed width (used when sizing is [SizingMode.fixed]).
  double? fixedWidth;

  /// Fixed height (used when sizing is [SizingMode.fixed]).
  double? fixedHeight;

  /// Minimum dimensions.
  double minWidth;
  double minHeight;

  /// Maximum dimensions.
  double maxWidth;
  double maxHeight;

  /// Pin edges — whether this child sticks to parent edges on resize.
  bool pinLeft;
  bool pinRight;
  bool pinTop;
  bool pinBottom;

  /// Flex grow factor (like CSS flex-grow). Only used when [primarySizing]
  /// is [SizingMode.fill]. Higher values take more available space.
  double flexGrow;

  LayoutConstraint({
    this.primarySizing = SizingMode.hug,
    this.crossSizing = SizingMode.hug,
    this.fixedWidth,
    this.fixedHeight,
    this.minWidth = 0,
    this.minHeight = 0,
    this.maxWidth = double.infinity,
    this.maxHeight = double.infinity,
    this.pinLeft = false,
    this.pinRight = false,
    this.pinTop = false,
    this.pinBottom = false,
    this.flexGrow = 1.0,
  });

  Map<String, dynamic> toJson() => {
    'primarySizing': primarySizing.name,
    'crossSizing': crossSizing.name,
    if (fixedWidth != null) 'fixedWidth': fixedWidth,
    if (fixedHeight != null) 'fixedHeight': fixedHeight,
    'minWidth': minWidth,
    'minHeight': minHeight,
    if (maxWidth != double.infinity) 'maxWidth': maxWidth,
    if (maxHeight != double.infinity) 'maxHeight': maxHeight,
    'pinLeft': pinLeft,
    'pinRight': pinRight,
    'pinTop': pinTop,
    'pinBottom': pinBottom,
    'flexGrow': flexGrow,
  };

  factory LayoutConstraint.fromJson(Map<String, dynamic> json) {
    return LayoutConstraint(
      primarySizing: SizingMode.values.byName(
        json['primarySizing'] as String? ?? 'hug',
      ),
      crossSizing: SizingMode.values.byName(
        json['crossSizing'] as String? ?? 'hug',
      ),
      fixedWidth: (json['fixedWidth'] as num?)?.toDouble(),
      fixedHeight: (json['fixedHeight'] as num?)?.toDouble(),
      minWidth: (json['minWidth'] as num?)?.toDouble() ?? 0,
      minHeight: (json['minHeight'] as num?)?.toDouble() ?? 0,
      maxWidth: (json['maxWidth'] as num?)?.toDouble() ?? double.infinity,
      maxHeight: (json['maxHeight'] as num?)?.toDouble() ?? double.infinity,
      pinLeft: json['pinLeft'] as bool? ?? false,
      pinRight: json['pinRight'] as bool? ?? false,
      pinTop: json['pinTop'] as bool? ?? false,
      pinBottom: json['pinBottom'] as bool? ?? false,
      flexGrow: (json['flexGrow'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

// ---------------------------------------------------------------------------
// Frame Node
// ---------------------------------------------------------------------------

/// A layout container node similar to Figma's Auto Layout Frame.
///
/// [FrameNode] extends [GroupNode] with automatic child positioning
/// and sizing based on [LayoutDirection], padding, spacing, and
/// per-child [LayoutConstraint]s.
///
/// ```dart
/// final frame = FrameNode(
///   id: 'toolbar',
///   direction: LayoutDirection.horizontal,
///   padding: EdgeInsets.all(16),
///   spacing: 8,
/// );
/// frame.addWithConstraint(buttonNode, LayoutConstraint(
///   primarySizing: SizingMode.fixed,
///   fixedWidth: 100,
/// ));
/// frame.performLayout(); // positions children automatically
/// ```
class FrameNode extends GroupNode {
  /// Direction children flow.
  LayoutDirection direction;

  /// Padding inside the frame.
  EdgeInsets padding;

  /// Spacing between children along the primary axis.
  double spacing;

  /// Main axis alignment.
  MainAxisAlignment mainAxisAlignment;

  /// Cross axis alignment.
  CrossAxisAlignment crossAxisAlignment;

  /// Whether the frame clips children that overflow.
  bool clipContent;

  /// Frame background color (optional).
  Color? fillColor;

  /// Frame border radius (optional).
  double borderRadius;

  /// Frame stroke/border color (optional).
  Color? strokeColor;
  double strokeWidth;

  /// Fixed size of the frame (null = hug content).
  Size? frameSize;

  /// Per-child layout constraints.
  final Map<String, LayoutConstraint> _constraints = {};

  FrameNode({
    required super.id,
    super.name = 'Frame',
    super.localTransform,
    super.opacity,
    super.blendMode,
    super.isVisible,
    super.isLocked,
    this.direction = LayoutDirection.vertical,
    this.padding = EdgeInsets.zero,
    this.spacing = 0,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.clipContent = true,
    this.fillColor,
    this.borderRadius = 0,
    this.strokeColor,
    this.strokeWidth = 1,
    this.frameSize,
  });

  // ---------------------------------------------------------------------------
  // Constraint management
  // ---------------------------------------------------------------------------

  /// Add a child with its layout constraint.
  void addWithConstraint(CanvasNode child, LayoutConstraint constraint) {
    add(child);
    _constraints[child.id] = constraint;
  }

  /// Get the constraint for a child, or a default one.
  LayoutConstraint constraintFor(String childId) =>
      _constraints[childId] ?? LayoutConstraint();

  /// Set/update the constraint for a child.
  void setConstraint(String childId, LayoutConstraint constraint) {
    _constraints[childId] = constraint;
  }

  /// Remove constraint when child is removed.
  @override
  bool remove(CanvasNode child) {
    _constraints.remove(child.id);
    return super.remove(child);
  }

  // ---------------------------------------------------------------------------
  // Layout engine
  // ---------------------------------------------------------------------------

  /// Perform auto layout — positions and sizes all children
  /// according to their constraints, padding, spacing, and alignment.
  void performLayout() {
    final visibleChildren = children.where((c) => c.isVisible).toList();
    if (visibleChildren.isEmpty) return;

    final isHorizontal = direction == LayoutDirection.horizontal;

    // Available space inside padding.
    final contentWidth =
        (frameSize?.width ?? _huggingWidth(visibleChildren)) -
        padding.left -
        padding.right;
    final contentHeight =
        (frameSize?.height ?? _huggingHeight(visibleChildren)) -
        padding.top -
        padding.bottom;

    final availableMain = isHorizontal ? contentWidth : contentHeight;
    final availableCross = isHorizontal ? contentHeight : contentWidth;

    // ---- Pass 1: Measure fixed + hug children ----
    double fixedTotal = 0;
    double totalFlexGrow = 0;
    final childSizes = <String, Size>{};

    for (final child in visibleChildren) {
      final constraint = constraintFor(child.id);
      final childBounds = child.localBounds;

      double mainSize;
      double crossSize;

      // Primary axis sizing
      switch (constraint.primarySizing) {
        case SizingMode.fixed:
          mainSize =
              isHorizontal
                  ? (constraint.fixedWidth ?? childBounds.width)
                  : (constraint.fixedHeight ?? childBounds.height);
          fixedTotal += mainSize;
        case SizingMode.hug:
          mainSize = isHorizontal ? childBounds.width : childBounds.height;
          fixedTotal += mainSize;
        case SizingMode.fill:
          mainSize = 0; // Resolved in pass 2
          totalFlexGrow += constraint.flexGrow;
      }

      // Cross axis sizing
      switch (constraint.crossSizing) {
        case SizingMode.fixed:
          crossSize =
              isHorizontal
                  ? (constraint.fixedHeight ?? childBounds.height)
                  : (constraint.fixedWidth ?? childBounds.width);
        case SizingMode.hug:
          crossSize = isHorizontal ? childBounds.height : childBounds.width;
        case SizingMode.fill:
          crossSize = availableCross;
      }

      // Apply min/max
      final w = isHorizontal ? mainSize : crossSize;
      final h = isHorizontal ? crossSize : mainSize;
      childSizes[child.id] = Size(
        w.clamp(constraint.minWidth, constraint.maxWidth),
        h.clamp(constraint.minHeight, constraint.maxHeight),
      );
    }

    // ---- Pass 2: Distribute remaining space to fill children ----
    final totalSpacing = spacing * (visibleChildren.length - 1);
    final remainingMain = availableMain - fixedTotal - totalSpacing;

    if (totalFlexGrow > 0 && remainingMain > 0) {
      for (final child in visibleChildren) {
        final constraint = constraintFor(child.id);
        if (constraint.primarySizing == SizingMode.fill) {
          final flexShare =
              (constraint.flexGrow / totalFlexGrow) * remainingMain;
          final current = childSizes[child.id]!;
          childSizes[child.id] =
              isHorizontal
                  ? Size(flexShare, current.height)
                  : Size(current.width, flexShare);
        }
      }
    }

    // ---- Pass 3: Position children ----
    double mainOffset = _mainAxisStartOffset(
      mainAxisAlignment,
      availableMain,
      fixedTotal + (totalFlexGrow > 0 ? remainingMain : 0),
      totalSpacing,
      visibleChildren.length,
    );

    for (final child in visibleChildren) {
      final size = childSizes[child.id]!;
      final childMain = isHorizontal ? size.width : size.height;
      final childCross = isHorizontal ? size.height : size.width;

      // Cross axis positioning
      final crossOffset = _crossAxisOffset(
        crossAxisAlignment,
        availableCross,
        childCross,
      );

      // Set position
      final x =
          isHorizontal ? padding.left + mainOffset : padding.left + crossOffset;
      final y =
          isHorizontal ? padding.top + crossOffset : padding.top + mainOffset;

      child.setPosition(x, y);

      // Advance along main axis
      mainOffset +=
          childMain +
          _mainAxisSpacing(
            mainAxisAlignment,
            availableMain,
            fixedTotal + (totalFlexGrow > 0 ? remainingMain : 0),
            totalSpacing,
            visibleChildren.length,
          );
    }
  }

  // ---------------------------------------------------------------------------
  // Layout calculation helpers
  // ---------------------------------------------------------------------------

  double _huggingWidth(List<CanvasNode> children) {
    if (direction == LayoutDirection.horizontal) {
      return padding.left +
          padding.right +
          children.fold<double>(0, (sum, c) => sum + c.localBounds.width) +
          spacing * (children.length - 1);
    } else {
      return padding.left +
          padding.right +
          children.fold<double>(
            0,
            (max, c) => c.localBounds.width > max ? c.localBounds.width : max,
          );
    }
  }

  double _huggingHeight(List<CanvasNode> children) {
    if (direction == LayoutDirection.vertical) {
      return padding.top +
          padding.bottom +
          children.fold<double>(0, (sum, c) => sum + c.localBounds.height) +
          spacing * (children.length - 1);
    } else {
      return padding.top +
          padding.bottom +
          children.fold<double>(
            0,
            (max, c) => c.localBounds.height > max ? c.localBounds.height : max,
          );
    }
  }

  double _mainAxisStartOffset(
    MainAxisAlignment alignment,
    double available,
    double contentTotal,
    double spacingTotal,
    int childCount,
  ) {
    switch (alignment) {
      case MainAxisAlignment.start:
        return 0;
      case MainAxisAlignment.center:
        return (available - contentTotal - spacingTotal) / 2;
      case MainAxisAlignment.end:
        return available - contentTotal - spacingTotal;
      case MainAxisAlignment.spaceBetween:
        return 0;
      case MainAxisAlignment.spaceAround:
        final gap = (available - contentTotal) / childCount;
        return gap / 2;
      case MainAxisAlignment.spaceEvenly:
        return (available - contentTotal) / (childCount + 1);
    }
  }

  double _mainAxisSpacing(
    MainAxisAlignment alignment,
    double available,
    double contentTotal,
    double spacingTotal,
    int childCount,
  ) {
    switch (alignment) {
      case MainAxisAlignment.start:
      case MainAxisAlignment.center:
      case MainAxisAlignment.end:
        return spacing;
      case MainAxisAlignment.spaceBetween:
        return childCount > 1
            ? (available - contentTotal) / (childCount - 1)
            : 0;
      case MainAxisAlignment.spaceAround:
        return (available - contentTotal) / childCount;
      case MainAxisAlignment.spaceEvenly:
        return (available - contentTotal) / (childCount + 1);
    }
  }

  double _crossAxisOffset(
    CrossAxisAlignment alignment,
    double available,
    double childSize,
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

  // ---------------------------------------------------------------------------
  // Bounds override
  // ---------------------------------------------------------------------------

  @override
  Rect get localBounds {
    if (frameSize != null) {
      return Rect.fromLTWH(0, 0, frameSize!.width, frameSize!.height);
    }
    return super.localBounds;
  }

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  @override
  Map<String, dynamic> toJson() {
    final json = baseToJson();
    json['nodeType'] = 'frame';
    json['direction'] = direction.name;
    json['padding'] = {
      'left': padding.left,
      'top': padding.top,
      'right': padding.right,
      'bottom': padding.bottom,
    };
    json['spacing'] = spacing;
    json['mainAxisAlignment'] = mainAxisAlignment.name;
    json['crossAxisAlignment'] = crossAxisAlignment.name;
    json['clipContent'] = clipContent;
    if (fillColor != null) json['fillColor'] = fillColor!.toARGB32();
    json['borderRadius'] = borderRadius;
    if (strokeColor != null) json['strokeColor'] = strokeColor!.toARGB32();
    json['strokeWidth'] = strokeWidth;
    if (frameSize != null) {
      json['frameSize'] = {
        'width': frameSize!.width,
        'height': frameSize!.height,
      };
    }
    json['children'] = children.map((c) => c.toJson()).toList();
    json['constraints'] = _constraints.map(
      (key, value) => MapEntry(key, value.toJson()),
    );
    return json;
  }

  factory FrameNode.fromJson(Map<String, dynamic> json) {
    final paddingJson = json['padding'] as Map<String, dynamic>? ?? {};
    final frameSizeJson = json['frameSize'] as Map<String, dynamic>?;

    final node = FrameNode(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Frame',
      direction: LayoutDirection.values.byName(
        json['direction'] as String? ?? 'vertical',
      ),
      padding: EdgeInsets.only(
        left: (paddingJson['left'] as num?)?.toDouble() ?? 0,
        top: (paddingJson['top'] as num?)?.toDouble() ?? 0,
        right: (paddingJson['right'] as num?)?.toDouble() ?? 0,
        bottom: (paddingJson['bottom'] as num?)?.toDouble() ?? 0,
      ),
      spacing: (json['spacing'] as num?)?.toDouble() ?? 0,
      mainAxisAlignment: MainAxisAlignment.values.byName(
        json['mainAxisAlignment'] as String? ?? 'start',
      ),
      crossAxisAlignment: CrossAxisAlignment.values.byName(
        json['crossAxisAlignment'] as String? ?? 'start',
      ),
      clipContent: json['clipContent'] as bool? ?? true,
      fillColor:
          json['fillColor'] != null ? Color(json['fillColor'] as int) : null,
      borderRadius: (json['borderRadius'] as num?)?.toDouble() ?? 0,
      strokeColor:
          json['strokeColor'] != null
              ? Color(json['strokeColor'] as int)
              : null,
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 1,
      frameSize:
          frameSizeJson != null
              ? Size(
                (frameSizeJson['width'] as num).toDouble(),
                (frameSizeJson['height'] as num).toDouble(),
              )
              : null,
    );

    CanvasNode.applyBaseFromJson(node, json);

    // Restore constraints
    final constraintsJson = json['constraints'] as Map<String, dynamic>? ?? {};
    for (final entry in constraintsJson.entries) {
      node._constraints[entry.key] = LayoutConstraint.fromJson(
        entry.value as Map<String, dynamic>,
      );
    }

    return node;
  }

  @override
  R accept<R>(NodeVisitor<R> visitor) => visitor.visitFrame(this);
}
