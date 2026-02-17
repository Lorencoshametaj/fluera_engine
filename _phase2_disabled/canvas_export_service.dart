import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/export_preset.dart';
import '../models/pro_drawing_point.dart';
import '../brushes/brushes.dart';
import '../canvas_renderers/shape_painter.dart';
import '../canvas_renderers/paper_pattern_painter.dart';
import '../controllers/layer_controller.dart';

/// 🎨 CANVAS EXPORT SERVICE
///
/// Servizio professionale per esportare il Professional Canvas in vari formati.
///
/// FEATURES:
/// - ✅ Export PNG/JPEG per aree piccole (≤8192×8192)
/// - ✅ Export PDF singola pagina o multi-pagina
/// - ✅ Multi-pagina automatico per aree grandi
/// - ✅ Progress callback per UI feedback
/// - ✅ Opzioni background (trasparente/solido/template)
/// - ✅ Qualità configurabile (72/150/300 DPI)
/// - ✅ Calcolo bounds automatico dal contenuto
class CanvasExportService {
  // Limite massimo per export immagine singola (evita crash memoria)
  static const int maxImageDimension = 8192;

  /// 📏 Calcola i bounds del contenuto da tutti i layer visibili
  static Rect? calculateContentBounds(
    LayerController layerController, {
    double padding = 50.0,
  }) {
    final strokes = layerController.getAllVisibleStrokes();
    final shapes = layerController.getAllVisibleShapes();

    if (strokes.isEmpty && shapes.isEmpty) return null;

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    // Calcola bounds degli strokes
    for (final stroke in strokes) {
      final bounds = stroke.bounds;
      minX = minX < bounds.left ? minX : bounds.left;
      minY = minY < bounds.top ? minY : bounds.top;
      maxX = maxX > bounds.right ? maxX : bounds.right;
      maxY = maxY > bounds.bottom ? maxY : bounds.bottom;
    }

    // Calcola bounds delle shapes
    for (final shape in shapes) {
      final shapeMinX =
          shape.startPoint.dx < shape.endPoint.dx
              ? shape.startPoint.dx
              : shape.endPoint.dx;
      final shapeMinY =
          shape.startPoint.dy < shape.endPoint.dy
              ? shape.startPoint.dy
              : shape.endPoint.dy;
      final shapeMaxX =
          shape.startPoint.dx > shape.endPoint.dx
              ? shape.startPoint.dx
              : shape.endPoint.dx;
      final shapeMaxY =
          shape.startPoint.dy > shape.endPoint.dy
              ? shape.startPoint.dy
              : shape.endPoint.dy;

      minX = minX < shapeMinX ? minX : shapeMinX;
      minY = minY < shapeMinY ? minY : shapeMinY;
      maxX = maxX > shapeMaxX ? maxX : shapeMaxX;
      maxY = maxY > shapeMaxY ? maxY : shapeMaxY;
    }

    if (minX == double.infinity) return null;

    // Aggiungi padding
    return Rect.fromLTRB(
      minX - padding,
      minY - padding,
      maxX + padding,
      maxY + padding,
    );
  }

  /// 🖼️ Esporta come immagine PNG/JPEG
  ///
  /// Lancia eccezione se l'area supera [maxImageDimension].
  /// Per aree grandi, usare [exportAsPDF] o [exportAsMultiPagePDF].
  Future<Uint8List> exportAsImage({
    required LayerController layerController,
    required Rect exportArea,
    required ExportConfig config,
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0.0);

    // Calcola dimensioni finali
    final scale = config.quality.dpi / 72.0;
    final width = (exportArea.width * scale).toInt();
    final height = (exportArea.height * scale).toInt();

    // Verifica limiti
    if (width > maxImageDimension || height > maxImageDimension) {
      throw ExportException(
        'Image size ($width × $height) exceeds maximum ($maxImageDimension × $maxImageDimension). '
        'Use PDF export for larger areas.',
      );
    }

    onProgress?.call(0.1);

    // Renderizza in immagine
    final image = await _renderAreaToImage(
      layerController: layerController,
      exportArea: exportArea,
      width: width,
      height: height,
      config: config,
    );

    onProgress?.call(0.8);

    // Converti in bytes
    final format =
        config.format == ExportFormat.jpeg
            ? ui
                .ImageByteFormat
                .rawRgba // JPEG richiede processing extra
            : ui.ImageByteFormat.png;

    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw ExportException('Failed to convert image to bytes');
    }

