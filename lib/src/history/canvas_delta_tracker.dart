import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../core/engine_logger.dart';
import '../core/engine_scope.dart';
import '../core/models/canvas_layer.dart';
import '../drawing/models/pro_drawing_point.dart';
import '../core/models/shape_type.dart';
import '../core/models/digital_text_element.dart';
import '../core/models/image_element.dart';
import './undo_redo_manager.dart'; // 🔄 Phase 2

/// 📊 Type of delta (modifica incrementale)
enum CanvasDeltaType {
  strokeAdded,
  strokeRemoved,
  shapeAdded,
  shapeRemoved,
  textAdded,
  textRemoved,
  textUpdated,
  imageAdded,
  imageRemoved,
  imageUpdated,
  layerAdded,
  layerRemoved,
  layerModified,
  layerCleared,
}

/// 🔄 Single delta — represents an incremental modification to the canvas.
///
/// Contains only the data needed to apply or reverse the modification,
/// avoiding full canvas serialization on every stroke.
class CanvasDelta {
  final String id;
  final CanvasDeltaType type;
  final String layerId;
  final int? pageIndex;
  final DateTime timestamp;

  /// Type-specific data (already serialized for efficiency)
  /// - strokeAdded/Removed: JSON of the stroke
  /// - shapeAdded/Removed: JSON of the shape
  /// - layerModified: Map with only the modified fields
  final Map<String, dynamic>? elementData;

  /// Element ID (stroke/shape) for removal operations
  final String? elementId;

  /// Previous state data for reversible operations (undo support).
  /// - layerModified: Map with old property values before the change
  /// - textUpdated: JSON of the text element before the update
  /// - imageUpdated: JSON of the image element before the update
  /// - layerCleared: JSON of the full layer before clearing
  final Map<String, dynamic>? previousData;

  CanvasDelta({
    required this.id,
    required this.type,
    required this.layerId,
    this.pageIndex,
    required this.timestamp,
    this.elementData,
    this.elementId,
    this.previousData,
  });

  /// Serialize the delta for storage (compact JSONL format)
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.index,
    'layerId': layerId,
    if (pageIndex != null) 'page': pageIndex,
    'ts': timestamp.millisecondsSinceEpoch,
    if (elementData != null) 'data': elementData,
    if (elementId != null) 'elemId': elementId,
    if (previousData != null) 'prev': previousData,
  };

  /// Deserialize from JSON (safe for RTDB data with _Map<Object?, Object?>)
  factory CanvasDelta.fromJson(Map<String, dynamic> json) {
    // RTDB returns nested maps as _Map<Object?, Object?>, need deep conversion
    final rawData = json['data'];
    Map<String, dynamic>? elementData;
    if (rawData is Map) {
      elementData = _deepConvertMap(rawData);
    }

    final rawPrev = json['prev'];
    Map<String, dynamic>? previousData;
    if (rawPrev is Map) {
      previousData = _deepConvertMap(rawPrev);
    }

    return CanvasDelta(
      id: json['id'] as String,
      type: CanvasDeltaType.values[json['type'] as int],
      layerId: json['layerId'] as String,
      pageIndex: json['page'] as int?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['ts'] as int),
      elementData: elementData,
      elementId: json['elemId'] as String?,
      previousData: previousData,
    );
  }

  /// Deep-convert RTDB maps recursively
  static Map<String, dynamic> _deepConvertMap(Map map) {
    return map.map<String, dynamic>((key, value) {
      if (value is Map) {
        return MapEntry(key.toString(), _deepConvertMap(value));
      } else if (value is List) {
        return MapEntry(key.toString(), _deepConvertList(value));
      }
      return MapEntry(key.toString(), value);
    });
  }

  static List<dynamic> _deepConvertList(List list) {
    return list.map((item) {
      if (item is Map) return _deepConvertMap(item);
      if (item is List) return _deepConvertList(item);
      return item;
    }).toList();
  }

  /// Serialize as a single JSON line (for JSONL format)
  String toJsonLine() => jsonEncode(toJson());

  @override
  String toString() =>
      'CanvasDelta(${type.name}, layer: $layerId, elem: $elementId)';
}

