part of '../fluera_canvas_screen.dart';

// =============================================================================
// 🎛️ DESIGN VARIABLES — Canvas integration part
//
// State and methods for the VariableManagerPanel & property binding sheet.
// The canvas screen owns variable state directly because the SceneGraph is
// lazily rebuilt from layers, which would discard variable state.
//
// All mutations go through CommandHistory for full undo/redo support.
// =============================================================================

extension DesignVariablesUI on _FlueraCanvasScreenState {
  // ---------------------------------------------------------------------------
  // Panel toggle
  // ---------------------------------------------------------------------------

  /// Toggle the variable manager panel.
  void _toggleVariablePanel() {
    setState(() {
      _showVariablePanel = !_showVariablePanel;
    });
  }

  // ---------------------------------------------------------------------------
  // Total variable count (for toolbar badge)
  // ---------------------------------------------------------------------------

  /// Total number of variables across all collections.
  int get _totalVariableCount {
    int count = 0;
    for (final c in _variableCollections) {
      count += c.variables.length;
    }
    return count;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  DesignVariable? _findVariable(String collectionId, String variableId) {
    for (final c in _variableCollections) {
      if (c.id == collectionId) return c.findVariable(variableId);
    }
    return null;
  }

  VariableCollection? _findCollection(String collectionId) {
    for (final c in _variableCollections) {
      if (c.id == collectionId) return c;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Panel widget builder
  // ---------------------------------------------------------------------------

  /// Build the VariableManagerPanel overlay (positioned top-right).
  Widget _buildVariableManagerOverlay() {
    if (!_showVariablePanel) return const SizedBox.shrink();

    return Positioned(
      right: 12,
      top: 60,
      child: VariableManagerPanel(
        collections: _variableCollections,
        resolver: _variableResolver,
        bindings: _variableBindings,
        onClose: _toggleVariablePanel,

        // ── Value editing (undoable) ──────────────────────────────
        onValueChanged: (collectionId, variableId, modeId, value) {
          final v = _findVariable(collectionId, variableId);
          if (v == null) return;
          _commandHistory.execute(
            SetVariableValueCommand(
              variable: v,
              modeId: modeId,
              newValue: value,
            ),
          );
          setState(() {});
          _autoSaveCanvas();
        },

        // ── Mode switch (undoable) ───────────────────────────────
        onModeSwitch: (collectionId, modeId) {
          _commandHistory.execute(
            SetActiveModeCommand(
              resolver: _variableResolver,
              collectionId: collectionId,
              newModeId: modeId,
            ),
          );
          setState(() {});
          _autoSaveCanvas();
        },

        // ── Add collection (not undoable — structural) ───────────
        onAddCollection: (name) {
          final id = 'col_${DateTime.now().microsecondsSinceEpoch}';
          final collection = VariableCollection(id: id, name: name);
          _variableCollections.add(collection);
          _variableResolver.addCollection(collection);
          setState(() {});
          _autoSaveCanvas();
        },

        // ── Add mode (not undoable — structural) ─────────────────
        onAddMode: (collectionId, modeName) {
          for (final c in _variableCollections) {
            if (c.id == collectionId) {
              final modeId = 'mode_${DateTime.now().microsecondsSinceEpoch}';
              c.addMode(VariableMode(id: modeId, name: modeName));
              break;
            }
          }
          setState(() {});
          _autoSaveCanvas();
        },

        // ── Add variable (undoable) ──────────────────────────────
        onAddVariable: (collectionId, variable) {
          final c = _findCollection(collectionId);
          if (c == null) return;
          _commandHistory.execute(
            AddVariableCommand(collection: c, variable: variable),
          );
          setState(() {});
          _autoSaveCanvas();
        },

        // ── Remove variable (undoable, restores bindings on undo) ─
        onRemoveVariable: (collectionId, variableId) {
          final c = _findCollection(collectionId);
          if (c == null) return;
          final v = c.findVariable(variableId);
          if (v == null) return;
          _commandHistory.execute(
            RemoveVariableCommand(
              collection: c,
              variable: v,
              bindingRegistry: _variableBindings,
            ),
          );
          setState(() {});
          _autoSaveCanvas();
        },

        // ── Rename variable (undoable) ───────────────────────────
        onVariableRenamed: (collectionId, variableId, newName) {
          final v = _findVariable(collectionId, variableId);
          if (v == null) return;
          _commandHistory.execute(
            PropertyChangeCommand<String>(
              label: 'Rename "${v.name}" → "$newName"',
              oldValue: v.name,
              newValue: newName,
              setter: (val) => v.name = val,
            ),
          );
          setState(() {});
          _autoSaveCanvas();
        },

        // ── Token import ─────────────────────────────────────────
        onImportTokens: (collection) {
          _variableCollections.add(collection);
          _variableResolver.addCollection(collection);
          setState(() {});
          _autoSaveCanvas();
        },

        // ── Token export ─────────────────────────────────────────
        onExportTokens: (json) {
          debugPrint('🌐 [DesignTokenExport]\n$json');
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Property binding sheet
  // ---------------------------------------------------------------------------

  /// Show the variable property binding sheet for a node.
  void _showVariablePropertySheet({
    required String nodeId,
    required String propertyName,
    required DesignVariableType propertyType,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (_) => VariablePropertySheet(
            nodeId: nodeId,
            propertyName: propertyName,
            propertyType: propertyType,
            collections: _variableCollections,
            bindings: _variableBindings,
            onBind: (variableId) {
              final binding = VariableBinding(
                variableId: variableId,
                nodeId: nodeId,
                nodeProperty: propertyName,
              );
              _commandHistory.execute(
                AddBindingCommand(
                  registry: _variableBindings,
                  binding: binding,
                ),
              );
              _autoSaveCanvas();
              setState(() {});
            },
            onUnbind: () {
              final existing = _variableBindings.bindingsForNode(nodeId);
              for (final b in existing) {
                if (b.nodeProperty == propertyName) {
                  _commandHistory.execute(
                    RemoveBindingCommand(
                      registry: _variableBindings,
                      binding: b,
                    ),
                  );
                  break;
                }
              }
              _autoSaveCanvas();
              setState(() {});
            },
          ),
    );
  }
}
