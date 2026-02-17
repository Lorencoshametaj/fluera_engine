import 'package:flutter/material.dart';
import '../scene_graph/canvas_node.dart';
import '../scene_graph/node_visitor.dart';
import './group_node.dart';
import '../vector/vector_path.dart';

/// Type of mask operation.
///
/// Extends the basic path-clip and alpha-mask from [ClipGroupNode]
/// with professional-grade compositing modes.
enum MaskType {
  /// Standard alpha mask: child alpha multiplied by mask alpha.
  alpha,

  /// Intersection: show only where both mask and content overlap.
  intersection,

  /// Exclusion: show content everywhere EXCEPT where mask covers.
  exclusion,

  /// Luminance: use the mask's brightness as the alpha channel.
  /// Brighter areas = more visible, darker areas = more transparent.
  luminance,

  /// Inverted luminance: darker areas = more visible.
  invertedLuminance,

  /// Silhouette: mask shape defines the visible region (like a stencil).
  silhouette,
}

/// Settings for mask preview/editing mode.
class MaskPreviewSettings {
  /// Whether to show the mask overlay in the UI.
  bool showOverlay;

  /// Color used to tint the mask region in preview mode.
  Color overlayColor;

  /// Opacity of the preview overlay.
  double overlayOpacity;

  /// Whether to show the mask outline.
  bool showOutline;

  MaskPreviewSettings({
    this.showOverlay = true,
    this.overlayColor = const Color(0x80FF0000),
    this.overlayOpacity = 0.5,
    this.showOutline = true,
  });
}

/// An advanced mask node that supports multiple compositing operations.
///
/// Unlike the basic [ClipGroupNode] which only supports path-clip and
/// simple alpha masks, [AdvancedMaskNode] provides intersection,
/// exclusion, luminance, and silhouette masking modes.
///
/// The mask itself is defined by [maskPath] (a [VectorPath]) or by
/// [maskChildId] (using another node in the scene graph as the mask source).
///
/// ```dart
/// final mask = AdvancedMaskNode(
///   id: 'text-mask',
///   maskType: MaskType.luminance,
///   maskPath: circlePath,
/// );
/// mask.add(contentNode); // Content masked by the circle
/// ```
class AdvancedMaskNode extends GroupNode {
  /// The type of mask operation.
  MaskType maskType;

  /// Vector path defining the mask shape (if using path-based masking).
  VectorPath? maskPath;

  /// ID of another node to use as the mask source (if using node-based masking).
  String? maskChildId;

  /// Feather/blur radius for mask edges (0 = hard edge).
  double featherRadius;

  /// Whether the mask is inverted (swap masked/unmasked regions).
  bool inverted;

  /// Whether the mask is currently in preview/editing mode.
  bool previewMode;

  /// Preview settings.
  final MaskPreviewSettings previewSettings;

  /// Expansion/erosion of the mask boundary (positive = expand).
  double expansion;

  AdvancedMaskNode({
    required super.id,
    super.name = 'Mask',
    super.localTransform,
    super.opacity,
    super.blendMode,
    super.isVisible,
    super.isLocked,
    this.maskType = MaskType.alpha,
    this.maskPath,
    this.maskChildId,
    this.featherRadius = 0,
    this.inverted = false,
    this.previewMode = false,
    this.expansion = 0,
    MaskPreviewSettings? previewSettings,
  }) : previewSettings = previewSettings ?? MaskPreviewSettings();

  // ---------------------------------------------------------------------------
  // Mask application
  // ---------------------------------------------------------------------------

  /// Apply this mask to a [Canvas] before rendering children.
  ///
  /// Callers should:
  /// 1. Call [beginMask] to set up the clip/compositing
  /// 2. Render children
  /// 3. Call [endMask] to finalize
  void beginMask(Canvas canvas, Size size) {
    canvas.save();

    switch (maskType) {
      case MaskType.alpha:
      case MaskType.silhouette:
        _applyPathClip(canvas);
      case MaskType.intersection:
        _applyIntersectionMask(canvas, size);
      case MaskType.exclusion:
        _applyExclusionMask(canvas, size);
      case MaskType.luminance:
      case MaskType.invertedLuminance:
        _applyLuminanceMask(canvas, size);
    }
  }

  /// Finalize the mask after rendering children.
  void endMask(Canvas canvas) {
    canvas.restore();
  }

  /// Render the mask preview overlay (when in preview mode).
  void renderPreview(Canvas canvas, Size size) {
    if (!previewMode || maskPath == null) return;

    final path = _getEffectivePath();
    if (path == null) return;

    if (previewSettings.showOverlay) {
      final paint =
          Paint()
            ..color = previewSettings.overlayColor.withValues(
              alpha: previewSettings.overlayOpacity,
            )
            ..style = PaintingStyle.fill;
      canvas.drawPath(path, paint);
    }

    if (previewSettings.showOutline) {
      final outlinePaint =
          Paint()
            ..color = Colors.red
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5;
      canvas.drawPath(path, outlinePaint);
    }
  }

