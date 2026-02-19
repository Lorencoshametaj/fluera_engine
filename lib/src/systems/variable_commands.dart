// =============================================================================
// ⏪ VARIABLE COMMANDS (UNDO/REDO)
//
// Command subclasses for all variable system mutations, integrating with
// the existing undo/redo system via the Command base class.
// =============================================================================

import '../history/command_history.dart';
import './design_variables.dart';
import './variable_binding.dart';
import './variable_resolver.dart';

// ---------------------------------------------------------------------------
// Value Commands
// ---------------------------------------------------------------------------

/// Undo/redo a `setValue()` call on a [DesignVariable].
class SetVariableValueCommand extends Command {
  final DesignVariable variable;
  final String modeId;
  final dynamic newValue;
  final dynamic _oldValue;

  SetVariableValueCommand({
    required this.variable,
    required this.modeId,
    required this.newValue,
  }) : _oldValue = variable.getValue(modeId),
       super(label: 'Set ${variable.name}');

  @override
  void execute() => variable.setValue(modeId, newValue);

  @override
  void undo() {
    if (_oldValue == null) {
      variable.removeValue(modeId);
    } else {
      variable.setValue(modeId, _oldValue);
    }
  }
}

// ---------------------------------------------------------------------------
// Mode Commands
// ---------------------------------------------------------------------------

/// Undo/redo switching the active mode on a [VariableResolver].
class SetActiveModeCommand extends Command {
  final VariableResolver resolver;
  final String collectionId;
  final String newModeId;
  final String? _oldModeId;

  SetActiveModeCommand({
    required this.resolver,
    required this.collectionId,
    required this.newModeId,
  }) : _oldModeId = resolver.getActiveMode(collectionId),
       super(label: 'Switch mode → $newModeId');

  @override
  void execute() => resolver.setActiveMode(collectionId, newModeId);

  @override
  void undo() {
    if (_oldModeId != null) {
      resolver.setActiveMode(collectionId, _oldModeId);
    }
  }
}

// ---------------------------------------------------------------------------
// Variable CRUD Commands
// ---------------------------------------------------------------------------

/// Undo/redo adding a variable to a collection.
class AddVariableCommand extends Command {
  final VariableCollection collection;
  final DesignVariable variable;

  AddVariableCommand({required this.collection, required this.variable})
    : super(label: 'Add variable "${variable.name}"');

  @override
  void execute() => collection.addVariable(variable);

  @override
  void undo() => collection.removeVariable(variable.id);
}

/// Undo/redo removing a variable from a collection.
///
/// On undo, restores the variable and re-adds all its bindings.
class RemoveVariableCommand extends Command {
  final VariableCollection collection;
  final DesignVariable variable;
  final VariableBindingRegistry? bindingRegistry;
  late final List<VariableBinding> _removedBindings;

  RemoveVariableCommand({
    required this.collection,
    required this.variable,
    this.bindingRegistry,
  }) : super(label: 'Remove variable "${variable.name}"') {
    _removedBindings =
        bindingRegistry != null
            ? List.from(bindingRegistry!.bindingsForVariable(variable.id))
            : [];
  }

  @override
  void execute() {
    bindingRegistry?.removeBindingsForVariable(variable.id);
    collection.removeVariable(variable.id);
  }

  @override
  void undo() {
    collection.addVariable(variable);
    if (bindingRegistry != null) {
      for (final b in _removedBindings) {
        bindingRegistry!.addBinding(b);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Binding Commands
// ---------------------------------------------------------------------------

/// Undo/redo adding a variable binding.
class AddBindingCommand extends Command {
  final VariableBindingRegistry registry;
  final VariableBinding binding;

  AddBindingCommand({required this.registry, required this.binding})
    : super(label: 'Bind ${binding.variableId} → ${binding.nodeId}');

  @override
  void execute() => registry.addBinding(binding);

  @override
  void undo() => registry.removeBinding(binding);
}

/// Undo/redo removing a variable binding.
class RemoveBindingCommand extends Command {
  final VariableBindingRegistry registry;
  final VariableBinding binding;

  RemoveBindingCommand({required this.registry, required this.binding})
    : super(label: 'Unbind ${binding.variableId} → ${binding.nodeId}');

  @override
  void execute() => registry.removeBinding(binding);

  @override
  void undo() => registry.addBinding(binding);
}

// ---------------------------------------------------------------------------
// Rename Command
// ---------------------------------------------------------------------------

/// Undo/redo renaming a variable ID.
///
/// Atomically updates the variable in the collection and all bindings
/// that reference it. The old variable is removed and a new copy with
/// the updated ID is added.
class RenameVariableCommand extends Command {
  final VariableCollection collection;
  final VariableBindingRegistry bindingRegistry;
  final String oldId;
  final String newId;

  RenameVariableCommand({
    required this.collection,
    required this.bindingRegistry,
    required this.oldId,
    required this.newId,
  }) : super(label: 'Rename variable $oldId → $newId');

  @override
  void execute() => _rename(oldId, newId);

  @override
  void undo() => _rename(newId, oldId);

  void _rename(String from, String to) {
    bindingRegistry.renameVariable(from, to);
    final variable = collection.findVariable(from);
    if (variable == null) return;
    final renamed = variable.copyWith(id: to);
    collection.removeVariable(from);
    collection.addVariable(renamed);
  }
}
