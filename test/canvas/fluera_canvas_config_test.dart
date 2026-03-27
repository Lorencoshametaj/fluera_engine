import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/canvas/fluera_canvas_config.dart';
import 'package:fluera_engine/src/core/models/pdf_text_rect.dart';
import 'package:fluera_engine/src/layers/layer_controller.dart';

/// Minimal mock for FlueraPdfProvider.
class _MockPdfProvider extends FlueraPdfProvider {
  @override
  int get pageCount => 0;
  @override
  Size pageSize(int _) => Size.zero;
  @override
  Future<bool> loadDocument(List<int> _) async => true;
  @override
  Future<ui.Image?> renderPage({
    required int pageIndex,
    required double scale,
    required Size targetSize,
  }) async => null;
  @override
  Future<List<PdfTextRect>> extractTextGeometry(int _) async => [];
  @override
  Future<String> getPageText(int _) async => '';
  @override
  void dispose() {}
}

/// Minimal mock for FlueraPresenceProvider.
class _MockPresence extends FlueraPresenceProvider {
  @override
  final activeUsers = ValueNotifier<List<FlueraPresenceUser>>([]);
  @override
  void joinCanvas(String _) {}
  @override
  void leaveCanvas() {}
}

/// Minimal mock for FlueraPermissionProvider.
class _MockPermissions extends FlueraPermissionProvider {
  @override
  Future<bool> canEdit(String _) async => true;
  @override
  Future<bool> canView(String _) async => true;
  @override
  String get currentUserRole => 'editor';
}

void main() {
  late LayerController layerController;

  setUp(() {
    layerController = LayerController();
    layerController.enableDeltaTracking = false;
  });

  tearDown(() {
    layerController.dispose();
  });

  // ===========================================================================
  // FlueraCanvasConfig — validate
  // ===========================================================================

  group('FlueraCanvasConfig - validate', () {
    test('minimal config reports no-persistence warning', () {
      final config = FlueraCanvasConfig(layerController: layerController);
      final issues = config.validate();
      expect(issues.length, 1);
      expect(issues.first, contains('persistence'));
    });

    test('with onSaveCanvas — no persistence warning', () {
      final config = FlueraCanvasConfig(
        layerController: layerController,
        onSaveCanvas: (_) async {},
        onLoadCanvas: (_) async => null,
      );
      final issues = config.validate();
      expect(issues, isEmpty);
    });

    test('pdfProvider without picker warns', () {
      final config = FlueraCanvasConfig(
        layerController: layerController,
        onSaveCanvas: (_) async {},
        onLoadCanvas: (_) async => null,
        pdfProvider: _MockPdfProvider(),
      );
      final issues = config.validate();
      expect(issues.length, 1);
      expect(issues.first, contains('onPickPdfFile'));
    });

    test('presence without permissions warns', () {
      final config = FlueraCanvasConfig(
        layerController: layerController,
        onSaveCanvas: (_) async {},
        onLoadCanvas: (_) async => null,
        presence: _MockPresence(),
      );
      final issues = config.validate();
      expect(issues.length, 1);
      expect(issues.first, contains('permissions'));
    });

    test('fully configured — no issues', () {
      final config = FlueraCanvasConfig(
        layerController: layerController,
        onSaveCanvas: (_) async {},
        onLoadCanvas: (_) async => null,
        pdfProvider: _MockPdfProvider(),
        onPickPdfFile: () async => null,
        presence: _MockPresence(),
        permissions: _MockPermissions(),
      );
      final issues = config.validate();
      expect(issues, isEmpty);
    });
  });

  // ===========================================================================
  // FlueraSubscriptionTier
  // ===========================================================================

  group('FlueraSubscriptionTier', () {
    test('free cannot use cloud sync', () {
      expect(FlueraSubscriptionTier.free.canUseCloudSync, isFalse);
    });

    test('plus can use cloud sync and collaborate', () {
      expect(FlueraSubscriptionTier.plus.canUseCloudSync, isTrue);
      expect(FlueraSubscriptionTier.plus.canCollaborate, isTrue);
    });

    test('pro can use everything', () {
      expect(FlueraSubscriptionTier.pro.canUseCloudSync, isTrue);
      expect(FlueraSubscriptionTier.pro.canCollaborate, isTrue);
      expect(FlueraSubscriptionTier.pro.canUseAIFilters, isTrue);
    });

    test('essential cannot use cloud sync', () {
      expect(FlueraSubscriptionTier.essential.canUseCloudSync, isFalse);
    });
  });

  // ===========================================================================
  // FlueraCanvasSaveData — toJson
  // ===========================================================================

  group('FlueraCanvasSaveData - toJson', () {
    test('serializes minimal data', () {
      final data = FlueraCanvasSaveData(
        canvasId: 'canvas_1',
        layers: const [],
        textElements: const [],
        imageElements: const [],
        backgroundColor: '#FFFFFF',
        paperType: 'blank',
      );
      final json = data.toJson();
      expect(json['canvasId'], 'canvas_1');
      expect(json['backgroundColor'], '#FFFFFF');
      expect(json['paperType'], 'blank');
      expect(json['updatedAt'], isNotNull);
    });

    test('includes optional fields when provided', () {
      final data = FlueraCanvasSaveData(
        canvasId: 'canvas_2',
        layers: const [],
        textElements: const [],
        imageElements: const [],
        backgroundColor: '#000000',
        paperType: 'grid',
        title: 'My Canvas',
        activeLayerId: 'layer_1',
      );
      final json = data.toJson();
      expect(json['title'], 'My Canvas');
      expect(json['activeLayerId'], 'layer_1');
    });

    test('omits null optional fields', () {
      final data = FlueraCanvasSaveData(
        canvasId: 'canvas_3',
        layers: const [],
        textElements: const [],
        imageElements: const [],
        backgroundColor: '#FFFFFF',
        paperType: 'blank',
      );
      final json = data.toJson();
      expect(json.containsKey('title'), isFalse);
      expect(json.containsKey('activeLayerId'), isFalse);
      expect(json.containsKey('guides'), isFalse);
    });
  });

  // ===========================================================================
  // FlueraPresenceUser
  // ===========================================================================

  group('FlueraPresenceUser', () {
    test('construction works', () {
      const user = FlueraPresenceUser(
        id: 'user_1',
        name: 'Lorenzo',
        cursorColor: Color(0xFF4CAF50),
        cursorPosition: Offset(100, 200),
      );
      expect(user.id, 'user_1');
      expect(user.name, 'Lorenzo');
      expect(user.cursorPosition, const Offset(100, 200));
    });
  });
}
