import 'package:flutter/material.dart';

import '../../tools/tabular/tabular_tool.dart';
import '../../core/nodes/tabular_node.dart';
import '../../core/tabular/cell_address.dart';
import '../../core/tabular/cell_node.dart';
import '../../core/tabular/cell_value.dart';

// ---------------------------------------------------------------------------
// Tab identifiers
// ---------------------------------------------------------------------------

enum _TabId { format, insert, data, view }

/// 📊 Tabbed contextual toolbar for spreadsheet operations.
///
/// Uses a **ribbon-style** layout with 4 tabs. Each tab's content is
/// horizontally scrollable so buttons are comfortably sized and grouped
/// in visual cards — the user swipes left/right to reveal more groups.
///
/// Undo/Redo are always visible in the tab bar.
class TabularContextualToolbar extends StatefulWidget {
  final TabularToolState toolState;

  // -- Format callbacks --
  final VoidCallback? onToggleBold;
  final VoidCallback? onToggleItalic;
  final ValueChanged<Color>? onTextColorChanged;
  final ValueChanged<Color>? onBackgroundColorChanged;
  final ValueChanged<CellAlignment>? onAlignmentChanged;
  final ValueChanged<double>? onFontSizeChanged;

  // -- Insert callbacks --
  final VoidCallback? onInsertRow;
  final VoidCallback? onDeleteRow;
  final VoidCallback? onInsertColumn;
  final VoidCallback? onDeleteColumn;
  final VoidCallback? onMergeCells;
  final VoidCallback? onUnmergeCells;

  // -- Data & LaTeX callbacks --
  final ValueChanged<String>? onNumberFormatChanged;
  final VoidCallback? onSetValidation;
  final VoidCallback? onSetConditionalFormat;
  final VoidCallback? onGenerateLatex;

  // -- View callbacks --
  final VoidCallback? onToggleFreeze;
  final bool isFrozen;
  final VoidCallback? onImportCsv;
  final VoidCallback? onExportCsv;
  final VoidCallback? onImportXlsx;
  final VoidCallback? onExportXlsx;

  // -- History callbacks --
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;

  const TabularContextualToolbar({
    super.key,
    required this.toolState,
    this.onToggleBold,
    this.onToggleItalic,
    this.onTextColorChanged,
    this.onBackgroundColorChanged,
    this.onAlignmentChanged,
    this.onFontSizeChanged,
    this.onInsertRow,
    this.onDeleteRow,
    this.onInsertColumn,
    this.onDeleteColumn,
    this.onMergeCells,
    this.onUnmergeCells,
    this.onNumberFormatChanged,
    this.onSetValidation,
    this.onSetConditionalFormat,
    this.onGenerateLatex,
    this.onToggleFreeze,
    this.isFrozen = false,
    this.onImportCsv,
    this.onExportCsv,
    this.onImportXlsx,
    this.onExportXlsx,
    this.onUndo,
    this.onRedo,
  });

  @override
  State<TabularContextualToolbar> createState() =>
      _TabularContextualToolbarState();
}

