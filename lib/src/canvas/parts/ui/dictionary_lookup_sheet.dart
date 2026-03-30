import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/dictionary_lookup_service.dart';

// =============================================================================
// 📖 DICTIONARY LOOKUP SHEET — Premium word definition bottom sheet
//
// Shows: word, phonetic, definitions by part of speech, synonyms, examples.
// Triggered from SpellcheckContextMenu → "Look Up" action.
// =============================================================================

class DictionaryLookupSheet extends StatefulWidget {
  final String word;

  const DictionaryLookupSheet({super.key, required this.word});

  /// Show the lookup sheet for a word.
  static Future<void> show(BuildContext context, String word) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DictionaryLookupSheet(word: word),
    );
  }

  @override
  State<DictionaryLookupSheet> createState() => _DictionaryLookupSheetState();
}

class _DictionaryLookupSheetState extends State<DictionaryLookupSheet>
    with SingleTickerProviderStateMixin {
  DictionaryLookupResult? _result;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _lookUp();
  }

  Future<void> _lookUp() async {
    try {
      final result = await DictionaryLookupService.instance.lookUp(widget.word);
      if (mounted) {
        setState(() {
          _result = result;
          _loading = false;
          if (result == null || !result.hasDefinitions) {
            _error = 'No definition found for "${widget.word}"';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not connect to dictionary';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.65,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
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
          // Handle bar
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[700] : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Content
          if (_loading) _buildLoading(isDark)
          else if (_error != null) _buildError(isDark)
          else _buildResult(isDark),
        ],
      ),
    );
  }

  Widget _buildLoading(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          SizedBox(
            width: 24, height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: isDark ? Colors.blue[300] : Colors.blue[600],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Looking up "${widget.word}"…',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Icon(
            Icons.menu_book_outlined,
            size: 40,
            color: isDark ? Colors.grey[600] : Colors.grey[400],
          ),
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResult(bool isDark) {
    final result = _result!;
    return Flexible(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          // Word header + phonetic
          _buildHeader(result, isDark),
          const SizedBox(height: 16),

          // Definitions by part of speech
          ..._buildDefinitions(result, isDark),

          // Synonyms
          if (result.allSynonyms.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildSynonyms(result, isDark),
          ],

          // Antonyms
          if (result.allAntonyms.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildAntonyms(result, isDark),
          ],

          // Origin
          if (result.origin != null) ...[
            const SizedBox(height: 16),
            _buildOrigin(result, isDark),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(DictionaryLookupResult result, bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Word
        Flexible(
          child: Text(
            result.word,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black87,
              letterSpacing: -0.5,
            ),
          ),
        ),
        // Phonetic
        if (result.phonetic != null) ...[
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              result.phonetic!,
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.blue[300] : Colors.blue[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _buildDefinitions(
    DictionaryLookupResult result,
    bool isDark,
  ) {
    // Group by part of speech
    final grouped = <String, List<WordDefinition>>{};
    for (final def in result.definitions) {
      grouped.putIfAbsent(def.partOfSpeech, () => []).add(def);
    }

    final widgets = <Widget>[];
    for (final entry in grouped.entries) {
      // Part of speech label
      widgets.add(
        Container(
          margin: const EdgeInsets.only(top: 4, bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.purple.withValues(alpha: 0.15)
                : Colors.purple.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            entry.key,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.purple[200] : Colors.purple[700],
              letterSpacing: 0.5,
            ),
          ),
        ),
      );

      // Definitions (max 3 per POS)
      for (int i = 0; i < entry.value.length && i < 3; i++) {
        final def = entry.value[i];
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${i + 1}. ',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        def.definition,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white70 : Colors.black87,
                          height: 1.4,
                        ),
                      ),
                      if (def.example != null) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.grey[800]
                                : Colors.grey[100],
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '"${def.example}"',
                            style: TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }
    return widgets;
  }

  Widget _buildSynonyms(DictionaryLookupResult result, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Synonyms',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.green[300] : Colors.green[700],
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: result.allSynonyms.take(8).map((syn) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.green.withValues(alpha: 0.12)
                    : Colors.green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                syn,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.green[300] : Colors.green[700],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildAntonyms(DictionaryLookupResult result, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Antonyms',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.orange[300] : Colors.orange[700],
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: result.allAntonyms.take(6).map((ant) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.orange.withValues(alpha: 0.12)
                    : Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                ant,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.orange[300] : Colors.orange[700],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildOrigin(DictionaryLookupResult result, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Origin',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          result.origin!,
          style: TextStyle(
            fontSize: 12,
            fontStyle: FontStyle.italic,
            color: isDark ? Colors.grey[500] : Colors.grey[600],
            height: 1.3,
          ),
        ),
      ],
    );
  }
}
