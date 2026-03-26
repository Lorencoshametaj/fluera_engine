import 'dart:async';

import 'package:flutter/material.dart';

import '../../../services/digital_ink_service.dart';
import '../../../drawing/models/pro_drawing_point.dart';

class HandwritingScratchpad extends StatefulWidget {
  final void Function(String text) onRecognizedText;
  final double height;
  final Color inkColor;

  const HandwritingScratchpad({
    super.key,
    required this.onRecognizedText,
    this.height = 240,
    this.inkColor = const Color(0xFF00FFCC), // Fluera cyan
  });

  @override
  State<HandwritingScratchpad> createState() => _HandwritingScratchpadState();
}

class _HandwritingScratchpadState extends State<HandwritingScratchpad> with TickerProviderStateMixin {
  final List<List<ProDrawingPoint>> _strokes = [];
  List<ProDrawingPoint> _currentStroke = [];
  Timer? _debounceTimer;
  bool _isRecognizing = false;

  // Fade out animation for recognized strokes
  late final AnimationController _fadeController;
  final List<List<ProDrawingPoint>> _fadingStrokes = [];

  // Countdown timer for OCR debounce visualization
  late final AnimationController _countdownController;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..addListener(() {
        setState(() {}); // trigger repaint for alpha
      });

    _countdownController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..addListener(() {
        setState(() {}); // trigger repaint for progress bar
      });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _fadeController.dispose();
    _countdownController.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    _debounceTimer?.cancel();
    _countdownController.stop();
    _countdownController.reset();
    
    // If an animation is running, snap it to end and clear
    if (_fadeController.isAnimating) {
      _fadeController.reset();
      _fadingStrokes.clear();
    }

    setState(() {
      _currentStroke = [
        ProDrawingPoint(
          position: event.localPosition,
          pressure: event.pressure, // Real Apple Pencil pressure
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
      ];
      _strokes.add(_currentStroke);
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_currentStroke.isEmpty) return;
    
    // Basic point deduplication
    final lastPoint = _currentStroke.last;
    if ((lastPoint.position - event.localPosition).distance < 1.0) return;

    setState(() {
      _currentStroke.add(ProDrawingPoint(
        position: event.localPosition,
        pressure: event.pressure, // Real Apple Pencil pressure
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ));
    });
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_currentStroke.isNotEmpty) {
      setState(() {
        _currentStroke.add(ProDrawingPoint(
          position: event.localPosition,
          pressure: event.pressure,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ));
      });
    }
    _currentStroke = [];
    _scheduleRecognition();
  }

  void _scheduleRecognition() {
    _debounceTimer?.cancel();
    _countdownController.reset();
    _countdownController.forward();
    _debounceTimer = Timer(const Duration(milliseconds: 1200), _recognizeInk);
  }

  Future<void> _recognizeInk() async {
    if (_strokes.isEmpty) return;
    
    // Snap countdown visual to 0 once we start recognizing
    _countdownController.reset();
    
    // Snapshot the current strokes for this recognition pass
    final strokesToRecognize = List<List<ProDrawingPoint>>.from(
      _strokes.map((s) => List<ProDrawingPoint>.from(s))
    );
    
    setState(() => _isRecognizing = true);
    try {
      final result = await DigitalInkService.instance.recognizeMultiStrokeWithAutoDetect(strokesToRecognize);
      if (result != null && result.text.isNotEmpty) {
        // Only consume if the current strokes haven't fundamentally changed since we started
        if (mounted) {
          widget.onRecognizedText(result.text);
          
          // Move strokes to the fading layer
          setState(() {
            _fadingStrokes.clear();
            _fadingStrokes.addAll(_strokes);
            _strokes.clear();
            
            // Start the dissolve animation
            _fadeController.forward(from: 0.0).then((_) {
              if (mounted) {
                setState(() => _fadingStrokes.clear());
              }
            });
          });
        }
      }
    } catch (e) {
      debugPrint('Error recognizing ink: $e');
    } finally {
      if (mounted) setState(() => _isRecognizing = false);
    }
  }

  void _clear() {
    _debounceTimer?.cancel();
    _fadeController.reset();
    _countdownController.reset();
    setState(() {
      _strokes.clear();
      _fadingStrokes.clear();
      _currentStroke = [];
    });
  }

