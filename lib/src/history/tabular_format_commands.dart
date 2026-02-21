import 'dart:ui';

import '../core/nodes/tabular_node.dart';
import '../core/tabular/cell_address.dart';
import '../core/tabular/cell_node.dart';
import '../core/tabular/cell_value.dart';
import 'command_history.dart';

// ---------------------------------------------------------------------------
// Tabular Format Commands — Undoable cell formatting operations
// ---------------------------------------------------------------------------

/// Set the [CellFormat] on a single cell. Undo restores the previous format.
///
/// Supports merge coalescing for rapid format changes (e.g. dragging a
/// color slider).
class SetCellFormatCommand extends Command {
  final TabularNode node;
  final CellAddress address;
  final CellFormat newFormat;
  final CellFormat? _oldFormat;

  SetCellFormatCommand({
    required this.node,
    required this.address,
    required this.newFormat,
  }) : _oldFormat = node.model.getCell(address)?.format,
       super(label: 'Format ${address.label}');

  @override
  void execute() {
    final cell = node.model.getCell(address);
    if (cell != null) {
      cell.format = newFormat;
    } else {
      // Create an empty cell with the format.
      node.model.setCell(
        address,
        CellNode(value: const EmptyValue(), format: newFormat),
      );
    }
  }

  @override
  void undo() {
    final cell = node.model.getCell(address);
    if (cell != null) {
      cell.format = _oldFormat;
      // If cell is now empty value with null format, remove it.
      if (cell.value is EmptyValue && cell.format == null) {
        node.model.clearCell(address);
      }
    }
  }

  @override
  bool canMergeWith(Command other) =>
      other is SetCellFormatCommand &&
      other.node.id == node.id &&
      other.address == address;

  @override
  void mergeWith(Command other) {
    // Keep _oldFormat from first command.
  }
}

/// Apply a [CellFormat] to all cells in a range. Undo restores each cell's
/// previous format individually.
class SetRangeFormatCommand extends Command {
  final TabularNode node;
  final CellRange range;
  final CellFormat newFormat;
  late final Map<CellAddress, CellFormat?> _oldFormats;

  SetRangeFormatCommand({
    required this.node,
    required this.range,
    required this.newFormat,
  }) : super(label: 'Format ${range.label}') {
    _oldFormats = {};
    for (final addr in range.addresses) {
      _oldFormats[addr] = node.model.getCell(addr)?.format;
    }
  }

  @override
  void execute() {
    for (final addr in range.addresses) {
      final cell = node.model.getCell(addr);
      if (cell != null) {
        cell.format = newFormat;
      } else {
        node.model.setCell(
          addr,
          CellNode(value: const EmptyValue(), format: newFormat),
        );
      }
    }
  }

