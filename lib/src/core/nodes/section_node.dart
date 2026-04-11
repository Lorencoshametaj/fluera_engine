import 'package:flutter/material.dart';
import '../scene_graph/canvas_node.dart';
import '../scene_graph/node_id.dart';
import '../scene_graph/node_visitor.dart';
import './group_node.dart';

// =============================================================================
// Section Presets
// =============================================================================

/// Common preset sizes for canvas sections.
///
/// Provides quick access to standard dimensions for common devices,
/// paper sizes, and screen resolutions.
enum SectionPreset {
  // --- Devices ---
  iphone16(label: 'iPhone 16', width: 393, height: 852),
  iphone16Pro(label: 'iPhone 16 Pro', width: 402, height: 874),
  iphone16ProMax(label: 'iPhone 16 Pro Max', width: 440, height: 956),
  ipadPro11(label: 'iPad Pro 11"', width: 834, height: 1194),
  ipadPro13(label: 'iPad Pro 13"', width: 1032, height: 1376),

  // --- Desktop ---
  macbook14(label: 'MacBook 14"', width: 1512, height: 982),
  desktop1080p(label: '1080p (Full HD)', width: 1920, height: 1080),
  desktop4k(label: '4K (UHD)', width: 3840, height: 2160),

  // --- Paper (at 150 DPI screen equivalents — matches device preset scale) ---
  a4Portrait(label: 'A4 Portrait', width: 1240, height: 1754),       // 210×297mm @150dpi
  a4Landscape(label: 'A4 Landscape', width: 1754, height: 1240),
  a3Portrait(label: 'A3 Portrait', width: 1754, height: 2480),       // 297×420mm @150dpi
  letterPortrait(label: 'US Letter Portrait', width: 1275, height: 1650),   // 8.5×11in @150dpi
  letterLandscape(label: 'US Letter Landscape', width: 1650, height: 1275),

  // --- Social ---
  instagramPost(label: 'Instagram Post', width: 1080, height: 1080),
  instagramStory(label: 'Instagram Story', width: 1080, height: 1920),
  twitterPost(label: 'Twitter/X Post', width: 1200, height: 675),

  // --- Presentation ---
  presentation16x9(label: 'Presentation 16:9', width: 1920, height: 1080),
  presentation4x3(label: 'Presentation 4:3', width: 1024, height: 768),

  // --- Custom ---
  custom(label: 'Custom', width: 800, height: 600);

  final String label;
  final double width;
  final double height;

  const SectionPreset({
    required this.label,
    required this.width,
    required this.height,
  });

  /// Get the size for this preset.
  Size get size => Size(width, height);
}

// =============================================================================
// Section Node
// =============================================================================

/// A named, bounded area on the infinite canvas.
///
/// `SectionNode` acts as an artboard: it defines a rectangular region
/// with a name, optional background color, and optional grid.
/// Unlike [FrameNode], it has **no auto-layout** — children are
/// free-form positioned within the section bounds.
///
/// Sections are top-level organizational units that let users:
/// - Define fixed-size working areas (A4, 1080p, mobile screens)
/// - Export individual sections as images/PDFs
/// - Navigate between sections via the minimap
///
/// ```dart
/// final section = SectionNode(
///   id: NodeId.generate(),
///   sectionName: 'Home Screen',
///   sectionSize: const Size(393, 852),
///   backgroundColor: Colors.white,
///   preset: SectionPreset.iphone16,
/// );
/// sceneGraph.rootNode.add(section);
/// ```
class SectionNode extends GroupNode {
  /// Display name shown above the section boundary.
  String sectionName;

  /// Width × height of the section area.
  Size sectionSize;

  /// Background fill color (null = transparent).
  Color? backgroundColor;

  /// Whether to display an internal alignment grid.
  bool showGrid;

  /// Grid spacing in canvas units (only used when [showGrid] is true).
  double gridSpacing;

  /// Grid type: 'grid' (square grid), 'ruled' (horizontal lines with margin),
  /// 'dotted' (dot grid). Only used when [showGrid] is true.
  String gridType;

  /// Optional preset this section was created from.
  SectionPreset? preset;

  /// Whether to clip children to the section bounds.
  bool clipContent;

  /// Border color for the section outline (design-time visual).
  Color borderColor;

  /// Border width for the section outline.
  double borderWidth;

  /// Number of horizontal subdivision rows (1 = no subdivision).
  int subdivisionRows;

  /// Number of vertical subdivision columns (1 = no subdivision).
  int subdivisionColumns;

  /// Color of the subdivision divider lines.
  Color subdivisionColor;

  /// Corner radius for the section bounding rectangle.
  double cornerRadius;

  SectionNode({
    required super.id,
    super.localTransform,
    super.opacity,
    super.blendMode,
    super.isVisible,
    super.isLocked,
    this.sectionName = 'Section',
    this.sectionSize = const Size(800, 600),
    this.backgroundColor = Colors.white,
    this.showGrid = false,
    this.gridSpacing = 20,
    this.gridType = 'grid',
    this.preset,
    this.clipContent = false,
    this.borderColor = const Color(0xFFBDBDBD),
    this.borderWidth = 1.0,
    this.subdivisionRows = 1,
    this.subdivisionColumns = 1,
    this.subdivisionColor = const Color(0x33000000),
    this.cornerRadius = 0,
  }) : super(name: sectionName);

