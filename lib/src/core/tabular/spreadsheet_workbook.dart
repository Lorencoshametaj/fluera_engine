import 'cell_address.dart';
import 'cell_value.dart';
import 'spreadsheet_evaluator.dart';
import 'spreadsheet_model.dart';

/// 📊 A workbook containing multiple spreadsheet sheets.
///
/// Supports cross-sheet references via `Sheet2!A1` syntax.
/// Each sheet has a unique name and its own [SpreadsheetModel] and
/// [SpreadsheetEvaluator].
///
/// ## Usage
///
/// ```dart
/// final wb = SpreadsheetWorkbook();
/// wb.addSheet('Revenue');
/// wb.addSheet('Summary');
///
/// // Set values in Revenue sheet.
/// wb.getEvaluator('Revenue')!
///   .setCellAndEvaluate(CellAddress(0, 0), NumberValue(1000));
///
/// // Reference from Summary sheet.
/// wb.getEvaluator('Summary')!
///   .setCellAndEvaluate(CellAddress(0, 0), FormulaValue("Revenue!A1 * 2"));
/// ```
class SpreadsheetWorkbook {
  /// Ordered list of sheet names.
  final List<String> _sheetNames = [];

  /// Sheet models keyed by name.
  final Map<String, SpreadsheetModel> _models = {};

  /// Sheet evaluators keyed by name.
  final Map<String, SpreadsheetEvaluator> _evaluators = {};

  /// Name of the currently active sheet.
  String? _activeSheet;

  /// Create an empty workbook.
  SpreadsheetWorkbook();

  // ---------------------------------------------------------------------------
  // Sheet Management
  // ---------------------------------------------------------------------------

  /// Add a new sheet with the given [name].
  ///
  /// Returns the model for the new sheet.
  /// Throws if a sheet with the same name already exists.
  SpreadsheetModel addSheet(String name, {SpreadsheetModel? model}) {
    if (_models.containsKey(name)) {
      throw ArgumentError('Sheet "$name" already exists');
    }
    final m = model ?? SpreadsheetModel();
    _sheetNames.add(name);
    _models[name] = m;

    final evaluator = SpreadsheetEvaluator(m);
    _evaluators[name] = evaluator;

    // Register cross-sheet reference resolver.
    _registerCrossSheetResolver(name, evaluator);

    _activeSheet ??= name;
    return m;
  }

  /// Remove a sheet by name. Returns true if removed.
  bool removeSheet(String name) {
    if (!_models.containsKey(name)) return false;
    _sheetNames.remove(name);
    _evaluators[name]?.dispose();
    _evaluators.remove(name);
    _models.remove(name);

    if (_activeSheet == name) {
      _activeSheet = _sheetNames.isNotEmpty ? _sheetNames.first : null;
    }
    return true;
  }

  /// Rename a sheet. Returns true if renamed successfully.
  bool renameSheet(String oldName, String newName) {
    if (!_models.containsKey(oldName)) return false;
    if (_models.containsKey(newName)) return false;

    final idx = _sheetNames.indexOf(oldName);
    _sheetNames[idx] = newName;

    _models[newName] = _models.remove(oldName)!;
    _evaluators[newName] = _evaluators.remove(oldName)!;

    if (_activeSheet == oldName) _activeSheet = newName;
    return true;
  }

  /// Reorder a sheet from [oldIndex] to [newIndex].
  void reorderSheet(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _sheetNames.length) return;
    if (newIndex < 0 || newIndex >= _sheetNames.length) return;
    final name = _sheetNames.removeAt(oldIndex);
    _sheetNames.insert(newIndex, name);
  }

  // ---------------------------------------------------------------------------
  // Accessors
  // ---------------------------------------------------------------------------

  /// All sheet names in order.
  List<String> get sheetNames => List.unmodifiable(_sheetNames);

  /// Number of sheets.
  int get sheetCount => _sheetNames.length;

  /// Whether a sheet with the given name exists.
  bool hasSheet(String name) => _models.containsKey(name);

  /// Get the model for a sheet by name.
  SpreadsheetModel? getModel(String name) => _models[name];

  /// Get the evaluator for a sheet by name.
  SpreadsheetEvaluator? getEvaluator(String name) => _evaluators[name];

  /// The active sheet name.
  String? get activeSheet => _activeSheet;

  /// Set the active sheet.
  set activeSheet(String? name) {
    if (name != null && !_models.containsKey(name)) {
      throw ArgumentError('Sheet "$name" does not exist');
    }
    _activeSheet = name;
  }

  // ---------------------------------------------------------------------------
  // Cross-Sheet References
  // ---------------------------------------------------------------------------

  /// Resolve a cross-sheet reference like `Sheet2!A1`.
  ///
  /// Sheet name lookup is case-insensitive because the tokenizer
  /// normalizes identifiers to uppercase.
  CellValue resolveCrossSheetRef(String sheetName, CellAddress address) {
    // Case-insensitive lookup since tokenizer uppercases identifiers.
    final upper = sheetName.toUpperCase();
    SpreadsheetEvaluator? evaluator;
    for (final entry in _evaluators.entries) {
      if (entry.key.toUpperCase() == upper) {
        evaluator = entry.value;
        break;
      }
    }
    if (evaluator == null) {
      return ErrorValue(
        CellError.invalidRef,
        message: 'Unknown sheet: $sheetName',
      );
    }
    return evaluator.getComputedValue(address);
  }

  /// Register a callback on the evaluator to handle `SheetName!CellRef` tokens.
  void _registerCrossSheetResolver(String name, SpreadsheetEvaluator eval) {
    eval.crossSheetResolver = (String sheetName, CellAddress addr) {
      return resolveCrossSheetRef(sheetName, addr);
    };
  }

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  /// Serialize the workbook to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'sheetNames': _sheetNames,
      'sheets': {for (final name in _sheetNames) name: _models[name]!.toJson()},
      if (_activeSheet != null) 'activeSheet': _activeSheet,
    };
  }

  /// Deserialize a workbook from JSON.
  factory SpreadsheetWorkbook.fromJson(Map<String, dynamic> json) {
    final wb = SpreadsheetWorkbook();
    final names = (json['sheetNames'] as List).cast<String>();
    final sheets = json['sheets'] as Map<String, dynamic>;

    for (final name in names) {
      final modelJson = sheets[name] as Map<String, dynamic>;
      final model = SpreadsheetModel.fromJson(modelJson);
      wb.addSheet(name, model: model);
      wb.getEvaluator(name)?.evaluateAll();
    }

    wb._activeSheet = json['activeSheet'] as String?;
    return wb;
  }

  /// Clone the entire workbook.
  SpreadsheetWorkbook clone() {
    final wb = SpreadsheetWorkbook();
    for (final name in _sheetNames) {
      wb.addSheet(name, model: _models[name]!.clone());
    }
    wb._activeSheet = _activeSheet;
    return wb;
  }

  // ---------------------------------------------------------------------------
  // Dispose
  // ---------------------------------------------------------------------------

  /// Dispose all evaluators.
  void dispose() {
    for (final eval in _evaluators.values) {
      eval.dispose();
    }
    _evaluators.clear();
    _models.clear();
    _sheetNames.clear();
  }
}
