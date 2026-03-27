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

  /// 🚀 Initialize native predicted touches subscription (iOS only)
  void _initNativePredictedTouches() {
    final service = PredictedTouchService.instance;
    service.initialize().then((_) {
      if (service.isSupported) {
        _predictedTouchSubscription = service.predictedTouchStream.listen((
          points,
        ) {
          // Convert native points to ProDrawingPoint
          _nativePredictedPoints.clear();
          for (final point in points) {
            if (point.isPredicted) {
              _nativePredictedPoints.add(
                ProDrawingPoint(
                  position: Offset(point.x, point.y),
                  pressure: point.pressure,
                  timestamp: point.timestamp,
                ),
              );
            }
          }
          // Notify listener about predicted points
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

      final ts = startTs + (i * dt);
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

    // 🚀 Notify once for the whole batch
    onPointsUpdated?.call(_currentStroke);
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
