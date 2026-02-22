/// 🖥️ CODE GENERATOR — Generates Flutter/CSS/SwiftUI from inspect reports.
///
/// Translates an [InspectReport] into platform-specific code snippets
/// for seamless design-to-development handoff.
///
/// ```dart
/// final report = inspectEngine.inspect(node);
/// final flutter = CodeGenerator.generateFlutter(report);
/// final css = CodeGenerator.generateCSS(report);
/// final swift = CodeGenerator.generateSwiftUI(report);
/// ```
library;

import 'dart:ui';
import 'inspect_engine.dart';

// =============================================================================
// GENERATED CODE
// =============================================================================

/// A generated code snippet with its target language.
class GeneratedCode {
  /// Target language identifier (e.g. 'dart', 'css', 'swift').
  final String language;

  /// The generated code string.
  final String code;

  const GeneratedCode({required this.language, required this.code});

  @override
  String toString() => '// $language\n$code';
}

// =============================================================================
// CODE GENERATOR
// =============================================================================

/// Generates platform-specific code from [InspectReport]s.
class CodeGenerator {
  const CodeGenerator._();

  // ---------------------------------------------------------------------------
  // Flutter
  // ---------------------------------------------------------------------------

  /// Generate a Flutter `Container` widget from an inspect report.
  static GeneratedCode generateFlutter(InspectReport report) {
    final buf = StringBuffer();

    buf.writeln('Container(');

    // Size.
    buf.writeln('  width: ${report.size.width.toStringAsFixed(1)},');
    buf.writeln('  height: ${report.size.height.toStringAsFixed(1)},');

    // Decoration.
    buf.writeln('  decoration: BoxDecoration(');

    // Fill.
    if (report.fills.isNotEmpty) {
      final fill = report.fills.first;
      if (fill.color != null) {
        buf.writeln(
          '    color: Color(0x${fill.color!.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}),',
        );
      }
    }

    // Border.
    if (report.stroke != null) {
      final s = report.stroke!;
      buf.writeln('    border: Border.all(');
      buf.writeln(
        '      color: Color(0x${s.color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}),',
      );
      buf.writeln('      width: ${s.width.toStringAsFixed(1)},');
      buf.writeln('    ),');
    }

    // Border radius.
    if (report.cornerRadius != null && report.cornerRadius! > 0) {
      buf.writeln(
        '    borderRadius: BorderRadius.circular(${report.cornerRadius!.toStringAsFixed(1)}),',
      );
    }

    // Box shadows.
    final shadows = report.effects.where(
      (e) => e.type.contains('DropShadow') || e.type.contains('Shadow'),
    );
    if (shadows.isNotEmpty) {
      buf.writeln('    boxShadow: [');
      for (final shadow in shadows) {
        final offset = shadow.parameters['offset'] as Map<String, dynamic>?;
        final dx = offset?['dx'] ?? 0.0;
        final dy = offset?['dy'] ?? 0.0;
        final blur = shadow.parameters['blur'] ?? 0.0;
        final color = shadow.parameters['color'] ?? '#000000';
        buf.writeln('      BoxShadow(');
        buf.writeln('        offset: Offset($dx, $dy),');
        buf.writeln('        blurRadius: $blur,');
        buf.writeln(
          "        color: Color(0xFF${_stripHash(color as String)}),",
        );
        buf.writeln('      ),');
      }
      buf.writeln('    ],');
    }

    buf.writeln('  ),');

    // Opacity.
    if (report.opacity < 1.0) {
      // Wrap note — in practice you'd wrap with Opacity widget.
      buf.writeln('  // opacity: ${report.opacity.toStringAsFixed(2)}');
    }

    // Typography child.
    if (report.typography != null) {
      buf.writeln('  child: Text(');
      buf.writeln("    'Text',");
      buf.writeln('    style: TextStyle(');
      final t = report.typography!;
      if (t.fontFamily != null)
        buf.writeln("      fontFamily: '${t.fontFamily}',");
      if (t.fontSize != null) {
        buf.writeln('      fontSize: ${t.fontSize!.toStringAsFixed(1)},');
      }
      if (t.letterSpacing != null) {
        buf.writeln(
          '      letterSpacing: ${t.letterSpacing!.toStringAsFixed(1)},',
        );
      }
      if (t.lineHeight != null) {
        buf.writeln('      height: ${t.lineHeight!.toStringAsFixed(2)},');
      }
      buf.writeln('    ),');
      buf.writeln('  ),');
    }

    buf.writeln(')');
    return GeneratedCode(language: 'dart', code: buf.toString());
  }

