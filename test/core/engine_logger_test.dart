import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/engine_logger.dart';

void main() {
  setUp(() {
    EngineLogger.enabled = true;
  });

  tearDown(() {
    EngineLogger.enabled = true;
  });

  group('EngineLogger', () {
    test('debug does not throw', () {
      expect(
        () => EngineLogger.debug('test message', tag: 'Test'),
        returnsNormally,
      );
    });

    test('info does not throw', () {
      expect(
        () => EngineLogger.info('test message', tag: 'Test'),
        returnsNormally,
      );
    });

    test('warning does not throw', () {
      expect(
        () => EngineLogger.warning(
          'test warning',
          tag: 'Test',
          error: Exception('test'),
          stack: StackTrace.current,
        ),
        returnsNormally,
      );
    });

    test('error does not throw', () {
      expect(
        () => EngineLogger.error(
          'test error',
          tag: 'Test',
          error: Exception('test'),
          stack: StackTrace.current,
        ),
        returnsNormally,
      );
    });

    test('disabled logger does not throw', () {
      EngineLogger.enabled = false;
      expect(() => EngineLogger.warning('should be silent'), returnsNormally);
      expect(() => EngineLogger.error('should be silent'), returnsNormally);
    });

    test('works without optional parameters', () {
      expect(() => EngineLogger.debug('no tag'), returnsNormally);
      expect(() => EngineLogger.info('no tag'), returnsNormally);
      expect(() => EngineLogger.warning('no tag'), returnsNormally);
      expect(() => EngineLogger.error('no tag'), returnsNormally);
    });
  });
}
