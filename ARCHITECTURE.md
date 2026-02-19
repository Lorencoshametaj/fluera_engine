# Scene Graph Engine — Architecture

Motore 2D professionale costruito in 6 fasi incrementali, 100% retrocompatibile.

---

## Directory Structure

```
├── core/              ← Fondamenta
│   ├── canvas_node.dart         Base astratta: transform, opacity, blend, hit-test
│   ├── canvas_node_factory.dart  Deserializzazione polimorfica da JSON
│   └── scene_graph.dart          Container root con lista LayerNode
│
├── nodes/             ← Tipi di nodo
│   ├── group_node.dart          Container con figli ordinati
│   ├── layer_node.dart          Layer = GroupNode + metadati legacy (adapter)
│   ├── shape_node.dart          Forme geometriche (rettangoli, cerchi, etc.)
│   ├── stroke_node.dart         Pennellate (ink strokes) con BrushEngine
│   ├── text_node.dart           Testo semplice (wraps DigitalTextElement)
│   ├── image_node.dart          Immagini raster
│   ├── clip_group_node.dart     Clipping masks (path clip / alpha mask)
│   ├── path_node.dart           Path vettoriali con fill/stroke/gradients
│   ├── rich_text_node.dart      Testo multi-span con paragrafi e text-on-path
│   ├── symbol_system.dart       Simboli riutilizzabili (definition + instance + registry)
│   ├── frame_node.dart          Auto Layout container (padding, spacing, constraints)
│   └── advanced_mask_node.dart  Maschere avanzate (6 tipi: alpha, intersection, exclusion, luminance, silhouette)
│
├── vector/            ← Editing vettoriale
│   ├── vector_path.dart         Segmenti Bézier (line, quad, cubic)
│   ├── anchor_point.dart        Punti di ancoraggio con handle di controllo
│   ├── shape_presets.dart       11 forme predefinite (stella, poligono, freccia, etc.)
│   └── boolean_ops.dart         Operazioni booleane (union, subtract, intersect, XOR)
│
├── effects/           ← Effetti non-distruttivi
│   ├── node_effect.dart         5 effetti: Blur, DropShadow, InnerShadow, OuterGlow, ColorOverlay
│   ├── gradient_fill.dart       3 tipi: Linear, Radial, Conic con color stops
│   ├── mesh_gradient.dart       Mesh gradient N×M con Coons patch e tessellazione
│   └── shader_effect.dart       GPU shader system (8 preset, uniforms, ShaderNode)
│
├── systems/           ← Sistemi standalone
│   ├── smart_snap_engine.dart   6 tipi di snap: bordi, centri, distribuzione, griglia, angolo, dimensione
│   ├── animation_timeline.dart  Keyframes, tracks, timeline con interpolazione e 5 curve di easing
│   ├── command_history.dart     Undo/redo con Command pattern, coalescing, batch
│   ├── selection_manager.dart   Multi-selezione, aggregate bounds, group transforms, allineamento
│   ├── export_pipeline.dart     Esportazione PNG (1x/2x/3x), SVG
│   ├── dirty_tracker.dart       Dirty tracking con propagazione a parent, minimal repaint region
│   ├── spatial_index.dart       R-tree per viewport culling O(log n) e hit testing
│   ├── style_system.dart        Design tokens (colori, tipografia, spacing) + stili riutilizzabili con linking
│   ├── prototype_flow.dart      Prototyping: link, transizioni, trigger, schermate, flow navigation
│   ├── plugin_api.dart          Plugin/extension API con capabilities, sandbox, registry
│   └── accessibility_tree.dart  Accessibility tree con 15 ruoli semantici, reading order, focus
│
└── renderers/         ← Rendering del scene graph
    ├── scene_graph_renderer.dart Traversal ricorsivo con compositing, effetti, viewport culling
    ├── path_renderer.dart        Rendering path vettoriali (fill + stroke + gradient)
    └── rich_text_renderer.dart   Layout e painting testo ricco via TextPainter
```

---

## Fasi di Implementazione

### Fase 1 — Scene Graph + Transform System
- `CanvasNode` base astratta con transform gerarchico (`Matrix4`)
- Hit testing con matrice inversa, bounds locali/mondiali
- `GroupNode`, `LayerNode`, `ShapeNode`, `StrokeNode`, `TextNode`, `ImageNode`
- `SceneGraph` root container, `CanvasNodeFactory` per deserializzazione
- Adapter `CanvasLayer` ↔ `LayerNode` per retrocompatibilità

### Fase 2 — Compositing + Gradients
- `GradientFill` con 3 tipi (linear, radial, conic) e color stops illimitati
- `ClipGroupNode` con path clip e alpha mask
- Compositing integrato nel renderer (opacity, blend mode, saveLayer)

### Fase 3 — Vector Path Editing
- `VectorPath` con segmenti Bézier (linea, quadratica, cubica)
- `AnchorPoint` con handle di controllo (mirrored, free, auto-smooth)
- `PathNode` con fill/stroke indipendenti + gradient shader
- `ShapePresets`: 11 forme parametriche
- `PathRenderer` per rendering vettoriale

### Fase 4 — Non-Destructive Effects
- `NodeEffect` base con 5 implementazioni concrete
- Stack di effetti per nodo (`List<NodeEffect>` su `CanvasNode`)
- Pre-effects (DropShadow, OuterGlow) e post-effects (Blur, ColorOverlay, InnerShadow)
- Serializzazione/deserializzazione completa

### Fase 5 — Rich Text + Smart Snapping
- `RichTextNode` con spans multi-stile, proprietà paragrafo, text-on-path
- `RichTextRenderer` con TextPainter e background fill
- `SmartSnapEngine` con 6 tipi di snap e soglia configurabile

