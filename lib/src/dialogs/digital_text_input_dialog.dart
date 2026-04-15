import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/fluera_localizations.dart';

/// 📝 DIALOG INPUT TESTO DIGITALE
/// Dialog professionale per inserire testo con tastiera
/// Features:
/// - Input multi-line
/// - Live text preview
/// - Color selection
/// - Selezione size font
/// - Validation (not empty)
/// - Checklist correzioni OCR
class DigitalTextInputDialog extends StatefulWidget {
  final Color initialColor;
  final String? initialText;
  final double? initialFontSize;
  final bool isOCR; // True if the text comes from OCR

  const DigitalTextInputDialog({
    super.key,
    this.initialColor = Colors.black,
    this.initialText,
    this.initialFontSize,
    this.isOCR = false,
  });

  /// Shows il dialog e ritorna the result
  static Future<DigitalTextResult?> show(
    BuildContext context, {
    Color initialColor = Colors.black,
    String? initialText,
    double? initialFontSize,
    bool isOCR = false,
  }) {
    return showDialog<DigitalTextResult>(
      context: context,
      builder:
          (context) => DigitalTextInputDialog(
            initialColor: initialColor,
            initialText: initialText,
            initialFontSize: initialFontSize,
            isOCR: isOCR,
          ),
    );
  }

  @override
  State<DigitalTextInputDialog> createState() => _DigitalTextInputDialogState();
}

class _DigitalTextInputDialogState extends State<DigitalTextInputDialog> {
  late final TextEditingController _textController;
  late Color _selectedColor;
  bool _keepHandwritingStrokes = false; // 🖊️ Keep original strokes?

  // Size font fissa
  static const double _fontSize = 24.0;

