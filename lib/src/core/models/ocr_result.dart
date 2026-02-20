import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart' show immutable;

import 'pdf_text_rect.dart';

// =============================================================================
// 📄 OCR Result Models — Native OCR output for scanned/image-based PDFs
//
// ENTERPRISE DESIGN PRINCIPLES:
// - Immutable value objects with const constructors
// - Full JSON round-trip for persistent caching across sessions
// - Confidence scores from native APIs for quality filtering
// - Memory estimation for budget controller integration
// - Processing duration metadata for performance monitoring
// - Defensive bounds clamping (0.0–1.0) against broken native data
// - Value equality (== / hashCode) for deduplication and testing
// - Per-page OCR status enum for state tracking
// =============================================================================

/// Clamp a value to the 0.0–1.0 range (guard against native coordinate leaks).
double _clamp01(double v) => v.clamp(0.0, 1.0);

/// Per-page OCR processing status.
///
/// Tracks the lifecycle of OCR on each page to prevent duplicate work
/// and enable UI status reporting.
enum OcrPageStatus {
  /// OCR has not been attempted on this page.
  notAttempted,

  /// OCR is currently running (native API in progress).
  inProgress,

  /// OCR completed successfully with text results.
  completed,

  /// OCR completed but found no recognizable text.
  empty,

  /// OCR failed due to an error (native API failure, timeout, etc).
  failed,

  /// OCR was skipped because the page already has text content.
  skipped,
}

/// A single text block recognized by OCR with its bounding box.
@immutable
class OcrTextBlock {
  /// The recognized text content.
  final String text;

  /// Bounding box in normalized 0.0–1.0 coordinates (origin top-left).
  final Rect rect;

  /// Recognition confidence from the native API (0.0–1.0).
  ///
  /// - iOS Vision: `VNRecognizedTextObservation.confidence`
  /// - Android ML Kit: `TextBlock.lines[].confidence`
  ///
  /// A value of `null` means the native API did not provide a score.
  final double? confidence;

  const OcrTextBlock({required this.text, required this.rect, this.confidence});

  /// Create from native platform map with defensive bounds clamping.
  factory OcrTextBlock.fromMap(Map<String, dynamic> map) {
    final x = _clamp01((map['x'] as num?)?.toDouble() ?? 0.0);
    final y = _clamp01((map['y'] as num?)?.toDouble() ?? 0.0);
    final w = _clamp01((map['width'] as num?)?.toDouble() ?? 0.0);
    final h = _clamp01((map['height'] as num?)?.toDouble() ?? 0.0);
    final conf = (map['confidence'] as num?)?.toDouble();

    return OcrTextBlock(
      text: map['text'] as String? ?? '',
      rect: Rect.fromLTWH(x, y, w, h),
      confidence: conf != null ? _clamp01(conf) : null,
    );
  }

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'text': text,
    'x': rect.left,
    'y': rect.top,
    'width': rect.width,
    'height': rect.height,
    if (confidence != null) 'confidence': confidence,
  };

  factory OcrTextBlock.fromJson(Map<String, dynamic> json) =>
      OcrTextBlock.fromMap(json);

  // ---------------------------------------------------------------------------
  // copyWith
  // ---------------------------------------------------------------------------

  OcrTextBlock copyWith({String? text, Rect? rect, double? confidence}) =>
      OcrTextBlock(
        text: text ?? this.text,
        rect: rect ?? this.rect,
        confidence: confidence ?? this.confidence,
      );

  // ---------------------------------------------------------------------------
  // Memory estimation
  // ---------------------------------------------------------------------------

  /// Estimated memory footprint in bytes.
  ///
  /// Accounts for: object header (16B) + String (header + chars) + Rect (32B)
  /// + confidence double (8B) + alignment padding.
  int get estimatedBytes => 16 + (text.length * 2 + 24) + 32 + 8 + 8;

  // ---------------------------------------------------------------------------
  // Value equality
  // ---------------------------------------------------------------------------

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OcrTextBlock &&
          text == other.text &&
          rect == other.rect &&
          confidence == other.confidence;

  @override
  int get hashCode => Object.hash(text, rect, confidence);

  @override
  String toString() =>
      'OcrTextBlock("$text", $rect${confidence != null ? ', conf=${confidence!.toStringAsFixed(2)}' : ''})';
}

/// Result of OCR on a single PDF page.
@immutable
class OcrPageResult {
  /// Full recognized text (all blocks concatenated with newlines).
  final String text;

  /// Individual recognized text blocks with bounding boxes.
  final List<OcrTextBlock> blocks;

  /// Processing duration from the native OCR API.
  ///
  /// Recorded client-side (Dart) as the time between method channel call
  /// and response. `null` when duration was not measured (e.g. cached result).
  final Duration? processingDuration;

  /// Page index this result belongs to (for cache key correlation).
  final int? pageIndex;

  const OcrPageResult({
    required this.text,
    required this.blocks,
    this.processingDuration,
    this.pageIndex,
  });

  /// Empty sentinel — no OCR text found.
  static const empty = OcrPageResult(text: '', blocks: []);

  /// Whether OCR produced any text.
  bool get isEmpty => text.isEmpty;
  bool get isNotEmpty => text.isNotEmpty;

  // ---------------------------------------------------------------------------
  // Confidence analytics
  // ---------------------------------------------------------------------------

