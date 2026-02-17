import 'dart:async';

import '../models/pro_drawing_point.dart'; // Contains both ProDrawingPoint and ProStroke
import '../../rendering/optimization/stroke_data_manager.dart';
import '../../rendering/optimization/disk_stroke_manager.dart';
import '../../core/engine_scope.dart';

/// 🚀 STROKE PERSISTENCE SERVICE - Coordinatore intelligente RAM/Disk
///
/// RESPONSIBILITIES:
/// - Gestisce automaticamente il passaggio tra RAM e Disk storage
/// - TIER 1-3 (0-10k strokes): Solo RAM (StrokeDataManager)
/// - TIER 4 (10k+ strokes): RAM + Disk (DiskStrokeManager attivato)
/// - API unificata per salvare/caricare indipendentemente dal tier
///
/// ARCHITETTURA:
/// ```
/// StrokePersistenceService
///   ├── StrokeDataManager (RAM cache, sempre attivo)
///   │   └── Max 10k strokes in memoria
///   └── DiskStrokeManager (Disk storage, auto-attivato @ 10k)
///       └── Chunks da 1000 strokes, LRU cache
/// ```
class StrokePersistenceService {
  // ═══════════════════════════════════════════════════════════════════════════
  // 📐 CONFIGURAZIONE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Soglia per attivare disk storage (10k = sweet spot)
  /// Sotto: solo RAM is more veloce
  /// Sopra: disk evita OOM su canvas enormi
  static const int diskActivationThreshold = 10000;

  // ═══════════════════════════════════════════════════════════════════════════
  // 🗂️ STATE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Manager disco (null if not ancora attivato)
  DiskStrokeManager? _diskManager;

  /// Flag attivazione disk
  bool _diskStorageActive = false;

  /// Contatore totale strokes (per trigger auto-activation)
  int _totalStrokeCount = 0;

  /// Current canvas ID
  String? _currentCanvasId;

  // ═══════════════════════════════════════════════════════════════════════════
  // 🔧 SINGLETON
  // ═══════════════════════════════════════════════════════════════════════════
  /// Legacy singleton accessor — delegates to [EngineScope.current].
  static StrokePersistenceService get instance => EngineScope.current.strokePersistenceService;

  /// Creates a new instance (used by [EngineScope]).
  StrokePersistenceService.create();

  // ═══════════════════════════════════════════════════════════════════════════
  // 🚀 INIZIALIZZAZIONE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Initializes service for a canvas
  Future<void> initialize(String canvasId) async {
    _currentCanvasId = canvasId;
    _totalStrokeCount = 0;
    _diskStorageActive = false;

  }

