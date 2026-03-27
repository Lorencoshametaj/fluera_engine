import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../services/text_recognition_service.dart';

// ============================================================================
// 📷 OCR Scan Dialog — Recognize text from photos
// ============================================================================

/// Result from the OCR dialog: text blocks with positions.
class OcrDialogResult {
  /// Whether to import as a single merged text block.
  final bool mergeAll;

  /// The full recognized text (if mergeAll == true).
  final String? fullText;

  /// Individual text blocks with positions (if mergeAll == false).
  final List<OcrTextBlock>? blocks;

  /// Image dimensions for coordinate mapping.
  final int imageWidth;
  final int imageHeight;

  const OcrDialogResult({
    required this.mergeAll,
    this.fullText,
    this.blocks,
    required this.imageWidth,
    required this.imageHeight,
  });
}

/// Dialog for scanning images and extracting text via OCR.
///
/// Shows a preview of the image with detected text blocks highlighted.
/// The user can import all text as one element or individual blocks.
class OcrScanDialog extends StatefulWidget {
  const OcrScanDialog({super.key});

  /// Show the OCR dialog and return the result.
  static Future<OcrDialogResult?> show(BuildContext context) {
    return showDialog<OcrDialogResult>(
      context: context,
      builder: (_) => const OcrScanDialog(),
    );
  }

  @override
  State<OcrScanDialog> createState() => _OcrScanDialogState();
}

class _OcrScanDialogState extends State<OcrScanDialog> {
  String? _imagePath;
  OcrResult? _ocrResult;
  bool _isScanning = false;
  String? _errorMessage;

  // ── UI state ──
  final Set<int> _selectedBlocks = {}; // indices of selected blocks
  bool _showOverlay = true;

  @override
  void initState() {
    super.initState();
    // Open file picker immediately
    WidgetsBinding.instance.addPostFrameCallback((_) => _pickImage());
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) {
      if (mounted && _imagePath == null) Navigator.pop(context);
      return;
    }

    final path = result.files.single.path;
    if (path == null) return;

    setState(() {
      _imagePath = path;
      _ocrResult = null;
      _errorMessage = null;
      _selectedBlocks.clear();
    });

