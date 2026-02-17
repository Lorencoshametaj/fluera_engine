import 'dart:math' as math;
import 'package:flutter/material.dart';
import './infinite_canvas_controller.dart';
import '../drawing/input/stylus_detector.dart';

/// Widget canvas infinito con zoom e pan
///
/// Supporta:
/// - Pinch zoom (due dita)
/// - Pan (two fingers to move)
/// - Drawing (one finger)
/// - Pan with a dito (se enableSingleFingerPan = true)
/// - 🖊️ Stylus Mode: stylus draws, finger pans
class InfiniteCanvasGestureDetector extends StatefulWidget {
  final InfiniteCanvasController controller;
  final Widget child;
  final Function(Offset, double pressure, double tiltX, double tiltY)?
  onDrawStart;
  final Function(Offset, double pressure, double tiltX, double tiltY)?
  onDrawUpdate;
  final Function(Offset)? onDrawEnd;
  final VoidCallback?
  onDrawCancel; // 🚫 Clear stroke without salvare (es. 2° dito interrompe)
  final Function(Offset)? onLongPress;
  final bool blockPanZoom; // 🔒 Block pan/zoom when true
  final bool
  enableSingleFingerPan; // 🖐️ Enable pan with a finger instead of drawing
  final bool
  isStylusModeEnabled; // 🖊️ Stylus mode: stylus draws, finger pans

