/// 🔍 COMPONENT STATE RESOLVER — Resolves instance content for interactive states.
///
/// Combines instance overrides with state-based variant selections,
/// using override cascading: instance overrides > state defaults > base.
///
/// ```dart
/// final resolver = ComponentStateResolver(stateMachine: myMachine);
/// final content = resolver.resolveContent(
///   definition, instance, InteractiveState.hover,
/// );
/// ```
library;

import '../core/nodes/group_node.dart';
import '../core/nodes/symbol_system.dart';
import 'component_state_machine.dart';

/// Resolves component instance content for a given interactive state.
class ComponentStateResolver {
  final ComponentStateMachine stateMachine;

  const ComponentStateResolver({required this.stateMachine});

  /// Resolve the effective variant selections for an instance in a state.
  ///
  /// Priority: instance overrides > state selections > base defaults.
  Map<String, String> resolveSelections(
    SymbolDefinition definition,
    SymbolInstanceNode instance,
    InteractiveState state,
  ) {
    // Start with base defaults from the definition.
    final effective = <String, String>{};
    for (final prop in definition.variantProperties) {
      effective[prop.name] = prop.defaultValue;
    }

    // Apply state-level selections (mid priority).
    final stateSelections = stateMachine.resolveState(definition.id, state);
    effective.addAll(stateSelections);

    // Apply instance-level overrides (highest priority).
    effective.addAll(instance.variantSelections);

    return effective;
  }

  /// Resolve the GroupNode content for an instance in a specific state.
  ///
  /// Uses override cascading:
  /// 1. Instance overrides (highest priority — user customization)
  /// 2. State selections (interactive state variant)
  /// 3. Definition defaults (base component)
  GroupNode resolveContent(
    SymbolDefinition definition,
    SymbolInstanceNode instance,
    InteractiveState state,
  ) {
    final selections = resolveSelections(definition, instance, state);
    return definition.resolveContent(selections);
  }

  /// Check if a definition has any interactive state mappings.
  bool hasInteractiveStates(String definitionId) =>
      stateMachine.hasStates(definitionId);

  /// Get all available states for a definition.
  Set<InteractiveState> availableStates(String definitionId) =>
      stateMachine.availableStates(definitionId);

  /// Preview all state variants for an instance.
  ///
  /// Returns a map of state → resolved GroupNode content.
  Map<InteractiveState, GroupNode> previewAllStates(
    SymbolDefinition definition,
    SymbolInstanceNode instance,
  ) {
    final states = stateMachine.availableStates(definition.id);
    return {
      for (final state in states)
        state: resolveContent(definition, instance, state),
    };
  }
}
