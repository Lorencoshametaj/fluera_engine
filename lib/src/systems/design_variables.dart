import 'package:flutter/foundation.dart';
import '../core/engine_scope.dart';
import '../core/engine_event.dart';

// =============================================================================
// 🎨 DESIGN VARIABLES / TOKENS RUNTIME
//
// Figma-style variable system supporting color, number, string, and boolean
// variables with multi-mode values (e.g. dark/light themes, responsive
// breakpoints). Variables live in collections that share the same set of modes.
// =============================================================================

/// Supported variable value types.
///
/// Each type maps to a specific Dart type for runtime resolution:
/// - [color] → `int` (ARGB32 color value)
/// - [number] → `double`
/// - [string] → `String`
/// - [boolean] → `bool`
enum DesignVariableType { color, number, string, boolean }

/// Describes a change to a design variable value.
class VariableChangeEvent {
  /// The variable that changed.
  final String variableId;

  /// The mode that was affected (or `null` if the variable itself changed).
  final String? modeId;

  /// The property that changed (e.g. 'value', 'name', 'alias').
  final String property;

  /// The old value (may be `null`).
  final dynamic oldValue;

  /// The new value (may be `null`).
  final dynamic newValue;

  const VariableChangeEvent({
    required this.variableId,
    this.modeId,
    required this.property,
    this.oldValue,
    this.newValue,
  });

  @override
  String toString() =>
      'VariableChangeEvent($variableId${modeId != null ? "[$modeId]" : ""}'
      '.$property: $oldValue → $newValue)';
}

/// Callback for variable change events.
typedef VariableChangeCallback = void Function(VariableChangeEvent event);

// ---------------------------------------------------------------------------
// Variable Mode
// ---------------------------------------------------------------------------

/// A named mode within a [VariableCollection].
///
/// Modes represent different contexts in which variables take on different
/// values — for example "Light" / "Dark" for themes, or "Mobile" / "Desktop"
/// for responsive breakpoints.
///
/// ```dart
/// final lightMode = VariableMode(id: 'light', name: 'Light');
/// final darkMode  = VariableMode(id: 'dark',  name: 'Dark');
/// ```
class VariableMode {
  /// Unique identifier within the collection.
  final String id;

  /// Human-readable display name.
  String name;

  /// Optional parent mode ID for inheritance.
  ///
  /// When resolving a variable, if the current mode has no value,
  /// the resolver will check the parent mode before falling back
  /// to the collection default.
  final String? inheritsFrom;

  VariableMode({required this.id, required this.name, this.inheritsFrom});

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'id': id, 'name': name};
    if (inheritsFrom != null) json['inheritsFrom'] = inheritsFrom;
    return json;
  }

  factory VariableMode.fromJson(Map<String, dynamic> json) => VariableMode(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    inheritsFrom: json['inheritsFrom'] as String?,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is VariableMode && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'VariableMode(id: $id, name: "$name"'
      '${inheritsFrom != null ? ", inherits: $inheritsFrom" : ""})';
}

// ---------------------------------------------------------------------------
// Variable Constraints
// ---------------------------------------------------------------------------

/// Optional constraints on a [DesignVariable]'s value.
///
/// ```dart
/// const opacity = VariableConstraints(min: 0, max: 1);
/// const align = VariableConstraints(allowedValues: ['left', 'center', 'right']);
/// ```
class VariableConstraints {
  /// Minimum value (applies to [DesignVariableType.number] only).
  final num? min;

  /// Maximum value (applies to [DesignVariableType.number] only).
  final num? max;

  /// Allowed string values (applies to [DesignVariableType.string] only).
  final List<String>? allowedValues;

  const VariableConstraints({this.min, this.max, this.allowedValues});

  /// Validate a value against these constraints.
  ///
  /// Returns an error message if invalid, or `null` if valid.
  String? validate(dynamic value, DesignVariableType type) {
    if (value == null) return null;

    if (type == DesignVariableType.number && value is num) {
      if (min != null && value < min!) {
        return 'Value $value is below minimum $min';
      }
      if (max != null && value > max!) {
        return 'Value $value exceeds maximum $max';
      }
    }

    if (type == DesignVariableType.string &&
        value is String &&
        allowedValues != null) {
      if (!allowedValues!.contains(value)) {
        return 'Value "$value" not in allowed values: $allowedValues';
      }
    }

    return null;
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (min != null) json['min'] = min;
    if (max != null) json['max'] = max;
    if (allowedValues != null) json['allowedValues'] = allowedValues;
    return json;
  }

