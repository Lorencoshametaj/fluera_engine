import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import '../../utils/key_value_store.dart';
import '../../drawing/models/pro_drawing_point.dart';
import '../../core/models/shape_type.dart';
import '../../layers/fluera_layer_controller.dart';
import 'eraser_hit_tester.dart';
import 'eraser_spatial_index.dart';
import 'eraser_analytics.dart';
import 'eraser_preset_manager.dart';

/// V5: Pressure curve types for eraser radius mapping
enum EraserPressureCurve { linear, easeIn, easeOut, easeInOut, custom }

/// 🎨 ERASER TOOL — Professional canvas eraser
///
/// Features:
/// - Partial stroke erasing (splits strokes at intersection)
/// - Eraser preview (highlights strokes under cursor)
/// - Segment-to-circle intersection (catches strokes between sparse points)
/// - Undo support with split-stroke awareness
/// - Configureble radius with visual cursor overlay
/// - Pressure-sensitive radius
/// - Radius persistence via SharedPreferences
/// - Haptic feedback (light on erase, medium on undo)
/// - V4: Layer-aware erasing, protected regions, color filter, lasso erase
/// - V5: Spatial index, pressure curve, drag-line erasing
/// - V6: Analytics, erase-to-reveal, auto-clean, stroke-by-stroke mode
/// - V7: Shape modes, smart selection, edge-aware, presets
/// - V8: Velocity-adaptive, tilt rotation, path prediction
/// - V9: Opacity erase, batch operations, redo, fragment tapering
/// - V10: Auto-complete, erase mask
///
/// ARCHITECTURE:
/// Delegates subsystems to extracted classes:
/// - [EraserHitTester] — pure geometry (static methods)
/// - [EraserSpatialIndex] — grid-based O(1) stroke lookup
/// - [EraserAnalytics] — session tracking, heatmap, dissolve effects
/// - [EraserPresetManager] — save/load/delete named configurations
class EraserTool {
  final FlueraLayerController layerController;

  // ─── Configuretion ─────────────────────────────────────────────────
  double eraserRadius;
  bool eraseWholeStroke;

  /// V4: Erase only strokes matching this color (null = erase all)
  ui.Color? eraseByColor;

  /// V4: Erase across all visible layers (not just active)
  bool eraseAllLayers;

  /// V4: Magnetic snap — cursor guided toward nearest stroke
  bool magneticSnap;

  /// V4: Feathered edge — soft erasure at the border
  bool featheredEdge;

  /// V4: Protected regions — rectangular no-erase zones
  final List<ui.Rect> protectedRegions = [];

  /// V5: Pressure curve for radius mapping
  EraserPressureCurve pressureCurve;

  /// V5: Custom pressure curve exponent (used when pressureCurve is easeIn/easeOut)
  double pressureCurveExponent;

  // ─── V6 Configuretion ────────────────────────────────────────────
  /// V6: Stroke-by-stroke mode — tap to select and erase individual strokes
  bool strokeByStrokeMode = false;

  /// V6: Erase-to-reveal (scratch-card) — erase top layer to show below
  bool eraseToReveal = false;

  /// V6: Auto-clean mode — highlight short/orphan strokes as suggestions
  bool autoCleanMode = false;
  double autoCleanMinLength = 15.0;
  double autoCleanOrphanRadius = 80.0;

  // ─── V7 Configuretion ────────────────────────────────────────────
  /// V7: Eraser shape mode
  EraserShape eraserShape = EraserShape.circle;

  /// V7: Rectangle eraser width (when shape == rectangle)
  double eraserShapeWidth = 30.0;

  /// V7: Eraser shape rotation angle in radians
  double eraserShapeAngle = 0.0;

  /// V7: Smart selection mode — long-press preview + confirm erase
  bool smartSelectionMode = false;

  /// V7: Currently selected stroke ID for smart selection
  String? smartSelectedStrokeId;

  /// V7: Undo ghost replay — strokes being animated back in
  final List<ProStroke> _undoGhostStrokes = [];
  double undoGhostProgress = 0.0;

  /// V7: Custom pressure curve Bézier control points
  List<Offset> pressureCurveControlPoints = [
    const Offset(0.25, 0.1),
    const Offset(0.75, 0.9),
  ];

  /// V7: Layer-specific preview mode — dim non-active layers
  bool layerPreviewMode = false;

  // ─── V8 Configuretion ────────────────────────────────────────────
  /// V8: Velocity-adaptive radius
  bool velocityAdaptiveRadius = false;
  double _velocityRadiusMin = 0.6;
  double _velocityRadiusMax = 1.8;
  double _velocityThreshold = 3.0;

  /// V8: Stylus tilt → shape rotation
  bool stylusTiltRotation = true;

  /// V8: Path-predictive erasing
  bool pathPredictiveMode = false;
  final List<Offset> _recentPositions = [];
  static const int _predictiveWindowSize = 5;
  static const double _predictiveExtension = 15.0;

  // ─── V9 Configuretion ────────────────────────────────────────────
  /// V9: Opacity erase mode — reduce alpha instead of removing strokes
  bool opacityEraseMode = false;
  double opacityEraseStrength = 0.3;

  /// V9: Multi-stroke smart selection — select multiple strokes in radius
  final Set<String> smartSelectedStrokeIds = {};

  /// V9: Last erase bounding rect — for dirty rect tile invalidation
  Rect? lastEraseBounds;

  /// V9: Eraser state preservation for zoom continuity
  Offset? _savedEraserPosition;
  double? _savedEraserRadius;

  // ─── V10 Configuretion ────────────────────────────────────────────
  /// V10: Auto-complete threshold — remove fragments with <threshold% of original
  double autoCompleteThreshold = 0.2;

  /// V10: Erase session mask — track all erase positions
  final List<Offset> eraseMaskPositions = [];

  // ─── Extracted subsystems ──────────────────────────────────────────
  final EraserSpatialIndex _spatialIndex = EraserSpatialIndex();
  final EraserAnalytics analytics = EraserAnalytics();

  /// Minimum and maximum radius for the eraser (for slider bounds).
  static const double minRadius = 5.0;
  static const double maxRadius = 80.0;

  /// SharedPreferences key for persisting radius.
  static const String _radiusPrefKey = 'eraser_radius';

  // ─── Undo Support ──────────────────────────────────────────────────
  final List<_EraseOperation> _currentGestureOps = [];
  final List<List<_EraseOperation>> _undoStack = [];
  static const int _maxUndoStack = 30;

