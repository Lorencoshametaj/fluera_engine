part of 'professional_canvas_toolbar.dart';

// ============================================================================
// 🔝 TOP ROW — Status bar, layout buttons, quick actions
// Extracted from professional_canvas_toolbar.dart
// ============================================================================

extension _TopRowBuilder on _ProfessionalCanvasToolbarState {
  Widget _buildTopRow(BuildContext context, bool isDark) {
    final l10n = FlueraLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.only(left: 0, right: 8, top: 8, bottom: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Back button
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, size: 22),
              onPressed: () => Navigator.pop(context),
              tooltip: l10n.close,
              color: isDark ? Colors.white70 : Colors.black87,
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            ),

            const SizedBox(width: 8),

            // 📐 LAYOUT BUTTONS - The buttons requested by the user
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Canvas button
                if (widget.onCanvasLayoutPressed != null)
                  ToolbarLayoutButton(
                    icon: Icons.gesture_rounded,
                    label: FlueraLocalizations.of(context).proCanvas_canvasMode,
                    onPressed: widget.onCanvasLayoutPressed!,
                    isDark: isDark,
                    color: Colors.grey,
                  ),
                if (widget.onCanvasLayoutPressed != null)
                  const SizedBox(width: 4),

                // H-Split button
                if (widget.onHSplitLayoutPressed != null)
                  ToolbarLayoutButton(
                    icon: Icons.view_sidebar_rounded,
                    label: FlueraLocalizations.of(context).proCanvas_hSplit,
                    onPressed: widget.onHSplitLayoutPressed!,
                    isDark: isDark,
                    color: Colors.blue,
                  ),
                if (widget.onHSplitLayoutPressed != null)
                  const SizedBox(width: 4),

                // V-Split button
                if (widget.onVSplitLayoutPressed != null)
                  ToolbarLayoutButton(
                    icon: Icons.view_agenda_rounded,
                    label: FlueraLocalizations.of(context).proCanvas_vSplit,
                    onPressed: widget.onVSplitLayoutPressed!,
                    isDark: isDark,
                    color: Colors.indigo,
                  ),
                if (widget.onVSplitLayoutPressed != null)
                  const SizedBox(width: 4),

                // Canvas Overlay button
                if (widget.onCanvasOverlayPressed != null)
                  ToolbarLayoutButton(
                    icon: Icons.picture_in_picture_alt_rounded,
                    label: 'Canvas Overlay',
                    onPressed: widget.onCanvasOverlayPressed!,
                    isDark: isDark,
                    color: Colors.teal,
                  ),
                if (widget.onCanvasOverlayPressed != null)
                  const SizedBox(width: 4),

                // Advanced Split button
                if (widget.onAdvancedSplitPressed != null)
                  ToolbarLayoutButton(
                    icon: Icons.view_quilt_rounded,
                    label: FlueraLocalizations.of(context).proCanvas_splitPro,
                    onPressed: widget.onAdvancedSplitPressed!,
                    isDark: isDark,
                    color: Colors.deepPurple,
                  ),
                if (widget.onAdvancedSplitPressed != null)
                  const SizedBox(width: 8),

