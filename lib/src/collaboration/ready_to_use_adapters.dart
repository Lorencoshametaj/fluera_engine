import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../canvas/fluera_canvas_config.dart';
import 'fluera_realtime_adapter.dart';

// =============================================================================
// 🚀 READY-TO-USE COLLABORATION ADAPTERS
//
// Zero-config adapters for testing and demoing live collaboration features
// without a backend (Supabase, Firebase, etc.).
//
// Usage:
// ```dart
// FlueraCanvasConfig(
//   subscriptionTier: FlueraSubscriptionTier.plus,
//   permissions: InMemoryPermissionProvider(),
//   presence: InMemoryPresenceProvider(localUserName: 'Demo User'),
//   realtimeAdapter: InMemoryRealtimeAdapter(),
// )
// ```
// =============================================================================

// ─── In-Memory Realtime Adapter ──────────────────────────────────────────────

/// A fully in-memory [FlueraRealtimeAdapter] for testing and demos.
///
/// All events are broadcast through local [StreamController]s — no network
/// required. The engine's built-in self-echo filter prevents the local user
/// from seeing their own events duplicated.
///
/// **Features:**
/// - Zero configuration — works out of the box
/// - Optional simulated remote user (mirrors local strokes with offset + delay)
/// - Optional artificial latency
///
/// ```dart
/// final adapter = InMemoryRealtimeAdapter(
///   simulateRemoteUser: true,  // See "ghost" drawing on single device
///   latencyMs: 100,            // Simulate 100ms network delay
/// );
/// ```
class InMemoryRealtimeAdapter implements FlueraRealtimeAdapter {
  /// Whether to simulate a phantom remote user that mirrors local strokes.
  final bool simulateRemoteUser;

  /// Simulated network latency in milliseconds (0 = instant).
  final int latencyMs;

  /// Display name for the simulated remote user.
  final String simulatedUserName;

  /// Offset (in canvas points) applied to mirrored strokes.
  final Offset simulatedOffset;

  InMemoryRealtimeAdapter({
    this.simulateRemoteUser = false,
    this.latencyMs = 0,
    this.simulatedUserName = 'Remote User',
    this.simulatedOffset = const Offset(80, 40),
  });

  // Internal streams
  final _eventController = StreamController<CanvasRealtimeEvent>.broadcast();
  final _cursorController =
      StreamController<Map<String, CursorPresenceData>>.broadcast();

  String? _activeCanvasId;
  Timer? _simulatedCursorTimer;
  final _random = Random();

  /// Unique ID for the simulated remote user.
  static const _simulatedUserId = '_simulated_remote_user';

  @override
  Stream<CanvasRealtimeEvent> subscribe(String canvasId) {
    _activeCanvasId = canvasId;
    return _eventController.stream;
  }

  @override
  Future<void> broadcast(String canvasId, CanvasRealtimeEvent event) async {
    if (_eventController.isClosed) return;

    // Apply optional latency
    if (latencyMs > 0) {
      await Future.delayed(Duration(milliseconds: latencyMs));
    }

    // Re-broadcast through the stream (engine filters self-echoes)
    _eventController.add(event);

    // Simulate a remote user mirroring the stroke with offset
    if (simulateRemoteUser) {
      _mirrorEventAsRemote(event);
    }
  }

  @override
  Future<void> disconnect(String canvasId) async {
    _activeCanvasId = null;
    _simulatedCursorTimer?.cancel();
    _simulatedCursorTimer = null;
  }

  @override
  Stream<Map<String, CursorPresenceData>> cursorStream(String canvasId) {
    // Start simulated cursor if enabled
    if (simulateRemoteUser) {
      _startSimulatedCursor();
    }
    return _cursorController.stream;
  }

  @override
  Future<void> broadcastCursor(
    String canvasId,
    CursorPresenceData cursor,
  ) async {
    if (_cursorController.isClosed) return;

    // If simulating, also emit a mirrored cursor
    if (simulateRemoteUser) {
      _cursorController.add({
        _simulatedUserId: CursorPresenceData(
          userId: _simulatedUserId,
          displayName: simulatedUserName,
          cursorColor: 0xFFFF6B6B,
          x: cursor.x + simulatedOffset.dx,
          y: cursor.y + simulatedOffset.dy,
          isDrawing: cursor.isDrawing,
          isTyping: cursor.isTyping,
          penType: cursor.penType,
          penColor: cursor.penColor,
        ),
      });
    }
  }

  /// Inject a synthetic remote event (useful for tests & demos).
  void injectRemoteEvent(CanvasRealtimeEvent event) {
    if (_eventController.isClosed) return;
    _eventController.add(event);
  }

  /// Inject synthetic cursor data (useful for tests & demos).
  void injectRemoteCursors(Map<String, CursorPresenceData> cursors) {
    if (_cursorController.isClosed) return;
    _cursorController.add(cursors);
  }

  /// Clean up resources.
  void dispose() {
    _simulatedCursorTimer?.cancel();
    _eventController.close();
    _cursorController.close();
  }

  // ─── Private: Simulated Remote User ──────────────────────────────────

