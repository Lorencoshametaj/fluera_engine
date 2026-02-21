/// 📐 AUTO LAYOUT CONFIG — Figma-style sizing, alignment, and spacing model.
///
/// Defines how children are distributed within a container frame:
/// direction, main/cross axis alignment, spacing, padding, sizing modes,
/// and overflow behavior.
///
/// ```dart
/// final config = AutoLayoutConfig(
///   direction: LayoutDirection.horizontal,
///   spacing: 12,
///   padding: EdgeInsets.all(16),
///   mainAxisAlignment: MainAxisAlignment.spaceBetween,
///   crossAxisAlignment: CrossAxisAlignment.center,
/// );
/// ```
library;

import 'dart:ui';

// =============================================================================
// ENUMS
// =============================================================================

/// Direction of child distribution.
enum LayoutDirection {
  /// Children laid out left-to-right.
  horizontal,

  /// Children laid out top-to-bottom.
  vertical,
}

/// Alignment along the main axis (direction of flow).
enum MainAxisAlignment {
  /// Pack children at start.
  start,

  /// Pack children at center.
  center,

  /// Pack children at end.
  end,

  /// Equal space between children, none at edges.
  spaceBetween,

  /// Equal space around each child.
  spaceAround,

  /// Equal space between and at edges.
  spaceEvenly,
}

/// Alignment along the cross axis (perpendicular to flow).
enum CrossAxisAlignment {
  /// Align to start of cross axis.
  start,

  /// Align to center of cross axis.
  center,

  /// Align to end of cross axis.
  end,

  /// Stretch to fill cross axis.
  stretch,
}

/// How a container sizes itself along an axis.
enum LayoutSizingMode {
  /// Fixed pixel size.
  fixed,

  /// Shrink to fit content.
  hugContents,

  /// Expand to fill parent.
  fillContainer,
}

/// What happens when children overflow the container.
enum OverflowBehavior {
  /// Children extend beyond bounds (visible).
  visible,

  /// Children are clipped at bounds.
  clip,

  /// Children wrap to next row/column.
  wrap,
}

// =============================================================================
// EDGE INSETS (lightweight, no Flutter dependency)
// =============================================================================

/// Padding/margin specification (matches Flutter's EdgeInsets API).
class LayoutEdgeInsets {
  final double left, top, right, bottom;

  const LayoutEdgeInsets.all(double value)
    : left = value,
      top = value,
      right = value,
      bottom = value;

  const LayoutEdgeInsets.symmetric({double horizontal = 0, double vertical = 0})
    : left = horizontal,
      right = horizontal,
      top = vertical,
      bottom = vertical;

  const LayoutEdgeInsets.only({
    this.left = 0,
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
  });

  static const zero = LayoutEdgeInsets.all(0);

  double get horizontal => left + right;
  double get vertical => top + bottom;

  Offset get topLeft => Offset(left, top);

  Map<String, dynamic> toJson() => {
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
  };

  factory LayoutEdgeInsets.fromJson(Map<String, dynamic> json) =>
      LayoutEdgeInsets.only(
        left: (json['left'] as num?)?.toDouble() ?? 0,
        top: (json['top'] as num?)?.toDouble() ?? 0,
        right: (json['right'] as num?)?.toDouble() ?? 0,
        bottom: (json['bottom'] as num?)?.toDouble() ?? 0,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LayoutEdgeInsets &&
          left == other.left &&
          top == other.top &&
          right == other.right &&
          bottom == other.bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'LayoutEdgeInsets($left, $top, $right, $bottom)';
}

// =============================================================================
// CHILD OVERRIDE
// =============================================================================

/// Per-child layout override within an auto-layout container.
class ChildOverride {
  /// Override sizing mode for this child.
  final LayoutSizingMode? sizing;

  /// Flex grow factor (0 = don't grow, 1+ = proportional).
  final double flexGrow;

  /// Per-child cross axis alignment override.
  final CrossAxisAlignment? selfAlign;

  /// Fixed size override (overrides intrinsic size).
  final double? fixedMainSize;

  const ChildOverride({
    this.sizing,
    this.flexGrow = 0,
    this.selfAlign,
    this.fixedMainSize,
  });

  Map<String, dynamic> toJson() => {
    if (sizing != null) 'sizing': sizing!.name,
    'flexGrow': flexGrow,
    if (selfAlign != null) 'selfAlign': selfAlign!.name,
    if (fixedMainSize != null) 'fixedMainSize': fixedMainSize,
  };

