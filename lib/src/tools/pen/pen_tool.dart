import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../base/tool_context.dart';
import '../base/base_tool.dart';
import '../base/tool_interface.dart';
import '../../core/vector/anchor_point.dart';
import '../../core/vector/vector_path.dart';
import '../../core/nodes/path_node.dart';
import '../../core/effects/gradient_fill.dart';
import './pen_tool_painter.dart';

/// ✒️ INTERACTIVE PEN TOOL — Bézier Path Editor
///
/// Creates vector paths by placing anchor points on the canvas.
///
/// INTERACTIONS:
/// - **Tap** → place a corner anchor (straight line segment)
/// - **Tap + drag** → place a smooth anchor with symmetric Bézier handles
/// - **Double-tap** → finalize the path as open
/// - **Tap on first anchor** (≥3 points) → close the path and finalize
/// - **Escape key** → cancel the current path
///
/// DESIGN PRINCIPLES:
/// - Extends BaseTool for standard lifecycle and position tracking
/// - Uses a callback [onPathNodeCreated] to notify the host app
///   when a PathNode is ready (dependency inversion — tool doesn't
///   know about the scene graph)
/// - Overlay rendering via [PenToolPainter]
/// - All internal state in CANVAS coordinates; overlay converts to screen

/// What part of an anchor is being edited.
enum _EditTarget { position, handleIn, handleOut }

class PenTool extends BaseTool {
  // ============================================================================
  // 🔧 CONFIGURATION
  // ============================================================================

  /// Callback invoked when the user finalizes a path.
  /// The host app should add the [PathNode] to the scene graph.
  final void Function(PathNode node)? onPathNodeCreated;

  /// Fill color for new paths (null = no fill).
  Color? fillColor;

  /// Stroke color for new paths.
  Color strokeColor;

  /// Stroke width for new paths.
  double strokeWidth;

  /// Fill gradient for new paths (null = use fillColor).
  GradientFill? fillGradient;

  /// Stroke cap style.
  StrokeCap strokeCap;

  /// Stroke join style.
  StrokeJoin strokeJoin;

  PenTool({
    this.onPathNodeCreated,
    this.fillColor,
    this.strokeColor = Colors.black,
    this.strokeWidth = 2.0,
    this.fillGradient,
    this.strokeCap = StrokeCap.round,
    this.strokeJoin = StrokeJoin.round,
  });

  // ============================================================================
  // IDENTITY
  // ============================================================================

  @override
  String get toolId => 'pen';

  @override
  IconData get icon => Icons.edit;

  @override
  String get label => 'Pen';

  @override
  String get description => 'Draw Bézier vector paths';

  @override
  bool get hasOverlay => true;

  @override
  bool get requiresExclusiveGesture => false;

  // ============================================================================
  // STATE
  // ============================================================================

  /// Anchors placed so far (in CANVAS coordinates).
  final List<AnchorPoint> _anchors = [];

  /// Current cursor position (in CANVAS coordinates) for rubber-band.
  Offset? _cursorCanvasPosition;

  /// Handle being dragged from the last-placed anchor (CANVAS coords, absolute).
  Offset? _dragHandleCanvas;

  /// Whether the user is currently dragging a handle (tap+drag gesture).
  bool _isDragging = false;

  /// Threshold distance (in screen px) for closing onto the first anchor.
  /// Scales inversely with zoom to feel consistent at any zoom level.
  static const double _baseCloseThreshold = 14.0;

  /// Whether the canvas is in dark mode (affects overlay colors).
  bool isDarkMode = false;

  /// Optional snap callback: receives canvas position, returns snapped position.
  /// Set by the host to enable snap-to-guide.
  Offset Function(Offset canvasPos)? snapPosition;

  /// Minimum distance (screen px) to register as a drag vs. a tap.
  static const double _dragDeadZone = 4.0;

  /// Hit-test radius (screen px) for tapping on an existing anchor.
  static const double _anchorHitRadius = 18.0;

  /// Timestamp of the last pointer-down for double-tap detection.
  int _lastPointerDownMs = 0;