/// 🎯 CanvasDeltaTracker - WAL (Write-Ahead Log) Implementation
///
/// **WAL STRATEGY v2.0** (40x fewer disk writes!)
/// Instead of full checkpoints every 50 modifications, uses:
/// - **Delta appends**: 99% of saves (1-10 KB)
/// - **Full checkpoint**: only when necessary (12 MB)
///
/// 📊 Checkpoint triggers:
/// 1. **500 accumulated deltas** (was 50) → compaction needed
/// 2. **30 minutes** since last checkpoint (was 30 sec) → safety backup
/// 3. **App exit** → final flush
///
/// 💾 Disk savings:
/// - BEFORE: 50 × 12MB = 600MB/500 strokes
/// - AFTER: 500 × 5KB + 1 × 12MB = ~15MB/500 strokes (40x less!)
class CanvasDeltaTracker {
  /// Legacy singleton accessor — delegates to [EngineScope.current].
  static CanvasDeltaTracker get instance => EngineScope.current.deltaTracker;

  /// Creates a new instance (used by [EngineScope]).
  CanvasDeltaTracker.create();

  /// Queue of pending deltas (not yet saved)
  final List<CanvasDelta> _pendingDeltas = [];

  /// Timestamp of last full checkpoint
  DateTime? _lastCheckpointTime;

  /// 🚀 WAL v2.0: Checkpoint threshold increased 10x (from 50 → 500)
  /// Trigger compaction only when WAL grows too large
  static const int checkpointThreshold = 500;

  /// 🚀 WAL v2.0: Time-based checkpoint every 30 minutes (was 30 sec)
  /// Ensures periodic backup without overhead
  static const Duration checkpointTimeThreshold = Duration(minutes: 30);

  /// Unique ID for current canvas (to avoid multi-canvas conflicts)
  String? _currentCanvasId;

  // ============================================================================
  // GETTERS
  // ============================================================================

  /// Number of pending deltas
  int get deltaCount => _pendingDeltas.length;

  /// Whether there are pending deltas
  bool get hasPendingDeltas => _pendingDeltas.isNotEmpty;

  /// 🚀 WAL v2.0: Checkpoint only when truly necessary
  bool get needsFullCheckpoint {
    // 1. WAL too large → compaction required
    if (_pendingDeltas.length >= checkpointThreshold) {
      return true;
    }

    // 2. Periodic safety backup (every 30 min)
    if (_lastCheckpointTime != null && _pendingDeltas.isNotEmpty) {
      final elapsed = DateTime.now().difference(_lastCheckpointTime!);
      if (elapsed >= checkpointTimeThreshold) {
        return true;
      }
    }

    return false;
  }

  /// ID of the current canvas
  String? get currentCanvasId => _currentCanvasId;

  // ============================================================================
  // SETUP
  // ============================================================================

  /// Initialize the tracker for a new canvas
  void initForCanvas(String canvasId) {
    if (_currentCanvasId != canvasId) {
      // Different canvas: clear previous deltas
      _pendingDeltas.clear();
      _currentCanvasId = canvasId;
      _lastCheckpointTime = DateTime.now();
    }
  }

  /// Full tracker reset (e.g., logout, user switch)
  void reset() {
    _pendingDeltas.clear();
    _currentCanvasId = null;
    _lastCheckpointTime = null;
  }

  /// Reset singleton state for testing. Clears all pending deltas.
  @visibleForTesting
  void resetForTesting() {
    _pendingDeltas.clear();
    _currentCanvasId = null;
    _lastCheckpointTime = null;
  }

  // ============================================================================
  // RECORD DELTAS
  // ============================================================================