  @override
  void undo() {
    for (final entry in _oldFormats.entries) {
      final cell = node.model.getCell(entry.key);
      if (cell != null) {
        cell.format = entry.value;
        if (cell.value is EmptyValue && cell.format == null) {
          node.model.clearCell(entry.key);
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Convenience toggle commands
// ---------------------------------------------------------------------------

/// Toggle bold on a cell. If bold is true, sets to false and vice versa.
class ToggleBoldCommand extends Command {
  final TabularNode node;
  final CellAddress address;
  final bool _wasBold;

  ToggleBoldCommand({required this.node, required this.address})
    : _wasBold = node.model.getCell(address)?.format?.bold ?? false,
      super(label: 'Toggle bold ${address.label}');

  @override
  void execute() => _setFormat(bold: !_wasBold);

  @override
  void undo() => _setFormat(bold: _wasBold);

  void _setFormat({required bool bold}) {
    final cell = node.model.getCell(address);
    if (cell != null) {
      cell.format = (cell.format ?? const CellFormat()).copyWith(bold: bold);
    } else {
      node.model.setCell(
        address,
        CellNode(value: const EmptyValue(), format: CellFormat(bold: bold)),
      );
    }
  }
}

/// Toggle italic on a cell.
class ToggleItalicCommand extends Command {
  final TabularNode node;
  final CellAddress address;
  final bool _wasItalic;

  ToggleItalicCommand({required this.node, required this.address})
    : _wasItalic = node.model.getCell(address)?.format?.italic ?? false,
      super(label: 'Toggle italic ${address.label}');

  @override
  void execute() => _setFormat(italic: !_wasItalic);

  @override
  void undo() => _setFormat(italic: _wasItalic);

  void _setFormat({required bool italic}) {
    final cell = node.model.getCell(address);
    if (cell != null) {
      cell.format = (cell.format ?? const CellFormat()).copyWith(
        italic: italic,
      );
    } else {
      node.model.setCell(
        address,
        CellNode(value: const EmptyValue(), format: CellFormat(italic: italic)),
      );
    }
  }
}

/// Set text color on a cell.
class SetTextColorCommand extends Command {
  final TabularNode node;
  final CellAddress address;
  final Color newColor;
  final Color? _oldColor;

  SetTextColorCommand({
    required this.node,
    required this.address,
    required this.newColor,
  }) : _oldColor = node.model.getCell(address)?.format?.textColor,
       super(label: 'Text color ${address.label}');

  @override
  void execute() => _applyColor(newColor);

  @override
  void undo() => _applyColor(_oldColor);

  void _applyColor(Color? color) {
    final cell = node.model.getCell(address);
    if (cell != null) {
      cell.format = (cell.format ?? const CellFormat()).copyWith(
        textColor: color,
      );
    }
  }

  @override
  bool canMergeWith(Command other) =>
      other is SetTextColorCommand &&
      other.node.id == node.id &&
      other.address == address;

  @override
  void mergeWith(Command other) {}
}

/// Set background color on a cell.
class SetBackgroundColorCommand extends Command {
  final TabularNode node;
  final CellAddress address;
  final Color newColor;
  final Color? _oldColor;

  SetBackgroundColorCommand({
    required this.node,
    required this.address,
    required this.newColor,
  }) : _oldColor = node.model.getCell(address)?.format?.backgroundColor,
       super(label: 'Background color ${address.label}');

  @override
  void execute() => _applyColor(newColor);

  @override
  void undo() => _applyColor(_oldColor);

  void _applyColor(Color? color) {
    final cell = node.model.getCell(address);
    if (cell != null) {
      cell.format = (cell.format ?? const CellFormat()).copyWith(
        backgroundColor: color,
      );
    }
  }

  @override
  bool canMergeWith(Command other) =>
      other is SetBackgroundColorCommand &&
      other.node.id == node.id &&
      other.address == address;

  @override
  void mergeWith(Command other) {}
}

/// Set horizontal alignment on a cell.
class SetAlignmentCommand extends Command {
  final TabularNode node;
  final CellAddress address;
  final CellAlignment newAlignment;
  final CellFormat? _oldFormat;

  SetAlignmentCommand({
    required this.node,
    required this.address,
    required this.newAlignment,
  }) : _oldFormat = node.model.getCell(address)?.format,
       super(label: 'Align ${address.label}');

  @override
  void execute() {
    final cell = node.model.getCell(address);
    if (cell != null) {
      cell.format = (cell.format ?? const CellFormat()).copyWith(
        horizontalAlign: newAlignment,
      );
    } else {
      node.model.setCell(
        address,
        CellNode(
          value: const EmptyValue(),
          format: CellFormat(horizontalAlign: newAlignment),
        ),
      );
    }
  }

  @override
  void undo() {
    final cell = node.model.getCell(address);
    if (cell != null) {
      cell.format = _oldFormat;
    }
  }
}

/// Set number format on a cell or range.
class SetNumberFormatCommand extends Command {
  final TabularNode node;
  final CellRange range;
  final String newFormat;
  late final Map<CellAddress, String?> _oldFormats;

  SetNumberFormatCommand({
    required this.node,
    required this.range,
    required this.newFormat,
  }) : super(label: 'Number format ${range.label}') {
    _oldFormats = {};
    for (final addr in range.addresses) {
      _oldFormats[addr] = node.model.getCell(addr)?.format?.numberFormat;
    }
  }

  @override
  void execute() {
    for (final addr in range.addresses) {
      final cell = node.model.getCell(addr);
      if (cell != null) {
        cell.format = (cell.format ?? const CellFormat()).copyWith(
          numberFormat: newFormat,
        );
      }
    }
  }

  @override
  void undo() {
    for (final entry in _oldFormats.entries) {
      final cell = node.model.getCell(entry.key);
      if (cell != null) {
        cell.format = (cell.format ?? const CellFormat()).copyWith(
          numberFormat: entry.value,
        );
      }
    }
  }
}
