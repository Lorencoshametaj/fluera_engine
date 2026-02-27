import 'dart:async';
import 'package:flutter/foundation.dart';
import 'realtime_enterprise.dart';
import 'conflict_resolution.dart';

// =============================================================================
// 🔴 REAL-TIME COLLABORATION — Backend-Agnostic Adapter + Engine
//
// This module provides the infrastructure for live multi-user canvas editing.
// It follows the same adapter pattern as FlueraCloudStorageAdapter — the host
// app implements a concrete adapter (Supabase Realtime, Firebase RTDB,
// WebSocket, etc.) and the engine handles orchestration.
// =============================================================================

// ─── Event Types ─────────────────────────────────────────────────────────────

/// Types of real-time canvas events broadcast between collaborators.
enum RealtimeEventType {
  /// A completed stroke was added to the canvas.
  strokeAdded,

  /// A stroke was removed (erased).
  strokeRemoved,

  /// An image was added to the canvas.
  imageAdded,

  /// An image was moved, resized, or rotated.
  imageUpdated,

  /// An image was removed from the canvas.
  imageRemoved,

  /// A text element was created or changed.
  textChanged,

  /// A text element was removed.
  textRemoved,

  /// An element is being actively edited (lock it for others).
  elementLocked,

  /// An element was released from active editing.
  elementUnlocked,

  /// Layer visibility, order, or name changed.
  layerChanged,

  /// Canvas-level settings changed (background, paper type, etc).
  canvasSettingsChanged,

  /// 🎨 Live stroke streaming — partial points during active drawing.
  /// Payload: `{ 'strokeId': '...', 'points': [...new points...], 'penType': '...', 'color': 0xFF... }`
  strokePointsStreamed,

  /// 📄 A PDF document is being uploaded — show placeholder on remote devices.
  /// Payload: `{ 'documentId': '...', 'pageCount': N, 'pageWidth': w, 'pageHeight': h, 'positionX': x, 'positionY': y }`
  pdfLoading,

  /// 📄 Upload progress for a PDF being transferred.
  /// Payload: `{ 'documentId': '...', 'progress': 0.0-1.0 }`
  pdfProgress,

  /// 📄 PDF loading failed — remove placeholder on remote devices.
  /// Payload: `{ 'documentId': '...' }`
  pdfLoadingFailed,

  /// 📄 A PDF document was added to the canvas.
  /// Payload: `{ 'documentId': '...', 'fileName': '...', 'pageCount': N, 'position': [x, y], ... }`
  pdfAdded,

  /// 📄 A blank PDF document was created on the canvas.
  /// Payload: `{ 'documentId': '...', 'pageCount': N, 'pageWidth': w, 'pageHeight': h, 'background': '...', ... }`
  pdfBlankCreated,

  /// 📄 A PDF document was updated (page move, rotate, reorder, delete, etc.).
  /// Payload: `{ 'documentId': '...', 'subAction': '...', ...data }`
  pdfUpdated,

  /// 📄 A PDF document was removed from the canvas entirely.
  /// Payload: `{ 'documentId': '...' }`
  pdfRemoved,

  /// 🎤 A voice recording was added to the canvas.
  /// Payload: `{ 'recordingId': '...', 'audioAssetKey': '...', 'noteTitle': '...', 'durationMs': N, 'recordingType': '...' }`
  recordingAdded,

  /// 🎤 A voice recording was removed from the canvas.
  /// Payload: `{ 'recordingId': '...', 'audioPath': '...' }`
  recordingRemoved,

  /// 🎤 A voice recording was renamed.
  /// Payload: `{ 'recordingId': '...', 'newTitle': '...' }`
  recordingRenamed,

  /// 📌 A recording pin was added to the canvas.
  /// Payload: RecordingPin.toJson()
  recordingPinAdded,

  /// 📌 A recording pin was removed from the canvas.
  /// Payload: `{ 'id': '...' }`
  recordingPinRemoved,
}

// ─── Data Classes ────────────────────────────────────────────────────────────

/// A single real-time canvas event.
///
/// Events are broadcast to all connected users on the same canvas.
/// The [senderId] allows filtering out self-echoes.
class CanvasRealtimeEvent {
  /// Event type.
  final RealtimeEventType type;

  /// ID of the user who sent this event.
  final String senderId;

  /// Optional element ID (stroke, image, text, layer...).
  final String? elementId;

  /// Serialized payload — depends on [type].
  ///
  /// • `strokeAdded` → full stroke JSON
  /// • `strokeRemoved` → `{ 'strokeId': '...' }`
  /// • `imageAdded/Updated` → full image element JSON
  /// • `textChanged` → full text element JSON
  /// • `elementLocked/Unlocked` → `{ 'elementId': '...' }`
  /// • `layerChanged` → layer JSON
  /// • `canvasSettingsChanged` → settings map
  final Map<String, dynamic> payload;

  /// Epoch millis (sender's clock).
  final int timestamp;

  const CanvasRealtimeEvent({
    required this.type,
    required this.senderId,
    this.elementId,
    required this.payload,
    required this.timestamp,
  });

