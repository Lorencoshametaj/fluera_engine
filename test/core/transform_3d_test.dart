import 'package:flutter/material.dart' show Matrix4;
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/transforms/transform_3d.dart';

void main() {
  group('Transform3D', () {
    test('identity has no effect', () {
      const t = Transform3D();
      expect(t.isIdentity, isTrue);
      expect(t.hasEffect, isFalse);
    });

    test('toMatrix4 produces non-identity when rotated', () {
      const t = Transform3D(rotateY: 45);
      final m = t.toMatrix4();
      expect(m, isNot(equals(Matrix4.identity())));
    });

    test('perspective sets entry 3,2', () {
      const t = Transform3D(perspective: 800);
      final m = t.toMatrix4();
      expect(m.entry(3, 2), closeTo(-1.0 / 800, 0.0001));
    });

    test('lerp at boundaries', () {
      const a = Transform3D(rotateX: 0);
      const b = Transform3D(rotateX: 90);
      final atZero = Transform3D.lerp(a, b, 0);
      final atOne = Transform3D.lerp(a, b, 1);
      final atHalf = Transform3D.lerp(a, b, 0.5);
      expect(atZero.rotateX, 0);
      expect(atOne.rotateX, 90);
      expect(atHalf.rotateX, closeTo(45, 0.01));
    });

    test('copyWith', () {
      const t = Transform3D(rotateX: 10, rotateY: 20);
      final copy = t.copyWith(rotateX: 30);
      expect(copy.rotateX, 30);
      expect(copy.rotateY, 20);
    });

    test('equality', () {
      const a = Transform3D(rotateX: 10, perspective: 800);
      const b = Transform3D(rotateX: 10, perspective: 800);
      const c = Transform3D(rotateX: 20, perspective: 800);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('JSON roundtrip', () {
      const t = Transform3D(
        rotateX: 15,
        rotateY: -10,
        rotateZ: 5,
        perspective: 1000,
        translateZ: 50,
        originX: 0.3,
        originY: 0.7,
      );
      final restored = Transform3D.fromJson(t.toJson());
      expect(restored, equals(t));
    });

    test('JSON omits zero values', () {
      const t = Transform3D(rotateX: 10);
      final json = t.toJson();
      expect(json.containsKey('rotateX'), isTrue);
      expect(json.containsKey('rotateY'), isFalse);
      expect(json.containsKey('perspective'), isFalse);
    });

    test('transform with origin offset', () {
      const t = Transform3D(rotateZ: 90);
      // With and without origin should produce different matrices.
      final withOrigin = t.toMatrix4(nodeWidth: 100, nodeHeight: 100);
      const tNoOrigin = Transform3D(rotateZ: 90, originX: 0, originY: 0);
      final withoutOrigin = tNoOrigin.toMatrix4(
        nodeWidth: 100,
        nodeHeight: 100,
      );
      expect(withOrigin, isNot(equals(withoutOrigin)));
    });
  });
}
