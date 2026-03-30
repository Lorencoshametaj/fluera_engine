part of 'pdf_reader_screen.dart';

/// Brush settings panel UI for PDF annotation mode.
extension _PdfBrushPanelMethods on _PdfReaderScreenState {

  Widget _buildBrushFab() {
    return GestureDetector(
      onTap: () { setState(() => _showBrushPanel = !_showBrushPanel); HapticFeedback.selectionClick(); },
      child: ClipOval(child: BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: AnimatedContainer(duration: const Duration(milliseconds: 200), width: 44, height: 44,
          decoration: BoxDecoration(
            color: _showBrushPanel ? const Color(0xFF6C63FF).withValues(alpha: 0.85) : Colors.black.withValues(alpha: 0.45),
            shape: BoxShape.circle,
            border: Border.all(color: _showBrushPanel ? Colors.white.withValues(alpha: 0.30) : Colors.white.withValues(alpha: 0.15)),
            boxShadow: _showBrushPanel ? [BoxShadow(color: const Color(0xFF6C63FF).withValues(alpha: 0.4), blurRadius: 12, spreadRadius: 1)] : null,
          ),
          child: Icon(Icons.brush_rounded, color: _showBrushPanel ? Colors.white : Colors.white70, size: 20),
        ),
      )),
    );
  }

  Widget _buildBrushPanel() {
    return ClipRect(child: BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.60), border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.10)))),
        child: SafeArea(top: false, child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
          _premiumToolPill(icon: Icons.edit_rounded, isActive: !_isErasing && _selectedShapeType == ShapeType.freehand,
            onTap: () => setState(() { _isErasing = false; _selectedShapeType = ShapeType.freehand; })),
          const SizedBox(width: 2),
          _premiumToolPill(icon: Icons.cleaning_services_rounded, isActive: _isErasing, onTap: () => setState(() => _isErasing = true)),
          _separator(),
          _premiumPenChip(ProPenType.fountain, '✒️'), _premiumPenChip(ProPenType.ballpoint, '🖋️'),
          _premiumPenChip(ProPenType.pencil, '✏️'), _premiumPenChip(ProPenType.highlighter, '🖍️'),
          _premiumPenChip(ProPenType.watercolor, '💧'), _premiumPenChip(ProPenType.marker, '🖊️'),
          _separator(),
          _buildShapeButton(ShapeType.line, Icons.show_chart), _buildShapeButton(ShapeType.rectangle, Icons.crop_square),
          _buildShapeButton(ShapeType.circle, Icons.circle_outlined), _buildShapeButton(ShapeType.arrow, Icons.arrow_forward),
          _separator(),
          ...List.generate(_penType == ProPenType.highlighter ? _PdfReaderScreenState._highlightColors.length : _PdfReaderScreenState._colorPresets.length, (i) {
            final c = _penType == ProPenType.highlighter ? _PdfReaderScreenState._highlightColors[i] : _PdfReaderScreenState._colorPresets[i];
            final isActive = _penColor.toARGB32() == c.toARGB32();
            return GestureDetector(onTap: () => setState(() => _penColor = c), child: AnimatedContainer(
              duration: const Duration(milliseconds: 200), curve: Curves.easeOutCubic,
              width: isActive ? 26 : 20, height: isActive ? 26 : 20, margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(color: c, shape: BoxShape.circle,
                border: Border.all(color: isActive ? Colors.white : const Color(0x30FFFFFF), width: isActive ? 2.5 : 1),
                boxShadow: isActive ? [BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 8, spreadRadius: 1)] : null)));
          }),
          const SizedBox(width: 8),
          AnimatedContainer(duration: const Duration(milliseconds: 200),
            width: (_penWidth * 2.5).clamp(6.0, 20.0), height: (_penWidth * 2.5).clamp(6.0, 20.0),
            decoration: BoxDecoration(color: _penColor.withValues(alpha: _penOpacity), shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: _penColor.withValues(alpha: 0.4 * _penOpacity), blurRadius: 6)])),
          SizedBox(width: 80, child: SliderTheme(
            data: SliderThemeData(trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12), activeTrackColor: const Color(0xFF6C63FF),
              inactiveTrackColor: const Color(0x20FFFFFF), thumbColor: Colors.white, overlayColor: const Color(0x206C63FF)),
            child: Slider(value: _penWidth, min: 0.5, max: 8.0, onChanged: (v) => setState(() => _penWidth = v)))),
          _separator(),
          const Icon(Icons.opacity_rounded, size: 14, color: Colors.white54),
          SizedBox(width: 72, child: SliderTheme(
            data: SliderThemeData(trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10), activeTrackColor: const Color(0xFF9B59B6),
              inactiveTrackColor: const Color(0x20FFFFFF), thumbColor: Colors.white, overlayColor: const Color(0x209B59B6)),
            child: Slider(value: _penOpacity, min: 0.1, max: 1.0, divisions: 9, onChanged: (v) => setState(() => _penOpacity = v)))),
          Text('${(_penOpacity * 100).toInt()}%', style: const TextStyle(fontSize: 10, color: Colors.white54, fontWeight: FontWeight.w600)),
        ]))),
      ),
    ));
  }

  Widget _premiumToolPill({required IconData icon, required bool isActive, required VoidCallback onTap}) {
    return GestureDetector(onTap: onTap, child: AnimatedContainer(
      duration: const Duration(milliseconds: 200), curve: Curves.easeOutCubic, padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        gradient: isActive ? const LinearGradient(colors: [Color(0xFF6C63FF), Color(0xFF8B5CF6)], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
        color: isActive ? null : Colors.transparent, borderRadius: BorderRadius.circular(12),
        boxShadow: isActive ? [BoxShadow(color: const Color(0xFF6C63FF).withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 2))] : null),
      child: Icon(icon, size: 18, color: isActive ? Colors.white : const Color(0x80FFFFFF))));
  }

  Widget _premiumPenChip(ProPenType type, String emoji) {
    final isActive = _penType == type && !_isErasing;
    return Builder(builder: (chipContext) => GestureDetector(
      onTap: () => setState(() {
        final wasHighlighter = _penType == ProPenType.highlighter;
        _penType = type; _isErasing = false; _selectedShapeType = ShapeType.freehand;
        if (type == ProPenType.highlighter && !wasHighlighter) {
          _savedPenColor = _penColor; _savedPenWidth = _penWidth; _penColor = _PdfReaderScreenState._highlightColors[0]; _penWidth = 6.0;
        } else if (type != ProPenType.highlighter && wasHighlighter && _savedPenColor != null) {
          _penColor = _savedPenColor!; _penWidth = _savedPenWidth ?? 2.0; _savedPenColor = null; _savedPenWidth = null;
        }
      }),
      onLongPress: () {
        HapticFeedback.mediumImpact();
        final box = chipContext.findRenderObject() as RenderBox;
        final pos = box.localToGlobal(Offset.zero);
        ProBrushSettingsDialog.show(chipContext, settings: _brushSettings, currentBrush: type, anchorRect: pos & box.size,
          currentColor: _penColor, currentWidth: _penWidth,
          onSettingsChanged: (newSettings) { setState(() => _brushSettings = newSettings); });
      },
      child: AnimatedContainer(duration: const Duration(milliseconds: 200), curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(color: isActive ? const Color(0x25FFFFFF) : Colors.transparent, borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isActive ? const Color(0x40FFFFFF) : Colors.transparent, width: 0.5)),
        child: Text(emoji, style: TextStyle(fontSize: isActive ? 18 : 15)))));
  }

  Widget _buildShapeButton(ShapeType type, IconData icon) {
    final isActive = _selectedShapeType == type;
    return GestureDetector(
      onTap: () => setState(() { _selectedShapeType = isActive ? ShapeType.freehand : type; _isErasing = false; }),
      child: AnimatedContainer(duration: const Duration(milliseconds: 200), curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(6), margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          gradient: isActive ? const LinearGradient(colors: [Color(0xFF6C63FF), Color(0xFF8B5CF6)], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
          color: isActive ? null : Colors.transparent, borderRadius: BorderRadius.circular(10),
          boxShadow: isActive ? [BoxShadow(color: const Color(0xFF6C63FF).withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))] : null),
        child: Icon(icon, size: 16, color: isActive ? Colors.white : const Color(0x80FFFFFF))));
  }

  Widget _separator() {
    return Container(height: 24, width: 1, margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Colors.transparent, const Color(0x30FFFFFF), Colors.transparent])));
  }
}