  /// 📝 Record stroke addition
  void recordStrokeAdded(String layerId, ProStroke stroke, {int? pageIndex}) {
    _addDelta(
      CanvasDelta(
        id: _generateDeltaId(),
        type: CanvasDeltaType.strokeAdded,
        layerId: layerId,
        pageIndex: pageIndex,
        timestamp: DateTime.now(),
        elementData: stroke.toJson(),
        elementId: stroke.id,
      ),
    );

    // 🔄 Phase 2: Auto-push to undo stack
    try {
      final delta = _pendingDeltas.last;
      UndoRedoManager.instance.pushDelta(delta);
    } catch (e) {
      EngineLogger.debug(
        'UndoRedoManager not ready, skipping auto-push',
        tag: 'WAL',
      );
    }
  }

  /// 📝 Record stroke removal
  void recordStrokeRemoved(String layerId, String strokeId, {int? pageIndex}) {
    _addDelta(
      CanvasDelta(
        id: _generateDeltaId(),
        type: CanvasDeltaType.strokeRemoved,
        layerId: layerId,
        pageIndex: pageIndex,
        timestamp: DateTime.now(),
        elementId: strokeId,
      ),
    );
  }

  /// 📝 Record shape addition
  void recordShapeAdded(
    String layerId,
    GeometricShape shape, {
    int? pageIndex,
  }) {
    _addDelta(
      CanvasDelta(
        id: _generateDeltaId(),
        type: CanvasDeltaType.shapeAdded,
        layerId: layerId,
        pageIndex: pageIndex,
        timestamp: DateTime.now(),
        elementData: shape.toJson(),
        elementId: shape.id,
      ),
    );
  }

  /// 📝 Record shape removal
  void recordShapeRemoved(String layerId, String shapeId, {int? pageIndex}) {
    _addDelta(
      CanvasDelta(
        id: _generateDeltaId(),
        type: CanvasDeltaType.shapeRemoved,
        layerId: layerId,
        pageIndex: pageIndex,
        timestamp: DateTime.now(),
        elementId: shapeId,
      ),
    );
  }

  /// 📝 Record layer property modification (visibility, lock, opacity)
  ///
  /// [changes] contains the new values, [previousValues] contains the old
  /// values for the same keys (needed for undo).
  void recordLayerModified(
    String layerId,
    Map<String, dynamic> changes, {
    Map<String, dynamic>? previousValues,
    int? pageIndex,
  }) {
    _addDelta(
      CanvasDelta(
        id: _generateDeltaId(),
        type: CanvasDeltaType.layerModified,
        layerId: layerId,
        pageIndex: pageIndex,
        timestamp: DateTime.now(),
        elementData: changes,
        previousData: previousValues,
      ),
    );
  }

  /// 📝 Record layer addition
  void recordLayerAdded(CanvasLayer layer) {
    _addDelta(
      CanvasDelta(
        id: _generateDeltaId(),
        type: CanvasDeltaType.layerAdded,
        layerId: layer.id,
        timestamp: DateTime.now(),
        elementData: layer.toJson(),
      ),
    );
  }

  /// 📝 Record layer removal
  void recordLayerRemoved(String layerId) {
    _addDelta(
      CanvasDelta(
        id: _generateDeltaId(),
        type: CanvasDeltaType.layerRemoved,
        layerId: layerId,
        timestamp: DateTime.now(),
      ),
    );
  }

  /// 📝 Record text addition
  void recordTextAdded(
    String layerId,
    DigitalTextElement text, {
    int? pageIndex,
  }) {
    _addDelta(
      CanvasDelta(
        id: _generateDeltaId(),
        type: CanvasDeltaType.textAdded,
        layerId: layerId,
        pageIndex: pageIndex,
        timestamp: DateTime.now(),
        elementData: text.toJson(),
        elementId: text.id,
      ),
    );
  }

  /// 📝 Record text removal
  void recordTextRemoved(String layerId, String textId, {int? pageIndex}) {
    _addDelta(
      CanvasDelta(
        id: _generateDeltaId(),
        type: CanvasDeltaType.textRemoved,
        layerId: layerId,
        pageIndex: pageIndex,
        timestamp: DateTime.now(),
        elementId: textId,
      ),
    );
  }

