import 'package:flutter/foundation.dart';

import '../modules/canvas_module.dart';
import '../nodes/latex_node.dart';
import '../../platform/latex_recognition_bridge.dart';
import '../../platform/onnx_latex_recognizer.dart';
import '../../platform/hme_latex_recognizer.dart';
import '../../platform/pix2tex_recognizer.dart';
import '../../tools/base/tool_interface.dart';

// =============================================================================
// LATEX MODULE
// =============================================================================

/// 🧮 Self-contained LaTeX recognition and rendering module.
///
/// Encapsulates all LaTeX functionality:
/// - [LatexNode]: scene graph node for rendered LaTeX
/// - LaTeX parser, tokenizer, layout engine (in `core/latex/`)
/// - Unified recognition via [LatexRecognitionBridge] with automatic fallback:
///   1. ONNX (on-device, fastest)
///   2. HME Attention (on-device, attention-based decoder)
///   3. Pix2Tex (HTTP fallback if device inference fails)
///
/// ## Usage
///
/// ```dart
/// await EngineScope.current.moduleRegistry.register(LaTeXModule());
///
/// // Access the recognizer
/// final latex = EngineScope.current.moduleRegistry.findModule<LaTeXModule>()!;
/// final result = await latex.recognizer.recognize(inkData);
/// ```
class LaTeXModule extends CanvasModule {
  // ---------------------------------------------------------------------------
  // Identity
  // ---------------------------------------------------------------------------

  @override
  String get moduleId => 'latex';

  @override
  String get displayName => 'LaTeX';

  // ---------------------------------------------------------------------------
  // Module-owned services
  // ---------------------------------------------------------------------------

  /// The active recognizer (selected during initialization via fallback chain).
  LatexRecognitionBridge? _activeRecognizer;

  /// All recognizer instances for lifecycle management.
  final List<LatexRecognitionBridge> _recognizers = [];

  /// The name of the active backend for diagnostics.
  String _activeBackendName = 'none';

  /// The active LaTeX recognizer.
  ///
  /// Returns `null` if no recognizer could be initialized.
  LatexRecognitionBridge? get recognizer => _activeRecognizer;

  /// Name of the active recognition backend ('onnx', 'hme', 'pix2tex', 'none').
  String get activeBackendName => _activeBackendName;

  // ---------------------------------------------------------------------------
  // CanvasModule contract
  // ---------------------------------------------------------------------------

  @override
  List<NodeDescriptor> get nodeDescriptors => [
    NodeDescriptor(
      nodeType: 'latex',
      fromJson: LatexNode.fromJson,
      displayName: 'LaTeX Expression',
    ),
  ];

  @override
  List<DrawingTool> createTools() => const [];

  @override
  bool get isInitialized => _initialized;
  bool _initialized = false;

  @override
  Future<void> initialize(ModuleContext context) async {
    if (_initialized) return;

    // Try recognizers in priority order: ONNX → HME → Pix2Tex
    await _initializeRecognizers();

    _initialized = true;
  }

  /// Initialize recognizers with fallback chain.
  ///
  /// Each recognizer is tried in order. The first one that initializes
  /// successfully and reports itself as available becomes the active backend.
  /// All instantiated recognizers are tracked for disposal.
  Future<void> _initializeRecognizers() async {
    // 1. ONNX — fastest, fully offline
    try {
      final onnx = OnnxLatexRecognizer();
      _recognizers.add(onnx);
      await onnx.initialize();
      if (await onnx.isAvailable()) {
        _activeRecognizer = onnx;
        _activeBackendName = 'onnx';
        debugPrint('LaTeXModule: ONNX recognizer active ✅');
        return;
      }
    } catch (e) {
      debugPrint('LaTeXModule: ONNX recognizer unavailable ($e)');
    }

    // 2. HME Attention — encoder-decoder with attention
    try {
      final hme = HmeLatexRecognizer();
      _recognizers.add(hme);
      await hme.initialize();
      if (await hme.isAvailable()) {
        _activeRecognizer = hme;
        _activeBackendName = 'hme';
        debugPrint('LaTeXModule: HME recognizer active ✅');
        return;
      }
    } catch (e) {
      debugPrint('LaTeXModule: HME recognizer unavailable ($e)');
    }

    // 3. Pix2Tex — HTTP fallback
    try {
      final pix2tex = Pix2TexRecognizer();
      _recognizers.add(pix2tex);
      await pix2tex.initialize();
      if (await pix2tex.isAvailable()) {
        _activeRecognizer = pix2tex;
        _activeBackendName = 'pix2tex';
        debugPrint('LaTeXModule: Pix2Tex recognizer active ✅');
        return;
      }
    } catch (e) {
      debugPrint('LaTeXModule: Pix2Tex recognizer unavailable ($e)');
    }

    debugPrint('LaTeXModule: No recognizer available ⚠️');
  }

  @override
  Future<void> dispose() async {
    if (!_initialized) return;

    for (final recognizer in _recognizers) {
      try {
        recognizer.dispose();
      } catch (e) {
        debugPrint('LaTeXModule: Error disposing recognizer: $e');
      }
    }
    _recognizers.clear();
    _activeRecognizer = null;
    _activeBackendName = 'none';
    _initialized = false;
  }
}
