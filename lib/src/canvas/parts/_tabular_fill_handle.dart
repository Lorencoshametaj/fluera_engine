part of '../nebula_canvas_screen.dart';

/// 📊 Tabular Fill Handle — auto-fill, smart sequences, formula shifting.
extension NebulaCanvasTabularFillHandle on _NebulaCanvasScreenState {
  // ── Fill handle state ─────────────────────────────────────────────────

  /// Known smart sequences for auto-fill.
  static const _smartSequences = <List<String>>[
    // English days (short + full).
    ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
    [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ],
    // Italian days.
    ['Lun', 'Mar', 'Mer', 'Gio', 'Ven', 'Sab', 'Dom'],
    [
      'Lunedì',
      'Martedì',
      'Mercoledì',
      'Giovedì',
      'Venerdì',
      'Sabato',
      'Domenica',
    ],
    // English months (short + full).
    [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ],
    [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ],
    // Italian months.
    [
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
    ],
    [
      'Gennaio',
      'Febbraio',
      'Marzo',
      'Aprile',
      'Maggio',
      'Giugno',
      'Luglio',
      'Agosto',
      'Settembre',
      'Ottobre',
      'Novembre',
      'Dicembre',
    ],
    // Quarters.
    ['Q1', 'Q2', 'Q3', 'Q4'],
  ];

  /// Tracks the last filled cell addresses for ripple animation.
  static List<CellAddress> _lastFilledAddresses = [];

  /// Timestamp when the last fill operation completed (for ripple animation).
  static DateTime? _lastFillTime;

  /// Simple power for doubles (avoids dart:math import in part file).
  static double _pow(double base, int exp) {
    if (exp == 0) return 1.0;
    double result = 1.0;
    final absExp = exp.abs();
    for (int i = 0; i < absExp; i++) {
      result *= base;
    }
    return exp < 0 ? 1.0 / result : result;
  }

  /// Compute the preview value that would be placed at [targetRow] for [col]
  /// during a fill-down operation. Used by the tooltip overlay.
  String _computeFillPreviewValue(int col, int targetRow) {
    final node = _tabularTool.selectedTabular;
    final range = _getEffectiveRange();
    if (node == null || range == null) return '';

    final sourceRowCount = range.endRow - range.startRow + 1;

    final sourceValues = <CellValue>[];
    final sourceCells = <CellNode?>[];
    for (int r = range.startRow; r <= range.endRow; r++) {
      final cell = node.model.getCell(CellAddress(col, r));
      sourceCells.add(cell);
      sourceValues.add(cell?.value ?? const EmptyValue());
    }

    final hasFormulas = sourceCells.any((c) => c != null && c.isFormula);
    final nums = sourceValues.map((v) => v.asNumber).toList();
    final allNumeric =
        nums.every((n) => n != null) && nums.length >= 2 && !hasFormulas;

    double? step;
    double? ratio;
    if (allNumeric && nums.length >= 2) {
      step = nums[1]! - nums[0]!;
      if (nums[0]! != 0) {
        final r0 = nums[1]! / nums[0]!;
        bool isGeometric = r0 != 1.0;
        for (int i = 2; i < nums.length && isGeometric; i++) {
          if (nums[i - 1]! == 0 || (nums[i]! / nums[i - 1]!) != r0) {
            isGeometric = false;
          }
        }
        if (isGeometric) ratio = r0;
      }
    }

    final smartSeq = _detectSmartSequence(sourceValues);
    final sourceIdx = (targetRow - (range.endRow + 1)) % sourceRowCount;
    final sourceRow = range.startRow + sourceIdx;
    final sourceCell = sourceCells[sourceIdx];

    if (hasFormulas && sourceCell != null && sourceCell.isFormula) {
      final rowDelta = targetRow - sourceRow;
      final formula = (sourceCell.value as FormulaValue).expression;
      return '=${_shiftFormulaReferences(formula, 0, rowDelta)}';
    } else if (smartSeq != null) {
      final seq = smartSeq.$1;
      final startIdx = smartSeq.$2;
      final seqIdx =
          (startIdx + sourceRowCount + (targetRow - range.startRow)) %
          seq.length;
      return seq[seqIdx];
    } else if (allNumeric && ratio != null) {
      final lastNum = nums.last!;
      final fillIdx = targetRow - range.endRow;
      final newVal = lastNum * _pow(ratio, fillIdx);
      return NumberValue(newVal).displayString;
    } else if (allNumeric && step != null) {
      final lastNum = nums.last!;
      final fillIdx = targetRow - range.endRow;
      final newVal = lastNum + step * fillIdx;
      return NumberValue(newVal).displayString;
    } else {
      return sourceValues[sourceIdx].displayString;
    }
  }

