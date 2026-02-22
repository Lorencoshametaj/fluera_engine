import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Image;
import 'package:logging/logging.dart';

import '../core/scene_graph/canvas_node.dart';
import '../core/scene_graph/scene_graph.dart';
import '../core/nodes/group_node.dart';
import '../core/nodes/frame_node.dart';
import '../core/nodes/path_node.dart';
import '../core/nodes/text_node.dart';
import '../core/nodes/image_node.dart';
import '../core/nodes/rich_text_node.dart';
import '../core/nodes/shape_node.dart';
import '../rendering/scene_graph/scene_graph_renderer.dart';
import 'pdf_export_writer.dart';
import 'saved_export_area.dart';
import 'raster_image_encoder.dart';

/// Supported export formats.
enum ExportFormat {
  /// Lossless raster (default).
  png,

  /// Lossy raster with configurable quality.
  jpeg,

  /// Modern lossy/lossless raster format.
  webp,

  /// Scalable vector graphics.
  svg,

  /// Portable Document Format (vector).
  pdf,
}

/// Export configuration.
class ExportConfig {
  /// Output format.
  final ExportFormat format;

  /// Device pixel ratio (1x, 2x, 3x). 1.0 = 72 DPI, 2.0 = 144 DPI, etc.
  final double pixelRatio;

  /// Optional background color. Null = transparent.
  final ui.Color? backgroundColor;

  /// Optional fixed region to export. Null = auto-fit to content bounds.
  final ui.Rect? region;

  /// Padding around the exported content (in logical pixels).
  final double padding;

  /// Whether to include hidden layers in the export.
  final bool includeHidden;

  /// Quality for lossy compression (0-100). Higher = better quality.
  /// Applies to JPEG and WebP formats. Ignored for PNG/SVG/PDF.
  final int quality;

  // PDF-specific options

  /// Enable PDF/A-1b archival conformance.
  final bool pdfAConformance;

  /// Watermark text to overlay on PDF pages.
  final String? pdfWatermark;

  /// Password to protect the PDF (future use).
  final String? pdfPassword;

  /// Enable Flate compression for PDF streams.
  final bool enableCompression;

  const ExportConfig({
    this.format = ExportFormat.png,
    this.pixelRatio = 2.0,
    this.backgroundColor,
    this.region,
    this.padding = 0,
    this.includeHidden = false,
    this.quality = 85,
    this.pdfAConformance = false,
    this.pdfWatermark,
    this.pdfPassword,
    this.enableCompression = true,
  });

  /// Create a 1x PNG export config.
  const ExportConfig.png1x({
    this.backgroundColor,
    this.region,
    this.padding = 0,
    this.includeHidden = false,
  }) : format = ExportFormat.png,
       pixelRatio = 1.0,
       quality = 100,
       pdfAConformance = false,
       pdfWatermark = null,
       pdfPassword = null,
       enableCompression = true;

  /// Create a 2x PNG export config (Retina).
  const ExportConfig.png2x({
    this.backgroundColor,
    this.region,
    this.padding = 0,
    this.includeHidden = false,
  }) : format = ExportFormat.png,
       pixelRatio = 2.0,
       quality = 100,
       pdfAConformance = false,
       pdfWatermark = null,
       pdfPassword = null,
       enableCompression = true;

  /// Create a 3x PNG export config.
  const ExportConfig.png3x({
    this.backgroundColor,
    this.region,
    this.padding = 0,
    this.includeHidden = false,
  }) : format = ExportFormat.png,
       pixelRatio = 3.0,
       quality = 100,
       pdfAConformance = false,
       pdfWatermark = null,
       pdfPassword = null,
       enableCompression = true;
}

/// Result of an export operation.
class ExportResult {
  /// The exported bytes (PNG or SVG data).
  final Uint8List bytes;

  /// The format of the export.
  final ExportFormat format;

  /// The logical size of the exported content.
  final ui.Size logicalSize;

  /// The pixel size (logicalSize × pixelRatio).
  final ui.Size pixelSize;

