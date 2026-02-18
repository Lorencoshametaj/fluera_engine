part of '../../nebula_canvas_screen.dart';

/// 📦 Drawing Auxiliary — auto-scroll, flood fill, rasterization, eraser particles, pinch
extension on _NebulaCanvasScreenState {
  // ============================================================================
  // 🏎️ EDGE AUTO-SCROLL — Proportional, rotation-aware
  // ============================================================================

  /// Start or update edge auto-scroll with proportional speed.
  ///
  /// Speed increases quadratically as the pointer moves deeper into the
  /// edge zone. Scroll direction is rotation-compensated so it always
  /// moves in the expected visual direction regardless of canvas rotation.
  ///
  /// Instead of compensating tool positions, we store the finger's screen
  /// position and re-derive the canvas position every tick. This ensures
  /// the dragged element always stays under the finger.
  void _startAutoScrollIfNeeded(Offset screenPosition, Size screenSize) {
    // Cancel existing timer
    _autoScrollTimer?.cancel();

    const double edgeZone = _NebulaCanvasScreenState._edgeScrollThreshold;
    const double maxSpeed = _NebulaCanvasScreenState._scrollSpeed;

    // Calculate how deep into each edge zone the pointer is (0 = outside, 1 = at edge)
    final distLeft = screenPosition.dx;
    final distRight = screenSize.width - screenPosition.dx;
    final distTop = screenPosition.dy;
    final distBottom = screenSize.height - screenPosition.dy;

    // Proportional intensity: 0 outside zone, 1 at screen edge (quadratic)
    double intensityX = 0.0;
    double intensityY = 0.0;

    if (distLeft < edgeZone) {
      final t = 1.0 - (distLeft / edgeZone); // 0 at zone edge, 1 at screen edge
      intensityX =
          t * t * maxSpeed; // Quadratic acceleration (positive = scroll right)
    } else if (distRight < edgeZone) {
      final t = 1.0 - (distRight / edgeZone);
      intensityX = -(t * t * maxSpeed); // Negative = scroll left
    }

    if (distTop < edgeZone) {
      final t = 1.0 - (distTop / edgeZone);
      intensityY = t * t * maxSpeed; // Positive = scroll down
    } else if (distBottom < edgeZone) {
      final t = 1.0 - (distBottom / edgeZone);
      intensityY = -(t * t * maxSpeed); // Negative = scroll up
    }

    // If no scroll needed, stop and clear edge state
    if (intensityX == 0.0 && intensityY == 0.0) {
      if (_activeEdgeScroll != 0) {
        _activeEdgeScroll = 0;
        setState(() {});
      }
      return;
    }

    // 🏎️ Track active edges for visual glow
    int edges = 0;
    if (distLeft < edgeZone) edges |= 1; // left
    if (distRight < edgeZone) edges |= 2; // right
    if (distTop < edgeZone) edges |= 4; // top
    if (distBottom < edgeZone) edges |= 8; // bottom
    _activeEdgeScroll = edges;

    // 🌀 Rotation-aware: rotate scroll vector by -rotation so visual direction is correct
    final rotation = _canvasController.rotation;
    double scrollX = intensityX;
    double scrollY = intensityY;
    if (rotation != 0.0) {
      final cosR = math.cos(-rotation);
      final sinR = math.sin(-rotation);
      scrollX = intensityX * cosR - intensityY * sinR;
      scrollY = intensityX * sinR + intensityY * cosR;
    }

    // 📏 Scale-aware: scroll faster when zoomed out, slower when zoomed in
    final scaleFactor = 1.0 / _canvasController.scale;
    scrollX *= scaleFactor;
    scrollY *= scaleFactor;

    // 📌 Store finger screen position — re-derived to canvas coords every tick
    _autoScrollFingerScreenPos = screenPosition;

    // 🫨 Haptic pulse when entering auto-scroll zone
    final wasScrolling = _autoScrollTimer != null;
    if (!wasScrolling) {
      HapticFeedback.lightImpact();
    }

    // 🏎️ Smooth ramp-up: ease into full speed over ~200ms (12 frames)
    int _rampFrame = wasScrolling ? 12 : 0; // Skip ramp if already scrolling

    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 16), (
      timer,
    ) {
      // Ramp factor: 0→1 over 12 frames
      _rampFrame = (_rampFrame + 1).clamp(0, 12);
      final ramp = _rampFrame / 12.0;
      final rampedScrollX = scrollX * ramp;
      final rampedScrollY = scrollY * ramp;

      // 📌 Snapshot BEFORE scroll: where does the finger point in canvas space?
      final canvasBefore = _canvasController.screenToCanvas(
        _autoScrollFingerScreenPos,
      );

      // Move the canvas (using ramped speed)
      final currentOffset = _canvasController.offset;
      final newOffset = Offset(
        currentOffset.dx + rampedScrollX,
        currentOffset.dy + rampedScrollY,
      );
      _canvasController.setOffset(newOffset);

      // 📌 Snapshot AFTER scroll: same screen position → different canvas position
      final canvasAfter = _canvasController.screenToCanvas(
        _autoScrollFingerScreenPos,
      );

      // The canvas-space delta: how much the "target" moved due to scroll.
      // This automatically accounts for scale AND rotation correctly.
      final compensation = canvasAfter - canvasBefore;

      if (_lassoTool.isDragging) {
        _lassoTool.compensateScroll(compensation);
        DrawingPainter.invalidateAllTiles();
      }

      // Digital text: compensate + sync list
      if (_digitalTextTool.isDragging || _digitalTextTool.isResizing) {
        _digitalTextTool.compensateScroll(compensation);
        if (_digitalTextTool.selectedElement != null) {
          final index = _digitalTextElements.indexWhere(
            (e) => e.id == _digitalTextTool.selectedElement!.id,
          );
          if (index != -1) {
            _digitalTextElements[index] = _digitalTextTool.selectedElement!;
          }
        }
      }

      // 🖼️ Image: compensate + sync list
      if (_imageTool.isDragging || _imageTool.isResizing) {
        _imageTool.compensateScroll(compensation);
        if (_imageTool.selectedImage != null) {
          final index = _imageElements.indexWhere(
            (e) => e.id == _imageTool.selectedImage!.id,
          );
          if (index != -1) {
            _imageElements[index] = _imageTool.selectedImage!;
          }
        }
      }

      setState(() {}); // Force rebuild to update positions
    });
  }

  /// Stop edge auto-scroll and clear visual state.
  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    if (_activeEdgeScroll != 0) {
      _activeEdgeScroll = 0;
      // No setState here — the drag end handler will trigger rebuild
    }
  }

  /// 🪣 Phase 3D: Execute flood fill at the given canvas position
  Future<void> _executeFloodFill(Offset canvasPosition) async {
    // Get the current canvas size from context
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final viewportSize = renderBox.size;
    final rasterWidth = viewportSize.width.toInt();
    final rasterHeight = viewportSize.height.toInt();

    if (rasterWidth <= 0 || rasterHeight <= 0) return;

    // Rasterize visible canvas to an image using PictureRecorder
    final recorder = ui.PictureRecorder();
    final recordCanvas = ui.Canvas(recorder);

    // Apply canvas transform (offset + scale)
    final canvasScale = _canvasController.scale;
    final canvasOffset = _canvasController.offset;
    recordCanvas.scale(canvasScale);
    recordCanvas.translate(canvasOffset.dx, canvasOffset.dy);

    // Draw all strokes from the active layer
    final activeLayer = _layerController.activeLayer;
    if (activeLayer != null) {
      for (final stroke in activeLayer.strokes) {
        _drawStrokeForRasterization(recordCanvas, stroke);
      }
    }

    final picture = recorder.endRecording();
    final rasterImage = await picture.toImage(rasterWidth, rasterHeight);

    // Convert canvas position to screen/raster coordinates
    final screenPos = _canvasController.canvasToScreen(canvasPosition);
    final rasterPoint = Offset(
      screenPos.dx.clamp(0.0, rasterWidth - 1.0),
      screenPos.dy.clamp(0.0, rasterHeight - 1.0),
    );

    // Update fill color from current selected color
    final fillColor = _effectiveColor;
    _floodFillTool.fillColor = fillColor;

    // Execute flood fill
    final mask = await _floodFillTool.executeFloodFill(
      rasterImage,
      rasterPoint,
    );
    if (mask == null) {
      rasterImage.dispose();
      return;
    }

    // Generate filled image
    final fillImage = await _floodFillTool.generateFillImage(
      mask,
      rasterWidth,
      rasterHeight,
      fillColor,
    );
    if (fillImage == null) {
      rasterImage.dispose();
      return;
    }

    // Calculate canvas-space bounds for the fill overlay
    // The fill image is in screen space; we need to know where it maps in canvas space
    // Screen → Canvas: canvasPos = screenPos / scale - offset
    final canvasBounds = Rect.fromLTWH(
      -canvasOffset.dx,
      -canvasOffset.dy,
      rasterWidth / canvasScale,
      rasterHeight / canvasScale,
    );

    // Create a fill stroke with the overlay attached
    final fillStroke = ProStroke(
      id: const Uuid().v4(),
      points: [
        ProDrawingPoint(
          position: canvasPosition,
          pressure: 1.0,
          tiltX: 0.0,
          tiltY: 0.0,
          orientation: 0.0,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
      ],
      color: fillColor,
      baseWidth: 1.0,
      penType: ProPenType.ballpoint,
      createdAt: DateTime.now(),
      fillOverlay: fillImage, // 🪣 Attach the fill raster overlay
      fillBounds: canvasBounds, // 🪣 Canvas-space position for rendering
    );

    // Add the fill stroke to the active layer
    _layerController.addStroke(fillStroke);

    setState(() {});

    // Dispose only the rasterized source image (the fill overlay stays alive on the stroke)
    rasterImage.dispose();
  }

  /// Helper: Draw a stroke on a ui.Canvas for rasterization purposes
  void _drawStrokeForRasterization(ui.Canvas canvas, ProStroke stroke) {
    if (stroke.points.isEmpty) return;

    final paint =
        Paint()
          ..color = stroke.color
          ..strokeWidth = stroke.baseWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke;

    if (stroke.points.length == 1) {
      final pos = stroke.points.first.position;
      canvas.drawCircle(
        pos,
        stroke.baseWidth / 2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }

    final path = Path();
    path.moveTo(
      stroke.points.first.position.dx,
      stroke.points.first.position.dy,
    );
    for (int i = 1; i < stroke.points.length; i++) {
      final prev = stroke.points[i - 1].position;
      final curr = stroke.points[i].position;
      final mid = Offset((prev.dx + curr.dx) / 2, (prev.dy + curr.dy) / 2);
      path.quadraticBezierTo(prev.dx, prev.dy, mid.dx, mid.dy);
    }
    path.lineTo(stroke.points.last.position.dx, stroke.points.last.position.dy);
    canvas.drawPath(path, paint);
  }

  // ─── V3: Eraser Particle System ──────────────────────────────────

  /// Spawn particles at the erase intersection point
  void _spawnEraserParticles(Offset position, int now) {
    final random = DateTime.now().microsecond;
    for (int i = 0; i < 6; i++) {
      // Pseudo-random velocity using microsecond seed
      final angle = (random + i * 60) * 0.0174533; // Convert to radians
      final speed = 0.5 + (((random + i * 37) % 100) / 100.0) * 1.5;
      _eraserParticles.add(
        _EraserParticle(
          position: position,
          velocity: Offset(
            speed * (angle.isNaN ? 1.0 : (i.isEven ? 1 : -1) * speed * 0.7),
            -speed * 0.5 - (((random + i * 13) % 100) / 100.0) * 1.0,
          ),
          createdAt: now,
          size: 1.5 + (((random + i * 23) % 100) / 100.0) * 2.5,
        ),
      );
    }
    // Cap total particles
    if (_eraserParticles.length > 60) {
      _eraserParticles.removeRange(0, _eraserParticles.length - 60);
    }
  }

  /// Update particle positions: gravity, decay, and cleanup
  void _updateEraserParticles(int now) {
    _eraserParticles.removeWhere((p) {
      final age = now - p.createdAt;
      if (age > 500) return true; // Remove after 500ms
      // Update position with velocity + gravity
      p.position = Offset(
        p.position.dx + p.velocity.dx,
        p.position.dy + p.velocity.dy + (age * 0.003), // Gravity
      );
      p.opacity = (1.0 - (age / 500.0)).clamp(0.0, 1.0);
      return false;
    });
  }

  // ═════════════════════════════════════════════════════════════════════
  // V4: PINCH-TO-RESIZE ERASER
  // ═════════════════════════════════════════════════════════════════════

  /// Call when a scale gesture starts while eraser is active
  void _onEraserPinchStart() {
    _eraserPinchBaseRadius = _eraserTool.eraserRadius;
  }

  /// Call with scale factor during pinch — resizes eraser radius
  void _onEraserPinchUpdate(double scale) {
    if (_eraserPinchBaseRadius == null) return;
    final newRadius = (_eraserPinchBaseRadius! * scale).clamp(
      EraserTool.minRadius,
      EraserTool.maxRadius,
    );
    _eraserTool.eraserRadius = newRadius;
    _eraserSmoothedRadius = newRadius;
    setState(() {});
  }

  /// Call when scale gesture ends — persist the new radius
  void _onEraserPinchEnd() {
    _eraserPinchBaseRadius = null;
    _eraserTool.persistRadius();
  }
}
