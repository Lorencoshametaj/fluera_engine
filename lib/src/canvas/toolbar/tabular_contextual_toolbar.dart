import 'package:flutter/material.dart';

import '../../tools/tabular/tabular_tool.dart';
import '../../core/nodes/tabular_node.dart';
import '../../core/tabular/cell_address.dart';
import '../../core/tabular/cell_node.dart';
import '../../core/tabular/cell_value.dart';

/// 📊 Contextual toolbar for spreadsheet operations.
///
/// Appears when a [TabularNode] is selected, providing:
/// - Cell formatting (bold, italic, text/bg color)
/// - Alignment controls
/// - Insert/Delete row/column
/// - CSV Import/Export actions
///
/// Observes [TabularToolState] to enable/disable buttons based on selection.
class TabularContextualToolbar extends StatelessWidget {
  final TabularToolState toolState;

  /// Called when the user toggles bold on the selected cell.
  final VoidCallback? onToggleBold;

  /// Called when the user toggles italic.
  final VoidCallback? onToggleItalic;

  /// Called when the user changes text color.
  final ValueChanged<Color>? onTextColorChanged;

  /// Called when the user changes cell background color.
  final ValueChanged<Color>? onBackgroundColorChanged;

  /// Called when a row is inserted.
  final VoidCallback? onInsertRow;

  /// Called when a row is deleted.
  final VoidCallback? onDeleteRow;

  /// Called when a column is inserted.
  final VoidCallback? onInsertColumn;

  /// Called when a column is deleted.
  final VoidCallback? onDeleteColumn;

  /// Called to import CSV data.
  final VoidCallback? onImportCsv;

  /// Called to export as CSV.
  final VoidCallback? onExportCsv;

  /// Called to import XLSX data.
  final VoidCallback? onImportXlsx;

  /// Called to export as XLSX.
  final VoidCallback? onExportXlsx;

  /// Called to open validation rule picker for selected cell.
  final VoidCallback? onSetValidation;

  /// Called to open conditional format rule picker.
  final VoidCallback? onSetConditionalFormat;

  /// Called when user selects a number format for the selected cell.
  final ValueChanged<String>? onNumberFormatChanged;

  /// Called when user changes text alignment.
  final ValueChanged<CellAlignment>? onAlignmentChanged;

  /// Called when user changes font size.
  final ValueChanged<double>? onFontSizeChanged;

  /// Called when user merges selected cells.
  final VoidCallback? onMergeCells;

  /// Called when user unmerges selected cells.
  final VoidCallback? onUnmergeCells;

  /// Called when user toggles freeze panes at selected cell.
  final VoidCallback? onToggleFreeze;

  /// Whether freeze panes are currently active.
  final bool isFrozen;

  /// Called to undo last action.
  final VoidCallback? onUndo;

  /// Called to redo last undone action.
  final VoidCallback? onRedo;

