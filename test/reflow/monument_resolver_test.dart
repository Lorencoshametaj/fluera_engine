import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/canvas/ai/fsrs_scheduler.dart';
import 'package:fluera_engine/src/reflow/content_cluster.dart';
import 'package:fluera_engine/src/reflow/knowledge_connection.dart';
import 'package:fluera_engine/src/reflow/monument_resolver.dart';

ContentCluster _cluster(String id, {bool pinned = false}) => ContentCluster(
      id: id,
      strokeIds: const [],
      bounds: Rect.fromLTWH(0, 0, 100, 40),
      centroid: const Offset(50, 20),
      isPinned: pinned,
    );

KnowledgeConnection _conn(
  String id,
  String src,
  String tgt, {
  int createdAt = 0,
}) {
  return KnowledgeConnection(
    id: id,
    sourceClusterId: src,
    targetClusterId: tgt,
    createdAt: createdAt,
  );
}

void main() {
  group('MonumentResolver', () {
    test('empty input returns empty maps', () {
      final r = MonumentResolver.compute(
        clusters: const [],
        connections: const [],
      );
      expect(r.monumentIds, isEmpty);
      expect(r.importance, isEmpty);
    });

    test('single unconnected cluster is not a monument', () {
      final r = MonumentResolver.compute(
        clusters: [_cluster('a')],
        connections: const [],
      );
      expect(r.monumentIds, isEmpty);
      expect(r.importance['a'], 0.0);
    });

    test('hub with many connections is classified as monument', () {
      final clusters = [for (var i = 0; i < 6; i++) _cluster('c$i')];
      // c0 is a hub: connects to c1..c5
      final connections = [
        for (var i = 1; i < 6; i++) _conn('k$i', 'c0', 'c$i'),
      ];
      final r = MonumentResolver.compute(
        clusters: clusters,
        connections: connections,
      );
      expect(r.monumentIds, contains('c0'));
      expect(r.importance['c0'], greaterThan(r.importance['c1']!));
    });

    test('pinned cluster gets a boost and is eligible without degree', () {
      final clusters = [_cluster('pinned', pinned: true), _cluster('other')];
      final r = MonumentResolver.compute(
        clusters: clusters,
        connections: const [],
      );
      // Pinned contributes 0.10 of score but is eligible as monument.
      // With no other signals score = 0.10, below threshold 0.45.
      expect(r.monumentIds, isEmpty);
      expect(r.importance['pinned'], greaterThan(r.importance['other']!));
    });

    test('deleted connections are ignored for degree', () {
      final clusters = [_cluster('a'), _cluster('b')];
      final connections = [
        _conn('k', 'a', 'b')..deletedAtMs = 1,
      ];
      final r = MonumentResolver.compute(
        clusters: clusters,
        connections: connections,
      );
      expect(r.importance['a'], 0.0);
      expect(r.importance['b'], 0.0);
    });

    test('FSRS stability lifts score when matched via cluster texts', () {
      final clusters = [
        _cluster('a'),
        _cluster('b'),
        for (var i = 0; i < 4; i++) _cluster('x$i'),
      ];
      final connections = [
        for (var i = 0; i < 4; i++) _conn('k$i', 'a', 'x$i'),
        for (var i = 0; i < 4; i++) _conn('l$i', 'b', 'x$i'),
      ];
      final now = DateTime.now();
      final schedule = {
        'entropia': SrsCardData(
          stability: 30.0,
          difficulty: 0.5,
          elapsedDays: 0,
          scheduledDays: 30,
          reps: 5,
          lapses: 0,
          state: FsrsState.review,
          nextReview: now.add(const Duration(days: 30)),
          lastReview: now,
        ),
      };
      final texts = {'a': 'entropia definizione', 'b': 'diverso'};
      final r = MonumentResolver.compute(
        clusters: clusters,
        connections: connections,
        reviewSchedule: schedule,
        clusterTexts: texts,
      );
      // a and b have identical degree — stability breaks the tie.
      expect(r.importance['a']!, greaterThan(r.importance['b']!));
    });

    test('ranking is deterministic and monotone in importance', () {
      final clusters = [
        _cluster('low'),
        _cluster('mid'),
        _cluster('high'),
        _cluster('x'),
      ];
      // Degrees: high=3 (k1,k2,k3), mid=2 (k1,k4), low=1 (k2), x=2 (k3,k4)
      final connections = [
        _conn('k1', 'high', 'mid'),
        _conn('k2', 'high', 'low'),
        _conn('k3', 'high', 'x'),
        _conn('k4', 'mid', 'x'),
      ];
      final r = MonumentResolver.compute(
        clusters: clusters,
        connections: connections,
      );
      final ranked = r.rankedByImportance();
      expect(ranked.first, 'high');
      expect(r.importance[ranked[0]]!, greaterThanOrEqualTo(
        r.importance[ranked[1]]!,
      ));
      expect(r.importance[ranked[1]]!, greaterThanOrEqualTo(
        r.importance[ranked[2]]!,
      ));
    });

    test('topMonuments respects the limit cap', () {
      final clusters = [for (var i = 0; i < 20; i++) _cluster('c$i')];
      // Fully connected hub-and-spoke with c0 as hub
      final connections = [
        for (var i = 1; i < 20; i++) _conn('k$i', 'c0', 'c$i'),
        // Secondary hubs
        _conn('s1', 'c1', 'c2'),
        _conn('s2', 'c1', 'c3'),
      ];
      final r = MonumentResolver.compute(
        clusters: clusters,
        connections: connections,
      );
      expect(r.topMonuments(limit: 1).length, lessThanOrEqualTo(1));
      expect(r.topMonuments(limit: 5).length, lessThanOrEqualTo(5));
      // Hub should be first
      final top = r.topMonuments(limit: 3);
      if (top.isNotEmpty) expect(top.first, 'c0');
    });

    test('age contributes: older connections → higher ageNorm', () {
      final clusters = [_cluster('old'), _cluster('new'), _cluster('x')];
      final now = DateTime.now().millisecondsSinceEpoch;
      final ninetyDaysMs = 90 * 24 * 60 * 60 * 1000;
      final connections = [
        _conn('o', 'old', 'x', createdAt: now - ninetyDaysMs),
        _conn('n', 'new', 'x', createdAt: now - 1000),
      ];
      final r = MonumentResolver.compute(
        clusters: clusters,
        connections: connections,
        nowMs: now,
      );
      expect(r.importance['old']!, greaterThan(r.importance['new']!));
    });
  });
}
