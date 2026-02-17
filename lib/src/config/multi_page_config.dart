import 'dart:ui';

import '../export/export_preset.dart';

/// Modalità di editing multi-pagina
enum MultiPageMode {
  /// All pages have the same size
  uniform,

  /// Each pagina can avere size diversa
  individual,
}

/// Configuretion for multi-page export with interactive editing
class MultiPageConfig {
  /// Modalità di editing (uniform o individual)
  final MultiPageMode mode;

  /// Page format for uniform mode (A4, A3, Letter, custom)
  final ExportPageFormat pageFormat;

  /// Custom size for uniform mode (used if pageFormat == custom)
  final Size? customPageSize;

  /// Size uniforme of pages in canvas coordinates (per mode uniform)
  final Size? uniformPageSize;

  /// Individual bounds for each page in canvas coordinates (for individual mode)
  final List<Rect> individualPageBounds;

  /// Maximum number di pagine consentite
  final int maxPages;

  /// Index of the currently selected page for editing
  final int selectedPageIndex;

  /// Quality di export (influenza DPI)
  final ExportQuality quality;

  const MultiPageConfig({
    this.mode = MultiPageMode.uniform,
    this.pageFormat = ExportPageFormat.a4Portrait,
    this.customPageSize,
    this.uniformPageSize,
    this.individualPageBounds = const [],
    this.maxPages = 20,
    this.selectedPageIndex = 0,
    this.quality = ExportQuality.high,
  });

  /// Creates a copy with modified values
  MultiPageConfig copyWith({
    MultiPageMode? mode,
    ExportPageFormat? pageFormat,
    Size? customPageSize,
    Size? uniformPageSize,
    List<Rect>? individualPageBounds,
    int? maxPages,
    int? selectedPageIndex,
    ExportQuality? quality,
  }) {
    return MultiPageConfig(
      mode: mode ?? this.mode,
      pageFormat: pageFormat ?? this.pageFormat,
      customPageSize: customPageSize ?? this.customPageSize,
      uniformPageSize: uniformPageSize ?? this.uniformPageSize,
      individualPageBounds: individualPageBounds ?? this.individualPageBounds,
      maxPages: maxPages ?? this.maxPages,
      selectedPageIndex: selectedPageIndex ?? this.selectedPageIndex,
      quality: quality ?? this.quality,
    );
  }

  /// Gets the size of the page in points (72 DPI base)
  Size getPageSizeInPoints() {
    if (pageFormat == ExportPageFormat.custom && customPageSize != null) {
      return customPageSize!;
    }
    return pageFormat.sizeInPoints;
  }

  /// Gets the size of the page in pixels for the specified quality
  Size getPageSizeInPixels() {
    final sizeInPoints = getPageSizeInPoints();
    final dpi = quality.dpi;
    final scale = dpi / 72.0;
    return Size(sizeInPoints.width * scale, sizeInPoints.height * scale);
  }

  /// Numero totale di pagine
  int get pageCount {
    if (mode == MultiPageMode.individual) {
      return individualPageBounds.length;
    }
    // For uniform, calcolato based onll'area e size pagina
    return individualPageBounds.length;
  }

  /// Checks if it is possible to add more pages
  bool get canAddPage => pageCount < maxPages;

  /// Checks if it is possible to remove pages
  bool get canRemovePage => pageCount > 1;

  /// Serialize in JSON
  Map<String, dynamic> toJson() {
    return {
      'mode': mode.index,
      'pageFormat': pageFormat.index,
      'customPageSize':
          customPageSize != null
              ? {
                'width': customPageSize!.width,
                'height': customPageSize!.height,
              }
              : null,
      'uniformPageSize':
          uniformPageSize != null
              ? {
                'width': uniformPageSize!.width,
                'height': uniformPageSize!.height,
              }
              : null,
      'individualPageBounds':
          individualPageBounds
              .map(
                (r) => {
                  'left': r.left,
                  'top': r.top,
                  'width': r.width,
                  'height': r.height,
                },
              )
              .toList(),
      'maxPages': maxPages,
      'selectedPageIndex': selectedPageIndex,
      'quality': quality.index,
    };
  }

