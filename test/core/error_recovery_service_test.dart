import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/engine_error.dart';
import 'package:nebula_engine/src/core/error_recovery_service.dart';

void main() {
  late ErrorRecoveryService service;

  setUp(() {
    service = ErrorRecoveryService();
  });

  tearDown(() {
    service.dispose();
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // RETRY — ASYNC
  // ═══════════════════════════════════════════════════════════════════════════

  group('retryAsync', () {
    test('succeeds on first attempt', () async {
      final result = await service.retryAsync(
        () async => 42,
        source: 'test',
        domain: ErrorDomain.storage,
      );
      expect(result, 42);
    });

    test('succeeds after transient failures', () async {
      int attempt = 0;
      final result = await service.retryAsync(
        () async {
          attempt++;
          if (attempt < 3) throw Exception('transient');
          return 'ok';
        },
        source: 'test',
        domain: ErrorDomain.storage,
        baseDelay: Duration.zero,
      );
      expect(result, 'ok');
      expect(attempt, 3);
    });

    test('throws after maxAttempts exhausted', () async {
      expect(
        () => service.retryAsync(
          () async => throw Exception('permanent'),
          maxAttempts: 2,
          source: 'test',
          domain: ErrorDomain.storage,
          baseDelay: Duration.zero,
        ),
        throwsException,
      );
    });

    test('reports transient errors during retries', () async {
      final errors = <EngineError>[];
      service.onError.listen(errors.add);

      int attempt = 0;
      await service.retryAsync(
        () async {
          attempt++;
          if (attempt < 2) throw Exception('transient');
          return 'ok';
        },
        source: 'test.retries',
        domain: ErrorDomain.storage,
        baseDelay: Duration.zero,
      );

      // Wait for stream delivery
      await Future.delayed(Duration.zero);

      expect(errors.length, 1);
      expect(errors.first.severity, ErrorSeverity.transient);
      expect(errors.first.source, 'test.retries');
    });

    test('reports fatal when all attempts exhausted', () async {
      final errors = <EngineError>[];
      service.onError.listen(errors.add);

      try {
        await service.retryAsync(
          () async => throw Exception('fail'),
          maxAttempts: 2,
          source: 'test.fatal',
          domain: ErrorDomain.rendering,
          baseDelay: Duration.zero,
        );
      } catch (_) {}

      await Future.delayed(Duration.zero);

      final fatalErrors =
          errors.where((e) => e.severity == ErrorSeverity.fatal).toList();
      expect(fatalErrors, hasLength(1));
      expect(fatalErrors.first.domain, ErrorDomain.rendering);
      expect(fatalErrors.first.context?['exhausted'], true);
    });

    test('retryIf skips retry for non-retryable errors', () async {
      final errors = <EngineError>[];
      service.onError.listen(errors.add);

      try {
        await service.retryAsync(
          () async => throw FormatException('corrupt data'),
          maxAttempts: 3,
          source: 'test.format',
          domain: ErrorDomain.storage,
          baseDelay: Duration.zero,
          retryIf: (e) => e is! FormatException,
        );
      } catch (_) {}

      await Future.delayed(Duration.zero);

      // Should report fatal immediately, no retries
      expect(errors.length, 1);
      expect(errors.first.severity, ErrorSeverity.fatal);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // RETRY — SYNC
  // ═══════════════════════════════════════════════════════════════════════════

  group('retrySync', () {
    test('succeeds on first attempt', () {
      final result = service.retrySync(
        () => 99,
        source: 'sync.test',
        domain: ErrorDomain.platform,
      );
      expect(result, 99);
    });

    test('succeeds after transient failure', () {
      int attempt = 0;
      final result = service.retrySync(
        () {
          attempt++;
          if (attempt < 2) throw Exception('retry');
          return 'done';
        },
        source: 'sync.retry',
        domain: ErrorDomain.platform,
      );
      expect(result, 'done');
    });

    test('throws after all attempts', () {
      expect(
        () => service.retrySync(
          () => throw Exception('fail'),
          maxAttempts: 2,
          source: 'sync.fail',
          domain: ErrorDomain.platform,
        ),
        throwsException,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // CIRCUIT BREAKER
  // ═══════════════════════════════════════════════════════════════════════════

  group('Circuit Breaker', () {
    test('starts closed — action executes normally', () {
      final result = service.withCircuitBreaker('testService', () => 42);
      expect(result, 42);
      expect(service.isCircuitOpen('testService'), false);
    });

    test('opens after failureThreshold consecutive failures', () {
      for (int i = 0; i < 3; i++) {
        service.withCircuitBreaker(
          'failService',
          () => throw Exception('fail $i'),
          failureThreshold: 3,
        );
      }

      expect(service.isCircuitOpen('failService'), true);
    });

    test('returns null when circuit is open', () {
      // Open the circuit
      for (int i = 0; i < 3; i++) {
        service.withCircuitBreaker(
          'openTest',
          () => throw Exception('fail'),
          failureThreshold: 3,
        );
      }

      // Now action should be skipped
      final result = service.withCircuitBreaker(
        'openTest',
        () => 'should not execute',
      );
      expect(result, isNull);
    });

    test('resets to closed on success', () {
      // Fail once (below threshold)
      service.withCircuitBreaker(
        'resetTest',
        () => throw Exception('fail'),
        failureThreshold: 3,
      );

      // Succeed resets the counter
      service.withCircuitBreaker('resetTest', () => 'success');

      expect(service.isCircuitOpen('resetTest'), false);
    });

    test('manual reset reopens the circuit', () {
      // Open the circuit
      for (int i = 0; i < 3; i++) {
        service.withCircuitBreaker(
          'manualReset',
          () => throw Exception('fail'),
          failureThreshold: 3,
        );
      }
      expect(service.isCircuitOpen('manualReset'), true);

      service.resetCircuitBreaker('manualReset');
      expect(service.isCircuitOpen('manualReset'), false);
    });

    test('emits degraded error when circuit opens', () async {
      final errors = <EngineError>[];
      service.onError.listen(errors.add);

      for (int i = 0; i < 3; i++) {
        service.withCircuitBreaker(
          'degraded',
          () => throw Exception('fail'),
          failureThreshold: 3,
          domain: ErrorDomain.platform,
        );
      }

      await Future.delayed(Duration.zero);

      final degraded =
          errors.where((e) => e.severity == ErrorSeverity.degraded).toList();
      expect(degraded, hasLength(1));
      expect(degraded.first.context?['circuitState'], 'open');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // CIRCUIT BREAKER — ASYNC
  // ═══════════════════════════════════════════════════════════════════════════

  group('Circuit Breaker Async', () {
    test('executes normally when closed', () async {
      final result = await service.withCircuitBreakerAsync(
        'asyncService',
        () async => 'hello',
      );
      expect(result, 'hello');
    });

    test('opens after threshold failures', () async {
      for (int i = 0; i < 3; i++) {
        await service.withCircuitBreakerAsync(
          'asyncFail',
          () async => throw Exception('fail'),
          failureThreshold: 3,
        );
      }
      expect(service.isCircuitOpen('asyncFail'), true);
    });

    test('returns null when open', () async {
      for (int i = 0; i < 3; i++) {
        await service.withCircuitBreakerAsync(
          'asyncOpen',
          () async => throw Exception('fail'),
          failureThreshold: 3,
        );
      }

      final result = await service.withCircuitBreakerAsync(
        'asyncOpen',
        () async => 'nope',
      );
      expect(result, isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // GRACEFUL DEGRADATION
  // ═══════════════════════════════════════════════════════════════════════════

  group('Graceful Degradation', () {
    test('returns action result on success', () {
      final result = service.executeWithFallback(
        () => 42,
        -1,
        source: 'fallback.test',
      );
      expect(result, 42);
    });

    test('returns fallback on failure', () {
      final result = service.executeWithFallback(
        () => throw Exception('fail'),
        -1,
        source: 'fallback.fail',
      );
      expect(result, -1);
    });

    test('reports degraded error on fallback', () async {
      final errors = <EngineError>[];
      service.onError.listen(errors.add);

      service.executeWithFallback(
        () => throw Exception('oops'),
        'fallback',
        source: 'fallback.report',
        domain: ErrorDomain.rendering,
      );

      await Future.delayed(Duration.zero);

      expect(errors.length, 1);
      expect(errors.first.severity, ErrorSeverity.degraded);
    });

    test('async variant works correctly', () async {
      final result = await service.executeWithFallbackAsync(
        () async => throw Exception('fail'),
        'default',
        source: 'async.fallback',
      );
      expect(result, 'default');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // TELEMETRY STREAM
  // ═══════════════════════════════════════════════════════════════════════════

  group('Telemetry Stream', () {
    test('stream is broadcast — supports multiple listeners', () async {
      final listener1 = <EngineError>[];
      final listener2 = <EngineError>[];

      service.onError.listen(listener1.add);
      service.onError.listen(listener2.add);

      service.reportError(
        EngineError(
          severity: ErrorSeverity.transient,
          domain: ErrorDomain.network,
          source: 'test.broadcast',
          original: 'test error',
        ),
      );

      await Future.delayed(Duration.zero);

      expect(listener1.length, 1);
      expect(listener2.length, 1);
    });

    test('reportError increments domain counters', () {
      service.reportError(
        EngineError(
          severity: ErrorSeverity.transient,
          domain: ErrorDomain.storage,
          source: 'counter.test',
          original: 'err1',
        ),
      );
      service.reportError(
        EngineError(
          severity: ErrorSeverity.fatal,
          domain: ErrorDomain.storage,
          source: 'counter.test',
          original: 'err2',
        ),
      );
      service.reportError(
        EngineError(
          severity: ErrorSeverity.degraded,
          domain: ErrorDomain.platform,
          source: 'counter.test',
          original: 'err3',
        ),
      );

      final stats = service.stats;
      expect(stats['errorCounts']['storage'], 2);
      expect(stats['errorCounts']['platform'], 1);
      expect(stats['totalErrors'], 3);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // STATISTICS
  // ═══════════════════════════════════════════════════════════════════════════

  group('Statistics', () {
    test('stats includes circuit breaker states', () {
      service.withCircuitBreaker('svc1', () => 42);

      final stats = service.stats;
      expect(stats['circuitBreakers']['svc1']['state'], 'closed');
      expect(stats['circuitBreakers']['svc1']['consecutiveFailures'], 0);
    });

    test('stats shows open circuit after failures', () {
      for (int i = 0; i < 3; i++) {
        service.withCircuitBreaker(
          'broken',
          () => throw Exception('fail'),
          failureThreshold: 3,
        );
      }

      final stats = service.stats;
      expect(stats['circuitBreakers']['broken']['state'], 'open');
      expect(stats['circuitBreakers']['broken']['consecutiveFailures'], 3);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ENGINE ERROR MODEL
  // ═══════════════════════════════════════════════════════════════════════════

  group('EngineError model', () {
    test('toString includes severity, domain, source', () {
      final error = EngineError(
        severity: ErrorSeverity.transient,
        domain: ErrorDomain.storage,
        source: 'TestSource',
        original: Exception('test'),
      );

      expect(error.toString(), contains('transient'));
      expect(error.toString(), contains('storage'));
      expect(error.toString(), contains('TestSource'));
    });

    test('timestamp is set automatically', () {
      final before = DateTime.now();
      final error = EngineError(
        severity: ErrorSeverity.fatal,
        domain: ErrorDomain.rendering,
        source: 'TimeTest',
        original: 'err',
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

    test('context map stores diagnostic data', () {
      final error = EngineError(
        severity: ErrorSeverity.degraded,
        domain: ErrorDomain.network,
        source: 'ContextTest',
        original: 'err',
        context: {'attempt': 3, 'url': 'http://example.com'},
      );

      expect(error.context?['attempt'], 3);
      expect(error.context?['url'], 'http://example.com');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // DISPOSE
  // ═══════════════════════════════════════════════════════════════════════════

  group('Dispose', () {
    test('dispose closes stream and clears state', () {
      service.withCircuitBreaker('svc', () => 42);
      service.dispose();

      // After dispose, reportError should not throw
      service.reportError(
        EngineError(
          severity: ErrorSeverity.transient,
          domain: ErrorDomain.storage,
          source: 'after.dispose',
          original: 'safe',
        ),
      );
    });
  });
}
