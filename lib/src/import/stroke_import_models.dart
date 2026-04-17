import 'dart:ui';

import '../drawing/models/pro_drawing_point.dart';

/// Source type for imported notes.
enum ImportSourceType {
  /// PDF with extractable ink annotations (vector data).
  pdfInk,

  /// SVG file with path elements.
  svgPath,

  /// Rasterized image (PNG, JPEG, PDF page rendered to bitmap).
  rasterized,
}

/// Result of a note import operation.
class NoteImportResult {
  /// Converted strokes ready to be added to the scene graph.
  final List<ProStroke> strokes;

  /// How the strokes were obtained.
  final ImportSourceType sourceType;

  /// Number of pages/images processed.
  final int pagesProcessed;

  const NoteImportResult({
    required this.strokes,
    required this.sourceType,
    this.pagesProcessed = 1,
  });
}

/// Progress callback during import.
typedef ImportProgressCallback = void Function(ImportProgress progress);

/// Import progress state.
class ImportProgress {
  /// Current page being processed (1-based).
  final int currentPage;

  /// Total pages to process.
  final int totalPages;

  /// Current phase description (e.g. 'Binarizing...', 'Tracing strokes...').
  final String phase;

  /// 0.0 to 1.0 overall progress.
  double get fraction =>
      totalPages > 0 ? (currentPage - 1 + 0.5) / totalPages : 0.0;

  const ImportProgress({
    required this.currentPage,
    required this.totalPages,
    required this.phase,
  });
}

/// A raw polyline extracted from vectorization, before conversion to ProStroke.
class ExtractedPolyline {
  /// Points along the stroke centerline.
  final List<Offset> points;

  /// Estimated half-width at each point (from distance transform).
  /// Same length as [points], or empty if width is uniform.
  final List<double> widths;

  /// Dominant ink color detected for this stroke.
  final Color color;

  const ExtractedPolyline({
    required this.points,
    this.widths = const [],
    this.color = const Color(0xFF000000),
  });
}
