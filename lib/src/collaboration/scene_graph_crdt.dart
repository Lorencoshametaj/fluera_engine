import 'dart:math';
import 'package:flutter/foundation.dart';

// =============================================================================
// 🔄 SCENE GRAPH CRDT — Conflict-free Replicated Data Types for scene graphs
//
// Provides deterministic, conflict-free merging for ALL scene graph operations:
//   1. HybridLogicalClock — monotonic causal+physical timestamps
//   2. LWWRegister — Last-Writer-Wins register for node properties
//   3. LWWElementSet — Add/remove set with tombstones for node membership
//   4. CRDTOperation — serializable operation envelope
//   5. CRDTMergeEngine — merge remote state into local state
//
// Use this instead of timestamp-based LWW for lossless concurrent merging.
// Unlike OT (which transforms operations), CRDTs merge STATE and always
// converge regardless of message ordering, duplication, or network partitions.
// =============================================================================

// ─────────────────────────────────────────────────────────────────────────────
// 1. HYBRID LOGICAL CLOCK (HLC)
// ─────────────────────────────────────────────────────────────────────────────

/// Hybrid Logical Clock combining wall-clock time with a logical counter.
///
/// Guarantees:
/// - Monotonically increasing (never goes backward)
/// - Causally consistent (if A→B then hlc(A) < hlc(B))
/// - Close to physical time (within network latency)
///
/// Based on: "Logical Physical Clocks" (Kulkarni et al., 2014)
///
/// ```dart
/// final clock = HybridLogicalClock('peer_1');
/// final ts1 = clock.now(); // Generate timestamp for local event
/// clock.receive(remoteTimestamp); // Merge on receiving remote event
/// final ts2 = clock.now(); // ts2 > ts1 and ts2 > remoteTimestamp
/// ```
class HybridLogicalClock {
  /// The local peer identifier.
  final String peerId;

  /// Physical time component (ms since epoch).
  int _physicalMs;

  /// Logical counter for events at the same physical time.
  int _counter;

  /// Injectable wall clock for testing.
  final int Function()? _wallClock;

  HybridLogicalClock(this.peerId, {int Function()? wallClock})
    : _physicalMs = 0,
      _counter = 0,
      _wallClock = wallClock;

  /// Generate a new timestamp for a local event.
  ///
  /// The returned [HLCTimestamp] is guaranteed to be strictly greater
  /// than any previously generated or received timestamp.
  HLCTimestamp now() {
    final wallMs = _wallClock?.call() ?? DateTime.now().millisecondsSinceEpoch;

    if (wallMs > _physicalMs) {
      _physicalMs = wallMs;
      _counter = 0;
    } else {
      _counter++;
    }

    return HLCTimestamp(
      physicalMs: _physicalMs,
      counter: _counter,
      peerId: peerId,
    );
  }

  /// Update the clock upon receiving a remote timestamp.
  ///
  /// Ensures the local clock advances past both its own state and the
  /// remote state, maintaining the monotonicity invariant.
  void receive(HLCTimestamp remote) {
    final wallMs = _wallClock?.call() ?? DateTime.now().millisecondsSinceEpoch;

    if (wallMs > _physicalMs && wallMs > remote.physicalMs) {
      _physicalMs = wallMs;
      _counter = 0;
    } else if (remote.physicalMs > _physicalMs) {
      _physicalMs = remote.physicalMs;
      _counter = remote.counter + 1;
    } else if (_physicalMs == remote.physicalMs) {
      _counter = max(_counter, remote.counter) + 1;
    } else {
      // _physicalMs > remote.physicalMs — local is ahead
      _counter++;
    }
  }

  /// Current clock state (read-only snapshot).
  HLCTimestamp get current =>
      HLCTimestamp(physicalMs: _physicalMs, counter: _counter, peerId: peerId);
}

/// An immutable HLC timestamp.
///
/// Ordered first by [physicalMs], then [counter], then [peerId]
/// for total deterministic ordering across all peers.
class HLCTimestamp implements Comparable<HLCTimestamp> {
  final int physicalMs;
  final int counter;
  final String peerId;

  const HLCTimestamp({
    required this.physicalMs,
    required this.counter,
    required this.peerId,
  });