  /// Attiva disk storage (chiamato automaticamente @ 10k strokes)
  Future<void> _activateDiskStorage() async {
    if (_diskStorageActive || _currentCanvasId == null) return;


    _diskManager = DiskStrokeManager.instance;
    await _diskManager!.initialize(_currentCanvasId!);

    _diskStorageActive = true;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 💾 SAVE OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Saves uno stroke (RAM sempre, Disk se attivo)
  Future<void> saveStroke(ProStroke stroke) async {
    // Incrementa contatore
    _totalStrokeCount++;

    // Save in RAM (sempre)
    StrokeDataManager.registerStrokePoints(stroke.id, stroke.points);

    // Auto-attiva disk storage se soglia raggiunta
    if (!_diskStorageActive && _totalStrokeCount >= diskActivationThreshold) {
      await _activateDiskStorage();
    }

    // Save to disk se attivo
    if (_diskStorageActive && _diskManager != null) {
      final bounds = StrokeBounds.fromRect(stroke.bounds);
      await _diskManager!.saveStroke(stroke.id, stroke.points, bounds);
    }
  }

  /// Removes a stroke (RAM + Disk if active)
  void removeStroke(String strokeId) {
    _totalStrokeCount--;
    StrokeDataManager.unregisterStroke(strokeId);

    if (_diskStorageActive && _diskManager != null) {
      _diskManager!.removeStroke(strokeId);
    }
  }

  /// 🚀 Save batch di strokes (ottimizzato per operazioni bulk)
  /// Uses chunked processing to avoid ANR on very large batches
  Future<void> saveStrokesBatch(List<ProStroke> strokes) async {
    if (strokes.isEmpty) return;


    // Incrementa contatore
    _totalStrokeCount += strokes.length;

    // Auto-attiva disk storage PRIMA se soglia raggiunta
    if (!_diskStorageActive && _totalStrokeCount >= diskActivationThreshold) {
      await _activateDiskStorage();
    }

    // Process in chunks to avoid blocking UI thread
    const chunkSize = 1000; // Process 1000 strokes at a time
    final chunks = <List<ProStroke>>[];
    for (int i = 0; i < strokes.length; i += chunkSize) {
      final end =
          (i + chunkSize < strokes.length) ? i + chunkSize : strokes.length;
      chunks.add(strokes.sublist(i, end));
    }

    // Process each chunk for RAM
    for (int chunkIndex = 0; chunkIndex < chunks.length; chunkIndex++) {
      final chunk = chunks[chunkIndex];

      // Save chunk in RAM
      for (final stroke in chunk) {
        StrokeDataManager.registerStrokePoints(stroke.id, stroke.points);
      }

      // Yield to UI thread between chunks
      if (chunkIndex < chunks.length - 1) {
        await Future.delayed(Duration.zero);
      }
    }

    // 🚀 Save to disk in BATCH se attivo (evita 10k await individuali!)
    if (_diskStorageActive && _diskManager != null) {
      // Prepara dati per batch save
      final strokeIds = <String>[];
      final pointsList = <List<ProDrawingPoint>>[];
      final boundsList = <StrokeBounds>[];

      for (final stroke in strokes) {
        strokeIds.add(stroke.id);
        pointsList.add(stroke.points);
        boundsList.add(StrokeBounds.fromRect(stroke.bounds));
      }

      // Singola chiamata batch invece di 10k chiamate individuali!
      await _diskManager!.saveStrokesBatch(strokeIds, pointsList, boundsList);
    }

  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 📤 LOAD OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Gets i punti for ao stroke (RAM first, Disk fallback)
  Future<List<ProDrawingPoint>> getStrokePoints(
    String strokeId, {
    List<ProDrawingPoint>? fallbackPoints,
  }) async {
    // 1. Prova RAM cache (veloce)
    final ramPoints = StrokeDataManager.getPoints(
      strokeId,
      fallbackPoints: fallbackPoints,
    );
    if (ramPoints.isNotEmpty) {
      return ramPoints;
    }

    // 2. Prova disk se attivo
    if (_diskStorageActive && _diskManager != null) {
      final diskPoints = await _diskManager!.getPoints(strokeId);
      if (diskPoints != null && diskPoints.isNotEmpty) {
        // Cachea in RAM per accesso futuro
        StrokeDataManager.registerStrokePoints(strokeId, diskPoints);
        return diskPoints;
      }
    }

    // 3. Fallback se fornito
    return fallbackPoints ?? const [];
  }

  /// Pre-carica strokes for a viewport (ottimizzazione)
  Future<void> preloadViewportStrokes(List<String> strokeIds) async {
    if (_diskStorageActive && _diskManager != null) {
      // Identifica strokes non in RAM
      final toLoad =
          strokeIds
              .where((id) => !StrokeDataManager.hasPointsCached(id))
              .toList();

      if (toLoad.isNotEmpty) {
        await _diskManager!.preloadStrokes(toLoad);
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 📊 STATISTICHE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Numero totale strokes gestiti
  int get totalStrokes => _totalStrokeCount;

  /// Disk storage attivo?
  bool get isDiskStorageActive => _diskStorageActive;

  /// Current tier
  String get currentTier {
    if (_totalStrokeCount < 1000) return 'TIER 1';
    if (_totalStrokeCount < 10000) return 'TIER 2';
    if (_totalStrokeCount < 100000) return 'TIER 3';
    return 'TIER 4 (DISK)';
  }

  /// Statistics for debugging
  Map<String, dynamic> get stats => {
    'totalStrokes': _totalStrokeCount,
    'diskActive': _diskStorageActive,
    'currentTier': currentTier,
    'ramStats': StrokeDataManager.stats,
    if (_diskStorageActive && _diskManager != null)
      'diskStats': _diskManager!.stats,
  };

  // ═══════════════════════════════════════════════════════════════════════════
  // 🧹 CLEANUP
  // ═══════════════════════════════════════════════════════════════════════════

  /// Flush tutti i dati to disk
  Future<void> flush() async {
    if (_diskStorageActive && _diskManager != null) {
      await _diskManager!.flush();
    }
  }

  /// Reset completo (nuovo canvas)
  Future<void> reset() async {
    await flush();
    StrokeDataManager.clearAll();
    _totalStrokeCount = 0;
    _diskStorageActive = false;
    _diskManager = null;
    _currentCanvasId = null;
  }
}
