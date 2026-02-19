import 'package:flutter/material.dart';
import '../../l10n/nebula_localizations.dart';
import '../../../testing/brush_testing.dart';

// ============================================================================
// TOOLBAR SETTINGS DROPDOWN — Settings menu, rename dialog, OCR, filters
// ============================================================================

/// Settings dropdown menu with brush settings, export, OCR, filters, etc.
class ToolbarSettingsDropdown extends StatefulWidget {
  final bool isDark;
  final VoidCallback onSettings;
  final void Function(Rect anchorRect)? onBrushSettingsPressed;
  final VoidCallback? onExportPressed;
  final String? noteTitle;
  final ValueChanged<String>? onNoteTitleChanged;

  final VoidCallback? onPaperTypePressed;

  const ToolbarSettingsDropdown({
    super.key,
    required this.isDark,
    required this.onSettings,
    this.onBrushSettingsPressed,
    this.onExportPressed,
    this.noteTitle,
    this.onNoteTitleChanged,

    this.onPaperTypePressed,
  });

  @override
  State<ToolbarSettingsDropdown> createState() =>
      _ToolbarSettingsDropdownState();
}

class _ToolbarSettingsDropdownState extends State<ToolbarSettingsDropdown> {
  final Set<String> _downloadedLanguages = {};

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = NebulaLocalizations.of(context);
    return PopupMenuButton<String>(
      icon: Icon(Icons.edit_note_rounded, color: cs.onSurface, size: 20),
      tooltip: l10n.proCanvas_writing,
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: cs.surfaceContainerLow,
      elevation: 8,
      itemBuilder:
          (BuildContext context) => [
            // Rename Note (only in canvas mode)
            if (widget.onNoteTitleChanged != null) ...[
              PopupMenuItem<String>(
                value: 'rename_note',
                height: 48,
                child: Row(
                  children: [
                    Icon(
                      Icons.drive_file_rename_outline,
                      size: 20,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      l10n.proCanvas_renameNote,
                      style: TextStyle(fontSize: 14, color: cs.onSurface),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
            ],

            // Paper Mode
            PopupMenuItem<String>(
              value: 'paper_mode',
              height: 48,
              child: Row(
                children: [
                  Icon(
                    Icons.grid_on_rounded,
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    l10n.proCanvas_paperMode,
                    style: TextStyle(fontSize: 14, color: cs.onSurface),
                  ),
                ],
              ),
            ),
            // Brush Settings
            if (widget.onBrushSettingsPressed != null)
              PopupMenuItem<String>(
                value: 'brush_settings',
                height: 48,
                child: Row(
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      size: 20,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      l10n.proCanvas_brushSettings,
                      style: TextStyle(fontSize: 14, color: cs.onSurface),
                    ),
                  ],
                ),
              ),
            // Export Canvas
            if (widget.onExportPressed != null)
              PopupMenuItem<String>(
                value: 'export_canvas',
                height: 48,
                child: Row(
                  children: [
                    Icon(
                      Icons.file_download_outlined,
                      size: 20,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      l10n.proCanvas_exportCanvas,
                      style: TextStyle(fontSize: 14, color: cs.onSurface),
                    ),
                  ],
                ),
              ),
            const PopupMenuDivider(),
            PopupMenuItem<String>(
              value: 'filters',
              height: 48,
              child: Row(
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    l10n.proCanvas_professionalFilters,
                    style: TextStyle(fontSize: 14, color: cs.onSurface),
                  ),
                ],
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem<String>(
              value: 'ocr',
              height: 48,
              child: Row(
                children: [
                  Icon(
                    Icons.text_fields_rounded,
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    l10n.proCanvas_ocrConvertWriting,
                    style: TextStyle(fontSize: 14, color: cs.onSurface),
                  ),
                ],
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem<String>(
              value: 'brush_testing',
              height: 48,
              child: Row(
                children: [
                  Icon(
                    Icons.brush_rounded,
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    l10n.proCanvas_brushTestingLab,
                    style: TextStyle(fontSize: 14, color: cs.onSurface),
                  ),
                ],
              ),
            ),
          ],
      onSelected: (String value) {
        switch (value) {
          case 'rename_note':
            _showRenameNoteDialog(context);
            break;
          case 'paper_mode':
            if (widget.onPaperTypePressed != null) {
              widget.onPaperTypePressed!();
            } else {
              widget.onSettings();
            }
            break;
          case 'brush_settings':
            final box = context.findRenderObject() as RenderBox;
            final pos = box.localToGlobal(Offset.zero);
            widget.onBrushSettingsPressed?.call(pos & box.size);
            break;
          case 'export_canvas':
            widget.onExportPressed?.call();
            break;
          case 'filters':
            _showFiltersDialog(context);
            break;
          case 'ocr':
            _showOCRLanguageDialog(context);
            break;
          case 'brush_testing':
            _openBrushTestingLab(context);
            break;
        }
      },
    );
  }

  void _showRenameNoteDialog(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = NebulaLocalizations.of(context);
    final TextEditingController controller = TextEditingController(
      text: widget.noteTitle ?? '',
    );

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: cs.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Icon(
                  Icons.drive_file_rename_outline,
                  color: cs.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  l10n.proCanvas_renameNote,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            content: TextField(
              controller: controller,
              autofocus: true,
              style: TextStyle(color: cs.onSurface, fontSize: 16),
              decoration: InputDecoration(
                labelText: l10n.proCanvas_noteName,
                labelStyle: TextStyle(color: cs.onSurfaceVariant),
                hintText: l10n.proCanvas_enterName,
                hintStyle: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.3),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: cs.primary, width: 2),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  l10n.cancel,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
              FilledButton(
                onPressed: () {
                  final newTitle = controller.text.trim();
                  if (newTitle.isNotEmpty &&
                      widget.onNoteTitleChanged != null) {
                    widget.onNoteTitleChanged!(newTitle);
                  }
                  Navigator.pop(context);
                },
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                child: Text(l10n.save),
              ),
            ],
          ),
    );
  }

  void _showFiltersDialog(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = NebulaLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.toolbarAIFilters),
        backgroundColor: cs.primary,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _openBrushTestingLab(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const BrushTestScreen()),
    );
  }

  void _showOCRLanguageDialog(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = NebulaLocalizations.of(context);

    showDialog(
      context: context,
      builder:
          (context) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            backgroundColor: cs.surfaceContainerLow,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.text_fields_rounded,
                            color: cs.onPrimaryContainer,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.proCanvas_ocrTextRecognition,
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: cs.onSurface,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                l10n.proCanvas_selectLanguagesForRecognition,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.close_rounded,
                            color: cs.onSurfaceVariant,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),

                  // Language list
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _buildLanguageItem(
                          context,
                          language: 'Italiano',
                          code: 'it',
                          flag: '🇮🇹',
                          isDownloaded: _downloadedLanguages.contains('it'),
                        ),
                        _buildLanguageItem(
                          context,
                          language: 'English',
                          code: 'en',
                          flag: '🇬🇧',
                          isDownloaded: _downloadedLanguages.contains('en'),
                        ),
                        _buildLanguageItem(
                          context,
                          language: 'Español',
                          code: 'es',
                          flag: '🇪🇸',
                          isDownloaded: _downloadedLanguages.contains('es'),
                        ),
                        _buildLanguageItem(
                          context,
                          language: 'Français',
                          code: 'fr',
                          flag: '🇫🇷',
                          isDownloaded: _downloadedLanguages.contains('fr'),
                        ),
                        _buildLanguageItem(
                          context,
                          language: 'Deutsch',
                          code: 'de',
                          flag: '🇩🇪',
                          isDownloaded: _downloadedLanguages.contains('de'),
                        ),
                        _buildLanguageItem(
                          context,
                          language: '中文',
                          code: 'zh',
                          flag: '🇨🇳',
                          isDownloaded: _downloadedLanguages.contains('zh'),
                        ),
                        _buildLanguageItem(
                          context,
                          language: '日本語',
                          code: 'ja',
                          flag: '🇯🇵',
                          isDownloaded: _downloadedLanguages.contains('ja'),
                        ),
                      ],
                    ),
                  ),

                  // Footer
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(20),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 16,
                          color: cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.proCanvas_languageModelsWillBeDownloaded,
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildLanguageItem(
    BuildContext context, {
    required String language,
    required String code,
    required String flag,
    required bool isDownloaded,
  }) {
    final cs = Theme.of(context).colorScheme;
    final l10n = NebulaLocalizations.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Text(flag, style: const TextStyle(fontSize: 32)),
        title: Text(
          language,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: cs.onSurface,
          ),
        ),
        subtitle: Text(
          code.toUpperCase(),
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        trailing:
            isDownloaded
                ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        l10n.proCanvas_downloaded,
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                )
                : FilledButton.icon(
                  onPressed: () {
                    _downloadLanguageModel(context, code, language);
                  },
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: Text(l10n.proCanvas_downloadLabel),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
      ),
    );
  }

  void _downloadLanguageModel(
    BuildContext context,
    String code,
    String language,
  ) {
    final l10n = NebulaLocalizations.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            title: Text('📥 Download $language'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(l10n.proCanvas_downloadingModel(code)),
              ],
            ),
          ),
    );

    Future.delayed(const Duration(seconds: 2), () {
      Navigator.pop(context);

      setState(() {
        _downloadedLanguages.add(code);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.proCanvas_modelDownloadedSuccess(language)),
          backgroundColor: Colors.green,
        ),
      );
    });
  }
}
