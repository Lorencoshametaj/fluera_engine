import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/dictionary_lookup_service.dart';
import '../../../services/thesaurus_service.dart';
import '../../../services/language_detection_service.dart';

// =============================================================================
// 🔄 SYNONYM POPUP — Inline synonym suggestions with one-tap replacement
//
// Offline-first: ThesaurusService (instant) → DictionaryLookupService (API).
// Tap a chip → replaces the original word in-place.
// =============================================================================

class SynonymPopup extends StatefulWidget {
  final String word;
  final void Function(String replacement) onReplace;
  final VoidCallback onDismiss;

  const SynonymPopup({
    super.key,
    required this.word,
    required this.onReplace,
    required this.onDismiss,
  });

  /// Show synonym popup as a bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required String word,
    required void Function(String replacement) onReplace,
  }) {
    HapticFeedback.mediumImpact();
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SynonymPopup(
        word: word,
        onReplace: (replacement) {
          Navigator.of(context).pop();
          onReplace(replacement);
        },
        onDismiss: () => Navigator.of(context).pop(),
      ),
    );
  }

  @override
  State<SynonymPopup> createState() => _SynonymPopupState();
}

class _SynonymPopupState extends State<SynonymPopup> {
  List<String> _synonyms = [];
  List<String> _antonyms = [];
  bool _loading = true;
  bool _isOffline = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchSynonyms();
  }

  Future<void> _fetchSynonyms() async {
    final lower = widget.word.toLowerCase();

    // ── Step 1: Try offline thesaurus (instant) ──
    final lang = LanguageDetectionService.instance.detectWordLanguage(lower);
    final langCode = lang.name;

    if (ThesaurusService.instance.supportsLanguage(langCode)) {
      final offlineSyns = await ThesaurusService.instance.lookUp(lower, langCode);
      if (offlineSyns.isNotEmpty) {
        setState(() {
          _synonyms = offlineSyns.take(12).toList();
          _loading = false;
          _isOffline = true;
        });
        return;
      }
    }

    // ── Step 2: Fallback to API (DictionaryLookupService) ──
    try {
      final result = await DictionaryLookupService.instance.lookUp(lower);

      if (result == null || result.definitions.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'No synonyms found';
        });
        return;
      }

      final synonyms = <String>{};
      final antonyms = <String>{};
      for (final def in result.definitions) {
        synonyms.addAll(def.synonyms);
        antonyms.addAll(def.antonyms);
      }
      synonyms.remove(lower);
      antonyms.remove(lower);

      setState(() {
        _synonyms = synonyms.take(12).toList();
        _antonyms = antonyms.take(6).toList();
        _loading = false;
        if (_synonyms.isEmpty && _antonyms.isEmpty) {
          _error = 'No synonyms found for "${widget.word}"';
        }
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Could not fetch synonyms';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[600] : Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF5856D6).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.swap_horiz_rounded,
                    color: Color(0xFF5856D6),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Synonyms',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      Text(
                        'Tap to replace "${widget.word}"',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, indent: 20, endIndent: 20),

          // Content
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator.adaptive(),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(
                    Icons.search_off_rounded,
                    size: 40,
                    color: isDark ? Colors.grey[600] : Colors.grey[400],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.grey[500] : Colors.grey[500],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Synonyms
                  if (_synonyms.isNotEmpty) ...[
                    _buildSectionLabel('Synonyms', Icons.swap_horiz_rounded,
                        const Color(0xFF5856D6), isDark),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _synonyms.map((s) => _buildChip(
                        s,
                        const Color(0xFF5856D6),
                        isDark,
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          widget.onReplace(s);
                        },
                      )).toList(),
                    ),
                  ],

                  // Antonyms
                  if (_antonyms.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildSectionLabel('Antonyms', Icons.compare_arrows_rounded,
                        const Color(0xFFFF6B6B), isDark),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _antonyms.map((a) => _buildChip(
                        a,
                        const Color(0xFFFF6B6B),
                        isDark,
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          widget.onReplace(a);
                        },
                      )).toList(),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(
    String label,
    IconData icon,
    Color color,
    bool isDark,
  ) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color.withValues(alpha: 0.7)),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  Widget _buildChip(
    String text,
    Color color,
    bool isDark, {
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withValues(alpha: isDark ? 0.15 : 0.08),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}