### Fase 6 — Symbols, Animation, Multi-thread Rendering
- **Symbols**: `SymbolDefinition` (master) + `SymbolInstanceNode` (istanza con overrides) + `SymbolRegistry`
- **Animation**: `Keyframe` + `AnimationTrack` + `AnimationTimeline` + `PropertyInterpolator` con 5 curve di easing
- **Multi-thread**: `RenderTask` + `TileCache` LRU + `RenderIsolatePool` (architettura pronta per Isolate spawning)

### Fase 7 — Professional Core Features
- **Undo/Redo**: `Command` pattern con `CommandHistory` (undo/redo illimitato, coalescing per drag, batch commands). 10 comandi concreti (Move, Position, Transform, Add, Delete, Reorder, PropertyChange, Opacity, Visibility, Lock)
- **Multi-Selezione**: `SelectionManager` con aggregate bounds, group transforms (translate/rotate/scale), marquee select, 6 allineamenti, distribuzione H/V, filtri per tipo
- **Boolean Ops**: Union, subtract, intersect, XOR via `Path.combine`. Path overlap detection, multi-path flatten, Flutter Path → VectorPath conversion
- **Auto Layout**: `FrameNode extends GroupNode` con `LayoutConstraint` per figlio (fill/fixed/hug, pin, flex-grow). Layout solver 3-pass con main/cross axis alignment e space distribution
- **Export Pipeline**: PNG (1x/2x/3x DPI), SVG (scene graph → SVG DOM). Export per nodo singolo, selezione, o intero scene graph

### Fase 8 — Performance & Design Systems
- **Dirty Tracking**: `DirtyTracker` con propagazione a parent, old-bounds tracking, dirty region computation (minimal repaint rect), per-layer dirty checking
- **Spatial Index**: R-tree con insert/remove/update, range query O(log n) per viewport culling, point query per hit testing, K-nearest query
- **Style System**: `StyleDefinition` con fill/stroke/effects/typography, `StyleRegistry` con node linking bidirezionale. Design tokens: `ColorToken`, `TypographyToken`, `SpacingToken`. Detach support
- **Advanced Masks**: `AdvancedMaskNode` con 6 tipi (alpha, intersection, exclusion, luminance, inverted luminance, silhouette), inversione, feathering, expansion, preview mode con overlay

### Fase 9 — Advanced Features
- **Mesh Gradients**: `MeshGradient` con griglia N×M di `MeshControlPoint`, interpolazione bilineare per patch (Coons patch), tessellazione a sub-quad, rendering via Canvas
- **Prototyping**: `PrototypeLink` con 6 trigger (click, hover, drag, timer, keyPress, scroll), 13 transizioni (dissolve, slide, push, flip, scale, smart animate), `PrototypeFlow` con navigation graph
- **Plugin API**: `PluginManifest` con 12 capabilities e 3 livelli permesso, `PluginContext` sandboxed con capability guards, `PluginRegistry` con lifecycle completo (install/activate/deactivate/uninstall)
- **Accessibility**: `AccessibilityInfo` con 15 ruoli semantici, reading order, heading levels, custom actions. `AccessibilityTreeBuilder` → a11y tree parallelo al scene graph
- **GPU Shaders**: `ShaderEffect` con 8 preset (noise, voronoi, chromatic aberration, glitch, gradient map, pixelate, vignette, custom), `ShaderUniform` hierarchy (float/vec2/vec4/color), `ShaderNode` standalone

### Fase 10 — Integration & Hardening
- **Renderer Dispatch**: Aggiunto rendering per `ShaderNode`, `AdvancedMaskNode`, `FrameNode` (tutti 13 tipi ora supportati)
- **System Wiring**: `SpatialIndex` e `DirtyTracker` integrati in `SceneGraph` con auto-registrazione nodi
- **Cached WorldTransform**: `worldTransform` cachato O(1) con dirty invalidation
- **SVG Export**: `PathNode` → `<path>`, `RichTextNode` → `<text>` con `<tspan>`, `ShapeNode`, `TextNode`
- **Clone**: `CanvasNode.clone()` via JSON roundtrip con ID univoco
- **Schema Version**: `version: 1` in `SceneGraph.toJson()`
- **Accessibility**: `accessibilityInfo` tipizzato `AccessibilityInfo?` con serializzazione

### Fase 11 — Polishing & Completeness
- **ShaderEffect Stack**: `ShaderEffectWrapper extends NodeEffect` per shader nel effect stack, dispatch in `fromJson`
- **MeshGradient Wiring**: `MeshGradient?` su `ShapeNode` con serializzazione
- **SceneGraph Integration**: `AnimationTimeline` e `PrototypeFlow` integrati in `SceneGraph.toJson/fromJson`
- **Barrel Export**: `scene_graph_engine.dart` — singolo import per tutto il motore
- **Code Quality**: Fix annotazioni `@override`, cleanup lint

---

## Statistiche

| Metrica | Valore |
|---------|--------|
| File totali | 38 |
| LOC totali | ~13,000 |
| Tipi di nodo | 13 |
| Effetti | 6 + 8 shader preset |
| Forme preset | 11 |
| Tipi di snap | 6 |
| Curve di easing | 5 |
| Comandi undo/redo | 10 |
| Formati export | 3 |
| Tipi di maschera | 6 |
| Design tokens | 3 |
| Trigger prototyping | 6 |
| Transizioni | 13 |
| Plugin capabilities | 12 |
| Ruoli a11y | 15 |
