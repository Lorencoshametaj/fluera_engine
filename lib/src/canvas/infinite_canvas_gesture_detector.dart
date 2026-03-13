import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import './infinite_canvas_controller.dart';
import '../drawing/input/stylus_detector.dart';
import '../services/handedness_settings.dart';
import './overlays/stylus_hover_overlay.dart';

/// Widget canvas infinito con zoom e pan
///
/// Supporta:
/// - Pinch zoom (due dita)
/// - Pan (two fingers to move)
/// - Drawing (one finger)
/// - Pan with a dito (se enableSingleFingerPan = true)
/// - 🖊️ Stylus Mode: stylus draws, finger pans
bool _defaultBlockPanZoom() => false;

class InfiniteCanvasGestureDetector extends StatefulWidget {
  final InfiniteCanvasController controller;
  final Widget child;
  final Function(Offset, double pressure, double tiltX, double tiltY)?
  onDrawStart;
  final Function(Offset position, double pressure, double tiltX, double tiltY)?
  onDrawUpdate;

  /// 🚀 Callback ottimizzata for batch updates
  final Function(
    List<Offset> positions,
    List<double> pressures,
    List<double> tiltsX,
    List<double> tiltsY,
  )?
  onDrawBatchUpdate;
  final Function(Offset)? onDrawEnd;
  final VoidCallback?
  onDrawCancel; // 🚫 Clear stroke without saving (e.g. 2nd finger interrupts)
  final VoidCallback?
  onDoubleTapZoom; // 🎯 Called on double-tap zoom to undo the first tap's dot
  final Function(Offset)? onLongPress;
  final bool Function() blockPanZoom; // 🔒 Block pan/zoom when true (evaluated at gesture time)
  final bool
  enableSingleFingerPan; // 🖐️ Enable pan with a finger instead of drawing
  /// 📄 Optional callback: given a canvas-space position, returns true if
  /// the single-finger pan should be intercepted and routed to draw callbacks
  /// instead (e.g. for PDF document dragging).
  final bool Function(Offset canvasPosition)? onPanInterceptTest;
  final bool isStylusModeEnabled; // 🖊️ Stylus mode: stylus draws, finger pans

  /// 🖐️ PALM REJECTION: optional exclusion zone where large-area touches
  /// (palms) are silently ignored. Stylus events are never rejected.
  final ui.Rect? palmExclusionZone;

  // 🌀 Image rotation callbacks (two-finger rotate + scale on selected image)
  final VoidCallback? onImageScaleStart;
  final Function(double rotationDelta, double scaleDelta)? onImageTransform;
  final VoidCallback? onImageScaleEnd;

  // 📈 Graph viewport zoom+pan: called when blockPanZoom blocks canvas zoom.
  // Routes two-finger pinch scale and pan delta to graph viewport.
  final Function(double scale, Offset focalDelta)? onBlockedScale;

  const InfiniteCanvasGestureDetector({
    super.key,
    required this.controller,
    required this.child,
    this.onDrawStart,
    this.onDrawUpdate,
    this.onDrawBatchUpdate,
    this.onDrawEnd,
    this.onDrawCancel,
    this.onDoubleTapZoom,
    this.onLongPress,
    this.blockPanZoom = _defaultBlockPanZoom,
    this.enableSingleFingerPan = false,
    this.onPanInterceptTest,
    this.isStylusModeEnabled = false,
    this.palmExclusionZone,
    this.onImageScaleStart,
    this.onImageTransform,
    this.onImageScaleEnd,
    this.onBlockedScale,
  });

  @override
  State<InfiniteCanvasGestureDetector> createState() =>
      _InfiniteCanvasGestureDetectorState();
}

