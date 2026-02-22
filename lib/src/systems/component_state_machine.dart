/// 🎯 COMPONENT STATE MACHINE — Interactive states for symbol instances.
///
/// Maps interactive states (hover, pressed, focused, disabled) to variant
/// selections in a [SymbolDefinition]'s variant matrix.
///
/// ```dart
/// final machine = ComponentStateMachine();
/// machine.registerStates('btn-def-id', {
///   InteractiveState.hover: {'state': 'hover'},
///   InteractiveState.pressed: {'state': 'pressed'},
///   InteractiveState.disabled: {'state': 'disabled'},
/// });
/// final selections = machine.resolveState('btn-def-id', InteractiveState.hover);
/// ```
library;

// =============================================================================
// INTERACTIVE STATE
// =============================================================================

/// Interactive states for UI components.
enum InteractiveState {
  /// Default/idle state.
  defaultState,

  /// Mouse/pointer hover state.
  hover,

  /// Active press/tap state.
  pressed,

  /// Keyboard/accessibility focus state.
  focused,

  /// Inactive/non-interactive state.
  disabled,
}

// =============================================================================
// COMPONENT STATE CONFIG
// =============================================================================

/// Maps interactive states to variant property selections for one component.
class ComponentStateConfig {
  /// The symbol definition ID this config applies to.
  final String definitionId;

  /// State → variant selections mapping.
  /// Each entry maps an [InteractiveState] to the [VariantProperty] selections
  /// that should be active in that state.
  final Map<InteractiveState, Map<String, String>> stateSelections;

  const ComponentStateConfig({
    required this.definitionId,
    this.stateSelections = const {},
  });

  ComponentStateConfig copyWith({
    Map<InteractiveState, Map<String, String>>? stateSelections,
  }) => ComponentStateConfig(
    definitionId: definitionId,
    stateSelections: stateSelections ?? this.stateSelections,
  );

  Map<String, dynamic> toJson() => {
    'definitionId': definitionId,
    'stateSelections': stateSelections.map(
      (state, selections) => MapEntry(state.name, selections),
    ),
  };

  factory ComponentStateConfig.fromJson(Map<String, dynamic> json) {
    final selectionsRaw =
        json['stateSelections'] as Map<String, dynamic>? ?? {};
    final stateSelections = <InteractiveState, Map<String, String>>{};
    for (final entry in selectionsRaw.entries) {
      final state = InteractiveState.values.byName(entry.key);
      final selections = Map<String, String>.from(
        entry.value as Map<String, dynamic>,
      );
      stateSelections[state] = selections;
    }
    return ComponentStateConfig(
      definitionId: json['definitionId'] as String,
      stateSelections: stateSelections,
    );
  }
}

// =============================================================================
// COMPONENT STATE MACHINE
// =============================================================================

/// Manages interactive state configurations for component definitions.
class ComponentStateMachine {
  ComponentStateMachine();
  final Map<String, ComponentStateConfig> _configs = {};

  /// All registered configs (unmodifiable).
  Map<String, ComponentStateConfig> get configs => Map.unmodifiable(_configs);

  /// Register state mappings for a component definition.
  void registerStates(
    String definitionId,
    Map<InteractiveState, Map<String, String>> stateSelections,
  ) {
    _configs[definitionId] = ComponentStateConfig(
      definitionId: definitionId,
      stateSelections: stateSelections,
    );
  }

  /// Remove state configuration.
  bool unregister(String definitionId) => _configs.remove(definitionId) != null;

  /// Check if a definition has state configs.
  bool hasStates(String definitionId) => _configs.containsKey(definitionId);

  /// Get the config for a definition.
  ComponentStateConfig? configFor(String definitionId) =>
      _configs[definitionId];

  /// Resolve variant selections for a given interactive state.
  ///
  /// Returns the variant selections for the state, or empty map
  /// if no mapping exists.
  Map<String, String> resolveState(
    String definitionId,
    InteractiveState state,
  ) {
    final config = _configs[definitionId];
    if (config == null) return {};
    return config.stateSelections[state] ?? {};
  }

  /// Get all states that have mappings for a definition.
  Set<InteractiveState> availableStates(String definitionId) {
    final config = _configs[definitionId];
    if (config == null) return {};
    return config.stateSelections.keys.toSet();
  }

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'configs': _configs.values.map((c) => c.toJson()).toList(),
  };

  factory ComponentStateMachine.fromJson(Map<String, dynamic> json) {
    final machine = ComponentStateMachine();
    final configsList = json['configs'] as List<dynamic>? ?? [];
    for (final raw in configsList) {
      final config = ComponentStateConfig.fromJson(raw as Map<String, dynamic>);
      machine._configs[config.definitionId] = config;
    }
    return machine;
  }
}