  factory VariableConstraints.fromJson(Map<String, dynamic> json) =>
      VariableConstraints(
        min: json['min'] as num?,
        max: json['max'] as num?,
        allowedValues:
            (json['allowedValues'] as List<dynamic>?)?.cast<String>(),
      );
}

// ---------------------------------------------------------------------------
// Design Variable
// ---------------------------------------------------------------------------

/// A single design variable with per-mode values.
///
/// Each variable has a fixed [type] and stores a value for each mode
/// in the owning collection. When resolving, the active mode's value is used;
/// if the active mode has no value, falls back to the first mode's value.
///
/// ```dart
/// final bgColor = DesignVariable(
///   id: 'bg-primary',
///   name: 'Background Primary',
///   type: DesignVariableType.color,
///   values: {
///     'light': 0xFFFFFFFF,
///     'dark':  0xFF1A1A1A,
///   },
/// );
/// ```
///
/// DESIGN PRINCIPLES:
/// - Type-safe: values are validated against the declared type on set
/// - Mode-keyed: each value is stored per mode ID
/// - Fallback: resolves to first mode value if active mode is unset
/// - Observable: fires [VariableChangeEvent] on mutations
class DesignVariable {
  /// Unique identifier.
  final String id;

  /// Human-readable display name.
  String _name;

  /// The value type of this variable.
  final DesignVariableType type;

  /// Description / documentation for this variable.
  String? description;

  /// Hierarchical group path (e.g. 'colors/primary', 'spacing/large').
  ///
  /// Used for organizing variables into folders in the UI. `null` means
  /// ungrouped.
  String? group;

  /// Optional value constraints (min/max for numbers, allowed values for strings).
  VariableConstraints? constraints;

  /// Scope node ID — when set, this variable only applies to descendants
  /// of the node with this ID. `null` means global scope.
  String? scopeNodeId;

  /// Whether this variable is locked (published).
  ///
  /// When `true`, [setValue] will throw a [StateError]. Use this to
  /// protect published/finalized tokens from accidental edits.
  bool isLocked;

  /// Optional alias: references another variable by ID.
  ///
  /// When set, [resolve] on this variable should be redirected to the
  /// referenced variable. Use [DesignVariableResolver] or the collection's
  /// `resolveAll()` for full alias resolution.
  String? _aliasVariableId;

  /// Values keyed by mode ID.
  final Map<String, dynamic> _values;

  /// Change listeners for fine-grained observation.
  final ObserverList<VariableChangeCallback> _listeners = ObserverList();

  // ---- Public getters/setters with change notification ----

  String get name => _name;
  set name(String value) {
    if (_name == value) return;
    final old = _name;
    _name = value;
    _fireChange(
      VariableChangeEvent(
        variableId: id,
        property: 'name',
        oldValue: old,
        newValue: value,
      ),
    );
  }

  String? get aliasVariableId => _aliasVariableId;
  set aliasVariableId(String? value) {
    if (_aliasVariableId == value) return;
    final old = _aliasVariableId;
    _aliasVariableId = value;
    _fireChange(
      VariableChangeEvent(
        variableId: id,
        property: 'alias',
        oldValue: old,
        newValue: value,
      ),
    );
  }

  /// Read-only access to the values map.
  Map<String, dynamic> get values => Map.unmodifiable(_values);

  DesignVariable({
    required this.id,
    required String name,
    required this.type,
    this.description,
    this.group,
    this.constraints,
    this.scopeNodeId,
    this.isLocked = false,
    String? aliasVariableId,
    Map<String, dynamic>? values,
  }) : _name = name,
       _aliasVariableId = aliasVariableId,
       _values = values != null ? Map<String, dynamic>.from(values) : {};