  /// Double-tap threshold in milliseconds.
  static const int _doubleTapMs = 350;

  /// Index of anchor being edited for repositioning (-1 = none).
  int _editingAnchorIndex = -1;

  /// What part of the anchor is being edited.
  _EditTarget _editTarget = _EditTarget.position;

  /// Whether a handle breakout is in progress (corner → symmetric by drag).
  bool _isHandleBreakout = false;

  /// Last anchor index that was tapped (for double-tap deletion).
  int _lastTappedAnchorIndex = -1;

  /// Timestamp of the last anchor tap (for double-tap deletion).
  int _lastAnchorTapMs = 0;

  /// Whether angles should be constrained to 45° increments.
  bool constrainAngles = false;

  // ── A2: Multi-anchor selection ──

  /// Set of selected anchor indices for batch operations.
  Set<int> _selectedAnchorIndices = {};

  /// Long-press threshold in milliseconds.
  static const int _longPressMs = 400;

  /// Whether a long-press timer is pending.
  bool _longPressPending = false;

  /// Timestamp of the current pointer-down (for long-press detection).
  int _pointerDownMs = 0;

  /// Read-only access to selected anchor indices.
  Set<int> get selectedAnchorIndices =>
      Set.unmodifiable(_selectedAnchorIndices);

  // ── A4: Grid snapping ──

  /// Optional grid spacing for anchor snapping (null = off).
  /// When set, new anchors and position drags snap to nearest grid intersection.
  double? gridSpacing;

  /// Whether we are in path-building mode.
  bool get isBuilding => _anchors.isNotEmpty;

  /// Read-only access to current anchors (for testing/inspection).
  List<AnchorPoint> get anchors => List.unmodifiable(_anchors);

  // ============================================================================
  // LIFECYCLE
  // ============================================================================

  @override
  void onActivate(ToolContext context) {
    super.onActivate(context);
    _reset();
  }

  @override
  void onDeactivate(ToolContext context) {
    // If the user switches tools while building, finalize what we have.
    if (_anchors.length >= 2) {
      _finalizePath(context, closed: false);
    }
    _reset();
    super.onDeactivate(context);
  }

  // ============================================================================
  // POINTER EVENTS
  // ============================================================================

  @override
  void onPointerDown(ToolContext context, PointerDownEvent event) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final isDoubleTap = (now - _lastPointerDownMs) < _doubleTapMs;
    _lastPointerDownMs = now;

    // Double-tap → finalize as open path.
    if (isDoubleTap && _anchors.length >= 2) {
      _finalizePath(context, closed: false);
      return;
    }

    beginOperation(context, event.localPosition);
    _isDragging = false;
    _dragHandleCanvas = null;
    _editingAnchorIndex = -1;

    final canvasPos = context.screenToCanvas(event.localPosition);
    _cursorCanvasPosition = canvasPos;

    // Check if tapping near the first anchor to close the path.
    if (_anchors.length >= 3) {
      final firstScreenPos = context.canvasToScreen(_anchors.first.position);
      final tapScreenPos = event.localPosition;
      // Threshold scales inversely with zoom for consistent feel
      final threshold = _baseCloseThreshold / context.scale.clamp(0.1, 10.0);
      if ((firstScreenPos - tapScreenPos).distance <
          threshold * context.scale) {
        _finalizePath(context, closed: true);
        return;
      }
    }

    // #1: Check if tapping near a handle FIRST (higher priority than anchor).
    for (int i = 0; i < _anchors.length; i++) {
      final anchor = _anchors[i];
      // Check handleIn
      final hIn = anchor.handleInAbsolute;
      if (hIn != null) {
        final screenHIn = context.canvasToScreen(hIn);
        if ((screenHIn - event.localPosition).distance < _anchorHitRadius) {
          _editingAnchorIndex = i;
          _editTarget = _EditTarget.handleIn;
          return;
        }
      }
      // Check handleOut
      final hOut = anchor.handleOutAbsolute;
      if (hOut != null) {
        final screenHOut = context.canvasToScreen(hOut);
        if ((screenHOut - event.localPosition).distance < _anchorHitRadius) {
          _editingAnchorIndex = i;
          _editTarget = _EditTarget.handleOut;
          return;
        }
      }
    }

