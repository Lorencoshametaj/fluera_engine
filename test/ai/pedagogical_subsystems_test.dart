// ============================================================================
// 🧪 UNIT TESTS — Red Wall, Content Taxonomy, Accessibility, Passeggiata,
//                  Interleaving Path, Step Transition Choreographer
//
// QA Criteria: CA-A10, CA-A11, CA-A13, CA-A20
// ============================================================================

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/canvas/ai/red_wall_controller.dart';
import 'package:fluera_engine/src/canvas/ai/content_taxonomy.dart';
import 'package:fluera_engine/src/canvas/ai/pedagogical_accessibility_config.dart';
import 'package:fluera_engine/src/canvas/ai/passeggiata_controller.dart';
import 'package:fluera_engine/src/canvas/ai/interleaving_path_controller.dart';
import 'package:fluera_engine/src/canvas/ai/step_transition_choreographer.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // RED WALL (A20.4.1)
  // ═══════════════════════════════════════════════════════════════════════════

  group('RedWallController', () {
    test('inactive when below 70% threshold', () {
      final eval = RedWallController.evaluate(
        forgottenCount: 5,
        totalCount: 10,
      );
      expect(eval.isActive, isFalse);
      expect(eval.ratio, 0.5);
    });

    test('active when above 70% threshold (A20-47)', () {
      final eval = RedWallController.evaluate(
        forgottenCount: 8,
        totalCount: 10,
      );
      expect(eval.isActive, isTrue);
      expect(eval.ratio, 0.8);
    });

    test('boundary: exactly 70% is NOT triggered (>70%)', () {
      final eval = RedWallController.evaluate(
        forgottenCount: 7,
        totalCount: 10,
      );
      expect(eval.isActive, isFalse);
    });

    test('volume reduction: max(10, N×0.3) (A20-50)', () {
      final eval = RedWallController.evaluate(
        forgottenCount: 45,
        totalCount: 50,
      );
      expect(eval.isActive, isTrue);
      // 50 × 0.3 = 15. max(10, 15) = 15
      expect(eval.suggestedNextSessionSize, 15);
    });

    test('volume reduction: minimum 10 nodes (A20-50)', () {
      final eval = RedWallController.evaluate(
        forgottenCount: 10,
        totalCount: 12,
      );
      expect(eval.isActive, isTrue);
      // 12 × 0.3 = 3.6 → 4. max(10, 4) = 10
      expect(eval.suggestedNextSessionSize, 10);
    });

    test('protective message has no negative words (A20-49)', () {
      final msg = RedWallController.protectiveMessage(15);
      expect(msg, contains('zone da rafforzare'));
      // Anti-pattern check: no "errore", "sbagliato", "fallimento"
      expect(msg.toLowerCase(), isNot(contains('errore')));
      expect(msg.toLowerCase(), isNot(contains('sbagliato')));
      expect(msg.toLowerCase(), isNot(contains('fallimento')));
    });

    test('forgottenNodeColor: grey when active (A20-48)', () {
      expect(
        RedWallController.forgottenNodeColor(RedWallState.active),
        const Color(0xFF888888),
      );
      expect(
        RedWallController.forgottenNodeColor(RedWallState.inactive),
        const Color(0xFFFF3B30),
      );
    });

    test('calibrateNextSession guarantees comfort node (A20-51)', () {
      final nodes = ['a', 'b', 'c', 'd', 'e'];
      final levels = {'a': 1, 'b': 1, 'c': 2, 'd': 1, 'e': 4};
      final selected = RedWallController.calibrateNextSession(
        allNodeIds: nodes,
        recallLevels: levels,
        maxNodes: 3,
      );
      // Must contain at least one comfort node (recall ≥ 4).
      expect(selected.any((id) => (levels[id] ?? 0) >= 4), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // CONTENT TAXONOMY (A20.3)
  // ═══════════════════════════════════════════════════════════════════════════

  group('ContentTaxonomy', () {
    test('generated content has full SRS weight', () {
      expect(InputMethod.generated.srsStabilityModifier, 1.0);
      expect(InputMethod.generated.isTrackedBySrs, isTrue);
      expect(InputMethod.generated.isSocraticTarget, isTrue);
    });

    test('pasted content has low SRS weight (A20-60)', () {
      expect(InputMethod.pasted.srsStabilityModifier, 0.3);
      expect(InputMethod.pasted.isTrackedBySrs, isTrue);
      expect(InputMethod.pasted.isSocraticTarget, isFalse);
      expect(InputMethod.pasted.needsVisualDistinction, isTrue);
    });

    test('reference content excluded from SRS', () {
      expect(InputMethod.reference.srsStabilityModifier, 0.0);
      expect(InputMethod.reference.isTrackedBySrs, isFalse);
    });

    test('AI content has half SRS weight', () {
      expect(InputMethod.aiGenerated.srsStabilityModifier, 0.5);
      expect(InputMethod.aiGenerated.isSocraticTarget, isFalse);
    });

    test('adjustInitialStability scales correctly', () {
      final pasted = ContentTaxonomy.pasted();
      expect(pasted.adjustInitialStability(10.0), 3.0); // 10 × 0.3

      final generated = ContentTaxonomy.generated();
      expect(generated.adjustInitialStability(10.0), 10.0); // 10 × 1.0
    });

    test('pasted content visual properties (A20-58)', () {
      final pasted = ContentTaxonomy.pasted();
      expect(pasted.useDashedBorder, isTrue);
      expect(pasted.opacityMultiplier, 0.90);
    });

    test('serialization round-trip', () {
      final original = ContentTaxonomy.pasted(sourceId: 'clipboard_123');
      final json = original.toJson();
      final restored = ContentTaxonomy.fromJson(json);
      expect(restored.inputMethod, InputMethod.pasted);
      expect(restored.sourceId, 'clipboard_123');
    });

    test('reclassify creates new instance', () {
      final pasted = ContentTaxonomy.pasted();
      final reclassified = pasted.reclassify(InputMethod.generated);
      expect(reclassified.inputMethod, InputMethod.generated);
      expect(reclassified.manuallyReclassified, isTrue);
      expect(pasted.inputMethod, InputMethod.pasted); // Original unchanged
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ACCESSIBILITY (A11)
  // ═══════════════════════════════════════════════════════════════════════════

  group('PedagogicalAccessibilityConfig', () {
    test('default config has all features off', () {
      const config = PedagogicalAccessibilityConfig.defaultConfig;
      expect(config.isColorblindModeEnabled, isFalse);
      expect(config.isKeyboardModeEnabled, isFalse);
      expect(config.isHighContrastBlurEnabled, isFalse);
    });

    test('standard palette returns correct colors', () {
      const config = PedagogicalAccessibilityConfig.defaultConfig;
      expect(config.resolveColor(SemanticColor.correct),
          const Color(0xFF4CAF50));
      expect(config.resolveColor(SemanticColor.missing),
          const Color(0xFFFF3B30));
    });

    test('colorblind palette returns different colors (A11-02)', () {
      const config = PedagogicalAccessibilityConfig(
        isColorblindModeEnabled: true,
      );
      expect(config.resolveColor(SemanticColor.correct),
          const Color(0xFF00C9DB)); // Cyan, not green
      expect(config.resolveColor(SemanticColor.missing),
          const Color(0xFFFF6B35)); // Orange, not red
    });

    test('icon redundancy provides secondary channel (A11-01)', () {
      expect(PedagogicalAccessibilityConfig.iconFor(SemanticColor.correct),
          '✅');
      expect(PedagogicalAccessibilityConfig.iconFor(SemanticColor.missing),
          '❌');
    });

    test('fill patterns for Ghost Map (A11-03)', () {
      expect(
        PedagogicalAccessibilityConfig.fillPatternFor(SemanticColor.missing),
        GhostMapFillPattern.diagonalHatch,
      );
      expect(
        PedagogicalAccessibilityConfig.fillPatternFor(SemanticColor.wrongEdge),
        GhostMapFillPattern.dots,
      );
    });

    test('serialization round-trip', () {
      const original = PedagogicalAccessibilityConfig(
        isColorblindModeEnabled: true,
        isKeyboardModeEnabled: true,
      );
      final json = original.toJson();
      final restored = PedagogicalAccessibilityConfig.fromJson(json);
      expect(restored.isColorblindModeEnabled, isTrue);
      expect(restored.isKeyboardModeEnabled, isTrue);
      expect(restored.isHighContrastBlurEnabled, isFalse);
    });

    test('copyWith creates modified copy', () {
      const original = PedagogicalAccessibilityConfig.defaultConfig;
      final modified = original.copyWith(isColorblindModeEnabled: true);
      expect(modified.isColorblindModeEnabled, isTrue);
      expect(original.isColorblindModeEnabled, isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // PASSEGGIATA (A10)
  // ═══════════════════════════════════════════════════════════════════════════

  group('PasseggiataController', () {
    late PasseggiataController controller;

    setUp(() => controller = PasseggiataController());
    tearDown(() => controller.dispose());

    test('starts inactive', () {
      expect(controller.state, PasseggiataState.inactive);
      expect(controller.isActive, isFalse);
    });

    test('activation transitions to entering (A10-01)', () {
      controller.activate();
      expect(controller.state, PasseggiataState.entering);
      expect(controller.isActive, isTrue);
      expect(controller.isTransitioning, isTrue);
    });

    test('completeEntry transitions to active', () {
      controller.activate();
      controller.completeEntry();
      expect(controller.state, PasseggiataState.active);
      expect(controller.isFullyActive, isTrue);
    });

    test('tracking is disabled when active (A10-06)', () {
      controller.activate();
      controller.completeEntry();
      expect(controller.isTrackingDisabled, isTrue);
    });

    test('tracking is enabled when inactive', () {
      expect(controller.isTrackingDisabled, isFalse);
    });

    test('vignette opacity: 0.1 when active (A10-02)', () {
      controller.activate();
      controller.completeEntry();
      expect(controller.targetVignetteOpacity, 0.1);
    });

    test('vignette opacity: 0.0 when inactive', () {
      expect(controller.targetVignetteOpacity, 0.0);
    });

    test('toolbar minimized when active (A10-02)', () {
      controller.activate();
      controller.completeEntry();
      expect(controller.shouldMinimizeToolbar, isTrue);
    });

    test('guided path lifecycle (A10-04)', () {
      controller.activate(clusterIds: ['a', 'b', 'c']);
      expect(controller.hasGuidedPath, isTrue);
      expect(controller.guidedPath!.clusterIds, ['a', 'b', 'c']);

      controller.dismissGuidedPath();
      expect(controller.hasGuidedPath, isFalse);
    });

    test('deactivation + completeExit resets', () {
      controller.activate(clusterIds: ['a']);
      controller.completeEntry();
      controller.deactivate();
      expect(controller.state, PasseggiataState.exiting);
      controller.completeExit();
      expect(controller.state, PasseggiataState.inactive);
      expect(controller.guidedPath, isNull);
    });

    test('cannot activate twice', () {
      controller.activate();
      controller.activate(); // Should be ignored
      expect(controller.state, PasseggiataState.entering);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // INTERLEAVING PATH (P6-15, P8-10)
  // ═══════════════════════════════════════════════════════════════════════════

  group('InterleavingPathController', () {
    late InterleavingPathController controller;

    setUp(() => controller = InterleavingPathController());
    tearDown(() => controller.dispose());

    test('starts hidden with no nodes', () {
      expect(controller.state, InterleavingPathState.hidden);
      expect(controller.pathNodes, isEmpty);
      expect(controller.isVisible, isFalse);
    });

    test('generates interleaved path with multiple topics', () {
      controller.generate(
        nodes: [
          const PathNode(clusterId: 'a', position: Offset(0, 0), topic: 'math'),
          const PathNode(clusterId: 'b', position: Offset(100, 0), topic: 'physics'),
          const PathNode(clusterId: 'c', position: Offset(50, 50), topic: 'math'),
          const PathNode(clusterId: 'd', position: Offset(150, 50), topic: 'physics'),
        ],
        topicAssignments: {
          'a': 'math', 'b': 'physics', 'c': 'math', 'd': 'physics',
        },
      );

      expect(controller.pathNodes.length, 4);

      // Verify interleaving: consecutive nodes should have different topics
      for (int i = 0; i < controller.pathNodes.length - 1; i++) {
        final current = controller.pathNodes[i].topic;
        final next = controller.pathNodes[i + 1].topic;
        // With 2 topics and 2+2 nodes, full interleaving is possible
        expect(current != next, isTrue,
            reason: 'Nodes $i and ${i + 1} should have different topics');
      }
    });

    test('pre-computes Float64List segments', () {
      controller.generate(
        nodes: [
          const PathNode(clusterId: 'a', position: Offset(0, 0)),
          const PathNode(clusterId: 'b', position: Offset(100, 100)),
          const PathNode(clusterId: 'c', position: Offset(200, 50)),
        ],
      );
      expect(controller.pathSegments, isNotNull);
      // 2 segments × 4 doubles each = 8
      expect(controller.pathSegments!.length, 8);
    });

    test('animation lifecycle', () {
      controller.generate(
        nodes: [
          const PathNode(clusterId: 'a', position: Offset(0, 0)),
          const PathNode(clusterId: 'b', position: Offset(100, 100)),
        ],
      );
      controller.startAnimation();
      expect(controller.state, InterleavingPathState.animating);
      expect(controller.isVisible, isTrue);

      controller.updateProgress(0.5);
      expect(controller.animationProgress, 0.5);

      controller.completeAnimation();
      expect(controller.state, InterleavingPathState.visible);
      expect(controller.animationProgress, 1.0);
    });

    test('dismiss hides path', () {
      controller.generate(
        nodes: [
          const PathNode(clusterId: 'a', position: Offset(0, 0)),
          const PathNode(clusterId: 'b', position: Offset(100, 100)),
        ],
      );
      controller.startAnimation();
      controller.completeAnimation();
      controller.dismiss();
      expect(controller.state, InterleavingPathState.dismissed);
      expect(controller.isVisible, isFalse);
    });

    test('rendering constants are correct', () {
      expect(InterleavingPathController.pathColor, const Color(0xFFFFD700));
      expect(InterleavingPathController.strokeWidth, 2.0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP TRANSITION CHOREOGRAPHER (A13.1, A13.2)
  // ═══════════════════════════════════════════════════════════════════════════

  group('StepTransitionChoreographer', () {
    late StepTransitionChoreographer choreographer;

    setUp(() => choreographer = StepTransitionChoreographer());
    tearDown(() => choreographer.dispose());

    test('P1→P2 transition: 800ms, single medium haptic (A13-T01)', () {
      choreographer.transitionTo(fromStep: 1, toStep: 2);
      expect(choreographer.isTransitioning, isTrue);
      final event = choreographer.currentTransition!;
      expect(event.fromStep, 1);
      expect(event.toStep, 2);
      expect(event.durationMs, 800);
      expect(event.haptic, TransitionHaptic.singleMedium);
      expect(event.sound, TransitionSound.lowCurtain);
      expect(event.phases.length, 3); // blur + tint + toolbar
    });

    test('P2→P3 transition: 600ms, double tap (A13-T02)', () {
      choreographer.transitionTo(fromStep: 2, toStep: 3);
      final event = choreographer.currentTransition!;
      expect(event.durationMs, 600);
      expect(event.haptic, TransitionHaptic.doubleTap);
      expect(event.sound, TransitionSound.mentorKnock);
    });

    test('P3→P4 transition: 1200ms, 3-phase (A13-T03)', () {
      choreographer.transitionTo(fromStep: 3, toStep: 4);
      final event = choreographer.currentTransition!;
      expect(event.durationMs, 1200);
      expect(event.haptic, TransitionHaptic.crescendo);
      expect(event.sound, TransitionSound.scanSweep);
      expect(event.phases.length, 3);
      // Verify phase ordering
      expect(event.phases[0].effect, TransitionVisualEffect.panelSlide);
      expect(event.phases[1].effect, TransitionVisualEffect.radialWave);
      expect(event.phases[2].effect, TransitionVisualEffect.staggeredFadeIn);
    });

    test('generic transition: 500ms, ambient cross-fade', () {
      choreographer.transitionTo(fromStep: 5, toStep: 6);
      final event = choreographer.currentTransition!;
      expect(event.durationMs, 500);
      expect(event.phases.length, 1);
      expect(event.phases[0].effect, TransitionVisualEffect.tint);
    });

    test('completeTransition resets state', () {
      choreographer.transitionTo(fromStep: 1, toStep: 2);
      expect(choreographer.isTransitioning, isTrue);
      choreographer.completeTransition();
      expect(choreographer.isTransitioning, isFalse);
      expect(choreographer.currentTransition, isNull);
    });

    test('cannot transition while already transitioning', () {
      choreographer.transitionTo(fromStep: 1, toStep: 2);
      choreographer.transitionTo(fromStep: 2, toStep: 3); // Should be ignored
      expect(choreographer.currentTransition!.toStep, 2);
    });

    test('step identities cover all 12 steps', () {
      for (int i = 1; i <= 12; i++) {
        final identity = StepIdentityRegistry.forStep(i);
        expect(identity.step, i);
        expect(identity.emotion, isNotEmpty);
        expect(identity.metaphor, isNotEmpty);
      }
    });
  });
}
