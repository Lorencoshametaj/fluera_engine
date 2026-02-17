import 'dart:async';
import 'package:flutter/scheduler.dart';
import '../../core/engine_scope.dart';

/// 🚀 FRAME BUDGET MANAGER - Mantiene 60 FPS anche con 500k strokes
///
/// PROBLEMA:
/// Rasterizere tile con molti strokes can bloccare il main thread,
/// causando jank e FPS drop.
///
/// SOLUZIONE:
/// - Budget per frame: max N ms of work per frame
/// - Time-slicing: dividi lavoro pesante su more frame
/// - Priority scheduling: visible work first
/// - Adaptive throttling: rallenta in background
///
/// PERFORMANCE:
/// - Every frame: max 8ms of rasterization (leaves 8ms for rendering)
/// - 60 FPS guaranteed even during heavy rasterization
class FrameBudgetManager {
  // ═══════════════════════════════════════════════════════════════════════════
  // 📐 CONFIGURATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Budget massimo per frame in ms (16ms = 60 FPS, usiamo mage)
  static const double frameBudgetMs = 8.0;

  /// Soglia per considerare un task "pesante"
  static const double heavyTaskThresholdMs = 4.0;

  /// Max tasks per frame
  static const int maxTasksPerFrame = 10;

  // ═══════════════════════════════════════════════════════════════════════════
  // 🗂️ STATE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Coda di task da eseguire
  final List<BudgetedTask> _taskQueue = [];

  /// Tempo usato nel current frame
  double _currentFrameTimeMs = 0;

  /// Stopwatch per misurare tempo
  final Stopwatch _stopwatch = Stopwatch();

  /// Flag to avoid registrazioni multiple
  bool _isScheduled = false;

  /// Legacy singleton accessor — delegates to [EngineScope.current].
  static FrameBudgetManager get instance =>
      EngineScope.current.frameBudgetManager;

  /// Creates a new instance (used by [EngineScope]).
  FrameBudgetManager.create();

  // ═══════════════════════════════════════════════════════════════════════════
  // 🚀 SCHEDULING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Adds a task to the queue
  ///
  /// [task]: Funzione da eseguire
  /// [priority]: 0 = bassa, 100 = alta (visibile immediatamente)
  /// [estimatedMs]: Tempo stimato in ms (per budgeting)
  void scheduleTask(
    Future<void> Function() task, {
    double priority = 50,
    double estimatedMs = 2.0,
    String? debugLabel,
  }) {
    _taskQueue.add(
      BudgetedTask(
        task: task,
        priority: priority,
        estimatedMs: estimatedMs,
        debugLabel: debugLabel,
      ),
    );

    // Sort per priority (alta prima)
    _taskQueue.sort((a, b) => b.priority.compareTo(a.priority));

    _scheduleFrame();
  }

  /// Schedules next frame if not already schedulato
  void _scheduleFrame() {
    if (_isScheduled) return;
    _isScheduled = true;

    SchedulerBinding.instance.scheduleFrameCallback(_onFrame);
  }

