import 'dart:ui' as ui;
import 'dart:ui';
import '../scene_graph/canvas_node.dart';
import '../scene_graph/node_id.dart';
import '../scene_graph/node_visitor.dart';
import '../../utils/uid.dart';
import '../latex/latex_draw_command.dart';

/// 🧮 Scene graph node for LaTeX mathematical expressions.
///
/// Stores a LaTeX source string and renders the typeset output as vector
/// graphics directly on the Canvas. The node participates fully in the
/// scene graph: transforms, opacity, blendMode, effects, hit-testing,
/// serialization, and undo/redo all work transparently.
///
/// The rendering pipeline:
/// 1. [latexSource] is parsed by `LatexParser` into an AST
/// 2. `LatexLayoutEngine` converts the AST into [LatexDrawCommand]s
/// 3. `LatexRenderer` executes the commands on the Canvas
///
/// Layout results are cached in [_cachedDrawCommands] and invalidated
/// when [latexSource], [fontSize], or [color] change.
///
/// Example:
/// ```dart
/// final node = LatexNode(
///   id: NodeId.generate(),
///   latexSource: r'\frac{a}{b} + \sqrt{c}',
///   fontSize: 24,
///   color: Colors.white,
/// );
/// sceneGraph.addNode(node, layerIndex: 0);
/// ```
class LatexNode extends CanvasNode {
  // ---------------------------------------------------------------------------
  // Fields
  // ---------------------------------------------------------------------------

  /// Raw LaTeX source string, e.g. r"\frac{a}{b}".
  String _latexSource;

  /// Font size for the root expression (in logical pixels).
  double _fontSize;

  /// Text color for the equation.
  Color _color;

  /// Pre-computed draw commands (populated by LatexLayoutEngine).
  LatexLayoutResult? _cachedLayout;

  /// Pre-recorded `ui.Picture` for zero-allocation re-painting.
  /// Invalidated whenever [_cachedLayout] is cleared.
  ui.Picture? cachedPicture;

  /// 🔗 Reactive binding: ID of the source TabularNode (null = standalone).
  String? sourceTabularId;

  /// 🔗 Reactive binding: cell range label (e.g. "A1:B3") to regenerate from.
  String? sourceRangeLabel;

  /// 📊 Chart type for visual rendering (null = not a chart, just LaTeX).
  String? chartType;

  /// 📊 Chart data: category labels (stored directly to avoid TikZ parsing).
  List<String>? chartLabels;

  /// 📊 Chart data: series values (list of series, each a list of doubles).
  List<List<double>>? chartValues;

  /// 📊 Chart data: series names from header row (e.g. 'Revenue', 'Costs').
  List<String>? chartSeriesNames;

  /// 🎨 Custom chart title (null = auto from chart type).
  String? chartTitle;

  /// 🎨 Custom chart background color (ARGB int, null = default dark).
  int? chartBgColor;

  /// 🎨 Whether to show the legend (default true).
  bool chartShowLegend;

  /// 🎨 Whether to show the avg dashed line (default true).
  bool chartShowAvg;

  /// 🎨 Whether to show the scatter trend line (default true).
  bool chartShowTrend;

  /// 🎨 Whether to show value labels on data points (default true).
  bool chartShowValues;

  /// 🎨 Value label display mode: 'value', 'percent', or 'both' (default 'value').
  String chartValueDisplay;

  /// 🎨 Color palette index (0=Neon, 1=Pastel, 2=Earth, 3=Ocean, 4=Sunset).
  int chartColorPalette;

  /// 🎨 Size preset ('small', 'medium', 'large').
  String chartSizePreset;

  /// 🎨 Custom axis color (ARGB int, null = default white 30%).
  int? chartAxisColor;

  // ---------------------------------------------------------------------------
  // Constructor
  // ---------------------------------------------------------------------------

