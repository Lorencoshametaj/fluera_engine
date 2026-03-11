import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/latex/latex_evaluator.dart';
import 'graph_painter.dart';
import 'graph_widgets.dart';

// =============================================================================
// LATEX FUNCTION GRAPH WIDGET
// =============================================================================

/// 📈 Interactive function graph for LaTeX expressions.
///
/// Parses a LaTeX string, evaluates it numerically for a range of x values,
/// and renders the curve on a coordinate plane with grid, axes, and overlays.
///
/// Features:
/// - Pan + pinch-to-zoom navigation
/// - Crosshair with value readout on touch
/// - Categorized toolbar (Zoom, Analysis, Display, Didactic)
/// - Info badges (zoom level, function domain)
/// - Optional derivative curve and area shading
class LatexFunctionGraph extends StatefulWidget {
  /// The LaTeX source string to graph (e.g. `\sin(x)` or `\frac{x^2}{2}`).
  final String latexSource;

  /// Initial color for the curve.
  final Color curveColor;

  const LatexFunctionGraph({
    super.key,
    required this.latexSource,
    this.curveColor = Colors.blue,
  });

  @override
  State<LatexFunctionGraph> createState() => _LatexFunctionGraphState();
}

class _LatexFunctionGraphState extends State<LatexFunctionGraph> {
  // ── Viewport ──
  double _xMin = -10;
  double _xMax = 10;
  double _yMin = -6;
  double _yMax = 6;

  // ── Samples ──
  static const int _sampleCount = 500;
  List<Offset> _points = [];
  List<Offset> _derivativePoints = [];

  // ── Display toggles ──
  bool _showGrid = true;
  bool _showMinorGrid = false;
  bool _showAxes = true;
  bool _showDerivative = false;
  bool _showArea = false;

  // ── Crosshair ──
  Offset? _crosshair; // math coords
  bool _isTouching = false;

  // ── Gesture state ──
  double? _panStartX;
  double? _panStartY;
  double _panAnchorXMin = 0;
  double _panAnchorXMax = 0;
  double _panAnchorYMin = 0;
  double _panAnchorYMax = 0;
  double _scaleAnchor = 1.0;

  @override
  void initState() {
    super.initState();
    _resample();
  }

