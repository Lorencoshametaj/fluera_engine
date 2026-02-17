import 'package:flutter/material.dart';
import '../../core/scene_graph/canvas_node.dart';
import '../../core/nodes/group_node.dart';
import '../../core/nodes/layer_node.dart';
import '../../core/nodes/stroke_node.dart';
import '../../core/nodes/shape_node.dart';
import '../../core/nodes/text_node.dart';
import '../../core/nodes/image_node.dart';
import '../../core/nodes/clip_group_node.dart';
import '../../core/nodes/path_node.dart';
import '../../core/effects/node_effect.dart';
import '../../core/nodes/rich_text_node.dart';
import '../../core/nodes/symbol_system.dart';
import '../../core/nodes/frame_node.dart';
import '../../core/nodes/advanced_mask_node.dart';
import '../../core/effects/shader_effect.dart';
import '../../core/scene_graph/scene_graph.dart';
import '../../drawing/brushes/brushes.dart';
import '../canvas/shape_painter.dart';
import './path_renderer.dart';
import './rich_text_renderer.dart';

/// Renders a [SceneGraph] by recursively traversing the node tree.
///
/// Each node's `localTransform`, `opacity`, and `blendMode` are
/// applied via Canvas save/restore and `saveLayer` compositing.
///
/// This renderer is designed to be used alongside (or eventually
/// replace) the flat-list rendering in `DrawingPainter`. During the
/// transition, it can be called for specific subtrees or layers.
///
/// Usage:
/// ```dart
/// final renderer = SceneGraphRenderer();
/// renderer.render(canvas, sceneGraph, viewport);
/// ```
class SceneGraphRenderer {
  /// Render the entire scene graph.
  ///
  /// Only nodes whose world bounds intersect [viewport] are rendered.
  void render(Canvas canvas, SceneGraph sceneGraph, Rect viewport) {
    for (final layer in sceneGraph.layers) {
      if (!layer.isVisible) continue;
      renderNode(canvas, layer, viewport);
    }
  }

  /// Render a single node and its subtree.
  ///
  /// This is the core recursive dispatch method. It handles:
  /// 1. Visibility & viewport culling
  /// 2. Transform application
  /// 3. Compositing (opacity / blendMode)
  /// 4. Clip masks
  /// 5. Type-specific rendering
  void renderNode(Canvas canvas, CanvasNode node, Rect viewport) {
    if (!node.isVisible) return;

    // Viewport culling — skip nodes entirely outside the viewport.
    final bounds = node.worldBounds;
    if (bounds.isFinite && !bounds.overlaps(viewport)) return;

    // Save canvas state for this node's transform.
    canvas.save();

    // Apply local transform.
    final transform = node.localTransform;
    if (transform != Matrix4.identity()) {
      canvas.transform(transform.storage);
    }

    // Apply pre-effects (shadows, glow) — drawn BEFORE the node.
    _applyPreEffects(canvas, node);

    // Compositing layer (opacity / blendMode).
    final needsCompositing = shouldComposite(node);
    if (needsCompositing) {
      canvas.saveLayer(null, createCompositingPaint(node));
    }

    // Post-effects that need saveLayer wrapping (blur, color overlay).
    final postLayers = _beginPostEffects(canvas, node);

    // Dispatch by node type.
    if (node is ClipGroupNode) {
      _renderClipGroup(canvas, node, viewport);
    } else if (node is LayerNode) {
      _renderChildren(canvas, node, viewport);
    } else if (node is GroupNode) {
      _renderChildren(canvas, node, viewport);
    } else if (node is StrokeNode) {
      _renderStroke(canvas, node);
    } else if (node is ShapeNode) {
      _renderShape(canvas, node);
    } else if (node is PathNode) {
      _renderPath(canvas, node);
    } else if (node is TextNode) {
      _renderText(canvas, node);
    } else if (node is RichTextNode) {
      _renderRichText(canvas, node);
    } else if (node is SymbolInstanceNode) {
      _renderSymbolInstance(canvas, node, viewport);
    } else if (node is ImageNode) {
      _renderImage(canvas, node);
    } else if (node is ShaderNode) {
      _renderShaderNode(canvas, node);
    } else if (node is AdvancedMaskNode) {
      _renderAdvancedMask(canvas, node, viewport);
    } else if (node is FrameNode) {
      _renderFrame(canvas, node, viewport);
    }

    // End post-effect layers.
    _endPostEffects(canvas, postLayers);

    // Pop compositing layer.
    if (needsCompositing) {
      canvas.restore();
    }

    // Pop transform.
    canvas.restore();
  }

