import 'package:flutter/material.dart';
import '../models/export_preset.dart';
import '../services/canvas_export_service.dart';

/// 📑 MULTI-PAGE PREVIEW OVERLAY
/// 
/// Mostra una griglia sopra l'area selezionata per visualizzare
/// come verrà diviso il canvas in pagine durante l'export multi-pagina.
/// 
/// FEATURES:
/// - ✅ Griglia con celle numerate
/// - ✅ Bordi tratteggiati tra le pagine
/// - ✅ Indicatore formato pagina
/// - ✅ Toggle visibilità
class MultiPagePreviewOverlay extends StatelessWidget {
  /// Area di export selezionata (in coordinate canvas)
  final Rect exportArea;
  
  /// Formato pagina per il calcolo della griglia
  final ExportPageFormat pageFormat;
  
  /// Qualità export (determina DPI per calcolo pagine)
  final ExportQuality quality;
  
  /// Scala del canvas (zoom level)
  final double canvasScale;
  
  /// Offset del canvas (pan position)
  final Offset canvasOffset;
  
  /// Se true, mostra la preview
  final bool isVisible;
  
  /// Callback per cambiare il formato pagina
  final ValueChanged<ExportPageFormat>? onPageFormatChanged;

  const MultiPagePreviewOverlay({
    super.key,
    required this.exportArea,
    required this.pageFormat,
    required this.quality,
    required this.canvasScale,
    required this.canvasOffset,
    this.isVisible = true,
    this.onPageFormatChanged,
  });

  /// Converti coordinate canvas → screen
  Offset _canvasToScreen(Offset canvasPoint) {
    return (canvasPoint - canvasOffset) * canvasScale;
  }

  @override
  Widget build(BuildContext context) {
    if (!isVisible) return const SizedBox.shrink();
    
    // Calcola griglia pagine
    final (columns, rows, total) = CanvasExportService.calculatePageGrid(
      exportArea: exportArea,
      quality: quality,
      pageFormat: pageFormat,
    );
    
    // Se è solo 1 pagina, non mostrare la griglia
    if (total <= 1) return const SizedBox.shrink();
    
    // Calcola posizione screen
    final screenTopLeft = _canvasToScreen(exportArea.topLeft);
    final screenBottomRight = _canvasToScreen(exportArea.bottomRight);
    final screenBounds = Rect.fromPoints(screenTopLeft, screenBottomRight);
    
    return Stack(
      children: [
        // Griglia delle pagine
        Positioned(
          left: screenBounds.left,
          top: screenBounds.top,
          width: screenBounds.width,
          height: screenBounds.height,
          child: IgnorePointer(
            child: CustomPaint(
              painter: _PageGridPainter(
                columns: columns,
                rows: rows,
              ),
            ),
          ),
        ),
        
        // Numeri delle pagine
        ..._buildPageNumbers(screenBounds, columns, rows),
        
        // Badge formato pagina (in alto a destra della selezione)
        Positioned(
          left: screenBounds.right + 8,
          top: screenBounds.top,
          child: _buildFormatBadge(context, columns, rows),
        ),
      ],
    );
  }

  List<Widget> _buildPageNumbers(Rect bounds, int columns, int rows) {
    final widgets = <Widget>[];
    final cellWidth = bounds.width / columns;
    final cellHeight = bounds.height / rows;
    
    int pageNumber = 1;
    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < columns; col++) {
        final cellCenter = Offset(
          bounds.left + cellWidth * (col + 0.5),
          bounds.top + cellHeight * (row + 0.5),
        );
        
        widgets.add(
          Positioned(
            left: cellCenter.dx - 16,
            top: cellCenter.dy - 16,
            child: IgnorePointer(
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha:  0.8),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha:  0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    '$pageNumber',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        
        pageNumber++;
      }
    }
    
    return widgets;
  }

  Widget _buildFormatBadge(BuildContext context, int columns, int rows) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final total = columns * rows;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark 
            ? Colors.grey[900]!.withValues(alpha:  0.95)
            : Colors.white.withValues(alpha:  0.95),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:  0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.grid_view_rounded,
                size: 14,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
              const SizedBox(width: 6),
              Text(
                '$columns × $rows',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$total pagine ${_getFormatName()}',
            style: TextStyle(
              color: isDark ? Colors.white54 : Colors.black45,
              fontSize: 11,
            ),
          ),
          
