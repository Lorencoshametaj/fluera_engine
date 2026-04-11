part of 'professional_canvas_toolbar.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 🛠️ Toolbar Tools Area — Helper Widgets
// ═══════════════════════════════════════════════════════════════════════════

/// 📄 PDF toggle button — shows active/inactive state with icon swap and glow.
class _PdfToggleButton extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String tooltip;
  final bool isActive;
  final bool isDark;
  final Color? activeColor;
  final VoidCallback onTap;

  const _PdfToggleButton({
    required this.icon,
    required this.activeIcon,
    required this.tooltip,
    required this.isActive,
    required this.isDark,
    this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color =
        isActive
            ? (activeColor ?? cs.primary)
            : (isDark ? Colors.white54 : Colors.black45);

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color:
                  isActive ? color.withValues(alpha: 0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color:
                    isActive
                        ? color.withValues(alpha: 0.3)
                        : Colors.transparent,
              ),
            ),
            child: Icon(isActive ? activeIcon : icon, size: 18, color: color),
          ),
        ),
      ),
    );
  }
}

/// 📄 PDF toolbar group — labelled card mirroring `_ExcelGroup`.
class _PdfGroup extends StatelessWidget {
  final String label;
  final bool isDark;
  final List<Widget> children;

  const _PdfGroup({
    required this.label,
    required this.isDark,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    // Intersperse spacing between children
    final spaced = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) spaced.add(const SizedBox(width: 4));
      spaced.add(children[i]);
    }

    return Container(
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
      decoration: BoxDecoration(
        color:
            isDark
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color:
              isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
          width: 0.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: spaced),
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 1),
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                color:
                    isDark
                        ? Colors.white.withValues(alpha: 0.30)
                        : Colors.black.withValues(alpha: 0.30),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact PDF toolbar button with optional badge.
/// Captures its render box and passes the [Rect] to [onTap].
class _PdfToolbarButton extends StatelessWidget {
  final IconData icon;
  final IconData? secondaryIcon;
  final String tooltip;
  final String? badge;
  final bool isDark;
  final Color? accentColor;
  final void Function(Rect anchor) onTap;

  const _PdfToolbarButton({
    required this.icon,
    this.secondaryIcon,
    required this.tooltip,
    this.badge,
    required this.isDark,
    this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = accentColor ?? cs.primary;

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            HapticFeedback.selectionClick();
            final box = context.findRenderObject() as RenderBox;
            final pos = box.localToGlobal(Offset.zero);
            onTap(pos & box.size);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.15)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: color),
                if (secondaryIcon != null) ...[
                  const SizedBox(width: 3),
                  Icon(secondaryIcon!, size: 18, color: color),
                ],
                if (badge != null) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badge!,
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
    );
  }
}

/// 📄 Compact PDF document switcher — dropdown chip to select the active PDF.
///
/// Shows the current PDF's label (name or "PDF N") and a dropdown arrow.
/// Tapping opens a popup menu listing all loaded PDFs so the user can switch.
class _PdfDocumentSwitcher extends StatelessWidget {
  final List<PdfDocumentNode> documents;
  final String? activeDocumentId;
  final bool isDark;
  final void Function(String documentId) onDocumentSelected;

  const _PdfDocumentSwitcher({
    required this.documents,
    required this.activeDocumentId,
    required this.isDark,
    required this.onDocumentSelected,
  });

  String _labelFor(PdfDocumentNode doc, int index) {
    final name = doc.name;
    if (name.isNotEmpty) return name;
    return 'PDF ${index + 1}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Find active index for display label
    final activeIdx = documents.indexWhere((d) => d.id == activeDocumentId);
    final activeLabel =
        activeIdx >= 0 ? _labelFor(documents[activeIdx], activeIdx) : 'PDF 1';

    return PopupMenuButton<String>(
      tooltip: 'Switch PDF',
      onSelected: onDocumentSelected,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
      itemBuilder: (context) {
        return [
          for (int i = 0; i < documents.length; i++)
            PopupMenuItem<String>(
              value: documents[i].id,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    documents[i].id == activeDocumentId
                        ? Icons.picture_as_pdf_rounded
                        : Icons.picture_as_pdf_outlined,
                    size: 16,
                    color:
                        documents[i].id == activeDocumentId
                            ? cs.primary
                            : (isDark ? Colors.white70 : Colors.black54),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _labelFor(documents[i], i),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            documents[i].id == activeDocumentId
                                ? FontWeight.w700
                                : FontWeight.w400,
                        color:
                            documents[i].id == activeDocumentId
                                ? cs.primary
                                : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${documents[i].documentModel.totalPages}p',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ],
              ),
            ),
        ];
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 160),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: cs.primaryContainer.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.picture_as_pdf_rounded, size: 14, color: cs.primary),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  activeLabel,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.primary,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.arrow_drop_down, size: 16, color: cs.primary),
            ],
          ),
        ),
      ),
    );
  }
}

