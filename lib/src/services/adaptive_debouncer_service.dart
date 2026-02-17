import 'dart:async';

import 'package:flutter/foundation.dart';
import '../core/engine_scope.dart';

/// ⏱️ AdaptiveDebouncerService - Debounce dinamico for saving canvas
///
/// Adapt debounce time based on diagram state:
/// - Durante disegno attivo: debounce lungo (3s) per non interrompere il flusso
/// - Dopo inactivity (500ms): debounce corto per salvare rapidamente
/// - Supporta callback diversi per delta-only vs full checkpoint
///
/// 🎯 Obiettivo: zero lag during drawing, salvataggio veloce dopo
class AdaptiveDebouncerService {
  // Singleton
  /// Legacy singleton accessor — delegates to [EngineScope.current].
  static AdaptiveDebouncerService get instance => EngineScope.current.adaptiveDebouncerService;

  /// Creates a new instance (used by [EngineScope]).
  AdaptiveDebouncerService.create();

  // ============================================================================
  // CONFIGURATION
  // ============================================================================

  /// Debounce base durante disegno attivo (aumentato da 3s a 5s)
  static const Duration baseActiveDebounce = Duration(seconds: 5);

  /// Debounce minimo durante disegno intenso (molti strokes/sec)
  static const Duration minActiveDebounce = Duration(seconds: 3);

  /// Debounce massimo durante disegno lento (pochi strokes/sec)
  static const Duration maxActiveDebounce = Duration(seconds: 8);

  /// Debounce dopo inactivity (corto per salvare velocemente)
  static const Duration idleDebounce = Duration(milliseconds: 300);

  /// Tempo di inactivity per considerare il disegno "terminato"
  static const Duration inactivityThreshold = Duration(milliseconds: 500);

  /// Intervallo minimo tra salvataggi (rate limiting) - aumentato a 5s
  static const Duration minSaveInterval = Duration(seconds: 5);

  /// Soglia strokes/secondo per considerare disegno "intenso"
  static const double highIntensityThreshold = 2.0; // strokes/sec

  /// Soglia strokes/secondo per considerare disegno "lento"
  static const double lowIntensityThreshold = 0.3; // strokes/sec

  // ============================================================================
  // STATE
  // ============================================================================

  /// Timer per debounce principale
  Timer? _debounceTimer;

  /// Timer per rilevare inactivity
  Timer? _inactivityTimer;

  /// Last save timestamp
  DateTime? _lastSaveTime;

  /// Callback pendente da eseguire
  VoidCallback? _pendingCallback;

  /// Flag: l'utente sta attivamente disegnando
  bool _isDrawing = false;

  /// Flag: c'was input recente
  bool _hasRecentInput = false;

  /// Notifier esterno per stato disegno (opzionale, per binding)
  ValueNotifier<bool>? _externalDrawingNotifier;

  /// 📊 ADAPTIVE: Contatore strokes per calcolo intensity
  int _strokeCount = 0;

  /// Timestamp inizio finestra di misurazione
  DateTime? _measurementWindowStart;

  /// Durata finestra di misurazione per calcolo intensity
  static const Duration measurementWindow = Duration(seconds: 10);

  // ============================================================================
  // SETUP
  // ============================================================================

  /// Connette un ValueNotifier esterno per monitorare lo stato disegno
  ///
  /// Use il notifier esistente in professional_canvas_screen
  /// per rilevare automaticamente quando l'utente sta disegnando.
  void bindDrawingNotifier(ValueNotifier<bool> notifier) {
    _externalDrawingNotifier?.removeListener(_onDrawingStateChanged);
    _externalDrawingNotifier = notifier;
    _externalDrawingNotifier!.addListener(_onDrawingStateChanged);
  }

  /// Disconnette il notifier
  void unbindDrawingNotifier() {
    _externalDrawingNotifier?.removeListener(_onDrawingStateChanged);
    _externalDrawingNotifier = null;
  }

  void _onDrawingStateChanged() {
    _isDrawing = _externalDrawingNotifier?.value ?? false;

    if (_isDrawing) {
      // Inizio disegno: resetta timer inactivity
      _inactivityTimer?.cancel();
      _hasRecentInput = true;
    } else {
      // Fine disegno: avvia timer inactivity per flush veloce
      _startInactivityTimer();
    }
  }

  // ============================================================================
  // PUBLIC API
  // ============================================================================

  /// 📝 Notifica che c'was un input (stroke point, etc.)
  ///
  /// Call at each point of the drawing to keep updated
  /// lo stato di "disegno attivo". Reset del timer inactivity.
  void notifyInput() {
    _hasRecentInput = true;
    _isDrawing = true;

    // Reset timer inactivity
    _inactivityTimer?.cancel();
    _startInactivityTimer();
  }

  /// 📊 Notifica che uno stroke was completato
  ///
  /// Used to calculate drawing intensity (strokes/second)
  /// e adattare il debounce di conseguenza.
  void notifyStrokeCompleted() {
    final now = DateTime.now();

    // Initialize finestra se necessario
    _measurementWindowStart ??= now;

    // Reset finestra se troppo vecchia
    if (now.difference(_measurementWindowStart!) > measurementWindow) {
      _strokeCount = 0;
      _measurementWindowStart = now;
    }

    _strokeCount++;
  }