          // Menu formato pagina
          if (onPageFormatChanged != null) ...[
            const SizedBox(height: 8),
            _buildFormatSelector(isDark),
          ],
        ],
      ),
    );
  }

  String _getFormatName() {
    switch (pageFormat) {
      case ExportPageFormat.a4Portrait:
        return 'A4';
      case ExportPageFormat.a4Landscape:
        return 'A4 Landscape';
      case ExportPageFormat.a3Portrait:
        return 'A3';
      case ExportPageFormat.a3Landscape:
        return 'A3 Landscape';
      case ExportPageFormat.letterPortrait:
        return 'Letter';
      case ExportPageFormat.letterLandscape:
        return 'Letter Landscape';
      case ExportPageFormat.custom:
        return 'Custom';
    }
  }

  Widget _buildFormatSelector(bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildFormatOption(
          ExportPageFormat.a4Portrait,
          'A4',
          isDark,
        ),
        const SizedBox(width: 4),
        _buildFormatOption(
          ExportPageFormat.a3Portrait,
          'A3',
          isDark,
        ),
        const SizedBox(width: 4),
        _buildFormatOption(
          ExportPageFormat.letterPortrait,
          'Letter',
          isDark,
        ),
      ],
    );
  }

  Widget _buildFormatOption(ExportPageFormat format, String label, bool isDark) {
    final isSelected = format == pageFormat;
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onPageFormatChanged?.call(format),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected 
                ? Colors.blue 
                : (isDark ? Colors.grey[800] : Colors.grey[200]),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected 
                  ? Colors.white 
                  : (isDark ? Colors.white70 : Colors.black54),
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

/// Painter per la griglia delle pagine
class _PageGridPainter extends CustomPainter {
  final int columns;
  final int rows;

  _PageGridPainter({
    required this.columns,
    required this.rows,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Linea principale rossa più spessa
    final mainPaint = Paint()
      ..color = Colors.red.withValues(alpha:  0.9)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    
    // Ombra per contrasto
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha:  0.5)
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke;

    // Path tratteggiato
    final dashPath = Path();
    
    final cellWidth = size.width / columns;
    final cellHeight = size.height / rows;
    
    // Linee verticali
    for (int i = 1; i < columns; i++) {
      final x = i * cellWidth;
      // Ombra prima
      _drawDashedLine(
        canvas,
        Offset(x + 1, 1),
        Offset(x + 1, size.height + 1),
        shadowPaint,
      );
      // Linea principale
      _drawDashedLine(
        canvas,
        Offset(x, 0),
        Offset(x, size.height),
        mainPaint,
      );
    }
    
    // Linee orizzontali
    for (int i = 1; i < rows; i++) {
      final y = i * cellHeight;
      // Ombra prima
      _drawDashedLine(
        canvas,
        Offset(1, y + 1),
        Offset(size.width + 1, y + 1),
        shadowPaint,
      );
      // Linea principale
      _drawDashedLine(
        canvas,
        Offset(0, y),
        Offset(size.width, y),
        mainPaint,
      );
    }
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashWidth = 10.0;
    const dashSpace = 6.0;
    
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final length = (Offset(dx, dy)).distance;
    final dashCount = (length / (dashWidth + dashSpace)).floor();
    
    for (int i = 0; i < dashCount; i++) {
      final startFraction = i * (dashWidth + dashSpace) / length;
      final endFraction = (i * (dashWidth + dashSpace) + dashWidth) / length;
      
      if (endFraction > 1) break;
      
      canvas.drawLine(
        Offset(
          start.dx + dx * startFraction,
          start.dy + dy * startFraction,
        ),
        Offset(
          start.dx + dx * endFraction,
          start.dy + dy * endFraction,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_PageGridPainter oldDelegate) {
    return columns != oldDelegate.columns || rows != oldDelegate.rows;
  }
}