    _runOcr(path);
  }

  Future<void> _runOcr(String path) async {
    setState(() => _isScanning = true);

    final result = await TextRecognitionService.instance.recognizeFromFile(
      path,
    );

    if (!mounted) return;

    setState(() {
      _isScanning = false;
      _ocrResult = result;
      if (result == null) {
        _errorMessage = 'Nessun testo trovato nell\'immagine';
      } else {
        // Select all blocks by default
        _selectedBlocks.addAll(List.generate(result.blocks.length, (i) => i));
      }
    });

    HapticFeedback.mediumImpact();
  }

  void _importMerged() {
    if (_ocrResult == null) return;

    // Get text from selected blocks only
    final selectedText = _ocrResult!.blocks
        .asMap()
        .entries
        .where((e) => _selectedBlocks.contains(e.key))
        .map((e) => e.value.text)
        .join('\n\n');

    if (selectedText.trim().isEmpty) return;

    Navigator.pop(
      context,
      OcrDialogResult(
        mergeAll: true,
        fullText: selectedText,
        imageWidth: _ocrResult!.imageWidth,
        imageHeight: _ocrResult!.imageHeight,
      ),
    );
  }

  void _importBlocks() {
    if (_ocrResult == null) return;

    final selectedBlocks =
        _ocrResult!.blocks
            .asMap()
            .entries
            .where((e) => _selectedBlocks.contains(e.key))
            .map((e) => e.value)
            .toList();

    if (selectedBlocks.isEmpty) return;

    Navigator.pop(
      context,
      OcrDialogResult(
        mergeAll: false,
        blocks: selectedBlocks,
        imageWidth: _ocrResult!.imageWidth,
        imageHeight: _ocrResult!.imageHeight,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 500,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: Row(
                children: [
                  Icon(
                    Icons.document_scanner_rounded,
                    color: cs.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Scansione Testo',
                    style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            const Divider(),

            // ── Content ──
            Flexible(child: _buildContent(cs, tt)),

            // ── Actions ──
            if (_ocrResult != null) ...[
              const Divider(height: 1),
              _buildActions(cs, tt),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ColorScheme cs, TextTheme tt) {
    if (_imagePath == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(48),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_isScanning) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 32),
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'Riconoscimento testo in corso...',
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 32),
        ],
      );
    }

    if (_errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.text_fields_rounded,
              size: 64,
              color: cs.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.tonal(
              onPressed: _pickImage,
              child: const Text('Prova un\'altra immagine'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Image Preview with overlay ──
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                Image.file(
                  File(_imagePath!),
                  fit: BoxFit.contain,
                  width: double.infinity,
                ),
                if (_showOverlay && _ocrResult != null)
                  Positioned.fill(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return CustomPaint(
                          painter: _OcrOverlayPainter(
                            blocks: _ocrResult!.blocks,
                            selectedIndices: _selectedBlocks,
                            imageWidth: _ocrResult!.imageWidth,
                            imageHeight: _ocrResult!.imageHeight,
                            viewWidth: constraints.maxWidth,
                            viewHeight: constraints.maxHeight,
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Toggle overlay ──
          Row(
            children: [
              Icon(Icons.layers_rounded, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                'Mostra blocchi rilevati',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const Spacer(),
              Switch(
                value: _showOverlay,
                onChanged: (v) => setState(() => _showOverlay = v),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // ── Text blocks list ──
          Text(
            'Testo riconosciuto (${_ocrResult!.blocks.length} blocchi)',
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),

          ...List.generate(_ocrResult!.blocks.length, (i) {
            final block = _ocrResult!.blocks[i];
            final isSelected = _selectedBlocks.contains(i);

            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _selectedBlocks.remove(i);
                    } else {
                      _selectedBlocks.add(i);
                    }
                  });
                  HapticFeedback.selectionClick();
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:
                        isSelected
                            ? cs.primaryContainer.withValues(alpha: 0.5)
                            : cs.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? cs.primary : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSelected
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                        color: isSelected ? cs.primary : cs.onSurfaceVariant,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          block.text,
                          style: tt.bodyMedium?.copyWith(color: cs.onSurface),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),

          // ── Try another image ──
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.photo_library_rounded),
              label: const Text('Altra immagine'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(ColorScheme cs, TextTheme tt) {
    final selectedCount = _selectedBlocks.length;
    final totalCount = _ocrResult?.blocks.length ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        children: [
          // ── Select all / none ──
          Row(
            children: [
              Text(
                '$selectedCount/$totalCount selezionati',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  setState(() {
                    if (_selectedBlocks.length == totalCount) {
                      _selectedBlocks.clear();
                    } else {
                      _selectedBlocks.addAll(
                        List.generate(totalCount, (i) => i),
                      );
                    }
                  });
                },
                child: Text(
                  _selectedBlocks.length == totalCount
                      ? 'Deseleziona tutto'
                      : 'Seleziona tutto',
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // ── Import buttons ──
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: selectedCount > 0 ? _importBlocks : null,
                  icon: const Icon(Icons.view_module_rounded, size: 18),
                  label: const Text('Blocchi separati'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: selectedCount > 0 ? _importMerged : null,
                  icon: const Icon(Icons.text_snippet_rounded, size: 18),
                  label: const Text('Testo unito'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Overlay Painter — draws bounding boxes on the image preview
// ──────────────────────────────────────────────────────────────────────────────

class _OcrOverlayPainter extends CustomPainter {
  final List<OcrTextBlock> blocks;
  final Set<int> selectedIndices;
  final int imageWidth;
  final int imageHeight;
  final double viewWidth;
  final double viewHeight;

  _OcrOverlayPainter({
    required this.blocks,
    required this.selectedIndices,
    required this.imageWidth,
    required this.imageHeight,
    required this.viewWidth,
    required this.viewHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (imageWidth == 0 || imageHeight == 0) return;

    // Compute scale (image is fitted with BoxFit.contain)
    final scaleX = viewWidth / imageWidth;
    final scaleY = viewHeight / imageHeight;
    final scale = scaleX < scaleY ? scaleX : scaleY;
    final offsetX = (viewWidth - imageWidth * scale) / 2;
    final offsetY = (viewHeight - imageHeight * scale) / 2;

    for (int i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      final isSelected = selectedIndices.contains(i);

      final rect = Rect.fromLTRB(
        block.boundingBox.left * scale + offsetX,
        block.boundingBox.top * scale + offsetY,
        block.boundingBox.right * scale + offsetX,
        block.boundingBox.bottom * scale + offsetY,
      );

      // Fill
      final fillPaint =
          Paint()
            ..color =
                isSelected ? const Color(0x3300AA55) : const Color(0x22FF6600)
            ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        fillPaint,
      );

      // Border
      final borderPaint =
          Paint()
            ..color =
                isSelected ? const Color(0xCC00AA55) : const Color(0x88FF6600)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        borderPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_OcrOverlayPainter old) =>
      old.selectedIndices != selectedIndices || old.blocks != blocks;
}