  void _mirrorEventAsRemote(CanvasRealtimeEvent original) {
    // Only mirror stroke events
    if (original.type != RealtimeEventType.strokeAdded &&
        original.type != RealtimeEventType.strokePointsStreamed) {
      return;
    }

    final delay = Duration(milliseconds: 200 + _random.nextInt(100));

    Timer(delay, () {
      if (_eventController.isClosed) return;

      final mirroredPayload = Map<String, dynamic>.from(original.payload);

      // Offset stroke ID to avoid conflicts
      if (mirroredPayload.containsKey('id')) {
        mirroredPayload['id'] = '${mirroredPayload['id']}_mirror';
      }
      if (mirroredPayload.containsKey('strokeId')) {
        mirroredPayload['strokeId'] = '${mirroredPayload['strokeId']}_mirror';
      }

      // Offset points
      if (mirroredPayload.containsKey('points')) {
        final points = mirroredPayload['points'] as List?;
        if (points != null) {
          mirroredPayload['points'] =
              points.map((pt) {
                if (pt is Map<String, dynamic>) {
                  return {
                    ...pt,
                    'x':
                        ((pt['x'] as num?)?.toDouble() ?? 0) +
                        simulatedOffset.dx,
                    'y':
                        ((pt['y'] as num?)?.toDouble() ?? 0) +
                        simulatedOffset.dy,
                  };
                }
                return pt;
              }).toList();
        }
      }

      _eventController.add(
        CanvasRealtimeEvent(
          type: original.type,
          senderId: _simulatedUserId,
          elementId:
              mirroredPayload['id'] as String? ??
              mirroredPayload['strokeId'] as String?,
          payload: mirroredPayload,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    });
  }

  void _startSimulatedCursor() {
    _simulatedCursorTimer?.cancel();
    // Emit an idle cursor every 2 seconds with slight random movement
    _simulatedCursorTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_cursorController.isClosed) return;
      _cursorController.add({
        _simulatedUserId: CursorPresenceData(
          userId: _simulatedUserId,
          displayName: simulatedUserName,
          cursorColor: 0xFFFF6B6B,
          x: 200.0 + _random.nextDouble() * 20,
          y: 300.0 + _random.nextDouble() * 20,
        ),
      });
    });
  }
}

// ─── In-Memory Permission Provider ──────────────────────────────────────────

/// A [FlueraPermissionProvider] that returns preconfigured permissions.
///
/// No backend needed — useful for testing and demos.
///
/// ```dart
/// final perms = InMemoryPermissionProvider(); // default: editor, can edit
/// final viewOnly = InMemoryPermissionProvider(canEdit: false, role: 'viewer');
/// ```
class InMemoryPermissionProvider implements FlueraPermissionProvider {
  /// Whether the current user can edit any canvas.
  final bool canEditValue;

  /// Whether the current user can view any canvas.
  final bool canViewValue;

  /// The role string returned by [currentUserRole].
  final String role;

  const InMemoryPermissionProvider({
    this.canEditValue = true,
    this.canViewValue = true,
    this.role = 'editor',
  });

  @override
  Future<bool> canEdit(String canvasId) async => canEditValue;

  @override
  Future<bool> canView(String canvasId) async => canViewValue;

  @override
  String get currentUserRole => role;
}

// ─── In-Memory Presence Provider ────────────────────────────────────────────

/// A [FlueraPresenceProvider] that manages presence in memory.
///
/// Automatically adds the local user on [joinCanvas] and removes on
/// [leaveCanvas]. Supports adding simulated remote users for demos.
///
/// ```dart
/// final presence = InMemoryPresenceProvider(localUserName: 'Alice');
/// // Simulate another user joining:
/// presence.addSimulatedUser('Bob', Colors.orange);
/// ```
class InMemoryPresenceProvider implements FlueraPresenceProvider {
  /// Display name for the local user.
  final String localUserName;

  /// Color for the local user's cursor.
  final Color localUserColor;

  InMemoryPresenceProvider({
    this.localUserName = 'You',
    this.localUserColor = const Color(0xFF42A5F5),
  });

  final ValueNotifier<List<FlueraPresenceUser>> _activeUsers = ValueNotifier(
    [],
  );

  String? _currentCanvasId;
  int _simulatedCounter = 0;

  @override
  ValueNotifier<List<FlueraPresenceUser>> get activeUsers => _activeUsers;

  @override
  void joinCanvas(String canvasId) {
    _currentCanvasId = canvasId;
    final current = List<FlueraPresenceUser>.from(_activeUsers.value);
    // Add local user if not already present
    if (!current.any((u) => u.id == '_local')) {
      current.insert(
        0,
        FlueraPresenceUser(
          id: '_local',
          name: localUserName,
          cursorColor: localUserColor,
        ),
      );
    }
    _activeUsers.value = current;
  }

  @override
  void leaveCanvas() {
    _currentCanvasId = null;
    final current = List<FlueraPresenceUser>.from(_activeUsers.value);
    current.removeWhere((u) => u.id == '_local');
    _activeUsers.value = current;
  }

  /// Add a simulated remote user (for demos).
  ///
  /// Returns the generated user ID for later removal.
  String addSimulatedUser(String name, [Color? color]) {
    _simulatedCounter++;
    final id = '_simulated_$_simulatedCounter';
    final current = List<FlueraPresenceUser>.from(_activeUsers.value);
    current.add(
      FlueraPresenceUser(
        id: id,
        name: name,
        cursorColor: color ?? Color((0xFF000000 + Random().nextInt(0xFFFFFF))),
      ),
    );
    _activeUsers.value = current;
    return id;
  }

  /// Remove a simulated user by ID.
  void removeSimulatedUser(String userId) {
    final current = List<FlueraPresenceUser>.from(_activeUsers.value);
    current.removeWhere((u) => u.id == userId);
    _activeUsers.value = current;
  }

  /// The canvas currently joined, or `null`.
  String? get currentCanvasId => _currentCanvasId;
}
