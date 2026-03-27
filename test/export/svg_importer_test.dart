import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/export/svg_importer.dart';
import 'package:fluera_engine/src/core/nodes/group_node.dart';
import 'package:fluera_engine/src/core/nodes/path_node.dart';
import 'package:fluera_engine/src/core/nodes/text_node.dart';
import 'package:fluera_engine/src/core/vector/vector_path.dart';

void main() {
  late SvgImporter importer;

  setUp(() {
    importer = SvgImporter();
  });

  group('SvgImporter', () {
    test('parses empty SVG', () {
      final node = importer.parse('<svg></svg>');
      expect(node, isA<GroupNode>());
      expect(node.children, isEmpty);
    });

    test('parses rect element', () {
      final node = importer.parse(
        '<svg><rect x="10" y="20" width="100" height="50" fill="#ff0000"/></svg>',
      );
      expect(node.children.length, 1);
      expect(node.children.first, isA<PathNode>());
      final path = (node.children.first as PathNode).path;
      // Rect creates 4 line segments + move + close.
      expect(path.segments.length, greaterThanOrEqualTo(4));
    });

    test('parses circle element', () {
      final node = importer.parse(
        '<svg><circle cx="50" cy="50" r="25" fill="blue"/></svg>',
      );
      expect(node.children.length, 1);
      expect(node.children.first, isA<PathNode>());
    });

    test('parses ellipse element', () {
      final node = importer.parse(
        '<svg><ellipse cx="100" cy="50" rx="80" ry="40" fill="green"/></svg>',
      );
      expect(node.children.length, 1);
    });

    test('parses line element', () {
      final node = importer.parse(
        '<svg><line x1="0" y1="0" x2="100" y2="100" stroke="black"/></svg>',
      );
      expect(node.children.length, 1);
      final path = (node.children.first as PathNode).path;
      expect(path.segments.length, 2); // Move + Line.
    });

    test('parses path with cubic bezier', () {
      final node = importer.parse(
        '<svg><path d="M 0 0 C 25 50 75 50 100 0" fill="none" stroke="red"/></svg>',
      );
      expect(node.children.length, 1);
      final path = (node.children.first as PathNode).path;
      expect(path.segments.whereType<CubicSegment>().length, 1);
    });

    test('parses path with relative commands', () {
      final node = importer.parse(
        '<svg><path d="M 10 10 l 50 0 l 0 50 z" fill="black"/></svg>',
      );
      expect(node.children.length, 1);
      final path = (node.children.first as PathNode).path;
      expect(path.isClosed, isTrue);
    });

    test('parses polygon element', () {
      final node = importer.parse(
        '<svg><polygon points="50,0 100,100 0,100" fill="yellow"/></svg>',
      );
      expect(node.children.length, 1);
      final path = (node.children.first as PathNode).path;
      expect(path.isClosed, isTrue);
    });

    test('parses text element', () {
      final node = importer.parse(
        '<svg><text x="10" y="30">Hello World</text></svg>',
      );
      expect(node.children.length, 1);
      expect(node.children.first, isA<TextNode>());
      expect((node.children.first as TextNode).textElement.text, 'Hello World');
    });

    test('parses group with children', () {
      final node = importer.parse(
        '<svg><g id="layer1">'
        '<rect x="0" y="0" width="50" height="50" fill="red"/>'
        '<circle cx="25" cy="25" r="10" fill="blue"/>'
        '</g></svg>',
      );
      expect(node.children.length, 1);
      final layer = node.children.first as GroupNode;
      expect(layer.name, 'layer1');
      expect(layer.children.length, 2);
    });

    test('parses stroke and fill colors', () {
      final node = importer.parse(
        '<svg><rect x="0" y="0" width="100" height="100" fill="#00ff00" stroke="rgb(255, 0, 0)" stroke-width="2"/></svg>',
      );
      // No crash = colors parsed correctly.
      expect(node.children.length, 1);
    });

    test('parses opacity attribute', () {
      final node = importer.parse(
        '<svg><rect x="0" y="0" width="50" height="50" fill="red" opacity="0.5"/></svg>',
      );
      expect(node.children.first.opacity, closeTo(0.5, 0.01));
    });

    test('ignores unsupported elements gracefully', () {
      final node = importer.parse(
        '<svg><defs><linearGradient/></defs><rect x="0" y="0" width="50" height="50" fill="red"/></svg>',
      );
      // Should not crash, only the rect is imported.
      expect(node.children.length, greaterThanOrEqualTo(1));
    });
  });
}
