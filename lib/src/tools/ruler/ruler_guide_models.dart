import 'package:flutter/material.dart';

/// Type of griglia prospettica
enum PerspectiveType { none, onePoint, twoPoint, threePoint }

/// Stile della griglia
enum GridStyle { lines, dots, crosses }

/// Unità di misura dei righelli
enum RulerUnit { px, cm, mm, inches }

/// Phase 11C: Guide color themes
enum GuideColorTheme { defaultTheme, blueprint, neon, minimal, custom }

// ─── Model Classes ───────────────────────────────────────────────────────

/// Ruler bookmark mark
class BookmarkMark {
  final double position;
  final bool isHorizontal;
  final Color color;
  BookmarkMark({
    required this.position,
    required this.isHorizontal,
    required this.color,
  });
}

/// Phase 10F: Spacing lock between two guides
class SpacingLock {
  final bool isHorizontal;
  final int index1;
  final int index2;
  final double distance;
  SpacingLock({
    required this.isHorizontal,
    required this.index1,
    required this.index2,
    required this.distance,
  });
}

/// Phase 11A: Guide group
class GuideGroup {
  String name;
  final List<int> horizontalIndices;
  final List<int> verticalIndices;
  bool visible;
  bool locked;
  Color color;
  GuideGroup({
    required this.name,
    List<int>? horizontalIndices,
    List<int>? verticalIndices,
    this.visible = true,
    this.locked = false,
    this.color = const Color(0xFF42A5F5),
  }) : horizontalIndices = horizontalIndices ?? [],
       verticalIndices = verticalIndices ?? [];
}

// ─── Angular Guide Model ────────────────────────────────────────────────

class AngularGuide {
  Offset origin;
  double angleDeg;
  bool locked;
  Color? color;

  AngularGuide({
    required this.origin,
    required this.angleDeg,
    this.locked = false,
    this.color,
  });

  AngularGuide copyWith({
    Offset? origin,
    double? angleDeg,
    bool? locked,
    Color? color,
  }) => AngularGuide(
    origin: origin ?? this.origin,
    angleDeg: angleDeg ?? this.angleDeg,
    locked: locked ?? this.locked,
    color: color ?? this.color,
  );

  Map<String, dynamic> toJson() => {
    'ox': origin.dx,
    'oy': origin.dy,
    'ang': angleDeg,
    'locked': locked,
    'color': color?.toARGB32(),
  };

  factory AngularGuide.fromJson(Map<String, dynamic> json) => AngularGuide(
    origin: Offset(
      (json['ox'] as num?)?.toDouble() ?? 0,
      (json['oy'] as num?)?.toDouble() ?? 0,
    ),
    angleDeg: (json['ang'] as num?)?.toDouble() ?? 45,
    locked: (json['locked'] as bool?) ?? false,
    color: json['color'] != null ? Color(json['color'] as int) : null,
  );
}

// ─── Guide Preset Model ─────────────────────────────────────────────────

class GuidePreset {
  final String name;
  final List<double> hGuides;
  final List<double> vGuides;
  final List<Color?> hColors;
  final List<Color?> vColors;
  final List<AngularGuide> angularGuides;

  GuidePreset({
    required this.name,
    required this.hGuides,
    required this.vGuides,
    required this.hColors,
    required this.vColors,
    this.angularGuides = const [],
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'hGuides': hGuides,
    'vGuides': vGuides,
    'hColors': hColors.map((c) => c?.toARGB32()).toList(),
    'vColors': vColors.map((c) => c?.toARGB32()).toList(),
    'angGuides': angularGuides.map((g) => g.toJson()).toList(),
  };

  factory GuidePreset.fromJson(Map<String, dynamic> json) {
    return GuidePreset(
      name: json['name'] as String? ?? 'Preset',
      hGuides:
          (json['hGuides'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          [],
      vGuides:
          (json['vGuides'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          [],
      hColors:
          (json['hColors'] as List<dynamic>?)
              ?.map((e) => e != null ? Color(e as int) : null)
              .toList() ??
          [],
      vColors:
          (json['vColors'] as List<dynamic>?)
              ?.map((e) => e != null ? Color(e as int) : null)
              .toList() ??
          [],
      angularGuides:
          (json['angGuides'] as List<dynamic>?)
              ?.map((e) => AngularGuide.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}
