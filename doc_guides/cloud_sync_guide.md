# ☁️ Cloud Sync — Guida all'integrazione

Fluera Engine supporta il salvataggio automatico dei canvas su qualsiasi database online tramite l'interfaccia `FlueraCloudStorageAdapter`.

## Come funziona

```
Canvas modificato → auto-save locale → FlueraSyncEngine (debounce 3s) → FlueraCloudStorageAdapter → tuo backend
```

1. **L'utente disegna** — il canvas si salva localmente
2. **Dopo 3 secondi di inattività** — il `FlueraSyncEngine` invia i dati al cloud
3. **La toolbar mostra lo stato** — ☁️ syncing / ✅ idle / ⚠️ error
4. **Su app background** — flush immediato (nessun dato perso)

## Passo 1: Implementa l'adapter

Crea una classe che implementa `FlueraCloudStorageAdapter`:

```dart
import 'package:fluera_engine/fluera_engine.dart';

class MyCloudAdapter implements FlueraCloudStorageAdapter {
  @override
  Future<void> saveCanvas(String canvasId, Map<String, dynamic> data) async {
    // Salva i dati nel tuo database
  }

  @override
  Future<Map<String, dynamic>?> loadCanvas(String canvasId) async {
    // Carica i dati dal tuo database (null se non esiste)
  }

  @override
  Future<void> deleteCanvas(String canvasId) async {
    // Elimina il canvas dal database
  }
}
```

## Passo 2: Passa l'adapter alla config

```dart
FlueraCanvasScreen(
  config: FlueraCanvasConfig(
    // ... altre opzioni ...
    cloudAdapter: MyCloudAdapter(),
  ),
)
```

**Fatto!** Il canvas si salverà automaticamente nel cloud dopo ogni modifica.

---

## Esempi per backend comuni

### 🔶 Supabase

```dart
class SupabaseCloudAdapter implements FlueraCloudStorageAdapter {
  final supabase = Supabase.instance.client;

  @override
  Future<void> saveCanvas(String canvasId, Map<String, dynamic> data) async {
    await supabase.from('canvases').upsert({
      'id': canvasId,
      'user_id': supabase.auth.currentUser!.id,
      'data': data,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  @override
  Future<Map<String, dynamic>?> loadCanvas(String canvasId) async {
    final row = await supabase
        .from('canvases')
        .select('data')
        .eq('id', canvasId)
        .maybeSingle();
    return row?['data'] as Map<String, dynamic>?;
  }

  @override
  Future<void> deleteCanvas(String canvasId) async {
    await supabase.from('canvases').delete().eq('id', canvasId);
  }
}
```

**SQL per creare la tabella:**
```sql
create table canvases (
  id text primary key,
  user_id uuid references auth.users not null,
  data jsonb not null default '{}',
  updated_at timestamptz default now(),
  created_at timestamptz default now()
);

-- RLS: ogni utente vede solo i suoi canvas
alter table canvases enable row level security;

create policy "Users manage own canvases"
  on canvases for all
  using (auth.uid() = user_id);
```

---

### 🔥 Firebase Firestore

```dart
class FirestoreCloudAdapter implements FlueraCloudStorageAdapter {
  final _db = FirebaseFirestore.instance;
  final String userId;

  FirestoreCloudAdapter({required this.userId});

  CollectionReference get _canvases =>
      _db.collection('users').doc(userId).collection('canvases');

  @override
  Future<void> saveCanvas(String canvasId, Map<String, dynamic> data) async {
    await _canvases.doc(canvasId).set({
      'data': data,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<Map<String, dynamic>?> loadCanvas(String canvasId) async {
    final doc = await _canvases.doc(canvasId).get();
    if (!doc.exists) return null;
    return doc.data()?['data'] as Map<String, dynamic>?;
  }

  @override
  Future<void> deleteCanvas(String canvasId) async {
    await _canvases.doc(canvasId).delete();
  }
}
```

---

### 🌐 REST API generica

```dart
class RestCloudAdapter implements FlueraCloudStorageAdapter {
  final String baseUrl;
  final String authToken;

  RestCloudAdapter({required this.baseUrl, required this.authToken});

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $authToken',
    'Content-Type': 'application/json',
  };

  @override
  Future<void> saveCanvas(String canvasId, Map<String, dynamic> data) async {
    final response = await http.put(
      Uri.parse('$baseUrl/canvases/$canvasId'),
      headers: _headers,
      body: jsonEncode(data),
    );
    if (response.statusCode != 200) {
      throw Exception('Save failed: ${response.statusCode}');
    }
  }

  @override
  Future<Map<String, dynamic>?> loadCanvas(String canvasId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/canvases/$canvasId'),
      headers: _headers,
    );
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw Exception('Load failed: ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  @override
  Future<void> deleteCanvas(String canvasId) async {
    await http.delete(
      Uri.parse('$baseUrl/canvases/$canvasId'),
      headers: _headers,
    );
  }
}
```