  /// Serialize for network transport.
  Map<String, dynamic> toJson() => {
    'type': type.name,
    'senderId': senderId,
    if (elementId != null) 'elementId': elementId,
    'payload': payload,
    'timestamp': timestamp,
  };

  /// Deserialize from network transport.
  factory CanvasRealtimeEvent.fromJson(Map<String, dynamic> json) {
    return CanvasRealtimeEvent(
      type: RealtimeEventType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => RealtimeEventType.canvasSettingsChanged,
      ),
      senderId: json['senderId'] as String,
      elementId: json['elementId'] as String?,
      payload: Map<String, dynamic>.from(json['payload'] as Map? ?? {}),
      timestamp: json['timestamp'] as int? ?? 0,
    );
  }
}

/// Cursor presence data — high frequency, separate from events.
///
/// Broadcast on a dedicated channel to avoid flooding the event stream.
class CursorPresenceData {
  /// User identifier.
  final String userId;

  /// Display name shown on the cursor label.
  final String displayName;

  /// Cursor color (unique per user).
  final int cursorColor;

  /// Canvas-space cursor position.
  final double x;
  final double y;

  /// Whether the user is actively drawing.
  final bool isDrawing;

  /// Whether the user is typing.
  final bool isTyping;

  /// Whether the user is actively recording audio.
  final bool isRecording;

  /// Whether the user is listening to a recording.
  final bool isListening;

  /// Current pen type (e.g. 'pencil', 'fountainPen', 'marker').
  final String? penType;

  /// Current pen color (ARGB integer).
  final int? penColor;

  /// Viewport info for follow mode.
  final double? viewportX;
  final double? viewportY;
  final double? viewportScale;

  const CursorPresenceData({
    required this.userId,
    required this.displayName,
    required this.cursorColor,
    required this.x,
    required this.y,
    this.isDrawing = false,
    this.isTyping = false,
    this.isRecording = false,
    this.isListening = false,
    this.penType,
    this.penColor,
    this.viewportX,
    this.viewportY,
    this.viewportScale,
  });

  /// Compact JSON for network (use short keys to reduce bandwidth).
  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'd': isDrawing,
    't': isTyping,
    if (isRecording) 'r': true,
    if (isListening) 'l': true,
    'n': displayName,
    'c': cursorColor,
    if (penType != null) 'pt': penType,
    if (penColor != null) 'pc': penColor,
    if (viewportX != null) 'vx': viewportX,
    if (viewportY != null) 'vy': viewportY,
    if (viewportScale != null) 'vs': viewportScale,
  };

  /// Deserialize (compact keys with legacy fallback).
  factory CursorPresenceData.fromJson(
    String userId,
    Map<String, dynamic> json,
  ) {
    return CursorPresenceData(
      userId: userId,
      displayName: (json['n'] ?? json['displayName']) as String? ?? 'User',
      cursorColor: (json['c'] ?? json['cursorColor']) as int? ?? 0xFF42A5F5,
      x: (json['x'] as num?)?.toDouble() ?? 0.0,
      y: (json['y'] as num?)?.toDouble() ?? 0.0,
      isDrawing: (json['d'] ?? json['isDrawing']) as bool? ?? false,
      isTyping: (json['t'] ?? json['isTyping']) as bool? ?? false,
      isRecording: (json['r'] ?? json['isRecording']) as bool? ?? false,
      isListening: (json['l'] ?? json['isListening']) as bool? ?? false,
      penType: (json['pt'] ?? json['penType']) as String?,
      penColor: (json['pc'] ?? json['penColor']) as int?,
      viewportX: (json['vx'] as num?)?.toDouble(),
      viewportY: (json['vy'] as num?)?.toDouble(),
      viewportScale: (json['vs'] as num?)?.toDouble(),
    );
  }
}

// ─── Connection State ────────────────────────────────────────────────────────

/// Connection state of the real-time engine.
enum RealtimeConnectionState {
  /// Not connected to any canvas channel.
  disconnected,

  /// Connecting to the backend.
  connecting,

  /// Live and receiving events.
  connected,

  /// Lost connection, attempting to reconnect.
  reconnecting,

  /// Permanently failed (auth error, etc).
  error,
}

// =============================================================================
// 🔌 ABSTRACT ADAPTER — Implemented by host app
// =============================================================================