class _TabularContextualToolbarState extends State<TabularContextualToolbar> {
  _TabId _selectedTab = _TabId.format;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.toolState,
      builder: (context, _) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A1A),
            border: Border(
              top: BorderSide(color: Color(0xFF333333), width: 0.5),
              bottom: BorderSide(color: Color(0xFF333333), width: 0.5),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [_buildTabBar(), _buildTabContent()],
          ),
        );
      },
    );
  }

  // =========================================================================
  // Tab bar (always visible — 36px)
  // =========================================================================

  Widget _buildTabBar() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: const Color(0xFF1E1E1E),
      child: Row(
        children: [
          // Tab chips.
          Expanded(
            child: Row(
              children: [
                _tabChip(_TabId.format, 'Format', Icons.text_format_rounded),
                const SizedBox(width: 4),
                _tabChip(_TabId.insert, 'Insert', Icons.add_box_outlined),
                const SizedBox(width: 4),
                _tabChip(_TabId.data, 'Data', Icons.data_usage_rounded),
                const SizedBox(width: 4),
                _tabChip(_TabId.view, 'View', Icons.visibility_outlined),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Cell address badge.
          if (widget.toolState.selectedCell != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF252525),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                widget.toolState.selectedCell!.label,
                style: const TextStyle(
                  color: Color(0xFF90CAF9),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                ),
              ),
            ),

          const SizedBox(width: 6),

          // Undo/Redo (always visible).
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF252525),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _miniButton(Icons.undo_rounded, 'Undo', widget.onUndo),
                Container(width: 1, height: 16, color: const Color(0xFF3A3A3A)),
                _miniButton(Icons.redo_rounded, 'Redo', widget.onRedo),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabChip(_TabId id, String label, IconData icon) {
    final isSelected = _selectedTab == id;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? const Color(0xFF2D5FE0).withValues(alpha: 0.20)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border:
              isSelected
                  ? Border.all(
                    color: const Color(0xFF2D5FE0).withValues(alpha: 0.4),
                    width: 0.5,
                  )
                  : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color:
                  isSelected
                      ? const Color(0xFF7EAAEF)
                      : const Color(0xFF888888),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color:
                    isSelected
                        ? const Color(0xFFCCDDFF)
                        : const Color(0xFF888888),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniButton(IconData icon, String tooltip, VoidCallback? onPressed) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(
            icon,
            size: 16,
            color:
                onPressed != null
                    ? const Color(0xFFBBBBBB)
                    : const Color(0xFF555555),
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // Tab content — horizontally scrollable with grouped cards (56px)
  // =========================================================================

  Widget _buildTabContent() {
    return SizedBox(
      height: 56,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 120),
        child: SingleChildScrollView(
          key: ValueKey(_selectedTab),
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: switch (_selectedTab) {
              _TabId.format => _formatTab(),
              _TabId.insert => _insertTab(),
              _TabId.data => _dataTab(),
              _TabId.view => _viewTab(),
            },
          ),
        ),
      ),
    );
  }

  /// Wraps a list of buttons in a visual group card with a label.
  Widget _group(String label, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF222222),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF333333), width: 0.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: children),
          Text(
            label,
            style: const TextStyle(
              fontSize: 8,
              color: Color(0xFF666666),
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // FORMAT tab
  // =========================================================================

  List<Widget> _formatTab() {
    final sel = widget.toolState.hasCellSelection;
    return [
      _group('Style', [
        _Btn(
          icon: Icons.format_bold,
          tooltip: 'Bold',
          onPressed: sel ? widget.onToggleBold : null,
          isActive: _isBold,
        ),
        _Btn(
          icon: Icons.format_italic,
          tooltip: 'Italic',
          onPressed: sel ? widget.onToggleItalic : null,
          isActive: _isItalic,
        ),
      ]),

      _group('Align', [
        _Btn(
          icon: Icons.format_align_left,
          tooltip: 'Left',
          onPressed:
              sel
                  ? () => widget.onAlignmentChanged?.call(CellAlignment.left)
                  : null,
          isActive: _currentAlign == CellAlignment.left,
        ),
        _Btn(
          icon: Icons.format_align_center,
          tooltip: 'Center',
          onPressed:
              sel
                  ? () => widget.onAlignmentChanged?.call(CellAlignment.center)
                  : null,
          isActive: _currentAlign == CellAlignment.center,
        ),
        _Btn(
          icon: Icons.format_align_right,
          tooltip: 'Right',
          onPressed:
              sel
                  ? () => widget.onAlignmentChanged?.call(CellAlignment.right)
                  : null,
          isActive: _currentAlign == CellAlignment.right,
        ),
      ]),

      _group('Color', [
        _ColorBtn(
          icon: Icons.format_color_text,
          tooltip: 'Text color',
          color: _textColor,
          onPressed:
              sel
                  ? () => _showColorPicker(
                    context,
                    _textColor,
                    widget.onTextColorChanged,
                  )
                  : null,
        ),
        _ColorBtn(
          icon: Icons.format_color_fill,
          tooltip: 'Fill color',
          color: _bgColor,
          onPressed:
              sel
                  ? () => _showColorPicker(
                    context,
                    _bgColor,
                    widget.onBackgroundColorChanged,
                  )
                  : null,
        ),
      ]),

      if (sel)
        _group('Size', [
          _FontSizeDropdown(
            currentSize: _currentFontSize,
            onChanged: widget.onFontSizeChanged,
          ),
        ]),
    ];
  }

  // =========================================================================
  // INSERT tab
  // =========================================================================

  List<Widget> _insertTab() {
    final sel = widget.toolState.hasCellSelection;
    return [
      _group('Rows', [
        _Btn(
          icon: Icons.add_rounded,
          tooltip: 'Insert row',
          onPressed: widget.onInsertRow,
        ),
        _Btn(
          icon: Icons.remove_rounded,
          tooltip: 'Delete row',
          onPressed: sel ? widget.onDeleteRow : null,
        ),
      ]),

      _group('Columns', [
        _Btn(
          icon: Icons.add_rounded,
          tooltip: 'Insert column',
          onPressed: widget.onInsertColumn,
        ),
        _Btn(
          icon: Icons.remove_rounded,
          tooltip: 'Delete column',
          onPressed: sel ? widget.onDeleteColumn : null,
        ),
      ]),

      _group('Merge', [
        _Btn(
          icon: Icons.call_merge_rounded,
          tooltip: 'Merge cells',
          onPressed: sel ? widget.onMergeCells : null,
        ),
        _Btn(
          icon: Icons.call_split_rounded,
          tooltip: 'Unmerge cells',
          onPressed: sel ? widget.onUnmergeCells : null,
        ),
      ]),
    ];
  }

  // =========================================================================
  // DATA tab
  // =========================================================================

  List<Widget> _dataTab() {
    final sel = widget.toolState.hasCellSelection;
    return [
      _group('Number Format', [
        _Btn(
          icon: Icons.numbers_rounded,
          tooltip: 'Number format',
          onPressed: sel ? () => _showNumberFormatPicker(context) : null,
        ),
      ]),

      _group('Validation', [
        _Btn(
          icon: Icons.rule_rounded,
          tooltip: 'Validation rule',
          onPressed: sel ? widget.onSetValidation : null,
        ),
      ]),

      _group('Conditional', [
        _Btn(
          icon: Icons.format_paint_rounded,
          tooltip: 'Conditional format',
          onPressed: sel ? widget.onSetConditionalFormat : null,
        ),
      ]),

      _group('Export Data', [
        _Btn(
          icon: Icons.functions_rounded, // or code, auto_awesome
          tooltip: 'Generate LaTeX Table from Selection',
          onPressed: sel ? widget.onGenerateLatex : null,
        ),
      ]),
    ];
  }

  // =========================================================================
  // VIEW tab
  // =========================================================================

  List<Widget> _viewTab() {
    return [
      _group('Freeze', [
        _Btn(
          icon: Icons.view_compact_rounded,
          tooltip: 'Freeze panes',
          onPressed: widget.onToggleFreeze,
          isActive: widget.isFrozen,
        ),
      ]),

      _group('CSV', [
        _Btn(
          icon: Icons.file_upload_outlined,
          tooltip: 'Import CSV',
          onPressed: widget.onImportCsv,
        ),
        _Btn(
          icon: Icons.file_download_outlined,
          tooltip: 'Export CSV',
          onPressed: widget.onExportCsv,
        ),
      ]),

      _group('XLSX', [
        _Btn(
          icon: Icons.grid_on_rounded,
          tooltip: 'Import XLSX',
          onPressed: widget.onImportXlsx,
        ),
        _Btn(
          icon: Icons.grid_view_rounded,
          tooltip: 'Export XLSX',
          onPressed: widget.onExportXlsx,
        ),
      ]),
    ];
  }

  // =========================================================================
  // Format state helpers
  // =========================================================================

  bool get _isBold => _selectedCellNode?.format?.bold ?? false;
  bool get _isItalic => _selectedCellNode?.format?.italic ?? false;
  Color get _textColor =>
      _selectedCellNode?.format?.textColor ?? const Color(0xFFE0E0E0);
  Color get _bgColor =>
      _selectedCellNode?.format?.backgroundColor ?? Colors.transparent;
  CellAlignment? get _currentAlign =>
      _selectedCellNode?.format?.horizontalAlign;
  double get _currentFontSize => _selectedCellNode?.format?.fontSize ?? 13.0;

  CellNode? get _selectedCellNode {
    if (widget.toolState.activeNode == null ||
        widget.toolState.selectedCell == null) {
      return null;
    }
    return widget.toolState.activeNode!.model.getCell(
      widget.toolState.selectedCell!,
    );
  }

  // =========================================================================
  // Dialogs
  // =========================================================================

  void _showColorPicker(
    BuildContext context,
    Color currentColor,
    ValueChanged<Color>? onColorChanged,
  ) {
    if (onColorChanged == null) return;

    const colors = [
      Colors.white,
      Colors.black,
      Colors.red,
      Colors.pink,
      Colors.purple,
      Colors.deepPurple,
      Colors.indigo,
      Colors.blue,
      Colors.lightBlue,
      Colors.cyan,
      Colors.teal,
      Colors.green,
      Colors.lightGreen,
      Colors.lime,
      Colors.yellow,
      Colors.amber,
      Colors.orange,
      Colors.deepOrange,
      Colors.brown,
      Colors.grey,
    ];

    showDialog(
      context: context,
      builder:
          (ctx) => SimpleDialog(
            backgroundColor: const Color(0xFF2A2A2A),
            title: const Text(
              'Pick Color',
              style: TextStyle(color: Color(0xFFE0E0E0), fontSize: 16),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children:
                      colors.map((c) {
                        return GestureDetector(
                          onTap: () {
                            onColorChanged(c);
                            Navigator.of(ctx).pop();
                          },
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: c,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color:
                                    c == currentColor
                                        ? const Color(0xFF90CAF9)
                                        : const Color(0xFF555555),
                                width: c == currentColor ? 2 : 0.5,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                ),
              ),
            ],
          ),
    );
  }

  void _showNumberFormatPicker(BuildContext context) {
    if (widget.onNumberFormatChanged == null) return;

    final formats = [
      ('General', ''),
      ('Number', '#,##0.00'),
      ('Currency', '\$#,##0.00'),
      ('Percentage', '0.00%'),
      ('Date', 'yyyy-mm-dd'),
      ('Scientific', '0.00E+00'),
      ('Text', '@'),
    ];

    showDialog(
      context: context,
      builder:
          (ctx) => SimpleDialog(
            backgroundColor: const Color(0xFF2A2A2A),
            title: const Text(
              'Number Format',
              style: TextStyle(color: Color(0xFFE0E0E0), fontSize: 16),
            ),
            children:
                formats.map((f) {
                  return SimpleDialogOption(
                    onPressed: () {
                      widget.onNumberFormatChanged!(f.$2);
                      Navigator.of(ctx).pop();
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          f.$1,
                          style: const TextStyle(color: Color(0xFFCCCCCC)),
                        ),
                        if (f.$2.isNotEmpty)
                          Text(
                            f.$2,
                            style: const TextStyle(
                              color: Color(0xFF90CAF9),
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  );
                }).toList(),
          ),
    );
  }
}

// ===========================================================================
// Toolbar button widgets — large (38×38) with proper tap targets
// ===========================================================================

/// Standard toolbar action button — 38×38 with 20px icon.
class _Btn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool isActive;

  const _Btn({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color:
            isActive
                ? const Color(0xFF2D5FE0).withValues(alpha: 0.25)
                : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(
              icon,
              size: 20,
              color:
                  onPressed != null
                      ? (isActive
                          ? const Color(0xFF90CAF9)
                          : const Color(0xFFD0D0D0))
                      : const Color(0xFF555555),
            ),
          ),
        ),
      ),
    );
  }
}

