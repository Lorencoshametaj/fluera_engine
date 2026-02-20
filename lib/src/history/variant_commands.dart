// =============================================================================
// ⏪ VARIANT COMMANDS (UNDO/REDO)
//
// Command subclasses for all variant property system mutations, integrating
// with the existing undo/redo system via the Command base class.
//
// Enterprise patterns:
//   • modifiedAt snapshot/restore on every definition-mutating command
//   • Merge coalescing for live-editing commands (rename axis/option, overrides)
//   • Validation guards with fail-fast error messages
//   • Cascading side-effects (orphaned variants, default values)
// =============================================================================

import '../core/nodes/group_node.dart';
import '../core/nodes/symbol_system.dart';
import '../core/nodes/variant_property.dart';
import 'command_history.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Lookup a [VariantProperty] by ID or throw a clear [StateError].
VariantProperty _findProperty(SymbolDefinition def, String propertyId) {
  final idx = def.variantProperties.indexWhere((p) => p.id == propertyId);
  if (idx == -1) {
    throw StateError(
      'VariantProperty "$propertyId" not found on definition "${def.id}"',
    );
  }
  return def.variantProperties[idx];
}

// ---------------------------------------------------------------------------
// Property CRUD Commands
// ---------------------------------------------------------------------------

/// Undo/redo adding a variant property axis to a [SymbolDefinition].
class AddVariantPropertyCommand extends Command {
  final SymbolDefinition definition;
  final VariantProperty property;
  late final DateTime _oldModifiedAt;

  AddVariantPropertyCommand({required this.definition, required this.property})
    : super(label: 'Add variant property "${property.name}"') {
    _oldModifiedAt = definition.modifiedAt;
  }

  @override
  void execute() => definition.addVariantProperty(property);

  @override
  void undo() {
    definition.removeVariantProperty(property.id);
    definition.modifiedAt = _oldModifiedAt;
  }
}

/// Undo/redo removing a variant property axis from a [SymbolDefinition].
///
/// Snapshots the property and all variant content referencing it for
/// reliable undo — the matrix entries need to be restored exactly.
class RemoveVariantPropertyCommand extends Command {
  final SymbolDefinition definition;
  final String propertyId;

  late final VariantProperty _removedProperty;
  late final Map<String, VariantContent> _removedVariants;
  late final DateTime _oldModifiedAt;

  RemoveVariantPropertyCommand({
    required this.definition,
    required this.propertyId,
  }) : super(label: 'Remove variant property') {
    _oldModifiedAt = definition.modifiedAt;

    // Snapshot before execute.
    _removedProperty = _findProperty(definition, propertyId).copyWith();

    // Snapshot variant entries referencing this property.
    _removedVariants = Map.fromEntries(
      definition.variants.entries.where(
        (e) => e.value.propertyValues.containsKey(_removedProperty.name),
      ),
    );
  }

  @override
  void execute() => definition.removeVariantProperty(propertyId);

  @override
  void undo() {
    definition.addVariantProperty(_removedProperty);
    for (final entry in _removedVariants.entries) {
      definition.variants[entry.key] = entry.value;
    }
    definition.modifiedAt = _oldModifiedAt;
  }
}

/// Undo/redo renaming a variant property axis.
///
/// Captures old name so the full key rebuild can be reversed.
/// Supports merge coalescing for character-by-character inline editing.
class RenameVariantAxisCommand extends Command {
  final SymbolDefinition definition;
  final String propertyId;
  String newName;
  late final String _oldName;
  late final DateTime _oldModifiedAt;

  RenameVariantAxisCommand({
    required this.definition,
    required this.propertyId,
    required this.newName,
  }) : super(label: '') {
    _oldModifiedAt = definition.modifiedAt;
    _oldName = _findProperty(definition, propertyId).name;
  }

  /// Dynamic label reflecting current [newName] after merge coalescing.
  @override
  String get label => 'Rename axis → "$newName"';

  @override
  void execute() => definition.renameVariantPropertyAxis(propertyId, newName);

  @override
  void undo() {
    definition.renameVariantPropertyAxis(propertyId, _oldName);
    definition.modifiedAt = _oldModifiedAt;
  }

  @override
  bool canMergeWith(Command other) =>
      other is RenameVariantAxisCommand &&
      other.definition == definition &&
      other.propertyId == propertyId;

  @override
  void mergeWith(Command other) {
    if (other is RenameVariantAxisCommand) {
      newName = other.newName;
    }
  }
}

/// Undo/redo renaming a variant option value.
///
/// Supports merge coalescing for character-by-character inline editing.
class RenameVariantOptionCommand extends Command {
  final SymbolDefinition definition;
  final String propertyId;
  final String oldValue;
  String newValue;
  late final DateTime _oldModifiedAt;

  RenameVariantOptionCommand({
    required this.definition,
    required this.propertyId,
    required this.oldValue,
    required this.newValue,
  }) : super(label: '') {
    _oldModifiedAt = definition.modifiedAt;
    // Validate property exists.
    _findProperty(definition, propertyId);
  }