  /// Dispatch fill result to the appropriate direction handler.
  void _performFill(
    ({FillDirection dir, int targetRow, int targetCol}) result,
  ) {
    final range = _getEffectiveRange();
    if (range == null) return;

    switch (result.dir) {
      case FillDirection.down:
        _performFillDown(range.endRow + 1, result.targetRow);
      case FillDirection.up:
        _performFillUp(result.targetRow, range.startRow - 1);
      case FillDirection.right:
        _performFillRight(range.endColumn + 1, result.targetCol);
      case FillDirection.left:
        _performFillLeft(result.targetCol, range.startColumn - 1);
    }
  }

  // ── Auto-fill ────────────────────────────────────────────────────────

  /// Auto-fill from the selected cell/range downward by [count] rows.
  /// Detects numeric sequences and repeats text patterns.
  void _autoFillDown({int count = 5}) {
    final node = _tabularTool.selectedTabular;
    final range = _getEffectiveRange();
    if (node == null || range == null) return;

    // For each column in the range, detect pattern and fill
    for (int c = range.startColumn; c <= range.endColumn; c++) {
      final sourceValues = <CellValue>[];
      for (int r = range.startRow; r <= range.endRow; r++) {
        final cell = node.model.getCell(CellAddress(c, r));
        sourceValues.add(cell?.value ?? const EmptyValue());
      }

      // Detect numeric sequence
      final nums = sourceValues.map((v) => v.asNumber).toList();
      final allNumeric = nums.every((n) => n != null) && nums.length >= 2;
      double? step;
      if (allNumeric && nums.length >= 2) {
        step = nums[1]! - nums[0]!;
      }

      // Fill below the range
      for (int i = 0; i < count; i++) {
        final targetRow = range.endRow + 1 + i;
        if (targetRow >= node.visibleRows) break;

        final addr = CellAddress(c, targetRow);
        if (allNumeric && step != null) {
          // Arithmetic sequence
          final lastNum = nums.last!;
          final newVal = lastNum + step * (i + 1);
          node.evaluator.setCellAndEvaluate(addr, NumberValue(newVal));
        } else {
          // Repeat pattern
          final patternIdx = i % sourceValues.length;
          node.evaluator.setCellAndEvaluate(addr, sourceValues[patternIdx]);
        }
      }
    }

    _refreshLinkedLatexNodes(node);
    _layerController.sceneGraph.bumpVersion();
    DrawingPainter.invalidateAllTiles();
    HapticFeedback.lightImpact();
    setState(() {});
    _autoSaveCanvas();
  }

