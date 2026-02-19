// =============================================================================
// 🎯 RESPONSIVE BREAKPOINT
//
// Immutable breakpoint definition for responsive variant resolution.
// A breakpoint defines a named width range (e.g. "mobile": 0–599px).
// When the viewport/parent width falls within [minWidth, maxWidth],
// the corresponding layout variant is activated.
// =============================================================================

/// Defines a named width range for responsive layout resolution.
///
/// Breakpoints are matched against the current viewport or parent width
/// to determine which [ResponsiveVariant] to apply on a [FrameNode].
///
/// ```dart
/// // Use built-in presets:
/// final breakpoints = ResponsiveBreakpoint.defaultPresets;
///
/// // Or define custom ones:
/// final custom = ResponsiveBreakpoint(
///   name: 'small-tablet',
///   minWidth: 600,
///   maxWidth: 839,
/// );
/// ```
///
/// DESIGN PRINCIPLES:
/// - Immutable — breakpoints are configuration, not state
/// - Ordered matching — first breakpoint whose range contains the width wins
/// - JSON-serializable with backward-compatible defaults
class ResponsiveBreakpoint {
  /// Human-readable name (e.g. 'mobile', 'tablet', 'desktop').
  final String name;

  /// Minimum width (inclusive) for this breakpoint to match.
  final double minWidth;

  /// Maximum width (inclusive) for this breakpoint to match.
  /// Use [double.infinity] for an open-ended upper bound.
  final double maxWidth;

  const ResponsiveBreakpoint({
    required this.name,
    required this.minWidth,
    this.maxWidth = double.infinity,
  });

  // ---------------------------------------------------------------------------
  // Default presets
  // ---------------------------------------------------------------------------

  /// Mobile breakpoint: 0 – 599px.
  static const mobile = ResponsiveBreakpoint(
    name: 'mobile',
    minWidth: 0,
    maxWidth: 599,
  );

  /// Tablet breakpoint: 600 – 1023px.
  static const tablet = ResponsiveBreakpoint(
    name: 'tablet',
    minWidth: 600,
    maxWidth: 1023,
  );

  /// Desktop breakpoint: 1024px and above.
  static const desktop = ResponsiveBreakpoint(name: 'desktop', minWidth: 1024);

  /// Default set of breakpoints: mobile, tablet, desktop.
  static const List<ResponsiveBreakpoint> defaultPresets = [
    mobile,
    tablet,
    desktop,
  ];

  // ---------------------------------------------------------------------------
  // Matching
  // ---------------------------------------------------------------------------

  /// Returns `true` if [width] falls within this breakpoint's range.
  bool matches(double width) => width >= minWidth && width <= maxWidth;

  /// Find the first matching breakpoint for [width] in [breakpoints].
  ///
  /// Returns `null` if no breakpoint matches.
  static ResponsiveBreakpoint? resolve(
    double width,
    List<ResponsiveBreakpoint> breakpoints,
  ) {
    for (final bp in breakpoints) {
      if (bp.matches(width)) return bp;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'name': name,
    'minWidth': minWidth,
    if (maxWidth != double.infinity) 'maxWidth': maxWidth,
  };

  factory ResponsiveBreakpoint.fromJson(Map<String, dynamic> json) {
    return ResponsiveBreakpoint(
      name: json['name'] as String,
      minWidth: (json['minWidth'] as num).toDouble(),
      maxWidth: (json['maxWidth'] as num?)?.toDouble() ?? double.infinity,
    );
  }

  // ---------------------------------------------------------------------------
  // Equality & toString
  // ---------------------------------------------------------------------------

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResponsiveBreakpoint &&
          name == other.name &&
          minWidth == other.minWidth &&
          maxWidth == other.maxWidth;

  @override
  int get hashCode => Object.hash(name, minWidth, maxWidth);

  @override
  String toString() =>
      'ResponsiveBreakpoint($name: $minWidth–${maxWidth == double.infinity ? '∞' : maxWidth})';

  /// Create a copy with optional field overrides.
  ResponsiveBreakpoint copyWith({
    String? name,
    double? minWidth,
    double? maxWidth,
  }) {
    return ResponsiveBreakpoint(
      name: name ?? this.name,
      minWidth: minWidth ?? this.minWidth,
      maxWidth: maxWidth ?? this.maxWidth,
    );
  }
}