  /// Dynamic label reflecting current [newValue] after merge coalescing.
  @override
  String get label => 'Rename option "$oldValue" → "$newValue"';

  @override
  void execute() =>
      definition.renameVariantOption(propertyId, oldValue, newValue);

  @override
  void undo() {
    definition.renameVariantOption(propertyId, newValue, oldValue);
    definition.modifiedAt = _oldModifiedAt;
  }

  @override
  bool canMergeWith(Command other) =>
      other is RenameVariantOptionCommand &&
      other.definition == definition &&
      other.propertyId == propertyId &&
      other.oldValue == newValue; // chain: A→B then B→C

  @override
  void mergeWith(Command other) {
    if (other is RenameVariantOptionCommand) {
      newValue = other.newValue;
    }
  }
}

/// Undo/redo reordering a variant property axis.
class ReorderVariantPropertyCommand extends Command {
  final SymbolDefinition definition;
  final String propertyId;
  final int newIndex;
  late final int _oldIndex;
  late final DateTime _oldModifiedAt;

  ReorderVariantPropertyCommand({
    required this.definition,
    required this.propertyId,
    required this.newIndex,
  }) : super(label: 'Reorder variant property') {
    _oldModifiedAt = definition.modifiedAt;
    _oldIndex = definition.variantProperties.indexWhere(
      (p) => p.id == propertyId,
    );
    if (_oldIndex == -1) {
      throw StateError(
        'VariantProperty "$propertyId" not found on definition "${definition.id}"',
      );
    }
  }

  @override
  void execute() => definition.reorderVariantProperty(propertyId, newIndex);

  @override
  void undo() {
    definition.reorderVariantProperty(propertyId, _oldIndex);
    definition.modifiedAt = _oldModifiedAt;
  }
}

// ---------------------------------------------------------------------------
// Option CRUD Commands
// ---------------------------------------------------------------------------

/// Undo/redo adding an option to a [VariantProperty].
///
/// Validates that the option does not already exist (fail-fast).
class AddVariantOptionCommand extends Command {
  final SymbolDefinition definition;
  final String propertyId;
  final String value;
  late final DateTime _oldModifiedAt;

  AddVariantOptionCommand({
    required this.definition,
    required this.propertyId,
    required this.value,
  }) : super(label: 'Add option "$value"') {
    _oldModifiedAt = definition.modifiedAt;
    final prop = _findProperty(definition, propertyId);
    if (prop.options.contains(value)) {
      throw ArgumentError.value(
        value,
        'value',
        'Option "$value" already exists on property "${prop.name}"',
      );
    }
  }

  @override
  void execute() {
    final prop = _findProperty(definition, propertyId);
    prop.addOption(value);
  }

  @override
  void undo() {
    final prop = _findProperty(definition, propertyId);
    prop.removeOption(value);
    definition.modifiedAt = _oldModifiedAt;
  }
}

/// Undo/redo removing an option from a [VariantProperty].
///
/// Cascades: removes orphaned variant content entries that reference
/// the deleted option, and handles default value invalidation.
class RemoveVariantOptionCommand extends Command {
  final SymbolDefinition definition;
  final String propertyId;
  final String value;

  late final int _oldIndex;
  late final String _oldDefaultValue;
  late final String _propName;
  late final Map<String, VariantContent> _orphanedVariants;
  late final DateTime _oldModifiedAt;

  RemoveVariantOptionCommand({
    required this.definition,
    required this.propertyId,
    required this.value,
  }) : super(label: 'Remove option "$value"') {
    _oldModifiedAt = definition.modifiedAt;
    final prop = _findProperty(definition, propertyId);
    _oldIndex = prop.options.indexOf(value);
    _oldDefaultValue = prop.defaultValue;
    _propName = prop.name;

    // Snapshot orphaned variant entries referencing this option.
    _orphanedVariants = Map.fromEntries(
      definition.variants.entries.where(
        (e) => e.value.propertyValues[_propName] == value,
      ),
    );
  }

  @override
  void execute() {
    final prop = _findProperty(definition, propertyId);
    prop.removeOption(value);

    // Cascade: remove orphaned variant content entries.
    for (final key in _orphanedVariants.keys) {
      definition.variants.remove(key);
    }
  }

  @override
  void undo() {
    final prop = _findProperty(definition, propertyId);
    // Restore option at original position.
    final mutable = List<String>.of(prop.options);
    mutable.insert(_oldIndex.clamp(0, mutable.length), value);
    prop.options = mutable;

    // Restore default value if it was invalidated.
    prop.defaultValue = _oldDefaultValue;

    // Restore orphaned variant entries.
    for (final entry in _orphanedVariants.entries) {
      definition.variants[entry.key] = entry.value;
    }
    definition.modifiedAt = _oldModifiedAt;
  }
}

// ---------------------------------------------------------------------------
// Variant Content Commands
// ---------------------------------------------------------------------------

/// Undo/redo setting variant content for a given combination.
///
/// If the combination already had content, stores it for undo.
class SetVariantContentCommand extends Command {
  final SymbolDefinition definition;
  final Map<String, String> propertyValues;
  final GroupNode content;

