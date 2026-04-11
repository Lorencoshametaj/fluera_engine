# 🤝 P2P Collaboration — Passo 7

Sistema di collaborazione peer-to-peer in tempo reale per Fluera.

> **Stato**: Infrastruttura completa, 120 test passano, **non attivato** nell'host app.
> Funziona senza server dedicato — usa Supabase per il signaling e WebRTC per la connessione diretta.

---

## Perché esiste

Il Passo 7 della specifica implementativa definisce tre modalità collaborative basate su evidenze cognitive:

| Modalità | Principio pedagogico | Descrizione |
|----------|---------------------|-------------|
| **Visita (7a)** | Peer learning | Guardare gli appunti di un compagno in tempo reale |
| **Insegnamento (7b)** | Effetto protégé (Feynman) | Spiegare a un compagno usando i propri appunti — chi insegna capisce meglio |
| **Duello (7c)** | Recall gamificato | Competere nel richiamare concetti — motivazione sociale |

## Come funziona

```
Alice (Host)                                    Bob (Guest)
    │                                               │
    ├─ Tap FAB → createSession()                    │
    │       │                                       │
    │       ▼                                       │
    │   Supabase Broadcast ──────────────────► riceve room ID
    │   (ICE candidates)                            │
    │       │                                       ├─ joinSession(roomId)
    │       ▼                                       │
    │   WebRTC DataChannel ◄─────────────────► WebRTC DataChannel
    │   (connessione DIRETTA, Supabase non serve più)
    │       │                                       │
    │       ▼                                       ▼
    │   Scelta modalità: Visit / Teaching / Duel
    │       │                                       │
    │       ▼                                       ▼
    │   Ghost cursor, laser, markers, voice in tempo reale
```

**Punti chiave:**
- I dati vanno **direttamente** tra i dispositivi (nessun server intermedio)
- Supabase serve solo per il "handshake" iniziale (scambio ICE candidates)
- Funziona su WiFi, 4G/5G, reti domestiche (~80% dei NAT)
- Per reti aziendali/universitarie restrittive serve un TURN server (non ancora configurato)

---

## Architettura

```
┌─────────────────── HOST APP (Fluera/) ───────────────────┐
│                                                           │
│  P2PConnector (extends FlueraP2PConnector)               │
│  ├── SupabaseP2PSignaling (ICE exchange)                 │
│  ├── WebRtcP2PTransport (DataChannel + Audio)            │
│  └── P2PDeepLinkHandler (fluera://collab/{roomId})       │
│                                                           │
│  Iniettato via: FlueraCanvasConfig(p2pConnector: ...)    │
│                                                           │
└───────────────────────────┬───────────────────────────────┘
                            │ extends FlueraP2PConnector
                            ▼
┌─────────────────── ENGINE (fluera_engine/) ───────────────┐
│                                                           │
│  FlueraP2PConnector (interfaccia astratta per DI)        │
│                                                           │
│  P2PEngine (orchestratore centrale)                      │
│  ├── P2PSessionController (FSM 14 fasi)                  │
│  ├── GhostCursorChannel (15fps, lerp)                    │
│  ├── ViewportSyncChannel (5fps, follow mode)             │
│  ├── VoiceChannelController (mute/PTT/VAD)               │
│  ├── LaserPointerChannel (30fps, 2s expiry)              │
│  └── P2PPrivacyGuard (aree nascoste)                     │
│                                                           │
│  CanvasRasterizer (720p@10fps per Visit mode)            │
│                                                           │
│  UI Widgets:                                              │
│  ├── P2PSessionOverlay (ghost cursor + laser + markers)  │
│  ├── P2PModeSelectionSheet (Visit/Teaching/Duel)         │
│  ├── P2PInviteSheet (link + codice visivo)               │
│  ├── P2PDuelOverlay (countdown + timer + split view)     │
│  └── InviteCodePainter (griglia visiva zero deps)        │
│                                                           │
│  Canvas Integration:                                      │
│  └── _p2p_session.dart (part file nel canvas Stack)      │
│                                                           │
└───────────────────────────────────────────────────────────┘
```

---

## File (34 totali)

### Engine — Core P2P (`lib/src/p2p/`)

| File | LOC | Descrizione |
|------|-----|-------------|
| `p2p_session_state.dart` | ~180 | FSM con 14 fasi + `DuelPhase` enum |
| `p2p_message_types.dart` | ~280 | 15 tipi di messaggio, serializzazione JSON compatta |
| `p2p_session_controller.dart` | ~590 | Orchestratore FSM, markers, logica duel/teaching |
| `p2p_engine.dart` | ~330 | Orchestratore centrale, dispatch messaggi |
| `p2p_privacy_guard.dart` | ~130 | Aree nascoste, hit testing |
| `p2p_session_data.dart` | ~160 | Telemetria sessione (P7-07) |
| `collab_invite_service.dart` | ~110 | Deep link + universal link + QR payload |
| `fluera_p2p_connector.dart` | ~80 | Interfaccia astratta per dependency injection |
| `canvas_rasterizer.dart` | ~295 | Cattura frame canvas per Visit mode |
| `in_memory_p2p_adapters.dart` | ~160 | Transport + signaling in-memory per test |

### Engine — Canali (`lib/src/p2p/channels/`)

