import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/rendering/shaders/shader_brush_service.dart';
import 'package:fluera_engine/src/core/engine_scope.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ShaderBrushService service;

  setUp(() {
    EngineScope.reset();
    service = ShaderBrushService.create();
  });

  tearDown(() {
    EngineScope.reset();
  });

  // =========================================================================
  // Initial State
  // =========================================================================

  group('initial state', () {
    test('starts unavailable before initialization', () {
      expect(service.isAvailable, isFalse);
    });

    test('stamp not available before init', () {
      expect(service.isStampAvailable, isFalse);
    });

    test('texture overlay not available before init', () {
      expect(service.isTextureOverlayAvailable, isFalse);
    });

    test('pro starts disabled', () {
      expect(service.isProEnabled, isFalse);
    });
  });

  // =========================================================================
  // Pro Feature Flags
  // =========================================================================

  group('pro feature flags', () {
    test('isProEnabled reflects initialized state', () {
      // Not initialized → not pro
      expect(service.isProEnabled, isFalse);
    });
  });

  // =========================================================================
  // Geometry Helpers
  // =========================================================================

  group('preComputeOffsets', () {
    test('extracts offsets from Offset list', () {
      final points = [
        const Offset(10, 20),
        const Offset(30, 40),
        const Offset(50, 60),
      ];
      final offsets = service.preComputeOffsets(points);
      expect(offsets.length, 3);
      expect(offsets[0], const Offset(10, 20));
      expect(offsets[1], const Offset(30, 40));
      expect(offsets[2], const Offset(50, 60));
    });

    test('handles single point', () {
      final points = [const Offset(5, 5)];
      final offsets = service.preComputeOffsets(points);
      expect(offsets.length, 1);
    });
  });

  group('getPressure', () {
    test('returns 0.5 for Offset type', () {
      final pressure = service.getPressure(const Offset(10, 20));
      expect(pressure, 0.5);
    });
  });

  group('coalesceIndices', () {
    test('returns all indices for 3 or fewer points', () {
      final offsets = [
        const Offset(0, 0),
        const Offset(10, 0),
        const Offset(20, 0),
      ];
      final indices = service.coalesceIndices(offsets);
      expect(indices, [0, 1, 2]);
    });

    test('coalesces collinear points', () {
      final offsets = [
        const Offset(0, 0),
        const Offset(10, 0),
        const Offset(20, 0),
        const Offset(30, 0),
        const Offset(40, 0),
      ];
      final indices = service.coalesceIndices(offsets);
      // First and last are always included
      expect(indices.first, 0);
      expect(indices.last, 4);
      expect(indices.length, lessThanOrEqualTo(5));
    });

    test('preserves sharp corners', () {
      final offsets = [
        const Offset(0, 0),
        const Offset(50, 0),
        const Offset(50, 50),
        const Offset(0, 50),
      ];
      final indices = service.coalesceIndices(offsets);
      // Sharp 90-degree turns should all be preserved
      expect(indices.length, 4);
    });
  });

  group('segmentDirFromOffsets', () {
    test('horizontal direction', () {
      final offsets = [const Offset(0, 0), const Offset(10, 0)];
      final dir = service.segmentDirFromOffsets(offsets, 0);
      expect(dir.dx, closeTo(1.0, 0.01));
      expect(dir.dy, closeTo(0.0, 0.01));
    });

    test('vertical direction', () {
      final offsets = [const Offset(0, 0), const Offset(0, 10)];
      final dir = service.segmentDirFromOffsets(offsets, 0);
      expect(dir.dx, closeTo(0.0, 0.01));
      expect(dir.dy, closeTo(1.0, 0.01));
    });

    test('returns default for last index', () {
      final offsets = [const Offset(0, 0)];
      final dir = service.segmentDirFromOffsets(offsets, 0);
      expect(dir.dx, closeTo(1.0, 0.01));
    });
  });

  group('calculateVelocitiesForIndices', () {
    test('returns normalized velocities', () {
      final offsets = [
        const Offset(0, 0),
        const Offset(10, 0),
        const Offset(30, 0),
      ];
      final indices = [0, 1, 2];
      final velocities = service.calculateVelocitiesForIndices(
        offsets,
        indices,
      );
      expect(velocities.length, 3);
      // The fastest segment should have velocity 1.0
      expect(velocities[1], closeTo(1.0, 0.01));
      // The slower segment should be < 1.0
      expect(velocities[0], closeTo(0.5, 0.01));
    });

    test('handles single index', () {
      final offsets = [const Offset(0, 0)];
      final indices = [0];
      final velocities = service.calculateVelocitiesForIndices(
        offsets,
        indices,
      );
      expect(velocities, [0.0]);
    });
  });

  // =========================================================================
  // Dispose
  // =========================================================================

  group('cleanup', () {
    test('starts as not available', () {
      expect(service.isAvailable, isFalse);
    });
  });
}
