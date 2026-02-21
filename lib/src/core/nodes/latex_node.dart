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
  }

  /// Font size for the root expression.
  double get fontSize => _fontSize;
  set fontSize(double value) {
    if (_fontSize == value) return;
    _fontSize = value;
    _cachedLayout = null;
  }

  /// Text color for the equation.
  Color get color => _color;
  set color(Color value) {
    if (_color == value) return;
    _color = value;
    _cachedLayout = null;
  }

  /// The cached layout result (draw commands + size).
  ///
  /// Set externally by the layout engine after computing the layout.
  LatexLayoutResult? get cachedLayout => _cachedLayout;
  set cachedLayout(LatexLayoutResult? value) => _cachedLayout = value;

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
    return json;
  }

  /// Deserialize from JSON.
  factory LatexNode.fromJson(Map<String, dynamic> json) {
    final node = LatexNode(
      id: NodeId(json['id'] as String),
      latexSource: json['latexSource'] as String? ?? '',
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 20.0,
      color: Color(json['color'] as int? ?? 0xFFFFFFFF),
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
