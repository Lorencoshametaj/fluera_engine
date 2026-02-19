/// 📐 Layout presets for PDF document grid.
///
/// Each preset defines a column count, spacing, and behavior
/// for how pages are arranged on the canvas.
enum PdfLayoutPreset {
  /// 📖 Reading mode — 1 column, tight spacing. Continuous vertical scroll.
  reading,

  /// 📄 Standard — 2 columns (default). Good balance of overview and detail.
  standard,

  /// 📊 Overview — 3-4 columns. See many pages at once for navigation.
  overview,

  /// 🖼️ Freeform — All pages unlocked, drag anywhere.
  freeform,

  /// 📑 Single page — Focus view. Only 1 column, wide spacing.
  single,
}

/// Extension methods for [PdfLayoutPreset] configuration.
extension PdfLayoutPresetConfig on PdfLayoutPreset {
  /// Number of grid columns for this preset.
  int get columns {
    switch (this) {
      case PdfLayoutPreset.reading:
        return 1;
      case PdfLayoutPreset.standard:
        return 2;
      case PdfLayoutPreset.overview:
        return 4;
      case PdfLayoutPreset.freeform:
        return 1; // Not used in freeform
      case PdfLayoutPreset.single:
        return 1;
    }
  }

  /// Spacing between pages in logical pixels.
  double get spacing {
    switch (this) {
      case PdfLayoutPreset.reading:
        return 12.0;
      case PdfLayoutPreset.standard:
        return 20.0;
      case PdfLayoutPreset.overview:
        return 16.0;
      case PdfLayoutPreset.freeform:
        return 0.0;
      case PdfLayoutPreset.single:
        return 80.0;
    }
  }

  /// Whether pages should be locked in the grid.
  bool get locksPages => this != PdfLayoutPreset.freeform;

  /// Display icon for UI.
  String get icon {
    switch (this) {
      case PdfLayoutPreset.reading:
        return '📖';
      case PdfLayoutPreset.standard:
        return '📄';
      case PdfLayoutPreset.overview:
        return '📊';
      case PdfLayoutPreset.freeform:
        return '🖼️';
      case PdfLayoutPreset.single:
        return '📑';
    }
  }

  /// Display label for UI.
  String get label {
    switch (this) {
      case PdfLayoutPreset.reading:
        return 'Reading';
      case PdfLayoutPreset.standard:
        return 'Standard';
      case PdfLayoutPreset.overview:
        return 'Overview';
      case PdfLayoutPreset.freeform:
        return 'Freeform';
      case PdfLayoutPreset.single:
        return 'Single';
    }
  }
}
