/// 🔄 SMART FILTER STACK — Ordered, re-editable filter pipeline.
///
/// Each filter in the stack can be independently enabled/disabled,
/// has its own opacity and blend mode, and the stack supports
/// insert/remove/reorder with dirty tracking for caching.
///
/// ```dart
/// final stack = SmartFilterStack();
/// stack.add(SmartFilter(
///   id: 'blur-1',
///   name: 'Gaussian Blur',
///   type: SmartFilterType.gaussianBlur,
///   parameters: {'radius': 4.0},
/// ));
/// ```
library;

// =============================================================================
// SMART FILTER TYPE
// =============================================================================

/// Types of smart filters available.
enum SmartFilterType {
  /// Gaussian blur with configurable radius.
  gaussianBlur,

  /// Sharpen using unsharp mask.
  sharpen,

  /// Box blur (fast, less quality).
  boxBlur,

  /// Noise reduction.
  denoise,

  /// Edge detection (Sobel).
  edgeDetect,

  /// Emboss/relief effect.
  emboss,

  /// Pixelation.
  pixelate,

  /// Vignette (darken edges).
  vignette,

  /// Chromatic aberration.
  chromaticAberration,

  /// Custom shader filter.
  custom,
}

// =============================================================================
// SMART FILTER
// =============================================================================

/// A single re-editable filter in the pipeline.
class SmartFilter {
  /// Unique identifier.
  final String id;

  /// Human-readable name.
  final String name;

  /// Filter type.
  final SmartFilterType type;

  /// Type-specific parameters.
  final Map<String, double> parameters;

  /// Whether this filter is active.
  bool enabled;

  /// Filter opacity (0 = no effect, 1 = full).
  double opacity;

  SmartFilter({
    required this.id,
    required this.name,
    required this.type,
    this.parameters = const {},
    this.enabled = true,
    this.opacity = 1.0,
  });

  /// Get a parameter with default.
  double param(String key, [double defaultValue = 0.0]) =>
      parameters[key] ?? defaultValue;

  /// Create a copy with updated fields.
  SmartFilter copyWith({
    String? id,
    String? name,
    SmartFilterType? type,
    Map<String, double>? parameters,
    bool? enabled,
    double? opacity,
  }) => SmartFilter(
    id: id ?? this.id,
    name: name ?? this.name,
    type: type ?? this.type,
    parameters: parameters ?? this.parameters,
    enabled: enabled ?? this.enabled,
    opacity: opacity ?? this.opacity,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'parameters': parameters,
    'enabled': enabled,
    'opacity': opacity,
  };

  factory SmartFilter.fromJson(Map<String, dynamic> json) => SmartFilter(
    id: json['id'] as String,
    name: json['name'] as String,
    type: SmartFilterType.values.firstWhere(
      (v) => v.name == json['type'],
      orElse: () => SmartFilterType.custom,
    ),
    parameters:
        (json['parameters'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, (v as num).toDouble()),
        ) ??
        {},
    enabled: json['enabled'] as bool? ?? true,
    opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
  );

  @override
  String toString() => 'SmartFilter($name, ${type.name}, enabled=$enabled)';
}

// =============================================================================
// SMART FILTER STACK
// =============================================================================

/// Ordered pipeline of smart filters with dirty tracking.
class SmartFilterStack {
  final List<SmartFilter> _filters;
  int _version = 0;

  SmartFilterStack([List<SmartFilter>? filters]) : _filters = filters ?? [];

  /// Unmodifiable view of filters.
  List<SmartFilter> get filters => List.unmodifiable(_filters);

  /// Number of filters.
  int get count => _filters.length;

  /// Whether the stack is empty.
  bool get isEmpty => _filters.isEmpty;

  /// Version counter (increments on every mutation for cache invalidation).
  int get version => _version;

  /// Add a filter to the end of the stack.
  void add(SmartFilter filter) {
    _filters.add(filter);
    _version++;
  }

  /// Insert a filter at a specific position.
  void insert(int index, SmartFilter filter) {
    _filters.insert(index.clamp(0, _filters.length), filter);
    _version++;
  }

  /// Remove a filter by ID. Returns true if found and removed.
  bool removeById(String id) {
    final before = _filters.length;
    _filters.removeWhere((f) => f.id == id);
    if (_filters.length < before) {
      _version++;
      return true;
    }
    return false;
  }

  /// Remove a filter at index.
  SmartFilter removeAt(int index) {
    final filter = _filters.removeAt(index);
    _version++;
    return filter;
  }

  /// Move a filter from [from] to [to].
  void reorder(int from, int to) {
    final filter = _filters.removeAt(from);
    _filters.insert(to.clamp(0, _filters.length), filter);
    _version++;
  }

  /// Find a filter by ID.
  SmartFilter? findById(String id) {
    for (final f in _filters) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// Toggle a filter's enabled state by ID.
  void toggleFilter(String id) {
    final filter = findById(id);
    if (filter != null) {
      filter.enabled = !filter.enabled;
      _version++;
    }
  }

  /// Get only enabled filters in order.
  List<SmartFilter> get activeFilters =>
      _filters.where((f) => f.enabled).toList();

  /// Content hash for cache invalidation.
  int get contentHash {
    var hash = 0;
    for (final f in _filters) {
      hash = hash * 31 + f.id.hashCode;
      hash = hash * 31 + f.enabled.hashCode;
      hash = hash * 31 + f.opacity.hashCode;
      hash = hash * 31 + f.parameters.hashCode;
    }
    return hash;
  }

  /// Clear all filters.
  void clear() {
    _filters.clear();
    _version++;
  }

  List<Map<String, dynamic>> toJson() =>
      _filters.map((f) => f.toJson()).toList();

  factory SmartFilterStack.fromJson(List<dynamic> json) => SmartFilterStack(
    json.map((j) => SmartFilter.fromJson(j as Map<String, dynamic>)).toList(),
  );

  @override
  String toString() => 'SmartFilterStack(filters=$count, v=$_version)';
}
