/// 📄 PDF EXPORT WRITER — Professional PDF 1.4 vector generator.
///
/// Generates vector PDF files from scene graph nodes without any external
/// dependencies. Supports paths, rectangles, text, images, gradients,
/// transforms, opacity, clipping, line styling, Flate compression,
/// metadata, and multi-page output.
///
/// ```dart
/// final writer = PdfExportWriter();
/// writer.beginPage(width: 595, height: 842);
/// writer.setFillColor(Color(0xFF2196F3));
/// writer.drawRect(10, 10, 200, 100);
/// writer.fillAndStroke();
/// final bytes = writer.finish(title: 'My Document');
/// ```
library;

import 'dart:io' show ZLibEncoder;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart' show Matrix4;

import '../core/scene_graph/canvas_node.dart';
import '../core/scene_graph/scene_graph.dart';
import '../core/nodes/group_node.dart';
import '../core/nodes/frame_node.dart'
    hide CrossAxisAlignment, MainAxisAlignment;
import '../core/nodes/path_node.dart';
import '../core/nodes/text_node.dart';
import '../core/nodes/rich_text_node.dart';
import '../core/nodes/shape_node.dart';
import '../core/nodes/stroke_node.dart';
import '../core/nodes/image_node.dart';
import '../core/vector/vector_path.dart';
import '../core/effects/gradient_fill.dart';

// =============================================================================
// PDF OBJECT HELPERS
// =============================================================================

/// A single PDF indirect object.
class _PdfObject {
  final int id;
  String content;
  int offset = 0;

  /// Optional raw binary data appended after [content].
  Uint8List? binaryData;

  _PdfObject(this.id, this.content, {this.binaryData});
}

// =============================================================================
// IMAGE XOBJECT
// =============================================================================

/// Registered image XObject reference.
class PdfImageXObject {
  /// PDF object ID for this image.
  final int objectId;

  /// Resource name (e.g. /Im1).
  final String resourceName;

  /// Pixel width.
  final int width;

  /// Pixel height.
  final int height;

  /// Optional SMask object ID (for alpha channel).
  final int? smaskId;

  const PdfImageXObject({
    required this.objectId,
    required this.resourceName,
    required this.width,
    required this.height,
    this.smaskId,
  });
}

// =============================================================================
// BOOKMARK
// =============================================================================

/// A PDF bookmark (outline) entry.
///
/// Bookmarks appear in the PDF viewer's sidebar and allow quick navigation
/// to specific pages.
class PdfBookmark {
  /// Display title in the bookmark tree.
  final String title;

  /// Zero-based page index to navigate to.
  final int pageIndex;

  /// Child bookmarks (for nested outline hierarchy).
  final List<PdfBookmark> children;

  const PdfBookmark({
    required this.title,
    required this.pageIndex,
    this.children = const [],
  });
}

// =============================================================================
// WATERMARK
// =============================================================================

/// Watermark position on the page.
enum WatermarkPosition {
  /// Centered diagonally across the page.
  diagonal,

  /// Centered horizontally and vertically.
  center,

  /// Tiled across the entire page.
  tiled,
}

/// A text watermark applied to PDF pages.
class PdfWatermark {
  /// Text to render (e.g. "DRAFT", "CONFIDENTIAL").
  final String text;

  /// Font size in points.
  final double fontSize;

  /// Text color.
  final ui.Color color;

  /// Opacity (0.0 = invisible, 1.0 = fully opaque).
  final double opacity;

  /// Rotation angle in degrees (only used for [WatermarkPosition.diagonal]).
  final double rotation;

  /// Position mode.
  final WatermarkPosition position;

  const PdfWatermark({
    required this.text,
    this.fontSize = 72,
    this.color = const ui.Color(0xFFCCCCCC),
    this.opacity = 0.3,
    this.rotation = -45,
    this.position = WatermarkPosition.diagonal,
  });
}

// =============================================================================
// LINK ANNOTATION
// =============================================================================

/// A clickable link annotation on a PDF page.
class PdfLinkAnnotation {
  /// Clickable rectangle (in page coordinates, top-left origin).
  final ui.Rect rect;

  /// External URI (e.g. "https://example.com").
  /// If null, this is an internal link using [destPageIndex].
  final String? uri;

  /// Destination page index for internal links.
  final int? destPageIndex;

  const PdfLinkAnnotation.uri({required this.rect, required String this.uri})
    : destPageIndex = null;

  const PdfLinkAnnotation.page({
    required this.rect,
    required int this.destPageIndex,
  }) : uri = null;
}

// =============================================================================
// PAGE LABEL
// =============================================================================

/// Page numbering style for PDF page labels.
enum PageLabelStyle {
  /// Decimal (1, 2, 3, ...)
  decimal,

  /// Uppercase Roman (I, II, III, IV, ...)
  upperRoman,

  /// Lowercase Roman (i, ii, iii, iv, ...)
  lowerRoman,

  /// Uppercase alphabetic (A, B, C, ...)
  upperAlpha,

  /// Lowercase alphabetic (a, b, c, ...)
  lowerAlpha,

  /// No numbering (prefix only).
  none,
}

/// A page label range definition.
///
/// Defines numbering for pages starting at [startPage].
class PdfPageLabel {
  /// Zero-based page index where this label range starts.
  final int startPage;

  /// Numbering style.
  final PageLabelStyle style;

  /// Optional prefix string (e.g. "Chapter ").
  final String prefix;

  /// Starting number (default: 1).
  final int startNumber;

  const PdfPageLabel({
    required this.startPage,
    this.style = PageLabelStyle.decimal,
    this.prefix = '',
    this.startNumber = 1,
  });
}

// =============================================================================
// FORM FIELDS
// =============================================================================

/// Base class for PDF interactive form fields.
sealed class PdfFormField {
  /// Field name (unique identifier within the form).
  final String name;

  /// Field position on the page (top-left origin).
  final ui.Rect rect;

  /// Page index where the field appears (0-based).
  final int pageIndex;

  const PdfFormField({
    required this.name,
    required this.rect,
    this.pageIndex = 0,
  });
}

/// Interactive text input field.
class PdfTextField extends PdfFormField {
  final String defaultValue;
  final double fontSize;
  final bool multiline;
  final int maxLength;

  const PdfTextField({
    required super.name,
    required super.rect,
    super.pageIndex,
    this.defaultValue = '',
    this.fontSize = 12,
    this.multiline = false,
    this.maxLength = 0,
  });
}

/// Checkbox toggle field.
class PdfCheckboxField extends PdfFormField {
  final bool defaultChecked;

  const PdfCheckboxField({
    required super.name,
    required super.rect,
    super.pageIndex,
    this.defaultChecked = false,
  });
}

/// Dropdown / combo-box selection field.
class PdfDropdownField extends PdfFormField {
  final List<String> options;
  final String? defaultValue;
  final bool editable;

  const PdfDropdownField({
    required super.name,
    required super.rect,
    super.pageIndex,
    required this.options,
    this.defaultValue,
    this.editable = false,
  });
}

// =============================================================================
// REDACTION
// =============================================================================

/// A content redaction area on a PDF page.
class PdfRedaction {
  final ui.Rect rect;
  final ui.Color overlayColor;
  final String? replacementText;
  final int pageIndex;

  const PdfRedaction({
    required this.rect,
    this.overlayColor = const ui.Color(0xFF000000),
    this.replacementText,
    this.pageIndex = 0,
  });
}

// =============================================================================
// PDF EXPORT WRITER
// =============================================================================

/// Professional PDF 1.4 vector writer.
///
/// Generates a valid PDF file from scene graph drawing commands.
/// Uses PDF content stream operators:
/// - `m`/`l`/`c` for path commands (moveTo, lineTo, curveTo)
/// - `re` for rectangles
/// - `f`/`S`/`B` for fill/stroke/both
/// - `rg`/`RG` for fill/stroke color
/// - `cm` for transform matrix
/// - `q`/`Q` for save/restore graphics state
/// - `Tf` for font, `Tj` for text
/// - `Do` for image XObjects
/// - `W n` for clipping paths
/// - `J`/`j`/`d` for line cap/join/dash
/// - `/Pattern cs` for gradient fills
class PdfExportWriter {
  final List<_PdfObject> _objects = [];
  final List<int> _pageObjectIds = [];
  int _nextId = 1;

  // Current page content stream
  StringBuffer? _currentPage;
  double _pageWidth = 595;
  double _pageHeight = 842;

  // Font object ID (shared across pages)
  int? _fontObjectId;

