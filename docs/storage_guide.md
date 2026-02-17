# 💾 Nebula Engine — Storage Guide

How to persist canvases locally using the Nebula Engine SDK.

---

## Quick Start (SQLite — Zero Config)

```dart
import 'package:nebula_engine/nebula_engine.dart';

// 1. Create the adapter (one instance per app)
final storage = SqliteStorageAdapter();

// 2. Pass it to the config
NebulaCanvasScreen(
  config: NebulaCanvasConfig(
    storageAdapter: storage,
    layerController: myLayerController,
  ),
)
```

That's it. The SDK handles everything:
- **Auto-save** on every stroke, shape, text, or image change
- **Auto-load** when opening a canvas by ID
- **ACID transactions** — no partial writes on crash
- **Binary BLOBs** — stroke data is 80% smaller than JSON

---

## Canvas Gallery (Browse / Create / Delete)

The SDK includes a pre-built gallery screen:

```dart
// Full screen with grid view, FAB, search, and delete
NebulaCanvasGallery(
  storageAdapter: storage,
  onCanvasSelected: (canvasId) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => NebulaCanvasScreen(
        config: NebulaCanvasConfig(
          storageAdapter: storage,
          layerController: NebulaLayerController(),
        ),
        canvasId: canvasId,
      ),
    ));
  },
)
```

### Customization

```dart
NebulaCanvasGallery(
  storageAdapter: storage,
  onCanvasSelected: (id) => navigateTo(id),
  // Layout
  gridColumns: 3,
  showSearchBar: true,
  title: 'My Drawings',
  // Custom create logic
  onCreateCanvas: () async {
    final name = await showNameDialog(context);
    return name != null ? 'canvas_${DateTime.now().millisecondsSinceEpoch}' : null;
  },
  // Custom card design
  canvasCardBuilder: (meta, onTap, onDelete) => MyCustomCard(
    title: meta.title,
    strokes: meta.strokeCount,
    onTap: onTap,
    onDelete: onDelete,
  ),
  // Custom empty state
  emptyStateBuilder: () => Center(child: Text('Start drawing!')),
)
```

### Or Build Your Own Gallery

```dart
// Use the adapter directly — full control
final canvases = await storage.listCanvases();
for (final meta in canvases) {
  print('${meta.title}: ${meta.strokeCount} strokes');
}
await storage.deleteCanvas('old-canvas-id');
```

---

### Custom Database Path

```dart
final storage = SqliteStorageAdapter(
  databasePath: '/path/to/my/custom_canvas.db',
);
```

### Listing All Canvases

```dart
await storage.initialize();
final canvases = await storage.listCanvases();

for (final meta in canvases) {
  print('${meta.canvasId}: ${meta.title ?? "Untitled"}');
  print('  Layers: ${meta.layerCount}, Strokes: ${meta.strokeCount}');
  print('  Updated: ${meta.updatedAt}');
}
```

### Deleting a Canvas

```dart
await storage.deleteCanvas('canvas-id-to-delete');
```

---

## Custom Storage Adapter

Implement `NebulaStorageAdapter` to use **any** backend:

```dart
import 'package:nebula_engine/nebula_engine.dart';

class MyCustomStorage implements NebulaStorageAdapter {
  @override
  Future<void> initialize() async {
    // Open connection, create tables, run migrations, etc.
  }

  @override
  Future<void> saveCanvas(String canvasId, Map<String, dynamic> data) async {
    // data contains:
    //   'canvasId': String
    //   'title': String?
    //   'paperType': String ('blank', 'lined', 'grid', etc.)
    //   'backgroundColor': String?
    //   'activeLayerId': String?
    //   'layers': List<Map<String, dynamic>>  ← full layer data with strokes
    //   'guides': Map<String, dynamic>?
  }

  @override
  Future<Map<String, dynamic>?> loadCanvas(String canvasId) async {
    // Return the same map structure as saveCanvas received,
    // or null if the canvas doesn't exist.
  }

  @override
  Future<void> deleteCanvas(String canvasId) async { ... }

  @override
  Future<List<CanvasMetadata>> listCanvases() async { ... }

  @override
  Future<bool> canvasExists(String canvasId) async { ... }

  @override
  Future<void> close() async { ... }
}
```

Then pass it to the config:

```dart
NebulaCanvasScreen(
  config: NebulaCanvasConfig(
    storageAdapter: MyCustomStorage(),
    layerController: myLayerController,
  ),
)
```

---

## Examples: Other Local Databases

### Hive (Key-Value)

```yaml
# pubspec.yaml
dependencies:
  hive: ^2.2.3
  hive_flutter: ^1.1.0
```

