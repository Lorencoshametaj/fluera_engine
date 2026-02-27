# Real-Time Collaboration — Integration Guide

> Enterprise-grade live multi-user canvas editing for Fluera Engine.

## Quick Start

```dart
FlueraCanvasConfig(
  // ... existing config
  realtimeAdapter: MySupabaseRealtimeAdapter(),  // ← just add this
  permissions: MyPermissionProvider(),            // required for shared canvases
  presence: MyPresenceProvider(),                 // optional: user list sidebar
)
```

That's it. The engine handles everything else automatically:
- Stroke/image/text broadcasting on every edit
- Cursor presence with animated indicators
- Element locking (prevents concurrent edits)
- Reconnection with exponential backoff
- Self-echo filtering

---

## Quick Start (No Backend)

Don't have Supabase/Firebase yet? Use the **built-in in-memory adapters**
to test collaboration features instantly — no backend required:

```dart
import 'package:fluera_engine/fluera_engine.dart';

FlueraCanvasConfig(
  subscriptionTier: FlueraSubscriptionTier.plus,
  permissions: InMemoryPermissionProvider(),
  presence: InMemoryPresenceProvider(localUserName: 'Demo User'),
  realtimeAdapter: InMemoryRealtimeAdapter(
    simulateRemoteUser: true,  // See a "ghost" drawing alongside you
    latencyMs: 50,             // Simulate 50ms network delay
  ),
)
```

This enables **live stroke preview**, **cursor presence**, and **element locking**
on a single device. The simulated remote user mirrors your strokes with an offset.

---

## Architecture

```
┌───────────────────────────────────────────────┐
│  Host App (Looponia)                          │
│  ┌─────────────────────────────────────────┐  │
│  │ SupabaseRealtimeAdapter                 │  │
│  │  subscribe() → Stream<Event>            │  │
│  │  broadcast() → send to channel          │  │
│  │  cursorStream() → Stream<Cursor>        │  │
│  └──────────────┬──────────────────────────┘  │
└─────────────────┼─────────────────────────────┘
                  │
┌─────────────────┼─────────────────────────────┐
│  Fluera Engine   │                             │
│  ┌──────────────▼──────────────────────────┐  │
│  │ FlueraRealtimeEngine                    │  │
│  │  • Cursor throttle (50ms / 20Hz)        │  │
│  │  • Element lock table                   │  │
│  │  • Self-echo filter                     │  │
│  │  • Reconnection (10 attempts, 30s cap)  │  │
│  └──────────────┬──────────────────────────┘  │
│                 │                              │
│  ┌──────────────▼──────────────────────────┐  │
│  │ Canvas Screen                           │  │
│  │  • Remote stroke/image/text apply       │  │
│  │  • CanvasPresenceOverlay (cursors)      │  │
│  │  • Drawing handler broadcast            │  │
│  └─────────────────────────────────────────┘  │
└────────────────────────────────────────────────┘
```

---

## Implementing `FlueraRealtimeAdapter`

You must implement 5 methods:

### 1. `subscribe(canvasId)` → `Stream<CanvasRealtimeEvent>`

Subscribe to canvas events from all collaborators.

### 2. `broadcast(canvasId, event)` → `Future<void>`

Send an event to all connected users.

### 3. `disconnect(canvasId)` → `Future<void>`

Clean up the channel subscription.

### 4. `cursorStream(canvasId)` → `Stream<Map<String, CursorPresenceData>>`

High-frequency cursor position stream (separate from events).

### 5. `broadcastCursor(canvasId, cursor)` → `Future<void>`

