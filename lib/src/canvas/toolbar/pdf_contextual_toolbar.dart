import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/models/pdf_annotation_model.dart';
import '../../core/models/pdf_document_model.dart';
import '../../core/models/pdf_layout_preset.dart';
import '../../core/nodes/pdf_document_node.dart';
import '../../history/command_history.dart';
import '../../tools/pdf/pdf_annotation_controller.dart';
import '../../tools/pdf/pdf_search_controller.dart';

// =============================================================================
// 📄 PDF TOOLBAR POPUPS — Anchored popup panels triggered from toolbar buttons
// =============================================================================

/// Shows the PDF page navigation & actions popup anchored below [anchor].
///
/// Only contains page nav + page actions + pro actions (watermark/stamp/bg).
/// Night mode, bookmark, zoom-to-fit, export, and layout mode are now
/// direct toolbar buttons — no longer in this popup.
void showPdfPagePopup({
  required BuildContext context,
  required Rect anchor,
  required PdfDocumentNode doc,
  required int selectedPageIndex,
  required ValueChanged<int> onPageChanged,
  void Function(int selectedPageIndex)? onInsertBlankPage,
  void Function(int)? onDuplicatePage,
  void Function(int)? onDeletePage,
  void Function(int oldIndex, int newIndex)? onReorderPage,
  VoidCallback? onLayoutChanged,
  VoidCallback? onWatermarkToggle,
  void Function(int pageIndex, PdfStampType stamp)? onAddStamp,
  void Function(int pageIndex)? onChangeBackground,
  VoidCallback? onDeleteDocument,
}) {
  showMenu<void>(
    context: context,
    position: RelativeRect.fromLTRB(
      anchor.left,
      anchor.bottom + 4,
      anchor.right,
      0,
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    elevation: 8,
    constraints: const BoxConstraints(minWidth: 280, maxWidth: 320),
    items: [
      _PopupHeader(
        icon: Icons.file_copy_rounded,
        title: 'Pages',
        trailing: '${doc.documentModel.totalPages}',
      ),
      _PopupDivider(),
      _PdfPageNavItem(
        doc: doc,
        selectedPageIndex: selectedPageIndex,
        onPageChanged: onPageChanged,
        onLayoutChanged: onLayoutChanged,
      ),
      _PopupDivider(),
      _PdfPageActionsItem(
        doc: doc,
        selectedPageIndex: selectedPageIndex,
        onInsertBlankPage: onInsertBlankPage,
        onDuplicatePage: onDuplicatePage,
        onDeletePage: onDeletePage,
        onReorderPage: onReorderPage,
        onLayoutChanged: onLayoutChanged,
      ),
      if (onWatermarkToggle != null ||
          onAddStamp != null ||
          onChangeBackground != null) ...[
        _PopupDivider(),
        _PdfProActionsItem(
          doc: doc,
          selectedPageIndex: selectedPageIndex,
          onWatermarkToggle: onWatermarkToggle,
          onAddStamp: onAddStamp,
          onChangeBackground: onChangeBackground,
        ),
      ],
      if (onDeleteDocument != null) ...[
        _PopupDivider(),
        _PdfDeleteDocItem(onDeleteDocument: onDeleteDocument),
      ],
    ],
  );
}

/// Shows the PDF search popup anchored below [anchor].
void showPdfSearchPopup({
  required BuildContext context,
  required Rect anchor,
  required List<PdfDocumentNode> docs,
  required PdfSearchController searchController,
  int? selectedPageIndex,
  VoidCallback? onLayoutChanged,
  void Function(String documentId, int pageIndex)? onGoToPage,
}) {
  showDialog(
    context: context,
    barrierColor: Colors.transparent,
    builder:
        (ctx) => _PdfSearchPanel(
          anchor: anchor,
          docs: docs,
          searchController: searchController,
          selectedPageIndex: selectedPageIndex,
          onLayoutChanged: onLayoutChanged,
          onGoToPage: onGoToPage,
        ),
  );
}

/// Shows the PDF annotation popup anchored below [anchor].
void showPdfAnnotatePopup({
  required BuildContext context,
  required Rect anchor,
  required PdfAnnotationController annotationController,
  required int selectedPageIndex,
  CommandHistory? history,
  VoidCallback? onLayoutChanged,
}) {
  showDialog(
    context: context,
    barrierColor: Colors.transparent,
    builder:
        (ctx) => _PdfAnnotatePanel(
          anchor: anchor,
          annotationController: annotationController,
          selectedPageIndex: selectedPageIndex,
          history: history,
          onLayoutChanged: onLayoutChanged,
        ),
  );
}

/// Shows the PDF layout popup anchored below [anchor].
void showPdfLayoutPopup({
  required BuildContext context,
  required Rect anchor,
  required PdfDocumentNode doc,
  VoidCallback? onLayoutChanged,
}) {
  showDialog(
    context: context,
    barrierColor: Colors.transparent,
    builder:
        (ctx) => _PdfLayoutPanel(
          anchor: anchor,
          doc: doc,
          onLayoutChanged: onLayoutChanged,
        ),
  );
}

// =============================================================================
// Menu items
// =============================================================================

class _PopupHeader extends PopupMenuEntry<void> {
  final IconData icon;
  final String title;
  final String? trailing;

  const _PopupHeader({required this.icon, required this.title, this.trailing});

  @override
  double get height => 40;

  @override
  bool represents(void value) => false;

  @override
  State<_PopupHeader> createState() => _PopupHeaderState();
}

class _PopupHeaderState extends State<_PopupHeader> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(widget.icon, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Text(
            widget.title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          if (widget.trailing != null) ...[
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                widget.trailing!,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: cs.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PopupDivider extends PopupMenuEntry<void> {
  @override
  double get height => 1;

  @override
  bool represents(void value) => false;

  @override
  State<_PopupDivider> createState() => _PopupDividerState();
}

class _PopupDividerState extends State<_PopupDivider> {
  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1);
  }
}

class _PdfPageNavItem extends PopupMenuEntry<void> {
  final PdfDocumentNode doc;
  final int selectedPageIndex;
  final ValueChanged<int> onPageChanged;
  final VoidCallback? onLayoutChanged;

  const _PdfPageNavItem({
    required this.doc,
    required this.selectedPageIndex,
    required this.onPageChanged,
    this.onLayoutChanged,
  });

  @override
  double get height => 48;

  @override
  bool represents(void value) => false;

  @override
  State<_PdfPageNavItem> createState() => _PdfPageNavItemState();
}

class _PdfPageNavItemState extends State<_PdfPageNavItem> {
  late int _page;

  @override
  void initState() {
    super.initState();
    _page = widget.selectedPageIndex;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = widget.doc.documentModel.totalPages;
    final page = widget.doc.pageAt(_page);
    final isLocked = page?.pageModel.isLocked ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Rotate left
          _miniBtn(Icons.rotate_left_rounded, cs, () {
            widget.doc.rotatePage(_page, angleDegrees: -90);
            widget.onLayoutChanged?.call();
            // 📡 Broadcast AFTER onLayoutChanged consumed pendingStrokeRotation
            widget.doc.onMutation?.call('pageRotated', {
              'pageIndex': _page,
              'angleDegrees': -90.0,
            });
            setState(() {});
          }),
          const SizedBox(width: 4),
          // Previous
          _miniBtn(
            Icons.chevron_left_rounded,
            cs,
            _page > 0
                ? () => setState(() {
                  _page--;
                  widget.onPageChanged(_page);
                })
                : null,
          ),
          const SizedBox(width: 4),
          // Page indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${_page + 1} / $total',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Next
          _miniBtn(
            Icons.chevron_right_rounded,
            cs,
            _page < total - 1
                ? () => setState(() {
                  _page++;
                  widget.onPageChanged(_page);
                })
                : null,
          ),
          const SizedBox(width: 4),
          // Rotate right
          _miniBtn(Icons.rotate_right_rounded, cs, () {
            widget.doc.rotatePage(_page, angleDegrees: 90);
            widget.onLayoutChanged?.call();
            // 📡 Broadcast AFTER onLayoutChanged consumed pendingStrokeRotation
            widget.doc.onMutation?.call('pageRotated', {
              'pageIndex': _page,
              'angleDegrees': 90.0,
            });
            setState(() {});
          }),
          const SizedBox(width: 4),
          // Lock toggle
          _miniBtn(
            isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
            cs,
            () {
              widget.doc.togglePageLock(_page);
              widget.onLayoutChanged?.call();
              setState(() {});
            },
            active: !isLocked,
          ),
        ],
      ),
    );
  }

  Widget _miniBtn(
    IconData icon,
    ColorScheme cs,
    VoidCallback? onTap, {
    bool active = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap:
            onTap != null
                ? () {
                  HapticFeedback.lightImpact();
                  onTap();
                }
                : null,
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? cs.primaryContainer.withValues(alpha: 0.5) : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 18,
            color:
                onTap == null
                    ? cs.onSurface.withValues(alpha: 0.25)
                    : (active ? cs.primary : cs.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

class _PdfPageActionsItem extends PopupMenuEntry<void> {
  final PdfDocumentNode doc;
  final int selectedPageIndex;
  final void Function(int selectedPageIndex)? onInsertBlankPage;
  final void Function(int)? onDuplicatePage;
  final void Function(int)? onDeletePage;
  final void Function(int oldIndex, int newIndex)? onReorderPage;
  final VoidCallback? onLayoutChanged;

  const _PdfPageActionsItem({
    required this.doc,
    required this.selectedPageIndex,
    this.onInsertBlankPage,
    this.onDuplicatePage,
    this.onDeletePage,
    this.onReorderPage,
    this.onLayoutChanged,
  });

  @override
  double get height => 44;

  @override
  bool represents(void value) => false;

  @override
  State<_PdfPageActionsItem> createState() => _PdfPageActionsItemState();
}

class _PdfPageActionsItemState extends State<_PdfPageActionsItem> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Wrap(
        alignment: WrapAlignment.spaceEvenly,
        runSpacing: 4,
        children: [
          if (widget.onInsertBlankPage != null)
            _actionBtn(Icons.add_rounded, 'Insert', cs, () {
              HapticFeedback.mediumImpact();
              widget.onInsertBlankPage!(widget.selectedPageIndex);
              widget.onLayoutChanged?.call();
              Navigator.pop(context);
            }),
          if (widget.onDuplicatePage != null)
            _actionBtn(Icons.copy_rounded, 'Duplicate', cs, () {
              HapticFeedback.mediumImpact();
              widget.onDuplicatePage!(widget.selectedPageIndex);
              widget.onLayoutChanged?.call();
              Navigator.pop(context);
            }),
          if (widget.onReorderPage != null && widget.selectedPageIndex > 0)
            _actionBtn(Icons.arrow_upward_rounded, 'Up', cs, () {
              HapticFeedback.mediumImpact();
              widget.onReorderPage!(
                widget.selectedPageIndex,
                widget.selectedPageIndex - 1,
              );
              widget.onLayoutChanged?.call();
              Navigator.pop(context);
            }),
          if (widget.onReorderPage != null &&
              widget.selectedPageIndex < widget.doc.pageNodes.length - 1)
            _actionBtn(Icons.arrow_downward_rounded, 'Down', cs, () {
              HapticFeedback.mediumImpact();
              widget.onReorderPage!(
                widget.selectedPageIndex,
                widget.selectedPageIndex + 1,
              );
              widget.onLayoutChanged?.call();
              Navigator.pop(context);
            }),
          if (widget.onDeletePage != null && widget.doc.pageNodes.length > 1)
            _actionBtn(Icons.delete_outline_rounded, 'Delete', cs, () {
              HapticFeedback.heavyImpact();
              widget.onDeletePage!(widget.selectedPageIndex);
              widget.onLayoutChanged?.call();
              Navigator.pop(context);
            }, destructive: true),
        ],
      ),
    );
  }

  Widget _actionBtn(
    IconData icon,
    String label,
    ColorScheme cs,
    VoidCallback onTap, {
    bool destructive = false,
  }) {
    final color = destructive ? cs.error : cs.onSurfaceVariant;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PdfQuickActionsItem extends PopupMenuEntry<void> {
  final PdfDocumentNode doc;
  final int selectedPageIndex;
  final VoidCallback? onNightModeToggle;
  final void Function(int)? onBookmarkToggle;
  final void Function(int)? onZoomToFit;

  const _PdfQuickActionsItem({
    required this.doc,
    required this.selectedPageIndex,
    this.onNightModeToggle,
    this.onBookmarkToggle,
    this.onZoomToFit,
  });

  @override
  double get height => 44;

  @override
  bool represents(void value) => false;

  @override
  State<_PdfQuickActionsItem> createState() => _PdfQuickActionsItemState();
}

class _PdfQuickActionsItemState extends State<_PdfQuickActionsItem> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isNight = widget.doc.documentModel.nightMode;
    final pages = widget.doc.pageNodes;
    final isBookmarked =
        widget.selectedPageIndex < pages.length &&
        pages[widget.selectedPageIndex].pageModel.isBookmarked;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (widget.onNightModeToggle != null)
            _quickBtn(
              isNight ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              isNight ? 'Day' : 'Night',
              cs,
              isActive: isNight,
              () {
                HapticFeedback.mediumImpact();
                widget.onNightModeToggle!();
                Navigator.pop(context);
              },
            ),
          if (widget.onBookmarkToggle != null)
            _quickBtn(
              isBookmarked
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
              'Bookmark',
              cs,
              isActive: isBookmarked,
              () {
                HapticFeedback.mediumImpact();
                widget.onBookmarkToggle!(widget.selectedPageIndex);
                Navigator.pop(context);
              },
            ),
          if (widget.onZoomToFit != null)
            _quickBtn(Icons.fit_screen_rounded, 'Fit', cs, () {
              HapticFeedback.mediumImpact();
              widget.onZoomToFit!(widget.selectedPageIndex);
              Navigator.pop(context);
            }),
        ],
      ),
    );
  }

  Widget _quickBtn(
    IconData icon,
    String label,
    ColorScheme cs,
    VoidCallback onTap, {
    bool isActive = false,
  }) {
    final color = isActive ? cs.primary : cs.onSurfaceVariant;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// 🔧 PRO ACTIONS — Watermark, Stamp, Print, Presentation, Sign, Layout
// =============================================================================

class _PdfProActionsItem extends PopupMenuEntry<void> {
  final PdfDocumentNode doc;
  final int selectedPageIndex;
  final VoidCallback? onWatermarkToggle;
  final void Function(int pageIndex, PdfStampType stamp)? onAddStamp;
  final void Function(int pageIndex)? onChangeBackground;

  const _PdfProActionsItem({
    required this.doc,
    required this.selectedPageIndex,
    this.onWatermarkToggle,
    this.onAddStamp,
    this.onChangeBackground,
  });

  @override
  double get height => 44;

  @override
  bool represents(void value) => false;

  @override
  State<_PdfProActionsItem> createState() => _PdfProActionsItemState();
}

class _PdfProActionsItemState extends State<_PdfProActionsItem> {
  Widget _proBtn(
    IconData icon,
    String label,
    ColorScheme cs,
    VoidCallback onTap, {
    bool isActive = false,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: isActive ? cs.primary : cs.onSurfaceVariant,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasWatermark = widget.doc.documentModel.watermarkText != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (widget.onWatermarkToggle != null)
            _proBtn(Icons.water_drop_rounded, 'Watermark', cs, () {
              HapticFeedback.mediumImpact();
              Navigator.pop(context);
              widget.onWatermarkToggle!();
            }, isActive: hasWatermark),
          if (widget.onAddStamp != null)
            _proBtn(Icons.approval_rounded, 'Stamp', cs, () {
              HapticFeedback.mediumImpact();
              Navigator.pop(context); // Close contextual menu first
              widget.onAddStamp!(
                widget.selectedPageIndex,
                PdfStampType.approved, // Ignored — _ui_toolbar shows chooser
              );
            }),
          if (widget.onChangeBackground != null)
            _proBtn(Icons.texture_rounded, 'Background', cs, () {
              HapticFeedback.mediumImpact();
              Navigator.pop(context);
              widget.onChangeBackground!(widget.selectedPageIndex);
            }),
        ],
      ),
    );
  }
}