  /// Create a copy with optional overrides.
  DesignVariable copyWith({
    String? id,
    String? name,
    DesignVariableType? type,
    String? description,
    String? group,
    VariableConstraints? constraints,
    String? scopeNodeId,
    bool? isLocked,
    String? aliasVariableId,
    Map<String, dynamic>? values,
  }) {
    return DesignVariable(
      id: id ?? this.id,
      name: name ?? _name,
      type: type ?? this.type,
      description: description ?? this.description,
      group: group ?? this.group,
      constraints: constraints ?? this.constraints,
      scopeNodeId: scopeNodeId ?? this.scopeNodeId,
      isLocked: isLocked ?? this.isLocked,
      aliasVariableId: aliasVariableId ?? _aliasVariableId,
      values: values ?? Map<String, dynamic>.from(_values),
    );
  }

  // ---- Change observation ----

  /// Add a change listener.
  void addListener(VariableChangeCallback listener) => _listeners.add(listener);

  /// Remove a change listener.
  void removeListener(VariableChangeCallback listener) =>
      _listeners.remove(listener);

  void _fireChange(VariableChangeEvent event) {
    for (final listener in _listeners) {
      listener(event);
    }
  }

  // ---- Value CRUD ----

  /// Set the value for a specific mode.
  ///
  /// Throws [StateError] if the variable is [isLocked].
  /// Throws [ArgumentError] if the value doesn't match the declared [type].
  void setValue(String modeId, dynamic value) {
    if (isLocked) {
      throw StateError('Variable "$_name" is locked and cannot be modified');
    }
    _validateType(value);
    final old = _values[modeId];
    if (old == value) return;
    _values[modeId] = value;
    _fireChange(
      VariableChangeEvent(
        variableId: id,
        modeId: modeId,
        property: 'value',
        oldValue: old,
        newValue: value,
      ),
    );
    // Bridge to centralized event bus
    if (EngineScope.hasScope) {
      EngineScope.current.eventBus.emit(
        VariableChangedEngineEvent(
          variableId: id,
          modeId: modeId,
          property: 'value',
          oldValue: old,
          newValue: value,
        ),
      );
    }
  }

  /// Get the value for a specific mode, or `null` if unset.
  dynamic getValue(String modeId) => _values[modeId];

  /// Resolve the current value given the active mode.
  ///
  /// Falls back to the first mode's value if the active mode has no value,
  /// then to `null` if no values exist at all.
  ///
  /// Note: does NOT resolve aliases — use [VariableCollection.resolveAll]
  /// or handle alias chains externally.
  dynamic resolve(String activeModeId) {
    if (_values.containsKey(activeModeId)) return _values[activeModeId];
    if (_values.isNotEmpty) return _values.values.first;
    return null;
  }

  // ---- Type-safe resolve helpers ----

  /// Resolve as `int` (ARGB32 color value). Returns `null` if unset or wrong type.
  int? resolveColor(String activeModeId) {
    final v = resolve(activeModeId);
    return v is int ? v : null;
  }

  /// Resolve as `double`. Returns `null` if unset or wrong type.
  double? resolveNumber(String activeModeId) {
    final v = resolve(activeModeId);
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return null;
  }

  /// Resolve as `String`. Returns `null` if unset or wrong type.
  String? resolveString(String activeModeId) {
    final v = resolve(activeModeId);
    return v is String ? v : null;
  }

  /// Resolve as `bool`. Returns `null` if unset or wrong type.
  bool? resolveBool(String activeModeId) {
    final v = resolve(activeModeId);
    return v is bool ? v : null;
  }

  /// Whether this variable is an alias (references another variable).
  bool get isAlias => _aliasVariableId != null;

  /// Remove the value for a specific mode.
  void removeValue(String modeId) {
    final old = _values.remove(modeId);
    if (old != null) {
      _fireChange(
        VariableChangeEvent(
          variableId: id,
          modeId: modeId,
          property: 'value',
          oldValue: old,
          newValue: null,
        ),
      );
    }
  }

  /// Whether this variable has a value for the given mode.
  bool hasValueForMode(String modeId) => _values.containsKey(modeId);

  // ---- Validation ----

