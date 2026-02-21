/// 📐 LAYOUT TEMPLATE — Predefined layout presets for common compositions.
///
/// Provides ready-to-use layout configurations for common design patterns.
/// Each template produces an [AutoLayoutConfig] or [GridLayoutConfig] that
/// can be attached to a frame node.
///
/// ```dart
/// final stack = LayoutTemplate.horizontalStack(spacing: 12);
/// final grid = LayoutTemplate.dashboardGrid();
/// ```
library;

import 'auto_layout_config.dart';
import 'grid_layout_solver.dart';

// =============================================================================
// LAYOUT TEMPLATE
// =============================================================================

/// Predefined layout configuration preset.
class LayoutTemplate {
  /// Unique template identifier.
  final String id;

  /// Human-readable name.
  final String name;

  /// Description of the layout.
  final String description;

  /// Flex layout config (null if grid-based).
  final AutoLayoutConfig? flexConfig;

  /// Grid layout config (null if flex-based).
  final GridLayoutConfig? gridConfig;

  const LayoutTemplate({
    required this.id,
    required this.name,
    required this.description,
    this.flexConfig,
    this.gridConfig,
  });

  /// Whether this template uses flex layout.
  bool get isFlex => flexConfig != null;

  /// Whether this template uses grid layout.
  bool get isGrid => gridConfig != null;

  // ===========================================================================
  // FLEX PRESETS
  // ===========================================================================

  /// Horizontal stack with configurable spacing.
  static LayoutTemplate horizontalStack({double spacing = 8}) => LayoutTemplate(
    id: 'horizontal_stack',
    name: 'Horizontal Stack',
    description: 'Children laid out horizontally with equal spacing',
    flexConfig: AutoLayoutConfig(
      direction: LayoutDirection.horizontal,
      spacing: spacing,
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.center,
      primarySizing: LayoutSizingMode.hugContents,
      counterSizing: LayoutSizingMode.hugContents,
    ),
  );

  /// Vertical stack with configurable spacing.
  static LayoutTemplate verticalStack({double spacing = 8}) => LayoutTemplate(
    id: 'vertical_stack',
    name: 'Vertical Stack',
    description: 'Children laid out vertically with equal spacing',
    flexConfig: AutoLayoutConfig(
      direction: LayoutDirection.vertical,
      spacing: spacing,
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      primarySizing: LayoutSizingMode.hugContents,
      counterSizing: LayoutSizingMode.fillContainer,
    ),
  );

  /// Center content both horizontally and vertically.
  static LayoutTemplate centeredContent() => const LayoutTemplate(
    id: 'centered_content',
    name: 'Centered Content',
    description: 'Single child centered in the container',
    flexConfig: AutoLayoutConfig(
      direction: LayoutDirection.vertical,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      primarySizing: LayoutSizingMode.fillContainer,
      counterSizing: LayoutSizingMode.fillContainer,
    ),
  );

  /// Navigation bar: items spread across the width.
  static LayoutTemplate navigationBar({double padding = 16}) => LayoutTemplate(
    id: 'navigation_bar',
    name: 'Navigation Bar',
    description: 'Horizontal bar with items spaced evenly',
    flexConfig: AutoLayoutConfig(
      direction: LayoutDirection.horizontal,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      padding: LayoutEdgeInsets.symmetric(horizontal: padding),
      primarySizing: LayoutSizingMode.fillContainer,
      counterSizing: LayoutSizingMode.hugContents,
    ),
  );

  /// Wrapping tag/chip layout.
  static LayoutTemplate wrappingTags({double spacing = 6}) => LayoutTemplate(
    id: 'wrapping_tags',
    name: 'Wrapping Tags',
    description: 'Horizontal items that wrap to next line when full',
    flexConfig: AutoLayoutConfig(
      direction: LayoutDirection.horizontal,
      spacing: spacing,
      overflow: OverflowBehavior.wrap,
      primarySizing: LayoutSizingMode.fillContainer,
      counterSizing: LayoutSizingMode.hugContents,
    ),
  );

  // ===========================================================================
  // GRID PRESETS
  // ===========================================================================

  /// Sidebar layout: fixed sidebar + flexible main content.
  static LayoutTemplate sidebar({double sidebarWidth = 240, double gap = 16}) =>
      LayoutTemplate(
        id: 'sidebar',
        name: 'Sidebar Layout',
        description: 'Fixed sidebar with flexible main content area',
        gridConfig: GridLayoutConfig(
          columns: [
            TrackDefinition.fixed(sidebarWidth),
            const TrackDefinition.fr(1),
          ],
          rows: const [TrackDefinition.fr(1)],
          columnGap: gap,
        ),
      );

  /// Magazine-style 3-column grid.
  static LayoutTemplate magazineGrid({double gap = 16}) => LayoutTemplate(
    id: 'magazine_grid',
    name: 'Magazine Grid',
    description: 'Three equal columns for editorial layouts',
    gridConfig: GridLayoutConfig(
      columns: const [
        TrackDefinition.fr(1),
        TrackDefinition.fr(1),
        TrackDefinition.fr(1),
      ],
      rows: const [TrackDefinition.fr(1), TrackDefinition.fr(1)],
      columnGap: gap,
      rowGap: gap,
    ),
  );

  /// Dashboard grid: header + 2-column body + footer.
  static LayoutTemplate dashboardGrid({double gap = 12}) => LayoutTemplate(
    id: 'dashboard_grid',
    name: 'Dashboard Grid',
    description: 'Header, 2-column body, and footer',
    gridConfig: GridLayoutConfig(
      columns: const [TrackDefinition.fr(1), TrackDefinition.fr(1)],
      rows: [
        const TrackDefinition.fixed(64), // header
        const TrackDefinition.fr(1), // body
        const TrackDefinition.fixed(48), // footer
      ],
      columnGap: gap,
      rowGap: gap,
    ),
  );

  /// Presentation slide: title area + content area.
  static LayoutTemplate presentationSlide() => const LayoutTemplate(
    id: 'presentation_slide',
    name: 'Presentation Slide',
    description: 'Title bar with large content area below',
    gridConfig: GridLayoutConfig(
      columns: [TrackDefinition.fr(1)],
      rows: [
        TrackDefinition.fixed(120), // title
        TrackDefinition.fr(1), // content
      ],
      rowGap: 24,
    ),
  );

  /// Card layout: image area + text area.
  static LayoutTemplate cardLayout() => const LayoutTemplate(
    id: 'card_layout',
    name: 'Card Layout',
    description: 'Image area above text content',
    gridConfig: GridLayoutConfig(
      columns: [TrackDefinition.fr(1)],
      rows: [
        TrackDefinition.fr(3), // image (60%)
        TrackDefinition.fr(2), // text (40%)
      ],
      rowGap: 0,
    ),
  );

  // ===========================================================================
  // REGISTRY
  // ===========================================================================

  /// All built-in templates.
  static List<LayoutTemplate> get allBuiltIn => [
    horizontalStack(),
    verticalStack(),
    centeredContent(),
    navigationBar(),
    wrappingTags(),
    sidebar(),
    magazineGrid(),
    dashboardGrid(),
    presentationSlide(),
    cardLayout(),
  ];

  @override
  String toString() => 'LayoutTemplate($id: $name)';
}