  // Predefined colors (same as toolbar)
  static const List<Color> _availableColors = [
    Colors.black,
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.pink,
    Colors.brown,
  ];

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialText ?? '');
    _selectedColor = widget.initialColor;
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  /// Apply automatic corrections to OCR text
  void _applyOCRCorrections() {
    String text = _textController.text;

    // 1. Trim spazi iniziali/finali
    text = text.trim();

    // 2. First letter uppercase
    if (text.isNotEmpty) {
      text = text[0].toUpperCase() + text.substring(1).toLowerCase();
    }

    // 3. Aggiungi punto finale se manca
    if (text.isNotEmpty &&
        !text.endsWith('.') &&
        !text.endsWith('!') &&
        !text.endsWith('?')) {
      text += '.';
    }

    // 4. Uppercase after period
    text = text.replaceAllMapped(
      RegExp(r'([.!?])\s*([a-z])'),
      (match) => '${match.group(1)} ${match.group(2)!.toUpperCase()}',
    );

    // 5. Remove multiple spaces
    text = text.replaceAll(RegExp(r'\s+'), ' ');

    // 6. Space after punctuation
    text = text.replaceAllMapped(
      RegExp(r'([.!?,;:])([^\s])'),
      (match) => '${match.group(1)} ${match.group(2)}',
    );

    setState(() {
      _textController.text = text;
      _textController.selection = TextSelection.fromPosition(
        TextPosition(offset: text.length),
      );
    });

    HapticFeedback.lightImpact();
  }

  /// Checks if the text has the first letter capitalized
  bool _hasCapitalStart() {
    final text = _textController.text.trim();
    return text.isNotEmpty && text[0] == text[0].toUpperCase();
  }

  /// Checks if the text ends with punctuation
  bool _hasEndPunctuation() {
    final text = _textController.text.trim();
    return text.endsWith('.') || text.endsWith('!') || text.endsWith('?');
  }

  /// Checks if the testo ha spaziatura corretta
  bool _hasCorrectSpacing() {
    final text = _textController.text;
    return !text.contains(RegExp(r'\s{2,}')) && // No multiple spaces
        !text.contains(
          RegExp(r'([.!?,;:])([^\s])'),
        ); // Space after punctuation
  }

  /// Widget checklist item
  Widget _buildChecklistItem(String label, bool isChecked, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            isChecked ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 14,
            color:
                isChecked
                    ? Colors.green
                    : (isDark ? Colors.white54 : Colors.black38),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color:
                    isChecked
                        ? (isDark ? Colors.white : Colors.black87)
                        : (isDark ? Colors.white54 : Colors.black54),
                fontWeight: isChecked ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirm() {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      // Show feedback that the testo is empty
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(FlueraLocalizations.of(context)!.proCanvas_textEmpty),
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }

    HapticFeedback.lightImpact();
    Navigator.of(context).pop(
      DigitalTextResult(
        text: text,
        color: _selectedColor,
        fontSize: _fontSize,
        keepStrokes:
            widget.isOCR ? _keepHandwritingStrokes : false, // 🖊️ Only if OCR
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.text_fields_rounded,
                  color: Colors.deepPurple,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Text(
                  FlueraLocalizations.of(context)!.proCanvas_insertText,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: FlueraLocalizations.of(context)!.close,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Contenuto scrollabile
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Input testo
                    Container(
                      decoration: BoxDecoration(
                        color: (isDark ? Colors.white : Colors.black)
                            .withValues(alpha:  0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: (isDark ? Colors.white : Colors.black)
                              .withValues(alpha:  0.1),
                        ),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: TextField(
                        controller: _textController,
                        autofocus: true,
                        maxLines: 4,
                        maxLength: 500,
                        style: TextStyle(
                          fontSize: 15,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        decoration: InputDecoration(
                          hintText: FlueraLocalizations.of(context)!.proCanvas_typeHere,
                          hintStyle: TextStyle(
                            color: (isDark ? Colors.white : Colors.black)
                                .withValues(alpha:  0.4),
                          ),
                          border: InputBorder.none,
                          counterStyle: TextStyle(
                            fontSize: 11,
                            color: (isDark ? Colors.white : Colors.black)
                                .withValues(alpha:  0.5),
                          ),
                        ),
                        onChanged: (_) => setState(() {}), // Update anteprima
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 🔍 CHECKLIST OCR (only if isOCR = true)
                    if (widget.isOCR) ...[
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.purple.withValues(alpha:  0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.purple.withValues(alpha:  0.3),
                            width: 1.5,
                          ),
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.checklist_rounded,
                                  size: 16,
                                  color: Colors.purple,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  FlueraLocalizations.of(context)!.proCanvas_ocrTextCheck,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.purple,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const Spacer(),
                                // "Fix All" button
                                TextButton.icon(
                                  onPressed: _applyOCRCorrections,
                                  icon: Icon(Icons.auto_fix_high, size: 14),
                                  label: Text(
                                    FlueraLocalizations.of(context)!.proCanvas_correct,
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.purple,
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // Checklist items
                            _buildChecklistItem(
                              FlueraLocalizations.of(context)!.proCanvas_capitalStart,
                              _hasCapitalStart(),
                              isDark,
                            ),
                            _buildChecklistItem(
                              FlueraLocalizations.of(context)!.proCanvas_endPunctuation,
                              _hasEndPunctuation(),
                              isDark,
                            ),
                            _buildChecklistItem(
                              FlueraLocalizations.of(context)!.proCanvas_correctSpacing,
                              _hasCorrectSpacing(),
                              isDark,
                            ),
                            const SizedBox(height: 12),
                            // Divisore
                            Divider(
                              color: Colors.purple.withValues(alpha:  0.2),
                              height: 1,
                            ),
                            const SizedBox(height: 12),
                            // 🖊️ Keep strokes checkbox
                            InkWell(
                              onTap: () {
                                setState(() {
                                  _keepHandwritingStrokes =
                                      !_keepHandwritingStrokes;
                                });
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                  horizontal: 4,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _keepHandwritingStrokes
                                          ? Icons.check_box
                                          : Icons.check_box_outline_blank,
                                      size: 18,
                                      color:
                                          _keepHandwritingStrokes
                                              ? Colors.purple
                                              : (isDark
                                                  ? Colors.white54
                                                  : Colors.black38),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        FlueraLocalizations.of(context)!.proCanvas_keepHandwriting,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color:
                                              isDark
                                                  ? Colors.white
                                                  : Colors.black87,
                                          fontWeight:
                                              _keepHandwritingStrokes
                                                  ? FontWeight.w600
                                                  : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Anteprima
                    if (_textController.text.isNotEmpty) ...[
                      Text(
                        FlueraLocalizations.of(context)!.proCanvas_previewLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: (isDark ? Colors.white : Colors.black)
                              .withValues(alpha:  0.6),
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha:  0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _textController.text,
                          style: TextStyle(
                            fontSize: _fontSize,
                            color: _selectedColor,
                            fontWeight: FontWeight.normal,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Color selection
                    Text(
                      FlueraLocalizations.of(context)!.proCanvas_colorLabel,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: (isDark ? Colors.white : Colors.black)
                            .withValues(alpha:  0.6),
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children:
                          _availableColors.map((color) {
                            final isSelected = color == _selectedColor;
                            return GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _selectedColor = color);
                              },
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color:
                                        isSelected
                                            ? Colors.white
                                            : Colors.transparent,
                                    width: 2.5,
                                  ),
                                  boxShadow: [
                                    if (isSelected)
                                      BoxShadow(
                                        color: color.withValues(alpha:  0.5),
                                        blurRadius: 6,
                                        spreadRadius: 1,
                                      ),
                                  ],
                                ),
                                child:
                                    isSelected
                                        ? const Icon(
                                          Icons.check,
                                          color: Colors.white,
                                          size: 18,
                                        )
                                        : null,
                              ),
                            );
                          }).toList(),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Pulsanti azione
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Cancel
                TextButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.of(context).pop();
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                  ),
                  child: Text(
                    FlueraLocalizations.of(context)!.cancel,
                    style: TextStyle(
                      fontSize: 14,
                      color: (isDark ? Colors.white : Colors.black).withValues(alpha:  
                        0.6,
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                // Confirm
                ElevatedButton(
                  onPressed: _confirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 10,
                    ),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    FlueraLocalizations.of(context)!.confirm,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Risultato del dialog
class DigitalTextResult {
  final String text;
  final Color color;
  final double fontSize;
  final bool keepStrokes; // 🖊️ Keep original strokes

  const DigitalTextResult({
    required this.text,
    required this.color,
    required this.fontSize,
    this.keepStrokes = false,
  });
}
