import '../core/models/digital_text_element.dart';
import '../core/models/image_element.dart';
import '../core/models/shape_type.dart';
import '../drawing/models/pro_drawing_point.dart';
import '../layers/layer_controller.dart';
import 'crdt_layer_controller_observer.dart';
import 'scene_graph_crdt.dart';

// =============================================================================
// 🔌 CRDT → LAYER CONTROLLER APPLIER
//
// Symmetric counterpart of [CRDTLayerControllerObserver]. Where the observer
// captures local LayerController mutations and turns them into CRDT ops,
// the applier consumes incoming CRDT ops and replays them onto a local
// LayerController inside the observer's `runSilently` window so the loop
// stays cycle-free.
//
// Wiring example:
// ```dart
// final crdt = CRDTSceneGraph(localPeerId: deviceId);
// final observer = CRDTLayerControllerObserver(crdt, onLocalOperation: send);
// layerController.addMutationObserver(observer.onMutation);
//
// final applier = CRDTToLayerControllerApplier(
//   crdt: crdt,
//   layerController: layerController,
//   observer: observer,
// );
// realtimeEngine.incomingCRDTOperations.listen(applier.applyRemote);
// ```
// =============================================================================

/// Routes [CRDTOperation]s into the local [LayerController].
class CRDTToLayerControllerApplier {
  /// CRDT graph mutated by the local observer and updated by remote ops.
  final CRDTSceneGraph crdt;

  /// Target controller whose state must mirror [crdt].
  final LayerController layerController;

  /// Local observer — used to suspend emission while replaying remote ops.
  final CRDTLayerControllerObserver observer;

  CRDTToLayerControllerApplier({
    required this.crdt,
    required this.layerController,
    required this.observer,
  }) {
    crdt.addChangeListener(_onChanges);
  }

  /// Apply a remote operation to the local CRDT and replay the resulting
  /// [CRDTChange]s onto the [LayerController]. Idempotent — the CRDT layer
  /// dedups by opId.
  ///
  /// While the apply runs we also flip [LayerController.suppressUndoTracking]
  /// so the resulting `_emitTT` calls don't push the remote mutation onto
  /// the local user's undo stack — `Ctrl+Z` must only revert the local
  /// user's own edits, never a teammate's.
  void applyRemote(CRDTOperation op) {
    final wasSuppressed = layerController.suppressUndoTracking;
    layerController.suppressUndoTracking = true;
    try {
      observer.runSilently(() => crdt.apply(op));
    } finally {
      layerController.suppressUndoTracking = wasSuppressed;
    }
  }