| File | LOC | Descrizione |
|------|-----|-------------|
| `ghost_cursor_channel.dart` | ~160 | Cursore fantasma, 15fps con interpolazione |
| `viewport_sync_channel.dart` | ~140 | Sincronizzazione viewport, 5fps |
| `voice_channel.dart` | ~220 | Stato voce: mute, PTT, VAD, livelli |
| `laser_pointer_channel.dart` | ~140 | Puntatore laser, 30fps con fade-out 2s |

### Engine — Painters (`lib/src/rendering/canvas/`)

| File | LOC | Descrizione |
|------|-----|-------------|
| `ghost_cursor_painter.dart` | ~145 | Cursore semi-trasparente + etichetta nome |
| `laser_pointer_painter.dart` | ~105 | Tratti giallo-glow con sfumatura |
| `p2p_marker_painter.dart` | ~105 | Punti colorati con simboli !/? |

### Engine — UI Overlays (`lib/src/canvas/overlays/`)

| File | LOC | Descrizione |
|------|-----|-------------|
| `p2p_session_overlay.dart` | ~350 | Composita tutti i layer + status pill animata |
| `p2p_mode_selection_sheet.dart` | ~215 | Bottom sheet Material 3: Visit/Teaching/Duel |
| `p2p_invite_sheet.dart` | ~305 | Link host + codice room + codice visivo |
| `p2p_duel_overlay.dart` | ~340 | Countdown (3-2-1-VIA!) + timer + split view |
| `invite_code_painter.dart` | ~200 | Griglia visiva deterministica (zero dipendenze) |

### Engine — Canvas Integration (`lib/src/canvas/parts/`)

| File | Tipo | Descrizione |
|------|------|-------------|
| `_p2p_session.dart` | NEW | Part file: lifecycle, rasterizer, FAB, menu attivo, deep link |
| `fluera_canvas_screen.dart` | EDIT | +imports, +part, +init, +dispose |
| `fluera_canvas_config.dart` | EDIT | +campo `p2pConnector: FlueraP2PConnector?` |
| `_build_ui.dart` | EDIT | +overlay + FAB nello Stack principale |

### Host App — Adapters (`Fluera/lib/adapters/`)

| File | LOC | Descrizione |
|------|-----|-------------|
| `p2p_connector.dart` | ~240 | Implementazione concreta (Supabase + WebRTC) |
| `supabase_p2p_signaling.dart` | ~130 | Scambio ICE via Supabase Broadcast |
| `webrtc_p2p_transport.dart` | ~300 | DataChannel + Audio via `flutter_webrtc` |
| `p2p_deep_link_handler.dart` | ~100 | Listener MethodChannel per `fluera://collab/` |

### Configurazione Nativa

| Piattaforma | File | Modifiche |
|-------------|------|-----------|
| iOS | `Info.plist` | `NSMicrophoneUsageDescription`, URL scheme `fluera://` |
| Android | `AndroidManifest.xml` | `RECORD_AUDIO`, `INTERNET`, intent filter deep link |
| macOS | `DebugProfile.entitlements` | `network.client`, `device.audio-input` |
| macOS | `Release.entitlements` | `network.client`, `device.audio-input` |
| macOS | `Info.plist` | `NSMicrophoneUsageDescription` |

---

## Test (120/120)

```
flutter test test/p2p/ --reporter compact
00:03 +120: All tests passed!
```

| Componente | Test |
|-----------|------|
| FSM transitions | 9 |
| Message protocol | 14 |
| Session controller | 17 |
| Ghost cursor channel | 8 |
| Viewport sync channel | 6 |
| Privacy guard | 8 |
| Invite service | 10 |
| Session data + P2PRect | 5 |
| Voice channel | 12 |
| Laser pointer channel | 10 |
| InMemory transport | 7 |
| InMemory signaling | 3 |
| P2P Engine integration | 11 |

---

## Come attivare

### 1. Aggiungere la dipendenza nell'host app

```yaml
# Fluera/pubspec.yaml
dependencies:
  flutter_webrtc: ^1.0.0
```

### 2. Iniettare il connector

```dart
// Dove crei FlueraCanvasScreen:
FlueraCanvasConfig(
  // ... config esistente ...
  p2pConnector: P2PConnector(
    client: Supabase.instance.client,
    localDisplayName: currentUser.displayName,
    localZoneId: currentZoneId,
    localZoneTopic: currentZoneTopic,
  ),
)
```

### 3. (Opzionale) Deep link handler

```dart
// In main.dart:
final deepLinkHandler = P2PDeepLinkHandler();
deepLinkHandler.onP2PInvite.listen((roomId) {
  // Naviga al canvas e joina la sessione
  navigator.pushCanvas(roomId: roomId);
});
deepLinkHandler.init();
```

### 4. (Opzionale) TURN server per reti restrittive

```dart
P2PConnector(
  // ...
  webRtcConfig: WebRtcConfig(
    iceServers: [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'turn:global.twilio.com:3478',
       'username': '<twilio-username>',
       'credential': '<twilio-token>'},
    ],
  ),
)
```

---

## Nota

Questa feature è **dormiente** finché non si inietta il `P2PConnector`.
Il codice non pesa sull'app — il FAB non appare, nessun listener è registrato,
nessuna dipendenza WebRTC è caricata finché `p2pConnector` è `null`.

Può essere attivata in qualsiasi momento con 5 righe di codice nell'host app.
