---
description: Regole permanenti per lo sviluppo su fluera_engine — motore grafico 2D professionale Flutter
---
# 🎨 FLUERA ENGINE — Regole di Sviluppo
## 1. ARCHITETTURA
### Scene Graph (core/)
- **Base**: `CanvasNode` — 13 tipi. Aggiungi: sottoclasse → `CanvasNodeFactory.fromJson()` → `SceneGraphRenderer` → `NodeVisitor`.
- **Serializzazione**: `toJson()`/`fromJson()`. MAI rompere retrocompatibilità JSON.
- **Transforms**: `Matrix4` gerarchico. `worldTransform` cachato → `invalidateTransformCache()`.
- **Observer**: `SceneGraphObserver`. **Concurrency**: `_guardedMutation()`, `snapshotVersion()`+`assertUnchanged()`.
- **Integrity**: 7 checks, 3 auto-repairs. `validate()` puro, `validateAndRepair()` → `ErrorRecoveryService`.
### DI — **MAI** importare Firebase/auth/servizi app dentro `fluera_engine`. DI via `FlueraCanvasConfig`.
### Tools — Implementa `DrawingTool` (stateless). Logica in `ToolContext`/`CanvasAdapter`. Registra in `ToolRegistry`.
### Selection — `SelectionManager` è **single source of truth**. MAI set paralleli.
### Design Systems (systems/)
- Dev Handoff: `InspectEngine`, `CodeGenerator`, `TokenResolver`, `AssetManifest`, `RedlineCalculator`.
- States: `ComponentStateMachine`+`ComponentStateResolver`. Tokens: `SemanticTokenRegistry`+`ThemeManager`.
- Animation: `SpringSimulation`, `MotionPath`, `StaggerAnimation`. Typography: `VariableFontConfig`, `OpenTypeConfig`, `TextAutoResizeEngine`.
- Image: `ImageAdjustmentConfig`, `FillConfig`. ⚠️ Design Tab: SDK-only, non esposto in toolbar.
### Drawing Pipeline
- `DrawingInputHandler` → 1€ Filter → predicted touches → pressure normalization.
- `BrushEngine` è l'**UNICO** dispatch pen→brush. MAI duplicare switch(penType).
- Aggiungere brush: classe + case in `ProPenType` + `BrushEngine.renderStroke()`.
### Rendering
- Painters: `DrawingPainter`, `CurrentStrokePainter`, `BackgroundPainter`, `ShapePainter`.
- Optimization: `SpatialIndex`, `TileCacheManager`, `ViewportCuller`, `LODManager`, `PaintPool`, `FrameBudgetManager`.
- **16ms budget**, zero allocazioni in paint(), usa `PaintPool`.
### Fluidity Pipeline (8 subsystems)
- **Predictive Stroke**: quadratic extrapolation, ghost trail. Guard: `enablePredictive`.
- **Gesture Coalescing**: `_addToBatch()`/`_flushBatch()` + `addPostFrameCallback` → O(1) repaint.
- **LOD Cross-Fade**: `_drawFallbackTile()` — adjacent LOD fallback with source-rect cropping.
- **Zoom Momentum**: `FrictionSimulation` on log-scale. Auto spring-back on limit.
- **Chunked Raster**: max 80 strokes/chunk, progressive compositing.
- **Variable Frame Budget**: auto-detect refresh rate. 8ms@60Hz, 4ms@120Hz.
- **Adaptive Filter**: continuous `reactivityNeed` curve. β 1x→6x, minCutoff 1x→4x.
- **Isolate Raster**: `serializeStrokes()` → `Isolate.run()` → `Float32List`. For 100+ strokes.
### File Limits: soft 500 LOC, hard 1000 LOC, preferred 200–400. `part`+extension per State privati.
---
## 2. CONVENZIONI
- **File**: `snake_case.dart`, prefisso `fluera_` (API), `pro_` (modelli). **Classi**: `PascalCase`, prefisso `Fluera` pubbliche.
- **ALL code in English**. No Italian in new code.
- **Serialization**: `toJson()`→`Map<String,dynamic>`, factory `fromJson()`. Campi opzionali con fallback.
- **Schema**: `kCurrentSchemaVersion`, `migrateDocument()`, `SchemaVersionException`.
- **State**: `ValueNotifier` (hot path), `ChangeNotifier` (controller), `flutter_riverpod` (app state).
- **Errors**: MAI `catch(_){}`. `ErrorRecoveryService.reportError(EngineError(severity, domain))`.
- **Lint**: `invalid_use_of_protected_member: ignore`, `unused_*: ignore` (Phase 2 stubs).
---
## 3. PERFORMANCE
- **MAI allocare in `paint()`** — usa `PaintPool`/cache. **16ms budget**.
- **Viewport culling**: `ViewportCuller`+`SpatialIndex`. MAI iterare tutti gli strokes.
- **Object pooling**: `PathPool`, `StrokePointPool`, `PaintPool`. **Dirty regions**: `DirtyRegionTracker`.
- **Isolates**: operazioni pesanti → Isolate. **Images**: cap 2048px. **Input**: 120Hz.
---
## 4. INTEGRAZIONE
```dart
FlueraCanvasScreen(config: FlueraCanvasConfig(
  layerController: ctrl, auth: MyAuth(), storage: MyStorage(), sync: MySync(),
))
```
Feature: core in `fluera_engine/lib/src/`, Firebase/app via interfaccia astratta, export in barrel.
Localizzazione: `FlueraLocalizations.of(context).x`. MAI hardcodare stringhe.
---
## 5. CRITICAL FILES
| File | Role |
|------|------|
| `fluera_canvas_screen.dart` | Canvas entry point + parts |
| `canvas_node.dart` | Base class scene graph |
| `brush_engine.dart` | Unified brush dispatch |
| `drawing_input_handler.dart` | 120Hz input pipeline |
| `fluera_canvas_config.dart` | DI config |
| `layer_controller.dart` | Layer management |
| `predictive_renderer.dart` | Quadratic stroke prediction |
| `one_euro_filter.dart` | Adaptive 1€ filter |
| `frame_budget_manager.dart` | Dynamic refresh-rate budgeting |
| `isolate_geometry_worker.dart` | Isolate path tessellation |
| `infinite_canvas_controller.dart` | Zoom/pan/rotation physics |
| `tile_cache_manager.dart` | LOD cross-fade + chunked raster |
---
## 6. CHECKLIST PRE-COMMIT
- [ ] `flutter analyze` clean
- [ ] No import Firebase/app in fluera_engine
- [ ] Nuovi file esportati nel barrel
- [ ] JSON retrocompatibile
- [ ] Zero allocazioni nel hot path
- [ ] Docstrings per API pubbliche
---
## 7. AUDIT
- **UNA sola passata** a 4 livelli: API surface, Integrazione, Edge case, Test coverage. MAI audit incrementali.
- **Trigger**: solo su richiesta esplicita utente o pre-commit finale. MAI durante fix a catena.
---
## 8. 🔒 NUCLEO BLINDATO
**⛔ MAI modificare senza richiesta esplicita. ⛔ MAI "migliorare" codice funzionante.**
✅ OK: test, nuovi file che importano blindati, fix bug con test che falliscono. 🔧 Prima di toccare: chiedere conferma.

