import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/grammar_check_service.dart';

// =============================================================================
// ⚙️ GRAMMAR SETTINGS SHEET — Toggleable rules list
//
// Premium bottom sheet for enabling/disabling grammar rules.
// Categorized by language with smooth animations.
// =============================================================================

class GrammarSettingsSheet extends StatefulWidget {
  const GrammarSettingsSheet({super.key});

  /// Show the settings sheet.
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const GrammarSettingsSheet(),
    );
  }

  @override
  State<GrammarSettingsSheet> createState() => _GrammarSettingsSheetState();
}

class _GrammarSettingsSheetState extends State<GrammarSettingsSheet> {
  final _service = GrammarCheckService.instance;
  late bool _grammarEnabled;

  @override
  void initState() {
    super.initState();
    _grammarEnabled = _service.enabled;
  }

  @override
  Widget build(BuildContext context) {
    final rules = _service.availableRules;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Group rules by category
    final categories = _categorizeRules(rules);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
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
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[700] : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.rule_rounded,
                  color: isDark ? Colors.blue[300] : Colors.blue[700],
                  size: 22,
                ),
                const SizedBox(width: 10),
                Text(
                  'Grammar Rules',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black87,
                    letterSpacing: -0.3,
                  ),
                ),
                const Spacer(),
                // Master toggle
                Transform.scale(
                  scale: 0.85,
                  child: Switch.adaptive(
                    value: _grammarEnabled,
                    activeThumbColor: Colors.blue,
                    onChanged: (v) {
                      HapticFeedback.lightImpact();
                      setState(() {
                        _grammarEnabled = v;
                        _service.setEnabled(v);
                      });
                    },
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Rules list
          Flexible(
            child: AnimatedOpacity(
              opacity: _grammarEnabled ? 1.0 : 0.4,
              duration: const Duration(milliseconds: 200),
              child: AbsorbPointer(
                absorbing: !_grammarEnabled,
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    return _buildCategory(category, isDark);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategory(_RuleCategory category, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Text(
            category.title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              letterSpacing: 0.5,
            ),
          ),
        ),
        // Rules
        ...category.rules.map((rule) => _buildRuleTile(rule, isDark)),
      ],
    );
  }

  Widget _buildRuleTile(
    ({String id, String name, bool enabled}) rule,
    bool isDark,
  ) {
    final info = _ruleInfo[rule.id];
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: Text(
        info?.emoji ?? '📝',
        style: const TextStyle(fontSize: 18),
      ),
      title: Text(
        info?.displayName ?? rule.name,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
      subtitle: info?.description != null
          ? Text(
              info!.description,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.grey[500] : Colors.grey[600],
              ),
            )
          : null,
      trailing: Transform.scale(
        scale: 0.75,
        child: Switch.adaptive(
          value: rule.enabled,
          activeThumbColor: Colors.blue,
          onChanged: (v) {
            HapticFeedback.selectionClick();
            setState(() {
              if (v) {
                _service.enableRule(rule.id);
              } else {
                _service.disableRule(rule.id);
              }
            });
          },
        ),
      ),
    );
  }

  // ── Rule categorization ────────────────────────────────────────────────

  List<_RuleCategory> _categorizeRules(
    List<({String id, String name, bool enabled})> rules,
  ) {
    final universal = <({String id, String name, bool enabled})>[];
    final english = <({String id, String name, bool enabled})>[];
    final romance = <({String id, String name, bool enabled})>[];
    final germanic = <({String id, String name, bool enabled})>[];
    final slavic = <({String id, String name, bool enabled})>[];
    final other = <({String id, String name, bool enabled})>[];

    for (final rule in rules) {
      if (rule.id.startsWith('en_')) english.add(rule);
      else if (rule.id.startsWith('it_') || rule.id.startsWith('es_') ||
               rule.id.startsWith('fr_') || rule.id.startsWith('pt_') ||
               rule.id.startsWith('ro_')) romance.add(rule);
      else if (rule.id.startsWith('de_') || rule.id.startsWith('nl_') ||
               rule.id.startsWith('sv_')) germanic.add(rule);
      else if (rule.id.startsWith('pl_') || rule.id.startsWith('cs_') ||
               rule.id.startsWith('hr_')) slavic.add(rule);
      else if (rule.id.startsWith('tr_') || rule.id.startsWith('hu_')) other.add(rule);
      else universal.add(rule);
    }

    return [
      if (universal.isNotEmpty) _RuleCategory('🌍 UNIVERSAL', universal),
      if (english.isNotEmpty) _RuleCategory('🇬🇧 ENGLISH', english),
      if (romance.isNotEmpty) _RuleCategory('🇮🇹🇪🇸🇫🇷🇵🇹🇷🇴 ROMANCE', romance),
      if (germanic.isNotEmpty) _RuleCategory('🇩🇪🇳🇱🇸🇪 GERMANIC', germanic),
      if (slavic.isNotEmpty) _RuleCategory('🇵🇱🇨🇿🇭🇷 SLAVIC', slavic),
      if (other.isNotEmpty) _RuleCategory('🇹🇷🇭🇺 OTHER', other),
    ];
  }

  // ── Rule metadata for display ──────────────────────────────────────────

  static const _ruleInfo = <String, _RuleDisplayInfo>{
    'duplicate_word': _RuleDisplayInfo('🔁', 'Duplicate Words', '"the the" → "the"'),
    'sentence_capitalization': _RuleDisplayInfo('🔠', 'Capitalization', 'After . ! ?'),
    'double_space': _RuleDisplayInfo('⬜', 'Double Spaces', 'Multiple spaces → single'),
    'missing_space_punctuation': _RuleDisplayInfo('✏️', 'Punctuation Spacing', 'hello,world → hello, world'),
    'punctuation_pairing': _RuleDisplayInfo('🔗', 'Bracket Pairing', 'Unclosed ( [ {'),
    'ellipsis': _RuleDisplayInfo('…', 'Ellipsis', '... → …'),
    'common_typo': _RuleDisplayInfo('🔤', 'Common Typos', 'teh → the'),
    'number_formatting': _RuleDisplayInfo('🔢', 'Number Format', '1000000 → 1.000.000'),
    'bigram_context': _RuleDisplayInfo('🧠', 'Context Suggestions', 'Bigram-powered'),
    'en_confusables': _RuleDisplayInfo('🔀', 'Confusables', 'your/you\'re, its/it\'s'),
    'en_contractions': _RuleDisplayInfo('✂️', 'Contractions', 'dont → don\'t'),
    'en_subject_verb': _RuleDisplayInfo('📐', 'Subject-Verb', 'He don\'t → He doesn\'t'),
    'it_article_agreement': _RuleDisplayInfo('🇮🇹', 'IT Articles', 'il casa → la casa'),
    'it_avere_essere': _RuleDisplayInfo('🇮🇹', 'IT Avere/Essere', 'ho andato → sono andato'),
    'es_article_agreement': _RuleDisplayInfo('🇪🇸', 'ES Articles', 'el ciudad → la ciudad'),
    'fr_article_agreement': _RuleDisplayInfo('🇫🇷', 'FR Articles', 'le maison → la maison'),
    'pt_article_agreement': _RuleDisplayInfo('🇵🇹', 'PT Articles', 'o cidade → a cidade'),
    'ro_article_agreement': _RuleDisplayInfo('🇷🇴', 'RO Articles', 'un casă → o casă'),
    'de_noun_capitalization': _RuleDisplayInfo('🇩🇪', 'DE Capitalization', 'haus → Haus'),
    'nl_article': _RuleDisplayInfo('🇳🇱', 'NL de/het', 'de huis → het huis'),
    'sv_article': _RuleDisplayInfo('🇸🇪', 'SV en/ett', 'en hus → ett hus'),
    'pl_diacritics': _RuleDisplayInfo('🇵🇱', 'PL Diacritics', 'dziekuje → dziękuję'),
    'cs_diacritics': _RuleDisplayInfo('🇨🇿', 'CS Háček', 'cesky → česky'),
    'hr_diacritics': _RuleDisplayInfo('🇭🇷', 'HR Diacritics', 'zivot → život'),
    'tr_vowel_harmony': _RuleDisplayInfo('🇹🇷', 'TR Vowel Harmony', '-da/-de suffix'),
    'hu_accents': _RuleDisplayInfo('🇭🇺', 'HU Accents', 'koszonom → köszönöm'),
  };
}

class _RuleCategory {
  final String title;
  final List<({String id, String name, bool enabled})> rules;
  const _RuleCategory(this.title, this.rules);
}

class _RuleDisplayInfo {
  final String emoji;
  final String displayName;
  final String description;
  const _RuleDisplayInfo(this.emoji, this.displayName, this.description);
}
