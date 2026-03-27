import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'pdf_annotation_model.dart';

/// Background pattern for PDF pages.
enum PdfPageBackground {
  /// Plain white — no pattern.
  blank,

  /// Horizontal ruled lines (notebook style).
  ruled,

  /// Square grid (graph paper).
  grid,

  /// Dotted grid.
  dotted,

  /// Music staff lines (5-line staves).
  music,

  /// Cornell note-taking layout (sections for notes, cues, summary).
  cornell,
}

/// 📄 Pure data model for a single PDF page on the canvas.
///
/// Stores metadata about one page: its index in the original PDF,
/// native dimensions, grid position, lock state, and timestamps.
/// The actual raster image is held by [PdfPageNode], not here.
///
/// DESIGN PRINCIPLES:
/// - Immutable (copyWith pattern) for clean state management
/// - Fully serializable with optional-field fallbacks
/// - Timestamps for Stroke Memory / Timeline integration
class PdfPageModel {
  /// 0-based index in the original PDF document.
  final int pageIndex;

  /// Native width × height in PDF points (72 ppi).
  final Size originalSize;

  /// Whether this page is pinned in the grid layout (default: true).
  final bool isLocked;

  /// Row position in the automatic grid (used when locked).
  final int gridRow;

  /// Column position in the automatic grid (used when locked).
  final int gridCol;

  /// Free-form canvas position (used when unlocked and dragged).
  final Offset? customOffset;

  /// Page rotation in radians.
  final double rotation;

  /// IDs of annotation nodes (strokes, shapes) drawn on this page.
  final List<String> annotations;

  /// Whether annotations are visible on this page.
  final bool showAnnotations;

  /// Structured annotations (highlights, underlines, sticky notes).
  final List<PdfAnnotation> structuredAnnotations;

  /// Whether this is a blank (user-inserted) page with no native PDF content.
  final bool isBlank;

  /// Background pattern for this page (lines, grid, dots, etc.).
  final PdfPageBackground background;

  /// Whether this page is bookmarked by the user.
  final bool isBookmarked;

  /// Optional crop rectangle (normalized 0..1 fractions of originalSize).
  /// null = no crop (show full page).
  final Rect? cropRect;

  /// Microseconds since epoch — last annotation or position change.
  final int lastModifiedAt;

  const PdfPageModel({
    required this.pageIndex,
    required this.originalSize,
    this.isLocked = true,
    this.gridRow = 0,
    this.gridCol = 0,
    this.customOffset,
    this.rotation = 0.0,
    this.annotations = const [],
    this.showAnnotations = true,
    this.structuredAnnotations = const [],
    this.isBlank = false,
    this.background = PdfPageBackground.blank,
    this.isBookmarked = false,
    this.cropRect,
    int? lastModifiedAt,
  }) : lastModifiedAt = lastModifiedAt ?? 0;

  // ---------------------------------------------------------------------------
  // CopyWith
  // ---------------------------------------------------------------------------

