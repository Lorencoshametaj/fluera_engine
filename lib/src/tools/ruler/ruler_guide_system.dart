import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';

export './ruler_guide_models.dart';
import './ruler_guide_models.dart';
export './ruler_guide_presets.dart';
export './canvas_guide.dart';
import './canvas_guide.dart';
export './constraint_guide.dart';
import './constraint_guide.dart';

part '_ruler_guide_serialization.dart';

/// 📏 Sistema righelli e guide for the canvas professionale
///
/// Fornisce:
/// - Draggable guides with snapping, lock, custom colors
/// - Grid overlay adattivo + grid snapping + stili (lines/dots/crosses)
/// - Griglia isometrica (30°/60°)
/// - Griglia prospettica (1/2/3 punti di fuga)
/// - Griglia radiale (cerchi concentrici + raggi)
/// - Smart guides (automatic alignment with existing strokes)
/// - Symmetry mode (mirrors strokes relative to a guide axis)
/// - Guide presets (centro, terzi, sezione aurea, aspect ratio, margini)
/// - Snap feedback (glow temporaneo)
/// - Measurement tool (distanza/angolo) with aità configurabili
/// - Multi-selezione guide
/// - Undo/redo for guide operations
class RulerGuideSystem {
  // ─── Change Notification ─────────────────────────────────────────

  /// Optional callback fired after any mutation. Allows reactive UI updates
  /// without tight coupling to ChangeNotifier.
  VoidCallback? onChanged;

  void _notify() => onChanged?.call();

  /// Public notification for use by external Command objects.
  void notifyListeners() => _notify();

  // ─── Guide Data ────────────────────────────────────────────────────

  final List<double> horizontalGuides = [];
  final List<double> verticalGuides = [];
  final List<bool> horizontalLocked = [];
  final List<bool> verticalLocked = [];

  /// Custom colors for guides (null = use default)
  final List<Color?> horizontalColors = [];
  final List<Color?> verticalColors = [];

  /// Annotazioni guide (null = nessuna etichetta)
  final List<String?> horizontalLabels = [];
  final List<String?> verticalLabels = [];

  /// Multi-selezione
  final Set<int> selectedHorizontalGuides = {};
  final Set<int> selectedVerticalGuides = {};
  bool multiSelectMode = false;

  // ─── Settings ──────────────────────────────────────────────────────

  double snapDistance = 8.0;
  bool snapEnabled = true;
  bool rulersVisible = true;
  bool guidesVisible = true;
  bool gridVisible = false;
  bool gridSnapEnabled = false; // snap strokes to grid intersections
  bool crosshairEnabled = false; // full-canvas crosshair

  /// Phase 9G: Ruler bookmark marks
  final List<BookmarkMark> bookmarkMarks = [];

  /// Phase 10C: Global guide opacity (0.0 - 1.0)
  double guideOpacity = 1.0;

  /// Phase 10F: Spacing locks between guide pairs
  /// Each entry is (isHorizontal, index1, index2, lockedDistance)
  final List<SpacingLock> spacingLocks = [];

  /// Phase 10H: Ghost snap preview position
  Offset? ghostSnapPosition;
  bool ghostSnapIsHorizontal = true;

  /// Phase 11A: Named guide groups
  final List<GuideGroup> namedGuideGroups = [];

  /// Phase 11B: Percentage-based guide positions (maps index to %)
  final Map<int, double> horizontalPercentGuides = {};
  final Map<int, double> verticalPercentGuides = {};

  /// Phase 11C: Current color theme
  GuideColorTheme guideColorTheme = GuideColorTheme.defaultTheme;

  /// Phase 11E: Snap strength (0.0 = weak, 1.0 = strong)
  double snapStrength = 0.5;

  static const int maxGuidesPerAxis = 20;

  // ─── Grid Style ────────────────────────────────────────────────────

  GridStyle gridStyle = GridStyle.lines;

  /// Grid overlay opacity (0.0 transparent → 1.0 full).
  double gridOpacity = 1.0;

  // ─── Frame-Scoped Guides ───────────────────────────────────────────

  /// Guides scoped to a specific FrameNode (artboard-local).
  final List<CanvasGuide> frameGuides = [];

  // ─── Constraint Guides ─────────────────────────────────────────────

  /// Guides that follow frame edges dynamically.
  final List<ConstraintGuide> constraintGuides = [];

  /// Resolved positions of constraint guides (updated by resolveConstraintGuides).
  final Map<String, double> _resolvedConstraintGuides = {};

  // ─── Isometric Grid ────────────────────────────────────────────────

  bool isometricGridVisible = false;
  double isometricAngle = 30.0; // degrees

  // ─── Unit System ───────────────────────────────────────────────────

  RulerUnit currentUnit = RulerUnit.px;
  double ppi = 72.0; // pixels per inch

  /// Converts pixel → unità corrente
  double convertToUnit(double px) {
    switch (currentUnit) {
      case RulerUnit.px:
        return px;
      case RulerUnit.cm:
        return px / ppi * 2.54;
      case RulerUnit.mm:
        return px / ppi * 25.4;
      case RulerUnit.inches:
        return px / ppi;
    }
  }

  /// Suffisso unità for thebels
  String get unitSuffix {
    switch (currentUnit) {
      case RulerUnit.px:
        return 'px';
      case RulerUnit.cm:
        return 'cm';
      case RulerUnit.mm:
        return 'mm';
      case RulerUnit.inches:
        return 'in';
    }
  }

  /// Cicla alla prossima unità
  void cycleUnit() {
    final values = RulerUnit.values;
    currentUnit = values[(currentUnit.index + 1) % values.length];
    _notify();
  }

  /// Cicla stile griglia: lines → dots → crosses
  void cycleGridStyle() {
    final values = GridStyle.values;
    gridStyle = values[(gridStyle.index + 1) % values.length];
    _notify();
  }

  // ─── Batch Operations ─────────────────────────────────────────────

  void lockAllGuides() {
    saveSnapshot();
    horizontalLocked
      ..clear()
      ..addAll(List.generate(horizontalGuides.length, (_) => true));
    verticalLocked
      ..clear()
      ..addAll(List.generate(verticalGuides.length, (_) => true));
    _notify();
  }