/// Backend-agnostic real-time collaboration adapter.
///
/// The host app implements this interface using their real-time backend:
/// - **Supabase Realtime** (Broadcast channels)
/// - **Firebase Realtime Database** (onValue / child_added)
/// - **WebSocket** (custom server)
/// - **Ably / Pusher** (managed WebSocket service)
///
/// **Example (Supabase Realtime):**
/// ```dart
/// class SupabaseRealtimeAdapter implements FlueraRealtimeAdapter {
///   final SupabaseClient supabase;
///   RealtimeChannel? _channel;
///
///   @override
///   Stream<CanvasRealtimeEvent> subscribe(String canvasId) {
///     _channel = supabase.channel('canvas:$canvasId');
///     final controller = StreamController<CanvasRealtimeEvent>();
///     _channel!.onBroadcast(
///       event: 'canvas_event',
///       callback: (payload) {
///         controller.add(CanvasRealtimeEvent.fromJson(payload));
///       },
///     ).subscribe();
///     return controller.stream;
///   }
///
///   @override
///   Future<void> broadcast(String canvasId, CanvasRealtimeEvent event) async {
///     _channel?.sendBroadcastMessage(
///       event: 'canvas_event',
///       payload: event.toJson(),
///     );
///   }
/// }
/// ```
abstract class FlueraRealtimeAdapter {
  /// Subscribe to real-time canvas events from other collaborators.
  ///
  /// The stream emits events broadcast by all users on the same canvas.
  /// The engine filters out self-echoes via [CanvasRealtimeEvent.senderId].
  Stream<CanvasRealtimeEvent> subscribe(String canvasId);

  /// Broadcast a local canvas event to all collaborators.
  Future<void> broadcast(String canvasId, CanvasRealtimeEvent event);

  /// Disconnect from the canvas channel.
  Future<void> disconnect(String canvasId);

  /// Subscribe to cursor presence updates from other collaborators.
  ///
  /// High-frequency channel — separate from events to avoid flooding.
  /// Returns a map of userId → cursor data, updated on each cursor move.
  Stream<Map<String, CursorPresenceData>> cursorStream(String canvasId);

  /// Broadcast local cursor position to all collaborators.
  ///
  /// The engine throttles this (50ms) — the adapter should not add
  /// additional throttling.
  Future<void> broadcastCursor(String canvasId, CursorPresenceData cursor);
}

// =============================================================================
// ⚙️ FLUERA REALTIME ENGINE — Internal orchestrator
//
// Manages:
//   • Subscription lifecycle (connect, reconnect, dispose)
//   • Event dispatch (incoming → canvas state)
//   • Cursor throttle (50ms batching)
//   • Element locking (pessimistic lock table)
//   • Conflict detection (timestamp-based)
//   • Outgoing event queue (batch multiple rapid events)
// =============================================================================

class FlueraRealtimeEngine {
  final FlueraRealtimeAdapter _adapter;
  final String _localUserId;

  /// Observable connection state.
  final ValueNotifier<RealtimeConnectionState> connectionState = ValueNotifier(
    RealtimeConnectionState.disconnected,
  );

  /// Remote cursors — the key is userId, value is cursor data.
  /// This is consumed directly by `CanvasPresenceOverlay`.
  final ValueNotifier<Map<String, Map<String, dynamic>>> remoteCursors =
      ValueNotifier({});

  /// Locked elements — maps elementId → userId who locked it.
  final ValueNotifier<Map<String, String>> lockedElements = ValueNotifier({});

  /// Stream of incoming canvas events (filtered: no self-echoes).
  /// The canvas screen subscribes to this.
  Stream<CanvasRealtimeEvent> get incomingEvents => _incomingController.stream;
  final _incomingController = StreamController<CanvasRealtimeEvent>.broadcast();

  /// ⭐ CRDT: Vector clock for causal ordering.
  late final VectorClockManager vectorClock;

  /// ⭐ Session audit log (compliance / debugging).
  final SessionAuditLog auditLog = SessionAuditLog();

  /// ⭐ Connection quality monitor (latency / jitter).
  final ConnectionQualityMonitor connectionQuality = ConnectionQualityMonitor();

  /// 🔀 Conflict resolver with pluggable strategy chain.
  late final ConflictResolver conflictResolver;

  /// 🔀 Element state tracker for conflict detection.
  final ElementStateTracker elementStateTracker = ElementStateTracker();

  // ─── Internal state ─────────────────────────────────────────────────

  String? _activeCanvasId;
  StreamSubscription<CanvasRealtimeEvent>? _eventSubscription;
  StreamSubscription<Map<String, CursorPresenceData>>? _cursorSubscription;
  Timer? _cursorBroadcastTimer;
  CursorPresenceData? _pendingCursorBroadcast;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _disposed = false;

  // 📦 Event batching
  final List<CanvasRealtimeEvent> _eventBatch = [];
  Timer? _batchFlushTimer;

  // 📴 Offline event queue
  final List<CanvasRealtimeEvent> _offlineQueue = [];

  // 💓 Heartbeat / stale cursor cleanup
  Timer? _heartbeatTimer;
  final Map<String, int> _lastCursorTimestamps = {};

  // 🚦 Rate limiting (token bucket)
  int _rateBucketTokens = _maxTokensPerSecond;
  Timer? _rateBucketRefillTimer;

  /// Cursor broadcast throttle (50ms = 20 updates/second max).
  static const _cursorThrottleMs = 50;

  /// Max reconnect attempts before giving up.
  static const _maxReconnectAttempts = 10;

  /// Backoff multiplier for reconnection (capped at 30s).
  static const _baseReconnectDelayMs = 1000;

  /// Event batch window (100ms) — groups rapid events.
  static const _batchWindowMs = 100;

  /// Stale cursor timeout (10 seconds).
  static const _staleCursorTimeoutMs = 10000;