  void _undo() {
    if (_strokes.isEmpty || _isRecognizing) return;
    setState(() {
      _strokes.removeLast();
      _debounceTimer?.cancel();
      _countdownController.reset();
      
      // If there are still strokes left, reschedule OCR. Otherwise, we're clean.
      if (_strokes.isNotEmpty) {
        _scheduleRecognition();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: widget.inkColor.withValues(alpha: 0.2)),
        boxShadow: _isRecognizing ? [
          BoxShadow(
            color: widget.inkColor.withValues(alpha: 0.05),
            blurRadius: 15,
            spreadRadius: 2,
          )
        ] : null,
      ),
      child: Stack(
        children: [
          // Drawing area (Active strokes)
          Positioned.fill(
            child: Listener(
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              behavior: HitTestBehavior.opaque,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: CustomPaint(
                  painter: _ScratchpadPainter(
                    strokes: _strokes,
                    color: widget.inkColor,
                  ),
                ),
              ),
            ),
          ),
          
          // Fading area (Recognized strokes dissolving)
          if (_fadingStrokes.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: CustomPaint(
                    painter: _ScratchpadPainter(
                      strokes: _fadingStrokes,
                      color: widget.inkColor,
                      alphaFade: 1.0 - _fadeController.value,
                    ),
                  ),
                ),
              ),
            ),
          
          // Helper text
          if (_strokes.isEmpty && _fadingStrokes.isEmpty)
            Center(
              child: Text(
                'Scrivi qui la tua risposta a mano...',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.2),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

          // Countdown progress bar at the bottom
          if (_countdownController.isAnimating)
            Positioned(
              left: 16,
              right: 16,
              bottom: 0,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                child: LinearProgressIndicator(
                  value: _countdownController.value,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(widget.inkColor.withValues(alpha: 0.5)),
                  minHeight: 3,
                ),
              ),
            ),
            
          // Controls
          Positioned(
            top: 8,
            right: 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isRecognizing)
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(widget.inkColor),
                      ),
                    ),
                  ),
                if (_strokes.isNotEmpty && !_isRecognizing)
                  GestureDetector(
                    onTap: _undo,
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.4),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.undo,
                        color: Colors.white54,
                        size: 18,
                      ),
                    ),
                  ),
                if (_strokes.isNotEmpty || _fadingStrokes.isNotEmpty)
                  GestureDetector(
                    onTap: _clear,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.4),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.delete_outline,
                        color: Colors.white54,
                        size: 18,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScratchpadPainter extends CustomPainter {
  final List<List<ProDrawingPoint>> strokes;
  final Color color;
  final double alphaFade;

  _ScratchpadPainter({
    required this.strokes,
    required this.color,
    this.alphaFade = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // ---- 1. Draw Ruled Background (Righe guida) ----
    final bgPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
      
    const double lineSpacing = 40.0;
    // Start drawing lines slightly offset from the top
    for (double y = 40.0; y < size.height; y += lineSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), bgPaint);
    }

    // ---- 2. Draw Strokes ----
    if (alphaFade <= 0.0) return;
    
    final finalColor = color.withValues(alpha: color.a * alphaFade);
    
    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      
      // Dynamic pressure-sensitive rendering
      if (stroke.length == 1) {
        final p = stroke.first;
        final paint = Paint()
          ..color = finalColor
          ..style = PaintingStyle.fill;
        final r = 1.5 + (p.pressure * 2.5);
        canvas.drawCircle(p.position, r, paint);
        continue;
      }
      
      for (int i = 0; i < stroke.length - 1; i++) {
        final p1 = stroke[i];
        final p2 = stroke[i + 1];
        
        final avgPressure = (p1.pressure + p2.pressure) / 2.0;
        final w = 1.5 + (avgPressure * 3.5); // 1.5 min, 5.0 max thickness
        
        final paint = Paint()
          ..color = finalColor
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke;
          
        canvas.drawLine(p1.position, p2.position, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ScratchpadPainter oldDelegate) {
    return oldDelegate.alphaFade != alphaFade || oldDelegate.strokes != strokes;
  }
}

