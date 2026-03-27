part of 'latex_editor_sheet.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 🧮 LaTeX Editor — Helper Widgets, Data & Formatters
// ═══════════════════════════════════════════════════════════════════════════

// =============================================================================
// Editor Mode
// =============================================================================

/// Input modes for the LaTeX editor.
enum LatexEditorMode {
  /// Traditional keyboard text input.
  keyboard,

  /// Stylus/touch handwriting recognition.
  handwriting,

  /// Symbol palette insertion.
  symbols,

  /// Camera/photo OCR recognition.
  camera,
}

// =============================================================================
// E5: Template Data
// =============================================================================

class _TemplateData {
  final String name;
  final String preview;
  final String latex;
  const _TemplateData(this.name, this.preview, this.latex);
}

const _templates = [
  _TemplateData(
    'Quadratica',
    'x = −b±√…',
    r'x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}',
  ),
  _TemplateData('Euler', 'e^{iπ}+1=0', r'e^{i\pi} + 1 = 0'),
  _TemplateData('Pitagora', 'a²+b²=c²', r'a^2 + b^2 = c^2'),
  _TemplateData('Derivata', 'df/dx', r'\frac{d}{dx} f(x)'),
  _TemplateData('Integrale def.', '∫ₐᵇ f dx', r'\int_{a}^{b} f(x) \, dx'),
  _TemplateData(
    'Taylor',
    'f=∑ fⁿ/n!',
    r'f(x) = \sum_{n=0}^{\infty} \frac{f^{(n)}(a)}{n!} (x-a)^n',
  ),
  _TemplateData('Limite', 'lim x→∞', r'\lim_{x \to \infty} f(x)'),
  _TemplateData(
    'Matrice 2×2',
    '[ a b; c d ]',
    r'\begin{pmatrix} a & b \\ c & d \end{pmatrix}',
  ),
  _TemplateData('Binomiale', '(n k)', r'\binom{n}{k}'),
  _TemplateData('Sommatoria', '∑ᵢ₌₁ⁿ', r'\sum_{i=1}^{n} a_i'),
  _TemplateData('Produttoria', '∏ᵢ₌₁ⁿ', r'\prod_{i=1}^{n} a_i'),
  _TemplateData(
    'Sistema',
    '{ eq₁; eq₂ }',
    r'\begin{cases} x + y = 1 \\ x - y = 0 \end{cases}',
  ),
];

// =============================================================================
// Helper Widgets
// =============================================================================

class _QuickInsertChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickInsertChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.secondaryContainer,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: cs.onSecondaryContainer,
            ),
          ),
        ),
      ),
    );
  }
}

/// E5: Template library toggle chip
class _TemplateToggleChip extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onTap;

  const _TemplateToggleChip({required this.isExpanded, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: isExpanded ? cs.primaryContainer : cs.tertiaryContainer,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                size: 14,
                color:
                    isExpanded ? cs.onPrimaryContainer : cs.onTertiaryContainer,
              ),
              const SizedBox(width: 4),
              Text(
                'Template',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color:
                      isExpanded
                          ? cs.onPrimaryContainer
                          : cs.onTertiaryContainer,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                isExpanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                size: 16,
                color:
                    isExpanded ? cs.onPrimaryContainer : cs.onTertiaryContainer,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// E5: Template card
class _TemplateCard extends StatelessWidget {
  final String name;
  final String preview;
  final VoidCallback onTap;

  const _TemplateCard({
    required this.name,
    required this.preview,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                preview,
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: cs.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolbarIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? dotColor;
  final double? size;

  const _ToolbarIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.dotColor,
    this.size,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: size ?? 36,
            height: size ?? 36,
            child: Center(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    icon,
                    size: size != null ? 18 : 20,
                    color: cs.onSurfaceVariant,
                  ),
                  if (dotColor != null)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: dotColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: cs.surface, width: 1.5),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact text key for the keyboard toolbar (e.g. '\\', '{', '}').
class _CompactKey extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final ColorScheme cs;
  final Color? bgColor;

  const _CompactKey({
    required this.label,
    required this.onTap,
    required this.cs,
    this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bgColor ?? cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 34,
          height: 32,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
                color: cs.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact icon key for the keyboard toolbar (e.g. arrow keys).
class _CompactIconKey extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final ColorScheme cs;
  final Color? bgColor;

  const _CompactIconKey({
    required this.icon,
    required this.onTap,
    required this.cs,
    this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bgColor ?? cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 34,
          height: 32,
          child: Center(child: Icon(icon, size: 18, color: cs.onSurface)),
        ),
      ),
    );
  }
}

/// E2: Header icon button (undo/redo) with enabled state
class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              icon,
              size: 20,
              color:
                  enabled
                      ? cs.onSurfaceVariant
                      : cs.onSurfaceVariant.withValues(alpha: 0.3),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// T3: Auto-bracket closing formatter
// =============================================================================

/// Automatically inserts matching closing brackets and positions
/// the cursor between them.
class _AutoBracketFormatter extends TextInputFormatter {
  static const _pairs = <String, String>{'{': '}', '(': ')', '[': ']'};

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Only process single-char insertions
    if (newValue.text.length != oldValue.text.length + 1) return newValue;
    if (!newValue.selection.isCollapsed) return newValue;

    final cursor = newValue.selection.baseOffset;
    if (cursor < 1) return newValue;

    final inserted = newValue.text[cursor - 1];
    final closer = _pairs[inserted];

    if (closer != null) {
      // Check if the next char is already the matching closer
      if (cursor < newValue.text.length && newValue.text[cursor] == closer) {
        return newValue;
      }

      // Insert the closer and position cursor between
      final text =
          newValue.text.substring(0, cursor) +
          closer +
          newValue.text.substring(cursor);
      return TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: cursor),
      );
    }

    return newValue;
  }
}

// =============================================================================
// T5: Intent classes for keyboard shortcuts
// =============================================================================

class _ConfirmIntent extends Intent {
  const _ConfirmIntent();
}

class _RedoIntent extends Intent {
  const _RedoIntent();
}

class _CancelIntent extends Intent {
  const _CancelIntent();
}

/// Helper for history sheet items.
class _HistoryItem {
  final String expr;
  final bool isFavorite;
  const _HistoryItem(this.expr, {required this.isFavorite});
}
