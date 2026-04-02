part of '../fluera_canvas_screen.dart';

/// 🧮 LaTeX Recognition Handler — converts lasso-selected strokes to LatexNode.
///
/// Flow:
/// 1. Collect selected ProStrokes from active layer
/// 2. Convert to InkData → rasterize via InkRasterizer
/// 3. Recognize via Pix2TexRecognizer
/// 4. Show confirmation dialog with preview
/// 5. On confirm: delete strokes + insert LatexNode at same position
extension FlueraCanvasLatexRecognitionHandler on _FlueraCanvasScreenState {
  /// Convert the current lasso selection to a LatexNode via OCR recognition.
  Future<void> _convertSelectionToLatex() async {
    try {
      if (!_lassoTool.hasSelection) {
        return;
      }

      // 1. Collect selected strokes
      final layer = _layerController.activeLayer;
      if (layer == null) {
        return;
      }

      final selectedStrokes = <ProStroke>[];
      for (final stroke in layer.strokes) {
        if (_lassoTool.selectedIds.contains(stroke.id)) {
          selectedStrokes.add(stroke);
        }
      }

      if (selectedStrokes.isEmpty) {
        return;
      }

      // 2. Convert ProStroke → InkData
      final inkStrokes =
          selectedStrokes.map((s) {
            final inkPoints =
                s.points.map((p) {
                  return InkPoint(
                    x: p.position.dx,
                    y: p.position.dy,
                    pressure: p.pressure,
                    timestamp: p.timestamp,
                  );
                }).toList();
            return InkStroke(inkPoints);
          }).toList();

      final inkData = InkData(inkStrokes);

      // 3. Rasterize to PNG
      final png = await InkRasterizer.rasterize(
        inkData,
        width: 512,
        height: 128,
      );
      if (png == null || !mounted) {
        return;
      }

      // DEBUG: Save rasterized image to inspect what the model sees
      try {
        final dir = await getSafeDocumentsDirectory();
        if (dir == null) return; // Web: no filesystem
        final debugFile = File('${dir.path}/hme_debug_input.png');
        await debugFile.writeAsBytes(png);
      } catch (_) {}

      // 4. Recognize via MyScript + HME dual-backend
      if (FlueraCanvasLatexHandler._latexRecognizer == null) {
        FlueraCanvasLatexHandler._latexRecognizer = MyScriptLatexBridge();
        await FlueraCanvasLatexHandler._latexRecognizer!.initialize();
      }
      final recognizer = FlueraCanvasLatexHandler._latexRecognizer!;
      if (!mounted) return;

      // Show loading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 12),
              Text('Riconoscimento formula...'),
            ],
          ),
          duration: Duration(seconds: 30),
        ),
      );

      final result = await recognizer.recognizeImage(png);

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (result.latexString.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nessuna formula riconosciuta'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }

      // 5. Show confirmation dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder:
            (ctx) => _LatexRecognitionDialog(
              latexSource: result.latexString,
              confidence: result.confidence,
              alternatives: result.alternatives,
              imageBytes: png,
            ),
      );

      if (confirmed != true || !mounted) return;

      // 6. Get selection bounds before deleting
      final bounds = _lassoTool.getSelectionBounds();
      final center = bounds?.center ?? Offset.zero;

      // 7. Delete selected strokes
      _lassoTool.deleteSelected();
      setState(() {});

      // 8. Create LatexNode at selection center
      final node = LatexNode(
        id: NodeId(generateUid()),
        latexSource: result.latexString,
        fontSize: 24.0,
        color: _effectiveSelectedColor,
      );

      node.localTransform.setTranslationRaw(center.dx, center.dy, 0);

      final rootGroup = _layerController.sceneGraph.rootNode;
      _commandHistory.execute(
        AddLatexNodeCommand(parent: rootGroup, latexNode: node),
      );

      _layerController.sceneGraph.bumpVersion();
      setState(() {});
      _autoSaveCanvas();

      HapticFeedback.heavyImpact();
    } catch (e, st) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore: $e'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  /// Build the floating "Convert to LaTeX" button above the selection.
  Widget _buildConvertToLatexFab() {
    final layer = _layerController.activeLayer;
    if (layer == null) return const SizedBox.shrink();

    // Check if selection contains any strokes
    final hasStrokes = layer.strokes.any(
      (s) => _lassoTool.selectedIds.contains(s.id),
    );
    if (!hasStrokes) return const SizedBox.shrink();

    // Calculate selection bounding rect in screen coordinates
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity;
    for (final stroke in layer.strokes) {
      if (!_lassoTool.selectedIds.contains(stroke.id)) continue;
      for (final p in stroke.points) {
        final sp = _canvasController.canvasToScreen(p.position);
        if (sp.dx < minX) minX = sp.dx;
        if (sp.dy < minY) minY = sp.dy;
        if (sp.dx > maxX) maxX = sp.dx;
      }
    }

    if (!minX.isFinite || !minY.isFinite) return const SizedBox.shrink();

    final centerX = (minX + maxX) / 2;
    final fabTop = (minY - 52).clamp(8.0, 9999.0);

    return Positioned(
      left: centerX - 20,
      top: fabTop,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(16),
        color: Colors.teal,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _convertSelectionToLatex,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.functions_rounded, color: Colors.white, size: 20),
                SizedBox(width: 4),
                Text(
                  'LaTeX',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Confirmation dialog
// =============================================================================

class _LatexRecognitionDialog extends StatefulWidget {
  final String latexSource;
  final double confidence;
  final List<LatexAlternative> alternatives;
  final Uint8List imageBytes;

  const _LatexRecognitionDialog({
    required this.latexSource,
    required this.confidence,
    required this.alternatives,
    required this.imageBytes,
  });

  @override
  State<_LatexRecognitionDialog> createState() =>
      _LatexRecognitionDialogState();
}

class _LatexRecognitionDialogState extends State<_LatexRecognitionDialog> {
  late String _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.latexSource;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.functions_rounded, size: 24),
          SizedBox(width: 8),
          Text('Formula riconosciuta'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image preview
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                widget.imageBytes,
                height: 80,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 12),

            // LaTeX preview
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: LatexPreviewCard(
                latexSource: _selected,
                fontSize: 20,
                color: cs.onSurface,
                minHeight: 40,
              ),
            ),
            const SizedBox(height: 8),

            // Confidence badge
            Row(
              children: [
                Icon(
                  Icons.verified_rounded,
                  size: 16,
                  color: widget.confidence > 0.8 ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 4),
                Text(
                  'Confidenza: ${(widget.confidence * 100).toStringAsFixed(0)}%',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),

            // Alternative chips
            if (widget.alternatives.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children:
                    widget.alternatives.map((alt) {
                      final isSelected = alt.latexString == _selected;
                      return ChoiceChip(
                        label: Text(
                          alt.latexString,
                          style: const TextStyle(fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        selected: isSelected,
                        onSelected: (_) {
                          setState(() => _selected = alt.latexString);
                        },
                      );
                    }).toList(),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Conferma'),
        ),
      ],
    );
  }
}
