import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/fluera_engine.dart';

void main() {
  group('EngineScope — Stack & Token Management', () {
    setUp(() {
      EngineScope.reset();
    });

    tearDown(() {
      EngineScope.reset();
    });

    test('current creates a default scope lazily', () {
      expect(EngineScope.hasScope, isFalse);
      final scope = EngineScope.current;
      expect(scope, isNotNull);
      expect(EngineScope.hasScope, isTrue);
    });

    test('push/pop lifecycle', () {
      final scope = EngineScope();
      final token = EngineScope.push(scope);

      expect(EngineScope.current, same(scope));
      expect(EngineScope.depth, equals(1));

      EngineScope.pop(token);
      expect(EngineScope.depth, equals(0));
    });

    test('popping with wrong token throws StateError', () {
      final scope1 = EngineScope();
      EngineScope.push(scope1);

      final scope2 = EngineScope();
      final token2 = EngineScope.push(scope2);

      // Now scope2 is on top, try popping with a stale token
      EngineScope.pop(token2);

      // Can't pop scope1 with token2 (already consumed)
      expect(() => EngineScope.pop(token2), throwsA(isA<StateError>()));
    });

    test('popping from empty stack throws StateError', () {
      // Create a valid token, then reset (empties the stack)
      final staleToken = EngineScope.push(EngineScope());
      EngineScope.reset();

      expect(() => EngineScope.pop(staleToken), throwsA(isA<StateError>()));
    });

    test('nested scopes: current returns top of stack', () {
      final scope1 = EngineScope();
      final token1 = EngineScope.push(scope1);

      final scope2 = EngineScope();
      final token2 = EngineScope.push(scope2);

      expect(EngineScope.current, same(scope2));
      expect(EngineScope.depth, equals(2));

      EngineScope.pop(token2);
      expect(EngineScope.current, same(scope1));
      expect(EngineScope.depth, equals(1));

      EngineScope.pop(token1);
    });

    test('reset disposes all scopes', () {
      EngineScope.push(EngineScope());
      EngineScope.push(EngineScope());
      EngineScope.push(EngineScope());

      expect(EngineScope.depth, equals(3));

      EngineScope.reset();

      expect(EngineScope.depth, equals(0));
      expect(EngineScope.hasScope, isFalse);
    });

    test('services are independent across scopes', () {
      final scope1 = EngineScope();
      final token1 = EngineScope.push(scope1);

      final scope2 = EngineScope();
      final token2 = EngineScope.push(scope2);

      expect(scope1.eventBus, isNot(same(scope2.eventBus)));
      expect(scope1.commandHistory, isNot(same(scope2.commandHistory)));
      expect(scope1.deltaTracker, isNot(same(scope2.deltaTracker)));

      EngineScope.pop(token2);
      EngineScope.pop(token1);
    });

    test('depth reflects stack size', () {
      expect(EngineScope.depth, equals(0));
      final t1 = EngineScope.push(EngineScope());
      expect(EngineScope.depth, equals(1));
      final t2 = EngineScope.push(EngineScope());
      expect(EngineScope.depth, equals(2));
      EngineScope.pop(t2);
      expect(EngineScope.depth, equals(1));
      EngineScope.pop(t1);
      expect(EngineScope.depth, equals(0));
    });
  });
}
