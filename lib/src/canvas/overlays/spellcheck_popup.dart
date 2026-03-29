import 'package:flutter/material.dart';
import '../../services/spellcheck_service.dart';

// =============================================================================
// 🔍 SPELLCHECK POPUP — Correction suggestions overlay
//
// Floating popup shown when user taps a misspelled word.
// Shows 2-3 suggestions as chips + ignore/add to dictionary buttons.
// =============================================================================

class SpellcheckPopup extends StatelessWidget {
  final SpellcheckError error;
  final Offset position;
  final double canvasScale;
  final VoidCallback onDismiss;
  final ValueChanged<String> onCorrect;
  final VoidCallback onIgnore;
  final VoidCallback? onAddToDictionary;

  const SpellcheckPopup({
    super.key,
    required this.error,
    required this.position,
    required this.canvasScale,
    required this.onDismiss,
    required this.onCorrect,
    required this.onIgnore,
    this.onAddToDictionary,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx,
      top: position.dy,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        builder: (context, opacity, child) {
          return Transform.scale(
            scale: 0.9 + 0.1 * opacity,
            alignment: Alignment.topLeft,
            child: Opacity(opacity: opacity, child: child),
          );
        },
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          color: const Color(0xFF1E1E2E), // Dark surface
          shadowColor: Colors.black54,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 280),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF333355),
                width: 0.5,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: misspelled word
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.spellcheck,
                      size: 14,
                      color: Color(0xFFE53935),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '"${error.word}"',
                      style: const TextStyle(
                        color: Color(0xFFE53935),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        fontStyle: FontStyle.italic,
                        fontFamily: 'Roboto',
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),

                if (error.suggestions.isNotEmpty) ...[
                  const SizedBox(height: 8),

                  // Suggestion chips
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: error.suggestions.map((suggestion) {
                      return GestureDetector(
                        onTap: () => onCorrect(suggestion),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2A2A4A),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(0xFF4A4A7A),
                              width: 0.5,
                            ),
                          ),
                          child: Text(
                            suggestion,
                            style: const TextStyle(
                              color: Color(0xFF8B9CF7),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              fontFamily: 'Roboto',
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],

                const SizedBox(height: 6),

                // Action buttons row
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Ignore button
                    GestureDetector(
                      onTap: onIgnore,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: const Text(
                          'Ignore',
                          style: TextStyle(
                            color: Color(0xFF888899),
                            fontSize: 11,
                            fontFamily: 'Roboto',
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ),

                    if (onAddToDictionary != null) ...[
                      const SizedBox(width: 4),
                      const Text('·', style: TextStyle(
                        color: Color(0xFF555566),
                        fontSize: 11,
                        fontFamily: 'Roboto',
                        decoration: TextDecoration.none,
                      )),
                      const SizedBox(width: 4),
                      // Add to dictionary button
                      GestureDetector(
                        onTap: onAddToDictionary,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_circle_outline,
                                size: 12,
                                color: Color(0xFF66BB6A),
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Add to dictionary',
                                style: TextStyle(
                                  color: Color(0xFF66BB6A),
                                  fontSize: 11,
                                  fontFamily: 'Roboto',
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
