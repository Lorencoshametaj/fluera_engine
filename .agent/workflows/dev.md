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
- **Integrity**: 7 checks, 3 auto-repairs. `validate()` puro, `validateAndRepair()` → `ErrorRecoveryService`. `fromJson()` asserts `violations.isEmpty`.
- **Concurrency**: `_guardedMutation()` anti-reentrant. `List.of(_observers)` snapshot. `snapshotVersion()` + `assertUnchanged()` per async gaps.
### Dependency Inversion (SDK ↔ App)
- **MAI** importare Firebase/auth/servizi app dentro `nebula_engine`.
- DI via `NebulaCanvasConfig`. Interfacce sync in `nebula_sync_interfaces.dart`. Provider in `nebula_canvas_config.dart`.
### Tool System (tools/)
- Implementa `DrawingTool` (`tool_interface.dart`). Tool sono **stateless** — logica in `ToolContext`/`CanvasAdapter`.
- Aggiungi tool: implementa `DrawingTool`, registra in `ToolRegistry`. Mixin: `SelectionToolMixin`, `ContinuousDrawingMixin`.
### Selection System (systems/selection_manager.dart)
- **Single source of truth**: `SelectionManager` gestisce TUTTO. MAI set paralleli.
- API: `select/All()`, `clear()`, `marquee()`, `translate/rotate/scale/flipH/V()`, `align*()`, `distributeH/V()`, `delete/duplicateAll()`.
### Design Systems (systems/)
- **Dev Handoff** (`dev_handoff/`): `InspectEngine`, `CodeGenerator` (Flutter/CSS/SwiftUI), `TokenResolver`, `AssetManifest`, `RedlineCalculator`. Nuovo target codegen → metodo in `CodeGenerator`.
- **Component States**: `ComponentStateMachine` + `ComponentStateResolver`. Cascata: definition defaults → state map → instance overrides.
- **Semantic Tokens**: `SemanticTokenRegistry` (alias chaining, circular detection). `ThemeManager` (switching, scaffolding light/dark). MAI alias circolari.
- **Animation**: `SpringSimulation` (3 damping), `MotionPath` (arc-length), `StaggerAnimation` (5 orderings).
- **Typography**: `VariableFontConfig` (6 assi), `OpenTypeConfig` (presets+merge), `TextAutoResizeEngine` (4 modi).
- **Image**: `ImageAdjustmentConfig` (6 regolazioni, 5×4 color matrix), `FillConfig` (5 fill modes).
- **⚠️ Design Tab**: SDK-only. NON esposto nella toolbar Looponia (features da design tool, non note-taking). Tab enum esiste ma `_availableTabs` lo esclude. Moduli restano nel codice per uso libreria.
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
- **UI**: Material design 3
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
- **MAI** `catch (_) {}`. Ogni errore osservabile via `ErrorRecoveryService.reportError(EngineError(...))`.
- `EngineError`: severity (.transient/.degraded/.critical), domain (.rendering/.storage/.platform/.input/.network/.sceneGraph).
- Eccezione: `compute()` isolate → `debugPrint`. `mounted` check prima di `setState()` async.
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
| `dev_handoff/inspect_engine.dart` | Node inspection + measurement |
| `component_state_machine.dart` | Interactive state management |
| `semantic_token.dart` | Semantic token alias resolution |
| `theme_manager.dart` | Theme switching + scaffolding |
| `spring_simulation.dart` | Spring physics simulation |
| `image_adjustment.dart` | Non-destructive image adjustments |
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
---
## 8. 🔒 NUCLEO GRAFICO BLINDATO
I seguenti moduli sono **BLINDATI**. Non modificarli MAI senza esplicita richiesta dell'utente.
### Core Scene Graph (`lib/src/core/scene_graph/`)
`canvas_node.dart`, `scene_graph.dart`, `invalidation_graph.dart`, `node_visitor.dart`, `scene_graph_transaction.dart`, `transform_bridge.dart`, `node_id.dart`, `node_constraint.dart`, `scene_graph_observer.dart`, `frozen_node_view.dart`, `read_only_scene_graph.dart`, `scene_graph_snapshot.dart`, `canvas_node_factory.dart`, `scene_graph_integrity.dart`, `scene_graph_interceptor.dart`, `paint_stack_mixin.dart`, `debug_info.dart`, `scene_graph_savepoint.dart`
### Design Systems (`lib/src/systems/`)
`component_state_machine.dart`, `component_state_resolver.dart`, `semantic_token.dart`, `theme_manager.dart`, `spring_simulation.dart`, `path_motion.dart`, `stagger_animation.dart`, `variable_font.dart`, `opentype_features.dart`, `text_auto_resize.dart`, `image_adjustment.dart`, `image_fill_mode.dart`, `dev_handoff/inspect_engine.dart`, `dev_handoff/code_generator.dart`, `dev_handoff/token_resolver.dart`, `dev_handoff/asset_manifest.dart`, `dev_handoff/redline_overlay.dart`
### Core Nodes (`lib/src/core/nodes/`)
`group_node.dart`, `layer_node.dart`, `shape_node.dart`, `stroke_node.dart`, `text_node.dart`, `image_node.dart`, `clip_group_node.dart`, `path_node.dart`, `rich_text_node.dart`, `frame_node.dart`, `advanced_mask_node.dart`, `boolean_group_node.dart`, `symbol_system.dart`, `variant_property.dart`, `pdf_page_node.dart`, `pdf_document_node.dart`, `vector_network_node.dart`, `latex_node.dart`
### Rendering Pipeline (`lib/src/rendering/scene_graph/`)
`scene_graph_renderer.dart`, `render_plan.dart`, `render_interceptor.dart`, `render_batch.dart`, `path_renderer.dart`, `rich_text_renderer.dart`, `latex_renderer.dart`, `vector_network_renderer.dart`, `network_lod.dart`
### Optimization (`lib/src/rendering/optimization/`)
`occlusion_culler.dart`, `dirty_region_tracker.dart`, `layer_picture_cache.dart`, `snapshot_cache_manager.dart`, `spatial_index.dart`, `viewport_culler.dart`, `tile_cache_manager.dart`, `stroke_cache_manager.dart`, `frame_budget_manager.dart`, `lod_manager.dart`, `memory_budget_controller.dart`, `memory_managed_cache.dart`, `paint_pool.dart`, `optimized_path_builder.dart`, `stroke_optimizer.dart`
### Canvas Painters (`lib/src/rendering/canvas/`)
`drawing_painter.dart`, `incremental_paint_mixin.dart`, `current_stroke_painter.dart`, `shape_painter.dart`, `pro_stroke_painter.dart`, `pdf_page_painter.dart`, `image_painter.dart`, `digital_text_painter.dart`
### Regole:
- ⛔ MAI modificare senza richiesta esplicita. ⛔ MAI "migliorare" codice funzionante.
- ✅ OK: aggiungere test, nuovi file che importano blindati, fix bug con test che falliscono.
- 🔧 Prima di toccare: chiedere conferma, spiegare impatto.