  // -------------------------------------------------------------------------
  // Private rendering methods
  // -------------------------------------------------------------------------

  /// Render all children of a GroupNode.
  void _renderChildren(Canvas canvas, GroupNode group, Rect viewport) {
    for (final child in group.children) {
      renderNode(canvas, child, viewport);
    }
  }

  /// Render a ClipGroupNode with its mask.
  void _renderClipGroup(Canvas canvas, ClipGroupNode clipNode, Rect viewport) {
    final applied = applyClipMask(canvas, clipNode);
    if (!applied) return;

    // Render the masked content (all children except the mask source).
    for (final child in clipNode.maskedContent) {
      renderNode(canvas, child, viewport);
    }

    if (clipNode.clipMode == ClipMode.alphaMask) {
      // Finalize alpha mask compositing.
      finalizeAlphaMask(
        canvas,
        clipNode,
        (c, node) => renderNode(c, node, viewport),
      );
    } else {
      // Pop the clip save.
      canvas.restore();
    }
  }

  /// Render a single stroke via BrushEngine.
  void _renderStroke(Canvas canvas, StrokeNode node) {
    final stroke = node.stroke;
    if (stroke.points.isEmpty) return;

    if (stroke.isFill) {
      _drawFillOverlay(canvas, stroke);
    } else {
      BrushEngine.renderStroke(
        canvas,
        stroke.points,
        stroke.color,
        stroke.baseWidth,
        stroke.penType,
        stroke.settings,
      );
    }
  }

  /// Render a shape via ShapePainter.
  void _renderShape(Canvas canvas, ShapeNode node) {
    ShapePainter.drawShape(canvas, node.shape);
  }

  /// Render a vector path via PathRenderer.
  void _renderPath(Canvas canvas, PathNode node) {
    PathRenderer.drawPathNode(canvas, node);
  }

  /// Render a rich text node via RichTextRenderer.
  void _renderRichText(Canvas canvas, RichTextNode node) {
    RichTextRenderer.drawRichTextNode(canvas, node);
  }

  /// Render a symbol instance by looking up its definition.
  ///
  /// When a [SymbolRegistry] is integrated into the renderer,
  /// this method resolves the definition and renders its content
  /// tree with instance overrides applied. Currently a no-op
  /// placeholder since the registry is not yet wired.
  void _renderSymbolInstance(
    Canvas canvas,
    SymbolInstanceNode node,
    Rect viewport,
  ) {
    // TODO: Resolve symbolDefinitionId via SymbolRegistry,
    // apply overrides, and render the definition's GroupNode content.
    // For now, this is a no-op — symbol instances are registered
    // but not yet rendered until the registry is wired into the renderer.
  }

  /// Render a text element.
  void _renderText(Canvas canvas, TextNode node) {
    final text = node.textElement;
    final textSpan = TextSpan(
      text: text.text,
      style: TextStyle(
        fontFamily: text.fontFamily,
        fontSize: text.fontSize * text.scale,
        color: text.color,
        fontWeight: text.fontWeight,
      ),
    );

    final painter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    painter.paint(canvas, text.position);

    // Update cached size for hit testing.
    node.cachedTextSize = painter.size;
  }

  /// Render an image element.
  ///
  /// Note: actual image decoding/loading is handled externally by the
  /// existing rendering pipeline. This method applies the transform
  /// and draws the image if already decoded (via ImageNode.imageSize).
  void _renderImage(Canvas canvas, ImageNode node) {
    // Image rendering is currently handled by the existing pipeline.
    // When the full scene graph renderer is enabled, this will need
    // integration with the image loading/caching system.
    // For now, this is a no-op placeholder — images continue to be
    // rendered by the existing DrawingPainter/image overlay system.
  }