  /// Create a section from a preset.
  factory SectionNode.fromPreset({
    required NodeId id,
    required SectionPreset preset,
    String? name,
    Color? backgroundColor,
  }) {
    return SectionNode(
      id: id,
      sectionName: name ?? preset.label,
      sectionSize: preset.size,
      backgroundColor: backgroundColor ?? Colors.white,
      preset: preset,
    );
  }

  // ---------------------------------------------------------------------------
  // Bounds
  // ---------------------------------------------------------------------------

  @override
  Rect get localBounds =>
      Rect.fromLTWH(0, 0, sectionSize.width, sectionSize.height);

  /// The label area sits above the section bounds.
  /// Used by the renderer to position the section name.
  static const double labelHeight = 28.0;
  static const double labelPadding = 8.0;

  /// Total bounds including the label area above.
  Rect get boundsWithLabel => Rect.fromLTWH(
    0,
    -labelHeight,
    sectionSize.width,
    sectionSize.height + labelHeight,
  );

  // ---------------------------------------------------------------------------
  // Hit testing
  // ---------------------------------------------------------------------------

  @override
  bool hitTest(Offset worldPoint) {
    if (!isVisible) return false;

    // Check children first (reverse z-order).
    final childHit = hitTestChildren(worldPoint);
    if (childHit != null) return true;

    // Then check the section bounds itself.
    final inverse = Matrix4.tryInvert(worldTransform);
    if (inverse == null) return false;
    final local = MatrixUtils.transformPoint(inverse, worldPoint);
    return localBounds.contains(local);
  }

  // ---------------------------------------------------------------------------
  // Resize
  // ---------------------------------------------------------------------------

  /// Resize the section to new dimensions.
  void resize(Size newSize) {
    sectionSize = newSize;
    preset = null; // No longer a standard preset
    invalidateBoundsCache();
  }

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  @override
  Map<String, dynamic> toJson() {
    final json = baseToJson();
    json['nodeType'] = 'section';
    json['sectionName'] = sectionName;
    json['sectionSize'] = {
      'width': sectionSize.width,
      'height': sectionSize.height,
    };
    if (backgroundColor != null) {
      json['backgroundColor'] = backgroundColor!.toARGB32();
    }
    json['showGrid'] = showGrid;
    json['gridSpacing'] = gridSpacing;
    if (gridType != 'grid') json['gridType'] = gridType;
    if (preset != null && preset != SectionPreset.custom) {
      json['preset'] = preset!.name;
    }
    json['clipContent'] = clipContent;
    json['borderColor'] = borderColor.toARGB32();
    json['borderWidth'] = borderWidth;
    if (subdivisionRows > 1) json['subdivisionRows'] = subdivisionRows;
    if (subdivisionColumns > 1) json['subdivisionColumns'] = subdivisionColumns;
    if (subdivisionRows > 1 || subdivisionColumns > 1) {
      json['subdivisionColor'] = subdivisionColor.toARGB32();
    }
    if (cornerRadius > 0) json['cornerRadius'] = cornerRadius;
    json['children'] = children.map((c) => c.toJson()).toList();
    return json;
  }

  factory SectionNode.fromJson(Map<String, dynamic> json) {
    final sizeJson =
        json['sectionSize'] as Map<String, dynamic>? ??
        {'width': 800, 'height': 600};

    SectionPreset? resolvedPreset;
    final presetName = json['preset'] as String?;
    if (presetName != null) {
      try {
        resolvedPreset = SectionPreset.values.byName(presetName);
      } catch (_) {
        // Unknown preset — ignore gracefully.
      }
    }

    final node = SectionNode(
      id: NodeId(json['id'] as String),
      sectionName: json['sectionName'] as String? ?? 'Section',
      sectionSize: Size(
        (sizeJson['width'] as num).toDouble(),
        (sizeJson['height'] as num).toDouble(),
      ),
      backgroundColor:
          json['backgroundColor'] != null
              ? Color(json['backgroundColor'] as int)
              : null,
      showGrid: json['showGrid'] as bool? ?? false,
      gridSpacing: (json['gridSpacing'] as num?)?.toDouble() ?? 20,
      gridType: json['gridType'] as String? ?? 'grid',
      preset: resolvedPreset,
      clipContent: json['clipContent'] as bool? ?? false,
      borderColor:
          json['borderColor'] != null
              ? Color(json['borderColor'] as int)
              : const Color(0xFFBDBDBD),
      borderWidth: (json['borderWidth'] as num?)?.toDouble() ?? 1.0,
      subdivisionRows: json['subdivisionRows'] as int? ?? 1,
      subdivisionColumns: json['subdivisionColumns'] as int? ?? 1,
      subdivisionColor:
          json['subdivisionColor'] != null
              ? Color(json['subdivisionColor'] as int)
              : const Color(0x33000000),
      cornerRadius: (json['cornerRadius'] as num?)?.toDouble() ?? 0,
    );

    CanvasNode.applyBaseFromJson(node, json);

    return node;
  }

  // ---------------------------------------------------------------------------
  // Visitor
  // ---------------------------------------------------------------------------

  @override
  R accept<R>(NodeVisitor<R> visitor) => visitor.visitSection(this);
}
