import 'package:flutter/material.dart';
import '../services/digital_ink_service.dart';

/// ✍️ Handwriting Recognition Confirmation Dialog
///
/// Shows recognized text in an editable TextField with language selector.
/// Returns the confirmed text or null if canceled.
class HandwritingConfirmationDialog extends StatefulWidget {
  final String recognizedText;
  final String languageCode;

  const HandwritingConfirmationDialog({
    super.key,
    required this.recognizedText,
    required this.languageCode,
  });

  /// Show the dialog and return confirmed text + deleteStrokes flag (null = canceled).
  static Future<({String text, bool deleteStrokes})?> show(
    BuildContext context, {
    required String recognizedText,
    required String languageCode,
  }) {
    return showDialog<({String text, bool deleteStrokes})?>(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => HandwritingConfirmationDialog(
            recognizedText: recognizedText,
            languageCode: languageCode,
          ),
    );
  }

  @override
  State<HandwritingConfirmationDialog> createState() =>
      _HandwritingConfirmationDialogState();
}

class _HandwritingConfirmationDialogState
    extends State<HandwritingConfirmationDialog> {
  late TextEditingController _textController;
  late String _selectedLanguage;
  bool _deleteStrokes = true;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.recognizedText);
    _selectedLanguage = widget.languageCode;
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final langInfo = DigitalInkService.supportedLanguages[_selectedLanguage];
    final flagEmoji = langInfo?.$3 ?? '🌐';
    final langName = langInfo?.$1 ?? _selectedLanguage;

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
                    color: Colors.deepPurple.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.draw_rounded,
                    color: Colors.deepPurple,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Handwriting Recognized',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Edit the text if needed',
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

            // ── Language Badge ──
            GestureDetector(
              onTap: _showLanguagePicker,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.deepPurple.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(flagEmoji, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 6),
                    Text(
                      langName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.expand_more_rounded,
                      size: 16,
                      color: isDark ? Colors.white38 : Colors.black26,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ── Editable Text Field ──
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.black12,
                ),
              ),
              child: TextField(
                controller: _textController,
                maxLines: 5,
                minLines: 2,
                autofocus: true,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.all(14),
                  border: InputBorder.none,
                  hintText: 'Recognized text...',
                  hintStyle: TextStyle(
                    color: isDark ? Colors.white24 : Colors.black26,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

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
                          ? Colors.deepPurple.withValues(alpha: 0.1)
                          : (isDark
                              ? Colors.white.withValues(alpha: 0.04)
                              : Colors.grey.withValues(alpha: 0.06)),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color:
                        _deleteStrokes
                            ? Colors.deepPurple.withValues(alpha: 0.3)
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
                              ? Colors.deepPurple
                              : (isDark ? Colors.white38 : Colors.black38),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _deleteStrokes
                            ? 'Replace strokes with text'
                            : 'Keep strokes, add text',
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
                      activeThumbColor: Colors.deepPurple,
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
                    final text = _textController.text.trim();
                    if (text.isNotEmpty) {
                      Navigator.pop(context, (
                        text: text,
                        deleteStrokes: _deleteStrokes,
                      ));
                    }
                  },
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Convert'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
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

  void _showLanguagePicker() async {
    // Show a simple language picker as bottom sheet
    final languages = DigitalInkService.supportedLanguages;
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.7,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Text(
                      'Select Language',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: languages.length,
                      itemBuilder: (context, index) {
                        final code = languages.keys.elementAt(index);
                        final (name, nativeName, flag) = languages[code]!;
                        final isActive = code == _selectedLanguage;
                        return ListTile(
                          leading: Text(
                            flag,
                            style: const TextStyle(fontSize: 24),
                          ),
                          title: Text(
                            name,
                            style: TextStyle(
                              fontWeight:
                                  isActive ? FontWeight.w700 : FontWeight.w400,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          subtitle:
                              nativeName != name
                                  ? Text(
                                    nativeName,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color:
                                          isDark
                                              ? Colors.white38
                                              : Colors.black38,
                                    ),
                                  )
                                  : null,
                          trailing:
                              isActive
                                  ? const Icon(
                                    Icons.check_circle_rounded,
                                    color: Colors.deepPurple,
                                    size: 20,
                                  )
                                  : null,
                          onTap: () => Navigator.pop(context, code),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (result != null && result != _selectedLanguage && mounted) {
      setState(() => _selectedLanguage = result);
      // Re-recognize with new language
      await _reRecognize(result);
    }
  }

  Future<void> _reRecognize(String languageCode) async {
    // The caller should set up the service; we just show a loading state
    final service = DigitalInkService.instance;
    final ok = await service.switchLanguage(languageCode);
    if (!ok || !mounted) return;

    // We can't re-recognize here since we don't have the raw points.
    // The user will just need to edit manually if the language is wrong.
  }
}