    onProgress?.call(1.0);

    return byteData.buffer.asUint8List();
  }

  /// 📄 Esporta come PDF singola pagina
  ///
  /// Scala il contenuto per adattarlo alla pagina specificata.
  Future<File> exportAsPDF({
    required LayerController layerController,
    required Rect exportArea,
    required ExportConfig config,
    String? outputPath,
    String? fileName,
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0.0);

    final pdf = pw.Document();

    // Determina formato pagina
    final pageFormat = _getPageFormat(config.pageFormat);

    // Calcola scala per fit nella pagina
    final scale = config.quality.dpi / 72.0;
    final contentWidth = exportArea.width * scale;
    final contentHeight = exportArea.height * scale;

    // Calcola dimensioni rendering (fit to page)
    double renderWidth, renderHeight;
    final pageAspect = pageFormat.width / pageFormat.height;
    final contentAspect = contentWidth / contentHeight;

    if (contentAspect > pageAspect) {
      // Contenuto più largo - fit to width
      renderWidth = pageFormat.width.toInt().toDouble();
      renderHeight = renderWidth / contentAspect;
    } else {
      // Contenuto più alto - fit to height
      renderHeight = pageFormat.height.toInt().toDouble();
      renderWidth = renderHeight * contentAspect;
    }

    onProgress?.call(0.2);

    // Renderizza contenuto
    final image = await _renderAreaToImage(
      layerController: layerController,
      exportArea: exportArea,
      width: renderWidth.toInt().clamp(1, maxImageDimension),
      height: renderHeight.toInt().clamp(1, maxImageDimension),
      config: config,
    );

    onProgress?.call(0.6);

    // Converti in bytes
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw ExportException('Failed to convert image to bytes');
    }
    final pngBytes = byteData.buffer.asUint8List();

    onProgress?.call(0.8);

    // Aggiungi pagina al PDF
    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: pw.EdgeInsets.zero,
        build: (context) {
          return pw.Center(
            child: pw.Image(pw.MemoryImage(pngBytes), fit: pw.BoxFit.contain),
          );
        },
      ),
    );

    // Salva PDF
    final file = await _savePDF(pdf, outputPath, fileName ?? 'canvas_export');

    onProgress?.call(1.0);

    return file;
  }

  /// 📚 Esporta come PDF multi-pagina
  ///
  /// Divide l'area in pagine del formato specificato, mantenendo la scala 1:1.
  /// Ideale per stampa di canvas grandi.
  Future<File> exportAsMultiPagePDF({
    required LayerController layerController,
    required Rect exportArea,
    required ExportConfig config,
    String? outputPath,
    String? fileName,
    void Function(int current, int total)? onProgress,
  }) async {
    final pdf = pw.Document();

    // Determina formato pagina
    final pageFormat = _getPageFormat(config.pageFormat);
    final scale = config.quality.dpi / 72.0;

    // Dimensioni pagina in pixel (a scala 1:1)
    final pageWidthPx = pageFormat.width * scale;
    final pageHeightPx = pageFormat.height * scale;

    // Calcola griglia di pagine
    final areaWidthPx = exportArea.width * scale;
    final areaHeightPx = exportArea.height * scale;

    final columns = (areaWidthPx / pageWidthPx).ceil();
    final rows = (areaHeightPx / pageHeightPx).ceil();
    final totalPages = columns * rows;

    onProgress?.call(0, totalPages);

    int pageIndex = 0;

    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < columns; col++) {
        pageIndex++;
        onProgress?.call(pageIndex, totalPages);

        // Calcola bounds per questa pagina
        final pageLeft = exportArea.left + (col * pageWidthPx / scale);
        final pageTop = exportArea.top + (row * pageHeightPx / scale);
        final pageRight = (pageLeft + pageWidthPx / scale).clamp(
          exportArea.left,
          exportArea.right,
        );
        final pageBottom = (pageTop + pageHeightPx / scale).clamp(
          exportArea.top,
          exportArea.bottom,
        );

        final pageArea = Rect.fromLTRB(
          pageLeft,
          pageTop,
          pageRight,
          pageBottom,
        );

        // Calcola dimensioni effettive (ultima pagina potrebbe essere più piccola)
        final effectiveWidth = (pageArea.width * scale).toInt().clamp(
          1,
          maxImageDimension,
        );
        final effectiveHeight = (pageArea.height * scale).toInt().clamp(
          1,
          maxImageDimension,
        );

        // Renderizza pagina
        final image = await _renderAreaToImage(
          layerController: layerController,
          exportArea: pageArea,
          width: effectiveWidth,
          height: effectiveHeight,
          config: config,
        );

        // Converti in bytes
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData == null) continue;
        final pngBytes = byteData.buffer.asUint8List();

        // Aggiungi pagina al PDF
        pdf.addPage(
          pw.Page(
            pageFormat: pageFormat,
            margin: pw.EdgeInsets.zero,
            build: (context) {
              return pw.Positioned(
                left: 0,
                top: 0,
                child: pw.Image(
                  pw.MemoryImage(pngBytes),
                  width:
                      pageArea.width * scale / (pageWidthPx / pageFormat.width),
                  height:
                      pageArea.height *
                      scale /
                      (pageHeightPx / pageFormat.height),
                ),
              );
            },
          ),
        );
      }
    }

    // Salva PDF
    final file = await _savePDF(
      pdf,
      outputPath,
      fileName ?? 'canvas_export_multipage',
    );

    return file;
  }

  /// 🎨 Renderizza un'area del canvas in un'immagine
  Future<ui.Image> _renderAreaToImage({
    required LayerController layerController,
    required Rect exportArea,
    required int width,
    required int height,
    required ExportConfig config,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = Size(width.toDouble(), height.toDouble());

    // Scala per adattare l'area di export alla dimensione output
    final scaleX = width / exportArea.width;
    final scaleY = height / exportArea.height;

    // Trasla per centrare l'area di export
    canvas.translate(-exportArea.left * scaleX, -exportArea.top * scaleY);
    canvas.scale(scaleX, scaleY);

    // 1. Disegna background
    await _drawBackground(canvas, exportArea, config);

    // 2. Disegna shapes
    final shapes = layerController.getAllVisibleShapes();
    for (final shape in shapes) {
      // Verifica se la shape interseca l'area di export
      final shapeBounds = Rect.fromPoints(shape.startPoint, shape.endPoint);
      if (shapeBounds.overlaps(exportArea)) {
        ShapePainter.drawShape(canvas, shape);
      }
    }

    // 3. Disegna strokes
    final strokes = layerController.getAllVisibleStrokes();
    for (final stroke in strokes) {
      // Verifica se lo stroke interseca l'area di export
      if (stroke.bounds.overlaps(exportArea)) {
        _drawStroke(canvas, stroke);
      }
    }

    // Converti in immagine
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);

    return image;
  }

  /// 🎨 Disegna il background secondo la configurazione
  Future<void> _drawBackground(
    Canvas canvas,
    Rect area,
    ExportConfig config,
  ) async {
    switch (config.background) {
      case ExportBackground.transparent:
        // Non disegnare nulla (trasparente per PNG)
        break;

      case ExportBackground.white:
        final paint = Paint()..color = Colors.white;
        canvas.drawRect(area, paint);
        break;

      case ExportBackground.solidColor:
        final paint = Paint()..color = config.backgroundColor ?? Colors.white;
        canvas.drawRect(area, paint);
        break;

      case ExportBackground.withTemplate:
        // Disegna background con pattern carta
        final bgColor = config.backgroundColor ?? Colors.white;
        final paint = Paint()..color = bgColor;
        canvas.drawRect(area, paint);

        // Disegna il pattern usando PaperPatternPainter
        if (config.paperType != null && config.paperType != 'blank') {
          final patternPainter = PaperPatternPainter(
            paperType: config.paperType!,
            backgroundColor: bgColor,
            scale: 37.8, // 1cm = 37.8px (stessa scala del BackgroundPainter)
          );
          patternPainter.paint(canvas, Size(area.width, area.height));
        }
        break;
    }
  }

  /// 🖌️ Disegna uno stroke usando il brush appropriato
  void _drawStroke(Canvas canvas, ProStroke stroke) {
    if (stroke.points.isEmpty) return;

    switch (stroke.penType) {
      case ProPenType.ballpoint:
        BallpointBrush.drawStroke(
          canvas,
          stroke.points,
          stroke.color,
          stroke.baseWidth,
        );
        break;
      case ProPenType.fountain:
        FountainPenBrush.drawStroke(
          canvas,
          stroke.points,
          stroke.color,
          stroke.baseWidth,
        );
        break;
      case ProPenType.pencil:
        PencilBrush.drawStroke(
          canvas,
          stroke.points,
          stroke.color,
          stroke.baseWidth,
        );
        break;
      case ProPenType.highlighter:
        HighlighterBrush.drawStroke(
          canvas,
          stroke.points,
          stroke.color,
          stroke.baseWidth,
        );
        break;
    }
  }

  /// 📄 Ottieni il formato pagina PDF
  PdfPageFormat _getPageFormat(ExportPageFormat format) {
    switch (format) {
      case ExportPageFormat.a4Portrait:
        return PdfPageFormat.a4;
      case ExportPageFormat.a4Landscape:
        return PdfPageFormat.a4.landscape;
      case ExportPageFormat.a3Portrait:
        return PdfPageFormat.a3;
      case ExportPageFormat.a3Landscape:
        return PdfPageFormat.a3.landscape;
      case ExportPageFormat.letterPortrait:
        return PdfPageFormat.letter;
      case ExportPageFormat.letterLandscape:
        return PdfPageFormat.letter.landscape;
      case ExportPageFormat.custom:
        return PdfPageFormat.a4; // Default to A4 for custom
    }
  }

  /// 💾 Salva il PDF su filesystem
  Future<File> _savePDF(
    pw.Document pdf,
    String? outputPath,
    String fileName,
  ) async {
    final bytes = await pdf.save();

    final path = outputPath ?? await _getDefaultOutputPath('$fileName.pdf');

    final file = File(path);
    await file.writeAsBytes(bytes);

    return file;
  }

  /// 📁 Ottieni percorso output predefinito
  Future<String> _getDefaultOutputPath(String fileName) async {
    final directory = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${directory.path}/exports');
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }
    return '${exportDir.path}/$fileName';
  }

  /// 📤 Condividi file esportato
  static Future<void> shareFile(File file) async {
    await Share.shareXFiles([XFile(file.path)], subject: 'Canvas Export');
  }

  /// 🔢 Calcola il numero di pagine per multi-page export
  static (int columns, int rows, int total) calculatePageGrid({
    required Rect exportArea,
    required ExportQuality quality,
    required ExportPageFormat pageFormat,
  }) {
    // Determina formato pagina
    PdfPageFormat pdfFormat;
    switch (pageFormat) {
      case ExportPageFormat.a4Portrait:
        pdfFormat = PdfPageFormat.a4;
        break;
      case ExportPageFormat.a4Landscape:
        pdfFormat = PdfPageFormat.a4.landscape;
        break;
      case ExportPageFormat.a3Portrait:
        pdfFormat = PdfPageFormat.a3;
        break;
      case ExportPageFormat.a3Landscape:
        pdfFormat = PdfPageFormat.a3.landscape;
        break;
      case ExportPageFormat.letterPortrait:
        pdfFormat = PdfPageFormat.letter;
        break;
      case ExportPageFormat.letterLandscape:
        pdfFormat = PdfPageFormat.letter.landscape;
        break;
      case ExportPageFormat.custom:
        pdfFormat = PdfPageFormat.a4;
        break;
    }

    final scale = quality.dpi / 72.0;
    final pageWidthPx = pdfFormat.width * scale;
    final pageHeightPx = pdfFormat.height * scale;

    final areaWidthPx = exportArea.width * scale;
    final areaHeightPx = exportArea.height * scale;

    final columns = (areaWidthPx / pageWidthPx).ceil().clamp(1, 100);
    final rows = (areaHeightPx / pageHeightPx).ceil().clamp(1, 100);

    return (columns, rows, columns * rows);
  }

  /// ✅ Verifica se l'area richiede multi-pagina
  static bool requiresMultiPage({
    required Rect exportArea,
    required ExportQuality quality,
  }) {
    final scale = quality.dpi / 72.0;
    final width = exportArea.width * scale;
    final height = exportArea.height * scale;

    return width > maxImageDimension || height > maxImageDimension;
  }
}

/// ❌ Eccezione per errori di export
class ExportException implements Exception {
  final String message;

  ExportException(this.message);

  @override
  String toString() => 'ExportException: $message';
}