  /// V9: Redo stack
  final List<List<_EraseOperation>> _redoStack = [];

  bool _gestureDidErase = false;
  int _currentGestureEraseCount = 0;

  // ─── Callbacks ─────────────────────────────────────────────────────
  VoidCallback? onEraseComplete;

  EraserTool({
    required this.layerController,
    this.eraserRadius = 20.0,
    this.eraseWholeStroke = false,
    this.eraseByColor,
    this.eraseAllLayers = false,
    this.magneticSnap = false,
    this.featheredEdge = false,
    this.pressureCurve = EraserPressureCurve.linear,
    this.pressureCurveExponent = 2.0,
    this.onEraseComplete,
  });

  // ═══════════════════════════════════════════════════════════════════
  // RADIUS PERSISTENCE
  // ═══════════════════════════════════════════════════════════════════

  Future<void> loadPersistedRadius() async {
    final prefs = await KeyValueStore.getInstance();
    final saved = prefs.getDouble(_radiusPrefKey);
    if (saved != null) {
      eraserRadius = saved.clamp(minRadius, maxRadius);
    }
  }

  Future<void> persistRadius() async {
    final prefs = await KeyValueStore.getInstance();
    await prefs.setDouble(_radiusPrefKey, eraserRadius);
  }

  // ═══════════════════════════════════════════════════════════════════
  // GESTURE LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════

  bool get isGestureActive => _gestureDidErase || _currentGestureOps.isNotEmpty;

  void beginGesture() {
    _currentGestureOps.clear();
    _gestureDidErase = false;
    _currentGestureEraseCount = 0;
    analytics.startSession();
  }

  void endGesture() {
    if (_currentGestureOps.isNotEmpty) {
      _undoStack.add(List<_EraseOperation>.from(_currentGestureOps));
      if (_undoStack.length > _maxUndoStack) {
        _undoStack.removeAt(0);
      }
      _redoStack.clear();
      _currentGestureOps.clear();
      _gestureDidErase = true;
    }
    if (_gestureDidErase) {
      onEraseComplete?.call();
      analytics.takeSnapshot(layerController.activeLayer?.strokes.length ?? 0);
    }
    analytics.endSession();
  }

  int get currentGestureEraseCount => _currentGestureEraseCount;

  // ═══════════════════════════════════════════════════════════════════
  // UNDO
  // ═══════════════════════════════════════════════════════════════════

  bool get canUndo => _undoStack.isNotEmpty;
  int get undoStackDepth => _undoStack.length;

  void undo() {
    if (_undoStack.isEmpty) return;
    final ops = _undoStack.removeLast();
    _redoStack.add(ops);

    for (final op in ops.reversed) {
      for (final frag in op.addedFragments) {
        final idx = layerController.activeLayer?.strokes.indexWhere(
          (s) => s.id == frag.id,
        );
        if (idx != null && idx >= 0) {
          layerController.removeStrokeAt(idx);
        }
      }
      layerController.addStroke(op.removedStroke);
    }
    HapticFeedback.mediumImpact();
  }

  bool get canRedo => _redoStack.isNotEmpty;

  void redo() {
    if (_redoStack.isEmpty) return;
    final ops = _redoStack.removeLast();

    for (final op in ops) {
      final idx = layerController.activeLayer?.strokes.indexWhere(
        (s) => s.id == op.removedStroke.id,
      );
      if (idx != null && idx >= 0) {
        layerController.removeStrokeAt(idx);
      }
      for (final frag in op.addedFragments) {
        layerController.addStroke(frag);
      }
    }

    _undoStack.add(ops);
    HapticFeedback.lightImpact();
    _spatialIndex.markDirty();
  }

  void undoMultiple(int count) {
    for (int i = 0; i < count && canUndo; i++) {
      undo();
    }
  }

  int undoNearby(Offset position, {double radius = 60.0}) {
    if (_undoStack.isEmpty) return 0;
    int undoneCount = 0;
    final radiusSq = radius * radius;

    for (int s = _undoStack.length - 1; s >= 0; s--) {
      final ops = _undoStack[s];
      bool anyNearby = false;

      for (final op in ops) {
        for (final point in op.removedStroke.points) {
          if (EraserHitTester.distanceSq(point.position, position) <=
              radiusSq) {
            anyNearby = true;
            break;
          }
        }
        if (anyNearby) break;
      }

      if (anyNearby) {
        final removedOps = _undoStack.removeAt(s);
        for (final op in removedOps.reversed) {
          for (final frag in op.addedFragments) {
            final idx = layerController.activeLayer?.strokes.indexWhere(
              (st) => st.id == frag.id,
            );
            if (idx != null && idx >= 0) {
              layerController.removeStrokeAt(idx);
            }
          }
          layerController.addStroke(op.removedStroke);
        }
        undoneCount++;
      }
    }

    if (undoneCount > 0) {
      _spatialIndex.markDirty();
      HapticFeedback.mediumImpact();
    }
    return undoneCount;
  }

  // ═══════════════════════════════════════════════════════════════════
  // PREVIEW — Hit test without mutation
  // ═══════════════════════════════════════════════════════════════════

  Set<String> getPreviewStrokeIds(Offset position) {
    final result = <String>{};
    final activeLayer = layerController.activeLayer;
    if (activeLayer == null || activeLayer.isLocked) return result;

    // 🚀 PERF: Pre-filter with spatial index to avoid O(N) full scan
    final nearbyIds = _spatialIndex.getNearbyStrokeIds(
      position,
      eraserRadius: eraserRadius + 10,
      eraserShape: eraserShape,
      eraserShapeWidth: eraserShapeWidth,
      eraserShapeAngle: eraserShapeAngle,
    );

    for (final stroke in activeLayer.strokes) {
      // Skip strokes outside spatial index range (if index is valid)
      if (nearbyIds.isNotEmpty && !nearbyIds.contains(stroke.id)) continue;

      if (EraserHitTester.strokeIntersectsEraser(
        stroke,
        position,
        eraserRadius: eraserRadius,
        eraserShape: eraserShape,
        eraserShapeWidth: eraserShapeWidth,
        eraserShapeAngle: eraserShapeAngle,
      )) {
        result.add(stroke.id);
      }
    }
    return result;
  }

  // ═══════════════════════════════════════════════════════════════════
  // ERASE LOGIC
  // ═══════════════════════════════════════════════════════════════════