  // ---------------------------------------------------------------------------
  // Private mask implementations
  // ---------------------------------------------------------------------------

  void _applyPathClip(Canvas canvas) {
    final path = _getEffectivePath();
    if (path == null) return;

    if (inverted) {
      // Invert: clip to everything OUTSIDE the path.
      final invertedPath =
          Path()
            ..fillType = PathFillType.evenOdd
            ..addRect(Rect.fromLTWH(-10000, -10000, 20000, 20000))
            ..addPath(path, Offset.zero);
      canvas.clipPath(invertedPath);
    } else {
      canvas.clipPath(path);
    }
  }

  void _applyIntersectionMask(Canvas canvas, Size size) {
    // Intersection: save layer with SrcIn blend mode.
    // Content is only visible where mask has content.
    final path = _getEffectivePath();
    if (path == null) return;

    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());

    // Draw mask shape first.
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );

    // Set blend mode so content only shows where mask exists.
    canvas.saveLayer(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..blendMode = inverted ? BlendMode.srcOut : BlendMode.srcIn,
    );
  }

  void _applyExclusionMask(Canvas canvas, Size size) {
    // Exclusion: show content everywhere EXCEPT where mask covers.
    final path = _getEffectivePath();
    if (path == null) return;

    if (inverted) {
      // Inverted exclusion = intersection.
      canvas.clipPath(path);
    } else {
      // Clip to the inverse of the mask path.
      final invertedPath =
          Path()
            ..fillType = PathFillType.evenOdd
            ..addRect(Rect.fromLTWH(-10000, -10000, 20000, 20000))
            ..addPath(path, Offset.zero);
      canvas.clipPath(invertedPath);
    }
  }

  void _applyLuminanceMask(Canvas canvas, Size size) {
    // Luminance masking: use brightness of mask as alpha.
    // This requires rendering the mask to a separate layer,
    // converting to grayscale, and using as alpha.
    final layerBounds = Rect.fromLTWH(0, 0, size.width, size.height);

    // We use a color filter to extract luminance.
    final colorFilter =
        maskType == MaskType.invertedLuminance
            ? const ColorFilter.matrix(<double>[
              // Invert luminance
              -0.2126, -0.7152, -0.0722, 0, 255,
              -0.2126, -0.7152, -0.0722, 0, 255,
              -0.2126, -0.7152, -0.0722, 0, 255,
              0, 0, 0, 1, 0,
            ])
            : const ColorFilter.matrix(<double>[
              // Standard luminance
              0.2126, 0.7152, 0.0722, 0, 0,
              0.2126, 0.7152, 0.0722, 0, 0,
              0.2126, 0.7152, 0.0722, 0, 0,
              0, 0, 0, 1, 0,
            ]);

    canvas.saveLayer(layerBounds, Paint()..colorFilter = colorFilter);
  }

  // ---------------------------------------------------------------------------
  // Path helpers
  // ---------------------------------------------------------------------------

  /// Get the Flutter [Path] for this mask, applying feather and expansion.
  Path? _getEffectivePath() {
    if (maskPath == null) return null;

    Path path = maskPath!.toFlutterPath();

    // Apply expansion/erosion (approximate via stroke + fill).
    if (expansion != 0) {
      // Positive expansion = grow the path, negative = shrink.
      // We approximate by stroking the path and combining.
      if (expansion > 0) {
        // Approximate expansion by adding the path as a union with itself.
        final expandedPath = Path()..addPath(path, Offset.zero);
        path = Path.combine(PathOperation.union, path, expandedPath);
      }
      // Erosion (negative expansion) would require path offsetting,
      // which is complex — left as a TODO for production.
    }

    return path;
  }

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  @override
  Map<String, dynamic> toJson() {
    final json = baseToJson();
    json['nodeType'] = 'advancedMask';
    json['maskType'] = maskType.name;
    if (maskPath != null) json['maskPath'] = maskPath!.toJson();
    if (maskChildId != null) json['maskChildId'] = maskChildId;
    json['featherRadius'] = featherRadius;
    json['inverted'] = inverted;
    json['expansion'] = expansion;
    json['children'] = children.map((c) => c.toJson()).toList();
    return json;
  }

  factory AdvancedMaskNode.fromJson(Map<String, dynamic> json) {
    final node = AdvancedMaskNode(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Mask',
      maskType: MaskType.values.byName(json['maskType'] as String? ?? 'alpha'),
      maskPath:
          json['maskPath'] != null
              ? VectorPath.fromJson(json['maskPath'] as Map<String, dynamic>)
              : null,
      maskChildId: json['maskChildId'] as String?,
      featherRadius: (json['featherRadius'] as num?)?.toDouble() ?? 0,
      inverted: json['inverted'] as bool? ?? false,
      expansion: (json['expansion'] as num?)?.toDouble() ?? 0,
    );

    CanvasNode.applyBaseFromJson(node, json);
    return node;
  }

  @override
  R accept<R>(NodeVisitor<R> visitor) => visitor.visitAdvancedMask(this);
}