  PdfPageModel copyWith({
    int? pageIndex,
    Size? originalSize,
    bool? isLocked,
    int? gridRow,
    int? gridCol,
    Offset? customOffset,
    bool clearCustomOffset = false,
    double? rotation,
    List<String>? annotations,
    bool? showAnnotations,
    List<PdfAnnotation>? structuredAnnotations,
    bool? isBlank,
    PdfPageBackground? background,
    bool? isBookmarked,
    Rect? cropRect,
    bool clearCropRect = false,
    int? lastModifiedAt,
  }) {
    return PdfPageModel(
      pageIndex: pageIndex ?? this.pageIndex,
      originalSize: originalSize ?? this.originalSize,
      isLocked: isLocked ?? this.isLocked,
      gridRow: gridRow ?? this.gridRow,
      gridCol: gridCol ?? this.gridCol,
      customOffset:
          clearCustomOffset ? null : (customOffset ?? this.customOffset),
      rotation: rotation ?? this.rotation,
      annotations: annotations ?? this.annotations,
      showAnnotations: showAnnotations ?? this.showAnnotations,
      structuredAnnotations:
          structuredAnnotations ?? this.structuredAnnotations,
      isBlank: isBlank ?? this.isBlank,
      background: background ?? this.background,
      isBookmarked: isBookmarked ?? this.isBookmarked,
      cropRect: clearCropRect ? null : (cropRect ?? this.cropRect),
      lastModifiedAt: lastModifiedAt ?? this.lastModifiedAt,
    );
  }

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'pageIndex': pageIndex,
    'originalSize': {
      'width': originalSize.width,
      'height': originalSize.height,
    },
    'isLocked': isLocked,
    'gridRow': gridRow,
    'gridCol': gridCol,
    if (customOffset != null)
      'customOffset': {'dx': customOffset!.dx, 'dy': customOffset!.dy},
    if (rotation != 0.0) 'rotation': rotation,
    if (annotations.isNotEmpty) 'annotations': annotations,
    if (!showAnnotations) 'showAnnotations': false,
    if (structuredAnnotations.isNotEmpty)
      'structuredAnnotations':
          structuredAnnotations.map((a) => a.toJson()).toList(),
    if (isBlank) 'isBlank': true,
    if (background != PdfPageBackground.blank) 'background': background.name,
    if (isBookmarked) 'isBookmarked': true,
    if (cropRect != null)
      'cropRect': {
        'left': cropRect!.left,
        'top': cropRect!.top,
        'right': cropRect!.right,
        'bottom': cropRect!.bottom,
      },
    'lastModifiedAt': lastModifiedAt,
  };

  factory PdfPageModel.fromJson(Map<String, dynamic> json) {
    // C7: Defensive fallback for missing originalSize
    Size originalSize = const Size(612, 792); // US Letter default
    if (json['originalSize'] is Map<String, dynamic>) {
      final sizeJson = json['originalSize'] as Map<String, dynamic>;
      originalSize = Size(
        (sizeJson['width'] as num?)?.toDouble() ?? 612,
        (sizeJson['height'] as num?)?.toDouble() ?? 792,
      );
    }

    Offset? customOffset;
    if (json['customOffset'] is Map<String, dynamic>) {
      final co = json['customOffset'] as Map<String, dynamic>;
      customOffset = Offset(
        (co['dx'] as num?)?.toDouble() ?? 0,
        (co['dy'] as num?)?.toDouble() ?? 0,
      );
    }

    return PdfPageModel(
      pageIndex: (json['pageIndex'] as num?)?.toInt() ?? 0,
      originalSize: originalSize,
      isLocked: json['isLocked'] as bool? ?? true,
      gridRow: (json['gridRow'] as num?)?.toInt() ?? 0,
      gridCol: (json['gridCol'] as num?)?.toInt() ?? 0,
      customOffset: customOffset,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      annotations:
          (json['annotations'] as List<dynamic>?)
              ?.whereType<String>()
              .toList() ??
          const [],
      showAnnotations: json['showAnnotations'] as bool? ?? true,
      structuredAnnotations:
          (json['structuredAnnotations'] as List<dynamic>?)
              ?.map((a) => PdfAnnotation.fromJson(a as Map<String, dynamic>))
              .toList() ??
          const [],
      isBlank: json['isBlank'] as bool? ?? false,
      background: PdfPageBackground.values.firstWhere(
        (b) => b.name == (json['background'] as String? ?? 'blank'),
        orElse: () => PdfPageBackground.blank,
      ),
      isBookmarked: json['isBookmarked'] as bool? ?? false,
      cropRect:
          json['cropRect'] is Map<String, dynamic>
              ? Rect.fromLTRB(
                (json['cropRect']['left'] as num?)?.toDouble() ?? 0,
                (json['cropRect']['top'] as num?)?.toDouble() ?? 0,
                (json['cropRect']['right'] as num?)?.toDouble() ?? 1,
                (json['cropRect']['bottom'] as num?)?.toDouble() ?? 1,
              )
              : null,
      lastModifiedAt: (json['lastModifiedAt'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PdfPageModel &&
          pageIndex == other.pageIndex &&
          originalSize == other.originalSize &&
          isLocked == other.isLocked &&
          gridRow == other.gridRow &&
          gridCol == other.gridCol &&
          customOffset == other.customOffset &&
          rotation == other.rotation &&
          listEquals(annotations, other.annotations) &&
          showAnnotations == other.showAnnotations &&
          listEquals(structuredAnnotations, other.structuredAnnotations) &&
          isBlank == other.isBlank &&
          background == other.background &&
          isBookmarked == other.isBookmarked &&
          cropRect == other.cropRect &&
          lastModifiedAt == other.lastModifiedAt;

  @override
  int get hashCode => Object.hash(
    pageIndex,
    originalSize,
    isLocked,
    gridRow,
    gridCol,
    customOffset,
    rotation,
    annotations.length,
    showAnnotations,
    structuredAnnotations.length,
    lastModifiedAt,
  );

  @override
  String toString() =>
      'PdfPageModel(page: $pageIndex, '
      '${originalSize.width.toInt()}×${originalSize.height.toInt()}, '
      '${isLocked ? "locked" : "unlocked"})';
}
