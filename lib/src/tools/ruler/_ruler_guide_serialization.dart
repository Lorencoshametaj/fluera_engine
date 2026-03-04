part of 'ruler_guide_system.dart';

// ════════════════════════════════════════════════════════════════════════
// 📏 RulerGuideSystem — Serialization & Undo Snapshot
// ════════════════════════════════════════════════════════════════════════

extension RulerSerializationMethods on RulerGuideSystem {
  Map<String, dynamic> toJson() => {
    'hGuides': List<double>.from(horizontalGuides),
    'vGuides': List<double>.from(verticalGuides),
    'hLocked': List<bool>.from(horizontalLocked),
    'vLocked': List<bool>.from(verticalLocked),
    'hColors': horizontalColors.map((c) => c?.toARGB32()).toList(),
    'vColors': verticalColors.map((c) => c?.toARGB32()).toList(),
    'hLabels': List<String?>.from(horizontalLabels),
    'vLabels': List<String?>.from(verticalLabels),
    'snapDist': snapDistance,
    'snapOn': snapEnabled,
    'gridOn': gridVisible,
    'gridSnap': gridSnapEnabled,
    'gridSt': gridStyle.index,
    'isoOn': isometricGridVisible,
    'isoAng': isometricAngle,
    'unit': currentUnit.index,
    'ppi': ppi,
    'smartOn': smartGuidesEnabled,
    'symOn': symmetryEnabled,
    'symIdx': symmetryAxisIndex,
    'symIsH': symmetryAxisIsHorizontal,
    'symSeg': symmetrySegments,
    'perspType': perspectiveType.index,
    'vp1x': vp1.dx,
    'vp1y': vp1.dy,
    'vp2x': vp2.dx,
    'vp2y': vp2.dy,
    'vp3x': vp3.dx,
    'vp3y': vp3.dy,
    'perspDensity': perspectiveLineDensity,
    'radialOn': radialGridVisible,
    'radialCx': radialCenter.dx,
    'radialCy': radialCenter.dy,
    'radialDiv': radialDivisions,
    'radialRings': radialRings,
    'radialRadius': radialMaxRadius,
    // Phase 5
    'angGuides': angularGuides.map((g) => g.toJson()).toList(),
    'showLabels': showGuideLabels,
    'customStep': customGridStep,
    'originX': rulerOrigin.dx,
    'originY': rulerOrigin.dy,
    'presets': savedPresets.map((p) => p.toJson()).toList(),
    // Enterprise v2 — previously missing fields
    'guideOpacity': guideOpacity,
    'snapStrength': snapStrength,
    'guideTheme': guideColorTheme.index,
    'goldenSpiral': showGoldenSpiral,
    'protractorStep': protractorSnapStep,
    'crosshairOn': crosshairEnabled,
    'rulersOn': rulersVisible,
    'guidesOn': guidesVisible,
    'bookmarks':
        bookmarkMarks
            .map(
              (b) => {
                'pos': b.position,
                'isH': b.isHorizontal,
                'color': b.color.toARGB32(),
              },
            )
            .toList(),
    'spacingLocks':
        spacingLocks
            .map(
              (s) => {
                'isH': s.isHorizontal,
                'i1': s.index1,
                'i2': s.index2,
                'dist': s.distance,
              },
            )
            .toList(),
    'namedGroups':
        namedGuideGroups
            .map(
              (g) => {
                'name': g.name,
                'hIdx': List<int>.from(g.horizontalIndices),
                'vIdx': List<int>.from(g.verticalIndices),
                'visible': g.visible,
                'locked': g.locked,
                'color': g.color.toARGB32(),
              },
            )
            .toList(),
    'hPercentGuides': horizontalPercentGuides.map(
      (k, v) => MapEntry(k.toString(), v),
    ),
    'vPercentGuides': verticalPercentGuides.map(
      (k, v) => MapEntry(k.toString(), v),
    ),
    // Enterprise v3 — frame-scoped, constraint, grid opacity
    'gridOpacity': gridOpacity,
    'frameGuides': frameGuides.map((g) => g.toJson()).toList(),
    'constraintGuides': constraintGuides.map((g) => g.toJson()).toList(),
  };

