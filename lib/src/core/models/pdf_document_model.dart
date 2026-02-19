import 'dart:ui';

import 'package:flutter/foundation.dart';

import './pdf_page_model.dart';

/// 📄 Pure data model for a PDF document on the canvas.
///
/// Stores document-level metadata: page list, grid layout settings,
/// source hash for change detection, and timestamps for Timeline
/// integration with Looponia's Stroke Memory system.
///
/// DESIGN PRINCIPLES:
/// - Immutable (copyWith pattern) for clean state management
/// - Fully serializable with optional-field fallbacks
/// - Timeline-aware via [createdAt], [lastModifiedAt], [timelineRef]
class PdfDocumentModel {
  /// SHA-256 hash of the original PDF bytes for change detection.
  final String sourceHash;

  /// Total number of pages in the document.
  final int totalPages;

  /// Per-page metadata.
  final List<PdfPageModel> pages;

  /// Number of columns in the automatic grid layout.
  final int gridColumns;

  /// Gap between pages in logical pixels.
  final double gridSpacing;

  /// Top-left of the grid in canvas space.
  final Offset gridOrigin;

  /// Microseconds since epoch — when the PDF was imported.
  final int createdAt;

  /// Microseconds since epoch — last structural change.
  final int lastModifiedAt;

  /// Optional link to Looponia's Timeline for Stroke Memory integration.
  final String? timelineRef;

  /// Local file path where the PDF bytes are stored for persistence.
  final String? filePath;

  const PdfDocumentModel({
    required this.sourceHash,
    required this.totalPages,
    required this.pages,
    this.gridColumns = 2,
    this.gridSpacing = 20.0,
    this.gridOrigin = Offset.zero,
    int? createdAt,
    int? lastModifiedAt,
    this.timelineRef,
    this.filePath,
  }) : createdAt = createdAt ?? 0,
       lastModifiedAt = lastModifiedAt ?? 0;

  // ---------------------------------------------------------------------------
  // CopyWith
  // ---------------------------------------------------------------------------

  PdfDocumentModel copyWith({
    String? sourceHash,
    int? totalPages,
    List<PdfPageModel>? pages,
    int? gridColumns,
    double? gridSpacing,
    Offset? gridOrigin,
    int? createdAt,
    int? lastModifiedAt,
    String? timelineRef,
    bool clearTimelineRef = false,
    String? filePath,
  }) {
    return PdfDocumentModel(
      sourceHash: sourceHash ?? this.sourceHash,
      totalPages: totalPages ?? this.totalPages,
      pages: pages ?? this.pages,
      gridColumns: gridColumns ?? this.gridColumns,
      gridSpacing: gridSpacing ?? this.gridSpacing,
      gridOrigin: gridOrigin ?? this.gridOrigin,
      createdAt: createdAt ?? this.createdAt,
      lastModifiedAt: lastModifiedAt ?? this.lastModifiedAt,
      timelineRef: clearTimelineRef ? null : (timelineRef ?? this.timelineRef),
      filePath: filePath ?? this.filePath,
    );
  }

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'sourceHash': sourceHash,
    'totalPages': totalPages,
    'pages': pages.map((p) => p.toJson()).toList(),
    'gridColumns': gridColumns,
    'gridSpacing': gridSpacing,
    'gridOrigin': {'dx': gridOrigin.dx, 'dy': gridOrigin.dy},
    'createdAt': createdAt,
    'lastModifiedAt': lastModifiedAt,
    if (timelineRef != null) 'timelineRef': timelineRef,
    if (filePath != null) 'filePath': filePath,
  };

  factory PdfDocumentModel.fromJson(Map<String, dynamic> json) {
    final originJson = json['gridOrigin'] as Map<String, dynamic>?;
    return PdfDocumentModel(
      sourceHash: json['sourceHash'] as String? ?? '',
      totalPages: (json['totalPages'] as num?)?.toInt() ?? 0,
      pages:
          (json['pages'] as List<dynamic>?)
              ?.map((p) => PdfPageModel.fromJson(p as Map<String, dynamic>))
              .toList() ??
          const [],
      gridColumns: (json['gridColumns'] as num?)?.toInt() ?? 2,
      gridSpacing: (json['gridSpacing'] as num?)?.toDouble() ?? 20.0,
      gridOrigin:
          originJson != null
              ? Offset(
                (originJson['dx'] as num?)?.toDouble() ?? 0,
                (originJson['dy'] as num?)?.toDouble() ?? 0,
              )
              : Offset.zero,
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      lastModifiedAt: (json['lastModifiedAt'] as num?)?.toInt() ?? 0,
      timelineRef: json['timelineRef'] as String?,
      filePath: json['filePath'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PdfDocumentModel &&
          sourceHash == other.sourceHash &&
          totalPages == other.totalPages &&
          listEquals(pages, other.pages) &&
          gridColumns == other.gridColumns &&
          gridSpacing == other.gridSpacing &&
          gridOrigin == other.gridOrigin &&
          createdAt == other.createdAt &&
          lastModifiedAt == other.lastModifiedAt &&
          timelineRef == other.timelineRef &&
          filePath == other.filePath;

  @override
  int get hashCode => Object.hash(
    sourceHash,
    totalPages,
    pages.length,
    gridColumns,
    gridSpacing,
    gridOrigin,
    createdAt,
    lastModifiedAt,
    timelineRef,
    filePath,
  );

  @override
  String toString() =>
      'PdfDocumentModel($totalPages pages, grid: ${gridColumns}col, '
      'hash: ${sourceHash.length > 8 ? sourceHash.substring(0, 8) : sourceHash}…)';
}
