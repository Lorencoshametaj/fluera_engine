// =============================================================================
// 🔍 SPELLCHECK & GRAMMAR — In-canvas text validation integration
//
// Part of FlueraCanvasScreen. Manages spellcheck + grammar state, triggers
// validation after text recognition/editing, and builds overlay widgets.
// =============================================================================

part of '../fluera_canvas_screen.dart';

/// Combined error type for both spelling and grammar issues.
class _TextValidationError {
  final String word;
  final int startIndex;
  final int endIndex;
  final List<String> suggestions;
  final String? message; // Grammar rule message (null = spelling)
  final bool isGrammar; // true = grammar, false = spelling

  const _TextValidationError({
    required this.word,
    required this.startIndex,
    required this.endIndex,
    required this.suggestions,
    this.message,
    this.isGrammar = false,
  });
}

extension _SpellcheckMixin on _FlueraCanvasScreenState {
  // ── State access (stored in _FlueraCanvasScreenState) ─────────────────
  // These are accessed via the main state's fields:
  //   _spellcheckOverlays — Map<String, SpellcheckOverlay>
  //   _grammarOverlays — Map<String, _GrammarOverlayData>
  //   _activeSpellcheckError — SpellcheckError? (for popup)
  //   _activeGrammarError — GrammarError? (for popup)
  //   _spellcheckPopupPosition — Offset? (screen position for popup)

  /// 🔍 Run spellcheck AND grammar check on all digital text elements.
  void runSpellcheck() {
    final newSpellOverlays = <String, SpellcheckOverlay>{};
    final newGrammarOverlays = <String, _GrammarOverlayData>{};

    for (final element in _digitalTextElements) {
      final text = element.plainText;

      // Spelling (multi-language aware)
      final spellResult = SpellcheckService.instance.checkTextMultiLang(text);
      if (spellResult.hasErrors) {
        newSpellOverlays[element.id] = SpellcheckOverlay(
          elementId: element.id,
          errors: spellResult.errors,
        );
      }

      // Grammar
      final grammarResult = GrammarCheckService.instance.checkText(text);
      if (grammarResult.hasErrors) {
        newGrammarOverlays[element.id] = _GrammarOverlayData(
          elementId: element.id,
          errors: grammarResult.errors,
        );
      }
    }

    // Only trigger rebuild if overlays actually changed
    final spellChanged = newSpellOverlays.length != _spellcheckOverlays.length ||
        !_spellcheckOverlaysEqual(newSpellOverlays);
    final grammarChanged = newGrammarOverlays.length != _grammarOverlays.length;

    if (spellChanged || grammarChanged) {
      setState(() {
        _spellcheckOverlays = newSpellOverlays;
        _grammarOverlays = newGrammarOverlays;
      });
    }
  }

  bool _spellcheckOverlaysEqual(Map<String, SpellcheckOverlay> other) {
    for (final key in _spellcheckOverlays.keys) {
      if (!other.containsKey(key)) return false;
      if (_spellcheckOverlays[key]!.errors.length !=
          other[key]!.errors.length) return false;
    }
    return true;
  }

  /// 🔍 Check if a tap on the canvas hits a misspelled word or grammar error.
  bool handleSpellcheckTap(Offset canvasPosition) {
    if (_spellcheckOverlays.isEmpty && _grammarOverlays.isEmpty) return false;

    for (final element in _digitalTextElements) {
      if (!element.containsPoint(canvasPosition)) continue;

      final painter = element.layoutPainter;
      final localPos = canvasPosition - element.position;
      final textPosition = painter.getPositionForOffset(localPos);

      // Check spelling errors first
      final spellOverlay = _spellcheckOverlays[element.id];
      if (spellOverlay != null) {
        for (final error in spellOverlay.errors) {
          if (textPosition.offset >= error.startIndex &&
              textPosition.offset < error.endIndex) {
            _showPopupForSpellError(element, error, painter);
            return true;
          }
        }
      }

      // Then check grammar errors
      final grammarOverlay = _grammarOverlays[element.id];
      if (grammarOverlay != null) {
        for (final error in grammarOverlay.errors) {
          if (textPosition.offset >= error.startIndex &&
              textPosition.offset < error.endIndex) {
            _showPopupForGrammarError(element, error, painter);
            return true;
          }
        }
      }
    }
    return false;
  }

  void _showPopupForSpellError(
    DigitalTextElement element,
    SpellcheckError error,
    TextPainter painter,
  ) {
    final screenPos = _canvasController.canvasToScreen(
      element.position + painter.getOffsetForCaret(
        TextPosition(offset: error.startIndex),
        Rect.zero,
      ),
    );
    setState(() {
      _activeSpellcheckError = error;
      _activeGrammarError = null;
      _activeSpellcheckElementId = element.id;
      _spellcheckPopupPosition = screenPos + const Offset(0, 24);
    });
  }

  void _showPopupForGrammarError(
    DigitalTextElement element,
    GrammarError error,
    TextPainter painter,
  ) {
    final screenPos = _canvasController.canvasToScreen(
      element.position + painter.getOffsetForCaret(
        TextPosition(offset: error.startIndex),
        Rect.zero,
      ),
    );
    setState(() {
      _activeGrammarError = error;
      _activeSpellcheckError = null;
      _activeSpellcheckElementId = element.id;
      _spellcheckPopupPosition = screenPos + const Offset(0, 24);
    });
  }