  /// Draw a fill overlay (bucket fill) for a stroke.
  void _drawFillOverlay(Canvas canvas, dynamic stroke) {
    if (stroke.fillOverlayImage == null) return;
    final src = Rect.fromLTWH(
      0,
      0,
      stroke.fillOverlayImage!.width.toDouble(),
      stroke.fillOverlayImage!.height.toDouble(),
    );
    final dst = stroke.bounds;
    canvas.drawImageRect(stroke.fillOverlayImage!, src, dst, Paint());
  }

  // -------------------------------------------------------------------------
  // Effect stack helpers
  // -------------------------------------------------------------------------

  /// Apply pre-effects (shadows, glow) — these draw BEFORE the node.
  void _applyPreEffects(Canvas canvas, CanvasNode node) {
    for (final fx in node.effects) {
      if (!fx.isEnabled || !fx.isPre) continue;

      if (fx is DropShadowEffect) {
        canvas.save();
        canvas.translate(fx.offset.dx, fx.offset.dy);
        canvas.saveLayer(null, fx.createShadowPaint());
        // The node will be rendered normally afterwards — this layer
        // captures a blurred shadow copy. We restore immediately so
        // the shadow offset doesn't affect the main node.
        canvas.restore(); // saveLayer
        canvas.restore(); // translate
      } else if (fx is OuterGlowEffect) {
        canvas.saveLayer(null, fx.createGlowPaint());
        canvas.restore();
      }
    }
  }

  /// Begin post-effects by opening saveLayer(s). Returns the count of
  /// layers opened so [_endPostEffects] can close them.
  int _beginPostEffects(Canvas canvas, CanvasNode node) {
    int layerCount = 0;

    for (final fx in node.effects) {
      if (!fx.isEnabled || !fx.isPost) continue;

      if (fx is BlurEffect) {
        canvas.saveLayer(null, fx.createPaint());
        layerCount++;
      } else if (fx is ColorOverlayEffect) {
        canvas.saveLayer(null, fx.createPaint());
        layerCount++;
      } else if (fx is InnerShadowEffect) {
        // Inner shadow uses a dedicated saveLayer for dstOut compositing.
        canvas.saveLayer(null, Paint());
        layerCount++;
      }
    }

    return layerCount;
  }

  /// Close the post-effect saveLayer(s) opened by [_beginPostEffects].
  void _endPostEffects(Canvas canvas, int layerCount) {
    for (int i = 0; i < layerCount; i++) {
      canvas.restore();
    }
  }

  // -------------------------------------------------------------------------
  // Compositing helpers
  // -------------------------------------------------------------------------

  /// Whether a node needs a separate compositing layer.
  ///
  /// A compositing layer is needed when the node has non-default
  /// opacity or blend mode that must be applied atomically to
  /// the entire subtree.
  bool shouldComposite(CanvasNode node) {
    return node.opacity < 1.0 || node.blendMode != BlendMode.srcOver;
  }

  /// Create a [Paint] for compositing (opacity + blend mode).
  Paint createCompositingPaint(CanvasNode node) {
    return Paint()
      ..color = Color.fromRGBO(255, 255, 255, node.opacity)
      ..blendMode = node.blendMode;
  }

  /// Apply a clip mask from a [ClipGroupNode].
  ///
  /// Returns true if the clip was successfully applied.
  bool applyClipMask(Canvas canvas, ClipGroupNode clipNode) {
    final maskSource = clipNode.maskSource;
    if (maskSource == null) return false;

    if (clipNode.clipMode == ClipMode.alphaMask) {
      // Alpha mask: use saveLayer with dstIn blend to mask content.
      canvas.saveLayer(null, Paint());
      return true;
    } else {
      // Path clip: clip to the mask source's bounds.
      canvas.save();
      canvas.clipRect(maskSource.localBounds);
      return true;
    }
  }

  /// Finalize alpha mask compositing.
  ///
  /// After the masked content has been rendered, this draws the
  /// mask source with DstIn blend mode to produce the alpha mask effect.
  void finalizeAlphaMask(
    Canvas canvas,
    ClipGroupNode clipNode,
    void Function(Canvas, CanvasNode) renderCallback,
  ) {
    final maskSource = clipNode.maskSource;
    if (maskSource == null) return;

    // Draw the mask with DstIn: keeps only the content where the mask is opaque.
    canvas.saveLayer(null, Paint()..blendMode = BlendMode.dstIn);
    renderCallback(canvas, maskSource);
    canvas.restore(); // DstIn layer
    canvas.restore(); // Content layer
  }