  /// File extension for the export format.
  String get extension {
    switch (format) {
      case ExportFormat.png:
        return 'png';
      case ExportFormat.jpeg:
        return 'jpg';
      case ExportFormat.webp:
        return 'webp';
      case ExportFormat.svg:
        return 'svg';
      case ExportFormat.pdf:
        return 'pdf';
    }
  }

  /// MIME type for the export format.
  String get mimeType {
    switch (format) {
      case ExportFormat.png:
        return 'image/png';
      case ExportFormat.jpeg:
        return 'image/jpeg';
      case ExportFormat.webp:
        return 'image/webp';
      case ExportFormat.svg:
        return 'image/svg+xml';
      case ExportFormat.pdf:
        return 'application/pdf';
    }
  }

  const ExportResult({
    required this.bytes,
    required this.format,
    required this.logicalSize,
    required this.pixelSize,
  });
}

/// Export pipeline for the scene graph.
///
/// Renders the scene graph to various output formats (PNG, SVG)
/// using the [SceneGraphRenderer].
///
/// ```dart
/// final pipeline = ExportPipeline(renderer);
/// final result = await pipeline.exportSceneGraph(
///   sceneGraph,
///   config: ExportConfig.png2x(),
/// );
/// // result.bytes contains the PNG data
/// ```
class ExportPipeline {
  final SceneGraphRenderer _renderer;
  final RasterImageEncoder _rasterEncoder;

  ExportPipeline(this._renderer, {RasterImageEncoder? rasterEncoder})
    : _rasterEncoder = rasterEncoder ?? RasterImageEncoder();

  /// Export the entire scene graph.
  Future<ExportResult> exportSceneGraph(
    SceneGraph sceneGraph, {
    ExportConfig config = const ExportConfig(),
  }) async {
    // Calculate export bounds.
    final bounds = config.region ?? _calculateContentBounds(sceneGraph);
    if (bounds.isEmpty) {
      return ExportResult(
        bytes: Uint8List(0),
        format: config.format,
        logicalSize: ui.Size.zero,
        pixelSize: ui.Size.zero,
      );
    }

    final expandedBounds = bounds.inflate(config.padding);

    switch (config.format) {
      case ExportFormat.png:
        return _exportPng(sceneGraph, expandedBounds, config);
      case ExportFormat.jpeg:
        return _exportRasterFormat(
          sceneGraph,
          expandedBounds,
          config,
          ExportFormat.jpeg,
        );
      case ExportFormat.webp:
        return _exportRasterFormat(
          sceneGraph,
          expandedBounds,
          config,
          ExportFormat.webp,
        );
      case ExportFormat.svg:
        return _exportSvg(sceneGraph, expandedBounds, config);
      case ExportFormat.pdf:
        return _exportPdf(sceneGraph, expandedBounds, config);
    }
  }

  /// Export a specific node and its subtree.
  Future<ExportResult> exportNode(
    CanvasNode node, {
    ExportConfig config = const ExportConfig(),
  }) async {
    final bounds = config.region ?? node.worldBounds;
    final expandedBounds = bounds.inflate(config.padding);
    switch (config.format) {
      case ExportFormat.png:
        return _exportNodePng(node, expandedBounds, config);
      case ExportFormat.jpeg:
      case ExportFormat.webp:
        return _exportNodeRaster(node, expandedBounds, config);
      case ExportFormat.svg:
        return _exportNodeSvg(node, expandedBounds, config);
      case ExportFormat.pdf:
        return _exportNodePdf(node, expandedBounds, config);
    }
  }

