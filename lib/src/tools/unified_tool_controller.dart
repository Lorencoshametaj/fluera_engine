import 'package:flutter/material.dart';
import '../drawing/models/pro_drawing_point.dart';
import '../core/models/shape_type.dart';
import '../tools/shape/shape_recognizer.dart';
import './base/tool_context.dart';
import './base/tool_registry.dart';

/// 🎛️ UNIFIED TOOL CONTROLLER
///
/// SINGLE controller to manage:
/// - Tool state (color, width, opacity, brush type)
/// - Current active tool
/// - Special modes (eraser, lasso, pan, stylus)
/// - Coordination between Canvas and Multiview
///
/// DESIGN PRINCIPLES:
/// - Single source of truth for all tool state
/// - ChangeNotifier for reactive updates
/// - Serializable for persistence
///
/// Replaces and unifies:
/// - Internal variables of ProfessionalCanvasScreenState
/// - Existing MultiviewToolController
class UnifiedToolController extends ChangeNotifier {
  // ============================================================================
  // TOOL SETTINGS STATE
  // ============================================================================

  ProPenType _penType = ProPenType.fountain;
  Color _color = Colors.black;
  double _width = 3.78; // 1mm = 3.78px @ 96 DPI
  double _opacity = 1.0;
  ShapeType _shapeType = ShapeType.freehand;

  // Getters
  ProPenType get penType => _penType;
  Color get color => _color;
  double get width => _width;
  double get opacity => _opacity;
  ShapeType get shapeType => _shapeType;
  Color get effectiveColor => _color.withValues(alpha: _opacity);

  /// Generate ToolSettings to pass to ToolContext
  ToolSettings get toolSettings => ToolSettings(
    penType: _penType,
    color: _color,
    width: _width,
    opacity: _opacity,
    shapeType: _shapeType,
  );

  // ============================================================================
  // B1: REGISTRY & CONTEXT ATTACHMENT
  // ============================================================================

  /// Attached tool registry for bidirectional sync.
  ToolRegistry? _registry;

  /// Cached tool context for registry operations.
  ToolContext? _lastContext;

  /// Whether we are currently syncing to avoid feedback loops.
  bool _isSyncing = false;

  /// Attach a [ToolRegistry] for bidirectional tool selection sync.
  ///
  /// When [selectTool] is called on this controller, the registry
  /// will also activate/deactivate the corresponding tool.
  void attachRegistry(ToolRegistry registry) {
    _registry = registry;
    // Listen for external registry changes (e.g. from keyboard shortcuts).
    registry.addListener(_onRegistryChanged);
  }

  /// Detach the registry and stop listening.
  void detachRegistry() {
    _registry?.removeListener(_onRegistryChanged);
    _registry = null;
  }

  /// Provide a fresh [ToolContext] for registry operations.
  void attachContext(ToolContext context) {
    _lastContext = context;
  }

  /// Callback when ToolRegistry changes externally.
  void _onRegistryChanged() {
    if (_isSyncing) return;
    final regToolId = _registry?.activeToolId;
    if (regToolId != _activeToolId) {
      _isSyncing = true;
      _activeToolId = regToolId;
      // Reset shape type when leaving shape mode.
      if (regToolId != 'shape' && _shapeType != ShapeType.freehand) {
        _shapeType = ShapeType.freehand;
      }
      notifyListeners();
      _isSyncing = false;
    }
  }

  // ============================================================================
  // TOOL MODE STATE
  // ============================================================================

  /// Active tool ID (null = default pen/drawing mode)
  String? _activeToolId;

  String? get activeToolId => _activeToolId;

  // Convenience getters for common modes
  bool get isDrawingMode => _activeToolId == null || _activeToolId == 'pen';
  bool get isEraserMode => _activeToolId == 'eraser';
  bool get isLassoMode => _activeToolId == 'lasso';
  bool get isTextMode => _activeToolId == 'text';
  bool get isImageMode => _activeToolId == 'image';
  bool get isPanMode => _activeToolId == 'pan';
  bool get isPenToolMode => _activeToolId == 'pen_tool';
  bool get isLatexMode => _activeToolId == 'latex';
  bool get isShapeMode =>
      _shapeType != ShapeType.freehand && _activeToolId == 'shape';

  // ============================================================================
  // SPECIAL MODES
  // ============================================================================

  /// Active stylus mode (Apple Pencil, S-Pen, etc.)
  bool _isStylusMode = false;
  bool get isStylusMode => _isStylusMode;

  /// Active export mode
  bool _isExportMode = false;
  bool get isExportMode => _isExportMode;