  /// Heartbeat interval (5 seconds).
  static const _heartbeatIntervalMs = 5000;

  /// Rate limit: max events per second.
  static const _maxTokensPerSecond = 60;

  /// Max offline queue size.
  static const _maxOfflineQueueSize = 200;

  FlueraRealtimeEngine({
    required FlueraRealtimeAdapter adapter,
    required String localUserId,
    ConflictResolver? conflictResolver,
  }) : _adapter = adapter,
       _localUserId = localUserId {
    vectorClock = VectorClockManager(localUserId);
    this.conflictResolver = conflictResolver ?? ConflictResolver();
  }

  /// Expose local user ID for external modules.
  String get localUserId => _localUserId;

  // ─── Connection Lifecycle ───────────────────────────────────────────

  /// Connect to a canvas channel and start receiving events.
  Future<void> connect(String canvasId) async {
    if (_disposed) return;
    _activeCanvasId = canvasId;
    connectionState.value = RealtimeConnectionState.connecting;

    try {
      // 1. Subscribe to canvas events
      final eventStream = _adapter.subscribe(canvasId);
      _eventSubscription = eventStream.listen(
        _onRemoteEvent,
        onError: _onStreamError,
        onDone: _onStreamDone,
      );

      // 2. Subscribe to cursor presence
      final cursorStream = _adapter.cursorStream(canvasId);
      _cursorSubscription = cursorStream.listen(
        _onCursorUpdate,
        onError: (_) {}, // Non-fatal: cursors are best-effort
      );

      connectionState.value = RealtimeConnectionState.connected;
      _reconnectAttempts = 0;

      // 💓 Start heartbeat for stale cursor cleanup
      _startHeartbeat();

      // 🚦 Start rate limiter
      _startRateLimiter();

      // 📴 Replay offline queue
      _replayOfflineQueue();

      // ⭐ Audit: log session join
      auditLog.logSession(_localUserId, true);

      debugPrint('🔴 Realtime connected to canvas: $canvasId');
    } catch (e) {
      debugPrint('🔴 Realtime connection failed: $e');
      connectionState.value = RealtimeConnectionState.error;
      _scheduleReconnect();
    }
  }

  /// Disconnect from the current canvas channel.
  Future<void> disconnect() async {
    final canvasId = _activeCanvasId;
    if (canvasId == null) return;

    _reconnectTimer?.cancel();
    _cursorBroadcastTimer?.cancel();
    _heartbeatTimer?.cancel();
    _rateBucketRefillTimer?.cancel();
    _batchFlushTimer?.cancel();
    await _eventSubscription?.cancel();
    await _cursorSubscription?.cancel();
    _eventSubscription = null;
    _cursorSubscription = null;

    // Clear remote state
    remoteCursors.value = {};
    lockedElements.value = {};
    _lastCursorTimestamps.clear();

    try {
      await _adapter.disconnect(canvasId);
    } catch (_) {}

    _activeCanvasId = null;
    connectionState.value = RealtimeConnectionState.disconnected;

    // ⭐ Audit: log session leave
    auditLog.logSession(_localUserId, false);

    debugPrint('🔴 Realtime disconnected from canvas: $canvasId');
  }

  // ─── Broadcasting (outgoing) ────────────────────────────────────────

  /// Broadcast a canvas event to all collaborators.
  ///
  /// If offline, queues the event for replay on reconnect.
  /// Rate-limited to [_maxTokensPerSecond] events/sec.
  Future<void> broadcastEvent(CanvasRealtimeEvent event) async {
    final canvasId = _activeCanvasId;
    if (canvasId == null) return;

    // 📴 Queue if offline
    if (connectionState.value != RealtimeConnectionState.connected) {
      _enqueueOffline(event);
      return;
    }

    // 🚦 Rate limit check
    if (_rateBucketTokens <= 0) {
      _enqueueOffline(event);
      debugPrint('🔴 Rate limited — event queued');
      return;
    }
    _rateBucketTokens--;

    // ⭐ CRDT: tick vector clock before sending
    vectorClock.tick();

    // 🔀 Track local modifications for conflict detection
    if (event.elementId != null) {
      elementStateTracker.markLocallyModified(event.elementId!, event);
    }

    try {
      await _adapter.broadcast(canvasId, event);
    } catch (e) {
      debugPrint('🔴 Broadcast failed: $e');
      _enqueueOffline(event);
    }
  }

