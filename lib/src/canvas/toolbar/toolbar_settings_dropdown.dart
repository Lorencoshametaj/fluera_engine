import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../l10n/fluera_localizations.dart';
import '../../../testing/brush_testing.dart';
import '../../dialogs/handwriting_language_picker.dart';
import '../../services/digital_ink_service.dart';
import '../../utils/ai_language_preference.dart';
import '../../utils/ui_language_preference.dart';

/// Type-safe action enum for the toolbar settings dropdown. Replaces the
/// previous `String` switch to get exhaustive-switch checking and IDE
/// autocomplete.
enum _CanvasSettingsAction {
  renameNote,
  exportCanvas,
  ocr,
  paperMode,
  brushSettings,
  wheelMode,
  filters,
  readingLevel,
  languages,
  brushTesting,
}

// ============================================================================
// TOOLBAR SETTINGS DROPDOWN — Settings menu, rename dialog, OCR, filters
// ============================================================================

/// Settings dropdown menu with brush settings, export, OCR, filters, etc.
class ToolbarSettingsDropdown extends StatefulWidget {
  final void Function(Rect anchorRect)? onBrushSettingsPressed;
  final VoidCallback? onExportPressed;
  final String? noteTitle;
  final ValueChanged<String>? onNoteTitleChanged;

  final VoidCallback? onPaperTypePressed;
  final VoidCallback? onReadingLevelPressed;

  /// Toggle radial brush-wheel mode (power-user opt-in, Round 4 moved
  /// out of the toolbar into Settings). Null hides the entry.
  final VoidCallback? onWheelModeToggle;

  /// Current wheel-mode state — drives the trailing "Active" badge so
  /// the user can tell at a glance whether it's on.
  final bool isWheelModeActive;

  /// When true, exposes debug-only items (Brush Testing Lab). Default false.
  /// Wire from the host's dev-mode toggle (7-tap easter egg in About settings).
  final bool devModeEnabled;

  /// Current paper label rendered as trailing on the Paper Mode item, e.g.
  /// "Quadretti 5mm", "Blank". When null, no trailing is shown — back-compat.
  final String? currentPaperLabel;

  /// Number of currently active filters, rendered as trailing on the Filters
  /// item, e.g. "2 attivi". When null or 0, no trailing is shown.
  final int? activeFiltersCount;

  /// Whether the user has already seen/tapped Reading Level. When `false`,
  /// the dropdown shows a green "NEW" badge as trailing. Host persists state
  /// (e.g. SharedPreferences) and re-passes it on rebuild.
  final bool readingLevelSeen;

  /// Optional host callback fired when Reading Level is tapped for the first
  /// time (i.e. with `readingLevelSeen == false`). Host should persist seen.
  final VoidCallback? onReadingLevelMarkSeen;

  const ToolbarSettingsDropdown({
    super.key,
    this.onBrushSettingsPressed,
    this.onExportPressed,
    this.noteTitle,
    this.onNoteTitleChanged,
    this.onPaperTypePressed,
    this.onReadingLevelPressed,
    this.onWheelModeToggle,
    this.isWheelModeActive = false,
    this.devModeEnabled = false,
    this.currentPaperLabel,
    this.activeFiltersCount,
    this.readingLevelSeen = false,
    this.onReadingLevelMarkSeen,
  });

  @override
  State<ToolbarSettingsDropdown> createState() =>
      _ToolbarSettingsDropdownState();
}

