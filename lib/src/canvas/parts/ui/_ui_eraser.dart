part of '../../nebula_canvas_screen.dart';

/// 🏗️ Eraser Overlays — cursor, trail, particles, shapes, analytics, undo ghost, etc.
/// Extracted from _NebulaCanvasScreenState._buildImpl
extension NebulaCanvasEraserUI on _NebulaCanvasScreenState {
  /// Builds all eraser-related overlays (cursor, trail, lasso, particles, etc.)
  List<Widget> _buildEraserOverlays(BuildContext context) {
    if (!_effectiveIsEraser || _eraserCursorPosition == null) {
      return const [];
    }

    final screenPos = _canvasController.canvasToScreen(_eraserCursorPosition!);
    final radius = _eraserTool.eraserRadius * _canvasController.scale;
    final now = DateTime.now().millisecondsSinceEpoch;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 🎨 Dark/light mode adaptive colors
    final cursorBorderColor =
        isDark
            ? Colors.red[300]!.withValues(alpha: 0.8)
            : Colors.red.withValues(alpha: 0.7);
    final cursorFillColor =
        isDark
            ? Colors.red[400]!.withValues(
              alpha: _eraserPreviewIds.isNotEmpty ? 0.25 : 0.08,
            )
            : Colors.red.withValues(
              alpha: _eraserPreviewIds.isNotEmpty ? 0.2 : 0.05,
            );
    final crosshairColor =
        isDark
            ? Colors.white.withValues(alpha: 0.7)
            : Colors.white.withValues(alpha: 0.6);

    return [
      // V10: Accessibility semantics for eraser cursor
      Builder(
        builder: (context) {
          return Semantics(
            label:
                'Eraser, radius ${_eraserTool.eraserRadius.round()}, '
                '${_eraserGestureEraseCount} erased',
            child: Stack(
              children: [
                // Eraser trail effect
                if (_eraserTrail.length >= 2)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _EraserTrailPainter(
                          trail: _eraserTrail,
                          canvasController: _canvasController,
                          now: now,
                          isDark: isDark,
                        ),
                      ),
                    ),
                  ),

                // 🎯 V3: Boundary particles
                if (_eraserParticles.isNotEmpty)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _EraserParticlePainter(
                          particles: _eraserParticles,
                          canvasController: _canvasController,
                          isDark: isDark,
                        ),
                      ),
                    ),
                  ),

                // 🎯 V4: Lasso eraser path overlay
                if (_eraserLassoMode && _eraserLassoPoints.length >= 2)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _EraserLassoPathPainter(
                          points: _eraserLassoPoints,
                          canvasController: _canvasController,
                          isDark: isDark,
                          isAnimating: _eraserLassoAnimating,
                        ),
                      ),
                    ),
                  ),

                // 🎯 V4: Protected regions overlay
                if (_eraserTool.protectedRegions.isNotEmpty)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _EraserProtectedRegionPainter(
                          regions: _eraserTool.protectedRegions,
                          canvasController: _canvasController,
                          isDark: isDark,
                        ),
                      ),
                    ),
                  ),

                // 🎯 V4: Undo scrubber (shows undo depth)
                if (_eraserTool.undoStackDepth > 0)
                  Positioned(
                    bottom: 100,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color:
                                isDark
                                    ? Colors.grey[800]!.withValues(alpha: 0.85)
                                    : Colors.grey[200]!.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            '↶ ${_eraserTool.undoStackDepth}',
                            style: TextStyle(
                              color: isDark ? Colors.white70 : Colors.black54,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // 🎯 V5: Ghost preview — show strokes under eraser at low opacity
                if (_eraserPreviewIds.isNotEmpty)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _EraserGhostPreviewPainter(
                          previewStrokeIds: _eraserPreviewIds,
                          layerController: _layerController,
                          canvasController: _canvasController,
                          isDark: isDark,
                        ),
                      ),
                    ),
                  ),

                // 🎯 V5: Magnetic snap indicator — dashed line from cursor to snap target
                if (_eraserTool.magneticSnap &&
                    _eraserTool.lastMagneticSnapTarget != null &&
                    _eraserCursorPosition != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _MagneticSnapIndicatorPainter(
                          cursorPos: _canvasController.canvasToScreen(
                            _eraserCursorPosition!,
                          ),
                          snapTarget: _canvasController.canvasToScreen(
                            _eraserTool.lastMagneticSnapTarget!,
                          ),
                          isDark: isDark,
                        ),
                      ),
                    ),
                  ),

                // 🎯 V5: Shortcut ring (radial menu on long-press)
                if (_showEraserShortcutRing && _eraserCursorPosition != null)
                  _buildEraserShortcutRing(context, isDark),

                // 🎯 V6: Dissolve particles — explosion effect at erased points
                if (_eraserShowDissolve &&
                    _eraserTool.dissolvePoints.isNotEmpty)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _DissolveParticlesPainter(
                          points: List.from(_eraserTool.dissolvePoints),
                          canvasController: _canvasController,
                          isDark: isDark,
                        ),
                      ),
                    ),
                  ),

                // 🎯 V6: Heatmap trail — color based on touch frequency
                if (_eraserTrail.isNotEmpty)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _HeatmapTrailPainter(
                          trail: _eraserTrail,
                          eraserTool: _eraserTool,
                          canvasController: _canvasController,
                        ),
                      ),
                    ),
                  ),

                // 🎯 V6: Mask preview — full-canvas erase coverage
                if (_eraserMaskPreview && _eraserCursorPosition != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _EraserMaskPreviewPainter(
                          cursorPos: _canvasController.canvasToScreen(
                            _eraserCursorPosition!,
                          ),
                          radius: radius,
                          isDark: isDark,
                        ),
                      ),
                    ),
                  ),

                // 🎯 V6: Auto-clean highlight — pulse suggested strokes
                if (_autoCleanSuggestions.isNotEmpty)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _AutoCleanHighlightPainter(
                          suggestionIds: _autoCleanSuggestions,
                          layerController: _layerController,
                          canvasController: _canvasController,
                          isDark: isDark,
                        ),
                      ),
                    ),
                  ),

                // 🎯 V6: Analytics badge (bottom-right near cursor)
                if (_eraserTool.totalStrokesErased > 0)
                  Positioned(
                    right: 16,
                    bottom: 100,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: (isDark ? Colors.grey[900]! : Colors.white)
                              .withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color:
                                isDark ? Colors.grey[700]! : Colors.grey[300]!,
                          ),
                        ),
                        child: Text(
                          _eraserTool.analyticsSummary,
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),

                // 🎯 V6: History timeline (bottom strip)
                if (_showEraserTimeline &&
                    _eraserTool.historySnapshots.isNotEmpty)
                  Positioned(
                    left: 60,
                    right: 60,
                    bottom: 50,
                    height: 40,
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _EraserHistoryTimelinePainter(
                          snapshots: _eraserTool.historySnapshots,
                          isDark: isDark,
                        ),
                      ),
                    ),
                  ),

                // ─── V7 OVERLAYS ────────────────────────────────

                // 🎯 V7: Undo ghost replay — semi-transparent strokes fading in
                if (_showUndoGhostReplay &&
                    _eraserTool.undoGhostStrokes.isNotEmpty)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _UndoGhostReplayPainter(
                          ghostStrokes: _eraserTool.undoGhostStrokes,
                          progress: _eraserTool.undoGhostProgress,
                          canvasController: _canvasController,
                          isDark: isDark,
                        ),
                      ),
                    ),
                  ),

                // 🎯 V7: Eraser shape cursor (rectangle/line shapes)
                if (_eraserCursorPosition != null &&
                    _eraserTool.eraserShape != EraserShape.circle)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _EraserShapeCursorPainter(
                          center: _canvasController.canvasToScreen(
                            _eraserCursorPosition!,
                          ),
                          shape: _eraserTool.eraserShape,
                          radius: radius,
                          shapeWidth:
                              _eraserTool.eraserShapeWidth *
                              _canvasController.scale,
                          angle: _eraserTool.eraserShapeAngle,
                          isDark: isDark,
                        ),
                      ),
                    ),
                  ),

                // 🎯 V7: Edge-aware highlight — glow on stroke edges near cursor
                if (_eraserCursorPosition != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _EdgeAwareHighlightPainter(
                          edgePoints: _eraserTool.getEdgeAwareStrokeIds(
                            _eraserCursorPosition!,
                          ),
                          canvasController: _canvasController,
                          isDark: isDark,
                        ),
                      ),
                    ),
                  ),

                // 🎯 V7: Smart selection preview — full highlighted stroke
                if (_smartSelectionStrokeId != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _SmartSelectionPreviewPainter(
                          strokeId: _smartSelectionStrokeId!,
                          layerController: _layerController,
                          canvasController: _canvasController,
                          isDark: isDark,
                        ),
                      ),
                    ),
                  ),

                // 🎯 V7: Layer-specific preview — dim non-active layers
                if (_showLayerPreview && _eraserTool.layerPreviewMode)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _LayerPreviewDimPainter(
                          nonActiveIndices:
                              _eraserTool.getNonActiveLayerIndices(),
                          layerController: _layerController,
                          canvasController: _canvasController,
                          isDark: isDark,
                        ),
                      ),
                    ),
                  ),

                // 🎯 V7/V8: Pressure curve editor (bottom-left, interactive)
                if (_showPressureCurveEditor)
                  _buildPressureCurveEditor(context, isDark),

                // 🎯 Cursor circle with pulse + crosshair + badge
                _buildEraserCursorCircle(
                  context,
                  screenPos: screenPos,
                  radius: radius,
                  isDark: isDark,
                  cursorBorderColor: cursorBorderColor,
                  cursorFillColor: cursorFillColor,
                  crosshairColor: crosshairColor,
                ),
              ],
            ), // Stack
          ); // Semantics
        },
      ),
    ];
  }

  /// 🎯 V5: Shortcut ring (radial menu on long-press)
  Widget _buildEraserShortcutRing(BuildContext context, bool isDark) {
    final center = _canvasController.canvasToScreen(_eraserCursorPosition!);
    const ringRadius = 80.0;
    final items = [
      ('🎯', 'Snap', _eraserTool.magneticSnap),
      ('✂️', 'Lasso', _eraserLassoMode),
      ('🪶', 'Feather', _eraserTool.featheredEdge),
      ('🔄', 'Undo', false),
    ];
    return Builder(
      builder: (context) {
        return Stack(
          children: [
            for (int i = 0; i < items.length; i++)
              Positioned(
                left:
                    center.dx +
                    ringRadius * math.cos(i * math.pi / 2 - math.pi / 2) -
                    22,
                top:
                    center.dy +
                    ringRadius * math.sin(i * math.pi / 2 - math.pi / 2) -
                    22,
                child: GestureDetector(
                  onTap: () {
                    switch (i) {
                      case 0:
                        _eraserTool.magneticSnap = !_eraserTool.magneticSnap;
                        break;
                      case 1:
                        _eraserLassoMode = !_eraserLassoMode;
                        break;
                      case 2:
                        _eraserTool.featheredEdge = !_eraserTool.featheredEdge;
                        break;
                      case 3:
                        _eraserTool.undo();
                        break;
                    }
                    _showEraserShortcutRing = false;
                    setState(() {});
                  },
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color:
                          items[i].$3
                              ? (isDark
                                  ? Colors.orange[700]
                                  : Colors.orange[400])
                              : (isDark ? Colors.grey[800] : Colors.grey[200]),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        items[i].$1,
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// 🎯 V7/V8: Pressure curve editor (bottom-left corner, interactive)
  Widget _buildPressureCurveEditor(BuildContext context, bool isDark) {
    return Positioned(
      left: 16,
      bottom: 100,
      width: 120,
      height: 120,
      child: GestureDetector(
        onPanUpdate: (details) {
          // V8: Convert drag position to normalized [0,1] coords
          final box = context.findRenderObject() as RenderBox?;
          if (box == null) return;
          final padding = 12.0;
          final w = 120.0 - padding * 2;
          final h = 120.0 - padding * 2;
          final lx = ((details.localPosition.dx - padding) / w).clamp(0.0, 1.0);
          final ly = (1.0 - (details.localPosition.dy - padding) / h).clamp(
            0.0,
            1.0,
          );
          final tapOffset = Offset(lx, ly);

          // Find nearest control point
          final cp = _eraserTool.pressureCurveControlPoints;
          final d0 = (cp[0] - tapOffset).distance;
          final d1 = (cp[1] - tapOffset).distance;
          if (d0 <= d1) {
            cp[0] = tapOffset;
          } else {
            cp[1] = tapOffset;
          }
          setState(() {});
        },
        child: CustomPaint(
          painter: _PressureCurveEditorPainter(
            controlPoints: _eraserTool.pressureCurveControlPoints,
            isDark: isDark,
          ),
        ),
      ),
    );
  }

  /// 🎯 Cursor circle with pulse + crosshair + erase count badge
  Widget _buildEraserCursorCircle(
    BuildContext context, {
    required Offset screenPos,
    required double radius,
    required bool isDark,
    required Color cursorBorderColor,
    required Color cursorFillColor,
    required Color crosshairColor,
  }) {
    return AnimatedBuilder(
      animation: _eraserPulseController,
      builder: (context, child) {
        final pulseScale = 1.0 + 0.15 * (1.0 - _eraserPulseController.value);
        final scaledRadius = radius * pulseScale;

        return Stack(
          children: [
            Positioned(
              left: screenPos.dx - scaledRadius,
              top: screenPos.dy - scaledRadius,
              child: IgnorePointer(
                child: SizedBox(
                  width: scaledRadius * 2,
                  height: scaledRadius * 2,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Circle border + fill (V5: tilt-based ellipse)
                      Positioned.fill(
                        child: Transform(
                          alignment: Alignment.center,
                          // V5: Compress on tilt axis for ellipse effect
                          transform:
                              Matrix4.identity()
                                ..scaleByDouble(
                                  1.0 -
                                      (_eraserTiltX.abs() * 0.3).clamp(
                                        0.0,
                                        0.4,
                                      ),
                                  1.0 -
                                      (_eraserTiltY.abs() * 0.3).clamp(
                                        0.0,
                                        0.4,
                                      ),
                                  1.0,
                                  1.0,
                                )
                                ..rotateZ(
                                  _eraserTiltX != 0 || _eraserTiltY != 0
                                      ? math.atan2(_eraserTiltX, _eraserTiltY)
                                      : 0.0,
                                ),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: cursorBorderColor,
                                width: 2,
                              ),
                              color: cursorFillColor,
                            ),
                          ),
                        ),
                      ),

                      // Crosshair lines
                      Center(
                        child: CustomPaint(
                          size: Size(scaledRadius * 2, scaledRadius * 2),
                          painter: _CrosshairPainter(
                            radius: scaledRadius,
                            color: crosshairColor,
                          ),
                        ),
                      ),

                      // 📏 Px label (below cursor)
                      Positioned(
                        bottom: -18,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Text(
                            '${_eraserTool.eraserRadius.round()}px',
                            style: TextStyle(
                              color: isDark ? Colors.red[200] : Colors.red[600],
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),

                      // Erase count badge (animated fade-out)
                      Positioned(
                        right: -6,
                        top: -6,
                        child: AnimatedOpacity(
                          opacity: _eraserGestureEraseCount > 0 ? 1.0 : 0.0,
                          duration: Duration(
                            milliseconds:
                                _eraserGestureEraseCount > 0 ? 100 : 400,
                          ),
                          child: AnimatedScale(
                            scale: _eraserGestureEraseCount > 0 ? 1.0 : 0.6,
                            duration: const Duration(milliseconds: 200),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.shade700,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 3,
                                  ),
                                ],
                              ),
                              child: Text(
                                '${_eraserGestureEraseCount > 0 ? _eraserGestureEraseCount : ""}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
