import 'dart:ui';
import 'package:flutter/material.dart';

import '../scene_graph/canvas_node.dart';
import '../scene_graph/node_id.dart';
import '../scene_graph/node_visitor.dart';
import '../../utils/uid.dart';
import '../tabular/cell_address.dart';
import '../tabular/cell_node.dart';
import '../tabular/cell_value.dart';
import '../tabular/spreadsheet_model.dart';
import '../tabular/spreadsheet_evaluator.dart';
import '../tabular/merge_region_manager.dart';

/// 📊 Scene graph node for spreadsheet/tabular data.
///
/// Embeds a full [SpreadsheetModel] and [SpreadsheetEvaluator] as a
/// first-class node in the scene graph. Supports transforms (translate,
/// rotate, scale) without losing text precision — text is rendered at
/// final device coordinates.
///
/// The node participates fully in the scene graph pipeline:
/// transforms, opacity, blendMode, effects, hit-testing,
/// serialization, undo/redo.
///
/// ## Usage
///
/// ```dart
/// final node = TabularNode(
///   id: NodeId.generate(),
///   name: 'Budget 2024',
/// );
/// node.evaluator.setCellAndEvaluate(CellAddress(0, 0), NumberValue(100));
/// node.evaluator.setCellAndEvaluate(CellAddress(1, 0), FormulaValue('A1*2'));
/// sceneGraph.addNode(node, layerIndex: 0);
/// ```
class TabularNode extends CanvasNode {
  // ---------------------------------------------------------------------------
  // Fields
  // ---------------------------------------------------------------------------

  /// The spreadsheet data model (sparse cell storage).
  final SpreadsheetModel _model;

  /// The reactive formula evaluator (DAG-based).
  late final SpreadsheetEvaluator _evaluator;

  /// Merged cell region manager.
  final MergeRegionManager mergeManager = MergeRegionManager();

  /// Whether to show column headers (A, B, C...).
  bool showColumnHeaders;

  /// Whether to show row headers (1, 2, 3...).
  bool showRowHeaders;

  /// Header area width (for row numbers).
  double headerWidth;

  /// Header area height (for column letters).
  double headerHeight;

  /// Grid line color.
  Color gridLineColor;

  /// Grid line width.
  double gridLineWidth;

  /// Selection highlight color.
  Color selectionColor;

  /// Background color of the grid.
  Color backgroundColor;

  /// Number of visible columns (viewport hint, 0 = auto from content).
  int visibleColumns;

  /// Number of visible rows (viewport hint, 0 = auto from content).
  int visibleRows;

  // ---------------------------------------------------------------------------
  // Constructor
  // ---------------------------------------------------------------------------

  TabularNode({
    required super.id,
    SpreadsheetModel? model,
    super.name = '',
    super.localTransform,
    super.opacity,
    super.blendMode,
    super.isVisible,
    super.isLocked,
    this.showColumnHeaders = true,
    this.showRowHeaders = true,
    this.headerWidth = 50.0,
    this.headerHeight = 28.0,
    this.gridLineColor = const Color(0xFF3A3A3A),
    this.gridLineWidth = 1.0,
    this.selectionColor = const Color(0x334A90D9),
    this.backgroundColor = const Color(0xFF1E1E1E),
    this.visibleColumns = 10,
    this.visibleRows = 20,
  }) : _model = model ?? SpreadsheetModel() {
    _evaluator = SpreadsheetEvaluator(_model);
  }

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------

  /// The spreadsheet data model.
  SpreadsheetModel get model => _model;

  /// The reactive formula evaluator.
  SpreadsheetEvaluator get evaluator => _evaluator;

  /// Effective number of columns for layout (max of content and visible hint).
  int get effectiveColumns {
    final contentCols = _model.maxColumn + 1;
    return contentCols > visibleColumns ? contentCols : visibleColumns;
  }

  /// Effective number of rows for layout (max of content and visible hint).
  int get effectiveRows {
    final contentRows = _model.maxRow + 1;
    return contentRows > visibleRows ? contentRows : visibleRows;
  }

  // ---------------------------------------------------------------------------
  // Bounds
  // ---------------------------------------------------------------------------

