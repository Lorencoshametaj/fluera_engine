import 'dart:convert';
import '../../drawing/models/pro_drawing_point.dart';

/// Synchronized stroke with timestamps relative to the recording
/// Contiene il timestamp di inizio e fine of the stroke rispetto all'inizio of the recording
class SyncedStroke {
  /// Lo stroke originale completo
  final ProStroke stroke;

  /// Start timestamp relative to the recording (milliseconds)
  /// Quando l'utente ha iniziato a disegnare questo tratto
  final int relativeStartMs;

  /// End timestamp relative to the recording (milliseconds)
  /// Quando l'utente ha completato questo tratto
  final int relativeEndMs;

  /// 📄 Indice della pagina PDF su cui was disegnato il tratto
  final int pageIndex;

  const SyncedStroke({
    required this.stroke,
    required this.relativeStartMs,
    required this.relativeEndMs,
    this.pageIndex = 0,
  });

  /// Durata of the stroke in millisecondi
  int get durationMs => relativeEndMs - relativeStartMs;

  /// Calculates quanti punti of the stroke sono visibili a un dato tempo di playback
  /// [playbackTimeMs] - tempo corrente di riproduzione in ms
  /// Returns: number of punti da mostrare (0 if the tratto is not ancora iniziato)
  int visiblePointsAtTime(int playbackTimeMs) {
    // If il playback non ha ancora raggiunto l'inizio of the stroke
    if (playbackTimeMs < relativeStartMs) return 0;

    // If il playback ha superato la fine of the stroke, mostra tutto
    if (playbackTimeMs >= relativeEndMs) return stroke.points.length;

    // Calculate la percentuale di progresso nel tratto
    final elapsed = playbackTimeMs - relativeStartMs;
    final progress = elapsed / durationMs;

    // Calculate quanti punti mostrare
    return (stroke.points.length * progress).ceil().clamp(
      0,
      stroke.points.length,
    );
  }

  /// Creates una versione parziale of the stroke con only the punti visibili
  /// [playbackTimeMs] - tempo corrente di riproduzione in ms
  ProStroke? getPartialStroke(int playbackTimeMs) {
    final visibleCount = visiblePointsAtTime(playbackTimeMs);
    if (visibleCount == 0) return null;
    if (visibleCount >= stroke.points.length) return stroke;

    return stroke.copyWith(points: stroke.points.sublist(0, visibleCount));
  }

  /// Checks if the stroke is completely visible
  bool isFullyVisible(int playbackTimeMs) => playbackTimeMs >= relativeEndMs;

  /// Checks if the stroke has started
  bool isStarted(int playbackTimeMs) => playbackTimeMs >= relativeStartMs;

  Map<String, dynamic> toJson() => {
    'stroke': stroke.toJson(),
    'relativeStartMs': relativeStartMs,
    'relativeEndMs': relativeEndMs,
    'pageIndex': pageIndex,
  };

  factory SyncedStroke.fromJson(Map<String, dynamic> json) => SyncedStroke(
    stroke: ProStroke.fromJson(json['stroke'] as Map<String, dynamic>),
    relativeStartMs: json['relativeStartMs'] as int,
    relativeEndMs: json['relativeEndMs'] as int,
    pageIndex: json['pageIndex'] as int? ?? 0,
  );
}

/// Registrazione sincronizzata che lega audio e tratti con timing preciso
/// Permette di riprodurre l'audio insieme ai tratti che si "disegnano" in real-time
class SynchronizedRecording {
  /// ID univoco of the recording
  final String id;

  /// Path del file audio
  final String audioPath;

  /// Durata totale of the recording
  final Duration totalDuration;

  /// Timestamp di inizio of the recording
  final DateTime startTime;

  /// Lista di strokes sincronizzati con timestamps relativi
  final List<SyncedStroke> syncedStrokes;

  /// ID of the canvas di origine
  final String? canvasId;

  /// Source note title
  final String? noteTitle;

  /// 🏷️ Recording type ('pdf', 'note', 'mixed')
  final String? recordingType;

  /// 📂 Path locale del file JSON (opzionale, per riferimento)
  final String? strokesPath;

  /// ☁️ URL Cloud Storage for the file audio (sync remoto)
  final String? audioStorageUrl;

  /// ☁️ URL Cloud Storage for the file JSON strokes (sync remoto)
  final String? strokesStorageUrl;

  const SynchronizedRecording({
    required this.id,
    required this.audioPath,
    required this.totalDuration,
    required this.startTime,
    required this.syncedStrokes,
    this.canvasId,
    this.noteTitle,
    this.recordingType,
    this.strokesPath,
    this.audioStorageUrl,
    this.strokesStorageUrl,
  });