  /// Detach from the CRDT change stream. Safe to call repeatedly.
  void dispose() {
    crdt.removeChangeListener(_onChanges);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Internal: translate CRDTChange → LayerController calls
  // ───────────────────────────────────────────────────────────────────────────

  void _onChanges(List<CRDTChange> changes) {
    // Only react while we are inside an applyRemote window. This is the
    // single switch that prevents apply→observe→re-broadcast loops.
    if (!observer.isSuspended) return;
    for (final change in changes) {
      _applyChange(change);
    }
  }

  void _applyChange(CRDTChange change) {
    switch (change.type) {
      case CRDTChangeType.added:
        _applyAdded(change);
      case CRDTChangeType.removed:
        _applyRemoved(change);
      case CRDTChangeType.propertyChanged:
        _applyPropertyChanged(change);
      case CRDTChangeType.moved:
        // Cross-layer reparenting / sortIndex changes are not yet wired —
        // local layer reordering goes through dedicated LayerController APIs
        // (moveLayerUp/Down) rather than per-element move ops.
        break;
    }
  }

  void _applyAdded(CRDTChange change) {
    final state = crdt.nodeState(change.nodeId);
    if (state == null) return;
    final type = change.nodeType ?? state.nodeType.value;
    final props = state.toPropertyMap();
    final id = change.nodeId;

    // Idempotency guard: the same op may legitimately reach `_applyAdded`
    // twice — once during the on-disk CRDT log replay at canvas open
    // (where the LayerController is already pre-populated from SQLite),
    // once during live transport delivery if the wire redelivers. Adding
    // the element a second time trips a `Duplicate child ID` assertion in
    // `GroupNode`. Check the controller's flat lists before mutating.
    switch (type) {
      case 'stroke':
        if (_strokeExists(id)) return;
        try {
          layerController.addStroke(ProStroke.fromJson(props));
        } catch (_) {}
      case 'shape':
        if (_shapeExists(id)) return;
        try {
          layerController.addShape(GeometricShape.fromJson(props));
        } catch (_) {}
      case 'text':
        if (_textExists(id)) return;
        try {
          layerController.addText(DigitalTextElement.fromJson(props));
        } catch (_) {}
      case 'image':
        if (_imageExists(id)) return;
        try {
          layerController.addImage(ImageElement.fromJson(props));
        } catch (_) {}
      case 'layer':
        // [LayerController.addLayer] is already idempotent on its `id`
        // parameter (returns early if a layer with that id exists).
        final name = props['name'] as String?;
        layerController.addLayer(name: name, id: id);
      // 'adjustment' is not exposed via a public LayerController API yet;
      // it stays in the CRDT graph and will be picked up once the host
      // app wires the AdjustmentLayer apply path.
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Idempotency helpers
  //
  // The LayerController exposes flat lists per layer; we scan only the active
  // layer first (the common case for newly-arrived strokes) and fall through
  // to all layers when the new element targets a different layer (rare —
  // usually the case during a multi-layer remote-apply replay).
  // ───────────────────────────────────────────────────────────────────────────

  bool _strokeExists(String id) {
    for (final layer in layerController.layers) {
      for (final s in layer.strokes) {
        if (s.id == id) return true;
      }
    }
    return false;
  }

  bool _shapeExists(String id) {
    for (final layer in layerController.layers) {
      for (final s in layer.shapes) {
        if (s.id == id) return true;
      }
    }
    return false;
  }

  bool _textExists(String id) {
    for (final layer in layerController.layers) {
      for (final t in layer.texts) {
        if (t.id == id) return true;
      }
    }
    return false;
  }

  bool _imageExists(String id) {
    for (final layer in layerController.layers) {
      for (final img in layer.images) {
        if (img.id == id) return true;
      }
    }
    return false;
  }

  void _applyRemoved(CRDTChange change) {
    final state = crdt.nodeState(change.nodeId);
    final type = state?.nodeType.value;
    final id = change.nodeId;
    switch (type) {
      case 'stroke':
        layerController.removeStroke(id);
      case 'shape':
        layerController.removeShape(id);
      case 'text':
        layerController.removeText(id);
      case 'image':
        layerController.removeImage(id);
      case 'layer':
        layerController.removeLayer(id);
      default:
        // Unknown type (e.g. CRDT state was GC'd or never carried a type) —
        // try the cheap remove* fall-throughs. Each is a no-op when the id
        // isn't present.
        layerController.removeStroke(id);
        layerController.removeShape(id);
        layerController.removeText(id);
        layerController.removeImage(id);
    }
  }

  void _applyPropertyChanged(CRDTChange change) {
    // The observer encodes element updates as setProperty('data', fullJson).
    if (change.propertyName !=
        CRDTLayerControllerObserver.dataPropertyName) {
      return;
    }
    final value = change.propertyValue;
    if (value is! Map) return;
    final props = Map<String, dynamic>.from(value);

    final state = crdt.nodeState(change.nodeId);
    final type = state?.nodeType.value;
    switch (type) {
      case 'text':
        try {
          layerController.updateText(DigitalTextElement.fromJson(props));
        } catch (_) {}
      case 'image':
        try {
          layerController.updateImage(ImageElement.fromJson(props));
        } catch (_) {}
      // 'stroke', 'shape', 'layer', 'adjustment': no in-place update API on
      // LayerController — host app re-creates the element via add* if needed.
    }
  }
}