  void loadFromJson(Map<String, dynamic>? json) {
    if (json == null) return;
    horizontalGuides.clear();
    verticalGuides.clear();
    horizontalLocked.clear();
    verticalLocked.clear();
    horizontalColors.clear();
    verticalColors.clear();

    final hList = json['hGuides'] as List<dynamic>?;
    if (hList != null) {
      horizontalGuides.addAll(hList.map((e) => (e as num).toDouble()));
    }

    final vList = json['vGuides'] as List<dynamic>?;
    if (vList != null) {
      verticalGuides.addAll(vList.map((e) => (e as num).toDouble()));
    }

    final hLockedList = json['hLocked'] as List<dynamic>?;
    if (hLockedList != null) {
      horizontalLocked.addAll(hLockedList.map((e) => e as bool));
    }
    while (horizontalLocked.length < horizontalGuides.length) {
      horizontalLocked.add(false);
    }

    final vLockedList = json['vLocked'] as List<dynamic>?;
    if (vLockedList != null) {
      verticalLocked.addAll(vLockedList.map((e) => e as bool));
    }
    while (verticalLocked.length < verticalGuides.length) {
      verticalLocked.add(false);
    }

    final hColorList = json['hColors'] as List<dynamic>?;
    if (hColorList != null) {
      horizontalColors.addAll(
        hColorList.map((e) => e != null ? Color(e as int) : null),
      );
    }
    while (horizontalColors.length < horizontalGuides.length) {
      horizontalColors.add(null);
    }

    final vColorList = json['vColors'] as List<dynamic>?;
    if (vColorList != null) {
      verticalColors.addAll(
        vColorList.map((e) => e != null ? Color(e as int) : null),
      );
    }
    while (verticalColors.length < verticalGuides.length) {
      verticalColors.add(null);
    }

    snapDistance = (json['snapDist'] as num?)?.toDouble() ?? 8.0;
    snapEnabled = (json['snapOn'] as bool?) ?? true;
    gridVisible = (json['gridOn'] as bool?) ?? false;
    gridSnapEnabled = (json['gridSnap'] as bool?) ?? false;

    // Grid style
    final gsIdx = json['gridSt'] as int?;
    gridStyle =
        gsIdx != null && gsIdx < GridStyle.values.length
            ? GridStyle.values[gsIdx]
            : GridStyle.lines;

    // Isometric
    isometricGridVisible = (json['isoOn'] as bool?) ?? false;
    isometricAngle = (json['isoAng'] as num?)?.toDouble() ?? 30.0;

    // Unit
    final uIdx = json['unit'] as int?;
    currentUnit =
        uIdx != null && uIdx < RulerUnit.values.length
            ? RulerUnit.values[uIdx]
            : RulerUnit.px;
    ppi = (json['ppi'] as num?)?.toDouble() ?? 72.0;

    // Smart guides
    smartGuidesEnabled = (json['smartOn'] as bool?) ?? false;

    // Symmetry
    symmetryEnabled = (json['symOn'] as bool?) ?? false;
    symmetryAxisIndex = json['symIdx'] as int?;
    symmetryAxisIsHorizontal = (json['symIsH'] as bool?) ?? true;

    // Perspective
    final ptIdx = json['perspType'] as int?;
    perspectiveType =
        ptIdx != null && ptIdx < PerspectiveType.values.length
            ? PerspectiveType.values[ptIdx]
            : PerspectiveType.none;
    vp1 = Offset(
      (json['vp1x'] as num?)?.toDouble() ?? 0,
      (json['vp1y'] as num?)?.toDouble() ?? 0,
    );
    vp2 = Offset(
      (json['vp2x'] as num?)?.toDouble() ?? 0,
      (json['vp2y'] as num?)?.toDouble() ?? 0,
    );
    vp3 = Offset(
      (json['vp3x'] as num?)?.toDouble() ?? 0,
      (json['vp3y'] as num?)?.toDouble() ?? 0,
    );
    perspectiveLineDensity = (json['perspDensity'] as int?) ?? 16;

    // Radial
    radialGridVisible = (json['radialOn'] as bool?) ?? false;
    radialCenter = Offset(
      (json['radialCx'] as num?)?.toDouble() ?? 0,
      (json['radialCy'] as num?)?.toDouble() ?? 0,
    );
    radialDivisions = (json['radialDiv'] as int?) ?? 12;
    radialRings = (json['radialRings'] as int?) ?? 6;
    radialMaxRadius = (json['radialRadius'] as num?)?.toDouble() ?? 400;

    // Phase 5
    symmetrySegments = (json['symSeg'] as int?) ?? 2;

    angularGuides.clear();
    final agList = json['angGuides'] as List<dynamic>?;
    if (agList != null) {
      for (final ag in agList) {
        if (ag is Map<String, dynamic>) {
          angularGuides.add(AngularGuide.fromJson(ag));
        }
      }
    }

    showGuideLabels = (json['showLabels'] as bool?) ?? false;
    customGridStep = (json['customStep'] as num?)?.toDouble();
    rulerOrigin = Offset(
      (json['originX'] as num?)?.toDouble() ?? 0,
      (json['originY'] as num?)?.toDouble() ?? 0,
    );

    savedPresets.clear();
    final pList = json['presets'] as List<dynamic>?;
    if (pList != null) {
      for (final p in pList) {
        if (p is Map<String, dynamic>) {
          savedPresets.add(GuidePreset.fromJson(p));
        }
      }
    }

    // Enterprise v2 — previously missing fields
    guideOpacity = (json['guideOpacity'] as num?)?.toDouble() ?? 1.0;
    snapStrength = (json['snapStrength'] as num?)?.toDouble() ?? 0.5;
    final gtIdx = json['guideTheme'] as int?;
    guideColorTheme =
        gtIdx != null && gtIdx < GuideColorTheme.values.length
            ? GuideColorTheme.values[gtIdx]
            : GuideColorTheme.defaultTheme;
    showGoldenSpiral = (json['goldenSpiral'] as bool?) ?? false;
    protractorSnapStep = (json['protractorStep'] as num?)?.toDouble() ?? 15.0;
    crosshairEnabled = (json['crosshairOn'] as bool?) ?? false;
    rulersVisible = (json['rulersOn'] as bool?) ?? true;
    guidesVisible = (json['guidesOn'] as bool?) ?? true;

    // Labels
    horizontalLabels.clear();
    verticalLabels.clear();
    final hlList = json['hLabels'] as List<dynamic>?;
    if (hlList != null) {
      horizontalLabels.addAll(hlList.map((e) => e as String?));
    }
    while (horizontalLabels.length < horizontalGuides.length) {
      horizontalLabels.add(null);
    }
    final vlList = json['vLabels'] as List<dynamic>?;
    if (vlList != null) {
      verticalLabels.addAll(vlList.map((e) => e as String?));
    }
    while (verticalLabels.length < verticalGuides.length) {
      verticalLabels.add(null);
    }

    // Bookmarks
    bookmarkMarks.clear();
    final bmList = json['bookmarks'] as List<dynamic>?;
    if (bmList != null) {
      for (final bm in bmList) {
        if (bm is Map<String, dynamic>) {
          bookmarkMarks.add(
            BookmarkMark(
              position: (bm['pos'] as num?)?.toDouble() ?? 0,
              isHorizontal: (bm['isH'] as bool?) ?? true,
              color: Color((bm['color'] as int?) ?? 0xFF42A5F5),
            ),
          );
        }
      }
    }

    // Spacing locks
    spacingLocks.clear();
    final slList = json['spacingLocks'] as List<dynamic>?;
    if (slList != null) {
      for (final sl in slList) {
        if (sl is Map<String, dynamic>) {
          spacingLocks.add(
            SpacingLock(
              isHorizontal: (sl['isH'] as bool?) ?? true,
              index1: (sl['i1'] as int?) ?? 0,
              index2: (sl['i2'] as int?) ?? 0,
              distance: (sl['dist'] as num?)?.toDouble() ?? 0,
            ),
          );
        }
      }
    }

    // Named groups
    namedGuideGroups.clear();
    final ngList = json['namedGroups'] as List<dynamic>?;
    if (ngList != null) {
      for (final ng in ngList) {
        if (ng is Map<String, dynamic>) {
          namedGuideGroups.add(
            GuideGroup(
              name: ng['name'] as String? ?? 'Group',
              horizontalIndices:
                  (ng['hIdx'] as List<dynamic>?)?.map((e) => e as int).toList(),
              verticalIndices:
                  (ng['vIdx'] as List<dynamic>?)?.map((e) => e as int).toList(),
              visible: (ng['visible'] as bool?) ?? true,
              locked: (ng['locked'] as bool?) ?? false,
              color: Color((ng['color'] as int?) ?? 0xFF42A5F5),
            ),
          );
        }
      }
    }

    // Percent guides
    horizontalPercentGuides.clear();
    final hpMap = json['hPercentGuides'] as Map<String, dynamic>?;
    if (hpMap != null) {
      for (final e in hpMap.entries) {
        horizontalPercentGuides[int.parse(e.key)] = (e.value as num).toDouble();
      }
    }
    verticalPercentGuides.clear();
    final vpMap = json['vPercentGuides'] as Map<String, dynamic>?;
    if (vpMap != null) {
      for (final e in vpMap.entries) {
        verticalPercentGuides[int.parse(e.key)] = (e.value as num).toDouble();
      }
    }

    // Enterprise v3 — frame-scoped, constraint, grid opacity
    gridOpacity = (json['gridOpacity'] as num?)?.toDouble() ?? 1.0;

    frameGuides.clear();
    final fgList = json['frameGuides'] as List<dynamic>?;
    if (fgList != null) {
      for (final fg in fgList) {
        if (fg is Map<String, dynamic>) {
          frameGuides.add(CanvasGuide.fromJson(fg));
        }
      }
    }

    constraintGuides.clear();
    _resolvedConstraintGuides.clear();
    final cgList = json['constraintGuides'] as List<dynamic>?;
    if (cgList != null) {
      for (final cg in cgList) {
        if (cg is Map<String, dynamic>) {
          constraintGuides.add(ConstraintGuide.fromJson(cg));
        }
      }
    }
  }
}