  void unlockAllGuides() {
    saveSnapshot();
    horizontalLocked
      ..clear()
      ..addAll(List.generate(horizontalGuides.length, (_) => false));
    verticalLocked
      ..clear()
      ..addAll(List.generate(verticalGuides.length, (_) => false));
    _notify();
  }

  void mirrorGuidesH(Rect viewport) {
    saveSnapshot();
    final center = (viewport.top + viewport.bottom) / 2;
    final mirrored = horizontalGuides.map((g) => center * 2 - g).toList();
    for (final m in mirrored) {
      if (!horizontalGuides.contains(m) &&
          horizontalGuides.length < maxGuidesPerAxis) {
        horizontalGuides.add(m);
        horizontalLocked.add(false);
        horizontalColors.add(null);
        horizontalLabels.add(null);
      }
    }
    _notify();
  }

  void mirrorGuidesV(Rect viewport) {
    saveSnapshot();
    final center = (viewport.left + viewport.right) / 2;
    final mirrored = verticalGuides.map((g) => center * 2 - g).toList();
    for (final m in mirrored) {
      if (!verticalGuides.contains(m) &&
          verticalGuides.length < maxGuidesPerAxis) {
        verticalGuides.add(m);
        verticalLocked.add(false);
        verticalColors.add(null);
        verticalLabels.add(null);
      }
    }
    _notify();
  }

  // ─── Animated Guide Creation ────────────────────────────────────────

  /// Timestamp of last guide creation (for glow animation)
  DateTime? lastGuideCreatedAt;

  // ─── Smart Guides ─────────────────────────────────────────────────

  bool smartGuidesEnabled = false;

  /// Guide temporanee calcolate da allineamenti stroke (non serializzate)
  final List<double> smartHGuides = [];
  final List<double> smartVGuides = [];

  /// Updates smart guides based on visible stroke and shape bounds
  void updateSmartGuides(
    List<Rect> strokeBounds,
    Offset currentPoint,
    double zoom, {
    List<Rect>? shapes,
  }) {
    smartHGuides.clear();
    smartVGuides.clear();
    if (!smartGuidesEnabled) return;

    final threshold = snapDistance / zoom;

    void addCandidate(double val, bool isH) {
      final list = isH ? smartHGuides : smartVGuides;
      final coord = isH ? currentPoint.dy : currentPoint.dx;
      if ((coord - val).abs() < threshold * 3) {
        if (!list.any((g) => (g - val).abs() < 0.5)) {
          list.add(val);
        }
      }
    }

    // Stroke bounds
    for (final bounds in strokeBounds) {
      addCandidate(bounds.top, true);
      addCandidate(bounds.bottom, true);
      addCandidate(bounds.center.dy, true);
      addCandidate(bounds.left, false);
      addCandidate(bounds.right, false);
      addCandidate(bounds.center.dx, false);
    }

    // Shape bounds
    if (shapes != null) {
      for (final r in shapes) {
        addCandidate(r.top, true);
        addCandidate(r.bottom, true);
        addCandidate(r.center.dy, true);
        addCandidate(r.left, false);
        addCandidate(r.right, false);
        addCandidate(r.center.dx, false);
      }
    }
  }

  void clearSmartGuides() {
    smartHGuides.clear();
    smartVGuides.clear();
    _notify();
  }

  // ─── Symmetry Mode ────────────────────────────────────────────────

  bool symmetryEnabled = false;
  int? symmetryAxisIndex; // index of the guide used as axis
  bool symmetryAxisIsHorizontal = true; // tipo dell'asse
  int symmetrySegments = 2; // 2 = single mirror, 4/6/8 = kaleidoscope

  /// Riflette un punto rispetto all'asse di simmetria (single mirror)
  Offset? mirrorPoint(Offset p) {
    if (!symmetryEnabled || symmetryAxisIndex == null) return null;

    final guides = symmetryAxisIsHorizontal ? horizontalGuides : verticalGuides;
    if (symmetryAxisIndex! >= guides.length) return null;

    final axisValue = guides[symmetryAxisIndex!];
    if (symmetryAxisIsHorizontal) {
      return Offset(p.dx, 2 * axisValue - p.dy);
    } else {
      return Offset(2 * axisValue - p.dx, p.dy);
    }
  }

  /// Genera tutti i punti mirror per multi-asse (kaleidoscope)
  /// Returne N-1 copie riflesse/ruotate (esclude l'originale)
  List<Offset> mirrorPointMulti(Offset p) {
    if (!symmetryEnabled || symmetryAxisIndex == null) return [];
    if (symmetrySegments <= 2) {
      final m = mirrorPoint(p);
      return m != null ? [m] : [];
    }

    final guides = symmetryAxisIsHorizontal ? horizontalGuides : verticalGuides;
    if (symmetryAxisIndex! >= guides.length) return [];
    final axisValue = guides[symmetryAxisIndex!];

    // Centro di simmetria
    final center =
        symmetryAxisIsHorizontal
            ? Offset(p.dx, axisValue) // usa Y dell'asse
            : Offset(axisValue, p.dy); // usa X dell'asse

    final results = <Offset>[];
    final angleStep = 2 * pi / symmetrySegments;
    final dp = p - center;
    final baseAngle = atan2(dp.dy, dp.dx);
    final radius = dp.distance;

    for (int i = 1; i < symmetrySegments; i++) {
      final a = baseAngle + angleStep * i;
      results.add(
        Offset(center.dx + radius * cos(a), center.dy + radius * sin(a)),
      );
    }
    return results;
  }

  /// Cycle symmetry segments: 2→4→6→8→2
  void cycleSymmetrySegments() {
    const options = [2, 4, 6, 8];
    final idx = options.indexOf(symmetrySegments);
    symmetrySegments = options[(idx + 1) % options.length];
    _notify();
  }

  /// Sets l'asse di simmetria
  void setSymmetryAxis(bool isHorizontal, int index) {
    symmetryAxisIsHorizontal = isHorizontal;
    symmetryAxisIndex = index;
    symmetryEnabled = true;
    _notify();
  }

  void clearSymmetry() {
    symmetryEnabled = false;
    symmetryAxisIndex = null;
    symmetrySegments = 2;
    _notify();
  }

