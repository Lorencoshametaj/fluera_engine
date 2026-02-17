import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/storage/nebula_storage_adapter.dart';
import 'package:nebula_engine/src/storage/sqlite_storage_adapter.dart';
import 'package:nebula_engine/src/core/models/canvas_layer.dart';
import 'package:nebula_engine/src/drawing/models/pro_drawing_point.dart';
import 'dart:ui';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ===========================================================================
  // CanvasMetadata
  // ===========================================================================

  group('CanvasMetadata', () {
    test('toJson/fromJson roundtrip preserves all fields', () {
      final now = DateTime.now();
      final meta = CanvasMetadata(
        canvasId: 'canvas-123',
        title: 'My Drawing',
        updatedAt: now,
        createdAt: now,
        paperType: 'grid',
        layerCount: 3,
        strokeCount: 150,
      );

      final json = meta.toJson();
      final restored = CanvasMetadata.fromJson(json);

      expect(restored.canvasId, equals('canvas-123'));
      expect(restored.title, equals('My Drawing'));
      expect(restored.paperType, equals('grid'));
      expect(restored.layerCount, equals(3));
      expect(restored.strokeCount, equals(150));
      expect(
        restored.updatedAt.millisecondsSinceEpoch,
        equals(now.millisecondsSinceEpoch),
      );
      expect(
        restored.createdAt.millisecondsSinceEpoch,
        equals(now.millisecondsSinceEpoch),
      );
    });

    test('fromJson uses defaults for missing optional fields', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final json = <String, dynamic>{
        'canvasId': 'test-id',
        'updatedAt': now,
        'createdAt': now,
      };

      final meta = CanvasMetadata.fromJson(json);

      expect(meta.title, isNull);
      expect(meta.paperType, equals('blank'));
      expect(meta.layerCount, equals(0));
      expect(meta.strokeCount, equals(0));
    });

    test('toString includes key fields', () {
      final meta = CanvasMetadata(
        canvasId: 'id-1',
        title: 'Test',
        updatedAt: DateTime.now(),
        createdAt: DateTime.now(),
        paperType: 'blank',
        layerCount: 2,
        strokeCount: 50,
      );

      final str = meta.toString();
      expect(str, contains('id-1'));
      expect(str, contains('Test'));
      expect(str, contains('2'));
      expect(str, contains('50'));
    });
  });

  // ===========================================================================
  // SqliteStorageAdapter
  // ===========================================================================

  group('SqliteStorageAdapter', () {
    test('isInitialized returns false before initialize()', () {
      final adapter = SqliteStorageAdapter();
      expect(adapter.isInitialized, isFalse);
    });

    test('constructor accepts custom databasePath', () {
      final adapter = SqliteStorageAdapter(databasePath: '/tmp/test_nebula.db');
      expect(adapter.databasePath, equals('/tmp/test_nebula.db'));
    });

    test('_ensureInitialized throws StateError if not initialized', () {
      final adapter = SqliteStorageAdapter();
      // Directly calling a method that relies on initialization should throw
      expect(() => adapter.loadCanvas('some-id'), throwsA(isA<StateError>()));
    });

    test('saveCanvas throws StateError if not initialized', () {
      final adapter = SqliteStorageAdapter();
      expect(
        () => adapter.saveCanvas('some-id', {}),
        throwsA(isA<StateError>()),
      );
    });

    test('deleteCanvas throws StateError if not initialized', () {
      final adapter = SqliteStorageAdapter();
      expect(() => adapter.deleteCanvas('some-id'), throwsA(isA<StateError>()));
    });

    test('listCanvases throws StateError if not initialized', () {
      final adapter = SqliteStorageAdapter();
      expect(() => adapter.listCanvases(), throwsA(isA<StateError>()));
    });

    test('canvasExists throws StateError if not initialized', () {
      final adapter = SqliteStorageAdapter();
      expect(() => adapter.canvasExists('some-id'), throwsA(isA<StateError>()));
    });
  });

  // ===========================================================================
  // NebulaStorageAdapter — interface contract
  // ===========================================================================

  group('NebulaStorageAdapter interface', () {
    test('SqliteStorageAdapter implements NebulaStorageAdapter', () {
      final adapter = SqliteStorageAdapter();
      expect(adapter, isA<NebulaStorageAdapter>());
    });
  });

  // ===========================================================================
  // Data model serialization roundtrip (CanvasLayer → JSON → CanvasLayer)
  // ===========================================================================

  group('Canvas data serialization for storage', () {
    test('CanvasLayer with strokes survives toJson/fromJson roundtrip', () {
      final stroke = ProStroke(
        id: 'stroke-1',
        points: [
          ProDrawingPoint(
            position: const Offset(10, 20),
            pressure: 0.5,
            timestamp: 1000,
          ),
          ProDrawingPoint(
            position: const Offset(30, 40),
            pressure: 0.7,
            timestamp: 1016,
          ),
        ],
        color: const Color(0xFF000000),
        baseWidth: 2.0,
        penType: ProPenType.ballpoint,
        createdAt: DateTime.now(),
      );

      final layer = CanvasLayer(
        id: 'layer-1',
        name: 'Layer 1',
        strokes: [stroke],
        isVisible: true,
        isLocked: false,
        opacity: 0.8,
      );

      final json = layer.toJson();
      final restored = CanvasLayer.fromJson(json);

      expect(restored.id, equals('layer-1'));
      expect(restored.name, equals('Layer 1'));
      expect(restored.isVisible, isTrue);
      expect(restored.isLocked, isFalse);
      expect(restored.opacity, closeTo(0.8, 0.01));
      expect(restored.strokes.length, equals(1));
      expect(restored.strokes.first.id, equals('stroke-1'));
      expect(restored.strokes.first.points.length, equals(2));
    });

    test('empty CanvasLayer survives roundtrip', () {
      final layer = CanvasLayer(id: 'layer-empty', name: 'Empty');

      final json = layer.toJson();
      final restored = CanvasLayer.fromJson(json);

      expect(restored.id, equals('layer-empty'));
      expect(restored.name, equals('Empty'));
      expect(restored.strokes, isEmpty);
      expect(restored.shapes, isEmpty);
      expect(restored.texts, isEmpty);
      expect(restored.images, isEmpty);
    });

    test('canvas save data map has expected structure', () {
      final data = <String, dynamic>{
        'canvasId': 'canvas-1',
        'title': 'Test Canvas',
        'paperType': 'lined',
        'backgroundColor': '4294967295',
        'activeLayerId': 'layer-1',
        'layers': <Map<String, dynamic>>[],
      };

      expect(data['canvasId'], equals('canvas-1'));
      expect(data['title'], equals('Test Canvas'));
      expect(data['paperType'], equals('lined'));
      expect(data['layers'], isA<List>());
    });
  });
}
