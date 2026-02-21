import 'dart:async';
import '../core/engine_event.dart';

/// A rate-limited, fail-safe wrapper around a broadcast stream
/// for plugin event consumption.
///
/// Ensures that single plugins cannot subscribe infinitely or
/// receive events at an uncontrolled rate which would stall the
/// engine event bus.
class SandboxedEventStream<T extends EngineEvent> extends Stream<T> {
  final Stream<T> _source;
  final int _maxEventsPerSecond;

  SandboxedEventStream(this._source, {int maxEventsPerSecond = 60})
    : _maxEventsPerSecond = maxEventsPerSecond;

  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    int eventCount = 0;
    int lastResetMs = DateTime.now().millisecondsSinceEpoch;

    return _source.listen(
      (event) {
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastResetMs >= 1000) {
          eventCount = 0;
          lastResetMs = now;
        }

        if (eventCount >= _maxEventsPerSecond) {
          // Drop the event. In a full system, we might route this drop notice
          // to engine telemetry rather than just silencing it.
          return;
        }

        eventCount++;

        // Isolate callback in case the plugin throws synchronously.
        if (onData != null) {
          try {
            onData(event);
          } catch (e, st) {
            // Forward safely to error handler
            if (onError != null) {
              onError(e, st);
            }
          }
        }
      },
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}
