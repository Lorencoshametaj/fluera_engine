/// Built-in [CommandMiddleware] implementations for the Fluera Engine.
///
/// These middlewares bridge the command system to other engine subsystems:
/// - [EventBusCommandMiddleware] — emits [CommandExecutedEngineEvent] and
///   [CommandUndoneEngineEvent] on the [EngineEventBus].
library;

import '../core/engine_event.dart';
import '../core/engine_event_bus.dart';
import 'command_history.dart';

// ---------------------------------------------------------------------------
// Event Bus Command Middleware
// ---------------------------------------------------------------------------

/// Emits [CommandExecutedEngineEvent] and [CommandUndoneEngineEvent] on the
/// [EngineEventBus] whenever a command is executed or undone.
///
/// ```dart
/// final history = CommandHistory(
///   middlewares: [EventBusCommandMiddleware(eventBus)],
/// );
/// ```
class EventBusCommandMiddleware extends CommandMiddleware {
  final EngineEventBus _eventBus;

  EventBusCommandMiddleware(this._eventBus);

  @override
  void afterExecute(Command cmd) {
    _eventBus.emit(
      CommandExecutedEngineEvent(
        commandLabel: cmd.label,
        commandType: cmd.runtimeType.toString(),
      ),
    );
  }

  @override
  void afterUndo(Command cmd) {
    _eventBus.emit(
      CommandUndoneEngineEvent(
        commandLabel: cmd.label,
        commandType: cmd.runtimeType.toString(),
      ),
    );
  }

  @override
  void afterRedo(Command cmd) {
    _eventBus.emit(
      CommandExecutedEngineEvent(
        commandLabel: cmd.label,
        commandType: cmd.runtimeType.toString(),
      ),
    );
  }
}