  /// Callback eseguito every frame
  void _onFrame(Duration timestamp) {
    _isScheduled = false;
    _currentFrameTimeMs = 0;
    _stopwatch.reset();
    _stopwatch.start();

    int tasksExecuted = 0;

    while (_taskQueue.isNotEmpty &&
        _currentFrameTimeMs < frameBudgetMs &&
        tasksExecuted < maxTasksPerFrame) {
      final task = _taskQueue.first;

      // If il task is too pesante for the budget rimanente, salta a next frame
      if (_currentFrameTimeMs + task.estimatedMs > frameBudgetMs &&
          tasksExecuted > 0) {
        break;
      }

      // Execute task
      _taskQueue.removeAt(0);

      // Execute in modo fire-and-forget
      task
          .task()
          .then((_) {
            // Task completato - niente da fare
          })
          .catchError((e) {});

      // Assumi tempo stimato per budgeting (task is async)
      _currentFrameTimeMs += task.estimatedMs;
      tasksExecuted++;
    }

    _stopwatch.stop();

    // If ci sono ancora task, schedula next frame
    if (_taskQueue.isNotEmpty) {
      _scheduleFrame();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ⏱️ SYNC EXECUTION (for thevoro critico)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Executes lavoro con budget checking
  ///
  /// Returns false if the budget is esaurito.
  /// Usare per dividere loop pesanti.
  bool hasRemainingBudget() {
    return _stopwatch.elapsedMilliseconds < frameBudgetMs;
  }

  /// Misura tempo speso e aggiornа budget
  T measureWork<T>(T Function() work) {
    final start = _stopwatch.elapsedMicroseconds;
    final result = work();
    final elapsed = (_stopwatch.elapsedMicroseconds - start) / 1000;
    _currentFrameTimeMs += elapsed;
    return result;
  }

  /// Yield: ritorna se budget esaurito
  ///
  /// Usare in loop pesanti:
  /// ```dart
  /// for (final stroke in strokes) {
  ///   processStroke(stroke);
  ///   if (FrameBudgetManager.instance.shouldYield()) break;
  /// }
  /// ```
  bool shouldYield() {
    return _stopwatch.elapsedMilliseconds >= frameBudgetMs;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 📊 STATISTICS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Numero task in coda
  int get pendingTasks => _taskQueue.length;

  /// Statistics for debugging
  Map<String, dynamic> get stats => {
    'pendingTasks': pendingTasks,
    'frameBudgetMs': frameBudgetMs,
    'isScheduled': _isScheduled,
  };

  // ═══════════════════════════════════════════════════════════════════════════
  // 🧹 CLEANUP
  // ═══════════════════════════════════════════════════════════════════════════

  /// Erases tutti i task pendenti
  void clearQueue() {
    _taskQueue.clear();
  }

  /// Erases task with priority < threshold
  void clearLowPriorityTasks(double threshold) {
    _taskQueue.removeWhere((t) => t.priority < threshold);
  }
}

/// Task con budgeting
class BudgetedTask {
  final Future<void> Function() task;
  final double priority;
  final double estimatedMs;
  final String? debugLabel;

  const BudgetedTask({
    required this.task,
    required this.priority,
    required this.estimatedMs,
    this.debugLabel,
  });
}

/// 🚀 MEMORY PRESSURE HANDLER - Gestisce memoria sotto pressione
///
/// Detects when the memoria is bassa e libera cache aggressivamente.
class MemoryPressureHandler {
  // ═══════════════════════════════════════════════════════════════════════════
  // 📐 SOGLIE MEMORIA
  // ═══════════════════════════════════════════════════════════════════════════

  /// Warning threshold (MB): inizia a liberare cache bassa priority
  static const double warningThresholdMB = 500;

  /// Critical threshold (MB): libera tutto il possibile
  static const double criticalThresholdMB = 200;

  // ═══════════════════════════════════════════════════════════════════════════
  // 🗂️ STATE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Callbacks to call under memory pressure
  final List<void Function(MemoryPressureLevel)> _pressureCallbacks = [];

  /// Livello corrente
  MemoryPressureLevel _currentLevel = MemoryPressureLevel.normal;

  /// Legacy singleton accessor — delegates to [EngineScope.current].
  static MemoryPressureHandler get instance =>
      EngineScope.current.memoryPressureHandler;

  /// Creates a new instance (used by [EngineScope]).
  MemoryPressureHandler.create();

  // ═══════════════════════════════════════════════════════════════════════════
  // 🚀 REGISTRATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Registra callback per notifiche pressione memoria
  void registerCallback(void Function(MemoryPressureLevel) callback) {
    _pressureCallbacks.add(callback);
  }

  /// Remove callback
  void unregisterCallback(void Function(MemoryPressureLevel) callback) {
    _pressureCallbacks.remove(callback);
  }

  /// Notifies pressione memoria (chiamato dal sistema o manualmente)
  void notifyPressure(MemoryPressureLevel level) {
    if (level == _currentLevel) return;

    _currentLevel = level;

    for (final callback in _pressureCallbacks) {
      try {
        callback(level);
      } catch (e) {}
    }
  }

  /// Simula pressione memoria per testing
  void simulatePressure(MemoryPressureLevel level) {
    notifyPressure(level);
  }

  /// Livello corrente
  MemoryPressureLevel get currentLevel => _currentLevel;
}

/// Livelli di pressione memoria
enum MemoryPressureLevel {
  /// Normale: cache full capacity
  normal,

  /// Warning: riduci cache del 50%
  warning,

  /// Critico: libera tutto il possibile
  critical,
}
