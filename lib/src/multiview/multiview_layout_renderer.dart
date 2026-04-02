import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/advanced_split_layout.dart';

// =============================================================================
// MULTIVIEW LAYOUT RENDERER — Arranges panels in a grid with dividers
// =============================================================================

/// Renders the multiview panel grid according to [AdvancedSplitLayout].
///
/// Features:
/// - Supports all 7 `SplitLayoutType` configurations
/// - Draggable dividers for resizing panels
/// - Active panel border highlighting
class MultiviewLayoutRenderer extends StatefulWidget {
  final AdvancedSplitLayout layout;
  final int activePanelIndex;
  final List<Widget> panels;
  final ValueChanged<Map<String, double>> onProportionsChanged;

  const MultiviewLayoutRenderer({
    super.key,
    required this.layout,
    required this.activePanelIndex,
    required this.panels,
    required this.onProportionsChanged,
  });

  @override
  State<MultiviewLayoutRenderer> createState() =>
      _MultiviewLayoutRendererState();
}

class _MultiviewLayoutRendererState extends State<MultiviewLayoutRenderer> {
  static const double _dividerThickness = 6.0;
  static const double _dividerHitArea = 20.0;
  static const double _minProportion = 0.15;
  // OPT #5: static const for divider grab handle
  static const _grabBorderRadius = BorderRadius.all(Radius.circular(1));

  // OPT #2: Stopwatch is monotonic and allocation-free (vs DateTime.now())
  final Stopwatch _hapticStopwatch = Stopwatch()..start();

  late Map<String, double> _proportions;

  @override
  void initState() {
    super.initState();
    _proportions = Map.from(widget.layout.proportions);
    _ensureDefaultProportions();
  }

