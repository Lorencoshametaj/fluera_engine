import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/layers/layer_controller.dart';

import '../helpers/test_helpers.dart';

void main() {
  group('Note import composite undo (F11)', () {
    late LayerController lc;

    setUp(() {
      lc = LayerController();
    });

    test('addStrokesBatch inside runAsBatch lands all strokes', () async {
      final strokes = List.generate(50, (i) => testStroke(id: 'imp_$i'));

      await lc.runAsBatch('Importa 50 tratti', () async {
        await lc.addStrokesBatch(strokes);
      });

      expect(lc.activeLayer!.strokes, hasLength(50));
      // Each imported stroke is identifiable by its id prefix.
      final imported = lc.activeLayer!.strokes
          .where((s) => s.id.startsWith('imp_'))
          .toList();
      expect(imported, hasLength(50));
    });

    test('empty import is a no-op', () async {
      await lc.runAsBatch('Importa 0 tratti', () async {
        await lc.addStrokesBatch(const []);
      });
      expect(lc.activeLayer!.strokes, isEmpty);
    });

    test('large import (1500 strokes) chunks without crashing', () async {
      final strokes = List.generate(1500, (i) => testStroke(id: 'big_$i'));
      await lc.runAsBatch('Importa 1500 tratti', () async {
        await lc.addStrokesBatch(strokes);
      });
      expect(
        lc.activeLayer!.strokes.where((s) => s.id.startsWith('big_')),
        hasLength(1500),
      );
    });
  });
}
