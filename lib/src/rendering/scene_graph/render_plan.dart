import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../core/scene_graph/canvas_node.dart';
import '../../core/scene_graph/scene_graph.dart';
import '../../core/scene_graph/invalidation_graph.dart';
import '../../core/nodes/group_node.dart';
import '../../core/nodes/layer_node.dart';
import '../../core/nodes/clip_group_node.dart';
import '../../core/nodes/frame_node.dart';
import '../../core/nodes/section_node.dart';
import '../../core/nodes/advanced_mask_node.dart';
import '../../core/effects/node_effect.dart';
import '../optimization/occlusion_culler.dart';
import './scene_graph_renderer.dart';

// =============================================================================
// Render Commands
// =============================================================================

/// Tag identifying the type of a [RenderCommand].
///
/// Using an enum tag instead of sealed classes avoids virtual dispatch
/// overhead during the hot execute loop.
enum RenderCommandType {
  /// Save the canvas state.
  save,

  /// Restore the canvas state.
  restore,

  /// Apply a transform to the canvas.
  transform,

  /// Open a compositing layer via `saveLayer`.
  saveLayer,

  /// Clip the canvas to a rectangle.
  clipRect,

  /// Clip the canvas to a path.
  clipPath,

  /// Draw a leaf node via `SceneGraphRenderer`.
  drawNode,

  /// Placeholder for a culled/occluded node — emits nothing.
  skip,
}

/// A single command in a compiled [RenderPlan].
///
/// Commands are stored in a flat list and executed sequentially,
/// eliminating recursive traversal and per-node branching decisions.
class RenderCommand {
  final RenderCommandType type;

  /// The node referenced by this command (for [drawNode] and some others).
  final CanvasNode? node;

  /// Transform matrix (for [transform] commands).
  final Matrix4? matrix;

  /// Paint for compositing (for [saveLayer] commands).
  final Paint? paint;

  /// Rectangle for [clipRect] commands.
  final Rect? rect;

  /// Path for [clipPath] commands.
  final Path? path;

  const RenderCommand._({
    required this.type,
    this.node,
    this.matrix,
    this.paint,
    this.rect,
    this.path,
  });

  // ---------------------------------------------------------------------------
  // Factory constructors for each command type
  // ---------------------------------------------------------------------------

  /// Save canvas state.
  const factory RenderCommand.save() = _SaveCommand;

  /// Restore canvas state.
  const factory RenderCommand.restore() = _RestoreCommand;

  /// Apply a local transform.
  factory RenderCommand.transform(Matrix4 matrix) =>
      RenderCommand._(type: RenderCommandType.transform, matrix: matrix);

  /// Open a compositing layer.
  factory RenderCommand.saveLayer(Paint paint) =>
      RenderCommand._(type: RenderCommandType.saveLayer, paint: paint);

  /// Clip to a rectangle.
  factory RenderCommand.clipRect(Rect rect) =>
      RenderCommand._(type: RenderCommandType.clipRect, rect: rect);

  /// Clip to a path.
  factory RenderCommand.clipPath(Path path) =>
      RenderCommand._(type: RenderCommandType.clipPath, path: path);

  /// Draw a leaf node.
  factory RenderCommand.drawNode(CanvasNode node) =>
      RenderCommand._(type: RenderCommandType.drawNode, node: node);

  /// No-op placeholder for culled/occluded nodes.
  const factory RenderCommand.skip() = _SkipCommand;
}

class _SaveCommand extends RenderCommand {
  const _SaveCommand() : super._(type: RenderCommandType.save);
}

class _RestoreCommand extends RenderCommand {
  const _RestoreCommand() : super._(type: RenderCommandType.restore);
}

class _SkipCommand extends RenderCommand {
  const _SkipCommand() : super._(type: RenderCommandType.skip);
}

// =============================================================================
// Render Plan
// =============================================================================