  bool eraseAt(Offset position) {
    for (final region in protectedRegions) {
      if (region.contains(position)) return false;
    }

    if (eraseToReveal) {
      return eraseToRevealAt(position);
    }

    // 🚀 Batch mode: defer version bumps + index rebuilds to one flush
    layerController.beginBatch();

    bool erased = false;

    if (eraseAllLayers) {
      for (final layer in layerController.layers) {
        if (!layer.isVisible || layer.isLocked) continue;
        layer.node.beginDeferIndexRebuild();
        erased |= _eraseOnLayer(layer, position);
        layer.node.endDeferIndexRebuild();
      }
    } else {
      final activeLayer = layerController.activeLayer;
      if (activeLayer == null || activeLayer.isLocked) {
        layerController.endBatch();
        return false;
      }
      activeLayer.node.beginDeferIndexRebuild();
      erased = _eraseOnLayer(activeLayer, position);
      activeLayer.node.endDeferIndexRebuild();
    }

    layerController.endBatch();

    if (erased) {
      if (!_gestureDidErase) {
        HapticFeedback.lightImpact();
      }
      _gestureDidErase = true;
      analytics.recordErase(position, eraserRadius);
    }

    return erased;
  }

  bool _eraseOnLayer(dynamic layer, Offset position) {
    bool erased = false;

    // 🚀 PERF: Snapshot strokes/shapes ONCE. The getter calls
    // strokeNodes.map((n) => n.stroke).toList() — O(N) allocation each time.
    // Previously called 2× per eraseAt (scan + process), up to 30× per frame.
    final strokes = layer.strokes as List<ProStroke>;
    final shapes = layer.shapes as List<GeometricShape>;

    final strokesToProcess = <ProStroke>[];
    final shapesToRemove = <GeometricShape>[];

    // Pre-filter using spatial index
    final nearbyIds = _spatialIndex.getNearbyStrokeIds(
      position,
      eraserRadius: eraserRadius + 10,
      eraserShape: eraserShape,
      eraserShapeWidth: eraserShapeWidth,
      eraserShapeAngle: eraserShapeAngle,
    );

    for (final stroke in strokes) {
      if (nearbyIds.isNotEmpty && !nearbyIds.contains(stroke.id)) continue;

      if (eraseByColor != null &&
          stroke.color.toARGB32() != eraseByColor!.toARGB32()) {
        continue;
      }

      if (EraserHitTester.strokeIntersectsEraser(
        stroke,
        position,
        eraserRadius: eraserRadius,
        eraserShape: eraserShape,
        eraserShapeWidth: eraserShapeWidth,
        eraserShapeAngle: eraserShapeAngle,
      )) {
        strokesToProcess.add(stroke);
        erased = true;
      }
    }

    for (final shape in shapes) {
      if (EraserHitTester.shapeIntersectsEraser(
        shape,
        position,
        eraserRadius: eraserRadius,
      )) {
        shapesToRemove.add(shape);
        erased = true;
      }
    }

    // Process strokes (no index dependency — uses stored references)
    for (final stroke in strokesToProcess) {
      // 🚀 PERF: Incremental spatial index update — keeps index valid for
      // subsequent eraseAt() calls within the same interpolation loop.
      _spatialIndex.incrementalRemove(stroke);

      if (opacityEraseMode) {
        final currentAlpha = stroke.color.a;
        final newAlpha = (currentAlpha - opacityEraseStrength).clamp(0.0, 1.0);
        if (newAlpha <= 0.02) {
          _currentGestureOps.add(
            _EraseOperation(removedStroke: stroke, addedFragments: const []),
          );
          layerController.removeStroke(stroke.id);
        } else {
          final fadedStroke = stroke.copyWith(
            color: stroke.color.withValues(alpha: newAlpha),
          );
          _currentGestureOps.add(
            _EraseOperation(
              removedStroke: stroke,
              addedFragments: [fadedStroke],
            ),
          );
          layerController.removeStroke(stroke.id);
          layerController.addStroke(fadedStroke);
          _spatialIndex.incrementalAdd(fadedStroke);
        }
      } else if (eraseWholeStroke) {
        _currentGestureOps.add(
          _EraseOperation(removedStroke: stroke, addedFragments: const []),
        );
        layerController.removeStroke(stroke.id);
      } else {
        final fragments = _splitStrokeAtEraser(stroke, position);
        _currentGestureOps.add(
          _EraseOperation(removedStroke: stroke, addedFragments: fragments),
        );
        layerController.removeStroke(stroke.id);

        for (final frag in fragments) {
          layerController.addStroke(frag);
          _spatialIndex.incrementalAdd(frag);
        }
      }
      _currentGestureEraseCount++;

      final bbox = EraserHitTester.strokeBBox(stroke);
      if (bbox != null) {
        lastEraseBounds = lastEraseBounds?.expandToInclude(bbox) ?? bbox;
      }
    }

    // Remove shapes
    for (final shape in shapesToRemove) {
      layerController.removeShape(shape.id);
    }

    return erased;
  }

  /// V4: Lasso eraser — erase all strokes/shapes inside a closed path
  int eraseLasso(List<Offset> lassoPoints) {
    if (lassoPoints.length < 3) return 0;

    final path = ui.Path();
    path.moveTo(lassoPoints.first.dx, lassoPoints.first.dy);
    for (int i = 1; i < lassoPoints.length; i++) {
      path.lineTo(lassoPoints[i].dx, lassoPoints[i].dy);
    }
    path.close();

    int eraseCount = 0;

    final layersToCheck =
        eraseAllLayers
            ? layerController.layers.where((l) => l.isVisible && !l.isLocked)
            : [
              if (layerController.activeLayer != null)
                layerController.activeLayer!,
            ];

    for (final layer in layersToCheck) {
      final strokeIds = <String>[];
      for (final stroke in layer.strokes) {
        final inside = stroke.points.any((p) => path.contains(p.position));
        if (inside) {
          strokeIds.add(stroke.id);
          _currentGestureOps.add(
            _EraseOperation(removedStroke: stroke, addedFragments: const []),
          );
          eraseCount++;
        }
      }
      for (final id in strokeIds) {
        layerController.removeStroke(id);
      }

      final shapeIds = <String>[];
      for (final shape in layer.shapes) {
        if (path.contains(shape.startPoint) || path.contains(shape.endPoint)) {
          shapeIds.add(shape.id);
          eraseCount++;
        }
      }
      for (final id in shapeIds) {
        layerController.removeShape(id);
      }
    }

    if (eraseCount > 0) {
      _gestureDidErase = true;
      _currentGestureEraseCount += eraseCount;
      HapticFeedback.mediumImpact();
    }

    return eraseCount;
  }

