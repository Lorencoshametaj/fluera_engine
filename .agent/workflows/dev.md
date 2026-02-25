---
description: Regole permanenti per lo sviluppo su nebula_engine — motore grafico 2D professionale Flutter
---

# 🎨 NEBULA ENGINE — Regole di Sviluppo
## 1. ARCHITETTURA
### Scene Graph (core/)
- **Base**: `CanvasNode` — 13 tipi. Aggiungi: sottoclasse → `CanvasNodeFactory.fromJson()` → `SceneGraphRenderer` → `NodeVisitor`.
- **Serializzazione**: `toJson()`/`fromJson()`. MAI rompere retrocompatibilità JSON.
- **Transforms**: `Matrix4` gerarchico. `worldTransform` cachato → `invalidateTransformCache()`.
- **Observer**: `SceneGraphObserver`. **Concurrency**: `_guardedMutation()`, `snapshotVersion()`+`assertUnchanged()`.
- **Integrity**: 7 checks, 3 auto-repairs. `validate()` puro, `validateAndRepair()` → `ErrorRecoveryService`.
### Dependency Inversion
- **MAI** importare Firebase/auth/servizi app dentro `nebula_engine`. DI via `NebulaCanvasConfig`.
### Tool System (tools/)
- Implementa `DrawingTool`. Tool **stateless** — logica in `ToolContext`/`CanvasAdapter`. Registra in `ToolRegistry`.
### Selection (`SelectionManager`)
- **Single source of truth**. MAI set paralleli. API: select/clear/marquee/transform/align/distribute/delete/duplicate.
### Design Systems (systems/)
- **Dev Handoff**: `InspectEngine`, `CodeGenerator`, `TokenResolver`, `AssetManifest`, `RedlineCalculator`.
- **States**: `ComponentStateMachine`+`ComponentStateResolver`. **Tokens**: `SemanticTokenRegistry`+`ThemeManager`.
- **Animation**: `SpringSimulation`, `MotionPath`, `StaggerAnimation`.
- **Typography**: `VariableFontConfig`, `OpenTypeConfig`, `TextAutoResizeEngine`.
- **Image**: `ImageAdjustmentConfig`, `FillConfig`. **⚠️ Design Tab**: SDK-only, non esposto in toolbar.
### Drawing Pipeline (drawing/)
- `DrawingInputHandler` → 1€ Filter → predicted touches → pressure normalization.
- `BrushEngine` è l'**UNICO** dispatch pen→brush. MAI duplicare switch(penType).
- Aggiungere brush: classe + case in `ProPenType` + `BrushEngine.renderStroke()`.
- Modelli: `ProDrawingPoint` (position, pressure, tilt, orientation, timestamp), `ProBrushSettings`.
### Rendering (rendering/)
- Painters: `DrawingPainter`, `CurrentStrokePainter`, `BackgroundPainter`, `ShapePainter`.
- Optimization: `SpatialIndex`, `TileCacheManager`, `ViewportCuller`, `LODManager`, `PaintPool`, `FrameBudgetManager`.
- **Performance critica**: 16ms budget, zero allocazioni in paint(), usa `PaintPool`.
### Fluidity Pipeline (8 subsystems)
- **Predictive Stroke** (`predictive_renderer.dart`): quadratic extrapolation, ghost trail in `CurrentStrokePainter`. Guard: `enablePredictive`.
- **Gesture Coalescing** (`infinite_canvas_gesture_detector.dart`): `_addToBatch()`/`_flushBatch()` + `addPostFrameCallback` → O(1) repaint.
- **LOD Cross-Fade** (`tile_cache_manager.dart`): `_drawFallbackTile()` — adjacent LOD fallback with source-rect cropping.
- **Zoom Momentum** (`infinite_canvas_controller.dart`): `startZoomMomentum()` — `FrictionSimulation` on log-scale. Auto spring-back on limit.
- **Chunked Rasterization** (`tile_cache_manager.dart`): `rasterizeTileChunked()` max 80 strokes/chunk, progressive compositing.
- **Variable Frame Budget** (`frame_budget_manager.dart`): auto-detect refresh rate (median frame deltas). 8ms@60Hz, 4ms@120Hz.
- **Adaptive Filter** (`one_euro_filter.dart`): continuous `reactivityNeed` curve. β 1x→6x, minCutoff 1x→4x.
- **Isolate Rasterization** (`isolate_geometry_worker.dart`): `serializeStrokes()` → `Isolate.run()` → `Float32List` paths. `rasterizeTileAsync()` for 100+ strokes.
### File Organization
- **Limiti**: soft 500 LOC, hard 1000 LOC, preferred 200–400 LOC.
- `part`+extension per State privati, standalone per logica pura. UI: Material 3. Toolbar: `library`+`part`+extensions.
---
## 2. CONVENZIONI
- **File**: `snake_case.dart`, prefisso `nebula_` (API), `pro_` (modelli). **Classi**: `PascalCase`, prefisso `Nebula` pubbliche.
- **ALL code in English**. No Italian in new code.
- **Serialization**: `toJson()`→`Map<String,dynamic>`, factory `fromJson()`. Campi opzionali con fallback.
- **Schema**: `kCurrentSchemaVersion`, `migrateDocument()`, `SchemaVersionException`. SQLite: colonna `schema_version`.
- **State**: `ValueNotifier` (hot path), `ChangeNotifier` (controller), `flutter_riverpod` (app state).
- **Errors**: MAI `catch(_){}`. `ErrorRecoveryService.reportError(EngineError(severity, domain))`.
- **Lint**: `invalid_use_of_protected_member: ignore`, `unused_*: ignore` (Phase 2 stubs).
---
## 3. PERFORMANCE
- **MAI allocare in `paint()`** — usa `PaintPool`/cache. **16ms budget**. `FrameBudgetManager` per misurare.
- **Viewport culling**: `ViewportCuller`+`SpatialIndex`. MAI iterare tutti gli strokes.
- **Object pooling**: `PathPool`, `StrokePointPool`, `PaintPool`. **Dirty regions**: `DirtyRegionTracker`.
- **Isolates**: operazioni pesanti → Isolate. **Images**: cap 2048px, progressive loading. **Input**: 120Hz.
---
## 4. INTEGRAZIONE
```dart
NebulaCanvasScreen(config: NebulaCanvasConfig(
  layerController: ctrl, auth: MyAuth(), storage: MyStorage(), sync: MySync(),
))
```
Aggiungere feature: core in `nebula_engine/lib/src/`, Firebase/app via interfaccia astratta, export in barrel.
Localizzazione: `NebulaLocalizations.of(context).x`. MAI hardcodare stringhe.
---
## 5. CRITICAL FILES
| File | Role |
|------|------|
| `nebula_canvas_screen.dart` | Canvas entry point + parts |
| `canvas_node.dart` | Base class scene graph |
| `brush_engine.dart` | Unified brush dispatch |
| `drawing_input_handler.dart` | 120Hz input pipeline |
| `nebula_canvas_config.dart` | DI config |
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
- [ ] No import Firebase/app in nebula_engine
- [ ] Nuovi file esportati nel barrel
- [ ] JSON retrocompatibile
- [ ] Zero allocazioni nel hot path
- [ ] Docstrings per API pubbliche
---
## 7. AUDIT
- **UNA sola passata** a 4 livelli: API surface, Integrazione, Edge case, Test coverage. MAI audit incrementali.
---
## 8. 🔒 NUCLEO BLINDATO
### Core Scene Graph (`lib/src/core/scene_graph/`)
`canvas_node.dart`, `scene_graph.dart`, `invalidation_graph.dart`, `node_visitor.dart`, `scene_graph_transaction.dart`, `transform_bridge.dart`, `node_id.dart`, `node_constraint.dart`, `scene_graph_observer.dart`, `frozen_node_view.dart`, `read_only_scene_graph.dart`, `scene_graph_snapshot.dart`, `canvas_node_factory.dart`, `scene_graph_integrity.dart`, `scene_graph_interceptor.dart`, `paint_stack_mixin.dart`, `debug_info.dart`, `scene_graph_savepoint.dart`
### Design Systems (`lib/src/systems/`)
`component_state_machine.dart`, `component_state_resolver.dart`, `semantic_token.dart`, `theme_manager.dart`, `spring_simulation.dart`, `path_motion.dart`, `stagger_animation.dart`, `variable_font.dart`, `opentype_features.dart`, `text_auto_resize.dart`, `image_adjustment.dart`, `image_fill_mode.dart`, `dev_handoff/inspect_engine.dart`, `dev_handoff/code_generator.dart`, `dev_handoff/token_resolver.dart`, `dev_handoff/asset_manifest.dart`, `dev_handoff/redline_overlay.dart`
### Core Nodes (`lib/src/core/nodes/`)
`group_node.dart`, `layer_node.dart`, `shape_node.dart`, `stroke_node.dart`, `text_node.dart`, `image_node.dart`, `clip_group_node.dart`, `path_node.dart`, `rich_text_node.dart`, `frame_node.dart`, `advanced_mask_node.dart`, `boolean_group_node.dart`, `symbol_system.dart`, `variant_property.dart`, `pdf_page_node.dart`, `pdf_document_node.dart`, `vector_network_node.dart`, `latex_node.dart`
### Rendering (`lib/src/rendering/scene_graph/` + `optimization/` + `canvas/`)
`scene_graph_renderer.dart`, `render_plan.dart`, `render_interceptor.dart`, `render_batch.dart`, `path_renderer.dart`, `rich_text_renderer.dart`, `latex_renderer.dart`, `vector_network_renderer.dart`, `network_lod.dart`, `occlusion_culler.dart`, `dirty_region_tracker.dart`, `layer_picture_cache.dart`, `snapshot_cache_manager.dart`, `spatial_index.dart`, `viewport_culler.dart`, `tile_cache_manager.dart`, `stroke_cache_manager.dart`, `frame_budget_manager.dart`, `lod_manager.dart`, `memory_budget_controller.dart`, `memory_managed_cache.dart`, `paint_pool.dart`, `optimized_path_builder.dart`, `stroke_optimizer.dart`, `isolate_geometry_worker.dart`, `drawing_painter.dart`, `incremental_paint_mixin.dart`, `current_stroke_painter.dart`, `shape_painter.dart`, `pro_stroke_painter.dart`, `pdf_page_painter.dart`, `image_painter.dart`, `digital_text_painter.dart`
### Regole:
- ⛔ MAI modificare senza richiesta esplicita. ⛔ MAI "migliorare" codice funzionante.
- ✅ OK: aggiungere test, nuovi file che importano blindati, fix bug con test che falliscono.
- 🔧 Prima di toccare: chiedere conferma, spiegare impatto.
---
## 9. ARCHITETTURA CONSAPEVOLE
### Cinque Livelli di Intelligenza
- **L0 — Fluido**: 60 FPS, 8 sottosistemi (§8 Fluidity Pipeline). COMPLETO.
- **L1 — Anticipatorio**: Predice l'intento utente. File: `anticipatory_tile_prefetch.dart`, `predictive_renderer.dart`, `lod_manager.dart`.
- **L2 — Adattivo**: Si regola al contesto. File: `adaptive_profile.dart`, `one_euro_filter.dart`, `frame_budget_manager.dart`, `liquid_canvas_config.dart`.
- **L3 — Invisibile**: La tecnologia scompare. File: `smart_snap_engine.dart`, `smart_animate_engine.dart`, `plugin_api.dart`, `accessibility_bridge.dart`.
- **L4 — Generativo**: Co-crea con l'utente. File: `onnx_latex_recognizer.dart`, `design_linter.dart`.
### Contratto
- Ogni sottosistema implementa `IntelligenceSubsystem` (`conscious_architecture.dart`).
- Registro: `ConsciousArchitecture` in `EngineScope.consciousArchitecture`.
- Lifecycle: `onContextChanged(EngineContext)` + `onIdle(Duration)` + `dispose()`.
### Aggiungere un Sottosistema
1. Classe → `extends IntelligenceSubsystem`
2. Dichiarare `layer` e `name`
3. Implementare `onContextChanged()` e `onIdle()`
4. Registrare in `EngineScope` o all'inizializzazione del canvas
5. Aggiornare `ARCHITECTURE.md`