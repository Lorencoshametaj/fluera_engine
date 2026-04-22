import 'dart:async';
import 'package:flutter/material.dart';
import '../models/pro_drawing_point.dart';
import '../filters/one_euro_filter.dart';
import '../filters/stroke_stabilizer.dart';
import '../filters/physics_ink_simulator.dart';
import '../../systems/organic_behavior_engine.dart';
// SDK: AI filters removed — use optional callback via FlueraToolbarConfig
import './predicted_touch_service.dart';

/// 🎨 DRAWING INPUT HANDLER
///
/// Handles drawing input logic, shared between:
/// - ProfessionalCanvasScreen
/// - BrushTestScreen
///
/// RESPONSIBILITIES:
/// - ✅ Gestione eventi touch/stylus (start, update, end)
/// - ✅ OneEuroFilter for adaptive smoothing
/// - ✅ Creazione punti ProDrawingPoint
/// - ✅ NO adaptive sampling (all points are recorded)
/// - ✅ NO post-stroke optimization (faithful stroke)
/// - 🚀 Native iOS predicted touches for ultra-low latency
///
/// PHILOSOPHY:
/// - Zero modifications to the user's stroke
/// - All points are preserved (circles close properly)
/// - Optional smoothing only during drawing (OneEuroFilter)
class DrawingInputHandler {
  /// Filtero OneEuroFilter for adaptive smoothing
  final OneEuroFilter _oneEuroFilter;

  /// 🎯 SAI-style stroke stabilizer — smooths hand tremor in real-time
  final StrokeStabilizer _stabilizer = StrokeStabilizer();

  /// 🌱 Physics ink simulator — spring-based inertial following
  final PhysicsInkSimulator _inkSimulator = PhysicsInkSimulator(
    damping: 0.2,
    stiffness: 350.0,
    mass: 0.8,
  );

  /// 🌱 Per-brush physics ink profile
  /// Returns (blendFactor, trailingCount) for each pen type.
  static ({double blend, int trailing}) _inkProfile(ProPenType? penType) {
    return switch (penType) {
      ProPenType.fountain => (blend: 0.25, trailing: 5),
      ProPenType.charcoal => (blend: 0.20, trailing: 3),
      ProPenType.watercolor => (blend: 0.20, trailing: 3),
      ProPenType.inkWash => (blend: 0.18, trailing: 4),
      ProPenType.oilPaint => (blend: 0.15, trailing: 3),
      ProPenType.pencil => (blend: 0.12, trailing: 2),
      ProPenType.marker => (blend: 0.10, trailing: 2),
      ProPenType.sprayPaint => (blend: 0.08, trailing: 1),
      ProPenType.neonGlow => (blend: 0.05, trailing: 1),
      ProPenType.ballpoint => (blend: 0.0, trailing: 0),
      ProPenType.highlighter => (blend: 0.0, trailing: 0),
      ProPenType.technicalPen => (blend: 0.0, trailing: 0),
      null => (blend: 0.15, trailing: 3),
    };
  }

  /// 🌱 Current pen type for physics ink profile (set by caller)
  ProPenType? currentPenType;

  /// Flag per abilitare/disabilitare OneEuroFilter
  bool enableOneEuroFilter;

  /// Current stroke in construction
  /// 🚀 PERF: Non-final — replaced (not cleared) on endStroke/startStroke
  /// to preserve old list references held by the StrokeNotifier.
  List<ProDrawingPoint> _currentStroke = [];

  /// 🚀 Direct reference to internal stroke list — shared with notifier.
  /// The screen reads this reference and calls forceRepaint() on the notifier.
  /// NO COPIES are ever made during drawing.
  List<ProDrawingPoint> get currentStrokeRef => _currentStroke;

  /// 🚀 Native predicted points from iOS (if available)
  final List<ProDrawingPoint> _nativePredictedPoints = [];

  /// 🚀 Subscription to native predicted touches
  StreamSubscription<List<PredictedTouchPoint>>? _predictedTouchSubscription;

  /// Toggle runtime logging of per-stroke sample rate.
  /// Set to true to show the in-app debug overlay with per-stroke hz/count.
  static bool debugLogSampleRate = false;

