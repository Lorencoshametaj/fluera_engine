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
  /// True when viewport is narrower than `ToolbarTokens.smallScreenThreshold`
  /// (500dp). Round 5.5 (2026-05-16): drives the layout switch in
  /// `_buildTopRow` — phones use `_buildSmallTopRow` (single horizontal
  /// scrollable across the whole row), tablets/desktops use the 3-zone
  /// anchored layout.
  bool _isSmallScreen(BuildContext context) =>
      MediaQuery.sizeOf(context).width < ToolbarTokens.smallScreenThreshold;

  /// Toggle + haptic + sub-panel reset for the chevron collapse button.
  /// Used by both the small-screen single-scroll layout and the 3-zone
  /// right-zone inline button.
  void _toggleToolsExpanded() {
    HapticFeedback.lightImpact();
    setState(() {
      _isToolsExpanded = !_isToolsExpanded;
      if (!_isToolsExpanded) {
        _isShapesExpanded = false;
      }
    });
  }

  Widget _buildTopRow(BuildContext context, bool isDark) {
    final l10n = FlueraLocalizations.of(context)!;
    // On small screens (<500dp) the top row uses a single horizontal
    // scrollable that contains EVERYTHING in sequence (Back, UndoRedo,
    // chips, Bookmark, Collapse, Badge, Settings). Mirrors the tools-row
    // pattern that reliably scrolls on every device.
    //
    // The 3-zone "anchor pillars" design only works on tablet+ — the
    // narrow center-zone SingleChildScrollView on phones keeps losing
    // the horizontal-drag gesture arena to the canvas pan handler
    // beneath (Round 5.1–5.4 attempted density/ShaderMask/dragDevices/
    // Listener fixes, none worked reliably). The Stack-with-pinned-
    // anchors attempt (Round 5.6–5.8) was theoretically nicer but
    // broke scroll again on phone. Single-scroll is the validated
    // working design.
    if (_isSmallScreen(context)) {
      return _buildSmallTopRow(context, isDark, l10n);
    }
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
            Flexible(
              fit: FlexFit.tight,
              child: _buildCenterZone(context, isDark, l10n),
            ),

            // ── RIGHT ZONE ────────────────────────────────────────────────
            _buildRightZone(context, isDark, l10n),
          ],
        ),
      ),
    );
  }

  /// Round 5.5 (2026-05-16, user-validated): the entire top row is a
  /// SINGLE horizontal scrollable containing everything in sequence —
  /// Back → UndoRedo → ✨Features → tab chips → cognitive chips →
  /// Bookmark → Collapse → CreditsBadge → Settings. Same pattern as the
  /// tools-row (second row) which already worked reliably.
  ///
  /// Trade-off accepted: Back/Settings lose their "always-in-corner"
  /// muscle-memory anchor (they scroll off-screen). Attempted Stack-with-
  /// pinned-anchors (Round 5.6–5.8) but it broke scroll on phone again —
  /// reverted to this validated layout.
  Widget _buildSmallTopRow(
    BuildContext context,
    bool isDark,
    FlueraLocalizations l10n,
  ) {
    return SizedBox(
      height: ToolbarTokens.topRowHeight,
      child: ScrollConfiguration(
        behavior: const _ToolbarScrollBehavior(),
        child: Listener(
          behavior: HitTestBehavior.opaque,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: ToolbarTokens.topRowPadding,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _BackButton(isDark: isDark),
                const SizedBox(width: 8),
                _UndoRedoGroup(
                  canUndo: widget.canUndo,
                  canRedo: widget.canRedo,
                  onUndo: widget.onUndo,
                  onRedo: widget.onRedo,
                  undoRedoListenable: widget.undoRedoListenable,
                  computeCanUndo: widget.computeCanUndo,
                  computeCanRedo: widget.computeCanRedo,
                  isImageEditingMode: widget.isImageEditingMode,
                  onImageEditorPressed: widget.onImageEditorPressed,
                  onExitImageEditMode: widget.onExitImageEditMode,
                  isDark: isDark,
                  l10n: l10n,
                ),
                const SizedBox(width: 6),
                ..._buildCenterChips(context, isDark, l10n),
                if (widget.onBookmarksPressed != null &&
                    widget.bookmarkCount > 0) ...[
                  const SizedBox(width: 4),
                  _LayoutChip(
                    icon: Icons.bookmark_rounded,
                    label: '${l10n.hub_bookmarks} (${widget.bookmarkCount})',
                    onPressed: widget.onBookmarksPressed!,
                    isDark: isDark,
                  ),
                ],
                const SizedBox(width: 4),
                _AnimatedCollapseButton(
                  isExpanded: _isToolsExpanded,
                  isDark: isDark,
                  tooltip: _isToolsExpanded
                      ? l10n.proCanvas_hide
                      : l10n.proCanvas_show,
                  onTap: _toggleToolsExpanded,
                ),
                if (widget.trailingBadge != null) ...[
                  const SizedBox(width: 4),
                  widget.trailingBadge!,
                  const SizedBox(width: 4),
                ],
                ToolbarSettingsDropdown(
                  onBrushSettingsPressed: widget.onBrushSettingsPressed,
                  onExportPressed: widget.onExportPressed,
                  noteTitle: widget.noteTitle,
                  onNoteTitleChanged: widget.onNoteTitleChanged,
                  onPaperTypePressed: widget.onPaperTypePressed,
                  onReadingLevelPressed: widget.onReadingLevelPressed,
                  onWheelModeToggle: widget.onWheelModeToggle,
                  isWheelModeActive: widget.isWheelModeActive,
                  devModeEnabled: widget.devModeEnabled,
                  currentPaperLabel: widget.currentPaperLabel,
                  activeFiltersCount: widget.activeFiltersCount,
                  readingLevelSeen: widget.readingLevelSeen,
                  onReadingLevelMarkSeen: widget.onReadingLevelMarkSeen,
                ),
              ],
            ),
          ),
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
    //
    // Cognitive features moved into the `_FeaturesDiscoveryChip` sheet
    // (2026-05-16): Time Travel, Ghost Map, Fog of War, Socratic, Exam,
    // Cross-Zone Bridges no longer surface as standalone chips here.
    // Recall, Checkpoint, Branch Explorer stay inline because the sheet
    // doesn't host them (recall is a quick toggle, checkpoint/branch are
    // version-control rather than cognitive).
    final hasLayoutChips =
        widget.onFeaturesDiscoveryPressed != null ||
        widget.onCanvasLayoutPressed != null ||
        widget.onHSplitLayoutPressed != null ||
        widget.onVSplitLayoutPressed != null ||
        widget.onCanvasOverlayPressed != null ||
        widget.onAdvancedSplitPressed != null ||
        widget.onWheelModeToggle != null ||
        (widget.onSyncToggle != null && widget.isSyncEnabled != null) ||
        (!widget.isImageEditingMode && widget.onRecallModePressed != null) ||
        (!widget.isImageEditingMode && widget.onCheckpointsPressed != null) ||
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

    // Tablet/desktop 3-zone layout reaches this. `ScrollConfiguration` +
    // explicit `dragDevices` + opaque `Listener` + `AlwaysScrollable`
    // parent physics — kept defensively so the center-zone scrollable
    // never silently loses to a sibling gesture handler.
    return ScrollConfiguration(
      behavior: const _ToolbarScrollBehavior(),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: _buildCenterChips(context, isDark, l10n),
            ),
          ),
        ),
      ),
    );
  }

  /// Center-zone chip list (Features ✨ + tab switcher + layout/cognitive
  /// chips + secondaries). Extracted so both the 3-zone tablet layout and
  /// the single-scroll phone layout (Round 5.5) can consume it.
  List<Widget> _buildCenterChips(
    BuildContext context,
    bool isDark,
    FlueraLocalizations l10n,
  ) {
    return [
              // ✨ Features discovery chip — Round 4 (2026-05-15).
              // On-demand discovery sheet for cognitive features (Ghost Map,
              // Socratic, Exam, etc.). Always-first in center zone so users
              // that bypass session-paced coachmarks still find them.
              if (widget.onFeaturesDiscoveryPressed != null) ...[
                _FeaturesDiscoveryChip(
                  onPressed: widget.onFeaturesDiscoveryPressed!,
                  isDark: isDark,
                  label: FlueraLocalizations.of(context)!
                      .featuresSheet_chipLabel,
                ),
                const SizedBox(width: 4),
              ],
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
                // 🧠 Cognitive feature chips (Time Travel, Ghost Map,
                // Fog of War, Socratic, Exam Session, Cross-Zone
                // Bridges) consolidated into the `_FeaturesDiscoveryChip`
                // sheet on 2026-05-16. The callbacks live on the host
                // (see `onShowCognitiveFeaturesSheet` actions map in
                // _ui_toolbar.dart) — the inline pills are redundant.
                //
                // What stays inline below:
                //   • Recall — quick toggle, not in the sheet
                //   • Checkpoint — version control, not cognitive
                //   • Branch Explorer + cloud sync indicator — same

                // Recall Mode chip
                if (widget.onRecallModePressed != null) ...[
                  _RecallChip(
                    onPressed: () {
                      if (!_chipTapDebounce()) return;
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

                // 📍 Checkpoint chip — Free+ entry point (no Pro gate),
                // independent from Time Travel. Standalone so Free users can
                // reach Checkpoint without Pro Time Travel access.
                if (widget.onCheckpointsPressed != null) ...[
                  _CheckpointChip(
                    onPressed: widget.onCheckpointsPressed!,
                    isDark: isDark,
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
              // SECONDARY ACTIONS — chip-with-label pattern (2026-05-16),
              // matches Time Travel / Split Pro / ✨ Funzioni so the user
              // can read each control's purpose without hovering.
              // ----------------------------------------------------------------

              // Dual page toggle
              if (!widget.isImageEditingMode &&
                  widget.onDualPagePressed != null) ...[
                _LayoutChip(
                  icon: widget.isDualPageMode
                      ? Icons.view_agenda_rounded
                      : Icons.view_sidebar_rounded,
                  label: widget.isDualPageMode
                      ? l10n.proCanvas_singleView
                      : l10n.proCanvas_dualView,
                  onPressed: widget.onDualPagePressed!,
                  isDark: isDark,
                  isActive: widget.isDualPageMode,
                ),
                const SizedBox(width: 4),
              ],

              // Canvas rotation reset — only visible when canvas is rotated.
              if (widget.isCanvasRotated &&
                  widget.onResetRotation != null) ...[
                _LayoutChip(
                  icon: Icons.screen_rotation_alt_rounded,
                  label: l10n.proCanvas_resetRotation,
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    widget.onResetRotation!();
                  },
                  isDark: isDark,
                ),
                const SizedBox(width: 4),
              ],

              // Rotation lock toggle
              if (widget.onToggleRotationLock != null) ...[
                _LayoutChip(
                  icon: widget.isRotationLocked
                      ? Icons.screen_lock_rotation_rounded
                      : Icons.screen_rotation_rounded,
                  label: widget.isRotationLocked
                      ? l10n.proCanvas_unlockRotation
                      : l10n.proCanvas_lockRotation,
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    widget.onToggleRotationLock!();
                  },
                  isDark: isDark,
                  isActive: widget.isRotationLocked,
                ),
                const SizedBox(width: 4),
              ],

              // 🔄 Wheel mode toggle — chip with label so first-time users
              // can read "Modalità ruota" instead of hovering for tooltip.
              if (widget.onWheelModeToggle != null) ...[
                _LayoutChip(
                  icon: widget.isWheelModeActive
                      ? Icons.donut_large_rounded
                      : Icons.linear_scale_rounded,
                  label: l10n.toolsArea_wheelMode,
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    widget.onWheelModeToggle!();
                  },
                  isDark: isDark,
                  isActive: widget.isWheelModeActive,
                ),
                const SizedBox(width: 4),
              ],

              // Layers
              if (!widget.isImageEditingMode) ...[
                _LayoutChip(
                  icon: Icons.layers_rounded,
                  label: l10n.proCanvas_layers,
                  onPressed: widget.onLayersPressed,
                  isDark: isDark,
                ),
                const SizedBox(width: 4),
              ],

              // Handwriting Search
              if (widget.onSearchPressed != null) ...[
                _LayoutChip(
                  icon: widget.isSearchActive
                      ? Icons.search_off_rounded
                      : Icons.search_rounded,
                  label: widget.isSearchActive
                      ? l10n.proCanvas_closeSearch
                      : l10n.proCanvas_searchHandwriting,
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    widget.onSearchPressed!();
                  },
                  isDark: isDark,
                  isActive: widget.isSearchActive,
                ),
                const SizedBox(width: 4),
              ],
    ];
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

        // 📌 Bookmarks — opens the bookmark list sheet. Hidden when there
        // are no bookmarks (keeps the toolbar uncluttered before the user
        // has actually saved anything). Only the 3-zone tablet layout
        // reaches this code path — phones use `_buildSmallTopRow` instead.
        if (widget.onBookmarksPressed != null && widget.bookmarkCount > 0)
          _LayoutChip(
            icon: Icons.bookmark_rounded,
            label: '${l10n.hub_bookmarks} (${widget.bookmarkCount})',
            onPressed: widget.onBookmarksPressed!,
            isDark: isDark,
          ),

        // 🔄 Wheel mode toggle — moved to Settings → Studio avanzato
        // (Round 4 — Cambio B: power-user opt-in, not a toolbar primary).

        // Collapse toggle — animated chevron.
        _AnimatedCollapseButton(
          isExpanded: _isToolsExpanded,
          isDark: isDark,
          tooltip:
              _isToolsExpanded ? l10n.proCanvas_hide : l10n.proCanvas_show,
          onTap: _toggleToolsExpanded,
        ),

        // 💎 Trailing badge slot — V1 (2026-05-14): host injects
        // `FlueraCreditsBadge` so the AI credit counter is always visible
        // next to the settings dropdown (trasparenza-first pillar).
        // Null = no slot rendered (back-compat with hosts that haven't
        // wired the credits controller yet).
        if (widget.trailingBadge != null) ...[
          const SizedBox(width: 4),
          widget.trailingBadge!,
          const SizedBox(width: 4),
        ],

        // Settings dropdown — always the far-right anchor
        ToolbarSettingsDropdown(
          onBrushSettingsPressed: widget.onBrushSettingsPressed,
          onExportPressed: widget.onExportPressed,
          noteTitle: widget.noteTitle,
          onNoteTitleChanged: widget.onNoteTitleChanged,
          onPaperTypePressed: widget.onPaperTypePressed,
          onReadingLevelPressed: widget.onReadingLevelPressed,
          onWheelModeToggle: widget.onWheelModeToggle,
          isWheelModeActive: widget.isWheelModeActive,
          devModeEnabled: widget.devModeEnabled,
          currentPaperLabel: widget.currentPaperLabel,
          activeFiltersCount: widget.activeFiltersCount,
          readingLevelSeen: widget.readingLevelSeen,
          onReadingLevelMarkSeen: widget.onReadingLevelMarkSeen,
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // Quick rename — triggered by tapping the title in the left zone
  // --------------------------------------------------------------------------

  void _showQuickRenameFromTop(BuildContext context) {
    if (widget.onNoteTitleChanged == null) return;
    final l10n = FlueraLocalizations.of(context)!;
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

    Widget divider() =>
        Container(width: 1, height: 18, color: dividerColor);

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
  /// When true, the chip renders with the primary accent (tinted bg +
  /// border + icon/label) so toggles like Search active, Rotation Lock
  /// on, Wheel mode on read at a glance. Defaults to the neutral
  /// surface look.
  final bool isActive;

  const _LayoutChip({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.isDark,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = isActive
        ? cs.primary.withValues(alpha: isDark ? 0.22 : 0.12)
        : cs.surfaceContainerHighest.withValues(alpha: 0.6);
    final border = isActive
        ? cs.primary.withValues(alpha: 0.45)
        : cs.outlineVariant.withValues(alpha: 0.5);
    final fg = isActive ? cs.primary : cs.onSurfaceVariant;
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
              color: bg,
              borderRadius: BorderRadius.circular(ToolbarTokens.chipRadius),
              border: Border.all(
                color: border,
                width: isActive ? 1.2 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: ToolbarTokens.iconSizeSmall,
                  color: fg,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    color: fg,
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
      message: isHard ? '$label — non disponibile' : label,
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

/// 🧠 Cognitive chip widgets (Ghost Map / Fog of War / Socratic /
/// Exam / Cross-Zone Bridges) removed 2026-05-16: consolidated into
/// the CognitiveFeaturesSheet accessed via _FeaturesDiscoveryChip.
/// Their callbacks remain wired on the host — the sheet's actions
/// map calls them.
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

/// 📍 Checkpoint chip — Free+ standalone entry point.
///
/// Bookmark-icon pill that opens the checkpoint panel. Independent from
/// Time Travel (Pro) so Free users can reach Checkpoint at any tier — the
/// tier-aware cap (3/canvas for Free) is enforced inside the panel.
class _CheckpointChip extends StatelessWidget {
  final VoidCallback onPressed;
  final bool isDark;

  const _CheckpointChip({required this.onPressed, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final color = isDark ? Colors.white70 : Colors.black54;
    return Tooltip(
      message: 'Checkpoint',
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
              color: (isDark ? Colors.white : Colors.black).withValues(
                alpha: 0.05,
              ),
              borderRadius: BorderRadius.circular(ToolbarTokens.chipRadius),
            ),
            child: Icon(
              Icons.bookmark_outline_rounded,
              size: ToolbarTokens.iconSizeSmall,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

/// ✨ Features discovery chip — Round 4 (2026-05-15).
///
/// Center-zone pill that opens [CognitiveFeaturesSheet] on tap. Always
/// first in the toolbar so the 6 cognitive features (Ghost Map, Socratic,
/// Exam Session, Fog of War, Cross-Zone Bridges, Time Travel) stay
/// discoverable on-demand for users that haven't accumulated enough
/// sessions to hit the [CoachmarkEngine] triggers.
class _FeaturesDiscoveryChip extends StatelessWidget {
  final VoidCallback onPressed;
  final bool isDark;
  final String label;

  const _FeaturesDiscoveryChip({
    required this.onPressed,
    required this.isDark,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final accent = const Color(0xFF7C4DFF);
    return Tooltip(
      message: label,
      waitDuration: ToolbarTokens.tooltipDelay,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onPressed();
          },
          borderRadius: BorderRadius.circular(ToolbarTokens.chipRadius),
          child: Container(
            height: ToolbarTokens.chipHeight,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(ToolbarTokens.chipRadius),
              border: Border.all(
                color: accent.withValues(alpha: 0.30),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('✨', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: accent,
                    letterSpacing: -0.2,
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
/// Force-enables touch + stylus + mouse drag for the top-row center-zone
/// scrollable chips. Default Flutter ScrollBehavior on Android sometimes
/// drops horizontal swipes on a narrow `SingleChildScrollView` when a
/// sibling widget (e.g. the canvas gesture handler) is in the same arena.
/// Listing every `PointerDeviceKind` explicitly bypasses that heuristic.
class _ToolbarScrollBehavior extends MaterialScrollBehavior {
  const _ToolbarScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.unknown,
  };
}