```dart
import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:nebula_engine/nebula_engine.dart';

class HiveStorageAdapter implements NebulaStorageAdapter {
  late Box<String> _box;

  @override
  Future<void> initialize() async {
    await Hive.initFlutter();
    _box = await Hive.openBox<String>('nebula_canvases');
  }

  @override
  Future<void> saveCanvas(String canvasId, Map<String, dynamic> data) async {
    await _box.put(canvasId, jsonEncode(data));
  }

  @override
  Future<Map<String, dynamic>?> loadCanvas(String canvasId) async {
    final json = _box.get(canvasId);
    if (json == null) return null;
    return jsonDecode(json) as Map<String, dynamic>;
  }

  @override
  Future<void> deleteCanvas(String canvasId) async {
    await _box.delete(canvasId);
  }

  @override
  Future<List<CanvasMetadata>> listCanvases() async {
    final result = <CanvasMetadata>[];
    for (final key in _box.keys) {
      final json = _box.get(key);
      if (json != null) {
        final data = jsonDecode(json) as Map<String, dynamic>;
        result.add(CanvasMetadata(
          canvasId: key as String,
          title: data['title'] as String?,
          paperType: data['paperType'] as String? ?? 'blank',
          updatedAt: DateTime.now(),
          createdAt: DateTime.now(),
        ));
      }
    }
    return result;
  }

  @override
  Future<bool> canvasExists(String canvasId) async => _box.containsKey(canvasId);

  @override
  Future<void> close() async => await _box.close();
}
```

> ⚠️ **Note:** Hive stores everything as JSON strings, which is ~5x larger than
> the built-in SQLite adapter's binary BLOBs. Suitable for small canvases
> (< 1000 strokes), but SQLite is recommended for professional use.

---

### Drift (Type-Safe SQLite Wrapper)

```yaml
# pubspec.yaml
dependencies:
  drift: ^2.14.0
  sqlite3_flutter_libs: ^0.5.0
dev_dependencies:
  drift_dev: ^2.14.0
  build_runner: ^2.4.0
```

```dart
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:nebula_engine/nebula_engine.dart';

// Define your Drift tables and database, then:
class DriftStorageAdapter implements NebulaStorageAdapter {
  final MyDriftDatabase _db;

  DriftStorageAdapter(this._db);

  @override
  Future<void> initialize() async {
    // Drift handles migrations via schemaVersion
  }

  @override
  Future<void> saveCanvas(String canvasId, Map<String, dynamic> data) async {
    await _db.into(_db.canvases).insertOnConflictUpdate(
      CanvasesCompanion.insert(
        canvasId: canvasId,
        data: jsonEncode(data),
        updatedAt: DateTime.now(),
      ),
    );
  }

  // ... implement remaining methods
}
```

> ℹ️ Drift adds code generation overhead but gives compile-time SQL safety.
> Recommended only if your app already uses Drift for other data.

---

### Firebase Firestore (Cloud)

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nebula_engine/nebula_engine.dart';

class FirestoreStorageAdapter implements NebulaStorageAdapter {
  final String userId;
  late CollectionReference _canvasesRef;

  FirestoreStorageAdapter({required this.userId});

  @override
  Future<void> initialize() async {
    _canvasesRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('canvases');
  }

  @override
  Future<void> saveCanvas(String canvasId, Map<String, dynamic> data) async {
    await _canvasesRef.doc(canvasId).set(data, SetOptions(merge: true));
  }

  @override
  Future<Map<String, dynamic>?> loadCanvas(String canvasId) async {
    final doc = await _canvasesRef.doc(canvasId).get();
    return doc.exists ? doc.data() as Map<String, dynamic>? : null;
  }

  @override
  Future<void> deleteCanvas(String canvasId) async {
    await _canvasesRef.doc(canvasId).delete();
  }

  @override
  Future<List<CanvasMetadata>> listCanvases() async {
    final snapshot = await _canvasesRef.orderBy('updatedAt', descending: true).get();
    return snapshot.docs.map((d) {
      final data = d.data() as Map<String, dynamic>;
      return CanvasMetadata(
        canvasId: d.id,
        title: data['title'] as String?,
        paperType: data['paperType'] as String? ?? 'blank',
        updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );
    }).toList();
  }

  @override
  Future<bool> canvasExists(String canvasId) async {
    final doc = await _canvasesRef.doc(canvasId).get();
    return doc.exists;
  }

  @override
  Future<void> close() async {}
}
```

> ⚠️ **Note:** Firestore has a 1MB document size limit. For canvases with
> many strokes, split layer data into subcollections or use Firebase Storage
> for binary data.

---

## Comparison

| Adapter | Best For | Size Efficiency | Transactions | Setup |
|---------|----------|----------------|-------------|-------|
| **SqliteStorageAdapter** (built-in) | Professional / enterprise | ⭐⭐⭐⭐⭐ (binary BLOBs) | ✅ ACID | Zero config |
| Hive | Simple apps, prototypes | ⭐⭐ (JSON strings) | ❌ | Low |
| Drift | Apps already using Drift | ⭐⭐⭐⭐⭐ (SQLite) | ✅ ACID | Medium (codegen) |
| Firestore | Cloud-first apps | ⭐⭐ (JSON + 1MB limit) | ✅ | Medium |

**Recommendation:** Use the built-in `SqliteStorageAdapter` unless you have a specific reason not to.
