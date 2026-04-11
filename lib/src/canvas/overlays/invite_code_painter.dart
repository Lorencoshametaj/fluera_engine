// ============================================================================
// 📱 QR CODE PAINTER — Lightweight QR-like grid code (P7-02)
//
// Renders an invite code as a visual grid pattern for quick scanning.
// Uses a simple hash-based grid (NOT a real QR code standard) since this
// is for visual identification only — actual joining uses the room ID text.
//
// For production QR codes, the host app can provide a qr_flutter widget
// via the FlueraP2PConnector or config callback.
// ============================================================================

import 'package:flutter/material.dart';

/// 📱 Visual Code Painter.
///
/// Renders the room code as a distinctive visual pattern.
/// This is a simplified grid representation — NOT ISO 18004 standard QR.
/// It serves as a quick visual identifier that the peer can recognize.
class InviteCodePainter extends CustomPainter {
  /// The room code to render.
  final String code;

  /// Module (dot) color.
  final Color moduleColor;

  /// Background color.
  final Color backgroundColor;

  /// Number of modules per side.
  final int gridSize;

  InviteCodePainter({
    required this.code,
    this.moduleColor = Colors.white,
    this.backgroundColor = Colors.transparent,
    this.gridSize = 11,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final moduleSize = size.width / gridSize;
    final radius = moduleSize * 0.35;

    final paint = Paint()..color = moduleColor;
    final bgPaint = Paint()..color = backgroundColor;

    // Background.
    if (backgroundColor != Colors.transparent) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(moduleSize),
        ),
        bgPaint,
      );
    }

    // Generate deterministic grid from code hash.
    final grid = _generateGrid(code, gridSize);

    // Draw modules.
    for (int y = 0; y < gridSize; y++) {
      for (int x = 0; x < gridSize; x++) {
        if (grid[y * gridSize + x]) {
          final center = Offset(
            (x + 0.5) * moduleSize,
            (y + 0.5) * moduleSize,
          );
          canvas.drawCircle(center, radius, paint);
        }
      }
    }

    // Draw finder patterns (3 corners).
    _drawFinderPattern(canvas, 0, 0, moduleSize, paint);
    _drawFinderPattern(canvas, gridSize - 3, 0, moduleSize, paint);
    _drawFinderPattern(canvas, 0, gridSize - 3, moduleSize, paint);
  }

  void _drawFinderPattern(
    Canvas canvas,
    int startX,
    int startY,
    double moduleSize,
    Paint paint,
  ) {
    final outerPaint = Paint()
      ..color = moduleColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = moduleSize * 0.3;

    final innerPaint = Paint()..color = moduleColor;

    // Outer ring.
    final outerRect = Rect.fromLTWH(
      (startX + 0.3) * moduleSize,
      (startY + 0.3) * moduleSize,
      2.4 * moduleSize,
      2.4 * moduleSize,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(outerRect, Radius.circular(moduleSize * 0.4)),
      outerPaint,
    );

    // Center dot.
    final center = Offset(
      (startX + 1.5) * moduleSize,
      (startY + 1.5) * moduleSize,
    );
    canvas.drawCircle(center, moduleSize * 0.35, innerPaint);
  }

  /// Generate a deterministic grid from a code string.
  static List<bool> _generateGrid(String code, int size) {
    final grid = List<bool>.filled(size * size, false);

    // Simple hash: spread code characters across grid.
    int hash = 0;
    for (int i = 0; i < code.length; i++) {
      hash = (hash * 31 + code.codeUnitAt(i)) & 0x7FFFFFFF;
    }

    // Fill data area (excluding finder pattern zones).
    final rng = _SimpleRng(hash);
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        // Skip finder pattern zones.
        if (_isFinderZone(x, y, size)) continue;

        grid[y * size + x] = rng.nextBool();
      }
    }

    return grid;
  }

  static bool _isFinderZone(int x, int y, int size) {
    // Top-left 3x3.
    if (x < 3 && y < 3) return true;
    // Top-right 3x3.
    if (x >= size - 3 && y < 3) return true;
    // Bottom-left 3x3.
    if (x < 3 && y >= size - 3) return true;
    return false;
  }

  @override
  bool shouldRepaint(InviteCodePainter oldDelegate) =>
      code != oldDelegate.code || moduleColor != oldDelegate.moduleColor;
}

/// Minimal deterministic PRNG for grid generation.
class _SimpleRng {
  int _state;

  _SimpleRng(this._state);

  bool nextBool() {
    _state = (_state * 1103515245 + 12345) & 0x7FFFFFFF;
    return (_state >> 16) & 1 == 1;
  }
}

/// 📱 Invite Code Widget.
///
/// Wraps [InviteCodePainter] in a convenient widget.
class InviteCodeDisplay extends StatelessWidget {
  final String code;
  final double size;
  final Color color;

  const InviteCodeDisplay({
    super.key,
    required this.code,
    this.size = 120,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: InviteCodePainter(
          code: code,
          moduleColor: color,
          backgroundColor: Colors.white.withValues(alpha: 0.08),
        ),
      ),
    );
  }
}