  /// Deserializza da JSON
  factory MultiPageConfig.fromJson(Map<String, dynamic> json) {
    return MultiPageConfig(
      mode: MultiPageMode.values[json['mode'] as int? ?? 0],
      pageFormat: ExportPageFormat.values[json['pageFormat'] as int? ?? 0],
      customPageSize:
          json['customPageSize'] != null
              ? Size(
                (json['customPageSize']['width'] as num).toDouble(),
                (json['customPageSize']['height'] as num).toDouble(),
              )
              : null,
      uniformPageSize:
          json['uniformPageSize'] != null
              ? Size(
                (json['uniformPageSize']['width'] as num).toDouble(),
                (json['uniformPageSize']['height'] as num).toDouble(),
              )
              : null,
      individualPageBounds:
          (json['individualPageBounds'] as List<dynamic>?)
              ?.map(
                (r) => Rect.fromLTWH(
                  (r['left'] as num).toDouble(),
                  (r['top'] as num).toDouble(),
                  (r['width'] as num).toDouble(),
                  (r['height'] as num).toDouble(),
                ),
              )
              .toList() ??
          [],
      maxPages: json['maxPages'] as int? ?? 20,
      selectedPageIndex: json['selectedPageIndex'] as int? ?? 0,
      quality: ExportQuality.values[json['quality'] as int? ?? 2],
    );
  }

  /// Creates una configurazione iniziale with aa singola pagina centrata
  factory MultiPageConfig.initial({
    required Rect canvasArea,
    MultiPageMode mode = MultiPageMode.uniform,
    ExportPageFormat pageFormat = ExportPageFormat.a4Portrait,
    ExportQuality quality = ExportQuality.high,
    int maxPages = 20,
  }) {
    // Calculate page size in canvas coordinates
    // We use a scale factor to make the page visible on the canvas
    final pageSizeInPoints = pageFormat.sizeInPoints;
    final aspectRatio = pageSizeInPoints.width / pageSizeInPoints.height;

    // Initial page size on the canvas (approximately 1/4 of the area)
    final targetHeight = canvasArea.height * 0.4;
    final targetWidth = targetHeight * aspectRatio;

    final pageSize = Size(targetWidth, targetHeight);

    // Center the first page in the canvas area
    final firstPageRect = Rect.fromCenter(
      center: canvasArea.center,
      width: pageSize.width,
      height: pageSize.height,
    );

    return MultiPageConfig(
      mode: mode,
      pageFormat: pageFormat,
      uniformPageSize: pageSize,
      individualPageBounds: [firstPageRect],
      maxPages: maxPages,
      selectedPageIndex: 0,
      quality: quality,
    );
  }

  /// Adds a new page to the configuration
  MultiPageConfig addPage(Rect canvasArea) {
    if (!canAddPage) return this;

    final newBounds = List<Rect>.from(individualPageBounds);

    if (mode == MultiPageMode.uniform && uniformPageSize != null) {
      // Calculate position for the nuova pagina (griglia)
      final cols = (canvasArea.width / uniformPageSize!.width).floor().clamp(
        1,
        10,
      );
      final pageIndex = newBounds.length;
      final row = pageIndex ~/ cols;
      final col = pageIndex % cols;

      final spacing = 20.0; // Spacing between pages
      final newRect = Rect.fromLTWH(
        canvasArea.left + col * (uniformPageSize!.width + spacing),
        canvasArea.top + row * (uniformPageSize!.height + spacing),
        uniformPageSize!.width,
        uniformPageSize!.height,
      );
      newBounds.add(newRect);
    } else {
      // Individual mode: add page with default size
      final lastRect =
          newBounds.isNotEmpty
              ? newBounds.last
              : Rect.fromLTWH(
                canvasArea.left + 50,
                canvasArea.top + 50,
                200,
                280,
              );

      // Offset the new page relative to the last one
      final newRect = lastRect.translate(50, 50);
      newBounds.add(newRect);
    }

    return copyWith(
      individualPageBounds: newBounds,
      selectedPageIndex: newBounds.length - 1,
    );
  }