    // Then check if tapping near an existing anchor (for editing/toggle).
    for (int i = 0; i < _anchors.length; i++) {
      final anchorScreenPos = context.canvasToScreen(_anchors[i].position);
      if ((anchorScreenPos - event.localPosition).distance < _anchorHitRadius) {
        // #2: Double-tap on anchor → delete it.
        final now2 = DateTime.now().millisecondsSinceEpoch;
        if (i == _lastTappedAnchorIndex &&
            (now2 - _lastAnchorTapMs) < _doubleTapMs) {
          _anchors.removeAt(i);
          // Update multi-selection indices after removal.
          _selectedAnchorIndices.remove(i);
          final adjusted =
              _selectedAnchorIndices
                  .map((idx) => idx > i ? idx - 1 : idx)
                  .toSet();
          _selectedAnchorIndices
            ..clear()
            ..addAll(adjusted);
          HapticFeedback.mediumImpact();
          _lastTappedAnchorIndex = -1;
          _lastAnchorTapMs = 0;
          state = ToolOperationState.idle;
          currentCanvasPosition = null;
          startCanvasPosition = null;
          lastScreenPosition = null;
          return;
        }
        _lastTappedAnchorIndex = i;
        _lastAnchorTapMs = now2;

        // Start long-press timer for multi-select.
        _pointerDownMs = now;
        _longPressPending = true;

        _editingAnchorIndex = i;
        _editTarget = _EditTarget.position;
        _isHandleBreakout = false;
        return;
      }
    }

    // A1: Check if tapping on a segment (insert anchor via De Casteljau).
    if (_anchors.length >= 2) {
      final result = _hitTestSegments(canvasPos, context);
      if (result != null) {
        final (segmentIndex, t) = result;
        _insertAnchorOnSegment(segmentIndex, t);
        HapticFeedback.mediumImpact();
        state = ToolOperationState.idle;
        currentCanvasPosition = null;
        startCanvasPosition = null;
        lastScreenPosition = null;
        return;
      }
    }

