import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/history/guide_commands.dart';
import 'package:fluera_engine/src/history/command_history.dart';
import 'package:fluera_engine/src/tools/ruler/ruler_guide_system.dart';

void main() {
  late RulerGuideSystem guideSystem;
  late CommandHistory history;

  setUp(() {
    guideSystem = RulerGuideSystem();
    history = CommandHistory();
  });

  // ===========================================================================
  // AddGuideCommand
  // ===========================================================================

  group('AddGuideCommand', () {
    test('execute adds a horizontal guide', () {
      final cmd = AddGuideCommand(
        guideSystem: guideSystem,
        isHorizontal: true,
        position: 100.0,
      );

      history.execute(cmd);

      expect(guideSystem.horizontalGuides, contains(100.0));
    });

    test('execute adds a vertical guide', () {
      final cmd = AddGuideCommand(
        guideSystem: guideSystem,
        isHorizontal: false,
        position: 200.0,
      );

      history.execute(cmd);

      expect(guideSystem.verticalGuides, contains(200.0));
    });

    test('undo removes the guide', () {
      final cmd = AddGuideCommand(
        guideSystem: guideSystem,
        isHorizontal: true,
        position: 100.0,
      );

      history.execute(cmd);
      final countAfterAdd = guideSystem.horizontalGuides.length;

      history.undo();
      expect(guideSystem.horizontalGuides.length, lessThan(countAfterAdd));
    });

    test('redo re-adds the guide', () {
      final cmd = AddGuideCommand(
        guideSystem: guideSystem,
        isHorizontal: false,
        position: 200.0,
      );

      history.execute(cmd);
      history.undo();
      history.redo();

      expect(guideSystem.verticalGuides, contains(200.0));
    });
  });

  // ===========================================================================
  // ClearAllGuidesCommand
  // ===========================================================================

  group('ClearAllGuidesCommand', () {
    test('clears all guides', () {
      history.execute(
        AddGuideCommand(
          guideSystem: guideSystem,
          isHorizontal: true,
          position: 50.0,
        ),
      );
      history.execute(
        AddGuideCommand(
          guideSystem: guideSystem,
          isHorizontal: false,
          position: 75.0,
        ),
      );

      final clearCmd = ClearAllGuidesCommand(guideSystem: guideSystem);
      history.execute(clearCmd);

      expect(guideSystem.horizontalGuides, isEmpty);
      expect(guideSystem.verticalGuides, isEmpty);
    });

    test('undo restores guides', () {
      history.execute(
        AddGuideCommand(
          guideSystem: guideSystem,
          isHorizontal: true,
          position: 50.0,
        ),
      );

      final totalBefore =
          guideSystem.horizontalGuides.length +
          guideSystem.verticalGuides.length;

      final clearCmd = ClearAllGuidesCommand(guideSystem: guideSystem);
      history.execute(clearCmd);
      history.undo();

      final totalAfter =
          guideSystem.horizontalGuides.length +
          guideSystem.verticalGuides.length;
      expect(totalAfter, totalBefore);
    });
  });

  // ===========================================================================
  // MoveGuideCommand
  // ===========================================================================

  group('MoveGuideCommand', () {
    test('canMergeWith returns true for same guide', () {
      // Add a guide first so index 0 exists
      guideSystem.addHorizontalGuide(100.0);

      final cmd1 = MoveGuideCommand(
        guideSystem: guideSystem,
        isHorizontal: true,
        index: 0,
        newPosition: 110,
      );
      final cmd2 = MoveGuideCommand(
        guideSystem: guideSystem,
        isHorizontal: true,
        index: 0,
        newPosition: 120,
      );

      expect(cmd1.canMergeWith(cmd2), true);
    });

    test('canMergeWith returns false for different guides', () {
      guideSystem.addHorizontalGuide(100.0);
      guideSystem.addHorizontalGuide(200.0);

      final cmd1 = MoveGuideCommand(
        guideSystem: guideSystem,
        isHorizontal: true,
        index: 0,
        newPosition: 110,
      );
      final cmd2 = MoveGuideCommand(
        guideSystem: guideSystem,
        isHorizontal: true,
        index: 1,
        newPosition: 210,
      );

      expect(cmd1.canMergeWith(cmd2), false);
    });
  });
}
