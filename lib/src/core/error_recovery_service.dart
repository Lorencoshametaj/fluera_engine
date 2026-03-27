import 'dart:async';
import 'package:flutter/foundation.dart';

import 'engine_error.dart';
import 'engine_event.dart';
import 'engine_scope.dart';

/// 🛡️ ERROR RECOVERY SERVICE — Enterprise-grade fault tolerance.
///
/// Provides four capabilities that transform scattered `catch(e) {}` blocks
/// into a structured, observable, recoverable error handling system:
///
/// 1. **Retry with exponential backoff** — for transient I/O failures
/// 2. **Circuit breaker** — prevents repeated calls to dead services
/// 3. **Error telemetry stream** — push-based diagnostics for production
/// 4. **Graceful degradation** — fallback registry for reduced functionality
///
/// ## Usage
///
/// ```dart
/// final recovery = EngineScope.current.errorRecovery;
///
/// // Retry transient I/O
/// final data = await recovery.retryAsync(
///   () => file.readAsString(),
///   source: 'DiskStrokeManager._loadIndex',
///   domain: ErrorDomain.storage,
/// );
///
/// // Circuit breaker for native channels
/// final metrics = recovery.withCircuitBreaker(
///   'NativePerformanceMonitor',
///   () => channel.invokeMethod('getMetrics'),
/// );
///
/// // Listen to all errors
/// recovery.onError.listen((e) => analytics.track(e));
/// ```
class ErrorRecoveryService {
  // ═══════════════════════════════════════════════════════════════════════════
  // TELEMETRY
  // ═══════════════════════════════════════════════════════════════════════════

  final StreamController<EngineError> _errorController =
      StreamController<EngineError>.broadcast();

  /// Push-based stream of all classified engine errors.
  Stream<EngineError> get onError => _errorController.stream;

  /// Total error count since creation, per domain.
  final Map<ErrorDomain, int> _errorCounts = {
    for (final d in ErrorDomain.values) d: 0,
  };

  /// Report an error to the telemetry stream.
  ///
  /// Called internally by retry/circuit breaker, but can also be called
  /// directly to report errors that don't need retry.
  void reportError(EngineError error) {
    _errorCounts[error.domain] = (_errorCounts[error.domain] ?? 0) + 1;
    if (!_errorController.isClosed) {
      _errorController.add(error);
    }

    // Telemetry: increment counter and emit event
    if (EngineScope.hasScope) {
      final scope = EngineScope.current;
      final t = scope.telemetry;
      t.counter('errors.total').increment();
      t.counter('errors.${error.domain.name}').increment();
      t.event('error.reported', {
        'domain': error.domain.name,
        'severity': error.severity.name,
        'source': error.source,
      });

      // Bridge to centralized event bus
      scope.eventBus.emit(ErrorReportedEngineEvent(error: error));
    }

  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RETRY WITH EXPONENTIAL BACKOFF
  // ═══════════════════════════════════════════════════════════════════════════

  /// Execute [action] with automatic retry on failure.
  ///
  /// - [maxAttempts]: total attempts (including the first). Default: 3.
  /// - [baseDelay]: delay before the first retry, doubled each subsequent retry.
  /// - [retryIf]: optional predicate — only retry if this returns true for the error.
  ///   Defaults to retrying all errors.
  /// - [source]: human-readable identifier for telemetry.
  /// - [domain]: error domain for classification.
  ///
  /// If all attempts fail, reports the error as `fatal` and rethrows.
  Future<T> retryAsync<T>(
    Future<T> Function() action, {
    int maxAttempts = 3,
    Duration baseDelay = const Duration(milliseconds: 200),
    Duration maxDelay = const Duration(seconds: 10),
    bool Function(Object error)? retryIf,
    required String source,
    required ErrorDomain domain,
  }) async {
    Object? lastError;
    StackTrace? lastStack;

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await action();
      } catch (e, stack) {
        lastError = e;
        lastStack = stack;

        // Check if we should retry this specific error
        if (retryIf != null && !retryIf(e)) {
          // Not retryable — report as fatal immediately
          reportError(
            EngineError(
              severity: ErrorSeverity.fatal,
              domain: domain,
              source: source,
              original: e,
              stack: stack,
              context: {'attempt': attempt, 'maxAttempts': maxAttempts},
            ),
          );
          rethrow;
        }

        if (attempt < maxAttempts) {
          // Report as transient (we'll retry)
          reportError(
            EngineError(
              severity: ErrorSeverity.transient,
              domain: domain,
              source: source,
              original: e,
              stack: stack,
              context: {
                'attempt': attempt,
                'maxAttempts': maxAttempts,
                'nextRetryMs':
                    (baseDelay * (1 << (attempt - 1))).inMilliseconds,
              },
            ),
          );

          // Exponential backoff capped at maxDelay.
          final delay = baseDelay * (1 << (attempt - 1));
          await Future.delayed(delay > maxDelay ? maxDelay : delay);
        }
      }
    }

