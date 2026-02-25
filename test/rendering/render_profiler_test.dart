import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/rendering/render_profiler.dart';

void main() {
  late RenderProfiler profiler;

  setUp(() {
    profiler = RenderProfiler();
  });

  // ===========================================================================
  // Basic frame recording
  // ===========================================================================

  group('RenderProfiler - frame recording', () {
    test('starts with no frames', () {
      expect(profiler.lastFrames(), isEmpty);
    });

    test('records a single frame', () {
      profiler.beginFrame();
      profiler.endFrame();
      expect(profiler.lastFrames().length, 1);
    });

    test('records multiple frames', () {
      for (int i = 0; i < 5; i++) {
        profiler.beginFrame();
        profiler.endFrame();
      }
      expect(profiler.lastFrames().length, 5);
    });

    test('lastFrames limits count', () {
      for (int i = 0; i < 100; i++) {
        profiler.beginFrame();
        profiler.endFrame();
      }
      expect(profiler.lastFrames(10).length, 10);
    });
  });

  // ===========================================================================
  // Phase tracking
  // ===========================================================================

  group('RenderProfiler - phases', () {
    test('records phase durations', () {
      profiler.beginFrame();
      profiler.beginPhase(RenderPhase.layout);
      profiler.endPhase();
      profiler.beginPhase(RenderPhase.paint);
      profiler.endPhase();
      profiler.endFrame();
      final frame = profiler.lastFrames().first;
      expect(frame.phaseDuration(RenderPhase.layout), isNotNull);
      expect(frame.phaseDuration(RenderPhase.paint), isNotNull);
    });
  });

  // ===========================================================================
  // Report
  // ===========================================================================

  group('RenderProfiler - report', () {
    test('generates report from recorded frames', () {
      for (int i = 0; i < 10; i++) {
        profiler.beginFrame();
        profiler.beginPhase(RenderPhase.paint);
        profiler.endPhase();
        profiler.endFrame(dirtyNodeCount: 5, paintedNodeCount: 3);
      }
      final report = profiler.report(windowSize: 10);
      expect(report.frameCount, 10);
      expect(report.avgUs, greaterThanOrEqualTo(0));
      expect(report.p95Us, greaterThanOrEqualTo(0));
    });

    test('report from empty profiler has 0 frames', () {
      final report = profiler.report();
      expect(report.frameCount, 0);
    });
  });

  // ===========================================================================
  // FrameProfile
  // ===========================================================================

  group('FrameProfile', () {
    test('toJson produces map', () {
      profiler.beginFrame();
      profiler.endFrame();
      final frame = profiler.lastFrames().first;
      final json = frame.toJson();
      expect(json, isA<Map<String, dynamic>>());
    });
  });

  // ===========================================================================
  // ProfileReport
  // ===========================================================================

  group('ProfileReport', () {
    test('toJson produces map', () {
      for (int i = 0; i < 3; i++) {
        profiler.beginFrame();
        profiler.endFrame();
      }
      final report = profiler.report();
      final json = report.toJson();
      expect(json, isA<Map<String, dynamic>>());
      expect(json['frameCount'], 3);
    });

    test('toString produces readable string', () {
      profiler.beginFrame();
      profiler.endFrame();
      final report = profiler.report();
      expect(report.toString(), isNotEmpty);
    });
  });

  // ===========================================================================
  // Reset
  // ===========================================================================

  group('RenderProfiler - reset', () {
    test('clears all recorded frames', () {
      for (int i = 0; i < 10; i++) {
        profiler.beginFrame();
        profiler.endFrame();
      }
      profiler.reset();
      expect(profiler.lastFrames(), isEmpty);
    });
  });

  // ===========================================================================
  // RenderPhase enum
  // ===========================================================================

  group('RenderPhase', () {
    test('has expected values', () {
      expect(RenderPhase.values, contains(RenderPhase.layout));
      expect(RenderPhase.values, contains(RenderPhase.paint));
    });
  });
}