  /// Live per-stroke metrics (hz/count/duration) for the in-app debug overlay.
  /// Updated on endStroke so the overlay stays readable between strokes.
  static final ValueNotifier<String> debugStrokeNotifier =
      ValueNotifier<String>('');

  int _ingestedSampleCount = 0;
  int _strokeStartMs = 0;

  /// Last time (ms since epoch) a native coalesced batch was ingested. Used
  /// as a rolling watchdog: while the native EventChannel is feeding samples,
  /// Flutter-side [updateStroke] calls become no-ops to avoid duplicates.
  /// If the native stream goes quiet (non-Pencil, Android, bug), Flutter
  /// resumes driving the stroke after [_nativeStaleThresholdMs].
  int _lastNativeIngestMs = 0;

  /// If no native batch has arrived for this many ms, fall back to the
  /// Flutter 120 Hz path. Keep small — at 120 Hz Flutter events arrive every
  /// ~8.3 ms, so one missed native frame should still be bridged.
  static const int _nativeStaleThresholdMs = 20;

  /// True while the native EventChannel is currently authoritative for the
  /// stroke (recent native batch observed). Readers use this to gate
  /// ancillary behaviors that were previously tied to Flutter pointer events.
  bool get nativeInputAuthoritative {
    if (_lastNativeIngestMs == 0) return false;
    return DateTime.now().millisecondsSinceEpoch - _lastNativeIngestMs <
        _nativeStaleThresholdMs;
  }

  bool _nativeWasUsedThisStroke = false;

  /// True if any native batch was ingested during the current (or just-ended)
  /// stroke. Used e.g. to suppress rendered-count trimming on commit since
  /// the extra samples are real user motion, not lookahead.
  bool get nativeWasUsedThisStroke => _nativeWasUsedThisStroke;

  /// Callback called when a nuovo punto is added
  /// 🚀 PERFORMANCE: Passa la lista originale, non una copia!
  final void Function(List<ProDrawingPoint> points)? onPointsUpdated;

  /// 🚀 Callback per punti predetti nativi (per rendering anti-lag)
  final void Function(List<ProDrawingPoint> predictedPoints)?
  onPredictedPointsUpdated;

  /// Callback called when the tratto is completato
  final void Function(List<ProDrawingPoint> finalPoints)? onStrokeCompleted;

  DrawingInputHandler({
    this.enableOneEuroFilter = true,
    this.onPointsUpdated,
    this.onPredictedPointsUpdated,
    this.onStrokeCompleted,
    double minCutoff = 1.0,
    double beta = 0.007,
    double dCutoff = 1.0,
  }) : _oneEuroFilter = OneEuroFilter(
         minCutoff: minCutoff,
         beta: beta,
         dCutoff: dCutoff,
       ) {
    // 🚀 Subscribe to native predicted touches if available
    _initNativePredictedTouches();
  }

  /// 🚀 Initialize native predicted touches subscription (iOS only).
  /// Subscribes to the predicted (visual anti-lag) stream. Real coalesced
  /// touches have a separate subscription owned by the canvas screen — see
  /// [PredictedTouchService.realTouchStream].
  void _initNativePredictedTouches() {
    final service = PredictedTouchService.instance;
    service.initialize().then((_) {
      if (service.isSupported) {
        _predictedTouchSubscription = service.predictedTouchStream.listen((
          points,
        ) {
          _nativePredictedPoints.clear();
          for (final point in points) {
            if (!point.isPredicted) continue;
            _nativePredictedPoints.add(
              ProDrawingPoint(
                position: Offset(point.x, point.y),
                pressure: point.pressure,
                timestamp: point.timestamp,
              ),
            );
          }
          if (_nativePredictedPoints.isNotEmpty) {
            onPredictedPointsUpdated?.call(_nativePredictedPoints);
          }
        });
      }
    });
  }

  /// 🚀 Get native predicted points (read-only)
  List<ProDrawingPoint> get nativePredictedPoints =>
      List.unmodifiable(_nativePredictedPoints);

