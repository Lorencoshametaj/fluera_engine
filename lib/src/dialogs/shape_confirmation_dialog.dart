import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/models/shape_type.dart';

/// ⬡ Shape Recognition Confirmation Dialog
///
/// Shows a preview of the recognized shape with options to:
/// - Override the detected shape type
/// - Toggle filled/outline
/// - Delete original strokes or keep them
/// Returns the confirmed shape config or null if canceled.
class ShapeConfirmationDialog extends StatefulWidget {
  final ShapeType detectedType;
  final double confidence;
  final Rect boundingBox;
  final Color strokeColor;
  final double strokeWidth;
  final bool isEllipse;
  final double rotationAngle;

  const ShapeConfirmationDialog({
    super.key,
    required this.detectedType,
    required this.confidence,
    required this.boundingBox,
    required this.strokeColor,
    required this.strokeWidth,
    this.isEllipse = false,
    this.rotationAngle = 0.0,
  });

  /// Show the dialog and return confirmed shape config (null = canceled).
  static Future<ShapeConfirmationResult?> show(
    BuildContext context, {
    required ShapeType detectedType,
    required double confidence,
    required Rect boundingBox,
    required Color strokeColor,
    required double strokeWidth,
    bool isEllipse = false,
    double rotationAngle = 0.0,
  }) {
    return showDialog<ShapeConfirmationResult?>(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => ShapeConfirmationDialog(
            detectedType: detectedType,
            confidence: confidence,
            boundingBox: boundingBox,
            strokeColor: strokeColor,
            strokeWidth: strokeWidth,
            isEllipse: isEllipse,
            rotationAngle: rotationAngle,
          ),
    );
  }

  @override
  State<ShapeConfirmationDialog> createState() =>
      _ShapeConfirmationDialogState();
}

/// Result returned by ShapeConfirmationDialog.
class ShapeConfirmationResult {
  final ShapeType type;
  final bool filled;
  final bool deleteStrokes;

  const ShapeConfirmationResult({
    required this.type,
    required this.filled,
    required this.deleteStrokes,
  });
}

class _ShapeConfirmationDialogState extends State<ShapeConfirmationDialog> {
  late ShapeType _selectedType;
  bool _filled = false;
  bool _deleteStrokes = true;

  // All shape types available for override (excluding freehand)
  static const _shapeOptions = [
    ShapeType.line,
    ShapeType.arrow,
    ShapeType.circle,
    ShapeType.rectangle,
    ShapeType.triangle,
    ShapeType.diamond,
    ShapeType.pentagon,
    ShapeType.hexagon,
    ShapeType.star,
    ShapeType.heart,
  ];

