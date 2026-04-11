// ============================================================================
// ♿ ACCESSIBILITY CONFIG — Pedagogical accessibility features (A11)
//
// Specifica: A11-01 → A11-08 (Appendice A11 — Accessibilità)
//
// Manages accessibility features required by the pedagogical framework:
//
//   A11-01: Color redundancy — every color has a secondary channel
//   A11-02: Colorblind palette — alternative colors for deuteranopia/protanopia
//   A11-03: Fill patterns for Ghost Map — works in grayscale
//   A11-04: Keyboard mode for Steps 3/6 (motor disabilities)
//   A11-06: Contrast ≥4.5:1 (WCAG AA)
//   A11-08: High-contrast blur option
//
// ARCHITECTURE:
//   Pure model class — no Flutter widgets, no BuildContext.
//   The canvas screen reads this config to select colors, icons, patterns.
//   Persisted via FlueraCanvasConfig (host app stores preferences).
//
// CRITICAL (A17-05): All accessibility features are ALWAYS FREE.
// ============================================================================

import 'dart:ui';

/// ♿ Pedagogical accessibility configuration.
///
/// Provides alternative visual representations for all color-coded
/// elements across the 12-step methodology.
///
/// Usage:
/// ```dart
/// final color = accessibilityConfig.resolveColor(SemanticColor.missing);
/// final icon = accessibilityConfig.resolveIcon(SemanticColor.missing);
/// ```
class PedagogicalAccessibilityConfig {

  // ── Colorblind mode (A11-02) ──────────────────────────────────────────

  /// Whether the colorblind palette is active.
  final bool isColorblindModeEnabled;

  // ── Keyboard mode (A11-04) ────────────────────────────────────────────

  /// Whether keyboard input replaces handwriting for Steps 3/6.
  final bool isKeyboardModeEnabled;

  // ── High-contrast blur (A11-08) ───────────────────────────────────────

  /// Whether to use opaque overlay instead of gaussian blur.
  final bool isHighContrastBlurEnabled;

  const PedagogicalAccessibilityConfig({
    this.isColorblindModeEnabled = false,
    this.isKeyboardModeEnabled = false,
    this.isHighContrastBlurEnabled = false,
  });

  /// Default configuration (all features off).
  static const PedagogicalAccessibilityConfig defaultConfig =
      PedagogicalAccessibilityConfig();

  // ─────────────────────────────────────────────────────────────────────────
  // COLOR RESOLUTION (A11-01, A11-02)
  // ─────────────────────────────────────────────────────────────────────────

  /// Resolve a semantic color to its visual representation.
  ///
  /// In colorblind mode, colors are swapped to a palette
  /// distinguishable for deuteranopia and protanopia (A11-02).
  Color resolveColor(SemanticColor semantic) {
    if (isColorblindModeEnabled) {
      return _colorblindPalette[semantic]!;
    }
    return _standardPalette[semantic]!;
  }

  /// Standard color palette (default).
  static const Map<SemanticColor, Color> _standardPalette = {
    SemanticColor.correct:       Color(0xFF4CAF50), // Green
    SemanticColor.missing:       Color(0xFFFF3B30), // Red
    SemanticColor.wrongEdge:     Color(0xFFFFEB3B), // Yellow
    SemanticColor.missingEdge:   Color(0xFF2196F3), // Blue
    SemanticColor.fogRevealed:   Color(0xFF4CAF50), // Green
    SemanticColor.fogUnrevealed: Color(0xFFFF3B30), // Red
    SemanticColor.fogUnvisited:  Color(0xFF9E9E9E), // Grey
    SemanticColor.srsFragile:    Color(0xFFFF5722), // Deep Orange
    SemanticColor.srsSolid:      Color(0xFF4CAF50), // Green
    SemanticColor.srsMastered:   Color(0xFFFFD700), // Gold
  };

  /// Colorblind-safe palette (A11-02).
  ///
  /// Tested with deuteranopia and protanopia simulation:
  /// - Standard Red → Orange #FF6B35
  /// - Standard Green → Cyan #00C9DB
  /// - Standard Yellow → Magenta #FF00FF
  /// - Standard Blue → White #FFFFFF
  static const Map<SemanticColor, Color> _colorblindPalette = {
    SemanticColor.correct:       Color(0xFF00C9DB), // Cyan (was Green)
    SemanticColor.missing:       Color(0xFFFF6B35), // Orange (was Red)
    SemanticColor.wrongEdge:     Color(0xFFFF00FF), // Magenta (was Yellow)
    SemanticColor.missingEdge:   Color(0xFFFFFFFF), // White (was Blue)
    SemanticColor.fogRevealed:   Color(0xFF00C9DB), // Cyan
    SemanticColor.fogUnrevealed: Color(0xFFFF6B35), // Orange
    SemanticColor.fogUnvisited:  Color(0xFF9E9E9E), // Grey (unchanged)
    SemanticColor.srsFragile:    Color(0xFFFF6B35), // Orange
    SemanticColor.srsSolid:      Color(0xFF00C9DB), // Cyan
    SemanticColor.srsMastered:   Color(0xFFFFD700), // Gold (unchanged)
  };

