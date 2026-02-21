import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'nebula_realtime_adapter.dart';

// =============================================================================
// ⭐ ENTERPRISE REAL-TIME COLLABORATION — Top-Tier Modules
//
// This file provides enterprise-grade extensions for the realtime engine:
//   1. CRDT Vector Clock — causal ordering for conflict-free merges
//   2. Session Audit Log — who did what, when (compliance)
//   3. E2E Encryption — encrypt events before broadcast
//   4. Connection Quality — latency/jitter measurement
//   5. Bandwidth Adaptive — reduce frequency on slow connections
//   6. Undo/Redo Broadcast — remote undo visibility
// =============================================================================

// ─────────────────────────────────────────────────────────────────────────────
// 1. CRDT VECTOR CLOCK — Causal ordering for conflict-free event merging
// ─────────────────────────────────────────────────────────────────────────────

/// A vector clock for causal ordering of distributed events.
///
/// Each user maintains an incrementing counter. When a user sends an event,
/// it includes the full vector clock. Receivers merge clocks to maintain
/// causal ordering.
///
/// This ensures that:
/// - If event A happened before event B, A is always applied first
/// - Concurrent events (no causal relationship) are detected and can be
///   resolved by the application
class VectorClock {
  /// Logical clock per user: userId → counter.
  final Map<String, int> _clocks;

  VectorClock([Map<String, int>? initial])
    : _clocks = Map<String, int>.from(initial ?? {});

  /// Increment the local user's counter before sending.
  void tick(String userId) {
    _clocks[userId] = (_clocks[userId] ?? 0) + 1;
  }

  /// Get the current counter for a user.
  int operator [](String userId) => _clocks[userId] ?? 0;

  /// Merge with a received clock (take element-wise max).
  void merge(VectorClock other) {
    for (final entry in other._clocks.entries) {
      _clocks[entry.key] = max(_clocks[entry.key] ?? 0, entry.value);
    }
  }

  /// Check causal relationship.
  ///
  /// Returns:
  ///   -1: this happened before other
  ///    0: concurrent (conflict!)
  ///    1: this happened after other
  CausalOrder compareTo(VectorClock other) {
    bool thisBeforeOrEqual = true;
    bool otherBeforeOrEqual = true;

    final allKeys = {..._clocks.keys, ...other._clocks.keys};
    for (final key in allKeys) {
      final a = _clocks[key] ?? 0;
      final b = other._clocks[key] ?? 0;
      if (a > b) thisBeforeOrEqual = false;
      if (b > a) otherBeforeOrEqual = false;
    }

    if (thisBeforeOrEqual && otherBeforeOrEqual) return CausalOrder.equal;
    if (thisBeforeOrEqual) return CausalOrder.before;
    if (otherBeforeOrEqual) return CausalOrder.after;
    return CausalOrder.concurrent;
  }

  /// Serialize for network transport.
  Map<String, int> toJson() => Map<String, int>.from(_clocks);

  /// Deserialize from network transport.
  factory VectorClock.fromJson(Map<String, dynamic> json) {
    return VectorClock(json.map((k, v) => MapEntry(k, (v as num).toInt())));
  }

  /// Create a copy.
  VectorClock copy() => VectorClock(Map<String, int>.from(_clocks));

  @override
  String toString() => 'VClock($_clocks)';
}

/// Causal ordering result.
enum CausalOrder {
  /// This event happened before the other.
  before,

  /// These events are concurrent (conflict).
  concurrent,

  /// This event happened after the other.
  after,

  /// Both clocks are identical.
  equal,
}

/// Wraps a [CanvasRealtimeEvent] with a vector clock for causal ordering.
class CausalEvent {
  final CanvasRealtimeEvent event;
  final VectorClock clock;

  const CausalEvent({required this.event, required this.clock});

  /// Serialize: embeds vector clock in the event payload.
  Map<String, dynamic> toJson() => {
    ...event.toJson(),
    '_vclock': clock.toJson(),
  };

  /// Deserialize: extracts vector clock from payload.
  factory CausalEvent.fromJson(Map<String, dynamic> json) {
    final vclockJson = json['_vclock'] as Map<String, dynamic>? ?? {};
    final clock = VectorClock.fromJson(vclockJson);
    final eventJson = Map<String, dynamic>.from(json)..remove('_vclock');
    return CausalEvent(
      event: CanvasRealtimeEvent.fromJson(eventJson),
      clock: clock,
    );
  }

