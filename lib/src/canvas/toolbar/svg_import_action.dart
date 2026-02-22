/// 📥 SVG IMPORT ACTION — File picker + import into scene graph.
///
/// Provides a button action that opens a file picker, reads SVG content,
/// parses it via [SvgImporter], and adds the result to the scene graph.
///
/// ```dart
/// SvgImportAction(
///   onImported: (group) => sceneGraph.addLayer(group),
/// )
/// ```
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../export/svg_importer.dart';
import '../../core/nodes/group_node.dart';

/// Toolbar button that imports an SVG file via clipboard paste or callback.
///
/// Since Flutter doesn't have a built-in file picker, this provides:
/// 1. A paste-from-clipboard action for SVG strings
/// 2. A callback-based API for when the host app provides the SVG content
class SvgImportAction extends StatelessWidget {
  /// Called with the imported GroupNode tree.
  final void Function(GroupNode importedTree)? onImported;

  /// Called with an error message if import fails.
  final void Function(String error)? onError;

  /// Icon to display.
  final IconData icon;

  /// Tooltip text.
  final String tooltip;

  const SvgImportAction({
    super.key,
    this.onImported,
    this.onError,
    this.icon = Icons.upload_file,
    this.tooltip = 'Import SVG',
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      onPressed: () => _showImportDialog(context),
    );
  }

  void _showImportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (ctx) => _SvgImportDialog(onImported: onImported, onError: onError),
    );
  }

  /// Import from an SVG string directly (for programmatic use).
  static GroupNode? importFromString(String svgContent) {
    if (svgContent.trim().isEmpty) return null;
    final importer = SvgImporter();
    return importer.parse(svgContent);
  }
}

class _SvgImportDialog extends StatefulWidget {
  final void Function(GroupNode)? onImported;
  final void Function(String)? onError;

  const _SvgImportDialog({this.onImported, this.onError});

  @override
  State<_SvgImportDialog> createState() => _SvgImportDialogState();
}

class _SvgImportDialogState extends State<_SvgImportDialog> {
  final _controller = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      setState(() => _controller.text = data!.text!);
    }
  }

  void _import() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _errorText = 'Please paste SVG content');
      return;
    }
    if (!text.contains('<svg')) {
      setState(() => _errorText = 'Not a valid SVG (missing <svg> tag)');
      return;
    }

    try {
      final importer = SvgImporter();
      final result = importer.parse(text);

      if (result.children.isEmpty) {
        setState(() => _errorText = 'No elements found in SVG');
        return;
      }

      Navigator.pop(context);
      widget.onImported?.call(result);
    } catch (e) {
      setState(() => _errorText = 'Import failed: $e');
      widget.onError?.call(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.upload_file, size: 20),
          SizedBox(width: 8),
          Text('Import SVG'),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              maxLines: 8,
              decoration: InputDecoration(
                hintText: 'Paste SVG content here...',
                border: const OutlineInputBorder(),
                errorText: _errorText,
              ),
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _pasteFromClipboard,
              icon: const Icon(Icons.content_paste, size: 16),
              label: const Text('Paste from clipboard'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _import, child: const Text('Import')),
      ],
    );
  }
}