  // ---------------------------------------------------------------------------
  // CSS
  // ---------------------------------------------------------------------------

  /// Generate CSS properties from an inspect report.
  static GeneratedCode generateCSS(InspectReport report) {
    final buf = StringBuffer();
    buf.writeln('.${_cssClassName(report.nodeName)} {');

    // Size.
    buf.writeln('  width: ${report.size.width.toStringAsFixed(0)}px;');
    buf.writeln('  height: ${report.size.height.toStringAsFixed(0)}px;');

    // Position.
    if (report.position.dx != 0 || report.position.dy != 0) {
      buf.writeln('  position: absolute;');
      buf.writeln('  left: ${report.position.dx.toStringAsFixed(0)}px;');
      buf.writeln('  top: ${report.position.dy.toStringAsFixed(0)}px;');
    }

    // Background.
    if (report.fills.isNotEmpty) {
      final fill = report.fills.first;
      if (fill.hexColor != null) {
        buf.writeln('  background-color: ${fill.hexColor};');
      } else if (fill.gradientType != null && fill.gradientColors != null) {
        final colors = fill.gradientColors!
            .map((c) => _colorToCSS(c))
            .join(', ');
        final type =
            fill.gradientType == 'radial'
                ? 'radial-gradient'
                : 'linear-gradient';
        buf.writeln('  background: $type($colors);');
      }
    }

    // Border.
    if (report.stroke != null) {
      buf.writeln(
        '  border: ${report.stroke!.width.toStringAsFixed(0)}px solid ${report.stroke!.hexColor};',
      );
    }

    // Border radius.
    if (report.cornerRadius != null && report.cornerRadius! > 0) {
      buf.writeln(
        '  border-radius: ${report.cornerRadius!.toStringAsFixed(0)}px;',
      );
    }

    // Opacity.
    if (report.opacity < 1.0) {
      buf.writeln('  opacity: ${report.opacity.toStringAsFixed(2)};');
    }

    // Blend mode.
    if (report.blendMode != 'srcOver') {
      buf.writeln('  mix-blend-mode: ${_cssBlendMode(report.blendMode)};');
    }

    // Box shadow.
    final shadows = report.effects.where((e) => e.type.contains('DropShadow'));
    if (shadows.isNotEmpty) {
      final parts = shadows.map((s) {
        final offset = s.parameters['offset'] as Map<String, dynamic>?;
        final dx = offset?['dx'] ?? 0;
        final dy = offset?['dy'] ?? 0;
        final blur = s.parameters['blur'] ?? 0;
        final color = s.parameters['color'] ?? '#000000';
        return '${dx}px ${dy}px ${blur}px $color';
      });
      buf.writeln('  box-shadow: ${parts.join(', ')};');
    }

    // Typography.
    if (report.typography != null) {
      final t = report.typography!;
      if (t.fontFamily != null)
        buf.writeln("  font-family: '${t.fontFamily}';");
      if (t.fontSize != null) {
        buf.writeln('  font-size: ${t.fontSize!.toStringAsFixed(0)}px;');
      }
      if (t.fontWeight != null) buf.writeln('  font-weight: ${t.fontWeight};');
      if (t.letterSpacing != null) {
        buf.writeln(
          '  letter-spacing: ${t.letterSpacing!.toStringAsFixed(1)}px;',
        );
      }
      if (t.lineHeight != null) {
        buf.writeln('  line-height: ${t.lineHeight!.toStringAsFixed(2)};');
      }
      if (t.color != null) {
        buf.writeln('  color: ${_colorToCSS(t.color!)};');
      }
    }

    // Layout (FrameNode).
    if (report.frameLayout != null) {
      final fl = report.frameLayout!;
      buf.writeln('  display: flex;');
      buf.writeln(
        '  flex-direction: ${fl.direction == 'horizontal' ? 'row' : 'column'};',
      );
      buf.writeln('  gap: ${fl.spacing.toStringAsFixed(0)}px;');
      buf.writeln('  justify-content: ${_cssJustify(fl.mainAxisAlignment)};');
      buf.writeln('  align-items: ${_cssAlign(fl.crossAxisAlignment)};');
    }

    buf.writeln('}');
    return GeneratedCode(language: 'css', code: buf.toString());
  }

  // ---------------------------------------------------------------------------
  // SwiftUI
  // ---------------------------------------------------------------------------

