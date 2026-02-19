import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/models/pdf_layout_preset.dart';
import '../../core/nodes/pdf_document_node.dart';
import '../../tools/pdf/pdf_text_selection_controller.dart';

// ============================================================================
// 📄 PDF CONTEXTUAL TOOLBAR — Appears when a PDF document is active
// ============================================================================

/// Contextual toolbar for PDF document interaction.
///
/// Shows layout presets, grid column selector, spacing slider,
/// page actions (rotate, lock/unlock), and page navigation info.
///
/// DESIGN: Material Design 3 bottom bar with glassmorphism, matching
/// the style of the main canvas toolbar.
class PdfContextualToolbar extends StatefulWidget {
  /// The active PDF document node.
  final PdfDocumentNode? documentNode;

  /// Callback to trigger a canvas repaint after layout changes.
  final VoidCallback? onLayoutChanged;

  /// Callback when the toolbar should close.
  final VoidCallback? onClose;

  /// Current page index (0-based) for page indicator.
  final int? currentPageIndex;

  /// Callback when a page is deleted.
  final void Function(int pageIndex)? onPageDeleted;

  /// Text selection controller for toggling selection mode.
  final PdfTextSelectionController? textSelectionController;

  /// Callback when user taps export (annotated PDF).
  final VoidCallback? onExport;

  const PdfContextualToolbar({
    super.key,
    required this.documentNode,
    this.onLayoutChanged,
    this.onClose,
    this.currentPageIndex,
    this.onPageDeleted,
    this.textSelectionController,
    this.onExport,
  });

  @override
  State<PdfContextualToolbar> createState() => _PdfContextualToolbarState();
}

