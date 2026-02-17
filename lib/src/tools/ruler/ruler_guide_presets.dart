import 'package:flutter/material.dart';
import './ruler_guide_system.dart';

/// Extension separating preset/serialization logic from [RulerGuideSystem].
extension RulerGuidePresets on RulerGuideSystem {
  // ─── Preset Export/Import ──────────────────────────────────────────────

  /// Esporta le guide correnti come un preset
  GuidePreset exportPreset(String name) {
    return GuidePreset(
      name: name,
      hGuides: List<double>.from(horizontalGuides),
      vGuides: List<double>.from(verticalGuides),
      hColors: List<Color?>.from(horizontalColors),
      vColors: List<Color?>.from(verticalColors),
      angularGuides: angularGuides.map((g) => g.copyWith()).toList(),
    );
  }

  /// Importa un preset (sostituisce le guide correnti)
  void importPreset(GuidePreset preset) {
    saveSnapshot();
    horizontalGuides
      ..clear()
      ..addAll(preset.hGuides);
    verticalGuides
      ..clear()
      ..addAll(preset.vGuides);
    horizontalLocked
      ..clear()
      ..addAll(List.filled(preset.hGuides.length, false));
    verticalLocked
      ..clear()
      ..addAll(List.filled(preset.vGuides.length, false));
    horizontalColors
      ..clear()
      ..addAll(preset.hColors);
    verticalColors
      ..clear()
      ..addAll(preset.vColors);
    angularGuides
      ..clear()
      ..addAll(preset.angularGuides);
    selectedHorizontalGuides.clear();
    selectedVerticalGuides.clear();
  }

  /// Save current guides as a named preset
  void savePreset(String name) {
    savedPresets.add(exportPreset(name));
  }

  /// Delete a saved preset by index
  void deletePresetAt(int index) {
    if (index >= 0 && index < savedPresets.length) {
      savedPresets.removeAt(index);
    }
  }

  // ─── JSON Serialization ────────────────────────────────────────────────

  /// Export all saved presets to a JSON-serializable map
  Map<String, dynamic> exportPresetsToJson() {
    return {
      'presets':
          savedPresets
              .map(
                (p) => {
                  'name': p.name,
                  'hGuides': p.hGuides,
                  'vGuides': p.vGuides,
                  'hColors': p.hColors.map((c) => c?.toARGB32()).toList(),
                  'vColors': p.vColors.map((c) => c?.toARGB32()).toList(),
                  'angularGuides':
                      p.angularGuides
                          .map(
                            (g) => {
                              'ox': g.origin.dx,
                              'oy': g.origin.dy,
                              'angle': g.angleDeg,
                              'color': g.color?.toARGB32(),
                            },
                          )
                          .toList(),
                },
              )
              .toList(),
    };
  }

  /// Import presets from a JSON map (replaces existing presets)
  void importPresetsFromJson(Map<String, dynamic> json) {
    final presetsList = json['presets'] as List<dynamic>?;
    if (presetsList == null) return;
    savedPresets.clear();
    for (final p in presetsList) {
      final map = p as Map<String, dynamic>;
      savedPresets.add(
        GuidePreset(
          name: map['name'] as String? ?? 'Unnamed',
          hGuides:
              (map['hGuides'] as List<dynamic>?)
                  ?.map((e) => (e as num).toDouble())
                  .toList() ??
              [],
          vGuides:
              (map['vGuides'] as List<dynamic>?)
                  ?.map((e) => (e as num).toDouble())
                  .toList() ??
              [],
          hColors:
              (map['hColors'] as List<dynamic>?)
                  ?.map((e) => e != null ? Color(e as int) : null)
                  .toList() ??
              [],
          vColors:
              (map['vColors'] as List<dynamic>?)
                  ?.map((e) => e != null ? Color(e as int) : null)
                  .toList() ??
              [],
          angularGuides:
              (map['angularGuides'] as List<dynamic>?)?.map((g) {
                final gm = g as Map<String, dynamic>;
                return AngularGuide(
                  origin: Offset(
                    (gm['ox'] as num).toDouble(),
                    (gm['oy'] as num).toDouble(),
                  ),
                  angleDeg: (gm['angle'] as num).toDouble(),
                  color: gm['color'] != null ? Color(gm['color'] as int) : null,
                );
              }).toList() ??
              [],
        ),
      );
    }
  }