/// 📄 PDF "More Actions" popup — exposes less-common functions.
class _PdfMoreActions extends StatelessWidget {
  final PdfDocumentNode doc;
  final int selectedPageIndex;
  final bool isDark;
  final bool showPageNumbers;
  final VoidCallback? onLayoutChanged;
  final VoidCallback? onTogglePageNumbers;
  final ValueChanged<int>? onPageIndexChanged;

  const _PdfMoreActions({
    required this.doc,
    required this.selectedPageIndex,
    required this.isDark,
    required this.showPageNumbers,
    this.onLayoutChanged,
    this.onTogglePageNumbers,
    this.onPageIndexChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final page = doc.pageAt(selectedPageIndex);
    final annotationsVisible = page?.pageModel.showAnnotations ?? true;
    final isUnlocked = page != null && !page.pageModel.isLocked;
    final totalPages = doc.documentModel.totalPages;

    return PopupMenuButton<String>(
      tooltip: 'More Actions',
      icon: Icon(
        Icons.more_vert_rounded,
        size: 20,
        color: isDark ? Colors.white70 : Colors.black54,
      ),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 8,
      onSelected: (action) {
        HapticFeedback.selectionClick();
        switch (action) {
          case 'toggle_annotations':
            doc.togglePageAnnotations(selectedPageIndex);
            onLayoutChanged?.call();
          case 'return_to_grid':
            doc.returnPageToGrid(selectedPageIndex);
            onLayoutChanged?.call();
          case 'move_up':
            if (selectedPageIndex > 0) {
              doc.reorderPage(selectedPageIndex, selectedPageIndex - 1);
              onPageIndexChanged?.call(selectedPageIndex - 1);
              onLayoutChanged?.call();
            }
          case 'move_down':
            if (selectedPageIndex < totalPages - 1) {
              doc.reorderPage(selectedPageIndex, selectedPageIndex + 1);
              onPageIndexChanged?.call(selectedPageIndex + 1);
              onLayoutChanged?.call();
            }
          case 'toggle_page_numbers':
            onTogglePageNumbers?.call();
        }
      },
      itemBuilder:
          (_) => [
            PopupMenuItem(
              value: 'toggle_annotations',
              child: Row(
                children: [
                  Icon(
                    annotationsVisible
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    size: 18,
                    color: cs.onSurface,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    annotationsVisible
                        ? 'Hide Annotations'
                        : 'Show Annotations',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
            if (isUnlocked)
              PopupMenuItem(
                value: 'return_to_grid',
                child: Row(
                  children: [
                    Icon(Icons.grid_on_rounded, size: 18, color: cs.onSurface),
                    const SizedBox(width: 10),
                    const Text(
                      'Return to Grid',
                      style: TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            const PopupMenuDivider(),
            PopupMenuItem(
              enabled: selectedPageIndex > 0,
              value: 'move_up',
              child: Row(
                children: [
                  Icon(
                    Icons.arrow_upward_rounded,
                    size: 18,
                    color:
                        selectedPageIndex > 0
                            ? cs.onSurface
                            : cs.onSurface.withValues(alpha: 0.3),
                  ),
                  const SizedBox(width: 10),
                  const Text('Move Page Up', style: TextStyle(fontSize: 13)),
                ],
              ),
            ),
            PopupMenuItem(
              enabled: selectedPageIndex < totalPages - 1,
              value: 'move_down',
              child: Row(
                children: [
                  Icon(
                    Icons.arrow_downward_rounded,
                    size: 18,
                    color:
                        selectedPageIndex < totalPages - 1
                            ? cs.onSurface
                            : cs.onSurface.withValues(alpha: 0.3),
                  ),
                  const SizedBox(width: 10),
                  const Text('Move Page Down', style: TextStyle(fontSize: 13)),
                ],
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'toggle_page_numbers',
              child: Row(
                children: [
                  Icon(
                    showPageNumbers ? Icons.numbers_rounded : Icons.tag_rounded,
                    size: 18,
                    color: cs.onSurface,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    showPageNumbers ? 'Hide Page Numbers' : 'Show Page Numbers',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
    );
  }
}

// =============================================================================
// 📊 EXCEL TAB — SUPPORTING WIDGETS
// =============================================================================

/// Row with label, slider, and value display for custom table sizing.
class _CustomSizeRow extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final Color color;
  final ValueChanged<int> onChanged;

  const _CustomSizeRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: color,
              thumbColor: color,
              inactiveTrackColor: color.withValues(alpha: 0.15),
              overlayColor: color.withValues(alpha: 0.1),
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: value.toDouble(),
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: max - min,
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
        ),
        Container(
          width: 36,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$value',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

/// 📊 Formula bar text field with Tab key support.
///
/// Tab → saves value and moves selection right.
/// Enter → saves value and moves selection down.
class _FormulaBarField extends StatefulWidget {
  final String cellRef;
  final String initialValue;
  final ValueChanged<String> onSubmit;
  final ValueChanged<String> onTab;

  const _FormulaBarField({
    required this.cellRef,
    required this.initialValue,
    required this.onSubmit,
    required this.onTab,
  });

  @override
  State<_FormulaBarField> createState() => _FormulaBarFieldState();
}

class _FormulaBarFieldState extends State<_FormulaBarField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode = FocusNode();
    // Auto-focus
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant _FormulaBarField old) {
    super.didUpdateWidget(old);
    if (old.cellRef != widget.cellRef) {
      _controller.text = widget.initialValue;
      _controller.selection = TextSelection.collapsed(
        offset: widget.initialValue.length,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return KeyboardListener(
      focusNode: FocusNode(), // Wrapper focus — forwards to TextField
      onKeyEvent: (event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.tab) {
          widget.onTab(_controller.text);
        }
      },
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Type value or =formula…',
          hintStyle: TextStyle(
            fontSize: 12,
            color: cs.onSurface.withValues(alpha: 0.35),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.3)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: cs.primary, width: 1.5),
          ),
          isDense: true,
          suffixIcon: IconButton(
            icon: Icon(Icons.check_rounded, size: 18, color: cs.primary),
            onPressed: () => widget.onSubmit(_controller.text),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ),
        onSubmitted: (value) => widget.onSubmit(value),
      ),
    );
  }
}

/// 📊 Compact toolbar icon button with press-scale micro-animation and haptic.
class _ToolbarIconBtn extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final bool isActive;
  final Color? color;
  final VoidCallback? onPressed;

  const _ToolbarIconBtn({
    required this.icon,
    required this.tooltip,
    this.isActive = false,
    this.color,
    this.onPressed,
  });

  @override
  State<_ToolbarIconBtn> createState() => _ToolbarIconBtnState();
}

class _ToolbarIconBtnState extends State<_ToolbarIconBtn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: ToolbarTokens.animFast);
    _scale = Tween(
      begin: 1.0,
      end: 0.82,
    ).animate(CurvedAnimation(parent: _ctrl, curve: ToolbarTokens.curveActive));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = widget.onPressed != null;
    return GestureDetector(
      onTapDown: enabled ? (_) => _ctrl.forward() : null,
      onTapUp:
          enabled
              ? (_) {
                _ctrl.reverse();
                HapticFeedback.selectionClick();
                widget.onPressed!();
              }
              : null,
      onTapCancel: () => _ctrl.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder:
            (_, child) => Transform.scale(scale: _scale.value, child: child),
        child: SizedBox(
          width: 32,
          height: 32,
          child: AnimatedContainer(
            duration: ToolbarTokens.animFast,
            decoration: BoxDecoration(
              color:
                  widget.isActive
                      ? cs.primary.withValues(alpha: 0.15)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              widget.icon,
              size: 18,
              color:
                  widget.color ??
                  (widget.isActive
                      ? cs.primary
                      : (Theme.of(context).brightness == Brightness.dark
                          ? Colors.white70
                          : Colors.black54)),
            ),
          ),
        ),
      ),
    );
  }
}

/// 📊 Thin vertical divider for toolbar groups.
class _ToolbarDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Container(
        width: 1,
        height: 20,
        color: Theme.of(
          context,
        ).colorScheme.outlineVariant.withValues(alpha: 0.3),
      ),
    );
  }
}

/// 📊 Visual group card for Excel toolbar — wraps buttons with a label.
class _ExcelGroup extends StatelessWidget {
  final String label;
  final bool isDark;
  final List<Widget> children;

  const _ExcelGroup({
    required this.label,
    required this.isDark,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.fromLTRB(4, 3, 4, 1),
      decoration: BoxDecoration(
        color:
            isDark
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color:
              isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
          width: 0.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: children),
          Padding(
            padding: const EdgeInsets.only(top: 1, bottom: 1),
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                color:
                    isDark
                        ? Colors.white.withValues(alpha: 0.30)
                        : Colors.black.withValues(alpha: 0.30),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 📊 Excel toolbar button — press-scale + haptic, 40×38 with 22px icon.
class _ExcelBtn extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final bool isDark;
  final bool isActive;
  final bool isDestructive;
  final VoidCallback? onPressed;

  const _ExcelBtn({
    required this.icon,
    required this.tooltip,
    required this.isDark,
    this.isActive = false,
    this.isDestructive = false,
    this.onPressed,
  });

  @override
  State<_ExcelBtn> createState() => _ExcelBtnState();
}

class _ExcelBtnState extends State<_ExcelBtn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: ToolbarTokens.animFast);
    _scale = Tween(
      begin: 1.0,
      end: 0.80,
    ).animate(CurvedAnimation(parent: _ctrl, curve: ToolbarTokens.curveActive));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = widget.onPressed != null;

    Color iconColor;
    if (!enabled) {
      iconColor =
          widget.isDark
              ? Colors.white.withValues(alpha: 0.20)
              : Colors.black.withValues(alpha: 0.20);
    } else if (widget.isDestructive) {
      iconColor = cs.error;
    } else if (widget.isActive) {
      iconColor = cs.primary;
    } else {
      iconColor = widget.isDark ? Colors.white70 : Colors.black54;
    }

    return GestureDetector(
      onTapDown: enabled ? (_) => _ctrl.forward() : null,
      onTapUp:
          enabled
              ? (_) {
                _ctrl.reverse();
                HapticFeedback.selectionClick();
                widget.onPressed!();
              }
              : null,
      onTapCancel: () => _ctrl.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder:
            (_, child) => Transform.scale(scale: _scale.value, child: child),
        child: SizedBox(
          width: 40,
          height: 38,
          child: AnimatedContainer(
            duration: ToolbarTokens.animFast,
            decoration: BoxDecoration(
              color:
                  widget.isActive
                      ? cs.primary.withValues(alpha: 0.12)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(child: Icon(widget.icon, size: 22, color: iconColor)),
          ),
        ),
      ),
    );
  }
}

/// 📊 Color picker button with popup grid of preset colors.
class _ColorPickerBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color? currentColor;
  final ValueChanged<Color> onColorSelected;

  const _ColorPickerBtn({
    required this.icon,
    required this.tooltip,
    this.currentColor,
    required this.onColorSelected,
  });

  static const _presetColors = [
    Colors.black,
    Colors.white,
    Colors.red,
    Colors.pink,
    Colors.orange,
    Colors.amber,
    Colors.yellow,
    Colors.green,
    Colors.teal,
    Colors.blue,
    Colors.indigo,
    Colors.purple,
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: PopupMenuButton<Color>(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onSelected: onColorSelected,
        itemBuilder:
            (ctx) => [
              PopupMenuItem(
                enabled: false,
                child: SizedBox(
                  width: 180,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children:
                        _presetColors.map((c) {
                          final selected =
                              currentColor?.toARGB32() == c.toARGB32();
                          return GestureDetector(
                            onTap: () {
                              onColorSelected(c);
                              Navigator.of(ctx).pop();
                            },
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: c,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color:
                                      selected
                                          ? Colors.blue
                                          : Colors.grey.withValues(alpha: 0.3),
                                  width: selected ? 2.5 : 1,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                  ),
                ),
              ),
            ],
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16),
            Container(
              width: 16,
              height: 3,
              decoration: BoxDecoration(
                color: currentColor ?? Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 🎨 DESIGN TOOLBAR — Design tools, prototyping, inspect, responsive
// ============================================================================

extension _DesignToolsBuilder on _ProfessionalCanvasToolbarState {
  Widget _buildDesignTools(BuildContext context, bool isDark) {
    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          // ─── Prototype ───
          _DesignChipGroup(
            label: 'Prototype',
            icon: Icons.play_circle_outline_rounded,
            isDark: isDark,
            children: [
              _DesignActionChip(
                icon: Icons.play_arrow_rounded,
                label: 'Play',
                isDark: isDark,
                onTap: widget.onPrototypePlay,
              ),
              _DesignActionChip(
                icon: Icons.link_rounded,
                label: 'Flow',
                isDark: isDark,
                onTap: widget.onFlowLinkAdd,
              ),
            ],
          ),
          const SizedBox(width: 8),

          // ─── Animate ───
          _DesignChipGroup(
            label: 'Animate',
            icon: Icons.animation_rounded,
            isDark: isDark,
            children: [
              _DesignActionChip(
                icon: Icons.timeline_rounded,
                label: 'Timeline',
                isDark: isDark,
                onTap: widget.onAnimationTimeline,
              ),
              _DesignActionChip(
                icon: Icons.auto_fix_high_rounded,
                label: 'Smart',
                isDark: isDark,
                onTap: widget.onSmartAnimate,
              ),
            ],
          ),
          const SizedBox(width: 8),

          // ─── Inspect ───
          _DesignChipGroup(
            label: 'Inspect',
            icon: Icons.straighten_rounded,
            isDark: isDark,
            children: [
              _DesignActionChip(
                icon: Icons.space_bar_rounded,
                label: 'Measure',
                isDark: isDark,
                isActive: widget.isInspectActive,
                onTap: widget.onInspectToggle,
              ),
              _DesignActionChip(
                icon: Icons.code_rounded,
                label: 'Code',
                isDark: isDark,
                onTap: widget.onCodeGen,
              ),
              _DesignActionChip(
                icon: Icons.grid_on_rounded,
                label: 'Redline',
                isDark: isDark,
                isActive: widget.isRedlineActive,
                onTap: widget.onRedlineToggle,
              ),
            ],
          ),
          const SizedBox(width: 8),

          // ─── Responsive ───
          _DesignChipGroup(
            label: 'Responsive',
            icon: Icons.devices_rounded,
            isDark: isDark,
            children: [
              _DesignActionChip(
                icon: Icons.phone_android_rounded,
                label: 'Mobile',
                isDark: isDark,
                onTap: () => widget.onBreakpointSelect?.call('mobile'),
              ),
              _DesignActionChip(
                icon: Icons.tablet_rounded,
                label: 'Tablet',
                isDark: isDark,
                onTap: () => widget.onBreakpointSelect?.call('tablet'),
              ),
              _DesignActionChip(
                icon: Icons.desktop_windows_rounded,
                label: 'Desktop',
                isDark: isDark,
                onTap: () => widget.onBreakpointSelect?.call('desktop'),
              ),
            ],
          ),
          const SizedBox(width: 8),

          // ─── Quality ───
          _DesignChipGroup(
            label: 'Quality',
            icon: Icons.verified_rounded,
            isDark: isDark,
            children: [
              _DesignActionChip(
                icon: Icons.grid_3x3_rounded,
                label: 'Snap',
                isDark: isDark,
                isActive: widget.isSmartSnapActive,
                onTap: widget.onSmartSnapToggle,
              ),
              _DesignActionChip(
                icon: Icons.checklist_rounded,
                label: 'Lint',
                isDark: isDark,
                onTap: widget.onDesignLint,
              ),
              _DesignActionChip(
                icon: Icons.palette_rounded,
                label: 'Styles',
                isDark: isDark,
                onTap: widget.onStyleSystem,
              ),
              _DesignActionChip(
                icon: Icons.accessibility_new_rounded,
                label: 'A11y',
                isDark: isDark,
                onTap: widget.onAccessibilityTree,
              ),
            ],
          ),
          const SizedBox(width: 8),

          // ─── Images ───
          _DesignChipGroup(
            label: 'Images',
            icon: Icons.tune_rounded,
            isDark: isDark,
            children: [
              _DesignActionChip(
                icon: Icons.brightness_6_rounded,
                label: 'Adjust',
                isDark: isDark,
                onTap: widget.onImageAdjust,
              ),
              _DesignActionChip(
                icon: Icons.crop_rounded,
                label: 'Fill',
                isDark: isDark,
                onTap: widget.onImageFillMode,
              ),
            ],
          ),
          const SizedBox(width: 8),

          // ─── Export ───
          _DesignChipGroup(
            label: 'Export',
            icon: Icons.download_rounded,
            isDark: isDark,
            children: [
              _DesignActionChip(
                icon: Icons.css_rounded,
                label: 'CSS',
                isDark: isDark,
                onTap: () => widget.onTokenExport?.call('css'),
              ),
              _DesignActionChip(
                icon: Icons.android_rounded,
                label: 'Kotlin',
                isDark: isDark,
                onTap: () => widget.onTokenExport?.call('kotlin'),
              ),
              _DesignActionChip(
                icon: Icons.apple_rounded,
                label: 'Swift',
                isDark: isDark,
                onTap: () => widget.onTokenExport?.call('swift'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 🏷️ Design Chip Widgets — Material 3 grouped action chips
// ============================================================================

/// A labeled group of action chips for the Design toolbar.
class _DesignChipGroup extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isDark;
  final List<Widget> children;

  const _DesignChipGroup({
    required this.label,
    required this.icon,
    required this.isDark,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: isDark ? 0.3 : 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Group label
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11, color: cs.onSurfaceVariant),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          // Action chips row
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                children[i],
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Single Material 3 action chip for the Design toolbar — with press-scale.
class _DesignActionChip extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final bool isActive;
  final VoidCallback? onTap;

  const _DesignActionChip({
    required this.icon,
    required this.label,
    required this.isDark,
    this.isActive = false,
    this.onTap,
  });

  @override
  State<_DesignActionChip> createState() => _DesignActionChipState();
}

class _DesignActionChipState extends State<_DesignActionChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: ToolbarTokens.animFast);
    _scale = Tween(
      begin: 1.0,
      end: 0.85,
    ).animate(CurvedAnimation(parent: _ctrl, curve: ToolbarTokens.curveActive));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeColor = cs.primary;
    final enabled = widget.onTap != null;

    return GestureDetector(
      onTapDown: enabled ? (_) => _ctrl.forward() : null,
      onTapUp:
          enabled
              ? (_) {
                _ctrl.reverse();
                HapticFeedback.selectionClick();
                widget.onTap!();
              }
              : null,
      onTapCancel: () => _ctrl.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder:
            (_, child) => Transform.scale(scale: _scale.value, child: child),
        child: AnimatedContainer(
          duration: ToolbarTokens.animFast,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color:
                widget.isActive
                    ? activeColor.withValues(alpha: widget.isDark ? 0.25 : 0.12)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border:
                widget.isActive
                    ? Border.all(
                      color: activeColor.withValues(alpha: 0.5),
                      width: 1.5,
                    )
                    : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 18,
                color:
                    !enabled
                        ? cs.onSurface.withValues(alpha: 0.25)
                        : widget.isActive
                        ? activeColor
                        : (widget.isDark ? Colors.white70 : Colors.black54),
              ),
              const SizedBox(height: 2),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight:
                      widget.isActive ? FontWeight.w700 : FontWeight.w500,
                  color:
                      !enabled
                          ? cs.onSurface.withValues(alpha: 0.25)
                          : widget.isActive
                          ? activeColor
                          : (widget.isDark ? Colors.white54 : Colors.black45),
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
// 🆕 ENTERPRISE UX WIDGETS — Round 2
// =============================================================================

/// Wraps a horizontally scrollable row with fade gradients on the edges.
/// Signals to the user that more content is available — Linear/Figma style.
class _FadedScrollRow extends StatefulWidget {
  final EdgeInsets padding;
  final List<Widget> children;
  final double fadeWidth;

  const _FadedScrollRow({
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(10, 4, 10, 6),
    this.fadeWidth = 24.0,
  });

  @override
  State<_FadedScrollRow> createState() => _FadedScrollRowState();
}

class _FadedScrollRowState extends State<_FadedScrollRow> {
  final _controller = ScrollController();
  bool _showLeftFade = false;
  bool _showRightFade = true;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    // After first frame, check if scroll is needed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onScroll();
    });
  }

  void _onScroll() {
    if (!mounted) return;
    final pos = _controller.position;
    setState(() {
      _showLeftFade = pos.pixels > 4;
      _showRightFade = pos.pixels < pos.maxScrollExtent - 4;
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.black : Colors.white;

    return Stack(
      children: [
        // The scroll content
        SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          padding: widget.padding,
          physics: const BouncingScrollPhysics(),
          child: Row(children: widget.children),
        ),
        // Left fade gradient
        if (_showLeftFade)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: widget.fadeWidth,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _showLeftFade ? 1 : 0,
                duration: ToolbarTokens.animFast,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        baseColor.withValues(alpha: 0.9),
                        baseColor.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        // Right fade gradient
        if (_showRightFade)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: widget.fadeWidth,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _showRightFade ? 1 : 0,
                duration: ToolbarTokens.animFast,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        baseColor.withValues(alpha: 0),
                        baseColor.withValues(alpha: 0.9),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Mini pill shown when toolbar is collapsed — displays active tool + color.
/// Tap to expand.
class _CollapsedToolIndicator extends StatelessWidget {
  final IconData toolIcon;
  final Color penColor;
  final double strokeWidth;
  final bool isDark;
  final VoidCallback onTap;

  const _CollapsedToolIndicator({
    required this.toolIcon,
    required this.penColor,
    required this.strokeWidth,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = (isDark ? Colors.white : Colors.black).withValues(
      alpha: 0.5,
    );
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: ToolbarTokens.animNormal,
        curve: ToolbarTokens.curveActive,
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Active tool icon
            Icon(toolIcon, size: 14, color: textColor),
            const SizedBox(width: 8),
            // Color dot
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: penColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: (isDark ? Colors.white : Colors.black).withValues(
                    alpha: 0.15,
                  ),
                  width: 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: penColor.withValues(alpha: 0.4),
                    blurRadius: 4,
                    spreadRadius: 0,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Width indicator
            Text(
              '${strokeWidth.round()}px',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: textColor,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(width: 6),
            // Expand chevron
            Icon(Icons.expand_less_rounded, size: 14, color: textColor),
          ],
        ),
      ),
    );
  }
}

/// Figma-style active dot — 4px circle that animates under the active tool.
/// Wraps a child widget and places the dot at the bottom center.
class _ActiveDotWrapper extends StatelessWidget {
  final bool isActive;
  final Color dotColor;
  final Widget child;

  const _ActiveDotWrapper({
    required this.isActive,
    required this.dotColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        child,
        Positioned(
          bottom: -4,
          child: AnimatedOpacity(
            opacity: isActive ? 1.0 : 0.0,
            duration: ToolbarTokens.animFast,
            child: AnimatedScale(
              scale: isActive ? 1.0 : 0.0,
              duration: ToolbarTokens.animNormal,
              curve: ToolbarTokens.curveActive,
              child: Container(
                width: ToolbarTokens.activeDotSize,
                height: ToolbarTokens.activeDotSize,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: dotColor.withValues(alpha: 0.6),
                      blurRadius: 4,
                      spreadRadius: 0,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Live stroke width preview — a short curved stroke painted with current
/// pen color and width. Used in the width section of the main toolbar.
class _StrokeWidthPreview extends StatelessWidget {
  final Color color;
  final double width;

  const _StrokeWidthPreview({required this.color, required this.width});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 32,
      child: CustomPaint(
        painter: _StrokePreviewPainter(color: color, strokeWidth: width),
      ),
    );
  }
}

class _StrokePreviewPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  const _StrokePreviewPainter({required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..strokeWidth = strokeWidth.clamp(1.0, 16.0)
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(size.width * 0.1, size.height * 0.65);
    path.cubicTo(
      size.width * 0.3,
      size.height * 0.2,
      size.width * 0.7,
      size.height * 0.8,
      size.width * 0.9,
      size.height * 0.35,
    );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_StrokePreviewPainter old) =>
      old.color != color || old.strokeWidth != strokeWidth;
}