  /// V4: Magnetic snap — find nearest stroke point within snap radius
  Offset getNearestStrokePosition(Offset position, {double snapRadius = 30.0}) {
    if (!magneticSnap) return position;

    final activeLayer = layerController.activeLayer;
    if (activeLayer == null) return position;

    // 🚀 PERF: Pre-filter with spatial index — only check nearby strokes
    // instead of iterating every point of every stroke (O(N×M) → O(K×M))
    final nearbyIds = _spatialIndex.getNearbyStrokeIds(
      position,
      eraserRadius: snapRadius,
      eraserShape: EraserShape.circle,
    );

    double bestDistSq = snapRadius * snapRadius;
    Offset bestPos = position;

    for (final stroke in activeLayer.strokes) {
      // Skip strokes outside spatial range (if index is valid)
      if (nearbyIds.isNotEmpty && !nearbyIds.contains(stroke.id)) continue;

      // 🚀 PERF: Bounding box pre-rejection — skip iterating all points
      // if the stroke's bounds are entirely outside the snap radius
      final bounds = stroke.bounds;
      if (bounds != Rect.zero) {
        final inflated = bounds.inflate(snapRadius);
        if (!inflated.contains(position)) continue;
      }

      for (final point in stroke.points) {
        final dSq = EraserHitTester.distanceSq(position, point.position);
        if (dSq < bestDistSq) {
          bestDistSq = dSq;
          bestPos = point.position;
        }
      }
    }

    lastMagneticSnapTarget = (bestPos != position) ? bestPos : null;
    return bestPos;
  }

  // ═══════════════════════════════════════════════════════════════════
  // PARTIAL STROKE ERASING — Split stroke at eraser intersection
  // ═══════════════════════════════════════════════════════════════════

  List<ProStroke> _splitStrokeAtEraser(ProStroke stroke, Offset eraserCenter) {
    if (stroke.points.length < 2) return [];

    final featherZone = eraserRadius * 0.7;
    final featherZoneSq = featherZone * featherZone;
    final fragments = <List<ProDrawingPoint>>[];
    var currentFragment = <ProDrawingPoint>[];

    for (final point in stroke.points) {
      final isInside = EraserHitTester.isPointInsideEraser(
        point.position,
        eraserCenter,
        eraserRadius: eraserRadius,
        eraserShape: eraserShape,
        eraserShapeWidth: eraserShapeWidth,
        eraserShapeAngle: eraserShapeAngle,
      );
      final distSq = EraserHitTester.distanceSq(point.position, eraserCenter);

      if (isInside) {
        if (featheredEdge && distSq > featherZoneSq) {
          final dist = math.sqrt(distSq);
          final t = ((dist - featherZone) / (eraserRadius - featherZone)).clamp(
            0.0,
            1.0,
          );
          final featheredPoint = ProDrawingPoint(
            position: point.position,
            pressure: point.pressure * t,
            timestamp: point.timestamp,
          );
          currentFragment.add(featheredPoint);
        } else {
          if (currentFragment.length >= 2) {
            fragments.add(currentFragment);
          }
          currentFragment = [];
        }
      } else {
        currentFragment.add(point);
      }
    }

    if (currentFragment.length >= 2) {
      fragments.add(currentFragment);
    }

    final now = DateTime.now();
    final originalPointCount = stroke.points.length;

    final validFragments =
        fragments.where((frag) {
          return frag.length / originalPointCount >= autoCompleteThreshold;
        }).toList();

    return validFragments.map((frag) {
      final tapered = _taperFragmentEndpoints(frag);
      return stroke.copyWith(
        id:
            '${stroke.id}_frag_${now.microsecondsSinceEpoch}_${validFragments.indexOf(frag)}',
        points: tapered,
      );
    }).toList();
  }

  // ═══════════════════════════════════════════════════════════════════
  // V10: FRAGMENT MERGING
  // ═══════════════════════════════════════════════════════════════════

  int mergeAdjacentFragments({double mergeDistance = 3.0}) {
    final activeLayer = layerController.activeLayer;
    if (activeLayer == null) return 0;
    final mergeSq = mergeDistance * mergeDistance;

    final groups = <String, List<ProStroke>>{};
    for (final stroke in activeLayer.strokes) {
      final fragIdx = stroke.id.indexOf('_frag_');
      if (fragIdx < 0) continue;
      final baseId = stroke.id.substring(0, fragIdx);
      (groups[baseId] ??= []).add(stroke);
    }

    if (groups.isEmpty) return 0;

    int mergeCount = 0;
    final toRemove = <String>{};
    final toAdd = <ProStroke>[];

    for (final frags in groups.values) {
      if (frags.length < 2) continue;

      final remaining = List<ProStroke>.from(frags);
      while (remaining.length >= 2) {
        var current = remaining.removeAt(0);
        bool didMerge = true;

        while (didMerge && remaining.isNotEmpty) {
          didMerge = false;
          for (int j = 0; j < remaining.length; j++) {
            final candidate = remaining[j];
            if (current.points.isEmpty || candidate.points.isEmpty) continue;

            if (EraserHitTester.distanceSq(
                  current.points.last.position,
                  candidate.points.first.position,
                ) <=
                mergeSq) {
              toRemove.add(current.id);
              toRemove.add(candidate.id);
              final mergedPoints = [...current.points, ...candidate.points];
              current = current.copyWith(points: mergedPoints);
              toAdd.add(current);
              remaining.removeAt(j);
              mergeCount++;
              didMerge = true;
              break;
            }

            if (EraserHitTester.distanceSq(
                  candidate.points.last.position,
                  current.points.first.position,
                ) <=
                mergeSq) {
              toRemove.add(current.id);
              toRemove.add(candidate.id);
              final mergedPoints = [...candidate.points, ...current.points];
              current = candidate.copyWith(points: mergedPoints);
              toAdd.add(current);
              remaining.removeAt(j);
              mergeCount++;
              didMerge = true;
              break;
            }
          }
        }
      }
    }

    if (mergeCount > 0) {
      for (final id in toRemove) {
        layerController.removeStroke(id);
      }
      final seen = <String>{};
      for (int i = toAdd.length - 1; i >= 0; i--) {
        if (!seen.contains(toAdd[i].id) && !toRemove.contains(toAdd[i].id)) {
          layerController.addStroke(toAdd[i]);
          seen.add(toAdd[i].id);
        }
      }
      for (int i = toAdd.length - 1; i >= 0; i--) {
        if (!seen.contains(toAdd[i].id)) {
          layerController.addStroke(toAdd[i]);
          seen.add(toAdd[i].id);
        }
      }
      _spatialIndex.markDirty();
    }
    return mergeCount;
  }