  /// Creates una registrazione vuota
  factory SynchronizedRecording.empty({
    required String id,
    required String audioPath,
    required DateTime startTime,
    String? canvasId,
    String? noteTitle,
    String? recordingType,
  }) {
    return SynchronizedRecording(
      id: id,
      audioPath: audioPath,
      totalDuration: Duration.zero,
      startTime: startTime,
      syncedStrokes: [],
      canvasId: canvasId,
      noteTitle: noteTitle,
      recordingType: recordingType,
      strokesPath: null,
    );
  }

  /// Creates una copia con modifiche
  SynchronizedRecording copyWith({
    String? id,
    String? audioPath,
    Duration? totalDuration,
    DateTime? startTime,
    List<SyncedStroke>? syncedStrokes,
    String? canvasId,
    String? noteTitle,
    String? recordingType,
    String? strokesPath,
    String? audioStorageUrl,
    String? strokesStorageUrl,
  }) {
    return SynchronizedRecording(
      id: id ?? this.id,
      audioPath: audioPath ?? this.audioPath,
      totalDuration: totalDuration ?? this.totalDuration,
      startTime: startTime ?? this.startTime,
      syncedStrokes: syncedStrokes ?? this.syncedStrokes,
      canvasId: canvasId ?? this.canvasId,
      noteTitle: noteTitle ?? this.noteTitle,
      recordingType: recordingType ?? this.recordingType,
      strokesPath: strokesPath ?? this.strokesPath,
      audioStorageUrl: audioStorageUrl ?? this.audioStorageUrl,
      strokesStorageUrl: strokesStorageUrl ?? this.strokesStorageUrl,
    );
  }

  /// Numero totale di tratti nella registrazione
  int get strokeCount => syncedStrokes.length;

  /// Checks if the recording has strokes
  bool get hasStrokes => syncedStrokes.isNotEmpty;

  /// Gets tutti i tratti parziali visibili a un dato tempo
  /// [playbackTimeMs] - tempo corrente di riproduzione in ms
  /// Returns: list of strokes (parziali o completi) da renderizzare
  List<ProStroke> getVisibleStrokesAtTime(int playbackTimeMs) {
    final result = <ProStroke>[];

    for (final synced in syncedStrokes) {
      final partial = synced.getPartialStroke(playbackTimeMs);
      if (partial != null) {
        result.add(partial);
      }
    }

    return result;
  }

  /// Gets tutti gli strokes "ghost" (not yet started) with reduced opacity
  /// [playbackTimeMs] - tempo corrente di riproduzione in ms
  /// [ghostOpacity] - opacity per i ghost strokes (default 0.1)
  List<ProStroke> getGhostStrokesAtTime(
    int playbackTimeMs, {
    double ghostOpacity = 0.1,
  }) {
    final result = <ProStroke>[];

    for (final synced in syncedStrokes) {
      if (!synced.isStarted(playbackTimeMs)) {
        // Create ghost version with semi-transparent color
        result.add(
          synced.stroke.copyWith(
            color: synced.stroke.color.withValues(alpha: ghostOpacity),
          ),
        );
      }
    }

    return result;
  }

  /// Serializezione JSON
  Map<String, dynamic> toJson() => {
    'id': id,
    'audioPath': audioPath,
    'totalDurationMs': totalDuration.inMilliseconds,
    'startTime': startTime.toIso8601String(),
    'syncedStrokes': syncedStrokes.map((s) => s.toJson()).toList(),
    if (canvasId != null) 'canvasId': canvasId,
    if (noteTitle != null) 'noteTitle': noteTitle,
    if (recordingType != null) 'recordingType': recordingType,
    if (audioStorageUrl != null) 'audioStorageUrl': audioStorageUrl,
    if (strokesStorageUrl != null) 'strokesStorageUrl': strokesStorageUrl,
  };

  /// Serializezione JSON come stringa compressa
  String toJsonString() => jsonEncode(toJson());

  /// Deserializzazione JSON
  factory SynchronizedRecording.fromJson(Map<String, dynamic> json) {
    return SynchronizedRecording(
      id: json['id'] as String,
      audioPath: json['audioPath'] as String,
      totalDuration: Duration(milliseconds: json['totalDurationMs'] as int),
      startTime: DateTime.parse(json['startTime'] as String),
      syncedStrokes:
          (json['syncedStrokes'] as List<dynamic>)
              .map((s) => SyncedStroke.fromJson(s as Map<String, dynamic>))
              .toList(),
      canvasId: json['canvasId'] as String?,
      noteTitle: json['noteTitle'] as String?,
      recordingType: json['recordingType'] as String?,
      audioStorageUrl: json['audioStorageUrl'] as String?,
      strokesStorageUrl: json['strokesStorageUrl'] as String?,
    );
  }

