part of '../nebula_canvas_screen.dart';

// ============================================================================
// ✅ DESIGN QUALITY — Wire smart snap, lint, styles, a11y, selection query
// ============================================================================

extension DesignQualityFeatures on _NebulaCanvasScreenState {
  /// Toggle smart snap engine.
  /// Wires: smart_snap_engine
  void _toggleSmartSnap() {
    setState(() {
      _isSmartSnapEnabled = !_isSmartSnapEnabled;
    });
    if (_isSmartSnapEnabled) {
      _smartSnapEngine = SmartSnapEngine();
      debugPrint('[Design] Smart Snap ON');
    } else {
      _smartSnapEngine = null;
      debugPrint('[Design] Smart Snap OFF');
    }
  }

  /// Run design linter and show results.
  /// Wires: design_linter
  void _runDesignLint() {
    final linter =
        DesignLinter()
          ..addRule(MissingA11yLabelRule())
          ..addRule(ConstraintConflictRule())
          ..addRule(DeepNestingRule())
          ..addRule(UnnamedNodeRule());
    final sceneGraph = _layerController.sceneGraph;
    final violations = linter.lint(sceneGraph);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DesignQualityPanel(lintResults: violations),
    );
    debugPrint('[Design] Lint: ${violations.length} issues found');
  }

  /// Show style system panel.
  /// Wires: style_system, theme_manager, engine_theme, semantic_token
  void _showStyleSystemPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          builder:
              (ctx, scrollCtrl) => Container(
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 8, bottom: 4),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.palette_rounded,
                            color: cs.primary,
                            size: 28,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Style System',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.all(16),
                        children: [
                          _buildStyleGroupCard(
                            cs,
                            'Color Styles',
                            Icons.color_lens_rounded,
                            Colors.pink,
                          ),
                          const SizedBox(height: 12),
                          _buildStyleGroupCard(
                            cs,
                            'Text Styles',
                            Icons.text_fields_rounded,
                            Colors.indigo,
                          ),
                          const SizedBox(height: 12),
                          _buildStyleGroupCard(
                            cs,
                            'Effect Styles',
                            Icons.blur_on_rounded,
                            Colors.deepOrange,
                          ),
                          const SizedBox(height: 12),
                          _buildStyleGroupCard(
                            cs,
                            'Grid Styles',
                            Icons.grid_4x4_rounded,
                            Colors.teal,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        );
      },
    );
    debugPrint('[Design] Style system panel opened');
  }

  Widget _buildStyleGroupCard(
    ColorScheme cs,
    String title,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const Spacer(),
          Icon(
            Icons.chevron_right_rounded,
            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ],
      ),
    );
  }

  /// Show accessibility tree overlay.
  /// Wires: accessibility_bridge, accessibility_tree
  void _showAccessibilityTree() {
    final builder = AccessibilityTreeBuilder();
    final sceneGraph = _layerController.sceneGraph;
    final root = sceneGraph.rootNode;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final tree = builder.buildTree(root);
        final nodes = tree?.flatten() ?? [];
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.25,
          maxChildSize: 0.8,
          builder:
              (ctx, scrollCtrl) => Container(
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 8, bottom: 4),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.accessibility_new_rounded,
                            color: cs.primary,
                            size: 28,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Accessibility Tree',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                          ),
                          const Spacer(),
                          Chip(
                            label: Text('${nodes.length} nodes'),
                            backgroundColor: cs.primaryContainer,
                            labelStyle: TextStyle(
                              color: cs.onPrimaryContainer,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child:
                          nodes.isEmpty
                              ? Center(
                                child: Text(
                                  'No semantic nodes found',
                                  style: TextStyle(color: cs.onSurfaceVariant),
                                ),
                              )
                              : ListView.builder(
                                controller: scrollCtrl,
                                padding: const EdgeInsets.all(12),
                                itemCount: nodes.length,
                                itemBuilder:
                                    (ctx, i) => ListTile(
                                      leading: Icon(
                                        Icons.label_rounded,
                                        color: cs.primary,
                                        size: 20,
                                      ),
                                      title: Text(
                                        nodes[i].info.label ?? 'Unnamed',
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                      subtitle: Text(
                                        nodes[i].info.role.name,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                      dense: true,
                                    ),
                              ),
                    ),
                  ],
                ),
              ),
        );
      },
    );
    debugPrint('[Design] A11y tree opened');
  }
}
