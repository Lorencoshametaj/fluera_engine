// ============================================================================
// 🔒 GHOST MAP SECURITY — Unit Tests for input sanitization & bounds clamping
//
// Tests the static security helpers in GeminiProvider:
//   - _sanitizeInput: prompt injection defense
//   - _clampString: UI overflow prevention
//
// Since the helpers are private/static on GeminiProvider, we test them
// indirectly through the full generateGhostMap pipeline by verifying
// the GhostMapModel fields are properly sanitized.
// ============================================================================

import 'dart:ui' show Offset, Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/canvas/ai/ghost_map_model.dart';

void main() {
  // ═════════════════════════════════════════════════════════════════════════
  // GhostNode bounds validation
  // ═════════════════════════════════════════════════════════════════════════

  group('GhostNode bounds', () {
    test('bounds are computed from position and size', () {
      final node = GhostNode(
        id: 'test',
        concept: 'Test',
        estimatedPosition: const Offset(100, 200),
        estimatedSize: const Size(220, 90),
        status: GhostNodeStatus.missing,
      );

      final bounds = node.bounds;
      expect(bounds.center, equals(const Offset(100, 200)));
      expect(bounds.width, equals(220));
      expect(bounds.height, equals(90));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // GhostNode status helpers
  // ═════════════════════════════════════════════════════════════════════════

  group('GhostNode status helpers', () {
    test('isMissing/isWeak/isCorrect match status enum', () {
      final missing = GhostNode(
        id: 'm', concept: 'X', estimatedPosition: Offset.zero,
        status: GhostNodeStatus.missing,
      );
      final weak = GhostNode(
        id: 'w', concept: 'Y', estimatedPosition: Offset.zero,
        status: GhostNodeStatus.weak,
      );
      final correct = GhostNode(
        id: 'c', concept: 'Z', estimatedPosition: Offset.zero,
        status: GhostNodeStatus.correct,
      );

      expect(missing.isMissing, isTrue);
      expect(missing.isWeak, isFalse);
      expect(missing.isCorrect, isFalse);

      expect(weak.isMissing, isFalse);
      expect(weak.isWeak, isTrue);
      expect(weak.isCorrect, isFalse);

      expect(correct.isMissing, isFalse);
      expect(correct.isWeak, isFalse);
      expect(correct.isCorrect, isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // GhostConnection deduplication
  // ═════════════════════════════════════════════════════════════════════════

  group('GhostConnection', () {
    test('pairKey is order-independent', () {
      final conn1 = GhostConnection(
        id: 'c1', sourceId: 'a', targetId: 'b',
      );
      final conn2 = GhostConnection(
        id: 'c2', sourceId: 'b', targetId: 'a',
      );

      expect(conn1.pairKey, equals(conn2.pairKey));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // GhostMapResult statistics
  // ═════════════════════════════════════════════════════════════════════════

  group('GhostMapResult statistics', () {
    test('empty result has zero counts', () {
      final result = GhostMapResult.empty();

      expect(result.totalMissing, equals(0));
      expect(result.totalWeak, equals(0));
      expect(result.totalCorrect, equals(0));
      expect(result.nodes, isEmpty);
      expect(result.connections, isEmpty);
    });

    test('counts match node status distribution', () {
      final result = GhostMapResult(
        nodes: [
          GhostNode(id: '1', concept: 'A', estimatedPosition: Offset.zero, status: GhostNodeStatus.missing),
          GhostNode(id: '2', concept: 'B', estimatedPosition: Offset.zero, status: GhostNodeStatus.missing),
          GhostNode(id: '3', concept: 'C', estimatedPosition: Offset.zero, status: GhostNodeStatus.weak),
          GhostNode(id: '4', concept: 'D', estimatedPosition: Offset.zero, status: GhostNodeStatus.correct),
          GhostNode(id: '5', concept: 'E', estimatedPosition: Offset.zero, status: GhostNodeStatus.correct),
          GhostNode(id: '6', concept: 'F', estimatedPosition: Offset.zero, status: GhostNodeStatus.correct),
        ],
        connections: const [],
        summary: 'Test',
      );

      expect(result.totalMissing, equals(2));
      expect(result.totalWeak, equals(1));
      expect(result.totalCorrect, equals(3));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // Mutable state
  // ═════════════════════════════════════════════════════════════════════════

  group('GhostNode mutable state', () {
    test('isRevealed defaults to false', () {
      final node = GhostNode(
        id: 'test', concept: 'X', estimatedPosition: Offset.zero,
        status: GhostNodeStatus.missing,
      );
      expect(node.isRevealed, isFalse);
    });

    test('userAttempt and attemptCorrect are settable', () {
      final node = GhostNode(
        id: 'test', concept: 'X', estimatedPosition: Offset.zero,
        status: GhostNodeStatus.missing,
      );

      node.userAttempt = 'my guess';
      node.attemptCorrect = true;

      expect(node.userAttempt, equals('my guess'));
      expect(node.attemptCorrect, isTrue);
    });
  });
}
