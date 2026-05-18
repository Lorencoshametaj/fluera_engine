import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/canvas/fluera_canvas_config.dart'
    show FlueraSubscriptionTier;
import 'package:fluera_engine/src/canvas/widgets/version_history_panel.dart';
import 'package:fluera_engine/src/history/version_history.dart';
import 'package:fluera_engine/src/l10n/generated/fluera_localizations.g.dart';

Widget _harness(Widget child, {Locale locale = const Locale('it')}) {
  return MaterialApp(
    home: Scaffold(body: child),
    localizationsDelegates: FlueraLocalizations.localizationsDelegates,
    supportedLocales: FlueraLocalizations.supportedLocales,
    locale: locale,
  );
}

void main() {
  group('VersionHistoryPanel — counter visibility per tier', () {
    testWidgets('Free: counter "0/3" visibile su empty', (tester) async {
      final history = VersionHistory();
      await tester.pumpWidget(_harness(VersionHistoryPanel(
        history: history,
        tier: FlueraSubscriptionTier.free,
      )));

      expect(find.textContaining('0/3'), findsOneWidget);
    });

    testWidgets('Plus: counter NON visibile', (tester) async {
      final history = VersionHistory();
      await tester.pumpWidget(_harness(VersionHistoryPanel(
        history: history,
        tier: FlueraSubscriptionTier.plus,
      )));

      expect(find.textContaining('/3'), findsNothing);
      expect(find.textContaining('Checkpoint usati'), findsNothing);
    });

    testWidgets('Pro: counter NON visibile', (tester) async {
      final history = VersionHistory();
      await tester.pumpWidget(_harness(VersionHistoryPanel(
        history: history,
        tier: FlueraSubscriptionTier.pro,
      )));

      expect(find.textContaining('/3'), findsNothing);
    });

    testWidgets('Free: counter aggiornato a "2/3" dopo 2 save', (tester) async {
      final history = VersionHistory();
      history.createEntry(title: 'a', authorId: 'u', data: {});
      history.createEntry(title: 'b', authorId: 'u', data: {});

      await tester.pumpWidget(_harness(VersionHistoryPanel(
        history: history,
        tier: FlueraSubscriptionTier.free,
      )));

      expect(find.textContaining('2/3'), findsOneWidget);
    });
  });

  group('VersionHistoryPanel — empty state copy', () {
    testWidgets('IT: mostra empty state "Nessun checkpoint ancora"',
        (tester) async {
      await tester.pumpWidget(_harness(VersionHistoryPanel(
        history: VersionHistory(),
        tier: FlueraSubscriptionTier.plus,
      )));
      expect(find.text('Nessun checkpoint ancora'), findsOneWidget);
    });

    testWidgets('EN: mostra empty state "No checkpoints yet"',
        (tester) async {
      await tester.pumpWidget(_harness(
        VersionHistoryPanel(
          history: VersionHistory(),
          tier: FlueraSubscriptionTier.plus,
        ),
        locale: const Locale('en'),
      ));
      expect(find.text('No checkpoints yet'), findsOneWidget);
    });
  });

  group('VersionHistoryPanel — upsell modal at Free limit', () {
    testWidgets('Free at 3/3: tap "+" opens upsell modal, not save dialog',
        (tester) async {
      final history = VersionHistory();
      history.createEntry(title: 'a', authorId: 'u', data: {});
      history.createEntry(title: 'b', authorId: 'u', data: {});
      history.createEntry(title: 'c', authorId: 'u', data: {});

      bool upgradePressed = false;
      await tester.pumpWidget(_harness(VersionHistoryPanel(
        history: history,
        tier: FlueraSubscriptionTier.free,
        onUpgradePressed: () => upgradePressed = true,
      )));

      // Counter 3/3 visible
      expect(find.textContaining('3/3'), findsOneWidget);

      // Tap the "+" icon in the header
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      // Upsell modal title visible — NOT the save dialog
      expect(find.text('Hai raggiunto il limite del piano Free'), findsOneWidget);
      expect(find.text('Passa a Plus'), findsOneWidget);

      // Tap upgrade — fires the callback
      await tester.tap(find.text('Passa a Plus'));
      await tester.pumpAndSettle();
      expect(upgradePressed, isTrue);
    });

    testWidgets('Plus at 3+: tap "+" opens save dialog (no cap)',
        (tester) async {
      final history = VersionHistory();
      for (var i = 0; i < 5; i++) {
        history.createEntry(title: 'cp$i', authorId: 'u', data: {});
      }

      await tester.pumpWidget(_harness(VersionHistoryPanel(
        history: history,
        tier: FlueraSubscriptionTier.plus,
      )));

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      // Save dialog title — NOT upsell
      expect(find.text('Salva checkpoint'), findsAtLeastNWidgets(1));
      expect(find.text('Hai raggiunto il limite del piano Free'), findsNothing);
    });
  });
}
