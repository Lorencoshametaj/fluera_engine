import '../history/canvas_delta_tracker.dart';
import '../layers/layer_controller.dart';
import 'scene_graph_crdt.dart';

// =============================================================================
// 🔌 CRDT LAYER CONTROLLER OBSERVER
//
// Bridges every [LayerController] mutation into a [CRDTSceneGraph] and surfaces
// the produced [CRDTOperation]s for broadcast / persistence. This is the
// single point of capture for the canvas data path: strokes, shapes, texts,
// images, layers and adjustment layers all funnel through here, so brush
// commits, AI atlas mutations, undo/redo and direct API calls produce CRDT
// ops uniformly.
//
// Pair it with [CRDTSceneGraphObserver] to also cover the formal
// [SceneGraph] node tree — the two observers are complementary and never
// overlap (one watches `LayerController`, the other watches `SceneGraph`).
//
// Usage:
// ```dart
// final crdt = CRDTSceneGraph(localPeerId: deviceId);
// final observer = CRDTLayerControllerObserver(
//   crdt,
//   onLocalOperation: (op) => realtimeAdapter.broadcastCRDTOperation(canvasId, op),
// );
// final unsubscribe = layerController.addMutationObserver(observer.onMutation);
//
// // While applying a remote op, suspend so we don't re-emit:
// observer.runSilently(() => crdt.apply(remoteOp));
// ```
// =============================================================================

/// Observer that converts [CanvasDelta] mutations into [CRDTOperation]s.
class CRDTLayerControllerObserver {
  /// CRDT graph kept in lockstep with the local [LayerController].
  final CRDTSceneGraph crdt;

  /// Invoked for every operation generated locally. Wire this to the realtime
  /// adapter for broadcast and to the persistent op-log.
  final void Function(CRDTOperation op)? onLocalOperation;

  /// When non-zero the observer is suspended — used while applying a remote
  /// op to the local LayerController to avoid the apply→observe→re-broadcast
  /// loop. Re-entrant via [runSilently].
  int _suspendDepth = 0;

  CRDTLayerControllerObserver(this.crdt, {this.onLocalOperation});

  /// Whether the observer is currently suspended.
  bool get isSuspended => _suspendDepth > 0;

  /// Run [body] with the observer suspended.
  ///
  /// Re-entrant: nested calls increment the suspend depth. Use this around
  /// local mutations triggered by an incoming remote op so the resulting
  /// [CanvasDelta] events do not generate new outbound CRDT operations.
  T runSilently<T>(T Function() body) {
    _suspendDepth++;
    try {
      return body();
    } finally {
      _suspendDepth--;
    }
  }

  /// Pluggable into [LayerController.addMutationObserver].
  void onMutation(CanvasDelta delta) {
    if (isSuspended) return;
    final ops = _opsFor(delta);
    for (final op in ops) {
      onLocalOperation?.call(op);
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Mapping CanvasDeltaType → CRDT operations
  //
  // Every element has a globally-unique id and lives under its parent layer.
  // Layers themselves are children of a synthetic root so the tree is closed.
  // Updates are encoded as a single LWW property `data` carrying the full
  // serialized element — this trades bandwidth for simplicity and lets the
  // CRDT auto-resolve concurrent edits via HLC.
  // ───────────────────────────────────────────────────────────────────────────

  static const _kRootParent = '_root';

  /// Property name that carries the full serialized element for `*Updated`
  /// deltas. Kept as a constant so the receiving side stays in sync.
  static const String dataPropertyName = 'data';

  List<CRDTOperation> _opsFor(CanvasDelta delta) {
    switch (delta.type) {
      case CanvasDeltaType.strokeAdded:
        return [
          _addElement(delta, nodeType: 'stroke', parentId: delta.layerId),
        ];
      case CanvasDeltaType.shapeAdded:
        return [
          _addElement(delta, nodeType: 'shape', parentId: delta.layerId),
        ];
      case CanvasDeltaType.textAdded:
        return [
          _addElement(delta, nodeType: 'text', parentId: delta.layerId),
        ];
      case CanvasDeltaType.imageAdded:
        return [
          _addElement(delta, nodeType: 'image', parentId: delta.layerId),
        ];
      case CanvasDeltaType.adjustmentAdded:
        return [
          _addElement(delta, nodeType: 'adjustment', parentId: delta.layerId),
        ];

      case CanvasDeltaType.strokeRemoved:
      case CanvasDeltaType.shapeRemoved:
      case CanvasDeltaType.textRemoved:
      case CanvasDeltaType.imageRemoved:
      case CanvasDeltaType.adjustmentRemoved:
        final id = delta.elementId;
        if (id == null) return const [];
        return [crdt.removeNode(id)];

      case CanvasDeltaType.textUpdated:
      case CanvasDeltaType.imageUpdated:
        final id = delta.elementId;
        final data = delta.elementData;
        if (id == null || data == null) return const [];
        return [crdt.setProperty(id, dataPropertyName, data)];

      case CanvasDeltaType.adjustmentUpdated:
        final id = delta.elementId;
        final stack = delta.elementData?['adjustmentStack'];
        if (id == null || stack == null) return const [];
        return [crdt.setProperty(id, 'adjustmentStack', stack)];

      case CanvasDeltaType.layerAdded:
        return [
          crdt.addNode(
            nodeId: delta.layerId,
            nodeType: 'layer',
            parentId: _kRootParent,
            properties: delta.elementData ?? const {},
          ),
        ];
      case CanvasDeltaType.layerRemoved:
        return [crdt.removeNode(delta.layerId)];
      case CanvasDeltaType.layerModified:
        final data = delta.elementData;
        if (data == null) return const [];
        return [crdt.setProperty(delta.layerId, dataPropertyName, data)];

      case CanvasDeltaType.layerCleared:
        // Emit removeNode for every element that was on the layer before
        // the clear. The CRDT semantic of a "clear" is exactly the union of
        // its element removals — there is no special op type needed.
        // The previousData snapshot is in scene-graph form (LayerNode.toJson)
        // with a flat `children` array; legacy format (separate typed arrays)
        // is also accepted for forward compatibility.
        final prev = delta.previousData;
        if (prev == null) return const [];
        final ops = <CRDTOperation>[];
        void collectFrom(Object? list) {
          if (list is! List) return;
          for (final item in list) {
            if (item is! Map) continue;
            final id = item['id'];
            if (id is String) ops.add(crdt.removeNode(id));
          }
        }

        collectFrom(prev['children']);
        for (final key in const ['strokes', 'shapes', 'texts', 'images']) {
          collectFrom(prev[key]);
        }
        return ops;

      case CanvasDeltaType.composite:
        // Composite deltas wrap N child deltas as a single atomic undo
        // entry (Atlas cluster actions). For CRDT propagation we flatten:
        // each child contributes its own op stream so peers see the same
        // sequence of element-level mutations they would have seen if the
        // batch had landed unwrapped.
        final children = delta.childDeltas;
        if (children == null) return const [];
        return [
          for (final child in children) ..._opsFor(child),
        ];
    }
  }

  CRDTOperation _addElement(
    CanvasDelta delta, {
    required String nodeType,
    required String parentId,
  }) {
    final id = delta.elementId ?? delta.id;
    return crdt.addNode(
      nodeId: id,
      nodeType: nodeType,
      parentId: parentId,
      properties: delta.elementData ?? const {},
    );
  }
}
