import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/scene_graph/scene_graph_interceptor.dart';
import 'package:fluera_engine/src/core/scene_graph/canvas_node.dart';
import 'package:fluera_engine/src/core/scene_graph/node_id.dart';
import 'package:fluera_engine/src/core/nodes/group_node.dart';
import 'package:fluera_engine/src/core/nodes/layer_node.dart';

void main() {
  group('InterceptorResult', () {
    test('allow() creates allowed result', () {
      const result = InterceptorResult.allow();
      expect(result.isAllowed, isTrue);
      expect(result.reason, isNull);
      expect(result.transformedNode, isNull);
    });

    test('reject() creates non-allowed result with reason', () {
      final result = InterceptorResult.reject('forbidden');
      expect(result.isAllowed, isFalse);
      expect(result.reason, 'forbidden');
      expect(result.transformedNode, isNull);
    });

    test('transform() carries the replacement node', () {
      final node = LayerNode(id: NodeId('l1'));
      final result = InterceptorResult.transform(node);
      expect(result.isAllowed, isTrue);
      expect(result.transformedNode, same(node));
      expect(result.reason, isNull);
    });
  });

  group('MutationRejectedError', () {
    test('carries interceptorName and reason', () {
      final error = MutationRejectedError(
        interceptorName: 'TestInterceptor',
        reason: 'node is locked',
      );

      expect(error.reason, 'node is locked');
      expect(error.interceptorName, 'TestInterceptor');
      expect(error.toString(), contains('node is locked'));
      expect(error.toString(), contains('TestInterceptor'));
    });
  });

  group('InterceptorChain', () {
    late InterceptorChain chain;

    setUp(() {
      chain = InterceptorChain();
    });

    test('runBeforeAdd allows by default (no interceptors)', () {
      final node = GroupNode(id: NodeId('g1'));
      final result = chain.runBeforeAdd(node, 'root');
      expect(result, same(node));
    });

    test('runBeforeAdd allows through a permissive interceptor', () {
      chain.add(_AllowAllInterceptor());
      final node = GroupNode(id: NodeId('g1'));
      final result = chain.runBeforeAdd(node, 'root');
      expect(result, same(node));
    });

    test('runBeforeAdd throws on rejection', () {
      chain.add(_RejectAllInterceptor());
      final node = GroupNode(id: NodeId('g1'));

      expect(
        () => chain.runBeforeAdd(node, 'root'),
        throwsA(isA<MutationRejectedError>()),
      );
    });

    test('runBeforeAdd returns transformed node', () {
      chain.add(_RenameInterceptor());
      final node = LayerNode(id: NodeId('l1'), name: '');

      final result = chain.runBeforeAdd(node, 'root');
      expect(result.name, 'Renamed');
    });

    test('runBeforeRemove throws on rejection', () {
      chain.add(_RejectAllInterceptor());
      final node = GroupNode(id: NodeId('g1'));

      expect(
        () => chain.runBeforeRemove(node, 'root'),
        throwsA(isA<MutationRejectedError>()),
      );
    });

    test('runBeforePropertyChange allows through', () {
      chain.add(_AllowAllInterceptor());
      final node = GroupNode(id: NodeId('g1'));

      expect(
        () => chain.runBeforePropertyChange(node, 'opacity', 0.5),
        returnsNormally,
      );
    });

    test('runBeforeReorder allows through', () {
      chain.add(_AllowAllInterceptor());

      expect(() => chain.runBeforeReorder('parent', 0, 1), returnsNormally);
    });

    test('chain runs in priority order (lowest priority first)', () {
      final log = <String>[];
      chain.add(_LoggingInterceptor('second', 10, log));
      chain.add(_LoggingInterceptor('first', 1, log));

      final node = GroupNode(id: NodeId('g1'));
      chain.runBeforeAdd(node, 'root');

      expect(log, ['first', 'second']);
    });

    test('chain short-circuits on rejection', () {
      final log = <String>[];
      chain.add(_LoggingInterceptor('first', 1, log));
      chain.add(_RejectAllInterceptor(priorityValue: 5));
      chain.add(_LoggingInterceptor('third', 10, log));

      final node = GroupNode(id: NodeId('g1'));
      expect(
        () => chain.runBeforeAdd(node, 'root'),
        throwsA(isA<MutationRejectedError>()),
      );
      // 'first' ran, 'third' was short-circuited
      expect(log, ['first']);
    });

    test('remove removes interceptor from chain', () {
      final interceptor = _RejectAllInterceptor();
      chain.add(interceptor);
      chain.remove(interceptor);

      final node = GroupNode(id: NodeId('g1'));
      expect(() => chain.runBeforeAdd(node, 'root'), returnsNormally);
    });

    test('clear removes all interceptors', () {
      chain.add(_RejectAllInterceptor());
      chain.clear();

      final node = GroupNode(id: NodeId('g1'));
      expect(() => chain.runBeforeAdd(node, 'root'), returnsNormally);
    });
  });

  group('LockInterceptor', () {
    test('blocks removal of locked nodes', () {
      final chain = InterceptorChain();
      chain.add(LockInterceptor());

      final node = LayerNode(id: NodeId('l1'), isLocked: true);

      expect(
        () => chain.runBeforeRemove(node, 'root'),
        throwsA(isA<MutationRejectedError>()),
      );
    });

    test('allows removal of unlocked nodes', () {
      final chain = InterceptorChain();
      chain.add(LockInterceptor());

      final node = LayerNode(id: NodeId('l1'), isLocked: false);

      expect(() => chain.runBeforeRemove(node, 'root'), returnsNormally);
    });

    test('blocks property changes on locked nodes', () {
      final chain = InterceptorChain();
      chain.add(LockInterceptor());

      final node = LayerNode(id: NodeId('l1'), isLocked: true);

      expect(
        () => chain.runBeforePropertyChange(node, 'opacity', 0.5),
        throwsA(isA<MutationRejectedError>()),
      );
    });

    test('allows isLocked property change even on locked nodes', () {
      final chain = InterceptorChain();
      chain.add(LockInterceptor());

      final node = LayerNode(id: NodeId('l1'), isLocked: true);

      // Unlocking should always be allowed
      expect(
        () => chain.runBeforePropertyChange(node, 'isLocked', false),
        returnsNormally,
      );
    });

    test('allows add of any node (even locked)', () {
      final chain = InterceptorChain();
      chain.add(LockInterceptor());

      final node = LayerNode(id: NodeId('l1'), isLocked: true);

      expect(() => chain.runBeforeAdd(node, 'root'), returnsNormally);
    });
  });
}