  void _validateType(dynamic value) {
    if (value == null) return; // null is always allowed (clear value)
    switch (type) {
      case DesignVariableType.color:
        if (value is! int) {
          throw ArgumentError(
            'Color variable "$_name" expects int (ARGB32), got ${value.runtimeType}',
          );
        }
      case DesignVariableType.number:
        if (value is! num) {
          throw ArgumentError(
            'Number variable "$_name" expects num, got ${value.runtimeType}',
          );
        }
      case DesignVariableType.string:
        if (value is! String) {
          throw ArgumentError(
            'String variable "$_name" expects String, got ${value.runtimeType}',
          );
        }
      case DesignVariableType.boolean:
        if (value is! bool) {
          throw ArgumentError(
            'Boolean variable "$_name" expects bool, got ${value.runtimeType}',
          );
        }
    }

    // Enforce constraints if present.
    if (constraints != null) {
      final error = constraints!.validate(value, type);
      if (error != null) {
        throw ArgumentError('$_name: $error');
      }
    }
  }

  /// Validate that all values match the declared type.
  ///
  /// Returns a list of mode IDs with invalid values.
  List<String> validateAllValues() {
    final invalid = <String>[];
    for (final entry in _values.entries) {
      try {
        _validateType(entry.value);
      } on ArgumentError {
        invalid.add(entry.key);
      }
    }
    return invalid;
  }

  // ---- Serialization ----

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'id': id,
      'name': _name,
      'type': type.name,
      'values': Map<String, dynamic>.from(_values),
    };
    if (description != null) json['description'] = description;
    if (group != null) json['group'] = group;
    if (constraints != null) json['constraints'] = constraints!.toJson();
    if (scopeNodeId != null) json['scopeNodeId'] = scopeNodeId;
    if (isLocked) json['isLocked'] = true;
    if (_aliasVariableId != null) json['aliasVariableId'] = _aliasVariableId;
    return json;
  }

  /// Resilient deserialization — silently skips malformed entries.
  factory DesignVariable.fromJson(Map<String, dynamic> json) {
    DesignVariableType type;
    try {
      type = DesignVariableType.values.firstWhere(
        (t) => t.name == json['type'],
      );
    } catch (_) {
      type = DesignVariableType.string; // safe fallback
    }

    final rawValues = json['values'] as Map<String, dynamic>? ?? {};

    // Coerce numeric values to double for number type, skip invalid entries.
    final values = <String, dynamic>{};
    for (final entry in rawValues.entries) {
      try {
        if (type == DesignVariableType.number && entry.value is num) {
          values[entry.key] = (entry.value as num).toDouble();
        } else {
          values[entry.key] = entry.value;
        }
      } catch (_) {
        // Skip malformed value — resilient loading.
      }
    }

    VariableConstraints? constraints;
    if (json['constraints'] is Map<String, dynamic>) {
      try {
        constraints = VariableConstraints.fromJson(
          json['constraints'] as Map<String, dynamic>,
        );
      } catch (_) {
        // Resilient — skip malformed constraints.
      }
    }

    return DesignVariable(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      type: type,
      description: json['description'] as String?,
      group: json['group'] as String?,
      constraints: constraints,
      scopeNodeId: json['scopeNodeId'] as String?,
      isLocked: json['isLocked'] as bool? ?? false,
      aliasVariableId: json['aliasVariableId'] as String?,
      values: values,
    );
  }

  @override
  String toString() =>
      'DesignVariable(id: $id, name: "$_name", type: ${type.name})';
}

// ---------------------------------------------------------------------------
// Variable Collection
// ---------------------------------------------------------------------------

/// A named collection of variables sharing the same set of modes.
///
/// Modeled after Figma's variable collections: each collection defines
/// a set of modes (e.g. "Light" / "Dark") and a set of variables whose
/// values are keyed by those modes.
///
/// ```dart
/// final themes = VariableCollection(
///   id: 'themes',
///   name: 'Color Themes',
///   modes: [
///     VariableMode(id: 'light', name: 'Light'),
///     VariableMode(id: 'dark',  name: 'Dark'),
///   ],
/// );
/// themes.addVariable(myColorVariable);
/// ```
///
/// DESIGN PRINCIPLES:
/// - At least one mode must exist (the default mode)
/// - Variables within a collection share all modes
/// - Default mode is the first mode in the list
/// - O(1) lookups via internal indexed maps
/// - Observable via [ChangeNotifier] for reactive UI
class VariableCollection extends ChangeNotifier {
  /// Unique identifier.
  final String id;

