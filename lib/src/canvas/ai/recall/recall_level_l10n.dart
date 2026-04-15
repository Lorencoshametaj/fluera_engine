// ============================================================================
// 🌐 RECALL LEVEL L10N — Localized labels for RecallLevel enum
//
// Extension to bridge the pure data model (RecallLevel) with the
// localization layer (FlueraLocalizations) without coupling the model
// to Flutter's BuildContext.
// ============================================================================

import '../../../l10n/generated/fluera_localizations.g.dart';
import 'recall_session_model.dart';

/// Resolves [RecallLevel.label] to the correct localized string.
///
/// Usage from a widget with BuildContext:
/// ```dart
/// final l10n = FlueraLocalizations.of(context)!;
/// final label = level.localizedLabel(l10n);
/// ```
extension RecallLevelL10n on RecallLevel {
  /// Returns the localized human-readable label for this recall level.
  String localizedLabel(FlueraLocalizations l10n) {
    switch (this) {
      case RecallLevel.peeked:
        return l10n.recall_levelPeeked;
      case RecallLevel.missed:
        return l10n.recall_levelMissed;
      case RecallLevel.tipOfTongue:
        return l10n.recall_levelTipOfTongue;
      case RecallLevel.partial:
        return l10n.recall_levelPartial;
      case RecallLevel.substantial:
        return l10n.recall_levelSubstantial;
      case RecallLevel.perfect:
        return l10n.recall_levelPerfect;
    }
  }
}