  // ═══════════════════════════════════════════════════════════════════
  // V10: ERASE MASK TRACKING
  // ═══════════════════════════════════════════════════════════════════

  void recordMaskPosition(Offset position) {
    eraseMaskPositions.add(position);
  }

  void clearMask() {
    eraseMaskPositions.clear();
  }

  // ═══════════════════════════════════════════════════════════════════
  // V10: ERASER PRESETS (delegates to EraserPresetManager)
  // ═══════════════════════════════════════════════════════════════════

  Future<void> savePreset(String name) async {
    await EraserPresetManager.save(
      name,
      radius: eraserRadius,
      shape: eraserShape,
      shapeWidth: eraserShapeWidth,
      shapeAngle: eraserShapeAngle,
      wholeStroke: eraseWholeStroke,
      featheredEdge: featheredEdge,
      magneticSnap: magneticSnap,
      opacityMode: opacityEraseMode,
      opacityStrength: opacityEraseStrength,
      pressureCurveIndex: pressureCurve.index,
      autoCompleteThreshold: autoCompleteThreshold,
      velocityAdaptive: velocityAdaptiveRadius,
    );
  }

  Future<bool> loadPreset(String name) async {
    final p = await EraserPresetManager.load(name);
    if (p == null) return false;
    eraserRadius = (p['radius'] as num?)?.toDouble() ?? eraserRadius;
    eraserShape = EraserShape.values[(p['shape'] as int?) ?? 0];
    eraserShapeWidth =
        (p['shapeWidth'] as num?)?.toDouble() ?? eraserShapeWidth;
    eraserShapeAngle =
        (p['shapeAngle'] as num?)?.toDouble() ?? eraserShapeAngle;
    eraseWholeStroke = (p['wholeStroke'] as bool?) ?? eraseWholeStroke;
    featheredEdge = (p['featheredEdge'] as bool?) ?? featheredEdge;
    magneticSnap = (p['magneticSnap'] as bool?) ?? magneticSnap;
    opacityEraseMode = (p['opacityMode'] as bool?) ?? opacityEraseMode;
    opacityEraseStrength =
        (p['opacityStrength'] as num?)?.toDouble() ?? opacityEraseStrength;
    pressureCurve =
        EraserPressureCurve.values[(p['pressureCurve'] as int?) ?? 0];
    autoCompleteThreshold =
        (p['autoComplete'] as num?)?.toDouble() ?? autoCompleteThreshold;
    velocityAdaptiveRadius =
        (p['velocityAdaptive'] as bool?) ?? velocityAdaptiveRadius;
    return true;
  }

  Future<List<String>> listPresets() => EraserPresetManager.list();

  Future<void> deletePreset(String name) => EraserPresetManager.delete(name);

  /// V9: Taper fragment endpoints — smoothly reduce width at cut points.
  List<ProDrawingPoint> _taperFragmentEndpoints(List<ProDrawingPoint> points) {
    if (points.length < 4) return points;
    final tapered = List<ProDrawingPoint>.from(points);
    const taperCount = 3;

    for (int i = 0; i < taperCount && i < tapered.length; i++) {
      final t = (i + 1) / (taperCount + 1);
      final p = tapered[i];
      tapered[i] = ProDrawingPoint(
        position: p.position,
        pressure: p.pressure * t,
        timestamp: p.timestamp,
      );
    }

    for (int i = 0; i < taperCount && i < tapered.length; i++) {
      final idx = tapered.length - 1 - i;
      final t = (i + 1) / (taperCount + 1);
      final p = tapered[idx];
      tapered[idx] = ProDrawingPoint(
        position: p.position,
        pressure: p.pressure * t,
        timestamp: p.timestamp,
      );
    }

    return tapered;
  }

  // ═══════════════════════════════════════════════════════════════════
  // V9: CATMULL-ROM ERASE PATH INTERPOLATION
  // ═══════════════════════════════════════════════════════════════════

  static List<Offset> catmullRomInterpolate(
    Offset p0,
    Offset p1,
    Offset p2,
    Offset p3, {
    int segments = 4,
    double alpha = 0.5,
  }) {
    final result = <Offset>[];
    for (int i = 1; i < segments; i++) {
      final t = i / segments;
      final t2 = t * t;
      final t3 = t2 * t;

      final x =
          0.5 *
          ((2 * p1.dx) +
              (-p0.dx + p2.dx) * t +
              (2 * p0.dx - 5 * p1.dx + 4 * p2.dx - p3.dx) * t2 +
              (-p0.dx + 3 * p1.dx - 3 * p2.dx + p3.dx) * t3);
      final y =
          0.5 *
          ((2 * p1.dy) +
              (-p0.dy + p2.dy) * t +
              (2 * p0.dy - 5 * p1.dy + 4 * p2.dy - p3.dy) * t2 +
              (-p0.dy + 3 * p1.dy - 3 * p2.dy + p3.dy) * t3);
      result.add(Offset(x, y));
    }
    return result;
  }

  List<Offset> getSmoothedErasePath(Offset current) {
    _recentPositions.add(current);
    if (_recentPositions.length > 6) _recentPositions.removeAt(0);
    if (_recentPositions.length < 4) return [current];

    final n = _recentPositions.length;
    final smoothed = <Offset>[];
    smoothed.addAll(
      catmullRomInterpolate(
        _recentPositions[n - 4],
        _recentPositions[n - 3],
        _recentPositions[n - 2],
        _recentPositions[n - 1],
        segments: 3,
      ),
    );
    smoothed.add(current);
    return smoothed;
  }

  // ═══════════════════════════════════════════════════════════════════
  // V9: MULTI-STROKE SMART SELECTION
  // ═══════════════════════════════════════════════════════════════════