  // ---------------------------------------------------------------------------
  // Shader Node rendering
  // ---------------------------------------------------------------------------

  /// Render a shader node.
  ///
  /// In production, this would compile and bind the fragment shader program.
  /// For now, it renders a filled rect as a placeholder — the actual
  /// GPU program binding requires runtime FragmentProgram.fromAsset().
  void _renderShaderNode(Canvas canvas, ShaderNode node) {
    if (!node.effect.isEnabled) return;

    final rect = node.localBounds;
    final paint =
        Paint()
          ..color = Color.fromRGBO(128, 128, 255, node.effect.opacity)
          ..blendMode = node.effect.blendMode;

    canvas.drawRect(rect, paint);
  }

  // ---------------------------------------------------------------------------
  // Advanced Mask rendering
  // ---------------------------------------------------------------------------

  /// Render an advanced mask node with its compositing.
  ///
  /// The mask node contains children (mask source) and applies
  /// its mask type as a compositing blend mode.
  void _renderAdvancedMask(
    Canvas canvas,
    AdvancedMaskNode node,
    Rect viewport,
  ) {
    if (node.children.isEmpty) return;

    final bounds = node.localBounds;
    if (bounds.isEmpty) return;

    // The first child is the mask source, remaining are masked content.
    final maskChild = node.children.first;
    final contentChildren = node.children.skip(1);

    // Determine blend mode from mask type.
    BlendMode maskBlend;
    switch (node.maskType) {
      case MaskType.alpha:
      case MaskType.luminance:
      case MaskType.silhouette:
        maskBlend = BlendMode.dstIn;
      case MaskType.intersection:
        maskBlend = BlendMode.srcIn;
      case MaskType.exclusion:
        maskBlend = BlendMode.dstOut;
      case MaskType.invertedLuminance:
        maskBlend = BlendMode.dstOut;
    }

    // Draw content first, then apply mask.
    canvas.saveLayer(null, Paint());
    for (final child in contentChildren) {
      renderNode(canvas, child, viewport);
    }

    // Apply mask with compositing blend.
    canvas.saveLayer(null, Paint()..blendMode = maskBlend);
    renderNode(canvas, maskChild, viewport);
    canvas.restore(); // mask layer
    canvas.restore(); // content layer
  }

  // ---------------------------------------------------------------------------
  // Frame Node rendering
  // ---------------------------------------------------------------------------

  /// Render a frame (auto-layout container) with fill, border, clip, and children.
  void _renderFrame(Canvas canvas, FrameNode node, Rect viewport) {
    final bounds = node.localBounds;

    // Draw fill background.
    if (node.fillColor != null) {
      final fillPaint = Paint()..color = node.fillColor!;
      if (node.borderRadius > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(bounds, Radius.circular(node.borderRadius)),
          fillPaint,
        );
      } else {
        canvas.drawRect(bounds, fillPaint);
      }
    }

    // Clip children to frame bounds if enabled.
    if (node.clipContent) {
      canvas.save();
      if (node.borderRadius > 0) {
        canvas.clipRRect(
          RRect.fromRectAndRadius(bounds, Radius.circular(node.borderRadius)),
        );
      } else {
        canvas.clipRect(bounds);
      }
    }

    // Render children.
    _renderChildren(canvas, node, viewport);

    // Pop clip.
    if (node.clipContent) {
      canvas.restore();
    }

    // Draw stroke/border.
    if (node.strokeColor != null && node.strokeWidth > 0) {
      final strokePaint =
          Paint()
            ..color = node.strokeColor!
            ..style = PaintingStyle.stroke
            ..strokeWidth = node.strokeWidth;
      if (node.borderRadius > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(bounds, Radius.circular(node.borderRadius)),
          strokePaint,
        );
      } else {
        canvas.drawRect(bounds, strokePaint);
      }
    }
  }
}