  /// Human-readable display name.
  String name;

  /// Modes available in this collection.
  final List<VariableMode> _modes;

  /// Variables in this collection.
  final List<DesignVariable> _variables;

  /// O(1) lookup indexes.
  final Map<String, VariableMode> _modeIndex = {};
  final Map<String, DesignVariable> _variableIndex = {};

  /// The default mode ID (first mode).
  String get defaultModeId => _modes.first.id;

  /// Read-only access to modes.
  List<VariableMode> get modes => List.unmodifiable(_modes);

  /// Read-only access to variables.
  List<DesignVariable> get variables => List.unmodifiable(_variables);

  /// Number of modes.
  int get modeCount => _modes.length;

  /// Number of variables.
  int get variableCount => _variables.length;

  /// All mode IDs as a set (useful for validation).
  Set<String> get modeIds => _modeIndex.keys.toSet();

  VariableCollection({
    required this.id,
    required this.name,
    List<VariableMode>? modes,
    List<DesignVariable>? variables,
  }) : _modes = modes != null ? List.from(modes) : [],
       _variables = variables != null ? List.from(variables) : [] {
    // Ensure at least one mode exists.
    if (_modes.isEmpty) {
      _modes.add(VariableMode(id: 'default', name: 'Default'));
    }
    // Build indexes.
    _rebuildIndexes();
  }

  void _rebuildIndexes() {
    _modeIndex
      ..clear()
      ..addEntries(_modes.map((m) => MapEntry(m.id, m)));
    _variableIndex
      ..clear()
      ..addEntries(_variables.map((v) => MapEntry(v.id, v)));
  }

  // ---- Mode CRUD ----

  /// Add a new mode.
  void addMode(VariableMode mode) {
    if (_modeIndex.containsKey(mode.id)) return; // skip duplicates
    _modes.add(mode);
    _modeIndex[mode.id] = mode;
    notifyListeners();
  }

  /// Remove a mode by ID.
  ///
  /// Cannot remove the last mode — at least one must remain.
  /// Also removes all variable values for this mode.
  /// Returns `true` if actually removed, `false` otherwise.
  bool removeMode(String modeId) {
    if (_modes.length <= 1) return false;
    final idx = _modes.indexWhere((m) => m.id == modeId);
    if (idx < 0) return false;
    _modes.removeAt(idx);
    _modeIndex.remove(modeId);
    // Clean up variable values for this mode.
    for (final v in _variables) {
      v.removeValue(modeId);
    }
    notifyListeners();
    return true;
  }

  /// Find a mode by ID. O(1) lookup.
  VariableMode? findMode(String modeId) => _modeIndex[modeId];

  // ---- Variable CRUD ----

  /// Add a variable to this collection.
  ///
  /// Validates that variable value mode IDs are a subset of collection modes.
  /// Values for unknown modes are silently stripped.
  /// Subscribes to the variable's change events for automatic propagation.
  void addVariable(DesignVariable variable) {
    if (_variableIndex.containsKey(variable.id)) return;
    // Strip values for modes that don't exist in this collection.
    _validateVariableModes(variable);
    _variables.add(variable);
    _variableIndex[variable.id] = variable;
    // Subscribe to child changes for automatic propagation.
    variable.addListener(_onChildVariableChanged);
    notifyListeners();
  }

  /// Remove a variable by ID.
  bool removeVariable(String variableId) {
    final idx = _variables.indexWhere((v) => v.id == variableId);
    if (idx < 0) return false;
    final variable = _variables.removeAt(idx);
    variable.removeListener(_onChildVariableChanged);
    _variableIndex.remove(variableId);
    notifyListeners();
    return true;
  }

  /// Handler for child variable change events.
  ///
  /// Automatically propagates DesignVariable mutations to collection-level
  /// ChangeNotifier listeners, enabling reactive UI updates.
  void _onChildVariableChanged(VariableChangeEvent event) {
    notifyListeners();
  }

