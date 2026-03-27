library variable_manager_panel;

import 'dart:convert';
import 'package:flutter/material.dart';
import '../../systems/design_variables.dart';
import '../../systems/variable_binding.dart';
import '../../systems/variable_resolver.dart';
import '../../systems/design_token_exporter.dart';

part 'variable_manager_widgets.dart';


// =============================================================================
// 🎛️ VARIABLE MANAGER PANEL
//
// Draggable overlay panel for browsing, editing, and managing design variables.
// Driven by VariableCollection ChangeNotifier for fully reactive updates.
// =============================================================================

/// Full-featured panel for managing design variables and collections.
///
/// Features:
/// - Collection selector + mode switcher chips
/// - Grouped variable list with inline value editing
/// - Search/filter
/// - Add/remove collections, modes, variables
/// - Token export action
class VariableManagerPanel extends StatefulWidget {
  /// All variable collections from the scene graph.
  final List<VariableCollection> collections;

  /// Variable resolver for reading/switching active modes.
  final VariableResolver resolver;

  /// Variable bindings registry (for usage count display).
  final VariableBindingRegistry bindings;

  /// Called when a variable value is changed.
  final void Function(
    String collectionId,
    String variableId,
    String modeId,
    dynamic value,
  )?
  onValueChanged;

  /// Called when the active mode is switched for a collection.
  final void Function(String collectionId, String modeId)? onModeSwitch;

  /// Called when a new collection is added.
  final void Function(String name)? onAddCollection;

  /// Called when a new mode is added to a collection.
  final void Function(String collectionId, String modeName)? onAddMode;

  /// Called when a new variable is added.
  final void Function(String collectionId, DesignVariable variable)?
  onAddVariable;

  /// Called when a variable is removed.
  final void Function(String collectionId, String variableId)? onRemoveVariable;

  /// Called when tokens are exported.
  final void Function(String jsonOutput)? onExportTokens;

  /// Called when a variable is renamed inline.
  final void Function(String collectionId, String variableId, String newName)?
  onVariableRenamed;

  /// Called when W3C tokens are imported into a new collection.
  final void Function(VariableCollection collection)? onImportTokens;

  /// Called when the panel is closed.
  final VoidCallback? onClose;

  const VariableManagerPanel({
    super.key,
    required this.collections,
    required this.resolver,
    required this.bindings,
    this.onValueChanged,
    this.onModeSwitch,
    this.onAddCollection,
    this.onAddMode,
    this.onAddVariable,
    this.onRemoveVariable,
    this.onExportTokens,
    this.onVariableRenamed,
    this.onImportTokens,
    this.onClose,
  });

  @override
  State<VariableManagerPanel> createState() => _VariableManagerPanelState();
}

class _VariableManagerPanelState extends State<VariableManagerPanel> {
  int _selectedCollectionIndex = 0;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  String? _editingVariableId; // For inline rename
  final TextEditingController _renameController = TextEditingController();

  VariableCollection? get _activeCollection =>
      widget.collections.isNotEmpty &&
              _selectedCollectionIndex < widget.collections.length
          ? widget.collections[_selectedCollectionIndex]
          : null;

