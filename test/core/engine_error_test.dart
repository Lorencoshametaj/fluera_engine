import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/engine_error.dart';

void main() {
  group('ErrorSeverity', () {
    test('has three levels', () {
      expect(ErrorSeverity.values, hasLength(3));
      expect(ErrorSeverity.values, contains(ErrorSeverity.transient));
      expect(ErrorSeverity.values, contains(ErrorSeverity.degraded));
      expect(ErrorSeverity.values, contains(ErrorSeverity.fatal));
    });
  });

  group('ErrorDomain', () {
    test('has five domains', () {
      expect(ErrorDomain.values, hasLength(5));
      expect(ErrorDomain.values, contains(ErrorDomain.storage));
      expect(ErrorDomain.values, contains(ErrorDomain.platform));
      expect(ErrorDomain.values, contains(ErrorDomain.rendering));
      expect(ErrorDomain.values, contains(ErrorDomain.network));
      expect(ErrorDomain.values, contains(ErrorDomain.sceneGraph));
    });
  });

  group('EngineError', () {
    test('stores all required fields', () {
      final originalError = Exception('disk full');
      final trace = StackTrace.current;

      final error = EngineError(
        severity: ErrorSeverity.transient,
        domain: ErrorDomain.storage,
        source: 'DiskStrokeManager._loadIndex',
        original: originalError,
        stack: trace,
        context: {'path': '/data/strokes.bin'},
      );

      expect(error.severity, ErrorSeverity.transient);
      expect(error.domain, ErrorDomain.storage);
      expect(error.source, 'DiskStrokeManager._loadIndex');
      expect(error.original, originalError);
      expect(error.stack, trace);
      expect(error.context, {'path': '/data/strokes.bin'});
    });

    test('timestamp is set automatically', () {
      final before = DateTime.now();
      final error = EngineError(
        severity: ErrorSeverity.fatal,
        domain: ErrorDomain.sceneGraph,
        source: 'test',
        original: 'failure',
      );
      final after = DateTime.now();

      expect(
        error.timestamp.isAfter(before.subtract(const Duration(seconds: 1))),
        true,
      );
      expect(
        error.timestamp.isBefore(after.add(const Duration(seconds: 1))),
        true,
      );
    });

    test('stack and context are optional', () {
      final error = EngineError(
        severity: ErrorSeverity.degraded,
        domain: ErrorDomain.platform,
        source: 'NativeMetrics',
        original: 'unavailable',
      );

      expect(error.stack, isNull);
      expect(error.context, isNull);
    });

    test('toString includes severity, domain, source, and original', () {
      final error = EngineError(
        severity: ErrorSeverity.fatal,
        domain: ErrorDomain.rendering,
        source: 'ShaderCompiler.compile',
        original: 'shader compilation failed',
      );

      final str = error.toString();
      expect(str, contains('fatal'));
      expect(str, contains('rendering'));
      expect(str, contains('ShaderCompiler.compile'));
      expect(str, contains('shader compilation failed'));
    });
  });
}
