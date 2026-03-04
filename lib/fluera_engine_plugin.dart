/// Plugin registration for Fluera Engine on desktop platforms.
///
/// This class is referenced by `pubspec.yaml` via `dartPluginClass` and is
/// called automatically by Flutter's plugin registrant during startup.
class FlueraEnginePlugin {
  /// Called by the generated plugin registrant. Fluera Engine is a pure-Dart
  /// plugin so no native registration is needed — this is intentionally a
  /// no-op.
  static void registerWith() {
    // No native platform channel registration required.
    // All Fluera Engine functionality is implemented in Dart.
  }
}