  /// Fill from the selected range downward to [fillEndRow] (inclusive).
  ///
  /// Handles:
  /// - **Formulas**: shifts cell references (A1 → A2, B3 → B4, etc.)
  /// - **Numeric sequences**: detects arithmetic step (1,2,3 → 4,5,6)
  /// - **Pattern repetition**: cycles text values
  void _performFillDown(int fillStartRow, int fillEndRow) {
    final node = _tabularTool.selectedTabular;
    final range = _getEffectiveRange();
    if (node == null || range == null) return;
    if (fillStartRow > fillEndRow) return;

    final sourceRowCount = range.endRow - range.startRow + 1;
    final filledAddrs = <CellAddress>[];

    for (int c = range.startColumn; c <= range.endColumn; c++) {
      final sourceCells = <CellNode?>[];
      final sourceValues = <CellValue>[];
      for (int r = range.startRow; r <= range.endRow; r++) {
        final cell = node.model.getCell(CellAddress(c, r));
        sourceCells.add(cell);
        sourceValues.add(cell?.value ?? const EmptyValue());
      }

      final hasFormulas = sourceCells.any((c) => c != null && c.isFormula);
      final nums = sourceValues.map((v) => v.asNumber).toList();
      final allNumeric =
          nums.every((n) => n != null) && nums.length >= 2 && !hasFormulas;

      // Detect arithmetic vs geometric sequence.
      double? step;
      double? ratio;
      if (allNumeric && nums.length >= 2) {
        step = nums[1]! - nums[0]!;
        // Check geometric: all ratios must be equal and non-zero divisor.
        if (nums[0]! != 0) {
          final r0 = nums[1]! / nums[0]!;
          bool isGeometric = r0 != 1.0;
          for (int i = 2; i < nums.length && isGeometric; i++) {
            if (nums[i - 1]! == 0 || (nums[i]! / nums[i - 1]!) != r0) {
              isGeometric = false;
            }
          }
          if (isGeometric) ratio = r0;
        }
      }

      final smartSeq = _detectSmartSequence(sourceValues);

      for (int targetRow = fillStartRow; targetRow <= fillEndRow; targetRow++) {
        if (targetRow >= node.effectiveRows + 50) break;

        final sourceIdx = (targetRow - fillStartRow) % sourceRowCount;
        final sourceRow = range.startRow + sourceIdx;
        final sourceCell = sourceCells[sourceIdx];
        final addr = CellAddress(c, targetRow);

        // Fill value.
        if (hasFormulas && sourceCell != null && sourceCell.isFormula) {
          final rowDelta = targetRow - sourceRow;
          final formula = (sourceCell.value as FormulaValue).expression;
          final shifted = _shiftFormulaReferences(formula, 0, rowDelta);
          node.evaluator.setCellAndEvaluate(addr, FormulaValue(shifted));
        } else if (smartSeq != null) {
          final seq = smartSeq.$1;
          final startIdx = smartSeq.$2;
          final seqIdx =
              (startIdx + sourceRowCount + (targetRow - range.startRow)) %
              seq.length;
          node.evaluator.setCellAndEvaluate(addr, TextValue(seq[seqIdx]));
        } else if (allNumeric && ratio != null) {
          // Geometric sequence (2, 4, 8, 16...).
          final lastNum = nums.last!;
          final fillIdx = targetRow - range.endRow;
          final newVal = lastNum * _pow(ratio, fillIdx);
          node.evaluator.setCellAndEvaluate(addr, NumberValue(newVal));
        } else if (allNumeric && step != null) {
          final lastNum = nums.last!;
          final fillIdx = targetRow - range.endRow;
          final newVal = lastNum + step * fillIdx;
          node.evaluator.setCellAndEvaluate(addr, NumberValue(newVal));
        } else {
          node.evaluator.setCellAndEvaluate(addr, sourceValues[sourceIdx]);
        }

        // Copy formatting from source cell.
        if (sourceCell?.format != null) {
          final targetCell = node.model.getCell(addr);
          if (targetCell != null) {
            targetCell.format = sourceCell!.format;
          }
        }

        filledAddrs.add(addr);
      }
    }

    _tabularTool.extendSelection(range.endColumn, fillEndRow);
    _lastFilledAddresses = filledAddrs;
    _lastFillTime = DateTime.now();
    _refreshLinkedLatexNodes(node);
    _layerController.sceneGraph.bumpVersion();
    DrawingPainter.invalidateAllTiles();
    HapticFeedback.lightImpact();
    setState(() {});
    _autoSaveCanvas();
  }

  /// Shift cell references in a formula expression by [deltaCol] columns
  /// and [deltaRow] rows.
  ///
  /// Example: `_shiftFormulaReferences("A1+B2", 0, 1)` → `"A2+B3"`
  static String _shiftFormulaReferences(
    String formula,
    int deltaCol,
    int deltaRow,
  ) {
    // Match cell references like A1, B23, AA5, etc.
    // Supports optional $ for absolute references (skips them).
    final regex = RegExp(r'(\$?)([A-Z]+)(\$?)(\d+)');

    return formula.replaceAllMapped(regex, (match) {
      final colAbsolute = match.group(1) == r'$';
      final colLetters = match.group(2)!;
      final rowAbsolute = match.group(3) == r'$';
      final rowNum = int.parse(match.group(4)!);

      // Compute new column letters.
      String newCol = colLetters;
      if (!colAbsolute && deltaCol != 0) {
        int colIdx = 0;
        for (int i = 0; i < colLetters.length; i++) {
          colIdx = colIdx * 26 + (colLetters.codeUnitAt(i) - 65);
        }
        colIdx = (colIdx + deltaCol).clamp(0, 16383);
        newCol = '';
        int temp = colIdx;
        do {
          newCol = String.fromCharCode(65 + temp % 26) + newCol;
          temp = temp ~/ 26 - 1;
        } while (temp >= 0);
      }

      // Compute new row number.
      int newRow = rowNum;
      if (!rowAbsolute) {
        newRow = (rowNum + deltaRow).clamp(1, 99999);
      }

      return '${colAbsolute ? r"$" : ""}$newCol'
          '${rowAbsolute ? r"$" : ""}$newRow';
    });
  }

