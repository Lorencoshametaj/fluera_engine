import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/digital_ink_service.dart';

/// ✍️ Language picker bottom sheet for Digital Ink Recognition.
///
/// Shows all supported languages with download status.
/// Users can download/delete language models and select the active language.
class HandwritingLanguagePicker extends StatefulWidget {
  final String activeLanguage;
  final ValueChanged<String> onLanguageSelected;

  const HandwritingLanguagePicker({
    super.key,
    required this.activeLanguage,
    required this.onLanguageSelected,
  });

  /// Show the picker as a modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required String activeLanguage,
    required ValueChanged<String> onLanguageSelected,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (_) => HandwritingLanguagePicker(
            activeLanguage: activeLanguage,
            onLanguageSelected: onLanguageSelected,
          ),
    );
  }

  @override
  State<HandwritingLanguagePicker> createState() =>
      _HandwritingLanguagePickerState();
}

class _HandwritingLanguagePickerState extends State<HandwritingLanguagePicker> {
  final _service = DigitalInkService.instance;
  Map<String, bool> _downloadStatus = {};
  final Set<String> _downloading = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final codes = DigitalInkService.supportedLanguages.keys.toList();
    final status = await _service.getDownloadStatus(codes);
    if (mounted) {
      setState(() {
        _downloadStatus = status;
        _loading = false;
      });
    }
  }

  Future<void> _download(String code) async {
    setState(() => _downloading.add(code));
    final ok = await _service.downloadLanguage(code);
    if (mounted) {
      setState(() {
        _downloading.remove(code);
        if (ok) _downloadStatus[code] = true;
      });
      if (ok) HapticFeedback.mediumImpact();
    }
  }

  Future<void> _delete(String code) async {
    if (code == widget.activeLanguage) return; // Can't delete active
    await _service.deleteModel(code);
    if (mounted) {
      setState(() => _downloadStatus[code] = false);
      HapticFeedback.lightImpact();
    }
  }

  void _select(String code) {
    HapticFeedback.selectionClick();
    widget.onLanguageSelected(code);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final languages = DigitalInkService.supportedLanguages;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              // ── Handle ──
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // ── Header ──
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.draw_rounded,
                      color: Colors.deepPurple,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Handwriting Languages',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Download models for offline recognition (~15 MB each)',
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
              ),

              Divider(
                height: 1,
                color: isDark ? Colors.white10 : Colors.black12,
              ),

              // ── Language List ──
              Expanded(
                child:
                    _loading
                        ? const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: languages.length,
                          itemBuilder: (context, index) {
                            final code = languages.keys.elementAt(index);
                            final (name, nativeName, flag) = languages[code]!;
                            final isDownloaded = _downloadStatus[code] ?? false;
                            final isDownloading = _downloading.contains(code);
                            final isActive = code == widget.activeLanguage;

                            return _LanguageTile(
                              code: code,
                              name: name,
                              nativeName: nativeName,
                              flag: flag,
                              isDownloaded: isDownloaded,
                              isDownloading: isDownloading,
                              isActive: isActive,
                              isDark: isDark,
                              onTap: isDownloaded ? () => _select(code) : null,
                              onDownload: () => _download(code),
                              onDelete:
                                  isDownloaded && !isActive
                                      ? () => _delete(code)
                                      : null,
                            );
                          },
                        ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LanguageTile extends StatelessWidget {
  final String code;
  final String name;
  final String nativeName;
  final String flag;
  final bool isDownloaded;
  final bool isDownloading;
  final bool isActive;
  final bool isDark;
  final VoidCallback? onTap;
  final VoidCallback onDownload;
  final VoidCallback? onDelete;

  const _LanguageTile({
    required this.code,
    required this.name,
    required this.nativeName,
    required this.flag,
    required this.isDownloaded,
    required this.isDownloading,
    required this.isActive,
    required this.isDark,
    this.onTap,
    required this.onDownload,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: isDownloaded ? onTap : onDownload,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color:
              isActive
                  ? Colors.deepPurple.withValues(alpha: isDark ? 0.15 : 0.06)
                  : null,
        ),
        child: Row(
          children: [
            // Flag
            Text(flag, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 14),

            // Name + native name
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  if (nativeName != name)
                    Text(
                      nativeName,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                ],
              ),
            ),

            // Status / actions
            if (isDownloading) ...[
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.deepPurple.withValues(alpha: 0.7),
                ),
              ),
            ] else if (isActive) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Active',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.deepPurple,
                  ),
                ),
              ),
            ] else if (isDownloaded) ...[
              // Select button
              GestureDetector(
                onTap: onTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.deepPurple.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Text(
                    'Use',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.deepPurple,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Delete button
              if (onDelete != null)
                GestureDetector(
                  onTap: onDelete,
                  child: Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: isDark ? Colors.white30 : Colors.black26,
                  ),
                ),
            ] else ...[
              // Download button
              GestureDetector(
                onTap: onDownload,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark ? Colors.white12 : Colors.black12,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.download_rounded,
                        size: 14,
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '~15 MB',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white38 : Colors.black45,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
