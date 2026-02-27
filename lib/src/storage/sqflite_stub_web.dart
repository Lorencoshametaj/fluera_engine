// Stub for web — provides no-op sqflite FFI types.
// On native platforms, the real sqflite_common_ffi is used via conditional import.

// Re-export sqflite_common types so the adapter sees Database, etc.
export 'package:sqflite_common/sqflite.dart';

/// No-op FFI initialization for web.
void sqfliteFfiInit() {
  // No-op on web — SQLite FFI is not available.
}

/// Stub factory — on web this throws because SQLite FFI is unavailable.
/// The adapter guards this with kIsWeb before calling.
dynamic get databaseFactoryFfi {
  throw UnsupportedError('sqflite FFI is not supported on web');
}
