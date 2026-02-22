import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../systems/design_token_exporter.dart';

// ============================================================================
// 🎨 TOKEN EXPORT DIALOG — Export design tokens in CSS / Kotlin / Swift
// ============================================================================

class TokenExportDialog extends StatefulWidget {
  final DesignTokenFormat format;
  const TokenExportDialog({super.key, required this.format});

  @override
  State<TokenExportDialog> createState() => _TokenExportDialogState();
}

class _TokenExportDialogState extends State<TokenExportDialog> {
  late DesignTokenFormat _selectedFormat;

  @override
  void initState() {
    super.initState();
    _selectedFormat = widget.format;
  }

  String get _formatLabel => switch (_selectedFormat) {
    DesignTokenFormat.cssCustomProperties => 'CSS Custom Properties',
    DesignTokenFormat.kotlinObject => 'Kotlin Object',
    DesignTokenFormat.swiftStruct => 'Swift Struct',
    DesignTokenFormat.w3c => 'W3C JSON',
    DesignTokenFormat.styleDictionary => 'Style Dictionary',
  };

  IconData get _formatIcon => switch (_selectedFormat) {
    DesignTokenFormat.cssCustomProperties => Icons.css_rounded,
    DesignTokenFormat.kotlinObject => Icons.android_rounded,
    DesignTokenFormat.swiftStruct => Icons.apple_rounded,
    DesignTokenFormat.w3c => Icons.data_object_rounded,
    DesignTokenFormat.styleDictionary => Icons.token_rounded,
  };

  String get _previewCode => switch (_selectedFormat) {
    DesignTokenFormat.cssCustomProperties =>
      ':root {\n'
          '  --color-primary: #6750A4;\n'
          '  --color-secondary: #625B71;\n'
          '  --spacing-sm: 8px;\n'
          '  --spacing-md: 16px;\n'
          '  --radius-card: 12px;\n'
          '}',
    DesignTokenFormat.kotlinObject =>
      'object DesignTokens {\n'
          '  val colorPrimary: Long = 0xFF6750A4\n'
          '  val colorSecondary: Long = 0xFF625B71\n'
          '  val spacingSm: Double = 8.0\n'
          '  val spacingMd: Double = 16.0\n'
          '  val radiusCard: Double = 12.0\n'
          '}',
    DesignTokenFormat.swiftStruct =>
      'struct DesignTokens {\n'
          '  static let colorPrimary = Color(hex: "#6750A4")\n'
          '  static let colorSecondary = Color(hex: "#625B71")\n'
          '  static let spacingSm: CGFloat = 8\n'
          '  static let spacingMd: CGFloat = 16\n'
          '  static let radiusCard: CGFloat = 12\n'
          '}',
    _ => '{ "tokens": {} }',
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      builder:
          (ctx, scrollCtrl) => Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 4),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Icon(_formatIcon, color: cs.primary, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        'Export Design Tokens',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                // Format picker
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      for (final fmt in [
                        DesignTokenFormat.cssCustomProperties,
                        DesignTokenFormat.kotlinObject,
                        DesignTokenFormat.swiftStruct,
                      ]) ...[
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _selectedFormat = fmt),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color:
                                    _selectedFormat == fmt
                                        ? cs.primaryContainer
                                        : cs.surfaceContainerHighest.withValues(
                                          alpha: 0.5,
                                        ),
                                borderRadius: BorderRadius.circular(10),
                                border:
                                    _selectedFormat == fmt
                                        ? Border.all(
                                          color: cs.primary.withValues(
                                            alpha: 0.4,
                                          ),
                                        )
                                        : null,
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    switch (fmt) {
                                      DesignTokenFormat.cssCustomProperties =>
                                        Icons.css_rounded,
                                      DesignTokenFormat.kotlinObject =>
                                        Icons.android_rounded,
                                      DesignTokenFormat.swiftStruct =>
                                        Icons.apple_rounded,
                                      _ => Icons.code_rounded,
                                    },
                                    size: 20,
                                    color:
                                        _selectedFormat == fmt
                                            ? cs.onPrimaryContainer
                                            : cs.onSurfaceVariant,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    switch (fmt) {
                                      DesignTokenFormat.cssCustomProperties =>
                                        'CSS',
                                      DesignTokenFormat.kotlinObject =>
                                        'Kotlin',
                                      DesignTokenFormat.swiftStruct => 'Swift',
                                      _ => '',
                                    },
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight:
                                          _selectedFormat == fmt
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                      color:
                                          _selectedFormat == fmt
                                              ? cs.onPrimaryContainer
                                              : cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Code preview
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: cs.outlineVariant.withValues(alpha: 0.3),
                        ),
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _formatLabel,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.copy_rounded,
                                    size: 18,
                                    color: cs.primary,
                                  ),
                                  onPressed: () {
                                    Clipboard.setData(
                                      ClipboardData(text: _previewCode),
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Tokens copied to clipboard',
                                        ),
                                      ),
                                    );
                                  },
                                  tooltip: 'Copy',
                                ),
                              ],
                            ),
                            Text(
                              _previewCode,
                              style: TextStyle(
                                fontSize: 12,
                                fontFamily: 'monospace',
                                color: cs.onSurface,
                                height: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Export button
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _previewCode));
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('$_formatLabel exported!'),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.download_rounded),
                      label: Text('Export $_formatLabel'),
                    ),
                  ),
                ),
              ],
            ),
          ),
    );
  }
}