  /// Average confidence across all blocks (null if no scores available).
  double? get averageConfidence {
    final scored = blocks.where((b) => b.confidence != null).toList();
    if (scored.isEmpty) return null;
    return scored.fold<double>(0, (s, b) => s + b.confidence!) / scored.length;
  }

  /// Minimum confidence across all blocks (null if no scores available).
  double? get minConfidence {
    final scored = blocks.where((b) => b.confidence != null).toList();
    if (scored.isEmpty) return null;
    return scored.fold<double>(
      1.0,
      (m, b) => b.confidence! < m ? b.confidence! : m,
    );
  }

  /// Number of blocks above a given confidence threshold.
  int blocksAboveConfidence(double threshold) =>
      blocks
          .where((b) => b.confidence != null && b.confidence! >= threshold)
          .length;

  /// Filter blocks by minimum confidence threshold.
  ///
  /// Returns a new [OcrPageResult] containing only blocks with
  /// `confidence >= threshold`. Useful for discarding noisy OCR output
  /// on low-quality scans.
  OcrPageResult filterByConfidence(double threshold) {
    final filtered =
        blocks
            .where((b) => b.confidence == null || b.confidence! >= threshold)
            .toList();
    return OcrPageResult(
      text: filtered.map((b) => b.text).join('\n'),
      blocks: filtered,
      processingDuration: processingDuration,
      pageIndex: pageIndex,
    );
  }

  // ---------------------------------------------------------------------------
  // Memory estimation
  // ---------------------------------------------------------------------------

  /// Estimated memory footprint in bytes.
  ///
  /// Used by the memory budget controller to track OCR cache pressure.
  int get estimatedBytes {
    // Object header + String + List overhead
    int bytes = 32 + (text.length * 2 + 24) + 24;
    for (final block in blocks) {
      bytes += block.estimatedBytes;
    }
    return bytes;
  }

  // ---------------------------------------------------------------------------
  // Factory constructors
  // ---------------------------------------------------------------------------

  /// Create from native platform response map.
  factory OcrPageResult.fromMap(Map<String, dynamic> map) {
    final blocks = <OcrTextBlock>[];
    final blockList = map['blocks'] as List?;
    if (blockList != null) {
      for (final item in blockList) {
        if (item is Map) {
          final block = OcrTextBlock.fromMap(Map<String, dynamic>.from(item));
          if (block.text.isNotEmpty) blocks.add(block);
        }
      }
    }
    return OcrPageResult(text: map['text'] as String? ?? '', blocks: blocks);
  }

  // ---------------------------------------------------------------------------
  // Serialization (for caching OCR results across sessions)
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'text': text,
    'blocks': blocks.map((b) => b.toJson()).toList(),
    if (processingDuration != null)
      'durationMs': processingDuration!.inMilliseconds,
    if (pageIndex != null) 'pageIndex': pageIndex,
  };

  factory OcrPageResult.fromJson(Map<String, dynamic> json) {
    final blocks = <OcrTextBlock>[];
    final blockList = json['blocks'] as List?;
    if (blockList != null) {
      for (final item in blockList) {
        if (item is Map) {
          blocks.add(OcrTextBlock.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    final durationMs = (json['durationMs'] as num?)?.toInt();
    return OcrPageResult(
      text: json['text'] as String? ?? '',
      blocks: blocks,
      processingDuration:
          durationMs != null ? Duration(milliseconds: durationMs) : null,
      pageIndex: (json['pageIndex'] as num?)?.toInt(),
    );
  }

  // ---------------------------------------------------------------------------
  // Convert to PdfTextRect for search highlighting
  // ---------------------------------------------------------------------------

  /// Convert OCR blocks to [PdfTextRect]s for highlight rendering.
  ///
  /// Each block becomes a single PdfTextRect. Character offsets are computed
  /// by tracking cumulative position through concatenated block text.
  List<PdfTextRect> toTextRects() {
    if (blocks.isEmpty) return const [];

    final rects = <PdfTextRect>[];
    int charOffset = 0;

    for (final block in blocks) {
      if (block.text.isEmpty) continue;

      rects.add(
        PdfTextRect(rect: block.rect, text: block.text, charOffset: charOffset),
      );

      // +1 for the newline separator between blocks in full text
      charOffset += block.text.length + 1;
    }

    return rects;
  }

  // ---------------------------------------------------------------------------
  // copyWith
  // ---------------------------------------------------------------------------

  OcrPageResult copyWith({
    String? text,
    List<OcrTextBlock>? blocks,
    Duration? processingDuration,
    int? pageIndex,
  }) => OcrPageResult(
    text: text ?? this.text,
    blocks: blocks ?? this.blocks,
    processingDuration: processingDuration ?? this.processingDuration,
    pageIndex: pageIndex ?? this.pageIndex,
  );

  // ---------------------------------------------------------------------------
  // Value equality
  // ---------------------------------------------------------------------------

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OcrPageResult &&
          text == other.text &&
          _blocksEqual(blocks, other.blocks);

  static bool _blocksEqual(List<OcrTextBlock> a, List<OcrTextBlock> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(text, blocks.length);

  @override
  String toString() =>
      'OcrPageResult(${blocks.length} blocks, ${text.length} chars'
      '${averageConfidence != null ? ', avgConf=${averageConfidence!.toStringAsFixed(2)}' : ''}'
      '${processingDuration != null ? ', ${processingDuration!.inMilliseconds}ms' : ''})';
}
