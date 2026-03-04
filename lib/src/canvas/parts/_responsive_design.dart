part of '../fluera_canvas_screen.dart';

// ============================================================================
// 📐 RESPONSIVE DESIGN — Wire breakpoints, variants, constraint propagation
// ============================================================================

extension ResponsiveDesignFeatures on _FlueraCanvasScreenState {
  /// Show breakpoint picker and preview at selected size.
  /// Wires: responsive_breakpoint, responsive_variant,
  ///        resizeWithConstraintPropagation
  void _showBreakpointPicker(String breakpoint) {
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
      builder:
          (ctx) => ResponsivePreviewPanel(
            breakpointName: breakpoint,
            targetSize: size,
          ),
    );
  }
}
