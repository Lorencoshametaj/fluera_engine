import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../utils/uid.dart';
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

/// Cursor feedback hint — indicates what action will occur on click.
enum PenCursorHint {
  /// No hint (cursor not in a meaningful area).
  none,

  /// Will add a new anchor point.
  addPoint,

  /// Will edit an existing anchor (reposition, handles).
  editAnchor,

  /// Will close the path (near first anchor with ≥3 points).
  closePath,

  /// Will insert a point on an existing segment.
  addOnSegment,
}

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
    this.onPathNodeEdited,
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

  // ── Handle double-tap tracking ──

  /// Last handle tap: anchor index.
  int _lastTappedHandleIndex = -1;

  /// Whether the last handle tap was on handleIn (true) or handleOut (false).
  bool _lastTappedHandleIsIn = false;

  /// Timestamp of the last handle tap.
  int _lastHandleTapMs = 0;

  // ── Alt key for handle break ──

  /// Whether the Alt/Option key is currently held down.
  bool _altKeyDown = false;

  // ── Edit existing PathNode ──

  /// Whether we are editing an existing PathNode (vs creating new).
  bool _isEditingExisting = false;

  /// ID of the PathNode being edited (null when creating new).
  String? _editingNodeId;

  /// Callback invoked when the user finishes editing an existing path.
  final void Function(String nodeId, PathNode updatedNode)? onPathNodeEdited;

  // ── Context menu state ──

  /// Anchor index for the context menu (-1 = none).
  int _contextMenuAnchorIndex = -1;

  /// Whether to show the anchor context menu popup.
  bool _showAnchorContextMenu = false;

  /// Segment index for the segment context menu (-1 = none).
  int _contextMenuSegmentIndex = -1;

  /// Whether to show the segment context menu popup.
  bool _showSegmentContextMenu = false;

  // ── Cursor feedback hint ──

  /// Current cursor hint for visual feedback.
  PenCursorHint _cursorHint = PenCursorHint.none;

  /// Whether we are in path-building mode.
  bool get isBuilding => _anchors.isNotEmpty;

  /// Whether we are editing an existing PathNode.
  bool get isEditingExisting => _isEditingExisting;

  /// Read-only access to current anchors (for testing/inspection).
  List<AnchorPoint> get anchors => List.unmodifiable(_anchors);

  /// Current cursor hint.
  PenCursorHint get cursorHint => _cursorHint;

  /// Whether the anchor context menu is visible.
  bool get showAnchorContextMenu => _showAnchorContextMenu;

  /// Index of anchor for context menu.
  int get contextMenuAnchorIndex => _contextMenuAnchorIndex;

  /// Whether the segment context menu is visible.
  bool get showSegmentContextMenu => _showSegmentContextMenu;

  /// Index of segment for context menu.
  int get contextMenuSegmentIndex => _contextMenuSegmentIndex;

  /// Set selected anchor indices for testing.
  @visibleForTesting
  void setSelectedAnchorsForTest(Set<int> indices) {
    _selectedAnchorIndices
      ..clear()
      ..addAll(indices);
  }

  /// Insert an anchor on a segment for testing.
  @visibleForTesting
  void insertAnchorOnSegmentForTest(int segIndex, double t) {
    insertAnchorOnSegment(segIndex, t);
  }

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

  /// Public method to delete selected anchors (used by touch UI).
  void deleteSelectedAnchors() {
    if (_selectedAnchorIndices.isNotEmpty) {
      _deleteAnchors(Set<int>.from(_selectedAnchorIndices));
      HapticFeedback.mediumImpact();
    }
  }

  /// Public method to reverse path direction (used by touch UI).
  void reversePathDirection() {
    if (_anchors.length >= 2) {
      _reversePath();
      HapticFeedback.selectionClick();
    }
  }

  /// Public method to cycle anchor type at [index] (used by touch UI).
  void cycleAnchorTypeAt(int index) {
    if (index >= 0 && index < _anchors.length) {
      _cycleAnchorType(_anchors[index], index);
      HapticFeedback.selectionClick();
    }
  }

  /// Public method to equalize handles at [index] (used by touch UI).
  void equalizeHandlesAt(int index) {
    if (index >= 0 && index < _anchors.length) {
      _equalizeHandles(index);
      HapticFeedback.selectionClick();
    }
  }

  /// Public method to auto-smooth all anchors (used by touch UI).
  void autoSmooth() {
    if (_anchors.length >= 2) {
      _autoSmooth();
      HapticFeedback.mediumImpact();
    }
  }

  /// Public method to delete a segment (split path).
  void splitPathAtSegment(int segIndex, ToolContext context) {
    if (segIndex >= 0 && segIndex < _anchors.length - 1) {
      _deleteSegment(segIndex, context);
      HapticFeedback.heavyImpact();
    }
  }

  /// Dismiss any visible context menu.
  void dismissContextMenu() {
    _showAnchorContextMenu = false;
    _showSegmentContextMenu = false;
    _contextMenuAnchorIndex = -1;
    _contextMenuSegmentIndex = -1;
  }

  // ============================================================================
  // ✏️ EDIT EXISTING PATHNODE
  // ============================================================================

  /// Enter edit mode for an existing [PathNode].
  ///
  /// Extracts anchors from the node's VectorPath and loads them
  /// into the tool state so the user can modify anchor points,
  /// handles, and then re-finalize to update the node in place.
  void editPathNode(PathNode node) {
    _reset();
    final extracted = AnchorPoint.fromVectorPath(node.path);
    _anchors.addAll(extracted);

    // Copy visual properties.
    fillColor = node.fillColor;
    fillGradient = node.fillGradient;
    strokeColor = node.strokeColor ?? Colors.black;
    strokeWidth = node.strokeWidth;
    strokeCap = node.strokeCap;
    strokeJoin = node.strokeJoin;

    // Mark as editing existing.
    _isEditingExisting = true;
    _editingNodeId = node.id;

    HapticFeedback.mediumImpact();
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

  void _deleteAnchors(Set<int> indices) => deleteAnchorsByIndex(indices);

  void _reversePath() => reversePath();

  void _equalizeHandles(int index) => equalizeHandles(index);

  void _cycleAnchorType(AnchorPoint anchor, int index) =>
      cycleAnchorType(anchor, index);

  void _deleteSegment(int segIndex, ToolContext context) =>
      deleteSegment(segIndex, context);

  void _autoSmooth({double tension = 0.5}) => autoSmoothPath(tension: tension);
}
