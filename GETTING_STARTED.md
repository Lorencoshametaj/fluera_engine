# 🚀 Getting Started — Fluera Engine SDK

Guida completa per integrare **Fluera Engine** nella tua app Flutter.

---

## 1. Aggiungi la dipendenza

```yaml
# pubspec.yaml
dependencies:
  fluera_engine:
    path: ../fluera_engine     # locale (sviluppo)
    # oppure da Git:
    # git:
    #   url: https://github.com/tuo-org/fluera_engine.git
    #   ref: main
```

```bash
flutter pub get
```

---

## 2. Setup minimo (5 righe)

```dart
import 'package:flutter/material.dart';
import 'package:fluera_engine/fluera_engine.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Persistenza locale zero-config (SQLite, WAL, binary BLOBs)
  final storage = SqliteStorageAdapter();
  await storage.initialize();

  runApp(MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    home: FlueraCanvasScreen(
      config: FlueraCanvasConfig(
        layerController: LayerController(),
        storageAdapter: storage,
      ),
    ),
  ));
}
```

**Questo ti dà subito:**
- ✏️ Canvas infinita con zoom e pan
- 🖊️ 12 pennelli professionali (ballpoint, pencil, fountain pen, marker, charcoal, oil, spray, neon, ink wash, watercolor, highlighter, eraser)
- 📐 Forme, testo, immagini, PDF
- ↩️ Undo/redo illimitato
- 💾 Auto-save locale su ogni modifica
- 🎨 Shader GPU per ogni pennello
- 📊 Scene graph gerarchico con spatial index

---

## 3. Configurazione completa

`FlueraCanvasConfig` usa **dependency injection** — ogni feature è opzionale e si attiva passando il provider corrispondente.

```dart
FlueraCanvasScreen(
  config: FlueraCanvasConfig(
    // ──── OBBLIGATORIO ────────────────────────────────────
    layerController: LayerController(),

    // ──── PERSISTENZA LOCALE ──────────────────────────────
    storageAdapter: SqliteStorageAdapter(),   // zero-config

    // ──── AUTH ─────────────────────────────────────────────
    getUserId: () async => myAuthService.currentUserId,

    // ──── CLOUD SYNC ──────────────────────────────────────
    cloudAdapter: MyCloudAdapter(),       // vedi §4

    // ──── COLLABORAZIONE REAL-TIME ────────────────────────
    realtimeAdapter: MyRealtimeAdapter(), // vedi §5
    permissions: MyPermissionProvider(),
    presence: MyPresenceProvider(),

    // ──── TIER / FEATURE GATING ───────────────────────────
    subscriptionTier: FlueraSubscriptionTier.pro,

    // ──── PDF ─────────────────────────────────────────────
    pdfProvider: MyPdfProvider(),
    onPickPdfFile: () async => pickPdfBytes(),

    // ──── VOICE RECORDING ─────────────────────────────────
    voiceRecording: MyVoiceRecorder(),

    // ──── IMMAGINI ────────────────────────────────────────
    onStoreImage: (canvasId, path) async => uploadAndGetUrl(path),
    onLoadImage: (canvasId, imageId) async => downloadToLocal(imageId),

    // ──── UI CALLBACKS ────────────────────────────────────
    onShareCanvas: (ctx, id) => showShareDialog(ctx, id),
    onShowExportDialog: (ctx, data) => showExportSheet(ctx, data),
    onOpenSplitView: (ctx, {canvasId}) => openSplitView(ctx),
    onShowSettings: (ctx) => showSettingsDialog(ctx),

    // ──── PERFORMANCE ─────────────────────────────────────
    onPauseSyncCoordinator: (pause) => syncCoordinator.setPaused(pause),
    onPauseAppListeners: (pause) => appListeners.setPaused(pause),

    // ──── BRANDING ────────────────────────────────────────
    splashLogoAsset: 'assets/my_logo.png',
  ),
  canvasId: 'my-canvas-123',
  title: 'My Drawing',
)
```

---

## 4. Cloud Sync (opzionale)

Implementa `FlueraCloudStorageAdapter` per il tuo backend:

```dart
class MyCloudAdapter implements FlueraCloudStorageAdapter {
  @override
  Future<void> saveCanvas(String canvasId, Map<String, dynamic> data) async {
    // Salva nel tuo database (Firestore, Supabase, REST API, ecc.)
  }

  @override
  Future<Map<String, dynamic>?> loadCanvas(String canvasId) async {
    // Carica dal database. Ritorna null se non esiste.
  }

  @override
  Future<void> deleteCanvas(String canvasId) async {
    // Elimina dal database
  }

  @override
  Future<String> uploadAsset(String canvasId, String assetId, Uint8List data,
      {String? mimeType}) async {
    // Upload immagini/PDF → ritorna URL di download
  }

  @override
  Future<Uint8List?> downloadAsset(String canvasId, String assetId) async {
    // Download asset binario → ritorna bytes
  }

  @override
  Future<void> deleteCanvasAssets(String canvasId) async {
    // Elimina tutti gli asset di un canvas
  }

  @override
  Future<List<Map<String, dynamic>>> listCanvases() async {
    // Lista di tutti i canvas nel cloud
  }
}
```

> 📖 Guide dettagliate per backend specifici: [`docs/cloud_sync_guide.md`](docs/cloud_sync_guide.md)

**Il sync è automatico:** dopo il save locale, il `FlueraSyncEngine` interno debounce (3s) e invia al cloud con retry esponenziale.

---

## 5. Collaborazione Real-Time (opzionale)

Implementa `FlueraRealtimeAdapter` per editing multi-utente:

```dart
class MyRealtimeAdapter implements FlueraRealtimeAdapter {
  @override
  Stream<CanvasRealtimeEvent> subscribe(String canvasId) {
    // Sottoscrivi a eventi canvas remoti (stroke aggiunti, cancellati, ecc.)
  }

  @override
  Future<void> broadcast(String canvasId, CanvasRealtimeEvent event) async {
    // Invia un evento a tutti i collaboratori
  }

  @override
  Future<void> disconnect(String canvasId) async {
    // Disconnetti dal canale
  }

  @override
  Stream<Map<String, CursorPresenceData>> cursorStream(String canvasId) {
    // Sottoscrivi a posizioni cursore degli altri utenti
  }

  @override
  Future<void> broadcastCursor(String canvasId, CursorPresenceData cursor) async {
    // Invia la posizione del cursore
  }
}
```

Il motore gestisce internamente:
- CRDT vector clock per ordinamento causale
- Rate limiting (60 events/s)
- Event batching (100ms window)
- Offline queue con replay automatico
- Reconnection con backoff esponenziale
- Element locking per evitare conflitti

> 📖 Guida completa: [`docs/realtime_collaboration_guide.md`](docs/realtime_collaboration_guide.md)

---

## 6. Esempio Firebase completo

```yaml
# pubspec.yaml
dependencies:
  fluera_engine:
    path: ../fluera_engine
  firebase_core: ^3.12.1
  cloud_firestore: ^5.6.5
  firebase_auth: ^5.5.1
  firebase_storage: ^12.4.4
  firebase_database: ^11.3.4
```

