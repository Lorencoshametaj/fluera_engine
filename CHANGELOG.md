# Changelog

## 1.0.0

Initial release of Fluera Engine — a professional 2D canvas engine for Flutter.

### Core
- Hierarchical scene graph with 13+ node types
- `CanvasNode` base with transform, opacity, blend mode, hit testing
- Spatial indexing (R-tree) for O(log n) viewport culling and hit testing
- Dirty tracking with minimal repaint regions

### Drawing
- 12 pressure-sensitive brushes with GPU shader rendering
- 120Hz input pipeline with 1€ adaptive filtering
- Predictive stroke rendering for zero-latency feel
- Isolate-based rasterization for complex scenes

### Tools
- Pen, eraser, lasso, shape, text, image, ruler, flood fill
- Extensible tool system via `DrawingTool` interface

### Effects
- Blur, drop shadow, inner shadow, outer glow, color overlay
- Linear, radial, and conic gradients
- Mesh gradient (N×M Coons patch)

### Vector
- Bézier path editing (line, quadratic, cubic segments)
- Boolean operations (union, subtract, intersect, XOR)
- 11 parametric shape presets

### PDF
- Native PDF viewing on canvas with annotation support
- Text selection, search, thumbnail sidebar
- Multi-page layout presets

### Collaboration
- Real-time multi-user editing via `FlueraRealtimeAdapter`
- CRDT vector clock for causal ordering
- Cursor presence, element locking, offline queue

### History
- Unlimited undo/redo with command pattern
- WAL-based delta tracking with auto-save
- Timeline branching and branch merging

### Export
- PNG, JPEG, WebP (configurable DPI and quality)
- SVG vector export
- PDF export

### Storage
- Zero-config `SqliteStorageAdapter` with WAL mode
- `FlueraCloudStorageAdapter` interface for any backend
- Automatic local→cloud sync with exponential backoff

### Performance
- Tile-cached rendering with LOD cross-fade
- Frame budget manager (auto-detect 60/120Hz)
- Memory pressure handling with cache eviction
- Object pooling (Path, Paint, StrokePoint)
