part of 'professional_canvas_toolbar.dart';

// ============================================================================
// 🔝 TOP ROW — Status bar with three fixed zones: Left | Center | Right
//
// Enterprise layout inspired by GoodNotes 6 / Figma:
//   LEFT  (shrink) — back button + note title (always visible)
//   CENTER (expand) — contextual layout/feature chips (may scroll internally)
//   RIGHT (shrink) — undo/redo + collapse + search + settings (always fixed)
//
// The key difference from the old single-scroll-row design:
//   • Undo/Redo are ALWAYS in the right corner — muscle-memory stable
//   • Settings is ALWAYS in the far right — never hidden by scroll
//   • Back + title are ALWAYS on the left — no hunting
// ============================================================================

extension _TopRowBuilder on _ProfessionalCanvasToolbarState {
  Widget _buildTopRow(BuildContext context, bool isDark) {
    final l10n = FlueraLocalizations.of(context);
    return SizedBox(
      height: ToolbarTokens.topRowHeight,
      child: Padding(
        padding: ToolbarTokens.topRowPadding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── LEFT ZONE ─────────────────────────────────────────────────
            _buildLeftZone(context, isDark, l10n),

            // ── CENTER ZONE (expandable) ───────────────────────────────────
            Expanded(child: _buildCenterZone(context, isDark, l10n)),

            // ── RIGHT ZONE ────────────────────────────────────────────────
            _buildRightZone(context, isDark, l10n),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // LEFT ZONE — Back button + note title
  // --------------------------------------------------------------------------

  Widget _buildLeftZone(
    BuildContext context,
    bool isDark,
    FlueraLocalizations l10n,
  ) {
    return _BackButton(isDark: isDark);
  }

  // --------------------------------------------------------------------------
  // CENTER ZONE — Layout chips, sync, contextual feature pills
  // These CAN scroll horizontally — they are contextual and may not all fit.
  // --------------------------------------------------------------------------

  Widget _buildCenterZone(
    BuildContext context,
    bool isDark,
    FlueraLocalizations l10n,
  ) {
    // Check if ANY scrollable content should appear in the center zone.
    // This includes both primary chips AND secondary actions.
    final hasLayoutChips =
        widget.onCanvasLayoutPressed != null ||
        widget.onHSplitLayoutPressed != null ||
        widget.onVSplitLayoutPressed != null ||
        widget.onCanvasOverlayPressed != null ||
        widget.onAdvancedSplitPressed != null ||
        (widget.onSyncToggle != null && widget.isSyncEnabled != null) ||
        (!widget.isImageEditingMode && widget.onTimeTravelPressed != null) ||
        (!widget.isImageEditingMode && widget.onRecallModePressed != null) ||
        (!widget.isImageEditingMode && widget.onGhostMapPressed != null) ||
        (!widget.isImageEditingMode && widget.onFogOfWarPressed != null) ||
        (!widget.isImageEditingMode && widget.onSocraticPressed != null) ||
        (!widget.isImageEditingMode && widget.onCrossZoneBridgesPressed != null) ||
        (!widget.isImageEditingMode && widget.onBranchExplorerPressed != null);

    // Secondary actions also count towards having scrollable content.
    final hasSecondaryActions =
        (!widget.isImageEditingMode && widget.onDualPagePressed != null) ||
        (widget.isCanvasRotated && widget.onResetRotation != null) ||
        widget.onToggleRotationLock != null ||
        (!widget.isImageEditingMode) || // Layers
        widget.onSearchPressed != null;

    // Stroke count status pill: show only when there's truly nothing else.
    if (!hasLayoutChips && !hasSecondaryActions) {
      return _CanvasStatusPill(
        strokeCount: widget.strokeCount,
        isRotated: widget.isCanvasRotated,
        isDark: isDark,
      );
    }

    return _ScrollFadeOverlay(
      fadeWidth: 16.0,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 🗂️ Inline tab switcher chips — no extra row needed
              for (final tab in _availableTabs)
                if (tab != _computedTab) ...[
                  _LayoutChip(
                    icon: tab.icon,
                    label: tab.label,
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      setState(() => _manualTabOverride = tab);
                    },
                    isDark: isDark,
                  ),
                  const SizedBox(width: 4),
                ],

              // Visual separator between tab chips and action chips
              if (_availableTabs.length > 1) ...[
                SizedBox(
                  height: 16,
                  child: VerticalDivider(
                    width: 12,
                    thickness: 1,
                    color: (isDark ? Colors.white : Colors.black)
                        .withValues(alpha: 0.1),
                  ),
                ),
              ],

              // Layout mode chips
              if (widget.onCanvasLayoutPressed != null) ...[
                _LayoutChip(
                  icon: Icons.gesture_rounded,
                  label: l10n.proCanvas_canvasMode,
                  onPressed: widget.onCanvasLayoutPressed!,
                  isDark: isDark,
                ),
                const SizedBox(width: 4),
              ],

              if (widget.onHSplitLayoutPressed != null) ...[
                _LayoutChip(
                  icon: Icons.view_sidebar_rounded,
                  label: l10n.proCanvas_hSplit,
                  onPressed: widget.onHSplitLayoutPressed!,
                  isDark: isDark,
                ),
                const SizedBox(width: 4),
              ],

              if (widget.onVSplitLayoutPressed != null) ...[
                _LayoutChip(
                  icon: Icons.view_agenda_rounded,
                  label: l10n.proCanvas_vSplit,
                  onPressed: widget.onVSplitLayoutPressed!,
                  isDark: isDark,
                ),
                const SizedBox(width: 4),
              ],

              if (widget.onCanvasOverlayPressed != null) ...[
                _LayoutChip(
                  icon: Icons.picture_in_picture_alt_rounded,
                  label: l10n.proCanvas_canvasOverlay,
                  onPressed: widget.onCanvasOverlayPressed!,
                  isDark: isDark,
                ),
                const SizedBox(width: 4),
              ],

              if (widget.onAdvancedSplitPressed != null) ...[
                _LayoutChip(
                  icon: Icons.view_quilt_rounded,
                  label: l10n.proCanvas_splitPro,
                  onPressed: widget.onAdvancedSplitPressed!,
                  isDark: isDark,
                ),
                const SizedBox(width: 4),
              ],

              // Sync chip
              if (widget.onSyncToggle != null &&
                  widget.isSyncEnabled != null) ...[
                _SyncChip(
                  isEnabled: widget.isSyncEnabled!,
                  onPressed: widget.onSyncToggle!,
                  isDark: isDark,
                ),
                const SizedBox(width: 4),
              ],

              if (!widget.isImageEditingMode) ...[
                // Time Travel chip
                if (widget.onTimeTravelPressed != null) ...[
                  ToolbarTimeTravelButton(
                    onPressed: widget.onTimeTravelPressed!,
                    isDark: isDark,
                  ),
                  const SizedBox(width: 4),
                ],

                // Recall Mode chip
                if (widget.onRecallModePressed != null) ...[
                  _RecallChip(
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      widget.onRecallModePressed!();
                    },
                    isDark: isDark,
                    label: l10n.proCanvas_recall,
                    gateType: widget.state.recallGateType ?? 0,
                    isSuggested: widget.state.suggestedStepIndex == 1,
                  ),
                  const SizedBox(width: 4),
                ],

                // Ghost Map chip — 🗺️ AI knowledge gap overlay (step ≥ 4)
                if (widget.onGhostMapPressed != null) ...[
                  _GhostMapChip(
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      widget.onGhostMapPressed!();
                    },
                    isDark: isDark,
                    isActive: widget.state.isGhostMapActive,
                    gapCount: widget.state.ghostMapGapCount,
                    gateType: widget.state.ghostMapGateType ?? 0,
                    isSuggested: widget.state.suggestedStepIndex == 3,
                  ),
                  const SizedBox(width: 4),
                ],

                // Fog of War chip — ⚔️ Exam preparation (step 10)
                if (widget.onFogOfWarPressed != null) ...[
                  _FogOfWarChip(
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      widget.onFogOfWarPressed!();
                    },
                    isDark: isDark,
                    gateType: widget.state.fogOfWarGateType ?? 0,
                    isSuggested: widget.state.suggestedStepIndex == 9,
                  ),
                  const SizedBox(width: 4),
                ],

                // Socratic chip — 🔶 Spatial interrogation (step 3)
                if (widget.onSocraticPressed != null) ...[
                  _SocraticChip(
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      widget.onSocraticPressed!();
                    },
                    isDark: isDark,
                    gateType: widget.state.socraticGateType ?? 0,
                    isSuggested: widget.state.suggestedStepIndex == 2,
                  ),
                  const SizedBox(width: 4),
                ],

                // Cross-Zone Bridges chip — 🌉 Cross-domain discovery (step 9)
                if (widget.onCrossZoneBridgesPressed != null) ...[
                  _CrossZoneBridgeChip(
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      widget.onCrossZoneBridgesPressed!();
                    },
                    isDark: isDark,
                    bridgeCount: widget.state.crossZoneBridgeCount,
                    isLoading: widget.state.isCrossZoneBridgeLoading,
                    gateType: widget.state.crossZoneBridgeGateType ?? 0,
                    isSuggested: widget.state.suggestedStepIndex == 8,
                  ),
                  const SizedBox(width: 4),
                ],