  @override
  String toString() => 'ChildOverride(grow=$flexGrow)';
}

// =============================================================================
// AUTO LAYOUT CONFIG
// =============================================================================

/// Complete layout configuration for a container frame.
class AutoLayoutConfig {
  /// Direction of child distribution.
  final LayoutDirection direction;

  /// Main axis alignment.
  final MainAxisAlignment mainAxisAlignment;

  /// Cross axis alignment.
  final CrossAxisAlignment crossAxisAlignment;

  /// Gap between children in pixels.
  final double spacing;

  /// Internal padding.
  final LayoutEdgeInsets padding;

  /// How the container sizes along the main axis.
  final LayoutSizingMode primarySizing;

  /// How the container sizes along the cross axis.
  final LayoutSizingMode counterSizing;

  /// Overflow behavior.
  final OverflowBehavior overflow;

  /// Whether to reverse child order.
  final bool reversed;

  const AutoLayoutConfig({
    this.direction = LayoutDirection.vertical,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.spacing = 0,
    this.padding = LayoutEdgeInsets.zero,
    this.primarySizing = LayoutSizingMode.hugContents,
    this.counterSizing = LayoutSizingMode.hugContents,
    this.overflow = OverflowBehavior.visible,
    this.reversed = false,
  });

  /// Whether this is a horizontal layout.
  bool get isHorizontal => direction == LayoutDirection.horizontal;

  /// Create a copy with updated fields.
  AutoLayoutConfig copyWith({
    LayoutDirection? direction,
    MainAxisAlignment? mainAxisAlignment,
    CrossAxisAlignment? crossAxisAlignment,
    double? spacing,
    LayoutEdgeInsets? padding,
    LayoutSizingMode? primarySizing,
    LayoutSizingMode? counterSizing,
    OverflowBehavior? overflow,
    bool? reversed,
  }) => AutoLayoutConfig(
    direction: direction ?? this.direction,
    mainAxisAlignment: mainAxisAlignment ?? this.mainAxisAlignment,
    crossAxisAlignment: crossAxisAlignment ?? this.crossAxisAlignment,
    spacing: spacing ?? this.spacing,
    padding: padding ?? this.padding,
    primarySizing: primarySizing ?? this.primarySizing,
    counterSizing: counterSizing ?? this.counterSizing,
    overflow: overflow ?? this.overflow,
    reversed: reversed ?? this.reversed,
  );

  Map<String, dynamic> toJson() => {
    'direction': direction.name,
    'mainAxisAlignment': mainAxisAlignment.name,
    'crossAxisAlignment': crossAxisAlignment.name,
    'spacing': spacing,
    'padding': padding.toJson(),
    'primarySizing': primarySizing.name,
    'counterSizing': counterSizing.name,
    'overflow': overflow.name,
    'reversed': reversed,
  };

  factory AutoLayoutConfig.fromJson(Map<String, dynamic> json) =>
      AutoLayoutConfig(
        direction: LayoutDirection.values.firstWhere(
          (v) => v.name == json['direction'],
          orElse: () => LayoutDirection.vertical,
        ),
        mainAxisAlignment: MainAxisAlignment.values.firstWhere(
          (v) => v.name == json['mainAxisAlignment'],
          orElse: () => MainAxisAlignment.start,
        ),
        crossAxisAlignment: CrossAxisAlignment.values.firstWhere(
          (v) => v.name == json['crossAxisAlignment'],
          orElse: () => CrossAxisAlignment.start,
        ),
        spacing: (json['spacing'] as num?)?.toDouble() ?? 0,
        padding:
            json['padding'] != null
                ? LayoutEdgeInsets.fromJson(
                  json['padding'] as Map<String, dynamic>,
                )
                : LayoutEdgeInsets.zero,
        primarySizing: LayoutSizingMode.values.firstWhere(
          (v) => v.name == json['primarySizing'],
          orElse: () => LayoutSizingMode.hugContents,
        ),
        counterSizing: LayoutSizingMode.values.firstWhere(
          (v) => v.name == json['counterSizing'],
          orElse: () => LayoutSizingMode.hugContents,
        ),
        overflow: OverflowBehavior.values.firstWhere(
          (v) => v.name == json['overflow'],
          orElse: () => OverflowBehavior.visible,
        ),
        reversed: json['reversed'] as bool? ?? false,
      );

  @override
  String toString() =>
      'AutoLayoutConfig(${direction.name}, spacing=$spacing, '
      '${mainAxisAlignment.name}/${crossAxisAlignment.name})';
}