  /// 📝 Apply a correction (spelling or grammar).
  void applySpellcheckCorrection(String correction) {
    final elementId = _activeSpellcheckElementId;
    if (elementId == null) return;

    final int startIdx;
    final int endIdx;

    if (_activeSpellcheckError != null) {
      startIdx = _activeSpellcheckError!.startIndex;
      endIdx = _activeSpellcheckError!.endIndex;
    } else if (_activeGrammarError != null) {
      startIdx = _activeGrammarError!.startIndex;
      endIdx = _activeGrammarError!.endIndex;
    } else {
      return;
    }

    final idx = _digitalTextElements.indexWhere((e) => e.id == elementId);
    if (idx < 0) return;

    final element = _digitalTextElements[idx];
    final oldText = element.plainText;

    final newText = oldText.substring(0, startIdx) +
        correction +
        oldText.substring(endIdx);

    final updated = element.copyWith(
      text: newText,
      modifiedAt: DateTime.now(),
    );

    setState(() {
      _digitalTextElements[idx] = updated;
      _activeSpellcheckError = null;
      _activeGrammarError = null;
      _activeSpellcheckElementId = null;
      _spellcheckPopupPosition = null;
    });

    runSpellcheck();
    WordCompletionDictionary.instance.boost(correction);
  }

  /// 🚫 Ignore the misspelled word.
  void ignoreSpellcheckWord() {
    if (_activeSpellcheckError != null) {
      SpellcheckService.instance.ignoreWord(_activeSpellcheckError!.word);
    }

    setState(() {
      _activeSpellcheckError = null;
      _activeGrammarError = null;
      _activeSpellcheckElementId = null;
      _spellcheckPopupPosition = null;
    });

    runSpellcheck();
  }

  /// 📚 Add the word to the personal dictionary.
  void addToPersonalDictionary() {
    if (_activeSpellcheckError != null) {
      PersonalDictionaryService.instance.addWord(_activeSpellcheckError!.word);
    }

    setState(() {
      _activeSpellcheckError = null;
      _activeGrammarError = null;
      _activeSpellcheckElementId = null;
      _spellcheckPopupPosition = null;
    });

    runSpellcheck();
  }

  /// Dismiss spellcheck/grammar popup.
  void dismissSpellcheckPopup() {
    if (_activeSpellcheckError == null && _activeGrammarError == null) return;
    setState(() {
      _activeSpellcheckError = null;
      _activeGrammarError = null;
      _activeSpellcheckElementId = null;
      _spellcheckPopupPosition = null;
    });
  }

  /// 🔍 Build the spellcheck + grammar overlay widgets.
  List<Widget> buildSpellcheckOverlays() {
    final widgets = <Widget>[];

    // 🔴 Wavy red underlines for spelling errors
    if (_spellcheckOverlays.isNotEmpty) {
      widgets.add(
        IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: SpellcheckPainter(
                texts: _digitalTextElements,
                canvasOffset: _canvasController.offset,
                canvasScale: _canvasController.scale,
                overlays: _spellcheckOverlays,
              ),
              size: Size.infinite,
            ),
          ),
        ),
      );
    }

    // 🔵 Wavy blue underlines for grammar errors
    if (_grammarOverlays.isNotEmpty) {
      widgets.add(
        IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: GrammarPainter(
                texts: _digitalTextElements,
                canvasOffset: _canvasController.offset,
                canvasScale: _canvasController.scale,
                overlays: _grammarOverlays,
              ),
              size: Size.infinite,
            ),
          ),
        ),
      );
    }

    // Correction popup — unified SpellcheckContextMenu for both spelling and grammar
    if (_spellcheckPopupPosition != null &&
        (_activeSpellcheckError != null || _activeGrammarError != null)) {
      final isGrammar = _activeGrammarError != null;
      final word = isGrammar
          ? (_activeGrammarError!.suggestion ?? '')
          : _activeSpellcheckError!.word;
      final suggestions = isGrammar
          ? (_activeGrammarError!.suggestion != null
              ? [_activeGrammarError!.suggestion!]
              : <String>[])
          : _activeSpellcheckError!.suggestions;

      widgets.add(
        SpellcheckContextMenu(
          position: _spellcheckPopupPosition!,
          word: word,
          suggestions: suggestions,
          isGrammar: isGrammar,
          grammarMessage: isGrammar ? _activeGrammarError!.message : null,
          onDismiss: dismissSpellcheckPopup,
          onApplyCorrection: applySpellcheckCorrection,
          onIgnore: ignoreSpellcheckWord,
          onAddToDictionary: isGrammar ? null : addToPersonalDictionary,
        ),
      );
    }

    return widgets;
  }

  /// 🗑️ Show grammar settings sheet.
  void showGrammarSettings() {
    final ctx = this as dynamic;
    if (ctx.context != null) {
      GrammarSettingsSheet.show(ctx.context as BuildContext).then((_) {
        runSpellcheck(); // Re-run after settings change
      });
    }
  }
}

/// Grammar overlay data for a single text element.
class _GrammarOverlayData {
  final String elementId;
  final List<GrammarError> errors;
  const _GrammarOverlayData({required this.elementId, required this.errors});
}
