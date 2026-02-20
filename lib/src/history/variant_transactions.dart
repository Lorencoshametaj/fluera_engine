// =============================================================================
// ⏪ VARIANT TRANSACTIONS (BATCH OPERATIONS)
//
// Convenience factories that build CommandTransactions for complex multi-step
// variant operations. Each returns a CompositeCommand ready for
// CommandHistory.pushWithoutExecute() (commands are already executed by the
// transaction).
//
// Enterprise patterns:
//   • Try/catch auto-rollback on every recipe
//   • Instance propagation for cross-cutting operations
//   • Empty-transaction guards to avoid stack pollution
// =============================================================================

import '../core/nodes/group_node.dart';
import '../core/nodes/symbol_system.dart';
import '../core/nodes/variant_property.dart';
import 'command_history.dart';
import 'variant_commands.dart';

/// Pre-built batch transactions for common variant system operations.
///
/// Each factory method groups multiple [Command]s into a single atomic
/// undo entry via [CommandTransaction]. If any step throws, all previously
/// executed commands are automatically rolled back before rethrowing.
///
/// ```dart
/// final composite = VariantTransactions.renameAxis(
///   def: buttonDef,
///   propertyId: sizeProperty.id,
///   newName: 'Dimension',
/// );
/// history.pushWithoutExecute(composite); // already executed
/// ```
class VariantTransactions {
  VariantTransactions._(); // static-only

  // -------------------------------------------------------------------------
  // Rename axis (atomic)
  // -------------------------------------------------------------------------

  /// Rename a variant property axis across all matrix keys.
  ///
  /// Internally: snapshot old keys → rename property → rebuild all keys.
  /// All steps are a single undo entry.
  static CompositeCommand renameAxis({
    required SymbolDefinition def,
    required String propertyId,
    required String newName,
  }) {
    final txn = CommandTransaction(label: 'Rename axis → "$newName"');
    try {
      txn.add(
        RenameVariantAxisCommand(
          definition: def,
          propertyId: propertyId,
          newName: newName,
        ),
      );
      return txn.commit();
    } catch (e) {
      txn.rollback();
      rethrow;
    }
  }

  // -------------------------------------------------------------------------
  // Remove property (atomic)
  // -------------------------------------------------------------------------

  /// Remove a variant property axis and all its content entries.
  ///
  /// Single undo entry: restores the property and all removed variants.
  static CompositeCommand removeProperty({
    required SymbolDefinition def,
    required String propertyId,
  }) {
    final txn = CommandTransaction(label: 'Remove variant property');
    try {
      txn.add(
        RemoveVariantPropertyCommand(definition: def, propertyId: propertyId),
      );
      return txn.commit();
    } catch (e) {
      txn.rollback();
      rethrow;
    }
  }

  // -------------------------------------------------------------------------
  // Remove property with instance sanitization (atomic)
  // -------------------------------------------------------------------------

  /// Remove a variant property axis and clean all instance selections.
  ///
  /// Removes the property from the definition, then removes the stale
  /// selection entry from every instance's `variantSelections`. Single
  /// undo entry.
  static CompositeCommand removePropertyAcrossInstances({
    required SymbolDefinition def,
    required String propertyId,
    required List<SymbolInstanceNode> instances,
  }) {
    final prop = def.variantProperties.firstWhere(
      (p) => p.id == propertyId,
      orElse: () => throw StateError('Property $propertyId not found'),
    );
    final propName = prop.name;

    final txn = CommandTransaction(label: 'Remove property "${prop.name}"');
    try {
      // 1. Remove on definition (cascades variants).
      txn.add(
        RemoveVariantPropertyCommand(definition: def, propertyId: propertyId),
      );

      // 2. Clean instance selections referencing this axis.
      for (final inst in instances) {
        if (inst.variantSelections.containsKey(propName)) {
          txn.add(
            SetVariantSelectionCommand(
              instance: inst,
              propertyName: propName,
              newValue: '', // will be removed in next line's undo
            ),
          );
        }
      }

      return txn.commit();
    } catch (e) {
      txn.rollback();
      rethrow;
    }
  }

  // -------------------------------------------------------------------------
  // Duplicate definition (atomic)
  // -------------------------------------------------------------------------

  /// Duplicate a symbol definition with all its variants.
  ///
  /// Creates a deep copy with a new ID and name, registers it in the
  /// registry. Single undo entry removes the copy.
  static CompositeCommand duplicateDefinition({
    required SymbolDefinition source,
    required SymbolRegistry registry,
    String? newId,
    String? newName,
  }) {
    final copy = source.copyWith(id: newId, name: newName);
    final txn = CommandTransaction(label: 'Duplicate "${source.name}"');
    try {
      txn.add(_RegisterDefinitionCommand(registry: registry, definition: copy));
      return txn.commit();
    } catch (e) {
      txn.rollback();
      rethrow;
    }
  }

  // -------------------------------------------------------------------------
  // Fill missing variants (atomic)
  // -------------------------------------------------------------------------