  @override
  int compareTo(HLCTimestamp other) {
    if (physicalMs != other.physicalMs) {
      return physicalMs.compareTo(other.physicalMs);
    }
    if (counter != other.counter) {
      return counter.compareTo(other.counter);
    }
    return peerId.compareTo(other.peerId);
  }

  bool operator >(HLCTimestamp other) => compareTo(other) > 0;
  bool operator <(HLCTimestamp other) => compareTo(other) < 0;
  bool operator >=(HLCTimestamp other) => compareTo(other) >= 0;
  bool operator <=(HLCTimestamp other) => compareTo(other) <= 0;

  Map<String, dynamic> toJson() => {
    'ms': physicalMs,
    'c': counter,
    'p': peerId,
  };

  factory HLCTimestamp.fromJson(Map<String, dynamic> json) => HLCTimestamp(
    physicalMs: (json['ms'] as num).toInt(),
    counter: (json['c'] as num).toInt(),
    peerId: json['p'] as String,
  );

  /// The zero / epoch timestamp — older than any real event.
  static const zero = HLCTimestamp(physicalMs: 0, counter: 0, peerId: '');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HLCTimestamp &&
          physicalMs == other.physicalMs &&
          counter == other.counter &&
          peerId == other.peerId;

  @override
  int get hashCode => Object.hash(physicalMs, counter, peerId);

  @override
  String toString() => 'HLC($physicalMs:$counter@$peerId)';
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. LWW-REGISTER — Last-Writer-Wins Register for single values
// ─────────────────────────────────────────────────────────────────────────────

/// A Last-Writer-Wins Register: stores a single value with a timestamp.
///
/// When two concurrent writes occur, the one with the greater
/// [HLCTimestamp] wins deterministically (no data loss for the winner).
///
/// ```dart
/// final reg = LWWRegister<double>(42.0, ts1);
/// reg.set(100.0, ts2); // ts2 > ts1 → value becomes 100.0
/// reg.set(50.0, ts1);  // ts1 < ts2 → ignored
/// ```
class LWWRegister<T> {
  T _value;
  HLCTimestamp _timestamp;

  LWWRegister(this._value, this._timestamp);

  /// The current value.
  T get value => _value;

  /// The timestamp of the current value.
  HLCTimestamp get timestamp => _timestamp;

  /// Set a new value if [ts] is strictly later than the current timestamp.
  ///
  /// Returns `true` if the value was updated.
  bool set(T newValue, HLCTimestamp ts) {
    if (ts > _timestamp) {
      _value = newValue;
      _timestamp = ts;
      return true;
    }
    return false;
  }

  /// Merge with a remote register — take the one with the later timestamp.
  bool merge(LWWRegister<T> other) => set(other._value, other._timestamp);

  Map<String, dynamic> toJson(dynamic Function(T) serializeValue) => {
    'v': serializeValue(_value),
    'ts': _timestamp.toJson(),
  };