  const InfiniteCanvasGestureDetector({
    super.key,
    required this.controller,
    required this.child,
    this.onDrawStart,
    this.onDrawUpdate,
    this.onDrawEnd,
    this.onDrawCancel,
    this.onLongPress,
    this.blockPanZoom = false, // Default: pan/zoom enabled
    this.enableSingleFingerPan = false, // Default: disegno with a dito
    this.isStylusModeEnabled = false, // Default: stylus mode disabled
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
  Offset? _firstPointerPosition;
  bool _hasMoved = false;
  bool _wasMultiTouch =
      false; // Flag to track se c'era multi-touch recente
  int _lastPointerChangeTime = 0; // Timestamp ultimo cambio pointer count

  // State per pan with a dito
  bool _isSingleFingerPanning = false;
  Offset _lastPanPosition = Offset.zero;

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

  void _onPointerDown(PointerDownEvent event) {
    _pointerCount++;
    _lastPointerChangeTime = DateTime.now().millisecondsSinceEpoch;

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
    // This cattura il primo punto without aspettare onPointerMove
    // Risolve il problema della perdita dei primi punti durante la scrittura
    if (_pointerCount == 1 &&
        _shouldEnableDrawing &&
        !widget.enableSingleFingerPan) {
      _isDrawing = true;
      _lastDrawPosition = event.localPosition;
      final normalizedPressure = _normalizePressure(event); // 🎯 FIX 3
      _lastPressure = normalizedPressure;

      // 🖊️ FIX: Calculate tiltX and tiltY from tilt and orientation
      final tiltMagnitude = event.tilt; // 0 to π/2
      final orientation = event.orientation; // -π to π
      _lastTiltX = (tiltMagnitude * math.cos(orientation)).clamp(-1.0, 1.0);
      _lastTiltY = (tiltMagnitude * math.sin(orientation)).clamp(-1.0, 1.0);

      if (widget.onDrawStart != null) {
        final canvasPoint = widget.controller.screenToCanvas(
          event.localPosition,
        );
        _lastCanvasPosition = canvasPoint; // 🚀 FIX #5: cache canvas position
        widget.onDrawStart!(
          canvasPoint,
          normalizedPressure, // 🎯 Usa pressure normalizzata
          _lastTiltX,
          _lastTiltY,
        );
      }
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    // 🖊️ Update pointer for stylus manager
    _stylusManager.updatePointer(event);

    // Ignora se ci sono 2+ dita (zoom/pan)
    if (_pointerCount >= 2) return;

    // NON disegnare se c'era multi-touch negli ultimi 60ms
    // Ridotto da 200ms per minimizzare input persi dopo zoom
    final timeSinceLastChange =
        DateTime.now().millisecondsSinceEpoch - _lastPointerChangeTime;
    if (_wasMultiTouch && timeSinceLastChange < 60) {
      return; // Ignora il movimento
    }

    // 🖐️ If finger pan mode is active, pan instead of drawing
    if (_pointerCount == 1 && widget.enableSingleFingerPan) {
      if (!_isSingleFingerPanning) {
        _isSingleFingerPanning = true;
        _lastPanPosition = event.localPosition;
      } else {
        // Calculate il delta di movimento
        final delta = event.localPosition - _lastPanPosition;
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
        _lastPanPosition = event.localPosition;
      } else {
        final delta = event.localPosition - _lastPanPosition;
        _lastPanPosition = event.localPosition;
        final newOffset = widget.controller.offset + delta;
        widget.controller.updateTransform(
          offset: newOffset,
          scale: widget.controller.scale,
        );
      }
      return;
    }

    // Drawing solo con 1 dito (quando pan mode is not attivo E stylus mode permette)
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
      if (_isDrawing && widget.onDrawUpdate != null) {
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
        // Invece di convertire ogni punto interpolato con screenToCanvas(),
        // interpoliamo direttamente among the posizioni canvas already calcolate.
        if (_lastCanvasPosition != null) {
          final distance = (event.localPosition - _lastDrawPosition!).distance;
          if (distance > _interpolationThreshold) {
            final rawSteps = (distance / _interpolationThreshold).ceil();
            final steps = rawSteps.clamp(
              1,
              _maxInterpolatedPoints + 1,
            ); // Limita punti
            for (int i = 1; i < steps; i++) {
              final t = i / steps;
              // 🚀 Direct interpolation in canvas space (zero screenToCanvas!)
              final interpolatedCanvas =
                  Offset.lerp(_lastCanvasPosition!, canvasPoint, t)!;
              final interpolatedPressure =
                  _lastPressure + (normalizedPressure - _lastPressure) * t;
              // 🖊️ Interpola anthat the tilt
              final interpolatedTiltX =
                  _lastTiltX + (currentTiltX - _lastTiltX) * t;
              final interpolatedTiltY =
                  _lastTiltY + (currentTiltY - _lastTiltY) * t;
              widget.onDrawUpdate!(
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
        widget.onDrawUpdate!(
          canvasPoint,
          normalizedPressure, // 🎯 Usa pressure normalizzata
          currentTiltX,
          currentTiltY,
        );
      }
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _pointerCount--;
    _lastPointerChangeTime = DateTime.now().millisecondsSinceEpoch;

    // 🖊️ Remove the pointer from stylus manager
    _stylusManager.removePointer(event.pointer);

    // Only se siamo all'ultimo dito e stiamo disegnando
    if (_pointerCount == 0) {
      // Reset flag multi-touch quando tutti i diti sono sollevati
      _wasMultiTouch = false;
      _isSingleFingerPanning = false; // 🖐️ Reset pan with a finger
      _shouldEnableDrawing = true; // 🖊️ Reset stylus drawing flag

      if (_isDrawing) {
        // Drawing normale (con movimento)
        _isDrawing = false;
        if (widget.onDrawEnd != null) {
          final canvasPoint = widget.controller.screenToCanvas(
            event.localPosition,
          );
          widget.onDrawEnd!(canvasPoint);
        }
      } else if (!_hasMoved &&
          _firstPointerPosition != null &&
          !widget.enableSingleFingerPan &&
          _shouldEnableDrawing) {
        // Tap veloce (nessun movimento) → disegna un puntino
        // Ma SOLO if not siamo in mode pan (altrimenti il tap non fa nulla)
        // 🖊️ AND ONLY if drawing was enabled (stylus in stylus mode)
        final canvasPoint = widget.controller.screenToCanvas(
          _firstPointerPosition!,
        );

        // Simula start + end nello stesso punto (tap veloce, no tilt)
        if (widget.onDrawStart != null) {
          widget.onDrawStart!(canvasPoint, 1.0, 0.0, 0.0);
        }
        if (widget.onDrawEnd != null) {
          widget.onDrawEnd!(canvasPoint);
        }
      }

      // Reset stato
      _firstPointerPosition = null;
      _hasMoved = false;
      _lastDrawPosition = null; // 🚀 Reset interpolazione
      _lastCanvasPosition = null; // 🚀 FIX #5: Reset canvas cache
      _lastPressure = 1.0;
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
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

    // Reset stato
    if (_pointerCount == 0) {
      _wasMultiTouch = false;
      _isSingleFingerPanning = false; // 🖐️ Reset pan with a finger
      _shouldEnableDrawing = true; // 🖊️ Reset stylus drawing flag
      _firstPointerPosition = null;
      _hasMoved = false;
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    _initialScale = widget.controller.scale;
    _initialFocalPoint = details.focalPoint;
    _initialOffset = widget.controller.offset;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    // Only con 2+ dita (zoom e pan)
    // 🔒 Block pan/zoom if the digital text tool is resizing/dragging
    if (_pointerCount < 2 || widget.blockPanZoom) return;

    // Calculate nuovo scale con limiti (dezoom massimo 0.2x, zoom massimo 5x)
    final newScale = (_initialScale * details.scale).clamp(0.2, 5.0);

    // Calculate il delta di pan dat the point iniziale
    final panDelta = details.focalPoint - _initialFocalPoint;

    // Calculate offset considerando sia lo zoom that the pan
    // 1. Start zoom: keep the initial focal point fixed
    final focalPointCanvas =
        (_initialFocalPoint - _initialOffset) / _initialScale;
    final offsetAfterZoom = _initialFocalPoint - (focalPointCanvas * newScale);

    // 2. Aggiungi il pan
    final newOffset = offsetAfterZoom + panDelta;

    // Applica trasformazione (zoom + pan)
    widget.controller.updateTransform(offset: newOffset, scale: newScale);
  }

  void _onScaleEnd(ScaleEndDetails details) {
    // Reset state
  }
}