/// Color picker button with colored underline.
class _ColorBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback? onPressed;

  const _ColorBtn({
    required this.icon,
    required this.tooltip,
    required this.color,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 38,
          height: 38,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color:
                    onPressed != null
                        ? const Color(0xFFD0D0D0)
                        : const Color(0xFF555555),
              ),
              Container(
                width: 16,
                height: 4,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact font size dropdown.
class _FontSizeDropdown extends StatelessWidget {
  final double currentSize;
  final ValueChanged<double>? onChanged;

  const _FontSizeDropdown({required this.currentSize, this.onChanged});

  static const _sizes = [
    8.0,
    9.0,
    10.0,
    11.0,
    12.0,
    13.0,
    14.0,
    16.0,
    18.0,
    20.0,
    24.0,
    28.0,
    36.0,
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 32,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF444444), width: 0.5),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<double>(
            value: _sizes.contains(currentSize) ? currentSize : null,
            hint: Text(
              currentSize.round().toString(),
              style: const TextStyle(
                color: Color(0xFFCCCCCC),
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
            isDense: true,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            dropdownColor: const Color(0xFF2A2A2A),
            style: const TextStyle(
              color: Color(0xFFCCCCCC),
              fontSize: 12,
              fontFamily: 'monospace',
            ),
            icon: const Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: Color(0xFF888888),
            ),
            items:
                _sizes
                    .map(
                      (s) => DropdownMenuItem(
                        value: s,
                        child: Text('${s.round()}'),
                      ),
                    )
                    .toList(),
            onChanged:
                onChanged != null
                    ? (v) {
                      if (v != null) onChanged!(v);
                    }
                    : null,
          ),
        ),
      ),
    );
  }
}