  // ─────────────────────────────────────────────────────────────────────────
  // ICON REDUNDANCY (A11-01)
  // ─────────────────────────────────────────────────────────────────────────

  /// Icon/shape for each semantic color, providing redundancy (A11-01).
  ///
  /// "Mai colore-solo": every color has a secondary channel
  /// (icon, form, pattern, or text).
  static const Map<SemanticColor, String> iconRedundancy = {
    SemanticColor.correct:       '✅',
    SemanticColor.missing:       '❌',
    SemanticColor.wrongEdge:     '❓',
    SemanticColor.missingEdge:   '---', // Dashed line
    SemanticColor.fogRevealed:   '✅',
    SemanticColor.fogUnrevealed: '❌',
    SemanticColor.fogUnvisited:  '◻️',
    SemanticColor.srsFragile:    '🌱',
    SemanticColor.srsSolid:      '🌳',
    SemanticColor.srsMastered:   '⭐',
  };

  /// Get the redundant icon for a semantic color.
  static String iconFor(SemanticColor semantic) =>
      iconRedundancy[semantic] ?? '•';

  // ─────────────────────────────────────────────────────────────────────────
  // FILL PATTERNS (A11-03)
  // ─────────────────────────────────────────────────────────────────────────

  /// Fill pattern type for Ghost Map nodes in colorblind mode (A11-03).
  ///
  /// Patterns work in grayscale and provide additional differentiation.
  static GhostMapFillPattern fillPatternFor(SemanticColor semantic) {
    return switch (semantic) {
      SemanticColor.missing     => GhostMapFillPattern.diagonalHatch,
      SemanticColor.wrongEdge   => GhostMapFillPattern.dots,
      SemanticColor.correct     => GhostMapFillPattern.horizontalLines,
      SemanticColor.missingEdge => GhostMapFillPattern.dashed,
      _                         => GhostMapFillPattern.none,
    };
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SERIALIZATION
  // ─────────────────────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'colorblindMode': isColorblindModeEnabled,
        'keyboardMode': isKeyboardModeEnabled,
        'highContrastBlur': isHighContrastBlurEnabled,
      };

  factory PedagogicalAccessibilityConfig.fromJson(Map<String, dynamic> json) {
    return PedagogicalAccessibilityConfig(
      isColorblindModeEnabled: json['colorblindMode'] as bool? ?? false,
      isKeyboardModeEnabled: json['keyboardMode'] as bool? ?? false,
      isHighContrastBlurEnabled: json['highContrastBlur'] as bool? ?? false,
    );
  }

  /// Create a new config with one or more properties changed.
  PedagogicalAccessibilityConfig copyWith({
    bool? isColorblindModeEnabled,
    bool? isKeyboardModeEnabled,
    bool? isHighContrastBlurEnabled,
  }) {
    return PedagogicalAccessibilityConfig(
      isColorblindModeEnabled:
          isColorblindModeEnabled ?? this.isColorblindModeEnabled,
      isKeyboardModeEnabled:
          isKeyboardModeEnabled ?? this.isKeyboardModeEnabled,
      isHighContrastBlurEnabled:
          isHighContrastBlurEnabled ?? this.isHighContrastBlurEnabled,
    );
  }
}

/// Semantic color categories used across the 12-step methodology.
///
/// Each category maps to both a visual color and a redundant icon/shape.
enum SemanticColor {
  /// Ghost Map: node correctly present in student's canvas.
  correct,

  /// Ghost Map: node missing from student's canvas.
  missing,

  /// Ghost Map: wrong connection in student's canvas.
  wrongEdge,

  /// Ghost Map: missing connection between student's nodes.
  missingEdge,

  /// Fog of War: node correctly revealed.
  fogRevealed,

  /// Fog of War: node not recalled correctly.
  fogUnrevealed,

  /// Fog of War: node not yet visited.
  fogUnvisited,

  /// SRS: fragile node (stage 1-2).
  srsFragile,

  /// SRS: solid node (stage 3-4).
  srsSolid,

  /// SRS: mastered node (stage 5).
  srsMastered,
}

/// Fill patterns for Ghost Map in colorblind mode (A11-03).
///
/// Used as additional visual channel when color alone is insufficient.
enum GhostMapFillPattern {
  /// No pattern — solid fill.
  none,

  /// Diagonal hatch lines — for missing nodes.
  diagonalHatch,

  /// Dot pattern — for wrong connections.
  dots,

  /// Horizontal lines — for correct nodes.
  horizontalLines,

  /// Dashed line — for missing connections.
  dashed,
}
