---
description: Regole permanenti per lo sviluppo su nebula_engine — motore grafico 2D professionale Flutter
---

# 🎨 NEBULA ENGINE — Regole di Sviluppo

## 1. ARCHITETTURA — Non violare mai

### Scene Graph (core/)
- **Base class**: `CanvasNode` — tutti gli elementi estendono questa. NON creare gerarchie parallele.
- **13 tipi di nodo** (stroke, shape, text, image, group, layer, path, rich_text, clip_group, frame, symbol_instance, advanced_mask, shader). Per aggiungerne uno: sottoclasse di `CanvasNode`, registra in `CanvasNodeFactory.fromJson()`, aggiungi case in `SceneGraphRenderer`, aggiungi case nel `NodeVisitor`.
- **Serializzazione**: ogni nodo implementa `toJson()` e usa `baseToJson()` + `applyBaseFromJson()`. MAI rompere la retrocompatibilità JSON. Aggiungere campi opzionali con fallback.
- **Transforms**: sempre `Matrix4` gerarchico. `worldTransform` è cachato — chiamare `invalidateTransformCache()` quando modifichi `localTransform`.
- **Observer pattern**: `SceneGraphObserver` per notifiche di modifica al scene graph. Usalo, non reinventare.

### Dependency Inversion (SDK ↔ App)
- **MAI** importare direttamente Firebase, auth, o servizi dell'app Looponia dentro `nebula_engine`.
- Tutte le dipendenze esterne passano via `NebulaCanvasConfig` (auth, storage, sync, voice, permissions, subscription tier).
- Interfacce astratte in `collaboration/nebula_sync_interfaces.dart`: `NebulaTimeTravelStorage`, `NebulaBranchCloudSync`, `NebulaRealtimeDeltaSync`.
- Provider astratti in `nebula_canvas_config.dart`: `NebulaVoiceRecordingProvider`, `NebulaRealtimeSyncProvider`, `NebulaTimeTravelProvider`, `NebulaPermissionProvider`, `NebulaPresenceProvider`.

### Tool System (tools/)
- Tutti i tool implementano `DrawingTool` (abstract class in `tool_interface.dart`).
- Tool sono **STATELESS rispetto al contesto** — tutta la logica context-specific vive in `ToolContext` / `CanvasAdapter`.
- `ToolContext` è immutabile (const constructor). Operazioni delegate all'adapter.
- Per aggiungere un tool: implementa `DrawingTool`, registra in `ToolRegistry`, crea la versione "unified" se serve.
- Mixin disponibili: `SelectionToolMixin`, `ContinuousDrawingMixin`.

### Drawing Pipeline (drawing/)
- `DrawingInputHandler` → gestisce input con 1€ Filter, predicted touches (iOS), pressure normalization.
- `BrushEngine` è l'**UNICO** dispatch point per pen type → brush. MAI duplicare la logica switch(penType).
- Brush concreti: `BallpointBrush`, `FountainPenBrush`, `PencilBrush`, `HighlighterBrush`. Per aggiungerne uno: crea classe, aggiungi case in `ProPenType` enum, aggiungi case in `BrushEngine.renderStroke()`.
- `ProDrawingPoint` è il modello base — contiene position, pressure, tiltX, tiltY, orientation, timestamp, velocity.
- `ProBrushSettings` contiene tutti i parametri del brush — NON creare settings separate.

### Rendering (rendering/)
- **Canvas painters** (CustomPainter): `DrawingPainter`, `CurrentStrokePainter`, `BackgroundPainter`, `ShapePainter`, etc.
- **Optimization layer**: `SpatialIndex` (R-tree), `TileCacheManager`, `ViewportCuller`, `LODManager`, `PaintPool`, `FrameBudgetManager`, `DirtyRegionTracker`.
- `DrawingPainter` renderizza a livello viewport (non canvas). Trasformazioni applicate direttamente nel painter.
- **Performance è critica**: ogni modifica al rendering deve considerare frame budget (16ms), evitare allocazioni in paint(), usare il `PaintPool`.

### Large File Decomposition
- `NebulaCanvasScreen` (885 righe) usa `part` files in `parts/`:
  - `_lifecycle.dart`, `_drawing_handlers.dart`, `_build_ui.dart`, `_canvas_operations.dart`, `_export.dart`, `_collaboration.dart`, `_cloud_sync.dart`, `_image_features.dart`, `_text_tools.dart`, `_voice_recording.dart`, `_eraser_painters.dart`, `_phase2_stubs.dart`
- Le extensions in `part` files accedono a `setState()` della State class (il lint `invalid_use_of_protected_member` è ignorato intenzionalmente).
- MAI creare nuovi `part` files senza necessità. Preferire composizione e estrazione in classi separate.

---

## 2. CONVENZIONI DI CODICE

### Naming
- File: `snake_case.dart` — prefisso `nebula_` per API publiche SDK, `pro_` per modelli professionali.
- Classi: `PascalCase` con prefisso `Nebula` per API pubbliche (es. `NebulaCanvasConfig`, `NebulaLayerController`).
- Privati nelle part files: prefisso `_` (es. `_initTimeTravelRecorder`, `_loadCanvasData`).