  // ─── Angular Guides ────────────────────────────────────────────────

  final List<AngularGuide> angularGuides = [];
  static const int maxAngularGuides = 10;

  void addAngularGuide(Offset origin, double angleDeg, {Color? color}) {
    if (angularGuides.length >= maxAngularGuides) return;
    saveSnapshot();
    angularGuides.add(
      AngularGuide(origin: origin, angleDeg: angleDeg, color: color),
    );
    _notify();
  }

  void removeAngularGuideAt(int index) {
    if (index >= 0 && index < angularGuides.length) {
      saveSnapshot();
      angularGuides.removeAt(index);
      _notify();
    }
  }

  void clearAngularGuides() {
    saveSnapshot();
    angularGuides.clear();
    _notify();
  }

  // ─── Guide Labels ──────────────────────────────────────────────────

  bool showGuideLabels = false;

  // ─── Custom Grid Spacing ───────────────────────────────────────────

  /// null = auto spacing, non-null = fixed custom step
  double? customGridStep;

  // ─── Snap Feedback ─────────────────────────────────────────────────

  /// Tipo of the last snap eseguito
  String? lastSnapType; // 'guide', 'grid', 'smart', 'angular'
  Offset? lastSnapPosition;

  /// True if the last snapPoint actually snapped
  bool get didSnapOnLastCall =>
      _lastSnapTime != null &&
      DateTime.now().difference(_lastSnapTime!).inMilliseconds < 500;

  // ─── Draggable Ruler Origin ────────────────────────────────────────

  Offset rulerOrigin = Offset.zero;

  void resetRulerOrigin() {
    rulerOrigin = Offset.zero;
    _notify();
  }

  // ─── Protractor Mode ───────────────────────────────────────────────

  bool isProtractorMode = false;
  Offset? protractorCenter;
  Offset? protractorArm1;
  Offset? protractorArm2;

  double? get protractorAngle {
    if (protractorCenter == null ||
        protractorArm1 == null ||
        protractorArm2 == null)
      return null;
    final a1 = atan2(
      protractorArm1!.dy - protractorCenter!.dy,
      protractorArm1!.dx - protractorCenter!.dx,
    );
    final a2 = atan2(
      protractorArm2!.dy - protractorCenter!.dy,
      protractorArm2!.dx - protractorCenter!.dx,
    );
    var diff = (a2 - a1) * 180 / pi;
    if (diff < 0) diff += 360;
    return diff;
  }

  void clearProtractor() {
    isProtractorMode = false;
    protractorCenter = null;
    protractorArm1 = null;
    protractorArm2 = null;
    _notify();
  }

  // ─── Guide Distribution ────────────────────────────────────────────

  void distributeGuides(bool isH, int count, double start, double end) {
    if (count < 2) return;
    saveSnapshot();
    final step = (end - start) / (count - 1);
    final guides = isH ? horizontalGuides : verticalGuides;
    final locked = isH ? horizontalLocked : verticalLocked;
    final colors = isH ? horizontalColors : verticalColors;
    final labels = isH ? horizontalLabels : verticalLabels;
    for (int i = 0; i < count; i++) {
      if (guides.length >= maxGuidesPerAxis) break;
      guides.add(start + step * i);
      locked.add(false);
      colors.add(null);
      labels.add(null);
    }
    _notify();
  }

  // ─── Export/Import Guide Presets ────────────────────────────────────

  final List<GuidePreset> savedPresets = [];

  // ─── Golden Spiral ─────────────────────────────────────────────────

  bool showGoldenSpiral = false;

  // ─── Protractor Snap Step ──────────────────────────────────────────

  /// Protractor angle snap step in degrees (e.g. 15.0 = snap to 0°, 15°, 30°...)
  double protractorSnapStep = 15.0;

  /// Snap an angle to the nearest increment of [protractorSnapStep]
  double snapAngle(double deg) {
    if (protractorSnapStep <= 0) return deg;
    return (deg / protractorSnapStep).round() * protractorSnapStep;
  }

  // ─── Guide Groups ──────────────────────────────────────────────────

  /// Groups of guides: groupId → list of (isHorizontal, guideIndex)
  final Map<int, List<({bool isH, int index})>> guideGroups = {};
  int _nextGroupId = 0;

  /// Group selected guides
  int groupSelectedGuides() {
    if (selectedHorizontalGuides.isEmpty && selectedVerticalGuides.isEmpty) {
      return -1;
    }
    saveSnapshot();
    final groupId = _nextGroupId++;
    final members = <({bool isH, int index})>[];
    for (final idx in selectedHorizontalGuides) {
      members.add((isH: true, index: idx));
    }
    for (final idx in selectedVerticalGuides) {
      members.add((isH: false, index: idx));
    }
    guideGroups[groupId] = members;
    selectedHorizontalGuides.clear();
    selectedVerticalGuides.clear();
    _notify();
    return groupId;
  }

  /// Ungroup a group by id
  void ungroupGuides(int groupId) {
    saveSnapshot();
    guideGroups.remove(groupId);
    _notify();
  }

  /// Move all guides in a group by delta
  void moveGroup(int groupId, Offset delta) {
    final members = guideGroups[groupId];
    if (members == null) return;
    for (final m in members) {
      final guides = m.isH ? horizontalGuides : verticalGuides;
      if (m.index < guides.length) {
        guides[m.index] += m.isH ? delta.dy : delta.dx;
      }
    }
    _notify();
  }

  // ─── Perspective Grid ──────────────────────────────────────────────

  PerspectiveType perspectiveType = PerspectiveType.none;

  /// Vanishing points in canvas coordinates
  Offset vp1 = Offset.zero; // center/single VP
  Offset vp2 = Offset.zero; // right VP (2-point)
  Offset vp3 = Offset.zero; // top VP (3-point)

  /// Densità linee prospettiche (numero for theto)
  int perspectiveLineDensity = 16;

