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

    // Build preview anchors: committed + in-progress preview anchor.
    final screenPreviewAnchors = <AnchorPoint>[...screenAnchors];
    if (_previewAnchor != null) {
      screenPreviewAnchors.add(_anchorToScreen(_previewAnchor!, context));
    }

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
            previewAnchors: screenPreviewAnchors,
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
    final theme = Theme.of(buildContext);
    final cs = theme.colorScheme;

    return StatefulBuilder(
      builder: (ctx, setLocalState) {
        // Wrap in Listener(opaque) to absorb pointer events and prevent
        // the canvas InfiniteCanvasGestureDetector (which uses a Listener
        // with HitTestBehavior.translucent) from stealing touches.
        return Listener(
          behavior: HitTestBehavior.opaque,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: cs.shadow.withValues(alpha: 0.2),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── ROW 1: Settings ──
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Stroke width chip with popup.
                    _settingsChip(
                      ctx: ctx,
                      cs: cs,
                      icon: Icons.line_weight_rounded,
                      label: '${strokeWidth.toStringAsFixed(1)}',
                      onTap:
                          () => _showStrokeWidthPopup(ctx, cs, setLocalState),
                    ),
                    const SizedBox(width: 4),

                    // Fill toggle.
                    _toggleChip(
                      cs: cs,
                      icon: Icons.format_color_fill_rounded,
                      active: fillColor != null,
                      onTap:
                          () => setLocalState(() {
                            fillColor =
                                fillColor != null
                                    ? null
                                    : strokeColor.withValues(alpha: 0.2);
                          }),
                    ),
                    const SizedBox(width: 4),

                    // 45° angle constraint.
                    _toggleChip(
                      cs: cs,
                      icon: Icons.straighten_rounded,
                      active: constrainAngles,
                      tooltip: '45°',
                      onTap:
                          () => setLocalState(() {
                            constrainAngles = !constrainAngles;
                          }),
                    ),
                    const SizedBox(width: 4),

                    // Grid snap.
                    _toggleChip(
                      cs: cs,
                      icon: Icons.grid_on_rounded,
                      active: gridSpacing != null,
                      onTap: () => _showGridPopup(ctx, cs, setLocalState),
                    ),
                    const SizedBox(width: 4),

                    // Curvature comb.
                    _toggleChip(
                      cs: cs,
                      icon: Icons.show_chart_rounded,
                      active: showCurvatureComb,
                      onTap:
                          () => setLocalState(() {
                            showCurvatureComb = !showCurvatureComb;
                          }),
                    ),
                  ],
                ),

                // ── ROW 2: Actions (only when building a path) ──
                if (_anchors.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Anchor count badge.
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: cs.secondaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${_anchors.length}',
                          style: TextStyle(
                            color: cs.onSecondaryContainer,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Undo last anchor.
                      _actionChip(
                        cs: cs,
                        icon: Icons.undo_rounded,
                        onTap: () {
                          undoLastAnchor();
                          onToolOptionsChanged?.call();
                        },
                      ),
                      const SizedBox(width: 4),

                      // Cancel path.
                      _actionChip(
                        cs: cs,
                        icon: Icons.close_rounded,
                        color: cs.error,
                        onTap: () {
                          cancelPath();
                          onToolOptionsChanged?.call();
                        },
                      ),
                      const SizedBox(width: 4),

                      // Finish open path (≥2 anchors).
                      if (_anchors.length >= 2)
                        _actionChip(
                          cs: cs,
                          icon: Icons.check_rounded,
                          color: Colors.green,
                          onTap: () {
                            if (toolOptionsContext != null) {
                              finalizeOpenPath(toolOptionsContext!);
                            }
                            onToolOptionsChanged?.call();
                          },
                        ),
                      if (_anchors.length >= 2) const SizedBox(width: 4),

                      // Close path (≥3 anchors).
                      if (_anchors.length >= 3)
                        _actionChip(
                          cs: cs,
                          icon: Icons.radio_button_unchecked_rounded,
                          color: Colors.amber.shade700,
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
          ),
        );
      },
    );
  }

  // ── MD3 CHIP COMPONENTS ──

  /// A settings chip: icon + label that opens a popup on tap.
  Widget _settingsChip({
    required BuildContext ctx,
    required ColorScheme cs,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A toggle chip: icon button that toggles on/off with MD3 tonal fill.
  Widget _toggleChip({
    required ColorScheme cs,
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
    String? tooltip,
  }) {
    final widget = GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 36,
        decoration: BoxDecoration(
          color: active ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          size: 18,
          color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant,
        ),
      ),
    );
    if (tooltip != null) {
      return Tooltip(message: tooltip, preferBelow: false, child: widget);
    }
    return widget;
  }

  /// A small action chip button for path operations.
  Widget _actionChip({
    required ColorScheme cs,
    required IconData icon,
    required VoidCallback onTap,
    Color? color,
  }) {
    final c = color ?? cs.onSurfaceVariant;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        width: 40,
        height: 36,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 20, color: c),
      ),
    );
  }

  // ── POPUP PANELS ──

  /// Show stroke width adjustment popup near the chip.
  void _showStrokeWidthPopup(
    BuildContext ctx,
    ColorScheme cs,
    void Function(VoidCallback) setLocalState,
  ) {
    final RenderBox box = ctx.findRenderObject() as RenderBox;
    final overlay = Overlay.of(ctx);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            // Dismiss on tap outside.
            Positioned.fill(
              child: GestureDetector(
                onTap: () => entry.remove(),
                behavior: HitTestBehavior.opaque,
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              bottom: box.size.height + 80,
              left: 0,
              right: 0,
              child: Center(
                child: _StrokeWidthPopup(
                  cs: cs,
                  initial: strokeWidth,
                  onChanged: (v) {
                    setLocalState(() => strokeWidth = v);
                  },
                  onDone: () => entry.remove(),
                ),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(entry);
  }

  /// Show grid spacing adjustment popup near the chip.
  void _showGridPopup(
    BuildContext ctx,
    ColorScheme cs,
    void Function(VoidCallback) setLocalState,
  ) {
    final RenderBox box = ctx.findRenderObject() as RenderBox;
    final overlay = Overlay.of(ctx);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  entry.remove();
                },
                behavior: HitTestBehavior.opaque,
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              bottom: box.size.height + 80,
              left: 0,
              right: 0,
              child: Center(
                child: _GridPopup(
                  cs: cs,
                  initial: gridSpacing ?? 0,
                  onChanged: (v) {
                    setLocalState(() => gridSpacing = v > 0 ? v : null);
                  },
                  onDone: () => entry.remove(),
                ),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(entry);
  }
}

// ── POPUP WIDGETS (separate StatefulWidgets for local state) ──

class _StrokeWidthPopup extends StatefulWidget {
  final ColorScheme cs;
  final double initial;
  final ValueChanged<double> onChanged;
  final VoidCallback onDone;

  const _StrokeWidthPopup({
    required this.cs,
    required this.initial,
    required this.onChanged,
    required this.onDone,
  });

  @override
  State<_StrokeWidthPopup> createState() => _StrokeWidthPopupState();
}

class _StrokeWidthPopupState extends State<_StrokeWidthPopup> {
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      color: widget.cs.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.line_weight_rounded,
              size: 18,
              color: widget.cs.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 150,
              child: Slider(
                value: _value,
                min: 0.5,
                max: 20.0,
                onChanged: (v) {
                  setState(() => _value = v);
                  widget.onChanged(v);
                },
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 44,
              child: Text(
                '${_value.toStringAsFixed(1)}',
                style: TextStyle(
                  color: widget.cs.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GridPopup extends StatefulWidget {
  final ColorScheme cs;
  final double initial;
  final ValueChanged<double> onChanged;
  final VoidCallback onDone;

  const _GridPopup({
    required this.cs,
    required this.initial,
    required this.onChanged,
    required this.onDone,
  });

  @override
  State<_GridPopup> createState() => _GridPopupState();
}

class _GridPopupState extends State<_GridPopup> {
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      color: widget.cs.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.grid_on_rounded,
              size: 18,
              color: widget.cs.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 150,
              child: Slider(
                value: _value,
                min: 0,
                max: 50,
                divisions: 10,
                onChanged: (v) {
                  setState(() => _value = v);
                  widget.onChanged(v);
                },
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 44,
              child: Text(
                _value > 0 ? '${_value.toStringAsFixed(0)}px' : 'Off',
                style: TextStyle(
                  color: widget.cs.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
