import 'package:flutter/material.dart'
    hide CrossAxisAlignment, MainAxisAlignment;
import '../core/nodes/frame_node.dart';

// =============================================================================
// 🎯 RESPONSIVE VARIANT
//
// Per-breakpoint layout override for a FrameNode. Only non-null fields
// override the base frame properties — everything else is inherited.
// =============================================================================

/// Per-breakpoint layout override for a [FrameNode].
///
/// Only non-null fields replace the frame's base values during layout
/// resolution. This allows each breakpoint to tweak only what changes
/// (e.g. switch from horizontal to vertical on mobile) while keeping
/// everything else from the base definition.
///
/// ```dart
/// final mobileVariant = ResponsiveVariant(
///   breakpointName: 'mobile',
///   direction: LayoutDirection.vertical,
///   spacing: 8,
///   padding: EdgeInsets.all(12),
/// );
/// ```
///
/// DESIGN PRINCIPLES:
/// - Override model: null = inherit from base
/// - Per-child constraint overrides via [constraintOverrides]
/// - Fully JSON-serializable with backward-compatible defaults
/// - Immutable after construction (fields are final)
class ResponsiveVariant {
  /// Name of the breakpoint this variant applies to.
  final String breakpointName;

  // ---------------------------------------------------------------------------
  // Frame-level overrides (null = inherit from base)
  // ---------------------------------------------------------------------------

  /// Override for layout direction.
  final LayoutDirection? direction;

  /// Override for frame padding.
  final EdgeInsets? padding;

  /// Override for spacing between children.
  final double? spacing;

  /// Override for main axis alignment.
  final MainAxisAlignment? mainAxisAlignment;

  /// Override for cross axis alignment.
  final CrossAxisAlignment? crossAxisAlignment;

  /// Override for wrap mode.
  final LayoutWrap? wrap;

  /// Override for frame size.
  final Size? frameSize;

  /// Override for width sizing mode.
  final SizingMode? widthSizing;

  /// Override for height sizing mode.
  final SizingMode? heightSizing;

  // ---------------------------------------------------------------------------
  // Per-child constraint overrides
  // ---------------------------------------------------------------------------

  /// Per-child layout constraint overrides, keyed by child node ID.
  ///
  /// Only children listed here get their constraints replaced for
  /// this breakpoint. All other children keep their base constraints.
  final Map<String, LayoutConstraint> constraintOverrides;

  const ResponsiveVariant({
    required this.breakpointName,
    this.direction,
    this.padding,
    this.spacing,
    this.mainAxisAlignment,
    this.crossAxisAlignment,
    this.wrap,
    this.frameSize,
    this.widthSizing,
    this.heightSizing,
    this.constraintOverrides = const {},
  });

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'breakpointName': breakpointName,
    if (direction != null) 'direction': direction!.name,
    if (padding != null)
      'padding': {
        'left': padding!.left,
        'top': padding!.top,
        'right': padding!.right,
        'bottom': padding!.bottom,
      },
    if (spacing != null) 'spacing': spacing,
    if (mainAxisAlignment != null) 'mainAxisAlignment': mainAxisAlignment!.name,
    if (crossAxisAlignment != null)
      'crossAxisAlignment': crossAxisAlignment!.name,
    if (wrap != null) 'wrap': wrap!.name,
    if (frameSize != null)
      'frameSize': {'width': frameSize!.width, 'height': frameSize!.height},
    if (widthSizing != null) 'widthSizing': widthSizing!.name,
    if (heightSizing != null) 'heightSizing': heightSizing!.name,
    if (constraintOverrides.isNotEmpty)
      'constraintOverrides': constraintOverrides.map(
        (key, value) => MapEntry(key, value.toJson()),
      ),
  };

  factory ResponsiveVariant.fromJson(Map<String, dynamic> json) {
    final paddingJson = json['padding'] as Map<String, dynamic>?;
    final frameSizeJson = json['frameSize'] as Map<String, dynamic>?;
    final constraintsJson =
        json['constraintOverrides'] as Map<String, dynamic>? ?? {};

    return ResponsiveVariant(
      breakpointName: json['breakpointName'] as String,
      direction:
          json['direction'] != null
              ? LayoutDirection.values.byName(json['direction'] as String)
              : null,
      padding:
          paddingJson != null
              ? EdgeInsets.only(
                left: (paddingJson['left'] as num?)?.toDouble() ?? 0,
                top: (paddingJson['top'] as num?)?.toDouble() ?? 0,
                right: (paddingJson['right'] as num?)?.toDouble() ?? 0,
                bottom: (paddingJson['bottom'] as num?)?.toDouble() ?? 0,
              )
              : null,
      spacing: (json['spacing'] as num?)?.toDouble(),
      mainAxisAlignment:
          json['mainAxisAlignment'] != null
              ? MainAxisAlignment.values.byName(
                json['mainAxisAlignment'] as String,
              )
              : null,
      crossAxisAlignment:
          json['crossAxisAlignment'] != null
              ? CrossAxisAlignment.values.byName(
                json['crossAxisAlignment'] as String,
              )
              : null,
      wrap:
          json['wrap'] != null
              ? LayoutWrap.values.byName(json['wrap'] as String)
              : null,
      frameSize:
          frameSizeJson != null
              ? Size(
                (frameSizeJson['width'] as num).toDouble(),
                (frameSizeJson['height'] as num).toDouble(),
              )
              : null,
      widthSizing:
          json['widthSizing'] != null
              ? SizingMode.values.byName(json['widthSizing'] as String)
              : null,
      heightSizing:
          json['heightSizing'] != null
              ? SizingMode.values.byName(json['heightSizing'] as String)
              : null,
      constraintOverrides: constraintsJson.map(
        (key, value) => MapEntry(
          key,
          LayoutConstraint.fromJson(value as Map<String, dynamic>),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Equality & toString
  // ---------------------------------------------------------------------------

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResponsiveVariant && breakpointName == other.breakpointName;

  @override
  int get hashCode => breakpointName.hashCode;

  @override
  String toString() => 'ResponsiveVariant($breakpointName)';

  /// Create a copy with optional field overrides.
  ResponsiveVariant copyWith({
    String? breakpointName,
    LayoutDirection? direction,
    EdgeInsets? padding,
    double? spacing,
    MainAxisAlignment? mainAxisAlignment,
    CrossAxisAlignment? crossAxisAlignment,
    LayoutWrap? wrap,
    Size? frameSize,
    SizingMode? widthSizing,
    SizingMode? heightSizing,
    Map<String, LayoutConstraint>? constraintOverrides,
  }) {
    return ResponsiveVariant(
      breakpointName: breakpointName ?? this.breakpointName,
      direction: direction ?? this.direction,
      padding: padding ?? this.padding,
      spacing: spacing ?? this.spacing,
      mainAxisAlignment: mainAxisAlignment ?? this.mainAxisAlignment,
      crossAxisAlignment: crossAxisAlignment ?? this.crossAxisAlignment,
      wrap: wrap ?? this.wrap,
      frameSize: frameSize ?? this.frameSize,
      widthSizing: widthSizing ?? this.widthSizing,
      heightSizing: heightSizing ?? this.heightSizing,
      constraintOverrides: constraintOverrides ?? this.constraintOverrides,
    );
  }
}
