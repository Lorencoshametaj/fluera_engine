import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/fluera_localizations.dart';
import '../models/canvas_branch.dart';
import '../branching_manager.dart';

/// 🌿 Alternative Explorer — bottom sheet listing canvas alternatives
///
/// Repositioned 2026-05-15 from "git branches" mental model to "Alternative
/// esplorate". Defaults to flat list + non-destructive "Sostituisci Originale"
/// action; classic merge UI is gated behind [showAdvancedMerge] for power
/// users (Settings → Studio avanzato).
class BranchExplorerSheet extends StatefulWidget {
  final String canvasId;
  final BranchingManager branchingManager;
  final String? activeBranchId;
  final void Function(String? branchId) onSwitchBranch;
  final VoidCallback? onCreateBranch;
  final void Function(String branchId)? onDeleteBranch;
  final void Function(
    String sourceBranchId, {
    required String targetBranchId,
    bool deleteAfterMerge,
  })?
  onMergeBranch;

  /// When true, surfaces the classic git-style merge UI with checkbox
  /// "delete after merge". Default false: a single "Sostituisci l'Originale"
  /// action that performs target=main + deleteAfterMerge=true.
  final bool showAdvancedMerge;

  const BranchExplorerSheet({
    super.key,
    required this.canvasId,
    required this.branchingManager,
    this.activeBranchId,
    required this.onSwitchBranch,
    this.onCreateBranch,
    this.onDeleteBranch,
    this.onMergeBranch,
    this.showAdvancedMerge = false,
  });

  /// Show as a modal bottom sheet
  static Future<void> show({
    required BuildContext context,
    required String canvasId,
    required BranchingManager branchingManager,
    String? activeBranchId,
    required void Function(String? branchId) onSwitchBranch,
    VoidCallback? onCreateBranch,
    void Function(String branchId)? onDeleteBranch,
    void Function(
      String sourceBranchId, {
      required String targetBranchId,
      bool deleteAfterMerge,
    })?
    onMergeBranch,
    bool showAdvancedMerge = false,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (_) => BranchExplorerSheet(
            canvasId: canvasId,
            branchingManager: branchingManager,
            activeBranchId: activeBranchId,
            onSwitchBranch: onSwitchBranch,
            onCreateBranch: onCreateBranch,
            onDeleteBranch: onDeleteBranch,
            onMergeBranch: onMergeBranch,
            showAdvancedMerge: showAdvancedMerge,
          ),
    );
  }

  @override
  State<BranchExplorerSheet> createState() => _BranchExplorerSheetState();
}