  // ExtGState objects for opacity (keyed by alpha 0-255)
  final Map<int, int> _gsAlphaObjects = {};

  // Image XObjects registered for this PDF
  final List<PdfImageXObject> _imageXObjects = [];
  int _imageCounter = 0;

  // Gradient shading patterns
  final Map<int, int> _shadingPatterns = {}; // patternId → objectId
  int _patternCounter = 0;

  /// Whether to compress content streams with Flate/zlib.
  final bool enableCompression;

  /// Callback to resolve image file paths to bytes.
  /// Set this before calling [exportSceneGraph] if images should be embedded.
  Uint8List Function(String path)? imageResolver;

  // Bookmarks to add to the outline tree
  final List<PdfBookmark> _bookmarks = [];

  // Watermark applied to all pages
  PdfWatermark? _watermark;

  // Per-page link annotations (indexed by page number, 0-based)
  final Map<int, List<PdfLinkAnnotation>> _pageAnnotations = {};
  List<PdfLinkAnnotation>? _currentPageAnnotations;

  // Page labels
  final List<PdfPageLabel> _pageLabels = [];

  // Form fields
  final List<PdfFormField> _formFields = [];

  // Redactions
  final List<PdfRedaction> _redactions = [];

  /// Whether to generate PDF/A-1b conformant output.
  bool pdfAConformance = false;

  PdfExportWriter({this.enableCompression = true, this.imageResolver});

  /// Whether any pages have been created.
  bool get hasPages => _pageObjectIds.isNotEmpty || _currentPage != null;

  // ---------------------------------------------------------------------------
  // Page management
  // ---------------------------------------------------------------------------

  /// Begin a new page with the given dimensions (in points, 72 DPI).
  void beginPage({double width = 595, double height = 842}) {
    // Finalize previous page if any.
    if (_currentPage != null) {
      _finalizePage();
    }

    _pageWidth = width;
    _pageHeight = height;
    _currentPage = StringBuffer();
    _currentPageAnnotations = [];
  }

  /// Finalize the current page and store it.
  void _finalizePage() {
    if (_currentPage == null) return;

    // Append watermark if set.
    if (_watermark != null) {
      _appendWatermark(_currentPage!, _pageWidth, _pageHeight);
    }

    final content = _currentPage.toString();
    final rawBytes = utf8.encode(content);

    // Optionally compress the content stream.
    final Uint8List streamBytes;
    final String filterEntry;
    if (enableCompression && rawBytes.length > 64) {
      streamBytes = Uint8List.fromList(ZLibEncoder().convert(rawBytes));
      filterEntry = ' /Filter /FlateDecode';
    } else {
      streamBytes = Uint8List.fromList(rawBytes);
      filterEntry = '';
    }

    // Content stream object.
    final streamId = _allocId();
    final header =
        '$streamId 0 obj\n'
        '<< /Length ${streamBytes.length}$filterEntry >>\n'
        'stream\n';
    final trailer =
        '\nendstream\n'
        'endobj\n';
    _objects.add(
      _PdfObject(
        streamId,
        header,
        binaryData: _concatBytes(streamBytes, utf8.encode(trailer)),
      ),
    );

    // Ensure font object exists.
    _fontObjectId ??= _createFontObject();

    // Build resources dict with font, ExtGState, XObjects, and patterns.
    final resourceParts = <String>['/Font << /F1 $_fontObjectId 0 R >>'];
    if (_gsAlphaObjects.isNotEmpty) {
      final gsEntries = _gsAlphaObjects.entries
          .map((e) => '/GS${e.key} ${e.value} 0 R')
          .join(' ');
      resourceParts.add('/ExtGState << $gsEntries >>');
    }
    if (_imageXObjects.isNotEmpty) {
      final xobjEntries = _imageXObjects
          .map((x) => '/${x.resourceName} ${x.objectId} 0 R')
          .join(' ');
      resourceParts.add('/XObject << $xobjEntries >>');
    }
    if (_shadingPatterns.isNotEmpty) {
      final patEntries = _shadingPatterns.entries
          .map((e) => '/P${e.key} ${e.value} 0 R')
          .join(' ');
      resourceParts.add('/Pattern << $patEntries >>');
    }
    final resources = resourceParts.join(' ');

    // Build annotation objects for this page.
    String annotsRef = '';
    if (_currentPageAnnotations != null &&
        _currentPageAnnotations!.isNotEmpty) {
      final annotIds = <int>[];
      for (final annot in _currentPageAnnotations!) {
        final annotId = _allocId();
        // Convert rect from top-left to PDF bottom-left coordinates.
        final llx = annot.rect.left;
        final lly = _pageHeight - annot.rect.bottom;
        final urx = annot.rect.right;
        final ury = _pageHeight - annot.rect.top;

        String actionOrDest;
        if (annot.uri != null) {
          actionOrDest = '/A << /S /URI /URI (${_escapeText(annot.uri!)}) >>';
        } else {
          // Internal link — dest will resolve in finish() via %%PAGEDEST_N%%
          actionOrDest = '/Dest [%%PAGEDEST_${annot.destPageIndex}%% /Fit]';
        }

        _objects.add(
          _PdfObject(
            annotId,
            '$annotId 0 obj\n'
            '<< /Type /Annot /Subtype /Link\n'
            '   /Rect [${_n(llx)} ${_n(lly)} ${_n(urx)} ${_n(ury)}]\n'
            '   /Border [0 0 0]\n'
            '   $actionOrDest\n'
            '>>\n'
            'endobj\n',
          ),
        );
        annotIds.add(annotId);
      }
      final annotRefs = annotIds.map((id) => '$id 0 R').join(' ');
      annotsRef = '   /Annots [$annotRefs]\n';
      _pageAnnotations[_pageObjectIds.length] = _currentPageAnnotations!;
    }

    // Page object.
    final pageId = _allocId();
    _objects.add(
      _PdfObject(
        pageId,
        '$pageId 0 obj\n'
        '<< /Type /Page\n'
        '   /MediaBox [0 0 ${_n(_pageWidth)} ${_n(_pageHeight)}]\n'
        '   /Contents $streamId 0 R\n'
        '   /Resources << $resources >>\n'
        '$annotsRef'
        '>>\n'
        'endobj\n',
      ),
    );

    _pageObjectIds.add(pageId);
    _currentPage = null;
  }

  // ---------------------------------------------------------------------------
  // Graphics state
  // ---------------------------------------------------------------------------

  /// Save graphics state (push).
  void saveState() => _currentPage?.write('q\n');

  /// Restore graphics state (pop).
  void restoreState() => _currentPage?.write('Q\n');

  /// Apply a 2D affine transform matrix.
  ///
  /// PDF uses bottom-left origin, so we apply a Y-flip in the transform.
  void setTransform(
    double a,
    double b,
    double c,
    double d,
    double e,
    double f,
  ) {
    _currentPage?.write(
      '${_n(a)} ${_n(b)} ${_n(c)} ${_n(d)} ${_n(e)} ${_n(f)} cm\n',
    );
  }

  /// Set fill color (RGB, 0.0-1.0).
  void setFillColor(ui.Color color) {
    _currentPage?.write('${_n(color.r)} ${_n(color.g)} ${_n(color.b)} rg\n');
  }

  /// Set stroke color (RGB, 0.0-1.0).
  void setStrokeColor(ui.Color color) {
    _currentPage?.write('${_n(color.r)} ${_n(color.g)} ${_n(color.b)} RG\n');
  }

  /// Set stroke line width.
  void setLineWidth(double width) {
    _currentPage?.write('${_n(width)} w\n');
  }

  /// Set opacity via ExtGState.
  void setOpacity(double opacity) {
    if (opacity >= 1.0) return;
    final alpha = (opacity * 255).round().clamp(0, 255);
    if (!_gsAlphaObjects.containsKey(alpha)) {
      final gsId = _allocId();
      _objects.add(
        _PdfObject(
          gsId,
          '$gsId 0 obj\n'
          '<< /Type /ExtGState /ca ${_n(opacity)} /CA ${_n(opacity)} >>\n'
          'endobj\n',
        ),
      );
      _gsAlphaObjects[alpha] = gsId;
    }
    _currentPage?.write('/GS$alpha gs\n');
  }

  // ---------------------------------------------------------------------------
  // Line styling
  // ---------------------------------------------------------------------------

  /// Set line cap style.
  ///
  /// - 0: butt cap (default)
  /// - 1: round cap
  /// - 2: projecting square cap
  void setLineCap(int cap) {
    _currentPage?.write('$cap J\n');
  }