  factory LWWRegister.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic) deserializeValue,
  ) => LWWRegister(
    deserializeValue(json['v']),
    HLCTimestamp.fromJson(json['ts'] as Map<String, dynamic>),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. LWW-ELEMENT-SET — Add/Remove set with bias toward add
// ─────────────────────────────────────────────────────────────────────────────

/// A CRDT set that tracks element membership using add/remove timestamps.
///
/// An element is considered present if its add timestamp > its remove
/// timestamp. This provides:
/// - Concurrent add+remove → add wins (add-bias, common for design tools)
/// - Deterministic convergence regardless of message order
/// - Tombstone-based tracking (removed elements remembered for merge)
///
/// ```dart
/// final set = LWWElementSet<String>();
/// set.add('node_1', ts1);
/// set.remove('node_1', ts2); // ts2 > ts1 → node removed
/// set.add('node_1', ts3);    // ts3 > ts2 → node re-added
/// ```
class LWWElementSet<E> {
  /// Add timestamps: element → HLC when it was added.
  final Map<E, HLCTimestamp> _addMap = {};

  /// Remove timestamps: element → HLC when it was removed.
  final Map<E, HLCTimestamp> _removeMap = {};

  /// Default constructor.
  LWWElementSet();

  /// Add an element with the given timestamp.
  void add(E element, HLCTimestamp ts) {
    final existing = _addMap[element];
    if (existing == null || ts > existing) {
      _addMap[element] = ts;
    }
  }

  /// Remove an element with the given timestamp.
  void remove(E element, HLCTimestamp ts) {
    final existing = _removeMap[element];
    if (existing == null || ts > existing) {
      _removeMap[element] = ts;
    }
  }

  /// Whether an element is currently in the set.
  ///
  /// Present if: added AND (not removed OR add > remove).
  bool contains(E element) {
    final addTs = _addMap[element];
    if (addTs == null) return false;
    final removeTs = _removeMap[element];
    if (removeTs == null) return true;
    return addTs >= removeTs; // add-bias: tie goes to add
  }

  /// All currently present elements.
  Set<E> get elements => _addMap.keys.where((e) => contains(e)).toSet();

  /// Merge another LWW-Element-Set into this one.
  void merge(LWWElementSet<E> other) {
    for (final entry in other._addMap.entries) {
      final existing = _addMap[entry.key];
      if (existing == null || entry.value > existing) {
        _addMap[entry.key] = entry.value;
      }
    }
    for (final entry in other._removeMap.entries) {
      final existing = _removeMap[entry.key];
      if (existing == null || entry.value > existing) {
        _removeMap[entry.key] = entry.value;
      }
    }
  }

  /// Number of currently present elements.
  int get length => elements.length;

  /// Compact tombstones older than [cutoff] for elements not in the set.
  ///
  /// Call periodically to prevent unbounded tombstone growth.
  int gc(HLCTimestamp cutoff) {
    var removed = 0;
    final toRemove = <E>[];
    for (final entry in _removeMap.entries) {
      if (!contains(entry.key) && entry.value < cutoff) {
        toRemove.add(entry.key);
      }
    }
    for (final e in toRemove) {
      _addMap.remove(e);
      _removeMap.remove(e);
      removed++;
    }
    return removed;
  }

  Map<String, dynamic> toJson(String Function(E) serializeElement) => {
    'add': {
      for (final e in _addMap.entries)
        serializeElement(e.key): e.value.toJson(),
    },
    'rm': {
      for (final e in _removeMap.entries)
        serializeElement(e.key): e.value.toJson(),
    },
  };

  factory LWWElementSet.fromJson(
    Map<String, dynamic> json,
    E Function(String) deserializeElement,
  ) {
    final set = LWWElementSet<E>();
    final addMap = json['add'] as Map<String, dynamic>? ?? {};
    final rmMap = json['rm'] as Map<String, dynamic>? ?? {};
    for (final entry in addMap.entries) {
      set._addMap[deserializeElement(entry.key)] = HLCTimestamp.fromJson(
        entry.value as Map<String, dynamic>,
      );
    }
    for (final entry in rmMap.entries) {
      set._removeMap[deserializeElement(entry.key)] = HLCTimestamp.fromJson(
        entry.value as Map<String, dynamic>,
      );
    }
    return set;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. CRDT NODE STATE — Per-node property map using LWW-Registers
// ─────────────────────────────────────────────────────────────────────────────

/// CRDT state for a single scene graph node.
///
/// Each property (x, y, width, opacity, fill, etc.) is stored as a
/// separate [LWWRegister], allowing concurrent edits to different
/// properties to merge without conflict.
///
/// ```dart
/// final state = CRDTNodeState('node_1');
/// state.setProperty('x', 100.0, ts1);
/// state.setProperty('y', 200.0, ts1);
/// state.setProperty('x', 150.0, ts2); // Only x updated, y unchanged
/// ```
class CRDTNodeState {
  /// The node ID in the scene graph.
  final String nodeId;

  /// The node type (e.g., 'shape', 'text', 'group').
  final LWWRegister<String> nodeType;

  /// Property registers: propertyName → LWW register.
  final Map<String, LWWRegister<dynamic>> _properties = {};

  /// Parent node ID (for tree structure), stored as LWW for reparenting.
  final LWWRegister<String?> parentId;

  /// Sort index within parent (for ordering), stored as LWW.
  final LWWRegister<int> sortIndex;

  CRDTNodeState(
    this.nodeId, {
    required String type,
    required HLCTimestamp createdAt,
    String? parent,
    int index = 0,
  }) : nodeType = LWWRegister(type, createdAt),
       parentId = LWWRegister(parent, createdAt),
       sortIndex = LWWRegister(index, createdAt);

  /// Set a property value with a timestamp.
  ///
  /// Returns `true` if the value was updated (timestamp was newer).
  bool setProperty(String name, dynamic value, HLCTimestamp ts) {
    final existing = _properties[name];
    if (existing == null) {
      _properties[name] = LWWRegister(value, ts);
      return true;
    }
    return existing.set(value, ts);
  }

  /// Get the current value of a property.
  dynamic getProperty(String name) => _properties[name]?.value;

  /// Get the timestamp of a property's last update.
  HLCTimestamp? getPropertyTimestamp(String name) =>
      _properties[name]?.timestamp;

  /// All property names.
  Iterable<String> get propertyNames => _properties.keys;

  /// Merge another node state into this one.
  ///
  /// Each property register is merged independently — the one
  /// with the later timestamp wins per-property.
  void merge(CRDTNodeState other) {
    assert(nodeId == other.nodeId, 'Cannot merge states for different nodes');
    nodeType.merge(other.nodeType);
    parentId.merge(other.parentId);
    sortIndex.merge(other.sortIndex);

    for (final entry in other._properties.entries) {
      final existing = _properties[entry.key];
      if (existing == null) {
        _properties[entry.key] = LWWRegister(
          entry.value.value,
          entry.value.timestamp,
        );
      } else {
        existing.merge(entry.value);
      }
    }
  }

  /// Export all properties as a flat map.
  Map<String, dynamic> toPropertyMap() => {
    for (final entry in _properties.entries) entry.key: entry.value.value,
  };

  Map<String, dynamic> toJson() => {
    'nodeId': nodeId,
    'type': nodeType.toJson((v) => v),
    'parent': parentId.toJson((v) => v),
    'sort': sortIndex.toJson((v) => v),
    'props': {
      for (final e in _properties.entries) e.key: e.value.toJson((v) => v),
    },
  };

  factory CRDTNodeState.fromJson(Map<String, dynamic> json) {
    final typeReg = LWWRegister<String>.fromJson(
      json['type'] as Map<String, dynamic>,
      (v) => v as String,
    );
    final parentReg = LWWRegister<String?>.fromJson(
      json['parent'] as Map<String, dynamic>,
      (v) => v as String?,
    );
    final sortReg = LWWRegister<int>.fromJson(
      json['sort'] as Map<String, dynamic>,
      (v) => (v as num).toInt(),
    );

    final state = CRDTNodeState(
      json['nodeId'] as String,
      type: typeReg.value,
      createdAt: typeReg.timestamp,
      parent: parentReg.value,
      index: sortReg.value,
    );

    // Override with actual deserialized registers
    state.nodeType.set(typeReg.value, typeReg.timestamp);
    state.parentId.set(parentReg.value, parentReg.timestamp);
    state.sortIndex.set(sortReg.value, sortReg.timestamp);

    final props = json['props'] as Map<String, dynamic>? ?? {};
    for (final entry in props.entries) {
      final reg = LWWRegister<dynamic>.fromJson(
        entry.value as Map<String, dynamic>,
        (v) => v,
      );
      state._properties[entry.key] = reg;
    }

    return state;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. CRDT OPERATION — Serializable operation envelope
// ─────────────────────────────────────────────────────────────────────────────

/// Type of CRDT operation on the scene graph.
enum CRDTOpType {
  /// Add a new node to the scene graph.
  addNode,

  /// Remove a node (tombstoned, not physically deleted).
  removeNode,

  /// Set a property on a node.
  setProperty,

  /// Move a node to a new parent / sort index.
  moveNode,

  /// Batch of multiple operations (atomic group).
  batch,
}

/// A single CRDT operation that can be serialized and broadcast.
///
/// Operations are idempotent — applying the same operation twice has
/// no effect (because of LWW timestamp comparison).
class CRDTOperation {
  /// Unique operation ID.
  final String opId;

  /// Type of operation.
  final CRDTOpType type;

  /// Target node ID.
  final String nodeId;

  /// HLC timestamp when the operation was created.
  final HLCTimestamp timestamp;

  /// Peer that originated the operation.
  final String peerId;

  /// Operation payload (varies by type).
  final Map<String, dynamic> payload;

  /// Sub-operations for batch type.
  final List<CRDTOperation>? batch;

  const CRDTOperation({
    required this.opId,
    required this.type,
    required this.nodeId,
    required this.timestamp,
    required this.peerId,
    this.payload = const {},
    this.batch,
  });

  /// Create an "add node" operation.
  factory CRDTOperation.addNode({
    required String opId,
    required String nodeId,
    required String nodeType,
    required HLCTimestamp timestamp,
    required String peerId,
    String? parentId,
    int sortIndex = 0,
    Map<String, dynamic> properties = const {},
  }) => CRDTOperation(
    opId: opId,
    type: CRDTOpType.addNode,
    nodeId: nodeId,
    timestamp: timestamp,
    peerId: peerId,
    payload: {
      'nodeType': nodeType,
      'parentId': parentId,
      'sortIndex': sortIndex,
      ...properties,
    },
  );

  /// Create a "remove node" operation.
  factory CRDTOperation.removeNode({
    required String opId,
    required String nodeId,
    required HLCTimestamp timestamp,
    required String peerId,
  }) => CRDTOperation(
    opId: opId,
    type: CRDTOpType.removeNode,
    nodeId: nodeId,
    timestamp: timestamp,
    peerId: peerId,
  );

  /// Create a "set property" operation.
  factory CRDTOperation.setProperty({
    required String opId,
    required String nodeId,
    required String propertyName,
    required dynamic value,
    required HLCTimestamp timestamp,
    required String peerId,
  }) => CRDTOperation(
    opId: opId,
    type: CRDTOpType.setProperty,
    nodeId: nodeId,
    timestamp: timestamp,
    peerId: peerId,
    payload: {'property': propertyName, 'value': value},
  );

  /// Create a "move node" operation (reparent + reorder).
  factory CRDTOperation.moveNode({
    required String opId,
    required String nodeId,
    required String? newParentId,
    required int newSortIndex,
    required HLCTimestamp timestamp,
    required String peerId,
  }) => CRDTOperation(
    opId: opId,
    type: CRDTOpType.moveNode,
    nodeId: nodeId,
    timestamp: timestamp,
    peerId: peerId,
    payload: {'parentId': newParentId, 'sortIndex': newSortIndex},
  );

  /// Create a batch of operations (atomic group).
  factory CRDTOperation.batchOp({
    required String opId,
    required HLCTimestamp timestamp,
    required String peerId,
    required List<CRDTOperation> operations,
  }) => CRDTOperation(
    opId: opId,
    type: CRDTOpType.batch,
    nodeId: '',
    timestamp: timestamp,
    peerId: peerId,
    batch: operations,
  );

  Map<String, dynamic> toJson() => {
    'opId': opId,
    'type': type.name,
    'nodeId': nodeId,
    'ts': timestamp.toJson(),
    'peer': peerId,
    'payload': payload,
    if (batch != null) 'batch': batch!.map((o) => o.toJson()).toList(),
  };

  factory CRDTOperation.fromJson(Map<String, dynamic> json) {
    final batchJson = json['batch'] as List?;
    return CRDTOperation(
      opId: json['opId'] as String,
      type: CRDTOpType.values.firstWhere((e) => e.name == json['type']),
      nodeId: json['nodeId'] as String,
      timestamp: HLCTimestamp.fromJson(json['ts'] as Map<String, dynamic>),
      peerId: json['peer'] as String,
      payload: Map<String, dynamic>.from(json['payload'] as Map? ?? {}),
      batch:
          batchJson
              ?.map((j) => CRDTOperation.fromJson(j as Map<String, dynamic>))
              .toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 6. CRDT SCENE GRAPH — Full scene graph state as CRDTs
// ─────────────────────────────────────────────────────────────────────────────

/// CRDT-based scene graph state that can be merged from any peer.
///
/// This is the core merge layer between the local scene graph and the
/// network. Each peer maintains a [CRDTSceneGraph] and applies
/// [CRDTOperation]s. When two peers' states are merged, the result
/// converges deterministically.
///
/// ```dart
/// final state = CRDTSceneGraph(localPeerId: 'peer_1');
/// final op = state.addNode(nodeId: 'n1', nodeType: 'shape');
/// // Broadcast op to other peers...
///
/// // On receiving remote op:
/// final changes = state.apply(remoteOp);
/// // Apply changes to local SceneGraph
/// ```
class CRDTSceneGraph {
  /// The local peer ID.
  final String localPeerId;

  /// HLC for generating timestamps.
  final HybridLogicalClock _clock;

  /// Node membership set: which nodes exist in the graph.
  final LWWElementSet<String> _nodeSet = LWWElementSet();

  /// Per-node CRDT state.
  final Map<String, CRDTNodeState> _nodeStates = {};

  /// Applied operation IDs (deduplication).
  final Set<String> _appliedOps = {};

  /// Operation counter for generating unique op IDs.
  int _opCounter = 0;

  /// Callback for when a merge produces changes.
  final List<void Function(List<CRDTChange>)> _changeListeners = [];

  CRDTSceneGraph({required this.localPeerId, int Function()? wallClock})
    : _clock = HybridLogicalClock(localPeerId, wallClock: wallClock);

  /// Listen for changes produced by applying operations.
  void addChangeListener(void Function(List<CRDTChange>) listener) {
    _changeListeners.add(listener);
  }

  /// Remove a change listener.
  void removeChangeListener(void Function(List<CRDTChange>) listener) {
    _changeListeners.remove(listener);
  }

  /// Generate a unique operation ID.
  String _nextOpId() => '${localPeerId}_${_opCounter++}';

  // ─── Local operations (generate + apply) ──────────────────────────

  /// Add a node to the scene graph. Returns the operation to broadcast.
  CRDTOperation addNode({
    required String nodeId,
    required String nodeType,
    String? parentId,
    int sortIndex = 0,
    Map<String, dynamic> properties = const {},
  }) {
    final ts = _clock.now();
    final op = CRDTOperation.addNode(
      opId: _nextOpId(),
      nodeId: nodeId,
      nodeType: nodeType,
      timestamp: ts,
      peerId: localPeerId,
      parentId: parentId,
      sortIndex: sortIndex,
      properties: properties,
    );
    apply(op);
    return op;
  }

  /// Remove a node. Returns the operation to broadcast.
  CRDTOperation removeNode(String nodeId) {
    final ts = _clock.now();
    final op = CRDTOperation.removeNode(
      opId: _nextOpId(),
      nodeId: nodeId,
      timestamp: ts,
      peerId: localPeerId,
    );
    apply(op);
    return op;
  }

  /// Set a property on a node. Returns the operation to broadcast.
  CRDTOperation setProperty(String nodeId, String propertyName, dynamic value) {
    final ts = _clock.now();
    final op = CRDTOperation.setProperty(
      opId: _nextOpId(),
      nodeId: nodeId,
      propertyName: propertyName,
      value: value,
      timestamp: ts,
      peerId: localPeerId,
    );
    apply(op);
    return op;
  }

  /// Move a node (reparent + reorder). Returns the operation to broadcast.
  CRDTOperation moveNode(
    String nodeId, {
    String? newParentId,
    int newSortIndex = 0,
  }) {
    final ts = _clock.now();
    final op = CRDTOperation.moveNode(
      opId: _nextOpId(),
      nodeId: nodeId,
      newParentId: newParentId,
      newSortIndex: newSortIndex,
      timestamp: ts,
      peerId: localPeerId,
    );
    apply(op);
    return op;
  }

  // ─── Apply operations (local or remote) ────────────────────────────

  /// Apply a CRDT operation. Idempotent — duplicate ops are ignored.
  ///
  /// Returns the list of changes that were applied to the state.
  List<CRDTChange> apply(CRDTOperation op) {
    // Deduplication
    if (_appliedOps.contains(op.opId)) return const [];
    _appliedOps.add(op.opId);

    // Update HLC from remote
    if (op.peerId != localPeerId) {
      _clock.receive(op.timestamp);
    }

    final changes = <CRDTChange>[];

    switch (op.type) {
      case CRDTOpType.addNode:
        _nodeSet.add(op.nodeId, op.timestamp);

        final nodeType = op.payload['nodeType'] as String? ?? 'unknown';
        final parentId = op.payload['parentId'] as String?;
        final sortIndex = (op.payload['sortIndex'] as num?)?.toInt() ?? 0;

        final state = _nodeStates.putIfAbsent(
          op.nodeId,
          () => CRDTNodeState(
            op.nodeId,
            type: nodeType,
            createdAt: op.timestamp,
            parent: parentId,
            index: sortIndex,
          ),
        );

        // Apply any additional properties
        for (final entry in op.payload.entries) {
          if (entry.key == 'nodeType' ||
              entry.key == 'parentId' ||
              entry.key == 'sortIndex')
            continue;
          state.setProperty(entry.key, entry.value, op.timestamp);
        }

        if (_nodeSet.contains(op.nodeId)) {
          changes.add(CRDTChange.added(op.nodeId, nodeType));
        }

      case CRDTOpType.removeNode:
        _nodeSet.remove(op.nodeId, op.timestamp);
        if (!_nodeSet.contains(op.nodeId)) {
          changes.add(CRDTChange.removed(op.nodeId));
        }

      case CRDTOpType.setProperty:
        final name = op.payload['property'] as String;
        final value = op.payload['value'];
        final state = _nodeStates[op.nodeId];
        if (state != null && state.setProperty(name, value, op.timestamp)) {
          changes.add(CRDTChange.propertyChanged(op.nodeId, name, value));
        }

      case CRDTOpType.moveNode:
        final state = _nodeStates[op.nodeId];
        if (state != null) {
          final parentId = op.payload['parentId'] as String?;
          final sortIndex = (op.payload['sortIndex'] as num?)?.toInt() ?? 0;
          final parentChanged = state.parentId.set(parentId, op.timestamp);
          final sortChanged = state.sortIndex.set(sortIndex, op.timestamp);
          if (parentChanged || sortChanged) {
            changes.add(CRDTChange.moved(op.nodeId, parentId, sortIndex));
          }
        }

      case CRDTOpType.batch:
        if (op.batch != null) {
          for (final subOp in op.batch!) {
            changes.addAll(apply(subOp));
          }
        }
    }

    if (changes.isNotEmpty) {
      for (final listener in _changeListeners) {
        listener(changes);
      }
    }

    return changes;
  }

  // ─── State queries ─────────────────────────────────────────────────

  /// All live (non-tombstoned) node IDs.
  Set<String> get liveNodeIds => _nodeSet.elements;

  /// Whether a node exists in the graph.
  bool containsNode(String nodeId) => _nodeSet.contains(nodeId);

  /// Get the CRDT state for a node.
  CRDTNodeState? nodeState(String nodeId) => _nodeStates[nodeId];

  /// Number of live nodes.
  int get nodeCount => _nodeSet.length;

  /// Number of applied operations (for stats).
  int get appliedOpCount => _appliedOps.length;

  /// Children of a node, sorted by sortIndex.
  List<String> childrenOf(String? parentId) {
    final children = <MapEntry<String, int>>[];
    for (final nodeId in liveNodeIds) {
      final state = _nodeStates[nodeId];
      if (state != null && state.parentId.value == parentId) {
        children.add(MapEntry(nodeId, state.sortIndex.value));
      }
    }
    children.sort((a, b) => a.value.compareTo(b.value));
    return children.map((e) => e.key).toList();
  }

  // ─── Full-state merge ──────────────────────────────────────────────

  /// Merge another peer's full state into this one.
  ///
  /// Use for initial sync or reconnection.
  List<CRDTChange> mergeState(CRDTSceneGraph other) {
    final changes = <CRDTChange>[];

    // Merge node membership set
    final oldLive = _nodeSet.elements;
    _nodeSet.merge(other._nodeSet);
    final newLive = _nodeSet.elements;

    // Detect additions
    for (final nodeId in newLive.difference(oldLive)) {
      final state = other._nodeStates[nodeId];
      if (state != null) {
        changes.add(CRDTChange.added(nodeId, state.nodeType.value));
      }
    }

    // Detect removals
    for (final nodeId in oldLive.difference(newLive)) {
      changes.add(CRDTChange.removed(nodeId));
    }

    // Merge per-node states
    for (final entry in other._nodeStates.entries) {
      final existing = _nodeStates[entry.key];
      if (existing == null) {
        _nodeStates[entry.key] = entry.value;
      } else {
        existing.merge(entry.value);
      }
    }

    // Merge applied ops
    _appliedOps.addAll(other._appliedOps);

    // Update HLC
    _clock.receive(other._clock.current);

    if (changes.isNotEmpty) {
      for (final listener in _changeListeners) {
        listener(changes);
      }
    }

    return changes;
  }

  /// Compact tombstones older than [cutoff].
  int gc(HLCTimestamp cutoff) {
    final removed = _nodeSet.gc(cutoff);
    // Remove node states for garbage-collected nodes
    _nodeStates.removeWhere(
      (id, _) => !_nodeSet.contains(id) && !_nodeSet.elements.contains(id),
    );
    return removed;
  }

  Map<String, dynamic> toJson() => {
    'peer': localPeerId,
    'nodes': _nodeSet.toJson((e) => e),
    'states': {for (final e in _nodeStates.entries) e.key: e.value.toJson()},
    'ops': _appliedOps.toList(),
  };

  factory CRDTSceneGraph.fromJson(Map<String, dynamic> json) {
    final graph = CRDTSceneGraph(localPeerId: json['peer'] as String);
    graph._nodeSet.merge(
      LWWElementSet<String>.fromJson(
        json['nodes'] as Map<String, dynamic>,
        (String s) => s,
      ),
    );
    final states = json['states'] as Map<String, dynamic>? ?? {};
    for (final entry in states.entries) {
      graph._nodeStates[entry.key] = CRDTNodeState.fromJson(
        entry.value as Map<String, dynamic>,
      );
    }
    final ops = json['ops'] as List? ?? [];
    graph._appliedOps.addAll(ops.cast<String>());
    return graph;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 7. CRDT CHANGE — Describes what changed after applying an operation
// ─────────────────────────────────────────────────────────────────────────────

/// The type of change that occurred.
enum CRDTChangeType { added, removed, propertyChanged, moved }

/// A single change produced by applying a CRDT operation.
///
/// Use these to update the local SceneGraph after merging.
class CRDTChange {
  final CRDTChangeType type;
  final String nodeId;
  final String? nodeType;
  final String? propertyName;
  final dynamic propertyValue;
  final String? newParentId;
  final int? newSortIndex;

  const CRDTChange._({
    required this.type,
    required this.nodeId,
    this.nodeType,
    this.propertyName,
    this.propertyValue,
    this.newParentId,
    this.newSortIndex,
  });

  factory CRDTChange.added(String nodeId, String nodeType) => CRDTChange._(
    type: CRDTChangeType.added,
    nodeId: nodeId,
    nodeType: nodeType,
  );

  factory CRDTChange.removed(String nodeId) =>
      CRDTChange._(type: CRDTChangeType.removed, nodeId: nodeId);

  factory CRDTChange.propertyChanged(
    String nodeId,
    String property,
    dynamic value,
  ) => CRDTChange._(
    type: CRDTChangeType.propertyChanged,
    nodeId: nodeId,
    propertyName: property,
    propertyValue: value,
  );

  factory CRDTChange.moved(String nodeId, String? parentId, int sortIndex) =>
      CRDTChange._(
        type: CRDTChangeType.moved,
        nodeId: nodeId,
        newParentId: parentId,
        newSortIndex: sortIndex,
      );

  @override
  String toString() {
    switch (type) {
      case CRDTChangeType.added:
        return 'Added $nodeId ($nodeType)';
      case CRDTChangeType.removed:
        return 'Removed $nodeId';
      case CRDTChangeType.propertyChanged:
        return 'Changed $nodeId.$propertyName = $propertyValue';
      case CRDTChangeType.moved:
        return 'Moved $nodeId → parent=$newParentId, idx=$newSortIndex';
    }
  }
}
