library pdf_contextual_toolbar;

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

part 'pdf_toolbar_panels.dart';


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
