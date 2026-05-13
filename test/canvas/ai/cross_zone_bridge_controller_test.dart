// Unit tests for [CrossZoneBridgeController] — Passo 9.
//
// Covers the controller logic added in the Cross-Zone Bridge completion:
//   Fase 1: telemetry envelope, JSON parsing (markdown fence + single
//           object fallback), parse-failure counting.
//   Fase 2: dismiss-as-tombstone, dismissed-pair filtering across calls.
//   Fase 3: ClusterConceptIndex consumption is exercised via direct
//           clusterTexts (legacy path) — index integration is covered by
//           cluster_concept_index_test.dart.
//
// The controller is intentionally pure-logic: no widget, no MethodChannel.
// We drive it with a [KnowledgeFlowController] (also pure-logic) and a
// [FakeGeminiProvider] that returns a deterministic JSON string.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluera_engine/src/ai/telemetry_recorder.dart';
import 'package:fluera_engine/src/canvas/ai/cross_zone_bridge_controller.dart';
import 'package:fluera_engine/src/reflow/content_cluster.dart';
import 'package:fluera_engine/src/reflow/knowledge_connection.dart';
import 'package:fluera_engine/src/reflow/knowledge_flow_controller.dart';

import '_fakes.dart';

void main() {
  group('CrossZoneBridgeController', () {
    late KnowledgeFlowController flowController;
    late FakeGeminiProvider provider;
    late _CapturingTelemetry telemetry;
    late CrossZoneBridgeController controller;

    setUp(() {
      flowController = KnowledgeFlowController();
      provider = FakeGeminiProvider();
      telemetry = _CapturingTelemetry();
      controller = CrossZoneBridgeController(
        flowController: flowController,
        telemetry: telemetry,
      );
    });

    List<ContentCluster> twoClusters() => [
          _cluster('A', const Offset(0, 0)),
          _cluster('B', const Offset(1000, 0)),
        ];

    Map<String, String> twoTexts() => const {
          'A': 'Equilibrio chimico e Le Chatelier — reazione reversibile',
          'B': 'Bilancia commerciale e teoria del mercato in equilibrio',
        };

    test('returns 0 with empty AI response and emits empty_response telemetry',
        () async {
      provider.askFreeTextResponse = '';

      final count = await controller.requestBridgeSuggestions(
        aiProvider: provider,
        clusters: twoClusters(),
        clusterTexts: twoTexts(),
      );

      expect(count, 0);
      expect(telemetry.events, hasLength(1));
      expect(telemetry.events.single.event, 'cross_zone_bridge_request');
      expect(telemetry.events.single.props['result'], 'empty_response');
      expect(telemetry.events.single.props['suggestion_count'], 0);
      expect(telemetry.events.single.props['cache_hit'], false);
      expect(telemetry.events.single.props['latency_ms'], isA<int>());
    });

    test('parses a valid JSON array and creates ghost connections', () async {
      provider.askFreeTextResponse = '''
[
  {
    "source_zone": 1,
    "target_zone": 2,
    "bridge_type": "analogyStructural",
    "socratic_question": "Hai notato che entrambe le situazioni convergono verso uno stato di equilibrio?",
    "confidence": 0.85
  }
]
''';

      final count = await controller.requestBridgeSuggestions(
        aiProvider: provider,
        clusters: twoClusters(),
        clusterTexts: twoTexts(),
      );

      expect(count, 1);
      expect(controller.suggestions, hasLength(1));
      expect(controller.suggestions.single.sourceClusterId, 'A');
      expect(controller.suggestions.single.targetClusterId, 'B');
      expect(controller.suggestions.single.bridgeType,
          CrossZoneBridgeType.analogyStructural);
      // Ghost connection registered on the flow controller for rendering.
      final ghosts =
          flowController.connections.where((c) => c.isGhost).toList();
      expect(ghosts, hasLength(1));
      expect(ghosts.single.sourceClusterId, 'A');
      expect(ghosts.single.targetClusterId, 'B');
      expect(telemetry.events.single.props['result'], 'success');
    });

    test('strips markdown ```json fences before parsing', () async {
      provider.askFreeTextResponse = '''
Here is the result:
```json
[{"source_zone":1,"target_zone":2,"bridge_type":"sharedMechanism","socratic_question":"Quale meccanismo condiviso noti?","confidence":0.7}]
```
''';

      final count = await controller.requestBridgeSuggestions(
        aiProvider: provider,
        clusters: twoClusters(),
        clusterTexts: twoTexts(),
      );

      expect(count, 1);
      expect(controller.suggestions.single.bridgeType,
          CrossZoneBridgeType.sharedMechanism);
    });

    test('wraps a single JSON object as a 1-element array (fallback)',
        () async {
      provider.askFreeTextResponse =
          '{"source_zone":1,"target_zone":2,"bridge_type":"complementaryPerspective","socratic_question":"Quale prospettiva complementare emerge?","confidence":0.6}';

      final count = await controller.requestBridgeSuggestions(
        aiProvider: provider,
        clusters: twoClusters(),
        clusterTexts: twoTexts(),
      );

      expect(count, 1);
      expect(controller.suggestions.single.bridgeType,
          CrossZoneBridgeType.complementaryPerspective);
    });

    test('counts parseFailures for malformed items', () async {
      // 2 items: one malformed (missing socratic_question), one valid.
      provider.askFreeTextResponse = '''
[
  {"source_zone":1,"target_zone":2,"bridge_type":"analogyStructural","confidence":0.5},
  {"source_zone":2,"target_zone":1,"bridge_type":"sharedMechanism","socratic_question":"Cosa li accomuna?","confidence":0.8}
]
''';

      final count = await controller.requestBridgeSuggestions(
        aiProvider: provider,
        clusters: twoClusters(),
        clusterTexts: twoTexts(),
      );

      expect(count, 1);
      expect(telemetry.events.single.props['parse_failures'], 1);
      expect(telemetry.events.single.props['suggestion_count'], 1);
    });

    test('dismissed pair is not re-suggested across calls', () async {
      provider.askFreeTextResponse = '''
[{"source_zone":1,"target_zone":2,"bridge_type":"analogyStructural","socratic_question":"Q1?","confidence":0.7}]
''';
      await controller.requestBridgeSuggestions(
        aiProvider: provider,
        clusters: twoClusters(),
        clusterTexts: twoTexts(),
      );
      expect(controller.suggestions, hasLength(1));

      // Dismiss the only suggestion.
      final id = controller.suggestions.single.id;
      controller.dismissBridge(id);
      expect(controller.suggestions, isEmpty,
          reason: 'dismissed suggestion is removed from active list');

      // The ghost should remain as a tombstone with the dismissed flag set.
      final tombstones = flowController.connections
          .where((c) => c.isGhost && c.bridgeSuggestionDismissed)
          .toList();
      expect(tombstones, hasLength(1));

      // Next AI call returns the same pair — the controller must filter it.
      final count2 = await controller.requestBridgeSuggestions(
        aiProvider: provider,
        clusters: twoClusters(),
        clusterTexts: twoTexts(),
      );
      expect(count2, 0);
      expect(telemetry.events.last.props['result'], 'all_dismissed');
    });

    test('emits clusters_in_prompt count based on zones with ≥10 chars',
        () async {
      provider.askFreeTextResponse = '';
      await controller.requestBridgeSuggestions(
        aiProvider: provider,
        clusters: [
          _cluster('A', const Offset(0, 0)),
          _cluster('B', const Offset(1000, 0)),
          _cluster('C', const Offset(2000, 0)),
        ],
        clusterTexts: const {
          'A': 'Long enough text for zone A',
          'B': 'short', // too short — excluded from prompt
          'C': 'Another sufficiently long zone description',
        },
      );

      expect(telemetry.events.single.props['clusters_in_prompt'], 2);
    });

    test('returns 0 when fewer than 2 zones are provided', () async {
      final count = await controller.requestBridgeSuggestions(
        aiProvider: provider,
        clusters: [_cluster('A', const Offset(0, 0))],
        clusterTexts: const {'A': 'Some text'},
      );
      expect(count, 0);
      // No AI call should be made.
      expect(provider.askFreeTextPrompts, isEmpty);
      // No telemetry emitted (early return before try-block).
      expect(telemetry.events, isEmpty);
    });

    test('onBridgeAccepted callback fires with correct payload', () async {
      provider.askFreeTextResponse = '''
[{"source_zone":1,"target_zone":2,"bridge_type":"analogyStructural","socratic_question":"Cosa hanno in comune?","confidence":0.9}]
''';
      _AcceptedPayload? captured;
      final c2 = CrossZoneBridgeController(
        flowController: flowController,
        telemetry: telemetry,
        onBridgeAccepted: ({
          required String sourceClusterId,
          required String targetClusterId,
          required CrossZoneBridgeType bridgeType,
          required String socraticQuestion,
        }) {
          captured = _AcceptedPayload(
            sourceClusterId: sourceClusterId,
            targetClusterId: targetClusterId,
            bridgeType: bridgeType,
            socraticQuestion: socraticQuestion,
          );
        },
      );
      await c2.requestBridgeSuggestions(
        aiProvider: provider,
        clusters: twoClusters(),
        clusterTexts: twoTexts(),
      );
      final id = c2.suggestions.single.id;
      c2.acceptBridge(id);

      expect(captured, isNotNull);
      expect(captured!.sourceClusterId, 'A');
      expect(captured!.targetClusterId, 'B');
      expect(captured!.bridgeType, CrossZoneBridgeType.analogyStructural);
      expect(captured!.socraticQuestion, contains('comune'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 🎓 Triennial-scale (100+ clusters / 3-year canvas) behavior
  // ─────────────────────────────────────────────────────────────────────────

  group('CrossZoneBridgeController — triennial scale', () {
    test(
        'prompt picks the 12 largest zones by elementCount, not first-in-order',
        () async {
      // Simulate a 3-year canvas: 20 clusters. Cluster IDs ordered z0..z19;
      // strokeIds count grows backward so z19 has the most content.
      final clusters = <ContentCluster>[];
      final texts = <String, String>{};
      for (int i = 0; i < 20; i++) {
        final strokes = i + 1; // z0=1 stroke, z19=20 strokes
        clusters.add(ContentCluster(
          id: 'z$i',
          strokeIds: List.generate(strokes, (k) => 's${i}_$k'),
          bounds: Rect.fromCenter(
            center: Offset(i * 200.0, 0),
            width: 100,
            height: 100,
          ),
          centroid: Offset(i * 200.0, 0),
        ));
        texts['z$i'] = 'Long enough zone text for cluster z$i sufficient depth';
      }

      final flow = KnowledgeFlowController();
      final tel = _CapturingTelemetry();
      final ctrl = CrossZoneBridgeController(
        flowController: flow,
        telemetry: tel,
      );

      final fake = FakeGeminiProvider();
      fake.askFreeTextResponse = '';
      await ctrl.requestBridgeSuggestions(
        aiProvider: fake,
        clusters: clusters,
        clusterTexts: texts,
      );

      // Inspect the prompt the AI actually saw.
      expect(fake.askFreeTextPrompts, hasLength(1));
      final prompt = fake.askFreeTextPrompts.single;

      // Z19 (largest) MUST appear; z0 (smallest) MUST NOT.
      expect(prompt, contains('z19'),
          reason:
              'triennial scale: the largest zone is the one currently being studied');
      expect(prompt, isNot(contains('z0\n')),
          reason: 'the tiniest year-1 zone must not crowd out active material');

      // Telemetry exposes total_canvas_clusters for scale visibility.
      expect(tel.events.single.props['total_canvas_clusters'], 20);
      expect(tel.events.single.props['clusters_in_prompt'], 12);
    });

    test('pruneOldDismissedTombstones removes >90 days dismisses only',
        () async {
      final flow = KnowledgeFlowController();
      final ctrl = CrossZoneBridgeController(flowController: flow);

      // Two ghost connections: one created "now", one created 120 days ago.
      // Both are marked as dismissed tombstones.
      final now = DateTime.now().millisecondsSinceEpoch;
      const oneDayMs = 24 * 60 * 60 * 1000;
      final old = KnowledgeConnection(
        id: 'old_tomb',
        sourceClusterId: 'A',
        targetClusterId: 'B',
        isGhost: true,
        bridgeSuggestionDismissed: true,
        createdAt: now - 120 * oneDayMs,
      );
      final recent = KnowledgeConnection(
        id: 'recent_tomb',
        sourceClusterId: 'C',
        targetClusterId: 'D',
        isGhost: true,
        bridgeSuggestionDismissed: true,
        createdAt: now,
      );
      // The flow controller doesn't have a public addConnection-with-instance
      // API, but `connections` is unmodifiable so we go through the standard
      // add path — easier: just use addConnection() then mutate the flags.
      flow.addConnection(
        sourceClusterId: 'A',
        targetClusterId: 'B',
        isGhost: true,
      );
      flow.addConnection(
        sourceClusterId: 'C',
        targetClusterId: 'D',
        isGhost: true,
      );
      // Reach into the connections to backdate the first one.
      final addedOld = flow.connections.firstWhere(
        (c) => c.sourceClusterId == 'A' && c.targetClusterId == 'B',
      );
      final addedRecent = flow.connections.firstWhere(
        (c) => c.sourceClusterId == 'C' && c.targetClusterId == 'D',
      );
      addedOld.bridgeSuggestionDismissed = true;
      addedOld.createdAtMs = old.createdAtMs;
      addedRecent.bridgeSuggestionDismissed = true;

      expect(flow.connections, hasLength(2));

      final pruned = ctrl.pruneOldDismissedTombstones();
      expect(pruned, 1, reason: 'only the 120-day-old tombstone should be GC-d');
      expect(flow.connections, hasLength(1));
      expect(flow.connections.single.sourceClusterId, 'C');
    });
  });
}

ContentCluster _cluster(String id, Offset centroid) {
  return ContentCluster(
    id: id,
    strokeIds: ['s_$id'],
    bounds: Rect.fromCenter(center: centroid, width: 100, height: 100),
    centroid: centroid,
  );
}

class _CapturingTelemetry implements TelemetryRecorder {
  final List<({String event, Map<String, dynamic> props})> events = [];

  @override
  void logEvent(String eventType, {Map<String, dynamic>? properties}) {
    events.add((event: eventType, props: properties ?? const {}));
  }
}

class _AcceptedPayload {
  final String sourceClusterId;
  final String targetClusterId;
  final CrossZoneBridgeType bridgeType;
  final String socraticQuestion;
  _AcceptedPayload({
    required this.sourceClusterId,
    required this.targetClusterId,
    required this.bridgeType,
    required this.socraticQuestion,
  });
}
