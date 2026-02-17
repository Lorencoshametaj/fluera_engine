import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/scene_graph/canvas_node.dart';
import 'package:nebula_engine/src/core/scene_graph/node_visitor.dart';
import 'package:nebula_engine/src/systems/style_system.dart';

/// Concrete leaf node for testing.
class _TestNode extends CanvasNode {
  _TestNode({required super.id, super.name = ''});

  @override
  Rect get localBounds => Rect.zero;

  @override
  Map<String, dynamic> toJson() => {'id': id, 'nodeType': 'test'};

  @override
  R accept<R>(NodeVisitor<R> visitor) =>
      throw UnimplementedError('not needed for tests');
}

void main() {
  // =========================================================================
  // Design Tokens
  // =========================================================================

  group('ColorToken', () {
    test('constructs with name and value', () {
      final token = ColorToken(name: 'Primary Blue', value: Colors.blue);
      expect(token.name, 'Primary Blue');
      expect(token.value, Colors.blue);
    });

    test('toJson serializes correctly', () {
      final token = ColorToken(name: 'Primary Blue', value: Colors.blue);
      final json = token.toJson();
      expect(json['name'], 'Primary Blue');
      expect(json.containsKey('value'), isTrue);
    });

    test('fromJson round-trips', () {
      final original = ColorToken(name: 'Red', value: Colors.red);
      final json = original.toJson();
      final restored = ColorToken.fromJson(json);
      expect(restored.name, 'Red');
    });
  });

  group('TypographyToken', () {
    test('constructs with font properties', () {
      final token = TypographyToken(
        name: 'Heading',
        fontFamily: 'Roboto',
        fontSize: 24,
        fontWeight: FontWeight.bold,
      );
      expect(token.name, 'Heading');
      expect(token.fontSize, 24);
      expect(token.fontWeight, FontWeight.bold);
    });

    test('toTextStyle returns a TextStyle', () {
      final token = TypographyToken(
        name: 'Body',
        fontFamily: 'Inter',
        fontSize: 16,
        fontWeight: FontWeight.normal,
      );
      final style = token.toTextStyle();
      expect(style, isA<TextStyle>());
      expect(style.fontSize, 16);
      expect(style.fontFamily, 'Inter');
    });

    test('toJson serializes correctly', () {
      final token = TypographyToken(
        name: 'Body',
        fontFamily: 'Inter',
        fontSize: 16,
        fontWeight: FontWeight.normal,
      );
      final json = token.toJson();
      expect(json['name'], 'Body');
      expect(json['fontSize'], 16);
    });
  });

  group('SpacingToken', () {
    test('constructs with name and value', () {
      final token = SpacingToken(name: 'Small', value: 8.0);
      expect(token.name, 'Small');
      expect(token.value, 8.0);
    });

    test('toJson serializes correctly', () {
      final token = SpacingToken(name: 'Small', value: 8.0);
      final json = token.toJson();
      expect(json['name'], 'Small');
      expect(json['value'], 8.0);
    });

    test('fromJson round-trips', () {
      final original = SpacingToken(name: 'Large', value: 24.0);
      final json = original.toJson();
      final restored = SpacingToken.fromJson(json);
      expect(restored.name, 'Large');
      expect(restored.value, 24.0);
    });
  });

  // =========================================================================
  // StyleDefinition
  // =========================================================================

  group('StyleDefinition', () {
    test('constructs with id and name', () {
      final style = StyleDefinition(id: 's1', name: 'Card Style');
      expect(style.id, 's1');
      expect(style.name, 'Card Style');
    });

    test('fillColor and strokeColor are optional', () {
      final style = StyleDefinition(id: 's1', name: 'Minimal');
      expect(style.fillColor, isNull);
      expect(style.strokeColor, isNull);
    });

    test('clone creates independent copy', () {
      final style = StyleDefinition(
        id: 's1',
        name: 'Original',
        fillColor: Colors.red,
        strokeWidth: 3.0,
      );
      final copy = style.clone();
      expect(copy.id, style.id);
      expect(copy.fillColor, Colors.red);
      expect(copy.strokeWidth, 3.0);
      // Mutating copy should not affect original
      copy.name = 'Modified';
      expect(style.name, 'Original');
    });

    test('toJson serializes correctly', () {
      final style = StyleDefinition(
        id: 's1',
        name: 'Card',
        fillColor: Colors.blue,
        cornerRadius: 12,
      );
      final json = style.toJson();
      expect(json['id'], 's1');
      expect(json['name'], 'Card');
      expect(json.containsKey('fillColor'), isTrue);
      expect(json['cornerRadius'], 12);
    });

    test('fromJson round-trips', () {
      final original = StyleDefinition(
        id: 's1',
        name: 'Card',
        fillColor: Colors.blue,
        strokeWidth: 2.0,
        opacity: 0.8,
      );
      final json = original.toJson();
      final restored = StyleDefinition.fromJson(json);
      expect(restored.id, 's1');
      expect(restored.name, 'Card');
      expect(restored.strokeWidth, 2.0);
      expect(restored.opacity, 0.8);
    });

    test('applyTo sets opacity on node', () {
      final style = StyleDefinition(id: 's1', opacity: 0.5);
      final node = _TestNode(id: 'n1');
      style.applyTo(node);
      expect(node.opacity, 0.5);
    });
  });

  // =========================================================================
  // StyleRegistry
  // =========================================================================

  group('StyleRegistry', () {
    late StyleRegistry registry;

    setUp(() {
      registry = StyleRegistry();
    });

    // ── Registration ───────────────────────────────────────────────────

    group('register / get', () {
      test('registers and retrieves a style', () {
        registry.register(StyleDefinition(id: 's1', name: 'Style 1'));
        final retrieved = registry.getStyle('s1');
        expect(retrieved, isNotNull);
        expect(retrieved!.name, 'Style 1');
      });

      test('returns null for unknown style', () {
        expect(registry.getStyle('unknown'), isNull);
      });

      test('removeStyle removes by id', () {
        registry.register(StyleDefinition(id: 's1', name: 'Style 1'));
        registry.removeStyle('s1');
        expect(registry.getStyle('s1'), isNull);
      });
    });

    // ── Apply / Link ───────────────────────────────────────────────────

    group('apply / link', () {
      test('applyStyle links node to style', () {
        final style = StyleDefinition(
          id: 's1',
          name: 'Highlight',
          fillColor: Colors.yellow,
        );
        registry.register(style);
        final node = _TestNode(id: 'n1');
        registry.applyStyle('s1', node);

        expect(registry.hasStyle('n1'), isTrue);
        expect(registry.usageCount('s1'), 1);
      });

      test('styleForNode returns linked style', () {
        final style = StyleDefinition(id: 's1', name: 'Test');
        registry.register(style);
        final node = _TestNode(id: 'n1');
        registry.applyStyle('s1', node);

        final linked = registry.styleForNode('n1');
        expect(linked, isNotNull);
        expect(linked!.id, 's1');
      });

      test('detachNode removes link', () {
        final style = StyleDefinition(id: 's1', name: 'Test');
        registry.register(style);
        final node = _TestNode(id: 'n1');
        registry.applyStyle('s1', node);
        registry.detachNode('n1');

        expect(registry.hasStyle('n1'), isFalse);
        expect(registry.usageCount('s1'), 0);
      });

      test('removeStyle detaches all linked nodes', () {
        final style = StyleDefinition(id: 's1', name: 'Test');
        registry.register(style);
        registry.applyStyle('s1', _TestNode(id: 'n1'));
        registry.applyStyle('s1', _TestNode(id: 'n2'));
        expect(registry.usageCount('s1'), 2);

        registry.removeStyle('s1');
        expect(registry.hasStyle('n1'), isFalse);
        expect(registry.hasStyle('n2'), isFalse);
      });
    });

    // ── Update Style ───────────────────────────────────────────────────

    group('updateStyle', () {
      test('updates style and re-applies to linked nodes', () {
        final style = StyleDefinition(id: 's1', name: 'Test', opacity: 1.0);
        registry.register(style);
        final node = _TestNode(id: 'n1');
        registry.applyStyle('s1', node);

        registry.updateStyle('s1', (s) {
          s.opacity = 0.5;
        }, (id) => id == 'n1' ? node : null);

        expect(node.opacity, 0.5);
      });
    });

    // ── Serialization ──────────────────────────────────────────────────

    group('serialization', () {
      test('toJson / loadFromJson round-trips', () {
        registry.register(StyleDefinition(id: 's1', name: 'Card'));
        registry.register(StyleDefinition(id: 's2', name: 'Heading'));

        final json = registry.toJson();
        final restored = StyleRegistry();
        restored.loadFromJson(json);

        expect(restored.getStyle('s1'), isNotNull);
        expect(restored.getStyle('s2'), isNotNull);
        expect(restored.getStyle('s1')!.name, 'Card');
      });
    });
  });
}
