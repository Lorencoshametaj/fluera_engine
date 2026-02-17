import 'package:flutter/material.dart';
import '../config/multi_page_config.dart';

/// 💾 Modello for a'area di esportazione salvata
///
/// Permette all'utente di salvare aree frequentemente esportate
/// per riutilizzarle rapidamente without ridefinire i bounds.
/// Also supports multi-page configurations.
class SavedExportArea {
  final String id;
  final String name;
  final String canvasId;
  final Rect bounds;
  final DateTime createdAt;
  final DateTime? lastUsedAt;

  /// Optional multi-page configuration
  final MultiPageConfig? multiPageConfig;

  /// True if this area is for multi-page editing
  bool get isMultiPage => multiPageConfig != null;

  /// Aspect ratio for reference (not used for positioning)
  double get aspectRatio => bounds.width / bounds.height;

  const SavedExportArea({
    required this.id,
    required this.name,
    required this.canvasId,
    required this.bounds,
    required this.createdAt,
    this.lastUsedAt,
    this.multiPageConfig,
  });

  /// Creates una copia con campi aggiornati
  SavedExportArea copyWith({
    String? id,
    String? name,
    String? canvasId,
    Rect? bounds,
    DateTime? createdAt,
    DateTime? lastUsedAt,
    MultiPageConfig? multiPageConfig,
  }) {
    return SavedExportArea(
      id: id ?? this.id,
      name: name ?? this.name,
      canvasId: canvasId ?? this.canvasId,
      bounds: bounds ?? this.bounds,
      createdAt: createdAt ?? this.createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      multiPageConfig: multiPageConfig ?? this.multiPageConfig,
    );
  }

  /// Serialize in JSON per storage locale
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'canvasId': canvasId,
      'bounds': {
        'left': bounds.left,
        'top': bounds.top,
        'width': bounds.width,
        'height': bounds.height,
      },
      'createdAt': createdAt.toIso8601String(),
      'lastUsedAt': lastUsedAt?.toIso8601String(),
      'multiPageConfig': multiPageConfig?.toJson(),
    };
  }

  /// Deserializza da JSON
  factory SavedExportArea.fromJson(Map<String, dynamic> json) {
    final boundsJson = json['bounds'] as Map<String, dynamic>;
    return SavedExportArea(
      id: json['id'] as String,
      name: json['name'] as String,
      canvasId: json['canvasId'] as String,
      bounds: Rect.fromLTWH(
        (boundsJson['left'] as num).toDouble(),
        (boundsJson['top'] as num).toDouble(),
        (boundsJson['width'] as num).toDouble(),
        (boundsJson['height'] as num).toDouble(),
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastUsedAt:
          json['lastUsedAt'] != null
              ? DateTime.parse(json['lastUsedAt'] as String)
              : null,
      multiPageConfig:
          json['multiPageConfig'] != null
              ? MultiPageConfig.fromJson(
                json['multiPageConfig'] as Map<String, dynamic>,
              )
              : null,
    );
  }

  /// Genera un ID unico for aa nuova area
  static String generateId() {
    return 'export_area_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Formatta le dimensioni of the area per visualizzazione
  String get formattedSize {
    return '${bounds.width.toInt()} × ${bounds.height.toInt()}';
  }

  /// Formatta il tempo trascorso from the creazione
  String get timeAgo {
    final now = DateTime.now();
    final diff = now.difference(createdAt);

    if (diff.inDays == 0) {
      if (diff.inHours == 0) {
        return '${diff.inMinutes} min fa';
      }
      return '${diff.inHours}h fa';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays}g fa';
    }
    return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SavedExportArea &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// 📚 Manager for the aree salvate (in-memory cache)
class SavedExportAreasManager {
  /// Istanza singleton
  static final SavedExportAreasManager instance = SavedExportAreasManager._();

  SavedExportAreasManager._();

  final Map<String, List<SavedExportArea>> _areasByCanvas = {};

  /// Get le aree salvate for a canvas specifico
  List<SavedExportArea> getAreasForCanvas(String canvasId) {
    return List.unmodifiable(_areasByCanvas[canvasId] ?? []);
  }

  /// Adds a new saved area
  void addArea(SavedExportArea area) {
    _areasByCanvas.putIfAbsent(area.canvasId, () => []);
    _areasByCanvas[area.canvasId]!.add(area);
  }

  /// Remove un'saved area
  void removeArea(String areaId) {
    for (final areas in _areasByCanvas.values) {
      areas.removeWhere((a) => a.id == areaId);
    }
  }

  /// Updates lastUsedAt for a'area
  void markAsUsed(String areaId) {
    for (final areas in _areasByCanvas.values) {
      final index = areas.indexWhere((a) => a.id == areaId);
      if (index != -1) {
        areas[index] = areas[index].copyWith(lastUsedAt: DateTime.now());
        break;
      }
    }
  }

  /// Loads tutte le aree da una lista JSON
  void loadFromJson(List<Map<String, dynamic>> jsonList) {
    _areasByCanvas.clear();
    for (final json in jsonList) {
      final area = SavedExportArea.fromJson(json);
      addArea(area);
    }
  }

  /// Esporta tutte le aree in JSON
  List<Map<String, dynamic>> toJson() {
    final result = <Map<String, dynamic>>[];
    for (final areas in _areasByCanvas.values) {
      for (final area in areas) {
        result.add(area.toJson());
      }
    }
    return result;
  }

  /// Numero totale di aree salvate
  int get totalCount {
    return _areasByCanvas.values.fold(0, (sum, areas) => sum + areas.length);
  }
}