### Language — EVERYTHING in English
- **ALL code MUST be in English**: variable names, function names, class names, comments, docstrings, commit messages, TODOs, error messages.
- No Italian in new code. When modifying existing code with Italian comments, convert them to English.
- Emoji section markers: 🎨 Drawing, 🚀 Performance, 💾 Storage, ⏱️ Time Travel, 🔄 Sync, 🖼️ Image, 🎛️ Settings, 🔧 Utils, 🎯 Core, 🔮 Recovery, ✨ Effects, 🎬 Export.
- Code sections delimited by `// ============================================================================`.
- Design principles documented in docstrings with bullet points (`/// DESIGN PRINCIPLES:`).

### Serializzazione
- Tutti i modelli: `toJson()` → `Map<String, dynamic>`, factory `fromJson(Map<String, dynamic>)`.
- Campi opzionali sempre con fallback: `json['field'] ?? defaultValue`.
- `toDouble()` per valori numerici da JSON per safety.
- Schema version in `SceneGraph.toJson()` con `version: 1`.
- Clone via JSON roundtrip: `CanvasNode.clone()`.

### State Management
- `ValueNotifier` per performance real-time (tratti correnti) — NO Riverpod per hot path.
- `ChangeNotifier` per controller (es. `UnifiedToolController`, `LayerController`).
- `flutter_riverpod` per stato applicativo (non nel hot path di rendering).

### Error Handling
- Mai crash silenziosamente nel rendering — catch + debugPrint.
- Operazioni async nel lifecycle: `try/catch` con fallback graceful.
- `mounted` check prima di `setState()` in callback async.

### Analysis Options
- `invalid_use_of_protected_member: ignore` — necessario per extensions su State.
- `unused_element/field/variable/import: ignore` — Phase 2 stubs intenzionali.
- Directory `_phase2_disabled/` esclusa dall'analisi.

---

## 3. PERFORMANCE — Regole ferree

- **MAI allocare oggetti in `paint()`** — usa `PaintPool` o cache pre-allocate.
- **Frame budget**: 16ms per frame (60fps). Misura con `FrameBudgetManager`.
- **Viewport culling**: usa `ViewportCuller` + `SpatialIndex` — NON iterare tutti gli strokes.
- **Path reuse**: `PathPool` per riciclare Path objects. `StrokePointPool` per punti.
- **Dirty regions**: usa `DirtyRegionTracker` per repaint minimale.
- **LOD**: `LODManager` per ridurre dettaglio a zoom bassi.
- **Isolates**: operazioni pesanti (compressione Time Travel, export) → Isolate. Mai bloccare il main thread.
- **Image loading**: cap a 2048px con `_decodeImageCapped()`. Progressive loading (thumbnail → full-res).
- **Input latency**: `RawInputProcessor120Hz` per massima responsività. Predicted touches su iOS.

---

## 4. PATTERN DI INTEGRAZIONE

### Come l'app Looponia usa l'SDK
```dart
NebulaCanvasScreen(
  config: NebulaCanvasConfig(
    layerController: myLayerController,
    auth: MyAuthProvider(),          // implements callbacks
    storage: MyStorageProvider(),     // implements callbacks
    sync: MyNebulaSyncInterfaces(),  // implements abstract classes
  ),
)
```

### Come aggiungere una feature
1. Se tocca il core: modifica in `nebula_engine/lib/src/`
2. Se ha dipendenze Firebase/app: crea interfaccia astratta, implementa nell'app.
3. Aggiungi l'export in `nebula_engine.dart` (barrel file).
4. Aggiorna `ARCHITECTURE.md` se architetturalmente significativo.

### Localizzazione
- `NebulaLocalizations` in `l10n/nebula_localizations.dart` — tutte le stringhe dell'SDK.
- MAI hardcodare stringhe UI. Usa `NebulaLocalizations.of(context).myString`.

---

## 5. FILE CRITICI — Consulta sempre prima di modificare

| File | Linee | Ruolo |
|------|-------|-------|
| `nebula_canvas_screen.dart` | 885 | Entry point del canvas |
| `parts/_build_ui.dart` | ~3500 | Tutto il widget tree |
| `parts/_lifecycle.dart` | ~1480 | Init, load, dispose, Time Travel |
| `parts/_drawing_handlers.dart` | ~1500 | Gestori input disegno |
| `canvas_node.dart` | 344 | Base class scene graph |
| `brush_engine.dart` | 512 | Dispatch unificato brush |
| `drawing_input_handler.dart` | 342 | Pipeline input 120Hz |
| `nebula_canvas_config.dart` | 355 | Dependency injection config |
| `tool_interface.dart` | 135 | Interfaccia base tool |
| `tool_context.dart` | 233 | Context per tool |
| `layer_controller.dart` | ~800 | Gestione layers |
| `nebula_engine.dart` | 255 | Barrel export |

---

## 6. CHECKLIST PRE-COMMIT

- [ ] `flutter analyze` clean (no nuovi warning)
- [ ] Nessun import diretto di Firebase/app in nebula_engine
- [ ] Nuovi file esportati nel barrel `nebula_engine.dart`
- [ ] Serializzazione JSON retrocompatibile (campi opzionali con fallback)
- [ ] Nessuna allocazione nel hot path di rendering
- [ ] Docstrings per API pubbliche
- [ ] `ARCHITECTURE.md` aggiornato se necessario
