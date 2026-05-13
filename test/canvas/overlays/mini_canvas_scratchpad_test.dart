// ============================================================================
// 🖋️ MINI CANVAS SCRATCHPAD — Widget tests for the read-only viewer mode.
//
// The scratchpad has two faces:
//   • Writable (exam answer) — pen draws, OCR fires, undo/clear visible.
//   • Read-only (past-answer review) — input ignored, toolbar buttons hidden,
//     no OCR debounce, hint text suppressed. Pinch + pan still work for
//     inspection.
//
// These tests pin down the read-only contract so a future refactor doesn't
// silently re-enable drawing in the dashboard's review screen.
// ============================================================================

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/canvas/overlays/components/mini_canvas_scratchpad.dart';
import 'package:fluera_engine/src/drawing/models/pro_drawing_point.dart';

ProStroke _stroke({String id = 's1', int n = 5}) {
  return ProStroke(
    id: id,
    points: List.generate(
      n,
      (i) => ProDrawingPoint(
        position: Offset(50 + i * 8.0, 60 + i * 4.0),
        pressure: 0.8,
        timestamp: 1700000000000 + i,
      ),
    ),
    color: const Color(0xFF00FFCC),
    baseWidth: 2.5,
    penType: ProPenType.ballpoint,
    createdAt: DateTime.utc(2026, 5, 8),
  );
}

/// Wraps a [MiniCanvasScratchpad] in a sized container so the painter has
/// a concrete surface to lay out against.
Widget _harness(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(width: 400, height: 280, child: child),
    ),
  );
}

void main() {
  group('MiniCanvasScratchpad — read-only mode', () {
    testWidgets('Hides the empty-state hint', (tester) async {
      await tester.pumpWidget(_harness(
        MiniCanvasScratchpad(
          onRecognizedText: (_) {},
          readOnly: true,
        ),
      ));
      await tester.pump();

      expect(
        find.text('Scrivi qui la tua risposta a mano…'),
        findsNothing,
        reason: 'a read-only viewer with no strokes must not invite drawing',
      );
    });

    testWidgets('Shows the hint in writable mode (sanity check)', (tester) async {
      await tester.pumpWidget(_harness(
        MiniCanvasScratchpad(onRecognizedText: (_) {}),
      ));
      await tester.pump();

      expect(find.text('Scrivi qui la tua risposta a mano…'), findsOneWidget);
    });

    testWidgets('Hides undo + clear buttons even with initial strokes',
        (tester) async {
      await tester.pumpWidget(_harness(
        MiniCanvasScratchpad(
          onRecognizedText: (_) {},
          readOnly: true,
          initialStrokes: [_stroke(id: 'a'), _stroke(id: 'b')],
        ),
      ));
      // Allow the post-frame fit-to-content callback + setState.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byIcon(Icons.undo), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });

    testWidgets(
        'Writable mode shows undo + clear when strokes exist (sanity check)',
        (tester) async {
      await tester.pumpWidget(_harness(
        MiniCanvasScratchpad(
          onRecognizedText: (_) {},
          initialStrokes: [_stroke(id: 'a')],
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byIcon(Icons.undo), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('Stylus input does NOT add a stroke in read-only mode',
        (tester) async {
      final key = GlobalKey<MiniCanvasScratchpadState>();
      await tester.pumpWidget(_harness(
        MiniCanvasScratchpad(
          key: key,
          onRecognizedText: (_) {},
          readOnly: true,
        ),
      ));
      await tester.pump();

      expect(key.currentState!.currentStrokes, isEmpty);

      // Simulate a stylus stroke through the centre.
      final centre = tester.getCenter(find.byType(MiniCanvasScratchpad));
      final gesture = await tester.startGesture(
        centre,
        kind: PointerDeviceKind.stylus,
      );
      await gesture.moveTo(centre + const Offset(50, 30));
      await gesture.moveTo(centre + const Offset(80, 60));
      await gesture.up();
      await tester.pump();

      // Even after the gesture, no stroke is committed.
      expect(
        key.currentState!.currentStrokes,
        isEmpty,
        reason: 'read-only must reject stylus drawing',
      );
    });

    testWidgets('flushPendingRecognition is a safe no-op on empty viewer',
        (tester) async {
      final key = GlobalKey<MiniCanvasScratchpadState>();
      await tester.pumpWidget(_harness(
        MiniCanvasScratchpad(
          key: key,
          onRecognizedText: (_) {
            fail('OCR must not fire in read-only mode');
          },
          readOnly: true,
        ),
      ));
      await tester.pump();

      // Should not throw, should not emit text.
      await key.currentState!.flushPendingRecognition();
      await tester.pump();
    });
  });

  group('MiniCanvasScratchpad — initial strokes', () {
    testWidgets('Initial strokes are exposed via currentStrokes',
        (tester) async {
      final key = GlobalKey<MiniCanvasScratchpadState>();
      final initial = [_stroke(id: 'first', n: 3), _stroke(id: 'second', n: 8)];
      await tester.pumpWidget(_harness(
        MiniCanvasScratchpad(
          key: key,
          onRecognizedText: (_) {},
          readOnly: true,
          initialStrokes: initial,
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final loaded = key.currentState!.currentStrokes;
      expect(loaded.map((s) => s.id), containsAll(['first', 'second']));
      expect(loaded.length, 2);
    });

    testWidgets('loadStrokes replaces the current stroke list',
        (tester) async {
      final key = GlobalKey<MiniCanvasScratchpadState>();
      await tester.pumpWidget(_harness(
        MiniCanvasScratchpad(
          key: key,
          onRecognizedText: (_) {},
          readOnly: true,
          initialStrokes: [_stroke(id: 'old')],
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(key.currentState!.currentStrokes.first.id, 'old');

      key.currentState!.loadStrokes([_stroke(id: 'new1'), _stroke(id: 'new2')]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final cur = key.currentState!.currentStrokes;
      expect(cur.length, 2);
      expect(cur.map((s) => s.id), containsAll(['new1', 'new2']));
    });
  });
}
