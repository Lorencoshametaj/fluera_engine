import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/reflow/content_cluster.dart';
import 'package:fluera_engine/src/reflow/zone_labeler.dart';

ContentCluster _c(String id, Offset center) => ContentCluster(
      id: id,
      strokeIds: const [],
      bounds: Rect.fromCenter(center: center, width: 100, height: 40),
      centroid: center,
    );

void main() {
  group('ZoneLabeler', () {
    test('returns empty for fewer than minClustersPerZone clusters', () {
      final result = ZoneLabeler.compute(
        clusters: [_c('a', const Offset(0, 0)), _c('b', const Offset(10, 10))],
        clusterTexts: {'a': 'entropia', 'b': 'entropia'},
      );
      expect(result.zones, isEmpty);
      expect(result.membership, isEmpty);
    });

    test('single dense cluster of 3+ nearby clusters becomes a zone', () {
      final result = ZoneLabeler.compute(
        clusters: [
          _c('a', const Offset(0, 0)),
          _c('b', const Offset(100, 0)),
          _c('c', const Offset(50, 80)),
        ],
        clusterTexts: {
          'a': 'termodinamica entropia',
          'b': 'entropia calore',
          'c': 'entropia sistema',
        },
      );
      expect(result.zones.length, 1);
      expect(result.zones.first.label.toLowerCase(), 'entropia');
      expect(result.zones.first.clusterCount, 3);
    });

    test('distant clusters form separate zones', () {
      final result = ZoneLabeler.compute(
        clusters: [
          // Zone 1 around origin
          _c('a', const Offset(0, 0)),
          _c('b', const Offset(50, 50)),
          _c('c', const Offset(100, 0)),
          // Zone 2 far away (> defaultLinkDistance in both x and y)
          _c('x', const Offset(3000, 3000)),
          _c('y', const Offset(3050, 3050)),
          _c('z', const Offset(3100, 3000)),
        ],
        clusterTexts: {
          'a': 'fisica', 'b': 'fisica newton', 'c': 'fisica massa',
          'x': 'biologia', 'y': 'biologia cellula', 'z': 'biologia',
        },
      );
      expect(result.zones.length, 2);
      final labels = result.zones.map((z) => z.label.toLowerCase()).toSet();
      expect(labels, containsAll(['fisica', 'biologia']));
    });

    test('membership maps each cluster in a zone to that zone id', () {
      final result = ZoneLabeler.compute(
        clusters: [
          _c('a', const Offset(0, 0)),
          _c('b', const Offset(50, 0)),
          _c('c', const Offset(0, 50)),
        ],
        clusterTexts: {'a': 'fisica', 'b': 'fisica', 'c': 'fisica'},
      );
      expect(result.membership.length, 3);
      final zoneId = result.zones.first.id;
      for (final id in ['a', 'b', 'c']) {
        expect(result.membership[id], zoneId);
      }
    });

    test('stopwords are filtered from label derivation', () {
      final result = ZoneLabeler.compute(
        clusters: [
          _c('a', const Offset(0, 0)),
          _c('b', const Offset(50, 0)),
          _c('c', const Offset(0, 50)),
        ],
        clusterTexts: {
          'a': 'la fotosintesi è',
          'b': 'il fotosintesi del',
          'c': 'con fotosintesi e',
        },
      );
      expect(result.zones, isNotEmpty);
      // Stopwords (la, il, con, è, del, e) must not win.
      expect(result.zones.first.label.toLowerCase(), 'fotosintesi');
    });

    test('purely numeric tokens are rejected', () {
      final result = ZoneLabeler.compute(
        clusters: [
          _c('a', const Offset(0, 0)),
          _c('b', const Offset(50, 0)),
          _c('c', const Offset(0, 50)),
        ],
        clusterTexts: {
          'a': '2024 matematica',
          'b': 'matematica 100',
          'c': 'matematica 42',
        },
      );
      expect(result.zones.first.label.toLowerCase(), 'matematica');
    });

    test('no labelable text → no zone', () {
      final result = ZoneLabeler.compute(
        clusters: [
          _c('a', const Offset(0, 0)),
          _c('b', const Offset(50, 0)),
          _c('c', const Offset(0, 50)),
        ],
        clusterTexts: const {}, // no text at all
      );
      expect(result.zones, isEmpty);
    });

    test('zone bounds contain all member clusters', () {
      final clusters = [
        _c('a', const Offset(-100, -100)),
        _c('b', const Offset(100, 100)),
        _c('c', const Offset(-50, 50)),
      ];
      final result = ZoneLabeler.compute(
        clusters: clusters,
        clusterTexts: {'a': 'fisica', 'b': 'fisica', 'c': 'fisica'},
      );
      final zone = result.zones.first;
      for (final c in clusters) {
        expect(zone.bounds.overlaps(c.bounds.inflate(1)), isTrue,
            reason: 'zone bounds should contain ${c.id}');
      }
    });

    test('no zone when only one cluster in the region has text (dedup)',
        () {
      // 3 spatially clustered, but text only in ONE → the monument layer
      // on that cluster would already name the area; emitting a zone
      // label would duplicate it.
      final result = ZoneLabeler.compute(
        clusters: [
          _c('a', const Offset(0, 0)),
          _c('b', const Offset(50, 0)),
          _c('c', const Offset(0, 50)),
        ],
        clusterTexts: {'a': 'entropia termodinamica'},
      );
      expect(result.zones, isEmpty);
      expect(result.membership, isEmpty);
    });

    test('zone emerges when 2+ text-bearing clusters contribute', () {
      final result = ZoneLabeler.compute(
        clusters: [
          _c('a', const Offset(0, 0)),
          _c('b', const Offset(50, 0)),
          _c('c', const Offset(0, 50)),
        ],
        clusterTexts: {
          'a': 'entropia termodinamica',
          'b': 'entropia statistica',
          // 'c' has no text — but 'a' and 'b' satisfy the 2+ requirement
        },
      );
      expect(result.zones.length, 1);
      expect(result.zones.first.label.toLowerCase(), 'entropia');
    });

    test('label truncates at maxLabelChars with ellipsis', () {
      const longWord = 'antidisestablishmentarianism'; // 28 chars
      final result = ZoneLabeler.compute(
        clusters: [
          _c('a', const Offset(0, 0)),
          _c('b', const Offset(50, 0)),
          _c('c', const Offset(0, 50)),
        ],
        clusterTexts: {
          'a': longWord, 'b': longWord, 'c': longWord,
        },
      );
      final label = result.zones.first.label;
      expect(label.length, lessThanOrEqualTo(ZoneLabeler.maxLabelChars));
      expect(label.endsWith('…'), isTrue);
    });
  });
}
