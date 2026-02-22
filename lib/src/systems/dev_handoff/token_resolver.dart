/// 🔗 TOKEN RESOLVER — Maps node properties back to design tokens.
library;

import 'dart:ui';

import '../../core/scene_graph/canvas_node.dart';
import '../../core/nodes/text_node.dart';
import '../../core/nodes/frame_node.dart';
import '../../core/scene_graph/paint_stack_mixin.dart';
import '../../core/effects/paint_stack.dart';
import '../design_variables.dart';

/// A resolved reference from a node property to a design token.
class TokenReference {
  final String property;
  final String collectionName;
  final String variableName;
  final String modeId;
  final dynamic value;

  const TokenReference({
    required this.property,
    required this.collectionName,
    required this.variableName,
    required this.modeId,
    required this.value,
  });

  Map<String, dynamic> toJson() => {
    'property': property,
    'collection': collectionName,
    'variable': variableName,
    'mode': modeId,
  };

  @override
  String toString() =>
      'TokenReference($property → $collectionName/$variableName @$modeId)';
}

/// Resolves node property values to design token references.
class TokenResolver {
  final List<VariableCollection> collections;
  final Map<String, String> activeModes;

  const TokenResolver({required this.collections, this.activeModes = const {}});

  /// Resolve all properties of a node to token references.
  List<TokenReference> resolveAll(CanvasNode node) {
    final refs = <TokenReference>[];

    // Resolve fill color.
    final fillColor = _extractFillColor(node);
    if (fillColor != null) {
      final ref = resolveColor('fill-color', fillColor);
      if (ref != null) refs.add(ref);
    }

    // Resolve stroke color.
    final strokeColor = _extractStrokeColor(node);
    if (strokeColor != null) {
      final ref = resolveColor('stroke-color', strokeColor);
      if (ref != null) refs.add(ref);
    }

    // Resolve font size.
    final fontSize = _extractFontSize(node);
    if (fontSize != null) {
      final ref = resolveNumber('font-size', fontSize);
      if (ref != null) refs.add(ref);
    }

    // Resolve corner radius.
    final radius = _extractCornerRadius(node);
    if (radius != null && radius > 0) {
      final ref = resolveNumber('corner-radius', radius);
      if (ref != null) refs.add(ref);
    }

    // Resolve spacing.
    if (node is FrameNode) {
      final ref = resolveNumber('spacing', node.spacing);
      if (ref != null) refs.add(ref);
    }

    return refs;
  }

  TokenReference? resolveColor(String property, Color color) {
    final colorInt = color.toARGB32();
    for (final collection in collections) {
      final modeId = activeModes[collection.id] ?? _defaultMode(collection);
      if (modeId == null) continue;

      for (final variable in collection.variables) {
        if (variable.type != DesignVariableType.color) continue;
        final tokenValue = variable.values[modeId];
        if (tokenValue is int && tokenValue == colorInt) {
          return TokenReference(
            property: property,
            collectionName: collection.name,
            variableName: variable.name,
            modeId: modeId,
            value: tokenValue,
          );
        }
      }
    }
    return null;
  }

  TokenReference? resolveNumber(String property, double value) {
    for (final collection in collections) {
      final modeId = activeModes[collection.id] ?? _defaultMode(collection);
      if (modeId == null) continue;

      for (final variable in collection.variables) {
        if (variable.type != DesignVariableType.number) continue;
        final tokenValue = variable.values[modeId];
        if (tokenValue is num && (tokenValue.toDouble() - value).abs() < 0.01) {
          return TokenReference(
            property: property,
            collectionName: collection.name,
            variableName: variable.name,
            modeId: modeId,
            value: tokenValue,
          );
        }
      }
    }
    return null;
  }

  TokenReference? resolveString(String property, String value) {
    for (final collection in collections) {
      final modeId = activeModes[collection.id] ?? _defaultMode(collection);
      if (modeId == null) continue;

      for (final variable in collection.variables) {
        if (variable.type != DesignVariableType.string) continue;
        final tokenValue = variable.values[modeId];
        if (tokenValue is String && tokenValue == value) {
          return TokenReference(
            property: property,
            collectionName: collection.name,
            variableName: variable.name,
            modeId: modeId,
            value: tokenValue,
          );
        }
      }
    }
    return null;
  }

  // -- Private helpers -------------------------------------------------------

  Color? _extractFillColor(CanvasNode node) {
    if (node is PaintStackMixin && node.fills.isNotEmpty) {
      return node.fills.first.color;
    }
    if (node is FrameNode) return node.fillColor;
    return null;
  }

  Color? _extractStrokeColor(CanvasNode node) {
    if (node is PaintStackMixin && node.strokes.isNotEmpty) {
      return node.strokes.first.color;
    }
    if (node is FrameNode) return node.strokeColor;
    return null;
  }

  double? _extractFontSize(CanvasNode node) {
    if (node is TextNode) return node.textElement.fontSize;
    return null;
  }

  double? _extractCornerRadius(CanvasNode node) {
    if (node is FrameNode) return node.borderRadius;
    return null;
  }

  String? _defaultMode(VariableCollection collection) {
    if (collection.modes.isEmpty) return null;
    return collection.modes.first.id;
  }
}