  List<ProStroke> smartSelectMultiple(Offset position, {double radius = 30.0}) {
    final activeLayer = layerController.activeLayer;
    if (activeLayer == null) return [];
    final radiusSq = radius * radius;
    smartSelectedStrokeIds.clear();

    final selected = <ProStroke>[];
    for (final stroke in activeLayer.strokes) {
      for (final point in stroke.points) {
        if (EraserHitTester.distanceSq(point.position, position) <= radiusSq) {
          smartSelectedStrokeIds.add(stroke.id);
          selected.add(stroke);
          break;
        }
      }
    }
    return selected;
  }

  int confirmMultiSelection() {
    int count = 0;
    for (final id in smartSelectedStrokeIds.toList()) {
      if (eraseStrokeById(id)) count++;
    }
    smartSelectedStrokeIds.clear();
    return count;
  }

  void cancelMultiSelection() {
    smartSelectedStrokeIds.clear();
  }

  // ═══════════════════════════════════════════════════════════════════
  // V9: BATCH OPERATIONS
  // ═══════════════════════════════════════════════════════════════════

  int batchEraseByColor(ui.Color color) {
    final activeLayer = layerController.activeLayer;
    if (activeLayer == null) return 0;
    final toRemove = <String>[];
    for (final stroke in activeLayer.strokes) {
      if (stroke.color.toARGB32() == color.toARGB32()) {
        toRemove.add(stroke.id);
        _currentGestureOps.add(
          _EraseOperation(removedStroke: stroke, addedFragments: []),
        );
      }
    }
    for (final id in toRemove) {
      layerController.removeStroke(id);
    }
    if (toRemove.isNotEmpty) {
      _gestureDidErase = true;
      _currentGestureEraseCount += toRemove.length;
      _spatialIndex.markDirty();
      HapticFeedback.heavyImpact();
    }
    return toRemove.length;
  }

  int batchEraseByType(ProPenType penType) {
    final activeLayer = layerController.activeLayer;
    if (activeLayer == null) return 0;
    final toRemove = <String>[];
    for (final stroke in activeLayer.strokes) {
      if (stroke.penType == penType) {
        toRemove.add(stroke.id);
        _currentGestureOps.add(
          _EraseOperation(removedStroke: stroke, addedFragments: []),
        );
      }
    }
    for (final id in toRemove) {
      layerController.removeStroke(id);
    }
    if (toRemove.isNotEmpty) {
      _gestureDidErase = true;
      _currentGestureEraseCount += toRemove.length;
      _spatialIndex.markDirty();
      HapticFeedback.heavyImpact();
    }
    return toRemove.length;
  }

  // ═══════════════════════════════════════════════════════════════════
  // V9: CONTEXTUAL HAPTICS
  // ═══════════════════════════════════════════════════════════════════

  static int getContextualHapticLevel(ProStroke stroke) {
    if (stroke.baseWidth >= 8.0) return 3;
    if (stroke.baseWidth >= 3.0) return 2;
    return 1;
  }