  /// 📝 Record text element update
  ///
  /// [text] is the new state. [previousText] is the old state (needed for undo).
  void recordTextUpdate(
    String layerId,
    DigitalTextElement text, {
    DigitalTextElement? previousText,
    int? pageIndex,
  }) {
    _addDelta(
      CanvasDelta(
        id: _generateDeltaId(),
        type: CanvasDeltaType.textUpdated,
        layerId: layerId,
        pageIndex: pageIndex,
        timestamp: DateTime.now(),
        elementData: text.toJson(),
        elementId: text.id,
        previousData: previousText?.toJson(),
      ),
    );
  }

  /// 📝 Record image addition
  void recordImageAdded(String layerId, ImageElement image, {int? pageIndex}) {
    _addDelta(
      CanvasDelta(
        id: _generateDeltaId(),
        type: CanvasDeltaType.imageAdded,
        layerId: layerId,
        pageIndex: pageIndex,
        timestamp: DateTime.now(),
        elementData: image.toJson(),
        elementId: image.id,
      ),
    );
  }

  /// 📝 Record image removal
  void recordImageRemoved(String layerId, String imageId, {int? pageIndex}) {
    _addDelta(
      CanvasDelta(
        id: _generateDeltaId(),
        type: CanvasDeltaType.imageRemoved,
        layerId: layerId,
        pageIndex: pageIndex,
        timestamp: DateTime.now(),
        elementId: imageId,
      ),
    );
  }

  /// 📝 Record image element update
  ///
  /// [image] is the new state. [previousImage] is the old state (needed for undo).
  void recordImageUpdate(
    String layerId,
    ImageElement image, {
    ImageElement? previousImage,
    int? pageIndex,
  }) {
    _addDelta(
      CanvasDelta(
        id: _generateDeltaId(),
        type: CanvasDeltaType.imageUpdated,
        layerId: layerId,
        pageIndex: pageIndex,
        timestamp: DateTime.now(),
        elementData: image.toJson(),
        elementId: image.id,
        previousData: previousImage?.toJson(),
      ),
    );
  }

  /// 📝 Record layer clear (remove all strokes/shapes/texts/images)
  ///
  /// [layerSnapshot] should be the full layer JSON before clearing (needed for undo).
  void recordLayerCleared(
    String layerId, {
    Map<String, dynamic>? layerSnapshot,
    int? pageIndex,
  }) {
    _addDelta(
      CanvasDelta(
        id: _generateDeltaId(),
        type: CanvasDeltaType.layerCleared,
        layerId: layerId,
        pageIndex: pageIndex,
        timestamp: DateTime.now(),
        previousData: layerSnapshot,
      ),
    );
  }

  // ============================================================================
  // CONSUME DELTAS
  // ============================================================================

  /// 🔄 Consume and return all pending deltas
  ///
  /// ⚠️ DEPRECATED: Use peek() + clearPendingDeltas() for crash safety!
  /// Called by local_storage_service to save deltas.
  /// After this call, the queue is empty.
  @Deprecated('Use peekDeltas() + clearPendingDeltas() for crash safety')
  List<CanvasDelta> consumeDeltas() {
    final deltas = List<CanvasDelta>.from(_pendingDeltas);
    _pendingDeltas.clear();
    return deltas;
  }

  /// 🔄 Get deltas without consuming them (for preview/debug)
  List<CanvasDelta> peekDeltas() {
    return List<CanvasDelta>.unmodifiable(_pendingDeltas);
  }

  /// ✅ SAFETY v4.3: Remove only the first N deltas (the saved ones)
  /// Prevents race condition: removes ONLY deltas already written to disk
  void removeDeltas({required int count}) {
    if (count <= 0 || count > _pendingDeltas.length) {
      return;
    }

    // Remove only the first N (FIFO — the saved ones)
    _pendingDeltas.removeRange(0, count);
  }

