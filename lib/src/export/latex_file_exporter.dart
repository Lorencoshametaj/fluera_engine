import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/nodes/latex_node.dart';
import '../core/nodes/layer_node.dart';
import '../core/scene_graph/canvas_node.dart';
import '../core/scene_graph/scene_graph.dart';
import '../core/nodes/group_node.dart';

/// 📄 Exports all LaTeX content from a scene graph to a standalone `.tex` file.
///
/// Supports:
/// - One-shot export via [exportDocument]
/// - Live auto-sync via [watchAndExport] (debounced writes on change)
///
/// ## Usage
///
/// ```dart
/// final exporter = LatexFileExporter();
/// // One-shot
/// final texSource = exporter.exportDocument(sceneGraph);
/// File('report.tex').writeAsStringSync(texSource);
///
/// // Live sync
/// exporter.watchAndExport(sceneGraph, layerController, '/path/to/report.tex');
/// // ... later
/// exporter.dispose();
/// ```
class LatexFileExporter {
  Timer? _debounceTimer;
  VoidCallback? _listenerCallback;
  ChangeNotifier? _listenedNotifier;

  /// Export all LaTeX nodes to a complete `.tex` document string.
  String exportDocument(SceneGraph sceneGraph, {TexExportOptions? options}) {
    final opts = options ?? const TexExportOptions();
    final latexNodes = _collectLatexNodes(sceneGraph);

    if (latexNodes.isEmpty) {
      return _wrapDocument('% No LaTeX content found in this canvas.', opts);
    }

    final sections = <String>[];
    for (int i = 0; i < latexNodes.length; i++) {
      final node = latexNodes[i];
      final label = node.name.isNotEmpty ? node.name : 'Section ${i + 1}';
      final source = node.latexSource;

      if (opts.addComments) {
        sections.add('% --- $label ---');
      }
      sections.add(source);
      sections.add('');
    }

    return _wrapDocument(sections.join('\n'), opts);
  }

  /// Start watching a [ChangeNotifier] (typically `LayerController`) for
  /// changes and auto-export to [outputPath] with debouncing.
  void watchAndExport(
    SceneGraph sceneGraph,
    ChangeNotifier notifier,
    String outputPath, {
    Duration debounce = const Duration(milliseconds: 500),
    TexExportOptions? options,
  }) {
    dispose(); // Clean up any previous watcher

    _listenedNotifier = notifier;
    _listenerCallback = () {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(debounce, () {
        final doc = exportDocument(sceneGraph, options: options);
        File(outputPath).writeAsStringSync(doc);
      });
    };

    notifier.addListener(_listenerCallback!);
  }

  /// Stop watching and clean up.
  void dispose() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    if (_listenerCallback != null && _listenedNotifier != null) {
      _listenedNotifier!.removeListener(_listenerCallback!);
    }
    _listenerCallback = null;
    _listenedNotifier = null;
  }

  // ---------------------------------------------------------------------------
  // Document assembly
  // ---------------------------------------------------------------------------

  String _wrapDocument(String body, TexExportOptions opts) {
    final buf = StringBuffer();

    // Document class
    buf.writeln('\\documentclass[${opts.fontSize}]{${opts.documentClass}}');
    buf.writeln();

    // Auto-detect required packages from content
    final packages = _detectPackages(body, opts);
    for (final pkg in packages) {
      if (pkg.contains('[')) {
        buf.writeln('\\usepackage$pkg');
      } else {
        buf.writeln('\\usepackage{$pkg}');
      }
    }
    buf.writeln();

    // Title / Author / Date
    if (opts.title != null) buf.writeln('\\title{${opts.title}}');
    if (opts.author != null) buf.writeln('\\author{${opts.author}}');
    if (opts.date != null) {
      buf.writeln('\\date{${opts.date}}');
    } else {
      buf.writeln('\\date{\\today}');
    }
    buf.writeln();

    // Begin document
    buf.writeln('\\begin{document}');
    if (opts.title != null) buf.writeln('\\maketitle');
    buf.writeln();

    buf.writeln(body);
    buf.writeln();

    buf.writeln('\\end{document}');
    return buf.toString();
  }

  List<String> _detectPackages(String body, TexExportOptions opts) {
    final pkgs = <String>{};

    // Always include essentials
    pkgs.add('[utf8]{inputenc}');
    pkgs.add('[T1]{fontenc}');

    // Detect TikZ/pgfplots
    if (body.contains('\\begin{tikzpicture}')) {
      pkgs.add('tikz');
      if (body.contains('\\begin{axis}') || body.contains('\\addplot')) {
        pkgs.add('pgfplots');
      }
    }

    // Detect math environments
    if (body.contains('\\begin{equation') ||
        body.contains('\\begin{align') ||
        body.contains('\\frac') ||
        body.contains('\\sum') ||
        body.contains('\\sqrt')) {
      pkgs.add('amsmath');
      pkgs.add('amssymb');
    }

    // Detect matrices
    if (body.contains('\\begin{bmatrix}') ||
        body.contains('\\begin{pmatrix}') ||
        body.contains('\\begin{vmatrix}')) {
      pkgs.add('amsmath');
    }

    // Detect tables with booktabs
    if (body.contains('\\toprule') ||
        body.contains('\\midrule') ||
        body.contains('\\bottomrule')) {
      pkgs.add('booktabs');
    }

    // Detect multicolumn
    if (body.contains('\\multicolumn')) {
      pkgs.add('multicol');
    }

    // Detect hyperlinks
    if (body.contains('\\href') || body.contains('\\url')) {
      pkgs.add('hyperref');
    }

    // Add user-specified extra packages
    pkgs.addAll(opts.extraPackages);

    return pkgs.toList()..sort();
  }

  // ---------------------------------------------------------------------------
  // Node collection
  // ---------------------------------------------------------------------------

  List<LatexNode> _collectLatexNodes(SceneGraph sceneGraph) {
    final nodes = <LatexNode>[];
    _collectFromNode(sceneGraph.rootNode, nodes);
    return nodes;
  }

  void _collectFromNode(CanvasNode node, List<LatexNode> result) {
    if (node is LatexNode && node.isVisible) {
      result.add(node);
    } else if (node is GroupNode) {
      for (final child in node.children) {
        _collectFromNode(child, result);
      }
    } else if (node is LayerNode) {
      for (final child in node.children) {
        _collectFromNode(child, result);
      }
    }
  }
}

/// Configuration for `.tex` document export.
class TexExportOptions {
  final String documentClass;
  final String fontSize;
  final String? title;
  final String? author;
  final String? date;
  final List<String> extraPackages;
  final bool addComments;

  const TexExportOptions({
    this.documentClass = 'article',
    this.fontSize = '12pt',
    this.title,
    this.author,
    this.date,
    this.extraPackages = const [],
    this.addComments = true,
  });
}