  /// Check if this event is concurrent with another (conflict).
  bool isConcurrentWith(CausalEvent other) =>
      clock.compareTo(other.clock) == CausalOrder.concurrent;
}

/// Manages vector clock state for the local user.
///
/// Usage:
/// ```dart
/// final vc = VectorClockManager('user_123');
/// final clock = vc.tick(); // Increment before broadcasting
/// vc.merge(remoteClock);   // Merge on receiving remote event
/// ```
class VectorClockManager {
  final String _localUserId;
  final VectorClock _clock = VectorClock();

  VectorClockManager(this._localUserId);

  /// Increment local counter and return a snapshot for broadcasting.
  VectorClock tick() {
    _clock.tick(_localUserId);
    return _clock.copy();
  }

  /// Merge an incoming clock (call on each received event).
  void merge(VectorClock remote) {
    _clock.merge(remote);
    // Also tick local to advance past the merge
    _clock.tick(_localUserId);
  }

  /// Current clock state (read-only copy).
  VectorClock get current => _clock.copy();

  /// Check causal order of a remote event relative to local state.
  CausalOrder checkOrder(VectorClock remote) => _clock.compareTo(remote);
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. SESSION AUDIT LOG — Enterprise compliance (who did what, when)
// ─────────────────────────────────────────────────────────────────────────────

/// A single audit log entry.
class AuditLogEntry {
  /// Unique log ID.
  final String id;

  /// User who performed the action.
  final String userId;

  /// Display name of the user.
  final String? userName;

  /// Type of action performed.
  final AuditAction action;

  /// Affected element ID (stroke, image, text...).
  final String? elementId;

  /// Human-readable description.
  final String description;

  /// ISO 8601 timestamp.
  final DateTime timestamp;

  /// Additional metadata.
  final Map<String, dynamic>? metadata;

