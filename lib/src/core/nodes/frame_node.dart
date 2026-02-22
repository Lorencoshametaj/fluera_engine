import 'dart:math' as math;
import 'package:flutter/material.dart'
    hide CrossAxisAlignment, MainAxisAlignment;
import '../scene_graph/canvas_node.dart';
import '../scene_graph/node_id.dart';
import '../scene_graph/node_visitor.dart';
import './group_node.dart';
import '../../systems/responsive_breakpoint.dart';
import '../../systems/responsive_variant.dart';

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

/// How a child sizes itself along a given axis.
enum SizingMode {
  /// Fixed pixel size (user-specified).
  fixed,

  /// Shrink-wrap to content.
  hug,

  /// Expand to fill available space.
  fill,
}

/// Whether a child participates in flow or is absolutely positioned.
enum PositionMode {
  /// Child is positioned by the layout engine (normal flow).
  auto,

  /// Child is placed at fixed coordinates, excluded from flow.
  absolute,
}

/// Whether children wrap to new lines when they overflow.
enum LayoutWrap {
  /// No wrapping — all children in a single line.
  noWrap,

  /// Wrap children to next line when they exceed available space.
  wrap,
}

/// Alignment of children along the cross axis.
enum CrossAxisAlignment {
  start,
  center,
  end,
  stretch,

  /// Align children by their reported [CanvasNode.baselineOffset].
  ///
  /// Nodes without a baseline fall back to [start] alignment.
  baseline,
}

/// Alignment of children along the main axis.
enum MainAxisAlignment {
  start,
  center,
  end,
  spaceBetween,
  spaceAround,
  spaceEvenly,
}

/// How a frame handles content that exceeds its bounds.
enum OverflowBehavior {
  /// Content is visible beyond the frame bounds.
  visible,

  /// Content is clipped at the frame bounds.
  hidden,

  /// Content is scrollable when exceeding bounds.
  scroll,
}

/// Whether children are arranged in a flow or stacked on top of each other.
enum LayoutMode {
  /// Standard auto-layout flow (horizontal or vertical).
  flow,

  /// Children overlap at their anchor position (like CSS position: relative).
  stack,
}

/// Anchor position for children in [LayoutMode.stack].
enum StackAnchor {
  topLeft,
  topCenter,
  topRight,
  centerLeft,
  center,
  centerRight,
  bottomLeft,
  bottomCenter,
  bottomRight,
}

// ---------------------------------------------------------------------------
// Layout Input
// ---------------------------------------------------------------------------

/// Constraints passed from a parent frame to its children during layout.
///
/// Enables children with [SizingMode.fill] to know the available space
/// provided by their parent, solving the key architectural gap where
/// nested frames couldn't resolve fill sizing.
///
/// ```dart
/// final input = LayoutInput(availableWidth: 400, availableHeight: 300);
/// childFrame.performLayout(input: input);
/// ```
class LayoutInput {
  /// Available width from the parent (null = unconstrained).
  final double? availableWidth;

  /// Available height from the parent (null = unconstrained).
  final double? availableHeight;

  const LayoutInput({this.availableWidth, this.availableHeight});

  @override
  String toString() => 'LayoutInput(w: $availableWidth, h: $availableHeight)';
}

// ---------------------------------------------------------------------------
// Layout Constraint
// ---------------------------------------------------------------------------

