import 'package:flutter/material.dart';

// =============================================================================
// 🎨 TOOLBAR TOKENS — Centralized design system for the canvas toolbar.
//
// All toolbar UI code should reference these constants instead of raw
// Colors.* values. This ensures visual consistency across all tool buttons,
// tab chips, and status indicators.
// =============================================================================

abstract final class ToolbarTokens {
  // ---------------------------------------------------------------------------
  // Sizing
  // ---------------------------------------------------------------------------

  /// Standard icon size (tool buttons, tab icons)
  static const double iconSize = 20.0;

  /// Small icon size (layout chips, badges)
  static const double iconSizeSmall = 16.0;

  /// Minimum interactive target size (WCAG 2.5.5 AAA: 44×44).
  /// Use for any tappable surface that doesn't already have ≥44pt of
  /// hit area from surrounding padding.
  static const double tapTargetMin = 44.0;

  /// Height of compact chips (Recall, Branch, layout buttons).
  /// Raised from 30→40 for better touch accessibility on stylus+finger
  /// devices. Pair with horizontal padding ≥ 6pt for effective ≥44×44
  /// hit area after surrounding layout.
  static const double chipHeight = 40.0;

  /// Horizontal padding for tool toggle buttons
  static const double buttonPadH = 10.0;

  /// Vertical padding for tool toggle buttons
  static const double buttonPadV = 8.0;

  /// Standard border radius for tool containers and chips
  static const double radius = 10.0;

  /// Border radius for layout/sync chips
  static const double chipRadius = 10.0;

  /// Border radius for tab chips
  static const double tabRadius = 8.0;

  // ---------------------------------------------------------------------------
  // Active state — semantic color palette
  //
  // Colors are chosen to form two families:
  //   • Blue family  — drawing/creation (pen, section)
  //   • Violet family — selection/analysis (lasso, recall, latex, branch)
  //   • Amber family  — overlays/navigation (ruler, pan)
  //   • Cyan/Teal     — media/content (image, recording, search)
  //   • Emerald       — text input
  //   • Red           — destructive (eraser)
  // ---------------------------------------------------------------------------

  /// Drawing pen, stylus, vector pen tool
  static const Color penActive = Color(0xFF2563EB); // Blue-600

  /// Eraser — destructive action, red family
  static const Color eraserActive = Color(0xFFDC2626); // Red-600

  /// Lasso selection — violet family
  static const Color lassoActive = Color(0xFF7C3AED); // Violet-600

  /// Ruler / guide overlay — amber family
  static const Color rulerActive = Color(0xFFD97706); // Amber-600

  /// Pan mode — amber/orange family
  static const Color panActive = Color(0xFFF59E0B); // Amber-500

  /// Digital text input — emerald family
  static const Color textActive = Color(0xFF059669); // Emerald-600

  /// Image picker, recording — cyan/teal family
  static const Color mediaActive = Color(0xFF0891B2); // Cyan-600

  /// LaTeX editor — violet family (same family as lasso/recall)
  static const Color latexActive = Color(0xFF7C3AED); // Violet-600

  /// Section / artboard — blue family (same as pen)
  static const Color sectionActive = Color(0xFF2563EB); // Blue-600

  /// Handwriting search — cyan family
  static const Color searchActive = Color(0xFF0891B2); // Cyan-600

  /// Recall Mode, Branch Explorer — brand purple
  static const Color recallActive = Color(0xFF6C63FF); // Brand violet

  /// Branch Explorer — brand purple (same family as Recall)
  static const Color branchActive = Color(0xFF6C63FF); // Brand violet

  /// Minimap — teal (navigation aid)
  static const Color minimapActive = Color(0xFF0D9488); // Teal-600

  /// Shape recognition — violet family
  static const Color shapeRecognitionActive = Color(0xFF7C3AED); // Violet-600

  // ---------------------------------------------------------------------------
  // Active state background helpers
  // ---------------------------------------------------------------------------

  /// Returns the background color for an active tool button (light mode).
  static Color activeBackground(Color color, {bool isDark = false}) {
    return color.withValues(alpha: isDark ? 0.22 : 0.10);
  }

  /// Returns the border color for an active tool button.
  static Color activeBorder(Color color) {
    return color.withValues(alpha: 0.45);
  }

  // ---------------------------------------------------------------------------
  // Top Bar zones
  // ---------------------------------------------------------------------------

  /// Height of the top row (containing back, title, quick actions)
  static const double topRowHeight = 50.0;

  /// Vertical padding inside the top row
  static const EdgeInsets topRowPadding = EdgeInsets.symmetric(
    horizontal: 4,
    vertical: 6,
  );

  // ---------------------------------------------------------------------------
  // Tab bar
  // ---------------------------------------------------------------------------

  /// Height of the tab bar strip
  static const double tabBarHeight = 34.0;

  /// Horizontal padding inside each tab chip
  static const double tabChipPadH = 10.0;

  /// Vertical padding inside each tab chip
  static const double tabChipPadV = 4.0;

  /// Label font size in tab chips
  static const double tabFontSize = 11.0;

  /// Tooltip delay — long enough to not pop up accidentally
  static const Duration tooltipDelay = Duration(milliseconds: 600);

  // ---------------------------------------------------------------------------
  // 🎬 Animation tokens — Enterprise micro-interaction system
  // ---------------------------------------------------------------------------

  /// Fast micro-animation: icon swap, tap feedback (150ms)
  static const Duration animFast = Duration(milliseconds: 150);

  /// Standard UI transition: button active state, collapse (220ms)
  static const Duration animNormal = Duration(milliseconds: 220);

  /// Slower reveal: panel appear, surface blur (300ms)
  static const Duration animSlow = Duration(milliseconds: 300);

  /// Undo/redo bounce spring total duration (360ms, 2 phases)
  static const Duration animBounce = Duration(milliseconds: 360);

  /// Standard curve — tool activation, chip transitions
  static const Curve curveActive = Curves.easeOutCubic;

  /// Deactivation curve — slightly faster out
  static const Curve curveDeactive = Curves.easeInCubic;

  /// Spring-like feel for panel collapse
  static const Curve curveCollapse = Curves.easeInOutCubic;

  // ---------------------------------------------------------------------------
  // 🌫️ Surface tokens — Glassmorphism background system
  // ---------------------------------------------------------------------------

  /// BackdropFilter blur sigma for the toolbar surface
  static const double surfaceBlur = 20.0;

  /// Surface background opacity in dark mode
  static const double surfaceOpacityDark = 0.80;

  /// Surface background opacity in light mode
  static const double surfaceOpacityLight = 0.90;

  /// Top border highlight opacity (scrim line at top of toolbar)
  static const double surfaceBorderOpacityDark = 0.12;
  static const double surfaceBorderOpacityLight = 0.08;

  /// Toolbar shadow blurRadius
  static const double surfaceShadowBlur = 28.0;

  /// Toolbar shadow spreadRadius (negative = tight shadow)
  static const double surfaceShadowSpread = -4.0;

  /// Toolbar base shadow color opacity
  static const double surfaceShadowOpacity = 0.35;

  // ---------------------------------------------------------------------------
  // 🔴 Active dot indicator
  // ---------------------------------------------------------------------------

  /// Size of the dot shown beneath active tool icons
  static const double activeDotSize = 4.0;
}
