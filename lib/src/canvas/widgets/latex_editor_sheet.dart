import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/latex/ink_stroke_data.dart';
import '../../core/latex/latex_fuzzy_corrector.dart';
import '../../core/latex/latex_validator.dart';
import '../../core/latex/latex_evaluator.dart';
import '../../core/latex/latex_confidence_annotator.dart';
import '../../platform/latex_recognition_bridge.dart';
import 'latex_command_reference.dart';
import 'latex_preview_card.dart';
import 'latex_ink_overlay.dart';
import 'latex_symbol_palette.dart';
import 'latex_confidence_chips.dart';
import 'latex_function_graph.dart';
import 'latex_syntax_highlighting.dart';

part '_latex_editor_widgets.dart';

/// 🧮 LatexEditorSheet — Enterprise-grade Material Design 3 bottom sheet for
/// creating and editing LaTeX mathematical expressions.
///
/// ## Enterprise Features
/// - **E1** Debounced live preview (300ms)
/// - **E2** Local undo/redo stack with toolbar buttons
/// - **E3** Expression history (last 10 confirmed expressions)
/// - **E4** Expanded quick-insert (3 rows: structures, environments, functions)
/// - **E5** Template library (12 pre-built expressions)
/// - **E6** Haptic feedback on all interactions
/// - **E7** Scrollable validation bar with tap-to-navigate
/// - **E8** Font size slider (10–96) with exact-value display
///
/// ## Modes
/// - `LatexEditorMode.keyboard`: traditional text input
/// - `LatexEditorMode.handwriting`: stylus/touch ink recognition
/// - `LatexEditorMode.symbols`: symbol palette insertion
class LatexEditorSheet extends StatefulWidget {
  /// Initial LaTeX source (for editing existing nodes).
  final String initialLatex;

  /// Initial font size.
  final double initialFontSize;

  /// Initial color.
  final Color initialColor;

  /// ML recognition bridge (can be [MockLatexRecognizer] for testing).
  final LatexRecognitionBridge? recognizer;

  /// Called when the user confirms the expression.
  final void Function(String latex, double fontSize, Color color)? onConfirm;

  /// Called when the user cancels.
  final VoidCallback? onCancel;

  const LatexEditorSheet({
    super.key,
    this.initialLatex = '',
    this.initialFontSize = 24.0,
    this.initialColor = Colors.white,
    this.recognizer,
    this.onConfirm,
    this.onCancel,
    this.onInsertGraphToCanvas,
  });

  /// Called when user inserts graph to canvas from the graph sheet.
  final void Function(String latexSource, double xMin, double xMax, double yMin, double yMax, int curveColor)? onInsertGraphToCanvas;

  @override
  State<LatexEditorSheet> createState() => _LatexEditorSheetState();
}