  @override
  void didUpdateWidget(MultiviewLayoutRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layout.type != widget.layout.type) {
      _proportions = Map.from(widget.layout.proportions);
      _ensureDefaultProportions();
    }
  }

  void _ensureDefaultProportions() {
    final count = widget.layout.panelCount;
    final defaultProportion = 1.0 / count;
    for (int i = 0; i < count; i++) {
      _proportions.putIfAbsent('panel_$i', () => defaultProportion);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return _buildLayout(constraints);
      },
    );
  }

  Widget _buildLayout(BoxConstraints constraints) {
    switch (widget.layout.type) {
      case SplitLayoutType.split2:
        return _buildSplit2(constraints);
      case SplitLayoutType.split3Horizontal:
        return _buildSplit3Horizontal(constraints);
      case SplitLayoutType.split3Vertical:
        return _buildSplit3Vertical(constraints);
      case SplitLayoutType.split3Mixed:
        return _buildSplit3Mixed(constraints);
      case SplitLayoutType.split4Grid:
        return _buildSplit4Grid(constraints);
      case SplitLayoutType.split4Rows:
        return _buildSplit4Rows(constraints);
      case SplitLayoutType.split4Columns:
        return _buildSplit4Columns(constraints);
    }
  }

  // ============================================================================
  // LAYOUT BUILDERS
  // ============================================================================

  /// 2 panels side by side (or stacked, depending on orientation)
  Widget _buildSplit2(BoxConstraints constraints) {
    final isHorizontal =
        widget.layout.primaryOrientation == SplitOrientation.horizontal;
    final prop = _proportions['panel_0'] ?? 0.5;

    if (isHorizontal) {
      final totalWidth = constraints.maxWidth - _dividerThickness;
      return Row(
        children: [
          SizedBox(width: totalWidth * prop, child: widget.panels[0]),
          _buildDivider(
            axis: Axis.vertical,
            onDrag:
                (delta) => _updateProportion(
                  'panel_0',
                  delta.dx,
                  constraints.maxWidth,
                ),
          ),
          Expanded(child: widget.panels[1]),
        ],
      );
    } else {
      final totalHeight = constraints.maxHeight - _dividerThickness;
      return Column(
        children: [
          SizedBox(height: totalHeight * prop, child: widget.panels[0]),
          _buildDivider(
            axis: Axis.horizontal,
            onDrag:
                (delta) => _updateProportion(
                  'panel_0',
                  delta.dy,
                  constraints.maxHeight,
                ),
          ),
          Expanded(child: widget.panels[1]),
        ],
      );
    }
  }

  /// 3 panels in a row
  Widget _buildSplit3Horizontal(BoxConstraints constraints) {
    final p0 = _proportions['panel_0'] ?? 0.333;
    final p1 = _proportions['panel_1'] ?? 0.333;
    final totalWidth = constraints.maxWidth - _dividerThickness * 2;

    return Row(
      children: [
        SizedBox(width: totalWidth * p0, child: widget.panels[0]),
        _buildDivider(
          axis: Axis.vertical,
          onDrag:
              (delta) =>
                  _updateProportion('panel_0', delta.dx, constraints.maxWidth),
        ),
        SizedBox(width: totalWidth * p1, child: widget.panels[1]),
        _buildDivider(
          axis: Axis.vertical,
          onDrag:
              (delta) =>
                  _updateProportion('panel_1', delta.dx, constraints.maxWidth),
        ),
        Expanded(child: widget.panels[2]),
      ],
    );
  }

  /// 3 panels in a column
  Widget _buildSplit3Vertical(BoxConstraints constraints) {
    final p0 = _proportions['panel_0'] ?? 0.333;
    final p1 = _proportions['panel_1'] ?? 0.333;
    final totalHeight = constraints.maxHeight - _dividerThickness * 2;

    return Column(
      children: [
        SizedBox(height: totalHeight * p0, child: widget.panels[0]),
        _buildDivider(
          axis: Axis.horizontal,
          onDrag:
              (delta) =>
                  _updateProportion('panel_0', delta.dy, constraints.maxHeight),
        ),
        SizedBox(height: totalHeight * p1, child: widget.panels[1]),
        _buildDivider(
          axis: Axis.horizontal,
          onDrag:
              (delta) =>
                  _updateProportion('panel_1', delta.dy, constraints.maxHeight),
        ),
        Expanded(child: widget.panels[2]),
      ],
    );
  }

  /// 1 large panel + 2 small panels (mixed)
  Widget _buildSplit3Mixed(BoxConstraints constraints) {
    final mainProp = _proportions['panel_0'] ?? 0.6;
    final totalWidth = constraints.maxWidth - _dividerThickness;

    return Row(
      children: [
        SizedBox(width: totalWidth * mainProp, child: widget.panels[0]),
        _buildDivider(
          axis: Axis.vertical,
          onDrag:
              (delta) =>
                  _updateProportion('panel_0', delta.dx, constraints.maxWidth),
        ),
        Expanded(
          child: Column(
            children: [
              Expanded(child: widget.panels[1]),
              _buildDivider(
                axis: Axis.horizontal,
                onDrag:
                    (delta) => _updateProportion(
                      'panel_1',
                      delta.dy,
                      constraints.maxHeight,
                    ),
              ),
              Expanded(child: widget.panels[2]),
            ],
          ),
        ),
      ],
    );
  }

  /// 2×2 grid
  Widget _buildSplit4Grid(BoxConstraints constraints) {
    final hProp = _proportions['panel_0'] ?? 0.5;
    final vProp = _proportions['panel_v'] ?? 0.5;
    final totalWidth = constraints.maxWidth - _dividerThickness;
    final totalHeight = constraints.maxHeight - _dividerThickness;

    return Column(
      children: [
        SizedBox(
          height: totalHeight * vProp,
          child: Row(
            children: [
              SizedBox(width: totalWidth * hProp, child: widget.panels[0]),
              _buildDivider(
                axis: Axis.vertical,
                onDrag:
                    (delta) => _updateProportion(
                      'panel_0',
                      delta.dx,
                      constraints.maxWidth,
                    ),
              ),
              Expanded(child: widget.panels[1]),
            ],
          ),
        ),
        _buildDivider(
          axis: Axis.horizontal,
          onDrag:
              (delta) =>
                  _updateProportion('panel_v', delta.dy, constraints.maxHeight),
        ),
        Expanded(
          child: Row(
            children: [
              SizedBox(width: totalWidth * hProp, child: widget.panels[2]),
              _buildDivider(
                axis: Axis.vertical,
                onDrag:
                    (delta) => _updateProportion(
                      'panel_0',
                      delta.dx,
                      constraints.maxWidth,
                    ),
              ),
              Expanded(child: widget.panels[3]),
            ],
          ),
        ),
      ],
    );
  }

  /// 4 rows stacked
  Widget _buildSplit4Rows(BoxConstraints constraints) {
    final props = List.generate(3, (i) => _proportions['panel_$i'] ?? 0.25);
    final totalHeight = constraints.maxHeight - _dividerThickness * 3;

    return Column(
      children: [
        for (int i = 0; i < 3; i++) ...[
          SizedBox(height: totalHeight * props[i], child: widget.panels[i]),
          _buildDivider(
            axis: Axis.horizontal,
            onDrag:
                (delta) => _updateProportion(
                  'panel_$i',
                  delta.dy,
                  constraints.maxHeight,
                ),
          ),
        ],
        Expanded(child: widget.panels[3]),
      ],
    );
  }

  /// 4 columns side by side
  Widget _buildSplit4Columns(BoxConstraints constraints) {
    final props = List.generate(3, (i) => _proportions['panel_$i'] ?? 0.25);
    final totalWidth = constraints.maxWidth - _dividerThickness * 3;

    return Row(
      children: [
        for (int i = 0; i < 3; i++) ...[
          SizedBox(width: totalWidth * props[i], child: widget.panels[i]),
          _buildDivider(
            axis: Axis.vertical,
            onDrag:
                (delta) => _updateProportion(
                  'panel_$i',
                  delta.dx,
                  constraints.maxWidth,
                ),
          ),
        ],
        Expanded(child: widget.panels[3]),
      ],
    );
  }

  // ============================================================================
  // DIVIDER
  // ============================================================================

  Widget _buildDivider({
    required Axis axis,
    required void Function(Offset delta) onDrag,
  }) {
    final isVertical = axis == Axis.vertical;
    final cs = Theme.of(context).colorScheme;
    final hitPadding = (_dividerHitArea - _dividerThickness) / 2;

    return MouseRegion(
      cursor:
          isVertical
              ? SystemMouseCursors.resizeColumn
              : SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) {
          // OPT #2: Stopwatch avoids DateTime.now() syscall allocation
          if (_hapticStopwatch.elapsedMilliseconds > 100) {
            HapticFeedback.selectionClick();
            _hapticStopwatch.reset();
          }
          onDrag(details.delta);
        },
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isVertical ? hitPadding : 0,
            vertical: isVertical ? 0 : hitPadding,
          ),
          child: Container(
            width: isVertical ? _dividerThickness : double.infinity,
            height: isVertical ? double.infinity : _dividerThickness,
            color: cs.outlineVariant.withValues(alpha: 0.2),
            child: Center(
              child: Container(
                width: isVertical ? 2 : 32,
                height: isVertical ? 32 : 2,
                decoration: BoxDecoration(
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                  borderRadius: _grabBorderRadius, // OPT #5
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================================
  // PROPORTION UPDATE
  // ============================================================================

  void _updateProportion(String key, double delta, double totalSize) {
    setState(() {
      final current = _proportions[key] ?? 0.5;
      final newValue = (current + delta / totalSize).clamp(
        _minProportion,
        1.0 - _minProportion,
      );
      _proportions[key] = newValue;
    });
    widget.onProportionsChanged(_proportions);
  }
}
