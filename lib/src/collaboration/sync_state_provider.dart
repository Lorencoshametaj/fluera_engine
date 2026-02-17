import 'package:flutter/foundation.dart';

/// Sync state for the canvas — used by toolbar sync indicator.
///
/// The SDK defines the states; the app provides the actual sync implementation.
enum NebulaSyncState { idle, uploading, downloading, error }

/// 🔄 Abstract sync state provider for the toolbar.
///
/// The app injects a concrete implementation connected to its cloud sync.
/// If not provided, the toolbar hides the sync indicator.
///
/// ```dart
/// class MyCloudSyncProvider extends NebulaSyncStateProvider {
///   MyCloudSyncProvider() {
///     // Listen to your cloud sync service
///     cloudSync.syncState.addListener(() {
///       state.value = _mapToNebula(cloudSync.syncState.value);
///     });
///   }
/// }
/// ```
class NebulaSyncStateProvider {
  /// Static instance — set by the app at startup
  static NebulaSyncStateProvider? _instance;
  static NebulaSyncStateProvider? get instance => _instance;
  static set instance(NebulaSyncStateProvider? value) => _instance = value;

  final ValueNotifier<NebulaSyncState> state = ValueNotifier(
    NebulaSyncState.idle,
  );

  final ValueNotifier<String?> statusMessage = ValueNotifier(null);

  void dispose() {
    state.dispose();
    statusMessage.dispose();
  }
}
