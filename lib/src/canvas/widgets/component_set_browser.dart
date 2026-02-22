/// 🗂️ COMPONENT SET BROWSER — Grouped components panel.
///
/// Shows component sets with their variants, supporting auto-grouping
/// and instance insertion.
///
/// ```dart
/// ComponentSetBrowser(
///   setRegistry: componentSetRegistry,
///   symbolRegistry: symbolRegistry,
///   onInsertInstance: (definitionId) => createInstance(definitionId),
/// )
/// ```
library;

import 'package:flutter/material.dart';
import '../../core/nodes/symbol_system.dart';
import '../../systems/component_set.dart';

/// Panel widget for browsing component sets.
class ComponentSetBrowser extends StatefulWidget {
  final ComponentSetRegistry setRegistry;
  final SymbolRegistry symbolRegistry;
  final void Function(String definitionId)? onInsertInstance;
  final void Function()? onClose;

  const ComponentSetBrowser({
    super.key,
    required this.setRegistry,
    required this.symbolRegistry,
    this.onInsertInstance,
    this.onClose,
  });

  @override
  State<ComponentSetBrowser> createState() => _ComponentSetBrowserState();
}

class _ComponentSetBrowserState extends State<ComponentSetBrowser> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sets =
        widget.setRegistry.sets.values
            .where(
              (s) =>
                  _searchQuery.isEmpty ||
                  s.name.toLowerCase().contains(_searchQuery.toLowerCase()),
            )
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));

    // Ungrouped definitions (not in any set).
    final groupedIds = <String>{};
    for (final set in widget.setRegistry.sets.values) {
      groupedIds.addAll(set.definitionIds);
    }
    final ungrouped =
        widget.symbolRegistry.definitions
            .where((d) => !groupedIds.contains(d.id))
            .where(
              (d) =>
                  _searchQuery.isEmpty ||
                  d.name.toLowerCase().contains(_searchQuery.toLowerCase()),
            )
            .toList();

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(left: BorderSide(color: cs.outline.withAlpha(30))),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                const Icon(Icons.widgets, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Components',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.auto_awesome, size: 16),
                  tooltip: 'Auto-group by name',
                  onPressed: () {
                    widget.setRegistry.autoGroup(widget.symbolRegistry);
                    setState(() {});
                  },
                ),
                if (widget.onClose != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: widget.onClose,
                  ),
              ],
            ),
          ),
          // Search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Search components...',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: cs.outline.withAlpha(40)),
                ),
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(height: 4),
          // Component sets
          Expanded(
            child: ListView(
              children: [
                ...sets.map(
                  (set) => _ComponentSetTile(
                    set: set,
                    symbolRegistry: widget.symbolRegistry,
                    onInsertInstance: widget.onInsertInstance,
                  ),
                ),
                if (ungrouped.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      'Ungrouped',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                  ...ungrouped.map(
                    (def) => _DefinitionTile(
                      definition: def,
                      onTap: () => widget.onInsertInstance?.call(def.id),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ComponentSetTile extends StatelessWidget {
  final ComponentSet set;
  final SymbolRegistry symbolRegistry;
  final void Function(String)? onInsertInstance;

  const _ComponentSetTile({
    required this.set,
    required this.symbolRegistry,
    this.onInsertInstance,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final defs =
        set.definitionIds
            .map((id) => symbolRegistry.lookup(id))
            .whereType<SymbolDefinition>()
            .toList();

    return ExpansionTile(
      leading: Icon(Icons.folder, size: 18, color: cs.primary),
      title: Text(
        set.name,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        '${set.variantCount} variants',
        style: TextStyle(fontSize: 11, color: cs.onSurface.withAlpha(130)),
      ),
      children:
          defs
              .map(
                (def) => _DefinitionTile(
                  definition: def,
                  onTap: () => onInsertInstance?.call(def.id),
                  indent: true,
                ),
              )
              .toList(),
    );
  }
}

class _DefinitionTile extends StatelessWidget {
  final SymbolDefinition definition;
  final VoidCallback? onTap;
  final bool indent;

  const _DefinitionTile({
    required this.definition,
    this.onTap,
    this.indent = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.only(left: indent ? 56 : 16, right: 16),
      leading: Icon(
        Icons.widgets_outlined,
        size: 16,
        color: cs.onSurface.withAlpha(150),
      ),
      title: Text(definition.name, style: const TextStyle(fontSize: 12)),
      trailing: IconButton(
        icon: const Icon(Icons.add_circle_outline, size: 16),
        tooltip: 'Insert instance',
        onPressed: onTap,
      ),
      onTap: onTap,
    );
  }
}