// ─── Undo/Redo Snapshot ──────────────────────────────────────────────

class _GuideSnapshot {
  final List<double> hGuides;
  final List<double> vGuides;
  final List<bool> hLocked;
  final List<bool> vLocked;
  final List<Color?> hColors;
  final List<Color?> vColors;
  final List<String?> hLabels;
  final List<String?> vLabels;
  final List<AngularGuide> angularGuides;
  final List<BookmarkMark> bookmarks;
  final List<SpacingLock> spacingLocks;
  final double guideOpacity;
  final double gridOpacity;
  final double snapStrength;
  final bool showGoldenSpiral;
  final List<CanvasGuide> frameGuides;
  final List<ConstraintGuide> constraintGuides;
  final List<GuideGroup> namedGuideGroups;
  final Map<int, double> horizontalPercentGuides;
  final Map<int, double> verticalPercentGuides;
  final GuideColorTheme guideColorTheme;
  final double protractorSnapStep;
  final bool symmetryEnabled;
  final int? symmetryAxisIndex;
  final bool symmetryAxisIsHorizontal;
  final int symmetrySegments;

  _GuideSnapshot({
    required this.hGuides,
    required this.vGuides,
    required this.hLocked,
    required this.vLocked,
    required this.hColors,
    required this.vColors,
    required this.hLabels,
    required this.vLabels,
    required this.angularGuides,
    required this.bookmarks,
    required this.spacingLocks,
    required this.guideOpacity,
    required this.gridOpacity,
    required this.snapStrength,
    required this.showGoldenSpiral,
    required this.frameGuides,
    required this.constraintGuides,
    required this.namedGuideGroups,
    required this.horizontalPercentGuides,
    required this.verticalPercentGuides,
    required this.guideColorTheme,
    required this.protractorSnapStep,
    required this.symmetryEnabled,
    required this.symmetryAxisIndex,
    required this.symmetryAxisIsHorizontal,
    required this.symmetrySegments,
  });

