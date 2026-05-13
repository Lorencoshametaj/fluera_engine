import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/ai/cluster_action.dart';

void main() {
  group('ClusterAction.fromJson', () {
    test('parses sposta_cluster with explicit dx/dy', () {
      final a = ClusterAction.fromJson({
        'tipo': 'sposta_cluster',
        'cluster_id': 'c_v2_a',
        'dx': 120,
        'dy': -40,
      });
      expect(a, isA<MoveClusterAction>());
      final m = a as MoveClusterAction;
      expect(m.clusterId, 'c_v2_a');
      expect(m.dx, 120);
      expect(m.dy, -40);
    });

    test('parses allinea_clusters with italian + english alignment names', () {
      final a = ClusterAction.fromJson({
        'tipo': 'allinea_clusters',
        'cluster_ids': ['c1', 'c2', 'c3'],
        'alignment': 'left',
      });
      expect(a, isA<AlignClustersAction>());
      final al = a as AlignClustersAction;
      expect(al.clusterIds, ['c1', 'c2', 'c3']);
      expect(al.alignment, ClusterAlignment.left);
    });

    test('defaults alignment to centerH when missing/unknown', () {
      final a = ClusterAction.fromJson({
        'tipo': 'allinea_clusters',
        'cluster_ids': ['c1', 'c2'],
        'alignment': 'martian',
      });
      expect((a as AlignClustersAction).alignment, ClusterAlignment.centerH);
    });

    test('parses distribuisci_clusters horizontal/vertical', () {
      final h = ClusterAction.fromJson({
        'tipo': 'distribuisci_clusters',
        'cluster_ids': ['c1', 'c2', 'c3'],
        'asse': 'horizontal',
      });
      final v = ClusterAction.fromJson({
        'tipo': 'distribuisci_clusters',
        'cluster_ids': ['c1', 'c2', 'c3'],
        'asse': 'vertical',
      });
      expect((h as DistributeClustersAction).axis, ClusterAxis.horizontal);
      expect((v as DistributeClustersAction).axis, ClusterAxis.vertical);
    });

    test('parses colora_cluster', () {
      final a = ClusterAction.fromJson({
        'tipo': 'colora_cluster',
        'cluster_id': 'c1',
        'colore': 'neon_green',
      });
      final c = a as ColorClusterAction;
      expect(c.clusterId, 'c1');
      expect(c.color, 'neon_green');
    });

    test('parses collega_clusters with italian + english keys', () {
      final a = ClusterAction.fromJson({
        'tipo': 'collega_clusters',
        'from_id': 'c1',
        'to_id': 'c2',
        'etichetta': 'causa',
      });
      final c = a as ConnectClustersAction;
      expect(c.fromId, 'c1');
      expect(c.toId, 'c2');
      expect(c.label, 'causa');
    });

    test('returns UnknownClusterAction for forward-compatible types', () {
      final a = ClusterAction.fromJson({
        'tipo': 'future_action_name',
        'foo': 42,
      });
      expect(a, isA<UnknownClusterAction>());
      expect((a as UnknownClusterAction).type, 'future_action_name');
    });
  });

  group('ClusterAction.parseAll', () {
    test('extracts azioni array and parses each entry', () {
      final actions = ClusterAction.parseAll({
        'spiegazione': 'Organizzo per topic',
        'azioni': [
          {
            'tipo': 'sposta_cluster',
            'cluster_id': 'c1',
            'dx': 10,
            'dy': 20,
          },
          {
            'tipo': 'colora_cluster',
            'cluster_id': 'c2',
            'colore': 'neon_cyan',
          },
        ],
      });
      expect(actions, hasLength(2));
      expect(actions[0], isA<MoveClusterAction>());
      expect(actions[1], isA<ColorClusterAction>());
    });

    test('falls back to english "actions" key', () {
      final actions = ClusterAction.parseAll({
        'actions': [
          {
            'tipo': 'sposta_cluster',
            'cluster_id': 'c1',
            'dx': 0,
            'dy': 0,
          },
        ],
      });
      expect(actions, hasLength(1));
    });

    test('returns empty list when neither key is present', () {
      expect(ClusterAction.parseAll(const {}), isEmpty);
    });
  });
}