  /// Deserializzazione da stringa JSON
  factory SynchronizedRecording.fromJsonString(String jsonString) {
    return SynchronizedRecording.fromJson(
      jsonDecode(jsonString) as Map<String, dynamic>,
    );
  }

  @override
  String toString() =>
      'SynchronizedRecording(id: $id, strokes: ${syncedStrokes.length}, duration: $totalDuration)';
}

/// Builder per costruire una SynchronizedRecording durante la registrazione
class SynchronizedRecordingBuilder {
  final String id;
  final String audioPath;
  final DateTime startTime;
  final String? canvasId;
  final String? noteTitle;

  // Mutable recording type inferred during recording
  String? _recordingType;

  final List<SyncedStroke> _strokes = [];
  int _recordingStartEpoch = 0;

  SynchronizedRecordingBuilder({
    required this.id,
    required this.audioPath,
    required this.startTime,
    this.canvasId,
    this.noteTitle,
  }) {
    _recordingStartEpoch = startTime.millisecondsSinceEpoch;
  }

  /// Adds a stroke to the recording
  /// [stroke] - lo stroke completato
  /// [strokeStartTime] - timestamp di inizio of the stroke (DateTime.now() quando l'utente ha iniziato)
  /// [strokeEndTime] - timestamp di fine of the stroke (DateTime.now() quando l'utente ha finito)
  /// [pageIndex] - indice della pagina PDF su cui was disegnato
  void addStroke(
    ProStroke stroke,
    DateTime strokeStartTime,
    DateTime strokeEndTime, {
    int pageIndex = 0,
  }) {
    final relativeStart =
        strokeStartTime.millisecondsSinceEpoch - _recordingStartEpoch;
    final relativeEnd =
        strokeEndTime.millisecondsSinceEpoch - _recordingStartEpoch;


    _strokes.add(
      SyncedStroke(
        stroke: stroke,
        relativeStartMs: relativeStart.clamp(0, double.maxFinite.toInt()),
        relativeEndMs: relativeEnd.clamp(0, double.maxFinite.toInt()),
        pageIndex: pageIndex,
      ),
    );
  }

  /// Adds a stroke using timestamps of points
  /// Calculates automaticamente start/end dai timestamps of points of the stroke
  void addStrokeWithPointTimestamps(ProStroke stroke) {
    if (stroke.points.isEmpty) return;

    // Use il timestamp del primo e last point
    final firstPointTimestamp = stroke.points.first.timestamp;
    final lastPointTimestamp = stroke.points.last.timestamp;

    // If aggiungiamo stroke con punti, assumiamo Note if not settato
    _recordingType ??= 'note';

    final relativeStart = firstPointTimestamp - _recordingStartEpoch;
    final relativeEnd = lastPointTimestamp - _recordingStartEpoch;

    _strokes.add(
      SyncedStroke(
        stroke: stroke,
        relativeStartMs: relativeStart.clamp(0, double.maxFinite.toInt()),
        relativeEndMs: relativeEnd.clamp(0, double.maxFinite.toInt()),
      ),
    );
  }

  /// Number of strokes aggiunti finora
  int get strokeCount => _strokes.length;

  /// Checks if there are strokes
  bool get hasStrokes => _strokes.isNotEmpty;

  /// Builds la registrazione finale
  /// [duration] - durata totale of the recording audio
  SynchronizedRecording build(Duration duration) {
    return SynchronizedRecording(
      id: id,
      audioPath: audioPath,
      totalDuration: duration,
      startTime: startTime,
      syncedStrokes: List.unmodifiable(_strokes),
      canvasId: canvasId,
      noteTitle: noteTitle,
      recordingType: _recordingType,
    );
  }

  /// Sets esplicitamente il type of registrazione per distinguere PDF da Note
  void setRecordingType(String type) {
    // 🧠 Be more tolerant: if type is already set but we DO NOT have strokes yet,
    // permetti di cambiare idea (utile se viene inizializzato come 'pdf' ma poi si disegna su 'note')
    if (_strokes.isEmpty) {
      _recordingType = type;
      return;
    }

    // If is already settato e diverso, diventa 'mixed'
    if (_recordingType != null && _recordingType != type) {
      _recordingType = 'mixed';
    } else {
      _recordingType = type;
    }
  }

  /// Resets il builder for aa nuova registrazione
  void reset() {
    _strokes.clear();
    _recordingStartEpoch = DateTime.now().millisecondsSinceEpoch;
  }
}