                // 🔄 Sync button - only if callback fornito
                if (widget.onSyncToggle != null && widget.isSyncEnabled != null)
                  ToolbarSyncButton(
                    onPressed: widget.onSyncToggle!,
                    isEnabled: widget.isSyncEnabled!,
                    isDark: isDark,
                  ),
                if (widget.onSyncToggle != null && widget.isSyncEnabled != null)
                  const SizedBox(width: 8),
              ],
            ),

            // 🎯 QUICK ACTIONS - Solo essenziali
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Layers button (hidden in editing mode)
                if (!widget.isImageEditingMode) ...[
                  ToolbarCompactActionButton(
                    icon: Icons.layers_rounded,
                    onPressed: widget.onLayersPressed,
                    tooltip: l10n.proCanvas_layers,
                    isDark: isDark,
                    isEnabled: true,
                  ),
                  const SizedBox(width: 4),
                  // ⏱️ Time Travel button (with animation MD3)
                  if (widget.onTimeTravelPressed != null) ...[
                    ToolbarTimeTravelButton(
                      onPressed: widget.onTimeTravelPressed!,
                      isDark: isDark,
                    ),
                    const SizedBox(width: 4),
                  ],
                  // 🌿 Branch Explorer / Active branch indicator
                  if (widget.onBranchExplorerPressed != null) ...[
                    GestureDetector(
                      onTap: widget.onBranchExplorerPressed,
                      child: Container(
                        height: 30,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color:
                              widget.activeBranchName != null
                                  ? const Color(
                                    0xFF7C4DFF,
                                  ).withValues(alpha: 0.15)
                                  : (isDark ? Colors.white : Colors.black)
                                      .withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                          border:
                              widget.activeBranchName != null
                                  ? Border.all(
                                    color: const Color(
                                      0xFF7C4DFF,
                                    ).withValues(alpha: 0.3),
                                  )
                                  : null,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              widget.activeBranchName != null
                                  ? Icons.alt_route_rounded
                                  : Icons.account_tree_rounded,
                              size: 14,
                              color:
                                  widget.activeBranchName != null
                                      ? const Color(0xFF7C4DFF)
                                      : (isDark
                                          ? Colors.white60
                                          : Colors.black45),
                            ),
                            if (widget.activeBranchName != null) ...[
                              const SizedBox(width: 4),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 80),
                                child: Text(
                                  widget.activeBranchName!,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF7C4DFF),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    // ☁️ Cloud sync status indicator
                    if (widget.cloudSyncState != null)
                      ValueListenableBuilder<FlueraSyncState>(
                        valueListenable: widget.cloudSyncState!,
                        builder: (context, state, _) {
                          if (state == FlueraSyncState.idle) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: ToolbarCloudSyncIndicator(
                              state: state,
                              progress: 0.0,
                            ),
                          );
                        },
                      ),
                    const SizedBox(width: 4),
                  ],
                  // 📋 MultiView button with theng press (only if callback fornito)
                  if (widget.onMultiViewPressed != null) ...[
                    ToolbarMultiViewCompactButton(
                      onPressed: widget.onMultiViewPressed!,
                      onModeSelected: widget.onMultiViewModeSelected,
                      isDark: isDark,
                    ),
                    const SizedBox(width: 4),
                  ],
                  // 📖 Dual page button (only if callback fornito)
                  if (widget.onDualPagePressed != null) ...[
                    ToolbarCompactActionButton(
                      icon:
                          widget.isDualPageMode
                              ? Icons.view_agenda_rounded
                              : Icons.view_sidebar_rounded,
                      onPressed: widget.onDualPagePressed,
                      tooltip:
                          widget.isDualPageMode
                              ? l10n.proCanvas_singleView
                              : l10n.proCanvas_dualView,
                      isDark: isDark,
                      isEnabled: true,
                    ),
                    const SizedBox(width: 4),
                  ],
                ],

                // 🌀 Reset Rotation button — only visible when canvas is rotated
                if (widget.isCanvasRotated &&
                    widget.onResetRotation != null) ...[
                  ToolbarCompactActionButton(
                    icon: Icons.screen_rotation_alt_rounded,
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      widget.onResetRotation!();
                    },
                    tooltip: 'Reset Rotation',
                    isDark: isDark,
                    isEnabled: true,
                  ),
                  const SizedBox(width: 4),
                ],

                // 🌀 Lock Rotation button — always visible
                if (widget.onToggleRotationLock != null) ...[
                  ToolbarCompactActionButton(
                    icon:
                        widget.isRotationLocked
                            ? Icons.screen_lock_rotation_rounded
                            : Icons.screen_rotation_rounded,
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      widget.onToggleRotationLock!();
                    },
                    tooltip:
                        widget.isRotationLocked
                            ? 'Unlock Rotation'
                            : 'Lock Rotation',
                    isDark: isDark,
                    isEnabled: true,
                  ),
                  const SizedBox(width: 4),
                ],

                // Undo/Redo group (+ Image Editor in editing mode)
                Container(
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.white : Colors.black).withValues(
                      alpha: 0.05,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ToolbarCompactActionButton(
                        icon: Icons.undo_rounded,
                        onPressed: widget.canUndo ? widget.onUndo : null,
                        tooltip: l10n.proCanvas_undo,
                        isDark: isDark,
                        isEnabled: widget.canUndo,
                      ),
                      Container(
                        width: 1,
                        height: 18,
                        color: (isDark ? Colors.white : Colors.black)
                            .withValues(alpha: 0.1),
                      ),
                      ToolbarCompactActionButton(
                        icon: Icons.redo_rounded,
                        onPressed: widget.canRedo ? widget.onRedo : null,
                        tooltip: l10n.proCanvas_redo,
                        isDark: isDark,
                        isEnabled: widget.canRedo,
                      ),
                      // 🎨 Pulsante Editor Immagini (only then editing mode)
                      if (widget.isImageEditingMode &&
                          widget.onImageEditorPressed != null) ...[
                        Container(
                          width: 1,
                          height: 18,
                          color: (isDark ? Colors.white : Colors.black)
                              .withValues(alpha: 0.1),
                        ),
                        ToolbarCompactActionButton(
                          icon: Icons.edit_rounded,
                          onPressed: widget.onImageEditorPressed,
                          tooltip: l10n.proCanvas_advancedEditor,
                          isDark: isDark,
                          isEnabled: true,
                        ),
                      ],
                      // ✅ Pulsante "Fatto" per uscire dall'edit mode
                      if (widget.isImageEditingMode &&
                          widget.onExitImageEditMode != null) ...[
                        Container(
                          width: 1,
                          height: 18,
                          color: (isDark ? Colors.white : Colors.black)
                              .withValues(alpha: 0.1),
                        ),
                        ToolbarCompactActionButton(
                          icon: Icons.check_rounded,
                          onPressed: widget.onExitImageEditMode,
                          tooltip: l10n.proCanvas_done,
                          isDark: isDark,
                          isEnabled: true,
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(width: 4),

                // Toggle tools
                ToolbarCompactActionButton(
                  icon:
                      _isToolsExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    setState(() => _isToolsExpanded = !_isToolsExpanded);
                  },
                  tooltip:
                      _isToolsExpanded
                          ? l10n.proCanvas_hide
                          : l10n.proCanvas_show,
                  isDark: isDark,
                  isEnabled: true,
                ),

                const SizedBox(width: 4),

                // Settings Dropdown
                ToolbarSettingsDropdown(
                  isDark: isDark,
                  onSettings: widget.onSettings,
                  onBrushSettingsPressed:
                      widget.onBrushSettingsPressed, // 🎛️ Brush settings
                  onExportPressed: widget.onExportPressed, // 📤 Export canvas
                  noteTitle: widget.noteTitle, // 🆕 Pass noteTitle
                  onNoteTitleChanged:
                      widget.onNoteTitleChanged, // 🆕 Pass callback

                  onPaperTypePressed:
                      widget.onPaperTypePressed, // 📄 Paper type
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
