import 'package:flutter/material.dart';
import '../../systems/design_variables.dart';
import '../../systems/variable_binding.dart';

// =============================================================================
// 🔗 VARIABLE PROPERTY SHEET
//
// Bottom sheet for binding a selected node's property to a design variable.
// Shows available variables filtered by compatible type.
// =============================================================================

/// Bottom sheet for linking a node property to a design variable.
///
/// Usage:
/// ```dart
/// showModalBottomSheet(
///   context: context,
///   builder: (_) => VariablePropertySheet(
///     nodeId: selectedNodeId,
///     propertyName: 'fill',
///     propertyType: DesignVariableType.color,
///     collections: sceneGraph.variableCollections,
///     bindings: sceneGraph.variableBindings,
///     onBind: (variableId) => ...,
///     onUnbind: () => ...,
///   ),
/// );
/// ```
class VariablePropertySheet extends StatefulWidget {
  /// The ID of the currently selected node.
  final String nodeId;

  /// The property name to bind (e.g. 'fill', 'opacity', 'text').
  final String propertyName;

  /// Expected variable type for filtering compatible variables.
  final DesignVariableType propertyType;

  /// All variable collections from the scene graph.
  final List<VariableCollection> collections;

  /// Binding registry to check current bindings.
  final VariableBindingRegistry bindings;

  /// Called when a variable is bound to this property.
  final void Function(String variableId)? onBind;

  /// Called when the current binding is removed.
  final VoidCallback? onUnbind;

  const VariablePropertySheet({
    super.key,
    required this.nodeId,
    required this.propertyName,
    required this.propertyType,
    required this.collections,
    required this.bindings,
    this.onBind,
    this.onUnbind,
  });

  @override
  State<VariablePropertySheet> createState() => _VariablePropertySheetState();
}

class _VariablePropertySheetState extends State<VariablePropertySheet> {
  String _searchQuery = '';

  /// Current binding for this node+property (if any).
  VariableBinding? get _currentBinding {
    final nodeBindings = widget.bindings.bindingsForNode(widget.nodeId);
    for (final b in nodeBindings) {
      if (b.nodeProperty == widget.propertyName) return b;
    }
    return null;
  }

  /// All compatible variables (matching type) across all collections.
  List<(VariableCollection, DesignVariable)> get _compatibleVariables {
    final results = <(VariableCollection, DesignVariable)>[];
    for (final c in widget.collections) {
      for (final v in c.variables) {
        if (v.type != widget.propertyType) continue;
        if (_searchQuery.isNotEmpty &&
            !v.name.toLowerCase().contains(_searchQuery.toLowerCase())) {
          continue;
        }
        results.add((c, v));
      }
    }
    return results;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    final currentBind = _currentBinding;
    final compatible = _compatibleVariables;

    return Container(
      constraints: const BoxConstraints(maxHeight: 420),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 32,
              height: 4,
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Icon(Icons.link_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Link Variable → ${widget.propertyName}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      Text(
                        'Type: ${widget.propertyType.name}',
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Current binding info
          if (currentBind != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.link, size: 14, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Bound to: ${currentBind.variableId}',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      widget.onUnbind?.call();
                      Navigator.pop(context);
                    },
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: Colors.red,
                    ),
                    child: const Text('Unlink', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ),

          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              style: TextStyle(fontSize: 12, color: cs.onSurface),
              decoration: InputDecoration(
                hintText: 'Search ${widget.propertyType.name} variables…',
                hintStyle: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.4),
                ),
                prefixIcon: Icon(
                  Icons.search,
                  size: 16,
                  color: cs.onSurface.withValues(alpha: 0.4),
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                filled: true,
                fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // Variable list
          Flexible(
            child:
                compatible.isEmpty
                    ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No ${widget.propertyType.name} variables available',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withValues(alpha: 0.4),
                        ),
                      ),
                    )
                    : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                      itemCount: compatible.length,
                      itemBuilder: (ctx, i) {
                        final (collection, variable) = compatible[i];
                        final isBound = currentBind?.variableId == variable.id;
                        return _buildVariableOption(
                          cs,
                          isDark,
                          collection,
                          variable,
                          isBound,
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildVariableOption(
    ColorScheme cs,
    bool isDark,
    VariableCollection collection,
    DesignVariable variable,
    bool isBound,
  ) {
    return InkWell(
      onTap:
          isBound
              ? null
              : () {
                widget.onBind?.call(variable.id);
                Navigator.pop(context);
              },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        margin: const EdgeInsets.symmetric(vertical: 1),
        decoration: BoxDecoration(
          color:
              isBound
                  ? cs.primaryContainer.withValues(alpha: 0.2)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border:
              isBound
                  ? Border.all(color: cs.primary.withValues(alpha: 0.4))
                  : null,
        ),
        child: Row(
          children: [
            // Bound indicator
            if (isBound)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(Icons.check_circle, size: 14, color: cs.primary),
              ),
            // Variable info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    variable.name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isBound ? FontWeight.w600 : FontWeight.w400,
                      color: cs.onSurface,
                    ),
                  ),
                  Text(
                    '${collection.name}${variable.group != null ? ' / ${variable.group}' : ''}',
                    style: TextStyle(
                      fontSize: 10,
                      color: cs.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ),
            // Arrow
            if (!isBound)
              Icon(
                Icons.arrow_forward_ios,
                size: 12,
                color: cs.onSurface.withValues(alpha: 0.3),
              ),
          ],
        ),
      ),
    );
  }
}