  /// Adds a new page centered at the specified point (in canvas coordinates)
  MultiPageConfig addPageAtCenter(Offset center) {
    if (!canAddPage) return this;

    // Determines the size of the new page
    final Size pageSize;
    if (mode == MultiPageMode.uniform && uniformPageSize != null) {
      pageSize = uniformPageSize!;
    } else if (individualPageBounds.isNotEmpty) {
      // Use the size of the last page
      final lastPage = individualPageBounds.last;
      pageSize = Size(lastPage.width, lastPage.height);
    } else {
      // Default: size standard A4 portrait
      pageSize = const Size(210, 297);
    }

    // Create centered rect
    final newRect = Rect.fromCenter(
      center: center,
      width: pageSize.width,
      height: pageSize.height,
    );

    final newBounds = List<Rect>.from(individualPageBounds)..add(newRect);

    return copyWith(
      individualPageBounds: newBounds,
      selectedPageIndex: newBounds.length - 1,
    );
  }

  /// Removes the selected page
  MultiPageConfig removeSelectedPage() {
    if (!canRemovePage) return this;

    final newBounds = List<Rect>.from(individualPageBounds);
    newBounds.removeAt(selectedPageIndex);

    final newSelectedIndex =
        selectedPageIndex >= newBounds.length
            ? newBounds.length - 1
            : selectedPageIndex;

    return copyWith(
      individualPageBounds: newBounds,
      selectedPageIndex: newSelectedIndex,
    );
  }

  /// Updates the bounds of a specific page
  MultiPageConfig updatePageBounds(int index, Rect newBounds) {
    if (index < 0 || index >= individualPageBounds.length) return this;

    final updatedBounds = List<Rect>.from(individualPageBounds);
    updatedBounds[index] = newBounds;

    // In uniform mode, updates the uniform size
    Size? newUniformSize = uniformPageSize;
    if (mode == MultiPageMode.uniform) {
      newUniformSize = Size(newBounds.width, newBounds.height);
      // Update all pages with the new size while maintaining positions
      for (int i = 0; i < updatedBounds.length; i++) {
        if (i != index) {
          final oldRect = updatedBounds[i];
          updatedBounds[i] = Rect.fromLTWH(
            oldRect.left,
            oldRect.top,
            newUniformSize.width,
            newUniformSize.height,
          );
        }
      }
    }

    return copyWith(
      individualPageBounds: updatedBounds,
      uniformPageSize: newUniformSize,
    );
  }

  /// Sposta una specific page
  MultiPageConfig movePage(int index, Offset delta) {
    if (index < 0 || index >= individualPageBounds.length) return this;

    final updatedBounds = List<Rect>.from(individualPageBounds);
    updatedBounds[index] = updatedBounds[index].translate(delta.dx, delta.dy);

    return copyWith(individualPageBounds: updatedBounds);
  }

  /// Riorganizza le pagine in una griglia ordinata
  MultiPageConfig reorganizeAsGrid(
    Rect canvasArea, {
    int columns = 2,
    double spacing = 20,
  }) {
    if (individualPageBounds.isEmpty) return this;

    final pageSize =
        mode == MultiPageMode.uniform && uniformPageSize != null
            ? uniformPageSize!
            : Size(
              individualPageBounds.first.width,
              individualPageBounds.first.height,
            );

    final newBounds = <Rect>[];

    for (int i = 0; i < individualPageBounds.length; i++) {
      final row = i ~/ columns;
      final col = i % columns;

      final rect = Rect.fromLTWH(
        canvasArea.left + col * (pageSize.width + spacing) + spacing,
        canvasArea.top + row * (pageSize.height + spacing) + spacing,
        pageSize.width,
        pageSize.height,
      );
      newBounds.add(rect);
    }

    return copyWith(individualPageBounds: newBounds);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! MultiPageConfig) return false;

    return mode == other.mode &&
        pageFormat == other.pageFormat &&
        customPageSize == other.customPageSize &&
        uniformPageSize == other.uniformPageSize &&
        maxPages == other.maxPages &&
        selectedPageIndex == other.selectedPageIndex &&
        quality == other.quality &&
        _listEquals(individualPageBounds, other.individualPageBounds);
  }

  bool _listEquals(List<Rect> a, List<Rect> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    mode,
    pageFormat,
    customPageSize,
    uniformPageSize,
    maxPages,
    selectedPageIndex,
    quality,
    Object.hashAll(individualPageBounds),
  );
}
