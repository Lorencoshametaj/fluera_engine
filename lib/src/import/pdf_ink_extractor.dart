import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import '../drawing/models/pro_drawing_point.dart';
import '../drawing/models/pro_brush_settings.dart';
import '../utils/uid.dart';

/// Extracts ink annotations from PDF files and converts them to [ProStroke].
///
/// Parses the raw PDF byte stream looking for `/Subtype /Ink` annotation
/// objects and extracts their `InkList` coordinate arrays. This is a
/// best-effort parser — not a full PDF library — designed to handle the
/// common structures produced by OneNote and similar apps.
///
/// PDF ink annotations store strokes as arrays of coordinate pairs in
/// PDF user space (origin at bottom-left, 72 DPI). This extractor
/// converts them to canvas coordinates (origin at top-left).
class PdfInkExtractor {
  const PdfInkExtractor._();

  /// Attempt to extract ink annotation strokes from raw PDF bytes.
  ///
  /// Returns an empty list if no ink annotations are found or the PDF
  /// structure cannot be parsed. Never throws.
  ///
  /// [pageHeight] is needed to flip Y coordinates (PDF origin is bottom-left).
  /// If null, defaults to 842 (A4 height at 72 DPI).
  static List<ProStroke> extract(
    Uint8List pdfBytes, {
    double? pageHeight,
    Offset offset = Offset.zero,
    double scale = 1.0,
  }) {
    try {
      return _extractInkAnnotations(pdfBytes, pageHeight, offset, scale);
    } catch (_) {
      return const [];
    }
  }

  static List<ProStroke> _extractInkAnnotations(
    Uint8List bytes,
    double? pageHeight,
    Offset offset,
    double scale,
  ) {
    final content = latin1.decode(bytes);
    final ph = pageHeight ?? 842.0; // A4 default
    final strokes = <ProStroke>[];
    final now = DateTime.now();

    // Find all Ink annotation objects:
    // /Type /Annot /Subtype /Ink
    final inkPattern = RegExp(
      r'/Subtype\s*/Ink',
      multiLine: true,
    );

    for (final match in inkPattern.allMatches(content)) {
      // Find the enclosing object (search backward for "obj" marker)
      final objStart = _findObjStart(content, match.start);
      if (objStart < 0) continue;

      // Find end of object
      final objEnd = content.indexOf('endobj', match.start);
      if (objEnd < 0) continue;

      final objContent = content.substring(objStart, objEnd);

      // Extract InkList: array of arrays of numbers
      // Format: /InkList [[x1 y1 x2 y2 ...] [x1 y1 x2 y2 ...]]
      final inkListMatch = RegExp(
        r'/InkList\s*\[([^\]]*(?:\[[^\]]*\])*[^\]]*)\]',
      ).firstMatch(objContent);
      if (inkListMatch == null) continue;

      final inkListStr = inkListMatch.group(1)!;

      // Extract color: /C [r g b] (values 0-1)
      Color inkColor = const Color(0xFF000000);
      final colorMatch = RegExp(r'/C\s*\[([^\]]+)\]').firstMatch(objContent);
      if (colorMatch != null) {
        final parts = colorMatch.group(1)!.trim().split(RegExp(r'\s+'));
        if (parts.length >= 3) {
          final r = (double.tryParse(parts[0]) ?? 0) * 255;
          final g = (double.tryParse(parts[1]) ?? 0) * 255;
          final b = (double.tryParse(parts[2]) ?? 0) * 255;
          inkColor = Color.fromARGB(255, r.round(), g.round(), b.round());
        }
      }

      // Extract border width: /BS << /W N >>
      double borderWidth = 2.0;
      final bsMatch = RegExp(r'/BS\s*<<[^>]*/W\s+([\d.]+)').firstMatch(
        objContent,
      );
      if (bsMatch != null) {
        borderWidth = double.tryParse(bsMatch.group(1)!) ?? 2.0;
      }

      // Parse each sub-array in InkList
      final subArrayPattern = RegExp(r'\[([^\]]+)\]');
      for (final subMatch in subArrayPattern.allMatches(inkListStr)) {
        final coordStr = subMatch.group(1)!.trim();
        final numbers =
            coordStr
                .split(RegExp(r'\s+'))
                .map((s) => double.tryParse(s))
                .where((v) => v != null)
                .cast<double>()
                .toList();

        if (numbers.length < 4) continue; // Need at least 2 points

        final points = <ProDrawingPoint>[];
        final baseTimestamp = now.millisecondsSinceEpoch;

        for (int i = 0; i < numbers.length - 1; i += 2) {
          final x = numbers[i] * scale + offset.dx;
          // Flip Y: PDF origin is bottom-left
          final y = (ph - numbers[i + 1]) * scale + offset.dy;
          points.add(ProDrawingPoint(
            position: Offset(x, y),
            pressure: 0.5, // Unknown from PDF
            timestamp: baseTimestamp + (i ~/ 2),
          ));
        }

        if (points.length >= 2) {
          strokes.add(ProStroke(
            id: generateUid(),
            points: points,
            color: inkColor,
            baseWidth: borderWidth * scale,
            penType: ProPenType.ballpoint,
            createdAt: now,
            settings: const ProBrushSettings(),
          ));
        }
      }
    }

    return strokes;
  }

  /// Search backward from [pos] to find the start of the PDF object.
  static int _findObjStart(String content, int pos) {
    // Look for "N N obj" pattern before this position
    final searchStart = (pos - 200).clamp(0, pos);
    final region = content.substring(searchStart, pos);
    final objMatch = RegExp(r'\d+\s+\d+\s+obj').allMatches(region).lastOrNull;
    return objMatch != null ? searchStart + objMatch.start : -1;
  }
}
