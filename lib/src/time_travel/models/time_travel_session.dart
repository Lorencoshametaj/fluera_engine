import '../../history/canvas_delta_tracker.dart';

/// 📜 Sessione di Time Travel — raggruppa eventi per session di editing
///
/// Each sessione corrisponde a un'apertura-chiusura of the canvas professionale.
/// Le sessioni sono serializzate in un file indice leggero (`index.json`);
/// i dati effettivi degli eventi risiedono in file compressi separati.
class TimeTravelSession {
  final String id;
  final String canvasId;
  final DateTime startTime;
  final DateTime endTime;
  final int deltaCount;
  final String deltaFilePath; // Path al file .tt.jsonl.gz compresso

  // Metadati rapidi for the timeline UI (evitano di caricare i delta)
  final int strokesAdded;
  final int elementsModified;

  TimeTravelSession({
    required this.id,
    required this.canvasId,
    required this.startTime,
    required this.endTime,
    required this.deltaCount,
    required this.deltaFilePath,
    this.strokesAdded = 0,
    this.elementsModified = 0,
  });

  /// Durata totale della sessione
  Duration get duration => endTime.difference(startTime);

  /// Serialize per l'indice (leggero, ~100 byte per session)
  Map<String, dynamic> toJson() => {
    'id': id,
    'canvasId': canvasId,
    'startMs': startTime.millisecondsSinceEpoch,
    'endMs': endTime.millisecondsSinceEpoch,
    'count': deltaCount,
    'file': deltaFilePath,
    'strokes': strokesAdded,
    'modified': elementsModified,
  };

  factory TimeTravelSession.fromJson(Map<String, dynamic> json) {
    return TimeTravelSession(
      id: json['id'] as String,
      canvasId: json['canvasId'] as String,
      startTime: DateTime.fromMillisecondsSinceEpoch(json['startMs'] as int),
      endTime: DateTime.fromMillisecondsSinceEpoch(json['endMs'] as int),
      deltaCount: json['count'] as int,
      deltaFilePath: json['file'] as String,
      strokesAdded: json['strokes'] as int? ?? 0,
      elementsModified: json['modified'] as int? ?? 0,
    );
  }

  @override
  String toString() =>
      'TimeTravelSession($id, $deltaCount events, ${duration.inSeconds}s)';
}

/// 🎬 Singolo evento Time Travel — wrapfor theggero e compatto
///
/// A differenza di `CanvasDelta`, usa timestamp relativi (ms from the beginning
/// sessione) per ridurre il payload e non include il campo `id` (l'ordine
/// sequenziale nell'array is sufficiente for the replay).
class TimeTravelEvent {
  final CanvasDeltaType type;
  final String layerId;
  final int? pageIndex;

  /// Millisecondi from the beginning della sessione (non epoch assoluto)
  final int timestampMs;

  /// Dati dell'elemento (stroke JSON, shape JSON, ecc.)
  /// Null per eventi di tipo *Removed (basta elementId)
  final Map<String, dynamic>? elementData;

  /// ID dell'elemento coinvolto (per remove/update)
  final String? elementId;

  TimeTravelEvent({
    required this.type,
    required this.layerId,
    this.pageIndex,
    required this.timestampMs,
    this.elementData,
    this.elementId,
  });

  /// Serializezione compatta per JSONL
  Map<String, dynamic> toJson() => {
    't': type.index,
    'l': layerId,
    if (pageIndex != null) 'p': pageIndex,
    'ms': timestampMs,
    if (elementData != null) 'd': elementData,
    if (elementId != null) 'e': elementId,
  };

  factory TimeTravelEvent.fromJson(Map<String, dynamic> json) {
    return TimeTravelEvent(
      type: CanvasDeltaType.values[json['t'] as int],
      layerId: json['l'] as String,
      pageIndex: json['p'] as int?,
      timestampMs: json['ms'] as int,
      elementData:
          json['d'] != null
              ? Map<String, dynamic>.from(json['d'] as Map)
              : null,
      elementId: json['e'] as String?,
    );
  }

  /// È un evento che aggiunge un elemento?
  bool get isAddition =>
      type == CanvasDeltaType.strokeAdded ||
      type == CanvasDeltaType.shapeAdded ||
      type == CanvasDeltaType.textAdded ||
      type == CanvasDeltaType.imageAdded ||
      type == CanvasDeltaType.layerAdded ||
      type == CanvasDeltaType.pageAdded;

  /// È un evento che rimuove un elemento?
  bool get isRemoval =>
      type == CanvasDeltaType.strokeRemoved ||
      type == CanvasDeltaType.shapeRemoved ||
      type == CanvasDeltaType.textRemoved ||
      type == CanvasDeltaType.imageRemoved ||
      type == CanvasDeltaType.layerRemoved ||
      type == CanvasDeltaType.pageRemoved;

  /// È un evento di modifica (update)?
  bool get isUpdate =>
      type == CanvasDeltaType.textUpdated ||
      type == CanvasDeltaType.imageUpdated ||
      type == CanvasDeltaType.layerModified ||
      type == CanvasDeltaType.layerCleared;

  /// Serialize as single JSON line (for JSONL)
  String toJsonLine() => '${toJson()}';

  @override
  String toString() =>
      'TimeTravelEvent(${type.name}, layer: $layerId, ms: $timestampMs)';
}