// ─── Test helpers ──────────────────────────────────────────────────────────

class _AllowAllInterceptor extends SceneGraphInterceptor {
  @override
  String get name => 'AllowAll';
  @override
  int get priority => 0;
}

class _RejectAllInterceptor extends SceneGraphInterceptor {
  final int priorityValue;
  _RejectAllInterceptor({this.priorityValue = 0});

  @override
  String get name => 'RejectAll';
  @override
  int get priority => priorityValue;

  @override
  InterceptorResult beforeAdd(CanvasNode node, String parentId) =>
      InterceptorResult.reject('blocked');

  @override
  InterceptorResult beforeRemove(CanvasNode node, String parentId) =>
      InterceptorResult.reject('blocked');

  @override
  InterceptorResult beforePropertyChange(
    CanvasNode node,
    String property,
    dynamic newValue,
  ) => InterceptorResult.reject('blocked');

  @override
  InterceptorResult beforeReorder(
    String parentId,
    int oldIndex,
    int newIndex,
  ) => InterceptorResult.reject('blocked');
}

class _RenameInterceptor extends SceneGraphInterceptor {
  @override
  String get name => 'Rename';
  @override
  int get priority => 0;

  @override
  InterceptorResult beforeAdd(CanvasNode node, String parentId) {
    if (node.name.isEmpty) {
      final renamed = LayerNode(id: node.id, name: 'Renamed');
      return InterceptorResult.transform(renamed);
    }
    return const InterceptorResult.allow();
  }
}

class _LoggingInterceptor extends SceneGraphInterceptor {
  final String label;
  @override
  final int priority;
  final List<String> log;

  _LoggingInterceptor(this.label, this.priority, this.log);

  @override
  String get name => label;

  @override
  InterceptorResult beforeAdd(CanvasNode node, String parentId) {
    log.add(label);
    return const InterceptorResult.allow();
  }
}