---

## Configurazione avanzata

Il `FlueraSyncEngine` gestisce internamente:

| Feature | Default | Descrizione |
|---------|---------|-------------|
| **Debounce** | 3 secondi | Attende inattività prima di salvare |
| **Retry** | 3 tentativi | Con backoff esponenziale (2s, 4s, 8s) |
| **Dedup** | Automatico | Solo l'ultimo snapshot viene salvato |
| **Flush** | Su app background | Salvataggio immediato quando l'app va in background |

### Stato sync nella toolbar

L'indicatore nella toolbar mostra automaticamente:
- ☁️ **Syncing** — salvataggio in corso (icona animata)
- ✅ **Idle** — tutto sincronizzato (nascosto)
- ⚠️ **Error** — errore dopo 3 tentativi (icona ambra)

### Caricare un canvas dal cloud

```dart
// Nel tuo codice, prima di aprire il canvas:
final adapter = MyCloudAdapter();
final cloudData = await adapter.loadCanvas('canvas_123');

if (cloudData != null) {
  // Passa i dati al canvas screen per il ripristino
  // (integrazione con il sistema di caricamento esistente)
}
```

---

## Upload/Download Asset Binari (Immagini e PDF)

L'adapter gestisce anche il caricamento e lo scaricamento di **file binari** (immagini, PDF):

### Upload automatico
Quando l'utente aggiunge un'immagine o un PDF al canvas, il file viene automaticamente caricato nel cloud:
```
pickAndAddImage() → adapter.uploadAsset() → storageUrl salvato nell'ImageElement
pickAndAddPdf()   → adapter.uploadAsset() → PDF bytes nel cloud
```

### Download automatico
Su un dispositivo diverso, quando il canvas viene caricato dal cloud:
- **Immagini**: `downloadMissingAssets()` scarica i file mancanti
- **PDF**: `_restorePdfDocuments()` tenta il download se il file locale non esiste

### Esempio Supabase Storage

```dart
@override
Future<String> uploadAsset(
  String canvasId,
  String assetId,
  Uint8List data, {
  String? mimeType,
}) async {
  final path = 'canvases/$canvasId/assets/$assetId';
  await supabase.storage.from('canvas-assets').uploadBinary(
    path,
    data,
    fileOptions: FileOptions(contentType: mimeType),
  );
  return supabase.storage.from('canvas-assets').getPublicUrl(path);
}

@override
Future<Uint8List?> downloadAsset(String canvasId, String assetId) async {
  final path = 'canvases/$canvasId/assets/$assetId';
  try {
    return await supabase.storage.from('canvas-assets').download(path);
  } catch (_) {
    return null;
  }
}

@override
Future<void> deleteCanvasAssets(String canvasId) async {
  final list = await supabase.storage
      .from('canvas-assets')
      .list(path: 'canvases/$canvasId/assets');
  if (list.isNotEmpty) {
    await supabase.storage.from('canvas-assets').remove(
      list.map((f) => 'canvases/$canvasId/assets/${f.name}').toList(),
    );
  }
}
```
---

## Elenco Canvas (`listCanvases`)

Per mostrare una lista dei canvas salvati nel cloud:

```dart
final canvases = await syncEngine.listCanvases();
for (final c in canvases) {
  print('${c['canvasId']}: ${c['title']} (updated: ${c['updatedAt']})');
}
```

### Esempio Supabase

```dart
@override
Future<List<Map<String, dynamic>>> listCanvases() async {
  final response = await supabase
      .from('canvases')
      .select('id, data->title, updated_at')
      .order('updated_at', ascending: false);
  return response.map((row) => {
    'canvasId': row['id'],
    'title': row['title'] ?? 'Untitled',
    'updatedAt': DateTime.parse(row['updated_at']).millisecondsSinceEpoch,
  }).toList();
}
```

---

## Audio Recordings

Le registrazioni audio vengono automaticamente caricate nel cloud dopo il salvataggio locale:
- **Upload**: dopo `RecordingStorageService.saveRecording()` → `adapter.uploadAsset()` con `mimeType: audio/m4a`
- L'asset ID segue il pattern `recording_{id}`

## Struttura dati salvati

Il `Map<String, dynamic>` passato a `saveCanvas` contiene:

```json
{
  "layers": [
    {
      "id": "layer_abc",
      "name": "Layer 1",
      "visible": true,
      "strokes": [...],
      "images": [...]
    }
  ],
  "metadata": {
    "title": "My Canvas",
    "createdAt": "2026-02-21T22:00:00Z",
    "version": 1
  }
}
```

> **Tip:** Il formato è JSON standard — puoi ispezionarlo e migrarlo facilmente.