// =============================================================================
// 🗑️ DELETE DOCUMENT — Destructive action
// =============================================================================

class _PdfDeleteDocItem extends PopupMenuEntry<void> {
  final VoidCallback onDeleteDocument;

  const _PdfDeleteDocItem({required this.onDeleteDocument});

  @override
  double get height => 48;

  @override
  bool represents(void value) => false;

  @override
  State<_PdfDeleteDocItem> createState() => _PdfDeleteDocItemState();
}

class _PdfDeleteDocItemState extends State<_PdfDeleteDocItem> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () {
        Navigator.of(context).pop(); // Close popup first
        widget.onDeleteDocument();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: cs.error, size: 20),
            const SizedBox(width: 12),
            Text(
              'Delete Document',
              style: TextStyle(
                color: cs.error,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PdfExportItem extends PopupMenuEntry<void> {
  final VoidCallback onExport;

  const _PdfExportItem({required this.onExport});

  @override
  double get height => 44;

  @override
  bool represents(void value) => false;

  @override
  State<_PdfExportItem> createState() => _PdfExportItemState();
}

class _PdfExportItemState extends State<_PdfExportItem> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: SizedBox(
        width: double.infinity,
        height: 34,
        child: FilledButton.tonalIcon(
          onPressed: () {
            HapticFeedback.mediumImpact();
            // Pop the pages popup FIRST, then invoke export after
            // the popup is fully dismissed. This prevents Navigator.pop
            // from accidentally closing the PdfExportDialog bottom sheet.
            Navigator.pop(context);
            // Microtask delay ensures the popup route is fully disposed
            Future.microtask(() => widget.onExport());
          },
          icon: const Icon(Icons.ios_share_rounded, size: 16),
          label: const Text(
            'Export Annotated',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// 🔍 SEARCH PANEL — Floating anchored dialog
// =============================================================================

class _PdfSearchPanel extends StatefulWidget {
  final Rect anchor;
  final List<PdfDocumentNode> docs;
  final PdfSearchController searchController;
  final int? selectedPageIndex;
  final VoidCallback? onLayoutChanged;
  final void Function(String documentId, int pageIndex)? onGoToPage;

  const _PdfSearchPanel({
    required this.anchor,
    required this.docs,
    required this.searchController,
    this.selectedPageIndex,
    this.onLayoutChanged,
    this.onGoToPage,
  });

  @override
  State<_PdfSearchPanel> createState() => _PdfSearchPanelState();
}

class _PdfSearchPanelState extends State<_PdfSearchPanel> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce; // (O) Debounced auto-search

  @override
  void initState() {
    super.initState();
    _textController.text = widget.searchController.query;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// (N) Navigate to next match and scroll to it.
  void _goToNext() {
    final sc = widget.searchController;
    sc.nextMatch();
    widget.onLayoutChanged?.call();
    if (sc.currentMatch != null) {
      widget.onGoToPage?.call(
        sc.currentMatch!.documentId,
        sc.currentMatch!.pageIndex,
      );
    }
    // Issue 20: Keep focus on search field after clicking Next
    _focusNode.requestFocus();
  }

  /// (N) Navigate to previous match and scroll to it.
  void _goToPrevious() {
    final sc = widget.searchController;
    sc.previousMatch();
    widget.onLayoutChanged?.call();
    if (sc.currentMatch != null) {
      widget.onGoToPage?.call(
        sc.currentMatch!.documentId,
        sc.currentMatch!.pageIndex,
      );
    }
    // Issue 20: Keep focus on search field after clicking Prev
    _focusNode.requestFocus();
  }

  /// (O) Trigger debounced search.
  void _onQueryChanged(String query) {
    setState(() {});
    _debounce?.cancel();
    if (query.isEmpty) {
      widget.searchController.clearSearch();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () {
      widget.searchController.searchDocuments(
        widget.docs,
        query,
        startPageIndex: widget.selectedPageIndex,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sc = widget.searchController;

    return Stack(
      children: [
        // Dismiss tap area
        GestureDetector(onTap: () => Navigator.pop(context)),
        Positioned(
          left: (widget.anchor.left - 40).clamp(
            8,
            MediaQuery.of(context).size.width - 308,
          ),
          top: widget.anchor.bottom + 8,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(16),
            color: isDark ? cs.surfaceContainerHigh : cs.surfaceContainerLow,
            child: Container(
              width: 300,
              padding: const EdgeInsets.all(12),
              child: ListenableBuilder(
                listenable: sc,
                builder: (context, _) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Search field with keyboard shortcuts (N)
                      SizedBox(
                        height: 38,
                        child: KeyboardListener(
                          focusNode: FocusNode(), // passthrough
                          onKeyEvent: (event) {
                            if (event is KeyDownEvent &&
                                event.logicalKey == LogicalKeyboardKey.enter) {
                              if (sc.hasMatches) {
                                if (HardwareKeyboard.instance.isShiftPressed) {
                                  _goToPrevious(); // Shift+Enter → prev
                                } else {
                                  _goToNext(); // Enter → next
                                }
                              }
                            }
                          },
                          child: TextField(
                            controller: _textController,
                            focusNode: _focusNode,
                            style: TextStyle(fontSize: 13, color: cs.onSurface),
                            decoration: InputDecoration(
                              hintText:
                                  widget.docs.length >= 2
                                      ? 'Search in ${widget.docs.length} PDFs…'
                                      : 'Search in PDF…',
                              hintStyle: TextStyle(
                                fontSize: 13,
                                color: cs.onSurfaceVariant.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                size: 18,
                                color: cs.onSurfaceVariant,
                              ),
                              suffixIcon:
                                  _textController.text.isNotEmpty
                                      ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // Issue 18: Whole Word Search Toggle
                                          Tooltip(
                                            message: 'Match whole word',
                                            child: InkWell(
                                              onTap: () {
                                                sc.wholeWord = !sc.wholeWord;
                                                // Retrigger search with new mode
                                                _onQueryChanged(
                                                  _textController.text,
                                                );
                                                _focusNode.requestFocus();
                                              },
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color:
                                                      sc.wholeWord
                                                          ? cs.primaryContainer
                                                          : Colors.transparent,
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  '[W]',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                    color:
                                                        sc.wholeWord
                                                            ? cs.onPrimaryContainer
                                                            : cs.onSurfaceVariant,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            icon: Icon(
                                              Icons.clear_rounded,
                                              size: 16,
                                              color: cs.onSurfaceVariant,
                                            ),
                                            onPressed: () {
                                              _textController.clear();
                                              sc.clearSearch();
                                              setState(() {});
                                              _focusNode.requestFocus();
                                            },
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                        ],
                                      )
                                      : null,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor:
                                  isDark
                                      ? cs.surfaceContainerHighest
                                      : cs.surfaceContainerHigh,
                            ),
                            textInputAction: TextInputAction.search,
                            // Issue 19: Use native onSubmitted for virtual keyboards
                            onSubmitted: (query) {
                              if (query.isNotEmpty) {
                                sc.searchDocuments(
                                  widget.docs,
                                  query,
                                  startPageIndex: widget.selectedPageIndex,
                                );
                              }
                              _focusNode.requestFocus();
                            },
                            onChanged: _onQueryChanged, // (O) Debounced
                          ),
                        ),
                      ),

                      // (M) Progress indicator during search
                      if (sc.isSearching) ...[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value:
                                sc.searchProgress > 0
                                    ? sc.searchProgress
                                    : null,
                            minHeight: 3,
                            backgroundColor: cs.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation(
                              cs.primary.withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Searching page ${sc.pagesSearched}'
                          ' / ${sc.totalPagesToSearch}…',
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                          ),
                        ),
                      ],

                      // Results nav
                      if (sc.hasMatches) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton.filledTonal(
                              onPressed: _goToPrevious,
                              icon: const Icon(
                                Icons.keyboard_arrow_up_rounded,
                                size: 18,
                              ),
                              tooltip: 'Previous (Shift+Enter)',
                              visualDensity: VisualDensity.compact,
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: cs.tertiaryContainer.withValues(
                                  alpha: 0.7,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${sc.currentIndex + 1} / ${sc.matchCount}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onTertiaryContainer,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              onPressed: _goToNext,
                              icon: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 18,
                              ),
                              tooltip: 'Next (Enter)',
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),

                        // 📄 Per-document match breakdown (multi-doc)
                        if (widget.docs.length >= 2) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            alignment: WrapAlignment.center,
                            children:
                                widget.docs.asMap().entries.map((entry) {
                                  final idx = entry.key;
                                  final doc = entry.value;
                                  final docMatches = sc.matchCountForDocument(
                                    doc.id,
                                  );
                                  final isCurrent =
                                      sc.currentMatch?.documentId == doc.id;
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          isCurrent
                                              ? cs.primaryContainer.withValues(
                                                alpha: 0.7,
                                              )
                                              : cs.surfaceContainerHighest
                                                  .withValues(alpha: 0.6),
                                      borderRadius: BorderRadius.circular(6),
                                      border:
                                          isCurrent
                                              ? Border.all(
                                                color: cs.primary.withValues(
                                                  alpha: 0.4,
                                                ),
                                              )
                                              : null,
                                    ),
                                    child: Text(
                                      'PDF ${idx + 1}: $docMatches',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight:
                                            isCurrent
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                        color:
                                            isCurrent
                                                ? cs.primary
                                                : cs.onSurfaceVariant,
                                      ),
                                    ),
                                  );
                                }).toList(),
                          ),
                        ],
                      ],

                      // No results
                      if (!sc.hasMatches &&
                          !sc.isSearching &&
                          sc.query.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'No results found',
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// 🏷️ ANNOTATE PANEL — Floating anchored dialog
// =============================================================================

class _PdfAnnotatePanel extends StatefulWidget {
  final Rect anchor;
  final PdfAnnotationController annotationController;
  final int selectedPageIndex;
  final CommandHistory? history;
  final VoidCallback? onLayoutChanged;

  const _PdfAnnotatePanel({
    required this.anchor,
    required this.annotationController,
    required this.selectedPageIndex,
    this.history,
    this.onLayoutChanged,
  });

  @override
  State<_PdfAnnotatePanel> createState() => _PdfAnnotatePanelState();
}

class _PdfAnnotatePanelState extends State<_PdfAnnotatePanel> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ac = widget.annotationController;

    return Stack(
      children: [
        GestureDetector(onTap: () => Navigator.pop(context)),
        Positioned(
          left: (widget.anchor.left - 60).clamp(
            8,
            MediaQuery.of(context).size.width - 288,
          ),
          top: widget.anchor.bottom + 8,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(16),
            color: isDark ? cs.surfaceContainerHigh : cs.surfaceContainerLow,
            child: Container(
              width: 280,
              padding: const EdgeInsets.all(12),
              child: ListenableBuilder(
                listenable: ac,
                builder: (context, _) {
                  final pageAnnotations = ac.annotationsForPage(
                    widget.selectedPageIndex,
                  );

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          Icon(
                            Icons.edit_note_rounded,
                            size: 18,
                            color: cs.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Annotations',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                          ),
                          const Spacer(),
                          if (pageAnnotations.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: cs.primaryContainer.withValues(
                                  alpha: 0.5,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${pageAnnotations.length}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onPrimaryContainer,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Type picker
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children:
                            PdfAnnotationType.values.map((type) {
                              final isActive = ac.activeType == type;
                              return GestureDetector(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  ac.activeType = type;
                                  ac.activeColor = type.defaultColor;
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        isActive
                                            ? cs.primaryContainer.withValues(
                                              alpha: 0.7,
                                            )
                                            : (isDark
                                                ? cs.surfaceContainerHighest
                                                : cs.surfaceContainerHigh),
                                    borderRadius: BorderRadius.circular(10),
                                    border:
                                        isActive
                                            ? Border.all(
                                              color: cs.primary.withValues(
                                                alpha: 0.4,
                                              ),
                                            )
                                            : null,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _annotationIcon(type),
                                        size: 18,
                                        color:
                                            isActive
                                                ? cs.primary
                                                : cs.onSurfaceVariant,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        type.name,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight:
                                              isActive
                                                  ? FontWeight.w600
                                                  : FontWeight.w400,
                                          color:
                                              isActive
                                                  ? cs.primary
                                                  : cs.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                      ),
                      const SizedBox(height: 10),

                      // Color + clear
                      Row(
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: ac.activeColor,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: cs.outlineVariant.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Page ${widget.selectedPageIndex + 1}',
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const Spacer(),
                          if (pageAnnotations.isNotEmpty)
                            TextButton.icon(
                              onPressed: () {
                                HapticFeedback.heavyImpact();
                                ac.clearPage(widget.selectedPageIndex);
                                widget.onLayoutChanged?.call();
                              },
                              icon: const Icon(
                                Icons.clear_all_rounded,
                                size: 14,
                              ),
                              label: const Text(
                                'Clear',
                                style: TextStyle(fontSize: 11),
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: cs.error,
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                              ),
                            ),
                        ],
                      ),

                      // Undo/redo
                      if (widget.history != null) ...[
                        const SizedBox(height: 8),
                        ValueListenableBuilder<int>(
                          valueListenable: widget.history!.revision,
                          builder: (context, _, __) {
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton.filledTonal(
                                  onPressed:
                                      widget.history!.canUndo
                                          ? () {
                                            widget.history!.undo();
                                            widget.onLayoutChanged?.call();
                                          }
                                          : null,
                                  icon: const Icon(
                                    Icons.undo_rounded,
                                    size: 16,
                                  ),
                                  tooltip: widget.history!.undoLabel ?? 'Undo',
                                  visualDensity: VisualDensity.compact,
                                ),
                                const SizedBox(width: 8),
                                IconButton.filledTonal(
                                  onPressed:
                                      widget.history!.canRedo
                                          ? () {
                                            widget.history!.redo();
                                            widget.onLayoutChanged?.call();
                                          }
                                          : null,
                                  icon: const Icon(
                                    Icons.redo_rounded,
                                    size: 16,
                                  ),
                                  tooltip: widget.history!.redoLabel ?? 'Redo',
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  IconData _annotationIcon(PdfAnnotationType type) {
    switch (type) {
      case PdfAnnotationType.highlight:
        return Icons.highlight_rounded;
      case PdfAnnotationType.underline:
        return Icons.format_underlined_rounded;
      case PdfAnnotationType.stickyNote:
        return Icons.sticky_note_2_rounded;
      case PdfAnnotationType.stamp:
        return Icons.approval_rounded;
    }
  }
}

// =============================================================================
// ⚙️ LAYOUT PANEL — Floating anchored dialog
// =============================================================================

class _PdfLayoutPanel extends StatefulWidget {
  final Rect anchor;
  final PdfDocumentNode doc;
  final VoidCallback? onLayoutChanged;

  const _PdfLayoutPanel({
    required this.anchor,
    required this.doc,
    this.onLayoutChanged,
  });

  @override
  State<_PdfLayoutPanel> createState() => _PdfLayoutPanelState();
}

class _PdfLayoutPanelState extends State<_PdfLayoutPanel> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final doc = widget.doc;
    final cols = doc.documentModel.gridColumns;
    final spacing = doc.documentModel.gridSpacing;

    // Detect active preset
    PdfLayoutPreset? activePreset;
    final allUnlocked = doc.pageNodes.every((p) => !p.pageModel.isLocked);
    if (allUnlocked) {
      activePreset = PdfLayoutPreset.freeform;
    } else if (cols == 1 && spacing <= 15) {
      activePreset = PdfLayoutPreset.reading;
    } else if (cols == 1 && spacing > 50) {
      activePreset = PdfLayoutPreset.single;
    } else if (cols == 2) {
      activePreset = PdfLayoutPreset.standard;
    } else if (cols >= 3) {
      activePreset = PdfLayoutPreset.overview;
    }

    return Stack(
      children: [
        GestureDetector(onTap: () => Navigator.pop(context)),
        Positioned(
          left: (widget.anchor.left - 80).clamp(
            8,
            MediaQuery.of(context).size.width - 308,
          ),
          top: widget.anchor.bottom + 8,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(16),
            color: isDark ? cs.surfaceContainerHigh : cs.surfaceContainerLow,
            child: Container(
              width: 300,
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Row(
                    children: [
                      Icon(
                        Icons.grid_view_rounded,
                        size: 18,
                        color: cs.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Layout',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${cols}col',
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Presets
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children:
                        PdfLayoutPreset.values.map((preset) {
                          final isActive = preset == activePreset;
                          return GestureDetector(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              doc.applyLayoutPreset(preset);
                              widget.onLayoutChanged?.call();
                              setState(() {});
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    isActive
                                        ? cs.primaryContainer
                                        : (isDark
                                            ? cs.surfaceContainerHighest
                                            : cs.surfaceContainerHigh),
                                borderRadius: BorderRadius.circular(10),
                                border:
                                    isActive
                                        ? Border.all(
                                          color: cs.primary.withValues(
                                            alpha: 0.4,
                                          ),
                                        )
                                        : null,
                              ),
                              child: Text(
                                '${preset.icon} ${preset.label}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight:
                                      isActive
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                  color:
                                      isActive
                                          ? cs.onPrimaryContainer
                                          : cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                  ),
                  const SizedBox(height: 10),

                  // Grid columns
                  Row(
                    children: [
                      ...List.generate(4, (i) {
                        final c = i + 1;
                        return Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Material(
                            color:
                                cols == c
                                    ? cs.primary
                                    : (isDark
                                        ? cs.surfaceContainerHighest
                                        : cs.surfaceContainerHigh),
                            borderRadius: BorderRadius.circular(8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                HapticFeedback.selectionClick();
                                doc.setGridColumns(c);
                                widget.onLayoutChanged?.call();
                                setState(() {});
                              },
                              child: SizedBox(
                                width: 32,
                                height: 32,
                                child: Center(
                                  child: Text(
                                    '$c',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color:
                                          cols == c
                                              ? cs.onPrimary
                                              : cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                      const SizedBox(width: 8),
                      // Spacing
                      Expanded(
                        child: Row(
                          children: [
                            Icon(
                              Icons.space_bar_rounded,
                              size: 14,
                              color: cs.onSurfaceVariant,
                            ),
                            Expanded(
                              child: SliderTheme(
                                data: SliderThemeData(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 5,
                                  ),
                                  overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 12,
                                  ),
                                  activeTrackColor: cs.primary,
                                  inactiveTrackColor:
                                      cs.surfaceContainerHighest,
                                  thumbColor: cs.primary,
                                ),
                                child: Slider(
                                  value: spacing,
                                  min: 0,
                                  max: 100,
                                  onChanged: (v) {
                                    doc.setGridSpacing(v);
                                    widget.onLayoutChanged?.call();
                                    setState(() {});
                                  },
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 24,
                              child: Text(
                                '${spacing.toInt()}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: cs.onSurfaceVariant,
                                ),
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
