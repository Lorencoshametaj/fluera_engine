/// 🎨 COLOR PALETTE STORE — Global palette management with swatches.
///
/// Named color swatches organized into palettes for design system management.
/// Supports CRUD, built-in presets, and JSON export/import for sharing.
///
/// ```dart
/// final store = ColorPaletteStore();
/// store.addPalette(ColorPalette.material());
///
/// final swatch = store.findSwatch('Blue 500');
/// ```
library;

// =============================================================================
// COLOR SWATCH
// =============================================================================

/// A named color with optional metadata.
class ColorSwatch {
  /// Unique display name (e.g. "Ocean Blue").
  final String name;

  /// sRGB red (0–1).
  final double r;

  /// sRGB green (0–1).
  final double g;

  /// sRGB blue (0–1).
  final double b;

  /// Alpha (0–1).
  final double a;

  /// Optional description.
  final String? description;

  /// Optional hex code override (for display).
  final String? hexCode;

  const ColorSwatch({
    required this.name,
    required this.r,
    required this.g,
    required this.b,
    this.a = 1.0,
    this.description,
    this.hexCode,
  });

  /// Create from 8-bit RGB values (0–255).
  factory ColorSwatch.fromRgb255(String name, int r, int g, int b) =>
      ColorSwatch(name: name, r: r / 255.0, g: g / 255.0, b: b / 255.0);

  /// Create from hex string (e.g. "#FF5722" or "FF5722").
  factory ColorSwatch.fromHex(String name, String hex) {
    final clean = hex.replaceFirst('#', '');
    final value = int.parse(clean, radix: 16);
    final hasAlpha = clean.length == 8;

    return ColorSwatch(
      name: name,
      r: ((hasAlpha ? (value >> 16) & 0xFF : (value >> 16) & 0xFF)) / 255.0,
      g: ((hasAlpha ? (value >> 8) & 0xFF : (value >> 8) & 0xFF)) / 255.0,
      b: ((hasAlpha ? value & 0xFF : value & 0xFF)) / 255.0,
      a: hasAlpha ? ((value >> 24) & 0xFF) / 255.0 : 1.0,
      hexCode: '#$clean',
    );
  }

  /// Get hex code string.
  String toHex() {
    if (hexCode != null) return hexCode!;
    final ri = (r * 255).round().clamp(0, 255);
    final gi = (g * 255).round().clamp(0, 255);
    final bi = (b * 255).round().clamp(0, 255);
    return '#${ri.toRadixString(16).padLeft(2, '0')}'
            '${gi.toRadixString(16).padLeft(2, '0')}'
            '${bi.toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'r': r,
    'g': g,
    'b': b,
    'a': a,
    if (description != null) 'description': description,
    if (hexCode != null) 'hexCode': hexCode,
  };

  factory ColorSwatch.fromJson(Map<String, dynamic> json) => ColorSwatch(
    name: json['name'] as String,
    r: (json['r'] as num).toDouble(),
    g: (json['g'] as num).toDouble(),
    b: (json['b'] as num).toDouble(),
    a: (json['a'] as num?)?.toDouble() ?? 1.0,
    description: json['description'] as String?,
    hexCode: json['hexCode'] as String?,
  );

  @override
  String toString() => 'ColorSwatch($name, ${toHex()})';
}

// =============================================================================
// COLOR PALETTE
// =============================================================================

/// An ordered collection of color swatches.
class ColorPalette {
  /// Palette identifier.
  final String id;

  /// Human-readable name.
  final String name;

  /// Optional description.
  final String? description;

  /// Ordered swatches.
  final List<ColorSwatch> swatches;

  ColorPalette({
    required this.id,
    required this.name,
    this.description,
    List<ColorSwatch>? swatches,
  }) : swatches = swatches ?? [];

  /// Number of swatches.
  int get count => swatches.length;

  /// Find a swatch by name (case-insensitive).
  ColorSwatch? findByName(String name) {
    final lower = name.toLowerCase();
    for (final s in swatches) {
      if (s.name.toLowerCase() == lower) return s;
    }
    return null;
  }

  /// Add a swatch to the palette.
  void add(ColorSwatch swatch) => swatches.add(swatch);

  /// Remove a swatch by name. Returns true if removed.
  bool remove(String name) {
    final before = swatches.length;
    swatches.removeWhere((s) => s.name == name);
    return swatches.length < before;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (description != null) 'description': description,
    'swatches': swatches.map((s) => s.toJson()).toList(),
  };

  factory ColorPalette.fromJson(Map<String, dynamic> json) => ColorPalette(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    swatches:
        (json['swatches'] as List)
            .map((s) => ColorSwatch.fromJson(s as Map<String, dynamic>))
            .toList(),
  );

  // ===========================================================================
  // BUILT-IN PRESETS
  // ===========================================================================

