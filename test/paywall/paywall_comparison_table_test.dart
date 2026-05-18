// ============================================================================
// 💳 PAYWALL COMPARISON TABLE — Default content + render smoke tests
//
// Locks the V1 launch copy so a typo in marketing strings (Free '100',
// Plus '500', Pro '2000') is caught before shipping a wrong number to
// the App Store screenshot.
// ============================================================================

import 'package:fluera_engine/fluera_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PaywallComparisonRowsV1 — V1 launch contract', () {
    test('credit allowance row matches AiCreditsCosts.monthlyAllowance', () {
      final row = PaywallComparisonRowsV1.rows.firstWhere(
        (r) => r.label.contains('Crediti AI'),
      );
      expect(row.free, '100');
      expect(row.plus, '500');
      expect(row.pro, '2000');
      expect(row.isPillar, isTrue,
          reason: 'AI credit allowance is a marketing pillar row');
    });

    test('Time Travel scrubber row is Pro-only and marked pillar', () {
      final row = PaywallComparisonRowsV1.rows.firstWhere(
        (r) => r.label.contains('Time Travel'),
      );
      expect(row.free, '—');
      expect(row.plus, '—');
      expect(row.pro, '✓');
      expect(row.isPillar, isTrue);
    });

    test('Collab row is Pro-only and marked pillar', () {
      final row = PaywallComparisonRowsV1.rows.firstWhere(
        (r) => r.label.contains('Collaborazione'),
      );
      expect(row.free, '—');
      expect(row.plus, '—');
      expect(row.pro, '✓');
      expect(row.isPillar, isTrue);
    });

    test('Audio-ink sync row is Pro-only and marked pillar', () {
      final row = PaywallComparisonRowsV1.rows.firstWhere(
        (r) => r.label.contains('Audio'),
      );
      expect(row.pro, '✓');
      expect(row.isPillar, isTrue);
    });

    test('Voice recording row matches Free — / Plus ∞ / Pro ∞', () {
      // V1.5 (2026-05-14 user pass): voice promoted to unlimited on Plus
      // so it stops being a Plus→Pro upgrade lever — Pro pillars own that.
      final row = PaywallComparisonRowsV1.rows.firstWhere(
        (r) => r.label.contains('Voice recording'),
      );
      expect(row.free, '—');
      expect(row.plus, '∞');
      expect(row.pro, '∞');
    });

    test('Multi-device row matches 1 / 2 / ∞', () {
      final row = PaywallComparisonRowsV1.rows.firstWhere(
        (r) => r.label.contains('Dispositivi'),
      );
      expect(row.free, '1');
      expect(row.plus, '2');
      expect(row.pro, '∞');
    });

    test('Cloud sync row matches Locale / 5 GB / 50 GB', () {
      final row = PaywallComparisonRowsV1.rows.firstWhere(
        (r) => r.label.contains('Cloud'),
      );
      expect(row.free, 'Locale');
      expect(row.plus, '5 GB');
      expect(row.pro, '50 GB');
    });

    test('Export formats row matches PNG-only Free, Tutti Plus+Pro', () {
      final row = PaywallComparisonRowsV1.rows.firstWhere(
        (r) => r.label.contains('Formati export'),
      );
      expect(row.free, 'PNG');
      expect(row.plus, 'Tutti');
      expect(row.pro, 'Tutti');
    });

    test('Default rows contain every V1 pillar (audio-ink / collab / time travel / bg OCR)',
        () {
      final pillars = PaywallComparisonRowsV1.rows.where((r) => r.isPillar);
      // 5 pillar rows (after V1.5 promotion of Background OCR to 4th Pro
      // pillar — see user pass 2026-05-14):
      //   1. AI credit allowance
      //   2. Time Travel scrubber
      //   3. Audio ↔ stroke sync
      //   4. Real-time collaboration
      //   5. Background OCR (NEW pillar — adds a solo-learner value lever)
      expect(pillars.length, 5);
    });

    test('Background OCR is marked pillar (Pro pillar #4, V1.5 promotion)', () {
      final row = PaywallComparisonRowsV1.rows.firstWhere(
        (r) => r.label.contains('Background OCR'),
      );
      expect(row.pro, '✓');
      expect(row.isPillar, isTrue,
          reason: 'Background OCR was promoted to 4th Pro pillar so '
              'solo-learners (no collab need) still see Pro value.');
    });
  });

  group('IncumbentsV1 — anti-rate-limit-nascosto comparison', () {
    test('Lists Notion AI / ChatGPT Plus / Notability + AI', () {
      final names = IncumbentsV1.entries.map((e) => e.name).toList();
      expect(names, contains('Notion AI'));
      expect(names, contains('ChatGPT Plus'));
      expect(names, contains('Notability + AI'));
    });

    test('Every incumbent entry has price + AI policy fields', () {
      for (final entry in IncumbentsV1.entries) {
        expect(entry.price, isNotEmpty);
        expect(entry.aiPolicy, isNotEmpty);
      }
    });
  });

  group('PaywallComparisonTable — smoke renders', () {
    testWidgets('Renders with defaults under MaterialApp', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: PaywallComparisonTable()),
        ),
      ));

      expect(find.text('Free'), findsOneWidget);
      expect(find.text('Plus'), findsOneWidget);
      expect(find.text('Pro'), findsOneWidget);
      // Header pricing.
      expect(find.text('€5,99'), findsOneWidget);
      expect(find.text('€11,99'), findsOneWidget);
      // Credit allowance numbers.
      expect(find.text('100'), findsOneWidget);
      expect(find.text('500'), findsOneWidget);
      expect(find.text('2000'), findsOneWidget);
    });

    testWidgets('Hides Spark Pack section when showSparkPackSection is false',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PaywallComparisonTable(showSparkPackSection: false),
          ),
        ),
      ));
      expect(find.textContaining('Spark Pack'), findsNothing);
    });

    testWidgets(
        'Default visibility follows V1FeatureGate.sparkPackVisible kill switch',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: PaywallComparisonTable()),
        ),
      ));
      if (V1FeatureGate.sparkPackVisible) {
        expect(find.textContaining('Spark Pack'), findsAtLeast(1));
      } else {
        expect(find.textContaining('Spark Pack'), findsNothing,
            reason: 'kill switch off → section must be hidden');
      }
    });

    testWidgets('Explicit showSparkPackSection: true overrides the kill switch',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PaywallComparisonTable(showSparkPackSection: true),
          ),
        ),
      ));
      expect(find.textContaining('Spark Pack'), findsAtLeast(1));
    });

    testWidgets('Renders incumbents block by default (trasparenza row)',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: PaywallComparisonTable()),
        ),
      ));
      expect(find.text('Notion AI'), findsOneWidget);
      expect(find.text('ChatGPT Plus'), findsOneWidget);
    });

    testWidgets('Shows "Attuale" badge for the current tier column',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PaywallComparisonTable(
              currentTier: FlueraSubscriptionTier.plus,
            ),
          ),
        ),
      ));
      // One "Attuale" badge — only the Plus header.
      expect(find.text('Attuale'), findsOneWidget);
    });

    testWidgets('"Attuale" badge rebuilds when currentTier changes',
        (tester) async {
      // Drive the table with a parent that swaps currentTier on tap so the
      // host's `ValueListenableBuilder<FlueraSubscriptionTier>` pattern is
      // reflected: change tier → rebuild → badge follows.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: _TierSwitcher(),
          ),
        ),
      ));

      // Free tier first.
      expect(find.text('Attuale'), findsOneWidget);
      final tierLabelFree = tester.widget<Text>(
        find.descendant(
          of: find.byType(Column).first,
          matching: find.byWidgetPredicate(
            (w) => w is Text && (w.data == 'Free' || w.data == 'Plus' || w.data == 'Pro'),
          ),
        ).first,
      );
      expect(tierLabelFree.data, 'Free');

      // Tap the "go Plus" button.
      await tester.tap(find.text('go plus'));
      await tester.pump();
      expect(find.text('Attuale'), findsOneWidget,
          reason: 'Badge must still render exactly once after tier swap');

      // Tap "go Pro".
      await tester.tap(find.text('go pro'));
      await tester.pump();
      expect(find.text('Attuale'), findsOneWidget,
          reason: 'Badge shifts to Pro column without leaking duplicates');
    });

    testWidgets('Pillar rows are present (Pro=✓ on time travel / collab / audio-ink / bg OCR)',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: PaywallComparisonTable()),
        ),
      ));
      // Pillar row labels must render.
      expect(find.text('Time Travel scrubber'), findsOneWidget);
      expect(find.text('Collaborazione real-time'), findsOneWidget);
      expect(find.text('Audio ↔ stroke sync'), findsOneWidget);
      expect(find.text('🔍 Background OCR proattivo'), findsOneWidget);
    });
  });
}

/// Tiny harness widget that flips the table's currentTier on tap so we
/// can assert the `Attuale` badge truly follows the prop (no stale state
/// from a previous build).
class _TierSwitcher extends StatefulWidget {
  @override
  State<_TierSwitcher> createState() => _TierSwitcherState();
}

class _TierSwitcherState extends State<_TierSwitcher> {
  FlueraSubscriptionTier _tier = FlueraSubscriptionTier.free;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            TextButton(
              onPressed: () =>
                  setState(() => _tier = FlueraSubscriptionTier.plus),
              child: const Text('go plus'),
            ),
            TextButton(
              onPressed: () =>
                  setState(() => _tier = FlueraSubscriptionTier.pro),
              child: const Text('go pro'),
            ),
          ],
        ),
        PaywallComparisonTable(currentTier: _tier),
      ],
    );
  }
}