class _LatexEditorSheetState extends State<LatexEditorSheet>
    with TickerProviderStateMixin {
  // T1: Syntax highlighting controller
  late LatexHighlightingController _sourceController;
  late double _fontSize;
  late Color _color;
  LatexEditorMode _mode = LatexEditorMode.keyboard;

  bool _isRecognizing = false;
  /// Incremented to signal the ink overlay to clear its strokes.
  final ValueNotifier<int> _inkClearSignal = ValueNotifier(0);
  List<ConfidenceAnnotation> _confidenceAnnotations = [];
  List<LatexValidationError> _validationErrors = [];

  late final TabController _tabController;

  // ── E1: Debounced validation ──
  Timer? _validationDebounce;

  // ── E2: Local undo/redo stack ──
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];
  String _lastSnapshotText = '';
  Timer? _undoDebounce;

  // ── P3: Evaluation state ──
  double? _evaluationResult;
  String? _evaluationError;

  // ── E3: Expression history ──
  static final List<String> _expressionHistory = [];

  // ── U5: Expression favorites ──
  static final List<String> _expressionFavorites = [];

  // ── E5: Template expanded flag ──
  bool _showTemplates = false;

  // ── Camera OCR state ──
  Uint8List? _cameraImageBytes;
  bool _isCameraRecognizing = false;
  double _cameraConfidence = 0.0;
  List<LatexAlternative> _cameraAlternatives = [];

  // ── T2: Autocomplete state ──
  List<LatexCommandEntry> _autocompleteSuggestions = [];
  String _autocompletePrefix = '';
  final FocusNode _editorFocusNode = FocusNode();

  // ── New UX state fields ──
  bool _previewCollapsed = false;
  bool _wasKeyboardOpen = false;
  final List<String> _recentCommands = [];
  // P4: Font size slider toggle
  bool _showFontSlider = false;

  @override
  void initState() {
    super.initState();
    // T1: Use syntax highlighting controller
    _sourceController = LatexHighlightingController(text: widget.initialLatex);
    _fontSize = widget.initialFontSize;
    _color = widget.initialColor;
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      HapticFeedback.selectionClick(); // E6
      setState(() {
        _mode = LatexEditorMode.values[_tabController.index];
      });
    });
    _sourceController.addListener(_onSourceChanged);
    _lastSnapshotText = widget.initialLatex;
    _undoStack.add(widget.initialLatex);

    // U1: Tab-through placeholders handler
    _editorFocusNode.onKeyEvent = _handleKeyEvent;
  }

  // U1: Tab key handler — jumps to next empty {} pair
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.tab) {
      final text = _sourceController.text;
      final cursor =
          _sourceController.selection.isValid
              ? _sourceController.selection.baseOffset
              : 0;

      // Find next '{}' after cursor
      final nextPlaceholder = text.indexOf('{}', cursor);
      if (nextPlaceholder >= 0) {
        _sourceController.selection = TextSelection.collapsed(
          offset: nextPlaceholder + 1,
        );
        HapticFeedback.selectionClick();
        return KeyEventResult.handled;
      }

      // Wrap around: search from beginning
      if (cursor > 0) {
        final wrapPlaceholder = text.indexOf('{}');
        if (wrapPlaceholder >= 0) {
          _sourceController.selection = TextSelection.collapsed(
            offset: wrapPlaceholder + 1,
          );
          HapticFeedback.selectionClick();
          return KeyEventResult.handled;
        }
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _validationDebounce?.cancel();
    _undoDebounce?.cancel();
    _editorFocusNode.dispose();
    _sourceController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // ── E1: Debounced validation ──
  void _onSourceChanged() {
    _validationDebounce?.cancel();
    _validationDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _validationErrors = LatexValidator.validate(_sourceController.text);
      });
    });

    // E2: Snapshot for undo after 500ms of no typing
    _undoDebounce?.cancel();
    _undoDebounce = Timer(const Duration(milliseconds: 500), () {
      _pushUndoSnapshot();
    });

    // T2: Update autocomplete suggestions
    _updateAutocompleteSuggestions();

    // P3: Live evaluation
    final src = _sourceController.text.trim();
    if (src.isNotEmpty && !src.contains('x')) {
      try {
        _evaluationResult = LatexEvaluator.evaluate(src);
        _evaluationError = null;
      } catch (e) {
        _evaluationResult = null;
        _evaluationError = e.toString().replaceFirst('Exception: ', '');
      }
    } else {
      _evaluationResult = null;
      _evaluationError = null;
    }

    // Trigger rebuild for preview (immediate, lightweight)
    setState(() {});
  }

  // ── T2: Autocomplete logic ──
  void _updateAutocompleteSuggestions() {
    final text = _sourceController.text;
    final sel = _sourceController.selection;
    if (!sel.isValid || !sel.isCollapsed) {
      if (_autocompleteSuggestions.isNotEmpty) {
        setState(() {
          _autocompleteSuggestions = [];
          _autocompletePrefix = '';
        });
      }
      return;
    }

    final cursor = sel.baseOffset;
    // Scan backwards from cursor to find '\' + letters
    int cmdStart = cursor;
    while (cmdStart > 0 && _isLatexLetter(text.codeUnitAt(cmdStart - 1))) {
      cmdStart--;
    }
    if (cmdStart > 0 && text[cmdStart - 1] == '\\') {
      cmdStart--; // include the backslash
    } else {
      if (_autocompleteSuggestions.isNotEmpty) {
        setState(() {
          _autocompleteSuggestions = [];
          _autocompletePrefix = '';
        });
      }
      return;
    }

    final prefix = text.substring(cmdStart, cursor);
    if (prefix.length < 2) {
      // Need at least '\' + one char
      if (_autocompleteSuggestions.isNotEmpty) {
        setState(() {
          _autocompleteSuggestions = [];
          _autocompletePrefix = '';
        });
      }
      return;
    }

    final query = prefix.toLowerCase();
    final matches =
        latexCommandDatabase
            .where((e) => e.command.toLowerCase().startsWith(query))
            .take(6)
            .toList();

    // Don't show if exact match only
    if (matches.length == 1 && matches.first.command == prefix) {
      matches.clear();
    }

    setState(() {
      _autocompleteSuggestions = matches;
      _autocompletePrefix = prefix;
    });
  }

  static bool _isLatexLetter(int codeUnit) =>
      (codeUnit >= 65 && codeUnit <= 90) || (codeUnit >= 97 && codeUnit <= 122);

  void _acceptAutocomplete(LatexCommandEntry entry) {
    HapticFeedback.selectionClick();
    final text = _sourceController.text;
    final sel = _sourceController.selection;
    final cursor = sel.baseOffset;
    final prefixLen = _autocompletePrefix.length;
    final cmdStart = cursor - prefixLen;

    // Replace the partial command with the full insert text
    final insertText = entry.insertText;
    final newText = text.replaceRange(cmdStart, cursor, insertText);

    _sourceController.removeListener(_onSourceChanged);
    _sourceController.text = newText;

    // T4: Smart cursor — place inside first {} if present
    final insertEnd = cmdStart + insertText.length;
    final firstBraceOpen = insertText.indexOf('{}');
    if (firstBraceOpen >= 0) {
      _sourceController.selection = TextSelection.collapsed(
        offset: cmdStart + firstBraceOpen + 1,
      );
    } else {
      _sourceController.selection = TextSelection.collapsed(offset: insertEnd);
    }

    _sourceController.addListener(_onSourceChanged);
    setState(() {
      _autocompleteSuggestions = [];
      _autocompletePrefix = '';
    });
    _pushUndoSnapshot();
  }

  // ── E2: Undo/Redo helpers ──
  void _pushUndoSnapshot() {
    final text = _sourceController.text;
    if (text == _lastSnapshotText) return;
    _undoStack.add(text);
    _redoStack.clear();
    _lastSnapshotText = text;
    // Cap at 50 entries
    if (_undoStack.length > 50) _undoStack.removeAt(0);
  }

  void _undo() {
    if (_undoStack.length <= 1) return;
    HapticFeedback.lightImpact(); // E6
    _redoStack.add(_undoStack.removeLast());
    final prev = _undoStack.last;
    _lastSnapshotText = prev;
    _sourceController.removeListener(_onSourceChanged);
    _sourceController.text = prev;
    _sourceController.selection = TextSelection.collapsed(offset: prev.length);
    _sourceController.addListener(_onSourceChanged);
    setState(() {
      _validationErrors = LatexValidator.validate(prev);
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    HapticFeedback.lightImpact(); // E6
    final next = _redoStack.removeLast();
    _undoStack.add(next);
    _lastSnapshotText = next;
    _sourceController.removeListener(_onSourceChanged);
    _sourceController.text = next;
    _sourceController.selection = TextSelection.collapsed(offset: next.length);
    _sourceController.addListener(_onSourceChanged);
    setState(() {
      _validationErrors = LatexValidator.validate(next);
    });
  }

  Future<void> _handleStrokesComplete(InkData inkData) async {
    if (widget.recognizer == null) return;
    if (_isRecognizing) return;

    setState(() => _isRecognizing = true);

    try {
      final result = await widget.recognizer!.recognize(inkData);

      // Apply fuzzy correction
      final corrected = LatexFuzzyCorrector.correct(result.latexString);

      // Compute confidence annotations
      final annotations = LatexConfidenceAnnotator.annotate(
        corrected,
        result.perSymbolConfidence,
      );

      setState(() {
        _sourceController.text = corrected;
        _sourceController.selection = TextSelection.collapsed(
          offset: corrected.length,
        );
        _confidenceAnnotations = annotations;
        _isRecognizing = false;
      });
      // Signal the ink overlay to clear its strokes — prevents
      // re-sending old strokes on the next auto-recognize cycle.
      _inkClearSignal.value++;
      _pushUndoSnapshot();
    } on LatexRecognitionException catch (e) {
      setState(() => _isRecognizing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Riconoscimento fallito: ${e.message}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // U2: Wrap selection + T4: Smart cursor positioning
  void _insertSymbol(String latex) {
    HapticFeedback.selectionClick(); // E6
    final text = _sourceController.text;
    final sel = _sourceController.selection;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;

    // U2: If there's a selection and the template has {}, wrap selected text
    if (start != end && latex.contains('{}')) {
      final selectedText = text.substring(start, end);
      // Replace first {} with {selectedText}
      final wrappedLatex = latex.replaceFirst('{}', '{$selectedText}');
      final newText = text.replaceRange(start, end, wrappedLatex);
      _sourceController.text = newText;

      // Place cursor after the wrapped content or inside next {}
      final insertedEnd = start + wrappedLatex.length;
      final secondBrace = wrappedLatex.indexOf('{}', selectedText.length + 2);
      if (secondBrace >= 0) {
        _sourceController.selection = TextSelection.collapsed(
          offset: start + secondBrace + 1,
        );
      } else {
        _sourceController.selection = TextSelection.collapsed(
          offset: insertedEnd,
        );
      }
    } else {
      // Normal insert (no selection)
      final newText = text.replaceRange(start, end, latex);
      _sourceController.text = newText;

      // T4: Smart cursor — find first {} and place cursor inside
      final firstBraceOpen = latex.indexOf('{}');
      if (firstBraceOpen >= 0) {
        _sourceController.selection = TextSelection.collapsed(
          offset: start + firstBraceOpen + 1,
        );
      } else {
        _sourceController.selection = TextSelection.collapsed(
          offset: start + latex.length,
        );
      }
    }
    _pushUndoSnapshot();
  }

  void _confirm() {
    HapticFeedback.mediumImpact(); // E6
    final source = _sourceController.text;

    // E3: Add to expression history
    if (source.trim().isNotEmpty) {
      _expressionHistory.remove(source);
      _expressionHistory.insert(0, source);
      if (_expressionHistory.length > 10) {
        _expressionHistory.removeLast();
      }
    }

    widget.onConfirm?.call(source, _fontSize, _color);
  }

  /// Insert text at cursor position, preserving focus.
  void _insertAtCursor(String text) {
    final sel = _sourceController.selection;
    final src = _sourceController.text;
    final pos = sel.isValid ? sel.baseOffset : src.length;
    final newText = src.substring(0, pos) + text + src.substring(pos);
    _sourceController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: pos + text.length),
    );
  }

  /// Move cursor left or right by [delta] characters.
  void _moveCursor(int delta) {
    final sel = _sourceController.selection;
    if (!sel.isValid) return;
    final newPos = (sel.baseOffset + delta).clamp(
      0,
      _sourceController.text.length,
    );
    _sourceController.selection = TextSelection.collapsed(offset: newPos);
  }

  /// Open the command reference screen with insert-at-cursor callback.
  void _openCommandReference() {
    LatexCommandReference.show(
      context,
      onCommandSelected: (cmd) => _insertAtCursor(cmd),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Editor LaTeX'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed:
              () => (widget.onCancel ?? () => Navigator.of(context).pop())(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo_rounded),
            tooltip: 'Annulla',
            onPressed: _undoStack.isNotEmpty ? _undo : null,
          ),
          IconButton(
            icon: const Icon(Icons.redo_rounded),
            tooltip: 'Ripeti',
            onPressed: _redoStack.isNotEmpty ? _redo : null,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (val) {
              switch (val) {
                case 'history':
                  _showHistorySheet();
                case 'templates':
                  _showTemplateSheet();
                case 'graph':
                  _showGraphSheet();
                case 'palette':
                  _showCommandPalette();
              }
            },
            itemBuilder:
                (_) => [
                  const PopupMenuItem(
                    value: 'history',
                    child: ListTile(
                      leading: Icon(Icons.history_rounded),
                      title: Text('Cronologia'),
                      dense: true,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'templates',
                    child: ListTile(
                      leading: Icon(Icons.grid_view_rounded),
                      title: Text('Modelli'),
                      dense: true,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'graph',
                    child: ListTile(
                      leading: Icon(Icons.show_chart_rounded),
                      title: Text('Grafico'),
                      dense: true,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'palette',
                    child: ListTile(
                      leading: Icon(Icons.terminal_rounded),
                      title: Text('Comandi'),
                      dense: true,
                    ),
                  ),
                ],
          ),
        ],
      ),
      body: Builder(
        builder: (ctx) {
          final kbOpen = MediaQuery.of(ctx).viewInsets.bottom > 80;
          if (kbOpen && !_wasKeyboardOpen) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _previewCollapsed = true);
            });
          }
          _wasKeyboardOpen = kbOpen;
          return Shortcuts(
            shortcuts: <ShortcutActivator, Intent>{
              const SingleActivator(LogicalKeyboardKey.enter, control: true):
                  const _ConfirmIntent(),
              const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                  const _ConfirmIntent(),
              const SingleActivator(
                    LogicalKeyboardKey.keyZ,
                    control: true,
                    shift: true,
                  ):
                  const _RedoIntent(),
              const SingleActivator(
                    LogicalKeyboardKey.keyZ,
                    meta: true,
                    shift: true,
                  ):
                  const _RedoIntent(),
              const SingleActivator(LogicalKeyboardKey.escape):
                  const _CancelIntent(),
            },
            child: Actions(
              actions: <Type, Action<Intent>>{
                _ConfirmIntent: CallbackAction<_ConfirmIntent>(
                  onInvoke: (_) {
                    if (_sourceController.text.isNotEmpty) _confirm();
                    return null;
                  },
                ),
                _RedoIntent: CallbackAction<_RedoIntent>(
                  onInvoke: (_) {
                    _redo();
                    return null;
                  },
                ),
                _CancelIntent: CallbackAction<_CancelIntent>(
                  onInvoke: (_) {
                    (widget.onCancel ?? () => Navigator.of(context).pop())();
                    return null;
                  },
                ),
              },
              child: Column(
                children: [
                  if (isLandscape)
                    Expanded(child: _buildLandscapeLayout(cs))
                  else
                    Expanded(child: _buildPortraitLayout(cs)),

                  _buildToolbar(cs),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _sourceController.text.isNotEmpty ? _confirm : null,
        backgroundColor:
            _sourceController.text.isNotEmpty
                ? cs.primary
                : cs.surfaceContainerHighest,
        child: Icon(
          Icons.check_rounded,
          color:
              _sourceController.text.isNotEmpty
                  ? cs.onPrimary
                  : cs.onSurfaceVariant,
        ),
      ),
    );
  }

  // ── E9: Landscape — side-by-side ──
  Widget _buildLandscapeLayout(ColorScheme cs) {
    return Row(
      children: [
        // Left: preview + validation
        Expanded(
          flex: 2,
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: LatexPreviewCard(
                    latexSource: _sourceController.text,
                    fontSize: _fontSize,
                    color: _color,
                    minHeight: 120,
                  ),
                ),
              ),
              if (_validationErrors.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                  child: _buildValidationBar(cs),
                ),
              if (_confidenceAnnotations.isNotEmpty)
                LatexConfidenceChips(
                  annotations: _confidenceAnnotations,
                  onChipTapped: (ann) {
                    _sourceController.selection = TextSelection(
                      baseOffset: ann.startIndex,
                      extentOffset: ann.endIndex,
                    );
                  },
                ),
            ],
          ),
        ),
        // Right: editor
        Expanded(
          flex: 3,
          child: Column(
            children: [
              _buildTabBar(cs),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  physics:
                      _tabController.index == 1
                          ? const NeverScrollableScrollPhysics()
                          : null,
                  children: [
                    _buildKeyboardMode(cs),
                    _buildHandwritingMode(cs),
                    _buildSymbolsMode(),
                    _buildCameraMode(cs),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Portrait — stacked with collapsible preview
  Widget _buildPortraitLayout(ColorScheme cs) {
    return GestureDetector(
      onVerticalDragUpdate: (d) {
        if (d.delta.dy > 6) {
          FocusScope.of(context).unfocus();
        }
      },
      child: Column(
        children: [
          // Collapsible preview
          GestureDetector(
            onTap: () => setState(() => _previewCollapsed = !_previewCollapsed),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              child:
                  _previewCollapsed
                      ? Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.expand_more_rounded,
                              size: 18,
                              color: cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Anteprima',
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      )
                      : Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: GestureDetector(
                          onLongPress: () {
                            final src = _sourceController.text;
                            if (src.isNotEmpty) {
                              Clipboard.setData(ClipboardData(text: src));
                              HapticFeedback.mediumImpact();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text('LaTeX copiato'),
                                  behavior: SnackBarBehavior.floating,
                                  duration: const Duration(seconds: 1),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              );
                            }
                          },
                          child: InteractiveViewer(
                            child: LatexPreviewCard(
                              latexSource: _sourceController.text,
                              fontSize: _fontSize,
                              color: _color,
                              minHeight: 100,
                            ),
                          ),
                        ),
                      ),
            ),
          ),

          // P3: Unified status bar (eval + graph chip + char count)
          _buildUnifiedStatusBar(cs),

          // Validation warnings
          if (_validationErrors.isNotEmpty) _buildValidationBar(cs),

          // Confidence chips
          if (_confidenceAnnotations.isNotEmpty)
            LatexConfidenceChips(
              annotations: _confidenceAnnotations,
              onChipTapped: (ann) {
                _sourceController.selection = TextSelection(
                  baseOffset: ann.startIndex,
                  extentOffset: ann.endIndex,
                );
              },
            ),

          // Tab bar
          _buildTabBar(cs),

          // Mode content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics:
                  _tabController.index == 1
                      ? const NeverScrollableScrollPhysics()
                      : null,
              children: [
                _buildKeyboardMode(cs),
                _buildHandwritingMode(cs),
                _buildSymbolsMode(),
                _buildCameraMode(cs),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Drag Handle
  // ---------------------------------------------------------------------------

  Widget _buildDragHandle(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Container(
        width: 32,
        height: 4,
        decoration: BoxDecoration(
          color: cs.onSurfaceVariant.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header
  // ---------------------------------------------------------------------------

  Widget _buildHeader(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Icon(Icons.functions_rounded, color: cs.primary, size: 24),
          const SizedBox(width: 12),
          Text(
            'Editor LaTeX',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const Spacer(),
          // E2: Undo/Redo buttons
          _HeaderIconButton(
            icon: Icons.undo_rounded,
            tooltip: 'Annulla',
            enabled: _undoStack.length > 1,
            onTap: _undo,
          ),
          _HeaderIconButton(
            icon: Icons.redo_rounded,
            tooltip: 'Ripristina',
            enabled: _redoStack.isNotEmpty,
            onTap: _redo,
          ),
          const SizedBox(width: 4),
          if (_isRecognizing)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: cs.primary,
              ),
            ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: widget.onCancel ?? () => Navigator.of(context).pop(),
            style: IconButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // E7: Scrollable Validation Bar with tap-to-navigate
  // ---------------------------------------------------------------------------

  Widget _buildValidationBar(ColorScheme cs) {
    final errorCount =
        _validationErrors
            .where((e) => e.severity == ValidationSeverity.error)
            .length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color:
            errorCount > 0
                ? cs.errorContainer.withValues(alpha: 0.7)
                : cs.tertiaryContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Summary row with count
          Row(
            children: [
              Icon(
                errorCount > 0
                    ? Icons.error_outline_rounded
                    : Icons.warning_amber_rounded,
                size: 16,
                color:
                    errorCount > 0
                        ? cs.onErrorContainer
                        : cs.onTertiaryContainer,
              ),
              const SizedBox(width: 8),
              Text(
                '${_validationErrors.length} ${_validationErrors.length == 1 ? "problema" : "problemi"}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color:
                      errorCount > 0
                          ? cs.onErrorContainer
                          : cs.onTertiaryContainer,
                ),
              ),
            ],
          ),
          // Scrollable error list (max 3 visible)
          if (_validationErrors.length > 1) const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 60),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _validationErrors.length,
              itemBuilder: (context, i) {
                final err = _validationErrors[i];
                return GestureDetector(
                  onTap: () {
                    // Navigate cursor to error position
                    HapticFeedback.selectionClick();
                    final pos = err.position.clamp(
                      0,
                      _sourceController.text.length,
                    );
                    _sourceController.selection = TextSelection.collapsed(
                      offset: pos,
                    );
                    // Switch to keyboard mode to show cursor
                    if (_mode != LatexEditorMode.keyboard) {
                      _tabController.animateTo(0);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Row(
                      children: [
                        Icon(
                          err.severity == ValidationSeverity.error
                              ? Icons.circle
                              : Icons.circle_outlined,
                          size: 6,
                          color:
                              errorCount > 0
                                  ? cs.onErrorContainer
                                  : cs.onTertiaryContainer,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            err.message,
                            style: TextStyle(
                              fontSize: 11,
                              color:
                                  errorCount > 0
                                      ? cs.onErrorContainer
                                      : cs.onTertiaryContainer,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          'pos ${err.position}',
                          style: TextStyle(
                            fontSize: 9,
                            color: (errorCount > 0
                                    ? cs.onErrorContainer
                                    : cs.onTertiaryContainer)
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab Bar
  // ---------------------------------------------------------------------------

  Widget _buildTabBar(ColorScheme cs) {
    return TabBar(
      controller: _tabController,
      labelColor: cs.primary,
      unselectedLabelColor: cs.onSurfaceVariant,
      indicatorColor: cs.primary,
      indicatorSize: TabBarIndicatorSize.label,
      dividerHeight: 0.5,
      labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      tabs: const [
        Tab(icon: Icon(Icons.keyboard_rounded, size: 18), text: 'Tastiera'),
        Tab(icon: Icon(Icons.draw_rounded, size: 18), text: 'Scrittura'),
        Tab(icon: Icon(Icons.grid_view_rounded, size: 18), text: 'Simboli'),
        Tab(icon: Icon(Icons.camera_alt_rounded, size: 18), text: 'Camera'),
      ],
    );
  }

  // ── Compact status bar ──
  // P3: Unified status bar — eval result + graph chip + validation badge + char count
  Widget _buildUnifiedStatusBar(ColorScheme cs) {
    final src = _sourceController.text;
    final len = src.length;
    final errCount = _validationErrors.length;
    final containsX = src.contains('x');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        children: [
          // Evaluation result
          if (_evaluationResult != null && errCount == 0)
            Expanded(
              child: GestureDetector(
                onTap: () {
                  final formatted = LatexEvaluator.formatResult(_evaluationResult!);
                  Clipboard.setData(ClipboardData(text: formatted));
                  HapticFeedback.selectionClick();
                },
                child: Text(
                  '= ${LatexEvaluator.formatResult(_evaluationResult!)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.primary,
                    fontFamily: 'monospace',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
          else if (_evaluationError != null)
            Expanded(
              child: Text(
                _evaluationError!,
                style: TextStyle(fontSize: 11, color: cs.error, fontStyle: FontStyle.italic),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            )
          else
            const Spacer(),

          // P2: Graph chip instead of inline graph
          if (containsX)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                avatar: Icon(Icons.show_chart_rounded, size: 14, color: cs.primary),
                label: Text('f(x)', style: TextStyle(fontSize: 11, color: cs.primary)),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  _showGraphSheet();
                },
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                backgroundColor: cs.primaryContainer.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                side: BorderSide.none,
              ),
            ),

          // Validation badge
          if (errCount > 0) ...[
            Icon(Icons.warning_amber_rounded, size: 14, color: cs.error),
            const SizedBox(width: 2),
            Text('$errCount', style: TextStyle(fontSize: 11, color: cs.error, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
          ],

          // Char count
          if (len > 0)
            Text(
              '$len car.',
              style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
            ),
        ],
      ),
    );
  }

  // ── Track and insert (for quick-insert chips) ──
  void _trackAndInsert(String latex) {
    _recentCommands.remove(latex);
    _recentCommands.insert(0, latex);
    if (_recentCommands.length > 20) _recentCommands.removeLast();
    _insertSymbol(latex);
  }

  // ── History sheet ──
  void _showHistorySheet() {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (_) => DraggableScrollableSheet(
            initialChildSize: 0.5,
            minChildSize: 0.25,
            maxChildSize: 0.85,
            expand: false,
            builder:
                (ctx, sc) => Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Cronologia',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child:
                          _expressionHistory.isEmpty
                              ? Center(
                                child: Text(
                                  'Nessuna espressione recente',
                                  style: TextStyle(color: cs.onSurfaceVariant),
                                ),
                              )
                              : ListView.builder(
                                controller: sc,
                                itemCount: _expressionHistory.length,
                                itemBuilder: (_, i) {
                                  final expr = _expressionHistory[i];
                                  final isFav = _expressionFavorites.contains(
                                    expr,
                                  );
                                  return ListTile(
                                    title: Text(
                                      expr,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 13,
                                      ),
                                    ),
                                    leading: Icon(
                                      isFav
                                          ? Icons.star_rounded
                                          : Icons.history_rounded,
                                      color: isFav ? cs.primary : null,
                                    ),
                                    trailing: IconButton(
                                      icon: Icon(
                                        isFav
                                            ? Icons.star_rounded
                                            : Icons.star_outline_rounded,
                                      ),
                                      onPressed: () {
                                        HapticFeedback.selectionClick();
                                        setState(() {
                                          if (isFav) {
                                            _expressionFavorites.remove(expr);
                                          } else {
                                            _expressionFavorites.insert(
                                              0,
                                              expr,
                                            );
                                          }
                                        });
                                        Navigator.of(ctx).pop();
                                      },
                                    ),
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      _sourceController.text = expr;
                                      _sourceController
                                          .selection = TextSelection.collapsed(
                                        offset: expr.length,
                                      );
                                      _pushUndoSnapshot();
                                      Navigator.of(ctx).pop();
                                    },
                                  );
                                },
                              ),
                    ),
                  ],
                ),
          ),
    );
  }

  // ── Template sheet ──
  void _showTemplateSheet() {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (_) => Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Modelli',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                _buildTemplateGrid(cs),
              ],
            ),
          ),
    );
  }

  // ── Command palette ──
  void _showCommandPalette() {
    _openCommandReference();
  }

  // ── Graph sheet ──
  void _showGraphSheet() {
    final src = _sourceController.text;
    if (src.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Inserisci un\'espressione prima di visualizzare il grafico',
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (_) => SizedBox(
            height: MediaQuery.of(context).size.height * 0.7,
            child: LatexFunctionGraph(
              latexSource: src,
              accentColor: Theme.of(context).colorScheme.primary,
              onInsertToCanvas: widget.onInsertGraphToCanvas,
            ),
          ),
    );
  }

  // ---------------------------------------------------------------------------
  // Mode: Keyboard — simplified editor-first layout
  // ---------------------------------------------------------------------------

  Widget _buildKeyboardMode(ColorScheme cs) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // P1+P5: Paginated quick-insert (with history as page 0)
          _buildPaginatedQuickInsert(cs),

          const SizedBox(height: 12),

          // Text field with autocomplete
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1A1A2E) : const Color(0xFFF5F5FF),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _color.withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                    ),
                    child: TextField(
                      controller: _sourceController,
                      focusNode: _editorFocusNode,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: _fontSize.clamp(16, 28),
                        color: cs.onSurface,
                        height: 1.5,
                        letterSpacing: 0.5,
                      ),
                      decoration: InputDecoration(
                        hintText: r'es. \frac{a}{b} + \sqrt{x}',
                        hintStyle: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 16,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                          fontStyle: FontStyle.italic,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.all(14),
                      ),
                      onChanged: (_) => _pushUndoSnapshot(),
                    ),
                  ),
                ),
                // Live evaluation result badge
                if (_evaluationResult != null || _evaluationError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _evaluationResult != null
                            ? Colors.green.withValues(alpha: isDark ? 0.15 : 0.08)
                            : Colors.red.withValues(alpha: isDark ? 0.15 : 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _evaluationResult != null
                              ? Colors.green.withValues(alpha: 0.3)
                              : Colors.red.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _evaluationResult != null ? Icons.functions_rounded : Icons.error_outline_rounded,
                            size: 14,
                            color: _evaluationResult != null ? Colors.green : Colors.red.shade300,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _evaluationResult != null
                                  ? '= ${_evaluationResult!.toStringAsFixed(_evaluationResult! == _evaluationResult!.roundToDouble() ? 0 : 4)}'
                                  : _evaluationError ?? '',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _evaluationResult != null ? Colors.green : Colors.red.shade300,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // Autocomplete suggestions
                if (_autocompleteSuggestions.isNotEmpty)
                  Container(
                    height: 40,
                    margin: const EdgeInsets.only(top: 4),
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _autocompleteSuggestions.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 4),
                      itemBuilder: (_, i) {
                        final entry = _autocompleteSuggestions[i];
                        return ActionChip(
                          label: Text(
                            entry.command,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                          onPressed: () => _acceptAutocomplete(entry),
                          visualDensity: VisualDensity.compact,
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Quick-insert — single scrollable row with cursor keys
  // ---------------------------------------------------------------------------

  // P1+P5: Paginated quick-insert with optional history page
  Widget _buildPaginatedQuickInsert(ColorScheme cs) {
    Widget chip(String label, String latex, {IconData? icon}) {
      return Padding(
        padding: const EdgeInsets.only(right: 4),
        child: ActionChip(
          avatar: icon != null ? Icon(icon, size: 14) : null,
          label: Text(label, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          onPressed: () {
            HapticFeedback.selectionClick();
            _trackAndInsert(latex);
          },
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }

    final hasHistory = _expressionHistory.isNotEmpty || _expressionFavorites.isNotEmpty;

    // Build pages list
    final pages = <Widget>[
      // Page 0 (optional): History + Favorites
      if (hasHistory)
        ListView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          children: [
            ..._expressionFavorites.map((expr) {
              final preview = expr.length > 18 ? '${expr.substring(0, 15)}…' : expr;
              return Padding(
                padding: const EdgeInsets.only(right: 5),
                child: GestureDetector(
                  onLongPress: () {
                    HapticFeedback.mediumImpact();
                    setState(() => _expressionFavorites.remove(expr));
                  },
                  child: ActionChip(
                    label: Text(preview, style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: cs.onPrimaryContainer)),
                    avatar: Icon(Icons.star_rounded, size: 14, color: cs.primary),
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      _sourceController.text = expr;
                      _sourceController.selection = TextSelection.collapsed(offset: expr.length);
                      _pushUndoSnapshot();
                    },
                    backgroundColor: cs.primaryContainer,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                ),
              );
            }),
            ..._expressionHistory.where((e) => !_expressionFavorites.contains(e)).map((expr) {
              final preview = expr.length > 18 ? '${expr.substring(0, 15)}…' : expr;
              return Padding(
                padding: const EdgeInsets.only(right: 5),
                child: GestureDetector(
                  onLongPress: () {
                    HapticFeedback.mediumImpact();
                    setState(() {
                      if (!_expressionFavorites.contains(expr)) {
                        _expressionFavorites.insert(0, expr);
                        if (_expressionFavorites.length > 10) _expressionFavorites.removeLast();
                      }
                    });
                  },
                  child: ActionChip(
                    label: Text(preview, style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: cs.onSurfaceVariant)),
                    avatar: Icon(Icons.history_rounded, size: 14, color: cs.onSurfaceVariant),
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      _sourceController.text = expr;
                      _sourceController.selection = TextSelection.collapsed(offset: expr.length);
                      _pushUndoSnapshot();
                    },
                    backgroundColor: cs.surfaceContainerHigh,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                ),
              );
            }),
          ],
        ),

      // Page: Structures (with cursor keys)
      ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                SizedBox(width: 32, child: IconButton(icon: const Icon(Icons.chevron_left_rounded, size: 18), onPressed: () => _moveCursor(-1), visualDensity: VisualDensity.compact, padding: EdgeInsets.zero)),
                SizedBox(width: 32, child: IconButton(icon: const Icon(Icons.chevron_right_rounded, size: 18), onPressed: () => _moveCursor(1), visualDensity: VisualDensity.compact, padding: EdgeInsets.zero)),
              ],
            ),
          ),
          chip(r'\\', r'\\'),
          chip('frac', r'\frac{}{}'),
          chip('sqrt', r'\sqrt{}'),
          chip('^', '^{}'),
          chip('_', '_{}'),
          chip('sum', r'\sum'),
          chip('int', r'\int'),
        ],
      ),

      // Page: Environments
      ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: [
          chip('()', r'\left(\right)'),
          chip('[]', r'\left[\right]'),
          chip('{}', r'\{\}'),
          chip('matrix', r'\begin{pmatrix}  \\  \end{pmatrix}'),
          chip('cases', r'\begin{cases}  \\  \end{cases}'),
          chip('aligned', r'\begin{aligned}  \\  \end{aligned}'),
        ],
      ),

      // Page: Functions + Greek
      ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: [
          chip('sin', r'\sin'),
          chip('cos', r'\cos'),
          chip('tan', r'\tan'),
          chip('log', r'\log'),
          chip('ln', r'\ln'),
          chip('inf', r'\infty'),
          chip('pi', r'\pi'),
          chip('alpha', r'\alpha'),
          chip('beta', r'\beta'),
        ],
      ),
    ];

    final pageCount = pages.length;
    // Use a consistent PageController — avoid recreating
    return Column(
      children: [
        SizedBox(
          height: 36,
          child: PageView(
            onPageChanged: (i) => setState(() {}), // refresh dots
            children: pages,
          ),
        ),
        const SizedBox(height: 4),
        // Dot indicators
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(pageCount, (i) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Template grid
  // ---------------------------------------------------------------------------

  Widget _buildTemplateGrid(ColorScheme cs) {
    final templates = <(String, String)>[
      ('Fraction', r'\frac{a}{b}'),
      ('Power', r'x^{n}'),
      ('Square Root', r'\sqrt{x}'),
      ('Integral', r'\int_{a}^{b} f(x)\,dx'),
      ('Sum', r'\sum_{i=0}^{n} a_i'),
      ('Matrix', r'\begin{pmatrix} a & b \\ c & d \end{pmatrix}'),
      ('Limit', r'\lim_{x \to \infty} f(x)'),
      ('Derivative', r'\frac{d}{dx} f(x)'),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children:
          templates.map((t) {
            return ActionChip(
              label: Text(t.$1, style: const TextStyle(fontSize: 12)),
              onPressed: () {
                HapticFeedback.selectionClick();
                _trackAndInsert(t.$2);
                Navigator.of(context).pop();
              },
            );
          }).toList(),
    );
  }

  // ---------------------------------------------------------------------------
  // Mode: Handwriting
  // ---------------------------------------------------------------------------

  Widget _buildHandwritingMode(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: LatexInkOverlay(
              clearSignal: _inkClearSignal,
              onStrokesComplete: _handleStrokesComplete,
              ghostLatex: _sourceController.text.isNotEmpty
                  ? _sourceController.text
                  : null,
              ghostFontSize: _fontSize,
              ghostColor: _color,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.draw_rounded, size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                'Scrivi con lo stilo o il dito',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Mode: Symbols
  // ---------------------------------------------------------------------------

  Widget _buildSymbolsMode() {
    return LatexSymbolPalette(onSymbolSelected: _insertSymbol);
  }

  // ---------------------------------------------------------------------------
  // Camera OCR mode
  // ---------------------------------------------------------------------------

  /// Pick an image from gallery/file system and run OCR recognition.
  Future<void> _pickAndRecognize() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final pickedFile = result.files.first;
      if (pickedFile.path == null) return;

      // On web, use bytes directly from FilePicker (no File access)
      final Uint8List bytes;
      if (kIsWeb) {
        if (pickedFile.bytes == null) return;
        bytes = pickedFile.bytes!;
      } else {
        bytes = await File(pickedFile.path!).readAsBytes();
      }
      setState(() {
        _cameraImageBytes = bytes;
        _isCameraRecognizing = true;
        _cameraAlternatives = <LatexAlternative>[];
        _cameraConfidence = 0.0;
      });

      HapticFeedback.mediumImpact();

      final recognizer = widget.recognizer;
      if (recognizer == null) {
        setState(() => _isCameraRecognizing = false);
        return;
      }

      final result2 = await recognizer.recognizeImage(bytes);

      if (!mounted) return;

      setState(() {
        _isCameraRecognizing = false;
        _cameraConfidence = result2.confidence;
        _cameraAlternatives = result2.alternatives;
      });

      if (result2.latexString.isNotEmpty) {
        _pushUndoSnapshot();
        _sourceController.text = result2.latexString;
        _sourceController.selection = TextSelection.collapsed(
          offset: result2.latexString.length,
        );
        HapticFeedback.heavyImpact();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCameraRecognizing = false);
      }
    }
  }

  Widget _buildCameraMode(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Image preview or placeholder
          Expanded(
            child:
                _cameraImageBytes != null
                    ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(_cameraImageBytes!, fit: BoxFit.contain),
                          if (_isCameraRecognizing)
                            Container(
                              color: Colors.black54,
                              child: const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(
                                      strokeWidth: 3,
                                      color: Colors.white,
                                    ),
                                    SizedBox(height: 12),
                                    Text(
                                      'Riconoscimento in corso...',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          // Confidence badge
                          if (!_isCameraRecognizing && _cameraConfidence > 0)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      _cameraConfidence > 0.8
                                          ? Colors.green
                                          : _cameraConfidence > 0.5
                                          ? Colors.orange
                                          : Colors.red,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${(_cameraConfidence * 100).toStringAsFixed(0)}%',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    )
                    : Container(
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withValues(
                          alpha: 0.3,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cs.outlineVariant, width: 1),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.camera_alt_rounded,
                              size: 48,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Fotografa un\'equazione matematica',
                              style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
          ),

          const SizedBox(height: 12),

          // Action buttons
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              onPressed:
                  _isCameraRecognizing ? null : () => _pickAndRecognize(),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.photo_library_rounded, size: 18),
                  SizedBox(width: 8),
                  Text('Scegli immagine'),
                ],
              ),
            ),
          ),

          // Alternative results
          if (_cameraAlternatives.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _cameraAlternatives.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final alt = _cameraAlternatives[index];
                  return ActionChip(
                    label: Text(
                      alt.latexString,
                      style: const TextStyle(fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: () {
                      _pushUndoSnapshot();
                      _sourceController.text = alt.latexString;
                      HapticFeedback.selectionClick();
                    },
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // E8: Bottom Toolbar with font size slider
  // ---------------------------------------------------------------------------

  Widget _buildToolbar(ColorScheme cs) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        8 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(top: BorderSide(color: cs.outlineVariant, width: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // P4: Font size slider — toggled by icon, hidden by default
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _showFontSlider && MediaQuery.of(context).viewInsets.bottom < 80
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Icon(Icons.format_size_rounded, size: 18, color: cs.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Text('${_fontSize.toInt()}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface, fontFeatures: const [FontFeature.tabularFigures()])),
                        Expanded(
                          child: SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                              activeTrackColor: cs.primary,
                              inactiveTrackColor: cs.primaryContainer,
                              thumbColor: cs.primary,
                            ),
                            child: Slider(value: _fontSize, min: 10, max: 96, divisions: 43, onChanged: (v) => setState(() => _fontSize = v), onChangeEnd: (_) => HapticFeedback.selectionClick()),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          // Action buttons row — compact when keyboard is visible
          Builder(
            builder: (context) {
              final kbOpen = MediaQuery.of(context).viewInsets.bottom > 80;

              if (kbOpen) {
                // ─── Compact keyboard toolbar ───
                return Row(
                  children: [
                    // Backslash key
                    _CompactKey(
                      label: '\\',
                      onTap: () => _insertAtCursor('\\'),
                      cs: cs,
                    ),
                    const SizedBox(width: 3),
                    // Opening brace
                    _CompactKey(
                      label: '{',
                      onTap: () => _insertAtCursor('{'),
                      cs: cs,
                    ),
                    const SizedBox(width: 3),
                    // Closing brace
                    _CompactKey(
                      label: '}',
                      onTap: () => _insertAtCursor('}'),
                      cs: cs,
                    ),
                    const SizedBox(width: 3),
                    // Caret
                    _CompactKey(
                      label: '^',
                      onTap: () => _insertAtCursor('^'),
                      cs: cs,
                    ),
                    const SizedBox(width: 3),
                    // Underscore
                    _CompactKey(
                      label: '_',
                      onTap: () => _insertAtCursor('_'),
                      cs: cs,
                    ),

                    const SizedBox(width: 6),

                    // Cursor left
                    _CompactIconKey(
                      icon: Icons.chevron_left_rounded,
                      onTap: () => _moveCursor(-1),
                      cs: cs,
                    ),
                    const SizedBox(width: 3),
                    // Cursor right
                    _CompactIconKey(
                      icon: Icons.chevron_right_rounded,
                      onTap: () => _moveCursor(1),
                      cs: cs,
                    ),

                    const Spacer(),

                    // Color (icon only)
                    _ToolbarIconButton(
                      icon: Icons.palette_rounded,
                      tooltip: 'Color',
                      onTap: () => _showColorPicker(cs),
                      dotColor: _color,
                      size: 32,
                    ),
                    // Reference (icon only)
                    _ToolbarIconButton(
                      icon: Icons.menu_book_rounded,
                      tooltip: 'Commands',
                      onTap: () => _openCommandReference(),
                      size: 32,
                    ),

                    const SizedBox(width: 4),

                    // Confirm (compact)
                    SizedBox(
                      height: 32,
                      child: FilledButton(
                        onPressed:
                            _sourceController.text.isNotEmpty ? _confirm : null,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          textStyle: const TextStyle(fontSize: 13),
                        ),
                        child: const Icon(Icons.check_rounded, size: 18),
                      ),
                    ),
                  ],
                );
              }

              // ─── Full toolbar (keyboard closed) ───
              return Row(
                children: [
                  // Color picker
                  _ToolbarIconButton(
                    icon: Icons.palette_rounded,
                    tooltip: 'Color',
                    onTap: () => _showColorPicker(cs),
                    dotColor: _color,
                  ),

                  const SizedBox(width: 4),

                  // Command reference
                  _ToolbarIconButton(
                    icon: Icons.menu_book_rounded,
                    tooltip: 'LaTeX Commands',
                    onTap: () => _openCommandReference(),
                  ),

                  const SizedBox(width: 4),

                  // P4: Font size toggle
                  _ToolbarIconButton(
                    icon: Icons.format_size_rounded,
                    tooltip: 'Dimensione: ${_fontSize.toInt()}',
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _showFontSlider = !_showFontSlider);
                    },
                  ),

                  const Spacer(),

                  // Clear
                  TextButton.icon(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      _pushUndoSnapshot();
                      setState(() {
                        _sourceController.clear();
                        _confidenceAnnotations.clear();
                        _validationErrors.clear();
                      });
                    },
                    icon: const Icon(Icons.clear_all_rounded, size: 18),
                    label: const Text('Clear'),
                    style: TextButton.styleFrom(
                      foregroundColor: cs.onSurfaceVariant,
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Confirm
                  FilledButton.icon(
                    onPressed:
                        _sourceController.text.isNotEmpty ? _confirm : null,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Confirm'),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Color Picker
  // ---------------------------------------------------------------------------

  void _showColorPicker(ColorScheme cs) {
    HapticFeedback.selectionClick(); // E6

    // U7: HSL color picker state
    double hue = HSLColor.fromColor(_color).hue;
    double saturation = HSLColor.fromColor(_color).saturation;
    double lightness = HSLColor.fromColor(_color).lightness;

    // Quick preset swatches (keep a few for convenience)
    final presets = [
      Colors.white,
      Colors.black,
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.amber,
      Colors.purple,
      Colors.teal,
    ];

    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setPickerState) {
            final currentColor =
                HSLColor.fromAHSL(1, hue, saturation, lightness).toColor();

            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with preview
                  Row(
                    children: [
                      Text(
                        'Colore formula',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      const Spacer(),
                      // Color preview swatch
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: currentColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: cs.outlineVariant),
                          boxShadow: [
                            BoxShadow(
                              color: currentColor.withValues(alpha: 0.4),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Preset swatches row
                  SizedBox(
                    height: 36,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: presets.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final c = presets[i];
                        return GestureDetector(
                          onTap: () {
                            final hsl = HSLColor.fromColor(c);
                            setPickerState(() {
                              hue = hsl.hue;
                              saturation = hsl.saturation;
                              lightness = hsl.lightness;
                            });
                          },
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: cs.outlineVariant,
                                width: 1,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),

                  // U7: Hue slider
                  Row(
                    children: [
                      Text(
                        'Tinta',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 8,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 8,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 14,
                            ),
                            activeTrackColor:
                                HSLColor.fromAHSL(1, hue, 1, 0.5).toColor(),
                            inactiveTrackColor: cs.surfaceContainerHighest,
                          ),
                          child: Slider(
                            value: hue,
                            min: 0,
                            max: 360,
                            onChanged: (v) => setPickerState(() => hue = v),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 32,
                        child: Text(
                          '${hue.toInt()}°',
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),

                  // Saturation slider
                  Row(
                    children: [
                      Text(
                        'Satur.',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 8,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 8,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 14,
                            ),
                            activeTrackColor: currentColor,
                            inactiveTrackColor: cs.surfaceContainerHighest,
                          ),
                          child: Slider(
                            value: saturation,
                            onChanged:
                                (v) => setPickerState(() => saturation = v),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 32,
                        child: Text(
                          '${(saturation * 100).toInt()}%',
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),

                  // Lightness slider
                  Row(
                    children: [
                      Text(
                        'Lum.',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 8,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 8,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 14,
                            ),
                            activeTrackColor: currentColor,
                            inactiveTrackColor: cs.surfaceContainerHighest,
                          ),
                          child: Slider(
                            value: lightness,
                            onChanged:
                                (v) => setPickerState(() => lightness = v),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 32,
                        child: Text(
                          '${(lightness * 100).toInt()}%',
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Confirm button
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        setState(() => _color = currentColor);
                        Navigator.of(ctx).pop();
                      },
                      child: const Text('Applica'),
                    ),
                  ),
                  SizedBox(height: MediaQuery.of(ctx).padding.bottom + 8),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