/// A compiled, flat list of [RenderCommand]s produced from a [SceneGraph].
///
/// The plan is compiled once (when the graph changes) and executed every
/// frame without recursive traversal or per-node branching.
///
/// Usage:
/// ```dart
/// final compiler = RenderPlanCompiler();
/// final plan = compiler.compile(sceneGraph, viewport, scale);
/// plan.execute(canvas, renderer);
/// ```
class RenderPlan {
  /// The flat command list.
  final List<RenderCommand> commands;

  /// Scene graph version when this plan was compiled.
  final int graphVersion;

  /// Viewport used during compilation (for staleness detection).
  final Rect viewport;

  /// Scale used during compilation.
  final double scale;

  /// Whether the plan has been invalidated and needs recompilation.
  bool _dirty = false;

  /// Number of draw commands in this plan.
  final int drawCount;

  /// Number of nodes culled during compilation.
  final int culledCount;

  RenderPlan({
    required this.commands,
    required this.graphVersion,
    required this.viewport,
    required this.scale,
    required this.drawCount,
    required this.culledCount,
  });

  /// Whether this plan is still valid for the given parameters.
  bool isValid({
    required int currentGraphVersion,
    required Rect currentViewport,
    required double currentScale,
    InvalidationGraph? invalidationGraph,
  }) {
    if (_dirty) return false;
    if (currentGraphVersion != graphVersion) return false;
    // Recompile if viewport changed significantly (>5% in any dimension)
    if (!_viewportsClose(viewport, currentViewport)) return false;
    // Recompile if scale changed significantly (>10%)
    if (scale <= 0.0 || (currentScale - scale).abs() / scale > 0.1) {
      return false;
    }
    // Recompile if invalidation graph has dirty nodes
    if (invalidationGraph != null && invalidationGraph.hasDirty) return false;
    return true;
  }

  /// Mark this plan as needing recompilation.
  void markDirty() => _dirty = true;

  /// Execute the plan by running each command on the canvas.
  ///
  /// This is the hot path — designed for minimal overhead:
  /// - No recursion
  /// - No type checking
  /// - Switch on enum tag (compiled to jump table)
  void execute(Canvas canvas, SceneGraphRenderer renderer) {
    for (int i = 0; i < commands.length; i++) {
      final cmd = commands[i];
      switch (cmd.type) {
        case RenderCommandType.save:
          canvas.save();
        case RenderCommandType.restore:
          canvas.restore();
        case RenderCommandType.transform:
          canvas.transform(cmd.matrix!.storage);
        case RenderCommandType.saveLayer:
          canvas.saveLayer(null, cmd.paint!);
        case RenderCommandType.clipRect:
          canvas.clipRect(cmd.rect!);
        case RenderCommandType.clipPath:
          canvas.clipPath(cmd.path!);
        case RenderCommandType.drawNode:
          renderer.renderNodeLeaf(canvas, cmd.node!);
        case RenderCommandType.skip:
          break; // no-op
      }
    }
  }

  /// Check if two viewports are close enough to reuse the plan.
  static bool _viewportsClose(Rect a, Rect b) {
    final w = a.width > 0 ? a.width : 1.0;
    final h = a.height > 0 ? a.height : 1.0;
    return (a.left - b.left).abs() / w < 0.05 &&
        (a.top - b.top).abs() / h < 0.05 &&
        (a.width - b.width).abs() / w < 0.05 &&
        (a.height - b.height).abs() / h < 0.05;
  }
}

// =============================================================================
// Render Plan Compiler
// =============================================================================

/// Compiles a [SceneGraph] into a flat [RenderPlan].
///
/// The compiler walks the scene graph recursively once, emitting
/// [RenderCommand]s for transforms, compositing, clipping, and leaf
/// node drawing. The resulting plan can be executed every frame
/// without re-traversal.
class RenderPlanCompiler {
  int _drawCount = 0;
  int _culledCount = 0;