  /// Initializes i VP based onl viewport
  void initPerspective(PerspectiveType type, Rect viewport) {
    perspectiveType = type;
    final cx = viewport.center.dx;
    final cy = viewport.center.dy;
    final w = viewport.width;
    final h = viewport.height;

    switch (type) {
      case PerspectiveType.none:
        break;
      case PerspectiveType.onePoint:
        vp1 = Offset(cx, cy);
        break;
      case PerspectiveType.twoPoint:
        vp1 = Offset(cx - w * 0.6, cy);
        vp2 = Offset(cx + w * 0.6, cy);
        break;
      case PerspectiveType.threePoint:
        vp1 = Offset(cx - w * 0.5, cy);
        vp2 = Offset(cx + w * 0.5, cy);
        vp3 = Offset(cx, cy - h * 0.6);
        break;
    }
    _notify();
  }

  // ─── Radial Grid ───────────────────────────────────────────────────

  bool radialGridVisible = false;
  Offset radialCenter = Offset.zero; // canvas coords
  int radialDivisions = 12; // number of radial lines
  int radialRings = 6; // number of concentric circles
  double radialMaxRadius = 400; // max radius in canvas pixels

  void initRadialGrid(Rect viewport) {
    radialCenter = viewport.center;
    radialMaxRadius = min(viewport.width, viewport.height) * 0.4;
    _notify();
  }

  // ─── Snap Feedback ─────────────────────────────────────────────────

  int? _lastSnapHGuideIndex;
  int? _lastSnapVGuideIndex;
  DateTime? _lastSnapTime;
  static const int _snapGlowDurationMs = 400;

  double snapGlowAlpha(bool isHorizontal, int index) {
    if (_lastSnapTime == null) return 0.0;
    final elapsed = DateTime.now().difference(_lastSnapTime!).inMilliseconds;
    if (elapsed > _snapGlowDurationMs) return 0.0;
    final targetIndex =
        isHorizontal ? _lastSnapHGuideIndex : _lastSnapVGuideIndex;
    if (targetIndex != index) return 0.0;
    return 1.0 - (elapsed / _snapGlowDurationMs);
  }

  bool get hasActiveGlow =>
      _lastSnapTime != null &&
      DateTime.now().difference(_lastSnapTime!).inMilliseconds <
          _snapGlowDurationMs;

  // ─── Measurement Tool ──────────────────────────────────────────────

  Offset? measureStart;
  Offset? measureEnd;
  bool isMeasuring = false;

  ({double distance, double angle, double dx, double dy})? get measureResult {
    if (measureStart == null || measureEnd == null) return null;
    final dx = measureEnd!.dx - measureStart!.dx;
    final dy = measureEnd!.dy - measureStart!.dy;
    final distance = sqrt(dx * dx + dy * dy);
    final angle = atan2(dy, dx) * 180 / pi;
    return (distance: distance, angle: angle, dx: dx, dy: dy);
  }

  void clearMeasurement() {
    measureStart = null;
    measureEnd = null;
    isMeasuring = false;
    _notify();
  }

  // ─── Guide Undo/Redo ──────────────────────────────────────────────

