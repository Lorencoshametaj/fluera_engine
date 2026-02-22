/// 🎯 SMART ANIMATE SNAPSHOT — Captures and interpolates animatable properties.
///
/// Provides a snapshot of a node's visual state that can be interpolated
/// between source and target states for smooth morphing transitions.
///
/// ```dart
/// final from = SmartAnimateSnapshot.capture(sourceNode);
/// final to = SmartAnimateSnapshot.capture(targetNode);
/// final mid = SmartAnimateSnapshot.interpolate(from, to, 0.5);
/// SmartAnimateSnapshot.apply(node, mid);
/// ```
library;

import 'dart:ui' as ui;
import 'package:flutter/material.dart' show Matrix4;
import '../core/scene_graph/canvas_node.dart';
import '../core/nodes/frame_node.dart'
    hide CrossAxisAlignment, MainAxisAlignment;

// =============================================================================
// ANIMATABLE PROPERTY KEYS
// =============================================================================

/// Canonical property names for Smart Animate snapshots.
abstract final class AnimatableProperty {
  static const positionX = 'position.x';
  static const positionY = 'position.y';
  static const width = 'width';
  static const height = 'height';
  static const opacity = 'opacity';
  static const rotation = 'rotation';
  static const fillColorR = 'fillColor.r';
  static const fillColorG = 'fillColor.g';
  static const fillColorB = 'fillColor.b';
  static const fillColorA = 'fillColor.a';
  static const strokeColorR = 'strokeColor.r';
  static const strokeColorG = 'strokeColor.g';
  static const strokeColorB = 'strokeColor.b';
  static const strokeColorA = 'strokeColor.a';
  static const borderRadius = 'borderRadius';
}

// =============================================================================
// SMART ANIMATE SNAPSHOT
// =============================================================================

/// Immutable snapshot of a node's animatable visual properties.
///
/// All values are stored as doubles for uniform interpolation.
/// Color channels are stored individually (0.0–1.0) for smooth lerp.
class SmartAnimateSnapshot {
  /// The node name used for matching.
  final String nodeName;

  /// The node type (for type-checked matching).
  final String nodeType;

  /// Property values (all doubles).
  final Map<String, double> properties;

  const SmartAnimateSnapshot({
    required this.nodeName,
    required this.nodeType,
    required this.properties,
  });

  /// Capture a snapshot of a [CanvasNode]'s animatable properties.
  factory SmartAnimateSnapshot.capture(CanvasNode node) {
    final props = <String, double>{};
    final bounds = node.localBounds;
    final pos = node.position;

    props[AnimatableProperty.positionX] = pos.dx;
    props[AnimatableProperty.positionY] = pos.dy;
    props[AnimatableProperty.width] = bounds.width;
    props[AnimatableProperty.height] = bounds.height;
    props[AnimatableProperty.opacity] = node.opacity;

    // Extract rotation from transform matrix (atan2 of sin/cos components).
    final m = node.localTransform;
    final rotation = _extractRotation(m);
    props[AnimatableProperty.rotation] = rotation;

    // Frame-specific properties.
    if (node is FrameNode) {
      if (node.fillColor != null) {
        props[AnimatableProperty.fillColorR] = node.fillColor!.r;
        props[AnimatableProperty.fillColorG] = node.fillColor!.g;
        props[AnimatableProperty.fillColorB] = node.fillColor!.b;
        props[AnimatableProperty.fillColorA] = node.fillColor!.a;
      }
      if (node.strokeColor != null) {
        props[AnimatableProperty.strokeColorR] = node.strokeColor!.r;
        props[AnimatableProperty.strokeColorG] = node.strokeColor!.g;
        props[AnimatableProperty.strokeColorB] = node.strokeColor!.b;
        props[AnimatableProperty.strokeColorA] = node.strokeColor!.a;
      }
      props[AnimatableProperty.borderRadius] = node.borderRadius;
    }

    return SmartAnimateSnapshot(
      nodeName: node.name,
      nodeType: node.runtimeType.toString(),
      properties: props,
    );
  }