  /// � Factory: creates DrawingInputHandler with settings from SharedPreferences
  static Future<DrawingInputHandler> createWithSavedSettings({
    void Function(List<ProDrawingPoint> points)? onPointsUpdated,
    void Function(List<ProDrawingPoint> finalPoints)? onStrokeCompleted,
    bool enableOneEuroFilter = true,
    double minCutoff = 1.0,
    double beta = 0.007,
    double dCutoff = 1.0,
  }) async {
    return DrawingInputHandler(
      enableOneEuroFilter: enableOneEuroFilter,
      onPointsUpdated: onPointsUpdated,
      onStrokeCompleted: onStrokeCompleted,
      minCutoff: minCutoff,
      beta: beta,
      dCutoff: dCutoff,
    );
  }

  /// 🎨 Start a new stroke
  ///
  /// [screenPosition] Position in SCREEN coordinates (pixels)
  /// [scaleFactor] Page scale factor (to convert to doc-space)
  /// [eventTimestamp] Timestamp from PointerEvent (milliseconds)
  /// [pressure] Stylus pressure (0.0-1.0), default 1.0 for touch
  /// [tiltX] Stylus X tilt (-1.0 to 1.0)
  /// [tiltY] Stylus Y tilt (-1.0 to 1.0)
  /// [orientation] Stylus orientation (radians)
  ///
  /// Overload: accepts doc-space directly when scaleFactor is omitted (legacy).
  void startStroke({
    required Offset position,
    Offset? screenPosition,
    double? scaleFactor,
    int? eventTimestamp,
    double pressure = 1.0,
    double tiltX = 0.0,
    double tiltY = 0.0,
    double orientation = 0.0,
  }) {
    // Reset filtri per nuovo tratto
    _oneEuroFilter.reset();
    _stabilizer.reset();
    _inkSimulator.reset();

    // 🚀 PERF: Replace with new list to preserve old reference if still held
    _currentStroke = [];

    // 🚀 PHASE 1: Coordinate transform happens HERE (single place)
    final docPosition =
        (screenPosition != null && scaleFactor != null && scaleFactor > 0)
            ? Offset(
              screenPosition.dx / scaleFactor,
              screenPosition.dy / scaleFactor,
            )
            : position;

    final ts = eventTimestamp ?? DateTime.now().millisecondsSinceEpoch;

    // Create primo punto
    final point = ProDrawingPoint(
      position: docPosition,
      pressure: pressure,
      tiltX: tiltX,
      tiltY: tiltY,
      orientation: orientation,
      timestamp: ts,
    );

    _currentStroke.add(point);

    _ingestedSampleCount = 1;
    _strokeStartMs = DateTime.now().millisecondsSinceEpoch;
    _lastNativeIngestMs = 0;
    _nativeWasUsedThisStroke = false;

    // Notify callback - passa lista originale (il painter non deve modificarla!)
    // 🚀 PERFORMANCE: No copies created
    onPointsUpdated?.call(_currentStroke);
  }