  /// Active multi-page edit mode
  bool _isMultiPageEditMode = false;
  bool get isMultiPageEditMode => _isMultiPageEditMode;

  // ============================================================================
  // CANVAS SETTINGS
  // ============================================================================

  /// Canvas background color
  Color _backgroundColor = Colors.white;
  Color get backgroundColor => _backgroundColor;

  /// Paper type (blank, lined, grid, dotted, etc.)
  String _paperType = 'blank';
  String get paperType => _paperType;

  /// 🪣 Fill tool mode
  bool _isFillMode = false;
  bool get isFillMode => _isFillMode;

  /// 🔷 Shape recognition mode — when enabled, freehand strokes are
  /// analyzed on pointer-up and replaced with perfect geometric shapes.
  bool _shapeRecognitionEnabled = false;
  bool get shapeRecognitionEnabled => _shapeRecognitionEnabled;

  /// 🔷 Shape recognition sensitivity level.
  ShapeRecognitionSensitivity _shapeRecognitionSensitivity =
      ShapeRecognitionSensitivity.medium;
  ShapeRecognitionSensitivity get shapeRecognitionSensitivity =>
      _shapeRecognitionSensitivity;

  /// 🔷 Ghost suggestion mode — when enabled, recognized shapes are
  /// shown as a semi-transparent preview before auto-accepting.
  bool _ghostSuggestionMode = false;
  bool get ghostSuggestionMode => _ghostSuggestionMode;

  /// 🔀 Multi-stroke buffer — accumulates recent unrecognized strokes
  /// and tries to combine them into a single shape.
  final List<_BufferedStroke> _multiStrokeBuffer = [];
  static const _multiStrokeTimeoutMs = 800; // Max time between strokes
  static const _maxBufferedStrokes = 3; // Max strokes to combine

  /// Get combined points from the multi-stroke buffer.
  List<Offset>? getMultiStrokePoints() {
    if (_multiStrokeBuffer.length < 2) return null;

    // Check time gap between strokes
    for (int i = 1; i < _multiStrokeBuffer.length; i++) {
      final gap =
          _multiStrokeBuffer[i].timestamp
              .difference(_multiStrokeBuffer[i - 1].timestamp)
              .inMilliseconds;
      if (gap > _multiStrokeTimeoutMs) {
        // Gap too large — clear older strokes
        _multiStrokeBuffer.removeRange(0, i);
        return null;
      }
    }

    // Combine all buffered points
    final combined = <Offset>[];
    for (final stroke in _multiStrokeBuffer) {
      combined.addAll(stroke.points);
    }
    return combined.length >= 5 ? combined : null;
  }

  /// Add a stroke to the multi-stroke buffer.
  void bufferStroke(List<Offset> points) {
    _multiStrokeBuffer.add(
      _BufferedStroke(points: points, timestamp: DateTime.now()),
    );
    // Keep buffer size bounded
    while (_multiStrokeBuffer.length > _maxBufferedStrokes) {
      _multiStrokeBuffer.removeAt(0);
    }
  }

  /// Clear the multi-stroke buffer (called on successful recognition).
  void clearMultiStrokeBuffer() {
    _multiStrokeBuffer.clear();
  }

  // ============================================================================
  // SETTERS WITH NOTIFICATION
  // ============================================================================

  void setPenType(ProPenType type) {
    if (_penType == type) return;
    _penType = type;
    notifyListeners();
  }

  void setColor(Color color) {
    if (_color == color) return;
    _color = color;
    notifyListeners();
  }

  void setWidth(double width) {
    if (_width == width) return;
    _width = width.clamp(0.5, 50.0);
    notifyListeners();
  }

  void setOpacity(double opacity) {
    if (_opacity == opacity) return;
    _opacity = opacity.clamp(0.0, 1.0);
    notifyListeners();
  }

  void setShapeType(ShapeType type) {
    if (_shapeType == type) return;
    _shapeType = type;

    // If a shape is selected, activate shape mode
    if (type != ShapeType.freehand) {
      _activeToolId = 'shape';
    } else if (_activeToolId == 'shape') {
      _activeToolId = null; // Return to drawing mode
    }

    notifyListeners();
  }

  // ============================================================================
  // TOOL SELECTION
  // ============================================================================

  /// Select a tool by ID
  ///
  /// Pass null to return to default drawing mode.
  void selectTool(String? toolId) {
    if (_activeToolId == toolId) return;
    _activeToolId = toolId;

    // Reset shape type when leaving shape mode
    if (toolId != 'shape' && _shapeType != ShapeType.freehand) {
      _shapeType = ShapeType.freehand;
    }

    // B1: Propagate to registry if attached.
    if (!_isSyncing && _registry != null && _lastContext != null) {
      _isSyncing = true;
      _registry!.selectTool(toolId, _lastContext!);
      _isSyncing = false;
    }

    notifyListeners();
  }