  /// Export selected nodes only.
  Future<ExportResult> exportNodes(
    List<CanvasNode> nodes, {
    ExportConfig config = const ExportConfig(),
  }) async {
    if (nodes.isEmpty) {
      return ExportResult(
        bytes: Uint8List(0),
        format: config.format,
        logicalSize: ui.Size.zero,
        pixelSize: ui.Size.zero,
      );
    }

    // Calculate union bounds of all nodes.
    ui.Rect? unionBounds;
    for (final node in nodes) {
      final b = node.worldBounds;
      if (b.isFinite && !b.isEmpty) {
        unionBounds = unionBounds == null ? b : unionBounds.expandToInclude(b);
      }
    }

    final bounds = config.region ?? unionBounds ?? ui.Rect.zero;
    final expandedBounds = bounds.inflate(config.padding);

    switch (config.format) {
      case ExportFormat.png:
        return _exportMultiNodePng(nodes, expandedBounds, config);
      case ExportFormat.jpeg:
      case ExportFormat.webp:
        return _exportMultiNodeRaster(nodes, expandedBounds, config);
      case ExportFormat.svg:
        return _exportNodeSvg(nodes.first, expandedBounds, config);
      case ExportFormat.pdf:
        return _exportPdf(null, expandedBounds, config, nodes: nodes);
    }
  }

  // ---------------------------------------------------------------------------
  // PNG export
  // ---------------------------------------------------------------------------