  /// 🎨 Adds a point to the current stroke
  ///
  /// IMPORTANT: ALL points are recorded, without adaptive sampling.
  /// This ensures that circles close correctly.
  ///
  /// [position] Position in coordinate doc-space (legacy fallback)
  /// [screenPosition] Position in SCREEN coordinates (pixels)
  /// [scaleFactor] Fattore di scala pagina
  /// [eventTimestamp] Timestamp from PointerEvent (milliseconds)
  /// [pressure] Stylus pressure (0.0-1.0), default 1.0 for touch
  /// [silent] If true, skips onPointsUpdated callback (for batch interpolation)
  void updateStroke({
    required Offset position,
    Offset? screenPosition,
    double? scaleFactor,
    int? eventTimestamp,
    double pressure = 1.0,
    double tiltX = 0.0,
    double tiltY = 0.0,
    double orientation = 0.0,
    bool silent = false,
  }) {
    // Native EventChannel is feeding the stroke at 240 Hz — skip this
    // 120 Hz sample to avoid duplicates. Rolling watchdog: auto-fallback if
    // the native stream goes quiet.
    if (nativeInputAuthoritative) return;

    // 🚀 PHASE 1: Coordinate transform happens HERE (single place)
    final docPosition =
        (screenPosition != null && scaleFactor != null && scaleFactor > 0)
            ? Offset(
              screenPosition.dx / scaleFactor,
              screenPosition.dy / scaleFactor,
            )
            : position;

    final ts = eventTimestamp ?? DateTime.now().millisecondsSinceEpoch;

    // 🎨 FILTRI PROFESSIONALI:
    // 1. OneEuroFilter for adaptive smoothing (opzionale)
    Offset filteredPosition =
        enableOneEuroFilter
            ? _oneEuroFilter.filter(docPosition, ts)
            : docPosition;

    // 🌱 Phase 4C: Physics ink simulation — inertial following
    final inkProfile = _inkProfile(currentPenType);
    if (OrganicBehaviorEngine.physicsInkEnabled && inkProfile.blend > 0) {
      // 🌱 Pressure → mass: heavy strokes = more inertia, light = agile
      _inkSimulator.mass = 0.5 + pressure * 1.0; // 0.5 at zero, 1.5 at full
      _inkSimulator.updateTarget(
        filteredPosition,
        DateTime.fromMillisecondsSinceEpoch(ts),
      );
      final physicsPos = _inkSimulator.getSimulatedPosition();
      final blend = inkProfile.blend;
      filteredPosition = Offset(
        filteredPosition.dx * (1.0 - blend) + physicsPos.dx * blend,
        filteredPosition.dy * (1.0 - blend) + physicsPos.dy * blend,
      );
    }

    // 🎯 Phase 4B: Apply stroke stabilizer smoothing (real-time)
    if (_stabilizer.level > 0) {
      filteredPosition = _stabilizer.stabilize(
        filteredPosition,
        timestampUs: ts * 1000, // ms → μs
      );
    }

    // 2. Normalize pressure for stability (clamp + smoothing)
    double normalizedPressure = _normalizePressure(pressure);

    // 🆕 Smooth pressure via stabilizer MA
    if (_stabilizer.level > 0) {
      normalizedPressure = _stabilizer.stabilizePressure(normalizedPressure);
    }

    // Create punto con position e pressione filtrate
    final point = ProDrawingPoint(
      position: filteredPosition,
      pressure: normalizedPressure,
      tiltX: tiltX,
      tiltY: tiltY,
      orientation: orientation,
      timestamp: ts,
    );

    _currentStroke.add(point);
    _ingestedSampleCount++;

    // 🚀 PERFORMANCE: Skip callback for silent (interpolated) points.
    // The final real point will trigger the callback once, causing ONE repaint
    // with ALL points instead of N repaints per event.
    if (!silent) {
      // Notify callback - passa lista originale (il painter non deve modificarla!)
      // 🚀 PERFORMANCE: No copies created
      onPointsUpdated?.call(_currentStroke);
    }
  }

  /// 🎨 Adds a batch of points to the current stroke
  ///
  /// PERFORMANCE: This is much more efficient than calling updateStroke in a loop
  /// as it triggers `onPointsUpdated` only once at the end.
  void addPointsBatch({
    required List<Offset> positions,
    Offset?
    screenPositionOrigin, // Optional: if provided, positions are relative to this
    double? scaleFactor,
    required List<double> pressures,
    List<double>? tiltsX,
    List<double>? tiltsY,
    List<double>? orientations,
    int? baseTimestamp,
    int? timeDeltaPerPoint, // e.g., 1ms per point for interpolation
    List<int>? timestamps, // Per-point timestamps (ms); overrides base+delta.
  }) {
    if (positions.isEmpty) return;

    final count = positions.length;
    final int startTs = baseTimestamp ?? DateTime.now().millisecondsSinceEpoch;
    final int dt = timeDeltaPerPoint ?? 1;

    for (int i = 0; i < count; i++) {
      final pos = positions[i];

      // 🚀 Transform coordinate if needed
      final docPosition =
          (scaleFactor != null && scaleFactor > 0)
              ? Offset(pos.dx / scaleFactor, pos.dy / scaleFactor)
              : pos;

      final ts =
          (timestamps != null && i < timestamps.length)
              ? timestamps[i]
              : startTs + (i * dt);
      final pressure = i < pressures.length ? pressures[i] : 1.0;
      final tx = (tiltsX != null && i < tiltsX.length) ? tiltsX[i] : 0.0;
      final ty = (tiltsY != null && i < tiltsY.length) ? tiltsY[i] : 0.0;
      final orientation =
          (orientations != null && i < orientations.length)
              ? orientations[i]
              : 0.0;

      // 🎨 FILTRI PROFESSIONALI
      // 1. OneEuroFilter
      Offset filteredPosition =
          enableOneEuroFilter
              ? _oneEuroFilter.filter(docPosition, ts)
              : docPosition;

      // 2. Stabilizer
      if (_stabilizer.level > 0) {
        filteredPosition = _stabilizer.stabilize(
          filteredPosition,
          timestampUs: ts * 1000, // ms → μs
        );
      }

      // 3. Pressure normalization
      final normalizedPressure = _normalizePressure(pressure);

      final point = ProDrawingPoint(
        position: filteredPosition,
        pressure: normalizedPressure,
        tiltX: tx,
        tiltY: ty,
        orientation: orientation,
        timestamp: ts,
      );

      _currentStroke.add(point);
    }
    _ingestedSampleCount += count;

    // 🚀 Notify once for the whole batch
    onPointsUpdated?.call(_currentStroke);
  }