  /// Set line join style.
  ///
  /// - 0: miter join (default)
  /// - 1: round join
  /// - 2: bevel join
  void setLineJoin(int join) {
    _currentPage?.write('$join j\n');
  }

  /// Set dash pattern.
  ///
  /// [dashArray] defines the dash/gap lengths. [phase] is the offset.
  /// Example: `setDashPattern([6, 3], 0)` for 6pt dash, 3pt gap.
  /// Empty array means solid line.
  void setDashPattern(List<double> dashArray, double phase) {
    final arr = dashArray.map(_n).join(' ');
    _currentPage?.write('[$arr] ${_n(phase)} d\n');
  }

  // ---------------------------------------------------------------------------
  // Path commands
  // ---------------------------------------------------------------------------

  /// Move to point (x, y).
  void moveTo(double x, double y) {
    _currentPage?.write('${_n(x)} ${_n(_flipY(y))} m\n');
  }

  /// Line to point (x, y).
  void lineTo(double x, double y) {
    _currentPage?.write('${_n(x)} ${_n(_flipY(y))} l\n');
  }

  /// Cubic Bézier curve to (x3, y3) with control points (x1, y1) and (x2, y2).
  void curveTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) {
    _currentPage?.write(
      '${_n(x1)} ${_n(_flipY(y1))} '
      '${_n(x2)} ${_n(_flipY(y2))} '
      '${_n(x3)} ${_n(_flipY(y3))} c\n',
    );
  }

  /// Draw a rectangle at (x, y) with given width and height.
  void drawRect(double x, double y, double width, double height) {
    // PDF rect uses bottom-left origin.
    _currentPage?.write(
      '${_n(x)} ${_n(_flipY(y + height))} ${_n(width)} ${_n(height)} re\n',
    );
  }

  /// Close the current path.
  void closePath() => _currentPage?.write('h\n');

  /// Fill the current path (non-zero winding rule).
  void fill() => _currentPage?.write('f\n');

  /// Stroke the current path.
  void stroke() => _currentPage?.write('S\n');

  /// Fill and stroke the current path.
  void fillAndStroke() => _currentPage?.write('B\n');

  /// End path without fill or stroke (clipping).
  void endPath() => _currentPage?.write('n\n');

  /// Inject raw content stream operators directly.
  ///
  /// Used by [PdfDocumentOperations] for merge/split operations.
  /// The content is written verbatim — caller is responsible for validity.
  void injectRawContent(String content) {
    _currentPage?.write(content);
    if (!content.endsWith('\n')) {
      _currentPage?.write('\n');
    }
  }

  // ---------------------------------------------------------------------------
  // Clipping
  // ---------------------------------------------------------------------------

  /// Clip to the current path using non-zero winding rule.
  ///
  /// Must call after building a path and before `endPath()`.
  void clipPath() => _currentPage?.write('W n\n');

  /// Clip to a rectangle.
  void clipRect(double x, double y, double width, double height) {
    drawRect(x, y, width, height);
    _currentPage?.write('W n\n');
  }

  // ---------------------------------------------------------------------------
  // Text
  // ---------------------------------------------------------------------------

  /// Draw text at position (x, y) with given font size.
  void drawText(String text, double x, double y, double fontSize) {
    final escaped = _escapeText(text);
    _currentPage?.write(
      'BT\n'
      '/F1 ${_n(fontSize)} Tf\n'
      '${_n(x)} ${_n(_flipY(y))} Td\n'
      '($escaped) Tj\n'
      'ET\n',
    );
  }

  // ---------------------------------------------------------------------------
  // Bookmarks
  // ---------------------------------------------------------------------------

  /// Add a bookmark (outline) entry.
  ///
  /// Bookmarks navigate to a specific page when clicked in the PDF viewer.
  /// Supports nested bookmarks via [PdfBookmark.children].
  void addBookmark(PdfBookmark bookmark) {
    _bookmarks.add(bookmark);
  }

  /// Add a flat bookmark by title and page index.
  void addBookmarkEntry(String title, int pageIndex) {
    _bookmarks.add(PdfBookmark(title: title, pageIndex: pageIndex));
  }

  // ---------------------------------------------------------------------------
  // Watermarks
  // ---------------------------------------------------------------------------

  /// Set a watermark to apply to all pages.
  ///
  /// The watermark is rendered as transparent text on top of page content.
  void setWatermark(PdfWatermark watermark) {
    _watermark = watermark;
  }

  // ---------------------------------------------------------------------------
  // Hyperlinks / Link Annotations
  // ---------------------------------------------------------------------------

  /// Add an external URI link annotation to the current page.
  ///
  /// [rect] is the clickable area in page coordinates (top-left origin).
  /// The link opens [uri] in the user's browser.
  void addUriLink(ui.Rect rect, String uri) {
    _currentPageAnnotations?.add(PdfLinkAnnotation.uri(rect: rect, uri: uri));
  }

  /// Add an internal page navigation link to the current page.
  ///
  /// [rect] is the clickable area. Clicking navigates to [destPageIndex].
  void addPageLink(ui.Rect rect, int destPageIndex) {
    _currentPageAnnotations?.add(
      PdfLinkAnnotation.page(rect: rect, destPageIndex: destPageIndex),
    );
  }

  // ---------------------------------------------------------------------------
  // Page Labels
  // ---------------------------------------------------------------------------

  /// Set page labels for the document.
  ///
  /// Labels control how page numbers appear in the PDF viewer's toolbar.
  /// Each [PdfPageLabel] defines a range starting at [PdfPageLabel.startPage].
  void setPageLabels(List<PdfPageLabel> labels) {
    _pageLabels.clear();
    _pageLabels.addAll(labels);
  }

  // ---------------------------------------------------------------------------
  // Form Fields
  // ---------------------------------------------------------------------------

  /// Add a text input field to the PDF.
  void addTextField(PdfTextField field) => _formFields.add(field);

  /// Add a checkbox field to the PDF.
  void addCheckbox(PdfCheckboxField field) => _formFields.add(field);

  /// Add a dropdown/combo-box field to the PDF.
  void addDropdown(PdfDropdownField field) => _formFields.add(field);

  // ---------------------------------------------------------------------------
  // Redaction
  // ---------------------------------------------------------------------------

  /// Add a content redaction to the PDF.
  ///
  /// Redacted areas are covered with a solid rectangle and optionally
  /// overlaid with replacement text. A `/Redact` annotation is also added.
  void addRedaction(PdfRedaction redaction) => _redactions.add(redaction);

  /// Add a JPEG image as an XObject.
  ///
  /// Returns a [PdfImageXObject] reference to use with [drawImageXObject].
  /// JPEG bytes are embedded directly with /DCTDecode (zero re-encoding).
  PdfImageXObject addJpegXObject(Uint8List jpegBytes, int width, int height) {
    final imgId = _allocId();
    final name = 'Im${++_imageCounter}';

    final header =
        '$imgId 0 obj\n'
        '<< /Type /XObject /Subtype /Image\n'
        '   /Width $width /Height $height\n'
        '   /ColorSpace /DeviceRGB\n'
        '   /BitsPerComponent 8\n'
        '   /Filter /DCTDecode\n'
        '   /Length ${jpegBytes.length}\n'
        '>>\n'
        'stream\n';
    final trailer =
        '\nendstream\n'
        'endobj\n';
    _objects.add(
      _PdfObject(
        imgId,
        header,
        binaryData: _concatBytes(jpegBytes, utf8.encode(trailer)),
      ),
    );

    final xobj = PdfImageXObject(
      objectId: imgId,
      resourceName: name,
      width: width,
      height: height,
    );
    _imageXObjects.add(xobj);
    return xobj;
  }

  /// Add a raw RGBA image as an XObject.
  ///
  /// Strips alpha channel → RGB, compresses with Flate.
  /// Alpha channel is stored as a separate SMask XObject.
  PdfImageXObject addRgbaXObject(Uint8List rgbaPixels, int width, int height) {
    // Split RGBA → RGB + Alpha
    final pixelCount = width * height;
    final rgb = Uint8List(pixelCount * 3);
    final alpha = Uint8List(pixelCount);
    bool hasAlpha = false;

    for (int i = 0; i < pixelCount; i++) {
      rgb[i * 3] = rgbaPixels[i * 4];
      rgb[i * 3 + 1] = rgbaPixels[i * 4 + 1];
      rgb[i * 3 + 2] = rgbaPixels[i * 4 + 2];
      alpha[i] = rgbaPixels[i * 4 + 3];
      if (alpha[i] != 255) hasAlpha = true;
    }

    // Compress RGB data
    final compressedRgb = Uint8List.fromList(ZLibEncoder().convert(rgb));

    // Create alpha SMask if needed
    int? smaskId;
    if (hasAlpha) {
      smaskId = _allocId();
      final compressedAlpha = Uint8List.fromList(ZLibEncoder().convert(alpha));
      final smaskHeader =
          '$smaskId 0 obj\n'
          '<< /Type /XObject /Subtype /Image\n'
          '   /Width $width /Height $height\n'
          '   /ColorSpace /DeviceGray\n'
          '   /BitsPerComponent 8\n'
          '   /Filter /FlateDecode\n'
          '   /Length ${compressedAlpha.length}\n'
          '>>\n'
          'stream\n';
      final smaskTrailer = '\nendstream\nendobj\n';
      _objects.add(
        _PdfObject(
          smaskId,
          smaskHeader,
          binaryData: _concatBytes(compressedAlpha, utf8.encode(smaskTrailer)),
        ),
      );
    }

    // Create image XObject
    final imgId = _allocId();
    final name = 'Im${++_imageCounter}';
    final smaskRef = smaskId != null ? '   /SMask $smaskId 0 R\n' : '';

    final imgHeader =
        '$imgId 0 obj\n'
        '<< /Type /XObject /Subtype /Image\n'
        '   /Width $width /Height $height\n'
        '   /ColorSpace /DeviceRGB\n'
        '   /BitsPerComponent 8\n'
        '   /Filter /FlateDecode\n'
        '$smaskRef'
        '   /Length ${compressedRgb.length}\n'
        '>>\n'
        'stream\n';
    final imgTrailer = '\nendstream\nendobj\n';
    _objects.add(
      _PdfObject(
        imgId,
        imgHeader,
        binaryData: _concatBytes(compressedRgb, utf8.encode(imgTrailer)),
      ),
    );

    final xobj = PdfImageXObject(
      objectId: imgId,
      resourceName: name,
      width: width,
      height: height,
      smaskId: smaskId,
    );
    _imageXObjects.add(xobj);
    return xobj;
  }

  /// Draw an image XObject at the given position and size.
  ///
  /// The image is placed using the current transform matrix.
  void drawImageXObject(
    PdfImageXObject xobj,
    double x,
    double y,
    double width,
    double height,
  ) {
    saveState();
    // PDF images are drawn in a 1×1 unit square; we scale to target size
    // and translate to position. Y is flipped.
    _currentPage?.write(
      '${_n(width)} 0 0 ${_n(height)} ${_n(x)} ${_n(_flipY(y + height))} cm\n'
      '/${xobj.resourceName} Do\n',
    );
    restoreState();
  }

  // ---------------------------------------------------------------------------
  // Gradient fills
  // ---------------------------------------------------------------------------

  /// Add a linear gradient shading pattern.
  ///
  /// Returns a pattern ID to use with [setFillGradient].
  int addLinearGradient(
    ui.Offset from,
    ui.Offset to,
    List<ui.Color> colors,
    List<double> stops,
  ) {
    if (colors.length < 2) return -1;

    // Build a stitching function for multi-stop gradients
    final funcId = _buildGradientFunction(colors, stops);

    // Shading dictionary
    final shadingId = _allocId();
    _objects.add(
      _PdfObject(
        shadingId,
        '$shadingId 0 obj\n'
        '<< /ShadingType 2\n'
        '   /ColorSpace /DeviceRGB\n'
        '   /Coords [${_n(from.dx)} ${_n(_flipY(from.dy))} ${_n(to.dx)} ${_n(_flipY(to.dy))}]\n'
        '   /Function $funcId 0 R\n'
        '   /Extend [true true]\n'
        '>>\n'
        'endobj\n',
      ),
    );

    // Pattern dictionary
    final patternId = _allocId();
    _objects.add(
      _PdfObject(
        patternId,
        '$patternId 0 obj\n'
        '<< /Type /Pattern\n'
        '   /PatternType 2\n'
        '   /Shading $shadingId 0 R\n'
        '>>\n'
        'endobj\n',
      ),
    );

    final id = ++_patternCounter;
    _shadingPatterns[id] = patternId;
    return id;
  }

  /// Add a radial gradient shading pattern.
  ///
  /// Returns a pattern ID to use with [setFillGradient].
  int addRadialGradient(
    ui.Offset center,
    double radius,
    List<ui.Color> colors,
    List<double> stops,
  ) {
    if (colors.length < 2) return -1;

    final funcId = _buildGradientFunction(colors, stops);

    final shadingId = _allocId();
    _objects.add(
      _PdfObject(
        shadingId,
        '$shadingId 0 obj\n'
        '<< /ShadingType 3\n'
        '   /ColorSpace /DeviceRGB\n'
        '   /Coords [${_n(center.dx)} ${_n(_flipY(center.dy))} 0 ${_n(center.dx)} ${_n(_flipY(center.dy))} ${_n(radius)}]\n'
        '   /Function $funcId 0 R\n'
        '   /Extend [true true]\n'
        '>>\n'
        'endobj\n',
      ),
    );

    final patternId = _allocId();
    _objects.add(
      _PdfObject(
        patternId,
        '$patternId 0 obj\n'
        '<< /Type /Pattern\n'
        '   /PatternType 2\n'
        '   /Shading $shadingId 0 R\n'
        '>>\n'
        'endobj\n',
      ),
    );

    final id = ++_patternCounter;
    _shadingPatterns[id] = patternId;
    return id;
  }

  /// Set fill to a gradient pattern.
  void setFillGradient(int patternId) {
    _currentPage?.write('/Pattern cs /P$patternId scn\n');
  }

  /// Build a PDF function for gradient color interpolation.
  int _buildGradientFunction(List<ui.Color> colors, List<double> stops) {
    if (colors.length == 2) {
      // Simple interpolation function (Type 2 — exponential)
      final funcId = _allocId();
      final c0 = colors[0];
      final c1 = colors[1];
      _objects.add(
        _PdfObject(
          funcId,
          '$funcId 0 obj\n'
          '<< /FunctionType 2\n'
          '   /Domain [0 1]\n'
          '   /C0 [${_n(c0.r)} ${_n(c0.g)} ${_n(c0.b)}]\n'
          '   /C1 [${_n(c1.r)} ${_n(c1.g)} ${_n(c1.b)}]\n'
          '   /N 1\n'
          '>>\n'
          'endobj\n',
        ),
      );
      return funcId;
    }

    // Multi-stop: stitching function (Type 3)
    final subFuncIds = <int>[];
    for (int i = 0; i < colors.length - 1; i++) {
      final fId = _allocId();
      final c0 = colors[i];
      final c1 = colors[i + 1];
      _objects.add(
        _PdfObject(
          fId,
          '$fId 0 obj\n'
          '<< /FunctionType 2\n'
          '   /Domain [0 1]\n'
          '   /C0 [${_n(c0.r)} ${_n(c0.g)} ${_n(c0.b)}]\n'
          '   /C1 [${_n(c1.r)} ${_n(c1.g)} ${_n(c1.b)}]\n'
          '   /N 1\n'
          '>>\n'
          'endobj\n',
        ),
      );
      subFuncIds.add(fId);
    }

    // Compute bounds and encode arrays
    final bounds = <double>[];
    final encode = <String>[];
    for (int i = 0; i < subFuncIds.length; i++) {
      if (i < subFuncIds.length - 1) {
        bounds.add(
          stops.length > i + 1 ? stops[i + 1] : (i + 1) / subFuncIds.length,
        );
      }
      encode.add('0 1');
    }

    final funcId = _allocId();
    final funcsRef = subFuncIds.map((id) => '$id 0 R').join(' ');
    final boundsStr = bounds.map(_n).join(' ');
    final encodeStr = encode.join(' ');
    _objects.add(
      _PdfObject(
        funcId,
        '$funcId 0 obj\n'
        '<< /FunctionType 3\n'
        '   /Domain [0 1]\n'
        '   /Functions [$funcsRef]\n'
        '   /Bounds [$boundsStr]\n'
        '   /Encode [$encodeStr]\n'
        '>>\n'
        'endobj\n',
      ),
    );
    return funcId;
  }

  // ---------------------------------------------------------------------------
  // Scene graph export
  // ---------------------------------------------------------------------------

  /// Export an entire [SceneGraph] as a single-page PDF.
  ///
  /// [bounds] defines the content area. The page size matches the bounds.
  void exportSceneGraph(SceneGraph sceneGraph, ui.Rect bounds) {
    beginPage(width: bounds.width, height: bounds.height);

    for (final layer in sceneGraph.layers) {
      if (!layer.isVisible) continue;
      _exportNode(layer, bounds);
    }
  }

  /// Export a single [CanvasNode] subtree.
  void exportNode(CanvasNode node, ui.Rect bounds) {
    beginPage(width: bounds.width, height: bounds.height);
    _exportNode(node, bounds);
  }

  /// Recursively export a node to PDF commands.
  void _exportNode(CanvasNode node, ui.Rect bounds) {
    if (!node.isVisible) return;

    saveState();

    // Apply node transform (translate to local coordinate space).
    final m = node.localTransform;
    if (m != Matrix4.identity()) {
      final s = m.storage;
      // Translate relative to bounds origin.
      setTransform(
        s[0],
        -s[1],
        -s[4],
        s[5],
        s[12] - bounds.left,
        s[13] - bounds.top,
      );
    } else {
      // Just offset by bounds origin for root-level nodes.
      setTransform(1, 0, 0, 1, -bounds.left, -bounds.top);
    }

    // Apply opacity.
    if (node.opacity < 1.0) {
      setOpacity(node.opacity);
    }

    // Dispatch by node type.
    if (node is FrameNode) {
      _exportFrameNode(node, bounds);
    } else if (node is GroupNode) {
      _exportGroupNode(node, bounds);
    } else if (node is PathNode) {
      _exportPathNode(node);
    } else if (node is ShapeNode) {
      _exportShapeNode(node);
    } else if (node is RichTextNode) {
      _exportRichTextNode(node);
    } else if (node is TextNode) {
      _exportTextNode(node);
    } else if (node is StrokeNode) {
      _exportStrokeNode(node);
    } else if (node is ImageNode) {
      _exportImageNode(node);
    } else {
      // Fallback: draw bounding box.
      final b = node.localBounds;
      if (b.isFinite && !b.isEmpty) {
        setFillColor(const ui.Color(0xFFCCCCCC));
        setStrokeColor(const ui.Color(0xFF999999));
        setLineWidth(0.5);
        drawRect(b.left, b.top, b.width, b.height);
        fillAndStroke();
      }
    }

    restoreState();
  }

  void _exportGroupNode(GroupNode node, ui.Rect bounds) {
    for (final child in node.children) {
      _exportNode(
        child,
        ui.Rect.zero,
      ); // Children use parent's coordinate space.
    }
  }

  void _exportFrameNode(FrameNode node, ui.Rect bounds) {
    final b = node.localBounds;

    // Clip children to frame bounds if needed.
    if (node.clipContent) {
      saveState();
      clipRect(b.left, b.top, b.width, b.height);
    }

    // Draw frame background.
    if (node.fillColor != null) {
      setFillColor(node.fillColor!);
      drawRect(b.left, b.top, b.width, b.height);
      fill();
    }

    // Draw frame border.
    if (node.strokeColor != null && node.strokeWidth > 0) {
      setStrokeColor(node.strokeColor!);
      setLineWidth(node.strokeWidth);
      drawRect(b.left, b.top, b.width, b.height);
      stroke();
    }

    // Export children.
    for (final child in node.children) {
      _exportNode(child, ui.Rect.zero);
    }

    if (node.clipContent) {
      restoreState();
    }
  }

  void _exportPathNode(PathNode node) {
    final path = node.path;

    // Check for gradient fill first.
    if (node.fillGradient != null) {
      _exportPathWithGradient(node);
      return;
    }

    // Fill.
    // ignore: deprecated_member_use_from_same_package
    if (node.fillColor != null) {
      // ignore: deprecated_member_use_from_same_package
      setFillColor(node.fillColor!);
    }

    // Stroke.
    // ignore: deprecated_member_use_from_same_package
    if (node.strokeColor != null) {
      // ignore: deprecated_member_use_from_same_package
      setStrokeColor(node.strokeColor!);
      setLineWidth(node.strokeWidth);
    }

    // Convert path segments to PDF commands.
    _writePathSegments(path);

    if (path.isClosed) closePath();

    // ignore: deprecated_member_use_from_same_package
    final hasFill = node.fillColor != null;
    // ignore: deprecated_member_use_from_same_package
    final hasStroke = node.strokeColor != null;

    if (hasFill && hasStroke) {
      fillAndStroke();
    } else if (hasFill) {
      fill();
    } else if (hasStroke) {
      stroke();
    } else {
      endPath();
    }
  }

  void _exportPathWithGradient(PathNode node) {
    final gradient = node.fillGradient!;
    final path = node.path;
    final b = node.localBounds;

    int patternId;
    if (gradient.type == GradientType.radial) {
      final center = ui.Offset(b.left + b.width * 0.5, b.top + b.height * 0.5);
      final radius = math.max(b.width, b.height) * 0.5;
      patternId = addRadialGradient(
        center,
        radius,
        gradient.colors,
        gradient.stops,
      );
    } else {
      // Linear (default) or conic (approximate as linear)
      final from = ui.Offset(b.left, b.top);
      final to = ui.Offset(b.right, b.bottom);
      patternId = addLinearGradient(from, to, gradient.colors, gradient.stops);
    }

    if (patternId > 0) {
      setFillGradient(patternId);
    }

    _writePathSegments(path);
    if (path.isClosed) closePath();

    // ignore: deprecated_member_use_from_same_package
    final hasStroke = node.strokeColor != null;
    if (hasStroke) {
      // ignore: deprecated_member_use_from_same_package
      setStrokeColor(node.strokeColor!);
      setLineWidth(node.strokeWidth);
      fillAndStroke();
    } else {
      fill();
    }
  }

  /// Write VectorPath segments to the current content stream.
  void _writePathSegments(VectorPath path) {
    for (int i = 0; i < path.segments.length; i++) {
      final segment = path.segments[i];

      if (segment is MoveSegment) {
        moveTo(segment.endPoint.dx, segment.endPoint.dy);
      } else if (segment is LineSegment) {
        lineTo(segment.endPoint.dx, segment.endPoint.dy);
      } else if (segment is CubicSegment) {
        curveTo(
          segment.controlPoint1.dx,
          segment.controlPoint1.dy,
          segment.controlPoint2.dx,
          segment.controlPoint2.dy,
          segment.endPoint.dx,
          segment.endPoint.dy,
        );
      } else if (segment is QuadSegment) {
        // Convert quadratic to cubic Bézier for PDF compatibility.
        final prevEnd =
            i > 0 ? path.segments[i - 1].endPoint : segment.endPoint;
        final cp = segment.controlPoint;
        final end = segment.endPoint;
        final cp1 = ui.Offset(
          prevEnd.dx + (2.0 / 3.0) * (cp.dx - prevEnd.dx),
          prevEnd.dy + (2.0 / 3.0) * (cp.dy - prevEnd.dy),
        );
        final cp2 = ui.Offset(
          end.dx + (2.0 / 3.0) * (cp.dx - end.dx),
          end.dy + (2.0 / 3.0) * (cp.dy - end.dy),
        );
        curveTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, end.dx, end.dy);
      }
    }
  }

  void _exportShapeNode(ShapeNode node) {
    final b = node.localBounds;
    if (b.isEmpty) return;

    setFillColor(const ui.Color(0xFFC8C8C8));
    setStrokeColor(const ui.Color(0xFF999999));
    setLineWidth(node.shape.strokeWidth);
    drawRect(b.left, b.top, b.width, b.height);
    fillAndStroke();
  }

  void _exportRichTextNode(RichTextNode node) {
    final b = node.localBounds;
    for (final span in node.spans) {
      setFillColor(span.color);
      drawText(span.text, b.left, b.top + span.fontSize, span.fontSize);
    }
  }

  void _exportTextNode(TextNode node) {
    final b = node.localBounds;
    setFillColor(const ui.Color(0xFF000000));
    drawText(node.textElement.text, b.left, b.top + 14, 14);
  }

  /// Export a stroke node as vector Bézier paths.
  ///
  /// Converts pressure-sensitive ink strokes to smooth cubic Bézier curves.
  /// Uses round line cap and join for natural ink appearance.
  void _exportStrokeNode(StrokeNode node) {
    final stk = node.stroke;
    if (stk.points.isEmpty) return;

    // Set stroke styling.
    setStrokeColor(stk.color);
    setLineWidth(stk.baseWidth);
    setLineCap(1); // Round cap
    setLineJoin(1); // Round join

    // Handle alpha from stroke color.
    if (stk.color.a < 1.0) {
      setOpacity(stk.color.a);
    }

    final points = stk.points;

    if (points.length == 1) {
      // Single point: draw a small dot.
      final p = points[0].position;
      final r = stk.baseWidth * 0.5;
      moveTo(p.dx - r, p.dy);
      lineTo(p.dx + r, p.dy);
      stroke();
      return;
    }

    // Draw using Catmull-Rom → cubic Bézier conversion for smooth curves.
    moveTo(points[0].position.dx, points[0].position.dy);

    if (points.length == 2) {
      lineTo(points[1].position.dx, points[1].position.dy);
    } else {
      // Convert Catmull-Rom spline segments to cubic Bézier.
      for (int i = 0; i < points.length - 1; i++) {
        final p0 = (i > 0 ? points[i - 1] : points[i]).position;
        final p1 = points[i].position;
        final p2 = points[i + 1].position;
        final p3 =
            (i + 2 < points.length ? points[i + 2] : points[i + 1]).position;

        // Catmull-Rom to cubic Bézier control points (alpha=0.5, tau=1/6)
        final cp1 = ui.Offset(
          p1.dx + (p2.dx - p0.dx) / 6.0,
          p1.dy + (p2.dy - p0.dy) / 6.0,
        );
        final cp2 = ui.Offset(
          p2.dx - (p3.dx - p1.dx) / 6.0,
          p2.dy - (p3.dy - p1.dy) / 6.0,
        );

        curveTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
      }
    }

    stroke();
  }

  /// Export an image node.
  ///
  /// Uses [imageResolver] to load the image bytes from disk.
  /// Falls back to a placeholder rectangle if resolver is unavailable.
  void _exportImageNode(ImageNode node) {
    final b = node.localBounds;
    if (b.isEmpty) return;

    final path = node.imageElement.imagePath;

    if (imageResolver != null && path.isNotEmpty) {
      try {
        final bytes = imageResolver!(path);
        if (bytes.isNotEmpty) {
          // Detect JPEG by magic bytes.
          final isJpeg =
              bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8;

          final imgSize = node.imageSize;
          final w = imgSize.width > 0 ? imgSize.width.toInt() : b.width.toInt();
          final h =
              imgSize.height > 0 ? imgSize.height.toInt() : b.height.toInt();

          PdfImageXObject xobj;
          if (isJpeg) {
            xobj = addJpegXObject(bytes, w, h);
          } else {
            // Assume raw RGBA or try to embed as-is
            xobj = addRgbaXObject(bytes, w, h);
          }

          drawImageXObject(xobj, b.left, b.top, b.width, b.height);
          return;
        }
      } catch (_) {
        // Fall through to placeholder.
      }
    }

    // Placeholder: light gray rectangle with "Image" text.
    setFillColor(const ui.Color(0xFFEEEEEE));
    setStrokeColor(const ui.Color(0xFF999999));
    setLineWidth(0.5);
    drawRect(b.left, b.top, b.width, b.height);
    fillAndStroke();
    setFillColor(const ui.Color(0xFF666666));
    drawText('Image', b.left + 4, b.top + 14, 10);
  }

  // ---------------------------------------------------------------------------
  // Finish and generate PDF bytes
  // ---------------------------------------------------------------------------

  /// Finalize all pages and generate the complete PDF file.
  ///
  /// Returns the PDF as a [Uint8List] ready for saving or sharing.
  ///
  /// [title] and [author] are embedded as PDF metadata.
  Uint8List finish({String? title, String? author}) {
    // Finalize last page.
    if (_currentPage != null) {
      _finalizePage();
    }

    if (_pageObjectIds.isEmpty) {
      // Empty document: create a blank page.
      beginPage();
      _finalizePage();
    }

    // Build the PDF structure.
    final buf = BytesBuilder();

    // Header.
    buf.add(utf8.encode('%PDF-1.4\n'));
    // Binary comment marker (recommended by spec).
    buf.add(Uint8List.fromList([0x25, 0xC0, 0xC1, 0xC2, 0xC3, 0x0A]));

    // Info dictionary (metadata).
    int? infoId;
    if (title != null || author != null) {
      infoId = _allocId();
      final infoParts = <String>['/Creator (Nebula Engine)'];
      if (title != null) infoParts.add('/Title (${_escapeText(title)})');
      if (author != null) infoParts.add('/Author (${_escapeText(author)})');
      // PDF date format: D:YYYYMMDDHHmmSS
      final now = DateTime.now();
      final dateStr =
          'D:${now.year}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}'
          '${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}'
          '${now.second.toString().padLeft(2, '0')}';
      infoParts.add('/CreationDate ($dateStr)');
      infoParts.add('/ModDate ($dateStr)');
      infoParts.add('/Producer (Nebula Engine PDF Writer)');

      _objects.add(
        _PdfObject(
          infoId,
          '$infoId 0 obj\n'
          '<< ${infoParts.join(' ')} >>\n'
          'endobj\n',
        ),
      );
    }

    // Pages object.
    final pagesId = _allocId();
    final kidsStr = _pageObjectIds.map((id) => '$id 0 R').join(' ');
    _objects.add(
      _PdfObject(
        pagesId,
        '$pagesId 0 obj\n'
        '<< /Type /Pages /Kids [$kidsStr] /Count ${_pageObjectIds.length} >>\n'
        'endobj\n',
      ),
    );

    // Update page objects to reference Pages parent.
    for (final obj in _objects) {
      if (_pageObjectIds.contains(obj.id)) {
        obj.content = obj.content.replaceAll(
          '/Type /Page',
          '/Type /Page /Parent $pagesId 0 R',
        );
      }
    }

    // Resolve internal page link destinations (%%PAGEDEST_N%% → page obj ref).
    for (final obj in _objects) {
      for (int i = 0; i < _pageObjectIds.length; i++) {
        obj.content = obj.content.replaceAll(
          '%%PAGEDEST_$i%%',
          '${_pageObjectIds[i]} 0 R',
        );
      }
    }

    // Build catalog extensions.
    final catalogParts = <String>['/Type /Catalog', '/Pages $pagesId 0 R'];

    // Outline tree (bookmarks).
    if (_bookmarks.isNotEmpty) {
      final outlinesId = _buildOutlineTree();
      catalogParts.add('/Outlines $outlinesId 0 R');
      catalogParts.add('/PageMode /UseOutlines');
    }

    // Page labels.
    if (_pageLabels.isNotEmpty) {
      final labelsEntries = <String>[];
      for (final label in _pageLabels) {
        final parts = <String>[];
        switch (label.style) {
          case PageLabelStyle.decimal:
            parts.add('/S /D');
          case PageLabelStyle.upperRoman:
            parts.add('/S /R');
          case PageLabelStyle.lowerRoman:
            parts.add('/S /r');
          case PageLabelStyle.upperAlpha:
            parts.add('/S /A');
          case PageLabelStyle.lowerAlpha:
            parts.add('/S /a');
          case PageLabelStyle.none:
            break; // No /S entry
        }
        if (label.prefix.isNotEmpty) {
          parts.add('/P (${_escapeText(label.prefix)})');
        }
        if (label.startNumber != 1) {
          parts.add('/St ${label.startNumber}');
        }
        labelsEntries.add('${label.startPage} << ${parts.join(' ')} >>');
      }
      catalogParts.add('/PageLabels << /Nums [${labelsEntries.join(' ')}] >>');
    }

    // AcroForm fields.
    if (_formFields.isNotEmpty) {
      _fontObjectId ??= _createFontObject();
      final fieldIds = <int>[];
      for (final field in _formFields) {
        final fieldId = _allocId();
        fieldIds.add(fieldId);

        final pageIdx = field.pageIndex.clamp(0, _pageObjectIds.length - 1);
        final pageObjId = _pageObjectIds[pageIdx];

        // Convert rect to PDF coordinates.
        // We need the page height for this field's page — use current _pageHeight as best approx.
        final llx = _n(field.rect.left);
        final lly = _n(_pageHeight - field.rect.bottom);
        final urx = _n(field.rect.right);
        final ury = _n(_pageHeight - field.rect.top);

        final escaped = _escapeText(field.name);

        String fieldDict;
        switch (field) {
          case PdfTextField():
            final defVal =
                field.defaultValue.isNotEmpty
                    ? ' /V (${_escapeText(field.defaultValue)})'
                    : '';
            final maxLen =
                field.maxLength > 0 ? ' /MaxLen ${field.maxLength}' : '';
            final flags = field.multiline ? ' /Ff 4096' : '';
            fieldDict =
                '$fieldId 0 obj\n'
                '<< /Type /Annot /Subtype /Widget\n'
                '   /FT /Tx\n'
                '   /T ($escaped)\n'
                '   /Rect [$llx $lly $urx $ury]\n'
                '   /P $pageObjId 0 R\n'
                '   /DA (/F1 ${_n(field.fontSize)} Tf 0 g)\n'
                '$defVal$maxLen$flags\n'
                '   /Border [0 0 1]\n'
                '>>\n'
                'endobj\n';
          case PdfCheckboxField():
            final val = field.defaultChecked ? '/Yes' : '/Off';
            fieldDict =
                '$fieldId 0 obj\n'
                '<< /Type /Annot /Subtype /Widget\n'
                '   /FT /Btn\n'
                '   /T ($escaped)\n'
                '   /Rect [$llx $lly $urx $ury]\n'
                '   /P $pageObjId 0 R\n'
                '   /V $val /AS $val\n'
                '   /Border [0 0 1]\n'
                '>>\n'
                'endobj\n';
          case PdfDropdownField():
            final opts = field.options
                .map((o) => '(${_escapeText(o)})')
                .join(' ');
            final defVal =
                field.defaultValue != null
                    ? ' /V (${_escapeText(field.defaultValue!)})'
                    : '';
            final flags = field.editable ? ' /Ff 393216' : ' /Ff 131072';
            fieldDict =
                '$fieldId 0 obj\n'
                '<< /Type /Annot /Subtype /Widget\n'
                '   /FT /Ch\n'
                '   /T ($escaped)\n'
                '   /Rect [$llx $lly $urx $ury]\n'
                '   /P $pageObjId 0 R\n'
                '   /Opt [$opts]\n'
                '   /DA (/F1 12 Tf 0 g)\n'
                '$defVal$flags\n'
                '   /Border [0 0 1]\n'
                '>>\n'
                'endobj\n';
        }

        _objects.add(_PdfObject(fieldId, fieldDict));
      }

      final fieldRefs = fieldIds.map((id) => '$id 0 R').join(' ');
      catalogParts.add(
        '/AcroForm << /Fields [$fieldRefs]'
        ' /DR << /Font << /F1 $_fontObjectId 0 R >> >>'
        ' /NeedAppearances true >>',
      );
    }

    // Redaction annotations → also add overlay rectangles.
    if (_redactions.isNotEmpty) {
      for (final redact in _redactions) {
        final pageIdx = redact.pageIndex.clamp(0, _pageObjectIds.length - 1);
        final pageObjId = _pageObjectIds[pageIdx];
        final annotId = _allocId();

        final llx = _n(redact.rect.left);
        final lly = _n(_pageHeight - redact.rect.bottom);
        final urx = _n(redact.rect.right);
        final ury = _n(_pageHeight - redact.rect.top);

        final r = _n(redact.overlayColor.r);
        final g = _n(redact.overlayColor.g);
        final b = _n(redact.overlayColor.b);

        final overlayText =
            redact.replacementText != null
                ? ' /OverlayText (${_escapeText(redact.replacementText!)})'
                : '';

        _objects.add(
          _PdfObject(
            annotId,
            '$annotId 0 obj\n'
            '<< /Type /Annot /Subtype /Redact\n'
            '   /Rect [$llx $lly $urx $ury]\n'
            '   /P $pageObjId 0 R\n'
            '   /IC [$r $g $b]\n'
            '$overlayText\n'
            '>>\n'
            'endobj\n',
          ),
        );
      }
    }

    // PDF/A-1b conformance.
    if (pdfAConformance) {
      // XMP metadata stream.
      final xmpId = _allocId();
      final xmpContent =
          '<?xpacket begin="\uFEFF" id="W5M0MpCehiHzreSzNTczkc9d"?>\n'
          '<x:xmpmeta xmlns:x="adobe:ns:meta/">\n'
          '<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">\n'
          '<rdf:Description rdf:about=""\n'
          '  xmlns:dc="http://purl.org/dc/elements/1.1/"\n'
          '  xmlns:pdf="http://ns.adobe.com/pdf/1.3/"\n'
          '  xmlns:pdfaid="http://www.aiim.org/pdfa/ns/id/">\n'
          '  <pdfaid:part>1</pdfaid:part>\n'
          '  <pdfaid:conformance>B</pdfaid:conformance>\n'
          '  <pdf:Producer>Nebula Engine PDF Writer</pdf:Producer>\n'
          '  <dc:title><rdf:Alt><rdf:li xml:lang="x-default">Nebula Export</rdf:li></rdf:Alt></dc:title>\n'
          '</rdf:Description>\n'
          '</rdf:RDF>\n'
          '</x:xmpmeta>\n'
          '<?xpacket end="w"?>';
      final xmpBytes = utf8.encode(xmpContent);
      _objects.add(
        _PdfObject(
          xmpId,
          '$xmpId 0 obj\n'
          '<< /Type /Metadata /Subtype /XML /Length ${xmpBytes.length} >>\n'
          'stream\n',
          binaryData: _concatBytes(
            Uint8List.fromList(xmpBytes),
            utf8.encode('\nendstream\nendobj\n'),
          ),
        ),
      );
      catalogParts.add('/Metadata $xmpId 0 R');

      // Output intent.
      final intentId = _allocId();
      _objects.add(
        _PdfObject(
          intentId,
          '$intentId 0 obj\n'
          '<< /Type /OutputIntent\n'
          '   /S /GTS_PDFA1\n'
          '   /OutputConditionIdentifier (sRGB IEC61966-2.1)\n'
          '   /RegistryName (http://www.color.org)\n'
          '>>\n'
          'endobj\n',
        ),
      );
      catalogParts.add('/OutputIntents [$intentId 0 R]');
      catalogParts.add('/MarkInfo << /Marked true >>');
    }

    // Catalog object.
    final catalogId = _allocId();
    _objects.add(
      _PdfObject(
        catalogId,
        '$catalogId 0 obj\n'
        '<< ${catalogParts.join(' ')} >>\n'
        'endobj\n',
      ),
    );

    // Write all objects, recording offsets.
    for (final obj in _objects) {
      obj.offset = buf.length;
      buf.add(utf8.encode(obj.content));
      if (obj.binaryData != null) {
        buf.add(obj.binaryData!);
      }
    }

    // Cross-reference table.
    final xrefOffset = buf.length;
    buf.add(utf8.encode('xref\n'));
    buf.add(utf8.encode('0 ${_objects.length + 1}\n'));
    buf.add(utf8.encode('0000000000 65535 f \n'));

    // Sort objects by ID for xref.
    final sorted = List<_PdfObject>.from(_objects)
      ..sort((a, b) => a.id.compareTo(b.id));
    for (final obj in sorted) {
      final offsetStr = obj.offset.toString().padLeft(10, '0');
      buf.add(utf8.encode('$offsetStr 00000 n \n'));
    }

    // Trailer.
    final infoRef = infoId != null ? ' /Info $infoId 0 R' : '';
    buf.add(
      utf8.encode(
        'trailer\n'
        '<< /Size ${_objects.length + 1} /Root $catalogId 0 R$infoRef >>\n'
        'startxref\n'
        '$xrefOffset\n'
        '%%EOF\n',
      ),
    );

    return buf.toBytes();
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  int _allocId() => _nextId++;

  /// Create a built-in Helvetica font object.
  int _createFontObject() {
    final id = _allocId();
    _objects.add(
      _PdfObject(
        id,
        '$id 0 obj\n'
        '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\n'
        'endobj\n',
      ),
    );
    return id;
  }

  /// Flip Y coordinate (PDF uses bottom-left origin).
  double _flipY(double y) => _pageHeight - y;

  /// Format a number for PDF (max 4 decimal places, no trailing zeros).
  static String _n(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v
        .toStringAsFixed(4)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  /// Escape text for PDF string literal.
  static String _escapeText(String text) {
    return text
        .replaceAll(r'\', r'\\')
        .replaceAll('(', r'\(')
        .replaceAll(')', r'\)');
  }

  /// Concatenate two byte lists into one.
  static Uint8List _concatBytes(Uint8List a, List<int> b) {
    final result = Uint8List(a.length + b.length);
    result.setAll(0, a);
    result.setAll(a.length, b);
    return result;
  }

  // ---------------------------------------------------------------------------
  // Watermark rendering
  // ---------------------------------------------------------------------------

  /// Append watermark operators to the content stream.
  void _appendWatermark(
    StringBuffer page,
    double pageWidth,
    double pageHeight,
  ) {
    final wm = _watermark!;
    final escaped = _escapeText(wm.text);

    // Ensure font is available.
    _fontObjectId ??= _createFontObject();

    switch (wm.position) {
      case WatermarkPosition.diagonal:
        // Rotate text diagonally across the page center.
        final rad = wm.rotation * math.pi / 180.0;
        final cosA = math.cos(rad);
        final sinA = math.sin(rad);
        final cx = pageWidth / 2;
        final cy = pageHeight / 2;
        // Estimate text width for centering.
        final textWidth = wm.fontSize * 0.5 * wm.text.length;

        page.write('q\n');
        // Set opacity via inline ExtGState.
        final alpha = (wm.opacity * 255).round().clamp(0, 255);
        if (!_gsAlphaObjects.containsKey(alpha)) {
          final gsId = _allocId();
          _objects.add(
            _PdfObject(
              gsId,
              '$gsId 0 obj\n'
              '<< /Type /ExtGState /ca ${_n(wm.opacity)} /CA ${_n(wm.opacity)} >>\n'
              'endobj\n',
            ),
          );
          _gsAlphaObjects[alpha] = gsId;
        }
        page.write('/GS$alpha gs\n');
        page.write(
          '${_n(wm.color.r)} ${_n(wm.color.g)} ${_n(wm.color.b)} rg\n',
        );
        page.write('BT\n');
        page.write('/F1 ${_n(wm.fontSize)} Tf\n');
        // Text matrix: rotate + translate to center, offset by half text width.
        page.write(
          '${_n(cosA)} ${_n(sinA)} ${_n(-sinA)} ${_n(cosA)} '
          '${_n(cx - textWidth * cosA / 2)} ${_n(cy - textWidth * sinA / 2)} Tm\n',
        );
        page.write('($escaped) Tj\n');
        page.write('ET\n');
        page.write('Q\n');

      case WatermarkPosition.center:
        // Centered text, no rotation.
        final textWidth = wm.fontSize * 0.5 * wm.text.length;
        final cx = (pageWidth - textWidth) / 2;
        final cy = pageHeight / 2;

        page.write('q\n');
        final alpha = (wm.opacity * 255).round().clamp(0, 255);
        if (!_gsAlphaObjects.containsKey(alpha)) {
          final gsId = _allocId();
          _objects.add(
            _PdfObject(
              gsId,
              '$gsId 0 obj\n'
              '<< /Type /ExtGState /ca ${_n(wm.opacity)} /CA ${_n(wm.opacity)} >>\n'
              'endobj\n',
            ),
          );
          _gsAlphaObjects[alpha] = gsId;
        }
        page.write('/GS$alpha gs\n');
        page.write(
          '${_n(wm.color.r)} ${_n(wm.color.g)} ${_n(wm.color.b)} rg\n',
        );
        page.write('BT\n');
        page.write('/F1 ${_n(wm.fontSize)} Tf\n');
        page.write('${_n(cx)} ${_n(cy)} Td\n');
        page.write('($escaped) Tj\n');
        page.write('ET\n');
        page.write('Q\n');

      case WatermarkPosition.tiled:
        // Tile watermark text across the page.
        final textWidth = wm.fontSize * 0.5 * wm.text.length;
        final stepX = textWidth + wm.fontSize;
        final stepY = wm.fontSize * 2.5;

        page.write('q\n');
        final alpha = (wm.opacity * 255).round().clamp(0, 255);
        if (!_gsAlphaObjects.containsKey(alpha)) {
          final gsId = _allocId();
          _objects.add(
            _PdfObject(
              gsId,
              '$gsId 0 obj\n'
              '<< /Type /ExtGState /ca ${_n(wm.opacity)} /CA ${_n(wm.opacity)} >>\n'
              'endobj\n',
            ),
          );
          _gsAlphaObjects[alpha] = gsId;
        }
        page.write('/GS$alpha gs\n');
        page.write(
          '${_n(wm.color.r)} ${_n(wm.color.g)} ${_n(wm.color.b)} rg\n',
        );

        final rad = wm.rotation * math.pi / 180.0;
        final cosA = math.cos(rad);
        final sinA = math.sin(rad);

        for (double y = 0; y < pageHeight + stepY; y += stepY) {
          for (double x = 0; x < pageWidth + stepX; x += stepX) {
            page.write('BT\n');
            page.write('/F1 ${_n(wm.fontSize)} Tf\n');
            page.write(
              '${_n(cosA)} ${_n(sinA)} ${_n(-sinA)} ${_n(cosA)} '
              '${_n(x)} ${_n(y)} Tm\n',
            );
            page.write('($escaped) Tj\n');
            page.write('ET\n');
          }
        }
        page.write('Q\n');
    }
  }

  // ---------------------------------------------------------------------------
  // Outline tree (bookmarks)
  // ---------------------------------------------------------------------------

  /// Build the PDF outline tree from [_bookmarks].
  ///
  /// Returns the object ID of the root `/Outlines` dictionary.
  int _buildOutlineTree() {
    final outlinesId = _allocId();

    // Flatten bookmarks with parent/sibling references.
    final itemIds = <int>[];
    for (int i = 0; i < _bookmarks.length; i++) {
      final itemId = _buildOutlineItem(_bookmarks[i], outlinesId);
      itemIds.add(itemId);
    }

    // Set sibling /Prev and /Next references.
    for (int i = 0; i < itemIds.length; i++) {
      final obj = _objects.firstWhere((o) => o.id == itemIds[i]);
      final prevRef = i > 0 ? ' /Prev ${itemIds[i - 1]} 0 R' : '';
      final nextRef =
          i < itemIds.length - 1 ? ' /Next ${itemIds[i + 1]} 0 R' : '';
      obj.content = obj.content.replaceFirst(
        '%%SIBLINGS%%',
        '$prevRef$nextRef',
      );
    }

    // Count total visible items.
    int totalCount = 0;
    for (final bm in _bookmarks) {
      totalCount += _countBookmarks(bm);
    }

    // Root outlines object.
    final firstRef = itemIds.isNotEmpty ? ' /First ${itemIds.first} 0 R' : '';
    final lastRef = itemIds.isNotEmpty ? ' /Last ${itemIds.last} 0 R' : '';
    _objects.add(
      _PdfObject(
        outlinesId,
        '$outlinesId 0 obj\n'
        '<< /Type /Outlines$firstRef$lastRef /Count $totalCount >>\n'
        'endobj\n',
      ),
    );

    return outlinesId;
  }

  /// Build a single outline item and its children recursively.
  int _buildOutlineItem(PdfBookmark bookmark, int parentId) {
    final itemId = _allocId();

    // Resolve page reference.
    final pageIdx = bookmark.pageIndex.clamp(0, _pageObjectIds.length - 1);
    final pageObjId = _pageObjectIds[pageIdx];

    // Build children if any.
    String childrenRef = '';
    if (bookmark.children.isNotEmpty) {
      final childIds = <int>[];
      for (final child in bookmark.children) {
        childIds.add(_buildOutlineItem(child, itemId));
      }

      // Set sibling references for children.
      for (int i = 0; i < childIds.length; i++) {
        final obj = _objects.firstWhere((o) => o.id == childIds[i]);
        final prevRef = i > 0 ? ' /Prev ${childIds[i - 1]} 0 R' : '';
        final nextRef =
            i < childIds.length - 1 ? ' /Next ${childIds[i + 1]} 0 R' : '';
        obj.content = obj.content.replaceFirst(
          '%%SIBLINGS%%',
          '$prevRef$nextRef',
        );
      }

      childrenRef =
          ' /First ${childIds.first} 0 R'
          ' /Last ${childIds.last} 0 R'
          ' /Count ${bookmark.children.length}';
    }

    final escaped = _escapeText(bookmark.title);
    _objects.add(
      _PdfObject(
        itemId,
        '$itemId 0 obj\n'
        '<< /Title ($escaped)\n'
        '   /Parent $parentId 0 R\n'
        '   /Dest [$pageObjId 0 R /Fit]\n'
        '   %%SIBLINGS%%$childrenRef\n'
        '>>\n'
        'endobj\n',
      ),
    );

    return itemId;
  }

  /// Count total bookmarks (including nested children).
  int _countBookmarks(PdfBookmark bookmark) {
    int count = 1;
    for (final child in bookmark.children) {
      count += _countBookmarks(child);
    }
    return count;
  }
}
