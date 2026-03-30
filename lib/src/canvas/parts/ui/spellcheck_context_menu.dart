import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/spellcheck_service.dart';
import '../../../services/personal_dictionary_service.dart';

// =============================================================================
// 📋 SPELLCHECK CONTEXT MENU — Long-press / tap correction menu
//
// Premium floating context menu for spelling and grammar corrections.
// Actions: Apply correction, Ignore, Add to dictionary.
// =============================================================================

/// Data for a context menu item.
class SpellcheckContextAction {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  const SpellcheckContextAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.color,
  });
}

class SpellcheckContextMenu extends StatelessWidget {
  final Offset position;
  final String word;
  final List<String> suggestions;
  final bool isGrammar; // true = grammar error, false = spelling error
  final String? grammarMessage;
  final VoidCallback onDismiss;
  final void Function(String correction) onApplyCorrection;
  final VoidCallback? onIgnore;
  final VoidCallback? onAddToDictionary;
  final VoidCallback? onLookUp;
  final VoidCallback? onSynonyms;

  const SpellcheckContextMenu({
    super.key,
    required this.position,
    required this.word,
    required this.suggestions,
    this.isGrammar = false,
    this.grammarMessage,
    required this.onDismiss,
    required this.onApplyCorrection,
    this.onIgnore,
    this.onAddToDictionary,
    this.onLookUp,
    this.onSynonyms,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accentColor = isGrammar ? Colors.blue : Colors.red;

    return Stack(
      children: [
        // Dismiss layer
        Positioned.fill(
          child: GestureDetector(
            onTap: onDismiss,
            behavior: HitTestBehavior.opaque,
            child: const SizedBox.expand(),
          ),
        ),

        // Menu
        Positioned(
          left: position.dx - 80,
          top: position.dy + 8,
          child: TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            tween: Tween(begin: 0.0, end: 1.0),
            builder: (context, value, child) {
              return Transform.scale(
                scale: 0.8 + (0.2 * value),
                alignment: Alignment.topCenter,
                child: Opacity(
                  opacity: value,
                  child: child,
                ),
              );
            },
            child: _buildMenuCard(isDark, accentColor),
          ),
        ),
      ],
    );
  }

  Widget _buildMenuCard(bool isDark, Color accentColor) {
    return Material(
      elevation: 12,
      borderRadius: BorderRadius.circular(14),
      shadowColor: Colors.black45,
      color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
      child: Container(
        constraints: const BoxConstraints(
          minWidth: 160,
          maxWidth: 260,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header: error type + word
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: isDark ? 0.15 : 0.08),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(14),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        isGrammar ? Icons.rule_rounded : Icons.spellcheck_rounded,
                        size: 14,
                        color: accentColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isGrammar ? 'Grammar' : 'Spelling',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: accentColor,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    grammarMessage ?? '"$word"',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Suggestions
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: suggestions.map((s) {
                    return _SuggestionChip(
                      text: s,
                      accentColor: accentColor,
                      isDark: isDark,
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        onApplyCorrection(s);
                      },
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 4),
            ],

            const Divider(height: 1, indent: 10, endIndent: 10),

            // Action buttons
            if (onIgnore != null)
              _ActionTile(
                icon: Icons.visibility_off_outlined,
                label: 'Ignore',
                isDark: isDark,
                onTap: () {
                  HapticFeedback.lightImpact();
                  SpellcheckService.instance.ignoreWord(word);
                  onIgnore!();
                },
              ),

            if (!isGrammar && onAddToDictionary != null)
              _ActionTile(
                icon: Icons.add_circle_outline_rounded,
                label: 'Add to Dictionary',
                isDark: isDark,
                onTap: () {
                  HapticFeedback.mediumImpact();
                  PersonalDictionaryService.instance.addWord(word);
                  onAddToDictionary!();
                },
              ),

            // Look Up action
            if (onLookUp != null)
              _ActionTile(
                icon: Icons.menu_book_outlined,
                label: 'Look Up',
                isDark: isDark,
                onTap: () {
                  HapticFeedback.lightImpact();
                  onLookUp!();
                },
              ),

            // Synonyms action
            if (onSynonyms != null)
              _ActionTile(
                icon: Icons.swap_horiz_rounded,
                label: 'Synonyms',
                isDark: isDark,
                onTap: () {
                  HapticFeedback.lightImpact();
                  onSynonyms!();
                },
              ),

            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final String text;
  final Color accentColor;
  final bool isDark;
  final VoidCallback onTap;

  const _SuggestionChip({
    required this.text,
    required this.accentColor,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: accentColor.withValues(alpha: isDark ? 0.2 : 0.1),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: accentColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.grey[300] : Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