  /// Ingest a batch of real coalesced samples coming from the native
  /// EventChannel (Apple Pencil ~240 Hz). [canvasSpacePositions] must already
  /// be in canvas/document coordinates — callers run screenToCanvas upstream
  /// because this handler is transform-agnostic. [timestamps] are ms on the
  /// uptime clock (as emitted by UITouch).
  void ingestCoalescedBatch({
    required List<Offset> canvasSpacePositions,
    required List<double> pressures,
    required List<int> timestamps,
  }) {
    if (canvasSpacePositions.isEmpty) return;
    _lastNativeIngestMs = DateTime.now().millisecondsSinceEpoch;
    _nativeWasUsedThisStroke = true;
    addPointsBatch(
      positions: canvasSpacePositions,
      pressures: pressures,
      timestamps: timestamps,
    );
  }

  /// 🎨 Complete the current stroke
  ///
  /// IMPORTANTE: NO post-stroke optimization is applied.
  /// The stroke remains exactly as drawn by the user.
  ///
  /// Returns: Final list of points (immutable)
  List<ProDrawingPoint> endStroke() {
    // 🌱 Inertial trailing: DISABLED.
    // Appending physics-simulated trailing points on finalization shifts
    // global arc-length resampling and backward EMA smoothing, causing the
    // entire finalized stroke to look visually different from the live version.
    // Since these points are never rendered during live drawing, their injection
    // creates a noticeable quality mismatch on pointer-up.
    //
    // TODO: Re-enable when live CurrentStrokePainter also renders
    // predicted trailing points in real-time (matching finalized output).

    // final inkProfile = _inkProfile(currentPenType);
    // if (OrganicBehaviorEngine.physicsInkEnabled &&
    //     inkProfile.trailing > 0 &&
    //     _currentStroke.length >= 3) { ... }

    // 🆕 Catch-up: append interpolated points to close stabilizer lag gap
    if (_stabilizer.level > 0 && _currentStroke.isNotEmpty) {
      final lastRaw = _currentStroke.last.position;
      final catchUpPoints = _stabilizer.finalize(lastRaw);
      final lastPressure = _currentStroke.last.pressure;
      final lastTs = _currentStroke.last.timestamp;
      for (int i = 0; i < catchUpPoints.length; i++) {
        _currentStroke.add(
          ProDrawingPoint(
            position: catchUpPoints[i],
            pressure: lastPressure,
            timestamp: lastTs + i + 1,
          ),
        );
      }
    }

    // 🌱 Notify pattern tracker for adaptive intensity
    OrganicBehaviorEngine.notifyStrokeCompleted(_currentStroke.length);

    if (debugLogSampleRate && _strokeStartMs > 0) {
      final durationMs = DateTime.now().millisecondsSinceEpoch - _strokeStartMs;
      final hz = durationMs > 0
          ? (_ingestedSampleCount * 1000.0 / durationMs)
          : 0.0;
      final line =
          'stroke hz=${hz.toStringAsFixed(0)}  '
          'count=$_ingestedSampleCount  '
          'ms=$durationMs  '
          'native=${_nativeWasUsedThisStroke ? "Y" : "N"}';
      debugPrint('[DrawingInputHandler] $line');
      debugStrokeNotifier.value = line;
    }
    _ingestedSampleCount = 0;
    _strokeStartMs = 0;
    _lastNativeIngestMs = 0;
    // Keep _nativeWasUsedThisStroke alive: callers consult it *after*
    // endStroke() (commit path) to decide whether to suppress
    // rendered-count trimming. Next startStroke resets it.

    // Create copia defensiva to avoid modifiche future
    final finalPoints = List<ProDrawingPoint>.unmodifiable(_currentStroke);

    // Notify callback
    onStrokeCompleted?.call(finalPoints);

    // 🚀 PERF: Replace with new list instead of .clear().
    // This preserves the old list reference (still held by StrokeNotifier)
    // allowing the screen to pass _currentStroke directly without O(N) copies.
    _currentStroke = [];

    return finalPoints;
  }