class _BranchExplorerSheetState extends State<BranchExplorerSheet> {
  List<CanvasBranch> _branchTree = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    await widget.branchingManager.loadBranches(widget.canvasId);
    if (mounted) {
      setState(() {
        _branchTree = widget.branchingManager.getBranchTree();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E1E2E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.white54 : Colors.black45;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: subtitleColor.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.alt_route_rounded,
                  color: const Color(0xFF7C4DFF),
                  size: 22,
                ),
                const SizedBox(width: 10),
                Text(
                  FlueraLocalizations.of(context)!.branchExplorer_title,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                  ),
                ),
                const Spacer(),
                if (widget.onCreateBranch != null)
                  TextButton.icon(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                      widget.onCreateBranch!();
                    },
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(
                        FlueraLocalizations.of(context)!.branchExplorer_new),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF7C4DFF),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Content
          Flexible(
            child:
                _isLoading
                    ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: CircularProgressIndicator(
                          color: Color(0xFF7C4DFF),
                        ),
                      ),
                    )
                    : _branchTree.isEmpty
                    ? _buildEmptyState(textColor, subtitleColor)
                    : _buildBranchList(textColor, subtitleColor, isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(Color textColor, Color subtitleColor) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.alt_route_rounded,
            size: 48,
            color: subtitleColor.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            FlueraLocalizations.of(context)!.branchExplorer_emptyTitle,
            style: TextStyle(
              color: textColor,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            FlueraLocalizations.of(context)!.branchExplorer_emptyBody,
            textAlign: TextAlign.center,
            style: TextStyle(color: subtitleColor, fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildBranchList(Color textColor, Color subtitleColor, bool isDark) {
    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _branchTree.length,
      itemBuilder: (context, index) {
        final branch = _branchTree[index];
        return _buildBranchEntry(branch, textColor, subtitleColor, isDark);
      },
    );
  }

  Widget _buildBranchEntry(
    CanvasBranch branch,
    Color textColor,
    Color subtitleColor,
    bool isDark,
  ) {
    final isActive = widget.activeBranchId == branch.id;
    final isMain = branch.id == 'br_main';
    final _m = [
      'Gen',
      'Feb',
      'Mar',
      'Apr',
      'Mag',
      'Giu',
      'Lug',
      'Ago',
      'Set',
      'Ott',
      'Nov',
      'Dic',
    ];
    final d = branch.createdAt;
    final dateStr =
        '${d.day} ${_m[d.month - 1]}, ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final branchColor =
        isMain ? const Color(0xFF7C4DFF) : _getBranchColor(branch);
    final l10n = FlueraLocalizations.of(context)!;

    // Subtitle: "Originale" for main, otherwise "Nasce da: <parent> · <date> [· ☁️]"
    String parentLabel = l10n.branchExplorer_main;
    if (!isMain && branch.parentBranchId != null &&
        branch.parentBranchId != 'br_main') {
      final parent = widget.branchingManager.branches
          .where((b) => b.id == branch.parentBranchId)
          .firstOrNull;
      if (parent != null) parentLabel = parent.name;
    }
    final subtitleParts = <String>[
      if (isMain)
        l10n.branchExplorer_primaryBranch
      else ...[
        '${l10n.branchExplorer_parent}: $parentLabel',
        dateStr,
      ],
    ];
    if (!isMain && branch.isSyncedToCloud) {
      subtitleParts.add('☁️');
    }

    return _BranchListTile(
      icon: isMain ? Icons.bookmark_rounded : Icons.alt_route_rounded,
      iconColor: branchColor,
      name: isMain ? l10n.branchExplorer_mainCanvasLabel : branch.name,
      subtitle: subtitleParts.join(' · '),
      description: isMain ? null : branch.description,
      isActive: isActive,
      indentLevel: 0, // 🌿 2026-05-15: flat layout — no more tree indentation.
      textColor: textColor,
      subtitleColor: subtitleColor,
      isDark: isDark,
      onTap: () {
        HapticFeedback.lightImpact();
        widget.onSwitchBranch(branch.id);
        Navigator.pop(context);
      },
      onLongPress: isMain ? null : () => _showBranchActions(branch),
    );
  }

  Color _getBranchColor(CanvasBranch branch) {
    if (branch.color != null) {
      try {
        return Color(int.parse(branch.color!, radix: 16) | 0xFF000000);
      } catch (e) {
      }
    }
    // Default: generate color from hash
    final colors = [
      const Color(0xFF448AFF), // Blue
      const Color(0xFF00BCD4), // Cyan
      const Color(0xFF66BB6A), // Green
      const Color(0xFFFF7043), // Orange
      const Color(0xFFAB47BC), // Purple
      const Color(0xFFEF5350), // Red
    ];
    return colors[branch.id.hashCode.abs() % colors.length];
  }

  void _showBranchActions(CanvasBranch branch) {
    HapticFeedback.mediumImpact();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder:
          (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  branch.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.edit_rounded, size: 20),
                  title: Text(
                      FlueraLocalizations.of(context)!.branchExplorer_rename),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showRenameDialog(branch);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.description_outlined, size: 20),
                  title: Text(FlueraLocalizations.of(context)!
                      .branchExplorer_editDescription),
                  subtitle:
                      branch.description != null
                          ? Text(
                            branch.description!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white38 : Colors.black38,
                            ),
                          )
                          : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    _showDescriptionDialog(branch);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.copy_rounded, size: 20),
                  title: Text(FlueraLocalizations.of(context)!
                      .branchExplorer_duplicate),
                  onTap: () async {
                    Navigator.pop(ctx);
                    HapticFeedback.mediumImpact();
                    final userId =
                        widget.branchingManager.activeBranch?.createdBy ?? '';
                    await widget.branchingManager.duplicateBranch(
                      canvasId: widget.canvasId,
                      branchId: branch.id,
                      createdBy: userId,
                    );
                    if (mounted) _loadBranches();
                  },
                ),
                // 🌿 2026-05-15: hide tree-style merge by default.
                // Default UI exposes a single "Sostituisci l'Originale" action
                // (target=br_main + deleteAfterMerge=true). Power users can
                // toggle [showAdvancedMerge] in Settings to restore the
                // classic UI with parent-target picker + checkbox.
                if (widget.onMergeBranch != null && branch.id != 'br_main')
                  ListTile(
                    leading: const Icon(
                      Icons.swap_horiz_rounded,
                      size: 20,
                      color: Color(0xFF66BB6A),
                    ),
                    title: Text(
                      FlueraLocalizations.of(context)!.branchExplorer_merge,
                      style: const TextStyle(color: Color(0xFF66BB6A)),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      if (widget.showAdvancedMerge) {
                        // Advanced: parent-target merge with checkbox
                        final targetId = branch.parentBranchId ?? 'br_main';
                        final targetBranch =
                            widget.branchingManager.branches
                                .where((b) => b.id == targetId)
                                .firstOrNull;
                        final targetName = targetId == 'br_main'
                            ? FlueraLocalizations.of(context)!
                                .branchExplorer_main
                            : (targetBranch?.name ??
                                FlueraLocalizations.of(context)!
                                    .branchExplorer_parent);
                        _confirmMergeAdvanced(branch, targetId, targetName);
                      } else {
                        // Default: replace original (main) one-tap
                        _confirmReplaceOriginal(branch);
                      }
                    },
                  ),
                ListTile(
                  leading: Icon(
                    Icons.inventory_2_outlined,
                    size: 20,
                    color: const Color(0xFFEF5350),
                  ),
                  title: Text(
                    FlueraLocalizations.of(context)!.branchExplorer_delete,
                    style: TextStyle(color: const Color(0xFFEF5350)),
                  ),
                  subtitle:
                      widget.branchingManager.hasChildren(branch.id)
                          ? Text(
                            FlueraLocalizations.of(context)!
                                .branchExplorer_archiveWithChildren,
                            style: TextStyle(
                              fontSize: 12,
                              color: const Color(0xFFE57373),
                            ),
                          )
                          : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmDelete(branch);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
    );
  }

  void _showRenameDialog(CanvasBranch branch) {
    final controller = TextEditingController(text: branch.name);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = FlueraLocalizations.of(context)!;

    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
            title: Text(l10n.branchExplorer_renameBranch),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: l10n.branchExplorer_branchNameHint,
                border: const OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.branchExplorer_cancel),
              ),
              FilledButton(
                onPressed: () async {
                  final name = controller.text.trim();
                  if (name.isNotEmpty) {
                    await widget.branchingManager.renameBranch(
                      widget.canvasId,
                      branch.id,
                      name,
                    );
                    Navigator.pop(ctx);
                    if (mounted) _loadBranches(); // Refresh
                  }
                },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF7C4DFF),
                ),
                child: Text(l10n.branchExplorer_rename),
              ),
            ],
          ),
    );
  }

  void _showDescriptionDialog(CanvasBranch branch) {
    final controller = TextEditingController(text: branch.description ?? '');
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = FlueraLocalizations.of(context)!;

    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
            title: Text(l10n.branchExplorer_branchDescription),
            content: TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: FlueraLocalizations.of(context)!
                    .branchExplorer_descriptionHint,
                border: const OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.branchExplorer_cancel),
              ),
              FilledButton(
                onPressed: () async {
                  final desc = controller.text.trim();
                  await widget.branchingManager.updateBranchDescription(
                    widget.canvasId,
                    branch.id,
                    desc.isEmpty ? null : desc,
                  );
                  Navigator.pop(ctx);
                  if (mounted) _loadBranches();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF7C4DFF),
                ),
                child: Text(l10n.branchExplorer_save),
              ),
            ],
          ),
    );
  }

  /// 🌿 Default replace flow: 1-tap confirm, target=main, deleteAfterMerge=true.
  /// No checkbox, no parent picker. Student-friendly semantics: "Sostituisci
  /// l'Originale con questa alternativa".
  void _confirmReplaceOriginal(CanvasBranch branch) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = FlueraLocalizations.of(context)!;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
        icon: const Icon(
          Icons.swap_horiz_rounded,
          color: Color(0xFF66BB6A),
          size: 32,
        ),
        title: Text(l10n.branchExplorer_replaceConfirmTitle),
        content: Text(
          l10n.branchExplorer_replaceConfirmBody(branch.name),
          style: TextStyle(
            color: isDark ? Colors.white70 : Colors.black54,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.branchExplorer_cancel),
          ),
          FilledButton(
            onPressed: () {
              HapticFeedback.heavyImpact();
              Navigator.pop(ctx);
              Navigator.pop(context); // Close explorer
              widget.onMergeBranch?.call(
                branch.id,
                targetBranchId: 'br_main',
                deleteAfterMerge: true,
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF43A047),
            ),
            child: Text(l10n.branchExplorer_merge),
          ),
        ],
      ),
    );
  }

  /// 🛠️ Power-user merge flow (gated by [showAdvancedMerge]).
  /// Original git-style UI: parent-target picker + delete-after-merge checkbox.
  void _confirmMergeAdvanced(
    CanvasBranch branch,
    String targetBranchId,
    String targetName,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    bool deleteAfterMerge = false;

    showDialog(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setDialogState) => AlertDialog(
                  backgroundColor:
                      isDark ? const Color(0xFF2A2A3E) : Colors.white,
                  icon: Icon(
                    Icons.merge_rounded,
                    color: const Color(0xFF66BB6A),
                    size: 32,
                  ),
                  title: Text(
                    FlueraLocalizations.of(context)!
                        .branchExplorer_replaceConfirmTitle,
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        FlueraLocalizations.of(context)!
                            .branchExplorer_replaceConfirmBody(branch.name),
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black54,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Advanced-mode target selector summary
                      Text(
                        '→ $targetName',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: deleteAfterMerge,
                              onChanged: (v) {
                                setDialogState(
                                  () => deleteAfterMerge = v ?? false,
                                );
                              },
                              activeColor: const Color(0xFF7C4DFF),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              FlueraLocalizations.of(context)!
                                  .branchExplorer_deleteAfterMerge,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.white70 : Colors.black54,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(FlueraLocalizations.of(context)!
                          .branchExplorer_cancel),
                    ),
                    FilledButton(
                      onPressed: () {
                        HapticFeedback.heavyImpact();
                        Navigator.pop(ctx);
                        Navigator.pop(context); // Close branch explorer
                        widget.onMergeBranch?.call(
                          branch.id,
                          targetBranchId: targetBranchId,
                          deleteAfterMerge: deleteAfterMerge,
                        );
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF43A047),
                      ),
                      child: Text(FlueraLocalizations.of(context)!
                          .branchExplorer_merge),
                    ),
                  ],
                ),
          ),
    );
  }

  void _confirmDelete(CanvasBranch branch) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasChildren = widget.branchingManager.hasChildren(branch.id);
    final isActive = widget.activeBranchId == branch.id;

    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
            icon: Icon(
              Icons.inventory_2_outlined,
              color: const Color(0xFFEF5350),
              size: 40,
            ),
            title: Text(
              FlueraLocalizations.of(context)!
                  .branchExplorer_archiveConfirmTitle(branch.name),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  FlueraLocalizations.of(context)!
                      .branchExplorer_archiveConfirmBody,
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black54,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                _buildDeleteItem(
                  Icons.brush_rounded,
                  FlueraLocalizations.of(context)!.branchExplorer_warningStrokes,
                  isDark,
                ),
                _buildDeleteItem(
                  Icons.history_rounded,
                  FlueraLocalizations.of(context)!
                      .branchExplorer_timeTravelHistory,
                  isDark,
                ),
                _buildDeleteItem(
                  Icons.photo_camera_rounded,
                  FlueraLocalizations.of(context)!
                      .branchExplorer_warningSnapshots,
                  isDark,
                ),
                if (hasChildren)
                  _buildDeleteItem(
                    Icons.account_tree_rounded,
                    FlueraLocalizations.of(context)!
                        .branchExplorer_subBranchesCascade,
                    isDark,
                    isWarning: true,
                  ),
                if (isActive) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(
                        alpha: isDark ? 0.15 : 0.08,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.orange.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 16,
                          color: const Color(0xFFFFA726),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            FlueraLocalizations.of(context)!
                                .branchExplorer_youAreOnActiveWarning,
                            style: TextStyle(
                              color: const Color(0xFFFFA726),
                              fontSize: 12,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(FlueraLocalizations.of(context)!
                    .branchExplorer_cancel),
              ),
              FilledButton.icon(
                onPressed: () async {
                  HapticFeedback.heavyImpact();
                  final wasActive = isActive;

                  // Delete branch and its data
                  await widget.branchingManager.deleteBranch(
                    widget.canvasId,
                    branch.id,
                  );

                  if (ctx.mounted) Navigator.pop(ctx);

                  // If deleted branch was active, switch to main
                  if (wasActive && widget.onDeleteBranch != null) {
                    Navigator.pop(context); // Close explorer
                    widget.onDeleteBranch!(branch.id);
                  } else {
                    if (mounted) _loadBranches(); // Refresh list
                  }
                },
                icon: const Icon(Icons.delete_forever_rounded, size: 18),
                label: Text(FlueraLocalizations.of(context)!
                    .branchExplorer_deleteForever),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF5350)),
              ),
            ],
          ),
    );
  }

  Widget _buildDeleteItem(
    IconData icon,
    String text,
    bool isDark, {
    bool isWarning = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color:
                isWarning
                    ? const Color(0xFFEF5350)
                    : (isDark ? Colors.white38 : Colors.black38),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color:
                    isWarning
                        ? const Color(0xFFEF5350)
                        : (isDark ? Colors.white60 : Colors.black54),
                fontSize: 13,
                fontWeight: isWarning ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// BRANCH LIST TILE
// =============================================================================

class _BranchListTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String name;
  final String subtitle;
  final String? description;
  final bool isActive;
  final int indentLevel;
  final Color textColor;
  final Color subtitleColor;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _BranchListTile({
    required this.icon,
    required this.iconColor,
    required this.name,
    required this.subtitle,
    this.description,
    required this.isActive,
    required this.indentLevel,
    required this.textColor,
    required this.subtitleColor,
    required this.isDark,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: EdgeInsets.only(
          left: 20.0 + (indentLevel * 24.0),
          right: 16,
          top: 12,
          bottom: 12,
        ),
        color:
            isActive ? iconColor.withValues(alpha: isDark ? 0.12 : 0.06) : null,
        child: Row(
          children: [
            // Tree connector
            if (indentLevel > 0)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  Icons.subdirectory_arrow_right_rounded,
                  size: 16,
                  color: subtitleColor.withValues(alpha: 0.4),
                ),
              ),

            // Icon
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: isDark ? 0.2 : 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),

            const SizedBox(width: 12),

            // Name + subtitle + description
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 14,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(color: subtitleColor, fontSize: 12),
                  ),
                  if (description != null && description!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      description!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: subtitleColor.withValues(alpha: 0.7),
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Active indicator
            if (isActive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  FlueraLocalizations.of(context)!.branchExplorer_active,
                  style: TextStyle(
                    color: iconColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
