import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../effects/node_effect.dart';
import '../../systems/accessibility_tree.dart';
import './canvas_node_factory.dart';
import './node_visitor.dart';

/// Base class for all elements in the scene graph.
///
/// Every canvas element (stroke, shape, text, image, group) is a [CanvasNode].
/// Each node carries its own [localTransform] matrix encoding
/// translate/rotate/scale/skew, plus per-node visual properties
/// ([opacity], [blendMode], [isVisible], [isLocked]).
///
/// The scene graph is a tree: each node has a [parent] and leaf nodes
/// represent concrete content, while [GroupNode] subclasses contain children.
abstract class CanvasNode {
  /// Unique identifier for this node.
  final String id;

  /// Human-readable name (shown in layer panel, etc.).
  String name;

  // ---------------------------------------------------------------------------
  // Transform
  // ---------------------------------------------------------------------------

  /// Local transform relative to this node's parent.
  ///
  /// Encodes translate, rotate, scale, and skew in a single 4×4 matrix.
  /// To move/rotate/scale a node, mutate this matrix — the underlying
  /// geometry never changes.
  Matrix4 localTransform;

  // ---------------------------------------------------------------------------
  // Visual properties
  // ---------------------------------------------------------------------------

  double _opacity;

  /// Node opacity (0.0 = fully transparent, 1.0 = fully opaque).
  ///
  /// Automatically clamped to `[0.0, 1.0]`.
  double get opacity => _opacity;
  set opacity(double value) {
    _opacity = value.clamp(0.0, 1.0);
  }

  ui.BlendMode blendMode;
  bool isVisible;
  bool isLocked;

  /// Non-destructive effects applied during rendering.
  ///
  /// Effects are processed in order: pre-effects (shadows, glow) before
  /// the node, post-effects (blur, color overlay) after.
  List<NodeEffect> effects;

  /// Accessibility metadata for assistive technologies.
  ///
  /// When non-null, the node is included in the accessibility tree
  /// with the specified role, label, and other semantic properties.
  AccessibilityInfo? accessibilityInfo;

  // ---------------------------------------------------------------------------
  // Hierarchy
  // ---------------------------------------------------------------------------

  /// Parent node in the scene graph (null for root).
  CanvasNode? parent;

  // ---------------------------------------------------------------------------
  // Constructor
  // ---------------------------------------------------------------------------

  CanvasNode({
    required this.id,
    this.name = '',
    Matrix4? localTransform,
    double opacity = 1.0,
    this.blendMode = ui.BlendMode.srcOver,
    this.isVisible = true,
    this.isLocked = false,
    this.parent,
    List<NodeEffect>? effects,
  }) : assert(id.isNotEmpty, 'Node ID must not be empty'),
       localTransform = localTransform ?? Matrix4.identity(),
       _opacity = opacity.clamp(0.0, 1.0),
       effects = effects ?? [];

  // ---------------------------------------------------------------------------
  // Bounds
  // ---------------------------------------------------------------------------

  /// Bounding box in **local** coordinates (geometry only, no transform).
  Rect get localBounds;

  /// Bounding box in **world** coordinates (with accumulated transforms).
  Rect get worldBounds {
    final wt = worldTransform;
    return MatrixUtils.transformRect(wt, localBounds);
  }

  // ---------------------------------------------------------------------------
  // World transform
  // ---------------------------------------------------------------------------

  /// Accumulated transform from root to this node.
  ///
  /// Computed by multiplying parent's [worldTransform] × [localTransform].
  /// Cached and invalidated via [invalidateTransformCache].
  late Matrix4 _cachedWorldTransform;
  bool _worldTransformDirty = true;

  Matrix4 get worldTransform {
    if (!_worldTransformDirty) return _cachedWorldTransform;
    if (parent == null) {
      _cachedWorldTransform = localTransform.clone();
    } else {
      _cachedWorldTransform = parent!.worldTransform.multiplied(localTransform);
    }
    _worldTransformDirty = false;
    return _cachedWorldTransform;
  }

  /// Invalidatete the cached world transform for this node and all descendants.
  void invalidateTransformCache() {
    _worldTransformDirty = true;
  }

  // ---------------------------------------------------------------------------
  // Hit testing
  // ---------------------------------------------------------------------------

  /// Returns `true` if [worldPoint] falls inside this node's bounds.
  ///
  /// The default implementation inverse-transforms the point into local
  /// space and checks against [localBounds]. Subclasses can override for
  /// more precise hit testing (e.g. path-based).
  bool hitTest(Offset worldPoint) {
    if (!isVisible) return false;

    final inverse = Matrix4.tryInvert(worldTransform);
    if (inverse == null) return false;

    final local = MatrixUtils.transformPoint(inverse, worldPoint);
    return localBounds.contains(local);
  }

  // ---------------------------------------------------------------------------
  // Transform helpers
  // ---------------------------------------------------------------------------

  /// Translate this node by [dx], [dy] (modifies [localTransform]).
  void translate(double dx, double dy) {
    localTransform = Matrix4.translationValues(dx, dy, 0.0)
      ..multiply(localTransform);
  }

  /// Set absolute position (replaces translation component).
  void setPosition(double x, double y) {
    localTransform.setTranslationRaw(x, y, 0.0);
  }

  /// Current translation extracted from [localTransform].
  Offset get position {
    final t = localTransform.getTranslation();
    return Offset(t.x, t.y);
  }