  factory _GuideSnapshot.from(RulerGuideSystem sys) {
    return _GuideSnapshot(
      hGuides: List<double>.from(sys.horizontalGuides),
      vGuides: List<double>.from(sys.verticalGuides),
      hLocked: List<bool>.from(sys.horizontalLocked),
      vLocked: List<bool>.from(sys.verticalLocked),
      hColors: List<Color?>.from(sys.horizontalColors),
      vColors: List<Color?>.from(sys.verticalColors),
      hLabels: List<String?>.from(sys.horizontalLabels),
      vLabels: List<String?>.from(sys.verticalLabels),
      angularGuides: sys.angularGuides.map((g) => g.copyWith()).toList(),
      bookmarks: List<BookmarkMark>.from(sys.bookmarkMarks),
      spacingLocks: List<SpacingLock>.from(sys.spacingLocks),
      guideOpacity: sys.guideOpacity,
      gridOpacity: sys.gridOpacity,
      snapStrength: sys.snapStrength,
      showGoldenSpiral: sys.showGoldenSpiral,
      frameGuides: sys.frameGuides.map((g) => g.copyWith()).toList(),
      constraintGuides: sys.constraintGuides.map((g) => g.copyWith()).toList(),
      namedGuideGroups:
          sys.namedGuideGroups
              .map(
                (g) => GuideGroup(
                  name: g.name,
                  horizontalIndices: List<int>.from(g.horizontalIndices),
                  verticalIndices: List<int>.from(g.verticalIndices),
                  visible: g.visible,
                  locked: g.locked,
                  color: g.color,
                ),
              )
              .toList(),
      horizontalPercentGuides: Map<int, double>.from(
        sys.horizontalPercentGuides,
      ),
      verticalPercentGuides: Map<int, double>.from(sys.verticalPercentGuides),
      guideColorTheme: sys.guideColorTheme,
      protractorSnapStep: sys.protractorSnapStep,
      symmetryEnabled: sys.symmetryEnabled,
      symmetryAxisIndex: sys.symmetryAxisIndex,
      symmetryAxisIsHorizontal: sys.symmetryAxisIsHorizontal,
      symmetrySegments: sys.symmetrySegments,
    );
  }