  const AuditLogEntry({
    required this.id,
    required this.userId,
    this.userName,
    required this.action,
    this.elementId,
    required this.description,
    required this.timestamp,
    this.metadata,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    if (userName != null) 'userName': userName,
    'action': action.name,
    if (elementId != null) 'elementId': elementId,
    'description': description,
    'timestamp': timestamp.toIso8601String(),
    if (metadata != null) 'metadata': metadata,
  };

  factory AuditLogEntry.fromJson(Map<String, dynamic> json) {
    return AuditLogEntry(
      id: json['id'] as String,
      userId: json['userId'] as String,
      userName: json['userName'] as String?,
      action: AuditAction.values.firstWhere(
        (e) => e.name == json['action'],
        orElse: () => AuditAction.unknown,
      ),
      elementId: json['elementId'] as String?,
      description: json['description'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }
}

/// Types of auditable actions.
enum AuditAction {
  /// User joined the canvas session.
  sessionJoin,

  /// User left the canvas session.
  sessionLeave,

  /// Stroke was added.
  strokeAdd,

  /// Stroke was removed.
  strokeRemove,

  /// Image was added or updated.
  imageChange,

  /// Image was removed.
  imageRemove,

  /// Text was created or changed.
  textChange,

  /// Text was removed.
  textRemove,

  /// Element was locked.
  elementLock,

  /// Element was unlocked.
  elementUnlock,

  /// Layer was changed.
  layerChange,

  /// Settings were changed.
  settingsChange,

  /// Undo was performed.
  undo,

  /// Redo was performed.
  redo,

  /// Conflict was detected and resolved.
  conflictResolved,

  /// Unknown action.
  unknown,
}

/// In-memory audit log with configurable capacity.
///
/// For persistent audit trails, the host app should subscribe to
/// [onEntry] and write entries to their backend.
class SessionAuditLog {
  /// Max entries to keep in memory.
  final int maxEntries;

  /// In-memory log (newest first).
  final List<AuditLogEntry> _entries = [];

  /// Stream of new audit entries (for persistence by host app).
  Stream<AuditLogEntry> get onEntry => _entryController.stream;
  final _entryController = StreamController<AuditLogEntry>.broadcast();

  SessionAuditLog({this.maxEntries = 1000});

  /// Add an audit entry.
  void log(AuditLogEntry entry) {
    _entries.insert(0, entry);
    if (_entries.length > maxEntries) {
      _entries.removeLast();
    }
    _entryController.add(entry);
  }

  /// Convenience: log from a realtime event.
  void logEvent(CanvasRealtimeEvent event, {String? userName}) {
    log(
      AuditLogEntry(
        id: '${event.timestamp}_${event.senderId}_${event.type.name}',
        userId: event.senderId,
        userName: userName,
        action: _eventTypeToAction(event.type),
        elementId: event.elementId,
        description: _describeEvent(event),
        timestamp: DateTime.fromMillisecondsSinceEpoch(event.timestamp),
        metadata: {'payloadKeys': event.payload.keys.toList()},
      ),
    );
  }

  /// Log a session join/leave.
  void logSession(String userId, bool joined, {String? userName}) {
    log(
      AuditLogEntry(
        id:
            '${DateTime.now().millisecondsSinceEpoch}_${userId}_'
            '${joined ? 'join' : 'leave'}',
        userId: userId,
        userName: userName,
        action: joined ? AuditAction.sessionJoin : AuditAction.sessionLeave,
        description:
            '${userName ?? userId} '
            '${joined ? 'joined' : 'left'} the session',
        timestamp: DateTime.now(),
      ),
    );
  }

  /// Get all entries.
  List<AuditLogEntry> get entries => List.unmodifiable(_entries);

  /// Get entries for a specific user.
  List<AuditLogEntry> entriesForUser(String userId) =>
      _entries.where((e) => e.userId == userId).toList();

  /// Get entries of a specific action type.
  List<AuditLogEntry> entriesOfAction(AuditAction action) =>
      _entries.where((e) => e.action == action).toList();

  /// Total number of entries.
  int get length => _entries.length;

  /// Clear all entries.
  void clear() => _entries.clear();

  /// Export as JSON list.
  List<Map<String, dynamic>> toJson() =>
      _entries.map((e) => e.toJson()).toList();

  void dispose() {
    _entryController.close();
  }

  AuditAction _eventTypeToAction(RealtimeEventType type) {
    switch (type) {
      case RealtimeEventType.strokeAdded:
        return AuditAction.strokeAdd;
      case RealtimeEventType.strokeRemoved:
        return AuditAction.strokeRemove;
      case RealtimeEventType.imageAdded:
      case RealtimeEventType.imageUpdated:
        return AuditAction.imageChange;
      case RealtimeEventType.imageRemoved:
        return AuditAction.imageRemove;
      case RealtimeEventType.textChanged:
        return AuditAction.textChange;
      case RealtimeEventType.textRemoved:
        return AuditAction.textRemove;
      case RealtimeEventType.elementLocked:
        return AuditAction.elementLock;
      case RealtimeEventType.elementUnlocked:
        return AuditAction.elementUnlock;
      case RealtimeEventType.layerChanged:
        return AuditAction.layerChange;
      case RealtimeEventType.canvasSettingsChanged:
        return AuditAction.settingsChange;
      case RealtimeEventType.strokePointsStreamed:
        return AuditAction.strokeAdd; // Live streaming is a sub-action
    }
  }

  String _describeEvent(CanvasRealtimeEvent event) {
    final elementPart = event.elementId != null ? ' on ${event.elementId}' : '';
    switch (event.type) {
      case RealtimeEventType.strokeAdded:
        return 'Added stroke$elementPart';
      case RealtimeEventType.strokeRemoved:
        return 'Removed stroke$elementPart';
      case RealtimeEventType.imageAdded:
        return 'Added image$elementPart';
      case RealtimeEventType.imageUpdated:
        return 'Updated image$elementPart';
      case RealtimeEventType.imageRemoved:
        return 'Removed image$elementPart';
      case RealtimeEventType.textChanged:
        return 'Changed text$elementPart';
      case RealtimeEventType.textRemoved:
        return 'Removed text$elementPart';
      case RealtimeEventType.elementLocked:
        return 'Locked element$elementPart';
      case RealtimeEventType.elementUnlocked:
        return 'Unlocked element$elementPart';
      case RealtimeEventType.layerChanged:
        return 'Changed layer$elementPart';
      case RealtimeEventType.canvasSettingsChanged:
        return 'Changed canvas settings';
      case RealtimeEventType.strokePointsStreamed:
        return 'Streaming stroke$elementPart';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. E2E ENCRYPTION — Encrypt events before broadcast
// ─────────────────────────────────────────────────────────────────────────────

/// Abstract encryption provider — host app supplies the implementation.
///
/// The SDK doesn't bundle crypto packages; the host app provides their own
/// (e.g. `pointycastle`, `cryptography`, or platform-native APIs).
///
/// **Example (simple XOR cipher for development):**
/// ```dart
/// class DevEncryptionProvider implements RealtimeEncryptionProvider {
///   final Uint8List _key;
///   DevEncryptionProvider(String passphrase)
///     : _key = Uint8List.fromList(utf8.encode(passphrase));
///
///   @override
///   Future<Uint8List> encrypt(Uint8List data) async {
///     return Uint8List.fromList([
///       for (var i = 0; i < data.length; i++)
///         data[i] ^ _key[i % _key.length],
///     ]);
///   }
///
///   @override
///   Future<Uint8List> decrypt(Uint8List data) async => encrypt(data);
/// }
/// ```
abstract class RealtimeEncryptionProvider {
  /// Encrypt raw bytes.
  Future<Uint8List> encrypt(Uint8List plaintext);

  /// Decrypt raw bytes.
  Future<Uint8List> decrypt(Uint8List ciphertext);
}

/// Wraps a [NebulaRealtimeAdapter] to add transparent E2E encryption.
///
/// Events are serialized to JSON → UTF-8 → encrypted → base64 before
/// broadcast, and reversed on receive.
class EncryptedRealtimeAdapter implements NebulaRealtimeAdapter {
  final NebulaRealtimeAdapter _inner;
  final RealtimeEncryptionProvider _crypto;

  EncryptedRealtimeAdapter({
    required NebulaRealtimeAdapter inner,
    required RealtimeEncryptionProvider crypto,
  }) : _inner = inner,
       _crypto = crypto;

  @override
  Stream<CanvasRealtimeEvent> subscribe(String canvasId) {
    return _inner.subscribe(canvasId).asyncMap((event) async {
      // Decrypt the payload
      try {
        final encPayload = event.payload['_enc'] as String?;
        if (encPayload == null) return event; // Not encrypted

        final cipherBytes = base64Decode(encPayload);
        final plainBytes = await _crypto.decrypt(cipherBytes);
        final jsonStr = utf8.decode(plainBytes);
        final decryptedPayload = Map<String, dynamic>.from(
          jsonDecode(jsonStr) as Map,
        );

        return CanvasRealtimeEvent(
          type: event.type,
          senderId: event.senderId,
          elementId: event.elementId,
          payload: decryptedPayload,
          timestamp: event.timestamp,
        );
      } catch (e) {
        debugPrint('🔐 Decryption failed: $e');
        return event; // Return as-is on failure
      }
    });
  }

  @override
  Future<void> broadcast(String canvasId, CanvasRealtimeEvent event) async {
    try {
      // Encrypt the payload
      final jsonStr = jsonEncode(event.payload);
      final plainBytes = utf8.encode(jsonStr);
      final cipherBytes = await _crypto.encrypt(Uint8List.fromList(plainBytes));
      final encPayload = base64Encode(cipherBytes);

      final encEvent = CanvasRealtimeEvent(
        type: event.type,
        senderId: event.senderId,
        elementId: event.elementId,
        payload: {'_enc': encPayload},
        timestamp: event.timestamp,
      );

      await _inner.broadcast(canvasId, encEvent);
    } catch (e) {
      debugPrint('🔐 Encryption failed, sending plaintext: $e');
      await _inner.broadcast(canvasId, event);
    }
  }

  @override
  Future<void> disconnect(String canvasId) => _inner.disconnect(canvasId);

  @override
  Stream<Map<String, CursorPresenceData>> cursorStream(String canvasId) =>
      _inner.cursorStream(canvasId);

  @override
  Future<void> broadcastCursor(String canvasId, CursorPresenceData cursor) =>
      _inner.broadcastCursor(canvasId, cursor);
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. CONNECTION QUALITY — Latency/jitter measurement
// ─────────────────────────────────────────────────────────────────────────────

/// Connection quality tiers.
enum ConnectionQuality {
  /// < 50ms latency, < 20ms jitter
  excellent,

  /// < 150ms latency, < 50ms jitter
  good,

  /// < 500ms latency, < 150ms jitter
  fair,

  /// > 500ms latency or > 150ms jitter
  poor,
}

/// Measures real-time connection quality by tracking event round-trip times.
class ConnectionQualityMonitor {
  /// Current quality assessment.
  final ValueNotifier<ConnectionQuality> quality = ValueNotifier(
    ConnectionQuality.good,
  );

  /// Current latency in milliseconds.
  final ValueNotifier<int> latencyMs = ValueNotifier(0);

  /// Current jitter in milliseconds.
  final ValueNotifier<int> jitterMs = ValueNotifier(0);

  /// Rolling window of latency samples.
  final List<int> _samples = [];

  /// Max samples to keep.
  static const _maxSamples = 20;

  /// Record a latency sample (call on every received event).
  ///
  /// Typical usage: `monitor.recordSample(now - event.timestamp)`.
  void recordSample(int latency) {
    // Clamp negative values (clock drift)
    final sample = latency.clamp(0, 10000);
    _samples.add(sample);
    if (_samples.length > _maxSamples) {
      _samples.removeAt(0);
    }
    _recalculate();
  }

  /// Record from an event timestamp.
  void recordFromEvent(CanvasRealtimeEvent event) {
    final now = DateTime.now().millisecondsSinceEpoch;
    recordSample(now - event.timestamp);
  }

  void _recalculate() {
    if (_samples.isEmpty) return;

    // Average latency
    final avg = _samples.reduce((a, b) => a + b) ~/ _samples.length;
    latencyMs.value = avg;

    // Jitter: standard deviation of latency
    if (_samples.length > 1) {
      final variance =
          _samples.map((s) => (s - avg) * (s - avg)).reduce((a, b) => a + b) /
          _samples.length;
      jitterMs.value = sqrt(variance).toInt();
    }

    // Update quality tier
    if (avg < 50 && jitterMs.value < 20) {
      quality.value = ConnectionQuality.excellent;
    } else if (avg < 150 && jitterMs.value < 50) {
      quality.value = ConnectionQuality.good;
    } else if (avg < 500 && jitterMs.value < 150) {
      quality.value = ConnectionQuality.fair;
    } else {
      quality.value = ConnectionQuality.poor;
    }
  }

  /// Reset all samples.
  void reset() {
    _samples.clear();
    latencyMs.value = 0;
    jitterMs.value = 0;
    quality.value = ConnectionQuality.good;
  }

  void dispose() {
    quality.dispose();
    latencyMs.dispose();
    jitterMs.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. BANDWIDTH ADAPTIVE — Reduce frequency on slow connections
// ─────────────────────────────────────────────────────────────────────────────

/// Dynamically adjusts broadcasting parameters based on connection quality.
class BandwidthAdaptiveConfig {
  final ConnectionQualityMonitor _monitor;

  BandwidthAdaptiveConfig(this._monitor);

  /// Max cursor updates per second (adaptive).
  int get cursorUpdatesPerSecond {
    switch (_monitor.quality.value) {
      case ConnectionQuality.excellent:
        return 20; // 50ms throttle (default)
      case ConnectionQuality.good:
        return 15; // ~67ms throttle
      case ConnectionQuality.fair:
        return 8; // 125ms throttle
      case ConnectionQuality.poor:
        return 4; // 250ms throttle
    }
  }

  /// Cursor throttle interval in ms.
  int get cursorThrottleMs => 1000 ~/ cursorUpdatesPerSecond;

  /// Max stroke streaming points per batch (adaptive).
  int get maxPointsPerStreamBatch {
    switch (_monitor.quality.value) {
      case ConnectionQuality.excellent:
        return 50;
      case ConnectionQuality.good:
        return 30;
      case ConnectionQuality.fair:
        return 15;
      case ConnectionQuality.poor:
        return 5;
    }
  }

  /// Whether to stream stroke points at all (disable on very poor).
  bool get enableStrokeStreaming =>
      _monitor.quality.value != ConnectionQuality.poor;

  /// Event batch window (adaptive — longer on slow connections).
  int get batchWindowMs {
    switch (_monitor.quality.value) {
      case ConnectionQuality.excellent:
        return 100;
      case ConnectionQuality.good:
        return 150;
      case ConnectionQuality.fair:
        return 300;
      case ConnectionQuality.poor:
        return 500;
    }
  }

  /// Max events per second (rate limit — adaptive).
  int get maxEventsPerSecond {
    switch (_monitor.quality.value) {
      case ConnectionQuality.excellent:
        return 60;
      case ConnectionQuality.good:
        return 40;
      case ConnectionQuality.fair:
        return 20;
      case ConnectionQuality.poor:
        return 10;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 6. UNDO/REDO BROADCAST — Remote undo visibility
// ─────────────────────────────────────────────────────────────────────────────

/// Undo/redo operation event data.
class UndoRedoEvent {
  /// Whether this is an undo (true) or redo (false).
  final bool isUndo;

  /// User who performed the operation.
  final String userId;

  /// The event that was undone/redone (for remote replay).
  final CanvasRealtimeEvent? affectedEvent;

  /// Number of steps undone/redone.
  final int stepCount;

  /// Timestamp of the operation.
  final int timestamp;

  const UndoRedoEvent({
    required this.isUndo,
    required this.userId,
    this.affectedEvent,
    this.stepCount = 1,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'isUndo': isUndo,
    'userId': userId,
    'stepCount': stepCount,
    'timestamp': timestamp,
    if (affectedEvent != null) 'affectedEvent': affectedEvent!.toJson(),
  };

  factory UndoRedoEvent.fromJson(Map<String, dynamic> json) {
    return UndoRedoEvent(
      isUndo: json['isUndo'] as bool? ?? true,
      userId: json['userId'] as String,
      stepCount: json['stepCount'] as int? ?? 1,
      timestamp: json['timestamp'] as int? ?? 0,
      affectedEvent:
          json['affectedEvent'] != null
              ? CanvasRealtimeEvent.fromJson(
                json['affectedEvent'] as Map<String, dynamic>,
              )
              : null,
    );
  }
}

/// Extension on [NebulaRealtimeEngine] to add undo/redo broadcasting.
///
/// Usage:
/// ```dart
/// final undoManager = UndoRedoBroadcastManager(engine);
/// undoManager.broadcastUndo(affectedEvent: lastEvent);
/// undoManager.incomingUndoRedos.listen((event) {
///   // Apply remote undo/redo to canvas
/// });
/// ```
class UndoRedoBroadcastManager {
  final NebulaRealtimeEngine _engine;
  final String _localUserId;

  /// Stream of incoming undo/redo operations from remote users.
  Stream<UndoRedoEvent> get incomingUndoRedos => _controller.stream;
  final _controller = StreamController<UndoRedoEvent>.broadcast();

  StreamSubscription<CanvasRealtimeEvent>? _subscription;

  UndoRedoBroadcastManager({
    required NebulaRealtimeEngine engine,
    required String localUserId,
  }) : _engine = engine,
       _localUserId = localUserId {
    // Listen for undo/redo events in the incoming stream
    _subscription = _engine.incomingEvents.listen((event) {
      if (event.type == RealtimeEventType.canvasSettingsChanged &&
          event.payload.containsKey('_undoRedo')) {
        final undoRedo = UndoRedoEvent.fromJson(
          event.payload['_undoRedo'] as Map<String, dynamic>,
        );
        _controller.add(undoRedo);
      }
    });
  }

  /// Broadcast an undo operation to collaborators.
  void broadcastUndo({CanvasRealtimeEvent? affectedEvent, int stepCount = 1}) {
    _broadcastUndoRedo(
      isUndo: true,
      affectedEvent: affectedEvent,
      stepCount: stepCount,
    );
  }

  /// Broadcast a redo operation to collaborators.
  void broadcastRedo({CanvasRealtimeEvent? affectedEvent, int stepCount = 1}) {
    _broadcastUndoRedo(
      isUndo: false,
      affectedEvent: affectedEvent,
      stepCount: stepCount,
    );
  }

  void _broadcastUndoRedo({
    required bool isUndo,
    CanvasRealtimeEvent? affectedEvent,
    int stepCount = 1,
  }) {
    final undoRedoData = UndoRedoEvent(
      isUndo: isUndo,
      userId: _localUserId,
      affectedEvent: affectedEvent,
      stepCount: stepCount,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    _engine.broadcastEvent(
      CanvasRealtimeEvent(
        type: RealtimeEventType.canvasSettingsChanged,
        senderId: _localUserId,
        payload: {'_undoRedo': undoRedoData.toJson()},
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  void dispose() {
    _subscription?.cancel();
    _controller.close();
  }
}