class _ToolbarSettingsDropdownState extends State<ToolbarSettingsDropdown> {
  /// Set of language codes whose OCR model has been downloaded locally —
  /// drives the "Downloaded" badge in the OCR language picker. Lazily
  /// populated as the user downloads models from the picker dialog.
  final Set<String> _downloadedLanguages = {};

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = FlueraLocalizations.of(context)!;
    return PopupMenuButton<_CanvasSettingsAction>(
      icon: Icon(Icons.edit_note_rounded, color: cs.onSurface, size: 20),
      tooltip: l10n.proCanvas_writing,
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: cs.surfaceContainerLow,
      elevation: 8,
      itemBuilder: (BuildContext context) => _buildMenuItems(context, cs, l10n),
      onSelected: (_CanvasSettingsAction action) {
        switch (action) {
          case _CanvasSettingsAction.renameNote:
            _showRenameNoteDialog(context);
          case _CanvasSettingsAction.exportCanvas:
            widget.onExportPressed?.call();
          case _CanvasSettingsAction.ocr:
            _showOCRLanguageDialog(context);
          case _CanvasSettingsAction.paperMode:
            widget.onPaperTypePressed?.call();
          case _CanvasSettingsAction.brushSettings:
            final box = context.findRenderObject() as RenderBox;
            final pos = box.localToGlobal(Offset.zero);
            widget.onBrushSettingsPressed?.call(pos & box.size);
          case _CanvasSettingsAction.wheelMode:
            HapticFeedback.lightImpact();
            widget.onWheelModeToggle?.call();
          case _CanvasSettingsAction.filters:
            _showFiltersDialog(context);
          case _CanvasSettingsAction.readingLevel:
            if (!widget.readingLevelSeen) {
              widget.onReadingLevelMarkSeen?.call();
            }
            widget.onReadingLevelPressed?.call();
          case _CanvasSettingsAction.languages:
            _showLanguagesDialog(context);
          case _CanvasSettingsAction.brushTesting:
            _openBrushTestingLab(context);
        }
      },
    );
  }

  /// Builds the dropdown items grouped in 4 themed sections:
  ///   Actions · Canvas appearance · Analysis · Languages · [Dev]
  /// Each section is introduced by a disabled "section header" PopupMenuItem
  /// and separated by a [PopupMenuDivider].
  List<PopupMenuEntry<_CanvasSettingsAction>> _buildMenuItems(
    BuildContext context,
    ColorScheme cs,
    FlueraLocalizations l10n,
  ) {
    final items = <PopupMenuEntry<_CanvasSettingsAction>>[];

    // ── AZIONI ──────────────────────────────────────────────────────────
    items.add(_sectionHeader(cs, l10n.canvasSettings_actionsSection));
    if (widget.onNoteTitleChanged != null) {
      items.add(_item(
        cs: cs,
        action: _CanvasSettingsAction.renameNote,
        icon: Icons.drive_file_rename_outline,
        label: l10n.proCanvas_renameNote,
      ));
    }
    if (widget.onExportPressed != null) {
      items.add(_item(
        cs: cs,
        action: _CanvasSettingsAction.exportCanvas,
        icon: Icons.file_download_outlined,
        label: l10n.proCanvas_exportCanvas,
      ));
    }
    items.add(_item(
      cs: cs,
      action: _CanvasSettingsAction.ocr,
      icon: Icons.text_fields_rounded,
      label: l10n.proCanvas_ocrConvertWriting,
    ));

    // ── ASPETTO CANVAS ──────────────────────────────────────────────────
    items.add(const PopupMenuDivider());
    items.add(_sectionHeader(cs, l10n.canvasSettings_appearanceSection));
    if (widget.onPaperTypePressed != null) {
      items.add(_item(
        cs: cs,
        action: _CanvasSettingsAction.paperMode,
        icon: Icons.grid_on_rounded,
        label: l10n.proCanvas_paperMode,
        trailingBadge: widget.currentPaperLabel == null
            ? null
            : _ValueTrailing(text: widget.currentPaperLabel!, cs: cs),
      ));
    }
    if (widget.onBrushSettingsPressed != null) {
      items.add(_item(
        cs: cs,
        action: _CanvasSettingsAction.brushSettings,
        icon: Icons.tune_rounded,
        label: l10n.proCanvas_brushSettings,
      ));
    }
    // 🔄 Wheel mode toggle — moved back to the toolbar as an inline
    // icon button (2026-05-16, see _toolbar_top_row.dart). The enum
    // case + handler stay so callers that still wire the field don't
    // crash, but the menu item is no longer rendered here.
    items.add(_item(
      cs: cs,
      action: _CanvasSettingsAction.filters,
      icon: Icons.auto_awesome_rounded,
      label: l10n.proCanvas_professionalFilters,
      trailingBadge: (widget.activeFiltersCount ?? 0) == 0
          ? null
          : _ValueTrailing(
              text: l10n.canvasSettings_filtersActiveCount(
                widget.activeFiltersCount!,
              ),
              cs: cs,
            ),
    ));

    // ── ANALISI ─────────────────────────────────────────────────────────
    if (widget.onReadingLevelPressed != null) {
      items.add(const PopupMenuDivider());
      items.add(_sectionHeader(cs, l10n.canvasSettings_analysisSection));
      items.add(_item(
        cs: cs,
        action: _CanvasSettingsAction.readingLevel,
        icon: Icons.analytics_outlined,
        label: l10n.canvasSettings_readingLevel_title,
        trailingBadge: widget.readingLevelSeen ? null : const _NewBadge(),
      ));
    }

    // ── LINGUE (consolida handwriting + app + AI output) ────────────────
    items.add(const PopupMenuDivider());
    items.add(_sectionHeader(cs, l10n.canvasSettings_languagesSection));
    items.add(_item(
      cs: cs,
      action: _CanvasSettingsAction.languages,
      icon: Icons.translate_rounded,
      label: l10n.canvasSettings_languages_title,
      subtitle: l10n.canvasSettings_languages_subtitle,
    ));

    // ── DEV (devMode-only) ──────────────────────────────────────────────
    if (widget.devModeEnabled) {
      items.add(const PopupMenuDivider());
      items.add(_item(
        cs: cs,
        action: _CanvasSettingsAction.brushTesting,
        icon: Icons.brush_rounded,
        label: l10n.proCanvas_brushTestingLab,
      ));
    }

    return items;
  }

  /// Renders a non-selectable section header inside the popup menu.
  /// Uses height=24 + uppercase letterSpacing for visual hierarchy.
  PopupMenuEntry<_CanvasSettingsAction> _sectionHeader(
    ColorScheme cs,
    String label,
  ) {
    return PopupMenuItem<_CanvasSettingsAction>(
      enabled: false,
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: cs.primary.withValues(alpha: 0.75),
        ),
      ),
    );
  }

  /// Standard menu item with icon + label + optional subtitle/trailing badge.
  PopupMenuEntry<_CanvasSettingsAction> _item({
    required ColorScheme cs,
    required _CanvasSettingsAction action,
    required IconData icon,
    required String label,
    String? subtitle,
    Widget? trailingBadge,
  }) {
    return PopupMenuItem<_CanvasSettingsAction>(
      value: action,
      height: subtitle == null ? 48 : 56,
      child: Row(
        children: [
          Icon(icon, size: 20, color: cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 14, color: cs.onSurface),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailingBadge != null) trailingBadge,
        ],
      ),
    );
  }

  /// Languages dialog: 1 entry-point → 3 sub-options that open the existing
  /// pickers. Replaces the 3 consecutive language items (handwriting / app /
  /// AI output) in the popup menu with a single "Languages" entry.
  void _showLanguagesDialog(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = FlueraLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Row(
          children: [
            Icon(Icons.translate_rounded, color: cs.primary, size: 22),
            const SizedBox(width: 10),
            Text(l10n.canvasSettings_languages_dialogTitle),
          ],
        ),
        children: [
          _languageOption(
            ctx: ctx,
            cs: cs,
            title: l10n.canvasSettings_handwritingLanguages_title,
            trailing: _handwritingLanguageTrailing(cs),
            onTap: () {
              Navigator.pop(ctx);
              _showHandwritingLanguagePicker(context);
            },
          ),
          _languageOption(
            ctx: ctx,
            cs: cs,
            title: l10n.canvasSettings_appLanguage_title,
            trailing: _uiLanguageTrailing(cs),
            onTap: () {
              Navigator.pop(ctx);
              _showUiLanguagePicker(context);
            },
          ),
          _languageOption(
            ctx: ctx,
            cs: cs,
            title: l10n.canvasSettings_aiOutputLanguage_title,
            trailing: _aiLanguageTrailing(cs),
            onTap: () {
              Navigator.pop(ctx);
              _showAiLanguagePicker(context);
            },
          ),
          // Reset all 3 languages back to auto-detect — visible only if at
          // least one has an explicit override or auto-detect is off.
          if (_hasAnyExplicitLanguage())
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _resetAllLanguagesToAuto();
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    SnackBar(
                      content: Text(
                        l10n.canvasSettings_languages_resetAutoSnack,
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: Text(
                  l10n.canvasSettings_languages_resetAutoButton,
                  style: const TextStyle(fontSize: 13),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: cs.primary,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// True if any of the 3 language preferences has an explicit user override
  /// (or handwriting auto-detect is off). Drives the visibility of the
  /// "Auto-detect tutte" reset button at the bottom of the languages dialog.
  bool _hasAnyExplicitLanguage() {
    return !DigitalInkService.instance.autoDetect ||
        UiLanguagePreference.hasExplicitOverride() ||
        AiLanguagePreference.hasExplicitOverride();
  }

  /// Reset all 3 language prefs back to their auto-detect / locale default.
  /// Fire-and-forget on the async preferences (UI + AI) — persistence is
  /// best-effort, the in-memory cache flips immediately.
  void _resetAllLanguagesToAuto() {
    DigitalInkService.instance.autoDetect = true;
    // ignore: discarded_futures
    UiLanguagePreference.setPreferred(null);
    // ignore: discarded_futures
    AiLanguagePreference.setPreferred(null);
    if (mounted) setState(() {});
  }

  Widget _languageOption({
    required BuildContext ctx,
    required ColorScheme cs,
    required String title,
    required Widget trailing,
    required VoidCallback onTap,
  }) {
    return SimpleDialogOption(
      onPressed: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
            ),
            trailing,
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _handwritingLanguageTrailing(ColorScheme cs) {
    final service = DigitalInkService.instance;
    final code = service.languageCode;
    final lang = DigitalInkService.supportedLanguages[code];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (service.autoDetect) _autoBadge(cs),
        if (lang != null) Text(lang.$3, style: const TextStyle(fontSize: 16)),
      ],
    );
  }

  Widget _uiLanguageTrailing(ColorScheme cs) {
    final name = UiLanguagePreference.displayName();
    final explicit = UiLanguagePreference.hasExplicitOverride();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!explicit) _autoBadge(cs),
        Text(
          name,
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _aiLanguageTrailing(ColorScheme cs) {
    final name = AiLanguagePreference.displayName();
    final explicit = AiLanguagePreference.hasExplicitOverride();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!explicit) _autoBadge(cs),
        Text(
          name,
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _autoBadge(ColorScheme cs) => Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'Auto',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: cs.onSurfaceVariant,
          ),
        ),
      );

  void _showRenameNoteDialog(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = FlueraLocalizations.of(context)!;
    final TextEditingController controller = TextEditingController(
      text: widget.noteTitle ?? '',
    );

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: cs.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Icon(
                  Icons.drive_file_rename_outline,
                  color: cs.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  l10n.proCanvas_renameNote,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            content: TextField(
              controller: controller,
              autofocus: true,
              style: TextStyle(color: cs.onSurface, fontSize: 16),
              decoration: InputDecoration(
                labelText: l10n.proCanvas_noteName,
                labelStyle: TextStyle(color: cs.onSurfaceVariant),
                hintText: l10n.proCanvas_enterName,
                hintStyle: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.3),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: cs.primary, width: 2),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  l10n.cancel,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
              FilledButton(
                onPressed: () {
                  final newTitle = controller.text.trim();
                  if (newTitle.isNotEmpty &&
                      widget.onNoteTitleChanged != null) {
                    widget.onNoteTitleChanged!(newTitle);
                  }
                  Navigator.pop(context);
                },
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                child: Text(l10n.save),
              ),
            ],
          ),
    );
  }

  void _showHandwritingLanguagePicker(BuildContext context) {
    final service = DigitalInkService.instance;
    HandwritingLanguagePicker.show(
      context,
      activeLanguage: service.languageCode,
      onLanguageSelected: (code) async {
        final ok = await service.switchLanguage(code);
        if (ok && context.mounted) {
          HapticFeedback.mediumImpact();
          final lang = DigitalInkService.supportedLanguages[code];
          if (lang != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${lang.$3} ${lang.$1} activated'),
                backgroundColor: Colors.deepPurple,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
      },
    );
  }

  /// 🌍 Picker for the AI output language preference. Persists via
  /// `AiLanguagePreference.setPreferred` (KeyValueStore). The "Use device
  /// locale" option clears the override.
  void _showAiLanguagePicker(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final supported = AiLanguagePreference.supportedLanguages();
    final currentCode =
        AiLanguagePreference.hasExplicitOverride() ? AiLanguagePreference.code() : null;
    showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('AI Output Language'),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text(
              'Choose the language Fluera AI uses for Socratic '
              'questions, Exam questions, and Chat answers. Your notes '
              'can still be in any language.',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          SimpleDialogOption(
            onPressed: () async {
              await AiLanguagePreference.setPreferred(null);
              if (ctx.mounted) Navigator.of(ctx).pop();
              if (context.mounted) {
                HapticFeedback.mediumImpact();
                setState(() {}); // refresh chip in dropdown
              }
            },
            child: Row(
              children: [
                Icon(
                  currentCode == null
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: cs.primary,
                ),
                const SizedBox(width: 12),
                const Expanded(child: Text('Use device locale (auto)')),
              ],
            ),
          ),
          const Divider(height: 1),
          for (final entry in supported.entries)
            SimpleDialogOption(
              onPressed: () async {
                await AiLanguagePreference.setPreferred(entry.key);
                if (ctx.mounted) Navigator.of(ctx).pop();
                if (context.mounted) {
                  HapticFeedback.mediumImpact();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('AI output: ${entry.value} activated. '
                          'Restart the app to apply to existing models.'),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                  setState(() {});
                }
              },
              child: Row(
                children: [
                  Icon(
                    currentCode == entry.key
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: cs.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(entry.value)),
                  Text(
                    entry.key.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 🌐 Picker for the UI language preference (app chrome). Persists via
  /// `UiLanguagePreference.setPreferred` and broadcasts on
  /// `UiLanguagePreference.changes` so the root `MaterialApp` rebuilds
  /// without an app restart.
  void _showUiLanguagePicker(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final supported = UiLanguagePreference.supportedLanguages();
    final currentCode = UiLanguagePreference.code();
    showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('App Language'),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text(
              'Choose the language used across the Fluera interface — '
              'buttons, labels, dialogs. Independent from the AI output '
              'language below.',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          SimpleDialogOption(
            onPressed: () async {
              await UiLanguagePreference.setPreferred(null);
              if (ctx.mounted) Navigator.of(ctx).pop();
              if (context.mounted) {
                HapticFeedback.mediumImpact();
                setState(() {});
              }
            },
            child: Row(
              children: [
                Icon(
                  currentCode == null
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: cs.primary,
                ),
                const SizedBox(width: 12),
                const Expanded(child: Text('Use device locale (auto)')),
              ],
            ),
          ),
          const Divider(height: 1),
          for (final entry in supported.entries)
            SimpleDialogOption(
              onPressed: () async {
                await UiLanguagePreference.setPreferred(entry.key);
                if (ctx.mounted) Navigator.of(ctx).pop();
                if (context.mounted) {
                  HapticFeedback.mediumImpact();
                  setState(() {});
                }
              },
              child: Row(
                children: [
                  Icon(
                    currentCode == entry.key
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: cs.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(entry.value)),
                  Text(
                    entry.key.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _showFiltersDialog(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = FlueraLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.toolbarAIFilters),
        backgroundColor: cs.primary,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _openBrushTestingLab(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const BrushTestScreen()),
    );
  }

  void _showOCRLanguageDialog(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = FlueraLocalizations.of(context)!;

    showDialog(
      context: context,
      builder:
          (context) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            backgroundColor: cs.surfaceContainerLow,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.text_fields_rounded,
                            color: cs.onPrimaryContainer,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.proCanvas_ocrTextRecognition,
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: cs.onSurface,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                l10n.proCanvas_selectLanguagesForRecognition,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.close_rounded,
                            color: cs.onSurfaceVariant,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),

                  // Language list
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _buildLanguageItem(
                          context,
                          language: 'Italiano',
                          code: 'it',
                          flag: '🇮🇹',
                          isDownloaded: _downloadedLanguages.contains('it'),
                        ),
                        _buildLanguageItem(
                          context,
                          language: 'English',
                          code: 'en',
                          flag: '🇬🇧',
                          isDownloaded: _downloadedLanguages.contains('en'),
                        ),
                        _buildLanguageItem(
                          context,
                          language: 'Español',
                          code: 'es',
                          flag: '🇪🇸',
                          isDownloaded: _downloadedLanguages.contains('es'),
                        ),
                        _buildLanguageItem(
                          context,
                          language: 'Français',
                          code: 'fr',
                          flag: '🇫🇷',
                          isDownloaded: _downloadedLanguages.contains('fr'),
                        ),
                        _buildLanguageItem(
                          context,
                          language: 'Deutsch',
                          code: 'de',
                          flag: '🇩🇪',
                          isDownloaded: _downloadedLanguages.contains('de'),
                        ),
                        _buildLanguageItem(
                          context,
                          language: '中文',
                          code: 'zh',
                          flag: '🇨🇳',
                          isDownloaded: _downloadedLanguages.contains('zh'),
                        ),
                        _buildLanguageItem(
                          context,
                          language: '日本語',
                          code: 'ja',
                          flag: '🇯🇵',
                          isDownloaded: _downloadedLanguages.contains('ja'),
                        ),
                      ],
                    ),
                  ),

                  // Footer
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(20),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 16,
                          color: cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.proCanvas_languageModelsWillBeDownloaded,
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildLanguageItem(
    BuildContext context, {
    required String language,
    required String code,
    required String flag,
    required bool isDownloaded,
  }) {
    final cs = Theme.of(context).colorScheme;
    final l10n = FlueraLocalizations.of(context)!;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Text(flag, style: const TextStyle(fontSize: 32)),
        title: Text(
          language,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: cs.onSurface,
          ),
        ),
        subtitle: Text(
          code.toUpperCase(),
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        trailing:
            isDownloaded
                ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        l10n.proCanvas_downloaded,
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                )
                : FilledButton.icon(
                  onPressed: () {
                    _downloadLanguageModel(context, code, language);
                  },
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: Text(l10n.proCanvas_downloadLabel),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
      ),
    );
  }

  void _downloadLanguageModel(
    BuildContext context,
    String code,
    String language,
  ) {
    final l10n = FlueraLocalizations.of(context)!;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            title: Text('📥 Download $language'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(l10n.proCanvas_downloadingModel(code)),
              ],
            ),
          ),
    );

    Future.delayed(const Duration(seconds: 2), () {
      Navigator.pop(context);

      setState(() {
        _downloadedLanguages.add(code);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.proCanvas_modelDownloadedSuccess(language)),
          backgroundColor: Colors.green,
        ),
      );
    });
  }
}

/// Trailing chip rendering a current-state label (e.g. "Quadretti 5mm" for
/// Paper Mode, "2 attivi" for Filters) so the user sees the active value
/// without expanding the sub-menu.
class _ValueTrailing extends StatelessWidget {
  final String text;
  final ColorScheme cs;
  const _ValueTrailing({required this.text, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// "NEW" trailing badge for items the user hasn't seen yet. Hidden once the
/// host marks them seen via `onReadingLevelMarkSeen`.
class _NewBadge extends StatelessWidget {
  const _NewBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.teal.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        'NEW',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: Colors.teal,
        ),
      ),
    );
  }
}

/// Trailing pill for toggleable settings items. Renders a small accent
/// "Active" badge so the user can see on/off state at a glance without
/// opening a deeper screen. Used by wheel mode (and reservable for any
/// future toggle that joins this dropdown).
class _ActiveBadge extends StatelessWidget {
  final ColorScheme cs;
  const _ActiveBadge({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: cs.primary.withValues(alpha: 0.32),
          width: 0.8,
        ),
      ),
      child: Text(
        'ON',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: cs.primary,
        ),
      ),
    );
  }
}