  /// Broadcast a completed stroke to all collaborators.
  void broadcastStroke(Map<String, dynamic> strokeJson) {
    broadcastEvent(
      CanvasRealtimeEvent(
        type: RealtimeEventType.strokeAdded,
        senderId: _localUserId,
        elementId: strokeJson['id'] as String?,
        payload: strokeJson,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// Broadcast a stroke removal (eraser).
  void broadcastStrokeRemoved(String strokeId) {
    broadcastEvent(
      CanvasRealtimeEvent(
        type: RealtimeEventType.strokeRemoved,
        senderId: _localUserId,
        elementId: strokeId,
        payload: {'strokeId': strokeId},
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// Broadcast an image addition or update.
  void broadcastImageUpdate(
    Map<String, dynamic> imageJson, {
    bool isNew = false,
  }) {
    broadcastEvent(
      CanvasRealtimeEvent(
        type:
            isNew
                ? RealtimeEventType.imageAdded
                : RealtimeEventType.imageUpdated,
        senderId: _localUserId,
        elementId: imageJson['id'] as String?,
        payload: imageJson,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// Broadcast an image removal to all collaborators.
  void broadcastImageRemoved(String imageId) {
    broadcastEvent(
      CanvasRealtimeEvent(
        type: RealtimeEventType.imageRemoved,
        senderId: _localUserId,
        elementId: imageId,
        payload: {'id': imageId},
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    debugPrint('[RT] 🖼️ Broadcast imageRemoved: $imageId');
  }

  /// Broadcast a text element change.
  void broadcastTextChange(Map<String, dynamic> textJson) {
    broadcastEvent(
      CanvasRealtimeEvent(
        type: RealtimeEventType.textChanged,
        senderId: _localUserId,
        elementId: textJson['id'] as String?,
        payload: textJson,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// 📄 Broadcast that a PDF upload is starting — remote devices show placeholder.
  void broadcastPdfLoading({
    required String documentId,
    required int pageCount,
    required double pageWidth,
    required double pageHeight,
    required double positionX,
    required double positionY,
    String? fileName,
    String? thumbnailBase64,
  }) {
    broadcastEvent(
      CanvasRealtimeEvent(
        type: RealtimeEventType.pdfLoading,
        senderId: _localUserId,
        elementId: documentId,
        payload: {
          'documentId': documentId,
          'pageCount': pageCount,
          'pageWidth': pageWidth,
          'pageHeight': pageHeight,
          'positionX': positionX,
          'positionY': positionY,
          if (fileName != null) 'fileName': fileName,
          if (thumbnailBase64 != null) 'thumbnail': thumbnailBase64,
        },
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// 📄 Broadcast PDF upload progress (0.0 - 1.0).
  void broadcastPdfProgress({
    required String documentId,
    required double progress,
  }) {
    broadcastEvent(
      CanvasRealtimeEvent(
        type: RealtimeEventType.pdfProgress,
        senderId: _localUserId,
        elementId: documentId,
        payload: {'documentId': documentId, 'progress': progress},
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// 📄 Broadcast that a PDF loading has failed — remove placeholder.
  void broadcastPdfLoadingFailed({required String documentId}) {
    broadcastEvent(
      CanvasRealtimeEvent(
        type: RealtimeEventType.pdfLoadingFailed,
        senderId: _localUserId,
        elementId: documentId,
        payload: {'documentId': documentId},
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// 📄 Broadcast a PDF document addition to all collaborators.
  ///
  /// If [pdfBytesBase64] is provided, the raw PDF bytes are embedded
  /// in the payload as a fallback when cloud storage upload fails.
  void broadcastPdfAdded({
    required String documentId,
    String? fileName,
    required int pageCount,
    required double positionX,
    required double positionY,
    String? pdfBytesBase64,
    int gridColumns = 1,
  }) {
    broadcastEvent(
      CanvasRealtimeEvent(
        type: RealtimeEventType.pdfAdded,
        senderId: _localUserId,
        elementId: documentId,
        payload: {
          'documentId': documentId,
          'fileName': fileName,
          'pageCount': pageCount,
          'positionX': positionX,
          'positionY': positionY,
          'gridColumns': gridColumns,
          if (pdfBytesBase64 != null) 'pdfBytesBase64': pdfBytesBase64,
        },
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// 📄 Broadcast a blank PDF document creation to all collaborators.
  void broadcastPdfBlankCreated({
    required String documentId,
    String? fileName,
    required int pageCount,
    required double pageWidth,
    required double pageHeight,
    required String background,
    required double positionX,
    required double positionY,
  }) {
    broadcastEvent(
      CanvasRealtimeEvent(
        type: RealtimeEventType.pdfBlankCreated,
        senderId: _localUserId,
        elementId: documentId,
        payload: {
          'documentId': documentId,
          'fileName': fileName,
          'pageCount': pageCount,
          'pageWidth': pageWidth,
          'pageHeight': pageHeight,
          'background': background,
          'positionX': positionX,
          'positionY': positionY,
        },
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// 📄 Broadcast a generic PDF operation to all collaborators.
  ///
  /// [subAction] identifies the operation (e.g. 'pageMoved', 'pageRotated').
  /// [data] contains action-specific parameters merged into the payload.
  void broadcastPdfUpdated({
    required String documentId,
    required String subAction,
    Map<String, dynamic> data = const {},
  }) {
    final payload = <String, dynamic>{
      'documentId': documentId,
      'subAction': subAction,
      ...data,
    };
    broadcastEvent(
      CanvasRealtimeEvent(
        type: RealtimeEventType.pdfUpdated,
        senderId: _localUserId,
        elementId: documentId,
        payload: payload,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    debugPrint('[RT] 📄 Broadcast pdfUpdated.$subAction: $documentId');
  }

  /// 📄 Broadcast that a PDF document was removed from the canvas.
  void broadcastPdfRemoved({required String documentId}) {
    broadcastEvent(
      CanvasRealtimeEvent(
        type: RealtimeEventType.pdfRemoved,
        senderId: _localUserId,
        elementId: documentId,
        payload: {'documentId': documentId},
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    debugPrint('[RT] 📄 Broadcast pdfRemoved: $documentId');
  }

  // ─── Recording Sync ─────────────────────────────────────────────────

  /// 🎤 Broadcast that a new voice recording was added to the canvas.
  void broadcastRecordingAdded({
    required String recordingId,
    required String audioAssetKey,
    String? noteTitle,
    required int durationMs,
    String? recordingType,
    String? senderName,
    bool compressed = false,
    List<double>? waveform,
    int? fileSize,
    String? strokesAssetKey,
    int strokeCount = 0,
  }) {
    broadcastEvent(
      CanvasRealtimeEvent(
        type: RealtimeEventType.recordingAdded,
        senderId: _localUserId,
        elementId: recordingId,
        payload: {
          'recordingId': recordingId,
          'audioAssetKey': audioAssetKey,
          'noteTitle': noteTitle,
          'durationMs': durationMs,
          'recordingType': recordingType ?? 'audio_only',
          if (senderName != null) 'senderName': senderName,
          if (compressed) 'compressed': true,
          if (waveform != null) 'waveform': waveform,
          if (fileSize != null) 'fileSize': fileSize,
          if (strokesAssetKey != null) 'strokesAssetKey': strokesAssetKey,
          if (strokeCount > 0) 'strokeCount': strokeCount,
        },
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    debugPrint(
      '[RT] 🎤 Broadcast recordingAdded: $recordingId'
      '${strokesAssetKey != null ? ' ($strokeCount strokes via asset)' : ''}',
    );
  }

  /// 🎤 Broadcast that a voice recording was removed.
  void broadcastRecordingRemoved({
    required String recordingId,
    required String audioPath,
  }) {
    broadcastEvent(
      CanvasRealtimeEvent(
        type: RealtimeEventType.recordingRemoved,
        senderId: _localUserId,
        elementId: recordingId,
        payload: {'recordingId': recordingId, 'audioPath': audioPath},
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    debugPrint('[RT] 🎤 Broadcast recordingRemoved: $recordingId');
  }

  /// 🎤 Broadcast that a voice recording was renamed.
  void broadcastRecordingRenamed({
    required String recordingId,
    required String newTitle,
  }) {
    broadcastEvent(
      CanvasRealtimeEvent(
        type: RealtimeEventType.recordingRenamed,
        senderId: _localUserId,
        elementId: recordingId,
        payload: {'recordingId': recordingId, 'newTitle': newTitle},
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    debugPrint('[RT] 🎤 Broadcast recordingRenamed: $recordingId → $newTitle');
  }

  /// 📌 Broadcast a recording pin addition to all collaborators.
  void broadcastRecordingPinAdded(Map<String, dynamic> pinJson) {
    broadcastEvent(
      CanvasRealtimeEvent(
        type: RealtimeEventType.recordingPinAdded,
        senderId: _localUserId,
        elementId: pinJson['id'] as String?,
        payload: pinJson,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    debugPrint('[RT] 📌 Broadcast recordingPinAdded: ${pinJson['id']}');
  }

  /// 📌 Broadcast a recording pin removal to all collaborators.
  void broadcastRecordingPinRemoved(String pinId) {
    broadcastEvent(
      CanvasRealtimeEvent(
        type: RealtimeEventType.recordingPinRemoved,
        senderId: _localUserId,
        elementId: pinId,
        payload: {'id': pinId},
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    debugPrint('[RT] 📌 Broadcast recordingPinRemoved: $pinId');
  }

  // ─── Live Stroke Streaming ──────────────────────────────────────────

  /// 🎨 Stream partial stroke points to collaborators during active drawing.
  ///
  /// Call on every pointer move during drawing. The engine batches points
  /// and broadcasts them at 20Hz (same as cursor throttle).
  void streamStrokePoints({
    required String strokeId,
    required List<Map<String, dynamic>> newPoints,
    required String penType,
    required int color,
    double? strokeWidth,
  }) {
    broadcastEvent(
      CanvasRealtimeEvent(
        type: RealtimeEventType.strokePointsStreamed,
        senderId: _localUserId,
        elementId: strokeId,
        payload: {
          'strokeId': strokeId,
          'points': newPoints,
          'penType': penType,
          'color': color,
          if (strokeWidth != null) 'strokeWidth': strokeWidth,
        },
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  // ─── Cursor Presence ────────────────────────────────────────────────

  /// Throttled cursor broadcast — call on every pointer move/draw update.
  ///
  /// Batches to 20 updates/second max to avoid flooding.
  void updateCursor(CursorPresenceData cursor) {
    _pendingCursorBroadcast = cursor;

    // If no timer is active, schedule one immediately
    if (_cursorBroadcastTimer == null || !_cursorBroadcastTimer!.isActive) {
      _cursorBroadcastTimer = Timer(
        const Duration(milliseconds: _cursorThrottleMs),
        _flushCursor,
      );
    }
  }

  void _flushCursor() {
    final cursor = _pendingCursorBroadcast;
    final canvasId = _activeCanvasId;
    if (cursor == null || canvasId == null) return;
    if (connectionState.value != RealtimeConnectionState.connected) return;

    _pendingCursorBroadcast = null;
    _adapter.broadcastCursor(canvasId, cursor).catchError((_) {});
  }

  // ─── Element Locking ────────────────────────────────────────────────

  /// Lock an element (e.g. when user starts dragging an image).
  ///
  /// Returns `false` if the element is already locked by another user.
  bool lockElement(String elementId) {
    final current = lockedElements.value;
    if (current.containsKey(elementId) && current[elementId] != _localUserId) {
      return false; // Already locked by someone else
    }

    lockedElements.value = {...current, elementId: _localUserId};

    broadcastEvent(
      CanvasRealtimeEvent(
        type: RealtimeEventType.elementLocked,
        senderId: _localUserId,
        elementId: elementId,
        payload: {'elementId': elementId, 'userId': _localUserId},
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    return true;
  }

  /// Unlock an element (e.g. when user finishes dragging).
  void unlockElement(String elementId) {
    final current = Map<String, String>.from(lockedElements.value);
    current.remove(elementId);
    lockedElements.value = current;

    broadcastEvent(
      CanvasRealtimeEvent(
        type: RealtimeEventType.elementUnlocked,
        senderId: _localUserId,
        elementId: elementId,
        payload: {'elementId': elementId},
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// Check if an element is locked by another user.
  bool isLockedByOther(String elementId) {
    final lockOwner = lockedElements.value[elementId];
    return lockOwner != null && lockOwner != _localUserId;
  }

  // ─── Incoming Event Handling ────────────────────────────────────────

  void _onRemoteEvent(CanvasRealtimeEvent event) {
    // Filter self-echoes
    if (event.senderId == _localUserId) return;

    // ⭐ Connection quality: measure latency
    connectionQuality.recordFromEvent(event);

    // ⭐ CRDT: merge vector clock if present
    final vclockJson = event.payload['_vclock'] as Map<String, dynamic>?;
    if (vclockJson != null) {
      vectorClock.merge(VectorClock.fromJson(vclockJson));
    }

    // ⭐ Audit: log the event
    auditLog.logEvent(event);

    // 🔀 Conflict detection: check if this element was locally modified
    if (elementStateTracker.hasConflict(event)) {
      final localEvent = elementStateTracker.getLastLocal(event.elementId!);
      if (localEvent != null) {
        // Attempt automatic resolution
        conflictResolver
            .resolveConflict(
              localEvent: localEvent,
              remoteEvent: event,
              localClock: vectorClock.current,
            )
            .then((result) {
              if (result != null) {
                // Apply resolved event instead of raw remote
                if (event.elementId != null) {
                  elementStateTracker.markRemoteApplied(
                    event.elementId!,
                    result.resolvedEvent,
                  );
                }
                _incomingController.add(result.resolvedEvent);
              }
              // If null, conflict is unresolved — onUnresolved callback fired
            });
        return; // Don't apply raw remote event
      }
    }

    // 🔀 Track applied remote event
    if (event.elementId != null) {
      elementStateTracker.markRemoteApplied(event.elementId!, event);
    }

    // Handle lock/unlock events internally
    if (event.type == RealtimeEventType.elementLocked) {
      final elementId = event.payload['elementId'] as String?;
      if (elementId != null) {
        lockedElements.value = {
          ...lockedElements.value,
          elementId: event.senderId,
        };
      }
    } else if (event.type == RealtimeEventType.elementUnlocked) {
      final elementId = event.payload['elementId'] as String?;
      if (elementId != null) {
        final current = Map<String, String>.from(lockedElements.value);
        current.remove(elementId);
        lockedElements.value = current;
      }
    }

    // Forward to canvas screen
    _incomingController.add(event);
  }

  void _onCursorUpdate(Map<String, CursorPresenceData> cursors) {
    // Convert to the format expected by CanvasPresenceOverlay
    final cursorMap = <String, Map<String, dynamic>>{};
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final entry in cursors.entries) {
      // Filter self
      if (entry.key == _localUserId) continue;
      cursorMap[entry.key] = entry.value.toJson();
      // 💓 Track last cursor timestamp for stale detection
      _lastCursorTimestamps[entry.key] = now;
    }
    remoteCursors.value = cursorMap;
  }

  // ─── Reconnection ──────────────────────────────────────────────────

  void _onStreamError(Object error) {
    debugPrint('🔴 Realtime stream error: $error');
    connectionState.value = RealtimeConnectionState.reconnecting;
    _scheduleReconnect();
  }

  void _onStreamDone() {
    if (_disposed) return;
    debugPrint('🔴 Realtime stream closed');
    connectionState.value = RealtimeConnectionState.reconnecting;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('🔴 Realtime: max reconnect attempts reached, giving up');
      connectionState.value = RealtimeConnectionState.error;
      return;
    }

    _reconnectAttempts++;
    final delayMs = (_baseReconnectDelayMs * _reconnectAttempts).clamp(
      1000,
      30000,
    );

    debugPrint(
      '🔴 Realtime: reconnecting in ${delayMs}ms '
      '(attempt $_reconnectAttempts/$_maxReconnectAttempts)',
    );

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      final canvasId = _activeCanvasId;
      if (canvasId != null && !_disposed) {
        connect(canvasId);
      }
    });
  }

  // ─── Event Batching ─────────────────────────────────────────────────

  /// Batch an event — groups multiple rapid events into a single broadcast.
  ///
  /// Use for high-frequency updates like image drag (many moves in 100ms).
  void batchEvent(CanvasRealtimeEvent event) {
    _eventBatch.add(event);

    _batchFlushTimer ??= Timer(
      const Duration(milliseconds: _batchWindowMs),
      _flushBatch,
    );
  }

  void _flushBatch() {
    _batchFlushTimer = null;
    if (_eventBatch.isEmpty) return;

    // Only keep the last event per elementId (deduplicate rapid updates)
    final deduped = <String, CanvasRealtimeEvent>{};
    for (final event in _eventBatch) {
      final key = event.elementId ?? '${event.type.name}_${event.timestamp}';
      deduped[key] = event; // Last one wins
    }
    _eventBatch.clear();

    for (final event in deduped.values) {
      broadcastEvent(event);
    }
  }

  /// Number of events currently queued in the batch.
  int get pendingBatchCount => _eventBatch.length;

  // ─── Offline Event Queue ────────────────────────────────────────────

  void _enqueueOffline(CanvasRealtimeEvent event) {
    if (_offlineQueue.length >= _maxOfflineQueueSize) {
      // Evict oldest to prevent unbounded growth
      _offlineQueue.removeAt(0);
    }
    _offlineQueue.add(event);
  }

  Future<void> _replayOfflineQueue() async {
    if (_offlineQueue.isEmpty) return;

    final toReplay = List<CanvasRealtimeEvent>.from(_offlineQueue);
    _offlineQueue.clear();

    debugPrint('📴 Replaying ${toReplay.length} offline events');

    final canvasId = _activeCanvasId;
    if (canvasId == null) return;

    for (final event in toReplay) {
      try {
        await _adapter.broadcast(canvasId, event);
      } catch (e) {
        debugPrint('📴 Offline replay failed: $e');
        _offlineQueue.add(event); // Re-queue on failure
        break; // Stop replay on first failure
      }
    }
  }

  /// Number of events waiting in the offline queue.
  int get offlineQueueSize => _offlineQueue.length;

  /// Whether there are offline events waiting to be replayed.
  bool get hasOfflineQueue => _offlineQueue.isNotEmpty;

  // ─── Heartbeat / Stale Cursor Cleanup ───────────────────────────────

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(milliseconds: _heartbeatIntervalMs),
      (_) => _cleanupStaleCursors(),
    );
  }

  void _cleanupStaleCursors() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final staleUserIds = <String>[];

    for (final entry in _lastCursorTimestamps.entries) {
      if (now - entry.value > _staleCursorTimeoutMs) {
        staleUserIds.add(entry.key);
      }
    }

    if (staleUserIds.isEmpty) return;

    for (final userId in staleUserIds) {
      _lastCursorTimestamps.remove(userId);
    }

    // Remove stale cursors from the overlay
    final current = Map<String, Map<String, dynamic>>.from(remoteCursors.value);
    for (final userId in staleUserIds) {
      current.remove(userId);
    }
    remoteCursors.value = current;

    // Also clean up locks from stale users
    final locks = Map<String, String>.from(lockedElements.value);
    locks.removeWhere((_, userId) => staleUserIds.contains(userId));
    lockedElements.value = locks;

    debugPrint(
      '💓 Cleaned ${staleUserIds.length} stale cursor(s): '
      '${staleUserIds.join(", ")}',
    );
  }

  // ─── Rate Limiting ──────────────────────────────────────────────────

  void _startRateLimiter() {
    _rateBucketRefillTimer?.cancel();
    _rateBucketTokens = _maxTokensPerSecond;
    _rateBucketRefillTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _rateBucketTokens = _maxTokensPerSecond;
      // Also try to drain offline queue if tokens available
      if (_offlineQueue.isNotEmpty &&
          connectionState.value == RealtimeConnectionState.connected) {
        _replayOfflineQueue();
      }
    });
  }

  /// Current rate limit tokens available.
  int get rateBucketTokens => _rateBucketTokens;

  // ─── Dispose ────────────────────────────────────────────────────────

  /// Clean up all subscriptions and timers.
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _cursorBroadcastTimer?.cancel();
    _heartbeatTimer?.cancel();
    _rateBucketRefillTimer?.cancel();
    _batchFlushTimer?.cancel();
    _eventSubscription?.cancel();
    _cursorSubscription?.cancel();
    _incomingController.close();
    connectionState.dispose();
    remoteCursors.dispose();
    lockedElements.dispose();
    auditLog.dispose();
    connectionQuality.dispose();
  }
}