/// Per-child layout constraint within a [FrameNode].
///
/// Determines how the child behaves when its parent resizes.
///
/// DESIGN PRINCIPLES:
/// - Every field has a sensible default so constraints can be created
///   with just `LayoutConstraint()`.
/// - JSON serialization only emits non-default values for compactness.
/// - Fully backward-compatible: old JSON without new fields deserializes
///   with defaults.
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

  /// Whether this child participates in auto-layout flow or is
  /// absolutely positioned within the parent frame.
  PositionMode positionMode;

  /// Absolute X position (used when [positionMode] is [PositionMode.absolute]).
  double? absoluteX;

  /// Absolute Y position (used when [positionMode] is [PositionMode.absolute]).
  double? absoluteY;

  /// Optional aspect ratio (width / height). When set, the layout engine
  /// enforces this ratio after computing one dimension.
  double? aspectRatio;

  /// Per-child cross-axis alignment override.
  ///
  /// When non-null, overrides the parent frame's [CrossAxisAlignment]
  /// for this specific child only.
  CrossAxisAlignment? alignSelf;

  /// Anchor position when parent uses [LayoutMode.stack].
  ///
  /// Determines where this child is placed relative to the parent frame.
  /// Defaults to [StackAnchor.topLeft].
  StackAnchor stackAnchor;

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
    this.positionMode = PositionMode.auto,
    this.absoluteX,
    this.absoluteY,
    this.aspectRatio,
    this.alignSelf,
    this.stackAnchor = StackAnchor.topLeft,
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
    if (positionMode != PositionMode.auto) 'positionMode': positionMode.name,
    if (absoluteX != null) 'absoluteX': absoluteX,
    if (absoluteY != null) 'absoluteY': absoluteY,
    if (aspectRatio != null) 'aspectRatio': aspectRatio,
    if (alignSelf != null) 'alignSelf': alignSelf!.name,
    if (stackAnchor != StackAnchor.topLeft) 'stackAnchor': stackAnchor.name,
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
      positionMode: PositionMode.values.byName(
        json['positionMode'] as String? ?? 'auto',
      ),
      absoluteX: (json['absoluteX'] as num?)?.toDouble(),
      absoluteY: (json['absoluteY'] as num?)?.toDouble(),
      aspectRatio: (json['aspectRatio'] as num?)?.toDouble(),
      alignSelf:
          json['alignSelf'] != null
              ? CrossAxisAlignment.values.byName(json['alignSelf'] as String)
              : null,
      stackAnchor: StackAnchor.values.byName(
        json['stackAnchor'] as String? ?? 'topLeft',
      ),
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
/// DESIGN PRINCIPLES:
/// - Supports both auto-layout (flow) and absolute positioning modes
/// - Children can wrap to new lines when [wrap] is enabled
/// - Per-axis sizing (widthSizing / heightSizing) for independent control
/// - Aspect ratio enforcement on children
/// - alignSelf overrides for per-child cross-axis alignment
/// - Dirty flag for lazy layout resolution
/// - Nested frames are recursively laid out bottom-up
///
/// ```dart
/// final frame = FrameNode(
///   id: 'toolbar',
///   direction: LayoutDirection.horizontal,
///   padding: EdgeInsets.all(16),
///   spacing: 8,
///   wrap: LayoutWrap.wrap,
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
  /// Can be negative for overlapping children.
  double spacing;

  /// Main axis alignment.
  MainAxisAlignment mainAxisAlignment;

  /// Cross axis alignment.
  CrossAxisAlignment crossAxisAlignment;

  /// Whether children wrap to new lines on overflow.
  LayoutWrap wrap;

  /// How overflow content is handled.
  OverflowBehavior overflow;

  /// Whether children are laid out in flow or stacked.
  LayoutMode layoutMode;

  /// Deprecated — use [overflow] instead.
  @Deprecated('Use overflow instead')
  bool get clipContent => overflow == OverflowBehavior.hidden;

  /// Frame background color (optional).
  Color? fillColor;

  /// Frame border radius (optional).
  double borderRadius;

  /// Frame stroke/border color (optional).
  Color? strokeColor;
  double strokeWidth;

  /// Fixed size of the frame (null = hug content).
  Size? frameSize;

  /// Independent width sizing mode (overrides frameSize logic).
  SizingMode widthSizing;

  /// Independent height sizing mode (overrides frameSize logic).
  SizingMode heightSizing;

  /// Per-child layout constraints.
  final Map<String, LayoutConstraint> _constraints = {};

  /// Whether layout needs to be recalculated.
  bool _layoutDirty = true;

  /// Cached child sizes from the measure pass (two-pass optimization).
  /// Cleared on [markLayoutDirty].
  final Map<String, Size> _cachedChildSizes = {};

  /// Previous frame size — used by pin-edge calculations.
  Size? _lastFrameSize;

  // ---------------------------------------------------------------------------
  // Responsive variants
  // ---------------------------------------------------------------------------

  /// Breakpoint definitions for responsive layout.
  ///
  /// When non-empty, the layout engine uses these to select a
  /// [ResponsiveVariant] based on the current viewport width.
  List<ResponsiveBreakpoint> breakpoints;

  /// Per-breakpoint layout overrides, keyed by breakpoint name.
  final Map<String, ResponsiveVariant> _responsiveVariants = {};

  /// Snapshot of base values before responsive overrides are applied.
  /// Used by [restoreBaseValues] to undo overrides after layout.
  Map<String, dynamic>? _baseSnapshot;

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
    this.wrap = LayoutWrap.noWrap,
    this.overflow = OverflowBehavior.hidden,
    this.layoutMode = LayoutMode.flow,
    this.fillColor,
    this.borderRadius = 0,
    this.strokeColor,
    this.strokeWidth = 1,
    this.frameSize,
    this.widthSizing = SizingMode.hug,
    this.heightSizing = SizingMode.hug,
    this.breakpoints = const [],
  });

  // ---------------------------------------------------------------------------
  // Dirty flag
  // ---------------------------------------------------------------------------

  /// Whether this frame needs layout recalculation.
  bool get needsLayout => _layoutDirty;

  /// Mark this frame (and parent frames) as needing layout.
  void markLayoutDirty() {
    _layoutDirty = true;
    _cachedChildSizes.clear();
    // Propagate up — parent frames may need to re-measure.
    if (parent is FrameNode) {
      (parent as FrameNode).markLayoutDirty();
    }
  }

  // ---------------------------------------------------------------------------
  // Constraint management
  // ---------------------------------------------------------------------------

  /// Add a child with its layout constraint.
  void addWithConstraint(CanvasNode child, LayoutConstraint constraint) {
    add(child);
    _constraints[child.id] = constraint;
    markLayoutDirty();
  }

  /// Get the constraint for a child, or a default one.
  LayoutConstraint constraintFor(String childId) =>
      _constraints[childId] ?? LayoutConstraint();

  /// Set/update the constraint for a child.
  void setConstraint(String childId, LayoutConstraint constraint) {
    _constraints[childId] = constraint;
    markLayoutDirty();
  }

  /// Remove constraint when child is removed.
  @override
  bool remove(CanvasNode child) {
    _constraints.remove(child.id);
    final removed = super.remove(child);
    if (removed) markLayoutDirty();
    return removed;
  }

  // ---------------------------------------------------------------------------
  // Responsive variant management
  // ---------------------------------------------------------------------------

  /// Whether this frame has any responsive variants defined.
  bool get hasResponsiveVariants => _responsiveVariants.isNotEmpty;

  /// All registered responsive variants (unmodifiable view).
  Map<String, ResponsiveVariant> get responsiveVariants =>
      Map.unmodifiable(_responsiveVariants);

  /// Add or replace a responsive variant for a breakpoint.
  void addResponsiveVariant(ResponsiveVariant variant) {
    _responsiveVariants[variant.breakpointName] = variant;
    markLayoutDirty();
  }

  /// Remove the responsive variant for a breakpoint.
  void removeResponsiveVariant(String breakpointName) {
    _responsiveVariants.remove(breakpointName);
    markLayoutDirty();
  }

  /// Get the variant for a specific breakpoint, if any.
  ResponsiveVariant? variantFor(String breakpointName) =>
      _responsiveVariants[breakpointName];

  /// Apply responsive overrides for the given [viewportWidth].
  ///
  /// Resolves the matching breakpoint, then applies non-null overrides
  /// from the corresponding variant on top of the base values.
  /// Call [restoreBaseValues] after layout to undo the overrides.
  void applyResponsiveOverrides(double viewportWidth) {
    if (_responsiveVariants.isEmpty) return;

    final effectiveBreakpoints =
        breakpoints.isNotEmpty
            ? breakpoints
            : ResponsiveBreakpoint.defaultPresets;

    final bp = ResponsiveBreakpoint.resolve(
      viewportWidth,
      effectiveBreakpoints,
    );
    if (bp == null) return;

    final variant = _responsiveVariants[bp.name];
    if (variant == null) return;

    // Snapshot base values before overriding.
    _baseSnapshot = {
      'direction': direction,
      'padding': padding,
      'spacing': spacing,
      'mainAxisAlignment': mainAxisAlignment,
      'crossAxisAlignment': crossAxisAlignment,
      'wrap': wrap,
      'frameSize': frameSize,
      'widthSizing': widthSizing,
      'heightSizing': heightSizing,
      'constraintOverrides': variant.constraintOverrides.keys.toList(),
      'originalConstraints': {
        for (final childId in variant.constraintOverrides.keys)
          childId:
              _constraints.containsKey(childId) ? _constraints[childId] : null,
      },
    };

    // Apply overrides (null = inherit base).
    if (variant.direction != null) direction = variant.direction!;
    if (variant.padding != null) padding = variant.padding!;
    if (variant.spacing != null) spacing = variant.spacing!;
    if (variant.mainAxisAlignment != null) {
      mainAxisAlignment = variant.mainAxisAlignment!;
    }
    if (variant.crossAxisAlignment != null) {
      crossAxisAlignment = variant.crossAxisAlignment!;
    }
    if (variant.wrap != null) wrap = variant.wrap!;
    if (variant.frameSize != null) frameSize = variant.frameSize!;
    if (variant.widthSizing != null) widthSizing = variant.widthSizing!;
    if (variant.heightSizing != null) heightSizing = variant.heightSizing!;

    // Apply per-child constraint overrides.
    for (final entry in variant.constraintOverrides.entries) {
      _constraints[entry.key] = entry.value;
    }
  }

  /// Restore base values after responsive override was applied.
  ///
  /// Must be called after layout when [applyResponsiveOverrides] was used.
  void restoreBaseValues() {
    if (_baseSnapshot == null) return;

    direction = _baseSnapshot!['direction'] as LayoutDirection;
    padding = _baseSnapshot!['padding'] as EdgeInsets;
    spacing = _baseSnapshot!['spacing'] as double;
    mainAxisAlignment =
        _baseSnapshot!['mainAxisAlignment'] as MainAxisAlignment;
    crossAxisAlignment =
        _baseSnapshot!['crossAxisAlignment'] as CrossAxisAlignment;
    wrap = _baseSnapshot!['wrap'] as LayoutWrap;
    frameSize = _baseSnapshot!['frameSize'] as Size?;
    widthSizing = _baseSnapshot!['widthSizing'] as SizingMode;
    heightSizing = _baseSnapshot!['heightSizing'] as SizingMode;

    // Restore original constraints.
    final originals =
        _baseSnapshot!['originalConstraints'] as Map<String, dynamic>;
    for (final entry in originals.entries) {
      if (entry.value != null) {
        _constraints[entry.key] = entry.value as LayoutConstraint;
      } else {
        _constraints.remove(entry.key);
      }
    }

    _baseSnapshot = null;
  }

  // ---------------------------------------------------------------------------
  // Layout engine
  // ---------------------------------------------------------------------------

  /// Perform auto layout — positions and sizes all children
  /// according to their constraints, padding, spacing, and alignment.
  ///
  /// Handles:
  /// 1. Absolute positioning (excluded from flow)
  /// 2. Nested frames (recursive bottom-up layout with [LayoutInput])
  /// 3. Stack layout (children overlap at anchored positions)
  /// 4. Wrap layout (multi-line)
  /// 5. Flex-grow distribution
  /// 6. Aspect ratio enforcement
  /// 7. alignSelf per-child overrides
  /// 8. Baseline alignment
  ///
  /// [input] provides available dimensions from the parent frame,
  /// enabling children with [SizingMode.fill] to resolve correctly.
  void performLayout({LayoutInput? input}) {
    final allVisible = children.where((c) => c.isVisible).toList();
    if (allVisible.isEmpty) {
      _layoutDirty = false;
      return;
    }

    // Store previous frame size for pin-edge calculations.
    _lastFrameSize = frameSize;

    // Use LayoutInput to resolve fill sizing for this frame.
    if (input != null) {
      if (widthSizing == SizingMode.fill && input.availableWidth != null) {
        frameSize = Size(input.availableWidth!, frameSize?.height ?? 0);
      }
      if (heightSizing == SizingMode.fill && input.availableHeight != null) {
        frameSize = Size(frameSize?.width ?? 0, input.availableHeight!);
      }
    }

    // ---- Step 0: Recursively layout nested FrameNodes (bottom-up) ----
    // Compute available space for children before recursing.
    final resolvedWidth = _resolveFrameWidth(allVisible);
    final resolvedHeight = _resolveFrameHeight(allVisible);
    final childAvailWidth = resolvedWidth - padding.left - padding.right;
    final childAvailHeight = resolvedHeight - padding.top - padding.bottom;

    for (final child in allVisible) {
      if (child is FrameNode) {
        child.performLayout(
          input: LayoutInput(
            availableWidth: childAvailWidth,
            availableHeight: childAvailHeight,
          ),
        );
      }
    }

    // ---- Step 1: Separate absolute vs flow children ----
    final flowChildren = <CanvasNode>[];
    final absoluteChildren = <CanvasNode>[];

    for (final child in allVisible) {
      final constraint = constraintFor(child.id);
      if (constraint.positionMode == PositionMode.absolute) {
        absoluteChildren.add(child);
      } else {
        flowChildren.add(child);
      }
    }

    // Position absolute children.
    for (final child in absoluteChildren) {
      final constraint = constraintFor(child.id);
      child.setPosition(constraint.absoluteX ?? 0, constraint.absoluteY ?? 0);
    }

    // ---- Step 2: Route to layout mode ----
    if (flowChildren.isEmpty) {
      _layoutDirty = false;
      return;
    }

    if (layoutMode == LayoutMode.stack) {
      _performStackLayout(flowChildren);
    } else if (wrap == LayoutWrap.wrap) {
      _performWrapLayout(flowChildren);
    } else {
      _performSingleLineLayout(flowChildren);
    }

    _layoutDirty = false;
  }

  // ---------------------------------------------------------------------------
  // Single-line layout (no wrap)
  // ---------------------------------------------------------------------------

  void _performSingleLineLayout(List<CanvasNode> visibleChildren) {
    final isHorizontal = direction == LayoutDirection.horizontal;

    // Available space inside padding.
    final contentWidth =
        _resolveFrameWidth(visibleChildren) - padding.left - padding.right;
    final contentHeight =
        _resolveFrameHeight(visibleChildren) - padding.top - padding.bottom;

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

      // Primary axis sizing.
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

      // Cross axis sizing.
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

      // Convert back to width/height.
      double w = isHorizontal ? mainSize : crossSize;
      double h = isHorizontal ? crossSize : mainSize;

      // Apply aspect ratio.
      if (constraint.aspectRatio != null && constraint.aspectRatio! > 0) {
        h = w / constraint.aspectRatio!;
      }

      // Apply min/max.
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
          double w = isHorizontal ? flexShare : current.width;
          double h = isHorizontal ? current.height : flexShare;

          // Re-apply aspect ratio after fill sizing.
          if (constraint.aspectRatio != null && constraint.aspectRatio! > 0) {
            h = w / constraint.aspectRatio!;
          }

          childSizes[child.id] = Size(
            w.clamp(constraint.minWidth, constraint.maxWidth),
            h.clamp(constraint.minHeight, constraint.maxHeight),
          );
        }
      }
    }

    // ---- Pass 3: Position children ----
    // Pre-compute max baseline for baseline alignment.
    double? maxBaseline;
    if (crossAxisAlignment == CrossAxisAlignment.baseline) {
      for (final child in visibleChildren) {
        final bl = child.baselineOffset;
        if (bl != null && (maxBaseline == null || bl > maxBaseline)) {
          maxBaseline = bl;
        }
      }
    }

    double mainOffset = _mainAxisStartOffset(
      mainAxisAlignment,
      availableMain,
      fixedTotal + (totalFlexGrow > 0 ? math.max(0, remainingMain) : 0),
      totalSpacing,
      visibleChildren.length,
    );

    for (final child in visibleChildren) {
      final size = childSizes[child.id]!;
      final constraint = constraintFor(child.id);
      final childMain = isHorizontal ? size.width : size.height;
      final childCross = isHorizontal ? size.height : size.width;

      // Cross axis positioning — use alignSelf if set.
      final effectiveCrossAlign = constraint.alignSelf ?? crossAxisAlignment;
      final crossOffset = _crossAxisOffset(
        effectiveCrossAlign,
        availableCross,
        childCross,
        baselineOffset: child.baselineOffset,
        maxBaseline: maxBaseline,
      );

      // Set position.
      final x =
          isHorizontal ? padding.left + mainOffset : padding.left + crossOffset;
      final y =
          isHorizontal ? padding.top + crossOffset : padding.top + mainOffset;

      child.setPosition(x, y);
      _cachedChildSizes[child.id] = size;

      // Advance along main axis.
      mainOffset +=
          childMain +
          _mainAxisSpacing(
            mainAxisAlignment,
            availableMain,
            fixedTotal + (totalFlexGrow > 0 ? math.max(0, remainingMain) : 0),
            totalSpacing,
            visibleChildren.length,
          );
    }
  }

  // ---------------------------------------------------------------------------
  // Wrap layout (multi-line)
  // ---------------------------------------------------------------------------

  void _performWrapLayout(List<CanvasNode> visibleChildren) {
    final isHorizontal = direction == LayoutDirection.horizontal;

    final contentWidth =
        _resolveFrameWidth(visibleChildren) - padding.left - padding.right;
    final contentHeight =
        _resolveFrameHeight(visibleChildren) - padding.top - padding.bottom;

    final availableMain = isHorizontal ? contentWidth : contentHeight;

    // ---- Build lines by overflow ----
    final lines = <List<CanvasNode>>[];
    var currentLine = <CanvasNode>[];
    double currentLineMain = 0;

    for (final child in visibleChildren) {
      final constraint = constraintFor(child.id);
      final childBounds = child.localBounds;

      double mainSize;
      switch (constraint.primarySizing) {
        case SizingMode.fixed:
          mainSize =
              isHorizontal
                  ? (constraint.fixedWidth ?? childBounds.width)
                  : (constraint.fixedHeight ?? childBounds.height);
        case SizingMode.hug:
          mainSize = isHorizontal ? childBounds.width : childBounds.height;
        case SizingMode.fill:
          mainSize = isHorizontal ? childBounds.width : childBounds.height;
      }

      final spacingBefore = currentLine.isNotEmpty ? spacing : 0;

      if (currentLine.isNotEmpty &&
          currentLineMain + spacingBefore + mainSize > availableMain) {
        // Overflow — start new line
        lines.add(currentLine);
        currentLine = <CanvasNode>[child];
        currentLineMain = mainSize;
      } else {
        currentLine.add(child);
        currentLineMain += spacingBefore + mainSize;
      }
    }
    if (currentLine.isNotEmpty) {
      lines.add(currentLine);
    }

    // ---- Position each line ----
    double crossOffset = 0;

    for (final line in lines) {
      double mainOffset = 0;
      double maxCross = 0;

      for (final child in line) {
        final constraint = constraintFor(child.id);
        final childBounds = child.localBounds;

        double mainSize;
        switch (constraint.primarySizing) {
          case SizingMode.fixed:
            mainSize =
                isHorizontal
                    ? (constraint.fixedWidth ?? childBounds.width)
                    : (constraint.fixedHeight ?? childBounds.height);
          case SizingMode.hug:
            mainSize = isHorizontal ? childBounds.width : childBounds.height;
          case SizingMode.fill:
            mainSize = isHorizontal ? childBounds.width : childBounds.height;
        }

        double crossSize;
        switch (constraint.crossSizing) {
          case SizingMode.fixed:
            crossSize =
                isHorizontal
                    ? (constraint.fixedHeight ?? childBounds.height)
                    : (constraint.fixedWidth ?? childBounds.width);
          case SizingMode.hug:
            crossSize = isHorizontal ? childBounds.height : childBounds.width;
          case SizingMode.fill:
            crossSize = isHorizontal ? childBounds.height : childBounds.width;
        }

        // Apply aspect ratio.
        double w = isHorizontal ? mainSize : crossSize;
        double h = isHorizontal ? crossSize : mainSize;
        if (constraint.aspectRatio != null && constraint.aspectRatio! > 0) {
          h = w / constraint.aspectRatio!;
        }
        w = w.clamp(constraint.minWidth, constraint.maxWidth);
        h = h.clamp(constraint.minHeight, constraint.maxHeight);

        final childCross = isHorizontal ? h : w;
        maxCross = math.max(maxCross, childCross);

        // Set position.
        final x =
            isHorizontal
                ? padding.left + mainOffset
                : padding.left + crossOffset;
        final y =
            isHorizontal ? padding.top + crossOffset : padding.top + mainOffset;

        child.setPosition(x, y);

        mainOffset += mainSize + spacing;
      }

      crossOffset += maxCross + spacing;
    }
  }

  // ---------------------------------------------------------------------------
  // Frame size resolution
  // ---------------------------------------------------------------------------

  /// Resolve the frame width based on [widthSizing] or [frameSize].
  double _resolveFrameWidth(List<CanvasNode> flowChildren) {
    // frameSize takes precedence for backward compatibility.
    if (frameSize != null) return frameSize!.width;

    switch (widthSizing) {
      case SizingMode.fixed:
        return frameSize?.width ?? _huggingWidth(flowChildren);
      case SizingMode.hug:
        return _huggingWidth(flowChildren);
      case SizingMode.fill:
        // Fill parent — use parent's available width if known.
        return frameSize?.width ?? _huggingWidth(flowChildren);
    }
  }

  /// Resolve the frame height based on [heightSizing] or [frameSize].
  double _resolveFrameHeight(List<CanvasNode> flowChildren) {
    // frameSize takes precedence for backward compatibility.
    if (frameSize != null) return frameSize!.height;

    switch (heightSizing) {
      case SizingMode.fixed:
        return frameSize?.height ?? _huggingHeight(flowChildren);
      case SizingMode.hug:
        return _huggingHeight(flowChildren);
      case SizingMode.fill:
        return frameSize?.height ?? _huggingHeight(flowChildren);
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
    double childSize, {
    double? baselineOffset,
    double? maxBaseline,
  }) {
    switch (alignment) {
      case CrossAxisAlignment.start:
        return 0;
      case CrossAxisAlignment.center:
        return (available - childSize) / 2;
      case CrossAxisAlignment.end:
        return available - childSize;
      case CrossAxisAlignment.stretch:
        return 0;
      case CrossAxisAlignment.baseline:
        // Align by baseline if available, otherwise fall back to start.
        if (baselineOffset != null && maxBaseline != null) {
          return maxBaseline - baselineOffset;
        }
        return 0;
    }
  }

  // ---------------------------------------------------------------------------
  // Stack layout
  // ---------------------------------------------------------------------------

  /// Position children at their anchor positions within the frame.
  ///
  /// All children overlap. Each child's position is determined by its
  /// [StackAnchor] constraint relative to the frame's content area.
  void _performStackLayout(List<CanvasNode> visibleChildren) {
    final contentWidth =
        _resolveFrameWidth(visibleChildren) - padding.left - padding.right;
    final contentHeight =
        _resolveFrameHeight(visibleChildren) - padding.top - padding.bottom;

    for (final child in visibleChildren) {
      final constraint = constraintFor(child.id);
      final childBounds = child.localBounds;
      double childW = childBounds.width;
      double childH = childBounds.height;

      // Apply sizing.
      if (constraint.primarySizing == SizingMode.fixed) {
        childW = constraint.fixedWidth ?? childW;
        childH = constraint.fixedHeight ?? childH;
      } else if (constraint.primarySizing == SizingMode.fill) {
        childW = contentWidth;
        childH = contentHeight;
      }

      // Apply aspect ratio.
      if (constraint.aspectRatio != null && constraint.aspectRatio! > 0) {
        childH = childW / constraint.aspectRatio!;
      }

      // Apply min/max.
      childW = childW.clamp(constraint.minWidth, constraint.maxWidth);
      childH = childH.clamp(constraint.minHeight, constraint.maxHeight);

      // Compute anchor offset.
      double x = padding.left;
      double y = padding.top;

      switch (constraint.stackAnchor) {
        case StackAnchor.topLeft:
          break; // default
        case StackAnchor.topCenter:
          x += (contentWidth - childW) / 2;
        case StackAnchor.topRight:
          x += contentWidth - childW;
        case StackAnchor.centerLeft:
          y += (contentHeight - childH) / 2;
        case StackAnchor.center:
          x += (contentWidth - childW) / 2;
          y += (contentHeight - childH) / 2;
        case StackAnchor.centerRight:
          x += contentWidth - childW;
          y += (contentHeight - childH) / 2;
        case StackAnchor.bottomLeft:
          y += contentHeight - childH;
        case StackAnchor.bottomCenter:
          x += (contentWidth - childW) / 2;
          y += contentHeight - childH;
        case StackAnchor.bottomRight:
          x += contentWidth - childW;
          y += contentHeight - childH;
      }

      child.setPosition(x, y);
      _cachedChildSizes[child.id] = Size(childW, childH);
    }
  }

  // ---------------------------------------------------------------------------
  // Pin-edge resize behavior
  // ---------------------------------------------------------------------------

  /// Reposition and resize pinned children after the frame is resized.
  ///
  /// Call this after changing [frameSize] to apply pin-edge constraints.
  /// Children with `pinLeft + pinRight` stretch horizontally;
  /// children with `pinTop + pinBottom` stretch vertically.
  /// Single-edge pins maintain their distance to that edge.
  void applyPinConstraints(Size oldSize, Size newSize) {
    final dw = newSize.width - oldSize.width;
    final dh = newSize.height - oldSize.height;

    for (final child in children) {
      final constraint = constraintFor(child.id);
      if (constraint.positionMode == PositionMode.absolute) continue;

      final pos = child.position;
      final bounds = child.localBounds;
      double x = pos.dx;
      double y = pos.dy;
      double w = bounds.width;
      double h = bounds.height;

      // Horizontal pin logic.
      if (constraint.pinLeft && constraint.pinRight) {
        // Stretch: maintain left offset, expand width by delta.
        w += dw;
      } else if (constraint.pinRight) {
        // Move right: maintain distance to right edge.
        x += dw;
      }
      // pinLeft only: do nothing (left offset stays the same).
      // Neither: child stays at its current position.

      // Vertical pin logic.
      if (constraint.pinTop && constraint.pinBottom) {
        // Stretch: maintain top offset, expand height by delta.
        h += dh;
      } else if (constraint.pinBottom) {
        // Move down: maintain distance to bottom edge.
        y += dh;
      }
      // pinTop only: do nothing (top offset stays the same).
      // Neither: child stays at its current position.

      // Apply clamped size.
      w = w.clamp(constraint.minWidth, constraint.maxWidth);
      h = h.clamp(constraint.minHeight, constraint.maxHeight);

      child.setPosition(x, y);
    }
  }

  /// Resize this frame and recursively propagate constraints to all
  /// nested [FrameNode] children at any depth.
  ///
  /// This is the top-level entry point for responsive resize. It:
  /// 1. Applies pin constraints to direct children
  /// 2. For any child that is a [FrameNode], recursively propagates
  ///    the resize to its children
  /// 3. Re-runs layout at each level to update positions
  ///
  /// ```dart
  /// frame.resizeWithConstraintPropagation(
  ///   Size(400, 300), // old size
  ///   Size(600, 400), // new size
  /// );
  /// ```
  void resizeWithConstraintPropagation(Size oldSize, Size newSize) {
    frameSize = newSize;
    applyPinConstraints(oldSize, newSize);
    _propagateToNestedFrames(oldSize, newSize);
    performLayout();
  }

  /// Recursively propagate resize constraints to nested [FrameNode] children.
  void _propagateToNestedFrames(Size parentOldSize, Size parentNewSize) {
    for (final child in children) {
      if (child is FrameNode && child.frameSize != null) {
        final childConstraint = constraintFor(child.id);
        final childOldSize = child.frameSize!;

        // Compute new child size based on pin constraints.
        double newW = childOldSize.width;
        double newH = childOldSize.height;
        final dw = parentNewSize.width - parentOldSize.width;
        final dh = parentNewSize.height - parentOldSize.height;

        if (childConstraint.pinLeft && childConstraint.pinRight) {
          newW += dw;
        }
        if (childConstraint.pinTop && childConstraint.pinBottom) {
          newH += dh;
        }

        // Clamp to min/max.
        newW = newW.clamp(childConstraint.minWidth, childConstraint.maxWidth);
        newH = newH.clamp(childConstraint.minHeight, childConstraint.maxHeight);

        final childNewSize = Size(newW, newH);

        if (childNewSize != childOldSize) {
          // Recurse into nested frame.
          child.resizeWithConstraintPropagation(childOldSize, childNewSize);
        }
      }
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
    if (wrap != LayoutWrap.noWrap) json['wrap'] = wrap.name;
    json['overflow'] = overflow.name;
    if (layoutMode != LayoutMode.flow) json['layoutMode'] = layoutMode.name;
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
    if (widthSizing != SizingMode.hug) json['widthSizing'] = widthSizing.name;
    if (heightSizing != SizingMode.hug) {
      json['heightSizing'] = heightSizing.name;
    }
    json['children'] = children.map((c) => c.toJson()).toList();
    json['constraints'] = _constraints.map(
      (key, value) => MapEntry(key, value.toJson()),
    );
    // Responsive variants (optional, only emitted when present).
    if (breakpoints.isNotEmpty) {
      json['breakpoints'] = breakpoints.map((b) => b.toJson()).toList();
    }
    if (_responsiveVariants.isNotEmpty) {
      json['responsiveVariants'] = _responsiveVariants.map(
        (key, value) => MapEntry(key, value.toJson()),
      );
    }
    return json;
  }

  factory FrameNode.fromJson(Map<String, dynamic> json) {
    final paddingJson = json['padding'] as Map<String, dynamic>? ?? {};
    final frameSizeJson = json['frameSize'] as Map<String, dynamic>?;

    final node = FrameNode(
      id: NodeId(json['id'] as String),
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
      wrap: LayoutWrap.values.byName(json['wrap'] as String? ?? 'noWrap'),
      // Backward compat: read 'overflow' first, fall back to 'clipContent'.
      overflow:
          json['overflow'] != null
              ? OverflowBehavior.values.byName(json['overflow'] as String)
              : (json['clipContent'] as bool? ?? true)
              ? OverflowBehavior.hidden
              : OverflowBehavior.visible,
      layoutMode: LayoutMode.values.byName(
        json['layoutMode'] as String? ?? 'flow',
      ),
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
      widthSizing: SizingMode.values.byName(
        json['widthSizing'] as String? ?? 'hug',
      ),
      heightSizing: SizingMode.values.byName(
        json['heightSizing'] as String? ?? 'hug',
      ),
    );

    CanvasNode.applyBaseFromJson(node, json);

    // Restore constraints.
    final constraintsJson = json['constraints'] as Map<String, dynamic>? ?? {};
    for (final entry in constraintsJson.entries) {
      node._constraints[entry.key] = LayoutConstraint.fromJson(
        entry.value as Map<String, dynamic>,
      );
    }

    // Restore breakpoints (optional, backward-compatible).
    final breakpointsJson = json['breakpoints'] as List<dynamic>?;
    if (breakpointsJson != null) {
      node.breakpoints =
          breakpointsJson
              .map(
                (b) => ResponsiveBreakpoint.fromJson(b as Map<String, dynamic>),
              )
              .toList();
    }

    // Restore responsive variants (optional, backward-compatible).
    final variantsJson =
        json['responsiveVariants'] as Map<String, dynamic>? ?? {};
    for (final entry in variantsJson.entries) {
      node._responsiveVariants[entry.key] = ResponsiveVariant.fromJson(
        entry.value as Map<String, dynamic>,
      );
    }

    return node;
  }

  @override
  R accept<R>(NodeVisitor<R> visitor) => visitor.visitFrame(this);
}