  /// Generate SwiftUI code from an inspect report.
  static GeneratedCode generateSwiftUI(InspectReport report) {
    final buf = StringBuffer();

    // Determine base view.
    if (report.typography != null) {
      buf.writeln('Text("Text")');
      final t = report.typography!;
      if (t.fontFamily != null || t.fontSize != null) {
        final size = t.fontSize?.toStringAsFixed(0) ?? '16';
        buf.writeln(
          '    .font(.custom("${t.fontFamily ?? 'system'}", size: $size))',
        );
      }
      if (t.color != null) {
        buf.writeln(
          '    .foregroundColor(Color(hex: "${_colorToHex(t.color!)}"))',
        );
      }
    } else if (report.frameLayout != null) {
      final dir = report.frameLayout!.direction == 'horizontal' ? 'H' : 'V';
      buf.writeln(
        '${dir}Stack(spacing: ${report.frameLayout!.spacing.toStringAsFixed(0)}) {',
      );
      buf.writeln('    // children');
      buf.writeln('}');
    } else {
      buf.writeln('Rectangle()');
    }

    // Frame.
    buf.writeln(
      '    .frame(width: ${report.size.width.toStringAsFixed(0)}, '
      'height: ${report.size.height.toStringAsFixed(0)})',
    );

    // Background.
    if (report.fills.isNotEmpty) {
      final fill = report.fills.first;
      if (fill.hexColor != null) {
        buf.writeln('    .background(Color(hex: "${fill.hexColor}"))');
      }
    }

    // Corner radius.
    if (report.cornerRadius != null && report.cornerRadius! > 0) {
      buf.writeln(
        '    .cornerRadius(${report.cornerRadius!.toStringAsFixed(0)})',
      );
    }

    // Border.
    if (report.stroke != null) {
      buf.writeln(
        '    .overlay(RoundedRectangle(cornerRadius: ${report.cornerRadius?.toStringAsFixed(0) ?? '0'})'
        '.stroke(Color(hex: "${report.stroke!.hexColor}"), '
        'lineWidth: ${report.stroke!.width.toStringAsFixed(0)}))',
      );
    }

    // Opacity.
    if (report.opacity < 1.0) {
      buf.writeln('    .opacity(${report.opacity.toStringAsFixed(2)})');
    }

    // Shadow.
    final shadows = report.effects.where((e) => e.type.contains('DropShadow'));
    for (final s in shadows) {
      final blur = s.parameters['blur'] ?? 0;
      final offset = s.parameters['offset'] as Map<String, dynamic>?;
      buf.writeln(
        '    .shadow(radius: $blur, x: ${offset?['dx'] ?? 0}, y: ${offset?['dy'] ?? 0})',
      );
    }

    return GeneratedCode(language: 'swift', code: buf.toString());
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static String _cssClassName(String name) =>
      name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');

  static String _stripHash(String hex) =>
      hex.startsWith('#') ? hex.substring(1) : hex;

  static String _colorToCSS(dynamic color) {
    if (color is String) return color;
    final c = color as Color;
    final argb = c.toARGB32();
    return '#${argb.toRadixString(16).padLeft(8, '0').substring(2)}';
  }

  static String _colorToHex(dynamic color) {
    if (color is String) return color;
    final c = color as Color;
    final argb = c.toARGB32();
    return '#${argb.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }

  static String _cssJustify(String alignment) => switch (alignment) {
    'start' => 'flex-start',
    'end' => 'flex-end',
    'center' => 'center',
    'spaceBetween' => 'space-between',
    'spaceAround' => 'space-around',
    'spaceEvenly' => 'space-evenly',
    _ => 'flex-start',
  };

  static String _cssAlign(String alignment) => switch (alignment) {
    'start' => 'flex-start',
    'end' => 'flex-end',
    'center' => 'center',
    'stretch' => 'stretch',
    'baseline' => 'baseline',
    _ => 'flex-start',
  };

  static String _cssBlendMode(String blendMode) => switch (blendMode) {
    'multiply' => 'multiply',
    'screen' => 'screen',
    'overlay' => 'overlay',
    'darken' => 'darken',
    'lighten' => 'lighten',
    'colorDodge' => 'color-dodge',
    'colorBurn' => 'color-burn',
    'hardLight' => 'hard-light',
    'softLight' => 'soft-light',
    'difference' => 'difference',
    'exclusion' => 'exclusion',
    'hue' => 'hue',
    'saturation' => 'saturation',
    'color' => 'color',
    'luminosity' => 'luminosity',
    _ => 'normal',
  };
}