  /// Detect if the source values match a known smart sequence.
  /// Returns (sequence, startIndex) or null.
  static (List<String>, int)? _detectSmartSequence(List<CellValue> values) {
    if (values.isEmpty) return null;
    final texts = values.map((v) => v.displayString.trim()).toList();
    if (texts.any((t) => t.isEmpty)) return null;

    for (final seq in _smartSequences) {
      final firstIdx = seq.indexWhere(
        (s) => s.toLowerCase() == texts[0].toLowerCase(),
      );
      if (firstIdx < 0) continue;

      bool match = true;
      for (int i = 1; i < texts.length; i++) {
        final expected = seq[(firstIdx + i) % seq.length].toLowerCase();
        if (texts[i].toLowerCase() != expected) {
          match = false;
          break;
        }
      }
      if (match) return (seq, firstIdx);
    }
    return null;
  }

  /// Fill upward from [fillStartRow] to [fillEndRow] (inclusive).
  void _performFillUp(int fillStartRow, int fillEndRow) {
    final node = _tabularTool.selectedTabular;
    final range = _getEffectiveRange();
    if (node == null || range == null) return;
    if (fillStartRow > fillEndRow) return;

    final sourceRowCount = range.endRow - range.startRow + 1;

    for (int c = range.startColumn; c <= range.endColumn; c++) {
      final sourceCells = <CellNode?>[];
      final sourceValues = <CellValue>[];
      for (int r = range.startRow; r <= range.endRow; r++) {
        final cell = node.model.getCell(CellAddress(c, r));
        sourceCells.add(cell);
        sourceValues.add(cell?.value ?? const EmptyValue());
      }

      final hasFormulas = sourceCells.any((c) => c != null && c.isFormula);
      final nums = sourceValues.map((v) => v.asNumber).toList();
      final allNumeric =
          nums.every((n) => n != null) && nums.length >= 2 && !hasFormulas;
      double? step;
      if (allNumeric) step = nums[1]! - nums[0]!;
      final smartSeq = _detectSmartSequence(sourceValues);

      for (int targetRow = fillEndRow; targetRow >= fillStartRow; targetRow--) {
        if (targetRow < 0) break;
        final distFromStart = range.startRow - targetRow;
        final sourceIdx =
            ((sourceRowCount - (distFromStart % sourceRowCount)) %
                sourceRowCount);
        final sourceRow = range.startRow + sourceIdx;
        final sourceCell = sourceCells[sourceIdx];
        final addr = CellAddress(c, targetRow);

        if (hasFormulas && sourceCell != null && sourceCell.isFormula) {
          final rowDelta = targetRow - sourceRow;
          final formula = (sourceCell.value as FormulaValue).expression;
          final shifted = _shiftFormulaReferences(formula, 0, rowDelta);
          node.evaluator.setCellAndEvaluate(addr, FormulaValue(shifted));
        } else if (smartSeq != null) {
          final seq = smartSeq.$1;
          final startIdx = smartSeq.$2;
          final seqIdx =
              ((startIdx - distFromStart) % seq.length + seq.length) %
              seq.length;
          node.evaluator.setCellAndEvaluate(addr, TextValue(seq[seqIdx]));
        } else if (allNumeric && step != null) {
          final firstNum = nums.first!;
          final newVal = firstNum - step * distFromStart;
          node.evaluator.setCellAndEvaluate(addr, NumberValue(newVal));
        } else {
          node.evaluator.setCellAndEvaluate(addr, sourceValues[sourceIdx]);
        }
      }
    }

    _tabularTool.extendSelection(range.endColumn, fillStartRow);
    _refreshLinkedLatexNodes(node);
    _layerController.sceneGraph.bumpVersion();
    DrawingPainter.invalidateAllTiles();
    HapticFeedback.lightImpact();
    setState(() {});
    _autoSaveCanvas();
  }