    // All attempts exhausted — report as fatal
    reportError(
      EngineError(
        severity: ErrorSeverity.fatal,
        domain: domain,
        source: source,
        original: lastError!,
        stack: lastStack,
        context: {
          'attempt': maxAttempts,
          'maxAttempts': maxAttempts,
          'exhausted': true,
        },
      ),
    );

    // ignore: only_throw_errors
    throw lastError;
  }

  /// Synchronous retry variant for non-async operations.
  T retrySync<T>(
    T Function() action, {
    int maxAttempts = 3,
    required String source,
    required ErrorDomain domain,
  }) {
    Object? lastError;
    StackTrace? lastStack;

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return action();
      } catch (e, stack) {
        lastError = e;
        lastStack = stack;

        if (attempt < maxAttempts) {
          reportError(
            EngineError(
              severity: ErrorSeverity.transient,
              domain: domain,
              source: source,
              original: e,
              stack: stack,
              context: {'attempt': attempt, 'maxAttempts': maxAttempts},
            ),
          );
        }
      }
    }

    reportError(
      EngineError(
        severity: ErrorSeverity.fatal,
        domain: domain,
        source: source,
        original: lastError!,
        stack: lastStack,
        context: {'attempt': maxAttempts, 'exhausted': true},
      ),
    );

    // ignore: only_throw_errors
    throw lastError;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CIRCUIT BREAKER
  // ═══════════════════════════════════════════════════════════════════════════

  /// Per-service circuit breaker state.
  final Map<String, _CircuitBreakerState> _breakers = {};

  /// Execute [action] behind a circuit breaker for [serviceId].
  ///
  /// - **Closed** (healthy): action executes normally.
  /// - **Open** (broken): action is skipped, returns `null` immediately.
  /// - **Half-open** (probing): one test call allowed — success → close, failure → reopen.
  ///
  /// [failureThreshold]: consecutive failures before opening. Default: 3.
  /// [resetTimeout]: time in open state before transitioning to half-open. Default: 30s.
  T? withCircuitBreaker<T>(
    String serviceId,
    T Function() action, {
    int failureThreshold = 3,
    Duration resetTimeout = const Duration(seconds: 30),
    ErrorDomain domain = ErrorDomain.platform,
  }) {
    final breaker = _breakers.putIfAbsent(
      serviceId,
      () => _CircuitBreakerState(
        failureThreshold: failureThreshold,
        resetTimeout: resetTimeout,
      ),
    );

    switch (breaker.state) {
      case _CircuitState.open:
        // Check if reset timeout has elapsed → try half-open
        if (DateTime.now().difference(breaker.lastFailureTime) >=
            resetTimeout) {
          breaker.state = _CircuitState.halfOpen;
          // Fall through to execute
        } else {
          return null; // Skip — service is considered dead
        }

      case _CircuitState.closed:
      case _CircuitState.halfOpen:
        break; // Execute normally
    }

    try {
      final result = action();
      // Success: reset breaker
      breaker.consecutiveFailures = 0;
      breaker.state = _CircuitState.closed;
      return result;
    } catch (e, stack) {
      breaker.consecutiveFailures++;
      breaker.lastFailureTime = DateTime.now();

      if (breaker.consecutiveFailures >= breaker.failureThreshold ||
          breaker.state == _CircuitState.halfOpen) {
        breaker.state = _CircuitState.open;
        reportError(
          EngineError(
            severity: ErrorSeverity.degraded,
            domain: domain,
            source: serviceId,
            original: e,
            stack: stack,
            context: {
              'circuitState': 'open',
              'consecutiveFailures': breaker.consecutiveFailures,
            },
          ),
        );
      } else {
        reportError(
          EngineError(
            severity: ErrorSeverity.transient,
            domain: domain,
            source: serviceId,
            original: e,
            stack: stack,
            context: {
              'circuitState': 'closed',
              'consecutiveFailures': breaker.consecutiveFailures,
            },
          ),
        );
      }

      return null;
    }
  }

  /// Async variant of [withCircuitBreaker].
  Future<T?> withCircuitBreakerAsync<T>(
    String serviceId,
    Future<T> Function() action, {
    int failureThreshold = 3,
    Duration resetTimeout = const Duration(seconds: 30),
    ErrorDomain domain = ErrorDomain.platform,
  }) async {
    final breaker = _breakers.putIfAbsent(
      serviceId,
      () => _CircuitBreakerState(
        failureThreshold: failureThreshold,
        resetTimeout: resetTimeout,
      ),
    );

    switch (breaker.state) {
      case _CircuitState.open:
        if (DateTime.now().difference(breaker.lastFailureTime) >=
            resetTimeout) {
          breaker.state = _CircuitState.halfOpen;
        } else {
          return null;
        }

      case _CircuitState.closed:
      case _CircuitState.halfOpen:
        break;
    }

    try {
      final result = await action();
      breaker.consecutiveFailures = 0;
      breaker.state = _CircuitState.closed;
      return result;
    } catch (e, stack) {
      breaker.consecutiveFailures++;
      breaker.lastFailureTime = DateTime.now();

      if (breaker.consecutiveFailures >= breaker.failureThreshold ||
          breaker.state == _CircuitState.halfOpen) {
        breaker.state = _CircuitState.open;
        reportError(
          EngineError(
            severity: ErrorSeverity.degraded,
            domain: domain,
            source: serviceId,
            original: e,
            stack: stack,
            context: {
              'circuitState': 'open',
              'consecutiveFailures': breaker.consecutiveFailures,
            },
          ),
        );
      } else {
        reportError(
          EngineError(
            severity: ErrorSeverity.transient,
            domain: domain,
            source: serviceId,
            original: e,
            stack: stack,
          ),
        );
      }

      return null;
    }
  }

  /// Check if a circuit breaker is currently open (service considered dead).
  bool isCircuitOpen(String serviceId) {
    final breaker = _breakers[serviceId];
    if (breaker == null) return false;
    return breaker.state == _CircuitState.open;
  }

  /// Manually reset a circuit breaker to closed state.
  void resetCircuitBreaker(String serviceId) {
    final breaker = _breakers[serviceId];
    if (breaker != null) {
      breaker.state = _CircuitState.closed;
      breaker.consecutiveFailures = 0;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GRACEFUL DEGRADATION — Safe execute with fallback
  // ═══════════════════════════════════════════════════════════════════════════

  /// Execute [action] and return [fallback] on any failure.
  ///
  /// Reports the error as [degraded] — the engine continues operating
  /// with reduced functionality.
  T executeWithFallback<T>(
    T Function() action,
    T fallback, {
    required String source,
    ErrorDomain domain = ErrorDomain.platform,
  }) {
    try {
      return action();
    } catch (e, stack) {
      reportError(
        EngineError(
          severity: ErrorSeverity.degraded,
          domain: domain,
          source: source,
          original: e,
          stack: stack,
        ),
      );
      return fallback;
    }
  }

  /// Async variant of [executeWithFallback].
  Future<T> executeWithFallbackAsync<T>(
    Future<T> Function() action,
    T fallback, {
    required String source,
    ErrorDomain domain = ErrorDomain.platform,
  }) async {
    try {
      return await action();
    } catch (e, stack) {
      reportError(
        EngineError(
          severity: ErrorSeverity.degraded,
          domain: domain,
          source: source,
          original: e,
          stack: stack,
        ),
      );
      return fallback;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STATISTICS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Diagnostic statistics for monitoring.
  Map<String, dynamic> get stats => {
    'errorCounts': {
      for (final entry in _errorCounts.entries) entry.key.name: entry.value,
    },
    'totalErrors': _errorCounts.values.fold<int>(0, (a, b) => a + b),
    'circuitBreakers': {
      for (final entry in _breakers.entries)
        entry.key: {
          'state': entry.value.state.name,
          'consecutiveFailures': entry.value.consecutiveFailures,
        },
    },
  };

  /// Dispose and release resources.
  void dispose() {
    _errorController.close();
    _breakers.clear();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CIRCUIT BREAKER INTERNALS
// ═══════════════════════════════════════════════════════════════════════════════

enum _CircuitState { closed, open, halfOpen }

class _CircuitBreakerState {
  final int failureThreshold;
  final Duration resetTimeout;

  _CircuitState state = _CircuitState.closed;
  int consecutiveFailures = 0;
  DateTime lastFailureTime = DateTime.fromMillisecondsSinceEpoch(0);

  _CircuitBreakerState({
    required this.failureThreshold,
    required this.resetTimeout,
  });
}