  /// Find a variable by ID. O(1) lookup.
  DesignVariable? findVariable(String variableId) => _variableIndex[variableId];

  /// Strip values from [variable] whose mode IDs don't exist in this collection.
  void _validateVariableModes(DesignVariable variable) {
    final invalidModes =
        variable.values.keys
            .where((modeId) => !_modeIndex.containsKey(modeId))
            .toList();
    for (final modeId in invalidModes) {
      variable.removeValue(modeId);
    }
  }

  /// Validate all variables, stripping values for non-existent modes.
  ///
  /// Returns the number of values stripped.
  int validateAndClean() {
    int stripped = 0;
    for (final v in _variables) {
      final invalidModes =
          v.values.keys
              .where((modeId) => !_modeIndex.containsKey(modeId))
              .toList();
      for (final modeId in invalidModes) {
        v.removeValue(modeId);
        stripped++;
      }
    }
    return stripped;
  }

  // ---- Bulk resolution ----

  /// Resolve all variables for a given mode ID.
  ///
  /// Returns a map of `variableId → resolved value`. Alias variables
  /// are followed up to [maxAliasDepth] levels deep to prevent cycles.
  Map<String, dynamic> resolveAll(String modeId, {int maxAliasDepth = 8}) {
    final result = <String, dynamic>{};
    for (final v in _variables) {
      result[v.id] = _resolveWithAlias(v, modeId, maxAliasDepth, <String>{});
    }
    return result;
  }

  /// Resolve a single variable by ID, following alias chains.
  dynamic resolveVariable(
    String variableId,
    String modeId, {
    int maxAliasDepth = 8,
  }) {
    final variable = _variableIndex[variableId];
    if (variable == null) return null;
    return _resolveWithAlias(variable, modeId, maxAliasDepth, <String>{});
  }

  /// Resolve a single variable, following alias chains with cycle detection.
  dynamic _resolveWithAlias(
    DesignVariable variable,
    String modeId,
    int remainingDepth,
    Set<String> visited,
  ) {
    if (remainingDepth <= 0 || visited.contains(variable.id)) {
      return variable.resolve(modeId); // break cycles gracefully
    }
    if (!variable.isAlias) {
      return _resolveWithInheritance(variable, modeId);
    }
    visited.add(variable.id);
    final target = _variableIndex[variable.aliasVariableId];
    if (target == null) return _resolveWithInheritance(variable, modeId);
    return _resolveWithAlias(target, modeId, remainingDepth - 1, visited);
  }

  /// Resolve a variable walking up the mode inheritance chain.
  ///
  /// If the variable has no value for [modeId], walks up via
  /// [VariableMode.inheritsFrom] before falling back to the first value.
  dynamic _resolveWithInheritance(DesignVariable variable, String modeId) {
    // Try the requested mode first.
    if (variable.hasValueForMode(modeId)) {
      return variable.getValue(modeId);
    }
    // Walk up the inheritance chain.
    final chain = modeInheritanceChain(modeId);
    for (var i = 1; i < chain.length; i++) {
      if (variable.hasValueForMode(chain[i])) {
        return variable.getValue(chain[i]);
      }
    }
    // Final fallback: first available value.
    return variable.resolve(modeId);
  }

  // ---- Grouping ----

  /// Group variables by their [DesignVariable.group] path.
  ///
  /// Returns a map where keys are group paths (empty string for ungrouped)
  /// and values are lists of variables in that group.
  Map<String, List<DesignVariable>> variablesByGroup() {
    final groups = <String, List<DesignVariable>>{};
    for (final v in _variables) {
      final key = v.group ?? '';
      (groups[key] ??= []).add(v);
    }
    return groups;
  }

  // ---- Search & Filter ----

  /// Search variables by name (case-insensitive substring match).
  List<DesignVariable> searchVariables(String query) {
    if (query.isEmpty) return List.unmodifiable(_variables);
    final lower = query.toLowerCase();
    return _variables
        .where((v) => v.name.toLowerCase().contains(lower))
        .toList();
  }