  @override
  Rect get localBounds {
    final cols = effectiveColumns;
    final rows = effectiveRows;

    final gridWidth = _model.totalWidth(cols);
    final gridHeight = _model.totalHeight(rows);

    final totalWidth = (showRowHeaders ? headerWidth : 0) + gridWidth;
    final totalHeight = (showColumnHeaders ? headerHeight : 0) + gridHeight;

    return Rect.fromLTWH(0, 0, totalWidth, totalHeight);
  }

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  @override
  Map<String, dynamic> toJson() {
    final json = baseToJson();
    json['nodeType'] = 'tabular';
    json['model'] = _model.toJson();
    json['showColumnHeaders'] = showColumnHeaders;
    json['showRowHeaders'] = showRowHeaders;
    json['headerWidth'] = headerWidth;
    json['headerHeight'] = headerHeight;
    json['gridLineColor'] = gridLineColor.toARGB32();
    json['gridLineWidth'] = gridLineWidth;
    json['selectionColor'] = selectionColor.toARGB32();
    json['backgroundColor'] = backgroundColor.toARGB32();
    json['visibleColumns'] = visibleColumns;
    json['visibleRows'] = visibleRows;
    if (mergeManager.regionCount > 0) {
      json['mergedRegions'] = mergeManager.toJson();
    }
    return json;
  }

  factory TabularNode.fromJson(Map<String, dynamic> json) {
    final model =
        json['model'] != null
            ? SpreadsheetModel.fromJson(json['model'] as Map<String, dynamic>)
            : SpreadsheetModel();

    final node = TabularNode(
      id: NodeId(json['id'] as String),
      model: model,
      showColumnHeaders: json['showColumnHeaders'] as bool? ?? true,
      showRowHeaders: json['showRowHeaders'] as bool? ?? true,
      headerWidth: (json['headerWidth'] as num?)?.toDouble() ?? 50.0,
      headerHeight: (json['headerHeight'] as num?)?.toDouble() ?? 28.0,
      gridLineColor: Color(json['gridLineColor'] as int? ?? 0xFF3A3A3A),
      gridLineWidth: (json['gridLineWidth'] as num?)?.toDouble() ?? 1.0,
      selectionColor: Color(json['selectionColor'] as int? ?? 0x334A90D9),
      backgroundColor: Color(json['backgroundColor'] as int? ?? 0xFF1E1E1E),
      visibleColumns: json['visibleColumns'] as int? ?? 10,
      visibleRows: json['visibleRows'] as int? ?? 20,
    );
    CanvasNode.applyBaseFromJson(node, json);

    // Re-evaluate all formulas after loading.
    node._evaluator.evaluateAll();

    // Load merge regions.
    if (json['mergedRegions'] != null) {
      node.mergeManager.loadFromJson(json['mergedRegions'] as List<dynamic>);
    }

    return node;
  }

  // ---------------------------------------------------------------------------
  // Clone
  // ---------------------------------------------------------------------------

  @override
  CanvasNode cloneInternal() {
    final cloned = TabularNode(
      id: NodeId(generateUid()),
      model: _model.clone(),
      name: name,
      showColumnHeaders: showColumnHeaders,
      showRowHeaders: showRowHeaders,
      headerWidth: headerWidth,
      headerHeight: headerHeight,
      gridLineColor: gridLineColor,
      gridLineWidth: gridLineWidth,
      selectionColor: selectionColor,
      backgroundColor: backgroundColor,
      visibleColumns: visibleColumns,
      visibleRows: visibleRows,
    );
    cloned.opacity = opacity;
    cloned.blendMode = blendMode;
    cloned.isVisible = isVisible;
    cloned.isLocked = isLocked;
    cloned.localTransform = localTransform.clone();

    // Re-evaluate formulas in the cloned model.
    cloned._evaluator.evaluateAll();

    // Clone merge regions.
    for (final region in mergeManager.regions) {
      cloned.mergeManager.addRegion(region);
    }

    return cloned;
  }

  // ---------------------------------------------------------------------------
  // Visitor
  // ---------------------------------------------------------------------------

  @override
  R accept<R>(NodeVisitor<R> visitor) => visitor.visitTabular(this);

  // ---------------------------------------------------------------------------
  // Dispose
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _evaluator.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Debug
  // ---------------------------------------------------------------------------

  @override
  String toString() =>
      'TabularNode(id: $id, cells: ${_model.cellCount}, '
      'cols: $effectiveColumns, rows: $effectiveRows)';
}