  /// Toggle eraser mode
  void toggleEraser() {
    selectTool(_activeToolId == 'eraser' ? null : 'eraser');
  }

  /// Toggle lasso mode
  void toggleLasso() {
    selectTool(_activeToolId == 'lasso' ? null : 'lasso');
  }

  /// Toggle text mode
  void toggleTextMode() {
    selectTool(_activeToolId == 'text' ? null : 'text');
  }

  /// Toggle image mode
  void toggleImageMode() {
    selectTool(_activeToolId == 'image' ? null : 'image');
  }

  /// Toggle vector pen tool mode
  void togglePenTool() {
    selectTool(_activeToolId == 'pen_tool' ? null : 'pen_tool');
  }

  /// Toggle pan/zoom mode
  void togglePanMode() {
    selectTool(_activeToolId == 'pan' ? null : 'pan');
  }

  /// 🧮 Toggle LaTeX editor mode
  void toggleLatexMode() {
    selectTool(_activeToolId == 'latex' ? null : 'latex');
  }

  /// Toggle stylus mode
  void toggleStylusMode() {
    _isStylusMode = !_isStylusMode;
    notifyListeners();
  }

  /// Set stylus mode
  void setStylusMode(bool value) {
    if (_isStylusMode == value) return;
    _isStylusMode = value;
    notifyListeners();
  }

  /// Toggle export mode
  void toggleExportMode() {
    _isExportMode = !_isExportMode;
    if (_isExportMode) {
      _activeToolId = null; // Deactivate other tools during export
    }
    notifyListeners();
  }

  /// Toggle multi-page edit mode
  void toggleMultiPageEditMode() {
    _isMultiPageEditMode = !_isMultiPageEditMode;
    notifyListeners();
  }

  /// Set background color
  void setBackgroundColor(Color color) {
    if (_backgroundColor == color) return;
    _backgroundColor = color;
    notifyListeners();
  }

  /// Set paper type
  void setPaperType(String type) {
    if (_paperType == type) return;
    _paperType = type;
    notifyListeners();
  }

  /// 🪣 Toggle fill mode
  void toggleFillMode() {
    _isFillMode = !_isFillMode;
    if (_isFillMode) {
      _activeToolId = 'fill';
    } else if (_activeToolId == 'fill') {
      _activeToolId = null;
    }
    notifyListeners();
  }

  /// 🔷 Toggle shape recognition mode
  void toggleShapeRecognition() {
    _shapeRecognitionEnabled = !_shapeRecognitionEnabled;
    notifyListeners();
  }

  /// 🔷 Set shape recognition mode
  void setShapeRecognition(bool value) {
    if (_shapeRecognitionEnabled == value) return;
    _shapeRecognitionEnabled = value;
    notifyListeners();
  }

  /// 🔷 Set shape recognition sensitivity
  void setShapeRecognitionSensitivity(ShapeRecognitionSensitivity value) {
    if (_shapeRecognitionSensitivity == value) return;
    _shapeRecognitionSensitivity = value;
    notifyListeners();
  }

  /// 🔷 Cycle through sensitivity levels (low → medium → high → low)
  void cycleShapeRecognitionSensitivity() {
    final values = ShapeRecognitionSensitivity.values;
    final nextIndex = (_shapeRecognitionSensitivity.index + 1) % values.length;
    _shapeRecognitionSensitivity = values[nextIndex];
    notifyListeners();
  }

  /// 👻 Toggle ghost suggestion mode
  void toggleGhostSuggestionMode() {
    _ghostSuggestionMode = !_ghostSuggestionMode;
    notifyListeners();
  }

  /// Reset to drawing mode (deselect everything)
  void resetToDrawingMode() {
    _activeToolId = null;
    _shapeType = ShapeType.freehand;
    _isExportMode = false;
    _isMultiPageEditMode = false;
    _isFillMode = false;
    notifyListeners();
  }

  // ============================================================================
  // ERASER CONFIGURATION
  // ============================================================================

  double _eraserRadius = 20.0;
  bool _eraseWholeStroke = true;

  double get eraserRadius => _eraserRadius;
  bool get eraseWholeStroke => _eraseWholeStroke;

  void setEraserRadius(double radius) {
    if (_eraserRadius == radius) return;
    _eraserRadius = radius.clamp(5.0, 100.0);
    notifyListeners();
  }