    // Tap on empty area clears multi-selection.
    if (_selectedAnchorIndices.isNotEmpty) {
      _selectedAnchorIndices.clear();
    }
  }

  @override
  void onPointerMove(ToolContext context, PointerMoveEvent event) {
    if (state == ToolOperationState.idle) {
      // Not in an operation — just track cursor for rubber-band.
      _cursorCanvasPosition = context.screenToCanvas(event.localPosition);
      return;
    }

    continueOperation(context, event.localPosition);

    final canvasPos = context.screenToCanvas(event.localPosition);
    _cursorCanvasPosition = canvasPos;

    // Cancel long-press if user moves beyond dead zone.
    if (_longPressPending) {
      final dist =
          (event.localPosition - _screenPosFromCanvasStart(context)).distance;
      if (dist > _dragDeadZone) {
        _longPressPending = false;
      }
    }

    // #1: Editing anchor or handle — drag to reposition.
    if (_editingAnchorIndex >= 0) {
      final anchor = _anchors[_editingAnchorIndex];
      var snapped = _applySnapping(canvasPos);

      switch (_editTarget) {
        case _EditTarget.position:
          // Handle breakout: dragging from a corner anchor creates handles.
          if (anchor.type == AnchorType.corner &&
              anchor.handleIn == null &&
              anchor.handleOut == null) {
            final dist =
                (event.localPosition - _screenPosFromCanvasStart(context))
                    .distance;
            if (dist > _dragDeadZone) {
              _isHandleBreakout = true;
              _editTarget = _EditTarget.handleOut;
              // Apply constraint if needed.
              if (constrainAngles) {
                snapped = _constrainTo45(snapped, anchor.position);
              }
              final handleOffset = snapped - anchor.position;
              anchor.handleOut = handleOffset;
              anchor.handleIn = -handleOffset;
              anchor.type = AnchorType.symmetric;
              return;
            }
          }
          // A2: Batch move selected anchors.
          if (_selectedAnchorIndices.contains(_editingAnchorIndex) &&
              _selectedAnchorIndices.length > 1) {
            final delta = snapped - anchor.position;
            for (final idx in _selectedAnchorIndices) {
              _anchors[idx].position += delta;
            }
          } else {
            anchor.position = snapped;
          }
          break;
        case _EditTarget.handleOut:
          // #3: Constrain handle angles.
          if (constrainAngles) {
            snapped = _constrainTo45(snapped, anchor.position);
          }
          anchor.handleOut = snapped - anchor.position;
          // Symmetric: mirror handleIn
          if (anchor.type == AnchorType.symmetric) {
            anchor.handleIn = -(snapped - anchor.position);
          } else if (anchor.type == AnchorType.smooth &&
              anchor.handleIn != null) {
            // Smooth: keep colinear, preserve length
            final len = anchor.handleIn!.distance;
            final dir = -(snapped - anchor.position);
            anchor.handleIn = dir / dir.distance * len;
          }
          break;
        case _EditTarget.handleIn:
          // #3: Constrain handle angles.
          if (constrainAngles) {
            snapped = _constrainTo45(snapped, anchor.position);
          }
          anchor.handleIn = snapped - anchor.position;
          // Symmetric: mirror handleOut
          if (anchor.type == AnchorType.symmetric) {
            anchor.handleOut = -(snapped - anchor.position);
          } else if (anchor.type == AnchorType.smooth &&
              anchor.handleOut != null) {
            final len = anchor.handleOut!.distance;
            final dir = -(snapped - anchor.position);
            anchor.handleOut = dir / dir.distance * len;
          }
          break;
      }
      return;
    }

    // Detect drag (beyond dead zone → user wants a curve handle).
    if (!_isDragging && startCanvasPosition != null) {
      if ((event.localPosition - _screenPosFromCanvasStart(context)).distance >
          _dragDeadZone) {
        _isDragging = true;
      }
    }

    if (_isDragging) {
      // #3: Constrain drag handle angles.
      if (constrainAngles && startCanvasPosition != null) {
        _dragHandleCanvas = _constrainTo45(canvasPos, startCanvasPosition!);
      } else {
        _dragHandleCanvas = canvasPos;
      }
    }
  }

  @override
  void onPointerUp(ToolContext context, PointerUpEvent event) {
    if (state == ToolOperationState.idle) return;

    final canvasPos = context.screenToCanvas(event.localPosition);

    // #1/#2: Editing an existing anchor or handle.
    if (_editingAnchorIndex >= 0) {
      final dist =
          (event.localPosition - _screenPosFromCanvasStart(context)).distance;
      if (_editTarget == _EditTarget.position && dist < _dragDeadZone) {
        // A2: Long-press on anchor → toggle multi-selection.
        final elapsed = DateTime.now().millisecondsSinceEpoch - _pointerDownMs;
        if (_longPressPending && elapsed >= _longPressMs) {
          if (_selectedAnchorIndices.contains(_editingAnchorIndex)) {
            _selectedAnchorIndices.remove(_editingAnchorIndex);
          } else {
            _selectedAnchorIndices.add(_editingAnchorIndex);
          }
          HapticFeedback.mediumImpact();
        } else {
          // #2: Tap without drag on anchor → toggle smooth/corner.
          final anchor = _anchors[_editingAnchorIndex];
          if (anchor.type == AnchorType.corner) {
            anchor.type = AnchorType.smooth;
          } else {
            anchor.type = AnchorType.corner;
            anchor.handleIn = null;
            anchor.handleOut = null;
          }
          HapticFeedback.selectionClick();
        }
      } else {
        // Was dragged — position/handle already updated in onPointerMove.
        HapticFeedback.lightImpact();
      }
      _longPressPending = false;
      _editingAnchorIndex = -1;
      _editTarget = _EditTarget.position;
      _isHandleBreakout = false;
      state = ToolOperationState.idle;
      currentCanvasPosition = null;
      startCanvasPosition = null;
      lastScreenPosition = null;
      return;
    }

    if (_isDragging && startCanvasPosition != null) {
      // Tap + drag → smooth anchor with symmetric handles.
      final rawAnchorPos = startCanvasPosition!;
      final anchorPos = _applySnapping(rawAnchorPos);
      final handleOut = canvasPos - anchorPos; // Relative offset.
      final handleIn = Offset(-handleOut.dx, -handleOut.dy); // Mirror.

      _anchors.add(
        AnchorPoint(
          position: anchorPos,
          handleIn: _anchors.isEmpty ? null : handleIn,
          handleOut: handleOut,
          type: AnchorType.symmetric,
        ),
      );
    } else {
      // Simple tap → corner anchor (straight line).
      final rawPos = startCanvasPosition ?? canvasPos;
      var snappedPos = _applySnapping(rawPos);

      // #3: Constrained angles — snap to 45° multiples.
      if (constrainAngles && _anchors.isNotEmpty) {
        snappedPos = _constrainTo45(snappedPos, _anchors.last.position);
      }

      _anchors.add(AnchorPoint(position: snappedPos, type: AnchorType.corner));
    }

    _isDragging = false;
    _dragHandleCanvas = null;
    _cursorCanvasPosition = canvasPos;

    // 📳 Haptic feedback on anchor placement
    HapticFeedback.lightImpact();

    // Reset operation state but keep anchors.
    state = ToolOperationState.idle;
    currentCanvasPosition = null;
    startCanvasPosition = null;
    lastScreenPosition = null;
  }

  @override
  void onPointerCancel(ToolContext context) {
    _isDragging = false;
    _dragHandleCanvas = null;
    state = ToolOperationState.idle;
  }

  // ============================================================================
  // KEYBOARD EVENTS
  // ============================================================================

  /// Call this from the host widget's key handler.
  /// Returns true if the event was consumed.
  bool handleKeyEvent(KeyEvent event, ToolContext context) {
    if (event is! KeyDownEvent) return false;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _reset();
      return true;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_anchors.length >= 2) {
        _finalizePath(context, closed: false);
        return true;
      }
    }

    // Backspace / Delete → remove last anchor.
    if (event.logicalKey == LogicalKeyboardKey.backspace ||
        event.logicalKey == LogicalKeyboardKey.delete) {
      if (_anchors.isNotEmpty) {
        _anchors.removeLast();
        return true;
      }
    }

    return false;
  }

  // ============================================================================
  // OVERLAY
  // ============================================================================

  @override
  Widget? buildOverlay(ToolContext context) {
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
    final closeThreshold = _baseCloseThreshold;
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

  // ============================================================================
  // TOOL OPTIONS
  // ============================================================================

  /// Whether to show the curvature comb visualization.
  bool showCurvatureComb = false;

  /// Callback for when the host should trigger setState after tool option changes.
  VoidCallback? onToolOptionsChanged;

  /// ToolContext provided by the host for finalize operations from touch UI.
  ToolContext? toolOptionsContext;

  /// Public method to finalize as open path (used by touch UI).
  void finalizeOpenPath(ToolContext context) {
    if (_anchors.length >= 2) _finalizePath(context, closed: false);
  }

  /// Public method to finalize as closed path (used by touch UI).
  void finalizeClosedPath(ToolContext context) {
    if (_anchors.length >= 3) _finalizePath(context, closed: true);
  }

  /// Public method to remove the last anchor (used by touch UI).
  void undoLastAnchor() {
    if (_anchors.isNotEmpty) {
      _anchors.removeLast();
      HapticFeedback.selectionClick();
    }
  }

  /// Public method to cancel the current path (used by touch UI).
  void cancelPath() {
    _reset();
    HapticFeedback.lightImpact();
  }

  @override
  Widget? buildToolOptions(BuildContext buildContext) {
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
                    _actionButton(
                      icon: Icons.undo_rounded,
                      tooltip: 'Undo',
                      onTap: () {
                        undoLastAnchor();
                        onToolOptionsChanged?.call();
                      },
                    ),

                    // Cancel path
                    _actionButton(
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
                      _actionButton(
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
                      _actionButton(
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
  Widget _actionButton({
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

  // ============================================================================
  // SERIALIZATION
  // ============================================================================

  @override
  Map<String, dynamic> saveConfig() => {
    'strokeColor': strokeColor.toARGB32(),
    'strokeWidth': strokeWidth,
    'fillColor': fillColor?.toARGB32(),
    'strokeCap': strokeCap.index,
    'strokeJoin': strokeJoin.index,
  };

  @override
  void loadConfig(Map<String, dynamic> config) {
    if (config['strokeColor'] != null) {
      strokeColor = Color(config['strokeColor']);
    }
    strokeWidth = (config['strokeWidth'] ?? 2.0).toDouble();
    if (config['fillColor'] != null) {
      fillColor = Color(config['fillColor']);
    }
    if (config['strokeCap'] != null) {
      strokeCap = StrokeCap.values[config['strokeCap']];
    }
    if (config['strokeJoin'] != null) {
      strokeJoin = StrokeJoin.values[config['strokeJoin']];
    }
  }

  // ============================================================================
  // PRIVATE HELPERS
  // ============================================================================

  /// Finalize the path: convert anchors → VectorPath → PathNode.
  void _finalizePath(ToolContext context, {required bool closed}) {
    if (_anchors.length < 2) {
      _reset();
      return;
    }

    context.saveUndoState();

    final vectorPath = AnchorPoint.toVectorPath(_anchors, closed: closed);

    final pathNode = PathNode(
      id: const Uuid().v4(),
      path: vectorPath,
      name: 'Path',
      fillColor: fillColor,
      fillGradient: fillGradient,
      strokeColor: strokeColor,
      strokeWidth: strokeWidth,
      strokeCap: strokeCap,
      strokeJoin: strokeJoin,
    );

    onPathNodeCreated?.call(pathNode);

    // 📳 Haptic feedback on path finalization
    HapticFeedback.mediumImpact();

    context.notifyOperationComplete();
    _reset();
  }

  /// Reset all in-progress state.
  void _reset() {
    _anchors.clear();
    _cursorCanvasPosition = null;
    _dragHandleCanvas = null;
    _isDragging = false;
    _editingAnchorIndex = -1;
    _editTarget = _EditTarget.position;
    _isHandleBreakout = false;
    _lastTappedAnchorIndex = -1;
    _lastAnchorTapMs = 0;
    _selectedAnchorIndices.clear();
    _longPressPending = false;
    state = ToolOperationState.idle;
  }

  /// Convert an AnchorPoint from canvas coordinates to screen coordinates.
  AnchorPoint _anchorToScreen(AnchorPoint anchor, ToolContext context) {
    final screenPos = context.canvasToScreen(anchor.position);

    Offset? screenHandleIn;
    if (anchor.handleIn != null) {
      final absIn = anchor.position + anchor.handleIn!;
      final screenAbsIn = context.canvasToScreen(absIn);
      screenHandleIn = screenAbsIn - screenPos;
    }

    Offset? screenHandleOut;
    if (anchor.handleOut != null) {
      final absOut = anchor.position + anchor.handleOut!;
      final screenAbsOut = context.canvasToScreen(absOut);
      screenHandleOut = screenAbsOut - screenPos;
    }

    return AnchorPoint(
      position: screenPos,
      handleIn: screenHandleIn,
      handleOut: screenHandleOut,
      type: anchor.type,
    );
  }

  /// Get the screen position of startCanvasPosition.
  Offset _screenPosFromCanvasStart(ToolContext context) {
    return startCanvasPosition != null
        ? context.canvasToScreen(startCanvasPosition!)
        : Offset.zero;
  }

  /// #3: Constrain [pos] to the nearest 45° angle relative to [ref].
  static Offset _constrainTo45(Offset pos, Offset ref) {
    final delta = pos - ref;
    final distance = delta.distance;
    if (distance < 1.0) return pos;

    // Snap angle to nearest 45° (0, 45, 90, 135, 180, 225, 270, 315).
    final angle = delta.direction; // radians, -pi to pi
    const step = 3.14159265358979 / 4; // 45°
    final snapped = (angle / step).round() * step;

    return ref + Offset.fromDirection(snapped, distance);
  }

  // ============================================================================
  // A1: SEGMENT HIT-TEST & INSERTION
  // ============================================================================

  /// Hit-test all segments to find if [canvasPos] is near a curve.
  /// Returns `(segmentIndex, t)` or null.
  (int, double)? _hitTestSegments(Offset canvasPos, ToolContext context) {
    const int samples = 20;
    double bestDist = double.infinity;
    int bestSeg = -1;
    double bestT = 0;

    for (int i = 0; i < _anchors.length - 1; i++) {
      final a = _anchors[i];
      final b = _anchors[i + 1];

      final p0 = a.position;
      final p1 = a.handleOutAbsolute ?? p0;
      final p2 = b.handleInAbsolute ?? b.position;
      final p3 = b.position;

      for (int s = 0; s <= samples; s++) {
        final t = s / samples;
        final pt = _cubicAt(t, p0, p1, p2, p3);
        final screenPt = context.canvasToScreen(pt);
        final screenTap = context.canvasToScreen(canvasPos);
        final dist = (screenPt - screenTap).distance;
        if (dist < bestDist) {
          bestDist = dist;
          bestSeg = i;
          bestT = t;
        }
      }
    }

    if (bestDist < _anchorHitRadius && bestSeg >= 0) {
      return (bestSeg, bestT);
    }
    return null;
  }

  /// Insert a new anchor on segment [segIndex] at parameter [t]
  /// using De Casteljau subdivision.
  void _insertAnchorOnSegment(int segIndex, double t) {
    final a = _anchors[segIndex];
    final b = _anchors[segIndex + 1];

    final p0 = a.position;
    final p1 = a.handleOutAbsolute ?? p0;
    final p2 = b.handleInAbsolute ?? b.position;
    final p3 = b.position;

    // De Casteljau split at t.
    final q0 = _lerpOffset(p0, p1, t);
    final q1 = _lerpOffset(p1, p2, t);
    final q2 = _lerpOffset(p2, p3, t);
    final r0 = _lerpOffset(q0, q1, t);
    final r1 = _lerpOffset(q1, q2, t);
    final s0 = _lerpOffset(r0, r1, t); // point on curve

    // Update anchor A: new handleOut = q0 - p0
    a.handleOut = q0 - p0;

    // Update anchor B: new handleIn = q2 - p3
    b.handleIn = q2 - p3;

    // Create new anchor at s0 with handles r0 and r1.
    final newAnchor = AnchorPoint(
      position: s0,
      handleIn: r0 - s0,
      handleOut: r1 - s0,
      type: AnchorType.smooth,
    );

    _anchors.insert(segIndex + 1, newAnchor);

    // Adjust multi-selection indices.
    final adjusted =
        _selectedAnchorIndices
            .map((idx) => idx > segIndex ? idx + 1 : idx)
            .toSet();
    _selectedAnchorIndices
      ..clear()
      ..addAll(adjusted);
  }

  /// Cubic Bézier point at parameter [t].
  static Offset _cubicAt(double t, Offset p0, Offset p1, Offset p2, Offset p3) {
    final mt = 1.0 - t;
    return p0 * (mt * mt * mt) +
        p1 * (3 * mt * mt * t) +
        p2 * (3 * mt * t * t) +
        p3 * (t * t * t);
  }

  /// Linear interpolation between two offsets.
  static Offset _lerpOffset(Offset a, Offset b, double t) {
    return Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t);
  }

  // ============================================================================
  // A4: GRID + GUIDE SNAPPING PIPELINE
  // ============================================================================

  /// Apply all snapping stages: grid first, then guide callback.
  Offset _applySnapping(Offset pos) {
    var snapped = pos;

    // Grid snap.
    if (gridSpacing != null && gridSpacing! > 0) {
      final g = gridSpacing!;
      snapped = Offset(
        (snapped.dx / g).roundToDouble() * g,
        (snapped.dy / g).roundToDouble() * g,
      );
    }

    // Guide snap callback.
    snapped = snapPosition?.call(snapped) ?? snapped;

    return snapped;
  }
}