Send cursor position (engine throttles at 50ms — don't add your own throttle).

---

## Example: Supabase Realtime

```dart
class SupabaseRealtimeAdapter implements FlueraRealtimeAdapter {
  final SupabaseClient supabase;
  RealtimeChannel? _channel;
  RealtimeChannel? _presenceChannel;

  SupabaseRealtimeAdapter(this.supabase);

  @override
  Stream<CanvasRealtimeEvent> subscribe(String canvasId) {
    final controller = StreamController<CanvasRealtimeEvent>();
    _channel = supabase.channel('canvas:$canvasId');

    _channel!.onBroadcast(
      event: 'canvas_event',
      callback: (payload) {
        controller.add(CanvasRealtimeEvent.fromJson(payload));
      },
    ).subscribe();

    return controller.stream;
  }

  @override
  Future<void> broadcast(String canvasId, CanvasRealtimeEvent event) async {
    await _channel?.sendBroadcastMessage(
      event: 'canvas_event',
      payload: event.toJson(),
    );
  }

  @override
  Future<void> disconnect(String canvasId) async {
    await _channel?.unsubscribe();
    await _presenceChannel?.unsubscribe();
  }

  @override
  Stream<Map<String, CursorPresenceData>> cursorStream(String canvasId) {
    final controller = StreamController<Map<String, CursorPresenceData>>();
    _presenceChannel = supabase.channel('presence:$canvasId');

    _presenceChannel!.onPresenceSync((payload) {
      final state = _presenceChannel!.presenceState();
      final cursors = <String, CursorPresenceData>{};
      for (final entry in state.entries) {
        final data = entry.value.first.payload;
        cursors[entry.key] = CursorPresenceData.fromJson(entry.key, data);
      }
      controller.add(cursors);
    }).subscribe();

    return controller.stream;
  }

  @override
  Future<void> broadcastCursor(
    String canvasId,
    CursorPresenceData cursor,
  ) async {
    await _presenceChannel?.track(cursor.toJson());
  }
}
```

---

## Example: Firebase Realtime Database

```dart
class FirebaseRealtimeAdapter implements FlueraRealtimeAdapter {
  final FirebaseDatabase db;

  FirebaseRealtimeAdapter(this.db);

  @override
  Stream<CanvasRealtimeEvent> subscribe(String canvasId) {
    return db
        .ref('canvases/$canvasId/events')
        .onChildAdded
        .map((event) => CanvasRealtimeEvent.fromJson(
              Map<String, dynamic>.from(event.snapshot.value as Map),
            ));
  }

  @override
  Future<void> broadcast(String canvasId, CanvasRealtimeEvent event) async {
    await db.ref('canvases/$canvasId/events').push().set(event.toJson());
  }

  @override
  Future<void> disconnect(String canvasId) async {
    // Firebase handles cleanup automatically
  }

  @override
  Stream<Map<String, CursorPresenceData>> cursorStream(String canvasId) {
    return db.ref('canvases/$canvasId/cursors').onValue.map((event) {
      final data = event.snapshot.value as Map?;
      if (data == null) return <String, CursorPresenceData>{};
      return data.map((key, value) => MapEntry(
            key as String,
            CursorPresenceData.fromJson(
              key as String,
              Map<String, dynamic>.from(value as Map),
            ),
          ));
    });
  }

  @override
  Future<void> broadcastCursor(
    String canvasId,
    CursorPresenceData cursor,
  ) async {
    await db
        .ref('canvases/$canvasId/cursors/${cursor.userId}')
        .set(cursor.toJson());
  }
}
```

---

## Event Types

| Type | Payload | When |
|------|---------|------|
| `strokeAdded` | Full stroke JSON | User finishes a stroke |
| `strokeRemoved` | `{ strokeId }` | Eraser removes a stroke |
| `imageAdded` | Image element JSON | User adds an image |
| `imageUpdated` | Image element JSON | User moves/resizes image |
| `imageRemoved` | `{ id }` | User deletes image |
| `textChanged` | Text element JSON | User types or moves text |
| `textRemoved` | `{ id }` | User deletes text |
| `elementLocked` | `{ elementId, userId }` | User starts editing element |
| `elementUnlocked` | `{ elementId }` | User finishes editing |
| `layerChanged` | Layer JSON | Layer visibility/order change |
| `canvasSettingsChanged` | Settings map | Background, paper type change |

---

## Cursor Presence Data

The compact JSON format (short keys for bandwidth):

```json
{
  "x": 150.0,
  "y": 300.0,
  "d": true,
  "t": false,
  "n": "Alice",
  "c": 4283215855,
  "pt": "fountainPen",
  "pc": 4294901760
}
```

| Key | Full Name | Type |
|-----|-----------|------|
| `x` | X position | `double` |
| `y` | Y position | `double` |
| `d` | isDrawing | `bool` |
| `t` | isTyping | `bool` |
| `n` | displayName | `String` |
| `c` | cursorColor | `int` (ARGB) |
| `pt` | penType | `String?` |
| `pc` | penColor | `int?` (ARGB) |

---

## Element Locking

Automatic pessimistic locking prevents concurrent edits:

```dart
// Check before editing
if (realtimeEngine.isLockedByOther('img_1')) {
  // Show "Element is being edited by Alice" toast
  return;
}

// Lock while editing
realtimeEngine.lockElement('img_1');

// Unlock after editing
realtimeEngine.unlockElement('img_1');
```

---

## Tier Gating

Real-time collaboration requires **both**:
1. A subscription tier with `canCollaborate == true`
2. A `realtimeAdapter` in the config

```dart
bool get _hasRealtimeCollab =>
    _subscriptionTier.canCollaborate && _config.realtimeAdapter != null;
```
