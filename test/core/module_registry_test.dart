import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/fluera_engine.dart';

// =============================================================================
// MOCK MODULE
// =============================================================================

class _MockModule extends CanvasModule {
  final String _id;
  final String _displayName;
  final List<NodeDescriptor> _descriptors;
  bool disposed = false;
  int initializeCallCount = 0;

  _MockModule({
    required String id,
    String displayName = 'Mock',
    List<NodeDescriptor>? descriptors,
  }) : _id = id,
       _displayName = displayName,
       _descriptors = descriptors ?? [];

  @override
  String get moduleId => _id;

  @override
  String get displayName => _displayName;

  @override
  List<NodeDescriptor> get nodeDescriptors => _descriptors;

  @override
  bool get isInitialized => initializeCallCount > 0;

  @override
  Future<void> initialize(ModuleContext context) async {
    initializeCallCount++;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

// =============================================================================
// TESTS
// =============================================================================

void main() {
  late EngineScope scope;

  setUp(() {
    scope = EngineScope();
    EngineScope.push(scope);
  });

  tearDown(() {
    EngineScope.reset();
  });

  group('ModuleRegistry', () {
    test('register adds module and indexes descriptors', () async {
      final module = _MockModule(
        id: 'test',
        descriptors: [
          NodeDescriptor(
            nodeType: 'customNode',
            fromJson: (_) => throw UnimplementedError(),
            displayName: 'Custom',
          ),
        ],
      );

      await scope.moduleRegistry.register(module);

      expect(scope.moduleRegistry.isRegistered('test'), isTrue);
      expect(scope.moduleRegistry.moduleCount, 1);
      expect(module.initializeCallCount, 1);
    });

    test('duplicate module ID throws StateError', () async {
      final a = _MockModule(id: 'dup');
      final b = _MockModule(id: 'dup');

      await scope.moduleRegistry.register(a);
      expect(
        () => scope.moduleRegistry.register(b),
        throwsA(isA<StateError>()),
      );
    });

    test('duplicate nodeType throws StateError', () async {
      final a = _MockModule(
        id: 'modA',
        descriptors: [
          NodeDescriptor(
            nodeType: 'shared',
            fromJson: (_) => throw UnimplementedError(),
            displayName: 'Shared',
          ),
        ],
      );
      final b = _MockModule(
        id: 'modB',
        descriptors: [
          NodeDescriptor(
            nodeType: 'shared',
            fromJson: (_) => throw UnimplementedError(),
            displayName: 'Shared',
          ),
        ],
      );

      await scope.moduleRegistry.register(a);
      expect(
        () => scope.moduleRegistry.register(b),
        throwsA(isA<StateError>()),
      );
    });

    test('findModule returns correct typed module', () async {
      final module = _MockModule(id: 'typed');
      await scope.moduleRegistry.register(module);

      final found = scope.moduleRegistry.findModule<_MockModule>();
      expect(found, same(module));
    });

    test('findModule returns null for unregistered type', () {
      final found = scope.moduleRegistry.findModule<_MockModule>();
      expect(found, isNull);
    });

    test('createNodeFromJson returns null for unknown nodeType', () {
      final result = scope.moduleRegistry.createNodeFromJson({
        'nodeType': 'doesNotExist',
      });
      expect(result, isNull);
    });

    test('disposeAll disposes all registered modules', () async {
      final first = _MockModule(id: 'first');
      final second = _MockModule(id: 'second');

      await scope.moduleRegistry.register(first);
      await scope.moduleRegistry.register(second);

      await scope.moduleRegistry.disposeAll();

      expect(first.disposed, isTrue);
      expect(second.disposed, isTrue);
      expect(scope.moduleRegistry.moduleCount, 0);
    });

    test('moduleCount is 0 initially', () {
      expect(scope.moduleRegistry.moduleCount, 0);
    });

    test('moduleCount grows with registrations', () async {
      await scope.moduleRegistry.register(_MockModule(id: 'a'));
      await scope.moduleRegistry.register(_MockModule(id: 'b'));

      expect(scope.moduleRegistry.moduleCount, 2);
      expect(scope.moduleRegistry.isRegistered('a'), isTrue);
      expect(scope.moduleRegistry.isRegistered('b'), isTrue);
    });

    test('unregister removes module and descriptors', () async {
      final module = _MockModule(
        id: 'rem',
        descriptors: [
          NodeDescriptor(
            nodeType: 'remNode',
            fromJson: (_) => throw UnimplementedError(),
            displayName: 'Removable',
          ),
        ],
      );

      await scope.moduleRegistry.register(module);
      expect(scope.moduleRegistry.hasNodeType('remNode'), isTrue);

      await scope.moduleRegistry.unregister('rem');
      expect(scope.moduleRegistry.isRegistered('rem'), isFalse);
      expect(scope.moduleRegistry.hasNodeType('remNode'), isFalse);
      expect(module.disposed, isTrue);
    });

    test('diagnostics returns non-empty string', () async {
      await scope.moduleRegistry.register(_MockModule(id: 'diag'));

      final diag = scope.moduleRegistry.diagnostics;
      expect(diag, contains('diag'));
      expect(diag, contains('ModuleRegistry'));
    });
  });

  group('initializeModules', () {
    test('is idempotent — second call is no-op', () async {
      await scope.initializeModules();
      final countAfterFirst = scope.moduleRegistry.moduleCount;

      await scope.initializeModules();
      expect(scope.moduleRegistry.moduleCount, countAfterFirst);
    });

    test('registers all built-in modules', () async {
      await scope.initializeModules();

      expect(scope.drawingModule, isNotNull);
      expect(scope.pdfModule, isNotNull);
      expect(scope.audioModule, isNotNull);
      // TabularModule and LaTeXModule are add-on packages, not registered by default
      expect(scope.tabularModule, isNull);
      expect(scope.latexModule, isNull);
    });

    test('sets modulesInitialized flag', () async {
      expect(scope.modulesInitialized, isFalse);
      await scope.initializeModules();
      expect(scope.modulesInitialized, isTrue);
    });
  });
}