class _InfiniteCanvasGestureDetectorState
    extends State<InfiniteCanvasGestureDetector> {
  // State per gesture recognition
  double _initialScale = 1.0;
  Offset _initialFocalPoint = Offset.zero;
  Offset _initialOffset = Offset.zero;
  int _pointerCount = 0;
  bool _isDrawing = false;
  bool _wasDrawingGesture =
      false; // 🎯 FIX: Prevents _onScaleEnd from launching viewport animations after drawing
  Offset? _firstPointerPosition;
  bool _hasMoved = false;
  bool _wasMultiTouch = false; // Flag to track se c'era multi-touch recente
  int _lastPointerChangeTime = 0; // Timestamp ultimo cambio pointer count

  // State per pan with a dito
  bool _isSingleFingerPanning = false;
  Offset _lastPanPosition = Offset.zero;
  bool _panIntercepted =
      false; // 📄 True when pan was intercepted for document drag

  // 🚀 State for interpolation of missing points
  Offset? _lastDrawPosition;
  Offset?
  _lastCanvasPosition; // 🚀 FIX #5: cache canvas position for interpolation
  double _lastPressure = 1.0;
  // 🔴 CRITICAL: Reduced threshold to capture more points during fast writing
  static const double _interpolationThreshold =
      4.0; // px minimum between points (reduced from 8 for more precision)
  // 🔴 CRITICAL: Increased limit to avoid discontinuities in fast writing
  static const int _maxInterpolatedPoints =
      25; // max punti interpolati per evento (aumentato da 5)

  // 🖊️ State for tilt calculation
  double _lastTiltX = 0.0;
  double _lastTiltY = 0.0;

  // 🖊️ Stylus input manager for stylus mode handling
  final StylusInputManager _stylusManager = StylusInputManager();

  // 🖊️ Flag to enable/disable drawing in stylus mode
  bool _shouldEnableDrawing = true;

  // 🌊 LIQUID: Velocity tracking for pan momentum
  Offset _lastScaleFocalPoint = Offset.zero;
  int _lastScaleUpdateTime = 0;
  Offset _panVelocity = Offset.zero;
  // 🌊 LIQUID: Track if we were zooming (2+ fingers) vs panning
  bool _wasZooming = false;
  Offset _lastScaleEndFocalPoint = Offset.zero;
  // 🌊 LIQUID: Zoom velocity tracking for zoom momentum (Gap 4)
  double _zoomVelocity = 0.0;
  double _lastGestureScale = 1.0;

  // 🔄 GESTURE CONTINUITY: Smooth transition when pointer count changes
  bool _gestureTransitioning = false;
  int _previousPointerCount = 0;

  // 🌀 ROTATION: State tracking
  double _initialRotation = 0.0;
  double _lastGestureRotation = 0.0;
  double _rotationVelocity = 0.0;
  double? _lastSnappedAngle; // Track snap detent to avoid repeated haptics
  bool _rotationUnlocked = false; // Requires intentional rotation to activate

  // 🌀 ROTATION: Deadzone to prevent accidental rotation during zoom/pan.
  // The user must rotate at least ~3° before rotation activates.
  static const double _rotationDeadzone = 0.05; // ~3° in radians
  static const double _maxAngularVelocity = 3.0; // Cap spin speed (rad/s)

  // 🌀 IMAGE ROTATION: State tracking for image-specific rotation
  bool _imageRotationUnlocked = false;
  double _imageRotationAccum = 0.0; // Accumulated rotation for image
  bool _imageScaleStarted = false; // Whether we fired onImageScaleStart
  double? _imageLastSnappedAngle; // For haptic deduplication
  double _imageInitialScale = 1.0; // Scale at gesture start

  // 🎯 DOUBLE-TAP ZOOM: State tracking
  int _lastSingleTapTime = 0;
  Offset _lastSingleTapPosition = Offset.zero;
  bool _pendingFirstTap =
      false; // True while waiting to see if second tap comes

  // ─── 🚀 GESTURE COALESCING ──────────────────────────────────────
  // Batch all draw updates within a single frame into one callback.
  // This reduces repaint count from O(N) to O(1) per frame.
  final List<Offset> _batchPositions = [];
  final List<double> _batchPressures = [];
  final List<double> _batchTiltsX = [];
  final List<double> _batchTiltsY = [];
  bool _batchFlushScheduled = false;

  /// 🎯 REALISM FIX: Simula pressione realistica per dito from the speed
  /// - Stylus: uses real pressure (0.0-1.0 con variazione)
  /// - Finger: simulates pressure from movement speed
  ///   • Slow = more pressure (like pressing hard with real pen)
  ///   • Fast = less pressure (light and fast stroke)
  double _normalizePressure(PointerEvent event) {
    final rawPressure = event.pressure;

    // If is uno stylus, usa la pressure reale
    if (StylusDetector.isStylus(event)) {
      // Stylus ha valori graduali realistici
      return rawPressure.clamp(0.1, 1.0);
    }

    // For finger/touch: simula pressione from the speed
    // This creates a realistic effect dove:
    // - Slow movement → more ink deposited → high pressure
    // - Fast movement → less ink → low pressure

    if (_lastDrawPosition != null) {
      final distance = (event.localPosition - _lastDrawPosition!).distance;

      // Speed normalizzata: 0-30px = lento, 30+ = veloce
      // Invertiamo: distanza piccola = pressione alta
      // Range: 0.3 (veloce) a 0.9 (lento)
      const double maxDistance = 30.0; // Soglia "veloce"
      const double minPressure = 0.3; // Pressione minima (tratto veloce)
      const double maxPressure = 0.9; // Pressione massima (tratto lento)

      // Calculate pressione: more vicino = more pressione
      final normalizedDistance = (distance / maxDistance).clamp(0.0, 1.0);
      final simulatedPressure =
          maxPressure - (normalizedDistance * (maxPressure - minPressure));

      return simulatedPressure;
    }

    // Primo punto: usa pressione media
    return 0.6;
  }

  @override
  void didUpdateWidget(InfiniteCanvasGestureDetector oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 🖊️ Update stylus mode if changed
    if (oldWidget.isStylusModeEnabled != widget.isStylusModeEnabled) {
      _stylusManager.setStylusMode(widget.isStylusModeEnabled);
    }
  }

  @override
  void initState() {
    super.initState();
    // 🖊️ Initialize stylus manager
    _stylusManager.setStylusMode(widget.isStylusModeEnabled);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      // 🖊️ FEATURE 7: Track stylus hover for aggressive palm rejection
      onPointerHover: _onPointerHover,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        onLongPressStart: (details) {
          // Long press rilevato - converti coordinata schermo → canvas
          if (widget.onLongPress != null && _pointerCount == 1) {
            final canvasPoint = widget.controller.screenToCanvas(
              details.localPosition,
            );
            widget.onLongPress!(canvasPoint);
          }
        },
        child: widget.child,
      ),
    );
  }

  // 🖊️ AUTO-DETECT: Track first draw position for stroke direction
  Offset? _strokeStartPosition;

  // 🖊️ Stylus hover detection + cursor preview
  void _onPointerHover(PointerHoverEvent event) {
    if (StylusDetector.isStylus(event)) {
      HandednessSettings.instance.onStylusHover(event.localPosition);
      // 🖊️ Feed hover state for cursor preview overlay
      StylusHoverState.instance.updateHover(
        event.localPosition,
        distance: event.distance,
      );
    } else {
      HandednessSettings.instance.onStylusHoverExit();
      StylusHoverState.instance.endHover();
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    final isStylus = StylusDetector.isStylus(event);

    // 🖊️ STYLUS TRACKING: Inform HandednessSettings for temporal rejection
    if (isStylus) {
      HandednessSettings.instance.onStylusDown(event.localPosition);
      StylusHoverState.instance.endHover(); // Hide cursor on touch-down
    }

    // 🖐️ COMPREHENSIVE PALM REJECTION:
    // UI bypass + temporal + cooldown + hover + multi-point + velocity + area + wrist + zone
    // 🔧 FIX: Skip palm rejection when a pointer is already down — the incoming
    // touch is likely the 2nd finger for pinch-zoom/pan, NOT a palm. Rejecting
    // it would prevent _pointerCount from reaching 2, breaking zoom/pan.
    if (!isStylus && _pointerCount == 0) {
      final speed = event.delta.distance.clamp(0.0, 100.0);
      final screenSize = MediaQuery.sizeOf(context);

      // 🛡️ UI safe zone: top 60px (toolbar) + bottom 44px (nav bar)
      final uiSafeZone = Rect.fromLTRB(0, 0, screenSize.width, 60);

      if (HandednessSettings.instance.shouldRejectTouch(
        position: event.localPosition,
        radiusMajor: event.radiusMajor,
        radiusMinor: event.radiusMinor,
        screenSize: screenSize,
        speed: speed,
        uiSafeZone: uiSafeZone,
      )) {
        // Trigger auto-calibration periodically
        HandednessSettings.instance.triggerAutoCalibration(screenSize);
        return; // Palm touch — rejected
      }

      // 🐌 Begin drift tracking for deferred rejection
      HandednessSettings.instance.beginDriftTracking(
          event.pointer, event.localPosition);
    }

    _pointerCount++;
    _lastPointerChangeTime = DateTime.now().millisecondsSinceEpoch;

    // 🌊 LIQUID: Stop any running physics animation on new touch
    widget.controller.stopAnimation();

    // 🖊️ Register the pointer for stylus manager
    _stylusManager.addPointer(event);

    // 🖊️ Determines if drawing should be enabled based on stylus mode
    if (widget.isStylusModeEnabled) {
      // In stylus mode, abilita drawing SOLO con stylus
      _shouldEnableDrawing = StylusDetector.isStylus(event);
    } else {
      // In mode normale, abilita drawing with a dito
      _shouldEnableDrawing = _pointerCount == 1;
    }

    // Traccia se c'was multi-touch
    if (_pointerCount >= 2) {
      _wasMultiTouch = true;
    }

    // Save la position del primo dito
    if (_pointerCount == 1) {
      _firstPointerPosition = event.localPosition;
      _hasMoved = false;
    } else if (_pointerCount > 1) {
      // If arriva un secondo dito, invalida il tap
      _firstPointerPosition = null;
    }

    // If c'è more di un dito, CANCELLA il drawing (non salvare il puntino)
    if (_pointerCount > 1 && _isDrawing) {
      _isDrawing = false;
      // 🚫 Use onDrawCancel to discard in-progress stroke
      // invece di onDrawEnd che lo salverebbe come puntino
      if (widget.onDrawCancel != null) {
        widget.onDrawCancel!();
      }
    }

    // 🚀 FIX: Start drawing IMMEDIATELY on pointer down
    // This captures the first point without waiting for onPointerMove
    // Solves the problem of losing the first points during writing
    //
    // 📄 PAN INTERCEPT: When pan mode is active BUT touch hits a PDF page,
    // route to draw callbacks instead of canvas pan.
    bool shouldDraw = !widget.enableSingleFingerPan;
    if (widget.enableSingleFingerPan && widget.onPanInterceptTest != null) {
      final canvasPoint = widget.controller.screenToCanvas(event.localPosition);
      if (widget.onPanInterceptTest!(canvasPoint)) {
        shouldDraw = true;
        _panIntercepted = true; // Flag to route moves to draw, not pan
      }
    }
    if (_pointerCount == 1 && _shouldEnableDrawing && shouldDraw) {
      // 🎯 DOUBLE-TAP CHECK: If this could be the second tap of a double-tap,
      // suppress drawing to avoid the temporary dot flash.
      final now = DateTime.now().millisecondsSinceEpoch;
      final isLikelySecondTap =
          _pendingFirstTap &&
          (now - _lastSingleTapTime) < 300 &&
          (event.localPosition - _lastSingleTapPosition).distance < 40;

      _isDrawing = true;
      _lastDrawPosition = event.localPosition;
      final normalizedPressure = _normalizePressure(event);
      _lastPressure = normalizedPressure;

      // 🖊️ Calculate tiltX and tiltY from tilt and orientation
      final tiltMagnitude = event.tilt;
      final orientation = event.orientation;
      _lastTiltX = (tiltMagnitude * math.cos(orientation)).clamp(-1.0, 1.0);
      _lastTiltY = (tiltMagnitude * math.sin(orientation)).clamp(-1.0, 1.0);

      if (!isLikelySecondTap && widget.onDrawStart != null) {
        final canvasPoint = widget.controller.screenToCanvas(
          event.localPosition,
        );
        _lastCanvasPosition = canvasPoint;
        _strokeStartPosition = canvasPoint; // 📊 AUTO-DETECT: record stroke start
        widget.onDrawStart!(
          canvasPoint,
          normalizedPressure,
          _lastTiltX,
          _lastTiltY,
        );
      }
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    // 🖊️ Update pointer for stylus manager
    _stylusManager.updatePointer(event);

    // 🖊️ STYLUS TRACKING: Update pen position for wrist guard
    if (StylusDetector.isStylus(event)) {
      HandednessSettings.instance.onStylusMove(event.localPosition);
    } else {
      // 📊 DEFERRED REJECTION: Pressure curve + drift analysis for non-stylus
      // These catch palms that passed the initial shouldRejectTouch check.
      final settings = HandednessSettings.instance;
      if (settings.recordPressureSample(event.pointer, event.pressure)) {
        // Flat pressure curve detected — cancel this touch
        settings.recordDeferredRejection(
            event.localPosition, PalmRejectionReason.pressureCurve,
            event.radiusMajor);
        return; // Swallow further move events for this palm
      }
      if (settings.checkDrift(
          event.pointer, event.localPosition, event.radiusMajor)) {
        settings.recordDeferredRejection(
            event.localPosition, PalmRejectionReason.drift,
            event.radiusMajor);
        return; // Near-zero movement — likely palm resting
      }
    }

    // Ignora se ci sono 2+ dita (zoom/pan)
    if (_pointerCount >= 2) return;

    // 🔄 GESTURE CONTINUITY: Don't draw/pan right after multi-touch
    // Extended cooldown prevents accidental strokes when lifting fingers.
    final timeSinceLastChange =
        DateTime.now().millisecondsSinceEpoch - _lastPointerChangeTime;
    if (_wasMultiTouch && timeSinceLastChange < 60) {
      // Re-anchor positions so first move after cooldown doesn't jump
      _lastPanPosition = event.localPosition;
      _lastDrawPosition = event.localPosition;
      return; // Ignore movement during cooldown
    }

    // 🖐️ If finger pan mode is active, pan instead of drawing
    // 📄 But NOT if pan was intercepted (e.g. PDF document drag)
    if (_pointerCount == 1 &&
        widget.enableSingleFingerPan &&
        !_panIntercepted) {
      if (!_isSingleFingerPanning) {
        _isSingleFingerPanning = true;
        widget.controller.isPanning = true; // 🚀 SCROLL OPT
        _lastPanPosition = event.localPosition;
        // 🌊 LIQUID: Reset velocity tracking for single-finger pan
        _lastScaleUpdateTime = DateTime.now().microsecondsSinceEpoch;
        _panVelocity = Offset.zero;
      } else {
        // Calculate il delta di movimento
        final delta = event.localPosition - _lastPanPosition;

        // 🌊 LIQUID: Track velocity
        final now = DateTime.now().microsecondsSinceEpoch;
        final dt = (now - _lastScaleUpdateTime) / 1000000.0;
        if (dt > 0.001) {
          final instantV = delta / dt;
          _panVelocity = Offset(
            _panVelocity.dx * 0.7 + instantV.dx * 0.3,
            _panVelocity.dy * 0.7 + instantV.dy * 0.3,
          );
        }
        _lastScaleUpdateTime = now;
        _lastPanPosition = event.localPosition;

        // Applica il pan
        final newOffset = widget.controller.offset + delta;
        widget.controller.updateTransform(
          offset: newOffset,
          scale: widget.controller.scale,
        );
      }
      return;
    }

    // 🖊️ STYLUS MODE: in stylus mode, finger pans instead of drawing
    if (widget.isStylusModeEnabled &&
        _pointerCount == 1 &&
        !_shouldEnableDrawing) {
      // È un dito in stylus mode → fai pan
      if (!_isSingleFingerPanning) {
        _isSingleFingerPanning = true;
        widget.controller.isPanning = true; // 🚀 SCROLL OPT
        _lastPanPosition = event.localPosition;
        // 🌊 LIQUID: Reset velocity tracking
        _lastScaleUpdateTime = DateTime.now().microsecondsSinceEpoch;
        _panVelocity = Offset.zero;
      } else {
        final delta = event.localPosition - _lastPanPosition;

        // 🌊 LIQUID: Track velocity
        final now = DateTime.now().microsecondsSinceEpoch;
        final dt = (now - _lastScaleUpdateTime) / 1000000.0;
        if (dt > 0.001) {
          final instantV = delta / dt;
          _panVelocity = Offset(
            _panVelocity.dx * 0.7 + instantV.dx * 0.3,
            _panVelocity.dy * 0.7 + instantV.dy * 0.3,
          );
        }
        _lastScaleUpdateTime = now;
        _lastPanPosition = event.localPosition;

        final newOffset = widget.controller.offset + delta;
        widget.controller.updateTransform(
          offset: newOffset,
          scale: widget.controller.scale,
        );
      }
      return;
    }

    // Drawing only with 1 finger (when pan mode is not active AND stylus mode allows)
    if (_pointerCount == 1 && _shouldEnableDrawing) {
      _hasMoved = true;

      // 🖊️ In stylus mode, verify we are still drawing with the stylus
      if (widget.isStylusModeEnabled &&
          !_stylusManager.canDrawWithCurrentPointer()) {
        // If is not more una stylus, termina il disegno
        if (_isDrawing && widget.onDrawEnd != null) {
          final canvasPoint = widget.controller.screenToCanvas(
            event.localPosition,
          );
          widget.onDrawEnd!(canvasPoint);
          _isDrawing = false;
        }
        return;
      }

      // 🚀 FIX: Removed block "if (!_isDrawing)" which called onDrawStart
      // onDrawStart ora is called in onPointerDown per catturare il primo punto
      // Qui gestiamo SOLO gli update of the drawing already iniziato
      if (_isDrawing) {
        final canvasPoint = widget.controller.screenToCanvas(
          event.localPosition,
        );

        final normalizedPressure = _normalizePressure(event); // 🎯 FIX 3

        // 🖊️ FIX: Calculate current tiltX and tiltY
        final tiltMagnitude = event.tilt;
        final orientation = event.orientation;
        final currentTiltX = (tiltMagnitude * math.cos(orientation)).clamp(
          -1.0,
          1.0,
        );
        final currentTiltY = (tiltMagnitude * math.sin(orientation)).clamp(
          -1.0,
          1.0,
        );

        // 🚀 FIX #5: INTERPOLATION IN CANVAS SPACE
        // Instead of converting each interpolated point with screenToCanvas(),
        // we interpolate directly between cached canvas positions.
        if (_lastCanvasPosition != null) {
          final distance = (event.localPosition - _lastDrawPosition!).distance;
          if (distance > _interpolationThreshold) {
            final rawSteps = (distance / _interpolationThreshold).ceil();
            final steps = rawSteps.clamp(
              1,
              _maxInterpolatedPoints + 1,
            ); // Limit points

            for (int i = 1; i < steps; i++) {
              final t = i / steps;
              // 🚀 Direct interpolation in canvas space (zero screenToCanvas!)
              final interpolatedCanvas =
                  Offset.lerp(_lastCanvasPosition!, canvasPoint, t)!;
              final interpolatedPressure =
                  _lastPressure + (normalizedPressure - _lastPressure) * t;
              final interpolatedTiltX =
                  _lastTiltX + (currentTiltX - _lastTiltX) * t;
              final interpolatedTiltY =
                  _lastTiltY + (currentTiltY - _lastTiltY) * t;

              // 🚀 COALESCED: Buffer point instead of dispatching immediately
              _addToBatch(
                interpolatedCanvas,
                interpolatedPressure,
                interpolatedTiltX,
                interpolatedTiltY,
              );
            }
          }
        }

        _lastDrawPosition = event.localPosition;
        _lastCanvasPosition =
            canvasPoint; // 🚀 FIX #5: cache for next interpolation
        _lastPressure = normalizedPressure;
        _lastTiltX = currentTiltX;
        _lastTiltY = currentTiltY;

        // 🚀 COALESCED: Buffer the real point and schedule batch flush
        _addToBatch(
          canvasPoint,
          normalizedPressure,
          currentTiltX,
          currentTiltY,
        );
        _scheduleBatchFlush();
      }
    }
  }

  // ─── 🚀 GESTURE COALESCING HELPERS ─────────────────────────────────

  /// Add a draw point to the intra-frame batch buffer.
  void _addToBatch(
    Offset position,
    double pressure,
    double tiltX,
    double tiltY,
  ) {
    _batchPositions.add(position);
    _batchPressures.add(pressure);
    _batchTiltsX.add(tiltX);
    _batchTiltsY.add(tiltY);
  }

  /// Schedule a single post-frame callback to flush all buffered points.
  /// Idempotent — only schedules once per frame.
  void _scheduleBatchFlush() {
    if (_batchFlushScheduled) return;
    _batchFlushScheduled = true;

    SchedulerBinding.instance.addPostFrameCallback((_) {
      _flushBatch();
    });
  }

  /// Flush the batch: dispatch all buffered points in one call.
  void _flushBatch() {
    _batchFlushScheduled = false;
    if (_batchPositions.isEmpty) return;

    if (_batchPositions.length == 1) {
      // Single point — use the standard callback
      widget.onDrawUpdate?.call(
        _batchPositions[0],
        _batchPressures[0],
        _batchTiltsX[0],
        _batchTiltsY[0],
      );
    } else if (widget.onDrawBatchUpdate != null) {
      // 🚀 Batch callback (N points → 1 repaint)
      widget.onDrawBatchUpdate!(
        List<Offset>.from(_batchPositions),
        List<double>.from(_batchPressures),
        List<double>.from(_batchTiltsX),
        List<double>.from(_batchTiltsY),
      );
    } else {
      // Fallback: dispatch individually (last point only triggers repaint)
      for (int i = 0; i < _batchPositions.length; i++) {
        widget.onDrawUpdate?.call(
          _batchPositions[i],
          _batchPressures[i],
          _batchTiltsX[i],
          _batchTiltsY[i],
        );
      }
    }

    _batchPositions.clear();
    _batchPressures.clear();
    _batchTiltsX.clear();
    _batchTiltsY.clear();
  }

  void _onPointerUp(PointerUpEvent event) {
    // 🚀 COALESCING: Flush any pending batch before finalizing the stroke.
    // This ensures that all buffered points are dispatched before onDrawEnd.
    _flushBatch();

    // 🖊️ STYLUS TRACKING: Inform HandednessSettings stylus is up
    if (StylusDetector.isStylus(event)) {
      HandednessSettings.instance.onStylusUp();
    } else {
      // 🧹 Clean up pressure/drift tracking for this pointer
      HandednessSettings.instance.clearPointerTracking(event.pointer);
    }

    _previousPointerCount = _pointerCount;
    _pointerCount--;
    _lastPointerChangeTime = DateTime.now().millisecondsSinceEpoch;

    // 🔄 GESTURE CONTINUITY: When transitioning between pointer counts
    // (e.g., 2→1 fingers), re-anchor to current state to prevent jumps.
    if (_previousPointerCount >= 2 && _pointerCount >= 1) {
      _gestureTransitioning = true;
    }

    // 🖊️ Remove the pointer from stylus manager
    _stylusManager.removePointer(event.pointer);

    // Only se siamo all'ultimo dito e stiamo disegnando
    if (_pointerCount == 0) {
      // Reset multi-touch flag when all fingers are lifted
      _wasMultiTouch = false;
      _gestureTransitioning = false; // Reset stale transition flag

      // 🌊 LIQUID: Launch momentum from single-finger pan
      if (_isSingleFingerPanning && _panVelocity.distance > 0) {
        widget.controller.startMomentum(_panVelocity);
        _panVelocity = Offset.zero;
      }

      _isSingleFingerPanning = false; // 🖐️ Reset pan with a finger
      widget.controller.isPanning = false; // 🚀 SCROLL OPT
      _panIntercepted = false; // 📄 Reset pan intercept
      _shouldEnableDrawing = true; // 🖊️ Reset stylus drawing flag

      if (_isDrawing && _hasMoved) {
        // Drawing with movement — finalize stroke
        _isDrawing = false;
        _wasDrawingGesture = true; // 🎯 FIX: Flag for _onScaleEnd
        if (widget.onDrawEnd != null) {
          final canvasPoint = widget.controller.screenToCanvas(
            event.localPosition,
          );
          widget.onDrawEnd!(canvasPoint);

          // 📊 AUTO-DETECT: Record stroke direction for handedness inference
          if (_strokeStartPosition != null) {
            final deltaX = canvasPoint.dx - _strokeStartPosition!.dx;
            HandednessSettings.instance.recordStrokeDirection(deltaX);
            _strokeStartPosition = null;
          }
        }
        // Drawing stroke resets double-tap state
        _pendingFirstTap = false;
        _lastSingleTapTime = 0;
      } else if (!_hasMoved && !_wasMultiTouch) {
        // 🎯 Quick tap (no movement, single finger) — double-tap zoom check
        final wasDrawing = _isDrawing;
        _isDrawing = false;

        final now = DateTime.now().millisecondsSinceEpoch;
        final timeSinceLastTap = now - _lastSingleTapTime;
        final distFromLastTap =
            (event.localPosition - _lastSingleTapPosition).distance;

        if (timeSinceLastTap < 300 &&
            distFromLastTap < 40 &&
            _pendingFirstTap) {
          // 🎯 DOUBLE-TAP DETECTED!
          _pendingFirstTap = false;
          _lastSingleTapTime = 0;

          // Cancel any in-progress stroke from this (second) tap
          if (wasDrawing) {
            widget.onDrawCancel?.call();
          }

          HapticFeedback.mediumImpact();

          // Discrete zoom levels: 1x → 2x → 3x → back to 1x
          final currentScale = widget.controller.scale;
          double targetScale;
          if (currentScale < 1.8) {
            targetScale = 2.0;
          } else if (currentScale < 2.8) {
            targetScale = 3.0;
          } else {
            targetScale = 1.0;
          }
          widget.controller.animateZoomTo(targetScale, event.localPosition);

          // Discard the first tap's dot silently (if drawing mode created one)
          widget.onDoubleTapZoom?.call();
        } else {
          // First tap — record timing for double-tap detection
          _pendingFirstTap = true;
          _lastSingleTapTime = now;
          _lastSingleTapPosition = event.localPosition;

          // In drawing mode, finalize the dot
          if (wasDrawing) {
            _wasDrawingGesture = true; // 🎯 FIX: Flag for _onScaleEnd
            if (widget.onDrawEnd != null) {
              final canvasPoint = widget.controller.screenToCanvas(
                event.localPosition,
              );
              widget.onDrawEnd!(canvasPoint);
            }
          }
        }
      } else {
        // Multi-touch or other — just clean up
        _isDrawing = false;
        _pendingFirstTap = false;
        _lastSingleTapTime = 0;
        // 📈 Call onDrawEnd to clean up any active drag state (graph, latex, etc.)
        // that was cancelled by multi-touch but never finalized.
        if (widget.onDrawEnd != null) {
          final canvasPoint = widget.controller.screenToCanvas(
            event.localPosition,
          );
          widget.onDrawEnd!(canvasPoint);
        }
      }

      // Reset state
      _firstPointerPosition = null;
      _hasMoved = false;
      _lastDrawPosition = null; // 🚀 Reset interpolation
      _lastCanvasPosition = null; // 🚀 FIX #5: Reset canvas cache
      _lastPressure = 1.0;
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _flushBatch(); // 🚀 COALESCING: Flush pending points
    _pointerCount--;
    _lastPointerChangeTime = DateTime.now().millisecondsSinceEpoch;

    // 🖊️ Remove the pointer from stylus manager
    _stylusManager.removePointer(event.pointer);

    if (_isDrawing) {
      _isDrawing = false;
      if (widget.onDrawEnd != null) {
        final canvasPoint = widget.controller.screenToCanvas(
          event.localPosition,
        );
        widget.onDrawEnd!(canvasPoint);
      }
    }

    // Reset state
    if (_pointerCount == 0) {
      _wasMultiTouch = false;
      _isSingleFingerPanning = false; // 🖐️ Reset pan with a finger
      _panIntercepted = false; // 📄 Reset pan intercept
      _shouldEnableDrawing = true; // 🖊️ Reset stylus drawing flag
      _firstPointerPosition = null;
      _hasMoved = false;
    }
  }

  // 🌀 Two-finger double-tap detection (reset view)
  int _lastTwoFingerTapTime = 0;
  Offset _lastTwoFingerTapPosition = Offset.zero;

  void _onScaleStart(ScaleStartDetails details) {
    // 🔒 Block pan/zoom when an interactive element is being manipulated
    if (widget.blockPanZoom()) return;
    // 🔄 GESTURE CONTINUITY: When transitioning between pointer counts
    // (e.g., 2→1 fingers), re-anchor to current state to prevent jumps.
    if (_gestureTransitioning) {
      _gestureTransitioning = false;
      _initialScale = widget.controller.scale;
      _initialFocalPoint = details.localFocalPoint;
      _initialOffset = widget.controller.offset;
      _initialRotation = widget.controller.rotation;
      _lastGestureRotation = 0.0;
      _lastScaleFocalPoint = details.localFocalPoint;
      _lastScaleUpdateTime = DateTime.now().microsecondsSinceEpoch;
      // Keep existing velocity for smooth momentum handoff
      _wasZooming = false;
      return; // Skip all other initialization — seamless transition
    }

    _initialScale = widget.controller.scale;
    _initialFocalPoint = details.localFocalPoint;
    _initialOffset = widget.controller.offset;
    _initialRotation = widget.controller.rotation;
    _lastGestureRotation = 0.0;
    _rotationUnlocked = false; // Reset deadzone for new gesture

    // 🌀 TWO-FINGER DOUBLE-TAP: Detect rapid 2-finger taps to reset view
    if (_pointerCount >= 2) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final timeSinceLastTap = now - _lastTwoFingerTapTime;
      final distFromLastTap =
          (details.localFocalPoint - _lastTwoFingerTapPosition).distance;

      if (timeSinceLastTap < 400 && distFromLastTap < 80) {
        // Double-tap detected! Reset rotation + zoom
        HapticFeedback.mediumImpact();
        widget.controller.resetRotation();
        widget.controller.startZoomSpringBack(details.localFocalPoint);
        _lastTwoFingerTapTime = 0; // Reset to avoid triple-tap
        return;
      }

      _lastTwoFingerTapTime = now;
      _lastTwoFingerTapPosition = details.localFocalPoint;
    }

    // 🌊 LIQUID: Initialize velocity tracking
    _lastScaleFocalPoint = details.localFocalPoint;
    _lastScaleUpdateTime = DateTime.now().microsecondsSinceEpoch;
    _panVelocity = Offset.zero;
    _rotationVelocity = 0.0;
    _wasZooming = false;
    _zoomVelocity = 0.0;
    _lastGestureScale = widget.controller.scale;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    // 🔒 Block canvas pan/zoom; route scale+pan to graph viewport instead
    if (widget.blockPanZoom()) {
      if (_pointerCount >= 2) {
        final delta = details.localFocalPoint - _lastScaleFocalPoint;
        widget.onBlockedScale?.call(details.scale, delta);
        _lastScaleFocalPoint = details.localFocalPoint;
      }
      return;
    }
    // Only process with 2+ fingers
    if (_pointerCount < 2) return;
    widget.controller.isPanning = true; // 🚀 SCROLL OPT

    // 🌀 IMAGE ROTATION: When image callbacks are wired (pan mode + selected image),
    // route rotation + scale to the image instead of the canvas.
    if (widget.onImageScaleStart != null) {
      // Fire start callback once
      if (!_imageScaleStarted) {
        _imageScaleStarted = true;
        _imageRotationAccum = 0.0;
        _imageRotationUnlocked = false;
        _imageLastSnappedAngle = null;
        _imageInitialScale = details.scale;
        widget.onImageScaleStart?.call();
      }

      // 🧲 MAGNETIC SNAP: Snap to 0°/45°/90°/180°/270° with haptic
      double rotation = 0.0;
      if (_imageRotationUnlocked ||
          details.rotation.abs() > _rotationDeadzone) {
        _imageRotationUnlocked = true;
        rotation = details.rotation;

        // Check snap angles (every 45° = π/4 radians)
        const snapInterval = 0.7853981633974483; // π/4 = 45°
        const snapThreshold = 0.12; // ~7° magnetic zone
        final nearestSnap = (rotation / snapInterval).round() * snapInterval;
        final distFromSnap = (rotation - nearestSnap).abs();
        if (distFromSnap < snapThreshold) {
          // Cubic dampening for magnetic feel
          final t = (distFromSnap / snapThreshold).clamp(0.0, 1.0);
          final dampening = t * t * t;
          rotation = nearestSnap + (rotation - nearestSnap) * dampening;

          // Haptic at snap crossing
          if (_imageLastSnappedAngle != nearestSnap) {
            HapticFeedback.lightImpact();
            _imageLastSnappedAngle = nearestSnap;
          }
        } else {
          _imageLastSnappedAngle = null;
        }
      }

      // 🤏 Simultaneous scale: ratio relative to gesture start
      final scaleRatio = details.scale / _imageInitialScale;

      widget.onImageTransform?.call(rotation, scaleRatio);
      return;
    }

    // 🌊 LIQUID: Track velocity for momentum
    final now = DateTime.now().microsecondsSinceEpoch;
    final dt = (now - _lastScaleUpdateTime) / 1000000.0; // seconds
    if (dt > 0.001) {
      final delta = details.localFocalPoint - _lastScaleFocalPoint;
      final instantVelocity = delta / dt;
      // Exponential smoothing (α = 0.3) for stable velocity
      _panVelocity = Offset(
        _panVelocity.dx * 0.7 + instantVelocity.dx * 0.3,
        _panVelocity.dy * 0.7 + instantVelocity.dy * 0.3,
      );
    }
    _lastScaleFocalPoint = details.localFocalPoint;
    _lastScaleUpdateTime = now;

    // Detect if user is zooming (scale significantly changed)
    // 🎯 FIX: Raised threshold from 0.02 to 0.10 to prevent 2-finger pan
    // from being misidentified as zoom (finger spread fluctuates ~2-5%).
    if ((details.scale - 1.0).abs() > 0.10) {
      _wasZooming = true;
    }

    // 🌊 LIQUID: Track zoom velocity (Gap 4)
    // Scale velocity = Δscale / Δtime (in scale-units per second)
    if (dt > 0.001) {
      final currentScale = _initialScale * details.scale;
      final scaleDelta = currentScale - _lastGestureScale;
      final instantZoomV = scaleDelta / dt;
      _zoomVelocity = _zoomVelocity * 0.6 + instantZoomV * 0.4;
      _lastGestureScale = currentScale;
    }

    // 🌊 LIQUID: Allow elastic overshoot for zoom (raw, unclamped scale)
    final rawScale = _initialScale * details.scale;

    // 🌀 ROTATION: Track rotation from gesture with deadzone.
    // Rotation is suppressed until the user exceeds ~3° to prevent
    // accidental rotation during fast zoom/pan gestures.
    double newRotation;
    if (_rotationUnlocked || details.rotation.abs() > _rotationDeadzone) {
      _rotationUnlocked = true;
      newRotation = _initialRotation + details.rotation;
    } else {
      newRotation = _initialRotation; // Keep locked until deadzone exceeded
    }

    // 🌀 MAGNETIC SNAP: Add resistance near snap angles (like Procreate)
    // When close to a snap angle, dampen the rotation delta to create
    // a "sticky" feel. The user must push harder to break free.
    final snapAngle = widget.controller.checkSnapAngle(newRotation);
    if (snapAngle != null && !widget.controller.rotationLocked) {
      final distFromSnap = (newRotation - snapAngle).abs();
      final snapThreshold = 0.18; // ~10° magnetic zone (wide detent)
      // Cubic dampening: very strong near center, fades at edges
      final t = (distFromSnap / snapThreshold).clamp(0.0, 1.0);
      final dampening = t * t * t; // 0 at center, 1 at edge
      newRotation = snapAngle + (newRotation - snapAngle) * dampening;
    }

    // 🌀 ROTATION: Track angular velocity
    final rotationDelta = details.rotation - _lastGestureRotation;
    _lastGestureRotation = details.rotation;
    if (dt > 0.001) {
      final instantAngularV = (rotationDelta / dt).clamp(
        -_maxAngularVelocity,
        _maxAngularVelocity,
      );
      _rotationVelocity = _rotationVelocity * 0.7 + instantAngularV * 0.3;
    }

    // Calculate il delta di pan dat the point iniziale
    final panDelta = details.localFocalPoint - _initialFocalPoint;

    // 🎯 FIX: Use the ACTUAL rotation/scale that will be applied, not raw values.
    // When rotation is locked, the controller ignores newRotation.
    // When elastic clamping is active, the applied scale differs from rawScale.
    final effectiveRotation =
        widget.controller.rotationLocked ? _initialRotation : newRotation;

    // Calculate offset considering zoom + pan + rotation
    // Convert focal point from screen → canvas using initial transform
    // (undo translate → undo rotate → undo scale)
    final translated = _initialFocalPoint - _initialOffset;
    final cosR0 = math.cos(-_initialRotation);
    final sinR0 = math.sin(-_initialRotation);
    final unrotated = Offset(
      translated.dx * cosR0 - translated.dy * sinR0,
      translated.dx * sinR0 + translated.dy * cosR0,
    );
    final focalPointCanvas = unrotated / _initialScale;

    // Apply new transform: scale → rotate → translate
    // Use getEffectiveScale (elastic) so offset and _scale stay consistent.
    // The elastic cap in _applyElasticClamp ensures the overshoot is tiny,
    // preventing noticeable viewport drift at large canvas positions.
    final effectiveScale = widget.controller.getEffectiveScale(rawScale);
    final cosR = math.cos(effectiveRotation);
    final sinR = math.sin(effectiveRotation);
    final scaledFocal = Offset(
      focalPointCanvas.dx * effectiveScale,
      focalPointCanvas.dy * effectiveScale,
    );
    final rotatedFocal = Offset(
      scaledFocal.dx * cosR - scaledFocal.dy * sinR,
      scaledFocal.dx * sinR + scaledFocal.dy * cosR,
    );
    final newOffset = _initialFocalPoint - rotatedFocal + panDelta;

    // 🌊 LIQUID: Apply transform with elastic bounds + rotation
    widget.controller.updateTransform(
      offset: newOffset,
      scale: rawScale,
      rotation: newRotation,
      elastic: true,
    );

    // 🌀 SNAP HAPTIC: Fire haptic when crossing a snap angle detent
    if (!widget.controller.rotationLocked) {
      final snapAngle = widget.controller.checkSnapAngle(newRotation);
      if (snapAngle != null && snapAngle != _lastSnappedAngle) {
        HapticFeedback.lightImpact();
        _lastSnappedAngle = snapAngle;
      } else if (snapAngle == null) {
        _lastSnappedAngle = null;
      }
    }

    _lastScaleEndFocalPoint = details.localFocalPoint;
  }

  void _onScaleEnd(ScaleEndDetails details) {
    // 🔒 Block momentum/spring-back when an interactive element is being manipulated
    if (widget.blockPanZoom()) return;
    // 🎯 FIX: If this scale-end follows a drawing gesture, skip ALL viewport
    // animations (spring-back, momentum, rotation). The GestureDetector fires
    // onScaleEnd after every gesture — including single-finger drawing.
    // Without this guard, startZoomSpringBack shifts the viewport on finger-up
    // when zoom is beyond elastic limits, causing the committed stroke to jump.
    final wasDrawing = _wasDrawingGesture;
    _wasDrawingGesture = false;
    if (wasDrawing) {
      _panVelocity = Offset.zero;
      _rotationVelocity = 0.0;
      _wasZooming = false;
      _lastGestureScale = 1.0;
      widget.controller.isPanning = false;
      widget.controller.markNeedsPaint();
      return;
    }

    // 🌀 IMAGE ROTATION: End image rotation if active
    final wasImageScaling = _imageScaleStarted;
    if (_imageScaleStarted) {
      _imageScaleStarted = false;
      _imageRotationUnlocked = false;
      _imageRotationAccum = 0.0;
      _imageLastSnappedAngle = null;
      widget.onImageScaleEnd?.call();
    }

    // If we were handling image gestures (rotation/scale),
    // skip canvas momentum to avoid conflicting animations.
    if (wasImageScaling) return;

    // 🌊 LIQUID: Launch zoom spring-back if scale is beyond limits
    widget.controller.startZoomSpringBack(_lastScaleEndFocalPoint);

    // 🌊 LIQUID: Launch zoom momentum if user was actively zooming (Gap 4)
    // 🎯 FIX: Raised velocity threshold and made mutually exclusive with
    // pan momentum — both write to _offset in the ticker and conflict.
    bool zoomMomentumLaunched = false;
    if (_wasZooming && _zoomVelocity.abs() > 0.5) {
      widget.controller.startZoomMomentum(
        _zoomVelocity,
        _lastScaleEndFocalPoint,
      );
      zoomMomentumLaunched = true;
    }

    // 🌊 LIQUID: Launch pan momentum from terminal velocity
    // 🎯 FIX: Skip if ANY zoom animation is active (spring-back or momentum).
    // Pan velocity from a zoom gesture is the centroid of diverging fingers,
    // not a meaningful pan direction — applying it causes viewport to fly off.
    if (!widget.controller.isAnimating && _panVelocity.distance > 0) {
      widget.controller.startMomentum(_panVelocity);
    }

    // 🌀 ROTATION: Launch rotation momentum
    widget.controller.startRotationMomentum(_rotationVelocity);

    _panVelocity = Offset.zero;
    _rotationVelocity = 0.0;
    _wasZooming = false;
    _lastGestureScale = 1.0;
    // 🚀 SCROLL OPT: Clear flag (momentum getter handles _isMomentumActive)
    widget.controller.isPanning = false;
    widget.controller
        .markNeedsPaint(); // 🚀 Final repaint with isPanning=false → annotations reappear
  }
}
