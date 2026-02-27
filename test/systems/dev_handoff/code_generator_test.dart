import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/systems/dev_handoff/inspect_engine.dart';
import 'package:fluera_engine/src/systems/dev_handoff/code_generator.dart';
import 'dart:ui';

void main() {
  group('CodeGenerator Tests', () {
    test('generateFlutter returns formatted dart code', () {
      final report = InspectReport(
        nodeId: 'rect-1',
        nodeName: 'Rectangle 1',
        nodeType: 'ShapeNode',
        position: const Offset(10, 20),
        size: const Size(100, 50),
        rotation: 0,
        worldBounds: const Rect.fromLTWH(10, 20, 100, 50),
        opacity: 0.8,
        blendMode: 'srcOver',
        fills: [InspectFill(color: const Color(0xFFFF0000))],
        stroke: InspectStroke(color: const Color(0xFF00FF00), width: 2.0),
        cornerRadius: 8.0,
        effects: [
          InspectEffect(
            type: 'DropShadowEffect',
            parameters: {
              'offset': {'dx': 0, 'dy': 4},
              'blur': 4.0,
              'color': '#000000',
            },
          ),
        ],
        typography: null,
        tokenReferences: [],
      );

      final generated = CodeGenerator.generateFlutter(report);

      expect(generated.language, 'dart');
      final code = generated.code;
      expect(code, contains('Container('));
      expect(code, contains('width: 100.0,'));
      expect(code, contains('height: 50.0,'));
      expect(code, contains('color: Color(0xFFFF0000),'));
      expect(code, contains('border: Border.all('));
      expect(code, contains('color: Color(0xFF00FF00),'));
      expect(code, contains('width: 2.0,'));
      expect(code, contains('borderRadius: BorderRadius.circular(8.0),'));
      expect(code, contains('boxShadow: ['));
      expect(code, contains('offset: Offset(0, 4),'));
      expect(code, contains('blurRadius: 4.0,'));
      expect(code, contains('// opacity: 0.80'));
    });

    test('generateCSS returns formatted CSS code', () {
      final report = InspectReport(
        nodeId: 'rect-1',
        nodeName: 'Rectangle 1',
        nodeType: 'ShapeNode',
        position: const Offset(10, 20),
        size: const Size(100, 50),
        rotation: 0,
        worldBounds: const Rect.fromLTWH(10, 20, 100, 50),
        opacity: 1.0,
        blendMode: 'srcOver',
        fills: [InspectFill(color: const Color(0xFFFF0000))],
        effects: [],
        tokenReferences: [],
      );

      final generated = CodeGenerator.generateCSS(report);

      expect(generated.language, 'css');
      final code = generated.code;
      expect(code, contains('.rectangle-1 {'));
      expect(code, contains('width: 100px;'));
      expect(code, contains('height: 50px;'));
      expect(code, contains('background-color: #FF0000;'));
      expect(code, contains('position: absolute;'));
      expect(code, contains('left: 10px;'));
      expect(code, contains('top: 20px;'));
    });

    test('generateSwiftUI returns formatted SwiftUI code', () {
      final report = InspectReport(
        nodeId: 'text-1',
        nodeName: 'Label',
        nodeType: 'TextNode',
        position: const Offset(0, 0),
        size: const Size(200, 40),
        rotation: 0,
        worldBounds: const Rect.fromLTWH(0, 0, 200, 40),
        opacity: 1.0,
        blendMode: 'srcOver',
        fills: [],
        typography: InspectTypography(
          fontFamily: 'SF Pro',
          fontSize: 16.0,
          color: const Color(0xFF333333),
        ),
        effects: [],
        tokenReferences: [],
      );

      final generated = CodeGenerator.generateSwiftUI(report);

      expect(generated.language, 'swift');
      final code = generated.code;
      expect(code, contains('Text("Text")'));
      expect(code, contains('.font(.custom("SF Pro", size: 16))'));
      expect(code, contains('.foregroundColor(Color(hex: "#333333"))'));
      expect(code, contains('.frame(width: 200, height: 40)'));
    });
  });
}
