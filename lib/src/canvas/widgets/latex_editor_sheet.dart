import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/latex/ink_stroke_data.dart';
import '../../core/latex/latex_fuzzy_corrector.dart';
import '../../core/latex/latex_validator.dart';
import '../../core/latex/latex_confidence_annotator.dart';
import '../../platform/latex_recognition_bridge.dart';
import 'latex_command_reference.dart';
import 'latex_preview_card.dart';
import 'latex_ink_overlay.dart';
import 'latex_symbol_palette.dart';
import 'latex_confidence_chips.dart';
import 'latex_syntax_highlighting.dart';

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
  });

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

    // T5: Keyboard shortcuts + T6: Accessibility semantics
    return Semantics(
      label: 'Editor LaTeX',
      container: true,
      child: Shortcuts(
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
          child: Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            child: Column(
              children: [
                _buildDragHandle(cs),
                _buildHeader(cs),
                const Divider(height: 1),

                // E9: Adaptive layout
                if (isLandscape)
                  Expanded(child: _buildLandscapeLayout(cs))
                else
                  Expanded(child: _buildPortraitLayout(cs)),

                _buildToolbar(cs),
              ],
            ),
          ),
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

  // Portrait — stacked
  Widget _buildPortraitLayout(ColorScheme cs) {
    return Column(
      children: [
        // Preview (compact)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: LatexPreviewCard(
            latexSource: _sourceController.text,
            fontSize: _fontSize,
            color: _color,
            minHeight: 56,
          ),
        ),

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

  // ---------------------------------------------------------------------------
  // Mode: Keyboard — E3 history + E4 expanded quick-insert + E5 templates
  // ---------------------------------------------------------------------------

  Widget _buildKeyboardMode(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // E3 + U5: Expression history + favorites chips
          if (_expressionHistory.isNotEmpty ||
              _expressionFavorites.isNotEmpty) ...[
            SizedBox(
              height: 30,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  // U5: Favorites first
                  ..._expressionFavorites.map((expr) {
                    final preview =
                        expr.length > 20 ? '${expr.substring(0, 17)}…' : expr;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        onLongPress: () {
                          // Remove from favorites
                          HapticFeedback.mediumImpact();
                          setState(() => _expressionFavorites.remove(expr));
                        },
                        child: ActionChip(
                          label: Text(
                            preview,
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: cs.onPrimaryContainer,
                            ),
                          ),
                          avatar: Icon(
                            Icons.star_rounded,
                            size: 14,
                            color: cs.primary,
                          ),
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            _sourceController.text = expr;
                            _sourceController.selection =
                                TextSelection.collapsed(offset: expr.length);
                            _pushUndoSnapshot();
                          },
                          backgroundColor: cs.primaryContainer,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        ),
                      ),
                    );
                  }),
                  // History (non-favorites)
                  ..._expressionHistory
                      .where((e) => !_expressionFavorites.contains(e))
                      .map((expr) {
                        final preview =
                            expr.length > 20
                                ? '${expr.substring(0, 17)}…'
                                : expr;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: GestureDetector(
                            onLongPress: () {
                              // U5: Add to favorites
                              HapticFeedback.mediumImpact();
                              setState(() {
                                if (!_expressionFavorites.contains(expr)) {
                                  _expressionFavorites.insert(0, expr);
                                  if (_expressionFavorites.length > 10) {
                                    _expressionFavorites.removeLast();
                                  }
                                }
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text(
                                    'Aggiunto ai preferiti ★',
                                  ),
                                  behavior: SnackBarBehavior.floating,
                                  duration: const Duration(seconds: 1),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              );
                            },
                            child: ActionChip(
                              label: Text(
                                preview,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              avatar: Icon(
                                Icons.history_rounded,
                                size: 14,
                                color: cs.onSurfaceVariant,
                              ),
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                _sourceController.text = expr;
                                _sourceController
                                    .selection = TextSelection.collapsed(
                                  offset: expr.length,
                                );
                                _pushUndoSnapshot();
                              },
                              backgroundColor: cs.surfaceContainerHigh,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                            ),
                          ),
                        );
                      }),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],

          // E4: Expanded quick-insert — compact when keyboard visible
          _buildQuickInsertRows(
            cs,
            compact: MediaQuery.of(context).viewInsets.bottom > 80,
          ),

          const SizedBox(height: 12),

          // E5: Template library (collapsible)
          if (_showTemplates) ...[
            _buildTemplateGrid(cs),
            const SizedBox(height: 8),
          ],

          // Text field with T1 syntax highlighting + T3 auto-brackets
          Expanded(
            child: Stack(
              children: [
                Semantics(
                  label: 'Campo sorgente LaTeX',
                  textField: true,
                  child: TextField(
                    controller: _sourceController,
                    focusNode: _editorFocusNode,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 15,
                      color: cs.onSurface,
                    ),
                    // T3: Auto-bracket closing
                    inputFormatters: [_AutoBracketFormatter()],
                    // U4: Context menu with 'Wrap in…' options
                    contextMenuBuilder: (context, editableTextState) {
                      final defaultItems =
                          editableTextState.contextMenuButtonItems;
                      final sel = _sourceController.selection;
                      final hasSelection = sel.isValid && !sel.isCollapsed;

                      if (!hasSelection) {
                        return AdaptiveTextSelectionToolbar.buttonItems(
                          anchors: editableTextState.contextMenuAnchors,
                          buttonItems: defaultItems,
                        );
                      }

                      // Add wrap-in commands
                      final wrapItems = <ContextMenuButtonItem>[
                        ContextMenuButtonItem(
                          label: 'Wrap \\frac{}{}',
                          onPressed: () {
                            ContextMenuController.removeAny();
                            _insertSymbol(r'\frac{}{}');
                          },
                        ),
                        ContextMenuButtonItem(
                          label: 'Wrap \\sqrt{}',
                          onPressed: () {
                            ContextMenuController.removeAny();
                            _insertSymbol(r'\sqrt{}');
                          },
                        ),
                        ContextMenuButtonItem(
                          label: 'Wrap \\hat{}',
                          onPressed: () {
                            ContextMenuController.removeAny();
                            _insertSymbol(r'\hat{}');
                          },
                        ),
                        ContextMenuButtonItem(
                          label: 'Wrap \\overline{}',
                          onPressed: () {
                            ContextMenuController.removeAny();
                            _insertSymbol(r'\overline{}');
                          },
                        ),
                        ContextMenuButtonItem(
                          label: 'Wrap \\mathbf{}',
                          onPressed: () {
                            ContextMenuController.removeAny();
                            _insertSymbol(r'\mathbf{}');
                          },
                        ),
                      ];

                      return AdaptiveTextSelectionToolbar.buttonItems(
                        anchors: editableTextState.contextMenuAnchors,
                        buttonItems: [...defaultItems, ...wrapItems],
                      );
                    },
                    decoration: InputDecoration(
                      hintText: r'Es: \frac{x^2 + 1}{y}',
                      hintStyle: TextStyle(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                        fontSize: 14,
                      ),
                      filled: true,
                      fillColor: cs.surfaceContainerLow,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: cs.outlineVariant),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: cs.primary, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                ),
                // T2: Autocomplete overlay
                if (_autocompleteSuggestions.isNotEmpty)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 8,
                    child: Material(
                      elevation: 8,
                      borderRadius: BorderRadius.circular(12),
                      color: cs.surfaceContainerHigh,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children:
                            _autocompleteSuggestions.map((entry) {
                              return InkWell(
                                onTap: () => _acceptAutocomplete(entry),
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  child: Row(
                                    children: [
                                      Text(
                                        entry.command,
                                        style: TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: cs.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          entry.label,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: cs.onSurfaceVariant,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (entry.category != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: cs.primaryContainer
                                                .withValues(alpha: 0.5),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            entry.category!,
                                            style: TextStyle(
                                              fontSize: 9,
                                              color: cs.onPrimaryContainer,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── E4: Three rows of quick-insert chips ──
  Widget _buildQuickInsertRows(ColorScheme cs, {bool compact = false}) {
    if (compact) {
      // ── Keyboard visible: 2 compact rows ──
      return Column(
        children: [
          // Row 1: Most-used structures
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              children: [
                _QuickInsertChip(
                  label: 'frac',
                  onTap: () => _insertSymbol(r'\frac{}{}'),
                ),
                const SizedBox(width: 4),
                _QuickInsertChip(
                  label: '√',
                  onTap: () => _insertSymbol(r'\sqrt{}'),
                ),
                const SizedBox(width: 4),
                _QuickInsertChip(
                  label: 'x²',
                  onTap: () => _insertSymbol('^{}'),
                ),
                const SizedBox(width: 4),
                _QuickInsertChip(
                  label: 'xᵢ',
                  onTap: () => _insertSymbol('_{}'),
                ),
                const SizedBox(width: 4),
                _QuickInsertChip(
                  label: '∫',
                  onTap: () => _insertSymbol(r'\int'),
                ),
                const SizedBox(width: 4),
                _QuickInsertChip(
                  label: '∑',
                  onTap: () => _insertSymbol(r'\sum'),
                ),
                const SizedBox(width: 4),
                _QuickInsertChip(
                  label: 'lim',
                  onTap: () => _insertSymbol(r'\lim'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          // Row 2: Brackets + common functions
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              children: [
                _QuickInsertChip(
                  label: '(  )',
                  onTap: () => _insertSymbol(r'\left( \right)'),
                ),
                const SizedBox(width: 4),
                _QuickInsertChip(
                  label: '[  ]',
                  onTap: () => _insertSymbol(r'\left[ \right]'),
                ),
                const SizedBox(width: 4),
                _QuickInsertChip(
                  label: 'sin',
                  onTap: () => _insertSymbol(r'\sin'),
                ),
                const SizedBox(width: 4),
                _QuickInsertChip(
                  label: 'cos',
                  onTap: () => _insertSymbol(r'\cos'),
                ),
                const SizedBox(width: 4),
                _QuickInsertChip(
                  label: 'log',
                  onTap: () => _insertSymbol(r'\log'),
                ),
                const SizedBox(width: 4),
                _QuickInsertChip(
                  label: '∂',
                  onTap: () => _insertSymbol(r'\partial'),
                ),
                const SizedBox(width: 4),
                _QuickInsertChip(
                  label: '∞',
                  onTap: () => _insertSymbol(r'\infty'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // ── Normal: 3 full rows ──
    return Column(
      children: [
        // Row 1: Structures
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            children: [
              _QuickInsertChip(
                label: 'frac',
                onTap: () => _insertSymbol(r'\frac{}{}'),
              ),
              const SizedBox(width: 5),
              _QuickInsertChip(
                label: '√',
                onTap: () => _insertSymbol(r'\sqrt{}'),
              ),
              const SizedBox(width: 5),
              _QuickInsertChip(label: 'x²', onTap: () => _insertSymbol('^{}')),
              const SizedBox(width: 5),
              _QuickInsertChip(label: 'xᵢ', onTap: () => _insertSymbol('_{}')),
              const SizedBox(width: 5),
              _QuickInsertChip(label: '∫', onTap: () => _insertSymbol(r'\int')),
              const SizedBox(width: 5),
              _QuickInsertChip(label: '∑', onTap: () => _insertSymbol(r'\sum')),
              const SizedBox(width: 5),
              _QuickInsertChip(
                label: '∏',
                onTap: () => _insertSymbol(r'\prod'),
              ),
              const SizedBox(width: 5),
              _QuickInsertChip(
                label: 'lim',
                onTap: () => _insertSymbol(r'\lim'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // Row 2: Environments
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            children: [
              _QuickInsertChip(
                label: '(  )',
                onTap: () => _insertSymbol(r'\left( \right)'),
              ),
              const SizedBox(width: 5),
              _QuickInsertChip(
                label: '[  ]',
                onTap: () => _insertSymbol(r'\left[ \right]'),
              ),
              const SizedBox(width: 5),
              _QuickInsertChip(
                label: '{  }',
                onTap: () => _insertSymbol(r'\left\{ \right\}'),
              ),
              const SizedBox(width: 5),
              _QuickInsertChip(
                label: 'matrix',
                onTap: () => _insertSymbol(r'\begin{matrix}  \\  \end{matrix}'),
              ),
              const SizedBox(width: 5),
              _QuickInsertChip(
                label: 'cases',
                onTap: () => _insertSymbol(r'\begin{cases}  \\  \end{cases}'),
              ),
              const SizedBox(width: 5),
              _QuickInsertChip(
                label: 'aligned',
                onTap:
                    () => _insertSymbol(r'\begin{aligned}  \\  \end{aligned}'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // Row 3: Common functions + template toggle
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            children: [
              _QuickInsertChip(
                label: 'sin',
                onTap: () => _insertSymbol(r'\sin'),
              ),
              const SizedBox(width: 5),
              _QuickInsertChip(
                label: 'cos',
                onTap: () => _insertSymbol(r'\cos'),
              ),
              const SizedBox(width: 5),
              _QuickInsertChip(
                label: 'tan',
                onTap: () => _insertSymbol(r'\tan'),
              ),
              const SizedBox(width: 5),
              _QuickInsertChip(
                label: 'log',
                onTap: () => _insertSymbol(r'\log'),
              ),
              const SizedBox(width: 5),
              _QuickInsertChip(label: 'ln', onTap: () => _insertSymbol(r'\ln')),
              const SizedBox(width: 5),
              _QuickInsertChip(
                label: '∂',
                onTap: () => _insertSymbol(r'\partial'),
              ),
              const SizedBox(width: 5),
              _QuickInsertChip(
                label: '∇',
                onTap: () => _insertSymbol(r'\nabla'),
              ),
              const SizedBox(width: 5),
              _QuickInsertChip(
                label: '∞',
                onTap: () => _insertSymbol(r'\infty'),
              ),
              const SizedBox(width: 12),
              // E5: Template toggle
              _TemplateToggleChip(
                isExpanded: _showTemplates,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _showTemplates = !_showTemplates);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── E5: Template grid ──
  Widget _buildTemplateGrid(ColorScheme cs) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 130),
      child: GridView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 0.35,
        ),
        itemCount: _templates.length,
        itemBuilder: (context, i) {
          final t = _templates[i];
          return _TemplateCard(
            name: t.name,
            preview: t.preview,
            onTap: () {
              HapticFeedback.mediumImpact();
              _sourceController.text = t.latex;
              _sourceController.selection = TextSelection.collapsed(
                offset: t.latex.length,
              );
              _pushUndoSnapshot();
              setState(() => _showTemplates = false);
            },
          );
        },
      ),
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
              onStrokesComplete: _handleStrokesComplete,
              enabled: !_isRecognizing,
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

  /// Pick an image from camera or gallery and run OCR recognition.
  Future<void> _pickAndRecognize(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 90,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
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

      final result = await recognizer.recognizeImage(bytes);

      if (!mounted) return;

      setState(() {
        _isCameraRecognizing = false;
        _cameraConfidence = result.confidence;
        _cameraAlternatives = result.alternatives;
      });

      if (result.latexString.isNotEmpty) {
        _pushUndoSnapshot();
        _sourceController.text = result.latexString;
        _sourceController.selection = TextSelection.collapsed(
          offset: result.latexString.length,
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
          Row(
            children: [
              Expanded(
                child: FilledButton.tonal(
                  onPressed:
                      _isCameraRecognizing
                          ? null
                          : () => _pickAndRecognize(ImageSource.camera),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.camera_alt_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('Scatta'),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonal(
                  onPressed:
                      _isCameraRecognizing
                          ? null
                          : () => _pickAndRecognize(ImageSource.gallery),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.photo_library_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('Galleria'),
                    ],
                  ),
                ),
              ),
            ],
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
          // E8: Font size slider — hide when keyboard is up
          if (MediaQuery.of(context).viewInsets.bottom < 80)
            Row(
              children: [
                Icon(
                  Icons.format_size_rounded,
                  size: 18,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  '${_fontSize.toInt()}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 7,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 14,
                      ),
                      activeTrackColor: cs.primary,
                      inactiveTrackColor: cs.primaryContainer,
                      thumbColor: cs.primary,
                    ),
                    child: Slider(
                      value: _fontSize,
                      min: 10,
                      max: 96,
                      divisions: 43,
                      onChanged: (v) {
                        setState(() => _fontSize = v);
                      },
                      onChangeEnd: (_) => HapticFeedback.selectionClick(),
                    ),
                  ),
                ),
              ],
            ),
          if (MediaQuery.of(context).viewInsets.bottom < 80)
            const SizedBox(height: 4),
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

  const _CompactKey({
    required this.label,
    required this.onTap,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: cs.surfaceContainerHighest,
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

  const _CompactIconKey({
    required this.icon,
    required this.onTap,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: cs.surfaceContainerHighest,
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