  /// Calculatates l'intensity di disegno (strokes/secondo)
  double get drawingIntensity {
    if (_measurementWindowStart == null || _strokeCount == 0) {
      return 0.0;
    }

    final elapsed = DateTime.now().difference(_measurementWindowStart!);
    if (elapsed.inMilliseconds == 0) return 0.0;

    return _strokeCount / (elapsed.inMilliseconds / 1000.0);
  }

  /// 🔄 Schedula un salvataggio con debounce adattivo
  ///
  /// [callback] - Function to execute (e.g. delta saving)
  /// [forceImmediate] - Ignora debounce e esegui subito (es. exit)
  void scheduleSave({
    required VoidCallback callback,
    bool forceImmediate = false,
  }) {
    _pendingCallback = callback;

    if (forceImmediate) {
      _executeCallback();
      return;
    }

    // Calculate debounce appropriato
    final debounceTime = _calculateDebounceTime();

    // Erase timer precedente
    _debounceTimer?.cancel();

    // Avvia nuovo timer
    _debounceTimer = Timer(debounceTime, () {
      _executeCallback();
    });
  }

  /// 🚀 Flush immediato - esegue callback pendente without attendere
  ///
  /// Call when the user exits the screen or the app goes to background.
  void flush() {
    _debounceTimer?.cancel();
    _inactivityTimer?.cancel();

    if (_pendingCallback != null) {
      _executeCallback();
    }
  }

  /// 🧹 Reset completo del debouncer
  void reset() {
    _debounceTimer?.cancel();
    _inactivityTimer?.cancel();
    _pendingCallback = null;
    _lastSaveTime = null;
    _isDrawing = false;
    _hasRecentInput = false;
    _strokeCount = 0;
    _measurementWindowStart = null;
  }

  /// Stato corrente (per debug/UI)
  bool get isDrawing => _isDrawing;
  bool get hasPendingCallback => _pendingCallback != null;
  Duration get currentDebounceTime => _calculateDebounceTime();

  // ============================================================================
  // PRIVATE METHODS
  // ============================================================================

  /// Calculatates il tempo di debounce basato sullo current state
  ///
  /// 🎯 LOGICA ADATTIVA basata su strokes/secondo:
  /// - Intensità alta (>2 strokes/s): debounce corto (3s) per non perdere dati
  /// - Intensità media: debounce base (5s)
  /// - Intensità bassa (<0.3 strokes/s): debounce lungo (8s) per ridurre I/O
  Duration _calculateDebounceTime() {
    // Rate limiting: non salvare troppo spesso
    if (_lastSaveTime != null) {
      final elapsed = DateTime.now().difference(_lastSaveTime!);
      if (elapsed < minSaveInterval) {
        // Ritarda fino al minimo intervallo
        return minSaveInterval - elapsed;
      }
    }

    // Debounce adattivo basato su stato disegno
    if (_isDrawing || _hasRecentInput) {
      // 📊 Calculate debounce basato su intensity strokes/tempo
      final intensity = drawingIntensity;

      if (intensity >= highIntensityThreshold) {
        // Disegno intenso: salva more spesso per sicurezza
        return minActiveDebounce;
      } else if (intensity <= lowIntensityThreshold) {
        // Disegno lento: can aspettare di more
        return maxActiveDebounce;
      } else {
        // Disegno normale: usa debounce base
        return baseActiveDebounce;
      }
    } else {
      return idleDebounce;
    }
  }

  /// Executes il callback pendente
  void _executeCallback() {
    final callback = _pendingCallback;
    if (callback == null) return;

    // Clear stato
    _pendingCallback = null;
    _debounceTimer?.cancel();

    // Rate limiting check
    final now = DateTime.now();
    if (_lastSaveTime != null) {
      final elapsed = now.difference(_lastSaveTime!);
      if (elapsed < minSaveInterval) {
        // Troppo presto, ri-schedula
        _pendingCallback = callback;
        _debounceTimer = Timer(minSaveInterval - elapsed, _executeCallback);
        return;
      }
    }

    // Execute callback
    _lastSaveTime = now;
    callback();
  }

  /// Avvia timer per rilevare inactivity
  void _startInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(inactivityThreshold, () {
      // Inactivity rilevata: disegno considerato "terminato"
      _hasRecentInput = false;
      _isDrawing = false;

      // If c'è un callback pendente, usa debounce corto
      if (_pendingCallback != null) {
        _debounceTimer?.cancel();
        _debounceTimer = Timer(idleDebounce, _executeCallback);
      }
    });
  }

  // ============================================================================
  // DISPOSE
  // ============================================================================

  void dispose() {
    unbindDrawingNotifier();
    _debounceTimer?.cancel();
    _inactivityTimer?.cancel();
    _pendingCallback = null;
  }
}

/// 🎯 Extension per schedulare salvataggi in modo fluente
extension AdaptiveDebouncerExtension on AdaptiveDebouncerService {
  /// Schedules salvataggio delta (frequente, leggero)
  void scheduleDeltaSave(VoidCallback callback) {
    scheduleSave(callback: callback, forceImmediate: false);
  }

  /// Forza checkpoint completo (raro, pesante)
  void forceCheckpoint(VoidCallback callback) {
    scheduleSave(callback: callback, forceImmediate: true);
  }
}
