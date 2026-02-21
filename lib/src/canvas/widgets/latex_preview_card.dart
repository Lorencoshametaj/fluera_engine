import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/latex/latex_parser.dart';
import '../../core/latex/latex_layout_engine.dart';
import '../../core/latex/latex_draw_command.dart';

/// 🧮 LatexPreviewCard — Enterprise-grade Material Design 3 live preview.
///
/// ## Enterprise Features
/// - **E10** Pinch-to-zoom via InteractiveViewer
/// - **E11** Copy-to-clipboard on long-press
/// - **E12** Error recovery: partial render up to the error point
///
/// Parses → layouts → renders the expression in real-time using a custom
/// painter. Automatically re-renders when [latexSource], [fontSize], or
/// [color] change.
class LatexPreviewCard extends StatefulWidget {
  /// The LaTeX source string to preview.
  final String latexSource;

  /// Base font size for the expression.
  final double fontSize;

  /// Text color for the expression.
  final Color color;

  /// Optional minimum height for the preview area.
  final double minHeight;

  /// Optional background color override.
  final Color? backgroundColor;

  const LatexPreviewCard({
    super.key,
    required this.latexSource,
    this.fontSize = 24.0,
    this.color = Colors.white,
    this.minHeight = 80,
    this.backgroundColor,
  });

  @override
  State<LatexPreviewCard> createState() => _LatexPreviewCardState();
}

class _LatexPreviewCardState extends State<LatexPreviewCard> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      // E11: Copy to clipboard on long-press
      onLongPress:
          widget.latexSource.isNotEmpty
              ? () {
                Clipboard.setData(ClipboardData(text: widget.latexSource));
                HapticFeedback.mediumImpact();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('LaTeX copiato negli appunti'),
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                );
              }
              : null,
      child: Container(
        constraints: BoxConstraints(minHeight: widget.minHeight),
        decoration: BoxDecoration(
          color:
              widget.backgroundColor ??
              cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
        child:
            widget.latexSource.isEmpty
                ? _buildEmptyState(cs)
                : ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _buildPreview(cs, context),
                ),
      ),
    );
  }

  Widget _buildPreview(ColorScheme cs, BuildContext context) {
    // E12: Try to parse, with error recovery
    LatexLayoutResult? layoutResult;
    String? parseError;

    try {
      final ast = LatexParser.parse(widget.latexSource);
      layoutResult = LatexLayoutEngine.layout(
        ast,
        fontSize: widget.fontSize,
        color: widget.color,
      );
    } catch (e) {
      parseError = e.toString();

      // E12: Attempt partial render
      if (widget.latexSource.length > 4) {
        try {
          var cutoff = widget.latexSource.length;
          for (int i = widget.latexSource.length - 1; i > 0; i--) {
            if (widget.latexSource[i] == '{' ||
                widget.latexSource[i] == '}' ||
                widget.latexSource[i] == '\\') {
              cutoff = i;
              break;
            }
          }
          if (cutoff > 0 && cutoff < widget.latexSource.length) {
            final partial = widget.latexSource.substring(0, cutoff);
            final ast = LatexParser.parse(partial);
            layoutResult = LatexLayoutEngine.layout(
              ast,
              fontSize: widget.fontSize,
              color: widget.color,
            );
          }
        } catch (_) {
          // Both full and partial parsing failed
        }
      }
    }

    if (layoutResult == null || layoutResult.commands.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 24, color: cs.error),
            const SizedBox(height: 6),
            Text(
              'Errore nel rendering',
              style: TextStyle(
                color: cs.error,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (parseError != null) ...[
              const SizedBox(height: 4),
              Text(
                parseError.length > 60
                    ? '${parseError.substring(0, 57)}…'
                    : parseError,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      );
    }

    // E12: Partial render indicator
    final isPartial = parseError != null;

    // E10: Wrap in InteractiveViewer for pinch-to-zoom
    return Stack(
      children: [
        Center(
          child: InteractiveViewer(
            boundaryMargin: const EdgeInsets.all(40),
            minScale: 0.5,
            maxScale: 5.0,
            child: CustomPaint(
              size: layoutResult.size,
              painter: _LatexPreviewPainter(layoutResult.commands),
            ),
          ),
        ),
        // E12: Partial render warning badge
        if (isPartial)
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: cs.tertiaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 12,
                    color: cs.onTertiaryContainer,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Parziale',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: cs.onTertiaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ),
        // E10: Zoom hint (bottom-right)
        Positioned(
          bottom: 0,
          right: 0,
          child: Icon(
            Icons.pinch_rounded,
            size: 14,
            color: cs.onSurfaceVariant.withValues(alpha: 0.3),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.functions_rounded, size: 32, color: cs.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(
            'Scrivi un\'espressione LaTeX',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            'Tieni premuto per copiare',
            style: TextStyle(
              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter that executes [LatexDrawCommand]s.
class _LatexPreviewPainter extends CustomPainter {
  final List<LatexDrawCommand> commands;

  _LatexPreviewPainter(this.commands);

  @override
  void paint(Canvas canvas, Size size) {
    for (final cmd in commands) {
      switch (cmd) {
        case GlyphDrawCommand():
          final style = TextStyle(
            fontSize: cmd.fontSize,
            color: cmd.color,
            fontStyle: cmd.italic ? FontStyle.italic : FontStyle.normal,
            fontWeight: cmd.bold ? FontWeight.bold : FontWeight.normal,
            fontFamily: cmd.fontFamily.isNotEmpty ? cmd.fontFamily : null,
          );
          final tp = TextPainter(
            text: TextSpan(text: cmd.text, style: style),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, Offset(cmd.x, cmd.y));

        case LineDrawCommand():
          canvas.drawLine(
            Offset(cmd.x1, cmd.y1),
            Offset(cmd.x2, cmd.y2),
            Paint()
              ..color = cmd.color
              ..strokeWidth = cmd.thickness
              ..strokeCap = StrokeCap.butt
              ..isAntiAlias = true,
          );

        case PathDrawCommand():
          if (cmd.points.isEmpty) continue;
          final path = Path()..moveTo(cmd.points.first.dx, cmd.points.first.dy);
          for (int i = 1; i < cmd.points.length; i++) {
            path.lineTo(cmd.points[i].dx, cmd.points[i].dy);
          }
          if (cmd.closed) path.close();
          canvas.drawPath(
            path,
            Paint()
              ..color = cmd.color
              ..style = cmd.filled ? PaintingStyle.fill : PaintingStyle.stroke
              ..strokeWidth = cmd.strokeWidth
              ..strokeCap = StrokeCap.round
              ..isAntiAlias = true,
          );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LatexPreviewPainter old) =>
      commands != old.commands;
}
