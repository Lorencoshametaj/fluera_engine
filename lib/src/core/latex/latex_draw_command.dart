import 'dart:ui';

/// 🧮 LaTeX Draw Commands — flat, serializable rendering instructions.
///
/// These are the output of [LatexLayoutEngine]. Each command represents
/// a single atomic drawing operation (glyph, line, or path) that can be
/// executed directly on a Flutter [Canvas].
///
/// Commands are designed to be:
/// - **Flat**: no nesting, simple sequential execution
/// - **Serializable**: can be cached and restored
/// - **Canvas-native**: map 1:1 to Canvas draw calls

/// Base class for all LaTeX draw commands.
sealed class LatexDrawCommand {
  /// Convert to JSON for caching/serialization.
  Map<String, dynamic> toJson();

  /// Restore from JSON.
  static LatexDrawCommand fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    switch (type) {
      case 'glyph':
        return GlyphDrawCommand.fromJson(json);
      case 'line':
        return LineDrawCommand.fromJson(json);
      case 'path':
        return PathDrawCommand.fromJson(json);
      default:
        throw ArgumentError('Unknown LatexDrawCommand type: $type');
    }
  }
}

/// Draw a single text glyph at a specific position.
///
/// Used for letters, digits, operators, and Greek symbols.
class GlyphDrawCommand extends LatexDrawCommand {
  /// The character or string to draw.
  final String text;

  /// Position (x, y) in the local coordinate space of the LatexNode.
  final double x;
  final double y;

  /// Font size for this glyph.
  final double fontSize;

  /// Color for this glyph.
  final Color color;

  /// Font family (e.g. 'Latin Modern Math', or system default).
  final String fontFamily;

  /// Whether to render in italic (common for math variables).
  final bool italic;

  /// Whether to render in bold.
  final bool bold;

  GlyphDrawCommand({
    required this.text,
    required this.x,
    required this.y,
    required this.fontSize,
    required this.color,
    this.fontFamily = '',
    this.italic = false,
    this.bold = false,
  });

  @override
  Map<String, dynamic> toJson() => {
    'type': 'glyph',
    'text': text,
    'x': x,
    'y': y,
    'fontSize': fontSize,
    'color': color.toARGB32(),
    if (fontFamily.isNotEmpty) 'fontFamily': fontFamily,
    if (italic) 'italic': true,
    if (bold) 'bold': true,
  };

  factory GlyphDrawCommand.fromJson(Map<String, dynamic> json) {
    return GlyphDrawCommand(
      text: json['text'] as String,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      fontSize: (json['fontSize'] as num).toDouble(),
      color: Color(json['color'] as int),
      fontFamily: json['fontFamily'] as String? ?? '',
      italic: json['italic'] as bool? ?? false,
      bold: json['bold'] as bool? ?? false,
    );
  }
}

/// Draw a straight line segment.
///
/// Used for fraction bars, radical horizontal bars, and vinculum.
class LineDrawCommand extends LatexDrawCommand {
  final double x1;
  final double y1;
  final double x2;
  final double y2;

  /// Line thickness in logical pixels.
  final double thickness;

  /// Line color.
  final Color color;

  LineDrawCommand({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.thickness,
    required this.color,
  });

  @override
  Map<String, dynamic> toJson() => {
    'type': 'line',
    'x1': x1,
    'y1': y1,
    'x2': x2,
    'y2': y2,
    'thickness': thickness,
    'color': color.toARGB32(),
  };

  factory LineDrawCommand.fromJson(Map<String, dynamic> json) {
    return LineDrawCommand(
      x1: (json['x1'] as num).toDouble(),
      y1: (json['y1'] as num).toDouble(),
      x2: (json['x2'] as num).toDouble(),
      y2: (json['y2'] as num).toDouble(),
      thickness: (json['thickness'] as num).toDouble(),
      color: Color(json['color'] as int),
    );
  }
}

/// Draw a path (series of connected points).
///
/// Used for integral signs, radical symbols, large brackets/braces,
/// and other complex mathematical symbols.
class PathDrawCommand extends LatexDrawCommand {
  /// Sequence of points defining the path.
  final List<Offset> points;

  /// Whether to close the path (connect last point to first).
  final bool closed;

  /// Stroke width (0 = filled path).
  final double strokeWidth;

  /// Path color.
  final Color color;

  /// Whether to fill the path instead of stroking it.
  final bool filled;

  PathDrawCommand({
    required this.points,
    this.closed = false,
    this.strokeWidth = 1.0,
    required this.color,
    this.filled = false,
  });

  @override
  Map<String, dynamic> toJson() => {
    'type': 'path',
    'points': points.map((p) => [p.dx, p.dy]).toList(),
    if (closed) 'closed': true,
    'strokeWidth': strokeWidth,
    'color': color.toARGB32(),
    if (filled) 'filled': true,
  };

  factory PathDrawCommand.fromJson(Map<String, dynamic> json) {
    final rawPoints = json['points'] as List<dynamic>;
    final points =
        rawPoints.map((p) {
          final coords = p as List<dynamic>;
          return Offset(
            (coords[0] as num).toDouble(),
            (coords[1] as num).toDouble(),
          );
        }).toList();

    return PathDrawCommand(
      points: points,
      closed: json['closed'] as bool? ?? false,
      strokeWidth: (json['strokeWidth'] as num).toDouble(),
      color: Color(json['color'] as int),
      filled: json['filled'] as bool? ?? false,
    );
  }
}

/// Result of the layout engine computation.
///
/// Contains the flat list of draw commands and the total computed size.
class LatexLayoutResult {
  /// All draw commands in painting order.
  final List<LatexDrawCommand> commands;

  /// Total size of the laid-out expression.
  final Size size;

  /// Baseline offset from the top (for vertical alignment with text).
  final double baseline;

  const LatexLayoutResult({
    required this.commands,
    required this.size,
    this.baseline = 0.0,
  });
}