  Future<ExportResult> _exportPng(
    SceneGraph sceneGraph,
    ui.Rect bounds,
    ExportConfig config,
  ) async {
    final pixelWidth = (bounds.width * config.pixelRatio).ceil();
    final pixelHeight = (bounds.height * config.pixelRatio).ceil();

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, pixelWidth.toDouble(), pixelHeight.toDouble()),
    );

    // Scale for pixel ratio.
    canvas.scale(config.pixelRatio);

    // Translate so content starts at origin.
    canvas.translate(-bounds.left, -bounds.top);

    // Draw background.
    if (config.backgroundColor != null) {
      canvas.drawRect(bounds, ui.Paint()..color = config.backgroundColor!);
    }

    // Render the scene graph.
    _renderer.render(canvas, sceneGraph, bounds);

    final picture = recorder.endRecording();
    final image = await picture.toImage(pixelWidth, pixelHeight);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    picture.dispose();
    image.dispose();

    return ExportResult(
      bytes: byteData?.buffer.asUint8List() ?? Uint8List(0),
      format: ExportFormat.png,
      logicalSize: ui.Size(bounds.width, bounds.height),
      pixelSize: ui.Size(pixelWidth.toDouble(), pixelHeight.toDouble()),
    );
  }

  Future<ExportResult> _exportNodePng(
    CanvasNode node,
    ui.Rect bounds,
    ExportConfig config,
  ) async {
    final pixelWidth = (bounds.width * config.pixelRatio).ceil();
    final pixelHeight = (bounds.height * config.pixelRatio).ceil();

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, pixelWidth.toDouble(), pixelHeight.toDouble()),
    );

    canvas.scale(config.pixelRatio);
    canvas.translate(-bounds.left, -bounds.top);

    if (config.backgroundColor != null) {
      canvas.drawRect(bounds, ui.Paint()..color = config.backgroundColor!);
    }

    _renderer.renderNode(canvas, node, bounds);

    final picture = recorder.endRecording();
    final image = await picture.toImage(pixelWidth, pixelHeight);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    picture.dispose();
    image.dispose();

    return ExportResult(
      bytes: byteData?.buffer.asUint8List() ?? Uint8List(0),
      format: ExportFormat.png,
      logicalSize: ui.Size(bounds.width, bounds.height),
      pixelSize: ui.Size(pixelWidth.toDouble(), pixelHeight.toDouble()),
    );
  }

  Future<ExportResult> _exportMultiNodePng(
    List<CanvasNode> nodes,
    ui.Rect bounds,
    ExportConfig config,
  ) async {
    final pixelWidth = (bounds.width * config.pixelRatio).ceil();
    final pixelHeight = (bounds.height * config.pixelRatio).ceil();

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, pixelWidth.toDouble(), pixelHeight.toDouble()),
    );

    canvas.scale(config.pixelRatio);
    canvas.translate(-bounds.left, -bounds.top);

    if (config.backgroundColor != null) {
      canvas.drawRect(bounds, ui.Paint()..color = config.backgroundColor!);
    }

    for (final node in nodes) {
      _renderer.renderNode(canvas, node, bounds);
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(pixelWidth, pixelHeight);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    picture.dispose();
    image.dispose();

    return ExportResult(
      bytes: byteData?.buffer.asUint8List() ?? Uint8List(0),
      format: ExportFormat.png,
      logicalSize: ui.Size(bounds.width, bounds.height),
      pixelSize: ui.Size(pixelWidth.toDouble(), pixelHeight.toDouble()),
    );
  }

  // ---------------------------------------------------------------------------
  // SVG export
  // ---------------------------------------------------------------------------

  Future<ExportResult> _exportSvg(
    SceneGraph sceneGraph,
    ui.Rect bounds,
    ExportConfig config,
  ) async {
    final svg = StringBuffer();
    svg.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    svg.writeln(
      '<svg xmlns="http://www.w3.org/2000/svg" '
      'viewBox="${bounds.left} ${bounds.top} ${bounds.width} ${bounds.height}" '
      'width="${bounds.width}" height="${bounds.height}">',
    );

    if (config.backgroundColor != null) {
      svg.writeln(
        '  <rect x="${bounds.left}" y="${bounds.top}" '
        'width="${bounds.width}" height="${bounds.height}" '
        'fill="${_colorToSvg(config.backgroundColor!)}" />',
      );
    }

    for (final layer in sceneGraph.layers) {
      if (!layer.isVisible && !config.includeHidden) continue;
      _nodeToSvg(svg, layer, '  ');
    }

    svg.writeln('</svg>');

    final bytes = Uint8List.fromList(svg.toString().codeUnits);
    return ExportResult(
      bytes: bytes,
      format: ExportFormat.svg,
      logicalSize: ui.Size(bounds.width, bounds.height),
      pixelSize: ui.Size(bounds.width, bounds.height),
    );
  }

  Future<ExportResult> _exportNodeSvg(
    CanvasNode node,
    ui.Rect bounds,
    ExportConfig config,
  ) async {
    final svg = StringBuffer();
    svg.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    svg.writeln(
      '<svg xmlns="http://www.w3.org/2000/svg" '
      'viewBox="${bounds.left} ${bounds.top} ${bounds.width} ${bounds.height}" '
      'width="${bounds.width}" height="${bounds.height}">',
    );

    _nodeToSvg(svg, node, '  ');

    svg.writeln('</svg>');

    final bytes = Uint8List.fromList(svg.toString().codeUnits);
    return ExportResult(
      bytes: bytes,
      format: ExportFormat.svg,
      logicalSize: ui.Size(bounds.width, bounds.height),
      pixelSize: ui.Size(bounds.width, bounds.height),
    );
  }

  /// Convert a scene graph node to SVG elements (recursive).
  void _nodeToSvg(StringBuffer svg, CanvasNode node, String indent) {
    if (!node.isVisible) return;

    final transform = node.localTransform;
    final hasTransform = transform != Matrix4.identity();

    // Group wrapper for transform and opacity.
    final attrs = StringBuffer();
    if (hasTransform) {
      final m = transform.storage;
      attrs.write(
        ' transform="matrix(${m[0]},${m[1]},${m[4]},${m[5]},${m[12]},${m[13]})"',
      );
    }
    if (node.opacity < 1.0) {
      attrs.write(' opacity="${node.opacity}"');
    }

    if (node is FrameNode) {
      // Frame as a rect + group.
      svg.writeln('$indent<g${attrs.toString()}>');
      if (node.fillColor != null) {
        final bounds = node.localBounds;
        svg.writeln(
          '$indent  <rect x="${bounds.left}" y="${bounds.top}" '
          'width="${bounds.width}" height="${bounds.height}" '
          'fill="${_colorToSvg(node.fillColor!)}" '
          'rx="${node.borderRadius}" />',
        );
      }
      for (final child in node.children) {
        _nodeToSvg(svg, child, '$indent  ');
      }
      svg.writeln('$indent</g>');
    } else if (node is GroupNode) {
      svg.writeln('$indent<g${attrs.toString()}>');
      for (final child in node.children) {
        _nodeToSvg(svg, child, '$indent  ');
      }
      svg.writeln('$indent</g>');
    } else if (node is PathNode) {
      // Vector path → SVG <path>.
      final d = node.path.toSvgPathData();
      final fill =
          // ignore: deprecated_member_use_from_same_package
          node.fillColor != null
              // ignore: deprecated_member_use_from_same_package
              ? 'fill="${_colorToSvg(node.fillColor!)}"'
              : 'fill="none"';
      final stroke =
          // ignore: deprecated_member_use_from_same_package
          node.strokeColor != null
              // ignore: deprecated_member_use_from_same_package
              ? 'stroke="${_colorToSvg(node.strokeColor!)}" stroke-width="${node.strokeWidth}"'
              : '';
      svg.writeln(
        '$indent<path d="$d" $fill $stroke'
        '${attrs.toString()} />',
      );
    } else if (node is ShapeNode) {
      // Shape → SVG rect (basic rectangle/ellipse placeholder).
      final bounds = node.localBounds;
      final fill = _colorToSvg(ui.Color.fromARGB(255, 200, 200, 200));
      svg.writeln(
        '$indent<rect x="${bounds.left}" y="${bounds.top}" '
        'width="${bounds.width}" height="${bounds.height}" '
        'fill="$fill" stroke="#999" stroke-width="${node.shape.strokeWidth}"'
        '${attrs.toString()} />',
      );
    } else if (node is RichTextNode) {
      // Rich text → SVG <text> with <tspan>s.
      final bounds = node.localBounds;
      svg.writeln(
        '$indent<text x="${bounds.left}" y="${bounds.top + 14}"${attrs.toString()}>',
      );
      for (final span in node.spans) {
        final color = _colorToSvg(span.color);
        final bold =
            span.fontWeight == FontWeight.bold ? ' font-weight="bold"' : '';
        final italic =
            span.fontStyle == FontStyle.italic ? ' font-style="italic"' : '';
        svg.writeln(
          '$indent  <tspan fill="$color" font-size="${span.fontSize}"'
          ' font-family="${span.fontFamily}"$bold$italic>${_escapeXml(span.text)}</tspan>',
        );
      }
      svg.writeln('$indent</text>');
    } else if (node is TextNode) {
      // Simple text → SVG <text>.
      final bounds = node.localBounds;
      svg.writeln(
        '$indent<text x="${bounds.left}" y="${bounds.top + 14}"'
        '${attrs.toString()}>${_escapeXml(node.textElement.text)}</text>',
      );
    } else {
      // Fallback: export as a rect placeholder with bounds.
      final bounds = node.localBounds;
      svg.writeln(
        '$indent<rect x="${bounds.left}" y="${bounds.top}" '
        'width="${bounds.width}" height="${bounds.height}" '
        'fill="#cccccc" stroke="#999999" stroke-width="0.5"'
        '${attrs.toString()} />',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // JPEG / WebP raster export
  // ---------------------------------------------------------------------------

  /// Export scene graph as JPEG or WebP.
  Future<ExportResult> _exportRasterFormat(
    SceneGraph sceneGraph,
    ui.Rect bounds,
    ExportConfig config,
    ExportFormat format,
  ) async {
    // First render to a raster image (same as PNG).
    final pixelWidth = (bounds.width * config.pixelRatio).ceil();
    final pixelHeight = (bounds.height * config.pixelRatio).ceil();

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, pixelWidth.toDouble(), pixelHeight.toDouble()),
    );

    canvas.scale(config.pixelRatio);
    canvas.translate(-bounds.left, -bounds.top);

    // For JPEG, always draw a white background (no transparency).
    final bgColor =
        config.backgroundColor ??
        (format == ExportFormat.jpeg ? const ui.Color(0xFFFFFFFF) : null);
    if (bgColor != null) {
      canvas.drawRect(bounds, ui.Paint()..color = bgColor);
    }

    _renderer.render(canvas, sceneGraph, bounds);

    final picture = recorder.endRecording();
    final image = await picture.toImage(pixelWidth, pixelHeight);

    Uint8List? encoded;
    if (format == ExportFormat.jpeg) {
      encoded = await _rasterEncoder.encodeImageToJpeg(
        image,
        quality: config.quality,
      );
    } else {
      encoded = await _rasterEncoder.encodeImageToWebp(
        image,
        quality: config.quality,
      );
    }

    picture.dispose();
    image.dispose();

    // If native encoding failed, fall back to PNG.
    if (encoded == null) {
      return _exportPng(sceneGraph, bounds, config);
    }

    return ExportResult(
      bytes: encoded,
      format: format,
      logicalSize: ui.Size(bounds.width, bounds.height),
      pixelSize: ui.Size(pixelWidth.toDouble(), pixelHeight.toDouble()),
    );
  }

  /// Export a single node as JPEG or WebP.
  Future<ExportResult> _exportNodeRaster(
    CanvasNode node,
    ui.Rect bounds,
    ExportConfig config,
  ) async {
    final pixelWidth = (bounds.width * config.pixelRatio).ceil();
    final pixelHeight = (bounds.height * config.pixelRatio).ceil();

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, pixelWidth.toDouble(), pixelHeight.toDouble()),
    );

    canvas.scale(config.pixelRatio);
    canvas.translate(-bounds.left, -bounds.top);

    final bgColor =
        config.backgroundColor ??
        (config.format == ExportFormat.jpeg
            ? const ui.Color(0xFFFFFFFF)
            : null);
    if (bgColor != null) {
      canvas.drawRect(bounds, ui.Paint()..color = bgColor);
    }

    _renderer.renderNode(canvas, node, bounds);

    final picture = recorder.endRecording();
    final image = await picture.toImage(pixelWidth, pixelHeight);

    Uint8List? encoded;
    if (config.format == ExportFormat.jpeg) {
      encoded = await _rasterEncoder.encodeImageToJpeg(
        image,
        quality: config.quality,
      );
    } else {
      encoded = await _rasterEncoder.encodeImageToWebp(
        image,
        quality: config.quality,
      );
    }

    picture.dispose();
    image.dispose();

    if (encoded == null) {
      return _exportNodePng(node, bounds, config);
    }

    return ExportResult(
      bytes: encoded,
      format: config.format,
      logicalSize: ui.Size(bounds.width, bounds.height),
      pixelSize: ui.Size(pixelWidth.toDouble(), pixelHeight.toDouble()),
    );
  }

  /// Export multiple nodes as JPEG or WebP.
  Future<ExportResult> _exportMultiNodeRaster(
    List<CanvasNode> nodes,
    ui.Rect bounds,
    ExportConfig config,
  ) async {
    final pixelWidth = (bounds.width * config.pixelRatio).ceil();
    final pixelHeight = (bounds.height * config.pixelRatio).ceil();

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, pixelWidth.toDouble(), pixelHeight.toDouble()),
    );

    canvas.scale(config.pixelRatio);
    canvas.translate(-bounds.left, -bounds.top);

    final bgColor =
        config.backgroundColor ??
        (config.format == ExportFormat.jpeg
            ? const ui.Color(0xFFFFFFFF)
            : null);
    if (bgColor != null) {
      canvas.drawRect(bounds, ui.Paint()..color = bgColor);
    }

    for (final node in nodes) {
      _renderer.renderNode(canvas, node, bounds);
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(pixelWidth, pixelHeight);

    Uint8List? encoded;
    if (config.format == ExportFormat.jpeg) {
      encoded = await _rasterEncoder.encodeImageToJpeg(
        image,
        quality: config.quality,
      );
    } else {
      encoded = await _rasterEncoder.encodeImageToWebp(
        image,
        quality: config.quality,
      );
    }

    picture.dispose();
    image.dispose();

    if (encoded == null) {
      return _exportMultiNodePng(nodes, bounds, config);
    }

    return ExportResult(
      bytes: encoded,
      format: config.format,
      logicalSize: ui.Size(bounds.width, bounds.height),
      pixelSize: ui.Size(pixelWidth.toDouble(), pixelHeight.toDouble()),
    );
  }

  // ---------------------------------------------------------------------------
  // PDF vector export
  // ---------------------------------------------------------------------------

  /// Export scene graph or specific nodes as a vector PDF.
  Future<ExportResult> _exportPdf(
    SceneGraph? sceneGraph,
    ui.Rect bounds,
    ExportConfig config, {
    List<CanvasNode>? nodes,
  }) async {
    final writer = PdfExportWriter(enableCompression: config.enableCompression);

    // Apply PDF-specific configuration.
    writer.pdfAConformance = config.pdfAConformance;
    if (config.pdfWatermark != null && config.pdfWatermark!.isNotEmpty) {
      writer.setWatermark(
        PdfWatermark(
          text: config.pdfWatermark!,
          position: WatermarkPosition.diagonal,
          opacity: 0.15,
        ),
      );
    }

    if (sceneGraph != null) {
      writer.exportSceneGraph(sceneGraph, bounds);
    } else if (nodes != null && nodes.isNotEmpty) {
      writer.beginPage(width: bounds.width, height: bounds.height);
      for (final node in nodes) {
        writer.exportNode(node, bounds);
      }
    } else {
      writer.beginPage(width: bounds.width, height: bounds.height);
    }

    final bytes = writer.finish(title: 'Nebula Engine Export');

    return ExportResult(
      bytes: bytes,
      format: ExportFormat.pdf,
      logicalSize: ui.Size(bounds.width, bounds.height),
      pixelSize: ui.Size(bounds.width, bounds.height),
    );
  }

  /// Export a single node as PDF.
  Future<ExportResult> _exportNodePdf(
    CanvasNode node,
    ui.Rect bounds,
    ExportConfig config,
  ) async {
    final writer = PdfExportWriter(enableCompression: config.enableCompression);

    // Apply PDF-specific configuration.
    writer.pdfAConformance = config.pdfAConformance;
    if (config.pdfWatermark != null && config.pdfWatermark!.isNotEmpty) {
      writer.setWatermark(
        PdfWatermark(
          text: config.pdfWatermark!,
          position: WatermarkPosition.diagonal,
          opacity: 0.15,
        ),
      );
    }

    writer.exportNode(node, bounds);
    final bytes = writer.finish(title: 'Nebula Engine Export');

    return ExportResult(
      bytes: bytes,
      format: ExportFormat.pdf,
      logicalSize: ui.Size(bounds.width, bounds.height),
      pixelSize: ui.Size(bounds.width, bounds.height),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Calculate the bounding box of all visible content.
  ui.Rect _calculateContentBounds(SceneGraph sceneGraph) {
    ui.Rect? bounds;
    for (final node in sceneGraph.allNodes) {
      if (!node.isVisible) continue;
      if (node is GroupNode) continue; // Groups derive bounds from children.
      final b = node.worldBounds;
      if (b.isFinite && !b.isEmpty) {
        bounds = bounds == null ? b : bounds.expandToInclude(b);
      }
    }
    return bounds ?? ui.Rect.zero;
  }

  /// Convert a Color to SVG hex string.
  String _colorToSvg(ui.Color color) {
    final r = (color.r * 255.0)
        .round()
        .clamp(0, 255)
        .toRadixString(16)
        .padLeft(2, '0');
    final g = (color.g * 255.0)
        .round()
        .clamp(0, 255)
        .toRadixString(16)
        .padLeft(2, '0');
    final b = (color.b * 255.0)
        .round()
        .clamp(0, 255)
        .toRadixString(16)
        .padLeft(2, '0');
    return '#$r$g$b';
  }

  /// Escape special XML characters for safe SVG embedding.
  String _escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
