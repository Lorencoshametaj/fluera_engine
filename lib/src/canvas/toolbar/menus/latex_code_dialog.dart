import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// =============================================================================
// LaTeX Code Dialog — extracted from _ui_toolbar.dart
//
// A reusable dialog that displays generated LaTeX code with syntax highlighting,
// package warnings, and a copy-to-clipboard action.
// =============================================================================

class LatexCodeDialog extends StatelessWidget {
  final String latex;
  final VoidCallback? onCopied;

  const LatexCodeDialog({super.key, required this.latex, this.onCopied});

  static Future<void> show(BuildContext context, String latex) {
    return showDialog<void>(
      context: context,
      builder:
          (ctx) => LatexCodeDialog(
            latex: latex,
            onCopied:
                () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('LaTeX copied to clipboard'),
                    duration: Duration(seconds: 2),
                  ),
                ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final needsMultirow = latex.contains(r'\multirow');
    final needsBooktabs = latex.contains(r'\toprule');
    final needsPackages = needsMultirow || needsBooktabs;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: const Color(0xFF1E1E1E),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      title: Row(
        children: [
          Icon(Icons.code_rounded, color: cs.primary, size: 22),
          const SizedBox(width: 10),
          const Text(
            'LaTeX Code',
            style: TextStyle(
              color: Color(0xFFE0E0E0),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Package requirements notice
          if (needsPackages)
            _PackageWarning(multirow: needsMultirow, booktabs: needsBooktabs),

          // LaTeX code viewer
          Container(
            width: double.maxFinite,
            constraints: const BoxConstraints(maxHeight: 300),
            decoration: BoxDecoration(
              color: const Color(0xFF121212),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF333333), width: 0.5),
            ),
            padding: const EdgeInsets.all(14),
            child: SingleChildScrollView(
              child: SelectableText(
                latex,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: Color(0xFFA5D6A7),
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: latex));
            HapticFeedback.mediumImpact();
            Navigator.of(context).pop();
            onCopied?.call();
          },
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: const Text('Copy'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _PackageWarning extends StatelessWidget {
  final bool multirow;
  final bool booktabs;

  const _PackageWarning({required this.multirow, required this.booktabs});

  @override
  Widget build(BuildContext context) {
    final packages = [
      if (multirow) r'\usepackage{multirow}',
      if (booktabs) r'\usepackage{booktabs}',
    ].join('\n');

    return Container(
      width: double.maxFinite,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2010),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF5C4A1E), width: 0.5),
      ),
      child: Text(
        '📦 Add to preamble:\n$packages',
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: Color(0xFFFFD54F),
          height: 1.4,
        ),
      ),
    );
  }
}