  LatexNode({
    required super.id,
    required String latexSource,
    double fontSize = 20.0,
    Color color = const Color(0xFFFFFFFF),
    super.name = '',
    super.localTransform,
    super.opacity,
    super.blendMode,
    super.isVisible,
    super.isLocked,
    this.sourceTabularId,
    this.sourceRangeLabel,
    this.chartType,
    this.chartLabels,
    this.chartValues,
    this.chartSeriesNames,
    this.chartTitle,
    this.chartBgColor,
    this.chartShowLegend = true,
    this.chartShowAvg = true,
    this.chartShowTrend = true,
    this.chartShowValues = true,
    this.chartValueDisplay = 'value',
    this.chartColorPalette = 0,
    this.chartSizePreset = 'medium',
    this.chartAxisColor,
  }) : _latexSource = latexSource,
       _fontSize = fontSize,
       _color = color;

  // ---------------------------------------------------------------------------
  // Getters / Setters (invalidate cache on change)
  // ---------------------------------------------------------------------------

  /// The raw LaTeX source string.
  String get latexSource => _latexSource;
  set latexSource(String value) {
    if (_latexSource == value) return;
    _latexSource = value;
    _cachedLayout = null;
    cachedPicture = null;
  }

  /// Font size for the root expression.
  double get fontSize => _fontSize;
  set fontSize(double value) {
    if (_fontSize == value) return;
    _fontSize = value;
    _cachedLayout = null;
    cachedPicture = null;
  }

  /// Text color for the equation.
  Color get color => _color;
  set color(Color value) {
    if (_color == value) return;
    _color = value;
    _cachedLayout = null;
    cachedPicture = null;
  }

  /// The cached layout result (draw commands + size).
  ///
  /// Set externally by the layout engine after computing the layout.
  LatexLayoutResult? get cachedLayout => _cachedLayout;
  set cachedLayout(LatexLayoutResult? value) {
    _cachedLayout = value;
    cachedPicture = null; // invalidate picture when layout changes
  }

  /// The cached draw commands for rendering.
  List<LatexDrawCommand>? get cachedDrawCommands => _cachedLayout?.commands;

  /// The cached layout size.
  Size get cachedLayoutSize => _cachedLayout?.size ?? Size.zero;

  // ---------------------------------------------------------------------------
  // Bounds
  // ---------------------------------------------------------------------------

  @override
  Rect get localBounds {
    final layoutSize = cachedLayoutSize;
    if (layoutSize.width > 0 && layoutSize.height > 0) {
      return Rect.fromLTWH(0, 0, layoutSize.width, layoutSize.height);
    }

    // Estimate bounds when layout is not yet computed.
    // Use a rough heuristic: 0.6 * fontSize per character width, 1.4 * fontSize height.
    final estimatedWidth = _fontSize * _latexSource.length * 0.5;
    final estimatedHeight = _fontSize * 1.6;
    return Rect.fromLTWH(0, 0, estimatedWidth, estimatedHeight);
  }

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  @override
  Map<String, dynamic> toJson() {
    final json = baseToJson();
    json['nodeType'] = 'latex';
    json['latexSource'] = _latexSource;
    if (_fontSize != 20.0) json['fontSize'] = _fontSize;
    json['color'] = _color.toARGB32();
    if (sourceTabularId != null) json['sourceTabularId'] = sourceTabularId;
    if (sourceRangeLabel != null) json['sourceRangeLabel'] = sourceRangeLabel;
    if (chartType != null) json['chartType'] = chartType;
    if (chartLabels != null) json['chartLabels'] = chartLabels;
    if (chartValues != null) {
      json['chartValues'] = chartValues!.map((s) => s.toList()).toList();
    }
    if (chartSeriesNames != null) json['chartSeriesNames'] = chartSeriesNames;
    if (chartTitle != null) json['chartTitle'] = chartTitle;
    if (chartBgColor != null) json['chartBgColor'] = chartBgColor;
    if (!chartShowLegend) json['chartShowLegend'] = false;
    if (!chartShowAvg) json['chartShowAvg'] = false;
    if (!chartShowTrend) json['chartShowTrend'] = false;
    if (!chartShowValues) json['chartShowValues'] = false;
    if (chartValueDisplay != 'value')
      json['chartValueDisplay'] = chartValueDisplay;
    if (chartColorPalette != 0) json['chartColorPalette'] = chartColorPalette;
    if (chartSizePreset != 'medium') json['chartSizePreset'] = chartSizePreset;
    if (chartAxisColor != null) json['chartAxisColor'] = chartAxisColor;
    return json;
  }