  /// Fill rightward from [fillStartCol] to [fillEndCol] (inclusive).
  void _performFillRight(int fillStartCol, int fillEndCol) {
    final node = _tabularTool.selectedTabular;
    final range = _getEffectiveRange();
    if (node == null || range == null) return;
    if (fillStartCol > fillEndCol) return;

    final sourceColCount = range.endColumn - range.startColumn + 1;

    for (int r = range.startRow; r <= range.endRow; r++) {
      final sourceCells = <CellNode?>[];
      final sourceValues = <CellValue>[];
      for (int c = range.startColumn; c <= range.endColumn; c++) {
        final cell = node.model.getCell(CellAddress(c, r));
        sourceCells.add(cell);
        sourceValues.add(cell?.value ?? const EmptyValue());
      }

      final hasFormulas = sourceCells.any((c) => c != null && c.isFormula);
      final nums = sourceValues.map((v) => v.asNumber).toList();
      final allNumeric =
          nums.every((n) => n != null) && nums.length >= 2 && !hasFormulas;
      double? step;
      if (allNumeric) step = nums[1]! - nums[0]!;

      for (int targetCol = fillStartCol; targetCol <= fillEndCol; targetCol++) {
        if (targetCol >= node.effectiveColumns + 50) break;
        final sourceIdx = (targetCol - fillStartCol) % sourceColCount;
        final sourceCol = range.startColumn + sourceIdx;
        final sourceCell = sourceCells[sourceIdx];
        final addr = CellAddress(targetCol, r);

        if (hasFormulas && sourceCell != null && sourceCell.isFormula) {
          final colDelta = targetCol - sourceCol;
          final formula = (sourceCell.value as FormulaValue).expression;
          final shifted = _shiftFormulaReferences(formula, colDelta, 0);
          node.evaluator.setCellAndEvaluate(addr, FormulaValue(shifted));
        } else if (allNumeric && step != null) {
          final lastNum = nums.last!;
          final fillIdx = targetCol - range.endColumn;
          node.evaluator.setCellAndEvaluate(
            addr,
            NumberValue(lastNum + step * fillIdx),
          );
        } else {
          node.evaluator.setCellAndEvaluate(addr, sourceValues[sourceIdx]);
        }
      }
    }

    _tabularTool.extendSelection(fillEndCol, range.endRow);
    _refreshLinkedLatexNodes(node);
    _layerController.sceneGraph.bumpVersion();
    DrawingPainter.invalidateAllTiles();
    HapticFeedback.lightImpact();
    setState(() {});
    _autoSaveCanvas();
  }

  /// Fill leftward from [fillStartCol] to [fillEndCol] (inclusive).
  void _performFillLeft(int fillStartCol, int fillEndCol) {
    final node = _tabularTool.selectedTabular;
    final range = _getEffectiveRange();
    if (node == null || range == null) return;
    if (fillStartCol > fillEndCol) return;

    final sourceColCount = range.endColumn - range.startColumn + 1;

    for (int r = range.startRow; r <= range.endRow; r++) {
      final sourceCells = <CellNode?>[];
      final sourceValues = <CellValue>[];
      for (int c = range.startColumn; c <= range.endColumn; c++) {
        final cell = node.model.getCell(CellAddress(c, r));
        sourceCells.add(cell);
        sourceValues.add(cell?.value ?? const EmptyValue());
      }

      final hasFormulas = sourceCells.any((c) => c != null && c.isFormula);
      final nums = sourceValues.map((v) => v.asNumber).toList();
      final allNumeric =
          nums.every((n) => n != null) && nums.length >= 2 && !hasFormulas;
      double? step;
      if (allNumeric) step = nums[1]! - nums[0]!;

      for (int targetCol = fillEndCol; targetCol >= fillStartCol; targetCol--) {
        if (targetCol < 0) break;
        final distFromStart = range.startColumn - targetCol;
        final sourceIdx =
            ((sourceColCount - (distFromStart % sourceColCount)) %
                sourceColCount);
        final sourceCol = range.startColumn + sourceIdx;
        final sourceCell = sourceCells[sourceIdx];
        final addr = CellAddress(targetCol, r);

        if (hasFormulas && sourceCell != null && sourceCell.isFormula) {
          final colDelta = targetCol - sourceCol;
          final formula = (sourceCell.value as FormulaValue).expression;
          final shifted = _shiftFormulaReferences(formula, colDelta, 0);
          node.evaluator.setCellAndEvaluate(addr, FormulaValue(shifted));
        } else if (allNumeric && step != null) {
          final firstNum = nums.first!;
          node.evaluator.setCellAndEvaluate(
            addr,
            NumberValue(firstNum - step * distFromStart),
          );
        } else {
          node.evaluator.setCellAndEvaluate(addr, sourceValues[sourceIdx]);
        }
      }
    }

    _tabularTool.extendSelection(fillStartCol, range.endRow);
    _refreshLinkedLatexNodes(node);
    _layerController.sceneGraph.bumpVersion();
    DrawingPainter.invalidateAllTiles();
    HapticFeedback.lightImpact();
    setState(() {});
    _autoSaveCanvas();
  }
}
