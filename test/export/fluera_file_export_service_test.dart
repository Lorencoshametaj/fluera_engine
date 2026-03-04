import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/export/fluera_file_export_service.dart';
import 'package:fluera_engine/src/export/fluera_file_format.dart';
import 'package:fluera_engine/src/core/models/canvas_layer.dart';
import 'package:fluera_engine/src/drawing/models/pro_drawing_point.dart';
import 'package:fluera_engine/src/core/models/shape_type.dart';
import 'package:fluera_engine/src/core/models/digital_text_element.dart';
import 'package:fluera_engine/src/core/models/image_element.dart';

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  // ROUNDTRIP: build → load with real canvas data
  // ───────────────────────────────────────────────────────────────────────────

  group('FlueraFileExportService roundtrip', () {
    test('single layer with strokes survives roundtrip', () async {
      final stroke = ProStroke(
        id: 'stroke_1',
        points: [
          ProDrawingPoint(
            position: const Offset(10, 20),
            pressure: 0.5,
            timestamp: 100,
          ),
          ProDrawingPoint(
            position: const Offset(30, 40),
            pressure: 0.8,
            timestamp: 200,
          ),
        ],
        color: const Color(0xFFFF0000),
        baseWidth: 3.0,
        penType: ProPenType.ballpoint,
        createdAt: DateTime(2025, 1, 15, 10, 30),
      );

      final layer = CanvasLayer(
        id: 'layer_1',
        name: 'Main Layer',
        strokes: [stroke],
        shapes: [],
        texts: [],
        images: [],
        isVisible: true,
        isLocked: false,
        opacity: 1.0,
      );

      // Build .fluera file
      final bytes = await FlueraFileExportService.buildFlueraFile(
        layers: [layer],
        title: 'Test Canvas',
        backgroundColor: '#FFFFFFFF',
        paperType: 'blank',
      );

      // Verify it's a valid Fluera file
      expect(FlueraFileExportService.isFlueraFile(bytes), isTrue);

      // Load it back
      final result = FlueraFileExportService.loadFlueraFile(bytes);

      // Verify metadata
      expect(result.title, 'Test Canvas');
      expect(result.backgroundColor, '#FFFFFFFF');
      expect(result.paperType, 'blank');
      expect(result.version, 4); // FlueraFileFormat v4

      // Verify layers
      expect(result.layers.length, 1);
      final loadedLayer = result.layers.first;
      expect(loadedLayer.id, 'layer_1');
      expect(loadedLayer.name, 'Main Layer');
      expect(loadedLayer.isVisible, true);
      expect(loadedLayer.isLocked, false);
      expect(loadedLayer.opacity, 1.0);

      // Verify stroke data
      expect(loadedLayer.strokes.length, 1);
      final loadedStroke = loadedLayer.strokes.first;
      expect(loadedStroke.id, 'stroke_1');
      expect(loadedStroke.color, const Color(0xFFFF0000));
      expect(loadedStroke.baseWidth, 3.0);
      expect(loadedStroke.penType, ProPenType.ballpoint);
      expect(loadedStroke.points.length, 2);
      expect(loadedStroke.points[0].position.dx, 10.0);
      expect(loadedStroke.points[0].position.dy, 20.0);
      expect(loadedStroke.points[0].pressure, closeTo(0.5, 0.01));
      expect(loadedStroke.points[1].position.dx, 30.0);
      expect(loadedStroke.points[1].position.dy, 40.0);
    });

    test('multiple layers with shapes and text survive roundtrip', () async {
      final shape = GeometricShape(
        id: 'shape_1',
        type: ShapeType.rectangle,
        startPoint: const Offset(0, 0),
        endPoint: const Offset(100, 100),
        color: const Color(0xFF0000FF),
        strokeWidth: 2.0,
        filled: true,
        createdAt: DateTime(2025, 1, 15),
      );

      final text = DigitalTextElement(
        id: 'text_1',
        text: 'Hello Fluera!',
        position: const Offset(50, 50),
        color: const Color(0xFF000000),
        fontSize: 24.0,
        fontWeight: FontWeight.w400,
        fontFamily: 'Roboto',
        scale: 1.0,
        isOCR: false,
        createdAt: DateTime(2025, 1, 15),
      );

      final layers = [
        CanvasLayer(
          id: 'layer_shapes',
          name: 'Shapes',
          strokes: [],
          shapes: [shape],
          texts: [],
          images: [],
        ),
        CanvasLayer(
          id: 'layer_text',
          name: 'Text',
          strokes: [],
          shapes: [],
          texts: [text],
          images: [],
          isLocked: true,
          opacity: 0.8,
        ),
      ];

      final bytes = await FlueraFileExportService.buildFlueraFile(
        layers: layers,
        title: 'Multi-Layer Design',
      );

      final result = FlueraFileExportService.loadFlueraFile(bytes);

      // Verify both layers
      expect(result.layers.length, 2);

      // Layer 1: shapes
      final shapesLayer = result.layers[0];
      expect(shapesLayer.id, 'layer_shapes');
      expect(shapesLayer.shapes.length, 1);
      expect(shapesLayer.shapes.first.id, 'shape_1');
      expect(shapesLayer.shapes.first.type, ShapeType.rectangle);
      expect(shapesLayer.shapes.first.filled, true);

      // Layer 2: text
      final textLayer = result.layers[1];
      expect(textLayer.id, 'layer_text');
      expect(textLayer.isLocked, true);
      expect(textLayer.opacity, closeTo(0.8, 0.01));
      expect(textLayer.texts.length, 1);
      expect(textLayer.texts.first.id, 'text_1');
      expect(textLayer.texts.first.text, 'Hello Fluera!');
      expect(textLayer.texts.first.fontSize, 24.0);
      expect(textLayer.texts.first.fontFamily, 'Roboto');
    });

    test('images with path references survive roundtrip', () async {
      final image = ImageElement(
        id: 'img_1',
        imagePath: '/tmp/test_image.png',
        position: const Offset(200, 300),
        scale: 1.5,
        rotation: 0.25,
        createdAt: DateTime(2025, 1, 15),
        pageIndex: 0,
        opacity: 0.9,
      );

      final layer = CanvasLayer(
        id: 'layer_img',
        name: 'Images',
        strokes: [],
        shapes: [],
        texts: [],
        images: [image],
      );

      final bytes = await FlueraFileExportService.buildFlueraFile(
        layers: [layer],
      );

      final result = FlueraFileExportService.loadFlueraFile(bytes);

      expect(result.layers.first.images.length, 1);
      final loadedImage = result.layers.first.images.first;
      expect(loadedImage.id, 'img_1');
      expect(loadedImage.imagePath, '/tmp/test_image.png');
      expect(loadedImage.position.dx, 200.0);
      expect(loadedImage.position.dy, 300.0);
      expect(loadedImage.scale, closeTo(1.5, 0.01));
      expect(loadedImage.rotation, closeTo(0.25, 0.01));
      expect(loadedImage.opacity, closeTo(0.9, 0.01));
    });

    test('empty canvas produces valid file', () async {
      final bytes = await FlueraFileExportService.buildFlueraFile(
        layers: [],
        title: 'Empty',
      );

      expect(FlueraFileExportService.isFlueraFile(bytes), isTrue);

      final result = FlueraFileExportService.loadFlueraFile(bytes);
      expect(result.layers, isEmpty);
      expect(result.title, 'Empty');
    });

    test('file stats are correct', () async {
      final bytes = await FlueraFileExportService.buildFlueraFile(
        layers: [
          CanvasLayer(
            id: 'l1',
            name: 'L1',
            strokes: [],
            shapes: [],
            texts: [],
            images: [],
          ),
        ],
        title: 'Stats Test',
      );

      final result = FlueraFileExportService.loadFlueraFile(bytes);
      final stats = result.stats;

      expect(stats['version'], 4);
      expect(
        stats['sectionCount'],
        greaterThanOrEqualTo(3),
      ); // metadata + pageDir + pageData
      expect((stats['sectionsByType'] as Map)['metadata'], 1);
      expect((stats['sectionsByType'] as Map)['pageData'], 1);
      expect((stats['sectionsByType'] as Map)['pageDirectory'], 1);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // MULTI-PAGE roundtrip
  // ───────────────────────────────────────────────────────────────────────────

  group('Multi-page roundtrip', () {
    test('two pages with different content survive roundtrip', () async {
      final pages = <int, List<CanvasLayer>>{
        0: [
          CanvasLayer(
            id: 'p0_layer',
            name: 'Page 0',
            strokes: [
              ProStroke(
                id: 'p0_s1',
                points: [
                  ProDrawingPoint(
                    position: const Offset(5, 5),
                    pressure: 0.7,
                    timestamp: 50,
                  ),
                ],
                color: const Color(0xFF00FF00),
                baseWidth: 2.0,
                penType: ProPenType.pencil,
                createdAt: DateTime(2025, 1, 15),
              ),
            ],
            shapes: [],
            texts: [],
            images: [],
          ),
        ],
        1: [
          CanvasLayer(
            id: 'p1_layer',
            name: 'Page 1',
            strokes: [],
            shapes: [
              GeometricShape(
                id: 'p1_shape',
                type: ShapeType.circle,
                startPoint: const Offset(10, 10),
                endPoint: const Offset(50, 50),
                color: const Color(0xFFFF00FF),
                strokeWidth: 1.5,
                filled: false,
                createdAt: DateTime(2025, 1, 15),
              ),
            ],
            texts: [],
            images: [],
          ),
        ],
      };

      final bytes = await FlueraFileExportService.buildFlueraFileMultiPage(
        pages: pages,
        title: 'Multi-Page Doc',
      );

      final result = FlueraFileExportService.loadFlueraFile(bytes);

      expect(result.pageCount, 2);
      expect(result.pages.containsKey(0), isTrue);
      expect(result.pages.containsKey(1), isTrue);

      // Page 0: stroke
      final page0 = result.pages[0]!;
      expect(page0.first.strokes.length, 1);
      expect(page0.first.strokes.first.id, 'p0_s1');

      // Page 1: shape
      final page1 = result.pages[1]!;
      expect(page1.first.shapes.length, 1);
      expect(page1.first.shapes.first.id, 'p1_shape');
      expect(page1.first.shapes.first.type, ShapeType.circle);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // VALIDATION
  // ───────────────────────────────────────────────────────────────────────────

  group('Validation', () {
    test('isFlueraFile rejects non-fluera bytes', () {
      final randomBytes = Uint8List.fromList([0, 1, 2, 3, 4, 5]);
      expect(FlueraFileExportService.isFlueraFile(randomBytes), isFalse);
    });

    test('isFlueraFile rejects empty bytes', () {
      expect(FlueraFileExportService.isFlueraFile(Uint8List(0)), isFalse);
    });
  });
}