  /// Whether to apply occlusion culling as a post-compilation pass.
  ///
  /// When enabled, nodes fully covered by opaque nodes above them
  /// are replaced with `skip` commands, reducing fill-rate waste.
  bool enableOcclusionCulling = true;

  /// Compile a scene graph into a render plan.
  ///
  /// [viewport] is used for viewport culling during compilation.
  /// [scale] is used for adaptive LOD decisions.
  RenderPlan compile(
    SceneGraph sceneGraph,
    Rect viewport, {
    double scale = 1.0,
  }) {
    _drawCount = 0;
    _culledCount = 0;
    var commands = <RenderCommand>[];

    for (final layer in sceneGraph.layers) {
      if (!layer.isVisible) continue;
      _compileNode(commands, layer, viewport, scale);
    }

    // Optional occlusion culling pass (GAP 4).
    if (enableOcclusionCulling) {
      commands = OcclusionCuller.optimize(commands);
    }

    return RenderPlan(
      commands: commands,
      graphVersion: sceneGraph.version,
      viewport: viewport,
      scale: scale,
      drawCount: _drawCount,
      culledCount: _culledCount,
    );
  }

  /// Recursively compile a node and its subtree into commands.
  void _compileNode(
    List<RenderCommand> commands,
    CanvasNode node,
    Rect viewport,
    double scale,
  ) {
    if (!node.isVisible) {
      _culledCount++;
      return;
    }

    // Viewport culling — skip nodes entirely outside the viewport.
    final bounds = node.worldBounds;
    if (bounds.isFinite && !bounds.overlaps(viewport)) {
      _culledCount++;
      return;
    }

    // --- Save canvas state ---
    commands.add(const RenderCommand.save());

    // --- Apply local transform ---
    if (!node.isIdentityTransform) {
      commands.add(RenderCommand.transform(node.localTransform));
    }

    // --- Pre-effects (shadows, glow) ---
    _compilePreEffects(commands, node, viewport, scale);

    // --- Compositing layer (opacity / blendMode) ---
    final needsCompositing = _shouldComposite(node);
    if (needsCompositing) {
      commands.add(RenderCommand.saveLayer(_createCompositingPaint(node)));
    }

    // --- Post-effects that need saveLayer wrapping ---
    final postLayerCount = _compilePostEffects(commands, node);

    // --- Node content ---
    if (node is ClipGroupNode) {
      _compileClipGroup(commands, node, viewport, scale);
    } else if (node is FrameNode) {
      _compileFrame(commands, node, viewport, scale);
    } else if (node is SectionNode) {
      _compileSection(commands, node, viewport, scale);
    } else if (node is AdvancedMaskNode) {
      _compileAdvancedMask(commands, node, viewport, scale);
    } else if (node is GroupNode) {
      // Generic group (including LayerNode): compile children.
      _compileChildren(commands, node, viewport, scale);
    } else {
      // Leaf node — emit a draw command.
      commands.add(RenderCommand.drawNode(node));
      _drawCount++;
    }

    // --- Pop post-effect layers ---
    for (int i = 0; i < postLayerCount; i++) {
      commands.add(const RenderCommand.restore());
    }

    // --- Pop compositing layer ---
    if (needsCompositing) {
      commands.add(const RenderCommand.restore());
    }

    // --- Restore canvas state ---
    commands.add(const RenderCommand.restore());
  }

  /// Compile all children of a group node.
  void _compileChildren(
    List<RenderCommand> commands,
    GroupNode group,
    Rect viewport,
    double scale,
  ) {
    for (final child in group.children) {
      _compileNode(commands, child, viewport, scale);
    }
  }

