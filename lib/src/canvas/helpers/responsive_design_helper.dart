import 'package:flutter/material.dart';

import '../canvas_scope.dart';
import '../overlays/responsive_preview_panel.dart';

// ============================================================================
// 📐 RESPONSIVE DESIGN — Standalone helper (extracted from God Object Phase 1)
// ============================================================================

/// Shows the responsive breakpoint preview panel.
///
/// Extracted from `_responsive_design.dart` (was `part of fluera_canvas_screen`).
void showBreakpointPicker(BuildContext context, String breakpoint) {
  final sizes = {
    'mobile': const Size(375, 812),
    'tablet': const Size(768, 1024),
    'desktop': const Size(1440, 900),
  };

  final size = sizes[breakpoint] ?? sizes['mobile']!;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => ResponsivePreviewPanel(
      breakpointName: breakpoint,
      targetSize: size,
    ),
  );
}