  @override
  void didUpdateWidget(covariant LatexFunctionGraph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.latexSource != widget.latexSource) {
      _resample();
    }
  }

  void _resample() {
    final xRange = _xMax - _xMin;
    final step = xRange / _sampleCount;

    final pts = <Offset>[];
    final dpts = <Offset>[];

    for (int i = 0; i <= _sampleCount; i++) {
      final x = _xMin + step * i;
      final y = LatexEvaluator.evaluateSource(widget.latexSource, x);
      pts.add(Offset(x, y));

      // Numerical derivative (central difference)
      if (_showDerivative) {
        const h = 0.001;
        final yPlus = LatexEvaluator.evaluateSource(widget.latexSource, x + h);
        final yMinus = LatexEvaluator.evaluateSource(widget.latexSource, x - h);
        final dy = (yPlus - yMinus) / (2 * h);
        dpts.add(Offset(x, dy));
      }
    }

    setState(() {
      _points = pts;
      _derivativePoints = dpts;
    });
  }

  void _resetView() {
    setState(() {
      _xMin = -10;
      _xMax = 10;
      _yMin = -6;
      _yMax = 6;
    });
    _resample();
  }

  void _zoomIn() {
    final cx = (_xMin + _xMax) / 2;
    final cy = (_yMin + _yMax) / 2;
    final xr = (_xMax - _xMin) * 0.35;
    final yr = (_yMax - _yMin) * 0.35;
    setState(() {
      _xMin = cx - xr;
      _xMax = cx + xr;
      _yMin = cy - yr;
      _yMax = cy + yr;
    });
    _resample();
  }

  void _zoomOut() {
    final cx = (_xMin + _xMax) / 2;
    final cy = (_yMin + _yMax) / 2;
    final xr = (_xMax - _xMin) * 0.75;
    final yr = (_yMax - _yMin) * 0.75;
    setState(() {
      _xMin = cx - xr;
      _xMax = cx + xr;
      _yMin = cy - yr;
      _yMax = cy + yr;
    });
    _resample();
  }

  void _autoFit() {
    // Find y-range from the data
    double minY = double.infinity;
    double maxY = double.negativeInfinity;
    for (final pt in _points) {
      if (pt.dy.isFinite && pt.dy.abs() < 1e6) {
        if (pt.dy < minY) minY = pt.dy;
        if (pt.dy > maxY) maxY = pt.dy;
      }
    }
    if (minY.isInfinite || maxY.isInfinite) return;
    final margin = (maxY - minY) * 0.15;
    setState(() {
      _yMin = minY - margin;
      _yMax = maxY + margin;
    });
    _resample();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zoomLevel = (20 / (_xMax - _xMin) * 100).round();

    return Column(
      children: [
        // ── Graph area with gestures ──
        Expanded(
          child: Stack(
            children: [
              // Graph
              GestureDetector(
                onScaleStart: (d) {
                  _panStartX = d.localFocalPoint.dx;
                  _panStartY = d.localFocalPoint.dy;
                  _panAnchorXMin = _xMin;
                  _panAnchorXMax = _xMax;
                  _panAnchorYMin = _yMin;
                  _panAnchorYMax = _yMax;
                  _scaleAnchor = 1.0;
                },
                onScaleUpdate: (d) {
                  if (_panStartX == null) return;
                  final size = context.size;
                  if (size == null) return;

                  if (d.scale != 1.0) {
                    // Pinch zoom
                    final factor = _scaleAnchor / d.scale;
                    final cx = (_panAnchorXMin + _panAnchorXMax) / 2;
                    final cy = (_panAnchorYMin + _panAnchorYMax) / 2;
                    final xr = (_panAnchorXMax - _panAnchorXMin) / 2 * factor;
                    final yr = (_panAnchorYMax - _panAnchorYMin) / 2 * factor;
                    setState(() {
                      _xMin = cx - xr;
                      _xMax = cx + xr;
                      _yMin = cy - yr;
                      _yMax = cy + yr;
                    });
                  } else {
                    // Pan
                    final dx = d.localFocalPoint.dx - _panStartX!;
                    final dy = d.localFocalPoint.dy - _panStartY!;
                    final xShift =
                        -dx / size.width * (_panAnchorXMax - _panAnchorXMin);
                    final yShift =
                        dy / size.height * (_panAnchorYMax - _panAnchorYMin);
                    setState(() {
                      _xMin = _panAnchorXMin + xShift;
                      _xMax = _panAnchorXMax + xShift;
                      _yMin = _panAnchorYMin + yShift;
                      _yMax = _panAnchorYMax + yShift;
                    });
                  }
                  _resample();
                },
                onScaleEnd: (_) {
                  _panStartX = null;
                  _panStartY = null;
                },
                onLongPressStart: (d) {
                  HapticFeedback.selectionClick();
                  _updateCrosshair(d.localPosition);
                  setState(() => _isTouching = true);
                },
                onLongPressMoveUpdate: (d) {
                  _updateCrosshair(d.localPosition);
                },
                onLongPressEnd: (_) {
                  setState(() {
                    _isTouching = false;
                    _crosshair = null;
                  });
                },
                child: ClipRect(
                  child: CustomPaint(
                    painter: FunctionGraphPainter(
                      points: _points,
                      derivativePoints:
                          _showDerivative ? _derivativePoints : null,
                      xMin: _xMin,
                      xMax: _xMax,
                      yMin: _yMin,
                      yMax: _yMax,
                      showGrid: _showGrid,
                      showMinorGrid: _showMinorGrid,
                      showAxes: _showAxes,
                      showDerivative: _showDerivative,
                      showArea: _showArea,
                      crosshair: _crosshair,
                      curveColor: widget.curveColor,
                    ),
                    size: Size.infinite,
                  ),
                ),
              ),

              // Info badges (top-right)
              Positioned(
                top: 8,
                right: 8,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    GraphInfoBadge(
                      icon: Icons.zoom_in_rounded,
                      label: '$zoomLevel%',
                    ),
                    const SizedBox(height: 4),
                    GraphInfoBadge(
                      icon: Icons.straighten_rounded,
                      label:
                          'x∈[${_xMin.toStringAsFixed(1)}, ${_xMax.toStringAsFixed(1)}]',
                    ),
                  ],
                ),
              ),

              // Crosshair tooltip
              if (_isTouching && _crosshair != null)
                Positioned(
                  top: 8,
                  left: 8,
                  child: GraphValueTooltip(
                    x: _crosshair!.dx,
                    y: _crosshair!.dy,
                  ),
                ),
            ],
          ),
        ),

        const Divider(height: 1),

        // ── Toolbar ──
        _buildToolbar(cs),
      ],
    );
  }

  void _updateCrosshair(Offset localPos) {
    final size = context.size;
    if (size == null) return;
    final mx = _xMin + (localPos.dx / size.width) * (_xMax - _xMin);
    final my = LatexEvaluator.evaluateSource(widget.latexSource, mx);
    setState(() {
      _crosshair = Offset(mx, my);
    });
  }

  Widget _buildToolbar(ColorScheme cs) {
    return Container(
      color: cs.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // ── Zoom group ──
            GraphToolbarGroup(
              label: 'ZOOM',
              children: [
                _toolChip(cs, Icons.zoom_in_rounded, 'Zoom +', _zoomIn),
                _toolChip(cs, Icons.zoom_out_rounded, 'Zoom −', _zoomOut),
                _toolChip(cs, Icons.fit_screen_rounded, 'Auto', _autoFit),
                _toolChip(cs, Icons.restart_alt_rounded, 'Reset', _resetView),
              ],
            ),
            _separator(),

            // ── Analysis group ──
            GraphToolbarGroup(
              label: 'ANALISI',
              children: [
                _toggleChip(
                  cs,
                  Icons.show_chart_rounded,
                  "f'(x)",
                  _showDerivative,
                  () {
                    setState(() => _showDerivative = !_showDerivative);
                    _resample();
                  },
                ),
                _toggleChip(
                  cs,
                  Icons.area_chart_rounded,
                  'Area',
                  _showArea,
                  () {
                    setState(() => _showArea = !_showArea);
                  },
                ),
              ],
            ),
            _separator(),

            // ── Display group ──
            GraphToolbarGroup(
              label: 'DISPLAY',
              children: [
                _toggleChip(
                  cs,
                  Icons.grid_on_rounded,
                  'Griglia',
                  _showGrid,
                  () {
                    setState(() => _showGrid = !_showGrid);
                  },
                ),
                _toggleChip(
                  cs,
                  Icons.grid_4x4_rounded,
                  'Minore',
                  _showMinorGrid,
                  () {
                    setState(() => _showMinorGrid = !_showMinorGrid);
                  },
                ),
                _toggleChip(
                  cs,
                  Icons.straighten_rounded,
                  'Assi',
                  _showAxes,
                  () {
                    setState(() => _showAxes = !_showAxes);
                  },
                ),
              ],
            ),
            _separator(),

            // ── Didactic group ──
            GraphToolbarGroup(
              label: 'DIDATTICO',
              children: [
                _toolChip(cs, Icons.share_rounded, 'Condividi', () {
                  Clipboard.setData(
                    ClipboardData(
                      text:
                          'f(x) = ${widget.latexSource}\n'
                          'x ∈ [${_xMin.toStringAsFixed(2)}, ${_xMax.toStringAsFixed(2)}]',
                    ),
                  );
                  HapticFeedback.mediumImpact();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Funzione copiata'),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolChip(
    ColorScheme cs,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    return ActionChip(
      avatar: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      onPressed: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _toggleChip(
    ColorScheme cs,
    IconData icon,
    String label,
    bool active,
    VoidCallback onTap,
  ) {
    return FilterChip(
      avatar: Icon(icon, size: 14, color: active ? cs.onPrimary : null),
      label: Text(
        label,
        style: TextStyle(fontSize: 11, color: active ? cs.onPrimary : null),
      ),
      selected: active,
      onSelected: (_) {
        HapticFeedback.selectionClick();
        onTap();
      },
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _separator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Container(
        width: 1,
        height: 40,
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }
}