  String get _activeModeId {
    final c = _activeCollection;
    if (c == null) return '';
    return widget.resolver.getActiveMode(c.id) ?? c.defaultModeId;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _renameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 340,
        constraints: const BoxConstraints(maxHeight: 520),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
          border: Border.all(
            color:
                isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(cs, isDark),
            if (widget.collections.isEmpty)
              _buildEmptyState(cs)
            else ...[
              _buildCollectionSelector(cs, isDark),
              _buildModeChips(cs, isDark),
              _buildSearchBar(cs, isDark),
              Flexible(child: _buildVariableList(cs, isDark)),
            ],
            _buildFooter(cs, isDark),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header
  // ---------------------------------------------------------------------------

  Widget _buildHeader(ColorScheme cs, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.tune_rounded, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Text(
            'Design Variables',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const Spacer(),
          // Export tokens action
          if (_activeCollection != null)
            _IconBtn(
              icon: Icons.upload_rounded,
              tooltip: 'Import W3C Tokens',
              onTap: _handleImportTokens,
              cs: cs,
            ),
          if (_activeCollection != null)
            _IconBtn(
              icon: Icons.download_rounded,
              tooltip: 'Export W3C Tokens',
              onTap: _handleExportTokens,
              cs: cs,
            ),
          _IconBtn(
            icon: Icons.close_rounded,
            tooltip: 'Close',
            onTap: widget.onClose,
            cs: cs,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Collection Selector
  // ---------------------------------------------------------------------------

  Widget _buildCollectionSelector(ColorScheme cs, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _selectedCollectionIndex,
                  isExpanded: true,
                  isDense: true,
                  style: TextStyle(fontSize: 13, color: cs.onSurface),
                  items: [
                    for (var i = 0; i < widget.collections.length; i++)
                      DropdownMenuItem(
                        value: i,
                        child: Text(
                          widget.collections[i].name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged:
                      (v) => setState(() => _selectedCollectionIndex = v ?? 0),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _IconBtn(
            icon: Icons.add_rounded,
            tooltip: 'New Collection',
            onTap: () => _showAddCollectionDialog(cs),
            cs: cs,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Mode Chips
  // ---------------------------------------------------------------------------

  Widget _buildModeChips(ColorScheme cs, bool isDark) {
    final collection = _activeCollection;
    if (collection == null) return const SizedBox.shrink();

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final mode in collection.modes)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(mode.name, style: const TextStyle(fontSize: 11)),
                selected: _activeModeId == mode.id,
                onSelected: (_) {
                  widget.onModeSwitch?.call(collection.id, mode.id);
                  setState(() {});
                },
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          // Add mode button
          ActionChip(
            avatar: const Icon(Icons.add, size: 14),
            label: const Text('Mode', style: TextStyle(fontSize: 11)),
            onPressed: () => _showAddModeDialog(cs, collection),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Search Bar
  // ---------------------------------------------------------------------------

  Widget _buildSearchBar(ColorScheme cs, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _searchQuery = v),
        style: TextStyle(fontSize: 12, color: cs.onSurface),
        decoration: InputDecoration(
          hintText: 'Search variables…',
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
    );
  }

  // ---------------------------------------------------------------------------
  // Variable List (grouped)
  // ---------------------------------------------------------------------------

  Widget _buildVariableList(ColorScheme cs, bool isDark) {
    final collection = _activeCollection;
    if (collection == null) return const SizedBox.shrink();

    final variables =
        _searchQuery.isEmpty
            ? collection.variables
            : collection.searchVariables(_searchQuery);

    if (variables.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          _searchQuery.isEmpty ? 'No variables yet' : 'No results',
          style: TextStyle(
            fontSize: 12,
            color: cs.onSurface.withValues(alpha: 0.4),
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    // Group by group path.
    final groups = <String, List<DesignVariable>>{};
    for (final v in variables) {
      final key = v.group ?? '';
      (groups[key] ??= []).add(v);
    }

    final sortedKeys = groups.keys.toList()..sort();

    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: sortedKeys.length,
      itemBuilder: (ctx, i) {
        final groupKey = sortedKeys[i];
        final vars = groups[groupKey]!;
        return _buildGroupSection(cs, isDark, groupKey, vars);
      },
    );
  }

  Widget _buildGroupSection(
    ColorScheme cs,
    bool isDark,
    String groupKey,
    List<DesignVariable> vars,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (groupKey.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
            child: Row(
              children: [
                Icon(
                  Icons.folder_outlined,
                  size: 12,
                  color: cs.onSurface.withValues(alpha: 0.4),
                ),
                const SizedBox(width: 4),
                Text(
                  groupKey,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface.withValues(alpha: 0.5),
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        for (final v in vars) _buildVariableRow(cs, isDark, v),
      ],
    );
  }

  Widget _buildVariableRow(ColorScheme cs, bool isDark, DesignVariable v) {
    final modeId = _activeModeId;
    final collection = _activeCollection!;
    final resolvedValue = collection.resolveVariable(v.id, modeId);
    final bindingCount = widget.bindings.bindingsForVariable(v.id).length;
    final isRenaming = _editingVariableId == v.id;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color:
            isDark
                ? Colors.white.withValues(alpha: 0.03)
                : Colors.black.withValues(alpha: 0.02),
      ),
      child: Row(
        children: [
          // Type indicator
          _VariableTypeIcon(type: v.type),
          const SizedBox(width: 8),
          // Name (tappable for rename)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isRenaming)
                  SizedBox(
                    height: 22,
                    child: TextField(
                      controller: _renameController,
                      autofocus: true,
                      style: TextStyle(fontSize: 12, color: cs.onSurface),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                      ),
                      onSubmitted: (newName) {
                        if (newName.isNotEmpty && newName != v.name) {
                          widget.onVariableRenamed?.call(
                            collection.id,
                            v.id,
                            newName,
                          );
                        }
                        setState(() => _editingVariableId = null);
                      },
                      onTapOutside: (_) {
                        setState(() => _editingVariableId = null);
                      },
                    ),
                  )
                else
                  GestureDetector(
                    onDoubleTap: () {
                      _renameController.text = v.name;
                      setState(() => _editingVariableId = v.id);
                    },
                    child: Text(
                      v.name,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: cs.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (v.isAlias)
                  Text(
                    '→ ${v.aliasVariableId}',
                    style: TextStyle(
                      fontSize: 10,
                      color: cs.primary.withValues(alpha: 0.7),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
          // Resolved value (tappable for inline editing)
          GestureDetector(
            onTap: () => _showInlineEditor(cs, collection, v, modeId),
            child: _ValuePreview(type: v.type, value: resolvedValue, cs: cs),
          ),
          // Boolean shortcut: inline toggle
          if (v.type == DesignVariableType.boolean)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: SizedBox(
                height: 20,
                child: Switch(
                  value: resolvedValue == true,
                  onChanged: (val) {
                    widget.onValueChanged?.call(
                      collection.id,
                      v.id,
                      modeId,
                      val,
                    );
                    setState(() {});
                  },
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          // Binding count badge
          if (bindingCount > 0)
            Container(
              margin: const EdgeInsets.only(left: 4),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '$bindingCount',
                style: TextStyle(
                  fontSize: 9,
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          // Delete
          _IconBtn(
            icon: Icons.delete_outline,
            tooltip: 'Remove',
            size: 14,
            onTap: () => widget.onRemoveVariable?.call(collection.id, v.id),
            cs: cs,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Empty state
  // ---------------------------------------------------------------------------

  Widget _buildEmptyState(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(
            Icons.tune_rounded,
            size: 40,
            color: cs.onSurface.withValues(alpha: 0.15),
          ),
          const SizedBox(height: 12),
          Text(
            'No variable collections',
            style: TextStyle(
              fontSize: 13,
              color: cs.onSurface.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: () => _showAddCollectionDialog(cs),
            child: const Text(
              'Create Collection',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Footer
  // ---------------------------------------------------------------------------

  Widget _buildFooter(ColorScheme cs, bool isDark) {
    if (_activeCollection == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: () => _showAddVariableDialog(cs),
            icon: const Icon(Icons.add, size: 14),
            label: const Text('Variable', style: TextStyle(fontSize: 11)),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
          const Spacer(),
          Text(
            '${_activeCollection!.variables.length} vars · ${_activeCollection!.modes.length} modes',
            style: TextStyle(
              fontSize: 10,
              color: cs.onSurface.withValues(alpha: 0.35),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Dialogs
  // ---------------------------------------------------------------------------

  void _showAddCollectionDialog(ColorScheme cs) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('New Collection', style: TextStyle(fontSize: 16)),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'e.g. Theme Colors',
                isDense: true,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (controller.text.isNotEmpty) {
                    widget.onAddCollection?.call(controller.text);
                    Navigator.pop(context);
                    setState(() {});
                  }
                },
                child: const Text('Create'),
              ),
            ],
          ),
    );
  }

  void _showAddModeDialog(ColorScheme cs, VariableCollection collection) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('New Mode', style: TextStyle(fontSize: 16)),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'e.g. Dark, Mobile',
                isDense: true,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (controller.text.isNotEmpty) {
                    widget.onAddMode?.call(collection.id, controller.text);
                    Navigator.pop(context);
                    setState(() {});
                  }
                },
                child: const Text('Add'),
              ),
            ],
          ),
    );
  }

  void _showAddVariableDialog(ColorScheme cs) {
    final nameController = TextEditingController();
    final groupController = TextEditingController();
    var selectedType = DesignVariableType.color;

    showDialog(
      context: context,
      builder:
          (_) => StatefulBuilder(
            builder:
                (ctx, setDialogState) => AlertDialog(
                  title: const Text(
                    'New Variable',
                    style: TextStyle(fontSize: 16),
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        autofocus: true,
                        decoration: const InputDecoration(
                          hintText: 'Variable name',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: groupController,
                        decoration: const InputDecoration(
                          hintText: 'Group (e.g. colors/primary)',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<DesignVariableType>(
                        initialValue: selectedType,
                        decoration: const InputDecoration(
                          labelText: 'Type',
                          isDense: true,
                        ),
                        items:
                            DesignVariableType.values
                                .map(
                                  (t) => DropdownMenuItem(
                                    value: t,
                                    child: Text(t.name),
                                  ),
                                )
                                .toList(),
                        onChanged:
                            (v) => setDialogState(() => selectedType = v!),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () {
                        if (nameController.text.isNotEmpty &&
                            _activeCollection != null) {
                          final id =
                              'var_${DateTime.now().microsecondsSinceEpoch}';
                          final variable = DesignVariable(
                            id: id,
                            name: nameController.text,
                            type: selectedType,
                            group:
                                groupController.text.isEmpty
                                    ? null
                                    : groupController.text,
                          );
                          widget.onAddVariable?.call(
                            _activeCollection!.id,
                            variable,
                          );
                          Navigator.pop(context);
                          setState(() {});
                        }
                      },
                      child: const Text('Add'),
                    ),
                  ],
                ),
          ),
    );
  }

  // ---------------------------------------------------------------------------
  // Token Export
  // ---------------------------------------------------------------------------

  void _handleExportTokens() {
    final collection = _activeCollection;
    if (collection == null) return;

    final json = DesignTokenExporter.exportToJson(
      collections: [collection],
      activeModes: {collection.id: _activeModeId},
      format: DesignTokenFormat.w3c,
    );
    widget.onExportTokens?.call(json);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Exported ${collection.variables.length} tokens (W3C DTCG)',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Token Import
  // ---------------------------------------------------------------------------

  void _handleImportTokens() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text(
              'Import W3C Tokens',
              style: TextStyle(fontSize: 16),
            ),
            content: SizedBox(
              width: 300,
              height: 200,
              child: TextField(
                controller: controller,
                maxLines: null,
                expands: true,
                autofocus: true,
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  hintText: 'Paste W3C DTCG JSON here…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  _doImport(controller.text);
                  Navigator.pop(context);
                },
                child: const Text('Import'),
              ),
            ],
          ),
    );
  }

  void _doImport(String jsonText) {
    if (jsonText.trim().isEmpty) return;
    try {
      final parsed = jsonDecode(jsonText) as Map<String, dynamic>;
      final id = 'col_import_${DateTime.now().microsecondsSinceEpoch}';
      final result = DesignTokenExporter.importW3CWithValidation(
        collectionId: id,
        collectionName: 'Imported Tokens',
        modeId: 'default',
        tokenDocument: parsed,
      );
      widget.onImportTokens?.call(result.collection);
      setState(() {});

      final msg =
          result.errors.isEmpty
              ? 'Imported ${result.collection.variables.length} tokens'
              : 'Imported ${result.collection.variables.length} tokens '
                  '(${result.errors.length} warnings)';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invalid JSON: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Inline Value Editing
  // ---------------------------------------------------------------------------

  void _showInlineEditor(
    ColorScheme cs,
    VariableCollection collection,
    DesignVariable variable,
    String modeId,
  ) {
    switch (variable.type) {
      case DesignVariableType.color:
        _showColorEditor(cs, collection, variable, modeId);
      case DesignVariableType.number:
        _showNumberEditor(cs, collection, variable, modeId);
      case DesignVariableType.string:
        _showStringEditor(cs, collection, variable, modeId);
      case DesignVariableType.boolean:
        // Boolean uses inline toggle, no dialog needed
        final current = collection.resolveVariable(variable.id, modeId);
        widget.onValueChanged?.call(
          collection.id,
          variable.id,
          modeId,
          !(current == true),
        );
        setState(() {});
    }
  }

  void _showColorEditor(
    ColorScheme cs,
    VariableCollection collection,
    DesignVariable variable,
    String modeId,
  ) {
    final current = collection.resolveVariable(variable.id, modeId);
    final initialColor =
        (current is int) ? Color(current) : const Color(0xFF6200EE);
    Color selectedColor = initialColor;

    showDialog(
      context: context,
      builder:
          (_) => StatefulBuilder(
            builder:
                (ctx, setDialogState) => AlertDialog(
                  title: Text(
                    'Edit: ${variable.name}',
                    style: const TextStyle(fontSize: 14),
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Color swatch grid (Material palette)
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final c in [
                            Colors.red,
                            Colors.pink,
                            Colors.purple,
                            Colors.deepPurple,
                            Colors.indigo,
                            Colors.blue,
                            Colors.lightBlue,
                            Colors.cyan,
                            Colors.teal,
                            Colors.green,
                            Colors.lightGreen,
                            Colors.lime,
                            Colors.yellow,
                            Colors.amber,
                            Colors.orange,
                            Colors.deepOrange,
                            Colors.brown,
                            Colors.grey,
                            Colors.blueGrey,
                            Colors.black,
                            Colors.white,
                          ])
                            GestureDetector(
                              onTap:
                                  () => setDialogState(() => selectedColor = c),
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: c,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color:
                                        selectedColor == c
                                            ? cs.primary
                                            : cs.outline.withValues(alpha: 0.2),
                                    width: selectedColor == c ? 2 : 1,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Current preview
                      Container(
                        height: 32,
                        decoration: BoxDecoration(
                          color: selectedColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: cs.outline.withValues(alpha: 0.3),
                          ),
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () {
                        widget.onValueChanged?.call(
                          collection.id,
                          variable.id,
                          modeId,
                          selectedColor.toARGB32(),
                        );
                        setState(() {});
                        Navigator.pop(context);
                      },
                      child: const Text('Apply'),
                    ),
                  ],
                ),
          ),
    );
  }

  void _showNumberEditor(
    ColorScheme cs,
    VariableCollection collection,
    DesignVariable variable,
    String modeId,
  ) {
    final current = collection.resolveVariable(variable.id, modeId);
    final controller = TextEditingController(
      text: current is num ? current.toString() : '',
    );

    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: Text(
              'Edit: ${variable.name}',
              style: const TextStyle(fontSize: 14),
            ),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Value',
                isDense: true,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final val = num.tryParse(controller.text);
                  if (val != null) {
                    widget.onValueChanged?.call(
                      collection.id,
                      variable.id,
                      modeId,
                      val,
                    );
                    setState(() {});
                  }
                  Navigator.pop(context);
                },
                child: const Text('Apply'),
              ),
            ],
          ),
    );
  }

  void _showStringEditor(
    ColorScheme cs,
    VariableCollection collection,
    DesignVariable variable,
    String modeId,
  ) {
    final current = collection.resolveVariable(variable.id, modeId);
    final controller = TextEditingController(
      text: current is String ? current : '',
    );

    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: Text(
              'Edit: ${variable.name}',
              style: const TextStyle(fontSize: 14),
            ),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Value',
                isDense: true,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  widget.onValueChanged?.call(
                    collection.id,
                    variable.id,
                    modeId,
                    controller.text,
                  );
                  setState(() {});
                  Navigator.pop(context);
                },
                child: const Text('Apply'),
              ),
            ],
          ),
    );
  }
}
