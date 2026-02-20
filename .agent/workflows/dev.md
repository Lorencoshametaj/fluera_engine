---
description: Regole permanenti per lo sviluppo su nebula_engine — motore grafico 2D professionale Flutter
---

# 🎨 NEBULA ENGINE — Regole di Sviluppo
## 1. ARCHITETTURA — Non violare mai
### Scene Graph (core/)
- **Base class**: `CanvasNode` — tutti gli elementi estendono questa. NON creare gerarchie parallele.
- **13 tipi di nodo** (stroke, shape, text, image, group, layer, path, rich_text, clip_group, frame, symbol_instance, advanced_mask, shader). Per aggiungerne uno: sottoclasse di `CanvasNode`, registra in `CanvasNodeFactory.fromJson()`, case in `SceneGraphRenderer` e `NodeVisitor`.
- **Serializzazione**: `toJson()` + `baseToJson()` + `applyBaseFromJson()`. MAI rompere retrocompatibilità JSON.
- **Transforms**: `Matrix4` gerarchico. `worldTransform` cachato — `invalidateTransformCache()` su modifica.
- **Observer**: `SceneGraphObserver` per notifiche. Usalo, non reinventare.
- **Integrity** (`scene_graph_integrity.dart`): 7 checks (duplicate IDs, parent pointers, root types, spatial index bidirectional, dirty tracker, depth, cycles), 3 auto-repairs (deduplicated). `validate()` è **puro**. `validateAndRepair()` → `ErrorRecoveryService`. `IntegrityMetrics` singleton + `IntegrityWatchdog` timer (debug only). `fromJson()` asserts `violations.isEmpty`.
- **Concurrency Safety**: `_guardedMutation()` wraps all mutations (throws on re-entrancy, resets in `finally`). `List.of(_observers)` snapshot in notify. `snapshotVersion()` + `assertUnchanged(v)` for async gaps. `toJson()` throws during mutation.
### Dependency Inversion (SDK ↔ App)
- **MAI** importare Firebase/auth/servizi app dentro `nebula_engine`.
- Dipendenze esterne via `NebulaCanvasConfig` (auth, storage, sync, voice, permissions, tier).
- Interfacce: `nebula_sync_interfaces.dart` (`NebulaTimeTravelStorage`, `NebulaBranchCloudSync`, `NebulaRealtimeDeltaSync`).
- Provider: `nebula_canvas_config.dart` (`NebulaVoiceRecordingProvider`, `NebulaRealtimeSyncProvider`, `NebulaTimeTravelProvider`, `NebulaPermissionProvider`, `NebulaPresenceProvider`).
### Tool System (tools/)
- Implementa `DrawingTool` (`tool_interface.dart`). Tool sono **stateless** — logica in `ToolContext`/`CanvasAdapter`.
- Aggiungi tool: implementa `DrawingTool`, registra in `ToolRegistry`. Mixin: `SelectionToolMixin`, `ContinuousDrawingMixin`.
### Selection System (systems/selection_manager.dart)
- **Single source of truth**: `SelectionManager` gestisce TUTTO lo stato di selezione. Nessun set tipizzato (`selectedStrokeIds`, etc.) fuori dal manager.
- **LassoTool** delega a `SelectionManager` per select, deselect, transforms (translate/rotate/scale/flip), alignment, distribution, delete, duplicate.
- **API**: `select()`, `selectAll()`, `clearSelection()`, `marqueeSelect()`, `translateAll()`, `rotateAll()`, `scaleAll()`, `flipHorizontal/Vertical()`, `alignLeft/Right/Top/Bottom/CenterH/CenterV()`, `distributeH/V()`, `deleteAll()`, `duplicateAll()`.
- **MAI** creare set di selezione paralleli nei tool. Usa `selectionManager.selectedIds` e `selectionManager.selectedNodes`.
### Drawing Pipeline (drawing/)
- `DrawingInputHandler` → 1€ Filter, predicted touches, pressure normalization.
- `BrushEngine` è l'**UNICO** dispatch point pen→brush. MAI duplicare switch(penType).
- Brush: `BallpointBrush`, `FountainPenBrush`, `PencilBrush`, `HighlighterBrush`. Aggiungere: crea classe + case in `ProPenType` + `BrushEngine.renderStroke()`.
- Modelli: `ProDrawingPoint` (position, pressure, tilt, orientation, timestamp, velocity), `ProBrushSettings` (unico settings).
### Rendering (rendering/)
- Painters: `DrawingPainter`, `CurrentStrokePainter`, `BackgroundPainter`, `ShapePainter`.
- Optimization: `SpatialIndex`, `TileCacheManager`, `ViewportCuller`, `LODManager`, `PaintPool`, `FrameBudgetManager`, `DirtyRegionTracker`.
- Renderizza a viewport level. **Performance critica**: 16ms budget, zero allocazioni in paint(), usa `PaintPool`.
### File Organization
- **Limiti**: soft 500 LOC, hard 1000 LOC, preferred 200–400 LOC.
- **Decomposition**: `part`+extension per accesso a State privati, standalone per logica pura. `part of` con path relativo.
- **Directory grouping** (>6 parts): subdirectories logiche (`lifecycle/`, `drawing/`, `ui/`, `eraser/`). `part of` depth match.
- **Toolbar pattern**: `library` + `part` + extensions. Menus come standalone widgets.
- Lint: `invalid_use_of_protected_member: ignore` per extensions su State.
---
## 2. CONVENZIONI DI CODICE
### Naming
- File: `snake_case.dart` — prefisso `nebula_` (API SDK), `pro_` (modelli professionali).
- Classi: `PascalCase` con prefisso `Nebula` per API pubbliche. Privati: `_prefix`.
### Language — EVERYTHING in English
- **ALL code in English**: names, comments, docstrings, TODOs, error messages. No Italian in new code.
- Emoji markers: 🎨 Drawing, 🚀 Performance, 💾 Storage, ⏱️ Time Travel, 🔄 Sync, 🖼️ Image, 🎛️ Settings, 🔧 Utils, 🎯 Core, 🔮 Recovery.
- Sections: `// ============================================================================`. Principles: `/// DESIGN PRINCIPLES:`.
### Serialization & Schema Versioning
- `toJson()` → `Map<String, dynamic>`, factory `fromJson()`. Campi opzionali con fallback. `toDouble()` per numeri.
- **Schema Versioning** (`schema_version.dart`): `kCurrentSchemaVersion`, `migrateDocument(json)` in `fromJson()`, `SchemaVersionException` per versioni future.
- **Nuova migrazione**: incrementa `kCurrentSchemaVersion`, aggiungi funzione in `_migrations` map con `walkNodes()`.
- SQLite: colonna `schema_version` in `canvases`, scritta ad ogni save.
### State Management
- `ValueNotifier` per real-time (hot path). `ChangeNotifier` per controller. `flutter_riverpod` per stato app (non hot path).
### Error Handling — Enterprise Error Recovery
- **MAI** `catch (_) {}` o `catchError((_))`. Ogni errore DEVE essere osservabile.
- Usa `ErrorRecoveryService`: `EngineScope.current.errorRecovery.reportError(EngineError(...))`.
- `EngineError`: `severity` (.transient/.degraded/.critical), `domain` (.rendering/.storage/.platform/.input/.network/.sceneGraph), `source`, `original`, `stack`.
- **Severity**: transient = retry-safe, degraded = partial loss, critical = subsystem down.
- Eccezione: `compute()` isolate → `debugPrint` fallback. UI-only catches (color parsing) → `debugPrint` accettabile.
- `mounted` check prima di `setState()` in async callbacks.
### Analysis Options
- `invalid_use_of_protected_member: ignore`, `unused_element/field/variable/import: ignore` (Phase 2 stubs).
- `_phase2_disabled/` esclusa dall'analisi.
---
## 3. PERFORMANCE — Regole ferree
- **MAI allocare in `paint()`** — usa `PaintPool` / cache pre-allocate.
- **16ms budget** (60fps). `FrameBudgetManager` per misurare.
- **Viewport culling**: `ViewportCuller` + `SpatialIndex`. MAI iterare tutti gli strokes.
- **Object pooling**: `PathPool`, `StrokePointPool`, `PaintPool`.
- **Dirty regions**: `DirtyRegionTracker` per repaint minimale. `LODManager` a zoom bassi.
- **Isolates**: operazioni pesanti (Time Travel, export) → Isolate. Mai bloccare main thread.
- **Images**: cap 2048px con `_decodeImageCapped()`. Progressive loading.
- **Input**: `RawInputProcessor120Hz`. Predicted touches su iOS.
---
## 4. INTEGRAZIONE
### SDK Usage
```dart
NebulaCanvasScreen(config: NebulaCanvasConfig(
  layerController: ctrl, auth: MyAuth(), storage: MyStorage(), sync: MySync(),
))
```
### Aggiungere una feature
1. Core: modifica in `nebula_engine/lib/src/`
2. Dipendenze Firebase/app: interfaccia astratta, implementa nell'app
3. Export nel barrel `nebula_engine.dart`
4. Aggiorna `ARCHITECTURE.md` se significativo
### Localizzazione
- `NebulaLocalizations` in `l10n/`. MAI hardcodare stringhe. Usa `NebulaLocalizations.of(context).x`.
---
## 5. CRITICAL FILES
| File | Role |
|------|------|
| `nebula_canvas_screen.dart` | Canvas entry point + parts |
| `parts/lifecycle/_lifecycle.dart` | Init, load, dispose |
| `parts/drawing/_drawing_handlers.dart` | Pointer-down/start |
| `parts/drawing/_drawing_update.dart` | Continuous draw update |
| `parts/drawing/_drawing_end.dart` | Stroke finalization |
| `canvas_node.dart` | Base class scene graph |
| `brush_engine.dart` | Unified brush dispatch |
| `drawing_input_handler.dart` | 120Hz input pipeline |
| `nebula_canvas_config.dart` | DI config |
| `layer_controller.dart` | Layer management |
| `nebula_engine.dart` | Barrel export |
---
## 6. CHECKLIST PRE-COMMIT
- [ ] `flutter analyze` clean
- [ ] No import Firebase/app in nebula_engine
- [ ] Nuovi file esportati nel barrel
- [ ] JSON retrocompatibile (campi opzionali con fallback)
- [ ] Zero allocazioni nel hot path
- [ ] Docstrings per API pubbliche
- [ ] `ARCHITECTURE.md` aggiornato se necessario
---
## 7. AUDIT — Regola singola passata
- Quando l'utente chiede un audit/analisi, fai **UNA sola passata completa** a 4 livelli:
  1. **API surface** — metodi mancanti, firma incompleta, naming inconsistente
  2. **Integrazione** — renderer, registry, factory, visitor tutti collegati
  3. **Edge case** — `const` safety, `null` handling, serializzazione roundtrip, error paths
  4. **Test coverage** — test per ogni feature, inclusi roundtrip e edge case
- **MAI** fare audit incrementali ("round 1, round 2..."). Un audit = un documento completo.
