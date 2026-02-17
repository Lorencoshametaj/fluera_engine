part of 'pen_tool.dart';

// ============================================================================
// OVERLAY + TOOL OPTIONS UI
// ============================================================================

extension _PenToolUI on PenTool {
  // ── OVERLAY ──

  Widget? buildPenOverlay(ToolContext context) {
    if (_anchors.isEmpty && _cursorCanvasPosition == null) return null;

    // Convert anchors to screen coordinates for the painter.
    final screenAnchors =
        _anchors.map((a) => _anchorToScreen(a, context)).toList();

    final screenCursor =
        _cursorCanvasPosition != null
            ? context.canvasToScreen(_cursorCanvasPosition!)
            : null;

    final screenDragHandle =
        _dragHandleCanvas != null
            ? context.canvasToScreen(_dragHandleCanvas!)
            : null;

    // Check if cursor is near the first anchor (for close indicator).
    bool showClose = false;
    final closeThreshold = PenTool._baseCloseThreshold;
    if (_anchors.length >= 3 &&
        screenCursor != null &&
        screenAnchors.isNotEmpty) {
      showClose =
          (screenCursor - screenAnchors.first.position).distance <
          closeThreshold;
    }

    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: PenToolPainter(
            anchors: screenAnchors,
            cursorPosition: screenCursor,
            dragHandle: screenDragHandle,
            showCloseIndicator: showClose,
            pathColor: strokeColor,
            pathStrokeWidth: strokeWidth.clamp(1.0, 4.0),
            anchorCount: _anchors.length,
            isDarkMode: isDarkMode,
            fillColor: fillColor,
            editingAnchorIndex: _editingAnchorIndex,
            selectedAnchorIndices: _selectedAnchorIndices,
            showCurvatureComb: showCurvatureComb,
          ),
        ),
      ),
    );
  }

  // ── TOOL OPTIONS ──

  Widget? buildPenToolOptions(BuildContext buildContext) {
    return StatefulBuilder(
      builder: (ctx, setLocalState) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: (isDarkMode ? Colors.grey.shade800 : Colors.grey.shade900)
                .withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Stroke width slider.
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.line_weight,
                    color: Colors.white70,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 120,
                    child: Slider(
                      value: strokeWidth,
                      min: 0.5,
                      max: 20.0,
                      activeColor: Colors.blue,
                      onChanged: (v) => setLocalState(() => strokeWidth = v),
                    ),
                  ),
                  Text(
                    '${strokeWidth.toStringAsFixed(1)}px',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),

              // Fill toggle.
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Fill:',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  Switch(
                    value: fillColor != null,
                    activeThumbColor: Colors.blue,
                    onChanged:
                        (v) => setLocalState(() {
                          fillColor =
                              v ? strokeColor.withValues(alpha: 0.2) : null;
                        }),
                  ),
                ],
              ),

              // Constrain angles toggle.
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '45°:',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  Switch(
                    value: constrainAngles,
                    activeThumbColor: Colors.orange,
                    onChanged:
                        (v) => setLocalState(() {
                          constrainAngles = v;
                        }),
                  ),
                ],
              ),

              // Grid snapping.
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.grid_on, color: Colors.white70, size: 16),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 100,
                    child: Slider(
                      value: gridSpacing ?? 0,
                      min: 0,
                      max: 50,
                      divisions: 10,
                      activeColor: Colors.teal,
                      onChanged:
                          (v) => setLocalState(() {
                            gridSpacing = v > 0 ? v : null;
                          }),
                    ),
                  ),
                  Text(
                    gridSpacing != null
                        ? '${gridSpacing!.toStringAsFixed(0)}px'
                        : 'Off',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),

              // Curvature comb toggle.
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Comb:',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  Switch(
                    value: showCurvatureComb,
                    activeThumbColor: Colors.purple,
                    onChanged:
                        (v) => setLocalState(() {
                          showCurvatureComb = v;
                        }),
                  ),
                ],
              ),

              // Touch-friendly action buttons (when building).
              if (_anchors.isNotEmpty) ...[
                const Divider(color: Colors.white24, height: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Anchor count
                    Text(
                      '${_anchors.length} pt',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Undo last anchor
                    actionButton(
                      icon: Icons.undo_rounded,
                      tooltip: 'Undo',
                      onTap: () {
                        undoLastAnchor();
                        onToolOptionsChanged?.call();
                      },
                    ),

                    // Cancel path
                    actionButton(
                      icon: Icons.close_rounded,
                      tooltip: 'Cancel',
                      color: Colors.red.shade300,
                      onTap: () {
                        cancelPath();
                        onToolOptionsChanged?.call();
                      },
                    ),

                    // Finish (open path) — needs ≥2 anchors
                    if (_anchors.length >= 2)
                      actionButton(
                        icon: Icons.check_rounded,
                        tooltip: 'Finish',
                        color: Colors.green.shade300,
                        onTap: () {
                          if (toolOptionsContext != null) {
                            finalizeOpenPath(toolOptionsContext!);
                          }
                          onToolOptionsChanged?.call();
                        },
                      ),

                    // Close path — needs ≥3 anchors
                    if (_anchors.length >= 3)
                      actionButton(
                        icon: Icons.radio_button_unchecked,
                        tooltip: 'Close',
                        color: Colors.amber.shade300,
                        onTap: () {
                          if (toolOptionsContext != null) {
                            finalizeClosedPath(toolOptionsContext!);
                          }
                          onToolOptionsChanged?.call();
                        },
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Small touch-friendly action button for the tool options bar.
  Widget actionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color color = Colors.white70,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Tooltip(
        message: tooltip,
        preferBelow: false,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
        ),
      ),
    );
  }
}