  /// Compile a ClipGroupNode.
  void _compileClipGroup(
    List<RenderCommand> commands,
    ClipGroupNode node,
    Rect viewport,
    double scale,
  ) {
    final maskSource = node.maskSource;
    if (maskSource == null) return;

    if (node.clipMode == ClipMode.alphaMask) {
      // Alpha mask needs saveLayer compositing — fall back to direct rendering.
      // The renderer handles this via renderNodeLeaf → _renderClipGroup.
      commands.add(RenderCommand.drawNode(node));
      _drawCount++;
    } else {
      // Path clip: clip to the mask source's bounds.
      commands.add(const RenderCommand.save());
      commands.add(RenderCommand.clipRect(maskSource.localBounds));

      // Render the masked content.
      for (final child in node.maskedContent) {
        _compileNode(commands, child, viewport, scale);
      }

      commands.add(const RenderCommand.restore());
    }
  }

  /// Compile a FrameNode.
  void _compileFrame(
    List<RenderCommand> commands,
    FrameNode node,
    Rect viewport,
    double scale,
  ) {
    // Frame rendering is complex (fill, border, clip, layout) —
    // delegate to direct rendering for correctness.
    commands.add(RenderCommand.drawNode(node));
    _drawCount++;
  }

  /// Compile a SectionNode.
  void _compileSection(
    List<RenderCommand> commands,
    SectionNode node,
    Rect viewport,
    double scale,
  ) {
    // Section rendering is complex (fill, border, label, grid, clip) —
    // delegate to direct rendering for correctness.
    commands.add(RenderCommand.drawNode(node));
    _drawCount++;
  }

  /// Compile an AdvancedMaskNode.
  void _compileAdvancedMask(
    List<RenderCommand> commands,
    AdvancedMaskNode node,
    Rect viewport,
    double scale,
  ) {
    // Advanced mask compositing is complex — delegate to direct rendering.
    commands.add(RenderCommand.drawNode(node));
    _drawCount++;
  }

  /// Compile pre-effects (shadows, glow) into commands.
  void _compilePreEffects(
    List<RenderCommand> commands,
    CanvasNode node,
    Rect viewport,
    double scale,
  ) {
    for (final fx in node.effects) {
      if (!fx.isEnabled || !fx.isPre) continue;

      if (fx is DropShadowEffect) {
        // Shadow: save → translate → saveLayer → draw node → restore × 2
        commands.add(const RenderCommand.save());
        commands.add(
          RenderCommand.transform(
            Matrix4.translationValues(fx.offset.dx, fx.offset.dy, 0),
          ),
        );
        commands.add(RenderCommand.saveLayer(fx.createShadowPaint()));
        commands.add(RenderCommand.drawNode(node));
        _drawCount++;
        commands.add(const RenderCommand.restore()); // saveLayer
        commands.add(const RenderCommand.restore()); // translate
      } else if (fx is OuterGlowEffect) {
        commands.add(RenderCommand.saveLayer(fx.createGlowPaint()));
        commands.add(RenderCommand.drawNode(node));
        _drawCount++;
        commands.add(const RenderCommand.restore());
      }
    }
  }

  /// Compile post-effects that need saveLayer wrapping.
  /// Returns the number of layers opened.
  int _compilePostEffects(List<RenderCommand> commands, CanvasNode node) {
    int layerCount = 0;
    for (final fx in node.effects) {
      if (!fx.isEnabled || !fx.isPost) continue;

      if (fx is BlurEffect) {
        commands.add(RenderCommand.saveLayer(fx.createPaint()));
        layerCount++;
      } else if (fx is ColorOverlayEffect) {
        commands.add(RenderCommand.saveLayer(fx.createPaint()));
        layerCount++;
      } else if (fx is InnerShadowEffect) {
        commands.add(RenderCommand.saveLayer(Paint()));
        layerCount++;
      }
    }
    return layerCount;
  }

  /// Whether a node needs a separate compositing layer.
  bool _shouldComposite(CanvasNode node) {
    return node.opacity < 1.0 || node.blendMode != BlendMode.srcOver;
  }

  /// Create a Paint for compositing (opacity + blend mode).
  Paint _createCompositingPaint(CanvasNode node) {
    return Paint()
      ..color = Color.fromRGBO(255, 255, 255, node.opacity)
      ..blendMode = node.blendMode;
  }
}