  /// ✅ SAFETY: Clear deltas ONLY after write confirmation
  /// Peek & flush pattern to prevent data loss
  @Deprecated('Use removeDeltas(count) to avoid race condition')
  void clearPendingDeltas() {
    _pendingDeltas.clear();
  }

  /// ✅ Notify that a full checkpoint was completed
  void markCheckpointCompleted() {
    _pendingDeltas.clear();
    _lastCheckpointTime = DateTime.now();
  }

  // ============================================================================
  // HELPERS
  // ============================================================================

  /// Add a delta to the queue
  void _addDelta(CanvasDelta delta) {
    _pendingDeltas.add(delta);

    // 🚀 WAL v2.0: Log every 50 deltas (was 10) to reduce noise
    if (_pendingDeltas.length % 50 == 0) {}
  }

  /// Generate unique delta ID
  String _generateDeltaId() {
    return '${DateTime.now().microsecondsSinceEpoch}_${_pendingDeltas.length}';
  }

  // ============================================================================
  // SERIALIZATION HELPERS
  // ============================================================================

  /// Serialize all pending deltas in JSONL format (one line per delta)
  String serializeDeltasToJsonl() {
    if (_pendingDeltas.isEmpty) return '';
    return _pendingDeltas.map((d) => d.toJsonLine()).join('\n');
  }

  /// Deserialize deltas from JSONL format
  static List<CanvasDelta> deserializeDeltasFromJsonl(String jsonl) {
    if (jsonl.isEmpty) return [];

    final lines = jsonl.split('\n').where((l) => l.trim().isNotEmpty);
    return lines.map((line) {
      final json = jsonDecode(line) as Map<String, dynamic>;
      return CanvasDelta.fromJson(json);
    }).toList();
  }

