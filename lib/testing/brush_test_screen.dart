import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import './brush_settings_dialog.dart';
import './brush_test_canvas.dart';
import './brush_test_toolbar.dart';
import './brush_test_painter.dart';

// ─────────────────────────────────────────────────────────────
// 🎨 Brush Type, Stroke Point, Stroke models + Test Screen
// ─────────────────────────────────────────────────────────────

/// Available brush type
enum BrushType {
  fountainPen,
  pencil,
  highlighter,
  ballpoint;

  /// Icona associata al tipo di pennello
  IconData get icon {
    switch (this) {
      case BrushType.fountainPen:
        return Icons.brush;
      case BrushType.pencil:
        return Icons.create;
      case BrushType.highlighter:
        return Icons.highlight;
      case BrushType.ballpoint:
        return Icons.edit;
    }
  }
}

/// Punto singolo di uno stroke con dati di input
class StrokePoint {
  final Offset offset;
  final double pressure;
  final double tiltX;
  final double tiltY;

  const StrokePoint({
    required this.offset,
    this.pressure = 0.5,
    this.tiltX = 0.0,
    this.tiltY = 0.0,
  });
}

/// Uno stroke completo with all i metadati
class BrushStroke {
  final List<StrokePoint> points;
  final Color color;
  final double width;
  final double opacity;
  final BrushType brushType;
  final BrushSettings settings;

  BrushStroke({
    required this.points,
    required this.color,
    required this.width,
    required this.opacity,
    required this.brushType,
    required this.settings,
  });
}

/// 🎨 Schermata principale per il test dei pennelli
///
/// Permette di:
/// - Testare i diversi tipi di pennelli
/// - Regolare parametri in tempo reale
/// - View performance
class BrushTestScreen extends StatefulWidget {
  const BrushTestScreen({super.key});

  @override
  State<BrushTestScreen> createState() => _BrushTestScreenState();
}

class _BrushTestScreenState extends State<BrushTestScreen> {
  // Brush state
  BrushType _selectedBrush = BrushType.fountainPen;
  Color _brushColor = Colors.black;
  double _brushWidth = 3.0;
  double _opacity = 1.0;
  BrushSettings _brushSettings = BrushSettings();

  // Strokes
  final List<BrushStroke> _strokes = [];
  BrushStroke? _currentStroke;

  // Performance tracking
  int _repaintKey = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Brush Testing'),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: 'Undo',
            onPressed: _strokes.isNotEmpty ? _undo : null,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear',
            onPressed: _strokes.isNotEmpty ? _clear : null,
          ),
        ],
      ),
      body: Column(
        children: [
          // Canvas
          Expanded(
            child: BrushTestCanvas(
              strokes: _strokes,
              currentStroke: _currentStroke,
              repaintKey: _repaintKey,
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
            ),
          ),
          // Toolbar
          BrushTestToolbar(
            selectedBrush: _selectedBrush,
            brushColor: _brushColor,
            brushWidth: _brushWidth,
            opacity: _opacity,
            brushSettings: _brushSettings,
            onBrushChanged: (brush) => setState(() => _selectedBrush = brush),
            onColorChanged: (color) => setState(() => _brushColor = color),
            onWidthChanged: (width) => setState(() => _brushWidth = width),
            onOpacityChanged: (opacity) => setState(() => _opacity = opacity),
            onSettingsChanged:
                (settings) => setState(() => _brushSettings = settings),
          ),
        ],
      ),
    );
  }

  void _onPanStart(
    Offset position,
    double pressure,
    double tiltX,
    double tiltY,
  ) {
    setState(() {
      _currentStroke = BrushStroke(
        points: [
          StrokePoint(
            offset: position,
            pressure: pressure,
            tiltX: tiltX,
            tiltY: tiltY,
          ),
        ],
        color: _brushColor,
        width: _brushWidth,
        opacity: _opacity,
        brushType: _selectedBrush,
        settings: _brushSettings.copyWith(),
      );
    });
  }

  void _onPanUpdate(
    Offset position,
    double pressure,
    double tiltX,
    double tiltY,
  ) {
    if (_currentStroke == null) return;

    setState(() {
      _currentStroke = BrushStroke(
        points: [
          ..._currentStroke!.points,
          StrokePoint(
            offset: position,
            pressure: pressure,
            tiltX: tiltX,
            tiltY: tiltY,
          ),
        ],
        color: _currentStroke!.color,
        width: _currentStroke!.width,
        opacity: _currentStroke!.opacity,
        brushType: _currentStroke!.brushType,
        settings: _currentStroke!.settings,
      );
    });
  }

  void _onPanEnd() {
    if (_currentStroke != null && _currentStroke!.points.isNotEmpty) {
      setState(() {
        _strokes.add(_currentStroke!);
        _currentStroke = null;
      });
    }
  }

  void _undo() {
    if (_strokes.isNotEmpty) {
      setState(() {
        _strokes.removeLast();
        _repaintKey++;
      });
      HapticFeedback.lightImpact();
    }
  }

  void _clear() {
    setState(() {
      _strokes.clear();
      _repaintKey++;
      BrushTestPainter.clearCache();
    });
    HapticFeedback.mediumImpact();
  }
}
