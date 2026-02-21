import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/rendering/scene_graph/render_batch.dart';
import 'package:flutter/widgets.dart'; // For Matrix4
import 'dart:ui';

void main() {
  group('RenderBatch', () {
    test('batches rects into a single drawVertices call efficiently', () {
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);

      final batcher = BatchRenderer();
      final key = const MaterialKey(
        colorValue: 0xFF0000FF,
        blendMode: BlendMode.srcOver,
        style: PaintingStyle.fill,
      );

      final stopwatch = Stopwatch()..start();

      for (int i = 0; i < 10000; i++) {
        batcher.addRect(
          key,
          Rect.fromLTWH(i.toDouble(), 0, 10, 10),
          Matrix4.identity(),
        );
      }

      // Flush combines 10000 Rects into a single Vertices object and 1 drawVertices call
      batcher.flushAll(canvas);
      stopwatch.stop();

      // Ensure the batching takes less than 500ms (typically it takes <50ms)
      expect(stopwatch.elapsedMilliseconds, lessThan(500));
    });
  });
}