  static void fireContextualHaptic(ProStroke stroke) {
    final level = getContextualHapticLevel(stroke);
    switch (level) {
      case 3:
        HapticFeedback.heavyImpact();
        break;
      case 2:
        HapticFeedback.mediumImpact();
        break;
      default:
        HapticFeedback.lightImpact();
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // V9: ZOOM STATE PRESERVATION
  // ═══════════════════════════════════════════════════════════════════

  void saveStateForZoom(Offset position, double radius) {
    _savedEraserPosition = position;
    _savedEraserRadius = radius;
  }

  Offset? restoreStateAfterZoom() {
    final pos = _savedEraserPosition;
    if (_savedEraserRadius != null) {
      eraserRadius = _savedEraserRadius!;
    }
    _savedEraserPosition = null;
    _savedEraserRadius = null;
    return pos;
  }

  // ═══════════════════════════════════════════════════════════════════
  // SPATIAL INDEX (delegates to EraserSpatialIndex)
  // ═══════════════════════════════════════════════════════════════════

  /// Rebuild spatial index (call after stroke mutations).
  void invalidateSpatialIndex() {
    final strokes = _collectVisibleStrokes();
    _spatialIndex.rebuild(strokes);
  }

  void incrementalSpatialRemove(ProStroke stroke) {
    _spatialIndex.incrementalRemove(stroke);
  }

  void incrementalSpatialAdd(ProStroke stroke) {
    _spatialIndex.incrementalAdd(stroke);
  }

  List<ProStroke> _collectVisibleStrokes() {
    final result = <ProStroke>[];
    final layers =
        eraseAllLayers
            ? layerController.layers.where((l) => l.isVisible && !l.isLocked)
            : [
              if (layerController.activeLayer != null)
                layerController.activeLayer!,
            ];
    for (final layer in layers) {
      result.addAll(layer.strokes);
    }
    return result;
  }

  // ═══════════════════════════════════════════════════════════════════
  // V5: PRESSURE CURVE
  // ═══════════════════════════════════════════════════════════════════

  double applyPressureCurve(double rawPressure) {
    final p = rawPressure.clamp(0.0, 1.0);
    switch (pressureCurve) {
      case EraserPressureCurve.linear:
        return p;
      case EraserPressureCurve.easeIn:
        return math.pow(p, pressureCurveExponent).toDouble();
      case EraserPressureCurve.easeOut:
        return 1.0 - math.pow(1.0 - p, pressureCurveExponent).toDouble();
      case EraserPressureCurve.easeInOut:
        if (p < 0.5) {
          return 0.5 * math.pow(2 * p, pressureCurveExponent).toDouble();
        } else {
          return 1.0 -
              0.5 * math.pow(2 * (1.0 - p), pressureCurveExponent).toDouble();
        }
      case EraserPressureCurve.custom:
        return _applyCustomBezierCurve(p);
    }
  }

  double _applyCustomBezierCurve(double t) {
    final p1y = pressureCurveControlPoints[0].dy;
    final p2y = pressureCurveControlPoints[1].dy;
    final mt = 1.0 - t;
    return mt * mt * mt * 0.0 +
        3 * mt * mt * t * p1y +
        3 * mt * t * t * p2y +
        t * t * t * 1.0;
  }

  // ═══════════════════════════════════════════════════════════════════
  // HIT TESTING (delegates to EraserHitTester)
  // ═══════════════════════════════════════════════════════════════════

  /// Smart edge detection — find the exact point closest to eraser border.
  Offset? getClosestEdgePoint(Offset eraserCenter) {
    final activeLayer = layerController.activeLayer;
    if (activeLayer == null) return null;
    return EraserHitTester.getClosestEdgePoint(
      eraserCenter,
      eraserRadius,
      activeLayer.strokes,
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // CONFIGURATION
  // ═══════════════════════════════════════════════════════════════════

  void setEraseMode({bool? wholeStroke, double? radius}) {
    if (wholeStroke != null) eraseWholeStroke = wholeStroke;
    if (radius != null) eraserRadius = radius;
    _spatialIndex.markDirty();
  }

  void addProtectedRegion(ui.Rect region) {
    protectedRegions.add(region);
  }

  void removeProtectedRegion(int index) {
    if (index >= 0 && index < protectedRegions.length) {
      protectedRegions.removeAt(index);
    }
  }

  void clearProtectedRegions() {
    protectedRegions.clear();
  }

  Offset? lastMagneticSnapTarget;

  // ═══════════════════════════════════════════════════════════════════
  // V6: ANALYTICS (delegates to EraserAnalytics)
  // ═══════════════════════════════════════════════════════════════════

  /// Convenience accessors for backward compatibility
  int get totalStrokesErased => analytics.totalStrokesErased;
  double get totalAreaCovered => analytics.totalAreaCovered;
  Duration get totalEraseTime => analytics.totalEraseTime;
  List<Offset> get dissolvePoints => analytics.dissolvePoints;
  List<(DateTime, int)> get historySnapshots => analytics.historySnapshots;

  void startEraseSession() => analytics.startSession();
  void endEraseSession() => analytics.endSession();

  double getHeatmapIntensity(Offset position) =>
      analytics.getHeatmapIntensity(position);

  String get analyticsSummary => analytics.summary;

  void resetAnalytics() => analytics.reset();

  // ═══════════════════════════════════════════════════════════════════
  // V6: STROKE-BY-STROKE MODE
  // ═══════════════════════════════════════════════════════════════════

  String? getStrokeAtPoint(Offset position, {double maxDist = 15.0}) {
    final activeLayer = layerController.activeLayer;
    if (activeLayer == null) return null;

    double bestDist = double.infinity;
    String? bestId;

    for (final stroke in activeLayer.strokes) {
      for (final point in stroke.points) {
        final d = (point.position - position).distance;
        if (d < bestDist && d <= maxDist) {
          bestDist = d;
          bestId = stroke.id;
        }
      }
    }
    return bestId;
  }

  bool eraseStrokeById(String strokeId) {
    final activeLayer = layerController.activeLayer;
    if (activeLayer == null) return false;

    final idx = activeLayer.strokes.indexWhere((s) => s.id == strokeId);
    if (idx < 0) return false;

    final removed = activeLayer.strokes[idx];
    _currentGestureOps.add(
      _EraseOperation(removedStroke: removed, addedFragments: []),
    );
    layerController.removeStrokeAt(idx);

    if (removed.points.isNotEmpty) {
      analytics.recordErase(removed.points.first.position, eraserRadius);
    }
    _gestureDidErase = true;
    _spatialIndex.markDirty();
    HapticFeedback.lightImpact();
    return true;
  }

  // ═══════════════════════════════════════════════════════════════════
  // V6: ERASE-TO-REVEAL (SCRATCH-CARD)
  // ═══════════════════════════════════════════════════════════════════

  bool eraseToRevealAt(Offset position) {
    final layers =
        layerController.layers
            .where((l) => l.isVisible && !l.isLocked)
            .toList();
    if (layers.length < 2) return false;

    final topLayer = layers.last;
    final result = _eraseOnLayer(topLayer, position);
    if (result) {
      _gestureDidErase = true;
      analytics.recordErase(position, eraserRadius);
      HapticFeedback.lightImpact();
      _spatialIndex.markDirty();
    }
    return result;
  }

  // ═══════════════════════════════════════════════════════════════════
  // V6: AUTO-CLEAN MODE
  // ═══════════════════════════════════════════════════════════════════

  List<String> getAutoCleanSuggestions() {
    final activeLayer = layerController.activeLayer;
    if (activeLayer == null) return [];

    final suggestions = <String>[];
    final strokes = activeLayer.strokes;

    for (final stroke in strokes) {
      if (stroke.points.length < 3) {
        suggestions.add(stroke.id);
        continue;
      }

      double length = 0;
      for (int i = 1; i < stroke.points.length; i++) {
        length +=
            (stroke.points[i].position - stroke.points[i - 1].position)
                .distance;
      }

      if (length < autoCleanMinLength) {
        suggestions.add(stroke.id);
        continue;
      }

      if (stroke.points.isEmpty) continue;
      final center = stroke.points[stroke.points.length ~/ 2].position;
      bool hasNeighbor = false;

      for (final other in strokes) {
        if (other.id == stroke.id) continue;
        for (final pt in other.points) {
          if ((pt.position - center).distance < autoCleanOrphanRadius) {
            hasNeighbor = true;
            break;
          }
        }
        if (hasNeighbor) break;
      }

      if (!hasNeighbor) {
        suggestions.add(stroke.id);
      }
    }

    return suggestions;
  }

  int executeAutoClean() {
    final suggestions = getAutoCleanSuggestions();
    int cleaned = 0;
    for (final id in suggestions) {
      if (eraseStrokeById(id)) cleaned++;
    }
    if (cleaned > 0) {
      analytics.takeSnapshot(layerController.activeLayer?.strokes.length ?? 0);
    }
    return cleaned;
  }

  // ═══════════════════════════════════════════════════════════════════
  // V7: EDGE-AWARE ERASING
  // ═══════════════════════════════════════════════════════════════════

  Map<String, Offset> getEdgeAwareStrokeIds(
    Offset position, {
    double maxDist = 20.0,
  }) {
    final result = <String, Offset>{};
    final activeLayer = layerController.activeLayer;
    if (activeLayer == null) return result;
    final maxDistSq = maxDist * maxDist;

    for (final stroke in activeLayer.strokes) {
      if (stroke.points.length < 2) continue;
      final checkCount = math.min(3, stroke.points.length);
      for (int i = 0; i < checkCount; i++) {
        if (EraserHitTester.distanceSq(stroke.points[i].position, position) <=
            maxDistSq) {
          result[stroke.id] = stroke.points[i].position;
          break;
        }
      }
      if (result.containsKey(stroke.id)) continue;
      for (
        int i = stroke.points.length - 1;
        i >= math.max(0, stroke.points.length - 3);
        i--
      ) {
        if (EraserHitTester.distanceSq(stroke.points[i].position, position) <=
            maxDistSq) {
          result[stroke.id] = stroke.points[i].position;
          break;
        }
      }
    }
    return result;
  }

  // ═══════════════════════════════════════════════════════════════════
  // V7: HAPTIC GRADIENT — Stroke density at cursor
  // ═══════════════════════════════════════════════════════════════════

  int getStrokeDensityAt(Offset position, {double radius = 40.0}) {
    final activeLayer = layerController.activeLayer;
    if (activeLayer == null) return 0;
    final radiusSq = radius * radius;
    int count = 0;

    for (final stroke in activeLayer.strokes) {
      for (final point in stroke.points) {
        if (EraserHitTester.distanceSq(point.position, position) <= radiusSq) {
          count++;
          break;
        }
      }
    }
    return count;
  }

  // ═══════════════════════════════════════════════════════════════════
  // V7: SMART SELECTION — Preview + confirm entire stroke
  // ═══════════════════════════════════════════════════════════════════

  ProStroke? smartSelectStroke(Offset position, {double maxDist = 20.0}) {
    final id = getStrokeAtPoint(position, maxDist: maxDist);
    if (id == null) {
      smartSelectedStrokeId = null;
      return null;
    }
    smartSelectedStrokeId = id;
    final activeLayer = layerController.activeLayer;
    if (activeLayer == null) return null;
    try {
      return activeLayer.strokes.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  bool confirmSmartSelection() {
    if (smartSelectedStrokeId == null) return false;
    final result = eraseStrokeById(smartSelectedStrokeId!);
    smartSelectedStrokeId = null;
    return result;
  }

  void cancelSmartSelection() {
    smartSelectedStrokeId = null;
  }

  // ═══════════════════════════════════════════════════════════════════
  // V7: REGION FLOOD ERASE
  // ═══════════════════════════════════════════════════════════════════

  int floodEraseRegion(ui.Path regionPath) {
    final activeLayer = layerController.activeLayer;
    if (activeLayer == null) return 0;

    final toRemove = <String>[];
    for (final stroke in activeLayer.strokes) {
      if (stroke.points.isEmpty) continue;
      double cx = 0, cy = 0;
      for (final p in stroke.points) {
        cx += p.position.dx;
        cy += p.position.dy;
      }
      cx /= stroke.points.length;
      cy /= stroke.points.length;

      if (regionPath.contains(Offset(cx, cy))) {
        toRemove.add(stroke.id);
        _currentGestureOps.add(
          _EraseOperation(removedStroke: stroke, addedFragments: []),
        );
      }
    }

    for (final id in toRemove) {
      layerController.removeStroke(id);
    }

    if (toRemove.isNotEmpty) {
      _gestureDidErase = true;
      _currentGestureEraseCount += toRemove.length;
      _spatialIndex.markDirty();
      HapticFeedback.mediumImpact();
    }
    return toRemove.length;
  }

  // ═══════════════════════════════════════════════════════════════════
  // V7: UNDO GHOST REPLAY
  // ═══════════════════════════════════════════════════════════════════

  List<ProStroke> startUndoGhostReplay() {
    if (_undoStack.isEmpty) return [];
    final ops = _undoStack.last;
    _undoGhostStrokes.clear();
    for (final op in ops) {
      _undoGhostStrokes.add(op.removedStroke);
    }
    undoGhostProgress = 0.0;
    return List.unmodifiable(_undoGhostStrokes);
  }

  List<ProStroke> get undoGhostStrokes => List.unmodifiable(_undoGhostStrokes);

  void finishUndoGhostReplay() {
    undo();
    _undoGhostStrokes.clear();
    undoGhostProgress = 0.0;
  }

  void cancelUndoGhostReplay() {
    _undoGhostStrokes.clear();
    undoGhostProgress = 0.0;
  }

  // ═══════════════════════════════════════════════════════════════════
  // V7: LAYER-SPECIFIC PREVIEW
  // ═══════════════════════════════════════════════════════════════════

  List<ProStroke> getActiveLayerStrokes() {
    return layerController.activeLayer?.strokes ?? [];
  }

  List<int> getNonActiveLayerIndices() {
    final result = <int>[];
    final activeIdx = layerController.activeLayerIndex;
    for (int i = 0; i < layerController.layers.length; i++) {
      if (i != activeIdx) result.add(i);
    }
    return result;
  }

  // ═══════════════════════════════════════════════════════════════════
  // V8: TILT AND VELOCITY
  // ═══════════════════════════════════════════════════════════════════

  void updateShapeAngleFromTilt(double tiltX, double tiltY) {
    if (!stylusTiltRotation) return;
    if (eraserShape == EraserShape.circle) return;
    eraserShapeAngle = math.atan2(tiltY, tiltX);
  }

  double getVelocityRadiusMultiplier(double speed) {
    if (!velocityAdaptiveRadius) return 1.0;
    final t = (speed / _velocityThreshold).clamp(0.0, 1.0);
    return _velocityRadiusMin + t * (_velocityRadiusMax - _velocityRadiusMin);
  }

  Offset? getPredictedPosition(Offset currentPosition) {
    _recentPositions.add(currentPosition);
    if (_recentPositions.length > _predictiveWindowSize) {
      _recentPositions.removeAt(0);
    }
    if (!pathPredictiveMode || _recentPositions.length < 3) return null;

    double dx = 0, dy = 0;
    for (int i = 1; i < _recentPositions.length; i++) {
      dx += _recentPositions[i].dx - _recentPositions[i - 1].dx;
      dy += _recentPositions[i].dy - _recentPositions[i - 1].dy;
    }
    final n = _recentPositions.length - 1;
    dx /= n;
    dy /= n;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 0.5) return null;
    final scale = _predictiveExtension / len;
    return Offset(
      currentPosition.dx + dx * scale,
      currentPosition.dy + dy * scale,
    );
  }

  void clearPredictionBuffer() {
    _recentPositions.clear();
  }
}

/// Tracks a single erase operation for undo support.
class _EraseOperation {
  final ProStroke removedStroke;
  final List<ProStroke> addedFragments;

  const _EraseOperation({
    required this.removedStroke,
    required this.addedFragments,
  });
}