  /// 🔄 Apply a list of deltas to a list of layers
  ///
  /// Used at loading time to rebuild current state
  /// starting from checkpoint + subsequent deltas.
  static List<CanvasLayer> applyDeltas(
    List<CanvasLayer> layers,
    List<CanvasDelta> deltas,
  ) {
    // Create mutable map of layers
    final layerMap = {for (final l in layers) l.id: l};

    // 🔧 Helper: auto-create missing layer so remote deltas aren't dropped
    CanvasLayer _ensureLayer(String layerId) {
      if (!layerMap.containsKey(layerId)) {
        layerMap[layerId] = CanvasLayer(id: layerId, name: 'Layer');
      }
      return layerMap[layerId]!;
    }

    for (final delta in deltas) {
      switch (delta.type) {
        case CanvasDeltaType.strokeAdded:
          if (delta.elementData != null) {
            final layer = _ensureLayer(delta.layerId);
            final stroke = ProStroke.fromJson(delta.elementData!);
            final updatedStrokes = List<ProStroke>.from(layer.strokes)
              ..add(stroke);
            layerMap[delta.layerId] = layer.copyWith(strokes: updatedStrokes);
          }
          break;

        case CanvasDeltaType.strokeRemoved:
          final layer = layerMap[delta.layerId];
          if (layer != null && delta.elementId != null) {
            final updatedStrokes =
                layer.strokes.where((s) => s.id != delta.elementId).toList();
            layerMap[delta.layerId] = layer.copyWith(strokes: updatedStrokes);
          }
          break;

        case CanvasDeltaType.shapeAdded:
          if (delta.elementData != null) {
            final layer = _ensureLayer(delta.layerId);
            final shape = GeometricShape.fromJson(delta.elementData!);
            final updatedShapes = List<GeometricShape>.from(layer.shapes)
              ..add(shape);
            layerMap[delta.layerId] = layer.copyWith(shapes: updatedShapes);
          }
          break;

        case CanvasDeltaType.shapeRemoved:
          final layer = layerMap[delta.layerId];
          if (layer != null && delta.elementId != null) {
            final updatedShapes =
                layer.shapes.where((s) => s.id != delta.elementId).toList();
            layerMap[delta.layerId] = layer.copyWith(shapes: updatedShapes);
          }
          break;

        case CanvasDeltaType.layerAdded:
          if (delta.elementData != null) {
            final newLayer = CanvasLayer.fromJson(delta.elementData!);
            layerMap[newLayer.id] = newLayer;
          }
          break;

        case CanvasDeltaType.layerRemoved:
          layerMap.remove(delta.layerId);
          break;

        case CanvasDeltaType.layerCleared:
          final layer = layerMap[delta.layerId];
          if (layer != null) {
            layerMap[delta.layerId] = layer.copyWith(
              strokes: [],
              shapes: [],
              texts: [],
              images: [],
            );
          }
          break;

        case CanvasDeltaType.layerModified:
          final layer = layerMap[delta.layerId];
          if (layer != null && delta.elementData != null) {
            final data = delta.elementData!;
            layerMap[delta.layerId] = layer.copyWith(
              name: data['name'] as String? ?? layer.name,
              isVisible: data['isVisible'] as bool? ?? layer.isVisible,
              isLocked: data['isLocked'] as bool? ?? layer.isLocked,
              opacity: (data['opacity'] as num?)?.toDouble() ?? layer.opacity,
            );
          }
          break;

        case CanvasDeltaType.textAdded:
          if (delta.elementData != null) {
            final layer = _ensureLayer(delta.layerId);
            final text = DigitalTextElement.fromJson(delta.elementData!);
            final updatedTexts = List<DigitalTextElement>.from(layer.texts)
              ..add(text);
            layerMap[delta.layerId] = layer.copyWith(texts: updatedTexts);
          }
          break;

        case CanvasDeltaType.textRemoved:
          final layer = layerMap[delta.layerId];
          if (layer != null && delta.elementId != null) {
            final updatedTexts =
                layer.texts.where((t) => t.id != delta.elementId).toList();
            layerMap[delta.layerId] = layer.copyWith(texts: updatedTexts);
          }
          break;

        case CanvasDeltaType.textUpdated:
          final layer = layerMap[delta.layerId];
          if (layer != null && delta.elementData != null) {
            final text = DigitalTextElement.fromJson(delta.elementData!);
            final updatedTexts =
                layer.texts.map((t) => t.id == text.id ? text : t).toList();
            layerMap[delta.layerId] = layer.copyWith(texts: updatedTexts);
          }
          break;

        case CanvasDeltaType.imageAdded:
          if (delta.elementData != null) {
            final layer = _ensureLayer(delta.layerId);
            final image = ImageElement.fromJson(delta.elementData!);
            final updatedImages = List<ImageElement>.from(layer.images)
              ..add(image);
            layerMap[delta.layerId] = layer.copyWith(images: updatedImages);
          }
          break;

        case CanvasDeltaType.imageRemoved:
          final layer = layerMap[delta.layerId];
          if (layer != null && delta.elementId != null) {
            final updatedImages =
                layer.images.where((i) => i.id != delta.elementId).toList();
            layerMap[delta.layerId] = layer.copyWith(images: updatedImages);
          }
          break;

        case CanvasDeltaType.imageUpdated:
          final layer = layerMap[delta.layerId];
          if (layer != null && delta.elementData != null) {
            final image = ImageElement.fromJson(delta.elementData!);
            final updatedImages =
                layer.images.map((i) => i.id == image.id ? image : i).toList();
            layerMap[delta.layerId] = layer.copyWith(images: updatedImages);
          }
          break;
      }
    }

    // Rebuild list preserving original order where possible
    final result = <CanvasLayer>[];
    for (final originalLayer in layers) {
      if (layerMap.containsKey(originalLayer.id)) {
        result.add(layerMap[originalLayer.id]!);
        layerMap.remove(originalLayer.id);
      }
    }
    // Add new layers (not present in original)
    result.addAll(layerMap.values);

    return result;
  }
}