  static const int _maxUndoStack = 20;
  final List<_GuideSnapshot> _undoStack = [];
  final List<_GuideSnapshot> _redoStack = [];

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  /// Saves uno snapshot before una mutazione
  void saveSnapshot() {
    _undoStack.add(_GuideSnapshot.from(this));
    if (_undoStack.length > _maxUndoStack) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  void undo() {
    if (!canUndo) return;
    // Save current state per redo
    _redoStack.add(_GuideSnapshot.from(this));
    _undoStack.removeLast().restoreTo(this);
    _notify();
  }

  void redo() {
    if (!canRedo) return;
    _undoStack.add(_GuideSnapshot.from(this));
    _redoStack.removeLast().restoreTo(this);
    _notify();
  }

  // ─── Guide Management ──────────────────────────────────────────────

  double snapGuideValue(double canvasValue, double zoomLevel) {
    final step = _calculateNiceStep(zoomLevel);
    final nearest = (canvasValue / step).round() * step;
    final screenDist = (canvasValue - nearest).abs() * zoomLevel;
    if (screenDist < 6.0) return nearest.toDouble();
    return canvasValue;
  }

  /// Phase 8E: Snap a guide position to the nearest existing guide
  double snapGuideToNearestGuide(
    double canvasValue,
    bool isHorizontal,
    int skipIndex,
    double zoomLevel,
  ) {
    final guides = isHorizontal ? horizontalGuides : verticalGuides;
    double bestVal = canvasValue;
    double bestDist = double.infinity;
    for (int i = 0; i < guides.length; i++) {
      if (i == skipIndex) continue;
      final screenDist = (canvasValue - guides[i]).abs() * zoomLevel;
      if (screenDist < 4.0 && screenDist < bestDist) {
        bestDist = screenDist;
        bestVal = guides[i];
      }
    }
    return bestVal;
  }

  /// Set an annotation label for a guide
  void setGuideLabel(bool isHorizontal, int index, String? label) {
    final labels = isHorizontal ? horizontalLabels : verticalLabels;
    if (index >= 0 && index < labels.length) {
      saveSnapshot();
      labels[index] = (label != null && label.trim().isEmpty) ? null : label;
      _notify();
    }
  }

  /// Get an annotation label for a guide
  String? getGuideLabel(bool isHorizontal, int index) {
    final labels = isHorizontal ? horizontalLabels : verticalLabels;
    if (index >= 0 && index < labels.length) return labels[index];
    return null;
  }

  void addHorizontalGuide(double y, {Color? color}) {
    if (horizontalGuides.length >= maxGuidesPerAxis) return;
    for (final existing in horizontalGuides) {
      if ((existing - y).abs() < 0.5) return;
    }
    horizontalGuides.add(y);
    horizontalLocked.add(false);
    horizontalColors.add(color);
    horizontalLabels.add(null);
    lastGuideCreatedAt = DateTime.now();
    _notify();
  }

  void addVerticalGuide(double x, {Color? color}) {
    if (verticalGuides.length >= maxGuidesPerAxis) return;
    for (final existing in verticalGuides) {
      if ((existing - x).abs() < 0.5) return;
    }
    verticalGuides.add(x);
    verticalLocked.add(false);
    verticalColors.add(color);
    verticalLabels.add(null);
    lastGuideCreatedAt = DateTime.now();
    _notify();
  }

  void removeHorizontalGuideAt(int index) {
    if (index < 0 || index >= horizontalGuides.length) return;
    horizontalGuides.removeAt(index);
    if (index < horizontalLocked.length) horizontalLocked.removeAt(index);
    if (index < horizontalColors.length) horizontalColors.removeAt(index);
    if (index < horizontalLabels.length) horizontalLabels.removeAt(index);
    selectedHorizontalGuides.remove(index);
    // Shift selection indices
    final newSelected = <int>{};
    for (final i in selectedHorizontalGuides) {
      if (i > index) {
        newSelected.add(i - 1);
      } else {
        newSelected.add(i);
      }
    }
    selectedHorizontalGuides
      ..clear()
      ..addAll(newSelected);
    // Fix symmetry axis reference
    if (symmetryAxisIsHorizontal && symmetryAxisIndex != null) {
      if (symmetryAxisIndex == index) {
        clearSymmetry();
      } else if (symmetryAxisIndex! > index) {
        symmetryAxisIndex = symmetryAxisIndex! - 1;
      }
    }
    _notify();
  }

  void removeVerticalGuideAt(int index) {
    if (index < 0 || index >= verticalGuides.length) return;
    verticalGuides.removeAt(index);
    if (index < verticalLocked.length) verticalLocked.removeAt(index);
    if (index < verticalColors.length) verticalColors.removeAt(index);
    if (index < verticalLabels.length) verticalLabels.removeAt(index);
    selectedVerticalGuides.remove(index);
    final newSelected = <int>{};
    for (final i in selectedVerticalGuides) {
      if (i > index) {
        newSelected.add(i - 1);
      } else {
        newSelected.add(i);
      }
    }
    selectedVerticalGuides
      ..clear()
      ..addAll(newSelected);
    // Fix symmetry axis reference
    if (!symmetryAxisIsHorizontal && symmetryAxisIndex != null) {
      if (symmetryAxisIndex == index) {
        clearSymmetry();
      } else if (symmetryAxisIndex! > index) {
        symmetryAxisIndex = symmetryAxisIndex! - 1;
      }
    }
    _notify();
  }

  void removeHorizontalGuideNear(double y, double threshold) {
    for (int i = horizontalGuides.length - 1; i >= 0; i--) {
      if ((horizontalGuides[i] - y).abs() < threshold) {
        removeHorizontalGuideAt(i);
      }
    }
  }

  void removeVerticalGuideNear(double x, double threshold) {
    for (int i = verticalGuides.length - 1; i >= 0; i--) {
      if ((verticalGuides[i] - x).abs() < threshold) {
        removeVerticalGuideAt(i);
      }
    }
  }

  void clearAllGuides() {
    saveSnapshot();
    horizontalGuides.clear();
    verticalGuides.clear();
    horizontalLocked.clear();
    verticalLocked.clear();
    horizontalColors.clear();
    verticalColors.clear();
    horizontalLabels.clear();
    verticalLabels.clear();
    selectedHorizontalGuides.clear();
    selectedVerticalGuides.clear();
    frameGuides.clear();
    constraintGuides.clear();
    _resolvedConstraintGuides.clear();
    angularGuides.clear();
    namedGuideGroups.clear();
    guideGroups.clear();
    horizontalPercentGuides.clear();
    verticalPercentGuides.clear();
    bookmarkMarks.clear();
    spacingLocks.clear();
    clearSymmetry();
    _notify();
  }

  // Phase 9D: Distribute selected guides evenly
  void distributeSelectedGuides() {
    // Try horizontal first, then vertical
    for (final isH in [true, false]) {
      final selected = isH ? selectedHorizontalGuides : selectedVerticalGuides;
      if (selected.length < 3) continue;
      final guides = isH ? horizontalGuides : verticalGuides;
      saveSnapshot();

      // Collect positions of selected guides
      final positions = <int, double>{};
      for (final idx in selected) {
        if (idx < guides.length) positions[idx] = guides[idx];
      }
      if (positions.length < 3) continue;

      final sorted =
          positions.entries.toList()
            ..sort((a, b) => a.value.compareTo(b.value));
      final first = sorted.first.value;
      final last = sorted.last.value;
      final spacing = (last - first) / (sorted.length - 1);

      for (int i = 1; i < sorted.length - 1; i++) {
        guides[sorted[i].key] = first + spacing * i;
      }
    }
    _notify();
  }

  // Phase 9G: Bookmark marks on ruler
  void addBookmark(double position, bool isHorizontal, Color color) {
    saveSnapshot();
    bookmarkMarks.add(
      BookmarkMark(
        position: position,
        isHorizontal: isHorizontal,
        color: color,
      ),
    );
    _notify();
  }

  void removeBookmark(int index) {
    if (index >= 0 && index < bookmarkMarks.length) {
      saveSnapshot();
      bookmarkMarks.removeAt(index);
      _notify();
    }
  }

  void clearBookmarks() {
    saveSnapshot();
    bookmarkMarks.clear();
    _notify();
  }

  // Phase 9E: Get coordinate string for clipboard
  String getGuideCoordinate(bool isHorizontal, int index) {
    final guides = isHorizontal ? horizontalGuides : verticalGuides;
    if (index < 0 || index >= guides.length) return '';
    final val = convertToUnit(guides[index]);
    final label =
        currentUnit == RulerUnit.px
            ? val.round().toString()
            : val.toStringAsFixed(1);
    return '$label$unitSuffix';
  }

  // Phase 10B: Duplicate a guide
  void duplicateGuide(bool isHorizontal, int index) {
    final guides = isHorizontal ? horizontalGuides : verticalGuides;
    if (index < 0 || index >= guides.length) return;
    if (guides.length >= maxGuidesPerAxis) return;
    saveSnapshot();
    final pos = guides[index] + 20; // offset by 20px
    if (isHorizontal) {
      addHorizontalGuide(pos);
    } else {
      addVerticalGuide(pos);
    }
  }

  // Phase 10F: Add spacing lock between two guides
  void addSpacingLock(bool isH, int idx1, int idx2) {
    final guides = isH ? horizontalGuides : verticalGuides;
    if (idx1 >= guides.length || idx2 >= guides.length) return;
    saveSnapshot();
    final dist = (guides[idx1] - guides[idx2]).abs();
    spacingLocks.add(
      SpacingLock(
        isHorizontal: isH,
        index1: idx1,
        index2: idx2,
        distance: dist,
      ),
    );
    _notify();
  }

  void removeSpacingLock(int index) {
    if (index >= 0 && index < spacingLocks.length) {
      saveSnapshot();
      spacingLocks.removeAt(index);
      _notify();
    }
  }

  // Phase 10F: Enforce spacing locks after a guide moves
  void enforceSpacingLocks(bool isH, int movedIndex) {
    for (final lock in spacingLocks) {
      if (lock.isHorizontal != isH) continue;
      final guides = isH ? horizontalGuides : verticalGuides;
      if (lock.index1 == movedIndex && lock.index2 < guides.length) {
        final sign = guides[lock.index1] > guides[lock.index2] ? 1.0 : -1.0;
        guides[lock.index2] = guides[lock.index1] - sign * lock.distance;
      } else if (lock.index2 == movedIndex && lock.index1 < guides.length) {
        final sign = guides[lock.index2] > guides[lock.index1] ? 1.0 : -1.0;
        guides[lock.index1] = guides[lock.index2] - sign * lock.distance;
      }
    }
  }

  // ─── Phase 11 Methods ────────────────────────────────────────────

  // Phase 11A: Guide group management
  void createGroup(String name, Set<int> hIndices, Set<int> vIndices) {
    saveSnapshot();
    namedGuideGroups.add(
      GuideGroup(
        name: name,
        horizontalIndices: hIndices.toList(),
        verticalIndices: vIndices.toList(),
      ),
    );
    _notify();
  }

  void removeNamedGroup(int index) {
    if (index >= 0 && index < namedGuideGroups.length) {
      saveSnapshot();
      namedGuideGroups.removeAt(index);
      _notify();
    }
  }

  void toggleGroupVisibility(int index) {
    if (index >= 0 && index < namedGuideGroups.length) {
      saveSnapshot();
      namedGuideGroups[index].visible = !namedGuideGroups[index].visible;
      _notify();
    }
  }

  void toggleGroupLock(int index) {
    if (index >= 0 && index < namedGuideGroups.length) {
      saveSnapshot();
      final g = namedGuideGroups[index];
      g.locked = !g.locked;
      for (final i in g.horizontalIndices) {
        if (i < horizontalLocked.length) horizontalLocked[i] = g.locked;
      }
      for (final i in g.verticalIndices) {
        if (i < verticalLocked.length) verticalLocked[i] = g.locked;
      }
      _notify();
    }
  }

  // Phase 11B: Add percentage-based guide
  void addPercentGuide(bool isH, double percent, double canvasSize) {
    saveSnapshot();
    final pos = canvasSize * percent / 100.0;
    final idx = isH ? horizontalGuides.length : verticalGuides.length;
    if (isH) {
      addHorizontalGuide(pos);
      horizontalPercentGuides[idx] = percent;
    } else {
      addVerticalGuide(pos);
      verticalPercentGuides[idx] = percent;
    }
  }

  // Resolve percentage guides when canvas resizes
  void resolvePercentGuides(double canvasWidth, double canvasHeight) {
    for (final entry in horizontalPercentGuides.entries) {
      if (entry.key < horizontalGuides.length) {
        horizontalGuides[entry.key] = canvasHeight * entry.value / 100.0;
      }
    }
    for (final entry in verticalPercentGuides.entries) {
      if (entry.key < verticalGuides.length) {
        verticalGuides[entry.key] = canvasWidth * entry.value / 100.0;
      }
    }
    _notify();
  }

  // Phase 11C: Apply color theme
  Color getThemeGuideColor(bool isHorizontal) {
    switch (guideColorTheme) {
      case GuideColorTheme.blueprint:
        return isHorizontal ? const Color(0xFF4FC3F7) : const Color(0xFF29B6F6);
      case GuideColorTheme.neon:
        return isHorizontal ? const Color(0xFF76FF03) : const Color(0xFFFF1744);
      case GuideColorTheme.minimal:
        return const Color(0xFF9E9E9E);
      case GuideColorTheme.custom:
      case GuideColorTheme.defaultTheme:
        return isHorizontal ? const Color(0xFF00BCD4) : const Color(0xFFFF9800);
    }
  }

  // Phase 11D: Mirror a guide across center
  void mirrorGuide(bool isH, int index, double canvasSize) {
    final guides = isH ? horizontalGuides : verticalGuides;
    if (index < 0 || index >= guides.length) return;
    if (guides.length >= maxGuidesPerAxis) return;
    saveSnapshot();
    final mirrored = canvasSize - guides[index];
    if (isH) {
      addHorizontalGuide(mirrored);
    } else {
      addVerticalGuide(mirrored);
    }
  }

  void toggleLock(bool isHorizontal, int index) {
    final lockedList = isHorizontal ? horizontalLocked : verticalLocked;
    if (index < lockedList.length) {
      saveSnapshot();
      lockedList[index] = !lockedList[index];
      _notify();
    }
  }

  bool isLocked(bool isHorizontal, int index) {
    final lockedList = isHorizontal ? horizontalLocked : verticalLocked;
    return index < lockedList.length && lockedList[index];
  }

  /// Get effective color for a guide
  Color getGuideColor(bool isHorizontal, int index) {
    final colorList = isHorizontal ? horizontalColors : verticalColors;
    if (index < colorList.length && colorList[index] != null) {
      return colorList[index]!;
    }
    return isHorizontal
        ? const Color(0xFF00BCD4) // cyan
        : const Color(0xFFE040FB); // magenta
  }

  /// Set custom color for a guide
  void setGuideColor(bool isHorizontal, int index, Color? color) {
    final colorList = isHorizontal ? horizontalColors : verticalColors;
    if (index < colorList.length) {
      saveSnapshot();
      colorList[index] = color;
      _notify();
    }
  }

  // ─── Multi-select ──────────────────────────────────────────────────

  void toggleSelection(bool isHorizontal, int index) {
    final set =
        isHorizontal ? selectedHorizontalGuides : selectedVerticalGuides;
    if (set.contains(index)) {
      set.remove(index);
    } else {
      set.add(index);
    }
  }

  void clearSelection() {
    selectedHorizontalGuides.clear();
    selectedVerticalGuides.clear();
    multiSelectMode = false;
  }

  bool isSelected(bool isHorizontal, int index) {
    return isHorizontal
        ? selectedHorizontalGuides.contains(index)
        : selectedVerticalGuides.contains(index);
  }

  /// Move all selected guides by delta (canvas coords)
  void moveSelectedGuides(double dx, double dy) {
    for (final i in selectedHorizontalGuides) {
      if (i < horizontalGuides.length && !isLocked(true, i)) {
        horizontalGuides[i] += dy;
      }
    }
    for (final i in selectedVerticalGuides) {
      if (i < verticalGuides.length && !isLocked(false, i)) {
        verticalGuides[i] += dx;
      }
    }
  }

  /// Delete all selected guides
  void deleteSelectedGuides() {
    saveSnapshot();
    final hIndices =
        selectedHorizontalGuides.toList()..sort((a, b) => b.compareTo(a));
    for (final i in hIndices) {
      removeHorizontalGuideAt(i);
    }
    final vIndices =
        selectedVerticalGuides.toList()..sort((a, b) => b.compareTo(a));
    for (final i in vIndices) {
      removeVerticalGuideAt(i);
    }
    clearSelection();
    _notify();
  }

  int get selectedCount =>
      selectedHorizontalGuides.length + selectedVerticalGuides.length;

  // ─── Frame-Scoped Guide Management ─────────────────────────────────

  /// Add a guide scoped to a specific frame.
  void addFrameGuide(CanvasGuide guide) {
    saveSnapshot();
    frameGuides.add(guide);
    _notify();
  }

  /// Remove a frame-scoped guide by ID.
  void removeFrameGuide(String guideId) {
    saveSnapshot();
    frameGuides.removeWhere((g) => g.id == guideId);
    _notify();
  }

  /// Get all guides for a specific frame.
  List<CanvasGuide> guidesForFrame(String frameId) {
    return frameGuides.where((g) => g.frameId == frameId).toList();
  }

  /// Get all global frame guides (no frame scope).
  List<CanvasGuide> get globalFrameGuides {
    return frameGuides.where((g) => g.frameId == null).toList();
  }

  // ─── Constraint Guide Management ──────────────────────────────────

  /// Add a constraint guide that follows a frame edge.
  void addConstraintGuide(ConstraintGuide guide) {
    saveSnapshot();
    constraintGuides.add(guide);
    _notify();
  }

  /// Remove a constraint guide by ID.
  void removeConstraintGuide(String guideId) {
    saveSnapshot();
    constraintGuides.removeWhere((g) => g.id == guideId);
    _resolvedConstraintGuides.remove(guideId);
    _notify();
  }

  /// Resolve all constraint guide positions from current frame bounds.
  ///
  /// Call this whenever frames move or resize.
  void resolveConstraintGuides(Map<String, Rect> frameBounds) {
    _resolvedConstraintGuides.clear();
    for (final cg in constraintGuides) {
      final bounds = frameBounds[cg.frameId];
      if (bounds != null) {
        _resolvedConstraintGuides[cg.id] = cg.resolve(bounds);
      }
    }
  }

  /// Get resolved constraint guide positions (read-only).
  Map<String, double> get resolvedConstraintPositions =>
      Map.unmodifiable(_resolvedConstraintGuides);

  // ─── Snapping ──────────────────────────────────────────────────────

  Offset snapPoint(Offset canvasPoint, double zoomLevel, {String? frameId}) {
    if (!snapEnabled) return canvasPoint;

    double x = canvasPoint.dx;
    double y = canvasPoint.dy;
    final adjustedSnap = snapDistance / zoomLevel;
    int? snappedHIndex;
    int? snappedVIndex;
    String? snapType;

    // Snap to vertical guides → X (skip locked)
    for (int i = 0; i < verticalGuides.length; i++) {
      if (isLocked(false, i)) continue;
      if ((x - verticalGuides[i]).abs() < adjustedSnap) {
        x = verticalGuides[i];
        snappedVIndex = i;
        snapType = 'guide';
        break;
      }
    }

    // Snap to horizontal guides → Y (skip locked)
    for (int i = 0; i < horizontalGuides.length; i++) {
      if (isLocked(true, i)) continue;
      if ((y - horizontalGuides[i]).abs() < adjustedSnap) {
        y = horizontalGuides[i];
        snappedHIndex = i;
        snapType = 'guide';
        break;
      }
    }

    // Angular guides snap
    if (snapType == null) {
      for (final ag in angularGuides) {
        final angleRad = ag.angleDeg * pi / 180;
        final dir = Offset(cos(angleRad), sin(angleRad));
        final toPoint = Offset(x - ag.origin.dx, y - ag.origin.dy);
        final proj = toPoint.dx * dir.dx + toPoint.dy * dir.dy;
        final closest = Offset(
          ag.origin.dx + dir.dx * proj,
          ag.origin.dy + dir.dy * proj,
        );
        final dist = (Offset(x, y) - closest).distance;
        if (dist < adjustedSnap) {
          x = closest.dx;
          y = closest.dy;
          snapType = 'angular';
          break;
        }
      }
    }

    // Smart guides snap
    if (smartGuidesEnabled) {
      if (snappedVIndex == null && snapType != 'angular') {
        for (final sg in smartVGuides) {
          if ((x - sg).abs() < adjustedSnap) {
            x = sg;
            snapType ??= 'smart';
            break;
          }
        }
      }
      if (snappedHIndex == null && snapType != 'angular') {
        for (final sg in smartHGuides) {
          if ((y - sg).abs() < adjustedSnap) {
            y = sg;
            snapType ??= 'smart';
            break;
          }
        }
      }
    }

    // Grid snapping (if enabled and no snap happened)
    if (gridSnapEnabled && gridVisible && snapType == null) {
      final step = gridStep(zoomLevel);
      if (snappedVIndex == null) {
        final nearestX = (x / step).round() * step;
        if ((x - nearestX).abs() < adjustedSnap) {
          x = nearestX.toDouble();
          snapType = 'grid';
        }
      }
      if (snappedHIndex == null) {
        final nearestY = (y / step).round() * step;
        if ((y - nearestY).abs() < adjustedSnap) {
          y = nearestY.toDouble();
          snapType ??= 'grid';
        }
      }
    }

    // Isometric grid snapping
    if (isometricGridVisible && snapType == null) {
      final step = gridStep(zoomLevel);
      final isoRad = isometricAngle * pi / 180;
      // Snap to nearest isometric intersection
      final nearestX = (x / step).round() * step;
      final isoY1 = (nearestX - x) * tan(isoRad) + y;
      final nearestIsoY = (isoY1 / step).round() * step;
      if ((x - nearestX.toDouble()).abs() < adjustedSnap &&
          (y - nearestIsoY.toDouble()).abs() < adjustedSnap) {
        x = nearestX.toDouble();
        y = nearestIsoY.toDouble();
        snapType = 'isometric';
      }
    }

    // Radial grid snapping
    if (radialGridVisible && snapType == null) {
      final dx0 = x - radialCenter.dx;
      final dy0 = y - radialCenter.dy;
      final dist = sqrt(dx0 * dx0 + dy0 * dy0);
      final ringSpacing = radialMaxRadius / radialRings;
      final nearestRing = (dist / ringSpacing).round() * ringSpacing;
      final angle = atan2(dy0, dx0);
      final sectorAngle = 2 * pi / radialDivisions;
      final nearestAngle = (angle / sectorAngle).round() * sectorAngle;
      // Snap to nearest radial intersection
      final snapX = radialCenter.dx + nearestRing * cos(nearestAngle);
      final snapY = radialCenter.dy + nearestRing * sin(nearestAngle);
      if ((x - snapX).abs() < adjustedSnap &&
          (y - snapY).abs() < adjustedSnap) {
        x = snapX;
        y = snapY;
        snapType = 'radial';
      }
    }

    // Frame-scoped guide snapping
    if (snapType == null) {
      for (final fg in frameGuides) {
        if (fg.locked) continue;
        // Skip guides not matching the active frame context
        if (frameId != null && fg.frameId != null && fg.frameId != frameId) {
          continue;
        }
        if (fg.isHorizontal) {
          if ((y - fg.position).abs() < adjustedSnap) {
            y = fg.position;
            snapType = 'frame_guide';
            break;
          }
        } else {
          if ((x - fg.position).abs() < adjustedSnap) {
            x = fg.position;
            snapType = 'frame_guide';
            break;
          }
        }
      }
    }

    // Constraint guide snapping
    if (snapType == null) {
      for (final cg in constraintGuides) {
        final pos = _resolvedConstraintGuides[cg.id];
        if (pos == null) continue;
        if (cg.isHorizontal) {
          if ((y - pos).abs() < adjustedSnap) {
            y = pos;
            snapType = 'constraint_guide';
            break;
          }
        } else {
          if ((x - pos).abs() < adjustedSnap) {
            x = pos;
            snapType = 'constraint_guide';
            break;
          }
        }
      }
    }

    // Record feedback glow + snap metadata
    if (snappedHIndex != null || snappedVIndex != null || snapType != null) {
      _lastSnapHGuideIndex = snappedHIndex;
      _lastSnapVGuideIndex = snappedVIndex;
      _lastSnapTime = DateTime.now();
      lastSnapType = snapType;
      lastSnapPosition = Offset(x, y);
    } else {
      lastSnapType = null;
      lastSnapPosition = null;
    }

    return Offset(x, y);
  }

  ({bool horizontal, bool vertical}) isNearGuide(
    Offset canvasPoint,
    double zoomLevel,
  ) {
    final adjustedSnap = snapDistance / zoomLevel;
    bool nearH = false;
    bool nearV = false;

    for (final guideY in horizontalGuides) {
      if ((canvasPoint.dy - guideY).abs() < adjustedSnap) {
        nearH = true;
        break;
      }
    }

    for (final guideX in verticalGuides) {
      if ((canvasPoint.dx - guideX).abs() < adjustedSnap) {
        nearV = true;
        break;
      }
    }

    // Also check frame-scoped guides
    if (!nearH || !nearV) {
      for (final fg in frameGuides) {
        if (fg.isHorizontal && !nearH) {
          if ((canvasPoint.dy - fg.position).abs() < adjustedSnap) nearH = true;
        } else if (!fg.isHorizontal && !nearV) {
          if ((canvasPoint.dx - fg.position).abs() < adjustedSnap) nearV = true;
        }
      }
    }

    // Also check constraint guides
    if (!nearH || !nearV) {
      for (final cg in constraintGuides) {
        final pos = _resolvedConstraintGuides[cg.id];
        if (pos == null) continue;
        if (cg.isHorizontal && !nearH) {
          if ((canvasPoint.dy - pos).abs() < adjustedSnap) nearH = true;
        } else if (!cg.isHorizontal && !nearV) {
          if ((canvasPoint.dx - pos).abs() < adjustedSnap) nearV = true;
        }
      }
    }

    return (horizontal: nearH, vertical: nearV);
  }

  // ─── Grid ──────────────────────────────────────────────────────────

  double gridStep(double zoom) =>
      customGridStep != null && customGridStep! > 0
          ? customGridStep!
          : _calculateNiceStep(zoom);

  double _calculateNiceStep(double zoom) {
    // Sub-pixel steps at high zoom for pixel-art precision
    if (zoom >= 4.0) {
      const subPixelSteps = [0.125, 0.25, 0.5, 1.0, 2.0, 5.0];
      const targetSpacing = 40.0;
      for (final step in subPixelSteps) {
        if (step * zoom >= targetSpacing) return step;
      }
    }
    const steps = [1.0, 2.0, 5.0, 10.0, 25.0, 50.0, 100.0];
    const targetSpacing = 40.0;
    for (final step in steps) {
      if (step * zoom >= targetSpacing) return step;
    }
    return 100.0;
  }

  // ─── Serialization, toJson/loadFromJson, _GuideSnapshot ────────────
  // See _ruler_guide_serialization.dart (part file)
}