  void setEraseWholeStroke(bool value) {
    if (_eraseWholeStroke == value) return;
    _eraseWholeStroke = value;
    notifyListeners();
  }

  // ============================================================================
  // SERIALIZATION
  // ============================================================================

  Map<String, dynamic> toJson() => {
    'penType': _penType.index,
    'color': _color.toARGB32(),
    'width': _width,
    'opacity': _opacity,
    'shapeType': _shapeType.index,
    'activeToolId': _activeToolId,
    'isStylusMode': _isStylusMode,
    'eraserRadius': _eraserRadius,
    'eraseWholeStroke': _eraseWholeStroke,
    'backgroundColor': _backgroundColor.toARGB32(),
    'paperType': _paperType,
    'shapeRecognitionEnabled': _shapeRecognitionEnabled,
    'shapeRecognitionSensitivity': _shapeRecognitionSensitivity.index,
    'ghostSuggestionMode': _ghostSuggestionMode,
  };

  void fromJson(Map<String, dynamic> json) {
    _penType = ProPenType.values[json['penType'] ?? 0];
    _color = Color(json['color'] ?? Colors.black.toARGB32());
    _width = (json['width'] ?? 3.78).toDouble();
    _opacity = (json['opacity'] ?? 1.0).toDouble();
    _shapeType = ShapeType.values[json['shapeType'] ?? 0];
    _activeToolId = json['activeToolId'];
    _isStylusMode = json['isStylusMode'] ?? false;
    _eraserRadius = (json['eraserRadius'] ?? 20.0).toDouble();
    _eraseWholeStroke = json['eraseWholeStroke'] ?? true;
    if (json['backgroundColor'] != null) {
      _backgroundColor = Color(json['backgroundColor']);
    }
    _paperType = json['paperType'] ?? 'blank';
    _shapeRecognitionEnabled = json['shapeRecognitionEnabled'] ?? false;
    final sensIndex = json['shapeRecognitionSensitivity'] ?? 1;
    _shapeRecognitionSensitivity =
        ShapeRecognitionSensitivity.values[sensIndex.clamp(
          0,
          ShapeRecognitionSensitivity.values.length - 1,
        )];
    _ghostSuggestionMode = json['ghostSuggestionMode'] ?? false;
    notifyListeners();
  }

  // ============================================================================
  // COMPATIBILITY (Backward compatibility with MultiviewToolController)
  // ============================================================================

  /// Alias for compatibility with old code
  ProPenType get selectedPenType => _penType;
  Color get selectedColor => _color;
  double get penWidth => _width;
  ShapeType get selectedShapeType => _shapeType;
  bool get isErasing => isEraserMode;
  bool get isLassoMode_ => isLassoMode;
  bool get isTextMode_ => isTextMode;
  bool get isImageMode_ => isImageMode;
  bool get isPanMode_ => isPanMode;

  void setErasing(bool value) {
    if (value) {
      selectTool('eraser');
    } else if (isEraserMode) {
      selectTool(null);
    }
  }

  void setLassoMode(bool value) {
    if (value) {
      selectTool('lasso');
    } else if (isLassoMode) {
      selectTool(null);
    }
  }

  void setTextMode(bool value) {
    if (value) {
      selectTool('text');
    } else if (isTextMode) {
      selectTool(null);
    }
  }

  void setPanMode(bool value) {
    if (value) {
      selectTool('pan');
    } else if (isPanMode) {
      selectTool(null);
    }
  }

  void setPenWidth(double width) => setWidth(width);

  // Canvas screen compatibility aliases
  void setStrokeWidth(double width) => setWidth(width);
  void toggleLassoMode() => toggleLasso();
  bool get isLassoActive => isLassoMode;
  void toggleDigitalTextMode() => toggleTextMode();
  bool get isDigitalTextActive => isTextMode;
  void setEraserMode(bool value) => setErasing(value);

  // ============================================================================
  // DEBUG
  // ============================================================================

  String get debugInfo => '''
UnifiedToolController:
  penType: $_penType
  color: $_color
  width: $_width
  opacity: $_opacity
  shapeType: $_shapeType
  activeToolId: $_activeToolId
  isStylusMode: $_isStylusMode
  eraserRadius: $_eraserRadius
  registry: ${_registry != null ? 'attached' : 'detached'}
  context: ${_lastContext != null ? 'set' : 'null'}
''';

  @override
  void dispose() {
    detachRegistry();
    super.dispose();
  }
}

/// Internal data class for multi-stroke buffering.
class _BufferedStroke {
  final List<Offset> points;
  final DateTime timestamp;

  const _BufferedStroke({required this.points, required this.timestamp});
}
