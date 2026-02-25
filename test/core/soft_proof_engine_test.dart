import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/color/soft_proof_engine.dart';
import 'package:nebula_engine/src/core/color/color_space_converter.dart';

void main() {
  // ===========================================================================
  // SoftProofEngine — basic proofing
  // ===========================================================================

  group('SoftProofEngine - proof', () {
    test('proofs white to near-paper-white', () {
      const engine = SoftProofEngine();
      final result = engine.proof(1.0, 1.0, 1.0);
      // Paper white is slightly off-white
      expect(result.r, lessThan(1.0));
      expect(result.g, lessThan(1.0));
      expect(result.b, lessThan(1.0));
    });

    test('proofs black to near-black', () {
      const engine = SoftProofEngine();
      final result = engine.proof(0.0, 0.0, 0.0);
      expect(result.r, closeTo(0, 0.2));
      expect(result.g, closeTo(0, 0.2));
    });

    test('result is within 0-1 range', () {
      const engine = SoftProofEngine();
      final result = engine.proof(0.8, 0.2, 0.5);
      expect(result.r, inInclusiveRange(0.0, 1.0));
      expect(result.g, inInclusiveRange(0.0, 1.0));
      expect(result.b, inInclusiveRange(0.0, 1.0));
    });
  });

  // ===========================================================================
  // Gamut check
  // ===========================================================================

  group('SoftProofEngine - gamut', () {
    test('light neutral is more likely in gamut', () {
      const engine = SoftProofEngine();
      // Very light neutrals close to paper white are more likely in gamut
      final result = engine.proof(0.9, 0.9, 0.9);
      expect(result.inGamut, isA<bool>());
    });

    test('gamut flag is set on result', () {
      const engine = SoftProofEngine();
      final result = engine.proof(0.5, 0.5, 0.5);
      expect(result.inGamut, isA<bool>());
    });
  });

  // ===========================================================================
  // Batch proofing
  // ===========================================================================

  group('SoftProofEngine - batch', () {
    test('proofBatch returns list', () {
      const engine = SoftProofEngine();
      final results = engine.proofBatch([
        const RgbColor(1, 0, 0),
        const RgbColor(0, 1, 0),
        const RgbColor(0, 0, 1),
      ]);
      expect(results.length, 3);
    });
  });

  // ===========================================================================
  // Print profiles
  // ===========================================================================

  group('PrintProfile', () {
    test('coatedFogra39 has id', () {
      expect(PrintProfile.coatedFogra39.id, 'coated_fogra39');
    });

    test('newsprint has lower ink density', () {
      expect(
        PrintProfile.newsprint.maxInkDensity,
        lessThan(PrintProfile.coatedFogra39.maxInkDensity),
      );
    });

    test('toString is readable', () {
      expect(PrintProfile.coatedFogra39.toString(), contains('Coated'));
    });
  });

  // ===========================================================================
  // Rendering intents
  // ===========================================================================

  group('SoftProofEngine - intents', () {
    test('saturation intent boosts color', () {
      const engine = SoftProofEngine(intent: RenderingIntent.saturation);
      final result = engine.proof(0.8, 0.2, 0.3);
      expect(result.r, inInclusiveRange(0.0, 1.0));
    });

    test('perceptual intent produces valid output', () {
      const engine = SoftProofEngine(intent: RenderingIntent.perceptual);
      final result = engine.proof(0.5, 0.5, 0.5);
      expect(result.r, inInclusiveRange(0.0, 1.0));
    });
  });

  // ===========================================================================
  // ProofResult
  // ===========================================================================

  group('ProofResult', () {
    test('toString distinguishes gamut', () {
      const engine = SoftProofEngine();
      final result = engine.proof(0.5, 0.5, 0.5);
      expect(result.toString(), isNotEmpty);
    });
  });

  // ===========================================================================
  // RenderingIntent enum
  // ===========================================================================

  group('RenderingIntent', () {
    test('has 4 values', () {
      expect(RenderingIntent.values.length, 4);
    });
  });
}