  /// Get il current stroke (read-only)
  List<ProDrawingPoint> get currentStroke => List.unmodifiable(_currentStroke);

  /// Checks se c'è un stroke in progress
  bool get hasStroke => _currentStroke.isNotEmpty;

  /// Erases the current stroke without completing it
  void cancelStroke() {
    _currentStroke = [];
    _ingestedSampleCount = 0;
    _strokeStartMs = 0;
    _lastNativeIngestMs = 0;
    _nativeWasUsedThisStroke = false;
    onPointsUpdated?.call(const []);
  }

  /// Current stabilizer level (0 = off, 10 = max smoothing)
  int get stabilizerLevel => _stabilizer.level;
  set stabilizerLevel(int value) => _stabilizer.level = value;

  /// Apply stabilizer smoothing to a raw position (for 120Hz path).
  /// Returns the smoothed position. O(1) per call.
  Offset applyStabilizer(Offset rawPosition) =>
      _stabilizer.stabilize(rawPosition);

  /// Reset stabilizer state for a new stroke (for 120Hz path).
  void resetStabilizer() => _stabilizer.reset();

  /// 🆕 Finalize stabilizer: returns catch-up points to close the lag gap.
  /// Call this on stroke end in 120Hz path.
  List<Offset> finalizeStabilizer(Offset lastRawPosition) =>
      _stabilizer.finalize(lastRawPosition);

  /// 🆕 Smooth pressure via stabilizer (for 120Hz path)
  double smoothPressure(double rawPressure) =>
      _stabilizer.stabilizePressure(rawPressure);

  /// Complete reset of the handler
  void reset() {
    _currentStroke = [];
    _nativePredictedPoints.clear();
    _ingestedSampleCount = 0;
    _strokeStartMs = 0;
    _lastNativeIngestMs = 0;
    _nativeWasUsedThisStroke = false;
    _oneEuroFilter.reset();
    _stabilizer.reset();
    _inkSimulator.reset();
  }

  /// 🚀 Cleanup resources
  void dispose() {
    _predictedTouchSubscription?.cancel();
    _predictedTouchSubscription = null;
    _nativePredictedPoints.clear();
  }

  /// 🎯 Normalize pressure for professional stability
  ///
  /// FUNCTION:
  /// - Clamp to valid range 0.1-1.0
  /// - Smoothing with last 3 points to eliminate hardware jitter
  /// - Preserves intentional variations
  ///
  /// [pressure] Raw pressure value
  /// Returns: Normalized and smoothed pressure
  double _normalizePressure(double pressure) {
    // 1. Clamp to valid range (0.1 = minimum visible, 1.0 = maximum)
    final clamped = pressure.clamp(0.1, 1.0);

    // 2. Smoothing with last 3 points to eliminate jitter
    if (_currentStroke.length >= 2) {
      final prev2 = _currentStroke[_currentStroke.length - 2].pressure;
      final prev1 = _currentStroke[_currentStroke.length - 1].pressure;

      // Media pesata: current point 50%, precedenti 25% ciascuno
      return (clamped * 0.5 + prev1 * 0.3 + prev2 * 0.2);
    } else if (_currentStroke.length == 1) {
      final prev1 = _currentStroke[0].pressure;
      return (clamped * 0.7 + prev1 * 0.3);
    }

    // Primo punto: usa direttamente il valore clamped
    return clamped;
  }
}