class _PdfContextualToolbarState extends State<PdfContextualToolbar>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  PdfDocumentNode? get _doc => widget.documentNode;

  /// Currently selected page index for page-specific actions.
  int _selectedPageIndex = 0;

  @override
  Widget build(BuildContext context) {
    if (_doc == null) return const SizedBox.shrink();

    // F2: Clamp before any child builder accesses _selectedPageIndex
    final totalPages = _doc!.documentModel.totalPages;
    if (totalPages > 0) {
      _selectedPageIndex = _selectedPageIndex.clamp(0, totalPages - 1);
    } else {
      _selectedPageIndex = 0;
    }

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SlideTransition(
      position: _slideAnimation,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color:
              isDark
                  ? cs.surfaceContainerHighest.withValues(alpha: 0.95)
                  : cs.surfaceContainerLow.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header with page info and close ─────────────────────────
            _buildHeader(cs),
            const SizedBox(height: 10),

            // ── Page actions (rotate, lock, annotations) ────────────────
            _buildPageActions(cs, isDark),
            const SizedBox(height: 10),

            // ── Layout presets ──────────────────────────────────────────
            _buildLayoutPresets(cs, isDark),
            const SizedBox(height: 10),

            // ── Grid columns + spacing ─────────────────────────────────
            _buildGridControls(cs, isDark),
            const SizedBox(height: 10),

            // ── Export annotated ─────────────────────────────────────────
            if (widget.onExport != null) _buildExportButton(cs, isDark),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header
  // ---------------------------------------------------------------------------

  Widget _buildHeader(ColorScheme cs) {
    final totalPages = _doc!.documentModel.totalPages;
    final currentPage = _selectedPageIndex + 1;

    return Row(
      children: [
        Icon(Icons.picture_as_pdf_rounded, color: cs.primary, size: 20),
        const SizedBox(width: 8),
        Text(
          'PDF',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(width: 8),

        // Page navigator: prev / indicator / next
        _PageNavButton(
          icon: Icons.chevron_left_rounded,
          enabled: _selectedPageIndex > 0,
          cs: cs,
          onTap: () {
            setState(() => _selectedPageIndex--);
          },
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: cs.primaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$currentPage / $totalPages',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: cs.onPrimaryContainer,
            ),
          ),
        ),
        _PageNavButton(
          icon: Icons.chevron_right_rounded,
          enabled: _selectedPageIndex < totalPages - 1,
          cs: cs,
          onTap: () {
            setState(() => _selectedPageIndex++);
          },
        ),

        const Spacer(),
        // Grid info
        Text(
          '${_doc!.documentModel.gridColumns} col',
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
        ),
        const SizedBox(width: 12),
        // Close button
        GestureDetector(
          onTap: widget.onClose,
          child: Icon(
            Icons.close_rounded,
            size: 20,
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Page actions row
  // ---------------------------------------------------------------------------

  Widget _buildPageActions(ColorScheme cs, bool isDark) {
    final page = _doc!.pageAt(_selectedPageIndex);
    if (page == null) return const SizedBox.shrink();

    final isLocked = page.pageModel.isLocked;
    final showAnnotations = page.pageModel.showAnnotations;
    final annotationCount = page.pageModel.annotations.length;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Rotate CCW
        _ActionButton(
          icon: Icons.rotate_left_rounded,
          label: '−90°',
          cs: cs,
          isDark: isDark,
          onTap: () {
            HapticFeedback.lightImpact();
            _doc!.rotatePage(_selectedPageIndex, angleDegrees: -90);
            widget.onLayoutChanged?.call();
            setState(() {});
          },
        ),

        // Rotate CW
        _ActionButton(
          icon: Icons.rotate_right_rounded,
          label: '+90°',
          cs: cs,
          isDark: isDark,
          onTap: () {
            HapticFeedback.lightImpact();
            _doc!.rotatePage(_selectedPageIndex, angleDegrees: 90);
            widget.onLayoutChanged?.call();
            setState(() {});
          },
        ),

        // Lock / Unlock toggle
        _ActionButton(
          icon: isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
          label: isLocked ? 'Locked' : 'Free',
          isActive: !isLocked,
          cs: cs,
          isDark: isDark,
          onTap: () {
            HapticFeedback.mediumImpact();
            _doc!.togglePageLock(_selectedPageIndex);
            widget.onLayoutChanged?.call();
            setState(() {});
          },
        ),

        // Annotations toggle
        _ActionButton(
          icon:
              showAnnotations
                  ? Icons.edit_note_rounded
                  : Icons.edit_off_rounded,
          label: annotationCount > 0 ? '$annotationCount' : 'Ann.',
          isActive: showAnnotations,
          cs: cs,
          isDark: isDark,
          onTap: () {
            HapticFeedback.selectionClick();
            _doc!.togglePageAnnotations(_selectedPageIndex);
            widget.onLayoutChanged?.call();
            setState(() {});
          },
        ),

        // Text selection toggle
        if (widget.textSelectionController != null)
          _ActionButton(
            icon: Icons.text_fields_rounded,
            label: 'Text',
            isActive: widget.textSelectionController!.isActive,
            cs: cs,
            isDark: isDark,
            onTap: () {
              HapticFeedback.selectionClick();
              widget.textSelectionController!.toggle();
              widget.onLayoutChanged?.call();
              setState(() {});
            },
          ),

        // Copy selected text (only if selection active)
        if (widget.textSelectionController != null &&
            widget.textSelectionController!.selection.isNotEmpty)
          _ActionButton(
            icon: Icons.copy_rounded,
            label: 'Copy',
            cs: cs,
            isDark: isDark,
            onTap: () {
              HapticFeedback.mediumImpact();
              widget.textSelectionController!.copyToClipboard();
            },
          ),

        // Delete page
        if (widget.onPageDeleted != null && _doc!.pageNodes.length > 1)
          _ActionButton(
            icon: Icons.delete_outline_rounded,
            label: 'Delete',
            cs: cs,
            isDark: isDark,
            onTap: () {
              HapticFeedback.heavyImpact();
              widget.onPageDeleted!(_selectedPageIndex);
              if (_selectedPageIndex >= _doc!.pageNodes.length) {
                _selectedPageIndex = _doc!.pageNodes.length - 1;
              }
              widget.onLayoutChanged?.call();
              setState(() {});
            },
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Export button
  // ---------------------------------------------------------------------------

  Widget _buildExportButton(ColorScheme cs, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SizedBox(
        width: double.infinity,
        height: 40,
        child: FilledButton.tonalIcon(
          onPressed: () {
            HapticFeedback.mediumImpact();
            widget.onExport?.call();
          },
          icon: const Icon(Icons.ios_share_rounded, size: 18),
          label: const Text(
            'Export Annotated',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Layout presets row
  // ---------------------------------------------------------------------------

  Widget _buildLayoutPresets(ColorScheme cs, bool isDark) {
    final currentCols = _doc!.documentModel.gridColumns;

    // Determine which preset is currently active
    PdfLayoutPreset? activePreset;
    final allLocked = _doc!.pageNodes.every((p) => p.pageModel.isLocked);
    final allUnlocked = _doc!.pageNodes.every((p) => !p.pageModel.isLocked);

    if (allUnlocked) {
      activePreset = PdfLayoutPreset.freeform;
    } else if (currentCols == 1 && _doc!.documentModel.gridSpacing <= 15) {
      activePreset = PdfLayoutPreset.reading;
    } else if (currentCols == 1 && _doc!.documentModel.gridSpacing > 50) {
      activePreset = PdfLayoutPreset.single;
    } else if (currentCols == 2) {
      activePreset = PdfLayoutPreset.standard;
    } else if (currentCols >= 3) {
      activePreset = PdfLayoutPreset.overview;
    }

    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children:
            PdfLayoutPreset.values.map((preset) {
              final isActive = preset == activePreset;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _PresetChip(
                  label: preset.label,
                  icon: preset.icon,
                  isActive: isActive,
                  isDark: isDark,
                  cs: cs,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _doc!.applyLayoutPreset(preset);
                    widget.onLayoutChanged?.call();
                    setState(() {});
                  },
                ),
              );
            }).toList(),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Grid controls (columns + spacing)
  // ---------------------------------------------------------------------------

  Widget _buildGridControls(ColorScheme cs, bool isDark) {
    final cols = _doc!.documentModel.gridColumns;
    final spacing = _doc!.documentModel.gridSpacing;

    return Row(
      children: [
        // Column buttons (1-4)
        ...[1, 2, 3, 4].map(
          (c) => Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _ColumnButton(
              value: c,
              isActive: cols == c,
              cs: cs,
              isDark: isDark,
              onTap: () {
                HapticFeedback.selectionClick();
                _doc!.setGridColumns(c);
                widget.onLayoutChanged?.call();
                setState(() {});
              },
            ),
          ),
        ),

        const SizedBox(width: 8),

        // Spacing slider
        Expanded(
          child: Row(
            children: [
              Icon(
                Icons.space_bar_rounded,
                size: 16,
                color: cs.onSurfaceVariant,
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 14,
                    ),
                    activeTrackColor: cs.primary,
                    inactiveTrackColor: cs.surfaceContainerHighest,
                    thumbColor: cs.primary,
                  ),
                  child: Slider(
                    value: spacing,
                    min: 0,
                    max: 100,
                    onChanged: (v) {
                      _doc!.setGridSpacing(v);
                      widget.onLayoutChanged?.call();
                      setState(() {});
                    },
                  ),
                ),
              ),
              SizedBox(
                width: 32,
                child: Text(
                  '${spacing.toInt()}',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Private sub-widgets
// =============================================================================

/// Chip widget for layout preset selection.
class _PresetChip extends StatelessWidget {
  final String label;
  final String icon;
  final bool isActive;
  final bool isDark;
  final ColorScheme cs;
  final VoidCallback onTap;

  const _PresetChip({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.isDark,
    required this.cs,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color:
              isActive
                  ? cs.primaryContainer
                  : (isDark
                      ? cs.surfaceContainerHigh
                      : cs.surfaceContainerHighest),
          borderRadius: BorderRadius.circular(12),
          border:
              isActive
                  ? Border.all(color: cs.primary.withValues(alpha: 0.5))
                  : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? cs.onPrimaryContainer : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Button for column count selection.
class _ColumnButton extends StatelessWidget {
  final int value;
  final bool isActive;
  final ColorScheme cs;
  final bool isDark;
  final VoidCallback onTap;

  const _ColumnButton({
    required this.value,
    required this.isActive,
    required this.cs,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color:
              isActive
                  ? cs.primary
                  : (isDark
                      ? cs.surfaceContainerHigh
                      : cs.surfaceContainerHighest),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '$value',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isActive ? cs.onPrimary : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Small chevron button for page navigation.
class _PageNavButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final ColorScheme cs;
  final VoidCallback onTap;

  const _PageNavButton({
    required this.icon,
    required this.enabled,
    required this.cs,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Icon(
          icon,
          size: 20,
          color: enabled ? cs.onSurface : cs.onSurface.withValues(alpha: 0.25),
        ),
      ),
    );
  }
}

/// Action button with icon and label for page actions.
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final ColorScheme cs;
  final bool isDark;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.isActive = false,
    required this.cs,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color:
              isActive
                  ? cs.primaryContainer.withValues(alpha: 0.7)
                  : (isDark
                      ? cs.surfaceContainerHigh
                      : cs.surfaceContainerHighest),
          borderRadius: BorderRadius.circular(10),
          border:
              isActive
                  ? Border.all(color: cs.primary.withValues(alpha: 0.4))
                  : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
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
}