                // Branch Explorer chip
                if (widget.onBranchExplorerPressed != null) ...[
                  _BranchChip(
                    onPressed: widget.onBranchExplorerPressed!,
                    isDark: isDark,
                    activeBranchName: widget.activeBranchName,
                  ),

                  // ☁️ Cloud sync status (shown inline with branch)
                  if (widget.cloudSyncState != null)
                    ValueListenableBuilder<FlueraSyncState>(
                      valueListenable: widget.cloudSyncState!,
                      builder: (context, state, _) {
                        if (state == FlueraSyncState.idle) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: ToolbarCloudSyncIndicator(
                            state: state,
                            progress: 0.0,
                          ),
                        );
                      },
                    ),

                  const SizedBox(width: 4),
                ],
              ],

              // ----------------------------------------------------------------
              // SECONDARY ACTIONS — scrollable, outside isImageEditingMode guard
              // ----------------------------------------------------------------

              // Dual page button
              if (!widget.isImageEditingMode &&
                  widget.onDualPagePressed != null) ...[
                _TopBarIconButton(
                  icon:
                      widget.isDualPageMode
                          ? Icons.view_agenda_rounded
                          : Icons.view_sidebar_rounded,
                  tooltip:
                      widget.isDualPageMode
                          ? l10n.proCanvas_singleView
                          : l10n.proCanvas_dualView,
                  onTap: widget.onDualPagePressed!,
                  isDark: isDark,
                ),
                const SizedBox(width: 2),
              ],

              // Canvas rotation controls (only when relevant)
              if (widget.isCanvasRotated &&
                  widget.onResetRotation != null) ...[
                _TopBarIconButton(
                  icon: Icons.screen_rotation_alt_rounded,
                  tooltip: l10n.proCanvas_resetRotation,
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    widget.onResetRotation!();
                  },
                  isDark: isDark,
                ),
                const SizedBox(width: 2),
              ],

              if (widget.onToggleRotationLock != null) ...[
                _TopBarIconButton(
                  icon:
                      widget.isRotationLocked
                          ? Icons.screen_lock_rotation_rounded
                          : Icons.screen_rotation_rounded,
                  tooltip:
                      widget.isRotationLocked
                          ? l10n.proCanvas_unlockRotation
                          : l10n.proCanvas_lockRotation,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    widget.onToggleRotationLock!();
                  },
                  isDark: isDark,
                ),
                const SizedBox(width: 2),
              ],

              // Layers button (hidden in editing mode)
              if (!widget.isImageEditingMode) ...[
                _TopBarIconButton(
                  icon: Icons.layers_rounded,
                  tooltip: l10n.proCanvas_layers,
                  onTap: widget.onLayersPressed,
                  isDark: isDark,
                ),
                const SizedBox(width: 2),
              ],

              // Handwriting Search — only if provided
              if (widget.onSearchPressed != null) ...[
                _TopBarIconButton(
                  icon:
                      widget.isSearchActive
                          ? Icons.search_off_rounded
                          : Icons.search_rounded,
                  tooltip:
                      widget.isSearchActive
                          ? l10n.proCanvas_closeSearch
                          : l10n.proCanvas_searchHandwriting,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    widget.onSearchPressed!();
                  },
                  isDark: isDark,
                ),
                const SizedBox(width: 2),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // RIGHT ZONE — Rotation, dual page, undo/redo, collapse, search, settings
  // These are ALWAYS visible and NEVER scroll. Order is fixed.
  // --------------------------------------------------------------------------

  Widget _buildRightZone(
    BuildContext context,
    bool isDark,
    FlueraLocalizations l10n,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ⚡ Undo/Redo group — subscribes to undoRedoListenable directly,
        // so only these buttons rebuild on history changes (not the full toolbar)
        _UndoRedoGroup(
          canUndo: widget.canUndo,
          canRedo: widget.canRedo,
          onUndo: widget.onUndo,
          onRedo: widget.onRedo,
          // Scoped rebuild wiring
          undoRedoListenable: widget.undoRedoListenable,
          computeCanUndo: widget.computeCanUndo,
          computeCanRedo: widget.computeCanRedo,
          // Image editor extras
          isImageEditingMode: widget.isImageEditingMode,
          onImageEditorPressed: widget.onImageEditorPressed,
          onExitImageEditMode: widget.onExitImageEditMode,
          isDark: isDark,
          l10n: l10n,
        ),

        const SizedBox(width: 4),

        // Collapse toggle — animated chevron
        _AnimatedCollapseButton(
          isExpanded: _isToolsExpanded,
          isDark: isDark,
          tooltip: _isToolsExpanded ? l10n.proCanvas_hide : l10n.proCanvas_show,
          onTap: () {
            HapticFeedback.lightImpact();
            setState(() {
              _isToolsExpanded = !_isToolsExpanded;
              // Reset sub-panels when collapsing to avoid stale visual state
              if (!_isToolsExpanded) {
                _isShapesExpanded = false;
              }
            });
          },
        ),

        // Settings dropdown — always the far-right anchor
        ToolbarSettingsDropdown(
          isDark: isDark,
          onSettings: widget.onSettings,
          onBrushSettingsPressed: widget.onBrushSettingsPressed,
          onExportPressed: widget.onExportPressed,
          noteTitle: widget.noteTitle,
          onNoteTitleChanged: widget.onNoteTitleChanged,
          onPaperTypePressed: widget.onPaperTypePressed,
          onReadingLevelPressed: widget.onReadingLevelPressed,
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // Quick rename — triggered by tapping the title in the left zone
  // --------------------------------------------------------------------------

  void _showQuickRenameFromTop(BuildContext context) {
    if (widget.onNoteTitleChanged == null) return;
    final l10n = FlueraLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final controller = TextEditingController(text: widget.noteTitle ?? '');
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: cs.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Icon(
                  Icons.drive_file_rename_outline,
                  color: cs.primary,
                  size: 26,
                ),
                const SizedBox(width: 12),
                Text(
                  l10n.proCanvas_renameNote,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            content: TextField(
              controller: controller,
              autofocus: true,
              style: TextStyle(color: cs.onSurface, fontSize: 16),
              decoration: InputDecoration(
                labelText: l10n.proCanvas_noteName,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: cs.primary, width: 2),
                ),
              ),
              onSubmitted: (v) {
                if (v.trim().isNotEmpty) widget.onNoteTitleChanged!(v.trim());
                Navigator.pop(ctx);
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  l10n.cancel,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
              FilledButton(
                onPressed: () {
                  final v = controller.text.trim();
                  if (v.isNotEmpty) widget.onNoteTitleChanged!(v);
                  Navigator.pop(ctx);
                },
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(l10n.save),
              ),
            ],
          ),
    );
  }
}