  /// Fill all missing variant matrix entries with generated content.
  ///
  /// The [contentFactory] receives each missing property-value map and
  /// returns a [GroupNode] for that combination.
  ///
  /// Returns `null` if the matrix is already complete (avoids polluting
  /// the undo stack with empty composites).
  static CompositeCommand? fillMissingVariants({
    required SymbolDefinition def,
    required GroupNode Function(Map<String, String> propertyValues)
    contentFactory,
  }) {
    final missing = def.missingVariantKeys;
    if (missing.isEmpty) return null; // Nothing to fill.

    final txn = CommandTransaction(
      label: 'Fill ${missing.length} missing variants',
    );

    try {
      for (final key in missing) {
        // Parse key back into property values.
        final propertyValues = _parseVariantKey(key, def);
        final content = contentFactory(propertyValues);
        txn.add(
          SetVariantContentCommand(
            definition: def,
            propertyValues: propertyValues,
            content: content,
          ),
        );
      }

      return txn.commit();
    } catch (e) {
      txn.rollback();
      rethrow;
    }
  }

  // -------------------------------------------------------------------------
  // Rename option with instance propagation (atomic)
  // -------------------------------------------------------------------------

  /// Rename a variant option and propagate to all instances.
  ///
  /// Updates the definition's option list, rebuilds affected matrix keys,
  /// and corrects `variantSelections` on every instance that was selecting
  /// the old value. Single undo entry.
  static CompositeCommand renameOptionAcrossInstances({
    required SymbolDefinition def,
    required String propertyId,
    required String oldValue,
    required String newValue,
    required List<SymbolInstanceNode> instances,
  }) {
    final prop = def.variantProperties.firstWhere((p) => p.id == propertyId);
    final propName = prop.name;
    final txn = CommandTransaction(
      label: 'Rename option "$oldValue" → "$newValue"',
    );

    try {
      // 1. Rename on definition (rebuilds keys).
      txn.add(
        RenameVariantOptionCommand(
          definition: def,
          propertyId: propertyId,
          oldValue: oldValue,
          newValue: newValue,
        ),
      );

      // 2. Propagate to instances selecting the old value.
      for (final inst in instances) {
        if (inst.variantSelections[propName] == oldValue) {
          txn.add(
            SetVariantSelectionCommand(
              instance: inst,
              propertyName: propName,
              newValue: newValue,
            ),
          );
        }
      }

      return txn.commit();
    } catch (e) {
      txn.rollback();
      rethrow;
    }
  }

  // -------------------------------------------------------------------------
  // Remove option with instance sanitization (atomic)
  // -------------------------------------------------------------------------

  /// Remove a variant option and sanitize all affected instances.
  ///
  /// Removes the option from the definition (cascading orphaned variants),
  /// then resets any instance selecting the deleted value to the property's
  /// default. Single undo entry.
  static CompositeCommand removeOptionAcrossInstances({
    required SymbolDefinition def,
    required String propertyId,
    required String value,
    required List<SymbolInstanceNode> instances,
  }) {
    final prop = def.variantProperties.firstWhere((p) => p.id == propertyId);
    final propName = prop.name;
    // Determine what the default will be AFTER removal.
    // If the removed value IS the default, fallback to the first remaining.
    final remainingOptions = prop.options.where((o) => o != value).toList();
    final fallback = remainingOptions.isNotEmpty ? remainingOptions.first : '';

    final txn = CommandTransaction(label: 'Remove option "$value"');

    try {
      // 1. Remove on definition (cascades orphaned variants).
      txn.add(
        RemoveVariantOptionCommand(
          definition: def,
          propertyId: propertyId,
          value: value,
        ),
      );

      // 2. Sanitize instances selecting the deleted value.
      for (final inst in instances) {
        if (inst.variantSelections[propName] == value) {
          txn.add(
            SetVariantSelectionCommand(
              instance: inst,
              propertyName: propName,
              newValue: fallback,
            ),
          );
        }
      }

      return txn.commit();
    } catch (e) {
      txn.rollback();
      rethrow;
    }
  }

  /// Parse a canonical variant key into a property-value map.
  ///
  /// Only works with keys built via [VariantContent.buildVariantKey]
  /// (which URI-encodes individual parts). Raw commas/equals in values
  /// are always encoded, so splitting on literal `,` and `=` is safe.
  static Map<String, String> _parseVariantKey(
    String key,
    SymbolDefinition def,
  ) {
    if (key.isEmpty) return {};
    final result = <String, String>{};
    for (final pair in key.split(',')) {
      final eqIndex = pair.indexOf('=');
      assert(eqIndex != -1, 'Malformed variant key segment: "$pair"');
      if (eqIndex == -1) continue;
      final name = Uri.decodeComponent(pair.substring(0, eqIndex));
      final value = Uri.decodeComponent(pair.substring(eqIndex + 1));
      result[name] = value;
    }
    return result;
  }
}

// ---------------------------------------------------------------------------
// Internal helper commands
// ---------------------------------------------------------------------------

/// Register a [SymbolDefinition] in a [SymbolRegistry]. Undo removes it.
class _RegisterDefinitionCommand extends Command {
  final SymbolRegistry registry;
  final SymbolDefinition definition;

  _RegisterDefinitionCommand({required this.registry, required this.definition})
    : super(label: 'Register "${definition.name}"');

  @override
  void execute() => registry.register(definition);

  @override
  void undo() => registry.remove(definition.id);
}