**Scene Graph** (`core/scene_graph/`): `canvas_node`, `scene_graph`, `invalidation_graph`, `node_visitor`, `scene_graph_transaction`, `transform_bridge`, `node_id`, `node_constraint`, `scene_graph_observer`, `frozen_node_view`, `read_only_scene_graph`, `scene_graph_snapshot`, `canvas_node_factory`, `scene_graph_integrity`, `scene_graph_interceptor`, `paint_stack_mixin`, `debug_info`, `scene_graph_savepoint`

**Systems** (`systems/`): `component_state_machine`, `component_state_resolver`, `semantic_token`, `theme_manager`, `spring_simulation`, `path_motion`, `stagger_animation`, `variable_font`, `opentype_features`, `text_auto_resize`, `image_adjustment`, `image_fill_mode`, `dev_handoff/*`

**Nodes** (`core/nodes/`): `group_node`, `layer_node`, `shape_node`, `stroke_node`, `text_node`, `image_node`, `clip_group_node`, `path_node`, `rich_text_node`, `frame_node`, `advanced_mask_node`, `boolean_group_node`, `symbol_system`, `variant_property`, `pdf_page_node`, `pdf_document_node`, `vector_network_node`, `latex_node`

**Rendering** (`rendering/`): `scene_graph_renderer`, `render_plan`, `render_interceptor`, `render_batch`, `path_renderer`, `rich_text_renderer`, `latex_renderer`, `vector_network_renderer`, `network_lod`, `occlusion_culler`, `dirty_region_tracker`, `layer_picture_cache`, `snapshot_cache_manager`, `spatial_index`, `viewport_culler`, `tile_cache_manager`, `stroke_cache_manager`, `frame_budget_manager`, `lod_manager`, `memory_budget_controller`, `memory_managed_cache`, `paint_pool`, `optimized_path_builder`, `stroke_optimizer`, `isolate_geometry_worker`, `drawing_painter`, `incremental_paint_mixin`, `current_stroke_painter`, `shape_painter`, `pro_stroke_painter`, `pdf_page_painter`, `image_painter`, `digital_text_painter`
---
## 9. ARCHITETTURA CONSAPEVOLE
### Livelli di Intelligenza
- **L0 Fluido**: 60 FPS, 8 sottosistemi. COMPLETO.
- **L1 Anticipatorio**: `anticipatory_tile_prefetch`, `predictive_renderer`, `lod_manager`.
- **L2 Adattivo**: `adaptive_profile`, `one_euro_filter`, `frame_budget_manager`, `liquid_canvas_config`.
- **L3 Invisibile**: `smart_snap_engine`, `smart_animate_engine`, `plugin_api`, `accessibility_bridge`.
- **L4 Generativo**: `onnx_latex_recognizer`, `design_linter`.
### Contratto: ogni sottosistema `extends IntelligenceSubsystem` (`conscious_architecture.dart`). Registro: `ConsciousArchitecture` in `EngineScope`. Lifecycle: `onContextChanged()` + `onIdle()` + `dispose()`.
### Nuovo Sottosistema: classe → `extends IntelligenceSubsystem` → dichiarare `layer`+`name` → impl `onContextChanged()`+`onIdle()` → registrare in `EngineScope` → aggiornare `ARCHITECTURE.md`.
---
## 10. 🛑 ERROR RECOVERY (Anti-Loop)
- **Regola dei 2 tentativi**: se un fix causa un nuovo errore, max 2 tentativi. Al 3° → **STOP**, mostra errore esatto + tentativi fatti, chiedi indicazioni.
- MAI fix a catena su Nucleo Blindato (§8).
- Se `flutter analyze` fallisce: import/typo → fix diretto (tentativo 1). Errore tipo/architettura → **STOP**, chiedi conferma.
- MAI provare soluzioni a raffica. Ogni tentativo deve essere ragionato.
- **Regressioni**: se un fix rompe qualcosa che funzionava → **revert immediato** e segnala. MAI edificare sopra codice rotto.
---
## 11. 📋 MODIFICATION PATTERNS
**Nuovo Nodo**: sottoclasse `CanvasNode` → `CanvasNodeFactory.fromJson()` → `toJson()`/`fromJson()` retrocompatibile → `NodeVisitor` → renderer → `SceneGraphRenderer` → barrel export.
**Nuovo Brush**: classe brush → case `ProPenType` → case `BrushEngine.renderStroke()` (UNICO dispatch) → barrel export.
**Nuovo Painter**: classe in `rendering/canvas/` → 16ms budget + `PaintPool` → `ViewportCuller` → registrare nel pipeline.
**Feature Esterna**: interfaccia astratta in `fluera_engine/lib/src/` → impl fuori engine → iniettare via `FlueraCanvasConfig` → MAI import esterni.
---
## 12. ⚖️ PRIORITY HIERARCHY
Conflitto tra regole? Gerarchia (alta→bassa): **1.Stabilità** (revert > fix creativo) → **2.Performance** (16ms, zero alloc) → **3.Retrocompatibilità** (JSON, API) → **4.Architettura** (DI, Nucleo Blindato) → **5.Convenzioni** (naming, lint) → **6.Nuove feature**.
---
## 13. 🗺️ DEPENDENCY MAP
Modifichi un file critico? Verifica **sempre** i dipendenti:
| Modificato | Verifica |
|-----------|----------|
| `canvas_node` | `canvas_node_factory`, `scene_graph_renderer`, `node_visitor`, `scene_graph`, `frozen_node_view` |
| `scene_graph` | `scene_graph_transaction`, `scene_graph_observer`, `scene_graph_integrity`, `scene_graph_snapshot` |
| `brush_engine` | `drawing_input_handler`, `current_stroke_painter`, `pro_stroke_painter` |
| `drawing_input_handler` | `one_euro_filter`, `predictive_renderer`, `infinite_canvas_gesture_detector` |
| `tile_cache_manager` | `lod_manager`, `spatial_index`, `isolate_geometry_worker`, `viewport_culler` |
| `infinite_canvas_controller` | `tile_cache_manager`, `viewport_culler`, `frame_budget_manager` |
| `layer_controller` | `scene_graph`, `drawing_painter`, `fluera_canvas_screen` |
| `selection_manager` | `fluera_canvas_screen`, `scene_graph_transaction` |
| `fluera_canvas_config` | `fluera_canvas_screen` — ogni campo aggiunto deve avere fallback |