  /// Material Design primary colors.
  static ColorPalette material() => ColorPalette(
    id: 'material',
    name: 'Material Design',
    description: 'Google Material Design primary palette',
    swatches: [
      ColorSwatch.fromHex('Red', 'F44336'),
      ColorSwatch.fromHex('Pink', 'E91E63'),
      ColorSwatch.fromHex('Purple', '9C27B0'),
      ColorSwatch.fromHex('Deep Purple', '673AB7'),
      ColorSwatch.fromHex('Indigo', '3F51B5'),
      ColorSwatch.fromHex('Blue', '2196F3'),
      ColorSwatch.fromHex('Cyan', '00BCD4'),
      ColorSwatch.fromHex('Teal', '009688'),
      ColorSwatch.fromHex('Green', '4CAF50'),
      ColorSwatch.fromHex('Yellow', 'FFEB3B'),
      ColorSwatch.fromHex('Orange', 'FF9800'),
      ColorSwatch.fromHex('Brown', '795548'),
    ],
  );

  /// Soft pastel palette.
  static ColorPalette pastel() => ColorPalette(
    id: 'pastel',
    name: 'Pastel',
    description: 'Soft pastel tones for gentle designs',
    swatches: [
      ColorSwatch.fromHex('Rose', 'FFB3BA'),
      ColorSwatch.fromHex('Peach', 'FFDFBA'),
      ColorSwatch.fromHex('Lemon', 'FFFFBA'),
      ColorSwatch.fromHex('Mint', 'BAE1BA'),
      ColorSwatch.fromHex('Sky', 'BAE1FF'),
      ColorSwatch.fromHex('Lavender', 'D4BAFF'),
    ],
  );

  /// Monochrome grayscale.
  static ColorPalette grayscale() => ColorPalette(
    id: 'grayscale',
    name: 'Grayscale',
    description: 'Neutral grays from white to black',
    swatches: [
      ColorSwatch.fromHex('White', 'FFFFFF'),
      ColorSwatch.fromHex('Gray 100', 'F5F5F5'),
      ColorSwatch.fromHex('Gray 200', 'EEEEEE'),
      ColorSwatch.fromHex('Gray 300', 'E0E0E0'),
      ColorSwatch.fromHex('Gray 400', 'BDBDBD'),
      ColorSwatch.fromHex('Gray 500', '9E9E9E'),
      ColorSwatch.fromHex('Gray 600', '757575'),
      ColorSwatch.fromHex('Gray 700', '616161'),
      ColorSwatch.fromHex('Gray 800', '424242'),
      ColorSwatch.fromHex('Gray 900', '212121'),
      ColorSwatch.fromHex('Black', '000000'),
    ],
  );

  @override
  String toString() => 'ColorPalette($name, ${swatches.length} swatches)';
}

// =============================================================================
// COLOR PALETTE STORE
// =============================================================================

/// Manages multiple color palettes.
class ColorPaletteStore {
  final Map<String, ColorPalette> _palettes = {};

  /// Create an empty store.
  ColorPaletteStore();

  /// Create a store with built-in palettes pre-loaded.
  factory ColorPaletteStore.withBuiltIns() {
    final store = ColorPaletteStore();
    store.addPalette(ColorPalette.material());
    store.addPalette(ColorPalette.pastel());
    store.addPalette(ColorPalette.grayscale());
    return store;
  }

  /// Add or replace a palette.
  void addPalette(ColorPalette palette) {
    _palettes[palette.id] = palette;
  }

  /// Get a palette by ID.
  ColorPalette? getPalette(String id) => _palettes[id];

  /// Remove a palette by ID. Returns true if it existed.
  bool removePalette(String id) => _palettes.remove(id) != null;

  /// All palette IDs.
  List<String> get paletteIds => _palettes.keys.toList();

  /// Number of palettes.
  int get count => _palettes.length;

  /// Find a swatch across all palettes by name.
  ColorSwatch? findSwatch(String name) {
    for (final palette in _palettes.values) {
      final swatch = palette.findByName(name);
      if (swatch != null) return swatch;
    }
    return null;
  }

  /// Search swatches across all palettes.
  List<ColorSwatch> searchSwatches(String query) {
    final q = query.toLowerCase();
    final results = <ColorSwatch>[];
    for (final palette in _palettes.values) {
      for (final swatch in palette.swatches) {
        if (swatch.name.toLowerCase().contains(q) ||
            (swatch.description?.toLowerCase().contains(q) ?? false)) {
          results.add(swatch);
        }
      }
    }
    return results;
  }

  /// Clear all palettes.
  void clear() => _palettes.clear();

  /// Export all palettes as JSON.
  Map<String, dynamic> toJson() => {
    'version': 1,
    'palettes': {
      for (final entry in _palettes.entries) entry.key: entry.value.toJson(),
    },
  };

  /// Import palettes from JSON.
  factory ColorPaletteStore.fromJson(Map<String, dynamic> json) {
    final store = ColorPaletteStore();
    final palettes = json['palettes'] as Map<String, dynamic>?;
    if (palettes != null) {
      for (final entry in palettes.entries) {
        store.addPalette(
          ColorPalette.fromJson(entry.value as Map<String, dynamic>),
        );
      }
    }
    return store;
  }

  @override
  String toString() => 'ColorPaletteStore(palettes=$count)';
}
