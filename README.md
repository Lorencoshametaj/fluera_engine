# Fluera Engine

A professional 2D canvas engine for Flutter, built by [Looponia](https://fluera.dev).

[![License: BSD-3-Clause](https://img.shields.io/badge/License-BSD_3--Clause-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-%E2%89%A53.27-blue.svg)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-%5E3.7-blue.svg)](https://dart.dev)

## Features

| Category | What you get |
|----------|-------------|
| **Drawing** | 12 pressure-sensitive brushes (ballpoint, pencil, fountain pen, marker, charcoal, oil, spray, neon, ink wash, watercolor, highlighter, eraser) |
| **Canvas** | Infinite canvas with smooth zoom, pan, and rotation physics |
| **Scene Graph** | Hierarchical node tree with 13+ node types, spatial indexing, and viewport culling |
| **Effects** | Blur, drop shadow, inner shadow, outer glow, gradients (linear, radial, conic), mesh gradients |
| **Vector** | Bézier path editing, boolean operations, 11 shape presets |
| **Tools** | Pen, eraser, lasso, shape, text, image, ruler, flood fill — extensible via `DrawingTool` |
| **PDF** | Native PDF viewing, annotation, text selection, search |
| **Collaboration** | Real-time multi-user editing with CRDT vector clock, cursors, presence |
| **History** | Unlimited undo/redo with WAL persistence and timeline branching |
| **Export** | PNG, JPEG, WebP, SVG, PDF |
| **Performance** | 60 FPS with tile cache, LOD, GPU shaders, isolate rasterization |
| **Storage** | Zero-config SQLite persistence with cloud sync adapter |

## Quick Start

```dart
import 'package:flutter/material.dart';
import 'package:fluera_engine/fluera_engine.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storage = SqliteStorageAdapter();
  await storage.initialize();

  runApp(MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    home: FlueraCanvasScreen(
      config: FlueraCanvasConfig(
        layerController: LayerController(),
        storageAdapter: storage,
      ),
    ),
  ));
}
```

## Architecture

Fluera Engine uses **dependency injection** via `FlueraCanvasConfig` — every feature is optional and activated by passing the corresponding provider. No Firebase, no backend, no vendor lock-in.

```
FlueraCanvasScreen
  └── FlueraCanvasConfig
        ├── storageAdapter      → Local persistence (SQLite)
        ├── cloudAdapter        → Cloud sync (any backend)
        ├── realtimeAdapter     → Real-time collaboration
        ├── pdfProvider         → PDF rendering
        ├── permissions         → Access control
        ├── presence            → User presence
        └── voiceRecording      → Audio notes
```

The engine is built on a **modular architecture** with `CanvasModule` plugin system. Core modules (Drawing, PDF, Audio) are registered automatically. Additional modules (LaTeX, Tabular, Enterprise) are available as separate add-on packages.

## Documentation

- **[Getting Started](GETTING_STARTED.md)** — Full integration guide with Firebase example
- **[Architecture](ARCHITECTURE.md)** — Scene graph, module system, performance pipeline

## Requirements

| Requirement | Minimum Version |
|------------|----------------|
| Dart SDK | `^3.7.0` |
| Flutter | `≥ 3.27.0` |
| Android minSdk | `23` (Android 6.0) |
| iOS | `12.0+` |

## License

BSD 3-Clause License. See [LICENSE](LICENSE) for details.
