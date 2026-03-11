import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/canvas/overlays/inline_text_overlay.dart';

void main() {
  group('InlineTextOverlay', () {
    late String? submittedText;
    late bool cancelCalled;

    setUp(() {
      submittedText = null;
      cancelCalled = false;
    });

    Widget buildOverlay({
      String initialText = '',
      Color color = Colors.black,
      double fontSize = 24.0,
      FontWeight fontWeight = FontWeight.normal,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: 100,
                top: 100,
                child: SizedBox(
                  width: 300,
                  child: InlineTextOverlay(
                    initialText: initialText,
                    color: color,
                    fontSize: fontSize,
                    fontWeight: fontWeight,
                    canvasScale: 1.0,
                    elementScale: 1.0,
                    onSubmit: (text) => submittedText = text,
                    onCancel: () => cancelCalled = true,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    testWidgets('renders with autofocus', (tester) async {
      await tester.pumpWidget(buildOverlay());
      await tester.pump();

      expect(find.byType(TextField), findsOneWidget);

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.autofocus, isTrue);
    });

    testWidgets('shows initial text when editing', (tester) async {
      await tester.pumpWidget(buildOverlay(initialText: 'Hello World'));
      await tester.pump();

      expect(find.text('Hello World'), findsOneWidget);
    });

    testWidgets('applies font styling', (tester) async {
      await tester.pumpWidget(
        buildOverlay(
          color: Colors.red,
          fontSize: 36.0,
          fontWeight: FontWeight.bold,
        ),
      );
      await tester.pump();

      final textField = tester.widget<TextField>(find.byType(TextField));
      final style = textField.style!;
      expect(style.color, Colors.red);
      expect(style.fontSize, 36.0);
      expect(style.fontWeight, FontWeight.bold);
    });

    testWidgets('onSubmit called on Enter key', (tester) async {
      await tester.pumpWidget(buildOverlay());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'Test text');
      await tester.pump();

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(submittedText, 'Test text');
    });

    testWidgets('empty text triggers onCancel', (tester) async {
      await tester.pumpWidget(buildOverlay());
      await tester.pump();

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(cancelCalled, isTrue);
    });

    testWidgets('onCancel called on Escape key', (tester) async {
      await tester.pumpWidget(buildOverlay(initialText: 'some text'));
      await tester.pump();

      await tester.tap(find.byType(TextField));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(cancelCalled, isTrue);
    });

    testWidgets('no border decoration on TextField', (tester) async {
      await tester.pumpWidget(buildOverlay());
      await tester.pump();

      final textField = tester.widget<TextField>(find.byType(TextField));
      final decoration = textField.decoration!;
      expect(decoration.border, InputBorder.none);
    });

    testWidgets('cursor color matches text color', (tester) async {
      await tester.pumpWidget(buildOverlay(color: Colors.blue));
      await tester.pump();

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.cursorColor, Colors.blue);
    });

    testWidgets('text scaling is applied correctly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  left: 100,
                  top: 100,
                  child: SizedBox(
                    width: 300,
                    child: InlineTextOverlay(
                      fontSize: 24.0,
                      canvasScale: 2.0,
                      elementScale: 1.5,
                      onSubmit: (_) {},
                      onCancel: () {},
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      final textField = tester.widget<TextField>(find.byType(TextField));
      // 24.0 * 1.5 * 2.0 = 72.0
      expect(textField.style!.fontSize, 72.0);
    });

    testWidgets('shows placeholder hint when empty', (tester) async {
      await tester.pumpWidget(buildOverlay());
      await tester.pump();

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.decoration!.hintText, 'Digita qui...');
    });

    testWidgets('has animated entrance (ScaleTransition)', (tester) async {
      await tester.pumpWidget(buildOverlay());
      await tester.pump();

      // V2: overlay uses ScaleTransition for entrance animation
      expect(find.byType(ScaleTransition), findsAtLeast(1));
    });

    testWidgets('cursor width is 2.5', (tester) async {
      await tester.pumpWidget(buildOverlay());
      await tester.pump();

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.cursorWidth, 2.5);
    });
  });
}