  /// Filter variables by type.
  List<DesignVariable> filterByType(DesignVariableType type) =>
      _variables.where((v) => v.type == type).toList();

  /// Filter variables by group path (exact match).
  List<DesignVariable> filterByGroup(String group) =>
      _variables.where((v) => v.group == group).toList();

  /// Filter variables matching a predicate.
  List<DesignVariable> filterWhere(bool Function(DesignVariable v) test) =>
      _variables.where(test).toList();

  /// Search with multiple criteria at once.
  ///
  /// All non-null criteria must match (AND logic).
  List<DesignVariable> advancedSearch({
    String? nameQuery,
    DesignVariableType? type,
    String? group,
    bool? isAlias,
    bool? hasConstraints,
  }) {
    return _variables.where((v) {
      if (nameQuery != null &&
          !v.name.toLowerCase().contains(nameQuery.toLowerCase())) {
        return false;
      }
      if (type != null && v.type != type) return false;
      if (group != null && v.group != group) return false;
      if (isAlias != null && v.isAlias != isAlias) return false;
      if (hasConstraints != null && (v.constraints != null) != hasConstraints) {
        return false;
      }
      return true;
    }).toList();
  }

  // ---- Mode Completeness ----

  /// Returns variable IDs that are missing a value for the given [modeId].
  ///
  /// Useful for validation UI — highlights variables the designer needs
  /// to fill in before a mode is considered "complete".
  List<String> incompleteVariables(String modeId) {
    final incomplete = <String>[];
    for (final v in _variables) {
      if (v.isAlias) continue; // aliases don't need own values
      if (!v.hasValueForMode(modeId)) {
        incomplete.add(v.id);
      }
    }
    return incomplete;
  }

  /// Returns the inheritance chain for a mode (self → parent → grandparent…).
  ///
  /// Stops at max depth 8 or on cycle detection.
  List<String> modeInheritanceChain(String modeId, {int maxDepth = 8}) {
    final chain = <String>[];
    final visited = <String>{};
    var currentId = modeId;
    for (var i = 0; i < maxDepth; i++) {
      if (visited.contains(currentId)) break; // cycle
      visited.add(currentId);
      chain.add(currentId);
      final mode = _modeIndex[currentId];
      if (mode?.inheritsFrom == null) break;
      currentId = mode!.inheritsFrom!;
    }
    return chain;
  }

  // ---- Alias Validation ----

  /// Returns variable IDs whose alias target is not in this collection.
  ///
  /// Useful for validation UI — highlights broken references that should
  /// be fixed before publishing.
  ///
  /// ```dart
  /// final broken = collection.brokenAliases();
  /// // [{'variableId': 'my-alias', 'missingTarget': 'deleted-var'}]
  /// ```
  List<Map<String, String>> brokenAliases() {
    final broken = <Map<String, String>>[];
    for (final v in _variables) {
      if (!v.isAlias) continue;
      if (_variableIndex[v.aliasVariableId] == null) {
        broken.add({'variableId': v.id, 'missingTarget': v.aliasVariableId!});
      }
    }
    return broken;
  }

  // ---- Serialization ----

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'modes': _modes.map((m) => m.toJson()).toList(),
    'variables': _variables.map((v) => v.toJson()).toList(),
  };

  /// Resilient deserialization — gracefully handles malformed data.
  factory VariableCollection.fromJson(Map<String, dynamic> json) {
    List<VariableMode> modes;
    try {
      modes =
          (json['modes'] as List<dynamic>? ?? [])
              .map((m) => VariableMode.fromJson(m as Map<String, dynamic>))
              .toList();
    } catch (_) {
      modes = [];
    }

    List<DesignVariable> variables;
    try {
      variables =
          (json['variables'] as List<dynamic>? ?? [])
              .map((v) => DesignVariable.fromJson(v as Map<String, dynamic>))
              .toList();
    } catch (_) {
      variables = [];
    }

    return VariableCollection(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      modes: modes.isNotEmpty ? modes : null,
      variables: variables,
    );
  }

  @override
  String toString() =>
      'VariableCollection(id: $id, name: "$name", '
      'modes: ${_modes.length}, variables: ${_variables.length})';
}
