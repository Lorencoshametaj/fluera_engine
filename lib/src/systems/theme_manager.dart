/// 🎨 THEME MANAGER — Theme switching for design variable modes.
///
/// Manages named theme definitions that map variable collections to modes,
/// enabling light/dark/brand theme switching across the entire design system.
library;

import 'design_variables.dart';

/// A named theme that maps collection IDs to their active mode IDs.
class ThemeDefinition {
  final String name;
  final String? description;
  final Map<String, String> modeSelections;

  const ThemeDefinition({
    required this.name,
    this.description,
    required this.modeSelections,
  });

  ThemeDefinition copyWith({
    String? name,
    String? description,
    Map<String, String>? modeSelections,
  }) => ThemeDefinition(
    name: name ?? this.name,
    description: description ?? this.description,
    modeSelections: modeSelections ?? this.modeSelections,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    if (description != null) 'description': description,
    'modeSelections': modeSelections,
  };

  factory ThemeDefinition.fromJson(Map<String, dynamic> json) =>
      ThemeDefinition(
        name: json['name'] as String,
        description: json['description'] as String?,
        modeSelections: Map<String, String>.from(
          json['modeSelections'] as Map<String, dynamic>,
        ),
      );

  @override
  String toString() => 'ThemeDefinition($name)';
}

/// Manages theme definitions and active theme switching.
class ThemeManager {
  ThemeManager();
  final Map<String, ThemeDefinition> _themes = {};
  String? _activeThemeName;

  /// All registered themes (unmodifiable).
  Map<String, ThemeDefinition> get themes => Map.unmodifiable(_themes);

  /// Name of the currently active theme (null if none).
  String? get activeThemeName => _activeThemeName;

  /// The currently active theme definition (null if none).
  ThemeDefinition? get activeTheme =>
      _activeThemeName != null ? _themes[_activeThemeName] : null;

  /// Add or replace a theme.
  void addTheme(ThemeDefinition theme) {
    _themes[theme.name] = theme;
  }

  /// Remove a theme by name.
  bool removeTheme(String name) {
    if (_activeThemeName == name) _activeThemeName = null;
    return _themes.remove(name) != null;
  }

  /// Get a theme by name.
  ThemeDefinition? getTheme(String name) => _themes[name];

  /// Check if a theme exists.
  bool hasTheme(String name) => _themes.containsKey(name);

  /// Switch to a named theme.
  ///
  /// Returns the mode selections map for the theme, or null if not found.
  Map<String, String>? switchTheme(String name) {
    final theme = _themes[name];
    if (theme == null) return null;
    _activeThemeName = name;
    return Map.unmodifiable(theme.modeSelections);
  }

  /// Apply the active theme to variable collections.
  ///
  /// Updates each collection's active mode based on the theme's
  /// mode selections. Collections not mentioned in the theme
  /// are left unchanged.
  ///
  /// Returns the number of collections updated.
  int applyTheme(
    List<VariableCollection> collections,
    Map<String, String> activeModes,
  ) {
    final theme = activeTheme;
    if (theme == null) return 0;

    int updated = 0;
    for (final entry in theme.modeSelections.entries) {
      final collectionId = entry.key;
      final modeId = entry.value;

      // Verify mode exists in collection.
      for (final collection in collections) {
        if (collection.id != collectionId) continue;
        final hasMode = collection.modes.any((m) => m.id == modeId);
        if (hasMode) {
          activeModes[collectionId] = modeId;
          updated++;
        }
        break;
      }
    }
    return updated;
  }

  /// Create scaffold themes from collections that have light/dark modes.
  List<ThemeDefinition> scaffoldLightDark(
    List<VariableCollection> collections,
  ) {
    final themes = <ThemeDefinition>[];
    final lightSelections = <String, String>{};
    final darkSelections = <String, String>{};

    for (final collection in collections) {
      for (final mode in collection.modes) {
        final modeName = mode.name.toLowerCase();
        if (modeName == 'light') {
          lightSelections[collection.id] = mode.id;
        } else if (modeName == 'dark') {
          darkSelections[collection.id] = mode.id;
        }
      }
    }

    if (lightSelections.isNotEmpty) {
      themes.add(
        ThemeDefinition(
          name: 'light',
          description: 'Auto-generated light theme',
          modeSelections: lightSelections,
        ),
      );
    }
    if (darkSelections.isNotEmpty) {
      themes.add(
        ThemeDefinition(
          name: 'dark',
          description: 'Auto-generated dark theme',
          modeSelections: darkSelections,
        ),
      );
    }

    return themes;
  }

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'themes': _themes.values.map((t) => t.toJson()).toList(),
    if (_activeThemeName != null) 'activeTheme': _activeThemeName,
  };

  factory ThemeManager.fromJson(Map<String, dynamic> json) {
    final manager = ThemeManager();
    final list = json['themes'] as List<dynamic>? ?? [];
    for (final raw in list) {
      final theme = ThemeDefinition.fromJson(raw as Map<String, dynamic>);
      manager._themes[theme.name] = theme;
    }
    manager._activeThemeName = json['activeTheme'] as String?;
    return manager;
  }
}