```dart
import 'package:fluera_engine/fluera_engine.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_database/firebase_database.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  final storage = SqliteStorageAdapter();
  await storage.initialize();

  runApp(MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    home: FlueraCanvasScreen(
      config: FlueraCanvasConfig(
        layerController: LayerController(),
        storageAdapter: storage,
        getUserId: () async => FirebaseAuth.instance.currentUser?.uid,
        cloudAdapter: FirestoreCloudAdapter(),
        realtimeAdapter: FirebaseRealtimeAdapter(),
      ),
    ),
  ));
}

// ─── Firestore Cloud Adapter ────────────────────────────────────────────

class FirestoreCloudAdapter implements FlueraCloudStorageAdapter {
  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  @override
  Future<void> saveCanvas(String id, Map<String, dynamic> data) async =>
      await _db.collection('canvases').doc(id).set({
        ...data,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  @override
  Future<Map<String, dynamic>?> loadCanvas(String id) async =>
      (await _db.collection('canvases').doc(id).get()).data();

  @override
  Future<void> deleteCanvas(String id) async =>
      await _db.collection('canvases').doc(id).delete();

  @override
  Future<String> uploadAsset(String canvasId, String assetId, Uint8List data,
      {String? mimeType}) async {
    final ref = _storage.ref('canvas_assets/$canvasId/$assetId');
    await ref.putData(data,
        mimeType != null ? SettableMetadata(contentType: mimeType) : null);
    return await ref.getDownloadURL();
  }

  @override
  Future<Uint8List?> downloadAsset(String canvasId, String assetId) async {
    try {
      return await _storage
          .ref('canvas_assets/$canvasId/$assetId')
          .getData(10 * 1024 * 1024);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> deleteCanvasAssets(String canvasId) async {
    final result = await _storage.ref('canvas_assets/$canvasId').listAll();
    for (final item in result.items) await item.delete();
  }

  @override
  Future<List<Map<String, dynamic>>> listCanvases() async =>
      (await _db.collection('canvases').orderBy('updatedAt', descending: true).get())
          .docs
          .map((d) => {...d.data(), 'canvasId': d.id})
          .toList();
}

// ─── Firebase RTDB Realtime Adapter ─────────────────────────────────────

class FirebaseRealtimeAdapter implements FlueraRealtimeAdapter {
  final _rtdb = FirebaseDatabase.instance;

  @override
  Stream<CanvasRealtimeEvent> subscribe(String canvasId) {
    final controller = StreamController<CanvasRealtimeEvent>();
    final sub = _rtdb
        .ref('realtime/$canvasId/events')
        .orderByChild('timestamp')
        .startAt(DateTime.now().millisecondsSinceEpoch)
        .onChildAdded
        .listen((e) {
      if (e.snapshot.value is Map) {
        controller.add(CanvasRealtimeEvent.fromJson(
            Map<String, dynamic>.from(e.snapshot.value as Map)));
      }
    });
    controller.onCancel = () => sub.cancel();
    return controller.stream;
  }

  @override
  Future<void> broadcast(String canvasId, CanvasRealtimeEvent event) async =>
      await _rtdb.ref('realtime/$canvasId/events').push().set(event.toJson());

  @override
  Future<void> disconnect(String canvasId) async {}

  @override
  Stream<Map<String, CursorPresenceData>> cursorStream(String canvasId) {
    final controller = StreamController<Map<String, CursorPresenceData>>();
    final sub = _rtdb.ref('realtime/$canvasId/cursors').onValue.listen((e) {
      final data = e.snapshot.value;
      if (data is! Map) { controller.add({}); return; }
      controller.add(Map.fromEntries(data.entries.map((entry) => MapEntry(
          entry.key as String,
          CursorPresenceData.fromJson(
              entry.key as String, Map<String, dynamic>.from(entry.value as Map))))));
    });
    controller.onCancel = () => sub.cancel();
    return controller.stream;
  }

  @override
  Future<void> broadcastCursor(String canvasId, CursorPresenceData cursor) async {
    final ref = _rtdb.ref('realtime/$canvasId/cursors/${cursor.userId}');
    await ref.set(cursor.toJson());
    await ref.onDisconnect().remove();
  }
}
```

---

## 7. Subscription Tier (Feature Gating)

```dart
enum FlueraSubscriptionTier { free, essential, plus, pro }
```

| Feature | free | essential | plus | pro |
|---------|------|-----------|------|-----|
| Disegno + salvataggio locale | ✅ | ✅ | ✅ | ✅ |
| Cloud sync | ❌ | ❌ | ✅ | ✅ |
| Collaborazione real-time | ❌ | ❌ | ✅ | ✅ |
| AI filters | ❌ | ❌ | ❌ | ✅ |

---

## 8. Canvas Gallery (pre-built)

```dart
FlueraCanvasGallery(
  storageAdapter: storage,
  onCanvasSelected: (canvasId) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => FlueraCanvasScreen(
        config: myConfig,
        canvasId: canvasId,
      ),
    ));
  },
)
```

---

## 9. Validazione config

```dart
final issues = config.validate();
if (issues.isNotEmpty) {
  for (final issue in issues) debugPrint('⚠️ $issue');
}
```

---

## Requisiti

| Requisito | Versione minima |
|-----------|----------------|
| Dart SDK | `^3.7.0` |
| Flutter | `≥ 3.27.0` |
| Android minSdk | `23` (Android 6.0) |
| iOS | `12.0+` |

---

## Link utili

- [Guida storage](docs/storage_guide.md) — Persistenza locale e adapter custom
- [Guida cloud sync](docs/cloud_sync_guide.md) — Sync automatico con qualsiasi backend
- [Guida collaborazione](docs/realtime_collaboration_guide.md) — Editing multi-utente
- [Guida voice recording](docs/voice_recording_guide.md) — Registrazioni audio sincronizzate
- [Architettura](ARCHITECTURE.md) — Scene graph, moduli, conscious architecture