  /// Export current guides to JSON
  Map<String, dynamic> exportGuidesJson() {
    return {
      'horizontal': horizontalGuides.toList(),
      'vertical': verticalGuides.toList(),
      'hLocked': horizontalLocked.toList(),
      'vLocked': verticalLocked.toList(),
      'hLabels': horizontalLabels.toList(),
      'vLabels': verticalLabels.toList(),
      'unit': currentUnit.name,
    };
  }

  /// Import guides from JSON
  void importGuidesJson(Map<String, dynamic> json) {
    saveSnapshot();
    clearAllGuides();
    final hGuides = (json['horizontal'] as List?)?.cast<num>() ?? [];
    final vGuides = (json['vertical'] as List?)?.cast<num>() ?? [];
    for (final h in hGuides) addHorizontalGuide(h.toDouble());
    for (final v in vGuides) addVerticalGuide(v.toDouble());

    final hLocked = (json['hLocked'] as List?)?.cast<bool>() ?? [];
    final vLocked = (json['vLocked'] as List?)?.cast<bool>() ?? [];
    for (int i = 0; i < hLocked.length && i < horizontalLocked.length; i++) {
      horizontalLocked[i] = hLocked[i];
    }
    for (int i = 0; i < vLocked.length && i < verticalLocked.length; i++) {
      verticalLocked[i] = vLocked[i];
    }

    final hLabels = (json['hLabels'] as List?)?.cast<String?>() ?? [];
    final vLabels = (json['vLabels'] as List?)?.cast<String?>() ?? [];
    for (int i = 0; i < hLabels.length && i < horizontalLabels.length; i++) {
      horizontalLabels[i] = hLabels[i];
    }
    for (int i = 0; i < vLabels.length && i < verticalLabels.length; i++) {
      verticalLabels[i] = vLabels[i];
    }
  }

  // ─── Guide Presets (Layout) ────────────────────────────────────────────

  /// Center crosshair preset
  void addCenterPreset(Rect viewport) {
    saveSnapshot();
    addVerticalGuide(viewport.center.dx);
    addHorizontalGuide(viewport.center.dy);
  }

  /// Rule of thirds preset
  void addThirdsPreset(Rect viewport) {
    saveSnapshot();
    final w = viewport.width;
    final h = viewport.height;
    addVerticalGuide(viewport.left + w / 3);
    addVerticalGuide(viewport.left + w * 2 / 3);
    addHorizontalGuide(viewport.top + h / 3);
    addHorizontalGuide(viewport.top + h * 2 / 3);
  }

  /// Golden ratio preset
  void addGoldenRatioPreset(Rect viewport) {
    saveSnapshot();
    const phi = 0.618;
    final w = viewport.width;
    final h = viewport.height;
    addVerticalGuide(viewport.left + w * (1 - phi));
    addVerticalGuide(viewport.left + w * phi);
    addHorizontalGuide(viewport.top + h * (1 - phi));
    addHorizontalGuide(viewport.top + h * phi);
  }

  /// Margin guides preset
  void addMarginsPreset(Rect viewport, double margin) {
    saveSnapshot();
    addVerticalGuide(viewport.left + margin);
    addVerticalGuide(viewport.right - margin);
    addHorizontalGuide(viewport.top + margin);
    addHorizontalGuide(viewport.bottom - margin);
  }

  /// Adds guide per aspect ratio centrate nel viewport
  void addAspectRatioPreset(Rect viewport, double ratio) {
    saveSnapshot();
    final cx = viewport.center.dx;
    final cy = viewport.center.dy;
    final viewW = viewport.width;
    final viewH = viewport.height;

    double rectW, rectH;
    if (viewW / viewH > ratio) {
      rectH = viewH * 0.85;
      rectW = rectH * ratio;
    } else {
      rectW = viewW * 0.85;
      rectH = rectW / ratio;
    }

    addVerticalGuide(cx - rectW / 2);
    addVerticalGuide(cx + rectW / 2);
    addHorizontalGuide(cy - rectH / 2);
    addHorizontalGuide(cy + rectH / 2);
  }
}