  /// Rotate around [pivot] by [radians].
  void rotateAround(double radians, Offset pivot) {
    localTransform = _rotateAroundPivot(localTransform, radians, pivot);
  }

  /// Scale from [anchor] by [sx], [sy].
  void scaleFrom(double sx, double sy, Offset anchor) {
    localTransform = _scaleFromAnchor(localTransform, sx, sy, anchor);
  }

  // ---------------------------------------------------------------------------
  // Cloning
  // ---------------------------------------------------------------------------

  /// Create a deep copy of this node with a new unique ID.
  ///
  /// Uses the JSON serialization roundtrip to ensure all subclass
  /// properties are fully copied. The new node gets a fresh ID
  /// composed of the original + '_copy' suffix.
  CanvasNode clone() {
    final json = toJson();
    json['id'] = const Uuid().v4();
    return CanvasNodeFactory.fromJson(json);
  }

  // ---------------------------------------------------------------------------
  // Visitor
  // ---------------------------------------------------------------------------

  /// Accept a [NodeVisitor] for type-safe double-dispatch traversal.
  R accept<R>(NodeVisitor<R> visitor);

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  /// Serialize this node to JSON.
  ///
  /// Subclasses must override [toJson] and include `'nodeType'` so the
  /// factory deserializer can reconstruct the correct type.
  Map<String, dynamic> toJson();

  /// Serialize the common [CanvasNode] properties shared by all subclasses.
  Map<String, dynamic> baseToJson() {
    final json = <String, dynamic>{'id': id, 'name': name};

    // Only serialize non-default values to keep JSON compact.
    if (!_isIdentity(localTransform)) {
      json['transform'] = localTransform.storage.toList();
    }
    if (_opacity != 1.0) json['opacity'] = _opacity;
    if (blendMode != ui.BlendMode.srcOver) json['blendMode'] = blendMode.name;
    if (!isVisible) json['isVisible'] = false;
    if (isLocked) json['isLocked'] = true;
    if (effects.isNotEmpty) {
      json['effects'] = effects.map((e) => e.toJson()).toList();
    }
    if (accessibilityInfo != null) {
      json['a11y'] = accessibilityInfo!.toJson();
    }

    return json;
  }

  /// Restore common [CanvasNode] properties from [json].
  static void applyBaseFromJson(CanvasNode node, Map<String, dynamic> json) {
    node.name = (json['name'] as String?) ?? '';

    if (json['transform'] != null) {
      final storage = (json['transform'] as List).cast<num>();
      node.localTransform = Matrix4.fromList(
        storage.map((n) => n.toDouble()).toList(),
      );
    }

    if (json['opacity'] != null) {
      node.opacity = (json['opacity'] as num).toDouble();
    }
    if (json['blendMode'] != null) {
      node.blendMode = ui.BlendMode.values.firstWhere(
        (m) => m.name == json['blendMode'],
        orElse: () => ui.BlendMode.srcOver,
      );
    }
    if (json['isVisible'] != null) {
      node.isVisible = json['isVisible'] as bool;
    }
    if (json['isLocked'] != null) {
      node.isLocked = json['isLocked'] as bool;
    }
    if (json['effects'] != null) {
      node.effects =
          (json['effects'] as List<dynamic>)
              .map((e) => NodeEffect.fromJson(e as Map<String, dynamic>))
              .toList();
    }
    if (json['a11y'] != null) {
      node.accessibilityInfo = AccessibilityInfo.fromJson(
        json['a11y'] as Map<String, dynamic>,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Equality
  // ---------------------------------------------------------------------------

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CanvasNode && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => '$runtimeType(id: $id, name: "$name")';

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  static bool _isIdentity(Matrix4 m) {
    final s = m.storage;
    return s[0] == 1 &&
        s[1] == 0 &&
        s[2] == 0 &&
        s[3] == 0 &&
        s[4] == 0 &&
        s[5] == 1 &&
        s[6] == 0 &&
        s[7] == 0 &&
        s[8] == 0 &&
        s[9] == 0 &&
        s[10] == 1 &&
        s[11] == 0 &&
        s[12] == 0 &&
        s[13] == 0 &&
        s[14] == 0 &&
        s[15] == 1;
  }

  static Matrix4 _rotateAroundPivot(
    Matrix4 current,
    double radians,
    Offset pivot,
  ) {
    // T(pivot) · R(radians) · T(-pivot) · current
    final pre = Matrix4.translationValues(pivot.dx, pivot.dy, 0.0);
    final rot = Matrix4.rotationZ(radians);
    final post = Matrix4.translationValues(-pivot.dx, -pivot.dy, 0.0);
    return pre
      ..multiply(rot)
      ..multiply(post)
      ..multiply(current);
  }

  static Matrix4 _scaleFromAnchor(
    Matrix4 current,
    double sx,
    double sy,
    Offset anchor,
  ) {
    // T(anchor) · S(sx,sy) · T(-anchor) · current
    final pre = Matrix4.translationValues(anchor.dx, anchor.dy, 0.0);
    final scl = Matrix4.diagonal3Values(sx, sy, 1.0);
    final post = Matrix4.translationValues(-anchor.dx, -anchor.dy, 0.0);
    return pre
      ..multiply(scl)
      ..multiply(post)
      ..multiply(current);
  }
}
