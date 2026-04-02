/// 🌍 Fluera Engine SDK Localization — Public API.
///
/// This file re-exports the generated localization classes.
/// All SDK code should import from here (never from `generated/` directly).
///
/// The generated classes come from the ARB source files in `arb/`.
/// To regenerate after editing ARB files, run:
///
/// ```sh
/// ./tool/gen_l10n.sh
/// ```
///
/// ## Quick Start (host app)
///
/// **Zero config (automatic):**
/// ```dart
/// // Just add the delegate. Falls back to EN if device language is unsupported.
/// MaterialApp(
///   localizationsDelegates: [
///     FlueraLocalizations.delegate,
///     GlobalMaterialLocalizations.delegate,
///     GlobalWidgetsLocalizations.delegate,
///   ],
///   supportedLocales: FlueraLocalizations.supportedLocales,
/// )
/// ```
///
/// **Force a language:**
/// ```dart
/// FlueraLocalizations.override = FlueraLocalizationsIt();
/// ```
///
/// **Custom override (extend any locale):**
/// ```dart
/// class MyLoc extends FlueraLocalizationsIt {
///   MyLoc() : super();
///   @override String get proCanvas_pen => 'Stilo';
/// }
/// FlueraLocalizations.override = MyLoc();
/// ```
library;

export 'generated/fluera_localizations.g.dart';
export 'generated/fluera_localizations_en.g.dart';
export 'generated/fluera_localizations_it.g.dart';
