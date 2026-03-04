part of '../fluera_canvas_screen.dart';

// ═══════════════════════════════════════
// 📝 PDF Features — Create Sheet & Pattern Widgets
// ═══════════════════════════════════════

}

// =============================================================================
// 📝 PDF Create Sheet — Stateful bottom sheet with MD3 design
// =============================================================================

class _PdfCreateSheet extends StatefulWidget {
  final void Function(PdfPageBackground bg, String title) onDone;

  const _PdfCreateSheet({required this.onDone});

  @override
  State<_PdfCreateSheet> createState() => _PdfCreateSheetState();
}

class _PdfCreateSheetState extends State<_PdfCreateSheet> {
  PdfPageBackground _selected = PdfPageBackground.blank;
  final _titleController = TextEditingController(text: 'Untitled Document');

  @override
  void initState() {
    super.initState();
    // Auto-select title text for quick replacement
    _titleController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _titleController.text.length,
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Handle bar ──
                Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Title ──
                Text(
                  'New Document',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 20),

                // ── Document title field ──
                TextField(
                  controller: _titleController,
                  autofocus: true,
                  style: TextStyle(
                    fontSize: 16,
                    color: cs.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Document title',
                    labelStyle: TextStyle(color: cs.onSurfaceVariant),
                    prefixIcon: Icon(
                      Icons.edit_document,
                      color: cs.primary,
                      size: 20,
                    ),
                    filled: true,
                    fillColor: cs.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: cs.primary, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _create(),
                ),
                const SizedBox(height: 24),

                // ── Section label ──
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Page style',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // ── Pattern grid with previews ──
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.72,
                  children:
                      PdfPageBackground.values.map((bg) {
                        final isSelected = _selected == bg;
                        return _PatternCard(
                          background: bg,
                          isSelected: isSelected,
                          colorScheme: cs,
                          onTap: () => setState(() => _selected = bg),
                        );
                      }).toList(),
                ),
                const SizedBox(height: 24),

                // ── Create button ──
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: _create,
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: const Text(
                      'Create',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _create() {
    widget.onDone(_selected, _titleController.text);
  }
}

// =============================================================================
// 📝 Pattern preview card
// =============================================================================

class _PatternCard extends StatelessWidget {
  final PdfPageBackground background;
  final bool isSelected;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const _PatternCard({
    required this.background,
    required this.isSelected,
    required this.colorScheme,
    required this.onTap,
  });

  String get _label {
    switch (background) {
      case PdfPageBackground.blank:
        return 'Blank';
      case PdfPageBackground.ruled:
        return 'Ruled';
      case PdfPageBackground.grid:
        return 'Grid';
      case PdfPageBackground.dotted:
        return 'Dotted';
      case PdfPageBackground.music:
        return 'Music';
      case PdfPageBackground.cornell:
        return 'Cornell';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? cs.primary : cs.outlineVariant,
            width: isSelected ? 2.5 : 1.0,
          ),
          color:
              isSelected
                  ? cs.primaryContainer.withValues(alpha: 0.3)
                  : cs.surfaceContainerLow,
        ),
        child: Column(
          children: [
            // ── Mini page preview ──
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.4),
                      width: 0.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: CustomPaint(
                    painter: _PatternPreviewPainter(background),
                    size: Size.infinite,
                  ),
                ),
              ),
            ),
            // ── Label ──
            Padding(
              padding: const EdgeInsets.only(bottom: 8, top: 2),
              child: Text(
                _label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// 📝 Pattern preview painter — mini version of page background
// =============================================================================

class _PatternPreviewPainter extends CustomPainter {
  final PdfPageBackground background;

  _PatternPreviewPainter(this.background);

  static final Paint _linePaint =
      Paint()
        ..color = const Color(0xFFB3D5F5)
        ..strokeWidth = 0.5
        ..style = PaintingStyle.stroke;

  static final Paint _dotPaint =
      Paint()
        ..color = const Color(0xFFB0BEC5)
        ..style = PaintingStyle.fill;

  static final Paint _heavyPaint =
      Paint()
        ..color = const Color(0xFF90A4AE)
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke;

  static final Paint _marginPaint =
      Paint()
        ..color = const Color(0x40E57373)
        ..strokeWidth = 0.6
        ..style = PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Size size) {
    switch (background) {
      case PdfPageBackground.blank:
        return;

      case PdfPageBackground.ruled:
        final mx = size.width * 0.18;
        canvas.drawLine(Offset(mx, 0), Offset(mx, size.height), _marginPaint);
        const spacing = 8.0;
        for (double y = spacing * 2; y < size.height - 4; y += spacing) {
          canvas.drawLine(Offset(4, y), Offset(size.width - 4, y), _linePaint);
        }

      case PdfPageBackground.grid:
        const spacing = 7.0;
        for (double x = 3; x <= size.width - 3; x += spacing) {
          canvas.drawLine(Offset(x, 3), Offset(x, size.height - 3), _linePaint);
        }
        for (double y = 3; y <= size.height - 3; y += spacing) {
          canvas.drawLine(Offset(3, y), Offset(size.width - 3, y), _linePaint);
        }

      case PdfPageBackground.dotted:
        const spacing = 7.0;
        for (double x = 4; x <= size.width - 4; x += spacing) {
          for (double y = 4; y <= size.height - 4; y += spacing) {
            canvas.drawCircle(Offset(x, y), 0.7, _dotPaint);
          }
        }

      case PdfPageBackground.music:
        const staffSpacing = 3.0;
        const groupGap = 14.0;
        double y = 10.0;
        while (y + staffSpacing * 4 < size.height - 8) {
          for (int i = 0; i < 5; i++) {
            canvas.drawLine(
              Offset(4, y + i * staffSpacing),
              Offset(size.width - 4, y + i * staffSpacing),
              _heavyPaint,
            );
          }
          y += staffSpacing * 4 + groupGap;
        }

      case PdfPageBackground.cornell:
        final cueX = size.width * 0.30;
        final summaryY = size.height * 0.80;
        final topLine = size.height * 0.12;
        canvas.drawLine(
          Offset(3, topLine),
          Offset(size.width - 3, topLine),
          _heavyPaint,
        );
        canvas.drawLine(
          Offset(cueX, topLine),
          Offset(cueX, summaryY),
          _heavyPaint,
        );
        canvas.drawLine(
          Offset(3, summaryY),
          Offset(size.width - 3, summaryY),
          _heavyPaint,
        );
        for (double y = topLine + 8; y < summaryY - 3; y += 8) {
          canvas.drawLine(
            Offset(cueX + 3, y),
            Offset(size.width - 4, y),
            _linePaint,
          );
        }
    }
  }

  @override
  bool shouldRepaint(_PatternPreviewPainter old) =>
      old.background != background;
}