  const TabularContextualToolbar({
    super.key,
    required this.toolState,
    this.onToggleBold,
    this.onToggleItalic,
    this.onTextColorChanged,
    this.onBackgroundColorChanged,
    this.onInsertRow,
    this.onDeleteRow,
    this.onInsertColumn,
    this.onDeleteColumn,
    this.onImportCsv,
    this.onExportCsv,
    this.onImportXlsx,
    this.onExportXlsx,
    this.onSetValidation,
    this.onSetConditionalFormat,
    this.onNumberFormatChanged,
    this.onAlignmentChanged,
    this.onFontSizeChanged,
    this.onMergeCells,
    this.onUnmergeCells,
    this.onToggleFreeze,
    this.isFrozen = false,
    this.onUndo,
    this.onRedo,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: toolState,
      builder: (context, _) {
        final hasSelection = toolState.hasCellSelection;

        return Container(
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            border: Border(
              top: BorderSide(color: const Color(0xFF333333), width: 0.5),
              bottom: BorderSide(color: const Color(0xFF333333), width: 0.5),
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 8),

              // ── Format group ──
              _ToolbarIconButton(
                icon: Icons.format_bold,
                tooltip: 'Bold',
                onPressed: hasSelection ? onToggleBold : null,
                isActive: _isBold,
              ),
              _ToolbarIconButton(
                icon: Icons.format_italic,
                tooltip: 'Italic',
                onPressed: hasSelection ? onToggleItalic : null,
                isActive: _isItalic,
              ),

              _divider(),

              // ── Alignment group ──
              _ToolbarIconButton(
                icon: Icons.format_align_left,
                tooltip: 'Align left',
                onPressed:
                    hasSelection
                        ? () => onAlignmentChanged?.call(CellAlignment.left)
                        : null,
                isActive: _currentAlign == CellAlignment.left,
              ),
              _ToolbarIconButton(
                icon: Icons.format_align_center,
                tooltip: 'Align center',
                onPressed:
                    hasSelection
                        ? () => onAlignmentChanged?.call(CellAlignment.center)
                        : null,
                isActive: _currentAlign == CellAlignment.center,
              ),
              _ToolbarIconButton(
                icon: Icons.format_align_right,
                tooltip: 'Align right',
                onPressed:
                    hasSelection
                        ? () => onAlignmentChanged?.call(CellAlignment.right)
                        : null,
                isActive: _currentAlign == CellAlignment.right,
              ),

              // ── Font size ──
              if (hasSelection)
                _FontSizeDropdown(
                  currentSize: _currentFontSize,
                  onChanged: onFontSizeChanged,
                ),

              _divider(),

              // ── Color group ──
              _ToolbarColorButton(
                icon: Icons.format_color_text,
                tooltip: 'Text color',
                color: _textColor,
                onPressed:
                    hasSelection
                        ? () => _showColorPicker(
                          context,
                          _textColor,
                          onTextColorChanged,
                        )
                        : null,
              ),
              _ToolbarColorButton(
                icon: Icons.format_color_fill,
                tooltip: 'Fill color',
                color: _bgColor,
                onPressed:
                    hasSelection
                        ? () => _showColorPicker(
                          context,
                          _bgColor,
                          onBackgroundColorChanged,
                        )
                        : null,
              ),

              _divider(),

              // ── Row/Column group ──
              _ToolbarIconButton(
                icon: Icons.table_rows_outlined,
                tooltip: 'Insert row',
                onPressed: onInsertRow,
              ),
              _ToolbarIconButton(
                icon: Icons.remove_circle_outline,
                tooltip: 'Delete row',
                onPressed: hasSelection ? onDeleteRow : null,
              ),
              _ToolbarIconButton(
                icon: Icons.view_column_outlined,
                tooltip: 'Insert column',
                onPressed: onInsertColumn,
              ),
              _ToolbarIconButton(
                icon: Icons.remove_circle_outline,
                tooltip: 'Delete column',
                onPressed: hasSelection ? onDeleteColumn : null,
              ),

              _divider(),

              // ── CSV/XLSX group ──
              _ToolbarIconButton(
                icon: Icons.file_upload_outlined,
                tooltip: 'Import CSV',
                onPressed: onImportCsv,
              ),
              _ToolbarIconButton(
                icon: Icons.file_download_outlined,
                tooltip: 'Export CSV',
                onPressed: onExportCsv,
              ),
              _ToolbarIconButton(
                icon: Icons.grid_on_rounded,
                tooltip: 'Import XLSX',
                onPressed: onImportXlsx,
              ),
              _ToolbarIconButton(
                icon: Icons.grid_view_rounded,
                tooltip: 'Export XLSX',
                onPressed: onExportXlsx,
              ),

              _divider(),

              // ── Data tools group ──
              _ToolbarIconButton(
                icon: Icons.numbers_rounded,
                tooltip: 'Number format',
                onPressed:
                    hasSelection
                        ? () => _showNumberFormatPicker(context)
                        : null,
              ),
              _ToolbarIconButton(
                icon: Icons.rule_rounded,
                tooltip: 'Validation rule',
                onPressed: hasSelection ? onSetValidation : null,
              ),
              _ToolbarIconButton(
                icon: Icons.format_paint_rounded,
                tooltip: 'Conditional format',
                onPressed: hasSelection ? onSetConditionalFormat : null,
              ),

              _divider(),

              // ── Merge / Freeze group ──
              _ToolbarIconButton(
                icon: Icons.call_merge_rounded,
                tooltip: 'Merge cells',
                onPressed: hasSelection ? onMergeCells : null,
              ),
              _ToolbarIconButton(
                icon: Icons.call_split_rounded,
                tooltip: 'Unmerge cells',
                onPressed: hasSelection ? onUnmergeCells : null,
              ),
              _ToolbarIconButton(
                icon: Icons.view_compact_rounded,
                tooltip: 'Freeze panes',
                onPressed: onToggleFreeze,
                isActive: isFrozen,
              ),

              _divider(),

              // ── Undo/Redo ──
              _ToolbarIconButton(
                icon: Icons.undo_rounded,
                tooltip: 'Undo',
                onPressed: onUndo,
              ),
              _ToolbarIconButton(
                icon: Icons.redo_rounded,
                tooltip: 'Redo',
                onPressed: onRedo,
              ),

              const Spacer(),

              // Cell address label.
              if (toolState.selectedCell != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    toolState.selectedCell!.label,
                    style: const TextStyle(
                      color: Color(0xFF90CAF9),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  bool get _isBold {
    final cell = _selectedCellNode;
    return cell?.format?.bold ?? false;
  }

  bool get _isItalic {
    final cell = _selectedCellNode;
    return cell?.format?.italic ?? false;
  }

  Color get _textColor {
    final cell = _selectedCellNode;
    return cell?.format?.textColor ?? const Color(0xFFE0E0E0);
  }

  Color get _bgColor {
    final cell = _selectedCellNode;
    return cell?.format?.backgroundColor ?? Colors.transparent;
  }

  CellAlignment? get _currentAlign {
    final cell = _selectedCellNode;
    return cell?.format?.horizontalAlign;
  }

  double get _currentFontSize {
    final cell = _selectedCellNode;
    return cell?.format?.fontSize ?? 13.0;
  }

  CellNode? get _selectedCellNode {
    if (toolState.activeNode == null || toolState.selectedCell == null) {
      return null;
    }
    return toolState.activeNode!.model.getCell(toolState.selectedCell!);
  }

  Widget _divider() {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: const Color(0xFF3A3A3A),
    );
  }

  void _showColorPicker(
    BuildContext context,
    Color currentColor,
    ValueChanged<Color>? onChanged,
  ) {
    if (onChanged == null) return;

    final colors = [
      Colors.white,
      const Color(0xFFE0E0E0),
      const Color(0xFF9E9E9E),
      const Color(0xFF424242),
      Colors.black,
      const Color(0xFFFF4444),
      const Color(0xFFFF8A65),
      const Color(0xFFFFD54F),
      const Color(0xFF81C784),
      const Color(0xFF4FC3F7),
      const Color(0xFF7986CB),
      const Color(0xFFBA68C8),
    ];

    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF2A2A2A),
            contentPadding: const EdgeInsets.all(16),
            content: Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  colors.map((c) {
                    return InkWell(
                      onTap: () {
                        onChanged(c);
                        Navigator.of(ctx).pop();
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: c,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color:
                                c == currentColor
                                    ? const Color(0xFF4A90D9)
                                    : const Color(0xFF555555),
                            width: c == currentColor ? 2 : 1,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
            ),
          ),
    );
  }

  void _showNumberFormatPicker(BuildContext context) {
    if (onNumberFormatChanged == null) return;

    final formats = <(String, String)>[
      ('General', ''),
      ('Number', '#,##0.00'),
      ('Currency', '\$#,##0.00'),
      ('Percentage', '0.00%'),
      ('Date', 'yyyy-mm-dd'),
      ('Scientific', '0.00E+0'),
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
                      onNumberFormatChanged!(f.$2);
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

// ---------------------------------------------------------------------------
// Internal button widgets
// ---------------------------------------------------------------------------

class _ToolbarIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool isActive;

  const _ToolbarIconButton({
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
        color: isActive ? const Color(0xFF3A3A3A) : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(
              icon,
              size: 18,
              color:
                  onPressed != null
                      ? const Color(0xFFCCCCCC)
                      : const Color(0xFF555555),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolbarColorButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback? onPressed;

  const _ToolbarColorButton({
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
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color:
                    onPressed != null
                        ? const Color(0xFFCCCCCC)
                        : const Color(0xFF555555),
              ),
              Container(
                width: 14,
                height: 3,
                margin: const EdgeInsets.only(top: 1),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        width: 52,
        height: 28,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFF444444), width: 0.5),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<double>(
              value: _sizes.contains(currentSize) ? currentSize : null,
              hint: Text(
                currentSize.round().toString(),
                style: const TextStyle(
                  color: Color(0xFFCCCCCC),
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
              isDense: true,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              dropdownColor: const Color(0xFF2A2A2A),
              style: const TextStyle(
                color: Color(0xFFCCCCCC),
                fontSize: 11,
                fontFamily: 'monospace',
              ),
              icon: const Icon(
                Icons.arrow_drop_down,
                size: 14,
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
      ),
    );
  }
}
