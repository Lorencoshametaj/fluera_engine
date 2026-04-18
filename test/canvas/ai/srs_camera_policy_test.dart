import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/canvas/ai/srs_camera_policy.dart';
import 'package:fluera_engine/src/rendering/lod_config.dart';

void main() {
  group('SrsCameraPolicy', () {
    test('reviewCount 0 returns userBaseScale unchanged (within clamp)', () {
      expect(
        SrsCameraPolicy.targetScaleForReturn(
          reviewCount: 0,
          userBaseScale: 1.0,
        ),
        1.0,
      );
    });

    test('target scale decreases monotonically with review count', () {
      double? prev;
      for (var i = 0; i <= 12; i++) {
        final s = SrsCameraPolicy.targetScaleForReturn(
          reviewCount: i,
          userBaseScale: 1.0,
        );
        if (prev != null) {
          expect(s, lessThanOrEqualTo(prev),
              reason: 'scale must not grow with reviews ($i: $s vs prev $prev)');
        }
        prev = s;
      }
    });

    test('target scale clamps to minAutoScale (inside LOD 2)', () {
      // Huge review count should floor at minAutoScale, never below.
      final s = SrsCameraPolicy.targetScaleForReturn(
        reviewCount: 200,
        userBaseScale: 1.0,
      );
      expect(s, SrsCameraPolicy.minAutoScale);
      expect(s, lessThan(kLodTier2Threshold));
    });

    test('target scale clamps to maxAutoScale', () {
      // Big base + no reviews → returns clamped maxAutoScale.
      final s = SrsCameraPolicy.targetScaleForReturn(
        reviewCount: 0,
        userBaseScale: 100.0,
      );
      expect(s, SrsCameraPolicy.maxAutoScale);
    });

    test('around 10 returns the student lands in LOD 2 satellite', () {
      final tier = SrsCameraPolicy.targetLodTier(
        reviewCount: 10,
        userBaseScale: 1.0,
      );
      expect(tier, 2);
    });

    test('first return keeps the student in LOD 0 or 1', () {
      final tier = SrsCameraPolicy.targetLodTier(
        reviewCount: 1,
        userBaseScale: 1.0,
      );
      expect(tier, lessThanOrEqualTo(1));
    });

    test('hint localizes by tier and differentiates satellite from detail',
        () {
      final satellite = SrsCameraPolicy.hintForTier(2);
      final detail = SrsCameraPolicy.hintForTier(0);
      expect(satellite, isNot(equals(detail)));
      expect(satellite.toLowerCase(), contains('satellite'));
      expect(detail.toLowerCase(), contains('dettaglio'));
    });

    test('geometric decay ratio holds between consecutive returns', () {
      final s1 = SrsCameraPolicy.targetScaleForReturn(
        reviewCount: 1,
        userBaseScale: 1.0,
      );
      final s2 = SrsCameraPolicy.targetScaleForReturn(
        reviewCount: 2,
        userBaseScale: 1.0,
      );
      // s2 / s1 should equal decayPerReview (within floating tolerance),
      // as long as neither is clamped.
      expect(s2 / s1,
          closeTo(SrsCameraPolicy.decayPerReview, 1e-6));
    });
  });
}