  /// Interpolate between two snapshots at progress [t] (0.0–1.0).
  ///
  /// Properties present in both snapshots are linearly interpolated.
  /// Properties in only one snapshot are kept at that value.
  static SmartAnimateSnapshot interpolate(
    SmartAnimateSnapshot from,
    SmartAnimateSnapshot to,
    double t,
  ) {
    final result = <String, double>{};

    // Interpolate shared properties.
    final allKeys = {...from.properties.keys, ...to.properties.keys};
    for (final key in allKeys) {
      final a = from.properties[key];
      final b = to.properties[key];

      if (a != null && b != null) {
        result[key] = a + (b - a) * t;
      } else if (a != null) {
        result[key] = a;
      } else if (b != null) {
        result[key] = b;
      }
    }

    return SmartAnimateSnapshot(
      nodeName: from.nodeName,
      nodeType: from.nodeType,
      properties: result,
    );
  }

  /// Apply a snapshot's values to a [CanvasNode].
  ///
  /// Only modifies properties that exist in the snapshot.
  static void apply(CanvasNode node, SmartAnimateSnapshot snapshot) {
    final p = snapshot.properties;

    // Position.
    if (p.containsKey(AnimatableProperty.positionX) ||
        p.containsKey(AnimatableProperty.positionY)) {
      final pos = node.position;
      node.setPosition(
        p[AnimatableProperty.positionX] ?? pos.dx,
        p[AnimatableProperty.positionY] ?? pos.dy,
      );
      node.invalidateTransformCache();
    }

    // Opacity.
    if (p.containsKey(AnimatableProperty.opacity)) {
      node.opacity = p[AnimatableProperty.opacity]!.clamp(0.0, 1.0);
    }

    // Frame-specific.
    if (node is FrameNode) {
      // Fill color.
      if (p.containsKey(AnimatableProperty.fillColorR)) {
        node.fillColor = ui.Color.fromARGB(
          (p[AnimatableProperty.fillColorA]! * 255).round().clamp(0, 255),
          (p[AnimatableProperty.fillColorR]! * 255).round().clamp(0, 255),
          (p[AnimatableProperty.fillColorG]! * 255).round().clamp(0, 255),
          (p[AnimatableProperty.fillColorB]! * 255).round().clamp(0, 255),
        );
      }

      // Stroke color.
      if (p.containsKey(AnimatableProperty.strokeColorR)) {
        node.strokeColor = ui.Color.fromARGB(
          (p[AnimatableProperty.strokeColorA]! * 255).round().clamp(0, 255),
          (p[AnimatableProperty.strokeColorR]! * 255).round().clamp(0, 255),
          (p[AnimatableProperty.strokeColorG]! * 255).round().clamp(0, 255),
          (p[AnimatableProperty.strokeColorB]! * 255).round().clamp(0, 255),
        );
      }

      // Border radius.
      if (p.containsKey(AnimatableProperty.borderRadius)) {
        node.borderRadius = p[AnimatableProperty.borderRadius]!;
      }
    }
  }

  /// Serialization.
  Map<String, dynamic> toJson() => {
    'nodeName': nodeName,
    'nodeType': nodeType,
    'properties': properties,
  };

  factory SmartAnimateSnapshot.fromJson(Map<String, dynamic> json) {
    return SmartAnimateSnapshot(
      nodeName: json['nodeName'] as String,
      nodeType: json['nodeType'] as String,
      properties: (json['properties'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, (v as num).toDouble()),
      ),
    );
  }

  // ---- Helpers ----

  /// Extract rotation angle (radians) from a 4×4 transform matrix.
  static double _extractRotation(Matrix4 m) {
    final s = m.storage;
    // atan2(sin, cos) from the 2D rotation submatrix.
    return _atan2(s[1], s[0]);
  }

  static double _atan2(double y, double x) {
    // Use dart:math indirectly to avoid import conflict.
    if (x > 0) return _dartAtan(y / x);
    if (x < 0 && y >= 0) return _dartAtan(y / x) + 3.141592653589793;
    if (x < 0 && y < 0) return _dartAtan(y / x) - 3.141592653589793;
    if (x == 0 && y > 0) return 3.141592653589793 / 2;
    if (x == 0 && y < 0) return -3.141592653589793 / 2;
    return 0.0; // x == 0 && y == 0
  }

  static double _dartAtan(double x) {
    // Taylor series approximation for small values, otherwise use identity.
    // This avoids importing dart:math when we just need atan2.
    // For production, we use the known formula.
    double result = x;
    double term = x;
    for (int n = 1; n <= 20; n++) {
      term *= -x * x * (2 * n - 1) / (2 * n + 1);
      result += term / (2 * n + 1);
      if (term.abs() < 1e-15) break;
    }
    return result;
  }
}
