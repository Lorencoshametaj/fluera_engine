<!-- markdownlint-disable MD033 MD041 -->

<p align="center">
  <strong>Fluera Engine</strong><br/>
  <em>Professional 2D canvas SDK for Flutter.</em>
</p>

<p align="center">
  <a href="https://pub.dev/packages/fluera_engine"><img alt="pub package" src="https://img.shields.io/pub/v/fluera_engine.svg"></a>
  <a href="./LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-blue.svg"></a>
  <a href="https://fluera.dev"><img alt="Docs" src="https://img.shields.io/badge/docs-fluera.dev-6c4dff"></a>
</p>

---

Pressure-sensitive brushes. Infinite canvas. Scene graph. 60 FPS rendering
on commodity hardware. **Fluera Engine** gives you the primitives to build a
drawing app, a whiteboard, a PDF annotator, a sketch tool, or a custom
creative surface — in Flutter, cross-platform, today.

```dart
import 'package:fluera_engine/fluera_engine.dart';

// A drawing canvas in ~5 lines of wiring.
final controller = InfiniteCanvasController();

InfiniteCanvasGestureDetector(
  controller: controller,
  onDrawStart: (pos, pressure, tiltX, tiltY) => /* push stroke */,
  onDrawUpdate: (pos, pressure, tiltX, tiltY) => /* extend stroke */,
  onDrawEnd: (pos) => /* commit stroke */,
  child: CustomPaint(painter: YourScenePainter(), size: Size.infinite),
);
```

→ **[5 runnable demos](../fluera_engine_examples/example)** ·
**[Full docs](https://fluera.dev/docs)** ·
**[Pricing](https://fluera.dev/pricing)**

---

## What's in the box

| Layer | What you get | Licence |
|---|---|---|
| **Core** (`package:fluera_engine`) | Infinite canvas controller, gesture detector with pressure/tilt, scene graph, 5 base node types (stroke/shape/text/image/layer), 3 base brushes (ballpoint/pencil/highlighter), module system, pen & eraser & shape tools, undo/redo, PNG/JPEG/WebP export, platform stylus input. | **MIT** |
| **Pro** (`package:fluera_engine_pro`) | 14 GPU shader renderers, advanced brushes (watercolor, charcoal, fountain pen), real-time CRDT collaboration, timeline branching with 3-way merge, time travel stroke playback, SQLCipher encrypted storage, PDF/SVG export, LaTeX handwriting recognition, tile-cached rendering with LOD + occlusion culling, 20+ advanced node types. | **Commercial** |

*Using Fluera Engine at work?
Check out the [Pro tier](https://fluera.dev/pricing) — one-time purchase
from €499, no per-seat fees.*

## Install

```yaml
dependencies:
  fluera_engine: ^0.1.0
```

```shell
flutter pub get
```

## 5-minute starter

The fastest way to see what the SDK can do is to run the example app:

```shell
git clone https://github.com/Lorencoshametaj/fluera_engine.git
cd fluera_engine/fluera_engine_examples/example
flutter run
```

You'll get a picker with five minimal demos, each ≤300 lines of glue code:

1. **Hello Canvas** — drawing surface with pressure, pan, zoom, undo
2. **Pressure & Tilt** — live stylus input readout (Apple Pencil, S Pen)
3. **Scene Manipulation** — programmatic stroke push (no gestures needed)
4. **Custom Brush** — swap the renderer for rainbow / dotted / calligraphy
5. **Export PNG** — rasterize to a PNG byte array — save, upload, share

Each example is a standalone file. Copy the one closest to your use case,
delete the rest.

## How it compares

| | Fluera Engine | `flutter_drawing_board` | `scribble` | `fldraw` |
|---|---|---|---|---|
| Pressure-sensitive brushes | ✅ | ❌ | ✅ | ❌ |
| Infinite canvas (unbounded pan/zoom) | ✅ | ❌ | ❌ | ✅ |
| Scene graph (nested layers, groups, frames) | ✅ | ❌ | ❌ | ❌ |
| GPU shader renderers (Pro) | ✅ | ❌ | ❌ | ❌ |
| Real-time collaboration (Pro) | ✅ CRDT | ❌ | ❌ | ❌ |
| Time travel playback (Pro) | ✅ | ❌ | ❌ | ❌ |
| Cross-platform (iOS/Android/desktop/web) | ✅ | ✅ | ✅ | ✅ |
| Commercial support & SLA | ✅ | ❌ | ❌ | ❌ |

## Platform support

Android, iOS, Linux, macOS, Windows, Web. Built on stock Flutter widgets +
`dart:ui` — **no platform channels required for the Core**.

The Pro tier adds optional native accelerators (Vulkan on Android, Metal on
Apple, Direct3D 11 on Windows, OpenGL on Linux, WebGPU on web) for the GPU
shader pipeline. Opt-in per-platform.

## Architecture at a glance

```
Your App
   │  constructs
   ▼
InfiniteCanvas (your widget over the primitives)
   │
   ├── InfiniteCanvasController      ← camera: offset, scale, physics
   ├── InfiniteCanvasGestureDetector ← pressure/tilt input pipeline
   ├── SceneGraph                    ← typed node tree with observers
   │    └── StrokeNode / ShapeNode / TextNode / ImageNode / LayerNode
   ├── BrushEngine                   ← pressure curves, stroke stabilisation
   ├── ToolRegistry                  ← pen / eraser / shape / text / image
   └── ExportPipeline                ← PNG, JPEG, WebP
```

Every box is replaceable via the `CanvasModule` plugin system.

## Requirements

| Requirement | Minimum Version |
|------------|----------------|
| Dart SDK | `^3.10.0` |
| Flutter | `≥ 3.27.0` |
| Android minSdk | `23` (Android 6.0) |
| iOS | `12.0+` |

## Commercial tier

If your project needs CRDT collaboration, GPU shader brushes, PDF export,
timeline branching, or encrypted storage, the Pro package picks up where
Core leaves off.

| Plan | Revenue cap | Price |
|---|---|---|
| Startup | < $100k/year | **€499** one-time + €149/year updates |
| Pro / Studio | < $1M/year | **€1,499** one-time + €399/year updates |
| Enterprise | unlimited | **€5k–15k/year** — custom SLA, priority support |

→ **[Get a licence](https://fluera.dev/pricing)** · **[Request a quote](mailto:hello@fluera.dev)**

## License

MIT for the Core (this package). See [LICENSE](LICENSE).

The companion `fluera_engine_pro` package is under a commercial license;
see that package's LICENSE for details.

## Links

- **Docs**: <https://fluera.dev/docs>
- **Pricing**: <https://fluera.dev/pricing>
- **Issues**: <https://github.com/Lorencoshametaj/fluera_engine/issues>
- **Commercial inquiries**: <hello@fluera.dev>

---

<sub>Made with 💜 in Italy by Lorenzo Shametaj.</sub>
