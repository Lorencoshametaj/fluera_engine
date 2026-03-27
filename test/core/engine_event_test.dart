import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/engine_event.dart';
import 'package:fluera_engine/src/core/engine_error.dart';
import 'package:fluera_engine/src/core/nodes/group_node.dart';
import 'package:fluera_engine/src/core/scene_graph/node_id.dart';

void main() {
  group('EventDomain', () {
    test('has expected values', () {
      expect(EventDomain.sceneGraph, isNotNull);
      expect(EventDomain.selection, isNotNull);
      expect(EventDomain.variable, isNotNull);
      expect(EventDomain.memory, isNotNull);
      expect(EventDomain.error, isNotNull);
      expect(EventDomain.custom, isNotNull);
      expect(EventDomain.bus, isNotNull);
      expect(EventDomain.command, isNotNull);
      expect(EventDomain.accessibility, isNotNull);
      expect(EventDomain.animation, isNotNull);
      expect(EventDomain.intelligence, isNotNull);
    });
  });

  group('SceneGraph Events', () {
    test('NodeAddedEngineEvent fields', () {
      final node = GroupNode(id: const NodeId('test-node'));
      final event = NodeAddedEngineEvent(node: node, parentId: 'parent-1');
      expect(event.domain, EventDomain.sceneGraph);
      expect(event.source, 'SceneGraph');
      expect(event.parentId, 'parent-1');
      expect(event.node, same(node));
      expect(event.timestamp, isNotNull);
    });

    test('NodeRemovedEngineEvent fields', () {
      final node = GroupNode(id: const NodeId('test-node'));
      final event = NodeRemovedEngineEvent(node: node, parentId: 'parent-2');
      expect(event.domain, EventDomain.sceneGraph);
      expect(event.parentId, 'parent-2');
    });

    test('NodePropertyChangedEngineEvent fields', () {
      final node = GroupNode(id: const NodeId('test-node'));
      final event = NodePropertyChangedEngineEvent(
        node: node,
        property: 'opacity',
      );
      expect(event.property, 'opacity');
      expect(event.domain, EventDomain.sceneGraph);
    });

    test('NodeReorderedEngineEvent fields', () {
      final event = NodeReorderedEngineEvent(
        parentId: 'group-1',
        oldIndex: 2,
        newIndex: 5,
      );
      expect(event.parentId, 'group-1');
      expect(event.oldIndex, 2);
      expect(event.newIndex, 5);
    });
  });

  group('SelectionChangedEngineEvent', () {
    test('fields', () {
      final event = SelectionChangedEngineEvent(
        changeType: 'selected',
        affectedIds: ['node-1', 'node-2'],
        totalSelected: 3,
      );
      expect(event.domain, EventDomain.selection);
      expect(event.source, 'SelectionManager');
      expect(event.changeType, 'selected');
      expect(event.affectedIds, hasLength(2));
      expect(event.totalSelected, 3);
    });
  });

  group('VariableChangedEngineEvent', () {
    test('fields with mode', () {
      final event = VariableChangedEngineEvent(
        variableId: 'color-primary',
        modeId: 'dark',
        property: 'value',
        oldValue: '#000000',
        newValue: '#FFFFFF',
      );
      expect(event.domain, EventDomain.variable);
      expect(event.variableId, 'color-primary');
      expect(event.modeId, 'dark');
      expect(event.oldValue, '#000000');
      expect(event.newValue, '#FFFFFF');
    });

    test('fields without mode', () {
      final event = VariableChangedEngineEvent(
        variableId: 'spacing-sm',
        property: 'name',
      );
      expect(event.modeId, isNull);
      expect(event.oldValue, isNull);
    });
  });

  group('MemoryPressureEngineEvent', () {
    test('fields', () {
      final event = MemoryPressureEngineEvent(
        level: 'warning',
        totalEstimatedMB: 450.5,
        budgetCapMB: 512,
      );
      expect(event.domain, EventDomain.memory);
      expect(event.level, 'warning');
      expect(event.totalEstimatedMB, 450.5);
      expect(event.budgetCapMB, 512);
    });
  });

  group('ErrorReportedEngineEvent', () {
    test('is CriticalEvent', () {
      final event = ErrorReportedEngineEvent(
        error: EngineError(
          severity: ErrorSeverity.transient,
          domain: ErrorDomain.rendering,
          source: 'TestSource',
          original: Exception('test'),
        ),
      );
      expect(event, isA<CriticalEvent>());
      expect(event.domain, EventDomain.error);
    });
  });

  group('CustomPluginEngineEvent', () {
    test('fields', () {
      final event = CustomPluginEngineEvent(
        pluginId: 'my-plugin',
        name: 'custom-action',
        data: {'key': 'value'},
      );
      expect(event.domain, EventDomain.custom);
      expect(event.source, 'Plugin:my-plugin');
      expect(event.pluginId, 'my-plugin');
      expect(event.name, 'custom-action');
      expect(event.data, {'key': 'value'});
    });

    test('no data', () {
      final event = CustomPluginEngineEvent(pluginId: 'p', name: 'e');
      expect(event.data, isNull);
    });
  });

  group('BatchCompleteEngineEvent', () {
    test('fields', () {
      final event = BatchCompleteEngineEvent(
        suppressedCount: 42,
        pauseDuration: const Duration(milliseconds: 500),
      );
      expect(event.domain, EventDomain.bus);
      expect(event.suppressedCount, 42);
      expect(event.pauseDuration.inMilliseconds, 500);
    });
  });

  group('Command Events', () {
    test('CommandExecutedEngineEvent', () {
      final event = CommandExecutedEngineEvent(
        commandLabel: 'Add Node',
        commandType: 'AddNodeCommand',
      );
      expect(event.domain, EventDomain.command);
      expect(event.commandLabel, 'Add Node');
      expect(event.commandType, 'AddNodeCommand');
    });

    test('CommandUndoneEngineEvent', () {
      final event = CommandUndoneEngineEvent(
        commandLabel: 'Delete Node',
        commandType: 'DeleteNodeCommand',
      );
      expect(event.commandLabel, 'Delete Node');
    });
  });

  group('AccessibilityTreeChangedEvent', () {
    test('fields', () {
      final event = AccessibilityTreeChangedEvent(nodeCount: 15);
      expect(event.domain, EventDomain.accessibility);
      expect(event.nodeCount, 15);
    });
  });

  group('Animation Events', () {
    test('AnimationPlaybackStartedEvent', () {
      final event = AnimationPlaybackStartedEvent();
      expect(event.domain, EventDomain.animation);
      expect(event.source, 'AnimationPlayer');
    });

    test('AnimationPlaybackStoppedEvent completed', () {
      final event = AnimationPlaybackStoppedEvent(completed: true);
      expect(event.completed, isTrue);
    });

    test('AnimationPlaybackStoppedEvent interrupted', () {
      final event = AnimationPlaybackStoppedEvent(completed: false);
      expect(event.completed, isFalse);
    });

    test('AnimationFrameEvent', () {
      final event = AnimationFrameEvent(time: const Duration(seconds: 2));
      expect(event.time.inSeconds, 2);
    });
  });

  group('Intelligence Events', () {
    test('ProfileRecommendationsChangedEvent', () {
      final event = ProfileRecommendationsChangedEvent(
        stabilizerLevel: 2,
        prefetchBias: 0.8,
      );
      expect(event.domain, EventDomain.intelligence);
      expect(event.stabilizerLevel, 2);
      expect(event.prefetchBias, 0.8);
    });

    test('LintCompletedEvent', () {
      final event = LintCompletedEvent(violationCount: 5);
      expect(event.violationCount, 5);
    });

    test('SnapThresholdChangedEvent', () {
      final event = SnapThresholdChangedEvent(threshold: 12.5);
      expect(event.threshold, 12.5);
    });
  });

  group('EngineEvent base', () {
    test('timestamp is auto-generated', () {
      final event = AnimationPlaybackStartedEvent();
      final now = DateTime.now();
      // Timestamp should be very recent (within 1 second)
      expect(now.difference(event.timestamp).inSeconds, lessThan(1));
    });
  });
}
