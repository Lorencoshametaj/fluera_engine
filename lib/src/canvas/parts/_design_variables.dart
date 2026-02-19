part of '../nebula_canvas_screen.dart';

// =============================================================================
// 🎛️ DESIGN VARIABLES — Canvas integration part
//
// State and methods for the VariableManagerPanel & property binding sheet.
// The canvas screen owns variable state directly because the SceneGraph is
// lazily rebuilt from layers, which would discard variable state.
// =============================================================================

extension DesignVariablesUI on _NebulaCanvasScreenState {
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
        onValueChanged: (collectionId, variableId, modeId, value) {
          // Value already set on DesignVariable by the panel — just persist
          setState(() {});
          _autoSaveCanvas();
        },
        onModeSwitch: (collectionId, modeId) {
          _variableResolver.setActiveMode(collectionId, modeId);
          setState(() {});
          _autoSaveCanvas();
        },
        onAddCollection: (name) {
          final id = 'col_${DateTime.now().microsecondsSinceEpoch}';
          final collection = VariableCollection(id: id, name: name);
          _variableCollections.add(collection);
          _variableResolver.addCollection(collection);
          setState(() {});
          _autoSaveCanvas();
        },
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
        onAddVariable: (collectionId, variable) {
          for (final c in _variableCollections) {
            if (c.id == collectionId) {
              c.addVariable(variable);
              break;
            }
          }
          setState(() {});
          _autoSaveCanvas();
        },
        onRemoveVariable: (collectionId, variableId) {
          for (final c in _variableCollections) {
            if (c.id == collectionId) {
              c.removeVariable(variableId);
              break;
            }
          }
          setState(() {});
          _autoSaveCanvas();
        },
        onVariableRenamed: (collectionId, variableId, newName) {
          for (final c in _variableCollections) {
            if (c.id == collectionId) {
              final v = c.variables.cast<DesignVariable?>().firstWhere(
                (v) => v!.id == variableId,
                orElse: () => null,
              );
              if (v != null) {
                v.name = newName;
              }
              break;
            }
          }
          setState(() {});
          _autoSaveCanvas();
        },
        onImportTokens: (collection) {
          _variableCollections.add(collection);
          _variableResolver.addCollection(collection);
          setState(() {});
          _autoSaveCanvas();
        },
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
              _variableBindings.addBinding(
                VariableBinding(
                  variableId: variableId,
                  nodeId: nodeId,
                  nodeProperty: propertyName,
                ),
              );
              _autoSaveCanvas();
              setState(() {});
            },
            onUnbind: () {
              final existing = _variableBindings.bindingsForNode(nodeId);
              for (final b in existing) {
                if (b.nodeProperty == propertyName) {
                  _variableBindings.removeBinding(b);
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