// =============================================================================
// 🔩 PRIVATE WIDGETS — Top row building blocks
// =============================================================================

/// Generic icon button for the top row right zone.
class _TopBarIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isDark;
  final bool isActive;

  const _TopBarIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.isDark,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor =
        isActive
            ? Theme.of(context).colorScheme.primary
            : (isDark ? Colors.white70 : Colors.black87);
    return Tooltip(
      message: tooltip,
      waitDuration: ToolbarTokens.tooltipDelay,
      child: SizedBox(
        width: 36,
        height: 36,
        child: Material(
          color:
              isActive
                  ? Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.12)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(ToolbarTokens.radius),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(ToolbarTokens.radius),
            child: Icon(icon, size: 22, color: iconColor),
          ),
        ),
      ),
    );
  }
}

/// Undo/Redo group — rounded container with bounce animation.
/// When [undoRedoListenable] is provided, subscribes internally so only this
/// widget rebuilds on history changes — not the whole toolbar.
class _UndoRedoGroup extends StatefulWidget {
  final bool canUndo;
  final bool canRedo;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final bool isImageEditingMode;
  final VoidCallback? onImageEditorPressed;
  final VoidCallback? onExitImageEditMode;
  final bool isDark;
  final FlueraLocalizations l10n;
  // ⚡ Scoped rebuild fields
  final ValueListenable<int>? undoRedoListenable;
  final bool Function()? computeCanUndo;
  final bool Function()? computeCanRedo;