  VariantContent? _oldContent;
  late final DateTime _oldModifiedAt;

  SetVariantContentCommand({
    required this.definition,
    required this.propertyValues,
    required this.content,
  }) : super(label: 'Set variant content') {
    _oldModifiedAt = definition.modifiedAt;
    final key = VariantContent.buildVariantKey(propertyValues);
    _oldContent = definition.variants[key];
  }

  @override
  void execute() => definition.setVariant(propertyValues, content);

  @override
  void undo() {
    final key = VariantContent.buildVariantKey(propertyValues);
    if (_oldContent != null) {
      definition.variants[key] = _oldContent!;
    } else {
      definition.variants.remove(key);
    }
    definition.modifiedAt = _oldModifiedAt;
  }
}

/// Undo/redo removing variant content for a given key.
class RemoveVariantContentCommand extends Command {
  final SymbolDefinition definition;
  final String variantKey;

  late final VariantContent _removedContent;

  RemoveVariantContentCommand({
    required this.definition,
    required this.variantKey,
  }) : super(label: 'Remove variant content') {
    _removedContent = definition.variants[variantKey]!;
  }

  @override
  void execute() => definition.variants.remove(variantKey);

  @override
  void undo() => definition.variants[variantKey] = _removedContent;
}

// ---------------------------------------------------------------------------
// Instance Commands
// ---------------------------------------------------------------------------

/// Undo/redo setting a variant selection on a [SymbolInstanceNode].
///
/// Supports merge coalescing for rapid selection changes (e.g. dropdown).
/// The [label] getter is dynamic so it stays accurate after merging.
class SetVariantSelectionCommand extends Command {
  final SymbolInstanceNode instance;
  final String propertyName;
  String newValue;
  final String? _oldValue;

  SetVariantSelectionCommand({
    required this.instance,
    required this.propertyName,
    required this.newValue,
  }) : _oldValue = instance.variantSelections[propertyName],
       super(label: '');

  /// Dynamic label that reflects the current [newValue] after merging.
  @override
  String get label => 'Set $propertyName → $newValue';

  @override
  void execute() => instance.variantSelections[propertyName] = newValue;

  @override
  void undo() {
    if (_oldValue != null) {
      instance.variantSelections[propertyName] = _oldValue;
    } else {
      instance.variantSelections.remove(propertyName);
    }
  }

  @override
  bool canMergeWith(Command other) =>
      other is SetVariantSelectionCommand &&
      other.instance.id == instance.id &&
      other.propertyName == propertyName;

  @override
  void mergeWith(Command other) {
    if (other is SetVariantSelectionCommand) {
      newValue = other.newValue;
    }
  }
}

/// Undo/redo setting an override on a [SymbolInstanceNode].
///
/// Supports merge coalescing for rapid value changes (e.g. color slider).
class SetInstanceOverrideCommand extends Command {
  final SymbolInstanceNode instance;
  final String key;
  dynamic newValue;
  final dynamic _oldValue;
  final bool _hadKey;

  SetInstanceOverrideCommand({
    required this.instance,
    required this.key,
    required this.newValue,
  }) : _oldValue = instance.overrides[key],
       _hadKey = instance.overrides.containsKey(key),
       super(label: '');

  /// Dynamic label reflecting current [newValue] after merge coalescing.
  @override
  String get label => 'Set override $key';

  @override
  void execute() => instance.overrides[key] = newValue;

  @override
  void undo() {
    if (_hadKey) {
      instance.overrides[key] = _oldValue;
    } else {
      instance.overrides.remove(key);
    }
  }

  @override
  bool canMergeWith(Command other) =>
      other is SetInstanceOverrideCommand &&
      other.instance.id == instance.id &&
      other.key == key;

  @override
  void mergeWith(Command other) {
    if (other is SetInstanceOverrideCommand) {
      newValue = other.newValue;
    }
  }
}

/// Undo/redo removing an override from a [SymbolInstanceNode].
///
/// Symmetric counterpart of [SetInstanceOverrideCommand].
class RemoveInstanceOverrideCommand extends Command {
  final SymbolInstanceNode instance;
  final String key;
  final dynamic _oldValue;

  RemoveInstanceOverrideCommand({required this.instance, required this.key})
    : _oldValue = instance.overrides[key],
      super(label: 'Remove override $key');

  @override
  void execute() => instance.overrides.remove(key);

  @override
  void undo() => instance.overrides[key] = _oldValue;
}

/// Undo/redo clearing all variant selections on a [SymbolInstanceNode].
///
/// Useful when detaching an instance from its definition or resetting
/// to defaults.
class ClearVariantSelectionsCommand extends Command {
  final SymbolInstanceNode instance;
  late final Map<String, String> _oldSelections;

  ClearVariantSelectionsCommand({required this.instance})
    : super(label: 'Clear variant selections') {
    _oldSelections = Map.of(instance.variantSelections);
  }

  @override
  void execute() => instance.variantSelections.clear();

  @override
  void undo() {
    instance.variantSelections.addAll(_oldSelections);
  }
}