  void restoreTo(RulerGuideSystem sys) {
    sys.horizontalGuides
      ..clear()
      ..addAll(hGuides);
    sys.verticalGuides
      ..clear()
      ..addAll(vGuides);
    sys.horizontalLocked
      ..clear()
      ..addAll(hLocked);
    sys.verticalLocked
      ..clear()
      ..addAll(vLocked);
    sys.horizontalColors
      ..clear()
      ..addAll(hColors);
    sys.verticalColors
      ..clear()
      ..addAll(vColors);
    sys.horizontalLabels
      ..clear()
      ..addAll(hLabels);
    sys.verticalLabels
      ..clear()
      ..addAll(vLabels);
    sys.angularGuides
      ..clear()
      ..addAll(angularGuides);
    sys.bookmarkMarks
      ..clear()
      ..addAll(bookmarks);
    sys.spacingLocks
      ..clear()
      ..addAll(spacingLocks);
    sys.frameGuides
      ..clear()
      ..addAll(frameGuides);
    sys.constraintGuides
      ..clear()
      ..addAll(constraintGuides);
    sys.namedGuideGroups
      ..clear()
      ..addAll(namedGuideGroups);
    sys.horizontalPercentGuides
      ..clear()
      ..addAll(horizontalPercentGuides);
    sys.verticalPercentGuides
      ..clear()
      ..addAll(verticalPercentGuides);
    sys.guideOpacity = guideOpacity;
    sys.gridOpacity = gridOpacity;
    sys.snapStrength = snapStrength;
    sys.showGoldenSpiral = showGoldenSpiral;
    sys.guideColorTheme = guideColorTheme;
    sys.protractorSnapStep = protractorSnapStep;
    sys.symmetryEnabled = symmetryEnabled;
    sys.symmetryAxisIndex = symmetryAxisIndex;
    sys.symmetryAxisIsHorizontal = symmetryAxisIsHorizontal;
    sys.symmetrySegments = symmetrySegments;
    sys.selectedHorizontalGuides.clear();
    sys.selectedVerticalGuides.clear();
  }
}