  /// Deserialize from JSON.
  factory LatexNode.fromJson(Map<String, dynamic> json) {
    final node = LatexNode(
      id: NodeId(json['id'] as String),
      latexSource: json['latexSource'] as String? ?? '',
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 20.0,
      color: Color(json['color'] as int? ?? 0xFFFFFFFF),
      sourceTabularId: json['sourceTabularId'] as String?,
      sourceRangeLabel: json['sourceRangeLabel'] as String?,
      chartType: json['chartType'] as String?,
      chartLabels: (json['chartLabels'] as List<dynamic>?)?.cast<String>(),
      chartValues:
          (json['chartValues'] as List<dynamic>?)
              ?.map(
                (s) =>
                    (s as List<dynamic>)
                        .map((v) => (v as num).toDouble())
                        .toList(),
              )
              .toList(),
      chartSeriesNames:
          (json['chartSeriesNames'] as List<dynamic>?)?.cast<String>(),
      chartTitle: json['chartTitle'] as String?,
      chartBgColor: json['chartBgColor'] as int?,
      chartShowLegend: json['chartShowLegend'] as bool? ?? true,
      chartShowAvg: json['chartShowAvg'] as bool? ?? true,
      chartShowTrend: json['chartShowTrend'] as bool? ?? true,
      chartShowValues: json['chartShowValues'] as bool? ?? true,
      chartValueDisplay: json['chartValueDisplay'] as String? ?? 'value',
      chartColorPalette: json['chartColorPalette'] as int? ?? 0,
      chartSizePreset: json['chartSizePreset'] as String? ?? 'medium',
      chartAxisColor: json['chartAxisColor'] as int?,
    );
    CanvasNode.applyBaseFromJson(node, json);
    return node;
  }

  // ---------------------------------------------------------------------------
  // Clone
  // ---------------------------------------------------------------------------

  @override
  CanvasNode cloneInternal() {
    final cloned = LatexNode(
      id: NodeId(generateUid()),
      latexSource: _latexSource,
      fontSize: _fontSize,
      color: _color,
      name: name,
      sourceTabularId: sourceTabularId,
      sourceRangeLabel: sourceRangeLabel,
      chartType: chartType,
      chartLabels: chartLabels != null ? List<String>.from(chartLabels!) : null,
      chartValues:
          chartValues != null
              ? chartValues!.map((s) => List<double>.from(s)).toList()
              : null,
      chartSeriesNames:
          chartSeriesNames != null
              ? List<String>.from(chartSeriesNames!)
              : null,
      chartTitle: chartTitle,
      chartBgColor: chartBgColor,
      chartShowLegend: chartShowLegend,
      chartShowAvg: chartShowAvg,
      chartShowTrend: chartShowTrend,
      chartShowValues: chartShowValues,
      chartValueDisplay: chartValueDisplay,
      chartColorPalette: chartColorPalette,
      chartSizePreset: chartSizePreset,
      chartAxisColor: chartAxisColor,
    );
    cloned.opacity = opacity;
    cloned.blendMode = blendMode;
    cloned.isVisible = isVisible;
    cloned.isLocked = isLocked;
    cloned.localTransform = localTransform.clone();
    return cloned;
  }

  // ---------------------------------------------------------------------------
  // Visitor
  // ---------------------------------------------------------------------------

  @override
  R accept<R>(NodeVisitor<R> visitor) => visitor.visitLatex(this);

  // ---------------------------------------------------------------------------
  // Debug
  // ---------------------------------------------------------------------------

  @override
  String toString() {
    final preview =
        _latexSource.length > 30
            ? '${_latexSource.substring(0, 30)}...'
            : _latexSource;
    return 'LatexNode(id: $id, source: "$preview", fontSize: $_fontSize)';
  }
}
