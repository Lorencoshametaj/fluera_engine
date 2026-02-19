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

part 'pen_tool_input.dart';
part 'pen_tool_ui.dart';
part 'pen_tool_geometry.dart';

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
///
/// STRUCTURE (part files):
/// - [pen_tool_input.dart]    — pointer + keyboard handlers
/// - [pen_tool_ui.dart]       — overlay + tool options widgets
/// - [pen_tool_geometry.dart] — path math, hit-testing, snapping

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

  /// Preview anchor built during tap+drag (not yet committed).
  /// Used to show the live Bézier curve shape before releasing.
  AnchorPoint? _previewAnchor;

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
  // POINTER EVENTS — delegate to _PenToolInput extension
  // ============================================================================

  @override
  void onPointerDown(ToolContext context, PointerDownEvent event) =>
      handlePointerDown(context, event);

  @override
  void onPointerMove(ToolContext context, PointerMoveEvent event) =>
      handlePointerMove(context, event);

  @override
  void onPointerUp(ToolContext context, PointerUpEvent event) =>
      handlePointerUp(context, event);

  @override
  void onPointerCancel(ToolContext context) => handlePointerCancel(context);

  // ============================================================================
  // KEYBOARD — delegate to _PenToolInput extension
  // ============================================================================

  /// Call this from the host widget's key handler.
  /// Returns true if the event was consumed.
  bool handleKeyEvent(KeyEvent event, ToolContext context) =>
      handleKeyboardEvent(event, context);

  // ============================================================================
  // OVERLAY — delegate to _PenToolUI extension
  // ============================================================================

  @override
  Widget? buildOverlay(ToolContext context) => buildPenOverlay(context);

  // ============================================================================
  // TOOL OPTIONS — delegate to _PenToolUI extension
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
  Widget? buildToolOptions(BuildContext buildContext) =>
      buildPenToolOptions(buildContext);

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
  // PRIVATE DELEGATES — thin wrappers for extension methods
  // ============================================================================

  void _finalizePath(ToolContext context, {required bool closed}) =>
      finalizePath(context, closed: closed);

  void _reset() => resetState();

  AnchorPoint _anchorToScreen(AnchorPoint anchor, ToolContext context) =>
      anchorToScreen(anchor, context);

  Offset _screenPosFromCanvasStart(ToolContext context) =>
      screenPosFromCanvasStart(context);

  static Offset _constrainTo45(Offset pos, Offset ref) {
    final delta = pos - ref;
    final distance = delta.distance;
    if (distance < 1.0) return pos;
    final angle = delta.direction;
    const step = 3.14159265358979 / 4;
    final snapped = (angle / step).round() * step;
    return ref + Offset.fromDirection(snapped, distance);
  }

  (int, double)? _hitTestSegments(Offset canvasPos, ToolContext context) =>
      hitTestSegments(canvasPos, context);

  void _insertAnchorOnSegment(int segIndex, double t) =>
      insertAnchorOnSegment(segIndex, t);

  Offset _applySnapping(Offset pos) => applySnapping(pos);
}