  const _UndoRedoGroup({
    required this.canUndo,
    required this.canRedo,
    required this.onUndo,
    required this.onRedo,
    required this.isImageEditingMode,
    this.onImageEditorPressed,
    this.onExitImageEditMode,
    required this.isDark,
    required this.l10n,
    this.undoRedoListenable,
    this.computeCanUndo,
    this.computeCanRedo,
  });

  @override
  State<_UndoRedoGroup> createState() => _UndoRedoGroupState();
}

class _UndoRedoGroupState extends State<_UndoRedoGroup>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounceCtrl;
  late final Animation<double> _scaleAnim;
  // Which side is bouncing: -1 = undo, 1 = redo
  int _bouncingSide = 0;

  @override
  void initState() {
    super.initState();
    _bounceCtrl = AnimationController(
      vsync: this,
      duration: ToolbarTokens.animBounce,
    );
    _scaleAnim = TweenSequence([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 0.82,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.82,
          end: 1.05,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.05,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 30,
      ),
    ]).animate(_bounceCtrl);
  }

  @override
  void dispose() {
    _bounceCtrl.dispose();
    super.dispose();
  }

  void _triggerBounce(int side) {
    _bouncingSide = side;
    _bounceCtrl.forward(from: 0);
  }

  // Builds the undo/redo row given live canUndo/canRedo values.
  Widget _buildContent(BuildContext context, bool canUndo, bool canRedo) {
    final dividerColor = (widget.isDark ? Colors.white : Colors.black)
        .withValues(alpha: 0.10);

    Widget divider() => Container(width: 1, height: 18, color: dividerColor);

    Widget btn(
      IconData icon,
      String tooltip,
      VoidCallback? onTap,
      bool enabled,
      int side,
    ) {
      final iconWidget = AnimatedBuilder(
        animation: _scaleAnim,
        builder: (_, child) {
          final scale = (_bouncingSide == side) ? _scaleAnim.value : 1.0;
          return Transform.scale(scale: scale, child: child);
        },
        child: Icon(
          icon,
          size: 20,
          color:
              enabled
                  ? (widget.isDark ? Colors.white : Colors.black87)
                  : (widget.isDark ? Colors.white24 : Colors.black26),
        ),
      );
      return Tooltip(
        message: tooltip,
        waitDuration: ToolbarTokens.tooltipDelay,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap:
                  onTap == null
                      ? null
                      : () {
                        HapticFeedback.selectionClick();
                        _triggerBounce(side);
                        onTap();
                      },
              borderRadius: BorderRadius.circular(ToolbarTokens.radius),
              child: Center(child: iconWidget),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: (widget.isDark ? Colors.white : Colors.black).withValues(
          alpha: 0.06,
        ),
        borderRadius: BorderRadius.circular(ToolbarTokens.radius),
        border: Border.all(
          color: (widget.isDark ? Colors.white : Colors.black).withValues(
            alpha: 0.08,
          ),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(
            Icons.undo_rounded,
            widget.l10n.proCanvas_undo,
            canUndo ? widget.onUndo : null,
            canUndo,
            -1,
          ),
          divider(),
          btn(
            Icons.redo_rounded,
            widget.l10n.proCanvas_redo,
            canRedo ? widget.onRedo : null,
            canRedo,
            1,
          ),
          if (widget.isImageEditingMode &&
              widget.onImageEditorPressed != null) ...[
            divider(),
            btn(
              Icons.edit_rounded,
              widget.l10n.proCanvas_advancedEditor,
              widget.onImageEditorPressed,
              true,
              0,
            ),
          ],
          if (widget.isImageEditingMode &&
              widget.onExitImageEditMode != null) ...[
            divider(),
            btn(
              Icons.check_rounded,
              widget.l10n.proCanvas_done,
              widget.onExitImageEditMode,
              true,
              0,
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ⚡ Scoped rebuild: if undoRedoListenable is provided, only this widget
    // rebuilds when history changes — the rest of the toolbar stays unchanged.
    final listenable = widget.undoRedoListenable;
    if (listenable != null &&
        widget.computeCanUndo != null &&
        widget.computeCanRedo != null) {
      return ValueListenableBuilder<int>(
        valueListenable: listenable,
        builder:
            (context, _, __) => _buildContent(
              context,
              widget.computeCanUndo!(),
              widget.computeCanRedo!(),
            ),
      );
    }
    // Fallback: use static canUndo/canRedo from widget props
    return _buildContent(context, widget.canUndo, widget.canRedo);
  }
}

/// Layout mode chip (Canvas, H-Split, V-Split, etc.)
class _LayoutChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool isDark;

  const _LayoutChip({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      waitDuration: ToolbarTokens.tooltipDelay,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(ToolbarTokens.chipRadius),
          child: Container(
            height: ToolbarTokens.chipHeight,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(ToolbarTokens.chipRadius),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: ToolbarTokens.iconSizeSmall,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sync toggle chip
class _SyncChip extends StatelessWidget {
  final bool isEnabled;
  final VoidCallback onPressed;
  final bool isDark;

  const _SyncChip({
    required this.isEnabled,
    required this.onPressed,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        isEnabled
            ? const Color(0xFF16A34A) // green-600
            : (isDark ? Colors.white38 : Colors.black38);
    return Tooltip(
      message: isEnabled ? 'Disable Sync' : 'Enable Sync',
      waitDuration: ToolbarTokens.tooltipDelay,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(ToolbarTokens.chipRadius),
          child: Container(
            height: ToolbarTokens.chipHeight,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(ToolbarTokens.chipRadius),
              border: Border.all(
                color: color.withValues(alpha: 0.30),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isEnabled ? Icons.sync_rounded : Icons.sync_disabled_rounded,
                  size: ToolbarTokens.iconSizeSmall,
                  color: color,
                ),
                const SizedBox(width: 4),
                Text(
                  'Sync',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// 🚦 A15: Shared gate decoration helper for cognitive tool chips.
// =============================================================================

/// Builds a [BoxDecoration] for cognitive tool chips that is gate-aware.
/// - **Open**: Standard gradient + colored border
/// - **Hard**: Flat grey background, subdued border
/// - **Suggested**: Golden glow border + shadow
BoxDecoration _gateDecoration({
  required Color baseColor,
  required bool isHard,
  required bool isSuggested,
  required bool isDark,
  bool isActive = false,
}) {
  final borderColor = isSuggested
      ? const Color(0xFFFFD54F).withValues(alpha: 0.6)
      : (isHard
          ? (isDark ? Colors.white12 : Colors.black12)
          : baseColor.withValues(alpha: isActive ? 0.6 : 0.25));

  return BoxDecoration(
    gradient: isHard
        ? null
        : LinearGradient(
            colors: isActive
                ? [baseColor.withValues(alpha: 0.35), baseColor.withValues(alpha: 0.20)]
                : [baseColor.withValues(alpha: 0.14), baseColor.withValues(alpha: 0.06)],
          ),
    color: isHard
        ? (isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.04))
        : null,
    borderRadius: BorderRadius.circular(ToolbarTokens.chipRadius),
    border: Border.all(
      color: borderColor,
      width: isSuggested ? 1.5 : (isActive ? 1.5 : 1),
    ),
    boxShadow: isSuggested
        ? [BoxShadow(color: const Color(0xFFFFD54F).withValues(alpha: 0.2), blurRadius: 6)]
        : (isActive
            ? [BoxShadow(color: baseColor.withValues(alpha: 0.25), blurRadius: 8)]
            : null),
  );
}

/// Recall Mode chip — gate-aware (A15)
class _RecallChip extends StatelessWidget {
  final VoidCallback onPressed;
  final bool isDark;
  final String label;
  final int gateType;
  final bool isSuggested;

  const _RecallChip({
    required this.onPressed,
    required this.isDark,
    required this.label,
    this.gateType = 0,
    this.isSuggested = false,
  });

  @override
  Widget build(BuildContext context) {
    const baseColor = ToolbarTokens.recallActive;
    final isHard = gateType == 2;
    final isSoft = gateType == 1;
    final effectiveColor = isHard
        ? (isDark ? Colors.white24 : Colors.black26)
        : (isDark ? const Color(0xFF9D92FF) : const Color(0xFF6C63FF));

    return Tooltip(
      message: isHard ? 'Recall — non disponibile' : 'Recall Mode — Passo 2',
      waitDuration: ToolbarTokens.tooltipDelay,
      child: Opacity(
        opacity: isSoft ? 0.5 : 1.0,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(ToolbarTokens.chipRadius),
            child: Container(
              height: ToolbarTokens.chipHeight,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: _gateDecoration(
                baseColor: baseColor,
                isHard: isHard,
                isSuggested: isSuggested,
                isDark: isDark,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isHard ? Icons.lock_rounded : Icons.psychology_rounded,
                    size: isHard ? 12 : ToolbarTokens.iconSizeSmall,
                    color: effectiveColor,
                  ),
                  const SizedBox(width: 4),
                  Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: effectiveColor)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 🗺️ Ghost Map chip — AI knowledge gap analysis
class _GhostMapChip extends StatelessWidget {
  final VoidCallback onPressed;
  final bool isDark;
  final bool isActive;
  final int gapCount;
  final int gateType;
  final bool isSuggested;

  const _GhostMapChip({
    required this.onPressed,
    required this.isDark,
    this.isActive = false,
    this.gapCount = 0,
    this.gateType = 0,
    this.isSuggested = false,
  });

  @override
  Widget build(BuildContext context) {
    final isHard = gateType == 2;
    final isSoft = gateType == 1;
    final baseColor = isDark ? const Color(0xFF4DD0E1) : const Color(0xFF00ACC1);
    final activeColor = isDark ? const Color(0xFF00BCD4) : const Color(0xFF0097A7);
    final color = isHard
        ? (isDark ? Colors.white24 : Colors.black26)
        : (isActive ? activeColor : baseColor);

    return Tooltip(
      message: isHard
          ? 'Ghost Map — non disponibile'
          : (isActive ? 'Chiudi Ghost Map 🗺️' : 'Ghost Map — Passo 4 🗺️'),
      waitDuration: ToolbarTokens.tooltipDelay,
      child: Opacity(
        opacity: isSoft ? 0.5 : 1.0,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(ToolbarTokens.chipRadius),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              height: ToolbarTokens.chipHeight,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: _gateDecoration(
                baseColor: isHard ? baseColor : (isActive ? activeColor : baseColor),
                isHard: isHard,
                isSuggested: isSuggested,
                isDark: isDark,
                isActive: isActive,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isHard
                        ? Icons.lock_rounded
                        : (isActive ? Icons.close_rounded : Icons.map_rounded),
                    size: isHard ? 12 : ToolbarTokens.iconSizeSmall,
                    color: color,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Ghost Map',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                      color: color,
                    ),
                  ),
                  // 🗺️ Count badge when gaps found
                  if (gapCount > 0 && isActive) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE65100).withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$gapCount',
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ⚔️ Fog of War chip — gate-aware (A15)
class _FogOfWarChip extends StatelessWidget {
  final VoidCallback onPressed;
  final bool isDark;
  final int gateType;
  final bool isSuggested;

  const _FogOfWarChip({
    required this.onPressed,
    required this.isDark,
    this.gateType = 0,
    this.isSuggested = false,
  });

  @override
  Widget build(BuildContext context) {
    final isHard = gateType == 2;
    final isSoft = gateType == 1;
    final baseColor = isDark ? const Color(0xFFB0BEC5) : const Color(0xFF546E7A);
    final color = isHard ? (isDark ? Colors.white24 : Colors.black26) : baseColor;

    return Tooltip(
      message: isHard ? 'Fog of War — non disponibile' : 'Fog of War — Passo 10 ⚔️',
      waitDuration: ToolbarTokens.tooltipDelay,
      child: Opacity(
        opacity: isSoft ? 0.5 : 1.0,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(ToolbarTokens.chipRadius),
            child: Container(
              height: ToolbarTokens.chipHeight,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: _gateDecoration(
                baseColor: baseColor,
                isHard: isHard,
                isSuggested: isSuggested,
                isDark: isDark,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isHard ? Icons.lock_rounded : Icons.shield_rounded,
                    size: isHard ? 12 : ToolbarTokens.iconSizeSmall,
                    color: color,
                  ),
                  const SizedBox(width: 4),
                  Text('Fog of War', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 🔶 Socratic chip — gate-aware (A15)
class _SocraticChip extends StatelessWidget {
  final VoidCallback onPressed;
  final bool isDark;
  final int gateType;
  final bool isSuggested;

  const _SocraticChip({
    required this.onPressed,
    required this.isDark,
    this.gateType = 0,
    this.isSuggested = false,
  });

  @override
  Widget build(BuildContext context) {
    final isHard = gateType == 2;
    final isSoft = gateType == 1;
    final baseColor = isDark ? const Color(0xFFFFB300) : const Color(0xFFF57C00);
    final color = isHard ? (isDark ? Colors.white24 : Colors.black26) : baseColor;

    return Tooltip(
      message: isHard ? 'Socratica — non disponibile' : 'Interrogazione Socratica — Passo 3 🔶',
      waitDuration: ToolbarTokens.tooltipDelay,
      child: Opacity(
        opacity: isSoft ? 0.5 : 1.0,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(ToolbarTokens.chipRadius),
            child: Container(
              height: ToolbarTokens.chipHeight,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: _gateDecoration(
                baseColor: baseColor,
                isHard: isHard,
                isSuggested: isSuggested,
                isDark: isDark,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isHard ? Icons.lock_rounded : Icons.quiz_rounded,
                    size: isHard ? 12 : ToolbarTokens.iconSizeSmall,
                    color: color,
                  ),
                  const SizedBox(width: 4),
                  Text('Socratica', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 🌉 Cross-Zone Bridge chip — gate-aware (A15), with bridge count badge
class _CrossZoneBridgeChip extends StatelessWidget {
  final VoidCallback onPressed;
  final bool isDark;
  final int bridgeCount;
  final bool isLoading;
  final int gateType;
  final bool isSuggested;

  const _CrossZoneBridgeChip({
    required this.onPressed,
    required this.isDark,
    this.bridgeCount = 0,
    this.isLoading = false,
    this.gateType = 0,
    this.isSuggested = false,
  });

  @override
  Widget build(BuildContext context) {
    final isHard = gateType == 2;
    final isSoft = gateType == 1;
    // Golden color for cross-domain bridges
    final baseColor = isDark ? const Color(0xFFFFD54F) : const Color(0xFFF9A825);
    final color = isHard ? (isDark ? Colors.white24 : Colors.black26) : baseColor;

    return Tooltip(
      message: isHard
          ? 'Ponti Cross-Dominio — non disponibile'
          : 'Ponti Cross-Dominio — Passo 9 🌉${bridgeCount > 0 ? ' ($bridgeCount)' : ''}',
      waitDuration: ToolbarTokens.tooltipDelay,
      child: Opacity(
        opacity: isSoft ? 0.5 : 1.0,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(ToolbarTokens.chipRadius),
            child: Container(
              height: ToolbarTokens.chipHeight,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: _gateDecoration(
                baseColor: baseColor,
                isHard: isHard,
                isSuggested: isSuggested,
                isDark: isDark,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isLoading)
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        valueColor: AlwaysStoppedAnimation(color),
                      ),
                    )
                  else
                    Icon(
                      isHard ? Icons.lock_rounded : Icons.hub_rounded,
                      size: isHard ? 12 : ToolbarTokens.iconSizeSmall,
                      color: color,
                    ),
                  const SizedBox(width: 4),
                  Text(
                    'Ponti',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  if (bridgeCount > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: baseColor.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$bridgeCount',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Branch Explorer chip — shows active branch name when one is set
class _BranchChip extends StatelessWidget {
  final VoidCallback onPressed;
  final bool isDark;
  final String? activeBranchName;

  const _BranchChip({
    required this.onPressed,
    required this.isDark,
    this.activeBranchName,
  });

  @override
  Widget build(BuildContext context) {
    final hasActiveBranch = activeBranchName != null;
    const activeColor = ToolbarTokens.branchActive;
    final inactiveColor = isDark ? Colors.white54 : Colors.black45;
    final color = hasActiveBranch ? activeColor : inactiveColor;

    return Tooltip(
      message:
          hasActiveBranch
              ? 'Branch: $activeBranchName — tap to explore'
              : 'Branch Explorer',
      waitDuration: ToolbarTokens.tooltipDelay,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(ToolbarTokens.chipRadius),
          child: Container(
            height: ToolbarTokens.chipHeight,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color:
                  hasActiveBranch
                      ? activeColor.withValues(alpha: 0.14)
                      : (isDark ? Colors.white : Colors.black).withValues(
                        alpha: 0.05,
                      ),
              borderRadius: BorderRadius.circular(ToolbarTokens.chipRadius),
              border:
                  hasActiveBranch
                      ? Border.all(
                        color: activeColor.withValues(alpha: 0.30),
                        width: 1,
                      )
                      : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  hasActiveBranch
                      ? Icons.alt_route_rounded
                      : Icons.account_tree_rounded,
                  size: ToolbarTokens.iconSizeSmall,
                  color: color,
                ),
                if (hasActiveBranch) ...[
                  const SizedBox(width: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 80),
                    child: Text(
                      activeBranchName!,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: activeColor,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// 🆕 NEW ENTERPRISE WIDGETS
// =============================================================================

/// Premium back/close button — pill with label and press-scale animation.
class _BackButton extends StatefulWidget {
  final bool isDark;
  const _BackButton({required this.isDark});

  @override
  State<_BackButton> createState() => _BackButtonState();
}

class _BackButtonState extends State<_BackButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: ToolbarTokens.animFast);
    _scale = Tween(
      begin: 1.0,
      end: 0.88,
    ).animate(CurvedAnimation(parent: _ctrl, curve: ToolbarTokens.curveActive));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isDark ? Colors.white70 : Colors.black54;
    return AnimatedBuilder(
      animation: _scale,
      builder:
          (ctx, child) => Transform.scale(scale: _scale.value, child: child),
      child: GestureDetector(
        onTapDown: (_) => _ctrl.forward(),
        onTapUp: (_) {
          _ctrl.reverse();
          Navigator.maybePop(context);
        },
        onTapCancel: () => _ctrl.reverse(),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: (widget.isDark ? Colors.white : Colors.black).withValues(
              alpha: 0.06,
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: (widget.isDark ? Colors.white : Colors.black).withValues(
                alpha: 0.09,
              ),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 13,
                color: textColor,
              ),
              const SizedBox(width: 4),
              Text(
                'Back',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Status pill — animated stroke count + rotation indicator in the center zone.
class _CanvasStatusPill extends StatelessWidget {
  final int strokeCount;
  final bool isRotated;
  final bool isDark;

  const _CanvasStatusPill({
    required this.strokeCount,
    required this.isRotated,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    if (strokeCount == 0 && !isRotated) return const SizedBox.shrink();

    final textColor = (isDark ? Colors.white : Colors.black).withValues(
      alpha: 0.45,
    );
    final bg = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05);

    return Center(
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (strokeCount > 0) ...[
              Icon(Icons.edit_outlined, size: 11, color: textColor),
              const SizedBox(width: 4),
              AnimatedSwitcher(
                duration: ToolbarTokens.animFast,
                transitionBuilder:
                    (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, -0.4),
                          end: Offset.zero,
                        ).animate(
                          CurvedAnimation(
                            parent: anim,
                            curve: ToolbarTokens.curveActive,
                          ),
                        ),
                        child: child,
                      ),
                    ),
                child: Text(
                  '$strokeCount',
                  key: ValueKey(strokeCount),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
            ],
            if (isRotated && strokeCount > 0) const SizedBox(width: 6),
            if (isRotated)
              Icon(
                Icons.screen_rotation_alt_rounded,
                size: 11,
                color: textColor,
              ),
          ],
        ),
      ),
    );
  }
}

/// Collapse toggle button with AnimatedRotation on the chevron icon.
class _AnimatedCollapseButton extends StatelessWidget {
  final bool isExpanded;
  final bool isDark;
  final String tooltip;
  final VoidCallback onTap;

  const _AnimatedCollapseButton({
    required this.isExpanded,
    required this.isDark,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: ToolbarTokens.tooltipDelay,
      child: SizedBox(
        width: 36,
        height: 36,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(ToolbarTokens.radius),
            child: Center(
              child: AnimatedRotation(
                turns: isExpanded ? 0.0 : 0.5,
                duration: ToolbarTokens.animNormal,
                curve: ToolbarTokens.curveCollapse,
                child: Icon(
                  Icons.expand_less_rounded,
                  size: 22,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