  @override
  void initState() {
    super.initState();
    _selectedType = widget.detectedType;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confPercent = (widget.confidence * 100).round();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.hexagon_outlined,
                    color: Colors.indigo,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Shape Recognized',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_shapeLabel(widget.detectedType)} · $confPercent% confidence',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // ── Shape Preview ──
            Center(
              child: Container(
                width: 160,
                height: 120,
                decoration: BoxDecoration(
                  color:
                      isDark
                          ? Colors.white.withValues(alpha: 0.04)
                          : Colors.grey.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark ? Colors.white10 : Colors.black12,
                  ),
                ),
                child: CustomPaint(
                  painter: _ShapePreviewPainter(
                    type: _selectedType,
                    color: widget.strokeColor,
                    filled: _filled,
                    isEllipse:
                        widget.isEllipse && _selectedType == ShapeType.circle,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Shape Type Selector ──
            Text(
              'Shape Type',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _shapeOptions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final type = _shapeOptions[index];
                  final isActive = type == _selectedType;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedType = type),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color:
                            isActive
                                ? Colors.indigo.withValues(alpha: 0.15)
                                : (isDark
                                    ? Colors.white.withValues(alpha: 0.04)
                                    : Colors.grey.withValues(alpha: 0.06)),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color:
                              isActive
                                  ? Colors.indigo.withValues(alpha: 0.4)
                                  : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _shapeIcon(type),
                            size: 16,
                            color:
                                isActive
                                    ? Colors.indigo
                                    : (isDark
                                        ? Colors.white38
                                        : Colors.black38),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _shapeLabel(type),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight:
                                  isActive ? FontWeight.w600 : FontWeight.w400,
                              color:
                                  isActive
                                      ? Colors.indigo
                                      : (isDark
                                          ? Colors.white54
                                          : Colors.black45),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 12),

            // ── Fill Toggle ──
            GestureDetector(
              onTap: () => setState(() => _filled = !_filled),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color:
                      _filled
                          ? Colors.indigo.withValues(alpha: 0.1)
                          : (isDark
                              ? Colors.white.withValues(alpha: 0.04)
                              : Colors.grey.withValues(alpha: 0.06)),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color:
                        _filled
                            ? Colors.indigo.withValues(alpha: 0.3)
                            : (isDark ? Colors.white12 : Colors.black12),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _filled
                          ? Icons.format_color_fill_rounded
                          : Icons.format_color_reset_rounded,
                      size: 20,
                      color:
                          _filled
                              ? Colors.indigo
                              : (isDark ? Colors.white38 : Colors.black38),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _filled ? 'Filled' : 'Outline only',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color:
                              _filled
                                  ? (isDark ? Colors.white : Colors.black87)
                                  : (isDark ? Colors.white54 : Colors.black45),
                        ),
                      ),
                    ),
                    Switch.adaptive(
                      value: _filled,
                      activeTrackColor: Colors.indigo,
                      onChanged: (v) => setState(() => _filled = v),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 8),

            // ── Delete Strokes Toggle ──
            GestureDetector(
              onTap: () => setState(() => _deleteStrokes = !_deleteStrokes),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color:
                      _deleteStrokes
                          ? Colors.indigo.withValues(alpha: 0.1)
                          : (isDark
                              ? Colors.white.withValues(alpha: 0.04)
                              : Colors.grey.withValues(alpha: 0.06)),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color:
                        _deleteStrokes
                            ? Colors.indigo.withValues(alpha: 0.3)
                            : (isDark ? Colors.white12 : Colors.black12),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _deleteStrokes
                          ? Icons.auto_delete_rounded
                          : Icons.edit_note_rounded,
                      size: 20,
                      color:
                          _deleteStrokes
                              ? Colors.indigo
                              : (isDark ? Colors.white38 : Colors.black38),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _deleteStrokes
                            ? 'Replace strokes with shape'
                            : 'Keep strokes, add shape',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color:
                              _deleteStrokes
                                  ? (isDark ? Colors.white : Colors.black87)
                                  : (isDark ? Colors.white54 : Colors.black45),
                        ),
                      ),
                    ),
                    Switch.adaptive(
                      value: _deleteStrokes,
                      activeTrackColor: Colors.indigo,
                      onChanged: (v) => setState(() => _deleteStrokes = v),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Actions ──
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(
                      context,
                      ShapeConfirmationResult(
                        type: _selectedType,
                        filled: _filled,
                        deleteStrokes: _deleteStrokes,
                      ),
                    );
                  },
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Convert'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Shape metadata helpers
  // ═══════════════════════════════════════════════════════════════════

  static String _shapeLabel(ShapeType type) {
    return switch (type) {
      ShapeType.freehand => 'Freehand',
      ShapeType.line => 'Line',
      ShapeType.arrow => 'Arrow',
      ShapeType.circle => 'Circle',
      ShapeType.rectangle => 'Rectangle',
      ShapeType.triangle => 'Triangle',
      ShapeType.diamond => 'Diamond',
      ShapeType.pentagon => 'Pentagon',
      ShapeType.hexagon => 'Hexagon',
      ShapeType.star => 'Star',
      ShapeType.heart => 'Heart',
    };
  }

  static IconData _shapeIcon(ShapeType type) {
    return switch (type) {
      ShapeType.freehand => Icons.gesture_rounded,
      ShapeType.line => Icons.horizontal_rule_rounded,
      ShapeType.arrow => Icons.arrow_forward_rounded,
      ShapeType.circle => Icons.circle_outlined,
      ShapeType.rectangle => Icons.rectangle_outlined,
      ShapeType.triangle => Icons.change_history_rounded,
      ShapeType.diamond => Icons.diamond_outlined,
      ShapeType.pentagon => Icons.pentagon_outlined,
      ShapeType.hexagon => Icons.hexagon_outlined,
      ShapeType.star => Icons.star_outline_rounded,
      ShapeType.heart => Icons.favorite_outline_rounded,
    };
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 🎨 Shape Preview Painter
// ═══════════════════════════════════════════════════════════════════════

class _ShapePreviewPainter extends CustomPainter {
  final ShapeType type;
  final Color color;
  final bool filled;
  final bool isEllipse;

  _ShapePreviewPainter({
    required this.type,
    required this.color,
    required this.filled,
    this.isEllipse = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..strokeWidth = 2.5
          ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final w = size.width * 0.7;
    final h = size.height * 0.7;

    switch (type) {
      case ShapeType.line:
        canvas.drawLine(Offset(cx - w / 2, cy), Offset(cx + w / 2, cy), paint);
      case ShapeType.arrow:
        final start = Offset(cx - w / 2, cy);
        final end = Offset(cx + w / 2, cy);
        canvas.drawLine(start, end, paint);
        // Arrowhead
        final headLen = w * 0.2;
        canvas.drawLine(
          end,
          Offset(end.dx - headLen, end.dy - headLen * 0.6),
          paint,
        );
        canvas.drawLine(
          end,
          Offset(end.dx - headLen, end.dy + headLen * 0.6),
          paint,
        );
      case ShapeType.circle:
        if (isEllipse) {
          canvas.drawOval(
            Rect.fromCenter(center: Offset(cx, cy), width: w, height: h * 0.6),
            paint,
          );
        } else {
          final r = math.min(w, h) / 2;
          canvas.drawCircle(Offset(cx, cy), r, paint);
        }
      case ShapeType.rectangle:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(cx, cy), width: w, height: h * 0.7),
            const Radius.circular(2),
          ),
          paint,
        );
      case ShapeType.triangle:
        final path =
            Path()
              ..moveTo(cx, cy - h / 2)
              ..lineTo(cx - w / 2, cy + h / 2)
              ..lineTo(cx + w / 2, cy + h / 2)
              ..close();
        canvas.drawPath(path, paint);
      case ShapeType.diamond:
        final path =
            Path()
              ..moveTo(cx, cy - h / 2)
              ..lineTo(cx + w / 2, cy)
              ..lineTo(cx, cy + h / 2)
              ..lineTo(cx - w / 2, cy)
              ..close();
        canvas.drawPath(path, paint);
      case ShapeType.pentagon:
        _drawRegularPolygon(canvas, Offset(cx, cy), w / 2, 5, paint);
      case ShapeType.hexagon:
        _drawRegularPolygon(canvas, Offset(cx, cy), w / 2, 6, paint);
      case ShapeType.star:
        _drawStar(canvas, Offset(cx, cy), w / 2, h / 2, paint);
      case ShapeType.heart:
        _drawHeart(canvas, Offset(cx, cy), w, h, paint);
      case ShapeType.freehand:
        break;
    }
  }

  void _drawRegularPolygon(
    Canvas canvas,
    Offset center,
    double radius,
    int sides,
    Paint paint,
  ) {
    final path = Path();
    for (int i = 0; i < sides; i++) {
      final angle = -math.pi / 2 + (2 * math.pi * i / sides);
      final x = center.dx + radius * math.cos(angle);
      final y = center.dy + radius * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawStar(
    Canvas canvas,
    Offset center,
    double rx,
    double ry,
    Paint paint,
  ) {
    final path = Path();
    final outerR = math.min(rx, ry);
    final innerR = outerR * 0.4;
    for (int i = 0; i < 10; i++) {
      final r = i.isEven ? outerR : innerR;
      final angle = -math.pi / 2 + (math.pi * i / 5);
      final x = center.dx + r * math.cos(angle);
      final y = center.dy + r * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawHeart(
    Canvas canvas,
    Offset center,
    double w,
    double h,
    Paint paint,
  ) {
    final path = Path();
    final hw = w / 2;
    final hh = h / 2;
    // Heart using cubic beziers
    path.moveTo(center.dx, center.dy + hh * 0.6);
    // Left bump
    path.cubicTo(
      center.dx - hw * 1.2,
      center.dy - hh * 0.2,
      center.dx - hw * 0.6,
      center.dy - hh * 0.9,
      center.dx,
      center.dy - hh * 0.3,
    );
    // Right bump
    path.cubicTo(
      center.dx + hw * 0.6,
      center.dy - hh * 0.9,
      center.dx + hw * 1.2,
      center.dy - hh * 0.2,
      center.dx,
      center.dy + hh * 0.6,
    );
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ShapePreviewPainter oldDelegate) =>
      type != oldDelegate.type ||
      color != oldDelegate.color ||
      filled != oldDelegate.filled ||
      isEllipse != oldDelegate.isEllipse;
}
